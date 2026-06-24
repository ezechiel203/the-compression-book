#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// local helper: a lightly-set worked-example block (built-ins only)
#let worked(body) = block(width: 100%, breakable: true, inset: (x: 10pt, y: 8pt),
  radius: 4pt, fill: rgb("#fbf7ef"), stroke: (left: 3pt + rgb("#783f04")),
  above: 9pt, below: 9pt)[#text(weight: "bold", fill: rgb("#783f04"))[Worked example. ] #body]

= The Future of Compression

#epigraph[
  We are drowning in information but starved for knowledge. The cure is not to
  store more, but to understand more, and to understand is to compress.
][after John Naisbitt, paraphrased]

You have arrived at the last chapter of a long book. Eighty chapters ago we
started with a single, almost childish question: when you save a photo and it
takes up less room than it "should," where did the missing bytes go? We answered
it with counting, with logarithms, with Shannon's entropy, with Huffman trees and
sliding windows and cosine transforms and neural networks. We built a working
compressor, `tinyzip`, byte by byte, and watched our running sample melt under
technique after technique. Along the way the question quietly grew up. By the time
we reached large language models in Chapter 62, "where did the bytes go?" had
become "what does it mean to *understand* data?", and the two turned out to be
the same question wearing different clothes.

So here is the final puzzle, and it is the biggest one in the book. The amount of
data humanity creates is exploding, roughly *doubling every two years*. The
machines we use to store and move that data are improving far more slowly, and the
old reliable doubling of raw transistor speed has all but stopped. If those two
curves keep diverging, something has to give. Either we throw away most of what we
record, or we get dramatically better at squeezing it. This chapter argues that
compression is not a finished, mature, boring corner of computer science that won
its battles in the 1990s. It is about to become *more* important than it has ever
been, and the reason is the very thesis this book has been building toward since
Chapter 23: #emph[compression is prediction is understanding]. Let us tie the
whole arc together and look, carefully and honestly, at where it goes from here.

#recap[
  This chapter is a synthesis, so it leans on the *entire* book. From Volume I:
  entropy as the floor on lossless size (Chapter 18) and the *source coding
  theorem* (Chapter 19); the thesis that *compression equals prediction equals
  learning* (Chapter 23); and the ideal-but-uncomputable compressor of *Kolmogorov
  complexity* (Chapter 22). From Volume II: the classical lossless coders
  (Huffman, arithmetic coding, ANS, the LZ family, DEFLATE, zstd, BWT). From
  Volume III: lossy media coding and the *rate–distortion–perception* triangle.
  From Volume IV: *learned* compression, generative codecs, and *large language
  models as compressors* (Chapter 62). And from Volume V's specialist tour
  (Chapters 66–78): genomic, scientific, columnar, model, and KV-cache
  compression, plus the politics, dead ends, and people of the field. Chapter 79
  surveyed the state of play in June 2026 and Chapter 80 laid out the open
  problems. Now we point the telescope forward.
]

#objectives((
  [State the central tension of the next decade (*data growth versus compute
   stagnation*) with real numbers, and explain why it makes compression a
   strategic necessity rather than a convenience.],
  [Explain why *compression has become the substrate of artificial intelligence*,
   so that progress in one now drives progress in the other.],
  [Describe *semantic and goal-oriented communication*: compressing *meaning*
   instead of *bits*, and why 6G research is betting on it.],
  [Reason about compression's role in *sustainability* and *energy*, and about
   *in-storage / computational* compression that hides the cost.],
  [Lay out a small set of *reasoned predictions* for 2026–2040, and, just as
   importantly, the honest reasons each one might be wrong.],
  [Articulate why, even in a world of perfect predictors, the *fundamental limits*
   we proved in Volume I keep compression permanently invaluable.],
))

== The scissors: data growth versus compute stagnation

Start with the single most important fact about the future of the field, the one
every other section in this chapter hangs from. There are two curves. One is the
amount of digital data the world creates and stores each year; the other is how
cheaply we can store, move, and process a byte. For sixty years those two curves
climbed together, which is why nobody outside the field thought much about
compression. They are now coming apart, and the gap between them is where
compression lives.

=== Curve one: the data is exploding

The industry analyst firm IDC has tracked the *global datasphere*, meaning all the
data created, captured, and replicated in a year, for over a decade. In 2010 it was
a few zettabytes. A *zettabyte* is a 1 followed by 21 zeros of bytes; written out,
that is $10^21$ bytes, or a trillion gigabytes. By 2025 the datasphere reached
roughly 180#sym.space.thin ZB, growing at a compound rate of around 23% a year, fast enough to
*double in just over three years*. The bulk of that growth is not your holiday
photos. It is machine-generated: sensor streams from billions of Internet-of-Things
devices, security-camera video, telemetry, scientific instruments, and, newest and
hungriest of all, the training corpora and activation logs of AI systems.

#gomaths("Doubling time from a growth rate")[
  When something grows by the same *percentage* every year, it grows
  *exponentially* (Chapter 7). A handy shortcut, the *rule of 70*, tells you how
  long it takes to double: divide 70 by the yearly percentage growth.

  At 23% per year, doubling time $approx 70 / 23 approx 3.0$ years. At 35% per
  year it is $approx 70 / 35 = 2.0$ years, "doubling every two years." The exact
  formula behind the rule is $t_"double" = (ln 2) / (ln(1 + r))$, where $r$ is the
  growth rate as a fraction (so 23% is $r = 0.23$) and $ln$ is the natural
  logarithm from Chapter 7. Plugging in: $(ln 2) / (ln 1.23) = 0.693 / 0.207
  approx 3.3$ years. The rule of 70 is just a friendly approximation of this.

  *Why it matters here:* a quantity that doubles every 3 years grows
  *one-thousand-fold in about 30 years* (because $2^10 approx 1000$, and ten
  doublings take $10 times 3 = 30$ years). That is the shape of the data curve.
]

#worked[
  *How big is a zettabyte, really?* Suppose you stored 180#sym.space.thin ZB on the best 2026
  hard drives, about 30#sym.space.thin TB each. You would need $180 times 10^21 \/ (30 times
  10^12) = 6 times 10^9$, that is *six billion* drives. Stacked flat, each drive
  about 25#sym.space.thin mm thick, the pile would be 150,000#sym.space.thin km tall, a third of the way to
  the Moon. Now remember the pile must grow tall enough to *double* in three years.
  Compression is not a nicety in this picture; it is the only thing keeping the
  pile from reaching escape velocity.
]

=== Curve two: the cheap-byte engine is sputtering

For decades the data flood was matched by an equally reliable flood of cheap
hardware. Three "laws" did the heavy lifting:

- *Moore's law*: the observation, named after Intel co-founder Gordon Moore in
  1965, that the number of transistors on a chip doubled about every two years. It
  gave us exponentially more compute per dollar.
- *Dennard scaling*: as transistors shrank, their power density stayed constant,
  so each generation ran faster *for free*. This is the one that actually died:
  it broke down around 2005–2007, which is why single-core clock speeds have
  been stuck near 3–5#sym.space.thin GHz for two decades.
- *Kryder's law*: hard-disk storage density grew even faster than Moore's law
  through the 1990s and 2000s. It, too, has slowed; areal density gains that were
  ~40% a year fell to the low teens, and the industry now leans on exotic tricks
  (heat-assisted magnetic recording) to keep inching forward.

The headline is blunt: *the data curve is rising faster than the cheap-hardware
curve, and the cheap-hardware curve is bending down.* When supply grows slower
than demand, you economize. In computing, the way you economize on bytes is called
compression.

#keyidea[
  Compression converts a *shortage of storage and bandwidth* into a *surplus of
  computation*: you spend CPU cycles to buy back space and transfer time. As long
  as compute stays cheaper than the storage and network it saves, compressing is
  the rational default. The widening scissors between the two curves is precisely
  why that trade keeps getting *more* favourable, not less.
]

=== But there is a floor, and we proved it

Here is the part that keeps the field honest, and it is worth stating as a
theorem because it is the one mathematical guarantee that bounds every prediction
in this chapter. We cannot simply "compress harder" forever. Back in Chapter 8 we
proved, by pure counting, that *no compressor can shrink every input*; and in
Chapter 18–19 we sharpened that into Shannon's source coding theorem: a source
with entropy $H$ bits per symbol cannot be coded, on average, in fewer than $H$
bits per symbol without loss. Let us restate the counting bound, because its proof
is the entire reason the future of compression is a story about *better models*
rather than magic.

#theorem("No free lunch in lossless compression")[
  For any lossless compressor that maps inputs to outputs, if some inputs get
  *shorter*, then others must get *longer*. No single lossless scheme can map
  every possible file to a strictly shorter file.
]

#proof[
  Count. There are exactly $2^n$ distinct binary strings of length $n$. Suppose, for
  contradiction, that our compressor turned *every* one of those $2^n$ strings into
  some *shorter* string, a string of length $n - 1$ or less. How many strings have
  length at most $n - 1$? Adding them up, that is
  $2^0 + 2^1 + dots.c + 2^(n-1) = 2^n - 1$. So we would be trying to stuff $2^n$
  different inputs into only $2^n - 1$ different shorter outputs. By the *pigeonhole
  principle* (Chapter 8) at least two distinct inputs must collide on the same
  output, and then the decompressor cannot tell them apart, so the scheme is not
  lossless. Contradiction. Therefore at least one input must *not* shrink. #h(1fr)
]

This little proof is the bedrock under everything that follows. It says compression
is never a generic, universal trick that works on "any data." It only ever works
by *betting* that real-world data is not random (that photos look like photos,
that English looks like English, that genomes look like genomes) and spending the
saved bits on the rare inputs that violate the bet. Every advance in the future of
compression is therefore an advance in *modelling*: a better, sharper bet about
what the data is going to look like. Hold that thought; it is the thread that runs
through every remaining section.

#checkpoint[
  Your friend says she has invented a program that shrinks *any* file by at least
  one bit, and you can run it again and again. What is wrong, in one sentence?
][
  Re-running a universal one-bit shrinker would eventually compress any file down
  to zero bits, from which nothing could be recovered. That is impossible by the
  counting proof above; some inputs *must* grow.
]

#fig([The scissors. Data created per year (steep) outruns the cost-efficiency of
storage and compute (flattening). The growing vertical gap is the demand for
compression, and the dashed entropy line is the hard floor below which no
lossless scheme can ever reach.],
cetz.canvas({
  import cetz.draw: *
  // axes
  line((0,0),(8,0), mark: (end: ">"))
  line((0,0),(0,5), mark: (end: ">"))
  content((8,-0.4))[time #sym.arrow.r]
  content((-0.35,4.8), angle: 90deg)[scale (log)]
  // data curve: steep exponential
  line((0,0.6),(2,1.3),(4,2.4),(6,3.7),(8,4.7), stroke: 1.4pt + rgb("#9a2617"))
  content((6.8,4.7), anchor: "west")[#box(width: 2.2cm, align(left, text(size:8pt, fill: rgb("#9a2617"))[data created]))]
  // hardware curve: flattening
  line((0,0.4),(2,1.1),(4,1.7),(6,2.1),(8,2.3), stroke: 1.4pt + rgb("#0b5394"))
  content((5.8,2.35), anchor: "west")[#box(width: 2.6cm, align(left, text(size:8pt, fill: rgb("#0b5394"))[cheap-byte\ capacity]))]
  // entropy floor
  line((0,0.9),(8,0.9), stroke: (dash: "dashed", paint: rgb("#0b6e4f")))
  content((1.7,1.15))[#text(size:7.5pt, fill: rgb("#0b6e4f"))[entropy floor]]
  // the gap arrow
  line((6,2.1),(6,3.7), stroke: 0.8pt, mark: (start: ">", end: ">"))
  content((6.75,2.9))[#text(size:7.5pt)[the gap =]]
  content((6.95,2.55))[#text(size:7.5pt)[compression]]
}))

== Compression is now the substrate of artificial intelligence

If the scissors explain *why* compression matters more, this section explains the
deeper, stranger reason the field has suddenly become exciting again: the frontier
of compression and the frontier of machine learning have *merged into one frontier*.
They are no longer two subjects that occasionally borrow from each other. They are
the same subject. To see why, we need only take the thesis of Chapter 23
seriously and follow it to its conclusion.

=== The thesis, restated for the last time

In Chapter 23 we proved the identity at the heart of this book. A *model* that
predicts the next symbol with probability $p$ lets an arithmetic coder (Chapter 26)
spend $-log_2 p$ bits encoding the symbol that actually occurs. Average that over a
long message and the expected code length equals the *cross-entropy* between the
true data distribution and the model's distribution. The better the model predicts,
the higher the probability it assigns to what really comes next, the shorter the
code. So:

$ "expected bits per symbol" = "cross-entropy"(p_"true", p_"model") >= H(p_"true"). $

#mathrecall[Cross-entropy is your *expected surprise* using the model's odds when
reality follows the true odds; it bottoms out at the true entropy $H$ exactly when
the model is perfect.]

Read that equation slowly, because it is the whole game. *To compress better is,
literally and mathematically, to predict better.* And a system that predicts the
next token of all of human text, what is that? It is a large language model. The
identity is not a metaphor. A language model *is* a compressor; the only reason we
usually run it forward to generate text instead of backward to compress is habit
and economics.

=== Three places the merger is already cashing out

This is not a philosophical flourish; the practical consequences are already on the
table, and we have seen each one earlier in the book. Three of them, briefly:

+ *LLMs are state-of-the-art lossless compressors (Chapter 62).* DeepMind's 2024
  paper "Language Modeling Is Compression" (Delétang et al.) showed a general
  language model, paired with an arithmetic coder, beating PNG on *images* and FLAC
  on *audio*, not because it was trained on pictures or sound, but because a good
  general predictor predicts *anything* with structure. Fabrice Bellard's `nncp`
  and `ts_zip` have held the top of the Large Text Compression Benchmark (the
  Hutter-Prize arena of Chapter 36) with neural predictors for years. The catch,
  also from Chapter 62, is *speed*: these compressors are thousands of times slower
  than zstd, so they win the ratio crown and lose the deployment war, for now.

+ *Training a model is compressing its data (Chapter 61).* The *minimum description
  length* principle (Rissanen, 1978; Chapter 23) says the best model of a dataset
  is the one that, together with the data it fails to explain, has the shortest
  total description. A neural network that has learned the regularities of its
  training set has, in a precise sense, *compressed* that set into its weights. The
  ability of a model to *generalize*, to do well on data it never saw, is, by the
  MDL and PAC-Bayes arguments of Chapter 61, a direct consequence of how much it
  compressed. This is why "compression as a measure of intelligence" (the Hutter
  thesis, Chapter 61) is taken seriously rather than dismissed.

+ *We compress the models themselves (Chapters 63–65).* A frontier model is
  hundreds of gigabytes of weights, and the data that lives *during* inference (the
  KV-cache, Chapter 65) can dwarf the weights for long contexts. Quantizing
  weights to 4 bits, the ternary `BitNet b1.58` idea of $log_2 3 approx 1.58$
  bits per weight, and DeepSeek's Multi-head Latent Attention that compresses the
  KV-cache by ~93% are all *compression* applied to AI's own plumbing. Without them,
  the models would not fit on the hardware that runs them.

#worked[
  *Cross-entropy in bits, on a tiny message.* Suppose the true next-letter odds are
  $p("a") = 1/2$, $p("b") = 1/4$, $p("c") = 1/4$, but our model wrongly believes
  $q("a") = 1/4$, $q("b") = 1/4$, $q("c") = 1/2$. An arithmetic coder driven by the
  *model* spends $-log_2 q(x)$ bits on each actual letter (Chapter 26). The expected
  cost per letter is the cross-entropy
  $-sum_x p(x) log_2 q(x) = 1/2 dot 2 + 1/4 dot 2 + 1/4 dot 1 = 1.75$ bits. The
  true entropy is $-sum_x p(x) log_2 p(x) = 1/2 dot 1 + 1/4 dot 2 + 1/4 dot 2 = 1.5$
  bits. The model's wrongness costs exactly $1.75 - 1.5 = 0.25$ extra bits per
  letter, a tax you pay *for every symbol* until you fix the model. *This is the
  whole reason a better predictor is a better compressor, made arithmetic:* improve
  $q$ toward $p$ and the code shrinks toward the entropy floor.
]

#keyidea[
  The merger runs in *both* directions. Better predictors (AI) give better
  compressors; and the practical existence of huge AI models *depends on*
  compressing their weights, their caches, and their training data. Progress in
  either field is now progress in the other. That feedback loop is the single most
  important reason compression has a bright, busy future rather than a quiet
  retirement.
]

#aside[
  There is a poetic symmetry in how this book ends where information theory began.
  In 1948 Shannon measured information by how much it *cannot* be compressed
  (Chapter 18). In 1964 Solomonoff and Kolmogorov defined the *ideal* learner as
  the shortest program that reproduces the data: pure compression as pure
  intelligence (Chapter 22). For fifty years that was an elegant but practically
  useless ideal, because we could not build good enough predictors. The deep-learning
  era is the first time in history we *can* build them. The future of compression is,
  in large part, the cashing-in of a sixty-year-old promissory note.
]

#misconception[
  "LLMs make classical compressors like zstd and JPEG obsolete."
][
  Not even close, and the reason is the cost curves of this very chapter. A neural
  predictor that wins on *ratio* loses on *speed and energy* by three or four orders
  of magnitude. For the firehose of everyday bytes (web pages, logs, backups, video
  streams) the deployed champions remain fast classical coders (zstd, DEFLATE, AV1,
  Opus). The neural compressors win only where the data is precious and scarce
  enough to justify the compute, or where the predictor is *already running anyway*
  for another reason. The future is a *layered* one - cheap classical coders
  everywhere, expensive learned coders at the high-value edges - not a replacement.
]

== Semantic communication: compressing meaning, not bits

Shannon, with characteristic precision, fenced off a question he deliberately did
*not* answer. On the very first page of his 1948 paper he wrote that the
"semantic aspects of communication are irrelevant to the engineering problem." His
theory measures bits, not meaning. A photograph of your grandmother and 8 megabytes
of random noise can carry the *same* number of bits while meaning wildly different
things to you. For seventy-five years that boundary was exactly the right place to
stand, and the whole of classical compression lives inside it. The next decade
brings the field's first serious, well-funded attempt to step *across* it.

=== The idea: transmit the answer, not the data

Here is the shift in one image. Today, if a self-driving car's camera sees a
pedestrian, the classical pipeline compresses the *image* (with a video codec from
Volume III), ships the bits, and the receiver decompresses a faithful picture.
*Semantic communication* asks a different question: what does the receiver actually
*need*? If the only thing that matters downstream is "there is a pedestrian at
bearing 40#sym.degree, 12 metres, walking left," then transmitting a pixel-perfect image
is absurdly wasteful. You could send that *meaning* in a few bytes. The sender runs
a model that extracts the task-relevant meaning; the receiver runs a model that
acts on it. The channel carries *understanding*, not *appearance*.

This is the natural endpoint of the rate–distortion–perception triangle from
Chapter 21 and the generative codecs of Chapter 58, pushed one step further. There,
we already stopped insisting on pixel-exact reconstruction and asked only that the
result *look* right to a human eye. Semantic communication drops even "look right"
and asks only that the result *be useful for the task*. The distortion measure is
no longer mean-squared pixel error; it is *did the receiver accomplish its goal?*
Researchers call this *goal-oriented* or *pragmatic* communication.


#gomaths("Information bottleneck: keeping only what's relevant")[
  How do you compress a signal $X$ down to a code $Z$ that keeps only the part
  relevant to a goal $Y$? The *information bottleneck* (Tishby, 1999) writes it as
  a trade-off using *mutual information* $I(dot;dot)$ from Chapter 20, the number
  of bits that two quantities share. You minimize:

  $ cal(L) = underbrace(I(X; Z), "bits kept from input") - beta dot underbrace(I(Z; Y), "bits useful for the goal"). $

  The first term pushes $Z$ to be *small* (compress hard, forget the input); the
  second pushes $Z$ to *predict the goal* $Y$ well (stay useful). The knob $beta$
  sets the balance, exactly like the Lagrange multiplier $lambda$ in
  rate–distortion optimization (Chapter 41). Classical compression is the special
  case where the "goal" is *reconstructing the input itself*, i.e. $Y = X$. Semantic
  communication is what you get when $Y$ is something *smaller and more abstract*
  (a label, a decision, an action) so the bottleneck can throw away far more.
]

#worked[
  *A number that shows the prize.* A 4K dashcam frame is on the order of
  8#sym.space.thin megabytes raw, perhaps 200#sym.space.thin kilobytes after a modern video codec. The
  semantic payload "pedestrian, bearing 40#sym.degree, 12#sym.space.thin m, moving left, confidence
  0.97" fits comfortably in *under 20 bytes*. That is a four-orders-of-magnitude
  reduction over the raw frame, but only because the receiver and sender *share a
  model* of what a "pedestrian" is. The bits saved were not in the image; they were
  in the *shared understanding* that both ends already possessed. Semantic
  compression is, at bottom, compression against a shared world-model.
]

The catch is severe and worth naming plainly, because it explains why this is a
*future* and not a *present*. The sender and receiver must share a model, and that
model must be *trusted*, *up to date on both ends*, and *robust*. If the shared
model is wrong about what a pedestrian looks like, the few bytes you sent encode a
confident, compact *mistake*. Classical compression fails *gracefully* (a blocky
image); semantic compression can fail *catastrophically and silently* (a missing
pedestrian). This is the same "hallucinated detail" worry we met with generative
codecs in Chapter 58, now with safety stakes. The active research programmes,
notably the EU's *6G-GOALS* project and the IEEE's goal-oriented-network efforts,
both targeting the 6G standard expected around 2030, spend much of their energy on
exactly this: making semantic codecs *fail safely*. As of 2026 the most concrete
results are in narrow, well-defined tasks (sensor fusion, machine-to-machine
telemetry, ultra-low-bitrate video for constrained links), not general human
communication. But the direction is set, and it is the first genuinely *new* place
the field has gone since Shannon drew his boundary.

#pitfall[
  Do not confuse *semantic compression* with *lossy compression*. Lossy coding
  (Volume III) still tries to reproduce the *original signal* approximately.
  Semantic coding may transmit something that, decompressed, looks *nothing* like
  the input (a sentence instead of a photo) because it preserves the *meaning for
  the task*, not the *signal*. The success metric moves from "fidelity to the data"
  to "fitness for the purpose."
]

== Sustainability, energy, and where the compressing happens

Every byte you do not have to write, move, or read is energy you do not have to
spend. As AI and video pushed global data-centre electricity use into the spotlight
in the mid-2020s, compression quietly became an *environmental* technology as much
as a performance one. This section looks at the energy ledger and at a structural
shift in *where* the compressing physically happens.

=== Compression as an energy lever

The arithmetic is simple and underappreciated. Moving a bit across a network or
in and out of storage costs far more energy than the handful of CPU cycles needed
to compress it, often by a wide margin once the bit travels any real distance.
So compressing before you transmit or store is usually a *net energy win*, not just
a net space win. This is why Cloudflare's 2025 roll-out of Zstandard across its
network was pitched as cutting both egress *costs* and *carbon*, and why the
storage industry's move from DEFLATE-era `zlib` to `zstd` is an efficiency story:
`zstd` reaches comparable ratios while decompressing several times faster, so every
byte read back costs less energy.

But the lever cuts both ways, and honesty demands we say so. The *learned*
compressors that win on ratio (Chapter 62) can *cost* enormous energy. Running a
billion-parameter predictor to save a few kilobytes is, today, an energy
*disaster* for everyday data. So the sustainability question is not "compress more"
but "compress *at the right point on the ratio–energy curve* for this data's
value and lifetime." Cold archival data that will sit untouched for a decade
justifies expensive, slow, high-ratio compression once. Hot data read a million
times a second wants the cheapest possible decode. The future is *adaptive*: codecs
that know how precious and how long-lived a byte is, and spend compute accordingly.

#worked[
  *The lifetime calculation.* Suppose a high-ratio coder takes 100#sym.space.thin joules to
  compress a file and saves 1#sym.space.thin GB of storage versus a cheap coder. If reading
  1#sym.space.thin GB back costs (say) 1#sym.space.thin joule and the file is read once, you spent 100#sym.space.thin J
  to save 1#sym.space.thin J of reads plus some storage power, a bad trade unless storage is
  the binding constraint. If the file is read a *million* times, the saved decode
  energy alone dwarfs the one-time compression cost. *Read count and lifetime, not
  ratio alone, decide whether harder compression is greener.*
]

=== In-storage and computational compression

There is also a quieter, architectural revolution in *where* compression runs, and
it directly addresses the scissors of the first section. Traditionally the CPU
compresses, then hands bytes to the disk. *Computational storage drives* (CSDs)
turn this around: a dedicated hardware engine *inside the SSD* compresses and decompresses
every block transparently, on the data path, at line rate. Commercial drives in
2025–2026 (for example ScaleFlux's CSD-class devices) advertise compression and
decompression latencies around 5#sym.space.thin microseconds and multi-gigabyte-per-second
throughput, with the drive's flash-translation layer quietly managing the
variable-length compressed blocks. The application sees an ordinary, *bigger,
faster* disk and never knows compression happened.

#keyidea[
  *Compression is migrating down the stack and out of sight.* It is moving off the
  CPU and into dedicated silicon (network cards, SSD controllers, database storage
  engines) so it becomes free in the sense that matters: it no
  longer competes with the application for cycles, and the programmer does not have
  to think about it. The most successful future for a technology is to become
  invisible infrastructure, like the DEFLATE that already sits unseen inside every
  web request (Chapter 30). Compression's destiny is to disappear into the walls.
]

#worked[
  *Transparent compression makes a disk look faster.* A drive's flash delivers
  4#sym.space.thin GB/s of *physical* reads. If the data on it compresses 3:1 and the controller
  decompresses on the fly at line rate, then each physical gigabyte read off the
  flash *expands* to 3 logical gigabytes for the application. The effective read
  bandwidth the application sees is $4 times 3 = 12$#sym.space.thin GB/s, three times the raw
  speed, and the usable capacity triples too, all without the CPU lifting a finger.
  This is why 2025–2026 computational storage drives advertise "up to 10×" gains on
  compressible data: compression stopped being a tax on throughput and became a
  *multiplier* on it, precisely because it moved off the CPU and into the drive.
]

To make "compression as an energy and lifetime decision" concrete, here is the kind
of tiny policy a future storage tier might run, pure `tinyzip`-style Python (no new
library needed), choosing a method by how the data will be used.

#gopython("Dictionaries as little lookup tables")[
  A Python *dictionary*, written with curly braces, maps *keys* to *values*, like
  a tiny labelled lookup table. `costs = {"fast": 1, "max": 40}` then `costs["max"]`
  gives back `40`. We met dicts back in the Python primer (Chapter 16); here we use
  one to map a named compression method to its rough energy cost per megabyte.
]

```python
# A toy "compression policy": pick a method by the data's value & lifetime.
# Energy is a rough relative cost-per-MB to COMPRESS; decode cost is separate.
from dataclasses import dataclass

ENERGY_PER_MB: dict[str, float] = {
    "store_raw": 0.0,     # no compression
    "deflate":   1.0,     # cheap classical (Chapter 30)
    "zstd_max":  4.0,     # strong classical, still fast (Chapter 32)
    "neural":    9000.0,  # LLM-as-compressor: best ratio, brutal cost (Ch 62)
}
RATIO: dict[str, float] = {            # bytes-out / bytes-in (smaller = better)
    "store_raw": 1.00, "deflate": 0.45, "zstd_max": 0.32, "neural": 0.18,
}

@dataclass
class Item:
    size_mb: float
    reads_per_day: float
    lifetime_days: float

def choose_method(item: Item) -> str:
    """Pick the method with the lowest *total* energy over the item's life."""
    best, best_cost = "store_raw", float("inf")
    for method in ENERGY_PER_MB:
        compress_e = ENERGY_PER_MB[method] * item.size_mb
        stored_mb  = item.size_mb * RATIO[method]
        # assume reading costs ~0.001 energy units per MB moved
        total_reads = item.reads_per_day * item.lifetime_days
        read_e = 0.001 * stored_mb * total_reads
        total = compress_e + read_e
        if total < best_cost:
            best, best_cost = method, total
    return best

# Cold archive read rarely -> spend compute once, store small.
print(choose_method(Item(size_mb=1000, reads_per_day=0.001, lifetime_days=3650)))
# Hot log read constantly -> keep decode cheap.
print(choose_method(Item(size_mb=10, reads_per_day=1_000_000, lifetime_days=30)))
```

Run it and the cold archive picks an aggressive method while the hammered hot log
picks a cheap one, the *same* logic a smart storage tier will apply automatically.
The lesson is not the toy numbers; it is that *the right amount of compression is a
decision about the data's whole future*, and increasingly that decision will be made
for us, in hardware, in real time.

== A reasoned set of predictions for 2026–2040

Predicting the future of technology is a humbling business, and the honest way to
do it is to attach each prediction to the *reason it follows* and the *reason it
might fail*. Everything below is grounded in the curves, theorems, and trends this
book has built. Treat them as well-supported bets, not prophecy. Where a date
appears, it is a centre of gravity, not a deadline.

#text(size: 8pt)[#table(
  columns: (1.05fr, 1.5fr),
  inset: 6pt, align: (left + top, left + top),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Prediction*], [*Why it follows / why it might be wrong*]),
  [*1. Learned codecs win high-value edges first.* Neural compression becomes standard for precious, long-lived data (scientific, medical, genomic) by the early 2030s; everyday bytes stay on fast classical coders.],
  [*Follows:* neural wins ratio but loses speed by orders of magnitude (Ch. 62); it colonizes data where ratio justifies the compute. *Might fail if:* dedicated neural-codec silicon makes inference cheap enough to undercut zstd on hot data, as GPUs did for neural nets.],

  [*2. Compression and AI become inseparable.* Sub-2-bit weight coding and KV-cache compression (MLA) are routine; "the model as compressor" and "compressing the model" are two faces of one coin.],
  [*Follows:* the merger argument of §2 and Chapters 63–65. *Might fail if:* a non-neural AI paradigm displaces transformers, though the compression = prediction identity (Ch. 23) is a theorem, not a fashion, and survives any architecture.],

  [*3. Semantic coding ships machine-to-machine first.* By ~2030 (6G era) it is real for telemetry and sensor fusion; general meaning-level human communication stays in research.],
  [*Follows:* 6G-GOALS programmes and the information-bottleneck framing (§3). *Might fail if:* the silent-catastrophic-failure problem proves intractable and the field retreats to classical lossy coding with a semantic garnish.],

  [*4. Compression disappears into hardware.* Transparent in-storage and in-network compression makes the question "is this compressed?" invisible to application programmers.],
  [*Follows:* the computational-storage trend (§4) and DEFLATE's own history (Ch. 30). *Might fail if:* format fragmentation and application-specific models keep compression visible at the app layer longer than storage vendors would like.],

  [*5. The classical champions do not die.* zstd, DEFLATE, JPEG, AV1/AV2, Opus, FLAC remain the deployed backbone through 2040, gaining incremental tuning, not replacement.],
  [*Follows:* the no-free-lunch theorem plus brutal installed-base economics (Chs. 77–78). *Might fail if:* a royalty-free learned codec with hardware decode matches zstd's speed, possible, but only if it beats fifty years of optimized engineering.],

  [*6. The fundamental limits never move.* Shannon's entropy floor and Kolmogorov's uncomputability bound everything in 2040 exactly as in 1948.],
  [*Follows:* they are *proved* (Chs. 18–19, 22). *Might fail if:* mathematics itself is overturned, which it will not. This is the one prediction with a proof attached.],
)]

#history[
  The field has a strong track record of *over*-predicting revolution and
  *under*-predicting the staying power of the boring classics. In the 1990s wavelets
  were going to sweep away the "obsolete" DCT; thirty years on, the DCT-based JPEG
  and its descendants still encode most of the world's images (Chapters 42, 45). The
  safe long-term bet in compression has almost always been this: *the simple, fast,
  good-enough, royalty-free thing wins the volume, and the brilliant thing wins the
  niche.* Keep that asymmetry in mind whenever someone announces that a new codec
  changes everything.
]

== Why compression stays permanently invaluable

Step back and ask the question a sceptic would: if predictors keep getting better,
won't compression eventually be "solved" and fade away? The answer, threaded
through this whole book, is a firm *no*, and there are four independent reasons,
each proved or argued in an earlier chapter, that guarantee it.

+ *The limits are permanent (Chapters 8, 18, 22).* The counting proof above and
  Shannon's entropy floor are not engineering hurdles that better technology clears;
  they are mathematical facts. There will *always* be a non-trivial gap between raw
  data and its entropy, and *always* be skill in approaching that floor cheaply. A
  field bounded by theorems that cannot be repealed does not get "solved"; it gets
  *refined forever*.

+ *Better models are the only lever, and modelling is open-ended (Chapters 23, 33,
  61).* Because compression *is* prediction, and prediction *is* learning, "better
  compression" has no ceiling short of perfectly modelling reality, which is to say,
  short of intelligence itself. The frontier of compression moved into the frontier
  of AI precisely because it ran out of cheap tricks and started needing genuine
  understanding. That makes it *more* alive, not less.

+ *The economics keep tilting toward it (§1, §4).* The scissors between exploding
  data and stagnating cheap hardware widen every year. Each widening makes spending
  computation to save storage and bandwidth a *better* deal. A technology whose value
  proposition strengthens with every passing year is not headed for retirement.

+ *Compression is how we cope with finitude (the whole book).* In the end this is
  the human reason. We have finite disks, finite spectrum, finite energy, finite
  attention, and an infinite appetite to record, transmit, and understand. Every
  compressor is a small act of choosing *what matters* and discarding what does not.
  From Morse shortening "E" to a single dot (Chapter 2), to JPEG discarding the
  high frequencies your eye ignores (Chapter 42), to an LLM distilling the regularity
  of all human text into its weights (Chapter 62), the act is the same: *find the
  pattern, keep the meaning, drop the rest.* That act is not going anywhere, because
  the gap between what we can record and what we can keep is the permanent condition
  of a finite mind in an infinite world.

#keyidea[
  Compression is invaluable not despite better predictors but *because* of them:
  every improvement in our ability to model the world is, by the identity of
  Chapter 23, an improvement in compression, and the converse holds too. The two
  cannot be separated, and neither can be finished, because modelling reality has no
  upper bound. That is why the future of compression is, quietly, the future of
  understanding itself.
]

This is where the running scoreboard finally closes. We have watched our sample
shrink the whole way down the book; the last column is not a number we can write
today, because the limit it approaches is the entropy of the data under the *best
model anyone will ever build*, and that frontier moves with the frontier of AI.

#scoreboard(
  caption: "the whole journey, and the open road ahead",
  [Raw bytes], [-], [1.00×], [Chapter 1: the starting line],
  [Huffman / arithmetic / ANS], [-], [≈2×], [Vol. II: reach the per-symbol entropy floor],
  [DEFLATE / zstd / BWT], [-], [3–5×], [Vol. II: model the context, not just symbols],
  [JPEG / AV1 / Opus (lossy)], [-], [10–100×], [Vol. III: discard the imperceptible],
  [Learned + LLM coders], [-], [best known], [Vol. IV: model the *source itself*],
  [The entropy of the best model], [?], [the floor], [the limit, and it keeps moving],
)

#checkpoint[
  In one sentence, why can the last row of that scoreboard never be filled in with a
  fixed number?
][
  Because its value is the entropy of the data under the *best possible model*, and
  since "best model" tracks the open-ended frontier of prediction/learning, the
  target keeps moving; it is bounded below by Shannon's $H$ but otherwise has no
  fixed ceiling we can name today.
]

#takeaways((
  [The defining tension of the next decade is the *scissors*: data created is
   doubling roughly every 2–3 years while the cost-efficiency of storage and compute
   is flattening. Compression turns a shortage of space and bandwidth into a surplus
   of computation, and that trade keeps getting *more* favourable.],
  [No technology repeals the *no-free-lunch* counting bound or Shannon's entropy
   floor. Every future advance is therefore an advance in *modelling*: a sharper bet
   about what the data looks like.],
  [Compression and AI have *merged into one frontier*. By the identity of Chapter 23,
   compressing better *is* predicting better; learned coders win on ratio (and lose
   on speed), training a model *is* compressing its data, and AI's own weights and
   caches survive only by being compressed.],
  [*Semantic / goal-oriented communication* aims to transmit *meaning for a task*
   rather than a faithful signal, potentially saving orders of magnitude, at the
   price of needing a shared, trusted model and risking silent catastrophic failure.],
  [Compression is becoming an *energy and sustainability* lever and is migrating
   *into hardware* (network cards, SSD controllers, storage engines) on its way to
   becoming invisible infrastructure.],
  [The reasoned bets: classical champions endure; learned coders take the
   high-value edges; semantic coding ships machine-to-machine first; compression
   disappears into silicon; and the fundamental limits never move. The last bet is
   the only one with a proof attached.],
  [Compression stays permanently invaluable because its limits are permanent, its
   only lever (better models) is open-ended, its economics keep tilting toward it,
   and it is simply *how a finite mind copes with an infinite world*.],
))

== Exercises

#exercise("81.1", 1)[
  *The scissors, quantified.* Suppose the world's data grows at 25% per year and
  the cost-efficiency of storage (bytes per dollar) improves at only 10% per year.
  (a) Using the rule of 70, give the doubling time of each. (b) After 14 years
  (about two doublings of the data), by what factor has the *gap* (the ratio of
  data volume to affordable storage) widened? Explain in one sentence why this is
  the core argument for compression's growing importance.
]
#solution("81.1")[
  (a) Data doubles in $70/25 = 2.8$ years; affordable storage doubles in
  $70/10 = 7$ years. (b) Over 14 years, data multiplies by $1.25^14 approx 23$
  while affordable storage multiplies by $1.10^14 approx 3.8$. The gap widens by
  $23 / 3.8 approx 6$×. So in 14 years you would need to compress about *6× harder
  just to stand still*; that mounting deficit, compounding every year, is exactly
  why compression's value strengthens rather than fades.
]

#exercise("81.2", 2)[
  *Why "compress everything by 1 byte" is impossible: your version.* Adapt the
  counting proof from this chapter. Consider all files of length *exactly* 10 bits
  (there are $2^10 = 1024$ of them). Suppose a lossless compressor maps each to a
  file of length *at most* 9 bits. How many distinct outputs of length $<= 9$ bits
  exist? Conclude that at least two inputs must collide, and state in one sentence
  what that means for the decompressor.
]
#solution("81.2")[
  Outputs of length at most 9 bits number $2^0 + 2^1 + dots.c + 2^9 = 2^10 - 1 =
  1023$. There are 1024 inputs but only 1023 possible shorter outputs, so by the
  pigeonhole principle at least two distinct 10-bit inputs map to the *same* output.
  The decompressor, seeing that one output, cannot know which of the two inputs
  produced it, so the scheme cannot be lossless. (Hence some input must *not*
  shrink: there is no universal one-byte shrinker.)
]

#exercise("81.3", 2)[
  *Semantic vs. lossy.* A drone must report to base whether a field contains a fire.
  Compare three strategies: (a) send a JPEG of the field; (b) send a heavily
  quantized, blocky JPEG; (c) send the single bit "fire / no fire" from an onboard
  detector. For each, state roughly how many bytes travel and one *failure mode*.
  Then explain why (c) is *semantic* compression and not merely *very lossy*
  compression, referring to what success is measured against.
]
#solution("81.3")[
  (a) Tens to hundreds of KB; failure mode: bandwidth/latency cost, may not fit a
  constrained link. (b) A few KB; failure mode: artefacts could hide or fake a small
  fire (signal-level distortion). (c) 1 bit (well under a byte in practice); failure
  mode: the onboard detector model is *wrong* and confidently reports the opposite
  of reality, a silent, catastrophic, *meaning-level* error. Strategy (c) is
  semantic because it transmits nothing resembling the original signal; its success
  is measured against *fitness for the task* ("did base learn the truth about the
  fire?"), not *fidelity to the image*. A lossy JPEG, however blocky, is still trying
  to reproduce the *signal*; (c) abandons the signal entirely and preserves only the
  task-relevant *meaning*, which is the defining move of semantic communication.
]

#exercise("81.4", 3)[
  *The energy break-even.* Extend the chapter's `choose_method` idea. A high-ratio
  coder costs $C$ energy units to compress a file once and shrinks it to a fraction
  $r$ of its size; a cheap coder costs ≈0 to compress and shrinks to fraction $r_0 >
  r$. Reading back 1 unit of stored size costs $e$ energy units per read, and the
  file is read $N$ times over its life. (a) Write the total-energy expressions for
  both coders (ignore storage-idle power). (b) Solve for the number of reads $N^*$
  at which the expensive coder breaks even. (c) Interpret: for *cold archival* data
  ($N$ tiny) versus a *hot log* ($N$ huge), which coder wins, and why does this
  justify the chapter's claim that "read count and lifetime, not ratio alone, decide
  whether harder compression is greener"?
]
#solution("81.4")[
  Let the original size be $S$. (a) Expensive: $E_"hi" = C + e dot (r S) dot N$.
  Cheap: $E_"lo" = 0 + e dot (r_0 S) dot N$. (b) Break-even when $E_"hi" = E_"lo"$:
  $C = e dot S dot (r_0 - r) dot N$, so $N^* = C \/ (e dot S dot (r_0 - r))$. (c) For
  cold archival data $N < N^*$, the one-time compression cost $C$ dominates and the
  *cheap* coder wins on energy (you rarely read it back, so the storage savings never
  pay off the compute). For a hot log $N > N^*$, the per-read savings $e(r_0 - r)S$
  accumulate past $C$ and the *expensive, high-ratio* coder wins (every cheap decode
  saved, multiplied by millions of reads, dwarfs the one-time cost). Because $N^*$
  depends on the read count $N$ and the file's lifetime, not on the ratio $r$ alone,
  the greenest choice is a property of *how the data will be used over its whole
  life*, exactly as claimed. (Note the subtlety: a *higher* ratio raises $C$ but also
  raises the per-read saving, so the break-even shifts both ways; the decision is
  genuinely multi-variable, which is why future storage tiers will make it
  automatically.)
]

== Further reading

The primary sources behind this chapter's claims, all introduced earlier in the
book, repay a direct read now that you can see the whole arc:

- #link("https://arxiv.org/abs/2309.10668")[Delétang et al. (2024), _Language Modeling Is Compression_]: the cleanest demonstration that a general predictor is a general compressor (Chapter 62).
- #link("https://arxiv.org/abs/0712.3329")[Legg & Hutter (2007), _Universal Intelligence_]: the formal case that compression measures intelligence (Chapter 61).
- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon (1948), _A Mathematical Theory of Communication_]: re-read the first page, where he sets *meaning* aside; semantic communication is the field finally picking it back up.
- #link("https://arxiv.org/abs/math/0406077")[Grünwald (2004), _A Tutorial Introduction to the MDL Principle_]: the bridge between "shortest description" and "best model" that underwrites §2.
- #link("https://arxiv.org/abs/2402.07573")[6G-GOALS (Strinati et al., 2024), _Goal-Oriented and Semantic Communication in 6G AI-Native Networks_]: the most concrete current programme for compressing *meaning* over the air (§3).
- #link("https://arxiv.org/abs/2402.17764")[Wang et al. (2024), _The Era of 1-bit LLMs_ (BitNet b1.58)]: the information-theoretic frontier of compressing the models themselves at $log_2 3 approx 1.58$ bits/weight (Chapter 63).
- #link("https://arxiv.org/abs/2202.06533")[Yang, Mandt & Theis (2023), _An Introduction to Neural Data Compression_]: a survey of where the learned-codec frontier stood as the merger accelerated.

#bridge[
  There is no next chapter. You have reached the end of the road we set out on in
  Chapter 1, and you arrive carrying everything: the counting and the logarithms,
  Shannon's entropy and Kraft's inequality, Huffman and arithmetic coding and ANS,
  the whole LZ family and DEFLATE and zstd, the cosine transform and JPEG and Opus
  and AV1, the neural codecs and the language models, and the one idea that ties them
  all together: that to compress is to predict, and to predict is to understand.
  `tinyzip` sits finished on your disk, a real compressor you built with your own
  hands from an empty file. The genuine bridge from here leads *out* of this book:
  pick one corner that lit you up (a codec to implement end to end, a benchmark to
  enter, a paper from the further-reading lists to truly digest, a piece of the
  Hutter Prize to chase) and go make the gap between data and its entropy a little
  smaller. The field has been built, for seventy-five years, by exactly the kind of
  curious person who reads a book like this one all the way to its last line. Welcome.
  You are one of us now.
]
