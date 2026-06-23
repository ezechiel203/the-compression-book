#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= A Guided History of the Field

#epigraph[The past is never dead. It's not even past.][William Faulkner]

Imagine you are a telegraph operator in 1844. A customer hands you a message: "SEND HELP IMMEDIATELY FATHER ILL." You will charge by the word, so the customer has already compressed their panic into eleven. Now imagine you have a machine that could shrink those words further — automatically, without losing a letter. How far could you go? And who figured it out?

That question took roughly 175 years to answer, and the journey is one of the great stories in the history of ideas. This chapter is your map. We will move fast — one date, one name, one breakthrough per stop — because the goal right now is orientation, not depth. Every section you read here will expand into a full chapter later in the book. Think of this as a first viewing of a city from a helicopter: you won't know every street yet, but you'll never be lost again.

#recap[
  In Chapter 1 we established the big picture: compression is the art of finding and removing redundancy, it splits into lossless (bit-perfect) and lossy (approximate) families, and the field rests on two pillars — a mathematical model of the data and a coder that turns that model into bits. We also introduced tinyzip, the running Python project. Now we place all of that in time.
]

#objectives((
  "Describe the major milestones in compression history from telegraphy to 2026.",
  "Name the people and institutions behind each milestone.",
  "Explain, in plain terms, what each milestone changed.",
  "Place any compression algorithm you encounter later in its historical context.",
  "Identify the recurring patterns: theory first, patents second, open-source third.",
))

== Before the Bit: Telegraphy and the First Codes

Long before computers existed, humans faced the same compression problem: how do you send information over a slow, expensive channel?

=== The Telegraph and Morse Code (1837–1844)

Samuel Morse and Alfred Vail built the first practical electrical telegraph in the late 1830s. Their insight about efficiency was simple but genuine: common letters should have short codes. The letter E — the most frequent letter in English — became a single dot. The letter Z, rare in everyday prose, became dot-dot-dot-dot in early Morse, and was later swapped to the familiar dash-dash-dot-dot. Vail reportedly counted the letter-frequency distribution by visiting a printing shop and counting the type-case: more type of a letter meant it appeared more often, so it deserved a shorter code.

This is Huffman coding, two centuries early, done by hand. Vail and Morse lacked the mathematics to prove their code was optimal — that would wait for 1952 — but they had the right instinct.

#algo(
  name: "Morse Code",
  year: "1837–1844",
  authors: "Samuel Morse, Alfred Vail",
  aim: "Variable-length encoding of the Latin alphabet, digits, and punctuation for electrical telegraphy. Shorter codes for more frequent symbols.",
  complexity: "Fixed lookup table; no computation required",
  strengths: "Human-readable, robust to noise with pauses as separators, frequency-sensitive encoding",
  weaknesses: "Not uniquely decodable without inter-symbol gaps; not proved optimal; no formal model of the source",
  superseded: "Huffman coding (1952) for digital systems; Morse still used in amateur radio",
)[
  Morse is the world's first deployed variable-length code and the clearest proof that the core idea of compression — assign short codewords to common symbols — predates the computer by a century. It also illustrates why informal intuition, though powerful, is not enough: it took until 1952 to prove that the greedy approach is provably optimal, and until 1948 to even define what "optimal" means.
]

=== Shorthand and Pre-Digital Compression

Stenography systems like Pitman shorthand (1837) and Gregg shorthand (1888) replaced common English words and sounds with compact pen strokes. They achieved real compression ratios: a skilled stenographer using Pitman could record speech at 200 words per minute, far faster than longhand. The principle, again, was the same: shorter notation for more common utterances.

Neither telegraphy nor shorthand had a theory behind them. They were engineering achievements guided by intuition. Theory would arrive in 1948 in a paper that changed everything.

#checkpoint[Why did Morse give E a one-dot code rather than a one-dash code?][Both dot and dash are single symbols; the choice was partly convention. What mattered was that E got the *shortest* possible code (one element) because it is the most frequent letter in English. Vail determined frequency by counting typeface counts at a print shop.]

== The Founding Year: Shannon 1948

On July 12, 1948, the Bell System Technical Journal published Part I of a paper called "A Mathematical Theory of Communication" by Claude Elwood Shannon, a 32-year-old mathematician at Bell Telephone Laboratories in New Jersey. Part II followed in October. The two parts together are arguably the most important scientific paper of the twentieth century for information technology.

Shannon had been thinking since the early 1940s. During World War II he worked on cryptography — the science of hiding information — and realized that hiding information and compressing it were deeply related: both involve removing predictable patterns. He was also influenced by earlier quantitative work from Nyquist (1924) and Hartley (1928) at Bell Labs, who had studied how much information a telegraph channel could carry.

Shannon's breakthrough was to refuse to care about meaning. To him, a message was simply a sequence of symbols drawn at random from some probability distribution. The right measure of how much information it contained, he argued, was how much it *surprised* you. A common event carries little information (you already expected it); a rare event carries a lot. He turned this intuition into a formula and called the resulting quantity *entropy*, borrowing the word from thermodynamics.

#gomaths("What entropy measures")[
  This box previews two pieces of notation — the logarithm $log_2$ and the sum symbol $sum$ — that we build from scratch later (logarithms in Chapter 7, sums in Chapter 11). You can skip every box like this and the main story still reads cleanly. But here is just enough to follow along.

  A *probability* $p$ is a number between 0 and 1 saying how likely something is: a fair coin lands heads with probability $p = 0.5$, a fair die shows a 3 with probability $p = 1\/6 approx 0.167$. (We build probability properly in Chapter 9.)

  The *base-2 logarithm* $log_2(x)$ answers one question: "$2$ to what power gives $x$?" So $log_2(2) = 1$ (because $2^1 = 2$), $log_2(8) = 3$ (because $2^3 = 8$), and $log_2(1) = 0$ (because $2^0 = 1$). It is the natural way to count bits, because each extra bit doubles how many things you can name.

  Now the idea. Imagine a coin. If it is fair (50% heads, 50% tails), each flip surprises you a lot — you have no idea what's coming. If it is a trick coin that always lands heads, each flip surprises you not at all.

  Shannon measured the surprise of a single event with probability $p$ as:

  $ i = log_2(1 / p) "bits" $

  A fair coin flip: $log_2(1\/0.5) = log_2(2) = 1$ bit. A certainty ($p = 1$): $log_2(1) = 0$ bits. A one-in-eight chance: $log_2(8) = 3$ bits. Notice the pattern: the rarer the event (smaller $p$), the bigger the surprise.

  *Entropy* $H$ is the average surprise over all possible outcomes. The big Greek letter $sum$ ("sigma") just means "add up the following over every outcome $i$":

  $ H = -sum_i p_i log_2 p_i $

  Read aloud: "for each outcome $i$, multiply its probability $p_i$ by its surprise $log_2(1\/p_i)$, then add them all together." For a fair coin (two outcomes, each $p = 0.5$): $H = -(0.5 log_2 0.5 + 0.5 log_2 0.5) = 1$ bit. For a coin that shows heads 99% of the time: $H approx 0.08$ bits — almost no uncertainty.

  The key takeaway: entropy tells you, in bits, *how unpredictable* a source is. It is the theoretical minimum number of bits you need per symbol to describe the source losslessly. You will encounter this formula constantly throughout the book; Chapter 18 derives it carefully from first principles.
]

Shannon's source coding theorem (proved in the same 1948 paper) made entropy useful: it said that the average number of bits per symbol in any lossless code must be at least $H$ bits, and you can get as close to $H$ as you like by coding long enough sequences together. This set compression's fundamental limit. It also defined *redundancy* — the gap between what you use and what $H$ says you need — as exactly the thing to eliminate.

#keyidea[
  Shannon entropy $H$ is compression's speed of light: an absolute lower bound you can approach but never beat (for a fixed probabilistic model of the data). Every lossless compressor in this book is, in essence, an attempt to close the gap between its actual bit rate and $H$.
]

Shannon also sketched, in 1948, the idea of *lossy* compression: if you allow some error, you can go even lower. He formalized this as *rate–distortion theory* in a 1959 paper, which gave us the theoretical basis for JPEG, MP3, and everything in between.

#history[
  Shannon credits some intellectual debt to Harry Nyquist's 1924 paper "Certain Factors Affecting Telegraph Speed" and Ralph Hartley's 1928 "Transmission of Information." Hartley's formula $I = n log_2 s$ (for $n$ symbols from an alphabet of size $s$) was the precursor to entropy, but without probability — Hartley assumed all messages were equally likely. Shannon's leap was to weight by probability, which made the theory both more general and more powerful. Shannon himself said he chose the name "entropy" because John von Neumann told him: "Call it entropy — no one knows what entropy really is, so in a debate you will always have the advantage."
]

== The First Algorithms: Huffman vs. Shannon (1948–1952)

Shannon's 1948 paper contained not just the theory but also a practical code: the *Shannon–Fano* code, which Shannon developed with Robert Fano. The idea was to sort symbols by frequency and divide the list repeatedly in half, assigning 0 to one half and 1 to the other. It worked, and it was close to optimal — but not quite.

In 1951, Robert Fano taught an information theory course at MIT. For the final exam, students could either take a traditional test or work on an open problem. David Huffman, a doctoral student, chose the open problem: find the optimal prefix code. The rest of the class worked on improving Shannon–Fano; Huffman started fresh. After months of failing to prove that any known approach was optimal, he was about to give up when, late one night, the greedy solution came to him: always merge the two least-probable symbols first.

He went to Fano the next morning. Fano's own approach — which he had been working on for years — was demonstrably suboptimal. The student had beaten the professor. Huffman's paper, "A Method for the Construction of Minimum-Redundancy Codes," appeared in the Proceedings of the IRE in September 1952.

#aside[
  Huffman later said he might never have found the solution if he hadn't been under the pressure of a deadline. He was a humble man who rarely lectured on his discovery, preferring to let others teach it. When colleagues urged him to file a patent — which would have given him substantial royalties, since Huffman codes went on to appear in virtually every compressor ever built — he declined, preferring that the discovery remain freely available to all.
]

Huffman coding is the subject of Chapter 24. For now the punchline is: it produces a code where the most common symbols get the fewest bits, and it is provably optimal among all *prefix codes* (codes where no codeword is a prefix of another). The algorithm runs in what computer scientists write as $O(n log n)$ time — a shorthand (taught from scratch in Chapter 14) meaning the work grows just a little faster than the size $n$ of the input, i.e. it is fast and practical. Its weakness — that it must know the probabilities in advance and that fractional bits are wasted when $log_2 (1\/p)$ is not an integer — would motivate the arithmetic coding work of the 1970s.

== Redundancy in Practice: The 1950s–1970s

Shannon had provided the theory. The 1950s and 1960s were a quiet period: computers were rare, expensive, and slow, and the data-compression problem felt theoretical. But two ideas were developing in parallel.

=== Run-Length Encoding

The simplest idea that actually works: if the same symbol appears many times in a row, say the number of repetitions rather than the symbol itself. A sequence like AAAAAAAABBBB becomes "8A4B." This is *run-length encoding* (RLE), and it was in practical use from the earliest days of fax machines and computer graphics. The CCITT Group 3 fax standard (1980) is built on RLE: a scanned black-and-white page is mostly white, so runs of white pixels compress enormously.

RLE appears inside many later systems — bzip2 uses it, JPEG uses a variant for runs of zero coefficients — and it will reappear throughout the book. It is always the baseline, the simplest possible thing that removes repetition.

=== Arithmetic Coding: The Idea (1960s–1970s)

Huffman coding's flaw is that it must assign a whole number of bits to each symbol. If a symbol has probability 0.999, Huffman must give it at least 1 bit, when the information content is only $-log_2(0.999) approx 0.0014$ bits — a factor of 700× waste. The fix is to code the *entire message* as a single number in the interval $[0, 1)$, choosing a sub-interval for each symbol proportional to its probability.

This idea was floating around in the 1960s. Peter Elias at MIT described it informally around 1963 (without publishing). Independently, Jorma Rissanen and Richard Pasco at IBM Research published practical finite-precision implementations in 1976. Ian Witten, Radford Neal, and John Cleary published the landmark practical implementation in the *Communications of the ACM* in 1987, the version most textbooks describe.

The arithmetic coding story is threaded with patent drama that will occupy a full chapter (Chapter 26). The short version: IBM and others filed patents on arithmetic coding variants throughout the 1980s and early 1990s, which led the bzip2 author (Julian Seward) to deliberately avoid it in 1996 by using Huffman instead. The patents lapsed around 2007, by which point the ecosystem had mostly moved on. Then in 2022, Microsoft filed a new patent on a variant of ANS — a story we reach in a moment.

== The Dictionary Revolution: Ziv and Lempel (1977–1978)

In 1977, Abraham Lempel and Jacob Ziv at the Technion in Israel published "A Universal Algorithm for Sequential Data Compression" in *IEEE Transactions on Information Theory*. In 1978 they published a follow-up. The two papers are universally called LZ77 and LZ78.

Their insight was fundamentally different from everything before it. Huffman and arithmetic coding are *statistical* methods: they exploit the frequency of individual symbols. Ziv and Lempel proposed *dictionary* methods: look for repeated *strings* — sequences of symbols that appeared earlier in the data — and encode them as references to those previous occurrences. The first time you see the word "compression" in a document you must spell it out; the second time you can write "go back 47 characters and copy the next 11."

This does not require knowing any probabilities in advance. It discovers structure in the data *during* compression, building a dictionary on the fly. And Ziv and Lempel proved something remarkable: their algorithm is *universally optimal* — it converges to the true entropy rate of any stationary ergodic source as the block length grows, without any prior knowledge of the source. This was not just a clever hack; it was a theoretically grounded breakthrough.

#gomaths("What 'universal' means in compression")[
  A compression algorithm is *universal* if it achieves the entropy rate $H$ of any source in the limit of long blocks, without being told the source's statistics in advance. (A *source* here just means whatever is producing the data — a person typing English, a camera, a sensor. We treat it as a machine that emits symbols according to some fixed but unknown probabilities; Chapters 9 and 18 make this precise.) In contrast, Huffman coding is *optimal* for a known distribution but must be given the frequencies; it is not universal in the strong sense.

  Ziv and Lempel showed LZ77/78 achieve universality by proving that the number of distinct phrases the algorithm produces grows at the right rate relative to $H$. This is a deep result — it says that even a completely unknown source can eventually be compressed to its theoretical limit just by observing it long enough. Chapter 28 proves a simplified version.
]

LZ77's immediate practical descendant was *LZSS* (Storer and Szymanski, 1982), which refined the encoding of matches and literals. Then in 1984, Terry Welch at Sperry Corporation published *LZW* (Lempel–Ziv–Welch), which simplified LZ78 by building the dictionary automatically without explicit length/distance codes. LZW became the engine of the Unix `compress` command and, fatefully, the CompuServe GIF format (1987).

== The Patent Wars Begin: GIF, PNG, and the Open-Source Response (1985–2000)

The GIF story is one of the great cautionary tales of the field. CompuServe's Graphics Interchange Format (1987) used LZW compression. LZW was patented by Sperry (later Unisys) in December 1985 as US Patent 4,558,302. For years nobody paid much attention. Then in December 1994 — just as the World Wide Web was exploding and GIF was becoming the default image format — Unisys announced it would enforce the patent and demand royalties from software that used GIF.

The internet was furious. The reaction was immediate and creative: the community designed *PNG* (Portable Network Graphics), a patent-free alternative. PNG uses *DEFLATE* compression (explained in a moment), not LZW, and adds prediction filters before compression (guessing each pixel from its neighbors reduces the residual entropy). PNG was released in 1996 and is now the standard lossless format for the web.

The GIF episode established a template that recurred with MP3, H.264, HEVC, and arithmetic coding: a patent on a compression algorithm that achieves wide adoption gets enforced, triggering a royalty-free alternative backed by the open-source community and large technology companies. Chapter 29 covers LZW and its patent saga; Chapter 44 covers GIF and PNG.

#misconception[
  "Open-source codecs are always worse than patented ones."
][
  Not so. PNG matches or beats GIF on every dimension: better compression, alpha transparency (transparency through GIF was a hack), no patent risk. AV1 and HEVC are comparable in quality. Opus outperforms MP3 at equivalent bitrates. The royalty-free codec is sometimes *better* precisely because a broader engineering community can improve it freely.
]

== DEFLATE: The Most Deployed Algorithm in History (1991–1996)

Phil Katz designed DEFLATE for PKZIP 2.0 in 1991. DEFLATE combines LZ77 dictionary coding with Huffman coding for the output symbols. It became the compression layer inside gzip, zlib, ZIP, PNG, and HTTP 1.1 content-encoding. The RFC (1951, 1996) documented it, and it propagated everywhere.

Katz's life is a genuinely sad story. He reverse-engineered the dominant PKware format, fought a lawsuit, eventually settled and standardized the format, but struggled with alcoholism and died alone in a Wisconsin motel room in April 2000 at age 37. The algorithm he designed for a commercial dispute became, arguably, the most ubiquitous data structure on the internet.

DEFLATE's design is beautiful in its simplicity: LZ77 finds repeated strings and replaces them with (distance, length) pairs; Huffman coding encodes those pairs and the remaining literal bytes. The combination squeezes both repetition (dictionary) and frequency skew (entropy coding). Chapter 30 dissects it completely.

#keyidea[
  DEFLATE = LZ77 (repeated-string matching) + Huffman (frequency-sensitive symbol coding). This two-layer structure — a model that finds structure, followed by an entropy coder that converts that structure into minimal bits — is the template for almost every compressor you will meet.
]

== The Lossless Golden Age: BWT, PPM, and the Ratio Champions (1990–2006)

The 1990s were a golden era for lossless compression research, driven by cheap storage, the internet, and competitive benchmarks.

=== Burrows–Wheeler Transform (1994)

Michael Burrows and David Wheeler at DEC's Systems Research Center in Palo Alto published "A Block-Sorting Lossless Data Compression Algorithm" in 1994 as a technical report (DEC SRC Research Report 124 — they never formally submitted it to a journal). The transform it describes is now called the BWT.

The BWT is not a compressor by itself. It is a *sorting* transform: it rearranges the bytes of a block so that similar contexts cluster together. The intuition: in English the letter just *before* "he" is very often "t" (from the word "the"), so if you sort the text by the context that follows each letter, all those t's get swept into the same neighbourhood. After the BWT, long runs of the same character appear that did not exist in the original — a stretch of `ttttt` where the text was full of "the". Those runs are then easy to compress with a simple coder such as run-length encoding followed by an entropy coder. Julian Seward used the BWT as the heart of *bzip2*, released July 18, 1996 — the same month as PNG. bzip2 achieves meaningfully better compression than gzip at the cost of slower speed and more memory. Chapter 35 covers it in full.

The BWT had a second life beginning around 2000, when Ferragina and Manzini discovered it could be turned into a *compressed self-index* (the FM-index): a data structure that stores the data in compressed form and allows substring searches without decompression. This became the foundation of modern DNA read aligners — essentially every genome sequencer on the planet uses a BWT-based data structure. Chapter 35 covers that connection too.

=== Prediction by Partial Matching: PPM (1984–2000)

John Cleary and Ian Witten proposed *Prediction by Partial Matching* (PPM) in 1984. The idea: maintain a statistical model that predicts the next symbol given the last $k$ symbols (the *context*). When the high-order context has seen the next symbol before, use that (very sharp) prediction; when it hasn't, fall back to shorter contexts. The entropy coder then codes the actual symbol with the predicted probability. This kind of context-dependent modeling achieves compression ratios that dictionary methods can't match on text.

PPM was refined throughout the 1990s by Alistair Moffat (PPMC, 1990) and Dmitry Shkarin (PPMd, 2002), and it remained the state of the art for text compression well into the 2000s. It is the direct intellectual ancestor of large language models viewed as compressors — the theme we will reach in Chapter 23.

=== Context Mixing and the PAQ Family (2002–present)

Matt Mahoney at Florida Institute of Technology published "Fast Text Compression with Neural Networks" at the AAAI FLAIRS conference in 2000, introducing the idea of *context mixing*: instead of picking one best model, blend many models' predictions together. In 2002 he released PAQ1, the first of the PAQ family. The PAQ models blend dozens of contexts, a small neural network, and various pattern detectors — all weighted by their recent accuracy.

The PAQ family and its descendants (PAQ8, ZPAQ, cmix) sit at the extreme end of the compression/speed trade-off: they achieve the best lossless compression ratios ever recorded on standard benchmarks, but they are orders of magnitude slower than practical tools and require gigabytes of memory. In 2023, Saurabh Kumar's fast-cmix won the Hutter Prize. In 2024, Kaido Orav's fx-cmix and then fx2-cmix (with Byron Knoll) set the current enwik9 record: 110,793,128 bytes (compared to 1,000,000,000 bytes uncompressed — a ratio of roughly 9:1 on Wikipedia text). Chapters 33 and 34 cover PPM and context mixing in depth.

=== The Hutter Prize (2006)

Marcus Hutter, a researcher at IDSIA in Switzerland, founded the *Hutter Prize* in 2006 as a public competition for lossless compression of a 100 MB excerpt of Wikipedia (enwik8). The prize was motivated by his AIXI theory, which frames general intelligence as compression. The tagline: "50,000 euros to compress human knowledge."

The prize was later expanded to 500,000 euros and enwik9 (one billion bytes of Wikipedia) in 2020. It remains active as of June 2026. Chapter 36 covers benchmarks, corpora, and the Hutter Prize.

#gopython("Measuring compression ratio in Python")[
  These code boxes are a taste of what is coming; we teach Python from absolute zero in Chapters 15–17, so you never need to understand the syntax yet — skip it freely. For the curious: `def ratio(...)` names a reusable recipe (a *function*); the words after the colons (`int`, `-> float`) are just labels noting that the inputs are whole numbers and the answer is a decimal.

  Throughout this book we will compute compression ratios. The simplest measurement in Python:

  ```python
  def ratio(original_bytes: int, compressed_bytes: int) -> float:
      """Return bits per byte (lower is better)."""
      return (compressed_bytes * 8) / original_bytes

  # Example: a 1000-byte file compressed to 400 bytes
  print(ratio(1000, 400))   # 3.2 bits per byte
  print(ratio(1000, 1000))  # 8.0 bits per byte (no compression)
  ```

  A ratio of 8.0 means no compression (8 bits = 1 byte). A ratio of 4.0 means the file shrank to half. Perfect compression of random bytes is impossible: it would require negative information.

  We will expand this into a full benchmarking harness in Chapter 36.
]

== The Audio Revolution: From PCM to MP3 (1974–1999)

While lossless compression matured, a parallel revolution was happening in *lossy* compression for audio. The key insight was psychoacoustics: the human ear does not hear all sounds equally. Sounds that are quiet, very high-pitched, or masked by louder simultaneous sounds can be thrown away entirely — and if they are, the listener won't notice.

The mathematical tools came first. In 1974, Nasir Ahmed, T. Natarajan, and K.R. Rao published the *Discrete Cosine Transform* (DCT) in *IEEE Transactions on Computers*. The DCT converts a block of signal samples into frequency coefficients, concentrating most of the signal energy in a few low-frequency terms. This makes it easy to discard the high-frequency, low-energy components that ears (and eyes) are insensitive to.

Karlheinz Brandenburg began his doctoral work on perceptual audio coding at the University of Erlangen-Nuremberg in 1977. Over more than a decade, Brandenburg and his colleagues developed the psychoacoustic model that would become MPEG Audio Layer III — MP3. The standard was finalized as ISO/IEC 11172-3 in 1993. The file extension .mp3 was chosen in a Fraunhofer IIS internal poll in July 1995.

In September 1998, Fraunhofer and Thomson began enforcing their MP3 patent portfolio, demanding royalties from software companies. This triggered the royalty-free audio codec movement. The Xiph.Org Foundation developed *Ogg Vorbis* (frozen in 2000), a free MDCT-based codec. The last significant US MP3 patents expired in April 2017, and Fraunhofer terminated its licensing program the same month.

MP3 changed the world in a way that is hard to overstate. The music industry, peer-to-peer file sharing (Napster launched 1999), and ultimately the entire streaming economy trace back to that compression algorithm. Chapter 47 covers the technical story; Chapter 77 covers the patent politics.

== The Image Wars: JPEG, JPEG 2000, and the Web (1992–2006)

For images, the story begins with *JPEG*, standardized in 1992 as ISO/IEC 10918-1 / ITU-T T.81. JPEG uses the DCT on 8×8 pixel blocks, quantizes the frequency coefficients (discarding small values), and then entropy-codes the result with Huffman coding. It achieved compression ratios of 10:1 to 20:1 on photographs with acceptable quality — a revolution for distributing images on the early internet.

JPEG's weaknesses were obvious: blocking artifacts (that characteristic pixelated look at high compression), and no alpha transparency. The successor, *JPEG 2000* (ISO 15444-1, 2000/2001), replaced the block DCT with wavelet transforms, achieving better quality and scalability — you can decode any resolution from the same file. It is genuinely superior to JPEG on almost every technical measure. Yet by 2006 it had essentially failed to achieve consumer adoption. The reasons were a mix: it was slower to decode, required more memory, had its own patent uncertainties, and the web had already standardized on JPEG. Technical superiority is not sufficient; adoption dynamics matter. JPEG 2000 did find success in cinema (the DCI standard) and medical imaging, where its advantages outweigh the costs. Chapter 43 covers this story in full.

== Video Compression: The Hybrid Codec Template (1988–2013)

Video compression is image compression with time added: most of the redundancy is between consecutive frames, not within a single frame. The *motion compensation* idea — predict each block of pixels from where it came in the previous frame, then code only the residual error — was established in the ITU-T H.261 standard in 1988.

The hybrid macroblock + motion compensation + DCT + entropy coding template proved durable. It became:

- *MPEG-1* (1992): DVD quality, the basis of Video-CD
- *MPEG-2 / H.262* (1994–1995): DVD and digital television, still in use today
- *H.264/AVC* (2003): The Joint Video Team's landmark standard, roughly 2× better than MPEG-2, now the dominant codec for streaming, recording, and video calls
- *H.265/HEVC* (2013): Another ~50% improvement over H.264, but immediately mired in patent-pool fragmentation that slowed adoption

Each generation roughly doubled efficiency. Each also generated substantial patent royalties. Chapters 51–55 cover the full video story.

#fig(
  [The efficiency ladder: each major video codec improved by roughly 35–50% over its predecessor.],
  cetz.canvas({
    import cetz.draw: *

    let codecs = ("H.261\n(1988)", "MPEG-2\n(1995)", "H.264\n(2003)", "HEVC\n(2013)", "AV1\n(2018)", "VVC\n(2020)")
    let heights = (1.0, 2.0, 4.0, 6.0, 8.5, 11.0)

    set-style(stroke: (paint: rgb("#0b5394"), thickness: 0.8pt))

    for (i, h) in heights.enumerate() {
      let x = i * 1.85
      rect((x, 0), (x + 1.3, h * 0.5),
        fill: rgb("#0b5394").lighten(if i == 0 { 10% } else if i == 5 { 70% } else if i == 1 { 40% } else if i == 2 { 50% } else if i == 3 { 55% } else { 60% }),
        stroke: (paint: rgb("#0b5394"), thickness: 0.5pt))
      content((x + 0.65, h * 0.5 + 0.25),
        text(size: 6pt, fill: rgb("#1a1a1a"))[#codecs.at(i)])
    }

    line((0, 0), (11.5, 0), stroke: (paint: rgb("#1a1a1a"), thickness: 0.7pt))
    content((5.75, -0.4), text(size: 7.5pt)[Compression efficiency (higher bar = better ratio)])
  })
)

== The Royalty-Free Movement: VP8, AV1, and the Alliance for Open Media (2010–2020)

The H.265/HEVC patent debacle — three competing patent pools with incompatible terms, making licensing a legal nightmare — created the political conditions for the most significant industry alliance in compression history.

Google had acquired On2 Technologies in February 2010 for approximately \$124.6 million, gaining control of the VP8 video codec. They released it as royalty-free in May 2010 under the WebM project. VP8 was the basis for WebP, a royalty-free image format. VP9 (2013) improved further.

In September 2015, Amazon, Apple, ARM, Cisco, Google, Intel, Microsoft, Mozilla, Netflix, NVIDIA, and Samsung formed the *Alliance for Open Media* (AOMedia) to develop a truly open, royalty-free video codec. The result was *AV1*, released in 2018. AV1 achieves roughly 30% better compression than HEVC and is available royalty-free. YouTube, Netflix, Twitch, and most major streaming platforms now use AV1. Hardware decoder support arrived in consumer products by 2020–2022.

The parallel in images: *AVIF* (AV1 Image File Format), specified in 2019, gained Chrome support in 2020 and Firefox support in 2021. And *JPEG XL* — a next-generation format merging Google's PIK codec and Cloudinary's FUIF — was finalized as ISO/IEC 18181 in 2021–2022. JPEG XL's Chrome story has its own drama: Google added it in 2021, removed it in Chrome 110 (2023) citing weak ecosystem interest, then re-added it in Chrome 145 (February 2026) via a memory-safe Rust decoder called jxl-rs. Chapter 45 covers the modern image format wars.

== ANS: The Entropy Coding Revolution (2007–2015)

By 2007, entropy coding had two main options: Huffman (fast but slightly suboptimal) and arithmetic coding (optimal but patented and slower). A Polish mathematician, Jarek Duda, changed this.

Duda's idea, developed between 2007 and 2013, is called *Asymmetric Numeral Systems* (ANS). The insight is to think of compression as encoding into a numeral system where the "base" is not fixed (like base 10 or base 2) but varies symbol by symbol according to the source probabilities. Encoding becomes: multiply the current state by a scaling factor and add the symbol. Decoding reverses this. The result is a coder that matches arithmetic coding in compression ratio while running at speeds close to Huffman — because the decode operation is a simple lookup or arithmetic step with no interval bisection.

ANS comes in two flavors: *rANS* (range ANS, a streaming mode) and *tANS* (table ANS, a finite-state machine). Yann Collet independently implemented and popularized rANS in Zstandard (2016). tANS is the foundation of the Huffman-replacement in zstd's ANS entropy coder. Apple used ANS in their LZFSE codec (2015). JPEG XL uses ANS. VVC/H.266 uses a variant. It is now the entropy coder of choice whenever the highest performance matters.

The patent story has a coda: in 2022, Microsoft filed a patent on an rANS modification, despite Duda having published ANS in 2009 as open prior art and explicitly placing it in the public domain. The compression community was outraged; the patent status as of mid-2026 remains contested. Chapter 27 covers ANS technically; Chapter 77 covers the patent politics.

== The Modern General-Purpose Landscape: zstd, Brotli, LZ4 (2011–2020)

The 2010s saw an explosion of general-purpose compressors occupying different points on the speed/ratio trade-off curve.

*LZ4* (Yann Collet, 2011): extreme speed. LZ4 prioritizes decode throughput above everything; it is faster than memory bandwidth on modern CPUs. Used in Linux kernel drivers, ZFS, and anywhere latency matters more than ratio.

*Snappy* (Google, 2011): similar philosophy to LZ4. Used inside Google's internal infrastructure and BigTable.

*Brotli* (Google, Alakuijala and Szabadka, 2015; RFC 7932 in 2016): designed for HTTP content-encoding. Uses a static dictionary of common web content (HTML tags, JavaScript keywords), LZ77, and context modeling. Better ratio than gzip on web content; now supported natively in all browsers.

*Zstandard / zstd* (Yann Collet at Facebook, v1.0 August 31, 2016; RFC 8478/8878): the synthesis. zstd uses LZ77 matching, context-based literal coding, and ANS entropy coding. It is tunable across 22 compression levels, supports trained dictionaries (dramatically improving ratio on small files), and includes long-distance matching for archive use. In 2017 it entered the Linux kernel (4.14) for btrfs, squashfs, and kernel module compression. In 2024, zstd 1.5.6 added native Zstandard content-encoding to Chrome 123 and Firefox 126. zstd has effectively won the general-purpose lossless crown: it is faster and better than gzip in almost all situations. Chapter 32 covers the full landscape.

== The Neural Era: Learned Compression (2016–present)

By 2016, deep learning had transformed computer vision and natural language processing. It was only a matter of time before researchers asked: can a neural network learn a better compressor?

=== Learned Image Compression (2016–2020)

Johannes Ballé, Valero Laparra, and Eero Simoncelli at NYU published "End-to-End Optimized Image Compression" at ICLR 2017, introducing the key framework: an *autoencoder* neural network (encoder–bottleneck–decoder) trained to minimize a rate-distortion objective. The encoder maps an image to a compact latent representation; the decoder reconstructs it; the loss function balances reconstruction quality against the bit cost of the latent.

The 2018 follow-up (Ballé et al., "Variational Image Compression with a Scale Hyperprior") added a second level of compression (the hyperprior) to model correlations in the latent space. Minnen, Ballé, and Toderici (NeurIPS 2018) added an autoregressive context model. By 2020–2021, these learned codecs achieved better PSNR and MS-SSIM than JPEG and AVIF at the same bitrate on standard benchmarks. Chapter 57 covers this in depth.

=== Generative Compression (2020–2026)

The next step was to stop optimizing for PSNR (which is not a perceptual metric) and instead train the decoder to produce *visually realistic* outputs even if they differ from the original. HiFiC (Mentzer et al., NeurIPS 2020) used a GAN loss to produce images rated subjectively better than traditional codecs at *half the bitrate*. The 2024–2026 period saw one-step diffusion codecs (StableCodec, OneDC) operating at 0.01 bits per pixel — roughly 100× below JPEG's minimum practical range — with outputs that look like plausible photographs even though they are not faithful reconstructions. The philosophical questions this raises (you are receiving a generated approximation, not your original photo) are taken up in Chapter 58.

=== LLMs as Compressors (2023–2026)

The deepest theoretical connection came in a 2023 paper (presented at ICLR 2024) from Grégoire Delétang, Jordi Grau-Moya, and colleagues at Google DeepMind: "Language Modeling Is Compression." They showed that a 70-billion-parameter language model (Chinchilla), paired with an arithmetic coder, outperforms domain-specific compressors on their own territory: it compressed LibriSpeech audio to 16.4% (versus FLAC's 30.3%) and ImageNet image patches to 43.4% (versus PNG's 58.5%), despite being trained only on text.

This is not magic; it is the prediction–compression equivalence from Chapter 23 made visible at scale. Any model that assigns good probabilities to its input can be used as a compressor. A large language model is a very good next-token predictor, so it is, by construction, a very good compressor. The implication runs both ways: compression ratio on a standard corpus is increasingly used as a benchmark for model quality, because a model that compresses well must understand the data's structure. Chapter 62 builds a working demonstration.

#keyidea[
  The compression = prediction equivalence (Chapter 23) is the theoretical skeleton on which the neural era hangs. Every advance from learned codecs to LLM-as-compressor is an instance of the same principle: a better probabilistic model of the data produces a better compressor.
]

== The Specialized Frontiers (2000–2026)

While the main compression story was advancing, parallel revolutions were happening in specialized domains.

*Genomics.* The BWT FM-index became the basis for DNA read alignment tools (Bowtie, BWA) from 2009 onward. As genome sequencing costs collapsed from \$100 million per genome in 2001 to under \$100 by 2024, the data volume became a genuine storage crisis. The CRAM format (2011, updated to 3.1 in 2022) achieves reference-based compression of sequencing reads, reducing storage by 60–75% compared to uncompressed BAM files. Chapter 69 covers genomic compression.

*Time series.* Facebook's Gorilla system (2015, VLDB) introduced XOR-based float compression and delta-of-delta timestamp encoding for their internal monitoring data, achieving 12× compression of time-series metrics. This became the basis of the Prometheus and InfluxDB time-series databases. Chapter 68 covers time-series compression.

*Floating-point arrays.* Scientific computing generates enormous arrays of floating-point numbers (climate models, particle physics simulations, fluid dynamics). Peter Lindstrom at Lawrence Livermore National Laboratory introduced *zfp* in 2014, an error-bounded floating-point compressor that guarantees the error in each value is below a user-specified threshold. Chapter 66 covers scientific data compression.

*Model compression.* As deep learning models grew to hundreds of billions of parameters, compressing the models themselves became critical. Weight quantization (using 8-bit or 4-bit integers instead of 32-bit floats), pruning, knowledge distillation, and low-rank factorization are now standard tools for deploying models on limited hardware. BitNet b1.58 (2024) showed that large language models could be trained natively with ternary weights (each weight is minus-one, zero, or plus-one), storing only about 1.58 bits per weight — since $log_2 3 approx 1.58$. Chapters 63 and 64 cover model compression.

*DNA data storage.* Yaniv Erlich and Dina Zielinski demonstrated in 2017 (Science) that DNA molecules could store approximately 215 petabytes per gram, using fountain codes for error tolerance. This speculative but genuine long-term storage medium imposes new constraints on compression (GC content balance, avoiding long homopolymer runs) that are unlike any electronic medium. Chapter 70 covers DNA storage.

== The Current Moment: June 2026

As of June 2026, compression is simultaneously mature and in ferment.

*What is deployed everywhere:* zstd for general data, DEFLATE/gzip for HTTP (with Brotli and zstd gaining fast), H.264/AVC for video (still the most-watched codec on earth), HEVC for streaming (despite its patent history), AV1 gaining ground on streaming platforms, Opus for audio in WebRTC and VoIP, AVIF and JPEG XL competing as next-generation image formats.

*What is emerging:* Learned image codecs surpassing AVIF on quality metrics but not yet standardized or hardware-accelerated. Neural audio codecs (SoundStream, EnCodec, DAC) serving as tokenizers for audio language models. LLM-as-compressor demonstrations with state-of-the-art ratios but impractical decode speed. ANS-based entropy coders in nearly every modern codec. BitNet and sub-2-bit model quantization pushing LLMs toward memory-constrained devices.

*What is on the horizon:* H.267/NNVC neural video codecs (JVET target ~2028). Semantic compression — encoding not the signal but its *meaning* — emerging as a research direction for wireless machine-to-machine communication. Compression rate as a measure of LLM capability becoming increasingly mainstream as a benchmark. The AV2 codec from AOMedia (late 2025) targeting ~30% improvement over AV1.

The field has always been a dialogue between mathematics and engineering, between theory and patents, between the ideal compressor (Kolmogorov complexity — uncomputable) and the practical one (zstd — fast, good, free). That dialogue continues.

#checkpoint[
  Which three eras does compression history divide into most naturally?
][
  (1) Pre-theory: Morse, shorthand, RLE — intuition-driven, before 1948. (2) Classical theory and algorithms: Shannon 1948 through the LZ family, Huffman, JPEG, DEFLATE — mathematics-guided, roughly 1948–2015. (3) Neural era: learned codecs, LLM-as-compressor, generative compression — data-driven, 2016–present. The boundaries are fuzzy; PPM and context mixing straddle eras 2 and 3.
]

#gopython("Counting words in a text — a first step toward compression")[
  Understanding a source's statistics is the first step to compressing it. Here is a minimal Python 3.14 word-frequency counter — a very distant ancestor of a compression model:

  ```python
  def word_frequencies(text: str) -> dict[str, int]:
      """Count how often each word appears in text."""
      counts: dict[str, int] = {}
      for word in text.lower().split():
          counts[word] = counts.get(word, 0) + 1
      return counts

  sample = "to be or not to be that is the question"
  freq = word_frequencies(sample)

  # Sort by frequency, most common first
  for word, count in sorted(freq.items(), key=lambda pair: -pair[1]):
      print(f"{count:3d}  {word}")
  ```

  Running this on the sample gives "be" and "to" as the most common (2 each). A Huffman coder would assign them the shortest codes. A real compression model would track letter and byte frequencies, not word frequencies, but the principle is identical. We build this up fully starting in Chapter 24.
]

#takeaways((
  "Morse code (1844) anticipated Huffman coding by 108 years: shorter codes for more common symbols.",
  "Shannon's 1948 paper defined entropy as the theoretical minimum bits per symbol and proved it is achievable — compression's speed-of-light limit.",
  "Huffman (1952) gave the first provably optimal prefix code; arithmetic coding (1976–1987) escaped the integer-bits constraint to reach entropy exactly.",
  "Ziv and Lempel (1977–1978) proved that dictionary methods are universally optimal — no prior knowledge of the source needed.",
  "DEFLATE (1991) combined LZ77 + Huffman into the most-deployed compression algorithm in history.",
  "The GIF/LZW patent war (1994) catalysed PNG; the MP3 patent war (1998+) catalysed Vorbis and Opus; the HEVC patent mess catalysed AV1. Patents repeatedly drove open-source innovation.",
  "ANS (Duda, 2007–2013) gave entropy coding arithmetic-coding ratio at Huffman speed, and is now inside zstd, JPEG XL, and AV1.",
  "The neural era (2016–present) treats compression as learned probabilistic modeling; learned codecs now match or exceed classical ones on benchmarks, and large language models are literally state-of-the-art compressors.",
  "Compression is simultaneously theory (Shannon, Kolmogorov), engineering (DEFLATE, zstd), law (patent wars), and now machine learning (learned codecs).",
))

== Exercises

#exercise("2.1", 1)[
  Morse code gives the letter E a single dot (·) and the letter Z four symbols (··--). Look up the frequency of E and Z in English. About how many times more common is E than Z? Does the code length difference match this frequency difference, as Huffman coding would predict?
]
#solution("2.1")[
  E appears about 13% of the time in English text; Z appears about 0.07%. The ratio is roughly 185:1. Huffman's optimal code length difference would be $log_2(185) approx 7.5$ bits. Morse gives E a length of 1 and Z a length of 4 — a difference of only 3, not 7.5. Morse is *frequency-sensitive* but not *optimally so*: it was designed intuitively, not by any algorithm. Huffman coding would achieve a much larger length difference and thus lower average code length.
]

#exercise("2.2", 1)[
  Shannon proved that the average code length of any lossless code must be at least $H$ bits per symbol, where $H$ is the source entropy. A fair six-sided die (each face equally likely) has what entropy? What is the minimum average number of bits needed to encode a long sequence of die rolls?
]
#solution("2.2")[
  For a fair die, each of the 6 faces has probability $1\/6$. The entropy is $H = -6 times (1\/6) log_2(1\/6) = log_2 6 approx 2.585$ bits per roll. So any lossless code needs at least 2.585 bits per roll on average. A naive 3-bit binary code (000 through 101) uses 3 bits per roll — only 0.415 bits above the minimum. Arithmetic coding can approach 2.585 bits arbitrarily closely.
]

#exercise("2.3", 2)[
  The GIF format (1987) used LZW compression and was widely deployed. PNG (1996) was designed as a patent-free alternative. List three technical differences between GIF and PNG, and explain which is superior on each dimension.
]
#solution("2.3")[
  (1) *Color depth*: GIF supports only 256 colors (8-bit palette); PNG supports up to 48-bit true color and 16-bit grayscale. PNG wins for photographic images. (2) *Transparency*: GIF supports 1-bit transparency (one palette color designated transparent); PNG supports full 8-bit or 16-bit alpha channels per pixel. PNG wins. (3) *Compression*: GIF uses LZW; PNG uses prediction filters + DEFLATE. PNG typically achieves 10–30% better compression on typical images. PNG wins. GIF retains one niche: animation (PNG's animation extension APNG was not widely supported until the 2010s). On every other technical measure, PNG is strictly better.
]

#exercise("2.4", 2)[
  Explain the patent dynamics that led to the creation of AV1. Name the predecessor codecs, the institution that created AV1, and the approximate year of release. Why was it important that AV1 be royalty-free?
]
#solution("2.4")[
  H.265/HEVC (2013) achieved ~50% better compression than H.264/AVC but was immediately encumbered by three competing patent pools (MPEG-LA, HEVC Advance/Access Advance, Velos Media) with incompatible terms. This fragmentation made licensing unpredictable and expensive. The Alliance for Open Media (AOMedia) was formed in September 2015 by Amazon, Apple, ARM, Cisco, Google, Intel, Microsoft, Mozilla, Netflix, NVIDIA, and Samsung to develop AV1. AV1 was released in 2018, royalty-free, with comparable compression to HEVC. It was important that AV1 be royalty-free because H.265's patent costs were prohibiting smaller companies from deploying video streaming and because the history of MP3 and GIF had shown that patent-encumbered formats get displaced by free alternatives once the quality is comparable.
]

#exercise("2.5", 3)[
  DeepMind's "Language Modeling Is Compression" (2023/2024) paper showed that a 70B LLM compressed LibriSpeech audio to 16.4% compared to FLAC's 30.3%. (a) Convert both figures to bits per byte. (b) What compression ratio (compressed:original) does each achieve? (c) Explain in 2–3 sentences *why* an LLM trained only on text can compress audio better than a specialized lossless audio codec.
]
#solution("2.5")[
  (a) FLAC: $30.3 / 100 times 8 = 2.424$ bits per byte. LLM: $16.4 / 100 times 8 = 1.312$ bits per byte. (b) FLAC compresses to 30.3% of original (ratio 1:3.3). LLM compresses to 16.4% of original (ratio 1:6.1). (c) The LLM achieves better compression because an LLM is, by construction, an extremely powerful predictor of the next token in its training domain — and, as Shannon showed, a better predictor always yields a better compressor when combined with an arithmetic coder. The audio was apparently represented as tokens (discretized) in a way the LLM could predict well, and the LLM's massive training had given it statistical models that captured structure the specialized FLAC compressor (which uses only linear prediction + Rice coding) could not. The LLM's breadth of training allows it to exploit statistical patterns across many scales simultaneously.
]

== Further Reading

- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon, C.E. (1948). "A Mathematical Theory of Communication." *Bell System Technical Journal.*] The founding paper. Surprisingly readable; Sections 1–9 are accessible with only algebra.

- #link("https://ieeexplore.ieee.org/document/4051119")[Huffman, D.A. (1952). "A Method for the Construction of Minimum-Redundancy Codes." *Proceedings of the IRE.*] Four pages. Read the construction in Section 4 and the proof of optimality.

- #link("https://ieeexplore.ieee.org/document/1055714")[Ziv, J. & Lempel, A. (1977). "A Universal Algorithm for Sequential Data Compression." *IEEE Trans. Information Theory.*] The LZ77 paper; the universality proof is in Section III.

- #link("https://ieeexplore.ieee.org/document/1659158")[Welch, T.A. (1984). "A Technique for High-Performance Data Compression." *IEEE Computer.*] LZW, readable and short.

- #link("https://www.cs.jhu.edu/~langmea/resources/burrows_wheeler.pdf")[Burrows, M. & Wheeler, D.J. (1994). "A Block-Sorting Lossless Data Compression Algorithm." DEC SRC Report 124.] The BWT. Technically elegant.

- #link("https://arxiv.org/abs/1311.2540")[Duda, J. (2013). "Asymmetric Numeral Systems." arXiv:1311.2540.] The definitive ANS paper.

- #link("https://arxiv.org/abs/2309.10668")[Delétang, G. et al. (2024). "Language Modeling Is Compression." *ICLR 2024.*] The paper that brought the compression = prediction thesis to the mainstream. Highly recommended.

- #link("https://www.mattmahoney.net/dc/text.html")[Mahoney, M. "Large Text Compression Benchmark."] The live scoreboard of lossless compression. Updated to this day.

- #link("http://prize.hutter1.net/")[Hutter Prize.] The ongoing compression-as-intelligence competition.

#bridge[
  We have now flown over the whole field at altitude. The next three chapters build the mathematical and computational foundation you will need to understand *why* each of these milestones works: Chapter 3 asks what "data" and "information" actually are; Chapters 4–13 develop the mathematics (number systems, logic, sets, logarithms, probability) from scratch; Chapters 15–17 teach Python. Then, in Chapter 18, we return to Shannon and derive entropy from first principles — armed with everything we need to truly understand it.
]
