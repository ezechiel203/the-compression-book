#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Large Language Models as Compressors

#epigraph[
  "The best compression of a string is the shortest program that prints it. We can't find that program — but we can train one that gets eerily close."
][a paraphrase of the folklore that runs through this whole book]

Here is a sentence with a hole in it: "The cat sat on the \_\_\_." If I asked you to bet, you would say *mat* — confidently, and you would be right far more often than chance. You have, without trying, just done the single most important thing a modern compressor does: you *predicted* the next symbol and you were *not surprised* by it. A surprising symbol costs a lot to write down; an unsurprising one costs almost nothing. That trade is the whole game, and we proved it rigorously back in Volume I.

Now turn the screw. The machines that finish that sentence best are not compression programs at all. They are *language models* — the same systems behind the chat assistants that exploded across the world after 2022. They were never built to make files smaller. They were built to predict the next word. And yet, in 2023, a team at Google DeepMind froze one of these models, bolted an arithmetic coder onto it, and discovered that it was *the best lossless compressor ever measured* — not just on text, but on images it had never seen and audio it had never heard.

A program trained only on words, beating PNG on photographs. That is the puzzle of this chapter. By the end you will understand exactly why it happens, you will have built a tiny working version yourself, and — just as importantly — you will understand why it is not the free lunch it first appears to be.

#recap[
  This chapter is where two long threads of the book finally tie into one knot.

  - In *Chapter 18* we defined the *surprisal* of a symbol with probability $p$ as $-log_2 p$ bits, and the *entropy* $H(X) = -sum_i p_i log_2 p_i$ as the average surprisal — the theoretical floor on bits per symbol.
  - In *Chapter 26* we built *arithmetic coding*: a coder that, given a probability for each next symbol, spends essentially $-log_2 p$ bits on it, hitting that floor to within a fraction of a bit *for the whole message*.
  - In *Chapter 23* we proved the hinge identity *cross-entropy = expected code length*: a model's average $-log_2 p$ on real data is exactly the bits-per-symbol an arithmetic coder pays when driven by that model. A better predictor is a shorter file.
  - In *Chapter 61* we examined the grand claim that *compression is intelligence* as theory — Solomonoff, MDL, the Hutter thesis.

  This chapter makes all of that *concrete and operational*. The "model" in "model + coder" becomes a neural language model. We plug it into the very arithmetic coder we wrote in Chapter 26, and we watch the bytes melt.
]

#objectives((
  [State precisely why an autoregressive next-symbol predictor, fed into an arithmetic coder, is a lossless compressor — and why its file size equals the model's cross-entropy loss.],
  [Explain what an *autoregressive language model* and a *tokenizer* are, in plain terms, without any prior deep-learning knowledge.],
  [Recount DeepMind's 2023 result — a text model beating PNG and FLAC — and say exactly what it does and does not prove.],
  [Describe Fabrice Bellard's `nncp` (online) and `ts_zip` (pretrained) tools and the crucial *determinism* requirement that makes them work at all.],
  [Carry out the honest accounting — file bits *plus* model bits — and explain why a 140 GB model winning by a fraction of a bit is not obviously a victory.],
  [Build `tinyzip`'s `llmzip.py`: a real, round-tripping LLM-as-compressor demo driven by a tiny prediction model and the Chapter 26 arithmetic coder.],
))

== The bridge we already built: prediction is compression

Let us state the central identity once, slowly and completely, because everything else in the chapter is a consequence of it.

A lossless compressor that works *symbol by symbol* needs exactly one thing from a model: for each position $t$ in the message, a probability for what the next symbol will be, *given everything before it*. Write that as $p(x_t | x_1 x_2 dots x_(t-1))$ — "the probability of the symbol at position $t$, given the first $t-1$ symbols." The vertical bar $|$ is read "given"; we met it in Chapter 9 as *conditional probability*.

Feed those probabilities, one at a time, into the arithmetic coder of Chapter 26. The coder spends $-log_2 p(x_t | x_1 dots x_(t-1))$ bits on symbol $x_t$. Add up the cost over the whole message and the total compressed length is

$ L = sum_(t=1)^n -log_2 p(x_t | x_1 dots x_(t-1)) "  bits." $

That sum is the surprisal of the message under the model. Where the model is confident *and correct* — it puts probability $0.99$ on the symbol that actually appears — the term $-log_2 0.99 approx 0.014$ bits is almost nothing. Where the model is caught out — it gave the true symbol probability $0.001$ — it pays $-log_2 0.001 approx 9.97$ bits, a stiff fine. Good prediction is cheap; bad prediction is expensive. The coder is just the cash register; the model decides the prices.

#gomaths("Reading a sum that depends on its own past")[
  We met $sum$ (capital sigma, "add up these terms") in Chapter 11. The new wrinkle here is that the thing inside the sum at step $t$ depends on *all the symbols before* $t$. There is nothing mysterious about this — it just means we walk through the message left to right, and at each step the "context" we condition on grows by one symbol.

  Tiny example. Message `AB`. Step 1: the model, with empty context, predicts the first symbol; suppose it gives `A` probability $1/2$, costing $-log_2 (1/2) = 1$ bit. Step 2: the model, now *told the first symbol was `A`*, predicts the second; suppose conditioning on `A` it gives `B` probability $1/4$, costing $-log_2 (1/4) = 2$ bits. Total: $1 + 2 = 3$ bits. That is the whole sum, with $n = 2$.
]

Now look at how a language model is *trained*. Researchers show it mountains of real text and tune it to make the true next symbol as probable as it can — equivalently, to make its *surprise* on real text as small as possible. The quantity they minimize is the average of $-log p(x_t | "context")$ over the training data. That is called the *cross-entropy loss*, or *log-loss*, or *negative log-likelihood*. We proved in Chapter 23 that this average is *exactly* the expected number of (natural-log) units the arithmetic coder would pay.

So the two activities — "train a language model" and "shrink the arithmetic-coded file" — are *the same optimization*, differing only by which logarithm you use. Training reports its loss in *nats* (using the natural log, base $e$); compression cares about *bits* (base 2). The conversion is a single constant:

$ "bits" = "nats" / (ln 2) = "nats" times 1.4427 dots $

#keyidea[
  *Log-loss is expected code length in disguise.* A language model that reports a cross-entropy loss of $1.0$ nats per symbol is, by that very fact, a compressor that achieves $1.0 / ln 2 approx 1.443$ bits per symbol when paired with an arithmetic coder. Nobody has to *add* compression to a language model. Training one *is* building one. The arithmetic coder is the last twenty lines of glue.
]

#gomaths("Nats vs bits: same idea, different ruler")[
  A logarithm (Chapter 7) answers "what power do I raise the base to?" Information theory can use any base; the base is just the unit.

  - Base 2 → the answer is in *bits*. $-log_2 p$. This is what a file's size is measured in.
  - Base $e approx 2.718$ → the answer is in *nats* (natural units). $-ln p$. This is what neural-network training code reports, because the calculus of base-$e$ logs is cleanest.

  They differ by a fixed scale factor, because $log_2 p = (ln p)/(ln 2)$. Since $ln 2 approx 0.6931$, one nat $= 1/0.6931 approx 1.4427$ bits. A loss of $2.0$ nats/symbol is $2.886$ bits/symbol. Nothing deep — it is centimetres vs inches. But you *must* convert, or your file-size predictions will be off by 44%.
]

#checkpoint[
  A model is trained on English and reports a validation loss of $1.6$ nats per token. Roughly how many bits per token will it cost when used as a compressor, ignoring all overhead?
][
  $1.6 times 1.4427 approx 2.31$ bits per token. (For comparison, raw English text is often quoted near $1$–$1.5$ bits per *character*; whether $2.31$ bits per *token* is good depends entirely on how many characters a token covers — typically about four, so this is roughly $0.58$ bits per character, which would be excellent. Watch your units: per-token and per-character are different rulers, a trap we return to.)
]

== What is a language model, really?

We have used the phrase "language model" as if you already knew it. The Prime Directive forbids that. Let us build the idea from nothing, because it is simpler than its reputation.

=== Autoregressive: predict the next thing, forever

Imagine the world's most diligent autocomplete. You hand it some text so far — the *context* — and it returns a full *probability distribution* over what comes next: not one guess, but a number for *every possible* next symbol, all adding to 1. "Given `The cat sat on the `, the next word is `mat` with probability 0.31, `floor` with 0.12, `roof` with 0.04, …" and so on across its whole vocabulary.

That is *all* an autoregressive language model is: a function from a context to a probability distribution over the next symbol. "Auto-regressive" is a fancy word for "it feeds on its own output" — to generate a long passage, you sample one symbol, append it to the context, and ask again, marching forward one symbol at a time. The very same machine that *generates* text by predicting forward can *compress* text: instead of sampling the next symbol, we are *told* the next symbol (it is the data), and we hand its probability to the coder.

#gomaths("A probability distribution over a vocabulary")[
  In Chapter 9 a probability distribution was a list of non-negative numbers, one per outcome, summing to 1. Here the "outcomes" are the possible next symbols. If the vocabulary is just $\{A, B, C\}$, a distribution is three numbers like $(0.7, 0.2, 0.1)$ — `A` is likeliest, and $0.7 + 0.2 + 0.1 = 1$.

  A real language model has a vocabulary of tens of thousands of symbols, so each prediction is a list of tens of thousands of numbers, all $gt.eq 0$, summing to 1. The model's whole job is to make that list *good*: high numbers on symbols that really do tend to follow this context, low numbers on the rest. A "confident" model concentrates its mass on a few symbols; an "uncertain" one spreads it thin. Spread-thin means high entropy means an expensive file.
]

#definition("Autoregressive language model")[
  A function $p_theta$ that, given a context $x_1 dots x_(t-1)$, returns a probability distribution $p_theta(dot | x_1 dots x_(t-1))$ over the next symbol $x_t$ in a fixed vocabulary. The subscript $theta$ ("theta") stands for the model's *parameters* — the millions or billions of internal numbers, learned from data, that determine its predictions. We treat $p_theta$ as a black box: text in, probabilities out.
]

We are deliberately *not* opening that black box here. *How* the model turns context into probabilities — the neurons, the attention, the gradient descent — is the subject of Chapter 56's machine-learning primer and Chapter 57's learned codecs. For *this* chapter, the only property that matters is the contract in the definition: context in, a clean probability distribution out. Given that contract, Chapter 26's coder does the rest.

#aside[
  This is the deep reason the book put information theory (Volume I) before neural networks (Volume IV). A language model is "just" a model in the model-plus-coder picture we drew in Chapter 1. Everything we learned about good and bad models — that they must be *shared* by encoder and decoder, that their quality is measured in bits — applies unchanged. The neural net is a spectacularly good model. It is not a new *kind* of thing.]

=== The tokenizer: the alphabet the model actually sees

There is one wrinkle that turns out to matter enormously, and it is a classic place to get confused. A language model does not usually predict *letters* or *bytes*. It predicts *tokens*.

A *tokenizer* is a fixed, agreed-upon rulebook that chops text into chunks called tokens and assigns each chunk a number. Common words become a single token; rare words get split into several pieces. The string `compression` might be one token; `antidisestablishmentarianism` might be five. The model's "vocabulary" is the list of all possible tokens — often around 50,000 to 200,000 of them — and the model predicts a distribution over *that* list, not over the 256 possible byte values.

#gomaths("Why tokens, and why they complicate the bits")[
  Predicting tokens instead of bytes is mostly an efficiency trick: a sequence of 1,000 English words is maybe 1,300 tokens but 6,000 bytes, so the model handles a shorter sequence. But it muddies our accounting in two ways.

  First, *bits per token* and *bits per byte* are different units (the trap from the checkpoint above). To report a file's compression honestly we must divide the total bits by the number of *original bytes*, not the number of tokens.

  Second — and this is subtle — the tokenizer itself silently *does some compression* before the model ever runs, because frequent strings collapse to single tokens. Worse, a single byte string can sometimes be tokenized more than one way, so a careless scheme could even be ambiguous. Honest LLM compressors must pin the tokenizer down exactly, ship it on both sides, and either feed the model raw bytes or account for the tokenizer's contribution. DeepMind's cleanest experiments avoided the issue by having the model predict *raw bytes* directly — a 256-symbol vocabulary — precisely so that "bits per byte" meant exactly what it says.]

#pitfall[
  When you read "this LLM compresses to 0.8 bits per token," your guard should go up. A token can be one byte or fifteen. The only unit that lets you compare against gzip, PNG, or FLAC is *bits per original byte* (bpb) — total compressed bits divided by the count of bytes in the *uncompressed* file. Always convert to bpb before believing a headline. Confusing the two is the single most common way LLM-compression claims get inflated.
]

#misconception[that a language model "memorizes" text and that is why it can compress it.][
  Memorization is the wrong picture and would actually *defeat* compression. If the model had simply stored enwik9, you would need to ship enwik9 inside the model to decompress — net savings zero. What the model does is *generalize*: it learns the statistical regularities of language (and, as we will see, of images and audio) so well that on text it has *never seen* it is rarely surprised. Low surprise on novel data is exactly what drives the file size down. The compression is a measure of *understanding the distribution*, not of remembering the file.
]

== The headline result: a text model beats PNG and FLAC

In September 2023, Grégoire Delétang, Anian Ruoss, and colleagues at Google DeepMind posted a paper with a title that is also a thesis: *Language Modeling Is Compression* (arXiv:2309.10668; published at ICLR 2024). They did the obvious-in-hindsight experiment that nobody had cleanly nailed down before. They took *Chinchilla 70B* — a large language model trained on text — *froze it* (no further training, no peeking at the test data), and used its next-symbol probabilities to drive a standard arithmetic coder. To make the units honest, they had it predict raw bytes.

The numbers are worth stating exactly, because they are the empirical heart of the whole "compression = intelligence" program.

#table(columns: (1.6fr, 1fr, 1fr, 1fr), inset: 6pt, align: (left, right, right, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Data (1 GB scale)*], [*gzip*], [*LZMA2*], [*Chinchilla 70B*]),
  [enwik9 (Wikipedia text)], [≈ 3.1 bpb], [≈ 2.3 bpb], [*0.642 bpb*],
  [ImageNet patches], [58.5%], [—], [*43.4%*],
  [LibriSpeech audio], [—], [—], [*16.4%*],
)
#align(center, text(size: 8.5pt, fill: c-ink.lighten(25%))[
  Raw compression rates (lower is better). For images/audio the figure is percentage of raw size; PNG manages 58.5% on those image patches, FLAC 30.3% on that audio. Source: Delétang et al., 2024.])

Read the text row first. On *enwik9*, a full gigabyte of English Wikipedia, the frozen Chinchilla 70B reaches *0.642 bits per byte*. The everyday workhorse `gzip` (DEFLATE, Chapter 30) sits near 3.1; the strong general-purpose coder LZMA2 (Chapter 31) near 2.3. The language model roughly *quartered* gzip's output. On text, where you would expect a *text* model to shine, it does — emphatically.

But the rows that made jaws drop are the other two. *ImageNet patches* are little squares of photographs. *LibriSpeech* is recorded human speech. Chinchilla was never trained on either; it was fed the raw bytes of images and audio as if they were a foreign language. And it compressed the images to *43.4%* of their size — beating *PNG* (Chapter 44), a codec built by humans specifically for images, at 58.5%. It compressed the audio to *16.4%* — beating *FLAC* (Chapter 50), a codec built specifically for lossless audio, at 30.3%.

#fig([The universal-predictor pipeline: the same arithmetic coder is fed bytes from text, image, or audio; only the model-supplied probabilities differ. A general enough predictor beats the specialised codec for each modality.],
  cetz.canvas({
    import cetz.draw: *
    // sources
    rect((0, 2.0), (2.2, 2.8), fill: rgb("#eef4fb"), stroke: 0.6pt)
    content((1.1, 2.4))[text bytes]
    rect((0, 1.0), (2.2, 1.8), fill: rgb("#eef4fb"), stroke: 0.6pt)
    content((1.1, 1.4))[image bytes]
    rect((0, 0.0), (2.2, 0.8), fill: rgb("#eef4fb"), stroke: 0.6pt)
    content((1.1, 0.4))[audio bytes]
    // model
    rect((3.6, 0.7), (6.1, 2.1), fill: rgb("#e8f5ee"), stroke: 0.7pt)
    content((4.85, 1.65))[language]
    content((4.85, 1.25))[model $p_theta$]
    content((4.85, 0.9))[text(size: 7pt)[(frozen)]]
    // coder
    rect((7.5, 0.7), (9.6, 2.1), fill: rgb("#fbf3ec"), stroke: 0.7pt)
    content((8.55, 1.55))[arithmetic]
    content((8.55, 1.15))[coder]
    // output
    rect((10.9, 1.0), (12.6, 1.8), fill: rgb("#f4f6f8"), stroke: 0.6pt)
    content((11.75, 1.4))[bits]
    // arrows
    line((2.2, 2.4), (3.6, 1.7), mark: (end: ">"))
    line((2.2, 1.4), (3.6, 1.4), mark: (end: ">"))
    line((2.2, 0.4), (3.6, 1.1), mark: (end: ">"))
    line((6.1, 1.4), (7.5, 1.4), mark: (end: ">"))
    content((6.8, 1.65))[text(size: 7pt)[$p(x_t)$]]
    line((9.6, 1.4), (10.9, 1.4), mark: (end: ">"))
  }))

#keyidea[
  A model that has only ever read *text* out-compresses dedicated *image* and *audio* codecs on their own turf. Why is this even possible? Because images and audio, viewed as byte streams, are full of statistical regularity — neighbouring pixels are similar, sound samples drift smoothly — and a *sufficiently general* next-byte predictor exploits that regularity better than a hand-built, domain-specific codec does. The language model learned, from words, a very broad sense of "what byte sequences from the real world look like," and that generality transfers. This is the most vivid demonstration in the whole book that *a good enough predictor is a universal compressor*.
]

#algo(
  name: "LLM + Arithmetic Coding",
  year: "2023",
  authors: "Delétang, Ruoss, et al. (Google DeepMind); precursors: Knoll's lstm-compress (2015), Bellard's nncp (2019)",
  aim: "Lossless compression by driving an arithmetic coder with an autoregressive neural language model's next-symbol probabilities.",
  complexity: "Encode and decode: one full neural-network forward pass per symbol — orders of magnitude slower than classical coders.",
  strengths: "State-of-the-art ratios; fully general (text, image, audio as raw bytes); rides every advance in language modelling for free.",
  weaknesses: "Enormous fixed model cost; punishingly slow; fragile to non-determinism; the model can dwarf the data it compresses.",
  superseded: "An active 2024–2026 frontier, not superseded; specialised online coders (nncp) and tiny pretrained ones (ts_zip) explore the practical corners.",
)[
  The scheme is model-agnostic: *any* function that emits a valid next-symbol distribution can be the front end. Swap in a bigger or better-trained model and the ratio improves with no change to the coder. That clean separation — Chapter 1's model-plus-coder split — is exactly why the arithmetic coder we wrote in Chapter 26 needs *zero* modification to become a neural compressor.
]

#history[
  The idea did not spring from nowhere in 2023. Byron Knoll's `lstm-compress` and `cmix` had been mixing neural predictors into context-mixing compressors since the mid-2010s, and Matt Mahoney's PAQ lineage (Chapter 34) had long blended many models' predictions. What DeepMind added was *scale and clarity*: take a single, huge, off-the-shelf language model, change nothing about it, and report clean bits-per-byte across modalities. The result reframed *scaling laws* — the empirical curves showing that bigger models predict better — as compression curves: a bigger model is a better compressor, full stop. That reframing is the bridge from this chapter back to Chapter 61's theory and forward to the rest of the AI era.
]

== Bellard's tools: making it actually run

A paper proves a point; an engineer ships a program. Enter *Fabrice Bellard* — the prodigious French programmer behind FFmpeg, QEMU, the Tiny C Compiler, and a world-record computation of $pi$. Bellard turned the LLM-compression idea into two real, downloadable tools that sit at opposite ends of a fundamental design choice: *do you ship the model, or learn it on the fly?*

=== nncp: learn the file as you compress it (online)

Bellard's *nncp* (first released 2019) takes the *online* route. The neural network starts out *untrained* — knowing nothing — and *learns the file while it compresses it*. As it reads the data left to right, after each chunk it nudges its own parameters to predict that chunk better, so its predictions sharpen as it goes. The decompressor does the *identical* learning in lockstep: it starts from the same blank model, decodes a chunk, then performs the same parameter update, so encoder and decoder always hold the same model. Because both sides regenerate the model deterministically, *no model weights need be stored in the file at all*.

#gomaths("Online vs. pretrained, in one breath")[
  *Online* (nncp): model starts empty, both sides train it identically as the data streams by. Nothing to ship; the model cost is paid in *time*, not in stored bytes. The decompressor must redo every training step the compressor did — so it is exactly as slow as the compressor (a property classical coders never have).

  *Pretrained* (ts_zip, DeepMind's setup): a fixed model is trained once, frozen, and shipped to both sides. Fast to *use* per file, but the model is a large fixed cost that must already live on both machines.

  Same identity ($L = sum -log_2 p$) drives both; they differ only in *where the model comes from and who pays for it*.
]

nncp moved from an LSTM (a kind of recurrent network) to a *Transformer* in its v2 (January 2021), tracking the same architecture shift that powered the chat-model revolution. On Matt Mahoney's *Large Text Compression Benchmark* (Chapter 36 — `enwik8`/`enwik9`), nncp has long sat among the very best entries: the 2024 release (`nncp` v3.x) compresses *enwik8* to roughly *1.19 bits per byte* and *enwik9* to about *0.85 bits per byte* — figures competitive with, and at times beating, the elaborate hand-engineered context-mixing compressor *cmix* (Chapter 34). For a program with essentially no hand-coded knowledge of English, only the ability to learn, that is remarkable.

#aside[
  A subtlety worth savouring: nncp's online model *does* effectively get stored in the file — not as weights, but as the *bits it costs to teach the model from scratch as you go*. Early in the file the untrained model is surprised by everything and the coder pays dearly; later the trained model is rarely surprised and pays little. The "model size" is amortised across the whole file as up-front clumsiness. This is the *minimum description length* idea of Chapter 23 made literal: the file pays for both the model and the data, automatically.]

=== ts_zip: ship a small frozen brain (pretrained)

Bellard's *ts_zip* (2023–) takes the opposite, pretrained route, and engineers it for the real world. It ships a *frozen* language model — an *RWKV* model with about *169 million* parameters, an RNN-style architecture chosen because it is fast and has a small, fixed memory footprint — *quantized to 8 bits* per parameter to keep it compact. It arithmetic-codes text against that fixed model. Reported figures hover around *1.1 bits per byte* on `enwik8` and `enwik9` and on classic test files like `alice29.txt`. It needs a GPU and a few gigabytes of RAM, and on a high-end card it runs at *roughly 1 MB per second*.

That "1 MB/s" number deserves a flinch. We will return to it.

#algo(
  name: "ts_zip (Bellard)",
  year: "2023",
  authors: "Fabrice Bellard",
  aim: "Practical pretrained LLM text compressor: a small, frozen, deterministic RWKV model + arithmetic coding.",
  complexity: "≈ 1 MB/s on an RTX-4090-class GPU; ~4 GB RAM; one model forward pass per token.",
  strengths: "≈ 1.1 bpb on text — well past LZMA; small shippable model (~169M params, 8-bit); engineered for cross-hardware determinism.",
  weaknesses: "Needs a GPU; far slower than classical coders; tied to the exact model version (Bellard warns: 'no backward compatibility should be expected').",
  superseded: "Companion to nncp; both are active research-grade tools, not production replacements for zstd.",
)[
  The choice of an RNN-style RWKV model over a Transformer is deliberate: RWKV processes tokens with a fixed-size running state, so its per-token cost and memory do not balloon with context length, which matters when you must run the *same* model identically on both ends, possibly on different hardware.
]

=== The determinism trap

Here is a danger classical compression never had to think about, and it is the most important practical lesson in the chapter. Arithmetic coding is *unforgiving*: the decoder must compute the *bit-for-bit identical* probability the encoder used at every single step. If they differ even in the last decimal place, the decoder's interval drifts away from the encoder's, every subsequent symbol decodes wrong, and the file is *irrecoverably corrupt* — not slightly wrong, but garbage from the point of divergence onward.

Now recall that neural networks are floating-point machines (Chapter 13). Floating-point arithmetic is *not* associative — $(a + b) + c$ can differ from $a + (b + c)$ in the last bit — and different GPUs, different CPUs, different math libraries, even different thread counts can sum the same numbers in different orders and get answers that differ in the last bit. For ordinary AI that is invisible. For arithmetic coding it is *fatal*.

#pitfall[
  *A neural compressor is only as reliable as its determinism.* The encoder and decoder must produce *identical* probabilities to the last representable digit, on whatever hardware each happens to run. Bellard's hardest engineering in `ts_zip` was not the model — it was making that 169M-parameter network evaluate *reproducibly* across GPUs and CPUs. Get this wrong and your "compressed" file decodes to noise. This is why every serious neural codec pins the exact model version, the exact arithmetic, and warns loudly that old files may be unrecoverable if any of it changes.
]

#checkpoint[
  Why can a tiny floating-point discrepancy between encoder and decoder destroy an *entire* arithmetic-coded file, rather than just garbling one symbol?
][
  Because arithmetic coding (Chapter 26) encodes the *whole message as one shrinking interval*, and each symbol's decoding depends on the cumulative state built from *all previous* symbols' probabilities. One wrong probability nudges the interval off-track; from that point on, every symbol is decoded against the wrong sub-interval, so the corruption *cascades* through the entire remainder of the file. There is no per-symbol resynchronisation to save you.
]

== Build it: `tinyzip`'s LLM-as-compressor

Theory is cheap. Let us make a real one round-trip. The beauty of everything above is that we *already wrote the coder* in Chapter 26; all we must add is a model that emits a probability distribution for the next symbol, and a loop that wires it to the coder. We will use a *deliberately tiny, deterministic* model — an order-2 adaptive byte model, the very kind nncp uses in spirit but shrunk to fit on a page — so the whole thing runs in plain Python with no GPU and no gigabyte downloads, yet demonstrates the *exact* mechanism a 70-billion-parameter model uses.

#note[
  We use a tiny statistical model, not a real neural net, on purpose. A real LLM needs PyTorch, a GPU, and hundreds of megabytes of weights — none of which belong in a from-scratch teaching codec. But the *interface* is identical: our model exposes a next-symbol distribution and an `update(symbol)` step — exactly the contract a frozen Chinchilla or an online RWKV satisfies, and exactly the contract Chapter 26's coder already consumes. Swap our 40-line model for a neural one and the surrounding code is unchanged. *That substitutability is the whole point.*]

#project("Step 22 · `llmzip.py` — model P(next) + arithmetic coder")[
  This is the final `tinyzip` step of the neural volume (the canonical step from `TINYZIP.md`). We reuse the *exact* `ArithmeticEncoder`/`ArithmeticDecoder` from Chapter 26 (`tinyzip/arithmetic.py`) and the `container` from Chapter 17 (`tinyzip/container.py`), and we add `tinyzip/llmzip.py`: an autoregressive byte predictor wired to that coder. It round-trips and ships a self-test.

  The trick to reuse is to notice what Chapter 26's coder actually asks of its model. There, the `FrequencyModel` exposed exactly three things the coder calls — `cumulative(sym) -> (cum_low, cum_high, total)`, `find(scaled) -> sym`, and `update(sym)` — and the coder did *not care* where those numbers came from. That is the model-plus-coder split of Chapter 1 made literal: *anything* that answers those three questions can drive the coder unchanged. So our LLM-style model just has to answer the same three questions. We are not inventing a new coder interface; we are *implementing the one Chapter 26 already defined.*

  First, the model. An *order-2 context model* predicts the next byte from the previous two bytes. It is *adaptive*: it starts knowing nothing and learns the file as it reads — exactly nncp's online philosophy, in miniature. Every byte keeps a count of at least $1$ so nothing ever has probability zero (a zero would mean "infinitely surprising," $-log_2 0 = infinity$ bits — an uncodeable, coder-killing zero-width slice, exactly the reason Chapter 26's model also started every count at $1$).

  #gopython("Counting with a dict, and the .get / .setdefault fallback")[
    A `dict` (Chapter 16) maps keys to values. Here we map a *context* (the last two bytes, as a `tuple`) to a list of 256 counts — one tally per possible next byte. `counts.get(ctx)` returns the list for that context, or `None` if we have never seen it; `dict.setdefault(ctx, default)` returns the existing list or installs `default` and returns that. We use these so a brand-new context starts from flat counts instead of crashing.

    ```python
    counts: dict[tuple[int, int], list[int]] = {}
    ctx = (65, 66)                          # previous two bytes
    row = counts.setdefault(ctx, [1] * 256) # 256 ones = uniform prior
    row[67] += 1                            # we just saw byte 67 after this context
    ```
  ]

  ```python
  # tinyzip/llmzip.py — an LLM-as-compressor demo (tiny, deterministic model)
  from tinyzip.arithmetic import ArithmeticEncoder, ArithmeticDecoder, QUARTER

  class Order2Model:
      """Autoregressive byte predictor: P(next byte | previous two bytes).
      Answers the SAME three questions Chapter 26's FrequencyModel did
      (cumulative / find / update), so the Chapter 26 coder drives it as-is.
      Adaptive (learns online), pure-integer, deterministic. No EOF symbol:
      the container records the length, so the loops run for exactly n bytes."""

      def __init__(self) -> None:
          self.counts: dict[tuple[int, int], list[int]] = {}
          self.ctx: tuple[int, int] = (0, 0)

      def _row(self) -> list[int]:
          """The 256 counts for the current context (uniform if never seen)."""
          row = self.counts.get(self.ctx)
          return row if row is not None else [1] * 256

      @property
      def total(self) -> int:                  # the coder reads model.total
          return sum(self._row())

      def cumulative(self, sym: int) -> tuple[int, int, int]:
          """(cum_low, cum_high, total) for byte `sym` — the coder's narrowing."""
          row = self._row()
          low = sum(row[:sym])                 # counts strictly before sym
          return low, low + row[sym], sum(row)

      def find(self, scaled: int) -> int:
          """Inverse of cumulative: which byte's slice contains `scaled`."""
          row = self._row()
          cum = 0
          for sym in range(256):
              if cum + row[sym] > scaled:
                  return sym
              cum += row[sym]
          raise ValueError("scaled value out of range")

      def update(self, sym: int) -> None:
          row = self.counts.setdefault(self.ctx, [1] * 256)
          row[sym] += 1
          self.ctx = (self.ctx[1], sym)        # slide the 2-byte window
  ```

  Those three methods *are* the model-plus-coder contract. `cumulative` and `find` are an exact inverse pair (the slice that `cumulative` lays down is the slice `find` walks back), and `update` makes the just-seen byte likelier next time — and, crucially, *slides the context*, so the very next `cumulative`/`find` answers from a freshly-conditioned distribution. The whole "autoregressive" idea lives in that one line `self.ctx = (self.ctx[1], sym)`.

  #gopython("Integer frequencies, not floats — and why")[
    Notice the model never produces a probability like `0.31`. It hands the coder whole-number *counts* whose running total is `model.total`, and the coder turns a count of, say, `c` out of `total` into a cost of about $-log_2(c \/ "total")$ bits with pure integer arithmetic. This is deliberate: Chapter 26's coder is integer-only precisely to stay deterministic — exactly the floating-point trap this chapter warned about. A real neural model emits floats, so the real engineering step is to *quantise* those floats to integer frequencies the same way (the very thing `ts_zip` must do reproducibly across GPUs). Here we sidestep that by counting in integers from the start.
  ]

  Now the encode/decode loop. Because our `Order2Model` answers the same three questions as Chapter 26's `FrequencyModel`, we can hand it straight to the Chapter 26 coder's per-symbol primitives. The encoder, at each position, narrows the interval for the real next byte, then updates the model; the decoder mirrors it exactly — it recovers the byte from the interval, then performs the *same* update.

  ```python
  def llm_compress(data: bytes) -> bytes:
      model = Order2Model()
      enc = ArithmeticEncoder()
      for byte in data:
          enc._encode_symbol(model, byte)     # narrow interval; calls model.update
      enc.pending += 1                          # flush: pin a point in the interval
      enc._emit(1 if enc.low >= QUARTER else 0)
      return enc.out.flush()

  def llm_decompress(blob: bytes, n: int) -> bytes:
      model = Order2Model()
      dec = ArithmeticDecoder(blob)
      out = bytearray()
      for _ in range(n):                        # length comes from the container
          byte = dec._decode_symbol(model)      # recover byte; calls model.update
          out.append(byte)
      return bytes(out)
  ```

  #note[
    To keep this readable we lean on two small, mechanical refactors of the Chapter 26 coder, which that chapter already wrote as private helpers in spirit: `_encode_symbol(model, sym)` (its narrowing + renormalize body, already shown in Chapter 26) and a matching `_decode_symbol(model)` that performs one decode step (the inside of its `decode` loop). `QUARTER`, `enc.pending`, `enc._emit`, and `enc.out` are exactly the names defined in `arithmetic.py`. We drop the `EOF` symbol that Chapter 26 used to mark end-of-stream because the *container* already stores the original length, so `llm_decompress` simply runs the loop `n` times. Nothing about the interval math changes.
  ]

  #gopython("Mirrored loops: the round-trip invariant")[
    The two loops are *structurally identical*: ask the model, (encode or decode) one symbol, and let that step `update` the model. That symmetry is what guarantees `decode(encode(x)) == x`. The encoder knows the byte and spends bits; the decoder spends bits to learn the byte. Because both consult the model's distribution *before* the byte is known and `update` *after*, their models stay in lockstep, byte for byte. Break the symmetry — update before consulting on one side — and the streams desynchronise, exactly the failure mode this chapter warns about.
  ]

  Finally the self-test and a container-wrapped round trip. We reuse Chapter 17's `container`, whose signature is `write(path, method, payload, original_len)` and `read(path) -> (method, original_len, payload)` — it stores the original length, which is exactly the `n` the decoder needs:

  ```python
  METHOD_LLMZIP = 9                              # this codec's method byte

  def _selftest() -> None:
      import tinyzip.container as container
      sample = (b"the cat sat on the mat. " * 40
                + b"the cat ran to the mat. " * 40)
      packed   = llm_compress(sample)
      restored = llm_decompress(packed, len(sample))
      assert restored == sample, "round-trip failed!"
      ratio = len(packed) / len(sample)
      print(f"in {len(sample)}  out {len(packed)}  "
            f"ratio {ratio:.3f}  "
            f"bits/byte {8 * len(packed) / len(sample):.3f}")
      # also exercise the on-disk container path of Chapter 17
      container.write("demo.llz", METHOD_LLMZIP, packed, original_len=len(sample))
      method, n, payload = container.read("demo.llz")
      assert payload == packed and n == len(sample)

  if __name__ == "__main__":
      _selftest()
  ```

  Run it and the repetitive sample compresses dramatically — the order-2 model learns the handful of recurring contexts within the first few sentences and is barely surprised thereafter, so the coder pays almost nothing for the rest. That is *exactly* the mechanism behind the headline results, only here the "model" is 40 lines and there it is 70 billion parameters. The contract — `cumulative`, `find`, `update`, feed the very same coder — is identical.
]

#note[
  *Where would a real LLM plug in?* Replace `Order2Model`'s `cumulative`/`find` with a call into a frozen neural network that returns 256 byte-probabilities (or a token distribution, with the tokenizer caveats above), quantised to integer frequencies exactly as Chapter 26's coder expects. The coder, the loops, the container — all unchanged. The hard parts become *the model download* and *cross-hardware determinism*, not the compression logic. You have already built the compression logic.]

== The scoreboard, and a dose of honesty

Let us put the LLM line on the same scoreboard we have grown all book, on the kind of text sample `tinyzip` has been chewing through. The point is not that our toy order-2 model rivals Chinchilla — it does not — but to slot the *technique* into the lineage and show where the real frontier sits.

#scoreboard(caption: "cumulative, on representative English text (≈ bits/byte; lower is better)",
  [Raw (no compression)], [8.00 bpb], [1.0×], [the baseline; every byte costs 8 bits],
  [Huffman (Ch 24)], [≈ 4.5 bpb], [≈ 1.8×], [optimal per-symbol code; no context],
  [DEFLATE / gzip (Ch 30)], [≈ 3.1 bpb], [≈ 2.6×], [LZ77 + Huffman; the web's workhorse],
  [bzip2 / BWT (Ch 35)], [≈ 2.3 bpb], [≈ 3.5×], [block-sorting; strong on text],
  [LZMA2 / xz (Ch 31)], [≈ 2.3 bpb], [≈ 3.5×], [large dictionary + range coding],
  [cmix / context-mixing (Ch 34)], [≈ 1.0 bpb], [≈ 8×], [hundreds of mixed models; very slow],
  [`tinyzip` `llmzip` (toy)], [model-dep.], [—], [order-2 demo of the LLM mechanism],
  [nncp (online Transformer)], [≈ 0.85 bpb], [≈ 9.4×], [learns the file as it codes; nothing shipped],
  [Chinchilla 70B + AC], [*0.642 bpb*], [*≈ 12.5×*], [frozen text LLM; SOTA raw — but see below],
)
#align(center, text(size: 8.5pt, fill: c-ink.lighten(25%))[
  Figures are representative bits-per-byte on enwik-class English text and vary with file and version. The crucial column is missing on purpose: *the model's own size*. Read on.])

Those bottom rows look like a clean victory — gzip's 3.1 quartered to 0.642. But a victory it is only if you ignore three things, and intellectual honesty forbids ignoring them. This is the most important section of the chapter.

=== Honesty 1: the model is part of the file

A frozen LLM is not free. The decoder must *possess the entire model* to decompress anything at all. The genuinely fair number is therefore not the file's bits but the *adjusted* size: file bits *plus* model bits.

#theorem("Two-part code lower bound (informal)")[
  For a decoder that does not already possess the model, the honest description length of compressing a single file $D$ with a model $M$ is at least
  $ L_"honest" = underbrace(L(M), "bits to describe the model") + underbrace(L(D | M), "bits to code D using M") . $
  No accounting that omits $L(M)$ can be a true measure of how much information was conveyed.
]

#proof[
  To reconstruct $D$ from the compressed stream alone, a receiver who starts with nothing must be handed *both* the model and the model-coded data — there is no other source for $M$. So the total information transmitted is $L(M) + L(D | M)$. Omitting $L(M)$ assumes the receiver already has $M$ for free, which silently moves a (possibly enormous) cost off the books. This is precisely the *minimum description length* principle of Chapter 23, which insists a hypothesis be charged for *itself* as well as for the data it explains. $square$
]

Now run the numbers. Chinchilla 70B in 16-bit precision is about *140 gigabytes* of parameters. The file it so impressively compressed, enwik9, is *1 gigabyte*. The model is *140 times larger than the data*. By the honest two-part accounting, "compressing" a single 1 GB file by shipping a 140 GB model to do it is absurd — you would have been a thousand times better off e-mailing the raw file. The DeepMind authors are completely explicit about this: their off-domain wins are *real and important as science*, but they are *not* free-lunch single-file compression.

#keyidea[
  An LLM compressor only "pays for itself" when its huge fixed model cost is *amortised over an enormous amount of data* — so much that the per-file share of the model is negligible. Compress a *library*, and a 140 GB model spread over many terabytes is a rounding error. Compress *one document*, and the model is a catastrophe. This is exactly why Bellard's *169-million*-parameter ts_zip (a few hundred megabytes) is the *practical* sweet spot, not the 70-billion-parameter giant: it is small enough that a person might actually keep it installed and amortise it across everything they ever compress.
]

#misconception[that DeepMind's result means an LLM is, all-in, the world's best compressor of a given file.][
  Only if you do not charge for the model. The headline *0.642 bpb on enwik9* is the cost of coding the *data given the model*, $L(D | M)$ — it pointedly excludes the 140 GB of $L(M)$. As a *scientific measurement of the model's predictive quality* it is honest and stunning. As a *practical recipe to make your file smaller*, it is only sensible when the same model is reused across a vast corpus. Both statements are true at once; conflating them is how the hype outruns the reality.
]

=== Honesty 2: it is staggeringly slow

Classical coders move at the speed of memory. *zstd* (Chapter 32) compresses *hundreds of megabytes per second* on one ordinary CPU core. ts_zip manages *about 1 MB/s* — and that is *on a high-end GPU*. Full LLM coders driving 70-billion-parameter models are far slower still, because *every single byte or token costs a complete forward pass* through the network. You are spending three to six *orders of magnitude* more compute, and a correspondingly enormous amount of energy, to shave a fraction of a bit per byte off an already-good classical result.

#gomaths("Orders of magnitude: feeling the gap")[
  An *order of magnitude* is a factor of ten (Chapter 7's logarithms again). "Three orders of magnitude" is $10^3 = 1000$ times. If zstd does 500 MB/s and ts_zip does 1 MB/s, the gap is $500 times$ — between two and three orders of magnitude. To compress a 1 GB file: zstd, about *two seconds*; ts_zip, on a GPU, about *seventeen minutes*. For a marginal ratio gain on most workloads, that is a trade almost nobody should take — which is precisely why your phone still uses Brotli and zstd, not an LLM, to load this very web page.]

#pitfall[
  Do not let the gorgeous ratios seduce you into thinking LLM compression is ready to replace zstd in your backups or your web server. For the overwhelming majority of real workloads — where speed, energy, and the absence of a multi-gigabyte model dependency matter — classical coders win decisively. LLM compression is, today, a *research instrument and a niche tool*, not a daily driver. Knowing *when not to use* a technique is as much a mark of expertise as knowing how it works.]

=== Honesty 3: it is fragile

Lose the exact model, or run it on hardware that rounds even slightly differently, and the data is *gone forever* — the determinism trap, now with archival stakes. A file compressed with model version 1.3 may be undecodable by version 1.4. Bellard states the discipline bluntly for ts_zip: *"no backward compatibility should be expected."* For ephemeral or amortised use that is fine. For a *long-term archive* — the very thing the Hutter Prize (Chapter 36) is about — it is a serious liability that classical, fully-specified, model-free formats like gzip simply do not have. A gzip file made in 1993 still opens today; nobody can promise that of a file compressed against a particular checkpoint of a particular neural network.

#aside[
  This is why the dedicated *Hutter Prize* — which charges the *decompressor's own size and runtime* against you and demands the whole thing run within tight resource limits — is *not* topped by a giant LLM. Its October 2024 record was set by Kaido Orav and Byron Knoll's *fx2-cmix*, a hand-engineered context-mixing compressor reaching *110,793,128 bytes* on enwik9. nncp's *raw ratio* is superb, but once you must *pay for the model and the clock*, the elaborate-but-self-contained classical coder wins the prize. The prize's rules encode exactly the honest accounting of this section.]

== Compression as intelligence: the evidence and the limits

We opened by invoking the slogan *compression is intelligence*, which Chapter 61 examined as pure theory. This chapter gives it teeth — and then, in fairness, files them down.

The strongest *empirical* support is a 2024 paper by Yuzhen Huang, Jinghan Zhang, Zifei Shan, and Junxian He (HKUST/Tencent): *Compression Represents Intelligence Linearly* (COLM 2024). Across *31* publicly available language models from many different organisations, evaluated on *12* benchmarks spanning knowledge, coding, and mathematical reasoning, they measured each model's *bits per character* on held-out text and plotted it against the model's average benchmark score. The relationship was almost a *straight line*, with a Pearson correlation coefficient around *$-0.95$* — the better a model compresses, the higher its measured "intelligence," nearly without exception.

#gomaths("Pearson correlation $r$, and what $-0.95$ means")[
  The *Pearson correlation coefficient* $r$ is a single number between $-1$ and $+1$ that summarises how tightly two quantities move together along a straight line.

  - $r = +1$: a perfect upward line (one goes up, the other goes up, exactly).
  - $r = 0$: no linear relationship at all (a shapeless cloud).
  - $r = -1$: a perfect *downward* line (one goes up, the other goes *down*, exactly).

  Here one axis is *bits per character* (lower = better compression) and the other is *benchmark score* (higher = smarter). Better compression means *fewer* bits, so a smarter model has a *lower* bpc *and* a *higher* score — the two move in opposite directions, hence the *minus* sign. The magnitude $0.95$ (very close to 1) says the points hug that downward line astonishingly tightly. An $r$ of $-0.95$ across dozens of independently-built models is a strikingly strong, clean empirical signal.]

That is a genuinely surprising and weighty result. It says that learning to predict text efficiently — to compress it — *tracks* measured capability with near-linear fidelity, across models nobody coordinated. It is the best evidence we have that the slogan is more than a slogan.

#keyidea[
  *Better compression of text correlates almost linearly with measured intelligence.* This is the empirical backbone of the "compression = intelligence" program. It strongly supports one direction of the claim: *being intelligent implies compressing text well.* A capable model is, by that very capability, a good predictor and hence a good compressor.]

But — and Chapter 61 already warned us — a correlation in one direction is not an identity in both. The honest 2025–2026 consensus is careful. The evidence supports *intelligence $arrow.r$ good compression* (a smart model predicts text well). It does *not* establish the converse, *all intelligence $=$ compression*:

- *Some capability need not show up as predictable token statistics.* Out-of-distribution generalisation, multi-step reasoning that diverges from the training distribution, the use of tools and external memory — these may not register cleanly as lower bits-per-character on a held-out text corpus.
- *The correlation is measured on text.* It is about *language* modelling. Intelligence that is not primarily linguistic sits outside the measurement.
- *The brute economics cut against the slogan as a definition.* If being the world's best compressor requires a 140 GB model running at 1 MB/s, then "intelligence = compression" cannot be the *whole* story of intelligence, which is also about doing more with less — efficiency, transfer, the right answer the first time.

#misconception[that DeepMind's and Huang et al.'s results prove "intelligence is just compression."][
  They prove something more careful and, honestly, more interesting: *compression is a reliable measurable signature of capability.* A model that compresses text well is, with near-certainty, a capable model — that is the $r approx -0.95$ result, and it is real. But "X is a strong signature of Y" is not "X is identical to Y." Compression appears to be a *necessary* hallmark of capable language models, not a *complete definition* of intelligence. The identity *log-loss = code length* is exact and beautiful; the leap from there to *intelligence = compression* is a philosophical bet, not a theorem.]

Where does that leave us? With one of the most satisfying convergences in all of computing. A field that began with Morse counting dots and dashes (Chapter 2), that Shannon turned into mathematics in 1948 (Chapter 18), that spent fifty years inventing ever-cleverer hand-built coders (Volume II), has arrived — via the very same identity it started with, $L = sum -log_2 p$ — at the doorstep of artificial intelligence. The best compressor and the best predictor turned out to be the same machine. That is not the end of the story; it is a hinge. But it is a hinge worth pausing on.

#takeaways((
  [An autoregressive language model emits $p(x_t | "context")$; feed that to an arithmetic coder and you have a lossless compressor whose file size is exactly $sum -log_2 p$ — the model's cross-entropy. *Training a language model is building a compressor.*],
  [Log-loss in nats converts to bits-per-symbol by multiplying by $1 / ln 2 approx 1.4427$. Always report *bits per original byte*, never per token, to compare against gzip/PNG/FLAC.],
  [DeepMind's *Language Modeling Is Compression* (2023) used a frozen Chinchilla 70B to reach *0.642 bpb on enwik9* and — astonishingly — to beat *PNG* on images (43.4% vs 58.5%) and *FLAC* on audio (16.4% vs 30.3%) with a *text-only* model. A good enough predictor is a universal compressor.],
  [Bellard's *nncp* learns the file online (nothing shipped, ~0.85 bpb on enwik9); his *ts_zip* ships a small frozen RWKV-169M (~1.1 bpb, ~1 MB/s on a GPU). Both demand *bit-exact determinism* across hardware, or the file decodes to noise.],
  [Honest accounting charges *model bits + file bits*. A 140 GB model compressing a 1 GB file is only sensible amortised over a vast corpus — which is why tiny models are the practical sweet spot and why the Hutter Prize (won Oct 2024 by *fx2-cmix*, 110.8 MB) is *not* topped by giant LLMs.],
  [LLM compression is slow, fragile, and model-dependent: a research instrument and niche tool, not a replacement for zstd. Knowing *when not to use it* is part of the expertise.],
  [Huang et al. (COLM 2024) found bits-per-character correlates with benchmark "intelligence" at $r approx -0.95$ across 31 models — strong evidence that *intelligence implies good compression*, but not that *intelligence is nothing but* compression.],
))

== Exercises

#exercise("62.1", 1)[
  A language model reports an average validation loss of $0.95$ nats per token on English text. (a) Convert this to bits per token. (b) If, on this corpus, one token corresponds on average to $4.1$ bytes, what is the model's compression rate in *bits per byte*? (c) Is that better or worse than gzip's typical $approx 3.1$ bpb on text?
]
#solution("62.1")[
  (a) $0.95 times 1.4427 approx 1.37$ bits/token. (b) Each token covers $4.1$ bytes, so bits per byte $= 1.37 / 4.1 approx 0.334$ bpb. (c) Far better than gzip's $approx 3.1$ bpb — roughly a $9 times$ improvement in this idealised accounting. (Caveat: this ignores the model's own size and the tokenizer's contribution; it is the $L(D | M)$ term only.)
]

#exercise("62.2", 1)[
  Explain in two or three sentences, to a friend who has never heard of compression, why a model trained only on English text was able to compress *photographs* better than PNG, a codec built specifically for images.
]
#solution("62.2")[
  Photographs, stored as a stream of numbers, are full of predictable patterns — pixels next to each other are usually similar colours. The text model had learned, from language, a very broad sense of "what real-world data tends to look like," and that general talent for guessing the next number worked surprisingly well on image data too. PNG only knows a few fixed image tricks; the model's general prediction beat them. (Key point: compression is just good guessing, and a good-enough guesser is general.)
]

#exercise("62.3", 2)[
  The message `BANANA` is to be compressed with an order-1 model (predict the next byte from the *one* previous byte) that, in each context, starts with a count of 1 for each of the three symbols $\{A, B, N\}$ and adds 1 to a symbol's count after seeing it. Work out, symbol by symbol, the probability the model assigns to each *actual* next symbol of `BANANA`, and sum the surprisals $-log_2 p$ to get the total code length in bits. (Treat the first symbol as predicted from an "empty" context that is uniform over the three symbols.)
]
#solution("62.3")[
  Three symbols, so a fresh context starts $(A{:}1, B{:}1, N{:}1)$, total 3. Process `B A N A N A`:

  - `B` from empty context (uniform $1/3$): $p = 1/3$, surprisal $log_2 3 approx 1.585$.
  - `A` from context `B` (fresh, uniform $1/3$): $p = 1/3$, $approx 1.585$. Now `B`'s row has $A{:}2$.
  - `N` from context `A` (fresh, $1/3$): $p = 1/3$, $approx 1.585$. `A`'s row now $N{:}2$.
  - `A` from context `N` (fresh, $1/3$): $p = 1/3$, $approx 1.585$. `N`'s row now $A{:}2$.
  - `N` from context `A` (now $A{:}1, B{:}1, N{:}2$, total 4): $p(N) = 2/4 = 1/2$, surprisal $1.0$. `A`'s row now $N{:}3$.
  - `A` from context `N` (now $A{:}2, B{:}1, N{:}1$, total 4): $p(A) = 2/4 = 1/2$, surprisal $1.0$.

  Total $approx 1.585 times 4 + 1.0 + 1.0 = 6.34 + 2.0 = 8.34$ bits. The model started clueless and paid full price early, then began to learn the `A`→`N` and `N`→`A` alternation and paid less — the online-learning curve of nncp in miniature.
]

#exercise("62.4", 2)[
  In `tinyzip`, both `llm_compress` and `llm_decompress` consult the model's distribution (via `cumulative`/`find`) *before* the current byte is known, and the per-symbol step calls `model.update(byte)` *after*. Suppose a careless programmer changed the *decoder only* so that it called `model.update` on the *previously* decoded byte an extra time before decoding the next one. The encoder is untouched. Describe precisely what goes wrong and at roughly which symbol the output first diverges.
]
#solution("62.4")[
  The decoder's model would have advanced one update further than the encoder's, so its context (the sliding two-byte window) and its counts would be one step ahead. For the *very first* symbol there is no prior byte, so it might survive symbol 1, but from the *second* symbol onward the decoder's `cumulative`/`find` answer from a *different* distribution than the encoder used to narrow the interval. Since arithmetic decoding depends on matching distributions exactly, the decoder recovers a wrong byte at that point and every subsequent byte cascades into garbage — the round-trip invariant "consult the *same* distribution, then apply the *same* update," identical on both sides, is broken. This is a controlled illustration of the determinism trap.
]

#exercise("62.5", 2)[
  A team compresses a single 2 GB text archive using a frozen 50-billion-parameter model stored at 2 bytes per parameter, achieving $0.7$ bits per byte on the data. (a) What is the size of the model-coded data alone? (b) What is the model's size? (c) Under the honest two-part accounting $L(M) + L(D | M)$, what is the total, and how does it compare to just keeping the raw 2 GB file? (d) Over how large a *corpus* would the model need to be amortised before the model-coded approach beats raw storage?
]
#solution("62.5")[
  (a) $0.7$ bpb on $2 "GB" = 2 times 10^9$ bytes gives $(0.7 / 8) times 2 times 10^9 = 0.175 times 2 times 10^9 = 0.35 times 10^9$ bytes $approx 0.35$ GB of coded data. (b) $50 times 10^9$ params $times 2$ bytes $= 100 times 10^9$ bytes $= 100$ GB. (c) Total $approx 100.35$ GB versus $2$ GB raw — the two-part code is *fifty times larger* than just keeping the file. For a single file, catastrophic. (d) The model adds a fixed $100$ GB; each GB of data costs $approx 0.175$ GB coded versus $1$ GB raw, saving $0.825$ GB per GB. To repay $100$ GB of model you need $100 / 0.825 approx 121$ GB of data. Beyond roughly *120 GB of corpus*, the amortised model-coded approach finally beats raw storage. This is exactly why LLM compression only makes sense at corpus scale.
]

#exercise("62.6", 1)[
  Why does the Hutter Prize — which charges the size and runtime of the *decompressor itself* — fail to be won by a giant frozen LLM, even though such a model achieves a better *raw* bits-per-byte than the winning entry? Connect your answer to the two-part code $L(M) + L(D | M)$.
]
#solution("62.6")[
  The Hutter Prize scores essentially the *honest* two-part code: it counts the bits of the data *plus* the size of the decompressor (which, for an LLM coder, includes the model), and it enforces strict memory and time limits. A giant LLM has a superb $L(D | M)$ (low raw bpb) but a gigantic $L(M)$ (the model) and a punishing runtime, so its *total* score is poor and it likely violates the resource limits outright. The October 2024 winner, fx2-cmix (110.8 MB on enwik9), is a self-contained context-mixing compressor whose decompressor is small and fast — it optimises the *whole* $L(M) + L(D | M)$, which is what the prize actually measures, rather than just $L(D | M)$.
]

#exercise("62.7", 3)[
  Extend `tinyzip`'s `Order2Model` into an `OrderKModel` that conditions on the previous $k$ bytes (so $k = 2$ reproduces the current model). Discuss, without necessarily running it: as $k$ grows, what happens to (a) compression on a long repetitive file, (b) the memory used by the `counts` dict, and (c) the *early-file* cost before contexts have been seen? What does this trade-off have to do with the difference between a tiny online model and a giant pretrained one?
]
#solution("62.7")[
  Implementation sketch: store the context as a `tuple` of the last $k$ bytes (or, faster, an integer rolling hash); `cumulative`/`find`/`update` are otherwise unchanged — only the size of the context key grows. (a) Larger $k$ captures longer-range structure, so on long repetitive or structured text compression *improves* — up to a point. (b) But the number of *possible* contexts is $256^k$, so the `counts` dict can blow up; memory grows fast and most contexts are seen rarely or never. (c) With big $k$, almost every context is *new* early in the file, so the model is uniform (maximally surprised) for a long warm-up, paying full price — the "cold start" worsens. This is the *online model's* core tension: rich context needs data to populate it. A *giant pretrained* model sidesteps the cold start entirely — it arrives already knowing a vast distribution learned from terabytes — at the cost of being a huge fixed dependency that must be shipped and amortised. The trade between "learn it cheaply on the fly but start clueless" and "know everything up front but be enormous" is exactly nncp-vs-Chinchilla, in miniature.
]

#exercise("62.8", 3)[
  The identity *log-loss = expected code length* is exact. The slogan *intelligence = compression* is contested. Write a tight argument (a) for why the identity is genuinely a theorem and not a metaphor, and (b) for *one* concrete kind of intelligent behaviour that the bits-per-character measure of Huang et al. might fail to capture. Reference the relevant earlier chapters.
]
#solution("62.8")[
  (a) The identity is a theorem because of Chapter 23's result: for a model assigning probability $p(x_t | "context")$, an arithmetic coder (Chapter 26, achieving $approx -log_2 p$ per symbol to within a bounded constant for the whole message) produces a file of $sum -log_2 p$ bits, and the *expectation* of $-log p$ over the data-generating distribution *is* the cross-entropy that training minimises (Chapter 18). The two quantities are equal by the definition of expectation and the coder's near-optimality — not by analogy. (b) Many valid answers; one good one: *multi-step tool-augmented reasoning* — e.g., a model that solves a problem by calling a calculator or searching external memory. Its competence lives partly *outside* its own next-token statistics on a static held-out corpus, so its bits-per-character on that corpus need not reflect it; the model could be a mediocre raw predictor yet highly capable in deployment. This is the gap between *intelligence $arrow.r$ compression* (well supported, $r approx -0.95$) and *intelligence $=$ compression* (not established), the careful line Chapter 61 drew.
]

== Further reading

- Grégoire Delétang, Anian Ruoss, et al., *Language Modeling Is Compression*, ICLR 2024 — the headline paper: Chinchilla 70B beating PNG and FLAC. #link("https://arxiv.org/abs/2309.10668")[arXiv:2309.10668]
- Chandra Shekhara Kaushik Valmeekam et al., *LLMZip: Lossless Text Compression Using Large Language Models*, 2023 — an independent, concurrent demonstration of the LLM-plus-arithmetic-coder recipe. #link("https://arxiv.org/abs/2306.04050")[arXiv:2306.04050]
- Yuzhen Huang, Jinghan Zhang, Zifei Shan, Junxian He, *Compression Represents Intelligence Linearly*, COLM 2024 — the $r approx -0.95$ correlation across 31 models. #link("https://arxiv.org/abs/2404.09937")[arXiv:2404.09937]
- Fabrice Bellard, *NNCP: Lossless Data Compression with Neural Networks* and *ts_zip: Text Compression using Large Language Models* — the practical online and pretrained tools, with benchmark figures and determinism notes. #link("https://bellard.org/nncp/")[bellard.org/nncp] and #link("https://bellard.org/ts_zip/")[bellard.org/ts_zip]
- Matt Mahoney, *Large Text Compression Benchmark* — the enwik8/enwik9 leaderboard where nncp and the context-mixers are ranked. #link("http://mattmahoney.net/dc/text.html")[mattmahoney.net/dc/text.html]
- Marcus Hutter, *The Hutter Prize for Lossless Compression of Human Knowledge* — the prize that encodes the honest two-part accounting; fx2-cmix's October 2024 record. #link("http://prize.hutter1.net/")[prize.hutter1.net]

#bridge[
  We have just seen that the *running* of a giant model is the bottleneck — every byte costs a full forward pass, and the model itself is a multi-gigabyte millstone. That raises an irresistible question: can we compress *the model*? If a 140 GB network could be squeezed to a few gigabytes without losing its predictive power, the honest accounting of this chapter would shift dramatically, and neural compression — and neural inference everywhere — would get cheaper, faster, and far more portable.

  *Chapter 63* turns the compression lens *inward*, onto the network's own weights. We will meet *quantization* — storing each weight in 8, 4, or even fewer bits — through *GPTQ* and *AWQ*, and then push to the information-theoretic edge with *BitNet b1.58*, where every weight is one of just three values $\{-1, 0, +1\}$, costing $log_2 3 approx 1.58$ bits apiece. The compressor, at last, compresses itself.
]
