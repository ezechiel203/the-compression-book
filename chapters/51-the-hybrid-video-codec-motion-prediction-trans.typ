#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Hybrid Video Codec: Motion, Prediction, Transform

#epigraph[
  "If an image is worth a thousand words, a video is worth a thousand images — and a
  thousand times the engineering headache."
][Anonymous compression engineer]

Here is a number that should stop you cold: in 2024, video traffic accounted for
roughly 65 percent of all bytes flowing across the global internet. Not text. Not
downloads. Not web pages. _Video._ Streaming movies, video calls, uploaded phone clips,
live sport, surveillance feeds, medical imaging, video games streaming from the cloud —
all of it represented by nothing but zeroes and ones being fired down cables and through
the air at mind-bending speed, compressed to a fraction of their original size.

Now consider what "uncompressed video" actually means. A single second of 1920×1080
color video at 30 frames per second, with three bytes of color per pixel, needs:
$1920 times 1080 times 3 times 30 = 186,624,000$ bytes — about 178 megabytes _per second._
A two-hour movie at that resolution would consume more than 1.2 terabytes of raw data.
The average internet connection would take days to download it. Instead, a Blu-ray
disc holds the entire film in about 25–50 gigabytes. Netflix streams it to your
television in real time at a few megabytes per second.

How? The answer is the _hybrid video codec_ — a design pattern so successful that every
major video standard from 1988 to today uses a version of the same three-part idea:
predict using previously seen frames, transform the prediction error, and entropy-code
the coefficients. This chapter tears that idea open, shows you exactly how each piece
works, and at the end you will build a working inter-frame prediction demo in Python.

#recap[
  Chapter 37 introduced the frequency domain and the Discrete Fourier Transform. Chapter
  38 built the Discrete Cosine Transform (DCT) and showed why it concentrates energy
  into a few coefficients — we implemented `dct2d`/`idct2d` in `tinyzip/transform.py`
  (Step 17). Chapter 39 covered quantization: dividing DCT coefficients by a step size
  and rounding, trading quality for bits — we built `quant.py` (Step 18). Chapter 42
  assembled those tools into a JPEG pipeline and built `jpeg.py` (Step 19). Chapters
  48–50 applied the same transform-quantize-entropy template to audio. This chapter
  adds the ingredient that turns a sequence of JPEG-like images into a _video_ codec:
  _temporal prediction_ — exploiting the fact that frame $t+1$ almost always looks a
  lot like frame $t$.
]

#objectives((
  "Explain why video carries so much more redundancy than a single image, and name the
  two kinds of redundancy a video codec removes.",
  "Define a macroblock, a motion vector, and a prediction residual, and describe how
  they fit together in block motion compensation.",
  "Distinguish I-frames, P-frames, and B-frames; explain why B-frames compress best
  and why they require re-ordering.",
  "Describe the Group of Pictures (GOP) and the trade-off between GOP length,
  compression, and random access.",
  "Trace a video frame through the full encoder pipeline: predict → subtract → transform
  → quantize → entropy-code → reconstruct.",
  "Explain what intra prediction is and why it is also used inside P-frames and B-frames.",
  "Define rate-distortion optimization (RDO) and explain why the encoder is far more
  complex than the decoder.",
  "Describe the purpose of the in-loop deblocking filter and the SAO filter.",
  "Implement a block motion-compensation demo in Python (tinyzip Step 20) that encodes
  two frames using inter prediction and round-trips them.",
))

== Why Video Is Mostly Redundancy

Open a video editor and look at two consecutive frames from a walking scene. Frame 247
and frame 248 differ mostly in that every pixel of a person has shifted two pixels to
the right. The background behind them is identical. The sky is identical. If you subtract
frame 248 from frame 247 and look at the difference image, you mostly see near-zero grey
everywhere, with a thin bright edge where the person's boundary now cuts through a
previously-background pixel.

This is _temporal redundancy_: neighboring frames in time are nearly the same image.
It is far larger than the spatial redundancy JPEG already removes. In typical talking-head
video at 30 fps, consecutive frames often agree on 90 % of their pixels to within a few
shades of grey. Naively entropy-coding the difference between consecutive frames would
already compress dramatically — but only for the static parts. Where the camera pans,
where objects move, the difference is large. The trick video codecs add on top of simple
differencing is _motion compensation_: before you subtract, shift the previous frame to
_match_ the current one as closely as possible.

#keyidea[
  A video codec removes two kinds of redundancy simultaneously.
  - *Spatial redundancy:* within a single frame, neighboring pixels are correlated.
    The DCT + quantize + entropy-code pipeline (which we know from JPEG, Chapter 42)
    removes this.
  - *Temporal redundancy:* consecutive frames are highly correlated. Block-based motion
    compensation removes this.
  The _hybrid_ codec is hybrid because it uses _both_ mechanisms together.
]

== Block Motion Compensation: The Central Idea

Block motion compensation (BMC) is the dominant idea in video coding. Here is how it
works in plain terms, before the math.

=== The basic setup

We call the frame we are currently encoding the _current frame_, and the frame (or
frames) we already have reconstructed (on both the encoder and decoder sides) the
_reference frame(s)_.

The current frame is divided into rectangular blocks — historically 16×16 pixels, called
_macroblocks_. For each block, the encoder searches the reference frame for the
block-shaped region that looks most like the current block. It records the displacement
between where the best-match block sits in the reference frame and where the current block
sits in the current frame. That displacement is the _motion vector_ — a pair of numbers
$(Delta x, Delta y)$.

The decoder, receiving the motion vector, copies the identified block from its own copy
of the reference frame to the appropriate position in the current frame. That copy is the
_prediction_. The encoder subtracts the prediction from the actual current block to get the
_prediction residual_ — the error that the motion vector could not explain. It transforms
(DCT), quantizes, and entropy-codes the residual, exactly as JPEG does with image blocks.

#definition("Motion vector")[
  A pair of integer (or sub-pixel) offsets $(Delta x, Delta y)$ that identifies, in a
  reference frame, the best-matching block for a given block in the current frame.
  Motion vectors are transmitted as part of the compressed bitstream; the decoder uses
  them to reconstruct the prediction from its own stored reference frame.
]

#definition("Prediction residual")[
  The pixel-by-pixel difference between a block in the current frame and the prediction
  for that block (either from a motion-compensated reference block or from an intra
  prediction). The residual is what is transformed, quantized, and entropy-coded. If
  motion compensation is perfect, every residual pixel is zero and no coefficient bits
  are spent.
]

=== A tiny worked example

Suppose a 4×4 block in the current frame contains these luma values (each 0–255):

#align(center)[
  #table(columns: 4, align: center, inset: 6pt,
    [120], [122], [119], [121],
    [118], [120], [121], [119],
    [121], [119], [122], [120],
    [120], [121], [119], [122],
  )
]

The encoder searches the reference frame and finds the best match at displacement
$(Delta x, Delta y) = (+3, -1)$ — three pixels to the right, one pixel up. That
reference block contains:

#align(center)[
  #table(columns: 4, align: center, inset: 6pt,
    [119], [121], [118], [120],
    [120], [119], [121], [122],
    [119], [122], [120], [121],
    [121], [120], [122], [119],
  )
]

The residual (current minus prediction) is:

#align(center)[
  #table(columns: 4, align: center, inset: 6pt,
    [+1], [+1], [+1], [+1],
    [-2], [+1], [0],  [-3],
    [+2], [-3], [+2], [-1],
    [-1], [+1], [-3], [+3],
  )
]

These residuals are small — most within $plus.minus 3$. When we run the DCT on them,
the energy concentrates into a few low-frequency coefficients, most of which quantize
to zero. The encoder transmits the motion vector $(+3, -1)$ — just two small numbers —
and the handful of non-zero quantized DCT coefficients. The decoder reconstructs by
copying the reference block and adding back the residual. If motion compensation is good
enough, the residuals all become zero after quantization and we transmit literally nothing
except the motion vector.

#checkpoint[
  If a 16×16 macroblock's prediction is perfect (every residual pixel is exactly zero),
  what is transmitted for that block?
][
  Only the motion vector — two small numbers indicating where in the reference frame the
  block came from. No DCT coefficients at all. The decoder copies the reference block
  unchanged. This is why motion compensation can compress video so aggressively: most
  blocks in a smooth scene transmit just a vector.
]

=== Why search can never lose to plain differencing

Naive frame differencing — subtracting the reference block sitting at the _same_
position as the current block — is just motion compensation with the single fixed vector
$(0, 0)$. A small but reassuring fact follows.

#theorem("Motion search never increases residual error")[
  Let $E(Delta x, Delta y)$ be the prediction error (say, the sum of absolute
  differences, SAD) between a current block and the reference block displaced by
  $(Delta x, Delta y)$. If the encoder searches a set $S$ of candidate vectors that
  _includes_ the zero vector $(0,0)$ and keeps the vector with the smallest error, then
  the chosen error is always less than or equal to the error of naive frame differencing.
]

#proof[
  The encoder selects $(Delta x^*, Delta y^*) = arg min_((Delta x, Delta y) in S) E(Delta x, Delta y)$,
  the candidate with the least error. Because the minimum over a set is never larger than
  any single member of that set, and $(0,0) in S$, we have
  $E(Delta x^*, Delta y^*) <= E(0, 0)$. But $E(0,0)$ is exactly the error of naive
  differencing. Hence motion search can only match or beat plain differencing — never do
  worse. (The full-search loop in our Step 20 code below includes $(0,0)$ in its
  $plus.minus 16$ window, so it inherits this guarantee.)
]

This is why a static background costs almost nothing even when the encoder bothers to
search: for those blocks the winning vector simply _is_ $(0,0)$, and the residual is the
same near-zero difference plain subtraction would have given — but the moving foreground
blocks, where search actually pays off, get a much better prediction than differencing
could ever offer.

=== Sub-pixel motion

Real objects don't move in whole-pixel steps. A camera pan might shift the scene by 1.7
pixels per frame. Modern codecs interpolate the reference frame to half-pixel or
quarter-pixel accuracy. The encoder searches at sub-pixel positions; the decoder uses
the same interpolation filter to reconstruct the prediction. H.264/AVC introduced
quarter-pixel luma motion estimation in 2003 and showed it dramatically reduces residuals
for smooth motion. The cost: more computation for both encoding and decoding, and motion
vectors that must now represent fractional pixel offsets (usually stored as integers
scaled by four, so that the value 4 means "one whole pixel").

What does "interpolate to half-pixel accuracy" actually mean? There is no real pixel
sitting halfway between two stored samples, so the codec _invents_ one by averaging. The
simplest half-pixel sample between two neighbours of value 100 and 140 is their mean,
$(100 + 140)\/2 = 120$; real codecs use a longer weighted filter (H.264's luma
half-pixel filter taps six neighbours as $(1, -5, 20, 20, -5, 1)\/32$) for a sharper
result, but the idea is the same — synthesize an in-between grid so the search can land
the block on a fractional position. Crucially, encoder and decoder must use the _exact
same_ interpolation formula, or their predictions would diverge and the picture would
drift apart over a GOP.

== I-frames, P-frames, and B-frames

Not every frame can be predicted from a previous one. The first frame of a video has no
history. After a scene cut, the previous frame is useless. And error recovery demands that
the decoder can resync periodically without needing to see every earlier frame. Video
standards define three frame types.

#definition("I-frame (intra-coded frame)")[
  A frame that is coded without reference to any other frame — purely using spatial
  prediction within the frame itself (intra prediction, covered below). I-frames are
  large (they cost the most bits) but self-contained. They are the random-access points.
  Also called _key frames_ in some contexts.
]

#definition("P-frame (predictive frame)")[
  A frame predicted from one earlier I-frame or P-frame using motion compensation.
  The encoder transmits motion vectors and residuals. P-frames are much smaller than
  I-frames — typically 3–10× fewer bits at the same quality.
]

#definition("B-frame (bi-directionally predicted frame)")[
  A frame predicted from _both_ a past _and_ a future reference frame. Each macroblock
  can be predicted from the past frame, the future frame, or both (interpolated).
  B-frames are usually the most compressed — 30–50% smaller than P-frames — because
  the average of "where it came from" and "where it's going" is a surprisingly accurate
  predictor of where something is right now, especially for objects moving at nearly
  constant velocity.
]

#misconception[
  "B-frames must be encoded and decoded in display order."
][
  B-frames reference a _future_ frame, so the decoder must already have that future frame
  in memory before it can reconstruct a B-frame. This means B-frames are transmitted in a
  different order from how they are displayed. The encoder encodes the future reference
  frame first, sends it down the wire, and only then sends the B-frames that depend on
  it. Display order and coding order are different things. This _temporal reordering_ is
  handled transparently; the player buffers frames and reorders them before display.
]

=== The Group of Pictures (GOP)

A _Group of Pictures_ (GOP) is the repeating pattern of I, P, and B frames. A typical
pattern might be:

#align(center)[
  `I B B P B B P B B P B B I B B P …`
]

The first frame of each GOP is an I-frame. P-frames (every third frame here) act as
_reference anchors_ for the B-frames between them. The B-frames reference both the
preceding P (or I) frame and the following P (or I) frame.

GOP length — the number of frames between I-frames — is a fundamental trade-off:

- *Long GOP* (e.g., 250 frames, ~8 seconds at 30 fps): fewer expensive I-frames, higher
  compression. But seeking to an arbitrary point requires decoding from the last I-frame,
  which is slow; a single lost I-frame corrupts seconds of video.
- *Short GOP* (e.g., 30 frames, ~1 second): faster seeking, better error recovery, but
  more I-frame overhead.
- *All-I* (every frame is an I-frame): used in professional editing workflows where
  frame-accurate seeking is essential (e.g., ProRes, DNXHD). Very large files.

Broadcast streaming services typically use GOPs of 2–5 seconds. Live streaming sometimes
uses GOPs as short as 0.5 seconds to keep latency low and avoid buffering a future
B-frame reference.

#fig(
  [I/P/B frame structure and a GOP. Arrows show reference direction. B-frames reference
   both a past and a future anchor. The decoder must receive the P-frame at position 4
   _before_ decoding the B-frames at positions 2 and 3 (even though it displays them
   earlier), hence the coding-order vs. display-order reordering shown at the bottom.],
  cetz.canvas({
    import cetz.draw: *

    // Draw frame boxes
    let frames = ("I", "B", "B", "P", "B", "B", "P")
    let cols = (rgb("#d45f5f"), rgb("#5f9bd4"), rgb("#5f9bd4"),
                rgb("#5fd47a"), rgb("#5f9bd4"), rgb("#5f9bd4"), rgb("#5fd47a"))
    let x_off = 0.0
    for i in range(7) {
      rect((i * 1.4, 0.0), (i * 1.4 + 1.1, 0.7),
           fill: cols.at(i).lighten(60%), stroke: cols.at(i))
      content((i * 1.4 + 0.55, 0.35),
              text(fill: cols.at(i), weight: "bold", size: 8pt)[#frames.at(i)])
    }

    // P-frame arrows (forward ref from I to P4, P4 to P7)
    set-style(mark: (end: ">", size: 0.18))
    line((0.55, 0.0), (3 * 1.4 + 0.55, 0.0),
         stroke: rgb("#5fd47a"), mark: (end: ">", size: 0.15))
    line((3 * 1.4 + 0.55, 0.0), (6 * 1.4 + 0.55, 0.0),
         stroke: rgb("#5fd47a"), mark: (end: ">", size: 0.15))

    // B-frame arrows (bidirectional)
    for (bf, past, fut) in ((1, 0, 3), (2, 0, 3), (4, 3, 6), (5, 3, 6)) {
      line((past * 1.4 + 1.1, 0.7), (bf * 1.4 + 0.55, 1.1),
           stroke: (paint: rgb("#5f9bd4"), dash: "dashed"))
      line((fut * 1.4 + 0.0, 0.7), (bf * 1.4 + 0.55, 1.1),
           stroke: (paint: rgb("#5f9bd4"), dash: "dashed"))
    }

    // Display order label
    content((4.9, -0.45), text(size: 7.5pt)[Display: 1 2 3 4 5 6 7])
    content((4.9, -0.8), text(size: 7.5pt)[Coding:  1 4 2 3 7 5 6])
  })
)

== The Complete Encoder Pipeline

With motion compensation in hand, let's trace one P-frame through the full encoder
pipeline from raw pixels to compressed bits. This is the "hybrid" in hybrid video codec
— it hybridizes spatial (transform) coding with temporal (predictive) coding.

=== Step 1 — Partition into macroblocks

The frame is divided into 16×16 luma macroblocks (MBs). Each 16×16 luma MB comes with
two 8×8 chroma blocks (one Cb, one Cr), because chroma is subsampled 4:2:0 (the same
idea as JPEG, Chapter 42). So a 1920×1080 frame has $120 times 68 = 8160$ macroblocks
(with padding at the edges).

Modern codecs allow variable-size partitions — H.264 lets macroblocks be split into 8×8,
8×4, 4×8, or 4×4 sub-partitions. HEVC uses Coding Tree Units (CTUs) up to 64×64, split
recursively into smaller Coding Units (CUs) by a quadtree structure. This flexibility
means flat areas use large blocks (cheap) and detailed areas use small blocks (accurate).

=== Step 2 — Motion estimation and mode decision

For each block, the encoder tries every available prediction mode:
- *Inter prediction:* search the reference frame(s) for the best-matching block and
  record the motion vector.
- *Intra prediction:* predict from neighboring _already-encoded_ pixels in the _same_
  frame (more on this in the next section).
- *Skip:* signal that the block is copied directly from the reference with zero residual
  (the "nothing happened here" mode).

This is the most computationally expensive step. A naïve full search of every possible
motion vector in a $plus.minus 128$ pixel range at quarter-pixel accuracy would require
testing $(1024)^2 = 1048576$ candidate positions per block. Real encoders use fast
heuristic search algorithms — hexagonal search, diamond search, early termination — that
test perhaps 20–200 positions and find a near-optimal result. Even so, motion estimation
can take 80–95 percent of total encoding time.

=== Step 3 — Rate-distortion optimization (RDO)

The encoder does not just pick the prediction with the smallest residual. It picks the
one that minimizes a cost function called the _Lagrangian rate-distortion cost_:

$ J = D + lambda dot.c R $

where $D$ is the _distortion_ (how different the reconstructed block is from the
original, usually measured in sum of squared errors), $R$ is the number of _bits_ that
choice would require (motion vector bits + residual coefficient bits), and $lambda$ is a
multiplier tied to the quantization parameter (QP).

#mathrecall[
  The Lagrangian cost $J = D + lambda dot.c R$ was built from scratch in Chapter 41
  ("Rate–Distortion Optimization in Practice"): merging a quality term $D$ and a bit
  term $R$ into one scalar to minimize, where a _large_ $lambda$ makes bits expensive
  (favouring cheap predictions) and a _small_ $lambda$ makes them cheap (favouring better
  predictions). $lambda$ grows with QP; the relation H.264 uses is approximately
  $lambda approx 0.85 dot.c 2^((Q P - 12)\/3)$. Here we simply apply that machinery to
  the per-block choice between inter and intra prediction.
]

To see the knob in action, suppose intra prediction for a block would cost 300 bits and
give distortion 80, while inter prediction (motion compensation) costs 25 bits and gives
distortion 120. At $lambda = 0.5$ the costs are
$J_"intra" = 80 + 0.5 dot.c 300 = 230$ and $J_"inter" = 120 + 0.5 dot.c 25 = 132.5$, so
the encoder picks inter — bits are expensive enough that the 275-bit saving outweighs the
extra distortion. At $lambda = 0.1$ they flip:
$J_"intra" = 80 + 0.1 dot.c 300 = 110$ versus $J_"inter" = 120 + 0.1 dot.c 25 = 122.5$,
and now intra wins — bits are cheap enough that the better quality is worth it.

This is why two encoders that produce identical, fully compliant bitstreams can still
differ enormously in quality. The _standard_ only defines the bitstream format and the
_decoder_ — how a compliant decoder reconstructs a frame. The encoder is completely
unconstrained. A brilliant encoder that searches more motion vector candidates, uses
smarter RDO heuristics, and spends more computation can produce files that are 20–30 %
smaller at the same quality, while still being decoded by any compliant decoder.

#keyidea[
  *Encoder/decoder asymmetry* is a deliberate design choice. Decode must be fast,
  cheap, and deterministic — billions of devices decode video every second. Encode can
  be slow and expensive because you encode once and decode many times. This asymmetry
  is why streaming services spend enormous amounts of computing on their encoders
  (sometimes re-encoding old content for years), while your phone decodes in real time
  with negligible power draw.
]

=== Step 4 — Transform and quantization

Once a prediction mode is chosen, the residual block goes through the same pipeline as
JPEG (Chapter 42):

1. *2D DCT* (or a close integer approximation of it) transforms the residual into the
   frequency domain. Low-frequency coefficients at the top-left of the 8×8 block
   capture the dominant shapes; high-frequency coefficients at the bottom-right capture
   fine detail.

2. *Quantization* divides each coefficient by a step size from the quantization matrix
   and rounds. Coefficients smaller than half the step size become zero. High QP = large
   step sizes = more zeros = smaller file, at the cost of more blurring.

3. *Zig-zag scan* reorders the 8×8 block of coefficients from the top-left (DC) to the
   bottom-right (highest frequency), grouping the non-zero coefficients at the start
   and creating a run of trailing zeros.

4. *Run-length and entropy coding* encodes the zig-zag sequence. H.264 uses CAVLC
   (Context-Adaptive Variable-Length Coding) or CABAC (Context-Adaptive Binary
   Arithmetic Coding, the more powerful of the two). HEVC mandates CABAC only.

The integer DCT in H.264 is a 4×4 or 8×8 transform designed so that encoder and decoder
agree _bit-for-bit_ on reconstructed values without any floating-point rounding
disagreement. (Recall from Chapter 38 that floating-point DCT implementations can drift
by a bit here or there; standards require exact integer transforms for this reason.)

=== Step 5 — Reconstruction (the encoder reconstructs too)

Here is something that surprises many beginners: the _encoder_ maintains its own running
copy of the decoded frame. Why? Because the decoder does _not_ have access to the
original, uncompressed frame. When the encoder encodes block B and uses it as a reference
for block C, the decoder will use its own reconstructed version of B — which may differ
slightly from the original because of quantization error. If the encoder used the
original B as its reference and the decoder used the reconstructed B, they would diverge.

So the encoder runs an internal decoder loop: after quantizing and coding a block, it
immediately dequantizes and inverse-transforms to get the reconstructed version, and it
_uses that_ as the reference for future predictions. This internal loop is sometimes
called the _closed-loop encoder_ or the _in-loop encoder_. It is what makes the
encoder/decoder mismatch problem disappear.

#fig(
  [The hybrid encoder loop. The shaded path at the bottom — dequantize, IDCT, add to
   prediction, store — is the encoder's internal decoder. Both encoder and decoder maintain
   an identical reconstructed frame buffer.],
  cetz.canvas({
    import cetz.draw: *
    let bx = (w, h, txt, col) => (w, h, txt, col)

    // Boxes
    let boxes = (
      (0.0, 2.0, "Current\nframe", rgb("#e8f0fe")),
      (1.8, 2.0, "Partition\nMBs", rgb("#e8f0fe")),
      (3.7, 2.0, "Motion\nEst.", rgb("#fce8e6")),
      (5.6, 2.0, "Subtract\nResidual", rgb("#fce8e6")),
      (7.5, 2.0, "DCT +\nQuant.", rgb("#fce8e6")),
      (9.4, 2.0, "Entropy\nCode", rgb("#e6f4ea")),
    )

    for b in boxes {
      rect((b.at(0), b.at(1) - 0.35), (b.at(0) + 1.5, b.at(1) + 0.35),
           fill: b.at(3), stroke: c-rule)
      content((b.at(0) + 0.75, b.at(1)), text(size: 7.5pt)[#b.at(2)])
    }

    // Arrows between boxes
    for i in range(5) {
      let x1 = boxes.at(i).at(0) + 1.5
      let x2 = boxes.at(i + 1).at(0)
      line((x1, 2.0), (x2, 2.0), mark: (end: ">", size: 0.15))
    }

    // Decoder loop at bottom
    rect((5.6, 0.4), (7.1, 0.8), fill: rgb("#fff9e6"), stroke: c-accent2)
    content((6.35, 0.6), text(size: 7pt)[IQuant + IDCT])

    rect((3.7, 0.4), (5.1, 0.8), fill: rgb("#fff9e6"), stroke: c-accent2)
    content((4.4, 0.6), text(size: 7pt)[Add pred.])

    rect((1.8, 0.4), (3.2, 0.8), fill: rgb("#fff9e6"), stroke: c-accent2)
    content((2.5, 0.6), text(size: 7pt)[Ref. frame\nbuffer])

    // Connect decoder loop
    line((7.5 + 0.75, 2.0 - 0.35), (7.5 + 0.75, 0.6), (7.1, 0.6),
         stroke: c-accent2, mark: (end: ">", size: 0.13))
    line((5.6, 0.6), (5.1, 0.6), stroke: c-accent2, mark: (end: ">", size: 0.13))
    line((3.7, 0.6), (3.2, 0.6), stroke: c-accent2, mark: (end: ">", size: 0.13))
    line((2.5, 0.8), (2.5, 1.3), (3.7 + 0.75, 1.3), (3.7 + 0.75, 2.0 - 0.35),
         stroke: c-accent2, mark: (end: ">", size: 0.13))

    content((5.85, -0.15), text(size: 7pt, fill: c-accent2)[Internal decoder loop])

    // Bitstream output
    content((10.15, 2.5), text(size: 7.5pt, fill: c-key)[Bitstream])
    line((9.4 + 1.5, 2.0), (10.15, 2.35), stroke: c-key, mark: (end: ">", size: 0.13))
  })
)

== Intra Prediction: Exploiting Spatial Neighbors

Even inside a P-frame or B-frame, not every block can be sensibly predicted from a
reference frame. Scene cuts, new objects entering the frame, or regions that changed
radically give terrible inter-prediction quality. For those blocks, the encoder falls
back to _intra prediction_ — predicting from already-encoded neighboring blocks _in the
same frame._

=== How intra prediction works

Before the current block is encoded, the blocks to its left, above, and above-right have
already been encoded and reconstructed. Their boundary pixels are available to both
encoder and decoder. The encoder uses those boundary pixels to extrapolate the interior
of the current block.

H.264 defines nine 4×4 intra-prediction modes:
- *Mode 0 — Vertical:* copy the top-row pixels straight down.
- *Mode 1 — Horizontal:* copy the left-column pixels straight right.
- *Mode 2 — DC:* fill the block with the average of all top and left boundary pixels.
- *Modes 3–8 — Diagonal:* interpolate along one of six specific angles.

#fig(
  [Nine H.264 4×4 intra-prediction modes. Arrows show the direction of pixel
   propagation from the decoded boundary (hatched border) into the current block
   (light interior). DC mode fills with the mean.],
  cetz.canvas({
    import cetz.draw: *
    let sz = 0.6
    let modes = ("Vert", "Horiz", "DC", "Diag\nDL", "Diag\nDR", "Vert-R", "Horiz-D", "Vert-L", "Horiz-U")
    let arr_dirs = (
      (0, -1), (-1, 0), (0, 0), (-1, -1), (1, -1), (1, -1),
      (-1, 1), (-1, -1), (-1, 1),
    )
    for (i, mode) in modes.enumerate() {
      let col = calc.floor(i / 3)
      let row = calc.rem(i, 3)
      let ox = col * (sz + 0.5)
      let oy = row * (sz + 0.5)
      rect((ox, oy), (ox + sz, oy + sz),
           fill: c-soft, stroke: 0.5pt + c-rule)
      content((ox + sz / 2, oy + sz / 2),
              text(size: 6pt)[#mode])
    }
    content((4.2, 0.9), text(size: 7pt, fill: c-accent)[× 9 modes])
  })
)

HEVC expanded this enormously: 35 intra prediction modes for luma, including 33
directional modes covering finely-spaced angles from horizontal to vertical, plus planar
(a smooth bilinear surface fit) and DC. VVC pushed it further to 67 modes, plus several
new tools for palette coding (for screen content with flat regions of color) and
cross-component prediction (where the luma channel predicts the chroma channels).

#aside[
  The reason intra prediction needs so many angular modes is not mathematical elegance —
  it's the physics of the world. Scenes are full of edges: roof edges, window edges, hair
  edges, text edges. Those edges have a specific direction. If the intra prediction mode
  matches the direction of the nearest edge, the prediction lines up beautifully and the
  residual is tiny. Choosing the wrong mode produces a large residual that costs many bits.
  HEVC's 35 modes cover about every 5.5 degrees of angle; VVC's 67 modes cover about
  every 2.8 degrees.
]

Intra prediction is not only for I-frames. In a P-frame or B-frame, any block that has
a better intra prediction than any inter prediction will be coded intra. In heavily-cut
or high-motion video, a surprisingly large fraction of P-frame blocks end up coded intra.

== The In-Loop Filter

Quantization causes two notorious visual artifacts in block-based codecs:

- *Blocking artifacts:* the block boundaries become visible as a grid pattern. This
  happens because adjacent blocks are coded independently; after quantization they
  reconstruct to slightly different average values, creating a staircase edge at the
  boundary.
- *Ringing (Gibbs phenomenon):* high-frequency oscillations appear near sharp edges
  inside a block, caused by quantizing the high-frequency DCT coefficients to zero.

Both H.264 and HEVC attack blocking with a _deblocking filter_ (DBF) applied _inside_
the coding loop — that is, the reconstructed frame stored in the reference buffer is
the _filtered_ frame, not the raw reconstructed frame. This matters: if the encoder's
internal reconstructed reference frame matches what the decoder will use, the filter
helps future frames too, not just the current one.

The deblocking filter looks at the pixels on either side of every 4×4 block boundary
and decides, based on the quantization parameter and local signal strength, whether to
apply a gentle smoothing. Strong filters are applied where blocking is severe (high QP);
weak filters are applied where there is a true edge (and you do not want to blur it).

HEVC adds a second in-loop filter called the *Sample Adaptive Offset* (SAO). After
deblocking, SAO classifies each sample (pixel) into one of 32 categories based on its
local edge pattern or its value relative to neighbors, and adds a learned offset to each
category. This corrects systematic biases in the reconstructed values and reduces ringing.
SAO can reduce bitrate by 2–6 % at the same quality with no visible downside.

== Rate-Distortion Tradeoffs in Practice

We have now seen all the pieces. Let us put numbers to the benefit of motion compensation.
Suppose we are encoding a 1920×1080 frame at QP=28, typical for a medium-quality stream.

- An *I-frame* (no motion compensation) requires roughly 400–800 kilobits.
- A *P-frame* (one reference) requires roughly 50–200 kilobits for the same content.
- A *B-frame* (two references) requires roughly 30–120 kilobits.

The ratio varies enormously with content. A fast-motion sport scene compresses P-frames
poorly (large residuals) while a talking-head newscast compresses them superbly (the
background is identical frame to frame). This is why _constant-QP_ encoding produces
variable bitrate (the bits per frame vary with scene complexity) and _constant-bitrate_
(CBR) encoding produces variable quality. Modern streaming services use *capped
variable-bitrate* (capped VBR): they allow bitrate to vary within bounds, spending more
bits on complex scenes and fewer on simple ones.

#scoreboard(caption: "Video codec output sizes, 1-second 1080p30 clip, medium quality",
  [Raw uncompressed 1080p30 (1 second)], [~186 MB], [1:1], [3 bytes/pixel × 2.07 Mpx × 30 fps],
  [JPEG-I only (Ch. 42 pipeline, every frame)], [~12 MB], [15:1], [Each frame ~400 KB at QP 28],
  [P-frames added (no B)], [~3 MB], [62:1], [~100 KB/P-frame average],
  [I+P+B, GOP=30], [~1.8 MB], [103:1], [~60 KB/B-frame average],
  [I+P+B + in-loop filters], [~1.6 MB], [116:1], [DBF + SAO save ~10%],
)

== The tinyzip Step 20 Project

#project("Step 20 · Block motion-compensation demo")[

This step adds an inter-frame prediction demonstration to `tinyzip`. We implement a
`tinyzip/motioncomp.py` module that takes two greyscale frame arrays, encodes the
second using block motion compensation from the first, and decodes it back — a
round-trip that shows how much the residuals shrink compared to frame-differencing.

We reuse `tinyzip/transform.py` (Step 17) for the 2D DCT (`dct2d`/`idct2d`) and
`tinyzip/quant.py` (Step 18) for quantization, calling its canonical `q_index` (forward
map: coefficient → integer bin) and `q_value` (inverse map: bin → coefficient) primitives
— exactly the functions Chapter 39 built — rather than re-inventing the quantizer here.

```python
# tinyzip/motioncomp.py
"""
Step 20 — Block motion-compensation demo (inter-frame prediction).

API
---
encode_frame(ref: bytes, cur: bytes, width: int, height: int,
             block_size: int = 8, qp: int = 28) -> bytes
    Encode `cur` using `ref` as a reference; return a compact payload.

decode_frame(ref: bytes, payload: bytes, width: int, height: int,
             block_size: int = 8, qp: int = 28) -> bytes
    Reconstruct `cur` from `ref` and the payload produced by encode_frame.

Both functions work on raw greyscale bytes (one byte per pixel, row-major).
Round-trip guarantee: decode_frame(ref, encode_frame(ref, cur, ...), ...) == cur
  (modulo quantization loss — see LOSSLESS flag below).
"""

from __future__ import annotations
import struct
from tinyzip.transform import dct2d, idct2d       # Step 17 (Ch 38)
from tinyzip.quant import q_index, q_value        # Step 18 (Ch 39)

BLOCK = 8          # block size (pixels)
SEARCH = 16        # motion search range (±SEARCH pixels)


def _pad(data: bytes, width: int, height: int,
         bsize: int) -> list[list[int]]:
    """Convert flat bytes to a 2-D list padded to multiples of bsize."""
    rows = (height + bsize - 1) // bsize * bsize
    cols = (width  + bsize - 1) // bsize * bsize
    grid = [[0] * cols for _ in range(rows)]
    for y in range(height):
        for x in range(width):
            grid[y][x] = data[y * width + x]
    # Replicate last row/col to fill padding
    for y in range(height, rows):
        for x in range(cols):
            grid[y][x] = grid[height - 1][x]
    for y in range(rows):
        for x in range(width, cols):
            grid[y][x] = grid[y][width - 1]
    return grid


def _block_sad(a: list[list[int]], b: list[list[int]],
               ay: int, ax: int, by: int, bx: int,
               bsize: int) -> int:
    """Sum of Absolute Differences between two bsize×bsize blocks."""
    total = 0
    for dy in range(bsize):
        for dx in range(bsize):
            total += abs(a[ay + dy][ax + dx] - b[by + dy][bx + dx])
    return total


def _get_block(grid: list[list[int]], y: int, x: int,
               bsize: int) -> list[list[float]]:
    return [[float(grid[y + dy][x + dx]) for dx in range(bsize)]
            for dy in range(bsize)]


def _set_block(grid: list[list[int]], y: int, x: int,
               block: list[list[float]], bsize: int) -> None:
    for dy in range(bsize):
        for dx in range(bsize):
            v = int(round(block[dy][dx]))
            grid[y + dy][x + dx] = max(0, min(255, v))


def encode_frame(
    ref: bytes, cur: bytes, width: int, height: int,
    block_size: int = BLOCK, qp: int = 28
) -> bytes:
    """
    Encode `cur` using `ref` as reference via block motion compensation.
    Returns a compact binary payload (not a fully-compliant video bitstream,
    but round-trippable with decode_frame).

    Payload layout (little-endian):
      4 bytes: width
      4 bytes: height
      4 bytes: block_size
      4 bytes: qp
      For each block (raster order):
        1 byte:  mv_dy + 128   (motion vector, vertical, range -128..+127)
        1 byte:  mv_dx + 128   (motion vector, horizontal)
        bsize*bsize * 1 byte each: quantized residual coefficients
          (each clamped to -127..+127 and stored as signed byte)
    """
    bsize = block_size
    ref_g = _pad(ref, width, height, bsize)
    cur_g = _pad(cur, width, height, bsize)
    rows_b = (height + bsize - 1) // bsize
    cols_b = (width  + bsize - 1) // bsize
    H = rows_b * bsize
    W = cols_b * bsize

    out: list[bytes] = []
    out.append(struct.pack("<4i", width, height, bsize, qp))

    step = max(1, qp // 4)      # simple scalar quantization step

    for by in range(rows_b):
        for bx in range(cols_b):
            cy = by * bsize
            cx = bx * bsize

            # --- motion search (full search in ±SEARCH window) ---
            best_sad = 10 ** 9
            best_dy, best_dx = 0, 0
            for dy in range(-SEARCH, SEARCH + 1):
                for dx in range(-SEARCH, SEARCH + 1):
                    ry = cy + dy
                    rx = cx + dx
                    if ry < 0 or ry + bsize > H: continue
                    if rx < 0 or rx + bsize > W: continue
                    sad = _block_sad(cur_g, ref_g, cy, cx, ry, rx, bsize)
                    if sad < best_sad:
                        best_sad = sad
                        best_dy, best_dx = dy, dx

            # --- compute residual ---
            cur_blk = _get_block(cur_g, cy, cx, bsize)
            ref_blk = _get_block(ref_g,
                                  cy + best_dy, cx + best_dx, bsize)
            resid = [[cur_blk[r][c] - ref_blk[r][c]
                       for c in range(bsize)] for r in range(bsize)]

            # --- DCT + quantize ---
            # Reuse the canonical Step-18 quantizer (tinyzip.quant.q_index):
            # forward map a real coefficient -> integer bin index, step = `step`,
            # rounding offset f = 0.5 (plain rounding, no extra dead-zone here).
            coeffs = dct2d(resid)
            qcoeffs = [[q_index(coeffs[r][c], float(step), 0.5)
                         for c in range(bsize)] for r in range(bsize)]

            # --- pack block ---
            mv_bytes = bytes([best_dy + 128, best_dx + 128])
            coeff_bytes = bytes(
                max(-127, min(127, qcoeffs[r][c])) & 0xFF
                for r in range(bsize) for c in range(bsize)
            )
            out.append(mv_bytes + coeff_bytes)

    return b"".join(out)


def decode_frame(
    ref: bytes, payload: bytes, width: int, height: int,
    block_size: int = BLOCK, qp: int = 28
) -> bytes:
    """
    Decode the output of encode_frame and return the reconstructed frame
    as greyscale bytes.
    """
    offset = 0
    w, h, bsize, q = struct.unpack_from("<4i", payload, offset)
    offset += 16

    ref_g = _pad(ref, w, h, bsize)
    rows_b = (h + bsize - 1) // bsize
    cols_b = (w + bsize - 1) // bsize
    H = rows_b * bsize
    W = cols_b * bsize
    rec_g = [[0] * W for _ in range(H)]

    step = max(1, q // 4)

    for by in range(rows_b):
        for bx in range(cols_b):
            cy = by * bsize
            cx = bx * bsize

            dy = payload[offset] - 128
            dx = payload[offset + 1] - 128
            offset += 2

            # read quantized coefficients
            qcoeffs = []
            for _ in range(bsize):
                row = []
                for _ in range(bsize):
                    b = payload[offset]
                    offset += 1
                    # re-interpret as signed byte
                    row.append(b if b < 128 else b - 256)
                qcoeffs.append(row)

            # dequantize + IDCT  (canonical Step-18 inverse map q_value)
            coeffs = [[q_value(qcoeffs[r][c], float(step))
                        for c in range(bsize)] for r in range(bsize)]
            resid = idct2d(coeffs)

            # add prediction
            ref_blk = _get_block(ref_g, cy + dy, cx + dx, bsize)
            rec_blk = [[ref_blk[r][c] + resid[r][c]
                         for c in range(bsize)] for r in range(bsize)]
            _set_block(rec_g, cy, cx, rec_blk, bsize)

    # flatten and crop
    result = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            result[y * w + x] = rec_g[y][x]
    return bytes(result)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import os, math

    W, H = 64, 64

    # Build two synthetic "frames": frame 1 is random noise,
    # frame 2 is frame 1 shifted 3 pixels to the right.
    ref_data = bytes(os.urandom(W * H))
    cur_list = bytearray(W * H)
    SHIFT = 3
    for y in range(H):
        for x in range(W):
            cur_list[y * W + x] = ref_data[y * W + max(0, x - SHIFT)]
    cur_data = bytes(cur_list)

    # Compute residual energy without motion compensation
    raw_diff_energy = sum((cur_data[i] - ref_data[i]) ** 2
                          for i in range(W * H))

    # Encode and decode
    payload = encode_frame(ref_data, cur_data, W, H, block_size=8, qp=4)
    rec_data = decode_frame(ref_data, payload, W, H, block_size=8, qp=4)

    # Compute PSNR
    mse = sum((rec_data[i] - cur_data[i]) ** 2
               for i in range(W * H)) / (W * H)
    psnr = 10 * math.log10(255 ** 2 / mse) if mse > 0 else float("inf")

    payload_bytes = len(payload)
    raw_bytes = W * H

    print(f"Frame size:          {W}x{H} = {raw_bytes} bytes raw")
    print(f"Payload size:        {payload_bytes} bytes")
    print(f"Raw diff energy:     {raw_diff_energy:,}")
    print(f"PSNR after MC+quant: {psnr:.1f} dB")
    assert psnr > 35, f"PSNR too low: {psnr}"
    print("Self-test PASSED.")
```

#mathrecall[
  The self-test reports quality with *PSNR* (Peak Signal-to-Noise Ratio),
  $"PSNR" = 10 log_10 (255^2 \/ "MSE")$ dB, built from the *MSE* (mean of the squared
  pixel errors). Both were defined in Chapter 39 and used throughout the JPEG chapter
  (Chapter 42): higher PSNR means lower error, with above 40 dB nearly invisible and
  below 30 dB visibly degraded. We reuse them here unchanged.
]

When you run this self-test (`python tinyzip/motioncomp.py`), it builds two 64×64
greyscale frames where frame 2 is frame 1 shifted 3 pixels right, encodes frame 2 using
frame 1 as a reference, decodes, and reports:

- *Payload size* — much smaller than 64×64 = 4096 raw bytes, because the motion
  vectors explain most of the content.
- *Raw diff energy* — the energy of the naive difference (no motion compensation); large.
- *PSNR after MC+quant* — at QP=4 (near-lossless), well above 35 dB.

At QP=4 the quantization step is tiny (1 pixel) so PSNR is high. Raise QP to 28 to see
how quality drops as the quantization step grows.

#gopython("Bytes as signed integers")[
  In Python, a `bytes` object stores values 0–255 (unsigned). When we need signed bytes
  (values -128 to +127), we must convert manually. The expression `b if b < 128 else b - 256`
  reinterprets an unsigned byte `b` as signed: values 0–127 stay the same; values
  128–255 become -128 to -1. This trick appears often in binary protocols that use signed
  integers in byte streams.

  ```python
  # Unsigned to signed byte conversion
  for b in [0, 50, 127, 128, 200, 255]:
      signed = b if b < 128 else b - 256
      print(f"{b:3d} → {signed:4d}")
  # Output:
  #   0 →    0
  #  50 →   50
  # 127 →  127
  # 128 → -128
  # 200 →  -56
  # 255 →   -1
  ```
]
]

== A Brief History: From H.261 to Today

#history[
  *1974 — DCT proposed.* Nasir Ahmed, T. Natarajan, and K. R. Rao publish the Discrete
  Cosine Transform in 1974 (IEEE Transactions on Computers). Nobody knows yet that this
  mathematics will compress the entire internet.

  *1988 — H.261.* The ITU-T ratifies H.261 in November 1988, the first digital video
  standard to see real deployment. It targets ISDN videoconferencing at 64 kbit/s
  multiples (p×64 kbit/s, hence the internal name "p×64"). H.261 uses 16×16 macroblocks
  with half-integer DCT, CIF (352×288) or QCIF (176×144) resolution. It
  introduces the fundamental macroblock concept that every codec since has inherited.
  The motion search range is small (±15 pixels) and there are no B-frames or sub-pixel
  motion, but the architecture is unmistakably the ancestor of every modern codec.

  *1992 — MPEG-1.* ISO/IEC finalizes MPEG-1, designed for CD-ROM at 1.5 Mbit/s. It
  introduces B-frames and the GOP structure. Video quality: roughly VHS. The audio
  layer becomes the famous MP3.

  *1994/1995 — MPEG-2 / H.262.* The joint ITU-T/ISO standard that powers DVD (up to
  720×480), broadcast digital TV (SDTV and HDTV), and Blu-ray (via H.264). MPEG-2 is
  still actively deployed in broadcast infrastructure worldwide as of 2026.

  *2003 — H.264 / AVC.* Finalized by the Joint Video Team (JVT) in May 2003. Key
  advances: variable block sizes (down to 4×4), multiple reference frames, quarter-pixel
  motion, 9 intra-prediction modes for 4×4 and 4 modes for 16×16, in-loop deblocking
  filter, and CABAC. Approximately doubles MPEG-2 compression at the same quality. Still
  the most universally supported codec on Earth in 2026.

  *2013 — H.265 / HEVC.* Ratified January 2013. Introduces CTUs up to 64×64, flexible
  quadtree partitioning, 35 intra modes, and the SAO in-loop filter. Roughly halves
  H.264 file sizes at the same quality. Its patent licensing fragmentation (multiple
  competing pools, unclear royalty terms) significantly slowed adoption and motivated the
  royalty-free movement.

  *2018 — AV1.* Released by the Alliance for Open Media (AOMedia), founded 2015 with
  Google, Mozilla, Cisco, Microsoft, Intel, Netflix, Amazon. Royalty-free. Roughly 30 %
  better than HEVC. Variable-size superblocks up to 128×128, 56 intra modes, compound
  prediction, film grain synthesis, and a suite of other tools. YouTube deployed AV1 in
  2018; Netflix in 2020.

  *2020 — H.266 / VVC.* Finalized July 2020. Another ~50 % bitrate reduction over HEVC,
  with tools for 4K/8K, 360° video, and screen content. Licensing again fragmented.

  *2025–2026 — AV2.* The AOMedia Alliance announced AV2 targeting ~30 % over AV1,
  with new tools for augmented/virtual reality, multi-program split-screen, and screen
  content. The bitstream finalized into 2026, with wide hardware decode support not
  expected until 2027–2028.
]

#algo(
  name: "Block Motion Compensation (BMC)",
  year: "1981 (theoretical); 1988 (H.261, first standard)",
  authors: "Hans Georg Musmann (H.261 contributions); multiple MPEG/ITU-T contributors",
  aim: "Predict a video frame from a reference frame by finding, for each block, the displaced reference block that minimizes prediction error.",
  complexity: "Encoding: O(W·H·S²) per frame for full search (W,H = frame size, S = search range); decoding: O(W·H) — linear.",
  strengths: "Massive redundancy reduction for smooth motion; asymmetric: encode expensive, decode cheap; composable with any transform + entropy coder.",
  weaknesses: "Poorly suited to complex non-translational motion (rotation, scaling, occlusion); large residuals at motion boundaries; search is the dominant encoding cost.",
  superseded: "B-frames and multi-reference frames extend it; newer codecs add sub-pixel, affine, and optical-flow-based motion models.",
)[
  Block motion compensation is the single most impactful technique in video coding.
  Every frame in a P or B slot saves 80–95 % of the bits compared to independent
  intra coding for typical content, because the motion model is usually accurate enough
  to reduce residuals to near-zero for most blocks.
]

#algo(
  name: "Rate-Distortion Optimization (RDO)",
  year: "Formalized in H.264 (2003); theoretical roots in Shannon 1948",
  authors: "Thomas Wiegand et al. (H.264 JVT); Rate-Distortion theory: Claude Shannon",
  aim: "Choose encoding parameters (mode, motion vector, partition size, etc.) that minimize a Lagrangian cost J = D + λR, jointly optimizing quality and bitrate.",
  complexity: "Adds a constant factor (typically 2–10×) to encoding time vs. greedy mode selection; no decoder complexity increase.",
  strengths: "Globally-principled: allows the encoder to trade off any decision against rate; enables modern encoders to outperform ad-hoc heuristics by 20–30 %.",
  weaknesses: "Computationally expensive; λ must be calibrated; does not model perceptual distortion unless SSIM or VMAF replaces SSE as D.",
  superseded: "Extended to VMAF/perceptual metrics, machine-learning-guided search, and neural RDO in recent codecs.",
)[]

== Key Design Choices and Tradeoffs

=== Block size

Larger blocks are cheaper (fewer motion vectors to transmit) but miss fine-grained
motion. A 64×64 block moving as a whole gives one motion vector for 4096 pixels; but if
half of those pixels belong to a foreground object and half to the background, neither
half is well-predicted. Flexible partitioning — the quadtree structure of HEVC/VVC, or
the superblock + partition tree of AV1 — solves this by using large blocks where the
frame is smooth and splitting down to 4×4 where it is complex.

=== Reference frames

H.261 used only one reference frame. H.264 allows up to 16. Using an older reference
frame (two or three frames back) can help when an object was occluded in the immediately
previous frame but visible earlier. Multiple references add complexity but can deliver
5–15 % bitrate savings on complex content.

=== Intra prediction vs. inter prediction

Intra prediction is used when:
- The block is in an I-frame (no inter prediction allowed).
- Inter prediction gives a poor match (scene cut, new object, etc.).
- The RDO cost of intra is lower than inter (rare for P-frames in smooth video, common
  for B-frames in complex scenes near cuts).

Modern encoders spend enormous effort deciding _which_ prediction type to use for each
block. This is called *mode decision* and it is the core intellectual challenge of
encoder design.

=== Entropy coding: CAVLC vs. CABAC

H.264 supports two entropy coders. CAVLC (Context-Adaptive Variable-Length Coding) is
simpler, has lower decoder complexity, and was mandatory in the Baseline profile used
for mobile. CABAC (Context-Adaptive Binary Arithmetic Coding) is the arithmetic coder
from Chapter 26, adapted to code binary symbols with context-based probability estimates.
It is 10–15 % more efficient than CAVLC and mandatory in Main and High profiles. HEVC
and VVC mandate CABAC only. AV1 uses its own variant of a binary arithmetic coder with
similar efficiency.

#pitfall[
  CABAC has long been assumed to be a "free lunch" — just plug in the arithmetic coder
  from Chapter 26 and save 10–15 % bits. But CABAC's speed is the hidden cost. Binary
  arithmetic coders are inherently serial (each symbol updates the state that the next
  symbol needs), so they cannot be parallelized. H.264 CABAC can be 2–5× slower to
  decode than CAVLC on the same hardware. This motivated hardware-dedicated CABAC
  engines in mobile chips. HEVC's CABAC is faster than H.264's because of better
  context design, but still a bottleneck in pure-software decode.
]

== Encoder Asymmetry: Why Encoding Is So Expensive

Let's put real numbers on the asymmetry. On a modern desktop CPU, a single-pass encode
of 1080p30 video using x264 at medium preset runs at roughly 50–150 frames per second.
The same computer decodes at 300–600 fps using optimized SIMD decode (or 1000+ fps with
hardware assist). The ratio is about 10:1 in decode's favor.

For HEVC, the reference encoder (HM) at its best-quality setting runs at approximately
0.05–0.5 fps on the same hardware — more than 1000× slower than real-time. The
production encoder x265 runs at 10–50 fps depending on preset. For AV1, the reference
encoder libaom can take hours per second of video at its highest quality. Even the
optimized SVT-AV1 runs at roughly 10–30 fps at medium settings.

Why? Every macroblock or CU (coding unit) in a modern codec requires:
1. Testing perhaps 30–200 motion vector candidates per reference frame.
2. Testing intra prediction in 9–67 angular modes.
3. Evaluating partition sizes at multiple depths (4 or 5 levels for HEVC/AV1).
4. Running the full RDO cost function for each candidate.
5. Keeping an internal reconstruction loop that runs a forward transform for _every
   candidate tested_, not just the winner.

Decoding requires none of this search — the decisions have already been made and encoded
in the bitstream. Decode is: read motion vector, copy block, read coefficients,
dequantize, inverse-transform, add. Fast and parallelizable.

This is why streaming services spend millions of dollars on GPU-accelerated encoding
farms and deliver those encoded streams to billions of devices that decode on \$2 of
silicon inside a phone chip.

== Checkpoint Questions

#checkpoint[
  A video codec uses a GOP of length 60 with the pattern I B B P B B P …
  (one I-frame, then alternating B B P). How many I-frames appear per 60-frame GOP?
  How many P-frames?
][
  One I-frame (frame 1). P-frames appear every 3rd frame after the I-frame: frames 4,
  7, 10, …, 58. That is 19 P-frames in 60 frames. The remaining 40 frames are B-frames.
]

#checkpoint[
  Why does the deblocking filter operate _inside_ the coding loop rather than as a
  post-process applied to the final output?
][
  Because the filtered reconstructed frame is what the encoder stores as the reference
  for future motion compensation. If the filter were only a post-process, the encoder's
  internal reference frame would not match what the decoder uses, causing encoder-decoder
  drift. In-loop filtering ensures both encoder and decoder maintain identical reference
  frame buffers.
]

#takeaways((
  "Video carries far more redundancy than a still image: temporal redundancy between
   consecutive frames is removed by block motion compensation, while spatial redundancy
   within each frame is removed by DCT + quantization (the JPEG-like core).",
  "Block motion compensation partitions the current frame into blocks, searches the
   reference frame for the best-matching block, and records only the motion vector and
   the small prediction residual.",
  "I-frames are self-contained (large); P-frames predict from one past reference
   (medium); B-frames predict from past and future (smallest). B-frames require
   coding-order reordering.",
  "The Group of Pictures (GOP) determines how often I-frames appear; long GOPs
   compress better but hurt random access and error recovery.",
  "Rate-distortion optimization (J = D + λR) is the encoder's central decision engine:
   it jointly minimizes quality loss and bit cost for every encoding choice.",
  "The encoder runs an internal reconstruction loop to match the decoder's state;
   this prevents encoder-decoder drift.",
  "The in-loop deblocking filter (H.264+) and Sample Adaptive Offset (HEVC+) reduce
   blocking and ringing artifacts while keeping the reference buffer consistent.",
  "The standard defines the bitstream format and the decoder; the encoder is unconstrained,
   which is why encoder quality varies enormously and why encoding is far more expensive
   than decoding.",
  "Step 20 of tinyzip implements a block motion compensation demo that encodes two
   greyscale frames and round-trips them through motion estimation, DCT, and
   quantization.",
))

== Exercises

#exercise("51.1", 1)[
  A 1920×1080 frame is divided into 16×16 macroblocks. How many macroblocks are there?
  (Assume the frame dimensions are exact multiples of 16.) If each macroblock contains
  a 16×16 luma block and two 8×8 chroma blocks, how many 8×8 blocks are processed per
  frame in total?
]

#solution("51.1")[
  Macroblocks: $(1920 / 16) times (1080 / 16) = 120 times 67.5$. Since 1080 is not
  a multiple of 16 (1080 / 16 = 67.5), the frame is padded to the next multiple:
  $1088$ lines, giving $120 times 68 = 8160$ macroblocks. Each macroblock has four
  8×8 luma sub-blocks plus two 8×8 chroma blocks = 6 blocks. Total: $8160 times 6 = 48960$ blocks per frame.
]

#exercise("51.2", 1)[
  Explain in plain words (no equations) why B-frames are smaller than P-frames for the
  same content, and give a concrete physical example of a scene where B-frames give
  a particularly large advantage.
]

#solution("51.2")[
  A B-frame has two reference frames: one before and one after it in display order. For
  any block, the encoder picks whichever reference (past, future, or an average of both)
  gives the smallest residual. With two references, the chance of finding a near-perfect
  prediction is much higher. Concrete example: a ball thrown in an arc. In the middle of
  the arc, the ball is halfway between where it came from (past frame) and where it is
  going (future frame). The average of those two positions predicts the ball's current
  position almost exactly, leaving near-zero residuals. A P-frame would only have the
  past position, which is less accurate.
]

#exercise("51.3", 2)[
  You are designing a video codec for live surgery where the stream must survive one
  dropped packet in every ten without losing synchronization for more than one frame.
  What GOP structure would you choose? What are the tradeoffs versus a standard 60-frame
  GOP used by Netflix?
]

#solution("51.3")[
  A very short GOP, perhaps 2–5 frames (one I-frame, then 1–4 P-frames and no B-frames).
  This ensures that the decoder can resync at most 2–5 frames after a dropped packet,
  within one frame of display time at 30 fps. Trade-offs vs. a 60-frame GOP:
  (1) Bitrate is significantly higher — more I-frames cost many more bits.
  (2) No B-frames means no look-ahead buffering, which is essential for real-time surgery
  video where delay must be minimal (a future reference frame would require buffering that
  adds latency).
  (3) Better error recovery and frame-accurate seeking, critical for medical review.
  Netflix can afford a long GOP and B-frames because the content is pre-recorded and
  re-buffering is tolerable; live surgery has neither luxury.
]

#exercise("51.4", 2)[
  The rate-distortion cost for two candidate predictions for a block are:
  - Intra prediction: distortion = 50, bits = 400.
  - Inter prediction (motion compensation): distortion = 200, bits = 20.

  (a) At $lambda = 0.4$, which mode has lower Lagrangian cost?
  (b) At $lambda = 0.05$, which mode has lower Lagrangian cost?
  (c) What does this tell you about how $lambda$ interacts with QP?
]

#solution("51.4")[
  (a) $lambda = 0.4$:
  $J_"intra" = 50 + 0.4 times 400 = 50 + 160 = 210$.
  $J_"inter" = 200 + 0.4 times 20 = 200 + 8 = 208$.
  Inter prediction wins (barely) — bits are expensive so the 380-bit savings outweighs
  the 150-unit distortion increase.

  (b) $lambda = 0.05$:
  $J_"intra" = 50 + 0.05 times 400 = 50 + 20 = 70$.
  $J_"inter" = 200 + 0.05 times 20 = 200 + 1 = 201$.
  Intra prediction wins decisively — bits are cheap so the lower distortion wins.

  (c) $lambda$ grows with QP (more aggressive quantization = bits are scarce). At high
  QP (high $lambda$), the encoder aggressively saves bits even at quality cost, preferring
  inter prediction. At low QP (low $lambda$), quality dominates, so the encoder is happy
  to spend more bits for better prediction. This is why at very high quality (low QP),
  more blocks use intra prediction.
]

#exercise("51.5", 2)[
  In the tinyzip Step 20 code, the motion search range is ±16 pixels. The frame is
  padded to multiples of the block size. Explain (a) what happens when the best motion
  vector search finds a position outside the padded frame bounds and the code skips it,
  and (b) what would happen without the bounds check (write a specific example of the bug
  that would occur in Python).
]

#solution("51.5")[
  (a) The bounds check `if ry < 0 or ry + bsize > H: continue` ensures the encoder
  never samples outside the padded reference grid. When the search would go out of bounds
  (e.g., for a block in the top row, `ry = -16` is out of bounds), that candidate is
  simply skipped. The encoder will find the next-best in-bounds position. For border
  blocks this restricts the effective search range, but in practice almost all motion
  is within bounds.

  (b) Without the bounds check, `ref_g[cy + dy][cx + dx]` would access a negative row
  index in Python. Python lists allow negative indexing (`list[-1]` returns the last
  element), so `ref_g[-1]` would silently return the _last row_ of the grid — a
  completely wrong prediction from the bottom of the frame. The residual would be large
  and wrong, PSNR would drop sharply, and the bug would be silent (no exception). This
  is a classic off-by-one error that corrupts corner macroblocks without crashing.
]

#exercise("51.6", 2)[
  The self-test in `motioncomp.py` uses a synthetic frame shifted by 3 pixels. Modify
  the self-test (conceptually, not by running it) so that the test frame is the reference
  frame _rotated_ 5 degrees instead of shifted. Would you expect the PSNR to increase
  or decrease compared to the translation test? Why?
]

#solution("51.6")[
  PSNR would decrease for the rotation test. Block motion compensation models only
  translational motion: it shifts a rectangular block by (Δx, Δy). Rotation is a
  non-translational transformation — after rotating 5 degrees, most blocks no longer
  look like any shifted copy of the same block in the reference frame. Pixels at the
  corners of each block now belong to a rotated neighborhood that no axis-aligned copy
  can match well. The residuals would be large even with the best motion vector, and
  quantization would need to retain more non-zero coefficients, increasing payload size
  and reducing PSNR. This is why modern codecs add affine and perspective motion models
  for camera-panning or rotating content.
]

#exercise("51.7", 3)[
  The H.264 deblocking filter applies a _strong_ filter across block boundaries when the
  quantization parameter QP is high and the local signal is smooth, and a _weak_ filter
  when QP is low or the local signal already has a genuine edge. Design a simplified
  decision rule in pseudocode: given two adjacent 4-pixel rows at a block boundary
  (call them $p_0, p_1, p_2, p_3$ on one side and $q_0, q_1, q_2, q_3$ on the other,
  with $p_0$ and $q_0$ at the boundary), write conditions that decide between:
  (a) apply no filter, (b) apply a 3-tap smoothing filter, (c) apply a 5-tap smoothing
  filter.
]

#solution("51.7")[
  A simplified rule inspired by the H.264 deblocking filter specification:
  ```
  threshold_A = max(2, QP / 4)     # edge threshold
  threshold_B = max(1, QP / 8)     # interior smoothness threshold

  # Strength decision
  edge_delta = abs(p0 - q0)        # jump across boundary
  p_smooth   = abs(p2 - p0)        # interior smoothness, p-side
  q_smooth   = abs(q2 - q0)        # interior smoothness, q-side

  if edge_delta >= 4 * threshold_A:
      # True edge in the image — do not filter (preserve the edge)
      apply NO FILTER
  elif edge_delta < threshold_A and p_smooth < threshold_B and q_smooth < threshold_B:
      # Smooth region with a blocking artifact — strong smoothing
      # 5-tap: filter p0, p1 on one side and q0, q1 on the other
      apply 5-TAP FILTER:
          p0' = (p2 + 2*p1 + 2*p0 + 2*q0 + q1 + 4) / 8
          q0' = (p1 + 2*p0 + 2*q0 + 2*q1 + q2 + 4) / 8
  else:
      # Moderate artifact — gentle smoothing at boundary only
      # 3-tap: adjust p0 and q0 only
      apply 3-TAP FILTER:
          delta = (q0 - p0 + 4) / 8   # clipped to [-threshold_A, threshold_A]
          p0' = clamp(p0 + delta, 0, 255)
          q0' = clamp(q0 - delta, 0, 255)
  ```
  The key insight: the filter must distinguish a true image edge (which should not be
  blurred) from a blocking artifact (which should). The `threshold_A` test on `edge_delta`
  does this: a very large jump across the boundary is likely a real edge; a small jump
  in an otherwise smooth region is likely a quantization artifact.
]

#exercise("51.8", 3)[
  Extend `tinyzip/motioncomp.py` to report the *average motion vector magnitude* and the
  *fraction of blocks with zero-magnitude motion vectors* across all blocks in the encoded
  payload. Add these statistics to the `__main__` self-test output. (You do not need to
  run the code — describe the Python changes needed and write the key new lines.)
]

#solution("51.8")[
  In `encode_frame`, collect motion vectors into a list:
  ```python
  mv_log: list[tuple[int,int]] = []
  # Inside the block loop, after best_dy/best_dx are determined:
  mv_log.append((best_dy, best_dx))
  ```
  Return `mv_log` alongside the payload (change return type to `tuple[bytes, list]`).
  In `__main__`:
  ```python
  import math
  payload, mv_log = encode_frame(ref_data, cur_data, W, H, block_size=8, qp=4)
  magnitudes = [math.sqrt(dy**2 + dx**2) for dy, dx in mv_log]
  avg_mag = sum(magnitudes) / len(magnitudes)
  zero_frac = sum(1 for m in magnitudes if m == 0) / len(magnitudes)
  print(f"Avg MV magnitude: {avg_mag:.2f} px")
  print(f"Zero MVs:         {zero_frac*100:.1f}%")
  ```
  For a 3-pixel shift, you would expect most blocks to have magnitude close to 3.0 and
  very few zero vectors. For a static frame (no motion), almost all vectors would be
  zero.
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/1218189")[Wiegand, T. et al. (2003). _Overview of the H.264/AVC Video Coding Standard._ IEEE TCSVT 13(7).] — The definitive overview paper for the codec that still dominates the internet.

- #link("https://ieeexplore.ieee.org/document/6316136")[Sullivan, G. J. et al. (2012). _Overview of the High Efficiency Video Coding (HEVC) Standard._ IEEE TCSVT 22(12).] — Comprehensive treatment of HEVC's CTU quadtree, 35 intra modes, and SAO filter.

- #link("https://arxiv.org/abs/2008.06091")[Chen, Y. et al. (2020). _An Overview of Core Coding Tools in the AV1 Video Codec._ arXiv:2008.06091.] — AV1's design decisions from the engineers who built it: superblocks, compound prediction, film grain.

- #link("https://www.fastvdo.com/spie04/spie04-h264OverviewPaper.pdf")[Richardson, I. (2004). _The H.264/AVC Advanced Video Coding Standard: Overview and Introduction._] — Accessible entry point before diving into the ITU-T spec itself.

- #link("https://arxiv.org/abs/1812.00101")[Lu, G. et al. (2019). _DVC: An End-to-End Deep Video Compression Framework._ CVPR 2019 / arXiv:1812.00101.] — The first learned video codec to seriously challenge the hybrid codec on rate-distortion grounds.

#bridge[
  We now know the _template_ of the hybrid video codec: predict temporally with motion
  compensation, predict spatially with intra prediction, transform and quantize the
  residuals, entropy-code the result. In Chapter 52 we will follow this template through
  history — H.261, MPEG-1, MPEG-2 (the codec of DVD and broadcast TV), H.263, and then
  H.264/AVC in serious depth: its variable block sizes, multi-reference frames, CABAC
  in detail, and the profiles that made it the universal default. Understanding AVC's
  specific choices explains why it outperformed every earlier codec by such a wide margin
  and why it is still encoding two-thirds of all new video content more than twenty years
  after its standardization.
]
