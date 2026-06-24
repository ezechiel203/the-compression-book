#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Engineering Fast Codecs

#epigraph[
  "Making something fast is not the same as making it clever. It is the art
  of never asking the CPU to do something it already knows the answer to."
][Fabian "ryg" Giesen, rANS notes blog post, February 2014]

Here is a question nobody warns you about when you first learn compression: what
good is a codec that achieves a 5:1 ratio but can only decompress at 50 MB/s?
If a modern SSD can feed your CPU at 7,000 MB/s, the compressor is the
bottleneck. It is slower than storage. It is slower than the network. It is,
in the ugliest possible sense, helping.

The algorithmic chapters you have read (Huffman: Chapter 24; arithmetic
coding: Chapter 26; ANS: Chapter 27; LZ77: Chapter 28; DEFLATE: Chapter 30;
BWT: Chapter 35) told you *what* to compute. This chapter tells you *how*
to make a computer do it as fast as physics allows. We will tour four
interlocking techniques that every high-performance codec relies on: interleaved
ANS decoding with SIMD, branchless match-copy loops, cache-aware hash-chain
match finders, and parallel framing. We will then look beyond the CPU at two
frontiers: GPU compression through NVIDIA's nvCOMP library, and hardware
offload engines from Intel (IAA and QAT). By the end you will understand not
only why zstd decompresses at multi-gigabyte-per-second speeds, but also how
that performance is engineered, instruction by instruction.

#recap[
  In *Chapter 27* we met rANS (the Range variant of Asymmetric Numeral
  Systems), which encodes symbols into a single integer state and achieves
  arithmetic-coding accuracy at near-table-lookup speed. In *Chapter 28* we
  built the LZ77 match finder, the heart of every modern dictionary codec.
  In *Chapter 30* we combined them into a DEFLATE implementation with a
  sliding-window hash. In *Chapter 27* we also noted, without proof, that
  decoding multiple ANS streams in parallel is the key to exploiting today's
  wide CPUs. This chapter makes good on that promise, and extends it to
  hardware.
]

#objectives((
  [Explain why a single-state rANS decoder leaves most of a modern CPU idle,
   and how *interleaving* fixes that.],
  [Describe how SIMD instructions let one CPU instruction decode 4 or 8 ANS
   symbols simultaneously.],
  [Explain what "branchless" means in the context of LZ77 back-reference
   copy loops, and why it matters.],
  [Describe the cache-miss problem in hash-chain match finders and the hash
   table tricks that mitigate it.],
  [Explain how compression can be parallelized across CPU cores using *frames*,
   and what the size/ratio trade-off is.],
  [Describe what NVIDIA nvCOMP does and where GPU decompression is genuinely
   faster than CPU decompression.],
  [Describe Intel IAA and QAT and the workloads for which hardware offload
   is the right choice.],
))

== The modern CPU's dirty secret

Before we can understand fast codecs, we need to understand the machine they
run on. Modern CPUs have a gap between their *theoretical* peak performance
and what most code actually achieves that is so large it might as well be a
chasm.

A modern CPU core does not just execute one instruction and then fetch the
next. It looks ahead into the instruction stream, figures out which instructions
do not depend on each other, and runs several at the same time. This is called
*superscalar execution*. A typical core can retire four to six instructions per
clock cycle, and since a chip running at 4 GHz ticks 4 billion times a second,
the theoretical ceiling is somewhere around 24 billion instructions per second
*per core*.

The catch: superscalar execution only helps when the CPU has *independent work
to do*. If instruction B needs the result of instruction A, the CPU has no
choice but to stall and wait. This is called a *data dependency*, and it is the
dominant performance killer in entropy decoders.

#gomaths("Latency versus throughput")[
  Processor architects talk about two measures of an instruction's speed.
  *Latency* is how many clock cycles you must wait before the result is
  ready (the delay from "start" to "usable output"). *Throughput* is how many
  of the same instruction can *start* per cycle if their inputs are already
  available.

  Example: a 64-bit multiply on a modern CPU might have a latency of 3 cycles
  (you must wait 3 ticks for the answer) but a throughput of one per cycle
  (you can start a new multiply every tick). If you have a chain of multiplies
  where each one uses the result of the last, you are bottlenecked on latency:
  3 cycles each, no overlap. If your multiplies are independent, you can
  *pipeline* them: start a new one every cycle, getting one result per cycle
  instead of one per three.

  The art of fast codec engineering is maximizing *independent* work so the
  CPU can fill its execution units while waiting for earlier results.
]

=== The single-state rANS bottleneck

Recall from Chapter 27 how rANS decoding works. At any moment there is one
number called the *state*, usually written $x$. To decode a symbol you:

1. Read the low bits of $x$ to look up a symbol in the decode table.
2. Update $x$: divide out the symbol's probability (one multiplication and one
   addition).
3. If $x$ is now below a threshold, read more bits from the compressed stream
   and multiply them in (*renormalization*).

Step 2 uses the result of step 1. Step 3 uses the result of step 2. The entire
decode loop is one long chain of data dependencies. Every iteration of the loop
must *wait* for the previous one to finish before it can start. On a 4 GHz
CPU where the critical multiply has a 3-cycle latency, the maximum decoding
speed is roughly one symbol per 3 cycles, throwing away the five-sixths of
execution capacity that is sitting idle.

How fast is that in practice? If a symbol decodes in roughly 8--12 clock
cycles end-to-end (table lookup + multiply + branch), a single-state rANS
decoder on a 4 GHz core tops out around 300--400 MB/s. That is perfectly
fine for 2010. It is embarrassing for 2024, when the same core can run
floating-point math at 50+ GB/s peak.

== Interleaved rANS: more states, more speed

The insight that breaks the bottleneck is simple once you see it. Instead of
maintaining *one* state and decoding symbols one at a time, maintain *two*
(or four, or eight) *independent states*, each encoding a separate sub-stream,
and interleave their decode steps.

With two states, $x_0$ and $x_1$, the decode loop looks like this in pseudocode:

```
  symbol_0 = lookup(x0)     # depends on x0
  symbol_1 = lookup(x1)     # depends on x1 -- INDEPENDENT of the above!
  x0 = update(x0, symbol_0) # depends on x0 and symbol_0
  x1 = update(x1, symbol_1) # depends on x1 and symbol_1 -- INDEPENDENT!
```

The update of $x_0$ and the update of $x_1$ have *no dependency on each other*.
The CPU can start the second before the first is finished. With two streams,
we nearly double throughput for free, with no algorithmic change at all, just
reordering the work.

With *four* interleaved states, throughput roughly doubles again. With *eight*,
we saturate the available multiply units on a typical superscalar core. In
practice, the sweet spot for software rANS is four to sixteen states, depending
on the CPU microarchitecture. Fabian "ryg" Giesen demonstrated this empirically
in his 2014 ryg\_rans library (the canonical open-source reference), showing
that four-way interleaved rANS decodes roughly 2--3x faster than single-state
rANS on Intel Haswell, dropping from around 11 cycles per symbol to roughly
4--5 cycles per symbol.

#keyidea[
  Interleaving $N$ independent ANS states (each encoding a sub-sequence of
  symbols) has *zero effect on the compression ratio*: you still reach the
  entropy floor. It is a pure speed optimization that exploits instruction-level
  parallelism. The decompressor must maintain all $N$ states simultaneously and
  interleave their renormalization reads from the compressed stream.
]

#history[
  Fabian "ryg" Giesen first published the interleaved ANS idea on arxiv
  (arXiv:1402.3392, "Interleaved entropy coders") in February 2014, accompanied
  by a practical blog post ("rANS notes") and the public-domain ryg\_rans
  repository on GitHub. The LZFSE codec (Apple, 2016) and JPEG XL (Google/ISO,
  2022) both adopted the technique. Zstandard (Facebook, 2016) independently
  uses a related approach via its Finite State Entropy (FSE) tANS engine.
  The 2023 "Recoil" paper (Lin et al., ICPP 2023) extended interleaved rANS
  decoding to GPUs with adaptive scalability across varying numbers of CUDA
  cores, pushing decompression throughputs above 100 GB/s on server-class GPUs.
]

=== SIMD: eight updates for the price of one instruction

Modern CPUs also have a special set of *SIMD* instructions, where SIMD stands
for *Single Instruction, Multiple Data*. One SIMD instruction operates on an
entire *vector* of values at once.

#gomaths("SIMD vectors")[
  Imagine a normal (scalar) instruction that multiplies two 32-bit integers
  and returns one 32-bit integer. A 256-bit SIMD multiply instruction instead
  takes two vectors, each containing *eight* 32-bit integers packed side by
  side, multiplies each pair in parallel, and returns one vector of eight
  results in *one* clock cycle.

  On Intel CPUs the relevant instruction sets are SSE2 (128-bit vectors,
  four 32-bit integers), SSE4.1, AVX2 (256-bit vectors, eight 32-bit
  integers), and AVX-512 (512-bit vectors, sixteen 32-bit integers). ARM
  CPUs have the equivalent NEON and SVE instruction sets.

  SIMD only helps when the *same* operation is applied to *many* independent
  pieces of data simultaneously, which is exactly the shape of interleaved
  ANS decoding.
]

With eight interleaved rANS states and AVX2, each decode "round" does eight
table lookups in parallel with one GATHER instruction, eight multiply-adds in
parallel with SIMD arithmetic, and eight threshold comparisons in parallel with
a SIMD compare. It then reads renormalization bytes only for the states that need
it, using a compact bit-mask to guide which lanes get refreshed.

In practical terms: an eight-way AVX2 interleaved rANS decoder running on a
modern Intel or AMD CPU achieves decompression throughputs in the range of
1--3 GB/s per core in real codecs. This is the engine inside zstd's Huffman
and FSE back-ends.

The tradeoff: SIMD code is *architecture-specific*. Code written for AVX2
will not run on an ARM phone, and code using AVX-512 will not run on a CPU that
only supports AVX2. Production codecs therefore ship multiple code paths and
select the best one at runtime, a technique called *CPU dispatch*.

#algo(
  name: "Interleaved rANS (N-way)",
  year: "2014",
  authors: "Fabian Giesen (\"ryg\"); formalized from Jarosław Duda's ANS, 2009",
  aim: "Exploit superscalar and SIMD execution to decode N independent rANS sub-streams in parallel, reaching the entropy floor at near-memory-bandwidth speeds.",
  complexity: "O(n) time, O(N·table) space where N is the interleave factor (typically 4–16)",
  strengths: "Near-zero compression-ratio penalty; scales linearly with available execution units; natural fit for SIMD; used in LZFSE, JPEG XL, zstd FSE.",
  weaknesses: "Encoder must also interleave streams (more complex); SIMD code is architecture-specific; requires CPU dispatch for portable binaries.",
  superseded: "",
)[
  The ANS state update is $x' = (x / p_s) dot L + (x mod p_s) + C_s$ where
  $p_s$ is the symbol's probability, $L$ is the range size, and $C_s$ is the
  symbol's cumulative frequency. The division is replaced by a multiply (by the
  reciprocal of $p_s$, precomputed) in fast implementations. With $N$ states,
  the encoder processes symbols in reverse order (ANS is LIFO), distributing
  them round-robin among the $N$ states; the decoder processes them in forward
  order, also round-robin.
]

#gopython("List slicing for interleaved buffers")[
  When we have $N$ interleaved streams, the symbols are distributed like this:
  symbol 0 goes to state 0, symbol 1 to state 1, ..., symbol $N-1$ to state
  $N-1$, symbol $N$ back to state 0, and so on.

  In Python, given a list of all symbols, we can extract the sub-sequence for
  state $k$ using *slice notation* `seq[k::N]` (meaning "start at index
  `k`, take every `N`-th element").

  ```python
  symbols = [7, 3, 5, 1, 4, 0, 6, 2]  # eight symbols total
  N = 4                                  # four interleaved states
  for k in range(N):
      sub = symbols[k::N]                # symbols for state k
      print(f"state {k}: {sub}")
  # state 0: [7, 4]
  # state 1: [3, 0]
  # state 2: [5, 6]
  # state 3: [1, 2]
  ```

  Each sub-list can be encoded and decoded *independently*. During decoding
  we interleave the results back together: take one symbol from state 0, one
  from state 1, and so on, which reconstructs the original order.
]

=== A tiny worked example: two-way interleaved rANS

Let us trace through the idea with the smallest useful case: two interleaved
states, a 2-symbol alphabet {A, B} with probabilities $p_A = 3/4$,
$p_B = 1/4$, and the message "A B A A" (4 symbols).

In a real rANS coder we would first encode the symbols into two states, then
write out both states to the compressed stream. On decoding we read both states
back and interleave their decode loops. Using the slice rule `seq[k::2]` from
the box above, state 0 carries the even-indexed symbols of "A B A A" (that is
positions 0 and 2, namely "A A") and state 1 carries the odd-indexed symbols,
positions 1 and 3, namely "B A".

Now watch the *dependency chain*. Writing $x_0 arrow.r x_0'$ for "the update of
state 0", a single-state decoder must run everything in one strict line, where
each arrow means "must finish before the next can start":

$ x_0 arrow.r x_0' arrow.r x_1 arrow.r x_1' arrow.r x_0'' arrow.r x_1'' $

Four updates, all in series: the CPU's other execution units sit idle. The
two-state decoder splits that single chain into *two shorter, parallel* chains:

$ underbrace(x_0 arrow.r x_0' arrow.r x_0'', "state 0: A, A") quad quad underbrace(x_1 arrow.r x_1' arrow.r x_1'', "state 1: B, A") $

Nothing in the left chain depends on anything in the right chain, so the CPU can
advance both at once, finishing in the time of *one* chain instead of two. The
update of state $x_0$ and the update of state $x_1$ in the same round have *no
data dependency on each other*, so both proceed simultaneously on a superscalar
core. To reconstruct the message the decoder simply alternates outputs: first
symbol from state 0 (A), first from state 1 (B), second from state 0 (A), second
from state 1 (A), recovering "A B A A".

Even without understanding every detail of rANS arithmetic (covered fully in
Chapter 27), the *structural* point is visible: independent states give
independent work, and independent work lets the CPU use its execution units in
parallel.

== Branchless decoding: eliminating the if-statement tax

The entropy coder is only half the battle. In LZ77-family codecs (Chapter 28),
the decompressor must also *copy* back-references: sequences of bytes from
earlier in the already-decompressed data. These copies dominate decompression
time in data-heavy codecs like LZ4 and LZ77.

A naive back-reference copy in Python looks like this:

```python
while length > 0:
    output.append(output[pos])
    pos += 1
    length -= 1
```

The problem: this is a tight loop with a *branch* (the `while` condition) that
the CPU checks on every iteration. Modern CPUs try to *predict* which way a
branch will go (the branch predictor), but if the prediction is wrong the CPU
must discard in-flight work and restart, incurring a *misprediction penalty* of 10--20
cycles. With back-references ranging from 4 to 255 bytes, the branch predictor
has a difficult time.

The solution production codecs use is called *branchless decoding*: restructure
the copy so the CPU never needs to branch at all.

=== The trick: copy more than you need, then fix up

The key insight is that for *most* back-references, the copy length fits within
one or two fixed-size SIMD loads. Instead of looping byte by byte, a branchless
decoder does:

1. *Always* copy 16 (or 32) bytes from the back-reference source position.
2. Advance the output pointer by exactly `length` bytes.

Step 1 may copy too many bytes, but step 2 limits what the next output sees.
The bytes past `length` are overwritten by the next token. The result is a
fixed number of SIMD moves per token: no branch, no loop, predictable
instruction count. LZ4's decompressor is famously built almost entirely on
this trick, and it achieves 3--5 GB/s decompression on modern CPUs, fast
enough that the decompressor can keep up with a PCIe SSD.

#pitfall[
  Branchless copy *assumes* the destination buffer has at least 16 (or 32)
  bytes of safe headroom beyond the last byte written. If you call a
  branchless decompressor on a buffer that is exactly the right size, it may
  write past the end and corrupt adjacent memory. Production decompressors
  always allocate a small output overshoot (commonly 32 bytes) for this reason.
  If you wrap a fast decompressor in your own code, do the same.
]

The same branchless technique applies to the *literal copy* phase, where
uncompressed bytes from the token stream go directly into the output. With 16-byte SIMD
stores, a codec can blast out 16 literal bytes in a single instruction, far
faster than a byte-at-a-time loop.

#gopython("bytearray and memoryview for fast buffer manipulation")[
  Python is not the right language for branchless decoding (the interpreter
  adds overhead that drowns out instruction-level tricks), but understanding
  the *idea* is still worthwhile. In Python, the closest
  equivalent to a SIMD copy is copying a *slice* of a `bytearray`, which
  uses C-level `memcpy` internally:

  ```python
  output = bytearray(1024)  # preallocate
  pos = 0
  # Copy 8 bytes from position `src` to position `pos`:
  src = 10
  length = 8
  output[pos:pos+length] = output[src:src+length]
  pos += length
  ```

  The `output[pos:pos+length] = ...` line calls into C code that uses
  `memmove` under the hood, which on most platforms becomes a SIMD copy.
  This is why slices are faster than explicit `for` loops in Python.
  A `memoryview` object gives zero-copy access to the same buffer for
  even tighter control:

  ```python
  mv = memoryview(output)
  mv[pos:pos+length] = mv[src:src+length]
  ```
]

=== When branchlessness meets overlap

There is one nasty corner case. If the back-reference offset is *smaller* than
the copy length (for example, offset 2 with length 10), the source and
destination regions overlap. This pattern is actually common: it is how RLE-like
runs are encoded in LZ codecs ("repeat the last 2 bytes, 10 times").

A SIMD copy that blindly reads 16 bytes from position $p$ and writes them to
position $p+2$ will read bytes that have not been written yet (or will read
stale copies). The fix is to check for overlap before choosing the fast path:
if `offset >= 16` (or whatever the SIMD width is), the fast branchless copy is
safe; otherwise, fall back to a slower byte-at-a-time copy. Because the
overlap case is rare in practice, the branch predictor learns to predict
"no overlap" with high accuracy, and the misprediction cost is paid infrequently.

== Cache-aware match finders

The other major cost center in *compression* (as opposed to decompression) is
the *match finder*: the code that searches the history buffer for the longest
previous occurrence of the current input string (Chapter 28).

#note[
  *A two-minute tour of the memory hierarchy.* Back in *Chapter 13* we met the
  *cache line* (the 64-byte chunk that is the smallest unit of data the CPU
  ever moves between main memory (RAM) and the chip). To understand why the next
  three sections obsess over "fitting in cache", we need a little more of the
  picture.

  A CPU does not read RAM directly when it can help it. RAM is *slow*: a single
  random read costs roughly 50--200 nanoseconds, which at 4 GHz is 200--800
  wasted clock cycles. So the chip keeps small, fast copies of recently-used
  data in on-chip *caches*, arranged in levels by size and speed:

  - *L1 cache*: tiny (32--64 KB), almost as fast as a register (~4 cycles).
  - *L2 cache*: small (256 KB--2 MB), fast (~12--15 cycles).
  - *L3 cache* (the "last-level cache"): larger (16--64 MB on a server), slower
    (~40 cycles) but still far faster than RAM.

  When the CPU needs a byte, it checks L1, then L2, then L3, then RAM, stopping
  at the first level that has it. Finding it in a cache is a *cache hit*; having
  to go all the way to RAM is a *cache miss* (the single most
  expensive everyday event in performance engineering). Because data moves in
  64-byte lines, reading one byte pulls in its 63 neighbours for free, so
  *sequential* access is cheap and *random* access (jumping all over a big
  array) is a parade of cache misses. Keeping a data structure small enough to
  live in L2 or L3 is what turns a miss-bound crawl into a cache-hot sprint.
]

The standard LZ77 hash chain works like this:

- Maintain a hash table `head[hash]` that maps each 3- or 4-byte string to the
  most recent position where that string appeared.
- Maintain a "chain" array `prev[pos]` such that `prev[pos]` is the previous
  position with the same hash.
- To find matches: hash the current 4 bytes, look up `head`, then walk the
  chain of `prev` links until you find the longest match or run out of chain.

The problem is *cache thrashing*. The sliding window is 32 KB in DEFLATE and up
to 128 MB in high-compression settings. The `prev` array for a 128 MB window
is 512 MB, far larger than the CPU's last-level cache (typically 16--64 MB on
a server). Walking a long chain requires loading random positions from this
512 MB array, each of which is a *cache miss* costing 50--200 nanoseconds. A
match finder walking chains of length 64 at 50 ns each spends 3.2 microseconds
on every output token, and at a token every 10--20 bytes, that limits
compression to 3--6 MB/s, barely faster than a hard drive.

=== The hash table tricks that matter

Three techniques dominate modern match-finder optimization:

*1. Small hash tables that fit in L2 or L3 cache.*
If you restrict the window to 32 KB (as DEFLATE does), the head array needs
only 128 KB of memory, small enough to stay in L2 cache. gzip's choice of a
32 KB window was not arbitrary; it was tuned to the cache sizes of 1990s
hardware. zstd's "fast" compression level uses a similarly-small hash to stay
in cache, trading ratio for speed.

*2. Hash table entries that store multiple candidates.*
Instead of one position per hash slot (and then chaining), store *four* or
*eight* positions per slot in an array ("multi-probe hash table" or "cuckoo
hash"). Looking up a slot loads all four candidates in one or two cache lines,
a single memory access instead of four independent chain hops each of which
might be a separate cache miss.

*3. Second-level hashing with a longer key.*
A two-level hash: first hash 4 bytes to find a bucket, then hash 8 bytes to
find a candidate within the bucket. Long matches (8+ bytes) are found quickly
by the second hash; short matches use the first hash. This avoids following
chains at all for the common case. zstd calls this the "binary tree" or
"row hash" strategy at higher compression levels.

#fig(
  [Three match-finder strategies and their cache footprint. The simple hash
   chain (left) walks many small nodes scattered across memory. The multi-probe
   bucket (center) loads four candidates in one cache line. The two-level hash
   (right) separates short and long matches.],
  cetz.canvas({
    import cetz.draw: *
    // Simple hash chain box
    rect((0,3),(3,4), fill: rgb("#e8f4f8"), stroke: rgb("#0b5394"))
    content((1.5,3.5), box(width: 2.6cm, inset: 2pt, align(center, text(size: 8pt)[Hash chain])))
    // arrows simulating chain hops
    for i in range(4) {
      circle((0.3 + i*0.7, 2.5 - i*0.4), radius: 0.18, fill: rgb("#0b5394"))
      if i < 3 {
        line((0.3 + i*0.7 + 0.18, 2.5 - i*0.4),
             (0.3 + (i+1)*0.7 - 0.18, 2.5 - (i+1)*0.4),
             mark: (end: "straight"))
      }
    }
    content((1.5, 1.6), text(size: 8pt)[4 cache misses])
    // Multi-probe bucket box
    rect((4,3),(7,4), fill: rgb("#e8f8ec"), stroke: rgb("#0b6e4f"))
    content((5.5,3.5), box(width: 2.6cm, inset: 2pt, align(center, text(size: 8pt)[Multi-probe])))
    rect((4.2,2.0),(6.8,2.8), fill: rgb("#cceedc"), stroke: rgb("#0b6e4f"))
    content((5.5,2.4), box(width: 2.2cm, inset: 2pt, align(center, text(size: 8pt)[4 slots / 1 line])))
    content((5.5, 1.6), text(size: 8pt)[1 cache miss])
    // Two-level hash box
    rect((8,3),(11,4), fill: rgb("#fef5e0"), stroke: rgb("#783f04"))
    content((9.5,3.5), box(width: 2.6cm, inset: 2pt, align(center, text(size: 8pt)[Two-level hash])))
    rect((8.2,2.4),(9.8,2.8), fill: rgb("#fde9b0"), stroke: rgb("#783f04"))
    content((9.0, 2.6), box(width: 1.2cm, inset: 2pt, align(center, text(size: 8pt)[4-byte])))
    rect((9.9,2.4),(10.8,2.8), fill: rgb("#fde9b0"), stroke: rgb("#783f04"))
    content((10.35, 2.6), box(width: 0.6cm, inset: 1pt, align(center, text(size: 7pt)[8-byte])))
    content((9.5, 1.6), text(size: 8pt)[1--2 misses])
  })
)

#checkpoint[
  A match finder uses a hash table covering a 128 KB window. Each entry is
  4 bytes. The table has 32,768 slots. How large is the hash table in
  kilobytes, and does it fit in a typical L2 cache (256 KB)?
][
  32,768 slots × 4 bytes = 131,072 bytes = 128 KB. This fits comfortably
  in a 256 KB L2 cache, which is why codecs tuned for speed often limit
  their window to 32--128 KB: the hash table stays hot in cache and cache
  misses almost disappear.
]

== Multithreading: frames and parallel blocks

The techniques above squeeze more performance from a *single core*. To use all
the cores on a modern CPU (typically 8 to 128 on a server) you need a
different strategy: *parallel framing*.

The idea is to split the input data into *independent blocks* (called frames in
zstd terminology) and compress each block on a separate CPU thread simultaneously.

#definition("Compression frame")[
  A *compression frame* is a self-contained compressed unit: it has its own
  header, its own compressed data, and can be decompressed without any context
  from neighboring frames. A file compressed as multiple frames can be
  decompressed in parallel.
]

zstd's `--threads N` option does exactly this: it divides the input into
blocks of a configurable size (default around 1 MB), compresses each in a
separate thread, and concatenates the frames in order. The decompressor can
then also split across threads, making the whole pipeline parallel both ways.

*The catch:* frames have a cost. Because each frame is independent, the match
finder at the start of frame $k$ has no knowledge of the data at the end of
frame $k-1$. Matches that cross frame boundaries cannot be represented.
Compression ratio suffers (slightly for large frames where the boundary penalty is
small relative to 1 MB of data, and noticeably for very small frames). There is an
inherent trade-off:

#table(
  columns: (auto, 1fr, 1fr),
  align: (left, center, center),
  table.header([*Frame size*], [*Speed (8 cores)*], [*Ratio vs single-threaded*]),
  [4 MB], [~7x faster], [-0.3%],
  [1 MB], [~7x faster], [-1--2%],
  [64 KB], [~7x faster], [-5--10%],
  [4 KB],  [~5x faster (overhead)], [-15--25%],
)

The sweet spot for most use cases is 1--4 MB frames: nearly linear speedup
with negligible ratio penalty.

=== pigz, pzstd, and the parallel gzip renaissance

The same idea powers `pigz` (Parallel gzip, Mark Adler, 2007), which splits
input into 128 KB blocks, compresses them independently with multiple threads,
and outputs a standard gzip stream. Because gzip was never designed for
parallelism, `pigz` has to concatenate single-byte sync blocks between
compressed chunks (a hack that works but wastes a few bytes per block). zstd
was *designed* with frames from the start, making parallel compression a
first-class feature rather than a retrofit.

#keyidea[
  The reason zstd compression is 3--5x faster than gzip at equivalent ratios
  is not purely algorithmic cleverness. It combines: (1) a better
  hash table match finder, (2) a branchless FSE/ANS entropy back-end instead
  of DEFLATE's Huffman, and (3) native multi-threading support with frames,
  all designed together from the start rather than bolted on after the fact.
]

#aside[
  LZ4 added official multi-threading support in July 2024, catching up with
  zstd in this regard. The LZ4MT extension had existed in third-party wrappers
  for years, but the mainline library had stayed single-threaded since 2011.
  The addition lets LZ4 saturate all available CPU cores for the first time,
  bringing its already-extraordinary decompression speed (often 4--6 GB/s
  single-threaded) into truly parallel territory.
]

== GPU compression: NVIDIA nvCOMP

The CPU techniques above push decompression into the 5--10 GB/s range on a
high-core-count server, but a modern NVIDIA H100 GPU has roughly 3.35 TB/s
of HBM3 memory bandwidth. If you can feed data to the GPU fast enough, GPU
decompression can crush CPU speeds.

This is the premise of NVIDIA's *nvCOMP* library, a CUDA-accelerated
compression and decompression toolkit introduced around 2019 and actively
developed through 2025.

#algo(
  name: "nvCOMP",
  year: "2019–2025",
  authors: "NVIDIA Corporation",
  aim: "Provide GPU-accelerated lossless compression and decompression for analytics, deep learning, and HPC workloads, leveraging CUDA parallelism and, on Blackwell GPUs, dedicated hardware decompression engines.",
  complexity: "Throughput-limited by GPU memory bandwidth; O(n) data movement dominant",
  strengths: "Extremely high throughput (up to 180 GB/s on Blackwell hardware for Snappy); integrates directly with CUDA pipelines, avoiding CPU round-trips; supports Snappy, LZ4, zstd, DEFLATE, ANS, and more.",
  weaknesses: "Requires data to already be in GPU memory; latency (kernel launch overhead) makes small inputs slower than CPU; not useful unless the workload is GPU-resident; licensing varies.",
  superseded: "",
)[
  nvCOMP exposes compression and decompression as CUDA kernels. For analytics
  workloads (Apache Parquet reading, database column decompression), it allows
  GPU kernels to decompress data *in place* as part of a query pipeline without
  ever sending data back to CPU memory. The NVIDIA Blackwell architecture
  (H200/B200, 2024--2025) added a dedicated *Decompression Engine (DE)*
  on-chip: a fixed-function hardware unit that decompresses Snappy at 180 GB/s
  and performs fused copy-decompress operations, with even lower latency than
  pure CUDA kernel approaches.
]

=== When is GPU decompression actually faster?

The rule of thumb: GPU decompression wins when the *data is already on the
GPU* and you need to decompress *a lot of it in parallel*. Three scenarios:

*Database analytics:* Parquet or ORC files compressed with Snappy or LZ4 can
be decompressed by nvCOMP kernels during a GPU SQL query (as in RAPIDS cuDF),
eliminating the round-trip of "CPU decompresses -> memcpy to GPU -> GPU queries."

*Deep learning checkpoints:* Storing model weights compressed and decompressing
them directly on the GPU saves PCIe bandwidth and time during model loading.

*HPC:* Simulation output compressed on-the-fly on the GPU before writing to
storage avoids the throughput bottleneck of writing raw data.

The scenario where GPU decompression does not win: when the data arrives from
the network or disk to CPU memory and the decompressed result is also needed by
the CPU. The cost of copying from CPU memory to GPU memory (PCIe at ~64 GB/s)
exceeds the CPU decompression cost for most codecs at most data sizes.

#misconception["GPU is always faster than CPU for compression."][
  GPU compression is faster *only if the data is already GPU-resident* and
  the batch is large enough to overcome kernel launch overhead. For small or
  CPU-bound workloads, a well-tuned CPU codec (zstd, LZ4) running in
  parallel threads is faster and simpler. The Blackwell hardware DE reaching
  180 GB/s for Snappy is genuinely extraordinary, but Snappy is a low-ratio
  codec designed for speed, and 180 GB/s only beats a CPU if you have 180 GB/s
  of GPU memory bandwidth to fill in the first place.
]

== Hardware offload: Intel IAA and QAT

At the other end of the spectrum from GPU parallelism is the idea of offloading
compression work to dedicated *hardware accelerators* integrated directly into
the CPU or chipset.

Intel introduced two relevant accelerators in its 4th-generation Xeon Scalable
(Sapphire Rapids) platform in 2023, and both are available in 5th-generation
(Emerald Rapids) and beyond:

=== Intel IAA (In-Memory Analytics Accelerator)

IAA is a fixed-function engine built into the CPU die that offloads specific
data operations: filtering, compression, decompression, and CRC calculation.
Each Sapphire Rapids socket has one IAA instance with multiple work queues that
applications can submit jobs to without CPU involvement.

IAA accelerates DEFLATE (gzip) compression and decompression using a
fixed-function pipeline (not a general CPU running DEFLATE code, but an
actual hardware circuit wired to perform DEFLATE). This lets IAA decompress
at multi-GB/s rates while burning near-zero CPU cycles, leaving those cycles
free for the application.

The sweet spot for IAA is *database I/O*: a database server that reads
compressed Parquet files from NVMe storage can use IAA to decompress the data
with no CPU overhead, then use CPU cores exclusively for query processing.
Linux kernel support for IAA arrived in kernel 6.8 (early 2024), making it
accessible from userspace via the `idxd` driver.

=== Intel QAT (QuickAssist Technology)

QAT is a PCIe-attached coprocessor (also integrated in some Xeon variants) that
offloads symmetric encryption, public-key cryptography, and compression. The
compression back-end supports DEFLATE and can be used as a drop-in backend for
zlib and zstd via the *QAT-ZSTD Plugin* (open source, Intel).

A 2025 IEEE paper found that using QAT for `zswap` (Linux kernel memory
compression for swap-to-RAM) reduced tail latency by 2.2--7.9x compared to
software DEFLATE, while reducing CPU usage by a corresponding amount. For
cloud workloads where CPU time is money and memory pressure is constant, that
is a compelling proposition.

#table(
  columns: (auto, 1fr, 1fr, 1fr),
  align: (left, center, center, center),
  table.header(
    [*Accelerator*],
    [*Interface*],
    [*Best for*],
    [*CPU cycles used*],
  ),
  [Intel IAA], [On-die, ENQCMD], [Database I/O, in-memory analytics], [Near zero],
  [Intel QAT], [PCIe coprocessor or on-die], [Cloud DEFLATE, memory compression], [Near zero],
  [NVIDIA Blackwell DE], [On-die GPU hardware], [GPU-resident analytics, DL checkpoints], [Zero (GPU)],
  [CPU (zstd, N threads)], [Software, any CPU], [General-purpose, latency-sensitive], [Full N cores],
)

#keyidea[
  Hardware offload wins when three conditions hold simultaneously: (1) the
  *workload* is dominated by compression/decompression (many GB/s of data
  to process), (2) the *CPU cycles* saved have genuine value (they can be
  spent on something else), and (3) the *data format* matches what the
  hardware speaks (almost always DEFLATE or LZ4 for fixed-function engines).
  For a personal laptop running occasional backups, none of these conditions
  hold and hardware offload is irrelevant. For a 128-core database server
  reading 50 GB/s of Parquet files, offloading decompression frees the CPUs
  to do something that actually requires a CPU.
]

== Putting it together: a mental model of codec design

With all four techniques in view (interleaved ANS, branchless copying,
cache-aware match finding, and parallel framing) we can describe the
*philosophy* that distinguishes a fast production codec from a slow reference
implementation.

A fast codec is not just a correct algorithm with some constant-factor tweaks.
It is an algorithm designed from the start around the properties of the hardware
it runs on:

- *Entropy stage*: avoid data dependencies between successive symbol
  decodings by using multiple interleaved states. Use SIMD to process
  multiple states in one instruction. Pre-compute reciprocals to replace
  division with multiplication.

- *Match copy stage*: design the token format so that the output can be
  written in fixed-width chunks with no per-byte branches. Accept that a
  few bytes of headroom overshoot are cheaper than the latency of a loop
  condition.

- *Match finding stage*: choose a hash table small enough to stay in L2
  or L3 cache. Use multi-probe buckets to find multiple candidates with one
  cache miss. Reserve long-chain walking for the highest compression levels
  only.

- *Parallel stage*: design the file format around independent frames so
  that both compression and decompression can scatter-gather across all
  available cores.

#scoreboard(
  caption: "Performance landscape: fast codecs on modern hardware (mid-2026)",
  [*Codec / engine*], [*Comp. speed*], [*Decomp. speed*], [*Notes*],
  [gzip -1 (1 core)],        [~80 MB/s],   [~500 MB/s],   [Reference baseline],
  [zstd -1 (1 core)],        [~500 MB/s],  [~2 GB/s],     [FSE/ANS + branchless LZ],
  [zstd -1 (16 cores)],      [~7 GB/s],    [~30 GB/s],    [Parallel frames],
  [LZ4 (1 core)],            [~700 MB/s],  [~5 GB/s],     [No entropy stage],
  [LZ4 (16 cores, MT 2024)], [~10 GB/s],   [~70 GB/s],    [New in LZ4 2024],
  [nvCOMP Snappy (B200 DE)],  [GPU-bound],  [~180 GB/s],   [Blackwell hardware DE],
  [Intel IAA DEFLATE],        [~10 GB/s],   [~10 GB/s],    [Zero CPU cycles],
)

#checkpoint[
  zstd at 16 threads achieves ~30 GB/s decompression. A PCIe 5.0 NVMe SSD
  can sustain about 14 GB/s read bandwidth. Does the decompressor become the
  bottleneck, or does the SSD?
][
  The SSD is the bottleneck. At 14 GB/s read and ~30 GB/s decompress,
  the decompressor can easily keep up with the incoming data, so the storage
  device will be saturated first. This means that for highly-parallel
  workloads reading from fast NVMe storage, you should *increase* the
  compression ratio (use zstd -3 or -6 instead of -1) to reduce the bytes
  read from disk, even at the cost of slower decompression, because the
  SSD is the bottleneck, not the CPU.
]

== Code walk: annotated branchless inner loop

To make the ideas concrete, here is an annotated Python rendering of the
logic inside a fast LZ sequence copy loop. Python is far too slow to benefit
from these tricks itself (they require C or Rust with SIMD intrinsics), but
reading the structure helps build intuition.

#gopython("bytes and bytearray: mutable versus immutable")[
  In Python, `bytes` objects are *immutable*: you cannot change individual
  bytes after creation. `bytearray` objects are *mutable*: you can write to
  specific indices or slices. Decompressors need to build their output
  incrementally, so they always use `bytearray`.

  ```python
  buf = bytearray(100)  # 100 zero bytes, mutable
  buf[0] = 65           # set byte 0 to ASCII 'A'
  buf[1:5] = b"hello"[0:4]  # copy a slice in
  ```

  The `bytearray[start:stop] = source[start:stop]` form calls into C and
  uses `memmove` internally, which is much faster than a Python `for` loop.
]

#pyrecall[
  The `@dataclass` decorator and the `field: type` annotations below were
  introduced in *Chapter 24*: `@dataclass` auto-generates the boilerplate
  (`__init__`, `__repr__`, ...) for a small record-like class, so `LZToken`
  just lists its three fields and Python writes the constructor for us.
]

```python
from dataclasses import dataclass

@dataclass
class LZToken:
    literal: bytes    # zero or more literal bytes
    offset: int       # distance back into output (0 = no match)
    length: int       # match length (0 = no match)

def lz_decompress(tokens: list[LZToken], capacity: int) -> bytes:
    """
    Decompress a list of LZ tokens into `capacity` bytes.
    Demonstrates the structure of a branchless-style copy loop.
    In production this would be written in C with SIMD, not Python.
    """
    # Pre-allocate with 32-byte headroom so SIMD writes never fault.
    # (In Python this matters less, but the habit is good.)
    out = bytearray(capacity + 32)
    pos = 0

    for tok in tokens:
        # --- literal copy ---
        n_lit = len(tok.literal)
        out[pos : pos + n_lit] = tok.literal
        pos += n_lit

        # --- back-reference copy ---
        if tok.length > 0:
            src = pos - tok.offset
            length = tok.length

            # Fast path: no overlap (offset >= length and offset >= 16).
            # In real code this would be a SIMD 16-byte or 32-byte copy.
            if tok.offset >= length and tok.offset >= 16:
                # Copy whole chunk at once -- no per-byte loop.
                out[pos : pos + length] = out[src : src + length]
            else:
                # Slow path: overlapping copy (e.g. run-length encoding).
                for i in range(length):
                    out[pos + i] = out[src + i]
            pos += length

    return bytes(out[:pos])  # trim to actual output length


# Self-test: encode "abcabcabc" as one literal + one back-reference
tokens = [
    LZToken(literal=b"abc", offset=0, length=0),   # "abc"
    LZToken(literal=b"",    offset=3, length=6),    # repeat "abc" twice
]
result = lz_decompress(tokens, capacity=9)
assert result == b"abcabcabc", f"Got {result}"
print("Round-trip OK:", result)
```

The comment "In real code this would be a SIMD 16-byte or 32-byte copy" is the
key lesson. In C with SIMD intrinsics, `out[pos : pos + length] = out[src : src + length]`
becomes one or two `_mm_storeu_si128` (SSE2, 16 bytes) or `_mm256_storeu_si256`
(AVX2, 32 bytes) instructions. The Python code shows the *logic*; the C code
makes that logic run in nanoseconds.

#takeaways((
  [A single-state rANS decoder leaves most of the CPU idle because each symbol
   depends on the previous one. *Interleaving $N$ states* breaks the dependency
   chain and multiplies throughput by up to $N$.],
  [*SIMD* instructions let one CPU instruction process 4, 8, or 16 rANS states
   simultaneously, pushing decompression into the GB/s range.],
  [*Branchless copy loops* eliminate the per-byte branch in back-reference
   copying; they always copy a fixed-width chunk and rely on the destination
   pointer for correctness, not a loop condition.],
  [*Cache-aware hash tables* (small enough to stay in L2 cache, with
   multi-probe buckets) replace long chain walks with one or two cache
   accesses, enabling compression speeds in the hundreds of MB/s.],
  [*Parallel frames* split input into independent blocks that compress and
   decompress simultaneously on all available CPU cores, giving near-linear
   throughput scaling with a modest ratio penalty.],
  [NVIDIA *nvCOMP* accelerates GPU-resident workloads; the Blackwell
   Decompression Engine reaches 180 GB/s for Snappy, useful in database
   analytics and deep learning pipelines where data never leaves the GPU.],
  [Intel *IAA* and *QAT* offload DEFLATE compression to hardware circuits,
   freeing CPU cores entirely; the right choice for database servers where
   CPU time is the scarce resource.],
  [Fast codecs are not just fast algorithms. They are algorithms designed
   around the latency, throughput, cache hierarchy, and SIMD width of a
   specific hardware generation.],
))

== Exercises

#exercise("73.1", 1)[
  A CPU can retire 4 instructions per clock cycle, runs at 3.5 GHz, and a
  single-state rANS decode loop takes 9 clock cycles per symbol (all
  data-dependent). What is the maximum decompression throughput in MB/s if
  the average symbol represents one byte?
]

#solution("73.1")[
  At 9 cycles per symbol and 3.5 GHz, we get
  $3.5 times 10^9 / 9 approx 389 times 10^6$ symbols per second. If one symbol
  = one byte, that is ~389 MB/s. Notice that 4 instructions/cycle × 3.5 GHz =
  14 billion instructions per second, but we only use 1/9 of that capacity
  because of the dependency chain: 96% of the execution units are idle.
]

#exercise("73.2", 1)[
  Explain in your own words why interleaving *two* rANS states doubles
  throughput without changing the compression ratio. What would happen to the
  ratio if you decoded symbols from only one of the two streams?
]

#solution("73.2")[
  Two independent states have no data dependency between them, so the CPU can
  execute their updates in parallel. This doubles the work done per clock cycle
  without changing the mathematical relationship between symbols and compressed
  bits (each state still encodes its sub-sequence at the entropy rate). If you
  decoded symbols from only one stream, the other stream's data would be lost
  and decompression would fail; you must interleave outputs from both states to
  reconstruct the original sequence.
]

#exercise("73.3", 2)[
  A hash-chain match finder uses a `prev[]` array covering a 2 MB window. Each
  entry is a 4-byte integer. A typical chain walk visits 32 entries. The L3
  cache is 24 MB. Estimate how many cache misses occur per match, and compare
  to a multi-probe bucket design where 8 candidates share one 64-byte cache
  line.
]

#solution("73.3")[
  The `prev[]` array is 2 MB × 4 bytes/entry = 8 MB (if treated as a flat
  array of 524,288 entries). At 32 chain hops, and assuming entries are
  scattered randomly, most hops load a new cache line (approximately 32 cache
  misses per match, though L3 at 24 MB can hold the full 8 MB array, so misses
  become L3 hits at ~40 cycles rather than ~200 cycles for RAM).
  A multi-probe bucket with 8 candidates in one 64-byte cache line needs
  *one* cache-line load for 8 candidates (at most 1 miss per match for the
  common case). This is 8--32x fewer cache misses.
]

#exercise("73.4", 2)[
  A file is compressed with 1 MB frames using 16 threads. The file is 512 MB.
  How many frames are produced? If the single-threaded compression speed is
  400 MB/s, what is the theoretical parallel speed? What compression-ratio
  penalty do you expect relative to single-threaded compression?
]

#solution("73.4")[
  512 MB / 1 MB per frame = 512 frames. With 16 threads, all 16 run
  simultaneously, so the time is approximately (512 frames / 16 threads) × (1 MB / 400 MB/s)
  = 32 × 2.5 ms = 80 ms total, giving a throughput of 512 MB / 80 ms ≈ 6,400 MB/s
  (about 16x the single-threaded speed). The ratio penalty for 1 MB frames is
  typically -1 to -2% relative to single-threaded (from the table in the
  chapter), because matches cannot cross frame boundaries.
]

#exercise("73.5", 3)[
  Implement a two-way interleaved rANS encoder and decoder in Python. Use the
  rANS machinery from Chapter 27 as a reference. Your encoder should distribute
  symbols alternately between two independent states and write both states to
  the output; your decoder should read both states and interleave their outputs.
  Verify round-trip correctness on a short string.
]

#solution("73.5")[
  The key is to treat even-indexed symbols (0, 2, 4, ...) as belonging to
  state 0 and odd-indexed symbols (1, 3, 5, ...) to state 1. The encoder
  processes symbols in *reverse* (ANS is LIFO) and alternates which state
  to push to. The decoder processes symbols in *forward* order, alternating
  which state to pull from. Both states are initialized to the same base
  value $L$ (the range size), and both are serialized to the output stream.
  A correct implementation produces `decode(encode(message)) == message` for
  any input.
]

#exercise("73.6", 2)[
  In the branchless copy loop described in the chapter, the fast path is taken
  when `offset >= length` and `offset >= 16`. Give a concrete example of input
  data where the *slow path* (byte-at-a-time copy) is required, and explain why
  the fast path would produce wrong output for that input.
]

#solution("73.6")[
  Consider offset = 3, length = 9. The output so far ends with "XYZ" and
  the match says "go back 3 bytes and copy 9". The intended output is
  "XYZXYZXYZ" (repeating "XYZ" three times). A fast SIMD copy reads 9 bytes
  starting 3 bytes behind the current write position, but those positions
  ahead of the 3 already-written bytes are garbage (they have not been filled
  yet). The slow byte-at-a-time copy is required: write byte 0 (X), then byte 1
  (Y = position -2), ..., and by the time we write bytes 3--8 the positions
  0--5 of the match have already been filled in by earlier iterations,
  correctly producing the repetition.
]

== Further reading

- #link("https://arxiv.org/abs/1402.3392")[Giesen, F. "Interleaved entropy coders." arXiv:1402.3392, 2014.] -- The paper that formalized interleaved ANS and proved it achieves the entropy rate; short, readable, essential.

- #link("https://fgiesen.wordpress.com/2014/02/02/rans-notes/")[Giesen, F. "rANS notes." ryg blog, February 2014.] -- Practical companion to the paper with implementation details and performance measurements.

- #link("https://github.com/rygorous/ryg_rans")[rygorous/ryg\_rans, GitHub.] -- Public-domain reference implementation of rANS with 2-way and 8-way interleaved variants and SIMD decode paths.

- #link("https://engineering.fb.com/2016/08/31/core-infra/smaller-and-faster-data-compression-with-zstandard/")[Collet, Y. "Smaller and Faster Data Compression with Zstandard." Meta Engineering Blog, 2016.] -- First-person account of the design choices behind zstd's speed; explains FSE and the branchless match copy.

- #link("https://developer.nvidia.com/blog/accelerating-lossless-gpu-compression-with-new-flexible-interfaces-in-nvidia-nvcomp/")[NVIDIA. "Accelerating Lossless GPU Compression with New Flexible Interfaces in nvCOMP." NVIDIA Developer Blog.] -- Official description of nvCOMP's API design and throughput on Ampere/Hopper/Blackwell GPUs.

- #link("https://dl.acm.org/doi/abs/10.1145/3605573.3605588")[Lin, F. et al. "Recoil: Parallel rANS Decoding with Decoder-Adaptive Scalability." ICPP 2023.] -- Extends interleaved rANS to GPU with adaptive lane allocation; benchmarks on CUDA.

- #link("https://www.phoronix.com/news/Linux-6.8-Crypto-Intel")[Larabel, M. "Linux 6.8 Crypto Provides Intel IAA Compression Accelerator Driver." Phoronix, 2024.] -- News coverage of the IAA driver landing in the Linux kernel.

- #link("https://ieeexplore.ieee.org/document/10856688/")[Cui, J. et al. "Hardware-Accelerated Kernel-Space Memory Compression Using Intel QAT." IEEE Computer Architecture Letters, 2025.] -- Quantifies the tail-latency benefit of QAT in `zswap` workloads.

#bridge[
  We now know how to make a compressor fast. But *fast compared to what*?
  Chapter 74 zooms out to place compression in the full I/O stack (caches,
  operating systems, file systems, and networks), showing where compression
  belongs architecturally, how it interacts with prefetching and paging, and
  why sometimes the fastest codec is *no compression at all*. Chapter 75 then
  builds the tools to measure and compare codecs honestly, with benchmarks
  that account for hardware, data types, and use cases.
]
