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

= Transforms for Compression: KLT, DCT, Wavelets, MDCT

#epigraph[
  "The whole problem of compression is to find the coordinate system in which the
  data is simplest. Everything else is bookkeeping."
][a paraphrase of the transform-coding credo]

A photograph of a clear sky is, to a computer, a few hundred thousand numbers — one
brightness value per pixel — and almost all of them are nearly equal. A second of a
sustained flute note is forty-odd thousand numbers that rise and fall in a smooth,
repeating wave. In both cases the file is *long* but the *content* is small: a slow
gradient, a single pitch. The information is there, but it is smeared across thousands
of samples, hidden in plain sight. The question this chapter answers is the deepest one
in all of lossy compression:

#align(center)[*Is there a way to rewrite the data so its simplicity becomes visible —
so a handful of numbers carry almost everything, and the rest can be thrown away
almost for free?*]

The answer is yes, and it is called a *transform*. Spin the coordinate axes until they
line up with the grain of the data, and the energy that was smeared across thousands of
samples piles up onto a few. JPEG does it to your photos. MP3, AAC, and Opus do it to
your music. Every mainstream video codec does it to every frame. The transform is the
single idea that makes lossy media compression possible at all — and remarkably, the
*same* family of cosine waves, written down in a three-page paper in 1974, still sits at
the centre of it half a century later. This chapter builds that idea from the ground up:
the ideal transform that theory hands us (and why we can't use it), the practical
cosine transform that almost matches it (and why we can), the multi-scale wavelet
alternative, and the clever overlapping transform that lets us cut audio into blocks
without hearing the seams.

#recap[
  In Chapter 12 we learned that *vectors* are arrows in a space, that a *matrix* rotates
  or reshapes them, and that an *orthonormal* (length-preserving) matrix $Q$ satisfies
  $Q^T Q = I$, so its inverse is just its transpose — a perfect, lossless undo. We even
  proved the *energy theorem* there (an orthonormal transform conserves the total squared
  length of a vector) and played with a tiny throwaway $2 times 2$ rotation in code to watch
  it come alive. In Chapter 21 we met Shannon's
  *rate–distortion function* $R(D)$, the exact bit-cost of allowing average distortion
  $D$, and in Chapter 37 we learned that any signal is a sum of *sine and cosine waves of
  different frequencies* — the frequency-domain view, and the Discrete Fourier Transform
  (DFT) that computes it. This chapter fuses all three: we use orthonormal *cosine*
  transforms to move signals into a frequency-like coordinate system where energy
  compacts, so the quantiser of Chapter 39 can spend bits exactly where $R(D)$ says they
  matter.
]

#objectives((
  "Explain decorrelation and energy compaction, and why they make a signal cheaper to code.",
  "State what the Karhunen–Loève Transform (KLT) is, prove it is the optimal decorrelating transform, and explain why it is impractical.",
  "Write down the 1-D and 8×8 Discrete Cosine Transform (DCT), compute small examples by hand, and explain why the DCT closely approximates the KLT for natural signals.",
  "Describe the multi-resolution idea behind wavelets and how it avoids blocking artifacts.",
  "Explain the Modified DCT (MDCT), critical sampling, and how time-domain aliasing cancellation gives perfect reconstruction with 50%-overlapping windows.",
  "Implement dct1d / idct1d and 8×8 dct2d / idct2d in tinyzip and verify round-tripping and energy compaction on a real block.",
))

== The one idea: rotate until the data is simple

Let us make the opening promise concrete with the smallest possible example. Suppose a
grey-scale image is so smooth that any two side-by-side pixels are almost equal. Take a
pair: $x = (50, 52)$. Stored directly, that is two numbers near 50, each needing, say, a
byte. But look at what they *share* and how they *differ*:

$ "average" = (50 + 52)/2 = 51, quad "difference" = (52 - 50)/2 = 1. $

The average is large; the difference is tiny. If we store $(51, 1)$ instead of
$(50, 52)$, we have *lost nothing* — we can recover $50 = 51 - 1$ and $52 = 51 + 1$ — yet
the second number is now so small it costs almost no bits. We have not compressed by
deleting data; we have *changed coordinates* so that one coordinate is big and the other
is nearly zero. That is the entire trick, and everything below is this trick made
rigorous, made multi-dimensional, and made fast.

The map $(x_0, x_1) |-> ("sum", "difference")$, scaled to preserve length, is an
orthonormal rotation — exactly the $45 degree$ rotation we built in Chapter 12:

$ Q = 1/sqrt(2) mat(1, 1; 1, -1), quad Q vec(50, 52) = 1/sqrt(2) vec(102, -2) approx vec(72.1, -1.4). $

One big coordinate ($approx 72$), one tiny one ($approx -1.4$). The energy
$50^2 + 52^2 = 5204$ is exactly the new energy $72.1^2 + 1.4^2 approx 5204$ — conserved,
as the energy theorem promised. Compression has not happened *yet*; we still have two
numbers. But the tiny coordinate will *quantise to zero* almost for free in Chapter 39,
and *that* is where the bytes vanish. Hold that sequence in mind for the whole chapter:
#emph[transform makes the data lopsided; quantisation banks the lopsidedness; the entropy
coder of Volume II packs the survivors.]

#keyidea[
  A transform never compresses by itself — it is perfectly reversible, so it cannot
  delete information. Its job is to *re-express* the signal in a coordinate system where a
  few coordinates are large and most are near zero. The deleting happens later, in
  quantisation, and it is cheap *precisely because* the transform made most coordinates
  small. Transform first, throw away second.
]

#misconception[
  "The transform is the lossy step — that's where the data gets thrown away."
][
  The transform (DCT, wavelet, MDCT) is *exactly invertible*: feed its output back through
  the inverse and you recover the original to the last decimal. It loses nothing. The
  *only* lossy step in a transform codec is quantisation (Chapter 39), which rounds the
  coefficients to a coarse grid. The transform's role is to arrange the coefficients so
  that rounding hurts as little as possible. Blame the rounding, not the rotation.
]

=== What "decorrelation" and "energy compaction" really mean

Two words run through this whole chapter, so let us pin them down with the pair example
still warm.

#definition("Correlation")[
  Two coordinates are *correlated* when knowing one lets you predict the other. In a smooth
  image, neighbouring pixels are strongly correlated: tell me one is 50 and I will bet the
  next is near 50. Correlation is *redundancy you can see between coordinates* — and
  redundancy, as we have said since Chapter 3, is exactly what compression removes.
]

#definition("Decorrelation")[
  A transform *decorrelates* when its output coordinates no longer predict each other —
  knowing one tells you nothing about the rest. In our pair, "sum" and "difference" are
  decorrelated: the sum being 102 tells you nothing about whether the difference is $+2$ or
  $-2$. Decorrelated coordinates can be quantised *independently* without one re-encoding
  information already carried by another.
]

#definition("Energy compaction")[
  A transform has good *energy compaction* when, after the rotation, the total energy (sum
  of squared coordinates) is concentrated in a few coordinates while the rest are near
  zero. Energy compaction is the *payoff* of decorrelation for correlated sources: spin the
  axes to remove the redundancy and, because the redundancy was "everything is nearly the
  same," what remains is one big DC-like coordinate and a long tail of near-zeros.
]

#gomaths("Covariance — measuring how two coordinates move together")[
  We need one number that says "how correlated." Take a coordinate that is sometimes above
  its average, sometimes below; write its *deviation* as $x - macron(x)$ where
  $macron(x)$ is the mean. The *covariance* of two coordinates $X$ and $Y$ is the average
  product of their deviations:
  $ "Cov"(X, Y) = EE[(X - macron(x))(Y - macron(y))]. $
  If $X$ and $Y$ tend to be above their means together (and below together), the products
  are mostly positive and the covariance is large and positive — they are correlated. If
  they wander independently, the products are as often $+$ as $-$ and average to $0$.
  *Tiny example:* over the samples $X = (1, 3)$, $Y = (2, 6)$, means are $2$ and $4$;
  deviations are $(-1, +1)$ and $(-2, +2)$; products $(+2, +2)$; average $+2$ — strongly
  positively correlated, as you can see (when $X$ goes up, so does $Y$). The variance
  $"Var"(X) = "Cov"(X, X) = EE[(X - macron(x))^2]$ is just a coordinate's covariance with
  itself: its energy about the mean. We met expectation $EE[dot.c]$ and variance in
  Chapter 10; here they become the tools that *define* what a good transform does.
]

We can stack all the pairwise covariances of an $n$-dimensional signal into an
$n times n$ grid called the *covariance matrix* $Sigma$, where entry $Sigma_(i j) =
"Cov"(X_i, X_j)$. The diagonal holds the per-coordinate variances (energies); the
off-diagonal holds the correlations between coordinates. A *decorrelating* transform is
now defined with total precision: it is the rotation that makes the off-diagonal entries
of the *transformed* signal's covariance matrix all zero — a diagonal covariance means
no coordinate predicts any other. That rotation has a name, and it is the best one can
possibly do.

== The Karhunen–Loève Transform: the perfect (impractical) ideal

#gomaths("Eigenvectors and eigenvalues — the natural axes of a matrix")[
  Most directions, when you push them through a matrix $A$, come out rotated *and*
  stretched. But a few special directions come out only *stretched*, not turned at all:
  $A bold(v) = lambda bold(v)$, meaning "applying $A$ to $bold(v)$ just scales it by the
  number $lambda$." Such a $bold(v)$ is an *eigenvector* (German _eigen_ = "own,
  characteristic"); its scale factor $lambda$ is the *eigenvalue*. They are the matrix's
  own natural axes — the skeleton it acts on simply. *Tiny example:*
  $A = mat(3, 0; 0, 5)$ stretches the $x$-axis by $3$ and the $y$-axis by $5$, so
  $bold(v) = (1, 0)$ has $lambda = 3$ and $bold(v) = (0, 1)$ has $lambda = 5$. A key fact
  we will use: a *symmetric* matrix (one equal to its own transpose, like every covariance
  matrix, since $"Cov"(X, Y) = "Cov"(Y, X)$) always has a full set of *mutually
  perpendicular* eigenvectors with real eigenvalues. Those perpendicular eigenvectors are
  the axes we will rotate onto.
]

Here is the beautiful fact at the heart of optimal transform coding. The covariance
matrix $Sigma$ is symmetric, so it has a full set of perpendicular (orthonormal)
eigenvectors. Collect them as the rows of a matrix $Phi$. Then the transform
$bold(y) = Phi bold(x)$ *exactly decorrelates* the signal — and it is named after the two
mathematicians who developed its continuous form.

#algo(
  name: "Karhunen–Loève Transform (KLT)",
  year: "1947 / 1948",
  authors: "Kari Karhunen; Michel Loève (continuous theory); equivalently Principal Component Analysis (Hotelling 1933) in the discrete case",
  aim: "Rotate a signal onto the eigenvectors of its covariance matrix, producing perfectly decorrelated coefficients with maximal energy compaction.",
  complexity: "Transform: O(n²) per block (a full matrix multiply). Plus the cost of estimating Σ and finding its eigenvectors, O(n³).",
  strengths: "Provably optimal: among all orthonormal transforms it best decorrelates and best compacts energy for a stationary source.",
  weaknesses: "Signal-dependent: the basis depends on the data's statistics, so it must be computed per source and transmitted to the decoder. No fast algorithm.",
  superseded: "the DCT, which approximates it with a fixed, fast, transmission-free basis",
)[
  The KLT is the gold standard against which every practical transform is measured. It is
  also, for compression, almost unusable — which is the whole reason the rest of this
  chapter exists. Note the names: in statistics the same construction is *Principal
  Component Analysis (PCA)*; the eigenvectors are the *principal components*. Same idea,
  different field, born independently.
]

Why is the KLT optimal? The claim has two halves — it decorrelates perfectly, and among
*all* transforms that keep only $k$ coefficients it loses the least energy — and both are
worth proving, because the proofs show exactly *what* "best transform" means.

#theorem("KLT decorrelation")[
  Let $bold(x)$ have covariance matrix $Sigma$, and let the rows of $Phi$ be orthonormal
  eigenvectors of $Sigma$. Then the transformed signal $bold(y) = Phi bold(x)$ has a
  diagonal covariance matrix: its coordinates are uncorrelated, and the variance of the
  $i$-th coordinate is the $i$-th eigenvalue $lambda_i$.
]

#proof[
  Subtract means so $bold(x)$ has mean zero; then $Sigma = EE[bold(x) bold(x)^T]$ (the
  average of the "outer product," a matrix whose $(i,j)$ entry is $EE[x_i x_j] =
  "Cov"(X_i, X_j)$). The covariance of $bold(y) = Phi bold(x)$ is
  $ EE[bold(y) bold(y)^T] = EE[(Phi bold(x))(Phi bold(x))^T] = Phi thin EE[bold(x) bold(x)^T] thin Phi^T = Phi Sigma Phi^T. $
  Now use the defining property of eigenvectors: stacked as rows of $Phi$, they satisfy
  $Sigma Phi^T = Phi^T Lambda$, where $Lambda$ is the diagonal matrix of eigenvalues
  (each column of $Phi^T$ is an eigenvector, and $Sigma$ acting on it just scales it by its
  $lambda$). Therefore
  $ Phi Sigma Phi^T = Phi (Phi^T Lambda) = (Phi Phi^T) Lambda = I dot.c Lambda = Lambda, $
  using $Phi Phi^T = I$ because the rows are orthonormal. The result $Lambda$ is diagonal:
  off-diagonal covariances are all zero, so the transformed coordinates are uncorrelated,
  and the $i$-th diagonal entry $lambda_i$ is the variance of $y_i$.
]

So the KLT *manufactures* decorrelation by construction. The eigenvalues $lambda_i$ are
the energies of the new coordinates; sorting them large-to-small sorts the coordinates by
importance. The second half says no other transform compacts energy better.

#theorem("KLT optimal energy compaction")[
  Among all orthonormal transforms, the KLT (with coordinates ordered by decreasing
  eigenvalue) minimises the energy lost when you keep only the first $k$ coefficients and
  discard the rest, for every $k$.
]

#proof[
  Keeping the first $k$ transformed coordinates and zeroing the rest loses the energy in
  the discarded tail, which for an orthonormal transform equals the *sum of the discarded
  variances* (because energy is the sum of squared coordinates, and orthonormal transforms
  conserve total energy). So minimising lost energy means *packing as much variance as
  possible into the first $k$ coordinates.* The total variance $sum_i "Var"(y_i)$ is fixed
  — it equals the *trace* of $Sigma$ (the sum of its diagonal entries, here the sum of the
  per-coordinate variances), which is unchanged by any orthonormal rotation (a
  rotation cannot create or destroy total energy). The KLT's coordinates have variances
  equal to the eigenvalues $lambda_1 >= lambda_2 >= dots.c$; taking the top $k$ takes the
  $k$ *largest* possible such variances summing to a fixed total. A classical result (the
  Ky Fan / Poincaré separation theorem) confirms that no other orthonormal basis can place
  more variance in any leading $k$-dimensional subspace than the top-$k$ eigenvectors do.
  Hence the KLT loses the least energy for every truncation depth $k$.
]

#example[
  *A worked KLT, by hand.* Take a source whose two pixels have covariance
  $Sigma = mat(2, 1.6; 1.6, 2)$ — equal variances $2$, strong positive correlation $1.6$.
  A symmetric $2 times 2$ matrix with equal diagonals always has eigenvectors along the two
  diagonals $bold(v)_1 = (1, 1)\/sqrt(2)$ and $bold(v)_2 = (1, -1)\/sqrt(2)$. Check:
  $ Sigma bold(v)_1 = mat(2, 1.6; 1.6, 2) 1/sqrt(2) vec(1, 1) = 1/sqrt(2) vec(3.6, 3.6) = 3.6 thin bold(v)_1, $
  so $lambda_1 = 3.6$; similarly $Sigma bold(v)_2 = 0.4 thin bold(v)_2$, so $lambda_2 =
  0.4$. The KLT basis is the $45 degree$ "sum/difference" rotation of our opening example —
  *and the eigenvalues tell us why it works*: the sum direction carries variance $3.6$,
  the difference direction only $0.4$. Keep just the first coordinate and you retain
  $3.6 \/ (3.6 + 0.4) = 90%$ of the energy from $50%$ of the numbers. The more correlated
  the pixels (the larger the off-diagonal $1.6$ relative to $2$), the more lopsided the
  split — correlation *is* compressibility, quantified.
]

#keyidea[
  The KLT proves that the *best possible* transform for a correlated source is simply "the
  eigenvectors of its covariance matrix, sorted by energy." It is the theoretical ceiling.
  Everything practical is a fixed, fast *imitation* of this ceiling — and the astonishing
  news of the next section is how close a fixed imitation can get.
]

But notice the fatal catch hiding in that example. To build $Phi$ you must *know* $Sigma$,
which means estimating the signal's statistics; then you must compute eigenvectors (an
$O(n^3)$ job); then — because $Phi$ is different for every source — you must *transmit the
entire basis to the decoder*, which for an $8 times 8 = 64$-dimensional image block is 64
basis vectors of 64 numbers each. The basis can cost more than the data it saves. The KLT
is optimal and almost useless. We need a transform that is *fixed* (no transmission),
*fast* (no $O(n^3)$), and *nearly* as good. In 1974, three engineers found one.

== The Discrete Cosine Transform: the workhorse of the world

The escape from the KLT's catch is a single, beautiful observation. Natural signals —
photographs, audio — are well modelled as a *first-order Markov process*: each sample is
its neighbour plus a little fresh randomness, with correlation $rho$ between adjacent
samples (think $rho approx 0.95$ for a smooth image). For such a source, the covariance
matrix has a fixed, known shape ($Sigma_(i j) = rho^(abs(i - j))$, up to scale), and as
the correlation $rho -> 1$, its eigenvectors — the KLT basis — converge to a *fixed set of
cosine waves that do not depend on $rho$ at all.* That limiting basis is the DCT. It is
the KLT's fixed, universal shadow: no statistics to estimate, no basis to transmit, and a
fast algorithm to boot.

#mathrecall[A *first-order Markov process* is one where each sample depends only on the
immediately previous one, not the whole past — the simplest model of "smooth": tomorrow is
today plus a nudge. It is built from the conditional probability of Chapter 9, asking only
$P("next" | "current")$ rather than $P("next" | "all the past")$.]

#algo(
  name: "Discrete Cosine Transform (DCT-II)",
  year: "January 1974",
  authors: "Nasir Ahmed, T. Raj Natarajan, K. R. Rao (IEEE Trans. Computers 23(1), pp. 90–93)",
  aim: "A fixed, signal-independent orthogonal transform onto cosine basis functions that approximates the KLT for highly-correlated (Markov-1) signals — the practical decorrelator.",
  complexity: "O(n log n) per block of length n via a fast algorithm (the same FFT-style butterfly structure as Chapter 37's DFT); a naive matrix multiply is O(n²).",
  strengths: "Fixed basis (nothing to transmit), excellent energy compaction on natural signals, near-KLT-optimal, fast, real-valued output, separable in 2-D.",
  weaknesses: "Blocking artifacts at low bitrates (hard block boundaries); fixed block size cannot adapt to local detail; not optimal for sharp edges.",
  superseded: "complemented by wavelets (JPEG 2000) and learned transforms (Chapter 57); still dominant in JPEG, MP3/AAC (via MDCT), and every mainstream video codec",
)[
  The DCT-II is *the* DCT — when someone says "the DCT" with no qualifier, this is it. Its
  inverse, used by every decoder, is the DCT-III. Ahmed conceived it at Kansas State
  University around 1972; his grant proposal to study it was reportedly rejected as too
  impractical. It went on to become very likely the most-executed numerical recipe in
  history, run billions of times per second on screens worldwide.
]

=== The formula, built from the frequency idea

Recall from Chapter 37 that any block of $N$ samples can be written as a sum of waves of
increasing frequency. The DCT chooses *cosine* waves specifically, sampled at the
"half-integer" points that make the basis orthogonal. The forward 1-D DCT of a length-$N$
block $x_0, x_1, dots, x_(N-1)$ produces $N$ coefficients $X_0, dots, X_(N-1)$:

$ X_k = alpha_k sum_(n=0)^(N-1) x_n cos[ (pi (2n + 1) k) / (2N) ], quad k = 0, 1, dots, N-1, $

where the normalisation $alpha_0 = sqrt(1\/N)$ and $alpha_k = sqrt(2\/N)$ for $k >= 1$ is
chosen to make the transform *orthonormal* — so, exactly as in Chapter 12, the inverse is
the transpose and energy is conserved. The inverse (the IDCT, DCT-III) rebuilds the
samples by summing the cosines back:

$ x_n = sum_(k=0)^(N-1) alpha_k thin X_k cos[ (pi (2n + 1) k)/(2N) ]. $

Read the formula physically. The $k=0$ coefficient uses $cos(0) = 1$ for every sample, so
$X_0$ is (a scaling of) the *average* of the block — the *DC term*, the flat component,
usually by far the largest. Higher $k$ multiplies the samples by faster and faster
cosines, measuring how much *wiggle* of that frequency the block contains — the *AC
terms*. For a smooth block the wiggles are tiny, so the high-$k$ coefficients are near
zero: energy compaction, straight out of the formula.

#gomaths("Why these particular cosines are orthonormal")[
  Two basis waves are *orthogonal* when their samples, multiplied point-by-point and
  summed, give zero — they "don't overlap." The DCT's cosines are sampled at the shifted
  points $(2n+1)\/(2N)$ precisely so that
  $ sum_(n=0)^(N-1) cos[(pi(2n+1) j)/(2N)] cos[(pi(2n+1) k)/(2N)] = 0 quad "whenever" j != k, $
  and equals a fixed constant when $j = k$ (which the $alpha_k$ factors normalise to $1$).
  This is the same product-to-sum trick that makes Fourier series work, applied to a finite
  block with the clever half-integer offset that handles the boundaries cleanly. The upshot
  is exactly Chapter 12's condition: stack the normalised cosine waves as rows of a matrix
  $C$ and you get $C^T C = I$ — an orthonormal transform, perfectly invertible, energy
  preserving. You do not need to re-derive this; you need to trust that the DCT is a
  genuine length-preserving rotation, just like the $45 degree$ one, only $N$-dimensional
  and made of cosines.
]

Two small theorems make the DCT's behaviour exact rather than hand-wavy. The first is the
*energy theorem* of Chapter 12, specialised to the DCT; it is what lets the quantiser of
Chapter 39 reason about distortion in the coefficient domain.

#theorem("DCT preserves energy (Parseval for the DCT)")[
  For the orthonormal DCT, the total energy of the coefficients equals the total energy of
  the samples: $sum_(k=0)^(N-1) X_k^2 = sum_(n=0)^(N-1) x_n^2$.
]

#proof[
  Write the forward DCT as a matrix–vector product $bold(X) = C bold(x)$, where the rows of
  $C$ are the normalised cosine waves. The energy of the coefficients is
  $ sum_k X_k^2 = bold(X)^T bold(X) = (C bold(x))^T (C bold(x)) = bold(x)^T C^T C thin bold(x). $
  By the orthonormality just established, $C^T C = I$, so this is
  $bold(x)^T I bold(x) = bold(x)^T bold(x) = sum_n x_n^2$. The two energies are equal. The
  consequence for compression is decisive: because the transform neither creates nor
  destroys energy, the squared error you introduce by rounding the coefficients equals,
  exactly, the squared error you will see in the reconstructed samples — so quantising in
  the coefficient domain lets you *predict the visible distortion directly*.
]

#theorem("The DC coefficient is the scaled block mean")[
  $X_0 = sqrt(N) thin macron(x)$, where $macron(x) = (1\/N) sum_n x_n$ is the average of the block.
]

#proof[
  Set $k = 0$ in the DCT formula. The cosine becomes $cos(0) = 1$ for every $n$, and
  $alpha_0 = sqrt(1\/N)$, so
  $ X_0 = sqrt(1/N) sum_(n=0)^(N-1) x_n dot.c 1 = sqrt(1/N) (N macron(x)) = sqrt(N) thin macron(x). $
  This is why $X_0$ is called the *DC term* (borrowing "direct current" from electronics):
  it is the flat, average level of the block, scaled by $sqrt(N)$ to keep the transform
  orthonormal. For our $N = 4$ ramp it predicts $X_0 = sqrt(4) dot.c 13 = 26$, matching the
  worked example exactly. Every other coefficient measures *departures* from this average —
  the detail — and for smooth blocks those departures are small.
]

#fig([The eight 1-D DCT basis waves for a block of length $N = 8$. Coefficient $X_k$
measures how much of wave $k$ the signal contains. $k = 0$ is flat (the DC average);
higher $k$ wiggles faster. A smooth block is mostly the top few; a busy block lights up
the lower ones.],
  cetz.canvas({
    import cetz.draw: *
    let N = 8
    for k in range(8) {
      let yoff = -1.7 * k
      line((0, yoff), (4.2, yoff), stroke: 0.4pt + rgb("#999999"))
      content((-0.75, yoff), text(size: 8pt)[$k=#k$])
      let pts = ()
      let M = 64
      for i in range(M + 1) {
        let t = i / M
        let n = t * (N - 1)
        let v = calc.cos(calc.pi * (2.0 * n + 1.0) * k / (2.0 * N))
        pts.push((0.1 + t * 4.0, yoff + 0.62 * v))
      }
      line(..pts, stroke: 1.1pt + rgb("#0b5394"))
    }
  }))

#example[
  *A 1-D DCT by hand, $N = 4$.* Take a smooth ramp $bold(x) = (10, 12, 14, 16)$ — average
  $13$, gently rising. The $k=0$ DC coefficient is
  $ X_0 = sqrt(1\/4) (10 + 12 + 14 + 16) = 1/2 dot.c 52 = 26, $
  which is $sqrt(4) = 2$ times the average $13$ (the orthonormal scaling). For $k=1$,
  compute the four cosines $cos(pi (2n+1)\/8)$ for $n = 0,1,2,3$: about
  $0.924, 0.383, -0.383, -0.924$; then
  $ X_1 = sqrt(2\/4) [10(0.924) + 12(0.383) + 14(-0.383) + 16(-0.924)] approx sqrt(0.5)(-6.31) approx -4.46. $
  Carrying on gives $X_2 approx 0$ and $X_3 approx -0.32$. So the ramp becomes roughly
  $(26, -4.46, 0, -0.32)$: a big DC, a modest "slope" term, and two near-zeros. Two
  numbers describe the ramp almost perfectly; the last two quantise to nothing. Verify
  energy: $10^2 + 12^2 + 14^2 + 16^2 = 696$, and $26^2 + 4.46^2 + 0^2 + 0.32^2 approx 696$
  — conserved to rounding, the energy theorem alive again.
]

#checkpoint[
  A block is *perfectly flat*: $bold(x) = (7, 7, 7, 7)$. Without computing all the
  cosines, what do you expect its DCT to be, and why?
][Only $X_0$ is nonzero; all AC coefficients are $0$. A flat block is pure DC — it contains
no wiggle at any frequency, so every cosine wave $k >= 1$ (which has equal positive and
negative parts) sums to exactly zero against a constant. The DCT reports "all average, no
detail," which is the truth. This is energy compaction at its extreme: $100%$ of the energy
in $1$ of $4$ coefficients.]

=== From 1-D to 8×8: the separable 2-D DCT

Images are two-dimensional, so JPEG works on $8 times 8$ blocks of pixels. The 2-D DCT is
not a new idea — it is the 1-D DCT applied *twice*, once to every row and once to every
column. This is called *separability*, and it is what keeps the 2-D transform fast.

$ X_(u v) = alpha_u alpha_v sum_(x=0)^7 sum_(y=0)^7 f_(x y) cos[(pi(2x+1)u)/16] cos[(pi(2y+1)v)/16]. $

The double sum looks fierce, but separability means you never compute it directly: DCT
each of the 8 rows (8 small 1-D transforms), then DCT each of the 8 columns of the result
(8 more). The coefficient $X_(0 0)$ in the top-left corner is the DC term — the block's
average brightness. Moving right increases horizontal frequency; moving down increases
vertical frequency; the bottom-right corner is the fastest checkerboard. For a typical
photographic block, the energy huddles in the top-left few coefficients and the rest are
near zero — which is exactly why JPEG can throw most of them away.

#example[
  *Separability on a $2 times 2$ block, in full.* Take the tiny block
  $F = mat(10, 10; 30, 30)$ — flat across each row, jumping top-to-bottom. Use the $N = 2$
  DCT matrix $C = 1/sqrt(2) mat(1, 1; 1, -1)$ (the sum/difference rotation again).
  *Step 1 — DCT each row.* Row $(10, 10) -> 1/sqrt(2)(20, 0) = (14.14, 0)$; row
  $(30, 30) -> (42.43, 0)$. The row-transformed matrix is $mat(14.14, 0; 42.43, 0)$ —
  every row was flat, so all the horizontal AC terms vanished. *Step 2 — DCT each column.*
  Left column $(14.14, 42.43) -> 1/sqrt(2)(56.57, -28.28) = (40, -20)$; right column
  $(0, 0) -> (0, 0)$. Final coefficients: $mat(40, 0; -20, 0)$. Read them off: $X_(0 0) = 40$
  is the DC term ($sqrt(4)$ times the block average $20$ — the 2-D version of the
  DC-equals-mean theorem); $X_(1 0) = -20$ captures the vertical top-to-bottom jump; the two
  horizontal terms are exactly zero because the block has no horizontal variation. Two
  numbers describe the whole block. Energy: input $10^2+10^2+30^2+30^2 = 2000$; coefficients
  $40^2 + 20^2 = 2000$ — conserved, and the 2-D DCT is just the 1-D DCT done twice.
]

#fig([The $8 times 8$ grid of 2-D DCT basis patterns. Top-left is flat (DC, the block
average). Rightward = faster horizontal stripes; downward = faster vertical stripes;
bottom-right = the busiest checkerboard. Any $8 times 8$ image block is a weighted sum of
these 64 patterns; in natural images the top-left weights dominate.],
  cetz.canvas({
    import cetz.draw: *
    let cell = 0.52
    for u in range(8) {
      for v in range(8) {
        let ox = v * (cell + 0.04)
        let oy = -u * (cell + 0.04)
        let val = calc.cos(calc.pi * 0.5 * u) * calc.cos(calc.pi * 0.5 * v)
        let g = (val + 1.0) / 2.0
        rect((ox, oy), (ox + cell, oy + cell),
          fill: rgb(int(255 * g), int(255 * g), int(255 * g)),
          stroke: 0.3pt + rgb("#cccccc"))
      }
    }
    content((4.0 * (cell + 0.04), 0.55), text(size: 8pt, fill: rgb("#0b5394"))[horizontal frequency $v ->$])
    content((-1.0, -3.6), text(size: 8pt, fill: rgb("#0b5394"))[$u$ down])
  }))

#example[
  *Energy compaction on a real-ish block.* Consider an $8 times 8$ block that is a smooth
  diagonal gradient, brightness rising from $80$ in the top-left to $200$ in the
  bottom-right. After the 2-D DCT, essentially all the energy lands in $X_(0 0)$ (the
  average, near $140 times 8 = 1120$) plus the two adjacent low-frequency terms $X_(0 1)$
  and $X_(1 0)$ (the horizontal and vertical slopes). The remaining $61$ coefficients are
  below $1$ in magnitude. Quantise with JPEG's standard table and all $61$ round to zero —
  the block is stored as *three numbers plus 61 zeros*, and the 61 zeros cost almost
  nothing once run-length and Huffman coded (Chapter 42). A $64$-byte block becomes a
  handful of bytes, with a reconstruction the eye cannot tell from the original. That single
  paragraph is, in miniature, why JPEG exists.
]

== The project: build the DCT in tinyzip

#project("Step 17 · transform.py — dct1d / idct1d and 8×8 dct2d / idct2d")[
  This is `tinyzip`'s first lossy-pipeline module. In Chapter 12 we wrote a throwaway
  $2 times 2$ rotation to watch the energy theorem come alive, but explicitly kept no module;
  Chapter 37 promised the real transform would land here. Now we create `transform.py` with
  the *real cosine matrix*: the 1-D DCT and its inverse, then the separable $8 times 8$ 2-D
  DCT used by JPEG (Chapter 42 imports these). Everything round-trips and conserves energy.

  #gopython("math.cos, and nested lists as matrices")[
    We use `math.cos`, `math.pi`, and `math.sqrt` from Python's standard `math` module
    (`import math`). A 2-D block is just a `list[list[float]]` — a list of rows, each row a
    list of numbers — and we index it `block[row][col]`. A *nested comprehension*
    `[[f(i, j) for j in range(N)] for i in range(N)]` builds an $N times N$ matrix row by
    row: the inner comprehension fills one row, the outer repeats it for every row. We met
    comprehensions in Chapter 16; here they let us write a whole transform in a few lines.
  ]

  ```python
  # tinyzip/transform.py  —  Step 17: the Discrete Cosine Transform
  import math

  def _dct_matrix(n: int) -> list[list[float]]:
      """Rows = the n orthonormal DCT-II basis waves of length n."""
      C: list[list[float]] = []
      for k in range(n):
          ak = math.sqrt(1.0 / n) if k == 0 else math.sqrt(2.0 / n)
          row = [ak * math.cos(math.pi * (2 * i + 1) * k / (2 * n))
                 for i in range(n)]
          C.append(row)
      return C

  def dct1d(x: list[float]) -> list[float]:
      """Forward 1-D DCT-II of a block of samples -> coefficients."""
      n = len(x)
      C = _dct_matrix(n)
      return [sum(C[k][i] * x[i] for i in range(n)) for k in range(n)]

  def idct1d(X: list[float]) -> list[float]:
      """Inverse 1-D DCT (DCT-III): coefficients -> samples.
      Because C is orthonormal, the inverse is multiply by C-transpose."""
      n = len(X)
      C = _dct_matrix(n)
      return [sum(C[k][i] * X[k] for k in range(n)) for i in range(n)]

  def dct2d(block: list[list[float]]) -> list[list[float]]:
      """Separable 8x8 (or NxN) 2-D DCT: rows then columns."""
      n = len(block)
      rows = [dct1d(block[r]) for r in range(n)]            # DCT every row
      cols = [[rows[r][c] for r in range(n)] for c in range(n)]
      tcols = [dct1d(cols[c]) for c in range(n)]            # DCT every column
      return [[tcols[c][r] for c in range(n)] for r in range(n)]

  def idct2d(coeffs: list[list[float]]) -> list[list[float]]:
      """Inverse 2-D DCT: undo columns then rows."""
      n = len(coeffs)
      cols = [[coeffs[r][c] for r in range(n)] for c in range(n)]
      tcols = [idct1d(cols[c]) for c in range(n)]
      rows = [[tcols[c][r] for c in range(n)] for r in range(n)]
      return [idct1d(rows[r]) for r in range(n)]
  ```

  A tiny self-test verifies round-tripping and shows energy compacting onto the DC corner:

  ```python
  def _selftest() -> None:
      # 1-D round-trip on a smooth ramp
      x = [10.0, 12.0, 14.0, 16.0]
      X = dct1d(x)
      back = idct1d(X)
      assert all(abs(a - b) < 1e-9 for a, b in zip(x, back)), "1-D round-trip failed"
      assert abs(sum(c * c for c in x) - sum(c * c for c in X)) < 1e-9, "energy not conserved"

      # 8x8 round-trip on a smooth diagonal gradient
      block = [[80.0 + (i + j) * 120.0 / 14.0 for j in range(8)] for i in range(8)]
      coeffs = dct2d(block)
      recon = idct2d(coeffs)
      err = max(abs(block[i][j] - recon[i][j]) for i in range(8) for j in range(8))
      assert err < 1e-6, "8x8 round-trip failed"

      # energy compaction: the DC corner should hold the lion's share
      total = sum(coeffs[i][j] ** 2 for i in range(8) for j in range(8))
      dc = coeffs[0][0] ** 2
      print(f"DC holds {100 * dc / total:.1f}% of the energy; round-trip error {err:.1e}")

  if __name__ == "__main__":
      _selftest()
  ```

  Run `python -m tinyzip.transform`: the asserts pass (the DCT is exactly invertible and
  energy-conserving), and the smooth block reports the overwhelming majority of its energy
  sitting in the single DC coefficient. The transform stage does not move the scoreboard by
  itself — a reversible rotation saves no bytes — but it is the lossless engine that the
  quantiser of Chapter 39 and the toy JPEG of Chapter 42 turn into real savings. The
  throwaway scaffold of Chapter 12 has become a genuine JPEG transform stage, exactly as
  Chapter 37 promised.
]

#pitfall[
  Our `dct1d` rebuilds the cosine matrix on every call and does a full $O(n^2)$ matrix
  multiply — perfect for learning, far too slow for a real codec. Production encoders use a
  *fast DCT* (an $O(n log n)$ butterfly, e.g. Loeffler–Ligtenberg–Moschytz, 1989, which
  computes an $8$-point DCT in just $11$ multiplications) and integer approximations so the
  encoder and decoder agree bit-exactly. We meet the integer DCT idea again with video
  codecs in Chapter 51. The clarity-first code here is correct; just do not ship it.
]

== Wavelets: seeing the signal at every scale at once

The DCT has one structural weakness baked into it: it chops the signal into *fixed-size
blocks* and transforms each independently. At high quality this is invisible. But push the
quantisation hard — a heavily compressed JPEG — and the block boundaries stop matching up,
producing the tell-tale $8 times 8$ *blocking artifacts* you have seen in over-compressed
images. The root cause is that a single block size cannot be right everywhere: a flat sky
wants big blocks (efficient), a sharp eyelash wants tiny ones (to localise the edge). What
if a transform could look at *every scale at once*?

That is the *wavelet* idea. Instead of one fixed block size, a wavelet transform splits the
signal into a *coarse* approximation (the slow, large-scale trends) and a *detail* signal
(the fast, fine-scale wiggles) — then recursively splits the coarse part again, and again,
building a pyramid of resolutions. Big smooth regions are captured cheaply by the coarse
levels; sharp edges are pinpointed by a few large detail coefficients exactly where they
occur. There is no fixed block grid to leave seams.

#gomaths("Multi-resolution by averages and differences — the Haar wavelet")[
  The simplest wavelet is just our opening "sum and difference," applied as a pyramid. Take
  a signal $(s_0, s_1, s_2, s_3, dots)$. Pair it up and, for each pair, store the
  *average* and the *difference*:
  $ a_i = (s_(2i) + s_(2i+1))/sqrt(2), quad d_i = (s_(2i) - s_(2i+1))/sqrt(2). $
  The averages $a_i$ are a *half-length, blurrier copy* of the signal; the differences
  $d_i$ are the *fine detail* lost in the blur. Now recurse: apply the same average/
  difference step to the $a_i$ alone, producing a quarter-length copy and another detail
  band, and so on. After $log_2 N$ steps you have one overall average plus detail bands at
  every scale. *Tiny example:* $(4, 6, 10, 12) ->$ averages $(10, 22)\/sqrt(2) approx
  (7.07, 15.56)$, details $(-2, -2)\/sqrt(2) approx (-1.41, -1.41)$; recurse on the
  averages: overall average $(7.07 + 15.56)\/sqrt(2) approx 16.0$, coarse detail
  $(7.07 - 15.56)\/sqrt(2) approx -6.0$. The full transform is $(16.0, -6.0, -1.41, -1.41)$
  — one number for "how bright overall," one for "the big top-to-bottom trend," two for
  "the fine wiggles." Each step is orthonormal (the $sqrt(2)$ keeps lengths), so the whole
  pyramid is a perfect, invertible rotation: average back the way you split.
]

#algo(
  name: "Discrete Wavelet Transform (DWT)",
  year: "1909 (Haar); 1988 (Daubechies, smooth orthonormal wavelets); 1989 (Mallat, the fast pyramid algorithm)",
  authors: "Alfréd Haar; Ingrid Daubechies; Stéphane Mallat; Yves Meyer",
  aim: "Decompose a signal into a coarse approximation plus detail bands at multiple scales simultaneously, localising both in space and in frequency.",
  complexity: "O(n) — even faster than the FFT/DCT, because each level halves the data and the pyramid is a geometric series.",
  strengths: "Multi-resolution (no fixed block grid → no blocking artifacts), localises edges, naturally scalable/progressive (send coarse first), good energy compaction on natural images.",
  weaknesses: "More complex to implement than a block DCT; boundary handling is fiddly; the better smooth wavelets (Daubechies, CDF 9/7) are not as hardware-trivial as an 8×8 DCT.",
  superseded: "not superseded — chosen by JPEG 2000 and used in many scientific and medical codecs; the DCT simply won the web on simplicity and momentum",
)[
  The wavelet transform is genuinely *better* than the DCT at low bitrates on many images —
  no blocking, graceful degradation, built-in scalability. JPEG 2000 (Chapter 43) is built
  on the Cohen–Daubechies–Feauveau (CDF) 9/7 wavelet. Yet JPEG-classic still dominates the
  web. The lesson, which recurs throughout this book, is that *technical superiority does
  not guarantee adoption*: simplicity, patent freedom, hardware support, and momentum often
  matter more.
]

#fig([The wavelet pyramid: each level splits into a coarse approximation (kept and split
again) and detail bands (saved). Smooth regions live in the small coarse box $"LL"_2$;
edges show up as a few large coefficients in the detail bands, localised where they occur.],
  cetz.canvas({
    import cetz.draw: *
    rect((0, 0), (4, 4), stroke: 0.6pt + rgb("#777777"))
    rect((2, 2), (4, 4), stroke: 0.5pt + rgb("#aaaaaa"))
    content((3, 3), text(size: 7pt)[$"HH"_1$])
    rect((0, 2), (2, 4), stroke: 0.5pt + rgb("#aaaaaa"))
    content((1, 3), text(size: 7pt)[$"LH"_1$])
    rect((2, 0), (4, 2), stroke: 0.5pt + rgb("#aaaaaa"))
    content((3, 1), text(size: 7pt)[$"HL"_1$])
    rect((0, 2), (1, 3), stroke: 0.5pt + rgb("#0b5394"))
    content((0.5, 2.5), text(size: 6pt)[$"LL"_2$])
    rect((1, 2), (2, 3), stroke: 0.5pt + rgb("#cccccc"))
    rect((0, 3), (1, 4), stroke: 0.5pt + rgb("#cccccc"))
    rect((1, 3), (2, 4), stroke: 0.5pt + rgb("#cccccc"))
    content((6.3, 3.5), text(size: 8pt)[$"LL"_2$: coarsest])
    content((6.55, 2.95), text(size: 8pt)[average (cheap)])
    content((6.65, 1.6), text(size: 8pt)[detail bands hold])
    content((6.55, 1.05), text(size: 8pt)[edges, localised])
  }))

#example[
  *Why wavelets dodge blocking.* Imagine a $1 times 16$ row that is flat at $100$ for the
  first $9$ samples, then jumps to $200$. The DCT of a block straddling the jump spreads the
  edge's energy across *many* high-frequency coefficients (a sharp step needs every
  frequency to build it; truncating or coarsening those frequencies leaves a rippling
  overshoot beside the edge, the classic *Gibbs ringing* of any finite sum of smooth waves),
  and quantising them coarsely smears the edge into ripples. The Haar wavelet, by contrast, records the edge as essentially
  *one* large detail coefficient at the scale and location of the jump, with the flat
  regions collapsing to a couple of coarse numbers. The edge stays sharp and local; there is
  no block grid to misalign. That locality — "an event affects only the coefficients near
  it" — is the wavelet's structural advantage, and the reason JPEG 2000 looks better than
  JPEG at the same low bitrate.
]

=== Why compaction actually saves bits: from energy to entropy

We have leaned on the phrase "energy compaction" as if concentrating energy obviously
saves bits. It is worth closing that loop precisely, because it connects this chapter back
to the very first theorems of the book. In Chapter 18 we learned that the cost of coding a
value is its *self-information*, and the average cost of a stream is its *entropy*
$H = - sum_i p_i log_2 p_i$ — and in Chapter 19 that no lossless coder can beat that
entropy. The transform does not change how many *coefficients* there are; it changes their
*distribution*, and the distribution is what entropy charges for.

Picture the histogram of a block's pixel values: a broad, flat spread — many different
mid-range brightnesses, each roughly as likely as the next. A broad, flat histogram has
*high* entropy, so each pixel costs many bits. Now apply the DCT. The coefficient histogram
is utterly different: one or two huge values (DC and the lowest frequencies) and a tall
spike of values clustered tightly at *zero* (all the empty high frequencies). A histogram
dominated by a single value — zero — has *low* entropy, because the entropy formula rewards
peaked distributions: when one outcome has probability near $1$, $- sum p_i log_2 p_i$
collapses toward $0$. The transform did not delete anything, but it moved the data from a
high-entropy arrangement to a low-entropy one, and the entropy coder of Volume II banks the
difference. *Energy compaction is the geometric face of entropy reduction.*

#gomaths("How a peaked distribution lowers entropy — a two-number check")[
  Take two ways to split a unit of probability over four symbols. *Flat:* each has
  $p = 1\/4$, so $H = -4 times (1\/4) log_2(1\/4) = -4 times (1\/4)(-2) = 2$ bits per symbol.
  *Peaked:* one symbol has $p = 0.97$, the other three share $0.01$ each. Then
  $H = -0.97 log_2 0.97 - 3 times 0.01 log_2 0.01 approx 0.043 + 0.199 = 0.24$ bits per
  symbol. Same four symbols, same total probability — but the peaked distribution costs
  *one-eighth* as many bits. After a transform, the coefficient stream looks like the
  peaked case (mostly zeros); before it, the pixel stream looks like the flat case. The
  entropy coder charges by the histogram, and the transform reshapes the histogram. That,
  in one calculation, is *why* we transform.
]

#checkpoint[
  After the DCT, a quantised $8 times 8$ block is $63$ zeros and one nonzero DC value. Why
  does an entropy coder store this in far fewer than $64$ bytes, even though there are still
  $64$ numbers?
][Because the histogram is extremely peaked — one symbol (zero) has probability $63\/64$, so
its self-information is tiny ($-log_2(63\/64) approx 0.02$ bits each). The entropy is near
zero, and a run-length plus Huffman or arithmetic coder (Volume II) spends almost nothing on
the long run of zeros, reserving its bits for the single DC value. The *count* of numbers is
unchanged; their *distribution* became nearly deterministic, and entropy charges for the
distribution, not the count.]

== The MDCT: cutting audio into blocks without hearing the seams

Audio raises a problem the image DCT does not face so sharply. A song is a continuous
stream; to transform it you must cut it into blocks. But if you DCT independent blocks and
quantise them, the tiny errors at the two sides of a block boundary differ, producing a
faint *click* at every seam — at, say, $44100$ samples per second and blocks of $1024$,
that is a click forty-odd times a second, an audible buzz. The fix in images would be to
*overlap* the blocks so the seams blend. But overlap means each sample lands in two blocks,
so you produce *twice* as many coefficients as samples — and doubling the data is the
opposite of compression.

The Modified DCT resolves this paradox with one of the most elegant tricks in signal
processing. It uses windows that overlap by exactly $50%$, *yet produces only half as many
coefficients as input samples* — so two overlapping length-$2N$ windows together yield
$2N$ coefficients for $2N$ fresh samples. No expansion at all. This property — same number
of coefficients out as samples in — is called *critical sampling*.

#definition("Critical sampling")[
  A transform is *critically sampled* when it outputs exactly as many coefficients as it
  takes in samples — no more (which would waste bits) and no fewer (which would lose
  information). The plain DCT is critically sampled; naive overlapping is *not* (it
  over-produces); the MDCT restores critical sampling *despite* overlapping.
]

How can overlapping windows not produce extra data? Because the MDCT is deliberately *not
individually invertible*: a single MDCT block, inverted alone, does *not* give back its
samples — it gives back the samples plus a ghostly, time-reversed copy of part of them,
called *time-domain aliasing*. That sounds like a disaster. The miracle is that this
aliasing is engineered so that *when you add the overlapping inverse blocks together, the
ghosts of adjacent blocks are exact negatives of each other and cancel perfectly*, leaving
only the true samples. This is *Time-Domain Aliasing Cancellation (TDAC)*.

#gomaths("Time-domain aliasing cancellation, intuitively")[
  Picture two overlapping windows $A$ and $B$, sharing their middle region. Invert block
  $A$ alone and in the shared region you get $"true" + "ghost"_A$, where the ghost is a
  folded (time-reversed) version of $A$'s samples. Invert block $B$ alone and in the same
  region you get $"true" + "ghost"_B$. The window shapes and the cosine phases are chosen so
  that $"ghost"_A = - "ghost"_B$ in the overlap. *Add the two inverse blocks:*
  $ ("true" + "ghost"_A) + ("true" + "ghost"_B) = 2 dot.c "true" + ("ghost"_A + "ghost"_B) = 2 dot.c "true" + 0, $
  and the window normalisation turns the $2$ back into $1$. The ghosts annihilate; the truth
  survives; and because each block stored only $N$ numbers, the total count never exceeded
  the number of samples. You get smooth, seam-free block transitions *and* critical
  sampling — overlap for free. The exact condition the windows must satisfy is the
  *Princen–Bradley condition*, $w(n)^2 + w(n + N)^2 = 1$ across the overlap, which the
  standard sine window $w(n) = sin[pi(n + 1\/2)\/(2N)]$ obeys.
]

#example[
  *The Princen–Bradley condition, checked numerically.* The whole TDAC trick rests on the
  windows summing correctly across the overlap, $w(n)^2 + w(n+N)^2 = 1$. Take the smallest
  case, $N = 2$, so a window is $2N = 4$ samples long, and use the sine window
  $w(n) = sin[pi(n + 1\/2)\/(2N)] = sin[pi(n + 0.5)\/4]$ for $n = 0,1,2,3$:
  $ w = (sin(pi/8), sin(3pi/8), sin(5pi/8), sin(7pi/8)) approx (0.383, 0.924, 0.924, 0.383). $
  Now check the overlap condition for the two positions $n = 0$ and $n = 1$ (pairing each
  sample with its partner $N = 2$ slots away):
  $ w(0)^2 + w(2)^2 approx 0.383^2 + 0.924^2 = 0.147 + 0.853 = 1.000, $
  $ w(1)^2 + w(3)^2 approx 0.924^2 + 0.383^2 = 0.853 + 0.147 = 1.000. $
  Both sum to exactly $1$. That is the algebraic guarantee that when neighbouring windowed,
  inverse-transformed blocks are overlap-added, the window weights of the shared region add
  to unity and the time-domain aliasing ghosts cancel — perfect reconstruction, with no
  extra coefficients stored. The elegant audio transform is, at bottom, two sine values that
  square-sum to one.
]

#algo(
  name: "Modified Discrete Cosine Transform (MDCT)",
  year: "1986 (TDAC principle, Princen–Bradley); 1987 (the MDCT, Princen–Johnson–Bradley)",
  authors: "John P. Princen, A. W. Johnson, Alan B. Bradley (University of Surrey)",
  aim: "A lapped (50%-overlapping) cosine transform that is critically sampled and gives perfect reconstruction via time-domain aliasing cancellation — the transform for streaming audio.",
  complexity: "O(n log n) via a length-N DCT-IV core plus pre/post windowing; a length-2N input yields N coefficients.",
  strengths: "No blocking/seam artifacts (overlap blends boundaries), critically sampled (no data expansion), perfect reconstruction, adaptive block sizes (long for steady tones, short for transients).",
  weaknesses: "Not individually invertible (needs the neighbouring block to cancel aliasing); window design is constrained by the Princen–Bradley condition; about one block of latency.",
  superseded: "not superseded — it is *the* transform of MP3, AAC, AC-3 (Dolby Digital), Vorbis, and Opus; essentially all modern lossy audio",
)[
  Built on the type-IV DCT, the MDCT maps $2N$ overlapping samples to $N$ coefficients.
  It is the reason an MP3 or an Opus stream has no audible block clicks despite chopping the
  music into thousands of overlapping frames per second. Codecs also switch between *long*
  windows (great frequency resolution for steady tones) and *short* windows (good time
  resolution to avoid *pre-echo* smearing a sharp drum hit backwards) — adaptive blocking,
  impossible with a non-overlapping transform.
]

#fig([Overlapping MDCT windows. Each length-$2N$ window (sine-shaped) overlaps its
neighbours by $50%$, yet each emits only $N$ coefficients. On reconstruction the
overlap-add blends the seams and the engineered time-domain aliasing cancels exactly.],
  cetz.canvas({
    import cetz.draw: *
    let win(ox, col) = {
      let pts = ()
      let M = 60
      for i in range(M + 1) {
        let t = i / M
        let v = calc.sin(calc.pi * t)
        pts.push((ox + t * 4.0, 0.9 * v))
      }
      line(..pts, stroke: 1.1pt + col)
    }
    line((-0.3, 0), (10.5, 0), stroke: 0.4pt + rgb("#999999"))
    win(0.0, rgb("#0b5394"))
    win(2.0, rgb("#9a2617"))
    win(4.0, rgb("#0b6e4f"))
    win(6.0, rgb("#783f04"))
    content((2.0, -0.45), text(size: 7pt)[$50%$ overlap])
    content((4.0, -0.45), text(size: 7pt)[$50%$ overlap])
    content((8.6, 1.1), text(size: 8pt, fill: rgb("#0b5394"))[$2N$ in, $N$ out])
  }))

#aside[
  The MDCT is why your music streams smoothly and your images do not need to. Video and
  images can tolerate the hard $8 times 8$ block grid because the eye forgives a little
  blockiness more than the ear forgives a periodic click. Audio's relentless time axis makes
  seamlessness non-negotiable — so audio got the cleverer transform. Form follows perception.
]

== Choosing a transform: the trade-off, in one view

We have met four transforms on a ladder of practicality versus optimality. It is worth
seeing them side by side, because real codecs choose among exactly these considerations.

#table(columns: (auto, 1fr, 1fr, 1fr), inset: 6pt, align: (left, left, left, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Transform*], [*Basis*], [*Cost / speed*], [*Where used*]),
  [KLT / PCA], [Data-dependent (eigenvectors of $Sigma$)], [$O(n^3)$ + must transmit basis], [the optimum; benchmark only],
  [DCT], [Fixed cosines, block-based], [$O(n log n)$, no transmission], [JPEG, video, MP3/AAC core],
  [Wavelet (DWT)], [Fixed, multi-scale], [$O(n)$, no transmission], [JPEG 2000, medical, scientific],
  [MDCT], [Fixed cosines, 50%-overlapped], [$O(n log n)$, critically sampled], [MP3, AAC, AC-3, Vorbis, Opus],
)

#keyidea[
  The KLT tells you the *best you could possibly do*; the DCT, wavelet, and MDCT are three
  fixed, fast, transmission-free *imitations* of it, each tuned to a different domain: the
  block DCT for images and video, the multi-scale wavelet where blocking must vanish, the
  overlapped MDCT for seamless audio. Every one of them is a length-preserving rotation that
  compacts energy so the quantiser can throw most of it away. Same idea, four costumes.
]

#history[
  The line of descent is tidy and worth holding onto. The KLT's theory comes from Karhunen
  (1947) and Loève (1948), with the discrete PCA going back to Hotelling (1933) and even
  Pearson (1901). Ahmed, Natarajan, and Rao published the DCT in January 1974, explicitly
  motivated as a fast KLT substitute for Markov-1 signals. Haar's wavelet dates to 1909, but
  the modern theory — smooth orthonormal wavelets (Daubechies, 1988) and the fast pyramid
  algorithm (Mallat, 1989) — arrived only in the late 1980s, just in time for JPEG 2000.
  Princen and Bradley gave the TDAC principle in 1986 and, with Johnson, the MDCT in 1987.
  Three of the four transforms that run every media file you touch were finalised in a single
  remarkable decade.
]

== Bringing it home: the transform's place in the pipeline

Step back and see where this chapter sits. Every transform codec — JPEG, MP3, H.264, and
the learned codecs of Volume IV — has the same three-stage skeleton we sketched in Chapter
21 and will build piece by piece:

#enum(
  [*Transform* (this chapter): rotate the signal into a coordinate system where energy
   compacts onto a few coefficients. _Lossless and reversible._],
  [*Quantise* (Chapter 39): round those coefficients to a coarse grid, spending fine grids
   on the coefficients that matter and coarse grids — even zero — on the rest. _The only
   lossy step._],
  [*Entropy-code* (Volume II): losslessly pack the quantised coefficients with Huffman,
   arithmetic, or ANS. _Lossless again._],
)

The transform is stage one, and it does no compression on its own — but it sets up
everything downstream. Without it, the quantiser would round *pixels*, smearing visible
noise everywhere; with it, the quantiser rounds *frequency coefficients*, and because
energy compacted, most rounds harmlessly to zero. The transform is the move that makes the
lossy step cheap. That is why half a century of codecs open with it, and why we built it
first.

#scoreboard(caption: "the transform stage adds no bytes yet — it sets up the savings",
  [Raw block ($8 times 8$, bytes)], [64], [1.00×], [the uncompressed pixel block],
  [After DCT (this chapter)], [64], [1.00×], [reversible rotation: energy compacted, no bytes saved *yet*],
  [After quantise (Ch 39)], [—], [—], [most coefficients → 0; the savings begin],
  [After entropy-code (Ch 42, toy JPEG)], [—], [—], [run-length + Huffman packs the survivors],
)

#takeaways((
  [A *transform* compresses nothing by itself — it is a perfectly reversible rotation. Its job is to re-express the signal so a few coordinates are large and the rest near zero; quantisation banks that later.],
  [*Decorrelation* removes the predict-each-other redundancy between coordinates; *energy compaction* is its payoff for correlated sources — a few big coefficients, a long tail of near-zeros.],
  [The *KLT* (eigenvectors of the covariance matrix) is provably the optimal decorrelating, energy-compacting transform — but it is signal-dependent, $O(n^3)$, and must be transmitted, so it is a benchmark, not a tool.],
  [The *DCT* (Ahmed–Natarajan–Rao, 1974) is a fixed, fast cosine transform that converges to the KLT for smooth (Markov-1) signals — near-optimal, transmission-free, and the heart of JPEG and every mainstream video codec.],
  [*Wavelets* decompose at every scale at once, avoiding the DCT's fixed-block blocking artifacts and localising edges; chosen by JPEG 2000, though the DCT won the web on simplicity.],
  [The *MDCT* overlaps audio blocks by 50% to kill seam clicks, yet stays critically sampled (no data expansion) through time-domain aliasing cancellation — the transform of MP3, AAC, AC-3, Vorbis, and Opus.],
  [In tinyzip we created `transform.py` with real `dct1d`/`idct1d` and 8×8 `dct2d`/`idct2d` that round-trip exactly and compact energy onto the DC corner — the engine Chapter 42's toy JPEG will drive.],
))

== Exercises

#exercise("38.1", 1)[
  In your own words, explain why a transform that is *perfectly reversible* (loses no
  information) can nevertheless be the key to *lossy* compression. What part of the pipeline
  actually discards data, and what does the transform do to make that discarding cheap?
]
#solution("38.1")[
  A reversible transform cannot, by itself, save any bytes — feed its output through the
  inverse and you recover the original exactly, so no information has left. Its purpose is to
  *rearrange* the signal's energy into a coordinate system where most coordinates are tiny.
  The actual discarding happens in the *quantisation* step (Chapter 39), which rounds the
  coefficients to a coarse grid; rounding tiny coefficients to zero costs almost no
  distortion. So the transform makes lossy compression cheap by ensuring that the things
  quantisation throws away were nearly zero to begin with — it concentrates the
  "throw-away-able" content into many small coefficients and the "must-keep" content into a
  few large ones.
]

#exercise("38.2", 1)[
  Compute the 1-D DCT of the constant block $bold(x) = (5, 5, 5, 5)$ by reasoning about the
  cosine waves (you should not need a calculator). Then describe qualitatively the DCT of
  $(5, 5, 5, 6)$: which coefficients become nonzero, and why?
]
#solution("38.2")[
  For $(5,5,5,5)$: only $X_0 != 0$. The DC basis is constant, so $X_0 = sqrt(1\/4)(5+5+5+5)
  = (1\/2)(20) = 10$. Every higher basis wave ($k >= 1$) has equal positive and negative
  lobes, so summed against a constant it gives exactly $0$. Result: $(10, 0, 0, 0)$ — pure
  DC, $100%$ energy compaction. For $(5,5,5,6)$: the single raised sample breaks the
  flatness, so *all* coefficients become nonzero, but $X_0$ stays large (the average rose
  slightly) and the AC terms are small (the deviation from flat is small). The DCT honestly
  reports "mostly flat, with a little high-frequency detail at one end." Energy is still
  compacted onto $X_0$, just not perfectly.
]

#exercise("38.3", 2)[
  A source has two correlated pixels with covariance matrix
  $Sigma = mat(4, 3; 3, 4)$. Find the eigenvectors and eigenvalues (use the same
  sum/difference reasoning as the worked example). What fraction of the energy does the
  larger eigenvalue carry? If you kept only the first KLT coefficient, what fraction of
  energy would you retain, and how does that compare to keeping one of the two *original*
  pixels?
]
#solution("38.3")[
  Equal diagonals, so eigenvectors are $bold(v)_1 = (1,1)\/sqrt(2)$ and $bold(v)_2 =
  (1,-1)\/sqrt(2)$. Then $Sigma bold(v)_1 = (4+3, 3+4)\/sqrt(2) = (7,7)\/sqrt(2) = 7 bold(v)_1$,
  so $lambda_1 = 7$; and $Sigma bold(v)_2 = (4-3, 3-4)\/sqrt(2) = (1,-1)\/sqrt(2) = 1
  bold(v)_2$, so $lambda_2 = 1$. The larger eigenvalue carries $7\/(7+1) = 87.5%$ of the
  energy. Keeping only the first KLT coefficient retains $87.5%$. Keeping one *original*
  pixel retains only its own variance $4$ out of the total variance $4 + 4 = 8$, i.e.
  $50%$ — and worse, you have not removed the correlation, so the kept pixel still carries
  redundant information. The KLT's rotation concentrates $87.5%$ of the energy into one
  decorrelated coordinate; the pixel basis spreads it $50\/50$. That gap is exactly the value
  of decorrelation.
]

#exercise("38.4", 2)[
  Explain *separability* for the 2-D DCT. Given that a 1-D DCT of length $8$ costs (naively)
  about $8^2 = 64$ multiply-adds, how many multiply-adds does an $8 times 8$ 2-D DCT cost
  when done separably (rows then columns)? How many would a non-separable direct
  double-sum cost? What is the speed-up factor?
]
#solution("38.4")[
  Separability means the 2-D DCT equals a 1-D DCT applied to every row, then a 1-D DCT
  applied to every column of the result (the cosine kernel factors into a product of a
  horizontal cosine and a vertical cosine). Separable cost: $8$ row transforms at $64$ each
  $= 512$, plus $8$ column transforms at $64$ each $= 512$, total $1024$ multiply-adds.
  Non-separable direct evaluation: each of the $64$ output coefficients is a double sum over
  all $64$ inputs, so $64 times 64 = 4096$ multiply-adds. Speed-up factor $= 4096 \/ 1024 =
  4 times$. (Real codecs go much further with a fast $O(n log n)$ DCT, but separability alone
  already quarters the work, and the gain grows for larger blocks.)
]

#exercise("38.5", 2)[
  Compute the full Haar wavelet transform of $(8, 4, 1, 3)$ by the average/difference
  pyramid (with the $sqrt(2)$ normalisation). Then verify that the energy is conserved.
]
#solution("38.5")[
  Level 1, pair up: averages $a = (8+4, 1+3)\/sqrt(2) = (12, 4)\/sqrt(2) = (8.485, 2.828)$;
  details $d = (8-4, 1-3)\/sqrt(2) = (4, -2)\/sqrt(2) = (2.828, -1.414)$. Level 2, recurse on
  the averages $(8.485, 2.828)$: overall average $(8.485 + 2.828)\/sqrt(2) = 11.314\/sqrt(2) =
  8.0$; coarse detail $(8.485 - 2.828)\/sqrt(2) = 5.657\/sqrt(2) = 4.0$. Full transform:
  $(8.0, 4.0, 2.828, -1.414)$. Energy check: input $8^2 + 4^2 + 1^2 + 3^2 = 64+16+1+9 = 90$;
  output $8.0^2 + 4.0^2 + 2.828^2 + 1.414^2 = 64 + 16 + 8 + 2 = 90$. Conserved exactly —
  the Haar transform is orthonormal.
]

#exercise("38.6", 2)[
  The MDCT takes $2N$ overlapping samples and produces only $N$ coefficients, yet perfectly
  reconstructs the audio. A naive overlapping scheme that kept all coefficients would produce
  $2N$ coefficients for $N$ new samples — a $2 times$ data expansion. Explain, in terms of
  time-domain aliasing cancellation, how the MDCT avoids this expansion while still using
  overlap.
]
#solution("38.6")[
  Naive overlap expands data because each sample is covered by two windows and each window
  is independently invertible, so you must store enough coefficients to invert each window
  alone — twice as many as samples. The MDCT instead makes each block emit only $N$
  coefficients for its $2N$ samples, which means a single block is *not* individually
  invertible: inverting it alone yields the true samples *plus* a folded, time-reversed
  "ghost" (time-domain aliasing). The window shapes and cosine phases are engineered (the
  Princen–Bradley condition) so that the ghost produced by one block is the exact negative of
  the ghost produced by the overlapping neighbour. When the inverse blocks are overlap-added,
  the ghosts cancel and only the true samples remain. So overlap is achieved with no extra
  coefficients: $N$ out per $N$ fresh samples in — critical sampling preserved — because the
  redundancy that overlap would normally cost is paid back by aliasing cancellation rather
  than by storing more numbers.
]

#exercise("38.7", 3)[
  Using the `transform.py` functions from this chapter's project, write a short experiment
  (pseudocode or Python) that takes an $8 times 8$ block, applies `dct2d`, zeros every
  coefficient *except* the top-left $k times k$ corner (for $k = 1, 2, 4, 8$), inverts with
  `idct2d`, and reports the reconstruction error and the fraction of energy retained at each
  $k$. Predict the shape of the error-vs-$k$ curve for a smooth block versus a noisy block.
]
#solution("38.7")[
  ```python
  import math
  from tinyzip.transform import dct2d, idct2d

  def keep_corner(coeffs, k):
      return [[coeffs[i][j] if (i < k and j < k) else 0.0
               for j in range(8)] for i in range(8)]

  def experiment(block):
      coeffs = dct2d(block)
      total_e = sum(coeffs[i][j] ** 2 for i in range(8) for j in range(8))
      for k in (1, 2, 4, 8):
          kept = keep_corner(coeffs, k)
          recon = idct2d(kept)
          err = math.sqrt(sum((block[i][j] - recon[i][j]) ** 2
                              for i in range(8) for j in range(8)))
          kept_e = sum(kept[i][j] ** 2 for i in range(8) for j in range(8))
          print(f"k={k}: err={err:.3f}, energy kept={100 * kept_e / total_e:.1f}%")
  ```
  *Predicted curves.* For a *smooth* block, energy is compacted onto the top-left corner, so
  even $k = 2$ retains nearly all the energy and the error drops almost to zero immediately —
  a steep early fall, then flat. For a *noisy* block, energy is spread across all
  frequencies, so the retained-energy curve climbs slowly and roughly in proportion to $k^2$
  (the number of kept coefficients), and the error falls slowly — there is no compaction to
  exploit. This is energy compaction made visible: the steeper the smooth block's curve, the
  more compressible the data, exactly as the KLT theory predicts.
]

#exercise("38.8", 3)[
  *Why cosines, not the KLT, for real images.* A first-order Markov source with correlation
  $rho$ has covariance $Sigma_(i j) = rho^(abs(i-j))$. It is a known result that as
  $rho -> 1$ the eigenvectors of this $Sigma$ converge to the DCT basis. Argue qualitatively
  why this makes the DCT an excellent practical choice for photographs (where adjacent pixels
  are highly correlated, $rho approx 0.9$–$0.98$), and identify two concrete costs you avoid
  by using the fixed DCT instead of computing the true KLT per image.
]
#solution("38.8")[
  Photographs are smooth almost everywhere — adjacent pixels are nearly equal — which is
  exactly the high-$rho$ regime where the Markov-1 model is accurate and its KLT eigenvectors
  are essentially the DCT cosines. So for the vast majority of natural image blocks the DCT
  *is* the KLT to within a tiny error: you get near-optimal decorrelation and energy
  compaction from a fixed basis. The two concrete costs you avoid: (1) *computation* — you
  skip estimating the per-image covariance matrix and finding its eigenvectors, an $O(n^3)$
  job per block, replacing it with a fixed $O(n log n)$ fast DCT; and (2) *transmission* —
  the KLT basis depends on the image, so a true-KLT codec would have to send the entire basis
  ($64$ vectors of $64$ numbers for $8 times 8$ blocks) to the decoder, often costing more
  than the data it saves. The DCT's basis is built into both encoder and decoder, so nothing
  is transmitted. Near-optimal quality, none of the cost: that is why the "impractical" KLT
  became the universal DCT.
]

== Further reading

- #link("https://ieeexplore.ieee.org/document/223784")[Ahmed, N., Natarajan, T. & Rao, K. R. (1974). _Discrete Cosine Transform_. IEEE Transactions on Computers 23(1), 90–93.] — the original three-page paper that launched transform coding.
- #link("https://spectrum.ieee.org/compression-algorithms")[Ahmed, N. & IEEE Spectrum. _How I Came Up With the Discrete Cosine Transform_.] — Ahmed's own account, including the rejected grant proposal.
- #link("https://en.wikipedia.org/wiki/Modified_discrete_cosine_transform")[Princen, J. P. & Bradley, A. B. (1986); Princen, Johnson & Bradley (1987).] — the TDAC and MDCT papers (IEEE Trans. ASSP 34(5); ICASSP 1987).
- #link("https://arxiv.org/abs/2202.06533")[Yang, Y., Mandt, S. & Theis, L. (2023). _An Introduction to Neural Data Compression_.] — connects the classical transform-coding pipeline of this chapter to the learned transforms of Chapter 57.
- Mallat, S. (2008). _A Wavelet Tour of Signal Processing_ (3rd ed.), Academic Press — the canonical, thorough treatment of wavelets and multi-resolution.
- Rao, K. R. & Yip, P. (1990). _Discrete Cosine Transform: Algorithms, Advantages, Applications_, Academic Press — everything about the DCT, including the fast algorithms our project omits.

#bridge[
  We now have a transform that piles a signal's energy onto a handful of coefficients —
  but a reversible rotation alone, as the scoreboard just confirmed, saves not one byte. The
  bytes appear only when we *throw coefficients away*: round the big ones coarsely, the small
  ones to zero, and never look back. That irreversible rounding is *quantisation*, the single
  lossy step in every transform codec, and the knob that walks us along Shannon's
  rate–distortion curve. Chapter 39 builds it from scratch — uniform and non-uniform scalar
  quantisers, the Lloyd–Max optimum, dead-zones, and the leap to *vector* quantisation that
  will carry us all the way to the VQ-VAE tokenizers of Volume IV. The transform has set the
  table; now we decide what to keep.
]
