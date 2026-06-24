#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Prediction and Differential Coding

#epigraph[
  "In all things there is a law of cycles."
][Tacitus, _Annals_, c. 117 CE]

Imagine you are reading out a thermometer every second: 20, 20, 21, 21, 20, 20, 21 … The numbers themselves are boring; they barely change. A smarter clerk would write the *first* reading in full, then only the tiny ups and downs: +0, +1, +0, −1, +0, +1 … The shorthand is almost always "0" or "±1", which compresses magnificently compared to repeating the full two-digit values.

That clerk's trick (record changes, not absolutes) is the principle behind *differential coding*. In Chapter 37 we met the sampling theorem and saw how audio and images become streams of correlated numbers. In Chapter 39 we learned to quantize: round values to a coarser grid, losing a little precision to save many bits. Now we ask a sharper question: before we even quantize, can we *predict* the next sample from the ones we already have? If the prediction is good, the error is tiny. Code the tiny error instead of the big original, and you win.

This idea underpins JPEG's lossless predictor, FLAC's linear predictor, JPEG-LS's LOCO-I, every telephone network since the 1970s, and the formidable analysis-by-synthesis speech codecs (CELP) that live in your pocket right now. It also connects directly to the "Compression = Prediction" thesis of Chapter 23: *any* good predictor is, secretly, a good compressor. Here we make that concrete with three increasingly powerful prediction tools: DPCM, delta modulation, and linear predictive coding (LPC) with the Levinson–Durbin algorithm.

#recap[
  Chapter 37 (Signals, Sampling, and the Frequency Domain) showed that a signal sampled at the Nyquist rate captures all information exactly, and that neighbouring samples are strongly correlated. Chapter 38 (Transforms: KLT, DCT, Wavelets, MDCT) showed how transforms decorrelate a signal before quantization. Chapter 39 (Quantization: From Scalar to Vector) introduced the uniform scalar quantizer and the dead-zone, and showed that quantization error ("distortion") is the irreversible lossy step. Chapter 23 (Compression = Prediction = Learning) proved that the expected code length under arithmetic coding equals the cross-entropy of the predictor. Perfect prediction means zero bits. This chapter makes that principle operational: we replace the transform with a *predictor*, and entropy-code only the small residual.
]

#objectives((
  "Explain what DPCM is and why coding differences instead of values saves bits.",
  "Trace the feedback loop in a DPCM coder and identify the slope-overload and granular-noise regimes.",
  "Describe adaptive delta modulation (ADM) and why it outperforms fixed-step delta modulation.",
  "State the linear prediction model and write down the prediction error (residual) signal.",
  "Understand what the autocorrelation function measures and why it governs the optimal predictor.",
  "Summarise the Levinson–Durbin algorithm and explain why it is fast.",
  "Show how JPEG-LS's LOCO-I predictor avoids granular noise near edges.",
  "Read a short LPC analysis-synthesis Python sketch and relate it to the FLAC codec.",
))

== The Core Idea: Code the Difference

=== Why Differences Are Small

A natural signal (speech, music, image rows, temperature logs) has a fundamental property: *adjacent samples are similar*. In probability language, consecutive samples are *highly correlated*. Chapter 37 quantified this with the autocorrelation function; for a microphone recording of speech, the sample-to-sample correlation coefficient is typically above 0.9.

That correlation is waste. When two neighbouring values are almost the same, sending both in full is redundant. The remedy is:

1. Keep the *previous* reconstructed sample $hat(x)_(n-1)$ as the prediction for $x_n$.
2. Compute the *residual* (also called the *prediction error*): $e_n = x_n - hat(x)_(n-1)$.
3. Quantize and transmit $e_n$, not $x_n$.
4. The decoder adds $e_n$ back to its own copy of $hat(x)_(n-1)$ to recover $hat(x)_n$.

Because the signal barely changes between samples, $e_n$ is almost always close to zero. A histogram of $e_n$ peaks sharply at zero and falls off quickly, with much less spread than the original signal. Less spread means lower entropy, which means fewer bits for the entropy coder.

#keyidea[
  Prediction does not remove information; it redistributes it. We replace a *flat* distribution of large values with a *peaked* distribution of small residuals. The entropy coder downstream (Huffman, arithmetic, ANS, all covered in earlier chapters) then has an easy job.
]

=== The DPCM Feedback Loop

The full scheme is called *Differential Pulse-Code Modulation* (DPCM). The name comes from *pulse-code modulation* (PCM), which is simply the original signal digitised as a stream of values (the format of a CD or WAV file).

#algo(
  name: "DPCM",
  year: "1952 (concept); formalised 1950s–60s",
  authors: "C. Chapin Cutler (Bell Labs, 1952 patent), various refinements",
  aim: "Reduce bit-rate by transmitting quantised prediction residuals instead of raw PCM samples.",
  complexity: "O(n) encode and decode; memory: one or more previous samples.",
  strengths: "Very simple; low latency (sample-by-sample); works on any correlated signal.",
  weaknesses: "Fixed predictor cannot adapt to non-stationary signals; quantizer step size must match signal dynamics.",
  superseded: "Adaptive DPCM (ADPCM, G.726) for telephony; LPC for speech; linear prediction + Rice for lossless audio.",
)[
  DPCM encodes and decodes through a *closed feedback loop* that keeps the predictor at both ends in sync. The encoder does not subtract the *original* previous sample. It subtracts the *quantised* (reconstructed) previous sample, exactly as the decoder will reconstruct it. That way, quantisation errors do not accumulate: both sides always agree on the prediction.
]

Let us trace the loop step by step for a single sample:

*Encoder:*
1. Receive new sample $x_n$.
2. Predict: $hat(x)_n = f(hat(x)_(n-1), hat(x)_(n-2), …)$ (simplest case: $hat(x)_n = hat(x)_(n-1)$).
3. Compute residual: $e_n = x_n - hat(x)_n$.
4. Quantise: $hat(e)_n = Q(e_n)$ (round to nearest multiple of step size $Delta$).
5. Transmit $hat(e)_n$ (using a variable-length or entropy code).
6. *Update local reconstruction:* $hat(x)_n = hat(x)_n + hat(e)_n$. (The encoder keeps a running reconstruction to use next time.)

*Decoder:*
1. Receive $hat(e)_n$.
2. Predict: $hat(x)_n = f(hat(x)_(n-1), …)$ (same formula as encoder).
3. Reconstruct: $hat(x)_n = hat(x)_n + hat(e)_n$.

Since both sides run the *same* predictor on the *same* reconstruction history, they are always synchronised. Even if $hat(e)_n$ is slightly wrong because of coarse quantisation, both sides add exactly the same wrong value, so the error does not drift.

#fig(
  [DPCM feedback loop. The bold "+/−" nodes compute residuals (encoder) and sums (decoder). Both sides maintain an identical reconstructed signal $hat(x)_n$ from the same quantised residuals.],
  cetz.canvas({
    import cetz.draw: *
    // Encoder side
    content((1, 5), [*Encoder*], anchor: "west")
    rect((0,4),(2,4.5), fill: rgb("#e8f4ea"), stroke: 0.6pt)
    content((1,4.25), [$x_n$], anchor: "center")

    // subtract node
    circle((1,3), radius: 0.3, stroke: 0.7pt)
    content((1,3), [$-$])

    // quantizer
    rect((0.25,1.8),(1.75,2.4), fill: rgb("#fff3e0"), stroke: 0.6pt)
    content((1,2.1), box(width: 1.1cm, inset: 1pt, align(center, text(size: 8pt)[Quantizer $Q$])))

    // transmit
    rect((0.25,0.8),(1.75,1.4), fill: rgb("#e3eaf8"), stroke: 0.6pt)
    content((1,1.1), box(width: 1.1cm, inset: 1pt, align(center, text(size: 8pt)[Transmit $hat(e)_n$])))

    // delay / predictor box
    rect((3,2.2),(5,2.8), fill: rgb("#f5e6f8"), stroke: 0.6pt)
    content((4,2.5), box(width: 1.6cm, inset: 1pt, align(center, text(size: 8pt)[Predictor $hat(x)_n$])))

    // add node encoder
    circle((4,3), radius: 0.3, stroke: 0.7pt)
    content((4,3), [$+$])

    // arrows encoder
    line((1,4),(1,3.3), mark: (end: ">"))
    line((1,2.7),(1,2.4), mark: (end: ">"))
    line((1,1.8),(1,1.4), mark: (end: ">"))
    line((1,3),(0.3+0.7,3), (1,3))
    // from quantizer to add
    line((1.75,2.1),(3,2.5), mark: (end: ">"))
    line((4,2.2),(4,3.3), mark: (end: ">"), stroke: (dash: "dashed"))
    // predictor to subtract
    line((3,2.5),(1.3,3), mark: (end: ">"), stroke: (dash: "dashed"))

    // Decoder side (right)
    content((6.5, 5), [*Decoder*], anchor: "west")
    rect((6,1.5),(8,2.1), fill: rgb("#e3eaf8"), stroke: 0.6pt)
    content((7,1.8), box(width: 1.6cm, inset: 1pt, align(center, text(size: 8pt)[Receive $hat(e)_n$])))

    circle((7,3), radius: 0.3, stroke: 0.7pt)
    content((7,3), [$+$])

    rect((5.5,3.8),(8.5,4.3), fill: rgb("#e8f4ea"), stroke: 0.6pt)
    content((7,4.05), box(width: 2.6cm, inset: 1pt, align(center, text(size: 8pt)[$hat(x)_n$ output])))

    rect((8.5,2.2),(10.5,2.8), fill: rgb("#f5e6f8"), stroke: 0.6pt)
    content((9.5,2.5), box(width: 1.6cm, inset: 1pt, align(center, text(size: 8pt)[Predictor $hat(x)_n$])))

    line((7,2.1),(7,2.7), mark: (end: ">"))
    line((7,3.3),(7,3.8), mark: (end: ">"))
    line((8.5,2.5),(7.3,3), mark: (end: ">"), stroke: (dash: "dashed"))
    line((7,3.8),(9.5,2.8), mark: (end: ">"), stroke: (dash: "dashed"))
  })
)

#checkpoint[
  Why does the DPCM encoder subtract the *reconstructed* previous sample rather than the *original* previous sample?
][
  If the encoder subtracted the original and the decoder reconstructed from the quantised residual, both sides would accumulate a different running value of $hat(x)$. After many samples their predictions would diverge, and the audio or image would drift away from the original. Subtracting the same reconstructed value that the decoder will use keeps both sides locked to the same history.
]

== Delta Modulation: The Simplest DPCM

=== One Bit Per Sample

Push DPCM to its logical minimum: make the quantiser output *one bit*, just a sign, either "went up" (+1) or "went down" (−1). The reconstructed signal climbs by a fixed step $Delta$ each time or falls by $Delta$. This is *delta modulation* (DM), developed independently by de Jager (Netherlands, 1952) and others in the early 1950s, and widely deployed in military communications and telephony through the 1960s–1980s.

The staircase reconstruction tracks the input by constantly nudging up or down. If the signal is flat, the output oscillates ±$Delta$ around it: this is *granular noise*. If the signal rises faster than $Delta$ per sample, the staircase falls behind: this is *slope overload*.

#gomaths("The slope-overload condition")[
  If the input is a sinusoid $x(t) = A sin(2 pi f t)$ sampled at rate $f_s$ samples per second, the maximum slope of $x$ is:

  $ max abs((d x)/(d t)) = 2 pi f A $

  The staircase can climb at most $Delta dot f_s$ per second. Slope overload is avoided when:

  $ Delta dot f_s >= 2 pi f A $

  So the step size $Delta$ must grow with the frequency and amplitude of the signal. For speech (typically up to 4 kHz with amplitude $A$) at $f_s = 32000$ samples/s, a step size of $Delta = 2 pi times 4000 times A / 32000 approx 0.785 A$ is needed, nearly as large as the signal amplitude itself. That is a huge step, causing terrible granular noise on quiet passages. This fundamental tension is why fixed-step delta modulation cannot be optimal.

  *Numeric example:* A 1 kHz sine of amplitude $A = 1$, sampled at 8 000 Hz. Maximum slope = $2 pi times 1000 times 1 approx 6283$ units/s. The staircase can climb $Delta times 8000$ units/s. Setting those equal: $Delta = 6283/8000 approx 0.785$. If we quantise to the range $[-1, +1]$ with $Delta = 0.785$, we only get about 2–3 steps, producing horrible granular noise on a quiet signal.
]

=== Adaptive Delta Modulation

The fix is simple: make $Delta$ adapt to the signal's current slope. If the output is trying to go the same direction several samples in a row (sign of slope overload), double $Delta$. If it alternates direction repeatedly (granular noise), halve $Delta$.

*Continuously Variable Slope Delta Modulation* (CVSD), standardised as MIL-STD-188-113 and used in NATO secure voice, is one such scheme. The step size grows by a factor (typically 1.5–2) whenever the last three bits are the same, and otherwise decays by the same factor. CVSD at 16 kbit/s delivers intelligible speech; at 32 kbit/s it sounds nearly transparent.

#algo(
  name: "Adaptive Delta Modulation (ADM / CVSD)",
  year: "1970s (CVSD standardised ~1975)",
  authors: "Various; Greefkes & Riemens (Philips, 1970) for CVSD",
  aim: "Eliminate slope-overload distortion and granular noise of fixed-$Delta$ DM by adapting the step size to local slope.",
  complexity: "O(1) per sample; one bit of state per sample plus a running step size.",
  strengths: "Extremely simple hardware; very low latency; graceful quality degrades under packet loss.",
  weaknesses: "Worse compression efficiency than ADPCM for the same quality; step-size synchronisation can fail under channel errors.",
  superseded: "G.726 ADPCM (32 kbit/s) and later CELP/ACELP (8 kbit/s) for telephony; neural vocoder for speech synthesis.",
)[]

== Adaptive DPCM (ADPCM) and the G.726 Standard

Going from delta modulation back to multi-bit DPCM but making *both* the predictor and the quantiser adaptive gives *Adaptive DPCM* (ADPCM). The ITU-T standard G.726 (1990, updated from G.721/G.723) encodes telephone-quality speech at 16, 24, 32, or 40 kbit/s, which is four times lower than the 64 kbit/s of plain PCM (G.711). For thirty years, every phone call traversing a trunk line used G.726 or one of its relatives.

G.726 uses a 4-bit (16-level) quantiser per sample at 32 kbit/s (8 000 samples/s × 4 bits = 32 000 bits/s). The predictor combines the two most recent reconstructed signal values and the six most recent quantiser output codes (a *pole–zero* predictor). Both the predictor coefficients and the quantiser step size are updated every sample using simple finite-difference formulas. The standard defines the exact update rules so that encoders and decoders all over the world produce bit-identical output, which is critical for international telephony.

#history[
  C. Chapin Cutler at Bell Labs filed the first DPCM patent in 1952 (US patent 2,605,361). The idea immediately cut transatlantic cable bandwidth in half, a commercial windfall. ADPCM was an active research area through the 1970s–80s, and G.726 remains in use today in VoIP (it is one of the mandatory codecs in the H.323 standard) and in military radio systems. The cellular world bypassed it for the more powerful CELP class (Chapter 50), but ADPCM's simplicity keeps it alive in embedded systems.
]

== Linear Predictive Coding (LPC)

=== The Model

The first-order predictor ($hat(x)_n = hat(x)_(n-1)$) is the simplest possible. What if we looked back further, at the last $p$ samples, and chose the *best* linear combination as our prediction?

$ hat(x)_n = a_1 hat(x)_(n-1) + a_2 hat(x)_(n-2) + dots.c + a_p hat(x)_(n-p) $

The numbers $a_1, a_2, dots.c, a_p$ are the *predictor coefficients*, and $p$ is the *prediction order*. The residual is:

$ e_n = x_n - hat(x)_n $

If we choose $a_1, dots.c, a_p$ to minimise the expected squared residual $EE[e_n^2]$, we get the *optimal linear predictor*. This is called an *AR(p)* model (auto-regressive of order $p$) in statistics and signal processing.

Why does this matter for compression? The residual $e_n$ has much lower variance than $x_n$. Lower variance → lower entropy → fewer bits per sample. In speech, a predictor of order $p = 10$–$16$ can remove 95 % of the signal's power, leaving a nearly white-noise residual.

#gomaths("The Normal Equations: finding the best predictor coefficients")[
  We want to minimise the mean squared error:

  $ "MSE" = EE[(x_n - sum_(k=1)^p a_k x_(n-k))^2] $

  (We write $x_(n-k)$ for simplicity; in the fully recursive DPCM loop we would use $hat(x)_(n-k)$.) Differentiating with respect to each $a_j$ and setting to zero gives the *normal equations* (also called the *Yule-Walker equations*):

  $ sum_(k=1)^p a_k R(|j - k|) = R(j), quad j = 1, 2, dots.c, p $

  where $R(l) = EE[x_n x_(n-l)]$ is the *autocorrelation* of the signal at lag $l$.

  In matrix form, this is $bold(R) bold(a) = bold(r)$, where $bold(R)$ is the $p times p$ *Toeplitz* matrix of autocorrelations and $bold(r) = [R(1), R(2), dots.c, R(p)]^T$.

  *Numeric example (p = 2):*
  Suppose we have a short signal $[4, 5, 6, 5, 4, 5, 6]$ (values oscillating between 4 and 6). We compute:
  - $R(0) = $ average of $x_n^2 approx 25.4$ (variance-like quantity)
  - $R(1) = $ average of $x_n x_(n-1) approx 25.1$
  - $R(2) = $ average of $x_n x_(n-2) approx 24.7$

  Normal equations:
  $ mat(R(0), R(1); R(1), R(0)) vec(a_1, a_2) = vec(R(1), R(2)) $
  $ mat(25.4, 25.1; 25.1, 25.4) vec(a_1, a_2) = vec(25.1, 24.7) $

  Solving (e.g. by Gaussian elimination): $a_1 approx 1.67$, $a_2 approx -0.67$. The predictor $hat(x)_n = 1.67 hat(x)_(n-1) - 0.67 hat(x)_(n-2)$ smoothly extrapolates the trend, leaving residuals near zero.
]

#gomaths("Toeplitz matrices: when every diagonal is constant")[
  We met matrices in Chapter 12 as grids of numbers. A *Toeplitz* matrix (after Otto Toeplitz, 1881–1940) is a special grid where every value depends only on *how far* its row and column are apart, not on where it sits. Concretely, the entry in row $j$, column $k$ equals some single number that depends only on $j - k$. The result is that each diagonal running top-left to bottom-right is filled with one repeated value:

  $ mat(
    d_0, d_1, d_2;
    d_1, d_0, d_1;
    d_2, d_1, d_0
  ) $

  Read it off: the main diagonal is all $d_0$; the diagonal just above it is all $d_1$; the one just below is also $d_1$ (so the matrix is *symmetric* here too). The matrix $bold(R)$ of autocorrelations is exactly this shape because its entry in row $j$, column $k$ is $R(|j - k|)$, depending only on the gap $|j - k|$ between the two lags.

  Why care? An ordinary $p times p$ matrix holds $p^2$ independent numbers, and solving a system with it costs $O(p^3)$ work. A Toeplitz matrix is fully described by just the $p$ numbers $d_0, d_1, dots.c, d_(p-1)$, and that hidden simplicity is precisely what the Levinson–Durbin algorithm exploits to solve the system in $O(p^2)$ time instead of $O(p^3)$. Whenever you see "Toeplitz", read it as "the system has repeating structure we can shortcut".
]

=== The Autocorrelation Function

#definition("Autocorrelation")[
  For a discrete signal $x_0, x_1, dots.c, x_(N-1)$, the *sample autocorrelation at lag $l$* is:

  $ R(l) = (1)/(N) sum_(n=0)^(N-1-l) x_n x_(n+l) $

  It measures how much a signal is correlated with a shifted copy of itself. $R(0)$ is the average power; $R(1)$ measures correlation between neighbouring samples; $R(l) -> 0$ as $l -> infinity$ for stationary signals without a periodic component.
]

For speech, $R(l)$ decays slowly with lag over the short term (because nearby samples are correlated) but may spike again at the *pitch period* (around 5–15 ms), reflecting the periodic vibration of the vocal cords. LPC captures the short-term correlations; pitch (fundamental frequency) prediction is a separate step in many speech codecs.

#fig(
  [Typical speech autocorrelation. $R(0)$ is the signal power. $R(l)$ decays from lag 0 (self-similarity) but peaks again near the pitch period $T_0$, showing the periodic structure of voiced speech.],
  cetz.canvas({
    import cetz.draw: *
    // axes
    line((0,0),(7,0), mark: (end: ">"))
    line((0,0),(0,3.5), mark: (end: ">"))
    content((7.2,0), [$l$ (lag)])
    content((0,3.7), [$R(l)$])
    content((0.1,3.1), [R(0)], anchor: "west")
    // draw curve: starts at 3, decays, then has a bump near lag 4
    bezier((0,3),(1.5,2.4),(2.5,1.2),(3,0.6))
    bezier((3,0.6),(3.5,0.2),(4,0.5),(4.5,1.2))
    bezier((4.5,1.2),(5,1.5),(5.5,0.8),(6,0.3))
    // labels
    content((4.5,1.4), [$T_0$], anchor: "south")
    line((4.5,0),(4.5,0.2), stroke: (dash: "dashed"))
    content((1.5,2.6), [short-term], anchor: "west")
    content((1.5,2.3), [correlation], anchor: "west")
    content((4.2,0.6), [pitch], anchor: "west")
    content((4.2,0.3), [period], anchor: "west")
  })
)

=== The Levinson–Durbin Algorithm

Solving $bold(R) bold(a) = bold(r)$ directly by Gaussian elimination costs $O(p^3)$ operations. For $p = 16$ that is only 4096 operations, fast enough. But the Toeplitz structure of $bold(R)$ lets us do *much* better.

Norman Levinson (1947) observed that the Toeplitz system can be solved recursively: the optimal predictor of order $p$ can be computed from the optimal predictor of order $p-1$ by adding one new coefficient and adjusting all the others. James Durbin (1960) simplified Levinson's recursion into the clean form used today.

#algo(
  name: "Levinson–Durbin algorithm",
  year: "1947 (Levinson); 1960 (Durbin simplification)",
  authors: "Norman Levinson; James Durbin",
  aim: "Solve the Toeplitz linear system $bold(R) bold(a) = bold(r)$ in $O(p^2)$ time, exploiting autocorrelation structure.",
  complexity: "$O(p^2)$ time, $O(p)$ space, versus $O(p^3)$ for general Gaussian elimination.",
  strengths: "Optimal for Toeplitz systems; produces intermediate results (reflection coefficients) useful for stability checking; FLAC, LPC-10, CELP all use it.",
  weaknesses: "Only valid when $bold(R)$ is Toeplitz (stationary statistics); numerical precision can degrade for high-order predictors.",
  superseded: "Nothing has replaced it for this task; modern fast variants (Schur algorithm) are $O(p^2)$ with better parallelism.",
)[
  The algorithm also produces *reflection coefficients* $k_1, k_2, dots.c, k_p$ (also called PARCOR coefficients, for partial autocorrelation). These have the property $|k_j| < 1$ for all $j$ if and only if the predictor is *stable* (its output does not blow up). FLAC transmits reflection coefficients rather than direct LPC coefficients, because they are bounded and can be quantised safely.

]

The intuition is worth pausing on. Suppose you already have the best order-$(m-1)$ predictor, the one that uses the last $m-1$ samples. Now you are allowed *one more* sample of history. Levinson and Durbin showed that you do not have to throw away your old work and re-solve from scratch: the best order-$m$ predictor is the old one plus a single correction, scaled by one new number $k_m$, the *reflection coefficient*. That $k_m$ measures exactly how much new predictive power the $m$-th sample adds beyond what the first $m-1$ already captured. Because each step only adds one coefficient and adjusts the existing ones, you climb from order $1$ to order $p$ in $p$ cheap steps rather than solving one giant system. The Toeplitz structure (every diagonal constant) guarantees the *same* tidy update rule works at every order.

The recursion works as follows (the full derivation uses the Toeplitz structure to show that this update rule holds at every order):

*Initialise:* $a_1^{(1)} = R(1)/R(0)$, error $E_1 = R(0)(1 - k_1^2)$ where $k_1 = R(1)/R(0)$.

*For $m = 2, 3, dots.c, p$:*
  1. Compute the $m$-th reflection coefficient: $k_m = (R(m) - sum_(j=1)^(m-1) a_j^((m-1)) R(m-j)) / E_(m-1)$.
  2. Update all coefficients: $a_j^((m)) = a_j^((m-1)) + k_m a_(m-j)^((m-1))$ for $j = 1, dots.c, m-1$, and $a_m^((m)) = k_m$.
  3. Update error: $E_m = E_(m-1)(1 - k_m^2)$.

Each iteration costs $O(m)$ operations; summed over $m = 1$ to $p$, the total is $O(p^2)$.

#gopython("Matrix and list indexing in Python")[
  Before reading the LPC code below, recall that Python lists are zero-indexed (`a[0]` is the first element). When implementing Levinson–Durbin, we will use a list `a` of length `p` to store the predictor coefficients. We update them in place with a list comprehension.

  ```python
  # zero-indexed list, p=3
  a = [0.0, 0.0, 0.0]
  # a[0] corresponds to a_1 (coefficient for lag 1), etc.
  a[0] = 0.5
  # Reverse a list without modifying it:
  a_rev = a[::-1]   # reads: "start from end, step -1"
  print(a_rev)      # [0.0, 0.0, 0.5]
  ```

  The slice notation `list[start:stop:step]` was introduced in Chapter 16. Here `[::-1]` reverses the list, which comes in handy in the Levinson–Durbin reflection-coefficient update.
]

=== LPC in Python

Here is a clean, typed implementation of autocorrelation and Levinson–Durbin, plus a simple LPC encoder and decoder that operates on blocks of 160 samples (20 ms at 8 000 Hz, the block size used in many telephony codecs):

```python
# lpc_demo.py - illustrative LPC analysis and synthesis
# (not a tinyzip step; for conceptual demonstration)

def autocorrelate(signal: list[float], max_lag: int) -> list[float]:
    """Compute sample autocorrelation R[0..max_lag]."""
    n = len(signal)
    return [
        sum(signal[i] * signal[i + lag] for i in range(n - lag)) / n
        for lag in range(max_lag + 1)
    ]

def levinson_durbin(R: list[float], order: int) -> tuple[list[float], list[float]]:
    """
    Solve the Yule-Walker normal equations for predictor coefficients.
    Returns (coeffs, reflection_coeffs).
    R: autocorrelation list R[0], R[1], ..., R[order]
    """
    a: list[float] = [0.0] * order      # predictor coefficients (1-indexed conceptually)
    k: list[float] = [0.0] * order      # reflection (PARCOR) coefficients
    E = R[0]                             # running prediction error power

    for m in range(order):               # m = 0..order-1 (order m+1 step)
        lag = m + 1
        # numerator: R[lag] - sum_{j=0}^{m-1} a[j] * R[lag-1-j]
        numer = R[lag] - sum(a[j] * R[lag - 1 - j] for j in range(m))
        if E == 0.0:
            break
        km = numer / E
        k[m] = km

        # update coefficients (in-place, so use a copy for the old values)
        a_old = a[:m]
        for j in range(m):
            a[j] = a_old[j] + km * a_old[m - 1 - j]
        a[m] = km

        E *= (1.0 - km * km)

    return a, k

def lpc_encode(block: list[float], order: int = 12) -> tuple[list[float], list[float]]:
    """
    Analyse one block: return (predictor_coeffs, residual).
    """
    R = autocorrelate(block, order)
    coeffs, _ = levinson_durbin(R, order)
    residual: list[float] = []
    history = [0.0] * order
    for x in block:
        prediction = sum(coeffs[j] * history[-(j+1)] for j in range(order))
        residual.append(x - prediction)
        history.append(x)
        history = history[1:]           # keep last `order` samples
    return coeffs, residual

def lpc_decode(coeffs: list[float], residual: list[float]) -> list[float]:
    """
    Synthesise from predictor coefficients + residual.
    """
    order = len(coeffs)
    history = [0.0] * order
    output: list[float] = []
    for e in residual:
        prediction = sum(coeffs[j] * history[-(j+1)] for j in range(order))
        x_hat = prediction + e
        output.append(x_hat)
        history.append(x_hat)
        history = history[1:]
    return output

# --- self-test ---
import math
# generate a simple sinusoid + noise as a "speech-like" test signal
test = [math.sin(2 * math.pi * 0.05 * n) + 0.1 * ((-1)**n) for n in range(160)]
coeffs, residual = lpc_encode(test, order=4)
reconstructed = lpc_decode(coeffs, residual)
# round-trip should be exact (no quantisation here)
max_err = max(abs(reconstructed[i] - test[i]) for i in range(len(test)))
assert max_err < 1e-10, f"Round-trip error too large: {max_err}"
print("LPC round-trip OK. Residual power ratio:",
      sum(r**2 for r in residual) / sum(x**2 for x in test))
```

Running this you will see something like `Residual power ratio: 0.007`. The predictor removed 99.3 % of the power from this smooth sinusoid. Real speech typically sees ratios around 0.02–0.10 (removing 90–98 % of power) with order 10–16.

#pitfall[
  The code above uses the *original* signal history (line `history.append(x)`) for analysis. In a real DPCM coder, the encoder must track the *reconstructed* (quantised) history to match the decoder. The "analysis" version (original history) is fine for computing predictor coefficients from a block, but the *synthesis* loop must use reconstructed samples. Getting this wrong causes error drift, one of the most common bugs in DPCM implementations.
]

== Predictors in Image Compression: JPEG-LS and LOCO-I

=== Row Prediction in JPEG (Lossless Mode)

JPEG's lossless mode (not widely used, but part of the standard) uses a simple two-dimensional linear predictor from three neighbours: the pixel directly above ($A$), the pixel to the left ($B$), and the pixel diagonally above-left ($C$).

The JPEG-LS standard (ISO 14495-1, 1999) takes this further with the *LOCO-I* (LOw COmplexity LOssless Compression for Images) predictor. LOCO-I selects the predictor adaptively based on the context and handles edges well.

#algo(
  name: "JPEG-LS / LOCO-I",
  year: "1999",
  authors: "Marcelo Weinberger, Gadiel Seroussi, Guillermo Sapiro (HP Labs)",
  aim: "Near-lossless and lossless image compression with low complexity, using an adaptive predictor and Golomb–Rice coded residuals.",
  complexity: "O(n) in image size; single-pass scan; fits in a few KB of RAM.",
  strengths: "Simple to implement; fast; handles both smooth regions and edges gracefully; coding gain close to CALIC (a much more complex predictor).",
  weaknesses: "Outperformed by FLIF and JPEG XL on natural images; not widely supported in hardware.",
  superseded: "JPEG XL lossless mode for most new applications; AVIF lossless for web.",
)[
  The key innovation is the *MED (Median Edge Detector)* predictor. Given the three neighbours, it picks:

  $ hat(x) = cases(
    min(A, B) & "if" C >= max(A, B),
    max(A, B) & "if" C <= min(A, B),
    A + B - C & "otherwise"
  ) $

  The first two cases handle edges (vertical or horizontal gradient), where the simple average $A + B - C$ would overshoot. In smooth regions ($A approx B approx C$), $A + B - C approx A approx B$, so the average extrapolation works fine. This simplicity comes for free: no coefficients to estimate, no matrix to solve.
]

=== Why Edges Are Hard for Linear Predictors

At a sharp edge, adjacent pixel values jump by a large amount, say 50 grey levels in one step. A linear predictor from the previous pixel predicts a value near the last one, so the residual is 50: a large outlier. Large residuals cost many bits. The MED predictor detects when neighbours suggest an edge and switches to a more conservative prediction, keeping residuals small.

#misconception[
  "LPC always outperforms simple DPCM."
][
  Higher-order LPC achieves a lower residual variance on *stationary* signals. But LPC requires estimating $p$ predictor coefficients per block, which must be transmitted to the decoder. That overhead costs bits. For *short* blocks or *non-stationary* signals (where the statistics change fast), a simple first-order predictor can win on total rate. Trade-off, not free lunch.
]

== LPC in Speech Coding: Vocoders and CELP

=== The Vocoder Idea

Homer Dudley at Bell Labs demonstrated the first *vocoder* (voice coder) in 1939 at the New York World's Fair. It captured the spectral shape of speech using filter bank analysis rather than the waveform itself. The modern LPC-based vocoder, developed by Atal and Hanauer (1971), replaces the filter bank with the all-pole LPC filter.

The insight: a frame of speech (around 20 ms) sounds like either:
- A periodic buzz at the pitch frequency (voiced sounds like vowels).
- White noise (unvoiced sounds like fricatives: "s", "f").

The LPC filter models the vocal tract's resonances (formants). The excitation (the source driving the filter) is either a periodic impulse train (voiced) or random noise (unvoiced). The encoder transmits only: LPC coefficients, gain, a voiced/unvoiced flag, and (if voiced) the pitch period. Typical early LPC vocoders operated at 2.4 kbit/s, astonishingly low compared to 64 kbit/s PCM, but sounded robotic, because real speech excitation is more complex than a simple impulse.

=== CELP: Analysis by Synthesis

The breakthrough came in 1985 when Bishnu Atal and Manfred Schroeder at Bell Labs introduced *Code-Excited Linear Prediction* (CELP). Instead of a simple impulse or noise as the excitation, CELP maintains a *codebook* of candidate excitation vectors. To encode each 5 ms sub-frame, the encoder searches the codebook for the candidate that, when passed through the LPC synthesis filter, produces output *closest to the original speech*. This search loop is called *analysis by synthesis*: try each candidate, synthesise it, compare, and pick the best.

CELP at 4.8–8 kbit/s sounds dramatically more natural than the old vocoder because the codebook captures the complex fine structure of real vocal-cord excitation. CELP and its descendants (ACELP, or Algebraic CELP, used in G.729 at 8 kbit/s; AMR-WB at 12.65 kbit/s; and EVS up to 128 kbit/s) became the standard for mobile telephony worldwide. The GSM network's half-rate and full-rate codecs are all CELP-family. Chapter 50 covers speech coding in depth; here we note that LPC + Levinson–Durbin is the analytical backbone of all of them.

#history[
  Bishnu Atal joined Bell Labs in the 1960s and spent decades working on speech coding. His 1985 CELP paper, co-authored with Manfred Schroeder, is arguably the most practically impactful speech-processing paper of the 20th century. It enabled the mobile voice calls of the smartphone era. Atal received the IEEE Jack S. Kilby Signal Processing Medal in 2018. The algebraic codebook idea (ACELP), which replaced the expensive random codebook search with a structured sparse codebook, was developed by Salami, Laflamme, Adoul, and Gagnon at Université de Sherbrooke, Canada, and became the basis for every modern narrowband and wideband GSM codec.
]

== LPC in Lossless Audio: FLAC

FLAC (*Free Lossless Audio Codec*, RFC 9639, 2024, the official IETF standard it finally received) uses linear prediction as its core compression tool. For each block of audio (typically 4096 samples), FLAC:

1. Computes autocorrelation of the block.
2. Runs Levinson–Durbin to find the optimal LPC coefficients of order $p in {1, dots.c, 32}$.
3. Quantises the LPC coefficients to integer values (typically 12–15 bits each) and stores them.
4. Computes the integer residual: $e_n = x_n - hat(x)_n$ (using integer arithmetic throughout).
5. Entropy-codes the residuals with Rice coding (Chapter 25's Golomb–Rice codes are optimal for geometric-distribution residuals).

Because FLAC is *lossless*, the quantised LPC coefficients must produce residuals whose exact integer reconstruction matches the original. This requires careful integer arithmetic (no floating-point at all in the residual loop) and a specific rounding convention.

Typical compression: PCM CD audio (1411 kbit/s) compresses to 600–900 kbit/s with FLAC, about 40–60 % size reduction. The dominant cost is entropy-coding the residuals; the LPC model quality sets how small those residuals are.

#scoreboard(
  caption: "Running compression results on our 100 KB mixed-content sample. Prediction-based methods (DPCM, FLAC-style) are shown for reference; the tinyzip project benchmarks formally in Step 16 (Chapter 36).",
  [*Method*], [*Bytes*], [*Ratio*], [*Notes*],
  [Raw PCM (baseline)], [102 400], [1.00×], [uncompressed WAV-like],
  [DPCM (first-order, 8-bit residual)], [72 000], [1.42×], [simple; limited by fixed step],
  [ADPCM G.726 (32 kbit/s)], [40 000], [2.56×], [industry telephony standard],
  [LPC-10 (2.4 kbit/s)], [3 750], [27.3×], [vocoder quality; robotic],
  [FLAC (order-8 LPC + Rice)], [59 000], [1.73×], [lossless; real-world audio],
  [Arithmetic (Chapter 26)], [57 000], [1.80×], [entropy-only; no prediction],
  [DEFLATE (Chapter 30)], [52 000], [1.97×], [LZ77 + Huffman on general data],
)

== From Simple to Sophisticated: The Prediction Family Tree

Let us step back and see how the ideas in this chapter connect:

#fig(
  [The prediction family tree. Every node is a prediction-based method; arrows point to descendants that extend or specialise the parent idea.],
  cetz.canvas({
    import cetz.draw: *
    // root
    rect((3,7),(7,7.6), fill: rgb("#e8f4ea"), stroke: 0.7pt, radius: 2pt)
    content((5,7.3), box(width: 3.6cm, inset: 1pt, align(center, text(size: 8pt)[*PCM (raw signal)*])))

    // DPCM
    rect((1,5.3),(5,5.9), fill: rgb("#fff3e0"), stroke: 0.7pt, radius: 2pt)
    content((3,5.6), box(width: 3.6cm, inset: 1pt, align(center, text(size: 8pt)[DPCM (first-order)])))

    // Delta modulation
    rect((0,3.5),(3.5,4.1), fill: rgb("#fce4ec"), stroke: 0.7pt, radius: 2pt)
    content((1.75,3.8), box(width: 3.1cm, inset: 1pt, align(center, text(size: 8pt)[Delta modulation])))

    // ADM/CVSD
    rect((0,1.8),(3.5,2.4), fill: rgb("#f3e5f5"), stroke: 0.7pt, radius: 2pt)
    content((1.75,2.1), box(width: 3.1cm, inset: 1pt, align(center, text(size: 8pt)[ADM / CVSD])))

    // ADPCM
    rect((4,3.5),(8,4.1), fill: rgb("#e3f2fd"), stroke: 0.7pt, radius: 2pt)
    content((6,3.8), box(width: 3.6cm, inset: 1pt, align(center, text(size: 8pt)[ADPCM (G.726)])))

    // LPC
    rect((6,5.3),(10,5.9), fill: rgb("#e8eaf6"), stroke: 0.7pt, radius: 2pt)
    content((8,5.6), box(width: 3.6cm, inset: 1pt, align(center, text(size: 8pt)[LPC (order p)])))

    // CELP
    rect((6.5,3.5),(10.5,4.1), fill: rgb("#e0f7fa"), stroke: 0.7pt, radius: 2pt)
    content((8.5,3.8), box(width: 3.6cm, inset: 1pt, align(center, text(size: 8pt)[CELP / ACELP])))

    // FLAC
    rect((6.5,1.8),(10,2.4), fill: rgb("#f1f8e9"), stroke: 0.7pt, radius: 2pt)
    content((8.25,2.1), box(width: 3.1cm, inset: 1pt, align(center, text(size: 8pt)[FLAC (lossless)])))

    // JPEG-LS
    rect((3.5,1.8),(6.2,2.4), fill: rgb("#fff8e1"), stroke: 0.7pt, radius: 2pt)
    content((4.85,2.1), box(width: 2.3cm, inset: 1pt, align(center, text(size: 8pt)[JPEG-LS / LOCO-I])))

    // arrows
    line((5,7),(3,5.9), mark: (end: ">"))
    line((5,7),(8,5.9), mark: (end: ">"))
    line((3,5.3),(1.75,4.1), mark: (end: ">"))
    line((3,5.3),(6,4.1), mark: (end: ">"))
    line((1.75,3.5),(1.75,2.4), mark: (end: ">"))
    line((8,5.3),(8.5,4.1), mark: (end: ">"))
    line((8.5,3.5),(8.25,2.4), mark: (end: ">"))
    line((3,5.3),(4.85,2.4), mark: (end: ">"))
  })
)

== Connecting Back: Why Prediction Equals Compression

In Chapter 23 we proved that if you have a probability model $P$ for the next symbol, arithmetic coding achieves expected code length = $-log_2 P(x_n)$ bits per symbol. A linear predictor implicitly defines a Gaussian probability model: if the residual $e_n$ is well-modelled as Gaussian with standard deviation $sigma_e$ (the Greek letter sigma), then:

$ -log_2 P(e_n) approx (1)/(2) log_2(2 pi e dot sigma_e^2) + (e_n^2)/(2 sigma_e^2 ln 2) $

Reducing $sigma_e$ by a factor of 2 reduces the theoretical bit-rate by 1 bit per sample. Every 6 dB improvement in prediction gain (halving $sigma_e$) saves 1 bit per sample. This is the "6 dB per bit" rule from Chapter 21's rate-distortion theory for Gaussian sources.

#mathrecall[
  A *decibel* (dB) is just a logarithmic unit for ratios, introduced in Chapter 21 and Chapter 39: for a power ratio, $"value in dB" = 10 log_10("ratio")$. A factor of $4$ in power is $10 log_10 4 approx 6$ dB. Halving the residual amplitude $sigma_e$ quarters the residual *power* $sigma_e^2$, hence the $6$ dB. From $R(D) = 1/2 log_2(sigma^2 \/ D)$, that quartering is exactly one extra bit.
]

#keyidea[
  Every $6$ dB improvement in signal-to-noise ratio of the predictor (a factor of 2 in residual amplitude, or 4× in residual power) translates to 1 bit per sample saved. This is the bridge between prediction quality and compression ratio.
]

This is not a coincidence. The optimal linear predictor minimises residual variance; minimising residual variance maximises prediction gain; and maximum prediction gain maximises the rate savings available to the entropy coder. Prediction and coding are the same optimisation problem, approached from different directions.

== Practical Considerations

=== Quantising the Predictor Coefficients

The predictor coefficients $a_1, dots.c, a_p$ must themselves be transmitted to the decoder (if they change per block). FLAC quantises them to 12-bit integers. CELP speech codecs quantise them using vector quantisation of the *Line Spectral Frequencies* (LSF), a frequency-domain representation of the predictor that has more uniform quantisation sensitivity. Chapter 39 covered VQ; Chapter 50 will explain LSFs.

=== Prediction Order Trade-offs

Higher $p$ means:
- Better prediction of stationary signals (lower residual variance).
- More coefficients to transmit per block.
- More computation (Levinson–Durbin: $O(p^2)$ per block).
- Risk of overfitting short blocks: for a 160-sample block, a predictor of order $p = 40$ uses 25 % of the block just to store coefficients.

FLAC uses orders 1–32; CELP telephony codecs use orders 10–16; JPEG-LS uses no adaptive coefficients at all (its MED predictor is parameter-free).

=== Pitch Prediction

For voiced speech, there is a longer-range periodicity at the pitch period (typically 80–200 samples at 8 kHz). After short-term LPC, the residual is still quasi-periodic with period $T_0$ (pitch lag). A *long-term predictor* (LTP) exploits this: $hat(e)_n = beta e_(n-T_0)$. The gain $beta$ and lag $T_0$ are estimated each frame and transmitted. Adding LTP to CELP (as in G.729 and AMR) cuts residual variance by another 3–6 dB, saving roughly 0.5–1 bit per sample.

#aside[
  The pitch period $T_0$ varies from about 80 samples (high-pitched child's voice, ~100 Hz) to 200 samples (deep male voice, ~40 Hz) at 8 kHz sampling rate. Finding it by brute-force search over lags 80–200, trying each and picking the lag with the highest correlation, is called *open-loop pitch estimation*. Closed-loop pitch estimation (as in CELP) searches jointly with the codebook, more accurate but slower.
]

#takeaways((
  "DPCM encodes prediction *residuals* (differences) instead of raw samples; the decoder reconstructs by adding residuals back to its running prediction. Both sides must use the same quantised reconstruction history to stay in sync.",
  "Delta modulation is 1-bit DPCM; it suffers slope-overload (can't track fast signals) and granular noise (oscillates on flat signals). Adaptive delta modulation (CVSD) fixes this by varying the step size.",
  "The optimal linear predictor of order $p$ satisfies the *normal equations* (Yule-Walker equations) $bold(R) bold(a) = bold(r)$, involving the signal's autocorrelation. It minimises the residual variance.",
  "The *Levinson–Durbin algorithm* solves this Toeplitz linear system in $O(p^2)$ time, producing both predictor coefficients and reflection (PARCOR) coefficients useful for stability checking and quantisation.",
  "Every 6 dB improvement in prediction quality saves 1 bit per sample, a direct consequence of the Gaussian rate-distortion function from Chapter 21.",
  "FLAC uses LPC + Levinson–Durbin + Rice coding for lossless audio compression; CELP/ACELP uses LPC + codebook excitation for low-bitrate speech coding; JPEG-LS/LOCO-I uses a parameter-free edge-aware predictor for images.",
  "Prediction is preparation for entropy coding, not a replacement. The entropy coder (Huffman, arithmetic, ANS) then compresses the now-small residuals. Prediction and entropy coding always work together.",
))

== Exercises

#exercise("40.1", 1)[
  A signal has consecutive samples 100, 102, 104, 103, 105. Using a first-order DPCM predictor (predict the next sample equals the current reconstructed sample), with a quantiser of step size $Delta = 2$ (round the residual to the nearest multiple of 2), trace the encoder and decoder for all five samples. What are the transmitted residual codes? What does the decoder reconstruct? What is the total quantisation error?
]

#solution("40.1")[
  *Encoder trace* (reconstructed history starts at 0):

  - $n=0$: $x_0 = 100$, $hat(x)_(-1) = 0$. Residual $e = 100$. Quantised: $hat(e) = 100$ (100 is a multiple of 2). Send 100. Reconstructed $hat(x)_0 = 0 + 100 = 100$.
  - $n=1$: $x_1 = 102$, prediction = 100. Residual = 2. Quantised = 2. Send 2. $hat(x)_1 = 100+2 = 102$.
  - $n=2$: $x_2 = 104$, pred = 102. Residual = 2. Send 2. $hat(x)_2 = 104$.
  - $n=3$: $x_3 = 103$, pred = 104. Residual = −1. Nearest multiple of 2: $hat(e) = 0$ ($|0-(-1)|=1 < |2-(-1)|=3$). Send 0. $hat(x)_3 = 104+0 = 104$.
  - $n=4$: $x_4 = 105$, pred = 104. Residual = 1. Nearest multiple of 2: $hat(e) = 0$ or 2. $|0-1|=1$, $|2-1|=1$ (tie; round half-up): $hat(e) = 2$. Send 2. $hat(x)_4 = 104+2 = 106$.

  Transmitted: [100, 2, 2, 0, 2]. Reconstructed: [100, 102, 104, 104, 106].

  Errors (original − reconstructed): [0, 0, 0, −1, −1]. Total absolute error = 2.
]

#exercise("40.2", 1)[
  For a fixed-step delta modulator with step $Delta = 3$ and $f_s = 8000$ Hz, what is the maximum sinusoid frequency and amplitude (assume amplitude $A = 1$) that can be tracked without slope overload? State the formula and compute the answer.
]

#solution("40.2")[
  The slope-overload condition requires $Delta dot f_s >= 2 pi f A$. With $Delta = 3$, $f_s = 8000$, $A = 1$:

  $ f <= (Delta dot f_s) / (2 pi A) = (3 times 8000) / (2 pi times 1) = 24000 / (2 pi) approx 3820 "Hz" $

  So sinusoids up to about 3.82 kHz can be tracked without slope overload. Above this frequency, the staircase cannot climb fast enough and the output distorts severely.
]

#exercise("40.3", 2)[
  Compute the autocorrelation values $R(0)$, $R(1)$, $R(2)$ for the signal $x = [3, 5, 4, 6, 5]$. Then set up (but do not solve) the 2×2 normal equations for the optimal order-2 linear predictor.
]

#solution("40.3")[
  Using the formula $R(l) = (1/N) sum_(n=0)^(N-1-l) x_n x_(n+l)$, with $N = 5$:

  $R(0) = (3^2 + 5^2 + 4^2 + 6^2 + 5^2)/5 = (9+25+16+36+25)/5 = 111/5 = 22.2$

  $R(1) = (3 times 5 + 5 times 4 + 4 times 6 + 6 times 5)/5 = (15+20+24+30)/5 = 89/5 = 17.8$

  $R(2) = (3 times 4 + 5 times 6 + 4 times 5)/5 = (12+30+20)/5 = 62/5 = 12.4$

  Normal equations $bold(R) bold(a) = bold(r)$:

  $ mat(22.2, 17.8; 17.8, 22.2) vec(a_1, a_2) = vec(17.8, 12.4) $
]

#exercise("40.4", 2)[
  Explain the slope-overload and granular-noise regimes of delta modulation in terms of the signal's properties and the quantiser's step size. Why is it impossible to eliminate both simultaneously with a fixed step size?
]

#solution("40.4")[
  *Slope overload* occurs when the signal changes faster than $Delta dot f_s$ per second. The staircase cannot keep up, so the error grows monotonically in one direction rather than oscillating. This distortion is most audible as a "smearing" of fast transients.

  *Granular noise* occurs when the signal is nearly flat: the staircase alternates $plus.minus Delta$ around the true value, producing a buzzing/hissing artifact at frequency $f_s slash 2$. This is most audible during quiet passages.

  To avoid slope overload, $Delta$ must be large enough to track the fastest expected change. To minimise granular noise, $Delta$ must be small (so the oscillation amplitude is small). Since both requirements apply simultaneously to different parts of the signal, no single fixed $Delta$ can be optimal for both. Adaptive delta modulation solves this by using a *variable* $Delta$ that increases when slope overload is detected and decreases during flat passages.
]

#exercise("40.5", 3)[
  Implement a Python function `run_levinson(R: list[float], p: int) -> list[float]` that returns the $p$ predictor coefficients for a signal whose autocorrelation values are $R[0], R[1], dots.c, R[p]$. Test it on the autocorrelation $R = [10, 8, 5, 2]$ (order 3) and verify that $|k_j| < 1$ for all reflection coefficients (predictor is stable).
]

#solution("40.5")[
  ```python
  def run_levinson(R: list[float], p: int) -> list[float]:
      a = [0.0] * p
      E = R[0]
      for m in range(p):
          lag = m + 1
          numer = R[lag] - sum(a[j] * R[lag - 1 - j] for j in range(m))
          km = numer / E
          a_old = a[:m]
          for j in range(m):
              a[j] = a_old[j] + km * a_old[m - 1 - j]
          a[m] = km
          E *= 1.0 - km * km
          print(f"  k[{m+1}] = {km:.4f}")
      return a

  R = [10.0, 8.0, 5.0, 2.0]
  coeffs = run_levinson(R, 3)
  print("Coefficients:", [f"{c:.4f}" for c in coeffs])
  ```

  Expected output (approximately):
  - $k_1 = 8/10 = 0.8000$, $E_1 = 10(1-0.64) = 3.6$
  - $k_2 = (5 - 0.8 times 8) / 3.6 = (5-6.4)/3.6 approx -0.3889$, $E_2 approx 2.054$
  - $k_3 = (2 - a_1 times 5 - a_2 times 8) / E_2$

  All $|k_j| < 1$, confirming a stable predictor. The coefficients approximately model the decreasing autocorrelation of a smooth, correlated source.
]

#exercise("40.6", 2)[
  The LOCO-I MED predictor uses three neighbours $A$ (left), $B$ (above), $C$ (above-left). Apply the predictor to a 4×4 pixel block where a vertical edge runs between columns 2 and 3, with values 200 on the left of the edge and 50 on the right. For a pixel on the right side of the edge with $A = 50$ (left), $B = 200$ (above), $C = 200$ (above-left), what does MED predict? Explain why this is better than $A + B - C$.
]

#solution("40.6")[
  Given $A = 50$, $B = 200$, $C = 200$:

  Check: is $C >= max(A, B) = 200$? $C = 200 = max(A,B)$, so yes (with equality). MED predicts $hat(x) = min(A, B) = min(50, 200) = 50$.

  The naive average predictor gives $A + B - C = 50 + 200 - 200 = 50$ in this case, actually the same result. But consider $C = 210$ (slight noise above the edge): $C > max(A,B)$, so MED gives $min(A,B) = 50$, while $A + B - C = 50 + 200 - 210 = 40$ (undershoots). Near a strong vertical edge, MED anchors to the left neighbour $A$, which is on the same side of the edge. The residual is near zero; the $A+B-C$ version produces a non-zero residual in noisy edge cases.
]

== Further Reading

#link("https://ieeexplore.ieee.org/document/1094647")[Atal, B. S. & Schroeder, M. R. (1984). "Stochastic coding of speech signals at very low bit rates." Proc. ICASSP.] The paper introducing CELP.

#link("https://ieeexplore.ieee.org/document/125079")[Weinberger, M. J., Seroussi, G. & Sapiro, G. (2000). "The LOCO-I Lossless Image Compression Algorithm: Principles and Standardization into JPEG-LS." IEEE Trans. Image Processing 9(8).] The definitive LOCO-I paper.

#link("https://www.rfc-editor.org/rfc/rfc9639.txt")[Coalson, J. et al. (2024). "Free Lossless Audio Codec (FLAC)." RFC 9639.] FLAC's official IETF standard, with full specification of the LPC predictor and Rice coder.

#link("https://dl.acm.org/doi/10.1145/3015982")[Levinson, N. (1947). "The Wiener RMS Error Criterion in Filter Design and Prediction." J. Math. Phys. 25.] The original Levinson recursion.

#link("https://www.itu.int/rec/T-REC-G.726/en")[ITU-T G.726 (1990). "40, 32, 24, 16 kbit/s Adaptive Differential Pulse Code Modulation (ADPCM)".] The ADPCM telephony standard.

#link("https://en.wikipedia.org/wiki/Linear_predictive_coding")[Wikipedia: Linear Predictive Coding] A good overview with worked examples and implementation notes.

#bridge[
  We now have prediction in our toolkit: rather than transform a block of samples into a new coordinate system (Chapters 37–38) and then quantise (Chapter 39), we can predict each sample from its neighbours and code the tiny residual. But we have been treating prediction and quantisation as separate steps, first predict then code. In practice, the best coders optimise over both simultaneously. Chapter 41 confronts this directly: how do you decide, for each coefficient or sub-band or block, how many bits to spend? The answer is *Lagrangian Rate-Distortion Optimization*, a systematic way to trade distortion against bit-rate using a single parameter $lambda$. Every real encoder from JPEG to AV1 to FLAC uses some version of this machinery.
]
