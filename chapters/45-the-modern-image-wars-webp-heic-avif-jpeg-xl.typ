#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Modern Image Wars: WebP, HEIC, AVIF, JPEG XL

#epigraph[
  "We are not in the image compression business. We are in the image
  _quality at every byte_ business, and those are not the same thing."
][Jon Sneyers, co-designer of JPEG XL, 2021]

Here is a puzzle that starts with your phone. Open your camera roll and look
at the format tag on a photo you took last year. On an iPhone it probably
says HEIC. On an Android or a modern web page it probably says WebP or AVIF.
And if you have ever worked with high-fidelity photography, you may have seen
the unusual extension `.jxl`. Four formats, each alive and actively used today,
each claiming to be the rightful heir to the thirty-year-old JPEG throne,
with JPEG itself still reigning as the universal floor. How did we end up with
four serious competitors and no clear winner?

The answer is a tangle of patents, corporate strategy, browser politics,
and genuine technical differences. WebP launched in 2010 promising to fix
JPEG; HEIC went straight to half a billion iPhone cameras in 2017; AVIF
arrived in 2019 with a royalty-free promise and swept all major browsers by
2022; JPEG XL was removed from Chrome in 2023 in one of the most controversial
decisions in the history of browser standards, only to be re-added in
February 2026. Every one of them is technically superior to JPEG in
measurable ways. None of them has replaced it on the open web.

This chapter maps the battlefield. We will examine how each format works
under the hood, what it does better than JPEG (and what it does worse),
who controls it and what that means, and where the war stands in mid-2026.

#recap[
  In Chapter 42 we dissected JPEG: the DCT, quantization tables, zig-zag
  scanning, and Huffman entropy coding: the template that every later lossy
  codec copies. Chapter 43 studied JPEG 2000 and its wavelet transform.
  Chapter 44 covered lossless image formats (GIF, PNG, and QOI). Chapter 27
  introduced ANS (Asymmetric Numeral Systems), the entropy coder that powers
  both Zstandard and JPEG XL. Chapter 54 will give the full story of VP8, VP9,
  and AV1 as _video_ codecs; here we focus on their _image_ mode.
]

#objectives((
  "Explain the key technical differences between WebP, HEIC, AVIF, and JPEG XL.",
  "Describe how each format is related to a parent video codec and what that inheritance means.",
  "Understand why HEVC's patent situation kept HEIC off the open web.",
  "Explain JPEG XL's lossless JPEG transcoding and why it is a unique feature.",
  "Read and interpret a Python snippet that measures file-size trade-offs between formats.",
  "Articulate the licensing, ecosystem, and political factors behind format adoption.",
))

== The Template Every Modern Format Inherits

Before we can judge these new formats fairly, we need to remember the
template they all compete with (and mostly copy). In Chapter 42 we built
JPEG's pipeline step by step:

+ Convert RGB to YCbCr and optionally subsample chroma (4:2:0).
+ Split the luminance and chroma channels into 8×8 pixel blocks.
+ Apply the Discrete Cosine Transform to each block.
+ Divide each DCT coefficient by a quantization table entry and round.
+ Entropy-code the quantized integers with Huffman coding.

That pipeline is not JPEG's invention in a vacuum; it is the distillation
of thirty years of signal-processing research. The lossy step is quantization:
it permanently discards information the eye cannot easily detect. The lossless
step is entropy coding: it packs what remains as tightly as possible. The
quality knob lives in the quantization table.

#keyidea[
  Every format in this chapter follows the same fundamental template:
  _transform_ (change basis so energy concentrates) → _quantize_ (throw away
  what the eye cannot see) → _entropy code_ (pack what remains). They differ
  in _which_ transform, _how_ they quantize, and _which_ entropy coder. The
  more aggressive the quantization, the smaller the file; the smarter the
  entropy coder, the fewer bits are wasted on what remains.
]

What improvements are even possible over 1992's JPEG? Three main categories:

- *Better transforms.* Larger blocks, variable block sizes, and wavelet
  decompositions all reduce blocking artifacts and capture more of the
  image's structure with fewer non-zero coefficients.
- *Better entropy coding.* ANS and arithmetic coding squeeze a few more
  percent out of the same quantized symbols at little quality cost.
- *Better perceptual models.* Newer perceptual color spaces and masking models
  know more precisely which errors the eye will and won't detect, so they can
  be more aggressive exactly where it hurts least.

Each format below exploits some subset of these three improvements.

== WebP: Google Wrangles a Video Codec

=== Origin

In May 2010, Google acquired On2 Technologies (a video codec company) for
approximately \$125 million. On2 had built VP8, a proprietary video codec.
Google open-sourced VP8 and announced _WebP_ on September 30, 2010: take VP8's
intra-frame (single-picture) prediction and transform machinery, wrap it in a
still-image container, and you have a modern image format. The appeal was
simple: the web giant that controlled Chrome, YouTube, and Android pushing one
format is a strong distribution guarantee.

=== How WebP Lossy Works

WebP's lossy mode closely mirrors an intra-coded VP8 video frame:

- The image is split into *16×16 macroblocks* (a _macroblock_ is just a fixed
  square tile of pixels, the unit a video codec processes at a time), each
  subdivided into 4×4 or 8×8 sub-blocks for the luminance (Y) plane. This is
  already an improvement over JPEG's fixed 8×8 grid: flexible block sizes can
  adapt better to the image content.
- Each block is *intra-predicted*: a predictor mode is chosen that extrapolates
  the block's expected pixel values from the already-encoded neighboring
  blocks above and to the left. The residual (error) is what gets transformed.
  JPEG has no prediction step; it just transforms raw pixel values.
- The residuals are transformed with a *4×4 or 8×8 DCT*, then quantized.
- Entropy coding uses an *arithmetic coder* (the technique we built in
  Chapter 26), which is slightly more efficient than JPEG's Huffman coder
  (Chapter 24) for the same statistics.

The intra-prediction step is the main technical advantage. When a block
can be accurately predicted from its neighbors, the residual is tiny:
many zeros, and the DCT and quantizer have a much easier job. In a smooth
blue sky, the predictor says "more of the same blue" and the residual is
almost nothing. JPEG has to DCT-code the raw blue values every time.

Google's own studies found WebP lossy images to be 25–34% smaller than JPEG
at equivalent structural quality (SSIM). Independent tests generally confirm
roughly 25–30% savings on photographic content, with gains skewing higher for
images with large flat regions (product photos, illustrations on white
backgrounds) and lower for complex natural scenes with fine grain or noise.

#gomaths("Structural Similarity (SSIM)")[
  JPEG-era engineers measured image quality with *PSNR* (Peak Signal-to-Noise
  Ratio), which is the ratio of the maximum possible pixel value to the
  mean-squared error: $"PSNR" = 10 log_10 (255^2 / "MSE")$, in decibels. High
  PSNR means low error. But PSNR is blind to the way the _eye_ perceives
  error: it counts a misplaced edge the same as a uniform brightness offset,
  even though they look very different to a person.

  *SSIM* (Structural Similarity Index, Wang et al. 2004) compares patches of
  two images across three dimensions: luminance, contrast, and structure. The
  result is a number between 0 and 1 (1 = identical). SSIM correlates much
  better with human quality judgments than PSNR. When WebP claims "25–34%
  smaller at equivalent SSIM", it means the files are smaller while producing
  images that look equally good to a human observer.

  Modern quality metrics go further still: VMAF (Netflix, 2016), BUTTERAUGLI
  (Google, 2016, used internally in JPEG XL), and SSIMULACRA2 (2022) model
  more aspects of human vision. But SSIM remains the most-cited baseline.
]

=== WebP Lossless and Animated Modes

WebP is not only lossy. It added a *lossless mode* that uses predictive
coding (predicting each pixel from its neighbors in color space, not just
luminance), followed by a palette-based color transform, entropy filtering,
and LZ77-based compression (the sliding-window match finder of Chapter 28).
WebP lossless is typically 26% smaller than PNG
on photographic images, though PNG often wins on synthetic images (screenshots,
pixel art) with few unique colors.

WebP also supports *animated sequences* (replacing animated GIF), an *alpha
channel* (transparency), and *metadata* (Exif, XMP).

=== Adoption

Google's market power eventually forced adoption: Chrome (obviously), then
Firefox (2019), then Safari (2020). By 2022 WebP had near-universal browser
support. But adoption did not mean enthusiasm. WebP never produced a dramatic
compression leap dramatic enough to trigger a wholesale migration from JPEG,
and by the time it had universal support, its successors were already arriving.

#algo(
  name: "WebP Lossy",
  year: "2010",
  authors: "On2 Technologies / Google",
  aim: "Reduce web image file sizes vs JPEG using VP8 intra-frame prediction",
  complexity: "O(N) per block for intra prediction; O(N log N) for DCT",
  strengths: "25–34% smaller than JPEG at equivalent SSIM; wide ecosystem support; lossless and animated modes; royalty-free",
  weaknesses: "VP8 intra-prediction (4:2:0 YUV, 8-bit) limits quality; no HDR; no wide-gamut; slow encoding compared to JPEG; no progressive delivery",
  superseded: "AVIF and JPEG XL outperform it at most quality levels",
)[
  WebP was Google's first shot across JPEG's bow. It normalized the idea that
  video codec technology could power still-image compression, a template
  that HEIC, AVIF, and many neural codecs would follow. Its royalty-free
  status and Google's distribution muscle gave it ubiquity that technically
  superior competitors struggled to match for years.
]

== HEIC: The Billion-Camera Format Nobody Can Touch Online

=== The HEIF Container and HEVC Inside

*HEIF* (High Efficiency Image File Format) is an *ISO container format*
(ISO/IEC 23008-12, 2015) that can hold image data compressed by any codec.
In practice, the version everyone uses is *HEIC* (High Efficiency Image
Container), which stores images coded with *HEVC* (High Efficiency Video
Coding, also called H.265), the video standard from the MPEG/VCEG joint team.

HEVC was finalized in 2013. It is a major step beyond H.264: larger transform
block sizes (up to 64×64 _coding-tree units_, the HEVC successor to the
macroblock, vs H.264's 16×16 macroblocks), a richer set
of intra-prediction modes (35 directions vs H.264's 9), more sophisticated
deblocking and sample adaptive offset filters, and a more efficient entropy
coder (CABAC, Context-Adaptive Binary Arithmetic Coding, the arithmetic coder
of Chapter 26 with a context model bolted on). In practice, HEVC achieves
roughly 50% better compression than H.264 at the same quality, or equivalently
the same quality at half the bitrate.

HEIC inherits all of this for still images. It also adds features that JPEG
completely lacks:

- *Image sequences* (like animated GIF, but using full HEVC inter-prediction
  between frames).
- *Burst photo representations*: multiple exposures in one file.
- *Wide color gamut and 10-bit depth*: essential for modern HDR photography.
- *Depth maps and alpha transparency* stored alongside the main image.
- *Thumbnail and preview images* baked into the file.
- *EXIF and XMP metadata* in a structured way.

For a device camera workflow, HEIC is genuinely excellent: 50% smaller than
JPEG at equivalent quality, 10-bit color, HDR-ready, and it stores the Live
Photo video clip and the depth-map together.

=== Why Apple Adopted It, and Why the Web Cannot

Apple announced HEIC as the default photo format on iPhones starting with iOS 11
and iPhone 7 (September 2017). The hardware argument was compelling: an A10
Fusion chip could encode HEVC in hardware in real time, halving storage
consumption with no visible quality loss.

The web argument is absent. HEVC carries *multiple overlapping patent pools*:
MPEG LA, HEVC Advance (later renamed Access Advance), and Velos Media. As of
2026, any party shipping a product that encodes or decodes HEVC must negotiate
licenses with multiple pools and pay per-device or per-stream royalties. The
rates are contested, the pools do not agree with each other, and the total
liability is uncertain, which makes HEVC a legal minefield for a browser
vendor shipping to billions of users at no charge.

Safari can and does render HEIC natively, because Apple already pays HEVC
licensing fees for its own products. Chrome and Firefox do not. As of mid-2026,
eight years after iPhone began shooting HEIC by default, Chrome still cannot
display a HEIC file without a third-party library. The consequence for web
developers is that any HEIC file uploaded by an iPhone user must be transcoded
to JPEG, WebP, or AVIF on the server before serving it back to browsers.

#history[
  The HEVC patent war is the direct reason the Alliance for Open Media was
  founded. When MPEG LA introduced the HEVC patent pool in 2013, and HEVC
  Advance announced a *separate and more aggressive* pool in 2015, major
  internet companies, which had watched the H.264 patent pools grow over time,
  decided to build a royalty-free alternative from scratch. Amazon, Cisco,
  Google, Intel, Microsoft, Mozilla, and Netflix formed the Alliance for Open
  Media on September 1, 2015. Apple joined in 2018. The result was AV1 and,
  eventually, AVIF.
]

#pitfall[
  HEIC is *not* lossless JPEG recompression and is *not* backward-compatible
  with JPEG. An iPhone set to "Most Compatible" mode in Settings → Camera →
  Formats will shoot JPEG instead, at the cost of larger files. Many
  developers default to this setting for their app's photo upload flows
  to avoid server-side transcoding.
]

#algo(
  name: "HEIC (HEIF + HEVC intra)",
  year: "2015 (HEIF); 2017 (iPhone default)",
  authors: "ISO/MPEG/VCEG (HEVC); Apple (HEIC deployment)",
  aim: "50% smaller than JPEG at equivalent quality, with HDR, wide color, 10-bit depth",
  complexity: "Higher than JPEG; hardware encoder required for real-time",
  strengths: "Excellent compression; HDR/10-bit/wide-color native; image sequences; metadata-rich; universal on Apple devices",
  weaknesses: "HEVC patent licensing blocks browser support (Chrome, Firefox); slow software encode; iOS-centric ecosystem",
  superseded: "AVIF and JPEG XL for open-web use; HEIC likely remains dominant on Apple devices indefinitely",
)[
  HEIC is a case study in how a technically superior format can be blocked
  from the open web by legal overhead. Half a billion cameras shoot it by
  default, yet web developers treat it as an obstacle to route around. Patent
  pools won the battle against JPEG's successor on the web, which is exactly
  why the Alliance for Open Media exists.
]

== AVIF: The Royalty-Free Champion

=== AV1 and the Alliance

AV1 is the royalty-free video codec released by the Alliance for Open Media in
2018. Its technical heritage is a merger of Google's VP10, Mozilla's Daala,
and Cisco's Thor, absorbing the best ideas from each:

- *Variable block size coding* from 4×4 to 128×128 (far larger than HEVC's 64×64 coding-tree unit, giving better large-structure coding).
- *A rich set of directional intra-prediction modes*, far more than VP8's handful, that extrapolate a block from its neighbors along many possible angles, so the residual the transform must code is smaller.
- *Palette mode* for synthetic content: efficiently codes images with few distinct colors.
- *Film grain synthesis*: rather than compressing grain (which is expensive), AV1 can discard it and instruct the decoder to re-add statistically matching noise. For grainy photographs or cinematic content this saves bits with minimal visible quality change.
- *Intra block copy*: references other blocks within the same frame, very useful for repeated patterns (textures, UI elements, text).
- *Arithmetic entropy coding* (ANS-based) providing tight symbol compression.
- *Royalty-free by design.* The Alliance's license grants a perpetual, worldwide, no-charge right to make, use, sell, and distribute any implementation.

=== AVIF: AV1 for Still Images

*AVIF* (AV1 Image File Format) was finalized by the Alliance for Open Media in
February 2019 (version 1.0.0). It places one or more AV1 intra-coded frames
inside a HEIF container (the same ISO container HEIC uses; the container
itself is royalty-free, and only the codec inside determines the license). A single
AV1 intra frame is a still image. A sequence of them, with or without
inter-prediction, is an animation.

Compared to WebP, AVIF typically achieves an additional 15–25% reduction in
file size at equivalent quality on photographic images. At _low_ bitrates
(heavy compression) the difference is especially dramatic: AVIF's more
sophisticated prediction modes produce significantly fewer blocking artifacts
and ringing than WebP or JPEG at the same file size.

#gomaths("PSNR-HVS and Psychovisual Quality Metrics")[
  We saw SSIM above. Another useful metric is *PSNR-HVS* (PSNR with
  Human Visual System weighting), which applies a frequency-weighted filter
  before computing mean squared error. Errors in the frequency bands the eye
  is most sensitive to count for more. A deeper metric is *VMAF* (Video
  Multi-method Assessment Fusion), developed by Netflix in 2016. VMAF trains
  a machine learning model on human opinion scores (MOS, mean opinion score),
  predicting a number between 0 and 100. It generally outperforms SSIM at
  predicting human preference, particularly for streaming content at low bitrates.

  For AVIF vs WebP vs JPEG XL comparisons, the Cloudinary-maintained ImageMin
  benchmarks and the encode.su community benchmarks (both updated through
  2025–2026) typically use SSIMULACRA2 or BUTTERAUGLI as the quality axis,
  since both are specifically designed for still-image quality assessment.
]

=== Weak Points

AVIF's design is inherited from a _video_ codec, which introduces constraints
that a dedicated image format would not choose:

- *12-bit depth maximum* (AV1's internal pipeline is 12-bit). True professional
  photography sometimes wants 16-bit color (though 12-bit captures most HDR needs).
- *No native progressive delivery.* JPEG can show a blurry preview of the
  whole image from the first few KB of the stream; AVIF cannot without external
  tricks (generating multiple resolution tiles).
- *Resolution limits.* AV1 was designed for video resolutions; very large
  images (gigapixel photography, satellite imagery) require tiling and separate
  metadata.
- *Slow encoding.* AV1 encoding is computationally expensive, and real-time
  encoding at high quality requires capable hardware. Decoding is fast, and
  hardware AV1 decoders are now standard (Apple M1 onwards, Intel Tiger Lake,
  AMD RDNA2).

=== Browser and Ecosystem Support

AVIF support landed in Chrome 85 (August 2020), Firefox 93 (October 2021),
and Safari 16 (September 2022). As of mid-2026 it has approximately 94% global
browser coverage. The AVIF v1.2.0 spec (November 2025)
added sample transforms for greater-than-12-bit depth via codec layering and
gain-map signaling for SDR-compatible HDR. Photoshop added native AVIF support
in its June 2025 release (version 26.x).

#algo(
  name: "AVIF",
  year: "2019",
  authors: "Alliance for Open Media (Google, Netflix, Mozilla, Apple, Amazon, et al.)",
  aim: "Royalty-free still-image format leveraging AV1 intra-coding; 15–25% better than WebP",
  complexity: "Decode: O(N), hardware-accelerated on modern chips; Encode: expensive",
  strengths: "Royalty-free; excellent compression, especially at low bitrates; HDR and wide color; near-universal browser support (94%+); animated sequences",
  weaknesses: "12-bit depth cap; no native progressive delivery; slow software encoding; resolution/tiling limitations from video heritage",
  superseded: "JPEG XL challenges it at high-fidelity and progressive use cases; both coexist as of 2026",
)[
  AVIF is currently the dominant modern image format on the open web:
  royalty-free, widely supported, and considerably smaller than JPEG or WebP.
  Its weaknesses are real but mostly matter at the high end (professional
  photography, archival imaging) where JPEG XL has a stronger case.
]

#fig([AVIF vs JPEG vs WebP relative file size at equivalent visual quality. At low quality (high compression) AVIF's advantage is largest; at high quality the gap narrows.], cetz.canvas({
  import cetz.draw: *
  // Axes
  line((0,0), (8,0), mark: (end: ">"))
  line((0,0), (0,5), mark: (end: ">"))
  content((4,-0.5))[Quality (low → high)]
  content((-0.7,2.5), angle: 90deg)[File size (relative)]
  // JPEG curve (top)
  bezier((0.5,4.2),(4,3.2),(7.5,2.0), stroke: (paint: rgb("#9a2617"), thickness: 2pt))
  content((7.8,2.0), anchor: "west", text(fill: rgb("#9a2617"), size: 9pt)[JPEG])
  // WebP curve (middle)
  bezier((0.5,3.2),(4,2.5),(7.5,1.7), stroke: (paint: rgb("#0b5394"), thickness: 2pt))
  content((7.8,1.7), anchor: "west", text(fill: rgb("#0b5394"), size: 9pt)[WebP])
  // AVIF curve (lower)
  bezier((0.5,2.2),(4,1.9),(7.5,1.5), stroke: (paint: rgb("#0b6e4f"), thickness: 2pt))
  content((7.8,1.5), anchor: "west", text(fill: rgb("#0b6e4f"), size: 9pt)[AVIF])
  // JPEG XL curve (lowest)
  bezier((0.5,2.0),(4,1.7),(7.5,1.3), stroke: (paint: rgb("#783f04"), thickness: 2pt, dash: "dashed"))
  content((7.8,1.3), anchor: "west", text(fill: rgb("#783f04"), size: 9pt)[JXL])
}))

== JPEG XL: The Clean-Sheet Challenger

=== Two Research Projects Become One Standard

JPEG XL is the odd one out in this chapter. WebP, HEIC, and AVIF are all
video codecs wearing still-image clothes. JPEG XL was designed from scratch
for _images_. It traces to two independent research codecs:

*PIK* was developed starting around 2017 by a Google Research team in Zurich
led by *Jyrki Alakuijala* (also known for Brotli, Zopfli, and Guetzli). PIK
pioneered the XYB perceptual color space, a variable block size DCT, the
Butteraugli perceptual quality metric, and an adaptive quantization scheme
driven by that metric.

*FUIF* (Free Universal Image Format) was created by *Jon Sneyers* at
Cloudinary, descended from the lossless format FLIF that Sneyers released
in 2015. FUIF introduced _Modular_ encoding: a flexible, tree-based prediction
and entropy coding system capable of lossless compression, near-lossless,
and animation without the block artifacts that plague block-DCT codecs.

In 2018 the JPEG Committee (ISO/IEC JTC1 SC29 WG1) issued a call for a next
generation image format. Seven proposals were submitted. The committee selected
PIK and FUIF as the two most promising and asked their teams to merge them.
The result, JPEG XL, was finalized as *ISO/IEC 18181* in 2022.

#history[
  Alakuijala's Zurich team had an unusual background for an image-format team:
  they were primarily compression researchers (Brotli, Zopfli) and perceptual
  quality researchers (Guetzli, Butteraugli) before writing a codec. Sneyers
  had a history in _lossless_ image compression (FLIF). The merger of a
  top-tier lossy researcher and a top-tier lossless researcher, both strongly
  motivated by royalty-free open-standard principles, gives JPEG XL an unusual
  breadth: it is simultaneously competitive at high fidelity, at extreme
  lossless compression, and at every point between.
]

=== The Two Modes: VarDCT and Modular

JPEG XL has two internal coding modes that share a container and a single
entropy coder:

==== VarDCT Mode (Lossy Photography)

VarDCT is the lossy photographic mode. Its key differences from JPEG:

*Variable block sizes:* Rather than the fixed 8×8 DCT blocks of JPEG, VarDCT
chooses block sizes of 2×2, 4×4, 8×8, 8×16, 8×32, 16×16, 32×32, and 64×64
on the fly. Large smooth areas use big blocks (fewer DCT coefficients overall);
fine-detail regions use small blocks (accurate local coding). JPEG's 8×8 grid
is a compromise; JPEG XL's grid is adaptive.

*XYB color space:* JPEG converts RGB to YCbCr and codes chroma at half
resolution (4:2:0). JPEG XL instead converts to *XYB*, a color space derived
from the human visual system's _opponent channels_. (The eye does not send raw
red, green, and blue to the brain; it sends one brightness signal plus two
difference signals (roughly "blue vs yellow" and "green vs red"). This is why
you can picture a bluish-green but not a reddish-green: the channels oppose.)
The XYB transform is built around those three signals, so it is optimized for
the eye's spatial and color sensitivity rather than for computational
convenience. Critically, JPEG XL can choose per-image whether to subsample
chroma at all, and can do so adaptively.

*Adaptive quantization driven by Butteraugli:* The quantization table is
not fixed. A fast approximation of the Butteraugli perceptual metric is run
before encoding, identifying regions where the eye is insensitive (uniform
textures, low-contrast areas) and regions where it is sensitive (sharp edges,
faces). Quantization steps are increased in the first category and decreased in
the second. The bits saved on insensitive regions are reallocated to regions
that matter perceptually.

*Patches and splines:* For repeated structures and smooth curved elements
(logos, gradients, text on a background), VarDCT can encode these as geometric
primitives rather than pixel blocks, achieving extremely compact representation
for mixed content.

==== Modular Mode (Lossless and Near-Lossless)

The Modular encoder applies a sequence of *reversible integer transforms*:
a palette transform, a squeeze (wavelet-like) transform, and a channel
correlation transform, all invertible with no rounding error. After the
transforms, a *meta-adaptive arithmetic coder* with a learned context tree
packs the residuals. This gives JPEG XL a true lossless mode competitive with
PNG and, on many image types, beating it by 10–20%.

The Modular engine can also operate in *near-lossless* mode, bounding the
maximum per-pixel error to a small value (1, 2, 4 levels out of 255). This
is useful for medical imaging where exact fidelity is legally required but
a tiny guaranteed error is acceptable.

=== The Entropy Coder: ANS at the Heart

Both VarDCT and Modular share the same entropy coding backend:
*ANS* (Asymmetric Numeral Systems, invented by Jarek Duda and described in
his 2009 arXiv paper, later refined in 2013). We covered ANS in depth in
Chapter 27; here we apply it directly.

#mathrecall[
  ANS maps a sequence of symbols from a distribution into a single large
  integer, achievable at near-arithmetic-coding efficiency with near-Huffman
  decode speed. The key insight: the "state" encodes both the compressed data
  and the probability context simultaneously.
]

JPEG XL uses ANS in a *hybrid* entropy coder: each symbol stream can be coded
either with ANS or with ordinary prefix (Huffman-style) codes, and the encoder
picks whichever is cheaper per stream. This is the same family of coder that
powers Zstandard (Chapter 32). The result is that JPEG XL's entropy coding is
significantly tighter than JPEG's pure-Huffman coding, recovering 5–10% of the
file size from the entropy step alone, before any improvement in the transform
or quantization.

=== The Killer Feature: Lossless JPEG Transcoding

JPEG XL has one unique capability that no other format in this chapter has:
it can *losslessly recompress an existing JPEG file into a smaller `.jxl` file
and recover the exact original JPEG bytes bit-for-bit*.

How? JPEG's DCT coefficients are already integers (they were quantized and
rounded during JPEG encoding). The JPEG file itself is just those integers
run through Huffman coding. JPEG XL can directly ingest the DCT coefficient
stream, skip the quantization step entirely (because it was already done by
the JPEG encoder), and re-encode the same integers using its superior ANS
entropy coder, plus additional coefficient prediction.

The result: a `.jxl` file that is 16–22% smaller than the JPEG source, with
the exact same visual quality, because no re-quantization happened. The JPEG
can be reconstructed bit-for-bit from the `.jxl` file. This means you can
migrate your photo library from JPEG to JPEG XL, save 16–22% of storage,
and perfectly regenerate the original JPEG whenever you need backward compatibility.

#keyidea[
  The world has accumulated an estimated one trillion JPEG files. Lossless
  JPEG transcoding means JPEG XL can shrink all of them with zero quality
  loss and perfect reversibility. No other format offers this. It is one of
  the strongest arguments for JPEG XL as a universal photographic archive
  format, independent of any web deployment question.
]

#fig([JPEG XL lossless JPEG transcoding pipeline. The JPEG's existing DCT coefficients are extracted and re-entropy-coded with ANS; no re-quantization occurs. The process is fully reversible.], cetz.canvas({
  import cetz.draw: *
  // JPEG source box
  rect((0,3),(2.5,4), fill: rgb("#fef3e2"), stroke: rgb("#783f04"))
  content((1.25,3.5), box(width: 2.1cm, inset: 2pt, align(center, text(size: 8pt)[JPEG file])))
  // Arrow
  line((2.5,3.5),(3.2,3.5), mark: (end: ">"))
  // "Extract DCT coefficients" box
  rect((3.2,3),(6.0,4), fill: rgb("#e8f4f8"), stroke: rgb("#0b5394"))
  content((4.6,3.5), box(width: 2.4cm, inset: 2pt, align(center, text(size: 8pt)[Extract DCT coefficients])))
  // Arrow down
  line((4.6,3.0),(4.6,2.3), mark: (end: ">"))
  // "Re-entropy-code with ANS" box
  rect((3.2,1.5),(6.0,2.3), fill: rgb("#e8f4f8"), stroke: rgb("#0b5394"))
  content((4.6,1.9), box(width: 2.4cm, inset: 2pt, align(center, text(size: 8pt)[ANS entropy coding])))
  // Arrow
  line((6.0,1.9),(6.8,1.9), mark: (end: ">"))
  // JXL output box
  rect((6.8,1.5),(9.0,2.3), fill: rgb("#eafaf1"), stroke: rgb("#0b6e4f"))
  content((7.9,1.9), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[.jxl file])))
  // Reconstruct arrow below
  line((6.8,1.5),(6.8,0.8), mark: (end: ">"))
  line((6.8,0.8),(0.5,0.8), mark: (end: ">"))
  line((0.5,0.8),(0.5,3.0), mark: (end: ">"))
  content((3.5,0.4), box(width: 5.0cm, inset: 2pt, align(center, text(size: 8pt, style: "italic")[reconstruct: exact JPEG bytes])))
}))

=== The Chrome Drama

No section on JPEG XL is complete without the political story. Let us tell
it in order.

*2021–2022.* Chrome ships experimental JPEG XL support behind a flag
(`--enable-features=JXL`). The imaging community tests it enthusiastically.
Safari announces it will ship JPEG XL.

*January 2023.* Google files an intent-to-remove in the Chromium tracker.
The stated reasons: "not enough interest from the broader ecosystem" and
concerns about the memory safety of the 100,000-line C++ `libjxl` decoder.
The comment thread on that intent becomes one of the most-read and most
heated technical discussions in web standards history, with hundreds of
developers, photographers, imaging engineers, and even the JPEG XL authors
arguing for reversal. Mozilla cites the same memory-safety concern.

*March 2023.* Chrome 110 ships without JPEG XL support. Safari 17 ships
_with_ it, default-on.

*2023–2025.* The Mozilla Firefox team states it will reconsider once a
memory-safe Rust decoder exists. The `jxl-rs` project (a pure Rust
reimplementation of the JPEG XL decoder) begins development.

*January 2026.* Google announces it will re-add JPEG XL to Chrome using
`jxl-rs` rather than `libjxl`, directly addressing the memory-safety objection.

*February 10, 2026.* *Chrome 145* ships with JPEG XL support, gated behind a
flag (`chrome://flags/#enable-jxl-image-format`). This is behind-flag, not
default-on; users or enterprise deployments can enable it.

*H2 2026 (expected).* Default-on enablement in Chrome (and hence Chromium,
Edge, Opera, and other Chromium-based browsers) is expected, which would
lift JPEG XL's browser coverage from roughly 16% (Safari only) to approximately
85–90%.

#aside[
  The Chrome removal triggered a broader conversation about who controls web
  standards. When a single browser vendor, even one committed to open
  standards, can unilaterally remove a format that the JPEG Committee, the
  imaging industry, and browser rivals have endorsed, it raises a genuine
  question about the governance of the web platform. The decision (and its
  reversal) made many imaging engineers think more carefully about format
  diversity and the difference between "implemented" and "standardized."
]

=== JPEG XL by the Numbers

Relative to JPEG at equivalent quality (SSIMULACRA2):
- Photographic images: *~60% of JPEG's file size* (40% smaller).
- Non-photographic images (screenshots, illustrations): *~50% of PNG*.
- Lossless: *~10–20% smaller than PNG* on most inputs.
- Lossless JPEG transcoding: *78–84% of JPEG source* (16–22% reduction).

These numbers come from the 2025 Cloudinary benchmark and the
independent encode.su community benchmark, both of which use SSIMULACRA2
as the quality axis. At _high_ quality settings (where photographers work)
JPEG XL's advantage over AVIF is larger; at _low_ quality (web thumbnails,
social media) AVIF's advantage over older formats remains strong and the
JPEG XL delta shrinks.

#algo(
  name: "JPEG XL",
  year: "2022 (finalized ISO/IEC 18181)",
  authors: "Jyrki Alakuijala (Google/PIK), Jon Sneyers (Cloudinary/FUIF), JPEG Committee",
  aim: "Universal royalty-free image format: better than JPEG and PNG on every axis, with lossless JPEG transcoding",
  complexity: "VarDCT encode: moderate-to-high; decode: fast (jxl-rs). Modular: comparable to advanced PNG encoders",
  strengths: "Best lossy quality among standardized formats at high fidelity; best lossless on most images; lossless JPEG transcoding (unique); HDR/wide-color/12-bit native; true progressive; royalty-free",
  weaknesses: "Slow software encode at highest settings; browser support incomplete until H2 2026; small ecosystem of tools vs JPEG/PNG; minimal hardware decode as of early 2026",
  superseded: "Nothing supersedes it as of mid-2026; it is the newest standardized image codec",
)[
  JPEG XL is the most technically ambitious and complete still-image format
  ever standardized. Its political journey (removal from Chrome in 2023,
  re-addition in February 2026) has become a defining case study for how
  technical merit, patent politics, memory safety, and browser market power
  interact to determine what formats the web can use.
]

== Comparing the Four Formats

#block(width: 100%, breakable: true, above: 12pt, below: 12pt)[
  #text(weight: "bold", size: 9pt)[Modern image formats vs JPEG (approximate, photographic content, equivalent SSIMULACRA2 quality)]
  #v(4pt)
  #text(size: 8pt)[
  #table(
    columns: (auto, auto, auto, auto, 1fr, auto),
    inset: 5pt,
    align: (left, center, center, center, left, left),
    fill: (_, row) => if row == 0 { luma(230) } else { none },
    [*Format*], [*Size vs JPEG*], [*HDR/Wide*], [*Progressive*], [*Browser 2026*], [*License*],
    [JPEG (1992)], [100%], [No], [Yes (partial)], [100%], [Royalty-free],
    [WebP (2010)], [~70%], [No], [No], [~98%], [Royalty-free],
    [HEIC (2017)], [~50%], [Yes], [No], [Safari only], [HEVC royalties],
    [AVIF (2019)], [~50--55%], [Yes], [No], [~94%], [Royalty-free],
    [JPEG XL (2022)], [~60%], [Yes], [Yes], [~16% to 85--90%#super[\u{2020}]], [Royalty-free],
  )
  ]
]

#note[† JPEG XL: ~16% with Safari only as of early 2026; Chrome 145 (Feb 2026) added flag support; default-on and full Chromium ecosystem rollout expected H2 2026.]

The table above shows the key tension: AVIF is the safe, universal, royalty-free
choice for the web right now. JPEG XL is technically superior for high-fidelity
work and has the unique lossless JPEG transcoding feature, but its browser
footprint is still recovering from the Chrome removal. HEIC is an excellent
camera format imprisoned behind patent walls.

=== Choosing a Format in 2026

#keyidea[
  A practical decision tree for 2026:
  - *Legacy compatibility required?* Use JPEG. Still.
  - *Web delivery, maximum compatibility now?* AVIF with WebP fallback.
  - *High-fidelity archival or professional photography?* JPEG XL (especially for lossless JPEG transcoding).
  - *Apple device ecosystem (camera, Photos app)?* HEIC on-device, transcode to AVIF for web upload.
  - *Lossless web images (UI, screenshots)?* WebP lossless or AVIF; JPEG XL once Chrome defaults it.
]

== What Makes a Format Win? Lessons from the Wars

Technical quality, as we have seen, is not enough. JPEG 2000 was technically
superior to JPEG in 2000 and still has not won the web in 2026. Let us
inventory the non-technical factors that actually determine format adoption:

=== Royalty-Free Licensing Is Table Stakes

HEIC demonstrated this conclusively. A format that requires patent licenses
cannot become the universal web format, because browser vendors will not
pay royalties for a codec available to billions of users. The Alliance for
Open Media was explicitly created to avoid repeating the H.264 (and later
HEVC) licensing problem. Both AVIF and JPEG XL are royalty-free, which is
why they can realistically compete on the open web. HEIC is excellent; it
simply cannot compete there.

=== Decode Speed and Memory Safety Matter

The Chrome removal of JPEG XL in 2023 was not purely pretextual. The `libjxl`
decoder is 100,000 lines of complex multithreaded C++. In an era of
sophisticated memory-safety vulnerabilities (use-after-free, buffer overflows
in image decoders have historically been serious attack vectors), shipping that
decoder to billions of users is a genuine security commitment. The `jxl-rs`
Rust decoder addresses this directly: Rust's ownership model makes entire
categories of memory bugs structurally impossible.

#gomaths("Why Memory Safety Is a Security Issue in Codecs")[
  An image decoder is particularly attractive to attackers because it is
  invoked _automatically_ when a browser downloads any image tag on any web
  page. A malicious `.jxl` file crafted to trigger a buffer overflow in the
  decoder can potentially execute arbitrary code in the browser process with
  no user interaction. This class of bug is called a *code execution via
  media parsing* vulnerability. The Chrome security team's caution about the
  C++ `libjxl` decoder was technically well-founded: image parsing bugs
  have caused real CVEs in JPEG, PNG, GIF, and WebP decoders over the years.
  Rust's memory safety guarantees at the language level (no raw pointer
  arithmetic without `unsafe`, checked borrows) eliminate the largest class of
  these bugs.
]

=== Google's Conflicting Incentives

WebP and AVIF are both formats Google champions (VP8/On2 for WebP;
Alliance for Open Media with Google as a dominant member for AV1/AVIF). JPEG XL
came from JPEG Committee standardization, not a Google-led process. Google's
decision to remove JXL from Chrome while AVIF was gaining momentum was
read by many observers as competitive format preference under a technical
justification. The re-addition in 2026, using a Rust decoder rather than the
C++ reference, made the memory-safety argument clean and removed the
competitive advantage argument at the same time. Whatever the internal
deliberations, the outcome validated the memory-safety concern as a real one.

=== The Chicken-and-Egg Ecosystem Problem

A format needs browser support to motivate encoders, CMSes, and CDNs. Encoders
and CDNs need to adopt it for photographers to demand browser support. JPEG XL
suffered a particular version of this: browser support was removed _after_
tools had begun adopting it and _before_ the ecosystem was mature enough to
absorb the blow. The recovery in 2026 has required reconstructing the ecosystem
confidence that the removal damaged.

== Python: Measuring Format Trade-offs

Even without writing a JPEG XL or AVIF encoder from scratch, we can use
Python's Pillow library to measure real-world file sizes and compare formats
on an example image. Chapter 45 has no assigned `tinyzip` step, but the
following snippet is valuable for understanding the trade-offs.

#gopython("Pillow and the `save()` Method")[
  Pillow (the Python Imaging Library fork) is the standard Python library for
  reading and writing image files. `Image.open(path)` loads any supported
  format; `img.save(path, format=..., quality=...)` saves it in a new format.
  The `quality` parameter for JPEG and WebP ranges from 1 (worst) to 95
  (best; 100 is usually not recommended as it disables some optimizations).
  For AVIF, Pillow wraps libavif and accepts a `quality` parameter (0–100)
  and `speed` (0–10, trading encode time for compression).
]

```python
from pathlib import Path
from PIL import Image

def compare_formats(source: Path, quality: int = 75) -> dict[str, int]:
    """
    Save the source image in JPEG, WebP, and AVIF at the given quality level.
    Return a dict mapping format name to output file size in bytes.
    The source can be any image Pillow can open (JPEG, PNG, TIFF, etc.).
    """
    img = Image.open(source).convert("RGB")   # normalise to 8-bit RGB
    results: dict[str, int] = {}

    # JPEG baseline
    jpeg_path = source.with_suffix(".out.jpg")
    img.save(jpeg_path, format="JPEG", quality=quality)
    results["JPEG"] = jpeg_path.stat().st_size

    # WebP lossy
    webp_path = source.with_suffix(".out.webp")
    img.save(webp_path, format="WEBP", quality=quality)
    results["WebP"] = webp_path.stat().st_size

    # AVIF (requires Pillow >= 9.1 with libavif)
    try:
        avif_path = source.with_suffix(".out.avif")
        img.save(avif_path, format="AVIF", quality=quality, speed=6)
        results["AVIF"] = avif_path.stat().st_size
    except Exception as e:
        results["AVIF"] = -1   # libavif not available

    return results

def report(source: Path, quality: int = 75) -> None:
    sizes = compare_formats(source, quality)
    jpeg_size = sizes["JPEG"]
    print(f"Quality {quality} - source: {source.name}")
    print(f"  {'Format':<10} {'Bytes':>8}  {'vs JPEG':>8}")
    for fmt, sz in sizes.items():
        if sz < 0:
            print(f"  {fmt:<10} {'N/A':>8}")
        else:
            ratio = sz / jpeg_size
            print(f"  {fmt:<10} {sz:>8}  {ratio:>8.1%}")
```

Running this on a typical photographic image at quality 75 typically gives
output resembling:

```
Quality 75 - source: photo.jpg
  Format      Bytes   vs JPEG
  JPEG        95120   100.0%
  WebP        67450    70.9%
  AVIF        51230    53.9%
```

The exact numbers vary dramatically by image content. Images with large
uniform regions compress much further than complex natural scenes.

#checkpoint[
  Why does AVIF tend to produce smaller files than WebP at the same quality
  level, even though both use lossy block coding?
][
  AVIF inherits AV1's richer toolkit: larger variable block sizes (up to
  128×128 vs WebP's 16×16 macroblock limit), many more intra-prediction
  modes (capturing structure that WebP's simpler predictor misses), intra
  block copy for repeated patterns, and a tighter arithmetic entropy coder.
  All of these mean that after the transform and quantization step, AVIF
  sends fewer bits to the same perceptual quality destination.
]

== Animation and Beyond

All four formats support animated image sequences, though in very different ways:

- *WebP animated*: multiple VP8 frames in a RIFF container (RIFF is a simple
  "chunks of tagged data" file wrapper, the same one used by `.wav` audio),
  with per-frame delay values. Suitable for simple GIF replacements.
- *HEIC animated* (HEIFS): a proper video sequence using HEVC inter-prediction
  between frames. Dramatically more efficient than animated WebP for longer
  sequences.
- *AVIF animated*: AV1 intra frames (or inter frames for efficiency) in a
  HEIF sequence. Increasingly preferred over animated WebP for web use.
- *JPEG XL animated*: any number of frames, with optional inter-frame
  delta-coding. Full JPEG XL quality and lossless modes available per-frame.

For most current web use cases (replacing animated GIFs, short loops), AVIF
animated with careful encoding is the strongest option; for archival quality
animation, JPEG XL animated is the most capable.

== The Formats Not in This Chapter

Two important image formats are adjacent but belong elsewhere:

*JPEG 2000*, the wavelet-based 2000 successor, was covered in Chapter 43.
It remains in active use in digital cinema (DCI-P3 color, 48 frames/second
4K), medical imaging, and archival, but never penetrated the web.

*Learned / neural image codecs* (formats like BPG, VVC/H.266
intra coding, and fully neural codecs like those from Stable Diffusion's VAE
encoder) are covered in Chapters 57--58. They represent the next frontier:
instead of hand-designed DCT transforms, they use neural networks trained to
find the _optimal_ transform for a given distribution of images.

#misconception[
  "AVIF replaced JPEG XL's role, so JPEG XL is unnecessary."
][
  AVIF and JPEG XL are optimized for different points on the quality–use-case
  curve. AVIF excels at low-to-medium bitrates (web delivery, thumbnails,
  social media) where its video-codec inheritance is an advantage. JPEG XL
  excels at high fidelity (professional photography, archival, HDR), true
  progressive delivery, and lossless (including the unique lossless JPEG
  transcoding feature). The two formats are more complementary than
  competitive. Many large imaging platforms are already planning to serve
  AVIF for low-quality web delivery and JPEG XL for high-quality archival
  and progressive loading once Chrome defaults it on.
]

#takeaways((
  "WebP (2010) took VP8 intra coding and added 25–34% compression over JPEG; it is now universally supported but has been surpassed by AVIF and JPEG XL.",
  "HEIC places HEVC-coded images in a HEIF container; it is excellent (50% over JPEG, HDR-native) but blocked from the open web by HEVC's multi-pool patent licensing.",
  "AVIF (2019) uses AV1 intra coding in a HEIF container; it is royalty-free, has ~94% browser support, and is 45--50% smaller than JPEG, the safest choice for modern web images.",
  "JPEG XL (2022) is the only native-image (not video-derived) format; it uses variable-block VarDCT with a perceptual quantizer, ANS entropy coding, and uniquely can losslessly transcode JPEG files 16–22% smaller with perfect reversibility.",
  "Chrome removed JPEG XL in 2023 (memory-safety concerns), then re-added it in Chrome 145 (February 2026) with a Rust decoder (jxl-rs); default-on is expected H2 2026.",
  "Format adoption is driven not only by compression quality but by patent licensing (HEIC's fatal web flaw), decode safety (libjxl C++ vs jxl-rs Rust), ecosystem inertia (JPEG's trillion-file install base), and corporate distribution power (Google/Chrome for WebP and AVIF).",
  "No format has replaced JPEG on the open web as of mid-2026; AVIF is the strongest challenger for web delivery, JPEG XL for archival and professional photography.",
))

== Exercises

#exercise("45.1", 1)[
  A JPEG file is 200 KB. Based on the typical compression ratios described
  in this chapter, estimate the file size of an equivalent-quality image
  saved as: (a) WebP, (b) AVIF, (c) JPEG XL. Show your reasoning.
]
#solution("45.1")[
  Typical ratios: WebP ≈ 70% of JPEG, AVIF ≈ 50–55%, JPEG XL ≈ 60%.
  (a) WebP: 200 × 0.70 ≈ 140 KB.
  (b) AVIF: 200 × 0.52 ≈ 104 KB (using 52% midpoint).
  (c) JPEG XL: 200 × 0.60 ≈ 120 KB.
  Note: all three are approximate; actual results vary by image content.
]

#exercise("45.2", 1)[
  Explain in one or two sentences why HEIC achieves much better compression
  than JPEG, but is not the dominant format on the open web.
]
#solution("45.2")[
  HEIC uses HEVC, which has far more sophisticated prediction, larger block
  sizes, and better entropy coding than JPEG's fixed 8x8 DCT pipeline,
  achieving roughly 50% smaller files. However, HEVC is encumbered by multiple
  competing patent pools demanding royalties, which prevents Chrome and Firefox
  from shipping HEIC support. The format is effectively inaccessible on the open web.
]

#exercise("45.3", 2)[
  JPEG XL can losslessly transcode a JPEG to a smaller `.jxl` file and
  recover the original JPEG exactly. Explain *why* this is possible: what
  specific property of the JPEG encoding process makes perfect recovery
  achievable? Why can't AVIF do this for JPEG files?
]
#solution("45.3")[
  A JPEG file's image data is already quantized DCT coefficients stored as
  integers. JPEG XL can read those integer coefficients directly from the
  JPEG bitstream (bypassing any decoding to pixels), then re-encode them
  losslessly using ANS, a superior entropy coder. Because no re-quantization
  occurs (the quantization happened during the original JPEG encode and the
  integers are preserved exactly), the process is lossless and reversible.
  AVIF cannot do this because it would need to decode JPEG to pixels (losing
  the original quantized integers) and then re-quantize for AV1, which
  is a different quantizer, introducing additional lossy distortion and
  making exact recovery impossible.
]

#exercise("45.4", 2)[
  The Python snippet in this chapter uses Pillow to compare JPEG, WebP, and
  AVIF sizes. Extend the `compare_formats` function to also compute the
  PSNR between each output and the original source image. Use the formula
  $"PSNR" = 10 log_10 (255^2 \/ "MSE")$ where MSE is the mean squared error
  over all pixel values. Print PSNR alongside file size.
  (Hint: convert both images to numpy arrays and compute mean squared error.)
]
#solution("45.4")[
  ```python
  import numpy as np
  from PIL import Image
  from pathlib import Path
  import math

  def psnr(orig: Image.Image, compressed_path: Path) -> float:
      orig_arr  = np.array(orig, dtype=float)
      comp_arr  = np.array(Image.open(compressed_path).convert("RGB"), dtype=float)
      mse = np.mean((orig_arr - comp_arr) ** 2)
      if mse == 0:
          return float("inf")
      return 10 * math.log10(255**2 / mse)
  ```
  Add a call to `psnr(img, jpeg_path)` etc. after each save and print the result.
  Typical values: JPEG at quality 75 ≈ 37–40 dB; WebP at equivalent SSIM
  slightly higher (better use of bits); AVIF similarly 37–40 dB but with
  fewer visible artifacts.
]

#exercise("45.5", 2)[
  In the context of image format adoption, explain the "chicken-and-egg"
  problem. Why is the order in which browsers, encoders, CDNs, and CMS
  platforms adopt a format important? Use JPEG XL's 2023–2026 history as
  a concrete example.
]
#solution("45.5")[
  The chicken-and-egg problem: browsers won't adopt a format users can't serve;
  CDNs won't transcode to a format browsers don't support; photographers won't
  shoot or export in a format CDNs don't handle; tools (Photoshop, Lightroom)
  won't add support for a format photographers don't use. Each stakeholder
  waits for the others. JPEG XL: by 2023 Photoshop, Chrome (flag-only), and
  several CDNs had tentatively adopted it. Chrome's removal broke the chain:
  CDNs downgraded JPEG XL priority, and the ecosystem stalled. The 2026
  re-addition has to restart that chain: Chrome flag → CDN support → tool
  support → photographer adoption → default Chrome → universal use.
]

#exercise("45.6", 3)[
  This chapter describes JPEG XL's VarDCT mode as choosing block sizes
  adaptively from 2×2 to 64×64. Qualitatively explain why a large smooth
  gradient benefits from a 64×64 block rather than an 8×8 block, using what
  you know about DCT from Chapter 42. What is the cost of very large blocks
  in regions with fine detail or sharp edges?
]
#solution("45.6")[
  A 64×64 block in a smooth gradient produces very few non-zero DCT
  coefficients: the gradient is captured almost entirely by the DC (constant)
  term and the first one or two low-frequency AC terms. An 8×8 grid over the
  same area would produce 64 separate DCT blocks, each with overhead (headers,
  DC prediction residuals) and quantized coefficients. The large block
  eliminates that overhead and captures the whole structure in fewer numbers.
  Cost: at a sharp edge or fine texture, a 64×64 block is forced to represent
  a wide range of frequencies simultaneously. High-frequency components
  (encoding the sharp edge) that are quantized to zero produce ringing across
  the entire 64x64 area, much more visible than ringing confined to one 8x8
  block. That is why VarDCT uses small blocks in high-detail regions: the
  local scope limits artifact spread.
]

== Further Reading

- #link("https://arxiv.org/abs/1908.03565")[Alakuijala, J. et al. (2019). _JPEG XL Next-Generation Image Compression Architecture and Coding Tools_ (PIK/JPEG XL). arXiv:1908.03565.] The original research paper describing the merger of PIK and FUIF.

- #link("https://arxiv.org/abs/2506.05987")[Alakuijala, J. et al. (2025). _The JPEG XL Image Coding System: History, Features, Coding Tools, Design Rationale, and Future_. arXiv:2506.05987.] The comprehensive 2025 retrospective by the core JPEG XL team.

- #link("https://developers.google.com/speed/webp/docs/webp_study")[Google. _WebP Compression Study_.] The official Google study establishing the 25–34% JPEG size reduction claim.

- #link("https://cloudinary.com/blog/the-case-for-jpeg-xl")[Sneyers, J. (Cloudinary). _The Case for JPEG XL_.] Jon Sneyers's accessible overview of JPEG XL's unique capabilities.

- #link("https://jakearchibald.com/2020/avif-has-landed/")[Archibald, J. (2020). _AVIF has landed_.] A widely-read technical introduction to AVIF for web developers.

- #link("https://www.theregister.com/2026/01/14/google_rekindles_relationship_with_jilted/")[The Register (2026). _Google rekindles relationship with jilted JPEG XL_.] Coverage of the Chrome re-addition announcement.

- #link("https://aomedia.org")[Alliance for Open Media.] The governing body for AV1/AVIF; specifications and news at aomedia.org.

- #link("https://jpeg.org/jpegxl/")[JPEG Committee JPEG XL page.] Official landing page with white papers and the ISO standard reference.

#bridge[
  We have mapped the image format battlefield. Now we turn to the ear. In
  Chapter 46 we ask: how does the human auditory system actually work, and
  which parts of a sound signal can we throw away without the listener
  noticing? The science of psychoacoustics (critical bands, the threshold
  of hearing, simultaneous and temporal masking) is what audio codecs like
  MP3, AAC, and Opus exploit the same way image codecs exploit the limitations
  of the visual system. The next chapter builds the perceptual model that
  makes audio compression possible.
]
