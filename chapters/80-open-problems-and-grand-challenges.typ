#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Open Problems and Grand Challenges

#epigraph[
  We can only see a short distance ahead, but we can see plenty there that needs to be done.
][Alan Turing, 1950]

Here is a number to start with. In a 2023 paper from Google DeepMind, a large language model (one never trained to compress anything) was handed a chunk of English text and, paired with a humble arithmetic coder (the very coder you built in Chapter 26), squeezed that text smaller than `gzip`, smaller than `bzip2`, smaller than the best classical compressor humans had ever hand-engineered. The same model, with no retraining, also beat the specialist image format PNG on images and beat the specialist audio format FLAC on sound.

That should stop you in your tracks. A program built to predict the next word in a sentence turned out to be a better compressor of *pictures* than a program built by experts to compress pictures. We have been promising you all book that *compression is prediction* (Chapter 23). This is the bill coming due. The best compressor is the best model of the data. As our models of the world grow vast and general, the act of compression has quietly merged with the act of building intelligence.

And yet. That record-setting compressor is far too slow and too power-hungry to ship in your phone's camera app. The "specialist" JPEG it humiliates on ratio will still encode a billion photos today, while the neural champion encodes a handful. This is the strange, electric state of the field in mid-2026: we know, in the lab, how to compress almost everything better than we currently do in production, and we mostly *can't afford to*. The frontier is not a wall of ignorance. It is a wall of cost, of standards, of energy, of trust.

This chapter is a map of that wall: the genuinely open problems, the ones nobody has solved, the ones where a clever reader might one day plant a flag.

#recap[
  We have come a very long way. In Chapter 23 we argued that *compression = prediction = learning*. Volume II built the classical lossless coders (Huffman in Chapter 24, arithmetic coding in Chapter 26, ANS in Chapter 27, the LZ family in Chapters 28–32). Volume III built the lossy media codecs (JPEG in Chapter 42, the video codecs in Chapters 51–55, audio in Chapters 46–50) on transforms (Chapter 38), quantization (Chapter 39), and rate–distortion theory (Chapter 21). Volume IV turned to the neural era: learned image compression (Chapter 57), generative codecs (Chapter 58), LLMs as compressors (Chapter 62), and model compression (Chapters 63–65). Chapter 79 gave the honest *snapshot* of what actually ships in June 2026. This chapter looks past the snapshot to the unanswered questions.
]

#objectives((
  "Explain the real limits of learned compression: why a lab record is not a shipping codec",
  "Describe the decode-complexity and energy problem and why it now dominates codec design",
  "Lay out the obstacles to standardizing neural codecs (reproducibility, drift, patents)",
  "Define semantic and goal-oriented compression and say how it breaks the classical framework",
  "Explain joint source–channel coding and why separating the two is no longer always optimal",
  "Describe coding for machines: compressing so a model, not a human, is the receiver",
  "State, in plain terms, several genuinely unsolved problems a researcher could attack",
))

== The Limit Question: How Much Is Left?

The first grand challenge is also the oldest, and it sounds almost childish: *how much compression is actually possible?* For any specific file, Chapter 22 gave the brutal answer. Its Kolmogorov complexity, the length of the shortest program that prints it, is the true floor, and it is *uncomputable*. We can never be sure we have reached it. We can only keep building better models and watching the bytes shrink, never knowing how close the bottom is.

For *general English text*, the most famous estimate is Shannon's own. In 1951 he ran an experiment: he showed people partial sentences and asked them to guess the next letter, and from how often they guessed right he estimated the entropy of English at roughly *0.6 to 1.3 bits per character*. Ordinary text stored in ASCII uses 8 bits per character; even a good classical compressor lands around 2 bits. Shannon's number says there is still a factor of two or more left on the table for a compressor that truly *understood* English the way a person does.

The Hutter Prize (Chapter 36) made this concrete and competitive: compress the first 1 GB of English Wikipedia (`enwik9`) as small as possible. For years the record crept down by single-digit percentages, dominated by hand-built context-mixing compressors like `cmix` and `nncp` (Chapter 34). The 2024–2026 entrants increasingly *are* neural language models in disguise, and they keep nudging the record lower, confirming Shannon's hunch that the ceiling for text sits well below what classical methods reach.

#keyidea[
  There are two different "limits" and beginners constantly confuse them. The *entropy* of a source (Chapter 18) is the floor for a compressor that knows the source's true statistics, a floor we can sometimes estimate. The *Kolmogorov complexity* of one specific string (Chapter 22) is the absolute floor for *any* description of it. It is uncomputable, so we can never prove we've hit it. Open problem: for real-world data (genomes, video, the web), nobody knows how far today's best compressors sit above the true floor. We are flying without an altimeter.
]

#gomaths("Bits per Character, and Why a Factor of Two Is Huge")[
  Suppose a text has $N$ characters. If a compressor achieves $b$ *bits per character*, the file takes $N times b$ bits, which is $(N times b) / 8$ bytes. So bits-per-character is just the average code length per symbol, exactly the quantity Chapter 18 called the per-symbol entropy when the model is perfect.

  - ASCII: $b = 8$. A 1-million-character book → 1,000,000 bytes.
  - Good classical compressor: $b approx 2$. → 250,000 bytes.
  - Shannon's estimate of English: $b approx 1$. → 125,000 bytes.

  Each halving of $b$ halves the file. Going from 2 to 1 bit per character is *another 2× on top of everything classical methods already do*, which is why "compression as understanding" is such a tantalizing prize. The catch: the only models good enough to approach $b approx 1$ are enormous neural networks that cost millions of times more energy to run than `gzip`.
]

#history[
  Shannon ran his "prediction of English" experiment by hand in 1950, using his wife Mary Elizabeth (Betty) Shannon and friends as test subjects, covering up parts of pages from a detective novel and a history book, asking the reader to guess the next letter. His estimate of roughly 1 bit per character has held up remarkably well for three-quarters of a century. Modern large language models, evaluated on clean English, land right around that figure. The man who founded the field also, characteristically, measured its hardest target before anyone else thought to ask.
]

== The Cost Wall: Decode Complexity and Energy

The problem that has come to dominate the entire field is this: a codec is not its compression ratio alone. It is a *budget*. Every byte you save costs computation to save and computation to undo, and that computation costs *time*, *silicon*, *battery*, and ultimately *carbon*.

Recall the deep asymmetry of media codecs from Chapter 51: a video is *encoded once* (you can afford a server farm and an hour of crunching) but *decoded billions of times* on phones, TVs, and laptops that must keep up with 30 frames a second on a battery. This asymmetry is the hidden ruler that has decided every codec war in this book. JPEG won because it decodes almost for free. `zstd` (Chapter 32) conquered the data center not because it compresses best but because it sits on the best *speed-versus-ratio* curve. AV1 (Chapter 54) was held back for years not by its ratio (which is excellent) but by how expensive it was to encode and, until hardware decoders arrived, to decode.

Neural codecs hit this wall hard. The learned image and video coders of Chapters 57–59 win on ratio in the papers, but a single forward pass through their networks can be *thousands of times* more arithmetic than a classical decode. As of mid-2026 the headline open problem in learned video is blunt: nobody has shipped a fully neural codec that decodes 1080p video in real time, at high ratio, on the kind of chip that sits in an ordinary laptop or phone, and does it without draining the battery. Research systems like DCVC-RT ("Towards Practical Real-Time Neural Video Compression," 2025) are the first to even decode in real time on a consumer GPU, and that is celebrated as a breakthrough precisely because it had not been done before.

#definition("Computational asymmetry")[
  A codec is *asymmetric* when encoding and decoding cost wildly different amounts of computation. Most media codecs are deliberately built so that *decoding is cheap* (it happens billions of times on weak devices) even if *encoding is expensive* (it happens once on a powerful machine). Many neural codecs are *symmetric and expensive on both ends*: a heavy network runs in both directions, which is exactly why they struggle to deploy.
]

#keyidea[
  In 2026 the binding constraint on compression research has shifted from *ratio* to *ratio-per-joule* and *ratio-per-millisecond*. A method that saves 20% of the bits but burns 100× the decode energy is, for almost every real product, a *worse* compressor. The frontier is no longer a two-dimensional rate–distortion curve (Chapter 21). It is a *rate–distortion–complexity* surface, and the unexplored region is "great ratio, tiny decode."
]

Why does this matter beyond engineering convenience? Because of *scale*. Video is already the majority of all internet traffic. If you shave 30% off the bits of every video stream but triple the energy each of a billion phones spends decoding them, you have not saved the planet anything. You have moved the cost from the network to a billion batteries and the power stations behind them. Compression has always been an *energy* technology in disguise: a bit not sent is energy not spent moving it. Neural compression threatens to invert that bargain, and finding ratios that are *also* cheap to decode is one of the genuinely important open problems of the decade.

#aside[
  There is a neat way to feel the asymmetry. Your phone can *play* a 4K movie for two hours on a fraction of its battery, because hardware decoders for H.264, HEVC, and AV1 are etched directly into the silicon: fixed circuits, breathtakingly efficient. But ask that same phone to *encode* 4K video and the battery wilts in minutes. A neural codec with no dedicated silicon is, in effect, asking the phone to *encode* even when it is only trying to *watch*.
]

== The Standardization Problem: A Codec Everyone Can Agree On

Suppose you solve the cost wall and build a fast, brilliant neural codec. You now face a problem classical codecs barely had: *how do two different computers agree, bit-for-bit, on what the file means?*

A compression format is a contract. When `gzip` writes a file, the DEFLATE specification (Chapter 30) defines *exactly* what every bit means, so a decoder written in 1996 still perfectly decodes a file made today, on any machine, forever. That iron-clad reproducibility is why standards matter (Chapter 77): a format you cannot reliably decode is worthless.

Neural codecs make this contract terrifyingly hard to honor, for three reasons.

*Floating-point drift.* A neural network is millions of floating-point multiplications and additions. As Chapter 13 warned, floating-point arithmetic is *not associative*: $(a + b) + c$ can differ from $a + (b + c)$ in the last bit. Run the "same" network on an NVIDIA GPU, an Apple chip, and an Intel CPU and you can get *slightly different* numbers. For most AI tasks a one-in-a-million rounding difference is harmless. For a compressor it is *catastrophic*: the entropy decoder (Chapter 26) feeds each decoded probability into the next step, so a single divergent bit can derail the entire rest of the file. The standard must therefore pin down the arithmetic to the last bit across every device on Earth, which often means forcing the network into slower integer-only math.

#pitfall[
  This is the single nastiest trap in neural-codec standardization, and it surprises newcomers every time. "The model is the standard" is *not enough*. Two decoders running the identical trained weights can still disagree in the last bit because their hardware adds floating-point numbers in a different order. A lossless or even a *consistently* lossy codec must specify the exact integer arithmetic, rounding, and order of operations. Without that, it is not a standard at all, just a suggestion.
]

*Model size and versioning.* DEFLATE's specification is a few dozen pages. A neural codec's "specification" includes *the trained weights*: potentially hundreds of megabytes that every decoder must possess, byte-identical, and that can never be patched without breaking every old file. You cannot ship a bug fix.

*The patent and openness question.* Chapters 53 and 77 told the grim story of HEVC's patent pools strangling its own adoption. Neural codecs layer on a new minefield: patents on architectures, on training methods, and the murky legal status of the *training data* itself.

Against all this, real progress has happened. *JPEG AI* (the first international image-coding standard built end-to-end on neural networks) was finalized and published as ISO/IEC 6048-1 in 2025, reporting roughly 30% better compression than the best previous methods. Its very existence proves the standardization problem is solvable. But it was solved the hard way: by carefully specifying integer arithmetic for bit-exact reproducibility and accepting a heavier decoder. The general problem - a neural codec that is fast, royalty-free, bit-exact on every device, and agreed upon by all - remains open.

#checkpoint[
  Why can't a neural codec standard simply say "use these exact trained weights" and call it done?
][Because the *weights* don't fully determine the *output*. Floating-point arithmetic isn't associative, so different hardware can add the same numbers in a different order and get a last-bit-different result. In a chained entropy decoder, one divergent bit ruins the rest of the file. The standard must pin down the exact integer arithmetic and operation order, not just the weights.]

== Semantic and Goal-Oriented Compression

Now a genuinely radical idea, one that breaks the framework this whole book has used.

Every codec so far, lossless or lossy, has tried to reconstruct the *signal*: the exact bytes, or a perceptually faithful copy of the pixels and samples. Even our lossy codecs measured success by *distortion* - how close the reconstruction is to the original (Chapter 21). But step back and ask: *why are you sending this data at all?* If a security camera streams video to a server whose only job is to answer "is there a person in frame?", then transmitting a pretty picture is *wasteful*. The receiver does not want the image. It wants the *answer*.

This is *semantic* or *goal-oriented* compression, and it quietly tears up Shannon's classical contract. Shannon, in his founding 1948 paper, deliberately set meaning aside: "the semantic aspects of communication are irrelevant to the engineering problem." That assumption (that the engineer's job is to reproduce symbols, never to understand them) built the entire field. Semantic compression dares to drop it.

#definition("Semantic / goal-oriented compression")[
  Compression that preserves only the information *relevant to the receiver's task*, discarding everything else (even perceptually obvious detail) because the receiver will never use it. Success is measured not by signal fidelity (distortion) but by *task performance*: did the downstream goal still succeed? A face-recognition stream may keep the geometry that identifies a face while throwing away the lighting, background, and texture a human would consider the "real" picture.
]

The classical picture had two knobs: *rate* (bits) and *distortion* (signal error). Recent theory adds a third, the *rate–distortion–perception* tradeoff we met in Chapter 58, and semantic coding pushes further still to *rate–task* tradeoffs, where the only thing that matters is whether the receiver's job got done. Each new axis opens new theoretical ground: we do not yet have a clean, general "semantic rate–distortion theorem" the way Shannon gave us one for signals.

#misconception[
  Semantic compression means the codec "understands" the content the way a human does.
][Not in any deep sense. It means the encoder is *trained jointly with the downstream task* so that the bits it keeps happen to be the ones the task needs. There is no comprehension, just a learned, task-shaped bottleneck. The effect is striking: for a fixed task, you can often cut the bitrate by an order of magnitude versus sending a faithful image, because most of the image was never relevant to the task in the first place.]

The danger is that *goal-oriented* means *lossy in a way that bites the moment the goal changes*. Compress a medical scan to preserve only "is there a tumor?", and you have thrown away everything the next, unforeseen question would have needed. Classical compression is *general*: the reconstruction serves any future purpose. Semantic compression is *specialized*: it serves one purpose superbly and betrays all the others. Knowing when that trade is wise is an unsolved engineering and ethical question.

== Joint Source–Channel Coding: Tearing Down a Wall Shannon Built

To explain the next frontier, we have to revisit one of Shannon's most beautiful and, it turns out, most *limiting* results.

In Chapter 20 we met the *separation theorem*. Shannon proved that you can split communication into two independent stages without losing optimality (in the ideal, infinite-length limit): first *source coding* squeezes the data to its entropy, removing redundancy; then *channel coding* adds carefully structured redundancy back so the message survives a noisy channel. Compress, then protect. This separation is the reason your phone has one chip that runs a video codec and a *separate* chip that runs the 5G error-correction: two clean, independent jobs. The whole architecture of modern communication rests on it.

#theorem("Source–channel separation, informally")[
  For a fixed source and a fixed memoryless channel, in the limit of infinitely long messages, compressing the source down to its entropy and *then* applying channel coding is optimal: there is no joint scheme that beats this two-stage design.
]

#proof[
  The full proof is Chapter 20's; here is the shape of *why* it holds and *where* it breaks. The forward direction is engineering: a source coder reaching entropy $H$ followed by a channel coder for any rate above $H$ and below capacity $C$ delivers the message reliably whenever $H < C$, so separation *achieves* what is possible. The converse uses the data-processing inequality (Chapter 20): no scheme can push more than $C$ bits of information per channel use through the channel, and no scheme can describe the source in fewer than $H$ bits on average. So if $H > C$ no scheme of any kind works, and if $H < C$ the simple two-stage design already works, hence joint design cannot beat separation. The proof leans on *infinite* block lengths and a *known, stationary* channel, and it is precisely those assumptions that fail in the real world, which is the opening the next frontier walks through. #h(1fr) $square$
]

So if separation is optimal, why is "joint source–channel coding" one of the hottest topics of 2024–2026? Because the theorem's fine print is fatal in practice. It assumes *infinitely long* messages and *unlimited* delay. Real systems (a live video call, a self-driving car's sensor link, a satellite) have *tiny packets* and *hard latency limits*. In that short-block, low-latency, fast-changing-channel regime, the separation theorem *no longer holds*, and a system that designs source and channel coding *together* can beat the two-stage classic.

The modern incarnation is *deep joint source–channel coding* (DeepJSCC). A neural network maps the source (say, an image) *directly* to the analog signals sent over the radio, with no clean separation into "compressed bits" and "error-correction bits" at all. The payoff is striking: classical separated systems suffer the *cliff effect* - they work perfectly until the channel gets slightly too noisy, then collapse to garbage all at once, the moment the channel code's error-correction is overwhelmed. DeepJSCC systems instead degrade *gracefully*: as the channel worsens, the image just gets gradually fuzzier, never abruptly destroyed. For a video call dropping in and out of a tunnel, graceful is worth far more than a higher peak. This couples directly to the *semantic* frontier: when the receiver is a machine doing a task, you want to send signals tuned to that task, robust to noise, with no wasteful separation at all.

#aside[
  The "cliff effect" has a name you have felt. Old analog TV, as the signal weakened, slowly dissolved into snow: graceful. Digital TV, by contrast, is crisp until the instant it is not, then freezes and blocks into a frozen mosaic - a cliff. That cliff is the separation theorem's price for digital perfection, and undoing it for short, urgent messages is exactly what joint source–channel coding is for.
]

== Coding for Machines: When the Receiver Is a Robot

This frontier ties the others together, and it starts from a simple observation about *who is watching*.

For the entire history of compression, the receiver was a *human*. JPEG's quantization tables (Chapter 42) and MP3's psychoacoustic model (Chapter 47) are exquisitely tuned to the human eye and ear: they throw away exactly what *people* cannot perceive. But more and more, the thing on the receiving end of a compressed stream is *not a person*. It is a neural network: a surveillance system counting cars, a factory camera spotting defects, a self-driving car's perception stack, a content-moderation classifier. By some estimates, machine-consumed visual data already rivals or exceeds human-consumed data, and the gap is widening fast.

This breaks every assumption baked into our codecs. A machine does not care about the "ringing" artifacts (Chapter 42) that bother human eyes; it may, however, be wrecked by quantization that a human would never notice. Optimizing a codec for human perception is, for a machine receiver, optimizing for the *wrong objective entirely*.

#definition("Coding for machines")[
  Compression designed so the decoded result is consumed by an *algorithm* (typically a neural network performing detection, recognition, or analysis) rather than viewed by a human. The codec is optimized to preserve *task accuracy* (does the downstream model still detect the car?) rather than perceptual quality. Often the bitstream is *scalable*: a small *base layer* carries compact features for the machine, and an optional *enhancement layer* reconstructs a viewable image for a human only when one is actually looking.
]

This is no longer a research curiosity. The MPEG standards committee (the same body behind JPEG, MP3, and the video codecs of this book) has active standardization efforts under the *MPEG-AI* umbrella for *Video Coding for Machines* (VCM) and *Feature Coding for Machines* (FCM). The use cases are the unglamorous backbone of the modern world: smart-city surveillance, autonomous vehicles, intelligent transportation, distributed sensor networks - domains where machines generate and consume far more video than humans ever will. The open problem is to define a *standard* way to compress for a machine receiver when you do not always know, at encode time, *which* machine or *which* task will consume the stream tomorrow. That is the same generality-versus-specialization tension that haunts semantic coding.

#fig([The classical pipeline versus coding for machines. Classically, every bit serves a human eye. In coding for machines, a compact base layer feeds the model directly, and a viewable image is reconstructed (enhancement layer) only on demand.],
  cetz.canvas({
    import cetz.draw: *
    // classical
    rect((0,2.6),(2.2,3.4), fill: rgb("#eef4fb"))
    content((1.1,3.0), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[source])))
    rect((3.0,2.6),(5.2,3.4), fill: rgb("#eef4fb"))
    content((4.1,3.0), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[encode])))
    rect((6.0,2.6),(8.2,3.4), fill: rgb("#eef4fb"))
    content((7.1,3.0), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[decode])))
    rect((9.0,2.6),(11.0,3.4), fill: rgb("#fff3e0"))
    content((10.0,3.0), box(width: 1.6cm, inset: 2pt, align(center, text(size: 8pt)[human eye])))
    line((2.2,3.0),(3.0,3.0), mark: (end: ">"))
    line((5.2,3.0),(6.0,3.0), mark: (end: ">"))
    line((8.2,3.0),(9.0,3.0), mark: (end: ">"))
    content((5.5,3.95), text(size: 9pt)[Classical: optimize for human perception])
    // machines
    rect((0,0.3),(2.2,1.1), fill: rgb("#eef4fb"))
    content((1.1,0.7), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[source])))
    rect((3.0,0.3),(5.2,1.1), fill: rgb("#eef4fb"))
    content((4.1,0.7), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[encode])))
    rect((6.0,0.6),(8.2,1.4), fill: rgb("#e8f5e9"))
    content((7.1,1.0), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[base → model])))
    rect((6.0,-0.5),(8.2,0.3), fill: rgb("#f4f6f8"))
    content((7.1,-0.1), box(width: 1.8cm, inset: 2pt, align(center, text(size: 8pt)[enh. → image])))
    rect((9.0,0.6),(11.0,1.4), fill: rgb("#fff3e0"))
    content((10.0,1.0), box(width: 1.6cm, inset: 2pt, align(center, text(size: 8pt)[task answer])))
    line((2.2,0.7),(3.0,0.7), mark: (end: ">"))
    line((5.2,0.7),(6.0,1.0), mark: (end: ">"))
    line((5.2,0.7),(6.0,-0.1), mark: (end: ">"))
    line((8.2,1.0),(9.0,1.0), mark: (end: ">"))
    content((5.5,1.95), text(size: 9pt)[Machines: optimize for task accuracy (image optional)])
  })
)

== Compressing the Models Themselves

There is one last twist, and it is the most self-referential idea in the book. We have spent Volume IV using big neural networks as *compressors*. But those networks are themselves enormous piles of data, and so they, too, must be *compressed*. The compressor has become the thing that needs compressing.

Chapters 63–65 covered this in depth, so here we only frame it as a *grand challenge*, because the frontier is moving weekly. A frontier language model has hundreds of billions of weights; storing each at 16 bits is hundreds of gigabytes. *Quantization* (Chapter 63) crushes weights to 4 bits or fewer; the information-theoretic curiosity *BitNet b1.58* stores each weight as one of three values ${-1, 0, +1}$, which is $log_2 3 approx 1.58$ bits, astonishingly close to the bound for a ternary alphabet (Chapter 18). At inference, the *KV-cache* (the model's working memory of the conversation so far) balloons with context length and now dominates memory; compressing it through eviction, low-bit quantization, and architectural tricks like DeepSeek's Multi-head Latent Attention (which caches a small shared latent instead of full keys and values) is one of the hottest axes of all.

#keyidea[
  The open problem here is a hard floor, not an engineering convenience. Below roughly 2 bits per weight, model accuracy starts to fall off a cliff that no current method fully tames. *How much can a trained network be compressed before it stops being the same network?* is, at bottom, a question about the Kolmogorov complexity (Chapter 22) of *intelligence itself*, and nobody knows the answer. The compressor that compresses compressors has met the same uncomputable floor as everything else.
]

== A Minimal Taste: Compressing for a Task, Not an Eye

To make "coding for machines" concrete, here is the smallest possible illustration of the core idea: the *right* thing to keep depends entirely on the receiver's goal. We will not build a neural codec (that needs the machinery of Chapter 57); we will simulate the *principle* in a dozen lines. Our "image" is a list of pixel brightnesses. A *human* receiver wants the picture to look right (low average error). A *machine* receiver has one job: answer "is the brightest spot above a threshold?" A compression that is terrible for the human can be perfect for the machine, at a fraction of the bits.

#gopython("The max() Function and a Boolean Task")[
  Python's built-in `max(xs)` returns the largest item in a list `xs`. A *Boolean* is a value that is either `True` or `False`; a comparison like `m > 200` evaluates to one. We will use `max` to extract the single number the machine's task depends on, and a comparison to produce the task's `True`/`False` answer.

  ```python
  xs = [10, 250, 30]
  print(max(xs))        # 250  - the brightest pixel
  print(max(xs) > 200)  # True - the machine's answer
  ```
]

#gopython("List Comprehensions for Quantization")[
  A *list comprehension* builds a new list by transforming each item of an old one: `[f(x) for x in xs]`. We met it in Chapter 16. Here we use it to *quantize* (round each pixel to the nearest multiple of a step size), which is exactly the lossy step from Chapter 39, just written compactly.

  ```python
  xs = [10, 250, 30]
  step = 64
  q = [round(x / step) * step for x in xs]
  print(q)   # [0, 256, 64]  - coarse, few distinct levels = few bits
  ```
  Coarser quantization (larger `step`) means fewer distinct levels, hence fewer bits to store, but more error.
]

#gopython("zip() and abs() - Comparing Two Lists Element by Element")[
  To measure how badly a decoded image differs from the original we must line the two lists up and compare them position by position. Python's built-in `zip(a, b)` does the lining-up: it walks two (or more) lists *in parallel*, handing you one pair `(a[i], b[i])` at a time. This is exactly the "two lists marching in lock-step" job we did the hard way in Chapter 16 before we had it.

  ```python
  for o, d in zip([10, 250, 30], [16, 240, 32]):
      print(o, d)        # 10 16  /  250 240  /  30 32
  ```

  `abs(x)` returns the *magnitude* of a number, dropping any minus sign: `abs(-7)` is `7`, `abs(7)` is `7`. We use it so that an error of $-5$ and an error of $+5$ both count as 5 units of wrongness. Combined with `sum(...)` (#pyrecall[`sum` adds up every value in a list or iterator (Chapter 16)]), the average absolute error of a whole image is one readable line:

  ```python
  orig, dec = [10, 250, 30], [16, 240, 32]
  # per-pixel errors |10-16|, |250-240|, |30-32| = 6, 10, 2
  print(sum(abs(o - d) for o, d in zip(orig, dec)) / len(orig))  # 6.0
  ```
]

```python
# coding_for_machines_demo.py -- the same data, two receivers, two notions of "good".

def quantize(pixels: list[int], step: int) -> list[int]:
    """Lossy compression: round each pixel to the nearest multiple of `step`.
    Larger step  ->  fewer distinct levels  ->  fewer bits  ->  more error."""
    return [round(p / step) * step for p in pixels]

def human_error(original: list[int], decoded: list[int]) -> float:
    """What a HUMAN cares about: average absolute pixel error (distortion)."""
    total = sum(abs(a - b) for a, b in zip(original, decoded))
    return total / len(original)

def machine_answer(pixels: list[int], threshold: int = 200) -> bool:
    """The MACHINE's one and only job: is the brightest pixel above threshold?"""
    return max(pixels) > threshold

# A tiny 1-D "image": mostly dark, one bright spot.
image = [12, 9, 14, 230, 11, 8, 15, 10]

for step in (1, 32, 128):
    decoded = quantize(image, step)
    print(f"step={step:>3}  "
          f"human_error={human_error(image, decoded):5.1f}  "
          f"machine_correct={machine_answer(decoded) == machine_answer(image)}")
```

Running it prints something like:

```text
step=  1  human_error=  0.0  machine_correct=True
step= 32  human_error= 10.6  machine_correct=True
step=128  human_error= 13.1  machine_correct=True
```

Look at the last row. At `step=128` we have quantized the image so brutally that a *human* sees large errors: every pixel is mangled to the nearest multiple of 128. But the *machine's* answer is still perfectly correct. The bright spot at 230 rounds to 256, which is still safely above the threshold of 200, while every dark pixel rounds to 0. We threw away most of the bits and kept *exactly the information the task needed*, nothing else. That is the entire philosophy of coding for machines, in eight pixels. A real system replaces our hand-picked "keep the maximum" rule with a neural encoder *trained* to discover, on its own, which bits the downstream task depends on.

#checkpoint[
  In the demo, why is heavy quantization (`step=128`) acceptable for the machine but not the human?
][The machine's task only depends on whether the *maximum* exceeds 200. Coarse quantization preserves that relationship (230 → 256 stays above 200; dark pixels → 0 stay below), so the task answer is unchanged. The human perceives *every* pixel's error, which heavy quantization makes large. Different receivers, different definitions of "lossless enough."]

== The Honest Ledger of What's Unsolved

Let us gather the open problems in one place, plainly stated, so you could hand this list to a curious student and say "pick one."

- *The altimeter problem.* For real data, how far above the true (Kolmogorov) floor do our best compressors sit? Uncomputable in general; even good *estimates* are missing for most domains.
- *The cost wall.* Find neural compression that decodes in real time, at high ratio, on weak hardware, without burning the energy savings it claims. The whole field is stuck on the *complexity* axis of rate–distortion–complexity.
- *Bit-exact neural standards.* A fast, royalty-free neural codec that decodes *identically* on every chip on Earth. JPEG AI proved it is possible; doing it cheaply and generally is open.
- *A semantic rate–distortion theory.* Shannon gave us $R(D)$ for signals (Chapter 21). There is no comparably clean, general theory for *task* fidelity in goal-oriented compression.
- *Joint source–channel coding for the real world.* A principled design for short-packet, low-latency, time-varying channels, where Shannon's separation theorem no longer rules.
- *Generality vs. specialization.* Semantic and machine codecs win by discarding everything off-task, but tomorrow's task is unknown. How to compress for *unknown future receivers* is wide open.
- *The sub-2-bit weight floor.* How far can a trained network be compressed before it stops being itself? A question about the complexity of intelligence, and unanswered.

#aside[
  Notice a pattern across this whole list. Almost every open problem is some version of the *same* sentence we have repeated since Chapter 23: *the best compressor is the best model of the data*. The altimeter problem is "we do not know how good the best model could be." The cost wall is "the best models are too expensive to run." Semantic coding is "the best model of the *task* beats the best model of the *signal*." Compression did not run out of problems. It ran into the problem of intelligence, and that problem is still very much open.
]

#takeaways((
  "A lab record is not a shipping codec: today's best compressors (often neural) win on ratio but lose on speed, energy, and standardization. The frontier is now a rate-distortion-complexity surface, not just a rate-distortion curve.",
  "For real data we have no reliable altimeter: we cannot compute how far our best compressors sit above the true Kolmogorov floor, though Shannon's ~1-bit-per-character estimate for English hints at large remaining gains in text.",
  "Standardizing neural codecs is genuinely hard because floating-point arithmetic isn't associative. Bit-exact decoding across all hardware requires pinning down exact integer math, not just sharing trained weights. JPEG AI (ISO/IEC 6048-1, 2025) proved it can be done.",
  "Semantic / goal-oriented compression abandons Shannon's signal-fidelity contract: it keeps only what the receiver's task needs, measured by task success rather than distortion. Superb for one purpose, brittle for all others.",
  "Shannon's source-channel separation theorem is optimal only for infinite block lengths; for short, low-latency, noisy links, joint (deep) source-channel coding wins by degrading gracefully instead of falling off the digital cliff.",
  "More and more, the receiver is a machine, not a human: coding for machines (MPEG VCM/FCM) optimizes for downstream task accuracy, often with a compact base layer for the model and an optional enhancement layer for human eyes.",
  "Every open problem is a face of one sentence: the best compressor is the best model of the data. That is why the frontier of compression has merged with the frontier of machine learning itself.",
))

== Exercises

#exercise("80.1", 1)[
  Shannon estimated the entropy of English at roughly 1 bit per character. A plain-text English novel of 500,000 characters is stored in ASCII (8 bits per character). (a) How many bytes is the ASCII file? (b) If a perfect compressor reached Shannon's 1 bit per character, how many bytes would it produce? (c) A good classical compressor reaches about 2 bits per character; how many bytes is that, and what is the ratio between the classical result and Shannon's ideal?
]
#solution("80.1")[
  (a) $500{,}000 times 8 = 4{,}000{,}000$ bits $= 500{,}000$ bytes. (b) At 1 bit/char: $500{,}000$ bits $= 62{,}500$ bytes. (c) At 2 bits/char: $1{,}000{,}000$ bits $= 125{,}000$ bytes. The classical result (125,000 bytes) is exactly *twice* Shannon's ideal (62,500 bytes). In principle, another 2× is still on the table, which is why "compression as understanding" is such a prize. The catch is that reaching ~1 bit/char requires a model so large it costs astronomically more energy than the classical compressor.
]

#exercise("80.2", 2)[
  Explain, in your own words and to a friend who has never programmed, why two computers running the *identical* trained neural network can disagree about the decompressed file, and why that disagreement is fatal for a compressor but harmless for, say, a photo-tagging app. Then propose how a standard fixes it.
]
#solution("80.2")[
  A neural network is millions of multiplications and additions of decimal (floating-point) numbers. Computers store only a fixed number of digits, so they must round, and crucially the *order* in which a chip adds numbers can change the last rounded digit: adding $a$ then $b$ then $c$ can differ in the last bit from adding them in another order. Different chips (a phone, a laptop, a server GPU) genuinely add in different orders. For a photo-tagging app, a one-in-a-million last-bit difference never changes the answer "this is a cat." But a compressor *chains* its decisions: the entropy decoder (Chapter 26) feeds each decoded probability into the next step, so a single wrong bit early on derails everything after it, producing garbage. A standard fixes this by specifying the *exact* integer arithmetic, rounding rule, and order of operations every conforming decoder must use, forcing every chip to compute the bit-identical result, even if that means slower, integer-only math. (This is exactly what JPEG AI did.)
]

#exercise("80.3", 2)[
  A roadside camera streams to a server whose only job is to count vehicles. (a) Describe how a *coding-for-machines* design would compress this stream differently from a normal video codec optimized for human viewing. (b) Give one concrete advantage and one concrete danger of this approach. (c) Why might the design include a separate "enhancement layer"?
]
#solution("80.3")[
  (a) A human-optimized codec spends bits making the footage *look* good: smooth gradients, accurate color, no blocking. A coding-for-machines design instead spends bits on whatever the *vehicle-counting model* actually uses (shapes, edges, motion that separate cars from background) and discards detail the counter ignores (exact paint color, sky texture, fine background). It may even transmit compact learned *features* for the model directly rather than a viewable image at all. (b) Advantage: far fewer bits for the same counting accuracy, since most of a normal image is irrelevant to counting. Danger: it is specialized. If you later want to read license plates or identify a specific car, the discarded detail is gone forever; and it is brittle if the downstream model is swapped. (c) An *enhancement layer* lets the system reconstruct a viewable image *on demand* - for a human investigator reviewing an incident - without paying for human-quality bits on every routine frame; the compact base layer serves the machine continuously, and the enhancement layer serves the rare human.
]

#exercise("80.4", 3)[
  Shannon's separation theorem says: for an infinitely long message over a fixed channel, compressing to entropy and *then* channel-coding is optimal, so there's no point designing them jointly. Yet "joint source–channel coding" is a hot research area. (a) Identify the two assumptions in the theorem that fail in a real-time video call over a flaky wireless link. (b) Explain the "cliff effect" of a classical separated system and how a joint (e.g. DeepJSCC) system avoids it. (c) Argue why graceful degradation can be worth *more* than a higher peak quality for this use case.
]
#solution("80.4")[
  (a) The theorem assumes (i) *infinite block length / unlimited delay*: a live call must send tiny packets with hard latency limits, far from the infinite-length limit where separation is proved optimal; and (ii) a *fixed, known channel*: a wireless link fades and varies moment to moment as you move, so the channel the code was designed for is not the channel you actually get. (b) A separated system protects the compressed bits with an error-correcting code rated for some noise level. While the channel stays within that level, decoding is perfect; the instant noise exceeds it, the error correction is overwhelmed and the decoded bits become garbage all at once - perfect, then suddenly destroyed: the cliff. A joint system maps the source directly to transmitted signals with no sharp bit boundary, so as noise rises the reconstruction just gets gradually fuzzier instead of collapsing. (c) On a call, a momentarily fuzzy face you can still recognize and a voice you can still understand is vastly more useful than a stream that is crisp until it abruptly freezes and blocks out entirely. Humans tolerate gradual degradation; the cliff is jarring and breaks the interaction. For short, urgent, noisy links, *graceful* beats *peak*.
]

== Further reading

- Delétang, Ruoss, et al., #link("https://arxiv.org/abs/2309.10668")[#emph[Language Modeling Is Compression]] (Google DeepMind, 2023). The paper showing a general LLM plus an arithmetic coder beats `gzip`, PNG, and FLAC; the empirical heart of this chapter.
- Shannon, #link("https://archive.org/details/bstj30-1-50")[#emph[Prediction and Entropy of Printed English]] (Bell System Technical Journal, 1951). The original ~1-bit-per-character experiment.
- #link("https://jpeg.org/jpegai/")[#emph[The JPEG AI standard (ISO/IEC 6048)]]. The first end-to-end learned image-coding international standard, finalized 2025.
- Gündüz, Qin, et al., #link("https://arxiv.org/abs/2207.09353")[#emph[Beyond Transmitting Bits: Context, Semantics, and Task-Oriented Communications]]. A survey framing semantic and goal-oriented compression.
- Bourtsoulatze, Burth Kurka, Gündüz, #link("https://arxiv.org/abs/1809.01733")[#emph[Deep Joint Source-Channel Coding for Wireless Image Transmission]] (2019). The founding DeepJSCC paper and the cliff-effect demonstration.
- #link("https://www.emergentmind.com/topics/video-coding-for-machines-vcm")[#emph[Video Coding for Machines (MPEG VCM)]]. Overview of the standardization effort for machine-receiver compression.

#bridge[
  We have stared straight at the unsolved. Every open problem turned out to be a face of one idea: the best compressor is the best model, and our models have grown into the engines of modern AI. The final chapter, *The Future of Compression* (Chapter 81), steps back to ask where the whole arc is heading: why, in a world where data grows faster than the chips that store it, compression stays *invaluable*, the quiet substrate beneath intelligence, communication, and the sustainability of computing itself.
]
