#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Lossless and Simple Image Formats: GIF, PNG, QOI

#epigraph[
  The best compression algorithm is the one you can actually ship.
][Anonymous, comp.compression, circa 1995]

Here is a peculiar fact. The year is 1994. You work at CompuServe, the most popular online
service in the United States. Millions of people are swapping pictures over slow dial-up modems
and your company invented the format they use: the Graphics Interchange Format, GIF. One day a
letter arrives from a law firm representing a company called Unisys. It informs you, politely,
that the compression algorithm inside every GIF file is covered by a patent --- and that
CompuServe owes licensing fees, retroactively, for every copy ever distributed.

The internet does not take this calmly. Within months, a coalition of programmers launches a
project to create a free replacement. They do not just copy GIF --- they improve it in almost
every measurable way, add features GIF cannot provide, and release the specification without
patents. They call it PNG: Portable Network Graphics, or, jokingly, "PNG's Not GIF."

PNG became the universal standard for lossless images on the web. GIF, patent burden lifted
decades later, survived as the cultural home of looping animations. And in 2021, one programmer
working alone over a long weekend published a third format --- QOI, the Quite OK Image Format ---
that compresses about as well as PNG but encodes twenty to fifty times faster, fits its entire
specification on a single sheet of paper, and stores a complete decoder in roughly three hundred
lines of C.

These three formats cover a spectrum from the complexly historical to the elegantly minimal.
Together they teach lessons about patents, design constraints, the tradeoffs between compression
ratio and speed, and why simplicity is sometimes exactly the right answer.

#recap[
  Chapters 42 and 43 covered the lossy end of image compression: JPEG's 8x8 block DCT and
  quantization pipeline, and JPEG 2000's wavelet-based alternative. Both accept image
  degradation in exchange for very high compression ratios. This chapter covers the _lossless_
  end: formats that reconstruct the image pixel-perfectly. The compression techniques involved
  are ones you already know: LZW (Chapter 29), DEFLATE = LZ77 + Huffman (Chapter 30), and
  basic prediction and differencing (Chapter 40). What is new here is how these techniques get
  packaged into widely deployed, real-world file formats, and what happens when patents enter
  the picture.
]

#objectives((
  [Explain how GIF encodes pixels: palette reduction, LZW compression, and the block stream
   structure.],
  [Describe GIF89a's animation model and why it is clever and limiting in equal measure.],
  [Explain why PNG was created and how it achieves better lossless compression than GIF through
   filter predictors followed by DEFLATE.],
  [Name the five PNG filter types and explain which kind of image each suits.],
  [Decode the QOI chunk types and trace how they combine to achieve fast lossless compression.],
  [Compare the three formats on compression ratio, speed, and implementation complexity.],
  [Identify which format is the right choice for logos, photographs, animations, and pipeline
   textures.],
))

== A Taxonomy of Lossless Image Compression

Before the history, it helps to understand what "lossless image compression" actually means and
why it is different from what we did in Chapters 42 and 43.

#keyidea[
  Lossless compression means that `decode(encode(image)) == image` exactly --- every single
  pixel value comes back unchanged. No quality setting, no ringing, no blocking artifacts. The
  price is that you cannot achieve the extreme ratios lossy coding offers: natural photographs
  that compress 15:1 under JPEG might compress only 2:1 or 3:1 losslessly, because the true
  pixel-level randomness in photographic noise genuinely cannot be removed without loss.
]

Lossless compression therefore shines on images that _have_ a lot of exploitable structure
beyond what lossy coding finds useful:

- *Palettized images*: computer-generated graphics, icons, cartoon art, and illustrations that
  use a small, fixed set of colors. A screenshot of a web page might use fewer than 64 distinct
  colors despite being 1920 pixels wide. Encoding 64 colors takes 6 bits per pixel instead of
  24, a 4:1 reduction before any further compression.

- *Images needing exact pixels*: medical images (a misquantized CT scan changes a diagnosis),
  text screenshots (even a tiny blur makes letters unreadable), images with transparent areas
  (quantization artifacts at alpha-blend boundaries look terrible), and archival documents.

- *Intermediate pipeline stages*: when a professional photographer shoots in RAW, edits the
  image, and saves a master copy before exporting a JPEG for web use, they want the master to
  be lossless. Each resave through a lossy codec degrades quality cumulatively.

GIF was built for the first case (palettized graphics over dial-up modems). PNG was built for
all three. QOI was built for the third --- speed in software pipelines --- while still handling
the others adequately.

== GIF: The Format That Spawned a Culture

=== CompuServe and the Birth of GIF

In 1987, CompuServe's technical staff needed a color image format for their file-sharing areas.
They needed something that would work over modems as slow as 300 bits per second, display on a
wide range of hardware with different screen capabilities, and be completely defined by a
written specification so that any programmer could implement it.

The lead engineer, Steve Wilhite, chose the Lempel-Ziv-Welch algorithm as the compression
core. LZW (Chapter 29) was fast, well-understood, and achieved good ratios on the kind of
blocky, palette-limited images typical of 1980s computer graphics. The resulting format was
released on June 15, 1987 as *GIF87a* --- the "87" for the year and "a" for the version letter.

Two years later, in July 1989, CompuServe published *GIF89a*, the version almost everyone uses
today. It added three important extensions:

1. *Animation*: a sequence of image frames, each with a delay time. The viewer displays them in
   order, looping indefinitely or a specified number of times.
2. *Transparent color*: one palette index can be designated as transparent, letting a background
   show through (though only fully on or fully off --- no partial transparency).
3. *Comment extensions*: arbitrary metadata blocks for copyright notices or creation tools.

GIF89a is the format behind every looping cat video, every reaction GIF, and every vintage web
animation you have ever seen. Its cultural footprint is enormous out of all proportion to its
technical sophistication.

=== The GIF Palette: Up to 256 Colors

Here is the central constraint of GIF: it supports at most *256 colors per frame*.

More precisely, each GIF frame has a color table --- a list of up to 256 RGB triplets. Instead
of storing the red, green, and blue values for every pixel directly (3 bytes per pixel), GIF
stores a single *palette index*: a number from 0 to 255 pointing into the color table (1 byte
per pixel, or fewer if the table is small). This is called *indexed color* or *palettized
color*.

#fig([GIF color model: a small palette of RGB entries on the left; each pixel in the image
stores a 1-byte index that points into the palette.],
cetz.canvas({
  import cetz.draw: *
  // Palette on left
  rect((0,0),(2,5), fill: rgb("#f5f5f5"), stroke: 1pt)
  content((1,5.5))[#text(size:8pt, weight:"bold")[Color Table]]
  let cols = (rgb("#e63946"), rgb("#457b9d"), rgb("#a8dadc"), rgb("#1d3557"), rgb("#f1faee"))
  for i in range(5) {
    let y0 = 0.2 + i * 0.9
    let y1 = 0.9 + i * 0.9
    rect((0.1, y0),(1.9, y1), fill: cols.at(i), stroke: 0.5pt)
    content((2.5, (y0+y1)/2))[#text(size:7pt)[idx #i]]
  }
  // Arrow
  line((3.2,2.5),(3.8,2.5), mark:(end:"stealth"), stroke: 1.5pt)
  // Pixel grid on right
  let pgrid = ((0,1,2,1,0),(1,2,3,2,1),(2,3,4,3,2),(1,2,3,2,1),(0,1,2,1,0))
  for row in range(5) {
    for col in range(5) {
      let idx = pgrid.at(row).at(col)
      let xi = 4.0 + col * 0.7
      let yi = 0.2 + row * 0.9
      rect((xi, yi),(xi+0.6, yi+0.7), fill: cols.at(idx), stroke: 0.3pt)
      content((xi+0.3, yi+0.35))[#text(size:6pt, fill: white)[#idx]]
    }
  }
  content((5.7,5.5))[#text(size:8pt, weight:"bold")[Index Grid]]
}))

For photographs with millions of shades, 256 colors is brutally insufficient --- the result is
visible banding and posterization. But for line art, logos, cartoons, and interface screenshots
with a limited palette, it works surprisingly well. Many such images naturally use fewer than
256 colors and need no approximation at all.

When an image _does_ have more colors than fit in the palette, an *encoder* must perform
*color quantization*: choosing 256 representative colors and mapping each original pixel to its
nearest match. Good quantizers (like the median-cut algorithm) are clever about this, but some
visual quality is inevitably lost.

#definition("Palette index")[
  In a palettized image, each pixel is stored not as a color value but as an index into a fixed
  lookup table (the palette or color table). Decoding a pixel means reading the index and looking
  up the corresponding color in the table.
]

=== LZW Compression Inside GIF

Once the image is expressed as a grid of palette indices, GIF applies *LZW compression* to that
stream of integers. We covered LZW in detail in Chapter 29, but here is a quick recap of how it
works in GIF's context.

#mathrecall[
  LZW builds a *code dictionary* that starts with one entry for each possible input symbol
  (here, palette indices 0-255). It scans the input left to right, finding the longest string
  already in the dictionary, emits its code number, then adds the current string extended by one
  symbol as a new dictionary entry. The decoder can reconstruct the dictionary identically from
  the code stream alone, so it does not need to be transmitted.
]

GIF adds a small twist: the initial dictionary does not just contain the 256 palette values. It
also contains a *clear code* and an *end-of-information code*. The clear code resets the
dictionary (needed when the dictionary fills up at 4096 entries), and the end code signals the
finish of data. The minimum LZW code size in GIF is 2 bits (for images with only 2 colors) up
to 8 bits (for full 256-color images).

To save bits, GIF lets the codes _grow as the dictionary grows_. Recall from Chapter 4 that to
name one of $N$ things you need $ceil(log_2 N)$ bits. With an 8-bit minimum code size, the
dictionary starts holding $256$ palette entries plus the clear and end codes --- $258$ values ---
so the first codes emitted are $9$ bits wide (since $2^8 = 256 < 258 <= 512 = 2^9$). Each time a
new entry pushes the dictionary count past the next power of two ($512$, then $1024$, then
$2048$), the code width ticks up by one bit, to a maximum of $12$ bits at $4096$ entries. When
the dictionary is full the encoder emits a clear code, both sides reset to the start width, and
the cycle begins again. The decoder tracks the same counts and so always knows exactly how many
bits to read next without any width markers in the stream.

The compressed codes are packed into *data sub-blocks* of at most 255 bytes each, prefixed by a
byte giving the block length. This was a pragmatic choice for streaming over slow modems: a
reader can skip a block even if it does not understand the extension type.

#algo(
  name: "GIF LZW Encoding",
  year: "1987",
  authors: "Steve Wilhite / CompuServe (based on LZW by Terry Welch, 1984)",
  aim: "Losslessly compress a stream of palette indices using an adaptive string dictionary",
  complexity: "$O(n)$ time and space (dictionary at most 4096 entries)",
  strengths: "Simple to implement; self-contained dictionary (no side-channel); effective on repetitive palette art",
  weaknesses: "Limited to 256 colors; dictionary resets lose context; patent-encumbered until 2003-2004",
  superseded: "Superseded by PNG's DEFLATE filters for general lossless use; still dominant for short looping animations",
)[
  GIF LZW works exactly like the LZW algorithm of Chapter 29, with two additions: (1) the
  initial dictionary includes a Clear Code and End Code alongside the palette entries; (2) the
  variable-length codes start at `minimum_code_size + 1` bits and grow by 1 bit each time the
  dictionary doubles, resetting to the start size after a Clear Code.
]

=== GIF89a's Animation Model

The animation extension in GIF89a is remarkably clever for 1989. Each *frame* is stored as an
independent GIF image block, preceded by a *Graphic Control Extension* block that specifies:

- *Delay time* in hundredths of a second (so delay = 10 means 100 ms between frames)
- *Disposal method*: what to do with the previous frame before rendering the next one
  (leave it, restore to background, restore to previous state)
- *Transparent color index*: which palette entry is transparent in this frame

The disposal method is the key to efficient animation. If most of a frame is identical to the
previous one, only the *changed region* needs updating --- the changed region is stored as a
smaller sub-image at an offset within the frame. A bouncing ball against a static background
can store the full background once and then only small patches around the ball's position for
each subsequent frame.

#aside[
  GIF animation has a hard technical limit many people do not know: each frame can only have
  *one* palette of up to 256 colors. Multi-frame animations can use *different* palettes per
  frame (GIF89a allows each frame its own local color table), which lets individual frames
  represent more color variety --- but the result is still palette-per-frame, not a unified
  color space. The 256-color limit per frame is why early web animations look the way they do.
]

#pitfall[
  The "GIF is lossless" claim is only conditionally true. If your source image fits in 256
  colors, GIF encodes it losslessly. If it does not --- a photograph, for example --- the
  *color-quantization step* that reduces it to 256 colors is lossy. Many people have been
  surprised to find that saving and reloading a "lossless GIF" of a photograph destroyed
  color accuracy. Always use PNG or a modern format for photographs you need to preserve exactly.
]

=== The Patent Shock of 1994

The LZW algorithm was patented by Terry Welch in 1983, and the patent (US4558302) was assigned
to Sperry Corporation, which merged with Burroughs to form Unisys in 1986. When CompuServe
designed GIF in 1987, they were not aware of the patent --- or at least, believed it was not
being actively enforced in software.

In January 1993, Unisys began licensing negotiations with CompuServe. On December 24, 1994 ---
Christmas Eve --- CompuServe announced the licensing agreement: developers who created software
that read or wrote GIF files would owe royalties to Unisys. The internet reacted with fury.
The backlash was immediate and sustained: boycotts, "Burn All GIFs" campaigns, and most
importantly, a coordinated effort to build a free replacement.

The US patent expired on June 20, 2003. European, UK, French, German, Italian, and Japanese
counterparts expired in June and July 2004. GIF has been completely patent-free for over two
decades as of this writing. But the damage was done --- PNG had already established itself, and
the story of the patent war had become one of the defining cautionary tales of open standards.

#history[
  The GIF patent controversy is often cited as one of the earliest large-scale demonstrations
  of how software patents can distort the evolution of technology. It directly caused PNG to be
  invented, directly motivated the open-source community to build royalty-free alternatives, and
  influenced later format politics around arithmetic coding (Chapter 26), HEVC (Chapter 53), and
  the Alliance for Open Media's decision to build AV1 (Chapter 54) without patent encumbrances.
  Compression history keeps teaching the same lesson: a format's technical quality is only one
  of the forces that determines whether it wins.
]

== PNG: The Format Built in Anger

=== Origin: January 1995

The first proposal for PNG appeared on January 4, 1995 --- just ten days after CompuServe's
Christmas Eve announcement --- in a Usenet post on comp.graphics by Thomas Boutell. The
specification that followed was authored by twenty-three people. Their mandate was explicit:
create a format that is:

1. Freely usable, with no patents on any part of the core algorithm.
2. Lossless (exact pixel reconstruction, always).
3. Better compression than GIF, using the freely available DEFLATE algorithm.
4. Better color: full 24-bit RGB (16.7 million colors), full 32-bit RGBA with a true 8-bit
   alpha channel (not just on/off transparency).
5. Portable across all platforms, with robust error detection.

They succeeded on all five counts. PNG version 1.0 was published as RFC 2083 in March 1996.
The format is now an ISO standard (ISO/IEC 15948:2004) and, in its third edition published June
24, 2025, officially incorporates the APNG animated PNG extension that Firefox pioneered in
2008, along with HDR and wide-gamut support.

=== PNG's Technical Pipeline

PNG's lossless compression is a two-stage process: *prediction* followed by *entropy coding*.
The prediction stage is where PNG's major technical insight lives.

==== Stage 1: Row Filters (Prediction)

Before any compression, PNG processes the image one row at a time, replacing raw pixel values
with prediction errors. This is exactly the DPCM idea from Chapter 40 applied to images.

A *filter* is applied independently to each row. The filter replaces each byte value with the
difference between that byte and a predicted value. If the prediction is good --- if it guesses
the pixel's color well based on its neighbors --- the difference will be small, and small
numbers compress much better than large ones (they have fewer non-zero bits for DEFLATE to
encode).

PNG defines five filter types, selectable per row:

#fig([The five PNG row filter types and their predictor neighborhoods. Each type replaces
the actual pixel value x with a residual (x minus the predicted value). Sub uses the left
neighbor; Up uses the pixel above; Average uses the mean of both; Paeth picks the closest
of three neighbors to a linear estimate.],
cetz.canvas({
  import cetz.draw: *
  // Draw five mini-grids
  let draw_mini(xo, label, hi_left, hi_up, hi_ul) = {
    // "Previous row" cells
    let labels_above = ("c","b",".")
    let labels_row   = ("a","x",".")
    for col in range(3) {
      let xi = xo + col * 0.85
      let highlight = (col == 0 and hi_ul) or (col == 1 and hi_up)
      rect((xi, 1.2),(xi+0.75, 1.95),
           fill: if highlight { rgb("#ffe066") } else { rgb("#e8e8e8") },
           stroke: 0.5pt)
      content((xi+0.375, 1.575))[#text(size:6.5pt)[#labels_above.at(col)]]
    }
    for col in range(3) {
      let xi = xo + col * 0.85
      let highlight = col == 0 and hi_left
      let is_x = col == 1
      rect((xi, 0.3),(xi+0.75, 1.1),
           fill: if is_x { rgb("#74c0fc") }
                 else if highlight { rgb("#ffa94d") }
                 else { rgb("#e8e8e8") },
           stroke: 0.5pt)
      content((xi+0.375, 0.7))[#text(size:6.5pt)[#labels_row.at(col)]]
    }
    content((xo+0.85, -0.1))[#text(size:6.5pt, weight:"bold")[#label]]
  }
  draw_mini(0.0,  "None",    false, false, false)
  draw_mini(2.8,  "Sub",     true,  false, false)
  draw_mini(5.6,  "Up",      false, true,  false)
  draw_mini(8.4,  "Average", true,  true,  false)
  draw_mini(11.2, "Paeth",   true,  true,  true)
}))

+ *None* --- store raw pixel bytes. No prediction, no transformation. Used when the data is
  already random or nearly so (rare in practice).

+ *Sub* --- predict each byte from the byte directly to its left (the same channel of the
  previous pixel in the same row). Works well on gradients that change primarily left-to-right.

+ *Up* --- predict each byte from the byte directly above it (same position, previous row).
  Works well on vertically-striped or slowly changing content.

+ *Average* --- predict from the arithmetic mean of left and above: `predict = floor((a + b)/2)`.
  Balances horizontal and vertical correlation.

+ *Paeth* --- the most sophisticated filter, named after its inventor Alan W. Paeth (1991).
  Predicts from whichever of `a` (left), `b` (above), or `c` (upper-left) is numerically
  closest to the linear prediction `p = a + b - c`. This performs best on images with diagonal
  gradients and smooth blending.

#gomaths("The Paeth Predictor")[
  The Paeth predictor computes $p = a + b - c$ where $a$ is the left byte, $b$ is the byte
  above, and $c$ is the byte at the upper-left. Then it picks whichever of $a$, $b$, $c$ is
  closest to $p$ in absolute value, calling that the prediction.

  *Example.* Suppose $a = 100$, $b = 120$, $c = 90$. Then
  $p = 100 + 120 - 90 = 130$.
  We compute $|130 - 100| = 30$, $|130 - 120| = 10$, $|130 - 90| = 40$.
  The minimum is 10 (for $b$), so the prediction is $b = 120$.
  If the actual pixel value is 118, the filter output is $118 - 120 = -2$, stored modulo 256
  as $254$ (one byte).

  The predictor is clever because the linear estimate $p$ lies along the "trend" of the gradient
  through the three neighbors; whichever neighbor is closest to $p$ is the one whose correlation
  with $x$ is strongest.
]

The encoder tries all five filters on every row and picks the one that produces the smallest
sum of absolute filter values --- a fast heuristic for which filter will compress best
downstream. An encoder can even use different filters on different rows of the same image.

This per-row adaptivity is one of PNG's key advantages over GIF. GIF just compresses the raw
pixel bytes with LZW. PNG transforms the data into small residuals first, then applies entropy
coding to those residuals. Small residuals (clustered near zero) compress dramatically better
than large pixel values spread across 0-255.

==== Stage 2: DEFLATE Compression

After filtering, the residual bytes are compressed with DEFLATE --- the same algorithm used by
gzip, zlib, and ZIP (Chapter 30). DEFLATE combines LZ77 sliding-window matching (finding
repeated byte sequences and encoding them as back-references) with Huffman coding of the
tokens.

#pyrecall[
  In Chapter 30 we saw that DEFLATE uses a 32 KB sliding window. A match is encoded as
  `(distance, length)` --- "the bytes starting 1,200 positions back, 18 bytes long."
  Literals (bytes that do not match anything) and length-distance pairs share a single Huffman
  tree. The filtered scanlines from PNG are concatenated into one byte stream and fed to this
  engine.
]

The reason this beats GIF's LZW is two-fold. First, LZ77 in DEFLATE is simply a more powerful
general-purpose compressor than LZW. Second, and more importantly, the PNG filter pre-process
produces _much_ more compressible data. A photograph's raw pixel values are complex; the same
photograph's Sub-filter residuals (each pixel minus its left neighbor) are mostly small values
clustered around zero, with a sharp distribution that DEFLATE can exploit heavily.

#checkpoint[
  A PNG file contains image data compressed with DEFLATE. Before DEFLATE, what step is applied,
  and why does that step help compression?
][
  Before DEFLATE, each image row is passed through a predictor filter that replaces pixel values
  with prediction errors (residuals). Because neighboring pixels are usually similar, residuals
  are small and cluster near zero. Small, clustered values compress better than arbitrary pixel
  values because they have more redundancy (more repeated patterns and shorter runs) for DEFLATE
  to exploit.
]

==== PNG File Structure: Chunks

A PNG file begins with an 8-byte signature: the bytes `0x89 50 4E 47 0D 0A 1A 0A`. (The first
byte is 0x89, a non-ASCII byte that catches transmission modes that strip high bits; then "PNG"
in ASCII; then carriage-return+line-feed to catch systems that mangle line endings; then a
Ctrl-Z that stops `type` commands on DOS; then a line-feed.) This 8-byte magic number serves as
a platform portability test.

After the signature, the file is a sequence of *chunks*. Each chunk has four fields:

- *Length* (4 bytes): the number of bytes in the chunk data field
- *Type* (4 bytes): a four-letter ASCII code identifying the chunk type
- *Data* (variable): the chunk's content
- *CRC* (4 bytes): a CRC-32 checksum over the type plus data, for error detection

#mathrecall[
  A *CRC-32* (cyclic redundancy check) is the 32-bit integrity checksum we built into the
  `tinyzip` container in Chapter 17: a bit-mixing function that maps any `bytes` to a number
  extremely sensitive to change, so flipping a single bit almost always changes the result. PNG
  recomputes each chunk's CRC on read and rejects the file if it disagrees with the stored value.
]

The critical (required) chunks in a standard PNG are:

- `IHDR` --- Image header: width, height, bit depth (1-16 bits per channel), color type
  (grayscale, RGB, palette, or with alpha), and compression, filter, and interlace methods.
- `IDAT` --- Image data: one or more chunks containing the zlib-wrapped DEFLATE stream of
  filtered scanlines. Multiple `IDAT` chunks are concatenated before decompression.
- `IEND` --- Image end: an empty marker chunk signaling the end of the PNG.

Optional ancillary chunks carry metadata: `PLTE` (the palette for indexed-color images),
`tEXt` and `iTXt` (text metadata), `gAMA` (gamma), `cHRM` (chromaticity), `sRGB`
(colorimetry), `bKGD` (background color), `tIME` (last modification time), and many more.

#algo(
  name: "PNG Encode Pipeline",
  year: "1996",
  authors: "Thomas Boutell et al. (PNG Development Group)",
  aim: "Losslessly compress raster images with better ratio than GIF and no patent issues",
  complexity: "$O(n)$ for filter and DEFLATE; memory proportional to window size (32 KB)",
  strengths: "Excellent ratio on graphics and screenshots; true alpha channel; robust chunk CRC; free of patents; interlace/progressive mode (Adam7); APNG animation (PNG 3rd ed., 2025)",
  weaknesses: "Larger files than JPEG for photographs; encoding can be slow at high compression levels; no native animation until APNG",
  superseded: "Not superseded for lossless web images; AVIF and JPEG XL are strong competitors for photographs; QOI preferred in performance-critical pipelines",
)[
  PNG encodes an image as: (1) convert to target color type; (2) for each row, apply the
  best-estimated filter (None/Sub/Up/Average/Paeth) to produce residual bytes; (3) compress all
  filtered rows concatenated via zlib/DEFLATE; (4) wrap in PNG chunk structure with CRC-32
  integrity on each chunk; (5) output 8-byte signature + IHDR + optional PLTE + IDAT + IEND.
  Decoding reverses: verify CRCs, decompress DEFLATE, un-filter each row (the inverse filter is
  modular addition), output pixels.
]

=== The Paeth Filter in Practice: A Worked Example

Let us trace through one small row of pixels to make the filter concrete.

Suppose a row of a grayscale image (one byte per pixel) is:

```
Raw pixels:     100  103  106  108  110  109  108
```

The row above (all we need are the same positions, the "b" values) is:

```
Row above:       98   99  101  104  107  108  110
```

We apply the *Sub* filter: subtract the left neighbor from each pixel. The leftmost pixel has
no left neighbor, so it is stored raw.

```
Sub residuals:  100    3    3    2    2  255  255
```

(The values -1 become 255 by modular arithmetic.) Six of the seven values are single digits.
DEFLATE will compress sequences of small numbers much more efficiently than the original values
ranging from 100 to 110.

Now try the *Up* filter instead --- subtract the pixel above:

```
Up residuals:     2    4    5    4    3    1  254
```

All small. The encoder computes the sum of absolute values for each filter (using signed
interpretation of byte residuals --- values over 127 are treated as negative):

- Sub: $|100| + |3| + |3| + |2| + |2| + |-1| + |-1| = 112$
- Up: $|2| + |4| + |5| + |4| + |3| + |1| + |-2| = 21$

Up wins for this row, so the encoder writes a `0x02` byte (filter type 2 = Up) before the
residual data. The decoder reads that byte first and knows to apply the inverse: add the pixel
above to each residual (modulo 256).

=== PNG Color Modes

PNG supports a rich variety of color representations, unlike GIF's fixed-palette model:

- *Grayscale*: 1, 2, 4, 8, or 16 bits per pixel. Used for scientific images, X-rays, and masks.
- *Indexed color* (palette): 1, 2, 4, or 8 bits per pixel index, with a PLTE chunk listing up to
  256 RGB entries. Compatible with GIF's model but using better compression.
- *True color (RGB)*: 8 or 16 bits per channel, for 24-bit or 48-bit color. No palette.
- *Grayscale with alpha*: 8 or 16 bits per gray channel plus 8 or 16 bits of alpha.
- *True color with alpha (RGBA)*: 8 or 16 bits per channel, 4 channels. The full 32-bit or
  64-bit format with complete transparency information. Absolutely cannot be represented in GIF.

The 16-bit-per-channel modes were ahead of their time in 1996 and are now essential for HDR
workflows and scientific imaging.

=== APNG: Animation Comes to PNG

PNG was explicitly designed for still images, and its designers intentionally left animation out
of the specification. But the web needed a patent-free animated format, and GIF's 256-color
limitation was increasingly painful as monitors improved.

The Mozilla Foundation developed the APNG (Animated PNG) extension in 2008. Rather than
changing the core PNG specification, APNG adds three new optional chunk types: `acTL` for
animation control, `fcTL` for per-frame timing and disposal, and `fdAT` for frame image data.
A non-APNG-aware decoder simply ignores these chunks and displays the first frame as a still
image --- backward compatibility preserved.

APNG reached universal browser support by 2024. On June 24, 2025, the World Wide Web
Consortium published the third edition of the PNG specification, officially incorporating APNG
and adding HDR/wide-gamut support. After thirty years, PNG now formally supports animation.

#aside[
  The PNG specification's third edition (2025) is the first major update since the second
  edition in 2003. It adds APNG animation, ICC color profiles at version 4, and Rec. 2100
  HDR metadata. The core compression algorithm --- filters plus DEFLATE --- is unchanged, a
  tribute to how well it was designed.
]

=== Where PNG Rules

PNG is the right choice when:
- The image must be reproduced exactly (screenshots, icons, logos, text, diagrams).
- The image has transparency that needs to blend cleanly (UI elements, game sprites).
- The image has a palette of fewer than 256 colors (often smaller as indexed-color PNG than
  the equivalent JPEG).
- An archival master is needed (before a JPEG export).

PNG is _not_ the right choice for photographs destined for web delivery --- JPEG (at medium
quality), AVIF, or JPEG XL will all be smaller and equally good-enough visually.

== The Compression Pipeline: Code Examples

Let us look at the filter step in Python to make the inner workings tangible.

#gopython("Modular arithmetic for PNG filter residuals")[
  PNG filters store residuals modulo 256. This means if the prediction is 200 and the actual
  pixel is 10, the residual is $10 - 200 = -190$, stored as $-190 + 256 = 66$ (one unsigned
  byte). On decoding, we add 200 + 66 = 266, then take 266 mod 256 = 10. Correct!

  The modular wrap-around is crucial: it ensures residuals are always 0-255 regardless of how
  far the prediction misses, so no extra bits are needed to represent negative residuals.

  ```python
  def sub_filter(row: bytes) -> bytes:
      """Apply PNG Sub filter: each byte minus the byte to its left, mod 256."""
      out = bytearray(len(row))
      for i, byte in enumerate(row):
          left = row[i - 1] if i > 0 else 0
          out[i] = (byte - left) % 256
      return bytes(out)

  def sub_unfilter(row: bytes) -> bytes:
      """Undo PNG Sub filter: running sum mod 256."""
      out = bytearray(len(row))
      running = 0
      for i, byte in enumerate(row):
          running = (running + byte) % 256
          out[i] = running
      return bytes(out)

  # Quick self-test
  original = bytes([100, 103, 106, 108, 110, 109, 108])
  filtered = sub_filter(original)
  restored = sub_unfilter(filtered)
  assert restored == original, "Round-trip failed!"
  print("Sub filter residuals:", list(filtered))
  # Output: Sub filter residuals: [100, 3, 3, 2, 2, 255, 255]
  ```
]

#gopython("The Paeth filter in Python 3.14")[
  ```python
  def paeth_predictor(a: int, b: int, c: int) -> int:
      """Return whichever of a, b, c is closest to p = a + b - c."""
      p = a + b - c
      pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
      if pa <= pb and pa <= pc:
          return a
      elif pb <= pc:
          return b
      else:
          return c

  def paeth_filter(row: bytes, prev_row: bytes | None) -> bytes:
      """Apply PNG Paeth filter. prev_row is the previous scanline (or None)."""
      n = len(row)
      prior = prev_row if prev_row is not None else bytes(n)
      out = bytearray(n)
      for i in range(n):
          a = row[i - 1] if i > 0 else 0
          b = prior[i]
          c = prior[i - 1] if i > 0 else 0
          pred = paeth_predictor(a, b, c)
          out[i] = (row[i] - pred) % 256
      return bytes(out)

  # Example from the worked numeric calculation above
  row   = bytes([100, 103, 106, 108, 110, 109, 108])
  above = bytes([ 98,  99, 101, 104, 107, 108, 110])
  print("Paeth residuals:", list(paeth_filter(row, above)))
  ```
]

== QOI: The Format That Fits on One Page

=== The Weekend Project That Went Viral

On November 24, 2021, Dominic Szablewski --- a game developer known for the IMPACT JavaScript
game engine --- published a blog post titled "QOI --- The Quite OK Image Format." He had built a
new lossless image format over a long weekend, implemented encoder and decoder in about 300
lines of C, and posted benchmarks showing it encoded images 20 to 50 times faster than libpng
while achieving similar compression ratios.

The post went viral in the software community. Within days, independent implementations
appeared in dozens of languages. The full specification --- every decision documented --- was
published on December 20, 2021, as a single-page PDF. Szablewski donated it to the public
domain under CC0. By 2024, QOI had been adopted by FFmpeg (v5.1+), GIMP (v3.0+),
ImageMagick (v7.1.0-20+), IrfanView, and numerous game engines and texture pipelines.

What made it so appealing? The answer is that Szablewski made a very specific trade-off: he
optimized for *speed and simplicity* rather than for maximum compression ratio. QOI is not the
smallest format --- it is larger than PNG for most images. But for pipelines where images are
loaded, processed, and saved repeatedly (game assets, video textures, real-time compositing),
encode/decode speed matters far more than the last few kilobytes of compression ratio.

=== The QOI Specification: Six Chunk Types

QOI is a stream of chunks. Each chunk encodes one or more pixels. The decoder maintains two
pieces of state: a "previously seen pixel" array of 64 entries (indexed by a hash of RGBA) and
the most recently emitted pixel. It starts with pixel $(r=0, g=0, b=0, a=255)$.

The chunk types are determined by the leading bits of the first byte:

#fig([QOI chunk dispatch table. Each chunk type handles a different common pixel pattern.
The first 2-8 bits of the tag byte identify the type.],
cetz.canvas({
  import cetz.draw: *
  let rows = (
    ("QOI_OP_RGB",   "0xFE",     "Full pixel: next 3 bytes are R,G,B. Alpha unchanged. (4 bytes)"),
    ("QOI_OP_RGBA",  "0xFF",     "Full pixel: next 4 bytes are R,G,B,A. (5 bytes)"),
    ("QOI_OP_INDEX", "00xxxxxx", "Index into 64-pixel cache. (1 byte)"),
    ("QOI_OP_DIFF",  "01xxxxxx", "Tiny delta dr,dg,db in -2..+1 each. (1 byte)"),
    ("QOI_OP_LUMA",  "10xxxxxx", "Medium luminance delta. (2 bytes)"),
    ("QOI_OP_RUN",   "11xxxxxx", "Run of 1-62 identical pixels. (1 byte)"),
  )
  // Header
  rect((0, 6.2), (13.0, 7.0), fill: rgb("#c8d8f0"), stroke: 0.8pt)
  content((1.5, 6.6))[#text(size:7pt, weight:"bold")[Chunk Type]]
  content((4.0, 6.6))[#text(size:7pt, weight:"bold")[Tag]]
  content((8.5, 6.6))[#text(size:7pt, weight:"bold")[Meaning]]
  for i in range(6) {
    let (name, tag, desc) = rows.at(i)
    let y0 = 5.3 - i * 0.9
    let y1 = y0 + 0.8
    let ymid = y0 + 0.4
    rect((0, y0), (13.0, y1),
         fill: if calc.rem(i, 2) == 0 { rgb("#edf2fb") } else { rgb("#e2eafc") },
         stroke: 0.5pt)
    content((1.5, ymid))[#text(size:6.5pt, weight:"bold")[#name]]
    content((4.0, ymid))[#text(size:6.5pt)[#tag]]
    content((8.5, ymid))[#text(size:6.5pt)[#desc]]
  }
}))

*QOI\_OP\_RGB* (`0xFE`): One full pixel follows as three bytes of R, G, B. Alpha is taken from
the previous pixel's alpha.

*QOI\_OP\_RGBA* (`0xFF`): One full pixel as four bytes R, G, B, A.

*QOI\_OP\_INDEX* (tag `0b00xxxxxx`): The 6-bit field indexes into the 64-entry recently-seen-
pixels array. If the current pixel matches `seen[hash(pixel)]`, emit a 1-byte index chunk
instead of storing the color at all. The hash is
$(r times 3 + g times 5 + b times 7 + a times 11) mod 64$.

#mathrecall[
  A *hash function* (Chapter 14) scrambles a key --- here the four bytes of an RGBA pixel ---
  into an index in a fixed range, so a 64-bucket array can be looked up in one step instead of
  searched. QOI's hash mixes the channels with small primes and takes the result $mod 64$ to
  land in $[0, 63]$. Two different pixels can collide into the same slot; QOI does not chain
  them, it simply lets the newer pixel overwrite the slot, which keeps the cache a single byte
  per lookup with no bookkeeping.
]

*QOI\_OP\_DIFF* (tag `0b01xxxxxx`): The pixel differs from the previous pixel by a small amount
in each channel. The delta is encoded as $d r+2$, $d g+2$, $d b+2$ in 2 bits each (fits deltas
$-2$ to $+1$). Alpha must be unchanged.

*QOI\_OP\_LUMA* (tag `0b10xxxxxx`): A medium-sized difference, encoded in two bytes. The first
byte carries $d g+32$ in 6 bits (delta green, range $-32$ to $+31$). The second byte carries
$(d r - d g)+8$ in 4 bits and $(d b - d g)+8$ in 4 bits. This channel-difference encoding is
similar to the YCbCr idea (Chapter 42): the green channel correlates strongly with luminance, so
expressing red and blue deltas relative to green gives smaller values.

*QOI\_OP\_RUN* (tag `0b11xxxxxx`): The current pixel is identical to the previous pixel, and
the run length (1 to 62) is encoded in 6 bits. Run lengths 63 and 64 are reserved for the RGB
and RGBA tags.

#keyidea[
  QOI's six chunk types map to six common pixel patterns: identical to previous (RUN), seen
  recently (INDEX), tiny change (DIFF), moderate change (LUMA), or completely new (RGB/RGBA).
  A real image is almost entirely runs, cache hits, and small diffs, so most pixels cost 1-2
  bytes rather than 3-4. The key insight is that you do not need a complex model to exploit
  locality --- just these six cases cover nearly all realistic patterns.
]

=== The QOI 64-Entry Pixel Cache

The INDEX chunk is QOI's most distinctive feature. The decoder maintains an array of 64 RGBA
values, initially all zeros. Every time a new pixel is decoded (by any chunk type), it is
stored in `seen[hash(pixel)]`, overwriting whatever was there. This acts as a tiny, fast cache
of recently-used colors.

If the current pixel happens to equal `seen[hash(pixel)]` --- because that exact color was seen
recently and still occupies its slot --- the entire pixel is stored as a single byte. For images
with a small active palette (logos, pixel art, screenshots), this hits very frequently. Even for
photographs, sky tones, skin tones, and ground often repeat enough colors that the cache saves
substantial space.

The hash function $(r times 3 + g times 5 + b times 7 + a times 11) mod 64$ is deliberately
simple: no division, just multiplications by small primes plus a modulo. An element-wise
equality check plus a modulo costs a few nanoseconds on modern hardware.

=== QOI File Structure

A QOI file begins with a 14-byte header:

- Magic: 4 bytes `"qoif"` (ASCII)
- Width: 4 bytes big-endian unsigned integer
- Height: 4 bytes big-endian unsigned integer
- Channels: 1 byte (3 = RGB, 4 = RGBA)
- Colorspace: 1 byte (0 = sRGB with linear alpha, 1 = all channels linear)

#pyrecall[
  *Big-endian* (Chapter 13) means the most-significant byte is written first: the width
  $1000 = $ `0x000003E8` is stored as the four bytes `00 00 03 E8`, not reversed. In Python you
  would write it with `(1000).to_bytes(4, "big")` and read it back with
  `int.from_bytes(data, "big")`, exactly the convention from Chapter 17's container.
]

After the header, the chunk stream follows. The file ends with the 8-byte end marker
`0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x01`.

The colorspace field is informational only --- QOI does not perform color conversion. It simply
records what color model the values are in so that downstream software knows how to interpret
them.

#algo(
  name: "QOI Encode",
  year: "2021",
  authors: "Dominic Szablewski (phoboslab.org)",
  aim: "Losslessly compress RGBA image pixels at very high throughput with trivial implementation",
  complexity: "$O(n)$ strictly linear; constant memory (64-pixel cache plus 1 previous pixel)",
  strengths: "20-50x faster encoding than libpng; 3-4x faster decoding; single-pass; spec fits on one page; public domain CC0",
  weaknesses: "Larger files than PNG by roughly 20-40% on typical photographs; no interlacing or progressive display; no metadata chunks; RGB/RGBA only (no 16-bit or grayscale)",
  superseded: "Not yet superseded; serves a different niche than PNG (speed vs ratio)",
)[
  For each pixel in raster order: (1) check if it equals the previous pixel --- if so, extend
  RUN counter (flush RUN chunk when run ends or reaches 62). (2) Check `seen[hash(pixel)]` ---
  emit INDEX chunk if match. (3) Compute delta from previous pixel; if all channels fit in
  $[-2,+1]$ and alpha unchanged --- emit DIFF chunk. (4) If green delta fits in $[-32,+31]$
  and $d r - d g$ and $d b - d g$ both fit in $[-8,+7]$ and alpha unchanged --- emit LUMA
  chunk. (5) Otherwise, emit RGB or RGBA chunk. After each pixel, store it in
  `seen[hash(pixel)]`.
]

=== A Worked QOI Encoding

Suppose we encode a 4-pixel sequence (RGBA):

```
P0: (100, 150, 200, 255)
P1: (100, 150, 200, 255)   -- identical to P0
P2: (100, 150, 200, 255)   -- identical
P3: (102, 153, 202, 255)   -- small diff
```

The encoder starts with `prev = (0, 0, 0, 255)` and an empty cache.

- *P0*: Not a run (prev is zero-black). Not in cache (all zeros). Delta from prev is huge.
  Emit `QOI_OP_RGB`: 1 tag byte + 3 color bytes = 4 bytes. Store P0 in `seen[hash(P0)]`.
  Update `prev = P0`.

- *P1*: Equals `prev` (P0). This is a run. Start run counter at 1. Do not emit yet.

- *P2*: Equals `prev` again. Extend run counter to 2.

- *P3*: Breaks the run. First, flush the run: emit `QOI_OP_RUN` with run length 2 = 1 byte.
  Now encode P3 relative to P2: $d r = 2, d g = 3, d b = 2, d a = 0$. DIFF requires
  $d r, d g, d b in [-2, +1]$: $d g = 3$ exceeds the range. Try LUMA: $d g = 3 in [-32,+31]$,
  $d r - d g = -1 in [-8,+7]$, $d b - d g = -1 in [-8,+7]$. LUMA works! Emit 2 bytes.

Total: 4 + 1 + 2 = 7 bytes for 4 RGBA pixels that would otherwise cost 16 bytes raw.
Compression ratio: 2.3:1, in one extremely fast linear pass.

== Comparing the Three Formats

=== Compression Performance

To make the comparison concrete, consider what happens when these formats encode different kinds
of image content.

*Palette-limited graphics* (icons, pixel art): For a 100 x 100 icon using exactly 16 distinct
colors, all three formats encode losslessly, and GIF can achieve 4 bits per pixel just from
the palette encoding. PNG's filter step plus DEFLATE generally beats GIF's LZW anyway, because
DEFLATE is a strictly more powerful compressor. QOI's INDEX chunks fire constantly (the 64-
entry cache covers 16 colors trivially) and RUN chunks handle solid areas --- QOI is very
competitive here and dramatically faster.

*Screenshots and interface graphics*: These have large solid regions, sharp edges, and many
repeated colors. PNG typically compresses well --- ratios of 5:1 to 10:1 are common. QOI is not
far behind (4:1 to 8:1) but encodes ten times faster. GIF struggles because palette
quantization degrades anti-aliased text, and 256 colors are rarely enough for modern UI.

*Photographs as lossless*: A raw photograph in PNG might compress to about 40-60% of its
uncompressed size (2:1 to 2.5:1). The Sub or Paeth filter removes some inter-pixel correlation,
but photographic noise is genuinely random and hard to compress. QOI will produce files 20-40%
larger than PNG (so roughly 1.5:1 to 2:1). Neither is competitive with JPEG or AVIF for
photographic web delivery.

#scoreboard(caption: "Format comparison for lossless image encoding (approximate, depends heavily on image content)",
[*Format*],[*Max colors*],[*Alpha*],[*Animation*],[*Ratio (UI)*],[*Enc. speed*],[*Patents*],
[GIF 89a],[256/frame],[1-bit on/off],[Yes],[Moderate],[Fast],[Expired 2003-2004],
[PNG],[16.7M+ (24-bit)],[8-bit full],[APNG (2025)],[Excellent],[Moderate],[None],
[QOI],[16.7M (24-bit)],[8-bit full],[No],[Good],[Very fast],[None (CC0)],
)

#scoreboard(caption: "QOI vs PNG encode/decode throughput benchmark (single-threaded, Linux x86-64, 2022 data, approximate)",
[*Format*],[*Encode speed*],[*Decode speed*],[*File size vs PNG*],[*Notes*],
[PNG (libpng, level 6)],[~15 MB/s],[~100 MB/s],[1.00x],[Default zlib level 6],
[PNG (stb\_image\_write)],[~200 MB/s],[~200 MB/s],[1.15x],[Faster but slightly worse ratio],
[QOI],[~300-400 MB/s],[~400-700 MB/s],[1.20-1.40x],[Larger files; much faster],
)

=== Decision Guide

*Use GIF when:*
- You need a looping animation that works everywhere, including very old email clients and
  ancient systems.
- The art style is genuinely palette-limited (pixel art, cartoons).
- In any new design, prefer APNG over animated GIF --- APNG offers full 24-bit color with alpha,
  better compression, and is now part of the official PNG standard.

*Use PNG when:*
- The image needs exact pixel reproduction.
- The image has transparency that needs to blend smoothly (UI elements, logos with soft edges).
- The image has text, sharp lines, or geometric shapes that look terrible with lossy artifacts.
- You need broad compatibility (PNG is universally supported, including email and documents).

*Use QOI when:*
- You control both the encoder and decoder (internal formats, game asset pipelines).
- Encode/decode speed is a bottleneck (texture streaming, real-time compositing, large datasets
  loaded repeatedly).
- The modest file size increase is acceptable, and you do not need metadata, HDR, or sub-byte
  palette encoding.

#misconception[
  "GIF supports more colors than PNG."
][
  The opposite is true. GIF supports at most 256 colors per frame, and only fully-on/fully-off
  transparency. PNG supports up to 16.7 million colors (24-bit RGB) or 281 trillion colors
  (48-bit RGB), plus full 8-bit or 16-bit alpha. The confusion may arise because GIF animation
  was ubiquitous while early PNG support was sometimes limited or buggy --- but in terms of
  color capability, PNG is strictly more expressive in every dimension.
]

== The Broader Lesson: Patents, Freedom, and Format Survival

GIF's story is a cautionary tale that compression engineers still tell. A technically solid
format, widely deployed, suddenly found itself behind a toll booth. The community's response
was swift and ultimately succeeded --- but it took years, and in the meantime the landscape
fragmented. PNG was built by volunteers working against a deadline imposed not by technical need
but by legal threat.

The patent story did not end with GIF. As we will see in Chapter 53, the same drama played out
again with HEVC (H.265) --- a technically superior codec hobbled by a fractured patent pool
that handed market share to the royalty-free AV1 (Chapter 54). And JPEG 2000 itself, which we
met in Chapter 43, is a case where patent _uncertainty_ (not even actual licensing demands) was
enough to drive developers to alternatives.

QOI's success story offers a different lesson: a format does not need to be the most technically
sophisticated to win in its niche. Clear goals, clean design, zero intellectual property
encumbrances, and a readable specification built QOI's adoption faster than most standards-body
formats achieve in a decade.

#keyidea[
  Format success is determined by at least three equally important factors: (1) technical
  quality for the target use case, (2) licensing and patent freedom, and (3) ecosystem momentum
  (browser support, library availability, toolchain integration). A format that fails on any one
  of these three will struggle, no matter how clever the compression algorithm.
]

#takeaways((
  [GIF87a (1987) introduced the palettized, LZW-compressed image format; GIF89a (1989) added
   animation, transparency, and extensions. The LZW patent firestorm of December 1994 directly
   caused PNG to be created.],
  [PNG uses a two-stage pipeline: per-row prediction filters (None, Sub, Up, Average, Paeth)
   reduce redundancy, then DEFLATE entropy-codes the residuals. It supports full 24-bit color
   with 8-bit alpha, making it strictly more capable than GIF in every color dimension.],
  [PNG stores data in self-describing, CRC-protected chunks (IHDR, IDAT, IEND, PLTE, and
   ancillary chunks). The 2025 third-edition standard formally adds APNG animation and HDR.],
  [QOI (November 2021, Dominic Szablewski) achieves 20-50x faster encoding than PNG using six
   simple chunk types: RGB/RGBA (full pixel), INDEX (64-entry cache hit), DIFF (tiny delta),
   LUMA (medium luminance delta), and RUN (repeated pixel). Files are 20-40% larger than PNG.],
  [The right format depends on use case: GIF for legacy palette animations; PNG for universal
   lossless images with transparency and metadata; QOI for high-throughput pipelines where
   encode/decode speed is the bottleneck.],
  [Patents can derail technically superior formats (GIF, JPEG 2000, HEVC); royalty-free designs
   (PNG, AV1, QOI) consistently win on the open web over time.],
))

== Exercises

#exercise("44.1", 1)[
  A GIF file uses a 16-color palette. How many bits per pixel does each palette index require?
  How does this compare to a PNG storing the same image in indexed-color mode? What further
  compression would each format apply after this initial representation?
]

#solution("44.1")[
  16 colors require $log_2(16) = 4$ bits per pixel as palette indices. GIF would apply LZW
  compression to those 4-bit indices. PNG would store the same 4-bit (or byte-aligned) indices
  and apply per-row filters (likely Sub or Up) followed by DEFLATE. PNG's pipeline generally
  achieves better compression than GIF's LZW for the same indexed-color content because (1)
  DEFLATE is more powerful than LZW and (2) the filter pre-processing reduces redundancy before
  the entropy coder runs.
]

#exercise("44.2", 1)[
  Explain the Paeth predictor in your own words. Given $a = 80$, $b = 100$, $c = 78$, and an
  actual pixel value $x = 104$, compute the Paeth prediction and the filter residual that would
  be stored in the PNG file.
]

#solution("44.2")[
  $p = a + b - c = 80 + 100 - 78 = 102$.
  Distances: $|p - a| = |102 - 80| = 22$, $|p - b| = |102 - 100| = 2$,
  $|p - c| = |102 - 78| = 24$.
  The minimum is 2 (for $b$), so the prediction is $b = 100$.
  Residual: $(104 - 100) mod 256 = 4$.
  This byte (4) is stored in the PNG file.
]

#exercise("44.3", 2)[
  A QOI encoder processes a pixel P = (50, 100, 150, 255) after a previous pixel of
  Q = (48, 98, 150, 255). Show which QOI chunk type is selected and how it is encoded.
  Assume the 64-entry cache does not contain P.
]

#solution("44.3")[
  Delta: $d r = 50 - 48 = 2$, $d g = 100 - 98 = 2$, $d b = 150 - 150 = 0$, $d a = 0$.
  Alpha is unchanged. DIFF requires $d r, d g, d b in [-2, +1]$: $d r = 2$ exceeds this range.
  Try LUMA: $d g = 2 in [-32, +31]$. $d r - d g = 2 - 2 = 0 in [-8, +7]$.
  $d b - d g = 0 - 2 = -2 in [-8, +7]$. LUMA qualifies.
  Encoded as two bytes.
  Byte 1: the top 2 bits are the LUMA tag `10`; the low 6 bits carry $d g + 32 = 34 = $`100010`
  in binary, giving `0xA2`.
  Byte 2: the high 4 bits carry $d r - d g + 8 = 0 + 8 = 8 = $`1000` in binary; the low 4
  bits carry $d b - d g + 8 = -2 + 8 = 6 = $`0110` in binary, giving `0x86`.
  The chunk is 2 bytes vs. 4 bytes for a raw RGBA pixel.
]

#exercise("44.4", 2)[
  Implement a function `png_up_filter(rows: list[bytes]) -> list[bytes]` in Python 3.14 that
  applies the PNG Up filter to each row, given the previous row (treating the first row as if
  the previous row is all zeros). Verify it round-trips with the inverse.
]

#solution("44.4")[
  ```python
  def png_up_filter(rows: list[bytes]) -> list[bytes]:
      """Apply PNG Up filter to each row. Returns list of filtered rows."""
      result: list[bytes] = []
      prev = bytes(len(rows[0]))
      for row in rows:
          filtered = bytes((b - p) % 256 for b, p in zip(row, prev))
          result.append(filtered)
          prev = row  # next row's "above" is this raw row
      return result

  def png_up_unfilter(filtered_rows: list[bytes]) -> list[bytes]:
      """Undo PNG Up filter."""
      result: list[bytes] = []
      prev = bytes(len(filtered_rows[0]))
      for row in filtered_rows:
          restored = bytes((f + p) % 256 for f, p in zip(row, prev))
          result.append(restored)
          prev = restored  # next row's "above" is the restored row
      return result

  # Self-test
  original = [bytes([100, 103, 106]), bytes([98, 100, 107]), bytes([95, 99, 108])]
  filtered = png_up_filter(original)
  restored = png_up_unfilter(filtered)
  assert restored == original
  print("Filtered:", [list(r) for r in filtered])
  ```
]

#exercise("44.5", 2)[
  A QOI encoder compresses a 1000x1000 RGBA image (4 MB raw). The image is a solid blue sky
  with a few white clouds. Estimate, roughly, how many bytes the result might be and which
  chunk types will dominate. Explain your reasoning.
]

#solution("44.5")[
  A large solid region: most pixels equal the previous pixel. RUN chunks fire constantly, each
  encoding up to 62 pixels in 1 byte. 1,000,000 pixels divided by 62 is roughly 16,130 RUN
  chunks, approximately 16 KB for the blue regions. Cloud pixels have small deltas relative to
  the sky color --- changing slightly at cloud edges --- producing DIFF or LUMA chunks (1-2 bytes
  each). Perhaps 10% of pixels are cloud-edge pixels: 100,000 pixels times 2 bytes = 200 KB.
  Total rough estimate: 50-300 KB, representing 10:1 to 80:1 compression. RUN chunks dominate.
  This type of image is where QOI excels most dramatically.
]

#exercise("44.6", 3)[
  The PNG Paeth filter references three neighboring pixels: left (a), above (b), and upper-left
  (c). For the very first row of an image (no row above), the PNG specification says to treat
  all "above" and "upper-left" values as zero. For the very first pixel in any row, the "left"
  pixel is also treated as zero. Implement a complete PNG Paeth filter and inverse for a single
  row in Python, handling these boundary conditions. Then trace through the encoding and
  decoding of the row `[200, 195, 198, 202, 197]` when the previous row is
  `[190, 188, 192, 199, 195]`.
]

#solution("44.6")[
  ```python
  def paeth_predictor(a: int, b: int, c: int) -> int:
      p = a + b - c
      pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
      return a if pa <= pb and pa <= pc else (b if pb <= pc else c)

  def paeth_row_filter(row: bytes, prev: bytes) -> bytes:
      out = bytearray(len(row))
      for i in range(len(row)):
          a = row[i-1] if i > 0 else 0
          b = prev[i]
          c = prev[i-1] if i > 0 else 0
          out[i] = (row[i] - paeth_predictor(a, b, c)) % 256
      return bytes(out)

  def paeth_row_unfilter(filt: bytes, prev: bytes) -> bytes:
      out = bytearray(len(filt))
      for i in range(len(filt)):
          a = out[i-1] if i > 0 else 0
          b = prev[i]
          c = prev[i-1] if i > 0 else 0
          out[i] = (filt[i] + paeth_predictor(a, b, c)) % 256
      return bytes(out)
  ```
  Trace for row = [200,195,198,202,197], prev = [190,188,192,199,195]:
  i=0: a=0, b=190, c=0 -> p=190, pa=190, pb=0 -> pred=b=190. res=(200-190)%256=10.
  i=1: a=200, b=188, c=190 -> p=198, pa=2, pb=10, pc=8 -> pred=a=200. res=(195-200)%256=251.
  i=2: a=195, b=192, c=188 -> p=199, pa=4, pb=7, pc=11 -> pred=a=195. res=(198-195)%256=3.
  i=3: a=198, b=199, c=192 -> p=205, pa=7, pb=6, pc=13 -> pred=b=199. res=(202-199)%256=3.
  i=4: a=202, b=195, c=199 -> p=198, pa=4, pb=3, pc=1 -> pred=c=199. res=(197-199)%256=254.
  Filtered row: [10, 251, 3, 3, 254]. Most values are small. Decoding applies the inverse
  (paeth\_row\_unfilter) and recovers the original row exactly.
]

== Further Reading

#link("https://www.w3.org/TR/png/")[PNG Specification, Third Edition (W3C, June 2025)] --- The
authoritative PNG standard, now including APNG and HDR support.

#link("https://www.w3.org/Graphics/GIF/spec-gif89a.txt")[GIF89a Specification (CompuServe, 1990)] ---
The original specification document; a surprisingly concise read.

#link("https://qoiformat.org/qoi-specification.pdf")[QOI Specification v1.0 (Dominic Szablewski, 2021)] ---
A single-page PDF; worth reading in its entirety as a model of clear specification writing.

#link("https://phoboslab.org/log/2021/11/qoi-fast-lossless-image-compression")[QOI --- The Quite OK Image Format (Szablewski, 2021)] ---
The original blog post with benchmarks, the weekend-project story, and the code repository link.

#link("http://www.libpng.org/pub/png/pnghist.html")[History of the PNG Format (libpng.org)] ---
The inside story of how PNG was designed, written by those who built it.

#link("https://www.cast-inc.com/blog/lossless-compression-efficiency-jpeg-ls-png-qoi-and-jpeg2000-comparative-study")[Comparative Study: JPEG-LS, PNG, QOI, and JPEG 2000 (CAST, 2023)] ---
A rigorous benchmark comparison across lossless image codecs with detailed numerical analysis.

#bridge[
  We have now covered the palette and lossless end of the image format spectrum. In Chapter 45
  we turn to the modern image format wars: WebP, HEIC, AVIF, and JPEG XL --- the wave of formats
  that arrived after 2010, each claiming to be JPEG's true successor. You will see the same
  forces we met here --- patents, ecosystem inertia, browser politics --- play out again at higher
  quality levels and on a web large enough to make the stakes enormous. And you will see how one
  format, JPEG XL, was removed from Chrome in 2023 and then restored in February 2026 after a
  memory-safe Rust decoder resolved the safety objections.
]
