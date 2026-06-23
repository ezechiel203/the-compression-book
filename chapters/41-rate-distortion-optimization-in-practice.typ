#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Rate–Distortion Optimization in Practice

#epigraph[
  The art of compression is the art of spending bits where they count.
][Anonymous video-codec engineer, circa 2003]

Picture an encoder that must squeeze a two-hour film into exactly 4 gigabytes for a Blu-ray disc.
Every scene is different — a dialogue in a dimly lit café barely moves; a car chase strobes with
fast-flying blur. If the encoder hands every frame the same number of bits, the café looks
gorgeous while the chase turns to mush, or vice versa. What the encoder needs is a *budget
officer*: a policy that decides, second by second, shot by shot, coefficient by coefficient, where
each bit buys the most quality. That budget officer is *rate–distortion optimization in practice*
— the topic of this chapter.

In Chapter 21 we learned Shannon's R(D) curve: a theorem that tells us the minimum bits needed
to hit a target distortion, but gives no algorithm. In Chapter 39 we saw how quantization is the
knob that trades bits for error. In Chapter 38 we met the transform that concentrates energy into
a few large coefficients. Now we weld all three ideas into the decision engine every modern encoder
runs thousands of times per second, from JPEG to AV1, from H.264 to the neural codecs of Chapter 57.

#recap[
  Chapter 21 established the rate–distortion function R(D) as a theoretical floor — the minimum
  bits for a given average distortion. Chapter 38 showed the transform (DCT, wavelet, MDCT) that
  decorrelates source data so coefficients can be quantized independently. Chapter 39 built the
  scalar quantizer and showed how the step size q trades distortion for fewer entropy-codeable
  levels. Chapter 40 introduced differential coding (DPCM) as a way to exploit prediction and
  reduce the range of values before quantization. Here we connect the theory to the practice:
  how encoders actually *choose* quantization levels, allocate bits across frames, and navigate
  the speed/quality/bitrate triangle.
]

#objectives((
  "Understand the Lagrangian RDO cost function J = D + λR and why λ is the magic knob.",
  "Read and interpret an operational R–D curve and a convex hull.",
  "Distinguish CBR, VBR, ABR, and CRF rate-control modes and know when each is used.",
  "Explain two-pass encoding and how a first pass improves second-pass bit allocation.",
  "Describe perceptual extensions: VMAF-driven RDO, adaptive quantization, and content-aware encoding.",
  "Understand Netflix per-title encoding as an application of operational R–D optimization.",
))

== The Core Problem: Bits Are Scarce, Quality Is Desired

An image or video encoder faces a constrained optimization problem every time it codes a block of
pixels. It has many decisions to make: which transform to use, how coarsely to quantize each
frequency coefficient, which prediction mode to pick, how long a motion vector to signal. Each
choice produces a different number of bits (a *rate* R) and a different reconstruction error
(a *distortion* D). The encoder wants low R and low D simultaneously — but they pull in opposite
directions. Spending fewer bits means coarser quantization, which means more distortion.

The elegant solution, used in every modern codec, is to combine the two goals into a single number
to minimize. That number is the *Lagrangian cost*:

$ J = D + lambda R $

Here D is the distortion of this choice (usually mean squared error, or MSE), R is the number of
bits it costs, and λ (the Greek letter "lambda") is a *weighting factor* that converts bits into
distortion units. The encoder picks whichever coding decision gives the smallest J.

#mathrecall[
  *Distortion and MSE* (Chapter 21). A _distortion measure_ $d(x, hat(x))$ is a rule that scores
  how bad it is to reconstruct a true value $x$ as $hat(x)$, with $d(x,x)=0$. The workhorse is
  _squared error_ $(x - hat(x))^2$; its average over a block or frame is the _mean squared error_
  (MSE). We proved in Chapter 21 that the choice of $d$ "is the whole game" — MSE is mathematically
  convenient but only a crude model of what the eye sees, which is exactly why this chapter later
  reaches for perceptual measures.
]

#gomaths("Lagrangian optimization")[
  A *Lagrangian* (named after 18th-century mathematician Joseph-Louis Lagrange) is a way to turn
  a constrained optimization problem — "minimize distortion, subject to rate ≤ budget" — into an
  unconstrained one: "minimize D + λR with no constraint." We met the same multiplier λ in
  Chapter 21, where it traced out the theoretical R(D) curve; here we put it to work *inside* a
  real encoder, one mode decision at a time. The trick is that for the right choice
  of λ, the unconstrained solution hits exactly the constraint. Visually: if you draw the R–D
  curve, each point on it corresponds to a particular λ. Large λ means bits are expensive, so the
  encoder is stingy (high D, low R). Small λ means bits are cheap, so the encoder spends freely
  (low D, high R). The Lagrangian reduces all the encoder's decisions to a single scalar comparison.

  *Tiny example.* Suppose you can code a block in two ways:
  - Mode A: costs 40 bits, distortion 100.
  - Mode B: costs 60 bits, distortion 50.

  With λ = 2: $J_A = 100 + 2 times 40 = 180$; $J_B = 50 + 2 times 60 = 170$. Choose B.
  With λ = 5: $J_A = 100 + 5 times 40 = 300$; $J_B = 50 + 5 times 60 = 350$. Choose A.
  A higher λ "taxes" the extra 20 bits more heavily, so the cheaper mode wins.
]

This decision rule — pick the coding mode with smallest J = D + λR — is called
*Lagrangian rate–distortion optimization* (Lagrangian RDO). It was first formalized for video
coding by Gary Sullivan and Thomas Wiegand in 1998 and became mandatory machinery in H.264/AVC
(2003) and every standard since. It is not one algorithm but a *framework* that sits inside every
mode decision the encoder makes: choosing between intra/inter prediction, picking a block size,
selecting motion vectors, deciding quantization step.

== The Operational R–D Curve

Shannon's R(D) curve is theoretical and inaccessible. What an encoder can actually measure is the
*operational R–D curve*: a set of real (R, D) points obtained by encoding the same content at
several different quality levels (different quantization steps) and plotting the results.

#fig([An operational R–D curve for a short video clip. Each dot is one encoding run at a different
quantization parameter (QP). The dashed line is the theoretical Shannon bound R(D), which
the practical encoder can approach but never cross.],
cetz.canvas({
  import cetz.draw: *

  // axes
  line((0,0), (7,0), mark: (end: ">"))
  line((0,0), (0,5), mark: (end: ">"))
  content((3.5,-0.45))[Bit-rate (R) →]
  content((-0.5,2.5), angle: 90deg)[Quality (PSNR) →]

  // theoretical R-D (dashed)
  bezier((0.8,4.7),(2.5,3.5),(5.5,1.3),(6.8,0.9),
         stroke: (paint: gray, dash: "dashed"))
  content((6.5,1.1), anchor: "west")[#text(size:8pt)[Shannon\nbound]]

  // operational points
  let pts = ((1.2,3.1),(1.9,3.7),(2.8,4.1),(3.9,4.4),(5.2,4.6),(6.2,4.7))
  for p in pts {
    circle(p, radius: 0.12, fill: rgb("#0b5394"), stroke: none)
  }
  // connect with line
  line((1.2,3.1),(1.9,3.7),(2.8,4.1),(3.9,4.4),(5.2,4.6),(6.2,4.7),
       stroke: (paint: rgb("#0b5394"), thickness: 1.5pt))

  // convex hull highlight (same here since it's all on one curve)
  content((3.9,4.55), anchor: "south")[#text(size:7.5pt, fill: rgb("#0b5394"))[operational\npoints]]
  content((1.0,3.05), anchor: "east")[#text(size:7.5pt)[Low\nQP]]
  content((6.35,4.65), anchor: "west")[#text(size:7.5pt)[High\nQP]]
}))

The shape of the curve reveals a lot. At low bitrates the curve is steep: one extra bit buys a
big quality jump. At high bitrates the curve flattens: you pay a lot for small improvements.
This is why "good enough" is usually far more efficient than "perfect" — the last few dB of
quality cost exponentially more bits.

#keyidea[
  The operational R–D curve is the encoder's *menu of choices*. Rate control, bit allocation,
  and quality targeting are all just different policies for choosing which point on that curve to
  use, for each piece of content, at each moment in time.
]

=== The Convex Hull and Efficient Operating Points

Not every point on the operational curve is worth using. If you can achieve the same distortion
with fewer bits by mixing two other operating points, then that point is *dominated* and you
should skip it. The set of non-dominated points traces the *convex hull* of the R–D cloud.

To make "dominated" concrete, imagine you tried five encodes and measured these (bitrate, VMAF)
points: (500, 70), (900, 78), (1100, 77), (1600, 86), (3000, 92). The fourth-listed point
(900, 78) beats (1100, 77) outright — it uses *fewer* bits for *more* quality — so (1100, 77) is
dominated and we discard it. The survivors, sorted, are (500, 70), (900, 78), (1600, 86),
(3000, 92): each step up the ladder costs more bits *and* buys more quality, and no other encode
beats them. Those four are the *convex hull*, the only operating points a sane bitrate ladder
would ever offer.

For a single image this is academic — you just pick the operating point that fits your target.
But for adaptive bitrate streaming (ABR), where a service offers a *ladder* of quality levels,
the ladder rungs should lie on the convex hull. Points inside the hull mean you could have gotten
the same quality more cheaply. Netflix's "per-title encoding" (discussed in detail below) is
precisely the science of finding that hull for each title individually.

== Lambda and Quantization: The Link Between Theory and Knobs

In most codecs, the programmer does not set λ directly. They set a *quantization parameter* (QP)
or a *constant rate factor* (CRF). The encoder derives λ from these internally.

In H.264 and H.265, the canonical formula is:

$ lambda = 0.85 times 2^((Q P - 12) / 3) $

where QP ranges from 0 (lossless-ish) to 51 (very coarse). Because QP steps are in a
*doubling* exponential scale — each step of 6 in QP doubles the quantization step size, halving
visual quality — the formula correctly ensures that a doubling of quantization cost corresponds
to a doubling of λ. For AV1 the encoder uses a different QP table but the Lagrangian idea is
identical.

#gomaths("Exponential scales in QP")[
  In H.264, the quantization step size $Q_"step"$ follows:

  $ Q_"step"(Q P) = 2^((Q P - 4) / 6) $

  This means QP = 0 gives $Q_"step" approx 0.625$ and QP = 51 gives $Q_"step" approx 224$ — a
  range of about 360× from finest to coarsest. The logarithmic scale is intentional: the human
  visual system perceives quality logarithmically (like loudness in decibels), so uniform steps
  in QP correspond to roughly uniform perceptual steps.

  Meanwhile PSNR (Peak Signal-to-Noise Ratio, Chapter 75) is itself a logarithmic measure:

  $ "PSNR" = 10 log_10 (255^2 / "MSE") $

  so a linear change in QP maps approximately to a linear change in PSNR — a useful property
  for rate control.
]

The takeaway: adjusting one parameter (QP, CRF) slides the encoder along the R–D curve
smoothly, because both rate and distortion respond exponentially to the quantization step, and
the ratio — the λ — stays roughly constant.

== Bit Allocation: Spending the Budget Where It Matters

A film is not a single image — it is 24, 30, or 60 frames per second, and not every frame is
equally hard to compress or equally important. The encoder has a global bit budget (say, 4 Mbps)
and must decide how many bits each frame gets. This is *bit allocation*.

The naive approach — give every frame the same number of bits — fails badly. A still scene wastes
bits; a fast-moving action scene gets too few and turns blocky. A good bit allocation strategy
directs the budget toward frames that need it.

=== Scene Complexity and Content Analysis

The simplest complexity measure is *inter-frame residual energy*: after motion compensation
(subtracting what the codec predicted from the previous frame), how much energy is left? High
residual energy means the content changed in ways prediction could not capture — this frame needs
more bits. Low residual means most information came for free from the previous frame.

Encoders compute a per-frame "complexity" estimate — sometimes as simple as the variance of the
pixel block, sometimes as the mean absolute difference (MAD) after motion compensation — and
scale each frame's QP up or down relative to this estimate. Harder frames get a lower QP (more
bits); easier frames get a higher QP (fewer bits).

#history[
  The idea of adaptive bit allocation across frames was formalized by Netravali and Haskell in
  their 1988 textbook *Digital Pictures* and refined in the ISO/IEC MPEG standards from
  1991 onward. By H.263 (1995) every serious encoder used some form of complexity-based bit
  allocation. H.264 reference software (JM) introduced a model-based R–D bit allocation where
  each frame's rate was predicted from a power-law fit to measured R–D data.
]

=== Frame-Type Weighting

Video codecs distinguish several frame types (see Chapter 51):
- *I-frames* (intra): coded without reference to other frames. They are the most expensive and
  serve as random-access points. Typically 5–20× the size of a P-frame.
- *P-frames* (predicted): coded using a single past reference. Medium cost.
- *B-frames* (bidirectional): coded using past and future references simultaneously. Usually the
  cheapest, often 0.5–0.8× the size of a P-frame.

A well-designed bit allocator gives each frame type a different *weight* in the budget. Spending
extra bits on I-frames pays dividends because P and B frames reference them — errors in an
I-frame propagate and corrupt many subsequent frames.

#fig([I/P/B frame structure in a GOP (Group of Pictures) and example bit allocation. I-frames
receive the largest individual budgets; B-frames the smallest.],
cetz.canvas({
  import cetz.draw: *

  let frames = ("I","B","B","P","B","B","P","B","B","I")
  let bits   = (100, 30, 30, 55, 28, 28, 50, 25, 25, 95)
  let colors = (
    rgb("#0b5394"), // I  blue
    rgb("#9a2617"), // B  red
    rgb("#9a2617"),
    rgb("#0b6e4f"), // P  green
    rgb("#9a2617"),
    rgb("#9a2617"),
    rgb("#0b6e4f"),
    rgb("#9a2617"),
    rgb("#9a2617"),
    rgb("#0b5394"),
  )

  let n = frames.len()
  let w = 0.58
  let gap = 0.12
  let max-b = 100.0
  let scale = 3.5

  for i in range(n) {
    let x = i * (w + gap)
    let h = bits.at(i) / max-b * scale
    rect((x, 0), (x + w, h), fill: colors.at(i).lighten(60%),
         stroke: colors.at(i))
    content((x + w/2, -0.25))[#text(size:8pt, weight:"bold", fill:colors.at(i))[#frames.at(i)]]
    content((x + w/2, h + 0.15))[#text(size:7pt)[#bits.at(i)]]
  }

  // legend
  content((0, -0.7), anchor: "west")[#text(size:7.5pt)[#box(fill:rgb("#0b5394").lighten(60%), stroke:rgb("#0b5394"), inset:3pt)[] I-frame]]
  content((2.2, -0.7), anchor: "west")[#text(size:7.5pt)[#box(fill:rgb("#0b6e4f").lighten(60%), stroke:rgb("#0b6e4f"), inset:3pt)[] P-frame]]
  content((4.4, -0.7), anchor: "west")[#text(size:7.5pt)[#box(fill:rgb("#9a2617").lighten(60%), stroke:rgb("#9a2617"), inset:3pt)[] B-frame]]

  line((0,-0.05),(n*(w+gap)-gap,-0.05))
  content(((n*(w+gap)-gap)/2, -1.1))[#text(size:8pt)[Relative bit budget per frame (illustrative)]]
}))

== Rate Control: The Three Regimes

*Rate control* is the high-level policy that governs bit allocation over time to meet constraints
on the output stream. Three major regimes dominate practical deployments.

=== Constant Bitrate (CBR)

In CBR mode, the encoder must produce a stream where the average bitrate over some window (often
1 second) stays within a fixed target — say, 5 Mbps. The classic CBR mechanism is the *video
buffering verifier* (VBV), a hypothetical decoder buffer of fixed size $B_"vbv"$ bits that drains
at exactly the target bitrate. The encoder must keep the buffer within bounds: it can temporarily
spike (a complex scene can use more bits than average) as long as it pays them back later with
quieter frames, and it can never let the buffer underflow (the decoder would stall) or overflow
(bits would have to be dropped).

CBR is essential for *broadcast* (fixed-bandwidth channels), *live streaming* (no lookahead),
and *hardware decoders* with small memory. The price is reduced quality on hard scenes — when
complexity exceeds budget, QP must rise sharply, causing visible blocking.

#gopython("Functions with default arguments")[
  Functions in Python can have *default argument values*, which are used when the caller does not
  provide that argument. The syntax is `def f(x, y=10):` — here y defaults to 10.

  ```python
  def clamp(value: float, lo: float, hi: float) -> float:
      """Return value clipped to [lo, hi]."""
      return max(lo, min(hi, value))

  # called with all three arguments:
  print(clamp(1.5, 0.0, 1.0))   # → 1.0

  # called with two — lo defaults to 0.0 if we had set that:
  print(clamp(-3.0, 0.0, 10.0)) # → 0.0
  ```

  Default arguments make rate-control functions readable: you write
  `encode_frame(frame, target_bits=1024, vbv_size=8192)` and can override
  either or neither.
]

=== Variable Bitrate (VBR)

In VBR mode, the encoder has a target *average* bitrate over the entire file or clip, but is free
to exceed it on hard scenes and undershoot on easy ones. This produces dramatically better quality
because bits are concentrated where they matter. The constraint is looser: the total bytes at the
end must be within budget, not the instantaneous rate.

*Two-pass VBR* is the gold standard for offline encoding:
1. *First pass*: encode at medium quality with no concern for rate, collecting per-frame
   complexity statistics (residual energy, actual bit cost, predicted QP).
2. *Second pass*: use the first-pass statistics to build a model of the R–D curve for each
   frame, then solve a global allocation problem: given total budget B, how many bits should each
   frame get to equalize perceptual quality?

The second pass then encodes each frame at the QP derived from this allocation. The result is a
file where hard scenes and easy scenes both look equally good — the hallmark of professional encoding.

#keyidea[
  Two-pass VBR is the difference between an encoder that reacts to difficulty and one that
  *anticipates* it. The first pass is a scout that maps the terrain; the second pass is the
  army that moves through it efficiently.
]

=== Constant Rate Factor (CRF)

CRF is the mode of choice for modern single-pass offline encoding (x264, x265, libaom-AV1,
SVT-AV1, VVenC). Instead of targeting a bitrate, the user specifies a quality target — the CRF
value — and the encoder produces whatever bitrate achieves that quality for this content.

Internally, CRF works by computing a *base QP* from the CRF value and then applying
*per-frame QP offsets* based on frame type (I/P/B) and scene complexity. The encoder uses
a "qcomp" (quantizer compression) parameter to control how aggressively complexity variation
drives QP changes. At qcomp = 0 all frames get the same QP (CBR-like within scenes);
at qcomp = 1 every frame gets its optimal individual QP (true constant-quality, potentially
huge bitrate swings).

*Capped CRF* (or *CRF with VBV*) combines CRF with a VBV buffer constraint — the encoder aims
for the quality target but won't burst above a maximum bitrate. This is the dominant production
mode for video-on-demand (VOD): it gives near-CRF quality while bounding the peak bitrate that
CDN caches must handle.

#aside[
  The term "CRF" was coined for x264 by Loren Merritt (Dark Shikari) around 2007. x264 uses a
  macroblock-level quality measure called "frame complexity" to determine each macroblock's
  offset from the frame's base QP, implementing what is now called *adaptive quantization* (AQ)
  within CRF. Every major open encoder (x265, SVT-AV1, VVenC) has since copied the CRF concept.
]

== Perceptual Extensions: Beyond MSE

Plain MSE (mean squared error) is the distortion measure that makes the math clean, but human
eyes do not work like MSE. The visual system is more sensitive to errors in:
- *Smooth regions* (flat gradients) than in *textured regions* (noise, grass, fur).
- *Low-frequency* content (color, large shapes) than *high-frequency* detail.
- *Edges* and *faces* than backgrounds.

=== Adaptive Quantization

*Adaptive quantization* (AQ) is a technique that applies a per-region QP offset based on a
perceptual model. Regions that are dark, textured, or near noise can tolerate a higher QP
(coarser quantization); smooth or high-contrast regions need a lower QP (finer). The overall
bitrate stays at the target while quality is perceptually equalized.

x264 introduced *AQ-mode 2* (auto-variance AQ) which computes each macroblock's variance, then
assigns a QP offset:

$ Delta Q P_i = k dot (overline(V) - V_i) $

where $V_i$ is the log-variance of macroblock $i$, $overline(V)$ is the average across the
frame, and $k$ is a strength parameter (default 1.0 in x264). Blocks with below-average variance
get *lower* QP (more bits for the smooth areas where errors are visible); above-average variance
gets *higher* QP (fewer bits where texture hides noise).

#mathrecall[
  *Variance* (Chapter 10) measures _spread_: how far a block's pixel values scatter around their
  own average. A flat patch of sky has near-zero variance; a patch of gravel has high variance.
  AQ uses variance as a cheap stand-in for "how well this region hides quantization error" — high
  variance means the eye is busy and forgives coarse coding.
]

#misconception[Adaptive quantization reduces image quality to save bitrate.][
  AQ does not reduce average quality — it *redistributes* bits from perceptually unimportant
  regions to perceptually important ones. Total distortion (MSE) may slightly increase, but
  perceived quality (measured by SSIM or VMAF) improves because errors are now hidden in texture.
  The key insight: all distortion measures are not equal.
]

#note[
  *SSIM* (Structural Similarity) and *VMAF* are _perceptual_ quality measures — they try to score
  an image the way a human would, where plain MSE fails. SSIM returns a number between 0 and 1
  (1 = identical); VMAF returns a 0–100 score. We sketch VMAF below and dissect all of these
  metrics properly in Chapter 75, "Measuring Compression." For now, just read them as "closer to
  how good it actually looks than MSE is."
]

=== VMAF-Driven RDO

VMAF (Video Multi-method Assessment Fusion), developed by Netflix in 2016 and open-sourced the
same year, is a machine-learning-based video quality metric trained on human viewing scores.
It combines multiple "elementary metrics" (VIF at multiple scales, ADM — additive detail
measurement — and motion features) through a support-vector-machine regressor to predict a
human MOS (mean opinion score) in a [0, 100] range.

VMAF correlates far better with human judgment than PSNR on compressed content. Netflix
began using VMAF as the distortion measure inside their encoder in their "Dynamic Optimizer"
framework (2017–2018): instead of minimizing J = MSE + λR, they minimize J = (1 − VMAF) + λR,
effectively doing Lagrangian RDO with a perceptual distortion measure. Chapter 55 returns to the
Dynamic Optimizer and its per-shot machinery at full depth as part of encoding-at-scale; here we
care only that it is Lagrangian RDO with a smarter D.

In June 2026 Netflix published VMAF v1, an updated model addressing known weaknesses: improved
handling of high-frame-rate content, better response to film grain, and integration of CAMBI
(Contrast Aware Multiscale Banding Index) as a banding-artifact feature. VMAF v1 brings the
metric closer to being a true just-noticeable-difference (JND) predictor.

#algo(
  name: "Lagrangian RDO",
  year: "1998 (video); concept earlier in speech coding)",
  authors: "Gary J. Sullivan, Thomas Wiegand (H.263+/H.264 formalization)",
  aim: "Select, from all candidate coding modes for each block/CU/TU, the one that minimizes J = D + λR, thereby optimally trading quality against bits.",
  complexity: "O(M × N) per block where M = number of candidate modes, N = encoding cost per mode; dominant cost in a high-quality encoder.",
  strengths: "Theoretically grounded; decouples mode decision from rate control; generalizes to any distortion measure or rate model; globally consistent across all decisions in a frame.",
  weaknesses: "Computationally expensive (must evaluate many modes); λ must be tuned to the QP; MSE as distortion measure is perceptually suboptimal; local decisions ignore global interactions.",
  superseded: "Still the dominant framework; extended to perceptual D (VMAF-RDO) and learned transforms in neural codecs.",
)[
  Lagrangian RDO underpins every significant codec since H.263 (1995). The encoder iterates over
  all candidate coding decisions — intra prediction modes, inter motion vectors, block sizes,
  transform coefficients, entropy coding choices — and for each computes D (the error in the
  reconstructed block vs. original) and R (the bit cost to transmit the choice). It picks the
  option with smallest J = D + λR. In H.264 this is applied at the level of each macroblock,
  each partition, each motion vector, and each transform coefficient. In VVC (H.266) the tree
  of coding units can have hundreds of candidate splits, making the RDO search the dominant
  encoder compute cost.
]

== Two-Pass Encoding: Scouting Before Marching

Two-pass encoding is the industry workhorse for offline VOD content. Let's walk through it
concretely with a worked example.

=== First Pass: Building the Complexity Map

In the first pass the encoder runs quickly at a fixed medium-quality QP (say, 22) and records,
for each frame $f$, at minimum:
- The *actual rate* $R_f$ (bits used).
- The *actual distortion* $D_f$ (PSNR or SSIM vs. original).
- The *complexity score* $C_f$, typically the sum of absolute transform coefficients or the
  motion-compensated residual energy.

These measurements are saved to a *first-pass log file*. The first pass is fast (often 2–3×
realtime) because it makes fewer mode decisions and uses faster motion search.

=== Second Pass: Solving the Allocation Problem

Given a target total budget $B_"total"$ bits and a complexity map $C_1, ..., C_N$ for N frames,
the second pass solves: choose QP values $Q P_1, ..., Q P_N$ such that $sum_f R(Q P_f, C_f) =
B_"total"$ and quality variation across frames is minimized.

The encoder uses an empirical model relating complexity, QP, and bitrate. A common power-law
model (used in H.264 JM software) is:

$ R_f approx alpha_f times C_f times Q P_f^(-beta) $

where $alpha_f$ and $beta$ (typically near 1.5–2) are fit from first-pass data. Given the
target rate for each frame, the encoder inverts this formula to get the required QP.

The constraint is solved by binary search on a global *quality multiplier* q until the total
predicted bits match the budget. This is the second pass's "setup" phase; then encoding
proceeds at the derived per-frame QPs.

=== A Concrete Worked Example

Suppose a 5-second clip at 24 fps (120 frames) has three scenes:

#table(
  columns: (auto, auto, auto, auto, auto),
  stroke: 0.5pt,
  [*Frames*], [*Content*], [*Complexity $C$*], [*Budget share*], [*Resulting QP*],
  [1–30 (1s)],  [Still talking head], [Low (100)],    [12%],  [28],
  [31–90 (2s)], [Explosion + motion], [High (800)],   [65%],  [22],
  [91–120 (1s)],[Cut to black+text],  [Very low (20)],[23%],  [34],
)

Without allocation, all frames at QP=25 might give the explosion scene 65% of bits anyway but
waste them on the black frame. With two-pass, the encoder *knows* the black frame costs almost
nothing and reallocates those bits to the explosion. The result: the explosion looks significantly
better, with no perceptible change to the other scenes.

#checkpoint[
  If frame 50 in the explosion gets twice the bits of frame 5 in the talking head, does frame 50
  necessarily look twice as good?
][
  No! Rate and quality are related logarithmically (roughly), not linearly. Twice the bits might
  buy only 3–4 dB of extra PSNR. And perceptual quality is even harder to predict — the talking
  head might be more sensitive to any distortion because faces are what viewers scrutinize.
]

== Per-Title Encoding: The Operational R–D Approach at Scale

Traditional streaming services historically used a *fixed bitrate ladder*: one set of
(resolution, bitrate) pairs for all content. A news broadcast at 1 Mbps and a nature documentary
at 1 Mbps would both look completely different, because the documentary has far more
high-frequency detail and motion. Content with low complexity (a talking head) can look great
at 400 kbps; complex content (fireworks) may need 4 Mbps for the same visual score.

Netflix, in their influential 2015 blog post and 2016–2018 papers, pioneered *per-title
encoding*: for each title, encode a set of (resolution, QP) combinations, measure each's VMAF
score and bitrate, plot the resulting operational R–D cloud, find the convex hull, and build a
custom bitrate ladder from the hull points. This means every title has its own bitrate ladder,
optimized for its content.

The results were striking: per-title encoding reduced average bitrate by 20–30% at equal visual
quality compared to the fixed ladder, or equivalently, gave significantly higher quality at the
same bitrate. For simple animation ("BoJack Horseman") the savings were 70%; for complex live
sports, near zero — but the average across a diverse catalog was enormous.

*Per-shot encoding* takes this further: segments of a video that differ dramatically in complexity
— a slow establishing shot versus an action sequence — get independently optimized ladders. By
2023 Netflix was running per-shot optimization as standard practice. Chapter 55 covers the
production engineering of this scale-out (per-title, per-shot, content-adaptive encoding); we keep
our focus here on the underlying R–D principle it rests on.

=== The Bitrate Ladder as an Optimization Problem

A streaming bitrate ladder must satisfy several constraints:
- Consecutive rungs must be *perceptually distinct* — close enough for a smooth transition, far
  enough that the lower rung is clearly worse (to trigger an adaptive switch). Ideally, the
  visual difference between adjacent rungs is approximately one JND (just noticeable difference).
- The lowest rung must work on the slowest connection; the top rung matches the best-connected
  viewer.
- The total number of rungs is bounded by storage/CDN cost.

Finding the optimal ladder is a combinatorial optimization over the operational R–D cloud.
Practical solutions use the convex hull to identify Pareto-optimal points and then sample them
at perceptually equal intervals.

#gopython("List comprehensions and min/max")[
  A *list comprehension* builds a list by applying an expression to each element of an iterable.
  `[f(x) for x in xs]` creates a new list. We can filter with `if`: `[f(x) for x in xs if condition]`.

  ```python
  # Suppose rd_points is a list of (bitrate_kbps, vmaf_score) tuples
  rd_points: list[tuple[float, float]] = [
      (400, 72.1), (800, 80.3), (1500, 86.7),
      (3000, 91.2), (6000, 94.8),
  ]

  # Find the point with highest VMAF per kbps (efficiency):
  best = max(rd_points, key=lambda p: p[1] / p[0])
  print(f"Best efficiency: {best[1]:.1f} VMAF at {best[0]:.0f} kbps")
  # → Best efficiency: 80.3 VMAF at 800 kbps

  # Build a ladder: keep only points where VMAF > 75
  ladder = [p for p in rd_points if p[1] > 75.0]
  print(ladder)
  # → [(800, 80.3), (1500, 86.7), (3000, 91.2), (6000, 94.8)]
  ```

  List comprehensions make it easy to filter and transform R–D data without verbose loops.
]

== Intra-Frame RDO: Quantizing Individual Coefficients

So far we have discussed frame-level bit allocation. But Lagrangian RDO applies at finer
granularity too: down to individual transform coefficients. This is *intra-frame* or
*coefficient-level* RDO.

=== Transform Coefficient Decision: Zero or Not?

After a DCT or wavelet transform, many high-frequency coefficients are small. The question is:
should we quantize this coefficient to zero (save bits, add distortion) or keep it (cost bits,
preserve fidelity)? The Lagrangian framework answers it directly. For coefficient $c_k$ with
quantized value $c_k'$:

- *Keep at non-zero*: rate cost = $R_k$ bits; distortion = $(c_k - c_k' times q)^2$.
- *Zero out*: rate cost = 0 (or just a zero flag); distortion = $c_k^2$.

Choose whichever has smaller J = D + λR. For small $c_k$ (low-energy coefficient), zeroing
is almost free in distortion and saves bits: zeroing wins. For large $c_k$, keeping it is
essential. The threshold where zeroing wins is approximately:

$ abs(c_k) < sqrt(lambda dot R_k) $

This is the theoretical basis for *trellis quantization* (used in H.264 and H.265) — a more
sophisticated version that optimizes an entire block of coefficients simultaneously via dynamic
programming on a trellis graph (see Chapter 14 for dynamic programming).

#pitfall[
  The common encoder parameter "quant dead-zone" (dead\_zone or dz in most encoders) is a
  practical approximation of trellis quantization. Setting it too large zeroes too many
  coefficients, causing "flat" artifacts in textures. Setting it too small wastes bits on
  coefficients that contribute nothing visible. The theoretical ideal dead-zone for MSE is
  q/2 (round-to-nearest); for perceptual quality it is larger (q × 0.7 to 0.85 × q) because
  the eye does not see small differences in textured regions.
]

=== Trellis Quantization

*Trellis quantization* treats the quantized coefficient sequence as a path through a trellis
(a graph where each node is a possible coefficient value and each edge has a rate+distortion cost).
The optimal sequence minimizes total J = D + λR across the block. This is solved by the
Viterbi algorithm in O(N × L) time where N is the number of coefficients and L is the number of
candidate quantization levels per coefficient.

H.264/AVC's JM reference encoder and all production encoders (x264, FFmpeg libx264) implement
trellis quantization as an option. For static images or slow scenes, enabling trellis quantization
can improve PSNR by roughly 0.5–1 dB at equal bitrate (or, equivalently, cut a few percent of
bits at equal quality). The cost is encoder complexity: typically 2–4× slower than no trellis.

== The Quality–Speed–Bitrate Triangle

Every encoder sits at a point in a three-way trade-off triangle:
- *Quality*: how close the reconstruction is to the original.
- *Speed*: how fast the encoder runs (realtime, or hours per frame).
- *Bitrate*: how many bits are used.

Improving any one of these typically worsens at least one of the others. Rate-control and RDO
are the tools for navigating this space. Consider some characteristic operating points:

#table(
  columns: (auto, auto, auto, auto, auto),
  stroke: 0.5pt,
  [*Use case*], [*Mode*], [*Quality*], [*Speed*], [*Bitrate control*],
  [Video call (Zoom)], [CBR], [Medium], [Realtime], [Strict, 100–800 kbps],
  [YouTube live stream], [CBR + VBV], [Good], [Realtime], [Constrained, 4–8 Mbps],
  [Netflix VOD archival], [CRF + VMAF-RDO], [Excellent], [Slow (hours)], [Flexible, per-title],
  [Blu-ray mastering], [2-pass VBR], [Near-lossless], [Very slow], [Fixed total bytes],
  [JPEG still image], [Single-pass QP], [Variable], [Instant], [User-chosen QP],
)

For neural codecs (Chapters 57–59), the same Lagrangian framework is used but the "encoder"
is a neural network trained to minimize $ cal(L) = D + lambda R$ end-to-end. λ becomes a
hyperparameter of training, not just a run-time knob, and the result is a *family* of models
(one per λ value) each corresponding to a point on the R–D curve.

== Rate-Distortion Optimization for Images: JPEG as a Case Study

While Chapters 42 and 43 go deeper, it's instructive to see how RDO applies in JPEG right now,
given what we know.

JPEG does not perform Lagrangian RDO in the encoder — it was designed in the early 1990s for
simplicity and speed. Each DCT block is quantized by dividing by entries in a fixed *quantization
matrix* and rounding. There is no λ, no mode decision, no adaptive allocation.

This is exactly why JPEG is sub-optimal. Consider two 8×8 blocks:
- *Block A*: a smooth blue sky. Almost all energy is in one low-frequency coefficient.
- *Block B*: a detailed brick wall. Energy spread across 30+ frequencies.

With JPEG's fixed matrix, both blocks get identical quantization step sizes per frequency. But
Block A could be compressed far more aggressively (its high-frequency coefficients are near zero
anyway) while Block B needs finer steps to avoid visible ringing. A proper RDO-aware image codec
would allocate differently per block.

JPEG 2000 (Chapter 43) addressed this via its rate-allocation layer (PCRD-opt: Post-Compression
Rate–Distortion optimization), which takes already-coded wavelet packets, sorts them by distortion-
reduction-per-bit (D-rate), and greedily adds them to the output until the bitrate budget is
exhausted — a near-optimal greedy algorithm for convex R–D curves. JPEG XL (Chapter 45) takes
this further with explicit per-group adaptive quantization and a sophisticated RDO search.

#algo(
  name: "PCRD-opt (Post-Compression R–D Optimization)",
  year: "2000",
  authors: "David Taubman (core JPEG 2000 design)",
  aim: "Optimally truncate pre-coded wavelet packets to hit a target bitrate, by sorting code-block contributions by their incremental D/ΔR ratio.",
  complexity: "O(N log N) where N = number of code-block truncation points across the image.",
  strengths: "Near-optimal rate allocation without re-encoding; handles arbitrary R–D shapes; enables scalable/progressive transmission as a byproduct.",
  weaknesses: "Requires the full compressed bitstream before truncation (large memory); only optimal for convex individual R–D curves; does not account for visual perception.",
  superseded: "Used in JPEG 2000 and HTJPEG 2000; less influential in subsequent codecs that integrate RDO into the encoding loop directly.",
)[
  PCRD-opt separates *compression* from *allocation*: first compress everything to the highest
  quality (generating all possible code-block layers), then optimally select which layers to
  include. It is a greedy knapsack: sort all available "packets" by D/ΔR and include them until
  the budget is full. The proof of optimality relies on the R–D curve of each code block being
  convex — a property JPEG 2000's bit-plane coding guarantees.
]

== Worked Example: Choosing Lambda

Let's work through a concrete numerical example of Lagrangian mode decision to see exactly how
the math plays out.

An encoder must choose between two coding modes for a 16×16 block:

- *Mode 1 (Intra DC)*: predict the block as its mean value, code the residual with 1 bit per
  pixel (coarse). Rate: 256 bits. Distortion (MSE): 80.
- *Mode 2 (Intra Smooth)*: use a gradient predictor, code residual with 2 bits per pixel. Rate:
  512 bits. Distortion: 20.
- *Mode 3 (Skip)*: copy the block from the previous frame, code nothing. Rate: 8 bits (just
  the skip flag). Distortion: 150.

Given λ = 0.5:

$ J_1 = 80 + 0.5 times 256 = 80 + 128 = 208 $
$ J_2 = 20 + 0.5 times 512 = 20 + 256 = 276 $
$ J_3 = 150 + 0.5 times 8 = 150 + 4 = 154 $

Mode 3 (Skip) wins! The distortion is higher but the bits saved dwarf it at this λ.

Given λ = 5:

$ J_1 = 80 + 5 times 256 = 80 + 1280 = 1360 $
$ J_2 = 20 + 5 times 512 = 20 + 2560 = 2580 $
$ J_3 = 150 + 5 times 8 = 150 + 40 = 190 $

Mode 3 still wins — but notice that at λ = 0.1:

$ J_1 = 80 + 0.1 times 256 = 80 + 25.6 = 105.6 $
$ J_2 = 20 + 0.1 times 512 = 20 + 51.2 = 71.2 $
$ J_3 = 150 + 0.1 times 8 = 150 + 0.8 = 150.8 $

Mode 2 wins — at very low λ (bits are cheap), the encoder invests heavily in fidelity.

This tiny three-way choice, multiplied across thousands of blocks per frame and hundreds of frames
per second, is the heartbeat of every modern video encoder.

== Rate Control in Practice: Tuning Tips

Understanding RDO helps practitioners tune encoders correctly. A few concrete guidelines.

=== Choosing CRF vs. 2-Pass VBR

Use CRF when:
- You do not know the target file size in advance.
- Content is being encoded once and stored (personal archival, VOD ingest).
- Speed matters and you do not want two passes.

Use 2-pass VBR when:
- You must hit an exact target file size (DVD/Blu-ray authoring, broadcast slot).
- Quality consistency across scenes is critical (premium VOD distribution).
- You have time for two passes.

Use CBR when:
- Real-time streaming with a fixed bandwidth cap.
- Hardware decoders with strict buffer sizes.
- Live broadcasting.

=== The λ–QP Relationship in Practice

The formulas above (e.g., λ = 0.85 × 2^((QP−12)/3)) are starting points. Different content
needs different λ values for optimal results:
- Film grain and high-detail natural content: lower λ (spend more bits for fidelity).
- Cartoons, screen recordings, flat graphics: higher λ (texture is cheap to quantize).
- Screen content mode (H.265/HEVC, VVC): uses a separate RDO mode tuned for flat areas and
  sharp text edges, with a different λ–QP mapping.

Most encoder tuning guides recommend setting the quality target (CRF or target bitrate) and
letting the encoder manage λ internally, adjusting only via the `-aq-mode` (adaptive quantization
mode) and `-aq-strength` parameters for perceptual optimization.

#checkpoint[
  You encode a video at CRF 23 in x264 and the file is 2 GB. You need it to be 1 GB.
  What are your options?
][
  Option A: raise CRF (e.g., to 27 or 29). Each CRF step of ~6 approximately halves bitrate.
  Option B: switch to 2-pass VBR with target 1 GB and let the encoder allocate optimally.
  Option C: lower resolution (e.g., 1080p → 720p) — the codec's task becomes intrinsically easier.
  Option D: choose a more efficient codec (e.g., H.265 or AV1 instead of H.264) — for the same
  quality, they produce 30–50% fewer bits, often enabling 1 GB at equal visual quality.
]

== The Neural Era: Learned Rate–Distortion Trade-offs

Traditional encoders implement RDO as a search: try many modes, evaluate J = D + λR, pick the
best. Neural codecs (Chapter 57) take a radically different approach: *learn* the entire encoder
as a function that directly minimizes the Lagrangian.

#note[
  This section is a *preview* — it uses two ideas the book builds from scratch later. _Gradient
  descent_ (nudging a function's tunable numbers downhill to reduce an error, using the slope/
  derivative from the gentle calculus of Chapter 11) and _backpropagation_ (the bookkeeping that
  computes those slopes through a whole neural network) are taught in the machine-learning primer
  of Chapter 56. Read the formulas below for their *shape* — "the network is trained to minimize
  D + λR directly" — and trust Chapters 56–57 to fill in the machinery.
]

The training loss is:

$ cal(L)(theta) = D(x, hat(x)) + lambda dot R(hat(z)) $

where $x$ is the input, $hat(x) = g_s(hat(z))$ is the reconstruction (synthesis transform applied
to quantized latent $hat(z)$), and R is the expected code length under the learned entropy model.
Gradient descent on this loss with respect to network parameters θ simultaneously learns the
analysis transform, the entropy model, and (implicitly) the quantization boundaries.

The key challenge: the quantization operation $hat(z) = "round"(z)$ has zero gradient
everywhere, breaking backpropagation. The standard fix (Ballé et al., 2017) is to substitute
additive uniform noise during training:

$ hat(z) = z + cal(U)(-1/2, 1/2) $

where $cal(U)(-1/2, 1/2)$ means "a random nudge drawn uniformly between $-1/2$ and $+1/2$" (every
value in that range equally likely — the probability built in Chapter 9),
whose expectation matches rounding and whose derivative is 1 — so gradients flow through. At
test time, actual rounding is used. This training trick enables the whole pipeline to be trained
end-to-end to minimize the Lagrangian, producing a learned codec whose R–D curve (on natural
images) beats hand-designed codecs.

The λ value during training determines which point on the R–D curve the model will operate at.
To cover the whole curve, practitioners train a separate model for each λ in {0.0018, 0.0035,
0.0067, 0.013, 0.025, 0.048, 0.095, 0.18} (or similar logarithmic grid). Each model is a
complete encoder/decoder pair, typically 20–100 MB of weights. This is expensive storage — a
problem active learned-codec research is addressing with *variable-rate* models.

== What Rate–Distortion Optimization Cannot Do

RDO is powerful but has real limits. Four things it cannot fix:

1. *A broken source signal*. If the original video was captured out of focus or in poor light,
   no amount of RDO recovers missing information. Garbage in, garbage out.

2. *Badly chosen distortion measures*. If your D is MSE but viewers care about structural
   similarity, you optimize the wrong thing. This is why VMAF-driven RDO is valuable: it trains
   D to match human perception.

3. *Global bit allocation*. Lagrangian RDO is fundamentally *local*: it makes each block or frame
   decision independently. It cannot globally redistribute bits from easy scenes to hard ones
   (that requires look-ahead or two-pass). Local RDO with a poor λ schedule can actually
   waste bits systematically.

4. *Complexity beyond the encoder's mode set*. If the "right" coding mode (e.g., a large skip
   region covering 128×128 pixels) is not in the encoder's mode search, RDO cannot find it.
   Expanding mode sets is how standards committees improve codecs — H.266/VVC's massive mode set
   (CTU sizes from 4×4 to 128×128, numerous intra/inter/palette/IBC modes) explains why it
   achieves 40% fewer bits than H.264 for equal quality, at the cost of 10–1000× encoder
   complexity.

#keyidea[
  Rate–distortion optimization is a *framework*, not a magic wand. Its power comes from
  consistently applying the same objective (J = D + λR) to every decision in the encoder.
  Its limits are the limits of the objective and the mode set, not the framework itself.
]

#takeaways((
  "The Lagrangian J = D + λR unifies all encoder decisions: pick the coding mode with smallest J.",
  "λ (lambda) converts bits into distortion units; changing λ slides the encoder along the R–D curve.",
  "The operational R–D curve is the set of real (rate, quality) points achievable by a codec on specific content. Its convex hull defines the efficient operating frontier.",
  "CBR fixes bitrate (needed for streaming/live); VBR targets average bitrate (best for VOD quality); CRF fixes perceptual quality level (simplest for archival).",
  "Two-pass encoding scouts complexity in a first pass, then allocates bits optimally in the second pass — the gold standard for fixed-size targets.",
  "Adaptive quantization (AQ) redistributes bits within a frame based on perceptual sensitivity, improving SSIM/VMAF without changing average bitrate.",
  "Per-title encoding builds a custom bitrate ladder from each title's own operational R–D cloud, saving 20–30% bitrate on average for a streaming library.",
  "Neural codecs train directly to minimize the Lagrangian, with the uniform-noise trick enabling gradient-based optimization through the quantization step.",
  "RDO's limits: it cannot fix a poor source, a wrong distortion measure, a missing mode, or the absence of global look-ahead.",
))

== Exercises

#exercise("41.1", 1)[
  An encoder can code a block in two modes:
  - Mode A: rate = 32 bits, MSE = 200.
  - Mode B: rate = 80 bits, MSE = 40.

  (a) For what value of λ are Modes A and B exactly equal cost?
  (b) For λ = 3, which mode wins?
  (c) For λ = 0.5, which mode wins?
]

#solution("41.1")[
  (a) Set $J_A = J_B$: $200 + lambda times 32 = 40 + lambda times 80$. Solving: $160 = 48 lambda$, so $lambda = 10/3 approx 3.33$.

  (b) λ = 3: $J_A = 200 + 96 = 296$; $J_B = 40 + 240 = 280$. Mode B wins (lower J).

  (c) λ = 0.5: $J_A = 200 + 16 = 216$; $J_B = 40 + 40 = 80$. Mode B still wins decisively.
  (At very low λ, bits are cheap, so Mode B — higher quality at higher rate — wins easily.)
]

#exercise("41.2", 1)[
  Explain in plain language why increasing CRF in x264 (say, from 18 to 28) decreases file size.
  What exactly changes inside the encoder?
]

#solution("41.2")[
  CRF increases correspond to a larger base QP for each frame. A larger QP means a larger quantization
  step size, so transform coefficients are rounded more aggressively to coarser values. Fewer distinct
  values produce lower entropy, which the entropy coder compresses into fewer bits. Quality drops
  because information is permanently discarded in the coarser rounding — reconstruction errors are
  larger. In Lagrangian terms, a higher CRF raises λ, making each bit more "expensive" and pushing
  the encoder toward higher-distortion, lower-rate choices for every block.
]

#exercise("41.3", 2)[
  A 10-minute clip has five scenes with the following first-pass measured bits at QP = 22:

  | Scene | Length | Bits at QP=22 |
  |-------|--------|---------------|
  | A     | 2 min  | 600 MB        |
  | B     | 3 min  | 180 MB        |
  | C     | 1 min  | 400 MB        |
  | D     | 2 min  | 100 MB        |
  | E     | 2 min  | 220 MB        |

  Total budget is 750 MB. Using a simple proportional allocation (each scene gets budget
  proportional to its QP=22 bit cost), compute the target bits for each scene. Which scene
  benefits most from proportional allocation vs. naive equal-per-minute allocation?
]

#solution("41.3")[
  Total at QP=22: 600+180+400+100+220 = 1500 MB. Compression ratio = 750/1500 = 0.5.

  Proportional targets: A: 300 MB, B: 90 MB, C: 200 MB, D: 50 MB, E: 110 MB. Total: 750 MB. ✓

  Naive equal per minute: 10 minutes / 750 MB = 75 MB/min. Targets: A: 150, B: 225, C: 75, D: 150, E: 150.

  Scene C suffers most under naive allocation: it is a complex 1-minute scene that needs 400 MB at
  high quality but gets only 75 MB naively (vs. 200 MB proportionally). Scene B (3 minutes, easy
  content needing only 180 MB) gets over-allocated naively (225 MB) — wasted bits on easy content.
  The proportional scheme correctly redirects bits from easy scenes (B, D) to complex ones (A, C).
]

#exercise("41.4", 2)[
  Why does per-title encoding save more bitrate on animated content (e.g., cartoons) than on
  sports content? Use R–D curve reasoning in your answer.
]

#solution("41.4")[
  Animation has very low spatial complexity: flat colors, simple backgrounds, limited motion. Its
  operational R–D curve is steep and reaches "good enough" quality at very low bitrates. Sports has
  high complexity: fine grass texture, fast motion, camera pans — its R–D curve is shallower and
  needs significantly more bits to achieve the same VMAF score. A fixed bitrate ladder allocates
  many bits to animation that it does not need (the quality curve has already plateaued) and may
  under-allocate to sports. Per-title encoding moves animation to a much lower rung (saving 50–70%
  bits) and may increase sports rungs slightly. Since animated content dominates many catalogs,
  the average savings are large.
]

#exercise("41.5", 2)[
  Explain trellis quantization. Why does it give better results than independent coefficient
  rounding? What is the algorithmic technique used to solve it efficiently?
]

#solution("41.5")[
  Independent rounding rounds each transform coefficient $c_k$ to the nearest multiple of the
  step size q, ignoring interactions between coefficients. Trellis quantization treats the
  entire block's coefficient sequence as a path through a trellis graph: each state represents
  a possible quantized value, and each edge has a combined distortion + rate cost (J = D + λR).
  The total cost includes both the quantization error *and* the entropy-coding cost of the
  chosen sequence (since adjacent non-zero coefficients affect the run-length coding cost).

  The optimal path through the trellis — minimizing total J over all coefficients — is found
  by the *Viterbi algorithm* (dynamic programming on the trellis), which runs in O(N × L) time
  where N is the number of coefficients and L is the quantization alphabet size. This globally
  considers which coefficients to zero out vs. keep, weighing the bit savings against the
  distortion increase, rather than making each decision in isolation.
]

#exercise("41.6", 3)[
  Implement a simple first-pass bit-allocation in Python. Given a list of per-frame
  complexity scores and a total bit budget, compute the QP for each frame assuming a
  power-law model $R_f = 1000 times C_f times 2^(-Q P_f / 6)$. Use binary search on a global
  quality multiplier to find QPs such that total predicted bits equals the budget.
]

#solution("41.6")[
  ```python
  import math

  def allocate_bits(complexities: list[float], total_budget: float) -> list[float]:
      """
      Given per-frame complexities and a total bit budget, compute per-frame QP values
      using power-law model: R_f = 1000 * C_f * 2^(-QP_f / 6).
      Strategy: scale all QPs by a global offset d so sum equals budget.
      """
      base_qp = 22.0  # starting QP for all frames

      def total_bits(delta_qp: float) -> float:
          total = 0.0
          for c in complexities:
              qp = base_qp + delta_qp
              total += 1000.0 * c * (2 ** (-qp / 6))
          return total

      # binary search on delta_qp in [-20, 40]
      lo, hi = -20.0, 40.0
      for _ in range(50):
          mid = (lo + hi) / 2
          if total_bits(mid) > total_budget:
              lo = mid
          else:
              hi = mid

      best_delta = (lo + hi) / 2
      return [base_qp + best_delta] * len(complexities)  # uniform QP (global)

  # Non-uniform: per-frame QP proportional to log(complexity)
  def allocate_bits_adaptive(complexities: list[float], total_budget: float) -> list[float]:
      """Per-frame QP: offset each frame's QP by log2(C/Cbar), then binary-search global."""
      if not complexities:
          return []
      log_cs = [math.log2(max(c, 1e-6)) for c in complexities]
      mean_log = sum(log_cs) / len(log_cs)
      offsets = [lc - mean_log for lc in log_cs]  # positive → harder → lower QP

      def total_bits(base: float) -> float:
          total = 0.0
          for c, off in zip(complexities, offsets):
              qp = base - off  # harder frames get lower QP
              total += 1000.0 * c * (2 ** (-qp / 6))
          return total

      lo, hi = 10.0, 60.0
      for _ in range(60):
          mid = (lo + hi) / 2
          if total_bits(mid) > total_budget:
              lo = mid
          else:
              hi = mid

      base = (lo + hi) / 2
      return [base - off for off in offsets]

  # Test
  complexities = [800.0, 100.0, 400.0, 50.0, 200.0]
  budget = 5_000_000  # 5 million bits
  qps = allocate_bits_adaptive(complexities, budget)
  for i, (c, qp) in enumerate(zip(complexities, qps)):
      bits = 1000 * c * (2 ** (-qp / 6))
      print(f"Frame {i}: complexity={c:.0f}, QP={qp:.1f}, predicted bits={bits:.0f}")
  ```
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/4015642")[Sullivan, G. J. & Wiegand, T. (1998). Rate-Distortion Optimization for Video Compression. IEEE Signal Processing Magazine 15(6).] The foundational paper formalizing Lagrangian RDO for video.

- #link("https://netflixtechblog.com/per-title-encode-optimization-7e99442b62a2")[Netflix Technology Blog (2015). Per-Title Encode Optimization.] The original blog post explaining the per-title encoding approach.

- #link("https://netflixtechblog.com/dynamic-optimizer-a-perceptual-video-encoding-optimization-framework-e19f1e3a277f")[Netflix Technology Blog (2018). Dynamic Optimizer — a Perceptual Video Encoding Optimization Framework.] VMAF-driven RDO in production.

- #link("https://medium.com/netflix-techblog/vmaf-v1-good-is-not-good-enough-60d7e4244ea8")[Netflix Technology Blog (2026). VMAF v1: Good Is Not Good Enough.] The June 2026 update to the VMAF perceptual model.

- #link("https://arxiv.org/abs/1611.01704")[Ballé, J., Laparra, V. & Simoncelli, E. (2017). End-to-End Optimized Image Compression. ICLR 2017.] The paper that extended Lagrangian RDO to learned, end-to-end trained codecs.

- #link("https://slhck.info/video/2017/03/01/rate-control.html")[Hoff, S. (2017). Understanding Rate Control Modes.] The best practical guide to CBR/VBR/CRF from a practitioner's perspective.

- #link("https://arxiv.org/abs/2411.05295")[Content-Adaptive Rate-Quality Curve Prediction Model in Media Processing System (2024).] Recent research on predicting R–D curves for efficient per-title encoding without exhaustive sweeps.

#bridge[
  We have seen how encoders decide where to spend bits and how much quality each decision buys.
  The next chapter, Chapter 42, puts all of this into action inside the world's most successful
  image codec: JPEG. We will trace the complete pipeline — YCbCr color space, chroma subsampling,
  the 8×8 DCT, the quantization tables (now you know exactly what those tables represent
  in Lagrangian terms!), the zig-zag scan, run-length coding, and Huffman entropy coding — and we
  will build a toy JPEG encoder in tinyzip (Step 19). Everything in Chapter 42 will be grounded
  in the RDO framework you now understand.
]
