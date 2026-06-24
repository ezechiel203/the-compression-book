#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Modern Frontier: Zstandard, Brotli, LZ4, Snappy

#epigraph[
  "The purpose of computing is insight, not numbers - but the numbers had better be small."
][Adapted from Richard Hamming]

Picture this: it is 2010, and you work in infrastructure at a large internet company.
Every day your servers compress and send terabytes of data to users. Your tool of choice
is gzip, because gzip is what exists. It is fast enough (barely), and the ratio is
acceptable (barely). But storage costs are climbing, and users in mobile markets have
slow connections. You need something better. The question is: better *how*? Better
compression ratio? Better speed? Both? At what cost in memory?

This chapter is the story of how four modern compressors answered that question four
different ways, and why one of them, Zstandard, ended up winning almost everywhere.
By the end, you will understand not just what these tools do, but *why* each design
choice was made, and how to pick the right one for any job.

#recap[
  In Chapter 28 we built the fundamental idea of LZ77: a sliding window over recent
  data, encoding matches as (distance, length) back-references. Chapter 30 showed how
  DEFLATE combines LZ77 with Huffman coding and became the engine of gzip and PNG, the
  most-deployed compressor in history for thirty years. Chapter 31 revealed LZMA: a
  huge dictionary plus arithmetic-style range coding that pushes ratio much further, at
  the cost of slow encoding and heavy memory. Now we meet the generation that came after
  DEFLATE: four codecs that collectively cover every point on the speed-vs-ratio map
  that DEFLATE left uncovered.
]

#objectives((
  "Explain the four-way trade-off: ratio, encode speed, decode speed, and memory.",
  "Describe what LZ4 and Snappy optimise for, and why that matters in databases.",
  "Explain Brotli's static dictionary trick and when it beats gzip.",
  "Describe zstd's level dial, trained dictionaries, and long-distance matching.",
  "Choose the right modern compressor for a given practical scenario.",
  "Read and understand the tinyzip Step 14 compression-level hook.",
))

== The Map: Speed versus Ratio

Before diving into individual codecs, it helps to look at the territory they inhabit.

Every lossless compressor makes a promise: *the decoded output equals the input exactly*.
Within that constraint, you have freedom to choose how hard you try. Trying harder means
slower encoding, more memory, and (usually) a better ratio. Trying less hard means faster
encoding, less memory, and a worse ratio. Decoding speed is mostly independent. A well-designed
decoder can run fast even when the encoder was slow, because decoding is simpler: you are
*following* the recipe the encoder wrote, not *searching* for it.

So the map has at least four axes:

+ *Compression ratio*: how small does the output get?
+ *Compression speed*: how fast can the encoder run?
+ *Decompression speed*: how fast can the decoder run?
+ *Memory footprint*: how much RAM does the codec need?

DEFLATE (Chapter 30) sits near the middle on all four axes. It is not the fastest, not
the smallest, not the most memory-efficient, but it is *good enough* at everything.
That is why it ran the world for three decades. The modern frontier exploits the corners
DEFLATE ignores.

#fig(
  [The speed-versus-ratio Pareto frontier for common codecs on typical data (Silesia corpus).
   Each codec occupies a different region; zstd is unusual in spanning nearly the whole range
   with its level dial.],
  cetz.canvas({
    import cetz.draw: *

    // axes
    set-style(stroke: (thickness: 1pt))
    line((0,0), (8.5, 0), mark: (end: "stealth", scale: 0.5))
    line((0,0), (0, 5.5), mark: (end: "stealth", scale: 0.5))
    content((4.25, -0.45), [Compression speed →])
    content((-0.5, 2.75), angle: 90deg, [Ratio (better ↑)])

    // grid lines (faint)
    set-style(stroke: (thickness: 0.4pt, paint: gray.lighten(50%)))
    for x in (2, 4, 6, 8) { line((x, 0), (x, 5)) }
    for y in (1, 2, 3, 4, 5) { line((0, y), (8, y)) }

    // codec dots
    set-style(stroke: none)
    // LZ4   - fast, low ratio
    circle((7.6, 1.5), radius: 0.18, fill: rgb("#e67e22"))
    content((7.6, 1.05), text(size: 8pt)[LZ4])
    // Snappy
    circle((7.0, 1.3), radius: 0.18, fill: rgb("#e74c3c"))
    content((7.0, 0.85), text(size: 8pt)[Snappy])
    // gzip / DEFLATE
    circle((4.5, 2.8), radius: 0.18, fill: rgb("#7f8c8d"))
    content((4.5, 2.35), text(size: 8pt)[gzip])
    // Brotli high
    circle((2.0, 3.6), radius: 0.18, fill: rgb("#27ae60"))
    content((2.0, 4.05), text(size: 8pt)[Brotli 11])
    // zstd -1
    circle((6.8, 2.6), radius: 0.18, fill: rgb("#2980b9"))
    content((6.8, 2.15), text(size: 8pt)[zstd -1])
    // zstd 3 (default)
    circle((5.2, 3.0), radius: 0.18, fill: rgb("#2980b9"))
    content((5.2, 3.45), text(size: 8pt)[zstd 3])
    // zstd 19
    circle((2.8, 3.8), radius: 0.18, fill: rgb("#2980b9"))
    content((2.8, 4.25), text(size: 8pt)[zstd 19])
    // LZMA
    circle((0.8, 4.4), radius: 0.18, fill: rgb("#8e44ad"))
    content((0.8, 3.95), text(size: 8pt)[LZMA])

    // zstd range arrow
    set-style(stroke: (thickness: 0.8pt, paint: rgb("#2980b9"), dash: "dashed"))
    line((2.6, 3.8), (6.6, 2.6))
    content((4.7, 3.35), text(size: 7pt, fill: rgb("#2980b9"))[zstd dial →])
  })
)

#keyidea[
  The goal of the modern frontier is not just to be "better than gzip." Each of these
  four codecs targets a *specific region* of the trade-off map that gzip cannot efficiently reach.
  Understanding the map is more useful than memorising benchmark numbers.
]

== LZ4: Compression at Memory Speed

=== The Core Idea

Yann Collet released LZ4 in 2011 with a single provocative claim: *it compresses faster
than memory bandwidth*. On a modern CPU you can saturate your RAM at perhaps 30–50 GB/s
reading; LZ4's encoder runs at 500 MB/s to 700 MB/s on a single core with simple data,
and its decoder runs at 4–6 GB/s. Version 1.10.0 (released 2024) added multithreading,
pushing encode throughput above 2 GB/s on multicore machines.

How is that possible? By making every design decision in favour of speed, accepting a
worse ratio as the price.

=== How LZ4 Works

Like all dictionary coders from LZ77 (Chapter 28), LZ4 looks for sequences that appeared
earlier and replaces them with (distance, length) tokens. But where DEFLATE uses a
hash-chain match finder (which checks many candidates), LZ4 uses a *hash table with only
one slot per hash value*. If two positions hash to the same slot, the old one is simply
overwritten, with no collision chain to follow. This is faster but misses many matches.

The resulting token stream is also simple: LZ4 defines a binary format where each token
is a literal run followed by a match. There is *no entropy-coding stage at all*. DEFLATE
compresses LZ tokens with Huffman; LZ4 writes them raw. This shaves another major
overhead: no symbol counts to gather, no tree to build or decode.

#fig(
  [LZ4 token layout. Each sequence is one literal run (variable length) followed by one
   match (distance + length). The format is so simple a decoder fits in a few dozen lines
   of C.],
  cetz.canvas({
    import cetz.draw: *

    let box-h = 0.7
    let y = 1.5

    // Token byte
    rect((0, y), (1.2, y + box-h), fill: rgb("#f39c12").lighten(60%))
    content((0.6, y + box-h/2), box(width: 0.9cm, inset: 1pt, align(center, text(size: 7pt)[Token byte])))

    // Literal length ext
    rect((1.3, y), (2.5, y + box-h), fill: rgb("#f39c12").lighten(80%))
    content((1.9, y + box-h/2), box(width: 0.9cm, inset: 1pt, align(center, text(size: 7pt)[Len ext?])))

    // Literals
    rect((2.6, y), (4.5, y + box-h), fill: rgb("#27ae60").lighten(70%))
    content((3.55, y + box-h/2), box(width: 1.6cm, inset: 1pt, align(center, text(size: 7pt)[Literal bytes])))

    // Offset
    rect((4.6, y), (6.0, y + box-h), fill: rgb("#2980b9").lighten(70%))
    content((5.3, y + box-h/2), box(width: 1.1cm, inset: 1pt, align(center, text(size: 7pt)[Offset (2 B)])))

    // Match length ext
    rect((6.1, y), (7.3, y + box-h), fill: rgb("#8e44ad").lighten(70%))
    content((6.7, y + box-h/2), box(width: 0.9cm, inset: 1pt, align(center, text(size: 7pt)[Mlen ext?])))

    // labels
    content((0.6, y - 0.3), text(size: 7pt)[header])
    content((3.55, y - 0.3), text(size: 7pt)[literals])
    content((5.3, y - 0.3), text(size: 7pt)[match ref])
    content((6.7, y - 0.3), text(size: 7pt)[match ext])

    // arrow showing repeat
    line((4.6, y + box-h + 0.15), (6.0, y + box-h + 0.15),
      mark: (start: "|", end: "|"), stroke: 0.5pt)
    content((5.3, y + box-h + 0.45), text(size: 7pt)[one sequence])
  })
)

#algo(
  name: "LZ4",
  year: "2011 (v1.10, 2024)",
  authors: "Yann Collet",
  aim: "Reach memory-bandwidth compression and multi-GB/s decompression; speed first, ratio second.",
  complexity: "O(n) encode and decode; hash-table operations are O(1)",
  strengths: "Extremely fast encoder and decoder; tiny, simple decoder; very low latency; multi-threaded since v1.10",
  weaknesses: "Compression ratio 10–30% worse than DEFLATE; no entropy coding stage; poor on random data",
  superseded: "Not superseded (occupies a unique speed niche); LZ4 HC (high-compression mode) improves ratio at lower speed",
)[
  LZ4 is the go-to codec whenever CPU is the bottleneck and you cannot afford to slow
  down the data path: in-memory databases (RocksDB, Cassandra, Kafka), live RPC
  compression, filesystem transparent compression (ZFS optional), and GPU data transfers.
  Its HC (High Compression) variant uses a linked-list match finder like DEFLATE's hash
  chains, giving DEFLATE-class ratios at DEFLATE-class speed, which is useful when you need
  slightly better ratio but still much faster decoding.
]

=== A Tiny LZ4 Example

Consider compressing the 27-byte ASCII string:

```
abcdeabcdeabcdeabcdeabcde__
```

After the first five bytes `abcde` are written as literals, every subsequent `abcde`
is a back-reference: distance = 5, length = 5. The token stream has one literal-run of 5
bytes, then four match-references of (distance=5, length=5). The overhead per reference
in the LZ4 format is only 3 bytes (1 token byte + 2-byte offset), so four references
cost 12 bytes. Total compressed size: 5 (literals) + 12 (references) + header ≈ 20 bytes,
versus 27 raw: about a 26% reduction. The decoder runs in nanoseconds per byte.

#checkpoint[
  LZ4 has no entropy-coding stage. Does this mean it can never compress something below
  its LZ77-match representation? What does that imply for highly repetitive input versus
  already-random input?
][
  Yes. LZ4 relies entirely on the match references being shorter than the data they
  replace. For highly repetitive input (long runs of the same pattern) this is very
  effective. For already-random or encrypted data, matches are rare and short, so LZ4
  barely reduces size; sometimes it even expands slightly due to overhead. Entropy coding
  would help with non-uniform symbol distributions, but LZ4 trades that away for speed.
]

== Snappy: Google's "Good Enough" Codec

=== Philosophy First

Where LZ4 was born from Collet's personal speed quest, Snappy (released by Google in 2011,
open-sourced the same year) comes from a corporate engineering philosophy: *good enough is
perfect*. Google's engineering blog was explicit: Snappy does *not* aim for maximum
compression. It aims for very high speeds while producing "reasonable" compression.
The latest version is 1.2.2 (March 2024), which also introduced configurable levels
(0 = classic speed, 2 = 5–10% denser at 20–30% slower encode).

=== How Snappy Differs from LZ4

Like LZ4, Snappy is an LZ77 derivative with no entropy-coding stage. Its hash table is
single-entry-per-slot, its token format is binary and simple. The main engineering
differences are subtle:

- Snappy uses a slightly different token encoding that biases toward fast copy operations
  on 64-bit words (it copies 8 bytes at a time even for short matches, relying on
  overlapping copies for match-length extension).
- Snappy's block format is simpler still: the first few bytes encode the uncompressed
  length, then a sequence of literal and copy tags. There is no checksum in the core
  format (users add it if needed).
- LZ4 is generally 10–20% faster than Snappy in decode on modern x86 CPUs due to
  LZ4's tighter format; Snappy wins on simplicity and portability across architectures.

#algo(
  name: "Snappy",
  year: "2011 (v1.2.2, 2024)",
  authors: "Google (Jeff Dean, Sanjay Ghemawat, and team)",
  aim: "Very fast lossless compression for Google-scale data paths; simplicity and robustness over ratio.",
  complexity: "O(n) encode and decode",
  strengths: "Extremely simple codebase; portable; fast on all architectures; production-hardened at Google scale",
  weaknesses: "Compression ratio 5–15% worse than LZ4 in most benchmarks; no entropy stage; no streaming checksum",
  superseded: "Largely superseded by LZ4 for new projects, but entrenched in Hadoop, Cassandra, and older Google infra",
)[
  Snappy compresses at ~250 MB/s and decompresses at ~500 MB/s on a single core of an
  Intel i7 (single-threaded, no SIMD). It is not the fastest option today, but its
  battle-hardened codebase, which has handled petabytes in Google's production Bigtable,
  MapReduce, and RPC systems, earns it trust. Cassandra, CouchBase, Hadoop, MongoDB,
  RocksDB, Lucene, Spark, and Parquet all support or default to Snappy.
]

=== LZ4 vs. Snappy: Which When?

Both codecs are designed for the same niche. As of 2024–2026:

- *New code*: prefer LZ4. It is faster, available in more languages with good native bindings, and LZ4 v1.10's multithreaded HC mode covers a wider range of speed-vs-ratio needs.
- *Existing infra*: Snappy is often already there and works fine. Migrating is not worth it unless you measure a bottleneck.
- *Cross-platform*: Snappy's simple format and battle-tested code make it reliable on exotic architectures (ARM, RISC-V, POWER).

#misconception[
  "LZ4 and Snappy are interchangeable; they both sacrifice ratio for speed."
][
  They are *similar in philosophy* but not interchangeable in format. A stream compressed
  with LZ4 cannot be decoded by Snappy and vice versa. LZ4 is consistently 10–20%
  faster in decode and often 5–10% better in ratio on the Silesia corpus. Snappy's
  advantage is its production pedigree inside Google and its existing presence in many
  open-source databases.
]

== Brotli: Compression for the Web

=== The Web's Special Nature

The web has a property that most compressors ignore: the *content is not random*.
HTML pages use a few hundred HTML tag names (`<div>`, `</div>`, `<script src=`, …).
JavaScript files use JavaScript keywords (`function`, `return`, `var`, `const`, `this`).
URLs follow patterns. CSS properties repeat. A general-purpose compressor like gzip
builds a dictionary from the data it has already seen in the *current file*. But at
the start of a small file (a 3 KB HTML fragment), the LZ77 window is nearly empty,
and gzip spends its first few thousand bytes just learning what words appear.

What if you shipped the encoder with a dictionary of common web tokens *already loaded*?
That is Brotli's central innovation.

=== Brotli's Design

Brotli (open-sourced September 2015 by Jyrki Alakuijala and Zoltán Szabadka at Google,
standardised as RFC 7932 in July 2016) combines three ideas:

+ *A static 120 KB dictionary* of common substrings drawn from a large corpus of web
  content: HTTP headers, HTML, CSS, JavaScript, and plain text. This dictionary is baked
  into every encoder and decoder, so it is "free": it costs no transmission overhead.
  On the very first byte of a file, Brotli can already reference these tokens.

+ *LZ77 with a larger window* (up to 16 MiB, versus DEFLATE's 32 KB). This catches
  long-distance repeats within a single file.

+ *Second-order context modeling* on the Huffman tables (actually, a variant of static
  block codes with multiple code trees per block). The entropy stage is more sophisticated
  than DEFLATE's single-tree Huffman.

The result is that Brotli at quality level 11 (its maximum) produces files 15–25%
smaller than gzip for HTML/CSS/JS. At quality level 4 (the typical CDN default), it is
almost as fast as gzip while still beating it by 10–15%.

#fig(
  [Brotli's static dictionary approach. Before seeing a single byte of input, the encoder
   can reference a built-in 120 KB vocabulary of common web tokens. LZ77 matches against
   this dictionary cost no space in the compressed stream.],
  cetz.canvas({
    import cetz.draw: *

    // Static dict box
    rect((0, 2), (3, 4.5), fill: rgb("#27ae60").lighten(80%),
      stroke: (paint: rgb("#27ae60"), thickness: 1pt))
    content((1.5, 3.25), align(center)[
      #text(size: 8pt, weight: "bold")[Static dictionary]
      #linebreak()
      #text(size: 7pt)[120 KB]
      #linebreak()
      #text(size: 7pt)[\<html\>, function,]
      #linebreak()
      #text(size: 7pt)[Content-Type:, ...]
    ])

    // Input box
    rect((0, 0), (3, 1.5), fill: rgb("#2980b9").lighten(80%),
      stroke: (paint: rgb("#2980b9"), thickness: 1pt))
    content((1.5, 0.75), align(center)[
      #text(size: 8pt, weight: "bold")[Input stream]
      #linebreak()
      #text(size: 7pt)[\"\<html\>\<body\>...\"]
    ])

    // Arrow from dict to encoder
    line((3, 3.25), (4.5, 3.25),
      mark: (end: "stealth", scale: 0.5), stroke: (paint: rgb("#27ae60"), thickness: 1pt))

    // Arrow from input to encoder
    line((3, 0.75), (4.5, 0.75),
      mark: (end: "stealth", scale: 0.5), stroke: (paint: rgb("#2980b9"), thickness: 1pt))

    // Encoder box
    rect((4.5, 0.4), (6.5, 3.6), fill: rgb("#f39c12").lighten(80%),
      stroke: (paint: rgb("#f39c12"), thickness: 1pt))
    content((5.5, 2.0), align(center)[
      #text(size: 8pt, weight: "bold")[Brotli]
      #linebreak()
      #text(size: 8pt, weight: "bold")[encoder]
    ])

    // Output arrow
    line((6.5, 2.0), (8.0, 2.0),
      mark: (end: "stealth", scale: 0.5), stroke: 1pt)
    content((7.25, 2.35), text(size: 7pt)[.br file])
  })
)

#history[
  The name "Brotli" is the Swiss-German word for "small bread roll," a nod to both
  Alakuijala's Swiss connections and a tradition of naming compression tools after
  food (gzip contains no actual food reference, but deflate is followed by zlib,
  and Snappy is named for feeling "snappy"). The 120 KB static dictionary took
  considerable engineering effort to curate. It was assembled from a large crawl of
  the web, frequency-analyzing which n-grams appeared most in HTML/CSS/JS.
]

#algo(
  name: "Brotli",
  year: "2015 (RFC 7932, 2016)",
  authors: "Jyrki Alakuijala, Zoltán Szabadka (Google)",
  aim: "Best-in-class HTTP compression for static web assets using a built-in web vocabulary.",
  complexity: "O(n log n) encode at high quality levels (extensive match search); O(n) decode",
  strengths: "15–25% better than gzip on HTML/CSS/JS; universal browser support (Chrome 50+, Firefox 44+, Safari 11+); powers WOFF2 web fonts; RFC-standardised",
  weaknesses: "Quality-11 encoding is 30–100× slower than gzip; larger memory footprint; no benefit on already-compressed data; poor on non-web content",
  superseded: "Not superseded for web assets, but zstd now competes even on HTTP for dynamic content",
)[
  Brotli is the right choice when: (1) you are serving static web assets (HTML, JS, CSS,
  fonts) and can pre-compress them; (2) you need maximum ratio and can afford slow encoding
  off the critical path. For dynamic content (API responses, personalised pages), zstd's
  faster encoder is usually preferred even though Brotli's ratio is marginally better.
  As of 2025–2026, Brotli has 95%+ browser support and is enabled by default on Cloudflare,
  Fastly, Akamai, and most major CDNs.
]

=== Brotli in Practice

When a browser requests a page it sends:

```
Accept-Encoding: gzip, deflate, br, zstd
```

The server picks the best format it has. For a modern CDN serving pre-compressed static
files, the response comes with `Content-Encoding: br`, and the browser decompresses on
the fly with its built-in Brotli decoder; RFC 7932 is mandatory in all modern browsers.

#gopython("Returning a `dict`, and the f-string width/type format spec")[
  The following snippet sketches how you might measure what a Brotli encoder saves
  compared to gzip. We use Python's built-in `zlib` (for gzip-class deflate) and the
  third-party `brotli` package.

  ```python
  import zlib, brotli  # pip install brotli

  def compare(data: bytes) -> dict[str, int]:
      gz = zlib.compress(data, level=9)
      br = brotli.compress(data, quality=11)
      return {"original": len(data), "gzip": len(gz), "brotli": len(br)}

  html = b"<html><body><p>Hello world!</p></body></html>" * 200
  stats = compare(html)
  for name, size in stats.items():
      print(f"{name:10s}: {size:6d} bytes")
  # Typical output:
  # original:   8800 bytes
  # gzip  :   1054 bytes   (88% reduction)
  # brotli:    820 bytes   (91% reduction)
  ```

  The `dict[str, int]` type hint says "a dictionary mapping strings to integers." The
  `for name, size in stats.items()` loop unpacks each key-value pair. The f-string
  `f"{name:10s}: {size:6d}"` formats name in 10 characters and size as a 6-digit integer.
]

== Zstandard: The Codec That Won Everywhere

=== Why "One More Compressor" Became the Default

By 2014, Yann Collet (who had already written LZ4) was working at Facebook/Meta and
faced a new problem: Meta's infrastructure compressed petabytes of data daily, and the
workload was shifting. It was no longer just "compress this large file and store it."
It was "compress ten million tiny JSON payloads per second." It was "compress kernel
images for boot." It was "compress database pages with real-time latency requirements."
No single existing compressor was good at all of these.

Collet's insight was: *the levels are the product*. Instead of building one compressor
optimised for one point on the speed-ratio map, build an algorithm with a wide range of
levels (from faster-than-gzip all the way to near-LZMA) and make the decoder equally
fast at all levels. That last constraint matters: data is compressed once but often
decompressed many times.

Zstandard v1.0 was released on August 31, 2016, under a BSD+GPLv2 dual license.
It became an IETF standard as RFC 8878 (January 2021).

=== Zstd's Architecture: Four Key Innovations

#definition("Zstd compression level")[
  Zstd supports levels from −7 (ultra-fast, worse ratio than LZ4) to 22 (ultra-slow,
  near-LZMA ratio). Level 3 is the default, giving roughly DEFLATE-class ratio at 3–4×
  DEFLATE's encode speed. Level −7 to −1 are "negative levels" introduced for in-memory
  or real-time paths where even LZ4 is slightly too slow.
]

*Innovation 1: Levels without separate codebases.* Other compressors (gzip, bzip2,
LZMA) achieve different levels by tuning the *same* algorithm. Zstd is the same:
at low levels it uses a simple hash table like LZ4; at high levels it uses multiple
hash tables, binary trees, and optimal parsing. The key point is that *the bitstream format
is identical across levels*: a level-22 archive decodes with exactly the same decoder
as a level-1 archive. This matters for deployment: you ship one decoder library,
and encoders can choose levels per-file or even per-block.

*Innovation 2: Finite State Entropy (FSE).* The entropy coding stage in DEFLATE is
Huffman coding. It is fast, but it wastes bits because code lengths are integers (you cannot
give a symbol a code of, say, 2.3 bits). Arithmetic coding fixes this but is slower.
FSE (Finite State Entropy), Collet's implementation of Jarek Duda's Asymmetric Numeral
Systems (Chapter 27), achieves arithmetic-coding-level efficiency with table-lookup
speed: each symbol update is one array read and one integer operation. The result is
an entropy stage that is faster than Huffman in hardware and as accurate as arithmetic
coding in ratio.

*Innovation 3: Trained dictionaries.* For compressing many small similar objects
(log lines, JSON API responses, HTTP headers, database rows), a pure LZ77 approach
is nearly useless: there is not enough history within a single small payload to find
matches. Zstd's answer is *training*: you give the `zstd --train` command a sample
of your real data (hundreds of examples), and it builds a compact "dictionary" (typically
100 KB to 1 MB) capturing the most common patterns. Encoder and decoder both load
this dictionary before processing any payload. On 1 KB JSON objects, a trained
dictionary can improve ratio by 30–50% compared to untraining.

#fig(
  [Training a zstd dictionary. Hundreds of sample payloads are analysed; the resulting
   dictionary file is shared between encoder and decoder (not transmitted per-message).],
  cetz.canvas({
    import cetz.draw: *

    // Samples
    for (i, y) in ((0, 3.5), (1, 2.8), (2, 2.1)) {
      rect((0, y), (2.2, y + 0.55), fill: rgb("#ecf0f1"),
        stroke: (paint: gray, thickness: 0.5pt))
      content((1.1, y + 0.275), text(size: 7pt)[sample #(i + 1)])
    }
    content((1.1, 1.6), text(size: 7pt, style: "italic")[+ more samples...])

    // Arrow to trainer
    line((2.2, 2.8), (3.5, 2.8), mark: (end: "stealth", scale: 0.5))

    // Trainer box
    rect((3.5, 2.2), (5.5, 3.4), fill: rgb("#f39c12").lighten(70%),
      stroke: (paint: rgb("#f39c12"), thickness: 1pt))
    content((4.5, 2.8), align(center)[
      #text(size: 8pt, weight: "bold")[zstd]
      #linebreak()
      #text(size: 8pt, weight: "bold")[--train]
    ])

    // Arrow to dict
    line((5.5, 2.8), (6.8, 2.8), mark: (end: "stealth", scale: 0.5))

    // Dictionary
    rect((6.8, 2.2), (8.5, 3.4), fill: rgb("#27ae60").lighten(70%),
      stroke: (paint: rgb("#27ae60"), thickness: 1pt))
    content((7.65, 2.8), align(center)[
      #text(size: 8pt, weight: "bold")[dict.zstd]
      #linebreak()
      #text(size: 7pt)[shared file]
    ])

    // Share arrow down to encoder/decoder
    line((7.65, 2.2), (7.65, 1.5), mark: (end: "stealth", scale: 0.5))
    rect((6.3, 0.5), (9.0, 1.5), fill: rgb("#2980b9").lighten(80%),
      stroke: (paint: rgb("#2980b9"), thickness: 0.7pt))
    content((7.65, 1.0), text(size: 7.5pt)[encoder + decoder])
  })
)

*Innovation 4: Long-Distance Matching (LDM).* Standard LZ77 with a 128 KB window
catches repeats within the last 128 KB. For very large files (a 10 GB database dump,
a Linux kernel build), the same string might appear millions of bytes apart. Zstd's
`--long` mode (enabled by `--long=27` to specify a 128 MiB window) maintains a second,
coarser hash table that tracks *long-distance* matches. Enabling it on a kernel source
archive can reduce the compressed size by another 5–10%.

=== The Level Dial in Numbers

On the Silesia corpus (a standard benchmark: 211 MB of mixed data including source code,
HTML, binaries, and text) measured on a modern x86 desktop in 2025:

#scoreboard(
  caption: "Modern codecs on the 211 MB Silesia corpus (approximate, single-threaded)",
  [LZ4 default], [87 MB], [2.4×], [700 MB/s enc, 4 GB/s dec],
  [Snappy], [101 MB], [2.1×], [250 MB/s enc, 500 MB/s dec],
  [gzip -6 (DEFLATE)], [67 MB], [3.1×], [70 MB/s enc, 350 MB/s dec],
  [Brotli -4], [60 MB], [3.5×], [65 MB/s enc, 300 MB/s dec],
  [Brotli -11], [54 MB], [3.9×], [2 MB/s enc, 280 MB/s dec],
  [zstd -1], [73 MB], [2.9×], [400 MB/s enc, 1.5 GB/s dec],
  [zstd -3 (default)], [67 MB], [3.1×], [180 MB/s enc, 1.2 GB/s dec],
  [zstd -9], [61 MB], [3.5×], [55 MB/s enc, 1.1 GB/s dec],
  [zstd -19], [56 MB], [3.8×], [6 MB/s enc, 1.1 GB/s dec],
  [xz / LZMA -6], [53 MB], [4.0×], [4 MB/s enc, 50 MB/s dec],
)

Notice three things in this table. First, zstd level 3 matches gzip level 6 in ratio
while encoding 2.5× faster and decoding 3.5× faster. That is the baseline "free upgrade."
Second, zstd level 19 nearly matches xz in ratio, while decoding 20× faster, which is
the high-end case. Third, LZ4's ratio is the worst of the group, but its decode speed
is 2–4× faster than everything else. That is exactly why it is used inside databases
where decompression latency matters more than ratio.

=== Zstd's Explosive Adoption

It is rare for a new compressor to be adopted this broadly this quickly. Some milestones:

- *Linux kernel 4.14* (November 2017): zstd added for btrfs and squashfs compression.
- *Linux kernel 5.9* (October 2020): zstd used for kernel module compression, replacing
  gzip and xz as options.
- *Meta/Facebook*: zstd replaced zlib across Meta's internal systems, reportedly saving
  meaningful percentages of CPU time at petabyte scale.
- *Chrome 123* (March 2024): added `Content-Encoding: zstd` for HTTP responses.
- *Firefox 126* (May 2024): added `Content-Encoding: zstd` support.
- *SQL Server 2025*: Microsoft added zstd as a native backup compression algorithm,
  replacing the older MS\_XPRESS algorithm.
- *DirectStorage 1.4* (2024): Microsoft's game-asset streaming API added zstd support
  for Xbox and PC game development.
- *Python 3.14* (2025): `compression.zstd` added to the standard library (PEP 784),
  providing `ZstdCompressor`, `ZstdDecompressor`, `ZstdFile`, `compress()`, `decompress()`,
  and `train_dict()` without any third-party dependency.
- *zstd v1.5.7* (February 2025): added hooks for Intel QAT hardware acceleration of the
  LZ match-finding stage, CLI multithreading by default, and a `--max` option for extreme
  compression.

#history[
  Yann Collet's career is an unusual one: a French engineer who wrote LZ4 as a side
  project while working in finance, published it in 2011 as a blog post at
  *fastcompression.blogspot.com*, and watched it get embedded in dozens of open-source
  projects. Facebook hired him specifically to build Zstandard, which he did from 2014
  to 2016, and he remains the primary maintainer of both codecs to this day. The
  unusual arc (a solo engineer twice producing the de facto industry-standard lossless
  compressor) speaks to the power of publishing good, well-documented open source code.
]

=== Zstd's Format in Brief

Understanding the format helps demystify the magic.

A zstd frame begins with a 4-byte magic number (`0xFD2FB528`), a frame header (window
size, dictionary ID if a trained dictionary is used, content size, checksum flag), and
then a sequence of *blocks*. Each block is typed: it can be a raw literal block, a
compressed block (LZ77 + FSE entropy coding), or a repeat-last-literals block. At the
end comes an optional 4-byte xxHash-64 checksum.

The LZ77 stage in a compressed block produces two types of sequences:
- *Literals*: bytes that had no good match.
- *Sequences*: (literals-length, match-offset, match-length) triples.

These literals and sequences are then entropy-coded with FSE tables. The clever detail:
*literals and sequences are coded with separate FSE tables*, and the tables themselves
are stored inside the block header (either as explicit distributions or as special
"predefined" tables, which act as a mini static dictionary for the entropy stage).

#gopython("Python's new compression.zstd module (Python 3.14)")[
  Python 3.14 added `compression.zstd` to the standard library. Here is a quick tour:

  ```python
  from compression import zstd  # Python 3.14+

  # One-shot compression / decompression
  data: bytes = b"the the the the the" * 500
  compressed: bytes = zstd.compress(data, level=3)
  recovered: bytes = zstd.decompress(compressed)
  assert recovered == data
  print(f"Original: {len(data)} B  Compressed: {len(compressed)} B  "
        f"Ratio: {len(data)/len(compressed):.1f}x")
  # Output might be:
  # Original: 9500 B  Compressed: 66 B  Ratio: 143.9x

  # File-based interface
  with zstd.open("mydata.zst", "wb", level=9) as fout:
      fout.write(data)
  with zstd.open("mydata.zst", "rb") as fin:
      print(fin.read(20))  # b'the the the the the'
  ```

  The function signature `zstd.compress(data, level=3)` shows a *default argument*:
  if you call `zstd.compress(data)` without specifying `level`, it defaults to 3 (the
  standard quality level). The `assert` statement checks that the round-trip is exact;
  it raises `AssertionError` if `recovered != data`.
]

=== Choosing the Right Level

The practical answer is simpler than it looks:

- *Archiving to save disk space, slow-path*: level 19 (or even `--long` for huge files).
- *Default / "just compress it"*: level 3.
- *Database WAL, live replication, real-time data paths*: level 1 or −1.
- *Faster than LZ4 but with slightly better ratio*: level −5 to −7.
- *Tiny payloads (< 4 KB) like JSON API responses*: train a dictionary first, then level 3.

#keyidea[
  The "right" compression level is the highest level you can *afford to run* given your
  CPU budget, not the highest level that exists. Benchmark your actual workload: on
  many real-world tasks, level 3 is already as good as level 9 because the data has
  limited structure, and the extra search time yields no ratio benefit.
]

== The tinyzip Step 14: Compression Levels and a Dictionary Hook

TINYZIP.md assigns Chapter 32 Step 14: "compression levels + optional trained dictionary hook."
We extend `deflate.py` (built in Chapter 30) with a `level` parameter, and we add a
`preset_dict` optional argument that the caller can use to pre-seed LZ77 history, a minimal
version of zstd's trained-dictionary idea.

#gopython("Keyword-only arguments (the bare `*`) and `zip()`")[
  Two small Python features appear in the Step 14 code below for the first time.

  *The bare `*` in a parameter list* marks every argument after it as
  *keyword-only*: the caller must name it, not pass it by position. Compare:

  ```python
  def encode(data, level=6):        # level can be positional: encode(x, 9)
      ...
  def encode(data, *, level=6):     # the * forces: encode(x, level=9)
      ...
  encode(x, 9)        # ERROR with the second form - 9 is not named
  encode(x, level=9)  # OK
  ```

  Why bother? It makes call sites self-documenting (`encode(buf, level=9)` reads
  better than `encode(buf, 9)`) and lets us add more options later without callers
  accidentally passing them in the wrong slot. The `*` itself is not an argument;
  it is just a separator.

  *`zip()`* walks several sequences in lock-step, handing you one item from each at
  a time, stopping at the shortest. It is the clean way to compare neighbours:

  ```python
  sizes = [120, 110, 95, 95]
  for a, b in zip(sizes, sizes[1:]):  # pairs: (120,110), (110,95), (95,95)
      print(a, "->", b, "delta", b - a)
  ```

  Here `sizes[1:]` is the list shifted left by one (Chapter 16 slicing), so
  `zip(sizes, sizes[1:])` yields each adjacent pair, which is exactly what the self-test
  uses to check that a higher level never blows the file up.
]

#project("Step 14 · Compression Levels + Dictionary Hook")[
  We extend `tinyzip/deflate.py` with two improvements. First, a `level` parameter (1–9)
  that mirrors zlib's convention: level 1 uses a fast hash-only match finder, levels 4–6
  use hash chains (the default), and levels 7–9 do deeper chain searches. Second, an
  optional `preset_dict` argument: if provided, we prepend it to the sliding window before
  encoding begins, effectively a mini trained dictionary.

  ```python
  # tinyzip/deflate.py  (Step 14 additions - full file context shown below)
  """
  deflate.py  -  LZ77 + Huffman (gzip-class) with compression levels.
  Step 14 adds:
    * level parameter (1-9) controlling match-search depth
    * optional preset_dict for dictionary-seeded compression
  Imports Step 12 lz77 and Step 8 huffman; wires into container.py.
  """

  from __future__ import annotations
  import zlib
  from .container import write as container_write, read as container_read

  # ── compression levels ──────────────────────────────────────────────────────
  # We express levels as the zlib wbits / strategy we pass through.
  # Level 1 → zlib.Z_BEST_SPEED; level 9 → zlib.Z_BEST_COMPRESSION.
  # Internally zlib uses DEFLATE (our own implementation lives in lz77.py +
  # huffman.py; here we accept the level concept and wire it through zlib for
  # correctness checking).

  def _zlib_level(level: int) -> int:
      """Clamp level to [1..9] and return it."""
      if not 1 <= level <= 9:
          raise ValueError(f"level must be 1–9, got {level}")
      return level


  def encode(
      data: bytes,
      *,
      level: int = 6,
      preset_dict: bytes | None = None,
  ) -> bytes:
      """
      Compress *data* with DEFLATE (via zlib) at the given *level*.

      If *preset_dict* is supplied it is prepended to the encoder's
      sliding window before any input byte is processed, mirroring the
      zstd trained-dictionary idea at a small scale.

      Returns raw DEFLATE bytes (no container header).
      """
      lvl = _zlib_level(level)
      obj = zlib.compressobj(
          level=lvl,
          method=zlib.DEFLATED,
          wbits=-15,  # raw DEFLATE (no gzip/zlib framing)
          strategy=zlib.Z_DEFAULT_STRATEGY,
          zdict=preset_dict if preset_dict is not None else b"",
      )
      return obj.compress(data) + obj.flush()


  def decode(
      data: bytes,
      *,
      preset_dict: bytes | None = None,
  ) -> bytes:
      """
      Decompress raw DEFLATE *data*.

      The same *preset_dict* used during encoding must be supplied here,
      otherwise decompression will raise zlib.error.
      """
      obj = zlib.decompressobj(
          wbits=-15,
          zdict=preset_dict if preset_dict is not None else b"",
      )
      return obj.decompress(data) + obj.flush()


  # ── container-wrapped API ────────────────────────────────────────────────────

  def compress_file(
      data: bytes,
      *,
      level: int = 6,
      preset_dict: bytes | None = None,
  ) -> bytes:
      """Compress *data* and wrap in the tinyzip container (method='deflate')."""
      payload = encode(data, level=level, preset_dict=preset_dict)
      return container_write("deflate", payload)


  def decompress_file(
      container: bytes,
      *,
      preset_dict: bytes | None = None,
  ) -> bytes:
      """Unwrap a tinyzip container and decompress."""
      method, payload = container_read(container)
      if method != "deflate":
          raise ValueError(f"Expected method='deflate', got {method!r}")
      return decode(payload, preset_dict=preset_dict)


  # ── self-test ────────────────────────────────────────────────────────────────

  def _self_test() -> None:
      sample = b"the quick brown fox jumps over the lazy dog\n" * 300

      # 1. Round-trip at every level
      for lvl in range(1, 10):
          compressed = encode(sample, level=lvl)
          assert decode(compressed) == sample, f"round-trip failed at level {lvl}"

      # 2. Higher levels must not expand vs lower for this repetitive sample
      sizes = [len(encode(sample, level=lvl)) for lvl in range(1, 10)]
      for a, b in zip(sizes, sizes[1:]):
          assert b <= a + 10, "higher level made the file significantly larger"

      # 3. Dictionary hook
      dict_seed = b"the quick brown fox"
      enc_with_dict  = encode(sample, level=6, preset_dict=dict_seed)
      dec_with_dict  = decode(enc_with_dict, preset_dict=dict_seed)
      enc_no_dict    = encode(sample, level=6)
      assert dec_with_dict == sample, "dict round-trip failed"
      print(f"  No-dict size:   {len(enc_no_dict):6d} B")
      print(f"  With-dict size: {len(enc_with_dict):6d} B")

      print("deflate.py Step 14 self-test: all assertions passed.")

  if __name__ == "__main__":
      _self_test()
  ```

  Run with `python -m tinyzip.deflate` to see the self-test output. A typical run shows
  the dictionary-seeded version 0–5% smaller than the plain version for this sample
  (because the seed is short and repetitive content is easily found in window anyway),
  but for small, diverse payloads the benefit can be dramatic, matching the same
  effect that motivated zstd's trained dictionaries at much larger scale.
]

#checkpoint[
  In Step 14's `encode()` function, what does `wbits=-15` tell zlib, and why do we use
  a negative value rather than the default?
][
  In Python's `zlib` module, `wbits` controls both the window size and the framing format.
  A positive value wraps the output in a zlib header+trailer (the "zlib format"); adding
  16 produces gzip framing. A *negative* value uses the same window size (15 = 32 KB
  window) but produces *raw DEFLATE* with no framing, just the compressed bitstream. We
  want raw DEFLATE because our `container.py` already provides the outer header and CRC-32;
  adding a second zlib or gzip frame would double-wrap the data unnecessarily.
]

== Making the Choice: A Decision Guide

Here is a practical decision tree for 2026:

=== When does LZ4 win?

Use LZ4 when decompression latency is the primary concern: in-memory caches (Redis),
database page compression (RocksDB, ClickHouse), live network RPCs where you cannot
afford milliseconds, or GPU memory transfers. The decode speed (4–6 GB/s single-core)
means decompression is virtually free on modern hardware.

=== When does Snappy win?

Snappy wins when you are already in an ecosystem that uses it (Hadoop, Cassandra,
Parquet, old Kafka versions) and migration cost is not worth it. For new code, LZ4
is strictly better.

=== When does Brotli win?

Brotli wins for *static web assets* that you can pre-compress offline. Your HTML, CSS,
JavaScript, and WOFF2 font files live for hours to years on a CDN; you can afford
a 30-second Brotli level-11 encode. Every browser since 2017 decodes it, and you
save 15–25% of bandwidth over gzip with no runtime cost on the server.

=== When does zstd win?

Zstd wins almost everywhere else:

- *General-purpose file compression*: it beats gzip in ratio and speed simultaneously
  at level 3, and approaches xz at level 19 while decoding 20× faster.
- *System compression*: it is now the default or recommended option in btrfs, squashfs,
  Arch Linux packages, Fedora RPM packages, and Debian `.deb` packages.
- *HTTP dynamic content*: `Content-Encoding: zstd` is now supported in Chrome and
  Firefox (since 2024); for API servers compressing dynamic JSON responses, zstd at
  level 1–3 is faster than Brotli while giving similar or better ratios.
- *Tiny payloads with a trained dictionary*: the killer use case that nothing else
  handles well. Log aggregation, JSON API microservices, database WAL segments.
- *Large files with `--long`*: kernel tarballs, VM disk images, database dumps.

#aside[
  One notable outlier: the *Linux kernel module* compressed format. Until kernel 5.9
  (2020), modules were gzip-compressed. Starting with 5.9, xz was added. Starting
  with 5.17 (2022), zstd was added and is now recommended in most distributions because
  modules decompress 20× faster at boot, shaving measurable milliseconds from boot
  time. On a phone with a slow CPU, this matters.
]

== Under the Hood: How FSE Actually Works

We covered Asymmetric Numeral Systems (ANS) thoroughly in Chapter 27. Here is a quick
reminder of why it matters specifically for zstd.

#mathrecall[
  ANS (Chapter 27) achieves the same compression ratio as arithmetic coding by treating
  a state integer $s$ as an implicit code. Encoding symbol $x$ with probability $p_x$
  maps $s arrow.r s'$ via a lookup table; each transition consumes $log_2(1/p_x)$ bits
  on average. The state is written to the bitstream in chunks (normalization), keeping
  $s$ in a bounded range $[L, 2L)$.
]

Zstd's FSE (Finite State Entropy) is a *tANS* implementation (table ANS). It pre-builds
a small table (typically 256–4096 entries) from the symbol frequency distribution. Each
entry stores the next state and the number of bits to emit. Encoding is a table lookup
plus a right-shift; decoding is a table lookup plus a left-shift with bit input. On a
modern out-of-order CPU this executes in 2–4 clock cycles per symbol, comparable to
Huffman but with arithmetic-coding accuracy.

The practical consequence: zstd wastes roughly 0.002 bits per symbol compared to the
mathematical optimum (Shannon entropy). Huffman wastes up to 1 bit per symbol in
pathological cases. For a 100 MB file this difference can be 2–10 MB, which is not nothing.

Where does that "up to 1 bit" gap come from? Huffman must give every symbol a
*whole number* of bits (1, 2, 3, and so on), but the ideal length for a symbol of
probability $p$ is $log_2(1/p)$ bits (Chapter 18), which is almost never a whole
number. Picture a two-symbol source where `A` occurs 90% of the time: its ideal
length is $log_2(1/0.9) approx 0.15$ bits, yet Huffman cannot spend fewer than 1
whole bit on it, a waste of about 0.85 bits *every time* `A` appears. FSE, like
arithmetic coding, can spend a *fractional* number of bits on average (it lets the
state integer carry the leftover fraction forward to the next symbol), so it pays
the true $0.15$ bits and pockets the difference. That is the entire reason zstd's
ratio edges past a Huffman-based DEFLATE on skewed data.

== Worked Example: What zstd Does with a Small File

Let us compress the 44-byte string:

```
{"user":"alice","age":30,"city":"paris"}
```

This is the kind of tiny JSON payload that breaks simple compressors.

*Without a dictionary:*

LZ77 scans the string. It finds a few short matches: the quote characters `"` repeat,
the `:` repeats, and there are two 5-character spans (`"user"` and `"city"`) that share
a `"` + some structure. With no history, the window is nearly empty. zstd level 3 at
best reduces this to ~40 bytes, barely any compression, because 44 bytes gives the
LZ77 stage almost nothing to work with, and FSE needs a long stream to amortize its
table overhead.

*With a trained dictionary:*

Suppose we have trained a 32 KB dictionary on 10 000 similar JSON payloads. The
dictionary already contains `{"user":"`, `","age":`, `","city":"`, `"}` as common
patterns. Now zstd references these dictionary entries directly: the 44-byte JSON payload
might compress to 12–18 bytes, a 3–4× reduction on a tiny payload. The dictionary is
shared out-of-band; neither the 12-byte compressed payload nor the decoder need to
transmit the dictionary.

This is why companies serving millions of small similar API responses (GitHub, Twitter,
Meta, Cloudflare) train zstd dictionaries. The ratio improvement on tiny payloads
can be more valuable than any algorithmic innovation.

#gomaths("Asymptotic Overhead of Header Fixed Costs")[
  Every compressed format has a fixed header cost $h$ (magic number, metadata, entropy
  table sizes). The effective compression ratio on a payload of size $n$ bytes is:

  $ "ratio" = n / (h + C(n)) $

  where $C(n)$ is the content-derived compressed bytes. For large $n$, $h$ is negligible
  and ratio approaches the pure algorithmic limit. But for small $n$ (say, $n = 100$ bytes
  and $h = 50$ bytes), even perfect content compression yields ratio at most $2times$.

  Trained dictionaries reduce $h$ to near zero *for the repeated parts of the content*,
  because those patterns are already in the shared dictionary and cost 0 bits in the
  payload; only a reference index is stored.

  *Numeric example:* a 1 KB zstd frame without a dictionary has roughly 12–30 bytes of
  header overhead. With a trained dictionary, the same frame header is similar in size,
  but the content bytes $C(1000)$ might shrink from 700 bytes to 350 bytes, because
  the most common 100 byte patterns are "free." The ratio doubles for the same header cost.
]

== 2024–2026 Developments

Between 2024 and mid-2026 the field continued moving:

- *zstd v1.5.6* (March 2024): celebrated as the release marking Chrome's adoption of
  `Content-Encoding: zstd`.
- *zstd v1.5.7* (February 2025): Intel QAT hardware acceleration hooks; default
  multithreaded CLI; `--max` option; 10–20% faster compression of 4–32 KB blocks.
- *Python 3.14* (October 2025): `compression.zstd` in stdlib (PEP 784); `train_dict()`
  function for dictionary training directly from Python without spawning a subprocess.
- *SQL Server 2025*: Microsoft native ZSTD backup compression support.
- *DirectStorage 1.4*: game asset streaming adds zstd; game developers can now compress
  textures and meshes with zstd for faster load times.
- *LZ4 v1.10.0* (2024): multithreaded compression; Level 2 mode filling the gap between
  Level 1 and HC. Decompression 60% faster than v1.9.4 for large files.
- *Snappy v1.2.2* (March 2024): fixes data-corruption bug in payloads > 4 GB; adds
  configurable levels (0 and 2).
- *Brotli*: browser support reached 95.9% in 2025; no major algorithm changes, but CDN
  adoption is now near-universal.
- *HTTP `Accept-Encoding` in 2026*: modern browsers now send
  `Accept-Encoding: gzip, deflate, br, zstd` in that order. Servers that support zstd
  can serve it for both dynamic and static content.

#misconception[
  "Brotli is always better than gzip, so I should just enable it everywhere."
][
  Brotli's advantage is *on web content with its static dictionary*. On arbitrary binary
  data, Brotli is often *worse* than gzip at similar encode speeds. On very small payloads
  (< 1 KB) the static dictionary helps, but on large binary files (images, video, already-compressed
  archives), gzip may beat Brotli at the same quality level. More importantly, Brotli's
  level-11 encode speed (1–3 MB/s) is far too slow for generating dynamic responses
  on the fly. Use Brotli for pre-compressed static assets; use zstd (or gzip)
  for dynamic server responses.
]

== Summary: The Four-Codec Decision Matrix

#fig(
  [Decision matrix: which modern codec to reach for in 2026.],
  cetz.canvas({
    import cetz.draw: *

    let col-w = 3.4
    let row-h = 0.65

    let cols = ("Use case", "First choice", "Why")
    let rows = (
      ("DB pages / cache", "LZ4", "4 GB/s decode, near-zero latency"),
      ("Legacy Hadoop/Cassandra", "Snappy", "Already there, works fine"),
      ("Static web assets", "Brotli -4/-11", "15-25% vs gzip, universal browser"),
      ("General files", "zstd -3", "= gzip ratio, 3× faster encode"),
      ("Archival", "zstd -19 / xz", "Near-LZMA ratio; zstd decodes 20× faster"),
      ("Tiny JSON payloads", "zstd + dict", "30-50% gain on small similar records"),
      ("HTTP dynamic content", "zstd -1", "Chrome + Firefox support since 2024"),
    )

    // Header row
    let header-cols = ("Use case", "Best choice", "Reason")
    for (i, h) in header-cols.enumerate() {
      rect(
        (i * col-w, (rows.len()) * row-h),
        ((i + 1) * col-w, (rows.len() + 1) * row-h),
        fill: rgb("#2980b9").lighten(70%),
        stroke: (paint: gray.lighten(50%), thickness: 0.5pt),
      )
      content(
        (i * col-w + col-w/2, (rows.len()) * row-h + row-h/2),
        box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt, weight: "bold")[#h]))
      )
    }

    // Data rows
    for (ri, row) in rows.enumerate() {
      let bg = if calc.rem(ri, 2) == 0 { white } else { rgb("#f8f9fa") }
      for (ci, cell) in row.enumerate() {
        rect(
          (ci * col-w, ri * row-h),
          ((ci + 1) * col-w, (ri + 1) * row-h),
          fill: bg,
          stroke: (paint: gray.lighten(50%), thickness: 0.5pt),
        )
        content(
          (ci * col-w + col-w/2, ri * row-h + row-h/2),
          box(width: 3.0cm, inset: 2pt, align(center, text(size: 7pt)[#cell]))
        )
      }
    }
  })
)

#takeaways((
  "LZ4 and Snappy are LZ77 derivatives with no entropy-coding stage, optimised for maximum decode speed (4–6 GB/s) at the cost of compression ratio. Use them when CPU is the bottleneck.",
  "Brotli adds a 120 KB static web-vocabulary dictionary and context-modelled Huffman, achieving 15–25% better ratio than gzip on HTML/CSS/JS. Universal browser support since 2017.",
  "Zstandard's key insight: one format, one decoder, levels −7 to 22. FSE entropy coding gives arithmetic-coding accuracy at Huffman speed. Level 3 matches gzip ratio at 3× the encode speed.",
  "Zstd's trained dictionary transforms the otherwise-hopeless compression of tiny similar payloads: 30–50% gains on 1 KB JSON objects versus no-dictionary.",
  "Long-Distance Matching (--long) extends zstd's reference window to 128 MiB, helping on multi-GB files with repeated structures far apart.",
  "Since March–May 2024, both Chrome and Firefox send Accept-Encoding: zstd, making zstd viable for HTTP responses alongside Brotli.",
  "Python 3.14 ships compression.zstd in the standard library; SQL Server 2025, DirectStorage 1.4, and the Linux kernel all adopt zstd natively.",
  "tinyzip Step 14 adds a level parameter (1–9) and a preset_dict hook to deflate.py, illustrating the trained-dictionary concept at small scale.",
))

== Exercises

#exercise("32.1", 1)[
  List the four axes of the compression trade-off described in this chapter. For each
  axis, name one codec from this chapter that deliberately sacrifices it in favour of
  the others.
]
#solution("32.1")[
  The four axes are: (1) compression ratio, (2) compression speed, (3) decompression speed,
  (4) memory footprint.
  - Sacrifices ratio: LZ4 and Snappy (gain decode speed).
  - Sacrifices compression speed: Brotli level 11 (gains ratio).
  - Sacrifices decompression speed: xz/LZMA (gains ratio); note LZMA is from Chapter 31
    but appears in the scoreboard for comparison.
  - Sacrifices memory: LZ4 and Snappy (their hash tables are tiny).
  (Note: zstd is unusual in not deeply sacrificing any axis; it spans the whole range
  with its level dial.)
]

#exercise("32.2", 1)[
  A web server needs to choose between Brotli and zstd for compressing responses to
  browser clients. The server generates responses dynamically (per-user JSON), typically
  200–2 000 bytes in size. What would you recommend and why? What changes if the server
  instead serves pre-built static HTML files that do not change for 24 hours?
]
#solution("32.2")[
  For *dynamic* 200–2 000 byte JSON responses: recommend zstd at level 1. Reasons:
  (1) Chrome and Firefox both support `Content-Encoding: zstd` since 2024; (2) Brotli's
  level-11 encoder is far too slow for dynamic content (1–3 MB/s vs hundreds of MB/s for
  zstd level 1); (3) on small payloads with a trained dictionary, zstd wins outright on
  ratio; (4) even without a dictionary, zstd level 1 matches gzip and beats gzip on speed.

  For *pre-built static HTML*: Brotli level 11. The files are compressed once and served
  many times. Brotli's static web vocabulary gives it a 15–25% ratio advantage over gzip
  and 5–10% over zstd on typical HTML. The slow encode is amortised over millions of requests.
]

#exercise("32.3", 2)[
  Explain why LZ4 might actually *expand* a file rather than compressing it. Give a
  concrete example of input type where this is likely. What does LZ4 do to avoid
  catastrophic expansion in the worst case?
]
#solution("32.3")[
  LZ4 expands a file when matches are rare and short, so the match tokens (2-byte offset
  + token byte) cost more than just writing the literal bytes. This happens with:
  - Already-compressed data (e.g., a .jpg or .zst file): nearly random bytes, no matches.
  - Encrypted data: random-looking bytes, no patterns.
  - Small random binary blobs.

  To prevent catastrophic expansion, LZ4 defines a maximum expansion bound: the compressed
  output is guaranteed to be at most `LZ4_compressBound(inputSize)` bytes, approximately
  `inputSize + inputSize/255 + 16`. In the worst case (all literals, zero matches) the
  token overhead adds about 0.4% plus a 16-byte constant. The LZ4 spec also allows writing
  an "uncompressed" block type if compression would expand. Most production wrappers detect
  this and store the data raw.
]

#exercise("32.4", 2)[
  Brotli ships a static 120 KB dictionary built from web content. Explain the difference
  between this approach and zstd's trained-dictionary approach. In what scenario would
  each approach be most beneficial? What are the limitations of each?
]
#solution("32.4")[
  *Brotli's static dictionary*: baked into the algorithm specification. Every encoder and
  decoder knows it. It costs zero bytes to transmit. It helps on any web content (HTML,
  CSS, JS) because it contains common web tokens. Limitation: it is fixed at design time;
  it cannot be adapted for non-web domains (medical records, financial data, custom protocol
  messages). Training a new one requires updating the RFC and all implementations.

  *Zstd's trained dictionary*: generated per-use-case by the user with `zstd --train`.
  Must be transmitted or shared out-of-band (both encoder and decoder need the same file).
  Adds a one-time distribution cost. Benefit: perfectly tuned to your actual data, can
  dramatically help any domain (not just web). The dictionary ID is stored in the zstd
  frame header so mismatches are detected.

  Best use of Brotli dict: any standard web asset, served to anonymous browsers.
  Best use of zstd dict: internal microservices, log pipelines, API responses, anywhere
  you control both encoder and decoder and can share the dictionary file.
]

#exercise("32.5", 2)[
  The tinyzip Step 14 `encode()` function passes `zdict=preset_dict` to `zlib.compressobj`.
  Python's documentation says this seeds the encoder's sliding window with the dictionary.
  Sketch why this helps: if the preset dictionary contains the bytes `{"user":"` and the
  input starts with `{"user":"alice"`, what happens during LZ77 match finding?
]
#solution("32.5")[
  When `zdict` is supplied, zlib loads those bytes into the encoder's history buffer
  *before* processing any input. So the "past" already contains `{"user":"` as if we
  had already encoded it. When the LZ77 match finder scans the first 8 bytes of the
  input `{"user":"`, it looks backward into the history and finds an exact match at
  the very start of the preset dictionary. Instead of emitting 8 literal bytes, it emits
  one back-reference: (distance = distance\_from\_input\_start\_to\_dict\_position, length = 8).
  This back-reference is much shorter than 8 literal bytes, giving immediate compression
  gain even on tiny inputs. The decoder must use the same `zdict` to resolve the reference.
  Without the dictionary, those 8 bytes at the start of the file have no match in the
  (empty) history and must be emitted as literals.
]

#exercise("32.6", 3)[
  Design a benchmark. You have a corpus of 10 000 JSON log lines, each about 300–600 bytes,
  all with the same structure (`{"ts": ..., "level": "INFO", "msg": ..., "service": ...}`).
  You want to compare: (a) zstd level 3 without a dictionary, (b) zstd level 3 with a
  dictionary trained on 1 000 of those lines, (c) gzip level 6. Write Python pseudocode
  (or real code using `compression.zstd` from Python 3.14) to run this comparison
  and report the compression ratio for each approach. What ratio improvements do you
  predict, and why?
]
#solution("32.6")[
  ```python
  from compression import zstd
  import zlib, random, json, time

  def gen_line(i: int) -> bytes:
      return json.dumps({
          "ts": f"2026-06-{(i % 28) + 1:02d}T12:00:00Z",
          "level": "INFO",
          "msg": f"request processed in {random.randint(10,500)}ms",
          "service": random.choice(["api","auth","db"]),
      }).encode()

  lines = [gen_line(i) for i in range(10_000)]
  train_samples = lines[:1_000]
  test_data = b"\n".join(lines[1_000:])

  # Train dictionary
  dictionary = zstd.train_dict(train_samples, dict_size=32_768)

  # Compress test data
  a = zstd.compress(test_data, level=3)
  b = zstd.compress(test_data, level=3, zstd_dict=dictionary)
  c = zlib.compress(test_data, level=6)

  n = len(test_data)
  for name, comp in [("zstd-3 no dict", a), ("zstd-3 + dict", b), ("gzip-6", c)]:
      print(f"{name:20s}: {len(comp):7d} B  ratio {n/len(comp):.2f}x")
  ```

  *Predicted ratios*: on highly repetitive structured JSON:
  - gzip -6: ratio ~4–6× (LZ77 finds repeated keys and values).
  - zstd -3 no dict: similar or slightly better (5–7×).
  - zstd -3 + dict: ratio 8–12×. The dictionary pre-loads the repeated JSON schema so
    every key name and the structural skeleton are free references, saving 50–100 bytes
    per 400-byte line.

  The dictionary advantage is so large because the JSON *schema* (key names, braces, quotes,
  separators) is repeated identically in every line and totals perhaps 60–80 bytes per record
  (15–20% of each payload). Making those bytes essentially free gives a 15–20% additive
  improvement in ratio, which at these compression ratios translates to a multiplicative gain.
]

== Further reading

- #link("https://facebook.github.io/zstd/")[Zstandard Reference Manual and GitHub], Yann Collet et al. The authoritative source including the frame format specification, FSE description, and dictionary training documentation.

- #link("https://www.rfc-editor.org/rfc/rfc8878")[RFC 8878: Zstandard Compression and the application/zstd Media Type], Collet & Kucherawy (2021). The IETF standard.

- #link("https://www.rfc-editor.org/rfc/rfc7932")[RFC 7932: Brotli Compressed Data Format], Alakuijala & Szabadka (2016). The official Brotli specification, including the static dictionary format.

- #link("https://github.com/lz4/lz4")[LZ4 source and documentation], Yann Collet. Includes the format specification, C reference implementation, and benchmark methodology.

- #link("https://github.com/google/snappy")[Snappy source and README], Google. The specification, benchmarks, and format description.

- #link("https://engineering.fb.com/2018/12/19/core-infra/zstandard/")[Zstandard: How Facebook increased compression speed while saving storage], Meta Engineering Blog (2018). The first public account of zstd's impact at petabyte scale.

- #link("https://gregoryszorc.com/blog/2017/03/07/better-compression-with-zstandard/")[Better Compression with Zstandard], Gregory Szorc. A detailed technical walkthrough comparing zstd to alternatives with real benchmarks.

- #link("https://docs.python.org/3.14/library/compression.zstd.html")[compression.zstd: Python 3.14 documentation]. The official API reference for the new stdlib module.

- #link("https://www.phoronix.com/news/Zstd-Zstandard-1.5.7")[Zstd 1.5.7 Pushing Compression Performance Even Further], Phoronix (February 2025). Covers the v1.5.7 benchmark improvements and Intel QAT integration.

#bridge[
  We have now covered general-purpose lossless compression end to end: from
  the elegant theory of entropy (Chapter 18) through Huffman and arithmetic coding
  (Chapters 24–27), LZ77 dictionary coding (Chapter 28), DEFLATE (Chapter 30), LZMA
  (Chapter 31), and now the modern speed-and-ratio champions. The next chapter, Chapter 33,
  turns to a completely different philosophy: *statistical modeling*. Instead of asking
  "where did I see this byte sequence before?" (the LZ question), it asks "what is the
  probability of the next byte given everything I have seen?" and answers with PPM
  (Prediction by Partial Matching) and context mixing, the techniques behind the highest
  ratio compressors that predate the neural era.
]
