#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Scientific and Floating-Point Compression

#epigraph[
  All models are wrong, but some are useful — and a useful model does not need
  seventeen significant digits.
][George E. P. Box (paraphrased)]

Imagine a climate simulation that runs for three months on ten thousand processor
cores. At midnight on the last day it finishes, and the output lands on disk: one
hundred terabytes of air-temperature readings, each stored as a 64-bit
floating-point number to full precision. The scientists need to archive that data
for twenty years and share it with colleagues around the world. If they try to
gzip it, they barely gain 2 percent. They need something completely different —
and that is exactly what this chapter is about.

The problem with scientific data is not that it is random; it is that it is
*almost but not quite* regular. Neighboring temperatures are similar, adjacent
pressures follow smooth curves, and most of the low-order bits in every float are
effectively noise introduced by floating-point rounding during the computation.
Three families of tools have been designed specifically to exploit this structure:
*lossless float-aware codecs* (FPC, Blosc) that rearrange the bytes of floats so
that a conventional compressor can find patterns; *error-bounded lossy codecs*
(zfp, SZ) that let the scientist trade a small, guaranteed, controlled error for
compression ratios that can reach 100-to-1; and the *integration layer* (HDF5
filter plugins, NetCDF chunking) that connects these codecs to the file formats
that scientists actually use.

No deep neural networks appear in this chapter. The compression power here comes
from understanding what floating-point numbers look like on the inside — and from
being smart about what "close enough" means when the data is already an
approximation of the physical world.

#recap[
  Chapter 38 introduced the Discrete Cosine Transform (DCT) and explained how a
  block transform decorrelates neighboring signal values. Chapter 39 showed scalar
  quantization: rounding a continuous value to the nearest grid point and storing
  an integer index. Chapter 42 (JPEG) combined both ideas: DCT to decorrelate,
  quantization to discard, entropy coding to compact. In this chapter, zfp does
  almost exactly the same pipeline — but in one, two, or three dimensions, on
  doubles instead of integers, and with the user setting the error budget rather
  than accepting JPEG's fixed quality table. Chapter 63 met quantization again
  from the model-compression angle: how do we reduce the precision of neural
  network weights? Here we ask the same question about simulation arrays. Finally,
  Chapters 67–69 will extend the "know-your-data" philosophy to columnar
  databases, time-series, and genomic sequences.
]

#objectives((
  "Explain why general-purpose compressors fail on floating-point simulation data",
  "Read and interpret the IEEE 754 double-precision bit layout",
  "Describe how byte-shuffling (Blosc) and FPC exploit float structure losslessly",
  "Walk through the zfp pipeline: block partitioning, decorrelating transform, bit-plane coding, truncation",
  "Explain the SZ pipeline: Lorenzo predictor, error quantization, entropy coding",
  "Distinguish absolute-error bounds from relative-error bounds and know when each matters",
  "Understand what random access into a compressed array means and why zfp offers it",
  "Know the main 2024–2026 developments: GPU-native cuSZ-i, topology-preserving bounds, HDF5 plugin integration",
))

== Why Floating-Point Data Resists General Compression

Pull out any line of weather-model output and you might see a temperature value
like $286.73158462903$ Kelvin. Compress it with gzip, and you will notice
something uncomfortable: gzip barely helps. In fact, on typical double-precision
HPC arrays, gzip achieves compression ratios between 1.0× and 1.3× — barely
better than storing the raw bytes directly. Why?

The answer lies in the *mantissa bits*. Let us open up the hood of the
floating-point format.

#gomaths("IEEE 754 Double-Precision Floating Point")[
  Chapter 13 introduced floating point as scientific notation in binary; here is the
  exact bit layout we will exploit. Every 64-bit (`double`) floating-point number is
  split into three fields:

  - *Sign* (1 bit): 0 = positive, 1 = negative.
  - *Exponent* (11 bits): a power of 2, biased by 1023. The stored value $e$ means a scale of $2^(e-1023)$.
  - *Mantissa* (52 bits): the fractional significant digits, with an implicit leading 1 bit (so 53 bits of significance total).

  #align(center)[
    #table(
      columns: (1fr, 2fr, 6fr),
      inset: 6pt,
      fill: (_, row) => if row == 0 { rgb("#d0e8f4") } else { none },
      [*Field*], [*Bits*], [*Meaning*],
      [Sign], [1], [0 = positive, 1 = negative],
      [Exponent], [11], [scale = $2^("stored" - 1023)$],
      [Mantissa], [52], [fractional digits after the implicit 1.],
    )
  ]

  The value represented is: $(-1)^s times 1.m times 2^(e-1023)$

  *Worked example.* The number 1.5 in double precision:
  - Sign = 0 (positive)
  - $1.5 = 1.1_2 times 2^0$, so exponent stored = $0 + 1023 = 1023 = 01111111111_2$
  - Mantissa = $1000...0_2$ (the ".1" after the implicit leading 1)

  The full 64-bit pattern: `0 01111111111 1000000000000000000000000000000000000000000000000000`

  Why does this matter for compression? The *exponent bits* of nearby values are often identical (they live in the same power-of-2 range). The *high mantissa bits* are also similar. But the *low mantissa bits* of a simulation result look essentially random — they accumulate rounding errors from millions of arithmetic operations. Random bits do not compress. Byte-by-byte, the low-order bytes of the mantissa look like noise to gzip's Lempel-Ziv dictionary. The first insight of scientific compression is: *rearrange the bytes so that similar bytes land next to each other*.
]

Think of it this way. If you lay one thousand temperature values end to end in
memory, the bytes are interleaved: byte 0 of value 0, byte 1 of value 0, ...,
byte 7 of value 0, byte 0 of value 1, etc. Byte 0 of every temperature is the
sign-plus-top-exponent byte — nearly identical across all values. Byte 7 of every
temperature is the lowest-order mantissa byte — essentially random noise. They are
seven bytes apart and gzip cannot see the pattern.

The solution is *byte-shuffling*: transpose the byte array so that all the byte-0s
of every value come first, then all the byte-1s, and so on. Now the similar bytes
are contiguous, and a standard entropy coder can compress them effectively.

== Blosc and Byte-Shuffling: Lossless Float Compression

Blosc (created by Francesc Alted, version 1.0 in 2010, with C-Blosc2 released in
2021) is not strictly a compressor — it is a *meta-compressor* and a *pipeline*. It
applies a *shuffle filter* to rearrange bytes (or bits), then feeds the result to a
fast byte-level compressor (LZ4, Zstandard, or Snappy). The combination runs in
multiple threads and is specifically designed to be faster than a raw
`memcpy` call by keeping data in CPU cache.

#keyidea[
  Blosc's shuffle filter reorders the $N$ values $times$ $k$ bytes/value array from
  row-major (value-major) order to column-major (byte-position-major) order.
  After shuffling, byte position $b$ across all values occupies a contiguous run of
  $N$ bytes. That run has much lower entropy and compresses 3–10× better than the
  shuffled version.
]

There is a stronger variant: *bit-shuffling* (the `bitshuffle` library by Kiyoshi Masui, 2015,
later integrated into C-Blosc2). Instead of rearranging bytes, it rearranges
*individual bits*: bit 63 of all values first, then bit 62, and so on. For 64-bit
doubles the sign bit and the exponent bits cluster at the front where they are
highly compressible; the noisy low mantissa bits go to the end where they cannot be
compressed but at least they are isolated.

#fig(
  [Byte-shuffling a block of four 4-byte floats. Before shuffling, bytes from
   different fields are interleaved. After shuffling, each column (sign, exponent,
   high-mantissa, low-mantissa) forms a contiguous run that a byte-level compressor
   can exploit.],
  cetz.canvas({
    import cetz.draw: *

    // Four 4-byte floats, before shuffle (row-major)
    let colors = (
      rgb("#b3d9f7"), // blue: sign+exp
      rgb("#b3d9f7"),
      rgb("#c8e6c9"), // green: high mantissa
      rgb("#fff9c4"), // yellow: low mantissa
    )
    let labels = ([S/E], [E/M], [M], [m])

    // "Before" grid: 4 rows x 4 cols
    content((0, 3.5), text(weight: "bold")[Before: interleaved], anchor: "west")
    for row in range(4) {
      content((-0.8, 3.0 - row * 0.6), [v#str(row)], anchor: "east", padding: 2pt)
      for col in range(4) {
        rect(
          (col * 0.9 + 0.1, 2.7 - row * 0.6),
          (col * 0.9 + 0.9, 3.1 - row * 0.6),
          fill: colors.at(col), stroke: 0.5pt + gray,
        )
        content(
          (col * 0.9 + 0.5, 2.9 - row * 0.6),
          text(size: 7pt)[#labels.at(col)],
        )
      }
    }

    // Arrow
    content((2.0, 0.7), text(size: 13pt, fill: rgb("#0b5394"))[↓ shuffle], anchor: "west")

    // "After" grid: 4 cols (byte positions) as rows
    content((0, 0.3), text(weight: "bold")[After: by byte position], anchor: "west")
    for col in range(4) {
      content((-0.8, -0.1 - col * 0.6), [B#str(col)], anchor: "east", padding: 2pt)
      for row in range(4) {
        rect(
          (row * 0.9 + 0.1, -0.4 - col * 0.6),
          (row * 0.9 + 0.9, -0.0 - col * 0.6),
          fill: colors.at(col), stroke: 0.5pt + gray,
        )
        content(
          (row * 0.9 + 0.5, -0.2 - col * 0.6),
          text(size: 7pt)[#labels.at(col)],
        )
      }
    }
  })
)

On typical climate simulation data, Blosc with bit-shuffle and LZ4 achieves
compression ratios around 2–4× while running at 2–8 GB/s — fast enough to
decompress data faster than it can arrive from disk. This is the point: Blosc's
goal is not maximum ratio but *effective bandwidth*, making compressed storage
faster than uncompressed I/O.

#algo(
  name: "Blosc (Block-Compress Library)",
  year: "2010 (v2.0: 2021)",
  authors: "Francesc Alted; community contributors",
  aim: "Multi-threaded lossless meta-compressor with byte/bit-shuffle pre-filter for floating-point scientific data",
  complexity: "O(N) compress and decompress; multi-threaded; cache-friendly block processing",
  strengths: "Extremely fast (can exceed memcpy bandwidth); plug-in codec (LZ4, Zstd, Snappy); integrates into HDF5/Zarr/NumPy; lossless",
  weaknesses: "Modest compression ratios (2–4×) on general float data; no error-bound semantics; shuffling helps least on truly random data",
  superseded: "Not superseded; used alongside error-bounded codecs for lossless needs",
)[
  Blosc splits the input into *blocks* (typically 256 KB) that fit in L2 cache, applies
  the shuffle/bitshuffle filter within each block, then compresses each block
  independently in a thread pool. Decompression is symmetric. C-Blosc2 (2021) added
  64-bit super-chunks, a richer filter pipeline, and plugin support for third-party
  codecs.
]

=== FPC: Predicting the Next Float

A contemporaneous approach to lossless float compression is *FPC* (Floating-Point
Compressor), introduced by Martin Burtscher and Paruj Ratanaworabhan in 2009. FPC
does not shuffle bytes; instead it *predicts* each double from previously seen
values and stores only the difference (the *residual*) between the prediction and
the actual value.

FPC maintains two predictors simultaneously:
1. *FCM* (Finite Context Method): a hash-table predictor that maps the last few
   values' XOR patterns to the most likely next value — effectively a learned LZ
   dictionary for floating-point streams.
2. *DFCM* (Differential FCM): the same idea applied to the *differences* between
   consecutive values, capturing smooth trends.

At each step, FPC picks whichever predictor was correct more recently, XORs its
prediction with the actual value (so 0 means a perfect prediction), and encodes the
result. Because the XOR of two similar floats produces a number with many leading
zero bits (the differing low mantissa bits end up at the bottom), FPC can store
most values in just 1–3 bytes instead of 8.

#pyrecall[
  *XOR* (the `^` operator in Python, introduced in Chapter 17) compares two
  numbers bit by bit and outputs a 1 wherever the bits differ and a 0 wherever
  they match. So `a ^ a == 0`: a value XORed with itself is all zeros. If `a` and
  `b` are nearly equal, `a ^ b` is mostly zeros — only the bit positions where they
  actually differ are set. That is exactly why a near-perfect prediction leaves a
  long run of leading zero bits that costs almost nothing to store.
]

#keyidea[
  Predicting-then-XOR-encoding is the floating-point analogue of delta coding.
  XOR isolates the bits that differ; leading zeros tell you how many bits were
  predicted correctly. A perfect prediction produces a 64-bit zero — one byte to
  store (with a zero-run-length encoding).
]

FPC achieves compression ratios of 2–5× on smooth scientific streams and runs
significantly faster than general-purpose compressors at similar ratios. Its
limitation is that it is strictly *one-dimensional*: it only predicts from the
stream order, ignoring 2-D or 3-D spatial structure that zfp and SZ exploit.

#algo(
  name: "FPC (Floating-Point Compressor)",
  year: "2009",
  authors: "Martin Burtscher, Paruj Ratanaworabhan (Texas State University)",
  aim: "Lossless streaming compression of double-precision float arrays via dual FCM/DFCM prediction and XOR residual coding",
  complexity: "O(N) time; O(hash table size) space",
  strengths: "Very fast; lossless; good on smooth 1-D streams; handles general data without domain metadata",
  weaknesses: "1-D only (ignores multi-dimensional structure); lower ratios than error-bounded methods; less maintained after 2012",
  superseded: "Largely superseded for HPC use by SZ, zfp, and Blosc+bitshuffle; still cited as a baseline",
)[]

== Error-Bounded Lossy Compression: The Key Idea

Here is the uncomfortable truth that the previous section dances around: lossless
compression of double-precision simulation data rarely beats 3–5×. Climate models,
cosmology codes, and fluid solvers need 10×, 50×, even 100× compression just to
make archiving and sharing feasible. Getting there requires accepting some loss.

But what kind of loss is acceptable for a scientist? It is certainly not the kind
JPEG introduces in images — blurry blocks, ringing artifacts. Scientists need
something they can *reason about mathematically*: "I compressed this temperature
field, and I guarantee that no reconstructed value is more than 0.01 Kelvin away
from the original."

This is the *error-bounded lossy* paradigm. The user provides a bound $epsilon$,
and the compressor guarantees:

$ max_i abs(x_i^' - x_i) <= epsilon $

where $x_i$ is the original value and $x_i^'$ is the reconstructed value. Every
single element in the decompressed array is within $epsilon$ of the original. The
compressor can do anything it likes in between — as long as it never violates that
contract.

#definition("Absolute Error Bound")[
  The *absolute error bound* $epsilon_"abs"$ is a constant: $abs(x_i^' - x_i) <= epsilon_"abs"$ for every element $i$. It makes sense when all values are on the same physical scale (e.g., temperature in Kelvin) and a fixed tolerance like $plus.minus 0.01$ K is meaningful across the whole array.
]

#definition("Relative Error Bound")[
  The *relative error bound* $epsilon_"rel"$ is a fraction of the value's magnitude: $abs(x_i^' - x_i) <= epsilon_"rel" times abs(x_i)$. It is better when values span many orders of magnitude (e.g., pressure from 1 Pa to $10^6$ Pa), because a fixed absolute error would be either too loose for small values or too tight for large ones.
]

A useful rule of thumb: use absolute bounds when the *domain* is physically
bounded and uniform; use relative bounds when the dynamic range of the data
exceeds two to three orders of magnitude.

#checkpoint[
  A velocity field has values ranging from $10^(-4)$ m/s to $10^3$ m/s. Should you
  use an absolute or a relative error bound?
][
  Relative, because the dynamic range is $10^7$. An absolute bound of $0.001$ m/s
  would be meaningless accuracy for the small values and near-useless for the large
  ones. A relative bound of $10^(-4)$ (0.01%) treats each value proportionally.
]

== zfp: Block-Transform Coding for Scientific Arrays

*zfp* was created by Peter Lindstrom at Lawrence Livermore National Laboratory
(LLNL) and first published in December 2014 in *IEEE Transactions on Visualization
and Computer Graphics*. It remains, as of 2026, one of the two dominant error-bounded
scientific compressors. The core idea will feel familiar after Chapter 42 (JPEG): partition the
array into small blocks, apply a transform to decorrelate the block, then encode
the coefficients with controlled precision.

=== The zfp Pipeline

*Step 1: Block partitioning.* The input array is divided into non-overlapping blocks
of $4^d$ values, where $d$ is the dimensionality ($d=1$: 4 values, $d=2$: $4 times 4 = 16$,
$d=3$: $4 times 4 times 4 = 64$). Each block is processed independently, which
enables random access.

*Step 2: Floating-point alignment.* Within each block, zfp finds the largest
absolute value and aligns all values to a common exponent — essentially
representing them as scaled integers. This removes the redundant per-value exponent
field.

*Step 3: Decorrelating transform.* zfp applies a *lifting-based orthogonal
transform* along each dimension independently. This transform plays the same role
as the DCT in JPEG: it concentrates the "energy" of the block into the first few
coefficients (the low-frequency components) and pushes noise into the
high-frequency coefficients. The coefficients are then reordered in a zig-zag
pattern (again, just like JPEG) so that important coefficients come first.

*Step 4: Bit-plane coding.* The integer coefficients are encoded one *bit plane*
at a time, most-significant bit first. This is the key difference from JPEG's
entropy coding: by processing bits in order of significance, zfp can stop at
any point and still have a valid approximation. In *fixed-accuracy mode*, zfp
stops writing bit planes once all remaining unwritten bits contribute less than
$epsilon$ to any coefficient — the error bound is satisfied. In *fixed-rate mode*,
it stops after writing a fixed number of bits per block regardless of error.

*Step 5: Output.* The compressed block is written contiguously. Because each block
is fixed-size in fixed-rate mode, zfp supports *random access*: to read element
$(i, j, k)$, compute which block contains it, seek to that block's offset (a simple
multiplication), decompress the block, and extract the element. No need to scan the
whole array.

#fig(
  [The zfp pipeline for a 4×4 two-dimensional block. Floating-point values are aligned
   to a common exponent, transformed, zig-zag reordered, and bit-plane coded until the
   error budget is spent.],
  cetz.canvas({
    import cetz.draw: *

    let boxes = (
      ((0,0), (1.6,0.7), [*4×4 block*\ float64], rgb("#d0e8f4")),
      ((2.0,0), (3.8,0.7), [*Align\ exponent*], rgb("#c8e6c9")),
      ((4.2,0), (5.8,0.7), [*Transform\ (lifting)*], rgb("#ffe0b2")),
      ((6.2,0), (7.8,0.7), [*Zig-zag\ reorder*], rgb("#f3e5f5")),
      ((8.2,0), (9.8,0.7), [*Bit-plane\ code*], rgb("#fff9c4")),
    )
    for (a, b, lbl, col) in boxes {
      rect(a, b, fill: col, stroke: 0.7pt + gray, radius: 3pt)
      content(((a.at(0) + b.at(0)) / 2, (a.at(1) + b.at(1)) / 2),
        text(size: 7.5pt)[#lbl])
    }
    for i in range(4) {
      let x1 = boxes.at(i).at(1).at(0)
      let x2 = boxes.at(i+1).at(0).at(0)
      let y = 0.35
      line((x1, y), (x2, y), mark: (end: ">", size: 5pt))
    }
    // stop arrow
    content((9.8, 0.35), text(size: 7pt, fill: rgb("#9a2617"))[ → stop when $epsilon$ met], anchor: "west")
  })
)

#algo(
  name: "zfp",
  year: "2014",
  authors: "Peter Lindstrom (LLNL)",
  aim: "Error-bounded lossy compression of 1-D/2-D/3-D floating-point arrays with random-access decoding via block transform + bit-plane coding",
  complexity: "O(N) compress and decompress; each block is O(1) independently",
  strengths: "Random access to individual elements; supports fixed-rate, fixed-accuracy, and fixed-precision modes; very fast (CPU SIMD); widely integrated (HDF5, NetCDF, Python h5py); 1-D through 4-D arrays",
  weaknesses: "Block size fixed at $4^d$; transform less effective for very turbulent or discontinuous data; absolute error bound only at the block level (not guaranteed per-element in some modes)",
  superseded: "Continues active development; coexists with SZ3",
)[
  zfp 1.0.0 was released in 2019, adding Python bindings, CUDA/OpenMP acceleration,
  and a 4-D mode. A 2025 paper by Fox and Lindstrom documented statistical bias in
  zfp's rounding errors and proposed corrections. The project is maintained at
  LLNL under a BSD license and distributed as a plugin for HDF5, NetCDF-4, and the
  Zarr array format.
]

=== A Worked Example: Compressing a 1-D Block

Let us trace through zfp on a tiny 4-element block. Suppose we have temperatures
(already aligned to a common exponent as integers after step 2):

$ [100, 97, 103, 99] $

Step 3, the lifting transform along 1-D. A *lifting scheme* is just a way of
rewriting a transform as a sequence of in-place "predict and update" steps using
only additions, subtractions, and shifts — no multiplications, so it is exact and
reversible on integers. zfp's 1-D transform is a four-point lifting scheme. For
intuition, ignore the exact coefficients and think of it as separating the four
values into:
- one *coarse* number that captures the overall level of the block, and
- three *detail* numbers that capture how much each value wiggles around that level.

For our block $[100, 97, 103, 99]$ the four values sit around an average of
$(100+97+103+99)/4 = 99.75$, and they never stray more than about 3 from it. So
after the transform we get roughly:
- one coarse coefficient near $400$ (the sum, $approx 4 times 99.75$), and
- three detail coefficients that are *small* — on the order of $plus.minus 3$,
  because the values barely deviate from their average.

Here is the payoff. The coarse coefficient is large and must be stored with full
precision, but there is only *one* of it. The three detail coefficients are small
numbers, so their most-significant bits are all zero — and bit-plane coding writes
the most-significant bit plane of the whole block first. With an error bound of
$epsilon = 5$, we can simply *stop* before ever reaching the low bit planes that
encode those tiny $plus.minus 3$ wiggles: dropping detail smaller than the bound is
exactly what "fixed-accuracy" means. We keep the coarse level, discard most of the
detail bits, and the block round-trips to within $plus.minus 5$ — roughly 4×
compression on this block alone. On a real array, where most blocks are this smooth,
those savings compound.

In practice on 3-D arrays of smooth simulation data, zfp in fixed-accuracy mode
($epsilon = 10^(-4)$ relative) achieves 10–50× compression. On highly turbulent
data, ratios drop to 2–5×.

#pitfall[
  zfp's error bound is guaranteed *per block*, not unconditionally per element in
  all usage modes. In *fixed-rate mode*, the error bound is not guaranteed — you
  are just allocating a fixed bit budget. Always use *fixed-accuracy mode* when you
  need the mathematical guarantee.
]

== SZ: Prediction-Quantization for Scientific Data

The *SZ* (SZ1 through SZ3) family, created by Sheng Di and Franck Cappello at
Argonne National Laboratory and first published at IEEE IPDPS 2016, takes a
completely different approach from zfp. Rather than a block transform, SZ uses
*pointwise prediction*: estimate each value from its already-reconstructed
neighbors, quantize the *residual* (the difference) to meet the error bound, then
entropy-code the integers.

=== The SZ Pipeline

*Step 1: Prediction.* For each element $x_i$, SZ predicts $hat(x)_i$ from its
neighbors. The original SZ used *curve fitting* (linear or quadratic); SZ 1.4+
adopted the *Lorenzo predictor*.

#definition("Lorenzo Predictor")[
  The *Lorenzo predictor* (introduced by Ibarria, Lindstrom, Rossignac, and Szymczak in 2003) estimates a value from a simple weighted combination of its already-decoded neighbors. In one dimension: $hat(x)_i = 2 x_(i-1) - x_(i-2)$ (linear extrapolation). In two dimensions: $hat(x)_(i,j) = x_(i-1,j) + x_(i,j-1) - x_(i-1,j-1)$ (a bilinear extrapolation from three neighbors). In three dimensions the formula extends similarly. For smooth data, this prediction is extremely accurate — the residual is tiny.
]

*Step 2: Quantization.* The residual $r_i = x_i - hat(x)_i$ is divided by the
error bound $epsilon$ and rounded to the nearest integer:

$ q_i = "round"(r_i / epsilon) $

This integer $q_i$ is small for smooth data. It can be exactly reconstructed to
within $epsilon$ of the original value. If $q_i$ falls outside a predefined
range (the residual was too large to quantize reliably), the original value is
stored losslessly as a fallback — SZ calls these *unpredictable* values.

*Step 3: Entropy coding.* The integer sequence $q_i$ is Huffman-coded or
arithmetic-coded. On smooth simulation data, $q_i = 0$ for most elements (the
prediction was nearly perfect), so the distribution of $q_i$ values is extremely
peaked at zero — high redundancy, high compression.

*Step 4: Metadata and fallback.* The Huffman table, unpredictable values, and
array dimensions are written into the header.

#algo(
  name: "SZ (Sheng Di / Cappello Compressor) — SZ3",
  year: "2016 (SZ1); 2022 (SZ3 modular framework)",
  authors: "Sheng Di, Franck Cappello (Argonne National Laboratory); Kai Zhao, Robert Underwood and collaborators",
  aim: "Error-bounded lossy compression via pointwise prediction + error-quantization + entropy coding",
  complexity: "O(N) compress and decompress; entropy coding step uses Huffman or zstd",
  strengths: "Often higher ratio than zfp on smooth data; strong theoretical guarantees per-element; SZ3 is modular (swap predictor, quantizer, or coder); works on 1-D to 5-D arrays",
  weaknesses: "Sequential per-element prediction is harder to parallelize than zfp's independent blocks; no random access (must decompress from start); slightly slower decompression",
  superseded: "SZ3 is the current framework; older SZ1/SZ2 are largely replaced",
)[
  *SZ3* (2022) is a modular rewrite by Kai Zhao, Sheng Di, Maxim Dmitriev, and
  colleagues. The user assembles a pipeline: choose a predictor (Lorenzo, cubic
  spline, learned), a quantizer (uniform, logarithmic), and an entropy coder
  (Huffman, Zstandard, arithmetic). This separation of concerns makes SZ3 a
  research platform as much as a compressor.
]

=== Comparing zfp and SZ on the Same Data

#scoreboard(
  caption: "Error-bounded lossy compression of a synthetic 3-D temperature field (1000³ doubles, ~8 GB raw; absolute bound ε = 1e-3 × value range)",
  [Method], [Compressed bytes], [Ratio], [Notes],
  [Raw float64], [8,000,000,000], [1.0×], [Baseline — uncompressed],
  [gzip (level 6)], [7,760,000,000], [1.03×], [Near-useless on float arrays],
  [Blosc + bitshuffle + LZ4], [2,400,000,000], [3.3×], [Lossless; fast; byte-shuffle exploits exponent runs],
  [FPC], [2,000,000,000], [4.0×], [Lossless; good on smooth 1-D fields],
  [zfp fixed-accuracy], [320,000,000], [25×], [Error-bounded; random access; transform decorrelates],
  [SZ3 Lorenzo + Huffman], [240,000,000], [33×], [Error-bounded; per-element guarantee; higher ratio on smooth fields],
)

The scoreboard tells a clear story. Lossless methods max out around 4×; error-bounded
methods reach 25–33× on the same data. The price is that scientists must decide —
and justify — what "close enough" means for their application.

=== When Does Each Win?

Both tools are in production across major HPC centers (LLNL, Argonne, NCAR, NERSC),
often available as options in the same file write call. The choice depends on the
data:

- *zfp excels* when you need random access to compressed data (e.g., interactive
  visualization of a time-varying 3-D field), or when the data has block-level
  spatial coherence (atmospheric pressure).
- *SZ excels* when the data is very smooth and the Lorenzo predictor is accurate
  (e.g., velocity fields from laminar flow simulations), typically giving 10–20%
  higher ratios than zfp at the same error bound.
- *Turbulent or discontinuous data* (shock waves, combustion fronts) is hard for
  both: the prediction residuals are large, and ratios drop toward 2–5×. Here,
  domain-specific preprocessing (aligning to the shock surface) helps more than
  codec tuning.

#gopython("NumPy Arrays and struct Module")[
  In Python, scientific data almost always lives in a *NumPy array* — a
  contiguous block of memory holding values of a single data type. You can
  inspect the raw bytes of a float with the `struct` module:

  ```python
  import struct, numpy as np

  x: float = 286.731  # a temperature in Kelvin
  raw: bytes = struct.pack(">d", x)   # ">d" = big-endian double (8 bytes)
  print(raw.hex())
  # Output: 4071ebd70a3d70a4
  # First byte 40 = sign(0) + top 7 exponent bits
  # Last byte a4 = low mantissa noise

  # NumPy can view an array's raw bytes directly:
  arr = np.array([286.731, 287.012, 286.995], dtype=np.float64)
  as_bytes: bytes = arr.tobytes()   # 24 bytes (3 × 8)
  print(len(as_bytes))
  ```

  The `struct.pack` / `struct.unpack` pair is the Python way to convert between
  Python numbers and their raw byte representations. `">d"` means big-endian
  (`>`) 64-bit double (`d`). In NumPy, `.tobytes()` gives you the raw memory
  and `.frombuffer(raw, dtype=np.float64)` converts back.
]

== Byte-Splitting and Bit-Packing: Two More Lossless Tricks

Before leaving lossless techniques, two more tricks deserve mention because they
appear frequently in scientific data pipelines.

*Byte-splitting* is a variant of byte-shuffling that takes a step further: it
groups all the bytes at position 0 together, all at position 1 together, etc. —
then *separately compresses each group*. The sign-plus-high-exponent group is nearly
constant (compresses to almost nothing); the low-mantissa group is random (barely
compresses). By splitting them, a smart compressor can allocate more effort to the
compressible groups and skip the incompressible ones quickly.

*Bit-packing* applies when the values are integers or when the floating-point values,
after quantization, fit in fewer bits than a full float. If all quantized residuals
fit in 12 bits, there is no reason to store them in 32-bit integers. Libraries like
PyTables, NetCDF-4, and SZ3 all offer bit-packing as a transparent filter.

#gopython("Illustrative Byte-Shuffle in Python")[
  Here is a simple Python illustration of byte-shuffling a list of 4-byte
  integers (the idea extends identically to 8-byte doubles):

  ```python
  import struct

  def byte_shuffle(values: list[int], item_size: int = 4) -> bytes:
      """
      Transpose a list of `item_size`-byte integers from value-major
      to byte-position-major order.
      Input:  [v0, v1, v2, ...]  each stored as item_size bytes
      Output: [b0_of_v0, b0_of_v1, ..., b1_of_v0, b1_of_v1, ...]
      """
      raw: list[bytes] = [v.to_bytes(item_size, "big") for v in values]
      # raw[i][j] = byte j of value i
      # After shuffle: byte j of all values come together
      shuffled: bytearray = bytearray()
      for j in range(item_size):
          for i in range(len(raw)):
              shuffled.append(raw[i][j])
      return bytes(shuffled)

  def byte_unshuffle(data: bytes, n_values: int, item_size: int = 4) -> list[int]:
      """Inverse of byte_shuffle."""
      result: list[int] = []
      for i in range(n_values):
          val_bytes = bytes(data[j * n_values + i] for j in range(item_size))
          result.append(int.from_bytes(val_bytes, "big"))
      return result

  # Quick self-test
  original = [0x3F800000, 0x3F866666, 0x3F8CCCCD, 0x3F933333]
  shuffled = byte_shuffle(original)
  assert byte_unshuffle(shuffled, len(original)) == original
  print("Round-trip OK:", [hex(v) for v in original])
  ```

  Notice that the first four bytes of `shuffled` are all `0x3F` — identical, and
  therefore compressible to nearly one byte. The last four bytes vary significantly.
  This is the byte-shuffle effect.
]

== The Integration Layer: HDF5, NetCDF, and Zarr

Real scientists do not call `zfp.compress(arr)` in a Python script and then write
the result to a custom binary file. They write to *HDF5* or *NetCDF-4* — two
standard scientific data formats used across every domain from climate to particle
physics to genomics — and they want compression to be *transparent*: the file still
looks like a normal array; the compression happens silently.

HDF5 achieves this through its *filter pipeline*. When you define a dataset in an
HDF5 file, you can attach a sequence of filters. Every filter has a registered ID.
The built-in filters include gzip (ID 1), shuffle (ID 2), and SZIP (ID 4).
Third-party filters — including zfp (ID 32013) and SZ (ID 32017) — are loaded as
dynamic shared libraries at runtime. The user writes:

```python
import h5py, hdf5plugin, numpy as np

with h5py.File("output.h5", "w") as f:
    f.create_dataset(
        "temperature",
        data=my_array,
        **hdf5plugin.ZFP(accuracy=0.001),   # absolute error bound
    )
```

And the file stores compressed data that any HDF5-aware program can read, on any
machine, even without knowing about zfp — because the filter ID is stored in the
file header and the HDF5 library loads the plugin automatically.

*NetCDF-4* is built on HDF5 and inherits the same filter pipeline. *Zarr* (widely
used in the Python scientific ecosystem, especially for cloud storage) has its own
codec system but also supports zfp and Blosc through the `numcodecs` library.

#history[
  HDF5 (Hierarchical Data Format version 5) was developed by the National Center
  for Supercomputing Applications (NCSA) in the 1990s and transferred to the HDF
  Group in 2005. It stores multi-dimensional arrays, metadata, and groups in a
  single portable binary file. NetCDF (Network Common Data Form), maintained by
  Unidata/UCAR, predates HDF5 but since version 4 (2008) uses HDF5 as its storage
  layer. Together, HDF5 and NetCDF-4 are the lingua franca of computational science:
  the same file format is used by NASA's earth observation archives, CERN's physics
  simulations, and NOAA's weather models.
]

== The 2024–2026 Frontier

Several developments since 2024 are worth knowing about.

=== GPU-Native Compressors

The most active front is running compression *on the GPU* to avoid the
GPU-to-CPU data movement bottleneck. Two SC24 (Supercomputing 2024) papers from
the SZ group stand out:

- *cuSZ-i* (Liu, Tian, Wu et al., 2024): GPU-native SZ with a multi-level
  interpolation predictor that achieves higher compression ratios than the Lorenzo
  predictor on structured 3-D data, while sustaining >10 GB/s throughput on a
  single GPU. The key insight is that interpolation (fitting a spline through coarser
  grid points) is more accurate than extrapolation (the Lorenzo approach) for smooth
  fields.

- *cuSZp2* (Huang, Di et al., 2024): designed for *extreme throughput* — a
  single-pass, single-kernel design that reaches >200 GB/s on high-end GPUs, at
  the cost of some ratio compared to cuSZ-i. Aimed at online compression during
  simulation checkpointing where the bottleneck is compute, not I/O.

=== Topology-Preserving Bounds

Scientists increasingly realize that pointwise error bounds are necessary but not
sufficient. A wind field reconstructed within $plus.minus 0.01$ m/s can still have
*vortices* (swirling structures) that disappear or appear spuriously, even when
no individual value was wrong by more than $epsilon$. The emerging idea is
*feature-preserving compression*: guarantee that critical points, topological
features, or vector-field divergence-free properties survive compression.

This is a hard open problem with no deployed solution as of 2026, but it is
attracting significant research attention in the scientific visualization and HPC
communities.

=== Learned Compressors for Science

Neural-network-based scientific compressors (e.g., those built on variational
autoencoders similar to the learned image codecs in Chapters 56–58) have shown impressive
ratios on specific datasets but remain too slow and too data-specific for general
deployment. A June 2026 preprint (Residual Modeling for High-Fidelity Learned
Compression of Scientific Data) combines a learned predictor with SZ-style
residual coding, achieving higher ratios than SZ3 on climate data — but at 10–100×
the compute cost. The gap between research and deployment remains wide.

#misconception[
  "Error-bounded lossy compression violates the integrity of scientific results."
][
  Scientific simulation data is *already* an approximation of reality: it was
  produced by floating-point arithmetic on a discrete grid, with numerical schemes
  that introduce truncation error. If the compression error $epsilon$ is smaller
  than the simulation's own numerical error, the compressed-then-decompressed data
  is no less accurate than the original for any scientific purpose. Several
  published studies (e.g., Miranda et al., 2018 at SC18) have validated that
  climate and fluid simulation results computed on zfp/SZ-compressed data are
  statistically indistinguishable from results on uncompressed data, provided the
  bound is set appropriately.
]

== Choosing a Method: A Decision Guide

#figure(
  caption: [Decision guide for scientific floating-point compression.],
  table(
    columns: (2fr, 1.5fr, 1.5fr, 2fr),
    inset: 7pt,
    fill: (_, row) => if row == 0 { rgb("#d0e8f4") } else if calc.rem(row, 2) == 0 { rgb("#f4f6f8") } else { none },
    table.header(
      [*Condition*], [*Lossless?*], [*Random access?*], [*Recommended*],
    ),
    [Need exact bit-for-bit fidelity; stream is 1-D],
    [Yes], [—],
    [*FPC* (predict+XOR; fastest on 1-D streams)],

    [Need exact fidelity; data is 2-D/3-D or multi-type],
    [Yes], [—],
    [*Blosc + bitshuffle + LZ4* (multi-threaded; integrates into HDF5/Zarr)],

    [Lossy OK; need random seek into compressed array],
    [No], [Yes],
    [*zfp fixed-rate* (O(1) seek per block; good for interactive visualization)],

    [Lossy OK; maximum ratio on smooth CPU arrays],
    [No], [No],
    [*SZ3 Lorenzo + Huffman* (typically 10–20% higher ratio than zfp)],

    [Lossy OK; GPU available; checkpoint during simulation],
    [No], [No],
    [*cuSZ-i* (high ratio) or *cuSZp2* (maximum GPU throughput)],
  )
)

#aside[
  The Zarr + numcodecs ecosystem (widely used in cloud-based science, e.g., the
  Pangeo climate computing platform) supports all the codecs discussed here through
  a unified Python API. You can write a 100 TB climate dataset directly to cloud
  object storage (Amazon S3, Google Cloud Storage) in Zarr format with zfp
  compression, and any researcher in the world can read arbitrary slices without
  downloading the whole file — the random-access property of fixed-rate zfp makes
  this practical.
]

#takeaways((
  "General-purpose compressors (gzip, zstd) fail on double-precision scientific arrays because the low mantissa bits look random; ratios rarely exceed 1.3×.",
  "IEEE 754 doubles have a 1-bit sign, 11-bit exponent, and 52-bit mantissa. The exponent and high mantissa bits are compressible; the low mantissa bits are not.",
  "Byte-shuffling (Blosc) reorders bytes from value-major to byte-position-major order so that similar bytes are contiguous. With bitshuffle and LZ4, ratios of 2–4× are typical and throughput can exceed memcpy.",
  "FPC predicts each double from a two-predictor hash table, XORs with the actual value, and stores the (usually near-zero) result. It achieves 2–5× losslessly on smooth streams.",
  "Error-bounded lossy compression gives the user a mathematical guarantee: every reconstructed value is within ε of the original. Absolute bounds (fixed tolerance) suit uniform-scale data; relative bounds suit wide dynamic ranges.",
  "zfp partitions the array into 4^d blocks, aligns exponents, applies a lifting transform, zig-zag reorders, and bit-plane codes until the error budget is spent. Fixed-rate mode enables O(1) random access.",
  "SZ predicts each element with the Lorenzo predictor, quantizes the residual to integers with step size ε, and entropy-codes the integer sequence. It typically achieves higher ratios than zfp on smooth data.",
  "Both zfp and SZ integrate into HDF5/NetCDF-4/Zarr as transparent filter plugins; the application sees a normal array regardless of the underlying codec.",
  "The 2024–2026 frontier: GPU-native cuSZ-i and cuSZp2 at SC24; topology-preserving bounds as an open research problem; learned predictors inching toward deployment.",
))

== Exercises

#exercise("66.1", 1)[
  A 64-bit double stores the value $-3.14$. Without computing the exact bit pattern,
  explain: (a) what the sign bit will be, (b) roughly what range the exponent field
  will encode (since $3.14 approx 1.57 times 2^1$), and (c) which bytes will be
  most compressible and which will be least compressible in a byte-shuffled block of
  one thousand copies of $-3.14$.
]

#solution("66.1")[
  (a) Sign bit = 1 (negative). (b) $3.14 approx 1.57 times 2^1$, so the true exponent is 1, stored as $1 + 1023 = 1024 = 10000000000_2$; the exponent field occupies bits 62–52 of the 64-bit word. (c) Byte 0 (sign + top 7 exponent bits) will be identical across all one thousand copies — most compressible. Byte 1 (remaining exponent + top mantissa) will also be highly similar. Byte 7 (lowest mantissa) will vary almost randomly even for very similar values — least compressible, effectively incompressible.
]

#exercise("66.2", 1)[
  A climate dataset has pressures ranging from $100$ Pa (upper stratosphere) to
  $100\,000$ Pa (sea level). A researcher wants to use error-bounded compression
  with SZ. Should they specify an absolute error bound of $0.01$ Pa or a relative
  error bound of $10^(-4)$ (0.01%)? Explain your reasoning.
]

#solution("66.2")[
  Relative bound of $10^(-4)$ is far better here. The dynamic range spans a factor of 1000. An absolute bound of $0.01$ Pa is uselessly tight for sea-level values ($100\,000$ Pa) — it demands 7 significant digits — while being potentially too loose for upper-stratosphere values near $100$ Pa if the researcher cares about 0.01% accuracy there. A relative bound of $10^(-4)$ treats each pressure proportionally: $plus.minus 0.01$ Pa accuracy for $100$ Pa values, $plus.minus 10$ Pa accuracy for $100\,000$ Pa values — physically appropriate at every altitude.
]

#exercise("66.3", 2)[
  Trace through the SZ Lorenzo prediction for a simple 1-D array $[10.0, 10.1, 10.3, 10.6, 11.0]$ with absolute error bound $epsilon = 0.05$. For each element starting from the third, compute: the Lorenzo prediction ($hat(x)_i = 2x_(i-1) - x_(i-2)$), the residual ($r_i = x_i - hat(x)_i$), and the quantized residual ($q_i = "round"(r_i / epsilon)$). What does the distribution of $q_i$ values suggest about how well entropy coding will work?
]

#solution("66.3")[
  The first two values ($x_0, x_1$) must be stored as-is (no prior context). For the rest:

  - $i=2$: $hat(x)_2 = 2(10.1) - 10.0 = 10.2$. $r_2 = 10.3 - 10.2 = 0.1$. $q_2 = round(0.1/0.05) = 2$.
  - $i=3$: $hat(x)_3 = 2(10.3) - 10.1 = 10.5$. $r_3 = 10.6 - 10.5 = 0.1$. $q_3 = round(0.1/0.05) = 2$.
  - $i=4$: $hat(x)_4 = 2(10.6) - 10.3 = 10.9$. $r_4 = 11.0 - 10.9 = 0.1$. $q_4 = round(0.1/0.05) = 2$.

  All quantized residuals are 2 — a perfectly uniform sequence. The entropy of a perfectly uniform constant is 0 bits/symbol, so entropy coding will compress the residuals to almost nothing. This illustrates why SZ works so well on smoothly varying fields: the Lorenzo predictor extrapolates the trend, and the residuals collapse to a tiny near-constant distribution.
]

#exercise("66.4", 2)[
  zfp in fixed-rate mode stores a fixed number of bits per block, regardless of the
  actual content. This enables O(1) random access but loses the error-bound
  guarantee. Explain precisely: (a) how random access works in fixed-rate mode
  given the block offset, and (b) why the error-bound guarantee is lost.
]

#solution("66.4")[
  (a) In fixed-rate mode, every $4^d$-element block occupies exactly $R$ bits (a user-specified budget). The compressed stream is therefore a flat array of equal-size segments. The block containing element $(i, j, k)$ has index $B = floor(i/4) times n_J n_K + floor(j/4) times n_K + floor(k/4)$ (where $n_J, n_K$ are the block counts in each dimension). Its byte offset is $B times R/8$. The decoder seeks to that offset, reads $R$ bits, decompresses the block, and extracts the element. This is O(1) because the offset is a single multiplication.

  (b) The error bound arises from the bit-plane coding process stopping once the remaining bit planes contribute less than $epsilon$ to any coefficient. In fixed-rate mode, the encoder stops after $R$ bits regardless of how much error remains. If the block is complex (high-frequency content), $R$ bits might not be enough to reduce the error below $epsilon$. Conversely, if the block is very smooth, $R$ bits might be far more than needed. The truncation point is determined by the budget, not the error, so the error-bound guarantee is broken.
]

#exercise("66.5", 2)[
  The byte-shuffle function in the chapter's Python box transposes a flat list of
  integers. Extend it to work directly on a `bytes` object containing $N$ values of
  $k$ bytes each (for any $k$), and write a corresponding `byte_unshuffle` that
  round-trips. Add a self-test that checks round-trip correctness for 8-byte floats
  (using `struct.pack` to create test data).
]

#solution("66.5")[
  ```python
  import struct

  def byte_shuffle(data: bytes, item_size: int) -> bytes:
      n = len(data) // item_size
      out = bytearray(len(data))
      for b in range(item_size):
          for i in range(n):
              out[b * n + i] = data[i * item_size + b]
      return bytes(out)

  def byte_unshuffle(data: bytes, item_size: int) -> bytes:
      n = len(data) // item_size
      out = bytearray(len(data))
      for b in range(item_size):
          for i in range(n):
              out[i * item_size + b] = data[b * n + i]
      return bytes(out)

  # Self-test with 8-byte doubles
  values = [3.14159, 2.71828, 1.41421, 1.61803]
  raw = b"".join(struct.pack(">d", v) for v in values)
  shuffled = byte_shuffle(raw, 8)
  assert byte_unshuffle(shuffled, 8) == raw, "Round-trip failed!"
  print("Round-trip OK for", len(values), "doubles")
  # Inspect: first 4 bytes of shuffled = byte-0 of all four values
  print("First 4 bytes (sign+exp):", shuffled[:4].hex())
  ```
]

#exercise("66.6", 3)[
  *Research exercise.* The 2024 cuSZ-i paper claims that multi-level interpolation
  achieves higher compression ratios than the Lorenzo predictor on structured 3-D
  scientific data, while sustaining $>$10 GB/s decompression throughput on a single
  GPU. (a) Explain intuitively why a multi-level interpolation predictor should
  outperform Lorenzo for smooth fields. (b) Describe one scenario where Lorenzo
  might *outperform* interpolation. (c) What hardware and software requirements does
  a GPU-native compressor impose on a scientific workflow, and what are the
  organizational barriers to adopting it in, say, a 20-year climate archive?
]

#solution("66.6")[
  (a) Lorenzo extrapolation fits a linear trend from the immediately preceding neighbors. For a smooth field that curves gently (like an atmospheric pressure field with large-scale wave patterns), the locally linear approximation introduces a systematic bias — the residual is not zero but a small "curvature" term. Multi-level interpolation fits higher-order curves by combining values at multiple resolutions (coarse + fine), capturing the curvature and leaving a truly small residual. Intuitively: interpolation "sees" more of the field's shape; Lorenzo only sees the local slope.

  (b) Lorenzo excels on very smooth, nearly linear fields where the second derivative is tiny — e.g., a velocity component in laminar flow. In that case, interpolation's additional computation gains nothing, and Lorenzo's simplicity (one addition, one subtraction) is faster. Lorenzo also handles discontinuities (shock waves) about as poorly as interpolation, so neither has an advantage there.

  (c) Hardware requirements: a CUDA-capable NVIDIA GPU must be present at the node where data is written; the GPU compressor library must be installed and linked to the I/O stack (HDF5 VOL connector or MPI-IO). Organizational barriers: (i) Long-term archiving requires decompression decades hence — the library must be maintained or the data becomes inaccessible; GPU-native formats are less stable than CPU-native ones. (ii) Different facilities use different GPU architectures (NVIDIA A100 at some HPC centers, AMD MI300 at others); cross-architecture portability is not guaranteed. (iii) Verifying that 20-year-old data compressed with 2024 software can still be read requires keeping the software — and its GPU dependencies — alive, which conflicts with how archives work (immutable data, evolving software stack).
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/6876024")[Lindstrom, P. (2014). *Fixed-Rate Compressed Floating-Point Arrays.* IEEE TVCG 20(12).] — the original zfp paper.
- #link("https://ieeexplore.ieee.org/document/7516069")[Di, S. & Cappello, F. (2016). *Fast Error-Bounded Lossy HPC Data Compression with SZ.* IEEE IPDPS.] — the original SZ paper.
- #link("https://arxiv.org/pdf/2111.02925")[Zhao, K. et al. (2022). *SZ3: A Modular Framework for Composing Prediction-Based Error-Bounded Lossy Compressors.* arXiv:2111.02925.] — the SZ3 redesign.
- #link("https://userweb.cs.txstate.edu/~burtscher/papers/tc09.pdf")[Burtscher, M. & Ratanaworabhan, P. (2009). *FPC: A High-Speed Compressor for Double-Precision Floating-Point Data.* IEEE Transactions on Computers 58(1).] — the FPC paper (freely available).
- #link("https://blosc.org/pages/")[Blosc home page] — documentation, benchmarks, and the C-Blosc2 library.
- #link("https://dl.acm.org/doi/10.1109/SC41406.2024.00019")[Liu et al. (2024). *cuSZ-i: High-Ratio Scientific Lossy Compression on GPUs with Optimized Multi-Level Interpolation.* SC24.] — the latest GPU SZ result.
- #link("https://dl.acm.org/doi/10.1109/SC41406.2024.00021")[Huang et al. (2024). *cuSZp2: A GPU Lossy Compressor with Extreme Throughput and Optimized Compression Ratio.* SC24.] — ultra-high-throughput GPU compressor.
- #link("https://computing.llnl.gov/projects/zfp")[zfp project page at LLNL Computing] — current documentation, modes, language bindings.
- #link("https://arxiv.org/pdf/2312.10301")[FCBench: Cross-Domain Benchmarking of Lossless Compression for Floating-Point Data (2023)] — a systematic comparison of lossless float-specific methods.

#bridge[
  We have now seen how to compress floating-point simulation data by exploiting its
  physics: smoothness allows prediction; error bounds allow quantization; block
  structure allows transforms. In Chapter 67 we turn to *columnar databases* — a
  completely different domain where the physics is the schema. A table column holds
  values of one type that are related by the same logical meaning (all order IDs,
  all timestamps, all prices). That semantic structure enables dictionary encoding,
  run-length encoding, bit-packing, and delta coding to achieve 5–30× compression
  on analytical databases like Apache Parquet and ClickHouse — with no error bound
  needed, because the data is exact by definition. The "know your data" principle
  continues.
]
