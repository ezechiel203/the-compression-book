#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Generative and Perceptual Codecs

#epigraph[
  A perfect photograph is not the goal of the painter. Why should it be the goal of the compressor?
][Anonymous research engineer, circa 2020]

Picture two images side by side on your screen. On the left is a face compressed by a conventional
codec at 0.1 bits per pixel — a bitrate so stingy that every block of skin has smeared into a
soap-opera blur, and the hair looks like it was sculpted from melted butter. On the right is the
same person's face at the same file size, reconstructed by a generative codec. Every strand of hair
is crisp. The pores look real. The eyes have that wet glint that says "alive." You would bet money
the right image was the original.

Here is the catch: it wasn't. The hair on the right was invented. The pores were dreamed up by a
neural network that asked itself, "Given this blurry code, what would a plausible human face look
like?" It guessed correctly — impressively so — but it guessed.

That one observation unlocks everything in this chapter. We are leaving the world where a codec
tries to reproduce pixels faithfully, and entering one where a codec tries to reproduce
*experience* faithfully, even if it has to make things up. This shift is philosophically radical,
practically powerful, and ethically thorny, all at once.

#recap[
  In Chapter 56 we learned the machine-learning vocabulary: neurons, gradient descent,
  autoencoders, GANs, and diffusion models. In Chapter 57 we saw how Ballé's team (2016–2018)
  built the first learned image codecs by plugging an autoencoder into a rate–distortion loss,
  using quantization-as-noise to make the whole pipeline differentiable, and adding a hyperprior
  to transmit side information about the latent's local statistics. Those codecs were trained to
  minimize *mean squared error* — which means they tried to be as pixel-accurate as possible.
  This chapter asks what happens when you train for *perceptual quality* instead, and why that
  change opens up a whole new category of compressor.
]

#objectives((
  "Explain the rate–distortion–perception tradeoff and why MSE codecs go blurry at low bitrates.",
  "Describe how a GAN discriminator loss trains a codec decoder to produce photo-realistic output.",
  "Walk through the HiFiC architecture and the human-preference results that validated it.",
  "Explain how diffusion-model decoders extend the idea to ultra-low bitrates, using PerCo as the example.",
  "Understand StableCodec's one-step distillation approach for faster decoding.",
  "Articulate the 'hallucinated detail' debate: when perceptual codecs are appropriate and when they are dangerous.",
  "Evaluate the current state of standardization (JPEG AI) and deployment barriers.",
))

== The Blur Problem: Why MSE Fails at Low Bitrates

To understand why generative codecs exist, you first need to feel the problem they solve.

Suppose you are compressing a portrait at a very aggressive ratio — 50:1, say. Most of the
detail is gone; only a skeleton of information survives in the bitstream. When the decoder
reconstructs the image, it must fill in all those missing pixels *somehow*. The classical answer,
baked into every MSE-trained model, is: *average over all plausible completions*.

Think of it this way. At some location in the image, the missing pixel might reasonably be any
shade from light grey to dark grey. The MSE-optimal reconstruction picks the middle grey —
exactly the average. The result: every uncertain region becomes smooth and grey. This is why
heavily compressed images look greasy and soft. The decoder is not being lazy; it is doing
exactly what MSE asks — minimizing the expected squared difference between possible
reconstructions. The mathematical average of many different sharp textures is an
indistinct blur.

This is not a bug in any particular implementation. It is a fundamental consequence of optimizing
for mean squared error when the reconstruction is uncertain.

#gomaths("Mean Squared Error and Why Averaging Causes Blur")[
  *Mean squared error* (MSE) between an original image $x$ and a reconstruction $hat(x)$ is:

  $ "MSE" = (1)/(N) sum_(i=1)^(N) (x_i - hat(x)_i)^2 $

  where $N$ is the number of pixels and $x_i$, $hat(x)_i$ are the $i$-th pixel values. Smaller
  MSE means less average pixel-level difference, which sounds good.

  The problem appears when the decoder is uncertain: suppose pixel $i$ could plausibly be 80 or
  120 (on a 0–255 scale). If the decoder outputs 100 (the average), it incurs error $(100-80)^2
  = 400$ or $(100-120)^2 = 400$ — a middle-of-the-road penalty. If it guesses boldly and outputs
  80, it scores 0 on the 80-case but 1600 on the 120-case — much worse on average. So MSE
  *punishes boldness* and rewards bland averaging. Applied across millions of pixels, this produces
  the characteristic smooth blur.

  *Signal-to-noise ratio* (PSNR) is just MSE in logarithmic disguise:

  $ "PSNR" = 10 log_10 ((255^2)/"MSE") " dB" $

  Higher PSNR sounds better, but a blurry reconstruction can have higher PSNR than a sharp one
  that invented slightly wrong details — another sign that PSNR misses perceptual quality.
]

Human vision is not an MSE meter. It is exquisitely sensitive to edges, textures, and whether
something looks *like* a known material (hair, wood, fabric) — but quite insensitive to whether
each pixel is exactly right. A codec that invents plausible hair texture may fool the eye even
though its MSE is terrible. A codec that blurs everything to the correct average may score well
on PSNR while looking dreadful.

== The Rate–Distortion–Perception Tradeoff

Yochai Blau and Tomer Michaeli at the Technion formally proved what engineers had felt for years.
Their 2019 paper, "The Perception-Distortion Tradeoff," extended Shannon's two-dimensional
rate–distortion curve into a *three-dimensional* surface that adds perception as a third axis.

#definition("Perceptual quality (Blau–Michaeli)")[
  A codec has perfect perceptual quality if its reconstructed images are statistically
  indistinguishable from natural images — that is, the *distribution* of reconstructions matches
  the *distribution* of real photographs, not just pixel-by-pixel similarity to a specific original.
  Perceptual quality is measured by the divergence between these two distributions.
]

#theorem("The Perception-Distortion Tradeoff")[
  For any fixed bitrate $R$, there is a fundamental tradeoff between average distortion (e.g., MSE)
  and perceptual quality (e.g., distributional divergence to natural images). Achieving perfect
  perceptual quality necessarily increases distortion, and achieving zero distortion sacrifices
  perceptual quality. You cannot simultaneously minimize both.
]

#proof[
  The intuition: zero distortion means $hat(x) = x$ exactly, so the reconstruction distribution is
  just the source distribution — perfect perception too. But as the bitrate drops, $hat(x)$ must
  deviate from $x$. It can deviate in a way that stays pixel-close (low distortion, possibly blurry)
  or in a way that stays distribution-close (high perceptual quality, possibly inventing details).
  At any fixed $R$, these pull in opposite directions. Blau and Michaeli prove this formally using
  information-theoretic arguments: the rate–distortion function under a perfect-perception
  constraint is strictly larger than the unconstrained one, with the gap narrowing as $R
  -> infinity$.
]

This theorem has two startling corollaries. First, the blurry MSE codecs we criticized are not
badly designed — they are faithfully implementing a choice to minimize distortion, at the cost of
perception. Second, a perceptually perfect codec is *not* trying to reproduce your specific image.
It is trying to generate a plausible member of the set "images that look like this kind of scene."
It may show you a face with different freckles. That is the trade you are making.

#keyidea[
  The rate–distortion–perception tradeoff is a law of nature, not a limitation of any particular
  algorithm. At low bitrates, you must choose: pixel accuracy or visual realism. Generative codecs
  choose realism. MSE codecs choose accuracy. Both are valid — for different use cases.
]

#fig(
  [The rate–distortion–perception surface. At high bitrates, both low distortion and high
   perceptual quality are achievable. At low bitrates, improving perception requires accepting
   more distortion, and vice versa.],
  cetz.canvas({
    import cetz.draw: *
    // Axes
    line((0,0),(5,0), mark: (end: ">"), name: "xax")
    line((0,0),(0,4), mark: (end: ">"), name: "yax")
    content((5.3, 0))[Distortion $D$]
    content((0, 4.3))[Perception $P$]
    content((-0.8, 2.0), angle: 90deg)[better →]
    content((2.5, -0.5))[← better]
    // The tradeoff frontier curve
    bezier((0.3, 3.7),(2.5,2.5),(4.5,0.5),
           stroke: (paint: rgb("#0b5394"), thickness: 2pt))
    // Annotations
    content((0.6, 3.5), anchor: "west")[
      #box(fill: rgb("#e8f0fb"), inset: 4pt)[
        #text(size: 8pt)[Perceptual \ codecs \ (GAN/diffusion)]
      ]
    ]
    content((3.5, 1.2), anchor: "west")[
      #box(fill: rgb("#fef3e2"), inset: 4pt)[
        #text(size: 8pt)[MSE-trained \ codecs]
      ]
    ]
    // high bitrate point
    content((0.4, 0.4))[
      #text(size: 7.5pt, fill: rgb("#0b6e4f"))[High R: both possible]
    ]
    // low bitrate region label
    line((1.2,3.3),(1.5,3.1), stroke: 0.5pt)
  })
)

== HiFiC: High-Fidelity Generative Image Compression

The breakthrough paper that moved generative compression from theory to a working system was
*"High-Fidelity Generative Image Compression"*, published at NeurIPS 2020 by Fabian Mentzer,
George Toderici, Michael Tschannen, and Esa Agustsson (all at Google). Its nickname, HiFiC, is
now a landmark in the field.

=== The Core Idea: Teaching the Decoder to Fool a Critic

HiFiC's key insight is that if you want the decoder to produce realistic-looking images, you
should explicitly train it against a *critic that knows what real images look like*. In machine
learning, this critic is called a *discriminator*, and the training setup is called a *generative
adversarial network* (GAN) — introduced in Chapter 56.

Here is how the training loop works in HiFiC:

1. *The encoder* takes an image $x$ and produces a compressed latent code $hat(y)$ (quantized,
   just like Ballé's models from Chapter 57).

2. *The decoder* (also called the generator in GAN terminology) takes $hat(y)$ and produces a
   reconstruction $hat(x)$. At first, $hat(x)$ looks blurry — the decoder knows nothing about
   realistic textures yet.

3. *The discriminator* is shown two kinds of images: real photographs from the training set, and
   the decoder's reconstructions. Its job is to label each one as "real" or "fake."

4. The training loss has three parts, all minimized jointly:
   - *Rate term*: how many bits does the code $hat(y)$ take? (Same as before — minimize
     bitrate.)
   - *Distortion term*: how different is $hat(x)$ from $x$ in pixel space? (A small MSE penalty
     to keep it tethered to reality.)
   - *GAN term*: how well does the decoder fool the discriminator into calling its output "real"?

Over thousands of training steps, the decoder learns that blurry averages fool nobody — the
discriminator immediately flags them as fake. It is forced to invent convincing texture, or the
GAN loss penalizes it. The distortion term keeps it from inventing textures that are
*completely* wrong for the scene. The result is a decoder that hallucinates plausible detail
with remarkable accuracy.

#algo(
  name: "HiFiC (High-Fidelity Generative Image Compression)",
  year: "2020",
  authors: "Fabian Mentzer, George Toderici, Michael Tschannen, Esa Agustsson (Google)",
  aim: "Lossy image compression optimizing perceptual quality via GAN training, achieving high visual fidelity at bitrates where MSE codecs produce blur.",
  complexity: "Encoder: ~0.5–1 s per image (GPU). Decoder: ~0.1–0.5 s per image (GPU). Training: days on many GPUs. Significantly slower than classical codecs.",
  strengths: "Dramatically better perceptual quality than any MSE codec at low bitrates; human studies show it is preferred over BPG at half the bitrate; architecture is flexible and extends to higher resolutions.",
  weaknesses: "Pixels are not faithfully reproduced — details are invented. Unacceptable for forensic, medical, or archival uses. Slower than classical decoders. Training is expensive and brittle.",
  superseded: "Diffusion-based decoders (PerCo, StableCodec) achieve even higher realism at ultra-low bitrates. OneDC (2025) offers 40%+ bitrate reduction over prior diffusion codecs at 20x faster decoding.",
)[
  HiFiC builds on the Ballé hyperprior architecture (Chapter 57) for the encoder/entropy model.
  The decoder is augmented with a GAN generator head. The discriminator uses a PatchGAN
  architecture that classifies overlapping image patches as real or fake, which is more stable
  than classifying whole images and better at catching texture inconsistencies.

  The training loss at each step is:

  $ cal(L) = R(hat(y)) + lambda_"dist" dot.c D(x, hat(x)) + lambda_"GAN" dot.c cal(L)_"GAN" (hat(x)) $

  where $cal(L)_"GAN"$ is the hinge loss on the discriminator, and $lambda_"dist"$,
  $lambda_"GAN"$ are hyperparameters controlling the distortion/perception balance.
]

=== What the Human Studies Found

The NeurIPS 2020 paper included careful human preference studies — arguably the most important
part of the work, because perceptual quality is fundamentally a human judgment.

The key result: *HiFiC at 0.237 bits per pixel (bpp) was preferred by human raters over BPG
(a state-of-the-art classical codec) at 0.504 bpp*. BPG was using more than twice the bits, but
people liked HiFiC's output better. Against MSE-optimized learned codecs, HiFiC needed only
about 60% of the bits to be equally preferred.

At the lowest tested bitrates (around 0.14 bpp), the comparison was not even close. BPG produced
severe blocking artifacts. MSE codecs produced wax-museum skin. HiFiC produced faces that raters
frequently described as "photographic," even though they had never existed as actual photographs.

#gopython("Lambda Expressions and Default Arguments")[
  In the code below, you will see `lambda: ...` — a way to write a tiny, nameless function inline.
  You will also see *default argument values* in function definitions like `def foo(x, lam=0.01)`,
  which means `lam` is optional; the caller can pass a value or leave it at the default.

  ```python
  # A lambda is a one-line function with no name.
  square = lambda x: x * x
  print(square(5))   # 25

  # A function with a default argument:
  def rate_distortion_loss(rate: float, distortion: float, lam: float = 0.01) -> float:
      return rate + lam * distortion

  print(rate_distortion_loss(2.3, 140.0))         # uses lam=0.01 → 3.7
  print(rate_distortion_loss(2.3, 140.0, lam=1.0)) # uses lam=1.0 → 142.3
  ```

  The same pattern appears in neural compression training: `lam` (often written $lambda$ in papers)
  controls how much you care about distortion versus bitrate.
]

Let's look at a simplified Python sketch of the HiFiC loss computation, to make the three-part
objective concrete:

```python
# Conceptual sketch — not a full training loop, just the loss structure.
# Real implementations use PyTorch autograd; this shows the idea.

def hific_loss(
    bits_per_pixel: float,    # from the entropy model (rate term)
    mse: float,               # pixel-level distortion
    gan_loss: float,          # discriminator's verdict on realism
    lam_dist: float = 0.075,  # weight on distortion (small = more perceptual)
    lam_gan: float = 1.0,     # weight on GAN term
) -> float:
    """
    Compute the combined HiFiC training loss.
    Lower is better for each component.
    """
    rate_term = bits_per_pixel
    dist_term = lam_dist * mse
    perc_term = lam_gan * gan_loss
    return rate_term + dist_term + perc_term

# Example numbers from a mid-training batch:
loss = hific_loss(
    bits_per_pixel=0.35,
    mse=180.0,
    gan_loss=0.42,
)
print(f"Total loss: {loss:.4f}")
# Total loss: 0.3500 + 13.5000 + 0.4200 = 14.2700
```

Notice that `lam_dist` is very small (0.075), meaning the decoder is NOT being trained to be
pixel-perfect. The `lam_gan` term dominates realism. Tuning these two numbers is how you slide
along the perception–distortion tradeoff curve.

=== The Discriminator Architecture in Detail

HiFiC uses what is called a *patch discriminator* (sometimes called PatchGAN). Instead of
looking at an entire image and saying "real or fake?", the discriminator examines overlapping
$70 times 70$-pixel patches and classifies each patch. This has two advantages.

First, textures and fine details live at the patch scale — asking about a whole image can miss
subtle texture artifacts. Second, training on patches provides many more training examples per
image, which stabilizes the GAN training.

The discriminator is a small convolutional network. During training, it is updated in an
*alternating* fashion: first update the discriminator to better distinguish real patches from
fake ones, then update the encoder-decoder to better fool the updated discriminator. This
adversarial tug-of-war is what forces the decoder to produce increasingly convincing outputs.

#checkpoint[
  Why doesn't HiFiC simply use a much higher MSE weight (`lam_dist`) to keep reconstructions
  closer to the original pixels?
][
  A high MSE weight drags the decoder back toward blurry averaging — the behavior we are
  trying to escape. The whole point is that low MSE weight forces the decoder to fill in
  missing detail using generative priors rather than pixel averages. Too much MSE weight
  and you are back to a conventional MSE-trained codec with a small GAN nudge that barely helps.
]

== PerCo: Diffusion Decoders for Ultra-Low Bitrates

By 2022, researchers had noticed that GAN-trained decoders, while impressive, had a ceiling.
At very low bitrates (below about 0.05 bpp), the compressed code contained so little information
that even the best GAN decoder had little to anchor on. Reconstructions sometimes lost semantic
structure entirely — a face might keep its texture but lose the shape of the nose.

The new idea: replace the GAN decoder with a *diffusion model* — the same architecture that had
just transformed image generation. Diffusion models (introduced in Chapter 56) generate images
by starting from random noise and iteratively removing that noise, guided by a conditioning signal.
For compression, the conditioning signal is the compressed code.

*PerCo* (Towards Image Compression with Perfect Realism at Ultra-Low Bitrates, ICLR 2024) by
Careil, Muckley, Verbeek, and Lathuilière is the landmark paper for this approach.

=== How PerCo Works: Semantic Code + Diffusion Prior

PerCo operates in two steps. First, an encoder compresses the input image into a tiny code
at extremely low bitrates — as few as 0.003 bpp. This code cannot possibly encode every pixel;
instead it encodes the *semantic gist* of the image: the broad layout of shapes, major colors,
coarse identity information.

The code is produced using *vector quantization* of VAE features — the image is passed through
a variational autoencoder (Chapter 56), the resulting latent is vector-quantized (snapped to a
small codebook of learned discrete symbols), and the codebook indices are entropy-coded and
transmitted.

At the decoder, PerCo conditions a pre-trained *text-to-image diffusion model* (specifically
a version of Stable Diffusion) on the received code. The diffusion model then *generates* a
full-resolution image that matches the semantic code. In multiple denoising steps it fills in
all the texture, lighting, fine detail — everything the code is too small to specify.

#algo(
  name: "PerCo (Perceptual Compression via Conditioned Diffusion)",
  year: "2024",
  authors: "Careil, Muckley, Verbeek, Lathuilière (Meta AI / Inria)",
  aim: "Ultra-low-bitrate image compression (0.003–0.1 bpp) using a semantic encoder and a conditioned pre-trained diffusion model as decoder.",
  complexity: "Encoder: moderate (VAE encode + VQ). Decoder: slow — requires 20–50 denoising steps, each a forward pass through a large diffusion model. Orders of magnitude slower than any classical or GAN-based codec.",
  strengths: "Achieves plausible reconstructions at bitrates where every other codec fails completely. Leverages powerful generative priors from internet-scale pretraining. Semantically coherent even at 0.003 bpp.",
  weaknesses: "Very slow decoding. Reconstructions can differ substantially from the original in pixel content, especially at the lowest bitrates. Fine detail is generated, not preserved. Requires a large pre-trained diffusion model at the decoder.",
  superseded: "StableCodec (ICCV 2025) achieves similar perceptual quality with one-step decoding, approximately 20x faster. OneDC (NeurIPS 2025) provides 40%+ further bitrate reduction.",
)[
  The key technical innovation is using the compressed code as a *conditioning signal* for
  guided diffusion, rather than as a direct input to a deterministic decoder. This gives the
  diffusion model's learned prior full freedom to hallucinate texture and detail, anchored only
  by the semantic content of the code. The result is a codec that does not "uncompress" an
  image so much as "regenerate" it.
]

=== The Denoising Process as a Decoder

To see why diffusion decoding is so powerful at ultra-low bitrates, think about what information
is in a 0.003 bpp code. At that rate, a 512×512 image is coded in roughly *800 bits* — about
100 bytes. That is enough to store, say, the rough layout of a face: "eyes here, mouth here,
hair color approximately brown, skin tone approximately medium." It cannot store the exact shape
of every eyelash.

The diffusion decoder starts with pure noise and asks, in each denoising step: "Given this noise
and the code saying 'brown-haired face with eyes here,' what should the image look like?" After
20–50 steps, it has assembled a photo-realistic face that matches the layout code but has invented
every fine detail from the model's prior over faces.

This is genuinely impressive — but it means the *specific person's eyelashes* were not preserved.
What was preserved is "someone who looks like this person." At 0.003 bpp, that may be the best
any system can do.

#gomaths("Vector Quantization")[
  *Vector quantization* (VQ) is the multi-dimensional version of rounding. We met it in
  Chapter 39 (Quantization) as the LBG/k-means idea; here it is the engine that turns a
  continuous latent into a few transmittable integers. You have a *codebook* of $K$ prototype
  vectors $e_1, e_2, dots, e_K$ (learned during training). When you receive a new vector $z$
  (a chunk of latent features), you find the nearest prototype:

  $ hat(z) = e_k "where" k = arg min_j norm(z - e_j) $

  #mathrecall[$arg min_j$ (Chapter 39) means "the index $j$ that makes the following expression
  smallest" — we keep the *position* of the nearest codeword, not the distance itself.
  $norm(dot.c)$ is the vector length (Chapter 12), so $norm(z - e_j)$ is how far apart the two
  vectors are.]

  and transmit only the index $k$, which takes $log_2 K$ bits. The decoder looks up $e_k$ and
  uses it in place of $z$.

  *Example:* codebook size $K = 1024$, latent dimension $= 256$. Each code takes
  $log_2 1024 = 10$ bits, instead of $256 times 32 = 8192$ bits for a 32-bit float vector.
  That's an 819× compression of the latent — at the cost of some approximation.

  VQ is heavily used in modern image and audio codecs (VQ-VAE, EnCodec) because it produces
  naturally discrete codes that can be entropy-coded and transmitted exactly.
]

```python
# Minimal illustration of vector quantization (NumPy sketch).
# Real use requires learning the codebook via gradient descent; this shows lookup.

import numpy as np
from numpy.typing import NDArray

def vq_encode(z: NDArray, codebook: NDArray) -> int:
    """
    Find the nearest codebook entry to latent vector z.
    Returns codebook index k (the 'code').
    codebook shape: (K, D) where K = number of entries, D = dimension.
    """
    # Compute squared Euclidean distance to every entry.
    diffs = codebook - z[np.newaxis, :]   # shape: (K, D)
    dists = np.sum(diffs ** 2, axis=1)    # shape: (K,)
    return int(np.argmin(dists))           # index of closest entry

def vq_decode(k: int, codebook: NDArray) -> NDArray:
    """Reconstruct the latent from codebook index k."""
    return codebook[k]

# Tiny example: 4 codebook entries of dimension 3.
rng = np.random.default_rng(42)
codebook = rng.standard_normal((4, 3))

z = np.array([0.1, 0.9, -0.3])   # some latent vector to encode
k = vq_encode(z, codebook)
z_hat = vq_decode(k, codebook)

print(f"Input z:       {z}")
print(f"Codebook index: {k}")
print(f"Reconstruction: {z_hat}")
print(f"Error:         {np.linalg.norm(z - z_hat):.4f}")
```

=== A Worked Bitrate Example

Let's trace through the numbers to feel what ultra-low bitrate really means.

*Image:* 512 × 512 pixels, RGB. Raw size: $512 times 512 times 3 times 8 = 6{,}291{,}456$ bits = 786 KB.

*PerCo target:* 0.003 bpp. That's $0.003 times 512 times 512 = 786$ bits — about *98 bytes*.
The compressed file is 8,000× smaller than the raw image.

To put 98 bytes in perspective: the JPEG header alone is larger than that. A single line of
this book's text is larger than that. Yet PerCo can decode a photo-realistic face from 98 bytes.
The trick is that those 98 bytes say "face, rough position of features, approximate identity,"
and the diffusion model's massive pre-trained knowledge of what faces look like fills in the rest.

*For comparison:* conventional JPEG at this bitrate produces a $32 times 32$ thumbnail stretched
to $512 times 512$ — indistinguishable mush. BPG (H.265-based) fails similarly. PerCo produces
something your eye reads as a plausible portrait.

== The 2025 Push: One-Step Distillation

The PerCo system's biggest practical problem was speed. A multi-step diffusion decoder might
require 20–50 forward passes through a large neural network to decode one image. On a consumer
GPU, that could take 5–15 seconds per image. For streaming or real-time applications, that
is untenable.

The 2025 research sprint focused on *distillation*: training a small, fast "student" network
to mimic the output of the slow multi-step diffusion "teacher" in a *single forward pass*.

=== StableCodec (ICCV 2025)

*StableCodec: Taming One-Step Diffusion for Extreme Image Compression* (Zhang et al., ICCV 2025)
is the most polished of the 2025 one-step systems. Its architecture:

1. A *latent codec* compresses the image into a noisy latent representation (not quite the full
   latent of a diffusion model — a careful partial encoding that preserves enough for one-step
   decoding).
2. A *one-step diffusion decoder*, distilled from a multi-step teacher, reconstructs the full
   image in a single forward pass.
3. A *fidelity module* injects high-frequency detail hints from the code to keep the output
   anchored to the original rather than drifting into pure hallucination.

StableCodec reports achieving compression to as low as 0.005 bpp with photo-realistic results,
while cutting decoding time by approximately 20× compared to multi-step methods. Encoding
speed is also improved because the latent codec is simpler than a full VAE.

*OneDC* (One-step Diffusion-based image Codec, arXiv 2505.16687, 2025) takes a complementary
approach: it uses a *semantic distillation mechanism* that transfers knowledge from a pre-trained
generative tokenizer into the hyperprior codec, combined with hybrid pixel- and latent-domain
optimization. OneDC reports over 40% bitrate reduction versus previous multi-step diffusion
codecs while achieving 20× faster decoding.

#history[
  The speed problem for generative codecs has a parallel in classical codec history: the early
  H.264 encoders took many seconds per frame; hardware acceleration eventually made them
  real-time. Neural codec advocates argue the same will happen here — dedicated neural
  processing units (NPUs) will accelerate diffusion decoding just as video DSPs accelerated
  motion compensation. As of 2026, this is still a hope more than a reality for most deployment
  targets, but smartphone NPU capabilities are improving rapidly.
]

=== CoD-Lite: Toward Real-Time Diffusion Codecs

Even more aggressive is the CoD-Lite direction (Compression with Diffusion, Lite variant, 2026),
which explores quantized, pruned diffusion decoders that can run at near-real-time rates on
modern mobile NPUs. The 2026 papers in this space suggest that the gap between perceptual quality
and acceptable latency is narrowing, though real-time decoding of 4K images via diffusion
remains out of reach on general hardware as of mid-2026.

== The Hallucinated Detail Debate

Every engineer who has seen a perceptual codec demo has the same reaction: "That's impressive —
but is it honest?" This question is not merely philosophical. It has sharp practical consequences.

#misconception[
  Perceptual codecs are just better versions of regular lossy codecs — same idea, better quality.
][
  There is a fundamental difference. A lossy JPEG loses detail by omission: it blurs or rounds
  things that were there. A GAN or diffusion codec loses detail by *substitution*: it replaces
  what was there with something it invented. An MSE codec never adds a freckle that was not there;
  a perceptual codec might. This distinction matters enormously in some domains.
]

=== Where Hallucination Is Acceptable

For many everyday uses, the hallucination is harmless or even desirable.

*Social media and messaging:* Nobody checks whether every hair strand in a compressed selfie
matches the original. The face looks good, the mood is conveyed, the memory is captured. A
20× smaller file that looks better to the eye is an obvious win.

*Video streaming at low bandwidth:* A diffusion-decoded movie frame that invents correct-looking
background textures causes no harm if it looks cinematic. The viewer never had access to the
ground truth anyway.

*Satellite and aerial imagery for public view:* A perceptual codec that renders plausible
foliage and building facades at low bitrates is fine for orientational purposes — checking
which side of a city you're looking at.

=== Where Hallucination Is Dangerous

*Medical imaging:* This is the clearest danger. A mammogram compressed with a GAN codec might
show a plausible-looking nodule that was invented. Or erase a real one. Either outcome could
affect a clinical decision. Medical imaging standards require lossless or tightly bounded lossy
compression precisely to prevent this. Perceptual codecs are contraindicated here unless their
reconstruction can be shown to have bounded, studied effects on clinical markers.

*Forensic and legal evidence:* A surveillance camera image of a crime scene cannot be perceptually
compressed if it is to be admitted as evidence. The chain of custody requires that the image
represents what was captured, not what a neural network imagined was plausible.

*Satellite intelligence:* Counting vehicles in a parking lot from a satellite image requires
that the vehicles in the image are real. A perceptual codec that invents a plausible-looking
parking situation (with slightly different vehicle counts) is useless or worse.

*News photojournalism:* Professional standards require that photographic evidence of events not
be fabricated. A perceptual codec applied in an archival pipeline could subtly alter the
documentary record.

*Archival and scientific data:* Astronomers, climatologists, and archaeologists need their data
reproduced faithfully. A generative model's idea of what a galaxy "should" look like is not a
substitute for the photons that actually arrived at the telescope.

#pitfall[
  The hallucination danger is not obvious to end users. A GAN-compressed image looks *more*
  sharp and detailed than the original at the same bitrate, not less. Naive users may actually
  prefer the perceptual codec's output without realizing it has been altered at the pixel level.
  Systems deploying perceptual codecs must clearly communicate this to users, and must disable
  them by default in contexts where pixel fidelity matters.
]

=== The Hallucination Index

Some researchers have proposed a *hallucination index* — a number measuring how much a
perceptual codec's output deviates from what the original image would have looked like
under an ideal lossless system. Computing it requires access to the original (to compare),
which limits its use in deployed systems. But it is a useful framework: any deployment of a
perceptual codec should include this kind of audit, not just a PSNR or LPIPS score.

A 2024–2025 trend in the research community is using confidence maps: the decoder also outputs
a per-pixel uncertainty estimate, and regions of high hallucination probability are flagged.
This allows downstream systems (or human reviewers) to know which parts of the image were
faithfully reproduced and which were generated.

#aside[
  The word "hallucination" for generative neural networks is borrowed from AI-assistant research,
  where it describes a language model confidently stating something false. In compression, the
  term is slightly more nuanced: the generated detail is usually *plausible* (a fair sample from
  the space of natural images given the code), not random noise. But it is still not the truth.
]

== JPEG AI: Standardizing the Neural Codec

While academia produced impressive research systems, the practical adoption of neural image
codecs in real products requires standardization — an agreed-upon bitstream format so that any
conforming encoder and decoder interoperate. This is what JPEG did for DCT-based compression
in 1992, and what the industry needed for learned codecs.

*JPEG AI* (ISO/IEC 6048) is the first international standard for end-to-end learning-based
image coding. Its history:

- *2022:* JPEG Committee published a Call for Proposals for JPEG AI.
- *2023:* Working Draft and Committee Draft completed.
- *October 2024:* First edition published as a standard.
- *February 2025:* At its 106th meeting, the JPEG Committee approved publication as a full
  ISO/IEC/ITU International Standard.

The standard specifies a bitstream format, conformance tests, and a reference software decoder,
but — unlike JPEG — it does not prescribe the specific neural network architecture of the encoder.
Encoders can use any architecture that produces a conforming bitstream; only the decoder profile
is standardized. This design acknowledges that neural codec architectures will keep improving.

JPEG AI's test model (version 4.3) achieves approximately 28–30% coding gains over VVC in all-intra
mode on standard benchmarks. Crucially, the standard also supports *machine vision tasks* directly
from the compressed representation: the same bitstream can be decoded for human viewing or
analyzed for object detection and segmentation without a full decode pass. This "coding for machines"
mode is a significant departure from all previous image standards.

#scoreboard(
  caption: "Compression results on the shared 512×512 test image (estimated)",
  [Uncompressed RGB], [786,432], [1.0×], [Raw bytes],
  [JPEG (quality 50)], [28,000], [28×], [Classical DCT, some blockiness],
  [AVIF (AV1-intra)], [18,000], [44×], [Modern classical, Chapter 45],
  [BPG (HEVC-intra)], [16,500], [48×], [Best classical at time of HiFiC],
  [Ballé hyperprior (Ch57)], [14,200], [55×], [MSE-optimized learned codec],
  [HiFiC (0.237 bpp)], [9,600], [82×], [Perceptual; preferred over BPG at 0.504 bpp],
  [PerCo (0.003 bpp)], [122], [6,446×], [Ultra-low; detail invented by diffusion],
  [StableCodec (0.005 bpp)], [200], [3,932×], [One-step diffusion; 20x faster than PerCo],
)

== A Python Sketch of Perception-Aware Training

Let us look at a more complete Python sketch that shows how the three-loss training objective
is assembled. This is conceptual — a real implementation uses PyTorch with autograd and GPU
tensors — but the structure is identical.

```python
"""
perception_training_sketch.py

Conceptual sketch of the HiFiC / perceptual codec training loop.
All tensors are plain Python floats for readability.
Real implementation: PyTorch, GPU, proper autograd.
"""
from dataclasses import dataclass
from typing import Protocol
import math

@dataclass
class TrainingConfig:
    lam_rate: float = 1.0     # weight on bits-per-pixel
    lam_dist: float = 0.075   # weight on pixel distortion
    lam_gan:  float = 1.0     # weight on GAN (perceptual) loss

class CompressionModel(Protocol):
    def encode(self, x: list[float]) -> tuple[list[int], float]:
        """Quantize and entropy-code x; return code and bits-per-pixel."""
        ...
    def decode(self, code: list[int]) -> list[float]:
        """Reconstruct pixels from code."""
        ...

class Discriminator(Protocol):
    def score(self, image: list[float]) -> float:
        """Return probability that image is real (higher = more real)."""
        ...

def mse(original: list[float], reconstruction: list[float]) -> float:
    """Mean squared error between two equal-length pixel lists."""
    n = len(original)
    return sum((a - b) ** 2 for a, b in zip(original, reconstruction)) / n

def hinge_gan_loss(disc_real_score: float, disc_fake_score: float) -> float:
    """
    Hinge GAN loss for generator (compression decoder).
    Generator wants disc_fake_score to be high (fooling discriminator).
    Loss = max(0, 1 - disc_fake_score): zero once discriminator is fooled.
    """
    return max(0.0, 1.0 - disc_fake_score)

def total_loss(
    bpp: float,           # rate: bits per pixel
    pixel_mse: float,     # distortion
    gan_loss: float,      # perception
    cfg: TrainingConfig,
) -> float:
    """Combined objective: rate + lambda_dist * distortion + lambda_gan * GAN."""
    return (
        cfg.lam_rate * bpp
        + cfg.lam_dist * pixel_mse
        + cfg.lam_gan  * gan_loss
    )

# --- Conceptual training step (what PyTorch's optimizer would compute) ------
def training_step_sketch(
    original_pixels:  list[float],
    model: CompressionModel,
    disc:  Discriminator,
    cfg:   TrainingConfig,
) -> dict[str, float]:
    """
    One conceptual training step.
    Returns a dict of loss components for logging.
    """
    # 1. Compress and decompress the image.
    code, bpp = model.encode(original_pixels)
    reconstructed = model.decode(code)

    # 2. Compute distortion.
    pixel_error = mse(original_pixels, reconstructed)

    # 3. Ask discriminator how real the reconstruction looks.
    fake_score = disc.score(reconstructed)
    real_score = disc.score(original_pixels)
    gan = hinge_gan_loss(real_score, fake_score)

    # 4. Combine into total loss.
    loss = total_loss(bpp, pixel_error, gan, cfg)

    return {
        "loss": loss,
        "bpp": bpp,
        "mse": pixel_error,
        "gan": gan,
        "fake_score": fake_score,
    }
```

The most important thing to read in this code: `lam_dist = 0.075` is very small. If we set it
to 10.0 instead, the training would optimize almost entirely for pixel accuracy — and we'd get
a standard MSE codec with a GAN term that barely matters. The small distortion weight is what
forces the perceptual magic to emerge.

== How Diffusion Decoders Are Conditioned: A Closer Look

The mechanism by which a compressed code *guides* a diffusion decoder deserves a closer look,
because it is not obvious and it differs between systems.

In standard diffusion generation (with no compression), the model starts from pure noise
$z_T tilde cal(N)(0, I)$ and takes $T$ denoising steps, each guided by a text prompt or class
label. For compression, we want to guide it by the *compressed code* instead.

#mathrecall[$z_T tilde cal(N)(0, I)$ just says "$z_T$ is random Gaussian noise." The symbol
$tilde$ reads "is distributed as"; $cal(N)$ is the *normal* (bell-curve) distribution from
Chapter 9; $0$ is its mean and $I$ (the identity matrix, Chapter 12) says every coordinate is
independent with variance $1$. In plain terms: each number in $z_T$ is an independent draw from
a standard bell curve — pure static.]

#note[
  Three pieces of neural-network plumbing appear below for the first time. A *U-Net* is the
  hourglass-shaped network diffusion models use to predict noise: it shrinks the image down to a
  small summary and back up again, with shortcut links across the waist so fine detail is not
  lost. *Cross-attention* is the mechanism by which a guiding signal (normally a text prompt,
  here the compressed code) is injected into the U-Net: at each layer, the network "looks at" the
  conditioning vectors and lets them steer what it draws. *DDIM* (Denoising Diffusion Implicit
  Models) is simply a *deterministic* recipe for the denoising steps — given the same starting
  noise and the same code, it always produces the same image, which a codec needs.
]

PerCo does this by:
1. Projecting the quantized code into an embedding that matches the size of the cross-attention
   conditioning vectors the diffusion model expects.
2. Replacing the text embedding with the code embedding in every cross-attention layer of the
   U-Net denoiser.
3. Running the standard DDIM (Denoising Diffusion Implicit Models) sampling loop, which is
   deterministic given the code — the same code always produces the same reconstruction, which
   is important for a codec (you need a defined decoding).

```python
# Pseudo-code for PerCo-style conditioned diffusion decoding.
# Real implementation uses HuggingFace Diffusers or similar.

def perco_decode(
    code_indices: list[int],       # VQ codebook indices from encoder
    codebook: list[list[float]],   # K×D learned codebook
    diffusion_model,               # pre-trained stable diffusion U-Net
    n_steps: int = 50,             # denoising steps
) -> list[float]:                  # reconstructed pixel values
    """
    Decode a compressed image using conditioned diffusion.
    The code provides semantic guidance; the diffusion model fills in detail.
    """
    # 1. Convert code indices to embedding vectors.
    code_embedding = [codebook[i] for i in code_indices]  # list of D-dim vectors

    # 2. Project to cross-attention dimension (learned linear projection).
    conditioning = project_to_attention_dim(code_embedding)  # shape matches U-Net

    # 3. Start from pure Gaussian noise in the latent space.
    latent = sample_gaussian_noise(shape=(4, 64, 64))  # U-Net latent size

    # 4. Run deterministic DDIM denoising, conditioned on code.
    for t in range(n_steps - 1, -1, -1):
        noise_pred = diffusion_model.predict_noise(latent, t, conditioning)
        latent = ddim_step(latent, noise_pred, t)  # one denoising step

    # 5. Decode latent to pixels via the VAE decoder.
    pixels = diffusion_model.vae_decode(latent)
    return pixels
```

The `ddim_step` function is deterministic — given the same noise prediction and timestep,
it always produces the same next latent. This ensures that the same compressed code always
decodes to the same image, which is a requirement for any compression system.

#gopython("Dataclasses")[
  A *dataclass* in Python is a convenient way to define a class that mostly holds data. You
  annotate the fields with types, and Python automatically generates `__init__`, `__repr__`,
  and other methods for you.

  ```python
  from dataclasses import dataclass

  @dataclass
  class CompressionResult:
      bpp: float          # bits per pixel
      psnr_db: float      # peak signal-to-noise ratio
      lpips: float        # learned perceptual similarity (lower = more similar)
      method: str = "unknown"

  r = CompressionResult(bpp=0.237, psnr_db=28.4, lpips=0.18, method="HiFiC")
  print(r)
  # CompressionResult(bpp=0.237, psnr_db=28.4, lpips=0.18, method='HiFiC')
  print(r.bpp)   # 0.237
  ```

  Dataclasses are widely used in compression research code to pass hyperparameters and results
  cleanly. The `TrainingConfig` in the code above is a dataclass.
]

== Measuring Perceptual Quality: LPIPS and FID

Because perceptual quality is not measurable by PSNR, perceptual codecs use different metrics.

*LPIPS* (Learned Perceptual Image Patch Similarity) was introduced by Zhang et al. in 2018.
It measures how different two images look to a *VGG or AlexNet network* — a network trained
on image classification that has learned, along the way, which visual features matter. Two images
that look similar to humans tend to have similar intermediate neural activations. LPIPS is the
average distance between those activations over image patches. Lower LPIPS = more perceptually
similar.

*FID* (Fréchet Inception Distance) is a distribution-level metric, introduced by Heusel et al.
in 2017. Instead of comparing a specific reconstruction to a specific original, FID measures
how much the *distribution* of reconstructed images differs from the *distribution* of real
images. It computes statistics (mean and covariance) of the InceptionV3 feature vectors of
both sets and measures the Fréchet distance between them. Lower FID = more realistic
distribution. FID is used to evaluate generative codecs across a test set, not per image.

#gomaths("The Fréchet Distance between Gaussians")[
  If you have two distributions $p$ and $q$, and they are both *Gaussian* (bell-curve shaped),
  the *Fréchet distance* between them has a closed-form formula. Let $mu_p, Sigma_p$ be the
  mean vector and covariance matrix of $p$, and similarly for $q$. Then:

  $ d_F^2 = norm(mu_p - mu_q)^2 + "Tr"(Sigma_p + Sigma_q - 2 (Sigma_p Sigma_q)^(1/2)) $

  where $"Tr"$ is the *trace* (sum of diagonal elements of a matrix) and $(Sigma_p Sigma_q)^(1/2)$
  is the matrix square root. For FID, $mu$ and $Sigma$ are estimated from the feature vectors
  of the two image sets. The formula penalizes both a *shift in the mean* (the generated images
  have systematically different features) and a *mismatch in spread* (the generated distribution
  is too narrow or too wide).

  *Tiny example:* If $p$ is a 1D Gaussian with mean 0, variance 1, and $q$ has mean 2, variance 1,
  then $d_F^2 = (0-2)^2 + (1 + 1 - 2 sqrt(1 dot.c 1)) = 4 + 0 = 4$, so $d_F = 2$.

  FID values for image compression: values near 0 mean the reconstruction distribution is
  nearly indistinguishable from real. Classical codecs at 0.1 bpp might have FID > 100.
  HiFiC achieves FID < 20. Best diffusion codecs approach FID < 5.
]

The key difference between LPIPS and FID:
- LPIPS is *reference-based*: it compares each reconstruction to its specific original.
- FID is *distribution-based*: it cares whether the set of all reconstructions looks like
  the set of all natural images.

A codec could theoretically have bad LPIPS (each reconstruction differs from its original)
but good FID (the reconstructions collectively look natural). Generative codecs often have
this property: your specific face is changed, but the set of all compressed faces looks
photo-realistic.

```python
# Conceptual illustration of LPIPS-style perceptual similarity.
# Real LPIPS uses deep VGG features; this uses a toy 1D signal for illustration.

def toy_perceptual_similarity(original: list[float], reconstructed: list[float]) -> float:
    """
    Compute a toy perceptual similarity score.
    Real LPIPS extracts features from multiple VGG/AlexNet layers
    and computes normalized distances in that feature space.
    Lower value = more similar (better reconstruction).
    """
    # Step 1: Simulate extracting "features" (here: running averages over windows).
    def extract_features(signal: list[float], window: int = 4) -> list[float]:
        feats = []
        for i in range(0, len(signal) - window + 1, window):
            feats.append(sum(signal[i:i+window]) / window)
        return feats

    # Step 2: Compare features of original and reconstruction.
    f_orig = extract_features(original)
    f_recon = extract_features(reconstructed)

    # Step 3: Average L2 distance in feature space.
    diffs = [(a - b) ** 2 for a, b in zip(f_orig, f_recon)]
    return (sum(diffs) / len(diffs)) ** 0.5

# Example: compare a clean signal to a blurry and a noisy version.
signal    = [1.0, 3.0, 2.0, 4.0, 1.0, 2.0, 3.0, 2.0]
blurry    = [2.0, 2.5, 2.5, 3.0, 2.0, 2.5, 2.5, 2.5]  # MSE-codec output
perceptual= [1.1, 2.9, 2.1, 3.9, 1.1, 2.1, 2.9, 2.1]  # GAN codec output

print(f"Blurry LPIPS:     {toy_perceptual_similarity(signal, blurry):.3f}")
print(f"Perceptual LPIPS: {toy_perceptual_similarity(signal, perceptual):.3f}")
# Perceptual version should score better (lower) despite adding texture.
```

== The Gap Between Research and Deployment

By mid-2026, the gap between what perceptual codecs demonstrate in papers and what appears in
deployed products remains wide. Understanding why is important for anyone who wants to work in
this field.

=== Speed

Even with one-step distillation, diffusion-based decoders are order-of-magnitude slower than
classical codecs. Decoding a 4K frame with H.265 on a modern CPU takes a few milliseconds.
Decoding with a neural diffusion codec takes seconds to minutes without specialized hardware.
GAN-based decoders (like HiFiC) are faster — roughly 100ms per megapixel on a GPU — but still
far from the microsecond-level decode that hardware video decoders achieve.

=== Hardware

Classical codecs have dedicated silicon on every smartphone, laptop, and streaming device.
Neural codec inference requires a GPU or a purpose-built NPU. The NPU in a 2025-era smartphone
can accelerate some neural workloads, but the specific operations in diffusion decoders (attention
layers, normalization, iterative sampling) are not yet as efficiently accelerated as convolutions.

=== Standardization and Interoperability

JPEG AI becoming an ISO standard (2025) is a critical first step, but standard ≠ deployment.
It took HEVC (H.265) about five years from standardization (2013) to widespread use in mobile
cameras. JPEG AI faces the same ramp. Moreover, JPEG AI defines only still-image compression;
neural video codec standardization is further behind.

=== Floating-Point Reproducibility

Neural codecs face a subtle engineering problem that classical codecs do not: *floating-point
arithmetic is not identical across hardware*. The same neural network, run on an NVIDIA GPU
versus an AMD GPU versus Apple Silicon, may produce slightly different intermediate values —
which can mean different quantization decisions, which can corrupt the decoded bitstream. Classical
codecs use integer arithmetic that is perfectly reproducible everywhere.

This is not an unsolvable problem — it requires careful engineering of the network to avoid
operations sensitive to floating-point order, and some systems use fixed-point inference. But
it adds significant engineering cost and is a real barrier to bit-exact interoperability.

#checkpoint[
  A streaming platform says it wants to switch to a perceptual codec to save bandwidth. What
  are the three most important questions you should ask before recommending it?
][
  (1) What are the use cases — does any content require pixel fidelity (documentaries, news,
  archival footage)? (2) What hardware decodes the stream — can all target devices run neural
  inference at the required speed? (3) What is the deployment timeline — is this for a
  proprietary pipeline (where format compatibility is controlled) or a public bitstream (where
  standardization matters)?
]

== Looking Forward: Compression as Conditional Generation

The deep principle underlying all of Chapter 58 is this: at low enough bitrates, *decompression
is an act of generation*. The decoder is not "recovering" what was there; it is using the code
as a partial specification and generating a plausible completion.

This reframing has philosophical consequences. The "decoder" of a diffusion codec is in many
ways more like a text-to-image model that has been given a very specific prompt than like a
traditional "inverse transform." The code is a latent description, not a reversible transform.

It also has practical consequences. The same pre-trained diffusion backbone that powers
Stable Diffusion or DALL-E can be reused as a compression decoder — you get the world's most
powerful image prior "for free" by piggybacking on models that were trained on billions of
images. The compression encoder only needs to produce a code that steers this prior correctly.

This is genuinely new in the history of compression. For seventy years, compression research
built custom representations: Huffman trees, DCT bases, wavelet filters, LZ dictionaries, Ballé
autoencoders. All of these were designed and optimized specifically for compression. Diffusion
codecs instead *borrow* from the general-purpose AI world — the decoder is a general image
generator that was trained for entirely different purposes, repurposed as a codec component.

Whether this convergence of generative AI and codec engineering continues to produce gains, or
whether there are fundamental limits on how much realism can be squeezed from a tiny code,
is one of the open questions that will define the field through the late 2020s.

#takeaways((
  "The rate–distortion–perception tradeoff (Blau & Michaeli, 2019) proves that at low bitrates, pixel accuracy and perceptual realism are in fundamental tension — you cannot maximize both.",
  "MSE-trained codecs produce blur at low bitrates because averaging over uncertain pixels is the mathematically correct way to minimize squared error — but humans hate blur.",
  "HiFiC (NeurIPS 2020) solved this by adding a GAN discriminator loss that penalizes the decoder for producing any image a critic can distinguish from a real photograph.",
  "PerCo (ICLR 2024) pushed further: at ultra-low bitrates below 0.01 bpp, a diffusion model guided by the compressed code regenerates a plausible image, inventing all fine detail.",
  "StableCodec and OneDC (2025) distilled multi-step diffusion into a single forward pass, cutting decoding time by roughly 20x while preserving perceptual quality.",
  "Hallucinated detail is not a bug — it is a design choice. Perceptual codecs are excellent for consumer media and dangerous for forensic, medical, or archival applications.",
  "JPEG AI became an ISO/IEC/ITU International Standard in February 2025, the first standard for end-to-end learned image coding, with ~30% gains over VVC.",
  "Deployment barriers — speed, hardware, floating-point reproducibility, standardization — mean perceptual codecs remain research systems for most applications as of 2026.",
))

== Exercises

#exercise("58.1", 1)[
  Explain in your own words why a codec trained to minimize mean squared error produces blurry
  images at low bitrates, even though it is "trying its best." Use the concept of averaging over
  uncertain completions in your answer.
]
#solution("58.1")[
  At low bitrates, many pixels cannot be stored precisely — the decoder has uncertainty about
  each pixel's true value. MSE is minimized by outputting the *expected value* (average) of all
  plausible pixel values, because averaging reduces the average squared error. When the true
  pixel could be anywhere from light to dark grey, outputting middle grey is mathematically
  optimal for MSE. Applied across millions of pixels, this produces smooth, blurry averages
  instead of sharp textures — not a bug, but the correct solution to the wrong problem.
]

#exercise("58.2", 1)[
  The Blau–Michaeli theorem says you cannot simultaneously minimize distortion and maximize
  perceptual quality at a fixed bitrate. Give a concrete scenario (two specific images) where
  a high-distortion codec output has better perceptual quality than a low-distortion one.
]
#solution("58.2")[
  Consider a portrait compressed at 0.05 bpp. *Scenario A:* The MSE-optimal decoder outputs
  the pixel-average face — correct mean color, low MSE, but indistinct blur for every feature.
  *Scenario B:* A GAN decoder invents sharp-looking eyes, crisp hair, realistic pores —
  high MSE because each invented pixel differs from the original, but humans rate it as
  "photographic." The GAN output has higher distortion (more MSE) but better perceptual
  quality (looks more like a real face). Blau–Michaeli predicts exactly this: at this bitrate,
  you cannot have both.
]

#exercise("58.3", 2)[
  In the HiFiC loss function $cal(L) = R + lambda_"dist" D + lambda_"GAN" cal(L)_"GAN"$,
  the paper uses $lambda_"dist" = 0.075$ and $lambda_"GAN" = 1.0$. What would happen to the
  reconstruction quality — in terms of both PSNR and perceptual quality — if you swapped these
  values, using $lambda_"dist" = 1.0$ and $lambda_"GAN" = 0.075$? Justify your answer using
  the rate–distortion–perception tradeoff.
]
#solution("58.3")[
  With $lambda_"dist" = 1.0$ (large), the distortion term dominates. The decoder would be
  trained primarily to minimize pixel MSE, producing blurry but pixel-accurate reconstructions
  — high PSNR, poor perceptual quality (similar to a standard MSE codec). The GAN term with
  $lambda_"GAN" = 0.075$ would be too weak to force realistic texture generation. The
  perception–distortion tradeoff implies that pushing toward low distortion pulls you away from
  high perceptual quality: by weighting distortion heavily, we slide along the tradeoff curve
  toward the "low D, low perception" end, not the "high perception" end.
]

#exercise("58.4", 2)[
  PerCo encodes a 512×512 image at 0.003 bpp. (a) How many bits are in the compressed file?
  (b) How many bytes is that? (c) The encoder uses a codebook of size $K = 1024$ and encodes
  a $16 times 16$ grid of latent vectors. How many bits does each latent vector's index take?
  Does the total match (a)?
]
#solution("58.4")[
  (a) $0.003 times 512 times 512 = 786.432$ bits, round to 786 bits.
  (b) $786 / 8 approx 98$ bytes.
  (c) With $K = 1024$ codebook entries, each index takes $log_2 1024 = 10$ bits.
  A $16 times 16$ grid has $256$ latent positions, so total bits $= 256 times 10 = 2560$ bits.
  That is larger than 786 bits — indicating that either the grid is much smaller, the codebook
  is much smaller, or (more likely) entropy coding of the indices reduces the cost well below
  10 bits each if the index distribution is skewed. Realistic PerCo systems use additional
  entropy coding that achieves average code lengths far below $log_2 K$ for likely indices.
]

#exercise("58.5", 2)[
  Explain the difference between *LPIPS* and *FID* as metrics for perceptual codec quality.
  For which goal is each more appropriate: (a) comparing a specific reconstruction to its
  original, or (b) evaluating whether a codec produces natural-looking images across a test set?
]
#solution("58.5")[
  LPIPS (Learned Perceptual Image Patch Similarity) compares a specific reconstruction to its
  specific original by measuring distance in VGG/AlexNet feature space — it is a
  *reference-based*, per-image metric. It answers: "Does this reconstruction look like this
  original?" FID (Fréchet Inception Distance) compares the *distribution* of reconstructed
  images to the *distribution* of real images across an entire test set — it is a
  *distribution-level* metric. It answers: "Do all the reconstructions, taken together, look
  like real photographs?" For (a), LPIPS is appropriate. For (b), FID is appropriate. A
  generative codec can have poor LPIPS (each reconstruction differs from its original) but
  good FID (the set of reconstructions looks natural) — this is normal and expected.
]

#exercise("58.6", 3)[
  A hospital considers using a perceptual codec to compress and archive its radiology images.
  Write a structured argument (pros and cons) explaining whether this is appropriate, and
  state your conclusion. Consider the following factors: storage cost, diagnostic accuracy,
  legal and regulatory requirements, and the specific behavior of diffusion-based decoders.
]
#solution("58.6")[
  *Pros of perceptual compression in radiology:* Storage cost reduction could be enormous
  (hospitals store millions of images); bandwidth savings for telemedicine; faster transfers.
  *Cons and dangers:* (1) Hallucinated detail is the core risk — a diffusion decoder could
  remove a real nodule or invent one, directly affecting diagnosis. (2) Medical imaging is
  regulated: DICOM standards and FDA guidelines require that archived images faithfully represent
  the original acquisition. (3) Legal liability — if a missed diagnosis is later linked to a
  perceptual codec altering an image, the liability would be severe. (4) Diffusion decoders
  are non-deterministic in stochastic sampling modes; bit-exact reproducibility (required for
  medicolegal purposes) requires additional engineering. *Conclusion:* Perceptual codecs are
  contraindicated for archival radiology images. Lossless or tightly controlled lossy codecs
  (e.g., JPEG 2000 at 10:1 with bounded error, as permitted in some DICOM profiles) are
  appropriate. Perceptual codecs might be acceptable for *preview thumbnails* in a radiology
  workflow system, never for the primary archived image.
]

#exercise("58.7", 3)[
  Implement a function in Python 3.14 that simulates the rate–distortion–perception tradeoff
  curve by computing, for each of a list of lambda values (perception weights), the "equilibrium
  quality" of a toy codec. Use the function signature:
  `def rdp_curve(lambdas: list[float], source_variance: float) -> list[tuple[float, float, float]]`
  where the return is a list of `(distortion, perception_loss, bits)` triples. You may use any
  simplified model (e.g., a Gaussian source). Write a brief docstring explaining what each
  lambda value represents on the tradeoff curve.
]
#solution("58.7")[
  ```python
  import math

  def rdp_curve(
      lambdas: list[float],
      source_variance: float = 1.0,
  ) -> list[tuple[float, float, float]]:
      """
      Compute toy rate-distortion-perception tradeoff curve for a Gaussian source.

      Each lambda controls the perception weight in the joint loss:
          L = rate + lam_dist * distortion + lambda * perception_loss

      Large lambda → minimize perception loss → generative, high distortion.
      Small lambda → minimize distortion → MSE codec, low perceptual quality.

      For a Gaussian source with variance σ², the rate-distortion function gives:
          D = σ² * 2^(-2R)  so  R = -0.5 * log2(D / σ²)

      We model perception loss as how far the distortion is from "zero distortion"
      (perfect perception requires the reconstruction distribution to match source).
      For a Gaussian, perception_loss ≈ D (simplified model).
      """
      results = []
      for lam in lambdas:
          # Trade off: higher lambda → accept more distortion for lower perception loss.
          # Simplified model: equilibrium distortion = source_variance / (1 + 1/lam)
          # (As lam → ∞, distortion → source_variance; as lam → 0, distortion → 0)
          distortion = source_variance / (1.0 + 1.0 / (lam + 1e-9))

          # Rate from rate-distortion function: R = 0.5 * log2(σ² / D)
          ratio = source_variance / max(distortion, 1e-9)
          bits = max(0.0, 0.5 * math.log2(ratio))

          # Perception loss: how non-Gaussian is the reconstruction?
          # Simplified: proportional to distortion (lower D = more perceptual)
          perception_loss = 1.0 / (1.0 + distortion)  # 0 (worst) to 1 (perfect)

          results.append((distortion, 1.0 - perception_loss, bits))

      return results

  # Example:
  curve = rdp_curve(lambdas=[0.01, 0.1, 1.0, 10.0, 100.0], source_variance=1.0)
  print("  lambda  |  distortion | perception_loss |  bits")
  for lam, (d, p, r) in zip([0.01, 0.1, 1.0, 10.0, 100.0], curve):
      print(f"  {lam:6.2f}  |   {d:.4f}    |     {p:.4f}      | {r:.4f}")
  ```
]

== Further Reading

- #link("https://arxiv.org/abs/2006.09965")[Mentzer et al. (2020). *High-Fidelity Generative Image Compression.* NeurIPS 2020. arXiv:2006.09965] — The HiFiC paper; required reading.
- #link("https://hific.github.io/")[HiFiC Project Page] — Interactive comparison tool; try it before reading the math.
- #link("https://arxiv.org/abs/2310.19817")[Careil et al. (2024). *Towards Image Compression with Perfect Realism at Ultra-Low Bitrates.* ICLR 2024.] — The PerCo paper introducing diffusion decoders for compression.
- #link("https://arxiv.org/abs/2506.21977")[Zhang et al. (2025). *StableCodec: Taming One-Step Diffusion for Extreme Image Compression.* ICCV 2025.] — One-step distillation for fast decoding.
- #link("https://arxiv.org/abs/2505.16687")[OneDC (2025). *One-Step Diffusion-Based Image Compression with Semantic Distillation.* arXiv:2505.16687.] — OneDC system; 40% bitrate reduction over prior diffusion codecs.
- #link("https://jpeg.org/items/20250219_press.html")[JPEG Committee (2025). *JPEG AI becomes an International Standard.* Press Release.] — Standardization milestone.
- #link("https://arxiv.org/abs/2202.06533")[Yang, Mandt, Theis (2023). *An Introduction to Neural Data Compression.* Foundations and Trends.] — Comprehensive survey of the whole neural compression field.
- #link("https://arxiv.org/abs/2401.12207")[Blau & Michaeli (2019/2024). *Rate-Distortion-Perception Tradeoff.* Extended treatment.] — Deeper mathematical treatment of the fundamental tradeoff.
- #link("https://arxiv.org/abs/1801.03924")[Zhang et al. (2018). *The Unreasonable Effectiveness of Deep Features as a Perceptual Metric.* CVPR.] — The LPIPS metric paper; explains why VGG features predict human perception.

#bridge[
  We have now seen how generative models — first GANs, then diffusion — transform the decoder
  from a deterministic inverse transform into a *conditioned image generator*. This is the most
  dramatic conceptual shift in compression since Shannon's theory.

  But still-image perceptual codecs are only the beginning. In Chapter 59 we turn to video:
  how do you handle the temporal dimension with neural codecs? The DVC family and the DCVC line
  replace classical motion estimation with learned optical flow and conditional entropy models.
  And a radically different approach — implicit neural representations — stores a video not as
  a sequence of frames but as the weights of a small network overfit to that particular clip.
  Both approaches struggle with the same deployment barriers we saw here, but both offer
  new ways to think about what it means to "store" moving images.
]
