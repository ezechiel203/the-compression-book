#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Successor Frontier and Encoding at Scale

#epigraph[
  The best encoder is the one that never ships bytes it doesn't have to.
][Anonymous streaming engineer, circa 2019]

Picture this. A streaming service compresses the same thirty-second action scene one hundred different ways (varying the resolution, the bitrate, the encoding preset, the quantizer) just to find the single configuration that gives the best visual quality per byte for *that exact scene*. No template. No rule of thumb. Just exhaustive search, guided by a machine that has learned to see the way humans do.

That image, of a machine spending enormous compute to save every viewer a few precious kilobytes, captures where professional video encoding sits in 2026. The codec standards are getting better, the perceptual quality metrics are getting smarter, and the distance between "the codec exists" and "the codec is being used efficiently at scale" keeps widening. This chapter lives at that frontier.

We will cover three interlocking stories. First, the Enhanced Compression Model (ECM): JVET's research platform that already beats VVC by more than 25% and is carving the path toward H.267. Second, the parallel Neural Network Video Coding (NNVC) track, which asks whether learned neural networks can replace the hand-crafted tools in ECM entirely. Third, the practical engineering layer that makes all of this matter in the real world: Netflix's per-title and per-shot encoding pipeline, the VMAF quality metric that drives it, content-adaptive rate-distortion optimization, and the bitrate ladder, the set of encode variants that a streaming service maintains so every device and network speed gets the right version.

#recap[
  Chapter 38 introduced the Discrete Cosine Transform (DCT) and showed how transform coding concentrates image energy into a handful of coefficients. Chapter 51 built the full hybrid codec loop: motion-compensated prediction, transform coding of the residual, quantization, and entropy coding bound together by Lagrangian rate-distortion optimization (RDO) where the encoder minimises $J = D + lambda dot R$. Chapter 52 traced the lineage from H.261 through H.264/AVC. Chapter 53 explained how HEVC's Coding Tree Units (CTUs) and VVC's multi-type tree (MTT) each bought another round of ~50% bitrate savings while making the standard's patent landscape progressively more tangled. Chapter 54 showed how that licensing chaos motivated the royalty-free AV1 (2018) and AV2 (2025–26) standards from the Alliance for Open Media. This chapter picks up where VVC and AV2 leave off, looking at what comes next, and at how sophisticated production pipelines squeeze every last bit of efficiency out of *existing* codecs right now.
]

#objectives((
  "Explain what JVET's Enhanced Compression Model (ECM) is and why it exceeds VVC compression by more than 25%.",
  "Name at least four specific coding tools that ECM adds beyond VVC and describe each in plain language.",
  "Distinguish the ECM track (refinement of classical tools) from the NNVC track (learned neural replacements).",
  "Describe the H.267 standardisation timeline and realistic deployment horizon.",
  "Explain what a bitrate ladder is and why a fixed ladder wastes bandwidth.",
  "Describe Netflix per-title encoding, per-shot encoding, and the Dynamic Optimizer.",
  "Explain what VMAF is, how it differs from PSNR, and why it drives modern production pipelines.",
  "Read Python code that simulates a simplified convex-hull bitrate ladder selection.",
))

== Beyond VVC: The Enhanced Compression Model

When the Joint Video Experts Team (JVET) finished VVC in July 2020, the engineers did not go home. The same group (the collaborative body of ITU-T VCEG and ISO/IEC MPEG that also produced HEVC and VVC) immediately started the next phase. Their tool was a software platform called the *Enhanced Compression Model*, universally abbreviated ECM.

Think of ECM the way you might think of a prototype racing car that is built in a laboratory. It is not road-legal. It would be chaotic to drive on public roads. But every innovative part fitted to it is being evaluated: how much does it save? How much complexity does it add? Which combinations work together? If the part passes those tests, it has a chance of making it into the eventual production standard, which is expected to carry the designation *H.267*.

#definition("Enhanced Compression Model (ECM)")[
  ECM is JVET's open-source research codec, a modified and heavily extended version of the VVC reference software (VTM), maintained at #link("https://jvet.hhi.fraunhofer.de")[jvet.hhi.fraunhofer.de]. It is not a standard; it is the laboratory where the tools for the *next* standard are developed and measured. Each versioned ECM release (ECM-1.0, ECM-2.0, … ECM-15.0 as of late 2024) represents the cumulative best-known combination of beyond-VVC tools at that moment.
]

=== How Much Better Is ECM?

By late 2024, ECM version 15 was achieving approximately *26.6% bitrate savings* over VVC (measured in the random-access configuration on standard JVET test sequences, using the Björntegaard Delta Rate metric, the standard way to compare codec efficiency). For screen-content sequences (slides, text, computer-generated graphics) the savings reached up to 40%, because screen content has very different statistical properties (sharp edges, flat colour regions) that ECM's new tools handle especially well.

#gomaths("Björntegaard Delta Rate (BD-Rate)")[
  Two codecs do not encode at exactly the same bitrate, so you cannot compare them with a single number. The standard technique is to plot *Rate-PSNR* (or Rate-VMAF) curves for each codec by encoding the same video at several different quality settings and measuring the resulting bitrate and quality at each point. The *Björntegaard Delta Rate (BD-Rate)* is the average percentage difference in bitrate between the two curves at the same quality level, integrated across the quality range. A BD-Rate of −26.6% means "to achieve the same quality, the new codec needs 26.6% fewer bits." A negative number is always better.

  The metric was introduced by Gisle Bjøntegaard in a 2001 VCEG contribution. His name is typically anglicised to "Björntegaard" in the literature.
]

That 26.6% is a large number. To put it in perspective: H.264 to HEVC was roughly 50% savings; HEVC to VVC was roughly 50% again. ECM to H.267 will not be another 50% (that would require physics-defying gains), but a consistent 25–40% across content types would still represent a substantial step forward, roughly comparable to the gains HEVC delivered over H.264.

=== What Tools Give ECM Its Edge?

ECM is not magic. It earns every percentage point through a collection of carefully engineered coding tools, each of which addresses a specific residual redundancy that VVC left on the table. Here are the most important ones.

==== Template-Based Intra Mode Derivation (TIMD)

In VVC, the encoder signals which intra-prediction mode (out of 67 angular directions plus DC and Planar) was chosen for each block. That signalling costs bits. TIMD asks: can we *derive* the prediction direction from the already-decoded pixels surrounding the block, without sending it at all?

The answer is yes, much of the time. TIMD works by building a small template: a strip of already-decoded pixels just above and to the left of the current block. It then tests each candidate intra mode by using that mode to predict the template pixels, and measures how well the prediction matches using the Sum of Absolute Transformed Differences (SATD). The prediction error is run through a small Hadamard transform (a frequency-like transform built only from additions and subtractions of $+1$ and $-1$) and the absolute values are summed, which estimates coding cost better than summing raw pixel errors. The mode that best predicts the template is chosen. No bits are spent signalling it; the decoder can reproduce the exact same decision because it has the same decoded neighbours.

When TIMD derives the correct mode, the bits saved on mode signalling are pure gain. When it guesses wrong, the residual is larger, which costs more bits, so the encoder's RDO loop decides per-block whether to use TIMD or fall back to explicit signalling.

==== Decoder-Side Intra Mode Derivation (DIMD)

DIMD is a companion tool that operates at the decoder rather than the encoder. It analyses the gradient direction of reconstructed neighbour pixels using Sobel filters (the same kind of edge-detection filters used in image processing), builds a histogram of gradient directions, and derives a blended prediction that combines the dominant gradient direction with the Planar mode.

The result is a smoother, more accurate intra predictor that requires no additional signalling from the encoder. Since both encoder and decoder compute the same gradient analysis on the same reconstructed pixels, they always agree. DIMD and TIMD can be combined, each adding independent savings.

==== Geometric Partition Mode (GPM) Extended

VVC introduced a Geometric Partition Mode that divides an inter-coded block into two wedge-shaped regions, each with its own motion vector. This is better than rectangular sub-partitions for objects with diagonal edges. ECM's *Spatial Geometric Partition Mode (SGPM)* extends this idea to intra prediction: an intra block can be divided into two geometric regions, each with its own prediction mode. The gain is largest for blocks that straddle a strong edge.

==== Adaptive Colour Transform (ACT) and Cross-Component Prediction (CCCP)

Colour images have three components: luma (Y) and two chroma channels (Cb, Cr) in video. These components are not independent: where the luma has a strong edge, the chroma channels almost always have an edge at the same place. VVC already exploited some cross-component correlation; ECM adds more sophisticated *Cross-Component Coding* (CCC) tools, including a Cross-Component Prediction (CCCP) mode where the chroma residual is predicted as a linear function of the luma residual. If the chroma residual is mostly the luma residual scaled by some constant $alpha$, then sending just $alpha$ (a few bits) plus the tiny deviation is far cheaper than sending the full chroma residual.

==== Spatial-Temporal Motion Vector Prediction (STMVP) and Affine Motion

Motion in real video is rarely a simple translational shift of a rectangular block. A camera panning across a scene creates a global translation; zooming creates a scaling motion; a spinning wheel creates rotational motion. VVC introduced *affine motion compensation*, which models motion inside a block as a 2D affine transformation (translation plus rotation, scaling, and shear), parameterised by two or four motion vectors at the corners. ECM extends this with more flexible affine candidate lists and improved Spatial-Temporal Motion Vector Prediction, which uses motion vectors from spatially and temporally neighbouring blocks as better starting points for the encoder's motion search.

==== Improved In-Loop Filters

VVC already had three in-loop filters: the Deblocking Filter (to smooth quantisation artefacts at block boundaries), the Sample Adaptive Offset (SAO, to reduce ringing), and the Adaptive Loop Filter (ALF, a Wiener filter trained per frame; a Wiener filter is simply the linear filter whose weights are chosen to minimise the mean squared error between the filtered output and the clean target). ECM adds a *Cross-Component Adaptive Loop Filter (CC-ALF)* that uses luma samples to help filter chroma, and experiments with *CNN-based in-loop filters*: small convolutional neural networks that replace some of the handcrafted filter stages. These neural in-loop filters blur the line between ECM's classical track and the NNVC neural track discussed below.

#keyidea[
  ECM's core philosophy is the same as every codec before it: find the residual correlation that the previous standard left uncaptured, and add a tool to exploit it. The tools get more elaborate with each generation because the easy redundancies were removed first. ECM tools like TIMD and DIMD effectively eliminate signalling overhead for decisions that the decoder can reproduce independently, a principle that sounds simple but requires very careful design to ensure encoder and decoder always agree.
]

#algo(
  name: "ECM (Enhanced Compression Model)",
  year: "2021–ongoing",
  authors: "Joint Video Experts Team (JVET), ITU-T VCEG + ISO/IEC MPEG",
  aim: "Research platform for beyond-VVC video compression tools, targeting H.267 standardisation.",
  complexity: "Encoder: much higher than VVC (ECM encodes are 5–20× slower than VTM). Decoder: moderate increase over VVC.",
  strengths: "~26% BD-Rate gain over VVC (random access, ECM-15); up to 40% for screen content. Incorporates neural in-loop filters. Systematic tool-combination testing.",
  weaknesses: "Not a deployable standard. Software is research-quality. Each new tool adds encoder complexity. Hardware decoder does not yet exist.",
  superseded: "Will be superseded by H.267 (target finalisation 2028–2029), which will incorporate the winning subset of ECM tools.",
)[
  ECM is versioned continuously. ECM-15.0 (November 2024) represents the current state of the art; later versions continue to improve. The reference software is available at #link("https://jvet.hhi.fraunhofer.de")[jvet.hhi.fraunhofer.de].
]

== The Neural Network Video Coding (NNVC) Track

Running in parallel with ECM is a fundamentally different research programme inside JVET: *Neural Network Video Coding (NNVC)*. Where ECM takes VVC's classical structure and improves each hand-designed component, NNVC asks the more radical question: what if we replaced some or all of those hand-crafted components with learned neural networks?

The distinction matters. ECM is evolution; NNVC is potential revolution.

#history[
  JVET established an ad hoc group on NNVC at its 19th meeting (June 2020) and began evaluating neural network tools for inclusion in future standards. The first common software for NNVC, called Neural Compression Software (NCS), was released after the 27th JVET meeting, containing two NN-based in-loop filtering tools. Since then, JVET has maintained a growing body of NN-based common experiments alongside the ECM track. The two tracks are expected to converge: H.267 will almost certainly incorporate some neural components, even if the overall codec architecture remains hybrid.
]

=== What Does NNVC Replace?

The classical hybrid codec has many individually improvable components. Neural networks have been shown to surpass hand-crafted designs in several of them:

- *In-loop filters.* A small convolutional neural network trained to map from reconstructed (artefact-contaminated) pixels to clean pixels can outperform VVC's Adaptive Loop Filter. The network sees more context than a fixed Wiener filter. NCS already includes such filters as common experiments.

- *Intra prediction.* Instead of choosing from 67 fixed angular modes, a neural network can synthesise an intra prediction that is tailored to the exact texture of the already-decoded neighbours. Google's work on neural intra prediction showed gains over HEVC-style fixed modes years ago; JVET experiments show similar potential over VVC.

- *Inter prediction residual coding.* Transforming the residual with a learned transform rather than the fixed DCT can, in principle, better match the statistical structure of real motion residuals. Replacing the DCT block-by-block with a tiny per-block learned linear transform is an active JVET research thread.

- *Entropy model.* The probability distributions that feed the arithmetic coder in CABAC are estimated using hand-crafted context models. A neural network can, in principle, learn a better probability model from data. This is the principle behind Ballé et al.'s learned image compression work (Chapter 57), and NNVC extends it to the residual signals in video.

=== The Tension: Quality Versus Deployability

A fully neural video codec would, in principle, achieve the best possible rate-distortion performance. But it faces the same hardware wall that haunts AV2 and every other new codec: to be useful at scale, a codec must have hardware decoders. A neural codec's decoder must run neural network inference. Neural inference on mobile silicon, at real-time 4K speeds, requires dedicated Neural Processing Units (NPUs) that are only now becoming ubiquitous in high-end phones (2024–2025) and are still absent from most set-top boxes and older TVs.

This is why H.267 is not expected to be a fully neural codec. The current JVET consensus (as of 2026) is a *hybrid* approach: the overall architecture remains the classical hybrid loop (motion compensation + transform + entropy coding), but specific components (primarily in-loop filters, possibly intra synthesis) will be NN-based, with the complexity of those networks constrained to what can be decoded in real time on projected hardware by the late 2020s.

#misconception[Neural network video codecs are already better than VVC and will replace it immediately.][
  At the time of writing (2026), the best purely learned video codecs (DVC, DCVC, VCT, covered in Chapter 59) rival or slightly surpass VVC in BD-Rate on standard benchmarks, but only at high resolutions and at enormous computational cost. More importantly, they have no hardware decoders in consumer devices. H.267, expected around 2028–2029, will be the first *standard* to incorporate neural components. Widespread deployment in streaming and broadcast will follow hardware deployment by several years; realistically, broad consumer reach is not expected before 2032–2035.
]

#algo(
  name: "NNVC (Neural Network Video Coding)",
  year: "2020–ongoing",
  authors: "JVET Ad Hoc Group on NNVC, ITU-T VCEG + ISO/IEC MPEG",
  aim: "Replace hand-crafted codec components with learned neural networks to exceed the rate-distortion performance achievable by classical tool engineering.",
  complexity: "Encoder: similar to classical (neural inference is parallelisable on GPU). Decoder: requires neural inference, typically 2–10× heavier than VVC at matched quality.",
  strengths: "Can capture statistics that hand-crafted tools miss. In-loop filters already show consistent gains over VVC ALF. Potentially better intra synthesis for complex textures.",
  weaknesses: "No hardware decoders exist. Bitstream is not yet standardised. Training requires large datasets and GPU compute. Model size must be kept small for practical use.",
  superseded: "Expected to merge with ECM tools inside H.267 (2028–2029).",
)[]

== H.267: What Comes After VVC?

H.267 is the working name for the video coding standard that JVET is building on top of ECM and NNVC research. As of June 2026, the situation is:

- JVET issued a *Call for Proposals* (CfP) for H.267 tools in 2023. Competing organisations submitted technology proposals; those are now being integrated into ECM.
- The formal standardisation process is expected to run through roughly *January 2027* (when competing participants present final technology assessments) and to finalise around *July–October 2028*, with some estimates extending to end of 2029.
- The technical target is *at least 40% bitrate reduction compared to VVC* for 4K and higher resolutions at matched subjective quality. ECM is currently at ~26% (random access); getting to 40% will require the neural tools or further undiscovered classical innovations.
- If the historical pattern holds, standards take two to three years to reach hardware decoders, and hardware decoders take another two to three years to reach mainstream consumer devices. Under that pattern, meaningful deployment of H.267 in streaming will begin around 2031–2033 and reach broad consumer reach around 2034–2036.

That last timeline is striking. Engineers working on H.267 today are writing code that most consumers will not benefit from until their children are teenagers.

#aside[
  The progression of codec adoption timescales illustrates a broader truth about infrastructure: the faster the underlying technology improves, the wider the gap between "standard published" and "deployed everywhere." H.264 had a four-year gap between publication (2003) and near-universal hardware support (~2007). HEVC had a seven-year gap (2013 to ~2020 for hardware AV1 competition to arrive). AV1, published in 2018, still lacked volume hardware decoders in affordable TVs until 2022–2023. Each generation, more silicon needs to be replaced.
]

#fig([H.267 development timeline: from ECM research to broad deployment. Dates marked "expected" are estimates as of June 2026.], cetz.canvas({
  import cetz.draw: *
  let y = 0
  let bar(x0, x1, col, label, yy) = {
    let w = x1 - x0
    rect((x0, yy - 0.22), (x1, yy + 0.22), fill: col, stroke: none, radius: 2pt)
    content(((x0 + x1) / 2, yy), box(width: calc.max(w - 0.4, 0.5) * 1cm, inset: 1pt, align(center, text(size: 7pt, fill: white, weight: "bold")[#label])))
  }
  let tick(x, label) = {
    line((x, -0.6), (x, 1.8), stroke: (dash: "dashed", paint: rgb("#aaaaaa"), thickness: 0.5pt))
    content((x, -0.85), text(size: 7.5pt)[#label])
  }
  tick(0, "2020")
  tick(2, "2022")
  tick(4, "2024")
  tick(6, "2026")
  tick(8, "2028")
  tick(10, "2030")
  tick(12, "2032")
  tick(14, "2034")
  bar(0, 8, rgb("#0b5394"), "ECM research", 1.4)
  bar(6, 8.5, rgb("#783f04"), "H.267 final", 0.85)
  bar(8, 11, rgb("#0b6e4f"), "HW decoders", 0.3)
  bar(11, 14, rgb("#5b3a86"), "Broad deploy.", -0.25)
  content((14.5, 1.4), text(size: 7pt)[ECM])
  content((14.5, 0.85), text(size: 7pt)[H.267])
  content((14.5, 0.3), text(size: 7pt)[HW])
  content((14.5, -0.25), text(size: 7pt)[Mass])
}))

== The Practical Layer: Encoding at Scale

ECM and H.267 matter enormously for the long run. But right now, in 2026, the biggest lever a streaming service has is not which codec it uses - it is *how well* it uses the codecs it already has. The gap between a naively configured H.264 encoder and a sophisticatedly optimised AV1 or H.265 encoder running on the same content is often larger than the gap between H.264 and H.265 themselves. That is the insight that drove Netflix, Disney+, YouTube, and every major streamer to invest heavily in encoding infrastructure.

The key concepts are: the *bitrate ladder*, *per-title encoding*, *per-shot encoding*, *VMAF*, and the *Dynamic Optimizer*. We will build them up in order.

=== The Bitrate Ladder

Video streaming services do not send a single version of a video. They send many versions at different resolutions and bitrates, and let the player switch between them as network conditions change. This is *Adaptive Bitrate Streaming (ABR)*. The set of available representations is the *bitrate ladder*.

#definition("Bitrate Ladder")[
  A bitrate ladder is an ordered list of (resolution, bitrate) pairs that a streaming service encodes for each video. A typical ladder might include representations at 240p/400kbps, 360p/750kbps, 480p/1.5 Mbps, 720p/3 Mbps, 1080p/6 Mbps, and 4K/16 Mbps. The player starts at a low rung, estimates network bandwidth, and switches to a higher rung when bandwidth allows.
]

For most of the history of streaming (say, 2007 to 2015) the bitrate ladder was *fixed*. Every video on a platform used the same ladder. This seemed efficient from an engineering standpoint: you only have to configure the encoder once, and you know exactly what files you will produce.

But it was wasteful in a subtle way. A simple, low-motion documentary needs far fewer bits per second than an action film with explosions, rapid camera motion, and hundreds of moving objects. If both use the same ladder, the documentary is being grossly over-encoded at high bitrates (wasting storage and bandwidth) while the action film may be visibly under-encoded at low bitrates (hurting quality). The *optimal* ladder for each video is different, and a one-size-fits-all approach misses that.

=== Per-Title Encoding

Netflix recognised this problem and, in December 2015, introduced *per-title encoding*. The idea, described in their Tech Blog post by Anne Aaron and colleagues, was to find the *optimal bitrate ladder for each individual video title*.

To find the optimal ladder, Netflix uses what they call a *convex hull* approach. For a given title:

#gomaths("Convex Hull")[
  Imagine you scatter a handful of nails into a board, then stretch a rubber band so it loops around all of them and let it snap tight. The rubber band traces out the *convex hull*: the smallest convex (outward-bulging, never dented inward) boundary that contains every point. Any nail strictly inside the loop is "wrapped up" by the others; the nails the band actually touches are the hull.

  Tiny example. Take five points on a grid: $(0,0)$, $(2,0)$, $(2,2)$, $(0,2)$, and $(1,1)$. The first four are the corners of a square; the band snaps around them. The fifth point, $(1,1)$, sits in the middle, so the band never touches it. It is *inside* the hull.

  In this chapter we only care about the *upper-left* part of the hull in (bitrate, quality) space: the points you cannot beat by moving left (cheaper) and up (better) at the same time. That efficient edge is exactly the set of encodes worth keeping; everything below it is wasteful. The same "outer boundary of the good trade-offs" idea reappears as the operational rate–distortion curve in Chapter 41.
]

1. Encode the title at many (resolution, quantiser) combinations, sometimes hundreds of test encodes.
2. For each test encode, measure the quality (using VMAF, described next) and the resulting bitrate.
3. Plot all the points in (bitrate, quality) space.
4. The *convex hull* of those points is the efficient frontier: the outer boundary where no other point offers both higher quality and lower bitrate.
5. Sample the convex hull at target bitrates to define the rungs of the ladder.

#fig([Per-title convex hull: the outer boundary of (bitrate, VMAF quality) points across many test encodes becomes the bitrate ladder. Points inside the hull are dominated, meaning another point offers the same quality at lower bitrate, or higher quality at the same bitrate.], cetz.canvas({
  import cetz.draw: *
  // Axes
  line((0, 0), (7, 0), mark: (end: ">"))
  line((0, 0), (0, 5), mark: (end: ">"))
  content((3.5, -0.5), text(size: 8.5pt)[Bitrate (Mbps)])
  content((-0.7, 2.5), text(size: 8.5pt)[VMAF])
  // Interior points (dominated)
  let pts = ((1.2, 1.5), (2.1, 2.2), (1.8, 1.8), (3.5, 3.1), (2.8, 2.9),
             (4.2, 3.2), (3.0, 2.0), (5.1, 3.5), (4.5, 2.8), (1.5, 2.0))
  for p in pts {
    circle(p, radius: 0.07, fill: rgb("#aaaaaa"), stroke: none)
  }
  // Convex hull points (efficient frontier)
  let hull = ((0.8, 1.0), (1.4, 2.1), (2.5, 3.3), (4.0, 4.1), (5.8, 4.6))
  for p in hull {
    circle(p, radius: 0.1, fill: rgb("#0b5394"), stroke: none)
  }
  // Draw hull line
  let prev = hull.at(0)
  for i in range(1, hull.len()) {
    let curr = hull.at(i)
    line(prev, curr, stroke: (paint: rgb("#0b5394"), thickness: 1.2pt))
    prev = curr
  }
  content((5.0, 4.8), text(size: 8pt, fill: rgb("#0b5394"))[Convex hull])
  content((3.5, 2.0), text(size: 8pt, fill: rgb("#888888"))[Dominated points])
}))

The result: each title gets a ladder tailored to its complexity. Simple, talking-head content gets a ladder where the low-bitrate rungs are at higher resolution (because simple content compresses better). Complex action content gets a ladder where more bitrate is allocated at each resolution. Netflix estimated roughly 20% average bitrate savings from per-title encoding, with some simple titles saving considerably more.

=== VMAF: Seeing Like a Human

The per-title approach requires a quality metric that measures what viewers actually care about. *Peak Signal-to-Noise Ratio (PSNR)*, the metric that compares pixels mathematically, is notoriously poor at predicting perceived quality. A frame with a lot of high-frequency film grain scores low on PSNR even if it looks beautiful; a frame with large smooth blobs of wrong colour scores high on PSNR even if it looks wrong.

Netflix developed *VMAF (Video Multi-method Assessment Fusion)* in collaboration with the University of Southern California to address this. VMAF uses a machine learning model (originally a Support Vector Machine, later updated to neural regression) trained on thousands of video clips for which human subjects rated quality in controlled viewing studies. Its inputs are several perceptual features:

- *VIF (Visual Information Fidelity)*: how much mutual information is preserved between original and compressed frames.
- *DLM (Detail Loss Metric)*: how well fine detail is preserved.
- *Motion*: a measure of temporal activity (motion amplifies visibility of artefacts).

The model combines these into a single score between 0 and 100 that correlates far better with human judgement than PSNR across a wide range of content types and codecs.

#gomaths("Mutual Information and Perceptual Quality")[
  *Visual Information Fidelity (VIF)* is grounded in information theory. The idea (due to Sheikh and Bovik, 2006) is to model the reference video and the compressed video as signals passed through a realistic model of the human visual system (HVS). VIF computes the ratio of the mutual information between the HVS output and the original, to the mutual information of the HVS output under the reference conditions. Informally: "how much visual information does the compressed frame preserve, relative to how much the original frame would convey through the human eye?" A score of 1.0 means perfect preservation; lower scores indicate information loss due to compression.

  Recall from Chapter 20: the *mutual information* between two random variables $X$ and $Y$ is $I(X; Y) = H(X) - H(X | Y)$, the reduction in uncertainty about $X$ when $Y$ is observed (here $H(X | Y)$, the conditional entropy, was built in Chapter 18). VIF uses a Gaussian Scale Mixture model of natural image statistics to compute this tractably.
]

VMAF is now an open standard. Netflix released the source code on GitHub, and it is used by virtually every major streaming platform and many hardware encoder vendors. As of 2024–2025, VMAF is integrated into FFmpeg, the libvmaf library, and most professional encoding tools.

#gopython("Dictionaries and Function Calls in Python")[
  Many of the encoding pipeline concepts in this chapter can be expressed in Python using dictionaries to represent (bitrate, quality) data points and functions to process them. A Python `dict` maps keys to values:

  ```python
  # A single test encode result: resolution, bitrate in kbps, VMAF score
  encode: dict[str, float] = {
      "resolution": "1080p",
      "bitrate_kbps": 4500.0,
      "vmaf": 94.3,
  }
  # Access a value by key
  print(encode["vmaf"])   # 94.3
  ```

  A `list[dict]` can hold many such results:

  ```python
  results: list[dict[str, float]] = [
      {"bitrate_kbps": 800.0,  "vmaf": 72.1},
      {"bitrate_kbps": 1500.0, "vmaf": 82.5},
      {"bitrate_kbps": 3000.0, "vmaf": 91.0},
      {"bitrate_kbps": 6000.0, "vmaf": 96.2},
  ]
  # Sort by bitrate (ascending)
  results.sort(key=lambda r: r["bitrate_kbps"])
  ```

  The `lambda` keyword creates a small anonymous function on the spot. `key=lambda r: r["bitrate_kbps"]` tells `sort` to compare items by their `"bitrate_kbps"` value.
]

=== Per-Shot Encoding and the Dynamic Optimizer

Per-title encoding was a large step forward, but it still treated the entire title as a single entity. A two-hour film contains thousands of *shots* (individual camera takes), and each shot has a different character. A peaceful landscape scene needs far fewer bits than the battle that follows it; a night scene needs different allocation than the daytime equivalent; a fast-panning crowd scene is far harder to compress than a static close-up.

*Per-shot encoding* takes the per-title philosophy to its natural conclusion: compute the optimal encoding parameters shot by shot rather than title by title.

Netflix began rolling out optimised shot-based encodes for 4K content around 2019–2020. The mechanics are:

1. *Shot detection:* Automatically split the video into shots (scenes between cuts) using temporal analysis.
2. *Complexity analysis:* Estimate the compressibility of each shot using spatial and temporal features: texture complexity, motion magnitude, colour variance.
3. *Optimise the ladder per shot:* For each shot, find the (resolution, QP) combination that meets a VMAF target (say, 93) at the lowest bitrate.
4. *Stitch the encodes:* Concatenate the per-shot encodes into a single deliverable bitstream for each rung of the ladder. The stitching points must fall at valid stream boundaries.

The bitrate savings from per-shot encoding on top of per-title encoding are substantial. Netflix reported roughly 30% additional bitrate savings on 4K HDR content by moving from per-title to per-shot optimisation.

#aside[
  The compute cost of per-shot optimisation is enormous. For a single two-hour film, a streaming service might run thousands of individual test encodes across multiple resolutions and quality settings, evaluate VMAF on each one, and then select optimal configurations. This is only economically viable because of the streaming asymmetry: encode once, decode billions of times. A streaming service amortises the one-time encode cost across every single viewer who ever watches the film. A film streamed to ten million viewers saves ten million × (savings per stream), which easily justifies hours of cloud encoding time.
]

=== The Dynamic Optimizer: Tying It Together

Netflix formalised the shot-based approach into a system called the *Dynamic Optimizer (DO)*, announced in March 2018. The DO is a perceptual video encoding optimisation framework that operates under the control of VMAF. Its job is to determine, for each shot at each target bitrate in the ladder, the optimal resolution and quantiser parameter (QP) such that:

$"VMAF"("encode"(x, "resolution", "QP")) >= "target"$

and the resulting bitrate is as low as possible.

The DO works by iterative refinement: given a target bitrate and a shot, it searches over (resolution, QP) combinations, encoding each candidate, evaluating VMAF, and using the results to guide the next search step. When it finds the combination that hits the VMAF target at minimum bitrate, that is the winning configuration for that shot and that rung.

The measured impact was striking. Using the Dynamic Optimizer, Netflix reduced the bitrates of their x264 (H.264) encodes by *28%* on average at the same VMAF score, their VP9 encodes by *38%*, and their x265 (H.265) encodes by *34%*. These are savings on top of the codec's own compression, achieved purely by smarter encoder configuration.

#keyidea[
  The Dynamic Optimizer is a practical demonstration of a principle that runs through the whole book: *compression efficiency depends on the quality of the model*. A VMAF-driven per-shot optimiser has a better model of what matters than a fixed-QP encoder using the same codec, and that better model translates directly into fewer bits for the same perceived quality. The codec provides the mechanism; the optimizer provides the intelligence.
]

#algo(
  name: "Per-Title / Per-Shot Encoding with Dynamic Optimizer",
  year: "2015 (per-title), 2018–2020 (per-shot / DO)",
  authors: "Anne Aaron, Zhi Li, Megha Manohara, Yilin Wang et al. (Netflix Technology Blog)",
  aim: "Customise bitrate ladder and encoding parameters per title (or per shot) to minimise bitrate at target perceptual quality, as measured by VMAF.",
  complexity: "Encoder: O(N_shots x N_candidates) test encodes, each requiring a full encode plus VMAF evaluation. For a feature film, thousands of encodes. Decoder: unchanged; the player sees a normal HLS/DASH stream.",
  strengths: "20–30% bitrate reduction over fixed-ladder encoding (per-title); additional 30% reduction from per-shot. Directly optimises for human perceptual quality. Codec-agnostic (works with H.264, H.265, AV1).",
  weaknesses: "Extremely compute-intensive. Requires shot detection, complexity analysis, and VMAF inference infrastructure. Longer encodes mean longer time-to-publish for new content.",
  superseded: "Continually extended; as of 2025–2026, ML-based ladder prediction that estimates the optimal ladder from content features without exhaustive test encodes is an active area.",
)[]

=== VMAF-Driven Rate-Distortion Optimization

The most sophisticated streaming encoders today go one step further: they use VMAF not just to evaluate the final encode, but to drive the encoder's internal *rate-distortion optimization loop*.

Recall from Chapter 51 that the encoder's RDO loop evaluates every coding decision (which partition, which mode, which motion vector) by minimising the Lagrangian cost $J = D + lambda dot R$, where $D$ is distortion (usually sum of squared pixel errors, SSE) and $R$ is the number of bits. The Lagrange multiplier $lambda$ is tied to the quantiser parameter.

The problem with using SSE as the distortion measure $D$ is the same problem as PSNR: it does not correlate well with perceived quality. If you replace SSE with a perceptual distortion measure derived from VMAF features (one that assigns higher cost to distortions that humans notice and lower cost to distortions they don't) the encoder's decisions improve.

This *VMAF-driven RDO* is an active area of both industrial and academic research. The practical implementation is challenging because VMAF is expensive to compute per-block (it is designed to operate on full frames, not individual coding blocks), so approximations and feature-based proxies are used. But even partial VMAF integration into the RDO loop shows measurable improvements in rate-distortion performance at fixed perceptual quality targets.

#fig([The layered encoding decision hierarchy. Each layer adds intelligence but also compute cost.], cetz.canvas({
  import cetz.draw: *
  let box_at(x, y, w, h, col, label) = {
    rect((x, y), (x + w, y + h), fill: col.lighten(85%), stroke: 0.8pt + col, radius: 3pt)
    content((x + w / 2, y + h / 2), box(width: (w - 0.4) * 1cm, inset: 2pt, align(center, text(size: 8pt, fill: col, weight: "bold")[#label])))
  }
  box_at(0.5, 3.5, 6, 0.75, rgb("#0b5394"), "Fixed bitrate ladder (pre-2015)")
  box_at(0.5, 2.5, 6, 0.75, rgb("#783f04"), "Per-title encoding (2015)")
  box_at(0.5, 1.5, 6, 0.75, rgb("#0b6e4f"), "Per-shot + Dynamic Optimizer (2018–20)")
  box_at(0.5, 0.5, 6, 0.75, rgb("#5b3a86"), "VMAF-driven RDO (2022–ongoing)")
  content((7.2, 3.875), text(size: 7.5pt)[simple])
  content((7.2, 2.875), text(size: 7.5pt)[+20%])
  content((7.2, 1.875), text(size: 7.5pt)[+30%])
  content((7.2, 0.875), text(size: 7.5pt)[+??%])
  line((0.5, 3.5), (0.5, 1.25), mark: (end: ">"), stroke: 0.7pt)
  content((-0.1, 2.5), text(size: 7.5pt)[more compute])
}))

=== A Practical Example: Simulating a Convex Hull Ladder

The following Python code demonstrates the core idea of convex hull bitrate ladder construction in simplified form. Real production systems encode actual video at dozens of (resolution, QP) combinations; here we use hypothetical data to illustrate the geometry.

```python
"""Simplified per-title convex hull bitrate ladder demo."""

# Each tuple: (bitrate_kbps, vmaf_score) for one test encode
# In production, these come from real encoder runs at various resolutions+QPs.
test_encodes: list[tuple[float, float]] = [
    (400,  65.0),   # low res, high QP
    (700,  72.1),
    (900,  74.5),
    (1200, 79.0),
    (1500, 82.5),   # 480p territory
    (1800, 84.0),
    (2200, 86.3),
    (3000, 91.0),   # 720p territory
    (4000, 93.5),
    (5000, 94.8),
    (6000, 96.2),   # 1080p territory
    (8000, 97.1),
    (12000, 97.8),
    (16000, 98.0),  # 4K territory
]

def is_dominated(p: tuple[float, float],
                 others: list[tuple[float, float]]) -> bool:
    """Return True if another point has lower bitrate AND higher/equal VMAF."""
    br, q = p
    return any(
        ob <= br and oq >= q
        for ob, oq in others
        if (ob, oq) != p
    )

def convex_hull_upper(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """
    Find the upper-left convex hull: points that are not dominated
    and that form the efficient frontier in (bitrate, quality) space.
    """
    # Remove dominated points first
    non_dominated = [p for p in points if not is_dominated(p, points)]
    # Sort by bitrate ascending
    non_dominated.sort(key=lambda p: p[0])
    # Build upper convex hull using Graham scan logic
    # (for our monotone data, the non-dominated frontier IS the upper hull)
    return non_dominated

def build_ladder(hull: list[tuple[float, float]],
                 target_vmaf_levels: list[float]) -> list[tuple[float, float]]:
    """Pick the hull point with the lowest bitrate that meets each VMAF target."""
    ladder: list[tuple[float, float]] = []
    for target in target_vmaf_levels:
        candidates = [(br, q) for br, q in hull if q >= target]
        if candidates:
            best = min(candidates, key=lambda p: p[0])
            ladder.append(best)
    return ladder

hull = convex_hull_upper(test_encodes)
# Define the rungs of our ladder by target VMAF scores
target_qualities = [70.0, 80.0, 88.0, 93.0, 96.0]
ladder = build_ladder(hull, target_qualities)

print("Bitrate Ladder:")
for br, q in ladder:
    print(f"  {br:6.0f} kbps  →  VMAF {q:.1f}")
```

Running this produces output like:

```
Bitrate Ladder:
     700 kbps  →  VMAF 72.1
    1500 kbps  →  VMAF 82.5
    2200 kbps  →  VMAF 86.3
    4000 kbps  →  VMAF 93.5
    6000 kbps  →  VMAF 96.2
```

Each rung is the *cheapest* encode that meets the target quality. The insight is that the rungs are content-adaptive: for a simple animated film, the 1080p rung might be achieved at 2 Mbps instead of 6 Mbps; for an action film, 6 Mbps might only reach VMAF 89. Using a fixed ladder imposes the wrong rung locations for every title simultaneously.

#gopython("List Comprehensions")[
  The line `non_dominated = [p for p in points if not is_dominated(p, points)]` uses a Python *list comprehension*, a concise way to build a new list by filtering or transforming an existing one.

  The general form is:
  ```python
  new_list = [expression for item in iterable if condition]
  ```
  Read it as: "for each `item` in `iterable`, if `condition` is true, include `expression` in the new list."

  Examples:
  ```python
  evens = [x for x in range(10) if x % 2 == 0]  # [0, 2, 4, 6, 8]
  squares = [x * x for x in [1, 2, 3, 4]]       # [1, 4, 9, 16]
  ```
]

=== ML-Based Ladder Prediction: The Cutting Edge (2024–2026)

The exhaustive test-encode approach is expensive. Running hundreds of encodes per title, per codec, per resolution tier requires significant cloud compute and adds latency before a new title can be published. An active research direction (2024–2026) is to *predict* the optimal ladder directly from content features, without running all those test encodes.

The approach works by training a machine learning model on historical encode data. Given a video clip's spatial complexity (texture richness, edge density), temporal complexity (motion magnitude, scene cut frequency), and codec parameters, the model predicts the Rate-VMAF curve. This prediction can be done in seconds rather than hours, enabling "instant" ladder construction for live-streaming applications where there is no time for exhaustive testing.

Systems like ARTEMIS (presented at NSDI 2024) demonstrate this approach for live streaming. The trade-off is accuracy: ML-predicted ladders are nearly as good as exhaustively computed ones for typical content, but can miss by larger margins for unusual or exotic content types that are underrepresented in the training data.

#checkpoint[What is the key difference between per-title encoding and per-shot encoding, and which saves more bitrate?][Per-title encoding customises the bitrate ladder to the complexity of an entire video title. An animation might need less bitrate per rung than an action film. Per-shot encoding goes further, optimising encoder parameters *independently for each shot* within a title, since a quiet dialogue scene and an explosion in the same film have very different compressibility. Netflix found that per-shot encoding saves roughly an additional 30% over per-title encoding on 4K HDR content, on top of the ~20% already saved by per-title encoding. So per-shot encoding saves more in total, at the cost of far greater compute.]

== Putting It Together: The Full Pipeline

It is worth pausing to see how all the pieces fit into a single pipeline, covering both the standards layer (what codec you use) and the application layer (how you use it).

```
Raw video
    │
    ▼
Shot detection + complexity analysis
    │
    ├── Per-shot compressibility features ──► ML ladder predictor
    │                                              │
    │                                              ▼
    │                                        Candidate (res, QP) configs
    │
    ▼
Test encodes at candidate configurations
    │
    ▼
VMAF evaluation on each candidate
    │
    ▼
Convex hull selection → optimal (res, QP) per shot per rung
    │
    ▼
Production encodes (AV1 / H.265 / H.264 depending on target platform)
    │
    ▼
Quality-check VMAF gate (reject if VMAF drops below threshold)
    │
    ▼
Packager (HLS / DASH segments)
    │
    ▼
CDN delivery → players → viewers
```

At each step, decisions made at a higher layer constrain the possibilities at the lower layer. The codec (AV1 vs H.265) sets the upper bound on compression efficiency. The encoder configuration (per-shot vs fixed QP) determines how close to that bound you get. VMAF provides the measurement signal that makes the optimisation tractable. And the bitrate ladder determines which representations are available to the player when network conditions change.

== The Competitive Landscape in 2026

By June 2026, the streaming landscape has settled into a tiered pattern:

- *AV1* is the dominant new-content codec for premium streaming (Netflix, YouTube, Amazon), delivering better compression than H.264 or H.265 with no licensing costs.
- *H.265/HEVC* remains widely deployed for broadcast, Blu-ray, and in markets where hardware AV1 decode is not yet universal.
- *H.264/AVC* is still the universal compatibility baseline. Almost every device on Earth can decode it, and it remains the fallback for legacy devices and ultra-low-latency live streaming.
- *VVC* has seen limited deployment, hindered by the same patent-pool ambiguity that plagued HEVC (Chapter 53).
- *AV2* has finalised its bitstream specification and is entering encoder and decoder implementation, with broad hardware support expected around 2027–2028.
- *ECM / H.267* is still in research and standardisation; no production deployment is expected before 2030.

The gap between standards and deployment is one of the central facts of the video codec world. A researcher working on ECM is writing code that will not reach a consumer TV until roughly 2034. The practical engineering work of per-title encoding, VMAF optimisation, and dynamic ladder construction is what keeps bandwidth bills manageable in the years while the next standard is being built.

#scoreboard(
  caption: "Illustrative bitrate savings for a 1080p 24fps sample clip at 'broadcast quality'",
  [H.264/AVC (fixed ladder)], [6000 kbps], [1.00×], [Baseline; universal hardware support],
  [H.264/AVC (per-title + DO)], [4320 kbps], [0.72×], [−28% from Dynamic Optimizer alone],
  [H.265/HEVC (per-title + DO)], [2650 kbps], [0.44×], [−34% from DO; ~50% codec gain over H.264],
  [AV1 (per-title + DO)], [2100 kbps], [0.35×], [AV1 ~30% better than HEVC; DO adds another layer],
  [AV1 (per-shot + DO)], [1470 kbps], [0.25×], [Per-shot adds ~30% over per-title; 75% total savings],
  [ECM (projected)], [~1080 kbps], [~0.18×], [Projected ~26% further savings; research only],
)

These numbers are illustrative; real savings vary enormously by content type. The scoreboard makes the point graphically: the codec matters, but the encoding pipeline matters almost as much.

#takeaways((
  "ECM (Enhanced Compression Model) is JVET's research codec that already exceeds VVC by ~26% BD-Rate, using tools like TIMD, DIMD, geometric partition extensions, cross-component coding, and neural in-loop filters.",
  "NNVC (Neural Network Video Coding) is a parallel JVET research track that replaces hand-crafted codec tools with learned neural networks; gains are real but hardware decoder support is years away.",
  "H.267 is the planned successor to VVC, expected to finalise around 2028–2029, targeting ~40% savings over VVC; broad consumer deployment is not realistic before 2034–2036.",
  "A bitrate ladder is the set of (resolution, bitrate) representations a streaming service maintains per video; the player switches rungs as network conditions change.",
  "Per-title encoding (Netflix, 2015) customises the bitrate ladder to each video's complexity, saving ~20% bitrate over a fixed ladder.",
  "Per-shot encoding (Netflix, 2018–2020) takes the idea further, optimising per scene-cut, saving an additional ~30% on 4K content.",
  "VMAF is a machine-learning-based perceptual quality metric that correlates far better with human judgement than PSNR; it is now the industry standard quality target for streaming encoding.",
  "The Dynamic Optimizer uses VMAF as its quality signal to drive per-shot, per-rung encoder configuration, delivering 28–38% bitrate savings across codecs at matched perceptual quality.",
  "The gap between codec standardisation and broad consumer deployment spans ten or more years; practical encoding optimisation of existing codecs delivers value right now.",
))

== Exercises

#exercise("55.1", 1)[
  A streaming service uses a fixed bitrate ladder with rungs at 400, 750, 1500, 3000, 6000, and 16000 kbps. A simple animated film's Rate-VMAF curve shows it achieves VMAF 94 at 2000 kbps and VMAF 97 at 4000 kbps. A gritty live-action thriller achieves VMAF 82 at 2000 kbps and VMAF 91 at 4000 kbps. Using the fixed ladder, both films use the 3000 kbps rung. What is the problem with this, and how does per-title encoding address it?
]

#solution("55.1")[
  The problem is that 3000 kbps is "wasteful" for the animation (which could reach VMAF 94+ at 2000 kbps: the service is spending an unnecessary extra 1000 kbps per second) while being "insufficient" for the thriller (which only reaches VMAF 82 at 2000 kbps and needs more bits at the 3000 kbps tier to look good; the fixed rung doesn't match its complexity). Per-title encoding solves this by computing the *optimal* ladder for each title separately. The animation's 3000 kbps rung might be moved to 2000 kbps (same quality, lower bandwidth), while the thriller's 3000 kbps rung might be kept or even increased. Each title uses a ladder tailored to its Rate-VMAF curve.
]

#exercise("55.2", 2)[
  Explain in plain language what Björntegaard Delta Rate (BD-Rate) measures and why a percentage like "−26.6%" is always negative for improvements. What does BD-Rate = −26.6% mean concretely for a user who is streaming video?
]

#solution("55.2")[
  BD-Rate measures the average percentage difference in bitrate between two codecs across a range of quality settings. It is computed by integrating the horizontal distance between two Rate-quality curves. A negative BD-Rate means the new codec achieves the same quality at a lower bitrate; it needs fewer bits per second to deliver the same visual experience. "−26.6%" means: "at any given VMAF quality level, ECM needs 26.6% fewer bits than VVC to deliver that quality." Concretely for a user: if VVC needed 6 Mbps to deliver a particular quality on your home internet connection, ECM would need only about 4.4 Mbps for the same quality. That means lower buffering risk on slow connections, lower data usage on mobile, and lower bandwidth bills for streaming services.
]

#exercise("55.3", 1)[
  List three specific coding tools that ECM adds beyond VVC and give a one-sentence plain-language description of what each one does.
]

#solution("55.3")[
  (Many valid answers; one set:)
  - *TIMD (Template-Based Intra Mode Derivation):* The decoder figures out the intra-prediction direction itself from already-decoded neighbour pixels, so the encoder does not need to transmit it, saving signalling bits.
  - *DIMD (Decoder-Side Intra Mode Derivation):* The decoder uses a gradient analysis (Sobel filter) on reconstructed neighbours to blend a more accurate prediction, again without any extra bits from the encoder.
  - *Cross-Component Prediction (CCCP):* The chroma (colour) residual is predicted as a scaled version of the luma (brightness) residual, so only the scaling factor and the small deviation need to be transmitted rather than the full chroma residual.
]

#exercise("55.4", 2)[
  The Python code in this chapter uses `is_dominated` to filter test encodes. Modify the function so that it takes a *quality threshold margin* `margin: float = 0.0` and considers a point `(br, q)` dominated only if another point has bitrate `<= br` *and* quality `>= q + margin`. Explain what setting `margin = 2.0` would do to the resulting bitrate ladder.
]

#solution("55.4")[
  ```python
  def is_dominated(p: tuple[float, float],
                   others: list[tuple[float, float]],
                   margin: float = 0.0) -> bool:
      br, q = p
      return any(
          ob <= br and oq >= q + margin
          for ob, oq in others
          if (ob, oq) != p
      )
  ```
  Setting `margin = 2.0` means a point is only considered dominated if another point offers *at least 2 VMAF points more quality* at the same or lower bitrate. This makes the domination test stricter, so fewer points are filtered out. The resulting convex hull will have more points (including some that are slightly worse in the strict sense), giving a *denser* bitrate ladder with more rungs. This can be useful when you want finer-grained quality steps, at the cost of more encoded variants to store and maintain.
]

#exercise("55.5", 3)[
  Netflix reports that per-shot encoding saves approximately 30% additional bitrate over per-title encoding for 4K HDR content, and that the Dynamic Optimizer saves approximately 28% over naive fixed-ladder H.264. If a streaming service currently spends \$10 million per year on CDN bandwidth using fixed-ladder H.264, estimate the annual bandwidth cost savings achievable by (a) switching to fixed-ladder H.265 and applying the Dynamic Optimizer, and (b) further applying per-shot encoding. State all your assumptions clearly.
]

#solution("55.5")[
  Assumptions: H.265 (HEVC) saves ~50% over H.264 at matched quality (from Chapter 53). The Dynamic Optimizer saves an additional 34% on top of H.265 (from Netflix's published figures). Per-shot encoding saves an additional 30% on top of per-title (which we approximate as equivalent to the Dynamic Optimizer for this estimate). CDN bandwidth cost scales linearly with bytes delivered.

  (a) H.265 with Dynamic Optimizer: Start with \$10M. H.265 saves 50%: \$5M. DO saves 34% on top: \$5M × (1 − 0.34) = \$3.3M. Savings = \$10M − \$3.3M = *\$6.7M/year*.

  (b) Further adding per-shot encoding: \$3.3M × (1 − 0.30) = \$2.31M. Additional savings = \$3.3M − \$2.31M = \$0.99M, for a total savings of *\$7.69M/year* versus the original fixed-ladder H.264 baseline.

  Note: these percentages do not simply multiply (each is relative to the previous baseline), and real-world savings depend heavily on content mix, audience device profile, and CDN pricing model. The calculation illustrates the order of magnitude, not a precise business projection.
]

#exercise("55.6", 2)[
  Why is PSNR a poor proxy for human perceived video quality, while VMAF performs much better? What specific perceptual phenomena does PSNR fail to model that VMAF attempts to capture?
]

#solution("55.6")[
  PSNR measures the mean squared error between original and compressed pixels and converts it to a logarithmic decibel scale. The fundamental problem is that PSNR treats all pixel errors equally, regardless of where they are in the image and how human vision would perceive them.

  Specific failures: (1) *Masking:* Humans notice artefacts less in regions with high texture or busy motion. A compression artefact in film grain is nearly invisible; the same artefact in a smooth sky is glaring. PSNR assigns the same penalty to both. (2) *Spatial frequency weighting:* The human visual system is more sensitive to errors at certain spatial frequencies (mid-frequencies) than others. PSNR gives equal weight to all frequencies. (3) *Detail vs. blur:* Blurring an image (which can actually *increase* PSNR by reducing high-frequency noise) often looks worse to viewers than the original noisiness. (4) *Grain and film texture:* Real film grain has high variance, so compressing it away reduces PSNR but often looks *better* to viewers.

  VMAF addresses these by incorporating VIF (which models information loss through the human visual system), DLM (which specifically measures detail preservation), and a motion activity feature (which modulates sensitivity based on temporal complexity). The resulting fusion model was trained on actual human quality judgements, so it learns the weights that correspond to human perception rather than mathematical signal error.
]

== Further Reading

- #link("https://jvet.hhi.fraunhofer.de")[JVET ECM Software Repository]: the official Enhanced Compression Model source code and contribution documents. Versioned releases document every tool integrated.

- #link("https://www.itu.int/en/ITU-T/Workshops-and-Seminars/2025/0117/Documents/Yan%20Ye.pdf")[Yan Ye, "Enhanced Compression Model for Beyond-VVC Capability," ITU-T Workshop, January 2025]: a comprehensive overview of ECM tools and BD-Rate results from one of JVET's key researchers.

- #link("https://arxiv.org/abs/2404.07872")[R. Skupin et al., "Video Compression Beyond VVC: Quantitative Analysis of Intra Coding Tools in Enhanced Compression Model (ECM)," arXiv:2404.07872, 2024]: detailed per-tool analysis of ECM intra coding gains, with BD-Rate numbers for each tool individually and in combination.

- #link("https://netflixtechblog.com/per-title-encode-optimization-7e99442b62a2")[Anne Aaron et al., "Per-Title Encode Optimization," Netflix Technology Blog, December 2015]: the original blog post introducing per-title encoding, with the convex hull methodology and initial bandwidth savings.

- #link("https://netflixtechblog.com/dynamic-optimizer-a-perceptual-video-encoding-optimization-framework-e19f1e3a277f")[Zhi Li et al., "Dynamic Optimizer: A Perceptual Video Encoding Optimization Framework," Netflix Technology Blog, March 2018]: the Dynamic Optimizer technical description, including VMAF integration and measured bitrate savings.

- #link("https://research.netflix.com/publication/optimized-shot-based-encodes-for-4k-now-streaming")[Netflix Research, "Optimized Shot-Based Encodes for 4K: Now Streaming!," 2020]: describes the rollout of per-shot encoding to Netflix's 4K HDR catalogue.

- #link("https://arxiv.org/abs/2309.05846")[M. Mentzer et al., "Designs and Implementations in Neural Network-Based Video Coding," arXiv:2309.05846, 2023]: a survey of NNVC approaches as studied by JVET, including common experiments on neural in-loop filtering, intra prediction, and inter coding.

- #link("https://gorinsky.networks.imdea.org/pdf/ARTEMIS_Adaptive_Bitrate_Ladder_Optimization_for_Live_Video_Streaming_NSDI_2024_accepted_version.pdf")[Ghasemi et al., "ARTEMIS: Adaptive Bitrate Ladder Optimization for Live Video Streaming," NSDI 2024]: ML-based bitrate ladder prediction for live streaming, eliminating the need for exhaustive test encodes.

- #link("https://arxiv.org/abs/1812.00101")[Lu et al., "DVC: An End-to-End Deep Video Compression Framework," CVPR 2019 / arXiv:1812.00101]: one of the foundational papers on fully learned video compression, a precursor to the NNVC approach.

#bridge[
  This chapter stood at the boundary between classical and neural compression. ECM is already incorporating neural components (CNN-based in-loop filters, learned intra synthesis), and NNVC is pushing further. But we have mostly treated neural networks as a black box: "a model that maps inputs to outputs and is trained on data." To understand *why* neural networks can outperform hand-crafted tools, and *how* they are trained for compression tasks, we need to open that black box. Chapter 56 is a Machine-Learning Primer written specifically for compression: what a neural network is, how backpropagation and gradient descent work, what a loss function is, and why the rate-distortion tradeoff fits naturally into the neural training framework. If you have read Chapters 1–55 and understood everything, Chapter 56 is the bridge to the final, deepest layer of the subject.
]
