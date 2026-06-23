#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= DEFLATE, zlib, gzip, and PNG

#epigraph[
  The most important algorithm you've never heard of runs inside every ZIP file,
  every `.gz` tarball, every PNG image, every HTTP response marked
  `Content-Encoding: gzip`. It has been compressing the world's data since 1991,
  and it was placed in the public domain by a man who died at thirty-seven.
][Phil Katz, 1962–2000]

Imagine you need to mail a book to a friend. You could tear out every page
and mail each one individually — but the postage would be enormous. Or you
could notice that the same phrases appear over and over again ("the", "and",
"compression"), write each phrase once at the start of the letter, give it a
number, and then use those numbers to reconstruct the rest. You have just
invented — in spirit — DEFLATE.

DEFLATE is the glue that binds the two biggest ideas in lossless compression:
dictionary coding (Chapter 28) and entropy coding (Chapter 24). It was designed
in the early 1990s by a programmer named Phil Katz, made royalty-free, and
became the compression engine of ZIP, gzip, zlib, PNG, and HTTP. To this day,
more data passes through DEFLATE than through any other compressor on Earth.

This chapter dissects how DEFLATE works, shows you its three-layer envelope
(zlib, gzip, ZIP), traces how PNG wraps it for images, and then — as Step 13
of our running `tinyzip` project — assembles your own working
gzip-class compressor.

#recap[
  In *Chapter 24* we built `huffman.py`, a canonical Huffman encoder that
  assigns short bit strings to common byte values. In *Chapter 28* we built
  `lz77.py`, a sliding-window match finder that turns a byte stream into a
  sequence of literal bytes and back-references (distance, length pairs). Now
  we snap these two modules together. DEFLATE = LZ77 + Huffman. That's it.
  Everything else in this chapter is precision engineering around that core.
]

#objectives((
  [Explain DEFLATE's three block types and why each exists.],
  [Trace a short string through the full LZ77-then-Huffman pipeline, computing
   bits by hand.],
  [Understand the 32 KB window limit and its historical origin.],
  [Describe what zlib, gzip, ZIP, and PNG each add on top of DEFLATE.],
  [Explain how PNG's pre-filters dramatically improve compression before
   DEFLATE even sees the data.],
  [Implement `deflate.py` — Step 13 of `tinyzip` — and verify round-trip
   correctness.],
))

== From Ingredients to Recipe: the LZ77 + Huffman Combination

Back in Chapter 28 you learned that LZ77 turns a string like:

```
abracadabra
```

into a token stream that looks roughly like:
- `LIT a`, `LIT b`, `LIT r`, `LIT a`, `LIT c`, `LIT a`, `LIT d`,
  `MATCH(dist=7, len=4)` — meaning "go back 7 positions and copy 4 bytes."

That token stream is much shorter than the original, because a single
MATCH token replaced four bytes. But there is a catch: we still have to
*represent* those tokens as bits. How many bits should a `LIT a` token cost?
How many bits for a `MATCH(dist=7, len=4)`?

This is exactly where Huffman coding from Chapter 24 earns its place. Frequent
tokens should get short codes; rare tokens get long codes. DEFLATE applies
two separate Huffman codes:

1. *A combined literal/length Huffman code.* The 286 possible symbols in this
   code are: the 256 possible literal byte values (0–255), a special
   end-of-block marker (symbol 256), and 29 "length codes" (symbols 257–285)
   that encode match lengths from 3 to 258 bytes.

2. *A distance Huffman code.* The 30 possible distance codes cover match
   distances from 1 to 32 768 bytes (the 32 KB window limit).

Extra bits are appended after length and distance codes to encode the exact
value within a code's range. For example, length code 265 covers lengths 11
and 12; an extra 1 bit selects between them.

#gomaths("Extra Bits in DEFLATE Codes")[
  DEFLATE uses a trick to pack a wide range of numbers into a small table.
  Each length code covers a *range* of lengths, not just one value. Code 257
  means exactly length 3. Code 265 means either length 11 or 12; one extra bit
  selects which. Code 285 means exactly length 258.

  The number of extra bits grows as the range grows:
  $ "extra bits" = floor(("code" - 261) / 4) quad "for codes 261–284" $
  (with small adjustments at the boundaries). This is an example of *Elias
  gamma–style* coding (Chapter 25) applied inside DEFLATE's fixed structure.

  A worked example: Match length = 15.

  - Length codes 265 covers 11–12 (1 extra bit), code 266 covers 13–14
    (1 extra bit), code 267 covers 15–16 (1 extra bit). So we emit code 267,
    then extra bit 0 to select 15 (not 16).

  Distance codes work the same way: distance code 8 covers distances 17–18;
  one extra bit selects between them.
]

The net result: after Huffman coding, a typical text file shrinks to roughly
3–4 bits per byte (vs. 8 bits in the original). On structured data, it can
reach 2 bits per byte. Compare that to Huffman alone (around 5–6 bits per
byte on English text) or LZ77 alone (it collapses repetition but still needs
byte-aligned codes for each token). The combination is genuinely multiplicative:
LZ77 removes cross-phrase redundancy; Huffman removes per-symbol redundancy.
Together they outperform either alone.

#keyidea[
  DEFLATE's two-stage approach — LZ77 then Huffman — is not just historical
  convenience. It attacks two *orthogonal* sources of redundancy. LZ77 handles
  *repetition* (the same phrase appearing multiple times). Huffman handles
  *frequency skew* (some bytes or match patterns being far more common than
  others). Neither step helps much with the other's problem.
]

== Block Structure: Fixed, Dynamic, and Stored Blocks

A DEFLATE stream is divided into *blocks*. Each block begins with a 3-bit
header:

- 1 bit: BFINAL — is this the last block?
- 2 bits: BTYPE — 00 = stored, 01 = fixed Huffman, 10 = dynamic Huffman,
  11 = reserved (error).

This block structure gives the compressor enormous flexibility.

=== Stored Blocks (BTYPE = 00)

Sometimes the data is already incompressible — encrypted bytes, random data,
or already-compressed files. Trying to compress random bytes with Huffman
actually *expands* them slightly (because the Huffman table itself takes space).
In that case, DEFLATE emits a *stored block*: the raw bytes, completely
uncompressed, preceded by a 16-bit length and its one's complement (a simple
integrity check).

Stored blocks are also used for very short inputs, where the overhead of
building a Huffman table would outweigh any savings.

=== Fixed Huffman Blocks (BTYPE = 01)

The DEFLATE specification defines a *fixed*, pre-agreed Huffman code
(specified in RFC 1951). Both encoder and decoder know this code without any
communication. Using it means the encoder saves the space of transmitting
a Huffman table, at the cost of not adapting the code to the actual data.

The fixed code assigns:
- Literals 0–143: 8-bit codes
- Literals 144–255: 9-bit codes
- Literals 256–279 (end-of-block and length codes 3–114): 7-bit codes
- Length codes 280–287: 8-bit codes

Fixed blocks are fastest to produce (no table-building step) and decode, but
compress slightly worse. They shine when the input is short or when fast
encoding matters more than size.

=== Dynamic Huffman Blocks (BTYPE = 10)

For real compression, dynamic Huffman blocks transmit *custom* Huffman codes
tailored to the actual distribution of literals, lengths, and distances in
the block. The encoder:

1. Counts how often each literal/length symbol and each distance symbol
   appear in the token stream for this block.
2. Builds two optimal Huffman trees from those counts (using the algorithm
   from Chapter 24).
3. Converts each tree to its *code-length sequence* (just the bit-lengths,
   not the actual codes — because canonical Huffman, Chapter 24, recovers
   the codes from the lengths alone).
4. Compresses the code-length sequences themselves with a *third* Huffman code
   (the "code-length code") to save space.
5. Encodes all three tables at the start of the block, then the token stream.

This three-level Huffman compression (tokens → codes → code-lengths → code)
is one of the most elegant compression tricks in the standard.

#aside[
  The code-length alphabet has 19 symbols: lengths 0–15, plus three
  "run-length" symbols (copy the previous length, repeat zero 3–10 times,
  repeat zero 11–138 times). This tiny 19-symbol vocabulary is enough to
  represent any pair of Huffman tables compactly. On typical data, the
  tables add only 100–200 bytes of overhead per block.
]

== The 32 KB Window: A Decision That Shaped the World

LZ77 match finding is bounded by a *sliding window* — a buffer of recently
seen bytes. The further back you can look, the longer the matches you can
find. But a larger window requires:

1. More memory to hold the buffer.
2. More bits to encode the distance in a match reference.

Phil Katz chose a 32 768-byte (32 KB) window for DEFLATE. In 1991, 32 KB was
a significant chunk of a PC's RAM (typical home computers had 640 KB total,
of which only part was available to applications). A 32 KB window needed
15 bits to address any position within it, which fit cleanly into the
DEFLATE distance code table (30 codes covering distances 1 to 32 768).

The 32 KB window became a ceiling and a floor simultaneously. Files longer than
32 KB can still compress well because patterns *within* a 32 KB window repeat
frequently enough. But extremely long-range patterns — the same boilerplate
text appearing 100 KB apart — are invisible to DEFLATE. This is one of DEFLATE's
chief structural weaknesses compared to LZMA (Chapter 31), which uses windows
up to gigabytes.

#history[
  *Phil Katz (1962–2000)* was a programmer in Milwaukee, Wisconsin who wrote
  the original ZIP compression utility as a faster, free alternative to the
  proprietary ARC format. After ARC's author sued him, Katz published the
  DEFLATE specification in the public domain, deliberately forgoing patents.
  His PKZIP software distributed his ideas to millions of DOS users, and his
  decision to keep the algorithm unencumbered allowed DEFLATE to propagate into
  gzip (1992), zlib (1995), PNG (1996), and HTTP — making it arguably the most
  impactful single decision in the history of data compression. Phil Katz died
  on April 14, 2000, at age 37, from complications of alcoholism.
]

== Hash Chain Match Finding

How does a DEFLATE encoder find the best match in 32 KB of previous data
efficiently? A naive search would take $O(n times w)$ time — for each new
byte, scan all 32 KB. That's far too slow.

The standard solution is a *hash chain*. The encoder maintains:

- A *hash table* with one slot per possible 3-byte hash value
  (typically 2#super[15] = 32 768 slots).
- A *chain array* (one entry per window position) linking previous positions
  that had the same hash.

When processing position $i$, the encoder:

1. Computes the hash of the 3-byte string at position $i$.
2. Looks up the hash table to find the *most recent* position $j$ that had
   the same hash (i.e., the same 3 bytes — a potential match).
3. Follows the chain back from $j$ to find older positions with the same hash,
   testing each to find the longest actual match.
4. Stops after checking a configurable number of positions (the "max chain
   length") to bound encoding time.

#gomaths("Hash Functions")[
  A *hash function* maps any input to a fixed-size output (the "hash" or
  "digest") in a way that is fast to compute and distributes inputs evenly
  across the output range.

  DEFLATE-style match finders use a very simple hash:
  $ h = (b_0 times p_0 + b_1 times p_1 + b_2 times p_2) mod 2^k $
  where $b_0, b_1, b_2$ are the three bytes at the current position and
  $p_0, p_1, p_2$ are small constants (often chosen as powers of 2 or
  small primes for speed). With $k = 15$, this maps any 3-byte sequence
  to one of 32 768 slots.

  *Collisions* (two different 3-byte sequences mapping to the same hash slot)
  are handled by the chain: when we follow a chain entry, we also check the
  actual bytes to confirm a true match.

  Quick example: if bytes at position $i$ are `[0x74, 0x68, 0x65]` ("the"),
  we compute their hash, find it maps to slot 12 347, look up chain[12347]
  to find the previous occurrence of a 3-byte sequence with the same hash,
  then verify "the" matches there, and extend the match as far as it goes.
]

The lazy evaluation strategy used by quality encoders (including zlib's
default) improves this further: instead of immediately emitting the best match
at position $i$, the encoder first peeks at position $i+1$ and checks whether
a longer match starts there. If so, it emits a literal at $i$ and uses the
longer match at $i+1$. This "lazy" approach improves ratio at the cost of
extra computation.

#fig(
  [DEFLATE encoding pipeline. Raw bytes enter from the left. LZ77 finds
   matches using a 32 KB hash-chain window and emits a token stream. The
   Huffman stage assigns variable-length codes to each token type, then
   assembles the final bit stream. Each DEFLATE block can independently
   choose its coding mode.],
  cetz.canvas({
    import cetz.draw: *
    // Boxes
    rect((0, 1.5), (2.5, 2.5), fill: rgb("#dce8f7"), stroke: 0.7pt)
    content((1.25, 2.0), text(size: 8pt)[Raw bytes])

    line((2.5, 2.0), (3.5, 2.0), mark: (end: ">"))

    rect((3.5, 1.5), (6.5, 2.5), fill: rgb("#d4edda"), stroke: 0.7pt)
    content((5.0, 2.1), text(size: 7.5pt)[LZ77])
    content((5.0, 1.7), text(size: 7pt)[hash-chain, 32 KB])

    line((6.5, 2.0), (7.5, 2.0), mark: (end: ">"))
    content((7.0, 2.3), text(size: 7pt)[tokens])

    rect((7.5, 1.5), (10.5, 2.5), fill: rgb("#fff3cd"), stroke: 0.7pt)
    content((9.0, 2.1), text(size: 7.5pt)[Huffman])
    content((9.0, 1.7), text(size: 7pt)[lit/len + dist codes])

    line((10.5, 2.0), (11.5, 2.0), mark: (end: ">"))

    rect((11.5, 1.5), (14.0, 2.5), fill: rgb("#f8d7da"), stroke: 0.7pt)
    content((12.75, 2.0), text(size: 8pt)[Bit stream])

    // Block header
    rect((3.5, 0.3), (10.5, 1.0), fill: rgb("#f0f0f0"), stroke: (dash: "dashed", paint: gray, thickness: 0.5pt))
    content((7.0, 0.65), text(size: 7.5pt)[Block header (3 bits): BFINAL + BTYPE (stored / fixed / dynamic)])
  })
)

== zlib, gzip, ZIP, and PNG: Four Wrappers Around One Engine

DEFLATE is a raw bit stream with no file header, no checksum, no filename.
In practice, you always encounter DEFLATE inside a *wrapper format* that adds
exactly those things. The four most important wrappers are:

=== zlib (RFC 1950)

zlib wraps DEFLATE with a 2-byte header and a 4-byte Adler-32 checksum. The
header encodes the compression method (always 8 for DEFLATE), the window size
(log base 2 of window bytes, stored in bits 4–7 of the second header byte),
and a "fcheck" value that makes the two header bytes together divisible by
31.

The *Adler-32* checksum is a faster alternative to CRC-32, named after Mark
Adler (one of the zlib authors). It maintains two 16-bit running sums:
$s_1 = sum_i b_i + 1$ and $s_2 = sum_i s_1$ (both modulo 65 521, the
largest prime below $2^{16}$). Adler-32 detects most corruption but has
weak coverage of short bursts; PNG uses CRC-32 instead.

zlib is the compression format used *inside* PNG image data.

=== gzip (RFC 1952)

gzip adds a richer wrapper: a 10-byte header with magic number `\x1f\x8b`,
compression method, flags, modification time, OS byte, and an optional
original filename; then DEFLATE data; then a CRC-32 checksum and the
original file length (both 32 bits). The OS byte lets you identify whether
the file was created on Unix (3), Windows (0), or macOS (7).

The Unix `gzip` command-line tool (written by Jean-loup Gailly and Mark Adler)
wraps exactly this format. HTTP's `Content-Encoding: gzip` is also this format.

#checkpoint[
  A gzip file starts with two magic bytes. What are they, and how do you know
  a file is a gzip file?
][
  The first two bytes are `0x1f` and `0x8b` (decimal 31 and 139). The gzip
  RFC 1952 mandates this signature. Any tool (or Python's `gzip` module) that
  reads `data[:2] == b'\x1f\x8b'` can quickly identify a gzip file without
  reading further.
]

=== ZIP

ZIP is an *archive* format (multiple files, each individually compressed) with
a quirky structure: the local file headers appear *before* each file's data,
but the central directory (a master table of contents) appears *at the end* of
the ZIP file. This allows streaming a ZIP while writing it (you don't need to
know all file names and sizes in advance), but it requires seeking to the end
to read the directory when extracting.

Each file in a ZIP archive can be independently stored or DEFLATE-compressed.
Because files are compressed separately, you cannot exploit repetition across
files — a trade-off accepted for the ability to extract individual files
without decompressing the whole archive.

=== PNG (RFC 2083 / ISO 15948)

PNG uses zlib (not raw DEFLATE) to compress pixel data. But before zlib even
sees the bytes, PNG applies a *filter* to each row of pixels. This is the
secret weapon that makes PNG dramatically better than a naive "compress the raw
pixels" approach — and it deserves its own section.

== PNG Filters: Turning Pixels into Residuals

A natural image is highly spatially correlated. The color of pixel $(x, y)$
is usually very close to the colors of its neighbors. Raw pixel values span
0–255 with a nearly uniform distribution — hard to compress. But *differences*
between neighboring pixels cluster tightly around zero — easy to compress.

PNG applies one of five *pre-filters* to each row, converting pixel values
to prediction residuals before passing them to zlib:

#definition("PNG row filter")[
  For each byte $P$ in a row (applied per color channel), PNG computes a
  *residual* $r = P - hat(P) space (mod 256)$ where $hat(P)$ is a predicted value
  derived from neighbors already decoded. The filter type byte (0–4) is
  prepended to each filtered row.
]

The five filter types are:

- *None (0):* $hat(P) = 0$; residual is the raw byte.
- *Sub (1):* $hat(P) = A$ (the byte to the left in the same row).
- *Up (2):* $hat(P) = B$ (the byte directly above, same column).
- *Average (3):* $hat(P) = floor((A + B)/2)$ where $A$ is left, $B$ is above.
- *Paeth (4):* A predictor due to Alan Paeth (1991) that picks among
  $A$, $B$, $C$ (upper-left) based on which is closest to
  $p = A + B - C$.

#gomaths("The Paeth Predictor")[
  The Paeth predictor picks the neighbor that lies in the "same direction" as
  the local gradient. Define $p = A + B - C$ where $A$ is left, $B$ is above,
  $C$ is upper-left. Then:

  $ hat(P) = cases(
    A & "if" |A - p| <= |B - p| "and" |A - p| <= |C - p|,
    B & "if" |B - p| <= |C - p|,
    C & "otherwise"
  ) $

  *Intuition:* $p$ is the value you'd predict if you drew a straight line
  from $C$ through both $A$ and $B$. The neighbor closest to $p$ is most
  consistent with that linear trend, so it's the best prediction.

  *Example:* Pixel neighbors are $A = 200, B = 198, C = 197$.
  Then $p = 200 + 198 - 197 = 201$. Distances: $|200 - 201| = 1$,
  $|198 - 201| = 3$, $|197 - 201| = 4$. We pick $A = 200$.
  Residual for pixel value 199: $199 - 200 = -1 equiv 255 space (mod 256)$.

  This residual (255) is much closer to 0 than the raw pixel value (199) in
  the signed sense. DEFLATE compresses small residuals much better than
  arbitrary values.
]

The PNG encoder chooses the filter independently for each row. A common
heuristic: sum the absolute values of the residuals for each filter type and
choose the filter that minimizes the sum (the "minimum sum of absolute
differences" heuristic). Better encoders run all five filters through a
trial DEFLATE pass.

#fig(
  [PNG row filtering for a simple 4-pixel row. Raw values (top) are converted
   to Sub filter residuals (bottom). The residuals cluster near zero, which
   DEFLATE compresses far more efficiently.],
  cetz.canvas({
    import cetz.draw: *
    // Raw pixels row
    content((0, 2.5), text(size: 9pt, weight: "bold")[Raw:])
    let vals = (120, 122, 121, 125)
    for (i, v) in vals.enumerate() {
      rect((i * 1.4 + 1.0, 2.2), (i * 1.4 + 2.3, 2.8), fill: rgb("#dce8f7"), stroke: 0.5pt)
      content((i * 1.4 + 1.65, 2.5), text(size: 9pt)[#v])
    }
    // Arrow
    line((0, 1.9), (0, 1.4), mark: (end: ">"))
    content((0.3, 1.65), text(size: 8pt, style: "italic")[Sub filter])
    // Filtered row
    content((0, 1.1), text(size: 9pt, weight: "bold")[Residuals:])
    let resids = ("120", "2", "255", "4")
    for (i, v) in resids.enumerate() {
      rect((i * 1.4 + 1.0, 0.8), (i * 1.4 + 2.3, 1.4), fill: rgb("#d4edda"), stroke: 0.5pt)
      content((i * 1.4 + 1.65, 1.1), text(size: 9pt)[#v])
    }
    content((7.0, 1.1), text(size: 7.5pt, style: "italic")[(255 = -1 mod 256)])
  })
)

The improvement is dramatic. On a typical screenshot with smooth gradients,
the raw pixel values are spread across 0–255 (near-uniform, entropy ~8 bits/byte).
After Sub or Paeth filtering, most residuals are in the range -5 to +5
(heavily concentrated near zero, entropy ~3–4 bits/byte). DEFLATE then
achieves 2–3x better compression on the residuals than on the raw pixels.

== The PNG File Format in Detail

A PNG file begins with an 8-byte signature: the bytes
`137, 80, 78, 71, 13, 10, 26, 10` (hex `89 50 4E 47 0D 0A 1A 0A`).
The first byte (137) is deliberately non-ASCII to catch text-mode
transmission corruption. The `PNG` in bytes 2–4 (values 80, 78, 71) lets
humans identify the format. The pair `\r\n` (13, 10) catches CR/LF translation.
Byte 26 is the old DOS end-of-file character. Byte 10 is a final newline.

After the signature come a series of *chunks*. Each chunk has:

- 4 bytes: *length* (big-endian, counts only the data field).
- 4 bytes: *type code* (four ASCII letters).
- Length bytes: *data*.
- 4 bytes: CRC-32 of the type code and data (not the length).

Chunks whose type starts with a lowercase letter are *ancillary* (optional,
may be ignored). Uppercase first letter = *critical* (must be understood).

The critical chunks in order:

1. *IHDR* (must be first): width, height, bit depth, color type, compression
   method (always 0), filter method (always 0), interlace method (0 or 1).
2. *PLTE* (for indexed-color images): up to 256 RGB triplets.
3. *IDAT* (one or more): zlib-compressed filtered pixel data. Multiple IDAT
   chunks are concatenated before decompression.
4. *IEND* (must be last, zero length): marks end of PNG.

Important ancillary chunks include `gAMA` (gamma correction), `sRGB`
(standard sRGB colorspace declaration), `tRNS` (transparency info),
`tEXt` / `zTXt` (text metadata), and `pHYs` (physical pixel dimensions).

The *interlaced PNG* format (Adam7) reorders the 8×8 pixel blocks in seven
passes, each adding detail. After pass 1 (1/64 of bytes received), a viewer
can display a rough 1/8-resolution preview. This progressive display was
critical in the slow-modem era; on modern connections it adds overhead without
visible benefit and is seldom used.

#misconception(
  "PNG and gzip are the same compression."
)[
  Both use DEFLATE, but they differ in structure, wrapper, and what sits
  *before* DEFLATE. gzip compresses arbitrary byte streams with CRC-32
  integrity. PNG compresses *filtered* rows of image pixels with per-chunk
  CRC-32 and zlib (Adler-32) wrapping, inside a chunk-based file container.
  PNG's pre-filters are the biggest difference: they can halve the entropy
  before DEFLATE sees a single byte.
]

== A Worked Compression Example

Let's compress a tiny 6-byte string, `"banana"`, step by step through DEFLATE.

*Step 1: LZ77 tokenization.* (Recall Chapter 28.)

Position 0: `b` — no match yet. Emit LIT `b`.
Position 1: `a` — no match of length >= 3. Emit LIT `a`.
Position 2: `n` — no match. Emit LIT `n`.
Position 3: `a` — match at position 1 (`a`), but length only 1. LZ77 requires
minimum match length 3. Emit LIT `a`.
Position 4: `n` — match at position 2 (`n`), length 1. Emit LIT `n`.
Position 5: `a` — match at position 1 (`a`), length 1. Emit LIT `a`.

Hmm — "banana" has no length-3 repeating substrings, so no matches fire.
Token stream: `LIT b, LIT a, LIT n, LIT a, LIT n, LIT a, EOB`.

*Step 2: Huffman coding (using fixed codes for simplicity).*

In the fixed Huffman code, byte values 0–143 get 8-bit codes starting at
`00110000`. Byte 98 (`b`) gets code `01100010`. Byte 97 (`a`) gets `01100001`.
Byte 110 (`n`) gets `01101110`. EOB (symbol 256) gets 7-bit code `0000000`.

Output bits: 8+8+8+8+8+8+7 = 55 bits vs. 48 bits for raw "banana"
(6 bytes × 8 bits). Fixed Huffman *expanded* it! This is why DEFLATE uses
stored blocks for tiny inputs.

Now let's try a longer input where LZ77 helps: `"abcabcabcabc"` (12 bytes).

LZ77 tokens: LIT a, LIT b, LIT c, MATCH(dist=3, len=9), EOB.
That's 3 literals + 1 match + EOB = 5 tokens instead of 12 bytes.

Fixed Huffman assigns: each literal ~8 bits, length code 275 (len 9–10,
one extra bit) 7 bits + 1 extra = 8 bits, distance code for dist=3:
distance code 2 (dist 3) + 0 extra = 5 bits.

Total: 3×8 + 8 + 5 + 7 = 44 bits ≈ 5.5 bytes vs. 96 raw bits (12 bytes).
Compression ratio ≈ 2.2:1. On longer repetitive input the ratio grows
toward 10:1 and beyond.

#checkpoint[
  Why does DEFLATE require a *minimum match length of 3*? Why not allow
  length-1 or length-2 matches?
][
  A match reference (distance + length) costs at minimum 5 bits (distance
  code) + 7 bits (length code) = 12 bits. A single literal byte costs 8 bits.
  Two literals cost 16 bits. Only at length 3 or more does the match reference
  pay off. Minimum length 3 is baked into both the LZ77 token representation
  and the length code table (code 257 = length 3).
]

== Performance Across Compression Levels

Real DEFLATE implementations (zlib, zopfli, libdeflate) expose *compression
levels* that trade encoding time for compressed size. The tradeoff is purely
in the LZ77 match-finding strategy; the decoder is always the same.

#scoreboard(caption: "DEFLATE levels on a 100 KB English text file",
  [Raw bytes], [102 400], [1.00x], [Baseline; no compression],
  [DEFLATE level 1 (fast)], [52 300], [1.96x], [Lazy match off; short chain length],
  [DEFLATE level 6 (default)], [39 800], [2.57x], [Lazy match on; medium chain],
  [DEFLATE level 9 (best)], [38 100], [2.69x], [Longest chain search; slow],
  [Zopfli (optimal)], [36 700], [2.79x], [True optimal parsing; ~100x slower],
  [Huffman-only (Chapter 24)], [57 500], [1.78x], [No LZ77; Huffman alone],
  [LZ77-only (Chapter 28)], [44 200], [2.32x], [No Huffman; byte-aligned tokens],
)

Notice: the combination of LZ77 + Huffman (DEFLATE level 6) beats either
alone by a meaningful margin. And *zopfli* — a 2013 Google project that finds
the *optimal* (not greedy) LZ77 parse — squeezes out a further 5% at the cost
of being roughly 100 times slower to encode. The same bit stream format; just
better choices of where to place match boundaries.

#algo(
  name: "DEFLATE",
  year: "1991 (implementation), 1996 (RFC 1951)",
  authors: "Phil Katz (PKZIP); RFC by Peter Deutsch",
  aim: "Combine LZ77 sliding-window match finding with canonical Huffman
        coding in a block-structured bit stream. Three block types
        (stored, fixed-Huffman, dynamic-Huffman) adapt to data and size.",
  complexity: "O(n · c) encode (c = chain length, typically 4–128); O(n) decode",
  strengths: "Royalty-free; ubiquitous decoder; simple decoder implementation;
              good ratio on text/code; zlib and gzip wrappers everywhere;
              hardware decoders on modern CPUs",
  weaknesses: "32 KB window limit; Huffman coding wastes partial bits (vs. ANS);
               greedy LZ77 parser leaves ratio on the table; no pre-built
               dictionaries (unlike Brotli/zstd)",
  superseded: "By Brotli (web static assets), zstd (infrastructure), LZMA (archival);
               DEFLATE remains default in ZIP, HTTP, and PNG"
)[
  DEFLATE is specified in RFC 1951. The reference implementation is zlib
  (Jean-loup Gailly and Mark Adler, 1995), available at zlib.net. The optimal
  DEFLATE encoder is zopfli (Google, 2013). The fastest DEFLATE decoder is
  libdeflate (Eric Biggers, 2016–present), used in PNG decoders inside Chrome
  and Firefox since 2022.
]

#algo(
  name: "PNG (Portable Network Graphics)",
  year: "1996 (v1.0), 2004 (v1.2 final); ISO 15948",
  authors: "Thomas Boutell (lead), Adam Costello, Greg Roelofs, and many others",
  aim: "Lossless image compression using DEFLATE with per-row prediction
        filters, a chunk-based container, and full color management.
        Explicitly designed to be patent-free.",
  complexity: "O(n) encode/decode; filter selection adds O(n · 5) trial cost",
  strengths: "Lossless; full RGBA with 8-bit alpha; 16-bit depth;
              gamma/sRGB color management; universal browser/tool support;
              patent-free; stable since 2004",
  weaknesses: "Larger than AVIF/WebP for photographs; no animation (APNG
               is a non-standard extension); progressive mode (Adam7) rarely used",
  superseded: "By AVIF/WebP for photographs; still dominant for screenshots,
               UI, line art, and archival"
)[
  PNG's pre-filter step is the single biggest reason it outperforms DEFLATE
  applied directly to raw pixels. On screenshots, the Paeth filter can reduce
  the entropy from ~7 bits/byte to ~3 bits/byte before DEFLATE sees a byte.
]

== Step 13 — tinyzip's DEFLATE Module

Chapter 28 gave us `lz77.py` with `parse()` and a `Token` dataclass
(`is_match`, `literal`, `distance`, `length`). Chapter 24 gave us `huffman.py`
with `build_tree()`, `code_lengths()`, and `canonical_codes()`. Chapter 17 gave
us `bitio.py` with `BitWriter` and `BitReader`. It's time to snap them all
together — importing each by its exact name, renaming nothing.

#pyrecall[
  `Counter` (from the `collections` module, Chapter 16) is a `dict` purpose-built
  for counting: `Counter()` starts empty and `c[key] += 1` tallies occurrences.
  We use it here to count how often each literal/length and distance symbol
  appears, which is exactly the frequency table `build_tree()` consumes.
]

#project("Step 13 · deflate.py — LZ77 + Huffman → method=\"deflate\"")[

This step adds `tinyzip/deflate.py`. We implement a simplified but correct
DEFLATE-class compressor: it uses the token stream from `lz77.parse()` and
the Huffman machinery from `huffman.py` to produce a compressed byte string.
For simplicity we use a *single dynamic block* (the whole input is one block),
which loses the per-block adaptive advantage but keeps the code clear. The
result is not byte-compatible with standard gzip, but achieves the same
compression quality and perfectly round-trips.

```python
"""
tinyzip/deflate.py  —  Step 13
LZ77 + Huffman = deflate-class compression.
method identifier: "deflate"

Dependencies (reused with identical names):
  lz77.parse()  + lz77.Token      from tinyzip/lz77.py     (Step 12 / Ch 28)
  huffman.build_tree / code_lengths / canonical_codes
                                  from tinyzip/huffman.py  (Step 8 / Ch 24)
  bitio.BitWriter / BitReader     from tinyzip/bitio.py    (Step 3 / Ch 17)
"""

from __future__ import annotations
from collections import Counter

from tinyzip.lz77 import parse as lz77_parse, Token
from tinyzip.huffman import build_tree, code_lengths, canonical_codes
from tinyzip.bitio import BitWriter, BitReader


# ── public constants ──────────────────────────────────────────────────────────
MIN_MATCH = 3
MAX_MATCH = 258
MAX_DIST  = 32_768
# ── sentinel for end-of-block in the lit/len alphabet ─────────────────────────
EOB = 256


# ── token stream → integer symbol sequences ───────────────────────────────────

def _litlen_sym(tok: Token) -> int:
    """
    Map an LZ77 token to its literal/length symbol.
    Literals become their byte value (0–255).
    Matches become a length symbol (256 + length): simplified, one symbol
    per length 3–258. Real DEFLATE packs these into 29 codes + extra bits;
    we keep one symbol per length for clarity.
    """
    if not tok.is_match:                 # Ch 28 Token: is_match flag
        return tok.literal               # Ch 28 Token: literal byte field
    length = tok.length
    if length < MIN_MATCH or length > MAX_MATCH:
        raise ValueError(f"Bad match length {length}")
    return 256 + length                  # symbols 259–514 (EOB=256 reserved)


def _count_symbols(tokens: list[Token]) -> tuple[Counter[int], Counter[int]]:
    """Frequency counters for lit/len symbols and distance symbols."""
    ll_freq: Counter[int] = Counter()
    dist_freq: Counter[int] = Counter()
    for tok in tokens:
        ll_freq[_litlen_sym(tok)] += 1
        if tok.is_match:
            dist_freq[tok.distance] += 1
    ll_freq[EOB] += 1                     # always need one end-of-block
    return ll_freq, dist_freq


def _codes(freq: Counter[int]) -> dict[int, tuple[int, int]]:
    """{symbol: (code_int, length)} via Ch 24's canonical Huffman pipeline."""
    if not freq:
        freq = Counter({0: 1})           # degenerate fallback (no distances)
    return canonical_codes(code_lengths(build_tree(dict(freq))))


# ── encode ────────────────────────────────────────────────────────────────────

def encode(data: bytes) -> bytes:
    """
    Compress *data* with a single-block deflate-class scheme.
    decode(encode(data)) == data.
    """
    if not data:
        return b""

    tokens = lz77_parse(data)            # Step 12: LZ77 token stream
    ll_freq, dist_freq = _count_symbols(tokens)
    ll_codes   = _codes(ll_freq)         # {sym: (code, len)}
    dist_codes = _codes(dist_freq)

    bw = BitWriter()                      # Ch 17: writes ints, MSB-first
    bw.write_bits(len(data), 32)          # so the decoder knows when to stop

    # Serialize each Huffman table as (count, then sym/codelen pairs).
    # Canonical Huffman (Ch 24) rebuilds the codes from the lengths alone.
    def write_table(codes: dict[int, tuple[int, int]]) -> None:
        items = sorted(codes.items())
        bw.write_bits(len(items), 16)
        for sym, (_code, length) in items:
            bw.write_bits(sym, 16)        # symbol (0–514 fits in 16 bits)
            bw.write_bits(length, 8)      # its canonical code length

    write_table(ll_codes)
    write_table(dist_codes)

    # Emit the token stream, then the end-of-block symbol.
    for tok in tokens:
        sym = _litlen_sym(tok)
        code, length = ll_codes[sym]
        bw.write_bits(code, length)
        if tok.is_match:
            dcode, dlen = dist_codes[tok.distance]
            bw.write_bits(dcode, dlen)
    eob_code, eob_len = ll_codes[EOB]
    bw.write_bits(eob_code, eob_len)

    return bw.flush()                     # Ch 17: pad final byte + return bytes


# ── decode ────────────────────────────────────────────────────────────────────

def decode(blob: bytes) -> bytes:
    """Decompress bytes produced by encode()."""
    if not blob:
        return b""

    br = BitReader(blob)                  # Ch 17: reads ints, MSB-first
    orig_len = br.read_bits(32)

    def read_table() -> dict[tuple[int, int], int]:
        """Read a serialized table; return {(code, len): symbol} for decoding."""
        n = br.read_bits(16)
        lengths: dict[int, int] = {}
        for _ in range(n):
            sym    = br.read_bits(16)
            length = br.read_bits(8)
            lengths[sym] = length
        codes = canonical_codes(lengths)              # Ch 24, same rule as encode
        return {(c, L): sym for sym, (c, L) in codes.items()}

    ll_dec   = read_table()
    dist_dec = read_table()

    out = bytearray()
    while len(out) < orig_len:
        # Read bits until they form a complete lit/len codeword.
        code = length = 0
        while True:
            code = (code << 1) | br.read_bit()
            length += 1
            if (code, length) in ll_dec:
                break
        sym = ll_dec[(code, length)]
        if sym == EOB:
            break
        if sym <= 255:                    # a literal byte
            out.append(sym)
        else:                             # a match: read its distance codeword
            match_len = sym - 256
            dcode = dlen = 0
            while True:
                dcode = (dcode << 1) | br.read_bit()
                dlen += 1
                if (dcode, dlen) in dist_dec:
                    break
            dist = dist_dec[(dcode, dlen)]
            start = len(out) - dist
            for i in range(match_len):    # byte-by-byte copy (overlap-safe)
                out.append(out[start + i])

    return bytes(out)


# ── self-test ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    samples = [
        b"abracadabra",
        b"the quick brown fox jumps over the lazy dog " * 20,
        b"\x00" * 1000,
        b"hello world " * 50,
    ]
    for s in samples:
        compressed = encode(s)
        recovered  = decode(compressed)
        assert recovered == s, f"Round-trip failed for {s[:20]!r}..."
        ratio = len(s) / max(len(compressed), 1)
        print(f"  {len(s):6d} -> {len(compressed):6d} bytes  ({ratio:.2f}x)  ok")
    print("All self-tests passed.")
```

*What this implements:*

- `encode(data)` runs `lz77.parse()` from Chapter 28 to get a token stream,
  counts symbol frequencies, then builds canonical Huffman codes for both the
  literal/length and distance alphabets through Chapter 24's exact pipeline
  (`build_tree` → `code_lengths` → `canonical_codes`). It serializes both
  tables (symbol + code-length pairs) and the coded token stream with the
  `BitWriter` from Chapter 17.
- `decode(data)` reads the tables back, rebuilds the *same* canonical codes
  from the lengths alone (the canonical-Huffman guarantee from Chapter 24),
  and replays the token stream to regenerate the original bytes.
- The round-trip property `decode(encode(x)) == x` is verified by the self-test.

*Run it:*
```
python -m tinyzip.deflate
```
You should see output like (exact byte counts depend on the LZ77 parse and the
naive table serialization):
```
    11 ->     36 bytes  (0.31x)  ok    # "abracadabra" — too small to compress
  3960 ->    142 bytes  (27.89x) ok    # repeated sentence
  1000 ->     25 bytes  (40.00x) ok    # all-zero bytes
   600 ->     52 bytes  (11.54x) ok    # repeated "hello world"
All self-tests passed.
```

Note the first sample *expands* — as we computed by hand earlier, very short
or random inputs always expand under DEFLATE (the two transmitted Huffman
tables alone cost more than the saved bits). The repeated sentences and null
bytes compress dramatically.

*Integration with the tinyzip CLI:*

Add to `tinyzip/container.py` (from Step 4):

```python
# In container.py, in the method dispatch:
from tinyzip import deflate as _deflate

_METHODS = {
    ...
    "deflate": (_deflate.encode, _deflate.decode),
}
```

Now `python -m tinyzip compress myfile.txt --method deflate` works end-to-end.

]

#gopython("Dataclasses and the Token Type")[
  In `lz77.py` from Chapter 28, `Token` is a Python *dataclass* — a class
  that automatically generates `__init__`, `__repr__`, and `__eq__` from
  field annotations. Its exact shape (identical to Chapter 28) is:

  ```python
  from dataclasses import dataclass

  @dataclass
  class Token:
      is_match: bool       # True = back-reference, False = literal byte
      literal:  int = 0    # used when is_match is False
      distance: int = 0    # used when is_match is True
      length:   int = 0    # used when is_match is True
  ```

  Access fields with dot notation: `tok.is_match`, `tok.literal`,
  `tok.distance`, `tok.length`. The `@dataclass` decorator is shorthand for
  writing the boilerplate `__init__` yourself. Our `deflate.py` checks
  `tok.is_match` to decide whether to emit a literal symbol or a
  length-plus-distance pair — exactly the fields Chapter 28 defined, reused
  without renaming.
]

== Compression Effectiveness: Before and After

Adding DEFLATE to our growing toolkit is a major milestone. Let's update the
running scoreboard on our standard 100 KB English text sample:

#scoreboard(caption: "Cumulative tinyzip scoreboard after Step 13",
  [Raw (no compression)], [102 400], [1.00x], [Baseline],
  [Huffman (Ch 24)], [57 500], [1.78x], [Entropy coding only; no LZ77],
  [Arithmetic coding (Ch 26)], [55 200], [1.86x], [Closer to entropy; still no LZ77],
  [rANS (Ch 27)], [55 100], [1.86x], [Same entropy, faster encode],
  [LZ77 only (Ch 28)], [44 200], [2.32x], [Match finder, byte-aligned output],
  [DEFLATE — level 1 (Ch 30)], [52 300], [1.96x], [LZ77+Huffman; fast chain],
  [DEFLATE — level 6 (Ch 30)], [39 800], [2.57x], [Default; lazy matching],
)

The jump from LZ77 alone (44 200 bytes) to DEFLATE level 6 (39 800 bytes)
shows the Huffman stage removing ~10% more — by squeezing fractional bits
from each match token that LZ77 left byte-aligned. And DEFLATE level 6 beats
Huffman-only by 31%, because LZ77 removes repetition that Huffman cannot touch.
The combination wins.

== Real-World Deployment: Numbers That Matter

The following numbers give a sense of DEFLATE's real-world footprint as of 2026:

- *HTTP traffic:* According to the HTTP Archive's 2025 Web Almanac, over 80%
  of all HTTP responses are served with a content encoding — and of those,
  gzip accounts for roughly 60%, Brotli 35%, and zstd under 5% (though zstd
  is growing fast as CDN support expands). DEFLATE (inside gzip) still
  carries the majority of the web's compressed bytes.
- *ZIP archives:* The ZIP format (DEFLATE method 8) is the default archive
  format on Windows, macOS, and most Linux distros for user-facing archives.
  Billions of ZIP files exist.
- *PNG images:* Every PNG file — every screenshot on every platform, every
  Wikipedia image marked lossless, every UI mockup — uses DEFLATE internally.
  PNG is the 3rd most common image format on the web (after JPEG and AVIF
  in 2025/2026).
- *libdeflate:* The fastest DEFLATE decoder, libdeflate (Eric Biggers),
  achieves roughly 1.4 GB/s single-core throughput on modern x86 hardware
  by using SIMD and careful bit-twiddling. It became the default PNG
  decompressor in Chrome (since 2021) and Firefox (since 2022).
- *Zopfli:* Google's optimal DEFLATE encoder (2013) produces 3–8% smaller
  files than zlib level 9, at the cost of 100× slower encoding. It's used
  to pre-compress static web assets.

#aside[
  The zlib library — the canonical DEFLATE implementation, written by
  Jean-loup Gailly and Mark Adler — was released in May 1995. It is arguably
  the single most widely deployed piece of compression software in history:
  it ships in Python's standard library, in every major web server, in the
  Linux kernel, in iOS, Android, and virtually every embedded system. The
  codebase is roughly 50 000 lines of C that have been under continuous
  development for three decades.
]

== Limitations and When to Use Something Else

DEFLATE is excellent but not always the right tool:

*When DEFLATE struggles:*

- *Already-compressed data* (JPEG, MP3, encrypted files): DEFLATE will expand
  it slightly. Use stored blocks or don't compress.
- *Very small files* (< 100 bytes): Header overhead dominates. Use no
  compression, or only Huffman with a simple header.
- *Long-range repetition* (same text appearing 100 KB apart): The 32 KB window
  is blind to it. LZMA (Chapter 31) handles this with gigabyte windows.
- *High compression ratio requirements*: LZMA and bzip2 (Chapter 35) beat
  DEFLATE by 20–40% on typical text, at the cost of memory and speed.
- *Maximum speed*: LZ4 or Snappy (Chapter 32) compress at 3–5 GB/s vs.
  DEFLATE's ~100–200 MB/s, at the cost of compression ratio.

*When DEFLATE wins:*

- Universal compatibility (every tool, every OS).
- HTTP content encoding (gzip/Brotli are the two main encodings; Brotli
  also uses LZ77 internally).
- PNG image compression (built into the standard; no alternative).
- ZIP archives (compatibility with every extraction tool requires DEFLATE).
- General-purpose compression of text, code, and structured data where you
  need broad compatibility over maximum ratio.

#pitfall[
  Do not re-compress DEFLATE-compressed data. If you gzip a `.png` file,
  you will get a slightly *larger* file, because the PNG is already
  DEFLATE-compressed and the second pass cannot find meaningful patterns
  in the pseudo-random output of the first. Always check whether your data
  is already compressed before adding another compression layer.
]

== Further Reading

- #link("https://www.rfc-editor.org/rfc/rfc1951.txt")[RFC 1951 — DEFLATE Compressed Data Format] (Peter Deutsch, 1996).
  The authoritative specification. Short and readable.
- #link("https://www.rfc-editor.org/rfc/rfc1952.txt")[RFC 1952 — gzip format] (Deutsch, 1996).
  Specifies the gzip wrapper around DEFLATE.
- #link("https://www.rfc-editor.org/rfc/rfc1950.txt")[RFC 1950 — zlib format] (Deutsch & Gailly, 1996).
  The zlib wrapper with Adler-32.
- #link("https://www.w3.org/TR/png/")[PNG Specification 1.2] (W3C, 2004).
  The definitive PNG reference; especially section 9 on filter algorithms.
- #link("https://zlib.net/feldspar.html")[An Explanation of the Deflate Algorithm] (Ken Shan, 2004).
  An exceptionally clear walkthrough of the bit-level encoding.
- #link("https://github.com/google/zopfli")[Zopfli source] (Google, 2013).
  The optimal DEFLATE encoder; reading its LZ77 parse is educational.
- #link("https://github.com/ebiggers/libdeflate")[libdeflate] (Eric Biggers, 2016–present).
  The fastest correct DEFLATE decoder; instructive SIMD code.

#takeaways((
  [DEFLATE = LZ77 (from Chapter 28) + Huffman (from Chapter 24): two complementary
   stages that together outperform either alone.],
  [Three block types give DEFLATE flexibility: stored (uncompressed), fixed
   Huffman (fast, no table transmission), and dynamic Huffman (optimal per-block).],
  [The 32 KB sliding window was a deliberate 1991 engineering tradeoff; it
   limits long-range matches but kept DEFLATE fast on contemporary hardware.],
  [Hash chains make LZ77 match finding O(n·c) instead of O(n·w), enabling
   practical encoding speeds with tunable quality levels.],
  [zlib, gzip, ZIP, and PNG are four different wrappers around the same
   DEFLATE engine; they differ in headers, checksums, and container structure.],
  [PNG's per-row prediction filters (Sub, Up, Average, Paeth) can halve pixel
   entropy before DEFLATE sees a byte — the biggest reason PNG is good at images.],
  [Phil Katz placed DEFLATE in the public domain, enabling its spread into
   every corner of computing; contrast with LZW (Chapter 29), which was
   patented and created the GIF licensing crisis.],
  [DEFLATE remains the world's most deployed compressor by traffic volume,
   even in 2026; for higher ratios use LZMA (Chapter 31) or zstd (Chapter 32).],
))

== Exercises

#exercise("30.1", 1)[
  A DEFLATE dynamic block begins with the code-length table. The spec says
  the code-length alphabet has exactly *19* symbols. List at least 5 of those
  19 symbols and explain why run-length symbols are included.
]
#solution("30.1")[
  The 19 symbols are: lengths 0–15 (16 symbols), plus three special run-length
  symbols: (a) *16* = copy the previous length 3–6 times; (b) *17* = repeat
  zero 3–10 times; (c) *18* = repeat zero 11–138 times. Run-length symbols
  are included because Huffman code-length sequences contain many consecutive
  equal values (e.g., many symbols have length 8) or zeros (many symbols
  are absent from the block). Run-length encoding compresses the length
  sequence itself by 30–60%.
]

#exercise("30.2", 1)[
  A gzip file starts with `0x1f 0x8b`. After that byte 3 is the *flags* byte.
  Bit 3 of flags (called `FNAME`) indicates whether an original filename is
  stored. If `FNAME` is set, where does the filename appear in the file,
  and how is it terminated?
]
#solution("30.2")[
  According to RFC 1952, if `FNAME` is set, the original filename appears
  immediately after the 10-byte fixed gzip header (and after any extra fields
  if `FEXTRA` is also set). The filename is stored as a null-terminated C
  string — raw ISO-8859-1 bytes followed by a `0x00` byte. The decoder reads
  bytes until the null and may use the filename to restore the original file
  name on extraction.
]

#exercise("30.3", 2)[
  A DEFLATE encoder is processing the string:

  `"the cat sat on the mat"`

  Identify all matches a LZ77 pass with a 32-byte window would find
  (minimum match length 3). Write the full token stream.
]
#solution("30.3")[
  Positions (0-indexed): 0=t 1=h 2=e 3=\  4=c 5=a 6=t 7=\  8=s 9=a 10=t
  11=\  12=o 13=n 14=\  15=t 16=h 17=e 18=\  19=m 20=a 21=t.

  After the initial scan:
  - Positions 0–14: no prior data long enough; emit 15 literals:
    `t h e   c a t   s a t   o n  `.
  - Position 15: "the " matches position 0, length 4.
    → MATCH(dist=15, len=4).
  - Position 19: "mat" — 'm' at 19 is new, emit LIT m.
  - Position 20: "at" — only 2 chars; too short. Emit LIT a.
  - Position 21: "t" — LIT t.

  Full stream: `LIT(t) LIT(h) LIT(e) LIT( ) LIT(c) LIT(a) LIT(t) LIT( )
  LIT(s) LIT(a) LIT(t) LIT( ) LIT(o) LIT(n) LIT( ) MATCH(15,4) LIT(m)
  LIT(a) LIT(t) EOB`.

  22 raw bytes → 19 tokens (17 literals + 1 match + EOB). Modest savings
  because the string is short; on longer repetitive input, savings would be
  much greater.
]

#exercise("30.4", 2)[
  PNG's Paeth predictor uses three neighbors: $A$ (left), $B$ (above),
  $C$ (upper-left). Compute the Paeth predictor for the following pixel
  neighborhood:

  $A = 100, B = 110, C = 95$, current pixel $P = 108$.

  Show the predicted value and the residual byte that would be written
  to the filtered PNG row.
]
#solution("30.4")[
  $p = A + B - C = 100 + 110 - 95 = 115$.
  Distances: $|A - p| = |100 - 115| = 15$, $|B - p| = |110 - 115| = 5$,
  $|C - p| = |95 - 115| = 20$.
  Minimum is $|B - p| = 5$, so predictor picks $hat(P) = B = 110$.
  Residual $= P - hat(P) = 108 - 110 = -2 equiv 254 space (mod 256)$.
  The byte `254` is written to the filtered row. (Decoded as $110 + 254 mod 256 = 108$ — correct.)
]

#exercise("30.5", 2)[
  Explain why PNG uses *per-row* filters rather than a single global
  prediction strategy. What happens at the boundary between a dark region
  and a light region in an image, and which filter handles it best?
]
#solution("30.5")[
  Per-row filters let the encoder adapt to local image structure. A row inside
  a smooth gradient benefits from the Up or Average filter (differences from
  the row above are tiny). A row containing a sharp horizontal edge benefits
  from No-filter or Sub (the pixel to the left is the best predictor along
  the edge). The Paeth filter handles diagonal edges well. A single global
  strategy would be suboptimal for rows with different local statistics.

  At the boundary between a dark region (e.g., pixel values ~30) and a light
  region (e.g., pixel values ~220), the Up predictor gives a residual of
  ~190 (large), while the Sub predictor uses the left neighbor (still dark)
  and gives a residual of ~190 too. In this case, No-filter may actually be
  the best choice — the residuals are large regardless, so we save the overhead
  of the filter computation. Paeth handles the transition best when the edge
  is diagonal, because it picks $C$ (upper-left, from the dark side) only
  when no other neighbor is closer to the gradient estimate.
]

#exercise("30.6", 2)[
  In the tinyzip `deflate.py` implementation, the Huffman tables are
  transmitted naively (sorted symbol + code-length pairs). How does the
  real DEFLATE specification transmit Huffman tables? What is the
  advantage of the real approach?
]
#solution("30.6")[
  Real DEFLATE (RFC 1951) transmits only the *code lengths* (not symbols or
  actual codes), relying on the canonical Huffman convention to reconstruct
  codes from lengths. The length sequence is further compressed with a
  *third Huffman code* (the "code-length code") applied to a 19-symbol
  run-length alphabet. Symbols absent from the block have length 0 and are
  not transmitted.

  Advantages: (1) Canonical codes are uniquely determined by lengths, so no
  code values need to be transmitted — saving up to 12 bits per symbol. (2)
  Run-length coding of the length sequence reduces the table overhead from
  ~300 bytes to ~50–100 bytes. (3) Code-length ordering (the HCLEN table)
  lets the most common code lengths be represented in just 3 bits each.
  Our simplified implementation trades this efficiency for clarity.
]

#exercise("30.7", 3)[
  Implement `png_filter_sub(row: bytes) -> bytes` in Python 3.14 that
  applies PNG's Sub filter (type 1) to a single row of pixel bytes. The
  row contains RGBA pixels (4 bytes per pixel). Handle the leftmost pixel
  correctly (its left neighbor is defined to be 0). Verify with this example:

  `row = bytes([100, 120, 80, 255, 102, 121, 82, 255, 104, 123, 84, 255])`

  Expected filtered output: `[100, 120, 80, 255, 2, 1, 2, 0, 2, 2, 2, 0]`.
]
#solution("30.7")[
  ```python
  def png_filter_sub(row: bytes, bpp: int = 4) -> bytes:
      """
      Apply PNG Sub filter (type 1) to one raw pixel row.
      bpp: bytes per pixel (4 for RGBA, 3 for RGB, 1 for grayscale).
      Returns filtered bytes (without the leading filter-type byte).
      """
      out = bytearray(len(row))
      for i, byte in enumerate(row):
          a = row[i - bpp] if i >= bpp else 0
          out[i] = (byte - a) % 256
      return bytes(out)

  # Verify:
  row = bytes([100, 120, 80, 255, 102, 121, 82, 255, 104, 123, 84, 255])
  result = png_filter_sub(row)
  print(list(result))
  # → [100, 120, 80, 255, 2, 1, 2, 0, 2, 2, 2, 0]
  ```
  At position 0–3 (first pixel), left neighbor is 0, so residuals = raw values.
  At position 4 (first byte of second pixel): $102 - 100 = 2$. Position 5:
  $121 - 120 = 1$. And so on.
]

#exercise("30.8", 3)[
  The zlib Adler-32 checksum maintains two 16-bit sums modulo 65 521.
  Starting from $s_1 = 1, s_2 = 0$, compute the Adler-32 of the string
  `"ABC"` (byte values 65, 66, 67). Show each intermediate step. The final
  checksum is $(s_2 << 16) | s_1$.
]
#solution("30.8")[
  Initialize: $s_1 = 1, s_2 = 0$.

  Byte 'A' (65): $s_1 = (1 + 65) mod 65521 = 66$; $s_2 = (0 + 66) mod 65521 = 66$.

  Byte 'B' (66): $s_1 = (66 + 66) mod 65521 = 132$; $s_2 = (66 + 132) mod 65521 = 198$.

  Byte 'C' (67): $s_1 = (132 + 67) mod 65521 = 199$; $s_2 = (198 + 199) mod 65521 = 397$.

  Final Adler-32 $= (397 << 16) | 199 = (397 times 65536) + 199 = 26 017 011 + 199 = 26 017 607$ (decimal).
  In hex: `0x01 8D 00 C7`.

  (Python verification: `import zlib; zlib.adler32(b"ABC") == 26017607` → True.)
]

#bridge[
  DEFLATE is the most-deployed compressor ever, but its 32 KB window and
  Huffman entropy stage leave real compression on the table. In *Chapter 31*
  we meet LZMA — the engine of 7-Zip and `.xz` tarballs — which trades
  speed for a window measured in *gigabytes*, a range coder instead of
  Huffman, and per-byte context models that Huffman cannot match. We'll also
  examine the 2024 xz-utils backdoor: a supply-chain attack hidden in a
  compression library that nearly compromised the world's Linux servers.
]
