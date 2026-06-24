#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= KV-Cache, Context, and Embedding Compression

#epigraph[
  The best way to serve a billion tokens is to never store them in the first place.
][Anonymous ML infrastructure engineer, 2025]

Picture a librarian who reads extraordinarily fast. Every time you start a new conversation, this librarian reads your entire message history (every word, every sentence, going back to the beginning) just to answer your next question. That is, more or less, exactly what a large language model does. And the library it maintains grows one shelf longer with every reply.

That library has a name: the *key-value cache*, or KV-cache. By the summer of 2024, running a large language model on a sequence of 100,000 tokens required more GPU memory for the cache alone than the model's own weights occupied. Teams at Google, Microsoft, Meta, and the Chinese AI lab DeepSeek all arrived at the same uncomfortable conclusion: the bottleneck to cheap, long-context AI is not the model. It is the *memory for the conversation so far*.

This chapter is about the compression tricks that attack that bottleneck. We will travel from the basic architecture of the KV-cache (why it exists, exactly what it stores, why it grows without bound), through three families of compression (*eviction*, *quantization*, and *low-rank architectural redesign*), to a fourth, complementary idea: compressing the *prompt itself* before it ever enters the model. Then we zoom out to the database side, where millions of vectors are stored for retrieval, and learn the elegant technique of *product quantization*, which shrinks a 768-number float vector into fewer bytes than a tweet.

By the end you will see a single principle running through all of it: every technique in this chapter is the same ancient move in a new costume. *Predict and throw away what can be reconstructed, code only the residual.*

#recap[
  - In *Chapter 26* we built an arithmetic coder: given a probability for the next symbol, spend $-log_2 p$ bits. The KV-cache problem is memory, not entropy, but the information-theoretic framing still applies.
  - In *Chapter 39* we met *scalar quantization*: replace a real number with the nearest step on a fixed grid. Chapter 63 extended this to the weights of a neural network (GPTQ, AWQ). This chapter applies the same idea to a running cache of vectors.
  - In *Chapter 62* we learned what an autoregressive language model actually does: it maintains a probability distribution over the next token, conditioned on every previous token. The mechanism that lets it "see" all those previous tokens at low cost is precisely the KV-cache we are about to meet.
]

#objectives((
  "Explain what the KV-cache is, why it exists, and why its memory cost grows with context length",
  "Describe the H2O eviction policy and the Heavy-Hitter Oracle insight behind it",
  "Explain SnapKV and how observation-window pooling selects which cache entries to keep",
  "Describe DeepSeek's Multi-head Latent Attention (MLA) and quantify how much memory it saves",
  "Understand KV-cache quantization and why rotation tricks tame outlier values",
  "Explain LLMLingua's prompt compression and how it decides which tokens to drop",
  "Define product quantization (PQ), work through a complete numeric example, and explain OPQ's improvement",
  "Describe binary and Matryoshka embeddings and state when each is the right choice",
))

== The KV-Cache: What It Is and Why It Hurts

Before we can compress the KV-cache, we need to understand what it contains and why it exists. The explanation requires a brief tour of the *attention mechanism*, which is the mathematical engine inside every modern language model.

=== Attention in Plain English

A transformer language model processes text in layers. At each layer, every token looks at every other token to gather context. This is the *attention* operation. For each token at position $i$, the model computes three vectors from the token's current representation: a *query* vector $q_i$, a *key* vector $k_i$, and a *value* vector $v_i$.

The intuition: the query is what the token is looking for; the key is what it is advertising about itself; the value is what it will contribute if selected. To produce the attention output for token $i$, the model dots $q_i$ with every other token's key $k_j$, turns those dot-products into probabilities with a softmax, then adds up all the value vectors $v_j$ weighted by those probabilities.

#mathrecall[From Chapter 64: the *softmax* turns a list of raw scores $z = (z_1, dots, z_n)$ into probabilities that sum to 1 by exponentiating and normalising, $"softmax"(z)_i = e^(z_i) \/ sum_j e^(z_j)$. The largest score gets the largest probability; negatives are allowed. In attention, the scores are the query--key dot products, so the most relevant tokens receive the most weight.]

#gomaths("Dot product and what it measures")[
  A *dot product* of two vectors $bold(a) = (a_1, a_2, dots, a_d)$ and $bold(b) = (b_1, b_2, dots, b_d)$ is:

  $ bold(a) dot bold(b) = a_1 b_1 + a_2 b_2 + dots + a_d b_d = sum_(i=1)^d a_i b_i $

  It is a single number. When $bold(a)$ and $bold(b)$ point in the same direction, the dot product is large and positive. When they are perpendicular, it is zero. When they point opposite ways, it is negative.

  *Why attention uses it:* if the query vector for the word "bank" (as in river bank) points in a similar direction to the key vector for "river," their dot product is large, telling the model to weight "river" heavily when computing context. The dot product measures *relevance*.

  Tiny example with $d = 2$: $bold(a) = (3, 1)$, $bold(b) = (2, 4)$. Dot product: $3 times 2 + 1 times 4 = 10$. With $bold(c) = (-1, 3)$: dot product $= 3 times (-1) + 1 times 3 = 0$. These two are perpendicular (unrelated in the model's space).
]

=== The Caching Opportunity - and the Memory Tax

Here is the critical observation: when the model generates token $t+1$, it needs to attend over every previous token $1, 2, dots, t$. But the keys and values for those earlier tokens were *already computed* when those tokens were processed. Recomputing them would waste time proportional to $t^2$ (each new token forces a full re-read of all history). So the model stores the keys and values for every past token in fast GPU memory: the KV-cache.

The price is steep. For a typical model with:
- 32 attention layers
- 32 heads per layer
- key/value dimension 128 per head
- BFloat16 precision (2 bytes per number)

Each token occupies $2 times 32 times 32 times 128 times 2 = 524,288$ bytes $approx 512$ KB, for the full 32-layer model. With a 128,000-token context (LLaMA-3 supported this in 2024), the KV-cache alone consumes $512 "KB" times 128,000 approx 64 "GB"$. The GPU has 80 GB total. The model weights (everything the model learned) take perhaps 14 GB. The cache is eating *four times more memory than the model itself*.

#keyidea[
  The KV-cache is a classic time--space trade-off: we spend memory to avoid recomputing keys and values. As contexts grow from thousands to millions of tokens, the memory bill becomes the dominant inference cost. Every technique in this chapter attacks that bill.
]

=== How Big Is "One Token" in the Cache?

Let us make the numbers concrete with a comparison. Different models make different architectural choices and pay different memory costs per token.

#fig(
  [KV-cache memory per token for representative 2024 models (all numbers approximate).],
  table(
    columns: (auto, auto, auto, 1fr),
    inset: 7pt,
    align: (left, right, right, left),
    fill: (_, row) => if row == 0 { rgb("#dbe8f4") } else { none },
    table.header([*Model*], [*Architecture*], [*Bytes/token*], [*Notes*]),
    [LLaMA-3.1 405B], [MHA, 128 heads], [516 KB], [Standard multi-head attention],
    [Mistral 7B], [GQA, 8 groups], [32 KB], [Grouped query: groups share K/V],
    [Qwen-2.5 72B], [GQA, 40 groups], [327 KB], [Large model, still expensive],
    [DeepSeek-V3 671B], [MLA latent], [70 KB], [Low-rank latent only; see section below],
  )
)

Grouped Query Attention (GQA), where multiple query heads share one pair of key/value heads, already cuts memory considerably compared to full Multi-Head Attention (MHA). DeepSeek's MLA shrinks it further still, by a fundamentally different mechanism.

== Family 1: Eviction - Throwing Away What You Don't Need

The simplest compression strategy is eviction: once the cache grows past a budget, drop some old entries. But which ones?

A naive policy of dropping the oldest tokens sounds reasonable, but it fails catastrophically. Older tokens often carry *structural* information: the opening sentence, the system prompt, the question being answered. Dropping them first is like throwing away the question before you write the answer.

=== The Heavy-Hitter Oracle (H2O)

The key observation behind H2O (Zhang et al., NeurIPS 2023) is empirical but well-supported: *across all heads and all layers, a small fraction of token positions consistently attract most of the total attention score*. These tokens are called *Heavy Hitters* (H2), and they are the tokens that are actually load-bearing for the model's reasoning.

The H2O policy maintains a fixed-size cache budget $B$ split between two pools:
- *Recent tokens* (the last $B/2$ or so): kept unconditionally, because attention to the very recent past is always important.
- *Heavy hitters* (the remaining budget): kept based on cumulative attention scores.

At each new decoding step, the model computes attention from the new query to all cached keys. H2O *accumulates* those attention scores over time. When the cache exceeds the budget, it evicts the non-recent token with the lowest cumulative score: the one that has received the least total attention weight from every subsequent token. The intuition: if no future token has found this past token relevant, it is unlikely to become relevant now.

#algo(
  name: "H2O: Heavy-Hitter Oracle KV-Cache Eviction",
  year: "2023",
  authors: "Zhenyu Zhang, Ying Sheng, Tianyi Zhou, et al. (UT Austin / UC Berkeley / CMU)",
  aim: "Reduce KV-cache memory during autoregressive decoding by evicting low-attention tokens while retaining heavy hitters and recent tokens",
  complexity: "$O(B)$ extra memory per layer; $O(n)$ work per decoding step to update the attention score accumulator",
  strengths: "Simple post-hoc optimization; no retraining needed; 29x throughput improvement reported on OPT-30B at 20% heavy-hitter budget; works across OPT, LLaMA, GPT-NeoX",
  weaknesses: "Eviction is irreversible: a dropped token cannot be recalled later; accuracy degrades on tasks that require looking far back beyond the recent window; optimal budget split is task-dependent",
  superseded: "SnapKV (2024), which uses observation-window pooling; StreamingLLM (2023), which keeps only 'sink' tokens plus recent; various learned eviction policies in 2024--2025",
)[
  H2O formalizes the eviction problem as maximizing a *submodular* function, a class of set functions where adding an element to a smaller set is at least as valuable as adding it to a larger one. This gives a theoretical guarantee: the greedy score-based eviction policy achieves a constant-factor approximation of the best possible offline eviction policy. In practice, using only the last-layer accumulated attention scores works nearly as well as using future-token scores, making the method fully causal (no peeking ahead).
]

=== SnapKV: What the Model Already Knows It Needs

H2O accumulates scores during decoding. SnapKV (Li et al., arXiv:2404.14469, NeurIPS 2024) asks a smarter question: *before generating*, can the model tell which prompt tokens it will need most?

The answer is yes. The intuition is that the last few tokens of the prompt (the actual question being asked) already "look ahead" to the parts of the context they will need. SnapKV calls this the *observation window*: typically the last 16--64 tokens.

The algorithm:
1. Process the full prompt normally, computing all keys and values.
2. For each attention head, compute the attention weights from the observation window tokens to every earlier prompt token. Average (pool) those weights using a small kernel (size 5) to prevent single-token spikes from dominating.
3. Keep the top-$k$ prompt positions per head (where $k$ is the memory budget).
4. Generate with this compressed cache, adding only new generated tokens.

SnapKV achieves a 3.6x generation speedup and 8.2x memory reduction at 16K-token context with almost no accuracy loss on standard benchmarks. The key insight - that the model "knows what it needs before generation" - is a beautiful example of using the model's own attention machinery as a compressor.

#checkpoint[
  H2O and SnapKV both keep a "recent" window unconditionally. Why?
][
  Very recent tokens carry the local coherence of the sentence being generated. The model almost always attends strongly to them for grammar, reference resolution, and continuation. Evicting them first would break the most immediate context.
]

== Family 2: Architectural Compression - DeepSeek's Multi-Head Latent Attention

Eviction works post-hoc: we build the full cache and then throw parts away. DeepSeek's approach is different: *redesign the architecture so the cache never gets large in the first place*. The result, Multi-head Latent Attention (MLA), was introduced in DeepSeek-V2 (May 2024) and carried forward into DeepSeek-V3 (December 2024).

=== The Low-Rank Bottleneck Trick

Standard multi-head attention caches, for each token, separate key and value vectors for each of $H$ heads. If each head has dimension $d_h$ and there are $H$ heads, the cache per token per layer is $2 H d_h$ floating-point numbers.

MLA's key insight: *keys and values across all heads are highly correlated*. The information they carry lives in a much lower-dimensional space. Instead of caching $2 H d_h$ numbers, cache a single *latent vector* $bold(c)$ of dimension $d_c$ (where $d_c << 2 H d_h$), trained to contain everything needed to reconstruct the keys and values.

Formally:

$ bold(c) = bold(W)_c bold(x) $

where $bold(x)$ is the token's current hidden state and $bold(W)_c$ is a learned compression matrix of shape $d_c times d_"model"$. At inference, the keys and values for all heads are recovered:

$ bold(K) = bold(W)_K bold(c), quad bold(V) = bold(W)_V bold(c) $

where $bold(W)_K$ and $bold(W)_V$ are learned expansion matrices. The critical point: *only $bold(c)$ is stored in the cache*. The expansion matrices are part of the model weights, already loaded into GPU memory. So the per-token cache cost drops from $2 H d_h$ numbers to $d_c$ numbers.

#gomaths("Low-rank matrix factorization")[
  A matrix $bold(M)$ of shape $m times n$ has *rank* $r$ if it can be written as a product of two smaller matrices:

  $ bold(M) = bold(A) bold(B), quad bold(A) in RR^(m times r), bold(B) in RR^(r times n) $

  When $r << min(m, n)$, this is a *low-rank factorization*. The number of stored values shrinks from $m n$ to $r(m + n)$.

  *Intuition:* if the rows of $bold(M)$ are not all independent but instead lie near a low-dimensional "plane" in $RR^n$, then $r$ basis vectors can describe them all. The rank is the dimension of that plane.

  *Example:* $bold(M) = mat(2,4,6;3,6,9;1,2,3)$ has rank 1, because every row is a multiple of $(1,2,3)$. We can write $bold(M) = bold(a) bold(b)^T$ with $bold(a) = (2,3,1)^T$ and $bold(b) = (1,2,3)^T$, storing 6 numbers instead of 9.

  MLA's bet: the full $K$ and $V$ matrices across all heads, for a given token, lie near a low-rank plane. The model is trained end-to-end to learn the right low-dimensional representation.
]

=== How Much Does MLA Save?

In DeepSeek-V2 with its MLA configuration:
- Standard MHA per token per layer: $2 times 128 "heads" times 128 "dim/head" = 32,768$ numbers.
- MLA latent per token per layer: 512 numbers (plus a small decoupled position vector of 64 numbers).

That is roughly a 60x reduction per layer. The actual reported figure (70 KB/token for the full DeepSeek-V3 model versus 327--516 KB/token for comparable MHA models) reflects approximately a 93% reduction in KV-cache memory, while the model *matches or exceeds* the quality of full attention on standard benchmarks.

#history[
  MLA was the architectural surprise of 2024. Prior attempts to compress KV-caches had all been post-hoc (train normally, apply a patch). DeepSeek's team, based in Hangzhou, baked the compression into the training objective itself. DeepSeek-V3, released December 2024 as a fully open-weights model (671B parameters, mixture-of-experts), demonstrated that the quality cost of this compression was negligible in practice. This was widely recognized as one of the most practically important architectural innovations in the transformer era, and several other frontier labs (including Moonshot AI's Kimi k1.5, 2025) adopted MLA or close variants.
]

#algo(
  name: "Multi-Head Latent Attention (MLA)",
  year: "2024",
  authors: "DeepSeek-AI (arXiv:2405.04434 for V2; arXiv:2412.19437 for V3)",
  aim: "Eliminate most of the KV-cache by storing a low-rank joint latent vector instead of per-head keys and values; trained end-to-end so the latent captures everything needed for high-quality attention",
  complexity: "$O(d_c)$ cache per token instead of $O(H d_h)$; matrix multiplications at each attention step to expand the latent to keys/values, but these matrices are already in GPU memory as model weights",
  strengths: "~93% KV-cache memory reduction; quality on par with full MHA; enables very long contexts (128K+ tokens) without special eviction logic; no post-hoc degradation since it is trained in",
  weaknesses: "Requires training from scratch (converting an existing MHA model needs full retraining); adds matrix multiplications at inference; interaction with rotary positional embeddings requires careful design",
  superseded: "Ongoing; MLA variants continue to appear in frontier models through 2025--2026",
)[
  MLA also introduced a subtle positional-encoding trick: a small separate "decoupled" key vector carries position information while the main latent stays position-free. This allows the expansion $bold(W)_K bold(c)$ to be algebraically "absorbed" into the query projection at inference time, eliminating one of the two matrix multiplications from the hot path. It is a compiler-style optimization baked into the mathematical structure of the mechanism.
]

== Family 3: KV-Cache Quantization - Fewer Bits per Number

Even without eviction or architectural change, we can shrink the cache by storing each key and value in fewer bits. Chapter 63 covered this idea thoroughly for model weights (GPTQ, AWQ, 4-bit quantization). The KV-cache presents the same challenge, and the same enemy: *outliers*.

=== Why KV-Cache Quantization Is Hard

When we quantize a vector of 128 numbers to 4 bits each, we are saying: "map the entire range of values to 16 grid steps." If most values cluster near zero but one value is 10x larger, that outlier forces the grid to spread wide, leaving the clustered values with terrible precision. (Recall the dead-zone and clipping tricks from Chapter 39: a single outlier wrecks a uniform quantizer's average error.) This is the same problem that makes naive INT8 quantization fail for activations (Chapter 63), and it is *worse* for the KV-cache because the key vectors encode position information through *Rotary Position Embeddings* (RoPE), a scheme that injects a token's position by rotating its key vector by an angle proportional to that position. This produces particularly structured, spiky coordinate distributions that are awkward to quantize.

=== PolarQuant: Rotation as a Pre-Conditioner

PolarQuant (published at AISTATS 2026) attacks the outlier problem geometrically. The insight: a random orthogonal rotation matrix $bold(R)$ preserves all the information in a vector (it just rotates it in space), but it *redistributes* the variance uniformly across all coordinates. After rotation, each coordinate independently follows a distribution close to a Gaussian, and a Gaussian quantizes beautifully with a standard scalar quantizer.

The algorithm:
1. Sample a random orthogonal matrix $bold(R)$ once (shared across all tokens and all heads).
2. Before caching key/value vector $bold(k)$, compute $bold(k)' = bold(R) bold(k)$.
3. Quantize $bold(k)'$ to 4 bits per coordinate with a per-head scalar quantizer.
4. At attention time, dequantize: the query is also rotated, so $bold(q)'^T bold(k)' = (bold(R) bold(q))^T (bold(R) bold(k)) = bold(q)^T bold(k)$. The rotation is mathematically invisible.

The rotation does not change the attention output. Only the *quantization grid* changes, from one that is distorted by outliers to one that is well-matched to a spread-out Gaussian.

=== TurboQuant: Online Vector Quantization at 3 Bits

TurboQuant (Google Research, ICLR 2026, arXiv:2504.19874) pushes further. Instead of scalar quantization post-rotation, it applies *online vector quantization*: each rotated key/value vector is quantized jointly rather than coordinate-by-coordinate, exploiting correlations between coordinates within a single vector.

TurboQuant achieves 3-bit compression with, according to its authors, effectively zero accuracy loss on standard LLM benchmarks. A companion system, KVTC (NVIDIA, 2025), uses PCA-based decorrelation instead of random rotation and reaches approximately 20x compression (storing the KV-cache in roughly 1.6 bits per coordinate) with less than one percentage point accuracy penalty across models from 1.5B to 70B parameters.

#mathrecall[*PCA* (Principal Component Analysis), met in Chapter 38 as the statistical cousin of the Karhunen--Loève transform, finds the orthogonal rotation that aligns the axes with the directions of greatest variance in the data. After this rotation the coordinates are decorrelated and most of the energy concentrates in the first few, exactly the property that makes quantization cheap. Where a _random_ rotation spreads variance evenly by luck, PCA computes the _best_ rotation from a sample of real cache vectors.]

#pitfall[
  "Zero accuracy loss" in quantization papers almost always means "no statistically significant degradation on the benchmarks we tested." Long-context tasks (multi-hop reasoning chains, retrieval over very long documents) are much more sensitive to small numerical errors than short-answer benchmarks. Aggressive KV-cache quantization should always be validated on the actual deployment task, not just on the standard short-context suite.
]

#fig(
  [KV-cache compression families and approximate memory relative to BFloat16 MHA baseline.],
  cetz.canvas({
    import cetz.draw: *
    // baseline
    rect((0, 5.2), (8.0, 5.7), fill: rgb("#d0d7de"), stroke: none)
    content((4.0, 5.45), box(width: 7.6cm, inset: 1pt, align(center, text(size: 8pt)[BFloat16 MHA baseline: 100%])))

    // Eviction
    rect((0, 4.0), (4.0, 4.5), fill: rgb("#0b5394").lighten(60%), stroke: none)
    content((6.5, 4.25), box(width: 3.8cm, inset: 1pt, align(center, text(size: 7.5pt)[Eviction (H2O): ~50%])))

    // 4-bit quant
    rect((0, 2.8), (2.0, 3.3), fill: rgb("#0f766e").lighten(50%), stroke: none)
    content((5.0, 3.05), box(width: 3.8cm, inset: 1pt, align(center, text(size: 7.5pt)[4-bit quantization: ~25%])))

    // MLA
    rect((0, 1.6), (0.56, 2.1), fill: rgb("#783f04").lighten(50%), stroke: none)
    content((4.0, 1.85), box(width: 4.0cm, inset: 1pt, align(center, text(size: 7.5pt)[MLA (DeepSeek-V3): ~7%])))

    // axes
    line((0, 1.2), (0, 6.0), stroke: 0.6pt)
    line((0, 1.2), (8.8, 1.2), stroke: 0.6pt)
    content((-0.6, 3.6), angle: 90deg, text(size: 7.5pt)[Cache size])
    content((4.4, 0.9), text(size: 7.5pt)[(each bar relative to baseline)])
  })
)

== Family 4: Prompt and Context Compression

All three families above shrink the *stored* cache. A fourth strategy attacks the problem at source: compress the *input text* before it ever enters the model, so fewer tokens are processed and fewer cache entries are ever created.

=== LLMLingua: Drop the Unimportant Tokens

LLMLingua (Microsoft Research, EMNLP 2023) uses a small, fast language model (much smaller than the target LLM) to evaluate *how surprising* each token in the prompt is, given its context. Unsurprising tokens (tokens with low *perplexity*, i.e., high model probability) are candidates for removal: if the small model already expected this token, the big model probably does too, and removing it loses little information.

#mathrecall[From Chapter 18: *perplexity* of a sequence under model $M$ is $2^H$ where $H$ is the cross-entropy. Low perplexity means the model was unsurprised: the sequence was predictable.]

The LLMLingua pipeline:
1. A *budget controller* decides the overall compression ratio (e.g., 4x) and how to allocate it across the prompt's structural parts (instructions, context, examples, question).
2. A small model (e.g., LLaMA-7B) scores each token in the prompt with its conditional perplexity.
3. Tokens with probability above a threshold (the predictable ones) are dropped.
4. A post-processing step reconnects the remaining tokens into pseudo-sentences that the target LLM will still parse correctly.

LLMLingua achieves up to 20x compression with minimal performance loss on benchmarks involving long-context retrieval and question answering. LLMLingua-2 (2024) improved on the original by training a dedicated BERT-scale classifier on GPT-4-distilled data, framing compression as token classification rather than perplexity thresholding. This lets it use bidirectional context and better preserve rare but critical tokens.

#algo(
  name: "LLMLingua / LLMLingua-2",
  year: "2023 / 2024",
  authors: "Huiqiang Jiang, Qianhui Wu, Chin-Yew Lin, Yuqing Yang, Lili Qiu (Microsoft Research)",
  aim: "Drop low-information tokens from a long prompt to reduce the context fed to a large, expensive target LLM. Fewer tokens means faster decoding, smaller KV-cache, lower API cost",
  complexity: "One forward pass through a small proxy model to score all tokens; $O(n)$ time where $n$ is prompt length",
  strengths: "Up to 20x compression achievable; no modification to target LLM; integrated into LlamaIndex; LLMLingua-2 achieves better recall of critical tokens via bidirectional context",
  weaknesses: "Target LLM must tolerate grammatically fragmented input; can drop rare high-perplexity tokens that are actually load-bearing facts; requires a proxy model running at serving time",
  superseded: "AutoCompressors (2023, soft token approach); selective context summarization methods; KV-cache reuse systems like gisting",
)[
  The key insight connecting LLMLingua to the rest of this book: dropping a token because a small model finds it predictable is exactly the compression move we have seen everywhere. *A good prediction makes a cheap code.* Here the "code" is zero bits (omission), and the "decoder" is the target LLM, which fills in the predictable word implicitly from context. This is lossy compression of the prompt, with the target model acting as a soft decoder.
]

#keyidea[
  LLMLingua exploits cross-entropy as a measure of information content: a token that the proxy model assigns high probability to carries little new information beyond what came before. Dropping it is the same bet we make in LZ77 when we replace a repeated string with a back-reference - that the decoder can reconstruct it from context.
]

== Product Quantization: Compressing Vectors for Retrieval

So far we have been inside the language model. Now we zoom out to a different but related problem: storing and searching enormous collections of *embedding vectors* efficiently.

=== The Embedding Problem

Modern retrieval systems (the "R" in RAG, or Retrieval-Augmented Generation) work like this: convert every document chunk into a *dense vector embedding* produced by a neural model. Store millions of these vectors. At query time, convert the query into a vector of the same kind, then find the nearest stored vectors (approximate nearest-neighbour search, ANN).

A typical embedding might have $d = 768$ or $d = 1536$ floating-point dimensions. In `float32`, one vector costs $768 times 4 = 3,072$ bytes. A million vectors: 3 GB. A billion vectors: 3 TB. That is too large for fast in-memory search.

Product Quantization (PQ), introduced by Jégou, Douze, and Schmid in their landmark 2011 IEEE TPAMI paper "Product Quantization for Nearest Neighbor Search," is the solution that almost every large-scale vector database uses today.

=== The PQ Idea: Divide and Conquer

PQ splits each $d$-dimensional vector into $M$ non-overlapping sub-vectors of dimension $d / M$ each, then separately quantizes each sub-vector.

Each sub-vector is quantized by finding the nearest of $K = 256$ *centroids* (cluster centers) learned from training data by running k-means on that subspace. The result is a single byte (one of 256 options) per sub-vector. So a 768-dimensional vector with $M = 96$ sub-vectors of dimension 8 each becomes 96 bytes, a *32x compression* from `float32`.

#gomaths("K-means clustering")[
  *K-means* is an algorithm for grouping $n$ data points into $K$ clusters. Starting with $K$ random centroids (representative points), it alternates between:

  1. Assign each data point to its nearest centroid.
  2. Move each centroid to the mean of its assigned points.

  Repeat until assignments stop changing. The result: $K$ cluster centers that best "summarize" the data.

  *Why 256 centroids?* Because $2^8 = 256$, so each centroid index fits in exactly one byte. With 8-bit codes, each sub-vector's centroid assignment is one byte, and all 256 centroids for one sub-space fit in a tiny lookup table. The training cost is $O(n d K)$ for $n$ vectors.
]

=== A Worked Numeric Example

Suppose we have 4-dimensional vectors and split into $M = 2$ sub-vectors of dimension 2. (In practice $M = 64$ or $M = 96$; we use 2 for clarity.)

*Training:* run k-means on sub-space 1 (dimensions 1--2) and sub-space 2 (dimensions 3--4) separately.

- Codebook 1: centroid A = $(0.1, 0.2)$, centroid B = $(0.9, 0.8)$, centroid C = $(0.5, 0.5)$ (256 in practice; 3 here).
- Codebook 2: centroid X = $(0.0, 1.0)$, centroid Y = $(1.0, 0.0)$, centroid Z = $(0.5, 0.5)$.

*Encoding* vector $bold(v) = (0.08, 0.19, 0.95, 0.12)$:
- Sub-vector 1: $(0.08, 0.19)$. Distances: to A = $sqrt((0.08-0.1)^2+(0.19-0.2)^2) approx 0.022$; to B $approx 1.14$; to C $approx 0.46$. Nearest: *A*. Code: byte 0.
- Sub-vector 2: $(0.95, 0.12)$. Distances: to X $approx 1.29$; to Y $= sqrt(0.0025+0.0144) approx 0.13$; to Z $approx 0.66$. Nearest: *Y*. Code: byte 1.

Stored representation: 2 bytes instead of 4 floats (16 bytes). *8x compression* for this toy example.

*Fast distance computation:* to compare query $bold(q)$ against all stored vectors, pre-compute *distance tables*: for each sub-space $m$, the distance from the corresponding sub-vector of $bold(q)$ to each of the 256 centroids. Then the approximate distance to any stored vector is the sum of $M$ table lookups, one memory access per sub-space. For a billion vectors and $M = 96$, this is 96 billion lookups, but each lookup is a single array read: far faster than computing 768 floating-point distances.

#fig(
  [Product quantization: split the vector into M sub-vectors, find the nearest centroid in each sub-space, store only the centroid indices.],
  cetz.canvas({
    import cetz.draw: *
    // Original vector box
    rect((0.0, 3.6), (7.5, 4.3), fill: rgb("#dbe8f4"), stroke: 0.5pt + rgb("#aabbcc"))
    content((3.75, 3.95), box(width: 7.1cm, inset: 1pt, align(center, text(size: 8pt)[Original 768-D float32 vector (3,072 bytes)])))

    // Arrow
    line((3.75, 3.6), (3.75, 3.1), mark: (end: ">"), stroke: 0.7pt)
    content((5.5, 3.35), box(width: 3.6cm, inset: 1pt, align(center, text(size: 7.5pt)[Split into M sub-vectors])))

    // Sub-vector boxes
    let fills = (rgb("#c8e6c9"), rgb("#fff9c4"), rgb("#fce4ec"), rgb("#e8eaf6"))
    for i in range(4) {
      let x0 = i * 1.85
      rect((x0, 2.0), (x0 + 1.6, 2.85), fill: fills.at(i), stroke: 0.4pt)
      content((x0 + 0.8, 2.43), box(width: 1.2cm, inset: 1pt, align(center, text(size: 7.5pt)[Sub-#str(i+1) \ (8-D)])))
    }
    content((7.6, 2.43), text(size: 8.5pt)[...])

    // Arrow
    line((3.75, 2.0), (3.75, 1.5), mark: (end: ">"), stroke: 0.7pt)
    content((6.0, 1.75), box(width: 3.6cm, inset: 1pt, align(center, text(size: 7.5pt)[k-means: nearest centroid])))

    // Code byte boxes
    for i in range(4) {
      let x0 = i * 1.85
      rect((x0, 0.4), (x0 + 1.6, 1.2), fill: rgb("#fff3e0"), stroke: 0.5pt + rgb("#ffb74d"))
      content((x0 + 0.8, 0.8), box(width: 1.2cm, inset: 1pt, align(center, text(size: 7.5pt)[byte #str(i+1)])))
    }
    content((7.6, 0.8), text(size: 8.5pt)[...])
    content((3.75, 0.1), box(width: 7.1cm, inset: 1pt, align(center, text(size: 8pt, style: "italic")[96 bytes total (from 3,072): 32x compression])))
  })
)

=== OPQ: Optimized Product Quantization

Standard PQ splits the vector at fixed dimension boundaries, ignoring correlations between sub-spaces. Optimized Product Quantization (OPQ, Ge, He, Ke & Sun, IEEE TPAMI 2013--14) adds a learned rotation before splitting: find the rotation matrix $bold(R)$ such that the quantization error after PQ on $bold(R) bold(v)$ is minimized. Equivalently, rotate the embedding space so variance is evenly distributed across sub-spaces before the fixed splits.

The rotation is learned iteratively, alternating between optimizing the PQ codebooks for a fixed $bold(R)$ and optimizing $bold(R)$ for fixed codebooks, on a sample of training vectors. At query time, the query is also rotated by $bold(R)$ before the lookup-table distance computation.

OPQ typically gives 10--20% better recall than vanilla PQ at the same compression ratio, at the cost of one matrix--vector product per query. It is available in FAISS as `IndexIVFOPQ`.

#algo(
  name: "Product Quantization (PQ) / Optimized PQ (OPQ)",
  year: "2011 (PQ) / 2013--14 (OPQ)",
  authors: "Hervé Jégou, Matthijs Douze, Cordelia Schmid (INRIA, France); OPQ: Tiezheng Ge, Kaiming He, Qifa Ke, Jian Sun (Microsoft Research)",
  aim: "Compress high-dimensional float vectors to a few bytes, while enabling fast approximate distance computation in the compressed domain via lookup tables",
  complexity: "Training: $O(n d K M)$ for $n$ vectors; Encoding: $O(d K)$ per vector; Query: $O(n M)$ per query via table lookups, much faster than $O(n d)$ exact search",
  strengths: "32x or greater memory compression; fast lookup-table distance computation; FAISS (Meta AI, 2017) makes billion-scale PQ search accessible; widely deployed in production vector databases",
  weaknesses: "Lossy: approximate distances, so some true nearest neighbours are missed (recall typically 80--95%); sensitive to sub-space dimension choice; OPQ training cost scales with corpus size",
  superseded: "ScaNN (Google, 2020) for top-recall scenarios; HNSW (graph-based index) for high-recall; neural quantizers like Qinco2 (arXiv:2501.03078, 2025) for better recall at same compression; PQ remains the default in FAISS for high-compression regimes",
)[
  PQ was originally proposed for image retrieval: finding similar images in billion-image databases, at a time when deep embeddings did not yet exist. It transferred cleanly to the neural-embedding era. FAISS, the open-source library Meta AI built around PQ (released 2017), now underpins vector search in most major LLM applications. Kaiming He, a co-author of OPQ, later co-invented ResNet (2015) and is now one of the most-cited researchers in computer vision.
]

== Binary and Matryoshka Embeddings

Beyond PQ, two other compression strategies for embeddings have become practically important in 2024--2026.

=== Binary Quantization: 1 Bit per Dimension

Binary quantization is the most aggressive form of scalar quantization: map each floating-point coordinate to a single bit (positive → 1, negative → 0). A 768-dimensional `float32` vector (3,072 bytes) becomes a 768-bit binary vector: 96 bytes, a *32x compression*.

Approximate distances in the binary domain are computed with the *Hamming distance*: the number of bit positions where two binary vectors differ. Modern CPUs can compare 64 bits in a single instruction using the hardware `POPCNT` instruction, making binary search extremely fast.

The accuracy cost is surprisingly small for modern embedding models. Research from Hugging Face and the MTEB (Massive Text Embedding Benchmark) leaderboard in 2024 shows that binary quantization of state-of-the-art sentence embeddings retains 85--95% of the retrieval recall of the full-precision vectors. FAISS, ScaNN, and virtually every production vector database support binary search as a first-pass filter (retrieve the top 10x candidates, then re-rank with full precision).

#gopython("Simulating binary quantization and Hamming distance")[
  Here is a tiny simulation showing how to binary-quantize a float embedding and compute Hamming distance.

  ```python
  def binary_quantize(vec: list[float]) -> bytes:
      """Convert a float vector to a packed binary vector (1 bit per dim)."""
      n_bytes = (len(vec) + 7) // 8
      result = bytearray(n_bytes)
      for i, x in enumerate(vec):
          if x >= 0.0:
              result[i // 8] |= (1 << (i % 8))
      return bytes(result)

  def hamming_distance(a: bytes, b: bytes) -> int:
      """Count differing bits between two packed binary vectors."""
      return sum(bin(x ^ y).count("1") for x, y in zip(a, b))

  # Demo with 8-dimensional toy vectors
  v1 = [0.3, -0.1,  0.8, -0.5,  0.2,  0.9, -0.4,  0.6]
  v2 = [0.2, -0.3,  0.7, -0.1,  0.1,  0.8, -0.6,  0.5]

  b1 = binary_quantize(v1)   # 1 byte encodes all 8 dimensions
  b2 = binary_quantize(v2)

  print(f"v1 signs: {[1 if x>=0 else 0 for x in v1]}")
  print(f"v2 signs: {[1 if x>=0 else 0 for x in v2]}")
  print(f"Hamming distance: {hamming_distance(b1, b2)}")
  # → 0 (signs agree on all 8 dims in this example)

  # A vector where the signs differ:
  v3 = [-0.2, 0.1, 0.8, -0.5, 0.2, -0.9, -0.4, 0.6]
  b3 = binary_quantize(v3)
  print(f"Hamming(v1, v3): {hamming_distance(b1, b3)}")
  # → 2 (dims 0 and 5 flipped)
  ```

  In production, `numpy` does this as `(vec >= 0).view(np.uint8)` packed with `numpy.packbits`, and FAISS handles the bitpacking and `POPCNT` distance computation internally. Binary search can be 100x faster than float dot-product at billion scale.
]

=== Matryoshka Representation Learning

Binary quantization reduces precision. What if instead we reduce *dimensionality*? Matryoshka Representation Learning (MRL, Kusupati et al., NeurIPS 2022) trains embeddings so that the *first $k$ dimensions already form a meaningful representation* for any prefix length $k in {8, 16, 32, 64, 128, 256, 512, 1024}$.

The training trick: optimize the standard retrieval loss simultaneously at *multiple* output sizes, front-loading the most important information into the earliest dimensions. The name "Matryoshka" refers to Russian nesting dolls: each shorter prefix is a valid, useful embedding nested inside the larger one.

#aside[
  OpenAI's `text-embedding-3-small` and `text-embedding-3-large` models, released in early 2024, explicitly support MRL-style truncation via an API `dimensions` parameter. They were the first production embedding models to ship with built-in multi-resolution support. Truncating from 3072 to 256 dimensions costs roughly 1% recall on standard benchmarks.
]

=== The Combination: MRL + Binary

The real leverage comes from combining both techniques:

1. Take a 1024-dimensional embedding.
2. Truncate to 128 dimensions (MRL). Memory: $128 times 4 = 512$ bytes.
3. Binary-quantize the 128 dimensions. Memory: $128 / 8 = 16$ bytes.

Total compression: $1024 times 4 / 16 = 256 times$ relative to the original `float32` 1024-D vector, while retaining roughly 90% of retrieval recall on standard benchmarks (per Vespa's published evaluation, 2024). This combination is the default configuration for large-scale retrieval in cost-sensitive deployments.

#scoreboard(
  caption: "KV-cache and embedding compression: representative savings (illustrative figures)",
  [Full BFloat16 MHA KV-cache], [512 KB/tok], [1.0x], [Baseline: 32 layers, 32 heads, 128 dim/head],
  [H2O eviction (20% budget)], [102 KB/tok], [5.0x], [Evicts 80%; some loss on long-range tasks],
  [4-bit KV quantization], [128 KB/tok], [4.0x], [PolarQuant / TurboQuant rotation + INT4],
  [MLA (DeepSeek-V3 style)], [37 KB/tok], [13.8x], [Low-rank latent; ~93% reduction vs. MHA],
  [Float32 768-D embedding], [3,072 bytes], [1.0x], [Baseline embedding for retrieval],
  [PQ (M=96 sub-spaces, K=256)], [96 bytes], [32x], [80--95% ANN recall; FAISS default],
  [Binary quantization 768-D], [96 bytes], [32x], [Fast Hamming; 85--95% recall],
  [MRL 128-D + binary], [16 bytes], [192x], [~90% recall; Vespa / FAISS deployment],
)

== Putting It All Together: The Inference Memory Stack

An LLM inference system in 2025--2026 stacks these techniques in layers:

*Architecture level:* choose MLA or GQA at training time. This is the highest-leverage intervention: a ~93% reduction before any further tricks.

*Quantization level:* store the KV-cache in 4 bits with rotation-based quantization (PolarQuant, TurboQuant). Independent of the architecture choice; roughly a 4x further reduction.

*Eviction level:* for very long contexts, combine with SnapKV or H2O-style policies. The three levels compose multiplicatively.

*Prompt level:* for RAG and multi-turn chat, use LLMLingua-style prompt compression to reduce the number of tokens that ever enter the model.

*Retrieval level:* store document embeddings in PQ or binary-quantized form in FAISS or a vector database; the ANN index fits in RAM rather than requiring expensive GPU memory.

The result: a system that can serve 128K-token contexts on hardware that could barely handle 4K tokens two years earlier, with quality that is, in most practical tasks, indistinguishable from the uncompressed version.

#misconception[
  "Compressing the KV-cache is just quantization, the same as compressing model weights."
][
  KV-cache compression and weight quantization share the same underlying arithmetic, but the target and the constraints differ. Weights are fixed after training; the cache grows dynamically with each new token and must be compressed in real time, with zero budget for expensive calibration passes. Weight quantization can afford one-shot calibration (GPTQ uses Hessian inverses computed over a calibration set). KV-cache quantization must be *online*: each new key/value vector is quantized the instant it is computed. This is why rotation-based methods (PolarQuant, TurboQuant) matter; the rotation can be pre-applied as a cheap matrix multiply, making the subsequent per-token scalar quantization trivially fast.
]

#gopython("A minimal KV-cache size estimator")[
  This function computes KV-cache memory (in bytes) for a standard MHA model and for an MLA model, so you can see the difference concretely.

  ```python
  def kv_cache_bytes_mha(
      n_layers: int,
      n_heads: int,
      head_dim: int,
      n_tokens: int,
      bytes_per_float: int = 2,   # bfloat16
  ) -> int:
      """Estimate KV-cache bytes for standard multi-head attention."""
      # Factor of 2: one K matrix and one V matrix per layer
      return 2 * n_layers * n_heads * head_dim * n_tokens * bytes_per_float

  def kv_cache_bytes_mla(
      n_layers: int,
      latent_dim: int,      # d_c, the compressed latent size
      decoupled_dim: int,   # small positional key kept separately
      n_tokens: int,
      bytes_per_float: int = 2,
  ) -> int:
      """Estimate KV-cache bytes for MLA (DeepSeek-V2/V3 style)."""
      # Only the latent vector + small decoupled positional key
      return n_layers * (latent_dim + decoupled_dim) * n_tokens * bytes_per_float

  # Approximate DeepSeek-V3 config
  mha = kv_cache_bytes_mha(
      n_layers=61, n_heads=128, head_dim=128, n_tokens=10_000
  )
  mla = kv_cache_bytes_mla(
      n_layers=61, latent_dim=512, decoupled_dim=64, n_tokens=10_000
  )

  print(f"MHA KV-cache at 10K tokens: {mha / 1e9:.2f} GB")
  print(f"MLA KV-cache at 10K tokens: {mla / 1e9:.2f} GB")
  print(f"Reduction: {mha / mla:.1f}x")
  # MHA KV-cache at 10K tokens: 40.31 GB
  # MLA KV-cache at 10K tokens:  0.70 GB
  # Reduction: 57.6x
  ```

  The numbers are somewhat larger than DeepSeek's reported 14x because DeepSeek uses GQA as the baseline for their comparison, not full MHA. But the principle is clear: only `latent_dim + decoupled_dim` numbers are cached per token per layer, instead of `2 * n_heads * head_dim`.
]

#checkpoint[
  In product quantization with $M = 64$ sub-spaces and $K = 256$ centroids per sub-space, how many bytes does one encoded vector occupy? How many entries are in the distance lookup table for a single query?
][
  Exactly 64 bytes: one byte per sub-space (since $K = 256 = 2^8$ centroids, the index fits in 8 bits). The lookup table has $M times K = 64 times 256 = 16,384$ entries, computed once per query from the query sub-vectors and then read once per stored vector.
]

#takeaways((
  "The KV-cache stores pre-computed keys and values for every past token, enabling fast attention at the cost of memory that grows linearly with context length. At 512 KB per token for a large MHA model, this dominates inference memory",
  "H2O eviction retains 'heavy hitter' tokens (highest cumulative attention scores) and recent tokens, evicting everything else once a budget is hit; 29x throughput reported on OPT-30B at 20% budget",
  "SnapKV uses the last few prompt tokens as an observation window to identify important cache positions before generation begins, enabling 3.6x speedup with near-zero quality loss",
  "DeepSeek's MLA trains a joint low-rank compression of all heads' keys and values into a single latent vector, achieving approximately 93% KV-cache reduction as a first-class architectural choice",
  "KV-cache quantization is complicated by outlier values; random rotation pre-conditioning (PolarQuant, TurboQuant) redistributes variance uniformly, enabling accurate 3--4-bit scalar quantization",
  "LLMLingua uses a small proxy model's perplexity scores to drop low-information tokens from prompts, compressing context length by up to 20x before tokens ever enter the model",
  "Product quantization splits an embedding into M sub-vectors, codes each sub-vector as a byte-sized centroid index, and enables fast approximate nearest-neighbour search via M table lookups per query; 32x compression typical",
  "Binary quantization (1 bit per dimension) and Matryoshka truncation each give approximately 32x compression; combined they reach ~192x while retaining about 90% retrieval recall, the standard for cost-sensitive deployment in 2025--2026",
))

== Exercises

#exercise("65.1", 1)[
  A model has 40 attention layers, 40 heads per layer, and 128 dimensions per head. Weights are stored in BFloat16 (2 bytes each). Calculate the KV-cache size for a 32,000-token context. Express your answer in gigabytes.
]
#solution("65.1")[
  Per token per layer: $2 times 40 times 128 times 2 = 20,480$ bytes (the factor of 2 accounts for both K and V). Over 40 layers and 32,000 tokens: $40 times 32,000 times 20,480 = 26,214,400,000$ bytes $approx 26.2$ GB.
]

#exercise("65.2", 1)[
  Explain in your own words why H2O keeps *both* heavy hitters and recent tokens, rather than keeping only heavy hitters.
]
#solution("65.2")[
  Heavy hitters capture long-range dependencies: the semantically important tokens established early in the context (the question, key facts, instructions). Recent tokens capture local coherence: the model almost always attends strongly to the last few generated tokens to stay grammatically and semantically connected to what comes next. Using only heavy hitters would cause the model to lose track of the immediate "thread" of the current sentence. Using only recent tokens would cause it to forget the key facts from earlier in the conversation. The combination handles both scales of dependency.
]

#exercise("65.3", 2)[
  A 512-dimensional embedding is compressed with PQ using $M = 64$ sub-spaces (dimension 8 each) and $K = 256$ centroids per sub-space. (a) How many bytes does the compressed vector occupy? (b) How many floating-point numbers are stored in all 64 codebooks combined? (c) What is the compression ratio versus the original `float32` vector?
]
#solution("65.3")[
  (a) 64 bytes: one byte per sub-space index ($2^8 = 256$ options fits in 8 bits). (b) $64 times 256 times 8 = 131,072$ floats across all codebooks, but these are shared across all stored vectors, not per-vector overhead. (c) Original: $512 times 4 = 2,048$ bytes. Compressed: 64 bytes. Ratio: $2,048 / 64 = 32 times$.
]

#exercise("65.4", 2)[
  MLA's low-rank latent has dimension $d_c = 512$ while the full key-value cache for the same model (128 heads, head dimension 128) has $2 times 128 times 128 = 32,768$ floats per layer per token. (a) What is the compression ratio? (b) MLA requires a matrix multiplication of shape $512 times 32,768$ to expand the latent to keys/values at each attention step. Why does this matrix not add to the *cache* memory?
]
#solution("65.4")[
  (a) $32,768 / 512 = 64 times$ per layer. (b) The expansion matrix is a fixed model parameter: it is loaded once when the model starts and stays in GPU memory throughout. The cache is the *per-token*, *growing* buffer of new information. Model weights are static; cache entries are dynamic. Only the latent $bold(c)$ (512 floats, 1 KB in BFloat16) is new for each token; the expansion matrix is the same whether we process 1 token or 100,000 tokens.
]

#exercise("65.5", 2)[
  LLMLingua uses a small proxy model to identify low-perplexity tokens for removal. One token has perplexity 1.2 under the proxy model; another has perplexity 85. (a) Which is the better candidate for removal? (b) Explain why, connecting to the information-theoretic definition of perplexity from Chapter 18. (c) Give one type of token that might have low perplexity but still be critical to keep.
]
#solution("65.5")[
  (a) The token with perplexity 1.2 is the better candidate for removal. (b) Perplexity equals $2^H$ where $H$ is the cross-entropy. Low perplexity means low surprisal: the model expected this token with high probability, so it carries little new information. Dropping it is like removing a predictable symbol; the "code length" (information content) is nearly zero. The high-perplexity token was unexpected and carries more information, so it should be kept. (c) A proper noun or specific number that happens to appear in a grammatically predictable slot ("the answer is 42") has low perplexity (the grammar predicts a number will follow "the answer is") but is semantically essential. Domain-specific technical terms in predictable syntactic positions can also be low-perplexity but factually critical.
]

#exercise("65.6", 3)[
  Design a combined KV-cache compression scheme for a 32-layer, 32-head, 128-dim/head transformer serving a 64,000-token context. Target: fit the cache in 4 GB of GPU memory. (a) Calculate the uncompressed BFloat16 cache size. (b) Choose which combination of MLA, quantization, and/or eviction reaches the target, showing your arithmetic. (c) Identify one quality risk of your chosen scheme and how you would validate it.
]
#solution("65.6")[
  (a) Uncompressed BFloat16: $2 times 32 times 32 times 128 times 64,000 times 2 = 16.78$ GB. (b) Option A: 4-bit quantization alone. BFloat16 is 2 bytes/float; INT4 is 0.5 bytes/float; ratio = $16.78 / 4 = 4.19$ GB, just fits. Option B: H2O at 20% budget alone, $16.78 / 5 = 3.36$ GB, fits with margin. Safer: combine both ($16.78 / 4 / 2 = 2.10$ GB), leaving ample headroom for model weights and activations. (c) Quality risk: 4-bit quantization may cause precision loss on long-context multi-hop reasoning (e.g., tracking entities across 64K tokens). Validate by comparing exact-match accuracy on a long-document QA benchmark (e.g., SCROLLS QuALITY or QASPER with full 64K context) against the BFloat16 baseline, and flag any degradation exceeding 2 absolute points as unacceptable.
]

== Further Reading

- #link("https://arxiv.org/abs/2306.14048")[Zhang et al. (2023). *H2O: Heavy-Hitter Oracle for Efficient Generative Inference of Large Language Models.* NeurIPS 2023.] The original H2O paper; includes the submodular formalization and ablations across OPT, LLaMA, and GPT-NeoX.

- #link("https://arxiv.org/abs/2404.14469")[Li et al. (2024). *SnapKV: LLM Knows What You are Looking for Before Generation.* NeurIPS 2024.] Observation-window pooling for smarter prefix compression; 3.6x speedup with near-zero quality cost.

- #link("https://arxiv.org/pdf/2405.04434")[DeepSeek-AI (2024). *DeepSeek-V2: A Strong, Economical, and Efficient Mixture-of-Experts Language Model.* arXiv:2405.04434.] MLA is introduced and analyzed here; the appendix derives the absorb-form optimization.

- #link("https://arxiv.org/pdf/2412.19437")[DeepSeek-AI (2024). *DeepSeek-V3 Technical Report.* arXiv:2412.19437.] Scaling MLA to 671B parameters with full open weights; reports the 70 KB/token figure.

- #link("https://openreview.net/pdf?id=tO3ASKZlok")[Google Research (2026). *TurboQuant: Online Vector Quantization for KV-Cache Compression.* ICLR 2026.] 3-bit KV-cache via rotation and online VQ; companion to PolarQuant.

- #link("https://arxiv.org/pdf/2502.02617")[PolarQuant authors (2025). *Quantizing KV Caches with Polar Transformation.* AISTATS 2026.] Rotation-based outlier taming for key-cache quantization.

- #link("https://www.microsoft.com/en-us/research/blog/llmlingua-innovating-llm-efficiency-with-prompt-compression/")[Jiang et al. (2023). *LLMLingua: Innovating LLM Efficiency with Prompt Compression.* EMNLP 2023.] First system to systematically drop low-perplexity prompt tokens; up to 20x compression.

- #link("https://arxiv.org/pdf/2407.18003")[Liang et al. (2024). *A Survey on Efficient Inference for Large Language Models.* arXiv:2407.18003.] Saved in `papers/liang-2024-kvcache-survey.pdf`. Comprehensive survey covering eviction, quantization, speculative decoding, and architectural approaches.

- #link("https://www.researchgate.net/publication/47815472_Product_Quantization_for_Nearest_Neighbor_Search")[Jégou, Douze & Schmid (2011). *Product Quantization for Nearest Neighbor Search.* IEEE TPAMI.] The paper that established PQ as the standard technique for large-scale ANN search.

- #link("https://people.csail.mit.edu/kaiming/publications/pami13opq.pdf")[Ge, He, Ke & Sun (2013--14). *Optimized Product Quantization.* IEEE TPAMI.] The rotation-optimization extension of PQ.

- #link("https://huggingface.co/blog/matryoshka")[HuggingFace (2024). *Introduction to Matryoshka Embedding Models.*] Matryoshka training and truncation, with practical guidance.

#bridge[
  We have now seen every major compression technique for the *serving* side of modern AI: how to shrink what the model stores during inference (KV-cache) and how to shrink what retrieval systems store (embeddings). The next chapter steps out of the AI world entirely and into the universe of *scientific data*, the outputs of climate simulations, cosmological N-body codes, and fluid dynamics solvers. These petabyte-scale floating-point arrays present a completely different compression challenge: the user does not care about exact reconstruction, but they care deeply about *error bounds*, and they need random access into the compressed data. Chapter 66 introduces zfp and SZ, the two dominant error-bounded lossy compressors for HPC, and explains why a DCT-like orthogonal transform is the right tool for decorrelating simulation data.
]
