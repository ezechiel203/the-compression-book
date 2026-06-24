#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= JPEG 2000 and the Wavelet Promise

#epigraph[The best is the enemy of the good.][Voltaire, _Dictionnaire philosophique_, 1770]

Imagine you are designing the image codec that will replace JPEG. You have a decade of research behind you, a bigger wavelet theory instead of block DCT, a richer bitstream that delivers any quality or resolution from the same file, a lossless option that is genuinely lossless, and a compression ratio that measurably beats JPEG at the same visual quality. You publish the standard in the year 2000, you name it JPEG 2000, and then almost nothing happens on the web. Browsers ignore it for years. JPEG shuffles along unthreatened. Yet simultaneously, every commercial cinema projector on Earth encodes its footage in your format, every hospital stores its MRI scans and CT slices in your format, and the archivists at national libraries depend on your format to preserve priceless cultural heritage.

How does the technically superior codec become the quiet champion of professional niches while losing the consumer market almost entirely? That story is Chapter 43. By the end, you will understand the wavelet machinery at JPEG 2000's core, the cleverness of its embedded bit-plane coder, and why "better" is never enough on its own.

#recap[
In Chapter 38 we built the mathematics of wavelets from scratch: filter banks, multi-resolution analysis, and the DWT. In Chapter 39 we met quantization (the lossy step where precision is traded for bits). In Chapter 42 we just finished dissecting JPEG itself: 8×8 block DCT, quantization tables, zig-zag scan, run-length coding, Huffman entropy. JPEG 2000 keeps quantization and entropy coding but replaces everything else: the block DCT becomes a full-image DWT, and the entropy coder becomes the MQ arithmetic coder feeding an embedded bit-plane engine called EBCOT. All the moving parts in this chapter connect directly to what you already know.
]

#objectives((
  [Explain why the Discrete Wavelet Transform avoids blocking artifacts that plague JPEG.],
  [Describe the EBCOT algorithm: code-blocks, bit-plane passes, and truncation.],
  [Explain the role of the MQ arithmetic coder and how it differs from JPEG's Huffman tables.],
  [Define scalability (resolution scalability and quality/SNR scalability) and give a concrete example of each.],
  [Name the three domains where JPEG 2000 genuinely dominates and explain why.],
  [Describe HTJ2K (Part 15) and explain the throughput–efficiency trade-off it makes.],
))

== Why JPEG's Blocks Break Down

Before getting into JPEG 2000, it is worth spending a moment on the exact problem it was designed to solve. JPEG breaks an image into a grid of independent 8×8 pixel blocks, transforms each block separately with the DCT, quantizes the resulting coefficients, and encodes them. That independence is both JPEG's strength (the blocks are easy to compute in parallel) and its weakness.

When you push a JPEG file to a very low bitrate (saving aggressively to squeeze a photograph into a small file), the quantization step rounds almost all the high-frequency DCT coefficients to zero. That is fine _within_ a block: the block's internal detail is blurred. The problem is what happens _between_ blocks. Two adjacent blocks are quantized independently, so their reconstructed edges no longer match. You see a grid of rectangular tiles: the blocking artifact. You also see _ringing_: because a sharp edge in the image requires high-frequency cosine terms that have been discarded, the reconstruction oscillates near the edge in a pattern called Gibbs overshoot.

#keyidea[
JPEG's artifacts come from independent block processing. JPEG 2000 eliminates blocking by applying its transform to the _whole image_ at once. Ringing is not eliminated (it is fundamental to any lossy transform-coder), but it spreads smoothly rather than landing on tile boundaries.
]

== The Wavelet Transform at the Heart of JPEG 2000

#mathrecall[Chapter 38 defined the DWT as an iterated filter bank: each level splits the signal into a low-frequency approximation (L) and a high-frequency detail (H), then subsamples both. The 2-D case applies this separately to rows and then columns, yielding four subbands: LL (low-low, the thumbnail), LH (horizontal detail), HL (vertical detail), HH (diagonal detail). The LL subband is then split again, and so on for several levels.]

JPEG 2000 uses a specific family of wavelets. For the _lossy_ path it uses the *CDF 9/7 filter* (Cohen–Daubechies–Feauveau, 1992), named after Albert Cohen, Ingrid Daubechies, and J.-C. Feauveau. For the _lossless_ path it uses the simpler integer *CDF 5/3 filter* (also called the LeGall 5/3), which operates entirely in whole numbers so there is no rounding error. The standard applies the DWT to the _entire image_ (after an optional colour transform), producing a pyramid of subbands.

=== The DWT Pyramid

Let us make this concrete. Suppose you start with a 512×512 greyscale image. After one level of the 2-D DWT you have four 256×256 subbands. After a second level you split the LL subband again, giving you seven 128×128 and 256×256 subbands. JPEG 2000 typically uses five levels of decomposition, resulting in a triangular pyramid that looks roughly like this:

#fig([Wavelet pyramid for a 512×512 image (5 levels). The LL5 thumbnail in the top-left is the coarsest approximation; the detail subbands fill the rest.],
cetz.canvas({
  import cetz.draw: *

  // Draw the full outer box
  rect((0,0),(8,8), fill: rgb("#e8f4f8"), stroke: 1pt + rgb("#0b5394"))

  // Level 5 (top left corner, smallest)
  rect((0,6),(2,8), fill: rgb("#0b5394").lighten(40%), stroke: 0.7pt + rgb("#0b5394"))
  content((1,7), box(width: 1.6cm, inset: 1pt, align(center, text(size:7pt)[LL5])))

  rect((2,6),(4,8), fill: rgb("#1f5066").lighten(60%), stroke: 0.7pt)
  content((3,7), box(width: 1.6cm, inset: 1pt, align(center, text(size:7pt)[LH5])))

  rect((0,4),(2,6), fill: rgb("#1f5066").lighten(60%), stroke: 0.7pt)
  content((1,5), box(width: 1.6cm, inset: 1pt, align(center, text(size:7pt)[HL5])))

  rect((2,4),(4,6), fill: rgb("#1f5066").lighten(70%), stroke: 0.7pt)
  content((3,5), box(width: 1.6cm, inset: 1pt, align(center, text(size:7pt)[HH5])))

  // Level 4
  rect((4,4),(8,8), fill: rgb("#1f5066").lighten(70%), stroke: 0.7pt)
  content((6,6), box(width: 3.6cm, inset: 2pt, align(center, text(size:7pt)[Level 4 subbands])))

  // Level 3
  rect((0,0),(4,4), fill: rgb("#1f5066").lighten(75%), stroke: 0.7pt)
  content((2,2), box(width: 3.6cm, inset: 2pt, align(center, text(size:7pt)[Level 3 subbands])))

  // Level 2/1 (right half lower)
  rect((4,0),(8,4), fill: rgb("#1f5066").lighten(80%), stroke: 0.7pt)
  content((6,2), box(width: 3.6cm, inset: 2pt, align(center, text(size:7pt)[Levels 1--2 subbands])))

  // Label
  content((4,-0.5), box(width: 4cm, inset: 1pt, align(center, text(size:8pt, fill: rgb("#0b5394"))[512 pixels wide])))
  line((0,-0.3),(8,-0.3), stroke: 0.5pt + rgb("#0b5394"), mark: (end: ">", start: "<"))
}))

The key point: the high-frequency subbands (LH, HL, HH) capture edges and textures. Because these subbands cover the _whole image_, a vertical edge spreads its energy coherently across the HL subband at multiple levels. When you aggressively quantize those coefficients, the artifact blurs smoothly across the neighbourhood of the edge. It never snaps to an 8×8 grid boundary, because there is no grid.

#aside[
The CDF 9/7 filter has 9 taps in the analysis lowpass and 7 taps in the synthesis (reconstruction) filter. The CDF 5/3 has 5 and 3 respectively. Why two different filters? The 9/7 gives better compression (more energy compaction) but uses floating-point arithmetic, which does not round-trip exactly. For lossless compression you _need_ exact round-trip behaviour, so JPEG 2000 switches to the integer 5/3 filter for its lossless mode.

How does the 5/3 filter manage to be _exactly_ reversible using only whole numbers? The trick is the *lifting scheme*: instead of computing the wavelet as a single sum of products (which would need fractions), you build it from a short sequence of simple steps, each of which adds to one sample a rounded combination of its neighbours. For the 5/3 filter the two steps are, in essence, "predict each odd-indexed sample from the average of its two even neighbours, then update each even sample using the corrected odd ones," with every intermediate result rounded to an integer. Because each step is _individually_ invertible (you simply subtract back exactly what you added), the whole transform inverts perfectly, integer in and integer out, with no rounding error to accumulate. Lifting also happens to be faster and to need less memory; modern wavelet codecs use it even for the floating-point 9/7 filter.
]

=== Colour Transformation

Like JPEG, JPEG 2000 works in a colour space other than RGB. For lossy compression it uses the *ICT* (Irreversible Colour Transform), a floating-point version of the YCbCr transform that decorrelates the three colour channels. For lossless compression it uses the *RCT* (Reversible Colour Transform), an integer approximation that is exactly invertible. Either way, colour correlation across channels is removed before the DWT, which improves the overall compression.

== Tiling

JPEG 2000 does support optional _tiles_ (rectangular regions processed independently), but these tiles are typically much larger than JPEG's 8×8 blocks: common sizes are 256×256, 1024×1024, or one tile for the whole image. For typical still-image compression the standard is one tile. Tiling is used primarily for very large images (satellite data, gigapixel scans) where you need random access to different spatial regions.

This is an important nuance: JPEG 2000 is not "just like JPEG with bigger blocks." When you use one tile (the most common case), the DWT spans the entire image, and there are no tile-boundary artifacts at all.

== Quantization in JPEG 2000

After the DWT, each subband's coefficients are quantized. JPEG 2000's quantization is straightforward: each coefficient $c$ in a subband is divided by a step size $Delta$ and the result is rounded toward zero:

$ q = floor(abs(c) / Delta) times "sign"(c) $

where $floor(dot)$ means "round down to the nearest whole number" (the floor function you may recall from Chapter 7). The step size $Delta$ can differ across subbands, allowing fine control of where distortion appears. A large step size discards fine detail; a small step size preserves it.

#gomaths("The floor function and integer quantization")[
The _floor_ of a real number $x$, written $floor(x)$, is the largest integer less than or equal to $x$. Examples: $floor(3.7) = 3$, $floor(-1.2) = -2$.

Integer quantization of a real value $c$ with step size $Delta > 0$ is: $q = floor(abs(c) / Delta)$, keeping the sign separately. To _reconstruct_ from $q$, you use $hat(c) = (q + 0.5) times Delta times "sign"(q)$ (the midpoint of the quantization interval), which minimises the average reconstruction error.

Concrete example: $c = 13.4$, $Delta = 5$. Then $q = floor(13.4 / 5) = floor(2.68) = 2$. Reconstruction: $hat(c) = (2 + 0.5) times 5 = 12.5$. Error: $abs(13.4 - 12.5) = 0.9 < Delta/2$, exactly the maximum rounding error.
]

== EBCOT: Embedded Block Coding with Optimised Truncation

The quantized coefficients in each subband now need to be entropy-coded. This is where JPEG 2000 does something genuinely clever, going well beyond JPEG's zig-zag + run-length + Huffman. The algorithm is called *EBCOT* (Embedded Block Coding with Optimised Truncation), proposed by David Taubman in his 2000 paper "High performance scalable image compression with EBCOT." It is what makes JPEG 2000 progressively decodable at _any_ quality.

=== Code-Blocks

EBCOT first divides each DWT subband into small rectangular _code-blocks_, typically 64×64 or 32×32 samples. Each code-block is compressed independently. (Do not confuse these with JPEG's 8×8 pixel blocks! JPEG 2000's code-blocks live in the _wavelet domain_, after the DWT, and cover a much larger spatial region of the original image.)

=== Bit-Plane Coding

For each code-block, EBCOT codes the quantized coefficients _one bit-plane at a time_, from the most significant bit down to the least significant bit. Think of each quantized coefficient as a binary number. The most significant bit (MSB) of all coefficients in the block is coded together; then the next bit of all coefficients; and so on.

Within each bit-plane, EBCOT makes three _passes_ in a fixed scan order across the code-block:

+ *Significance propagation pass.* A coefficient is called _significant_ once its MSB has been seen (i.e., it is non-zero in the bit-planes coded so far). In this pass, only coefficients that are _not yet significant_ but have at least one significant neighbour are coded, because context from neighbours makes their bits more predictable.

+ *Magnitude refinement pass.* Coefficients that _are already_ significant get their next bit coded. These bits carry precise magnitude information and are relatively independent of context.

+ *Cleanup pass.* All remaining coefficients that were neither coded in the significance-propagation pass nor in the magnitude-refinement pass are coded here, sweeping up everything that was skipped.

Each pass produces a small chunk of compressed data (a "compressed bit-plane segment"). These segments are the _granularity_ of JPEG 2000's quality scalability: by including more or fewer segments in the final bitstream, the decoder gets a coarser or finer rendering of each code-block.

#keyidea[
Bit-plane coding means the coder always works from the most important bits toward the least important bits. At any point you can stop and you have the best possible image for the bits spent so far. That property is called _embeddedness_: the same bitstream decodes at any quality level you choose.
]

=== The MQ Arithmetic Coder

Each bit in the three passes is fed into the *MQ coder*, a context-adaptive binary arithmetic coder. You met arithmetic coders in Chapter 26; the MQ coder is a specific finite-precision binary variant adopted by the JPEG committee. (Mitsubishi submitted it to Working Group 1 at the March 1999 meeting in Korea.) The MQ coder is also used in JBIG2 (the fax/document compression standard).

For each bit being coded, the MQ coder chooses one of 19 _contexts_, selected based on whether the surrounding coefficients are already significant, their signs, and their positions. The MQ coder then models the probability of a "1" bit in that context and arithmetic-codes accordingly. Because probabilities are adapted per context, the coder converges to close to the entropy of each context.

#algo(
  name: "EBCOT (Embedded Block Coding with Optimised Truncation)",
  year: "2000",
  authors: "David Taubman",
  aim: "Bit-plane coding of DWT coefficient blocks with adaptive truncation to meet a target bitrate, producing an embedded bitstream with SNR and resolution scalability.",
  complexity: "O(N) in image size; three passes per bit-plane per code-block.",
  strengths: "True SNR and resolution scalability from one bitstream; near-optimal rate–distortion at each truncation point; no blocking artifacts; supports lossless and lossy with the same framework.",
  weaknesses: "High implementation complexity; slow compared to JPEG (the MQ coder is sequential and branch-heavy); code-block independence limits context to small regions.",
  superseded: "HTJ2K (JPEG 2000 Part 15) replaces the MQ coder with a simpler high-throughput block coder for speed-critical applications.",
)[
Taubman's key insight was that each code-block's compressed stream can be _truncated_ at any of the pass boundaries, and that the rate–distortion trade-off of each truncation point can be computed. A global optimiser (Tier 2 of JPEG 2000) then picks the truncation points across all code-blocks that achieve the lowest total distortion for a given total bitrate. This post-hoc optimisation is what the "Optimised Truncation" in the name refers to.
]

=== A Worked Example of Bit-Plane Coding

Let us trace EBCOT on a tiny 4×1 block of already-quantized DWT coefficients:

#figure(
  table(
    columns: (4cm, auto, auto, auto, auto),
    inset: 6pt,
    align: center,
    table.header([*Position*], [*A*], [*B*], [*C*], [*D*]),
    [Quantized value], [5], [-3], [0], [7],
    [3-bit magnitude], [101], [011], [000], [111],
    [Sign (0=pos)], [0], [1], [--], [0],
  ),
  caption: [Four quantized DWT coefficients and their binary representations (magnitudes).]
)

Bit-plane 2 (the MSB): the significance propagation pass codes coefficients whose neighbours are already significant. None are, so nothing is coded here. The cleanup pass codes _all_ coefficients: the MSBs are 1, 0, 0, 1. Now A and D are _significant_; B and C are not.

Bit-plane 1: the significance propagation pass sees that B (neighbour of A, which is significant) and C (neighbour of D) are not yet significant, so their bit-plane-1 bits are coded here: B=1, C=0. B is now significant. The magnitude-refinement pass codes the bit-plane-1 bits of A (0) and D (1) since they were already significant.

Bit-plane 0: all four are now significant, so the magnitude-refinement pass codes their LSBs: A=1, B=1, C=0, D=1.

After all three bit-planes, the decoder has perfect reconstructions: A=5, B=3 (with sign=-1 → −3), C=0, D=7. If the bitstream were truncated after bit-plane 2, the decoder would reconstruct A≈6, B=0, C=0, D≈6: a coarser but sensible approximation.

#checkpoint[After the significance-propagation pass for bit-plane 2 in our example, how many coefficients are significant?][Two: A (value 5, MSB=1) and D (value 7, MSB=1). B (MSB=0) and C (MSB=0) are not yet significant.]

== Layers: The Scalable Bitstream

The truncated code-block segments from all the code-blocks across all subbands are then assembled into _layers_. Layer 0 contains the most important truncation points (typically one pass per code-block); Layer 1 adds the next improvement; and so on, up to however many quality layers the encoder chose to create (commonly 10–20).

This layered bitstream is a remarkable engineering achievement. A single JPEG 2000 file can:

- Decode at _full resolution, full quality_ if you read the whole file.
- Decode a low-quality _thumbnail_ by reading only the first few layers.
- Decode at _half the linear resolution_ (quarter the pixel count) by stopping at the LL3 subband.
- Decode a _region of interest_ by reading only the code-blocks overlapping that region.

These properties (quality scalability, resolution scalability, and spatial random access) are built into the bitstream structure without any extra work from the decoder. Nothing comparable exists in JPEG, which requires separate low-resolution JPEG files or multi-res image pyramids.

#gomaths("Scalability: SNR vs resolution")[
_SNR scalability_ means you can trade quality for bitrate smoothly: each additional layer improves the signal-to-noise ratio of every pixel. In information terms, you are adding refinement bits that reduce quantization error.

_Resolution scalability_ means you can trade image dimensions for bitrate: to decode at half resolution, simply stop after the LL subband at a coarser DWT level. The coarser subbands cost far fewer bits (they are smaller), and the decoder never even reads the fine-detail subbands. A 1 MB file might decode to a sharp thumbnail using only 50 KB of data from its start.

Both types of scalability come "for free" from the DWT-plus-EBCOT structure, with no extra coding penalty.
]

== The Compression Performance

How well does JPEG 2000 actually compress? On photographic images (the Kodak image set is the standard benchmark), JPEG 2000 Part 1 achieves roughly *20–30% better compression* than baseline JPEG at the same visual quality (as measured by PSNR). At very low bitrates (heavy compression), the advantage grows: JPEG 2000 avoids blocking while JPEG tiles collapse into ugly grids, so the _perceptual_ quality gap is larger than the PSNR gap.

#algo(
  name: "JPEG 2000",
  year: "2000–2001",
  authors: "ISO/IEC JTC 1/SC 29/WG 1 (Christopoulos, Skodras, Ebrahimi, Taubman, and many others); EBCOT by David Taubman",
  aim: "Wavelet-based scalable image coding standard: resolution scalability, quality scalability, lossless and lossy in one bitstream, regions of interest, large images.",
  complexity: "O(N log N) DWT; O(N) EBCOT per bit-plane; O(N) total where N = image pixels.",
  strengths: "No blocking artifacts; genuine SNR and resolution scalability; lossless mode; tiling for huge images; regions-of-interest; superior low-bitrate quality vs JPEG.",
  weaknesses: "Complex implementation; slow encoder/decoder (MQ coder); never gained web browser support; patent uncertainty chilled early adoption.",
  superseded: "HTJ2K (Part 15) for throughput; AVIF/JPEG XL for consumer web use; still dominant in cinema, medical, and archival.",
)[
The standard has 17 parts. Part 1 (ISO/IEC 15444-1, first edition 2000, latest 2019) is the core, and is free of known royalties. Part 2 adds extensions (arbitrary wavelet filters, ROI coding, etc.). Part 3 defines Motion JPEG 2000 (MJP2) for digital cinema. Part 6 covers compound documents.
]

== The MQ Coder in Detail

The MQ coder is worth a closer look because it shows a neat design philosophy. The name carries no grand meaning: the "Q" comes from IBM's earlier _Q-coder_ and _QM-coder_ lineage used in the original JPEG and JBIG standards, and the "M" marks the Mitsubishi-submitted variant the committee adopted in 1999. It is _not_ short for "multi-resolution," a common myth. It is a _binary_ arithmetic coder, coding only one bit at a time. That restriction simplifies the implementation considerably compared to multi-symbol arithmetic coders.

Each bit has a _context label_ (a small integer 0–18), computed from the spatial neighbourhood. The MQ coder maintains a probability estimate for each context: the probability that the next bit in this context is a "0" (the _more probable symbol_, or MPS, for that context). When it codes a "0" it updates the MPS count; when it codes a "1" it updates the _less probable symbol_ (LPS) count. The coder adapts its estimates via a finite-state probability table with 47 states, each encoding a probability estimate and a switching direction, rather than doing exact counting. This keeps the memory and logic small.

The arithmetic itself follows the same interval-subdivision logic you learned in Chapter 26: the current code interval is split according to the probability of the MPS, and the new interval is renormalized to keep the precision register from underflowing.

#gopython("Binary arithmetic coding: the MQ coder idea")[
Here is a simplified sketch of how a context-adaptive binary coder works (not the full MQ coder, but the essential idea). Each context maintains a running estimate of P(bit=0). The arithmetic coder uses that probability to encode each bit.

```python
# Very simplified context-adaptive binary encoder sketch.
# This is NOT the full MQ coder - just the probability-adaptation idea.

class ContextModel:
    """Tracks the probability of bit=0 for one context."""
    def __init__(self) -> None:
        self.count0: int = 1   # pseudo-count for 0-bits
        self.count1: int = 1   # pseudo-count for 1-bits

    def prob_zero(self) -> float:
        return self.count0 / (self.count0 + self.count1)

    def update(self, bit: int) -> None:
        if bit == 0:
            self.count0 += 1
        else:
            self.count1 += 1

def encode_bits_with_context(bits: list[int],
                              contexts: list[int],
                              n_contexts: int) -> None:
    models = [ContextModel() for _ in range(n_contexts)]
    for bit, ctx in zip(bits, contexts):
        p0 = models[ctx].prob_zero()
        # In a real arithmetic coder: narrow the interval by p0 or (1-p0)
        print(f"ctx={ctx} bit={bit} P(0)={p0:.3f}")
        models[ctx].update(bit)

# Example: code 8 bits with 3 contexts
example_bits     = [0, 0, 1, 0, 1, 0, 0, 1]
example_contexts = [0, 0, 1, 2, 1, 0, 2, 1]
encode_bits_with_context(example_bits, example_contexts, n_contexts=3)
```

Each context learns independently. If context 0 consistently sees 0-bits (significance propagation in a smooth region), its `prob_zero` rises toward 1, and the arithmetic coder assigns very few bits per 0-bit. That is nearly optimal compression for that context.
]

== JPEG 2000 in the Real World: Where It Actually Won

For a format often described as a "failure," JPEG 2000 has an impressive installed base, just not where you look with a web browser.

=== Digital Cinema

In 2005, *Digital Cinema Initiatives (DCI)* (the consortium of major Hollywood studios) selected JPEG 2000 as the mandatory compression standard for *Digital Cinema Packages (DCPs)*. Every digital projector you sit in front of in a commercial cinema plays back JPEG 2000. The DCI specification (version 1.4.2, June 2022) mandates JPEG 2000 Part 3 (Motion JPEG 2000) at up to 250 megabits per second for 4K content.

Why JPEG 2000 for cinema? The professional requirements fit its strengths exactly:
- *Lossless or very high quality* is required; blocking artifacts are unacceptable.
- *Large frames* (4096×2160 for 4K) benefit from the DWT's whole-image transform.
- *Random access* to individual frames matters for studio post-production workflows.
- *Bitrate doesn't matter much* at 250 Mbps: the bottleneck is disk throughput, not compression ratio.

=== Medical Imaging

The *DICOM* (Digital Imaging and Communications in Medicine) standard, which governs how hospitals exchange CT scans, MRI images, X-rays, pathology slides, and ultrasound images, adopted JPEG 2000 by 2008 as a transfer syntax. Radiology and digital pathology are heavy users, especially for _lossless_ JPEG 2000 (using the integer CDF 5/3 wavelet) where diagnostic certainty is paramount.

The scalability is again the draw: a 2-gigapixel whole-slide image from a digital pathology scanner can be stored as one JPEG 2000 file, then zoomed and panned in a viewer that reads only the resolution level and spatial tile it needs at any given moment, without decompressing the whole file.

=== Archiving and Preservation

National archives, libraries, and museums use JPEG 2000 for master archival copies of digitised manuscripts, photographs, maps, and art. The Library of Congress's NDNP (Newspaper Digitization Program) archives in JPEG 2000. The Internet Archive stores many digitised books in JPEG 2000. The lossless mode means the archival copy is a perfect pixel-by-pixel record; a lower-quality derivative can be generated on the fly by truncating the bitstream.

=== Why the Web Said No

The reasons the web never embraced JPEG 2000 combine business, politics, and practical engineering in about equal measure.

*Complexity and slowness.* A JPEG 2000 decoder circa 2000 needed roughly ten times the computation of a JPEG decoder on the same image at equivalent quality. Web browsers in that era ran on much slower hardware, and page load time was everything.

*Patent uncertainty.* Part 1 of the standard was intended to be royalty-free, but the broader JPEG 2000 ecosystem (especially extensions in later parts) had tangled intellectual property. IBM and other companies held patents on sub-elements of JPEG 2000. The JPEG committee worked to clear Part 1, but browser vendors were not willing to risk even uncertain royalty exposure.

*JPEG was good enough.* The web's images were mostly at moderate quality, where JPEG blocking was not catastrophic. The improvement from JPEG 2000 was real but not obviously worth a new format rollout.

*No dominant open-source implementation.* OpenJPEG, the main open-source library, was slower and less reliable than the mature `libjpeg` ecosystem for a long time. (This situation improved substantially from 2015 onward.)

*Apple's half-measure.* Safari shipped JPEG 2000 support for a time (it still appears in some iOS documentation), but without wide browser support, web publishers had no incentive to produce JPEG 2000 content.

#misconception[JPEG 2000 was a commercial failure.][It depends entirely on your market. JPEG 2000 dominates digital cinema, is widespread in medical imaging, and runs archival workflows at major cultural institutions. It "failed" only on the consumer web, a market where it faced insurmountable momentum advantages for a less capable incumbent.]

== Regions of Interest

One capability unique to JPEG 2000 (and absent from JPEG or most other still-image formats) is *Region of Interest (ROI) coding*. The encoder can designate a rectangular or arbitrary-shaped region of the image as "important" and arrange the bitstream so that region's bits come first. A decoder that stops early (at a low bitrate) gets a sharp ROI surrounded by a blurry background, rather than a uniformly blurry image.

The simplest method (the "maxshift" method in Part 1) works by shifting the bit-planes of the ROI coefficients up by a fixed number $s$. Since bit-planes are coded from the MSB down, the ROI's bits appear first in the stream. The shift $s$ must be large enough that even the ROI's least significant bit outranks all background bits, which requires $s >= ceil(log_2(K))$ where $K$ is the maximum quantized magnitude in the background, and $ceil(dot)$ is the _ceiling_ function (round _up_ to the nearest whole number, the partner of the floor function from Chapter 7: $ceil(2.1) = 3$, $ceil(4) = 4$).

Medical imaging makes obvious use of this: a radiologist's region of interest (say, a lesion or a joint) is coded at high quality while surrounding tissue degrades gracefully.

== High-Throughput JPEG 2000 (HTJ2K, Part 15)

The slow MQ coder has always been the primary complaint against JPEG 2000. An image codec operating at 2–3 frames per second on 2000-era hardware was fine for archival and cinema (which have lots of time and money) but useless for real-time applications.

In 2019, ISO/IEC 15444-15, informally known as *HTJ2K* or *High-Throughput JPEG 2000*, was standardised. HTJ2K keeps everything about JPEG 2000 (the DWT, the code-block structure, the layer/tier architecture) but replaces the MQ coder with a completely new *HT Block Coder* designed for vectorised (SIMD) hardware. The HT block coder:

- Uses much simpler context modelling than MQ (fewer passes, simpler states).
- Operates on groups of four (or more) samples simultaneously, exploiting hardware SIMD.
- Sacrifices roughly *5–10% compression efficiency* compared to MQ-coded JPEG 2000.
- In exchange, gains *10–30× throughput*: a code block that took 1 ms with MQ takes 30–100 µs with HTJ2K.

*OpenJPEG 2.5* (released May 2022) added HTJ2K decoding support. The open-source *OpenJPH* library specialises in HTJ2K and is used in several broadcast and medical imaging workflows. Code4Lib and digital library communities have evaluated HTJ2K as a "drop-in replacement for JPEG 2000 with IIIF" (the International Image Interoperability Framework used by museums and archives) and found the quality-throughput trade-off very favourable.

#algo(
  name: "HTJ2K (High-Throughput JPEG 2000, Part 15)",
  year: "2019",
  authors: "ISO/IEC JTC 1/SC 29/WG 1; principal contributors Aous Naman and David Taubman (University of NSW)",
  aim: "Replace JPEG 2000's sequential MQ entropy coder with a vectorisable HT block coder, enabling 10–30× higher throughput with ~5–10% compression penalty.",
  complexity: "O(N) per frame; SIMD-parallelisable within each code-block.",
  strengths: "All JPEG 2000 scalability and quality features preserved; dramatic speed increase; drop-in bitstream compatibility with existing infrastructure.",
  weaknesses: "Slightly worse compression than classical JPEG 2000; still not widely deployed outside specialist domains.",
  superseded: "N/A: HTJ2K is the current high-performance branch of the JPEG 2000 family.",
)[]

== Illustrative Python: Wavelet-Based Compression

There is no assigned tinyzip step for Chapter 43 (that belongs to Chapter 38, where the DCT/DWT modules were built). Let us write some illustrative code that uses the principles of JPEG 2000 - forward DWT, quantization, and an insight into bit-plane counting - to understand the quality trade-off.

#gopython("Nested lists and 2-D arrays in Python")[
Python's built-in `list` can hold other lists, giving you a 2-D array. To access element at row `r`, column `c`, write `grid[r][c]`. For image processing, the NumPy library's `ndarray` is more efficient, but understanding list-of-lists first builds the right mental model.

```python
# A 3×3 grid as a list of lists
grid: list[list[int]] = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
]
print(grid[1][2])   # → 6  (row 1, column 2, zero-indexed)
```
]

```python
"""
Illustrative sketch: how bit-plane depth relates to quality.
This is NOT a full JPEG 2000 encoder - just the key idea that
more bit-planes = better quality, and you can stop anywhere.
"""

def quantize(value: float, step: float) -> int:
    """Dead-zone scalar quantizer - same rule JPEG 2000 uses."""
    return int(value / step) if abs(value) >= step/2 else 0

def bitplanes_needed(q: int) -> int:
    """Number of bit-planes to represent the magnitude of q."""
    return max(1, q.bit_length())

def quality_at_planes(q_values: list[int], planes_kept: int) -> list[int]:
    """
    Simulate truncating the bitstream to `planes_kept` bit-planes.
    Each coefficient is rounded to only its top `planes_kept` bits.
    """
    result: list[int] = []
    for q in q_values:
        magnitude = abs(q)
        total_bits = max(1, magnitude.bit_length())
        # Keep only the top `planes_kept` bits
        shift = max(0, total_bits - planes_kept)
        truncated = (magnitude >> shift) << shift
        result.append(truncated if q >= 0 else -truncated)
    return result

# Example: 8 quantized DWT coefficients
import math
orig: list[float] = [23.1, -14.7, 5.3, 0.2, -9.8, 31.5, -0.5, 17.4]
step: float = 1.0
q_vals = [quantize(v, step) for v in orig]
print("Quantized:", q_vals)

max_planes = max(abs(q).bit_length() for q in q_vals if q != 0)
print(f"Max bit-planes needed: {max_planes}")

for planes in range(1, max_planes + 1):
    recon = quality_at_planes(q_vals, planes)
    mse = sum((o - r)**2 for o, r in zip(orig, recon)) / len(orig)
    psnr = 10 * math.log10(31.5**2 / mse) if mse > 0 else float('inf')
    print(f"  {planes} planes: recon={recon}  PSNR≈{psnr:.1f} dB")
```

#mathrecall[PSNR (Peak Signal-to-Noise Ratio) and MSE (Mean Squared Error) were defined in Chapter 42: $"MSE" = (1/N) sum (o_i - r_i)^2$ averaged over all samples, and $"PSNR" = 10 log_10("peak"^2 / "MSE")$ in decibels, where "peak" is the largest possible signal value. Higher PSNR means lower error. Chapter 42 used $"peak" = 255$ for 8-bit pixels; the toy example above uses the largest coefficient magnitude as the peak, since these are abstract DWT coefficients rather than 0–255 pixels.]

Running this, you would see PSNR grow steadily as `planes` increases, which is exactly the SNR scalability EBCOT exploits. With 1 plane you get a coarse sketch; with `max_planes` planes you get perfect reconstruction (at the quantization step used).

== Comparing JPEG and JPEG 2000 Directly

#scoreboard(
  caption: "JPEG vs JPEG 2000 on a 512×512 natural colour image (representative values)",
  [JPEG (quality 10)], [~12 KB], [≈ 65:1], [Heavy blocking artifacts; MSE high],
  [JPEG (quality 50)], [~35 KB], [≈ 23:1], [Moderate blocking; typical web use],
  [JPEG (quality 90)], [~120 KB], [≈ 6:1], [Mild artifacts; high quality],
  [JPEG 2000 (0.1 bpp)], [~33 KB], [≈ 24:1], [Smooth blur; no blocking; ~2–3 dB PSNR advantage over JPEG at similar rate],
  [JPEG 2000 (0.5 bpp)], [~160 KB], [≈ 5:1], [High quality; significantly better PSNR than JPEG-90],
  [JPEG 2000 lossless], [~330 KB], [≈ 2.4:1], [Pixel-perfect; using CDF 5/3 wavelet],
)

The bitrate is measured in *bits per pixel (bpp)*: $"bpp" = (8 times "file size in bytes") / ("width" times "height")$. For a 512×512 image, 1 bpp = 262,144 bits = 32,768 bytes ≈ 32 KB. JPEG 2000's advantage is largest at low bitrates (0.1–0.5 bpp), where its avoidance of blocking makes a dramatic perceptual difference.

#gomaths("Bits per pixel (bpp)")[
_Bits per pixel_ (bpp) is the most natural way to compare image codecs: it tells you how many bits, on average, were spent per pixel in the stored file. An uncompressed 8-bit greyscale image costs exactly 8 bpp. An 8-bit-per-channel RGB image costs 24 bpp.

$ "bpp" = (8 times "file size in bytes") / ("image width" times "image height") $

For a 512×512 colour image:
- 1 bpp → 32 KB file (very good compression from 768 KB raw)
- 0.25 bpp → 8 KB file (heavy compression)
- 0.1 bpp → 3.2 KB file (extreme compression)

JPEG typically looks good at 0.5–1 bpp. JPEG 2000 is competitive at 0.1–0.5 bpp.
]

== The Legacy and the Lesson

JPEG 2000 embodies one of the clearest lessons in the history of technology: _technical superiority is necessary but not sufficient for adoption_.

Look at what JPEG 2000 offered in 2000: embedded progressive coding, lossless and lossy from one bitstream, no blocking, genuine scalability, ROI coding, large-image tiling. JPEG offered none of these. Yet JPEG remained dominant on the web for another quarter century.

The forces that held JPEG in place were:
- *Installed base*: trillions of JPEG files; billions of web pages with `<img src=".jpg">`.
- *Decoder availability*: `libjpeg` was on every device; JPEG 2000 decoders were not.
- *Complexity cost*: a JPEG 2000 decoder is roughly ten times more code than a JPEG decoder.
- *Perceived benefit*: at typical web image qualities, the difference was real but not _obviously_ better at a glance.
- *Licensing uncertainty*: even a small patent risk made browser vendors nervous.

#history[
The standardisation of JPEG 2000 was completed at the _turn of a century_, which felt auspicious. The working group (ISO/IEC JTC 1/SC 29/WG 1) was chaired by Daniel Lee for much of its development. David Taubman (University of New South Wales, Australia) contributed EBCOT; Athanassios Skodras (Greece) and Charilaos Christopoulos (Ericsson, Sweden) co-led early standardisation. The reference software was shipped as two separate open-source projects: *JasPer* (by Michael Adams, begun 1999 at the University of British Columbia and first released to the public in December 2000) and later *OpenJPEG* (UCLouvain, Belgium). OpenJPEG became the more widely used of the two and is now the reference implementation for many professional applications.
]

What actually eroded JPEG's web dominance was not JPEG 2000 but a sequence of codecs that each solved a narrower problem: WebP (2010, VP8's intra frame), AVIF (2019, AV1's intra frame), and JPEG XL (2021, a purpose-designed image codec). We will meet those in Chapters 44 and 45.

== A Note on Part 2 and Beyond

JPEG 2000 Part 1 is the core, but the standard grew to 17 parts:

- *Part 2*: Extensions: additional wavelet filters, arbitrary ROI shapes, non-rectangular tiling.
- *Part 3*: Motion JPEG 2000 (MJP2): per-frame JPEG 2000 in an MJ2 container. Used in cinema and some broadcast applications.
- *Part 6*: Compound documents: mixing continuous-tone and binary content in one file (similar to JBIG2 for the binary parts).
- *Part 9*: JPIP (JPEG 2000 Interactive Protocol): a streaming protocol that lets a client request only the spatial region and quality layers it needs, over HTTP. Used in museum image viewers and geospatial platforms.
- *Part 15*: HTJ2K: high-throughput block coder, described above.

The IIIF (International Image Interoperability Framework), used by libraries and museums worldwide to expose zoomable high-resolution images via REST APIs, was designed specifically around JPEG 2000 and JPIP. An IIIF viewer zooms into a manuscript page by fetching just the relevant tile and resolution level from a JPEG 2000 file, a use case that no other standard format supported at the time.

#aside[
JPEG 2000 has a small but passionate community that remains convinced it is the _right_ format for a large class of applications. They are not wrong: for archival, cinema, and medical imaging, no successor has fully displaced it. The HTJ2K extension breathed new life into the family in 2019, and ongoing work continues within the JPEG committee on JPEG 2000 profiles for specific domains.
]

== Summary: The JPEG 2000 Pipeline

Let us walk through the full encoder pipeline end to end:

+ *Pre-processing*: split image into tiles (often one tile = whole image). Apply the colour transform (ICT for lossy, RCT for lossless).

+ *Wavelet transform*: apply the 2-D DWT to each component of each tile (CDF 9/7 for lossy, CDF 5/3 for lossless), typically 5 levels.

+ *Quantization*: divide each subband's coefficients by the appropriate step size and round toward zero.

+ *Code-block partition*: divide each subband into small code-blocks (e.g., 64×64).

+ *EBCOT Tier 1* (per code-block): bit-plane coding in three passes (significance propagation, magnitude refinement, cleanup), each pass using the MQ arithmetic coder with context-dependent probability models.

+ *Rate–distortion optimisation*: for each code-block, compute the rate–distortion slope at each truncation point. Select truncation points globally to minimise distortion at the target bitrate.

+ *EBCOT Tier 2* (packet assembly): collect the selected code-block segments and organise them into _packets_. Each packet corresponds to one layer × one resolution level × one tile × one component.

+ *Bitstream (codestream)*: packets are written into the JPEG 2000 codestream, prefixed with a main header describing tile, component, and wavelet parameters.

+ *File format*: the codestream can be wrapped in the JP2 container (which adds colour space metadata, XML metadata boxes, and an integrity check) or left as a raw codestream (.j2c / .j2k).

#fig([JPEG 2000 encoder pipeline, from image pixels to bitstream.],
cetz.canvas({
  import cetz.draw: *

  let box-w = 1.5
  let box-h = 0.85
  let gap = 0.25
  let y = 0.0

  let stages = (
    ("Colour", "Transform"),
    ("2-D", "DWT"),
    ("Quant-", "ize"),
    ("Code-", "blocks"),
    ("EBCOT", "Tier 1"),
    ("RDO", "Tier 2"),
    ("Bit-", "stream"),
  )

  let n = stages.len()

  for (i, parts) in stages.enumerate() {
    let x = i * (box-w + gap)
    let is-ebcot = i == 4
    rect((x, y), (x + box-w, y + box-h),
      fill: rgb("#0b5394").lighten(if is-ebcot { 30% } else { 70% }),
      stroke: 0.8pt + rgb("#0b5394"),
      radius: 3pt)
    let lbl-col = if is-ebcot { white } else { rgb("#1a1a1a") }
    content((x + box-w/2, y + box-h/2),
      box(width: 1.3cm, inset: 1pt, align(center,
        text(size: 7pt, fill: lbl-col)[#parts.at(0) \ #parts.at(1)])))
    if i < n - 1 {
      let ax = x + box-w
      let ay = y + box-h/2
      line((ax, ay), (ax + gap, ay),
        stroke: 0.7pt + rgb("#0b5394"),
        mark: (end: ">"))
    }
  }

  // Highlight EBCOT
  content((4 * (box-w + gap) + box-w/2, y + box-h + 0.25),
    box(width: 1.8cm, inset: 1pt, align(center,
      text(size: 7pt, fill: rgb("#9a2617"))[MQ coder])))
}))

#takeaways((
  [JPEG 2000 replaces JPEG's independent 8×8 block DCT with a full-image 2-D DWT, eliminating blocking artifacts. Degradation at low bitrates is smooth blur, not tiles.],
  [Two wavelet filters are used: CDF 9/7 (floating-point, for lossy) and CDF 5/3 (integer, for exact lossless reconstruction).],
  [EBCOT codes each code-block's quantized DWT coefficients one bit-plane at a time in three passes (significance propagation, magnitude refinement, cleanup), using the MQ binary arithmetic coder.],
  [The bit-plane structure makes the bitstream _embedded_: truncating it at any point yields the best possible image for the bits spent. This provides both SNR (quality) scalability and resolution scalability.],
  [Rate–distortion optimisation (Tier 2) globally selects which code-block truncation points to include in each quality layer, minimising distortion at the target bitrate.],
  [JPEG 2000 dominates digital cinema (DCI/DCP), medical imaging (DICOM), and cultural archiving, while never gaining mainstream web adoption. The contrast illustrates the gap between technical merit and ecosystem momentum.],
  [HTJ2K (Part 15, 2019) replaces the MQ coder with a vectorisable HT block coder, gaining 10–30× throughput at ~5–10% compression cost, enabling real-time use cases while preserving all JPEG 2000 scalability features.],
))

== Exercises

#exercise("43.1", 1)[
A JPEG 2000 encoder uses 4 levels of DWT decomposition on a 256×256 greyscale image. How many subbands does this create? Sketch the pyramid structure, naming each subband. (Hint: level 1 creates 4 subbands from the full image; level 2 creates 4 more from the LL subband of level 1, and so on.)
]
#solution("43.1")[
Each DWT level creates 4 subbands (LL, LH, HL, HH) by splitting the previous LL. With 4 levels, levels 2–4 split the LL subband further, so the total number of subbands is $3 times 4 + 1 = 13$: LL4 plus 3 detail subbands at each of the 4 levels. The pyramid: LL4 (16×16), LH4 (16×16), HL4 (16×16), HH4 (16×16) in the top-left quadrant; then LH3, HL3, HH3 at 32×32; then LH2, HL2, HH2 at 64×64; then LH1, HL1, HH1 at 128×128. One LL plus 12 detail subbands = 13 total.
]

#exercise("43.2", 1)[
Explain in plain words what _SNR scalability_ and _resolution scalability_ mean in the context of a JPEG 2000 file. Give one practical use case for each type of scalability.
]
#solution("43.2")[
_SNR scalability_: the same bitstream can be truncated to deliver any image quality. Reading more bytes raises the PSNR monotonically. Use case: a museum's image viewer first sends a low-quality preview; as the user waits or pays for a higher-quality licence, more layers are streamed in. _Resolution scalability_: the decoder can stop at a coarser DWT level to reconstruct a lower-resolution version without decompressing the full image. Use case: a web thumbnail is generated from the first few KB of a 10 MB archival scan, without loading the whole file.
]

#exercise("43.3", 2)[
A code-block contains the following 1-D array of quantized DWT coefficients: 4, −6, 0, 2. Trace the significance-propagation pass and cleanup pass for bit-plane 2 (the "2s-place" bit, that is, the second-most-significant bit for values representable in 3 bits). Assume no coefficient has a left or right neighbour outside this block, and significance is determined only by the MSB already having been set.

Specifically: after bit-plane 2 (the MSB) is coded, which coefficients are significant? In the significance-propagation pass for bit-plane 1, which coefficients are coded, and why?
]
#solution("43.3")[
Magnitudes: |4|=4 (binary 100), |−6|=6 (binary 110), |0|=0 (binary 000), |2|=2 (binary 010).

Bit-plane 2 (MSB = bit value 4): bits are 1, 1, 0, 0. After the cleanup pass, coefficients at positions 0 (value 4) and 1 (value 6) are significant; positions 2 and 3 are not.

Bit-plane 1 (bit value 2), significance-propagation pass: only non-significant coefficients with a significant neighbour are coded. Position 2 (value 0) has a significant neighbour at position 1 → it is coded (its bit-plane-1 bit is 0; remains non-significant). Position 3 (value 2) has no significant neighbour (position 2 is still non-significant after coding) → it is _not_ coded in the significance-propagation pass, and waits for the cleanup pass, where its bit-plane-1 bit (1) makes it significant.
]

#exercise("43.4", 2)[
JPEG 2000 Part 1 uses two different wavelet filters: CDF 9/7 for lossy compression and CDF 5/3 for lossless. Why can a floating-point wavelet filter _not_ be used for lossless compression? What property of the CDF 5/3 filter enables lossless coding?
]
#solution("43.4")[
Floating-point arithmetic is not exact: rounding errors in the filter coefficients mean that a forward-then-inverse transform does not reproduce the original integers. Even tiny rounding differences make lossless coding impossible. The CDF 5/3 filter uses integer arithmetic throughout: its analysis and synthesis filter coefficients are rational numbers that, when applied in the _lifting scheme_ with rounding steps specified by the standard, produce an exactly invertible transform. Every integer input maps to integer intermediate values, and the inverse perfectly recovers the originals.
]

#exercise("43.5", 2)[
Consider the trade-off HTJ2K makes: roughly 5–10% worse compression, but 10–30× faster. For each of the following applications, state whether classical JPEG 2000 (MQ coder) or HTJ2K is the better choice and explain why: (a) archiving a 10-million-image photograph collection to cold storage; (b) a live 4K video feed over a 1 Gbps network link; (c) a DICOM viewer for a radiologist reading a 3 GB CT scan.
]
#solution("43.5")[
(a) Cold archival storage: classical JPEG 2000 (MQ). Encoding is a one-time cost; throughput does not matter. The 5–10% compression saving over HTJ2K means meaningful storage cost reductions at 10 million images. (b) Live 4K video: HTJ2K, decisively. Real-time encoding requires enormous throughput. A 10–30× speed advantage enables 4K at 24fps or higher, which the MQ coder cannot deliver without prohibitively expensive hardware. (c) Radiology DICOM viewer: either, but HTJ2K for interactive use. The radiologist needs fast random-access pan and zoom; HTJ2K's throughput helps load new tiles rapidly. If storage is limited, classical JPEG 2000 lossless is marginally smaller. Modern DICOM implementations increasingly support both.
]

#exercise("43.6", 3)[
Write a Python function `bitplane_truncate(coefficients: list[int], planes: int) -> list[int]` that, given a list of signed integer coefficients (the result of DWT quantization) and a number of bit-planes to keep, returns the truncated reconstruction. The function should: (a) find the maximum number of bit-planes needed for any coefficient; (b) keep only the top `planes` bit-planes of each magnitude; (c) preserve the sign. Test it by verifying that calling with `planes = max_planes` recovers the original values exactly, and that the mean squared error decreases monotonically as `planes` increases from 1 to `max_planes`.
]
#solution("43.6")[
```python
import math

def bitplane_truncate(coefficients: list[int], planes: int) -> list[int]:
    result: list[int] = []
    for c in coefficients:
        magnitude = abs(c)
        total = max(1, magnitude.bit_length())
        shift = max(0, total - planes)
        truncated = (magnitude >> shift) << shift
        result.append(truncated if c >= 0 else -truncated)
    return result

def mse(a: list[int], b: list[int]) -> float:
    return sum((x - y)**2 for x, y in zip(a, b)) / len(a)

# Test
coeffs = [23, -14, 5, 0, -9, 31, -1, 17]
max_planes = max(abs(c).bit_length() for c in coeffs if c != 0)

# Exact reconstruction at max_planes
assert bitplane_truncate(coeffs, max_planes) == coeffs

# Monotone decreasing MSE
errors = [mse(coeffs, bitplane_truncate(coeffs, p))
          for p in range(1, max_planes + 1)]
for i in range(len(errors) - 1):
    assert errors[i] >= errors[i+1], "MSE not monotone!"
print("All assertions passed. MSEs:", [f"{e:.1f}" for e in errors])
```
]

== Further Reading

- #link("https://uweb.engr.arizona.edu/~bilgin/publications/DCC2000.pdf")[A. Skodras, C. Christopoulos, T. Ebrahimi, "The JPEG 2000 Still Image Compression Standard," _IEEE Signal Processing Magazine_, 2001.] The authoritative overview article written by the standardisation leads.

- D. S. Taubman and M. W. Marcellin, _JPEG 2000: Image Compression Fundamentals, Standards and Practice_, Kluwer Academic, 2002. The definitive textbook on every aspect of the standard; still the primary reference.

- #link("https://www.openjpeg.org/")[OpenJPEG project (openjpeg.org)]: the main open-source JPEG 2000 library (UCLouvain, Belgium), written in C.

- #link("https://github.com/aous72/OpenJPH")[OpenJPH (github.com/aous72/OpenJPH)]: open-source HTJ2K implementation; useful for understanding the HT block coder.

- #link("https://journal.code4lib.org/articles/17596")[M. Appleby et al., "Evaluating HTJ2K as a Drop-In Replacement for JPEG 2000 with IIIF," _Code4Lib Journal_, 2023.] Practical evaluation of HTJ2K performance in library/museum image servers.

- D. S. Taubman, "High Performance Scalable Image Compression with EBCOT," _IEEE Trans. Image Processing_, vol. 9, no. 7, July 2000. The original EBCOT paper, and the primary reference for the theory.

- #link("https://www.dcimovies.com/specification/")[DCI Digital Cinema System Specification v1.4.2, June 2022.] Shows exactly how JPEG 2000 is mandated in cinema.

#bridge[
JPEG 2000 showed that wavelets, embedded coding, and genuine scalability can coexist in one standard. It also showed that patent risk and implementation complexity can strand a format in niches, however technically capable it is. Chapter 44 turns to the other side of the image-format story: the formats that _did_ win the web. GIF gave the world the animated meme and a patent firestorm. PNG fixed the losslessness that JPEG could never offer. And QOI (2021) proved that a motivated programmer with a weekend and a remarkably simple idea could write a format that outperforms PNG on decode speed with a single-file specification. They are all waiting for us in the next chapter.
]
