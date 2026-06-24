#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Statistical Modeling: PPM and Context Mixing

#epigraph[
  To compress a string you must understand it, and to understand it is to know
  its probable continuations. Every good predictor is a good compressor in disguise.
][Matt Mahoney, _Large Text Compression Benchmark_ notes]

Picture yourself reading a mystery novel. After the sentence "The butler entered the dimly lit
library carrying a candle," the word that follows is almost certainly not "xylophone." Your brain
effortlessly assigns xylophone a probability near zero and candlestick a probability near one.
You are doing statistical modeling, exactly what this chapter's algorithms do, one character at a
time, millions of times per second.

Every compressor we have built so far answers the question "what symbol comes next?" with
something simple: Huffman (Chapter 24) uses a fixed, global histogram; DEFLATE (Chapter 30) uses
a sliding window to copy recent matches; Zstandard (Chapter 32) adds a trained dictionary.
All of these are approximations to the true answer, which requires knowing the entire history of
the stream and the deep structure of the source.

The algorithms in this chapter push that approximation to its limit. They track rich statistical
contexts (the last 5, 10, even 20 characters) and they blend the predictions of dozens or
hundreds of specialized models into one bit-level probability. The payoff is extraordinary
compression ratios. The cost is compute time measured in hours for a gigabyte, and RAM measured
in gigabytes. These are the ratio champions of the classical era, and they sit right at the
boundary where compression silently becomes intelligence.

#recap[
  In Chapter 18 we learned that Shannon entropy $H(X) = -sum_i p_i log_2 p_i$ is the minimum
  average bits per symbol. In Chapter 23 we proved that compression equals prediction: a model
  assigning probability $p$ to the correct next symbol costs $-log_2 p$ bits via an arithmetic
  coder, so a better model means fewer bits. Chapter 26 gave us that arithmetic coder (the engine
  that turns a probability into a bit stream). Chapters 28–32 showed dictionary coders that
  implicitly model recency. This chapter builds the explicit statistical model that an arithmetic
  coder can drive to near-entropy performance.
]

#objectives((
  "Understand how PPM builds and queries context models of multiple orders.",
  "Explain the zero-frequency problem and how escape mechanisms (PPMA through PPMd) solve it.",
  "Describe context mixing: why many models beat one, and how logistic blending works.",
  "Understand SSE (Secondary Symbol Estimation) and how it sharpens mixed probabilities.",
  "Read a simplified PPM implementation and see how a context table is built online.",
  "Know the PAQ/ZPAQ/cmix lineage, the Hutter Prize, and why these algorithms matter for AI.",
))

== The Idea: Predict, Then Code

Before any algebra, take a step back to the big picture.

An arithmetic coder (Chapter 26) can take any probability $p$ you hand it and encode the next
symbol in approximately $-log_2 p$ bits. If you somehow always knew the true probability of the
next byte, you would compress exactly to the Shannon entropy limit. Every technique in this
chapter is a strategy for getting $p$ as close to the true probability as possible.

#keyidea[
  The three-part recipe for a statistical compressor:
  1. *Model*: maintain a table of counts that lets you estimate $P("next symbol" | "recent history")$.
  2. *Code*: feed that probability into an arithmetic coder that emits the exact fractional bits.
  3. *Update*: after coding each symbol, update the count table so the model adapts to the data.
  Everything in this chapter is a variation on these three steps.
]

The simplest non-trivial model is *order-1*: for each symbol $c$ that appeared in the past, track
how often each symbol $d$ followed it, and use those relative frequencies as probabilities. On
English text, this already cuts bits per character from about 4.7 (order-0 Huffman) to about 3.5.
Order-2 contexts (two-character history) drop it to roughly 2.8. Order-5 gets below 2.0. But
there is a problem.

=== The Zero-Frequency Problem

Every time you raise the order, you encounter more contexts you have never seen before. If you
have never seen the trigram "zxq" in your training data, your order-2 model assigns probability
zero to any symbol after "zq". If you try to encode such a symbol with an arithmetic coder
that sees probability zero, you divide by zero and the compressor crashes.

This is the *zero-frequency problem*, also known as the *sparse data* problem. It is not a
corner case. In a typical English file, the majority of high-order contexts appear only once or
twice, and countless others never appear at all. Any practical high-order model must handle it.

#gomaths("Probability and Frequency Estimation")[
  If we observe $c_i$ occurrences of symbol $i$ in $N$ total observations, the *maximum-likelihood
  estimate* of its probability is simply $hat(p)_i = c_i / N$. The trouble: if $c_i = 0$, then
  $hat(p)_i = 0$, and coding that symbol would require $-log_2(0) = infinity$ bits.

  The classic fix is *Laplace smoothing* (add-one smoothing): pretend every symbol appeared once
  already, so $hat(p)_i = (c_i + 1) / (N + S)$ where $S$ is the alphabet size. This guarantees
  no probability is zero, but it wastes bits on rare symbols.

  PPM solves it more elegantly with an *escape* mechanism: keep the observed probabilities for
  known symbols but reserve a small probability mass for an escape code that signals "back off to a
  shorter context." We will see exactly how that mass is chosen in the next section.
]

== PPM: Prediction by Partial Matching

*PPM* was introduced by John Cleary and Ian Witten in their 1984 paper "Data Compression Using
Adaptive Coding and Partial String Matching." The idea is deceptively simple: blend multiple
orders of context model by *escaping* from higher orders to lower ones whenever a symbol is
unseen.

=== The Context Hierarchy

An order-$k$ model predicts the next symbol using the previous $k$ symbols as context. PPM
maintains models at *every* order from $k$ down to $-1$:

- *Order $k$*: the primary model; predicts from the last $k$ characters.
- *Order $k-1, k-2, dots, 0$*: fallback models; shorter histories.
- *Order $-1$*: the uniform model; every symbol in the alphabet gets equal probability $1\/256$.

When encoding a symbol $x$ given context $c$ of length $k$:

1. Look up $x$ in the order-$k$ table for context $c$.
2. If $x$ has been seen there before, encode it using the order-$k$ probability and *stop*.
3. If $x$ has *never* been seen in this context, encode an *escape* symbol (a special event whose
   probability we also track), then drop to order $k-1$ and try again.
4. Keep backing off until order $-1$, which is guaranteed to have a nonzero probability for every
   symbol.

#fig(
  [PPM context hierarchy. Encoding the character "n" after context "sio". Order-3 has never
   seen "n" after "sio", so it emits an escape and falls back. Order-2 ("io") has seen "n"
   once and succeeds. The escape itself costs bits, but far fewer than encoding blindly.],
  cetz.canvas({
    import cetz.draw: *
    // Draw boxes for each order level
    let box-width = 3.2
    let box-height = 0.7
    let gap = 1.1
    let orders = (("Order 3", "ctx: \"sio\"", "seen: {}", "→ ESCAPE"), ("Order 2", "ctx: \"io\"", "seen: {n:1, t:2}", "→ encode n"), ("Order 1", "ctx: \"o\"", "seen: {n:4, e:1}", "(not needed)"), ("Order 0", "ctx: \"\"", "seen: all", "(not needed)"))
    for (i, (label, ctx, seen, action)) in orders.enumerate() {
      let y = -i * gap
      let col = if i == 1 { rgb("#0b6e4f") } else if i == 0 { rgb("#9a2617") } else { rgb("#555555") }
      rect((0, y - box-height/2), (box-width, y + box-height/2), stroke: 0.8pt + col, fill: col.lighten(92%))
      content((box-width / 2, y + 0.18), box(width: 2.8cm, align(center, text(size: 8pt, weight: "bold", fill: col)[#label: #ctx])))
      content((box-width / 2, y - 0.18), box(width: 2.8cm, align(center, text(size: 7pt, fill: col.darken(10%))[#seen  #action])))
      // Arrow down (except last)
      if i < 3 {
        line((box-width/2, y - box-height/2), (box-width/2, y - gap + box-height/2), mark: (end: ">"), stroke: 0.7pt + rgb("#444"))
      }
    }
    // Label arrows
    content((box-width + 0.4, -0 * gap), text(size: 7pt, style: "italic")[escape])
    content((box-width + 0.4, -1 * gap), text(size: 7pt, style: "italic")[encode!])
  })
)

=== Escape Probability: The PPM Variants

The crux of PPM is this: how much probability mass do you set aside for the escape event? Too
little, and you waste bits encoding symbols that keep escaping. Too much, and you dilute the
probability of symbols you *have* seen, wasting bits there instead. Different answers to this
question gave the classic variants:

*PPMA (Cleary & Witten, 1984):* Escape probability = (number of distinct symbols seen in this
context) / (total count + number of distinct symbols). Simple, but tends to over-estimate.

*PPMB (Cleary & Witten, 1984):* Escape probability = 1 / (total count + 1). Different trade-off,
slightly better on some sources.

*PPMC (Moffat, 1990):* The variant that struck the best empirical balance and became the
reference. Escape probability = (number of distinct symbols) / (total count + number of distinct
symbols). Moffat's key insight was also the *exclusion* principle: when you escape to a lower
order, exclude from the lower-order distribution any symbol that already appeared in the
higher-order context (since those would have been coded there, not escaped). This avoids double-
counting probability mass and improves compression by a measurable margin.

*PPMD (Moffat, 1990):* A simpler approximation that skips exclusion for speed; generally slightly
worse than PPMC but much faster to implement.

#algo(
  name: "PPM (Prediction by Partial Matching)",
  year: "1984",
  authors: "John G. Cleary, Ian H. Witten",
  aim: "Encode each symbol using the best available context, escaping to shorter contexts for unseen symbols.",
  complexity: "O(k · |symbol|) per symbol; O(alphabet · max\\_context · data) space",
  strengths: "Near-entropy compression on structured text; purely adaptive (no offline training); elegant theoretical grounding.",
  weaknesses: "Commits to one context per symbol; memory can grow large; slow compared to LZ codecs.",
  superseded: "By context mixing (which blends all orders simultaneously) for maximum ratio.",
)[
  The core loop: given the current symbol $x$ and context $c$ of length at most $k$:
  1. If $x$ in context-table[$c$]: encode using stored probability; update count.
  2. Else: encode ESCAPE with escape probability; shorten $c$ by 1 character; repeat.
  3. At order $-1$: encode $x$ uniformly over the full alphabet.
  After coding, insert/increment $x$ in context-table[$c$] at all orders (update).
]

=== PPMd: The Practical Champion

In 2002, Dmitry Shkarin published *PPMII* ("PPM with Information Inheritance"), implemented as
the freely available *PPMd*. PPMII addressed a subtle weakness: after escaping to a shorter
context, the algorithm had been throwing away information it already possessed. PPMII "inherits"
the count from the higher-order context to inform the lower-order estimate, achieving noticeably
better compression on the same data.

PPMd became the compression ratio champion on the Calgary Corpus at roughly 2 bits per character
on English text. More importantly, Shkarin's implementation was adopted into *7-Zip* and *WinRAR*
as their high-ratio text mode (the PPMd method), where it is used by millions of users today as
the option to choose when file size matters more than time.

#history[
  Alistair Moffat's 1990 paper "Implementing the PPM Data Compression Scheme" is one of the most
  carefully engineered compression papers ever written. Where the 1984 original was conceptual,
  Moffat specified exact data structures (a trie of contexts with carefully maintained count
  arrays) that made PPM practical on the computers of the day. The paper is still the standard
  reference for implementers. Moffat went on to co-author the textbook _Managing Gigabytes_
  (1999), which shaped a generation of information retrieval and compression engineers.
]

=== A Worked Example: Encoding "ABRACADABRA"

Let us trace PPM at order 2 on the string "ABRACADABRA", starting with an empty model and
encoding one character at a time.

At the very start the model is empty: order-2 and order-1 tables have no entries. Every symbol
escapes all the way to order $-1$ (uniform over the alphabet). As we encode:

- *A*: escape from order 2 (empty), escape from order 1 (empty), encode A at order $-1$. Update: add A to order-0 and order-1 (context "") tables.
- *B*: similar escape chain; adds B to context tables.
- *R*: similarly.
- *A*: the order-1 model (context "R") is empty, escape; order-0 model has {A:1, B:1, R:1}, A has count 1 of 3. Encode A there. Update: add A after "RA" in order-2 table.
- After "ABRA" the model has counts like: after "R" → {A:1}, after "A" → {B:1}, etc.
- When we reach the second "BRA" near the end, order-2 sees "BR" → {A:1} with certainty: one bit to encode A.

The result: early symbols cost many bits (escaping to order $-1$); later symbols with rich context
cost near zero. PPM is a pure *online* learner, requiring no offline training pass.

#checkpoint[
  After encoding "ABRACAD", what does the order-1 table contain for the context "A"?
][
  A appears followed by B (in "AB"), then C (in "AC"), then D (in "AD"). So the order-1 table
  for context "A" has: {B: 1, C: 1, D: 1}, total count 3. Each has probability 1/3 plus the
  escape gets 3/(3+3) = 1/2 by PPMC. (Exact values depend on the escape method chosen.)
]

=== Python: A Minimal PPM Encoder

No `#project` step is assigned to Chapter 33 (PPMd has no tinyzip step), but a small, readable
implementation makes the algorithm concrete.

#gopython("Dictionaries of dictionaries: nested tables")[
  In Python, a `dict[str, dict[int, int]]` is a dictionary whose keys are strings (the contexts)
  and whose values are themselves dictionaries mapping byte values to counts. This nesting is the
  natural way to represent a PPM context table.

  ```python
  # Build a nested context table
  ctx_table: dict[str, dict[int, int]] = {}

  def update(ctx: str, symbol: int) -> None:
      if ctx not in ctx_table:
          ctx_table[ctx] = {}
      counts = ctx_table[ctx]
      counts[symbol] = counts.get(symbol, 0) + 1

  update("AB", ord("C"))
  update("AB", ord("D"))
  update("AB", ord("C"))
  print(ctx_table["AB"])   # {67: 2, 68: 1}  (67=C, 68=D)
  ```

  The outer key is the context string; the inner dict maps symbol bytes to their counts.
  `counts.get(symbol, 0)` returns 0 if the symbol has never appeared: the zero-frequency
  problem in miniature.
]

```python
# ppm_demo.py: order-2 PPM model (probability query only; no actual arithmetic coding)
# Python 3.14

def ppm_escape_prob_c(counts: dict[int, int]) -> float:
    """PPMC escape probability: distinct_symbols / (total + distinct)."""
    n_distinct = len(counts)
    total = sum(counts.values())
    return n_distinct / (total + n_distinct) if counts else 1.0

def ppm_symbol_prob(counts: dict[int, int], symbol: int) -> float:
    """Probability of `symbol` given this context's count table (PPMC)."""
    if not counts or symbol not in counts:
        return 0.0
    n_distinct = len(counts)
    total = sum(counts.values())
    # Of the (total + n_distinct) mass, n_distinct goes to escape; the rest is split
    # among seen symbols in proportion to their counts.
    return counts[symbol] / (total + n_distinct)  # share of the non-escape mass

class PPMModel:
    """Minimal order-2 PPM model. Tracks contexts of length 0, 1, and 2."""

    def __init__(self, max_order: int = 2, alphabet: int = 256) -> None:
        self.max_order = max_order
        self.alphabet = alphabet
        # table[context_bytes] -> {symbol: count}
        self.table: dict[bytes, dict[int, int]] = {}

    def _counts(self, ctx: bytes) -> dict[int, int]:
        return self.table.get(ctx, {})

    def query(self, symbol: int, context: bytes) -> float:
        """
        Return the probability PPM assigns to `symbol` in `context`.
        Chains through orders from max_order down to order -1.
        """
        prob = 1.0  # accumulated escape probability multiplier
        for order in range(self.max_order, -2, -1):
            if order == -1:
                # Order -1: uniform over full alphabet
                return prob * (1.0 / self.alphabet)
            ctx = context[-order:] if order > 0 else b""
            counts = self._counts(ctx)
            sym_prob = ppm_symbol_prob(counts, symbol)
            if sym_prob > 0:
                return prob * sym_prob
            # escape
            esc = ppm_escape_prob_c(counts)
            prob *= esc
        return prob  # unreachable but satisfies type checker

    def update(self, symbol: int, context: bytes) -> None:
        """Add `symbol` to all context tables for this position."""
        for order in range(0, self.max_order + 1):
            ctx = context[-order:] if order > 0 else b""
            if ctx not in self.table:
                self.table[ctx] = {}
            self.table[ctx][symbol] = self.table[ctx].get(symbol, 0) + 1

# Quick self-test
if __name__ == "__main__":
    model = PPMModel(max_order=2)
    data = b"abracadabra"
    for i, byte in enumerate(data):
        ctx = data[max(0, i-2):i]
        prob = model.query(byte, ctx)
        print(f"P({chr(byte)} | {ctx!r}) = {prob:.4f}")
        model.update(byte, ctx)
```

The output shows probabilities rising as the model learns: the second "a" after "br" has
probability 1.0 after the model has seen "bra" once: one free bit.

== The Limits of PPM: Why One Context Is Not Enough

PPM is clever, but it has a fundamental architectural limitation: at any given moment, *one*
context wins and all predictions come from that single order. The word-level model and the
character-level model cannot simultaneously vote on what comes next.

Consider compressing C source code. After the token `if`, the next characters are almost always
`(`. That is a powerful word-level clue. But the character-level order-3 context `"f ("` also
predicts a space or a variable name. PPM must pick one of these contexts to use; it throws the
other's evidence away.

Context mixing answers: what if we used *all* contexts simultaneously and let a learned combiner
decide how much to trust each one?

== Context Mixing: Many Predictors, One Verdict

*Context mixing* (CM) is the family of techniques that run multiple prediction models in parallel
and combine their outputs. Every CM compressor operates *bit by bit*, not byte by byte. This matters:
at the bit level, each model outputs a single number $p in [0,1]$ (the probability that
the next bit is 1), which makes combination trivially one-dimensional.

The models run in parallel on every bit:

- An order-0 byte model (global bit frequencies)
- An order-1 byte model (conditioned on the previous byte)
- An order-2, order-3, order-4, order-8 byte model
- A word model (conditioned on recent whole words)
- A sparse model (conditioned on the byte 4 positions ago)
- A "record length" model (for fixed-width table data)
- An "indentation" model (for source code or structured text)
- ...and dozens more

Each of these has learned its own statistics from the bits seen so far. Now the question is: how
do we combine their $p_i$ predictions into a single probability?

=== Linear Mixing and Its Problem

The naive approach: weighted average $P = sum_i w_i p_i$ where weights $sum_i w_i = 1$.
This has a crippling flaw. If model A predicts $p_A = 0.9$ and model B predicts $p_B = 0.1$, the
average is $0.5$, leaving us uncertain. But if A is always right when it's confident and B is always wrong
when it's confident, a smart combiner should *invert* B and get $P approx 0.9$. Linear mixing
has no way to express this inversion; weights must be positive.

=== Logistic Mixing: The Key Idea

The solution is to work in *logit space* (also called log-odds space).

#mathrecall[
  Two tools from Chapter 7 return here: the *natural logarithm* $ln = log_e$, the logarithm to
  the base $e approx 2.71828$, and its partner the exponential $e^x$. We only need three facts:
  $ln$ turns multiplication into addition just like every other log, $ln 1 = 0$, and $e^x$ undoes
  $ln$ (so $e^(ln y) = y$). Everything below is built from these.
]

#gomaths("Logits and the Logistic Function")[
  The *logit* of a probability $p$ is $"logit"(p) = ln(p / (1-p))$. Think of it as a way to
  stretch the $[0,1]$ probability axis out to the whole real number line $(-infinity, +infinity)$:
  - $p = 0.5$ maps to logit $0$ (neither favoring 0 nor 1)
  - $p = 0.9$ maps to logit $approx 2.2$
  - $p = 0.01$ maps to logit $approx -4.6$

  The inverse is the *logistic function* (also called sigmoid):
  $sigma(s) = 1 \/ (1 + e^(-s))$

  Together they form a round-trip: logit stretches probability to a real number; logistic squashes
  it back.

  *Example:* If model A gives $p = 0.9$ and model B gives $p = 0.1$:
  - Logits: $s_A = ln(9) approx 2.20$, $s_B = ln(0.1/0.9) approx -2.20$
  - With weights $w_A = 1.0, w_B = -1.0$: $S = 1.0 times 2.20 + (-1.0) times (-2.20) = 4.40$
  - $sigma(4.40) approx 0.988$, confidently predicting 1, correctly inverting B.

  Negative weights are now meaningful! A model that consistently predicts backwards gets a
  negative weight, and its "wrongness" becomes useful signal.
]

The logistic mixer:

$ S = sum_i w_i dot "logit"(p_i), quad P = sigma(S) = 1 / (1 + e^(-S)) $

The weights $w_i$ are trained online after every bit: since the goal is to minimize the number of
bits spent (cross-entropy loss), and since gradient descent on the logistic output is
straightforward, the compressor literally trains a one-layer neural network on the fly while
compressing.

#mathrecall[
  Two ideas we already built power this. From Chapter 23, the *cross-entropy loss* of coding a bit
  whose true value is $b$ with predicted probability $P$ is $-log_2 P$ when $b = 1$ and
  $-log_2(1 - P)$ when $b = 0$, which is the number of bits the arithmetic coder will actually spend. From
  Chapter 11, *gradient descent* nudges each tunable number a small step *opposite* its slope, so
  the loss goes downhill. Put together: after each bit we ask "which way should each weight move to
  spend fewer bits?" and take one tiny step that way.
]

The weight update for each model $i$ after observing true bit $b$ is:

$ w_i arrow.l w_i + eta dot (b - P) dot "logit"(p_i) $

where $eta$ (eta) is a learning rate (typically around 0.002 to 0.01). The factor $(b - P)$ is the
*prediction error*: if the bit was 1 but we only predicted $P = 0.3$, then $(b - P) = 0.7$ is large
and positive, and every model that voted "1" (positive logit) gets its weight pushed up so it counts
for more next time; a model that voted "0" gets pushed down. When $P$ already matches the bit, the
error is near zero and weights barely move. This is exactly the *backpropagation* update for a
single sigmoid output neuron. This is the same learning rule that trains the giant neural networks of
Volume IV, here running on one tiny layer, one step per bit.

#keyidea[
  A context-mixing compressor *is* a real-time, online neural network. Every bit it encodes is
  a training step. The "model" is not pre-trained. It learns from the very data it is
  compressing, which is exactly what we want: the model specializes to this particular file.
]

#fig(
  [Context mixing architecture. Eight models each produce a bit probability $p_i$. Logits
   $s_i$ are computed, multiplied by learned weights $w_i$, summed into $S$, then squashed
   by the logistic function to produce the final prediction $P$. After the bit is observed,
   weights are updated by gradient descent.],
  cetz.canvas({
    import cetz.draw: *
    // Models on the left
    let models = ("Ord-0", "Ord-1", "Ord-4", "Word", "Sparse", "Record", "Match", "Ord-8")
    for (i, m) in models.enumerate() {
      let y = (3.5 - i * 1.0)
      rect((-3.2, y - 0.28), (-1.8, y + 0.28), stroke: 0.6pt + rgb("#0b5394"), fill: rgb("#dce9f5"))
      content((-2.5, y), box(width: 1.2cm, align(center, text(size: 7.5pt)[#m])))
      line((-1.8, y), (-0.8, 0.0), stroke: 0.5pt + rgb("#888"))
    }
    // Mixer node
    circle((0.0, 0.0), radius: 0.6, stroke: 0.8pt + rgb("#0b6e4f"), fill: rgb("#d9f0e8"))
    content((0.0, 0.0), box(width: 1.0cm, align(center, text(size: 8pt, weight: "bold")[logit mix])))
    // Output
    line((0.6, 0.0), (1.8, 0.0), mark: (end: ">"), stroke: 0.8pt)
    rect((1.8, -0.3), (3.0, 0.3), stroke: 0.6pt + rgb("#9a2617"), fill: rgb("#f7ddd9"))
    content((2.4, 0.0), box(width: 1.0cm, align(center, text(size: 7.5pt)[σ(S)=P])))
    // Weight update arrow
    line((2.4, -0.3), (2.4, -1.1), stroke: 0.6pt + rgb("#783f04"), mark: (end: ">"))
    content((2.4, -1.4), box(width: 1.2cm, align(center, text(size: 7.5pt, style: "italic", fill: rgb("#783f04"))[update w])))
    line((2.4, -1.4), (0.0, -1.4), stroke: 0.4pt + rgb("#783f04"))
    line((0.0, -1.4), (0.0, -0.6), stroke: 0.4pt + rgb("#783f04"), mark: (end: ">"))
    // Labels
    content((-2.5, -4.1), box(width: 2.0cm, align(center, text(size: 7pt, style: "italic")[context models])))
    content((0.0, 0.85), box(width: 2.8cm, align(center, text(size: 7pt, style: "italic")[sum wᵢ·logit(pᵢ)])))
  })
)

#algo(
  name: "Context Mixing (Logistic CM)",
  year: "2000–2002",
  authors: "Matt Mahoney (PAQ1/PAQ2, 2002); logistic variant in PAQ7 (2007)",
  aim: "Combine many context-model bit predictions via a learned logistic mixture, minimizing cross-entropy per bit.",
  complexity: "O(M) per bit where M = number of models; O(M + context tables) space.",
  strengths: "Dramatically better than any single model; negative weights allow model inversion; purely online.",
  weaknesses: "Requires many models → slow (seconds per MB); hard to tune without expertise.",
  superseded: "Not superseded. Still the basis of the best classical compressors as of 2026.",
)[
  Logistic mixing formula per bit:
  $ S = sum_(i=1)^M w_i dot "logit"(p_i), quad P = 1/(1 + e^(-S)) $
  Weight update (gradient descent, learning rate $eta$, observed bit $b in {0,1}$):
  $ w_i arrow.l w_i + eta (b - P) "logit"(p_i) $
  The arithmetic coder then encodes the bit using probability $P$.
]

=== SSE: Secondary Symbol Estimation

Even the logistic mixer makes systematic errors. It might consistently over-predict 1 in certain
situations that it lacks the context to recognize. *SSE* (Secondary Symbol Estimation), sometimes
called APM (Adaptive Probability Map), corrects these errors by passing the mixed probability $P$
through a second learned calibration table.

The table maps quantized input probabilities (say, 256 buckets from 0 to 1) to better output
probabilities. After each bit, the entry for the input bucket is nudged toward the true outcome
by a small learning rate. Over time, the table learns the mixer's systematic biases and removes
them. A well-tuned SSE stage can improve compression by several percent on its own.

A concrete picture: suppose that, whenever the mixer outputs $P = 0.90$, the bit actually turns out
to be 1 only about 80% of the time: the mixer is *over-confident* in that range. SSE notices this.
Its bucket for "input near 0.90" gradually drifts down toward the observed 0.80, so the next time
the mixer says 0.90, SSE quietly hands the arithmetic coder 0.80 instead. Because the coder spends
$-log_2 P$ bits, feeding it a *calibrated* probability spends fewer bits on average than feeding it
the mixer's raw, slightly-wrong one. The table needs no formula for *why* the mixer is biased; it
simply measures the bias bucket by bucket and cancels it.

Think of SSE as a learned "correction layer" on top of the mixer: first blends models,
then calibrates the result. (This is the same calibration idea that the
adaptive bit model of Chapter 23 used at the level of a single context; SSE applies it to the
mixer's *output*.)

== The PAQ Lineage: A Collaborative Arms Race

Matt Mahoney launched the PAQ project in 2002 based on his earlier 2000 paper "Fast Text
Compression with Neural Networks." PAQ1 was a proof of concept; within months it was outperforming
everything then available on text. What happened next was remarkable: Mahoney released the source
code, and a global community of hobbyists began contributing model ideas.

#history[
  The PAQ story is one of the most unusual collaborative software projects in history. Unlike
  Linux (millions of professionals) or Wikipedia (millions of amateurs), PAQ was driven by a
  small, deeply technical community (perhaps a dozen active contributors at peak) who competed
  fiercely and collaborated generously, sharing ideas on data-compression forums (primarily
  encode.ru). The culture was meritocratic: better compression spoke for itself. Contributors
  included professional researchers, students, and self-taught enthusiasts from Russia, Poland,
  Germany, and the United States. The result, over twenty years, was an algorithm family that
  pushes compression to limits still not surpassed by any classical technique.
]

*PAQ1–PAQ4* (2002–2003): Established the basic multi-model arithmetic-coding framework.
*PAQ6* (2003): Introduced a rich model set (byte, word, and position models) that set new records.
*PAQ7* (2005): Alexander Rhatushnyak and others introduced *logistic mixing*, the neural net
  layer. This was the decisive improvement; PAQ7 leapt past all competitors.
*PAQ8* (2006 onward): Dozens of specialized models, SSE stages, and preprocessing transforms.
  The PAQ8 family branched into many variants: `paq8l`, `paq8px`, `paq8pxd`, `paq8kx`, each
  tuned for different data types (text, executable, binary, images).
*paq8px v209* (2025): The community continues. Version 209 of paq8px, released in 2025, added
  LSTM-based models, pre-trained word-level dictionaries, and further SSE tuning. On enwik8
  it achieves approximately 1.27 bits per character, or about 2.7× compression
  on the first 100 MB of English Wikipedia.

#aside[
  PAQ can compress many file types adaptively without being told which type it is. It has no
  hard-coded format parser; instead, its models gradually learn that the data has, say,
  fixed-width 4-byte records (a `struct` binary file) or that alternating bytes follow the
  pattern of a BMP image. This flexibility is both PAQ's strength (one compressor fits all)
  and its weakness (dedicated format compressors can exploit format-specific knowledge better).
]

=== ZPAQ: The Archival Container

One practical problem with PAQ was longevity: a file compressed with `paq8l` from 2006 can only
be decompressed by `paq8l`. If that binary is lost or the OS changes, the data is unrecoverable.
Mahoney solved this in *ZPAQ (2009–2015)* with a clever design: the archive header contains a
complete description of the decompressor in a simple bytecode. A fixed, minimal `zpaq` program
just interprets that bytecode and can therefore decompress files made by any future version
of the compressor it has never seen.

ZPAQ is designed for *archival* use: compress once, decompress reliably decades later. It is the
only general-purpose compressor with this guarantee. Mahoney maintained ZPAQ through version 7.15
(2016), at which point he considered the format stable.

#algo(
  name: "ZPAQ",
  year: "2009",
  authors: "Matt Mahoney",
  aim: "Archival lossless compression with embedded decompressor bytecode, ensuring long-term decodability.",
  complexity: "Similar to PAQ8: slow compression, moderate memory.",
  strengths: "Portability: the single zpaq binary can decompress any future ZPAQ archive; incremental backup support.",
  weaknesses: "Community/tool ecosystem smaller than zip/7z; compression speed similar to PAQ.",
  superseded: "Not superseded for archival; ZPAQ archives made today should remain decompressible indefinitely.",
)[
  ZPAQ archive structure: header block containing a ZPAQL bytecode program that, when
  interpreted by the reference `zpaq` runtime, produces the exact decoding algorithm used
  to create the archive. Data block follows. A future `zpaq` binary only needs the ZPAQL
  interpreter; the decompression logic is inside the archive itself.
]

=== cmix: The Current Champion

*cmix* was started around 2014 by Byron Knoll (Vancouver, Canada). Where PAQ grows organically
by adding models, cmix was engineered for maximum ratio from the start, incorporating a large
LSTM (long short-term memory) neural network alongside hundreds of context models.

The LSTM in cmix is a genuine deep-learning component: a recurrent neural network that processes
the byte stream and produces a prediction of the next byte. This prediction is then fed as one
more model into the logistic mixer alongside all the classical context models. The combination
of deep neural sequence modeling with traditional context statistics is extraordinarily effective.

#note[
  Do not worry if "LSTM," "recurrent neural network," and "long short-term memory" are unfamiliar
  here; they belong to the deep-learning toolkit we build from scratch in Chapter 56. For now,
  treat an LSTM as a black box with one job: it reads the bytes seen so far and outputs a
  probability for the next byte, learning as it goes. Crucially it slots into the *exact same
  socket* as every other model. It just produces a $p_i$ that the logistic mixer blends in. That
  is why a 2014 statistical compressor could bolt a neural network onto a pile of count tables and
  have them cooperate.
]

As of the most recent awarded Hutter Prize record (September 2024), cmix variants hold every
top position on the leaderboard.

== The Hutter Prize: Compressing Human Knowledge

In 2006, Marcus Hutter, the AI researcher who formalized the theory of general intelligence in
terms of compression (AIXI, 2000), founded the *Hutter Prize* with a simple premise: compress
a snapshot of human knowledge as densely as possible, and win money for doing so.

#history[
  Marcus Hutter's theoretical work established that the optimal predictor (the one that
  compresses best) is also the optimal reasoner. His 2000 book *Universal Artificial
  Intelligence* and the AIXI framework (which we preview in Chapter 22 and revisit in
  Chapter 61) show that intelligence and compression are mathematically equivalent. The Hutter
  Prize was a practical bet: if you believe compression equals intelligence, then a prize for
  best compression of Wikipedia is a prize for most machine knowledge.
]

=== The Test Corpus: enwik8 and enwik9

Mahoney chose the first 100 MB of an English Wikipedia XML dump (stripped to plain text) as
the primary benchmark, calling it *enwik8* (100 = $10^8$ bytes). The larger *enwik9* (1 GB =
$10^9$ bytes) was added later and became the Hutter Prize target in 2020.

Wikipedia is a deliberately hard, meaningful benchmark: it contains prose, tables, mathematical
formulas, foreign-language names, dates, URLs, and encyclopedic facts in no particular order.
Compressing it well demands modeling language, structure, and to some extent *knowledge of the
world* (knowing that "Paris is the capital of" is followed by "France").

=== Prize Rules and Record Progression

The prize structure is elegant: beat the current record by $x%$ and collect $x%$ of the total
€500,000 fund (€5,000 per 1% improvement). Constraints prevent brute-force: the decompressor
must run in under approximately 100 hours on a single CPU core, within 10 GB of RAM, with no
GPU, on a standard machine; source code must also be released under a free license.

These constraints are the whole point: a giant pre-trained language model can "compress" enwik9
by simply memorizing it, but that does not demonstrate algorithmic intelligence. The time and
memory limits force the compressor to work with learned statistics, not stored answers.

#scoreboard(
  caption: "Hutter Prize enwik9 record progression (selected milestones).",
  [*Year*], [*Submitter*], [*Program*], [*Bytes on enwik9*], [*bpc*],
  [2020 (baseline)], [(none)], [reference], [116,671,095], [~0.933],
  [2021], [Margaritov], [starlit], [~115,000,000], [~0.920],
  [2023], [Kumar], [fast-cmix], [114,156,155], [0.913],
  [Aug 2024], [Orav], [fx-cmix], [112,578,322], [0.900],
  [Sep 2024], [Orav & Knoll], [*fx2-cmix*], [*110,793,128*], [*0.886*],
)

The current record of 110,793,128 bytes was set in September 2024 by Kaido Orav and Byron Knoll
with *fx2-cmix*, awarded €7,950. It compresses enwik9 from 1,000,000,000 bytes to 110,793,128,
a ratio of 9.02:1 on Wikipedia text. The compression time is measured in *days*; this is not a
practical tool but a scientific measurement of how much algorithmic intelligence knows.

As of June 2026, no new awarded record exists (an experimental entry *jax-compress* by Byron
Knoll was released in March 2026 using a TPU-based neural architecture, but the prize
computation-time rules were under review for GPU/TPU entries).

=== Why Compression = Intelligence (Seriously)

The Hutter Prize is not merely a compression competition. It rests on a deep theoretical
argument.

In Chapter 22 we introduced Kolmogorov complexity: the length of the shortest program that
produces a given string. In Chapter 23 we proved that a perfect predictor is a perfect
compressor. Ray Solomonoff's 1964 *universal prior* gives probability $2^(-K(x))$ to any string
$x$ where $K(x)$ is its Kolmogorov complexity. The shorter the program, the more probable the
string. Hutter showed that an agent maximizing expected reward, using the Solomonoff prior, is
the optimal rational agent (AIXI).

The practical consequence: *to predict the next Wikipedia character correctly, you must "know"
grammar, geography, arithmetic, and encyclopedic facts*. PPM and context mixing approximate
this knowledge through statistical tables; LSTMs approximate it through learned weights; LLMs
approximate it through billions of parameters. They are all playing the identical game.

In 2023, Google DeepMind published "Language Modeling Is Compression" (Delétang et al., ICLR
2024), showing that large language models like Chinchilla and Llama 2 compress enwik8 better
than most classical compressors when paired with arithmetic coding; the math works out exactly
as theory predicts. We will revisit this in Chapter 62, where we build that LLM compressor as
the final tinyzip step.

#misconception[
  "PAQ and cmix are just clever data structures, not really doing anything like thinking."
][
  They are implementing, approximately and computably, the same mathematical ideal (Solomonoff
  induction) that the theoretical frameworks of machine intelligence are based on. The PAQ
  bit-level logistic mixer is a genuine online neural network; cmix's LSTM component is a
  standard deep-learning sequence model. The difference from "AI" is scale and training data,
  not kind. The Hutter Prize exists precisely because the field takes this equivalence seriously.
]

== Compression Levels, Speed, and Practical Use

PPMd, PAQ8, ZPAQ, and cmix all occupy the extreme end of the compression spectrum: maximum
ratio, maximum time, maximum memory. Where do they fit in practice?

*PPMd* (inside 7-Zip, mode "PPMd"):
- Order 6–16, 1 MB to 256 MB memory usage
- Compression speed: 5–50 MB/s; decompression roughly the same
- Best for: dense text archives (source code, books, HTML, email)
- Ratio: typically 15–25% better than DEFLATE on English text

*PAQ8px*:
- Dozens to hundreds of models; 256 MB to 1 GB RAM
- Compression speed: 0.3–3 MB/s
- Best for: maximum-ratio archiving when time is irrelevant
- Not recommended for: anything time-sensitive

*ZPAQ*:
- Similar to PAQ in ratio; adds the archival guarantee
- Has incremental backup support (like `git` for arbitrary files)
- Used by researchers and archivists who need long-term reliability

*cmix*:
- 32 GB RAM recommended; hours per gigabyte
- Used for: Hutter Prize, research, benchmarking, and showing off
- Not used for: any production workload

#pitfall[
  PPMd's compression ratio can be destroyed by a poor choice of order and memory parameters.
  7-Zip defaults to order=6 and memory=16 MB for PPMd, which is fine for typical use, but on very long
  correlated texts (novels, code repositories) raising order to 12 or 16 with 64+ MB memory
  makes a significant difference. Too much order on short files hurts ratio because the model
  never builds reliable high-order statistics.
]

== Context Mixing in Production: Surprising Appearances

You might think context mixing is only for benchmarks. In fact, a stripped-down version runs
inside a surprising number of deployed systems.

*CABAC (Chapter 26)*, the entropy coder inside H.264 and H.265 video, uses context models and
adaptive probability estimation that are direct descendants of PPM ideas. Each syntax element
(motion vector, residual coefficient, transform flag) has its own small adaptive model, updated
after each element. The whole video bitstream is coded with probabilities that adapt in real time.

*LZMA (Chapter 31)* uses range coding (arithmetic coding over a range) driven by context models
for its literal bytes, length codes, and match distances, each with separate adaptive models
updated incrementally. LZMA is architecturally a hybrid: LZ dictionary for matches, PPM-style
context models for the arithmetic coder.

*Zstandard's* finite state entropy (tANS-based Huffman) uses trained frequency tables that are
recomputed per block, which is a simple one-shot version of the same idea.

The context mixing paradigm (run multiple models, blend adaptively) is embedded in
everyday software even if "PAQ" is not a household name.

== Looking Under the Hood: A Context-Mixing Toy

Let us build a tiny, complete bit-level context mixer in Python to see the moving parts.
This is not a #project step (Chapter 33 has no TINYZIP assignment), but it is the most
clarifying code in the chapter.

#gopython("Integer vs float arithmetic in compressors")[
  Real compressors use integer arithmetic for speed: probabilities are stored as integers in
  a fixed range like $[0, 4096]$ rather than floats in $[0.0, 1.0]$. This avoids floating-point
  rounding and allows fast bitwise operations. In our demo we use floats for readability. The
  production pattern is:

  ```python
  # Instead of p = 0.7, store stretched: p_int = int(p * 4096)
  # instead of logit, use a 4096-entry lookup table
  # Weight updates use integer arithmetic with fixed shift amounts
  ```

  This makes the algorithm ~10× faster on modern CPUs with no change in compression ratio.
]

#gopython("Walking two lists together with `zip`")[
  The mixer needs to march through two lists in lock-step: each model's weight $w_i$ alongside
  that model's prediction $p_i$. Python's built-in `zip` does exactly that: it pairs up the
  items of several iterables position by position and hands you one tuple per step:

  ```python
  weights = [0.5, 2.0, -1.0]
  preds   = [0.8, 0.6, 0.9]
  for w, p in zip(weights, preds):
      print(w, p)          # 0.5 0.8 │ 2.0 0.6 │ -1.0 0.9
  ```

  Read `zip(self.weights, preds)` as "take the first weight with the first prediction, the second
  with the second, and so on." If the lists differ in length, `zip` stops at the shorter one. It
  is the clean way to combine parallel lists without juggling an index by hand.
]

```python
# context_mixer_demo.py: a minimal bit-level context mixer
# Python 3.14
import math

def logit(p: float) -> float:
    """Map probability to log-odds. Clamp to avoid infinity."""
    p = max(1e-9, min(1 - 1e-9, p))
    return math.log(p / (1.0 - p))

def sigmoid(s: float) -> float:
    """Map log-odds back to probability."""
    return 1.0 / (1.0 + math.exp(-s))

class BitModel:
    """Order-N bit model: tracks P(next bit = 1 | last N bits)."""

    def __init__(self, order: int = 4) -> None:
        self.order = order
        # counts[context_int] = [count_0, count_1]
        self.counts: dict[int, list[int]] = {}
        self._ctx: int = 0  # sliding context integer

    def predict(self) -> float:
        """Return P(next bit = 1)."""
        c = self.counts.get(self._ctx, [1, 1])
        return (c[1] + 1) / (c[0] + c[1] + 2)  # Laplace-smoothed

    def update(self, bit: int) -> None:
        if self._ctx not in self.counts:
            self.counts[self._ctx] = [1, 1]
        self.counts[self._ctx][bit] += 1
        # Shift in new bit, keep only last `order` bits
        self._ctx = ((self._ctx << 1) | bit) & ((1 << self.order) - 1)

class ContextMixer:
    """Combine multiple BitModels via logistic mixing with online weight learning."""

    def __init__(self, models: list[BitModel], lr: float = 0.005) -> None:
        self.models = models
        self.lr = lr
        self.weights = [1.0 / len(models)] * len(models)

    def predict(self) -> float:
        preds = [m.predict() for m in self.models]
        S = sum(w * logit(p) for w, p in zip(self.weights, preds))
        return sigmoid(S)

    def update(self, bit: int) -> None:
        preds = [m.predict() for m in self.models]
        P = self.predict()
        # Gradient update: move weights toward lower cross-entropy
        for i, p in enumerate(preds):
            self.weights[i] += self.lr * (bit - P) * logit(p)
        for m in self.models:
            m.update(bit)

# Self-test: compress a simple repeating bit pattern
def encode_bits(data: bytes, mixer: ContextMixer) -> float:
    """Return average bits per bit (should be << 1 for predictable patterns)."""
    total_bits = 0
    total_cost = 0.0
    for byte in data:
        for shift in range(7, -1, -1):
            bit = (byte >> shift) & 1
            p = mixer.predict()
            total_cost += -math.log2(p if bit == 1 else 1 - p)
            mixer.update(bit)
            total_bits += 1
    return total_cost / total_bits

if __name__ == "__main__":
    # Test on alternating bytes (very predictable)
    data = bytes([0b10101010, 0b01010101] * 100)
    models = [BitModel(order=o) for o in (1, 2, 4, 8)]
    mixer = ContextMixer(models)
    bpb = encode_bits(data, mixer)
    print(f"Alternating pattern: {bpb:.4f} bits/bit (ideal ≈ 0)")

    # Test on random-ish data
    import os
    data2 = os.urandom(1000)
    models2 = [BitModel(order=o) for o in (1, 2, 4, 8)]
    mixer2 = ContextMixer(models2)
    bpb2 = encode_bits(data2, mixer2)
    print(f"Random data: {bpb2:.4f} bits/bit (ideal ≈ 1)")
```

Running this, the alternating pattern compresses to near 0 bits per bit after just a few cycles
of learning, while random data stays near 1.0. The mixer correctly learns that alternating data
is perfectly predictable.

== Preprocessing: What Goes in Matters

Both PPM and context mixing are model-only; they do not restructure the data before modeling.
But real high-ratio compressors often add preprocessing transforms that make the data more
predictable for the model downstream.

Common preprocessing steps in PAQ and ZPAQ:

*E8/E9 transform:* Re-targets relative CALL addresses in x86 executable files to absolute
addresses. This creates long runs of similar bytes that the context model handles much better
than the original relative offsets (which jump around unpredictably based on code layout).

*Dictionary substitution:* Replace common English words with single-byte tokens (PPMD inside
7-Zip optionally does a simple form of this for document archives).

*BWT (Burrows-Wheeler Transform, Chapter 35):* Not typically used ahead of PPM (PPM makes
better use of raw context order), but BWT is central to bzip2's approach of making similar
characters cluster together.

#pitfall[
  A preprocessing transform that helps one model can hurt another. The E8 transform improves
  PPM and LZ compression of executables dramatically, but applying it to a text file produces
  garbage. Production compressors detect file type (by examining the first few bytes or via
  explicit headers) and apply transforms only when beneficial.
]

== Comparing the Statistical Approaches

#fig(
  [Speed-vs-ratio map of statistical compressors and their dictionary peers, on enwik8.
   The diagonal of better ratio always costs more time; context mixing sits at the extreme
   ratio end. (Numbers approximate for 2024–2026 on a modern CPU.)],
  cetz.canvas({
    import cetz.draw: *
    // Axes
    line((0, 0), (5.5, 0), mark: (end: ">"))
    line((0, 0), (0, 4.5), mark: (end: ">"))
    content((2.8, -0.35), box(width: 5.0cm, align(center, text(size: 8pt)[Compression speed (MB/s, log scale) →])))
    content((-0.4, 2.3), box(width: 1.5cm, align(center, text(size: 8pt)[Ratio →])), angle: 90deg)

    // Points: (x_speed, y_ratio, label)  x: 0=slow..5=fast  y: 0=low..4=high
    let pts = (
      (0.3, 3.8, "cmix"),
      (0.6, 3.5, "paq8px"),
      (1.0, 3.1, "zpaq"),
      (1.6, 2.9, "PPMd-o16"),
      (2.0, 2.5, "PPMd-o6"),
      (2.5, 2.2, "LZMA"),
      (3.2, 1.8, "zstd-19"),
      (4.0, 1.4, "zstd-1"),
      (4.6, 1.0, "lz4"),
    )
    for (x, y, lbl) in pts {
      circle((x, y), radius: 0.09, fill: rgb("#0b5394"), stroke: none)
      content((x + 0.15, y + 0.05), box(width: 1.5cm, text(size: 7pt)[#lbl]))
    }
  })
)

The figure makes the trade-off visual: you can have Zstandard (fast, good ratio) or cmix
(extraordinarily slow, extraordinary ratio), but not both. PPMd sits comfortably in the
"slow but usable" zone: better ratio than LZ codecs, and faster than PAQ by two orders of magnitude.

== Exercises

#exercise("33.1", 1)[
  In PPMC, the escape probability for a context that has seen 5 distinct symbols with total
  count 20 is $5 \/ (20 + 5) = 0.2$. If the escape probability were 0.5 instead, would that
  help or hurt compression of a character that *has* been seen in this context? Explain why.
]
#solution("33.1")[
  It would hurt. Raising the escape probability to 0.5 means only 0.5 of the probability mass
  is shared among the 5 known symbols. If a known symbol had count 10/20 (probability 0.5 of
  the non-escape mass under PPMC), it now gets at most $0.5 times 0.5 = 0.25$, far less than
  the $0.5 times 0.8 = 0.4$ it gets under PPMC. Encoding it costs $-log_2(0.25) = 2$ bits
  instead of $-log_2(0.4) approx 1.32$ bits. Over-escaping wastes bits on the symbols you do know.
]

#exercise("33.2", 1)[
  PPM order-2 is encoding the string "MISSISSIPPI". List all the order-2 contexts that will
  be created after encoding the first 6 characters "MISSIS" and give the count of each symbol
  following each context.
]
#solution("33.2")[
  After encoding M, I, S, S, I, S (updating after each symbol using the two preceding characters
  as context):
  - Context "MI" → {S: 1}
  - Context "IS" → {S: 1, (then S: 2 after second IS)}... let us be precise: the contexts are:
    - After M, I is encoded with context "": updates context "" → {I: 1}. Context "M" → {I: 1}.
    - After I, S: context "MI" → {S: 1}, context "I" → {S: 1}, context "" → {S: 1}.
    - After S, S: context "IS" → {S: 1}, context "S" → {S: 1}, context "" → {S: 2}.
    - After S, I: context "SS" → {I: 1}, context "S" → {S: 1, I: 1}, context "" → {I: 2, S: 2}.
    - After I, S: context "SI" → {S: 1}, context "I" → {S: 2}, context "" → {S: 3, I: 2}.
  So the order-2 tables after "MISSIS": "MI"→{S:1}, "IS"→{S:1}, "SS"→{I:1}, "SI"→{S:1}.
]

#exercise("33.3", 2)[
  Suppose a logistic mixer has two models with weights $w_1 = 2.0$ and $w_2 = -1.5$. Model 1
  predicts $p_1 = 0.8$ and model 2 predicts $p_2 = 0.9$. Compute the mixed probability $P$.
  (Hint: compute $"logit"(p_i) = ln(p_i \/ (1-p_i))$, then $S = w_1 s_1 + w_2 s_2$, then
  $P = 1\/(1 + e^(-S))$.)
]
#solution("33.3")[
  $s_1 = ln(0.8 / 0.2) = ln(4) approx 1.386$. \
  $s_2 = ln(0.9 / 0.1) = ln(9) approx 2.197$. \
  $S = 2.0 times 1.386 + (-1.5) times 2.197 = 2.772 - 3.296 = -0.524$. \
  $P = 1 / (1 + e^(0.524)) = 1 / (1 + 1.689) approx 0.372$.

  Despite both models predicting above 0.5 individually, the negative weight on the high-confidence
  model 2 pulls the result below 0.5. This makes sense if model 2 is known to be systematically
  wrong (its negative weight means "invert this model's prediction").
]

#exercise("33.4", 2)[
  The Hutter Prize requires the decompressor to run in under 100 hours on a single CPU with
  10 GB RAM. A team proposes to cheat by storing a pre-trained 70-billion-parameter LLM inside
  the archive alongside the compressed data (since the LLM predictions are needed for
  decompression). A 70B parameter LLM at 4 bits per parameter requires $70 times 10^9 times 4 / 8$
  bytes of storage. Compute this size and explain why the "trick" fails.
]
#solution("33.4")[
  $70 times 10^9 times 0.5 = 35 times 10^9 = 35 "GB"$. The model alone takes 35 GB, far
  exceeding the 10 GB RAM limit, and the storage of the model in the archive would itself
  be far larger than the enwik9 original (1 GB). The prize rules explicitly forbid this
  approach by constraining memory. More importantly, the goal is to measure algorithmic
  compression, not model memorization.
]

#exercise("33.5", 3)[
  Implement a function `order_k_entropy(data: bytes, k: int) -> float` in Python 3.14 that
  estimates the empirical order-$k$ entropy of `data` in bits per byte. Use the formula:
  $H_k = -sum_(c, x) P(x | c) log_2 P(x | c) dot P(c)$ where the sum is over all contexts $c$
  of length $k$ and all symbols $x$ observed after $c$.
]
#solution("33.5")[
  #pyrecall[
    `defaultdict(int)` from the `collections` module is a dictionary that, when you look up a
    missing key, silently creates it with a default value (`int()` gives `0`) instead of raising an
    error, so `d[k] += 1` just works on a fresh key. `defaultdict(lambda: defaultdict(int))` nests
    this: a missing outer key auto-creates an *inner* counting dictionary. (The `lambda` one-liner
    is from Chapter 16.) It saves the "if key not in dict: create it" dance we wrote by hand earlier.
  ]
  ```python
  import math
  from collections import defaultdict

  def order_k_entropy(data: bytes, k: int) -> float:
      # Count P(c) and P(x | c)
      ctx_counts: dict[bytes, dict[int, int]] = defaultdict(lambda: defaultdict(int))
      for i in range(k, len(data)):
          ctx = bytes(data[i-k:i])
          sym = data[i]
          ctx_counts[ctx][sym] += 1
      total = len(data) - k
      h = 0.0
      for ctx, sym_counts in ctx_counts.items():
          ctx_total = sum(sym_counts.values())
          p_ctx = ctx_total / total
          for count in sym_counts.values():
              p_sym_given_ctx = count / ctx_total
              h -= p_ctx * p_sym_given_ctx * math.log2(p_sym_given_ctx)
      return h

  # Quick test
  data = b"abracadabra" * 100
  for k in range(4):
      print(f"H_{k} = {order_k_entropy(data, k):.3f} bpc")
  ```
  Increasing $k$ should decrease the entropy estimate as contexts become more predictive.
  On truly random data, all orders yield the same entropy (near 8 bits per byte for random bytes).
]

#exercise("33.6", 3)[
  Write a one-paragraph critique of using enwik9 as the benchmark for machine intelligence.
  Address at least: (a) encoding knowledge vs. testing generalization; (b) the 100-hour time
  limit and what it excludes; (c) whether a text-only corpus captures the full range of
  intelligence.
]
#solution("33.6")[
  The Hutter Prize's enwik9 benchmark has both deep strength and genuine weaknesses. Its strength
  is that compressing English prose well requires implicit knowledge of grammar, facts, and
  structure, which is a real proxy for knowledge. Its weaknesses: (a) enwik9 was seen by the program's
  author during development; the program is trained on the test set implicitly, which is not
  the same as generalization to unseen knowledge. (b) The 100-hour CPU limit excludes modern
  GPU/TPU models, which are the actual frontier of learned compression; jax-compress broke the
  limit in March 2026 and the rules may need revision. (c) Intelligence also involves spatial
  reasoning, perception, action planning, and common sense that do not appear in a Wikipedia
  text dump. A program perfectly compressing enwik9 still cannot recognize a face or tie a knot.
  Nevertheless, the prize remains the cleanest single-number proxy for "how much does this
  algorithm know about the world in text form": a useful if incomplete measure.
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/1096090")[Cleary & Witten (1984). "Data Compression Using Adaptive Coding and Partial String Matching." *IEEE Transactions on Communications* 32(4).] The foundational PPM paper.

- #link("https://ieeexplore.ieee.org/document/61469")[Moffat, A. (1990). "Implementing the PPM Data Compression Scheme." *IEEE Transactions on Communications* 38(11).] The definitive PPMC/PPMD engineering reference.

- #link("https://ieeexplore.ieee.org/document/999958")[Shkarin, D. (2002). "PPM: One Step to Practicality." *Data Compression Conference (DCC)*.] PPMII / PPMd.

- #link("https://cs.fit.edu/~mmahoney/compression/nn_paper.pdf")[Mahoney, M. (2000). "Fast Text Compression with Neural Networks." *FLAIRS 2000*.] The paper that spawned PAQ.

- #link("https://en.wikipedia.org/wiki/Context_mixing")[Wikipedia: Context mixing]: surprisingly comprehensive coverage of the PAQ family with links to all variants.

- #link("http://prize.hutter1.net/")[Hutter Prize official site]: current record, rules, and history of all awarded submissions.

- #link("http://www.mattmahoney.net/dc/text.html")[Mahoney, M. Large Text Compression Benchmark (LTCB)]: enwik8 and enwik9 leaderboards; the field's de facto scoreboard.

- #link("https://arxiv.org/abs/2309.10668")[Delétang et al. (2024). "Language Modeling Is Compression." *ICLR 2024*.] DeepMind's proof that LLMs are SOTA lossless compressors; see Chapter 62 for the full treatment.

- #link("https://github.com/kaitz/fx2-cmix")[GitHub: kaitz/fx2-cmix]: source code of the current Hutter Prize champion (September 2024 record).

#takeaways((
  "PPM (Cleary & Witten, 1984) encodes each symbol using the longest available context, escaping to shorter ones when the symbol is unseen. This is the core mechanism for handling the zero-frequency problem.",
  "PPMC (Moffat, 1990) added exclusion and better escape estimation; PPMd (Shkarin, 2002) refined it further with information inheritance and ships inside 7-Zip today.",
  "Context mixing runs many models in parallel, blending predictions via logistic (log-odds) weighted summation, trained online as a one-layer neural network after every bit.",
  "SSE (Secondary Symbol Estimation) corrects systematic biases in the mixed probability through a learned calibration table.",
  "PAQ (Mahoney, 2002) launched a two-decade open-source arms race; logistic mixing (PAQ7, 2005) was the decisive breakthrough; paq8px continues to be updated (v209, 2025).",
  "ZPAQ added an archival guarantee: the decompressor bytecode lives inside the archive, so a single fixed zpaq binary can decompress any future format.",
  "cmix (Knoll, ~2014) holds the current Hutter Prize record: 110,793,128 bytes for enwik9 (September 2024), using an LSTM alongside hundreds of context models.",
  "The Hutter Prize rests on the theoretical equivalence of compression and intelligence: a perfect compressor of Wikipedia would need to 'know' everything in it.",
  "Context mixing ideas appear inside CABAC (H.264/H.265 video) and LZMA, proving the paradigm's impact well beyond exotic benchmarks.",
))

#bridge[
  We have now seen the statistical summit of classical lossless compression: PPM and context
  mixing squeeze English text to as little as 0.9 bits per character. The next chapter, Chapter 34,
  climbs even higher into the ratio champions: PAQ, ZPAQ, and cmix in full detail, examining
  their exact model structures, memory layouts, and the community of researchers who built them.
  After that, Chapter 35 takes a completely different approach: the Burrows-Wheeler Transform,
  which reorganizes data so that ordinary PPM-style modeling becomes far more powerful. It also
  underpins not just bzip2 but the entire field of genome alignment.
]
