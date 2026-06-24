#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The State of the Field, June 2026

#epigraph[
  "The map is not the territory, but a good map saves you from walking off a cliff."
][paraphrase of Alfred Korzybski, _Science and Sanity_, 1933]

Here is a puzzle that might feel familiar if you have been paying attention to
the news cycle. In one week in early 2026, three different journalists published
three different takes on the same slice of the compression world. The first
declared that "AI has made traditional codecs obsolete." The second ran the
headline "Netflix Reaches 30% AV1 Streaming." The third warned that
"JPEG will never die." All three were reporting accurately on real numbers.
All three were, in important ways, wrong about what those numbers mean.

You now have 78 chapters of scaffolding in your head. You understand entropy,
Huffman coding, arithmetic coders, ANS, LZ77, DEFLATE, BWT, DCT, rate-distortion
theory, neural learned compression, LLMs as compressors, model quantization,
KV-cache tricks, and more. You have earned the right to read a real snapshot of
the field without being fooled by any of those headlines.

This chapter is that snapshot, taken in June 2026. We will survey what is
actually shipping in production, what is genuinely emerging, and then we will
build an honest _hype-versus-deployed_ ledger. Nothing here is prediction; it is
a careful reading of publicly available evidence.

#recap[
  By this point in the book we have covered the full arc of the field. *Chapter 2*
  gave the historical overview from Morse to modern times. *Chapters 24–36*
  (Volume II) built the classical lossless stack: Huffman, arithmetic, ANS, LZ77,
  DEFLATE, and BWT. *Chapters 37–55* (Volume III) covered lossy media: DCT
  (Chapter 38), JPEG (Chapter 42), Opus (Chapter 49), HEVC (Chapter 53), and the
  open video codecs including AV1 (Chapter 54), all resting on the rate–distortion
  theory of *Chapter 21*. *Chapters 56–65* (Volume IV) tackled the neural and AI
  era: learned image compression (Chapters 57–58), LLM-as-compressor (Chapter 62),
  neural audio codecs (Chapter 60), and model quantization (Chapter 63).
  *Chapters 66–78* (Volume V) explored specialized domains and the social
  history of the field. Now we pull it all together into a single honest
  picture of where things stand today.
]

#objectives((
  "Name the dominant production codecs in each category (general-purpose, image, audio, video) as of June 2026 and explain what makes each one the current leader.",
  "Describe three genuinely emerging techniques (learned codecs, BitNet-style weight compression, and KV-cache compression) and give an honest status for each.",
  "Apply the hype-vs-deployed test to a claim about compression to decide whether it belongs in a product meeting or a research paper.",
  "Read a compression benchmark or press release and identify what is being measured, what is being omitted, and whether the comparison is fair.",
))

== The Deployed Stack: What Actually Ships

Before we look at the cutting edge, let us anchor ourselves in the present. The
word "deployed" means: a library or format that runs in production on devices
you have already used today: your phone, your browser, a data-centre that
served you a video last night. The bar is not "published" or "benchmarked" or
"merged into a GitHub repository." The bar is: *running at scale, right now.*

=== General-Purpose Lossless: zstd Wins, With Help

If you had to pick one word for the state of general-purpose lossless compression
in mid-2026, the word would be: *zstd*. Facebook (Meta) released Zstandard (zstd)
in 2015 and it became an IETF standard in RFC 8478 (2018) and RFC 8878 (2021).
The design, by Yann Collet, is clever in ways we examined in Chapter 30: it uses
a large sliding-window LZ77 match-finder, ANS entropy coding (which we built
from scratch in Chapter 27), and a _trained dictionary_ feature that lets you
pre-build a shared dictionary from a corpus of similar files and distribute it
as a tiny side-file.

What makes zstd interesting is its range. At
level 1 it is competitive with LZ4 in speed while beating gzip on ratio. At
level 22 it is competitive with bzip2 and even touches LZMA territory. That
single library handles everything from real-time network traffic to cold-storage
archiving, which is exactly what a production engineer wants: one dependency,
one API, sensible defaults.

By June 2026 the deployment picture is almost total. Linux kernel (since 2021).
Facebook's internal fleet (since 2017). Meta white-papers estimate 20 petabytes
per day pass through zstd decoders. Android's OTA updates. Chromium's resource
packing. SQLite extension. And now, as of the SQL Server 2025 Preview
announcement (Microsoft, 2025), even Windows database backups. The HTTP
ecosystem finally moved: Chrome added `Content-Encoding: zstd` support in
version 123 (March 2024) and Firefox followed in version 126 (May 2024).
Cloudflare began end-to-end zstd serving in 2025. The standard compression
handshake for a modern HTTPS connection now often reads: "zstd preferred,
Brotli fallback, gzip for dinosaurs."

gzip (Chapter 30) has not died; it will not die for years, because it is baked
into too many pipes. But no serious new deployment chooses gzip over zstd or
Brotli unless hardware or tooling forces it.

#algo(
  name: "Zstandard (zstd)",
  year: "2015 (open source); 2018 (RFC 8478)",
  authors: "Yann Collet, Meta (Facebook)",
  aim: "Fast, wide-range lossless compression for network traffic, file systems, databases, and package formats; covers LZ4's speed slot through LZMA's ratio slot in one library.",
  complexity: "Encode O(n) to O(n log n) by level; decode O(n) always",
  strengths: "Extreme speed range across 22 levels; trained dictionary support; royalty-free; huge ecosystem; streaming-friendly framing format.",
  weaknesses: "Default ratio slightly behind Brotli at equal speed; dictionary distribution adds deployment complexity; not tuned for random-access into compressed streams.",
  superseded: "Supersedes gzip and LZ4 in most new deployments; complements Brotli for web content.",
)[
  zstd's internal entropy coder uses the tANS (table ANS) variant we described
  in Chapter 27. The match-finder uses a hash-chain + binary-tree hybrid for
  higher levels. The trained dictionary feature is grounded in the Cover algorithm
  for selecting representative substrings, the same idea as the dictionary
  seeding in Chapter 32.
]

#keyidea[
  zstd is not the *best* compressor on any single benchmark. It is the best
  *single library* that covers the entire speed-ratio spectrum acceptably. That
  is the right trade-off for infrastructure.
]

=== Image: AVIF Is the Web Standard; JPEG XL Is Knocking

The image format war of 2020–2025 has ended, with two survivors and one wildcard.

*JPEG* (Chapter 42) is still 73% of all images served on the web in June 2026.
That number will be true five years from now too. JPEG is embedded in a billion
devices, understood by every image-processing library ever written, and perfectly
adequate for photographs. It will not be "replaced"; it will be gradually
marginalised for new content as better formats accumulate browser support.

*AVIF* (the AV1 Image File Format) reached near-universality in 2025. Safari 17
finally shipped AVIF decoding, and as of April 2026 all four major browser
engines (Chrome, Firefox, Safari, Edge) support it, covering over 93% of global
browser usage. The AVIF v1.2.0 specification published in November 2025. At
equal visual quality, AVIF files are roughly 50% smaller than JPEG. The catch
is encoding speed: AVIF encoding takes on the order of 480 ms per typical web
image, about ten times slower than JPEG. That cost lands on the content pipeline,
not the end user. Production CDNs handle this by pre-encoding and caching. For
a site that serves a known catalogue of images (a product page, a photo gallery),
the one-time encoding cost is negligible. For a site that generates images
on-demand from user uploads, the latency is a real engineering problem.

*JPEG XL* is the wildcard. The format (Chapter 45) offers better compression
than AVIF on complex scenes, lossless re-encoding of existing JPEGs with no
generation loss, and a rich feature set. The political story was messy: Google
dropped Chrome support in 2022, then in November 2025 the Chromium team reversed
its "obsolete" stance. A Rust-based `jxl-rs` decoder was merged into Chromium in
January 2026. Chrome 145 shipped it behind a flag in February 2026. Firefox 152
added experimental JXL support in June 2026. Safari has supported JPEG XL by
default for some time. As of this writing, Chrome and Firefox keep JXL behind
an experimental flag, so effective browser coverage is about 20–25% (Safari's
user base). The expected timeline: Chrome enables JXL by default in H2 2026,
which would push global coverage to 85–90% overnight.

#fig(
  [Image format landscape, June 2026. Bars show approximate global browser coverage (percent of users who can decode). AVIF has cleared the practical deployment threshold; JPEG XL is approaching it.],
  cetz.canvas({
    import cetz.draw: *
    let formats = (("JPEG", 99), ("WebP", 97), ("AVIF", 93), ("JPEG XL", 25))
    let bar-h = 0.55
    let gap = 0.25
    let max-w = 6.5
    for (i, (name, pct)) in formats.enumerate() {
      let y = (formats.len() - 1 - i) * (bar-h + gap)
      let w = pct / 100 * max-w
      rect((0, y), (w, y + bar-h),
        fill: if pct >= 90 { rgb("#0b5394").lighten(20%) }
              else if pct >= 50 { rgb("#0b6e4f").lighten(30%) }
              else { rgb("#783f04").lighten(40%) })
      content((-0.1, y + bar-h / 2), anchor: "east",
        text(size: 8pt)[#name])
      content((w + 0.15, y + bar-h / 2), anchor: "west",
        text(size: 8pt)[#pct%])
    }
    line((max-w * 0.9, -0.2), (max-w * 0.9, (formats.len()) * (bar-h + gap) - gap + 0.2),
      stroke: (dash: "dashed", paint: red.lighten(30%), thickness: 0.7pt))
    content((max-w * 0.9, (formats.len()) * (bar-h + gap) - gap + 0.45),
      anchor: "east",
      text(size: 7pt, fill: red.darken(20%))[90% threshold])
  })
)

#algo(
  name: "AVIF (AV1 Image File Format)",
  year: "2019 (spec); 2025 (near-universal browser support)",
  authors: "Alliance for Open Media",
  aim: "Royalty-free still-image format derived from AV1 video codec; replaces WebP and challenges JPEG for web photography.",
  complexity: "Encoding O(n·Q) where Q scales with quality/effort level; decoding O(n).",
  strengths: "~50% size reduction vs JPEG; universal browser support as of 2025; royalty-free; HDR, wide-gamut, and alpha support.",
  weaknesses: "Encoding is 5-10× slower than JPEG; metadata/ICC profile handling has had interoperability bugs; animation support lags behind WebP.",
  superseded: "WebP for new web deployments; not yet replacing JPEG in camera pipelines.",
)[
  Under the hood AVIF uses the AV1 intra-frame coding tools we studied in
  Chapter 54: DCT and ADST transforms, quantization matrices, CDEF filtering,
  loop restoration, and arithmetic entropy coding. The container is HEIF/ISOBMFF,
  which is also used by Apple's HEIC format.
]

=== Video: AV1 Is Growing; HEVC Holds 4K; VVC Waits

Video compression is a three-way story right now.

*H.264 / AVC* is still the baseline that everything must support. Legacy live
streams, corporate video conferencing infrastructure, older smart TVs, and
billions of embedded devices all speak H.264 and only H.264. It is not going
anywhere.

*HEVC / H.265* dominates 4K streaming and hardware video recording. Every modern
smartphone records in HEVC. Broadcast and over-the-top delivery of 4K HDR
content predominantly uses HEVC encoders. The patent licensing situation (Chapter
77) created years of uncertainty, but the market settled: the major streaming
platforms pay the licensing fees because the alternatives were not ready.

*AV1* is the growth story. Netflix reported in December 2025 that 30% of its
streams use AV1, up from near zero in 2020. Apple added hardware AV1
decoding in the M3 and A17 Pro chips (late 2023), removing the last major
barrier to mainstream adoption on Apple devices. YouTube launched AV1 for popular
live streams in 2025. A March 2026 white paper from Hanwha Vision examined
surveillance camera applications. The Alliance for Open Media has begun
preliminary work on AV2, with key milestones reached in late 2025.

The codec coexistence pattern here is important: AV1 has *not* displaced HEVC.
In June 2026 the real world runs AV1, HEVC, and H.264 simultaneously, targeting
each codec at the hardware available on a given device. A major streaming service
will typically have three encoding ladders in production at once.

#misconception[AV1 has replaced H.265 for 4K streaming.][In June 2026, HEVC still dominates 4K hardware recording and broadcast delivery. AV1 is taking market share for OTT streaming to AV1-capable devices. The two codecs coexist on different delivery pipelines; neither has "won."]

*VVC / H.266* was standardized in 2020 and offers roughly 30–50% improvement
over HEVC. It has made no real impact on the market, for the same reason
HEVC struggled: patent licensing. The MPEG-LA pool, the Via Licensing pool, and
the Access Advance pool all claimed essential patents, creating the same three-way
impasse that delayed HEVC. As of mid-2026 VVC has found niche use in broadcast
and videoconferencing research but is not a mainstream deployment target.

#checkpoint[
  A startup claims to have built the "first AV1 live streaming pipeline for 4K
  sports." Is this plausible in mid-2026?
][
  Plausible but not impressive. YouTube launched AV1 live support for popular
  streams in 2025, and cloud encoding services (AWS, GCP) added AV1 live encoding
  in 2024–2025. "First" is likely marketing. The real question is latency and
  encoder cost at 4K 60fps, where AV1 remains expensive to encode in real time.
]

=== Audio: Opus 1.6 Adds Neural Features; Neural Codecs Are Production-Ready

Opus (Chapter 49) remains the dominant open-source audio codec for real-time
communication. It is the default codec for WebRTC, used in Google Meet, WhatsApp,
Discord, and virtually every browser-based voice call. In December 2025, the Opus
team released *Opus 1.6*, which extends the neural features first added in 1.5:

- A new *bandwidth extension (BWE)* neural module that generates high-frequency
  content (8–20 kHz) from wideband speech (0–8 kHz) with no side information,
  using pure synthesis from a small neural predictor. The result is perceptually richer
  audio at no additional bitrate.
- *Opus HD* support at 96 kHz sampling rates.
- Improved *DRED* (Deep Redundancy), which embeds a compressed fallback
  representation for concealing packet loss.

This hybrid architecture (classical codec internals with neural post-processing)
is representative of the near-term convergence path for audio. The IETF has
an active *mlcodec* working group specifically tasked with standardizing
machine-learning codec extensions to Opus.

Pure neural audio codecs (EnCodec from Meta, SoundStream from Google, LPCNet for
speech) are now production-deployed in specific verticals. Meta uses EnCodec for
Voicebox and other internal audio generation. Neural codecs can match or exceed
Opus quality at half the bitrate for speech, at the cost of significantly more
compute on the encoder side. For devices with DSP hardware (which describes
every recent phone), the decode cost is acceptable. For battery-constrained IoT
audio devices, classical Opus remains the right answer.

=== General-Purpose Lossless: The Role of Brotli and Beyond

It would be incomplete not to mention *Brotli* (Chapter 32). Brotli was designed
by Google with a static pre-built dictionary of common web content patterns and
an LZ77-plus-Huffman back-end. It typically beats zstd at ratio for web assets
(HTML, CSS, JavaScript) because the static dictionary carries substantial benefit
for those exact content types. In practice, web servers serve Brotli to browsers
and zstd to everything else. They coexist comfortably.

#scoreboard(
  caption: "Lossless compression, Canterbury Corpus `alice29.txt` (152,089 bytes), June 2026",
  [Original],[152,089],[1.00×],[uncompressed],
  [gzip -6],[54,191],[2.81×],[DEFLATE, the classic],
  [Brotli -9],[49,765],[3.06×],[best for web text],
  [zstd -3],[52,003],[2.92×],[fast default],
  [zstd -19],[47,108],[3.23×],[slow, high ratio],
  [bzip2 -9],[43,765],[3.47×],[BWT-based, Chapter 35],
  [xz -6],[40,104],[3.79×],[LZMA, best classical],
)

== What Is Genuinely Emerging

Having nailed down what is deployed and boring, let us look at what is genuinely
promising but not yet ubiquitous. The test for "genuinely emerging" versus "pure
hype" is: _does it run in production on real users' data, or does it exist only
in papers and demos?_ Several techniques pass that test in 2026 despite not yet
being mainstream.

=== Learned Image Compression: Research-Grade But Gaining Traction

The line of work begun by Ballé et al. (ICLR 2017, studied in Chapter 57)
has matured enormously. Modern learned image codecs (the Cheng 2020 anchor,
ELIC, and their successors) consistently beat AVIF at equal PSNR and match or
exceed JPEG XL at high-fidelity targets on benchmark images.

#mathrecall[
  *PSNR* (peak signal-to-noise ratio), defined in Chapter 42 and revisited in
  Chapter 75, measures how close a reconstructed image is to the original: it is
  $10 log_10 ("MAX"^2 / "MSE")$ in decibels, where MSE is the mean squared pixel
  error and MAX is the largest possible pixel value (255 for 8-bit). Higher is
  better; "equal PSNR" means "same measured fidelity," so a codec that wins at
  equal PSNR delivers the same fidelity in fewer bits.
]

On photographic
content, the best learned codecs achieve the same visual quality as JPEG at
roughly 60–70% lower file size, well beyond what any classical codec achieves.

Why is this not deployed yet? Three reasons:

1. *Encoding speed.* A classical JPEG encoder runs in milliseconds. A state-of-the-art
   neural encoder running on a CPU takes seconds; even on GPU, the latency is
   significant for a real-time pipeline.
2. *Complexity and maintenance.* A codec you deploy on a billion devices must be
   interoperable, auditable, and maintainable for a decade. A neural network
   bundled with weights is none of those things easily.
3. *Standardization.* The JPEG committee's *JPEG AI* standard (formally ISO/IEC 15444-17)
   is in active development and aims to standardize a learned-compression pipeline,
   which would solve the interoperability problem. As of mid-2026 it has not reached
   final standard status but the committee process is moving.

#aside[
  Fabrice Bellard (whom we met in Chapter 2 as the author of QEMU and FFmpeg)
  published his `ts_zip` neural compressor in the early 2020s as a research
  curiosity. By 2026 the same *principle* - use a powerful model to predict the
  next byte or token, then arithmetic-code the residual - has been validated
  academically by Delétang et al. (ICLR 2024). The practical speed barrier
  is what keeps it out of production.
]

=== Generative / Super-Resolution Codecs: A Different Kind of Trade-Off

At extremely low bitrates, learned codecs face the same problem all lossy codecs
face: you must discard information, and at some point the reconstruction looks
wrong, not just blurry. A classical codec at 0.05 bits-per-pixel produces
block-artifact nightmares. (_Bits-per-pixel_, or bpp, is the image analogue of
the bits-per-byte we used for text: total compressed bits divided by the number
of pixels. Uncompressed 8-bit colour is 24 bpp; good JPEG sits near 1–2 bpp;
0.05 bpp means roughly one bit for every twenty pixels, almost nothing to work
with.) A learned codec produces smooth but hallucinated
content: faces with impossible symmetry, text that becomes plausible nonsense.

*Generative* or *perceptual* codecs (HiFiC, Mentzer et al., and their
2024–2026 successors, the topic of Chapter 58) lean into this. Rather than trying to reconstruct the
exact original, they synthesize a *plausible* image that passes perceptual
metrics and human evaluation. HiFiC at 0.15 bits-per-pixel can produce images
that human raters prefer to JPEG at twice the bitrate. The cost: the decoder is
a large generative model (typically a GAN or diffusion model), and the
reconstruction is *not* the original; it is a hallucination that looks better.

This is a genuine paradigm shift, not hype: the goal of compression has been,
since Shannon, to recover the exact source or an approximation within a
distortion bound. Generative codecs explicitly abandon the goal of reconstructing
the source and optimize for human perception instead. Whether this is acceptable
depends on the use case. For a news photograph that will be authenticated later,
hallucination is unacceptable. For a social media thumbnail at very low bitrate,
it may be the best option.

#keyidea[
  Generative codecs optimize for *perceived quality*, not *distortion from the
  original*. They produce images that look better to humans but cannot be used
  anywhere the original content must be verifiable.
]

=== LLMs as Compressors: Theoretically Beautiful, Practically Slow

We devoted Chapter 62 to this topic. The core result, that a language model's
perplexity score on a dataset is equivalent to a compression ratio, is clean
and has been experimentally confirmed (Delétang et al., "Language Modeling Is
Compression," ICLR 2024). GPT-4 can, in principle, compress English text below
1 bit/character, far better than any classical compressor.

#gomaths("Perplexity")[
  _Perplexity_ is the standard score for how well a language model predicts text,
  and it is just a re-dressing of the cross-entropy we built in Chapter 23. If the
  model assigns probability $p_i$ to each true next token $i$ across $N$ tokens,
  its cross-entropy (in bits per token) is the average surprisal
  $ H = -1/N sum_(i=1)^N log_2 p_i, $
  exactly the "expected code length" a perfect coder would pay. Perplexity is
  simply $2^H$: the model is "as confused as if it were guessing uniformly among
  $2^H$ equally likely tokens." A model with perplexity 8 is, on average, as
  unsure as someone picking blindly from 8 options (that is, $log_2 8 = 3$ bits
  of surprise per token). So *lower perplexity means lower cross-entropy means
  fewer bits to code the text*: perplexity and compression ratio are two faces
  of the same number.
]

In June 2026 this is still a laboratory result. The fundamental speed problem
has not been solved: to compress 1 MB of text with an LLM as the arithmetic-
coding model, you must make on the order of 4 million autoregressive token
predictions. At current inference throughput, that takes minutes per megabyte on
a modern GPU, three to four orders of magnitude slower than zstd. Bellard's
`ts_zip` achieves sub-1-bit-per-character compression on text but runs at kilobytes
per second. For archival compression of data that will be stored for decades and
decompressed rarely, this speed may be acceptable in niche applications. For
anything resembling general use, it is not.

#pitfall[
  "LLMs compress better than zstd, so we should use LLMs for compression."
  This statement is true on ratio for text and completely false as an engineering
  recommendation in 2026. The speed gap is 1000× or more. Always ask: ratio
  *and* speed *and* resource requirements.
]

=== BitNet and Extreme Weight Quantization

Chapter 63 covered model compression in depth. The update for mid-2026: the
1-bit and 1.58-bit LLM research direction (BitNet b1.58 by Wang et al., 2024)
has been validated at scale. A 1.58-bit model stores each weight as one of
$\{-1, 0, +1\}$. The "1.58" is the information content of a three-way choice:
$log_2 3 approx 1.58$ bits is the theoretical floor for a ternary symbol (the
exponents-and-logarithms idea from Chapter 7), which an entropy coder can
approach in bulk. Stored naively, three values still need 2 bits each; either
way it is a ~8–11× shrink of the 16-bit (FP16) weights. The quality gap versus
full-precision models has been closing; as of
2026 the architecture has been validated up to the 7B–13B parameter scale, though
not yet competitive with the best full-precision models at equivalent scale and
compute.

*BitNet v2* (2025) adds Hadamard transformation to handle activation outliers,
a problem we saw in Chapter 63 with GPTQ and AWQ. The combination enables native
4-bit activations on top of 1-bit weights, which is significant for inference
efficiency because activation quantization previously required careful calibration.

#mathrecall[
  A *Hadamard transform* (Chapter 63) is a fixed, cheap orthogonal "mixing"
  matrix built entirely from $+1$ and $-1$ entries. Multiplying a vector by it
  spreads each component evenly across all the others. A single huge outlier
  value gets smeared into many moderate values that quantize cleanly, and the
  transform is exactly undone afterwards because it is its own inverse (up to a
  scale). It is the same "rotate to tame outliers" trick that PolarQuant and the
  rotation-based KV methods below also use.
]

The production story: 4-bit weight quantization (GPTQ, AWQ, and friends) is fully
deployed. It is how most consumer and edge LLM inference actually runs today:
llama.cpp, Ollama, and similar tools default to 4-bit quantized weights. The
1-bit/1.58-bit regime is genuinely emerging: real research, promising results,
but not yet the deployment default.

=== KV-Cache Compression: The 2024–2026 Hotspot

If you follow the LLM engineering space, you cannot have missed the
KV-cache problem. Every token in a long prompt requires storing a key vector
and a value vector for every attention head in every layer. For a model with
32 layers and 32 heads using 128-dimensional vectors in FP16, each token
costs $2 times 32 times 32 times 128 times 2 "bytes" = 524 "KB"$ of KV
storage. A context window of 128,000 tokens then needs 64 GB, more than fits
in any consumer GPU's VRAM.

#gomaths("Memory arithmetic for KV caches")[
  Let us make this concrete. A transformer with:
  - $L = 32$ layers
  - $H = 32$ attention heads
  - $d_"head" = 128$ dimensions per head
  - $p = 2$ bytes per value (FP16)

  stores, per token, a key tensor and a value tensor:

  $ "bytes/token" = 2 times L times H times d_"head" times p $

  $ = 2 times 32 times 32 times 128 times 2 = 524,288 "bytes" approx 512 "KB" $

  For a context of $N = 128,000$ tokens:

  $ 128,000 times 512 "KB" = 64 "GB" $

  That is the entire VRAM of four high-end consumer GPUs. At 4-bit quantization
  (dividing by 4), it drops to 16 GB, one GPU's VRAM, which is why INT4 KV
  quantization is the current production baseline.
]

Three families of techniques are deployed or near-deployment:

*KV quantization* stores keys and values at INT8 or INT4 rather than FP16.
INT8 halves the memory; INT4 quarters it with some quality degradation on long-
context tasks. The technical challenge is outlier activations: a few key/value
dimensions have unusually large magnitudes that cause rounding errors. Rotation-
based methods like PolarQuant (AISTATS 2026) apply a learned Hadamard rotation
to smooth outliers before quantization.

*Token eviction* discards keys and values for tokens that receive low attention
weight. The H2O method (from 2023) and SnapKV (2024) are the canonical examples.
In practice this is aggressive: you are permanently deleting information, and the
models can fail silently on long-reasoning tasks. Production use requires
careful evaluation.

*Architectural KV compression* bakes compression into the model design at
training time. The landmark here is DeepSeek's *Multi-head Latent Attention
(MLA)*, first deployed in DeepSeek-V2 (May 2024) and carried forward in
DeepSeek-V3 (December 2024) and DeepSeek-R1. MLA jointly projects keys and
values into a small shared latent vector; only that latent is stored in the
KV cache. DeepSeek-V2 reports 93% KV cache reduction compared to standard
multi-head attention, with no quality loss. This is compression built into the
attention mechanism itself, not a post-hoc workaround but an architectural
choice.

#algo(
  name: "Multi-head Latent Attention (MLA)",
  year: "2024",
  authors: "DeepSeek AI (DeepSeek-V2 team)",
  aim: "Reduce KV-cache memory by jointly compressing keys and values into a shared low-rank latent representation at training time, eliminating the need for post-hoc cache compression at inference.",
  complexity: "Attention compute unchanged; KV storage reduced by ~93% vs MHA at same model scale.",
  strengths: "No quality loss; reduction is structural, not heuristic; compatible with standard transformers; enables million-token contexts on feasible hardware.",
  weaknesses: "Requires training from scratch with new architecture; cannot be retrofitted to existing pre-trained weights; low-rank bottleneck may slightly limit model expressiveness on some tasks.",
  superseded: "Partial replacement for GQA (Grouped Query Attention) and MQA at the same compression target.",
)[
  MLA is an application of low-rank matrix factorization (Chapter 12) to the
  attention key-value computation. The key insight: at each layer, rather than
  maintaining $H times d_"head"$ separate key and value vectors per token,
  project them all through a shared matrix of rank $r << H times d_"head"$
  and store only the $r$-dimensional latent. Reconstruction at attention time
  is a cheap matrix multiply.
]

== The Hype-versus-Deployed Ledger

Now we can build the ledger. The left column is "deployed and boring": things
that ship in production, receive no press coverage because they work, and will
still be running in five years. The right column is "hyped but not there yet":
real techniques with real research behind them, not fraud, but not production.

#figure(
  table(
    columns: (1fr, 1fr),
    inset: 8pt,
    fill: (_, row) => if row == 0 { rgb("#0b5394").lighten(85%) } else { none },
    align: left,
    table.header([*Deployed and Boring*], [*Hyped But Not Production*]),
    [zstd for general lossless], [LLM compressors (1000× too slow)],
    [Brotli for web content], [1-bit/1.58-bit LLMs at scale],
    [AVIF for web images], [JPEG XL (flag only in Chrome/Firefox)],
    [AV1 for OTT streaming], [VVC/H.266 for consumer video],
    [HEVC for 4K recording], [Learned image codecs (JPEG AI in progress)],
    [Opus for WebRTC audio], [Generative reconstruction codecs for mainstream use],
    [4-bit LLM weight quantization], [Sub-3-bit LLM weights without quality loss],
    [KV quantization INT8/INT4], [Token eviction without quality regression],
    [MLA architecture (DeepSeek)], [Attention compression without retraining],
    [Parquet/Gorilla for analytics], [Universal neural lossless compression],
    [CRAM for genomics], [Reference-free neural genomic compression at speed],
  ),
  caption: [The hype-versus-deployed ledger, June 2026. Both columns represent real work; the right column is not fraud: it is research.],
)

=== An Honest Worked Example: Reading a Benchmark

Let us apply this thinking to a real scenario. A paper appears in June 2026
claiming: "Our codec achieves 2.5× the compression ratio of zstd on standard
text corpora." How do you evaluate this?

Step 1: *What is being compressed?* Text is zstd's weakest domain. On English
prose, methods with powerful language models (like PPMd or CMIX) easily beat
zstd. On binary data, binary executables, or mixed corpora, zstd is far more
competitive. A "2.5×" win on text tells you nothing about the general case.

Step 2: *What speed?* A 2.5× ratio improvement is worthless if the codec takes
ten minutes to compress a 1 MB file. The paper should report MB/s for both
encode and decode.

Step 3: *What is the baseline setting?* zstd at level 1? Level 19? The default
is level 3. Comparing a slow new codec to zstd-1 is not a fair test.

Step 4: *Is the comparison to a trained dictionary?* A custom-trained zstd
dictionary on a homogeneous corpus can close 30–50% of the gap that methods
claim on "standard" text corpora without a pre-built dictionary.

Step 5: *What is the decompression cost?* For many use cases, random-access
decompression (can you seek to byte 1,000,000 without decompressing everything
before it?) matters as much as ratio.

#gopython("Benchmarking compression in Python")[
  Python's standard library includes `zlib` (for DEFLATE/gzip), and the
  `zstandard` third-party package wraps the libzstd C library.
  Here is a simple timing harness that measures both ratio and throughput.

  ```python
  import time, zlib, zstandard as zstd

  def bench(name: str, data: bytes, compress_fn, decompress_fn) -> None:
      t0 = time.perf_counter()
      compressed = compress_fn(data)
      enc_s = time.perf_counter() - t0

      t0 = time.perf_counter()
      _ = decompress_fn(compressed)
      dec_s = time.perf_counter() - t0

      ratio = len(data) / len(compressed)
      mb = len(data) / 1_000_000
      print(f"{name:20s}  ratio={ratio:.2f}x  "
            f"enc={mb/enc_s:.0f} MB/s  dec={mb/dec_s:.0f} MB/s  "
            f"size={len(compressed):,} B")

  with open("alice29.txt", "rb") as f:
      data = f.read()

  # gzip level 6
  bench("gzip-6", data,
        lambda d: zlib.compress(d, level=6),
        zlib.decompress)

  # zstd level 3 (default)
  cctx3 = zstd.ZstdCompressor(level=3)
  dctx  = zstd.ZstdDecompressor()
  bench("zstd-3", data,
        cctx3.compress,
        dctx.decompress)

  # zstd level 19 (high ratio)
  cctx19 = zstd.ZstdCompressor(level=19)
  bench("zstd-19", data,
        cctx19.compress,
        dctx.decompress)
  ```

  On a modern laptop, you might see:
  ```
  gzip-6               ratio=2.81x  enc=74 MB/s   dec=280 MB/s  size=54,191 B
  zstd-3               ratio=2.92x  enc=310 MB/s  dec=1,100 MB/s  size=52,003 B
  zstd-19              ratio=3.23x  enc=5 MB/s    dec=1,050 MB/s  size=47,108 B
  ```

  Notice that zstd decode speed is roughly equal at level 3 and level 19.
  The level only affects the encoder's search effort, not the compressed
  format. This is a design property called _asymmetric compression_: you
  pay once to encode slowly, then decompress quickly forever.
]

#gomaths("Bits per character and compression ratio")[
  Compression ratio and bits-per-character (bpc) are two ways to describe
  the same quantity. If a file has $N$ bytes and compresses to $M$ bytes:

  - *Compression ratio:* $r = N / M$ (larger is better; "3× compression")
  - *Bits per byte:* $b = (M times 8) / N$ (smaller is better; "3 bits/byte")
  - *Space saving:* $s = 1 - M/N$ (in percent)

  They relate as: $r = 8 / b$ and $b = 8 / r$. Saying "2.81× compression"
  is exactly the same as saying "2.85 bits/byte" or "64.4% space saving."

  For text, information theorists often measure in _bits per character_ (bpc)
  where each character is one ASCII byte (8 bits). Shannon estimated English
  text has about 1–1.5 bits per character of true entropy. zstd at 2.85 bpc
  is still well above that floor; an LLM-based compressor can approach 1 bpc.
]

== Where the Frontier Has Moved

Let us end with an observation that the scoreboards above do not capture.

For the first half-century of compression research, the question was:
_given a fixed statistical model of the data, how efficiently can we code the
symbols?_ That was Shannon's original question, and it produced Huffman coding,
arithmetic coding, and ANS: all beautiful answers.

For the second half-century, the question shifted to:
_how do we build better models?_ That is what PPM, CTW, BWT, and context mixing
all did. They built progressively better models of the data distribution so the
coder had less residual to spend bits on.

Now, in 2026, the question has shifted again. For images and video, the question
is: _can the decoder hallucinate what was not sent?_ For text, the question is:
_can we exploit a model trained on all human text to predict the next byte of any
new document?_ For LLM weights, the question is: _can we represent 70 billion
parameters in 35 gigabytes without losing what the model knows?_ For KV caches,
the question is: _can we compress the entire context of an ongoing conversation
without the model forgetting the beginning?_

All of these questions are compression questions. But the "model" in the
model-plus-coder pair is now a neural network with billions of parameters,
not a Markov chain or a suffix array. The mathematical structure is the same
as what Shannon described in 1948: send only the surprise. The engineering
is entirely different.

#keyidea[
  The frontier of compression has merged with the frontier of machine learning.
  You cannot work on the cutting edge of either field without understanding both.
  The chapters in this volume have built exactly that dual fluency.
]

This also means the deployment gap has widened. Classical codecs (zstd, HEVC,
Opus, AVIF) deploy on tiny embedded chips because their algorithms are simple
enough to implement in hardware or optimized C code. Neural codecs require
substantial compute. The gap between "best possible compression" and "compression
that runs on your refrigerator's chip" is larger in 2026 than it has ever been.
That gap is an engineering frontier that will define the next decade.

#history[
  The pattern of "theoretically optimal but practically too slow" has appeared
  before. Arithmetic coding was theoretically superior to Huffman from the day
  Rissanen and Langdon published it in 1979, but practical Huffman dominated
  for fifteen years until CPUs were fast enough to make arithmetic coding
  worth the implementation cost. ANS was published by Duda in 2009 and did not
  appear in production codecs until zstd (2015) and JPEG XL's Brotli-derived
  coder. The speed gap between theory and practice always closes, but it
  closes on a timeline of years to decades, not months.
]

#takeaways((
  "zstd is the dominant general-purpose lossless codec in June 2026, covering everything from HTTP responses to database backups.",
  "AVIF has near-universal browser support (93%) and is the practical choice for new web image deployments. JPEG XL is behind an experimental flag in Chrome and Firefox but expected to default on in H2 2026.",
  "AV1 reaches 30% of Netflix streams; HEVC still dominates 4K hardware recording. H.264 remains the universal baseline. VVC has made no market impact.",
  "Opus 1.6 adds neural bandwidth extension and DRED improvements. Pure neural audio codecs are deployed in speech synthesis but remain compute-heavy for real-time communication.",
  "4-bit LLM weight quantization is fully deployed and the production default for edge inference. 1-bit/1.58-bit (BitNet) is genuinely promising but not yet deployment-grade.",
  "KV-cache compression is the hottest active engineering front. INT4 KV quantization is deployed; DeepSeek's MLA (93% KV reduction by architecture) is deployed; aggressive token eviction requires careful quality evaluation.",
  "LLM-as-compressor and learned image codecs (JPEG AI) are genuine research advances, not hype, but are currently too slow for general production use.",
  "The frontier of compression and the frontier of machine learning have merged. Both require the other to advance.",
))

== Exercises

#exercise("79.1", 1)[
  A colleague says "AVIF is better than JPEG in every way, so you should
  convert all your old photos to AVIF." Give two specific reasons why you
  might *not* want to do this, using concepts from this chapter and earlier.
]
#solution("79.1")[
  First, converting a lossy-encoded JPEG to AVIF involves decoding the JPEG
  (introducing JPEG's quantization artifacts into the decoded pixels) and then
  re-encoding in AVIF. Every generation of lossy re-encoding degrades quality;
  the converted AVIF is *worse* than the original JPEG content. Second, JPEG XL
  offers a lossless JPEG-to-JXL path that preserves the exact original JPEG
  bitstream and is reversible back to the original JPEG; AVIF has no equivalent.
  If archival quality matters, the right move is to archive the original JPEGs
  (or losslessly re-encode to JPEG XL), not re-compress to AVIF.
]

#exercise("79.2", 1)[
  Using the scoreboard in this chapter, calculate the bits-per-byte achieved
  by `zstd -19` on `alice29.txt`. How far is this from English text's
  estimated entropy of about 1.0–1.5 bits per character?
]
#solution("79.2")[
  `zstd -19` produces 47,108 bytes from 152,089 bytes.
  Bits per byte $= (47108 times 8) / 152089 approx 2.48$ bits per byte (character).
  English entropy is estimated at 1.0–1.5 bits/character. The gap is about
  1 to 1.5 bits per character. There is still roughly a factor of 1.7–2.5×
  left on the table for text, which explains why LLM-based compressors can
  outperform zstd on text even though they lose badly on speed.
]

#exercise("79.3", 2)[
  Explain why DeepSeek's MLA achieves a 93% KV-cache reduction while maintaining
  model quality, using the concepts of low-rank approximation (Chapter 12) and
  rate-distortion theory (Chapter 21). Why can't you simply apply MLA to an
  existing pre-trained model without retraining?
]
#solution("79.3")[
  MLA applies low-rank factorization to the key-value projection matrices. If
  the attention mechanism's effective rank (the number of dimensions that
  actually carry useful information) is much smaller than the full $H times d$
  dimensionality, a low-rank bottleneck loses little information. Rate-distortion
  theory tells us there exists an optimal trade-off between the bitrate
  (memory used for the KV cache) and the distortion (quality degradation); MLA
  finds a favorable operating point on that curve because the attention weight
  matrices are empirically low-rank (a structural property discovered through
  training). You cannot retrofit MLA because the low-rank structure must be
  *learned jointly with the model's other weights*. The attention heads must
  learn to route information through the latent bottleneck from the start of
  training; injecting a bottleneck after the fact into weights trained without
  it destroys the learned representations.
]

#exercise("79.4", 2)[
  A company claims their new codec "beats zstd 3× on benchmark X." Design
  a five-question checklist you would use to evaluate whether this claim is
  meaningful, drawing on the analysis in this chapter.
]
#solution("79.4")[
  1. What corpus is "benchmark X"? If it is a text corpus, does the comparison
     use a zstd trained dictionary?
  2. What zstd level is the baseline? (Level 1 vs level 19 gives very different
     ratios.)
  3. What is the encoding speed and decoding speed, in MB/s?
  4. Does the new codec support streaming and random access, or must the entire
     file be loaded to decompress any part of it?
  5. What is the memory footprint during encode and decode? (A codec that uses
     10 GB of RAM to encode is not usable on a server or embedded device.)
]

#exercise("79.5", 2)[
  A smartphone app stores 10,000 product images, each about 150 KB as JPEG.
  The developer wants to reduce storage. Evaluate the trade-offs of:
  (a) converting all images to AVIF, (b) converting all images to JPEG XL,
  and (c) keeping JPEG but recompressing with a higher quality factor.
  What additional information would you need before making a recommendation?
]
#solution("79.5")[
  (a) AVIF: would achieve roughly 50% size reduction vs JPEG at equal visual
  quality. Browser/OS support is near-universal in mid-2026. Encoding cost
  is the concern: 10,000 images at ~480 ms per image = ~80 minutes on a single
  thread, but this is a one-time batch job. Risk: generation loss from decoding
  original JPEGs before re-encoding. (b) JPEG XL: offers lossless re-encoding
  of existing JPEG bytes (no generation loss), plus JXL's own lossy mode at
  better efficiency than AVIF for complex scenes. As of mid-2026 Chrome and
  Firefox keep JXL behind a flag, so viewing JXL on the web requires checking
  the target audience's browser. If the app controls display (native app), this
  is fine. (c) Recompressing at lower JPEG quality: lossy re-compression degrades
  quality without meaningful benefits vs modern formats. Not recommended.
  Additional information needed: does the app target web browsers (AVIF safer)
  or native iOS/Android apps (JXL works); is image fidelity critical (avoids
  generation-loss by using JXL lossless path); what is acceptable encoding
  compute budget.
]

#exercise("79.6", 3)[
  Using the KV-cache memory formula derived in this chapter, compute the KV-cache
  memory for a 70B-parameter model with the following architecture: 80 layers,
  64 attention heads, 128 dimensions per head, FP16 precision. Then compute
  the memory at:
  (a) INT8 quantization of the KV cache,
  (b) INT4 quantization of the KV cache,
  (c) MLA with a latent dimension of 512 (versus the $80 times 64 times 128 = 655,360$
  full dimension).
  Express your answers for a context of 32,768 tokens.
]
#solution("79.6")[
  Full FP16 KV cache per token:
  $2 times 80 times 64 times 128 times 2 "bytes" = 2,621,440 "bytes" approx 2.5 "MB/token"$

  For 32,768 tokens:
  $32768 times 2.5 "MB" approx 82 "GB"$

  (a) INT8 (1 byte per value instead of 2):
  $82 "GB" / 2 = 41 "GB"$

  (b) INT4 (0.5 bytes per value):
  $82 "GB" / 4 = 20.5 "GB"$

  (c) MLA with latent dimension 512:
  Per token, instead of $80 times 64 times 128 = 655,360$ values, store
  $512$ values. Ratio = $512 / 655360 approx 0.078%$, i.e. ~99.9% reduction
  (this is a theoretical minimum; in practice MLA stores the latent plus a
  small set of decoupled rope keys, landing near the 93% reported in the paper).
  At 93% reduction: $82 "GB" times 0.07 approx 5.7 "GB"$, which fits on a single
  consumer GPU.
]

== Further Reading

#link("https://www.rfc-editor.org/rfc/rfc8878.txt")[Collet & Kucherawy (2021). _Zstandard Compression_. RFC 8878. IETF.] The definitive specification of the zstd format.

#link("https://arxiv.org/abs/2506.05987")[Alakuijala et al. (2025). _JPEG XL: Overview and Applications_. arXiv:2506.05987.] A fresh overview of the format's technical design and deployment trajectory, submitted June 2025.

#link("https://arxiv.org/abs/2008.06091")[Chen et al. (2020). _An Overview of Core Coding Tools in the AV1 Video Codec_. arXiv:2008.06091.] The canonical technical reference for AV1 internals.

#link("https://arxiv.org/abs/2309.10668")[Delétang et al. (2024). _Language Modeling Is Compression_. ICLR 2024 / arXiv:2309.10668.] The paper that proved LLMs are the best lossless compressors we have for text, and why speed is the remaining barrier.

#link("https://arxiv.org/abs/2402.17764")[Wang et al. (2024). _The Era of 1-bit LLMs: All Large Language Models are in 1.58 Bits_ (BitNet b1.58). arXiv:2402.17764.] The ternary-weight LLM paper that launched the sub-2-bit research wave.

#link("https://arxiv.org/abs/2407.18003")[Liang et al. (2024). _A Survey on Efficient Inference for Large Language Models_. arXiv:2407.18003.] Comprehensive survey of KV-cache compression, quantization, and architectural strategies, with a scorecard of production-deployed vs. research-only techniques.

#link("https://arxiv.org/abs/2006.09965")[Mentzer et al. (2020). _High-Fidelity Generative Image Compression (HiFiC)_. NeurIPS 2020 / arXiv:2006.09965.] The flagship paper for perceptual/generative compression at low bitrates.

#link("https://www.mattmahoney.net/dc/text.html")[Mahoney, M. _Large Text Compression Benchmark (LTCB)_.] The definitive independent benchmark for lossless text compression, updated regularly and an essential calibration tool for any compression ratio claim.

#bridge[
  *Chapter 80* steps back from the current snapshot and asks: what problems
  remain genuinely unsolved? We will examine the open challenges in compression
  theory: the gap between Shannon's entropy and what we can actually achieve
  in practice, the unsolved problem of universal compression of arbitrary data
  structures, and the deep question of whether generative decoding is "cheating"
  or a legitimate extension of rate-distortion theory. If this chapter was the
  map, the next chapter is the blank space at the edge marked _here be dragons_.
]
