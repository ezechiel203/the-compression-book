#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Delta, Diff, and Deduplication

#epigraph[
  "The most powerful insight in computer science is that two things which
  look different might, at their core, be exactly the same."
][Anonymous systems programmer]

Imagine you are maintaining the operating system on a million computers. Every few weeks
you push a security update. A typical OS image is 500 MB. Sending 500 MB to a million
machines is 500 terabytes of traffic — and you are updating a handful of changed functions
inside one library, maybe 50 KB of real changes.

What if you could send only the _difference_ between the old file and the new one?
Fifty kilobytes, not five hundred megabytes. A 10,000-to-1 saving. That is the core
promise of *delta compression* — and it is used every time your phone receives an app
update, every time you pull a Git commit, and every time a backup system stores your
files without duplicating what it already has.

This chapter covers three tightly related ideas that all exploit the same insight — that
data often already exists, somewhere, in a slightly different form, and we only need to
record the change:

- *Delta compression and binary diffing:* computing the differences between two versions
  of a file and encoding only those differences.
- *Deduplication:* finding and eliminating duplicate chunks across many files or many
  backups, so identical content is stored exactly once.
- *Real-world systems:* Git packfiles, Docker layers, Borg/Restic backup tools, and ZFS.

Along the way you will see that the same "predict from what is already known, encode
only the residual" trick that powered DPCM (Chapter 40) and inter-frame video prediction
(Chapter 51) is alive and well in your file system.

#recap[
  In Chapter 28 we built LZ77's sliding-window match finder: the encoder scans forward,
  finds the longest match in a history buffer, and emits a _(distance, length)_ back-reference.
  That is delta compression in miniature — but the "dictionary" is the recent past of
  the _same_ file. In delta compression we extend this idea across _two different files_:
  the old version is the dictionary, and the new version is what we are encoding against it.

  Chapter 51 showed the same principle in video: a P-frame is encoded as differences from
  a reference frame. Chapter 40 described DPCM: encode only the residual after subtracting
  a prediction. Delta compression is DPCM across file versions rather than across time.

  Chapter 35 introduced the BWT and suffix arrays. Those same data structures appear
  in bsdiff's suffix-sort step.
]

#objectives((
  "Understand the delta-compression model: source + delta → target.",
  "Trace how VCDIFF (RFC 3284) encodes deltas with ADD, COPY, and RUN instructions.",
  "Explain how bsdiff exploits suffix arrays for high-quality binary patches.",
  "Define content-defined chunking (CDC) and explain why fixed-size chunking fails.",
  "Describe Rabin fingerprints and the FastCDC algorithm.",
  "Explain file-level and chunk-level deduplication and their trade-offs.",
  "Trace how Git packfiles, Docker layers, Borg, Restic, and ZFS use these ideas.",
))

== The Model: Source, Target, Delta

All delta compression follows the same three-part model.

You have a *source* — the old version of the data, already known to both the
encoder and the decoder. You want to transmit a *target* — the new version. Instead
of transmitting the target in full, you compute and transmit a *delta* (also called
a *patch*). The decoder reconstructs the target by applying the delta to the source:

$ "target" = "apply"("source", "delta") $

The delta is useful only if it is smaller than the target. How much smaller depends
on how similar the two files are. If you are patching version 3.1.2 of a library with
version 3.1.3, the files are 99% identical and the delta might be 1% the size of the
original. If you try to delta-compress two completely unrelated files, the delta will
be at least as large as the target — no savings at all.

#keyidea[
  Delta compression works by exploiting the similarity between two versions of
  the same data. The more similar source and target are, the better the delta.
  If source and target share nothing, delta compression cannot help.
]

=== Fixed-Range vs. Whole-File Deltas

LZ77 (Chapter 28) works within a single file: the "source" is a sliding window of
the recent past, and we look for matches in that window. Delta compression is the
same idea scaled up to whole files: the entire source file is the dictionary, and
the encoder finds matches anywhere within it.

This means a delta compressor must solve a search problem: given a byte sequence in
the target, find the longest matching sequence anywhere in (potentially megabytes of)
source. A naive scan would be too slow. Every efficient delta compressor uses an
index over the source — a hash table or a suffix array — to make this fast.

== VCDIFF: The Standard Delta Format

The most important standard for delta encoding is *VCDIFF*, specified in
IETF RFC 3284 (Korn, MacDonald, Mogul, and Vo, 2002). VCDIFF defines both
the _format_ of a delta (what a patch file looks like on disk) and a reference
_algorithm_ for computing deltas based on work by Jon Bentley and Douglas McIlroy
from 1999.

VCDIFF is the format used by *xdelta3*, the most widely deployed open-source delta
tool, and it is the delta format used internally by Google's Chrome update
infrastructure and Shared Dictionary Compression over HTTP.

=== The Three Instructions

A VCDIFF delta is a sequence of three types of instruction that together describe
how to reconstruct the target file:

#table(
  columns: (auto, 1fr),
  stroke: 0.5pt,
  fill: (col, row) => if row == 0 { rgb("#e8f0f8") } else { white },
  [*Instruction*], [*Meaning*],
  [`ADD n, data`],  [Copy `n` bytes of literal data directly into the output.],
  [`COPY n, pos`],  [Copy `n` bytes starting at position `pos` in the source (or in the target for self-referential copies).],
  [`RUN n, byte`],  [Emit `n` copies of a single byte value.],
)

That is the entire instruction set. The art is in choosing which instruction to use
and at what position — that is the _delta computation_ problem.

#aside[
  `RUN` is a special case of `ADD` for constant runs, optimized because runs are
  common (null-padding, zero-filled blocks) and a single byte costs far less to
  encode than `n` literal bytes.
]

=== A Tiny VCDIFF Example

Suppose the source file is the string `"the cat sat on the mat"` and the target
is `"the cat sat on the hat"`. Only the last word changed: `mat` → `hat`.

The VCDIFF delta might look like:

```
COPY 19, 0       # copy "the cat sat on the " from source[0..19]
ADD  1, "h"      # add literal "h"
COPY 2, 20       # copy "at" from source[20..22]
```

That is 3 instructions instead of 22 bytes — and in practice the instruction stream
itself is entropy-coded (the RFC allows an application-level codec like zlib on top).

#gopython("String slicing to reconstruct a VCDIFF-style delta")[
  Python slices let you pull a subrange of a string or bytes object.
  `s[start:end]` returns bytes at positions `start, start+1, …, end-1`.
  Index 0 is the first byte; negative indices count from the end.

  ```python
  source = b"the cat sat on the mat"
  target = b"the cat sat on the hat"

  # Manually apply the 3 instructions above:
  result  = source[0:19]       # COPY 19 from position 0
  result += b"h"               # ADD 1 byte
  result += source[20:22]      # COPY 2 from position 20

  assert result == target
  print(result)  # b'the cat sat on the hat'
  ```

  Real VCDIFF works the same way but automatically finds these instructions
  using an index structure over the source.
]

=== Computing a VCDIFF Delta

The standard approach (used by xdelta3) builds a *hash table* over the source:
for every overlapping window of some fixed length (e.g., 32 bytes) in the source,
record the (hash → position) mapping. Then scan the target from left to right:
at each position, hash the next 32 bytes, look it up in the source table, and
if a match is found, extend it as far as possible. If no match is found, emit an
`ADD` instruction for that byte.

This is structurally identical to LZ77 hash-chain matching (Chapter 28), except
the "history" is a separate file rather than the recent past of the same file.

#algo(
  name: "VCDIFF / xdelta",
  year: "2002 (RFC 3284); xdelta3 implementation 2007",
  authors: "Korn, MacDonald, Mogul, Vo (RFC); Joshua MacDonald (xdelta3)",
  aim: "Generic format and algorithm for encoding the difference between a source and a target as a sequence of ADD/COPY/RUN instructions.",
  complexity: "O(N) encoding with hash index; O(M) decoding (N = source size, M = target size).",
  strengths: "Standardized format; fast encoding; any general codec can be applied on top of the instruction stream; self-referential copies allow compression even of additions.",
  weaknesses: "Hash-based matching can miss the best patch for highly rearranged content; quality lower than bsdiff for binary executables.",
)[
  Used in: Chrome/Chromium updates (alongside Courgette preprocessing), Google's
  Shared Dictionary Compression over HTTP (SDCH, since retired), various software
  update pipelines. RFC 3284 download available at `https://www.rfc-editor.org/rfc/rfc3284`.
]

== bsdiff: Suffix Sorting for Better Binary Patches

VCDIFF with a hash table is fast but not always optimal — a match starting at
an unusual position can be missed if the hash collides or the window size misses it.
Colin Percival addressed this in 2003 with *bsdiff*, a binary patching tool that
uses a _suffix array_ over the source to find the best possible match for every
position in the target.

#history[
  Colin Percival, then a PhD student at Oxford, published bsdiff in 2003 as
  part of his work on FreeBSD's update system. Originally named `bdiff/bpatch`,
  it was renamed to avoid clashes. The name "bsdiff" is sometimes said to stand
  for "binary software diff" or to be an abbreviation with a less polite first word
  — Percival himself left it ambiguous.

  bsdiff became the foundation for software update diffing at Apple (macOS updates),
  Google (Chrome updates, via Courgette which preprocesses executables before bsdiff),
  and mobile app stores worldwide. A 2003 benchmark showed bsdiff producing patches
  50–80% smaller than xdelta for binary executables.
]

=== Why Executables Are Hard to Diff

Binary executables are deceptive: two versions of a program might be logically
nearly identical — the same functions, just recompiled — yet differ by thousands
of bytes scattered throughout the file because of address relocation. When a function
moves by 16 bytes, every pointer to it changes. A naive differ finds no long matches
because the bytes at every address have shifted.

Percival's key insight: before comparing bytes, subtract them. If `source[i] = 200`
and `target[j] = 201`, the _difference_ is only 1. Two aligned versions of a binary
will have very similar difference vectors even when the absolute bytes differ widely.

bsdiff encodes three streams:
1. *Control stream:* triples $(x, y, z)$ meaning "match $x$ bytes using the difference,
   then copy $y$ new literal bytes, then skip $z$ bytes in source."
2. *Difference stream:* the byte-by-byte difference $("target"[i] - "source"[i + "offset"])$ for
   each matched byte, entropy-compressed with bzip2.
3. *Extra stream:* the literal bytes for unmatched regions, also bzip2-compressed.

#gomaths("Modular byte arithmetic")[
  When bsdiff computes the "difference" between bytes, it uses modular arithmetic
  modulo 256 (since bytes are integers from 0 to 255). The difference of bytes
  $a$ and $b$ is defined as $(b - a) mod 256$, which always gives a result in
  $[0, 255]$.

  *Example:* if source byte = 200 and target byte = 205, the difference is
  $(205 - 200) mod 256 = 5$, which fits in one byte.
  If source byte = 250 and target byte = 3, the difference is
  $(3 - 250) mod 256 = (3 - 250 + 256) mod 256 = 9 mod 256 = 9$.

  Because nearby versions of an executable differ by small amounts at most
  positions, the difference stream has very low entropy — it is dominated
  by zeros and small values — and bzip2 compresses it extremely well.
]

=== Finding Matches with a Suffix Array

The heart of bsdiff is a suffix array over the source. Recall from Chapter 35:
a *suffix array* for a string $S$ of length $N$ is the array of all $N$ suffixes
of $S$, sorted lexicographically. This lets you binary-search for any pattern in
$O(|P| dot log N)$ time. bsdiff builds a suffix array over the source file, then for
each position in the target binary-searches to find the suffix in the source that
matches the longest prefix of the remaining target.

#mathrecall[Suffix arrays (Chapter 35) sort all suffixes of a string and enable
  O(|pattern| × log N) substring search by binary search — the same structure used
  by the FM-index for genomic alignment.]

Because the comparison is done on raw bytes — including the non-contiguous "this
byte is close to this source byte" heuristic using the difference trick — bsdiff
tends to find longer and better matches than hash-based approaches.

#algo(
  name: "bsdiff",
  year: "2003",
  authors: "Colin Percival",
  aim: "Compute a compact binary patch between two versions of a file, especially executables, using suffix-array matching and byte-difference encoding.",
  complexity: "O(N log N) encoding (suffix sort dominates); O(N + M) decoding. Memory: O(N) for the suffix array.",
  strengths: "Produces very small patches for binary executables; handles relocated code naturally via byte-difference encoding; broadly deployed.",
  weaknesses: "Slow encoding for large files; requires suffix array in RAM (O(N) space); no streaming — the full source must be present.",
)[
  Tool page: `https://www.daemonology.net/bsdiff/`. Google's Courgette preprocesses
  executables (disassembling them to normalize addresses) before applying bsdiff,
  shrinking Chrome update sizes further.
]

=== Courgette: Preprocessing for Even Smaller Patches

Google engineers noticed that most of the "noise" in binary patches comes from
address relocation — pointer values that change by a fixed offset when a function
moves. Courgette (released 2009) first _disassembles_ the executable to a
pseudo-assembly language, normalizes all relative addresses so they are expressed
as labels rather than absolute offsets, then applies bsdiff. The result: Chrome
updates roughly 10× smaller than naive bsdiff, and roughly 100× smaller than
sending a new binary.

This is the same principle as predictive coding: remove the predictable component
(address layout), then encode only the residual (actual code changes).

== From File Deltas to Chunk-Level Deduplication

Delta compression works brilliantly when you have two _specific_ versions of a file
to compare. But backup systems face a different problem: they store thousands of
files, many of which share large identical regions — two virtual machine disk images
might share an operating system, or many users might store the same popular PDF.

*Deduplication* is the technique of finding and eliminating this redundancy by
storing each unique piece of data exactly once. There are two main levels:

=== File-Level Deduplication

The simplest form: hash every file, and if two files have the same hash (SHA-256 is
the standard), store only one copy and just add a pointer for the second. This works
for exact duplicates but misses the case where two files are 95% identical —
like two versions of the same document.

#gopython("Computing a file's SHA-256 hash in Python")[
  `hashlib` is Python's built-in cryptographic hashing library. A hash function
  takes any number of bytes and returns a fixed-size digest (for SHA-256, always
  32 bytes = 256 bits). Same input always gives same output; any change, even a
  single bit, gives a completely different output.

  ```python
  import hashlib

  def file_sha256(path: str) -> str:
      """Return the hex SHA-256 digest of a file."""
      h = hashlib.sha256()
      with open(path, "rb") as f:
          for chunk in iter(lambda: f.read(65536), b""):
              h.update(chunk)
      return h.hexdigest()

  # Two identical files will produce the same digest
  digest = file_sha256("report.pdf")
  print(digest)
  # e.g. "3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b"
  ```

  Two new tricks here. We read the file in 64 KB pieces (rather than loading the
  whole thing into memory) and feed each piece to `h.update`, because a digest can
  be built up incrementally. The loop uses the two-argument form of `iter`:
  `iter(callable, sentinel)` calls `callable()` over and over until it returns the
  `sentinel` value, then stops. Here `callable` is `lambda: f.read(65536)` — a
  throwaway one-line function (the `lambda`, from Chapter 16) that reads the next
  64 KB — and the sentinel is `b""`, the empty `bytes` that `read` returns at
  end-of-file. So the loop walks the file 64 KB at a time and halts when the file
  runs out. File-level deduplication hashes every file this way and stores duplicates
  as pointers to the existing copy.
]

=== Block-Level Deduplication: The Naive Approach (and Its Fatal Flaw)

To catch partial duplicates, we can split files into fixed-size *blocks* (say,
4 KB each), hash every block, and store only unique blocks. This already works
much better — two Linux ISO images might deduplicate at 90%.

But there is a fatal flaw: *the shift problem*. Insert one byte near the start
of a file and every subsequent fixed-size block shifts by one byte. Two blocks
that were identical in the old and new version are now at different offsets
and hash to different values, so deduplication fails catastrophically for even
tiny edits.

This is exactly why video inter-frame prediction uses motion vectors to align
blocks before comparing them (Chapter 51). We need the same idea for byte streams.

#pitfall[
  Fixed-size chunking fails when the file changes. A single inserted byte shifts
  every subsequent block, destroying all deduplication hits for the rest of the file.
  This is called the *boundary-shift problem*, and it is the key motivation for
  content-defined chunking.
]

== Content-Defined Chunking (CDC)

The solution is to choose chunk boundaries based on the _content_ of the file,
not on fixed byte positions. If the same content appears in both the old and new
version of a file — even if it has shifted in position — content-defined chunking
will assign the same boundary positions relative to the content and produce the
same chunk, so it will hash to the same value.

#keyidea[
  *Content-defined chunking (CDC):* split a byte stream at positions determined
  by the content itself (a local property of the bytes), not by a fixed offset.
  Identical content, wherever it appears, produces the same chunks — even if
  surrounding content has changed.
]

=== Rabin Fingerprints: The Classic CDC Algorithm

The most famous CDC algorithm uses *Rabin fingerprints*, introduced by Michael
O. Rabin in 1981. A Rabin fingerprint is a *rolling hash*: a hash function computed
over a sliding window of bytes that can be updated in $O(1)$ time as the window
slides one byte forward.

#gomaths("Rolling hashes")[
  A *rolling hash* $H(w)$ of a window of $w$ bytes has the property that when the
  window slides one position forward (dropping the oldest byte $b_"out"$ and adding
  a new byte $b_"in"$), you can compute the new hash from the old hash in constant
  time:

  $ H_"new" = "update"(H_"old", b_"out", b_"in") $

  without re-hashing all $w$ bytes from scratch. This makes it possible to evaluate
  the hash at every position in a file of length $N$ in total time $O(N)$ rather
  than $O(N times w)$.

  The Rabin fingerprint uses polynomial arithmetic over GF(2) — arithmetic where
  every number is just a single bit (0 or 1) and "add" means XOR (Chapter 5).
  Think of the window's $w$ bytes as the long list of bits of a polynomial $P(x)$,
  then the fingerprint is the remainder $P(x) mod Q(x)$ after dividing by a fixed
  $Q(x)$. ($Q(x)$ is chosen to be _irreducible_ — it has no smaller factors, the
  polynomial version of a prime number — which spreads the fingerprints out so
  collisions are rare.) Because this kind of division is _linear_ (it plays nicely
  with XOR), sliding the window one byte corresponds to a simple XOR and shift —
  computable in one or two CPU instructions. You do not need any of this to use a
  rolling hash; the analogy below is all the intuition the rest of the chapter needs.

  *Simpler analogy:* imagine the rolling hash as a running "personality score" of
  the last 64 bytes. Each new byte nudges the score, and the oldest byte's
  contribution is subtracted. When the personality score hits a special value —
  say, the last 13 bits are all zero — you declare a chunk boundary. On average
  this happens every $2^(13) = 8192$ bytes.
]

The chunk-boundary rule is: declare a boundary at position $i$ if and only if
$H_i "mod" T = 0$, where $T$ is the *target chunk size*. Because the test depends
only on the content of the window, two streams containing the same byte sequence
will agree on boundary positions — regardless of what precedes them.

#fig(
  [Content-defined chunking with a rolling hash. The hash is evaluated at every
   byte position. Boundaries (vertical bars) are declared when the hash hits
   a special pattern. An insertion near the start shifts content but preserves
   boundaries determined by later, unchanged content.],
  cetz.canvas({
    import cetz.draw: *
    // Draw a file stream
    rect((0,3),(12,4), fill: rgb("#dbeafe"), stroke: 0.7pt)
    content((6,3.5))[ #text(size: 8pt)[File byte stream] ]

    // Draw chunk boundaries
    line((2,3),(2,4), stroke: 1.5pt + rgb("#1d4ed8"))
    line((5,3),(5,4), stroke: 1.5pt + rgb("#1d4ed8"))
    line((8,3),(8,4), stroke: 1.5pt + rgb("#1d4ed8"))
    line((11,3),(11,4), stroke: 1.5pt + rgb("#1d4ed8"))

    // Label chunks
    content((1,2.5))[#text(size:7.5pt)[Chunk A]]
    content((3.5,2.5))[#text(size:7.5pt)[Chunk B]]
    content((6.5,2.5))[#text(size:7.5pt)[Chunk C]]
    content((9.5,2.5))[#text(size:7.5pt)[Chunk D]]

    // Rolling hash indicator
    rect((4,1),(6,2), fill: rgb("#dcfce7"), stroke: 0.7pt)
    content((5,1.5))[#text(size:7.5pt)[rolling hash\nwindow (64 B)]]
    line((5,2),(5,3), stroke: (dash:"dashed"))

    // Labels
    content((2,4.3))[#text(size:7.5pt, fill: rgb("#1d4ed8"))[boundary]]
    content((5,4.3))[#text(size:7.5pt, fill: rgb("#1d4ed8"))[boundary]]
    content((8,4.3))[#text(size:7.5pt, fill: rgb("#1d4ed8"))[boundary]]
  })
)

=== FastCDC: A 10x Faster Alternative

Rabin-based CDC is the historical standard but can be slow. Wen Xia et al. published
*FastCDC* at USENIX ATC 2016, achieving about 10 times the throughput of Rabin CDC
while maintaining nearly the same deduplication ratio. FastCDC uses three key ideas:

1. *Gear hash:* replace Rabin's polynomial computation with a simpler table-lookup
   hash (called a Gear hash) that is faster to compute per byte.
2. *Skip sub-minimum:* chunks smaller than a minimum size are never cut — the
   algorithm skips all positions up to `min_size` without evaluating the hash,
   saving time.
3. *Normalized chunking:* after skipping the minimum zone, use a stricter boundary
   condition near the beginning of the "expected" zone and a looser one near the
   maximum size, which makes the chunk-size distribution much more uniform.

FastCDC is now the default chunker in several modern backup tools including
Restic (since 2022).

#algo(
  name: "Content-Defined Chunking (CDC) / FastCDC",
  year: "Rabin fingerprints: Rabin 1981; applied to CDC: LBFS 2001; FastCDC: Xia et al., USENIX ATC 2016",
  authors: "Michael O. Rabin (fingerprints); Athicha Muthitacharoen et al. (LBFS CDC); Wen Xia et al. (FastCDC)",
  aim: "Split a byte stream at content-determined boundaries so that identical content, wherever it appears, produces identical chunks — enabling deduplication across shifted or partially-changed files.",
  complexity: "O(N) scan of the file using O(1) rolling hash update per byte.",
  strengths: "Eliminates boundary-shift problem; chunks are position-independent; deduplication works across file versions and across different files sharing content.",
  weaknesses: "Chunk sizes vary (must cap at a max size to bound memory); the chunking function is a parameter to tune; does not help if files share no common subsequences.",
)[
  Used in: Borg backup (variable-sized Rabin chunking), Restic (FastCDC since
  2022), Casync (content-addressable tar), rsync (rolling-checksum block matching
  is a related idea). Paper: `https://www.usenix.org/conference/atc16/technical-sessions/presentation/xia`
]

== Deduplication Systems in Practice

With content-defined chunking, every unique chunk gets a hash fingerprint (SHA-256
in most systems). The deduplication store is simply a hash → chunk data mapping.
Before writing a chunk, check if its hash is already in the store. If yes, just
store a reference (the hash); if no, store the full chunk data.

This creates a *content-addressable storage* (CAS): data is addressed by its
content (its hash), not by its location. The same chunk of data, found in ten
different files on ten different days, is stored exactly once.

=== Borg Backup

*Borg* (BorgBackup, first release 2010 as Attic; renamed Borg in 2015) is the
most popular open-source deduplication backup tool. It uses variable-sized chunking
with Buzhash (a rolling hash similar to Rabin) and stores chunks in a repository
indexed by BLAKE2b hash. Borg's deduplication is *global* within a repository:
if you back up 10 machines to the same repo, chunks that appear in multiple machine
images are stored once. A typical Linux server backup occupies only 5–20% of its
naive size once a few snapshots have accumulated.

Borg also encrypts chunks before storing them (AES-CTR with an HMAC-SHA256 MAC),
applies zstd compression (or LZ4 or none, selectable), and verifies integrity on
restore using the stored hash.

=== Restic

*Restic* (2015) takes a similar approach but is designed for simplicity and
portability: it stores each chunk (called a "pack") as a blob in object storage
(local filesystem, S3, B2, SFTP, etc.), addressed by SHA-256. Since 2022 it uses
FastCDC. Restic encrypts all data at rest using AES-256-CTR and an HMAC-SHA256
check-tag, before deduplication — which means the repository server learns nothing
about file contents.

#checkpoint[
  Borg and Restic both split files into variable-size chunks and store chunks by
  hash. What is the main difference between them?
][
  Borg stores everything in a local or network-mountable repository format optimized
  for fast access; it uses a local chunk index. Restic stores each chunk as a separate
  object addressable in cloud storage (S3, B2, etc.) and uses a simpler on-disk
  format. Restic prioritizes portability and encryption before deduplication; Borg
  prioritizes performance and compression ratio.
]

=== ZFS Block-Level Deduplication

ZFS (originally from Sun Microsystems, now maintained by OpenZFS) can deduplicate
at the *block level* within a storage pool: before writing any block, ZFS computes
its SHA-256 hash and consults a per-pool deduplication table. If the block already
exists in the pool, ZFS stores only a reference. ZFS deduplication is _inline_
(happens on the write path, synchronously) and _block-level_ (not chunk-level —
boundaries are fixed by the block size, typically 4–128 KB).

ZFS deduplication has a reputation for being memory-hungry: the dedup table must
fit in RAM for reasonable performance (roughly 5 GB of RAM per TB of unique data).
For this reason, many ZFS deployments use compression (LZ4/zstd) but disable dedup,
relying on larger-scale deduplication at the application layer instead.

#pitfall[
  ZFS block-level deduplication uses fixed block boundaries, so it suffers from
  the boundary-shift problem. It works best for workloads where files are rarely
  modified (VM images written once, database snapshot exports) rather than for
  incrementally updated files.
]

=== Comparison: Block vs. Chunk-Level Dedup

#scoreboard(
  caption: "Deduplication approaches: trade-offs.",
  [*Approach*], [*Boundary type*], [*Shift-resistant*], [*Example tools*],
  [File-level], [Whole file], [Yes (no boundaries)], [basic hard-linking],
  [Block-level], [Fixed size], [No], [ZFS dedup, early VMs],
  [Chunk-level (Rabin)], [Content-defined], [Yes], [Borg, old Restic],
  [Chunk-level (FastCDC)], [Content-defined], [Yes, faster], [Restic ≥ 2022, Casync],
)

== Git Packfiles: Delta Compression Inside Version Control

Git is the most widely used version control system in the world, and its storage
model is a masterclass in applying delta compression at scale.

=== Git's Object Model

Every object in Git (a file snapshot called a *blob*, a directory listing called
a *tree*, a commit, or a tag) is stored as a zlib-compressed file named by its
SHA-1 (or SHA-256 in newer Git) hash. This is content-addressable storage at the
object level — the same file content always has the same hash and is stored once.

Initially Git stores each object as a separate "loose object" file. Over time, as
objects accumulate, Git packs them into *packfiles* for efficiency.

=== Inside a Packfile

A packfile stores many objects in a single binary file. Each object is stored in
one of two forms:

- *Undeltified:* the object's zlib-compressed content, stored directly.
- *Deltified:* a compact delta against another object in the same packfile.

The two deltified types are called `OBJ_OFS_DELTA` (offset-based: "my base is
$k$ bytes before me in this packfile") and `OBJ_REF_DELTA` (name-based: "my base
is the object with this SHA-1 hash"). Git prefers `OBJ_OFS_DELTA` because it
is 3–5% more compact (no need to store the full 20-byte name).

The delta format inside a packfile is a custom instruction set, related in spirit
to VCDIFF but not byte-compatible: `COPY` from the base object and `INSERT` new
literal bytes.

#history[
  Git was created by Linus Torvalds in April 2005, in roughly ten days, as a
  replacement for BitKeeper after a licensing dispute. The packfile format and
  delta compression were crucial design decisions: without them, a repository of
  the Linux kernel (50,000+ files, 30+ years of history) would occupy hundreds
  of gigabytes. With packfiles and delta compression, the entire Linux kernel
  history fit comfortably in a few gigabytes by the 2010s.

  The `git pack-objects` command controls the delta compression: it sorts
  candidate object pairs by type, size, and name similarity, then uses a
  sliding window of objects (controlled by `--window`) to find good delta bases.
  Deeper delta chains compress better but slow down random access.
]

=== How Git Finds Good Delta Bases

The `git pack-objects` command sorts objects by type and filename, then slides
a window of typically 10 objects and tries using each as the base for every
other object in the window. The pair with the best (smallest) delta wins.
Objects with similar names (e.g., `src/foo.c` at commit $n$ and `src/foo.c`
at commit $n-1$) tend to be good delta pairs and end up next to each other
after sorting.

#fig(
  [Git packfile delta chain. Each object can be stored as a delta against
   another. Decoding requires walking the chain back to the first
   undeltified base.],
  cetz.canvas({
    import cetz.draw: *
    // Base object
    rect((0,1.5),(2.5,2.5), fill: rgb("#dbeafe"), stroke: 0.7pt)
    content((1.25,2))[#text(size:8pt)[Base blob\n(zlib, full)]]

    // Delta objects
    rect((4,2),(6.5,3), fill: rgb("#dcfce7"), stroke: 0.7pt)
    content((5.25,2.5))[#text(size:8pt)[Delta 1\n(COPY+INSERT)]]

    rect((4,0.5),(6.5,1.5), fill: rgb("#dcfce7"), stroke: 0.7pt)
    content((5.25,1))[#text(size:8pt)[Delta 2\n(COPY+INSERT)]]

    rect((8,0.5),(10.5,1.5), fill: rgb("#fef9c3"), stroke: 0.7pt)
    content((9.25,1))[#text(size:8pt)[Delta 3\n(COPY+INSERT)]]

    // Arrows (OFS_DELTA chain)
    line((2.5,2),(4,2.5), mark: (end: ">"), stroke: 0.7pt)
    line((2.5,2),(4,1), mark: (end: ">"), stroke: 0.7pt)
    line((6.5,1),(8,1), mark: (end: ">"), stroke: 0.7pt)

    content((3.25,2.6))[#text(size:7pt)[base]]
    content((3.25,1.3))[#text(size:7pt)[base]]
    content((7.25,0.65))[#text(size:7pt)[base of 2]]
  })
)

=== Delta Depth and the Speed Trade-off

Delta chains can be nested: Delta 1 is stored against Base, Delta 2 is stored
against Delta 1, Delta 3 against Delta 2, and so on. Deeper chains can achieve
better compression (each delta is tinier), but decoding requires walking the
entire chain. Git defaults to a maximum delta depth of 50. Shallow repositories
or repositories optimized for fast random reads use shallower chains.

#checkpoint[
  Why does Git's packfile format use delta compression between _different_ versions
  of the same file rather than just storing each version in full?
][
  Because successive versions of a source file are typically 95–99% identical, the
  delta is tiny compared to the full content. Storing 1,000 commits of a 100 KB
  file would require 100 MB with full storage; with delta compression it might
  require only a few MB, since most commits change only a handful of lines.
]

== Docker Layers: Deduplication for Containers

Docker images are stacks of *layers*. Each layer captures the changes made to
the filesystem by one step in a `Dockerfile` (e.g., `RUN apt-get install nginx`).
Layers are immutable and content-addressed by SHA-256.

The key insight is the same as in Git: if ten images all build on the same base
Ubuntu layer, that layer is stored exactly once. A `docker pull` only downloads
the layers you do not already have. This is file-level deduplication applied
to filesystem snapshots.

=== How Docker Layers Work

When a container is started, Docker uses the Linux kernel's *OverlayFS* to stack
read-only layers into a single unified filesystem view. The bottommost layer is
the base image; each successive layer adds, modifies, or marks files as deleted
(a "whiteout" file). The running container sees one coherent filesystem.

Each layer is stored as a tar archive on disk, addressed by its SHA-256 digest.
Docker Engine 29.0 and later (2025) uses containerd's image store by default,
where layers are stored by digest in a content store — identical layers across
different images share storage transparently.

#aside[
  Docker layers are *not* content-defined chunks of file data — they are file-level
  diffs of directory trees. If a single large file changes by one byte, the entire
  file appears in the new layer. This is why Docker best practices recommend placing
  frequently-changing files at the top of the layer stack: each `Dockerfile` line
  creates a new layer, and changing a line invalidates all subsequent layers.
]

#fig(
  [Docker image layers stacked with OverlayFS. Three images share the same
   base Ubuntu layer, saving storage.],
  cetz.canvas({
    import cetz.draw: *
    // Shared base
    rect((0,0),(10,1), fill: rgb("#bfdbfe"), stroke: 0.7pt)
    content((5,0.5))[#text(size:8pt)[Layer 0: Ubuntu 24.04 base (stored once, ~30 MB)]]

    // Image 1 layers
    rect((0,1.1),(3,2.1), fill: rgb("#bbf7d0"), stroke: 0.7pt)
    content((1.5,1.6))[#text(size:7.5pt)[nginx layer\n(Image A)]]
    rect((0,2.2),(3,3.2), fill: rgb("#fde68a"), stroke: 0.7pt)
    content((1.5,2.7))[#text(size:7.5pt)[app layer\n(Image A)]]

    // Image 2 layers
    rect((3.5,1.1),(6.5,2.1), fill: rgb("#bbf7d0"), stroke: 0.7pt)
    content((5,1.6))[#text(size:7.5pt)[python layer\n(Image B)]]
    rect((3.5,2.2),(6.5,3.2), fill: rgb("#fde68a"), stroke: 0.7pt)
    content((5,2.7))[#text(size:7.5pt)[flask app\n(Image B)]]

    // Image 3 layers
    rect((7,1.1),(10,2.1), fill: rgb("#bbf7d0"), stroke: 0.7pt)
    content((8.5,1.6))[#text(size:7.5pt)[nginx layer\n(shared!)]]
    rect((7,2.2),(10,3.2), fill: rgb("#fde68a"), stroke: 0.7pt)
    content((8.5,2.7))[#text(size:7.5pt)[config layer\n(Image C)]]

    // Arrow indicating sharing
    content((5,-0.5))[#text(size:7.5pt, fill: rgb("#1d4ed8"))[All three images share this layer — stored once on disk.]]
  })
)

== Putting It All Together: The rsync Insight

All of the techniques in this chapter are variations on one idea, first articulated
clearly by Andrew Tridgell in the *rsync* algorithm (1996):

1. Split the target into chunks (rsync uses fixed-size blocks, but modern tools
   use CDC).
2. Hash each chunk.
3. Send only the chunks that the receiver does not already have.

rsync over a slow network link is roughly equivalent to sending a binary delta.
The receiver has the old version of a file; rsync's rolling-checksum protocol
identifies which 512-byte blocks of the new file match blocks in the old file,
and transfers only the novel bytes. This is a distributed VCDIFF without an
explicit patch format.

#aside[
  Andrew Tridgell's 1996 PhD thesis (University of Canberra) described the
  rsync algorithm. The key insight was using a weak (Adler-32 based) rolling hash
  to find _candidate_ matching blocks quickly, then confirming matches with a
  strong MD4 hash — a two-level filter that made the protocol efficient even on
  slow links. rsync became one of the most-used Unix utilities and directly inspired
  the content-defined chunking line of research.
]

== A Worked Example: Deduplicating Three Backups

Let us trace through a concrete example. You are backing up a project directory
to Borg. It contains three large files:

- `data.csv` — 10 MB, the same on Monday, Tuesday, and Wednesday (not modified)
- `model.pkl` — 50 MB on Monday; 51 MB on Tuesday (retrained); 51.5 MB on Wednesday
- `report.pdf` — 5 MB on Monday; the first page updated on Tuesday and Wednesday

On *Monday* (first backup), Borg chunks all three files using its rolling hash
(target chunk size ~2 MB). Suppose `data.csv` produces 5 chunks (D1–D5), `model.pkl`
produces 25 chunks (M1–M25), and `report.pdf` produces 3 chunks (R1–R3). Total
unique chunks: 33. Total data stored: ~65 MB.

On *Tuesday* (second backup), Borg rechunks:
- `data.csv`: produces the exact same 5 chunks D1–D5 (file unchanged). *All already in the store.* Zero new data stored.
- `model.pkl`: mostly the same chunks M1–M24, but the tail changed → one new chunk M26. Stored: ~2 MB.
- `report.pdf`: R1 changed (first page), R2–R3 unchanged. New chunk R1'. Stored: ~2 MB.

Tuesday's snapshot metadata references: D1–D5, M1–M24, M26, R1', R2, R3.
New data written: ~4 MB. Total stored: ~69 MB for _two_ complete snapshots.

On *Wednesday* (third backup), a similar analysis yields another few MB of new chunks.
Three complete snapshots, representing 3 × 65 = 195 MB of data, stored in perhaps
80 MB total. The deduplication ratio is roughly 2.4:1.

This is the everyday magic of a deduplication backup tool.

== Delta Compression vs. Traditional Compression: When to Use Which

It is worth pausing to compare these techniques with the general-purpose compressors
we studied in Chapters 28–36.

#table(
  columns: (auto, 1fr, 1fr),
  stroke: 0.5pt,
  fill: (col, row) => if row == 0 { rgb("#e8f0f8") } else { white },
  [*Technique*], [*Best for*], [*Requires*],
  [General compression (zstd, LZ77)], [Redundancy within one file], [Just the file itself],
  [Delta compression (xdelta, bsdiff)], [Two versions of the same file], [Both old and new version simultaneously],
  [File deduplication], [Exact duplicate files], [A hash index of all files],
  [Chunk deduplication (Borg, Restic)], [Partial duplicates across files/backups], [A chunk store + content-defined chunking],
  [Git delta (packfiles)], [Many versions of many files, version history], [The whole repository; index of objects],
)

In practice, these techniques are layered: Borg compresses each unique chunk with
zstd before storing it, on top of the deduplication. Zstandard itself trains on
a dictionary that represents "typical" data, which is a lightweight form of delta
coding. The layers reinforce each other.

== Further Developments: Similarity-Based Deduplication

Standard deduplication finds _identical_ chunks. *Similarity-based* (or *delta
deduplication*) goes further: if two chunks are not identical but are similar
(e.g., two versions of a document that differ slightly), it stores one full chunk
and a delta against it. This is used in enterprise deduplication systems (EMC
Data Domain, NetApp WAFL) and can achieve significantly higher ratios at the cost
of more CPU.

The algorithm: given a new chunk, find the most similar existing chunk (using
a sampling fingerprint — hash a few bytes from different positions in the chunk),
then apply a lightweight binary diff (often a VCDIFF variant) and store the diff.

#misconception[
  "Deduplication and compression are the same thing."
][
  They are related but distinct. *Compression* removes redundancy _within_ a single
  stream by finding repeated patterns and encoding them compactly. *Deduplication*
  removes redundancy _across_ streams by identifying identical chunks and storing
  them once. A 100 MB file with no internal redundancy compresses poorly but can
  deduplicate perfectly against an identical copy. A file with high internal
  redundancy (e.g., all zeros) compresses to near-nothing but does not deduplicate
  against a different file unless they share chunks. In practice, you use both:
  deduplicate first (identify unique chunks), then compress each unique chunk.
]

#takeaways((
  "Delta compression encodes a target file as a sequence of instructions (COPY, ADD, RUN) applied to a known source, sending only the difference.",
  "VCDIFF (RFC 3284) is the standard format; xdelta3 implements it with a hash-based matcher. bsdiff uses suffix-array matching and byte-difference encoding for much smaller patches on binary executables.",
  "Fixed-size chunking fails when files shift; content-defined chunking (CDC) uses rolling hashes to place boundaries based on content, not position, eliminating the boundary-shift problem.",
  "Rabin fingerprints are the classical rolling hash for CDC; FastCDC (Xia et al., 2016) achieves ~10× higher throughput with near-identical deduplication ratios.",
  "Deduplication stores each unique chunk once (addressed by SHA-256), sharing it across all files and backups that contain it. Borg and Restic implement this with encryption and compression on top.",
  "Git packfiles use object-level delta compression (OBJ\_OFS\_DELTA / OBJ\_REF\_DELTA) between similar blobs, making it feasible to store decades of version history in a few gigabytes.",
  "Docker uses OverlayFS to stack immutable, content-addressed layers; identical layers across images are stored once, providing file-level deduplication for container images.",
  "General compression, delta compression, and deduplication are complementary and are routinely combined: deduplicate to remove identical chunks, then compress each unique chunk.",
))

== Exercises

#exercise("71.1", 1)[
  VCDIFF uses three instructions: ADD, COPY, and RUN. For the source string
  `"aaabbbccc"` and the target string `"aaabbbcccaaabbbccc"`, write out a minimal
  sequence of VCDIFF instructions that produces the target from the source.
  (Hint: the second half of the target is identical to the source.)
]

#solution("71.1")[
  The target is two copies of the source concatenated.

  Instruction sequence:
  - `COPY 9, 0` — copy all 9 bytes from `source[0..9]`, producing `"aaabbbccc"`.
  - `COPY 9, 0` — copy the same 9 bytes again from source, producing the second `"aaabbbccc"`.

  This is 2 instructions instead of 18 literal bytes. Note that VCDIFF also supports
  "target window" COPY (copying from the already-produced target output), so an
  alternative is: `COPY 9, 0` then `COPY 9, 0` from the target — both are valid.
]

#exercise("71.2", 1)[
  Explain, in your own words, why fixed-size chunking fails when a single byte is
  inserted at the start of a large file. How does content-defined chunking solve
  this problem?
]

#solution("71.2")[
  With fixed-size chunking (say, 4 KB blocks), block $k$ contains bytes
  $4096(k-1)$ through $4096k - 1$. Insert one byte at position 0, and every
  block shifts: block $k$ now contains bytes $4096(k-1) + 1$ through $4096k$.
  Every block's content has changed — different bytes — so every block hashes to
  a new value. The deduplication system sees no matches at all.

  Content-defined chunking places boundaries where a rolling hash of the local bytes
  hits a specific pattern. After the insertion, the bytes at the start shift, but
  eventually — once past the insertion point — the same sequences of bytes appear
  in the same order. As soon as the rolling hash window moves past the inserted byte,
  it sees the same byte sequence as before and produces the same boundary decisions.
  All chunks beyond the insertion point are identical to the previous version.
]

#exercise("71.3", 2)[
  bsdiff encodes a "difference stream" of $("target"[i] - "source"[i])$ values (modulo
  256). Suppose you have source bytes `[100, 200, 50, 10]` and target bytes
  `[102, 203, 50, 11]`. Compute the difference stream. What property of this stream
  makes it compress well?
]

#solution("71.3")[
  Differences (mod 256):
  - $(102 - 100) mod 256 = 2$
  - $(203 - 200) mod 256 = 3$
  - $(50 - 50) mod 256 = 0$
  - $(11 - 10) mod 256 = 1$

  Difference stream: `[2, 3, 0, 1]`.

  This stream has very low entropy: most values are 0 or small positive integers.
  A general-purpose compressor like bzip2 (or zstd) will find very short codes for
  these values. In an executable, most positions change by at most a few due to
  address relocation — so the difference stream is dominated by zeros and small
  values, compressing to a small fraction of its raw size.
]

#exercise("71.4", 2)[
  Borg uses content-defined chunking with a target chunk size of 2 MB. You back up
  a 20 MB file on Monday. On Tuesday, you insert 100 bytes at the very beginning
  of the file. Roughly how many bytes of _new_ data will Borg write on Tuesday's
  backup, and why? (Assume the rolling hash window is 64 bytes and the first chunk
  boundary in the original file falls at position 1,900,000.)
]

#solution("71.4")[
  The 100-byte insertion shifts the first 1,900,000 bytes of the file. The first
  chunk boundary in the original file was at byte 1,900,000. After insertion it is
  at approximately byte 1,900,100 (shifted by 100 bytes). So the first chunk is now
  ~100 bytes longer than before and has different content — it is a new, unique chunk.

  After the first boundary, the remaining ~18 MB of the file is identical to
  Monday's backup (same byte sequences, same rolling-hash outcomes). Those chunks
  already exist in the Borg store.

  New data written: roughly one chunk ≈ 2 MB (the modified first chunk).
  Total stored for Tuesday: metadata (~1 KB) + ~2 MB of new chunk data.
  The insertion of 100 bytes costs only one chunk of storage.
]

#exercise("71.5", 2)[
  A Git repository contains 10,000 commits of a single 1 MB source file. With
  no delta compression, how much space would the packfile take to store all versions
  (ignoring zlib compression overhead)? With delta compression achieving an average
  delta size of 2 KB per commit (starting from a full 1 MB base), how much space
  does the packfile take? What is the compression ratio?
]

#solution("71.5")[
  *Without delta compression:* $10000 times 1 "MB" = 10000 "MB" = 9.77 "GB"$.

  *With delta compression:* one full base (1 MB) + 9,999 deltas (2 KB each).
  Total: $1 "MB" + 9999 times 2 "KB" = 1 "MB" + 19.5 "MB" = 20.5 "MB"$.

  *Compression ratio:* $9770 "MB" \/ 20.5 "MB" approx 477:1$.

  This is why Git can store the entire decades-long history of the Linux kernel
  (millions of commits) in a repository of a few gigabytes.
]

#exercise("71.6", 3)[
  Implement a minimal content-defined chunker in Python 3.14. Use a simple
  polynomial rolling hash (you may use a gear-hash table approach). Your function
  should accept a `bytes` object and a target chunk size, and return a list of
  `bytes` chunks. Test that inserting one byte at the start of a file only
  changes the first chunk and leaves subsequent chunks identical.
]

#solution("71.6")[
```python
import os

# Gear hash table: one 32-bit value per byte value (0-255).
# In production these are carefully chosen constants; here we generate them from
# a seeded random-like scheme for reproducibility.
_GEAR: list[int] = [
    (i * 0x08088405 + 1) & 0xFFFFFFFF for i in range(256)
]

def cdc_chunk(data: bytes, target: int = 65536) -> list[bytes]:
    """
    Split `data` into variable-size chunks using a Gear rolling hash.
    A boundary is declared when (hash & mask) == 0, where mask is chosen
    to give an expected chunk size of `target` bytes.
    Minimum chunk size: target // 4. Maximum: target * 4.
    """
    mask     = target - 1          # works cleanly when target is a power of 2
    min_size = max(64, target // 4)
    max_size = target * 4

    chunks: list[bytes] = []
    start  = 0
    h      = 0
    n      = len(data)

    i = start
    while i < n:
        chunk_end = start
        h = 0
        j = start
        # Skip minimum zone
        skip_to = min(start + min_size, n)
        # Compute initial hash over first bytes (no boundary allowed here)
        while j < skip_to:
            h = ((h << 1) | (h >> 31)) & 0xFFFFFFFF
            h ^= _GEAR[data[j]]
            j += 1
        # Now look for a boundary
        while j < n:
            h = ((h << 1) | (h >> 31)) & 0xFFFFFFFF
            h ^= _GEAR[data[j]]
            j += 1
            chunk_len = j - start
            if (h & mask) == 0 or chunk_len >= max_size:
                break
        chunks.append(data[start:j])
        start = j
        i = j

    return chunks

# --- self-test ---
import os as _os

base = b"Hello world! " * 5000        # ~65 KB of repeated content
modified = b"X" + base                # insert one byte at start

chunks_base = cdc_chunk(base, target=4096)
chunks_mod  = cdc_chunk(modified, target=4096)

# First chunk should differ; most later chunks should be the same
same_later = sum(
    1 for a, b in zip(chunks_base[1:], chunks_mod[2:]) if a == b
)
print(f"Base chunks: {len(chunks_base)}, Modified chunks: {len(chunks_mod)}")
print(f"Chunks after first that are identical: {same_later} "
      f"out of {len(chunks_base) - 1}")
# Expected: most are identical — the insertion only changes the first chunk.
```

  The key insight in the test: inserting one byte changes only the first chunk;
  most subsequent chunks are identical between `base` and `modified`, confirming
  that CDC is shift-resistant.
]

== Further Reading

- Korn, D., MacDonald, J., Mogul, J. & Vo, K. (2002). #link("https://www.rfc-editor.org/rfc/rfc3284")[*RFC 3284: The VCDIFF Generic Differencing and Compression Data Format.*] IETF. The canonical specification for the VCDIFF delta format used by xdelta3.

- Percival, C. (2003). #link("https://www.daemonology.net/bsdiff/")[*bsdiff and bspatch: Naïve Differences of Executable Code.*] The algorithm and tool behind macOS and Chrome binary patching.

- Muthitacharoen, A., Chen, B. & Mazières, D. (2001). *A Low-bandwidth Network File System.* ACM SOSP 2001. The paper that introduced content-defined chunking with Rabin fingerprints into the systems community.

- Xia, W. et al. (2016). #link("https://www.usenix.org/conference/atc16/technical-sessions/presentation/xia")[*FastCDC: A Fast and Efficient Content-Defined Chunking Approach for Data Deduplication.*] USENIX ATC 2016. The algorithm now used in Restic.

- Tridgell, A. (1999). #link("https://www.samba.org/~tridge/phd_thesis.pdf")[*Efficient Algorithms for Sorting and Synchronization.*] PhD thesis, Australian National University. The rsync algorithm.

- Chacon, S. & Straub, B. (2014). #link("https://git-scm.com/book/en/v2/Git-Internals-Packfiles")[*Pro Git — Packfiles.*] git-scm.com. Accessible explanation of Git's internal storage and delta compression.

#bridge[
  Every technique in this chapter removed redundancy by exploiting something already
  known: an older file version, an existing chunk, a base image layer. The next chapter
  flips the idea completely — instead of removing redundancy to save space, we
  _add_ redundancy on purpose, to survive errors. Chapter 72 asks: once you have
  compressed a file as tightly as possible, how do you protect it against bit flips,
  disk failures, and network corruption? The answer is error-correcting codes —
  Reed–Solomon, LDPC, and polar codes — and it is the other half of Shannon's
  original 1948 duality between source coding and channel coding.
]
