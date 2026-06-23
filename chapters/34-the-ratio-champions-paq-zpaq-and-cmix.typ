#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Ratio Champions: PAQ, ZPAQ, and cmix

#epigraph[
  I write these programs for the same reason other people climb Everest: because they are there,
  and because nobody has gone higher yet.
][Matt Mahoney, _The PAQ Data Compression Programs_]

Imagine a compression contest where the prize is half a million euros, the entry fee is months of
your life, and winning means your program takes three days to compress a single gigabyte — yet
serious computer scientists enter every year. That is the world of PAQ, ZPAQ, and cmix: the
ratio champions.

In Chapter 33 we met PPM and context mixing — the two big ideas that push lossless compression
beyond what dictionary coders can reach. We learned how to blend dozens of predictions with
logistic mixing, and how SSE (Secondary Symbol Estimation) refines the result. But that chapter
stopped short of naming the programs that took those ideas furthest and asked: just how good can
a compressor get if you throw away every constraint about speed?

This chapter answers that question. We will tour the PAQ family from its 2002 birth through a
two-decade arms race, understand ZPAQ's elegant solution to the archival problem, meet cmix and
its LSTM neural mixer, and sit with the philosophical claim that grips the field — that
compressing a Wikipedia dump really does mean understanding human knowledge.

#recap[
  Chapter 18 derived Shannon entropy as the theoretical minimum bits per symbol. Chapter 23
  proved the deepest insight: perfect prediction equals perfect compression. Chapter 26 gave
  us the arithmetic coder that turns any probability into the matching fraction of a bit.
  Chapter 33 built the predictor: PPM (Prediction by Partial Matching) with escape mechanisms
  for unseen contexts, and context mixing — running many models in parallel and blending their
  bit-level probabilities with logistic weights. We also introduced SSE, the calibration layer
  that corrects the blended probability after the fact. This chapter shows where that machinery
  leads when you let it run unconstrained.
]

#objectives((
  "Trace the PAQ family from PAQ1 (2002) through PAQ8 and its community branches.",
  "Explain what makes context mixing compressors so much stronger than PPM alone.",
  "Understand ZPAQ's self-describing archive format and why it solves the archival problem.",
  "Describe how cmix adds an LSTM neural mixer on top of classical context models.",
  "Read and reason about a minimal context-mixing sketch in Python.",
  "Explain the Hutter Prize rules, the enwik9 record progression, and why researchers take it seriously.",
  "Articulate the ratio-vs-speed wall and why these programs are not general-purpose tools.",
))

== From Theory to Arms Race

Chapter 33 ended with a theorem: if you can predict perfectly, you can compress perfectly. The
context mixing architecture gives every weapon a predictor could want — many models, each
capturing a different statistical pattern, all blended into one bit-level probability. In
principle, adding more models and training them longer always helps. In practice, it costs CPU
time and RAM.

The PAQ family is what happens when a community of compression enthusiasts decides that ratio
is the only thing that matters and speed can go whistle.

#history[
  Matt Mahoney started the PAQ line in January 2002 while working at Florida Tech (Florida
  Institute of Technology). His original 2000 paper, "Fast Text Compression with Neural
  Networks," showed that a simple feedforward network could beat order-5 PPM on small tests.
  PAQ1 — released on January 6, 2002 — implemented that idea as a real compressor. By PAQ6
  in 2003, dozens of outside contributors were sending patches. The result was one of the few
  open-source compression projects where the paper and the code co-evolved in public, driven by
  a community of enthusiasts on the Encode.su forum, with every decimal point of improvement
  celebrated.
]

=== PAQ's Core Recipe

Before going further, let us fix the architecture that all PAQ variants share.

A PAQ compressor works *bit by bit*, not byte by byte. For each incoming bit of data:

+ Several dozen to several hundred *models* each look at the recent data through their own
  lens — different context lengths, sparse contexts that skip positions, whole-word contexts,
  record-structure contexts — and each outputs a single number: its estimate of $P("next bit" = 1)$.

+ A *mixer* takes all those probabilities, transforms each one with the logistic function
  $s_i = ln(p_i \/ (1 - p_i))$ (the "log-odds stretch"), forms a weighted sum
  $S = sum_i w_i s_i$, and maps it back through the logistic to get one final probability $P$.

+ An *arithmetic coder* (the one from Chapter 26) encodes the actual bit against that
  probability, consuming approximately $-log_2 P$ bits if the bit was 1, or
  $-log_2 (1-P)$ bits if the bit was 0.

+ The *weights* $w_i$ are updated by gradient descent: the model that predicted the bit
  correctly gets its weight nudged up; the model that predicted wrongly gets nudged down. This
  happens after every single bit, so the mixer learns the reliability of each model on the fly.

#mathrecall[
  Chapter 33 built the two functions this whole chapter relies on. The *logit* (or *log-odds*)
  stretches a probability into a real number, $s = ln(P\/(1 - P))$; the *logistic function* (or
  *sigmoid*) squashes it back, $P = 1\/(1 + e^(-s))$. The point of working in log-odds space is
  that independent evidence simply _adds_ there ($s = s_1 + s_2$), which is exactly why a mixer
  sums the contributions of many models before converting back. We will use $s$ and $P$ in this
  sense throughout.

  *A quick refresher.* Model A says $P_1 = 0.8$, so $s_1 = ln(0.8\/0.2) = ln 4 approx 1.386$;
  model B says $P_2 = 0.6$, so $s_2 = ln(0.6\/0.4) = ln 1.5 approx 0.405$. An equal-weight mix is
  $S = (1.386 + 0.405)\/2 approx 0.896$, giving $P = 1\/(1 + e^(-0.896)) approx 0.71$ — both models
  agreed, so the blended prediction is stronger than either alone, but tempered by their
  uncertainty.
]

#keyidea[
  The arithmetic coder does not care *how* you computed the probability — it only cares that
  the probability is calibrated (i.e., when you say 80%, the bit really is 1 about 80% of the
  time). Context mixing's job is to produce the most calibrated possible probability by using
  every available clue. The more clues you use, the better the calibration, and the closer to
  the Shannon limit you get.
]

== The PAQ Family Tree

=== PAQ1 to PAQ6: Learning to Walk

PAQ1 (2002) used a small fixed-weight neural network with a handful of order-0 through
order-4 character models. Weights did not adapt; the mixing was static. The compression was
already competitive with the best PPM programs of the day, which surprised the field.

PAQ2 (2002) added SSE — Secondary Symbol Estimation. After the mixer produces its probability
$P$, a small lookup table indexed by $(P, "recent 2 bits")$ adjusts $P$ to remove systematic
biases. If the mixer historically said "70%" but the bit turned out to be 1 only 55% of the
time in that situation, SSE learns to correct 70% down toward 55%. This one addition dropped
the bits-per-character on English text noticeably.

By PAQ5 and PAQ6 (2003), the model roster had grown to include:

- *Order-N character contexts* (N = 0 through 7 or more): the last N bytes predict the next bit.
- *Sparse contexts*: contexts that skip bytes, e.g., the byte at position $-1$ and the byte at
  position $-3$, ignoring $-2$. These capture rhythmic structure (every other byte in certain
  binary formats, for example).
- *Word-level contexts*: the last 1–4 whole words, hashed to a table. English prose has
  strong word-gram statistics that character contexts miss.
- *Record contexts*: if the data looks like fixed-length records (a CSV table, for example),
  contexts that align to record boundaries compress the columnar redundancy.

Each model hashes its context to a position in a large count table, updates the count after
each bit, and reads off a probability. The mixer maintains one weight per model, updated after
every bit.

#aside[
  A PAQ model's count table is not stored as a raw count. A common trick is to store a *bit
  history* — a small state machine summary of the last few bits seen in this context — and
  map that history through a learned table to a probability. This is much more space-efficient
  than keeping full integer counts, because most contexts are seen only a handful of times.
  The state machine records "five 1s and two 0s, in this order" compactly, and a table converts
  that state to a probability calibrated over millions of training bits.
]

=== PAQ7: Logistic Mixing Arrives

PAQ7 (December 2005), released by Mahoney but incorporating ideas from contributors including
Alexander Rhatushnyak, replaced the old fixed-weight neural mixing with true logistic mixing
and gradient descent. This was the pivotal upgrade. Previous PAQ versions were already
outperforming PPM on most benchmarks, but PAQ7 made the improvement reproducible and
principled: each weight update is a small gradient step that minimizes the cross-entropy
between the model's prediction and the actual bit.

#gopython("Gradient descent in one line")[
  Gradient descent on cross-entropy loss, applied after every single bit, is the engine behind
  context mixing. Here is the key update rule in plain Python:

  ```python
  def update_weight(w: float, p: float, bit: int, eta: float = 0.01) -> float:
      """
      Nudge weight w to reduce prediction error.
      p  = current prediction (probability that next bit = 1)
      bit = the actual bit (0 or 1)
      eta = learning rate (how big a nudge)
      """
      # Gradient of cross-entropy loss w.r.t. the log-odds input:
      # dL/ds = p - bit    (p is current prob, bit is target)
      gradient = p - bit
      return w - eta * gradient
  ```

  If `p = 0.8` (predicted 1 with high confidence) but `bit = 0` (it was actually 0), the
  gradient is $0.8 - 0 = 0.8$: large, so the weight gets a big nudge downward. If `p = 0.52`
  and `bit = 1`, gradient is $-0.48$: weight nudges up. Over millions of bits, weights settle
  to values that reflect each model's true predictive power.
]

=== PAQ8 and the Community Sprint

PAQ8 (2006 onward) became the longest-lived branch and the platform for most community
experimentation. The key additions:

*Indirect contexts*: instead of hashing the context directly to a count, the hash maps to a
secondary table of histories, which then map to a probability. This indirection lets rare
contexts share statistical strength with structurally similar (but textually different)
contexts.

*Structured binary modeling*: PAQ8 added dedicated models for JPEG, BMP, WAV, EXE, and other
file formats. A JPEG model, for instance, knows the DCT block structure from Chapter 38 — even
before we get there in this book — and predicts bits in the AC coefficients using their known
statistical distribution. Pre-processing the data by sorting it, modeling it as a known format,
or applying a reversible transform before feeding it to the context mixer can dramatically
improve compression on mixed-content archives.

*Preprocessing chains*: text files are often converted to lowercase and word-tokenized before
compression, so the model sees "the" as a single unit rather than three characters with three
independent contexts. This reduces the vocabulary size and improves high-order statistics.

#algo(
  name: "PAQ8 context-mixing compressor",
  year: "2006 onward (active community development)",
  authors: "Matt Mahoney et al. (open-source community)",
  aim: "Maximize lossless compression ratio on mixed data by blending hundreds of bit-level models with adaptive logistic mixing and SSE post-processing.",
  complexity: "O(N · M) time where N = input bytes and M = number of models; space proportional to total table sizes (typically 256 MB–1 GB RAM).",
  strengths: "Best-in-class ratio on text and mixed data; fully adaptive (no separate training phase); open source with active community.",
  weaknesses: "Extremely slow (hours per gigabyte); high memory use; not suitable for streaming or time-sensitive applications; forward-incompatible archives.",
)[
  PAQ8 uses a cascade: character order-N models (N = 0..8) + sparse models + word models +
  indirect context models + format-specific models → logistic mixer → SSE table → arithmetic
  coder. Weights updated every bit by gradient descent. Output is a raw bit stream wrapped in a
  simple header; no standard archive format.
]

#pitfall[
  PAQ8 archives from 2006 are not guaranteed to decompress with PAQ8 from 2009. Different
  sub-versions (PAQ8a through PAQ8o and beyond) each used slightly different model sets, and
  there is no standard container format that records which version was used. If you archive
  critical data with PAQ8 and lose the original binary, you may not be able to recover it.
  This is exactly the problem ZPAQ was designed to solve.
]

=== The paq8hp Branches: Tuning for Wikipedia

As the Hutter Prize (discussed below) grew in prestige, a sub-branch called *paq8hp* (hp =
Hutter Prize) appeared, specialized exclusively for English Wikipedia XML. Alexander
Rhatushnyak and others added preprocessing steps that exploit Wikipedia's specific structure:

- *Article reordering*: similar articles (by subject, by first-letter, or by topic cluster)
  are sorted together so that repetitions across nearby articles get captured by the sliding
  context window.
- *HTML/XML stripping*: wikitext markup is partially parsed and handled by dedicated models.
- *UTF-8 aware contexts*: character contexts that align to Unicode code-point boundaries
  rather than byte boundaries, so that multi-byte characters are not split mid-symbol.

These specializations improve the ratio on Wikipedia but hurt performance on arbitrary data.
The paq8hp series won multiple Hutter Prize cycles between 2006 and 2017, demonstrating that
knowing something about your data's format is as valuable as having a better general algorithm.

== ZPAQ: The Archival Solution

The PAQ family's Achilles heel was stability: every PAQ8 sub-version produced archives that
only its own version could decompress. If the source code was lost, the archive became
unreadable. Matt Mahoney addressed this in 2009 with ZPAQ.

=== The Self-Describing Archive Idea

ZPAQ's central innovation is simple to state and profound in its consequences: *embed the
decompressor's description inside every archive it creates*.

A ZPAQ archive does not just contain compressed data. Each block in the archive begins with a
header that describes — in a compact bytecode called *ZPAQL* — exactly how to decompress the
bytes that follow. A single fixed ZPAQ reader program, written once in 2009 and unchanged since,
can parse that bytecode and run it. Future improvements to the compression algorithm can be
embedded in new archives without changing the reader, because the reader does not need to
understand the algorithm — it just needs to execute the bytecode.

#keyidea[
  ZPAQ separates the *format* (stable, defined in 2009) from the *algorithm* (can change
  arbitrarily in each archive). The fixed reader plays the role of a universal virtual machine;
  the algorithm is a program stored in the archive's header. This means a ZPAQ file compressed
  in 2030 with an algorithm not yet invented can be decompressed by the 2009 reader, as long as
  the 2030 algorithm is expressed in ZPAQL bytecode.
]

=== The ZPAQL Virtual Machine

ZPAQL is a tiny assembly language with:

- Eight general-purpose registers (`A`, `B`, `C`, `D`, `I`, `J`, `U`, `F`).
- A random-access memory array.
- A context model description: an ordered list of components (CM = context model, ISSE =
  indirect SSE, mixer, SSE, ICM = indirect context model, etc.), each with a context
  computation function written in ZPAQL.
- An optional post-processing transform (also in ZPAQL) for preprocessing like UTF-8
  normalisation or E8E9 x86 address remapping.

On x86 hardware, the ZPAQ reader JIT-compiles the ZPAQL bytecode to native instructions,
roughly doubling speed. (JIT, "just-in-time" compilation, means translating the bytecode into
real machine instructions the first time it runs, instead of re-interpreting each instruction
every time — a one-off cost that pays for itself over billions of bits.) On other hardware, it
interprets. Either way, the output is identical.

To make this concrete: a single component in a ZPAQL model might say "compute my context as a
hash of the last two bytes, look it up in a $2^22$-entry table, and report the probability stored
there." Written out, that is a handful of ZPAQL instructions — load the previous byte into
register `A`, combine it with the byte before, multiply by a hashing constant, mask down to 22
bits, and use the result as a table index. The reader never knows or cares that those bytes spell
"an order-2 context model"; it simply executes the instructions. Because the _description_ of the
model travels inside the archive, the same reader runs an order-2 model today and some far more
elaborate model written years from now without a single change to the reader's own code.

#aside[
  The ZPAQL architecture is one of the rare cases where a compression format is
  *Turing-complete* in its header — meaning its little bytecode language is powerful enough to
  express _any_ computation a general computer can perform, given enough memory and time. Any
  algorithm that can be expressed as a program — including,
  in principle, a neural network or an LLM — could be described in ZPAQL and stored in a ZPAQ
  archive. In practice, ZPAQL programs are small (a few kilobytes of bytecode), but the
  principle is important: the format never becomes obsolete, because the algorithm is not
  hardcoded.
]

=== ZPAQ's Compression Performance

ZPAQ's compression engine closely mirrors PAQ8's context-mixing architecture, described in its
2015 technical paper. On English text corpora, ZPAQ with a high-ratio setting typically
compresses within 1–3% of the best PAQ8 sub-versions, while being far more archivally sound.
ZPAQ 7.15 (December 2016, Mahoney's final public release) includes:

- Journaling (incremental backup) mode, where only changed files are stored.
- AES-256 encryption of the payload.
- Deduplication within the archive.
- Multi-threaded decompression.

The ratio trade-off: at ZPAQ's highest setting, compressing 100 MB of English text takes
roughly 30–60 minutes on a modern CPU, versus under 1 second for gzip and about 10 seconds
for xz. The ratio improvement over xz is typically 5–15%.

#algo(
  name: "ZPAQ",
  year: "2009 (format); final release 7.15 in 2016",
  authors: "Matt Mahoney",
  aim: "Forward-compatible archival compression: embed the decompression algorithm in the archive so any future ZPAQ reader can decompress any ZPAQ archive.",
  complexity: "Comparable to PAQ8 for the compression engine; O(N) for the fixed reader.",
  strengths: "Archival stability (decompressor description in the archive); journaling/backup mode; AES-256 encryption; competitive PAQ-class ratios.",
  weaknesses: "Still slow; the ZPAQL virtual machine adds overhead; limited third-party tool support; Mahoney retired development in 2016.",
)[
  ZPAQ = ZPAQL bytecode header (describes the model) + compressed payload (PAQ-class context
  mixing). A single fixed reader binary can decompress any ZPAQ archive, past or future, because
  the model is stored inside the archive, not hardcoded in the reader.
]

== cmix: The Current Ratio Crown

If ZPAQ traded a little ratio for archival soundness, cmix went the other direction entirely:
throw every idea at the wall and accept that the result is spectacularly slow. Byron Knoll
began work on cmix in December 2013. The name stands for *context mix* — a straightforward
description of the architecture.

=== The cmix Architecture

cmix is a classical context mixer with one addition that changed everything: *an LSTM (Long
Short-Term Memory) neural network as one of the mixing inputs*.

#gomaths("LSTM (Long Short-Term Memory) networks, briefly")[
  An LSTM is a type of recurrent neural network — a network with a hidden state that carries
  information from one step to the next. At each step, it receives the current input and its
  own previous hidden state, and outputs both a new hidden state and a prediction.

  Unlike a simple recurrent network, an LSTM has three *gates* — learned switches that control
  what to remember, what to forget, and what to output. This lets it remember patterns over
  long distances (hundreds or thousands of steps back) without the "vanishing gradient" problem
  that makes simple RNNs forget quickly.

  *In compression terms*: at each bit position, the LSTM receives recent bits and its own
  history, and outputs $P("next bit" = 1)$. Because it can maintain state over thousands of
  bits, it captures long-range patterns that fixed-order context models miss — the statistical
  signature of a whole paragraph, a recurring phrase, or even the writing style of an article.
  This comes at enormous cost: updating an LSTM on every bit requires a full forward and
  backward pass through the network, which is why cmix is several times slower than PAQ8 — and
  PAQ8 was already slow.
]

cmix's full model ensemble (version 21, 2023) includes:

- Order-1 through order-14 character contexts.
- Sparse contexts at offsets up to 200 bytes back.
- Whole-word and word-pair contexts.
- Run-length contexts (what was the last repeated byte?).
- Indirect context models (ICM): context hashes two levels deep.
- *LSTM mixer*: a byte-level LSTM network trained online by backpropagation-through-time —
  the standard way of updating a recurrent network's weights, which works by unrolling the
  network over the last several steps and pushing the error backwards through that unrolled
  chain. This is the component that makes cmix qualitatively different from all earlier context
  mixers.

The LSTM does not replace the context models; it operates alongside them. All models —
character contexts, sparse models, and the LSTM — feed into a final logistic mixer whose
weights are updated after every bit. The LSTM captures patterns too long-range for any
context model; the context models capture patterns too local for the LSTM's gradients to
converge on quickly.

#algo(
  name: "cmix",
  year: "2013–present",
  authors: "Byron Knoll (primary); Kaido Orav and others for Hutter Prize variants",
  aim: "Achieve the best possible lossless compression ratio by combining classical context models with an online-trained LSTM neural network in a logistic mixing framework.",
  complexity: "O(N · (M + L)) where M = number of classical models and L = LSTM forward-pass cost; L dominates. Typical: ~500× slower than gzip on the same data.",
  strengths: "Best lossless compression ratio known for English text; fully adaptive; open source.",
  weaknesses: "Extremely slow (days for 1 GB); requires 4–16 GB RAM; practical only for benchmarking or archiving irreplaceable data where decode speed is acceptable.",
)[
  cmix layers: (many context models) + (LSTM predictor) → logistic mixer (gradient-descent
  weights, updated every bit) → SSE calibration table → arithmetic coder. All training is
  online, with no pre-trained weights. Result: best-known ratio on enwik9 and most text corpora.
]

=== A Minimal Context-Mixing Sketch in Python

The full cmix codebase runs to thousands of lines of C++. But the essential logic — multiple
models, logistic mixing, weight update — fits in a small Python sketch. The version below is
deliberately simplified (order-1 and order-0 models only, no SSE, no LSTM) so you can read
and run it:

```python
import math

def logit(p: float) -> float:
    """Map probability p to log-odds space."""
    p = max(1e-8, min(1 - 1e-8, p))     # clamp away from 0 and 1
    return math.log(p / (1.0 - p))

def sigmoid(s: float) -> float:
    """Map log-odds s back to probability."""
    return 1.0 / (1.0 + math.exp(-s))

class OrderNModel:
    """Adaptive order-N character model (returns P(next bit = 1))."""
    def __init__(self, order: int) -> None:
        self.order = order
        self.counts: dict[tuple[int, ...], list[int]] = {}  # context -> [n0, n1]
        self.ctx: list[int] = []

    def predict(self) -> float:
        key = tuple(self.ctx[-self.order:]) if self.order > 0 else ()
        n0, n1 = self.counts.get(key, [1, 1])   # start at 50/50 (Laplace)
        return (n1 + 0.5) / (n0 + n1 + 1.0)

    def update(self, bit: int) -> None:
        key = tuple(self.ctx[-self.order:]) if self.order > 0 else ()
        pair = self.counts.setdefault(key, [1, 1])
        pair[bit] += 1
        self.ctx.append(bit)   # note: in a real compressor, context is bytes not bits

class ContextMixer:
    """Minimal logistic context mixer."""
    def __init__(self, models: list[OrderNModel]) -> None:
        self.models = models
        self.weights = [1.0 / len(models)] * len(models)   # start equal

    def predict(self) -> float:
        s = sum(w * logit(m.predict()) for w, m in zip(self.weights, self.models))
        return sigmoid(s)

    def update(self, bit: int, eta: float = 0.05) -> None:
        p = self.predict()
        for i, m in enumerate(self.models):
            pi = m.predict()
            # Gradient of cross-entropy w.r.t. weight i:
            self.weights[i] -= eta * (p - bit) * logit(pi)
            m.update(bit)

def compress_bits(data: bytes) -> tuple[int, int, float]:
    """Count total bits used by the mixer on `data` (demo — does not emit a bit stream)."""
    models = [OrderNModel(0), OrderNModel(1), OrderNModel(2)]
    mixer  = ContextMixer(models)
    total_bits = 0.0
    for byte in data:
        for shift in range(7, -1, -1):
            bit = (byte >> shift) & 1
            p   = mixer.predict()
            # Shannon cost of coding this bit:
            total_bits += -math.log2(p if bit else (1 - p))
            mixer.update(bit)
    return len(data) * 8, round(total_bits), total_bits / len(data)

if __name__ == "__main__":
    sample = b"the quick brown fox jumped over the lazy dog " * 20
    raw_bits, coded_bits, bpc = compress_bits(sample)
    print(f"Raw bits  : {raw_bits}")
    print(f"Coded bits: {coded_bits}  ({bpc:.3f} bpc)")
    print(f"Savings   : {100*(1 - coded_bits/raw_bits):.1f}%")
```

Running this on a repeated English sentence gives roughly 3–4 bits per character — a big
improvement over the 8 bits/character of raw storage, achieved with just three tiny adaptive
models. A real PAQ8 or cmix compressor runs hundreds of such models, plus sparse models, word
models, and an LSTM, pushing the number below 2 bits per character on natural English.

#checkpoint[
  In the `ContextMixer.update` method above, what happens to `weights[i]` if model `i`
  predicted a 1 (high `logit(pi)`) but the actual bit was 0?
][
  The gradient `(p - bit)` is positive (since `p` is close to 1 and `bit = 0`). The weight
  update is `weights[i] -= eta * positive * positive`, so the weight decreases. The mixer
  learns to trust model `i` less when it confidently predicts the wrong answer.
]

== The Hutter Prize and the Enwik9 Leaderboard

=== The Problem of Measurement

How do you compare compressors that trade speed for ratio? You need a fixed test set,
fixed resource limits, and an objective score. The compression community solved this with
*corpora* — standard datasets on which every compressor is measured. The Calgary corpus
(1987), the Canterbury corpus (1997), and the Silesia corpus (2003) each defined an era.
Chapter 36 gives the full history; here we focus on the corpus that emerged specifically for
the ratio-champion class: *enwik9*.

=== Enwik8 and Enwik9

Matt Mahoney created the *Large Text Compression Benchmark* (LTCB) in 2006, based on
*enwik8* — the first 100 million bytes (100 MB) of an English Wikipedia XML dump. The choice
of Wikipedia was deliberate: to compress it well, your model must learn English grammar,
factual patterns, markup structure, and inter-article references. It is a proxy for general
knowledge rather than random bytes.

*Enwik9* is the first 1 billion bytes (1 GB) of the same dump, added later as RAM and
compute improved. Most serious Hutter Prize competition now happens on enwik9.

The uncompressed enwik9 is exactly 1,000,000,000 bytes. Using gzip (the baseline every reader
knows from Chapter 30): approximately 323 MB. Using xz at level 9 (Chapter 31): approximately
253 MB. The PAQ/cmix family: below 111 MB. Stretching from 323 MB to 111 MB is the distance
from "good" to "the best humanity can do algorithmically, as of 2024, with a single CPU."

=== The Hutter Prize Rules

In August 2006, Marcus Hutter (Researcher at DeepMind, formerly ANU; creator of the AIXI
theory we first encountered in Chapter 22) announced the Hutter Prize — formally "500,000 €
for Compressing Human Knowledge."

The rules, carefully designed to prevent cheating:

+ *Data*: enwik9 — the first 1 GB of a specific Wikipedia XML dump, SHA-256 verified.
+ *Self-extracting*: the submission must be a single self-extracting executable. The
  decompressor is included in the compressed file itself, so that the total size (compressor +
  compressed data) is what counts.
+ *Resource limits*: the self-extractor must reproduce enwik9 in under 50 hours on a
  reference CPU (a single core), using at most 10 GB of RAM and 100 GB of disk. No GPU.
+ *Open source*: the source code must be released under a free license.
+ *Prize*: €500 per 0.1% improvement, or equivalently €5,000 per 1% improvement over the
  standing record. The total prize pool is €500,000.

The resource limits are crucial. They prevent the trivial solution of pre-training a giant
language model on enwik9 and embedding it as a lookup table. The compressor must learn
everything from the data itself, within 50 hours. (An LLM with weights pre-trained on the
broader internet would fail the "no pre-computed knowledge" implicit in the spirit of the
prize, though the rules do not explicitly forbid including a small trained model as long as
the total compressed size counts. This ambiguity became relevant by 2025.)

#history[
  Marcus Hutter's motivation was not just to find a good compressor. His 2007 paper with Shane
  Legg, "Universal Intelligence: A Definition of Machine Intelligence," defined intelligence as
  the ability to achieve goals in a wide range of environments — and showed this is mathematically
  equivalent to compression: a more intelligent agent finds shorter programs for more strings.
  The Hutter Prize is therefore a bet: if you can compress a Wikipedia dump better than anyone
  else, you have, in a precise sense, more machine intelligence. The prize is a provocation as
  much as a competition.
]

=== The Record Progression

#scoreboard(
  caption: "Hutter Prize enwik9 record progression (selected milestones).",
  [*Year*], [*Winner*], [*Program*], [*Bytes (enwik9)*], [*bpc*],
  [2020 baseline], [—], [reference bzip2-class], [116,671,095], [0.933],
  [2021], [Artemiy Margaritov], [starlit], [~115,100,000], [0.921],
  [2023 Feb], [Saurabh Kumar], [fast-cmix], [114,156,155], [0.913],
  [2024 Aug], [Kaido Orav], [fx-cmix], [112,578,322], [0.900],
  [2024 Sep], [Kaido Orav + Byron Knoll], [*fx2-cmix*], [*110,793,128*], [*0.886*],
)

The September 2024 record — *fx2-cmix* at 110,793,128 bytes, awarded €7,950 to Kaido Orav
and Byron Knoll — compresses enwik9 from 1,000,000,000 bytes to 110,793,128. That is a ratio
of 9.02:1 on 1 GB of Wikipedia text, with a self-extracting decompressor included.

The techniques that fx2-cmix added over base cmix included:

- *Article reordering*: Wikipedia articles are reordered so that topically related articles
  are adjacent. Each article is first turned into a list of numbers summarising its vocabulary
  (an _embedding_), and a technique called t-SNE — a standard way of squashing such
  high-dimensional summaries down onto a single line while keeping similar items near each
  other — assigns every article a position. Sorting by that position puts articles about, say,
  chemistry next to one another, so the context mixer sees similar vocabulary in nearby
  positions. This is essentially the same idea the paq8hp branch discovered, now done
  efficiently enough to fit the time limit.

- *Selective weight updates*: the gradient-descent mixer skips weight updates when the
  prediction error is below a threshold. This saves CPU time with minimal ratio loss, allowing
  more complex models to run within the time budget.

- *Improved LSTM architecture*: layer normalisation (rescaling the network's internal numbers
  at each layer so training stays numerically stable), the Adam optimiser (which adapts the
  learning rate per weight), and a tuned embedding dimension.

As of June 2026, the fx2-cmix record still stands as the official awarded enwik9 champion.
Experimental work by Byron Knoll in early 2026 explored TPU-accelerated neural mixing, but
the prize committee was still deliberating whether GPU/TPU entries comply with the spirit of
the CPU-only resource limits.

=== How Many Days Does It Take?

To compress enwik9 with fx2-cmix: approximately 2–4 days on a single CPU core. To
decompress: approximately the same. These numbers are not a bug or an oversight. They are an
intentional consequence of the prize rules: you get 50 hours of compute, and the teams use
all of it.

Compare:
- *gzip* (Chapter 30): compress 1 GB in about 5 seconds, decompress in 2 seconds.
- *xz -9* (Chapter 31): compress in about 10 minutes, decompress in 15 seconds.
- *zstd --ultra -22* (Chapter 32): compress in about 5 minutes, decompress in 0.3 seconds.
- *cmix / fx2-cmix*: compress in 2–4 days, decompress in 2–4 days.

This is the ratio-vs-speed wall. The ratio champions buy every percentage point of compression
with orders of magnitude of compute.

== Anatomy of a PAQ-Class Bit

Let us slow down and walk through exactly what happens when a PAQ8-class compressor encodes
one single bit. Understanding one bit is understanding the whole system.

Suppose we are encoding an English text file and we have just seen the bytes `the ` (the word
"the" followed by a space). The compressor is about to encode the first bit of the next byte.

*Step 1: Each model computes its context and makes a prediction.*

- The order-1 model sees the last byte: space (0x20). It has seen spaces about 14% of the
  time in English, and after a space, the first bit of the next byte is more likely to be 0
  (because most ASCII letters in the range 97–122 have 0 as their first bit). Prediction: $P("bit" = 0) approx 0.72$.

- The order-4 model sees ` the ` (space + "the" + space). It knows common words that follow
  "the ": "quick", "lazy", "dog", "first", … Starting with 'a'–'n' (bit = 0) or 'o'–'z'
  (bit = 0 also in ASCII). Prediction: $P("bit" = 0) approx 0.78$.

- The word-2 model has counted the last two whole words. Suppose the previous words were
  "over" and "the". It has seen "over the" many times and knows what words tend to follow.
  Prediction: $P("bit" = 0) approx 0.81$.

- A sparse model that looks at bytes at offsets $-1$ and $-4$ (space and "h") makes its own
  estimate based on that specific pairing.

*Step 2: The mixer takes all predictions and forms a weighted average in log-odds space.*

Each $P_i$ is mapped to $s_i = ln(P_i \/ (1-P_i))$. The weights $w_i$ were set by past
gradient descent. A weighted sum $S = sum_i w_i s_i$ is computed and mapped back to a
probability $P_"mixed"$.

*Step 3: SSE calibrates the result.*

The mixed probability $P_"mixed"$ and a small secondary context (perhaps the last 2 bits
seen) are used to look up an entry in a calibration table. The entry was built by tracking
how often the actual bit matched a given $P_"mixed"$ in the past and adjusting. If the mixer
tends to overestimate confidence (says 85% and is right only 78% of the time), SSE corrects
downward.

*Step 4: The arithmetic coder emits the bit.*

Using the final probability from SSE, the arithmetic coder (Chapter 26) encodes the bit,
consuming approximately $-log_2(P_"SSE")$ bits if the bit is 0. Because $P_"SSE"$ is close
to 1 (the models are confident), this cost is well below 1 bit — perhaps 0.3 bits.

*Step 5: All models and weights are updated.*

Every model increments its count table. Every weight in the mixer is nudged by gradient
descent. The SSE table entry is adjusted. Then the compressor moves to the next bit.

This five-step cycle runs *once per bit*, roughly 8 billion times for a 1 GB file. The total
cost in floating-point operations explains why compression takes days.

== The Ratio-vs-Speed Wall

Why can't we get PAQ-level ratios quickly? The answer is fundamental, not accidental.

=== Why More Models Always Help (Theoretically)

In Chapter 23 we proved that compression equals prediction. The better your model of
$P("next bit" | "all history")$, the fewer bits you need. A context-mixing architecture that
runs more models always does at least as well as one with fewer, provided the weights can
adapt. Adding a model never hurts (the mixer can learn to set its weight to zero if the model
is useless).

So why not run 10,000 models? Because each model must be evaluated and updated on every bit.
With 8 billion bits per gigabyte, even a single extra microsecond per model adds 2.2 hours.
The LSTM is especially costly: a full forward-backward pass through a 512-unit LSTM takes
roughly 100–500 microseconds, which is 10–50 days per gigabyte before the time limit cuts
it off. Practitioners choose LSTM depth and width to fit within the prize's 50-hour budget.

=== Why Speed Champions Cannot Use These Techniques

LZ4 and Snappy (Chapter 32) aim for gigabytes per second. At that speed, there is time for
exactly one cheap lookup per byte — perhaps a 4-byte hash into a small history table. There
is no time for logistic mixing, SSE, or an LSTM.

Even gzip's Huffman coding (Chapter 24) and LZ77 match finding (Chapter 28) are already at
the limit for what simple hardware can do quickly. The PAQ family sits at a different point
on the Pareto frontier: the extreme of ratio with no constraint on speed.

#fig(
  [The compression ratio-vs-speed trade-off landscape, with representative codecs.],
  cetz.canvas({
    import cetz.draw: *

    // Axes
    line((0, 0), (8, 0), mark: (end: ">"))
    line((0, 0), (0, 6), mark: (end: ">"))
    content((4, -0.5))[Speed (faster →)]
    content((-1.8, 3), angle: 90deg)[Ratio (better →)]

    // Speed zones (right = fast)
    // Data points: (speed_x, ratio_y, name)
    // LZ4 Snappy: fast, lower ratio
    circle((7.2, 1.5), radius: 0.08, fill: black)
    content((7.2, 1.9))[LZ4/Snappy]

    // gzip
    circle((5.5, 2.4), radius: 0.08, fill: black)
    content((5.5, 2.8))[gzip]

    // zstd
    circle((5.0, 3.1), radius: 0.08, fill: black)
    content((5.0, 3.5))[zstd]

    // xz/LZMA
    circle((3.5, 3.8), radius: 0.08, fill: black)
    content((3.5, 4.2))[xz/LZMA]

    // PPMd
    circle((2.5, 4.5), radius: 0.08, fill: black)
    content((2.5, 4.9))[PPMd]

    // PAQ8 / ZPAQ
    circle((1.2, 5.2), radius: 0.08, fill: black)
    content((1.2, 5.6))[PAQ8/ZPAQ]

    // cmix
    circle((0.3, 5.8), radius: 0.08, fill: black)
    content((0.6, 5.8))[cmix]

    // Pareto frontier curve (dashed)
    bezier(
      (0.3, 5.8),
      (7.2, 1.5),
      (0.8, 5.5),
      (5.0, 2.0),
      stroke: (dash: "dashed", paint: gray)
    )
  })
)

== Preprocessing: The Hidden Weapon

Before a context mixer ever sees a byte, many PAQ-class compressors run preprocessing
transforms that reorganise the data into a form easier to model. These transforms are always
reversible — the decompressor inverts them after expanding the data.

=== Text Preprocessing

English text compresses better if you:

- *Word-tokenise*: replace each word with its token ID, so "compression" always maps to the
  same integer regardless of where it appears.
- *Sort by frequency*: assign the lowest IDs to the most common words, making the
  high-frequency tokens (the, a, of, in) one byte instead of multiple characters.
- *Case-fold*: fold uppercase to lowercase so "The" and "the" share statistics.
- *Remove duplicate whitespace*: normalise spacing so the model does not waste probability
  on space variations.

Wikipedia-specific preprocessing in fx2-cmix also reorders articles: similar articles
(by topic, by first character of title, or by t-SNE embedding of word-frequency vectors) are
placed adjacent in the compressed file. The context mixer then sees similar vocabulary in
nearby positions, which dramatically improves order-$N$ statistics.

=== Binary Preprocessing

For executable files, PAQ8 applies an *E8E9 transform*: x86 CALL and JMP instructions
encode the destination as a relative address, which varies depending on where in memory the
code is loaded. Replacing relative addresses with absolute ones makes the bytes more
predictable (the same function is called from many places, but the absolute address is always
the same). This is lossless and completely transparent to the context mixer.

For JPEG files embedded in an archive, PAQ8 can decompress the JPEG to pixel values, model
the DCT coefficients with specialised models, and re-compress. The final result is often
smaller than modeling the raw JPEG byte stream, because the DCT structure is highly
predictable in its own domain.

#misconception[
  "PAQ-class programs are cheating because they preprocess data into a special form."][
  Every compressor preprocesses data. gzip's LZ77 finds repeated matches and replaces them
  with back-references — that is a preprocessing transform. bzip2 applies the
  Burrows-Wheeler Transform (Chapter 35) before entropy coding. The difference is only
  degree: PAQ-class preprocessors are more numerous and more specialised. All transforms are
  lossless (the original data is always recoverable). Preprocessing is not special-casing; it
  is just modeling with domain knowledge.
]

== The Intelligence Argument

The Hutter Prize rests on a philosophical claim that is worth examining carefully.

=== Compression Equals Prediction Equals Understanding

In Chapter 23 we proved that the expected code length of a source under a model equals the
cross-entropy between the model and the true source distribution. The model that assigns the
highest probability to the actual data is the model closest to the truth — and it produces
the shortest compressed file.

To assign high probability to Wikipedia text, a compressor must predict accurately:
- Which word follows "the capital of France is" (answer: "Paris").
- Whether "affect" or "effect" comes after "have a profound" in a particular sentence.
- What number follows "the 44th President" (answer: "Barack Obama").
- The structure of a wikitext citation: `{{cite|year=…|title=…|author=…}}`.

These are not pattern-matching exercises; they require something very close to *knowing facts*.
A compressor that knows facts can assign higher probability to factual sentences and lower
probability to nonsense — and therefore compresses better.

This is the argument Hutter and Legg formalised: Solomonoff's universal prior (Chapter 22)
defines the ideal predictor as the one that compresses every data sequence to its Kolmogorov
complexity. A better compressor, in this sense, is a more intelligent machine.

#aside[
  In 2023, DeepMind published "Language Modeling Is Compression" (Delétang et al.), showing
  that large language models (GPT-4-class) paired with arithmetic coding achieve state-of-the-art
  lossless compression on enwik8 and other corpora. A 70-billion-parameter model compresses
  enwik8 to about 0.9 bits per character — competitive with the Hutter Prize winners, achieved
  by models that never saw enwik8 during training. This closed the loop: the Hutter Prize
  competitors build intelligence from scratch on the data; LLMs bring intelligence pre-built
  from the internet. Both approaches converge on the same compression ratios. The Hutter Prize
  rules (50 hours, no GPU) are specifically designed to block the LLM route.
]

=== The Honest Counterargument

The intelligence claim is suggestive but not decisive. A compressor that memorises a specific
Wikipedia dump does well on that dump but may not generalize. The PAQ family, trained on
enwik9, would compress a JavaScript source tree worse than zstd, because its models are
tuned for English text.

True intelligence generalizes across domains. The Hutter Prize measures a proxy: general-
purpose English-text prediction. It is a better proxy than most, because Wikipedia covers
enormous breadth. But a programmer who compresses Wikipedia well by specialising in Wikipedia
is not demonstrating general machine intelligence — they are demonstrating excellent
domain-specific modeling. The debate between the "compression as AI" camp and the "it's just
very good statistics" camp remains alive in mid-2026.

#keyidea[
  The ratio champions — PAQ, ZPAQ, cmix — are not practical tools in the everyday sense.
  They are *scientific instruments*: measuring how close we can get to the theoretical minimum
  bits-per-character on a fixed well-understood corpus, subject to realistic (if generous)
  time and memory constraints. Every step closer to the limit is a step toward understanding
  what it means to model human knowledge algorithmically.
]

== Why It All Matters

The PAQ family may seem like an academic curiosity — programs that take days to run,
useful to nobody in a hurry. But the ideas that emerged from the PAQ community influenced
the whole field:

- *Context mixing* is now used in ZPAQ, and its logistic-mixing principles influenced the
  SSE stages in many production codecs.

- *Logistic (neural) mixing weights updated by gradient descent on every symbol* is a form
  of online learning that predates the modern deep-learning wave. The community independently
  discovered that "the loss function is the code length" years before it became fashionable.

- *LSTM as a compressor component* (cmix, 2013–2014) arrived before the 2015–2016 wave of
  LSTM text generation. The Encode.su forum threads where Byron Knoll and others built these
  systems are a forgotten early chapter in neural sequence modeling.

- *ZPAQ's self-describing archive* is the cleanest solution to the archival format problem.
  The idea of embedding a bytecode description of the decompressor inside the archive has
  influenced thinking about format longevity in digital preservation communities.

And the Hutter Prize's core insight — that compressing Wikipedia is equivalent to modeling
it, and modeling it is equivalent to understanding it — became the theoretical underpinning
of the "language modeling is compression" result (Delétang et al., 2023) and the ongoing
research connecting large language models to lossless compression (Chapter 62).

== Scoreboard Update

How do these programs compare on our running sample? For this chapter the sample is a 100 KB
excerpt of English Wikipedia XML (the same type of data the Hutter Prize uses), to give
the ratio champions a fair surface to work on.

#scoreboard(
  caption: "Ratio champions on 100 KB Wikipedia XML sample (approximate; ratios vary by content).",
  [*Program / Setting*], [*Output bytes*], [*Ratio*], [*Notes*],
  [Raw (uncompressed)], [102,400], [1.00:1], [Baseline],
  [gzip -9 (Ch. 30)], [32,100], [3.19:1], [Classic, fast],
  [xz -9 / LZMA (Ch. 31)], [24,800], [4.13:1], [High ratio, minutes],
  [zstd --ultra -22 (Ch. 32)], [26,300], [3.89:1], [Fast decode],
  [PPMd order-8 (Ch. 33)], [18,500], [5.53:1], [Statistical modeling],
  [PAQ8 (this chapter)], [14,200], [7.21:1], [Hours, PAQ8pxd],
  [ZPAQ (this chapter)], [14,700], [6.97:1], [Archival stable],
  [cmix (this chapter)], [13,100], [7.82:1], [Days, ratio champion],
)

== Summary

This chapter showed where classical statistical compression goes when speed is removed as a
constraint. The ratio-champion family — PAQ (2002–present), ZPAQ (2009–2016), and cmix
(2013–present) — is built on context mixing (Chapter 33's core idea) pushed to its logical
limit: hundreds of models, an LSTM neural predictor, gradient-descent weight updates on every
bit, SSE calibration, and aggressive preprocessing.

ZPAQ's self-describing archive solved the archival soundness problem that plagued earlier PAQ
versions. cmix's LSTM mixer captures long-range dependencies that no finite-order context
model can reach. And the Hutter Prize — 500,000 € for compressing 1 GB of Wikipedia — turned
this engineering into an ongoing scientific benchmark, with the September 2024 record of
110,793,128 bytes by Orav and Knoll still standing in June 2026.

The price is extraordinary compute: days per gigabyte, gigabytes of RAM. The prize is
extraordinary insight: these programs are the sharpest lens the field has for measuring how
close algorithmic modeling can get to the theoretical limits of prediction.

#takeaways((
  "PAQ (2002–present) applies context mixing with dozens to hundreds of bit-level models, logistic mixing with gradient-descent weights, and SSE calibration — building ratio supremacy at the cost of extreme slowness.",
  "ZPAQ (2009) solved the archival problem by storing the decompression algorithm as ZPAQL bytecode inside every archive, so a fixed reader can decompress any ZPAQ file, past or future.",
  "cmix (2013–present) adds an LSTM neural network to the classical context-mixer ensemble, capturing long-range patterns beyond any finite context order — making it the current ratio champion on most text benchmarks.",
  "The Hutter Prize (2006–present) offers €500,000 for compressing enwik9 (1 GB Wikipedia XML); the September 2024 record by Orav and Knoll using fx2-cmix is 110,793,128 bytes, still the standing champion in June 2026.",
  "The ratio-vs-speed wall is fundamental: every extra model costs microseconds per bit, multiplied by 8 billion bits per gigabyte. PAQ-class tools are scientific instruments, not everyday codecs.",
  "Compressing Wikipedia well requires predicting factual sentences correctly, which is closely related to intelligence. The Hutter Prize, the DeepMind LLM-compression result (2023), and Chapter 62's LLM-as-compressor all rest on the same equation: better predictor = better compressor = more knowledge about the world.",
))

== Exercises

#exercise("34.1", 1)[
  A context mixer uses three models with predictions $P_1 = 0.7$, $P_2 = 0.6$, $P_3 = 0.5$
  and equal weights $w_i = 1/3$. The actual bit is 1.

  (a) Compute the log-odds $s_i = ln(P_i \/ (1-P_i))$ for each model.

  (b) Compute the weighted sum $S$ and the final mixed probability $P_"mix" = 1\/(1 + e^(-S))$.

  (c) What is the Shannon coding cost of this bit (in bits) using $P_"mix"$?
]

#solution("34.1")[
  (a) $s_1 = ln(0.7/0.3) = ln(7/3) approx 0.847$; $s_2 = ln(0.6/0.4) = ln(3/2) approx 0.405$;
  $s_3 = ln(0.5/0.5) = ln 1 = 0$.

  (b) $S = (0.847 + 0.405 + 0)/3 approx 0.417$. $P_"mix" = 1/(1+e^(-0.417)) approx 0.603$.

  (c) The bit is 1, so cost $= -log_2(0.603) approx 0.730$ bits. (Compare: if all three models
  had uniform weight and averaged directly, $P_"avg" = 0.600$, cost $= -log_2(0.600) approx 0.737$
  bits. The logistic mix is almost identical here because the predictions are close to 0.5.)
]

#exercise("34.2", 1)[
  Explain in your own words why ZPAQ archives remain readable in the future even if the ZPAQ
  program is updated to use a completely different compression algorithm. What part of the
  archive design makes this possible?
]

#solution("34.2")[
  Because every ZPAQ archive stores the decompression algorithm as ZPAQL bytecode in its own
  header. The fixed ZPAQ reader program only needs to know how to interpret ZPAQL — it does
  not need to know which compression algorithm was used. When a future version of ZPAQ uses
  a new algorithm, it writes the new algorithm in ZPAQL bytecode into the archive's header.
  The 2009 reader, which already knows how to execute ZPAQL, can run that new bytecode and
  decompress the archive perfectly. The reader stays fixed; the algorithm changes.
]

#exercise("34.3", 2)[
  The Hutter Prize rules require a self-extracting archive: the decompressor is included in
  the compressed file. If a team achieves 110,793,128 bytes for the compressed enwik9 data
  alone, but their decompressor binary is 2.5 MB, what is the total self-extracting size, and
  does this improve upon the 110,793,128 byte record? What does this tell you about the
  trade-off between algorithm complexity and archive size?
]

#solution("34.3")[
  Total size = 110,793,128 + 2,500,000 = 113,293,128 bytes. This is *larger* than 110,793,128
  bytes and therefore does not improve the record. It tells us that making the compressor more
  complex — for example, by adding a larger LSTM — may improve the ratio on the data payload,
  but the added code size in the self-extracting decompressor may cancel the gain. This is the
  competition's elegance: it rewards algorithms that are simultaneously powerful and compact.
  Winning teams use every trick to keep the decompressor binary small.
]

#exercise("34.4", 2)[
  The Python sketch in this chapter has a function `compress_bits(data: bytes)` that returns
  the Shannon cost, not an actual bit stream. Explain what would be needed to turn it into a
  real compressor — one that produces compressed bytes the receiver can decompress. What pieces
  are missing, and which earlier chapter covers each missing piece?
]

#solution("34.4")[
  Three things are missing:

  1. *A real arithmetic coder*: the sketch computes the ideal Shannon cost but does not emit
     actual bits. Chapter 26 covers arithmetic coding — converting a sequence of probability
     estimates into a real bit stream (and back).

  2. *A bit I/O layer*: the arithmetic coder emits bits, which need to be packed into bytes
     for storage or transmission. Chapter 17 covers `BitWriter` and `BitReader` in the tinyzip
     project. Without these, you cannot write a file or read it back.

  3. *Synchronised models on the decoder side*: the decoder must run exactly the same sequence
     of model updates in exactly the same order, starting from the same initial state, so that
     its probability estimates match the encoder's. This is guaranteed in context mixing because
     both sides process the same decoded bits in the same order — but the code must be structured
     carefully to ensure that no model uses the current bit before it has been decoded.
]

#exercise("34.5", 3)[
  Consider the following variant of the mixing update rule. Instead of updating *all* model
  weights after every bit, you update only the weight of the model whose prediction was most
  wrong (the one with the largest absolute error $|p_i - "bit"|$).

  (a) Sketch an argument for why this "winner-penalises-most-wrong" strategy might converge
  more slowly than updating all weights.

  (b) The fx2-cmix algorithm uses a selective update that *skips* weight updates when the
  prediction error is below a threshold. Is this similar or opposite to the variant described
  here? What is the motivation for the fx2-cmix choice?
]

#solution("34.5")[
  (a) Standard gradient descent pushes all weights toward their optimal values simultaneously.
  If you update only the most-wrong model's weight, you are ignoring information about how
  well all other models performed. In particular, you lose the information that a *correctly*
  predicting model deserves a higher weight — you only ever penalise. Over many steps, the
  mixer still converges (the most-wrong model's weight slowly decreases), but convergence is
  slower because you are not simultaneously reinforcing the correct models.

  (b) The fx2-cmix strategy is opposite in spirit. It skips updates when the error is *small*
  (the prediction was nearly right), not when the error is large. The motivation: when the
  mixer is already very confident and correct, the weight updates are tiny anyway (gradient
  $approx 0$), and computing them wastes CPU time with negligible benefit. Skipping these
  micro-updates saves a measurable fraction of compute time, allowing the algorithm to spend
  its 50-hour budget on more bits and larger models. This is a computational efficiency trick,
  not a change in the learning algorithm.
]

#exercise("34.6", 2)[
  The Hutter Prize's resource limits include a 50-hour time limit and a 10 GB RAM limit.
  Imagine you wanted to enter with a pure lookup-table compressor: you pre-compute an optimal
  code for every possible 8-byte context in enwik9 and store that table.

  (a) How many distinct 8-byte contexts are there, in the worst case?

  (b) Even if we allow 10 GB of table memory, is there enough space? (Each entry needs at
  least 1 byte.) What does this tell you about why context tables must use hashing and
  approximate representations?
]

#solution("34.6")[
  (a) Each byte has 256 possible values. An 8-byte context has $256^8 = 2^64 approx 1.8 times 10^19$
  possible values. That is roughly 18 billion billion distinct contexts.

  (b) 10 GB = $10 times 10^9 = 10^10$ bytes of RAM. The table would need $2^64 approx 1.8 times 10^19$
  bytes — about 1.8 billion times more than available. Hopeless. This is why context models
  use *hashing*: the context is hashed to one of a manageable number of table positions (say,
  $2^24 approx 16$ million), collisions are accepted and averaged, and the table is stored in
  a practical amount of RAM. Most high-order contexts in a real file appear only once or twice;
  a 16-million-entry hash table captures the statistically meaningful contexts without wasting
  space on the astronomical number of contexts that never appear.
]

== Further Reading

#link("https://mattmahoney.net/dc/paq.html")[Mahoney, M. _The PAQ Data Compression Programs_ (2002–2016)] — the canonical source for the PAQ family, with full source code, technical notes, and the evolution from PAQ1 through PAQ8 and all branches.

#link("https://mattmahoney.net/dc/zpaq.html")[Mahoney, M. _ZPAQ Archive Format_ (2009–2016)] — the ZPAQ specification, ZPAQL virtual machine description, and source releases through version 7.15.

#link("https://mattmahoney.net/dc/zpaq_compression.pdf")[Mahoney, M. "The ZPAQ Compression Algorithm" (December 2015)] — the definitive technical paper describing the ZPAQL architecture, model component types, and performance evaluation.

#link("https://www.byronknoll.com/cmix.html")[Knoll, B. _cmix_ (2013–present)] — home page for the cmix compressor, with build instructions, benchmark results, and links to the GitHub repository.

#link("https://github.com/kaitz/fx2-cmix")[Orav, K. and Knoll, B. _fx2-cmix_ (2024)] — the Hutter Prize submission source code for the current enwik9 record (110,793,128 bytes).

#link("http://prize.hutter1.net/")[Hutter, M. _Human Knowledge Compression Contest — the Hutter Prize_ (2006–present)] — the official prize site, with current records, rules, and the prize fund status.

#link("http://www.mattmahoney.net/dc/text.html")[Mahoney, M. _Large Text Compression Benchmark_ (2006–present)] — the leaderboard for enwik8 and enwik9, the definitive scoreboard for ratio-champion compressors.

#link("https://arxiv.org/abs/2309.10668")[Delétang, G. et al. "Language Modeling Is Compression." DeepMind, 2023] — shows that large language models paired with arithmetic coding achieve state-of-the-art lossless compression; the theoretical bridge between the Hutter Prize community and the LLM world.

#link("https://en.wikipedia.org/wiki/Context_mixing")[Wikipedia: "Context mixing"] — a compact overview of the logistic mixing architecture used in PAQ and its descendants.

#link("https://encode.su")[Encode.su compression forum] — the community where PAQ, cmix, and most modern ratio-champion algorithms were developed and debated; an extraordinary primary source for the history of the field.

#bridge[
  We have now climbed from Shannon's entropy floor all the way to the ratio champions that
  approach it asymptotically — at the cost of compute measured in days. But there is one more
  reversible transform in the lossless toolkit that belongs in a different class: not a model
  and a coder, but a structural rearrangement of the data itself that makes any coder work
  dramatically better. Chapter 35 introduces the Burrows–Wheeler Transform — the 1994
  discovery that permutes a block of text into something far more compressible, powers bzip2,
  and found a second life in the FM-index that makes genome alignment possible. It is the last
  major classical technique, and it completes Volume II's picture of the lossless landscape.
]
