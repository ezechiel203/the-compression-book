## Video Compression: Motion Compensation and the H.26x / AV1 Lineage

Video is the largest single category of bytes moving across the planet — by most estimates well over half of all internet traffic. The reason video compresses so well is also the reason it dominates traffic: a video is not a sequence of independent images but a sequence of *nearly identical* images. Understanding how codecs exploit that fact, and the four-decade standards war that resulted, is the goal of this section.

### Two redundancies, two predictions

A still image carries **spatial redundancy**: neighboring pixels are correlated, so a transform (recall the DCT and JPEG) concentrates energy into a few coefficients you can cheaply quantize. Video adds **temporal redundancy**: frame *t* and frame *t+1* are usually the same scene shifted slightly. If you simply subtracted consecutive frames, the difference (the *residual*) would already be mostly zero — but only where nothing moved. Where objects move, naive subtraction produces large residuals exactly at edges.

The central insight, dating to the 1970s and made practical by the late 1980s, is **block-based motion compensation**. Partition the frame into blocks (16×16 "macroblocks" historically; flexible quadtree partitions today). For each block, the encoder searches the previously decoded frame for the best-matching block and records a **motion vector** — a small (Δx, Δy) offset. The decoder copies that displaced block forward as a *prediction*; the encoder then transmits only the **prediction residual** (true block minus prediction), which it transforms, quantizes, and entropy-codes exactly like a JPEG image. Intuitively, motion estimation turns "encode a whole moving object" into "encode a 2-vector plus a near-zero residual." The cost is asymmetric: *finding* the best motion vector means searching many candidate positions, which is why encoding is far more expensive than decoding — a theme that recurs.

### I, P, and B frames

Frames come in three flavors, a structure stable since MPEG-1 (1992):

- **I-frame (intra):** coded alone, like a JPEG. It's the random-access point and the recovery anchor, but large.
- **P-frame (predicted):** predicted from one *past* frame via motion compensation; only motion vectors + residuals are sent.
- **B-frame (bi-directional):** predicted from both a past *and* a future frame, averaging two predictions. Because real motion is often locally linear, the average of "where it came from" and "where it's going" is an excellent predictor, so B-frames are the cheapest. This requires *reordering*: the future reference must be decoded before the B-frame that depends on it, so coding order differs from display order.

A repeating I-P-B-B-P… pattern is a **Group of Pictures (GOP)**. Longer GOPs compress better but make seeking and error recovery harder.

### Transform, quantize, entropy-code, and rate-distortion

The residual pipeline mirrors image coding: a block transform (an integer DCT-like transform in H.264 onward, chosen so encoder and decoder agree bit-exactly), uniform **quantization** controlled by a quantization parameter (QP) that trades quality for size, then **entropy coding** (CABAC, context-adaptive binary arithmetic coding, in H.264/HEVC) that squeezes the quantized symbols toward their entropy.

The encoder's deepest job is **rate-distortion optimization (RDO)**. For every decision — block partition, which reference frame, which motion vector, intra vs. inter, which transform — the encoder evaluates a Lagrangian cost *J = D + λ·R*, where *D* is distortion (often sum of squared errors), *R* is the bits that choice would cost, and λ is a multiplier tied to QP. It picks the option minimizing *J*. Crucially, **the standard only defines the bitstream and the decoder**; how cleverly an encoder searches this combinatorial space is left open. That is why two compliant H.264 encoders can differ by 30%+ in quality at the same bitrate, and why "the codec" and "the encoder" are different things.

### The H.26x lineage

- **H.261 (1988)** and **MPEG-1 (1992)** / **MPEG-2 / H.262 (1994/1995)** established the macroblock + motion-compensation + DCT template. MPEG-2 is the codec of DVD and digital TV.
- **H.264 / AVC** (the workhorse), finalized May 2003 by the **Joint Video Team** of ITU-T VCEG and ISO/IEC MPEG, roughly doubled MPEG-2 efficiency through variable block sizes, multiple reference frames, quarter-pixel motion, an in-loop deblocking filter, and CABAC. It remains the most universally decodable codec on Earth.
- **H.265 / HEVC** (2013) added flexible **coding tree units** (quadtree blocks up to 64×64) and better prediction for ~50% bitrate savings over H.264 — but its rollout was crippled by a **patent-pool mess**: multiple, overlapping pools (MPEG LA, then Access Advance/HEVC Advance, plus unaffiliated holders) and confusing royalty terms. The uncertainty, not the technology, slowed adoption and directly motivated the royalty-free movement.
- **H.266 / VVC** (finalized 6 July 2020) targets another ~50% over HEVC, with tools for 4K/8K, 360° video, and screen content. Its licensing is again fragmented across Access Advance and Via-LA (formerly MPEG LA); in December 2025 Access Advance acquired Via-LA's HEVC and VVC pools, consolidating administration — though numerous essential patent holders remained outside any pool into 2026.

### The royalty-free counter-movement

Google, having bought **On2 Technologies** (Feb 2010, ~$124.6M), released **VP8** (May 2010) inside the open **WebM** container, then **VP9** (June 2013), roughly matching HEVC efficiency with no royalties. To unify the effort and gain legal weight, the **Alliance for Open Media (AOMedia)** formed September 2015 (Google, Mozilla, Cisco, Microsoft, Intel, Netflix, Amazon, and others). Its codec, **AV1**, shipped in 2018: royalty-free, roughly 30% better than HEVC, deployed first by YouTube (2018), then Netflix (2020) and Amazon (2024). **AV2** followed, with AOMedia announcing a year-end-2025 launch (the bitstream/version 1.0 finalizing into 2026), claiming ~30% over AV1 with new tools for AR/VR, multi-program split-screen, and screen content.

### Encoder asymmetry and the role of hardware

These gains are bought with brutal encoder complexity. AV1's reference encoder **libaom** can be 10–100× slower than the x265 HEVC encoder; even Intel's optimized **SVT-AV1** runs ~3–10× slower than x265 at matched quality. Both rely on *presets* (libaom's `cpu-used`, SVT-AV1's preset levels) that trade encode time for compression — reference-quality settings can take *days* for a single 4K clip. This is economically viable only because of the encode-once/decode-billions asymmetry: a streaming service amortizes one expensive encode across millions of cheap decodes.

But cheap decode requires **hardware decoders** baked into phone and TV silicon; pure-software decode drains batteries. This is AV1's structural lag — hardware AV1 decode only became common around 2022–2024, years after the spec. AV2 faces the same wall: as of mid-2026 there is excellent software progress (the dav1d-family decoders, even real-time AV2 demos in VLC), but volume hardware decode is not expected until roughly 2027–2028, with broad consumer reach later. The lesson of the whole lineage is that compression efficiency is necessary but never sufficient — licensing clarity and silicon support decide which codec actually wins.