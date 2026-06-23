#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= HEVC and VVC: More Compression, More Patents

#epigraph[
  The technology was brilliant. The licensing was a disaster.
][Jan Ozer, Streaming Learning Center, 2023]

Imagine you are running a streaming service in 2013. Your engineers hand you a gift: a new video codec called H.265, also known as HEVC — High Efficiency Video Coding. It squeezes a movie into half the bytes that H.264 needed. Half. For a business paying millions of dollars in bandwidth bills every month, that is not a minor improvement; it is a revolution.

Then the lawyers call.

"How many patent pools are there for this new codec?" you ask.

"Well," the lawyer begins, "there are at least two right now. Possibly three. It depends on which patents get sorted into which pool. And we are not sure all the essential patents are even in any pool. And the royalty terms overlap, so you might owe fees twice for the same product."

You hang up and call your engineers back. "Tell me about that royalty-free VP9 thing Google released last week."

That exchange — real in spirit if not in detail — is the story of H.265/HEVC and its successor H.266/VVC. Both are extraordinary pieces of engineering. Both were hamstrung for years by patent licensing structures so tangled that entire businesses chose technically inferior alternatives just to avoid the legal exposure. In this chapter we will understand both the technology and the politics, because in video compression you cannot separate the two.

#recap[
  Chapter 51 introduced the hybrid video codec architecture: I-frames coded like still images, P-frames and B-frames coded as prediction residuals using motion vectors, and a rate-distortion optimization (RDO) loop that minimizes $J = D + lambda dot R$ at every decision point. Chapter 52 traced the lineage from H.261 (1988) through MPEG-2 (1995) and then H.264/AVC (2003), which became the universal codec of streaming, mobile video, and Blu-ray. Chapter 38 taught the DCT and how transform coding concentrates image energy into a few low-frequency coefficients. We rely on all of that here.
]

#objectives((
  "Explain what a Coding Tree Unit (CTU) is and why it replaced the fixed macroblock.",
  "Describe HEVC's five main improvements over H.264: CTUs, angular intra prediction, SAO, CABAC improvements, and parallel processing.",
  "Sketch the VVC multi-type tree (MTT) partition and explain why it outperforms HEVC's quadtree.",
  "Understand the HEVC patent-pool crisis and how it shaped the open-codec movement.",
  "Read Python code that measures the theoretical bitrate saved by moving from H.264 to HEVC to VVC quality settings.",
))

== Why H.264 Was Not Enough

By 2010, H.264/AVC was the dominant video codec on Earth. It ran on every smartphone, powered YouTube and Netflix, and was baked into billions of chips. But the world was changing fast. 4K Ultra-HD televisions were entering living rooms. Mobile data consumption was doubling every 18 months. Streaming was replacing broadcast. The bottleneck was bandwidth, and bandwidth cost money.

The ITU-T Video Coding Experts Group (VCEG) and ISO/IEC Moving Picture Experts Group (MPEG) — the same two bodies that jointly created H.264 — formed a new team called the *Joint Collaborative Team on Video Coding (JCT-VC)* in January 2010. Their brief was explicit: deliver roughly 50% better compression than H.264 at the same perceptual quality, at the cost of higher encoding complexity.

The project that emerged was H.265/HEVC. The standard was formally approved by ITU-T on 13 April 2013, just three years after JCT-VC was formed — fast, by standards-body timescales. The key overview paper, by Sullivan, Ohm, Han, and Wiegand, appeared in IEEE Transactions on Circuits and Systems for Video Technology in December 2012, just before the standard finalized.

#history[
  H.264 was developed by the *Joint Video Team (JVT)*, formed in 2001. HEVC was developed by the *Joint Collaborative Team on Video Coding (JCT-VC)*, formed in 2010. VVC was developed by the *Joint Video Experts Team (JVET)*, formed in 2015. The escalating complexity of each successor is reflected in the escalating effort: H.264 took roughly four years; HEVC took three; VVC took five.
]

== Coding Tree Units: The Key Idea Behind HEVC

To understand HEVC's biggest structural innovation, we need to revisit how H.264 partitioned a video frame.

In H.264, every frame is divided into fixed 16×16 pixel *macroblocks*. A macroblock can be further subdivided — down to 4×4 blocks for certain prediction modes — but the top-level grid is always 16×16. This was fine in 2003, when most video was 720×576 or 1280×720. But at 3840×2160 (4K UHD), a 16×16 macroblock covers a tiny sliver of the scene. Large flat areas — a blue sky, a concrete wall, a field of grass — could be represented far more efficiently with a single large block than with thousands of 16×16 tiles each carrying their own overhead.

HEVC replaced the macroblock with the *Coding Tree Unit (CTU)*.

#definition("Coding Tree Unit (CTU)")[
  A CTU is the top-level processing unit in HEVC. Its luma size $L times L$ is configurable: $L in {16, 32, 64}$ samples, with 64×64 being the default for most applications. Each CTU is recursively split into *Coding Units (CUs)* using a *quadtree* structure. A CU can be as small as 8×8 samples. The CU is the unit of prediction (intra or inter) and transform coding.
]

The quadtree splitting works like this. Start with a 64×64 CTU. The encoder asks: "Should I code this whole block as one unit, or split it into four 32×32 children?" If it splits, each 32×32 child faces the same question: code as-is, or split into four 16×16 grandchildren? And so on, down to the minimum CU size.

#gomaths("Quadtree Recursion")[
  A *quadtree* is a tree where every internal node has exactly four children. Think of a square piece of paper. If you fold it in half twice, you get four equal squares — that is one level of splitting. Each of those squares can itself be folded again into four smaller squares, and so on. For an $L times L$ block, the depth of the tree is at most $log_2(L / L_"min")$, where $L_"min"$ is the minimum allowed block size. For $L=64$ and $L_"min"=8$, the maximum depth is $log_2(64/8) = log_2(8) = 3$ levels.
]

Why does this matter so much? Consider a 4K frame containing a close-up of a face. The person's forehead might be a smooth gradient coverable by a single 64×64 CTU coded as one unit. Their eyelash, with fine texture and sharp edges, might need 8×8 CUs. The background wall might need 32×32. The quadtree lets the encoder use the right size for each region, spending bits only where the video genuinely demands detail.

#fig(
  [HEVC quadtree CTU splitting. A 64×64 CTU (large dashed square) can remain whole, split into four 32×32 CUs, or recurse further to 16×16 and 8×8 CUs. The encoder chooses the depth that minimises the rate-distortion cost $J = D + lambda R$.],
  cetz.canvas({
    import cetz.draw: *
    // 64x64 outer
    rect((0,0),(4,4), stroke: (paint: rgb("#0b5394"), thickness: 1.5pt, dash: "dashed"), name: "outer")
    // 4 x 32x32 quadrants -- top-right stays whole, others split
    // bottom-left 32x32: split into 4 x 16x16
    line((0,2),(4,2), stroke: 0.8pt + rgb("#783f04"))
    line((2,0),(2,4), stroke: 0.8pt + rgb("#783f04"))
    // bottom-left quadrant (0,0)-(2,2): further split into 16x16
    line((0,1),(2,1), stroke: 0.5pt + rgb("#0b6e4f"))
    line((1,0),(1,2), stroke: 0.5pt + rgb("#0b6e4f"))
    // top-left quadrant (0,2)-(2,4): stays 32x32 (no further split shown)
    // top-right quadrant (2,2)-(4,4): stays 32x32
    // bottom-right quadrant (2,0)-(4,2): further split
    line((2,1),(4,1), stroke: 0.5pt + rgb("#0b6e4f"))
    line((3,0),(3,2), stroke: 0.5pt + rgb("#0b6e4f"))
    // labels
    content((1,3))[#text(size:7pt)[32×32]]
    content((3,3))[#text(size:7pt)[32×32]]
    content((0.5,1.5))[#text(size:6pt)[16]]
    content((1.5,1.5))[#text(size:6pt)[16]]
    content((0.5,0.5))[#text(size:6pt)[16]]
    content((1.5,0.5))[#text(size:6pt)[16]]
    content((2.5,1.5))[#text(size:6pt)[16]]
    content((3.5,1.5))[#text(size:6pt)[16]]
    content((2.5,0.5))[#text(size:6pt)[16]]
    content((3.5,0.5))[#text(size:6pt)[16]]
    content((2,4.4))[#text(size:7.5pt, fill: rgb("#0b5394"), weight: "bold")[64×64 CTU]]
  })
)

== Five Ways HEVC Improved on H.264

The CTU/quadtree structure is the headline change, but HEVC improved on H.264 in at least five distinct technical areas. Let us work through each one.

=== 1. Larger, Flexible Block Sizes

As described above, H.264 topped out at 16×16 for its top-level macroblock, while HEVC goes up to 64×64. This change alone accounts for a significant fraction of HEVC's gain on high-resolution content. Coding a 64×64 uniform region as one unit costs one transform block plus minimal overhead. Coding the same region as sixteen 16×16 H.264 macroblocks costs sixteen transform blocks, sixteen sets of motion vectors or intra-prediction signals, and sixteen times the overhead. The savings are direct.

=== 2. Angular Intra Prediction with 35 Directions

In H.264, intra prediction (predicting a block from already-decoded neighbors within the same frame) offered 9 angular modes for 4×4 blocks and 4 modes for larger ones. HEVC expands this to *35 intra prediction modes*: 33 directional angles plus DC (flat average) and Planar (smooth gradient).

Why 35? Human scenes are full of edges: door frames, window borders, hair strands, brickwork. If you can predict along the edge direction, the prediction residual is nearly zero and costs almost nothing to transmit. With 35 finely-spaced angles, HEVC can align its prediction to diagonal edges that H.264 would leave as costly residuals.

#keyidea[
  Intra prediction is about exploiting spatial redundancy within a single frame: a pixel is likely similar to its neighbors. More angular modes mean finer alignment to real-world edges, leaving a smaller residual. A smaller residual means fewer bits. This is "compression through geometry."
]

=== 3. Sample Adaptive Offset (SAO)

Every quantization step introduces ringing artefacts — wavy halos around sharp edges — and a systematic intensity bias. H.264 used a *deblocking filter* after the transform to smooth block boundaries. HEVC keeps the deblocking filter and adds a second in-loop filter: *Sample Adaptive Offset (SAO)*.

SAO classifies each decoded pixel into one of a small number of categories — either by its edge pattern (edge offset) or by its intensity level (band offset) — and applies a precomputed correction offset to each category. The encoder signals the category assignments and offsets in the bitstream.

Concretely, in *edge offset* mode the decoder looks at each pixel together with two of its neighbours along a chosen direction (horizontal, vertical, or one of the two diagonals). If the centre pixel is a local minimum — dimmer than both neighbours — it likely sits in the dark trough of a ringing ripple, so SAO nudges it brighter by a signalled offset; if it is a local maximum, SAO nudges it darker. Pixels that are not at an edge are left alone. In *band offset* mode the 0–255 intensity range is sliced into 32 equal bands, and the encoder sends a correction for a handful of consecutive bands where it measured a systematic bias — useful when, say, all the mid-grey pixels drifted slightly dark after quantization. The result: ringing and intensity bias are corrected before the reconstructed frame is used as a reference for future inter prediction, so errors do not accumulate across frames.

Measured independently, SAO recovers about 1–2 dB of PSNR quality at the same bitrate, or equivalently saves roughly 5–6% of bitrate at the same PSNR.

#definition("PSNR")[
  Peak Signal-to-Noise Ratio measures reconstruction quality. If the maximum pixel value is $V_"max"$ (255 for 8-bit video) and the mean squared error between original and reconstructed frames is $"MSE"$, then:
  $"PSNR" = 10 log_10 (V_"max"^2 / "MSE")$
  Higher PSNR means less distortion. 35 dB is "acceptable"; 40 dB is "good"; 45+ dB is "near-transparent." A gain of 1 dB is roughly equivalent to a 10–15% bitrate saving at matched quality.
]

=== 4. CABAC Improvements

H.264 offered two entropy coding modes: the faster but weaker CAVLC (Context-Adaptive Variable-Length Coding) and the slower but more powerful CABAC (Context-Adaptive Binary Arithmetic Coding). We built the theory for arithmetic coding in Chapter 26.

HEVC made a clean design decision: *only CABAC*. The H.264 CABAC context model was reworked from scratch — fewer contexts overall but better-tuned to the new syntax elements introduced by the quadtree structure. The result: HEVC's CABAC achieves roughly 10–15% better compression than H.264's CABAC on the entropy-coding step alone. Simplifying to one mode also simplified decoder chips, which now only needed to implement one entropy path.

#mathrecall[CABAC is an arithmetic coder where the probability model for each binary symbol is conditioned on a "context" — a few bits of recently coded syntax. Chapter 26 built the arithmetic coder; Chapter 52 explained how H.264 wired it to video syntax.]

=== 5. Parallel Processing Structures

This improvement is almost invisible to a viewer but critical to chip designers. H.264's macroblock grid created data dependencies that made it hard to process multiple macroblocks in parallel: to decode macroblock $(i,j)$, you needed the already-decoded neighbors above and to the left.

HEVC introduced two structures that break these dependencies:

- *Tiles:* the frame is divided into rectangular regions (tiles) that can be decoded completely independently on separate CPU cores. No data flows between tiles.
- *Wavefront Parallel Processing (WPP):* rows of CTUs are processed in a diagonal wavefront pattern. Row 2 starts one CTU behind row 1, row 3 one CTU behind row 2, so many rows are in flight simultaneously on different cores.

At 4K resolution on a 16-core decoder chip, these structures allow near-linear speedup with core count — essential for real-time 4K playback on streaming devices.

== How Much Better Is HEVC?

The JCT-VC's target was a 50% bitrate reduction versus H.264 at matched quality. Did they hit it?

The answer is: roughly yes, with caveats. The official JCT-VC verification tests measured BD-rate savings of 39–44% on standard-definition test sequences, rising toward 50%+ on 1080p and 4K content where the larger CTU sizes shine most. For real-world content, x265 (the dominant open-source HEVC encoder, released July 2013 by MulticoreWare) consistently delivers 30–50% savings over x264 depending on content type and preset settings.

#definition("BD-rate (Bjøntegaard Delta Rate)")[
  You cannot compare two codecs by quoting one bitrate and one PSNR, because each codec has a whole *curve* of quality-versus-bitrate trade-offs: spend more bits, get higher PSNR. The honest question is "across a matched range of quality, how many fewer bits does codec B need than codec A?" The *BD-rate*, proposed by Gisle Bjøntegaard in 2001, answers exactly this. You measure each codec at four or more quality settings to get a list of $("bitrate", "PSNR")$ points, fit a smooth curve to each (in practice, interpolate in the $log$ of the bitrate, because bitrate behaves multiplicatively), then compute the average horizontal gap between the two curves over the overlapping quality range. The result is a single percentage. A BD-rate of $-44%$ means codec B reaches the *same* quality as codec A using 44% fewer bits on average. Negative is better; it is the standard yardstick the whole video field uses.
]

#mathrecall[
  The BD-rate code below "integrates" a curve by the *trapezoidal rule* from Chapter 11: the area under a curve sampled at points is approximated by summing the areas of the trapezoids between consecutive points, $0.5 (y_0 + y_1)(x_1 - x_0)$. Here the area under the PSNR-versus-$log("bitrate")$ curve, divided by the width of the overlap, is just the *average* PSNR over that range — which is what lets us compare two curves with one number.
]

#scoreboard(caption: "Codec progression on a 90-second 1080p test clip, constant quality",
  [Uncompressed 1080p/30],  [7,776,000,000], [1.0×],  [Raw YUV, no compression],
  [H.264/AVC (x264, medium)], [195,000,000], [40×],  [Baseline for comparison],
  [H.265/HEVC (x265, medium)],[110,000,000], [71×],  [~44% smaller than H.264],
  [H.266/VVC (VVenC, medium)], [62,000,000], [125×],  [~44% smaller than HEVC],
  [AV1 (SVT-AV1, medium)],    [75,000,000], [104×],  [~32% smaller than HEVC],
)

#aside[
  These numbers are illustrative benchmarks, not official test results. Real-world savings depend heavily on content (sports vs. animation vs. talking-head), resolution, and encoder preset. The ranking of codecs (VVC > AV1 > HEVC > H.264) is consistent with published academic BD-rate studies, however.
]

== The Patent Catastrophe

Here is where the story turns dark.

Every video codec standardized by ITU-T or ISO/IEC includes technology patented by dozens of companies. That is expected and acceptable: the standards process identifies which patents are "essential" to implementing the standard (Standard Essential Patents, or SEPs), and the patent holders agree to license them on *Fair, Reasonable, and Non-Discriminatory* (FRAND) terms. Typically one or a few patent pools consolidate the essential patents so a manufacturer pays a single license fee.

For H.264, MPEG LA ran a single pool from 2004 onward. Its terms were controversial but comprehensible. The royalty for an internet video distributor was initially zero (MPEG LA made it free for internet streaming for several years), which is a big part of why H.264 conquered the web so quickly.

For HEVC, the situation fragmented catastrophically.

=== Three Pools, No Consensus

When HEVC was published in 2013, two patent pools immediately competed:

1. *MPEG LA's HEVC pool:* The familiar administrator, with a set of essential patents but — crucially — missing patents from some major holders who refused to join on MPEG LA's terms.

2. *HEVC Advance (later renamed Access Advance):* A new pool that launched in 2015 with different royalty terms and different essential patent holders, including several that MPEG LA's pool lacked.

The result: to be fully licensed, a manufacturer might need to pay *both* pools. And even paying both pools was no guarantee of safety, because a third group of essential patent holders remained outside either pool entirely.

#history[
  MPEG LA was not a standards body but a private licensing administrator founded by Leonard Chitikin in 1997. Its first major pool was for MPEG-2, followed by H.264. Via Licensing (later Via Licensing Alliance, or Via LA) entered as a competitor administrator for several codecs. In 2023, MPEG LA was acquired by Via Licensing to form Via LA. In December 2025, Access Advance announced it was acquiring Via LA's HEVC and VVC patent pool programs, finally consolidating the two competing HEVC pools under a single administrator — twelve years after the standard launched.
]

=== The Royalty Calculation Problem

Even if a manufacturer paid both pools, the royalty calculations were murky. HEVC Advance's initial terms were widely criticized as requiring royalties from streaming services *and* device makers and content producers — a potential triple payment for the same bits. A Düsseldorf District Court ruled in December 2021 that Access Advance's duplicate royalty policy was not FRAND because of the substantial overlap of patents in both pools.

Samsung, the largest essential patent holder in MPEG LA's HEVC pool, withdrew from that pool between January and April 2020 and eventually joined Access Advance. Major manufacturers HP and TCL took HEVC licenses from Access Advance only in late 2024 — more than a decade after the standard was published.

#pitfall[
  "Paying one pool licensed you" is a common misunderstanding of the HEVC situation. With multiple pools each claiming essential patents — some of which were contested — and unaffiliated holders outside any pool, many manufacturers chose to simply absorb the legal risk and not license at all, or to avoid HEVC in their products entirely. This is not a hypothetical: it is documented behavior that slowed HEVC adoption measurably relative to H.264.
]

=== The Strategic Response

The patent mess had a concrete strategic consequence: it accelerated the royalty-free codec movement. Google had already bought On2 Technologies (February 2010, approximately \$124.6 million) and released VP9 in June 2013 — the same year as HEVC. VP9 was not as efficient as HEVC but it was free. Netflix, YouTube, and later Mozilla, Microsoft, and Amazon chose VP9 over HEVC for web delivery partly for technical reasons (better software decoder support) but partly because "free" is an extremely appealing license term when the alternative is a litigation minefield.

The Alliance for Open Media formed in September 2015 specifically to create a patent-unencumbered successor: AV1. We will cover AV1 in detail in Chapter 54. Here it is enough to say: the HEVC licensing crisis is the proximate cause of AV1's existence.

== HEVC in Practice: x265 and the Encoder Landscape

Despite the patent troubles, HEVC became the dominant codec for a specific, high-value niche: 4K content delivered to devices with hardware HEVC decoders.

Apple adopted HEVC as its default video format in 2017, baking it into iPhone camera capture and iCloud photo libraries. Netflix uses HEVC for 4K HDR delivery to Apple TV, smart TVs, and game consoles. Amazon Prime Video, Disney+, and virtually every major streamer use HEVC for their premium tier content.

The practical reason: hardware HEVC decode was built into most smartphones and smart TVs by 2016–2018. Once the silicon was everywhere, the codec could be used. The streaming services that had avoided HEVC for web delivery (where AV1 or VP9 ran in software on Chrome/Firefox) happily used it for the living-room TV where the dedicated decode chip made it free in both power and CPU cost.

The dominant encoder is *x265*, developed by MulticoreWare. First released in July 2013, it follows the same architecture as x264: a configurable number of presets from `ultrafast` to `veryslow`, a tunable quantization parameter (QP), and highly optimized assembly for modern SIMD instruction sets. A medium-speed x265 encode of a feature film runs roughly 3–5 frames per second on a modern CPU — slow, but acceptable for an encode-once/stream-billions workflow.

#gopython("Subprocess and Measurement")[
  Python's `subprocess` module lets you run external programs (like x265) from inside a script and capture their output. Here is the pattern we use in the code listings below:

  ```python
  import subprocess
  result = subprocess.run(
      ["x265", "--input", "video.y4m", "--output", "out.265"],
      capture_output=True,     # capture stdout and stderr
      text=True,               # decode bytes to strings
  )
  print(result.returncode)    # 0 means success
  print(result.stderr)        # x265 prints stats to stderr
  ```

  `subprocess.run()` blocks until the program finishes and returns a `CompletedProcess` object with the exit code and output. We use `capture_output=True` so we can parse the encoder statistics programmatically.
]

#gopython("Dictionaries for Structured Results")[
  A Python `dict[str, float]` maps string keys to floating-point values. We use it to collect codec measurement results:

  ```python
  result: dict[str, float] = {
      "bitrate_kbps": 2450.0,
      "psnr_y": 38.7,
      "bd_rate_vs_h264": -0.42,   # -42% means 42% smaller
  }
  print(f"PSNR: {result['psnr_y']:.1f} dB")
  # Output: PSNR: 38.7 dB
  ```

  The `f"..."` notation is an *f-string* — Python evaluates anything inside `{...}` and inserts the result into the string. The `:.1f` format code rounds to one decimal place.
]

== A Concrete Comparison: Measuring Compression

The following code listing is illustrative — it shows the measurement logic that would be used to compare codecs on a shared test clip. It does not require a real x265 or VVenC installation to understand.

#pyrecall[The listing uses `@dataclass` (Chapter 24) to bundle a `(bitrate, PSNR)` point into a tiny named record, and `key=lambda t: t[0]` (Chapter 16) to sort points by their first field. A `lambda` is just a one-line anonymous function: `lambda t: t[0]` means "given `t`, give back `t[0]`."]

```python
# codec_compare.py — measure BD-rate across HEVC quality levels
# (illustrative; requires x265 and ffmpeg in PATH for real use)

from dataclasses import dataclass
import math

@dataclass
class RatePoint:
    """One (bitrate, PSNR) point on a codec's rate-distortion curve."""
    bitrate_kbps: float
    psnr_db: float

def bd_rate(ref: list[RatePoint], test: list[RatePoint]) -> float:
    """
    Bjøntegaard Delta Rate: average % bitrate difference between two
    codecs at the same PSNR. Negative means 'test' is better (smaller).
    Requires at least 4 rate-distortion points for each codec.
    Uses log-domain linear interpolation per the ITU-T standard method.
    """
    def log_rate(pts: list[RatePoint]) -> list[tuple[float, float]]:
        return [(math.log(p.bitrate_kbps), p.psnr_db) for p in pts]

    def integrate(pts: list[tuple[float, float]]) -> float:
        """Trapezoidal integration of PSNR as a function of log(bitrate)."""
        total = 0.0
        for i in range(len(pts) - 1):
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            total += 0.5 * (y0 + y1) * (x1 - x0)
        return total

    ref_pts  = sorted(log_rate(ref),  key=lambda t: t[0])
    test_pts = sorted(log_rate(test), key=lambda t: t[0])

    # Overlap interval in log-bitrate space
    lo = max(ref_pts[0][0], test_pts[0][0])
    hi = min(ref_pts[-1][0], test_pts[-1][0])
    if hi <= lo:
        raise ValueError("Rate-distortion curves do not overlap")

    # Clip both curves to the overlap
    def clip(pts: list[tuple[float,float]]) -> list[tuple[float,float]]:
        return [(x, y) for x, y in pts if lo <= x <= hi]

    ref_clipped  = clip(ref_pts)
    test_clipped = clip(test_pts)
    span = hi - lo
    return (integrate(test_clipped) - integrate(ref_clipped)) / span

# Example: H.264 vs HEVC rate-distortion points at four quality levels
h264_curve = [
    RatePoint(500,  34.2),
    RatePoint(1000, 37.1),
    RatePoint(2000, 39.8),
    RatePoint(4000, 42.5),
]
hevc_curve = [
    RatePoint(280,  34.2),
    RatePoint(560,  37.1),
    RatePoint(1120, 39.8),
    RatePoint(2200, 42.5),
]

delta = bd_rate(h264_curve, hevc_curve)
print(f"HEVC BD-rate vs H.264: {delta:+.1f}%")
# Expected output: around -40% to -44%
```

#checkpoint[
  The `bd_rate()` function returns a negative number when the test codec is better. If it returns `-41.3`, what does that mean in plain English?
][
  It means the test codec (HEVC) achieves the same visual quality as the reference (H.264) using 41.3% fewer bits on average, measured across the overlapping range of quality levels.
]

== H.266 / VVC: The Next Leap

Work on HEVC's successor began almost immediately after HEVC finalized. The Joint Video Experts Team (JVET), successor to JCT-VC, issued a formal Call for Proposals in October 2017 for what they called "Future Video Coding." The target: another 50% improvement over HEVC. The standard was finalized as ITU-T H.266 and ISO/IEC 23090-3 on *6 July 2020*.

The "Versatile" in Versatile Video Coding reflects an explicit design goal: one codec that handles not just traditional 2D video but 360° immersive video, screen content (slideshows, text-heavy gaming streams), high dynamic range (HDR), wide colour gamut (WCG), and very high frame rates (up to 120 fps and beyond).

=== Multi-Type Tree Partitioning

HEVC's pure quadtree — which could only split a block into four equal square children — was replaced in VVC by the *Multi-Type Tree (MTT)*.

#definition("Multi-Type Tree (MTT)")[
  In VVC's MTT, a Coding Tree Unit (now up to 128×128 samples) can be split in five ways: the HEVC-style *quadtree* split (into four equal square quarters), or any of four *binary* or *ternary* splits (horizontal binary, vertical binary, horizontal ternary, vertical ternary). A ternary split divides a block into three unequal pieces: two narrow strips flanking a wide centre strip (in 1:2:1 proportions).
]

#fig(
  [VVC multi-type tree partition options for a rectangular block. From left to right: no split (unsplit), quadtree (QT), horizontal binary (HBT), vertical binary (VBT), horizontal ternary (HTT), vertical ternary (VTT). The ternary splits are new in VVC.],
  cetz.canvas({
    import cetz.draw: *
    let bw = 1.0
    let bh = 0.8
    let gap = 0.3
    // Unsplit
    rect((0,0),(bw,bh), stroke: 1pt + rgb("#0b5394"), fill: rgb("#e8f0fa"))
    content((bw/2, bh/2))[#text(size:5pt)[None]]
    // QT
    let ox = bw + gap
    rect((ox,0),(ox+bw,bh), stroke: 0.5pt)
    line((ox+bw/2,0),(ox+bw/2,bh), stroke: 0.8pt + rgb("#0b5394"))
    line((ox,bh/2),(ox+bw,bh/2), stroke: 0.8pt + rgb("#0b5394"))
    content((ox+bw/2, -0.18))[#text(size:5.5pt)[QT]]
    // HBT
    let ox2 = ox + bw + gap
    rect((ox2,0),(ox2+bw,bh), stroke: 0.5pt)
    line((ox2,bh/2),(ox2+bw,bh/2), stroke: 0.8pt + rgb("#783f04"))
    content((ox2+bw/2, -0.18))[#text(size:5.5pt)[HBT]]
    // VBT
    let ox3 = ox2 + bw + gap
    rect((ox3,0),(ox3+bw,bh), stroke: 0.5pt)
    line((ox3+bw/2,0),(ox3+bw/2,bh), stroke: 0.8pt + rgb("#783f04"))
    content((ox3+bw/2, -0.18))[#text(size:5.5pt)[VBT]]
    // HTT
    let ox4 = ox3 + bw + gap
    rect((ox4,0),(ox4+bw,bh), stroke: 0.5pt)
    line((ox4,bh*0.25),(ox4+bw,bh*0.25), stroke: 0.8pt + rgb("#0b6e4f"))
    line((ox4,bh*0.75),(ox4+bw,bh*0.75), stroke: 0.8pt + rgb("#0b6e4f"))
    content((ox4+bw/2, -0.18))[#text(size:5.5pt)[HTT]]
    // VTT
    let ox5 = ox4 + bw + gap
    rect((ox5,0),(ox5+bw,bh), stroke: 0.5pt)
    line((ox5+bw*0.25,0),(ox5+bw*0.25,bh), stroke: 0.8pt + rgb("#0b6e4f"))
    line((ox5+bw*0.75,0),(ox5+bw*0.75,bh), stroke: 0.8pt + rgb("#0b6e4f"))
    content((ox5+bw/2, -0.18))[#text(size:5.5pt)[VTT]]
  })
)

Why do non-square splits help so much? Consider a vertical edge in the frame — the border between a bright window and a dark wall. In HEVC, the quadtree can only split the block containing this edge into four square pieces. The edge might still cut diagonally through each piece, leaving costly residuals everywhere. With a vertical binary split, the encoder can place the block boundary exactly along the edge, giving one block that is pure bright and one that is pure dark. Both can be predicted trivially, leaving near-zero residuals.

The MTT also allows the 128×128 maximum CTU size, up from 64×64 in HEVC. For 8K UHD content (7680×4320), this is especially valuable.

=== Affine Motion Compensation

H.264 and HEVC used *translational* motion models: a block moved $Delta x$ pixels left/right and $Delta y$ pixels up/down. This is an excellent model for objects sliding across the frame, but it fails for objects that rotate (a spinning coin) or zoom (a car approaching the camera). For these cases, the residual is large and wastes bits.

VVC adds *affine motion compensation*, which models a block's motion with a 6-parameter affine transformation:

$ x' = a x + b y + c_0 $
$ y' = d x + e y + f_0 $

This can represent translation, rotation, scaling, and shear — all common in real video. The encoder signals the affine parameters rather than a single motion vector. The decoder applies the affine warp to the reference frame to generate the prediction.

#gomaths("Affine Transformations")[
  An *affine transformation* is any map that preserves straight lines and parallel lines. In 2D, it has the form:
  $ mat(x'; y') = mat(a, b; d, e) mat(x; y) + mat(c_0; f_0) $
  The $2 times 2$ matrix handles rotation, scaling, and shear; the vector $(c_0, f_0)$ handles translation. If $a=e=1$ and $b=d=0$, you get pure translation — the same as an H.264/HEVC motion vector. The extra four parameters ($a, b, d, e$) cost a few more bits to signal but eliminate large residuals for rotating or zooming objects. This is a classic rate-distortion trade-off: spend a few more bits on the model to save many more bits on the residual.
]

=== Palette Mode for Screen Content

Traditional video codecs were designed for *camera-captured content*: natural scenes with gradual color gradients and no sharp, repeating color regions. Screen content — desktop screenshots, game streams, slide presentations, subtitles — looks completely different. It has sharp color boundaries, large flat regions, and repeating patterns that normal intra prediction handles poorly.

VVC introduces *Palette Mode*: instead of predicting a block from its neighbors via an angular mode, the encoder signals a small *palette* (a list of up to 31 colors) and then encodes each pixel as an index into the palette. For a screenshot with 8 distinct colors, this is vastly more efficient than any transform-based approach.

Palette mode is not an obvious compression tool for natural video, but it makes VVC far more competitive with specialized screen-content codecs like RDP or VNC for mixed-content streams.

=== Adaptive Loop Filter (ALF)

VVC adds a third in-loop filter on top of HEVC's deblocking filter and SAO: the *Adaptive Loop Filter (ALF)*. ALF is a Wiener filter — a small convolution kernel — whose coefficients are optimized by the encoder for each frame and signaled in the bitstream. The decoder applies the filter to the reconstructed frame, further removing ringing and blurring introduced by quantization.

A Wiener filter with, say, 7×7 coefficients can be tuned to match the statistical profile of quantization noise for the specific content and QP value being used, achieving better noise removal than a fixed filter. The cost is a modest bit overhead to signal the filter coefficients, but the quality gain consistently outweighs it.

== How Much Better Is VVC?

The JVET's target was 50% over HEVC. Published academic BD-rate studies on UHD test sequences consistently find 40–50% savings versus HEVC, with results toward the higher end for 4K and 8K content where the larger 128×128 CTU shines. At the same time, VVC is measured to be approximately 10–15% better than AV1 on the same test sequences — a meaningful edge.

The price is complexity. Encoding with VVC is roughly 10 times more complex than encoding with HEVC. Even the *decoder* is roughly twice as complex, which matters for battery-powered devices. This is the same arms race we saw with every previous generation.

The practical tooling is open source and improving fast. Fraunhofer HHI (the institute that has been central to H.264, HEVC, and VVC development) maintains two key projects:

- *VVenC* (Fraunhofer Versatile Video Encoder): production-quality, multi-preset VVC encoder. By January 2026 it reached version 1.14, delivering speedups of 20× to over 2,000× compared to the VTM reference encoder, depending on the preset.
- *VVdeC* (Fraunhofer Versatile Video Decoder): fully compliant VVC Main 10 decoder, capable of real-time HD playback at 60 fps on modern laptops using only 2–3 threads.

=== Hardware Adoption

The VVC story in hardware is more promising than HEVC's slow rollout. MediaTek's Pentonic 700 and 800 chipsets, powering 2024–2025 smart TVs from Samsung, LG, and Sony, include dedicated VVC hardware decode. The key question is mobile: VVC hardware decode in mainstream smartphones is not yet widely deployed as of mid-2026, meaning that battery-constrained devices still rely on software decode — which drains the battery. Expect VVC to follow the HEVC pattern: living-room hardware first, mobile hardware 2–4 years later.

== VVC's Patent Situation: Learning from HEVC

Did the standards bodies learn from the HEVC licensing disaster? Partially.

VVC's essential patents are again distributed across multiple holders. Two pools formed: Access Advance's "VVC Advance" and Via LA's VVC pool. In December 2025, Access Advance announced the acquisition of Via LA's HEVC and VVC patent pool programs — renaming the combined holding the "VCL Advance" (Video Codec Licensing) program. This consolidation was widely welcomed; having a single administrator for both pools is an improvement over the fragmented HEVC situation.

However, consolidation of the two pools is not the same as universal coverage. Numerous essential patent holders remain outside VCL Advance into 2026. The situation is better than early HEVC but not clean. The royalty-free AV1 and forthcoming AV2 continue to attract content providers who prefer "free and clear" to "probably cheaper if you navigate carefully."

#misconception[
  "VVC is the obvious successor to HEVC for streaming."
][
  This depends entirely on your use case, your legal team, and your hardware footprint. For 4K living-room delivery to devices with VVC silicon, VVC's superior compression is compelling. For web delivery where JavaScript-based or software decoders dominate, the royalty-free AV1 (and soon AV2) may be preferable despite inferior compression ratios, because deployment complexity and legal exposure matter as much as bits saved.
]

== Putting It Together: The Codec Decision Tree

When a streaming engineer in 2026 asks "which codec should I use?", the answer is a decision tree, not a single answer. Here is a simplified version of the real trade-offs:

#fig(
  [Codec selection decision tree as of mid-2026. Choice depends on resolution, target hardware, licensing tolerance, and content type.],
  cetz.canvas({
    import cetz.draw: *
    // Root
    rect((2,5.5),(5,6.2), fill: rgb("#e8f0fa"), stroke: 0.8pt + rgb("#0b5394"), radius: 2pt)
    content((3.5,5.85))[#text(size:6.5pt, weight:"bold")[Target hardware has\ VVC decode?]]
    // Yes branch
    line((3.5,5.5),(1.5,4.5), stroke: 0.7pt)
    content((2.1,5.05))[#text(size:5.5pt, fill: rgb("#0b6e4f"))[Yes]]
    rect((0.5,3.8),(2.5,4.5), fill: rgb("#e8faf0"), stroke: 0.8pt + rgb("#0b6e4f"), radius: 2pt)
    content((1.5,4.15))[#text(size:6.5pt)[Use *VVC*\ (H.266)]]
    // No branch — AV1
    line((3.5,5.5),(5.5,4.5), stroke: 0.7pt)
    content((4.9,5.05))[#text(size:5.5pt, fill: rgb("#783f04"))[No]]
    rect((4.5,3.4),(6.5,4.5), fill: rgb("#faf7ee"), stroke: 0.8pt + rgb("#783f04"), radius: 2pt)
    content((5.5,3.95))[#text(size:6.5pt)[Web/mobile?\ Use *AV1*\ (royalty-free)]]
    // Legacy
    line((3.5,5.5),(3.5,4.5), stroke: 0.7pt)
    content((3.7,5.0))[#text(size:5.5pt)[Legacy?]]
    rect((2.7,3.4),(4.3,4.5), fill: rgb("#faf0f0"), stroke: 0.8pt + rgb("#9a2617"), radius: 2pt)
    content((3.5,3.95))[#text(size:6.5pt)[Use *HEVC*\ (H.265)]]
  })
)

== The Technical Lineage at a Glance

#fig(
  [The H.26x codec lineage: each generation roughly doubles efficiency at the cost of doubled (or greater) encoding complexity.],
  cetz.canvas({
    import cetz.draw: *
    // H.264 box
    rect((0.4, 0),(1.6, 1.5), fill: rgb("#e8f0fa"), stroke: 0.8pt + rgb("#0b5394"), radius: 3pt)
    content((1.0, 1.1))[#text(size:6.5pt, weight:"bold")[H.264/AVC]]
    content((1.0, 0.65))[#text(size:6pt, fill: rgb("#783f04"))[2003]]
    content((1.0, 0.25))[#text(size:6pt, fill: rgb("#0b6e4f"))[1.0× bitrate]]
    // Arrow 1
    line((1.6, 0.75),(2.4, 0.75), mark: (end: ">"), stroke: 0.7pt + rgb("#0b5394"))
    content((2.0, 1.0))[#text(size:5.5pt, fill:rgb("#783f04"))[~50%\ smaller]]
    // H.265 box
    rect((2.4, 0),(3.6, 1.5), fill: rgb("#e8f0fa"), stroke: 0.8pt + rgb("#0b5394"), radius: 3pt)
    content((3.0, 1.1))[#text(size:6.5pt, weight:"bold")[H.265/HEVC]]
    content((3.0, 0.65))[#text(size:6pt, fill: rgb("#783f04"))[2013]]
    content((3.0, 0.25))[#text(size:6pt, fill: rgb("#0b6e4f"))[~0.5× bitrate]]
    // Arrow 2
    line((3.6, 0.75),(4.4, 0.75), mark: (end: ">"), stroke: 0.7pt + rgb("#0b5394"))
    content((4.0, 1.0))[#text(size:5.5pt, fill:rgb("#783f04"))[~50%\ smaller]]
    // H.266 box
    rect((4.4, 0),(5.6, 1.5), fill: rgb("#e8f0fa"), stroke: 0.8pt + rgb("#0b5394"), radius: 3pt)
    content((5.0, 1.1))[#text(size:6.5pt, weight:"bold")[H.266/VVC]]
    content((5.0, 0.65))[#text(size:6pt, fill: rgb("#783f04"))[2020]]
    content((5.0, 0.25))[#text(size:6pt, fill: rgb("#0b6e4f"))[~0.25× bitrate]]
    content((3.0, -0.25))[#text(size:6.5pt)[Bitrate relative to H.264 at equal quality]]
  })
)

== Algorithm Profiles

#algo(
  name: "H.265 / HEVC",
  year: "2013",
  authors: "JCT-VC (ITU-T VCEG + ISO/IEC MPEG); key contributors: Fraunhofer HHI, Samsung, Qualcomm, Microsoft",
  aim: "~50% bitrate reduction over H.264/AVC at matched perceptual quality for HDTV, UHD, and 4K content",
  complexity: "Encoding: ~3–10× H.264 at matched presets; Decoding: ~1.5–2× H.264",
  strengths: "Universal hardware decode support (2016–present phones and TVs); dominant for 4K HDR streaming; well-optimised open-source encoder (x265)",
  weaknesses: "Patent licensing fragmentation slowed adoption for nearly a decade; royalty overhead remains for device makers; not royalty-free",
  superseded: "H.266/VVC (partially); AV1 (for royalty-free web delivery)",
)[]

#algo(
  name: "H.266 / VVC — Versatile Video Coding",
  year: "2020",
  authors: "JVET (ITU-T VCEG + ISO/IEC MPEG); key contributors: Fraunhofer HHI, Qualcomm, Apple, Samsung, ByteDance",
  aim: "~50% bitrate reduction over HEVC; support for 360°, HDR, screen content, 8K/120fps; unified codec across all content types",
  complexity: "Encoding: ~10× HEVC at matched presets; Decoding: ~2× HEVC",
  strengths: "Best-in-class compression efficiency as of 2026; open-source VVenC/VVdeC implementations; hardware decode in 2024–2025 smart TV chipsets",
  weaknesses: "Patent pool still fragmented (VCL Advance does not cover all essential holders); limited mobile hardware decode; high encode complexity limits real-time use",
  superseded: "Not yet superseded as of mid-2026; AV2 is the expected successor for the royalty-free path",
)[]

== Lessons from Two Generations

Looking across the HEVC and VVC stories, several patterns emerge that will recur in Chapter 54 (AV1) and beyond.

*The 50% gain is real but content-dependent.* Both HEVC and VVC hit their ~50% BD-rate targets on the standard test sequences they were optimized against. Real-world gains depend heavily on content type, resolution, and the specific encoder settings used.

*Codec adoption is driven by hardware, not specs.* A codec that exists only as a software encoder is a research project. Mass adoption requires chip-level integration: dedicated decode hardware that runs fast and cheap enough for battery-powered devices. HEVC took 3–4 years after its 2013 publication to achieve that scale. VVC is following the same curve.

*Licensing friction imposes a real cost, measurable in market share.* HEVC's patent pool mess is not just an IP-lawyer complaint — it is measurable in the billions of streaming hours delivered via VP9 and AV1 that would have gone via HEVC if licensing had been clean. The entire AV1 ecosystem exists, in significant part, as a response to that friction.

*Encoder and decoder are different products.* The standard defines only the bitstream and the decoder. Encoder quality is a separate competitive landscape. Two HEVC encoders from different teams can differ by 30%+ in efficiency at the same preset speed. This is why x265 (open source, well-optimized) is often preferred over commercial alternatives for its combination of quality and cost.

== Exercises

#exercise("53.1", 1)[
  A streaming service encodes a 4K movie at 10 Mbps using H.264. Using the rough rule that HEVC saves 44% of bitrate versus H.264 at equal quality, what bitrate would HEVC need to deliver the same visual quality? Show your arithmetic.
]
#solution("53.1")[
  HEVC needs $10 "Mbps" times (1 - 0.44) = 10 times 0.56 = 5.6 "Mbps"$. This is the direct application of the 44% BD-rate saving: at equal quality, the HEVC stream is 44% smaller in bits per second.
]

#exercise("53.2", 1)[
  In HEVC, the maximum CTU size is 64×64. How many 64×64 CTUs does a 3840×2160 (4K UHD) frame contain? How many 16×16 macroblocks would the same frame contain in H.264?
]
#solution("53.2")[
  CTU count: $(3840 / 64) times (2160 / 64) = 60 times 33.75$. Since 2160 is not divisible by 64 ($2160 = 33 times 64 + 48$), the last row uses partial CTUs; in practice the frame is padded to a multiple of 64. With padding: $(3840/64) times (2176/64) = 60 times 34 = 2040$ CTUs. H.264 macroblock count: $(3840/16) times (2160/16) = 240 times 135 = 32,400$ macroblocks. HEVC processes roughly 16× fewer top-level units for the same frame, with each unit able to cover flat regions without subdivision.
]

#exercise("53.3", 2)[
  Explain in your own words why the multi-type tree (MTT) in VVC is better than the pure quadtree in HEVC for a frame containing a vertical line (e.g., a door frame). Draw a sketch showing how each codec would partition a block that contains such a vertical line near the centre.
]
#solution("53.3")[
  HEVC's quadtree can only split a block into four equal square quadrants. If a vertical edge cuts through the middle of a 32×32 block, the quadtree splits it into four 16×16 blocks, each still bisected by the edge. Only after another level of splitting (to 8×8) can individual blocks be fully on one side of the edge. VVC's MTT adds a vertical binary tree split: the encoder places a vertical cut exactly along the edge, giving a left block that is purely "wall" and a right block that is purely "door." Both blocks are trivially predictable, leaving near-zero residuals. The key efficiency gain is that the cut can be placed precisely where the content demands it, at any horizontal position, not only at powers-of-two offsets.
]

#exercise("53.4", 2)[
  The HEVC patent situation involved at least two competing pools. In your own words, explain what a patent pool is, what "FRAND" means, and why having two overlapping pools for the same standard creates problems for manufacturers.
]
#solution("53.4")[
  A *patent pool* is an arrangement where multiple patent holders contribute their patents to a central administrator, who then licenses the entire bundle to manufacturers for a single fee. This is more efficient than each holder negotiating separately. *FRAND* stands for Fair, Reasonable, and Non-Discriminatory — the terms under which standard essential patent holders are obligated to license. Two overlapping pools for the same standard create problems because: (1) a manufacturer may need to pay both pools to be fully licensed, doubling the cost; (2) if the same patent appears in both pools, the manufacturer may be charged twice for the same technology — which a German court ruled was not FRAND in the HEVC case; (3) even paying both pools may not protect against unaffiliated holders suing independently. The resulting legal uncertainty leads some manufacturers to avoid the codec entirely.
]

#exercise("53.5", 3)[
  Implement a Python function `bd_rate_approx(ref_points, test_points)` that takes two lists of `(bitrate_kbps, psnr_db)` tuples and returns an approximate Bjøntegaard Delta Rate (BD-rate) percentage using piecewise linear interpolation in log-bitrate space. Test it with the H.264 vs HEVC numbers from the chapter's code listing and verify you get roughly -40% to -44%.
]
#solution("53.5")[
  ```python
  import math

  def bd_rate_approx(
      ref_points: list[tuple[float, float]],
      test_points: list[tuple[float, float]],
  ) -> float:
      """Return BD-rate (%) of test vs reference. Negative = test is better."""
      def log_pts(pts):
          return sorted([(math.log(r), p) for r, p in pts])

      def trapz(pts):
          area = 0.0
          for i in range(len(pts) - 1):
              x0, y0 = pts[i]; x1, y1 = pts[i+1]
              area += 0.5 * (y0 + y1) * (x1 - x0)
          return area

      rp = log_pts(ref_points)
      tp = log_pts(test_points)
      lo = max(rp[0][0], tp[0][0])
      hi = min(rp[-1][0], tp[-1][0])
      rp = [(x, y) for x, y in rp if lo <= x <= hi]
      tp = [(x, y) for x, y in tp if lo <= x <= hi]
      span = hi - lo
      if span <= 0:
          return float("nan")
      return (trapz(tp) - trapz(rp)) / span

  # Test
  h264 = [(500, 34.2), (1000, 37.1), (2000, 39.8), (4000, 42.5)]
  hevc = [(280, 34.2), (560,  37.1), (1120, 39.8), (2200, 42.5)]
  print(f"{bd_rate_approx(h264, hevc):+.1f}%")  # should be around -40% to -44%
  ```
]

#exercise("53.6", 3)[
  In VVC, affine motion compensation models a block's motion with up to 6 parameters ($a, b, c_0, d, e, f_0$), using the two equations $x' = a x + b y + c_0$ and $y' = d x + e y + f_0$ from the chapter. For a block where the only motion is pure translation by $(Delta x, Delta y)$, what values do the six parameters take? For a block that is uniformly scaled by a factor $s$ (zooming in) about its center, how do the parameters look (approximately)?
]
#solution("53.6")[
  For pure translation $(Delta x, Delta y)$: $a=1, e=1, b=0, d=0, c_0=Delta x, f_0=Delta y$. The affine map then becomes $x' = x + Delta x$ and $y' = y + Delta y$ — identical to a simple motion vector.

  For uniform scaling by factor $s$ about the block centre $(x_c, y_c)$: the transform is $x' = s(x - x_c) + x_c = s dot x + x_c(1-s)$ and similarly for $y$. So $a=e=s$, $b=d=0$, $c_0=x_c(1-s)$, $f_0=y_c(1-s)$. For $s>1$ (zoom in), $c_0$ and $f_0$ are negative offsets; for $s<1$ (zoom out), they are positive offsets. The key insight is that pure translation is a special case of the affine model, and affine compensation generalizes it to handle zoom and rotation without needing a separate signaling mechanism.
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/6316136")[Sullivan, G. J., Ohm, J., Han, W., and Wiegand, T. (2012). *Overview of the High Efficiency Video Coding (HEVC) Standard.* IEEE Transactions on Circuits and Systems for Video Technology, 22(12), 1649–1668.] — The definitive overview paper for H.265/HEVC by four of its primary architects.

- #link("https://hevc.hhi.fraunhofer.de/")[Fraunhofer HHI — HEVC Overview.] — The research group most central to HEVC development maintains a resource page with test sequences, encoder/decoder software, and technical documentation.

- #link("https://github.com/fraunhoferhhi/vvenc")[Fraunhofer VVenC — open-source VVC encoder.] — Production-quality VVC encoder with multiple presets; the fastest practical path to real VVC encoding without the VTM reference complexity.

- #link("https://github.com/fraunhoferhhi/vvdec")[Fraunhofer VVdeC — open-source VVC decoder.] — The companion decoder; can achieve real-time HD decoding on modern CPUs.

- #link("https://streaminglearningcenter.com/codecs/hevc-licensing-misunderstood-maligned-and-surprisingly-successful.html")[Ozer, J. (2023). *HEVC Licensing: Misunderstood, Maligned, and Surprisingly Successful.* Streaming Learning Center.] — The most accessible and honest analysis of the HEVC patent situation and its real-world impact on adoption.

- #link("https://accessadvance.com/licensing-programs/vvc-advance/")[Access Advance — VVC Advance Patent Pool.] — Current licensing terms and pool membership for VVC essential patents under VCL Advance (formerly VVC Advance + Via LA).

- #link("https://arxiv.org/pdf/2206.15311")[Wieckowski, A. et al. (2022). *Performance Analysis of Optimized Versatile Video Coding Software Decoders on Embedded Platforms.* arXiv:2206.15311.] — Rigorous measurement of VVC decoder complexity and real-time performance on resource-constrained hardware.

#bridge[
  HEVC and VVC demonstrate what is possible when a large standardization consortium pools the best ideas from dozens of companies: each generation achieves roughly 50% better compression, and the tools to exploit those gains (CTUs, MTT, affine motion, palette mode) are genuinely clever engineering. But both codecs were shaped — and in HEVC's case, wounded — by the patent licensing structures surrounding them.

  In Chapter 54 we turn to the direct response: the royalty-free AV1 codec developed by the Alliance for Open Media. We will see how the AV1 team borrowed many of the same ideas as HEVC and VVC but organized the IP situation completely differently — and whether that bet is paying off in practice in 2024–2026.
]

#takeaways((
  "HEVC (H.265, 2013) replaced H.264's fixed 16×16 macroblock with flexible Coding Tree Units (CTUs) up to 64×64, enabling large flat regions to be coded as a single unit and saving roughly 44% of H.264's bitrate at matched quality.",
  "HEVC's five key improvements over H.264 are: larger CTUs (quadtree partition), 35-direction angular intra prediction, Sample Adaptive Offset (SAO) in-loop filter, improved CABAC entropy coding, and tile/wavefront parallel processing.",
  "VVC (H.266, finalized 6 July 2020) replaced HEVC's pure quadtree with a Multi-Type Tree (MTT) supporting binary and ternary splits, expanded CTUs to 128×128, added affine motion compensation, palette mode, and an adaptive loop filter — delivering ~50% better compression than HEVC.",
  "HEVC's patent licensing fragmented into at least two competing pools (MPEG LA and HEVC Advance/Access Advance), with unaffiliated holders outside both. This slowed adoption and directly motivated the creation of the royalty-free AV1 codec by the Alliance for Open Media.",
  "In December 2025, Access Advance acquired Via LA's HEVC and VVC patent pool programs, consolidating administration under the VCL Advance brand — but essential patent holders outside the pool remain, and the situation is not fully resolved.",
  "Codec adoption is driven by hardware decode support, not by specification publication. HEVC hit consumer hardware by ~2016–2018; VVC hardware decode appeared in living-room TV chipsets in 2024–2025; widespread mobile VVC hardware is still expected 2027–2028.",
  "The BD-rate metric quantifies codec efficiency as the average percentage difference in bitrate at equal quality across multiple rate points. A BD-rate of -44% means the new codec is 44% cheaper at matched quality.",
))
