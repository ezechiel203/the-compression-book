#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= H.261 to H.264/AVC: The Workhorse Era

#epigraph[
  The standard only defines the decoder. How cleverly you find the answer
  is entirely up to you.
][Gary Sullivan, chair of the Joint Video Team, 2003]

Imagine you are watching a film on your phone right now — any streaming service, any country, any device made in the last fifteen years. Odds are better than 8-in-10 that the video reaching your eyes is compressed with a standard whose first version was finished in a university conference room in Fairfax, Virginia, in May 2003. That standard is H.264/AVC, and it is without question the most universally deployed video codec in history. Its 84% production-adoption figure in 2026 dwarfs every competitor. To understand why, you need to trace the forty-year lineage that made it possible — and to understand what every single video codec built since has either borrowed or rebelled against.

This chapter follows that lineage: from the tentative first steps of H.261 in the late 1980s, through the DVD-era triumph of MPEG-2, the chaotic interregnum of H.263 and DivX piracy, and finally to the careful engineering that made H.264/AVC the workhorse of the modern internet.

#recap[
  Chapter 51 opened the door to video compression: we saw how *temporal redundancy* lets a codec predict most of the next frame from the previous one using *block motion compensation*, and how the leftover *prediction residual* is then treated like a JPEG image — transformed, quantized, and entropy-coded. We built a tiny inter-prediction demo in `tinyzip` (Step 20). Here we trace how those ideas were standardized, refined, and eventually turned into the codec that now handles the majority of human video consumption.
]

#objectives((
  [Name every standard in the H.26x/MPEG video lineage and place it on a timeline from 1988 to 2003.],
  [Explain what H.261 introduced and why it was limited to low-resolution videoconferencing.],
  [Describe the MPEG-1 and MPEG-2 pipeline, including I/P/B frames, the GOP, and the macroblock.],
  [Trace H.263 and MPEG-4 Part 2 as the bridge to the internet era, including DivX and XviD.],
  [List the key innovations in H.264/AVC — variable block sizes, multiple references, quarter-pixel motion, in-loop deblocking, CAVLC, and CABAC — and explain what each one buys.],
  [Explain what "profile" and "level" mean, and name the four main H.264 profiles.],
  [Understand why the codec standard and the encoder are different things, and why two compliant encoders can differ by 30% in quality.],
  [Describe H.264's patent and licensing history, including the 2026 fee escalation.],
))

== The Shape of the Problem

Before we go codec-by-codec, let us make sure the fundamental challenge is crystal-clear, because every innovation in this chapter is a direct response to it.

A raw HD video frame at 1920×1080 pixels, 24-bit color, is roughly 6 megabytes. At 30 frames per second, one second of raw video is about 178 megabytes. A two-hour film would be over 1.2 *terabytes* — more than the storage of most laptops. Streaming that over a home internet connection at its raw size would require a connection roughly 1,400× faster than the average in 2003. Even today, uncompressed video is impractical for almost all consumer uses.

The good news, reviewed in Chapter 51, is that video contains two massive flavors of redundancy. *Spatial redundancy*: within a single frame, neighboring pixels are strongly correlated (the sky is blue across hundreds of pixels; a face has smooth gradients). *Temporal redundancy*: from one frame to the next, most of the picture has barely changed. A codec's job is to find and remove both.

The core loop is this:

+ *Predict* a block from previously decoded data (either a nearby block in the same frame, or a matching block in a reference frame, displaced by a motion vector).
+ *Subtract* the prediction from the actual block to get the *residual* — a block of small numbers.
+ *Transform* the residual (usually a DCT variant) to concentrate its energy.
+ *Quantize* the coefficients, trading precision for fewer bits.
+ *Entropy-code* the resulting sparse coefficient stream.

The decoder reverses the process: entropy-decode, de-quantize, inverse-transform, add prediction. Every standard we will study implements this loop; they differ in how elaborately they implement each step.

#gomaths("Integer vs real-valued transforms")[
  In JPEG (Chapter 42) we used the real-valued DCT. Decoder and encoder could differ by a tiny rounding error — harmless for a still image. In a video codec the prediction for frame *t+1* depends on what the *decoder* reconstructed for frame *t*. If encoder and decoder compute slightly different numbers, errors *accumulate* frame by frame, causing "encoder–decoder mismatch drift."

  The solution H.264 adopted (and every standard since) is an *integer transform*: a carefully chosen integer approximation of the DCT that produces bit-identical results on every conforming decoder in the world, regardless of operating system or hardware. The trade-off is a tiny quality loss versus the true DCT — but the gain in predictability is invaluable. Think of it as choosing a less elegant knife that everyone sharpens to exactly the same angle, so the dish always tastes the same.
]

== H.261 (1988–1990): The First Practical Standard

The story begins with a problem that has nothing to do with entertainment: companies wanted to hold video calls over ISDN telephone lines. ISDN came in multiples of 64 kbit/s — 64, 128, 192 kbit/s up to 2 Mbit/s. The ITU's Video Coding Experts Group (VCEG) set out to define a standard that would work at those rates.

The result, approved in November 1988 and published in 1990 as ITU-T Recommendation H.261, was the first video codec to use the hybrid block-based motion-compensation + transform framework that every later standard inherits. The key decisions H.261 made:

- *The macroblock*: divide the frame into 16×16-pixel blocks (called macroblocks), each covering four 8×8 luma (brightness) blocks plus two 8×8 chroma (color) blocks, in the 4:2:0 sampling we met in Chapter 42 — the chroma is stored at half resolution in each direction, so one 8×8 chroma block covers the whole 16×16 region. (Chapter 42 explained the YCbCr split and why the eye barely notices the coarser color.) This macroblock — luma at full resolution, chroma subsampled, all wrapped into one addressable unit — became the universal currency of video coding for the next thirty years.

- *Two frame resolutions*: CIF (352×288) and QCIF (176×144), small enough to compress usefully at ISDN rates.

- *Motion compensation*: P-frames (predicted frames) each macroblock could copy a displaced 16×16 block from the previous frame, with a motion vector accurate to one full pixel.

- *The DCT residual*: after motion compensation, the 8×8 residual block was transformed with the standard DCT, quantized, and entropy-coded with run-length coding plus a fixed Huffman table.

H.261 did not invent these ideas individually — block matching, DCT, and entropy coding had existed in research labs — but it was the first standard to specify the *complete pipeline* in enough detail that equipment from different vendors could interoperate. That interoperability was the whole point: a Panasonic camera talking to a Sony receiver over a German ISDN line.

What H.261 could not do: it was designed for CIF/QCIF images at talking-head quality. Full-motion natural video at even standard-definition quality was beyond it. The residual Huffman table was fixed (not adaptive). Motion vectors were only integer-pixel-accurate. There were no B-frames. The standard was deliberately minimal, enough for its target application.

#history[
  H.261's name refers to a coding rate of "p×64 kbit/s" — the "p" in the ITU naming system standing for any positive integer. When the standard was drafted, the committee had to demonstrate that the proposed algorithm could run on hardware that would actually be affordable. The reference design was implemented partly in custom silicon because the general-purpose processors of 1988 were far too slow to decode video in real time. The idea that your phone would casually run H.264 at 4K resolution would have seemed like science fiction.
]

== MPEG-1 (1992): Bringing Video to the CD

While VCEG was focused on videoconferencing, a different group — ISO's Moving Picture Experts Group (MPEG) — had a more ambitious target: compress video good enough for a consumer medium. In 1988, they launched a project to fit an hour of reasonable-quality video onto a single 650 MB CD-ROM at 1.5 Mbit/s (the CD drive's sustained transfer rate).

MPEG-1, published as ISO/IEC 11172 in 1992, extended H.261 in two critical directions:

*B-frames (bi-directional predicted frames)*. An I-frame is coded alone. A P-frame is predicted from one past frame. A B-frame is predicted from *both a past and a future frame simultaneously*, choosing the better of (a) a copy from the past, (b) a copy from the future, or (c) an average of both. Because real motion is often locally linear — an object moves at roughly constant speed for a few frames — the average of "where it came from" and "where it's going" is a superb prediction. B-frames can be 30–50% smaller than P-frames.

The catch: a B-frame needs its future reference before it can be decoded. So the encoder *reorders* frames: it sends the future reference *earlier* in the bitstream than the B-frames that need it, even though it appears *later* in display order. Encoder and decoder must each maintain a buffer to handle this reordering. The result is a repeating *Group of Pictures* (GOP) pattern, such as:

#align(center, block[
  `I B B P B B P B B P B B I …`\
  (coding order: I P B B P B B P B B I …)
])

Longer GOPs (more P and B frames between I-frames) compress better but make random-access seeking slower, since you must find the nearest I-frame to start.

*Half-pixel-accurate motion*: MPEG-1 extended motion vector accuracy from integer to *half-pixel* (half-pel). A half-pel position does not exist in the source image — you generate it by linearly interpolating between two real pixels. The extra precision significantly reduces the residual for any non-integer motion, at the cost of some extra computation.

MPEG-1 Video at 1.5 Mbit/s produced quality roughly comparable to a mediocre VHS tape — watchable but not impressive by broadcast standards. It became the technology behind Video CDs (VCDs), widely popular in Asia through the 1990s, and early internet video formats.

#aside[
  The "MP3" in the audio file format millions of us grew up with stands for MPEG-1 Audio Layer III — a reminder that MPEG-1 was a *combined* audio+video standard. The video portion is largely forgotten today; the audio coder (developed at Fraunhofer IIS in Erlangen, Germany) became one of the most culturally significant technologies in history. Chapter 47 covers MP3 in depth.
]

== MPEG-2 / H.262 (1994–1995): The DVD and Broadcast Workhorse

MPEG-1 was a proof of concept. MPEG-2 was the industrial-strength successor, jointly developed by MPEG and ITU-T VCEG (giving it the dual name MPEG-2 / H.262) and published in 1994–1995. Its target was broadcast-quality video at 2–30 Mbit/s.

The main additions over MPEG-1:

- *Interlaced video support*: broadcast television in the 1990s was interlaced — each frame was split into two "fields" (odd lines, then even lines) transmitted alternately, a legacy of 1940s television engineering. MPEG-2 added field-based prediction and field-adaptive encoding so interlaced content compressed well.

- *Scalable profiles*: different hardware capabilities and bandwidth budgets needed different quality levels. MPEG-2 introduced the concept of *profiles* (which tools are allowed) and *levels* (resolution and bitrate caps). The "Main Profile at Main Level" (MP\@ML) specified standard-definition video; "Main Profile at High Level" (MP\@HL) specified HD.

- *Higher resolutions*: MPEG-2 was designed for 720×480 (NTSC) and 720×576 (PAL) standard definition, and stretched to 1920×1080 HDTV.

MPEG-2 became the codec of choice for:
- DVD-Video (up to 9.8 Mbit/s per the DVD specification)
- Digital satellite TV (DirecTV launched in the USA in June 1994 using MPEG-2)
- Digital cable (CableLabs-certified systems)
- ATSC digital broadcast television in the US (at up to 19.39 Mbit/s)
- DVB (Digital Video Broadcasting) throughout Europe and much of the world

For a decade, MPEG-2 was effectively *the* definition of digital video. If you had a DVD player or a digital satellite box in the 1990s or 2000s, you owned an MPEG-2 decoder.

#algo(
  name: "MPEG-2 / H.262",
  year: "1994–1995 (finalized)",
  authors: "ISO/IEC MPEG + ITU-T VCEG",
  aim: "Broadcast and storage quality video at 2–30 Mbit/s; DVD, digital TV",
  complexity: "O(W·H) per frame for decoding; encoding is much heavier",
  strengths: "Universal hardware support; established I/P/B/GOP structure; handles interlaced video; proven at scale",
  weaknesses: "Efficiency roughly half of H.264; fixed macroblock sizes only; requires newer codecs for HD streaming",
  superseded: "H.264/AVC for most applications; still used in legacy broadcast infrastructure",
)[
  MPEG-2 established the vocabulary that every later codec speaks. The macroblock, the GOP, the DCT-quantize-entropy pipeline, the split between profile (tools) and level (parameters) — all of this was crystallized in MPEG-2 and inherited, sometimes unchanged, by H.264, HEVC, and AV1.
]

Let us look at a concrete worked example of how a P-frame works in the MPEG-2 / H.264 model.

=== Worked Example: Motion Compensation in Detail

Suppose we have two frames, each 16×16 macroblocks (for simplicity a tiny 64×64 pixel video). Frame 0 is our I-frame; frame 1 is a P-frame.

In frame 0, pixels at positions (8, 4) through (23, 19) form a macroblock MB₀ that shows the corner of a red car.

In frame 1, the car has moved 3 pixels right and 2 pixels down. The encoder *searches* the neighborhood of MB₀'s location in frame 1 for the best match in the *reference* (decoded frame 0). It finds that the block at offset (+3, +2) from MB₀'s original position closely matches frame 1's content. The *motion vector* is (3, 2).

The encoder now *predicts* frame 1's macroblock by copying the reference block from frame 0 at the displaced location. It then computes:

$ "residual" = "frame 1 pixels" - "predicted pixels" $

If the car moved cleanly without changing appearance, the residual is near zero everywhere. The DCT of a near-zero block has most energy in the DC coefficient (the mean), and the AC coefficients (the detail) are tiny — so aggressive quantization can set most of them to zero without visible loss. What gets transmitted is:

- The motion vector (3, 2) — maybe 4–6 bits with predictive coding
- The quantized DCT coefficients of the residual — maybe 20–50 bits instead of the 2,048 bits a raw 16×16 luma block would need

The compression factor for this one macroblock, versus sending it as a raw image block, might be 40:1.

#gomaths("Half-pel and Quarter-pel Interpolation")[
  A motion vector like (3.5, 2.25) refers to a position that does not correspond to any real pixel — it falls between four real pixels. To use sub-pixel motion, we *interpolate*:

  *Half-pel* (used since MPEG-1): the half-pel sample between two horizontally adjacent real pixels $A$ and $B$ is $(A + B)/2$, rounded. A 6-tap or 4-tap FIR filter is used for smoother results in H.264.

  *Quarter-pel* (added by H.264): quarter-pel positions are generated by interpolating between half-pel positions. So ($x + 0.25$) is interpolated between the integer position and the half-pel.

  Why bother? Because real-world motion is rarely in integer steps. An object moving at 3.7 pixels per frame will, over 10 frames, be misaligned by almost 4 pixels if we round to integers — producing large residuals. Quarter-pel accuracy dramatically reduces residuals for smooth motion (panning cameras, walking people, flowing water) at the cost of more computation for the encoder to search at finer granularity.
]

== H.263 and MPEG-4 Part 2: The Internet Bridge

By the mid-1990s, the internet was growing fast, and people wanted video not just on DVDs but over dial-up modems (28.8 kbit/s!) and early broadband. MPEG-2 was far too heavy. Two parallel efforts addressed this:

=== H.263 (1995–1998)

ITU-T's VCEG developed H.263 as a low-bitrate video codec for videoconferencing, improving on H.261 with:
- Half-pixel motion vectors (like MPEG-1)
- P-frames allowed B-frames (optional)
- Advanced prediction mode: overlapping block motion compensation (OBMC)
- Multiple *annexes* (optional extensions) added over time — H.263+ (1998) and H.263++ (2000) added scalability, improved entropy coding, and more

H.263 found a home in early video calls (it was used in NetMeeting and many early web-camera applications) and mobile video (3GPP mandated H.263 for 3G video calls).

=== MPEG-4 Part 2 and the DivX Revolution

MPEG-4 (ISO/IEC 14496), finalized in 1998, was an ambitious multi-part standard for interactive multimedia. Part 2 defined *MPEG-4 Visual*, a video codec built on H.263's foundation with additions like:
- Global motion compensation (for panning cameras)
- The Advanced Simple Profile (ASP) with B-frames and quarter-pixel motion

MPEG-4 Part 2 might have remained obscure if not for one of the most interesting moments in codec history. In 2000, a hacker group reverse-engineered and leaked an early Microsoft MPEG-4 encoder. Enthusiasts cleaned it up and released it as *DivX* — a free, high-quality video codec that ran on any Windows PC. For the first time, a two-hour movie could be compressed to fit on two CD-ROMs (700 MB each) at watchable quality. The effect on internet piracy was explosive and permanent.

The open-source response was *XviD* (DivX spelled backward), a fully open MPEG-4 Part 2 ASP implementation released in 2001. For half a decade, DivX and XviD files dominated peer-to-peer file sharing, and the era made two things abundantly clear:

1. There was enormous consumer demand for good-quality video at moderate bit rates.
2. The standard itself (MPEG-4 Part 2) was only a moderate improvement over MPEG-2 — maybe 20–30% better efficiency. Something more substantial was needed.

#history[
  The DivX story is a strange one. The leaked Microsoft encoder was based on a draft of MPEG-4 that Microsoft had been developing for Windows Media Player — their own proprietary spin. The leak stripped away the proprietary wrappers, leaving something close to the open standard. The hacker who originally released it used the name "DivX ;-)" (with a smiley), a reference to a then-failed pay-per-view DVD system called DIVX. The free DivX that emerged from this chaos eventually became its own legal company, DivX Networks Inc., which went on to legitimize its codec and support genuine MPEG-4 licenses. The open-source community, uncomfortable with DivX's increasingly commercial direction, created XviD.
]

#algo(
  name: "MPEG-4 Part 2 / H.263",
  year: "1998 (MPEG-4 Part 2), 1995 (H.263)",
  authors: "ISO/IEC MPEG; ITU-T VCEG",
  aim: "Low-to-moderate bitrate video for internet and mobile applications",
  complexity: "Moderate; lighter than MPEG-2 per quality unit",
  strengths: "Better than MPEG-2 at low bitrates; enabled internet video era; H.263 critical for 3G video",
  weaknesses: "Only modest improvement over MPEG-2 (~20–30%); rigid block structure; superseded quickly",
  superseded: "H.264/AVC for virtually all uses by 2010",
)[
  MPEG-4 Part 2 is historically important not because of its technical design but because of the DivX/XviD phenomenon it spawned — the first mass demonstration that compressed video could live on the internet without a disc.
]

== H.264 / AVC (2003): The Engineering Masterpiece

In December 2001, the ITU-T's Video Coding Experts Group and ISO/IEC's MPEG formally merged their video coding efforts into a *Joint Video Team* (JVT), chaired by Gary Sullivan (Microsoft), Thomas Wiegand (Fraunhofer HHI), and Ajay Luthra (Motorola). Their mandate: produce a codec that was *twice as efficient as MPEG-2* at equivalent quality.

The result, approved in March 2003 and completed in May 2003 as both *ITU-T Recommendation H.264* and *ISO/IEC 14496-10 MPEG-4 AVC* (Advanced Video Coding), exceeded that mandate. At the same perceptual quality, H.264 typically needs *half the bitrate* of MPEG-2, and sometimes better. Against MPEG-4 Part 2, the improvement is around 30–50%.

How? Not through any single breakthrough, but through a dozen carefully engineered improvements, each buying a few percent, together buying a revolution. Let us go through them.

=== Variable Block Sizes for Motion Compensation

MPEG-2 used a single block size: 16×16 macroblocks for the luma motion search. This is fine for large, smooth objects but wasteful at complex boundaries — a diagonal edge through a macroblock gives a bad motion match, producing a large residual everywhere.

H.264 introduced *flexible macroblock partitioning*. A 16×16 macroblock can be split into:
- One 16×16 partition
- Two 16×8 partitions (wide, half-height)
- Two 8×16 partitions (half-width, tall)
- Four 8×8 partitions (quarter)

And each 8×8 partition can be further split into:
- One 8×8
- Two 8×4
- Two 4×8
- Four 4×4

This gives the encoder up to 16 independent motion vectors per macroblock, each potentially pointing to a different reference frame location. For complex scenes — sports, crowds, foliage — this dramatically reduces residuals. For simple scenes, using a single 16×16 vector is cheap. The encoder chooses the partition that minimizes the Lagrangian cost J = D + λR (Chapter 41).

=== Multiple Reference Frames

MPEG-2 allowed each P-frame to reference only the immediately preceding decoded frame. H.264 allows up to 16 reference frames in its reference picture list. This enables:

- *Long-range motion compensation*: if an object disappears behind something and reappears later, the encoder can reach back to the frame where it was visible, not just the immediately preceding frame.
- *Error concealment*: the decoder can substitute a reference from further back if a P-frame is lost in transmission.
- *Better B-frame prediction*: B-frames can reference from a much richer pool of past and future frames.

The practical improvement is 5–15% in bitrate, largest on scenes with complex non-linear motion.

=== Quarter-Pixel Motion Accuracy

H.264 improved motion vector accuracy from MPEG-1/2's half-pixel to *quarter-pixel* (quarter-pel). The quarter-pel positions are computed using a 6-tap bilinear filter for the half-pel positions, then linear interpolation to quarter-pel. The result is much more precise tracking of smooth motion, reducing residual magnitudes substantially — typically another 5–10% in bitrate savings.

#fig(
  [Motion vector precision evolution. Each generation halved the rounding error in sub-pixel motion, directly reducing residual energy. H.261 was integer-only; MPEG-1/2 added half-pel; H.264 added quarter-pel. HEVC added 1/8-pel for luma.],
  cetz.canvas({
    import cetz.draw: *

    // Draw a pixel grid
    let cols = (0, 1, 2, 3)
    let rows = (0, 1, 2, 3)
    for x in cols {
      for y in rows {
        circle((x, y), radius: 0.07, fill: rgb("#0b5394"), stroke: none)
      }
    }

    // Half-pel positions (between integer pixels)
    let half_positions = (
      (0.5, 0), (1.5, 0), (2.5, 0),
      (0.5, 1), (1.5, 1), (2.5, 1),
      (0.5, 2), (1.5, 2), (2.5, 2),
      (0, 0.5), (1, 0.5), (2, 0.5), (3, 0.5),
      (0, 1.5), (1, 1.5), (2, 1.5), (3, 1.5),
      (0, 2.5), (1, 2.5), (2, 2.5), (3, 2.5),
    )
    for (x, y) in half_positions {
      circle((x, y), radius: 0.05, fill: rgb("#0b6e4f"), stroke: none)
    }

    // Quarter-pel positions (sample)
    let qpel = ((0.25, 0), (0.75, 0), (1.25, 0), (0.25, 1), (0.75, 1))
    for (x, y) in qpel {
      circle((x, y), radius: 0.035, fill: rgb("#9a2617"), stroke: none)
    }

    // Legend
    circle((0.5, 3.6), radius: 0.07, fill: rgb("#0b5394"), stroke: none)
    content((0.8, 3.6), anchor: "west")[#text(size: 7pt)[Integer pixel (H.261+)]]

    circle((0.5, 3.2), radius: 0.05, fill: rgb("#0b6e4f"), stroke: none)
    content((0.8, 3.2), anchor: "west")[#text(size: 7pt)[Half-pel (MPEG-1+)]]

    circle((0.5, 2.8), radius: 0.035, fill: rgb("#9a2617"), stroke: none)
    content((0.8, 2.8), anchor: "west")[#text(size: 7pt)[Quarter-pel (H.264+)]]
  })
)

=== The In-Loop Deblocking Filter

Every block-transform codec suffers from *blocking artifacts*: at high compression, the quantizer zeroes out many DCT coefficients, and the block boundaries become visible as a grid pattern superimposed on the image. You have certainly seen this in a low-quality streaming video — the picture looks like it was cut into squares.

MPEG-2 had no way to fix this. H.264 introduced an *in-loop deblocking filter* that runs as part of the decoding process, before the decoded frame is stored as a reference. The filter examines every 4×4 block boundary and, if it detects a blocking artifact (an abrupt discontinuity inconsistent with the local gradient), it smooths the boundary adaptively. The "in-loop" part is critical: because the filter runs on the reference frames, both encoder and decoder smooth the references the same way, so the encoder's motion search is based on the same signal the decoder will actually produce. The net effect is:

- Cleaner pictures (obviously), especially at lower bitrates
- 5–10% bitrate reduction because the smoothed reference gives better predictions, reducing residuals in subsequent frames

This single feature was arguably H.264's most visible quality improvement over MPEG-4 Part 2.

=== Intra Prediction

In MPEG-2, I-frame macroblocks were coded entirely independently — no prediction from neighbors. H.264 added *intra prediction*: before taking the DCT of an I-frame block, the encoder predicts the block's content from the already-coded pixels in neighboring blocks (above, left, upper-left diagonal, etc.).

The intuition is the same spatial-redundancy argument as for motion, but *within* a single frame. If the row of pixels directly above your block is a smooth blue gradient, the top row of your block is almost certainly the continuation of that gradient. So instead of coding the block's actual pixels, you extrapolate a prediction from the already-decoded border and code only the (tiny) residual. The reason there are several *directional* modes is that an edge can run through the block at any angle: a vertical fence-post wants the "copy the column above" prediction, a horizon line wants "copy the row to the left," and a diagonal roofline wants one of the slanted modes. The encoder tries each and keeps whichever leaves the smallest residual. H.264 defines 9 intra prediction *modes* for 4×4 luma blocks:

- DC (flat prediction: the mean of adjacent pixels)
- Horizontal (copy the left column)
- Vertical (copy the top row)
- Diagonal directions in four angles

For 16×16 macroblocks, 4 modes. The encoder picks the mode that minimizes J = D + λR. Result: I-frames compress about 2× better than in MPEG-2, because most of the spatial correlation is removed before the DCT even runs.

=== CAVLC: Context-Adaptive Variable-Length Coding

In MPEG-2 the entropy coder used fixed Huffman tables for the quantized DCT coefficients. H.264 introduced *Context-Adaptive Variable-Length Coding* (CAVLC) for the Main Profile's residual coefficients. CAVLC adapts the code table based on the statistics of recently coded neighbors — if the surrounding blocks had many non-zero coefficients, different code tables are selected than if they were mostly zero. The result is a 10–15% improvement in entropy-coding efficiency over a fixed table, at modest computational cost.

=== CABAC: Context-Adaptive Binary Arithmetic Coding

H.264's High Profile adds *Context-Adaptive Binary Arithmetic Coding* (CABAC), a full arithmetic coder (similar in principle to what we built in Chapter 26, but highly optimized). CABAC:

1. *Binarizes* all syntax elements (converts them to binary strings)
2. For each bit, selects a *context model* based on neighboring syntax elements (block type, position, previously coded values)
3. Runs a binary arithmetic coder with that model's probability estimate
4. Updates the model after each bit

The result is a further 10–15% bitrate improvement over CAVLC — arithmetic coding uses the full entropy, while Huffman-based CAVLC leaves a small gap. CABAC is computationally more expensive than CAVLC (roughly 2–3× the entropy-coding cost), which is why it is optional — low-power devices can use CAVLC.

#algo(
  name: "H.264 / AVC",
  year: "2003 (first version); extended through 2014",
  authors: "Joint Video Team (JVT) of ITU-T VCEG + ISO/IEC MPEG. Key contributors: Gary Sullivan, Thomas Wiegand, Iain Richardson, et al.",
  aim: "~2× MPEG-2 efficiency at equivalent quality; universal video for internet, broadcast, Blu-ray, mobile",
  complexity: "Decoder: O(W·H) per frame; encoder: O(W·H·S²·P) where S = search range, P = partitions considered",
  strengths: "Universally hardware-decoded; 84% production adoption in 2026; enormous ecosystem; flexible profiles/levels; CABAC near-entropy coding; quarter-pel precision; variable blocks; multi-reference",
  weaknesses: "Macroblock still fixed at 16×16 top level (HEVC breaks this); no overlapping transforms; patent-pool licensing cost rising in 2026",
  superseded: "HEVC for high-end streaming and disc; but dominates as universal baseline",
)[
  H.264 is not one algorithm but a *system* of interlocking improvements. Any single feature — quarter-pel, CABAC, multi-reference, deblocking — buys a small fraction of the total gain. Together they compound: each improvement reduces the signal another coder must clean up.
]

=== Putting It Together: The H.264 Encoding Pipeline

#fig(
  [The H.264 encoding pipeline for an inter-coded macroblock. The motion estimation and intra prediction boxes run the rate-distortion optimization. The transform and quantize boxes operate on the residual. CABAC handles all syntax elements.],
  cetz.canvas({
    import cetz.draw: *

    let box_w = 2.2
    let box_h = 0.7
    let gap = 0.4

    let boxes = (
      ("Input\nFrame", 0),
      ("Predict\n(Inter/Intra)", 1),
      ("Residual\nDCT", 2),
      ("Quantize\n(QP)", 3),
      ("Entropy\n(CABAC)", 4),
    )

    for (name, i) in boxes {
      let x = i * (box_w + gap)
      rect((x, 0), (x + box_w, box_h), fill: rgb("#e8f0f8"), stroke: 0.7pt + rgb("#0b5394"), radius: 3pt)
      content((x + box_w / 2, box_h / 2), anchor: "center")[#text(size: 7.5pt)[#name]]
      if i < boxes.len() - 1 {
        let arr_x = x + box_w
        line((arr_x, box_h / 2), (arr_x + gap, box_h / 2), mark: (end: ">", fill: rgb("#0b5394"), size: 0.18))
      }
    }

    // Reconstructed reference feedback arrow
    let fb_x_start = 3 * (box_w + gap) + box_w / 2
    let fb_x_end = 1 * (box_w + gap) + box_w / 2
    line((fb_x_start, 0), (fb_x_start, -0.5), stroke: 0.7pt + rgb("#9a2617"))
    line((fb_x_start, -0.5), (fb_x_end, -0.5), stroke: 0.7pt + rgb("#9a2617"))
    line((fb_x_end, -0.5), (fb_x_end, 0), mark: (end: ">", fill: rgb("#9a2617"), size: 0.15), stroke: 0.7pt + rgb("#9a2617"))
    content((fb_x_start / 2 + fb_x_end / 2, -0.78))[#text(size: 7pt, fill: rgb("#9a2617"))[Reconstructed reference (with in-loop deblocking)]]

    // Bitstream arrow out
    let last_x = 4 * (box_w + gap) + box_w
    line((last_x, box_h / 2), (last_x + gap, box_h / 2), mark: (end: ">", fill: rgb("#0b5394"), size: 0.18))
    content((last_x + gap + 0.1, box_h / 2), anchor: "west")[#text(size: 7.5pt)[Bitstream]]
  })
)

=== H.264 Profiles and Levels

A *profile* specifies which tools are allowed. A *level* specifies maximum resolution, frame rate, and bitrate. Together they let manufacturers build decoders for exactly the capabilities they need.

The four main H.264 profiles are:

*Baseline Profile (BP)*: No B-frames, CAVLC entropy coding only. Designed for videoconferencing and mobile video where simplicity and error robustness matter. Targets low-power decoders.

*Main Profile (MP)*: Adds B-frames and field-coding for interlaced video. Original target for standard and high-definition broadcast. In practice somewhat eclipsed by High Profile.

*Extended Profile (XP)*: A hybrid for streaming — adds switching slices (for adaptive bitrate streams to switch quality mid-stream) and data-partitioning for partial error concealment. Rarely used in practice; the streaming ecosystem ended up using Baseline or High instead.

*High Profile (HiP)*: The workhorse of Blu-ray, streaming, and broadcast HD. Adds the 8×8 integer DCT transform, adaptive 4:4:4/4:2:2/4:2:0 chroma support, and most importantly, *CABAC*. Roughly 15% better than Main Profile at the same quality.

Additional profiles (High 10, High 4:2:2, High 4:4:4, MVC for 3D, SVC for scalable) were added in later amendments, but High Profile is the one 99% of streaming and disc content uses.

Levels run from 1 (176×144 at 15 fps, 64 kbit/s) to 6.2 (8192×4320 at 300 fps, 800 Mbit/s). Level 4.1 — 1080p at 30 fps, 50 Mbit/s — is the threshold that virtually every Blu-ray player, game console, and smartphone from 2010 onward must support.

#checkpoint[
  Why is it significant that the H.264 standard specifies only the decoder, not the encoder?
][
  The standard guarantees that any compliant bitstream can be decoded correctly by any compliant decoder — interoperability. But it says nothing about *how* the encoder searches for good motion vectors, chooses block partitions, or decides when to use CABAC vs CAVLC. Encoders are free to be as clever (or as fast, or as lazy) as they like. The result is that high-quality encoders like x264 (with weeks of engineering and clever rate-distortion optimization) produce dramatically better-compressed bitstreams than a naïve reference encoder — both are "H.264," but one is 30%+ more efficient. This asymmetry also means codec quality improves for free over time without changing the standard: new encoding algorithms can produce better results that older decoders still correctly play back.
]

=== Why H.264 Won (and Keeps Winning)

H.264 was officially approved in March 2003. Within five years it was mandatory in the Blu-ray Disc specification, adopted by Apple's iPod and QuickTime, required by YouTube for HD uploads, and embedded in virtually every digital camera and smartphone sold. Why such rapid adoption compared to, say, the lingering struggles of HEVC or the long hardware wait for AV1?

Several factors converged:

*A clear licensing pool*. Via Licensing's AVC/H.264 patent pool launched in 2004 and provided a single place to license the essential patents for a manageable fee (initially capped at \$100,000 per year for large licensees). This was far simpler than the multi-pool chaos that would later plague HEVC.

*Hardware ubiquity*. Because the license was clear and the spec was stable, silicon manufacturers built H.264 decode acceleration into everything — every ARM Cortex-A8 (the chip in the original iPhone 3G), every Intel Sandy Bridge GPU, every NVIDIA chip. Software decode was fine for desktops but power-hungry on phones; hardware decode enabled the smartphone video era.

*A well-timed solution*. In 2003–2005, streaming video was just beginning to matter. YouTube launched in 2005. When high-speed internet and smartphone screens collided in the late 2000s, H.264 was the only codec that was simultaneously (a) better than anything previous, (b) licensed without landmines, (c) hardware-accelerated in mass-market silicon. No alternative existed.

*The software encoder*. x264, the open-source H.264 encoder, was released in 2003 and steadily improved to become perhaps the most carefully optimized encoder ever written. Its existence meant even small websites and hobbyists could produce H.264 video cheaply.

#misconception[
  H.264 is obsolete — modern platforms use HEVC or AV1.
][
  H.264 is never sent to you when something better is available — true. But "available" requires hardware decoding (for battery life), license clarity (for legal safety), and server-side encoding capability. In 2026, 84% of all video streaming production still uses H.264, because it remains the only codec guaranteed to work on every device from a 2009 Android phone to a 2026 gaming PC. For live streaming, where encoding must happen in real time at low latency, H.264 encodes 3–30× faster than H.265 or AV1 at equivalent quality. The architecture of the internet is long — legacy devices are slow to retire.
]

== The Patent Story: How Licensing Shaped Adoption

H.264's licensing history is, counterintuitively, one of its greatest features — and a cautionary tale about how bad it could have been.

=== The Patent Pool Model

Video codecs rely on dozens of patents covering specific technical innovations: the way a particular interpolation filter is specified, the way context models are initialized, the way motion vectors are coded. These patents are scattered across universities, companies, and countries. Without a licensing mechanism, any company implementing H.264 would need to separately negotiate with every patent holder — hundreds of individual licenses.

The solution was a *patent pool*: a single administrator (Via Licensing for H.264, later renamed Via LA) collects licenses from all willing essential patent holders and offers a single license to implementers. One fee, one agreement, one pool of rights.

Via Licensing's H.264 pool charged:
- Free for royalty-free internet video (for many years)
- Capped at \$100,000/year for large commercial deployments

This was genuinely manageable. Compared to the chaos of MP3 licensing or the later HEVC multi-pool disaster, the H.264 pool made licensing nearly painless.

=== The 2026 Fee Shock

In early 2026, Via LA quietly restructured the H.264 streaming license for new licensees — companies that had not already signed an agreement by the end of 2025. The new tiered structure:

- Tier 1 OTT (100M+ subscribers): *\$4,500,000/year* — a 4,400% increase from the old \$100,000 cap
- Tier 2 (20–99M subscribers): \$3,375,000/year
- Tier 3 (under 20M): \$2,250,000/year
- Small/nascent services: retain the \$100,000 cap

Companies with licenses signed before 2026 are grandfathered under the old terms. But any new streaming service, or any existing service that let its license lapse, faces the new rates. The announcement came without a press release — Via LA contacted affected companies directly — and was not widely reported until trade press picked it up in March 2026. The change accelerated interest in royalty-free alternatives.

#aside[
  The Via LA fee escalation follows a pattern seen repeatedly in codec history. A patent pool is initially priced attractively to maximize adoption (and thus royalty volume). Once the codec is so deeply embedded that switching is costly, fees rise. The GIF/LZW situation in 1994 (Chapter 29), the HEVC pool fragmentation in 2013–2015 (Chapter 53), and now the H.264 escalation all follow this template. The lesson the industry keeps relearning: adoption of a proprietary codec is not just a technical decision but a long-term economic bet.
]

== The Codec Standard vs. the Encoder: A Critical Distinction

It is worth pausing to make explicit something that confuses many newcomers.

*The H.264 standard* is a document specifying the bitstream syntax and the decoder behavior. It says: "given these bits, produce these pixels." It says nothing about how to produce the bits in the first place.

*An H.264 encoder* is a program that takes raw video and produces a valid H.264 bitstream. It must produce bits that the standard decoder can decode. But the standard gives the encoder complete freedom in *how* it searches for the best encoding.

The practical consequence is enormous. Two fully compliant H.264 encoders can produce bitstreams that, at the same file size, have *wildly different quality*:

- The ITU-T *reference encoder* (JM), designed to demonstrate correctness, not speed, achieves excellent quality but runs roughly 100–1000× slower than real-time.
- *x264* at its highest quality settings (veryslow preset) approaches JM quality at much higher speed.
- *x264 at veryfast* is 20–50× faster than veryslow, but 15–30% worse in quality at the same bitrate.
- A badly written H.264 encoder might produce a compliant bitstream with 2× the needed bits.

This is why "the codec" is not a single thing — the hardware in your phone doing "H.264 decode" is a fixed box, but the "H.264 encode" on a streaming server can range from mediocre to brilliant.

#gopython("Measuring codec quality: PSNR")[
  PSNR (Peak Signal-to-Noise Ratio) is the most common quick metric for image and video quality. It measures the ratio of the maximum possible pixel value to the mean-squared error between original and decoded frames. Chapter 75 covers quality metrics deeply; here is the formula and a tiny implementation so you can compare encoders:

  #pyrecall[`zip(a, b)` walks two sequences in lockstep, handing you matched pairs `(x, y)` one at a time — exactly as we used it for vector arithmetic in Chapters 11 and 12. Below, `zip(original, decoded)` pairs each original byte with its decoded counterpart so we can square their difference.]

  ```python
  import math

  def psnr(original: bytes, decoded: bytes, max_val: int = 255) -> float:
      """Compute PSNR between two grayscale images (same length byte buffers)."""
      if len(original) != len(decoded):
          raise ValueError("buffers must be same length")
      mse = sum((a - b) ** 2 for a, b in zip(original, decoded)) / len(original)
      if mse == 0:
          return float("inf")   # identical
      return 10 * math.log10(max_val ** 2 / mse)

  # Quick demo
  orig = bytes(range(256)) * 4    # 1024-byte "image"
  noisy = bytes((b + 5) % 256 for b in orig)
  print(f"PSNR with small noise: {psnr(orig, noisy):.1f} dB")
  # Typically ~34 dB — a small constant offset.
  # >40 dB is generally "transparent"; <30 dB is visibly degraded.
  ```

  Higher is better. Each +6 dB corresponds roughly to halving the noise amplitude, so +6 dB ≈ the same improvement as doubling the bitrate (roughly). This is only a rough guide — PSNR correlates poorly with human perception for strong artifacts. (Chapter 75 covers SSIM and VMAF, which do better.)
]

== The Workhorse in Numbers

Let us collect the key numbers that justify calling H.264 "the workhorse era":

#scoreboard(
  caption: "Video quality per bitrate — approximate comparison (1080p, 30fps, medium motion)",
  [MPEG-2 Main Profile @ 8 Mbit/s], [~4,500 kB/s], [baseline], [DVD quality; very visible at low rates],
  [MPEG-4 Part 2 ASP (DivX/XviD) @ 8 Mbit/s], [~4,500 kB/s], [1.0× MPEG-2], [Moderate improvement; ~20–30% better],
  [H.264 Baseline Profile @ 4 Mbit/s], [~2,250 kB/s], [~2.0× MPEG-2], [DVD quality at half the bitrate],
  [H.264 High Profile, x264 @ 4 Mbit/s], [~2,250 kB/s], [~2.5× MPEG-2], [Better-than-DVD quality; Blu-ray uses ~25–40 Mbit/s H.264],
  [H.265 HEVC @ 2 Mbit/s], [~1,125 kB/s], [~4× MPEG-2], [4K streaming quality; Chapter 53],
  [AV1 @ 1.5 Mbit/s], [~844 kB/s], [~5× MPEG-2], [4K quality; Chapter 54],
)

The "Bytes" column above shows approximate bytes per second for each scenario. The ratio column normalizes by MPEG-2 bitrate needed for equivalent quality. The numbers illustrate why H.264 was such a watershed: halving the bitrate versus MPEG-2 was not a marginal improvement but a practical revolution — it made HD streaming viable on the 2–5 Mbit/s home connections common in the late 2000s.

By 2026, H.264 bitrates for streaming have converged to practical norms:
- 720p 30fps: 2.5 Mbit/s (Netflix recommended)
- 1080p 30fps: 5 Mbit/s (Netflix recommended)
- 1080p 60fps: 8 Mbit/s

These are conservative targets; x264 at "slow" or "veryslow" preset can deliver excellent perceptual quality at 30–50% lower bitrates.

== A Brief Look Forward

H.264's successors — H.265/HEVC (Chapter 53) and the open-source AV1 (Chapter 54) — achieve 30–50% additional efficiency by breaking the fundamental constraint H.264 never overcame: the fixed 16×16 macroblock as the top-level coding unit. HEVC introduced *Coding Tree Units* up to 64×64 with recursive quadtree splitting. AV1 pushed further with superblocks up to 128×128 and partition shapes that are not limited to rectangles.

But every one of those innovations rests on the same conceptual core that H.261 established in 1988 and H.264 perfected in 2003: predict, subtract, transform, quantize, entropy-code. The blocks have changed; the loop has not.

#keyidea[
  The entire 35-year lineage from H.261 to H.264 is the *same algorithm* being engineered more carefully. Variable block sizes, quarter-pixel motion, CABAC, intra prediction, in-loop deblocking — each is a more precise answer to the question "what is the cheapest prediction?" The insight that defines video coding has not changed since 1988. The craft with which it is implemented has changed enormously.
]

#takeaways((
  [H.261 (1988) established the macroblock + motion-compensation + DCT pipeline that every subsequent standard inherits.],
  [MPEG-1 (1992) added B-frames and half-pixel motion; MPEG-2/H.262 (1994–95) scaled to DVD and broadcast quality (2–30 Mbit/s).],
  [H.263 and MPEG-4 Part 2 bridged to the internet era; DivX and XviD demonstrated mass consumer demand for compressed internet video.],
  [H.264/AVC (2003) doubled MPEG-2 efficiency through six key innovations: variable block sizes, multiple references, quarter-pixel motion, in-loop deblocking, CABAC, and 9-mode intra prediction.],
  [H.264 profiles (Baseline, Main, Extended, High) let decoders of different capability play valid bitstreams; levels cap resolution and bitrate.],
  [The standard specifies only the decoder; encoder quality varies hugely — two compliant encoders can differ 30%+ in quality at the same bitrate.],
  [H.264 licensing via Via Licensing's pool was initially manageable; a 2026 fee restructuring raised streaming costs up to \$4.5M/year for new licensees, accelerating interest in royalty-free alternatives.],
  [H.264 maintains 84% production adoption in 2026 as the universal baseline codec.],
))

== Exercises

#exercise("52.1", 1)[
  A video frame is 1280×720 pixels, each pixel stored as 3 bytes (RGB). How many bytes is one raw frame? At 30 frames per second, how many bytes is one second of raw video? At 2 Mbit/s H.264 streaming, what is the approximate compression ratio?
]
#solution("52.1")[
  Raw bytes per frame: 1280 × 720 × 3 = 2,764,800 bytes ≈ 2.76 MB. Per second at 30 fps: 82.9 MB. At 2 Mbit/s = 0.25 MB/s, the compression ratio is 82.9 / 0.25 ≈ 332:1.
]

#exercise("52.2", 1)[
  A P-frame macroblock has motion vector (−3, 5). What does this mean geometrically? If the search for this vector took 30 ms of CPU time for one macroblock, and a 1280×720 frame has 3,600 macroblocks, estimate the time needed to encode one frame with an exhaustive motion search.
]
#solution("52.2")[
  MV (−3, 5) means the prediction is taken from 3 pixels to the left and 5 pixels downward in the reference frame — the block "moved" 3 left and 5 down between frames. Time estimate: 30 ms × 3,600 = 108,000 ms = 108 seconds per frame. At 30 fps, that is 3,240 seconds (over 54 minutes) to encode one second of video — clearly impractical. Real encoders use fast search algorithms (three-step search, diamond search, hierarchical motion estimation) to reduce this to milliseconds.
]

#exercise("52.3", 2)[
  Explain the difference between CAVLC and CABAC in H.264. Why is CABAC restricted to High Profile while CAVLC is available in all profiles? What is the typical bitrate difference between the two for the same video?
]
#solution("52.3")[
  CAVLC is a context-adaptive Huffman scheme — it changes the code table based on neighbor statistics but uses fixed-length codewords (power-of-two probabilities). CABAC is a binary arithmetic coder that maintains continuously updated probability estimates per context, approaching the true entropy. CABAC offers 10–15% better compression. It is High-Profile-only because it is computationally more expensive (roughly 2–3× the entropy-coding cost) and more complex to implement, making it unsuitable for baseline low-power and mobile devices. CAVLC is simpler and fast enough for real-time decode on constrained hardware.
]

#exercise("52.4", 2)[
  In an H.264 stream, the in-loop deblocking filter runs *before* the frame is stored as a reference. Why is this "in-loop" placement important? What would happen if the filter ran only at display time (after the frame was stored as a reference)?
]
#solution("52.4")[
  If the filter ran only at display time, the reference frames stored in the DPB (Decoded Picture Buffer) would contain unfiltered blocking artifacts. The encoder's motion search works against these unfiltered references. When the decoder reconstructs using the same unfiltered references, everything matches — but the quality is limited by the artifact-laden references. By filtering the reference before storage, both encoder and decoder use the same smooth signal as the basis for prediction. This means the encoder's motion predictions are more accurate (smoother signal = lower residual = fewer bits), and the decoder reconstructs from smoother references, compounding quality improvements across frames.
]

#exercise("52.5", 2)[
  A Blu-ray disc encoding uses H.264 High Profile at 30 Mbit/s for a 120-minute film. Estimate the total encoded video data in gigabytes. A dual-layer BD-50 disc holds 50 GB. Roughly how many minutes of content can fit if video uses the entire disc? (Real Blu-rays also hold audio, subtitles, and menus, reducing available space.)
]
#solution("52.5")[
  120 minutes × 60 s/min × 30 Mbit/s ÷ 8 = 27,000 MB ≈ 27 GB. For a 50 GB disc: 50 GB × 8 bits/byte ÷ 30 Mbit/s = 13,333 seconds ≈ 222 minutes ≈ 3.7 hours. In practice, most 2-hour films fit comfortably on a BD-50 even with audio and extras at 20–30 Mbit/s video, leaving room for lossless audio (TrueHD, DTS-HD MA) which adds 2–5 Mbit/s.
]

#exercise("52.6", 3)[
  Write a Python function `split_macroblock(mb: list[list[int]]) -> list[tuple[str, list[list[int]]]]` that takes a 16×16 list-of-lists (representing luma pixel values) and returns a list of possible H.264-style partitions: the whole block as `"16x16"`, two halves as `"16x8"` (top, bottom), two halves as `"8x16"` (left, right), and four quarters as `"8x8"`. Each partition should include its pixel sub-grid. Then compute the mean-squared error (MSE) of each partition relative to its own mean (as a proxy for residual energy if the motion vector were perfect). Which partition minimizes total residual energy for a block where the top half is all 100s and the bottom half is all 200s?
]
#solution("52.6")[
  ```python
  def split_macroblock(mb: list[list[int]]) -> list[tuple[str, list[list[int]]]]:
      top  = [mb[r] for r in range(8)]
      bot  = [mb[r] for r in range(8, 16)]
      left  = [row[:8] for row in mb]
      right = [row[8:] for row in mb]
      tl = [row[:8] for row in mb[:8]]
      tr = [row[8:] for row in mb[:8]]
      bl = [row[:8] for row in mb[8:]]
      br = [row[8:] for row in mb[8:]]
      return [
          ("16x16", mb),
          ("16x8-top", top), ("16x8-bot", bot),
          ("8x16-left", left), ("8x16-right", right),
          ("8x8-tl", tl), ("8x8-tr", tr), ("8x8-bl", bl), ("8x8-br", br),
      ]

  def mse_from_mean(block: list[list[int]]) -> float:
      flat = [v for row in block for v in row]
      mean = sum(flat) / len(flat)
      return sum((v - mean) ** 2 for v in flat) / len(flat)

  # Build test block: top 8 rows = 100, bottom 8 rows = 200
  mb = [[100] * 16] * 8 + [[200] * 16] * 8
  for name, part in split_macroblock(mb):
      print(f"{name}: MSE={mse_from_mean(part):.1f}")
  ```
  The 16×16 split gives MSE = 2500 (mean is 150; each pixel is ±50 from mean). The "16x8-top" and "16x8-bot" partitions each give MSE = 0 (all pixels in each half are identical). So splitting into 16×8 halves eliminates all residual energy — perfect motion vectors for each half would give zero residual. This illustrates exactly why H.264's variable block sizes matter: a region with two distinct motions benefits enormously from smaller partitions.
]

== Further Reading

- #link("https://www.fastvdo.com/spie04/spie04-h264OverviewPaper.pdf")[Sullivan, G., Wiegand, T., & Lim, K.-P. (2004). H.264/AVC Overview. SPIE Conference on Visual Communications and Image Processing.] — The authoritative introduction to H.264's design by its architects.
- #link("https://avc.hhi.fraunhofer.de/")[Fraunhofer HHI AVC/H.264 Resource Page] — Papers and technical notes from one of the key development labs.
- #link("https://www.vcodex.com/h264avc-context-adaptive-variable-length-coding")[Vcodex: H.264 CAVLC Deep Dive] — Iain Richardson's excellent technical breakdowns of H.264 entropy coding.
- #link("https://www.itu.int/ITU-T/worksem/vica/docs/presentations/S3_P1_Sullivan.pdf")[Sullivan, G. (ITU-T presentation). H.264/AVC Technical Overview.] — Covers profiles, levels, and design rationale in compact form.
- Richardson, I. E. G. (2010). *The H.264 Advanced Video Compression Standard* (2nd ed.). Wiley. — The most complete book-length treatment.
- #link("https://www.techspot.com/news/111971-h264-streaming-license-fees-could-jump-100k-45m-streaming.html")[TechSpot (2026). H.264 streaming fees jump from \$100,000 to \$4.5 million a year.] — Reporting on Via LA's 2026 fee restructuring.

#bridge[
  H.264/AVC set a high bar. But by the mid-2000s, the video industry could see the wall: 4K television was coming, mobile broadband was growing, and H.264's fundamental macroblock structure — a 16×16 grid that cannot adapt to large uniform regions or tiny fine-grained textures — was a genuine limitation. In Chapter 53 we meet H.265/HEVC, which breaks that limitation with *Coding Tree Units* up to 64×64 and recursive quadtree partitioning — and pays for it with a patent licensing disaster that handed the royalty-free movement its greatest opportunity.
]
