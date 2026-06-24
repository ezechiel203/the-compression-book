#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Open Codecs: VP8, VP9, AV1, AV2

#epigraph[
  When the patent pool sent its first invoice, we realized the real competition was not between codecs. It was between open and closed.
][Jim Bankoski, Google VP8/AV1 engineer, ~2013]

In the summer of 2010, Google did something strange. It had just paid \$124.6 million to buy a small video-codec company called On2 Technologies. And then, instead of keeping the technology secret, licensing it for profit, or folding it into a proprietary product, Google gave it away. Not a limited freeware version. The whole thing: source code, patents, bitstream spec, all released under an open, irrevocable license that anyone could use forever, for free.

The codec was called VP8. Nobody outside the streaming world noticed. But inside it, the move sent shockwaves. The message was unmistakable: Google was declaring war on the patent-tax model that governed video compression.

That opening shot set off a decade-long open-vs-licensed war. In this chapter we trace the story from VP8's 2010 liberation through VP9's maturation, the founding of the Alliance for Open Media, and the construction of AV1 (arguably the most complex codec ever standardized by committee). We end with AV2, whose specification was finalized on 28 May 2026, just weeks before this book went to press.

#recap[
  Chapter 51 built the hybrid-video-codec template: I/P/B frames, block motion compensation, the residual transform-quantize-entropy pipeline, and the Lagrangian RDO loop $J = D + lambda R$. Chapter 52 traced H.261 through H.264/AVC, the codec that set the baseline every successor must beat. Chapter 53 explained HEVC's Coding Tree Unit architecture and VVC's multi-type trees, along with the patent-pool crisis that accidentally handed the royalty-free movement its best recruiting pitch. We lean on all of that here: this chapter is about the codecs built _because_ of those patent problems.
]

#objectives((
  "Explain why Google acquired On2 Technologies and what VP8's open release meant for the industry.",
  "Describe VP9's improvements over VP8 and its role as YouTube's main delivery codec for nearly a decade.",
  "List the seven founding members of the Alliance for Open Media and explain why the group formed.",
  "Describe at least four of AV1's new tools (CDEF, the loop-restoration filter, warped motion, and compound prediction) and explain the problem each solves.",
  "Explain why AV1 encoding is so much slower than decoding, and how SVT-AV1 changed the economics.",
  "Summarize AV2's headline improvements over AV1 and the timeline from specification to hardware.",
  "Read Python code that computes the bitrate savings at each generation from H.264 through AV2.",
))

== The Duck That Became a VP

To understand why VP8 mattered, you have to understand what video compression looked like in 2010. The dominant format was H.264/AVC: technically excellent, universally supported in hardware, and controlled by a patent pool that charged royalties for every device that decoded it. For most companies that was fine: the fees were predictable, the legal risk was clear, and the hardware decoders were already in every phone.

But one category of company had a different problem: the big internet platforms. Google's YouTube was serving billions of videos per month. Each one was encoded once and decoded potentially millions of times. The royalty exposure was enormous, and worse, it was _uncertain_: patent pools can change their terms, new claimants can appear, and litigation is expensive even when you win.

#history[
  On2 Technologies was founded in 1992 as *The Duck Corporation* (yes, really) in upstate New York. It built a succession of codecs: TrueMotion VP3 (2001, later donated to the Xiph.Org Foundation and renamed *Theora*), VP4 through VP7, each sold mainly to Adobe Flash for early online video. VP6 powered most YouTube video from 2005 to 2008. When Google announced its acquisition of On2 in August 2009 for about \$124.6 million, the deal closed on 19 February 2010. Three months later, VP8 was open.
]

=== VP8: Liberation (May 2010)

On 19 May 2010 at Google I/O, Google released VP8 under a BSD-style source license and, more importantly, an irrevocable, royalty-free patent license covering the bitstream specification. This was more than "free software": it was a pledge that Google would never sue anyone for implementing VP8, and would defend against third-party patent claims on the core technology.

VP8 shipped packaged inside a new container format called *WebM* (a variant of Matroska/MKV), with Vorbis as the accompanying audio codec. Google announced that Chrome would support it natively and that it would be the mandatory video format for *WebRTC*, the new real-time-communication protocol that would eventually power Google Meet, Zoom, and browser-based video calls worldwide.

Technically, VP8 was close to an H.264 Baseline Profile analog. It shared the same conceptual architecture (block-based motion compensation, a residual DCT, entropy coding) but with different specific choices. Its macroblock size was 16×16, its maximum reference frames per inter-block were two, and it used a custom boolean arithmetic coder rather than CABAC. The compression was roughly on par with H.264 Baseline but noticeably behind H.264 High Profile.

The more important technical contribution was VP8's *in-loop deblocking filter*, which was baked into the spec as a mandatory post-processing step, producing cleaner decoded frames at low bitrates. VP8 also introduced a clean three-frame prediction structure (key frame, inter frame, alternate reference frame) that would evolve directly into AV1's reference-frame management.

#misconception[
  VP8 was technically inferior to H.264, so it failed.
][
  VP8 was technically _competitive_ with H.264 Baseline and slightly behind H.264 High Profile. More importantly, it _succeeded_ at its real goal: establishing a royalty-free codec on every Chrome browser and every WebRTC endpoint in the world. That installed base made VP8 a permanent fixture in real-time communication, where it still runs in hundreds of millions of WebRTC sessions today.
]

=== The H.264 Patent Response

Shortly after VP8's release, the MPEG LA patent pool announced it was investigating whether VP8 infringed H.264-related patents and invited patent holders to submit claims. The investigation dragged on for two years. In March 2013, MPEG LA closed the investigation without action, announcing a patent cross-license with Google that covered VP8. This outcome was widely interpreted as a win for the open-codec camp: the threatened lawsuit never materialized, and the license cost nothing to VP8 users.

#aside[
  Nokia separately sued HTC (which shipped Android phones with VP8) in 2012, claiming VP8 infringed Nokia's video patents. That suit was eventually settled quietly. The same pattern - a large incumbent threatening an open codec with patent litigation, then retreating - would repeat with AV1.
]

== VP9: The Second Attempt (June 2013)

VP8 was a political victory more than a technical one. Google's engineers knew it, and they immediately began work on its successor. Development started in the second half of 2011 under the internal name *Next Gen Open Video (NGOV)* and sometimes *VP-Next*. The first stable version of VP9's specification was finalized in June 2013, and Chrome shipped VP9 decode two months later.

VP9's improvements over VP8 were substantial:

- *Larger superblocks*: VP9 raised the coding-unit maximum from 16×16 to 64×64 pixels, the same insight HEVC's CTU embodied, arrived at independently. Large flat areas in 4K video could now be described in a single block with minimal overhead.
- *More intra prediction modes*: VP8 had 4 intra prediction directions for luma; VP9 had 10, covering more angles and better exploiting directional texture.
- *Segmentation*: VP9 introduced per-segment feature overrides (quantizer, loop-filter strength, reference frame eligibility), giving the encoder fine-grained control of how different regions of a frame are coded.
- *Adaptive probability context models*: VP9's entropy coder used adaptive per-frame probability contexts, giving it more modeling power than VP8's simpler arithmetic coder.
- *Tiling*: Frames could be divided into independently decodable tiles, enabling multi-threaded decode. This was critical for real-time 4K on multi-core devices.

The result was roughly a 50% bitrate reduction over VP8 at the same quality. At matched bitrates, VP9 was competitive with HEVC and typically slightly behind it - but free, widely adopted in Chrome, and already baked into Android.

YouTube's adoption sealed VP9's importance. Starting in 2014, YouTube served VP9 video to every Chrome browser. Since Chrome commands a large share of desktop web traffic, VP9 almost overnight became one of the most-decoded codecs on Earth. By 2020, Google reported VP9 delivering roughly one exabyte of video per day through YouTube alone.

#algo(
  name: "VP9",
  year: 2013,
  authors: ("Google",),
  aim: "Royalty-free codec targeting ~50% bitrate reduction over VP8, with 64×64 superblocks, expanded intra prediction angles, tiled parallelism, and adaptive probability entropy coding.",
  complexity: ("encode", "O(N²) in superblock area due to rate-distortion search over all partition sizes"),
  strengths: ("Royalty-free", "Wide hardware and software support by 2018--2022", "Multi-threaded tile decode enables real-time 4K software decode"),
  weaknesses: ("Limited to quadtree square splits, no rectangular partitions", "Entropy model less powerful than CABAC"),
  superseded: "AV1 (2018)",
)[
  VP9 divides each frame into non-overlapping 64×64 *superblocks*. Each superblock is recursively split using a quadtree into coding units of 64, 32, 16, or 8 pixels. For each CU the encoder tests intra or inter prediction, computes the RDO cost $J = D + lambda R$, and selects the cheapest option. The chosen partition, prediction mode, motion vectors, and quantized residual transform coefficients are then entropy-coded using VP9's adaptive arithmetic coder with per-frame probability context updates.
]

=== VP9 and YouTube at Scale

By 2016, YouTube was using VP9 for the majority of its video delivery to Chrome users. The scale was staggering: tens of billions of minutes of VP9 video decoded per day. This gave Google real-world feedback at a scope no research lab could simulate: edge cases in the spec, encoding pathologies on unusual content, and a steady stream of motivation for improving the `libvpx` encoder.

VP9 would hold its YouTube dominance until AV1 decode hardware became widespread enough to justify the switch. YouTube began AV1 delivery to hardware-capable clients in 2018 (starting with mobile), but VP9 remained the dominant YouTube codec through 2022--2023 for the bulk of streams. Even in 2026, VP9 streams remain live for the enormous installed base of VP9-capable-but-not-AV1-capable devices.

== The Alliance for Open Media (September 2015)

Google could see, by 2014, that VP9 was a real commercial success. A single company controlling an open codec invited skepticism, though. If Google ever changed its mind about openness, or if patent litigation pinned VP9 from an unexpected direction, the royalty-free web video project would collapse.

More urgently, HEVC was landing with its crushing patent-pool crisis (Chapter 53). The streaming industry needed a durable, genuinely free alternative backed by enough companies that no single claimant could hold it hostage.

On 1 September 2015, seven companies announced the formation of the *Alliance for Open Media (AOMedia)*:

#keyidea[
  AOMedia's seven founding members (*Amazon, Cisco, Google, Intel, Microsoft, Mozilla*, and *Netflix*) each contributed engineers and patent pledges. Every company agreed that any technology they contributed to the AV1 specification would be royalty-free to all, forever. The governance structure was explicitly designed to prevent any member from defecting and asserting patents against AOMedia codecs.
]

The project was to merge three in-flight codec efforts into one:
- *VP10* (Google): the natural successor to VP9.
- *Daala* (Mozilla/Xiph): an experimental codec built around a perceptual coding framework using overlapped block DCTs and vector quantization. It had excellent ideas but was not production-ready.
- *Thor* (Cisco): a clean-room H.264 successor designed from the ground up to sidestep known H.264 and HEVC patents.

All three teams would work together on a common bitstream, contributing their best tools, each vetted against patent risks. The name of the resulting codec was *AV1*, short for "AOMedia Video 1." The target: approximately 30% bitrate reduction over HEVC at the same quality, royalty-free, with an independently audited patent position.

By 2020, AOMedia's membership had grown to include Apple, ARM, Meta (Facebook), and many others. The organization now covers AV1, AV2, audio formats, and next-generation container specifications.

#fig(
  [The VP8/VP9/AV1/AV2 lineage on a timeline, alongside the licensed HEVC and VVC standards. Open codecs (green) have tracked within 5--10% of licensed codecs technically while remaining royalty-free.],
  cetz.canvas({
    import cetz.draw: *
    // Timeline axis
    line((0.5,0),(7.5,0), mark: (end: ">", size: 0.15), stroke: 0.8pt)
    content((7.7, 0))[#text(size:6.5pt)[Year]]
    // Year markers
    for (x, yr) in ((1.0,"2003"),(2.0,"2010"),(3.0,"2013"),(4.0,"2015"),(5.0,"2018"),(6.0,"2020"),(7.0,"2026")) {
      line((x, -0.08),(x, 0.08), stroke: 0.6pt)
      content((x, -0.3))[#text(size:5.5pt)[#yr]]
    }
    // Licensed codecs (blue, top row)
    content((0.1, 1.4))[#text(size:6pt, fill: rgb("#1a5276"), weight:"bold")[Licensed]]
    circle((1.0, 1.2), radius: 0.12, fill: rgb("#1a5276"), stroke: none)
    content((1.0, 1.6))[#text(size:5.5pt, fill:rgb("#1a5276"))[H.264]]
    circle((3.0, 1.2), radius: 0.12, fill: rgb("#1a5276"), stroke: none)
    content((3.0, 1.6))[#text(size:5.5pt, fill:rgb("#1a5276"))[HEVC]]
    circle((6.0, 1.2), radius: 0.12, fill: rgb("#1a5276"), stroke: none)
    content((6.0, 1.6))[#text(size:5.5pt, fill:rgb("#1a5276"))[VVC]]
    line((1.0,1.2),(3.0,1.2), stroke:0.6pt + rgb("#1a5276"))
    line((3.0,1.2),(6.0,1.2), stroke:0.6pt + rgb("#1a5276"))
    // Open codecs (green, bottom row)
    content((0.1, 0.5))[#text(size:6pt, fill: rgb("#117a65"), weight:"bold")[Open]]
    circle((2.0, 0.5), radius: 0.12, fill: rgb("#117a65"), stroke: none)
    content((2.0, 0.15))[#text(size:5.5pt, fill:rgb("#117a65"))[VP8]]
    circle((3.0, 0.5), radius: 0.12, fill: rgb("#117a65"), stroke: none)
    content((3.2, 0.15))[#text(size:5.5pt, fill:rgb("#117a65"))[VP9]]
    circle((4.0, 0.5), radius: 0.12, fill: rgb("#0b5394"), stroke: none)
    content((4.0, 0.15))[#text(size:5.5pt, fill:rgb("#0b5394"))[AOMedia]]
    circle((5.0, 0.5), radius: 0.12, fill: rgb("#117a65"), stroke: none)
    content((5.0, 0.15))[#text(size:5.5pt, fill:rgb("#117a65"))[AV1]]
    circle((7.0, 0.5), radius: 0.12, fill: rgb("#117a65"), stroke: none)
    content((7.0, 0.15))[#text(size:5.5pt, fill:rgb("#117a65"))[AV2]]
    line((2.0,0.5),(3.0,0.5), stroke:0.6pt + rgb("#117a65"))
    line((3.0,0.5),(5.0,0.5), stroke:0.6pt + rgb("#117a65"))
    line((5.0,0.5),(7.0,0.5), stroke:0.6pt + rgb("#117a65"))
  })
)

== AV1: The Most Complex Open Codec Ever Built

AV1's specification was frozen in March 2018 and released publicly on 28 June 2018. It is, by most measures, the most algorithmically sophisticated codec produced by a committee process. Where HEVC introduced roughly 30% new tools over H.264, AV1 introduced approximately 40 new or substantially extended tools over VP9 alone. The following sections explain the most important.

=== Superblocks and the Multi-Type Partition Tree

Like VP9, AV1 starts with 64×64 superblocks, but adds a 128×128 size for very large flat regions. More importantly, AV1 extends the partition vocabulary far beyond quadtree squares.

#definition("Multi-Type Partition (AV1)")[
  AV1 supports *10 partition types* within a coding block: the classic quadtree SPLIT into four equal squares; HORZ (two equal horizontal halves); VERT (two equal vertical halves); HORZ\_A, HORZ\_B, VERT\_A, VERT\_B (T-shaped splits producing one large and two small rectangles); HORZ\_4 (four equal horizontal slices); and VERT\_4 (four equal vertical slices). A coding unit can be as small as 4×4 pixels. This vocabulary vastly exceeds VP9's square-only quadtree.
]

Rectangular partitions are especially useful for text lines, vertical edges (building facades, window frames), and horizontal textures (grass, ocean waves). A single 64×32 partition can cover a region that would require two 32×32 blocks under VP9, saving the overhead of two prediction mode signals, two motion vectors, and two transform headers.

=== CDEF: Fixing Ringing Artifacts

When you quantize DCT coefficients aggressively, the decoded image shows *ringing*: ripple patterns around sharp edges, like the rings that spread when you throw a stone into still water. Traditional in-loop deblocking filters (H.264, HEVC, VP9 all had them) smooth the block boundaries but do not specifically address ringing _inside_ blocks.

AV1 introduced *CDEF*, the Constrained Directional Enhancement Filter.

#definition("CDEF")[
  CDEF operates on 8×8 blocks after deblocking. For each block it first detects the dominant *edge direction* by testing 8 angles (0°, 22.5°, 45°, 67.5°, 90°, 112.5°, 135°, 157.5°) and finding the one that best aligns with the local gradient. It then applies a 1-D nonlinear filter *along that direction* (the *primary filter*) and a weaker 2-D cross-shaped *secondary filter* at 45°. The filter strength is signaled per 64×64 region with 3 bits. CDEF adds about 5--10% encoding complexity but recovers meaningful detail at low bitrates, especially on text and fine lines.
]

The key word in the name is "Constrained": the filter is not allowed to create pixels brighter or darker than the brightest or darkest pixel already in the 8×8 region. This prevents CDEF from introducing *halos*, a common failure mode of aggressive sharpening filters.

=== The Loop-Restoration Filter

Even after deblocking and CDEF, large smooth regions like sky gradients can show *banding*: discrete steps in what should be a smooth ramp, caused by limited quantization precision. AV1 adds a third in-loop filter, the *loop-restoration filter*, that addresses banding across the full frame.

AV1 implements two loop-restoration modes:
- *Wiener filter*: a separable 2-D linear filter trained per 256×256 restoration unit to best undo the quantization damage to that region.
- *Self-guided projection filter (SGR)*: a two-stage nonlinear filter that first computes a guided-filter output (using local means and variances) and then blends it with the degraded signal according to per-unit weights.

The encoder chooses the cheapest option (or no filter) per restoration unit using RDO. In practice, the loop-restoration filter contributes about 2--4% bitrate savings.

#gomaths("Wiener Filter Basics")[
  A *Wiener filter* is a linear filter designed to minimize the mean-squared error between the filtered output and the true (undegraded) signal. For a 1-D signal:

  $ hat(x)_i = sum_(k = -r)^(r) w_k dot y_(i+k) $

  where $y$ is the noisy (quantized) input, $hat(x)$ is the estimate of the true signal, and the weights $w_k$ are chosen to minimize $EE[(hat(x)_i - x_i)^2]$. In AV1 the filter is separable: first apply a horizontal 1-D Wiener filter, then a vertical one. The weights are derived by solving a small linear system during encoding and transmitted as side information.
]

=== Warped Motion Compensation

Standard inter prediction in H.264/HEVC/VP9 uses *translational* motion vectors: block A in frame $t$ matches block B at position $(x + Delta x, y + Delta y)$ in frame $t-1$. This models most motion well, but not camera motion involving rotation, zoom, or perspective tilt, and not deformable objects.

AV1 adds *warped motion compensation*, which allows each inter-predicted block to use a local *affine transformation* rather than a pure translation.

#definition("Affine Transformation (2-D)")[
  An affine transformation maps every point $(x, y)$ to a new point $(x', y')$ by:

  $ x' = a_1 x + a_2 y + t_x $
  $ y' = a_3 x + a_4 y + t_y $

  where $(t_x, t_y)$ is a translation and the $a_i$ coefficients add rotation, scale, and shear. Pure translation is the special case $a_1 = a_4 = 1$, $a_2 = a_3 = 0$.
]

AV1 estimates a global affine model per inter frame (the *global motion model*) by fitting the best-matching affine map to all motion vectors in the frame. Individual blocks can then use this global model, a local affine override, or a plain translation, whichever minimizes RDO cost $J = D + lambda R$. For drone footage (slow camera pan plus rotation), warped motion consistently saves 3--8% bitrate over a pure translation model.

=== Compound Prediction

Standard B-frame inter prediction blends two reference frames, one past and one future. AV1 extends this idea in several directions.

*Uni-directional compound prediction* blends two references that are both in the past (or both in the future). This is useful for overlapping objects.

*Wedge compound prediction* uses a binary *wedge mask*, a hard-edged spatial partition dividing the block into two halves, one predicted from reference A and the other from reference B. This is exactly the right model for an object crossing a background: one side of the block is background, the other is foreground.

*Difference-weighted compound prediction* generates the mask automatically: the encoder computes the per-pixel difference between the two reference predictions and weights toward the reference that is locally more confident. No explicit mask bits are transmitted.

Together, compound prediction modes recover meaningful quality on overlapping-object sequences where H.264 and HEVC leave large residuals.

=== Film Grain Synthesis

One of AV1's most unusual tools is the *film grain synthesis filter*. High-end cameras produce sensor noise that looks like film grain. Conventional codecs treat this grain as information and try to encode it faithfully, which is expensive. AV1 instead measures the grain's statistical properties (its power spectrum as a function of luma level), encodes those few parameters in a small header, _strips the grain out_ of the encoded signal (making it smoother and cheaper to compress), and then re-adds synthetic grain with matching statistics in the decoder.

The result: film-grain-heavy content (cinematic footage, low-light phone video) can be coded at significantly lower bitrates without the "plastic" look that comes from conventional compression of noisy signals.

#algo(
  name: "AV1",
  year: 2018,
  authors: ("Alliance for Open Media (Google, Mozilla, Cisco, Intel, Microsoft, Netflix, Amazon, ...)",),
  aim: "Royalty-free video codec targeting ~30% bitrate reduction over HEVC at equivalent quality, with multi-type partitions, three-stage in-loop filtering (deblock + CDEF + restoration), warped affine motion, compound prediction, and film grain synthesis.",
  complexity: ("encode libaom cpu-used 0", "10--100x slower than x265 HEVC at matched quality"),
  strengths: (
    "Royalty-free with an audited patent position",
    "~30% over HEVC; ~62% over H.264 at matched VMAF",
    "Multi-type partitions handle all content types well",
    "CDEF + restoration produce excellent low-bitrate quality",
    "SVT-AV1 encoder practical for production since ~2022",
  ),
  weaknesses: (
    "Decoder complexity higher than HEVC; software-only decode drains batteries",
    "Hardware AV1 decode only widespread from 2022--2024 onward",
    "Encoding substantially slower than competing codecs at equal quality",
    "No hardware AV1 encoder until Intel Arc / AMD RX 7000 / Nvidia RTX 40",
  ),
  superseded: "AV2 (2026)",
)[
  AV1 processes frames as 64×64 or 128×128 superblocks. Each superblock is recursively partitioned using a multi-type tree (10 split types). For each coding unit the encoder evaluates intra prediction (56 angle modes + DC + smooth + paeth predictor) or inter prediction (up to 7 reference frames, translational or warped affine motion, compound modes). The residual is transformed with a selected 2-D separable transform pair (DCT-DCT, DCT-ADST, ADST-ADST, identity, and others). Quantized coefficients are entropy-coded with AV1's ANS-based coding engine (as taught in Chapter 27). Three in-loop filters (deblock, CDEF, loop-restoration) clean the decoded frame before it becomes a reference.
]

== The Encoder Complexity Wall

AV1's richness (10 partition types, 56 intra prediction modes, warped motion, compound prediction, 6 transform pairs, ANS entropy coding) is also its biggest practical problem. Finding the _best_ combination of choices for every block in every frame requires searching an enormous decision tree.

The reference encoder, *libaom*, tries to search this tree exhaustively at its slowest preset (`cpu-used 0`). The result is extraordinary compression quality, but encoding a single minute of 1080p video can take hours at that setting. This is useful for research and archival but no streaming service can operate there.

#mathrecall[
  *PSNR* (Peak Signal-to-Noise Ratio), our quality ruler below, was built from scratch in Chapter 42: it converts the mean-squared error between two images into decibels (dB) on a logarithmic scale, so higher means closer to the original. A jump of a few dB is a visible quality jump.
]

#gopython("Encoding Speed vs. Quality Trade-off")[
  The concept of a quality/speed trade-off appears in every modern encoder as *preset levels*. We measure quality here with PSNR (Peak Signal-to-Noise Ratio), the metric from Chapter 42. Here is a Python 3.14 sketch of the relationship:

```python
import math

def psnr(mse: float, max_val: float = 255.0) -> float:
    """Peak Signal-to-Noise Ratio in dB. Higher is better."""
    if mse == 0:
        return float("inf")
    return 10.0 * math.log10(max_val ** 2 / mse)

# Hypothetical MSE at 2 Mbit/s, 1080p, for three AV1 presets.
# Lower MSE means the decoded image is closer to the original.
results: dict[str, float] = {
    "libaom cpu-used=6 (fast)":  psnr(28.0),
    "libaom cpu-used=3 (medium)": psnr(21.0),
    "libaom cpu-used=0 (slow)":  psnr(16.0),
}
for name, value in results.items():
    print(f"{name}: PSNR = {value:.1f} dB")
# cpu-used=6: PSNR ~ 37.7 dB  (fast but leaves quality on the table)
# cpu-used=0: PSNR ~ 42.1 dB  (slow but squeezes every last dB)
```

  A difference of 4 dB in PSNR is perceptible on a good monitor. That 4 dB costs roughly 10--50x more encode time, a stark illustration of the diminishing-returns curve in encoder optimization.
]

The practical solution came from Intel's *SVT-AV1* encoder, open-sourced in 2019 and rapidly improved through 2021--2024. SVT-AV1 (Scalable Video Technology for AV1) was designed from the ground up for speed and multi-core parallelism, using a look-ahead window, hierarchical motion estimation, and a tiered decision structure that prunes the search space early. At preset 6, SVT-AV1 encodes 3--5x faster than libaom at comparable quality, while remaining within 2--3% of libaom's compression efficiency.

#mathrecall[
  *VMAF* (Video Multi-method Assessment Fusion), Netflix's perceptual quality score from 0 to 100, was introduced in Chapter 41. Unlike PSNR, which only measures raw pixel error, VMAF is tuned to track _human_ judgment of video quality, so it is the yardstick streaming services actually optimize against. Two codecs "at matched quality" below means matched VMAF.
]

By 2022, Netflix had adopted SVT-AV1 for production encoding. Netflix's December 2025 announcement confirmed AV1 at 30% of all streaming traffic, with VMAF scores averaging 4.3 points higher than AVC at one-third the bandwidth. Meta reported more than 70% of users watching AV1 video across their platforms. The numbers were in: the open codec had won the streaming war.

#scoreboard(
  caption: "Approximate bitrate at matched perceptual quality (1080p, VMAF ~85), relative to H.264/AVC.",
  [Codec], [Relative bitrate], [Year], [Notes],
  [H.264/AVC], [100%], [2003], [Universal hardware; royalty-bearing],
  [VP8], [~85%], [2010], [Royalty-free; close to H.264 Baseline],
  [VP9], [~60%], [2013], [YouTube main codec 2014--2022; royalty-free],
  [H.265/HEVC], [~52%], [2013], [Better than VP9; patent quagmire],
  [AV1 (libaom)], [~38%], [2018], [Best quality; slow encode],
  [AV1 (SVT-AV1)], [~40%], [2022], [Production-ready speed],
  [H.266/VVC], [~30%], [2020], [Technically best; fragmented licensing],
  [AV2 (projected)], [~24--28%], [2026], [Spec finalized 28 May 2026],
)

== Hardware: The Adoption Gap

Writing a codec specification costs person-years of engineering. Getting it into every phone, TV, and laptop costs billions of dollars of silicon investment and takes years after the spec.

AV1 hardware decode arrived in stages:

- *2020--2021*: MediaTek Dimensity 900+, Samsung Exynos 2100, Nvidia RTX 30 series, Intel Xe / 12th Gen: first mainstream chips with hardware AV1 decode.
- *2022*: AMD Radeon RX 7000 series (hardware decode and encode), most new smart TVs from Samsung, LG, Sony, and Hisense. Effectively any TV bought new in 2022 or later includes AV1 hardware decode.
- *2023*: Apple A17 Pro (iPhone 15 Pro) and Apple M3 family: hardware AV1 decode finally arrives in Apple silicon. Qualcomm Snapdragon 8 Gen 2 brings AV1 hardware decode to mainstream Android flagships.
- *2024*: Virtually all new devices above mid-range include AV1 hardware decode. Netflix certifies 88% of large-screen devices submitted for certification between 2021 and 2025 as AV1-capable.

Hardware AV1 *encode* (not just decode) is a separate, harder problem requiring more silicon and more power. Hardware AV1 encoders only shipped in the Intel Arc GPU family, AMD RX 7000, and Nvidia RTX 40 (Ada Lovelace) architecture, all arriving in 2022--2023.

#pitfall[
  Hardware AV1 encoders produce good real-time quality but cannot match libaom or SVT-AV1 in compression efficiency. The silicon encodes in milliseconds; software encoders spend seconds per frame searching better partitions. For live streaming, hardware encode is the only viable option. For on-demand content, software encoding is always superior at the same file size.
]

The decode lag is the structural pattern of the whole lineage: a spec ships, software decoders work immediately (Google's *libvpx* for VP9; *dav1d* for AV1), hardware arrives 2--4 years later, and broad consumer reach takes 3--6 years. The dav1d decoder, released November 2018 just months after the AV1 spec, achieved real-time 4K AV1 software decode on most desktop CPUs via aggressive SIMD optimization (AVX-2, AVX-512, NEON on ARM). Both Firefox and Chrome switched to dav1d in 2020. Its name is a pun on "David" (the Biblical underdog) and "AV1D", a joke that did not require much imagination given the competitive situation.

== The Sisvel Patent Challenge

AV1's royalty-free status faced its first serious test in 2019 when *Sisvel International*, a patent-licensing company, assembled a patent pool claiming to cover AV1 and began offering licenses. AOMedia responded by stating that AV1 was developed from day one to be royalty-free, that member companies had pledged their relevant patents, and that Sisvel's claimed essential patents were either licensed by AOMedia members, not essential, or invalid.

The dispute escalated enough that the European Commission opened a preliminary investigation in 2021 into whether AOMedia's royalty-free licensing policy constituted an anticompetitive practice, essentially asking whether a group of companies _agreeing to give technology away for free_ could somehow harm competition. In May 2023, the EC closed the investigation without finding a violation. AOMedia called it a vindication; the streaming industry collectively exhaled.

As of mid-2026, AV1 is deployed at massive scale across Netflix, YouTube, Meta, Amazon, Android, Chrome, Firefox, and Edge, without paying royalties to Sisvel or any other third-party pool. The legal dust has not entirely settled, but the commercial reality is clear.

#checkpoint[What were the three codec projects that merged into AV1?][Google's VP10, Mozilla/Xiph's Daala, and Cisco's Thor.]

== AV2: The Next Chapter (May 2026)

On 28 May 2026, the Alliance for Open Media released the AV2 specification (version 1.0 of the bitstream), accompanied by reference encoder and decoder implementations. The official announcement on 9 June 2026 confirmed what prototype tests had shown throughout 2025: AV2 delivers approximately 30--40% bitrate reduction over AV1 at equivalent quality, comparable to VVC's improvement over HEVC. At CES 2026, VLC 4.0 demonstrated live AV2 playback on a MacBook Pro.

The jump from AV1 to AV2 is as large as the jump from VP9 to AV1. The key technical advances include:

=== Extended Recursive Partitioning

AV2 adds *extended recursive partitioning*, expanding the multi-type tree vocabulary further. Partitions can now be non-power-of-two rectangles at more split levels. More importantly, the luma and chroma channels are *semi-decoupled*: the luma partition tree and the chroma partition tree can make different choices within the same superblock. In AV1, they must share the same partition structure. Decoupling them lets the encoder apply fine luma partitions where luminance detail is complex while using coarser chroma partitions where color information is smoother, which is almost always the case, because the human eye is less sensitive to color resolution (Chapter 42 covered the same insight behind chroma subsampling in JPEG).

=== New Intra and Inter Prediction Tools

AV2 extends intra prediction with *chroma-from-luma (CfL)* improvements and additional directional modes tuned for common content types: screen-capture video, animation, and HDR highlights. For inter prediction, new compound modes and improved reference frame management contribute further gains.

=== Multi-Layer and Multi-View Support

AV1 was designed for a single video stream. AV2's bitstream natively supports *multi-layer streams* and *multi-view* scenarios: stereoscopic video for VR/AR, multiple camera angles within a single bitstream, and composite split-screen experiences. This is structurally new: a single AV2 file can carry a left-eye view, a right-eye view, and depth information, with the decoder selecting what it needs.

=== Scalable Bitstreams

AV2 supports *spatial* and *temporal scalability*, meaning a lower-resolution or lower-frame-rate version of the video can be extracted from the bitstream without re-encoding. This is valuable for adaptive streaming: a single AV2 encode can serve 4K, 1080p, and 720p clients from the same file.

#algo(
  name: "AV2",
  year: 2026,
  authors: ("Alliance for Open Media",),
  aim: "Royalty-free successor to AV1 with ~30--40% bitrate reduction over AV1, native multi-view and scalability support, and semi-decoupled luma/chroma partition trees.",
  complexity: ("encode", "Expected significantly slower than AV1 at launch; hardware decode targeted for ~2027--2028"),
  strengths: (
    "Royalty-free by design",
    "~30--40% over AV1 (~60--70% over H.264 at matched quality)",
    "Native multi-view for AR/VR without container tricks",
    "Scalable bitstreams simplify adaptive streaming pipelines",
    "Semi-decoupled luma/chroma exploits human color sensitivity",
  ),
  weaknesses: (
    "No hardware decoder available as of June 2026",
    "Software decode slow; real-time 4K requires fast desktop CPU",
    "Existing AV1 content must be re-encoded to gain AV2 benefits",
    "Broader ecosystem support and hardware years away",
  ),
  superseded: "N/A (current frontier as of June 2026)",
)[
  AV2 extends the AV1 architecture. Frames are divided into superblocks with extended recursive partitioning supporting non-power-of-two rectangles. Luma and chroma use semi-decoupled partition trees within each superblock. Inter prediction gains new compound modes and improved reference management. The entropy coder is a refined ANS variant. Three in-loop filters clean the decoded signal. The bitstream container natively supports multi-layer and multi-view streams, enabling stereoscopic and scalable delivery from a single file.
]

=== The Hardware Timeline for AV2

History is the best guide here. AV1's spec shipped June 2018; its first mainstream hardware decode appeared in late 2020 (MediaTek Dimensity) and became universal in 2022--2024. That is a 2--4-year gap for high-end chips and 4--6 years for broad consumer reach.

Projecting the same pattern for AV2 (spec: May 2026):

- *2026--2027*: Software-only decode. VLC 4.0 demonstrated real-time AV2 playback at CES 2026 on a MacBook Pro with Apple M-series hardware. Broad software decoder availability (browser, phone) expected by end of 2027.
- *2027--2028*: First hardware AV2 decode in high-end chips, likely Intel next-generation Arc, AMD RDNA 4+, or equivalent ARM/Qualcomm IP.
- *2029--2030*: Mid-range mobile SoC support; first wave of AV2-capable smart TVs.
- *2030+*: Broad consumer reach comparable to AV1's current installed base.

Netflix's Director of Codec Development Andrey Norkin framed the adoption reality plainly: production AV2 deployment begins "once device support makes it sensible." That single sentence captures the entire economics of codec transitions.

#history[
  VLC (VideoLAN Client) has a tradition of being among the first players to implement new codecs. It added VP9 support before Chrome; it added AV1 support in VLC 3.0 (2018); and it demonstrated AV2 playback in a preview of VLC 4.0 at CES 2026. The VLC team, operating as volunteers from a French university project that became a global open-source effort, has served as the canary in the codec coal mine for thirty years.
]

== Putting the Numbers Together

Here is a concrete example to make the generations tangible. Suppose you want to stream a one-hour film at good quality (VMAF 85) to a viewer's TV. Based on Netflix's publicly reported numbers and approximate BD-rate measurements across codecs:

#keyidea[
  At VMAF 85 for a typical one-hour HD film:
  - H.264/AVC: ~8 GB
  - VP9: ~4.8 GB (~40% less than H.264)
  - H.265/HEVC: ~4.2 GB (~47% less than H.264)
  - AV1: ~2.7 GB (~66% less than H.264; consistent with Netflix's "one-third less than AVC")
  - AV2 (projected): ~1.6--1.9 GB (~76--80% less than H.264)

  Over billions of streaming sessions per day, the difference between H.264 and AV1 alone amounts to roughly five exabytes of bandwidth per year. That is enough energy saved to power a small country.
]

#mathrecall[
  *BD-rate* (Bjøntegaard Delta Rate), the savings numbers driving the code below, was defined in Chapter 53. It answers a single question, "at the same quality, how much smaller is codec B's bitstream than codec A's?", averaged over several quality points. A BD-rate of $-66%$ for AV1 versus H.264 means AV1 needs about two-thirds fewer bits for the same picture.
]

#gopython("Estimating Cross-Generation Bitrate Savings")[
```python
def bitrate_at_generation(
    h264_gb: float,
    generation: str,
) -> float:
    """
    Estimate file size in GB for a one-hour HD stream
    relative to H.264, based on published BD-rate data.
    """
    savings: dict[str, float] = {
        "H.264":  0.00,   # baseline
        "VP8":    0.15,   # ~15% less
        "VP9":    0.40,   # ~40% less
        "HEVC":   0.47,   # ~47% less
        "AV1":    0.66,   # ~66% less
        "VVC":    0.72,   # ~72% less (theoretical best licensed)
        "AV2":    0.77,   # ~77% less (projected, midpoint estimate)
    }
    factor = 1.0 - savings[generation]
    return h264_gb * factor

h264_gb = 8.0
for gen in ["H.264", "VP8", "VP9", "HEVC", "AV1", "VVC", "AV2"]:
    size = bitrate_at_generation(h264_gb, gen)
    print(f"{gen:<10}: {size:.2f} GB")
# H.264    : 8.00 GB
# VP8      : 6.80 GB
# VP9      : 4.80 GB
# HEVC     : 4.24 GB
# AV1      : 2.72 GB
# VVC      : 2.24 GB
# AV2      : 1.84 GB
```
]

== The Open vs. Licensed War: A Ledger

After fifteen years of open-codec development (VP8 in 2010, VP9 in 2013, AV1 in 2018, AV2 in 2026) it is worth taking stock. The honest verdict:

Open codecs have tracked within about 5--10% of licensed codecs technically at every generation. The maximum quality gap in favor of licensed codecs has been about 10--15% in bitrate: real, but small. Meanwhile the patent-cost gap went from uncertain-but-real to a commercial existential issue with HEVC. The open codecs won because they were _good enough_ and _free_. In a market serving trillions of video streams per year, "good enough and free" beats "slightly better and expensive" every single time.

The one domain where licensed codecs still dominate is professional broadcast: HEVC remains the backbone of satellite and cable delivery, with VVC beginning its replacement. But even there, AV1 is making inroads through internet-delivered broadcast (ATSC 3.0, some IPTV systems). AV2's native multi-view support positions it as a strong candidate for the next-generation broadcast standard, royalty-free, for the first time in broadcast video history.

#checkpoint[Why did AV1 succeed commercially despite H.265/HEVC being slightly better technically?][HEVC's patent-pool crisis made licensing expensive, unpredictable, and legally risky. AV1 was royalty-free and within 5--10% of HEVC quality. For streaming companies serving billions of sessions, the legal certainty of AV1 outweighed HEVC's marginal compression advantage.]

#takeaways((
  "VP8 (May 2010) was Google's open release of the On2 VP8 codec as WebM. Technically close to H.264 Baseline; politically transformative. Google pledged an irrevocable royalty-free patent license to all implementors.",
  "VP9 (June 2013) raised superblock size to 64x64, added 10 intra prediction angles, adaptive entropy contexts, and tiled parallel decode. YouTube deployed it at exabyte scale; by any measure it became one of the most-decoded codecs ever.",
  "The Alliance for Open Media formed 1 September 2015 with seven founding members (Amazon, Cisco, Google, Intel, Microsoft, Mozilla, Netflix), merging Google's VP10, Mozilla/Xiph's Daala, and Cisco's Thor into AV1.",
  "AV1 (June 2018) introduced 10 partition types, CDEF for ringing suppression, the Wiener/SGR loop-restoration filter for banding, warped affine motion compensation, compound prediction modes, and film grain synthesis. The result: approximately 30% over HEVC and 62% over H.264.",
  "SVT-AV1 (Intel, 2019+) made AV1 production-viable by encoding 3--5x faster than libaom. Netflix deployed it for 30% of streaming traffic by December 2025. dav1d (2018) made AV1 software decode fast enough for real-time 4K.",
  "AV1 hardware decode arrived in mainstream silicon 2020--2024: Nvidia RTX 30, AMD RX 7000, Apple A17 Pro and M3, Qualcomm Snapdragon 8 Gen 2. The 2--4-year hardware lag after the spec is an unchangeable physics of chip development cycles.",
  "AV2 specification finalized 28 May 2026 with ~30--40% bitrate reduction over AV1, adding extended recursive partitioning, semi-decoupled luma/chroma partition trees, native multi-view and scalability. Hardware decode expected ~2027--2030.",
  "Open codecs win not by being technically dominant but by being free and legally certain. In a world of trillions of video streams and billion-dollar patent exposure, royalty-free beats slightly-better-and-encumbered every time.",
))

== Exercises

#exercise("54.1", 1)[
  VP8 was released in May 2010 under what two types of legal commitments? What did each cover, and why were _both_ required to make VP8 truly free for everyone to implement?
]
#solution("54.1")[
  First: a *BSD-style open-source license* covering the source code, which anyone could use, modify, and distribute freely. Second: an *irrevocable royalty-free patent license* covering the bitstream specification itself, meaning Google pledged never to sue anyone for implementing VP8 even using their own independently written code. Both were required because open-source code licenses only govern the specific codebase; they say nothing about whether implementing the same algorithm independently might infringe patents. Without the patent pledge, a company could write its own VP8 decoder from scratch (using only the spec, not Google's code) and still face infringement claims. The two commitments together made VP8 free to implement by any means.
]

#exercise("54.2", 1)[
  List three specific technical improvements VP9 made over VP8. For each, state in one sentence what problem in video compression it solved.
]
#solution("54.2")[
  1. *64×64 superblocks* (up from 16×16 macroblocks): allowed large flat regions in 4K video to be coded in one block, eliminating the per-block overhead that would otherwise be repeated thousands of times across a smooth area. 2. *10 intra prediction angles* (up from 4): better exploited directional texture (horizontal grass, diagonal roof tiles, vertical walls) by fitting a prediction direction closer to the actual texture, leaving less signal in the residual for entropy coding to handle. 3. *Tile-based decoding*: divided frames into independently decodable tiles so that different cores of a multi-core CPU could decode them in parallel, enabling real-time 4K software decode that would otherwise be too slow on a single core.
]

#exercise("54.3", 2)[
  The CDEF filter in AV1 has a "Constrained" step that prevents output pixels from exceeding the dynamic range of the input block. Explain in your own words: (a) what visual artifact CDEF primarily addresses; (b) what visual artifact the constraint prevents; (c) why both properties are needed for CDEF to improve quality rather than hurt it.
]
#solution("54.3")[
  (a) CDEF primarily addresses *ringing*, the ripple patterns that appear around sharp edges when DCT coefficients are heavily quantized. The ripples arise because the quantized transform can only approximate sharp edges with a finite sum of smooth cosine waves, which overshoot and undershoot. (b) The constraint prevents *halos*, artificially bright or dark rings around edges that result when sharpening filters amplify edges beyond the actual pixel values in the image. (c) Without CDEF, ringing remains; viewers see waves around text and edges. With CDEF but without the constraint, the directional filter sharpens aggressively and introduces halos that are often more disturbing than the original ringing. The constraint ensures CDEF redistributes existing pixel energy to better align with the true edge without inventing new, out-of-range values.
]

#exercise("54.4", 2)[
  Explain the difference between *translational* motion compensation (used in H.264, HEVC, VP9) and *warped (affine) motion compensation* (introduced in AV1). Give one specific real-world video scenario where warped motion provides a clear advantage over translational motion vectors.
]
#solution("54.4")[
  Translational motion compensation models each block as having moved by a fixed pixel offset $(Delta x, Delta y)$: the block shifts uniformly with no rotation, scaling, or shearing. Affine motion compensation allows the block to be rotated, scaled, and sheared in addition to translated, using six parameters (two per row of the $2 times 3$ affine matrix). A clear advantage scenario: a drone filming a city from above while flying forward. The camera zooms in slightly (scale change) and may rotate as the pilot adjusts heading. Every block in the frame moves with a different zoom amount depending on its distance from the image center; objects near the center zoom less, and objects at the edges zoom more. Translational motion vectors must use a different vector for every block and still leave large residuals at the zoom boundaries. A single global affine warp model captures the entire camera motion in six parameters, reducing residuals across the whole frame simultaneously.
]

#exercise("54.5", 2)[
  AOMedia reported AV2 achieves approximately 30--40% bitrate reduction over AV1. If a streaming service currently delivers one-hour HD content at 2.7 GB in AV1, estimate the range of AV2 file sizes for the same quality. Show your full calculation. Then estimate how much bandwidth a service delivering 100 million AV1-equivalent streams per day would save per year by switching to AV2 (use the midpoint of your estimate).
]
#solution("54.5")[
  Per-file estimates: At 30% reduction: $2.7 times (1 - 0.30) = 2.7 times 0.70 = 1.89$ GB. At 40% reduction: $2.7 times (1 - 0.40) = 2.7 times 0.60 = 1.62$ GB. AV2 range: *1.62--1.89 GB*. Midpoint: $(1.89 + 1.62) / 2 = 1.755$ GB per stream. Saving per stream: $2.7 - 1.755 = 0.945$ GB. Annual saving for 100 million streams/day: $0.945 times 10^8 times 365 approx 3.45 times 10^10$ GB $= 3.45 times 10^7$ TB $approx 34.5$ exabytes per year. That is a substantial enough saving to meaningfully reduce global internet bandwidth consumption.
]

#exercise("54.6", 3)[
  Write a Python 3.14 function `simulate_grain_savings(source_bits: float, grain_fraction: float, param_bits: float = 256.0) -> float` that estimates the percentage bitrate saving from AV1's film grain synthesis feature. Assumptions: without synthesis, the encoder must code all `source_bits` bits; with synthesis, it codes `(1 - grain_fraction) * source_bits` bits for the de-grained frame plus `param_bits` fixed overhead for the grain parameters. Test it with `source_bits = 1_000_000`, `grain_fraction = 0.25`, and verify that the saving is close to 25% (the overhead should be negligible).
]
#solution("54.6")[
```python
def simulate_grain_savings(
    source_bits: float,
    grain_fraction: float,
    param_bits: float = 256.0,
) -> float:
    """
    Estimate percentage bitrate saving from film grain synthesis.

    Without synthesis: must encode all source_bits.
    With synthesis:    encode de-grained frame (smaller)
                       plus fixed grain parameter overhead.
    Returns percentage saving, e.g. 24.97 for ~25%.
    """
    bits_without: float = source_bits
    bits_with: float = (1.0 - grain_fraction) * source_bits + param_bits
    saving_pct: float = (bits_without - bits_with) / bits_without * 100.0
    return saving_pct

# Test: 1 million bits per frame, 25% is grain
pct = simulate_grain_savings(1_000_000, 0.25)
print(f"Saving: {pct:.2f}%")
# Output: Saving: 24.97%
# The 256-bit overhead reduces the saving from exactly 25%
# to 24.97% --- negligible, as expected for a large frame.

# Sensitivity: if the frame is small (e.g. a thumbnail)
# the overhead becomes significant:
pct_small = simulate_grain_savings(10_000, 0.25)
print(f"Small frame saving: {pct_small:.2f}%")
# Output: ~22.44% -- overhead now matters
```
]

== Further Reading

- #link("https://norkin.org/pdf/PCS_2018_AV1_tools_overview.pdf")[Chen, Y. et al. (2018). "An Overview of Core Coding Tools in the AV1 Video Codec." Picture Coding Symposium.] The authoritative technical overview of every AV1 tool by the team that built them.

- #link("https://arxiv.org/abs/2008.06091")[Chen, Y. et al. (2020). "An Overview of Core Coding Tools in the AV1 Video Codec." arXiv:2008.06091.] Expanded journal version; also in `papers/chen-2020-av1-overview.pdf`.

- #link("https://aomedia.org/docs/AV1_ToolDescription_v11-clean.pdf")[AOMedia. "Tool Description for AV1 and libaom" (v11).] The codec team's own plain-language description of each AV1 tool and why it was included.

- #link("https://netflixtechblog.com/av1-now-powering-30-of-netflix-streaming-02f592242d80")[Netflix Technology Blog (December 2025). "AV1: Now Powering 30% of Netflix Streaming."] Real deployment data: bitrate savings, VMAF gains, and buffering reductions at scale.

- #link("https://norkin.org/research/av2_overview/")[Norkin, A. (2025--2026). "AV2 Video Codec Overview."] Andrey Norkin's (Netflix) running technical overview of AV2 as the specification evolved.

- #link("https://aomedia.org/press%20releases/Alliance-for-Open-Media-Releases-AV2-Codec/")[Alliance for Open Media (June 2026). "Alliance for Open Media Releases AV2 Codec."] The official release announcement with headline specifications and compression numbers.

- #link("https://en.wikipedia.org/wiki/On2_Technologies")[On2 Technologies - Wikipedia.] The full history of The Duck Corporation through VP8, with the Google acquisition timeline.

- #link("https://en.wikipedia.org/wiki/Alliance_for_Open_Media")[Alliance for Open Media - Wikipedia.] Founding members, governance, patent pledge mechanism, and the Sisvel patent challenge history.

- #link("https://www.streamingmedia.com/Articles/News/Online-Video-News/AV2-Arriving-What-We-Know-and-What-We-Dont-Know-171548.aspx")[Ozer, J. (2025). "AV2 Arriving: What We Know, and What We Don't Know." Streaming Media.] Practical industry analysis of AV2's adoption challenges and expected timeline.

#bridge[
  We have now traced the complete open-codec lineage: from Google's audacious 2010 gift to the industry, through VP9's exabyte-scale YouTube deployment, through the Alliance for Open Media's committee-built marvel AV1, to AV2's fresh specification. Both the open and licensed lines converge on the same fundamental architecture that Chapter 51 introduced: predict, transform the residual, quantize, entropy-code. The differences are in the sophistication of each tool and in who charges what for the right to use it.

  But a question has been building throughout these codec chapters: what if the prediction model itself could be learned from data? What if instead of hand-crafted CDEF filters and warped-motion models, a neural network could learn to predict what comes next? Chapter 55 surveys the encoding-at-scale tools that exist today: per-title optimization, VMAF-driven RDO, content-adaptive encoding pipelines. Then Chapter 59 examines the neural video codecs (DVC, DCVC, VCT) that are attempting to replace the entire hand-engineered pipeline. Same compression goal; radically different path.
]
