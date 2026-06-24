#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Learned Video and Implicit Neural Representations

#epigraph[
  We do not predict motion. We predict _distributions_, and let the network
  decide how to use time.
][Jizheng Xu, on the philosophy behind the DCVC series]

Here is a puzzle. Everything you learned in Chapters 51–55 about classical
video coding boils down to one grand idea: find what moved, encode only the
difference, then entropy-code the leftovers. Motion estimation, block matching,
the hybrid codec loop: all of it is a beautifully engineered machine for
answering the question "what changed?" In Chapter 57 you saw how the image half
of that story was rewritten by neural networks: instead of a hand-built
transform, a trained autoencoder discovers its own representation, and the whole
pipeline (encoder, quantizer, entropy model) is optimized together by gradient
descent. Learned image codecs now beat the best classical ones.

So here is the natural question: can we do the same thing for video?

The answer turns out to be both "yes" and "it is more complicated than you
think." This chapter tells you exactly how. We will follow two very different
answers to that question.

The first answer is *neural video coding*: replace the blocks of the classical
hybrid codec (the optical-flow estimator, the residual coder, the entropy
model) with neural networks, keep the overall predict-then-code structure,
and train everything end-to-end. The landmark is DVC (2019); the dominant
research line today is Microsoft's DCVC family (2021–2025), which quietly
discarded the "explicit residual" idea in favor of something information-
theoretically cleaner. Google's Video Compression Transformer, VCT (2022),
goes further still and removes explicit motion estimation entirely.

The second answer is *implicit neural representation* compression, or INR. It
asks: what if you don't encode the video as a stream of pixels at all? What if
the video _is_ a small neural network, trained from scratch to memorize every
frame, and the "bitstream" is just the quantized weights of
that network? COIN (2021) showed this worked for single images. NeRV (2021)
extended it to video. The results are elegant, the decoder is simple, and the
encoder is... slow. Very slow.

By the end of this chapter you will understand why both approaches are genuinely
exciting, where each one wins, and why neither has yet replaced
AV1 on your phone.

#recap[
  *Chapter 51* built the classical hybrid video codec loop: motion-compensated
  prediction, DCT on the residual, quantization, entropy coding, all tied
  together by Lagrangian rate-distortion optimization (minimize
  $J = D + lambda R$). *Chapter 57* replaced the image codec's hand-built
  transform with a trained autoencoder, added quantization-as-noise to make
  gradients flow, and introduced the hyperprior for adaptive entropy modeling.
  *Chapter 58* added GAN and diffusion losses for perceptual quality. This
  chapter applies all of that machinery to video, where time is the new
  dimension that creates both the biggest compression opportunity and the
  hardest engineering problem.
]

#objectives((
  "Explain why temporal prediction is the dominant source of compression gain in video, and what an end-to-end neural video codec does differently from a classical one.",
  "Describe the DVC (2019) architecture: optical-flow networks, motion compression, residual compression, and why it was a first.",
  "Explain the key conceptual shift in the DCVC family: conditional coding versus explicit residual coding, and why it is information-theoretically tighter.",
  "Describe VCT's even more radical simplification: no motion estimation at all, just a transformer on latents.",
  "Define an implicit neural representation (INR) and explain how COIN uses one to store an image.",
  "Explain the NeRV architecture for video: frame index in, RGB frame out.",
  "State the central tension for INR codecs: fast decoding, extremely slow encoding.",
  "Assess the current (2026) state of learned video codecs: where they win, where they lose, and what the deployment barriers are.",
))

== Why Video Is Both Easier and Harder Than Images

When you compress a single image, every pixel has to be coded independently of
any temporal context: there is only one frame. The only structure you can
exploit is spatial: nearby pixels tend to be similar, smooth areas have
predictable colors, and so on. That is what JPEG, JPEG XL, and learned image
codecs exploit.

Video gives you an enormous extra gift: *time*. In most video (a person
talking, a film scene, a sports match) the vast majority of the frame is simply
the previous frame, shifted and deformed slightly by motion. A good codec does
not need to re-encode what is already there; it encodes only the *difference*.
In the H.264 standard, motion-compensated residuals typically carry only 10–20%
of the information that an intra-coded frame would require. Time is the most
powerful compression trick in the entire book.

But time creates a harder engineering problem. Images are independent objects.
You compress one, you are done. Video frames are *causally linked*: frame 100
depends on frames 95, 90, and perhaps 1. Errors propagate. Motion in the real
world is complicated: partial occlusions, large displacements, lighting
changes, fast objects. A codec that gets motion slightly wrong pays a large
penalty in residual size. Classical codecs solved this by hand-crafting motion
search algorithms, carefully tuned loop filters, and elaborate reference-frame
management. The neural approach asks: can we learn all of this from data?

#keyidea[
  The compression gain from temporal prediction is so large that it dominates
  everything else in video coding. Any learned video codec must either (a) learn
  to do motion prediction better than classical methods, or (b) find a different
  way to exploit temporal correlation that makes motion prediction unnecessary.
  The DVC line does (a); VCT does (b).
]

== DVC: The First End-to-End Neural Video Codec

In December 2018, Guo Lu, Wanli Ouyang, Dong Xu, Xiaoyun Zhang, Chunlei Cai,
and Zhiyong Gao posted a preprint titled "DVC: An End-to-End Deep Video
Compression Framework." It was accepted to CVPR 2019 as an oral presentation, the highest distinction
at that venue. DVC was the first neural video codec to
jointly optimize every component by gradient descent, and it is the baseline
against which everything since is measured.

=== The Classical Structure, Neuralized

The key insight of DVC is that the classical hybrid codec pipeline, block by
block, has a learned neural counterpart:

*Optical flow estimation.* Classical codecs search for block matches in a
reference frame, a heuristic with many failure modes. DVC replaces this with
a pre-trained optical flow network (SpyNet or a similar architecture from the
computer vision literature) that estimates a dense pixel-level motion field
$v$ mapping each pixel in frame $t-1$ to its location in frame $t$. The flow
field is a continuous, smooth function learned from data. It handles occlusions
and large motions more gracefully than block matching.

*Motion compression.* The flow field $v$ is itself a 2D signal that must be
stored in the bitstream. DVC applies a learned image codec (Ballé et al., 2018,
the same hyperprior architecture from Chapter 57) to compress and decompress it
as $hat(v)$. The reconstructed flow $hat(v)$ is used to warp the reference
frame: $hat(x)_(t-1) tilde(arrow.r) tilde(x)_t$ ("warp frame $t-1$ using flow
$hat(v)$ to predict frame $t$").

*Residual compression.* The difference between the true frame $x_t$ and the
warp prediction $tilde(x)_t$ is the *residual* $r = x_t - tilde(x)_t$. Another
learned codec (again, hyperprior style) compresses the residual to get $hat(r)$.
The final reconstruction is $hat(x)_t = tilde(x)_t + hat(r)$.

*End-to-end training.* The whole pipeline (flow network, motion codec, warp
operation, residual codec) is differentiable (with quantization-as-noise, as
in Chapter 57). The training objective is a rate-distortion loss:

$ cal(L) = lambda dot D(x_t, hat(x)_t) + R_v + R_r $

where $D$ is the mean squared error between the original and reconstructed
frame, $R_v$ is the number of bits spent on the motion field, and $R_r$ is the
bits spent on the residual. By minimizing this jointly, the network learns to
trade motion precision against residual size in whatever way saves the most bits.

#gomaths("Rate-distortion loss for video")[
  The rate-distortion tradeoff is the fundamental tension in any lossy
  compressor: more distortion (lower quality) saves bits; less distortion
  (higher quality) costs bits. In the classical formulation from Chapter 21,
  we choose a Lagrange multiplier $lambda > 0$ and minimize the combined cost:

  $ J = D + lambda dot R $

  where $D$ is distortion (e.g., mean squared error in pixel values) and $R$
  is the number of bits. Large $lambda$ weights quality heavily; small $lambda$
  weights file size. For DVC there are two bit streams to account for:
  motion bits $R_v$ and residual bits $R_r$. The loss becomes:
  $ cal(L) = lambda dot D + R_v + R_r $
  The network jointly minimizes both bit costs while controlling quality.
]

=== What DVC Achieved

On standard video benchmarks (UVG, MCL-JCV, HEVC Class B), DVC at its best
configuration outperformed H.264 (the dominant streaming codec at the time) on
both PSNR and MS-SSIM metrics. It did not beat HEVC (H.265), but it
demonstrated that the entire hand-crafted classical pipeline could, in
principle, be replaced by trained neural networks, and that gradient-based
joint optimization found a better balance between motion coding and residual
coding than the separately tuned classical components.

#mathrecall[
  *PSNR* (Peak Signal-to-Noise Ratio, defined in Chapter 42) measures
  reconstruction quality in decibels: $"PSNR" = 10 log_10 (255^2 \/ "MSE")$,
  where MSE is the mean squared pixel error. Higher is better; above 40 dB is
  near-indistinguishable from the original. *MS-SSIM* is a perceptual quality
  score (also Chapter 42) that tracks human judgment of structural similarity
  better than raw error. We use both here exactly as the video chapters did.
]

The cost: DVC was orders of magnitude slower than any classical codec. Encoding
a single frame took many seconds on a GPU; classical H.264 encoders run at
real-time on a CPU. The inference complexity was also high for decoding.

#history[
  DVC arrived at a moment when computer vision had already solved dense optical
  flow with neural networks. The insight of Lu et al. was not to invent a new
  flow estimator, but to recognize that a flow estimator is just a motion coder,
  and a motion coder is just an image coder applied to a 2D vector field, and
  that the whole chain could be trained together. The paper's oral acceptance at
  CVPR 2019 (top ~1% of submissions) signaled that the compression community
  had arrived at the deep learning era.
]

#algo(
  name: "DVC: Deep Video Compression",
  year: "2019",
  authors: "Guo Lu, Wanli Ouyang, Dong Xu, Xiaoyun Zhang, Chunlei Cai, Zhiyong Gao",
  aim: "First fully end-to-end learned video codec, replacing every classical block (motion estimation, motion coding, residual coding) with neural networks trained jointly via rate–distortion loss.",
  complexity: "O(H × W) per frame inference; GPU-only; many seconds per frame at 2019 hardware.",
  strengths: "Joint optimization of motion + residual; better handles large motions and occlusions than block matching; milestone proof-of-concept.",
  weaknesses: "Far slower than classical codecs; quality below HEVC; inherits classical residual-coding paradigm's information-theoretic ceiling.",
  superseded: "DCVC family (2021–), VCT (2022), DCVC-RT (2024–2025).",
)[
  DVC keeps the skeleton of the classical hybrid codec (predict → residual →
  code) but replaces every component with a trained network. The optical-flow
  estimator produces a dense motion field; a learned image codec compresses that
  field; a warp operation generates the prediction; a second learned codec
  handles the residual. Everything is differentiable and trained jointly.
]

== The DCVC Family: Conditional Coding

The DVC architecture was a milestone, but it inherited one assumption from the
classical world: the notion of an explicit *residual*. You predict the current
frame, subtract the prediction, and encode the difference. This seems natural.
In fact, it has an information-theoretic ceiling.

The DCVC family of codecs was developed at Microsoft Research Asia, starting
with "Deep Contextual Video Compression" by Jizheng Xu, Jianping Lin, and
colleagues at NeurIPS 2021. It made a cleaner and more powerful choice.

=== From Residuals to Conditions

In a learned codec, every frame is compressed by passing it through an encoder
network to produce a latent representation $y$, which is then quantized and
entropy-coded. The entropy coder needs a probability model $p(hat(y))$: the
better the model, the fewer bits are needed.

In a *residual* approach, you compute $r = x_t - tilde(x)_t$ and then encode
$r$. The temporal information (the warped prediction) enters the picture before
the encoder: you are literally encoding a smaller number.

In *conditional coding*, the temporal information enters the probability model
differently. You still encode the full latent $y_t$ of frame $t$, but the
entropy model is *conditioned* on the temporal context $phi_t$ (features derived
from the already-decoded reference frames). That is:

$ R = -log_2 p(hat(y)_t | phi_t) $

The entropy model predicts what the current latent will look like, given what
came before, and assigns short codes to likely outcomes. The encoder still sends
the full latent, but because the entropy model makes good predictions, the
expected number of bits is small.

Why is this better? Conditional coding is strictly more powerful than residual
coding. The residual paradigm forces the prediction to happen in *pixel space*:
you warp pixels, subtract pixels. Conditional coding allows the prediction to
happen in *latent space*, where the network has learned a much richer
representation. The network can condition the probability of each latent
coefficient on patterns that have no simple pixel-domain description:
texture distributions, object identity, scene illumination. Those patterns let it assign fewer
bits to predictable structure.

#gomaths("Conditional entropy")[
  Recall from Chapter 18 that the entropy $H(Y)$ of a random variable $Y$ is the
  average number of bits needed to describe it. The *conditional entropy*
  $H(Y | X)$ is the average number of bits needed to describe $Y$ once you
  already know $X$. It obeys:

  $ H(Y | X) <= H(Y) $

  Knowing $X$ can only help: it can never increase the average code length.
  In DCVC, $Y$ is the current frame's latent and $X$ is the temporal context
  $phi_t$ from previous frames. By conditioning the entropy model on $phi_t$,
  DCVC pays at most $H(Y_t | phi_t)$ bits per frame, which is always at most
  $H(Y_t)$, the cost of coding the frame without any temporal information, and
  usually much less.
]

=== The DCVC Architecture

The DCVC encoder for frame $t$ works as follows:

1. *Extract temporal context.* From previously decoded frames, a feature
   extraction network produces a rich temporal context $phi_t$. This is not
   just a warped copy of the previous frame; it is a learned feature map that
   can capture higher-level structure.

2. *Encode the current frame.* The encoder network maps $x_t$ to a latent $y_t$,
   using $phi_t$ as an additional input so that it can "already assume" the
   decoder knows the context.

3. *Entropy code conditionally.* The entropy model predicts $p(hat(y)_t | phi_t)$
   and uses it to assign bit costs. Because the context is rich, most latent
   coefficients are highly predictable and cost very few bits.

4. *Decode and update context.* The decoder reconstructs $hat(x)_t$ from
   $hat(y)_t$ and $phi_t$. The reconstructed frame feeds into the next step's
   context extraction.

Notice that there is no explicit residual anywhere. The network has quietly
internalized the idea of "what changed" into the conditional probability model,
without ever computing $x_t - tilde(x)_t$ as an explicit variable.

#fig(
  [The DCVC conditional coding pipeline versus the classical residual pipeline.
   In the residual approach (top), the reference frame is warped and subtracted
   before the encoder. In conditional coding (bottom), the temporal context
   $phi_t$ conditions the entropy model, allowing prediction in latent space.],
  cetz.canvas({
    import cetz.draw: *
    // - top row: residual coding -
    content((0, 3.8), text(weight: "bold", size: 9pt)[Residual (DVC-style)])
    rect((0.1, 2.8), (1.7, 3.5), radius: 3pt, fill: rgb("#dbeafe"), stroke: rgb("#3b82f6"))
    content((0.9, 3.15), text(size: 8pt)[Warp])
    rect((2.1, 2.8), (3.3, 3.5), radius: 3pt, fill: rgb("#fef9c3"), stroke: rgb("#ca8a04"))
    content((2.7, 3.15), text(size: 8pt)[$x_t - tilde(x)_t$])
    rect((3.7, 2.8), (5.1, 3.5), radius: 3pt, fill: rgb("#dcfce7"), stroke: rgb("#16a34a"))
    content((4.4, 3.15), text(size: 8pt)[Encoder])
    rect((5.5, 2.8), (6.9, 3.5), radius: 3pt, fill: rgb("#fce7f3"), stroke: rgb("#be185d"))
    content((6.2, 3.15), text(size: 8pt)[Entropy])
    line((1.7, 3.15), (2.1, 3.15), mark: (end: ">"))
    line((3.3, 3.15), (3.7, 3.15), mark: (end: ">"))
    line((5.1, 3.15), (5.5, 3.15), mark: (end: ">"))
    // ref frame arrow into warp
    content((0.9, 2.3), text(size: 7.5pt, fill: rgb("#6b7280"))[ref $hat(x)_(t-1)$])
    line((0.9, 2.6), (0.9, 2.8), mark: (end: ">"))

    // - bottom row: conditional coding -
    content((0, 1.6), text(weight: "bold", size: 9pt)[Conditional (DCVC-style)])
    rect((0.1, 0.6), (1.7, 1.3), radius: 3pt, fill: rgb("#dbeafe"), stroke: rgb("#3b82f6"))
    content((0.9, 0.95), text(size: 8pt)[Context $phi_t$])
    rect((2.1, 0.6), (3.5, 1.3), radius: 3pt, fill: rgb("#dcfce7"), stroke: rgb("#16a34a"))
    content((2.8, 0.95), text(size: 8pt)[Encoder])
    rect((3.9, 0.6), (5.3, 1.3), radius: 3pt, fill: rgb("#fce7f3"), stroke: rgb("#be185d"))
    content((4.6, 0.95), box(width: 1.0cm, inset: 1pt, align(center, text(size: 7pt)[Entropy $p(hat(y)_t | phi_t)$])))
    line((2.8, 1.3), (4.6, 0.6), stroke: (dash: "dashed", paint: rgb("#be185d")), mark: (end: ">"))
    line((1.7, 0.95), (2.1, 0.95), mark: (end: ">"))
    line((3.5, 0.95), (3.9, 0.95), mark: (end: ">"))
    // x_t arrow into encoder
    content((2.8, 0.15), text(size: 7.5pt, fill: rgb("#6b7280"))[$x_t$])
    line((2.8, 0.4), (2.8, 0.6), mark: (end: ">"))
  })
)

=== The DCVC Family, 2021–2025

The original DCVC paper was followed by a series of extensions, each fixing a
specific limitation:

*DCVC-TCM (2022)* (Temporal Context Mining), published in IEEE Transactions on
Multimedia. It improved the quality of the temporal context by mining features
at multiple temporal scales, so the entropy model sees both fine-grained motion
and coarser scene structure.

*DCVC-HEM (2022)* (Hybrid Spatial-Temporal Entropy Modelling), at ACM
Multimedia. It combined the temporal context (from previous frames) with a
spatial context model (from already-decoded positions in the current frame),
giving the entropy coder two sources of side information simultaneously.

*DCVC-DC (NeurIPS 2023)* (Diverse Contexts) was the first
end-to-end neural video codec to clearly surpass VVC (the current champion
classical codec) on both PSNR and MS-SSIM on standard benchmark datasets.
The bitrate savings over VVC's reference software ranged from 23% to 26%
depending on the test sequence.

*DCVC-FM (2024)* (Feature Modulation) further pushed the rate-distortion curve
and introduced a more flexible context modulation mechanism. On benchmark
sequences at the time of its release, DCVC-FM maintained the lead over VVC.

*DCVC-RT (2024–2025)* (Real-Time) is the most practically significant entry. By
redesigning the architecture for GPU-parallel execution (eliminating serial
dependencies in the entropy model), DCVC-RT achieved over 125 frames per
second at 1080p on modern hardware, genuinely real-time, while still showing
roughly a 21% bitrate saving compared to VVC at the same quality level. This
closed the speed gap from "orders of magnitude slower" to "within range of
classical hardware encoders."

#pitfall[
  "DCVC beats VVC" needs a careful reading. These comparisons are against VVC's
  *reference software* (VTM), which is a research-grade implementation, correct
  but not optimized for speed. Practical VVC encoders (like x265's HEVC
  predecessor or the emerging x266) are much faster. The JVET Enhanced
  Compression Model (ECM, described in Chapter 55) still beats DCVC-FM by about
  11% on the same benchmarks. The neural codec wins on flexibility and trainability;
  it does not yet win on every axis simultaneously.
]

#algo(
  name: "DCVC: Deep Contextual Video Compression",
  year: "2021 (NeurIPS); extended 2022–2025",
  authors: "Jizheng Xu, Jianping Lin, et al. (Microsoft Research Asia); multiple subsequent papers",
  aim: "Replace explicit residual coding with conditional entropy coding: encode the full frame latent, but condition the entropy model on rich temporal context features so bits per frame are minimized.",
  complexity: "Encoder: GPU-dependent; DCVC-RT achieves >125 fps at 1080p. Decoder: comparably fast with parallel entropy decoding.",
  strengths: "Information-theoretically cleaner than residual coding; surpasses VVC reference software on standard benchmarks; DCVC-RT is first neural video codec with practical real-time speeds.",
  weaknesses: "Still requires GPU; ECM (classical) is still ~11% better on benchmarks; bit-exact reproducibility across platforms remains fragile; context model training requires large video datasets.",
  superseded: "Active research line as of 2026; not yet superseded.",
)[
  The key conceptual advance: temporal prediction moves from pixel space (warp
  and subtract) to latent space (condition the entropy model). The decoder
  reconstructs each frame's latent by knowing that certain coefficients, given
  what came before, are nearly certain, so they cost almost no bits.
]

== VCT: Remove Motion Entirely

In 2022, Fabian Mentzer and colleagues at Google Research published "VCT: A
Video Compression Transformer," which appeared at NeurIPS 2022. VCT asked an
even more radical question than DCVC: what if you do not model motion at all?

The architecture is surprisingly simple. VCT uses a standard learned *image*
codec (the hyperprior model from Chapter 57) to encode each frame independently
into a quantized latent $hat(y)_t$. There is no optical flow, no warping, no
conditional context extraction. Each frame is compressed as if it were a
standalone image.

The magic happens at the entropy coding step. A large transformer model,
trained on sequences of video latents, predicts the distribution
$p(hat(y)_t | hat(y)_(t-k), ..., hat(y)_(t-1))$ for each new frame's latent,
conditioned on the previously transmitted latents. The transformer learns, from
data, whatever temporal patterns are useful: motion, scene continuity, lighting
changes, periodicity. It does not need to be told "this is motion"; it
discovers useful patterns on its own, including ones that have no classical
counterpart.

#gomaths("Transformers and attention")[
  A _transformer_ is a kind of neural network (built from the neurons of
  Chapter 56) designed to process a _sequence_ of items (here, the sequence of
  past frame latents $hat(y)_1, hat(y)_2, dots, hat(y)_(t-1)$) and predict the
  next one. Its central trick is _attention_: to predict the next item, the
  network computes, for every earlier item, a _relevance weight_ between 0 and 1
  saying "how much should I look at this one?", then forms a weighted average of
  the items it deems relevant. Think of it as a soft, learned table lookup: when
  predicting frame $t$, the network might place 70% of its attention on frame
  $t-1$ (the most recent), 20% on a frame from one second ago that looked
  similar, and almost none on the rest.

  Because every item can attend to every other, a transformer captures
  long-range patterns that a fixed warp-the-previous-frame rule never could.
  The price is cost: with $n$ items in the sequence, attention compares every
  pair, so the work grows like $n^2$ (quadratic in the Big-O language of
  Chapter 14). That is why long sequences make transformers slow. _Positional
  encoding_ is a small extra signal added to each item that tells the network
  _where_ in the sequence (which time step) the item sits, since attention by
  itself is order-blind. We meet the transformer in full when we reach language
  models in Chapter 62; here we use it purely as a powerful next-item predictor.
]

The result: VCT matches or beats DVC on standard benchmarks, despite having no
motion model at all. On datasets with complex motion (panning, blurring, fading)
that defeat block matching, VCT can be up to 45% better in rate-distortion than
CNN-based codecs. The architectural simplicity is appealing: there are fewer
hand-crafted components that could fail.

The cost is that transformers are computationally expensive (the attention box
above explains why: the work grows quadratically with sequence length), and
autoregressive decoding of latents is serial: each coefficient depends on the
previous ones, limiting parallelism.

#algo(
  name: "VCT: Video Compression Transformer",
  year: "2022 (NeurIPS)",
  authors: "Fabian Mentzer, David Minnen, Eirikur Agustsson, Michael Tschannen (Google Research)",
  aim: "Remove all explicit motion modeling from neural video compression; use a transformer to predict per-frame latent distributions from previously transmitted latents, learning temporal structure purely from data.",
  complexity: "Frame encoding: image codec (fast); entropy prediction: transformer (slow for long sequences due to attention cost). Autoregressive decoding limits GPU parallelism.",
  strengths: "No motion estimation failure modes; handles complex motion (panning, occlusion) naturally; simpler architecture with fewer hand-crafted components; strong on distribution-shift scenarios.",
  weaknesses: "Transformer inference is expensive; autoregressive decoding is serial; performance on standard benchmarks is competitive but not always best-in-class against DCVC-DC/FM.",
  superseded: "Active research line; descendants explored in 2023–2025.",
)[
  VCT demonstrates that temporal prediction does not require explicit motion
  vectors. A sufficiently powerful sequence model discovers its own notion of
  "what is expected next" in latent space (motion, repetition, gradual lighting
  change, whatever helps) and assigns short codes to the expected and long codes to
  the surprising.
]

#checkpoint[
  A colleague claims: "DCVC-style conditional coding and VCT are just two names
  for the same idea, since they both condition the entropy model on past frames." Is
  this right? Where do they differ?
][
  Partially right. Both condition entropy on past context. The crucial
  difference is how the context is computed. DCVC explicitly extracts feature
  maps from decoded reference frames using convolutional networks and uses them
  as input to the entropy model; the engineer still controls what "temporal
  context" means. VCT instead feeds the raw quantized latents of past frames
  to a large transformer and lets the transformer attend to whatever patterns
  it finds useful. VCT has no concept of "motion feature" at all. DCVC has
  a more structured but potentially more limited context; VCT has a less
  structured but potentially more general one.
]

== Implicit Neural Representations: A Completely Different Idea

Everything so far (DVC, DCVC, VCT) keeps the classical encoder-bitstream-
decoder architecture. The encoder produces a bitstream of symbols representing
the video; the decoder reconstructs the video from those symbols. The innovation
is in how the symbols are chosen and modeled.

Implicit neural representation (INR) compression throws out this architecture
entirely. It asks: what if the bitstream is not a compressed description of the
video, but instead the *parameters of a neural network that was trained to
memorize the video*?

=== What Is an Implicit Neural Representation?

An implicit neural representation is a neural network $f_theta$ that maps a
*coordinate* to a *value*:

$ f_theta : "coordinate" arrow.r "signal value" $

For an image: the coordinate is a pixel position $(x, y)$ and the output is a
color $(r, g, b)$. For audio: the coordinate is a time $t$ and the output is a
sample amplitude. For 3D geometry: the coordinate is a point $(x, y, z)$ and
the output might be a signed distance or an occupancy probability (this is the
idea behind NeRF, Neural Radiance Fields, 2020).

The network is not trained on a general image dataset. It is *overfit*, trained
specifically on a single piece of data, until $f_theta(x, y) approx$ the true
color at pixel $(x, y)$ for every pixel. Once trained, to recover the signal
you simply evaluate the network at every coordinate. The "compression" is the
fact that the network weights $theta$ may be far smaller than the raw pixel data.

#mathrecall[
  In Chapter 23 we met _over-fitting_ as a vice: a model that "memorises" its
  training data (including the noise) instead of capturing genuine regularity,
  and so fails to generalise to new data. INR compression flips this on its head.
  Here we _want_ to memorise one specific signal as exactly as possible, because
  we never ask the network to generalise to anything else: the file _is_ the
  signal. Over-fitting, normally the enemy, becomes the whole point. The reason
  this still compresses is the lesson of Chapter 23: a network small enough to be
  worth storing can only fit the signal well if the signal has real structure
  for it to latch onto. Pure noise would need as many parameters as pixels, and
  no compression would result.
]

#definition("Implicit Neural Representation (INR)")[
  An implicit neural representation is a neural network $f_theta$ whose
  parameters $theta$ are optimized to represent a single signal $s$ by
  learning the mapping from coordinates (position, time, frequency) to signal
  values. The network is the codec: encoding is training $f_theta$ on $s$;
  decoding is evaluating $f_theta$ at every coordinate.
]

=== COIN: Compression with Implicit Neural Representations (2021)

"COIN: COmpression with Implicit Neural Representations" by Emilien Dupont,
Adam Golinski, Milad Alizadeh, Yee Whye Teh, and Arnaud Doucet appeared as a
spotlight at the Neural Compression Workshop at ICLR 2021. It was the first
paper to seriously evaluate INRs as a compression method for images.

The COIN encoder is remarkably simple:

1. Take an image with pixel coordinates $(x, y)$ and RGB values.
2. Define a small multilayer perceptron (MLP) with sinusoidal activations
   (called a SIREN, Sinusoidal Representation Network, because sinusoids are
   well-suited to representing the smooth, oscillatory structure of natural
   images).
3. Train this MLP, via gradient descent on the mean squared error between
   predicted and true pixel values, until it memorizes the image.
4. Quantize the trained weights from 32-bit floats to, say, 8 or 16 bits.
5. The bitstream is the quantized weight vector.

The COIN decoder:

1. Receive the quantized weights, dequantize them.
2. Reconstruct the MLP.
3. Evaluate the MLP at every pixel coordinate $(x, y)$ in row-major order.
4. Output the RGB values. Done.

There is no entropy coder, no transform, no motion model. Just network
evaluation. And yet, at low bitrates (below roughly 0.1 bits per pixel), COIN
outperformed JPEG, a hand-crafted codec that had been tuned for decades. The
reason: at very low bitrates, JPEG's block artifacts dominate the distortion,
while COIN's smooth MLP produces a globally coherent, artifact-free
reconstruction.

#gopython("Multilayer Perceptron in PyTorch: the concept")[
  A multilayer perceptron (MLP) is the simplest kind of neural network. Each
  layer takes a vector of numbers, multiplies it by a weight matrix, adds a
  bias, and applies a nonlinear function. In PyTorch (which uses a very similar
  syntax to what we have seen in tinyzip), a 3-layer MLP looks like:

  ```python
  import torch
  import torch.nn as nn

  class TinyMLP(nn.Module):
      def __init__(self):
          super().__init__()
          self.net = nn.Sequential(
              nn.Linear(2, 64),   # 2 inputs: (x, y) pixel coords
              nn.ReLU(),
              nn.Linear(64, 64),
              nn.ReLU(),
              nn.Linear(64, 3),   # 3 outputs: (R, G, B)
          )

      def forward(self, coords: torch.Tensor) -> torch.Tensor:
          # coords: shape (N, 2), values in [-1, 1]
          return self.net(coords)  # shape (N, 3)
  ```

  Training means adjusting all the weights so that for each pixel coordinate
  `coords[i]`, the network output matches the true color. COIN uses sinusoidal
  activations (`torch.sin(w * x)`) instead of `ReLU` because they handle
  high-frequency detail better, but the core idea is identical.
]

#aside[
  The SIREN network (Sitzmann et al., NeurIPS 2020) uses the activation
  function $sin(omega_0 dot W x + b)$ at each layer, where $omega_0 approx 30$
  is a frequency scaling factor. This choice makes the network's Jacobian
  (the rate of change with respect to its inputs) periodic, which is ideal for
  representing signals that have oscillatory structure at multiple scales,
  exactly what natural images look like when you examine their Fourier spectrum.
]

=== What COIN Cannot Do (Yet)

COIN beat JPEG at very low bitrates. It did not beat JPEG at higher bitrates.
And it did not beat JPEG XL, WebP, or any modern codec at any bitrate. The
fundamental problem is twofold.

First, COIN has no *entropy coder*. The quantized weights are stored as-is,
without modeling their distribution or exploiting statistical structure. Adding
entropy coding to the weights (the approach taken in COIN++ by Dupont et al.,
2022) significantly improves results, but the gap to classical codecs remains.

Second, COIN *encodes slowly*. Training an MLP to memorize a single image by
gradient descent takes hundreds of gradient steps. On a modern GPU, encoding a
single 512×512 image takes on the order of 10–30 seconds. Classical image
codecs encode in milliseconds. For batch processing, INR encoding is unusable
at any reasonable throughput.

#misconception[
  "INR codecs are fast to use because the decoder is just a neural network evaluation."][
  The decoder is fast: evaluation of a small MLP at every pixel coordinate is
  essentially a matrix multiplication, which GPUs handle in milliseconds. But the
  *encoder* is training a neural network from scratch for every single file, which
  is expensive (seconds to minutes). The decode/encode asymmetry is the reverse
  of classical codecs: in INR, encoding is slow and decoding is fast. Classical
  codecs are usually encode-slow, decode-fast only at the most aggressive quality
  settings; in practice, software encoders like libx264 are much faster than
  INR encoding at any setting.
]

== NeRV: Extending INRs to Video

Hao Chen, Bo He, Hanyu Wang, Yixuan Hou, Ser Nam Lim, and Abhinav Shrivastava
published "NeRV: Neural Representations for Videos" at NeurIPS 2021. NeRV
extends the INR idea to video in a clever way that sidesteps the biggest
bottleneck of pixel-wise INRs.

=== Frame Index In, Full Frame Out

The key insight of NeRV is to change what the coordinate means. Instead of
mapping a pixel coordinate $(x, y)$ to a pixel color $(r, g, b)$, which
requires one network evaluation per pixel, NeRV maps a *frame index* $t$ to
an entire *frame image*. The network architecture uses convolutional upsampling
layers (like a decoder half of an autoencoder, as seen in Chapter 57) to turn
a small embedding vector $e_t$ into a full-resolution image:

$ f_theta : t arrow.r "frame" in RR^(H times W times 3) $

Here $e_t$ is a learned positional embedding for time step $t$, the same idea
as the positional encoding for transformers we met a few pages ago: a small
vector that encodes _which_ time step we are asking about. The output is the full
RGB frame at time $t$, produced in a single forward pass.

This is dramatically more efficient than pixel-wise INRs. Instead of evaluating
the network $H times W$ times per frame, you evaluate it *once* per frame,
producing all $H times W$ pixels simultaneously through the upsampling layers.
NeRV reported encoding speed improvements of 25× to 70× over pixel-wise INRs
(like COIN applied per-frame), and decoding improvements of 38× to 132×.

=== Compression via Weight Pruning and Quantization

To use NeRV as a video codec:

1. Train $f_theta$ on the video until it memorizes every frame well.
2. Compress the network weights using standard neural network compression
   techniques: structured pruning (remove the least important weight groups),
   weight quantization (reduce from 32-bit to 8-bit or lower), and entropy
   coding of the resulting sparse weight tensors.
3. The bitstream is the compressed weight tensor.
4. Decoding: receive weights, reconstruct network, run one forward pass per
   frame (each pass in milliseconds on a GPU).

On standard video benchmarks (UVG, HEVC sequences), NeRV reached quality
comparable to H.264 at similar bitrates, and better than H.264 at some
low-bitrate settings. It did not reach HEVC or AV1 quality.

#fig(
  [The NeRV architecture. A frame index $t$ is mapped to a positional embedding, which is then upsampled through convolutional blocks to produce a full video frame. The entire frame is generated in a single forward pass.],
  cetz.canvas({
    import cetz.draw: *
    // Frame index box
    rect((0, 1.5), (1.2, 2.5), radius: 3pt, fill: rgb("#f0fdf4"), stroke: rgb("#16a34a"))
    content((0.6, 2.0), box(width: 0.8cm, inset: 1pt, align(center, text(size: 8pt)[Frame idx $t$])))
    // Embedding box
    rect((1.6, 1.5), (3.0, 2.5), radius: 3pt, fill: rgb("#dbeafe"), stroke: rgb("#3b82f6"))
    content((2.3, 2.0), box(width: 1.0cm, inset: 1pt, align(center, text(size: 8pt)[Embedding $e_t$])))
    // Conv block 1
    rect((3.4, 1.4), (4.8, 2.6), radius: 3pt, fill: rgb("#fef9c3"), stroke: rgb("#ca8a04"))
    content((4.1, 2.0), text(size: 8pt)[Conv Up\ ×2])
    // Conv block 2
    rect((5.2, 1.4), (6.6, 2.6), radius: 3pt, fill: rgb("#fef9c3"), stroke: rgb("#ca8a04"))
    content((5.9, 2.0), text(size: 8pt)[Conv Up\ ×4])
    // Output frame
    rect((7.0, 1.2), (8.4, 2.8), radius: 3pt, fill: rgb("#fce7f3"), stroke: rgb("#be185d"))
    content((7.7, 2.0), text(size: 8pt)[Frame\ $H times W$])
    // Arrows
    line((1.2, 2.0), (1.6, 2.0), mark: (end: ">"))
    line((3.0, 2.0), (3.4, 2.0), mark: (end: ">"))
    line((4.8, 2.0), (5.2, 2.0), mark: (end: ">"))
    line((6.6, 2.0), (7.0, 2.0), mark: (end: ">"))
    // Label
    content((4.1, 0.9), text(size: 7.5pt, fill: rgb("#6b7280"))[One forward pass per frame])
  })
)

=== The Encoding Wall

NeRV is elegant. Its decoding is fast and GPU-friendly. But its encoding
problem is severe: training the network means running gradient descent for
thousands of iterations, using the video itself as a training set, until the
network memorizes every frame. For a 1-minute video at 30 fps (1,800 frames),
this can take 30 minutes to several hours, depending on the network size and
desired quality. Classical codecs encode the same video in seconds.

Subsequent work, including PNVC (2024) and TeCoNeRV (2025), has made
progress on reducing training time through better architectures, meta-learning
(training on video datasets so the network starts closer to a good solution),
and parallel training strategies. As of 2026, the encoding time for INR-based
video codecs has decreased significantly but remains a practical barrier for
any use case that requires fast encoding: live streaming, video conferencing,
real-time broadcasting.

#keyidea[
  The INR paradigm inverts the classical codec's asymmetry. Classical codecs
  (H.264, AV1) are designed to be decoded fast, because every viewer must decode
  but content is encoded once. INR codecs decode fast but encode slowly,
  which is exactly the right asymmetry for *streaming on demand*, where the
  encoder has unlimited time but the viewer needs instant playback. The problem
  is that "unlimited encoding time" still needs to mean "hours, not days."
]

== Comparing the Three Approaches

To make the tradeoffs concrete, let us put the three families side by side
against a common benchmark. The UVG dataset (Ultra Video Group, a standard
research benchmark of 7 high-resolution 1080p sequences) is the most widely
reported. Numbers below are approximate, as exact figures depend on
configuration and hardware; they are meant to illustrate relative positions,
not to be cited as definitive benchmarks.

#mathrecall[
  *BD-Rate* (Bjøntegaard Delta Rate, introduced in Chapter 53) is the standard
  way to compare two codecs with a single number. Each codec has a whole
  quality-versus-bitrate _curve_; the BD-Rate is the average percentage of bits
  codec B saves to reach the same quality as codec A, across the overlapping
  quality range. A BD-Rate of $-50%$ means "half the bits for the same quality".
  Negative is better.
]

#scoreboard(
  caption: "Approximate PSNR BD-Rate relative to H.264 (libx264 at same quality), UVG benchmark, ca. 2023–2024. Negative = fewer bits than H.264 for same quality.",
  [*Method*], [*Type*], [*BD-Rate vs H.264*], [*Enc. Speed*],
  [H.264 (libx264)], [Classical], [0% (reference)], [Fast, CPU],
  [HEVC (H.265, x265)], [Classical], [approx. −35%], [Fast, CPU],
  [AV1 (libaom)], [Classical], [approx. −40%], [Slow, CPU],
  [VVC (VTM)], [Classical], [approx. −50%], [Very slow, CPU],
  [DVC (2019)], [Neural end-to-end], [approx. −10 to −20%], [Very slow, GPU],
  [DCVC-DC (2023)], [Neural cond.], [approx. −55 to −60%], [Slow, GPU],
  [DCVC-RT (2025)], [Neural cond.], [approx. −45%], [Real-time, GPU],
  [VCT (2022)], [Neural transformer], [approx. −30%], [Slow, GPU],
  [NeRV (2021)], [INR], [approx. +0 to −10%], [Very slow (train)],
)

The scoreboard tells a clear story. By 2023–2024, the best neural codecs
(DCVC-DC) surpass even VVC on rate-distortion. But the encoding speed and GPU
dependency columns reveal the deployment gap. DCVC-RT is the first crack in
that wall: by 2025 it reaches real-time speeds on a GPU while still beating
VVC. NeRV is competitive with H.264 but not better, and its encoding wall
remains the defining limitation.

== The Deployment Reality: Why Your Phone Still Uses AV1

If DCVC-DC beats VVC by 55%, why is it not in your phone's video player?

The answer has nothing to do with compression ratios. It has everything to do
with deployment constraints that the research community tends to underemphasize.

=== Hardware Acceleration

Classical video codecs are accelerated in dedicated silicon on virtually every
modern device: a smartphone has a hardware H.264/H.265/AV1 decoder that runs
at 120 fps while consuming milliwatts. That decoder does not use the general
CPU or GPU; it is a fixed-function chip. Neural codecs run on the GPU (or NPU),
which consumes more power and competes with other tasks. Until NPU silicon is
designed and shipped for specific neural codec architectures, which requires
years of standardization and fab cycles, neural codecs will always lose the
energy and performance battle on constrained devices.

=== Bit-Exact Reproducibility

When you compress a video for a streaming service and send it to a billion
devices, every device's decoder must produce the *exact same pixels* from the
same bitstream. This is not optional: encrypted video, digital rights management,
forensic analysis, and broadcast engineering all depend on it. Classical codecs
guarantee bit-exact reproducibility by specification. Neural codecs that use
floating-point arithmetic do not: the same weights can produce slightly different
outputs on different hardware, different compiler versions, or different
floating-point rounding modes. Achieving bit-exact neural decoding is an open
engineering problem.

=== Standardization

Streaming infrastructure is built around standards: H.264, H.265, AV1, VP9.
Every browser, every smart TV, every content delivery network supports these
formats. A new codec format requires browser support, device driver support,
CDN transcoding pipelines, and player compatibility, a multi-year process that
starts with an international standards body (ITU-T, MPEG, or AOM). As of 2026,
no end-to-end neural video codec has been standardized. JPEG AI (for still
images, Chapter 58) was the first learned codec to reach ISO/IEC/ITU status,
in 2025, a milestone that took seven years from the first competitive papers.
Video will take longer.

=== Energy and Environmental Cost

Neural codec inference, at scale, consumes significantly more energy than
classical codec execution on fixed-function hardware. Streaming is already one
of the largest electricity consumers in the internet infrastructure. Replacing
hardware-accelerated AV1 with GPU-executed neural networks would dramatically
increase per-stream energy cost, a concern taken seriously by large
cloud operators.

#pitfall[
  Research papers compare neural codecs to VVC's *reference software* (VTM),
  which is unoptimized for speed and always much slower than any classical codec
  in practice. The fair comparison is against practical encoders like x265 or
  SVT-AV1. Against those, the neural advantage shrinks considerably, though it
  does not vanish.
]

== A Tiny Worked Example: INR in 20 Lines

Even without PyTorch or GPU acceleration, we can understand the INR idea with
a minimal Python sketch. The following code is illustrative; it uses numpy
rather than a real neural network library, and the "network" is a single linear
layer (essentially just a linear basis expansion). It is not competitive with
JPEG. Its purpose is to make the core loop of INR encoding and decoding
completely concrete.

#gopython("Numpy arrays and matrix operations")[
  In our tinyzip code we have worked with `bytes` and `dict`. Here we briefly
  use `numpy`, a Python library for fast array arithmetic. A numpy array stores
  a grid of numbers (all the same type) and supports operations like matrix
  multiplication (`@`), element-wise addition, and reshaping. You can create one
  from a Python list:

  ```python
  import numpy as np
  a = np.array([[1.0, 2.0], [3.0, 4.0]])  # 2×2 matrix
  b = np.array([1.0, 0.0])                 # vector of length 2
  print(a @ b)  # matrix-vector multiply: [1.0, 3.0]
  ```

  Numpy arrays also support slicing (`a[0, :]` = first row), broadcasting (adding
  a scalar to every element), and universal functions like `np.sin`. We will use
  these to build a tiny sinusoidal basis for our INR sketch.
]

```python
"""
Tiny INR sketch - illustrative only, not competitive with any real codec.
Encodes a small grayscale image as the weights of a linear model on a
sinusoidal feature basis; decodes by evaluating that model at every pixel.
"""

import numpy as np
from pathlib import Path

# ── Step 1: Build sinusoidal feature basis ─────────────────────────────────
def make_features(H: int, W: int, n_freqs: int = 16) -> np.ndarray:
    """
    For each pixel (y, x), create a feature vector of sin/cos at multiple
    frequencies - a simple Fourier feature map.
    Returns array of shape (H*W, 1 + 4*n_freqs).
    """
    ys = np.linspace(-1, 1, H)
    xs = np.linspace(-1, 1, W)
    yy, xx = np.meshgrid(ys, xs, indexing="ij")   # each (H, W)
    coords = np.stack([yy.ravel(), xx.ravel()], axis=1)  # (H*W, 2)
    freqs = 2.0 ** np.arange(n_freqs)             # 1, 2, 4, 8, ..., 2^(n-1)
    feats = [np.ones((H * W, 1))]                 # bias term
    for f in freqs:
        feats.append(np.sin(f * np.pi * coords))  # 2 columns per frequency
        feats.append(np.cos(f * np.pi * coords))  # 2 more columns
    return np.concatenate(feats, axis=1)           # (H*W, 1 + 4*n_freqs)

# ── Step 2: Encode = least-squares fit of linear weights ───────────────────
def inr_encode(image: np.ndarray, n_freqs: int = 16) -> np.ndarray:
    """
    image: (H, W) float32 array of pixel intensities in [0, 1].
    Returns weight vector of shape (1 + 4*n_freqs,).
    """
    H, W = image.shape
    F = make_features(H, W, n_freqs)              # (H*W, D)
    y = image.ravel()                              # (H*W,)
    # Normal equations: weights = (F^T F)^{-1} F^T y  (least squares)
    weights, _, _, _ = np.linalg.lstsq(F, y, rcond=None)
    return weights.astype(np.float16)             # quantize: 16-bit floats

# ── Step 3: Decode = evaluate model at every pixel ─────────────────────────
def inr_decode(weights: np.ndarray, H: int, W: int,
               n_freqs: int = 16) -> np.ndarray:
    """Returns reconstructed (H, W) float32 image in [0, 1]."""
    F = make_features(H, W, n_freqs)
    pixels = F @ weights.astype(np.float32)
    return np.clip(pixels.reshape(H, W), 0.0, 1.0)

# ── Self-test ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    rng = np.random.default_rng(42)
    img = rng.random((32, 32), dtype=np.float32)   # tiny random image

    weights = inr_encode(img)
    print(f"Original pixels : {img.size * 4} bytes (float32)")
    print(f"Encoded weights : {weights.nbytes} bytes (float16)")
    ratio = (img.size * 4) / weights.nbytes
    print(f"Compression ratio: {ratio:.1f}×")

    recovered = inr_decode(weights, 32, 32)
    mse = np.mean((img - recovered) ** 2)
    psnr = -10 * np.log10(mse + 1e-10)
    print(f"PSNR: {psnr:.1f} dB")
```

Running this on a 32×32 float image with `n_freqs=16` gives a weight vector of
$1 + 4 times 16 = 65$ values. The original image is $32 times 32 = 1024$ pixels
(each 4 bytes as float32 = 4096 bytes). The weight vector at float16 is
$65 times 2 = 130$ bytes, a roughly 31× compression ratio. The reconstruction
quality depends entirely on how well a sinusoidal basis can approximate the
image. For a smooth image the fit is excellent; for a noisy image, many
frequencies are needed and the compression is less impressive.

Real INR systems (COIN, NeRV) use deeper networks and gradient-based
optimization (not closed-form least squares), which produces much better quality
at the same bit count, but the idea is identical.

== Where the Field Stands in 2026

From the vantage point of mid-2026, here is where neural video compression stands.

*Rate-distortion:* On standard benchmarks, the best neural codecs (DCVC-DC/FM)
have definitively surpassed VVC's reference software. This is a genuine
scientific achievement: the hand-crafted classical codec line that dominated
for fifty years has been exceeded. However, ECM (the Enhanced Compression Model
from JVET, Chapter 55) is still ahead of neural codecs on some benchmarks,
suggesting that the classical engineering tradition has not been exhausted.

*Speed:* DCVC-RT achieved real-time GPU encoding in 2024–2025, closing the most
glaring gap. Neural decoding is still slower than fixed-function hardware
decoders for classical codecs, but the gap is narrowing with NPU hardware.

*INRs:* NeRV and its descendants are competitive with H.264 in quality, faster
to decode than most neural codecs, but still slow to encode. The meta-learning
approach (PNVC, 2024) reduces encoding time by pre-training the network on a
dataset so that overfitting to a new video starts from a better initial point,
a promising direction. Practical INR deployment remains niche as of 2026.

*Standardization:* No neural video codec has been standardized. JPEG AI
(for images) reached ISO status in early 2025. Discussions within MPEG and
JVET about "NNVC" (Neural Network Video Coding) are active but no standard
timeline exists. This is the single biggest barrier to widespread adoption.

*Perceptual quality:* At very low bitrates (below 0.05 bits per pixel per
frame), generative neural codecs (adding a diffusion or GAN decoder to DCVC-
style coding, as seen in DiffVC-RT (2025)) produce dramatically better
perceptual quality than any classical codec. This mirrors what we saw for
images in Chapter 58. The "hallucinated detail" concern applies here too:
generative video codecs can invent plausible motion that was not in the
original.

#aside[
  The NeRF (Neural Radiance Field) paper by Mildenhall et al. (2020) used INRs
  for a different purpose: representing 3D scenes so that novel viewpoints could
  be rendered. The connection to compression was noticed quickly: a NeRF is
  implicitly compressing 3D information into a set of network weights. Storing
  a NeRF representation of a scene costs far less than storing all the raw camera
  footage, and the decoder (the renderer) can synthesize any viewpoint, a form
  of compression that is also a novel-view synthesis engine. This has spawned
  a whole field of "NeRF compression" and "Gaussian splatting compression" as of
  2024–2026.
]

#takeaways((
  "DVC (CVPR 2019) was the first end-to-end neural video codec: it neuralized every block of the classical hybrid pipeline (optical flow, motion coding, residual coding) and trained them jointly via a rate–distortion loss.",
  "The DCVC family (2021–2025) made the key conceptual shift from residual coding to conditional coding: instead of subtracting a pixel-domain prediction, they condition the entropy model on rich latent-space temporal context, which is information-theoretically tighter.",
  "VCT (NeurIPS 2022) removes explicit motion estimation entirely, using a transformer to predict per-frame latent distributions from previously transmitted latents; the network discovers its own notion of temporal predictability.",
  "Implicit Neural Representation (INR) compression stores a signal as the weights of a small network trained to memorize it; encoding is training, decoding is inference. COIN (2021) beat JPEG at low image bitrates with this idea.",
  "NeRV (NeurIPS 2021) extended INRs to video by mapping frame indices (not pixel coordinates) to full output frames, achieving 25–130× faster encode/decode than pixel-wise INRs.",
  "The central tension of INR codecs: decoding is fast (one GPU forward pass per frame), but encoding is slow (training a network from scratch per video clip).",
  "As of 2026, DCVC-RT is the first neural video codec with real-time GPU encoding and meaningful bitrate savings over VVC. No neural video codec has been standardized. Hardware, bit-exactness, and standardization remain the dominant barriers to deployment.",
))

== Exercises

#exercise("59.1", 1)[
  A classical codec uses block motion estimation to find that a 16×16 block in
  frame $t$ came from position $(x+3, y-2)$ in frame $t-1$. DVC replaces this
  with an optical-flow network. In plain words: (a) what does a dense optical-
  flow field represent that block motion vectors do not? (b) Why is a dense
  flow field potentially more expensive to compress than a set of block vectors?
]

#solution("59.1")[
  (a) A block motion vector assigns a single displacement $(Delta x, Delta y)$
  to the whole 16×16 block: every pixel in the block is assumed to have moved
  by the same amount. A dense optical flow field assigns a separate displacement
  $(Delta x, Delta y)$ to *every* pixel individually, capturing smoothly varying
  motion (e.g., a spinning object where each pixel moves differently), partial
  occlusions, and fine-grained motion boundaries that block vectors miss.
  (b) A dense flow field has $H times W$ motion vectors rather than
  $ceil(H/16) times ceil(W/16)$ block vectors, roughly 256× more data. This
  must be compressed by the motion codec. DVC handles this with a learned image
  codec applied to the 2D flow field; the flow field is smooth enough that the
  codec compresses it well, but the raw size is larger.
]

#exercise("59.2", 1)[
  In the DCVC approach, there is no explicit residual $r = x_t - tilde(x)_t$.
  Yet the encoder still needs to send information about what changed between
  frames. Where does that information go? How does the decoder know what changed?
]

#solution("59.2")[
  In DCVC, the encoder still transmits the full latent $hat(y)_t$ of the current
  frame; it does not subtract anything. What changes is how those latents are
  *entropy coded*: the entropy model is conditioned on temporal context $phi_t$
  (feature maps from previously decoded frames), so it assigns very short codes
  to latent coefficients that the context predicts well, and longer codes to
  coefficients that are surprising. The "information about what changed" is
  implicitly carried by the latent coefficients that the entropy model *could not*
  predict; those are the ones that cost significant bits. The decoder
  reconstructs $hat(x)_t$ from $hat(y)_t$ and $phi_t$ using the learned decoder
  network; the network has learned to combine current-frame latents with temporal
  context to produce a good reconstruction.
]

#exercise("59.3", 2)[
  The conditional entropy inequality states $H(Y | X) <= H(Y)$.
  (a) In DVC-style residual coding, what plays the role of $Y$ and what plays
  the role of $X$? (b) In DCVC-style conditional coding, what plays the role of
  $Y$ and $X$? (c) Both approaches use temporal context; why does conditional
  coding potentially extract more benefit from the same context information?
]

#solution("59.3")[
  (a) In DVC residual coding: $Y$ is the residual $r = x_t - tilde(x)_t$ and
  $X$ is the warp prediction $tilde(x)_t$. The context $X$ is used in pixel
  space before encoding, literally subtracted. The encoder then compresses $r$,
  which has no further access to $X$.

  (b) In DCVC: $Y$ is the full current-frame latent $hat(y)_t$ and $X$ is the
  temporal context $phi_t$ (features from past decoded frames). The entropy
  model explicitly computes $p(hat(y)_t | phi_t)$ and uses it for coding.

  (c) Residual coding uses $X$ in pixel space; if motion estimation is imperfect,
  the residual still contains large values. Conditional coding uses $X$ in
  *latent* space, where the network has learned a much richer representation.
  The entropy model can condition on patterns (texture statistics, object-level
  features, scene semantics) that have no simple pixel-domain description but
  are highly predictive of what latent coefficients will look like, squeezing
  more from the same temporal context.
]

#exercise("59.4", 2)[
  Write a Python function `nerv_params(H, W, n_frames, hidden_dim)` that
  computes and returns the *total number of parameters* in a simplified NeRV
  network consisting of: (1) an embedding matrix mapping frame indices to
  hidden vectors (shape: `n_frames × hidden_dim`), (2) two upsampling
  convolutional blocks each with `hidden_dim` input and output channels and
  a 3×3 kernel, and (3) a final 1×1 convolution from `hidden_dim` to 3 (RGB).
  Ignore bias terms. Then answer: for a 100-frame, 720p (1280×720) video with
  `hidden_dim=128`, what is the parameter count? What is the raw pixel data size
  (in bytes, at 8 bits per channel)?
]

#solution("59.4")[
  ```python
  def nerv_params(H: int, W: int, n_frames: int, hidden_dim: int) -> int:
      # Embedding: n_frames vectors of size hidden_dim
      embed = n_frames * hidden_dim
      # Two 3x3 conv blocks (depth-preserving, hidden_dim -> hidden_dim)
      conv_block = 2 * (hidden_dim * hidden_dim * 3 * 3)
      # Final 1x1 conv: hidden_dim -> 3
      final = hidden_dim * 3 * 1 * 1
      return embed + conv_block + final

  # 720p, 100 frames, hidden_dim=128
  params = nerv_params(720, 1280, 100, 128)
  print(f"Parameters: {params:,}")
  # embed = 100 * 128 = 12,800
  # conv_block = 2 * 128*128*9 = 294,912
  # final = 128*3 = 384
  # total = 308,096

  raw_bytes = 100 * 1280 * 720 * 3  # 3 bytes per pixel
  print(f"Raw pixels: {raw_bytes:,} bytes")
  # = 276,480,000 bytes ≈ 263 MB
  ```

  Parameter count: 308,096.
  At 4 bytes each (float32) that is 1,232,384 bytes ≈ 1.2 MB.
  Raw pixel data: 276,480,000 bytes ≈ 263 MB.
  The network represents the video at roughly 1.2 MB/263 MB ≈ 0.45% of its raw
  size, before we have even applied weight quantization or entropy coding. Of
  course at this extreme compression the reconstruction quality will be poor;
  a real NeRV network uses many more upsampling stages and larger channels.
]

#exercise("59.5", 2)[
  VCT's transformer is said to learn "temporal prediction without motion
  estimation." Concretely: if a transformer is shown the latents
  $hat(y)_1, hat(y)_2, ..., hat(y)_(t-1)$ of a panning shot (the camera moves
  slowly left), what kind of pattern in the latents would the transformer need
  to learn in order to accurately predict $hat(y)_t$? Describe this in intuitive
  terms, with no mathematics required.
]

#solution("59.5")[
  In a panning shot, the camera moves slowly left, so the content visible at
  the right edge of frame $t$ is the content that was just off-screen to the
  right in frame $t-1$, and everything else shifts one position to the left.
  In the latent space (a compressed grid of feature vectors), this manifests
  as a spatial *shift* of the entire feature map by a small amount. The
  transformer would need to learn: "when I see a sequence of latent grids where
  each one is the previous one shifted slightly in the same direction, the next
  one will be shifted by the same amount again." This is like predicting the
  next step in a geometric sequence. The attention mechanism (see the transformer
  box earlier in this chapter) allows
  the transformer to look at multiple past frames simultaneously and infer the
  shift direction and magnitude, then predict the corresponding shifted version
  of the previous latent as the most likely next latent. No explicit "optical
  flow" is needed; the transformer learns to do shift prediction as a special
  case of pattern continuation.
]

#exercise("59.6", 3)[
  *Research question.* The DCVC-RT paper (2024–2025) claims real-time encoding
  at 125+ fps for 1080p video on a modern GPU, with a ~21% bitrate saving over
  VVC. A classical hardware H.265 encoder chip does 240 fps at 1080p at a
  fraction of a watt. (a) In what streaming scenarios does DCVC-RT's quality
  advantage make the extra compute cost worthwhile? (b) In what scenarios does it
  not? (c) What hardware or software development could change this trade-off in
  the next 5 years? Justify each answer with concrete examples.
]

#solution("59.6")[
  (a) The compute cost is worth it in scenarios where encoding happens *once*
  and the video is served *many times*: video-on-demand libraries (Netflix,
  YouTube), where a film is encoded once and watched by millions. A 21% bitrate
  saving on a film streamed 100 million times saves enormous CDN bandwidth cost.
  The GPU cost of encoding is amortized over all playback events. Also worth
  it: high-value, ultra-low-latency scenarios where quality per bit matters more
  than encoding hardware cost: 8K sports broadcasting, medical video archival.

  (b) Not worth it for: live streaming (sports, gaming, video calls) where there
  is no time to encode offline and the GPU must be doing other work. Consumer
  cameras and smartphones where dedicated H.264/HEVC silicon encodes at zero
  marginal energy cost. Any context where the decoder is a classical hardware
  chip that cannot run neural inference, which is still most end-user devices
  in 2026.

  (c) Changes that could shift the trade-off: (1) NPU silicon designed for
  DCVC-RT inference shipped in devices; once the decoder has dedicated hardware,
  energy and speed become competitive. (2) Standardization: if DCVC-RT (or a
  successor) becomes an ISO/IEC standard, browser and OS vendors implement it,
  and CDN pipelines support it. (3) Continued GPU/NPU efficiency improvements:
  at current improvement rates, the compute gap between neural and classical
  decoding narrows by roughly 2× every 2–3 years.
]

== Further Reading

The primary source for DVC is #link("https://arxiv.org/abs/1812.00101")[Lu et al. (2019), "DVC: An End-to-End Deep Video Compression Framework," CVPR 2019], available open access. For the DCVC family, the Microsoft Research GitHub repository at #link("https://github.com/microsoft/DCVC")[github.com/microsoft/DCVC] hosts code and links to all papers in the series. The NeurIPS 2021 DCVC paper is at #link("https://arxiv.org/abs/2109.15047")[arXiv:2109.15047].

VCT is described in #link("https://arxiv.org/abs/2206.07307")[Mentzer et al. (2022), "VCT: A Video Compression Transformer," NeurIPS 2022]. The paper is unusual for a neural compression paper in its architectural simplicity.

For INRs, start with the COIN paper at #link("https://arxiv.org/abs/2103.03123")[arXiv:2103.03123] and the NeRV paper at #link("https://arxiv.org/abs/2110.13903")[arXiv:2110.13903]. The SIREN network that underlies COIN is described in Sitzmann et al. (NeurIPS 2020), #link("https://arxiv.org/abs/2006.09661")[arXiv:2006.09661].

For a comprehensive survey of learned video compression, Yang et al. (2023), "An Introduction to Neural Data Compression," is an excellent graduate-level overview: #link("https://arxiv.org/abs/2202.06533")[arXiv:2202.06533].

On the practical deployment gap, the Streaming Learning Center's evaluation of DCVC-RT is an accessible technical analysis aimed at industry practitioners.

#bridge[
  This chapter closed the video chapter of learned compression. We have seen
  neural codecs conquer images, video, and now approach real-time video speeds.
  But we have not yet touched the most abundant signal on the internet after
  video: *audio*. Chapter 60 turns to neural audio codecs (SoundStream (2021),
  EnCodec (2022), DAC (2023)) and discovers something unexpected: the very
  same residual vector quantization technique that makes a codec small also
  produces a perfect *tokenizer* for audio language models. The codec and the
  AI tokenizer converge.
]
