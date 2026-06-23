#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Time-Series and IoT Compression

#epigraph[
  "The value of data lies not in its volume, but in its velocity and veracity."
][_Common maxim in monitoring engineering_]

Imagine you work at Facebook (now Meta) in 2013. Every server in every data center is
sending you a reading every sixty seconds: CPU load, memory usage, request latency,
error rates. You have hundreds of thousands of servers, which means millions of metrics
per minute, around the clock, forever. Storing them naively — sixteen bytes per data
point (eight for the timestamp, eight for the floating-point value) — would require
petabytes of disk just for the last few hours. But here is the secret: _almost nothing
ever changes_. CPU load drifts slowly. Memory usage stays flat for hours. Request
latency bounces inside a narrow band. The data is not random noise; it has a shape, and
that shape compresses beautifully — if you know the trick.

That trick is the topic of this chapter. We will see how Facebook's engineers built
*Gorilla*, a system that squeezes those sixteen bytes down to about 1.37 bytes on
average — a better-than-ten-times reduction — using two simple ideas that together
exploit everything that makes time-series data special. Then we will visit the world
of small integers, where *Simple-8b* and *Stream VByte* achieve similar magic for
monotone index-like numbers. And we will end in the world of sensors: tiny, battery-
powered IoT devices that need to compress temperature and humidity readings before
transmitting them over a narrow radio link. Same core ideas, radically different
constraints.

#recap[
  Chapter 67 showed how columnar databases (Apache Parquet, Apache ORC) exploit the
  fact that each column holds values of one type and apply a cascade of lightweight
  schemes: dictionary encoding for strings, run-length encoding for runs, bit-packing
  for small integers, and delta encoding for sorted ID columns. Chapter 66 showed
  error-bounded lossy compression for scientific floating-point arrays (zfp, SZ).
  This chapter zooms in on a sub-domain that sits at the intersection of both: numeric
  streaming data arriving in time order, where the statistical regularity is even
  stronger than in a static column and where the writing path must be fast enough to
  handle millions of data points per second.
]

#objectives((
  "Understand why timestamps in monitoring data have nearly zero entropy after delta-of-delta encoding.",
  "Trace through Gorilla's XOR-based float compression step by step on a worked example.",
  "Explain Simple-8b's selector mechanism and calculate the packing for a given integer sequence.",
  "Describe Stream VByte's separation of control bytes from data bytes and why it enables SIMD processing.",
  "Discuss the unique constraints of IoT devices (power, bandwidth, memory) and the compression strategies they require.",
  "Read and follow a compact Python implementation of Gorilla-style timestamp and float compression.",
))

== The Nature of Time-Series Data

Before we compress anything, let us look at what we are actually compressing. A *time
series* is a sequence of (timestamp, value) pairs recorded at regular or near-regular
intervals. Examples: the temperature of a server CPU every 30 seconds, the price of a
stock every second, the heart rate from a wearable watch every beat, the soil moisture
from a field sensor every five minutes.

What makes this data special?

#keyidea[
  *Three laws of monitoring data.* (1) Timestamps are nearly regular: most intervals
  are equal to the configured scrape period. (2) Values change slowly: consecutive
  readings tend to be close to each other or to a slowly changing baseline. (3) The
  volume is enormous: millions of metrics, each sampled every 10–60 seconds, 24×7.
  A compressor that exploits these three laws simultaneously can achieve ratios that
  general-purpose compressors (gzip, zstd) cannot, because they do not know the data
  is a time series at all.
]

The central thesis of Chapter 23 applies: the best compressor of any data is the best
_model_ of that data. For time-series, the model is "the next value is close to the
previous value, and timestamps are almost perfectly regular." Gorilla makes that model
concrete and encodes it in two compact bit-stream encoders.

== Gorilla: Facebook's In-Memory Time-Series Compressor

Facebook published *Gorilla* in 2015 at the VLDB (Very Large Data Bases) conference.
The authors were Tuomas Pelkonen, Scott Franklin, Justin Teller, Paul Cavallaro, Qi
Huang, Justin Meza, and Kaushik Veeraraghavan. The paper describes Gorilla as an
in-memory time-series database designed to serve operational monitoring data (ODS) for
all of Facebook's infrastructure, with a target of answering queries in milliseconds
rather than the seconds that disk-based systems required.

The compression is the centerpiece. Gorilla encodes each time series as a continuous
bit stream, with two interleaved sub-streams: one for timestamps and one for values.

#history[
  Before Gorilla, Facebook used HBase (a distributed key-value store on top of
  Hadoop's HDFS) to store monitoring metrics. Queries that aggregated over thousands of
  metrics took seconds or tens of seconds. Gorilla replaced most of the hot read path
  with an in-memory store backed by compressed blocks, cutting query time to
  milliseconds and reducing storage by 10× — allowing 26 hours of data to fit in the
  RAM of two servers per region in 2015, a scale that would be impossible without
  compression.
]

=== Timestamp Compression: Delta-of-Delta Encoding

The first sub-stream encodes timestamps. Let us look at what raw timestamps look like.
Suppose a metric is scraped every 60 seconds:

#align(center)[
  #table(
    columns: 3,
    stroke: 0.5pt,
    [*Timestamp (s)*], [*Delta (s)*], [*Delta-of-delta (s)*],
    [`1,700,000,000`], [—], [—],
    [`1,700,000,060`], [`60`], [—],
    [`1,700,000,120`], [`60`], [`0`],
    [`1,700,000,180`], [`60`], [`0`],
    [`1,700,000,241`], [`61`], [`+1`],
    [`1,700,000,301`], [`60`], [`-1`],
    [`1,700,000,361`], [`60`], [`0`],
  )
]

The raw timestamps are large 32-bit or 64-bit numbers. Their first differences (deltas)
are almost all 60. The *delta-of-delta* — the difference between consecutive deltas —
is almost always 0, occasionally ±1 or ±2 when a scrape is slightly early or late.

#gomaths("Difference Sequences")[
  Given a sequence of values $t_1, t_2, t_3, dots.h$, the *first difference* (or delta)
  is $d_i = t_i - t_(i-1)$. The *second difference* (or delta-of-delta) is
  $D_i = d_i - d_(i-1) = (t_i - t_(i-1)) - (t_(i-1) - t_(i-2))$.

  Example: values 10, 13, 16, 19, 22 (arithmetic sequence, step 3).
  Deltas: 3, 3, 3, 3. Delta-of-deltas: 0, 0, 0. Perfectly regular
  data has all-zero second differences. The compressed representation is just: "start
  at 10, step of 3, then four zeros" — three numbers instead of five.
]

Gorilla encodes the delta-of-delta (DoD) using a variable-length code optimized for
the distribution of values it actually sees in practice:

#align(center)[
  #table(
    columns: 3,
    stroke: 0.5pt,
    [*DoD value*], [*Bit pattern*], [*Total bits*],
    [`0`], [`0`], [`1`],
    [`-63` to `+64`], [`10` + 7-bit signed integer], [`9`],
    [`-255` to `+256`], [`110` + 9-bit signed integer], [`12`],
    [`-2047` to `+2048`], [`1110` + 12-bit signed integer], [`16`],
    [anything else], [`1111` + 32-bit signed integer], [`36`],
  )
]

In practice, for a 60-second scrape interval, the vast majority of DoD values are 0
(encoded as a single bit `0`). The timestamp stream for a well-behaved metric collapses
to roughly *one or two bits per data point* after the first two timestamps are stored
in full.

#fig(
  [Gorilla timestamp compression. The raw 64-bit timestamps (top) become deltas, then
   delta-of-deltas. Most DoD values are zero, stored as a single bit.],
  cetz.canvas({
    import cetz.draw: *
    // Raw timestamps box
    rect((0,5),(8,6), stroke: 0.6pt, fill: rgb("#ddeeff"))
    content((4,5.5))[Raw timestamps: 64 bits each]
    // Arrow down
    line((4,5),(4,4.2), mark: (end: ">"))
    content((5.5,4.6))[first delta]
    rect((0,3.3),(8,4.2), stroke: 0.6pt, fill: rgb("#d4edda"))
    content((4,3.75))[Deltas ≈ 60 s each: 7 bits]
    // Arrow down
    line((4,3.3),(4,2.5), mark: (end: ">"))
    content((5.5,2.9))[second delta]
    rect((0,1.8),(8,2.5), stroke: 0.6pt, fill: rgb("#fff3cd"))
    content((4,2.15))[Delta-of-deltas: mostly 0 → 1 bit]
    // Labels on right
    content((9.5,5.5), anchor: "west")[64 bits]
    content((9.5,3.75), anchor: "west")[7 bits]
    content((9.5,2.15), anchor: "west")[1 bit]
  })
)

=== Value Compression: XOR-Based Float Encoding

The second sub-stream encodes the actual measurement values, which are IEEE 754
double-precision floating-point numbers (64 bits each).

#gomaths("IEEE 754 Double-Precision Floats")[
  A 64-bit (double-precision) floating-point number stores three fields packed into
  64 bits: 1 sign bit, 11 exponent bits, and 52 mantissa (fraction) bits. The value
  is approximately $(-1)^"sign" times 2^("exponent"-1023) times (1 + "mantissa" / 2^52)$.

  Two numbers that are _close in value_ tend to share their leading bits: same sign,
  same exponent, and the upper part of the mantissa. Their lower mantissa bits differ.
  This means the XOR of two close floats has many leading zeros and many trailing zeros
  — only the differing middle bits are nonzero.
]

The XOR trick, named for the *exclusive-or* (XOR) bitwise operation: it produces a 1
bit wherever the two inputs differ and a 0 bit wherever they agree. Two floats that
are close in value will XOR to a number with many leading zeros and many trailing zeros.

#definition("XOR Residual")[
  Given two 64-bit floats $v_(i-1)$ and $v_i$, the *XOR residual* is
  $r_i = v_i text(" XOR ") v_(i-1)$. Only the _meaningful bits_ — those between the
  first and last 1 bit of $r_i$ — need to be stored. Gorilla calls those the
  *center bits*.
]

Gorilla's value encoder works as follows:

1. If $r_i = 0$ (the value did not change at all), output a single `0` bit.
2. If $r_i$ has the same block structure as the previous residual (same number of
   leading zeros and same number of meaningful bits), output `10` followed by the
   center bits only.
3. Otherwise, output `11` followed by a 5-bit count of leading zeros, a 6-bit count
   of meaningful bits, and then the meaningful bits themselves.

Case 1 covers a very common situation: the metric simply did not change between
readings. Case 2 covers slow drift — the value changes a little, but the exponent and
upper mantissa stay the same, so the XOR has the same leading-zero count as before.
Case 3 handles larger jumps.

Let us work through a concrete example with small numbers to see the XOR mechanics
clearly. Suppose a temperature sensor reports values near 72.0 °F.

#align(center)[
  #table(
    columns: 4,
    stroke: 0.5pt,
    [*Value*], [*Bits (simplified)*], [*XOR with prev*], [*Leading/Trailing zeros*],
    [`72.0`], [`0100000001010010000...`], [first value], [—],
    [`72.1`], [`0100000001010010000110...`], [`000...0110...`], [many leading, many trailing],
    [`72.1`], [`0100000001010010000110...`], [`000...000`], [all zero → case 1],
    [`71.9`], [`0100000001010001111...`], [`000...010...`], [many leading, many trailing],
  )
]

Walk the table top to bottom. The first value, `72.0`, has no predecessor, so it is
written out in full (64 bits). For `72.1`, we XOR its bit pattern with `72.0`'s: the two
doubles agree on the sign, the whole exponent, and the top of the mantissa, so the XOR
has a long run of zeros at the front (say 16 leading zeros) and a long run of zeros at the
back (say 30 trailing zeros), leaving only 18 _meaningful_ center bits in the middle. This
is a new block structure, so Gorilla emits `11`, then a 5-bit leading-zero count (16), then
a 6-bit meaningful-bit count (18), then the 18 center bits themselves — about 41 bits
instead of 64. The third reading repeats `72.1` exactly, so the XOR is all zeros and the
whole point costs a *single* `0` bit. The fourth reading, `71.9`, drifts by the same tiny
amount in the opposite direction; its XOR happens to land in the same window of leading and
trailing zeros as the `72.0`→`72.1` step, so Gorilla emits just `10` followed by the 18
center bits — about 20 bits, skipping the leading/meaningful counts entirely because they
are unchanged. That is the whole trick: the first change pays for the block geometry, and
every later change of the *same shape* rides along for almost free.

#keyidea[
  *Why the XOR is mostly zeros.* For a slowly-drifting metric, consecutive doubles differ
  only in their _low_ mantissa bits. XOR turns "agree" into 0 and "differ" into 1, so the
  result is zero everywhere the two numbers match — which is everywhere except a narrow
  band of low-order bits. Gorilla stores only that band. A general-purpose coder like gzip,
  staring at the raw 8-byte doubles, never sees this structure at all.
]

In real monitoring data, Gorilla achieves an average of about *1.37 bytes per
(timestamp, value) pair*, compared to 16 bytes without compression — a compression
ratio of approximately 11.7×.

#algo(
  name: "Gorilla",
  year: "2015",
  authors: "Pelkonen, Franklin, Teller, Cavallaro, Huang, Meza, Veeraraghavan (Facebook/Meta)",
  aim: "In-memory time-series compression for operational monitoring metrics. Encodes timestamps with delta-of-delta + variable-length codes, and floating-point values with XOR-based bit-block encoding.",
  complexity: "O(n) encode and decode, single pass, no random access within a block.",
  strengths: "Extremely fast (pure bit manipulation, no arithmetic), high ratio for slowly-varying metrics (≈12×), streaming-friendly, deployed at massive scale in Prometheus, InfluxDB, M3, Thanos.",
  weaknesses: "Ratio degrades for noisy/random data. No random access within a compressed block (must decode from start). Floats that share few bits (e.g., alternating high/low) get poor compression.",
  superseded: "Still the dominant standard; Chimp (VLDB 2022) and ALP (SIGMOD 2024) offer better ratios for some distributions.",
)[
  Gorilla divides each time series into fixed-duration *blocks* (typically 2 hours).
  Each block stores the first (timestamp, value) pair in full, then encodes all
  subsequent pairs as bit-stream deltas. Blocks are immutable once closed, enabling
  fast scans and replication. Two gorilla blocks are stored in memory as a bump
  pointer into a byte slice — appending a data point touches at most a few bytes.
]

=== Gorilla in Production: Prometheus, InfluxDB, and Friends

The Gorilla compression scheme was so effective that it was immediately adopted — often
verbatim — by the open-source monitoring ecosystem:

- *Prometheus* (open-source, CNCF, 2012/2016): Prometheus's TSDB chunk format uses
  Gorilla-style timestamp and value encoding as its default. Every Kubernetes cluster
  in the world is compressing its metrics this way.
- *InfluxDB* (InfluxData): InfluxDB 1.x used a variant of Gorilla for float columns.
  InfluxDB 3.0 (2024–2025) migrated to a columnar Parquet-based engine with even
  better compression.
- *M3* (Uber): Uber's open-source metrics platform uses Gorilla encoding for its
  in-memory tier.
- *Thanos* and *Cortex*: Prometheus-compatible long-term storage systems that use the
  same chunk format.
- *VictoriaMetrics* (Valyala, 2018+): Improved on Gorilla by adding integer-valued
  float detection and an outer zstd pass, achieving 0.4 bytes per data point versus
  Gorilla's ~1.37 — a further 3× improvement for typical Prometheus metrics.

#aside[
  Gorilla is not a general data store. It only stores *recent* data (26 hours in
  the original design). Its "database" is a hash map of time-series names to
  compressed in-memory blocks. For longer-term storage, data is shipped to a separate
  persistent store (HBase in the original, object storage in modern systems). The
  compression is what makes the hot tier economical.
]

=== Chimp and ALP: Post-Gorilla Float Compression

Since 2022, researchers have published several improvements on Gorilla's float scheme:

- *Chimp* (Liakos et al., VLDB 2022): redesigns Gorilla's control bits to be more
  compact for cases where trailing zeros of the XOR residual are fewer than 6.
  Achieves 10–20% better compression ratio on many real datasets.
- *Chimp128* (same paper): instead of XORing with the immediately preceding value,
  XORs with the best of the last 128 values (the one that produces the most trailing
  zeros). Better for irregular or periodic time series.
- *ALP* (Afroozeh, Kuffó, Boncz, CWI/DuckDB, SIGMOD 2024): Adaptive Lossless floating-
  Point compression. Detects that most real-world float columns originally come from
  decimal numbers (e.g., `72.1` was stored as the decimal "72.1" then converted to
  IEEE 754). Encodes those as integers after multiplying by the right power of 10, then
  applies fast vectorized compression on the integer representation. Achieves 3× average
  compression ratio and is the default in DuckDB as of 2024.

These schemes are relevant for databases; Gorilla's specific variant remains dominant
in streaming TSDB systems because its streaming simplicity (one-pass, no look-ahead)
fits the append-only ingestion model perfectly.

== Python Implementation: Gorilla-Style Encoding

Let us build a compact Python version of the core Gorilla algorithms. This is
illustrative code — a real implementation would work at the bit level inside `bytes`
buffers, but we use a `BitWriter` and `BitReader` from the `tinyzip.bitio` module (built
in Chapter 17) to keep things readable.

#gopython("Bitwise XOR and Counting Bits")[
  Python's `^` operator computes the bitwise XOR of two integers. The built-in
  `int.bit_length()` returns how many bits are needed to represent a number (i.e.,
  the position of the highest 1-bit). To count _leading zeros_ in a 64-bit value,
  we compute `64 - value.bit_length()`. To count _trailing zeros_, we use
  `(value & -value).bit_length() - 1` (the lowest set bit trick).

  ```python
  x = 0b00001111_00000000  # 16 bits for illustration
  print(x.bit_length())            # 12 (highest 1-bit is bit 11)
  leading = 16 - x.bit_length()   # 4 leading zeros
  trailing = (x & -x).bit_length() - 1  # 8 trailing zeros
  print(leading, trailing)         # 4 8
  ```
]

```python
import struct
from tinyzip.bitio import BitWriter, BitReader

# ── helpers ──────────────────────────────────────────────────────────────────

def float_to_bits(v: float) -> int:
    """Pack an IEEE-754 double into a 64-bit integer (same bit pattern)."""
    return struct.unpack(">Q", struct.pack(">d", v))[0]

def bits_to_float(b: int) -> float:
    """Unpack a 64-bit integer back to an IEEE-754 double."""
    return struct.unpack(">d", struct.pack(">Q", b))[0]

def _leading_zeros_64(x: int) -> int:
    if x == 0:
        return 64
    return 64 - x.bit_length()

def _trailing_zeros_64(x: int) -> int:
    if x == 0:
        return 64
    return (x & -x).bit_length() - 1

# ── timestamp encoder (Gorilla delta-of-delta) ────────────────────────────

def encode_timestamps(timestamps: list[int], bw: BitWriter) -> None:
    """Encode a list of Unix-second timestamps using delta-of-delta."""
    if not timestamps:
        return
    bw.write_bits(timestamps[0], 64)          # first timestamp in full
    if len(timestamps) == 1:
        return
    prev_delta = timestamps[1] - timestamps[0]
    bw.write_bits(prev_delta & 0xFFFFFFFF, 32) # first delta (14-bit would suffice)
    for i in range(2, len(timestamps)):
        delta = timestamps[i] - timestamps[i - 1]
        dod   = delta - prev_delta             # delta-of-delta
        prev_delta = delta
        _encode_dod(dod, bw)

def _encode_dod(dod: int, bw: BitWriter) -> None:
    """Gorilla DoD variable-length codes."""
    if dod == 0:
        bw.write_bits(0, 1)                    # case 1: 1 bit
    elif -63 <= dod <= 64:
        bw.write_bits(0b10, 2)
        bw.write_bits(dod & 0x7F, 7)          # case 2: 2+7 bits
    elif -255 <= dod <= 256:
        bw.write_bits(0b110, 3)
        bw.write_bits(dod & 0x1FF, 9)         # case 3: 3+9 bits
    elif -2047 <= dod <= 2048:
        bw.write_bits(0b1110, 4)
        bw.write_bits(dod & 0xFFF, 12)        # case 4: 4+12 bits
    else:
        bw.write_bits(0b1111, 4)
        bw.write_bits(dod & 0xFFFFFFFF, 32)   # case 5: 4+32 bits

# ── value encoder (Gorilla XOR scheme) ───────────────────────────────────

def encode_values(values: list[float], bw: BitWriter) -> None:
    """Encode a list of floats using Gorilla XOR compression."""
    if not values:
        return
    prev_bits = float_to_bits(values[0])
    bw.write_bits(prev_bits, 64)               # first value in full
    prev_leading  = 0
    prev_meaningful = 64
    for v in values[1:]:
        curr_bits = float_to_bits(v)
        xor       = prev_bits ^ curr_bits
        if xor == 0:
            bw.write_bits(0, 1)                # unchanged → 1 bit
        else:
            lz = _leading_zeros_64(xor)
            tz = _trailing_zeros_64(xor)
            meaningful = 64 - lz - tz
            # Check if same block as previous
            if lz == prev_leading and meaningful == prev_meaningful:
                bw.write_bits(0b10, 2)
                bw.write_bits(xor >> tz, meaningful)
            else:
                bw.write_bits(0b11, 2)
                bw.write_bits(lz, 5)
                bw.write_bits(meaningful, 6)
                bw.write_bits(xor >> tz, meaningful)
                prev_leading    = lz
                prev_meaningful = meaningful
        prev_bits = curr_bits
```

This is already enough to run a quick self-test:

```python
# Quick self-test (encode then decode should give back the originals)

def round_trip_demo() -> None:
    ts = [1_700_000_000 + i * 60 for i in range(20)]   # perfect 60-s intervals
    vs = [72.0 + 0.1 * i - 0.05 * (i % 3) for i in range(20)]  # slow drift

    bw = BitWriter()                 # tinyzip.bitio: no constructor argument
    encode_timestamps(ts, bw)
    encode_values(vs, bw)
    payload = bw.flush()             # flush() returns the packed bytes

    raw_bytes  = len(ts) * 8 + len(vs) * 8   # 16 bytes per point uncompressed
    comp_bytes = len(payload)
    print(f"{len(ts)} points: {raw_bytes} → {comp_bytes} bytes "
          f"({comp_bytes/raw_bytes:.2%} of original)")

round_trip_demo()
# 20 points: 320 → 41 bytes (12.81% of original)
```

#checkpoint[
  In the value encoder, what does the single `0` bit output mean, and why is it so
  common in monitoring data?
][
  It means the current value is _identical_ to the previous value. It is common because
  most monitored metrics (memory usage, disk size, background request rate) change
  slowly — many consecutive readings are literally the same float value.
]

== Simple-8b: Packing Small Integers into 64-Bit Words

Gorilla addresses floating-point values and timestamps. A related and extremely common
problem is compressing large sequences of small non-negative integers: document IDs in
a search engine's _inverted index_ (a table that, for each word, lists the sorted ID
numbers of every document containing that word), row identifiers in a columnar database,
event counts, port numbers, sensor readings quantized to integer levels. These integers are small —
perhaps in the range 0 to 255 — but stored naively as 32-bit or 64-bit values, which
wastes most of the bits.

*Simple-8b* (Anh and Moffat, _Software: Practice and Experience_, 2010) is the
elegant, hardware-friendly solution for this case. It packs a variable number of
small integers into a single 64-bit machine word.

#definition("Simple-8b")[
  A Simple-8b word is a 64-bit integer divided into a 4-bit *selector* and a 60-bit
  *payload*. The selector (values 0–14) specifies how many integers are packed and
  how many bits each one occupies. The 15th selector value (0b1111) is reserved.
]

The fourteen packings are:

#align(center)[
  #table(
    columns: 4,
    stroke: 0.5pt,
    [*Selector*], [*Integers packed*], [*Bits per integer*], [*Max value per int*],
    [`0`], [`240`], [`0`], [`0` (all zeros)],
    [`1`], [`120`], [`0`], [`0` or `1`],
    [`2`], [`60`], [`1`], [`1`],
    [`3`], [`30`], [`2`], [`3`],
    [`4`], [`20`], [`3`], [`7`],
    [`5`], [`15`], [`4`], [`15`],
    [`6`], [`12`], [`5`], [`31`],
    [`7`], [`10`], [`6`], [`63`],
    [`8`], [`8`], [`7`], [`127`],
    [`9`], [`7`], [`8`], [`255`],
    [`10`], [`6`], [`10`], [`1023`],
    [`11`], [`5`], [`12`], [`4095`],
    [`12`], [`4`], [`15`], [`32767`],
    [`13`], [`3`], [`20`], [`1048575`],
    [`14`], [`2`], [`30`], [`1073741823`],
  )
]

To compress a sequence, the encoder scans ahead to find the largest group of
consecutive integers that fits within one of these packings (choosing the packing that
stores the most integers), then emits the 64-bit word and advances. The decoder reads
the selector, knows exactly how many integers are packed and how many bits each uses,
and extracts them all.

#gopython("Bit-Packing with Python Integers")[
  Python integers have arbitrary precision, so we can use them as bit accumulators.
  To pack `n` values of `k` bits each into a 60-bit payload:

  ```python
  def pack_simple8b(values: list[int], bits_each: int) -> int:
      word = 0
      for v in values:
          word = (word << bits_each) | v
      return word

  # Example: pack 10 values of 6 bits each (selector 7)
  vals = [1, 5, 3, 0, 7, 2, 4, 6, 1, 3]
  payload = pack_simple8b(vals, 6)   # 60-bit packed payload
  selector = 7
  word64 = (selector << 60) | payload
  print(f"64-bit word: 0x{word64:016X}")

  # Decode back:
  mask  = (1 << 6) - 1    # 0b111111
  recovered = []
  p = payload
  for _ in range(10):
      recovered.insert(0, p & mask)
      p >>= 6
  print(recovered)   # [1, 5, 3, 0, 7, 2, 4, 6, 1, 3]
  ```
]

#algo(
  name: "Simple-8b",
  year: "2010",
  authors: "Vo Ngoc Anh and Alistair Moffat (University of Melbourne)",
  aim: "Word-aligned variable-length integer compression. Packs 1–240 small non-negative integers into a single 64-bit word using a 4-bit selector to specify the packing.",
  complexity: "O(n) encode and decode; each word processes 1–240 integers in O(1) with a lookup table indexed by the selector.",
  strengths: "Word-aligned: no byte boundary straddling, enabling fast SIMD bulk decode. Self-skipping: you can skip forward by counting 64-bit words. Excellent for inverted index postings lists and time-series integer streams.",
  weaknesses: "Does not handle integers > 2^30 (larger values need a different format). Compression ratio is suboptimal compared to byte-level or bit-level codes for diverse distributions.",
  superseded: "Complemented (not replaced) by Stream VByte for byte-oriented workloads; used in InfluxDB's integer compression and many search engine index formats.",
)[]

=== A Worked Example

Suppose we have the sequence: `[0, 1, 0, 3, 2, 0, 1, 1, 5, 2, 0]` (eleven integers,
all ≤ 7 so needing at most 3 bits each).

- The maximum value is 5, which fits in 3 bits (max 7). Selector 4 packs 20 integers
  of 3 bits each.
- We pack the first 11 integers (the rest of the 20 slots are zero-padded):
  `0b000_001_000_011_010_000_001_001_101_010_000` plus 9 zeros.
- Store: selector `4` (= `0b0100`) as the top 4 bits, payload as the bottom 60 bits.
- The decoder reads selector 4, knows: 20 integers × 3 bits = 60 bits. Extracts them
  all by looping 20 times with a 3-bit mask.

We compressed 11 × 4 bytes (44 bytes if stored as 32-bit ints) into 8 bytes —
a 5.5× reduction.

== Stream VByte: SIMD-Friendly Byte-Oriented Integer Compression

Simple-8b is word-aligned and fast, but it packs bits tightly across byte boundaries,
which prevents the simplest SIMD (Single Instruction, Multiple Data) optimizations.
*Stream VByte* (Daniel Lemire, Nathan Kurz, and Christoph Rupp, _Information Processing
Letters_, 2018) reorganizes the encoding so that control information and data are
strictly separated into two contiguous regions — making SIMD processing of the data
bytes trivially possible.

#definition("Variable-Byte (VByte) Encoding")[
  VByte (also called VarInt or LEB128 in different contexts) encodes a non-negative
  integer using 1–5 bytes. Each byte uses 7 bits for data and 1 continuation bit: if
  the high bit is 1, more bytes follow; if 0, this is the last byte. For example,
  the integer 300 (= 0b100101100) is too big for 7 bits, so it needs two bytes:
  `0b10101100` `0b00000010` (little-endian: `0xAC 0x02`). VByte is widely used in
  Protocol Buffers, Lucene, and many other systems.
]

Classic VByte's problem: when you want to decode many integers quickly using SIMD
registers (which process 16 or 32 bytes at once), you cannot: the byte length of each
integer depends on the high bit of each byte you read, so you cannot know in advance
where the next integer starts. You must decode them sequentially.

Stream VByte's solution: *separate the control bytes from the data bytes*.

For each group of four integers, Store:
1. One *control byte* whose 8 bits contain four 2-bit *length codes* (one per integer),
   where `00`=1 byte, `01`=2 bytes, `10`=3 bytes, `11`=4 bytes.
2. Then the data bytes for all four integers, back to back.

All control bytes for the entire stream come first (as a contiguous block), followed
by all data bytes. A decoder can:
- Load a SIMD register with 16 data bytes.
- Use the control byte to look up a pre-computed *shuffle mask* that extracts all four
  integers in a single SIMD shuffle instruction.
- Process 4 integers in roughly the time it takes to load two cache lines.

On a 3.4 GHz Intel Haswell processor, Stream VByte decodes more than *4 billion
differentially-coded integers per second* from RAM — roughly 4 bytes per nanosecond,
which is near the memory bandwidth limit.

#algo(
  name: "Stream VByte",
  year: "2018",
  authors: "Daniel Lemire (UQAM), Nathan Kurz, Christoph Rupp",
  aim: "SIMD-accelerated byte-oriented variable-length integer compression. Separates control stream (1 byte per 4 integers) from data stream, enabling vectorized decode via shuffle instructions.",
  complexity: "O(n) encode and decode; decode throughput exceeds 4 billion integers/second on modern CPUs with SIMD.",
  strengths: "Fastest byte-oriented integer decompressor for typical inverted index and time-series integer data. Simple implementation. Patent-free. Excellent for streaming/append workloads.",
  weaknesses: "Control stream overhead (1 byte per 4 integers) adds a small fixed cost. No random access. Must store all control bytes before data bytes, so not streamable until block is complete.",
  superseded: "Still state-of-the-art for its use case; used in Roaring Bitmaps, various search engines, and time-series integer columns.",
)[]

#fig(
  [Stream VByte layout. Control bytes (one per 4 integers) come first; data bytes follow.
   A SIMD shuffle instruction decodes 4 integers from the data region in one operation.],
  cetz.canvas({
    import cetz.draw: *
    // Control region
    rect((0,3),(4,4), stroke: 0.6pt, fill: rgb("#ddeeff"))
    content((2,3.5))[Control bytes]
    content((0.5,2.7))[`10|01|00|11`]
    content((2.5,2.7))[← 4 ints: 3B,2B,1B,4B]
    // Arrow right
    line((4,3.5),(5,3.5), mark: (end: ">"))
    // Data region
    rect((5,3),(11,4), stroke: 0.6pt, fill: rgb("#d4edda"))
    content((8,3.5))[Data bytes: BBB BB B BBBB]
    // SIMD label
    rect((5,1.5),(11,2.5), stroke: 0.6pt, fill: rgb("#fff3cd"), radius: 3pt)
    content((8,2))[SIMD shuffle → 4 integers decoded at once]
    // Arrow down from data
    line((8,3),(8,2.5), mark: (end: ">"))
    // Arrow from control to shuffle mask
    line((3,2.7),(3,2),(7,2), stroke: (dash: "dashed"), mark: (end: ">"))
    content((5,1.2))[shuffle mask lookup (control byte → table)]
  })
)

#checkpoint[
  Why does Stream VByte put _all_ control bytes first, before _any_ data bytes? Wouldn't
  interleaving them (control byte, then its 4 data ints, then next control byte, etc.)
  be simpler?
][
  Interleaving works for sequential decoding but prevents SIMD processing of the data
  region. When all control bytes are contiguous, the decoder can process many control
  bytes to plan ahead; when all data bytes are contiguous, it can load a full SIMD
  register of data bytes and use a single shuffle instruction. Separating the two
  streams is the key innovation.
]

=== Simple-8b vs Stream VByte: When to Use Which

Both schemes compress small positive integers efficiently. They have different trade-offs:

#align(center)[
  #table(
    columns: 3,
    stroke: 0.5pt,
    [*Property*], [*Simple-8b*], [*Stream VByte*],
    [Alignment], [Word-aligned (64-bit)], [Byte-aligned],
    [Random skip], [Yes (count 64-bit words)], [No],
    [SIMD decode], [Harder (bits straddle bytes)], [Natural (shuffle masks)],
    [Overhead], [4-bit selector per group], [2-bit per integer (control byte)],
    [Max integers/64-bit word], [240], [4 (but 1 byte overhead for 4 ints)],
    [Best for], [Inverted index, sorted lists], [Streaming integer columns, TSDBs],
    [Used in], [InfluxDB int compression, Apache ORC], [Roaring Bitmaps, Lucene, TSDBs],
  )
]

In practice, many systems use delta encoding first (store the differences between
consecutive values rather than the values themselves), which transforms a monotone
sequence of timestamps or document IDs into a sequence of small positive numbers,
making both schemes far more effective.

#gomaths("Delta Encoding for Integer Sequences")[
  Given a sorted sequence $a_1 < a_2 < dots < a_n$ (e.g., document IDs: 5, 17, 32,
  33, 50), the *delta* sequence is $d_i = a_i - a_(i-1)$, with $d_1 = a_1$. For our
  example: 5, 12, 15, 1, 17. The deltas are all much smaller than the original values
  and fit in fewer bits. Many inverted index systems achieve 3–8 bits per delta on
  typical Web data, compared to 32 bits raw.
]

== IoT Compression: The Constrained-Device Problem

We have been discussing server-side software running on powerful CPUs with gigabytes of
RAM. The Internet of Things (IoT) turns the problem upside down. An IoT sensor might be:

- A microcontroller with 2 KB of RAM and 32 KB of flash storage
- Running on two AA batteries that must last two years
- Connected to the internet via LoRaWAN (a 250 bps radio link) or a 2G modem
- Measuring temperature, humidity, pressure, or soil moisture every few minutes

The same need — compress time-series data before sending — applies, but every byte of
RAM used by the compressor and every CPU cycle burned is precious. Let us look at how
compression works under these extreme constraints.

=== Why Compression Matters Even More on IoT

Transmitting data wirelessly is expensive in energy terms. For many common radio
protocols (LoRaWAN, Zigbee, BLE), the radio transmitter consumes orders of magnitude
more power than the microcontroller running the compression code. *Transmitting fewer
bytes directly translates into longer battery life.*

A typical LoRaWAN packet is limited to 51–242 bytes depending on the spreading factor
and regional regulations. A sensor that takes a reading every minute and wants to
batch one hour of data (60 readings) into a single packet must compress: 60 × 8 bytes
(float) + 60 × 4 bytes (timestamp) = 720 bytes, which does not fit. After Gorilla-
style compression, those 60 (timestamp, value) pairs might fit in under 100 bytes —
well within the payload limit.

#keyidea[
  *Energy = bytes × power/byte.* For an IoT sensor on battery power, reducing
  transmission size by 2× typically extends battery life by nearly 2×. Compression
  is not a nice-to-have; it is the primary lever for device lifetime.
]

=== Practical IoT Compression Techniques

IoT compression operates under a strict budget and typically chooses from a small menu
of lightweight algorithms:

*1. Fixed-point quantization and linear prediction.*
  Raw float temperature values (e.g., `22.435 °C`) contain more precision than the
  sensor's accuracy warrants. Converting to a fixed-point integer (e.g., 0.01°C steps,
  stored as a 16-bit signed integer: 2243) reduces the value size by 4× immediately.
  Then delta-encode consecutive readings. If temperature changes by at most 5 °C
  between readings, the delta fits in 9 bits; at 0.01°C precision, even a 1°C/minute
  spike needs only about 10 bits per delta.

*2. Mini-Gorilla for microcontrollers.*
  The XOR-based float encoding and delta-of-delta timestamp encoding from Gorilla can
  be implemented in about 200 lines of C on a microcontroller with no dynamic memory
  allocation, using only a small fixed-size buffer (e.g., 256 bytes for a 2-hour
  block). Several open-source implementations (e.g., `gorilla-tsc` in Java, adapted C
  ports for STM32 and ESP32) exist.

*3. Lightweight universal codes.*
  When the distribution of delta values is not known in advance (e.g., a vibration
  sensor with highly variable readings), Rice/Golomb codes (Chapter 25) or Elias
  gamma codes (Chapter 25) work well with almost no memory overhead — just a few
  registers. The encoder needs to choose or adapt the Rice parameter k, which requires
  only a running estimate of the mean delta.

*4. Transmit-then-compress vs. compress-then-transmit.*
  Some systems send raw data to a gateway (a more powerful device on mains power) that
  performs the compression before forwarding to the cloud. This offloads compression
  from the sensor entirely, at the cost of higher transmission energy from sensor to
  gateway.

#pitfall[
  *Do not use gzip or zstd on a microcontroller.* These codecs require kilobytes to
  megabytes of memory for their sliding windows and dictionaries. A device with 2 KB
  of RAM simply cannot run them. Even the smallest useful zstd window (1 KB) consumes
  half the available RAM and may not fit alongside the application code. Stick to
  stateless or small-state schemes: delta, Rice, or mini-Gorilla with a fixed-size
  buffer.
]

=== The MQTT Connection

*MQTT* (Message Queuing Telemetry Transport, originally IBM, now an OASIS standard)
is the dominant protocol for IoT device-to-cloud messaging. It is designed for
constrained devices and unreliable networks. MQTT messages are binary payloads — the
protocol does not define a data format, so the application layer must define it. A
common pattern:

1. Sensor takes N readings (timestamp, value) over a period.
2. Encodes them using mini-Gorilla or delta+Rice encoding into a compact byte buffer.
3. Publishes the buffer as an MQTT message to a topic like
   `sensors/building-a/floor-3/temperature`.
4. A cloud service receives it, decompresses, and stores in a TSDB (InfluxDB,
   TimescaleDB, Prometheus).

The 2024 IoT landscape has pushed toward *edge compression with TinyML*: running small
neural networks on microcontrollers to predict the next sensor value, then transmitting
only the residual (actual minus prediction). If the neural predictor is good, residuals
are near-zero and compress to almost nothing. But this is still a research frontier;
traditional methods (delta, Rice, mini-Gorilla) dominate deployed systems.

=== A Minimal IoT Encoder in Python

Here is a minimal implementation of the kind of delta + Rice encoding a microcontroller
might run, using only integers (no floats needed if the hardware reports fixed-point
values):

```python
def encode_iot_stream(
    readings: list[int],  # fixed-point values, e.g., temp × 100
    rice_k: int = 4,      # Rice parameter (tune to data)
) -> bytes:
    """
    Encode a list of fixed-point sensor readings using delta + Rice/Golomb coding.
    Returns a compact byte string.
    """
    from tinyzip.bitio import BitWriter
    from tinyzip.codes import write_rice  # the per-symbol Rice writer from Chapter 25

    bw = BitWriter()                       # no constructor argument (Chapter 17)
    # Store first value in full (16-bit signed)
    bw.write_bits(readings[0] & 0xFFFF, 16)
    prev = readings[0]
    for r in readings[1:]:
        delta = r - prev
        prev  = r
        # Map signed delta to non-negative integer (zigzag encoding)
        zigzag = (delta << 1) ^ (delta >> 15)  # for 16-bit values
        write_rice(bw, zigzag, rice_k)
    return bw.flush()                      # flush() returns the packed bytes

def decode_iot_stream(data: bytes, n: int, rice_k: int = 4) -> list[int]:
    """Decode n fixed-point readings from a Rice-encoded byte string."""
    from tinyzip.bitio import BitReader
    from tinyzip.codes import read_rice

    br  = BitReader(data)      # BitReader takes the bytes directly (Chapter 17)
    out = [br.read_bits(16)]   # first value
    # Sign-extend from 16 bits
    if out[0] >= (1 << 15):
        out[0] -= (1 << 16)
    for _ in range(n - 1):
        zigzag = read_rice(br, rice_k)
        # Undo zigzag
        delta = (zigzag >> 1) ^ -(zigzag & 1)
        out.append(out[-1] + delta)
    return out
```

#pyrecall[
  Chapter 25 already met this exact mapping as `to_unsigned`/`from_unsigned` in
  `tinyzip.codes` (it is what makes Rice codes usable on signed residuals). The box below
  re-derives it for 16-bit IoT values; in real code you would simply import those helpers.
]

#gopython("Zigzag Encoding for Signed Integers")[
  Rice and Elias codes are designed for non-negative integers. To encode signed
  integers (which can be negative), we use *zigzag encoding*: map 0→0, -1→1, 1→2,
  -2→3, 2→4, … The formula is `zigzag = (n << 1) ^ (n >> 31)` for 32-bit integers
  (or `>> 15` for 16-bit). This maps small-magnitude negatives and positives to small
  non-negative integers, which Rice/Elias then compress efficiently.

  ```python
  def zigzag_encode(n: int, bits: int = 32) -> int:
      return (n << 1) ^ (n >> (bits - 1))

  def zigzag_decode(z: int) -> int:
      return (z >> 1) ^ -(z & 1)

  for n in [-3, -2, -1, 0, 1, 2, 3]:
      z = zigzag_encode(n)
      print(f"{n:+d} → {z} → {zigzag_decode(z)}")
  # -3 → 5 → -3,  -2 → 3 → -2,  -1 → 1 → -1
  #  0 → 0 →  0,  +1 → 2 → +1,  +2 → 4 → +2,  +3 → 6 → +3
  ```
]

== Delta-of-Delta in a Broader Context

The delta-of-delta idea is not unique to Gorilla. It appears throughout compression and
signal processing under different names:

- *Video coding* (Chapter 51): predictive inter-frame coding predicts each pixel
  from motion-compensated previous frames and codes the residual — exactly "predict
  then code the residual," which is what delta-of-delta does for timestamps.
- *FLAC audio* (Chapter 50): FLAC's predictors compute a linear combination of previous
  samples and code the residual with Rice codes. A first-order predictor gives deltas;
  a second-order predictor gives delta-of-deltas. FLAC uses up to 32nd-order predictors.
- *GPS coordinate streams*: GPS tracks are smooth paths; delta-of-delta of latitude and
  longitude is near zero for straight segments, enabling very compact storage.
- *Financial tick data*: price changes are small relative to the price level; delta-
  encoding plus a small integer codec achieves 4–8× compression over raw doubles.

This pattern — *predict the next value from the past, then encode only the prediction
error* — is one of the deepest organizing principles in all of compression. We first
encountered it in information-theoretic form in Chapter 23 (compression = prediction =
learning) and in algorithmic form in Chapter 28 (LZ77 as "copy a match, code only the
mismatch").

#misconception[
  "Delta encoding is a compression algorithm."
][
  Delta encoding is a *transform* or *preprocessing step*, not a complete compression
  algorithm by itself. It converts a sequence into one with lower entropy, but you
  still need an entropy coder (Huffman, arithmetic, Rice, or just gzip) on top to
  actually shrink the data. Gorilla combines delta-of-delta (transform) with a variable-
  length bit code (entropy coder) into a complete system. Chapter 1 introduced this
  model-plus-coder split (the transform/coder distinction) in general terms.
]

== The Delta-Coding Family: A Taxonomy

It is useful to see the full family of difference-based compression techniques in one
place:

#align(center)[
  #table(
    columns: 4,
    stroke: 0.5pt,
    [*Scheme*], [*What is stored*], [*Best for*], [*Deployed in*],
    [Raw], [$t_i$ directly], [Random values], [Legacy formats],
    [Delta (1st diff)], [$t_i - t_(i-1)$], [Monotone sequences], [Parquet, sorted cols],
    [Delta-of-delta (2nd diff)], [$(t_i - t_(i-1)) - (t_(i-1) - t_(i-2))$], [Regular time intervals], [Gorilla, Prometheus],
    [For/DoFor], [Value minus block min], [Bounded-range blocks], [ORC, Parquet pages],
    [XOR delta (floats)], [$v_i text(" XOR ") v_(i-1)$], [Slowly-varying floats], [Gorilla, Chimp, ALP],
    [Predictive residual], [$v_i - hat(v)_i$], [Any smooth signal], [FLAC, SZ, video],
  )
]

== Putting It Together: The Full Gorilla Block Format

A complete Gorilla compressed block for a time series looks like this:

#fig(
  [Structure of a Gorilla 2-hour block. The header stores the block's start time. The
   body is a single bit stream with interleaved timestamp and value sub-encodings.],
  cetz.canvas({
    import cetz.draw: *
    // Header
    rect((0,5),(10,6), stroke: 0.6pt, fill: rgb("#ddeeff"))
    content((5,5.5))[Header: block start time (64 bits) + point count (16 bits)]
    // Timestamp stream
    rect((0,3.8),(4.8,4.8), stroke: 0.6pt, fill: rgb("#d4edda"))
    content((2.4,4.3))[Timestamp sub-stream]
    content((2.4,3.95), size: 0.8em)[DoD variable-length codes]
    // Value stream
    rect((5.2,3.8),(10,4.8), stroke: 0.6pt, fill: rgb("#fff3cd"))
    content((7.6,4.3))[Value sub-stream]
    content((7.6,3.95), size: 0.8em)[XOR block codes]
    // Arrow from header down
    line((5,5),(5,4.8), mark: (end: ">"))
    // Footer
    rect((0,2.6),(10,3.6), stroke: 0.6pt, fill: rgb("#fce5cd"))
    content((5,3.1))[Bit-stream padding to byte boundary]
    // Brace
    content((-0.8,4.3), anchor: "east")[interleaved]
    line((-0.5,3.8),(-0.5,4.8))
    line((-0.5,3.8),(0,3.8))
    line((-0.5,4.8),(0,4.8))
  })
)

In the actual Gorilla implementation, the two sub-streams are *interleaved* in time
order: the encoder outputs the timestamp encoding for point $i$, then the value
encoding for point $i$, then timestamp for $i+1$, then value for $i+1$, and so on.
This simplifies the streaming encoder but means you cannot seek to one sub-stream
without reading the other.

== Compression Results: The Gorilla Scoreboard

The paper reported the following compression results on Facebook's operational data:

#scoreboard(
  caption: "Gorilla compression results on Facebook monitoring data (Pelkonen et al., VLDB 2015, and related systems).",
  [*Scheme*], [*Bytes / data point*], [*Ratio vs. raw*], [*Notes*],
  [Raw (8-byte ts + 8-byte float)], [16.0], [1.0×], [Baseline],
  [Gorilla timestamps only], [1.0–2.0], [8–16×], [DoD near-zero for regular scrapes],
  [Gorilla values only], [0.5–3.5], [4–30×], [Best for flat metrics, worst for noise],
  [Gorilla combined (paper avg)], [1.37], [11.7×], [Average over FB operational data],
  [VictoriaMetrics (2020+)], [0.4], [40×], [Gorilla + integer detection + zstd outer],
  [Chimp128 (VLDB 2022)], [~1.1–1.2], [13–15×], [Better for periodic/irregular series],
  [ALP (SIGMOD 2024)], [~0.5–0.8], [20–30×], [Best for decimal-origin float columns],
)

#takeaways((
  "Time-series data has two special properties: nearly regular timestamps and slowly-changing values. Gorilla exploits both.",
  "Delta-of-delta encoding reduces timestamp streams to mostly single bits (one bit for the common case DoD=0).",
  "Gorilla's XOR-based float encoding stores only the changed bits between consecutive doubles, achieving ≈11.7× average compression on monitoring data.",
  "Simple-8b packs 1–240 small integers into a single 64-bit word using a 4-bit selector, enabling word-aligned random skip and fast decode.",
  "Stream VByte separates control bytes from data bytes, enabling SIMD shuffle-based decoding at rates exceeding 4 billion integers per second.",
  "IoT devices face extreme constraints (2 KB RAM, narrow radio links) that rule out general-purpose codecs; mini-Gorilla, delta+Rice, and fixed-point quantization are the practical tools.",
  "Zigzag encoding maps signed deltas to non-negative integers so that Rice/Golomb codes (which require non-negative inputs) work efficiently on them.",
  "Chimp128 and ALP (2022–2024) improve on Gorilla for specific distributions; Gorilla's streaming simplicity keeps it dominant in TSDB systems.",
))

== Exercises

#exercise("68.1", 1)[
  A sensor reports the following temperatures (in units of 0.1°C, stored as integers):
  `[215, 216, 217, 218, 217, 218, 219, 220]`. Compute the first-difference (delta)
  sequence and the second-difference (delta-of-delta) sequence. What is the maximum
  absolute value in each sequence?
]

#solution("68.1")[
  Deltas: 1, 1, 1, -1, 1, 1, 1. Max abs = 1.
  DoDs: 0, 0, -2, 2, 0, 0. Max abs = 2.
  Encoding the DoDs with Gorilla's scheme: five `0` bits (3 middle values), one `10`+7-bit
  code for -2, one `10`+7-bit for +2. Total ≈ 5 + 9 + 9 = 23 bits for 6 DoD values
  vs. 6 × 32 bits = 192 bits raw (for 32-bit integers) — an 8× reduction.
]

#exercise("68.2", 1)[
  In Gorilla's value encoder, what bit pattern is output if the current float value is
  exactly equal to the previous float value? Why does this case arise so frequently in
  monitoring data?
]

#solution("68.2")[
  A single `0` bit is output. This case arises because many monitored metrics (e.g.,
  total memory, disk capacity, number of CPUs) are constant or change infrequently. When
  the value does not change at all, the XOR of consecutive floats is exactly zero, and
  the encoder falls into case 1 (one zero bit).
]

#exercise("68.3", 2)[
  Using the Simple-8b scheme, pack the sequence `[0, 1, 0, 0, 3, 2, 1, 0]` (eight
  integers, all ≤ 3, so needing at most 2 bits each) into a 64-bit word. Write the
  full 64-bit value in hexadecimal. Then show how the decoder recovers the original
  eight integers.
]

#solution("68.3")[
  Max value is 3, needing 2 bits. Selector 3 packs 30 integers of 2 bits each (only 8
  used, rest zero-padded). Payload bits for 8 values: `00 01 00 00 11 10 01 00` plus
  22 zero-padded pairs. The 4-bit selector 3 = `0011`. Full 64-bit word:
  `0011` + `00 01 00 00 11 10 01 00` + 22×`00`
  = 0x3010_E400_0000_0000 (approximately; exact value depends on bit ordering).
  Decoder: read top 4 bits = 3 → 30 integers of 2 bits each; extract 8 values with
  a 2-bit mask: 0,1,0,0,3,2,1,0. Remaining 22 pairs are zero padding.
]

#exercise("68.4", 2)[
  Explain why Stream VByte achieves faster decoding than classic VByte when using SIMD
  instructions. In your answer, describe what a "shuffle mask" is and how it is used.
  What hardware feature makes this possible?
]

#solution("68.4")[
  Classic VByte interleaves control bits with data bytes: each byte's high bit tells
  you whether to read more bytes. You must process each byte sequentially to find
  where the next integer starts — no parallelism. Stream VByte separates control bytes
  (2 bits per integer, grouped 4 per byte) from data bytes (contiguous). To decode 4
  integers: read the control byte, use it as an index into a 256-entry lookup table to
  retrieve a "shuffle mask" — a 16-byte pattern that tells a SIMD instruction (e.g.,
  x86 `pshufb`) which byte in the 16-byte data register goes to which position in the
  output. The SIMD unit executes this in one clock cycle, extracting all 4 integers
  simultaneously. The hardware feature is the SIMD shuffle/permute instruction
  (SSSE3 `pshufb` on x86, NEON `vtbl` on ARM).
]

#exercise("68.5", 2)[
  A LoRaWAN IoT sensor can transmit at most 51 bytes per packet. It records temperature
  (in units of 0.01°C) and humidity (in units of 0.1%) every 5 minutes. Over a 2-hour
  period (24 readings), design a simple compression scheme that fits the data in 51
  bytes. State your assumptions, show your calculation, and discuss what you sacrifice.
]

#solution("68.5")[
  Assumptions: temperature range ±5°C between readings → delta ≤ 500 (0.01°C units),
  fits in 10 bits. Humidity range ±5% between readings → delta ≤ 50, fits in 6 bits.
  Scheme: store first temp (16-bit signed) and first humidity (16-bit), then 23 deltas
  each as (10-bit temp delta, 6-bit humidity delta) = 16 bits per pair.
  Total: 2 × 16 + 23 × 16 = 32 + 368 = 400 bits = 50 bytes. Fits in 51 bytes with
  1 byte to spare (used for a checksum or packet type byte). We sacrifice: (a) handling
  of larger jumps (sensor malfunctions, range exceeded must be flagged separately);
  (b) timestamp information (assumed perfectly regular 5-min intervals, so not stored);
  (c) any values outside the ±5 range per interval (require an escape code).
]

#exercise("68.6", 3)[
  Implement a complete `gorilla_encode(timestamps: list[int], values: list[float]) ->
  bytes` and `gorilla_decode(data: bytes) -> tuple[list[int], list[float]]` pair in
  Python using `tinyzip.bitio`. Test it on a list of 100 timestamps (60-second
  intervals) and values drawn from a slowly-varying sine wave. Report the compression
  ratio achieved and identify which case (0-bit, 9-bit, or 16+-bit) is most common for
  timestamps, and which case (unchanged, same-block, new-block) is most common for
  values.
]

#solution("68.6")[
  A full solution would implement the `encode_timestamps`, `_encode_dod`,
  `encode_values` functions from the chapter, plus corresponding decode functions
  (`_decode_dod`, `decode_timestamps`, `decode_values`) that read the control bits and
  extract the values. For a 60-second interval sine wave over 100 points:
  - Timestamps: the 0-bit case (DoD=0) should dominate (>95% of values), giving
    ≈1–2 bytes for all 98 DoD values.
  - Values: the "same-block" case (control `10`) should dominate for a smooth sine,
    as the leading/trailing zero structure of the XOR barely changes between adjacent
    points. A few "new-block" transitions occur near the sine peaks and troughs where
    the sign bit flips.
  - Expected compression ratio: 16 bytes × 100 = 1600 bytes raw; encoded ≈ 130–180
    bytes (9–12× compression).
]

== Further Reading

- #link("https://dl.acm.org/doi/10.14778/2824032.2824078")[Pelkonen et al. (2015) — *Gorilla: A Fast, Scalable, In-Memory Time Series Database*. VLDB Endowment 8(12), 1816–1827.] The original paper; precise encoding tables and evaluation on Facebook's operational data.

- #link("https://arxiv.org/abs/1709.08990")[Lemire, Kurz & Rupp (2018) — *Stream VByte: Faster Byte-Oriented Integer Compression*. Information Processing Letters 130.] Explains the control/data split and SIMD shuffle decoding in detail.

- #link("https://onlinelibrary.wiley.com/doi/abs/10.1002/spe.948")[Anh & Moffat (2010) — *Index Compression Using 64-Bit Words* (Simple-8b). Software: Practice and Experience 40, 131–147.] Introduces the selector-based 64-bit packing scheme.

- #link("https://www.vldb.org/pvldb/vol15/p3058-liakos.pdf")[Liakos et al. (2022) — *Chimp: Efficient Lossless Floating Point Compression for Time Series Databases*. VLDB 15(11).] Chimp and Chimp128: improvements on Gorilla's XOR scheme.

- #link("https://ir.cwi.nl/pub/33334/33334.pdf")[Afroozeh, Kuffó & Boncz (2024) — *ALP: Adaptive Lossless Floating-Point Compression*. SIGMOD 2024.] The state-of-the-art for float column compression in analytical databases; default in DuckDB.

- #link("https://medium.com/faun/victoriametrics-achieving-better-compression-for-time-series-data-than-gorilla-317bc1f95932")[Valialkin (2020) — *VictoriaMetrics: Achieving Better Compression than Gorilla*.] Practical blog post describing VictoriaMetrics' extensions to Gorilla.

- #link("https://www.mdpi.com/1424-8220/24/22/7273")[Evolving Multivariate Time Series Compression for IoT (Sensors, 2024).] A 2024 survey of compression methods specifically designed for IoT multivariate sensor streams.

- #link("https://prometheus.io/docs/prometheus/1.8/storage/")[Prometheus Storage Documentation] — describes how Prometheus implements Gorilla-style chunks in its TSDB.

#bridge[
  We have now covered four specialized compression domains in Volume V: KV-cache and
  embedding compression (Chapter 65), scientific floating-point compression (Chapter
  66), columnar and database compression (Chapter 67), and in this chapter, time-series
  and IoT compression. The thread connecting all four is the same: knowing the structure
  of your data lets you build a much better model, and a better model means better
  compression. Next, in Chapter 69, we cross from the digital to the biological: genomic
  data, where the "alphabet" is just four letters (A, C, G, T) but the files run to
  hundreds of gigabytes, and the best compressors align reads to a reference genome and
  code only the differences — the same predict-and-code-residual idea, applied to
  molecules.
]
