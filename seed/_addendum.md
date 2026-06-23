## Supplementary Topics: Filling the Gaps

This chapter closes twelve gaps left by the main text, ranging from the deep information theory underneath compression to the 2025–2026 research frontier in neural codecs, LLM quantization, and molecular storage.

### Tightening the Theory: Universality, Typical Sets, and the Two Coding Theorems

The main text asserted that good compressors approach the entropy rate; here is *why*, and what "approach" means rigorously.

**The Asymptotic Equipartition Property (AEP)** is the engine. For an i.i.d. source $X_1,\dots,X_n$, the law of large numbers applied to $-\frac1n \log p(X_1,\dots,X_n)$ shows it converges to the entropy $H(X)$. The consequence is the **typical set**: although there are $|\mathcal{X}|^n$ possible sequences, almost all probability concentrates on roughly $2^{nH}$ of them, each with probability $\approx 2^{-nH}$. You can therefore index the typical sequences with $nH$ bits and ignore the rest with vanishing error probability. This *is* **Shannon's source coding theorem (1948)**: $H$ bits/symbol is both achievable and a lower bound. The AEP is the bridge — it converts a statement about *expected* code length into a statement about a small, near-uniform set of sequences you actually need to name.

**Lempel–Ziv universality** removes the assumption that you know $p$. LZ78 (Ziv & Lempel, 1978) parses the input into a dictionary of never-before-seen phrases. Ziv and Lempel proved that for *any* stationary ergodic source, the per-symbol code length of LZ78 converges almost surely to the entropy rate $H$ — without any model of the source. This is *universality*: one fixed algorithm asymptotically matches the optimum for an entire class of sources. It is the theoretical reason `gzip`-class tools work acceptably on text they were never tuned for.

**Two distinct theorems, often conflated.** The *source* coding theorem (above, noiseless) says how few bits losslessly represent data. The *channel* coding theorem (noisy) says how many bits per channel use can be sent reliably over a noisy channel: the **capacity** $C = \max_{p(x)} I(X;Y)$. One removes redundancy; the other adds it. They meet at Shannon's **separation theorem** (next-but-one section).

### Quantization Theory: From Lloyd–Max to Product Quantization

Lossy compression of continuous signals reduces, at its core, to **quantization** — mapping a continuum to a finite set of *reproduction points* (a *codebook*), sending only the index.

**Scalar quantization** discretizes one dimension at a time. The optimal fixed-rate scalar quantizer is the **Lloyd–Max quantizer** (Lloyd 1957/1982, Max 1960): it alternates two conditions — each *cell boundary* sits at the midpoint between neighbouring reproduction points (nearest-neighbour encoding), and each reproduction point sits at the *centroid* of its cell (the conditional mean). This is exactly k-means in 1-D, and convergence to a local optimum is guaranteed.

**Vector quantization (VQ)** quantizes blocks of samples jointly. Because it can exploit correlation *and* the geometry of high-dimensional space (sphere-packing gains), VQ beats scalar quantization at equal rate — Shannon's rate-distortion bound is only attainable in the vector limit. The **Linde–Buzo–Gray (LBG) algorithm** (Linde, Buzo & Gray, *IEEE Trans. Commun.*, Jan. 1980) generalizes Lloyd to vectors: it is k-means on a training set, designing the codebook offline.

Two refinements matter. **Dithering** adds (and at decode subtracts) a small pseudo-random signal before quantizing, decorrelating quantization error from the signal so it becomes perceptually benign noise rather than structured banding. **Trellis-coded quantization (TCQ)** (Marcellin & Fischer, 1990), the source-coding dual of trellis-coded modulation, expands the codebook and uses a Viterbi search through a trellis to pick a *sequence* of reproduction points, gaining ~0.5 bit/sample over memoryless scalar quantization at low complexity.

The lineage runs straight to modern ML: VQ codebooks reappear as the learned discrete latents of **VQ-VAE**, and **product quantization** (splitting a high-dim vector into sub-vectors, each VQ'd by a small codebook) powers billion-scale approximate nearest-neighbour search and the KV-cache compressors below.

### 1-bit / Ternary LLM Weight Quantization

A 16-bit weight is mostly wasted precision. **BitNet b1.58** ("The Era of 1-bit LLMs," Ma et al., Microsoft Research + UCAS, Feb. 2024) constrains every weight to the ternary set $\{-1, 0, +1\}$. The information-theoretic content of three equiprobable symbols is $\log_2 3 \approx 1.58$ bits — hence "b1.58." The payoff is structural: ternary weights turn the dominant matrix-multiply into *additions and subtractions*, eliminating most multipliers and slashing memory bandwidth and energy.

The decisive distinction is **native low-bit training vs. post-training quantization (PTQ)**. PTQ takes a finished full-precision model and compresses it afterward with a small calibration set: **GPTQ** (Frantar et al., 2022/ICLR 2023) uses second-order (inverse-Hessian) information to update remaining weights and minimize per-layer error down to 3–4 bits; **AWQ** (Lin et al., 2023/MLSys 2024) protects the ~1% of weight channels deemed salient by *activation* magnitude via per-channel scaling. BitNet instead trains *quantization-aware from scratch*, so the network learns weights that are good *given* the ternary constraint rather than being forced into it post hoc.

**BitNet b1.58 2B4T** (Microsoft, April 2025) is the first open-weight *natively-trained* 1.58-bit LLM at scale: 2B parameters, 4T training tokens. It reports roughly an order-of-magnitude energy reduction and ~0.4 GB non-embedding memory (vs. ~2 GB for full-precision Llama 3.2 1B) while remaining competitive with similarly-sized full-precision peers — though the gains require the dedicated `bitnet.cpp` kernels, not stock `transformers`. **BitNet v2** (April 2025) pushes to *native 4-bit activations* via an online **Hadamard transform** (`H-BitLinear`) that reshapes spiky, outlier-heavy activation distributions into near-Gaussian ones that quantize cleanly.

### The KV-Cache Compression Frontier (mid-2026)

Autoregressive LLMs cache the keys and values of every past token; this **KV cache** grows linearly with context and dominates inference memory at long context. Three lines of attack exist: *eviction* (drop "unimportant" tokens — H2O, StreamingLLM; risks losing needed context), *architectural* compression, and *post-hoc* compression of the full cache.

**DeepSeek MLA (Multi-head Latent Attention)**, introduced in DeepSeek-V2 (2024), is the architectural route: it jointly projects keys and values into a shared low-rank *latent* vector and caches only that, reconstructing per-head K/V on the fly — shrinking the cache to roughly 4–14% of standard multi-head attention. But it must be baked in at training time.

The 2026 frontier compresses the cache of *existing* models, post-hoc, treating KV vectors as a quantization/entropy-coding problem. **TurboQuant** (Zandieh, Daliri, Hadian & Mirrokni, Google Research/NYU; ICLR 2026) is *data-oblivious* rotation-based vector quantization: a random rotation concentrates each vector's per-coordinate distribution and near-decorrelates coordinates, so an optimal *scalar* quantizer applied per-coordinate becomes near-optimal for the whole vector — provably within a small constant ($\approx 2.7\times$) of the information-theoretic distortion bound, with near-zero quality loss at ~3.5 bits/channel and no calibration. **KVTC** (KV Cache Transform Coding, NVIDIA Research; arXiv Nov. 2025, ICLR 2026) borrows the classical media-codec pipeline outright — PCA decorrelation, DP-optimized adaptive bit allocation, then entropy coding (DEFLATE) — reaching up to ~20× (and 40×+ in cases) compression while preserving long-context accuracy, keeping attention-sink and recent-window tokens uncompressed.

### Video's Successor Track: ECM, Neural Coding, and Per-Title RDO

VVC/H.266 (2020) is not the end of the line. **JVET** runs two parallel exploration efforts toward the next standard.

The conventional track is the **Enhanced Compression Model (ECM)**, JVET's exploration software beyond VVC. As of mid-2026 it delivers **>25% bitrate reduction over VVC (VTM) in random-access** configuration and **up to ~40% for screen content** (text, UI, slides), with smaller intra-only gains. The neural track is **Neural Network Video Coding (NNVC)**, whose most deployment-ready module is the **NN in-loop filter** (a learned post-block filter that cleans coding artifacts before the frame is used as a reference), alongside experimental NN intra-prediction and super-resolution. These feed the anticipated VVC successor — working name **H.267** — targeting roughly **40% over VVC** and **finalization around 2028** (names and dates not yet ratified).

Standards set the *ceiling*; practical gains come from **rate-distortion optimization (RDO)** at encode time. Netflix's **per-title encoding** (2015) abandoned the one-size bitrate ladder, deriving a convex-hull-optimal resolution/bitrate ladder *per title*. The **Dynamic Optimizer** (2018) went finer — **per-shot** optimization, choosing RD-optimal parameters for each shot under a perceptual metric (VMAF), reporting ~28–37% bitrate savings at equal quality. This is rate-distortion theory applied as production engineering: spend bits where the content and the human visual system actually need them.

### Generative Image Codecs and the Rate–Distortion–Perception Tradeoff

Classical lossy compression minimizes *distortion* (e.g. MSE/PSNR) at a given *rate*. **Blau & Michaeli** ("Rethinking Lossy Compression: The Rate-Distortion-Perception Tradeoff," ICML 2019) proved a third axis is fundamental: **perception** — the statistical divergence between the *distribution* of reconstructions and the source distribution. Low distortion and high realism are *in conflict*; at a fixed rate, forcing reconstructions to look like real images (low perceptual divergence) necessarily *raises* their per-image distortion. This reframes "blurry but low-MSE" vs. "sharp but slightly wrong" as a principled, quantifiable trade, not a bug.

Generative codecs live at the low-rate, high-perception corner. **PerCo** (Careil, Muckley, Verbeek & Lathuilière; ICLR 2024) encodes an image as a vector-quantized representation plus a short text description, then *decodes with an iterative text-conditioned diffusion model* — hallucinating plausible, realistic detail consistent with the bitstream. It operates at ultra-low bitrates, from ~0.1 down to ~0.003 bpp (a Kodak image in under ~153 bytes). An open Stable-Diffusion reimplementation, **PerCo (SD)** (Körber et al., 2024), and a follow-up **PerCoV2** (2025) make it reproducible.

The decisive 2025–2026 problem is *speed*: multi-step diffusion decoding is far too slow for real use. The push is to **one-step** decoding. **OSCAR** (2025) distills a multi-step Stable-Diffusion codec into a single-step model via semantic distillation; **CoD** ("A Diffusion Foundation Model for Image Compression," 2025) trains a *compression-specific* diffusion backbone and uses Distribution Matching Distillation to obtain a one-step variant at a fraction of the training cost, excelling at ultra-low bitrate.

### Neural Audio Codecs as Tokenizers

Neural audio codecs converged on one architecture — a convolutional encoder, **residual vector quantization (RVQ)**, and a decoder — but their importance now exceeds compression. **SoundStream** (Zeghidour et al., Google, 2021) introduced the design; **EnCodec** ("High Fidelity Neural Audio Compression," Défossez et al., Meta, 2022) refined it with adversarial spectrogram losses; **DAC** (the Descript Audio Codec, Kumar et al., NeurIPS 2023) pushed fidelity further, compressing 44.1 kHz audio to ~8 kbps.

The conceptual payoff is the **codec-as-tokenizer** role, a direct expression of the *compression = modeling* theme. RVQ turns a continuous waveform into a short sequence of *discrete integer tokens*. That discrete substrate lets transformer language-modeling machinery — built for text — apply directly to audio: **AudioLM** language-models SoundStream tokens, **VALL-E** TTS language-models EnCodec tokens, and **MusicGen/VampNet** generate music over codec tokens. A good codec is a good *tokenizer* precisely because compressing well means modeling the data distribution well; the same learned discretization that minimizes bitrate also yields the units a generative model wants to predict.

### The Compression–Channel-Coding Boundary

Compression and error correction are *opposite* operations bolted together. **Source coding** removes redundancy to shrink data; **channel coding** then *re-adds structured redundancy* so the data survives a noisy channel or storage medium. **Shannon's separation theorem (1948)** justifies the "compress, then protect" pipeline: for an idealized point-to-point channel, designing the two stages independently is asymptotically optimal. The caveat matters — separation breaks at finite blocklength, under latency constraints, and for multi-user channels, which is exactly where **joint source-channel coding (JSCC)** wins.

The ECC families form a clean historical arc: **CRCs** (Peterson, 1961) *detect* errors via polynomial remainders; **Reed–Solomon** (1960) corrects symbol-level errors and underpins CDs, QR codes, and DNA storage; **LDPC** (Gallager, 1962; rediscovered mid-1990s) and **polar codes** (Arıkan, 2009 — the first provably capacity-achieving codes) drive 5G NR (data and control channels respectively). A code is **systematic** if the original message appears verbatim in the codeword with parity appended (cheap to read when uncorrupted), **non-systematic** otherwise.

Two threads in this chapter sit exactly on this boundary. **DNA storage** (next section) must add Reed–Solomon-style outer codes because synthesis/sequencing drops and mutates oligos. And **Opus DRED** (Deep REDundancy, Valin et al., IETF, 2024) is JSCC in miniature: a rate-distortion-optimized neural VAE packs up to ~1 second of *redundant* acoustic features into the bitstream at ~1/50 the normal rate, so a lost packet can be neurally resynthesized rather than concealed by guesswork.

### DNA and Molecular Data Storage

DNA stores ~2 bits per nucleotide at extraordinary density and millennia-scale durability, making it a candidate archival medium. But it is a **constrained-coding** channel: synthesis and sequencing chemistry forbid certain strings. Practical codes must hold **GC content** near 50% (DNA Fountain used 45–55%), cap **homopolymer runs** (no long `AAAAA…`; Fountain capped at 3), and avoid repeats — biochemical analogues of run-length and balance constraints. These constraints, plus oligo dropout, lower the usable capacity from a naive 2 bits/nt to ~1.83 bits/nt.

**DNA Fountain** (Erlich & Zielinski, *Science*, 2017) is the landmark. It applies **fountain codes** — *rateless* erasure codes. The family: **LT codes** (Luby, published 2002) XOR random subsets of input packets to generate a *limitless* stream of "droplets," from which the message is recovered using *any* sufficiently large subset (a few percent more than the original) — no retransmission, ideal against dropout. **Raptor codes** (Shokrollahi, 2006) prepend an outer precode to make encoding/decoding linear-time. DNA Fountain generates droplets, *screens* each candidate against the GC/homopolymer constraints (discarding violators), and maps survivors to oligos. The result reached ~1.6 bits/nt — about **85% of the ~1.83 bits/nt Shannon capacity** — at a density of **~215 petabytes per gram**, the closest approach to the DNA information bound to date.

### Delta, Diff, and Deduplication: The Across-Files Axis

LZ-family compression removes redundancy *within* a stream. A second, orthogonal axis removes redundancy *across* files and versions — usually a far larger win for backups, software updates, and source control.

**Delta compression** encodes file B as a patch against a reference A. **VCDIFF** (RFC 3284, 2002) is the standard delta *format* (copy/add/run instructions); **xdelta3** implements it. **bsdiff** (Colin Percival, 2003) specializes in *executables*, using suffix sorting to align shifted code regions and producing patches far smaller than generic diffs — the backbone of many binary auto-updaters.

**Deduplication** generalizes this to whole storage systems: identical data, stored once. The hard problem is *chunking* — fixed-size blocks fail because inserting one byte shifts every subsequent boundary. **Content-defined chunking (CDC)**, pioneered by **LBFS** (SOSP 2001), solves it with a **rolling hash** (Rabin fingerprinting): slide a small window across the data and cut a chunk boundary whenever the hash hits a magic pattern. Boundaries then track *content*, not position, so an insertion only re-chunks locally — duplicate regions hash identically and are stored once. CDC powers **Restic** and **Borg** backups. Related ideas: **Git packfiles** delta-encode each object against a similar one (then zlib); **Docker** deduplicates whole image *layers* by content digest. The axis is complementary to LZ — dedup finds the duplicate blocks; an ordinary codec then compresses each unique block.

### The Practical Engineering Layer

Information theory sets the ceiling; throughput is won in the implementation. Modern entropy coders are bottlenecked by *serial dependency*, not arithmetic. **Asymmetric Numeral Systems (ANS)**, invented by **Jarek Duda** (~2009–2014), matches arithmetic coding's compression at near-Huffman speed. **Interleaved / SIMD rANS** (Fabian Giesen, 2014) runs several independent rANS states in lockstep, breaking the dependency chain so the CPU can vectorize — the technique that makes **JPEG XL**'s entropy stage fast.

Beyond the CPU, compression is increasingly *offloaded*. **nvCOMP** (NVIDIA) provides GPU implementations of LZ4, Snappy, Deflate, GDeflate (a DEFLATE variant restructured for parallel GPU decode), and zstd, so data can be decompressed at PCIe/HBM bandwidth without a CPU round-trip. Dedicated silicon goes further: **Intel IAA** (In-Memory Analytics Accelerator) offloads Deflate plus scan/filter analytics; **Intel QAT** (QuickAssist) offloads gzip/Deflate *and* crypto; and many enterprise SSD/array controllers apply **inline LZ/zstd-class compression** transparently in the storage path. The trend is clear: entropy coding is migrating from a software inner loop to a fixed-function unit.

### The Floating-Point and Columnar Lossless Toolkit

General-purpose codecs treat data as bytes; columnar and scientific stores do better by exploiting *structure* before handing bytes to a generic backend like zstd. The standard toolkit, layered under **Parquet** and **ORC**:

- **Bit-packing** stores integers in exactly $\lceil\log_2(\max+1)\rceil$ bits rather than 32/64.
- **Frame-of-Reference (FOR)** subtracts a per-block minimum so values fit in fewer bits; **delta** and **delta-of-delta** store successive differences (and differences-of-differences), collapsing slowly-varying or monotonic columns (timestamps especially) to near-zero residuals.
- **Dictionary encoding + RLE** replaces low-cardinality string/category columns with small integer codes, then run-length-encodes the codes.
- **Roaring bitmaps** compress index/selection sets adaptively (array, bitmap, or run container per block), accelerating filters.
- **Blosc** specializes in numeric arrays: a **byte/bit-shuffle** transform groups the high-order bytes of all floats together (where they are nearly constant), exposing long runs before LZ4/zstd compress them — often turning incompressible float arrays into compressible ones. **FPC** predicts each IEEE-754 value from context and XORs, encoding the leading-zero count of the residual.

Crucially, these are **lossless**. HPC adds a distinct regime: **error-bounded lossy** compressors — **SZ** (prediction + quantization to a user error bound + Huffman) and **ZFP** (block transform + bit-plane coding) — trade a *guaranteed-bounded* numerical error for 10×+ ratios on simulation data, a different contract from the bit-exact guarantee above.

---

*File written: `/home/ezechiel203/Projects/RESEARCH/compression/.build/addendum.md` — word count ≈ 2,810.*
