#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= What Is Compression?

#epigraph[
  The fundamental problem of communication is that of reproducing at one point
  either exactly or approximately a message selected at another point.
][Claude Shannon, 1948]

Here is a puzzle to open with. A single hour of 4K cinema, the kind Netflix streams
to your television, contains roughly 2 *terabytes* (about 2,000 gigabytes) of raw pixel
data. On a fast home internet connection that is the better part of a *day's* worth of
downloading, which means streaming it in real time would be flatly impossible. Yet
millions of people do exactly that, every evening, simultaneously. The same hour of 4K
footage, after compression, fits inside roughly 5 to 10 gigabytes and flows through your
broadband without a hiccup.

Where did the other 99-plus percent of that data go? And more importantly: how can throwing
away that much data produce something that looks exactly right to your eyes?

That question is what this book is about. The answer turns out to run far deeper than
"files get smaller." It connects to one of the most profound mathematical results of the
twentieth century, to a history full of brilliant people, bitter patent wars, and
billion-dollar business bets, and to a stunning modern realization: the best compressors
and the best artificial intelligences are, at a deep level, doing the same thing.

This opening chapter lays the foundation for everything that follows. It answers three
questions: what compression actually is, why it is not optional but structurally necessary
for the modern world, and what this book's contract with you (the reader) looks like.
No equations yet. No code yet. Just the big picture, drawn clearly.

#recap[
  This is the first chapter, so there is no earlier material to recap. Everything you
  need right now is your ability to reason carefully and your willingness to follow an
  idea through. The mathematics and the Python programming will be built up from scratch,
  starting with Chapter 4 (numbers and number systems) and Chapter 15 (Python from zero).
]

#objectives((
  [Explain in plain language what compression is and why it exists.],
  [Distinguish lossless from lossy compression and name two concrete examples of each.],
  [Describe the model + coder idea that underlies every compressor.],
  [State the one result that proves no compressor can shrink every input.],
  [Recognize the tinyzip project that you will build throughout this book.],
))

== The Numbers Do Not Fit

Start with numbers, because the numbers are staggering.

*Video.* A single frame of 4K video is 3,840 pixels wide and 2,160 pixels tall. Each
pixel carries three colour values (red, green, blue), and each value takes 8 bits to
store. Multiply that out: $3840 times 2160 times 3 times 8 = 199,065,600$ bits per frame,
just under 200 million bits, or about 25 megabytes, for *one* still frame. A standard film
runs at 24 frames per second, so one second of raw 4K video is $24 times 199,065,600
approx 4.8$ billion bits. One hour is 3,600 of those seconds: about 17.2 *trillion* bits,
which is roughly 2.1 terabytes. The average home broadband connection in the United States
in 2025 runs at about 200 megabits (200 million bits) per second. Pouring 17.2 trillion
bits through a 200-million-bits-per-second pipe takes $17.2 times 10^12 \/ (200 times 10^6)
approx 86,000$ seconds, close to a full *day* to download a single hour of raw 4K.

What actually happens: H.265/HEVC or AV1 compression reduces that same hour to roughly
5 to 15 gigabytes without noticeable quality loss. Streaming becomes not just possible
but routine. The difference between "4K streaming is impossible" and "hundreds of millions
of people watch it tonight" is, literally, the existence of good compression algorithms.

*Genomes.* The human genome contains about 3 billion base pairs. Each pair is one of
four possibilities (A, C, G, T), which takes 2 bits to represent. Raw storage: roughly
750 megabytes per genome. That sounds manageable, until you realize that a single modern
genome sequencing centre processes thousands of samples per week, and each run does not
produce just the genome but the raw sequencing reads (short overlapping fragments with
quality scores and metadata), which can run to 100–200 gigabytes per sample. A national
biobank might store genetic data for a million patients. Without compression, the storage
bill alone would be prohibitive. With formats like CRAM (which exploits the fact that
human genomes differ from each other by only about 0.1%, so one genome can be described
as a short list of differences from a reference), storage shrinks by a factor of 5 to 10.
Population-scale genetics is only possible because of compression.

*Artificial intelligence models.* A large language model like Llama 3 70B is, at the
physical level, a file of numbers: the weights of a neural network. Seventy billion
weights, each stored as a 32-bit floating-point number, adds up to 280 gigabytes. Loading
that onto a single consumer GPU is impossible; deploying it on a mobile phone is
laughable. Quantization (a form of lossy compression that reduces each weight from 32
bits to 4 bits) shrinks the model to about 35 gigabytes. More aggressive techniques
push further. The AI models that run in your phone's keyboard, your voice assistant, and
your camera's face-detection system are compressed AI models. The entire industry of
on-device AI depends on compression to exist.

*The web itself.* By 2025, the internet was routing something like 79 exabytes of traffic
per month. More than 60% of that traffic is video. Almost every byte of it passes through
at least one compression codec. HTML, CSS, JavaScript, and JSON pages are compressed
automatically by your browser and the web server (using gzip, Brotli, or Zstandard) before
they travel over the network. Without HTTP content compression, the web would require
several times more physical infrastructure to carry the same information.

#keyidea[
  Compression is not a performance optimisation you can choose to skip. It is the
  structural mechanism by which the gap between "how much data exists" and "how much
  bandwidth and storage humanity has" is closed. Every major leap in what digital
  technology can do (streaming video, mobile internet, scalable genomics, deployable AI)
  was enabled, in part, by a corresponding leap in compression.
]

== What Compression Actually Means

Strip away the applications and the idea is simple. A *compressor* takes a sequence of
bits as input and produces a (usually shorter) sequence of bits as output. A matching
*decompressor* inverts the process: given the compressed output, it reconstructs the
original. Together they form a *codec* (coder–decoder). The central question is: on what
kinds of input does the output tend to be shorter, by how much, and at what cost in time
and computing power?

There are two fundamentally different flavours of codec, and they exist for different
reasons and obey different laws.

=== Lossless compression

A lossless codec guarantees that the decompressed output is *bit-for-bit identical* to
the original. Not approximately identical. Not very similar. Identical. Every 0 and
every 1 in the original is present in the reconstruction.

#definition("Lossless compression")[
  A pair of algorithms (Compress, Decompress) such that for every input string $s$,
  $"Decompress"("Compress"(s)) = s$ exactly. The output of Compress will usually be
  shorter than $s$ for the kinds of data the codec is designed for, but the guarantee of
  perfect reconstruction is absolute.
]

Lossless compression is mandatory when a single changed bit would corrupt the data beyond
use. Text files, source code, spreadsheets, databases, cryptographic keys, ZIP archives,
executable programs, PDF documents: all of these must be lossless. If you compress your
tax return and get back something one bit different, the numbers might change. If you
compress an executable and get back something one byte different, the program might crash
or behave in unexpected ways.

Examples of lossless codecs: gzip (used for web pages and software downloads), PNG
(images where every pixel must be preserved exactly), FLAC (audio where audiophiles
need the exact original), 7-Zip (general archive format for files of any kind).

=== Lossy compression

A lossy codec trades perfect reconstruction for much smaller size. The decompressed
output is *an approximation* of the original: similar, possibly indistinguishable to a
human, but not identical.

#definition("Lossy compression")[
  A pair of algorithms (Encode, Decode) such that $"Decode"("Encode"(s)) approx s$
  under some agreed measure of quality, but the original cannot generally be recovered
  exactly. Information is irreversibly discarded during encoding.
]

Lossy compression is appropriate when the *intended consumer of the decoded data* cannot
perceive the difference, or does not need to. Your ear cannot hear frequencies above about
20,000 cycles per second. An MP3 encoder can simply discard all that high-frequency
information, and you will never notice. Your visual system is much more sensitive to
changes in brightness than to changes in colour. JPEG exploits this by compressing the
colour channels more aggressively than the brightness channel. You look at the JPEG and
it looks fine. But compare it to the original at the pixel level and you will find
differences in almost every pixel.

Examples of lossy codecs: JPEG (photographs), MP3 and AAC (music), H.264 and AV1 (video),
Opus (voice calls and streaming audio). These codecs make the web's media experience
possible at realistic data rates.

#pitfall[
  *Lossy does not mean bad.* Lossy compression routinely produces output that is
  completely indistinguishable from the original to human senses, while being ten to
  fifty times smaller. The question is always: *who (or what) will consume the decoded
  data, and what can they not detect?* A JPEG photograph looks identical to the original
  for casual viewing. The same JPEG might be unsuitable for a forensic image analysis
  system that needs to detect tiny changes in colour gradient. A lossy codec is a bargain;
  like all bargains, it matters that you know what you are giving up.
]

#misconception[Lossless compression always produces a smaller file.][
  Lossless compression *tends* to produce smaller files for structured, redundant data.
  But on some inputs it *must* produce a larger file; this is mathematically unavoidable
  (we will see why in a moment). Compress a JPEG with gzip and the output will often be
  slightly *larger* than the input, because the JPEG is already nearly random-looking and
  gzip can find nothing further to remove. The right response is to detect this and store
  the original uncompressed, which is what most archive programs do automatically.
]

=== The one diagram that explains everything

Both kinds of compression, and indeed every compressor that has ever been built, can
be understood through a single architectural diagram: the *model + coder* decomposition.

#fig(
  [The model + coder decomposition. Every compressor consists of these two stages.],
  cetz.canvas({
    import cetz.draw: *

    // Input arrow
    content((0.5, 3.3), text(size: 9pt)[*Data in*])
    line((0.5, 3.0), (0.5, 2.45), mark: (end: ">"))

    // Model box
    rect((0, 1.6), (6, 2.4), fill: rgb("#e8f4f8"), stroke: rgb("#0b5394") + 1.2pt, radius: 3pt)
    content((3, 2.0), box(width: 5.6cm, inset: 2pt, align(center, text(size: 9pt)[*Model*: predicts what comes next])))

    // Arrow from model to coder
    line((3, 1.6), (3, 1.15), mark: (end: ">"))
    content((3.8, 1.37), text(size: 8pt)[probabilities])

    // Coder box
    rect((0, 0.3), (6, 1.1), fill: rgb("#e8f8ee"), stroke: rgb("#0b6e4f") + 1.2pt, radius: 3pt)
    content((3, 0.7), box(width: 5.6cm, inset: 2pt, align(center, text(size: 9pt)[*Coder*: converts probabilities to bits])))

    // Output arrow
    line((3, 0.3), (3, -0.15), mark: (end: ">"))
    content((3.8, 0.07), text(size: 8pt)[fewer bits])
    content((3, -0.35), text(size: 9pt)[*Compressed output*])

    // Feedback arrow (model updates from data)
    line((6, 2.0), (7.2, 2.0), (7.2, 0.7), (6, 0.7),
      stroke: (dash: "dashed", paint: rgb("#783f04"), thickness: 0.8pt),
      mark: (end: ">"))
    content((7.9, 1.35), text(size: 7pt, fill: rgb("#783f04"))[model #linebreak() updates])
  })
)

The *model* looks at the data seen so far and answers a single question: *what is likely
to come next, and with what probability?* It does not produce any compressed bits. It
produces a probability prediction.

The *coder* takes that prediction and the actual next symbol and produces bits. The key
insight: if the model predicted the symbol with high probability, the coder needs very
few bits to encode it. If the model predicted it with low probability (it was a surprise),
the coder needs more bits. The better the model's predictions, the fewer bits the coder
produces overall.

This is the whole game. Every compressor ever built fits this pattern:

- In *Huffman coding*, the model is a table of how often each symbol appears (its
  frequency). The coder assigns short bit sequences to common symbols and long ones to
  rare symbols. A file where 'e' appears 12% of the time gets a short code for 'e'.

- In *gzip/DEFLATE*, the model is a sliding window of recent bytes: the coder looks back
  to find repeated patterns and replaces them with short references, then uses a Huffman
  coder on the result. The "model" is the assumption that patterns repeat.

- In *JPEG*, the model is an 8×8 block of pixels transformed into frequency coefficients:
  the model has observed that natural images contain mostly low-frequency information
  (gentle gradients), so the coder spends few bits on those and more on the (less common)
  high-frequency details.

- In a *large language model used as a compressor*, the model is a neural network with
  billions of parameters that has learned, from trillions of words of text, what word is
  likely to follow any given sequence. The coder is an arithmetic coder. The model's
  predictions are so good that the coder achieves remarkable compression ratios, even on
  images and audio that the model was never explicitly trained on.

#keyidea[
  *The model/coder principle:* every compressor = model + coder. The coder's job is
  largely solved: arithmetic coding and ANS (Asymmetric Numeral Systems) can
  convert any probability model into a compressed bitstream that is close to optimal.
  The interesting engineering challenge is always the model. The entire history of
  compression is the history of building better models: from simple frequency tables, to
  sliding-window pattern matchers, to neural networks trained on the structure of human
  knowledge.
]

#gomaths("What is a bit?")[
  You will see the word *bit* throughout this book. Here is what it means from scratch.

  A *bit* (short for *binary digit*) is the simplest possible unit of information: it
  can hold exactly two values, conventionally written as 0 and 1. Think of a light
  switch: on or off. A single bit can distinguish between two equally likely outcomes.
  A coin flip (heads or tails) carries exactly one bit of information.

  Two bits can distinguish between four outcomes: 00, 01, 10, 11. Three bits can
  distinguish eight outcomes. In general, $n$ bits can represent $2^n$ different things.
  That superscript notation means "2 raised to the power $n$", i.e. multiplied by itself
  $n$ times: $2^3 = 2 times 2 times 2 = 8$.

  *The connection to information:* if something happens with probability $p$ (where
  $p = 1$ means certain and $p = 0$ means impossible), the number of bits needed to
  encode it is $-log_2(p)$. The logarithm base 2 is the function that answers: "what
  power do I need to raise 2 to in order to get this number?" So $log_2(8) = 3$ because
  $2^3 = 8$, and $log_2(1) = 0$ because $2^0 = 1$.

  The minus sign is there because $p$ is always between 0 and 1, which makes $log_2(p)$
  negative, so $-log_2(p)$ is positive. A very likely event ($p$ close to 1) carries
  almost zero bits of information (no surprise). A rare event ($p$ close to 0) carries
  many bits (big surprise). That is the mathematical heart of compression: common things
  get short codes, rare things get long codes. Chapter 7 builds this up fully.

  *How many bits does a byte have?* A *byte* is 8 bits, a convention so universal
  it is baked into every computer ever built. File sizes are measured in bytes, kilobytes
  (1,024 bytes), megabytes, gigabytes, and so on. The human genome in 750 megabytes means
  $750 times 1,024 times 1,024 times 8 = 6,291,456,000$ bits.
]

== Why You Cannot Compress Everything

Here is one of the most elegant results in computer science, provable with nothing but
the ability to count.

Suppose you have a compressor that claims to shrink every possible file. Let's test this
claim on files that are exactly 1,000 bits long. How many different 1,000-bit files exist?
Each of the 1,000 positions can be 0 or 1, so there are $2^1000$ possibilities. That is
an astronomically large number (far more than the atoms in the observable universe),
but the exact value does not matter. Let us call it $N = 2^1000$.

Now: our compressor claims to shrink every one of these $N$ inputs to at most 999 bits.
How many distinct 999-bit files exist? At most $2^999$. But $2^999$ is exactly half of
$2^1000$. So we need $N = 2^1000$ distinct outputs from at most $N/2 = 2^999$ output slots.
By the *pigeonhole principle* (if you have more items than containers, at least two items
must share a container), at least two different 1,000-bit inputs must compress to the same
999-bit output. But then the decompressor, given that output, cannot know which of the two
originals to restore. It is stuck. Perfect lossless reconstruction is impossible.

This argument generalises to any lengths, any compressor, any claim of universal
compression. *No lossless compressor can compress every input.* For every file it
shortens, there must exist some other file it either leaves the same size or makes longer.
Compression only works because real-world data (text, photographs, genomes, source code)
is not uniformly random. It has structure and patterns, and compressors exploit those
patterns. Compress a truly random file and the output will often be slightly larger than
the input, because there is no pattern to exploit.

#aside[
  This result is why you should be deeply suspicious of anyone claiming to have invented
  a "universal compressor" that always makes files smaller. It is mathematically
  impossible. History is littered with such claims, sometimes from people who genuinely
  believe they have made a discovery (a testing mistake hid the cases that would have
  gotten longer), and occasionally from outright fraud. Chapter 78 examines several
  historical examples of this pattern, including the legal cases some of them spawned.
  The pigeonhole argument above is a complete and airtight refutation.
]

The impossibility of universal compression has a practical corollary: *already-compressed
data cannot be compressed again.* If you run gzip on a JPEG photograph, the output will
be roughly the same size as the input or slightly larger. JPEG has already squeezed out
all the structure the compressor could find. The remaining bits look, to gzip, essentially
random, and truly random bits, as we argued above, cannot be compressed at all. This is
why you never see streaming services "double-compress" their video, and why ZIP archives
of JPEG images are never significantly smaller than the originals.

== A First Look at the Limits

You now know what compression is and why it can't work on everything. The next natural
question is: for data that *can* be compressed, how far can you go? What is the absolute
best a lossless compressor could possibly achieve?

The answer was given in 1948 by Claude Shannon, a 32-year-old mathematician at Bell
Telephone Laboratories in New Jersey. His result is called the *source coding theorem*,
and it says: the best possible lossless compressor, for data drawn from a source with a
certain pattern of probabilities, achieves an average code length of exactly *one quantity*,
no shorter and achievable in principle. That quantity is called the *entropy* of the
source.

We will not define entropy mathematically until Chapter 18, because doing so properly
requires probability theory that we build in Chapters 9–10. But the intuition is simple:
entropy measures how *random* or *surprising* the source is. A source where every output
is completely predictable (say, a file of all zeros) has entropy zero and can be
compressed to essentially nothing. A source where every output is completely random and
unpredictable has maximum entropy and cannot be compressed at all. English text sits
somewhere in between: it has a lot of structure (certain letters follow certain others far
more often than chance, some words appear thousands of times more than others), and
Shannon estimated in 1951 that its entropy is roughly 1.0 to 1.5 bits per character.
Since text is normally stored as 8 bits per character (one byte), that means English text
has a theoretical compression potential of roughly 5× to 8×, and the best compressors
do indeed achieve ratios in that range.

#history[
  Claude Elwood Shannon published "A Mathematical Theory of Communication" in two
  parts in the July and October 1948 issues of the Bell System Technical Journal. He was
  32 years old. The paper introduced the concept of *entropy* as the measure of information,
  proved the source coding theorem, gave the word *bit* its technical meaning (crediting
  the coinage to John Tukey, who had used it informally), and laid the foundations for
  both lossless compression theory and, in a 1959 follow-up, lossy compression theory.

  The historian James Gleick, in his 2011 book _The Information_, called the 1948 paper
  "even more profound and more fundamental" than the invention of the transistor, which
  happened the same year, in the same building at Bell Labs. Shannon's paper described
  the mathematics of information itself; the transistor was merely hardware.

  Shannon was famously modest and notoriously private. By the accounts of his Bell Labs
  colleagues, he juggled multiple balls at once, built maze-solving mechanical mice, and
  rode a unicycle down the laboratory hallways. That a man who spent his spare time on
  such diversions had also written, in a single paper, the theoretical framework for the
  entire digital age is one of the better stories in twentieth-century science.
]

For lossy compression, the analogous limit is given by *rate–distortion theory*, also
developed by Shannon (with a key paper in 1959). It answers: if I am willing to accept
some amount of error (some *distortion*) in the reconstructed output, what is the
minimum number of bits I need? The rate–distortion function gives a curve: the better
the quality you demand, the more bits you must spend, with diminishing returns as you
approach perfection. Real codecs like JPEG, MP3, and H.264 can be understood as
engineering attempts to get close to this curve for their specific type of data.

These two theoretical limits (entropy for lossless, the rate–distortion curve for lossy)
are the stars compression engineers steer by. Algorithms get judged by how closely
they approach the limits, at what computational cost.

== The tinyzip Project

Throughout this book, you will build a real working compressor, not merely read about
one. We call it *tinyzip*. It is a Python program that you assemble
piece by piece, adding each new technique as you learn it, until by the final chapters
you have a surprisingly capable compression tool built entirely from scratch.

#project("tinyzip · the build-along project")[
  This is the tinyzip project. In later chapters, you will write Python code in boxes like
  this one. The actual building begins in *Chapter 15*, where Step 1 sets up the package
  skeleton; every later step is numbered and adds one piece. For now, just know the plan:

  - Chapters 15–17: lay the plumbing. The `tinyzip/` package, a `histogram()` helper,
    and a from-scratch `BitWriter`/`BitReader` for reading and writing individual bits.
  - Chapter 24 (Huffman coding): the first real codec, a working Huffman encoder and decoder.
  - Chapter 26 (Arithmetic coding): add an arithmetic entropy coder.
  - Chapter 27 (ANS): swap in rANS for speed.
  - Chapter 28 (LZ77): build a sliding-window match finder.
  - Chapter 30 (DEFLATE): assemble a gzip-class core from the above pieces.
  - Chapter 35 (BWT): implement the Burrows–Wheeler Transform.
  - Chapter 42 (JPEG): build a toy image encoder.
  - Chapter 51 (Video): add inter-frame prediction.

  Each `#project` step gives you runnable, tested Python 3.14 code, builds on the previous
  one, and reuses the same modules and function names throughout. By the end, `tinyzip`
  will compress and decompress real files.

  No code is expected from you yet, and this opening chapter carries no step number. The
  numbering starts at Step 1 in Chapter 15, once you have learned enough Python.
]

The tinyzip project serves a purpose beyond getting you to write code. It forces
every idea in the book to be *concrete*. An entropy coder becomes a function you call;
a match finder becomes code you debug. Every technique that looks abstract on the page
will, by the time you have implemented it, feel as tangible as a tool in your hand.

== Lossless and Lossy: A Closer Look at Two Regimes

Because the rest of this book is organized around the lossless/lossy distinction, it is
worth painting a slightly more detailed picture of each before moving on.

=== Lossless in depth

Every lossless compressor works by finding and exploiting *statistical redundancy*: the
fact that the input is not uniformly random. The main strategies are:

*Statistical coding* assigns shorter bit patterns to more common symbols. If 'e' appears
in a text 12% of the time and 'z' only 0.07% of the time, it makes sense to use a
shorter bit pattern for 'e' and a longer one for 'z'. Huffman coding (Chapter 24) is the
canonical example; arithmetic coding (Chapter 26) and ANS (Chapter 27) go further.

*Dictionary coding* notices that real data contains repeated phrases. Instead of encoding
each occurrence of the word "the" from scratch, a dictionary compressor stores it once
and then says "reference to earlier copy," which is much shorter. LZ77, LZ78, DEFLATE,
gzip, Brotli, Zstandard: all dictionary compressors (Chapters 28–32).

*Transform coding for lossless use* rearranges data so that redundancy is easier to
exploit. The Burrows–Wheeler Transform (Chapter 35) is a famous example: it permutes the
bytes of its input so that the same character tends to appear in long runs, which simple
run-length coding can then compress dramatically.

*Statistical modelling* predicts each symbol using its context: the symbols that came
before it. The more context you use, the better your predictions and the fewer bits you
need. PPM (Prediction by Partial Matching) and context-mixing compressors (Chapters 33–34)
push this to the extreme.

In practice, the best lossless compressors layer these techniques. DEFLATE = LZ77 +
Huffman. 7-Zip's LZMA = large-window LZ + arithmetic coding + context modelling.
bzip2 = Burrows–Wheeler Transform + move-to-front + Huffman. Zstandard = LZ77 +
trained dictionary + ANS entropy coder. Each layer removes a different kind of redundancy.

=== Lossy in depth

Lossy compression adds a step that lossless cannot use: it *chooses what to throw away*.
The choice is guided by knowledge of who will use the decoded data and what they can
or cannot perceive.

For images and video, the key insight is that human vision is a non-uniform sensor.
We detect brightness variations much more readily than colour variations, and we are far
more attuned to smooth gradients than to fine texture. JPEG exploits both facts: it
decomposes each 8×8 block of the image into frequency components and discards the
high-frequency ones that human eyes barely notice.

For audio, the key insight is *psychoacoustic masking*: sounds can be masked by nearby
sounds. A very loud sound at one frequency temporarily deafens your ear to softer sounds
at nearby frequencies. MP3 and AAC measure what sounds are present and calculate which
sounds will be masked and therefore inaudible, then skip encoding those. The result sounds
identical to the original in most listening conditions.

For video, the key insight is *temporal redundancy*: consecutive frames of video look
almost identical. Instead of encoding each frame from scratch, video codecs encode only
the *differences* from earlier frames: "this block moved 3 pixels to the right" rather
than re-encoding the entire block. The savings are enormous.

All of this rests on *rate–distortion theory*: the mathematical framework
that tells you, given a tolerable level of distortion, how many
bits you must spend. Chapters 21 and 41 cover this in detail.

#checkpoint[Can a lossless compressor always produce an output shorter than its input?][
  No. By the pigeonhole argument: there are $2^n$ possible inputs of length $n$ and only
  $2^n - 1$ outputs of length less than $n$, so at least two inputs must map to the
  same shorter output. For every file a lossless compressor shortens, there must be some
  file it leaves the same length or makes longer. In practice, already-compressed or
  truly random files often get slightly larger when run through another lossless compressor.
]

== What the Rest of This Book Looks Like

This book is long, because compression is a rich field. Here is a map.

*Volume I: Foundations* (the volume you are reading) lays the groundwork. It starts
here with the big picture, then visits the history of compression from the telegraph to
the present (Chapter 2), explains what data and information actually are (Chapter 3),
and spends several chapters building the mathematical toolkit from scratch: numbers in
binary and other bases, logic, sets and functions, exponents and logarithms, counting and
combinatorics, probability, random variables, sequences and sums, and a first look at
vectors and matrices (Chapters 4–12). Then it covers what computers do with all this
(Chapters 13–14), teaches Python programming from zero (Chapters 15–17), and arrives
at the mathematical theory of information: Shannon entropy, the source coding theorem,
channel capacity, rate–distortion theory, Kolmogorov complexity, and the deep link between
compression and learning (Chapters 18–23). This is the foundation on which everything
else stands.

*Volume II: Classical Lossless Compression* covers the canonical algorithms in depth:
Huffman, arithmetic coding, ANS, LZ77, LZ78, DEFLATE, LZMA, Zstandard, Brotli, PPM,
PAQ, the Burrows–Wheeler Transform, and the benchmarks that drive the field (Chapters 24–36).

*Volume III: Lossy and Perceptual Media Compression* covers signals and transforms,
quantization, prediction, and rate–distortion optimization in practice, then the full
story of JPEG, JPEG 2000, modern image formats, audio codecs from MP3 to Opus, and video
codecs from H.264 to AV1 (Chapters 37–55).

*Volume IV: The Neural and AI Era* covers learned compression: neural image codecs,
generative codecs, neural video, neural audio codecs used as tokenizers, the theory
of compression as intelligence, LLMs as compressors, and the compression of AI models
themselves (quantization, pruning, distillation, LoRA; Chapters 56–65).

*Volume V: Specialized Domains, Systems, and Reflections* covers scientific data,
databases, genomics, DNA data storage, delta and deduplication, error correction,
systems engineering, measuring compression, the human history of the field, the
present moment (June 2026), open problems, and where compression is heading
(Chapters 66–81).

You do not need to read linearly. If you already know probability and information theory,
you can skip Chapters 4–17 and start at Chapter 18. If you want to go straight to JPEG,
you can jump to Chapter 42 and follow the forward references back when you need them.
The book is designed so that every chapter is self-contained enough to read independently,
with clear pointers to prerequisites.

== A Sample: What Compression Looks Like in Numbers

Let's make the abstract concrete with a tiny worked example, one that fits in your head
right now, before we have covered any algorithms.

Consider a very short text message: `AABABCAABABCAABABC`. It is 18 characters long. If
we store it naively in ASCII (the standard encoding where each letter takes one byte),
we use $18 times 8 = 144$ bits.

*Observation 1: Some letters are more common than others.* Count the characters: A appears
9 times, B appears 6 times, C appears 3 times. Total: 18 characters, so A is 50% of the
message, B is 33%, C is 17%.

If we use a very short code for A, a medium code for B, and a longer code for C, we
might design:
- A → `0` (1 bit)
- B → `10` (2 bits)
- C → `110` (3 bits)

The coded message would use $9 times 1 + 6 times 2 + 3 times 3 = 9 + 12 + 9 = 30$ bits.
That is down from 144 bits to 30 bits, a 5× compression ratio. This is Huffman coding
in embryonic form.

*Observation 2: The pattern repeats.* Notice that `AABABC` repeats exactly three times.
Instead of encoding all 18 characters, we could encode `AABABC` once and then say "repeat
this twice more." Where does that get us? Spend our short codes from Observation 1 on the
six-character block `AABABC` ($1 + 1 + 2 + 1 + 2 + 3 = 10$ bits) and then add a
tiny instruction meaning "now repeat the last block two more times", which a real codec
encodes in just a few bits. Ten bits for the pattern plus two or three for the
repeat-instruction lands us around 12–13 bits for the *entire* message, versus 144 raw.
A dictionary compressor (Chapter 28) finds and exploits exactly this kind of repetition
automatically.

*Observation 3: The two approaches compose.* We can first find the repeating pattern
(dictionary step), then encode the non-repeated parts with short codes for common letters
(statistical step). This is exactly what DEFLATE, gzip, and most real compressors do.

#scoreboard(
  caption: "Chapter 1: our tiny example (18-character string AABABCAABABCAABABC)",
  [Raw ASCII], [144 bits], [1.0×], [8 bits per character, no compression],
  [Statistical coding (Huffman-like)], [30 bits], [4.8×], [A=1 bit, B=2 bits, C=3 bits],
  [Dictionary + statistical], [\~12 bits], [\~12×], [Encode pattern once, then reference],
)

In later chapters, when we apply real algorithms to real data, we will watch the
compression ratio improve as each new technique adds another layer of understanding. The
scoreboard at the end of each chapter tracks our cumulative progress.

== The Book's Contract with You

Before moving on, it is worth being explicit about what this book promises you and what it asks in return.

This book assumes exactly one thing: that you can do 9th-grade mathematics. Fractions,
basic algebra, the idea of an equation: that is all. Everything beyond that is taught
from scratch, at first use, in clearly-marked skippable boxes. The two kinds of box are:

*Go Further · The Maths boxes* (the teal-bordered boxes like the one on bits and
logarithms earlier in this chapter) introduce a mathematical concept (logarithms,
probability, entropy, vectors) from absolute scratch. Each one has a plain definition,
a tiny numeric example, and the intuition for why it matters. The first major cluster
of these appears in Chapters 4 through 12, which build the complete mathematical toolkit.
If you already know probability theory and linear algebra, you can skim them. If this is
your first encounter with these ideas, read them carefully.

*Go Further · Python boxes* (dark-blue-bordered) teach Python 3.14 programming from
zero, at first use of each language feature. The first cluster appears in Chapters 15
through 17. If you already know Python, you can skip most of them. If not, read them
and you will be writing compression algorithms by Chapter 24.

The critical design rule is this: *the main prose must make sense even if you skip every
single box.* What algorithms do, what they achieve, who built them, how they connect:
all of that is told in the main text. The boxes teach the machinery
for those who want the full picture.

In return, the book asks you to be patient. Some ideas in compression are genuinely
subtle. When we get to entropy coding, or the Burrows–Wheeler Transform, or learned
compression, the ideas take time to settle. The worked examples, checkpoints, and
exercises at the end of each chapter are there to give the ideas time to land. Use them.

== Further Reading

The primary source for the theoretical ideas in this chapter is Shannon's original paper,
freely available:

- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon, C. E. (1948). *A Mathematical Theory of Communication*. Bell System Technical Journal 27(3–4), 379–423 & 623–656.]

For an accessible and wonderful narrative account of information theory:

- Gleick, J. (2011). _The Information: A History, a Theory, a Flood._ Pantheon Books.

For the modern link between language models and compression (mentioned briefly above,
developed fully in Chapter 62):

- #link("https://arxiv.org/abs/2309.10668")[Delétang, G. et al. (2024). *Language Modeling Is Compression*. International Conference on Learning Representations (ICLR 2024).]

For the Hutter Prize:

- #link("http://prize.hutter1.net/")[Hutter, M. (2006–present). *The Hutter Prize for Lossless Compression of Human Knowledge.*]

#takeaways((
  [Compression closes the gap between "how much data exists" and "how much storage
   and bandwidth the world has." Every advance in digital technology (streaming video,
   mobile internet, genomics at scale, deployable AI) was enabled by a corresponding
   advance in compression.],
  [Lossless compression guarantees bit-for-bit reconstruction; it is mandatory for
   text, code, archives, and any data where a single changed bit matters. Lossy
   compression discards some information; it is appropriate when the intended consumer
   (a human eye or ear) cannot perceive the difference.],
  [Every compressor is a model plus a coder. The model predicts what comes next; the
   coder converts that prediction into bits. Better model = better compression. The
   whole history of compression is the history of building better models.],
  [No lossless compressor can shrink every input. For every file it shortens, it must
   lengthen some other. This is an elementary counting argument (pigeonhole), not a
   limitation that cleverness can overcome.],
  [The theoretical floor for lossless compression is Shannon entropy; for lossy, it is
   the rate–distortion function. Real algorithms are judged by how close they get to
   these limits at practical speed. The mathematical details arrive in Chapters 18–21.],
  [Throughout this book you will build tinyzip, a real compressor assembled piece by
   piece from every technique you learn. The Python scaffolding starts in Chapter 15, and
   the first full codec (Huffman) lands in Chapter 24.],
))

== Exercises

#exercise("1.1", 1)[
  You have a text file where the letter A appears 50% of the time, B appears 25%,
  C appears 12.5%, and D appears 12.5%. A simple code assigns: A → `0`, B → `10`,
  C → `110`, D → `111`. Calculate the average number of bits used per character.
  Is this better or worse than storing each character in 8-bit ASCII?
]

#solution("1.1")[
  Average bits = $0.5 times 1 + 0.25 times 2 + 0.125 times 3 + 0.125 times 3 = 0.5 + 0.5 + 0.375 + 0.375 = 1.75$ bits per character.
  ASCII uses 8 bits per character. So this simple variable-length code achieves
  $8 / 1.75 approx 4.6 times$ compression, without losing any information.
  We will prove in Chapter 24 that this particular code is actually optimal for these
  probabilities: it is a Huffman code.
]

#exercise("1.2", 1)[
  In your own words, explain why running gzip twice on the same file produces almost
  no additional compression on the second pass. Use the ideas from the section
  "Why You Cannot Compress Everything."
]

#solution("1.2")[
  After the first gzip pass, the output looks nearly random: gzip has already removed
  the statistical structure from the input. A truly random file has maximum "entropy"
  (surprise per bit) and cannot be compressed: there are no patterns to exploit.
  The second gzip pass finds essentially nothing to work with. In fact, the second pass
  may make the file very slightly larger by adding gzip's own small header overhead.
  The pigeonhole argument shows this must happen: for every file gzip shortens on a
  second pass, some other file must get longer; in practice, already-compressed files
  consistently fall into the "gets longer" category.
]

#exercise("1.3", 1)[
  A salesperson claims to have invented a compression algorithm that makes every
  file at least 10% smaller. Using the counting argument from this chapter, explain
  precisely why this claim is false.
]

#solution("1.3")[
  Consider all files of exactly 1,000 bits. There are $2^1000$ such files. The
  salesperson's algorithm would map each of them to a file of at most 900 bits.
  But there are only $2^900$ possible files of at most 900 bits, vastly fewer than
  the $2^1000$ inputs (the ratio is $2^1000 \/ 2^900 = 2^100$, which is about
  $10^30$, a 1 followed by thirty zeros).
  By the pigeonhole principle, many pairs of distinct 1,000-bit inputs would compress
  to the same 900-bit output. A lossless decompressor cannot then distinguish which
  original to restore. The claim is therefore impossible: no algorithm can losslessly
  shrink all inputs by 10%.
]

#exercise("1.4", 2)[
  Consider a file that consists of 1,000,000 zeros (the character '0', stored in ASCII
  as the byte written `0x30`; the `0x` prefix just means "this number is in base 16,
  hexadecimal," a shorthand for bytes that Chapter 4 teaches from scratch, and you do not need
  it to answer this question). Intuitively, how compressible is this file? What is the simplest
  description you could give of its contents? (No need to calculate exact numbers; just
  reason about what a clever compressor might do.)
]

#solution("1.4")[
  The file is extremely compressible. Its entire content can be described as: "one
  million copies of the byte 0x30." A run-length encoding might say something like
  [count: 1,000,000, value: 0x30], which takes on the order of 40–50 bits compared
  to the 8,000,000 bits in the raw file: a compression ratio of roughly 200,000:1.
  Highly repetitive or highly predictable data has very low entropy and can
  be compressed to a tiny fraction of its raw size. The limit, per Shannon's theory,
  depends on the entropy of the source generating such data, which, if it always
  produces zeros, is exactly zero bits per symbol.
]

#exercise("1.5", 2)[
  A photograph of a clear blue sky and a photograph of a fireworks display are stored
  as raw PNG images of the same dimensions. You want to apply JPEG compression to both.
  Which image would you expect to achieve a higher compression ratio? Which would suffer
  more visible quality loss at the same compression setting? Explain your reasoning in
  terms of the lossless/lossy concepts from this chapter.
]

#solution("1.5")[
  The clear blue sky would compress far more (achieve a higher compression ratio). The
  sky is nearly uniform in colour, a gentle gradient with little variation. There is
  little information per pixel. JPEG would represent it with very few non-zero frequency
  coefficients and could discard the high-frequency ones without visible effect.

  The fireworks photograph has sudden, bright bursts of varied colour, sharp edges,
  and fine details spread across the image. It carries much more information per pixel.
  At the same JPEG quality setting, it would be harder to compress without
  visible artifacts. If compressed to the same file size as the sky photo, the fireworks
  would likely show visible JPEG blocking and ringing around the bright edges.

  This illustrates a key principle: how well a *lossy* codec works depends on the
  statistical structure of the source, not just its pixel count.
]

#bridge[
  You now have the big picture: what compression is, why it exists, the model + coder
  architecture, the impossibility of universal compression, and the theoretical limits
  Shannon gave us. Chapter 2 will tell the human story behind these ideas, tracing an arc
  from Morse's telegraph in 1837 to the state of the art in June 2026, naming the
  milestones and the people so that every later chapter has a place to land. If you want
  to skip straight to the mathematics, Chapter 4 is where the systematic building begins.
  But Chapter 2 is a good read: the history of compression is, among other things, the
  history of brilliant ideas blocked by bad laws, bad timing, and the occasional magnificent
  stubbornness of one person who refused to believe something was impossible.
]
