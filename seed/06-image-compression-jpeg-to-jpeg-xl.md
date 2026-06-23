## Image Compression: JPEG to JPEG XL

Photographs are different from text. Text is symbolic and demands exact reconstruction; a photograph is a noisy sampling of a continuous light field, and the human eye is a lossy instrument that discards most of what arrives. Image compression exploits this twice over: it removes statistical redundancy (nearby pixels are correlated) *and* perceptual redundancy (the eye is insensitive to certain errors). The history below is largely a story of doing those two things ever more cleverly — and a surprising amount of patent politics.

### JPEG (1992): the transform-coding template

The Joint Photographic Experts Group, a joint ISO/CCITT committee, published its standard as **ITU-T Rec. T.81 / ISO 10918-1 in 1992**; the canonical explainer is **Gregory K. Wallace's 1991/1992 papers**. JPEG established a pipeline that essentially every later lossy codec still follows: **transform → quantize → entropy-code**.

A *transform* rewrites a block of pixels in a new basis where energy concentrates in a few coefficients. JPEG splits the image into **8×8 pixel blocks** and applies the **Discrete Cosine Transform (DCT)** to each: it expresses the block as a weighted sum of 64 fixed cosine patterns, from flat (the "DC" average) to fine checkerboards (high-frequency "AC" terms). Natural images are locally smooth, so most energy lands in the low-frequency coefficients while the high-frequency ones are near zero. This is *decorrelation*: the DCT approximates the optimal Karhunen–Loève transform for typical image statistics, but with a fixed, fast basis.

The lossy step is **quantization**: each coefficient is divided by an entry of an 8×8 *quantization table* and rounded to the nearest integer. High-frequency entries are large, so those coefficients are crushed — often to zero — because the eye barely notices their loss. The quality slider just scales this table. The integer coefficients are then **entropy-coded losslessly**: they are zig-zag scanned (low to high frequency), run-length encoded for the long zero runs, and packed with **Huffman coding** (an optional arithmetic coder existed but was patent-encumbered and rarely used). JPEG also typically converts RGB to **YCbCr** and *subsamples the chroma* (4:2:0), throwing away three-quarters of the color resolution, since the eye resolves luminance far better than color.

The famous cost is **blocking artifacts**. Because each 8×8 block is quantized independently, at low bitrates the reconstructed blocks no longer agree at their shared edges, producing visible tiling. Hard edges also produce **ringing** (Gibbs-like oscillations) because a sharp discontinuity needs high-frequency coefficients that quantization has discarded. These artifacts are the signature of block-DCT coding.

### JPEG 2000 (2000): wavelets, and a cautionary tale

The successor, **ISO 15444-1, finalized in 2000–2001**, replaced the block DCT with the **Discrete Wavelet Transform (DWT)** applied to the whole image. A wavelet transform decomposes the image into nested resolution bands — a coarse thumbnail plus successive layers of detail — using basis functions localized in *both* space and frequency. Because there are no independent blocks, **JPEG 2000 has no blocking artifacts**; at low bitrates it degrades into a soft blur rather than tiles. It also gained genuinely elegant features: **embedded/progressive coding** (the same bitstream decodes at any quality or resolution, truncatable anywhere), arithmetic-coded bitplanes (EBCOT), regions of interest, and a lossless mode via an integer wavelet.

It was technically superior and it **never won the web**. The reasons are instructive. It was far more **computationally and memory-hungry** than baseline JPEG — a real burden on 2000-era hardware. Browsers never shipped it. And while Part 1 was nominally royalty-free, lingering **patent uncertainty** around the broader standard chilled adoption. JPEG 2000 survives in niches that value its features and can pay the cost: digital cinema (DCI), medical and satellite imaging, and archival. It is the field's classic lesson that *better compression does not guarantee adoption* — ecosystem, licensing, and decode cost dominate.

### PNG (1996): the lossless niche

Photographs want lossy coding; logos, screenshots, line art, and anything needing exact pixels or transparency do not. **PNG (Portable Network Graphics, 1996)** filled that niche, created expressly to route around the **patent on GIF's LZW** compressor. PNG is fully lossless. It first applies a *prediction filter* per scanline — each pixel is predicted from its left/up/upper-left neighbors and only the small **residual** (prediction error) is stored, which decorrelates smooth gradients — then compresses the residuals with **DEFLATE**, the LZ77-plus-Huffman algorithm shared with zip and gzip. PNG added an **alpha channel** for true transparency, which GIF and JPEG lacked, and remains the default lossless web format.

### The modern format wars (2010–2026)

Every modern image codec since has been **a video codec turned into an image codec** — an intra-frame (single still) of a video standard wrapped in a container. This is efficient engineering (decades of video R&D for free) but it dragged image formats into video's patent and politics minefield.

- **WebP (Google, 2010)** wrapped the **VP8** video codec's intra coding. It beat JPEG modestly and added lossless and alpha modes, and Google's reach eventually forced broad browser support — but it was never a dramatic enough leap to displace JPEG.
- **HEIF/HEIC (2015)** is the MPEG container holding stills coded with **HEVC (H.265)**. **Apple adopted HEIC as the iPhone default in 2017**, which is why it dominates *device* storage — but HEVC's **heavy patent licensing** kept it off the open web; browsers won't touch a royalty-bearing format.
- **AVIF (2019)** is the intra frame of **AV1**, the codec from the **Alliance for Open Media** (Google, Netflix, Mozilla, Amazon, Apple, et al.) built explicitly to be **royalty-free**. It compresses very well, especially at low bitrates and on flat/synthetic content, and won fast browser support (Chrome 2020, Firefox 2021, Safari 2022); it now reaches **>95% of users**. Its weaknesses: slow encoding, a 12-bit depth cap, and limited resolution/progressive support inherited from a video design.

### JPEG XL (2021): a clean-sheet image codec

**JPEG XL (ISO/IEC 18181)** is the outlier — not a video frame, but a format designed for *images* from scratch, finalized **2021–2022**. It merged two research codecs: **Google's PIK** (led by **Jyrki Alakuijala**) and **Cloudinary's FUIF** (Jon Sneyers, descended from the lossless FLIF). Its distinctive pieces:

- **ANS entropy coding** — **Asymmetric Numeral Systems**, invented by **Jarek Duda (2007)** — achieves arithmetic-coding compression ratios at near-Huffman decode speed, the same breakthrough powering Zstandard. (Entropy coders are covered in their own section.)
- A perceptual **XYB color space** and an adaptive variable-block-size DCT plus a separate **Modular mode** for lossless and non-photographic content.
- **Royalty-free** licensing.
- True **progressive decoding**, HDR, wide gamut, and very high resolution.
- A killer feature: **lossless JPEG transcoding (~20% smaller)**. Because both JPEG and JPEG XL keep DCT coefficients and only differ in the lossless entropy step, an existing JPEG can be *recompressed and perfectly reversed* — letting the world's trillions of legacy JPEGs shrink with zero generational quality loss.

JPEG XL became the field's biggest *political* drama. Despite contributing code, **Google removed it from Chrome in early 2023** (Chrome 110), citing insufficient ecosystem interest and memory-safety concerns in the C++ decoder — a decision the imaging community loudly contested while Safari shipped it by default. Then it reversed: a memory-safe **Rust decoder (`jxl-rs`)** addressed the security objection, and **Chrome 145 (February 2026)** re-added JPEG XL, with default-on enablement expected across Chromium and Edge in the second half of 2026, potentially lifting browser support from ~16% to ~85–90%.

The current landscape is thus genuinely contested: **AVIF** (royalty-free, video-derived, ubiquitous, great at low bitrate) versus **JPEG XL** (royalty-free, image-native, superb at high fidelity, progressive, with legacy-JPEG transcoding), with HEIC entrenched on Apple devices and plain old JPEG still the universal floor. Looming over all of them are **learned (neural) image codecs**, which replace these hand-designed transforms with trained autoencoders optimized end-to-end for rate–distortion — covered in their own section.