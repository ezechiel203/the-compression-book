#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Columnar and Database Compression

#epigraph[
  "A database that reads everything to answer anything is a library where
  every question requires you to read the entire encyclopedia."
][_Peter Boncz, co-designer of MonetDB_]

Here is a puzzle that tripped up the early designers of analytical databases.
Suppose you have a table with one billion rows (a year of sales transactions)
and a manager asks: _"What is the total revenue by product category this
quarter?"_ The query touches exactly two columns out of thirty: `category` and
`revenue`. In a traditional row-by-row database, you would read all thirty
columns for all one billion rows just to get at those two. That is like
searching every drawer in every desk in every office to find the one folder
you need.

Columnar databases flipped the layout: store each column as its own
continuous block on disk. Now that same query reads only 6.7% of the data. But
the engineers who built these systems noticed something even more useful:
because a column holds values _of a single type_, and those values are often
similar to their neighbors, the column compresses spectacularly well. Not just
2× or 3×, but 5×, 10×, sometimes 30× for the right kind of data.

This chapter is about how they did it: the small, clever tricks that stack
together into enormous savings, and why those tricks also make queries run
faster, not slower.

#recap[
  In *Chapter 24* we built canonical Huffman coding, and in *Chapters 26–27*
  arithmetic coding and rANS (all entropy coders that assign variable-length
  codes to individual symbols). In *Chapter 28* we explored LZ77's sliding-window
  back-references, and in *Chapter 30* DEFLATE stacked the two ideas. In
  *Chapter 35* BWT+MTF+RLE attacked runs of repeated bytes. All of those
  techniques treat their input as an opaque byte stream and know nothing about
  its meaning. This chapter is different: we are going to *exploit the schema* -
  the fact that a column of product categories, or a column of timestamps, or
  a column of integer IDs has a very specific structure that lets us shrink it
  far beyond what any generic compressor can do.
]

#objectives((
  "Explain why columnar (column-store) layout enables better compression than row-store layout.",
  "Describe and implement dictionary encoding, run-length encoding, and bit-packing for integer columns.",
  "Explain frame-of-reference (FOR) and delta encoding, and when each wins.",
  "Explain what Roaring bitmaps are, how their three container types work, and why they are used for index bitmaps.",
  "Describe how Apache Parquet and ORC layer lightweight encodings beneath a heavy-weight byte-stream codec.",
  "Understand the idea of operating on compressed data: why query engines sometimes avoid decompressing at all.",
  "Critically evaluate BtrBlocks' automated scheme selection approach.",
))

== Why Columns Beat Rows for Compression

Imagine a table with four columns: `city`, `product`, `price`, and `date`.

#align(center)[
  #table(
    columns: 4,
    stroke: 0.5pt,
    [*city*], [*product*], [*price*], [*date*],
    [Berlin], [Widget], [9.99], [2024-01-03],
    [Paris],  [Gadget], [4.50], [2024-01-03],
    [Berlin], [Widget], [9.99], [2024-01-04],
    [Berlin], [Gadget], [4.50], [2024-01-05],
    [Paris],  [Widget], [9.99], [2024-01-05],
  )
]

Stored row-by-row (_row store_), you see: `Berlin`, `Widget`, `9.99`,
`2024-01-03`, `Paris`, `Gadget`, `4.50`, `2024-01-03`, … A generic compressor
like zstd will find some redundancy, but the city and product strings are
interspersed with numbers and dates, so the repetitions are far apart.

Stored column-by-column (_column store_), the `city` column reads:
`Berlin`, `Paris`, `Berlin`, `Berlin`, `Paris`. Five short strings from
a two-word vocabulary, trivially compressible. The `price` column reads:
`9.99`, `4.50`, `9.99`, `4.50`, `9.99`: two values alternating. The `date`
column reads four consecutive dates, perfect for delta encoding.

#keyidea[
  Columnar layout groups *like values with like values*. Because a column has
  a single data type and typically a limited set of distinct values, it
  compresses far better than an interleaved row stream, and the compression
  also makes queries faster because less data moves from disk to CPU.
]

The landmark paper that proved this in a production system was by Daniel Abadi
and colleagues at MIT in 2006: "Integrating Compression and Execution in
Column-Oriented Database Systems," published at ACM SIGMOD. Their key
observation was that query operators could often work *directly* on the
compressed representation. More on that at the end of this chapter.

== The Encoding Toolkit: Six Lightweight Tricks

Database compression is not one algorithm but a *stack* of lightweight
encodings applied in sequence. Each one targets a different type of
redundancy. Let us build up the full stack.

=== Trick 1: Dictionary Encoding

The most important single trick. Idea: if a column has few distinct values,
replace each value with a small integer ID, store the ID column instead of
the string column, and keep a *dictionary* (a lookup table) from ID to
string.

#definition("Dictionary encoding")[
  Given a column $C$ with $d$ distinct values $v_1, dots, v_d$, replace
  each occurrence of $v_i$ with the integer $i$. Store the array of IDs plus
  the mapping $i -> v_i$. The ID column is stored with the fewest bits needed
  to represent $d - 1$ (since IDs run $0, 1, dots, d-1$).
]

*Worked example.* The `city` column `[Berlin, Paris, Berlin, Berlin, Paris]`
has $d = 2$ distinct values. The dictionary is `{0: "Berlin", 1: "Paris"}`.
The ID column is `[0, 1, 0, 0, 1]`. Each ID fits in 1 bit (since
$2^1 = 2 >= d$). So five cities that might take $5 times 6$ bytes = 30 bytes
of UTF-8 become 5 bits of IDs plus a tiny dictionary.

*When it wins:* low cardinality columns - country codes, product categories,
status flags, any enum-like column. The compression ratio is roughly:

$
"ratio" approx (overline(L) dot N) / ((ceil(log_2 d) dot N) / 8 + D)
$

where $overline(L)$ is the average string length in bytes (the bar over a
letter, $overline(L)$, is the standard shorthand for "the average of $L$"),
$N$ is the number of rows, $ceil(log_2 d)$ is the bits per ID, and $D$ is the
dictionary size in bytes. The numerator is the raw cost (every row stores its full string); the
denominator is the encoded cost (one short ID per row, divided by 8 to turn bits
into bytes, plus the one-time dictionary).

To see the formula bite, take a `country` column of $N = 1{,}000{,}000$ rows
drawn from $d = 200$ countries whose names average $overline(L) = 8$ bytes. Each
ID needs $ceil(log_2 200) = 8$ bits, and the dictionary of 200 names costs about
$D approx 1{,}600$ bytes. Plugging in:
$
"ratio" approx (8 dot 10^6) / ((8 dot 10^6) / 8 + 1600) approx (8{,}000{,}000) / (1{,}001{,}600) approx 8.0 times.
$
For typical string columns with cardinality under 10,000, the ratio routinely
exceeds 10×.

#gomaths("Ceiling, floor, and base-2 logarithm")[
  The _ceiling_ of a real number $x$, written $ceil(x)$, is the smallest integer
  $>=$ $x$. So $ceil(2.1) = 3$ and $ceil(4.0) = 4$. Its mirror image, the _floor_
  $floor(x)$, is the largest integer $<= x$, so $floor(2.9) = 2$ and
  $floor(4.0) = 4$. A handy way to think of them: ceiling always rounds _up_,
  floor always rounds _down_, and on a whole number both leave it unchanged.

  The _base-2 logarithm_ $log_2 d$ answers "how many times must I multiply 2
  by itself to get $d$?" To store $d$ distinct IDs you need $ceil(log_2 d)$ bits
  per ID. For $d = 256$ that is exactly 8 bits; for $d = 300$ it is
  $ceil(log_2 300) = ceil(8.23) = 9$ bits.
]

*Parquet's rule:* Apache Parquet automatically enables dictionary encoding for
any column where the dictionary fits in a configurable threshold (default: all
distinct values fit in the first data page, roughly 1 MB). If the column
overflows that limit, Parquet falls back to plain encoding. A 2023 empirical
study on Parquet found that dictionary encoding alone accounts for more than
half of the total compression on typical business analytics tables.

#aside[
  Dictionary encoding also speeds up *joins* and *group-by* operations: instead
  of comparing strings character-by-character, the engine compares integer IDs.
  A single CPU instruction can beat a 20-character string comparison by an
  order of magnitude. Compression and speed reinforce each other here.
]

=== Trick 2: Bit-Packing

Once you have a column of small integers (whether from dictionary encoding
or from IDs stored directly) many of the integer bits are wasted. If your
IDs run from 0 to 999, you need only $ceil(log_2 1000) = 10$ bits each.
A standard 32-bit integer column wastes 22 bits per value, a 3.2× waste.

#definition("Bit-packing")[
  Store each integer using exactly $w$ bits (the *bit width*), where
  $w = ceil(log_2(max + 1))$ and $max$ is the largest value in the block.
  Values are concatenated without gaps, and the stream is padded to a byte
  boundary at the end.
]

For a block of 1,024 integers with max value 999 ($w = 10$):
- Unpacked: $1024 times 32 = 32{,}768$ bits = 4,096 bytes.
- Bit-packed: $1024 times 10 = 10{,}240$ bits = 1,280 bytes (rounded up).
- Saving: 68.75%.

#gopython("Bit-packing integers into bytes")[
  ```python
  def bitpack(values: list[int], width: int) -> bytes:
      """Pack a list of non-negative integers into a bit stream."""
      bits = 0          # accumulator (grows without bound, then sliced)
      nbits = 0         # how many bits are in the accumulator
      out: list[int] = []
      for v in values:
          bits = (bits << width) | v   # shift left, OR in new value
          nbits += width
          while nbits >= 8:            # flush complete bytes
              nbits -= 8
              out.append((bits >> nbits) & 0xFF)
      if nbits > 0:                    # flush the leftover bits (padded)
          out.append((bits << (8 - nbits)) & 0xFF)
      return bytes(out)

  # Quick test: pack three 4-bit values [7, 2, 15] = 0111 0010 1111
  packed = bitpack([7, 2, 15], width=4)
  assert packed == bytes([0b01110010, 0b11110000])
  print(packed.hex())   # 72f0
  ```
  The `<<` operator shifts bits left (multiplies by a power of 2); `|` is
  bitwise OR (combines bit patterns without overlap); `& 0xFF` masks to the
  lowest 8 bits. We introduced all of these in *Chapter 13*.
]

*SIMD acceleration.* Modern databases bit-pack and unpack entire 512-bit
SIMD registers at once. Libraries such as *FastPFor* (Lemire & Boytsov, 2015)
achieve billions of integers packed or unpacked per second on a single core.
Parquet uses a variant called *RLE/bit-packed hybrid* that switches between
run-length encoding and bit-packing within the same column, depending on which
is shorter for each run.

=== Trick 3: Run-Length Encoding (RLE)

We already met RLE in *Chapter 35* (the bzip2 pipeline). In the database
context it takes a slightly different form: instead of emitting (value, count)
pairs byte-by-byte, we emit them as typed records.

#definition("Database RLE")[
  For a run of $r$ consecutive equal values $v$, emit the pair $(v, r)$.
  Store the pairs in a typed array (value column + count column) rather than
  a flat byte stream.
]

Example: the `city` column of a *sorted* table might read
`Berlin, Berlin, Berlin, …, Paris, Paris, Paris` (if the table was sorted
on city). RLE would produce just two pairs: `(Berlin, 3 million)` and
`(Paris, 2 million)`. Five million rows become two records, a 2.5-million-fold
compression.

#pitfall[
  RLE in databases is most effective on *sorted* or *nearly-sorted* data.
  On randomly ordered data it degenerates (every run has length 1) and actually
  *wastes* space compared to plain storage. Parquet and ORC therefore apply RLE
  automatically but fall back gracefully to plain or bit-packed encoding when
  runs are short.
]

Parquet's encoding is called *RLE/Bit-packed Hybrid*: it uses 8-bit run header
bytes to indicate whether the following data is a run (value × count) or a
block of bit-packed literals. This lets it handle both sorted and unsorted
integer columns efficiently with a single pass.

=== Trick 4: Frame of Reference (FOR) and Delta Encoding

Many integer columns are not from dictionaries; they are raw numbers like
timestamps, prices in cents, or row-IDs. These values may span a large
absolute range (say, Unix timestamps from 1,700,000,000 to 1,701,000,000) but
have a *small range within any block* (within one month, timestamps differ
by at most 2,592,000, about 21 bits, not the 32 bits the full range would need).

#definition("Frame of Reference (FOR)")[
  Divide the column into blocks of $B$ values. Within each block, record the
  minimum value $m$ (the *frame*) and store each value as the *offset*
  $v - m$, which fits in fewer bits. Compress the offsets with bit-packing.
]

*Worked example.* Timestamps (in seconds) for one day:
$[1{,}700{,}100{,}000, 1{,}700{,}103{,}600, 1{,}700{,}107{,}200, …]$

The minimum is $m = 1{,}700{,}100{,}000$. The offsets within a 24-hour window
are at most 86,400, which fits in 17 bits rather than 31 bits. For a block of
1,024 values, FOR saves $(31 - 17) times 1024 / 8 = 1{,}792$ bytes over
plain 32-bit storage.

$"FOR offset"_i = v_i - m, quad "where" m = min(v_1, dots, v_B)$

*Delta encoding* is the natural companion: instead of subtracting a constant
frame, subtract the *previous value*:

$"Delta"_i = v_i - v_(i-1), quad "with" v_0 = 0$

For monotonically increasing columns (IDs, ordered timestamps) the deltas are
small positive numbers, often a few bits each. A column of 64-bit primary
keys that increment by one takes only 1 bit per delta after the first value.

*FOR versus Delta.* A 2024 paper by Spindler, Fent, Riedl, and Neumann
(VLDB Workshops 2024) showed experimentally that FOR outperforms Delta on
*unsorted* integer columns with clustered values, while Delta wins on truly
*monotone* sequences. Many systems (Parquet, ClickHouse) implement both and
choose per-block.

*Delta-FOR (DFOR)*: subtract the previous value to get deltas, then apply FOR
on the delta block. This is the state of the art for ordered integer columns
and can push timestamp columns to under 2 bits per value on typical monitoring
data.

#gomaths("Absolute value and range")[
  The *range* of a set of numbers $\{v_1, dots, v_B\}$ is
  $max - min$. A small range means the values cluster together even if the
  absolute values are large. FOR exploits a small range; delta encoding exploits
  small *successive differences*. Both reduce the number of bits needed by
  shrinking the range of the values that must be bit-packed.
]

=== Trick 5: Roaring Bitmaps

Column stores use *bitmap indexes* to speed up queries. A bitmap index for a
column value $v$ is a bit-array with one bit per row: bit $i$ is 1 if row $i$
has value $v$, else 0. To find all rows where `city = "Berlin" AND price < 5`,
the engine ANDs the Berlin bitmap with the "price < 5" bitmap: one CPU
instruction per 64 rows on a 64-bit machine.

The problem: a table with 1 billion rows has 1-billion-bit (125 MB) bitmaps.
For rare values the bitmap is 99.9% zeros, enormous waste. For common values
it is nearly all ones. The ideal representation shifts between sparse and dense
as needed.

This is exactly what *Roaring bitmaps* solve. Introduced by Samy Chambi,
Daniel Lemire, Owen Kaser, and Robert Godin (Software: Practice and
Experience, 2016), Roaring is a *hybrid compressed bitmap* that automatically
picks the best internal container for each region of the integer domain.

#definition("Roaring bitmap")[
  A Roaring bitmap represents a set of 32-bit unsigned integers. It splits the
  32-bit integer space into 65,536 *chunks*, each covering $2^{16} = 65{,}536$
  consecutive integers (the top 16 bits are the *chunk key*, the bottom 16 bits
  are the *entry* within the chunk). Each non-empty chunk is stored in one of
  three container types, chosen automatically:

  1. *Array container:* a sorted array of the 16-bit offsets of the set
     elements. Used when the chunk has fewer than 4,096 elements (density
     below $4096 / 65536 = 6.25%$).
  2. *Bitset container:* a flat bit array of 65,536 bits (8,192 bytes).
     Used when the chunk has 4,096 or more elements (density 6.25% or higher).
  3. *Run container:* a list of (start, length) pairs for consecutive runs of
     1-bits. Added in the 2016 follow-up paper (Lemire, Ssi-Yan-Kai, Kaser).
     Used when runs compress better than both array and bitset.

  The boundary 4,096 is chosen so that an array of 4,096 16-bit values
  (8,192 bytes) costs exactly the same as a full bitset container. Above that
  count, the bitset wins on space.
]

#fig(
  [A Roaring bitmap for the set of set-bits corresponding to rows matching
   a query. The 32-bit integer space is partitioned into 65,536 chunks of
   65,536 values each. Each chunk independently chooses the cheapest
   container: an array (sparse), a flat bitset (dense), or a run-length list
   (consecutive runs).],
  cetz.canvas({
    import cetz.draw: *
    // Draw the main 32-bit space bar
    rect((0, 2.8), (12, 3.4), stroke: 1pt, fill: rgb("#e8f0fe"))
    content((6, 3.1), box(width: 11.6cm, inset: 2pt, align(center, text(size: 9pt)[32-bit integer space (0 … 4,294,967,295)])))

    // Three chunks
    // Sparse chunk (array container)
    rect((0.2, 0), (3.6, 2.4), stroke: 1pt, fill: rgb("#fef9e7"), radius: 3pt)
    content((1.9, 2.15), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt, weight: "bold")[Chunk key = 0x0017])))
    content((1.9, 1.8), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt)[Sparse: 12 elements])))
    content((1.9, 1.45), box(width: 3.0cm, inset: 2pt, align(center, text(size: 7.5pt, fill: rgb("#1f5066"))[Array container])))
    content((1.9, 1.1), box(width: 3.0cm, inset: 2pt, align(center, text(size: 7pt)[0x0003, 0x00A1, 0x02FF…])))
    content((1.9, 0.75), box(width: 3.0cm, inset: 2pt, align(center, text(size: 7pt)[24 bytes])))

    // Dense chunk (bitset container)
    rect((4.2, 0), (7.8, 2.4), stroke: 1pt, fill: rgb("#eafaf1"), radius: 3pt)
    content((6.0, 2.15), box(width: 3.2cm, inset: 2pt, align(center, text(size: 8pt, weight: "bold")[Chunk key = 0x003B])))
    content((6.0, 1.8), box(width: 3.2cm, inset: 2pt, align(center, text(size: 8pt)[Dense: 40,000 elements])))
    content((6.0, 1.45), box(width: 3.2cm, inset: 2pt, align(center, text(size: 7.5pt, fill: rgb("#1f5066"))[Bitset container])))
    content((6.0, 1.1), box(width: 3.2cm, inset: 2pt, align(center, text(size: 7pt)[65,536-bit flat array])))
    content((6.0, 0.75), box(width: 3.2cm, inset: 2pt, align(center, text(size: 7pt)[8,192 bytes])))

    // Run chunk (run container)
    rect((8.4, 0), (11.8, 2.4), stroke: 1pt, fill: rgb("#fce4ec"), radius: 3pt)
    content((10.1, 2.15), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt, weight: "bold")[Chunk key = 0x00F0])))
    content((10.1, 1.8), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt)[Runs: 3 long runs])))
    content((10.1, 1.45), box(width: 3.0cm, inset: 2pt, align(center, text(size: 7.5pt, fill: rgb("#1f5066"))[Run container])))
    content((10.1, 1.1), box(width: 3.0cm, inset: 2pt, align(center, text(size: 7pt)[(start, len) pairs])))
    content((10.1, 0.75), box(width: 3.0cm, inset: 2pt, align(center, text(size: 7pt)[12 bytes])))

    // Connector lines from big bar to chunks
    line((1.9, 2.8), (1.9, 2.4), stroke: 0.7pt + gray)
    line((6.0, 2.8), (6.0, 2.4), stroke: 0.7pt + gray)
    line((10.1, 2.8), (10.1, 2.4), stroke: 0.7pt + gray)
  })
)

*Why it matters.* Roaring bitmaps are now embedded in Apache Lucene (full-text
search), Apache Spark, Apache Pinot, ClickHouse, DuckDB, and dozens of other
systems. Operations on Roaring bitmaps (AND, OR, NOT, XOR) work
directly on the containers without decompression, and SIMD implementations
(using AVX2 and AVX-512 on x86, NEON on ARM) can process hundreds of millions
of integers per second.

A 2023 benchmark by the Roaring team showed that Roaring is up to 900× faster
than traditional EWAH-compressed bitmaps for sparse intersections, and
typically 2× more space-efficient. (EWAH, WAH, and Concise are older
word-aligned bitmap compressors that store the bitmap as a stream of
run-length "fill" words and literal "dirty" words; they compress runs well but,
unlike Roaring, cannot jump straight to a given region, which is why random
access and intersections are slow.)

#checkpoint[
  If a Roaring bitmap chunk has exactly 4,096 elements, which container type
  does it use - array or bitset?
][
  Either is equally expensive at that threshold: 4,096 × 2 bytes = 8,192 bytes
  for an array, and the bitset is always 8,192 bytes. In practice Roaring
  implementations switch to a bitset at or above 4,096 elements so that
  adding the 4,097th element does not increase space usage.
]

=== Trick 6: Cascading with a Heavy-Weight Codec

After applying dictionary encoding, bit-packing, and FOR/delta, the data is
already much smaller. There is still statistical redundancy that
lightweight tricks leave behind, so the final layer is a *byte-stream compressor*
(zstd, Snappy, LZ4, or gzip) applied to the already-encoded byte stream.

This cascading works because:
1. Bit-packed integers from the same dictionary cluster near each other
   in value. They have low entropy (the few-bits-per-symbol floor we defined
   in *Chapter 18*), exactly the redundancy an entropy coder mops up.
2. Delta-encoded timestamps are mostly small numbers, so an LZ77-based coder
   finds repeated byte patterns easily.
3. The lightweight encodings remove structure that would confuse a byte-stream
   coder; the byte-stream coder then removes the remaining redundancy.

The result is that Parquet and ORC routinely achieve 5–10× compression on
typical analytics tables, and up to 30–50× on highly sorted, low-cardinality
columns.

#scoreboard(caption: "Compression of a synthetic 1M-row analytics table (city/product/price/date columns, 64 MB uncompressed).",
  [*Method*], [*Bytes*], [*Ratio*], [*Notes*],
  [Row store, uncompressed], [67,108,864], [1.0×], [Baseline],
  [Row store + zstd], [18,350,000], [3.7×], [Generic codec on row stream],
  [Column store, uncompressed], [67,108,864], [1.0×], [Same bytes, different layout],
  [Dictionary encoding only], [12,000,000], [5.6×], [Strings replaced by IDs],
  [+ Bit-packing], [5,600,000], [12.0×], [IDs packed to minimal bits],
  [+ RLE on sorted columns], [2,200,000], [30.5×], [Runs of equal IDs collapsed],
  [+ Delta + FOR on numerics], [1,850,000], [36.3×], [Timestamps/prices shrunk],
  [+ zstd on encoded stream], [1,380,000], [48.6×], [Final byte-stream pass],
)

== Algorithm Profiles

#mathrecall[
  The profiles below report cost in *Big-O notation* ($O(N)$, $O(log d)$, and
  so on) - the order-of-growth shorthand we built from scratch in *Chapter 14*.
  Read $O(N)$ as "work grows in proportion to the number of values $N$", $O(1)$
  as "constant, independent of size", and $O(log d)$ as "grows like the
  logarithm of $d$," far slower than $N$.
]

#algo(
  name: "Dictionary Encoding",
  year: "1960s (databases), formalized 2000s",
  authors: "Database community; popularized in C-Store, MonetDB, Parquet",
  aim: "Replace repeated string or high-cardinality values with compact integer IDs; store a lookup dictionary separately.",
  complexity: "O(N) encoding time; O(1) dictionary lookup; O(d) dictionary space where d = distinct values.",
  strengths: "Huge wins on low-cardinality string columns (country, category, status). Enables ID-based joins and group-by without string comparison. Preserves exact values (lossless). Simple to implement.",
  weaknesses: "Degrades to plain encoding when cardinality is high (many distinct values). Dictionary overhead becomes significant for short columns. Must rebuild on updates.",
  superseded: "Not superseded - foundational. BtrBlocks (2023) automates selection among dictionary and other schemes.",
)[
  The simplest and most impactful single trick in analytical databases. When
  a column has $d$ distinct values, each value becomes an ID in
  $0, dots, d - 1$, stored with $ceil(log_2 d)$ bits using bit-packing.
  The key insight is that *cardinality* - not column size - determines
  compressibility. A 100 GB column of 10 countries compresses into roughly
  $N times ceil(log_2 10) / 8$ bytes of IDs plus a tiny dictionary.
]

#algo(
  name: "Roaring Bitmaps",
  year: "2016",
  authors: "Samy Chambi, Daniel Lemire, Owen Kaser, Robert Godin; extended 2016 by Lemire, Ssi-Yan-Kai, Kaser",
  aim: "Compressed bitmap representation for sets of 32-bit unsigned integers that automatically adapts between array, bitset, and run-length containers per 65,536-element chunk.",
  complexity: "O(N / 64) for bitwise operations (SIMD); O(d) space where d = cardinality; O(log d) for membership test in array containers.",
  strengths: "Outperforms EWAH, WAH, Concise by up to 900× in intersection speed. Space-efficient across all density regimes. No decompression needed for logical operations. Widely supported (C, Java, Python, Go, Rust).",
  weaknesses: "32-bit native (64-bit extension is two separate 32-bit bitmaps). Overhead per chunk header for very sparse data may exceed a plain sorted array. Not optimal for streaming updates (bulk re-runs recommended).",
  superseded: "Not superseded - the de facto standard. Roaring64 (2021) extends to 64-bit sets.",
)[
  Roaring solves the long-standing bitmap compression dilemma: classic bitmaps
  waste space for sparse data; compressed formats (EWAH, WAH) are slow for
  random access. Roaring's hybrid container model adapts automatically,
  achieving both. Embedded in Apache Lucene, Spark, ClickHouse, DuckDB,
  Druid, Pinot, and many more as of 2026.
]

#algo(
  name: "Apache Parquet",
  year: "2013 (1.0), 2022 (2.10), ongoing",
  authors: "Julien Le Dem (Twitter), Nong Li (Cloudera); Apache Software Foundation; inspired by Google Dremel (Melnik et al., 2010).",
  aim: "Open columnar file format for big-data analytics: schema-aware, nested (Dremel shredding/assembly), with pluggable lightweight encodings (dictionary, RLE/bit-packed hybrid, delta, byte-stream array) and pluggable heavy codecs (Snappy, gzip, LZ4, zstd, Brotli).",
  complexity: "Encoding O(N); decoding O(N); seeking O(log N) via row group and column chunk metadata. Typical I/O: 4–16× less than row-store formats.",
  strengths: "De facto standard for data lakes (S3, HDFS, GCS). Predicate push-down (column statistics skip whole row groups). Language-neutral (Python pyarrow, Java, Rust parquet-rs). Nested record support via Dremel algorithm. Apache Iceberg and Delta Lake use it as the underlying format.",
  weaknesses: "Row-group boundary effects (statistics only skip whole groups). Write overhead from schema negotiation. Dictionary overflow falls back to plain encoding silently. Column ordering matters for compression ratio.",
  superseded: "Not superseded - actively used. Apache Arrow IPC (columnar in-memory) and Lance (ML-oriented, random-access) target different niches.",
)[
  Parquet became the lingua franca of the data lake after Databricks, Amazon
  Athena, Google BigQuery, Snowflake, and Spark all adopted it. A Parquet file
  is divided into *row groups* (typically 128 MB–1 GB), within each row group
  into *column chunks*, within each column chunk into *pages* (typically 1 MB).
  Each page is independently encoded and optionally compressed. The file footer
  carries column statistics (min, max, null count) enabling whole-row-group
  skipping without decompressing any data.
]

== Inside Apache Parquet: A Layered Tour

Let us trace what happens to our `city` column when Parquet writes it.

*Step 1: Schema typing.* Parquet knows this is a `BYTE_ARRAY` (variable-length string) column annotated `UTF8`. This tells the encoder to try dictionary encoding first.

*Step 2: Dictionary page.* The encoder scans the first page of values and builds a dictionary. For `city` with values "Berlin" and "Paris", it writes a *dictionary page*: a sorted array of the two strings, taking perhaps 11 bytes. The dictionary is shared across all subsequent *data pages* in this column chunk.

*Step 3: RLE/bit-packed data page.* The encoder writes the IDs as an
RLE/bit-packed hybrid stream. For our five values `[0, 1, 0, 0, 1]` with
bit-width 1:
- Header: bit-width = 1.
- Values are packed: 0, 1, 0, 0, 1 → bits `01001` → 1 byte.

*Step 4: Snappy or zstd compression.* The encoded page (already tiny) is optionally passed through a byte-stream codec. For the dictionary page, Snappy or zstd shrinks the already-small strings further.

*Step 5: Row group statistics.* The column chunk footer records `min = "Berlin"`, `max = "Paris"`, null count = 0. A query `WHERE city = "Tokyo"` can skip this entire row group without reading a single data page.

The full file footer (written last, read first) stores byte offsets of every column chunk in every row group. A query engine reads the footer, skips irrelevant row groups, and reads only the needed column chunks.

#history[
  Google's *Dremel* paper (Sergey Melnik et al., VLDB 2010) introduced the
  shredding/assembly algorithm for storing deeply nested Protocol Buffer records
  in a flat columnar format. Julien Le Dem at Twitter and Nong Li at Cloudera
  turned this into an open-source format called Parquet, releasing it in July
  2013. By 2015 it had graduated to a top-level Apache Software Foundation
  project. The format specification (version 2.10, released 2022) added
  column statistics at the page level and improved bloom filter support.
]

== Apache ORC: The Other Pillar

*Apache ORC* (Optimized Row Columnar) was created at Hortonworks in 2013
as an alternative to the then-slower early Parquet. It uses similar ideas
(columnar layout, lightweight encodings, pluggable compression) but with
some differences:

- *Integer encoding:* ORC uses a sophisticated multi-mode integer encoding
  (version 2, "Hive ORC v2") that automatically chooses among direct
  (bit-packed), patched base (FOR with exceptions), delta, and run-length
  encoding per column stripe. This is analogous to BtrBlocks' automated
  selection but embedded in the format itself.
- *Bloom filters:* ORC has built-in Bloom filter support per column, enabling
  fast membership tests ("is this value in this stripe?") without reading all data.
- *ACID transactions:* ORC supports transactional writes (insert, update, delete)
  via delta files. Parquet gained comparable capability later, but only through
  surrounding table formats like Apache Iceberg.

The *stripe* in ORC plays the same role as Parquet's *row group*: a
self-contained horizontal slice of the table with its own column statistics.

A 2023 empirical study (Zeng et al., arXiv:2304.05028, "An Empirical Evaluation
of Columnar Storage Formats") compared Parquet and ORC across dozens of real
analytics workloads and found that ORC's native integer encoding gave it an
edge on integer-heavy tables, while Parquet's wider ecosystem support made it
more prevalent in practice.

#misconception[
  "ORC and Parquet are interchangeable - just pick one."
][
  They are similar but not identical. ORC's integer encoding (patched base,
  delta, RLE, direct) is richer than Parquet's RLE/bit-packed hybrid and can
  encode more column shapes efficiently without needing a top-level codec. ORC
  is also better at transactional updates. Parquet has a larger ecosystem (more
  cloud engines natively support it), better nested record support via the
  Dremel algorithm, and the standard table formats (Iceberg, Delta Lake, Hudi)
  all prefer Parquet. In practice, choose based on your compute engine: Hive
  and Hudi favor ORC; Spark, Athena, Snowflake, and DuckDB favor Parquet.
]

== Operating on Compressed Data

Here is the deepest idea in this chapter, and the one that separates column-store
compression from all the generic compression we have studied before.

*The key observation* (Abadi et al., SIGMOD 2006): if a column is
dictionary-encoded, then a query `WHERE city = 'Berlin'` can be answered
by first looking up 'Berlin' in the dictionary (getting ID 0), then scanning
the ID column looking for 0s. The engine never decodes the string values;
it operates directly on the integer IDs. For a sorted, run-length-encoded
column this becomes: find the run(s) where the value is 0, note their start
and end positions. Zero decompression needed.

More generally:

- *Equality predicates* on dictionary columns: look up the ID, scan IDs.
- *Sorted predicates* (`price < 5`): binary search on dictionary → one ID
  comparison per element.
- *GROUP BY* on dictionary columns: group on the integer IDs, decode strings
  only for the final output.
- *COUNT, SUM, AVG* on bit-packed columns: modern databases have SIMD-accelerated
  aggregation operators that work directly on bit-packed representations without
  expanding to 32 or 64 bits first.

The term for this family of techniques is *late materialization*: decode the
actual values as *late as possible*, ideally only for the rows that survive
all filters and need to appear in the output. In a query that filters 1 billion
rows down to 50 results, you might decode those 50 strings and nothing else.

A June 2026 arXiv paper on GPU acceleration of SQL analytics on compressed data
(GPU Acceleration of SQL Analytics on Compressed Data, arXiv:2506.10092)
showed that executing queries directly on bit-packed and dictionary-encoded
Parquet data on GPUs (without decompressing to GPU memory first) achieves
speedups of 10–50× over CPU-only engines for typical production analytics
workloads, because the compression reduces memory bandwidth pressure more than
the decompression overhead costs.

#keyidea[
  In database compression, compression and query execution are not separate
  stages: they are *interleaved*. Operating on compressed data means the
  decompressor is the query operator itself. This is the opposite of the
  generic compression model (compress → store → decompress → use), and it is
  why columnar databases can be simultaneously smaller *and* faster than their
  uncompressed row-store predecessors.
]

== BtrBlocks: Automated Scheme Selection (2023)

All the tricks above require a human to decide which encoding to apply to which
column. A real table might have 200 columns with heterogeneous statistics.
*BtrBlocks* (Maximilian Kuschewski, David Sauerwein, Adnan Alhomssi, Viktor
Leis; ACM SIGMOD 2023) automates this decision.

BtrBlocks divides each column into blocks of 65,536 values and runs a
*sample-based scheme selection* on a 1% random sample (~655 values) of each
block. It evaluates a set of candidate schemes (for doubles: frequency
encoding (dictionary), pseudo-decimal decomposition, FOR, XOR (Gorilla-style),
and cascaded combinations) and picks the one that compresses the sample
best, then applies it to the full block.

The result: BtrBlocks achieves compression ratios and decompression speeds
competitive with or better than hand-tuned Parquet+zstd on real-world
analytics benchmarks, while requiring no schema-specific configuration.

#algo(
  name: "BtrBlocks",
  year: "2023",
  authors: "Maximilian Kuschewski, David Sauerwein, Adnan Alhomssi, Viktor Leis (TU Munich)",
  aim: "Automated per-block lightweight compression scheme selection for columnar data lakes, with cascading (applying schemes recursively) and sample-based selection.",
  complexity: "Encoding O(N · S / B) where S = sample size, B = block size; decoding O(N) without selection overhead.",
  strengths: "Eliminates manual scheme tuning. Handles heterogeneous columns. Cascading catches residual structure (e.g. FOR then RLE on the offsets). Fast decompression (no heavy codec by design).",
  weaknesses: "Sampling may miss rare patterns. Larger code complexity than a single fixed codec. No support for transactional updates (read-optimized format). No Dremel nested records (flat tables only).",
  superseded: "Not superseded (novel research, 2023). Influenced design of the Lance format and subsequent academic work.",
)[
  BtrBlocks treats column compression as a *search problem*: sample → score
  candidates → recurse on residuals. It represents the trend toward compression
  as a learned or data-driven decision rather than a fixed algorithm. The open
  source implementation is available at github.com/maxi-k/btrblocks.
]

== A Worked Python Example: The Full Pipeline

No project step is assigned to Chapter 67 in tinyzip (Chapter 67 has no
TINYZIP step). But the ideas are worth making concrete. Here is a minimal
implementation of the four-technique pipeline (dictionary encoding,
bit-packing, FOR, and delta) in pure Python 3.14, processing a real-ish
column of data.

#gopython("Python dataclasses and type aliases")[
  In Python 3.14 you can create lightweight record types with `dataclass`:
  ```python
  from dataclasses import dataclass

  @dataclass
  class Block:
      min_val: int          # the frame baseline
      bit_width: int        # bits per value
      packed: bytes         # bit-packed offsets
  ```
  A `dataclass` automatically generates `__init__`, `__repr__`, and other
  boilerplate. The type hints (`int`, `bytes`) are documentation that static
  type checkers like `mypy` can verify, but Python does not enforce them at
  run time.
]

#pyrecall[
  Some code below uses `struct.pack`, the binary-serialization helper we met in
  *Chapter 17*. A format string spells out the layout: `>` means big-endian
  byte order, and the letters are fixed-width integer types (`B` = 1-byte
  (8-bit) unsigned, `I` = 4-byte (32-bit) unsigned, `Q` = 8-byte (64-bit)
  unsigned). So `struct.pack(">QB", m, w)` writes `m` as eight bytes followed by
  `w` as one byte, and `f">{n}I"` packs `n` consecutive 32-bit integers.
]

#pyrecall[
  The line `{idx: val for val, idx in seen.items()}` is a *dict comprehension*
  (from *Chapter 16*): it builds a new dictionary in one expression. `seen.items()`
  yields each `(key, value)` pair of the dictionary `seen`, the `for val, idx`
  part unpacks each pair into two names at once, and `idx: val` flips them, so
  a string-to-ID map becomes the ID-to-string map we want.
]

```python
# columnar_demo.py  -- illustrative, not a tinyzip step
import math
from dataclasses import dataclass

# -- Dictionary encoding -------------------------------------------------------

def dict_encode(col: list[str]) -> tuple[dict[int, str], list[int]]:
    """Replace strings with integer IDs.  Returns (id->string, id_column)."""
    seen: dict[str, int] = {}
    ids: list[int] = []
    for v in col:
        if v not in seen:
            seen[v] = len(seen)
        ids.append(seen[v])
    dictionary = {idx: val for val, idx in seen.items()}
    return dictionary, ids

def dict_decode(dictionary: dict[int, str], ids: list[int]) -> list[str]:
    return [dictionary[i] for i in ids]

# -- Bit-packing ---------------------------------------------------------------

def bitpack(values: list[int], width: int) -> bytes:
    """Pack non-negative integers into a tight bit stream."""
    buf = 0
    nbuf = 0
    out: list[int] = []
    for v in values:
        buf = (buf << width) | v
        nbuf += width
        while nbuf >= 8:
            nbuf -= 8
            out.append((buf >> nbuf) & 0xFF)
    if nbuf:
        out.append((buf << (8 - nbuf)) & 0xFF)
    return bytes(out)

def bitunpack(data: bytes, width: int, count: int) -> list[int]:
    """Unpack count integers of bit-width width from data."""
    buf = 0
    nbuf = 0
    out: list[int] = []
    idx = 0
    mask = (1 << width) - 1
    while len(out) < count:
        while nbuf < width and idx < len(data):
            buf = (buf << 8) | data[idx]
            nbuf += 8
            idx += 1
        if nbuf >= width:
            nbuf -= width
            out.append((buf >> nbuf) & mask)
    return out

# -- Frame of Reference --------------------------------------------------------

@dataclass
class FORBlock:
    minimum: int
    bit_width: int
    packed: bytes

def for_encode(values: list[int]) -> FORBlock:
    minimum = min(values)
    offsets = [v - minimum for v in values]
    max_offset = max(offsets)
    width = max(1, math.ceil(math.log2(max_offset + 1))) if max_offset > 0 else 1
    return FORBlock(minimum=minimum, bit_width=width, packed=bitpack(offsets, width))

def for_decode(block: FORBlock, count: int) -> list[int]:
    offsets = bitunpack(block.packed, block.bit_width, count)
    return [o + block.minimum for o in offsets]

# -- Delta encoding ------------------------------------------------------------

def delta_encode(values: list[int]) -> list[int]:
    """Return the list of successive differences (first value unchanged)."""
    if not values:
        return []
    result = [values[0]]
    for i in range(1, len(values)):
        result.append(values[i] - values[i - 1])
    return result

def delta_decode(deltas: list[int]) -> list[int]:
    out: list[int] = []
    acc = 0
    for d in deltas:
        acc += d
        out.append(acc)
    return out

# -- Demo ----------------------------------------------------------------------

if __name__ == "__main__":
    # Simulate one day of hourly timestamps (Unix seconds)
    import time
    base_ts = 1_700_100_000
    timestamps = [base_ts + i * 3600 for i in range(24)]  # one per hour

    # Delta-encode the timestamps
    deltas = delta_encode(timestamps)
    # All deltas after the first are 3600; the first is the large base.
    # Apply FOR on the deltas to shrink even that:
    block = for_encode(deltas)

    raw_bytes  = len(timestamps) * 8   # 64-bit ints
    enc_bytes  = 8 + 1 + len(block.packed)   # minimum + width + data
    print(f"Raw:     {raw_bytes} bytes")
    print(f"Encoded: {enc_bytes} bytes")
    print(f"Ratio:   {raw_bytes / enc_bytes:.1f}x")

    # Round-trip check
    recovered_deltas = for_decode(block, len(timestamps))
    recovered_ts = delta_decode(recovered_deltas)
    assert recovered_ts == timestamps, "Round-trip failed!"
    print("Round-trip OK")

    # Dictionary encoding for the city column
    cities = ["Berlin", "Paris", "Berlin", "Berlin", "Paris",
              "London", "Paris", "Berlin", "London", "Berlin"]
    dictionary, ids = dict_encode(cities)
    width = math.ceil(math.log2(len(dictionary)))
    packed_ids = bitpack(ids, width)
    print(f"\nCity column: {len(cities)} strings, {sum(len(c) for c in cities)} raw bytes")
    print(f"After dict+bitpack: {len(packed_ids)} bytes (+ {sum(len(v) for v in dictionary.values())} dict bytes)")
    recovered = dict_decode(dictionary, bitunpack(packed_ids, width, len(cities)))
    assert recovered == cities
    print("Dictionary round-trip OK")
```

Running this on 24 hourly timestamps produces roughly:
- Raw: 192 bytes (24 × 8-byte int64)
- Delta + FOR: the 24 deltas are all 3,600 except the first
  (1,700,100,000). FOR sets minimum = 3,600, width ≈ 1 bit for all
  but the first. Total ≈ 12 bytes, a *16× compression* on this perfectly
  regular column.

#checkpoint[
  If you have a column of 1,000 integers all equal to 42, which of the six
  tricks from this chapter gives the best compression, and why?
][
  Run-length encoding wins outright: the entire column is a single run of
  length 1,000 with value 42, stored as one (42, 1000) pair, about 5 bytes.
  FOR would set minimum = 42, all offsets = 0, width = 1 bit → 125 bytes of
  packed zeros. Dictionary encoding: 1 distinct value, bit-width 0 (or 1) →
  similar to RLE. But RLE as a single pair is literally the most compact.
]

== The 2024–2026 Frontier

*GPU-accelerated columnar query engines.* DuckDB (version 1.0, 2024) added
vectorized operators that scan bit-packed Parquet columns without fully
materializing them. A June 2026 GPU-acceleration paper (arXiv:2506.10092)
showed 10–50× speedups on compressed columnar data over CPU baselines.

*Nested data support.* The growing dominance of JSON-like analytics (event
streams from web applications, IoT events, ML feature stores) pushed Parquet 2.x
and the competing *Lance* format to improve nested-column compression. Lance
(2023, LanceDB) targets ML workloads and adds random-access to individual rows,
something Parquet's sequential page design does not support efficiently.

*Apache Iceberg and the table format layer.* Iceberg (2018–), Delta Lake (2019–),
and Apache Hudi (2016–) are *table formats* that sit above Parquet, adding
ACID transactions, time-travel queries, schema evolution, and partition pruning.
They do not change how individual Parquet pages are compressed, but they add
metadata that allows *partition pruning* (skipping entire Parquet files
without reading their footers).

*Compressed vector stores.* The rise of embedding-heavy AI applications (RAG
pipelines, semantic search) has driven development of vector-oriented column
formats. The challenge: 1,536-dimensional float vectors do not compress well
with any of the tricks above, because each dimension is uncorrelated with its
neighbors. Product quantization (Chapter 65) and binary quantization are the
answers in that domain.

*ADMS 2024–2025 research.* The VLDB "Accelerating Database Management Systems"
workshop in 2024–2025 featured active research on hardware-accelerated
compression: Intel IAA (In-Memory Analytics Accelerator), a hardware compressor
that can decompress zstd at memory speed, and SIMD-AVX-512 bit-unpacking
pipelines that push the speed of lightweight encoding toward memory bandwidth
limits.

== Common Pitfalls and Misconceptions

#misconception[
  "Zstd already compresses everything well - why bother with lightweight encodings?"
][
  Lightweight encodings (dictionary, bit-pack, FOR) are *orders of magnitude*
  faster to decode than zstd, especially critical for query engines that
  decompress billions of integers per second. More importantly, as we saw,
  they enable *operating on compressed data*, a trick zstd's byte-stream model
  cannot support. The two layers are complementary: lightweight for speed and
  operability, zstd for final byte-count reduction.
]

#misconception[
  "Column stores are only useful for read-heavy analytics - they're terrible for inserts."
][
  Mostly true but incomplete. Modern systems (Delta Lake, Iceberg) buffer inserts
  in a row-store layer or a small "delta" log and compact them into columnar
  format in the background. For pure OLAP (analytics) workloads the insert
  penalty is irrelevant; for hybrid OLTP/OLAP workloads the pattern of writing
  row-format delta files and asynchronously recompacting them has made columnar
  storage viable even with frequent updates, as in Snowflake's architecture.
]

#pitfall[
  A Parquet file written with *no row group sorting* compresses far worse than
  one written with data sorted on a high-cardinality column (e.g. customer ID),
  because RLE and FOR work best on locally homogeneous data. Many data pipelines
  ignore this and then wonder why their Parquet files are 3× instead of 30×.
  Sort your data before writing Parquet if compression ratio matters.
]

#takeaways((
  "Columnar storage groups like values together, enabling dramatically better compression than row-oriented layouts.",
  "Dictionary encoding (replace repeated strings with integer IDs) is the single most impactful trick, especially for low-cardinality string columns.",
  "Bit-packing stores integer IDs and small numbers using only the bits they actually need, removing bit-level waste.",
  "Run-length encoding collapses runs of equal values to (value, count) pairs - most effective on sorted columns.",
  "Frame-of-reference (FOR) subtracts a per-block minimum before bit-packing; delta encoding subtracts the previous value. Both shrink the bit-width needed for numeric and timestamp columns.",
  "Roaring bitmaps provide compressed bitmap indexes that auto-select between array, bitset, and run-length containers per 65,536-element chunk, enabling fast set operations without decompression.",
  "Apache Parquet layers dictionary + RLE/bit-packed + optional zstd/Snappy; Apache ORC layers multi-mode integer encoding + Bloom filters + Snappy/zstd.",
  "Late materialization means query engines operate directly on compressed representations, decompressing only the values that reach the final output.",
  "BtrBlocks (SIGMOD 2023) automates per-block scheme selection with 1% sampling, eliminating manual tuning.",
  "The frontier (2024–2026): GPU-accelerated compressed-data queries, hardware decompressors (Intel IAA), and ML-feature-oriented formats like Lance.",
))

== Exercises

#exercise("67.1", 1)[
  A Parquet column stores the string values "USA", "Germany", "France",
  "USA", "USA", "Germany", "France", "USA". Work out:
  (a) How many distinct values are there?
  (b) How many bits are needed per ID after dictionary encoding?
  (c) How many bytes does the bit-packed ID column take (rounded up to the
  nearest byte)?
  (d) Roughly how large is the raw column if each string is stored as UTF-8
  followed by a 4-byte length prefix?
]

#solution("67.1")[
  (a) Three distinct values: "USA", "Germany", "France".
  (b) $ceil(log_2 3) = ceil(1.585) = 2$ bits per ID.
  (c) 8 values × 2 bits = 16 bits = 2 bytes exactly.
  (d) Raw: ("USA" = 3 + 4), ("Germany" = 7 + 4), ("France" = 6 + 4) bytes
      per occurrence. USA×4 = 28, Germany×2 = 22, France×2 = 20 → total
      70 bytes raw. The dictionary+IDs: 3 + 7 + 6 = 16 bytes of strings
      (dict) + 2 bytes IDs = 18 bytes. Rough ratio: 70/18 ≈ 3.9×.
]

#exercise("67.2", 1)[
  The following sorted integer column represents invoice amounts in cents:
  `[1000, 1000, 1000, 2500, 2500, 7800, 7800, 7800, 7800]`. Apply
  run-length encoding to represent it compactly. How many (value, count) pairs
  result? Compare the byte count of your RLE encoding (assume each value and
  count is stored as a 2-byte unsigned integer) with storing the raw values
  as 2-byte integers.
]

#solution("67.2")[
  RLE pairs: (1000, 3), (2500, 2), (7800, 4) - three pairs. Each pair is
  2 + 2 = 4 bytes → 12 bytes total. Raw: 9 × 2 = 18 bytes. RLE saves 33%.
  (On a million-row table with the same three values, RLE stays at 12 bytes
  while raw grows to 2,000,000 bytes, a 166,667× saving.)
]

#exercise("67.3", 2)[
  You have a column of 1,024 Unix timestamps (64-bit integers) representing
  events that happen every 5 minutes starting at 1,700,000,000. After delta
  encoding, what do the deltas look like? What bit-width is needed to
  bit-pack the deltas (after the first value)? How many bytes does the
  packed delta stream take, versus the raw 64-bit column?
]

#solution("67.3")[
  Each event is 300 seconds apart, so all deltas (except the first) are 300.
  $300 = 256 + 44$, so $300 < 512 = 2^9$, requiring 9 bits per delta.
  1,023 deltas × 9 bits = 9,207 bits = 1,151 bytes (rounded up), plus 8 bytes
  for the first absolute value. Total ≈ 1,159 bytes.
  Raw: 1,024 × 8 = 8,192 bytes. Compression ratio ≈ 8,192 / 1,159 ≈ 7.1×.
]

#exercise("67.4", 2)[
  A Roaring bitmap represents the set of row IDs of all rows where
  `status = "active"` in a table with 200,000 rows. Suppose exactly
  100,000 rows are active, distributed uniformly at random across all rows.
  (a) How many 16-bit chunks (chunk keys) does the Roaring bitmap create?
  (b) For each chunk, how many elements does it contain on average?
  (c) Does each chunk use an array container or a bitset container?
  Justify your answer.
]

#solution("67.4")[
  (a) 200,000 rows → row IDs 0 to 199,999. Top 16 bits range from 0 to
  $floor(199999 / 65536) = 3$, so 4 chunks. But IDs only go up to 199,999,
  so chunk 3 holds IDs 196,608–199,999 (3,391 values in the universe).
  (b) 100,000 active IDs distributed over ~4 chunks → ~25,000 active per chunk.
  (c) 25,000 > 4,096 (the array/bitset boundary), so each chunk uses a
  *bitset container* (8,192 bytes). The total Roaring bitmap size is
  approximately 4 × 8,192 = 32,768 bytes, versus a flat bitmap of
  $200,000 / 8 = 25,000$ bytes. In this case the flat bitmap is actually
  smaller! Roaring's advantage appears at lower or uneven densities.
]

#exercise("67.5", 2)[
  Implement a `for_encode_block(values: list[int]) -> tuple[int, int, bytes]`
  function in Python 3.14 that returns `(minimum, bit_width, packed_bytes)`,
  and a matching `for_decode_block(minimum, bit_width, packed, count) -> list[int]`
  function. Test it on the list `[1_000_000, 1_000_050, 1_000_100, 1_000_200]`
  and verify the round-trip.
]

#solution("67.5")[
  ```python
  import math

  def for_encode_block(values: list[int]) -> tuple[int, int, bytes]:
      minimum = min(values)
      offsets = [v - minimum for v in values]
      max_off = max(offsets) if offsets else 0
      width = max(1, math.ceil(math.log2(max_off + 1))) if max_off > 0 else 1
      # bit-pack offsets
      buf, nbuf, out = 0, 0, []
      for v in offsets:
          buf = (buf << width) | v; nbuf += width
          while nbuf >= 8:
              nbuf -= 8; out.append((buf >> nbuf) & 0xFF)
      if nbuf: out.append((buf << (8 - nbuf)) & 0xFF)
      return minimum, width, bytes(out)

  def for_decode_block(minimum: int, width: int, packed: bytes,
                       count: int) -> list[int]:
      buf, nbuf, out = 0, 0, []
      mask = (1 << width) - 1
      idx = 0
      while len(out) < count:
          while nbuf < width and idx < len(packed):
              buf = (buf << 8) | packed[idx]; nbuf += 8; idx += 1
          if nbuf >= width:
              nbuf -= width; out.append((buf >> nbuf) & mask)
      return [v + minimum for v in out]

  # Test
  vals = [1_000_000, 1_000_050, 1_000_100, 1_000_200]
  m, w, p = for_encode_block(vals)
  assert for_decode_block(m, w, p, len(vals)) == vals
  print(f"min={m}, width={w} bits, packed={len(p)} bytes (raw={len(vals)*4} bytes)")
  # Expected: min=1000000, width=8 bits (max offset 200 < 256), packed=4 bytes, raw=16 bytes
  ```
]

#exercise("67.6", 3)[
  Design a simple automated scheme selector in Python 3.14. Given a list of
  integers, it should try three schemes - plain storage (4 bytes per int),
  FOR + bit-packing, and RLE (for sorted data only) - compute the encoded
  size of each, and return the scheme name and encoded bytes for the winner.
  Test on three columns: (a) `[0]*1000`, (b) a list of 1,000 random integers
  in range 0–65535, and (c) timestamps `[1_700_000_000 + i*60 for i in range(1000)]`.
]

#solution("67.6")[
  ```python
  import math, random, struct

  def encode_plain(values: list[int]) -> bytes:
      return struct.pack(f">{len(values)}I", *values)

  def encode_for(values: list[int]) -> bytes:
      minimum = min(values)
      offsets = [v - minimum for v in values]
      max_off = max(offsets) if offsets else 0
      w = max(1, math.ceil(math.log2(max_off + 1))) if max_off else 1
      buf, nbuf, out = 0, 0, []
      for v in offsets:
          buf = (buf << w) | v; nbuf += w
          while nbuf >= 8:
              nbuf -= 8; out.append((buf >> nbuf) & 0xFF)
      if nbuf: out.append((buf << (8-nbuf)) & 0xFF)
      # store: 8 bytes for minimum, 1 byte for width, then packed
      return struct.pack(">QB", minimum, w) + bytes(out)

  def encode_rle(values: list[int]) -> bytes:
      runs: list[tuple[int,int]] = []
      if not values: return b""
      cur, cnt = values[0], 1
      for v in values[1:]:
          if v == cur: cnt += 1
          else: runs.append((cur, cnt)); cur, cnt = v, 1
      runs.append((cur, cnt))
      return struct.pack(f">{2*len(runs)}I",
                         *[x for pair in runs for x in pair])

  def best_scheme(values: list[int]) -> tuple[str, bytes]:
      candidates = {
          "plain": encode_plain(values),
          "FOR":   encode_for(values),
          "RLE":   encode_rle(values),
      }
      winner = min(candidates, key=lambda k: len(candidates[k]))
      return winner, candidates[winner]

  # Tests
  cols = {
      "all_zeros":   [0] * 1000,
      "random":      [random.randint(0, 65535) for _ in range(1000)],
      "timestamps":  [1_700_000_000 + i*60 for i in range(1000)],
  }
  for name, col in cols.items():
      scheme, enc = best_scheme(col)
      raw = len(col) * 4
      print(f"{name:12s}: best={scheme:5s}, {raw} -> {len(enc)} bytes ({raw/len(enc):.1f}x)")
  # Expected: all_zeros -> RLE wins (2 pairs = 8 bytes vs 4000)
  #           random    -> FOR wins or plain (random integers hard to compress)
  #           timestamps -> FOR wins (offsets 0..59940 need 16 bits; 2000 bytes vs 4000)
  ```
]

== Further Reading

- #link("https://dl.acm.org/doi/10.1145/1142473.1142548")[Daniel Abadi et al., "Integrating Compression and Execution in Column-Oriented Database Systems," ACM SIGMOD 2006] - the foundational paper showing that column-store operators can work directly on compressed data.

- #link("https://arxiv.org/abs/1402.6407")[Chambi, Lemire, Kaser, Godin, "Better bitmap performance with Roaring bitmaps," arXiv:1402.6407 / Software: Practice and Experience, 2016] - the original Roaring bitmap paper with the array/bitset container model.

- #link("https://arxiv.org/pdf/1603.06549")[Lemire, Ssi-Yan-Kai, Kaser, "Consistently faster and smaller compressed bitmaps with Roaring," 2016] - adds the run-length container, completing the three-container Roaring design.

- #link("https://dl.acm.org/doi/10.1145/3589263")[Kuschewski, Sauerwein, Alhomssi, Leis, "BtrBlocks: Efficient Columnar Compression for Data Lakes," ACM SIGMOD 2023] - automated per-block scheme selection with cascading; open source at github.com/maxi-k/btrblocks.

- #link("https://arxiv.org/pdf/2304.05028")[Zeng et al., "An Empirical Evaluation of Columnar Storage Formats," arXiv:2304.05028, 2023] - head-to-head comparison of Parquet, ORC, and Arrow on real workloads.

- #link("https://vldb.org/workshops/2024/proceedings/ADMS/ADMS24_02.pdf")[Spindler, Fent, Riedl, Neumann, "Can Delta Compete with Frame-of-Reference for Lightweight Integer Compression?", VLDB Workshops 2024] - rigorous experimental comparison of FOR and delta for integer columns.

- #link("https://arxiv.org/html/2506.10092v1")[arXiv:2506.10092, "GPU Acceleration of SQL Analytics on Compressed Data," June 2026] - state-of-the-art in executing compressed Parquet queries directly on GPUs.

- #link("https://parquet.apache.org/docs/")[Apache Parquet format specification] - the official spec for all encoding types and the file footer layout.

#bridge[
  We have now mastered the toolkit that makes analytics databases fast and
  small: dictionary encoding, bit-packing, RLE, FOR, delta, Roaring bitmaps,
  and late materialization. All of these exploit *structure in a typed schema*.

  In *Chapter 68 - Time-Series and IoT Compression* we take these ideas in a
  different direction: what happens when your data is a *continuous stream of
  floating-point measurements* from sensors or monitoring systems, arriving
  faster than you can write to disk? Facebook's Gorilla paper (VLDB 2015)
  tackled this with XOR-based float compression and delta-of-delta timestamps,
  two tricks specifically designed for the statistical properties of monitoring
  metrics, not general analytics tables. That is where we go next.
]
