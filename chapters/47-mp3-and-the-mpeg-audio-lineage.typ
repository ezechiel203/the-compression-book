#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= MP3 and the MPEG Audio Lineage

#epigraph[
  "The result was, at bit rates where everything else sounded quite nice, Suzanne Vega's voice sounded horrible."
][Karlheinz Brandenburg, recalling an early MP3 test]

Imagine you could fit a thousand songs in your shirt pocket. In 1990, that was pure science fiction. A CD held about seventy minutes of music and weighed eighty grams, and playing it back required bulky, skip-prone hardware. By 2001, the original iPod held a thousand songs in a device the size of a deck of cards. The technology that made that possible was not the hard drive or the battery. It was a compression algorithm. Specifically, it was MP3.

This chapter dissects exactly how MP3 works: the peculiar two-stage filterbank that carves audio into frequency bands, the psychoacoustic model that decides how many bits each band deserves, the nested quantization loops that push noise just below the edge of human perception, and the Huffman tables that squeeze the final integers. We also trace the three layers of the MPEG-1 Audio standard and the human drama (patents, courtroom raids, and one singer's inadvertent role in shaping modern music) that surrounded its birth and death.

#recap[
  Chapter 37 introduced sampling and the frequency domain: the idea that any audio signal can be broken into a sum of sine waves at different frequencies. Chapter 38 built the MDCT, the lapped transform that turns a block of samples into frequency coefficients without creating audible block-edge artifacts. Chapter 39 covered quantization (rounding coefficients to a finite set of levels) and the trade-off between quantization step size and distortion. Chapter 40 showed linear prediction for audio. Chapter 41 explained rate--distortion optimization: how a real encoder *chooses* where to spend its bit budget. Chapter 46 was the psychoacoustics ground floor: the critical bands, the masking threshold, and why some distortion is imperceptible. All of that converges here in MP3.
]

#objectives((
  "Describe the MPEG-1 Audio family (Layers I, II, III) and what each layer adds.",
  "Explain the hybrid filterbank: polyphase analysis into 32 subbands followed by MDCT.",
  "Trace data through the MP3 encoder: analysis → psychoacoustic model → quantization loops → Huffman coding → frame packing.",
  "Understand the bit reservoir and how it helps with perceptually hard passages.",
  "Appreciate the patent history and why it created the royalty-free codec movement.",
))

== The Problem: Why Generic Compression Fails on Audio

Let us start with a number. A stereo CD audio stream carries $44{,}100 "samples"/"second" times 16 "bits"/"sample" times 2 "channels" = 1{,}411{,}200 "bit/s"$, which is roughly 1.4 Mbit/s. Apply a generic lossless compressor (say, DEFLATE from Chapter 30) to a typical pop song, and you might squeeze it by 10--15%. That is useful but not transformative: 1.4 Mbit/s becomes roughly 1.2 Mbit/s. To shrink by a factor of ten (the scale needed for internet downloads in the dial-up 1990s) you cannot go lossless. You have to throw things away.

The question is: which things? Raw PCM samples are highly correlated in *time* (successive samples are similar), but that correlation is already exploited by generic coders. The deeper insight is that human ears are not measuring instruments. They cannot hear everything. Chapter 46 catalogued the blind spots: the absolute threshold of hearing, simultaneous (frequency) masking, and temporal masking. Together, those blind spots carve out an enormous budget of "distortion you are allowed to add," as long as you add it to the parts of the spectrum the ear is already ignoring.

#keyidea[
  The goal of perceptual audio coding is not to minimize mean-squared error between the original and the reconstruction. It is to minimize *audible* distortion: distortion above the masking threshold. Distortion that stays below the masking threshold is, by definition, inaudible.
]

This requires two things operating in parallel during encoding: (1) a way to separate the audio signal into frequency bands, so you can control quantization noise *per band*; and (2) a psychoacoustic model that computes how much noise each band can tolerate before it becomes audible. The MPEG-1 Audio standard packages both into one architecture, but it does so in three layers of increasing sophistication.

== The Three Layers of MPEG-1 Audio

The story begins in December 1988, when the Moving Pictures Experts Group issued a call for proposals for a unified audio coding standard. Fourteen algorithms were submitted in June 1989. The group identified two strong competitors: *MUSICAM* (Masking-pattern adapted Universal Subband Integrated Coding And Multiplexing), developed collaboratively by CCETT, IRT, and Philips and rooted in the European Digital Audio Broadcasting (DAB) project; and *ASPEC* (Adaptive Spectral Perceptual Entropy Coding), led by Karlheinz Brandenburg at Fraunhofer IIS, AT&T Bell Labs, and the University of Hannover.

Rather than picking one winner outright, the committee did something unusual: it blended both into a single standard with three "layers" of increasing complexity. All three were published as ISO/IEC 11172-3 in 1993.

#history[
  The MPEG-1 Audio committee was chaired by Leonardo Chiariglione, who also led the larger MPEG group. The decision to create three layers rather than one format was politically pragmatic: different industries had different hardware budgets and quality requirements. Layer I was designed to be *real-time encodable on cheap DSPs* of the early 1990s; Layer II was the broadcast sweet spot; Layer III was the high-quality-at-low-bitrate choice, acceptable if encoding took longer.
]

=== Layer I (MP1): The Foundation

Layer I is the simplest. The encoder splits the audio signal into *32 equal-width frequency subbands* using a polyphase filterbank (we will unpack this below). Each subband is independently quantized and transmitted. The psychoacoustic model computes a masking threshold per subband and allocates more bits to louder, more audible subbands and fewer (or zero) to masked ones. The frame size is 384 samples, making the encoder very low-latency. Target bitrate is 384 kbit/s or higher.

MP1 was used in the DCC (Digital Compact Cassette) format by Philips. It is rarely encountered today.

=== Layer II (MP2 / MUSICAM): The Broadcaster's Choice

Layer II is a refined Layer I: same 32-subband polyphase filterbank, but a larger frame of 1152 samples, finer bit allocation granularity, and a more sophisticated handling of scale factors across frames. It achieves good quality around 192--256 kbit/s.

Layer II never died. It remains the mandatory audio format in DAB digital radio (still dominant in the United Kingdom as of 2026) and was the audio track in DVD-Video alongside Dolby AC-3. Its encoder is simpler than MP3's, which makes it a practical choice in broadcast transmission chains where real-time encoding on modest hardware matters.

=== Layer III (MP3): The Revolution

Layer III is Layer II plus two major upgrades: a *modified discrete cosine transform* applied on top of the polyphase subbands (making the effective frequency resolution 18x finer), and a *psychoacoustic model* that can compute perceptual masking at that full MDCT resolution. The result is substantially better quality at low bitrates. Layer III can match Layer II's quality at roughly half the bitrate, and that was the margin that made internet audio distribution practical.

The rest of this chapter is about Layer III.

#algo(
  name: "MPEG-1 Audio (all three Layers)",
  year: "1993",
  authors: "ISO/IEC JTC 1/SC 29/WG 11 (MPEG); Brandenburg, Grill, Herre, Popp (Fraunhofer IIS); Johnston, Jayant (AT&T Bell Labs); Ziegler, Stoll, Dehery (MUSICAM team)",
  aim: "Perceptual audio coding of stereo audio at 32–448 kbit/s using a polyphase subband filterbank, psychoacoustic masking model, and entropy coding",
  complexity: "Encoder O(N log N) per frame (dominated by FFT for psychoacoustic analysis); decoder O(N) per frame",
  strengths: "Extremely widely deployed; Layer III (MP3) achieves near-CD quality at 128 kbit/s; patent-free since 2017",
  weaknesses: "Hybrid filterbank is inelegant; Layer III encoder is complex; pre-echo on transients without block switching; superseded by AAC for quality-per-bit",
  superseded: "By AAC (ISO/IEC 13818-7, 1997) for quality; by Opus (RFC 6716, 2012) for low-latency real-time applications",
)[
  The MPEG-1 Audio standard defines three interoperable codecs sharing a common frame format. All use a polyphase filterbank; Layer III adds an MDCT and a full psychoacoustic model with iterative bit allocation. The bitstream is self-contained: each frame carries a sync word, header, side information, and Huffman-coded main data. The bit reservoir mechanism allows frames to "borrow" bits from future frames for difficult passages.
]

== Stage One: The Polyphase Filterbank

Before the MDCT even enters the picture, MP3 runs every frame of audio through a *32-band polyphase filterbank*. Understanding why it exists (and why it is imperfect) requires a short detour into filter design.

#gomaths("Filterbanks and Subband Decomposition")[
  A *filterbank* is a set of bandpass filters that together cover the full frequency range $[0, f_s slash 2]$. If you pass a signal through the filterbank and then downsample each output by the number of bands, you have decomposed the signal into $M$ narrower-band streams with the same total sample rate as the original. This is called *critical sampling*. A *perfect reconstruction* filterbank lets you recombine the M streams exactly (up to a delay) to recover the original.

  The MPEG polyphase filterbank uses $M = 32$ bands. With a sampling rate of 44,100 Hz, each subband covers roughly 689 Hz. The analysis filters are designed by *cosine modulating* a single lowpass prototype filter $h[n]$ of length 512:

  $ h_k [n] = h[n] dot cos( (2k+1)(2n - 511 slash 2) pi slash (2 times 32) ) $

  where $k = 0, 1, dots, 31$ indexes the band. The key property: computing all 32 subband outputs simultaneously is equivalent to multiplying a length-512 windowed input by a 32-row matrix, which can be implemented very efficiently as a matrix-vector multiply of size $32 times 32$ after rearranging the polyphase components.

  *Numeric example:* At 44,100 Hz, each of the 32 subbands is roughly 689 Hz wide. Subband 0 covers 0–689 Hz; subband 1 covers 689–1378 Hz; ...; subband 31 covers 21,400–22,050 Hz. After downsampling by 32, each subband delivers 1378 samples/second, the same total as the original.
]

The polyphase filterbank processes 32 new input samples at a time and produces one output sample per subband per step. The name "polyphase" comes from how that single 512-tap prototype filter is reorganised. Instead of sliding one long filter over the signal and recomputing 512 multiplies for every output, you slice the filter into 32 short pieces (one per subband, each handling a different *phase* (offset) of the input stream) and run all 32 pieces at once. "Poly" (many) + "phase" (offset): many offset copies of one filter, evaluated in parallel. The cosine modulation in the box above is the bookkeeping that steers each piece to its frequency band, and the rearrangement turns what looks like 32 separate convolutions into one compact $32 times 32$ matrix multiply, the reason a 1990s DSP could run it in real time.

=== The Problem with Equal-Width Bands

There is a significant mismatch between the filterbank and human hearing. The ear's critical bands (Chapter 46) are roughly logarithmically spaced: narrow at low frequencies, wide at high frequencies. The polyphase filterbank produces 32 *equal-width* bands. That means the low-frequency region (where hearing is most sensitive and where most musical energy lives) is carved into only a few bands, while high-frequency regions that the ear lumps into single critical bands are split across many subbands.

Layer I and Layer II live with this imperfection. Layer III fixes it, but without discarding the polyphase stage, because that would break decoder compatibility. Instead, it adds another transform on top.

== Stage Two: The MDCT

Each of the 32 polyphase subbands produces a stream of samples. MP3 collects 18 consecutive samples from each subband and passes them through an *18-point MDCT*, yielding 18 frequency coefficients per subband. Across all 32 subbands, that gives $32 times 18 = 576$ MDCT coefficients per *granule* (half a frame; we return to frames shortly).

Those 576 coefficients have far finer frequency resolution than the raw 32 subbands. Crucially, they are more closely aligned with the critical-band structure of hearing, so the psychoacoustic model can assign a masking threshold to each of the 576 bins individually.

#gomaths("Why the MDCT is Critically Sampled Despite Overlap")[
  Recall from Chapter 38: the MDCT transforms a block of $2N$ input samples into $N$ frequency coefficients (half as many outputs as inputs). But consecutive blocks overlap by 50%, so every input sample participates in two transforms. The net result is one output coefficient per input sample: critically sampled. And the time-domain aliasing cancellation (TDAC) principle proved by Princen and Bradley (University of Surrey, 1986) guarantees that overlapping and adding consecutive reconstructed blocks cancels the aliasing introduced by the analysis window, giving perfect reconstruction in the lossless limit.

  In MP3: each granule takes $2 times 18 = 36$ samples from one subband and produces 18 MDCT coefficients. Consecutive granules overlap by 18 samples. Total coefficients per frame = $2 "granules" times 32 "subbands" times 18 "MDCT coefficients" = 1152$, matching the 1152 input samples per frame.
]

=== Long Blocks and Short Blocks

An 18-point MDCT has decent frequency resolution but moderate time resolution: the 36-sample window spans about 0.8 ms at 44,100 Hz. For steady tonal signals (sustained notes, vowels), this is fine; you want frequency resolution to apply masking accurately. But for *transients* (a drum hit, a plucked string attack) the 36-sample window is too long. The quantization noise from a transient gets smeared over the whole window. When that noise emerges before the transient (because the overlap extends backward in time), you hear a pre-echo: a soft "prr" or "sss" noise before the loud sound.

MP3's solution is *block switching*: when the psychoacoustic model detects a transient, the encoder switches from long blocks (18-point MDCT per subband) to *three short blocks* (3 x 6-point MDCT per subband). Short blocks give better time resolution at the cost of frequency resolution, a reasonable trade when time-domain precision matters more than spectral precision.

The transition between long and short blocks uses special *start* and *stop* window shapes that guarantee continuity at the boundaries.

#fig(
  [The MP3 encoder pipeline. A frame of 1152 PCM samples feeds both the hybrid filterbank and the FFT-based psychoacoustic model. The filterbank path (polyphase + MDCT) produces 576 coefficients per granule; the psychoacoustic model produces per-band masking thresholds. The quantization loops use both to find scale factors; Huffman coding compresses the result; the frame packer writes the bitstream.],
  cetz.canvas({
    import cetz.draw: *
    // PCM input
    rect((0, 5.5), (2.4, 6.5), fill: rgb("#e8f4f8"), stroke: 0.7pt)
    content((1.2, 6.0), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[*PCM Input*])))
    // arrow down to polyphase
    line((1.2, 5.5), (1.2, 4.8), mark: (end: ">"))
    // polyphase box
    rect((0, 3.8), (2.4, 4.8), fill: rgb("#d0e8d0"), stroke: 0.7pt)
    content((1.2, 4.3), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[32-band Polyphase])))
    // arrow down to MDCT
    line((1.2, 3.8), (1.2, 3.1), mark: (end: ">"))
    // MDCT box
    rect((0, 2.1), (2.4, 3.1), fill: rgb("#d0e8d0"), stroke: 0.7pt)
    content((1.2, 2.6), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[18-pt MDCT × 32])))
    // arrow down to quant
    line((1.2, 2.1), (1.2, 1.4), mark: (end: ">"))
    // quant box
    rect((0, 0.4), (2.4, 1.4), fill: rgb("#f0e8d0"), stroke: 0.7pt)
    content((1.2, 0.9), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[Quantization])))

    // FFT psychoacoustic path
    rect((3.2, 5.5), (5.6, 6.5), fill: rgb("#e8f4f8"), stroke: 0.7pt)
    content((4.4, 6.0), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[*PCM Input*])))
    line((4.4, 5.5), (4.4, 4.8), mark: (end: ">"))
    rect((3.2, 3.8), (5.6, 4.8), fill: rgb("#f8d0d0"), stroke: 0.7pt)
    content((4.4, 4.3), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[FFT (1024-pt)])))
    line((4.4, 3.8), (4.4, 3.1), mark: (end: ">"))
    rect((3.2, 2.1), (5.6, 3.1), fill: rgb("#f8d0d0"), stroke: 0.7pt)
    content((4.4, 2.6), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[Masking Thresholds])))
    line((4.4, 2.1), (2.4, 0.9), mark: (end: ">"))

    // Huffman box
    rect((0, -0.6), (2.4, 0.4), fill: rgb("#e8d0f0"), stroke: 0.7pt)
    content((1.2, -0.1), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[Huffman Coding])))
    line((1.2, 0.4), (1.2, -0.6), mark: (end: ">"))

    // Frame packer
    rect((0, -1.6), (2.4, -0.6), fill: rgb("#d0d0f0"), stroke: 0.7pt)
    content((1.2, -1.1), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[Frame Packer])))
    line((1.2, -1.6), (1.2, -2.3), mark: (end: ">"))
    content((1.2, -2.6), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[*MP3 Bitstream*])))
  })
)

== Stage Three: The Psychoacoustic Model

Running in parallel with the hybrid filterbank is a completely separate FFT-based analysis. The encoder takes the same 1152-sample frame and computes a 1024-point (Model 1) or 256-point (Model 2) fast Fourier transform. This FFT is not part of the bitstream. It is a tool for the encoder to understand the spectral content and compute masking thresholds.

From the FFT, the psychoacoustic model (as described in Chapter 46) computes:

1. *The absolute threshold of hearing (ATH)*: the minimum audibility floor at each frequency.
2. *The masking curves* for each tonal and noise-like masker identified in the spectrum.
3. *The simultaneous masking threshold* at each frequency: the sum of contributions from all maskers, spread according to the Bark-scale spreading function.
4. *The temporal masking*: pre- and post-masking adjustments for transient frames.

The output is a per-MDCT-band *noise masking threshold* (NMT): the maximum quantization noise power that can be added to each band without becoming audible. Any quantization noise below this threshold is perceptually free.

#keyidea[
  The psychoacoustic model does not modify the signal. It is a *measurement tool* that tells the quantizer: "In this band you can afford this much noise; in that band you must be more careful." It runs on the uncompressed input and produces a permission slip for each frequency band.
]

== Stage Four: The Quantization Loops

With 576 MDCT coefficients and 576 per-band masking thresholds in hand, the encoder must find quantization step sizes that:
- Keep the quantization noise in every band below its masking threshold (the perceptual constraint), and
- Fit the Huffman-coded result into the available number of bits for this frame (the rate constraint).

These two constraints can conflict. A very "difficult" passage might not be fully maskable within the available bits, and MP3 resolves that conflict with a *two-loop* iteration.

=== The Inner Loop: Rate Control

The inner loop finds a *global gain* parameter $G$ such that the Huffman-coded bitcount fits the available bits for this granule. The quantization formula is:

$ y_i = "round" \[ abs(x_i / (2^(G/4)))^(3/4) \] dot "sign"(x_i) $

where $x_i$ is the $i$-th MDCT coefficient and $y_i$ is the integer index. Here $"round"(dot)$ means "round to the nearest integer" (the operation MP3 specifies is technically `nint`, *nearest integer*, identical to ordinary rounding), and $"sign"(x_i)$ is $+1$ when $x_i$ is positive and $-1$ when it is negative. It strips off the sign so we can work with the magnitude $abs(x_i)$, then glues the sign back on afterwards. (The exponent $3/4$ produces a non-uniform quantizer appropriate for the approximately Laplacian distribution of MDCT coefficients.) The inner loop increments $G$ (coarser quantization → fewer bits) until the Huffman-coded output fits the bit budget.

#mathrecall[
  "Approximately Laplacian" describes the *shape* of the histogram of MDCT coefficients: a tall spike at zero with two exponentially-decaying tails, the symmetric "two-sided geometric" we met in Chapter 10. Most coefficients are near zero; a few are large. That lopsided shape is exactly what makes a non-uniform quantizer (and, later, Huffman coding) pay off.
]

#gomaths("Non-Uniform Quantization and the 3/4 Power")[
  A uniform quantizer maps $x$ to the nearest integer multiple of a step size $Delta$: $hat(x) = Delta dot "round"(x / Delta)$. The quantization error is bounded by $Delta / 2$.

  MP3 uses a *non-uniform* quantizer where the step size grows with the magnitude of $x$. Specifically, mapping $x$ to $y = "round"(abs(x)^(3/4) / Delta)$ is equivalent to using a step size that grows as $abs(x)^(1/4)$. This provides finer resolution for small coefficients (where the ear is more sensitive to errors) and coarser resolution for large coefficients. It matches the perceptual sensitivity profile better than a uniform quantizer.

  Numeric check: if $x = 64$ and $Delta = 1$, then $abs(64)^(3/4) = 64^(3/4) = (64^3)^(1/4) = 262144^(1/4) approx 22.6$, rounded to 23.
]

=== The Outer Loop: Noise Control

After the inner loop fixes the bit count, the outer loop checks whether the quantization noise in any scale-factor band exceeds its masking threshold. If any band is "noisy" (noise-to-mask ratio > 1), the encoder increases that band's *scale factor* (effectively applying finer quantization locally) and re-enters the inner loop. The outer loop repeats until all bands meet their masking thresholds or a maximum iteration count is reached.

#note[
  Chapter 46 wrote the noise-to-mask ratio (NMR) in *decibels*, where the target is NMR $< 0$ dB (noise below the mask). Here we use the equivalent *linear* ratio of noise power to mask power, where the same target reads NMR $< 1$. They are the same condition (a ratio is below 1 exactly when its decibel value is below 0), just two units for the one quantity.
]

Scale factors are logarithmically encoded (each step is approximately 2 dB) and transmitted in the side information so the decoder can reconstruct the quantization step size per band.

#pitfall[
  The two-loop system can fail to converge when the audio content is genuinely beyond what the bit budget allows at this bitrate. In that case, the encoder settles for some noise above the masking threshold. This is when audible "MP3 artifacts" (pre-echo, metallic ringing, loss of high-frequency "air") become perceptible, especially at bitrates below 96 kbit/s.
]

=== Scalefactor Bands vs. Subbands

The 576 MDCT coefficients are grouped into *scalefactor bands*, which (unlike the 32 equal-width polyphase subbands) are designed to approximate the critical bands of hearing. For long blocks there are 21 scalefactor bands; for short blocks there are 12. Each band shares one scale factor, applied uniformly to all coefficients within the band.

#aside[
  The difference between "subbands" (the 32 polyphase bands) and "scalefactor bands" (the 21 perceptual bands from the MDCT) confuses many readers of the MP3 spec. Subbands are artifacts of the polyphase stage and are not sent in the bitstream. Only the MDCT coefficients and their scale factors matter for coding. The polyphase stage exists because it was borrowed from Layer II, and removing it would have broken backward compatibility.
]

== Stage Five: Huffman Coding

Once the quantized integer indices $\{y_i\}$ are determined, they are entropy-coded using a *fixed set of Huffman tables* defined in the ISO standard. Unlike JPEG's Huffman tables (which are transmitted per-image), MP3's tables are baked into every encoder and decoder. The standard defines 32 Huffman code tables; the encoder selects the best table for each of three "regions" of the coefficient spectrum.

#gopython("Fixed vs. Adaptive Huffman Tables")[
  JPEG (Chapter 42) derives optimal Huffman tables from the image statistics and transmits them as part of the compressed file. MP3 does not. It uses predefined tables. Why? Because MP3 frames are very short (about 26 ms at 128 kbit/s), and transmitting table headers per frame would carry crippling overhead. The fixed tables are a compromise: they are near-optimal for the *typical* distribution of quantized MDCT coefficients across many real audio signals, but not optimal for any one frame.

  The coefficients are split into three regions:
  - *Big values region*: coefficients $abs(y_i) >= 2$, coded with 32 possible Huffman tables selected per region to minimize bitcount.
  - *Count1 region*: coefficients where $abs(y_i) <= 1$, coded as quadruples $(v, w, x, y)$ using one of two special tables.
  - *Zero region*: the remaining high-frequency coefficients are all zero and need no bits at all.

  The encoder signals its table choices and the boundary between regions in the *side information* field.
]

The Huffman coding gives a further lossless compression of roughly 20--30% on top of the quantization, since the distribution of quantized coefficients is far from uniform: most coefficients are zero or small.

== The Frame: Putting It All Together

An MP3 bitstream is a sequence of *frames*, each covering 1152 PCM samples. At a sampling rate of 44,100 Hz, one frame covers $1152 / 44100 approx 26$ ms. Each frame contains:

1. *Sync word* (11 bits of all-ones): the decoder scans for this to lock onto the stream.
2. *Header* (21 remaining bits): MPEG version, layer, bitrate index, sampling rate, stereo mode, copyright flag.
3. *CRC* (16 bits, optional): protects the side information against bit errors.
4. *Side information* (17 bytes for mono, 32 bytes for stereo): the main data begin (MDB) pointer, scale factor selection, Huffman table selections, region boundaries, and granule-level gain parameters.
5. *Main data*: the Huffman-coded coefficient data, though not necessarily for *this* frame (see the bit reservoir below).
6. *Ancillary data*: optional user-defined bytes, used for ID3 tags and other metadata.

One key subtlety: the side information and main data are *not* the same size even though the header specifies a fixed bitrate. The *main data begin* pointer in the side information tells the decoder how far back in the bitstream to look for the actual Huffman data. It may start inside a previous frame's payload. This is the bit reservoir.

=== The Bit Reservoir

At a fixed bitrate of 128 kbit/s, every 26-ms frame gets exactly 418 bytes of payload. A quiet passage of music (low amplitude, easy to quantize) might need only 200 bytes for fully perceptual quality. The encoder saves the spare 218 bytes in a *bit reservoir* (a buffer, not part of the bitstream directly). When a difficult passage arrives (a cymbal crash, a complex chord) the encoder can draw from the reservoir and use 600 bytes for that frame, transmitting the surplus bits inside the next frame's payload with the MDB pointer pointing backwards.

#keyidea[
  The bit reservoir smooths out the variable-difficulty nature of music: it lets the encoder be generous when the ear most needs it, without exceeding the average bitrate. It behaves like VBR within the constraints of a fixed declared bitrate.
]

The maximum reservoir size is 511 bytes for MPEG-1 (2^9 - 1, since the MDB pointer is 9 bits in the side information). This means only about one second of extra "credit" is available at 128 kbit/s, a modest buffer but enough for most musical passages.

== Worked Example: Encoding One Granule

Let us walk through the encoding of a single granule (576 MDCT coefficients) at 128 kbit/s mono.

*Available bits:* a frame holds 1152 samples = 2 granules, so at 44,100 Hz there are $44100 \/ 1152 approx 38.3$ frames per second. At 128 kbit/s each frame gets $128{,}000 \/ 38.3 approx 3343$ bits $approx 418$ bytes. Split across the two granules, that is $approx 1672$ bits per granule. Subtracting per-granule side-information overhead (~68 bits) leaves roughly 1604 bits for the granule's main (Huffman-coded) data, the budget the inner loop must hit.

*Coefficient distribution (typical)* For a vocal + guitar passage at medium loudness:
- Scalefactor band 0 (0--100 Hz): 6 coefficients, average magnitude 800 → large, need fine quantization
- Scalefactor bands 1--8 (100--2000 Hz): strongest signal, masking threshold moderate
- Scalefactor bands 9--17 (2000--11025 Hz): moderate signal, strong masking from lower frequencies
- Scalefactor bands 18--20 (11025--22050 Hz): very weak signal, strong masking → can use very coarse quantization or zero

*Inner loop iteration:* Global gain G starts high (fine quantization → many bits). After Huffman coding, the output is 2800 bits, too many. G is increased by 4. New estimate: 2100 bits. Increase by 2: 1850 bits. Increase by 1: 1590 bits. Fits. Four iterations.

*Outer loop check:* In band 3 (400--600 Hz), noise-to-mask ratio is 1.4, slightly above threshold. Scale factor for band 3 is increased by one step, increasing its local resolution. Re-enter inner loop: now 1640 bits. Outer loop recheck: all bands below masking threshold. Done.

*Result:* 576 coefficients encoded in 1640 bits ≈ 205 bytes, well within budget. The encoder deposits the spare bits in the reservoir.

== Stereo Coding: Joint Stereo and M/S

For stereo audio, MP3 offers several stereo coding modes:

- *Simple stereo*: left and right channels encoded independently. No gain.
- *Joint stereo - M/S mode*: the encoder transmits the sum (Mid = L+R) and difference (Side = L−R) channels instead of L and R. For typical music, the Side channel has much lower energy than Mid, so it can be quantized more coarsely, saving bits.

#mathrecall[
  Chapter 46 introduced Mid--Side stereo with the *averaging* convention $M = (L+R)\/2$, $S = (L-R)\/2$. MP3's bitstream uses the *energy-preserving* convention $M = (L+R)\/sqrt(2)$, $S = (L-R)\/sqrt(2)$ instead. Dividing by $sqrt(2)$ rather than $2$ is what makes the total energy identical before and after the transform (we verify this below); the two conventions describe the same idea, just scaled differently.
]

To talk precisely about "how much energy" a channel carries, we need one small piece of vocabulary: the *root-mean-square*.

#gomaths("Root-Mean-Square (RMS)")[
  Given a list of numbers $x_1, x_2, dots, x_n$ (for us, the samples of an audio channel) its *root-mean-square* is exactly what the three words say, read right to left:

  $ "RMS"(x) = sqrt( underbrace((x_1^2 + x_2^2 + dots + x_n^2) / n, "mean of the squares") ) = sqrt( 1/n sum_(i=1)^n x_i^2 ) $

  *Square* every value (so positives and negatives both count, and big values count more), take the *mean* of those squares, then the square *root* to return to the original units. The result is a single positive number measuring the "typical magnitude" of the list. For an audio signal, $"RMS"^2$ is proportional to its average power, so RMS is the natural way to compare how loud two channels are.

  *Tiny example:* for $x = (3, -4)$, RMS $= sqrt((9 + 16)\/2) = sqrt(12.5) approx 3.54$, between the two magnitudes 3 and 4, as a "typical size" should be. (If every value were the same constant $c$, the RMS would be exactly $abs(c)$.)

  RMS is close kin to the *standard deviation* from Chapter 10: when a list already averages to zero (as an audio waveform does) the two are the same number. RMS just drops the "subtract the mean first" step.
]
- *Joint stereo - Intensity stereo*: at high frequencies (above ~2 kHz), the encoder transmits only the combined energy and a stereo panning angle. The ear loses the ability to localize high-frequency sounds binaurally, so intensity stereo is perceptually transparent in that range. It saves the most bits but can sound "phasey" if the crossover point is chosen wrong.

Good encoders (LAME in particular) switch between these modes granule by granule depending on the content.

#gopython("Computing the M/S Gain")[
  The simplest way to see why M/S stereo helps is to look at the variances of the two channels.

  ```python
  import math

  def ms_gain(left: list[float], right: list[float]) -> tuple[float, float]:
      """Return RMS energy of Mid and Side channels.

      M/S stereo sends (L+R)/sqrt(2) and (L-R)/sqrt(2) so energy is preserved.
      If |side_rms| << |mid_rms|, the side channel can be coarsely quantized.
      """
      mid  = [(l + r) / math.sqrt(2) for l, r in zip(left, right)]
      side = [(l - r) / math.sqrt(2) for l, r in zip(left, right)]
      rms = lambda v: math.sqrt(sum(x*x for x in v) / len(v))
      return rms(mid), rms(side)

  # Simulated stereo signal with weak difference
  import random
  random.seed(42)
  L = [random.gauss(0, 1) for _ in range(576)]
  R = [l + random.gauss(0, 0.1) for l in L]  # right ≈ left + tiny noise

  mid_e, side_e = ms_gain(L, R)
  print(f"Mid RMS:  {mid_e:.3f}")
  print(f"Side RMS: {side_e:.3f}")
  print(f"Side is {side_e/mid_e*100:.1f}% of Mid - save bits on Side!")
  # Output: Mid RMS: ~1.00, Side RMS: ~0.071 - Side is ~7% of Mid
  ```

  When the Side channel is 7% of the Mid, it needs roughly $log_2(1/0.07) approx 3.8$ fewer bits per coefficient to achieve the same relative noise floor, a significant saving.
]

== The MP3 Encoder Landscape: Where Quality Actually Comes From

The ISO standard specifies the *bitstream format and the decoder*, not the encoder. This means the same MP3 file can be produced by encoders of wildly different quality. The reference encoder included with the standard was mediocre. What made MP3 actually sound good was the work of independent encoder developers.

The *Fraunhofer mp3enc* commercial encoder was the gold standard for years. The *LAME* (LAME Ain't an MP3 Encoder) project, begun by Mike Cheng in 1998, reverse-engineered and improved the psychoacoustic model, added proper VBR (variable bitrate) with target quality settings, and introduced the GAPLESS extension that makes gapless album playback possible without a separate framing standard. LAME became, and arguably remains, the best-quality open-source MP3 encoder, and it is what most music software uses under the hood today.

#history[
  LAME's name is a recursive acronym in the tradition of GNU (GNU's Not Unix) and WINE (WINE Is Not an Emulator). Mike Cheng originally released it in 1998 as a set of patches to a reference encoder; Gabriel Bouvigne and Mark Taylor rewrote large portions. The VBR quality settings (`-V 0` through `-V 9`) that LAME introduced became the defacto standard for archival-quality MP3 encoding: `-V 2` (roughly 190 kbit/s average) is widely considered transparent to most listeners on most content.
]

#algo(
  name: "LAME (LAME Ain't an MP3 Encoder)",
  year: "1998 (initial release); ongoing",
  authors: "Mike Cheng (founder); Gabriel Bouvigne, Mark Taylor, and open-source contributors",
  aim: "High-quality open-source MP3 encoder implementing ISO/IEC 11172-3 Layer III with improved psychoacoustic model, VBR mode, gapless encoding, and ABR (average bitrate) mode",
  complexity: "Encoder O(N log N) per frame; faster than real-time on any hardware since ~2005",
  strengths: "Best or equal-to-best quality among free encoders; mature VBR mode (-V 0 to -V 9) provides quality-per-bit superior to CBR; gapless album playback via INFO header; widely tested and trusted",
  weaknesses: "Encoder only (no decoder needed, every MP3 decoder is compatible); the psychoacoustic model, while excellent, is still the 1993-era two-loop design; cannot improve on the fundamental MP3 format limitations",
  superseded: "For new applications, AAC (Chapter 48) or Opus (Chapter 49) give better quality per bit; LAME remains the reference for archival MP3 encoding",
)[
  LAME implements the full ISO 11172-3 Layer III bitstream with numerous extensions: the Xing/INFO header for VBR gapless playback, noise shaping improvements, pre-echo detection, and automatic block switching. Its `-V 2` setting (targeting ~190 kbit/s average) is widely used as the archival gold standard when MP3 compatibility is required.
]

== The Birth Story: Suzanne Vega and the Sound of One Voice

No account of MP3 would be complete without mentioning Suzanne Vega's a cappella recording of "Tom's Diner." In the early 1990s, Karlheinz Brandenburg and his colleagues at Fraunhofer were refining the psychoacoustic model using a battery of test tracks: opera, orchestral music, rock. Brandenburg read a hi-fi magazine article noting that the acapella vocal recording was used to test loudspeakers, and decided to add it to the test suite.

The result was alarming. At bitrates where everything else sounded "quite nice," Vega's voice sounded terrible: harsh, with an audible digital rattle. A lone female voice, with no other instruments to mask its artifacts, exposed every weakness in the psychoacoustic model. The team spent years refining the masking thresholds, the block-switching logic, and the quantization control loops with this one track as their torture test. When it finally sounded right, they felt confident they were done.

This earned Suzanne Vega the informal title "The Mother of the MP3" among audio engineers, a title Brandenburg himself has used, though he is careful to note the full story is more legend than fact. What is unambiguous is that a single musical test case drove years of engineering refinement, a reminder that the hardest cases matter most.

== The Patents: Drama, Money, and the Royalty-Free Rebellion

The technical success of MP3 was almost immediately overshadowed by its legal story. In September 1998, the Fraunhofer Institute sent letters to several MP3 software developers stating that a license was required to "distribute and/or sell decoders and/or encoders." Fraunhofer and Thomson Multimedia (later Technicolor) jointly administered the patent portfolio; royalties ran from \$0.75 to several dollars per encoder/decoder unit, plus a percentage of revenue for software.

The timing was no coincidence: by 1998, MP3 had become a genuine internet phenomenon. Winamp (released by Nullsoft in 1997) had made MP3 playback on Windows trivially easy; millions of users were ripping CDs and sharing files. The licensing letter was Fraunhofer's attempt to monetize that success.

#aside[
  The Fraunhofer patents list runs to dozens of entries. The key claims covered the psychoacoustic model, the joint stereo mode, the Huffman table structure, and aspects of the bit reservoir. Not all were universally accepted as valid. Sisvel, an Italian patent licensing firm, held additional patents and pursued an even more aggressive enforcement strategy, including seizing MP3 players from SanDisk's booth at the IFA trade show in Berlin in September 2006 after winning an injunction in German court.
]

The royalty demand had an enormous side effect: it made developers of new codecs determined to be *patent-free from the start*. The Xiph.Org Foundation was founded in response; Chris Montgomery released the first version of Ogg Vorbis (the first serious royalty-free alternative) in 2000. The entire open codec movement (Vorbis, Theora, FLAC, Opus, WebM, AV1) traces its philosophical lineage to the 1998 Fraunhofer letter.

The US patents expired gradually: the Sisvel portfolio largely expired by 2015. Three remaining Fraunhofer patents expired in February 2017 and April 2017. On April 23, 2017, Fraunhofer formally terminated its licensing program. MP3 was finally free, though by then it had been culturally eclipsed by streaming services and its successors.

#block(width: 100%, breakable: true, above: 12pt, below: 12pt)[
  #text(weight: "bold", fill: rgb("#783f04"), size: 9.5pt)[SCOREBOARD: Compression of a 3-minute stereo pop song (≈ 31.7 MB uncompressed PCM at 44.1 kHz / 16-bit stereo), illustrating the MP3 bitrate ladder.]
  #v(3pt)
  #text(size: 8pt)[
    #table(
      columns: (1fr, auto, auto, auto, 1fr),
      inset: (x: 5pt, y: 3.5pt),
      align: (left, right, right, right, left),
      fill: (_, row) => if row == 0 { rgb("#0b5394").lighten(85%) } else { none },
      [*Mode*], [*Bitrate*], [*Size*], [*Ratio*], [*Notes*],
      [Uncompressed PCM], [1411 kbit/s], [31.7 MB], [1.0×], [CD-quality baseline],
      [MP3 Layer III 320 kbit/s CBR], [320 kbit/s], [7.2 MB], [4.4×], [Transparent to all listeners],
      [MP3 Layer III 128 kbit/s CBR], [128 kbit/s], [2.9 MB], [11.0×], [Near-CD; occasional artifacts],
      [MP3 Layer III 64 kbit/s CBR], [64 kbit/s], [1.4 MB], [22.1×], [Acceptable for speech; music degraded],
      [MP3 LAME VBR -V2 (~190 kbit/s)], [~190 kbit/s], [4.3 MB], [7.4×], [Recommended archival quality],
    )
  ]
]

== The Cultural Detonation

The technology was complete by 1993. The explosion came later, driven not by audio engineers but by teenagers and college students.

*1997:* Nullsoft releases Winamp 1.0, a freeware MP3 player for Windows. Within a year it has 15 million users, at a time when Windows 95 was the dominant operating system. The interface was a skeuomorphic silver player with a spectrum visualizer, and it was the first mass-market software that made digital music feel *cool*.

*1999:* Sean Fanning, a 19-year-old at Northeastern University, launches Napster, a peer-to-peer file-sharing service that makes finding and downloading MP3s effortless. Within two years, Napster has 80 million registered users. The music industry panics. Metallica and Dr. Dre sue Napster for copyright infringement; the RIAA sues Napster itself. The service is shut down in July 2001 following a court order, but the damage (or liberation, depending on your perspective) is done: listeners have learned to expect music as bits, not plastic.

*2001:* Apple releases the first iPod on October 23, 2001. The marketing slogan was "1,000 songs in your pocket." It could have been "1,000 MP3s in your pocket," but Apple was wise enough to hide the technology. The iPod becomes the fastest-growing consumer electronics product in history.

*2004--present:* iTunes, then Spotify, then YouTube, then Apple Music, then Amazon Music. Streaming replaces downloads, and the MP3 file (which you owned) gives way to a licensed stream (which you rent). Yet the MP3 format persists: billions of files exist in the wild and will continue to play back for as long as compatible decoders exist.

#misconception[
  "MP3 sounds worse than lossless because it throws away information."
][
  At high bitrates (≥ 192 kbit/s with a good encoder), MP3 is *perceptually transparent* to the vast majority of listeners on typical audio equipment. Controlled double-blind ABX tests consistently fail to distinguish high-bitrate MP3 from the uncompressed original. "Throwing away information" is only harmful if you throw away information the ear would have used. The psychoacoustic model is specifically designed to discard only the information the ear cannot hear.
]

== The Technical Legacy: What MP3 Bequeathed

The MPEG-1 Audio Layer III architecture left deep marks on every perceptual codec that followed.

*The MDCT became universal.* Every major lossy audio codec after MP3 (AAC (Chapter 48), Vorbis, AC-3 (Dolby Digital), WMA, Opus) is based on the MDCT. The polyphase stage was not copied: AAC replaced it with a pure 1024-point MDCT, giving smoother frequency resolution and eliminating the equal-bandwidth mismatch.

*The psychoacoustic model became the blueprint.* The two-model approach (Model 1 for low-complexity applications, Model 2 for high-quality) and the concepts of tonal/noise masker detection, spreading function, and noise-to-mask ratio are directly inherited by every codec in the MPEG family.

*The bit reservoir idea lives on.* The principle of smoothing bitrate variability by borrowing from nearby frames appears in AAC, AC-3, and virtually every CBR codec.

*The patent problem created the open ecosystem.* Without the 1998 Fraunhofer licensing letter, there would likely be no Xiph Foundation, no Ogg Vorbis, no FLAC, and possibly no Opus. The entire royalty-free codec movement is a direct political consequence of MP3's commercial success.

#checkpoint[
  An MP3 encoder has computed 576 MDCT coefficients for a granule. After the inner loop finds global gain G = 210, the output Huffman-coded bitcount is 1580 bits, within the budget of 1600. The outer loop finds that scalefactor band 7 (covering roughly 1300--1800 Hz) has a noise-to-mask ratio of 1.8, meaning the quantization noise is 80% above the masking threshold. What happens next?
][
  The outer loop increases the scale factor for band 7 by one step (approximately 2 dB of additional resolution in that band). This effectively reduces the quantization step size for band 7, producing smaller noise in that band but requiring more bits to code those coefficients. The encoder re-enters the inner loop to find a new global gain G that fits the (now slightly larger) bitcount within the available bits. The process repeats until band 7's noise-to-mask ratio falls below 1.0, or until a maximum iteration count is reached.
]

== Comparing the Three Layers

#fig(
  [Comparison of MPEG-1 Audio Layer complexity vs. coding efficiency. Layer I is simplest but needs the most bits. Layer III is the most complex but achieves the best quality at low bitrates.],
  cetz.canvas({
    import cetz.draw: *
    // Axes
    line((0.5, 0.5), (6.0, 0.5), mark: (end: ">"))
    line((0.5, 0.5), (0.5, 4.5), mark: (end: ">"))
    content((3.25, 0.0), box(width: 4.0cm, inset: 1pt, align(center, text(size: 8pt)[Encoder Complexity →])))
    content((0.0, 2.5), angle: 90deg, box(width: 3.5cm, inset: 1pt, align(center, text(size: 8pt)[← Quality at low bitrate])))

    // Layer I
    circle((1.5, 1.2), radius: 0.55, fill: rgb("#d0e8d0"), stroke: 0.7pt)
    content((1.5, 1.2), box(width: 0.9cm, inset: 1pt, align(center, text(size: 8pt)[*L I*])))
    content((1.5, 0.55), box(width: 1.2cm, inset: 1pt, align(center, text(size: 7pt)[384 kb/s])))

    // Layer II
    circle((3.0, 2.5), radius: 0.55, fill: rgb("#f0e8d0"), stroke: 0.7pt)
    content((3.0, 2.5), box(width: 0.9cm, inset: 1pt, align(center, text(size: 8pt)[*L II*])))
    content((3.0, 1.85), box(width: 1.2cm, inset: 1pt, align(center, text(size: 7pt)[192 kb/s])))

    // Layer III
    circle((5.0, 4.0), radius: 0.55, fill: rgb("#f8d0d0"), stroke: 0.7pt)
    content((5.0, 4.0), box(width: 0.9cm, inset: 1pt, align(center, text(size: 8pt)[*L III*])))
    content((5.0, 3.35), box(width: 1.2cm, inset: 1pt, align(center, text(size: 7pt)[128 kb/s])))

    // Arrow indicating direction
    line((1.9, 1.55), (4.45, 3.65), stroke: (dash: "dashed"), mark: (end: ">"))
  })
)

#takeaways((
  "MPEG-1 Audio defines three layers; Layer III (MP3) adds an MDCT on top of the polyphase filterbank, giving 576 frequency coefficients and perceptual-band resolution.",
  "The hybrid filterbank (32-band polyphase followed by 18-point MDCT) is an engineering compromise: it preserves compatibility with Layer II decoders while achieving the fine frequency resolution needed for psychoacoustic masking.",
  "The psychoacoustic model runs a separate 1024-point FFT on each frame to compute per-band masking thresholds; the quantization loops iterate until all bands meet their thresholds within the bit budget.",
  "The bit reservoir lets difficult frames borrow bits from easier frames, providing effective VBR behavior within a CBR stream.",
  "MP3 Huffman coding uses predefined fixed tables; the encoder selects the best table per region of the coefficient spectrum.",
  "The 1998 Fraunhofer patent licensing campaign directly triggered the royalty-free codec movement (Vorbis, FLAC, Opus, AV1).",
  "MP3's last relevant patents expired in April 2017; the format is now fully free for any use.",
))

== Exercises

#exercise("47.1", 1)[
  A CD plays stereo audio at 44,100 samples/second, 16 bits per sample, 2 channels. An MP3 file of the same music at 128 kbit/s is 2.9 MB for a 3-minute song.
  (a) Compute the uncompressed size of the 3-minute audio in megabytes.
  (b) Compute the compression ratio.
  (c) How many bits does MP3 use per audio sample (per channel)?
]

#solution("47.1")[
  (a) $44100 "samples/s" times 60 "s/min" times 3 "min" times 2 "ch" times 16 "bits" = 254{,}016{,}000 "bits" = 31.75 "MB"$.

  (b) $31.75 "MB" / 2.9 "MB" approx 10.9:1$.

  (c) Total samples in 3 min per channel: $44100 times 180 = 7{,}938{,}000$. Total bits in MP3: $2.9 times 10^6 times 8 = 23{,}200{,}000$. Per channel: $23{,}200{,}000 / (2 times 7{,}938{,}000) approx 1.46$ bits/sample. Compare to 16 bits/sample uncompressed, a factor of ~11 reduction.
]

#exercise("47.2", 1)[
  MP3 uses a 32-band polyphase filterbank that divides 0--22,050 Hz (half the 44,100 Hz sample rate) into 32 equal bands.
  (a) How wide is each subband in Hz?
  (b) The ear's first critical band (Bark band 1) covers roughly 0--100 Hz. How many polyphase subbands fall entirely within this band?
  (c) Why is this a problem for the psychoacoustic model?
]

#solution("47.2")[
  (a) $22050 / 32 approx 689$ Hz per subband.

  (b) The band 0--100 Hz is only $100 / 689 approx 0.15$ subbands wide, less than one complete subband. Only a fraction of subband 0 covers the lowest critical band.

  (c) Because the psychoacoustic model in Layers I and II can only assign bits at subband granularity, it cannot separately control quantization noise for different critical bands within the same subband. The MDCT in Layer III partially fixes this by further subdividing each subband into 18 frequency bins, giving finer control over masking thresholds within each Bark band.
]

#exercise("47.3", 2)[
  The MP3 bit reservoir uses a 9-bit main data begin (MDB) pointer in the side information.
  (a) What is the maximum number of bytes the reservoir can hold?
  (b) At 128 kbit/s with 26 ms frames, approximately how many frames' worth of "credit" does this represent?
  (c) For what kind of audio content would the reservoir most benefit the listener?
]

#solution("47.3")[
  (a) The MDB pointer is 9 bits, so it can point up to $2^9 - 1 = 511$ bytes into the past.

  (b) At 128 kbit/s: bytes per frame $= 128000 / 8 / (44100/1152) approx 418$ bytes. Reservoir of 511 bytes is approximately $511 / 418 approx 1.2$ frames' worth of credit.

  (c) The reservoir is most valuable for audio with highly variable difficulty (e.g., an orchestral piece where a quiet passage (easy to encode) precedes a loud, complex fortissimo (hard to encode)). The encoder saves bits during the quiet and spends them on the loud section, reducing perceptible artifacts at the most critical moments.
]

#exercise("47.4", 2)[
  Explain in your own words why MP3 uses a non-uniform quantizer with a $3/4$ power law (i.e., $y = "round"(abs(x)^(0.75) / Delta)$) rather than a simple uniform quantizer. What property of MDCT coefficient distributions motivates this choice? How does it relate to perceptual quality?
]

#solution("47.4")[
  MDCT coefficients have a distribution that is roughly Laplacian (many values near zero, exponentially fewer large values). A uniform quantizer applies the same step size $Delta$ everywhere, which wastes precision on large coefficients (where the ear tolerates larger absolute errors) and may be too coarse for small coefficients. The $3/4$ power non-uniformity makes the effective step size grow with magnitude: small coefficients get finer resolution, large coefficients get coarser resolution. This matches the perceptual sensitivity profile, since the ear's detection threshold for a tone scales roughly with its surrounding noise level (Weber's law applied to masking). The practical result is lower perceived noise for the same average bitrate.
]

#exercise("47.5", 2)[
  M/S (Mid-Side) stereo coding can save bits when the left and right channels are similar. Write a short Python 3.14 function `ms_coding_gain(L: list[float], R: list[float]) -> float` that returns the ratio of the *total RMS energy* in the original L/R channels to the *total RMS energy* in the M/S channels. (They should be equal if you use the normalized formulas $M = (L+R)/sqrt(2)$ and $S = (L-R)/sqrt(2)$.) Then explain: even though total energy is the same, how does M/S stereo reduce the bitrate?
]

#solution("47.5")[
  ```python
  import math

  def ms_coding_gain(L: list[float], R: list[float]) -> float:
      """Total RMS ratio LR->MS (should be 1.0 - energy preserved).

      The gain comes from the *distribution*, not total energy.
      """
      def rms(v: list[float]) -> float:
          return math.sqrt(sum(x * x for x in v) / len(v))

      mid  = [(l + r) / math.sqrt(2) for l, r in zip(L, R)]
      side = [(l - r) / math.sqrt(2) for l, r in zip(L, R)]
      lr_rms  = math.sqrt(rms(L)**2 + rms(R)**2)
      ms_rms  = math.sqrt(rms(mid)**2 + rms(side)**2)
      return lr_rms / ms_rms  # Should be ~1.0

  # Test with highly correlated stereo
  L = [1.0] * 576
  R = [0.9] * 576
  print(ms_coding_gain(L, R))  # ≈ 1.0 - energy conserved

  # But the Side channel RMS is tiny:
  # Mid RMS ≈ (1.0 + 0.9)/sqrt(2) ≈ 1.34
  # Side RMS ≈ (1.0 - 0.9)/sqrt(2) ≈ 0.071
  # Side needs far fewer bits to represent at the same SNR.
  ```

  The total energy is conserved ($"RMS"^2_M + "RMS"^2_S = "RMS"^2_L + "RMS"^2_R$). The saving comes from the *imbalance*: when L ≈ R, the Side channel is nearly zero and can be coded at very coarse quantization (or even zeroed out above certain frequencies) with imperceptible impact. The encoder allocates the saved bits to the Mid channel, improving overall perceived quality.
]

#exercise("47.6", 3)[
  The MPEG psychoacoustic Model 1 represents each masker (tonal or noise) as spreading energy across neighboring Bark bands according to a spreading function $S(Delta z)$ in dB, where $Delta z$ is the distance in Bark. A simplified form is:

  $ S(Delta z) = cases(17 Delta z - 0.4 P - 6 & "if" Delta z < 0, (-17 + 0.15 P) Delta z & "if" 0 <= Delta z <= 3, -75 Delta z + 0.5 Delta z^2 & "if" Delta z > 3) $

  where $P$ is the masker power in dB SPL. A masker at Bark band 4 ($z = 4$) with $P = 80$ dB SPL spreads into bands at $z = 1, 2, 3, 5, 6, 7$.

  (a) Compute $S(Delta z)$ for the four *lower-frequency* bands ($Delta z = -3, -2, -1$) and the three *upper-frequency* bands ($Delta z = 1, 2, 3$).

  (b) Which side (lower or upper frequency) has more spreading, and why does this asymmetry make sense perceptually?

  (c) Why does the spreading function depend on $P$ (masker power) on the lower-frequency side but not the upper-frequency side?
]

#solution("47.6")[
  (a) Lower-frequency side ($Delta z < 0$), with $P = 80$:
  - $Delta z = -1$: $S = 17(-1) - 0.4(80) - 6 = -17 - 32 - 6 = -55$ dB
  - $Delta z = -2$: $S = 17(-2) - 32 - 6 = -34 - 38 = -72$ dB
  - $Delta z = -3$: $S = 17(-3) - 32 - 6 = -51 - 38 = -89$ dB

  Upper-frequency side ($0 <= Delta z <= 3$), with $P = 80$:
  - $Delta z = 1$: $S = (-17 + 0.15 times 80)(1) = (-17 + 12)(1) = -5$ dB
  - $Delta z = 2$: $S = (-5)(2) = -10$ dB
  - $Delta z = 3$: $S = (-5)(3) = -15$ dB

  (b) The upper-frequency (upward) spreading is much stronger: −5 dB at one Bark above vs. −55 dB at one Bark below. This matches auditory physiology: the basilar membrane resonates at characteristic frequencies with a sharper cutoff on the low-frequency side and a broader, gentler roll-off on the high-frequency side. A loud low tone effectively masks nearby higher frequencies far more than it masks nearby lower ones.

  (c) On the lower-frequency side, the masking effect is power-dependent because at very high masker power the upward slope of the lower tail of the excitation pattern becomes relevant. On the upper-frequency side the slope is dominated by the characteristic frequency response of the basilar membrane, which is largely fixed in shape regardless of level (at least in this simplified model). More complete models (like those in AAC) include level dependence on both sides.
]

== Further Reading

- #link("https://www.aes.org/e-lib/browse.cfm?elib=8079")[Brandenburg, K. (1999). *MP3 and AAC Explained.* AES 17th International Conference.] The primary technical overview by the algorithm's chief architect, accessible and authoritative.

- #link("https://ccrma.stanford.edu/~jos/sasp/MPEG_Layer_III_Filter.html")[Smith, J. O. (Stanford CCRMA). *MPEG Layer III Filter Bank.* Spectral Audio Signal Processing online book.] A mathematically precise treatment of the polyphase filterbank and its relationship to the MDCT.

- #link("https://reynal.etis-lab.fr/docs/audio-sia/tp/tp_mp3/mp3_theory.pdf")[Raissi, R. (2002). *The Theory Behind MP3.*] A clear technical exposition of the complete encoding pipeline, including the quantization loops.

- #link("https://www.iis.fraunhofer.de/en/magazin/panorama/2025/30-years-of-mp3.html")[Fraunhofer IIS. (2025). *30 Years of .mp3: Three Letters That Changed the World.*] Fraunhofer's own retrospective marking the 30th anniversary of the ".mp3" file extension name.

- #link("https://wiki.hydrogenaudio.org/index.php?title=MP3")[Hydrogenaudio Knowledgebase: MP3.] The audiophile community's reference, with extensive coverage of encoder comparisons, ABX testing, and psychoacoustic subtleties.

- #link("https://us.kef.com/blogs/news/tom-s-diner-and-the-birth-of-the-mp3")[KEF. *Tom's Diner and the Birth of the MP3.*] A concise retelling of the Suzanne Vega anecdote, with context from Brandenburg himself.

- #link("https://ieeexplore.ieee.org/document/475398/")[Stoll, G. et al. (1995). *MPEG Audio Layer II: A generic coding standard for two and multichannel sound for DVB, DAB and computer multimedia.* IET Conference.] Technical background on the Layer II standard that underpins broadcasting to this day.

#bridge[
  MP3 proved the concept: perceptual audio coding works, and at 128 kbit/s the ear simply cannot hear what is missing. But the community immediately asked a harder question: can we do better? The answer is yes, and the next chapter shows how. Chapter 48 dissects AAC (Advanced Audio Coding), which replaced the awkward polyphase--MDCT hybrid with a pure 1024-point MDCT, added Temporal Noise Shaping to handle transients more gracefully, introduced Spectral Band Replication (SBR) to reconstruct high frequencies from fewer bits, and achieved MP3-equivalent quality at roughly 96 kbit/s. We will also meet Ogg Vorbis, the open, patent-free codec born directly from the patent anger of 1998, and see how the royalty-free movement that MP3's patents accidentally created would ultimately produce codecs better than anything Fraunhofer ever built.
]
