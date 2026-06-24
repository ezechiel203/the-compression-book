#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Neural Audio Codecs as Tokenizers

#epigraph[
  The best interface between a waveform and a language model
  is a sequence of discrete tokens: small, fast, and full of meaning.
][Alexandre Défossez, Meta AI Research, 2022]

Here is a puzzle: you want to build a voice assistant that can not only understand
speech but generate it. One that continues a conversation in your own voice, with
your own accent and emotional colour. You have a powerful language model that
predicts sequences of text tokens beautifully. But audio is not text. A single
second of high-quality speech contains 24,000 or 44,100 individual floating-point
samples. Feeding raw samples to a language model would be like trying to read a novel
one atom at a time. How do you bridge these two worlds (the continuous waveform of
sound and the discrete token stream that language models understand)?

The answer arrived in a burst between 2021 and 2023, in three papers that together
redefined what an audio codec is for: Google's *SoundStream* (2021), Meta's *EnCodec*
(2022), and Descript's *DAC* (2023). These codecs can compress speech to a few
kilobits per second, as good as the best traditional codecs, but they deliver
something classical codecs never dreamed of: a neat stream of *discrete integers*
that a language model can treat exactly like words. Codec and tokenizer have converged
into the same device.

This chapter explains how they work, why the key ingredient is a technique called
*residual vector quantization*, and how the resulting tokens now power a remarkable
zoo of systems, from voice cloning to real-time conversational AI.

#recap[
  Chapters 56 and 57 introduced the machinery of learned compression: autoencoders,
  rate--distortion loss, quantization-as-noise, and the hyperprior that transmits
  "side information" about a learned prior. Chapter 58 showed how GAN and diffusion
  losses push codecs toward perceptual realism. Chapter 59 examined neural video
  codecs and implicit neural representations. All of this dealt with *images* and
  *video*. Now we turn to *audio*, where the same ideas land on a new substrate,
  one-dimensional waveforms sampled at 16 kHz to 48 kHz, and gain a second career
  as the foundation of audio language models.
]

#objectives((
  [Explain what residual vector quantization (RVQ) is and how it squeezes a
   continuous audio latent into a hierarchy of discrete codebook indices.],
  [Trace the architecture and key innovations of SoundStream, EnCodec, and DAC,
   noting what each one added.],
  [Describe the two roles a neural audio codec plays: as a *compressor* that shrinks
   audio files, and as a *tokenizer* that converts audio into sequences a language
   model can read and write.],
  [Explain how AudioLM, VALL-E, and Moshi use codec tokens as their working currency,
   and why semantic versus acoustic tokens matter.],
  [Identify the trade-offs (bitrate, latency, codebook collapse, compute) and
   describe the directions the field is exploring in 2025--2026.],
))

== From Waveform to Latent: the Encoder--Decoder Backbone

Every neural audio codec is, at its heart, an autoencoder for one-dimensional
signals. Recall from Chapter 56 that an autoencoder consists of two networks: an
*encoder* that maps an input to a compact *latent representation*, and a *decoder*
that reconstructs the input from that latent; Chapter 57 then put a price tag on
the latent to turn it into a learned image codec. For images the encoder operates on
two-dimensional pixel grids; for audio it operates on a time series of samples.

The encoder in SoundStream is a stack of *strided convolutional layers*. Each layer
doubles or quadruples the number of channels while halving the time dimension, so a
one-second audio clip at 24 kHz (24,000 samples) ends up as a sequence of, say,
75 frames, each a 512-dimensional vector. The ratio of input samples to output frames
is called the *stride product* or *downsampling factor*. In SoundStream it is 320,
meaning one latent frame for every 320 raw samples. The decoder is the mirror image:
strided *transposed* convolutions that upsample back to full audio rate and reconstruct
the waveform.

#gomaths("Convolution and Stride")[
  A *convolution* slides a small window of weights (a *kernel*) across a signal and
  computes a dot product at each position. For a 1-D signal of length $N$ and a
  kernel of size $k$, the output has roughly $N - k + 1$ values. A *strided*
  convolution moves the window $s$ steps at a time instead of 1, giving an output
  of length $floor((N - k) / s) + 1$. Stride is the downsampling factor in one shot:
  a stride-4 convolution on 24,000 samples gives 6,000 output positions. Stack four
  such layers with strides 2, 4, 8, and 8 and you get a total downsampling of
  $2 times 4 times 8 times 8 = 512$, compressing 24,000 samples to 47 frames.
  A *transposed convolution* (sometimes called a deconvolution) is the reverse: it
  upsamples, scattering the kernel weights for every output position, effectively
  inserting zeros between samples and then convolving with the kernel.
]

Between the encoder and decoder sits the quantizer, the only lossy step, just as
rounding is the only lossy step in JPEG's pipeline. But here the quantizer is not
a simple "round to the nearest integer"; it is a *vector quantizer* operating on
512-dimensional vectors, and it is what makes the codec a tokenizer.

== Vector Quantization: Turning Vectors into Codebook Indices

#mathrecall[
  We met *vector quantization* (VQ) in Chapter 39: instead of rounding each number on
  its own, you snap a whole tuple to the nearest entry in a learned *codebook* and
  transmit that entry's index. The LBG/Lloyd algorithm there learned the codebook from
  data. Neural codecs use exactly this idea, but the vectors being quantized are now the
  *learned latents* coming out of a neural encoder rather than raw signal samples.
]

Imagine you have a set of 1,024 reference vectors stored in a table, a *codebook*.
When the encoder outputs a 512-dimensional frame, instead of transmitting all 512
floating-point numbers, you find the *nearest neighbour* in the codebook and transmit
only its integer index (10 bits, since $log_2 1024 = 10$). The decoder looks up
that index and uses the corresponding codebook vector as input to its reconstruction
network.

#definition("Vector Quantization (VQ)")[
  Given a codebook $cal(C) = {e_1, e_2, dots, e_K}$ of $K$ vectors in
  $RR^d$, vector quantization maps an input vector $z in RR^d$ to its
  nearest codebook entry:
  $ hat(z) = "argmin"_(e_k in cal(C)) norm(z - e_k)_2 $
  The *token* (or *code*) is the index $k^star = "argmin"_k norm(z - e_k)_2$.
  Transmitting $k^star$ costs $ceil(log_2 K)$ bits.
]

This is enormously efficient. SoundStream's 75 frames per second, each indexed into
a codebook of 1,024 entries, costs $75 times 10 = 750$ bits per second. At 24 kHz,
that is the same as transmitting 750 bits for every 24,000 samples, a 32x reduction
over even 8-bit PCM, and the reconstruction from a good decoder is remarkable.

But 750 bps is very aggressive. At that rate, a single codebook is too coarse to
capture all the acoustic detail of speech and music. The elegant solution is to
*stack* quantizers in a cascade.

#gomaths("Nearest Neighbour in High Dimensions")[
  The nearest-neighbour operation $"argmin"_k norm(z - e_k)_2$ is just finding the
  closest point in a list, the same idea as finding the nearest house on a map.
  The squared Euclidean distance between two $d$-dimensional vectors
  $z = (z_1, dots, z_d)$ and $e = (e_1, dots, e_d)$ is
  $ norm(z - e)^2_2 = sum_(i=1)^d (z_i - e_i)^2 $
  For a codebook of size $K$, a brute-force search takes $O(K d)$ operations.
  With $K=1024$ and $d=512$, that is about 524,288 multiplications per frame,
  fast enough on modern hardware.
]

== Residual Vector Quantization: the Core Idea

*Residual vector quantization* (RVQ) runs multiple VQ steps in a chain, each one
refining the error left by the previous one. The idea is beautifully simple.

Step 1: quantize the encoder output $z$ to get the first token $k_1$ and the
reconstructed first-level vector $hat(z)_1 = e_(k_1)$. Compute the *residual*
$r_1 = z - hat(z)_1$ (the part the first quantizer could not capture).

Step 2: feed $r_1$ into a *second* vector quantizer with its own separate codebook,
getting token $k_2$ and reconstruction $hat(z)_2 = e_(k_2)^((2))$. Compute
$r_2 = r_1 - hat(z)_2$.

Step 3: repeat for $N_q$ levels total.

The final reconstruction adds up all the codebook entries:
$
hat(z) = hat(z)_1 + hat(z)_2 + dots + hat(z)_(N_q)
$

If each codebook has $K$ entries, one frame is represented by $N_q$ indices, and the
total bitrate for that frame is $N_q times log_2 K$ bits. By choosing $N_q$, you
slide along the rate--quality curve: more quantizers = higher bitrate = better quality.
SoundStream uses $N_q = 1$ to $32$ quantizers and a single model covers bitrates from
3 kbps to 24 kbps simply by choosing how many levels to include at runtime.

#keyidea[
  Residual vector quantization is just VQ applied repeatedly to the leftover error.
  Each new codebook captures a finer layer of detail that the previous ones missed.
  The first codebook gets the big shapes, the second gets the grain, the third gets
  the texture, and so on. The decoder sums up all the contributions to reconstruct
  a rich signal from a short sequence of small integers.
]

#fig([Residual vector quantization with three codebooks. The encoder output $z$ is
  approximated by a sum of three codebook entries, with each codebook refining the
  residual of the previous step.], cetz.canvas({
  import cetz.draw: *
  // encoder output
  rect((-0.5, 1.5), (0.5, 2.5), fill: rgb("#e8f4f8"), stroke: 0.8pt)
  content((0, 2.0))[$z$]
  // arrows going to three VQ boxes
  line((0, 1.5), (0, 1.1), mark: (end: ">"))
  // VQ1
  rect((-1.5, 0.0), (-0.5, 1.0), fill: rgb("#d0e8d0"), stroke: 0.8pt)
  content((-1.0, 0.5), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[VQ1])))
  line((0, 1.0), (-1.0, 1.0), mark: (end: ">"))
  line((-1.0, 0.0), (-1.0, -0.4), mark: (end: ">"))
  content((-1.0, -0.7))[$k_1$]
  // residual r1 arrow
  line((0, 1.0), (0.5, 1.0))
  line((0.5, 1.0), (0.5, 0.5))
  // VQ2
  rect((-0.2, 0.0), (0.8, 1.0), fill: rgb("#d0e8d0"), stroke: 0.8pt)
  content((0.3, 0.5), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[VQ2])))
  line((0.5, 0.5), (0.3, 0.5))
  line((0.3, 0.0), (0.3, -0.4), mark: (end: ">"))
  content((0.3, -0.7))[$k_2$]
  // residual r2 arrow
  line((0.8, 0.5), (1.3, 0.5))
  line((1.3, 0.5), (1.3, 0.0))
  // VQ3
  rect((0.8, 0.0), (1.8, 1.0), fill: rgb("#d0e8d0"), stroke: 0.8pt)
  content((1.3, 0.5), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[VQ3])))
  line((1.3, 0.0), (1.3, -0.4), mark: (end: ">"))
  content((1.3, -0.7))[$k_3$]
  // label at top
  content((0.0, 3.0), text(size: 9pt)[Encoder output])
  content((0.0, -1.2), text(size: 9pt)[Token stream per frame])
}))

=== Training the Codebooks

Training is the tricky part. The nearest-neighbour operation ("find the closest
codebook vector") has no gradient. You cannot just run backpropagation through it
because there is no smooth slope to follow when the output suddenly jumps from one
codebook entry to another.

The standard fix, introduced in the original VQ-VAE paper (van den Oord, Vinyals,
and Kavukcuoglu, 2017, whose codebook idea we traced in Chapter 39 and whose
gradient trick reappeared in Chapter 57) and adopted by all three codecs, is the
*straight-through estimator* (STE). During the *forward* pass, the quantized vector
$hat(z)$ is used as normal. During the *backward* pass (gradient descent), the
gradient that would have been sent to $hat(z)$ is passed directly to the pre-quantized
encoder output $z$, as if the quantization step were the identity function. The
gradient "passes straight through the rounding."

The codebook entries themselves are updated by an *exponential moving average* of
the encoder outputs that were assigned to each entry, a soft form of the
$k$-means algorithm. A *commitment loss* pushes the encoder outputs to stay close
to the chosen codebook entry, preventing the encoder from wildly jumping between
entries and making training unstable.

#gomaths("Exponential Moving Average (EMA)")[
  An EMA keeps a running estimate $mu$ of a value by blending old and new:
  $ mu arrow.l (1 - gamma) mu + gamma x_"new" $
  where $gamma in (0,1)$ is the *decay* (typically 0.99). This gives recent
  observations more weight without storing the full history. In RVQ training, the
  codebook entry for code $k$ is updated as the EMA of all encoder outputs
  assigned to it during a minibatch.
]

One persistent problem is *codebook collapse*: some codebook entries get chosen
repeatedly while others are never used, wasting capacity. Both EnCodec and DAC
introduced tricks to fight this, including random codebook resets (replacing unused entries
with randomly selected encoder outputs) and improved initialisation. DAC
especially made codebook utilisation a design priority.

== SoundStream (2021): the First Universal Neural Audio Codec

Google's SoundStream, published by Neil Zeghidour, Alejandro Luebs, Ahmed Omran,
Jan Skoglund, and Marco Tagliasecca in 2021, was the first neural codec to match
or beat classical speech codecs (Opus at the same bitrate) on general audio content
including speech, music, and environmental sounds.

#algo(
  name: "SoundStream",
  year: "2021",
  authors: "Zeghidour, Luebs, Omran, Skoglund, Tagliasecca (Google)",
  aim: "End-to-end neural audio codec for speech and general audio using RVQ; operates at 3--18 kbps at 24 kHz.",
  complexity: "Encoder: causal convolutions, stride 320. Decoder: mirrored transposed convolutions. RVQ: $N_q$ = 1--32.",
  strengths: "First universal codec; variable bitrate via quantizer dropout; real-time on a single CPU; strong perceptual quality at low rates.",
  weaknesses: "No Transformer refinement; no real-time stereo support in the original; codebook collapse can occur without careful training.",
  superseded: "EnCodec (2022) and DAC (2023) on quality; Mimi (2024) for language-model use.",
)[
  The most important design choice beyond the architecture itself was *quantizer
  dropout*: during training, the model randomly drops some of the later RVQ quantizers.
  This forces the decoder to learn to reconstruct good audio from as few as one quantizer
  level, so at inference, you simply choose how many levels to use and the same model
  works at any bitrate in a wide range. No retraining needed.

  Training uses a combination of losses: a reconstruction loss in the waveform domain
  (L1 distance on raw samples and on log-mel spectrograms) and a *discriminator* loss
  from a multi-scale spectrogram discriminator, a simplified GAN loss that rewards the
  decoder for producing audio that "sounds real" rather than just minimising a pixel-wise
  number. This perceptual component is important at low bitrates.
]

#history[
  Before SoundStream, the art of neural speech coding had progressed through LPCNet
  (2019, Valin and Skoglund), which combined a classical linear predictive coder
  with a recurrent neural network for the residual, a hybrid approach rather than
  a pure end-to-end one. SoundStream was the first fully end-to-end neural codec to
  compete with and then beat classical codecs across diverse audio content.
]

== EnCodec (2022): Streaming, Stereo, and Entropy Coding

Meta's EnCodec, by Alexandre Défossez, Jade Copet, Gabriel Synnaeve, and Yossi Adi
(2022), kept the SoundStream architecture and RVQ core but added several improvements.

The most important is a *streaming* design. SoundStream could already run in real
time, but EnCodec carefully made the encoder *causal*: each output frame depends
only on past input frames, never on future ones. This is essential for live
communication: you cannot wait for the whole audio file before starting to encode.

EnCodec also introduced *stereophonic support* at 48 kHz (music fidelity rather
than just voice fidelity) and a lightweight *language model entropy coder*
on top of the RVQ indices.

#mathrecall[
  A *Transformer* (introduced in Chapter 59) is a neural network that processes a
  sequence by letting every position "attend" to every other position, so each output
  can depend on the whole context. Trained to predict the next item, it becomes a
  probability model for sequences, exactly what an entropy coder needs.
]

After the RVQ step produces a stream of integers, a tiny
Transformer reads the sequence and predicts the probability of each next index,
then passes those probabilities to an arithmetic coder (Chapter 26). This "post-hoc"
entropy coding squeezes an additional 20--40% out of the bitstream, because adjacent
RVQ codes are correlated. The model exploits that correlation the same way a
language model exploits word co-occurrence.

#algo(
  name: "EnCodec",
  year: "2022",
  authors: "Défossez, Copet, Synnaeve, Adi (Meta AI Research)",
  aim: "High-fidelity streaming neural audio codec with RVQ + lightweight Transformer entropy coding; targets 1.5--24 kbps.",
  complexity: "Causal convolutions + RVQ up to 8 quantizers; 24 kHz mono or 48 kHz stereo. Entropy coder: small Transformer.",
  strengths: "Real-time streaming; stereo support; 20--40% extra compression via entropy coding; open-sourced; became default tokenizer for VALL-E and AudioLM.",
  weaknesses: "Entropy coder adds latency; codebook collapse occurs without care; at 1.5 kbps stereo music quality is limited.",
  superseded: "DAC (2023) on reconstruction quality for music; Mimi (2024) for semantic--acoustic disentanglement.",
)[
  EnCodec shipped with two public checkpoints, one for 24 kHz mono (speech) and one
  for 48 kHz stereo (music), and released the model weights on Hugging Face, which
  accelerated adoption dramatically. Within months, nearly every audio language model
  paper was built on EnCodec tokens.
]

#checkpoint[
  EnCodec at 6 kbps with 8-bit codebooks and $N_q = 8$ quantizers runs at 24 kHz.
  How many RVQ tokens per second does the encoder produce?
][
  The frame rate is $24000 / 320 = 75$ frames per second, and each frame produces
  $N_q = 8$ tokens, so $75 times 8 = 600$ tokens per second total.
  At 8 bits each, that is $600 times 8 = 4800$ bits per second = 4.8 kbps,
  and with the entropy coder's ~20% gain the effective rate reaches ~6 kbps.
]

== DAC (2023): Codebook Utilisation and Wideband Quality

Descript's *Descript Audio Codec* (DAC), published by Kumar et al. in 2023, addressed
a persistent weakness of both predecessors: *codebook collapse* at higher sample rates
and with music content. DAC made three key contributions.

*Better codebook training.* DAC initialises the codebook with a batch of encoder
outputs (rather than random vectors) and uses random restarts: any codebook entry
that has not been used recently is teleported to a randomly chosen encoder output.
This keeps every entry in use and maximises the information each code carries.

*Periodic activations.* Instead of standard ReLU nonlinearities, DAC uses *snake
activations* - a nonlinearity of the form $x + (1/alpha) sin^2(alpha x)$, where the
learnable parameter $alpha$ sets the frequency. The plain $x$ term keeps the gradient
healthy (just like ReLU's straight half), while the $sin^2$ term injects a built-in
periodicity, so the network does not have to laboriously synthesise oscillation out of
piecewise-linear pieces. Speech and music are full of periodic structure (vowels,
musical notes, drum hits), and an activation that is *itself* periodic represents that
structure far more efficiently.

*Wideband fidelity.* DAC supports 44.1 kHz, the CD standard, with 9 residual
quantizers, achieving near-transparent quality on music. This was the first open
neural codec that could plausibly replace a lossless file at high enough bitrate.

#algo(
  name: "DAC (Descript Audio Codec)",
  year: "2023",
  authors: "Kumar, Kumar, Kumar, Musikant, Reganti, Khatri, et al. (Descript)",
  aim: "Universal neural audio codec with improved codebook utilisation, periodic activations, and support for 44.1 kHz audio.",
  complexity: "RVQ with 9 quantizers, 1024-entry codebooks. Encoder strides: 2×4×8×8 = 512. Snake activations.",
  strengths: "Near-transparent music quality at 44.1 kHz; excellent codebook utilisation; open weights on Hugging Face; used widely as a research baseline.",
  weaknesses: "Not designed for streaming (non-causal); heavier than SoundStream/EnCodec at comparable bitrate; no built-in entropy coder.",
  superseded: "Mimi (2024) for language-model-friendly tokenisation; specialist music codecs for narrowly musical use cases.",
)[
  DAC became the standard ablation baseline for neural audio codec research in 2024--2025.
  Its open weights, clear code, and strong quality across content types made it the
  "ImageNet ResNet" of the audio codec world, the thing everything is compared against.
]

#fig([Comparison of neural audio codec architectures. SoundStream, EnCodec, and DAC all
  share the encoder--RVQ--decoder skeleton; they differ in encoder depth, activation
  functions, training losses, and codebook management.], cetz.canvas({
  import cetz.draw: *
  // Three column headers
  content((-3.2, 3.5), box(width: 2.0cm, align(center, text(weight: "bold", size: 8pt)[SoundStream])))
  content((0.0, 3.5), box(width: 2.0cm, align(center, text(weight: "bold", size: 8pt)[EnCodec])))
  content((3.2, 3.5), box(width: 2.0cm, align(center, text(weight: "bold", size: 8pt)[DAC])))
  // Common backbone
  for x in (-3.2, 0.0, 3.2) {
    rect((x - 1.2, 0.6), (x + 1.2, 1.3), fill: rgb("#d8ecf8"), stroke: 0.7pt)
    content((x, 0.95), box(width: 2.0cm, inset: 1pt, align(center, text(size: 8pt)[Strided Encoder])))
    rect((x - 1.2, -0.3), (x + 1.2, 0.4), fill: rgb("#d0e8d0"), stroke: 0.7pt)
    content((x, 0.05), box(width: 2.0cm, inset: 1pt, align(center, text(size: 8pt)[RVQ])))
    rect((x - 1.2, -1.2), (x + 1.2, -0.5), fill: rgb("#fce8d8"), stroke: 0.7pt)
    content((x, -0.85), box(width: 2.0cm, inset: 1pt, align(center, text(size: 8pt)[Transp. Dec.])))
    line((x, 0.6), (x, 0.4), mark: (end: ">"))
    line((x, -0.3), (x, -0.5), mark: (end: ">"))
  }
  // Distinctive labels
  content((-3.2, -1.7), box(width: 2.0cm, inset: 1pt, align(center, text(size: 7.5pt)[Variable $N_q$])))
  content((0.0, -1.7), box(width: 2.0cm, inset: 1pt, align(center, text(size: 7.5pt)[Causal + Entropy])))
  content((3.2, -1.7), box(width: 2.0cm, inset: 1pt, align(center, text(size: 7.5pt)[Snake + 44.1 kHz])))
}))

== The Token Hierarchy: Acoustic vs. Semantic

The RVQ structure is more than an engineering convenience: it creates a natural
*hierarchy of information* in the tokens. The first quantizer captures the
coarsest, most important structure. The later ones add progressively finer detail.

Researchers noticed something striking: the *first* RVQ token per frame tends to
encode *semantic* content (what the speaker is saying, the words, the
linguistic meaning). The later tokens carry *acoustic* content: timbre, pitch,
speaking style, room acoustics. This happens because the first quantizer faces the
hardest task (reconstruct the audio from one vector), so it latches onto the most
predictable, most compressible features, which happen to be the linguistic ones.
The rest is refined by subsequent quantizers.

#misconception[
  "All RVQ tokens are equivalent; they all carry the same kind of audio information."
][
  The tokens form a strict hierarchy. Token stream 1 (the coarsest quantizer) contains
  mostly *semantic* information: what is being said. Token streams 2--8 carry *acoustic*
  details: how it sounds (the speaker's voice, room acoustics, emotion). This hierarchy
  is not designed in; it *emerges* from the rate--distortion pressure of training.
  Systems like AudioLM exploit this by using separate models for the two levels.
]

This hierarchy was formalised in *SpeechTokenizer* (Zhang et al., published at ICLR 2024),
which explicitly *forced* the first RVQ quantizer to match a self-supervised semantic
representation (from the HuBERT model) using a distillation loss. The result: a codec
whose first token stream is a reliable semantic token, and whose subsequent streams
handle only acoustics. SpeechTokenizer proved that you could *engineer* the hierarchy
rather than just hoping it would emerge.

== From Codec to Tokenizer: AudioLM, VALL-E, and the Audio LLM Era

The conceptual leap that made neural audio codecs matter far beyond compression
happened in 2022, when Google's *AudioLM* paper (Borsos et al.) showed that you
could treat audio generation as a *language modelling* problem operating entirely
on codec tokens.

The idea is straightforward: run a SoundStream encoder on hours of audio, collect
all the RVQ token streams, train a Transformer language model to predict the next
token (exactly as GPT predicts the next word), and to generate audio, sample from
this model and run the SoundStream decoder. The result: a model that can extend
a snippet of audio in a way that is remarkably natural,
preserving the speaker's voice, musical style, and long-range structure like verse
and chorus.

AudioLM actually used two models in sequence. First, a *semantic* model (operating
on tokens from a self-supervised speech model, wav2vec-BERT) generated the
high-level "what happens next." Then an *acoustic* model (operating on SoundStream
tokens) translated those semantic tokens into full waveform tokens. The two-stage
hierarchy reflects the acoustic vs. semantic split we saw in the RVQ structure.

*VALL-E* (Wang et al., Microsoft, January 2023) showed perhaps the most dramatic
application: zero-shot voice cloning. The system treats text-to-speech as a
conditional codec-token language model: given a transcript and just three seconds
of a target speaker's voice (encoded as EnCodec tokens), predict the EnCodec tokens
that a speaker would produce reading the transcript in that voice, then decode.
VALL-E's results surprised the research community. Three seconds of audio was enough
to imitate not just a voice but emotional tone and room acoustics.

#aside[
  VALL-E uses EnCodec tokens because EnCodec was the open neural codec available
  when the paper was written. The linguistic layer uses an autoregressive Transformer
  to generate the first RVQ stream token-by-token; the acoustic layers (streams 2--8)
  are generated *in parallel* by a non-autoregressive model conditioned on stream 1.
  This hybrid approach speeds up generation enormously: you only need to do the slow
  sequential decoding for the small semantic token stream.
]

By 2023 and 2024, the pattern had become standard: every major audio language model
used a neural codec as its tokenisation layer. MusicLM, AudioPaLM, VoiceCraft,
SoundStorm, VoiceLM (all of them) convert audio to codec tokens, run a language
model, and decode. The neural audio codec had become the audio equivalent of the
text tokenizer: the irreplaceable bridge between a continuous signal and a language
model's discrete vocabulary.

#gopython("List of lists and nested indexing")[
  RVQ produces one list of tokens per quantizer level, per frame. In Python the
  natural representation is a list of lists (or a 2-D array):

  ```python
  # tokens[q][t] = token index for quantizer q, time frame t
  tokens: list[list[int]] = [
      [23, 7, 104, 2, ...],   # quantizer 0 (semantic-ish)
      [512, 301, 88, 7, ...], # quantizer 1
      [1020, 5, 67, 903, ...],# quantizer 2
      # ... up to N_q - 1
  ]

  n_q    = len(tokens)            # number of quantizer levels
  n_frames = len(tokens[0])       # number of time frames
  # Reconstruct total from index: look up e[q][k] and sum
  ```

  Indexing `tokens[q][t]` gives the integer code for quantizer level `q` at
  time frame `t`. With $N_q = 8$ levels and 75 frames/s, one second of audio
  becomes an 8x75 array of integers: 600 small numbers instead of 24,000
  floating-point samples.
]

== A Worked Encoding Example

Let us trace one frame through a three-level RVQ to make the arithmetic concrete.
Suppose the encoder has produced the vector:
$
z = (1.2,  -0.8,  2.1)
$
(a 3-dimensional latent for clarity; real codecs use 512-dimensional vectors).

Each codebook has 4 entries ($K=4$, costing $log_2 4 = 2$ bits per level):

#table(
  columns: (auto, 1fr, 1fr, 1fr),
  [*Code*], [*Codebook 1*], [*Codebook 2*], [*Codebook 3*],
  [$k=0$], [$(0.0, -0.5, 1.8)$], [$(1.0, -0.3, 0.2)$], [$(0.1, -0.05, 0.08)$],
  [$k=1$], [$(1.0, -1.0, 2.0)$], [$(0.3, -0.1, 0.4)$], [$(0.0, 0.1, -0.1)$],
  [$k=2$], [$(0.5, 0.5, 1.0)$], [$(0.5, 0.2, 0.1)$], [$(0.2, 0.0, 0.15)$],
  [$k=3$], [$(1.5, -0.5, 2.5)$], [$(0.2, -0.4, 0.3)$], [$(0.0, -0.1, 0.05)$],
)

*Level 1.* Compute squared distances from $z = (1.2, -0.8, 2.1)$ to each codebook-1 entry:
- $k=0$: $(1.2-0.0)^2 + (-0.8+0.5)^2 + (2.1-1.8)^2 = 1.44 + 0.09 + 0.09 = 1.62$
- $k=1$: $(0.2)^2 + (0.2)^2 + (0.1)^2 = 0.04 + 0.04 + 0.01 = 0.09$ ← nearest
- $k=2$: $(0.7)^2 + (1.3)^2 + (1.1)^2 = 0.49 + 1.69 + 1.21 = 3.39$
- $k=3$: $(0.3)^2 + (0.3)^2 + (0.4)^2 = 0.09 + 0.09 + 0.16 = 0.34$

Nearest: $k_1 = 1$, reconstruction $hat(z)_1 = (1.0, -1.0, 2.0)$.
Residual: $r_1 = z - hat(z)_1 = (0.2, 0.2, 0.1)$.

*Level 2.* Nearest codebook-2 entry to $r_1 = (0.2, 0.2, 0.1)$:
- $k=0$: $(0.8)^2 + (0.5)^2 + (0.1)^2 = 0.64 + 0.25 + 0.01 = 0.90$
- $k=1$: $(0.1)^2 + (0.3)^2 + (0.3)^2 = 0.01 + 0.09 + 0.09 = 0.19$
- $k=2$: $(0.3)^2 + (0.0)^2 + (0.0)^2 = 0.09 + 0.0 + 0.0 = 0.09$  ← nearest (tied; pick $k=2$)
- $k=3$: $(0.0)^2 + (0.6)^2 + (0.2)^2 = 0.0 + 0.36 + 0.04 = 0.40$

Nearest: $k_2 = 2$, reconstruction $hat(z)_2 = (0.5, 0.2, 0.1)$.
Residual: $r_2 = (0.2-0.5, 0.2-0.2, 0.1-0.1) = (-0.3, 0.0, 0.0)$.

*Level 3.* Nearest codebook-3 entry to $r_2 = (-0.3, 0.0, 0.0)$:
- $k=0$: $(0.4)^2 + (0.05)^2 + (0.08)^2 approx 0.173$
- $k=1$: $(0.3)^2 + (0.1)^2 + (0.1)^2 = 0.11$ ← nearest
- $k=2$: $(0.5)^2 + (0.0)^2 + (0.15)^2 approx 0.272$
- $k=3$: $(0.3)^2 + (0.1)^2 + (0.05)^2 approx 0.1025$

Nearest: $k_3 = 1$, reconstruction $hat(z)_3 = (0.0, 0.1, -0.1)$.

*Final reconstruction:*
$hat(z) = hat(z)_1 + hat(z)_2 + hat(z)_3 = (1.0+0.5+0.0, -1.0+0.2+0.1, 2.0+0.1-0.1) = (1.5, -0.7, 2.0)$

The transmitted token stream for this frame is just $(1, 2, 1)$, three 2-bit
codes = 6 bits total. Original: $3 times 32 = 96$ bits floating-point. Compression
ratio: 16x. The reconstruction error is $z - hat(z) = (-0.3, -0.1, 0.1)$, small
enough that a well-trained decoder will produce excellent audio.

#gopython("NumPy and argmin")[
  In real code, the nearest-neighbour search uses vectorised operations. The following
  sketch uses NumPy (which provides fast array operations; we introduced it in
  Chapter 56):

  ```python
  import numpy as np

  def rvq_encode(z: np.ndarray,
                 codebooks: list[np.ndarray],
                 n_q: int) -> list[int]:
      """Encode one latent frame z with n_q RVQ levels.

      codebooks[q] has shape (K, d) - K entries of dimension d.
      Returns a list of n_q integer indices.
      """
      tokens: list[int] = []
      residual = z.copy()
      for q in range(n_q):
          cb = codebooks[q]               # shape (K, d)
          # squared distances: (K,) vector
          dists = np.sum((cb - residual) ** 2, axis=1)
          k_star = int(np.argmin(dists))
          tokens.append(k_star)
          residual = residual - cb[k_star]   # update residual
      return tokens

  def rvq_decode(tokens: list[int],
                 codebooks: list[np.ndarray]) -> np.ndarray:
      """Reconstruct latent from RVQ token list."""
      d = codebooks[0].shape[1]
      recon = np.zeros(d)
      for q, k in enumerate(tokens):
          recon += codebooks[q][k]
      return recon
  ```

  `np.argmin(dists)` returns the index of the smallest value in the array,
  exactly the nearest-neighbour search. Both encode and decode run in microseconds
  per frame.
]

== Mimi and the Moshi System (2024): Merging Semantics and Acoustics

The most architecturally sophisticated open neural audio codec as of 2025 is
*Mimi*, developed by the French AI lab Kyutai as part of their *Moshi* full-duplex
spoken dialogue system (released in September 2024). Mimi is the first codec to
*combine* semantic and acoustic information in a principled, streaming-compatible way.

Mimi builds on the EnCodec architecture but adds a Transformer in both the encoder
and the decoder, increasing the model's ability to capture long-range dependencies
in speech. More importantly, it is trained with a *distillation loss* that pushes
the first codebook to produce tokens that match the representations of WavLM, a
large self-supervised model trained to understand speech content. This is the same
"semantic distillation" idea as SpeechTokenizer, but applied to a streaming,
low-latency codec.

The result: Mimi encodes one second of speech into just 12.5 RVQ frames (an
8x lower frame rate than EnCodec at the same quality), with 8 codebooks, for a
total bitrate of only 1.1 kbps, far below any classical codec at this quality.
The first token stream is semantic; tokens 2--8 are acoustic.

Moshi itself uses Mimi as its tokenizer and runs an "inner monologue": an LLM
simultaneously generating text tokens and acoustic tokens, operating in real time
with under 200 milliseconds of latency. It was the first fully open conversational
AI system capable of full-duplex dialogue: the model listens and speaks at the same
time, without waiting for a turn-taking signal.

#history[
  The full-duplex spoken dialogue problem had been considered nearly impossible for
  neural systems: how do you interrupt, respond to interruption, and maintain
  conversational coherence when both sides speak simultaneously? Moshi solved
  this by processing *two* parallel audio streams (the user's voice and the
  system's own voice) as two interleaved token sequences, letting a single LLM
  reason about both at once. The 200 ms latency was comparable to a satellite
  phone call, not quite natural conversation, but the first neural system in
  that range.
]

== The Semantic--Acoustic Split in Practice

The distinction between semantic and acoustic tokens has concrete consequences for
how audio LLMs are designed. Consider the two extreme cases.

A *pure acoustic* codec (like a vanilla SoundStream without distillation) produces
tokens that capture sound very faithfully but have no particular linguistic structure.
A language model trained on these tokens must simultaneously learn linguistics and
acoustics, a harder joint problem. Generation tends to produce very natural-sounding
audio but is harder to control for *content*.

A *semantic-only* tokenizer (like a discrete unit from a HuBERT model) produces
tokens with strong linguistic structure (you can decode them to text roughly) but
loses speaker identity, emotion, and paralinguistic detail. Generation is controllable
but sounds like a robot.

The *hybrid* approach (SpeechTokenizer, Mimi) uses the RVQ hierarchy to put semantics
in stream 1 and acoustics in streams 2--$N_q$. You can then run a separate generative
model on stream 1 (small, fast, text-aligned) and a second model on streams 2--$N_q$
conditioned on stream 1 (handling voice style). This is exactly AudioLM's two-stage
design, now made cleaner by a codec that explicitly disentangles the two.

#keyidea[
  The two-level hierarchy, one semantic token stream plus several acoustic token
  streams, is the standard architecture for neural audio language models as of
  2025. The semantic stream is small (low bitrate, linguistically structured,
  easy to condition on text), and the acoustic streams are generated in parallel
  conditioned on the semantic stream. The neural audio codec is the infrastructure
  that makes this hierarchy possible.
]

#fig([Semantic vs. acoustic token streams in a hybrid codec. Stream 0 (first RVQ
  level, distilled toward a semantic teacher) controls linguistic content. Streams
  1 through $N_q - 1$ refine acoustic detail. An audio LLM generates stream 0
  autoregressively, then fills in acoustic streams in parallel.], cetz.canvas({
  import cetz.draw: *
  // Waveform input
  rect((-0.5, 4.2), (0.5, 4.9), fill: rgb("#e8e8f8"), stroke: 0.7pt)
  content((0, 4.55), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[Audio in])))
  line((0, 4.2), (0, 3.8), mark: (end: ">"))
  // Encoder
  rect((-1.2, 3.2), (1.2, 3.8), fill: rgb("#d8ecf8"), stroke: 0.7pt)
  content((0, 3.5), box(width: 2.0cm, inset: 1pt, align(center, text(size: 8pt)[Encoder + Transf.])))
  line((0, 3.2), (0, 2.8), mark: (end: ">"))
  // RVQ box
  rect((-1.8, 2.0), (1.8, 2.8), fill: rgb("#d0e8d0"), stroke: 0.7pt)
  content((0, 2.4), box(width: 3.2cm, inset: 1pt, align(center, text(size: 8pt)[Residual VQ])))
  // Output streams
  line((-1.2, 2.0), (-1.8, 1.2), mark: (end: ">"))
  line((0, 2.0), (0, 1.2), mark: (end: ">"))
  line((1.2, 2.0), (1.8, 1.2), mark: (end: ">"))
  // Stream labels
  rect((-2.3, 0.5), (-1.3, 1.2), fill: rgb("#ffe8d0"), stroke: 0.7pt)
  content((-1.8, 0.85), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[Stream 0])))
  content((-1.8, 0.35), box(width: 1.2cm, inset: 1pt, align(center, text(size: 7.5pt)[semantic])))
  rect((-0.5, 0.5), (0.5, 1.2), fill: rgb("#e8d0e8"), stroke: 0.7pt)
  content((0, 0.85), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[Stream 1])))
  content((0, 0.35), box(width: 1.0cm, inset: 1pt, align(center, text(size: 7.5pt)[acoustic])))
  rect((1.3, 0.5), (2.3, 1.2), fill: rgb("#e8d0e8"), stroke: 0.7pt)
  content((1.8, 0.85), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[Str. $N_q-1$])))
  content((1.8, 0.35), box(width: 1.0cm, inset: 1pt, align(center, text(size: 7.5pt)[acoustic])))
}))

== WavTokenizer and the Single-Codebook Frontier (2024--2025)

The extreme end of compression is asking whether one single integer per short time
slice is workable, rather than eight per frame. This is the territory explored by
*WavTokenizer* (Pan et al., 2024). WavTokenizer uses a single vector quantizer (not
residual) but with a *much larger* codebook ($K = 4096$ or $K = 8192$ entries) and a
*much wider* context window in the encoder, allowing each code to represent many more
acoustic features at once. At 40 tokens per second with a single quantizer, WavTokenizer
encodes one second of 24 kHz audio into 40 integers, a codebook sequence small
enough to fit inside a standard language model's context window alongside text with
room to spare.

The quality of WavTokenizer is surprisingly competitive with multi-level RVQ codecs
at the same token budget, showing that the residual hierarchy is one design choice
among many, not a fundamental requirement. The field is converging on a pragmatic
question: for a given generation-model budget (context length, compute, latency),
what tokeniser produces the best trade-off between sequence length and acoustic
fidelity?

#aside[
  There is a deep parallel here with the history of text tokenisation. Early language
  models used character-level tokens (one integer per character, maximum granularity,
  very long sequences). Then word-level tokens reduced sequence length but gave a huge
  vocabulary. Byte-pair encoding (BPE), a scheme that starts from single bytes and
  repeatedly merges the most frequent adjacent pair into a new token (the same
  greedy "merge what recurs" instinct behind the dictionary coders of Chapter 28),
  found a middle ground. Audio
  tokenisation is having exactly the same debate: frame-level vs. chunk-level, RVQ
  hierarchy vs. single codebook, temporal resolution vs. vocabulary size. The answers
  will not be the same as for text (audio has physical structure that text does not),
  but the design pressures are similar.
]

== Trade-offs and Open Problems (2025--2026)

Neural audio codecs have transformed both compression and audio AI, but they come
with real costs and open questions.

*Latency.* A streaming codec must encode the audio in real time and add only a
fixed look-ahead (the algorithmic delay). EnCodec's 320-sample stride at 24 kHz
gives 13 ms of delay per frame, acceptable for a live call. But the Transformer
entropy coder in EnCodec, and the Transformer encoder in Mimi, add more compute.
Achieving sub-100 ms round-trip delay while maintaining quality remains an active
design challenge.

*Codebook collapse.* Despite EMA updates and codebook resets, some codebooks still
underutilise entries. Recent work (2024--2025) has explored *finite scalar
quantization* (FSQ), which replaces the codebook with per-dimension bounded integers
(e.g., each of 8 dimensions is quantized to $\{-2, -1, 0, 1, 2\}$, five levels, giving
$5^8 = 390,625$ effective codes), eliminating the collapse problem entirely.

*Reproducibility and streaming.* Neural codecs use floating-point arithmetic. Two
machines with different GPU architectures can produce different RVQ token streams
for the same audio because floating-point rounding differs. This is harmless for
compression (transmit the tokens and decode them on the same machine) but
catastrophic for a protocol where sender and receiver must agree. The audio
arrives as tokens, and the decoder must produce identical results. This is the
analogue of the "reproducible floating-point" problem in learned image coding
(Chapter 57) and remains unsolved for real deployment.

*Energy and hardware.* A neural codec running in real time at 24 kHz on a smartphone
DSP chip is feasible in 2025 only with careful model quantisation (model compression,
Chapter 63). SoundStream was designed to run on a single CPU core; Mimi requires
a modest GPU. Democratising neural audio at device level is an active engineering
frontier.

*Evaluation.* Classical audio codecs have a well-understood evaluation toolkit:
PESQ, VISQOL, MOS (mean opinion score from human listeners). Neural codecs add a
new goal, namely how well their tokens serve downstream audio language models,
for which there is no agreed metric. The *Codec-SUPERB* benchmark (2024) began
addressing this by testing codecs on multiple downstream tasks, but a universal
"tokenization quality" metric remains elusive.

#pitfall[
  Neural audio codecs are *lossy compressors*, not lossless ones. Encoding and
  decoding a voice recording will not recover the original waveform sample-by-sample.
  For archival, legal, forensic, or medical use, you must use a lossless format
  (FLAC, WAV). Neural codecs optimise *perceptual* quality, not sample fidelity.
]

== The Big Picture: Codec and Tokenizer Converge

We began this chapter with a puzzle: how do you feed audio to a language model?
The answer turned out to require reimagining what a codec *is*. For fifty years a
codec was a compression device: it shrank files for storage and transmission. Neural
audio codecs are still that. But they are simultaneously *tokenizers*: they convert
continuous waveforms into discrete sequences that sit comfortably inside the vocabulary
of a transformer language model.

This convergence matters. It means that every advance in language modelling,
better architectures, better training data, better scaling laws, can now be
applied directly to audio. The spectacular results of VALL-E, AudioLM, MusicLM, and
their successors are not primarily results about audio; they are results about language
modelling, enabled by a codec that translates audio into the right input format.

#keyidea[
  A neural audio codec is two things at once: a *compressor* (shrinks audio for
  storage and streaming) and a *tokenizer* (converts audio into a form that a
  language model can read and write). The residual VQ quantizer is the hinge that
  makes both uses possible. The token stream's discrete, low-rate nature lets an
  LLM treat audio generation exactly like text generation.
]

#scoreboard(caption: "Running compression scoreboard (audio, one minute of 24 kHz speech)",
  [Raw PCM 24 kHz 16-bit], [2,880,000], [1.0×], [Uncompressed baseline],
  [FLAC lossless], [1,670,000], [1.72×], [Lossless; perfect reconstruction],
  [Opus 24 kbps (classical)], [180,000], [16×], [Lossy; excellent speech quality],
  [SoundStream 6 kbps], [45,000], [64×], [Neural; competitive with Opus at 24 kbps],
  [EnCodec 3 kbps], [22,500], [128×], [Neural + entropy coding; strong quality],
  [Mimi 1.1 kbps], [8,250], [349×], [Neural; streaming; 12.5 Hz frame rate],
)

#takeaways((
  [Residual vector quantization (RVQ) stacks multiple codebook lookups in series, each
   refining the residual of the previous, to represent a continuous audio latent as a
   short sequence of discrete integers.],
  [SoundStream (2021) was the first universal end-to-end neural audio codec,
   introducing quantizer dropout for variable-bitrate operation.],
  [EnCodec (2022) added causal streaming, stereo support, and a Transformer entropy
   coder on top of RVQ for an additional 20--40% bitrate saving.],
  [DAC (2023) improved codebook utilisation with random codebook resets and periodic
   (snake) activations, enabling near-transparent 44.1 kHz music quality.],
  [The first RVQ token stream tends to capture semantic (linguistic) information;
   later streams carry acoustic detail. SpeechTokenizer and Mimi formalise this
   split with a semantic distillation loss.],
  [AudioLM (2022) and VALL-E (2023) demonstrated that language models operating on
   neural codec tokens can generate highly natural audio, including zero-shot voice
   cloning from three seconds of reference audio.],
  [Mimi (2024) combines streaming with semantic distillation, achieving 1.1 kbps at
   12.5 Hz, the codec backbone of the Moshi full-duplex spoken dialogue system.],
  [Open problems include codebook collapse, reproducible floating-point token streams,
   real-time decode on low-power hardware, and standardised evaluation for
   tokenization quality.],
))

== Exercises

#exercise("60.1", 1)[
  A neural audio codec encodes at 24 kHz with a stride product of 320.
  It uses $N_q = 6$ RVQ levels, each with a 1,024-entry codebook.
  (a) How many latent frames are produced per second?
  (b) How many bits per second does the raw RVQ stream occupy (before any entropy coding)?
  (c) If an entropy coder achieves 25% compression, what is the final bitrate in kbps?
]
#solution("60.1")[
  (a) $24000 / 320 = 75$ frames per second.
  (b) Each frame produces 6 tokens, each 10 bits ($log_2 1024 = 10$): $75 times 6 times 10 = 4500$ bits/s = 4.5 kbps.
  (c) $4500 times 0.75 = 3375$ bits/s $approx$ 3.4 kbps.
]

#exercise("60.2", 1)[
  Explain in your own words what *codebook collapse* is, why it happens, and
  name one technique used by DAC to prevent it.
]
#solution("60.2")[
  Codebook collapse is when some codebook entries are selected for every (or almost
  every) encoder output, while other entries are never used. It happens because the
  training objective does not directly penalise unused entries: gradient descent just
  reinforces whatever is already working. DAC prevents it by periodic *random restart*:
  any entry that has not been chosen for a fixed number of steps is replaced by a
  randomly selected encoder output from the current minibatch, forcing it back into
  use.
]

#exercise("60.3", 2)[
  Given the following two-level RVQ codebooks (dimension $d=2$, $K=3$ entries each),
  encode the vector $z = (3.0, 1.5)$ and report:
  (a) the two token indices $(k_1, k_2)$,
  (b) the final reconstruction $hat(z)$,
  (c) the reconstruction error $norm(z - hat(z))_2$.

  Codebook 1: $e_0 = (1.0, 0.5)$, $e_1 = (3.5, 2.0)$, $e_2 = (2.0, 1.0)$.
  Codebook 2: $e_0 = (0.5, 0.5)$, $e_1 = (-0.5, -0.5)$, $e_2 = (0.8, 0.2)$.
]
#solution("60.3")[
  *Level 1:* Distances from $(3.0, 1.5)$:
  $e_0$: $(2.0)^2+(1.0)^2=5.0$; $e_1$: $(0.5)^2+(0.5)^2=0.5$ ← nearest; $e_2$: $(1.0)^2+(0.5)^2=1.25$.
  So $k_1=1$, $hat(z)_1 = (3.5, 2.0)$. Residual $r_1 = (3.0-3.5, 1.5-2.0) = (-0.5, -0.5)$.

  *Level 2:* Distances from $(-0.5, -0.5)$:
  $e_0$: $(1.0)^2+(1.0)^2=2.0$; $e_1$: $(0.0)^2+(0.0)^2=0.0$ ← exact match; $e_2$: $(1.3)^2+(0.3)^2=1.78$.
  So $k_2=1$, $hat(z)_2=(-0.5,-0.5)$.

  $(k_1, k_2) = (1, 1)$. $hat(z) = (3.5-0.5, 2.0-0.5) = (3.0, 1.5)$. Error = 0 (exact reconstruction in this small example).
]

#exercise("60.4", 2)[
  AudioLM generates audio in two stages: first a semantic model, then an acoustic model.
  (a) What kind of tokens does the semantic model generate, and what kind does the
  acoustic model generate?
  (b) Why is this two-stage approach better than a single model that generates all RVQ
  token streams in order?
  (c) VALL-E uses a similar split. What is the prompt (conditioning signal) for VALL-E's
  acoustic model?
]
#solution("60.4")[
  (a) The semantic model generates token stream 0 (or tokens from a self-supervised
  speech model), which encodes linguistic/content information. The acoustic model
  generates streams 1 through $N_q-1$, conditioned on stream 0, encoding voice quality
  and fine acoustic detail.

  (b) Stream 0 alone is a much shorter sequence (or uses tokens that are more
  compressible because they have linguistic structure). The semantic model can be a
  smaller, faster autoregressive model. The acoustic model can generate all streams
  in parallel conditioned on stream 0, avoiding the slow sequential generation for
  those streams. A single model generating all streams autoregressively would face
  a much longer sequence and harder joint distribution.

  (c) VALL-E's acoustic model is conditioned on: the text transcript (encoded as text
  tokens), the first RVQ stream generated by the autoregressive semantic model, and
  a three-second reference audio clip of the target speaker (also as EnCodec tokens).
]

#exercise("60.5", 2)[
  The *straight-through estimator* (STE) is used to train RVQ codebooks.
  (a) Why is the nearest-neighbour operation not differentiable?
  (b) Describe what the STE does during the forward pass and during the backward pass.
  (c) What is the *commitment loss*, and what problem does it solve?
]
#solution("60.5")[
  (a) The function $k = "argmin"_k norm(z - e_k)_2$ outputs an integer index.
  Changing $z$ slightly does not change $k$ until $z$ crosses the boundary between
  two Voronoi cells, at which point $k$ jumps discontinuously. A function that is
  constant except at isolated jump points has zero gradient almost everywhere: there
  is no smooth slope for gradient descent to follow.

  (b) Forward pass: the quantized vector $hat(z) = e_(k^star)$ is used normally in
  the computation. Backward pass: the gradient $partial cal(L) / partial hat(z)$ is
  passed directly to $z$ as if the quantization were the identity, "passed straight
  through." The codebook entries themselves are not updated by backpropagation;
  they are updated by EMA.

  (c) The commitment loss adds a term $beta norm("sg"(e_(k^star)) - z)^2_2$ to the
  training loss, where "sg" means "stop gradient." This pushes $z$ (the encoder output)
  toward the chosen codebook entry $e_(k^star)$, preventing the encoder from producing
  outputs that drift far from any codebook entry, which would destabilise training.
]

#exercise("60.6", 3)[
  Write a Python function `bitrate_from_rvq(n_q: int, K: int, frame_rate: float) -> float`
  that computes the raw bitrate (in bits per second, before entropy coding) of an RVQ
  codec with `n_q` quantizer levels, each with `K` codebook entries, at the given
  frame rate in frames per second. Then write a second function
  `min_codebook_bits(target_bps: float, frame_rate: float, n_q: int) -> int`
  that returns the minimum codebook size $K$ (as a power of 2) needed to reach
  at least `target_bps` bits per second with `n_q` levels. Test both functions
  with SoundStream's parameters (stride 320, 24 kHz, $N_q = 8$, $K = 1024$)
  and EnCodec's entropy-coded rate of approximately 6 kbps ($N_q = 8$, frame rate 75,
  K=1024, assume 25% entropy coding saving).
]
#solution("60.6")[
  ```python
  import math

  def bitrate_from_rvq(n_q: int, K: int, frame_rate: float) -> float:
      """Raw bits per second for an RVQ codec (before entropy coding)."""
      bits_per_frame = n_q * math.log2(K)
      return frame_rate * bits_per_frame

  def min_codebook_bits(target_bps: float,
                        frame_rate: float,
                        n_q: int) -> int:
      """Minimum codebook size K (power of 2) to reach target_bps."""
      bits_per_frame_needed = target_bps / frame_rate
      bits_per_code = bits_per_frame_needed / n_q
      K_exact = 2 ** bits_per_code
      # Round up to next power of 2
      K_min = 2 ** math.ceil(math.log2(K_exact))
      return K_min

  # SoundStream: 24000 / 320 = 75 fps, n_q=8, K=1024
  ss_rate = bitrate_from_rvq(8, 1024, 75.0)
  print(f"SoundStream raw bitrate: {ss_rate:.0f} bps = {ss_rate/1000:.1f} kbps")
  # -> 6000 bps = 6.0 kbps

  # EnCodec with 25% entropy saving: effective rate ~6 kbps from 8 kbps raw
  # (8 kbps raw x 0.75 = 6 kbps after entropy coding)
  ec_raw = bitrate_from_rvq(8, 1024, 75.0)
  ec_effective = ec_raw * 0.75
  print(f"EnCodec effective bitrate: {ec_effective:.0f} bps = {ec_effective/1000:.1f} kbps")
  # -> 4500 bps = 4.5 kbps (illustrative; actual EnCodec configuration varies)

  # Minimum K to hit 12 kbps with n_q=4, 75 fps
  K = min_codebook_bits(12000.0, 75.0, 4)
  print(f"Minimum K for 12 kbps, n_q=4: {K}")  # -> K = 16 (4 bits each)
  ```
]

== Further Reading

- #link("https://arxiv.org/abs/2107.03312")[Zeghidour et al. (2021). *SoundStream: An End-to-End Neural Audio Codec.* arXiv:2107.03312.] The original paper. Clear architecture description and ablations on quantizer dropout.

- #link("https://arxiv.org/abs/2210.13438")[Défossez et al. (2022). *High Fidelity Neural Audio Compression (EnCodec).* arXiv:2210.13438.] The EnCodec paper. Section 3 on the Transformer entropy coder is particularly instructive.

- #link("https://arxiv.org/abs/1711.00937")[van den Oord, Vinyals, Kavukcuoglu (2017). *Neural Discrete Representation Learning (VQ-VAE).* NeurIPS 2017 / arXiv:1711.00937.] The paper that introduced vector quantization as a training objective and the straight-through estimator for codebook learning. Foundational reading.

- #link("https://arxiv.org/abs/2209.03143")[Borsos et al. (2022). *AudioLM: A Language Modeling Approach to Audio Generation.* arXiv:2209.03143.] The paper that demonstrated that audio generation is a language modelling problem, using SoundStream tokens as the vocabulary.

- #link("https://arxiv.org/abs/2301.02111")[Wang et al. (2023). *VALL-E: Neural Codec Language Models are Zero-Shot Text to Speech Synthesizers.* arXiv:2301.02111.] The voice-cloning paper that surprised the research community.

- #link("https://arxiv.org/abs/2308.16692")[Zhang et al. (2024). *SpeechTokenizer: Unified Speech Tokenizer for Speech Language Models.* ICLR 2024 / arXiv:2308.16692.] Formalises the semantic--acoustic split in RVQ via distillation.

- #link("https://kyutai.org/Moshi.pdf")[Défossez et al. (2024). *Moshi: A Speech-Text Foundation Model for Real-Time Dialogue.* Kyutai Technical Report.] Describes both Mimi and the Moshi spoken dialogue system. Unusually thorough engineering description.

- #link("https://arxiv.org/abs/2402.13071")[Shi et al. (2024). *Codec-SUPERB: An In-Depth Analysis of Sound Codec Models.* arXiv:2402.13071.] The benchmark paper for evaluating neural audio codecs on downstream tasks, not just reconstruction quality.

#bridge[
  We have seen that a language model operating on codec tokens can generate,
  clone, and transform speech. The codec is the missing glue. But what does it
  *mean* for a language model to be good at compression? In Chapter 61 we step back
  to the theory: the deep connection between generalisation, intelligence, and
  compression that runs through Solomonoff induction, the Minimum Description
  Length principle, PAC-Bayes bounds, and Hutter's prize. The question "why do
  language models compress so well?" turns out to have a beautiful theoretical
  answer rooted in ideas we first met in Chapter 22 (Kolmogorov complexity and the
  Solomonoff prior) and Chapter 23 (compression = prediction = learning, and
  Rissanen's MDL).
]
