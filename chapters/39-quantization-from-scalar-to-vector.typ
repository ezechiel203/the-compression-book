#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// Local worked-example box (styled like the book's admonitions).
#let example(body) = block(width: 100%, breakable: true,
  inset: (x: 11pt, y: 9pt), radius: 4pt, fill: rgb("#eef4fb"),
  stroke: (left: 3pt + rgb("#0b5394")), above: 10pt, below: 10pt)[
  #text(weight: "bold", fill: rgb("#0b5394"), size: 9.5pt, tracking: 0.4pt)[WORKED EXAMPLE]
  #v(2pt)
  #set text(size: 10pt)
  #body
]

= Quantization: From Scalar to Vector

#epigraph[
  "Quantization is the only genuinely lossy step in almost every lossy codec.
  Everything before it merely rearranges; everything after it merely packs.
  The forgetting happens here."
][a working maxim of transform coding]

Hold a ruler up to the world and you will never measure anything exactly. The shelf is
"about 71 centimetres"; your weight this morning was "73-point-something kilograms"; the
temperature is "around 19 degrees". Reality comes in a smooth, unbroken flood of values,
but the moment we want to *write a number down* we are forced to choose one of a finite
list of tick marks and round to it. That act of rounding-to-the-nearest-tick has a name,
and it is the quiet engine inside every photograph, every song, and every video
you have ever streamed. It is called *quantization*.

Here is the puzzle this chapter answers. In Chapter 38 we learned to spin a block of
pixels or audio samples into a new coordinate system (the DCT) so that almost all the
signal's energy piled onto a handful of coefficients and the rest fell close to zero. But
a DCT coefficient like $73.6841...$ is still a real number with, in principle, infinitely
many digits. We have not saved a single bit yet; we have only *rearranged* the bits. The
saving comes when we look at that $73.6841...$ and decide: "for a human eye, $74$ is
close enough." And that nearby coefficient of $0.21$? Round it to $0$ and it vanishes
entirely." Throwing away the digits we don't need is where lossy compression actually
earns its keep.

So the real questions are sharp ones. *Where do we put the tick marks?* Evenly spaced, or
crowded where the data lives? *How coarse can we be* before a human notices? The
deep idea that powers everything from JPEG to the latent codes inside a modern AI image
model: *should we round each number on its own, or round whole groups of numbers
together as a single unit?* That last question is the leap from *scalar* quantization
(one number at a time) to *vector* quantization (a whole tuple at once), and it turns out
to win bits that no amount of per-number cleverness ever can.

#recap[
  This chapter is the third stage of the lossy pipeline we have been assembling. In
  Chapter 21 we met Shannon's *rate--distortion function* $R(D)$: the exact, unbeatable
  trade between bits spent (rate $R$) and error tolerated (distortion $D$), with the
  Gaussian law $R(D) = 1/2 log_2(sigma^2 \/ D)$ giving the famous "6 dB per bit". In
  Chapter 38 we built the *transform* stage (the DCT and its cousins) that decorrelates
  a signal and compacts its energy. Quantization is the bridge between them: it is the
  *only* step that actually discards information, and it is the knob that walks us up and
  down the $R(D)$ curve. We will lean on *expectation* (the weighted average, Chapter 10),
  *variance* (Chapter 10), *logarithms* (Chapter 7), the idea of *entropy* $H(X)$ as the
  bit-floor (Chapters 18--19), and the *Euclidean distance* between vectors (Chapter 12).
  Downstream, the entropy coders of Chapters 24--27 will losslessly pack whatever
  quantization leaves behind. And in tinyzip terms, this is *Step 18*: we finally write
  `quant.py`, the uniform scalar quantizer with a dead-zone that Chapter 42's toy JPEG
  will use.
]

#objectives((
  [Explain what a *quantizer* is as a pair of maps (a forward "which bin?" and an inverse "which value stands for that bin?") and why only the forward map loses information.],
  [Build and analyse the *uniform scalar quantizer*, compute its mean-squared error, and derive the "$Delta^2 \/ 12$" noise law and the 6-dB-per-bit rule from scratch.],
  [Design *non-uniform* quantizers by companding, and state the two *Lloyd--Max conditions* (nearest-neighbour + centroid) that any optimal scalar quantizer must satisfy.],
  [Run *Lloyd's iteration* by hand on a tiny data set and see it converge to a locally optimal codebook.],
  [Add a *dead-zone* and understand why every real image and video codec rounds small coefficients straight to zero.],
  [Explain *dithering*: why deliberately adding noise before quantizing can make the result look and sound better.],
  [Make the jump to *vector quantization*: why coding a whole tuple at once beats coding its parts, and how the *LBG algorithm* learns a codebook.],
  [Trace the living lineage from VQ through *product quantization* (billion-scale vector search) to the *VQ-VAE* codebooks inside today's neural codecs and image generators.],
  [Implement `quant.py` for tinyzip: a uniform scalar quantizer with a tunable dead-zone, round-tripping a stream of DCT coefficients.],
))

== What a quantizer really is

Strip away the jargon and a quantizer is just a machine that takes a number with many
possible values and replaces it with one of a *small, finite* menu of values. A bathroom
scale that reads to the nearest $0.1$ kg is a quantizer. So is rounding money to the
nearest cent. So is the analog-to-digital converter in a microphone that turns a smooth
voltage into one of $65{,}536$ levels.

It helps enormously to see a quantizer as *two* maps working in sequence, because they
behave very differently.

#definition("Quantizer")[
  A *(scalar) quantizer* on the real line is a pair of maps. The *forward map* (or
  *classifier*, or *encoder*) $Q$ sends every input value $x$ to an integer *index*
  $i = Q(x)$, by deciding which of finitely many *decision regions* (or *bins*,
  *cells*) the value $x$ falls into. The *inverse map* (or *reconstruction*,
  *decoder*) $Q^(-1)$ sends each index $i$ back to a single *representative value*
  (or *codeword*, *reproduction level*) $hat(x)_i$ that stands for the whole bin. The
  output of the quantizer on input $x$ is $hat(x) = Q^(-1)(Q(x))$.
]

The split matters because *all the information loss happens in the forward map.* Once you
have decided "$x$ lives in bin number 5", you have thrown away exactly where inside bin 5
it sat. The inverse map adds no further loss; it simply hands you the agreed-upon
stand-in $hat(x)_5$ for everything in that bin. This is why a quantizer can never be
undone: many different inputs collapse to the same index, and there is no way to recover
which one you started with. (Recall Chapter 6: the forward map is not *injective*, being
many-to-one, so it has no true inverse. $Q^(-1)$ is a deliberately chosen best-guess,
not a real undo.)

#keyidea[
  A quantizer is *forget-then-name*: the forward map forgets where in the bin you were
  (this is the lossy part), and the inverse map names a single value to stand for the
  whole bin (this is lossless, but it is where you choose how much the forgetting will
  hurt). Good quantizer design is the art of (1) drawing the bin boundaries and (2)
  choosing each bin's stand-in.
]

We measure how much the forgetting hurts with a *distortion measure*, almost always the
*squared error* $(x - hat(x))^2$, because it is smooth, easy to differentiate, and adds
up nicely. Averaged over all the data a source produces, this gives the *mean-squared
error* (MSE), the quantity every classical quantizer is built to minimise.

#gomaths("Mean-squared error and expectation, in one breath")[
  Suppose a source produces values $x$ with probability density $p(x)$, a curve whose
  height tells you how likely values near $x$ are (Chapter 10). The *mean-squared error*
  of a quantizer is the *expected* (probability-weighted average) squared mistake:
  $ D = EE[(X - hat(X))^2] = integral_(-infinity)^(infinity) (x - Q^(-1)(Q(x)))^2 thin p(x) thin d x. $
  The big "S", $integral$, is just a continuous sum (Chapter 11): chop the line into tiny
  slivers, multiply each sliver's squared error by how probable it is, add them all up.
  If your data is a finite list of $N$ numbers instead of a smooth density, the integral
  becomes an ordinary average:
  $ D = 1/N sum_(n=1)^(N) (x_n - hat(x)_n)^2. $
  *Tiny example.* The four numbers $1, 2, 3, 4$ are each rounded to the single value
  $hat(x) = 2.5$. The squared errors are $(1-2.5)^2 = 2.25$, $0.25$, $0.25$, $2.25$, so
  $D = (2.25+0.25+0.25+2.25)\/4 = 1.25$. Notice $2.5$ is the *mean* of the four numbers.
  That is no accident, as we will prove shortly.
]

#aside[
  Why squared error and not, say, the plain absolute error $abs(x - hat(x))$? Three
  reasons that recur throughout the book: squared error has a clean derivative
  everywhere (the absolute value has a kink at zero), it makes the optimal stand-in the
  ordinary *mean* (the absolute error would demand the *median*), and it matches the
  *energy* language of Chapter 38, where an orthonormal transform conserves total squared
  length. The catch (which Chapters 41 and 46 will dwell on) is that squared error is
  *perceptually wrong*: the human eye and ear do not weight all errors equally. For now we
  optimise squared error because it is tractable; later we bend it toward perception.
]

== The uniform scalar quantizer

The simplest quantizer puts its tick marks at *evenly spaced* intervals. Pick a *step
size* $Delta$ (the gap between neighbouring reconstruction values). To quantize, divide by
$Delta$, round to the nearest whole number, and multiply back:

$ hat(x) = Delta dot.c "round"(x \/ Delta). $

That is the entire algorithm. If $Delta = 10$, then $73.6841$ becomes
$10 times "round"(7.36841) = 10 times 7 = 70$; the value $48.2$ becomes $50$; the value
$4.9$ becomes $0$. Every input within $±5$ of a multiple of ten collapses onto that
multiple. The bins are the intervals $[-5, 5), [5, 15), [15, 25), dots$, and each bin's
stand-in sits at its centre.

#example[
  Quantize the DCT coefficients $73.68, -12.4, 0.21, 48.9, -3.1$ with step $Delta = 16$
  (a plausible JPEG-ish step for a mid-frequency coefficient).
  + $73.68 \/ 16 = 4.605 -> "round" -> 5 -> hat(x) = 80$.
  + $-12.4 \/ 16 = -0.775 -> "round" -> -1 -> hat(x) = -16$.
  + $0.21 \/ 16 = 0.013 -> "round" -> 0 -> hat(x) = 0$.
  + $48.9 \/ 16 = 3.056 -> "round" -> 3 -> hat(x) = 48$.
  + $-3.1 \/ 16 = -0.194 -> "round" -> 0 -> hat(x) = 0$.
  Two of the five coefficients ($0.21$ and $-3.1$) were rounded to *exactly zero*. That is
  the magic of the transform-plus-quantize combination: after the DCT compacts energy, most
  coefficients are small, and a coarse step turns a long list of numbers into a short list
  of non-zeros padded with runs of zeros, exactly what the entropy coder of Chapter 24
  devours. The five stored *indices* are $5, -1, 0, 3, 0$, small integers an entropy coder
  can pack tightly.
]

The genius of the uniform quantizer is that it stores only the *indices*
$i = "round"(x\/Delta)$ (here $5, -1, 0, 3, 0$), not the reconstructed values. The decoder
multiplies each index by the agreed step $Delta$ to rebuild $hat(x)$. Smaller numbers,
fewer distinct values, lots of zeros: pure food for entropy coding.

#fig([A uniform scalar quantizer with step $Delta$. The smooth input line (the diagonal)
  is replaced by a staircase: every input in a bin of width $Delta$ snaps to that bin's
  central reconstruction dot. The vertical gap between line and stair is the quantization
  error, which never exceeds $Delta\/2$.],
  cetz.canvas({
    import cetz.draw: *
    line((-0.2,0),(6.2,0), mark: (end: ">"))
    line((0,-0.2),(0,4.2), mark: (end: ">"))
    content((6.4,0))[$x$]
    content((0,4.5))[$hat(x)$]
    line((0,0),(4,4), stroke: (dash: "dashed", paint: rgb("#9a2617")))
    let d = 1
    for k in range(0,4) {
      let x0 = k*d
      let x1 = (k+1)*d
      let y = (k+0.5)*d
      line((x0,y),(x1,y), stroke: 1.2pt + rgb("#0b5394"))
      circle(((x0+x1)/2, y), radius: 0.05, fill: rgb("#0b5394"), stroke: none)
    }
    line((2,-0.15),(3,-0.15), stroke: rgb("#783f04"))
    content((2.5,-0.45))[$Delta$]
    content((4.9,3.9), text(fill: rgb("#9a2617"), size: 8pt)[ideal $hat(x)=x$])
  })
)

=== How much error does it make? The $Delta^2\/12$ law

Here is one of the most useful little facts in all of signal compression, and we can
derive it from scratch. Suppose the data is reasonably busy, fine-grained, with no value
overwhelmingly more likely than its neighbours, so that *inside any one bin* the input is
about equally likely to land anywhere. Then the quantization error $e = x - hat(x)$ is a
value spread *uniformly* across the bin, from $-Delta\/2$ to $+Delta\/2$. What is its
average squared size?

#gomaths("The average squared value of a uniform error")[
  Let the error $e$ be equally likely anywhere in the interval $[-Delta\/2, +Delta\/2]$.
  Its probability density is flat: it has constant height $1\/Delta$ across that width
  (so the total area, height times width, is $1$; every probability density must
  integrate to $1$). The *mean* error is $0$ by symmetry. The *mean square* is
  $ EE[e^2] = integral_(-Delta\/2)^(+Delta\/2) e^2 dot.c 1/Delta thin d e. $
  We need the integral of $e^2$. From the gentle calculus of Chapter 11, the area under
  $e^2$ from $0$ to $b$ is $b^3\/3$ (each power $e^n$ integrates to $e^(n+1)\/(n+1)$).
  So between $-Delta\/2$ and $+Delta\/2$ the integral of $e^2$ is
  $2 times (Delta\/2)^3 \/ 3 = Delta^3\/12$. Multiply by the height $1\/Delta$:
  $ EE[e^2] = 1/Delta dot.c Delta^3/12 = Delta^2/12. $
  *Tiny check.* With $Delta = 16$, the noise power is $16^2\/12 = 256\/12 approx 21.3$,
  so the typical error is about $sqrt(21.3) approx 4.6$, comfortably under the worst
  case of $Delta\/2 = 8$, exactly as you'd expect for an average versus a maximum.
]

So the quantization noise power of a uniform quantizer is
$ D = Delta^2 / 12, $
the single most quoted formula in the subject. It says the error grows with the *square*
of the step size: halve the step and you cut the noise power by four. This is the lever
every codec pulls.

#keyidea[
  *Uniform quantizer noise law:* $D = Delta^2\/12$. Halving the step size $Delta$ quarters
  the mean-squared error. Because each extra bit of precision *halves* the step (one more
  bit = twice as many levels = half the spacing), each extra bit *quarters* the noise.
]

=== Where the "6 dB per bit" rule comes from

Engineers love to talk about quantization quality in *decibels* of signal-to-noise ratio.
We can now derive the rule of thumb that every audio and imaging textbook quotes, and
connect it straight back to Shannon's $R(D)$ from Chapter 21.

Suppose we have $R$ bits per sample, giving $2^R$ levels. If the signal swings across a
range of width $A$, the step size is $Delta = A \/ 2^R$. Plug into the noise law:
$ D = Delta^2 / 12 = A^2 / (12 dot.c 2^(2R)) = A^2 / (12 dot.c 4^R). $
Every time $R$ goes up by one, the denominator multiplies by $4$, so the noise $D$
*divides by 4*. In decibel language a factor of $4$ in power is
$10 log_10 4 approx 6.02$ dB. Hence:

#theorem("6 dB per bit")[
  For a uniform quantizer on a signal of fixed range, each additional bit of precision
  improves the signal-to-quantization-noise ratio by about $6.02$ dB, because it halves
  the step and therefore quarters the noise power.
]

#gomaths("Decibels: turning ratios into a friendly scale")[
  A *decibel* (dB) is a way of writing a power ratio on a logarithmic scale so that huge
  ratios become small, addable numbers. For a power ratio $r$, the value in decibels is
  $10 log_10 r$. A ratio of $10$ is $10$ dB; a ratio of $100$ is $20$ dB; a ratio of $2$
  is $approx 3.01$ dB; a ratio of $4$ is $approx 6.02$ dB. The *signal-to-noise ratio*
  (SNR) in dB is $10 log_10(P_"signal" \/ P_"noise")$; bigger is cleaner. Because $log$
  turns multiplication into addition (Chapter 7), every doubling of the SNR ratio simply
  *adds* about $3$ dB, and every quadrupling adds about $6$ dB. That is why "$6$ dB per
  bit" is such a tidy slogan: one more bit, one more factor of $4$, one more $6$ dB.
]

#aside[
  This is *exactly* the same "6 dB per bit" we met in Chapter 21 for the Gaussian
  rate--distortion curve $R(D) = 1/2 log_2(sigma^2\/D)$. There it dropped out of pure
  information theory; here it drops out of the geometry of evenly spaced tick marks. The
  two agree because, for a smooth source, a well-designed quantizer followed by an entropy
  coder gets within a small constant of the Shannon bound. Quantization is how the abstract
  $R(D)$ curve becomes an actual knob you can turn. The constant gap, for a uniform
  quantizer on a smooth source, is about $0.255$ bits per sample. This is the famous
  "$1.53$ dB" or "$pi e \/ 6$" penalty, money left on the table that fancier quantizers
  try to recover.
]

#gopython("From `round()` to a vectorised quantizer")[
  Python's built-in `round(x)` rounds to the nearest integer, with one quirk worth knowing:
  it uses *banker's rounding* (round-half-to-even), so `round(0.5) == 0` and
  `round(1.5) == 2`. For quantization we usually want plain arithmetic rounding, which we
  get with `math.floor(x + 0.5)`. Here is a one-number uniform quantizer and its inverse:
  ```python
  import math

  def q_forward(x: float, delta: float) -> int:
      "Map a real value to its integer bin index."
      return math.floor(x / delta + 0.5)

  def q_inverse(i: int, delta: float) -> float:
      "Map a bin index back to its representative value."
      return i * delta

  i = q_forward(73.68, 16.0)      # -> 5
  xhat = q_inverse(i, 16.0)       # -> 80.0
  ```
  The `-> int` and `-> float` after the parentheses are *type hints* (Chapter 16): notes
  to the reader (and to tools) saying "this function takes/returns these types". Python
  does not enforce them at run time, but they make code self-documenting. We will build the
  full, stream-oriented version in this chapter's tinyzip step.
]

== Non-uniform quantization: put the tick marks where the data lives

Uniform spacing is only optimal when the data is spread evenly. Real signals are not.
A DCT coefficient, an audio sample, a pixel difference: these cluster heavily near zero
and thin out toward the extremes; their histogram is a tall spike in the middle with long
shallow tails (a Laplacian or Gaussian shape, Chapter 10). If most of your values land
near zero, it is wasteful to give the far-out region the same fine tick spacing as the
crowded centre. You want *fine* tick marks where the data is dense and *coarse* tick marks
where it is sparse: small bins for common values, big bins for rare ones.

#keyidea[
  *Spend resolution where the probability is.* A good non-uniform quantizer uses many
  closely-spaced levels in high-probability regions and few widely-spaced levels in
  low-probability regions. This is the same instinct as a variable-length code (Chapter
  24): short codes for common symbols. Here it is *fine bins* for common values.
]

=== Companding: squash, quantize uniformly, un-squash

The oldest trick for building a non-uniform quantizer is *companding*, a portmanteau of
*compress* and *expand*. Instead of designing irregular bins directly, you:

+ pass the value through a *compressor* function $c(x)$ that squashes the wide tails inward
  and stretches the crowded centre outward;
+ apply an ordinary *uniform* quantizer to the squashed value;
+ pass the result through the inverse *expander* $c^(-1)$ to undo the warp.

Because the uniform bins in the squashed world correspond to *unequal* bins in the
original world (narrow where $c$ stretched, wide where $c$ squeezed), you get
non-uniform quantization for free, using only a uniform quantizer plus two
warp functions.

#history[
  Companding is why your phone call sounds the way it does. The global telephone network
  digitises speech at just $8$ bits per sample, but a *uniform* $8$-bit quantizer would
  sound terrible: quiet speech (most of speech, energetically) would be drowned in
  quantization hiss while loud bursts were over-served. The fix, standardised in the
  1970s as ITU-T G.711, is *logarithmic companding*: the *$mu$-law* curve in North
  America and Japan ($mu = 255$) and the *A-law* curve in Europe ($A = 87.6$). Both squash
  the signal through a logarithm-shaped $c(x)$ before a uniform quantizer, so the *relative*
  error stays roughly constant across loud and quiet, matching the ear, which hears in
  ratios, not absolutes. Half a century on, G.711 still carries an astonishing fraction of
  the world's voice traffic.
]

#fig([Companding. The compressor $c(x)$ (left) is steep near zero and flat in the tails,
  so uniform tick marks on the vertical axis pull back to *unequal* tick marks on the
  horizontal axis (right): fine spacing near zero where data is dense, coarse spacing far
  out where it is sparse.],
  cetz.canvas({
    import cetz.draw: *
    // left: a log-like compressor curve
    line((0,0),(3.2,0), mark: (end: ">")); line((0,0),(0,2.4), mark: (end: ">"))
    content((3.4,0))[$x$]; content((0,2.7))[$c(x)$]
    let pts = ((0,0),(0.3,0.9),(0.7,1.4),(1.2,1.75),(1.9,2.0),(3.0,2.25))
    line(..pts, stroke: 1.3pt + rgb("#0b5394"))
    // uniform ticks on vertical, projected to horizontal
    for y in (0.5,1.0,1.5,2.0) {
      line((0,y),(0.1,y), stroke: rgb("#783f04"))
    }
    content((1.6,-0.45), text(size:7.5pt)[compressor: steep then flat])
  })
)

The $mu$-law compressor used in telephony is a concrete logarithmic warp. For a signal
scaled to $[-1, 1]$ it is
$ c(x) = "sign"(x) dot.c (ln(1 + mu abs(x))) / (ln(1 + mu)), $
with $mu = 255$. The $ln$ here is the *natural logarithm* (log to base $e approx 2.718$,
Chapter 7); any base would give the same shape up to a constant. Notice $c$ is steep near
$x = 0$ (small inputs get spread out, so they earn fine bins) and flat for large $abs(x)$
(big inputs get squashed together into coarse bins).

#example[
  *$mu$-law in action ($mu = 255$).* A quiet sample $x = 0.02$ maps to
  $c(0.02) = ln(1 + 255 times 0.02)\/ln(256) = ln(6.1)\/ln(256) = 1.808\/5.545 approx 0.326$
  This is pulled far from zero, so the uniform quantizer that follows gives it fine resolution.
  A loud sample $x = 0.8$ maps to $c(0.8) = ln(1 + 204)\/ln(256) = 5.323\/5.545 approx 0.960$,
  already near the top, packed close to its neighbours, so it gets coarse resolution.
  The quiet sample, $40times$ smaller than the loud one in the raw signal, is only about
  $3times$ smaller after companding: the warp has equalised their treatment, exactly as the
  ear (which hears ratios) wants.
]

#gopython("$mu$-law companding round-trip")[
  Companding is three steps (compress, (uniform) quantize, expand), and the compressor
  and its inverse are short. We import `math` for the natural log `math.log` and the
  exponential `math.exp`, and `copysign` to carry the sign through:
  ```python
  import math

  def mu_compress(x: float, mu: float = 255.0) -> float:
      "Squash x in [-1,1] toward the edges (steep near 0)."
      return math.copysign(math.log(1 + mu * abs(x)) / math.log(1 + mu), x)

  def mu_expand(y: float, mu: float = 255.0) -> float:
      "Inverse: undo the mu-law warp."
      return math.copysign(((1 + mu) ** abs(y) - 1) / mu, y)

  x = 0.02
  y = mu_compress(x)            # ~0.326  (pulled away from zero)
  back = mu_expand(y)           # ~0.02   (round-trips)
  print(round(y, 3), round(back, 3))
  ```
  `math.copysign(a, b)` returns `a` with the sign of `b`, a tidy way to make an
  odd-symmetric function without an `if`. In a real codec you would insert a uniform
  `q_forward`/`q_inverse` (from the earlier box) *between* `mu_compress` and `mu_expand`;
  here we show the warp alone round-trips, which is the part that makes the bins non-uniform.
]

=== The optimal scalar quantizer: the two Lloyd--Max conditions

Companding is a clever heuristic, but is there a *best possible* non-uniform quantizer for
a given source: the one with the smallest mean-squared error for a fixed number of
levels? Yes, and the answer was found independently by two people whose names the
quantizer now carries.

#history[
  *Stuart P. Lloyd* worked out the iterative design at Bell Labs in *1957*, in an internal
  technical memorandum on pulse-code modulation. Astonishingly, his manuscript circulated
  by photocopy for a quarter-century before finally appearing in print in the *IEEE
  Transactions on Information Theory* in *1982*. Meanwhile *Joel Max*, working
  independently, published the same conditions in *1960*. So the optimal scalar quantizer
  is the *Lloyd--Max quantizer*, and the iterative algorithm that finds it is *Lloyd's
  algorithm*, the very same procedure that, applied to vectors, the rest of the world
  calls *k-means clustering*.
]

The reasoning is a beautiful "chicken and egg" that splits the design into two halves,
each easy once you pretend the other is fixed. Suppose the quantizer has bins with
boundaries $b_0 < b_1 < dots < b_L$ and reconstruction values $hat(x)_1, dots, hat(x)_L$
(one per bin). We want to choose all of them to minimise
$D = sum_(k) integral_(b_(k-1))^(b_k) (x - hat(x)_k)^2 thin p(x) thin d x$.

*Condition 1: the nearest-neighbour rule (best boundaries, given the values).* If the
reconstruction values are fixed, where should the boundary between bin $k$ and bin $k+1$
go? Exactly *halfway* between their reconstruction values:
$ b_k = (hat(x)_k + hat(x)_(k+1)) / 2. $
Any value should be assigned to whichever reconstruction point is *closer*; putting the
boundary at the midpoint guarantees that. (If a value sat on the far side of the midpoint
from its assigned point, moving it to the other bin would shrink its error.)

*Condition 2: the centroid rule (best values, given the boundaries).* If the boundaries
are fixed, where should each reconstruction value go? At the *centroid*, the
probability-weighted *mean*, of the values that fall in its bin:
$ hat(x)_k = (integral_(b_(k-1))^(b_k) x thin p(x) thin d x) / (integral_(b_(k-1))^(b_k) p(x) thin d x) = EE[X mid(|) X in "bin" k]. $
This is exactly the fact we noticed earlier: the single value that minimises mean-squared
error over a set of numbers is their *mean*. We can prove it in one line.

#theorem("The mean minimises squared error")[
  For any set of numbers (or any distribution), the constant $hat(x)$ that minimises
  $EE[(X - hat(x))^2]$ is $hat(x) = EE[X]$, the mean.
]
#proof[
  Expand $EE[(X - hat(x))^2] = EE[X^2] - 2 hat(x) EE[X] + hat(x)^2$, a simple upward
  parabola in the variable $hat(x)$. From the gentle calculus of Chapter 11, its minimum
  is where the derivative with respect to $hat(x)$ is zero:
  $-2 EE[X] + 2 hat(x) = 0$, i.e. $hat(x) = EE[X]$. The second derivative is $+2 > 0$, so
  it is indeed a minimum, not a maximum.
]

#definition("Lloyd--Max optimality conditions")[
  A scalar quantizer minimising mean-squared error must satisfy *both* conditions
  simultaneously: (1) *nearest-neighbour*, meaning each bin boundary sits midway between its two
  neighbouring reconstruction values; and (2) *centroid*, meaning each reconstruction value sits
  at the mean of the data inside its bin. Neither alone is enough; the optimum is a
  *fixed point* where both hold at once.
]

=== Lloyd's iteration: alternate until it settles

Because each condition is easy to enforce when the other half is held fixed, we get an
algorithm by simply *alternating* between them: fix the values, fix the boundaries to
their midpoints; then fix the boundaries, move each value to its bin's mean; repeat. Each
step can only *decrease* (never increase) the distortion, and distortion can't go below
zero, so the process must converge.

#algo(
  name: "Lloyd's algorithm (Lloyd--Max quantizer design)",
  year: "1957 (Lloyd, pub. 1982); 1960 (Max)",
  authors: "Stuart P. Lloyd; Joel Max",
  aim: "Find the L-level scalar quantizer with minimum mean-squared error for a given source distribution or data set.",
  complexity: "Each iteration is linear in the data size; a handful of iterations usually suffice. Converges to a local optimum.",
  strengths: "Provably non-increasing distortion; simple; the exact 1-D ancestor of k-means and of the LBG vector algorithm.",
  weaknesses: "Only locally optimal (sensitive to the starting levels); needs the source statistics or training data; assumes squared error.",
  superseded: "Generalised to vectors by the LBG / k-means algorithm; perceptual codecs replace MSE with a perceptual distortion.",
)[
  *Input:* training data (or density $p$), number of levels $L$. *Output:* boundaries
  $b_k$ and reconstruction values $hat(x)_k$.
  + Initialise $L$ reconstruction values (e.g. spread them evenly across the data range).
  + *Assign (nearest-neighbour):* put each boundary $b_k$ at the midpoint of neighbouring values; this assigns every data point to its closest reconstruction value.
  + *Update (centroid):* set each $hat(x)_k$ to the mean of the data points assigned to bin $k$.
  + Compute the total distortion $D$. If it dropped by less than a tiny threshold since the last round, stop; otherwise go to step 2.
]

#example[
  *Lloyd's iteration by hand, $L = 2$ levels.* Data: $1, 2, 3, 9, 10, 11$ (two tight
  clusters). Start with reconstruction values guessed at $hat(x)_1 = 0$, $hat(x)_2 = 6$.

  *Round 1, assign.* Boundary midway: $(0+6)\/2 = 3$. Points $<= 3$ go to bin 1
  ($1,2,3$); points $> 3$ go to bin 2 ($9,10,11$). *Update.* Bin means:
  $hat(x)_1 = (1+2+3)\/3 = 2$, $hat(x)_2 = (9+10+11)\/3 = 10$. Distortion:
  each point is now within $1$ of its centre, $D = (1+0+1+1+0+1)\/6 = 0.667$.

  *Round 2, assign.* New boundary $(2+10)\/2 = 6$. Same split ($1,2,3$ vs $9,10,11$).
  *Update.* Same means $2$ and $10$. Nothing moved; we have reached a *fixed point*.
  The algorithm converged in one real step to the obvious answer: one level per cluster,
  each sitting at its cluster's mean. A *uniform* 2-level quantizer would have placed its
  levels by range alone and done far worse; Lloyd's found where the data actually lives.
]

#pitfall[
  Lloyd's algorithm finds only a *local* optimum; the answer it lands on depends on where
  you start. Bad initial levels can trap it in a poor configuration (for instance, two
  reconstruction values both stuck inside the same cluster while a far cluster gets only
  one). In practice you run it from several random starts and keep the best, or use a
  smart initialiser. This local-optimum caveat carries over verbatim to its vector cousin,
  the LBG algorithm, and to k-means everywhere in machine learning.
]

#gopython("Lloyd's iteration in a dozen lines")[
  The whole algorithm is two helpers in a loop. `assign` buckets each value with its
  nearest level; `update` moves each level to its bucket's mean. We use a `dict[int, list]`
  (Chapter 16) keyed by bin index to gather the buckets:
  ```python
  def lloyd(data: list[float], levels: list[float],
            rounds: int = 20) -> list[float]:
      "Refine reconstruction `levels` to a local MSE optimum on `data`."
      for _ in range(rounds):
          buckets: dict[int, list[float]] = {j: [] for j in range(len(levels))}
          for x in data:                       # assign: nearest level
              j = min(range(len(levels)), key=lambda k: (x - levels[k]) ** 2)
              buckets[j].append(x)
          new = [sum(b) / len(b) if b else levels[j]   # update: bucket mean
                 for j, b in buckets.items()]
          if new == levels:                    # fixed point -> done
              return new
          levels = new
      return levels

  print(lloyd([0, 1, 2, 8, 9, 10], [3.0, 7.0]))   # -> [1.0, 9.0]
  ```
  The `if b else levels[j]` guard keeps an *empty* bucket's level where it was instead of
  dividing by zero, a small but essential robustness detail that LBG handles the same way.
]

== The dead-zone: rounding small values straight to zero

Real image and video codecs do not use a plain uniform quantizer. They use one with a
twist that matters enormously for compression: a *widened bin around zero*, called a
*dead-zone*. Every coefficient whose magnitude falls inside the dead-zone is rounded to
*exactly zero*, even if a plain uniform quantizer would have nudged it to $±1$.

Why deliberately widen the zero bin? Two reasons, both decisive.

First, *zeros are nearly free.* After the DCT (Chapter 38) most coefficients are already
tiny. An entropy coder loves long runs of zeros: run-length coding plus Huffman (as in
JPEG, Chapter 42) can pack "forty zeros in a row" into a few bits. A coefficient quantized
to $±1$, by contrast, costs a real symbol *and* breaks the run. So turning marginal small
values into zeros is hugely cheaper than coding them as $±1$, for a barely-perceptible
loss of accuracy on coefficients that were already close to zero.

Second, those marginal values are *the least trustworthy and least visible* part of the
signal: small high-frequency wiggles that are often as much noise as content, and that the
eye barely registers. Killing them is almost pure win.

#definition("Dead-zone scalar quantizer")[
  A uniform quantizer with a central bin of width $2 z$ (the *dead-zone*) wider than the
  regular step $Delta$. Inputs with $abs(x) < z$ map to index $0$ (reconstruction $0$);
  outside the dead-zone the bins are the usual width $Delta$. A common, hardware-friendly
  form combines a step $Delta$ with a *rounding offset* $f in [0, 1\/2]$:
  $ i = "sign"(x) dot.c floor( abs(x) / Delta + f ), $
  and reconstruction $hat(x) = i dot.c Delta$. Smaller $f$ means a *bigger* dead-zone
  (more coefficients pushed to zero); $f = 1\/2$ recovers ordinary rounding (no
  dead-zone). The H.264 and HEVC video standards (Chapters 52--53) use exactly this
  offset-controlled form, typically with $f approx 1\/3$ for predicted (inter) blocks and
  $f approx 1\/6$ for intra blocks, a small constant that quietly buys a lot of bits.
]

#example[
  *Dead-zone vs plain rounding.* Step $Delta = 16$, offset $f = 1\/6 approx 0.167$.
  Take the coefficient $x = 9.5$. Plain rounding ($f = 0.5$): $floor(9.5\/16 + 0.5) =
  floor(0.594 + 0.5) = floor(1.094) = 1$, reconstruct to $16$. Dead-zone ($f = 1\/6$):
  $floor(9.5\/16 + 0.167) = floor(0.594 + 0.167) = floor(0.761) = 0$, so it vanishes. The
  value $9.5$ was on the fence; the dead-zone tips it to zero, costing one small unit of
  accuracy but possibly extending a run of zeros worth several bits. A value of $x = 13$,
  on the other hand: $floor(13\/16 + 0.167) = floor(0.979) = 0$ under the dead-zone too,
  whereas $x = 14$: $floor(0.875 + 0.167) = floor(1.042) = 1$ survives. The dead-zone
  boundary for the first non-zero bin sits at $x = (1 - f) Delta = (1 - 0.167) times 16
  approx 13.3$.
]

#fig([A dead-zone quantizer. The central bin around zero (shaded) is wider than the
  regular step $Delta$, so small coefficients are rounded all the way to $0$ rather than
  to $±1$, extending the zero-runs that the entropy coder packs almost for free.],
  cetz.canvas({
    import cetz.draw: *
    line((-4,0),(4,0), mark: (end: ">"))
    content((4.2,0))[$x$]
    // dead zone shaded
    rect((-1.3,-0.25),(1.3,0.25), fill: rgb("#9a2617").lighten(75%), stroke: none)
    // regular bin marks
    for b in (-3.5,-2.4,-1.3,1.3,2.4,3.5) {
      line((b,-0.25),(b,0.25), stroke: 0.8pt + rgb("#0b5394"))
    }
    // reconstruction dots
    for (cx, lab) in ((0,$0$),(1.85,$1$),(2.95,$2$),(-1.85,$-1$),(-2.95,$-2$)) {
      circle((cx,0), radius: 0.06, fill: rgb("#0b5394"), stroke: none)
      content((cx,0.55), text(size:8pt)[#lab])
    }
    content((0,-0.6), text(size:7.5pt, fill: rgb("#9a2617"))[dead-zone $2z$])
  })
)

== Dithering: adding noise on purpose to hide quantization

Here is a counter-intuitive trick that audio and image engineers swear by: sometimes you
get a *better-looking* (or better-sounding) result by adding a little random noise *before*
you quantize. It sounds mad (we are trying to remove information, why add noise?) but it
solves a real perceptual problem.

When a smooth gradient (a clear sky fading from light to dark, or a slow fade-out at the
end of a song) is quantized coarsely, the rounding errors are not random; they are
*correlated* with the signal. The result is *banding*: visible stair-step contours where
the gradient jumps from one level to the next, or, in audio, a gritty distortion that
tracks the melody. Our eyes and ears are exquisitely tuned to spot *structured* error;
they barely notice *random* error of the same size.

*Dither* breaks the structure. By adding a tiny bit of random noise (typically uniform
over one quantizer step) before rounding, you *decorrelate* the quantization error from
the signal: it becomes a faint, even hiss instead of hard contour lines. The total error
power is slightly *larger*, but it is spread out and unstructured, so the result looks and
sounds *cleaner*. The banding dissolves into imperceptible grain.

#keyidea[
  *Dithering trades structured error for random error.* The eye and ear forgive random
  noise far more readily than the banding and contouring of correlated quantization error.
  A pinch of pre-quantization noise turns ugly stair-steps into invisible grain, for the same
  reason a newspaper printed gritty halftone photos rather than hard black-and-white
  blocks.
]

#aside[
  Dither has a deeper magic in audio. With the right noise (and a refinement called
  *noise shaping*, which pushes the dither energy up into frequencies the ear can't hear),
  a dithered $16$-bit recording can preserve detail *quieter than its least significant
  bit*, information that would otherwise be lost entirely to the rounding. The
  noise acts as a kind of carrier that smuggles sub-bit information through, on average.
  This is why mastering engineers always dither when reducing a $24$-bit master to a
  $16$-bit CD.
]

#misconception[Quantization noise is always something to avoid, so adding noise can only make things worse.][
  Quantization noise that is *correlated* with the signal (banding, contouring) is far more
  objectionable than uncorrelated noise of equal or even slightly greater power. Dithering
  deliberately *increases* total noise power a little; the noise becomes random and
  unstructured, and the perceptual result improves. The goal was never minimum noise; it
  was minimum *perceived* distortion.
]

#project("Step 18 · quant.py: a uniform scalar quantizer with a dead-zone")[
  Time to make this real. tinyzip's lossy path (the toy JPEG of Chapter 42) needs to turn
  the floating-point DCT coefficients from Step 17's `transform.py` into small integers,
  with a dead-zone so small coefficients become zeros. We write `quant.py` with a tiny,
  typed, round-tripping API: a forward map (coefficients → integer indices) and an inverse
  map (indices → reconstructed coefficients). We reuse nothing from earlier steps here
  except the project's conventions (type hints everywhere; `list` in, `list` out for the
  coefficient stream).

  ```python
  # tinyzip/quant.py  - Step 18: uniform scalar quantizer + dead-zone
  """Uniform scalar quantization for the lossy pipeline.

  forward()  maps real coefficients to small integer indices.
  inverse()  maps indices back to reconstructed coefficients.
  A rounding offset f in [0, 0.5] sets the dead-zone width:
    f = 0.5  -> ordinary rounding, no dead-zone
    f < 0.5  -> wider zero bin (more zeros, more compression)
  """
  import math


  def q_index(x: float, delta: float, f: float = 0.5) -> int:
      "Forward map: real coefficient -> integer bin index (with dead-zone)."
      if x >= 0:
          return math.floor(x / delta + f)
      else:
          return -math.floor(-x / delta + f)


  def q_value(i: int, delta: float) -> float:
      "Inverse map: integer index -> reconstructed coefficient."
      return i * delta


  def forward(coeffs: list[float], delta: float, f: float = 0.5) -> list[int]:
      "Quantize a whole stream of coefficients to indices."
      return [q_index(x, delta, f) for x in coeffs]


  def inverse(indices: list[int], delta: float) -> list[float]:
      "Reconstruct coefficients from a stream of indices."
      return [q_value(i, delta) for i in indices]


  def mse(a: list[float], b: list[float]) -> float:
      "Mean-squared error between two equal-length streams."
      return sum((x - y) ** 2 for x, y in zip(a, b)) / len(a)
  ```

  The list comprehension `[q_index(x, delta, f) for x in coeffs]` (Chapter 16) is just a
  compact `for`-loop that builds a new list. The `zip(a, b)` in `mse` walks two lists in
  lockstep, pairing `a[0]` with `b[0]`, and so on. A quick self-test confirms it
  round-trips structurally (indices in, coefficients out, error bounded by the step) and
  that a smaller offset really does create more zeros:

  ```python
  # tinyzip/tests/test_quant.py
  from tinyzip import quant

  def test_roundtrip_and_deadzone():
      coeffs = [73.68, -12.4, 0.21, 48.9, -3.1, 9.5, 0.0]
      delta = 16.0

      # Plain rounding (f = 0.5): no dead-zone.
      idx = quant.forward(coeffs, delta, f=0.5)
      rec = quant.inverse(idx, delta)
      assert idx == [5, -1, 0, 3, 0, 1, 0]          # 9.5 -> 1
      # every reconstruction is within half a step of its input
      assert all(abs(c - r) <= delta / 2 + 1e-9
                 for c, r in zip(coeffs, rec))

      # Dead-zone (f = 1/6): the marginal 9.5 now collapses to 0.
      idx_dz = quant.forward(coeffs, delta, f=1/6)
      assert idx_dz[5] == 0                          # 9.5 -> 0
      assert idx_dz.count(0) > idx.count(0)          # strictly more zeros

      # The dead-zone trades a little accuracy for more compressibility:
      rec_dz = quant.inverse(idx_dz, delta)
      assert quant.mse(coeffs, rec_dz) >= quant.mse(coeffs, rec)

  test_roundtrip_and_deadzone()
  print("quant.py: round-trip + dead-zone OK")
  ```

  Chapter 42 will feed `forward()` a per-frequency *quantization table* of step sizes:
  one $Delta$ for each of the $64$ DCT coefficients in an $8 times 8$ block, coarse for the
  high frequencies the eye ignores and fine for the low ones it scrutinises. That is exactly the
  "spend resolution where it matters" idea, applied to vision.
]

== Vector quantization: rounding whole tuples at once

Everything so far has rounded one number at a time. But what if we rounded a *whole group*
of numbers (a pair, a triple, a $64$-tuple) as a single unit? Instead of a tick mark on
a line, our reconstruction values become *points scattered in a multi-dimensional space*,
and each input vector snaps to its nearest such point. This is *vector quantization* (VQ),
and it is provably better than quantizing the same numbers one at a time. Even when the
numbers are *independent* (when knowing one tells you nothing about the next), vector
quantization still wins. That surprising fact is worth understanding, because it explains
why VQ sits inside everything from 1980s speech chips to today's AI image generators.

#definition("Vector quantizer")[
  A *vector quantizer* of dimension $n$ partitions $n$-dimensional space into regions and
  assigns each region a single representative vector. The collection of representatives is
  the *codebook* $cal(C) = {bold(c)_1, dots, bold(c)_K}$; each $bold(c)_j$ is a
  *codeword*. To encode an input vector $bold(x)$, find the *nearest* codeword (smallest
  Euclidean distance) and transmit only its *index* $j$. The decoder looks up
  $bold(c)_j$ in its copy of the codebook. The cost is $log_2 K$ bits per *vector*,
  i.e. $(log_2 K) \/ n$ bits per *sample*.
]

#gomaths("Euclidean distance, the ruler for vectors")[
  In Chapter 12 we learned a vector is just a list of numbers, an arrow in space. The
  *Euclidean distance* between two vectors $bold(x) = (x_1, dots, x_n)$ and
  $bold(c) = (c_1, dots, c_n)$ is the ordinary straight-line distance, got from
  Pythagoras in $n$ dimensions:
  $ d(bold(x), bold(c)) = sqrt((x_1 - c_1)^2 + (x_2 - c_2)^2 + dots + (x_n - c_n)^2). $
  To find the *nearest* codeword we compare these distances and pick the smallest; we
  can skip the square root, since whichever vector is closest in distance is also closest
  in *squared* distance, and squared distance is cheaper to compute.
  *Tiny example.* Input $bold(x) = (3, 4)$, codewords $bold(c)_1 = (0,0)$ and
  $bold(c)_2 = (5,5)$. Squared distances: $9 + 16 = 25$ to $bold(c)_1$ and
  $4 + 1 = 5$ to $bold(c)_2$. So $bold(x)$ snaps to $bold(c)_2$, and we send the single
  index "2".
]

#gomaths([$arg min$: "which one wins", not "what is the smallest"])[
  We will keep writing things like "$j^* = arg min_j thin d(bold(x), bold(c)_j)$", so let
  us pin down that symbol. Plain $min$ asks for the *smallest value* in a list; $arg min$
  ("argument of the minimum") asks for *which input achieves it*, the winning index, not
  the winning value. If the squared distances to four codewords are $(9, 4, 16, 4)$, then
  $min = 4$ (the smallest distance) but $arg min = 1$ (the *position* of a smallest entry,
  counting from $0$). When two entries tie for smallest (here positions $1$ and $3$ both
  hold $4$) $arg min$ is ambiguous, so codecs fix a tie-breaking rule (usually "take the
  lowest index") to keep encoder and decoder in lockstep. In a vector quantizer we never
  transmit the *distance*; we transmit the $arg min$, the index of the nearest codeword.
  Its twin $arg max$ (the position of the *largest* entry) shows up later when a model picks
  its most-likely symbol.
]

=== Why grouping wins (even when the numbers are independent)

There are three distinct reasons VQ beats scalar quantization, and it is worth separating
them because the third is the deep one.

*1. It exploits correlation (the obvious gain).* If neighbouring samples tend to move
together (and in real signals they overwhelmingly do), the data clusters along
diagonals in the joint space, leaving vast empty regions. A scalar quantizer wastes code
points on those empty regions (it tiles the whole rectangle uniformly); a vector quantizer
places its codewords only where data actually lives.

*2. It packs space more efficiently (the geometric gain).* A scalar quantizer carves space
into *rectangular* cells (the product of its 1-D bins). But rectangles (squares, cubes,
hyper-cubes) are not the most efficient way to tile space: they have wasteful corners. In
two dimensions, hexagons tile more efficiently than squares; in higher dimensions the gap
grows. A vector quantizer is free to use rounder, better-packed cells, lowering distortion
for the same number of code points. This is the *space-filling advantage*, and it exists
*even for independent uniform data* where there is no correlation to exploit at all.

*3. It captures the shape of the distribution (the gain that scales with dimension).*
Even for independent samples, the *joint* distribution of a high-dimensional vector
concentrates its probability in a thin "typical" shell (the law of large numbers,
foreshadowing the typical sets of Chapter 19). A vector quantizer can put all its codewords
on that shell and spend nothing on the improbable interior; a scalar quantizer cannot see
the shell at all. The bigger the blocks, the more this *shape gain* compounds, which is
exactly Shannon's promise from Chapter 21 that coding in long blocks approaches $R(D)$.

#keyidea[
  *Vector quantization is strictly more powerful than scalar.* For the same bits per
  sample it achieves equal or lower distortion, and the advantage grows with block size,
  approaching the rate--distortion bound $R(D)$ in the limit. The price is exponential: a
  codebook for $n$-dimensional vectors at $r$ bits/sample needs $2^(n r)$ entries, and
  every encode is a nearest-neighbour search through all of them.
]

#theorem("VQ dominates scalar quantization")[
  For any source and any target rate, the best $n$-dimensional vector quantizer achieves
  mean-squared distortion no larger than that of the best scalar quantizer at the same rate,
  with strict improvement whenever the source is not a product of identical uniform
  components quantized at their own optimum. As $n -> infinity$ the achievable
  rate--distortion performance approaches Shannon's $R(D)$.
]
#proof[
  *(Sketch.)* A scalar quantizer applied independently to each of the $n$ coordinates *is*
  a vector quantizer, the special case whose cells are axis-aligned rectangles. So the
  best vector quantizer, free to choose *any* cell shapes and codeword positions, can do at
  least as well as this rectangular special case: minimising over a larger set of options
  can never give a worse optimum. Strict improvement follows whenever non-rectangular cells
  (better space-filling) or non-grid codeword placement (matching correlation or
  distribution shape) lowers distortion, which holds for essentially every real source.
  The approach to $R(D)$ as $n -> infinity$ is Shannon's source-coding-with-fidelity
  theorem (Chapter 21). $square$ See Further reading for the full argument.
]

=== The LBG algorithm: learning a codebook from data

How do we *find* a good codebook? We can't write it down by hand for a $16$-dimensional
space. Instead we *learn* it from a pile of training vectors, and the algorithm is simply
Lloyd's iteration, lifted from the line into many dimensions. Yoseph Linde, Andrés Buzo,
and Robert M. Gray published it in January *1980*, and it is universally known by their
initials: *LBG*. (Outside compression, the very same procedure is *k-means clustering*.)

The two Lloyd--Max conditions carry over unchanged, now reading in vector language:

- *Nearest-neighbour:* each training vector is assigned to its closest codeword (the cells become *Voronoi regions*, the set of points nearer to one codeword than any other).
- *Centroid:* each codeword moves to the *mean* (centroid) of all training vectors assigned to it.

Alternate the two until the codebook stops moving. LBG adds one clever wrinkle for getting
a *good start*: the *splitting* trick. Begin with a single codeword (the mean of all the
data). Then *split* it into two by nudging it in opposite directions, run Lloyd's iteration
to settle the two, then split each of those into two (four total), settle, and so on,
doubling the codebook size each round until you reach the target $K$. Growing the codebook
gradually avoids many of the bad local optima that plague a random start.

#algo(
  name: "LBG algorithm (vector quantizer / codebook design)",
  year: "1980",
  authors: "Yoseph Linde, Andrés Buzo, Robert M. Gray",
  aim: "Learn a K-entry codebook for vector quantization that minimises mean-squared distortion over a training set.",
  complexity: "Each iteration costs O(N · K · n) for N training vectors of dimension n; encoding a new vector is O(K · n), a full nearest-neighbour scan.",
  strengths: "Exploits correlation, space-filling, and distribution shape together; approaches R(D) with larger blocks; the foundation of classical speech/image VQ.",
  weaknesses: "Local optimum only; codebook size 2^(n·r) explodes with dimension and rate; encode cost grows with K; codebook must be stored/transmitted.",
  superseded: "Structured VQ (tree/lattice/product) to tame cost; learned VQ-VAE codebooks; product quantization for billion-scale search.",
)[
  *Input:* training vectors, target codebook size $K$ (a power of $2$). *Output:* codebook
  $cal(C)$.
  + Start with one codeword = the mean of all training vectors.
  + *Split:* replace each codeword $bold(c)$ by two perturbed copies $bold(c) ± bold(epsilon)$, doubling the codebook size.
  + *Lloyd loop:* repeat until distortion stops dropping: (a) *assign* each training vector to its nearest codeword; (b) *update* each codeword to the centroid of its assigned vectors.
  + If the codebook size is still below $K$, go to step 2; otherwise stop.
]

#example[
  *One LBG split in 2-D.* Training vectors: two clusters, one around $(1,1)$ and one
  around $(9,9)$. Start with a single codeword at the overall mean $(5,5)$. *Split* into
  $(5 - 0.1, 5 - 0.1)$ and $(5 + 0.1, 5 + 0.1)$. *Assign:* the lower-left cluster snaps to
  the first, the upper-right cluster to the second. *Update (centroid):* the two codewords
  jump to $(1,1)$ and $(9,9)$, the true cluster means. Two indices now describe the data
  perfectly, at $1$ bit per *vector* (= $0.5$ bit per *sample* in 2-D), where scalar
  quantizing each coordinate to even $1$ bit would have cost $2$ bits per vector and placed
  levels blind to where the clusters actually sit.
]

#gopython("Nearest-codeword search and a centroid update")[
  The whole engine of VQ is "find the closest codeword". With lists of numbers as vectors,
  it is a short loop. `range(len(codebook))` enumerates the candidate indices $0, 1, 2, dots$,
  and `min(..., key=...)` (Chapter 16) picks the index whose squared distance is smallest,
  Python's way of writing the $arg min$ we defined above.
  ```python
  def sq_dist(a: list[float], b: list[float]) -> float:
      "Squared Euclidean distance between two equal-length vectors."
      return sum((x - y) ** 2 for x, y in zip(a, b))

  def encode(x: list[float], codebook: list[list[float]]) -> int:
      "Index of the nearest codeword to x."
      return min(range(len(codebook)), key=lambda j: sq_dist(x, codebook[j]))

  def centroid(vectors: list[list[float]]) -> list[float]:
      "Component-wise mean of a list of vectors (the centroid update)."
      n = len(vectors[0])
      return [sum(v[k] for v in vectors) / len(vectors) for k in range(n)]

  book = [[1.0, 1.0], [9.0, 9.0]]
  print(encode([8.0, 7.5], book))      # -> 1  (nearest is (9,9))
  print(centroid([[0,0],[2,2],[1,4]])) # -> [1.0, 2.0]
  ```
  The `lambda j: ...` is an *anonymous function* (Chapter 16), a throwaway rule used once,
  here as the comparison key. This is the entire inner loop of both LBG codebook training
  and VQ encoding.
]

Once the codebook exists, the *run-time* quantizer itself is the simplest algorithm in
this chapter: encode is a nearest-neighbour search, decode is a table lookup.

#algo(
  name: "Vector quantizer (encode / decode at run time)",
  year: "1980 (formalised with LBG)",
  authors: "Linde, Buzo, Gray (codebook); the lookup pattern is folklore",
  aim: "Replace each input vector by the index of its nearest codebook entry, and reconstruct by lookup.",
  complexity: "Encode: O(K · n) per vector (full scan of K codewords of dimension n). Decode: O(n), one table lookup. Rate: (log₂ K)/n bits per sample.",
  strengths: "Trivial, ultra-cheap decoder; reconstruction quality limited only by the codebook; the same loop powers PQ search and VQ-VAE token lookup.",
  weaknesses: "Encode scan is linear in codebook size; codebook must be shared with the decoder; nearest-neighbour ties need a fixed rule.",
  superseded: "Structured search (tree/lattice/product VQ) to make encode sub-linear in K.",
)[
  *Encode* $bold(x)$: compute the squared distance to every codeword $bold(c)_j$, output
  the index $j^* = arg min_j d(bold(x), bold(c)_j)^2$. *Decode* index $j$: output
  $bold(c)_j$. Both sides hold an identical copy of the codebook $cal(C)$; only the small
  integer index $j$ travels between them.
]

== Taming the cost: structured vector quantization

Plain ("unstructured") VQ has a brutal scaling problem baked into the key idea above: a
codebook for $n$-dimensional vectors at $r$ bits per sample has $K = 2^(n r)$ entries, and
encoding each vector means computing the distance to *every* one of them. At a modest $r =
2$ bits/sample on $16$-dimensional vectors that is $2^32 approx 4$ billion codewords, far
too many to store, let alone search. The history of VQ is largely the history of *imposing
structure* on the codebook so that storage and search stay manageable while keeping most of
the gain.

- *Tree-structured VQ* arranges codewords in a binary tree. Encoding walks down the tree, making $log_2 K$ cheap comparisons instead of $K$; search becomes logarithmic. The price is a small loss of optimality (the greedy path may miss the true nearest codeword).
- *Lattice VQ* uses a regular geometric lattice (like the efficient hexagonal or $E_8$ packings) as the codebook. There is *nothing to store*: the codewords are defined by a formula, and encoding is a fast rounding operation. You give up adapting to the data's exact shape in exchange for near-zero cost.
- *Product VQ* splits the big vector into several short sub-vectors and quantizes each with its own small codebook. A handful of small codebooks multiply together to *represent* an enormous effective codebook without ever storing it. This is the idea that, decades later, scaled to billions of vectors.
- *Trellis-coded / shape--gain VQ* and other hybrids borrow structure from channel coding or split a vector into its *magnitude* (gain) and *direction* (shape) and quantize each separately. These dominated 1980s--90s speech coders such as CELP (Chapter 50), where a small codebook of excitation *shapes* plus a gain index reconstructs intelligible speech at a few thousand bits per second.

#aside[
  The encoder/decoder asymmetry of VQ is a feature, not a bug. *Decoding* is trivial, a
  table lookup, so a cheap device (a 1990s mobile phone, a tiny embedded chip) can
  reconstruct beautifully even if building the codebook took a supercomputer. This same
  asymmetry (heavy encoder, light decoder) recurs in every video codec (Chapter 51) and
  in the neural codecs of Volume IV.
]

== The living lineage: from VQ to product quantization to VQ-VAE

Vector quantization might look like a museum piece from the speech-chip era, but the idea
is more alive in 2026 than ever; it simply moved into new costumes.

*Product quantization (PQ), 2011.* Hervé Jégou, Matthijs Douze, and Cordelia Schmid took
product VQ and aimed it at a modern problem: searching *billions* of high-dimensional
vectors (image descriptors, and now the embeddings that power semantic search and
retrieval-augmented LLMs). Split a $128$-dimensional vector into, say, $8$ chunks of $16$
dimensions; quantize each chunk with its own $256$-entry codebook; store the vector as just
$8$ bytes (one index per chunk). Distances can be computed *directly on the compressed
codes* via small lookup tables, so you can scan a billion vectors in milliseconds. PQ and
its descendants are the backbone of the FAISS-style vector databases now ubiquitous in AI
search.

*VQ-VAE, 2017.* Aäron van den Oord and colleagues at DeepMind fused vector quantization
with the neural autoencoder (which we will build properly in Chapter 56). A neural network
*learns* the transform, replacing the fixed DCT, mapping an image into a grid of latent
vectors; each latent vector is then *vector-quantized* against a learned codebook, turning
the image into a grid of *discrete tokens*; a decoder network reconstructs from those
tokens. The bottleneck is exactly the codebook lookup we just built, now trained jointly
with the network by gradient descent. The same forget-then-name structure, the same
nearest-codeword search; only the transform and the codebook are *learned* rather than
designed.

This discrete-token substrate turned out to be the bridge between *compression* and
*generation*. Because a VQ-VAE turns an image (or a second of audio) into a short sequence
of codebook indices, those indices can be modelled by the same autoregressive machinery as
text, which is precisely how modern image and audio generators, and the neural audio
codecs of Chapter 60 (SoundStream, EnCodec, with their *residual* VQ stacking several
codebooks to refine the quantization), came to be. Lloyd's 1957 "round to the nearest
representative" became, seventy years on, the tokenizer of generative AI.

#history[
  Robert M. Gray (the "G" in LBG) spent his career at Stanford carrying vector
  quantization from speech chips to the foundations of information theory, and lived to see
  his 1980 algorithm reborn as the codebook inside billion-parameter generative models.
  The through-line from G.711 companding (1972) to LBG (1980) to product quantization
  (2011) to VQ-VAE (2017) to the neural audio tokenizers of the 2020s is one of the
  cleanest examples in this book of a single idea, *replace a value by the nearest entry
  in a small menu*, being rediscovered at ever-larger scale.
]

== Where quantization sits in the pipeline

Let us pin down the trade-offs, because choosing a quantizer is choosing a point on
several axes at once.

#table(columns: (auto, 1fr, 1fr), inset: 7pt, align: (left, left, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Choice*], [*Buys you*], [*Costs you*]),
  [Uniform scalar], [Trivial to build; pairs perfectly with entropy coding; no codebook to store], [Suboptimal for peaky data; leaves ~0.25 bit/sample on the table],
  [Dead-zone scalar], [Long zero-runs → big entropy-coding win; one cheap offset knob], [A little extra distortion on marginal coefficients],
  [Non-uniform (Lloyd--Max)], [Minimum MSE for the given level count], [Needs source statistics; only locally optimal; irregular bins],
  [Vector (LBG)], [Approaches $R(D)$; exploits correlation, packing, and shape], [Codebook size $2^(n r)$ explodes; nearest-neighbour search per vector],
  [Structured VQ], [Most of the VQ gain at log-time search / tiny storage], [Some loss of optimality; more design complexity],
)

#checkpoint[A uniform scalar quantizer uses step $Delta = 8$ on a busy signal. Roughly
what is its quantization-noise power, and by how many decibels would halving the step to
$Delta = 4$ improve the signal-to-noise ratio?][
  Noise power $approx Delta^2\/12 = 64\/12 approx 5.33$. Halving the step quarters the
  noise (to $approx 1.33$), an improvement of $10 log_10 4 approx 6.02$ dB, the
  "6 dB per bit" rule, since halving $Delta$ is exactly one extra bit of precision.
]

#scoreboard(caption: "lossy stage: the quantizer is the knob (illustrative, on the shared 8x8 image block)",
  [DEFLATE (lossless, Ch 30)], [reference], [-], [our lossless baseline carries forward],
  [DCT only (Ch 38)], [no saving], [1.00×], [transform *rearranges* energy; saves nothing alone],
  [DCT + coarse uniform quant], [small], [≈3–5×], [rounding finally discards bits; many coeffs → small ints],
  [DCT + dead-zone quant], [smaller], [≈5–8×], [zero-runs feed run-length + Huffman (Ch 42)],
)

#takeaways((
  [A quantizer is *forget-then-name*: a many-to-one forward map (the only lossy step) plus a chosen stand-in per bin. It is the single irreversible stage in nearly every lossy codec.],
  [The *uniform scalar quantizer* rounds to the nearest multiple of a step $Delta$. Its noise power is $D = Delta^2\/12$, giving the *6 dB per bit* rule, the operational face of Shannon's $R(D)$.],
  [*Non-uniform* quantizers spend fine resolution where probability is high. The optimal one obeys the two *Lloyd--Max conditions* (nearest-neighbour boundaries + centroid values); *Lloyd's iteration* alternates them to a local optimum.],
  [A *dead-zone* widens the bin around zero so small coefficients become exact zeros, cheaply extending the zero-runs that entropy coders devour; every real image/video codec does this.],
  [*Dithering* trades structured error (banding) for benign random noise, improving *perceived* quality even though total noise power rises slightly.],
  [*Vector quantization* rounds whole tuples to the nearest codeword, beating scalar quantization by exploiting correlation, better space-filling, and distribution shape, approaching $R(D)$ as blocks grow. The *LBG algorithm* (1980) learns the codebook; structured VQ tames its exponential cost.],
  [The VQ idea is thoroughly modern: *product quantization* powers billion-scale vector search, and *VQ-VAE* codebooks are the discrete-token substrate of today's neural codecs and generative models.],
))

== Exercises

#exercise("39.1", 1)[
  A uniform scalar quantizer has step $Delta = 20$. Quantize the values $34$, $-9$, $0.5$,
  $51$, and $-25$ to their integer indices (use ordinary rounding, offset $f = 0.5$), then
  give each reconstruction $hat(x) = i Delta$ and each error $x - hat(x)$. Which input
  suffered the largest absolute error, and is it within the guaranteed bound $Delta\/2$?
]
#solution("39.1")[
  Indices $i = "round"(x\/20)$: $34\/20 = 1.7 -> 2$ ($hat(x) = 40$, error $-6$);
  $-9\/20 = -0.45 -> 0$ ($hat(x) = 0$, error $-9$); $0.5\/20 = 0.025 -> 0$
  ($hat(x) = 0$, error $0.5$); $51\/20 = 2.55 -> 3$ ($hat(x) = 60$, error $-9$);
  $-25\/20 = -1.25 -> -1$ ($hat(x) = -20$, error $-5$). The largest absolute error is
  $9$ (tied, for both $-9$ and $51$). The guaranteed bound is $Delta\/2 = 10$, and indeed
  $9 < 10$, so every error stays within it.
]

#exercise("39.2", 1)[
  Explain in one or two sentences why the inverse map $Q^(-1)$ of a quantizer adds no
  information loss even though the overall quantizer is lossy. Where, precisely, does the
  loss happen?
]
#solution("39.2")[
  All loss happens in the forward map $Q$, which is many-to-one: once an input is labelled
  with a bin index, the exact position within the bin is gone forever. The inverse map just
  substitutes the agreed representative for that index, a deterministic lookup that
  destroys nothing further. The loss is the collapse of a whole bin's worth of inputs onto
  one index.
]

#exercise("39.3", 2)[
  Derive the noise power of a uniform quantizer from scratch by integrating $e^2$ over a
  bin, assuming the error is uniform on $[-Delta\/2, Delta\/2]$. Then compute the noise
  power for $Delta = 4$, $Delta = 8$, and $Delta = 16$, and confirm that each doubling of
  $Delta$ multiplies the noise by $4$ (equivalently, $+6$ dB).
]
#solution("39.3")[
  With flat density $1\/Delta$, $D = integral_(-Delta\/2)^(Delta\/2) e^2 (1\/Delta) thin d e = (1\/Delta)[e^3\/3]_(-Delta\/2)^(Delta\/2) = (1\/Delta)(2 (Delta\/2)^3\/3) =
  (1\/Delta)(Delta^3\/12) = Delta^2\/12$. Values: $4^2\/12 = 1.333$; $8^2\/12 = 5.333$;
  $16^2\/12 = 21.33$. Each step is $4times$ the previous, i.e. $10 log_10 4 approx 6.02$ dB
  louder noise per doubling of $Delta$.
]

#exercise("39.4", 2)[
  Run Lloyd's algorithm by hand on the data $0, 1, 2, 8, 9, 10$ for $L = 2$ levels, starting
  from reconstruction values $hat(x)_1 = 3$, $hat(x)_2 = 7$. Show the assign and update
  steps until it converges, and give the final levels and the mean-squared error.
]
#solution("39.4")[
  *Round 1.* Boundary $(3+7)\/2 = 5$. Bin 1: $0,1,2$; bin 2: $8,9,10$. Centroids:
  $hat(x)_1 = 1$, $hat(x)_2 = 9$. *Round 2.* Boundary $(1+9)\/2 = 5$; same split; same
  centroids; converged. Final levels $1$ and $9$. Errors are $-1,0,1$ in each bin, so
  $D = (1+0+1+1+0+1)\/6 = 4\/6 approx 0.667$.
]

#exercise("39.5", 2)[
  A dead-zone quantizer uses step $Delta = 10$ and rounding offset $f = 1\/4$. Using
  $i = "sign"(x) floor(abs(x)\/Delta + f)$, find the indices for $x = 2$, $7$, $7.6$, $12$,
  and $-8$. At what positive value of $x$ does the first non-zero index begin?
]
#solution("39.5")[
  $2$: $floor(0.2 + 0.25) = floor(0.45) = 0$. $7$: $floor(0.7+0.25) = floor(0.95) = 0$.
  $7.6$: $floor(0.76+0.25) = floor(1.01) = 1$. $12$: $floor(1.2+0.25) = floor(1.45) = 1$.
  $-8$: $-floor(0.8 + 0.25) = -floor(1.05) = -1$. The first non-zero index begins where
  $abs(x)\/Delta + f = 1$, i.e. $abs(x) = (1 - f)Delta = (0.75)(10) = 7.5$. So values with
  $abs(x) >= 7.5$ leave the dead-zone.
]

#exercise("39.6", 2)[
  Give two distinct reasons a 2-dimensional vector quantizer can beat quantizing each
  coordinate separately, *even if the two coordinates are statistically independent and
  uniform*. (Hint: think about cell shapes, not correlation.)
]
#solution("39.6")[
  (1) *Space-filling:* a scalar quantizer carves the plane into squares, but for a fixed
  number of cells, hexagonal cells have lower average squared distance to their centres
  than squares; VQ can use rounder, better-packed cells. (2) *Codeword placement:* VQ may
  position its representatives anywhere, including off the rectangular grid that the product
  of two scalar quantizers is forced onto, letting it tile space more efficiently. Both
  gains exist with zero correlation; correlation would only add a third, separate gain.
]

#exercise("39.7", 3)[
  Implement, in the style of this chapter's tinyzip step, an LBG codebook trainer:
  `train(vectors, K)` that starts from the data centroid, repeatedly *splits* every
  codeword by $±epsilon$ and runs a few Lloyd iterations (assign by nearest codeword,
  update to cluster centroids) until the codebook reaches $K$ entries. Test it on two
  obvious clusters and confirm the two codewords land near the cluster means. State why
  your result might differ on a different random $epsilon$.
]
#solution("39.7")[
  A correct solution loops: `book = [centroid(vectors)]`; while `len(book) < K`, replace
  each `c` with `[c+eps, c-eps]`, then iterate (assign each vector to `encode(v, book)`,
  recompute each codeword as `centroid` of its assigned vectors) until distortion stabilises.
  On clusters near $(1,1)$ and $(9,9)$ the two codewords converge to those means. Results
  can differ because LBG finds only a *local* optimum: a different perturbation $epsilon$ (or
  an unlucky split) can seat both codewords in one cluster on some data sets, the same
  local-optimum caveat as scalar Lloyd and as k-means. Reusing `encode`, `centroid`, and
  `sq_dist` from the chapter's `gopython` box gives a compact, correct trainer.
]

#exercise("39.8", 3)[
  Argue (no heavy math) why vector quantization in *large* blocks can approach Shannon's
  rate--distortion bound $R(D)$ from Chapter 21, while scalar quantization always leaves a
  fixed gap. Then explain what practical obstacle stops us from simply using huge blocks,
  and name two structured-VQ tricks that sidestep it.
]
#solution("39.8")[
  As block length $n$ grows, the joint distribution of a vector concentrates on a thin
  "typical" shell (law of large numbers / AEP, Chapter 19); a large-block VQ can place
  codewords only on that shell and match the source's true shape, while a scalar quantizer
  sees only one coordinate at a time and cannot exploit the joint structure, so it keeps a
  fixed per-sample gap (≈$0.25$ bit for smooth sources). The obstacle is that codebook size
  $2^(n r)$ and the per-vector nearest-neighbour search both grow *exponentially* in $n$.
  Structured tricks that dodge this include *tree-structured VQ* (log-time search),
  *lattice VQ* (formula-defined codebook, no storage), and *product quantization* (split
  into sub-vectors with small codebooks) - any two suffice.
]

== Further reading

- Stuart P. Lloyd, "Least Squares Quantization in PCM," #link("https://doi.org/10.1109/TIT.1982.1056489")[_IEEE Transactions on Information Theory_, 28(2), 1982]. The famous 1957 Bell Labs memo, in print at last, with the two optimality conditions.
- Joel Max, "Quantizing for Minimum Distortion," #link("https://doi.org/10.1109/TIT.1960.1057548")[_IRE Transactions on Information Theory_, 6(1), 1960]. The independent derivation.
- Yoseph Linde, Andrés Buzo, Robert M. Gray, "An Algorithm for Vector Quantizer Design," #link("https://doi.org/10.1109/TCOM.1980.1094577")[_IEEE Transactions on Communications_, COM-28(1), 1980]. The LBG splitting algorithm.
- Robert M. Gray, "Vector Quantization," #link("https://doi.org/10.1109/MASSP.1984.1162229")[_IEEE ASSP Magazine_, 1(2), 1984]. The classic tutorial; Gersho & Gray, _Vector Quantization and Signal Compression_ (1992), remains the definitive book.
- Hervé Jégou, Matthijs Douze, Cordelia Schmid, "Product Quantization for Nearest Neighbor Search," #link("https://doi.org/10.1109/TPAMI.2010.57")[_IEEE TPAMI_, 33(1), 2011]. VQ at billion scale.
- Aäron van den Oord, Oriol Vinyals, Koray Kavukcuoglu, "Neural Discrete Representation Learning (VQ-VAE)," #link("https://arxiv.org/abs/1711.00937")[arXiv:1711.00937, 2017]. Learned codebooks inside a neural autoencoder.

#bridge[
  We can now *transform* a signal (Chapter 38) and *quantize* its coefficients (this
  chapter), turning a flood of real numbers into a short list of small integers and zeros.
  But we have been assuming the transform sees the raw signal cold. Often we can do better
  by *predicting* each sample from its neighbours and quantizing only the small *surprise*
  left over, the prediction error. Chapter 40 builds that idea: differential and
  predictive coding (DPCM, linear prediction, Levinson--Durbin), the engine behind lossless
  audio (FLAC) and the predictors inside JPEG-LS. Then Chapter 41 shows how real encoders
  decide, coefficient by coefficient, exactly how coarsely to quantize (*rate--distortion
  optimization* in practice) before Chapter 42 assembles transform, quantizer, and entropy
  coder into a working JPEG.
]
