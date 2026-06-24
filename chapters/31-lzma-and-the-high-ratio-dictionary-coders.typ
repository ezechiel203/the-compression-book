#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= LZMA and the High-Ratio Dictionary Coders

#epigraph[
  The best compression ratio you can get without changing the model is to use
  the best possible entropy coder, and then extend the dictionary.
][Igor Pavlov, author of 7-Zip and LZMA]

Picture a kernel developer who needs to ship a Linux tarball to thousands of servers around the world. That `.tar.gz` file might clock in at 140 MB. Swap out gzip for `xz --best` and the same tarball shrinks to 98 MB, a 30 percent saving with no loss of data. On the other hand, the compression step now takes eight minutes rather than thirty seconds, and needs a gigabyte of RAM instead of four megabytes. Is that deal worth taking?

Welcome to the world of *high-ratio dictionary coders*: compressors engineered to push the compression frontier as far as physics allows, at the deliberate cost of speed and memory. In Chapter 30 we dissected DEFLATE: LZ77 plus Huffman, a 32 KB window, a speedy hash chain, greedy parsing. DEFLATE optimises for *time*. The algorithms in this chapter optimise for *size*. They trade every second and every byte of RAM they can extract from the machine in pursuit of a smaller output. Understanding why they work (and why the world's most notorious supply-chain attack in 2024 targeted one of them) requires going deeper into dictionary search strategies, range coding, and context-modelled probability.

#recap[
  In *Chapter 28* we built the LZ77 sliding window compressor: a match finder scans back through a window of recently seen bytes to find the longest string of upcoming bytes that already appeared, and emits a back-reference (distance, length) plus a literal when no match exists. In *Chapter 30* we assembled DEFLATE, which sits LZ77 output through two layers of Huffman coding. The Huffman step in DEFLATE is fast but leaves bits on the table, because Huffman codes must have integer bit-lengths. In *Chapters 26–27* we built the arithmetic coder and rANS, both capable of encoding a symbol in a fractional number of bits, approaching the true information-theoretic cost set by Shannon's entropy limit. This chapter asks: what happens if you combine the *largest possible* LZ77 dictionary with the *most precise* entropy coder, and then also model which symbols are *likely* at each position?
]

#objectives((
  "Explain why DEFLATE's 32 KB window is an inherent bottleneck, and what a larger dictionary gains.",
  "Describe how a range coder differs from a Huffman coder and why it can represent sub-bit probabilities.",
  "Explain what a Markov chain probability model is and how LZMA uses one to compress literals and match decisions.",
  "Understand optimal parsing and why it beats greedy parsing when codes have variable cost.",
  "Read the .xz container format and know what LZMA2 adds to LZMA.",
  "Explain the 2024 xz-utils backdoor: how it was injected, how it was caught, and what it teaches about supply-chain trust.",
  "Describe PPMd and when it beats LZ-based methods.",
))

== Why DEFLATE Leaves Ratio on the Table

DEFLATE is beautiful in its simplicity, but it carries three structural limits that cap its compression ratio.

*The 32 KB window.* LZ77's match finder can only look back 32,768 bytes. If the same string appeared 50 KB ago, DEFLATE cannot reference it. It must emit fresh literals. For source code, English text, or any file with long-range repetition, those missed matches cost dearly.

*Huffman integer codes.* Huffman assigns each symbol a whole-number-of-bits code. If a literal `'e'` has probability 0.13, its true information content is $-log_2(0.13) approx 2.94$ bits. Huffman might assign it a 3-bit code (wasteful by 2 percent) or a 2-bit code (which forces other symbols to carry overly long codes). The rounding never goes away. Across millions of symbols, those fractional losses compound.

*Greedy parsing.* DEFLATE's LZ77 engine picks the *longest possible match* at every position. That sounds optimal, but it is not. Suppose taking a match of length 6 now forces you to next emit four expensive literals, whereas a match of length 5 now lets you immediately take another match of length 7. The *total* cost of the second plan is lower, yet the greedy parser never considers it.

High-ratio codecs attack all three limits simultaneously.

#keyidea[
  The three pillars of high-ratio lossless compression are: (1) a *very large dictionary* to find long-range matches; (2) a *fractional-bit entropy coder* (range coding or ANS) to avoid rounding losses; and (3) *context-based probability models* that let the coder send common patterns for near-zero bits.
]

== Range Coding: Arithmetic Precision Without the Arithmetic Slowness

In Chapter 26 we built a complete arithmetic coder. Recall the idea: you maintain a numeric interval $["low", "high")$ that starts at $[0, 1)$. For each symbol you narrow the interval in proportion to the symbol's probability, then output just enough bits to identify which narrow interval you chose. The result encodes each symbol in exactly $-log_2 p$ bits, which is information-theoretically perfect.

The problem with that arithmetic coder is that it works with real numbers (or very-large-integer fractions), which are expensive to compute. *Range coding*, independently discovered by Jorma Rissanen and G. G. Langdon in 1979 and made practical by Martin (1979) and Schindler (1998), is an equivalent idea that cleverly keeps all arithmetic in machine-word-sized integers.

#gomaths("Range coding in integers")[
  In a range coder, you maintain two machine words: `low` and `range`, where the current interval is $["low", "low" + "range")$.

  To encode a symbol with cumulative frequency `cum_freq` and individual frequency `freq` out of a total count `total`:

  $ "low"' = "low" + "range" times "cum_freq" / "total" $
  $ "range"' = "range" times "freq" / "total" $

  After narrowing, if `range` has fallen below some threshold (say, $2^24$), you "normalize" by outputting the top byte of `low` and left-shifting both `low` and `range` by 8. This keeps both values in a 32-bit window and is exactly as precise as a "true" arithmetic coder because: the integer divisions are the same operations, just in a scaled integer representation.

  *Tiny example.* Suppose `range = 0x01000000`, total = 4, symbol has cum\_freq = 1, freq = 1.
  - `low'  = low + 0x01000000 × 1/4 = low + 0x00400000`
  - `range' = 0x01000000 × 1/4 = 0x00400000`

  Range has fallen below $2^24$. Output the top byte of `low'`, shift left 8, multiply `range` by 256: `range' = 0x40000000`. Both values fit comfortably in 32 bits.
]

The key property that makes range coding attractive for LZMA specifically is that the probability model and the coder are *decoupled*. The range coder does not need to know the alphabet size in advance; you can call it once per *bit*, with a probability that the bit is 0. If you have a sophisticated model that says "this bit is 0 with probability 97%", the range coder encodes it for $-log_2(0.97) approx 0.044$ bits. If you have a dumb model that says 50/50, it costs 1 bit. The model does all the work; the coder just faithfully translates probability into bits. LZMA uses exactly this split: hundreds of small bit-level probability contexts, each updated adaptively, all fed into a single range coder.

#misconception[A range coder is slower than Huffman.][In most implementations, a range coder is competitive with Huffman decoding speed and significantly *faster than arithmetic coding* implemented with big-integer fractions. Because range coding works with 32-bit integer arithmetic and, in the binary (one-bit-at-a-time) form LZMA uses, needs no division during decode. The decoder only has to *split* the current range at the boundary the probability dictates and ask "did the coded value land in the low part or the high part?" That is one multiply, one comparison, and one subtraction. It compiles to a tight inner loop. The speed gap between Huffman and range coding on modern CPUs is typically under 20 percent in favour of Huffman. That small gap is why DEFLATE uses Huffman for speed and LZMA uses range coding for ratio.]

== Markov Chains and Context-Modelled Probability

The range coder is just the messenger. The real magic in LZMA is *what probability it is given* for each bit. LZMA builds a probability model using a concept called a *Markov chain*, named after Russian mathematician Andrey Andreyevich Markov (1856–1922), who first studied sequences of probabilistically dependent events in 1906.

#gomaths("Markov chains")[
  Imagine a frog sitting on one of several lily pads. At each time step it jumps to another lily pad, and the probability of where it lands depends *only on the pad it is currently on*, not on how it got there. This "memory of only the last step" is the Markov property.

  Formally: a Markov chain is a sequence of random variables $X_1, X_2, X_3, dots$ where the probability of moving to state $s$ at time $t+1$ depends only on $X_t$:
  $ P(X_(t+1) = s | X_t, X_(t-1), dots, X_1) = P(X_(t+1) = s | X_t) $

  A *finite* Markov chain has a matrix of *transition probabilities*: entry $(i, j)$ is the probability of going from state $i$ to state $j$ in one step.

  *Tiny example.* Suppose the two states are "last bit was 0" and "last bit was 1". If we observe that after a 0 bit the next bit is also 0 with probability 0.75, and after a 1 bit the next bit is also 1 with probability 0.60, our transition matrix is:

  $ mat(0.75, 0.25; 0.40, 0.60) $

  (Row = current state, column = next state.) A Markov model thus says: "given the last few symbols I've seen, I can estimate the probability of the next symbol." Longer contexts (remembering more past symbols) are called *higher-order* Markov models and can capture more structure, at the cost of needing more memory for the probability table.
]

LZMA's name is literally an acronym: *Lempel–Ziv–Markov chain Algorithm*. The Markov part refers to the fact that LZMA maintains a *separate* probability estimate for each position in its internal state machine. The state machine tracks:

- Whether the *previous* output was a literal, a short match, a long match, or a repeat of a recently used distance.
- The top bits of the *previous* byte written (the high 3–4 bits form a "literal context" that says "we are in the middle of a run of uppercase letters" vs "we just saw a zero byte").
- The *position* modulo some power of two (for files with periodic structure like bitmap rows).

Each combination of those state variables has its *own* probability table: a tiny array of 11-bit counters, one per bit of each decision. The result is hundreds of independent probability estimates, each adapted to the local statistics the coder has observed in that context. When the range coder is given a well-tuned probability instead of 50/50, every bit becomes cheaper.

#aside[
  The 11-bit probability representation is deliberate: LZMA updates each counter with a fast formula:
  $p' = p + (2^11 - p) >> 5$ if the bit was 1, and $p' = p - (p >> 5)$ if the bit was 0.
  This is a multiplicative update: the probability decays toward 0 or 1 exponentially, using only shifts and additions, with no multiplication or division. The entire inner loop of LZMA decoding fits in a handful of CPU instructions.
]

== Inside the LZMA Algorithm

Let us trace how LZMA compresses a stream of bytes, step by step.

=== The Encoder's High-Level Loop

At each position in the input, LZMA must choose one of several *packet types*:

1. *Literal*: output the next raw byte (encoded as 8 bits through the context model).
2. *Match*: encode a back-reference (distance, length) to a previous occurrence.
3. *Rep*: reuse one of the four *most-recently-used distances* (the "rep" cache), optionally with a new length.

The distinction between "Match" and "Rep" is clever. After a long match, you often immediately want another match at the *same* distance (think of structured binary formats, or English where "the" often follows itself). LZMA maintains a buffer of the last four distances used. Referencing one of them costs only 1–3 bits, versus encoding a full distance (up to $2^30$ positions for a 1 GB dictionary, which needs ~30 bits). This "rep buffer" is a key reason LZMA beats DEFLATE on binary data.

=== Literals

A literal is not encoded as a plain byte. Instead, the 8 bits of the literal are encoded *one bit at a time*, each bit in a context that includes:
- The 3 most significant bits of the previous *decoded* byte (the "literal context bits", `lc` in LZMA parlance).
- The low bits of the current *position* in the output stream (`lp` bits).

So if `lc=3` and `lp=0`, there are $2^3 = 8$ separate probability tables, each holding 256 probability entries (one per bit position, split by the accumulated 7 prefix bits). That is $8 times 256 = 2048$ probability entries just for literals. Each is updated independently. If you are compressing English text, the probability table for "context = 'TH'" quickly learns that the next byte is overwhelmingly likely to be a space or 'E' or 'I', and encodes those choices for a fraction of a bit.

=== Match Distances and Lengths

When a match is chosen, LZMA encodes the *length* first (via a length encoder with its own probability model), then the *distance*. Distances are stored in a slot-and-offset form: the 6-bit "slot" encodes the leading bit position of the distance (essentially a magnitude), and the trailing bits are encoded either through context-model probabilities (for short distances) or as raw bits through the range coder without context (for long distances, where the low bits are essentially random).

Length is encoded as a series of flag bits (is the match length ≤ 10? ≤ 18? or longer?) followed by the actual value in the relevant range. Because long matches are rare, the model quickly learns to assign them low probability and they encode efficiently despite needing more bits.

=== The State Machine

At the heart of LZMA is a 12-state Markov chain over *packet type*. The states encode a memory of recent choices: "the last output was a literal", "the last output was a match", "the last two outputs were both literals", etc. Each state gate has its own probability for the question "is the next packet a match or a literal?". This means the model can learn, for example, that after two consecutive literals it is more likely to see another literal (common in natural-language text), while after a long match it is likely to see another match or a rep (common in binary formats).

#fig([The LZMA encoder's decision tree. Each diamond is a 1-bit decision encoded with its own adaptive probability. "Lit" emits a context-modelled byte; "Rep" reuses one of four cached distances; "Match" emits a full distance and length.], cetz.canvas({
  import cetz.draw: *
  set-style(stroke: (cap: "round", join: "round"))

  // Root
  circle((4.5, 5.5), radius: 0.5pt, fill: black)
  content((4.5, 5.9), text(size: 8pt)[*Packet type?*])

  // Branch: Literal
  line((4.5, 5.5), (1.5, 3.5))
  content((2.4, 4.8), text(size: 7.5pt, fill: rgb("#0b6e4f"))[literal])

  rect((0.5, 2.8), (2.5, 3.5), fill: rgb("#0b6e4f").lighten(85%), stroke: rgb("#0b6e4f"))
  content((1.5, 3.15), box(width: 1.6cm, inset: 2pt, align(center, text(size: 8pt)[*Lit* (8 bits, ctx model)])))

  // Branch: Match/Rep
  line((4.5, 5.5), (7.5, 3.5))
  content((6.5, 4.8), text(size: 7.5pt, fill: rgb("#0b5394"))[match/rep])

  // Sub-decision
  circle((7.5, 3.5), radius: 0.4pt, fill: black)
  content((7.5, 3.9), text(size: 8pt)[*is\_rep?*])

  // Rep branch
  line((7.5, 3.5), (5.5, 1.8))
  content((5.9, 2.8), text(size: 7.5pt, fill: rgb("#783f04"))[yes])
  rect((4.3, 1.2), (6.7, 1.8), fill: rgb("#783f04").lighten(88%), stroke: rgb("#783f04"))
  content((5.5, 1.5), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[*Rep* (cached dist)])))

  // Match branch
  line((7.5, 3.5), (9.5, 1.8))
  content((9.0, 2.8), text(size: 7.5pt, fill: rgb("#0b5394"))[no])
  rect((8.3, 1.2), (10.7, 1.8), fill: rgb("#0b5394").lighten(88%), stroke: rgb("#0b5394"))
  content((9.5, 1.5), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[*Match* (dist+len)])))
}))

#checkpoint[
  LZMA keeps a "rep buffer" of the four most recently used distances. Why does this help more on binary formats (like executables or compressed archives) than on plain text?
][
  Binary formats tend to have highly regular, repeating structure: record headers at fixed intervals, alignment padding, repeated byte sequences. The same distance (e.g., "32 bytes back") may be reused dozens of times in a row. Text is more diverse in structure, so distances vary more. The rep buffer compresses its entries for near-zero cost, and binary formats exercise that buffer heavily.]

=== Optimal Parsing

Greedy parsing (always choosing the longest match) is what DEFLATE does. It is fast but suboptimal. Consider this scenario: at position $i$, the greedy parser finds a match of length 8. But the byte at position $i+7$ starts another match of length 15. If the greedy parser had taken a match of length 7 instead (slightly shorter), it could then encode the length-15 match, for a combined gain of $7 + 15 = 22$ units at cost $2$ tokens, versus the greedy choice of $8$ at cost $1$ token followed by a fresh search.

#mathrecall[We met optimal (price-based) parsing in *Chapter 28*: model the input as a graph where each position is a node, each candidate literal or match is an edge whose weight is its bit cost, and the best parse is the cheapest path from start to end. That path is found by *dynamic programming*: building the answer for a long string out of already-computed answers for its prefixes. LZMA pushes that same idea to its practical limit.]

LZMA's encoder (at its highest compression levels) uses *optimal parsing* via dynamic programming. The idea:

1. For every position in a buffer (say, the next 128 bytes), find all possible matches and their costs in bits.
2. Build a shortest-path graph where edges are "take match of length $k$ from position $i$" and weights are the estimated bit cost.
3. Sweep forward through the buffer once, at each position recording the cheapest known total cost to reach it (the dynamic-programming pass), then read the winning path back off. Because every edge points strictly forward, no fancy graph search is needed. A single left-to-right pass suffices.

The result is a parse that might look strange (short matches followed by short matches) but when you count the bits, it is genuinely smaller.

#aside[
  Optimal parsing interacts with the *probability model* in a subtle way: the cost of encoding a literal depends on the current Markov state, which depends on what was output before. True optimality would require re-running the probability model for each candidate parse, which is prohibitively expensive. LZMA's practical approximation re-estimates costs using the current model state without full re-simulation. This is "near-optimal" rather than truly optimal, but in practice the gain over greedy is significant: compression levels 7–9 in 7-Zip owe much of their advantage over level 5 to deeper parsing.]

== The Algorithm Profile

#algo(
  name: "LZMA (Lempel–Ziv–Markov chain Algorithm)",
  year: "1998 (first public: 2001 in 7-Zip 2.30)",
  authors: "Igor Pavlov",
  aim: "Maximum lossless compression ratio for general data, trading encode speed and memory for size.",
  complexity: "Encode: O(n · W) with dictionary size W; decode: O(n). RAM: O(W) for the dictionary plus O(1) model tables.",
  strengths: "Very high compression ratio, especially on large files with long-range repetition; fast decode; adaptive context model; rep buffer excellent on binary data; public domain SDK.",
  weaknesses: "Slow, memory-hungry encoding at high levels; single-threaded by design (LZMA1); not suitable for streaming without buffering.",
  superseded: "LZMA2 (multithread support); xz as the standard container format.",
)[
  LZMA was created by Igor Pavlov, a Russian software developer, starting around 1998. It was first released as part of 7-Zip 2.30 in 2001 and became the default method for the `.7z` archive format. The algorithm is formally a sliding-window LZ scheme (like LZ77) but replaces the simple hash chain and Huffman coder of DEFLATE with a large-dictionary binary tree search, a range coder, and a rich Markov-chain probability model. In 2008, Pavlov released the LZMA SDK into the public domain, enabling its adoption in the Linux kernel (via `xz-utils`) and countless embedded systems.
]

== LZMA2: Threading and Practicality

LZMA1 has a significant practical problem: it is inherently *serial*. Both the encoder and decoder must process the stream front-to-back, because every byte's probability estimate depends on the bytes before it. You cannot split the file and compress halves in parallel. On a 16-core server, LZMA1 still uses one core.

*LZMA2*, introduced in 7-Zip 9.30 (October 2012), solves this by adding a *chunked wrapper*. The stream is divided into independent *chunks* (by default around 1–2 MB each). Each chunk resets the LZ dictionary (partially or fully) and is compressed independently. The encoder can now distribute chunks across threads and process them in parallel. The decoder can also be parallelised, though LZMA2 decode is fast enough that it rarely needs to be.

The chunked structure has another benefit: each chunk can independently be a *literal chunk* (uncompressed data, for content that resists compression) or an *LZMA chunk*. LZMA2 gracefully handles incompressible segments without overhead, unlike LZMA1 which might expand them.

LZMA2 also fixes a minor spec issue: it stores the dictionary size in the compressed header in a more standard way, so the decompressor can allocate exactly the right amount of memory without guessing.

== The .xz Container Format

Raw LZMA2 is just a byte stream, with no filename, no size, and no checksum. The *.xz* file format (maintained by Lasse Collin and Jia Tan, with the specification published at tukaani.org) wraps LZMA2 in a container that provides:

- A *magic number* (`FD 37 7A 58 5A 00`, which is `ý7zXZ\0` in ASCII) for identification.
- A *stream header* with flags and a CRC-32 of the header.
- One or more *blocks*, each independently LZMA2-compressed, with their own header and optional check (CRC-32, CRC-64, or SHA-256).
- An *index* that lists the (compressed size, uncompressed size) of every block, enabling random access within the file.
- A *stream footer* that locates the index and verifies the stream.

The block index is what enables `xz --list` to report the uncompressed size without decompressing, and what would allow (with the right tools) decompressing only part of a large `.xz` file. Most users never notice this structure. They just type `tar xf archive.tar.xz` and it works.

#fig([The .xz container layout. The stream is one or more Blocks, followed by an Index that stores each block's compressed and uncompressed size, allowing random access without full decompression.], cetz.canvas({
  import cetz.draw: *
  set-style(stroke: (thickness: 0.8pt))

  // Header box
  rect((0, 3.2), (2.2, 4.0), fill: rgb("#e8f4fd"), stroke: rgb("#0b5394"))
  content((1.1, 3.6), box(width: 1.8cm, inset: 2pt, align(center, text(size: 7pt)[*Stream Header*\ magic+flags+CRC])))

  // Block 1
  rect((2.4, 3.2), (5.0, 4.0), fill: rgb("#e8fde8"), stroke: rgb("#0b6e4f"))
  content((3.7, 3.6), box(width: 2.2cm, inset: 2pt, align(center, text(size: 7.5pt)[*Block 1*\ LZMA2 compressed])))

  // Block 2
  rect((5.2, 3.2), (7.8, 4.0), fill: rgb("#e8fde8"), stroke: rgb("#0b6e4f"))
  content((6.5, 3.6), box(width: 2.2cm, inset: 2pt, align(center, text(size: 7.5pt)[*Block 2*\ LZMA2 compressed])))

  // Index
  rect((8.0, 3.2), (10.2, 4.0), fill: rgb("#fdf8e8"), stroke: rgb("#783f04"))
  content((9.1, 3.6), box(width: 1.8cm, inset: 2pt, align(center, text(size: 7.5pt)[*Index*\ sizes of all\ blocks])))

  // Footer
  rect((10.4, 3.2), (12.0, 4.0), fill: rgb("#fde8e8"), stroke: rgb("#9a2617"))
  content((11.2, 3.6), box(width: 1.2cm, inset: 2pt, align(center, text(size: 7pt)[*Footer*\ +CRC])))

  // Arrow showing random access
  line((9.1, 3.2), (3.7, 3.2), mark: (end: ">"), stroke: (paint: rgb("#783f04"), dash: "dashed"))
  content((6.5, 2.8), box(width: 5.5cm, align(center, text(size: 7pt, fill: rgb("#783f04"))[random access: jump to any block])))
}))

The practical upshot: `.xz` has replaced `.bz2` as the default archive format for Linux kernel releases, major distribution packages, and many open-source tarballs. As of 2026, a `tar.xz` archive is the standard interchange format when you want DEFLATE-class portability with LZMA-class ratio.

== The xz-utils Backdoor: A Supply-Chain Catastrophe in Slow Motion

In late March 2024, a Microsoft security engineer named *Andres Freund* was troubleshooting slow SSH logins on a Debian testing machine. He noticed that the `sshd` process was consuming unexpectedly high CPU time. After methodical debugging that took weeks, he discovered that the `xz-utils` library (version 5.6.0 and 5.6.1), which provides liblzma, had been *deliberately backdoored*. The malicious code, disguised as test data files in the repository, injected itself into OpenSSH's authentication path during linking. It replaced the RSA key decryption function with an attacker-controlled version that would allow anyone with a specific private key to authenticate as any user, a remote code execution vulnerability with a CVSS score of 10.0 (the maximum possible).

What made this attack extraordinary was not the technical implementation but the *patience and social engineering* behind it.

#history[
  *The xz-utils attack timeline (2021–2024):*

  - *2021, October:* A GitHub account named "Jia Tan" (`JiaT75`) appears and begins contributing small, plausible patches to various open-source projects. The account's activity suggests a professional developer.

  - *2022:* Jia Tan starts contributing to `xz-utils`, whose sole maintainer, *Lasse Collin*, was known to be overworked and struggling with the project's maintenance load. Other accounts (likely sock puppets, fake accounts run by the same actor) begin publicly pressuring Collin to add a co-maintainer and process patches faster.

  - *2023:* After over a year of legitimate contributions, Collin gives Jia Tan commit access to the repository. Jia Tan becomes increasingly the *de facto* primary maintainer, reviewing code, cutting releases, and managing the mailing list.

  - *June 2023:* Jia Tan adds `IFUNC` resolver hooks to the codebase, ostensibly for performance. This is the first piece of the actual attack infrastructure, but is written to look benign.

  - *February 2024:* Jia Tan releases versions 5.6.0 (February 24) and 5.6.1 (March 9) containing the backdoor. The malicious payload is not in the C source. It is hidden in binary *test data files* (`tests/files/bad-3-corrupt_lzma2.xz` and `tests/files/good-large_compressed.lzma`) that are committed to the git repository but whose content is obfuscated. The build system scripts unpack and link this payload during the `./configure` step.

  - *March 29, 2024:* Andres Freund publishes his findings to the `oss-security` mailing list. The severity is immediately understood. Linux distributions scramble to roll back to version 5.4.6. The affected versions (5.6.0 and 5.6.1) had only made it into Debian unstable and some rolling-release distributions, not to stable releases. The attack was caught just in time.

  - *May 29, 2024:* Lasse Collin, after regaining full control of the repository, releases 5.6.2 as a clean version with the malicious code removed. The "Jia Tan" identity was never definitively traced to a specific person or nation-state, though many security researchers speculate about state-actor involvement based on the operation's sophistication and patience.
]

#keyidea[
  The xz-utils attack was not a bug in the LZMA algorithm. LZMA itself is unchanged and secure. The attack targeted the *human layer* of open-source maintenance: an overworked volunteer, social pressure, and a years-long persona-building effort. The exploit lived in the *build system*, not the compression code. The lesson: even the most mathematically rigorous code can be compromised by attacks on the people who review and merge patches.
]

The attack revealed a structural vulnerability in open-source infrastructure: critical libraries depended on by millions of systems can be maintained by a single volunteer with no institutional support. In its aftermath, the Open Source Security Foundation (OpenSSF) and major Linux distributions began more actively reviewing maintainer transitions and providing resources for volunteer maintainers of high-impact projects.

#gopython("The subprocess module: running system tools from Python")[
  Python's `subprocess` module lets you call external programs (like `xz`) and capture their output. Here is a minimal example that compresses and then decompresses a byte string using the system `xz` command:

  ```python
  import subprocess

  data = b"Hello, LZMA!" * 200  # 2400 bytes of repetitive data

  # Compress: pipe data in, read compressed bytes out
  result = subprocess.run(
      ["xz", "--compress", "--stdout", "--check=none"],
      input=data,
      capture_output=True,
  )
  compressed = result.stdout
  print(f"Original : {len(data):,} bytes")
  print(f"Compressed: {len(compressed):,} bytes")

  # Decompress
  result2 = subprocess.run(
      ["xz", "--decompress", "--stdout"],
      input=compressed,
      capture_output=True,
  )
  assert result2.stdout == data, "Round-trip failed!"
  print("Round-trip OK.")
  ```

  `subprocess.run` takes a list of command-line arguments (the first element is the program name), optional `input=` bytes to send to the program's standard input, and `capture_output=True` to collect both stdout and stderr. The result object's `.stdout` attribute holds the output bytes. This pattern lets you benchmark external tools from Python without writing a file.
]

== Python's Built-In lzma Module

You do not need to shell out to `xz` for simple tasks; Python 3.3 and later ship with the `lzma` module in the standard library, which wraps liblzma directly.

```python
import lzma

data = b"The quick brown fox jumps over the lazy dog. " * 500

# One-shot compression
compressed = lzma.compress(data, format=lzma.FORMAT_XZ, preset=6)
print(f"Original  : {len(data):,} bytes")
print(f"Compressed: {len(compressed):,} bytes")
ratio = len(data) / len(compressed)
print(f"Ratio     : {ratio:.2f}x")

# One-shot decompression
recovered = lzma.decompress(compressed)
assert recovered == data
print("Round-trip verified.")
```

The `preset` parameter corresponds to the compression level: 0 is fastest (minimal memory), 9 is slowest (maximum ratio). Adding `| lzma.PRESET_EXTREME` (equivalent to `xz -e`) enables optimal parsing for a few more percent of gain at double the time. The `format` parameter chooses between `FORMAT_XZ` (the `.xz` container), `FORMAT_ALONE` (the legacy `.lzma` format), and `FORMAT_RAW` (bare LZMA2 with no container).

#gopython("Class instances and state: the LZMACompressor object")[
  For streaming compression (when you do not have all the data at once), use `lzma.LZMACompressor`:

  ```python
  import lzma

  comp = lzma.LZMACompressor(format=lzma.FORMAT_XZ, preset=3)

  # Feed data in chunks
  chunks: list[bytes] = []
  for i in range(10):
      piece = f"Chunk number {i}: hello world!\n".encode() * 50
      chunks.append(comp.compress(piece))
  chunks.append(comp.flush())   # finalise the stream

  compressed = b"".join(chunks)
  print(f"Streaming compressed: {len(compressed):,} bytes")

  # Decompress
  recovered = lzma.decompress(compressed, format=lzma.FORMAT_XZ)
  print(f"Recovered: {len(recovered):,} bytes")
  ```

  An `LZMACompressor` is a *class instance*, an object that holds the internal compressor state between calls to `.compress()`. Each call returns some output bytes (possibly empty if LZMA is still buffering), and `.flush()` drains the internal buffer and closes the stream. This pattern (create an object, feed it data in pieces, call flush at the end) is common for codecs in Python and mirrors how real streaming systems work.
]

The `lzma` module is also how Python's `tarfile` module handles `.tar.xz` files: it transparently wraps this streaming interface.

== PPMd: When Context Depth Beats Dictionary Depth

LZMA is not the only algorithm that occupies the high-ratio end of the spectrum. *PPMd* (Prediction by Partial Matching, variant "d", and its successor variants H, I, J) takes a completely different architectural approach to the same goal, and in many benchmarks it matches or exceeds LZMA on natural-language text.

Where LZMA is fundamentally an LZ77 engine with a good entropy coder bolted on, PPMd is a *pure statistical model*: it has no dictionary in the LZ sense at all. Instead, it looks at the last $N$ bytes of *already-decoded* output (the "context") and predicts the probability distribution of the *next byte* from a table built from previous occurrences of that exact context. It then arithmetic-codes that byte using the predicted probability.

The concept goes back to *John Cleary and Ian Witten* at the University of Canterbury, New Zealand, who published the PPM algorithm in 1984 (*IEEE Transactions on Communications*). Their key insight: if you have seen the byte sequence "tion" appear 47 times in the past, you probably know with high confidence that the next byte is often a space, a comma, or 'a'. You use that knowledge to assign a very high probability to those bytes, coding them cheaply.

*Dmitry Shkarin* (Russia) published the variant PPMII (PPM with Information Inheritance) in 2002 and released the source code of PPMd in the public domain. PPMd became the highest-ratio option in many archiver suites, including RAR and 7-Zip's `.7z` format.

#algo(
  name: "PPMd (Prediction by Partial Matching, variant d)",
  year: "PPM: 1984 (Cleary & Witten); PPMd: 2002 (Shkarin)",
  authors: "Original PPM: John Cleary, Ian Witten. PPMd: Dmitry Shkarin.",
  aim: "High-ratio compression via adaptive statistical context modelling: predict each byte from recent context, arithmetic-code it.",
  complexity: "O(n · max\_order) encode/decode; memory proportional to max context order (can be bounded).",
  strengths: "Excellent on natural text and structured data; no LZ dictionary overhead; handles short repeated patterns poorly handled by LZ; very high ratio on Calgary/Canterbury corpus.",
  weaknesses: "Slower than LZ methods; limited context order by memory; not parallelisable; outperformed by LZMA on binary data; harder to tune.",
  superseded: "PPMd variants J, I2 (incremental improvements); context-mixing in PAQ, ZPAQ for even higher ratio.",
)[
  PPMd operates by maintaining a trie (the prefix-tree structure we defined in *Chapter 29*: a tree in which each path from the root spells out a string, so shared prefixes share branches) of all context strings seen so far, with frequency counts for every byte that followed each context. To encode byte $b$ in context $C$:
  1. Look up context $C$ in the trie. If $b$ has been seen after $C$ before, encode it using those frequencies.
  2. If $b$ has *not* been seen after $C$ (an "escape"), send an *escape symbol* and try the shorter context $C'$ (one byte shorter).
  3. Repeat with shorter and shorter contexts until $b$ is found, or you reach the order-0 context (byte frequencies only) or even an escape to literal mode.
  This hierarchical fallback is called the "escape mechanism" and is what makes PPM self-adapting: it degrades gracefully on novel contexts.
]

=== PPMd vs LZMA: When to Pick Which

The performance of PPMd versus LZMA varies sharply with data type:

- *English text, source code, HTML:* PPMd typically wins by 2–8 percent. Its deep context model captures linguistic regularity that LZ back-references miss.
- *Binary executables, compressed data:* LZMA typically wins by 5–15 percent. Its large dictionary catches long repeated byte sequences; PPMd struggles with apparent randomness at high contexts.
- *Mixed data, archives:* Close contest; LZMA's rep-buffer advantage on binary often wins overall.

This is why 7-Zip and similar archivers offer *both* as method options. No single algorithm has displaced both for all uses.

#scoreboard(
  caption: "Cumulative compression of our running 100 KB English text sample (the same file carried since Chapter 30)",
  [Raw (no compression)], [102,400], [1.00×], [baseline],
  [Huffman (Ch 24)], [57,500], [1.78×], [symbol frequencies only],
  [Arithmetic coding (Ch 26)], [55,200], [1.86×], [sub-bit precision],
  [rANS (Ch 27)], [55,100], [1.86×], [ANS; near-identical to arithmetic],
  [LZ77 only (Ch 28)], [44,200], [2.32×], [32 KB window, greedy match],
  [DEFLATE -6 (Ch 30)], [39,800], [2.57×], [LZ77 + Huffman, 32 KB window],
  [PPMd -o8], [33,900], [3.02×], [order-8 context model; shines on text],
  [LZMA -9 (7-Zip)], [33,200], [3.08×], [large dict + range coder + optimal parse],
  [LZMA2 / xz -9], [33,300], [3.08×], [LZMA2 chunked; near-identical single-block],
)

== Worked Example: LZMA Encoding a Short Sequence

Let us walk through a tiny, hand-traceable example of how LZMA handles the string `"ABABABAB"` (8 bytes, ASCII values 65 and 66 alternating).

*Initial state.* The match buffer is empty; dictionary is empty. All probability counters start at 0.5 (the neutral, "no information" value, represented as $2^10 = 1024$ in LZMA's 11-bit fixed-point scale).

*Position 0: `A` (byte 65).* No match possible. Emit *Literal*. The literal 'A' is encoded bit by bit in the literal context table (context = previous byte = none, so the order-0 table). Each of the 8 bits costs 1.0 bits (50/50 probability). Total cost: 8 bits.

*Position 1: `B` (byte 66).* No match possible (only one byte in dictionary). Emit *Literal*. State updates; the literal context now tracks that we last emitted 'A'. Probability for 'B' given context 'A' is still ~50/50. Cost: ~8 bits.

*Position 2: `A` (byte 65).* The encoder looks for matches. It finds the byte `A` at distance 2, length 1, but LZMA only uses matches of length >= 2 (shorter matches are never profitable). Still no usable match. Emit *Literal* `A`. Cost: ~8 bits.

*Position 3: `B` (byte 66).* Now the encoder looks at what follows position 3: `ABAB`. It scans the dictionary and finds that starting 2 bytes back (`ABAB...`) the string `AB` matches. Match of distance=2, length=2. Comparing costs:
- Literal 'B': ~8 bits, plus next literal 'A': ~8 bits = 16 bits for 2 bytes.
- Match (dist=2, len=2): distance slot costs ~6 bits, length flag costs ~2 bits = ~8 bits for 2 bytes.
The match wins. The encoder emits *Match(dist=2, len=2)*. The rep buffer now holds [2, 0, 0, 0] (distance 2 is the most recent).

*Position 5: `A` (byte 65).* The encoder finds another match starting here: `AB` at distance 2 again. Better: it can use a *Rep0* (the most recently used distance is still 2). Rep0 matches cost only 1 bit for the "is it rep0?" decision, plus the length. Rep0 of length 2 costs roughly 3 bits total. Two bytes for 3 bits: far better than 16 bits for two literals.

*Position 7: `B` (byte 66).* Another Rep0 of length 1, but LZMA only uses matches of length >= 2. Emit *Literal* `B`. However, the probability model for 'B' after state "just emitted a rep" and context from previous decoded byte has now updated. After seeing B appear reliably after A in this context, the probability is no longer 50/50; it is shifting toward 0.8 or more. The cost drops below 2 bits.

Total approximate: 3 literals at 8 bits + 1 match at 8 bits + 1 rep at 3 bits + 1 literal at ~2 bits = 45 bits ≈ 6 bytes for 8 bytes input. Ratio of ~1.33×. On tiny inputs the model has no time to warm up; real compression gains appear over kilobytes.

#pitfall[
  LZMA's probability model starts "cold": all probabilities are 0.5, meaning the first kilobyte or so achieves worse compression than even a simple Huffman coder. This is why LZMA is a *large-file* algorithm. For small payloads (under ~10 KB), the model overhead exceeds the gains, and DEFLATE or even Huffman may produce smaller output. Never use `xz` for tiny files without measuring.
]

== The Landscape of High-Ratio Lossless Compression

To put LZMA and PPMd in context, here is a snapshot of where major lossless algorithms sit on the ratio-vs-speed spectrum (approximate figures on mixed text+binary, single core, as of 2025):

#fig([Compression ratio vs. decompression speed for major lossless codecs. High-ratio codecs sit in the top-left; speed codecs in the bottom-right. The horizontal axis is decompression throughput (MB/s); the vertical axis is compression ratio.], cetz.canvas({
  import cetz.draw: *
  set-style(stroke: (thickness: 0.6pt))

  // Axes
  line((0.5, 0.3), (0.5, 5.5), mark: (end: ">"))
  line((0.5, 0.3), (10.5, 0.3), mark: (end: ">"))
  content((0.0, 5.5), box(width: 1.2cm, align(center, text(size: 7pt)[Ratio])))
  content((10.5, 0.1), box(width: 2.0cm, align(left, text(size: 7pt)[Decomp. MB/s])))

  // X-axis ticks
  for (x, label) in ((1.5, "10"), (3.0, "50"), (5.0, "200"), (7.0, "500"), (9.5, "3000")) {
    line((x, 0.25), (x, 0.35))
    content((x, 0.05), text(size: 6pt)[#label])
  }
  // Y-axis ticks
  for (y, label) in ((1.0, "1.5×"), (2.0, "2.5×"), (3.0, "3.5×"), (4.5, "4.5×")) {
    line((0.45, y), (0.55, y))
    content((0.1, y), text(size: 6pt)[#label])
  }

  // Data points
  let pt(x, y, label, col) = {
    circle((x, y), radius: 0.15, fill: col.lighten(60%), stroke: col)
    content((x, y + 0.35), text(size: 6.5pt, fill: col)[#label])
  }

  pt(1.5, 4.5, "PPMd", rgb("#783f04"))
  pt(1.8, 4.3, "LZMA -9", rgb("#0b5394"))
  pt(2.2, 3.8, "LZMA -6", rgb("#0b5394"))
  pt(3.0, 3.2, "bzip2", rgb("#5b3a86"))
  pt(4.5, 2.8, "zstd -19", rgb("#0b6e4f"))
  pt(5.5, 2.7, "DEFLATE -9", rgb("#0b6e4f"))
  pt(7.0, 2.4, "zstd -3", rgb("#0b6e4f"))
  pt(9.0, 1.8, "LZ4", rgb("#9a2617"))
  pt(9.5, 1.6, "Snappy", rgb("#9a2617"))
}))

The diagram makes the trade-off clear: LZ4 and Snappy sit at the far right, offering a few percent compression at multi-gigabyte decode speeds. LZMA-9 and PPMd sit at the far left, delivering deep compression; decompression still runs at dozens of MB/s (fast enough for sequential reading) while encoding can take minutes per gigabyte. Zstandard occupies the middle ground with its tunable dial.

== The lzma Standard Library Module in Depth

Python's `lzma` module exposes several constants and knobs worth knowing:

```python
import lzma

# lzma.FORMAT_XZ   - .xz container (stream header + block + index + footer)
# lzma.FORMAT_ALONE  - legacy .lzma format (just LZMA1, no container)
# lzma.FORMAT_RAW    - no container at all; you supply filters explicitly

# Filters: each is a dict with 'id' and parameters
filters = [
    {"id": lzma.FILTER_LZMA2,
     "dict_size": 64 * 1024 * 1024,  # 64 MB dictionary
     "lc": 3,          # literal context bits (0-4, default 3)
     "lp": 0,          # literal pos bits (0-4, default 0)
     "pb": 2,          # pos bits for all other events (0-4, default 2)
     "mode": lzma.MODE_NORMAL,  # or MODE_FAST for greedy parse
     "mf": lzma.MF_BT4,        # match finder: binary tree depth 4
     "nice_len": 273,           # "nice" match length threshold
     "depth": 0,                # search depth (0 = auto)
    }
]

data = b"LZMA parameters demo " * 10000

compressed_tuned = lzma.compress(data, format=lzma.FORMAT_XZ, filters=filters)
compressed_default = lzma.compress(data, format=lzma.FORMAT_XZ, preset=6)

print(f"Default preset 6 : {len(compressed_default):,} bytes")
print(f"Tuned (64 MB dict): {len(compressed_tuned):,} bytes")
```

The most impactful parameter is `dict_size`. A 64 MB dictionary can reference repeats up to 64 MB in the past; a 4 MB dictionary (LZMA default for level 6) can only look back 4 MB. For Linux kernel tarballs, where many identical function names and headers appear megabytes apart, a large dictionary is worth its memory cost.

The `lc` (literal context bits) and `lp` (literal position bits) parameters control how finely the literal probability tables are split. More bits = more tables = more context-sensitivity but also more cold-start cost and memory. The default `lc=3` means the literal context selector uses the top 3 bits of the previous byte (8 tables). Setting `lc=4` doubles the tables; useful for high-entropy binary data with structured bytes.

== Summary and Connections

This chapter covered the pinnacle of classical lossless compression. The key moves were:

1. *Replace the 32 KB window with a window measured in megabytes or gigabytes*, so long-range repetition can be found.
2. *Replace Huffman coding with range coding*, eliminating the integer-bit-length constraint and enabling sub-bit symbol costs.
3. *Model every decision with a context-specific probability* (which packet type, which literal bit, which length value) using a fast adaptive Markov-chain estimator that updates in a few instructions.
4. *Replace greedy parsing with optimal or near-optimal parsing*, trading encoder time for smaller output.
5. *Wrap the result in a proper container* (`.xz`) that provides integrity checks, random access, and multi-threaded chunking (LZMA2).

For the reader who has worked through Chapters 26–30, each of these steps should feel like a natural extrapolation: "what if we applied our arithmetic coder *here*, and our adaptive model *there*, and searched *longer*?" LZMA is the answer that results when you follow those instincts as far as they go within the classical framework. The next chapter explores what happens at the *speed* end of the spectrum, where Zstandard, Brotli, LZ4, and Snappy live.

#takeaways((
  "DEFLATE's three limits (32 KB window, integer Huffman codes, greedy parsing) set a ceiling that LZMA is designed to break through.",
  "A range coder is an integer-arithmetic arithmetic coder: it encodes one bit at a time using adaptive probability counters, costing fractional bits and eliminating Huffman's rounding loss.",
  "LZMA maintains hundreds of context-specific probability tables organised as a Markov chain over encoder state, literal context bits, and position bits.",
  "Optimal parsing uses dynamic programming over a window to find the sequence of matches and literals with minimum total bit cost. Greedy always-longest-match is not always cheapest.",
  "LZMA2 adds chunked parallelism to LZMA1's serial model; .xz wraps it in a container with integrity checks and a block index for random access.",
  "The 2024 xz-utils backdoor (CVE-2024-3094) was a multi-year supply-chain attack via social engineering; it affected liblzma but not the LZMA algorithm itself.",
  "PPMd is a pure statistical model with no LZ dictionary. It beats LZMA on natural-language text by using deep byte-level context; both live at the high-ratio end of the spectrum.",
  "Python's built-in `lzma` module provides one-shot and streaming access to the full LZMA/LZMA2 feature set, including tunable dictionary size, context bits, and match finders.",
))

== Exercises

#exercise("31.1", 1)[
  A compression tool reports that compressing a 10 MB file with `xz -0` (fastest level) produced a 4.2 MB output, while `xz -9` (slowest level) produced a 3.1 MB output. The encode time was 2 seconds vs 90 seconds respectively. In each case below, which level would you choose? Justify your answer briefly.

  (a) You are distributing a one-time software release that millions of users will download and never re-compress.

  (b) You are compressing hourly log files on a server with limited spare CPU, and your team typically inspects each log file once.
]
#solution("31.1")[
  (a) Level 9. The file is compressed once (even 90 seconds is acceptable) and decompressed millions of times. Users benefit from the smaller download. The encode time is a one-time cost spread over all downloads.

  (b) Level 0. Encoding must be fast (hourly runs, limited CPU). The 4.2 MB vs 3.1 MB difference matters little if logs are stored on cheap disk. The fast level keeps the compression step from blocking other server tasks.
]

#exercise("31.2", 1)[
  LZMA maintains a "rep buffer" of the four most recently used match distances. Suppose you have just finished encoding a run of matches at distance 8 (say, a repeating 8-byte header). The rep buffer is [8, 32, 512, 4096].

  (a) What is the cost (in flag bits) to reference distance 8 again for the next match, versus encoding a fresh match at distance 8?

  (b) If the next match is at distance 32 (the second entry), what happens to the rep buffer after encoding it?
]
#solution("31.2")[
  (a) Referencing rep0 (the first entry, distance 8) costs 1 bit for the "is it rep0?" flag plus the length encoding. Encoding a fresh match at distance 8 would require encoding the full distance (the slot for distance 8 is slot 6, costing 6 bits for the slot plus 0 extra bits = ~6 bits) plus length. So the rep0 reference costs ~1–3 bits total vs ~8+ bits for a fresh match, a significant saving.

  (b) Referencing rep1 (distance 32) promotes it to the front: the new rep buffer becomes [32, 8, 512, 4096]. The previously used distance moves to position 1, and the old rep0 moves to position 1 being pushed down. The four most recently used distances are always kept in order of recency.
]

#exercise("31.3", 2)[
  The LZMA literal probability model uses `lc` "literal context bits" (the top `lc` bits of the previously decoded byte) to select which probability table to use for the next literal.

  (a) If `lc=3`, how many distinct literal probability tables are there?

  (b) If `lc=4`, how many tables? How much more memory (in entries) does this require, given that each table holds 256 entries (one probability counter per possible next byte)?

  (c) A file consists entirely of printable ASCII text (bytes 32–127). All previous bytes have their top bit (bit 7) equal to 0. Does increasing `lc` from 3 to 4 help, hurt, or make no difference? Explain.
]
#solution("31.3")[
  (a) $2^3 = 8$ tables.

  (b) $2^4 = 16$ tables. Each table has 256 entries × 8 bits per literal = 256 entries. Increase: $16 - 8 = 8$ extra tables, so $8 times 256 = 2048$ extra probability entries.

  (c) For pure ASCII text, bit 7 of every previous byte is always 0. With `lc=3`, the context selector uses bits 7–5 of the previous byte. Bit 7 is always 0, so only 4 of the 8 tables (those with leading 0) ever get used. With `lc=4` (bits 7–4), bit 7 is still always 0, so only 8 of the 16 tables are used. The extra tables add memory overhead and cold-start cost without benefit. You would be better served by reducing `lc` and increasing `lp` (position bits) if the file has byte-positional periodicity. So increasing `lc` from 3 to 4 *hurts* slightly (more memory, same number of active contexts).
]

#exercise("31.4", 2)[
  Explain in plain language why greedy parsing is suboptimal for a compressor that uses variable-bit-length codes. Give a concrete two-match example (invent numbers) where taking a shorter first match leads to smaller total output than taking the longest possible first match.

  Then explain why greedy parsing *is* optimal for a fixed-code-length system (like fixed-length encoding where every match costs exactly the same number of bits).
]
#solution("31.4")[
  *Greedy suboptimality example.* At position $i$, greedy finds a match of length 8, costing 12 bits. Then the next token must be a literal costing 8 bits. Total: 20 bits for 9 bytes.

  An optimal parser instead takes a match of length 5 at position $i$ (cost 8 bits), then a match of length 12 starting at $i+5$ (cost 11 bits). Total: 19 bits for 17 bytes, 1 bit cheaper overall, and it encoded more data. Greedy missed this because it committed to length 8 without looking ahead.

  *Why greedy is optimal with fixed costs.* If every match token (regardless of length, distance, or type) costs exactly the same number of bits, then the problem reduces to: "minimise the number of tokens." Greedy always picks the longest match, which maximises bytes per token, which minimises token count, which minimises total bits. Variable bit-lengths break this argument because a longer match might cost more bits-per-byte than a shorter one followed by another efficient match.
]

#exercise("31.5", 2)[
  The xz-utils backdoor was hidden in binary test data files committed to the repository, not in C source code.

  (a) Why is hiding malicious code in binary files more effective at evading code review than hiding it in C source?

  (b) After the attack was discovered, the security community proposed several countermeasures. For each countermeasure below, briefly evaluate whether it would have prevented or detected this attack earlier:
     - Automated diff review of all committed binary files.
     - Requiring two independent maintainers to approve any release.
     - Reproducible builds (building from source produces a bit-identical binary to the official release).
     - Regular automated fuzzing of the library's API.
]
#solution("31.5")[
  (a) C source code can be read and analysed by automated tools (compilers, static analysers, syntax highlighters). Reviewers can read it. Binary files are opaque blobs. A reviewer cannot read a `.xz` test file and notice that it contains shellcode. Automated tools typically skip binary test data as "not interesting". The attacker exploited the common assumption that test fixtures are inert data.

  (b) Countermeasure evaluation:
  - *Automated binary diff review*: Would have flagged changes to the test binary files and prompted a human to investigate what the new content was. Likely would have detected this, if the tooling extracted and inspected the payload.
  - *Two-maintainer approval*: Would have helped if the second maintainer were genuinely independent and suspicious. However, the attacker spent two years building trust, and a second maintainer who also trusted Jia Tan would not have helped. Partial mitigation.
  - *Reproducible builds*: Would not have prevented the backdoor (the attack targeted the build process, and a reproducible build of the backdoored source would reproduce the backdoor). However, reproducible builds *would* detect any post-release binary tampering. Not directly applicable here.
  - *API fuzzing*: Would not have detected this attack. Fuzzing finds crashes and memory errors; this backdoor introduced a subtle authentication bypass only triggered with a specific private key. The library's published API appeared to function correctly during fuzzing.
]

#exercise("31.6", 3)[
  Write a Python function `lzma_bench(data: bytes) -> dict[str, float]` that compresses `data` at LZMA presets 1, 3, 6, and 9, and returns a dictionary mapping preset names like `"xz-1"`, `"xz-3"`, `"xz-6"`, `"xz-9"` to compression ratios (uncompressed / compressed). Also time each compression and print a table showing preset, ratio, encode time (ms), and estimated decode time (ms). Use Python's `lzma` module and `time.perf_counter` for timing. Test your function on a 100 KB block of English text (you may use `b"the quick brown fox " * 5000`).

  *Challenge extension*: also vary the `dict_size` parameter (try 64 KB, 1 MB, and 16 MB) at preset 6 and include those results in your table.
]
#solution("31.6")[
  ```python
  import lzma, time

  def lzma_bench(data: bytes) -> dict[str, float]:
      results: dict[str, float] = {}
      print(f"{'Preset':<12} {'Ratio':>6} {'Enc ms':>8} {'Dec ms':>8}")
      print("-" * 38)
      for preset in (1, 3, 6, 9):
          t0 = time.perf_counter()
          compressed = lzma.compress(data, format=lzma.FORMAT_XZ, preset=preset)
          enc_ms = (time.perf_counter() - t0) * 1000
          t1 = time.perf_counter()
          lzma.decompress(compressed, format=lzma.FORMAT_XZ)
          dec_ms = (time.perf_counter() - t1) * 1000
          ratio = len(data) / len(compressed)
          key = f"xz-{preset}"
          results[key] = ratio
          print(f"{key:<12} {ratio:>6.2f}x {enc_ms:>8.1f} {dec_ms:>8.1f}")
      # Challenge: vary dict_size at preset 6
      for dict_kb in (64, 1024, 16384):
          filters = [{"id": lzma.FILTER_LZMA2,
                      "dict_size": dict_kb * 1024,
                      "preset": 6 & lzma.PRESET_DEFAULT}]
          try:
              t0 = time.perf_counter()
              c = lzma.compress(data, format=lzma.FORMAT_XZ, filters=filters)
              enc_ms = (time.perf_counter() - t0) * 1000
              ratio = len(data) / len(c)
              key = f"xz-6-d{dict_kb}k"
              results[key] = ratio
              print(f"{key:<12} {ratio:>6.2f}x {enc_ms:>8.1f}")
          except Exception as e:
              print(f"dict {dict_kb}k: {e}")
      return results

  if __name__ == "__main__":
      sample = b"the quick brown fox " * 5000  # 100 KB
      lzma_bench(sample)
  ```
  On `b"the quick brown fox " * 5000` (highly repetitive), all presets achieve very high ratios (10–50×) because the 20-byte pattern repeats 5000 times. For a more realistic test, use the first 100 KB of a Wikipedia article or a source-code file.
]

== Further Reading

- #link("https://en.wikipedia.org/wiki/LZMA")[LZMA on Wikipedia]: a clear overview of the algorithm, its parameters, and its history, with links to the SDK documentation.

- #link("https://xz.tukaani.org/format/")[The .xz File Format specification] (tukaani.org): the authoritative technical specification for the `.xz` container, maintained by Lasse Collin.

- #link("https://nigeltao.github.io/blog/2024/xz-lzma-part-5-xz.html")[XZ/LZMA Worked Example by Nigel Tao (2024)]: a detailed five-part blog series that hand-traces the bytes of a real `.xz` file, explaining every field. Outstanding for deep understanding.

- #link("https://www.openwall.com/lists/oss-security/2024/03/29/4")[Andres Freund's original xz-utils disclosure] (oss-security, March 29 2024): the post that broke the story. Read it to see how meticulous security work catches sophisticated attacks.

- #link("https://en.wikipedia.org/wiki/XZ_Utils_backdoor")[XZ Utils backdoor on Wikipedia]: a comprehensive timeline of the attack, its technical details, and its aftermath.

- #link("https://ieeexplore.ieee.org/document/999958")[Dmitry Shkarin, "PPM: One Step to Practicality" (DCC 2002)]: the paper introducing PPMII and PPMd; the foundation of the best statistical compression in 7-Zip and WinRAR.

- #link("https://docs.python.org/3/library/lzma.html")[Python `lzma` module documentation]: reference for every function, constant, and parameter, including the filter specification for fine-grained LZMA2 tuning.

#bridge[
  We have now climbed to the compression summit of classical lossless coding: LZMA at 3–4× on mixed data, PPMd rivalling it on text. Climbing higher costs enormous time and memory. For many real-world applications (databases, caches, network streams, large-scale ML training), time is the binding constraint, not ratio. *Chapter 32: The Modern Frontier - Zstandard, Brotli, LZ4, Snappy* maps the other end of the speed-ratio spectrum: how Yann Collet, starting with LZ4 in 2011 and culminating in Zstandard in 2016, built codecs that compress at gigabytes per second while still achieving useful ratios, and why, by 2026, zstd has become the new default for almost everything that is not a distribution tarball.
]
