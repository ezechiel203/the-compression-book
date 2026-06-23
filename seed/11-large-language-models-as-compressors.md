## Large Language Models as Compressors

This is the frontier where compression and modern AI become, quite literally, the same object. The thesis is provocative but precise: a good predictor *is* a good compressor, and vice versa. If that equivalence is exact, then the decades-long race to compress English Wikipedia is also a race to build intelligence — and the largest language models, almost as a side effect of being trained to predict text, turn out to be the best lossless compressors ever measured. This section explains the mechanism, the headline results, and the deep tension at the heart of the program.

### The bridge: prediction is compression (Shannon, restated)

Recall the foundational fact from earlier sections. A lossless **entropy coder** assigns short codes to likely symbols and long codes to unlikely ones; Shannon's source coding theorem says the best achievable expected code length for a symbol with probability `p` is `-log₂ p` bits. **Arithmetic coding** (Rissanen 1976, Witten–Neal–Cleary 1987) realizes this almost exactly: given a probability `p(xₜ | x₁…xₜ₋₁)` for the next symbol, it consumes essentially `-log₂ p(xₜ | x₁…xₜ₋₁)` bits to encode it, narrowing an interval on `[0,1)` symbol by symbol. The total compressed length of a sequence is therefore

`L = Σₜ -log₂ p(xₜ | x₁…xₜ₋₁)` bits.

Now look at how a language model is trained. The standard objective is to minimize the **cross-entropy** (negative log-likelihood) of the next token — exactly `Σₜ -log p(xₜ | context)`. That is the *same sum*. Minimizing an LLM's training loss and minimizing the arithmetic-coded file size are mathematically identical operations, differing only by the constant `log 2`. A model reporting a loss of, say, 1.0 nats/token compresses at ~1.44 bits/token. This is why people say "log-loss is just expected code length in disguise." The model supplies `p`; arithmetic coding turns surprise — `-log p` — into bits. Where the model is confident and correct, the residual surprise is near zero and almost no bits are spent; where it is wrong, it pays.

### DeepMind's "Language Modeling Is Compression" (2023)

The cleanest statement of this came from Grégoire Delétang, Anian Ruoss, and colleagues at Google DeepMind in their paper *Language Modeling Is Compression* (arXiv, September 2023; ICLR 2024). They took **Chinchilla 70B** — a text-trained LLM — froze it, and used it as the probability model `p` feeding an arithmetic coder. The results were striking precisely because the model was used *out of domain*:

- On **enwik9** (1 GB of Wikipedia), Chinchilla reached around **1.0 bits/byte**, beating gzip (~3.1 bpb) and the strong general-purpose coder LZMA (~2.3 bpb) by a wide margin.
- On **ImageNet image patches**, it compressed to **43.4%** of raw size, beating PNG (58.5%) — *despite never being trained on images*, fed as raw byte streams.
- On **LibriSpeech audio**, it reached **16.4%**, beating the specialized lossless audio codec FLAC (30.3%).

A text model beating PNG on images and FLAC on audio is the headline. It works because all three are, at bottom, sequences of bytes with statistical regularity, and a sufficiently general next-byte predictor exploits that regularity better than hand-built domain codecs. The paper also reframed **scaling laws** through compression: bigger models predict better, so they compress better — but only up to a point that depends honestly on accounting (below).

### Bellard's nncp and ts_zip: the practical leaderboard

Fabrice Bellard — author of FFmpeg, QEMU, and TCC — turned this idea into running tools. His **nncp** (first released 2019; v2 in 2021 switched from LSTM to a Transformer) is an *online* neural compressor: the network starts untrained and learns the file *as it compresses it*, so no model needs to be shipped. On the **Large Text Compression Benchmark** (Matt Mahoney's enwik8/enwik9 board), nncp's 2023 release reaches **1.19 bpb on enwik8** and **0.853 bpb on enwik9** (106.6 MB) — long among the very best results, competitive with or beating the elaborate context-mixing compressor cmix. (Note that the dedicated **Hutter Prize**, which charges decompressor size and runtime, was won in October 2024 by Kaido Orav and Byron Knoll's *fx2-cmix* at ~110.8 MB on enwik9; nncp's raw ratio is excellent but its model-evaluation cost sits awkwardly with the prize's strict resource limits.)

His **ts_zip** (2023–) takes the opposite, *pretrained* route. It ships a frozen **RWKV 169M** language model (an RNN-style architecture chosen for speed), quantized to 8 bits, and arithmetic-codes text against it. Reported figures: **1.106 bpb on enwik8**, **1.084 bpb on enwik9**, **1.142 bpb on alice29.txt**. Crucially, Bellard engineered the model to evaluate **deterministically and reproducibly across GPUs and CPUs** — a non-obvious requirement, because if the encoder and decoder compute even slightly different floating-point probabilities, the arithmetic decoder desynchronizes and the file is corrupt. ts_zip needs a GPU and ~4 GB RAM and runs at up to ~1 MB/s on an RTX 4090.

### The tension: enormous, slow models for tiny gains

Here the intellectual honesty has to kick in. Three caveats hollow out the "we just won compression" claim:

**1. Model-size accounting.** A frozen LLM is a fixed cost the decoder must possess. The genuinely fair number is *adjusted* compressed size = file bits + model bits. By this honest accounting, Chinchilla 70B at fp16 is ~140 GB of parameters — vastly larger than the 1 GB it compresses. The DeepMind authors are explicit about this: the off-domain wins are real but the model dwarfs the payload, so it is *not* free-lunch compression of a single file. The model only "pays for itself" when amortized over an enormous corpus, which is exactly why Bellard's tiny 169M RWKV (a few hundred MB) is the *practical* sweet spot, not Chinchilla.

**2. Speed.** Classical zstd compresses hundreds of MB/s; ts_zip manages ~1 MB/s *on a high-end GPU*, and full LLM coders are far slower. You spend orders of magnitude more compute and energy to shave a fraction of a bit per byte. For most real workloads this is a catastrophic trade.

**3. Fragility and reproducibility.** Lose the exact model — or run it on hardware that rounds differently — and the data is gone forever. Versioned, deterministic models are mandatory; Bellard warns explicitly that "no backward compatibility should be expected."

### What it says about "compression = intelligence"

The strongest *empirical* support for the slogan is Huang, Zhang, Shan, and He's *Compression Represents Intelligence Linearly* (HKUST/Tencent, 2024): across 30 LLMs and 12 benchmarks, a model's bits-per-character on held-out text correlates with downstream benchmark scores at a Pearson r of about **−0.95** — better compression, higher "intelligence," nearly a straight line. This is genuinely surprising and lends the thesis real weight: learning to predict text efficiently *does* track measured capability.

But by 2025–2026 the consensus is more careful. The correlation says intelligence implies compression (a smart model predicts text well); it does not establish that *all* intelligence reduces to it. Reasoning that doesn't manifest as predictable token statistics, out-of-distribution generalization, and the brute economics — gigantic, slow, fragile models for marginal ratio gains — all suggest compression is a *necessary signature* of capable models, not a complete *definition* of intelligence. The frontier remains a beautiful identity (log-loss = code length) that unified two fields, plus a sober reminder that being the world's best compressor, at the cost of a 140 GB model running at 1 MB/s, is not obviously a victory.