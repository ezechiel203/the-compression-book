#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Benchmarks, Corpora, and the Hutter Prize

#epigraph[
  "To compress is to understand."
][Marcus Hutter, announcing the Hutter Prize, 2006]

Picture two engineers arguing about which compressor is "better." One points to a 12%
speed advantage on a database dump. The other counters with a 3% ratio advantage on a
legal archive. Both claim victory. Without an agreed-upon measuring stick — a fixed set of
files, a shared definition of "ratio," and a transparent way to publish the numbers — they
are talking past each other. The entire field has this problem, and the answer it reached
over forty years is the *benchmark corpus*: a canonical collection of real data, made
freely available, against which every compressor reports numbers in the same units.

This chapter is the field's report card. We will walk through the three generations of
compression corpora — Calgary, Canterbury, Silesia — then the Large Text Compression
Benchmark and its centerpiece, *enwik*, and finally the most unusual benchmark in computer
science: the *Hutter Prize*, a 500,000 € bet that compressing Wikipedia is the same thing
as building an artificial mind. Along the way we will wire in Step 16 of `tinyzip`,
giving you a live `bench.py` module that runs every method you have built and prints a
scoreboard you can actually trust.

#recap[
  By Chapter 35 we finished the BWT pipeline — the `bwt`/`ibwt` functions, Move-to-Front,
  and Run-Length Encoding — giving `tinyzip` a bzip2-class compressor and the
  `method="bwt"` container entry. Chapters 24–35 gave us a full toolkit: canonical
  Huffman (Ch. 24), Rice/Golomb codes (Ch. 25), arithmetic coding (Ch. 26), rANS (Ch. 27),
  LZ77 (Ch. 28), DEFLATE (Ch. 30), and the BWT transform (Ch. 35). Now we need to know:
  how do all these methods actually compare, and how does the broader field compare itself?
]

#objectives((
  "Name and distinguish the Calgary, Canterbury, and Silesia corpora and explain what each tests.",
  "Explain what enwik8 and enwik9 are and why Wikipedia text is a meaningful benchmark.",
  "Read a lzbench or Squash results table and extract ratio, compression speed, and decompression speed.",
  "Describe the Hutter Prize rules, constraints, record progression, and underlying philosophy.",
  "Implement bench.py in tinyzip and interpret the scoreboard it produces.",
  "Explain why 'compression equals intelligence' is a serious claim, not just a slogan.",
))

== Why Benchmarks Matter

Before corpora existed, each paper measured its algorithm on whatever files the author
happened to have — a fragment of C source here, a digitized photograph there. Results
were not reproducible. Ratios measured different things: some authors counted the
compressed file alone, others included the decompressor, and some forgot to count
the dictionary that the decoder also needed. Speeds were quoted in seconds on long-gone
hardware with no note of clock frequency or cache size.

#keyidea[
  A *corpus* is a fixed, publicly downloadable set of files that everyone agrees to use.
  A *benchmark* is a protocol that says exactly what to measure and how to report it.
  Together they turn subjective boasting into falsifiable science.
]

The three numbers that matter are:

*Ratio* — the fraction $"compressed size" / "original size"$. A ratio of 0.30 means the
file shrank to 30% of its original size; lower is better. Equivalently, the *bits per
character* (bpc) for a text file: if 1 byte → 8 bits, perfect compression of English
(whose Shannon entropy is about 1.0–1.3 bits per character) would give bpc ≈ 1.1.

*Compression speed* — how many megabytes per second the encoder processes. Measured on a
single CPU thread, at a stated clock speed, with the data already in RAM (so disk I/O
cannot hide in the numbers).

*Decompression speed* — equally important, often more so. A file is compressed once and
decompressed many times.

#gomaths("Bits per character (bpc)")[
  If a file has $N$ bytes = $8N$ bits, and the compressed version has $C$ bytes, then:
  $ "bpc" = (8 C) / N $
  For English text, $N$ is the number of characters and the target is the Shannon entropy,
  about 1.0–1.3 bits per character (as estimated in Chapter 18). So if you compress a
  100,000-character file to 15,000 bytes:
  $ "bpc" = (8 times 15000) / 100000 = 1.2 $
  which is very close to the entropy floor — excellent compression. Compare gzip, which
  typically achieves about 3.2 bpc on English text.
]

== The Calgary Corpus (1987)

The story starts in 1987, in Calgary, Canada. Tim Bell, Ian Witten, and John Cleary — the
same Witten and Cleary who invented PPM, as we saw in Chapter 33 — were writing what
would become the definitive textbook on lossless compression, _Managing Gigabytes_. They
needed a fixed set of files for their experiments. The result was the *Calgary Corpus*:
fourteen files totaling about 3.14 MB, downloaded for free, covering a deliberate variety
of data types:

- English prose (`bib`, `book1`, `book2`, `news`)
- C source code (`progc`)
- LISP source code (`progl`)
- Assembly source code (`progp`)
- Object code (`obj1`, `obj2`)
- Geophysical data (`geo`)
- A genetic sequence (`dna`)
- A grayscale image (`pic`)

This heterogeneity was the point. A compressor that crushed English text but failed on
binary images would score differently than one optimized for source code. The corpus
forced algorithms to be general-purpose.

#history[
  Bell, Witten, and Cleary published their results in the book _Text Compression_ (1990) and
  the companion _Managing Gigabytes_ (1994, 2nd ed. 1999). The Calgary Corpus became so
  standard that papers through the mid-1990s did not even bother to cite it — they simply
  said "tested on the Calgary Corpus" and readers understood. Even today, papers sometimes
  include Calgary numbers alongside modern benchmarks for historical continuity.
]

The canonical Calgary score is the *total compressed size* across all 14 files, usually
quoted in bytes. PPMC (Chapter 33) first cracked 1.0 MB total in the early 1990s; gzip
typically scores around 1.02 MB; PAQ8 (Chapter 34) reaches around 0.82 MB.

Calgary's weakness became apparent over time: fourteen files, only 3 MB, very 1980s
file types. By the late 1990s, typical computer users had GBs of HTML, images, multimedia,
and executable packages — none of which the Calgary Corpus represented well.

== The Canterbury Corpus (1997)

In 1997, Ross Arnold and Tim Bell at the University of Canterbury, New Zealand, published
"A Corpus for the Evaluation of Lossless Compression Algorithms" (Data Compression
Conference 1997). Their *Canterbury Corpus* kept the same design philosophy — a small,
varied, freely downloadable set — but brought the file types into the late 1990s. It had
eleven files totaling about 2.81 MB:

- `alice29.txt` — Alice's Adventures in Wonderland (English prose)
- `asyoulik.txt` — As You Like It (Shakespeare)
- `cp.html` — HTML source (web was new!)
- `fields.c` — C source
- `grammar.lsp` — LISP grammar
- `kennedy.xls` — spreadsheet (Microsoft Excel binary)
- `lcet10.txt` — technical report
- `plrabn12.txt` — Paradise Lost (long English poem)
- `ptt5` — fax transmission (CCITT Group 3)
- `sum` — SPARC executable
- `xargs.1` — Unix man page (troff)

The ptt5 fax file was a deliberate shibboleth: it is highly structured binary data that
looks nothing like text, rewarding compressors that did not assume ASCII.

#checkpoint[
  Why would including a fax file (`ptt5`) in a corpus be valuable when most users never
  compress faxes?
][
  It tests whether the compressor degrades gracefully on non-text binary data, instead of
  only being tuned to English characters. A general-purpose compressor must handle any
  byte sequence without assuming structure.
]

== The Silesia Corpus (2003)

By 2003, Przemysław Skibiński and Szymon Grabowski at the University of Silesia, Poland,
observed that even Canterbury was aging. Modern data was gigabytes of Mozilla source,
Word documents, XML, images, and database tables. They built the *Silesia Corpus*: twelve
files totaling about 211.9 MB — roughly 70× larger than Calgary — drawn from real sources:

#fig(
  [The twelve Silesia corpus files, their sizes, and what they represent.],
  cetz.canvas({
    import cetz.draw: *
    let files = (
      ("dickens", "10.2 MB", "English prose (Dickens novels)"),
      ("mozilla", "51.2 MB", "Mozilla 1.0 tarball (binaries+source)"),
      ("mr", "9.8 MB", "MRI scan (medical imaging)"),
      ("nci", "33.5 MB", "Chemical database (NCI compounds)"),
      ("ooffice", "6.2 MB", "OpenOffice executable"),
      ("osdb", "10.1 MB", "MySQL OSS database"),
      ("reymont", "6.6 MB", "Polish novel (UTF-8)"),
      ("samba", "21.5 MB", "Samba tarball"),
      ("sao", "7.3 MB", "Star catalogue (binary)"),
      ("webster", "41.5 MB", "Webster dictionary"),
      ("xml", "5.3 MB", "XML data"),
      ("x-ray", "8.5 MB", "X-ray image"),
    )
    let col-w = 5.5
    let row-h = 0.45
    for (i, (name, size, desc)) in files.enumerate() {
      let y = -(i * row-h)
      let fill-col = if calc.rem(i, 2) == 0 { rgb("#eef4fb") } else { white }
      rect((0, y), (col-w * 2.5, y - row-h + 0.05),
        fill: fill-col, stroke: rgb("#d0d7de"))
      content((0.15, y - row-h * 0.5), anchor: "west",
        text(size: 7pt, font: "monospace")[#name])
      content((1.8, y - row-h * 0.5), anchor: "west",
        text(size: 7pt)[#size])
      content((2.8, y - row-h * 0.5), anchor: "west",
        text(size: 7pt)[#desc])
    }
    content((2.75, 0.35), text(weight: "bold", size: 8pt)[Silesia Corpus — 12 files, ~211.9 MB])
  })
)

The huge size matters: short files can be lucked into good compression; 50 MB of Mozilla
source exercises the full window of a sliding-window compressor and exposes whether a
dictionary-based compressor benefits from long-range matches.

Today, the Silesia corpus is the workhorse of practical compressor development. When a
developer says "I tested on Silesia," they mean the community can verify the claim
immediately by downloading 12 files from a stable URL and running the same commands.

#aside[
  The `reymont` file — a Polish novel — is a subtle trap for compressors that assume
  ASCII or Latin-1. Polish uses ą, ć, ę, ł, ń, ó, ś, ź, ż, which in UTF-8 encode as
  two-byte sequences. A compressor that models bytes without understanding character
  boundaries will see the high-byte prefix (0xC4, 0xC5) appear suspiciously often. Good
  compressors handle this gracefully; naive ones do not.
]

== How Benchmarks Are Run: lzbench and Squash

Benchmark corpora say *what* to test; tools like *lzbench* and *Squash* say *how*.

*lzbench*, written by Przemysław Skibiński (the same person behind the Silesia Corpus) and
maintained at `github.com/inikep/lzbench`, is an in-memory benchmark. The key word is
"in-memory": all files are loaded into RAM before the clock starts, and the compressed
output never touches disk. This removes I/O variability. On a 2025-class server (AMD
EPYC, a common benchmark machine), typical results on `silesia.tar` look like:

#scoreboard(
  caption: "Representative lzbench numbers on silesia.tar (AMD EPYC, 2025)",
  [lz4 1.10], [94,370,390], [0.445], [fastest compressor; trivial ratio],
  [snappy 1.1.10], [101,358,547], [0.478], [Google's fast path],
  [zlib 1.3 (lvl 6)], [67,643,057], [0.319], [gzip-class; 570 MB/s compress],
  [zstd 1.5.6 (lvl 3)], [61,082,033], [0.288], [default; fast and better than zlib],
  [zstd 1.5.6 (lvl 19)], [52,979,940], [0.250], [slow compress; fast decompress],
  [brotli 1.1 (lvl 11)], [56,521,898], [0.267], [best for pre-trained dicts],
  [bzip2 1.0.8], [54,572,540], [0.257], [BWT pipeline; slow],
  [xz/lzma (lvl 9)], [48,382,163], [0.228], [high ratio; very slow compress],
  [7-zip (LZMA2)], [47,891,244], [0.226], [near-LZMA peak],
  [paq8 (long run)], [36,100,000], [0.170], [context mixing; hours of CPU],
)

(Note: "Ratio" here is compressed/original; lower is better. Bytes column is the
compressed size of silesia.tar's ~212 MB.)

#pitfall[
  Speed numbers are meaningless without knowing the hardware and the thread count.
  Always check: single-threaded or multi-threaded? What CPU? What RAM clock? lzbench
  reports single-threaded throughput by default. A "10 GB/s" decompression claim may mean
  eight threads on a 64-core machine — or may just mean LZ4 on modern hardware, where
  3 GB/s is normal.
]

*Squash* is an abstraction layer: it wraps many compression libraries behind a unified
API, which lets you write `squash compress zstd myfile.dat` and `squash compress lzma myfile.dat`
with identical syntax. The Squash benchmark then runs all available plugins and produces a
unified results table. As of 2025, `lzbench` tends to be more current and more popular for
raw algorithm comparisons; Squash is more useful when you want to compare dozens of
configurations in one run.

== The Large Text Compression Benchmark and enwik

Dictionary coders and the Silesia corpus are a natural match: 51 MB of Mozilla source
has enormous long-range repetition, and an LZ77 with a large window finds it easily. But
there is another kind of structure that dictionary coding misses: *semantic* structure.
The word "Paris" predicts "France"; the phrase "the square root of" predicts a number;
an article titled "Beethoven" predicts discussions of the 9th Symphony. To model this
you need a *statistical model*, not a dictionary.

Matt Mahoney — the creator of the PAQ family we met in Chapter 34 — built the *Large Text
Compression Benchmark* (LTCB) to foreground exactly this challenge. The centerpiece files
are:

*enwik8* — the first 100 million bytes (100 MB) of an English Wikipedia database dump
(the XML-formatted `pages-articles.xml`). Released as a clean benchmark around 2006.

*enwik9* — the first 1 billion bytes (1 GB) of the same dump.

Wikipedia text is deliberately tricky: it mixes prose, markup tags, hyperlinks, templates,
mathematical expressions, foreign-language redirects, and encyclopedic facts that no
dictionary coder would discover. A compressor that scores well on enwik9 must have
actually learned something about human language.

#keyidea[
  On enwik8, `gzip -9` achieves about 36.4 MB (2.91 bpc). PPMd achieves about 15.7 MB
  (1.26 bpc). PAQ8 gets close to 14.9 MB (1.19 bpc). The theoretical entropy floor
  for English is estimated at 0.6–1.3 bpc depending on the model, so the ratio champions
  are within striking distance of Shannon's limit.
]

#gomaths("Bits per character revisited — the English entropy debate")[
  Shannon himself ran a famous experiment in 1951: he gave subjects a passage to read,
  covered the next character, and asked them to guess it. From the guessing statistics he
  estimated the entropy of English at about 1.0–1.5 bpc. Later experiments with better
  subjects and bigger contexts put it at 0.6–1.0 bpc. This matters because it sets the
  theoretical floor — no lossless compressor can go below it. The PPMd and PAQ family
  compressors achieving 1.1–1.3 bpc on enwik8 are within a factor of roughly two of
  that floor; a large language model (Chapter 62) gets even closer.
]

Mahoney publishes the LTCB leaderboard at `www.mattmahoney.net/dc/text.html` with entries
going back to the 1990s. The progression on enwik8 tells the whole story of lossless
compression in miniature: Lempel-Ziv methods in the 1970s–80s, PPM in the 1990s, context
mixing from 2002 onward, and LLMs entering (informally) from 2023.

== The Hutter Prize: Compressing Human Knowledge

Now we arrive at the most unusual benchmark in computer science.

=== The Origin and the Bet

In August 2006, Marcus Hutter — a computer scientist at Australian National University and
the inventor of AIXI (a formal model of optimal intelligence based on Kolmogorov complexity,
previewed in Chapter 22) — announced the *Hutter Prize for Lossless Compression of Human
Knowledge*. The initial prize was 50,000 CHF for enwik8. In *February 2020*, he expanded
it: new submissions now compete on *enwik9* (1 GB), and the prize pool is *500,000 €*.

The logic behind choosing Wikipedia is not arbitrary. Hutter's thesis, developed formally
with Shane Legg in their 2007 paper "Universal Intelligence: A Definition of Machine
Intelligence," is that intelligence is precisely the ability to compress — that is, to find
patterns and predict. A system that cannot summarize or predict natural language has not
understood it.

=== The Rules

The rules are precise and strict. As of 2026:

1. *The file*: `enwik9` — the first $10^9$ bytes of the `enwiki-20060303-pages-articles.xml.bz2`
   dump, which Wikipedia made available in 2006. (The *same* dump, fixed forever — not
   updated Wikipedia content.)
2. *The format*: a *self-extracting archive* (a single executable, typically Linux ELF)
   that contains both the compressed data and the decompressor. The contestant submits one
   file; the judges run it and obtain `enwik9` back, byte-for-byte identical.
3. *The constraints*: decompression must complete in *under approximately 100 hours* on a
   standard single CPU core, using *under 10 GB RAM*, with *no GPU*. Source code must be
   released under a free license (GPL or compatible).
4. *The award*: to win a share of the prize, you must beat the standing record by at least
   1%. You collect 5,000 € per percentage point of improvement, up to 5% per submission.
5. *The review*: a 30-day public comment period during which anyone can examine the source
   and claim a foul.

The "no GPU, 100-hour CPU limit" is the key constraint — it rules out simply loading a
pretrained language model with hundreds of gigabytes of weights and letting it predict
every Wikipedia character. The intelligence must come from the *algorithm itself* running
in bounded resources.

#algo(
  name: "Hutter Prize Benchmark",
  year: "2006 (enwik8) / 2020 (enwik9, 500 k€)",
  authors: "Marcus Hutter",
  aim: "Encourage compression of enwik9 (1 GB Wikipedia XML) to the smallest self-extracting archive, as a proxy for machine intelligence.",
  complexity: "Decompression ≤ 100 CPU-hours, ≤ 10 GB RAM, no GPU; compression can take any amount of time/memory.",
  strengths: "Cheat-resistant constraints; forces algorithmic intelligence, not brute-force model storage; freely verifiable; links compression to AI theory.",
  weaknesses: "Extremely slow winners (days per GB); enwik9 frozen at 2006 Wikipedia, not representative of current web text; English-centric.",
  superseded: "Not superseded; the LTCB leaderboard is complementary.",
)[
  The prize has now paid out roughly €30,000 of its €500,000 total, with each marginal
  percentage point of improvement becoming harder to achieve. The compression of enwik9
  from its 1 GB original to ~110 MB represents a factor of about 9× compression — compared
  with gzip's factor of ~3.6×, a remarkable gap.
]

=== The Record Progression

The Hutter Prize leaderboard is a chronological record of the field's progress:

#scoreboard(
  caption: "Hutter Prize enwik9 record progression (selected winners)",
  [*Winner / Entry*], [*Bytes*], [*bpc*], [*Year / Note*],
  [gzip -9 (baseline reference)], [322,592,757], [2.58], [Not a winner; the common reference],
  [Matt Mahoney — cmix], [116,671,009], [0.933], [Initial enwik9 entry after 2020 expansion],
  [Artemiy Margaritov — starlit], [115,436,792], [0.923], [2021; 1.06% improvement],
  [Saurabh Kumar — fast-cmix], [113,746,218], [0.910], [July 2023; 1.46% improvement, 5,187€],
  [Kaido Orav — fx-cmix], [112,578,322], [0.900], [February 2024; 1.02% improvement],
  [Kaido Orav & Byron Knoll — fx2-cmix], [110,793,128], [0.886], [Sep. 2024; 1.59% improvement, 7,950€],
)

The fx2-cmix entry, submitted August 11, 2024, and accepted October 8, 2024, is the current
standing record as of mid-2026. Kaido Orav and Byron Knoll improved over the previous
record by 1.59%, winning 7,950 €. Their entry incorporated several algorithmic refinements:
embedding entire Wikipedia articles in a vector space, using dimensionality reduction to
reorder the corpus for better statistical locality, and mixing with an improved context
model. Decompression on a modern CPU takes roughly a day of wall-clock time — which satisfies
the 100-hour limit, but illustrates why these compressors are academic curiosities rather
than production tools.

#history[
  The enwik8 phase of the prize (2006–2019) saw the most dramatic gains. Alexander
  Rhatushnyak dominated with the `paq8hp*` series and the `phda9` entry, winning multiple
  prizes between 2006 and 2017. Byron Knoll's cmix broke new ground with LSTM neural
  mixing, a direct ancestor of the modern fx2-cmix. The pivot to enwik9 in 2020 reset the
  competition to a harder, larger target and attracted a new generation of contestants.
]

=== Why "Compression = Intelligence" Is Serious

The Hutter Prize is not a vanity project. The underlying theory connects three fields that
seem separate on the surface:

*Kolmogorov complexity* (Chapter 22) defines the information content of a string as the
length of the shortest program that outputs it. A string with low Kolmogorov complexity
is "simple" — it has structure that a short program can describe.

*Solomonoff induction* (Ray Solomonoff, 1964) shows that the optimal predictor of the
next symbol in a sequence gives each possible continuation a probability proportional to
$2^(-K)$, where $K$ is the Kolmogorov complexity of the hypothesis that predicts it.
The shorter your model, the higher its prior probability.

*Shannon's source coding theorem* (Chapter 19) links prediction to compression: a perfect
predictor of symbol $x$ with probability $p$ can be encoded in $-log_2 p$ bits. So: a
perfect predictor is a perfect compressor, and vice versa.

The chain is: *compressing enwik9 well → predicting Wikipedia text well → modeling human
knowledge well → approaching intelligence*. Hutter made this chain formal in the AIXI
framework: an optimal agent is one that finds the shortest description of its environment
and acts on it.

#keyidea[
  The Hutter Prize is the only prize in AI where the task is unambiguous (compress this
  specific file), the metric is objective (bytes, no human judgment), and the connection to
  intelligence theory is mathematically precise. You cannot cheat by memorizing the test
  set: the 100-hour constraint makes it impossible to embed a giant pretrained model.
]

The DeepMind paper "Language Modeling Is Compression" (Gavin Deletang et al., ICLR 2024)
made the connection explicit in the other direction: state-of-the-art LLMs like Chinchilla,
when used as arithmetic coders (as we will see in Chapter 62), compress enwik8 to
approximately 0.93 bpc — better than most PAQ variants and within reach of the Hutter Prize
winners, without the 100-hour constraint. This does not invalidate the prize; it confirms
the thesis. The LLM is doing exactly what the prize rewards: modeling human knowledge.

=== The Practical Limits

A fair question: why don't the Hutter Prize winners just use a large neural network?
Because of the 10 GB RAM constraint and the 100-hour CPU limit. A 7B-parameter model in
4-bit quantization takes roughly 4 GB of RAM — within limits — but applying it to predict
$10^9$ characters one at a time at, say, 100 tokens/second on a CPU would take
$10^9 / 100 / 3600 approx 2778$ hours. Far over budget.

The winners instead use *online* context models that update their weights as they read the
file forward — the same trick that makes PPM and PAQ adaptive. They learn the specific
statistics of the 2006 Wikipedia dump in real time, without needing pre-training. It is a
beautiful constraint: the algorithm must be intelligent *during* compression, not merely
storing pre-packaged knowledge.

#misconception[
  "The Hutter Prize is just a math puzzle; it has nothing to do with real AI."
][
  The Hutter Prize's theoretical foundations — Kolmogorov complexity, Solomonoff induction,
  AIXI — are the same foundations that underpin modern Bayesian machine learning and
  minimum description length theory. When DeepMind's language models achieve near-record
  compression ratios on Wikipedia, it is because the prize predicted this result two
  decades before the models existed.
]

== tinyzip Step 16 — bench.py

#project("Step 16 · Benchmark every method on a real corpus")[

Step 16 adds `tinyzip/bench.py`, a module that runs every compression method we have built
across Chapters 24–35 on any file (or a small corpus) and prints a scoreboard. The key to
keeping this code short is that *every codec we built already round-trips on its own*: each
module exposes a self-contained `encode(data: bytes) -> bytes` and `decode(blob: bytes) ->
bytes` pair that writes its own little header and reads it back. So `bench.py` does not need
to know anything about the internals — it just calls `encode`, then `decode`, checks they
match, and measures the bytes and the time. We reuse every module *unchanged* and with its
*exact* canonical names:

- `huffman.encode` / `huffman.decode` (Step 8, Chapter 24)
- `arithmetic.encode` / `arithmetic.decode` (Step 10, Chapter 26 — the module-level wrappers)
- `ans.encode` / `ans.decode` (Step 11, Chapter 27 — aliases for `rans_encode`/`rans_decode`)
- `deflate.encode` / `deflate.decode` (Step 13, Chapter 30)
- `bwt.encode` / `bwt.decode` (Step 15, Chapter 35 — the full BWT → MTF → RLE0 → Huffman pipeline)

```python
# tinyzip/bench.py
"""Step 16 — run all tinyzip methods on a corpus and print the scoreboard."""

import time
from pathlib import Path
from typing import Callable, NamedTuple

# ── reuse all prior tinyzip modules, exactly as earlier steps defined them ───
from tinyzip import huffman, arithmetic, ans, deflate, bwt

# ── codec registry ────────────────────────────────────────────────────────────
class Codec(NamedTuple):
    name:   str
    encode: Callable[[bytes], bytes]   # bytes -> bytes
    decode: Callable[[bytes], bytes]   # bytes -> bytes

# Each entry is just the module's own (encode, decode) pair — no wrapping needed,
# because every codec already emits a self-describing blob that decode() reverses.
CODECS: list[Codec] = [
    Codec("huffman",    huffman.encode,    huffman.decode),
    Codec("arithmetic", arithmetic.encode, arithmetic.decode),
    Codec("rANS",       ans.encode,        ans.decode),
    Codec("deflate",    deflate.encode,    deflate.decode),
    Codec("bwt",        bwt.encode,        bwt.decode),
]

# ── single-file benchmark ─────────────────────────────────────────────────────
class Result(NamedTuple):
    codec: str
    original: int
    compressed: int
    ratio: float
    enc_ms: float     # milliseconds
    dec_ms: float

def bench_file(path: Path) -> list[Result]:
    data = path.read_bytes()
    results: list[Result] = []
    for codec in CODECS:
        # encode
        t0 = time.perf_counter()
        blob = codec.encode(data)
        enc_ms = (time.perf_counter() - t0) * 1000

        # decode and verify round-trip
        t0 = time.perf_counter()
        recovered = codec.decode(blob)
        dec_ms = (time.perf_counter() - t0) * 1000

        assert recovered == data, f"{codec.name}: round-trip FAILED"

        ratio = len(blob) / len(data)
        results.append(Result(codec.name, len(data), len(blob),
                               ratio, enc_ms, dec_ms))
    return results

# ── multi-file corpus benchmark ───────────────────────────────────────────────
def bench_corpus(paths: list[Path]) -> dict[str, list[Result]]:
    return {p.name: bench_file(p) for p in paths}

# ── scoreboard printer ────────────────────────────────────────────────────────
_HDR = f"{'Codec':<14} {'Orig':>9} {'Comp':>9} {'Ratio':>7} {'Enc ms':>8} {'Dec ms':>8}"
_SEP = "-" * len(_HDR)

def print_scoreboard(results: list[Result], label: str = "") -> None:
    if label:
        print(f"\n=== {label} ===")
    print(_HDR)
    print(_SEP)
    for r in results:
        print(f"{r.codec:<14} {r.original:>9,} {r.compressed:>9,} "
              f"{r.ratio:>7.3f} {r.enc_ms:>8.1f} {r.dec_ms:>8.1f}")
    print(_SEP)
    best = min(results, key=lambda r: r.compressed)
    print(f"  Best ratio: {best.codec} → {best.ratio:.3f} "
          f"({best.compressed:,} bytes)")

# ── command-line entry point ──────────────────────────────────────────────────
def main(argv: list[str] | None = None) -> None:
    import sys
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print("Usage: python -m tinyzip.bench <file> [<file> ...]")
        return
    for arg in args:
        p = Path(arg)
        if not p.exists():
            print(f"Not found: {p}", file=sys.stderr)
            continue
        results = bench_file(p)
        print_scoreboard(results, label=p.name)

if __name__ == "__main__":
    main()
```

*Self-test* — try it on any file you have:

```python
# Quick smoke-test: compress this very script
from pathlib import Path
from tinyzip.bench import bench_file, print_scoreboard
results = bench_file(Path(__file__))
print_scoreboard(results, "bench.py self-test")
```

For a file that is 100% compressible (all zeros), you will see every codec approach a
ratio near 0.01 or better. For random bytes, every codec will return a ratio above 1.0
because you cannot compress true randomness (Chapter 8 proved this: there are not enough
short strings to represent all long ones).

#gopython("Named tuples as lightweight data classes")[
  `NamedTuple` creates a class whose instances are tuples, but whose fields have names.
  ```python
  from typing import NamedTuple
  class Result(NamedTuple):
      name: str
      score: float

  r = Result("gzip", 0.32)
  print(r.name)   # "gzip"
  print(r[1])     # 0.32  (tuple indexing still works)
  ```
  Named tuples are immutable, memory-efficient (no `__dict__`), and unpack cleanly
  into functions that expect plain tuples. They are ideal for benchmark results that
  you want to collect and sort without changing.
]

#gopython("Functions as values, and the Callable type hint")[
  In Python a function is just another *value*: you can store it in a variable, put it in a
  list, and call it later. That is exactly what the `CODECS` table does — each `Codec` holds
  two functions, `encode` and `decode`, which we call later inside the loop.
  ```python
  def shout(s: str) -> str:
      return s.upper()

  f = shout          # store the function itself (no parentheses!)
  print(f("hi"))     # call it through the variable -> "HI"
  ```
  To *describe* such a value in a type hint we import `Callable` from `typing`. The hint
  `Callable[[bytes], bytes]` reads "a function that takes one `bytes` argument and returns
  `bytes`" — the square brackets list the argument types, then the return type. It is the
  type-hint twin of the `bytes -> bytes` shape every tinyzip codec obeys.
]

]

== Interpreting Benchmark Results: A Worked Example

Let us walk through what a real benchmark run on a 100 KB English text file might look
like, so you know how to read the numbers:

Suppose the file `alice.txt` is 147,717 bytes (the full text of Alice's Adventures in
Wonderland, which appears in both the Canterbury and Silesia corpora):

#scoreboard(
  caption: "Hypothetical tinyzip results on alice.txt (147,717 bytes)",
  [Huffman], [82,440], [0.558], [Removes only symbol-frequency redundancy],
  [Arithmetic], [79,100], [0.536], [Gets closer to entropy; slightly smaller],
  [rANS], [79,050], [0.535], [Same entropy limit; slightly different constants],
  [DEFLATE], [52,300], [0.354], [LZ77 removes repetition; big gain],
  [BWT + MTF], [48,700], [0.330], [Better clustering; closer to optimal for text],
  [gzip -9 (reference)], [53,462], [0.362], [DEFLATE with careful match finding],
  [bzip2 (reference)], [43,537], [0.295], [Full BWT pipeline; better than our toy],
)

Notice the pattern: entropy coders alone (Huffman, arithmetic, rANS) get to around 0.54,
which is the *local* symbol entropy of English (each byte, considered independently, has
about 4.3 bits of uncertainty out of 8). But DEFLATE jumps to 0.35 because it removes
*repetition* — "the", "Alice", "said" appear over and over, and LZ77 represents them as
back-references. The BWT method goes further because it reorders the text to create long
runs of identical bytes, making the subsequent entropy coder even more effective.

The gap between our toy `bwt+mtf` (0.330) and `bzip2` (0.295) is real: bzip2 applies
multiple Huffman passes, a more carefully tuned MTF, and hand-optimized block sizes that
our educational version skips.

#checkpoint[
  If a compressor achieves 0.354 ratio on `alice.txt`, what is the bits-per-character
  figure, and how does it compare to Shannon's estimated entropy of English?
][
  bpc = 0.354 × 8 = 2.83 bpc. Shannon estimated English entropy at about 1.0–1.5 bpc
  (Chapter 18). So 2.83 bpc means DEFLATE is still using roughly twice the theoretical
  minimum. This is expected — DEFLATE does not model long-range semantic patterns; it only
  matches local byte sequences up to 32 KB back.
]

#algo(
  name: "Large Text Compression Benchmark (LTCB)",
  year: "c. 2006",
  authors: "Matt Mahoney",
  aim: "Provide a leaderboard and standard methodology for comparing lossless compressors on enwik8 (100 MB) and enwik9 (1 GB) Wikipedia text.",
  complexity: "No runtime constraints; results are self-reported with hardware specs.",
  strengths: "Stable test files (frozen 2006 dump); long historical record; covers semantic structure beyond LZ methods; freely downloadable.",
  weaknesses: "Self-reported, not formally verified; no runtime limit, so memory-unlimited entries can game it; English-only text; does not test binary or multimedia data.",
  superseded: "Complementary to Silesia/Canterbury for binary/general data; Hutter Prize adds formal verification and resource constraints.",
)[]

== What Makes a Good Corpus?

Not all test sets are equal. A principled corpus should satisfy several properties:

*Variety*: cover text, binary, images, executables, databases, source code. A single file
type punishes or rewards specialization.

*Size*: large enough that startup costs (loading a dictionary, initializing a model) do not
dominate, but small enough that experiments finish in minutes on a single machine.

*Stability*: fixed content, fixed byte order. A benchmark that changes its files breaks
historical comparisons. enwik9 is frozen at the 2006 Wikipedia dump for precisely this
reason — even though Wikipedia has grown enormously since.

*Accessibility*: freely downloadable, no license fees, no registration. Science must be
reproducible.

*Representativeness*: the hardest criterion. No corpus perfectly represents all possible
data. The Canterbury corpus is English-centric; the Silesia corpus is Linux/open-source-
centric; enwik9 is Wikipedia-centric. Users who compress genomes, financial tick data, or
3D point clouds should test on *domain-specific* files, not just Silesia.

#aside[
  The "no corpus perfectly represents all data" problem has a theoretical name: the *no
  free lunch theorem* for compression states that every compressor is optimal on the data
  distribution it was designed for and suboptimal on others. Averaging over all possible
  data, every lossless compressor achieves the same compression: none. The Calgary/Silesia
  corpora implicitly define a distribution — approximately "files that Unix users created
  circa 1987–2003" — and rankings on those corpora are valid only within that distribution.
]

== Reading the Leaderboards

The LTCB leaderboard at `www.mattmahoney.net/dc/text.html` reports results on enwik8 and
enwik9 along with the date submitted and the program name. A few things to watch out for:

*Preprocessing vs raw compression*: some entries apply preprocessing (reordering text,
removing XML tags, filtering markup) before the entropy stage. The rules allow it, as long
as the self-extracting archive also contains the preprocessor and the output is verified
byte-identical.

*Memory use*: entries that use 128 GB of RAM (which the Hutter Prize forbids, but the LTCB
does not restrict) should not be compared directly with entries running in 10 GB.

*Speed*: the LTCB does not require any speed constraint. An entry that takes six months
of CPU time to compress enwik8 is valid on the LTCB but would fail the Hutter Prize's
100-hour decompression limit.

*Verification*: the LTCB is self-reported. The Hutter Prize has a formal 30-day public
comment period. Trust verified entries more.

#fig(
  [The compression landscape: ratio vs speed for the major compressor families on Silesia.],
  cetz.canvas({
    import cetz.draw: *
    // axes
    line((0,0),(8,0), mark: (end: ">"))
    line((0,0),(0,6), mark: (end: ">"))
    content((8.3, 0), text(size: 8pt)[Speed (MB/s) →])
    content((0, 6.3), text(size: 8pt)[← Better ratio])
    // axis labels
    for (x, lbl) in ((1,"10"),(2,"100"),(4,"1k"),(6,"10k")) {
      line((x, -0.05),(x, 0.05))
      content((x, -0.2), text(size: 7pt)[#lbl])
    }
    for (y, lbl) in ((1,"0.45"),(2,"0.35"),(3,"0.28"),(4,"0.23"),(5,"0.17")) {
      line((-0.05, y),(0.05, y))
      content((-0.4, y), text(size: 7pt)[#lbl])
    }
    // data points (log-ish x positions)
    let pts = (
      ("lz4", 6.8, 1.1, rgb("#e63946")),
      ("snappy", 6.3, 1.0, rgb("#e63946")),
      ("zlib-6", 4.1, 2.0, rgb("#457b9d")),
      ("zstd-3", 4.5, 3.0, rgb("#2a9d8f")),
      ("zstd-19", 2.2, 3.0, rgb("#2a9d8f")),
      ("brotli-11", 1.5, 3.3, rgb("#e9c46a")),
      ("bzip2", 2.2, 2.5, rgb("#f4a261")),
      ("xz-9", 1.2, 3.8, rgb("#264653")),
      ("paq8", 0.3, 5.1, rgb("#9b2335")),
    )
    for (name, x, y, col) in pts {
      circle((x, y), radius: 0.13, fill: col, stroke: none)
      content((x + 0.18, y), anchor: "west", text(size: 7pt)[#name])
    }
    // Pareto frontier line
    line((6.8, 1.1),(4.5, 3.0),(2.2, 3.0),(1.2, 3.8),(0.3, 5.1),
      stroke: (dash: "dashed", paint: rgb("#888888"), thickness: 0.5pt))
    content((3.5, 1.4), text(size: 7.5pt, style: "italic")[Pareto frontier])
  })
)

The dashed line in the figure is the *Pareto frontier* — the set of compressors where you
cannot improve ratio without sacrificing speed, or improve speed without sacrificing ratio.
Everything inside the frontier is dominated. Practical choice depends on your use case:
a CDN serving millions of files prefers zstd at level 3 (excellent ratio, very fast decomp);
an archival backup system can afford xz's slow compression for its superior ratio; a
real-time database log prefers lz4's near-memory-speed throughput.

== The Squash Benchmark and Reproducibility

One persistent problem with compression benchmarks is *hardware drift*: a benchmark run
in 2010 on a single-core Pentium 4 cannot be fairly compared to one run in 2025 on an
AMD EPYC with AVX-512 instructions. Modern compressors like zstd explicitly target SIMD
(single instruction, multiple data) hardware — they can compress at 2–3× their single-core
speed on a modern CPU simply because the AVX-512 instruction does 16 bytes at once.

The Squash benchmark (`squash.github.io`) addresses this by running all codecs on the same
machine in the same session and publishing the hardware specification alongside the results.
The lzbench project at `github.com/inikep/lzbench` does the same: you download it, compile
it, and run it on your own machine, producing results that are meaningful *for your machine*.
This is the gold standard: run the benchmark yourself on the hardware that matters to you.

#gopython("Timing code in Python with time.perf_counter")[
  `time.perf_counter()` returns a float in seconds with the highest available resolution
  (typically nanoseconds on modern hardware). It does not include sleep time and is
  independent of wall-clock adjustments.
  ```python
  import time
  t0 = time.perf_counter()
  result = expensive_function()
  elapsed_ms = (time.perf_counter() - t0) * 1000
  print(f"Took {elapsed_ms:.2f} ms")
  ```
  For serious benchmarking, run the function several times and take the *minimum* (not
  average): the minimum represents the fastest the hardware can go without OS interruptions.
  The `timeit` module automates this.
]

== The Bigger Picture: What Benchmarks Cannot Tell You

Benchmarks answer "which compressor is smaller/faster on these files." They cannot answer:

*Will it work on my data?* A compressor optimized for English text (PPMd, the Hutter Prize
winners) may expand, not compress, a genome file or a JPEG image. Always test on your
actual data.

*Is it safe?* Several compression format vulnerabilities (zip bombs, zlib CVEs, the 2024
xz-utils backdoor we discussed in Chapter 31) have caused real security incidents. A
compressor that scores brilliantly on lzbench may also have an exploitable buffer overflow
in its decompressor.

*Will it be maintained?* The zlib source code has been largely unchanged since 1995. The
LZMA SDK is maintained by one person (Igor Pavlov). Both are extraordinarily stable and
well-audited. A novel compressor that tops the lzbench charts but has three contributors
and no test suite may not be suitable for production data.

*What happens at the edge?* An empty file, a file of all-identical bytes, a file that is
exactly one byte — these are the edge cases that reveal bugs. Our tinyzip `bench.py` does
not test these automatically; in a real production library, a property-based test (like
Python's Hypothesis library) would generate random inputs, including edge cases, and verify
round-trips.

#takeaways((
  "The Calgary (1987, 3 MB), Canterbury (1997, 2.8 MB), and Silesia (2003, 212 MB) corpora are the three generations of lossless compression benchmarks, covering progressively larger and more varied file types.",
  "enwik8 and enwik9 are the first 100 MB and 1 GB of a 2006 Wikipedia XML dump, used by the Large Text Compression Benchmark to test semantic compression.",
  "The Hutter Prize (2006/2020, 500,000 €) rewards compression of enwik9 within a 100-hour / 10 GB RAM / no-GPU constraint, with the current record (fx2-cmix, Oct. 2024) at 110,793,128 bytes (~0.886 bpc).",
  "The prize rests on a mathematically precise thesis: optimal prediction equals optimal compression, and both equal intelligence — formalized through Kolmogorov complexity and Solomonoff induction.",
  "lzbench and Squash are the standard tools for fair benchmarking; always report hardware alongside results.",
  "tinyzip Step 16 adds bench.py, which runs all methods, verifies round-trips, and prints a scoreboard you can compare with industry results.",
  "Benchmarks measure performance on the corpus they define; always test on your own data for domain-specific workloads.",
))

== Exercises

#exercise("36.1", 1)[
  The Canterbury Corpus file `alice29.txt` is 152,089 bytes. If a compressor achieves a
  ratio of 0.318 on it, how many bytes is the compressed output, and what is the bpc?
  Is this above or below Shannon's estimated entropy floor for English?
]
#solution("36.1")[
  Compressed size = 0.318 × 152,089 ≈ 48,364 bytes. bpc = (48,364 × 8) / 152,089 ≈ 2.54 bpc.
  Shannon's estimated entropy for English is about 1.0–1.5 bpc, so 2.54 bpc is roughly
  double the theoretical floor — still plenty of room to improve.
]

#exercise("36.2", 1)[
  Why is it important that enwik9 is frozen at the 2006 Wikipedia dump rather than using
  the current (2026) Wikipedia? Name one advantage and one disadvantage of the freeze.
]
#solution("36.2")[
  *Advantage*: historical comparisons are valid. An entry from 2021 and one from 2024 are
  both compressing exactly the same bytes, so the byte counts are directly comparable.
  *Disadvantage*: the 2006 dump does not represent modern Wikipedia (which has grown
  enormously, has more templates, more languages, and different markup conventions). A
  compressor tuned for 2006 XML patterns may not perform as well on 2026 data.
]

#exercise("36.3", 2)[
  Run tinyzip's `bench.py` on a file of your choice (any file from your system, at least
  50 KB). Report the ratios for each method and identify which compression stage (entropy
  coding vs LZ77 vs BWT clustering) contributes the most gain.
]
#solution("36.3")[
  Typical results for English text: Huffman ≈ 0.55, arithmetic/rANS ≈ 0.54 (small gain
  over Huffman because text symbols are skewed but not perfectly modeled). DEFLATE ≈ 0.35
  (the big jump — LZ77 removes repetition). BWT+MTF ≈ 0.33 (further clustering gain).
  The largest single contributor is LZ77/DEFLATE, which exploits long-range repetition
  that entropy coders cannot see.
]

#exercise("36.4", 2)[
  The fx2-cmix entry compressed enwik9 (1,000,000,000 bytes) to 110,793,128 bytes. What
  is the compression ratio? What is the bpc? How does this compare to gzip -9's
  approximately 322,592,757 bytes on the same file?
]
#solution("36.4")[
  fx2-cmix ratio = 110,793,128 / 1,000,000,000 ≈ 0.111. bpc = 0.111 × 8 ≈ 0.886.
  gzip ratio = 322,592,757 / 1,000,000,000 ≈ 0.323, bpc ≈ 2.58.
  fx2-cmix is (0.323 - 0.111) / 0.323 ≈ 65.6% smaller than gzip's output — a massive gap
  that reflects the difference between dictionary matching and deep statistical modeling.
]

#exercise("36.5", 3)[
  Modify `bench.py` to also report the *entropy* (in bpc) of the original file, computed
  using `model.entropy()` from Step 6 (Chapter 18–19). Add a column showing what fraction
  of the theoretical entropy gap each method closes. For a perfectly random file, what
  should each method's ratio be, and why?
]
#solution("36.5")[
  Add `from tinyzip.model import entropy` and compute `H = entropy(data) / 8` (converting
  nats/bits to bpc). For each result, the "gap closed" is `(initial_bpc - achieved_bpc) /
  (initial_bpc - H)`. For a perfectly random file, entropy ≈ 8 bpc; every compressor
  should achieve ratio ≥ 1.0 (because random data cannot be compressed). DEFLATE's ratio
  should be slightly above 1.0 (a small overhead for the LZ77 metadata). Huffman's ratio
  will be close to 1.0 since random bytes have a flat frequency distribution.
]

#exercise("36.6", 3)[
  Design a "micro-corpus" of five files that you believe would be a more representative
  benchmark for a developer building a compressor for genomic FASTQ files. What file types
  would you include? What size? What metrics would you report that the LTCB does not
  currently include? Write a Python script outline (pseudocode is fine) that could automate
  running and reporting the benchmark.
]
#solution("36.6")[
  Suggested micro-corpus: (1) a real FASTQ file with 10 M reads; (2) a FASTA reference
  genome chromosome (100 MB); (3) a SAM alignment file; (4) a quality-score-only file
  (to isolate the hardest part); (5) a compressed FASTQ (to test behavior on already-
  compressed input). Extra metrics: compression of quality scores separately vs read IDs
  separately (they have very different entropy); reference-based vs reference-free ratio;
  decompression speed (critical for analysis pipelines). The Python script would loop over
  files, run each codec, and call `print_scoreboard`, extended with a `domain_notes` column
  explaining why each file is included.
]

== Further Reading

- #link("http://prize.hutter1.net/")[*Hutter Prize official site*] — rules, FAQ, leaderboard, and all awarded submissions.
- #link("http://www.mattmahoney.net/dc/text.html")[*Large Text Compression Benchmark* (Matt Mahoney)] — the enwik8/enwik9 leaderboard with historical entries back to the 1990s.
- #link("https://arxiv.org/abs/2309.10668")[*Language Modeling Is Compression* (Deletang et al., ICLR 2024)] — the DeepMind paper proving that LLMs are SOTA lossless compressors when paired with arithmetic coding.
- #link("https://arxiv.org/abs/0712.3329")[*Universal Intelligence: A Definition of Machine Intelligence* (Legg & Hutter, 2007)] — the formal AI-theory grounding for the Hutter Prize.
- #link("https://github.com/inikep/lzbench")[*lzbench* (inikep, GitHub)] — the standard in-memory compression benchmark; run it yourself to get numbers for your hardware.
- #link("https://morotti.github.io/lzbench-web/")[*lzbench-web*] — interactive charts of lzbench results on various Silesia corpus files.
- #link("https://github.com/kaitz/fx2-cmix")[*fx2-cmix* (Kaitz/Knoll, GitHub)] — source code for the current Hutter Prize record holder (Sep. 2024, 7,950 €).
- #link("http://cs.fit.edu/~mmahoney/compression/nn_paper.pdf")[*Fast Text Compression with Neural Networks* (Mahoney, 2000)] — the paper that began the PAQ/context-mixing lineage and first linked neural networks to compression.

#bridge[
  We have now measured exactly where tinyzip stands against the world. The honest verdict:
  our DEFLATE and BWT implementations are within striking distance of industrial tools on
  small English text, but far below the context-mixing giants on Wikipedia-scale data. The
  reason is that we have only exploited *local* redundancy — nearby bytes that repeat, or
  bytes that share a BWT cluster. The next volume of this book attacks an entirely different
  kind of redundancy: the *perceptual* redundancy in images, audio, and video — the parts
  of a signal that human eyes and ears literally cannot perceive. We will build JPEG from
  scratch, then MP3, then H.264. Chapter 37 begins with signals, sampling, and the
  frequency domain — the mathematical toolkit every lossy codec depends on.
]
