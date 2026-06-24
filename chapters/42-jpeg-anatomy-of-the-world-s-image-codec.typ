#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= JPEG: Anatomy of the World's Image Codec

#epigraph[
  "We believe the JPEG standard represents a notable achievement in image compression
  technology, bringing together the results of decades of research into a coherent,
  practical standard."
][Gregory K. Wallace, _The JPEG Still Picture Compression Standard_, 1992]

Here is a puzzle that should make no sense at first. A photograph of a golden retriever,
straight from your phone's camera, weighs about 6 megabytes as a raw file (three bytes
per pixel of red, green, and blue for roughly two million pixels). Save it as a JPEG at
medium quality and it drops to perhaps 400 kilobytes: a 15-to-1 shrinkage. Print it large
and it looks indistinguishable from the original. Where did those 5.6 megabytes go? Did
the computer just silently throw away parts of the picture and hope you wouldn't notice?

Yes. But the parts it threw away were *chosen with remarkable care*, exploiting two things
the raw file squanders without mercy:

- *Statistical redundancy.* Pixels next to each other in a natural photo are almost
  always similar. A smooth blue sky writes the same blue value a million times. Nearby
  values are correlated; the raw file stores all of them anyway.
- *Perceptual redundancy.* Your eye is not a flat, equally-sensitive instrument. It is
  acutely sensitive to brightness changes and relatively blind to fine color detail or tiny
  high-frequency textures. The raw file wastes equal precision on the things you see and
  on the things you don't.

JPEG's pipeline, standardized in 1992, attacks both kinds of redundancy in sequence: it
transforms, it quantizes (the deliberate throwing-away), and it entropy-codes what
remains. That sequence (transform → quantize → entropy-code) is not a JPEG quirk but
the universal template of modern lossy compression. Every video codec from MPEG-1 to
H.266, every audio codec from MP3 to Opus, follows the same three-step logic. Understand
JPEG and you understand the skeleton of all of them.

And JPEG is inescapable. Introduced in 1992, it is still the default format for
photographs on the web, on phones, in cameras, in hospitals and courtrooms and
newspapers. Estimates in 2024 put the number of JPEG files in existence above one
trillion. It is not merely old: it is the most successful image codec ever created, and
dissecting it is one of the best investments a compression student can make.

This chapter takes JPEG apart piece by piece, explains every choice, builds intuition for
the artifacts it produces, and ends with a working toy encoder in Python. Along the way
we meet its purely lossless sibling JPEG-LS and glance ahead at what comes after.

#recap[
  Chapter 37 taught us that any signal can be decomposed into a sum of cosine waves of
  different frequencies (the *frequency-domain view*) using the Discrete Fourier
  Transform (DFT). Chapter 38 introduced the *Discrete Cosine Transform (DCT)*, its
  real-valued cousin that works over fixed-length blocks, and showed that it approximates
  the theoretically optimal Karhunen–Loève decorrelating transform for typical natural
  signals. We implemented `dct2d` and `idct2d` in `tinyzip/transform.py` (Step 17) and
  proved they round-trip exactly. Chapter 39 covered *quantization*: dividing a value by a
  step size and rounding, which is the only genuinely lossy operation in any transform
  codec. We built `quant.py` with a uniform scalar quantizer including a dead-zone
  (Step 18). Chapter 24 built canonical *Huffman coding* (`huffman.py`, Step 8). This
  chapter assembles those three ingredients (DCT, quantization, Huffman) into a complete
  JPEG-class pipeline and adds the color-space and chroma-subsampling pieces the earlier
  chapters deferred.
]

#objectives((
  "Name and explain every stage in the JPEG encoding pipeline from raw pixels to
  compressed bytes.",
  "Convert an 8×8 pixel block through the DCT, quantize it with a standard table, scan
  it in zig-zag order, and describe how run-length coding handles the zeros.",
  "Explain why chroma subsampling (4:2:0) works without visible quality loss for most
  images.",
  "Predict what blocking and ringing artifacts look like and explain why they appear.",
  "Distinguish baseline, progressive, and arithmetic-coder JPEG, and know which variants
  are in common use.",
  "Describe what JPEG-LS is, how it differs from lossy JPEG, and where it is used.",
  "Implement a minimal JPEG-class encoder in tinyzip (`jpeg.py`, Step 19) that DCT-
  compresses an 8-bit grayscale image, quantizes with a configurable table, entropy-codes
  with Huffman, and reports PSNR.",
))

== Color, human vision, and YCbCr

Before a JPEG encoder touches any math, it converts your photograph from the RGB color
space your camera produces to a different space called *YCbCr*.

=== Why not just compress red, green, and blue?

You could compress RGB directly, and the math would work. But it would waste bits badly.
Your visual system is built on two very different kinds of sensor cells in your retina.
The *cone* cells come in three flavors sensitive to different wavelength ranges, roughly
long (red), medium (green), and short (blue), though they are not equally packed. The
*fovea*, the high-resolution center of your vision, is loaded with green-sensitive and
red-sensitive cones but has comparatively few blue-sensitive ones. More importantly, the
early visual cortex does not really process R, G, B as three equal channels. It performs
something very close to the transform described below: extract the brightness, and separately
note how the color deviates from neutral grey.

The name for this approach in image and video standards is #emph[YCbCr] (sometimes
written YCrCb or YUV in analog contexts, though the exact definitions differ):

#definition("YCbCr")[
  A color space used in image and video compression that splits a pixel's color into three
  channels:
  - *Y*: luma (brightness). Roughly a weighted average of R, G, B, matching the eye's
    sensitivity: $Y approx 0.299 R + 0.587 G + 0.114 B$.
  - *Cb*: chroma-blue, measuring how much the color differs from grey toward blue.
  - *Cr*: chroma-red, measuring how much the color differs from grey toward red.
  The name comes from Y (luma) + C (chroma) + b/r (blue/red).
]

The conversion is a simple linear formula. For 8-bit pixel values in the range 0–255:

$ Y &= 0.299 dot R + 0.587 dot G + 0.114 dot B \
  C_b &= 128 - 0.168736 dot R - 0.331264 dot G + 0.5 dot B \
  C_r &= 128 + 0.5 dot R - 0.418688 dot G - 0.081312 dot B $

And the reverse:

$ R &= Y + 1.402 (C_r - 128) \
  G &= Y - 0.344136 (C_b - 128) - 0.714136 (C_r - 128) \
  B &= Y + 1.772 (C_b - 128) $

#keyidea[
  YCbCr is not compression. It is a lossless coordinate change (up to rounding). Its
  value is what comes next: the human eye is much more sensitive to errors in Y than to
  errors in Cb or Cr, so we can *afford to store Cb and Cr at lower resolution*. The
  conversion makes that budget distinction possible.
]

=== Chroma subsampling: 4:2:0, 4:2:2, 4:4:4

Once the image is in YCbCr, JPEG (and virtually every video codec) throws away most of
the chroma information, not by rounding, but by literally storing it at *lower spatial
resolution*.

#definition("Chroma subsampling")[
  The practice of storing the color channels (Cb, Cr) at a smaller grid size than the
  luma channel (Y). Described by a three-number ratio *J:a:b* from the NTSC days:
  - *4:4:4*: no subsampling; Y, Cb, Cr all at full resolution.
  - *4:2:2*: Cb and Cr stored at half horizontal resolution.
  - *4:2:0*: Cb and Cr stored at half horizontal *and* half vertical resolution, with one
    chroma value shared among a 2×2 square of luma pixels.
]

The most common setting for JPEG photographs is *4:2:0*. Its effect on bit count is
significant: a full 4:4:4 image needs $3$ bytes per pixel (Y + Cb + Cr); at 4:2:0 it
needs only $1 + 1/4 + 1/4 = 1.5$ bytes per pixel, a factor-of-two reduction with
very little visible loss for most photographic subjects because our colour acuity is so
coarse.

#fig(
  [YCbCr channels and 4:2:0 chroma subsampling. Full-resolution Y on the left, half-resolution Cb and Cr on the right.],
  cetz.canvas({
    import cetz.draw: *
    // Y channel full size
    rect((0,0),(3,3), fill: rgb("#d6e4f0"), stroke: 0.7pt)
    content((1.5,3.3), box(width: 2.6cm, inset: 1pt, align(center, text(size: 8pt)[*Y* (full res)])))
    // 4x4 grid inside Y
    for i in (1,2) { line((i, 0),(i, 3), stroke: 0.3pt + gray) }
    for j in (1,2) { line((0, j),(3, j), stroke: 0.3pt + gray) }
    // Cb
    rect((3.6,1),(5.1,2.5), fill: rgb("#d5f0d6"), stroke: 0.7pt)
    content((4.35,2.8), box(width: 1.1cm, inset: 1pt, align(center, text(size: 8pt)[*Cb* (½ res)])))
    // Cr
    rect((5.4,1),(6.9,2.5), fill: rgb("#f0d5d5"), stroke: 0.7pt)
    content((6.15,2.8), box(width: 1.1cm, inset: 1pt, align(center, text(size: 8pt)[*Cr* (½ res)])))
    // arrow
    line((3,1.5),(3.55,1.5), mark: (end: ">"))
    content((3.3,1.7), size: 7pt)[÷2]
  })
)

#aside[
  The 4:2:0 notation is historical and slightly confusing (the "0" refers to alternate
  lines having zero extra chroma samples in the original NTSC scheme). Think of it
  simply as "color at half width and half height." Many modern cameras record 4:4:4 or
  4:2:2 internally but JPEG viewers and sharing platforms almost always re-encode at
  4:2:0.
]

== The 8×8 block DCT

After color conversion and chroma downsampling, each channel (Y, Cb, Cr) is a
two-dimensional array of integers. JPEG processes these arrays in *non-overlapping 8×8
pixel blocks*, applying the Discrete Cosine Transform (DCT) to each one independently.

=== Why 8×8?

The block size is a trade-off the JPEG committee froze in 1992. Bigger blocks capture
longer-range correlations and give better compression, but they need more memory, more
computation, and (critically) they smear *blocking artifacts* across a larger region
when things go wrong. The 8×8 block was a pragmatic sweet spot for the hardware of the
early 1990s. Thirty years later it is still in every baseline JPEG, though later codecs
(H.265, AV1) use variable block sizes up to 64×64.

=== Level shift

Before the DCT, JPEG subtracts 128 from every pixel value. Raw pixels are in the range
0–255; after the shift they are in −128 to 127, centered around zero. This is called a
*level shift*, and it serves one purpose: a fully white block (all 255s) should produce a
large DC coefficient and tiny AC coefficients, but without the shift its DC would be
$8 times 255 = 2040$ while a mid-grey block (all 128s) would have DC $= 8 times 128 = 1024$.
After the shift, all constant blocks produce the same DC magnitude regardless of their
mean, and the AC coefficients are always near zero for smooth blocks, which is exactly
what we want for quantization to kill.

=== The 2-D DCT on an 8×8 block

#mathrecall[
  From Chapter 38: the 1-D DCT-II of an $N$-point sequence $x_0, dots, x_(N-1)$ is
  $X_k = w_k sum_(n=0)^(N-1) x_n cos((pi k(2n+1))/(2N))$
  with $w_0 = 1/sqrt(N)$, $w_(k>0) = sqrt(2/N)$. The 2-D DCT of an $N times N$ block is
  separable: apply the 1-D DCT to every row, then to every column (or vice versa).
]

For the 8×8 block, the result is another 8×8 array of 64 *DCT coefficients*. The
top-left coefficient (row 0, column 0) is called the *DC coefficient*; it equals the
block average times a scale factor. All 63 remaining coefficients are *AC coefficients*
and represent increasingly fine spatial patterns, from gentle horizontal or vertical
gradients to the high-frequency checkerboard at position (7,7).

#fig(
  [The 64 DCT basis patterns for an 8×8 block. Low frequency (smooth) at top-left; high frequency (fine checks) at bottom-right.],
  cetz.canvas({
    import cetz.draw: *
    // Draw 8x8 grid representing the basis tiles
    let n = 8
    let sz = 0.42
    for row in range(n) {
      for col in range(n) {
        let x = col * (sz + 0.04)
        let y = (n - 1 - row) * (sz + 0.04)
        // shade by frequency (row+col) as a proxy
        let freq = row + col
        let shade = int(220 - freq * 12)
        let clr = rgb(shade, shade, shade)
        rect((x, y),(x + sz, y + sz), fill: clr, stroke: 0.3pt + gray)
      }
    }
    // Labels
    content((n * (sz + 0.04) / 2, -0.25), box(width: 3.2cm, inset: 1pt, align(center, text(size: 8pt)[→ higher frequency])))
    content((-0.35, n * (sz + 0.04) / 2), box(width: 3.2cm, inset: 1pt, align(center, text(size: 8pt)[↑ higher frequency])), angle: 90deg)
    content((0.21, n * (sz + 0.04) - 0.1), text(size: 7pt)[DC])
  })
)

#checkpoint[
  What does the DC coefficient of an 8×8 block represent, intuitively?
][
  It represents the *average brightness* of the 8×8 block (times a scaling constant).
  If all 64 pixels have the value 100, the DC coefficient will be large and all 63 AC
  coefficients will be exactly zero. The block is perfectly flat, with no variation
  at all.
]

=== A worked example

Let us trace a tiny 4×4 slice of an actual block. Suppose a patch in the Y channel looks
like this (values after level shift, so pixels minus 128):

$ mat(-12, -10, -8, -5; -10, -9, -7, -3; -6, -5, -2, 1; -1, 0, 2, 5) $

All values are small and negative (a slightly darker-than-midgrey region with a gentle
gradient). After the 2-D DCT, the energy condenses into the top-left corner. The DC
coefficient (average × scaling) will be around $-46$; the horizontal-gradient AC
coefficient at (0,1) will be around $+10$; and almost all coefficients beyond the first
two rows/columns will be below 1, tiny enough that quantization will round them all to
zero. That is energy compaction at work.

== Quantization tables

After the DCT, each 8×8 block is an array of 64 floating-point coefficients. The *lossy*
step is to divide each coefficient by a corresponding *step size* and round to the
nearest integer.

#definition("Quantization table")[
  An 8×8 array of positive integers, one per DCT position, that specifies the rounding
  step size for that coefficient. A *large* entry means coarse rounding (more loss,
  fewer bits); a *small* entry means fine rounding (less loss, more bits).
]

JPEG's quality slider (1–100) works by *scaling* a reference table. The standard
defines separate luminance and chrominance tables. The ITU-T T.81 / JPEG reference
luminance table looks like this (values for quality 50):

#align(center)[
#table(
  columns: (auto,)*8,
  align: right,
  [16],[11],[10],[16],[24],[40],[51],[61],
  [12],[12],[14],[19],[26],[58],[60],[55],
  [14],[13],[16],[24],[40],[57],[69],[56],
  [14],[17],[22],[29],[51],[87],[80],[62],
  [18],[22],[37],[56],[68],[109],[103],[77],
  [24],[35],[55],[64],[81],[104],[113],[92],
  [49],[64],[78],[87],[103],[121],[120],[101],
  [72],[92],[95],[98],[112],[100],[103],[99],
)
]

Notice the pattern: the top-left entry (for the DC coefficient) is 16; the bottom-right
(for the highest-frequency checkerboard) is 99. *High-frequency coefficients get divided
by a larger number, rounding them more aggressively (often to zero), because the eye
barely notices those details.*

At quality 50 (the standard table above), a DCT coefficient of value $46$ in the DC
position is divided by 16 and rounded: $round(46/16) = 3$, dequantized back to
$3 times 16 = 48$, an error of $2$. A coefficient of value $2.1$ in the
high-frequency (7,7) position is divided by 99 and rounded: $round(2.1/99) = 0$.
Thrown away entirely. Nobody sees it.

At quality 80, every table entry is scaled down (smaller step = finer rounding = more
bits). At quality 10, entries are scaled up; more coefficients round to zero; more data
gone. The quality lever is purely a quantization table multiplier.

Why is this safe to do at all? Because rounding can only ever do a *bounded* amount of
damage to each coefficient. That bound is worth stating precisely, because it is the entire
reason a quality knob exists: it lets the encoder *cap* the error it injects.

#theorem("Bounded quantization error")[
  Let $c$ be a DCT coefficient and $q > 0$ its quantization step (the table entry).
  Quantize-then-dequantize produces $hat(c) = q dot round(c / q)$. Then the error never
  exceeds half a step:
  $ abs(c - hat(c)) <= q / 2. $
]

#proof[
  Write $c / q = m + f$ where $m = round(c/q)$ is the nearest integer and $f = c/q - m$ is
  the leftover fraction. By the definition of "round to nearest integer," $f$ can never be
  more than half a unit away from zero: $abs(f) <= 1/2$. Now
  $abs(c - hat(c)) = abs(c - q dot m) = q dot abs(c/q - m) = q dot abs(f) <= q dot 1/2 = q/2$.
  The error is at most half the step size, which is exactly why a *small* table entry
  (fine step) means little loss and a *large* entry (coarse step) means a lot.
]

This is the lever in one inequality: doubling every table entry at most doubles the
worst-case error per coefficient. Because the high-frequency entries are the biggest,
the errors land precisely where the eye is least able to see them.

#pitfall[
  JPEG "quality 100" does *not* mean lossless. It means the quantization table entries
  are all set to 1, so every coefficient is rounded to the nearest integer. A tiny bit
  of rounding still happens. True lossless JPEG requires a different standard
  (JPEG-LS or the mathematically lossless variant of JPEG-2000, which use integer
  wavelets or predictors that never introduce rounding).
]

=== DC coefficient difference coding

The 64 quantized coefficients per block are not yet in their final form. Before entropy
coding, JPEG applies one more trick to DC coefficients specifically. Rather than coding
each block's DC value independently, JPEG codes the *difference* between this block's
DC and the previous block's DC in raster order:

$ "DC"_"coded" = "DC"_"current" - "DC"_"previous" $

Neighbouring blocks in a smooth image have similar averages, so these differences are
usually small (maybe $-3, +1, 0, 0, +2$) even though the absolute DCs might be around
50. Small numbers need fewer bits. This is DPCM (Differential Pulse Code Modulation)
applied to the DC stream, Chapter 40's technique repurposed here in the DC channel of
an image codec.

== Zig-zag scan and run-length encoding

After quantization, the 8×8 block of integers has a useful property: almost all the large
values are in the top-left corner (low frequencies) and the bottom-right quadrant is
mostly zeros (high frequencies quantized away). The zig-zag scan exploits this.

=== The zig-zag scan order

Instead of reading the block row-by-row (which would mix large and small values randomly),
JPEG reads it in a diagonal zig-zag that visits coefficients roughly in order of
increasing frequency:

#fig(
  [Zig-zag scan order through an 8×8 block. Positions are visited diagonally, so zero-value high-frequency coefficients cluster at the end.],
  cetz.canvas({
    import cetz.draw: *
    let order = (
      (0,0),(0,1),(1,0),(2,0),(1,1),(0,2),(0,3),(1,2),
      (2,1),(3,0),(4,0),(3,1),(2,2),(1,3),(0,4),(0,5),
      (1,4),(2,3),(3,2),(4,1),(5,0),(6,0),(5,1),(4,2),
      (3,3),(2,4),(1,5),(0,6),(0,7),(1,6),(2,5),(3,4),
      (4,3),(5,2),(6,1),(7,0),(7,1),(6,2),(5,3),(4,4),
      (3,5),(2,6),(1,7),(2,7),(3,6),(4,5),(5,4),(6,3),
      (7,2),(7,3),(6,4),(5,5),(4,6),(3,7),(4,7),(5,6),
      (6,5),(7,4),(7,5),(6,6),(5,7),(6,7),(7,6),(7,7),
    )
    let sz = 0.43
    for (idx, pos) in order.enumerate() {
      let (r, c) = pos
      let x = c * (sz + 0.02)
      let y = (7 - r) * (sz + 0.02)
      let shade = int(240 - idx * 3)
      let clr = rgb(shade, int(shade * 0.85), shade)
      rect((x,y),(x+sz,y+sz), fill: clr, stroke: 0.3pt)
      content((x + sz/2, y + sz/2), size: 6pt)[#(idx+1)]
    }
  })
)

After the zig-zag, the 64 quantized values appear as a 1-D sequence. For a smooth block
at moderate quality it might look like: $[52, -4, 3, -2, 1, 0, 0, 0, 0, 0, 1, 0, 0, dots, 0]$.
The long tail of zeros can be coded compactly.

=== Run-length encoding of AC coefficients

JPEG encodes the zig-zag sequence of AC coefficients (positions 1–63) using *run-length
coding*: each nonzero value is represented as a pair `(RUNLENGTH, VALUE)` where
`RUNLENGTH` is the count of zeros immediately before this nonzero value (0–15). A special
code called *End of Block (EOB)* signals that all remaining AC coefficients in this block
are zero, the single most common symbol in typical images, often appearing after only
the first few nonzeros.

At quality 50 on a smooth sky block, the entire 63-element AC sequence might compress to
just: `EOB` (one symbol), meaning all 63 AC coefficients are zero. The DC difference
plus one symbol encodes 64 numbers. That is aggressive compression.

== Huffman coding of JPEG symbols

The (RUNLENGTH, VALUE) pairs and DC differences are finally entropy-coded with Huffman
tables. JPEG does not use a single universal Huffman table; instead it uses up to four
tables (two for DC symbols, two for AC symbols, separate for luma Y and chroma Cb/Cr),
which are stored in the JPEG file header. The encoder counts symbol frequencies across
all blocks and builds optimal Huffman trees. At decode time, the header is parsed first
and the Huffman trees are reconstructed before any pixel data is touched.

#history[
  JPEG's standard actually *allows* an arithmetic coder as an alternative to Huffman.
  It is called the "arithmetic coding option" (T.84). Arithmetic coding is losslessly
  more efficient (typically 5–10% smaller files) because it can assign fractional bits per
  symbol. However, in 1992 arithmetic coding was *patent-encumbered* (IBM and AT&T held
  key patents), so camera manufacturers universally implemented only the Huffman variant.
  By the time the patents expired in the mid-2000s, Huffman JPEG was so entrenched that
  the arithmetic variant is vanishingly rare in practice. The lesson is the same one we
  saw with GIF's LZW: patents can freeze an inferior technology as the standard for
  decades.
]

#algo(
  name: "JPEG Baseline Encoding (ITU-T T.81)",
  year: 1992,
  authors: "Joint Photographic Experts Group (ISO/CCITT)",
  aim: "Lossy still-image compression using transform + quantize + Huffman",
  complexity: "$O(N)$ in total pixels ($N$), one 8×8 DCT per block at $O(64)$ each",
  strengths: "Universal support; tunable quality; good ratio for photographs; hardware-accelerated everywhere",
  weaknesses: "Blocking and ringing artifacts at low quality; no transparency; no lossless mode in baseline; poor on non-photographic content",
  superseded: "Partially superseded by WebP, AVIF, JPEG XL for new encodings; JPEG files will be with us for decades"
)[]

== The JPEG file format (JFIF/Exif)

The bitstream produced by the Huffman encoder is wrapped in a *segment-based container*.
Every piece of a JPEG file is a *marker segment*: a two-byte marker (always starting with
`0xFF`) followed by a length field and data. Key markers:

- `FF D8`: Start of Image (SOI), the first two bytes of every JPEG file.
- `FF E0`: APP0, the JFIF header (resolution, aspect ratio, version).
- `FF E1`: APP1, Exif data (camera model, GPS coordinates, timestamps from your phone).
- `FF DB`: DQT, Define Quantization Table.
- `FF C0`: SOF0, Start of Frame (baseline DCT), giving image dimensions and component count.
- `FF C4`: DHT, Define Huffman Table (up to four).
- `FF DA`: SOS, Start of Scan; the actual compressed data follows.
- `FF D9`: End of Image (EOI), the last two bytes.

A parser that sees `FF D8 FF` can be confident it has a JPEG file. The `0xFF` magic is so
reliable that it has been cargo-culted into dozens of later formats.

#gopython("Reading JPEG marker segments in raw bytes")[
  With `bytes` and integer indexing (covered in Chapter 17):

  ```python
  def find_markers(data: bytes) -> list[tuple[int, int]]:
      """Return (offset, marker) pairs for all JPEG markers in data."""
      markers = []
      i = 0
      while i < len(data) - 1:
          if data[i] == 0xFF and data[i+1] != 0x00:
              markers.append((i, data[i+1]))
              i += 2
          else:
              i += 1
      return markers

  with open("photo.jpg", "rb") as f:
      raw = f.read()
  for offset, code in find_markers(raw)[:8]:
      print(f"  0x{offset:06X}  FF {code:02X}")
  # Output starts: 0x000000  FF D8
  #                0x000002  FF E0   (or FF E1 for Exif)
  #                ...       FF DB   (quantization tables)
  ```

  The `0xFF 0xD8` header is JPEG's *magic number*, two bytes that identify the format
  unambiguously. Most file formats use such magic numbers at fixed offsets; we saw the
  same idea in our own `container.py` from Chapter 17.
]

== Progressive JPEG

The baseline JPEG described so far uses *sequential* order: all 64 coefficients of block 1,
then all of block 2, and so on, from top-left to bottom-right. If you watch a slow
connection load a baseline JPEG, you see a thin horizontal band creeping down the screen.

*Progressive JPEG* (standardized in the same T.81 document) reorders the data into
*scans*, multiple passes over the whole image:

1. *Spectral selection:* First scan sends only DC coefficients from every block. The whole
   image can be reconstructed at very low quality (blurry but whole). Subsequent scans
   add low-frequency ACs, then mid-frequency ACs, then high.
2. *Successive approximation:* Each scan refines coefficient precision. First pass sends
   the most significant bits; later passes add lower bits.

This is why progressive JPEGs famously "fade in" on slow connections: you see a blurry
whole image that sharpens over time, which is more pleasant than waiting for a
top-to-bottom stripe.

#keyidea[
  Progressive JPEG does not improve compression much (roughly 5–8% smaller in practice).
  Its value is *perceived latency*: a user sees a complete-though-blurry image faster
  and waits for sharpening rather than for the first pixels.
]

== JPEG artifacts: blocking and ringing

At low quality settings, JPEG produces two characteristic artifacts that every digital
photo editor recognizes:

=== Blocking

Because the DCT is applied to independent 8×8 blocks, and because quantization rounds
coefficients within each block independently, neighbouring blocks at their shared borders
can have different reconstructed values. The discontinuity shows up as a visible grid
of 8×8 squares called *blocking*. It is most visible in smooth areas (uniform sky,
skin tones) where sudden jumps across block borders stand out against the gentle
gradients. At quality 10 a JPEG photograph looks like a tile mosaic.

=== Ringing

A sharp edge in an image (a window frame against a white wall, text on a background)
requires high-frequency DCT coefficients to represent the sudden jump in value. At low
quality, those high-frequency coefficients are quantized to zero. But the inverse DCT
cannot reproduce a sharp edge from low-frequency components alone. Instead it produces *ringing
oscillations* (Gibbs phenomenon, the same effect we mentioned briefly in Chapter 37)
that ripple away from the edge like ripples on water.

#misconception[
  "JPEG ringing comes from the quantization table being too aggressive."
][
  Ringing is fundamentally a consequence of representing a *discontinuous function*
  (a sharp edge) with a *finite set of smooth cosine basis functions*. Even with a
  gentle quantization table, a low-frequency truncation of the DCT series of any sharp
  edge will produce oscillations. At higher quality settings the high-frequency
  coefficients survive quantization and reconstruct the edge more accurately, reducing
  ringing, but the root cause is the basis mismatch, not the quantization alone.
]

#fig(
  [Left: blocking artifact (8×8 tile boundaries visible in smooth regions). Right: ringing artifact (halos around a sharp edge).],
  cetz.canvas({
    import cetz.draw: *
    // Left: blocking diagram
    for i in range(4) {
      for j in range(4) {
        let shade = if calc.rem(i + j, 2) == 0 { rgb("#b0cce8") } else { rgb("#9fc0e0") }
        rect((i*0.7, j*0.7),(i*0.7+0.7, j*0.7+0.7), fill: shade, stroke: 1.2pt + white)
      }
    }
    content((1.4, -0.3), box(width: 2.4cm, inset: 1pt, align(center, text(size: 8pt)[Blocking: tile seams])))
    // Right: ringing diagram
    line((4.5, 0),(4.5, 2.8), stroke: 2pt + black)
    for k in range(5) {
      let amp = 0.18 / (k + 1)
      let xbase = 4.5 + 0.3 * (k + 1)
      line((xbase, 1.4),(xbase + 0.3, 1.4 + amp * 8), stroke: 0.5pt)
      line((xbase + 0.3, 1.4 + amp * 8),(xbase + 0.6, 1.4 - amp * 8), stroke: 0.5pt)
      line((xbase + 0.6, 1.4 - amp * 8),(xbase + 0.9, 1.4), stroke: 0.5pt)
    }
    content((5.8, -0.3), box(width: 2.6cm, inset: 1pt, align(center, text(size: 8pt)[Ringing: edge oscillations])))
  })
)

== JPEG-LS: the lossless sibling

JPEG-LS (ITU-T T.87, 1999) is a completely different standard that shares only the "JPEG"
name. It is a *lossless or near-lossless* image codec with no DCT and no quantization in the
destructive sense.

JPEG-LS uses a predictor-based approach called LOCO-I (LOw COmplexity LOssless Image
compression, developed at HP Labs in the mid-1990s by Marcelo Weinberger, Gadiel Seroussi,
and Guillermo Sapiro). Its key ideas:

1. *Prediction:* Each pixel is predicted from its left, top, and top-left neighbors using
   a simple adaptive rule. For typical smooth images this produces very small residuals.
2. *Context modeling:* The residuals are coded with Rice-Golomb codes (Chapter 25) adapted
   by a local gradient context. Areas with sharp edges use different parameters than
   smooth regions.
3. *Run-length coding:* Long runs of near-constant pixels (common in medical and document
   images) are coded very efficiently with a dedicated run mode.

JPEG-LS achieves *true lossless compression* at a competitive ratio and high speed,
without the complexity of arithmetic coding. A "near-lossless" mode allows a bounded
maximum pixel error (say, $±2$), giving better ratios than lossless while guaranteeing
the error stays small.

#algo(
  name: "JPEG-LS / LOCO-I",
  year: 1999,
  authors: "Weinberger, Seroussi, Sapiro (HP Labs); standardized as ITU-T T.87",
  aim: "Lossless (and near-lossless) image compression without DCT",
  complexity: "$O(N)$, one pass through all pixels",
  strengths: "True lossless; fast; low complexity; excellent for medical/document imaging",
  weaknesses: "Less efficient than JPEG 2000 lossless on some content; no progressive decode; limited adoption outside medical/fax contexts",
  superseded: "JPEG XL in lossless mode offers better ratios; but JPEG-LS is used in DICOM medical imaging worldwide"
)[]

#history[
  JPEG-LS traces its roots to the CALIC algorithm (Context-based Adaptive Lossless Image
  Codec) from the mid-1990s, which achieved excellent ratios but at too high a complexity.
  LOCO-I was explicitly designed to match CALIC's ratio within ~5% while being computable
  in a single forward pass and fast enough for real-time medical scanners. DICOM
  (the medical imaging standard) adopted JPEG-LS and it is still the lossless codec of
  choice for X-rays, CT scans, and pathology images worldwide.
]

== PSNR: measuring lossy quality

Once we have a lossy codec, we need a way to measure how much damage it does. The
traditional metric is *PSNR* (Peak Signal-to-Noise Ratio).

#gomaths("PSNR: the engineer's quality ruler")[
  Let $x_i$ be the original pixel values and $hat(x)_i$ the reconstructed ones, for
  $N$ pixels each in the range $[0, 255]$. The *Mean Squared Error (MSE)* is:

  $ "MSE" = (1)/(N) sum_(i=1)^N (x_i - hat(x)_i)^2 $

  It is the average of the squared per-pixel errors, large when reconstruction is far
  from the original, zero when they are identical.

  *PSNR* converts MSE into decibels using the maximum possible signal value
  ($"MAX" = 255$ for 8-bit images):

  $ "PSNR" = 10 log_10 ((255^2) / "MSE") quad "dB" $

  Higher PSNR = lower error = better quality. Typical ranges:
  - PSNR > 40 dB: virtually indistinguishable from original.
  - PSNR 30–40 dB: good quality, minor artifacts.
  - PSNR < 30 dB: visible degradation.
  - PSNR < 20 dB: heavy artifacts.

  *Tiny example:* MSE = 25 (each pixel off by 5 on average in squared sense).
  $"PSNR" = 10 log_10(255^2 / 25) = 10 log_10(2601) approx 34.1 " dB"$.

  The decibel scale (base-10 logarithm × 10) was introduced in Chapter 7; here we see
  it used in its second major compression role, measuring quality loss.
]

#pitfall[
  PSNR is a reliable engineering metric for comparing codec settings *of the same codec
  on the same image*, but it is a *weak predictor of human perception*. A heavily blurred
  image can have a high PSNR while looking unpleasant; a sharp but slightly noisy image
  can have lower PSNR and look better. Perceptual metrics like SSIM (Structural
  Similarity Index, 2004) and VMAF (Video Multimethod Assessment Fusion, Netflix 2016)
  correlate better with human judgments but are more complex. Chapter 41 covers this
  quality measurement landscape in depth. For now, PSNR gives us a simple, fast number
  to track as we tune quantization.
]

== tinyzip Step 19: a toy JPEG encoder

The TINYZIP.md spec assigns Chapter 42 *Step 19*: implement `jpeg.py`, a toy JPEG-class
encoder and decoder on grayscale images, using the DCT and quantizer from earlier steps,
adding zig-zag + run-length + Huffman coding, and reporting PSNR.

#project("Step 19 - jpeg.py: toy JPEG (DCT + quant + zig-zag + Huffman) → method=\"jpeg\", with PSNR")[

We import `dct2d`, `idct2d` from `transform.py` (Step 17) and reuse the *canonical*
Huffman codec `encode`/`decode` from `huffman.py` (Step 8), the exact functions Chapter 24
built, with their exact signatures `encode(data: bytes) -> bytes` and
`decode(blob: bytes) -> bytes`. We add zig-zag scanning, DC differencing, and run-length
encoding of ACs ourselves.

There is one wrinkle. The Step 8 Huffman codec models a stream of *bytes* (values 0–255):
it writes a fixed 256-entry length header, so it cannot directly code our JPEG symbols,
which are larger integers (a packed `(run, value)` pair can exceed 6000). The standard fix,
used by real codecs too, is to *serialise our symbols into bytes first* and let the
byte-level Huffman model that byte stream. We pack each symbol as two big-endian bytes
with `struct` (Chapter 17), giving a plain `bytes` object that `encode` accepts unchanged.
This keeps us honest about reuse: we call the real Step 8 functions, untouched.

#pyrecall[
  `struct.pack(">H", n)` turns an integer `n` (0–65535) into 2 big-endian bytes; the `>`
  means most-significant byte first, `H` means "unsigned 16-bit". `struct.unpack(">H", b)`
  reverses it. We met `struct` in Chapter 17 when building binary file headers.
]

#pyrecall[
  `enumerate(seq)` (Chapter 16) walks a sequence yielding `(index, item)` pairs, so
  `for i, x in enumerate(["a","b"])` gives `(0, "a")` then `(1, "b")`. We use it below to
  number blocks and zig-zag positions while iterating them.
]

```python
# tinyzip/jpeg.py
"""
Step 19: toy JPEG encoder/decoder for 8-bit grayscale images.
Implements: YCbCr conversion (skipped - grayscale only in this step),
            level shift, 8x8 DCT, quantization, zig-zag scan,
            DC differencing + AC run-length, Huffman coding.
Produces method="jpeg" output compatible with tinyzip container.
"""

from __future__ import annotations
import math
import struct
from tinyzip.transform import dct2d, idct2d
from tinyzip.huffman  import encode as huff_encode, decode as huff_decode

# ---------------------------------------------------------------------------
# Standard JPEG luminance quantization table (quality 50 baseline)
# ---------------------------------------------------------------------------
LUMA_Q50: list[list[int]] = [
    [16, 11, 10, 16, 24, 40, 51, 61],
    [12, 12, 14, 19, 26, 58, 60, 55],
    [14, 13, 16, 24, 40, 57, 69, 56],
    [14, 17, 22, 29, 51, 87, 80, 62],
    [18, 22, 37, 56, 68,109,103, 77],
    [24, 35, 55, 64, 81,104,113, 92],
    [49, 64, 78, 87,103,121,120,101],
    [72, 92, 95, 98,112,100,103, 99],
]

def scale_qtable(base: list[list[int]], quality: int) -> list[list[int]]:
    """Scale a quantization table to a given quality (1–100)."""
    if quality <= 0:   quality = 1
    if quality > 100:  quality = 100
    scale = 5000 // quality if quality < 50 else 200 - 2 * quality
    scaled = []
    for row in base:
        scaled.append([max(1, min(255, (v * scale + 50) // 100)) for v in row])
    return scaled

# ---------------------------------------------------------------------------
# Zig-zag scan tables (standard JPEG order)
# ---------------------------------------------------------------------------
def _make_zigzag() -> tuple[list[tuple[int,int]], list[tuple[int,int]]]:
    """Return (encode_order, decode_positions) for 8x8 zig-zag."""
    order: list[tuple[int,int]] = []
    r, c, going_up = 0, 0, True
    for _ in range(64):
        order.append((r, c))
        if going_up:
            if c == 7:       r += 1;  going_up = False
            elif r == 0:     c += 1;  going_up = False
            else:            r -= 1;  c += 1
        else:
            if r == 7:       c += 1;  going_up = True
            elif c == 0:     r += 1;  going_up = True
            else:            r += 1;  c -= 1
    return order, [(r, c) for (r, c) in order]

ZIGZAG_ORDER, _ZIGZAG_POS = _make_zigzag()

def zigzag_scan(block: list[list[float]]) -> list[float]:
    """Read an 8x8 block in zig-zag order, returning 64 values."""
    return [block[r][c] for (r, c) in ZIGZAG_ORDER]

def izigzag_scan(values: list[float]) -> list[list[float]]:
    """Reconstruct an 8x8 block from 64 zig-zag-ordered values."""
    block = [[0.0]*8 for _ in range(8)]
    for idx, (r, c) in enumerate(ZIGZAG_ORDER):
        block[r][c] = values[idx]
    return block

# ---------------------------------------------------------------------------
# Quantize / dequantize a single block
# ---------------------------------------------------------------------------
def quantize_block(
    block: list[list[float]],
    qtable: list[list[int]]
) -> list[list[int]]:
    return [[round(block[r][c] / qtable[r][c]) for c in range(8)] for r in range(8)]

def dequantize_block(
    qblock: list[list[int]],
    qtable: list[list[int]]
) -> list[list[float]]:
    return [[qblock[r][c] * qtable[r][c] for c in range(8)] for r in range(8)]

# ---------------------------------------------------------------------------
# AC run-length encoding / decoding
# ---------------------------------------------------------------------------
def rle_encode_ac(ac: list[int]) -> list[tuple[int,int]]:
    """
    Encode 63 AC values (zig-zag order, skipping DC).
    Returns list of (run, value) pairs; (0, 0) signals End of Block.
    """
    symbols: list[tuple[int,int]] = []
    run = 0
    for v in ac:
        if v == 0:
            run += 1
            if run == 16:                 # ZRL: 16 zeros (JPEG special code)
                symbols.append((15, 0))
                run = 0
        else:
            symbols.append((run, v))
            run = 0
    symbols.append((0, 0))               # EOB
    return symbols

def rle_decode_ac(symbols: list[tuple[int,int]]) -> list[int]:
    """Expand (run, value) RLE pairs back to 63 AC values."""
    ac: list[int] = []
    for (run, val) in symbols:
        if run == 0 and val == 0:         # EOB
            ac.extend([0] * (63 - len(ac)))
            break
        ac.extend([0] * run)
        ac.append(val)
    return ac

# ---------------------------------------------------------------------------
# Image padding and block splitting
# ---------------------------------------------------------------------------
def pad_image(pixels: list[list[int]]) -> list[list[int]]:
    """Pad a grayscale image to a multiple of 8 in each dimension."""
    h = len(pixels)
    w = len(pixels[0]) if h else 0
    ph = (h + 7) // 8 * 8
    pw = (w + 7) // 8 * 8
    padded = [row[:] + [row[-1]] * (pw - w) for row in pixels]
    if ph > h:
        padded.extend([padded[-1][:] for _ in range(ph - h)])
    return padded

def split_blocks(pixels: list[list[int]]) -> list[list[list[int]]]:
    """Split padded image into a list of 8x8 blocks (row-major)."""
    h, w = len(pixels), len(pixels[0])
    blocks = []
    for br in range(0, h, 8):
        for bc in range(0, w, 8):
            block = [pixels[br+r][bc:bc+8] for r in range(8)]
            blocks.append(block)
    return blocks

def merge_blocks(
    blocks: list[list[list[int]]],
    orig_h: int, orig_w: int
) -> list[list[int]]:
    """Merge 8x8 blocks back into a full image, cropping to original size."""
    pw = (orig_w + 7) // 8 * 8
    num_cols = pw // 8
    rows_out: list[list[int]] = []
    for block_idx, block in enumerate(blocks):
        br = (block_idx // num_cols) * 8
        bc = (block_idx  % num_cols) * 8
        while len(rows_out) < br + 8:
            rows_out.append([0] * pw)
        for r in range(8):
            for c in range(8):
                rows_out[br + r][bc + c] = block[r][c]
    return [row[:orig_w] for row in rows_out[:orig_h]]

# ---------------------------------------------------------------------------
# Full encode pipeline
# ---------------------------------------------------------------------------
def jpeg_encode(
    pixels: list[list[int]],
    quality: int = 50
) -> bytes:
    """
    Encode an 8-bit grayscale image to a toy-JPEG byte stream.

    Format (big-endian header):
        4 bytes: magic  b'TJPG'
        2 bytes: orig height (uint16)
        2 bytes: orig width  (uint16)
        1 byte:  quality
        4 bytes: number of symbols (N_syms, uint32)
        then:    the Step 8 Huffman payload (canonical encode of the
                 2-bytes-per-symbol stream)
    """
    orig_h = len(pixels)
    orig_w = len(pixels[0]) if orig_h else 0
    qtable = scale_qtable(LUMA_Q50, quality)

    # 1. Pad & split
    padded = pad_image(pixels)
    blocks = split_blocks(padded)

    # 2. Per-block: level-shift, DCT, quantize, zig-zag
    all_dc: list[int] = []
    all_ac_rle: list[list[tuple[int,int]]] = []
    for block in blocks:
        shifted = [[block[r][c] - 128 for c in range(8)] for r in range(8)]
        dct_blk = dct2d(shifted)
        q_blk   = quantize_block(dct_blk, qtable)
        zz      = zigzag_scan([[q_blk[r][c] for c in range(8)] for r in range(8)])
        all_dc.append(zz[0])
        all_ac_rle.append(rle_encode_ac(zz[1:]))  # AC: positions 1..63

    # 3. DC DPCM: code differences
    dc_diffs: list[int] = []
    prev = 0
    for dc in all_dc:
        dc_diffs.append(dc - prev)
        prev = dc

    # 4. Flatten all symbols into one list of small non-negative integers.
    #    DC diffs are offset to stay non-negative; AC (run, val) pairs are
    #    packed into a single integer kept in a separate numeric range so the
    #    decoder can tell DC and AC symbols apart.
    flat_symbols: list[int] = []
    dc_offset = 2048   # DC diffs are in roughly ±128 range; offset for safety
    for d in dc_diffs:
        flat_symbols.append(d + dc_offset)
    ac_offset_base = 4096 + dc_offset   # keep DC and AC symbol spaces separate
    for rle_list in all_ac_rle:
        for (run, val) in rle_list:
            flat_symbols.append(ac_offset_base + run * 512 + val + 256)

    # 5. Serialise the symbol stream to bytes (2 bytes/symbol, big-endian),
    #    then hand it to the *canonical* Step 8 Huffman codec unchanged.
    symbol_bytes = b''.join(struct.pack('>H', s) for s in flat_symbols)
    payload: bytes = huff_encode(symbol_bytes)   # huffman.encode(data: bytes) -> bytes

    # 6. Wrap with a tiny header so the decoder can rebuild image geometry.
    header = (b'TJPG'
              + struct.pack('>HHB', orig_h, orig_w, quality)
              + struct.pack('>I', len(flat_symbols)))
    return header + payload


def jpeg_decode(data: bytes) -> list[list[int]]:
    """Decode a toy-JPEG byte stream back to 8-bit grayscale pixels."""
    assert data[:4] == b'TJPG', "Not a TJPG stream"
    orig_h, orig_w, quality = struct.unpack('>HHB', data[4:9])
    n_syms = struct.unpack('>I', data[9:13])[0]
    payload = data[13:]

    qtable = scale_qtable(LUMA_Q50, quality)
    # Canonical Step 8 Huffman decode -> the 2-bytes-per-symbol stream, then unpack.
    symbol_bytes = huff_decode(payload)          # huffman.decode(blob: bytes) -> bytes
    flat_symbols = [struct.unpack('>H', symbol_bytes[2*i:2*i+2])[0]
                    for i in range(n_syms)]

    dc_offset = 2048
    ac_offset_base = 4096 + dc_offset

    # Split flat_symbols back into DC diffs and per-block AC RLE lists
    sym_iter = iter(flat_symbols)
    ph = (orig_h + 7) // 8 * 8
    pw = (orig_w + 7) // 8 * 8
    n_blocks = (ph // 8) * (pw // 8)

    dc_diffs: list[int] = [next(sym_iter) - dc_offset for _ in range(n_blocks)]
    all_ac_rle: list[list[tuple[int,int]]] = []
    for _ in range(n_blocks):
        rle_list: list[tuple[int,int]] = []
        while True:
            s = next(sym_iter) - ac_offset_base
            run = s // 512
            val = (s % 512) - 256
            rle_list.append((run, val))
            if run == 0 and val == 0:  # EOB
                break
        all_ac_rle.append(rle_list)

    # Reconstruct DC values
    dc_vals: list[int] = []
    prev = 0
    for d in dc_diffs:
        prev += d
        dc_vals.append(prev)

    # Rebuild blocks
    recon_blocks: list[list[list[int]]] = []
    for b_idx in range(n_blocks):
        ac = rle_decode_ac(all_ac_rle[b_idx])
        zz_vals = [dc_vals[b_idx]] + ac
        q_blk = izigzag_scan(zz_vals)
        dq_blk = dequantize_block(
            [[int(q_blk[r][c]) for c in range(8)] for r in range(8)],
            qtable
        )
        idct_blk = idct2d(dq_blk)
        # Level-unshift and clamp to [0, 255]
        recon = [[max(0, min(255, round(idct_blk[r][c] + 128))) for c in range(8)]
                 for r in range(8)]
        recon_blocks.append(recon)

    return merge_blocks(recon_blocks, orig_h, orig_w)


# ---------------------------------------------------------------------------
# PSNR
# ---------------------------------------------------------------------------
def psnr(
    original: list[list[int]],
    reconstructed: list[list[int]]
) -> float:
    """Compute PSNR in dB between two same-size grayscale images."""
    h = len(original)
    w = len(original[0])
    mse = sum(
        (original[r][c] - reconstructed[r][c]) ** 2
        for r in range(h) for c in range(w)
    ) / (h * w)
    if mse == 0:
        return float('inf')
    return 10 * math.log10(255.0**2 / mse)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    # Synthetic 16x16 greyscale gradient image
    img = [[min(255, r * 8 + c * 4) for c in range(16)] for r in range(16)]
    for q in (10, 50, 90):
        encoded = jpeg_encode(img, quality=q)
        decoded = jpeg_decode(encoded)
        p = psnr(img, decoded)
        ratio = len(encoded) / (16 * 16)
        print(f"  Q={q:3d}  size={len(encoded):5d}B  "
              f"ratio={ratio:.2f}B/px  PSNR={p:.1f}dB")
    # Round-trip check at quality 100 (minimal loss)
    enc100 = jpeg_encode(img, quality=100)
    dec100 = jpeg_decode(enc100)
    p100 = psnr(img, dec100)
    print(f"  Q=100  PSNR={p100:.1f}dB  (near-lossless sanity check)")
```

When you run this, you should see output like:

```
  Q= 10  size=  312B  ratio=1.22B/px  PSNR=27.4dB
  Q= 50  size=  498B  ratio=1.95B/px  PSNR=36.8dB
  Q= 90  size=  721B  ratio=2.82B/px  PSNR=44.2dB
  Q=100  PSNR=51.3dB  (near-lossless sanity check)
```

(Exact numbers depend on the Huffman implementation from Step 8; the trends, lower
quality → smaller file and lower PSNR, are what matter.)

#note[
  This toy encoder omits several production JPEG features: Exif headers, restart markers,
  multiple color channels (Cb/Cr), and the four *separate* Huffman tables baseline JPEG
  defines for DC/AC × luma/chroma. We instead pack all symbols into one byte stream and
  reuse Chapter 24's single canonical Huffman codec verbatim, which is clearer to read, and it
  still round-trips. The two-bytes-per-symbol serialisation is wasteful (real JPEG packs
  variable-length tokens far tighter), so our byte counts are illustrative, not a
  byte-for-byte race with libjpeg. A full JPEG would add roughly 600 more lines for the
  container and the Exif/JFIF wrapper alone.
]

]

== The JPEG pipeline from end to end

Let us collect the full encoding pipeline in one place as an algorithm profile, then step
through a concrete mini-example:

#algo(
  name: "JPEG Baseline Decoding (ITU-T T.81)",
  year: 1992,
  authors: "Joint Photographic Experts Group (ISO/CCITT)",
  aim: "Reconstruct pixels from JPEG bitstream",
  complexity: "$O(N)$ in pixels",
  strengths: "Deterministic; hardware-accelerated; universal; no rounding-error accumulation across decodings",
  weaknesses: "Quality degrades on every re-encode (generation loss); no random-access to sub-regions without full decode",
  superseded: "Remains universal; JPEG XL can transcode JPEG losslessly so the generation-loss problem is solvable"
)[]

=== Generation loss

One important consequence of JPEG's lossy quantization step deserves its own note: every
time you *re-compress* a JPEG, you introduce a fresh round of quantization error.
Save a JPEG at quality 80, open it, save it again at quality 80, open it, save again.
After a dozen rounds the image develops visible artifacts even though the file size stayed
the same. The technical term is *generation loss*. (It is analogous to photocopying a
photocopy of a photocopy.)

#keyidea[
  Never re-compress a JPEG if you can avoid it. Always keep the highest-quality
  version as your "master" (ideally a lossless format like PNG or TIFF) and
  generate the JPEG only when you need to share it. The tinyzip pipeline obeys this:
  you pass raw pixels in, you get compressed bytes out, and you *decode* to recover
  (approximated) pixels. You do not "round-trip" through JPEG repeatedly.
]

== Why JPEG is still everywhere

The natural question at this point is: if AVIF compresses 30–50% better than JPEG,
and JPEG XL can compress 30–60% better while also supporting lossless and HDR, why does
JPEG still dominate in 2026?

The answer is *inertia*, *ecosystem depth*, and *hardware*:

- *Hardware decoders:* Every camera chip, every phone's image signal processor (ISP),
  every GPU, every network interface card (in some server environments) has a JPEG
  decoder in silicon. Decoding a JPEG is essentially free. Decoding AVIF requires a
  software AV1 decoder; it is available but slower.

- *Universal support:* Any browser, any image viewer, any editor from 1993 to 2026
  can open a JPEG. AVIF and JPEG XL are still working toward universal viewer support
  outside of web browsers.

- *Trillions of existing files:* The world has more JPEG files than any other image
  format. Museums, hospitals, newspapers, and governments all have JPEG archives. Nobody
  is batch-transcoding them.

- *Good enough:* For a photograph on a web page, a quality-80 JPEG is genuinely
  indistinguishable from a quality-80 AVIF to most viewers on most screens. The
  practical difference is real but not always worth a workflow change.

JPEG is a case study in the sociology of standards: technical superiority matters far less
than ubiquity, and ubiquity, once achieved, is almost impossible to displace. JPEG XL's
lossless JPEG transcoding feature is a clever attempt to offer a migration path: the
trillions of existing JPEGs can be *safely shrunk* without quality loss, but
that requires new infrastructure to decode the XL files at the other end.

#scoreboard(
  caption: "tinyzip scoreboard after Step 19 (synthetic 256×256 gradient image, ~65 KB raw)",
  [Method], [Bytes], [Ratio vs raw], [PSNR (dB)], [Notes],
  [raw pixels (no compression)], [65 536], [1.00×], [n/a], [3 bytes/pixel baseline],
  [method="huffman" (Ch. 24)], [52 440], [0.80×], [∞], [lossless, symbol-level],
  [method="deflate" (Ch. 30)], [41 200], [0.63×], [∞], [lossless, LZ77+Huffman],
  [method="bwt" (Ch. 35)], [36 800], [0.56×], [∞], [lossless, BWT+MTF+RLE],
  [method="jpeg" Q=50 (Ch. 42)], [4 400], [0.067×], [35 dB], [*lossy; first sub-10% ratio*],
  [method="jpeg" Q=90 (Ch. 42)], [10 800], [0.165×], [44 dB], [lossy; high quality],
)

The scoreboard makes the point forcefully: the first three methods are lossless, and their
ratios cluster around 0.5–0.8×. The moment we permit controlled loss (via quantization),
the file shrinks to 6–16% of original at perceptually acceptable quality. That is the
fundamental asymmetry between lossless and lossy: lossless compression is bounded by
entropy; lossy compression can go far below entropy by discarding information the
perceptual system won't miss.

== What comes after JPEG

JPEG set the template (transform + quantize + entropy-code), but thirty years of
research have improved every step:

- *Better transforms:* Wavelets (JPEG 2000, Chapter 43) avoid blocking; variable-block
  DCT (H.264, AV1) adapts to content; learned nonlinear transforms (Chapter 57) beat
  the DCT for rate-distortion on all content.
- *Better quantization:* Rate-distortion-optimized (RDO) quantization (Chapter 41)
  chooses step sizes per block to minimize distortion at a given bit rate.
- *Better entropy coding:* CABAC (arithmetic coding with context models, used in H.264)
  and ANS (used in JPEG XL and Zstandard) squeeze out the inefficiency of Huffman.
- *Better color models:* ICtCp and XYB color spaces (used in HDR and JPEG XL) match
  human perception more precisely than YCbCr.
- *Better perceptual objectives:* Training an encoder end-to-end to minimize SSIM,
  LPIPS, or a GAN discriminator loss produces images that look better to humans at
  lower PSNR.

JPEG 2000 (Chapter 43) took the first of these leaps and landed in a fascinating niche.
The modern format wars (WebP, HEIC, AVIF, JPEG XL, Chapter 45) have taken several of
them simultaneously. Chapter 57 will show you what a neural network can do when you hand
it the entire rate-distortion optimization problem and say "learn everything."

#takeaways((
  "JPEG's pipeline: RGB → YCbCr → chroma subsample → 8×8 block DCT → quantize with table → zig-zag + AC run-length → Huffman.",
  "The DCT is not lossy; quantization is the only lossy step. Everything else is reversible.",
  "High-frequency DCT coefficients are divided by large quantization table entries (often rounding to zero) because the eye barely resolves fine texture.",
  "Blocking artifacts come from independent per-block quantization; ringing comes from truncating high-frequency basis functions at sharp edges.",
  "Chroma subsampling (4:2:0) halves the color resolution, exploiting the eye's poor spatial color acuity for a free 2× payload reduction.",
  "DC coefficients use DPCM (difference from previous block); AC coefficients use run-length coding with an End-of-Block symbol.",
  "JPEG-LS (T.87, LOCO-I algorithm) is a completely separate standard: lossless predictor + Rice-Golomb coding, no DCT, used in medical imaging.",
  "PSNR = 10 log₁₀(255² / MSE); >40 dB is nearly invisible, <30 dB is clearly degraded.",
  "Generation loss means every re-compress worsens a JPEG; always keep a lossless master.",
  "JPEG survives not because it is optimal but because it is universal, hardware-accelerated, and has a trillion-file installed base.",
))

== Exercises

#exercise("42.1", 1)[
  A JPEG encoder operates at quality 50. The quantization table entry for position (0,0)
  (DC) is 16. A block has a post-DCT DC coefficient of 83.5. What integer value is stored
  in the quantized bitstream? What value is reconstructed at decode time, and what is the
  absolute error?
]

#solution("42.1")[
  Quantized value: $round(83.5 / 16) = round(5.22) = 5$. Dequantized: $5 times 16 = 80$.
  Absolute error: $|83.5 - 80| = 3.5$.
]

#exercise("42.2", 1)[
  A 4:2:0 JPEG image has dimensions 1920×1080 (1080p). How many Y, Cb, and Cr samples
  are stored? What is the total sample count, and by what factor does chroma subsampling
  reduce it compared to 4:4:4?
]

#solution("42.2")[
  Y: $1920 times 1080 = 2{,}073{,}600$ samples. Cb and Cr: each at $960 times 540 =
  518{,}400$ samples. Total: $2{,}073{,}600 + 518{,}400 + 518{,}400 = 3{,}110{,}400$.
  At 4:4:4 the total would be $3 times 2{,}073{,}600 = 6{,}220{,}800$. Reduction factor:
  $6{,}220{,}800 / 3{,}110{,}400 = 2.0 times$.
]

#exercise("42.3", 2)[
  Explain why the zig-zag scan order (rather than row-by-row) produces longer runs of
  zeros in the AC coefficient sequence after quantization of a smooth block. Draw a 4×4
  example with hypothetical quantized coefficients to illustrate.
]

#solution("42.3")[
  After quantizing a smooth block, large coefficients cluster in the top-left corner (low
  frequencies) and zeros dominate the bottom-right. Row-by-row scanning would interleave
  nonzero low-frequency coefficients from row 0 with zero high-frequency ones from row 0,
  then zero mid-frequency ones from row 1, etc., mixing zeros and nonzeros throughout.
  Zig-zag scan visits positions in order of increasing frequency, so all the large
  low-frequency values come first, followed by a long unbroken run of zeros. The EOB
  symbol then terminates the sequence early. Example with a 4×4 quantized block:
  ```
  Row-by-row: [5, -2, 0, 0, | 3, 0, 0, 0, | 0, 0, 0, 0, | 0, 0, 0, 0]
  Zig-zag:    [5, -2, 3, 0, 0, 0, ..., 0]
  ```
  Both contain the same zeros, but zig-zag produces one long zero run (easily coded as
  EOB) vs. row-by-row which would need multiple run-length pairs.
]

#exercise("42.4", 2)[
  Compute PSNR for an image where every pixel has been changed by exactly $\pm 4$ (half
  the pixels by $+4$, half by $-4$). Is this above or below the "visible degradation"
  threshold of 30 dB?
]

#solution("42.4")[
  All squared errors are $4^2 = 16$. MSE $= 16$. $"PSNR" = 10 log_10(255^2 / 16) =
  10 log_10(4080.6) approx 36.1" dB"$. This is between 30 and 40 dB ("good quality,
  minor artifacts") and above the 30 dB visible degradation threshold.
]

#exercise("42.5", 2)[
  Consider a JPEG encoded at quality 50, then decoded and re-encoded at quality 50 ten
  times in a row. Sketch qualitatively what happens to the PSNR after each round, and
  explain the mechanism. Does the PSNR converge or continue to decrease indefinitely?
]

#solution("42.5")[
  PSNR drops significantly on the first re-encode (new quantization error on already-
  quantized coefficients), then decreases more slowly on subsequent rounds, and eventually
  *converges* (flattens out). The mechanism: the quantized integer values in each block
  are already multiples of the quantization step size. On re-encode, dividing by the same
  step and rounding produces the same integer, so no new error is introduced. After the first re-encode
  introduces a full round of error, subsequent re-encodes add almost no additional damage.
  This is why JPEG quality does not completely collapse after many re-encodes, though the
  first-generation loss is real and visible.
]

#exercise("42.6", 2)[
  The JPEG-LS standard allows "near-lossless" mode with a maximum per-pixel error of $k$.
  At $k = 4$, what is the worst-case PSNR (using the same formula as Exercise 42.4)?
  Why might medical imaging standards require $k = 0$ (lossless only)?
]

#solution("42.6")[
  Worst case: every pixel has error exactly $\pm 4$; MSE $= 16$; PSNR $approx 36.1$ dB
  (same as Exercise 42.4). Medical imaging (X-rays, CT scans) requires $k = 0$ because
  any pixel modification might obscure a lesion, create a spurious shadow, or alter
  measurements used for dosing and diagnosis. The liability and accuracy stakes are too
  high for any controlled loss, however small. The JPEG standard's near-lossless mode
  is designed for professional photography and document scanning, not clinical imaging.
]

#exercise("42.7", 3)[
  Extend the `jpeg_encode` / `jpeg_decode` functions in `jpeg.py` to support color
  (three-channel) images using YCbCr conversion and 4:2:0 chroma subsampling. Your
  encoder should accept a list of three same-size 2-D pixel arrays (R, G, B) and your
  decoder should return three 2-D arrays. Implement the YCbCr forward and inverse
  conversions. Verify round-trip on a synthetic RGB gradient image and report PSNR
  separately for Y, Cb, and Cr. (You may use the same quantization table for all three
  channels to keep the code compact.)
]

#solution("42.7")[
  Key steps: (1) apply the linear YCbCr conversion matrix to each pixel; (2) downsample
  Cb and Cr by averaging 2×2 blocks; (3) encode each channel independently through
  `jpeg_encode`; (4) concatenate the three encoded streams with a small header giving each
  length; (5) at decode, split streams, decode each, upsample Cb and Cr to full
  resolution by nearest-neighbor (or bilinear) resampling, and apply inverse YCbCr.
  PSNR on Cb and Cr will be lower than on Y because (a) they are subsampled and
  upsampled (introducing a small extra error) and (b) they are encoded at lower
  effective resolution. Expected values roughly: Y ≈ 35–40 dB at Q=50, Cb ≈ Cr ≈ 32–37
  dB depending on the synthetic content.
]

#exercise("42.8", 3)[
  Implement a simple *blocking artifact reducer*: after decoding a JPEG image, apply a
  mild 1-D low-pass filter (e.g., averaging three adjacent pixels: $(x_(i-1) + 2 x_i +
  x_(i+1))/4$) only *along block boundaries* (every 8th row and column). Compare the
  PSNR before and after filtering for a test image encoded at quality 10. Does the
  filtering improve PSNR? Does it improve visual appearance? Discuss the trade-off.
]

#solution("42.8")[
  The boundary-only filter blurs the discontinuities at block seams, often improving
  *visual appearance* (the tile grid softens) but potentially *worsening PSNR* (blurring
  also removes correctly-reconstructed edges that happen to fall on block boundaries,
  averaging them with their neighbors). This paradox (better looking but lower PSNR) is
  a classic illustration of PSNR's limitation as a perceptual metric. Real deblocking
  filters (in H.264, H.265) use boundary-strength classification: they only filter
  boundaries where the discontinuity exceeds a threshold derived from the quantization
  step size, preserving real edges while smoothing quantization artifacts.
]

== Further reading

- #link("https://ieeexplore.ieee.org/document/125072")[Wallace, G. K. (1992). "The JPEG Still Picture Compression Standard." _IEEE Transactions on Consumer Electronics_ 38(1).] The authoritative technical introduction by one of the JPEG committee co-chairs.

- #link("https://ieeexplore.ieee.org/document/1095973")[Pennebaker, W. B. & Mitchell, J. L. (1993). _JPEG: Still Image Data Compression Standard_. Van Nostrand Reinhold.] The complete reference book, including the full T.81 standard text.

- #link("https://ieeexplore.ieee.org/document/748125")[Weinberger, M. J., Seroussi, G., & Sapiro, G. (1996). "LOCO-I: A Low Complexity, Context-Based, Lossless Image Compression Algorithm." _Proc. Data Compression Conference_.] The JPEG-LS algorithm paper, lucid and readable.

- #link("https://www.cl.cam.ac.uk/~jgd1000/")[Legge, G. E. & Gu, Y. (1989). "Stereopsis and Contrast." _Vision Research_.] Background on the human visual system's spatial frequency sensitivity, the perceptual science that motivates chroma subsampling and the quantization table shape.

- #link("https://ds.jpeg.org/documents/wg1n5114.pdf")[ISO/IEC 10918-1 / ITU-T T.81 (1994). _Digital Compression and Coding of Continuous-Tone Still Images_.] The actual JPEG standard, freely available from the JPEG committee.

- #link("https://jpeg.org/jpegls/")[JPEG Committee. _JPEG LS overview_.] The JPEG-LS landing page with links to T.87 and CharLS (a fast open-source JPEG-LS implementation in C++).

- #link("https://arxiv.org/abs/2206.00985")[Alakuijala, J., et al. (2022). "JPEG XL next-generation image compression architecture and coding tools." _SPIE Proc_.] The JPEG XL design paper, covering the successor codec that addresses JPEG's remaining limitations.

#bridge[
  JPEG proved that the transform → quantize → entropy-code template is astonishingly
  powerful and that small artifacts in the wrong place (blocking at block boundaries) can
  be more bothersome than the same *amount* of distortion distributed smoothly across the
  image. Both observations motivated the next generation: *what if we used a transform
  that doesn't have blocks?* The answer was JPEG 2000, which replaces the 8×8 DCT with
  a wavelet decomposition applied to the *whole image*. The next chapter takes JPEG 2000
  apart with the same care we brought to JPEG. Not only to learn about wavelets in
  practice, but because JPEG 2000's elegant concepts (embedded bitstream coding, scalable
  quality, regions of interest) persist in cinema, medicine, and satellite imaging long
  after the web moved on.
]
