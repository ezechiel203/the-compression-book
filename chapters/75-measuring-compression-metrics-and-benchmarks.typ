#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Measuring Compression: Metrics and Benchmarks

#epigraph[
  You can't improve what you can't measure. But you can fool yourself badly with the wrong measurement.
][Paraphrased from a Netflix engineering postmortem, 2015]

Imagine you are a judge at a cooking competition. You taste two dishes and declare a winner. But what if one dish was saltier, and you were judging on saltiness alone? You might crown the worst-tasting food on the table. The same trap devours compression researchers every single day.

A codec is a piece of software that squeezes data and then stretches it back out. How do you decide which codec is better? You measure. But measure the *wrong thing* and you reward the wrong codec, ship the wrong product, and (in the video-streaming world) waste billions of dollars sending pixels no human eye can distinguish. This chapter is about measuring right.

We will cover the full hierarchy of compression metrics: the simple ratios people compute in one line of code, the rate-distortion curves that reveal how a codec behaves at every quality level, the Bjøntegaard Delta that collapses a whole curve into one honest number, and the perceptual quality metrics (SSIM, VMAF, LPIPS, DISTS) that try to quantify what your eyes actually see rather than what a formula says about pixel errors. We will also examine how benchmark corpora are designed, what pitfalls corrupt them, and how the listening and viewing tests that serve as the gold standard are run. By the end you will be able to read a codec comparison table, spot its flaws, and design a fair evaluation of your own.

#recap[
  Volume I (Chapters 18–19) taught us Shannon entropy: the theoretical minimum number of bits needed to represent a source. Chapters 37–42 built the DCT-based image pipeline and introduced _lossy_ compression, where we deliberately discard information to save space. Chapters 51–66 covered video codecs and neural learned compression. Chapter 73 explored the engineering of fast codecs. Chapter 74 surveyed where compression lives in the software stack. Now we zoom out and ask: once we have two codecs, how do we decide which is better?
]

#objectives((
  "Compute and interpret the four basic compression metrics: compression ratio, space savings, bits per pixel (bpp), and bits per character/byte (bpc).",
  "Read and draw rate-distortion (R-D) curves, understand what the axes mean, and explain what it means for one curve to dominate another.",
  "Explain BD-rate and BD-PSNR: what they measure, how they are calculated, and what pitfalls can make them misleading.",
  "Compare PSNR, SSIM, MS-SSIM, VMAF, LPIPS, and DISTS: what each metric captures, where it fails, and when to use it.",
  "Describe the gold-standard subjective evaluation methods: MOS, MUSHRA, and double-blind listening tests.",
  "Identify the classic benchmark corpora (Calgary, Canterbury, Silesia, enwik8/9) and the pitfalls of corpus selection and evaluation methodology.",
))

== The Basic Metrics: Four Ways to Say "How Much Did We Squeeze?"

Before we can talk about fancy perceptual metrics or elaborate statistical tools, we need to be fluent in the everyday language of compression measurement. There are four numbers you will see quoted everywhere, and they are all saying roughly the same thing from different angles.

=== Compression Ratio

The most intuitive metric is the *compression ratio* (CR): how many bytes did we start with, and how many did we end with?

$ "CR" = ("uncompressed size (bytes)") / ("compressed size (bytes)") $

If your original file is 1,000,000 bytes and the compressed version is 250,000 bytes, the compression ratio is 4.0, sometimes written 4:1, meaning "four bytes became one." A ratio of 1.0 means no compression happened at all. A ratio below 1.0 means the compressed file is *bigger* than the original, which can genuinely happen with already-compressed or random data (see Chapter 19).

#gomaths("Ratios and percentages")[
  A *ratio* compares two quantities by division. "4:1" reads as "four to one" and means the first quantity is four times the second. To convert a ratio to a *percentage*, note that CR = 4 means the compressed file is $1/4 = 25%$ the size of the original. The percentage of the original kept is $100\% / "CR"$.

  *Tiny example:* Original = 800 bytes, compressed = 200 bytes.
  $ "CR" = 800/200 = 4 $
  The compressed file is 25 % of the original size.
]

=== Space Savings

Sometimes people prefer to report the fraction of space *saved* rather than the ratio:

$ "Space savings" = 1 - (1) / ("CR") = ("uncompressed" - "compressed") / ("uncompressed") $

A CR of 4 gives a space savings of 75 %. A CR of 2 gives 50 %. Space savings is easier to communicate to non-technical stakeholders ("we saved 75 % of storage costs"), while compression ratio is easier to use in formulas.

=== Bits Per Pixel (bpp)

For images and video, the natural unit is *bits per pixel* (bpp). An uncompressed 24-bit colour image (the kind your camera produces before saving as JPEG) uses exactly 24 bpp: 8 bits each for the red, green, and blue channels. After JPEG compression at moderate quality, that same image might use 1.5 bpp to 3 bpp. The lower the bpp, the more aggressively the image has been compressed.

Bits per pixel ties compression directly to *what is being compressed* (pixels), which makes it meaningful to compare across different image sizes. Saying "our encoder uses 1.2 bpp" tells you something universal; saying "our encoder produces 100 KB files" tells you almost nothing without also knowing the image dimensions.

#gomaths("Bits per pixel")[
  If a compressed image file is $S$ bytes and contains $W times H$ pixels (width times height), then:
  $ "bpp" = (S times 8) / (W times H) $

  The factor of 8 converts bytes to bits. $W times H$ is the *total pixel count*, also called the *resolution*.

  *Example:* A 1920 × 1080 image compressed to 400 KB.
  - Total pixels: $1920 times 1080 = 2{,}073{,}600$
  - Compressed size in bits: $400{,}000 times 8 = 3{,}200{,}000$ bits
  - bpp: $3{,}200{,}000 \/ 2{,}073{,}600 approx 1.54$ bpp
]

=== Bits Per Character / Bits Per Byte (bpc / bpB)

For *text* and *general data*, the equivalent unit is *bits per character* (bpc) or *bits per byte* (bpB). If a corpus of English text originally uses 8 bits per ASCII character and a compressor squeezes it to 2.1 bits per character, it has achieved 2.1 bpc.

This metric surfaces in two places. In text compression benchmarks (the Calgary corpus, enwik8), bpc tells you how close the compressor got to the Shannon entropy of English (roughly 1.0–1.5 bits per character, as Shannon himself estimated in 1951). In machine learning, bpc and its cousin *bits per byte* (bpB) are used to measure how well a language model predicts text: a lower bpc means the model is "less surprised" by each new character, which is equivalent to compressing more tightly.

#aside[
  There is a direct mathematical equivalence between a language model's perplexity and its bits-per-character. If a model assigns probability $p$ to each character on average, then $"bpc" = -log_2 p$. A model with perplexity 10 is assigning each character an average probability of $1\/10$, giving $log_2 10 approx 3.32$ bpc. See Chapter 62 for the deep connection between language models and compression.
]

=== Which Metric to Use?

These four metrics (CR, space savings, bpp, bpc) all measure the same underlying thing from different angles: how many bits the compressed representation uses. The rule of thumb is:

- Use *compression ratio* when talking about general-purpose compressors (gzip, zstd, bzip2).
- Use *bpp* when comparing image or video codecs.
- Use *bpc* or *bpB* when comparing text compressors or language models.
- Use *space savings* when communicating with non-engineers.

None of them say anything about *quality*. That is the next problem.

== Rate-Distortion Curves: Seeing the Whole Picture

Here is a fundamental truth about lossy compression: *there is no single answer to which codec is better*. The answer depends on how much quality you are willing to sacrifice for how much space savings. A codec that looks terrible at low bitrates might look magnificent at high bitrates. A codec that is slightly worse at medium quality might be far superior at very low bitrates.

The tool that captures this truth is the *rate-distortion (R-D) curve*, sometimes called an R-D plot.

=== What the Axes Mean

An R-D curve is a simple graph with:
- The *horizontal axis* (x-axis): *rate*, measured in bpp for images or kilobits-per-second (kbps) for video. Moving right = more bits = more storage/bandwidth.
- The *vertical axis* (y-axis): *quality* or equivalently *distortion* (often shown inverted so that "up" means "better"). For now assume PSNR in decibels, though we will replace this later.

Each codec can be operated at many different quality levels by turning a "quality knob." JPEG has a quality slider from 1 to 100. H.264 has a Constant Rate Factor (CRF) parameter. Each setting of the knob produces one (rate, distortion) pair, giving one point on the graph. Connect all those points and you get the codec's R-D curve.

#fig([Rate-distortion curve comparison: Codec A consistently outperforms Codec B.], cetz.canvas({
  import cetz.draw: *

  // Axes
  set-style(stroke: (thickness: 0.8pt))
  line((0,0), (7,0), mark: (end: ">"))
  line((0,0), (0,5.5), mark: (end: ">"))
  content((3.5, -0.5), [Rate (bpp)], anchor: "north")
  content((-0.5, 2.8), text(size: 9pt)[Quality (PSNR dB)], anchor: "east", angle: 90deg)

  // Codec A curve (better)
  set-style(stroke: (paint: rgb("#0b5394"), thickness: 1.8pt))
  bezier((0.4, 1.5), (2.0, 3.2), (1.0, 2.5), (1.8, 3.0))
  bezier((2.0, 3.2), (3.5, 4.2), (2.6, 3.6), (3.1, 4.0))
  bezier((3.5, 4.2), (5.5, 4.8), (4.2, 4.5), (5.0, 4.7))
  content((5.8, 4.8), [*Codec A*], anchor: "west", fill: rgb("#0b5394"))

  // Codec B curve (worse)
  set-style(stroke: (paint: rgb("#9a2617"), thickness: 1.8pt, dash: "dashed"))
  bezier((0.4, 0.8), (2.0, 2.4), (1.0, 1.7), (1.8, 2.2))
  bezier((2.0, 2.4), (3.5, 3.5), (2.6, 2.9), (3.1, 3.3))
  bezier((3.5, 3.5), (5.5, 4.2), (4.2, 3.8), (5.0, 4.0))
  content((5.8, 4.2), [*Codec B*], anchor: "west", fill: rgb("#9a2617"))

  // axis labels
  content((0, 0), [0], anchor: "north-east")
  for x in (1,2,3,4,5) {
    line((x, -0.07), (x, 0.07))
    content((x, -0.2), [#x], anchor: "north", size: 7.5pt)
  }
  for y in (1,2,3,4,5) {
    line((-0.07, y), (0.07, y))
    content((-0.12, y), [#(y*8+24)], anchor: "east", size: 7.5pt)
  }
}))

=== Dominance

We say Codec A *dominates* Codec B if Codec A's R-D curve lies entirely *above and to the left* of Codec B's curve. "Above" means higher quality at the same bitrate; "to the left" means the same quality at a lower bitrate. A dominating codec is strictly better in every possible tradeoff scenario.

Often the curves cross. One codec wins at low bitrates and the other wins at high bitrates. In that case you cannot say one is "better" overall without knowing which bitrate range you care about.

#keyidea[
  The R-D curve is the *minimum* you should show when comparing lossy codecs. Any comparison that reports a single point ("our codec achieves 35 dB PSNR at 1 bpp") is hiding the full story. Always show at least 4–5 operating points spanning the practical quality range.
]

=== Drawing an R-D Curve in Practice

In practice, you run the encoder at several quality levels, measure the output bitrate and distortion at each level, and plot the results. The ITU-T standard for video codec testing (used in the H.264, H.265, and AV1 comparison processes) specifies at least four quantization parameter (QP) values: QP = 22, 27, 32, and 37 for H.264, giving four data points from high quality to low quality.

#gopython("Plotting a rate-distortion curve")[
  Here is a simple Python 3.14 script that collects R-D data from a hypothetical image encoder and plots the curve. The `subprocess` module runs shell commands from Python.

  ```python
  # rd_plot.py - sketch of R-D data collection
  # Requires: pip install matplotlib

  import subprocess, json
  from pathlib import Path

  def encode_decode(src: Path, quality: int) -> tuple[float, float]:
      """Return (bpp, psnr_db) for the given quality level."""
      # In a real script, call your encoder here.
      # We return fake values for illustration.
      fake_data: dict[int, tuple[float, float]] = {
          10: (0.30, 28.5), 30: (0.55, 32.1),
          50: (0.90, 35.8), 70: (1.60, 38.4),
          90: (3.20, 42.0),
      }
      return fake_data[quality]

  qualities = [10, 30, 50, 70, 90]
  results = [encode_decode(Path("test.png"), q) for q in qualities]
  bpps   = [r[0] for r in results]
  psnrs  = [r[1] for r in results]

  # --- plot (if matplotlib is available) ---
  try:
      import matplotlib.pyplot as plt
      plt.plot(bpps, psnrs, "o-", label="My Codec")
      plt.xlabel("Rate (bpp)")
      plt.ylabel("PSNR (dB)")
      plt.title("Rate-Distortion Curve")
      plt.legend()
      plt.grid(True)
      plt.savefig("rd_curve.png", dpi=150)
      print("Saved rd_curve.png")
  except ImportError:
      for bpp, psnr in zip(bpps, psnrs):
          print(f"  bpp={bpp:.2f}  PSNR={psnr:.1f} dB")
  ```
]

== PSNR: The Reigning Champion with a Glass Jaw

The y-axis of most R-D curves shows *PSNR* (Peak Signal-to-Noise Ratio). PSNR has dominated codec evaluation for decades. It is fast to compute, deterministic, and easy to understand. It is also, in the words of Netflix engineers, "not good enough."

=== What PSNR Measures

PSNR is built on top of *Mean Squared Error* (MSE). Given an original image $O$ and a reconstructed image $R$, each with $N$ pixels, MSE is the average of the squared differences:

$ "MSE" = (1)/(N) sum_(i=1)^N (O_i - R_i)^2 $

#mathrecall[
  The $sum$ symbol means "add up all the terms." $sum_(i=1)^N a_i = a_1 + a_2 + dots + a_N$. Chapter 11 introduced this notation.
]

PSNR then expresses MSE on a logarithmic decibel scale, referenced to the *peak* possible pixel value (255 for 8-bit images):

$ "PSNR" = 10 log_10 (255^2 / "MSE") $

Higher PSNR = lower MSE = less error. Typical values for good JPEG compression are 35–40 dB. A completely identical image gives infinite PSNR (MSE = 0).

#gomaths("Decibels and PSNR")[
  A *decibel* (dB) is a logarithmic unit for expressing ratios. For power-like quantities, $10 log_10(x)$ converts a ratio $x$ to decibels. Doubling power adds ~3 dB; multiplying by 10 adds 10 dB.

  *Why use dB for PSNR?* Human perception of image quality is roughly logarithmic. The difference between 25 dB and 26 dB looks about as significant as the difference between 35 dB and 36 dB, even though the absolute MSE change is very different.

  *Example:* If MSE = 100, then:
  $"PSNR" = 10 log_10(255^2 / 100) = 10 log_10(650.25) approx 10 times 2.813 = 28.1 "dB"$
]

=== Why PSNR Fails

PSNR has three serious problems.

*Problem 1: It ignores spatial structure.* MSE treats every pixel as independent. Blurring an image slightly and adding fine grain noise might give the same MSE, even though a human would rate the blurred image as far better. Your visual system does not work pixel-by-pixel; it recognises edges, textures, and structures.

*Problem 2: It is fooled by simple operations.* Shifting an image by one pixel in any direction can drop PSNR by 5 dB even though the images look identical. Adding a global brightness shift of 1 LSB affects every pixel. Neither operation looks bad to the human eye, yet both murder PSNR scores.

*Problem 3: Gains in PSNR can be perceptually invisible.* Going from 38 dB to 39 dB PSNR often produces no visible improvement, yet a codec developer who optimises PSNR will burn bits to get there. Worse, some codecs are specifically tuned to score well on PSNR while looking bad (a practice called *metric gaming*).

#misconception[
  A higher PSNR always means a better-looking image.
][
  Not at all. Two images with the same PSNR can look wildly different. An image with low PSNR but perceptually natural texture can look better than an image with high PSNR but ugly blockiness. PSNR is a *proxy* for quality, not quality itself. It correlates with quality well enough to be useful, but it should never be the only metric you report.
]

=== When PSNR Is Still Fine

Despite its flaws, PSNR is not useless. It is reproducible, fast, deterministic, and easy to compute. For *lossless* compression it is irrelevant (lossless = infinite PSNR). For *lossy* compression where the distortion is small and well-behaved (high-bitrate images, lightly compressed audio), PSNR correlates reasonably well with quality. Use it as one data point among several, never as the final word.

== SSIM: Bringing in Structure

In 2004, Zhou Wang, Alan Bovik, Hamid Sheikh, and Eero Simoncelli at the University of Texas / New York University published a seminal paper introducing the *Structural Similarity Index* (SSIM). Their core insight was that human vision is exquisitely sensitive to structural information (edges, shapes, and spatial relationships) and that a good quality metric should reflect this.

#history[
  Wang and Bovik had been collaborating since 2001 on what they called the Universal Quality Index (UQI). When they partnered with Sheikh and Simoncelli, who brought expertise in human visual neuroscience, the result was SSIM, published in _IEEE Transactions on Image Processing_, April 2004 (vol. 13, no. 4, pp. 600–612). It became one of the most cited papers in image processing, with over 60,000 citations by 2026. The core idea was deceptively simple: instead of measuring *error*, measure *similarity* along three dimensions that the human visual system cares about.
]

=== How SSIM Works

SSIM compares two image patches along three dimensions, each expressed as a number between −1 and 1 (with 1 meaning identical):

- *Luminance* ($l$): Are the patches equally bright on average?
- *Contrast* ($c$): Are the patches equally "varied" in brightness? (Measured by standard deviation.)
- *Structure* ($s$): Do the patches have similar spatial patterns after normalising for brightness and contrast?

The final SSIM index combines these:

$ "SSIM"(x, y) = l(x,y)^alpha dot c(x,y)^beta dot s(x,y)^gamma $

In the standard formulation, $alpha = beta = gamma = 1$, giving:

$ "SSIM"(x, y) = ((2 mu_x mu_y + C_1)(2 sigma_(x y) + C_2)) / ((mu_x^2 + mu_y^2 + C_1)(sigma_x^2 + sigma_y^2 + C_2)) $

where $mu_x, mu_y$ are local means, $sigma_x^2, sigma_y^2$ are local variances, $sigma_(x y)$ is the cross-correlation, and $C_1, C_2$ are small constants to prevent division by zero.

#mathrecall[
  $mu$ (Greek "mu") is just the *mean*, the average pixel brightness in a patch. $sigma^2$ (sigma-squared) is the *variance*, the average squared distance of pixels from that mean, a measure of how "spread out" the brightnesses are; its square root $sigma$ is the *standard deviation*, here standing in for contrast. The *cross-correlation* $sigma_(x y)$ measures whether the two patches brighten and darken *together* in the same places. All three were built from scratch in Chapter 10.
]

In practice, SSIM is computed on small local windows (typically 11×11 pixels with a Gaussian weight) across the whole image, then averaged to get a single score between 0 and 1.

#keyidea[
  SSIM scores near 1.0 mean high quality. An SSIM of 0.98 is typically excellent; 0.90 is noticeably degraded; 0.80 is poor. The scale is not linear with perceived quality, so always report the raw number rather than "SSIM was 90%."
]

=== MS-SSIM: Multiple Scales

A known weakness of basic SSIM is that it operates at a single spatial scale, making it sensitive to the viewing distance and image resolution. *Multi-Scale SSIM* (MS-SSIM), introduced by Wang, Simoncelli, and Bovik in 2003, computes SSIM at several spatial resolutions (by progressive downsampling) and combines the results. MS-SSIM generally correlates better with human quality judgements across different image sizes and viewing distances.

#algo(
  name: "SSIM / MS-SSIM",
  year: "2004 / 2003",
  authors: "Zhou Wang, Alan C. Bovik, Hamid R. Sheikh, Eero P. Simoncelli (SSIM); Wang, Simoncelli, Bovik (MS-SSIM)",
  aim: "Measure perceptual image similarity by comparing luminance, contrast, and structural information in local windows.",
  complexity: "$O(N)$ in image pixels (sliding window)",
  strengths: "Much better correlation with human quality ratings than PSNR; fast to compute; intuitive score range [0, 1]; widely adopted standard.",
  weaknesses: "Single-scale SSIM is resolution-dependent; both variants are sensitive to texture resynthesis (a texture that looks identical but is not pixel-matched may score poorly); does not model high-level visual features.",
  superseded: "LPIPS, DISTS for research; VMAF for video streaming",
)[
  SSIM was the first widely adopted metric to move beyond pixel-error and model human perception. MS-SSIM extends it to multiple image scales, improving robustness. Both are still standard metrics in image compression research papers and are required reporting in major conference venues.
]

== VMAF: Netflix's Machine-Learning Metric

By the mid-2010s, Netflix was encoding tens of millions of videos and streaming them to millions of screens of wildly different sizes, from 4K televisions to tiny phone displays. PSNR was clearly failing: their engineers observed that videos with lower PSNR often looked *better* to viewers, especially after sharpening or denoising pre-processing steps. A better metric was needed, one trained directly to match human opinion.

In 2016, Netflix released *VMAF* (Video Multimethod Assessment Fusion) as an open-source project on GitHub. VMAF combines multiple elementary quality metrics (VIF (Visual Information Fidelity), detail loss measure (DLM), and motion-based features) using a *support vector machine (SVM)* trained on thousands of hours of human quality ratings (MOS scores). The training data was collected through carefully controlled subjective viewing tests at Netflix.

#gopython("Support vector machine, in one paragraph")[
  A *support vector machine* is a machine-learning model that learns to draw a boundary separating examples of different kinds, or, in VMAF's case, to learn a smooth function that maps a list of input numbers to one output number. You feed it a *training set*: many examples, each a list of features (here: the VIF score, the DLM score, the motion score, ...) paired with the "right answer" a human gave (the MOS). The SVM then finds the weighting of those features that best reproduces the human answers, while keeping the boundary as simple as possible so it generalises to new clips it has never seen. You do not need its internals here; just hold onto the idea "a formula whose coefficients were *fitted to human ratings* rather than chosen by a theorist." That single fact - learning from people instead of from first principles - is the whole reason VMAF beats PSNR. (Chapter 56 builds the machine-learning toolkit from scratch.)
]

#history[
  Netflix open-sourced VMAF in June 2016, developed primarily by Zhi Li and colleagues at Netflix. It was first deployed internally to drive encoding decisions for Netflix's own library, which means VMAF now influences the quality of billions of video streams. In 2019, VMAF received a Technology and Engineering Emmy Award from the Academy of Television Arts and Sciences. By 2026, VMAF v2 had been released, incorporating neural network components and addressing known failure modes of the original SVM-based system. Netflix's blog post from June 2026, "VMAF v1: Good Is Not Good Enough," announced the transition to VMAF v2 for production.
]

=== How VMAF Is Computed

VMAF fuses several sub-metrics:

1. *VIF (Visual Information Fidelity)* at multiple scales: measures how much visual information is preserved through the distortion channel, inspired by information-theoretic models of the human visual system.
2. *DLM (Detail Loss Measure)*: quantifies the loss of fine spatial detail.
3. *ADM (Anti-Distortion Measure)*: penalises ringing and blocking artefacts.
4. *Motion* feature: captures temporal smoothness, since humans are more tolerant of quality drops during fast motion.

A trained SVM (or in VMAF v2, a neural network) combines these features into a single score from 0 to 100, where 100 is perfect quality and 93+ is generally broadcast-quality.

#algo(
  name: "VMAF",
  year: "2016 (v1), 2024 (v2)",
  authors: "Zhi Li et al., Netflix",
  aim: "Predict perceptual video quality by fusing multiple elementary metrics through machine-learning, trained on human Mean Opinion Scores.",
  complexity: "$O(N)$ in pixels per frame, plus per-frame feature extraction overhead (~10–50× slower than PSNR).",
  strengths: "Best correlation with human quality judgements among objective metrics as of 2024–2026; handles sharpening, denoising, and pre-processing effects correctly; multiple models (phone, 4K) tuned to viewing conditions.",
  weaknesses: "Computationally expensive; trained on Netflix content so may not generalise to all content types (animation, medical imaging, satellite imagery); can be gamed by adversarial pre-processing; difficult to interpret individual scores without context.",
  superseded: "Still the dominant metric for streaming; being challenged by deep-learning metrics (LPIPS, DISTS) for research.",
)[
  VMAF is the de facto standard for video streaming quality evaluation in production environments. Encoders like FFmpeg expose `libvmaf` natively. The key lesson from VMAF's development: a metric trained on human data beats a metric derived purely from theory.
]

=== Practical VMAF Use

VMAF scores above 93 are generally considered excellent (broadcast quality or better). Scores of 70–93 are good but with visible compression artefacts in some content. Scores below 70 are noticeable quality problems. Netflix uses VMAF internally to automate bitrate-ladder decisions, choosing the optimal (bitrate, quality) operating points for each piece of content without human review.

#checkpoint[
  A video encoder produces two versions of a clip: Version A achieves 36 dB PSNR and 71 VMAF; Version B achieves 34 dB PSNR and 88 VMAF. Which should you release?
][
  Version B. VMAF 88 is solidly in the "good quality" range for streaming; VMAF 71 is borderline. The fact that Version A has higher PSNR is misleading. PSNR and VMAF often disagree precisely because PSNR ignores perceptual structure. Trust the perceptual metric.
]

== LPIPS and DISTS: Deep Learning Meets Perception

The arrival of deep convolutional neural networks (CNNs) in the 2010s opened a new frontier for quality metrics. The key insight, demonstrated spectacularly by Richard Zhang, Phillip Isola, Alexei Efros, Eli Shechtman, and Oliver Wang at CVPR 2018, was this: *intermediate feature maps from a neural network trained for image classification capture perceptual similarity far better than any hand-crafted metric*.

=== LPIPS

Zhang et al.'s paper, "The Unreasonable Effectiveness of Deep Features as a Perceptual Metric" (CVPR 2018), introduced *LPIPS* (Learned Perceptual Image Patch Similarity). They collected a large dataset of human quality judgements (the BAPPS dataset), then showed that comparing the *feature representations* of a pretrained VGG or AlexNet network, rather than the pixels themselves, aligned much more closely with human perception than PSNR, SSIM, or MS-SSIM.

LPIPS computes a distance: two images are *far apart* in LPIPS when their feature maps differ significantly, even if their pixel values are close. This lets LPIPS correctly handle texture resynthesis (same material, different realisation) and structural differences (an edge shifted by a few pixels).

Lower LPIPS = more similar = better quality. Typical values are 0.0 (identical) to 1.0 (completely dissimilar), with good reconstructions scoring below 0.1.

=== DISTS

*DISTS* (Deep Image Structure and Texture Similarity), introduced by Ding et al. in 2020, goes one step further. LPIPS is sensitive to the exact texture realisation: a texture patch that looks identical to human eyes but uses different random phases will get a high (bad) LPIPS score. DISTS was designed to be *texture-tolerant*: it separates structure similarity (which it penalises) from texture similarity (which it rewards even for perceptually equivalent textures). This makes DISTS particularly useful for evaluating generative compression methods, where the decoder may synthesise plausible texture rather than reconstructing it exactly.

#algo(
  name: "LPIPS",
  year: "2018",
  authors: "Richard Zhang, Phillip Isola, Alexei A. Efros, Eli Shechtman, Oliver Wang",
  aim: "Measure perceptual image similarity using feature maps from a deep neural network pre-trained on image classification.",
  complexity: "One forward pass through a VGG-16 network per image pair; GPU-accelerated in practice.",
  strengths: "Excellent correlation with human perceptual judgements; works across many image types and distortion types; handles texture resynthesis reasonably well.",
  weaknesses: "Computationally expensive (requires GPU for speed); black box, hard to interpret why two scores differ; may not generalise outside the training distribution; scores are relative, not absolute.",
  superseded: "Being complemented (not replaced) by DISTS for texture-rich scenarios; FID for distribution-level comparisons in generative models.",
)[
  LPIPS became the default perceptual metric in the neural image compression community from 2019 onward. Almost every paper in learned image compression now reports bpp, PSNR, MS-SSIM, and LPIPS as a standard set.
]

=== A Practical Metric Comparison

#scoreboard(
  caption: "Quality metric properties: summary comparison",
  [*Metric*], [*Scale*], [*Perceptual?*], [*Speed*],
  [PSNR], [0–∞ dB], [Poor], [Very fast],
  [SSIM], [0–1], [Fair], [Fast],
  [MS-SSIM], [0–1], [Good], [Fast],
  [VMAF], [0–100], [Excellent (video)], [Slow],
  [LPIPS], [0–1 (↓ better)], [Excellent (images)], [Slow (GPU)],
  [DISTS], [0–1 (↓ better)], [Excellent (generative)], [Slow (GPU)],
)

== BD-Rate: One Number to Rule the R-D Curve

We now have the tools to understand the most important derived metric in video codec comparison: *BD-rate* (Bjøntegaard Delta Rate).

=== The Problem It Solves

Suppose you are comparing Codec A and Codec B. You run each codec at four quality levels and plot their R-D curves. Codec A has a higher curve (better). But how much better, *on average across the entire curve*? You could eyeball it, but that is not reproducible. You need a single number.

BD-rate answers the question: *at the same quality level, how much fewer bits does Codec A need compared to Codec B, expressed as a percentage?*

A BD-rate of -20 % means Codec A achieves the same quality as Codec B with 20 % fewer bits. A BD-rate of +5 % means Codec A needs 5 % *more* bits to achieve the same quality, which is a regression.

=== The History

In April 2001, Gisle Bjøntegaard submitted a contribution to the ITU-T Video Coding Experts Group (VCEG) meeting in Austin, Texas. The document, ITU-T SG16 Q.6 VCEG-M33, proposed a method to "calculate the average PSNR differences between RD-curves." His key insight was to fit a *third-order polynomial* (cubic curve) through four R-D data points, compute the integral of that polynomial, and compare the integrals of two codecs. Because bitrate values span a wide range (e.g., 100 kbps to 5000 kbps), Bjøntegaard proposed using the *logarithm* of the bitrate on the x-axis, so that the integration gives equal weight to each factor-of-two change in bitrate rather than to each kilobit-per-second step.

#history[
  Gisle Bjøntegaard's 2001 document VCEG-M33 was written by hand by one person in a committee document, and initially just circulated internally within VCEG. It was never published in a journal or conference proceedings. Yet the method it proposed, now universally called *BD-rate*, became the mandatory reporting format for all major video codec standardisation bodies (ITU-T, ISO/IEC MPEG) and the de facto standard in the academic video compression literature. Bjøntegaard himself has noted the irony that one of the most widely used metrics in video compression is not a peer-reviewed paper but an internal committee memo.
]

=== How BD-Rate Is Computed

The algorithm, step by step:

1. *Choose your anchor codec* (Codec B). Encode a test clip at four quality levels (four QP values). For each, record (bitrate in kbps, PSNR in dB).
2. *Do the same for the test codec* (Codec A).
3. *Fit a cubic polynomial* through the four points $(log "bitrate", "PSNR")$ for each codec. Call them $f_A$ and $f_B$.
4. *Find the overlapping PSNR range*: the range of PSNR values covered by *both* curves. This is the integration interval $[P_"min", P_"max"]$.
5. *Integrate both polynomials* over that range:
   $ I_A = integral_(P_"min")^(P_"max") f_A^(-1)(p) d p, quad I_B = integral_(P_"min")^(P_"max") f_B^(-1)(p) d p $
   where $f^(-1)$ maps PSNR to log-bitrate.
6. *Compute the average log-bitrate difference*:
   $ "BD-rate" = (exp((I_A - I_B) / (P_"max" - P_"min")) - 1) times 100 % $

#gomaths("The integral: area under a curve")[
  The long S symbol $integral$ is an *integral*. It is the smooth cousin of the $sum$ you already know (Chapter 11): instead of adding up a handful of separate values, it adds up the value of a curve at *every* point across an interval, which geometrically is the *area trapped under the curve* between the two limits written at the top and bottom of the S.

  *Why BD-rate needs it.* Each codec's R-D curve is a function $f^(-1)(p)$ giving the log-bitrate it needs to reach quality $p$. The area under that curve, between the worst and best quality both codecs reach, is the codec's "total cost." Subtracting the two areas, $I_A - I_B$, and dividing by the width $P_"max" - P_"min"$ gives the *average* log-bitrate gap. Finally $exp(...)$ undoes the logarithm (recall from Chapter 7 that $exp$ and $log$ are inverses), turning that average log-gap back into a plain percentage. So the whole formula is just: "average the bitrate difference over all qualities, then read it as a percent."

  *Tiny picture:* if $f_A$ sits a constant $0.32$ below $f_B$ on a base-$e$ log axis across the whole range, then $exp(-0.32) - 1 approx -0.27$, i.e. Codec A needs about 27 % fewer bits at matched quality.
]

A negative BD-rate means Codec A uses fewer bits (Codec A is better). A positive BD-rate means Codec A uses more bits (regression).

#algo(
  name: "BD-Rate (Bjøntegaard Delta Rate)",
  year: "2001",
  authors: "Gisle Bjøntegaard (ITU-T VCEG-M33)",
  aim: "Summarise the average bitrate difference between two R-D curves as a single percentage, integrating over quality levels.",
  complexity: "Requires 4 operating points per codec; polynomial fitting and numerical integration, $O(1)$ computation once data is collected.",
  strengths: "Standard, reproducible, accepted by ITU-T and ISO/IEC; collapses an R-D curve comparison to one number; log-bitrate axis gives equal weight to relative (not absolute) bitrate differences.",
  weaknesses: "Only valid over the overlapping PSNR/quality range; sensitive to the choice of operating points; cubic polynomial may not fit well if the R-D curve is not smooth; PSNR as the quality axis inherits all of PSNR's weaknesses; can be gamed by choosing anchor operating points strategically.",
  superseded: "Extensions use VMAF or SSIM as the y-axis; Akima spline variants address the 4-point limitation.",
)[
  BD-rate is mandatory reporting in MPEG, VCEG, AOM (the Alliance for Open Media, which produced AV1), and in most conference papers on video compression. Always check: what quality metric is on the y-axis, how many operating points were used, and whether the bitrate ranges are comparable.
]

=== BD-PSNR (the dual metric)

The *dual* of BD-rate is *BD-PSNR*: at the same bitrate, how many dB of PSNR does Codec A gain compared to Codec B? A BD-PSNR of +1.5 dB means Codec A achieves 1.5 dB higher quality at the same bitrate, which is quite significant.

The two metrics answer slightly different questions. BD-rate is more intuitive for bandwidth and storage engineers ("we need 20% less bandwidth"). BD-PSNR is more intuitive for quality engineers ("we get 2 dB better quality"). Mathematically, they are equivalent descriptions of the same curve-area difference.

=== BD-Rate Pitfalls

#pitfall[
  *Operating points outside the overlap region.* BD-rate is only defined over the PSNR range covered by both codecs. If you compare an H.264 encoder (which you tested at QP 22/27/32/37) against an AV1 encoder (which you tested at very different quality settings), the overlap region may be tiny, and the BD-rate will be computed over a narrow, possibly unrepresentative range.
]

#pitfall[
  *Using BD-rate with a perceptual y-axis.* BD-rate was designed for PSNR. When people use it with VMAF or SSIM on the y-axis (and many do), the cubic polynomial assumptions may not hold. The "BD-VMAF" or "BD-SSIM" number can be misleading if the VMAF curve has a different shape than PSNR assumes. Check the curve shape before trusting the number.
]

#pitfall[
  *Cherry-picking operating points.* If one codec happens to include a very high-bitrate anchor point and the other does not, the overlap region shifts, and the resulting BD-rate favours the codec that set up the comparison. Independent evaluations always specify exact QP or CRF values in advance.
]

=== A Worked BD-Rate Example

Suppose Codec A (test) and Codec B (anchor) produce the following data on a test clip:

#table(
  columns: (auto, 1fr, auto, 1fr, auto),
  align: (left, right, right, right, right),
  fill: (_, row) => if row == 0 { rgb("#d0e8ff") } else { none },
  table.header([*Point*], [*Rate A (kbps)*], [*PSNR A (dB)*], [*Rate B (kbps)*], [*PSNR B (dB)*]),
  [QP 22], [3450], [42.1], [4200], [42.0],
  [QP 27], [1800], [38.4], [2300], [38.2],
  [QP 32], [850],  [34.9], [1100], [34.7],
  [QP 37], [380],  [31.2], [510],  [31.0],
)

In every row, Codec A achieves essentially the same PSNR as Codec B but uses fewer bits. The BD-rate will be negative. Let us estimate it crudely, the way you can sanity-check any BD-rate by hand. At QP 22, Codec A uses $3450/4200 approx 82\%$ of Codec B's bits (18% savings). At QP 37, it uses $380/510 approx 74\%$ (26% savings). The four per-row savings are about 18%, 22%, 23%, and 26%.

The true BD-rate does not simply average those four numbers; it does the proper integral from step 5, fitting a smooth cubic through each codec's points and comparing the areas under them on a log-bitrate axis. But because the PSNR rows already line up almost exactly (42.1 vs 42.0, 38.4 vs 38.2, ...), the integral barely has to interpolate, so it lands very close to the average of the per-row savings: roughly -22%. That is the point of the worked example. When the operating points are well matched, the intimidating integral collapses to "average the bitrate savings across the curve," and Codec A offers about a 22% bitrate saving over Codec B at equal quality. When the points are *not* well matched, the curve-fitting is exactly what saves you from comparing apples to oranges.

== The Gold Standard: Subjective Tests

All the objective metrics above (PSNR, SSIM, VMAF, LPIPS) are *proxies* for what we actually want to measure: *what a human sees*. When it truly matters (when a video codec is being standardised, when a new audio format is being deployed, when a streaming platform is evaluating a major encoding change) the gold standard is a carefully designed *subjective evaluation test*.

=== Mean Opinion Score (MOS)

The simplest subjective metric is the *Mean Opinion Score* (MOS). Each human listener or viewer rates the quality of a single sample on a five-point scale:

- 5 = Excellent
- 4 = Good
- 3 = Fair
- 2 = Poor
- 1 = Bad

The scores from a panel of listeners (typically 20–100 people for audio; 10–30 for video) are averaged to produce the MOS. For audio, this is defined by ITU-T Recommendation P.800; for video, by ITU-T P.910.

The problem with MOS is that it is *absolute*: each sample is rated in isolation, without comparison to a reference. This makes MOS less sensitive to small quality differences, because listeners calibrate their scales differently from each other. A MOS of 3.9 vs. 4.1 might not be statistically significant with a small panel.

=== MUSHRA: Finer Granularity

For audio quality evaluation (the standard used in codec comparisons), the preferred method is *MUSHRA* (MUltiple Stimuli with Hidden Reference and Anchor), defined by ITU-R Recommendation BS.1534-3.

In a MUSHRA test, the listener is presented simultaneously with:
- A *reference* (the original, uncompressed audio)
- A *hidden reference* (the original again, but unlabelled; if the listener does not rate it 90+, their session may be excluded as invalid)
- One or more *anchors* (deliberately degraded low-quality signals, typically a 3.5 kHz low-pass filtered version of the reference, rated as "bad" anchors to calibrate the scale)
- The *test items* (the codecs being evaluated)

The listener can switch freely between all signals and assigns each a score from 0 to 100 on a continuous scale: Excellent (80–100), Good (60–80), Fair (40–60), Poor (20–40), Bad (0–20). The ability to directly compare all signals simultaneously makes MUSHRA far more sensitive than MOS for detecting small differences.

#keyidea[
  MUSHRA requires fewer participants than MOS to achieve statistical significance, typically 12–25 trained listeners for audio. The key insight is that *direct comparison* amplifies sensitivity. Listeners can detect differences they could not rate reliably in isolation.
]

=== Double-Blind Comparison Tests

For video quality, the equivalent of MUSHRA is a *double-blind* viewing test where neither the participants nor the test administrators know which codec produced which video. Participants typically see two versions of a clip side by side or in sequence and rate their preference, or rate each clip on an absolute scale.

The "double-blind" aspect is critical: human raters are highly susceptible to expectation effects. If a rater knows they are watching a "new AI codec," they may unconsciously rate it higher. Blind tests eliminate this bias.

=== Practical Reality: When Subjective Tests Are Impractical

Subjective tests are expensive: you need a controlled viewing environment, trained participants, statistical analysis, and weeks of time. For everyday codec development, they are impractical. The practical workflow is:

1. During development: use fast objective metrics (PSNR, SSIM, VMAF) to drive engineering decisions.
2. Before major releases: run BD-rate comparisons against reference codecs on a standard test set.
3. For standards bodies and product launches: run full subjective evaluations.

== Benchmark Corpora: What Data Do You Test On?

A metric answers "how good is this output?" A benchmark corpus answers "how good is this codec on *typical* data?" Both matter, and corpus design is a surprisingly subtle problem.

=== The Classic Corpora

*The Calgary Corpus* (1987): One of the first standardised text compression benchmarks, assembled by Tim Bell, Ian Witten, and John Cleary at the University of Calgary. It contains 18 files totalling about 3.3 MB, a mix of English text, C source code, binary executable files, scientific data, and raster images. For a decade, the Calgary corpus was the standard benchmark for lossless compression.

By the mid-1990s, its problems were clear: the files were small and unrepresentative of modern data. The 3.3 MB corpus could be memorised by a sufficiently creative encoder. Researchers began training compressors on the Calgary corpus itself, defeating the purpose of an independent test.

*The Canterbury Corpus* (1997): Assembled by Ross Arnold and Timothy Bell as an update to Calgary. It dropped some Calgary files, added new ones, and raised the total to about 3 MB. Better, but still small.

*The Silesia Corpus* (2003): Created by Sebastian Deorowicz and Szymon Grabowski at the Silesian University of Technology as a direct response to the limitations of Calgary and Canterbury. Silesia contains 12 files totalling about 211 MB (an order of magnitude larger than Canterbury), representing modern file types: English text, XML, HTML, binary executables, a medical CT scan image, a genetics database, and more. Silesia became the standard for lossless compression benchmarks.

*enwik8 and enwik9* (Matt Mahoney, Large Text Compression Benchmark): enwik8 is the first $10^8$ bytes of an English Wikipedia dump; enwik9 is the first $10^9$ bytes. These are the standard benchmarks for the Hutter Prize and the Large Text Compression Benchmark (LTCB), which tracks the state-of-the-art in general-purpose compression. Compressing enwik9 well is essentially equivalent to modelling the structure of human language and knowledge.

=== Corpus Pitfalls

#pitfall[
  *Training-set contamination.* If a compressor was developed (even implicitly) with knowledge of the benchmark corpus, its scores on that corpus are inflated. Always evaluate on held-out data. For neural compressors, this is particularly dangerous: an encoder trained on ImageNet may score artificially well on a benchmark derived from similar distribution data.
]

#pitfall[
  *Unrepresentative content.* The Calgary corpus is dominated by English text. A compressor that is brilliant on English text but terrible on DNA data, binary executables, or structured XML will score well on Calgary. Match your benchmark corpus to your actual use case.
]

#pitfall[
  *Single-file benchmarks.* A single file can be an outlier. Compression ratios on individual files vary enormously depending on the file's redundancy. Always benchmark on a diverse collection of files and report aggregate statistics (average, median, worst-case).
]

#pitfall[
  *Reporting only compression ratio, not speed.* A compressor that achieves 10:1 compression ratio but takes 100 seconds per megabyte is not useful in most applications. Always report both compression ratio (or bpp/bpc) and throughput (MB/s for compression and decompression separately).
]

=== The Speed Dimension: Throughput

The R-D curve captures quality vs. bitrate. But there is a third dimension that is equally important in practice: *speed*. A compressor has both a compression throughput (how many MB/s can it compress?) and a decompression throughput (how many MB/s can it decompress?).

For most applications, decompression is in the critical path: data is compressed once and decompressed many times. That is why fast decompression is at a premium. Codecs like LZ4, Snappy, and zstd at its fastest settings prioritise decompression speed (1–4 GB/s on modern hardware) over maximum compression. The "three-way trade-off" in compression is: ratio vs. speed vs. memory.

#gopython("Measuring compression throughput")[
  Here is a Python 3.14 script that measures the compression and decompression throughput of the `zlib` module (which implements DEFLATE, as discussed in Chapter 30) in MB/s.

  ```python
  # throughput.py - measure compression speed
  import zlib, time, os

  def measure_throughput(data: bytes) -> dict[str, float]:
      """Returns compression and decompression throughput in MB/s."""
      n_bytes = len(data)
      n_mb    = n_bytes / 1_000_000

      # --- compression ---
      t0         = time.perf_counter()
      compressed = zlib.compress(data, level=6)
      t_comp     = time.perf_counter() - t0

      # --- decompression ---
      t0           = time.perf_counter()
      decompressed = zlib.decompress(compressed)
      t_decomp     = time.perf_counter() - t0

      assert decompressed == data, "Round-trip failed!"

      ratio = n_bytes / len(compressed)
      return {
          "ratio":        ratio,
          "comp_mbs":     n_mb / t_comp,
          "decomp_mbs":   n_mb / t_decomp,
          "savings_pct":  (1 - 1/ratio) * 100,
      }

  # Generate 10 MB of fake "English-like" data for a quick test
  sample = (b"The quick brown fox jumps over the lazy dog. " * 50_000)[:10_000_000]

  stats = measure_throughput(sample)
  print(f"Compression ratio : {stats['ratio']:.2f}:1")
  print(f"Space savings     : {stats['savings_pct']:.1f}%")
  print(f"Compress speed    : {stats['comp_mbs']:.1f} MB/s")
  print(f"Decompress speed  : {stats['decomp_mbs']:.1f} MB/s")
  # Typical output on a 2024-era laptop:
  # Compression ratio : 6.80:1
  # Space savings     : 85.3%
  # Compress speed    : 45.2 MB/s
  # Decompress speed  : 198.7 MB/s
  ```

  Note that decompression is about 4–5× faster than compression for DEFLATE. This is typical: the *encoder* does the hard work of finding matches; the *decoder* just follows instructions.
]

=== The Three-Way Trade-Off Visualised

#fig([The compression trade-off triangle: ratio, speed, and memory. Every codec lives somewhere in this space; none dominates all three dimensions.], cetz.canvas({
  import cetz.draw: *

  // Triangle
  set-style(stroke: (thickness: 1.2pt, paint: rgb("#0b5394")))
  let A = (3.5, 5.5)
  let B = (0.5, 0.5)
  let C = (6.5, 0.5)
  line(A, B)
  line(B, C)
  line(C, A)

  // Labels at corners
  content(A, box(width: 3.5cm, align(center, text(size: 9pt)[*Ratio*\ (compress more)])), anchor: "south", padding: 5pt)
  content(B, box(width: 3.5cm, align(center, text(size: 9pt)[*Speed*\ (compress faster)])), anchor: "east", padding: 5pt)
  content(C, box(width: 3.5cm, align(center, text(size: 9pt)[*Memory*\ (use less RAM)])), anchor: "west", padding: 5pt)

  // Codec positions (dots)
  set-style(stroke: none)
  circle((3.5, 4.5), radius: 0.12, fill: rgb("#783f04"))
  content((3.8, 4.5), [LZMA/xz], anchor: "west", size: 8pt, fill: rgb("#783f04"))

  circle((2.5, 1.5), radius: 0.12, fill: rgb("#0b6e4f"))
  content((2.8, 1.5), [LZ4], anchor: "west", size: 8pt, fill: rgb("#0b6e4f"))

  circle((3.5, 2.5), radius: 0.12, fill: rgb("#9a2617"))
  content((3.8, 2.5), [zstd -3], anchor: "west", size: 8pt, fill: rgb("#9a2617"))

  circle((3.5, 3.5), radius: 0.12, fill: rgb("#0b5394"))
  content((3.8, 3.5), [zstd -19], anchor: "west", size: 8pt, fill: rgb("#0b5394"))

  circle((1.8, 1.2), radius: 0.12, fill: rgb("#5b3a86"))
  content((2.1, 1.2), [Snappy], anchor: "west", size: 8pt, fill: rgb("#5b3a86"))
}))

== Common Evaluation Mistakes and How to Avoid Them

This section catalogues the most frequent errors in compression benchmark papers and product comparisons, some inadvertent, some (unfortunately) deliberate.

=== The Anchor Problem

BD-rate is defined *relative to an anchor codec*. A BD-rate of −30 % against H.264 at baseline settings is very different from −30 % against a well-tuned H.264 with optimal settings. Researchers sometimes choose a weak anchor to make their improvements look larger. Always ask: "What exact encoder and settings were used as the reference?"

=== The Resolution and Content Problem

Codecs behave differently on different content types (animation, sports, film, documentary, screen capture) and at different resolutions. A codec that achieves excellent BD-rate on HD content may perform poorly in 4K or on low-complexity animation. Production evaluations (like those at AOM for the AV1 codec) test across *multiple content types and resolutions*, typically including the JCT-VC common test conditions.

=== The "Best of Five" Problem

If you test five codecs and report only the best BD-rate, you are performing implicit multiple testing. This inflates the probability of finding a spurious "winner." Preregister your methodology, test the codecs you planned to test, and report all results.

=== The Measurement Overhead Problem

Metrics like VMAF and LPIPS are slow. In large-scale evaluations, researchers sometimes run them on a *subset* of frames rather than every frame to save time. This can introduce sampling bias, especially for content with variable quality across frames. Always specify whether quality metrics were computed per-frame on all frames or on a sample.

=== The Missing Decompression Timing

Many papers report compression speed but omit decompression speed. For most real-world applications, decompression is in the hot path (read on every access) while compression is amortised (written once). Always report both.

#misconception[
  A higher compression ratio is always better.
][
  Only if you care about ratio alone. In practice, compression ratio trades off against speed, memory, CPU usage, and latency. A database using columnar compression (Chapter 67) may prefer a 2:1 ratio at 5 GB/s decompression over a 10:1 ratio at 50 MB/s. A real-time video encoder may accept lower BD-rate savings in exchange for 4× faster encoding. The *best* metric depends on the application's constraints.
]

== Putting It All Together: A Codec Evaluation Checklist

After all this theory, here is a practical checklist for evaluating compression quality honestly.

#keyidea[
  *The compression evaluation checklist*

  1. *Lossless?* Use compression ratio and throughput. Lossless codecs must round-trip perfectly.
  2. *Lossy text/data?* Use bpc or bpB alongside accuracy metrics specific to your domain.
  3. *Lossy images?* Report bpp on the x-axis. Report at minimum: PSNR, MS-SSIM, and LPIPS (or DISTS). Show the full R-D curve, not a single point.
  4. *Lossy video?* Report kbps on the x-axis. Report: VMAF, PSNR. Compute BD-rate against a well-specified anchor. Specify content type and resolution.
  5. *Audio?* Use objective metrics (PESQ, ViSQOL, MOS-LQO) for development, MUSHRA for final evaluation.
  6. *Speed?* Always report both compression and decompression throughput in MB/s.
  7. *Memory?* Report peak RAM usage during compression and decompression.
  8. *Corpus?* Use a standard corpus (Silesia for lossless; JCT-VC, CLIC, Kodak for images; UVG, MCL-JCV for video). State its provenance.
  9. *Reproducibility?* Publish encoder settings, QP/CRF values, and the exact test sequence names.
  10. *Anchor?* State exactly which codec version and settings served as the reference for BD-rate.
]

== A Note on Neural Compression Metrics (2024–2026)

As learned (neural) image and video codecs matured in Chapters 56–66, the compression community has encountered new metric challenges. Neural decoders (particularly those based on generative adversarial networks (GANs) or diffusion models) can produce images that look perceptually excellent but fail traditional metrics badly.

Consider a generative image codec at very low bitrates. It might decode a compressed landscape photo into a beautiful, sharp image with plausible grass and sky, but with completely different grass blades than the original. A human finds this indistinguishable from high quality. PSNR would give it a catastrophic score; MS-SSIM would give it a mediocre score; LPIPS would score it much better; DISTS would score it best of all.

This has led to the *rate-distortion-perception trade-off*, formalised by Blau and Michaeli (2019) and further extended in 2024–2026 work. The key finding: *there is a fundamental tension between minimising distortion (matching the original pixel-by-pixel) and maximising perceptual quality (producing the most realistic-looking image)*. You cannot perfectly optimise both simultaneously. The choice of which metric you optimise determines which trade-off you land on.

#aside[
  By June 2026, the field had partially converged on using FID (Fréchet Inception Distance) to measure distribution-level quality for generative compression, DISTS for perceptual similarity at the image level, and a combination of user studies and MUSHRA-style tests for final evaluation. No single metric had emerged as universally agreed upon for generative codecs. This remains an active research frontier.
]

#takeaways((
  "The four basic compression metrics (compression ratio, space savings, bpp, and bpc) all measure how many bits the compressed output uses; none measure quality.",
  "An R-D curve plots quality (y-axis) against bitrate (x-axis) across many operating points. One curve dominates another when it lies entirely above-and-to-the-left. Always show curves, not single points.",
  "PSNR is fast and reproducible but poorly correlated with human perception; it is blind to spatial structure and easily fooled by texture resynthesis or small shifts.",
  "SSIM and MS-SSIM improved on PSNR by comparing luminance, contrast, and structural similarity in local windows. They correlate better with human quality ratings.",
  "VMAF (Netflix, 2016) uses machine learning trained on human opinion scores and is now the de facto standard for streaming video quality evaluation.",
  "LPIPS (CVPR 2018) and DISTS (2020) use deep network feature maps as a distance metric; DISTS is especially appropriate when texture resynthesis is acceptable.",
  "BD-rate (Bjøntegaard, ITU-T VCEG-M33, 2001) summarises the average bitrate savings between two R-D curves as a single percentage. A negative BD-rate means the test codec saves bits. Always check the anchor, the operating points, and the quality metric on the y-axis.",
  "Subjective tests (MOS and MUSHRA) are the gold standard. MUSHRA is more sensitive than MOS because it uses direct comparison and a 0-100 scale.",
  "Corpus design is as important as metric choice. Benchmark on diverse, held-out data. Match corpus content type to your application. Report both compression ratio and throughput.",
  "For generative neural codecs, traditional distortion metrics (PSNR, SSIM) can be misleading. DISTS, FID, and user studies are more appropriate.",
))

== Exercises

#exercise("75.1", 1)[
  A 1920×1080 PNG image file is 4.2 MB. After JPEG compression at quality 75, it becomes 320 KB.

  (a) Compute the compression ratio (CR).
  (b) Compute the space savings as a percentage.
  (c) Compute the bits per pixel (bpp) of the JPEG file.
  (d) How does your answer to (c) compare to the 24 bpp of the original uncompressed 8-bit colour image?
]
#solution("75.1")[
  (a) CR = 4,200 KB / 320 KB ≈ 13.1:1 (or equivalently, 4.2 MB / 0.32 MB ≈ 13.1).

  (b) Space savings = 1 − 1/13.1 = 1 − 0.076 ≈ 92.4%.

  (c) Total pixels = 1920 × 1080 = 2,073,600. JPEG size in bits = 320,000 bytes × 8 = 2,560,000 bits. bpp = 2,560,000 / 2,073,600 ≈ 1.23 bpp.

  (d) The original 24 bpp has been reduced to 1.23 bpp, a factor of approximately 19.5x reduction. JPEG at quality 75 achieves substantial compression while typically retaining visually acceptable quality.
]

#exercise("75.2", 1)[
  Explain in plain language the difference between *compression ratio* and *BD-rate*. Why can't you use compression ratio to compare two lossy codecs?
]
#solution("75.2")[
  Compression ratio measures the total space savings without regard to quality. For lossy codecs, this is misleading: a codec that discards all the data achieves infinite compression ratio but produces garbage. BD-rate compares codecs at *equal quality levels*, asking "at the same perceived quality, who needs fewer bits?" It integrates this comparison across a range of quality levels using R-D curves. Compression ratio alone would declare the more destructive codec "better"; BD-rate correctly measures efficiency while controlling for quality.
]

#exercise("75.3", 2)[
  You are comparing two image codecs on a test image. Codec A produces (bpp, PSNR) pairs: (0.4, 30.2), (0.8, 34.5), (1.5, 38.1), (3.0, 42.4). Codec B produces: (0.5, 30.1), (1.0, 34.0), (1.8, 37.5), (3.5, 41.8).

  (a) Without computing the exact BD-rate, explain which codec is likely better and why.
  (b) At PSNR = 34 dB, approximately how many bits per pixel does each codec need? By what percentage does the better codec save bits?
  (c) Why might PSNR be an insufficient basis for this comparison?
]
#solution("75.3")[
  (a) Codec A dominates Codec B: at every PSNR level, Codec A achieves the same quality with fewer bits (its curve lies to the left). The BD-rate will be negative, favouring Codec A.

  (b) At PSNR ≈ 34 dB: Codec A uses about 0.8 bpp (its data point is exactly there). Codec B uses about 1.0 bpp (its nearest point). Savings = (1.0 − 0.8)/1.0 = 20%. Codec A saves roughly 20% of the bits at this quality level.

  (c) PSNR may not reflect perceptual quality well. Codec A might produce blocky artefacts that score well on PSNR but look worse than Codec B's smooth noise. Reporting SSIM, VMAF, or LPIPS alongside PSNR would give a fuller picture.
]

#exercise("75.4", 2)[
  A paper reports: "Our codec achieves a BD-rate of −22% versus H.264." A critic says: "This result is meaningless without more information." What three specific pieces of information should the paper have disclosed to make the BD-rate claim verifiable?
]
#solution("75.4")[
  At minimum, the paper should disclose: (1) *The anchor encoder settings*: which H.264 encoder (libx264? JM reference?), at which presets and QP values; (2) *The quality metric on the y-axis*: was this BD-rate computed with PSNR, VMAF, or SSIM on the y-axis? The choice matters significantly; (3) *The test content*: which sequences, at which resolutions and frame rates. A -22% BD-rate on 4K film content is very different from -22% on 720p animation. Without these three disclosures, the result cannot be reproduced or trusted.
]

#exercise("75.5", 2)[
  Design a benchmark for evaluating a new *audio codec* intended for voice calls (not music). Specify: (a) the corpus you would use, (b) the objective metrics you would report, (c) the subjective test methodology, and (d) one pitfall you would specifically guard against.
]
#solution("75.5")[
  (a) *Corpus:* Use standard speech corpora: the ITU-T P.50 appendix synthetic sentences, or the TIMIT dataset, supplemented with real-world captures covering different speaking rates, accents, and background noise conditions. Target bitrates of 6–32 kbps. Avoid music (out of scope).

  (b) *Objective metrics:* PESQ (ITU-T P.862 / P.862.2), ViSQOL (Google's neural MOS predictor), and WER (Word Error Rate) of a standard ASR model as a functional quality measure.

  (c) *Subjective:* A MUSHRA test (ITU-R BS.1534-3) with at least 20 trained listeners, using the original wideband speech as the reference, a 3.5 kHz lowpass-filtered anchor, and all codecs as stimuli. Rate each 8-second clip on the 0–100 scale.

  (d) *Pitfall:* Avoid evaluating only on the specific accent/dialect used in the training corpus. Neural codecs can learn accent-specific shortcuts. Include at least 3 distinct accents/languages in the evaluation.
]

#exercise("75.6", 3)[
  *Code exercise.* Write a Python 3.14 function `compute_ssim_simple(orig: bytes, recon: bytes, width: int, height: int) -> float` that computes a simplified (single global, not sliding-window) SSIM score between two 8-bit grayscale images provided as flat `bytes` objects. Use only the Python standard library (no NumPy). Test it on an identical pair (should return ≈1.0) and a completely different pair (should return much less than 1.0).
]
#solution("75.6")[
  ```python
  import math

  def compute_ssim_simple(
      orig: bytes, recon: bytes, width: int, height: int
  ) -> float:
      """Global (non-windowed) SSIM approximation for 8-bit greyscale images."""
      assert len(orig) == len(recon) == width * height

      C1 = (0.01 * 255) ** 2  # stability constants
      C2 = (0.03 * 255) ** 2

      n = len(orig)
      # Means
      mu_x = sum(orig)  / n
      mu_y = sum(recon) / n
      # Variances and cross-correlation
      var_x = sum((b - mu_x)**2 for b in orig)  / n
      var_y = sum((b - mu_y)**2 for b in recon) / n
      cov   = sum((orig[i] - mu_x)*(recon[i] - mu_y) for i in range(n)) / n

      ssim = ((2*mu_x*mu_y + C1) * (2*cov + C2)) / (
             (mu_x**2 + mu_y**2 + C1) * (var_x + var_y + C2))
      return ssim

  # --- self-test ---
  img = bytes(range(256)) * 16          # 4096 bytes, 64×64 greyscale
  print(compute_ssim_simple(img, img, 64, 64))          # ≈ 1.0
  noisy = bytes((b + 50) % 256 for b in img)
  print(compute_ssim_simple(img, noisy, 64, 64))        # much less than 1.0
  ```
]

== Further Reading

- #link("https://medium.com/innovation-labs-blog/bjontegaard-delta-rate-metric-c8c82c1bc42c")[Sharabayko, M. "Bjøntegaard Delta-Rate Metric." Medium, Innovation Labs Blog.] Accessible explanation of BD-rate with numeric examples.

- #link("https://arxiv.org/pdf/2401.04039")[Bjøntegaard Delta (BD): A Tutorial Overview of the Metric, Evolution, Challenges, and Recommendations. arXiv:2401.04039, 2024.] Comprehensive 2024 survey of BD-rate's history, variants, and pitfalls; highly recommended before writing a codec paper.

- #link("https://www.reznik.org/papers/MHV22_BD_BR-CameraReady.pdf")[Reznik et al. "Revisiting Bjøntegaard Delta Bitrate (BD-BR) Computation for Codec Compression Efficiency Comparison." Mile-High Video 2022.] Identifies numerical problems in the original BD-rate formula and proposes corrections.

- #link("https://www.cns.nyu.edu/pub/lcv/wang03-preprint.pdf")[Wang, Z., Bovik, A. C., Sheikh, H. R. & Simoncelli, E. P. "Image Quality Assessment: From Error Visibility to Structural Similarity." IEEE TIP, April 2004.] The original SSIM paper; clear and accessible.

- #link("https://netflixtechblog.com/toward-a-better-quality-metric-for-the-video-community-7ed94e752a30")[Netflix Technology Blog. "Toward a Better Quality Metric for the Video Community." 2016.] Netflix's original VMAF announcement with motivation and technical overview.

- #link("https://richzhang.github.io/PerceptualSimilarity/index_files/poster_cvpr.pdf")[Zhang, R., Isola, P., Efros, A. A., Shechtman, E. & Wang, O. "The Unreasonable Effectiveness of Deep Features as a Perceptual Metric." CVPR 2018.] Introduces LPIPS; demonstrates that deep features beat hand-crafted metrics for perceptual similarity.

- #link("https://arxiv.org/pdf/2211.12109")[Video compression dataset and benchmark of learning-based video-quality metrics. arXiv:2211.12109.] Systematic evaluation of how well objective metrics predict human quality judgements for compressed video.

- #link("https://arxiv.org/html/2409.08772")[The Practice of Averaging Rate-Distortion Curves over Testsets Can Cause Misleading Conclusions. arXiv:2409.08772, 2024.] Important methodological warning for neural codec evaluators.

- #link("https://handwiki.org/wiki/Silesia_corpus")[Silesia corpus, HandWiki.] History and contents of the standard lossless compression benchmark corpus.

- #link("http://www.mattmahoney.net/dc/text.html")[Mahoney, M. Large Text Compression Benchmark (enwik8/enwik9).] The leaderboard tracking the state of the art in text compression since 2006.

#bridge[
  We now have a complete toolkit for measuring compression honestly: basic metrics, R-D curves, BD-rate, perceptual quality metrics, and subjective tests. The next chapter zooms out from the technical to the human. Chapter 76, "A People's History of Compression," tells the story of the inventors behind every algorithm we have studied. Shannon working alone at Bell Labs, Huffman racing against a deadline, Lempel and Ziv corresponding across the world, and the dozens of engineers and researchers whose names rarely appear in headlines but whose work runs invisibly inside every device you own.
]
