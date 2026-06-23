## Audio Compression: Psychoacoustics, MP3, AAC, Opus, FLAC

Audio compression splits cleanly into two philosophies. **Lossless** coding (FLAC) reconstructs the original PCM samples bit-for-bit and typically only halves the file. **Lossy** coding (MP3, AAC, Opus) throws away information and reaches ratios of 10:1 or more — but it is *perceptual*: it discards precisely the sounds your ear cannot hear, so the loss is, by design, inaudible. Understanding lossy audio therefore means understanding the ear before the math.

### Psychoacoustics: exploiting the limits of hearing

A raw audio signal is a stream of amplitude samples — CD audio is 44,100 samples/second at 16 bits/sample/channel, about 1.4 Mbit/s for stereo. Generic entropy coding barely dents this, because the samples are not very redundant in the Shannon sense. The breakthrough was to redefine the goal: don't preserve the *signal*, preserve the *perception*. The human auditory system has well-measured blind spots, and three matter most.

**The absolute threshold of hearing (ATH).** At each frequency there is a sound-pressure level below which a tone is simply inaudible. The threshold is lowest (most sensitive) around 2–4 kHz and rises steeply at low and high frequencies. Any spectral energy below the ATH can be discarded outright.

**Frequency (simultaneous) masking.** A loud tone raises the audibility threshold for nearby frequencies. A strong 1 kHz tone makes a faint 1.1 kHz tone vanish entirely. The masking curve is asymmetric and follows the ear's **critical bands** — frequency groups (the Bark scale) within which the cochlea integrates energy. This is the workhorse: encode the loud component faithfully, and you can crudely quantize or drop everything it masks.

**Temporal masking.** Masking also extends in time. A loud transient masks quiet sounds for ~5 ms before it (pre-masking) and 50–200 ms after (post-masking). This lets coders quantize coarsely around loud onsets.

A **psychoacoustic model** turns these effects into a per-band *masking threshold*: the quantization noise budget that will stay inaudible. The encoder then allocates bits to push quantization error just under that threshold everywhere. This is rate–distortion optimization where "distortion" is measured in perceptual units, not mean-squared error.

### The MDCT: the transform that makes it possible

To apply masking you must work in the frequency domain. The tool of choice is the **Modified Discrete Cosine Transform (MDCT)**, built on the time-domain aliasing cancellation principle of John Princen and Alan Bradley (University of Surrey, 1986–1987). The MDCT is a *lapped* transform: consecutive blocks overlap by 50%, yet it is **critically sampled** — N input samples per block still yield only N/2 coefficients, with no expansion. The overlap-add at reconstruction exactly cancels the aliasing introduced by the windowing, giving perfect reconstruction in the lossless limit. The overlap is what suppresses *blocking artifacts* (audible discontinuities at frame edges), the audio analogue of JPEG's block boundaries. Nearly every modern lossy codec — MP3 (partly), AAC, Vorbis, Opus's music layer — runs on the MDCT.

### MP3: the format that escaped the lab

MP3 — formally **MPEG-1 Audio Layer III** — grew out of work begun by **Karlheinz Brandenburg** at the University of Erlangen-Nuremberg from 1977, then developed at **Fraunhofer IIS** with Bernhard Grill, Jürgen Herre, Harald Popp and others. It standardized as part of MPEG-1 (ISO/IEC committee draft 1991, finalized 1992, published 1993); the ".mp3" extension was picked in a 1995 internal Fraunhofer poll. Architecturally MP3 is a *hybrid*: a 32-band polyphase filterbank feeding an MDCT, a psychoacoustic model controlling quantization, and Huffman entropy coding on the quantized coefficients. At ~128 kbit/s it gave near-CD quality at roughly one-eleventh the size.

MP3's cultural detonation (Winamp, Napster in 1999, the iPod in 2001) was inseparable from its **patent** drama. Fraunhofer and Thomson began enforcing licensing in September 1998, demanding per-decoder/encoder royalties; in Europe **Sisvel** pursued customs seizures and even raided trade-show booths. Those fees motivated the entire royalty-free codec movement. The last relevant US patents expired around **April 2017**, when Fraunhofer terminated its licensing program — making MP3 finally free, long after it had been culturally eclipsed.

### AAC and Vorbis: the successors

**Advanced Audio Coding (AAC)** was standardized as MPEG-2 Part 7 in **April 1997** (folded into MPEG-4 in 1999), by Fraunhofer, Dolby, Sony, AT&T and Nokia. It dropped MP3's awkward hybrid filterbank for a **pure MDCT** with up to 1024 coefficients (vs MP3's coarser resolution), better stereo tools (joint/parametric stereo), and temporal noise shaping. The payoff: AAC at ~96 kbit/s roughly matches MP3 at 128. It became the default for iTunes, YouTube and broadcast — but, like MP3, it was patent-encumbered.

That encumbrance is exactly why **Vorbis** exists. After Fraunhofer's 1998 licensing letter, **Chris Montgomery** founded the **Xiph.Org Foundation** and released Ogg Vorbis (1.0 frozen May 2000) as a fully **royalty-free**, patent-unencumbered MDCT codec of comparable quality. Vorbis never dethroned AAC in consumer devices but became standard in games (its small decoder, no royalties) and was the proof-of-concept for open codecs.

### Opus: the codec that won real-time

**Opus** (IETF **RFC 6716**, September 2012) is the modern endgame, built by a broad coalition — Xiph, Skype, Mozilla, Broadcom, Google, Microsoft — explicitly chartered to be royalty-free and suitable for WebRTC. Its trick is to fuse two codecs designed for opposite signals: **SILK** (Skype's linear-predictive speech coder, modeling the vocal tract) and **CELT** (Xiph's low-delay MDCT music coder). Opus runs SILK-only at low bitrates, CELT-only for very-low-delay music, or a hybrid in between, switching seamlessly. Crucially it offers frame sizes from **2.5 ms** up, giving algorithmic delay as low as ~5 ms — beating AAC-ELD — which is why it dominates VoIP, Discord, video conferencing and WebRTC streaming.

Opus keeps evolving. **Opus 1.5 (March 2024)** added deep-learning tools that run while staying bitstream-compatible: **LACE/NoLACE** (neural postfilters that sharpen decoded speech without sending the audio through the network) and **DRED (Deep REDundancy)**, which embeds ~1 second of neural recovery data in packet padding to survive long burst losses — directly attacking VoIP's worst failure mode. Subsequent maintenance releases through 2025–2026 have refined these; Opus remains the reference real-time codec.

### FLAC: lossless, and why its ratios are modest

For archival and audiophile use, lossy is unacceptable. **FLAC (Free Lossless Audio Codec)**, released by **Josh Coalson** under a BSD license in 2001, is the open lossless standard (it became an IETF-documented format via the CELLAR working group in the 2020s). Its method is classic: per-block **linear prediction** estimates each sample from its predecessors, leaving a small **residual** (prediction error); that residual is entropy-coded with **Rice/Golomb codes**, which are near-optimal for the roughly geometric/Laplacian distribution of residuals and need only a single tunable parameter per partition. No psychoacoustics, no information thrown away — so FLAC typically reaches only **30–60% reduction** (~2:1). The contrast is the whole lesson: lossy codecs win an order of magnitude *only* by discarding perceptually irrelevant information, whereas lossless coding is bounded by the true Shannon entropy of the waveform, which for music is stubbornly high.