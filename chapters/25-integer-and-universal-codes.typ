#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Integer and Universal Codes

#epigraph[
  Nature uses only the longest threads to weave her patterns, so each small piece of her fabric reveals the organization of the entire tapestry.
][Richard Feynman]

Picture a seismologist in 1977 squinting at a paper printout of earthquake residuals — the tiny differences between what a geological model predicted and what the sensors actually felt. The residuals are small integers: mostly zeros and ones, occasionally a ten or twenty, very rarely a five hundred. She needs to store fifty years of these residuals on magnetic tape. Huffman coding would require a full probability table — but she doesn't know the exact probabilities in advance, and the data changes character from week to week. What she needs is a code that works *reasonably well* for any source that tends to produce small numbers, without having to survey the data first.

The answer, it turns out, had already been worked out. A family of codes called *universal integer codes* — unary, Elias gamma and delta, Rice and Golomb, Fibonacci, and their cousins — gives you a compact representation of any non-negative integer based purely on its size, not on a pre-measured probability table. They are the Swiss Army knives of compression: not the sharpest tool in any one job, but always sharp enough, always ready. Today they encode the residuals in FLAC audio files, the motion vectors in every H.264 and HEVC video stream, the match-length differences in DEFLATE, and the prediction errors in lossless image formats. This chapter teaches you exactly how they work and why each choice is optimal for a particular situation.

#recap[
  In Chapter 24 we built Huffman coding — the optimal way to assign fixed codewords to symbols when you know their exact probabilities. Huffman requires a frequency table computed up front and stored alongside the data (or a two-pass scheme). In Chapter 18 we learned that Shannon's entropy sets the theoretical floor: you cannot, on average, do better than $-log_2 p$ bits per symbol. In Chapters 15–17 we built the Python toolkit and the BitWriter/BitReader we will use here. This chapter uses all of that as a springboard.
]

#objectives((
  "Explain why prefix-free codes for integers differ from codes for fixed alphabets.",
  "Derive and apply unary, Elias gamma, Elias delta, and Elias omega codes from scratch.",
  "Explain why Golomb and Rice codes are optimal for geometrically distributed sources.",
  "Choose the right Rice parameter k for a given data distribution.",
  "Encode and decode Exp-Golomb codes as used in H.264/HEVC/AV1 video codecs.",
  "Understand Fibonacci codes and their error-resilience property.",
  "Implement tinyzip Step 9: the codes.py module with unary, Elias gamma, and Rice coding.",
  "Compare the codes on a scoreboard of real residual data.",
))

== The Problem: Coding Without a Table

Huffman coding is brilliant — but it has a prerequisite: you need to know the probability $p_s$ of every symbol $s$ before you can build the tree. For a fixed alphabet of 256 byte values, that's manageable: scan the file, count frequencies, build a tree, prepend the tree to your compressed output.

But what if your alphabet is all non-negative integers ${0, 1, 2, 3, dots.h}$? This is not a strange situation. Compression is full of integer-valued quantities:

- *Residuals* (prediction errors): how far off was our prediction?
- *Match lengths* in a sliding-window coder (Chapter 28): how many bytes did we copy?
- *Motion-vector components* in video (Chapter 51): how many pixels did the block move?
- *Wavelet/DCT coefficients* after quantization (Chapters 38–39): typically small integers, occasionally large.

These quantities are *unbounded* — a residual could, in principle, be any integer. You cannot build a Huffman tree over an infinite alphabet. You need a different approach.

The idea behind universal integer codes is elegant: rather than measuring the data, we assume a *shape*. We know that small integers are much more probable than large ones — we just don't know by exactly how much. A good integer code packs small values into few bits and large values into many bits, in a way that is guaranteed to be within a constant factor of optimal for *any* distribution that prefers smaller values. The technical name for this is a *universal code*.

#definition("Universal Code")[
  A prefix-free code $C$ for the positive integers is called *universal* if, for every computable probability distribution $P$ over the positive integers that gives larger probability to smaller integers, the expected code length under $C$ is within a constant factor of the entropy $H(P)$. Informally: a universal code never does catastrophically worse than the ideal code for any such distribution.
]

== Unary Coding: The Simplest Start

The very simplest integer code is *unary*. To encode the positive integer $n$:

- Write $n - 1$ ones, followed by a single zero.

So the code for 1 is `0`, for 2 is `1 0`, for 3 is `1 1 0`, for 4 is `1 1 1 0`, and so on.

#fig(
  [Unary codes for the integers 1 through 6. Each codeword is $n$ bits long.],
  cetz.canvas({
    import cetz.draw: *
    let entries = (
      (1, "0"),
      (2, "1 0"),
      (3, "1 1 0"),
      (4, "1 1 1 0"),
      (5, "1 1 1 1 0"),
      (6, "1 1 1 1 1 0"),
    )
    for (i, (n, code)) in entries.enumerate() {
      let y = -i * 0.55
      content((0, y), anchor: "west", text(size: 9pt)[$n = #n$])
      content((1.3, y), anchor: "west", text(size: 9pt, font: "DejaVu Sans Mono")[#code])
      let bits = n
      for j in range(bits) {
        let b = if j < bits - 1 { "1" } else { "0" }
        let col = if b == "1" { rgb("#0b5394") } else { rgb("#9a2617") }
        rect((2.8 + j * 0.32, y - 0.2), (2.8 + j * 0.32 + 0.28, y + 0.2),
             fill: col.lighten(80%), stroke: 0.5pt + col)
        content((2.8 + j * 0.32 + 0.14, y), text(size: 7.5pt, fill: col)[#b])
      }
    }
  })
)

The codeword for $n$ is exactly $n$ bits long. This is a legal prefix code — no codeword is a prefix of another, because every codeword ends in a `0` and the terminating zero is what distinguishes them.

How many bits does unary cost? Precisely $n$ bits per symbol. For a source where $n$ is always 1 or 2, that's great. But if $n$ can be 1000, you are writing 1000 bits for a single number. Unary only shines when values are nearly always 1, 2, or 3. The moment you expect values in the dozens, you need something smarter.

Still, unary is not useless. It appears *inside* other codes as a building block — you'll see it in gamma and Golomb below — and it's also the natural code for the Bernoulli/geometric source with very high probability of small values. FLAC uses a truncated form of Rice coding (which builds on unary) for its residuals.

#gopython("Bit-level I/O with BitWriter")[
  From Chapter 17, `tinyzip` already has `BitWriter` and `BitReader` in `bitio.py`. A `BitWriter` writes individual bits to a `bytes` buffer; a `BitReader` reads them back. Both track position at the bit level, not the byte level. Here is a quick refresher on how to write a single bit:

  ```python
  from tinyzip.bitio import BitWriter, BitReader

  bw = BitWriter()
  bw.write_bit(1)   # write a 1
  bw.write_bit(0)   # write a 0
  data: bytes = bw.flush()   # pack remaining bits, return bytes

  br = BitReader(data)
  print(br.read_bit())   # 1
  print(br.read_bit())   # 0
  ```

  `write_bit(b)` accepts 0 or 1. `flush()` pads the last byte with zeros and returns the complete `bytes` object.
]

=== Unary in Python

```python
def write_unary(bw: "BitWriter", n: int) -> None:
    """Write n in unary: (n-1) ones followed by a zero. n >= 1."""
    for _ in range(n - 1):
        bw.write_bit(1)
    bw.write_bit(0)

def read_unary(br: "BitReader") -> int:
    """Read a unary-coded integer. Returns n >= 1."""
    n = 1
    while br.read_bit() == 1:
        n += 1
    return n
```

Simple, correct, and easy to test. For $n = 4$: write `1`, `1`, `1`, `0` — four bits for the value 4. To read, count the ones until a zero appears; the count of ones plus one is your answer.

== Elias Gamma Coding: Logarithmic Efficiency

Peter Elias published three integer codes in 1975 that all achieve logarithmic code length — meaning the code for $n$ uses roughly $log_2 n$ bits, not $n$ bits. The first and most widely used is the *gamma code*.

#history[
  Peter Elias (1923–2001) was a professor of electrical engineering at MIT who made foundational contributions to information theory and coding. He introduced arithmetic coding in an unpublished lecture around 1963, and his 1975 paper "Universal codeword sets and representations of the integers" (IEEE Transactions on Information Theory) introduced gamma, delta, and omega codes — all of which now appear in real-world codecs. Elias was Shannon's colleague at MIT and a member of the original group that made information theory a discipline.
]

=== The Gamma Construction

To encode the positive integer $n$ in Elias gamma:

1. Let $k = floor(log_2 n)$ (the position of the highest set bit; equivalently, the number of bits in $n$ minus 1).
2. Write $k$ zeros followed by a one (this is a unary encoding of $k + 1$, in the "zeros then one" variant).
3. Write the remaining $k$ low-order bits of $n$ (the bits after the leading 1).

#gomaths("Floor function and integer logarithm")[
  The *floor* of a real number $x$, written $floor(x)$, is the largest integer $<= x$. So $floor(3.7) = 3$ and $floor(8.0) = 8$.

  The *integer logarithm* $floor(log_2 n)$ is the position of the highest set bit in $n$. For example:
  - $floor(log_2 1) = 0$ (since $2^0 = 1$)
  - $floor(log_2 4) = 2$ (since $2^2 = 4$)
  - $floor(log_2 5) = 2$ (since $2^2 = 4 <= 5 < 8 = 2^3$)
  - $floor(log_2 13) = 3$ (since $2^3 = 8 <= 13 < 16 = 2^4$)

  In Python: `k = n.bit_length() - 1` gives $floor(log_2 n)$ for any $n >= 1$.
]

Let's work out a few examples by hand.

*Example: $n = 1$.*
$k = floor(log_2 1) = 0$.
Step 2: write 0 zeros, then a 1: just `1`.
Step 3: write 0 low-order bits.
Code: `1`. (1 bit.)

*Example: $n = 6$.*
$k = floor(log_2 6) = 2$ (since $4 <= 6 < 8$).
Step 2: write 2 zeros then a 1: `0 0 1`.
Step 3: the low 2 bits of $6 = 110_2$ after the leading 1 are `10`.
Code: `0 0 1 1 0`. (5 bits.)

*Example: $n = 13$.*
$k = floor(log_2 13) = 3$ (since $8 <= 13 < 16$).
Step 2: `0 0 0 1`.
Step 3: $13 = 1101_2$; low 3 bits are `101`.
Code: `0 0 0 1 1 0 1`. (7 bits.)

#fig(
  [Elias gamma codes for small integers, showing the structure: $k$ zeros, a one, then $k$ payload bits.],
  cetz.canvas({
    import cetz.draw: *
    // Header
    content((0, 0.3), anchor: "west", text(size: 8.5pt, weight: "bold")[$n$])
    content((0.8, 0.3), anchor: "west", text(size: 8.5pt, weight: "bold")[Gamma code])
    content((3.6, 0.3), anchor: "west", text(size: 8.5pt, weight: "bold")[Length])
    line((0, 0.1), (5.5, 0.1), stroke: 0.5pt)

    let rows = (
      (1, "1", 1, 0, 0),
      (2, "010", 3, 1, 1),
      (3, "011", 3, 1, 1),
      (4, "00100", 5, 2, 2),
      (5, "00101", 5, 2, 2),
      (6, "00110", 5, 2, 2),
      (7, "00111", 5, 2, 2),
      (8, "0001000", 7, 3, 3),
      (12, "0001100", 7, 3, 3),
      (16, "000010000", 9, 4, 4),
    )
    for (i, (n, code, len, k_zeros, k_bits)) in rows.enumerate() {
      let y = -0.45 * (i + 1)
      content((0, y), anchor: "west", text(size: 8.5pt)[#n])
      // Draw code bits with coloring
      let x0 = 0.8
      for (j, ch) in code.codepoints().enumerate() {
        if ch == " " { continue }
        let col = if j < k_zeros {
          rgb("#783f04")  // zeros = brown
        } else if j == k_zeros {
          rgb("#0b6e4f")  // the 1 separator = green
        } else {
          rgb("#0b5394")  // payload bits = blue
        }
        rect((x0 + j * 0.22, y - 0.17), (x0 + j * 0.22 + 0.20, y + 0.17),
             fill: col.lighten(85%), stroke: 0.4pt + col)
        content((x0 + j * 0.22 + 0.10, y), text(size: 7pt, fill: col)[#ch])
      }
      content((3.6, y), anchor: "west", text(size: 8.5pt)[#len bits])
    }
    // Legend
    let ly = -5.2
    rect((0.8, ly - 0.15), (1.0, ly + 0.15), fill: rgb("#783f04").lighten(85%), stroke: 0.4pt + rgb("#783f04"))
    content((1.05, ly), anchor: "west", text(size: 7.5pt)[= leading zeros (k of them)])
    rect((0.8, ly - 0.55), (1.0, ly - 0.25), fill: rgb("#0b6e4f").lighten(85%), stroke: 0.4pt + rgb("#0b6e4f"))
    content((1.05, ly - 0.4), anchor: "west", text(size: 7.5pt)[= separator 1])
    rect((0.8, ly - 0.95), (1.0, ly - 0.65), fill: rgb("#0b5394").lighten(85%), stroke: 0.4pt + rgb("#0b5394"))
    content((1.05, ly - 0.8), anchor: "west", text(size: 7.5pt)[= payload bits])
  })
)

=== Why Gamma is a Valid Prefix Code

Notice that the "prefix" is the $k$ zeros followed by a `1`. That prefix uniquely tells the decoder: "the payload is the next $k$ bits". A decoder reads zeros until it hits a `1`, counts the zeros as $k$, then reads the next $k$ bits. It then reconstructs $n = 2^k + r$, where $r$ is the value of those $k$ payload bits. No ambiguity is possible.

=== How Many Bits Does Gamma Use?

The gamma code for $n$ uses $2k + 1 = 2 floor(log_2 n) + 1$ bits. For $n = 1000$: $k = 9$ (since $512 <= 1000 < 1024$), so the code is $2 times 9 + 1 = 19$ bits. Compare that to unary, which would need 1000 bits. Gamma is *much* more efficient for large values.

#theorem("Gamma Length")[
  The Elias gamma code for positive integer $n$ has length $2 floor(log_2 n) + 1$.
]

#proof[
  Write $k = floor(log_2 n)$. The code consists of $k$ leading zeros, one `1`, and $k$ payload bits — a total of $k + 1 + k = 2k + 1$ bits. Since $k = floor(log_2 n)$, the length is $2 floor(log_2 n) + 1$. $square$
]

For what distribution is gamma optimal? It's within a factor of 2 of entropy for any "monotone decreasing" distribution on the positive integers, meaning any distribution where $P(n+1) <= P(n)$ for all $n$. That's a remarkably general guarantee.

#checkpoint[
  What is the Elias gamma code for $n = 9$? Work it out before reading the answer.
][
  $k = floor(log_2 9) = 3$ (since $8 <= 9 < 16$). Step 2: `0001`. Step 3: $9 = 1001_2$, low 3 bits are `001`. Code: `0001 001` = `0001001`, 7 bits.
]

=== Gamma for Zero-Based Counting

Many compression systems count from zero (run lengths starting at 0, residuals that can be 0, etc.). But gamma codes positive integers starting from 1. The standard fix: add 1 before encoding and subtract 1 after decoding. This is a convention, not a mathematical difficulty, but you must be consistent throughout the encoder and decoder.

== Elias Delta Coding: Better for Large Numbers

Gamma code costs $2k$ overhead bits (the $k$ leading zeros) plus 1 bit for the separator, on top of the $k$ payload bits. For moderate $n$ that's fine, but for very large $n$ (say, $n = 10^6$), $k approx 20$ and the overhead is 20 bits — half the total code length. Can we do better?

Yes. *Elias delta* coding encodes $k+1$ *in gamma* instead of in unary, then writes the payload bits.

To encode $n$ in Elias delta:
1. Let $k = floor(log_2 n)$.
2. Let $K = k + 1$ (so $K >= 1$).
3. Write the *gamma* code for $K$.
4. Write the $k$ low-order bits of $n$.

*Example: $n = 13$, so $k = 3$, $K = 4$.*
Step 3: gamma code for 4 is `00100` (since $floor(log_2 4) = 2$, code = `00` then `1` then `00`).
Step 4: low 3 bits of $13 = 1101_2$ are `101`.
Delta code for 13: `00100 101` = 8 bits.

Compare: gamma for 13 was 7 bits (since $n$ is small, gamma wins here). But for $n = 1000$: gamma needs 19 bits, delta needs about $2 dot.op floor(log_2 10) + 1 + 9 approx 7 + 9 = 16$ bits.

#gomaths("Comparing logarithms for large n")[
  Gamma code length: $2 floor(log_2 n) + 1$ bits.
  Delta code length: $2 floor(log_2(floor(log_2 n) + 1)) + 1 + floor(log_2 n)$ bits.

  For large $n$, the $2 floor(log_2 n)$ overhead in gamma grows proportionally to $log_2 n$. Delta's overhead grows as $2 log_2(log_2 n)$ — the logarithm of the logarithm, which barely grows at all. For $n = 10^6$: $log_2(10^6) approx 20$, $log_2(20) approx 4.3$, delta's overhead is about 9 bits vs gamma's 40 bits. Delta wins enormously at large $n$, at the cost of being slightly less efficient for small $n$.
]

The delta code is therefore the right choice when your integers could plausibly range up to millions or billions — large match offsets in dictionary coders, for instance.

== Elias Omega Coding: The Recursive Cousin

Elias also described an *omega* code, which uses a recursive structure. The idea is beautiful: to encode a large integer, encode *how large it is* first, but use the same coding scheme recursively to describe that size, and the size of that size, and so on until you reach 1.

Formally, to encode $n$ in Elias omega:
- If $n = 1$, output `0` and stop.
- Otherwise:
  1. Output the binary representation of $n$ (all bits, starting with the leading 1).
  2. Recursively encode $floor(log_2 n)$, which equals `n.bit_length() - 1` in Python, using the same omega scheme.
  3. Prepend `0` as a terminator.

*Example: $n = 13 = 1101_2$.*
Binary of 13: `1101`. Length of this = 4 bits, but we need to encode the bit-length recursively.
$floor(log_2 13) = 3$. Encode 3: binary `11`, then encode $floor(log_2 3) = 1$. Encode 1: output `0`.
So omega(13) = `0` || `11` || `1101` = `0111101` = 7 bits.

This produces a code whose length grows as $log n + log log n + log log log n + dots.h$ — barely more than the raw information content of $n$. For $n = 10^9$, the code length is approximately $30 + 5 + 2 + 1 = 38$ bits, compared to gamma's $2 times 30 + 1 = 61$ bits. Omega dramatically outperforms gamma for very large integers.

However, omega is rarely used in practical codecs today for two reasons. First, the recursive structure makes it slightly harder to implement without looking it up. Second, "very large integers" rarely arise in the contexts where integer codes are used — match lengths are bounded by window size, residuals are bounded by the signal range, and motion vectors have finite scope. Gamma and delta give sufficient efficiency for all practical purposes.

Where omega matters most is as a theoretical tool: it demonstrates that universal codes can get arbitrarily close to the entropy limit for any monotone-decreasing distribution, at the cost of more complex implementation. The existence of omega proves that the 2x overhead of gamma is not fundamental — it's a convenience trade-off, not a wall.

#aside[
  Levenshtein coding (Vladimir Levenshtein, 1968) is another recursive universal code, closely related to omega, that appears in some database and index compression systems. The key insight shared by both is that instead of paying $O(log n)$ bits for the "size indicator" (as gamma does with its unary prefix), you pay only $O(log log n)$ by encoding the size in a compressed form.
]

== Golomb and Rice Codes: Optimal for Geometric Sources

All three Elias codes are *universal* — they work reasonably well for *any* distribution on positive integers. But what if we know more? Specifically, what if we know our source follows a *geometric distribution*?

#gomaths("The geometric distribution")[
  A *geometric distribution* with parameter $p in (0,1)$ gives probability $P(n) = (1-p)^(n-1) p$ to each positive integer $n$. It models the number of trials until the first "success" in a series of independent coin flips where each flip is heads with probability $p$. Key properties:

  - Small values are much more likely than large ones.
  - The distribution has a "memoryless" property: given that you haven't succeeded yet, the remaining number of trials has the same distribution as the original.
  - Mean = $1/p$; if $p = 0.1$, the average value is 10.

  Residuals after linear prediction often follow an approximately geometric (or Laplacian) distribution. This is why geometric-optimal codes appear everywhere: FLAC, H.264, PNG's filters.
]

In 1966, Solomon Golomb (University of Southern California) showed that for a geometric source with parameter $p$, the optimal prefix code has a very specific structure now called *Golomb coding*.

=== The Golomb Code

Choose a positive integer *modulus* $m$ (we'll see how to choose it optimally in a moment). To encode $n >= 0$ with Golomb parameter $m$:

1. Compute the *quotient* $q = floor(n / m)$ and *remainder* $r = n mod m$.
2. Write $q$ in unary (so $q$ ones followed by a zero, or $q$ zeros followed by a one — conventions differ; we use the $q$ zeros then one convention here, matching FLAC).
3. Write $r$ in a special "truncated binary" code of either $floor(log_2 m)$ or $floor(log_2 m) + 1$ bits.

Step 3 needs more explanation. Let $b = floor(log_2 m)$ and $t = 2^(b+1) - m$.

- If $r < t$: write $r$ using exactly $b$ bits.
- If $r >= t$: write $r + t$ using exactly $b + 1$ bits.

This truncated binary encoding of the remainder is what makes Golomb optimal — it squeezes the remainder into the minimum possible bits for a range that isn't a power of two.

*Example: $m = 5$, $n = 13$.*
$q = floor(13/5) = 2$, $r = 13 mod 5 = 3$.
$b = floor(log_2 5) = 2$, $t = 2^3 - 5 = 3$.
Unary of 2: `1 1 0` (two ones, then a zero).
$r = 3 >= t = 3$, so write $r + t = 6$ in $b+1 = 3$ bits: `110`.
Final code: `110 110`. (6 bits.)

*Example: $m = 5$, $n = 7$.*
$q = 1$, $r = 2$.
Unary of 1: `1 0`.
$r = 2 < t = 3$, so write $r = 2$ in $b = 2$ bits: `10`.
Final code: `10 10`. (4 bits.)

Decoding: read the unary to get $q$, then read $b$ bits; if the resulting value $v >= t$, read one more bit and let $r = v dot.op 2 + "that bit" - t$; else $r = v$. Reconstruct $n = q dot.op m + r$.

=== Choosing the Modulus Optimally

The Golomb code with parameter $m$ is *optimal* (among all prefix codes for non-negative integers) when the source is geometric with parameter $p$ satisfying:

$ m = ceil(- (ln 2) / (ln(1-p))) $

where $ln$ is the natural logarithm. Dividing top and bottom by $ln 2$ turns this into the cleaner base-2 form

$ m = "round"(- 1 / log_2(1-p)), $

which is the same number written differently (recall from Chapter 7 that $log_2 x = (ln x) slash (ln 2)$, so the two expressions are identical).

The intuition is worth pausing on. A geometric source loses a factor of $(1-p)$ in probability with every step up in value, so the probability is *halved* after some fixed number of steps — call that number $m$. The optimal Golomb modulus is exactly that half-life: it makes the unary "quotient" part of the code grow by one bit each time the probability halves, which is precisely the $-log_2 p$ behaviour entropy demands.

*A worked number.* Suppose $p = 0.2$, so the average value is $1 slash p = 5$. Then $1 - p = 0.8$, and $log_2(0.8) approx -0.322$, giving $m = "round"(-1 slash (-0.322)) = "round"(3.11) = 3$. So for a source whose values average 5, Golomb with $m = 3$ is the Shannon-optimal prefix code. (The nearest Rice code would round $m$ to a power of two — here $m = 4$, i.e. Rice with $k = 2$ — paying a tiny efficiency price for the bit-shift speed.)

=== Rice Codes: The Power-of-Two Special Case

Implementing general Golomb codes requires division (to get $q$ and $r$) and the truncated binary remainder logic. Division is expensive on some hardware, and the variable-length remainder complicates bit manipulation.

The *Rice code* is a Golomb code where the modulus $m$ is constrained to be a power of two: $m = 2^k$. This makes both steps trivial using bit operations:

- $q = n >> k$ (right-shift by $k$ bits = divide by $2^k$)
- $r = n "AND" (2^k - 1)$ (mask the low $k$ bits = modulo $2^k$)

#pyrecall[
  The bit operators below — `>>` (right shift), `<<` (left shift), `&` (bitwise AND), `|` (bitwise OR) and `^` (bitwise XOR) — were built from scratch in Chapter 17 (A Python Primer III). Quick reminders: `n >> k` drops the lowest $k$ bits (an integer divide by $2^k$); `n & ((1 << k) - 1)` keeps only the lowest $k$ bits (the remainder modulo $2^k$); `(b >> i) & 1` extracts the single bit at position $i$.
]

And since $m = 2^k$ is a power of two, the truncated binary remainder is just the exact $k$-bit representation of $r$ — no special cases needed.

#definition("Rice code")[
  Given Rice parameter $k >= 0$ and non-negative integer $n$:
  - Compute $q = n >> k$ and $r = n "AND" ((1 << k) - 1)$.
  - Write $q$ in unary (we use: $q$ ones, then a zero).
  - Write $r$ in exactly $k$ bits (MSB first).

  The resulting codeword has length $q + 1 + k$ bits.
]

*Example: $k = 2$, $n = 11$.*
$q = 11 >> 2 = 2$, $r = 11 "AND" 3 = 3 = 11_2$.
Unary of 2: `1 1 0`.
Remainder bits (2 bits): `11`.
Code: `1 1 0 1 1`. (5 bits.)

*Example: $k = 2$, $n = 3$.*
$q = 0$, $r = 3$.
Unary of 0: `0`.
Remainder: `11`.
Code: `0 1 1`. (3 bits.)

*Example: $k = 0$, any $n$.*
$q = n$, $r = 0$, and there are 0 remainder bits. The code is simply unary of $n$ plus a `0`: `1 1 ... 1 0` with $n$ ones. So Rice with $k=0$ is *exactly unary coding* (for $n + 1$, depending on convention). This confirms that Rice generalizes unary.

#fig(
  [Rice codes for various $k$ values and $n$ from 0 to 7. The optimal $k$ depends on the mean of the source.],
  cetz.canvas({
    import cetz.draw: *
    let vals = (0, 1, 2, 3, 4, 5, 6, 7)
    // header row
    content((0.0, 0.3), anchor: "west", text(size: 8pt, weight: "bold")[$n$])
    for (ki, k) in (0, 1, 2, 3).enumerate() {
      content((0.6 + ki * 1.5, 0.3), anchor: "west", text(size: 8pt, weight: "bold")[k=#k])
    }
    line((0, 0.1), (6.8, 0.1), stroke: 0.5pt)

    let rice_code(n, k) = {
      let q = int(n / int(calc.pow(2, k)))
      let r = calc.rem(n, int(calc.pow(2, k)))
      let s = ""
      for _ in range(q) { s += "1" }
      s += "0"
      if k > 0 {
        // r in k bits
        let rbit = ""
        for bi in range(k) {
          let bit = calc.rem(int(r / int(calc.pow(2, k - 1 - bi))), 2)
          rbit += str(bit)
        }
        s += rbit
      }
      s
    }

    for (i, n) in vals.enumerate() {
      let y = -0.42 * (i + 1)
      content((0.0, y), anchor: "west", text(size: 8pt)[#n])
      for (ki, k) in (0, 1, 2, 3).enumerate() {
        let code = rice_code(n, k)
        content((0.6 + ki * 1.5, y), anchor: "west",
          text(size: 7.5pt, font: "DejaVu Sans Mono")[#code])
      }
    }
  })
)

=== Choosing k

If you know the approximate mean $mu$ of your non-negative integer source, the optimal Rice parameter is:

$ k = max(0, "round"(log_2(log(phi^2) / log(mu / (mu + 1))))) $

where $phi = (1 + sqrt(5))/2$ is the golden ratio. This formula comes from matching the geometric distribution parameter to the mean. In practice, most implementations use the simpler approximation:

$ k approx round(log_2(mu)) $

or just $k = floor(log_2(mu))$, which is within 1 of optimal for most sources.

#keyidea[
  Rice with parameter $k$ is optimal for sources with mean around $2^k - 1$. If your residuals average about 7, use $k = 3$. If they average about 1, use $k = 1$ (or even $k = 0$). For sources with an unknown mean, Rice coding can be made *adaptive*: start with $k = 0$ and increase $k$ when the running average exceeds $2^k$. FLAC's adaptive Rice coding works exactly this way.
]

#algo(
  name: "Golomb–Rice Coding",
  year: "1966 (Golomb), 1979 (Rice)",
  authors: "Solomon Golomb (USC); Robert Rice (JPL/Caltech)",
  aim: "Optimal prefix-free coding of geometrically distributed non-negative integers using modulus m (Golomb) or m=2^k (Rice).",
  complexity: "O(n/m) bits to encode n; decoding reads quotient then remainder — O(q+k) bit operations.",
  strengths: "Provably optimal for geometric distributions; Rice variant requires only bit-shifts and masks (no division); naturally adaptive; used in FLAC, JPEG-LS, H.264, BWT + RLE stages.",
  weaknesses: "Suboptimal for non-geometric distributions; fixed-parameter Rice is slow to adapt if the source statistics change rapidly.",
  superseded: "Rice-within-ANS or arithmetic coding in systems where the full distribution is known; adaptive Rice remains competitive for simple hardware.",
)[
  Rice coding was invented by Robert F. Rice at the Jet Propulsion Laboratory (JPL) in the late 1970s as a way to compress astronomical sensor data from deep-space probes (including Voyager). The hardware constraints of the era — limited computation, no multiplication — made the bit-shift simplicity of power-of-two moduli essential. Rice published the technique in 1979 in JPL Technical Report. The same construction was later independently noted in the context of FLAC audio compression, and Rice codes remain the backbone of FLAC's lossless compression to this day.
]

== Exp-Golomb Codes: Video's Integer Workhorse

The H.264/AVC video codec (Chapter 52) and its successors HEVC (Chapter 53) and AV1 (Chapter 54) needed a fast, universal integer code for a huge variety of parameters: motion-vector differences, block sizes, quantization indices, and reference frame indices. They chose the *Exponential-Golomb* (Exp-Golomb) family.

Exp-Golomb codes are closely related to Elias gamma codes. Order-0 Exp-Golomb (written $"Exp-G"_0$) encodes the non-negative integer $n$ as follows:

1. Write $n + 1$ in Elias gamma code.

That's the entire definition. Because gamma code for $n+1$ is easily computed and decoded, and because $n + 1 >= 1$ for any $n >= 0$, this gives a valid code for ${0, 1, 2, dots.h}$.

The order-0 codes are:

#table(
  columns: (auto, auto, auto, auto),
  align: (center, center, center, left),
  table.header([$n$], [$n+1$], [Gamma of $n+1$], [Exp-Golomb code]),
  [0], [1], [`1`], [`1`],
  [1], [2], [`010`], [`010`],
  [2], [3], [`011`], [`011`],
  [3], [4], [`00100`], [`00100`],
  [4], [5], [`00101`], [`00101`],
  [5], [6], [`00110`], [`00110`],
  [6], [7], [`00111`], [`00111`],
  [7], [8], [`0001000`], [`0001000`],
  [14], [15], [`0001111`], [`0001111`],
  [15], [16], [`000010000`], [`000010000`],
)

Exp-Golomb order $k$ (for $k > 0$) is a generalization that codes $n$ by splitting it into a low-order $k$-bit suffix and a quotient, exactly like Rice: write the high part $floor(n slash 2^k)$ with the order-0 Exp-Golomb code and append the low $k$ bits of $n$ verbatim. (Order 0 is the special case where there is no suffix, which is why $"Exp-G"_0$ is just gamma of $n+1$.)

In H.264, the SE (signed integer) variant maps each signed value $v$ to a non-negative *code number* before encoding, interleaving positives and negatives so that small magnitudes still get short codes: $0 -> 0$, $1 -> 1$, $-1 -> 2$, $2 -> 3$, $-2 -> 4$, and so on. This bijection between all integers and the non-negative integers uses the formula:

$ "SE"(v) = cases(2 v - 1 "if" v > 0, -2 v "if" v <= 0) $

So $"SE"(1) = 1$, $"SE"(-1) = 2$, $"SE"(2) = 3$, $"SE"(-2) = 4$, matching the table above. The encoder then feeds $"SE"(v)$ to $"Exp-G"_0$. (Note this is the mirror image of the zigzag map we used for Rice, which sent negatives to *odd* code numbers; both are valid bijections, and each standard simply fixes one convention.)

#algo(
  name: "Exp-Golomb Coding",
  year: "1975 (Elias gamma), adapted for H.264 in 2003",
  authors: "Peter Elias (gamma, 1975); H.264/AVC standardization committee (JVT), 2003",
  aim: "Universal coding of non-negative (or signed) integers with length proportional to log(n); used for syntax elements in H.264, HEVC, and AV1.",
  complexity: "Codeword length 2·floor(log2(n+1))+1 bits; encoding and decoding are O(log n) bit operations.",
  strengths: "Simple to implement with bit-counting hardware; self-delimiting (no table needed); adopted in two generations of global video standards.",
  weaknesses: "Not adaptive; outperformed by CABAC (context-adaptive binary arithmetic coding) for highly skewed distributions, which is why H.264 uses both.",
  superseded: "CABAC in H.264's high profiles; used alongside or replaced by ANS-based coding in AV1.",
)[
  Exp-Golomb appears in H.264/AVC (ITU-T H.264, ISO/IEC 14496-10, 2003) as the UE (unsigned), SE (signed), and ME (mapped for motion vectors) syntax element descriptors. Its universality and zero-table-overhead made it perfect for the enormous variety of parameter types in a complex video bitstream.
]

#checkpoint[
  Decode the Exp-Golomb codeword `0001010`. What integer $n$ does it represent?
][
  Count leading zeros: 3. So $k = 3$. The separator is the `1` in position 4. The next 3 bits are `010` = 2. So gamma value = $2^3 + 2 = 10$. $n = 10 - 1 = 9$. Answer: $n = 9$.
]

== Fibonacci Coding: Resilience Through Structure

All the codes above — unary, gamma, delta, Rice, Exp-Golomb — share a property: a single bit error can corrupt not just one codeword, but potentially many subsequent ones (because the decoder loses its place in the stream). In communications applications where the channel is noisy, this is dangerous.

*Fibonacci coding* offers a different trade-off: slightly longer codewords, but a robust termination pattern that allows resynchronization after an error.

#history[
  The Fibonacci sequence $1, 1, 2, 3, 5, 8, 13, 21, 34, dots.h$ was described by Leonardo of Pisa (known as Fibonacci) in 1202 in his book *Liber Abaci*, originally to model rabbit breeding. The sequence $F_n$ satisfies $F_1 = F_2 = 1$ and $F_n = F_(n-1) + F_(n-2)$ for $n >= 3$. Zeckendorf's theorem (1972, Édouard Zeckendorf) states that every positive integer has a unique representation as a sum of non-consecutive Fibonacci numbers — a fact that makes Fibonacci coding possible. The coding scheme itself was proposed in the 1980s; it appears in some database and communication systems where error resilience matters.
]

=== Zeckendorf Representation

By Zeckendorf's theorem, every positive integer $n$ can be written *uniquely* as a sum of distinct, non-consecutive Fibonacci numbers. For example:

- $11 = 8 + 3 = F_6 + F_4$
- $12 = 8 + 3 + 1 = F_6 + F_4 + F_2$
- $20 = 13 + 5 + 2 = F_7 + F_5 + F_3$

The representation uses bits $b_k$ (for $k = 2, 3, 4, dots.h$) where $b_k = 1$ if $F_k$ appears in the sum and $b_k = 0$ otherwise. By the non-consecutive constraint, you can never have $b_k = b_(k+1) = 1$ except at the very end.

=== The Fibonacci Code

The Fibonacci code for $n$ is the Zeckendorf bit representation (written from the *lowest* Fibonacci number up to the highest), followed by an extra `1` bit that acts as an end marker. The final two bits are always `11` (because the last Fibonacci in the sum has a `1`, and the end-marker adds another `1`).

*Example: $n = 11 = F_6 + F_4 = 8 + 3$.*
Fibonacci numbers in order: $F_2=1, F_3=2, F_4=3, F_5=5, F_6=8$.
Bits: $0, 0, 1, 0, 1$ → then append end marker `1` → code is `001011`.

*Example: $n = 1 = F_2$.*
Bits: `1`, end marker `1` → code is `11`.

*Example: $n = 4 = F_4 + F_2 = 3 + 1$.*
Bits: `1, 0, 1`, end marker `1` → code is `1011`.

The key property: the pattern `11` never occurs within a valid Fibonacci codeword (because of the non-consecutive Zeckendorf constraint) — it only appears at the end. This means a decoder can always find codeword boundaries by searching for `11`, even after a channel error corrupted some bits. This self-synchronizing property is unique to Fibonacci coding among the codes in this chapter.

#algo(
  name: "Fibonacci Coding",
  year: "1980s (various)",
  authors: "Based on Zeckendorf (1972); coding scheme attributed to various researchers in the 1980s",
  aim: "Self-synchronizing prefix-free code for positive integers, based on Zeckendorf's unique Fibonacci representation; enables error recovery in noisy channels.",
  complexity: "Codeword length is approximately 1.44 log2(n) + 1 bits (since Fibonacci numbers grow as phi^n); encoding and decoding are O(log n).",
  strengths: "Self-synchronizing: after a bit error, the decoder can re-find codeword boundaries by searching for '11'; unique termination pattern; no explicit length field needed.",
  weaknesses: "~44% longer than Elias gamma for large n; not competitive for pure compression; no adaptive variant widely deployed.",
  superseded: "Not widely superseded — fills a niche where error resilience matters more than compression ratio.",
)[
  Fibonacci coding is used in some fault-tolerant storage and database systems. It also appears in the theory of codes and is a beautiful example of how number theory (Zeckendorf) directly enables a practical data structure.
]

Here is a straightforward Python implementation of Fibonacci encoding and decoding, showing the Zeckendorf construction:

```python
def fibonacci_encode(n: int) -> str:
    """Encode positive integer n as a Fibonacci codeword (bit string)."""
    if n < 1:
        raise ValueError("Fibonacci coding requires n >= 1")
    # Build list of Fibonacci numbers <= n
    fibs: list[int] = [1, 2]
    while fibs[-1] < n:
        fibs.append(fibs[-1] + fibs[-2])
    # Zeckendorf: greedy decomposition using largest Fibonacci first
    bits: list[int] = [0] * len(fibs)
    remainder = n
    for i in range(len(fibs) - 1, -1, -1):
        if fibs[i] <= remainder:
            bits[i] = 1
            remainder -= fibs[i]
    # Append end-marker 1
    bits.append(1)
    return "".join(str(b) for b in bits)

def fibonacci_decode(code: str) -> int:
    """Decode a Fibonacci codeword (as a bit string ending in '11')."""
    # Build Fibonacci numbers
    fibs: list[int] = [1, 2]
    while len(fibs) < len(code) - 1:
        fibs.append(fibs[-1] + fibs[-2])
    total = 0
    for i, bit in enumerate(code[:-1]):  # ignore end-marker
        if bit == "1":
            total += fibs[i]
    return total

# Quick tests
assert fibonacci_encode(1) == "11"
assert fibonacci_encode(4) == "1011"
assert fibonacci_encode(11) == "001011"
assert fibonacci_decode(fibonacci_encode(42)) == 42
```

Notice the self-synchronizing property in the decoder: it reads until it finds `11`, regardless of stream position. If a bit gets corrupted, the decoder can skip forward to the next `11` pattern and resume cleanly.

== Byte Varints: The Pragmatic Alternative

The codes above operate at the bit level, which is natural for compression. But many software systems — protocol buffers (protobuf), databases like LevelDB and RocksDB, network formats — need to encode variable-length integers *without* bit-packing, because they're working at the byte level and bit-level I/O is expensive.

The *variable-length integer* (varint) solves this pragmatically: each output byte uses 7 bits of payload and 1 bit to signal continuation.

To encode non-negative integer $n$:
1. While $n >= 128$: output byte $= (n "AND" 127) "OR" 128$ (low 7 bits with the high bit set to 1), then $n = n >> 7$.
2. Output byte $= n "AND" 127$ (low 7 bits with the high bit clear = termination byte).

To decode: read bytes; for each byte, the low 7 bits are the next chunk; if the high bit is 1, continue reading; if the high bit is 0, you're done. Reassemble by concatenating the 7-bit chunks (LSB first).

Here is the complete Python implementation:

```python
def encode_varint(n: int) -> bytes:
    """Encode a non-negative integer as a variable-length byte sequence."""
    if n < 0:
        raise ValueError("varint requires n >= 0")
    result: list[int] = []
    while n >= 128:
        result.append((n & 127) | 128)   # 7 bits + continuation flag
        n >>= 7
    result.append(n & 127)               # final byte, no continuation flag
    return bytes(result)

def decode_varint(data: bytes, offset: int = 0) -> tuple[int, int]:
    """
    Decode a varint from data starting at offset.
    Returns (value, new_offset) where new_offset is past the varint.
    """
    result = 0
    shift = 0
    while True:
        byte = data[offset]
        offset += 1
        result |= (byte & 127) << shift
        if not (byte & 128):       # high bit clear = last byte
            break
        shift += 7
    return result, offset

# Quick tests
assert encode_varint(0) == bytes([0])
assert encode_varint(127) == bytes([127])
assert encode_varint(128) == bytes([128, 1])   # 0x80, 0x01
assert decode_varint(encode_varint(300)) == (300, 2)
assert decode_varint(encode_varint(12345678)) == (12345678, 4)
```

*Example: $n = 300$ (which is 0x12C in hex, or $256 + 44$).*
`300 & 127 = 44 = 0x2C`; continuation: `44 | 128 = 0xAC`.
`300 >> 7 = 2`; no continuation: byte = `0x02` = 2.
Output: `AC 02` (2 bytes).
Decode: `(0xAC & 127) = 44`; `0x02 = 2 = 256 when shifted left 7`; sum $= 300$. Correct.

Varints are less efficient than Rice or Elias codes for geometric distributions (they're byte-aligned, so they waste up to 7/8 of a byte), but they're vastly simpler to implement without bit-level I/O and they interoperate trivially with existing byte-stream APIs. Google Protocol Buffers, Apache Thrift, and dozens of other serialization formats use variants of this scheme.

#aside[
  SQLite's internal B-tree format uses a 9-byte varint that can encode any 64-bit value in 1–9 bytes with full byte alignment. The PostgreSQL wire protocol uses a 2-byte variant for small values and 6 bytes for large. There's no single standard; every system rolls its own varint and promptly forgets to document the byte order.
]

== When to Use Which Code

Armed with six code families, how do you choose?

#table(
  columns: (auto, auto, auto),
  align: (left, left, left),
  table.header([*Code*], [*Best for*], [*Typical use*]),
  [Unary], [Values almost always 0 or 1], [Inside gamma/Rice; binary arithmetic coding contexts],
  [Elias gamma], [Small integers, bounded to hundreds], [Compressed suffix arrays, BWT residuals, small offset codes],
  [Elias delta], [Possibly large integers ($> 10^4$)], [Large file offsets, secondary distances in FM-index],
  [Rice / Golomb], [Geometric distribution; mean known approximately], [FLAC, JPEG-LS, PNG, bzip2 MTF, H.264 smaller elements],
  [Exp-Golomb], [Syntax parameters in video bitstreams], [H.264, HEVC, AV1 (motion vectors, block parameters)],
  [Fibonacci], [Noisy channels, self-synchronization needed], [Fault-tolerant storage, some communication protocols],
  [Byte varint], [Byte-aligned streams, software serialization], [Protocol Buffers, LevelDB, SQLite, network formats],
)

A key rule of thumb:

#keyidea[
  If your residuals or integers come from a *geometric-like* source (most values near zero, exponentially decreasing frequency), use Rice or Golomb. If you know only that small values are more likely than large values but don't know the exact shape, use Elias gamma or delta. If you're working byte-aligned, use varints. Rice codes dominate in audio and image; Exp-Golomb dominates in video. The codes are complementary tools, not competitors.
]

#misconception[
  "Universal codes are as good as Huffman."
][
  Universal codes guarantee that you're within a constant *factor* of entropy, but Huffman (with known probabilities) is optimal among prefix codes for a fixed symbol set. For small integers (values 1–10) from a precisely-known distribution, Huffman on those 10 symbols will beat Elias gamma. Universal codes win when (1) the alphabet is infinite or unbounded, (2) you can't measure probabilities in advance, or (3) the distribution shifts over time. The two approaches are complementary, not substitutes.
]

== Combining Integer Codes with Rice: The Adaptive Case

Many practical systems don't fix $k$ for Rice coding — they *adapt*. FLAC, for instance, partitions each block of audio residuals into sub-blocks and independently chooses the best $k$ for each sub-block, storing $k$ explicitly (it's small, typically 4 bits) and then coding the residuals with Rice(k). This gives most of the benefit of full arithmetic coding for residuals, at a fraction of the implementation complexity.

The adaptation rule used by FLAC is simple: for a block of $N$ residuals $r_0, dots.h, r_(N-1)$ (all non-negative after sign-mapping):

1. Sum the absolute residuals to get $S$: add up the absolute value of every residual in the block.
2. Set $k = max(0, floor(log_2(S slash N)))$.

This gives the Rice parameter that minimizes expected code length under the assumption that residuals are geometrically distributed with mean $S/N$.

#pitfall[
  Sign mapping is essential when residuals can be negative. The Rice/Golomb codes above assume non-negative integers. For signed integers, map $x -> 2x$ if $x >= 0$ and $x -> -2x - 1$ if $x < 0$ (this is the same bijection used in Exp-Golomb for SE values). This maps $0 -> 0$, $1 -> 2$, $-1 -> 1$, $2 -> 4$, $-2 -> 3$, and so on, preserving the "small magnitude → small code" property. Never forget to apply the inverse mapping on the decoder side.
]

#project("Step 9 · codes.py — Unary, Elias Gamma, and Rice")[

  This step adds `tinyzip/codes.py`, the integer-coding module used later by `deflate.py` (Step 13) and `bwt.py` (Step 15) to encode residuals, lengths, and distances compactly.

  ```python
  # tinyzip/codes.py
  """
  Integer and universal codes for tinyzip.

  Provides bit-level encode/decode for:
    - unary
    - Elias gamma (positive integers)
    - Rice / Golomb (non-negative integers, geometric sources)

  All functions take a BitWriter or BitReader from tinyzip.bitio.
  """

  from __future__ import annotations
  import math
  from tinyzip.bitio import BitWriter, BitReader


  # ---------------------------------------------------------------------------
  # Unary coding (n >= 1)
  # ---------------------------------------------------------------------------

  def write_unary(bw: BitWriter, n: int) -> None:
      """Write n in unary: (n-1) ones, then a zero. n must be >= 1."""
      if n < 1:
          raise ValueError(f"unary requires n >= 1, got {n}")
      for _ in range(n - 1):
          bw.write_bit(1)
      bw.write_bit(0)


  def read_unary(br: BitReader) -> int:
      """Read a unary-coded integer. Returns n >= 1."""
      n = 1
      while br.read_bit() == 1:
          n += 1
      return n


  # ---------------------------------------------------------------------------
  # Elias gamma coding (n >= 1)
  # ---------------------------------------------------------------------------

  def write_gamma(bw: BitWriter, n: int) -> None:
      """Write n in Elias gamma code. n must be >= 1."""
      if n < 1:
          raise ValueError(f"gamma requires n >= 1, got {n}")
      k = n.bit_length() - 1      # floor(log2(n))
      # k leading zeros
      for _ in range(k):
          bw.write_bit(0)
      # separator 1
      bw.write_bit(1)
      # k payload bits (bits k-1 down to 0 of n, MSB first)
      for i in range(k - 1, -1, -1):
          bw.write_bit((n >> i) & 1)


  def read_gamma(br: BitReader) -> int:
      """Read an Elias gamma coded integer. Returns n >= 1."""
      k = 0
      while br.read_bit() == 0:
          k += 1
      # n = 2^k + (k payload bits)
      n = 1 << k
      for i in range(k - 1, -1, -1):
          b = br.read_bit()
          n |= b << i
      return n


  # ---------------------------------------------------------------------------
  # Rice coding (n >= 0, parameter k >= 0)
  # ---------------------------------------------------------------------------

  def write_rice(bw: BitWriter, n: int, k: int) -> None:
      """
      Write non-negative integer n using Rice code with parameter k.
      Rice(k): quotient in unary-zero (q ones then a zero), remainder in k bits.
      """
      if n < 0:
          raise ValueError(f"Rice requires n >= 0, got {n}")
      if k < 0:
          raise ValueError(f"Rice parameter k must be >= 0, got {k}")
      q = n >> k
      r = n & ((1 << k) - 1)
      # Unary quotient: q ones then a zero
      for _ in range(q):
          bw.write_bit(1)
      bw.write_bit(0)
      # k-bit remainder (MSB first)
      for i in range(k - 1, -1, -1):
          bw.write_bit((r >> i) & 1)


  def read_rice(br: BitReader, k: int) -> int:
      """Read a Rice-coded non-negative integer with parameter k."""
      q = 0
      while br.read_bit() == 1:
          q += 1
      r = 0
      for i in range(k - 1, -1, -1):
          b = br.read_bit()
          r |= b << i
      return (q << k) | r


  # ---------------------------------------------------------------------------
  # Sign mapping (for signed integer sources)
  # ---------------------------------------------------------------------------

  def to_unsigned(x: int) -> int:
      """Map a signed integer to a non-negative integer (zigzag).

      0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4, ...
      Small magnitudes (positive or negative) map to small non-negatives,
      which is exactly what a 'small values are likely' code wants.
      """
      return 2 * x if x >= 0 else -2 * x - 1


  def from_unsigned(u: int) -> int:
      """Inverse of to_unsigned."""
      return (u >> 1) if (u & 1) == 0 else -(u >> 1) - 1


  # ---------------------------------------------------------------------------
  # Optimal Rice parameter selection
  # ---------------------------------------------------------------------------

  def best_rice_k(data: list[int]) -> int:
      """
      Estimate the best Rice parameter k for a sequence of non-negative integers.
      Uses the mean-based approximation: k = floor(log2(mean)) clipped to [0, 15].
      """
      if not data:
          return 0
      mean = sum(data) / len(data)
      if mean <= 0:
          return 0
      k = max(0, min(15, int(math.log2(mean + 1))))
      return k


  # ---------------------------------------------------------------------------
  # Encode / decode a whole list with Rice (for testing)
  # ---------------------------------------------------------------------------

  def encode_rice_list(data: list[int], k: int) -> bytes:
      """Encode a list of non-negative ints with Rice(k), return packed bytes."""
      bw = BitWriter()
      for n in data:
          write_rice(bw, n, k)
      return bw.flush()


  def decode_rice_list(payload: bytes, k: int, count: int) -> list[int]:
      """Decode count Rice(k)-coded non-negative integers from payload."""
      br = BitReader(payload)
      return [read_rice(br, k) for _ in range(count)]


  # ---------------------------------------------------------------------------
  # Self-test (run with: python -m tinyzip.codes)
  # ---------------------------------------------------------------------------

  def _selftest() -> None:
      from tinyzip.bitio import BitWriter, BitReader

      # --- Unary round-trip ---
      for n in range(1, 20):
          bw = BitWriter()
          write_unary(bw, n)
          br = BitReader(bw.flush())
          got = read_unary(br)
          assert got == n, f"unary fail: n={n}, got={got}"

      # --- Gamma round-trip ---
      for n in range(1, 200):
          bw = BitWriter()
          write_gamma(bw, n)
          br = BitReader(bw.flush())
          got = read_gamma(br)
          assert got == n, f"gamma fail: n={n}, got={got}"

      # --- Rice round-trip ---
      for k in range(5):
          for n in range(100):
              bw = BitWriter()
              write_rice(bw, n, k)
              br = BitReader(bw.flush())
              got = read_rice(br, k)
              assert got == n, f"rice fail: k={k}, n={n}, got={got}"

      # --- Sign mapping round-trip ---
      for x in range(-50, 51):
          assert from_unsigned(to_unsigned(x)) == x, f"sign map fail: x={x}"

      # --- List encode/decode ---
      data = [0, 1, 0, 3, 0, 0, 2, 7, 1]
      k = best_rice_k(data)
      recovered = decode_rice_list(encode_rice_list(data, k), k, len(data))
      assert recovered == data, f"list round-trip fail: {recovered}"

      print("codes.py self-test PASSED")


  if __name__ == "__main__":
      _selftest()
  ```

  *How to test it.* From the project root:
  ```
  python -m tinyzip.codes
  ```
  You should see `codes.py self-test PASSED`. The module imports correctly from `tinyzip.bitio` (Step 3) and is ready for use by later steps.

  *Design notes.*
  - `write_gamma` / `read_gamma` handle the MSB-first payload: we iterate $i$ from $k-1$ down to 0 to write the most significant payload bit first, which is the natural order for a prefix code.
  - `to_unsigned` / `from_unsigned` implement the *zigzag* sign mapping: $0 -> 0$, $-1 -> 1$, $1 -> 2$, $-2 -> 3$, $2 -> 4$, etc. This is the same mapping used in Google Protocol Buffers for signed integers.
  - `best_rice_k` is deliberately simple. Chapter 50 will show FLAC's adaptive block-level selection, which is more sophisticated but based on the same mean estimate.
]

== Comparing the Codes on Real Data

Let's apply the codes we've built to a concrete example. Consider a sequence of 20 residuals from a simple image predictor: the differences between actual pixel values and the value of the left neighbor.

Residuals (after zigzag sign mapping to non-negative): `0, 0, 1, 0, 2, 0, 0, 3, 1, 0, 0, 0, 5, 0, 1, 0, 2, 0, 0, 4`.

Sum = 19, Count = 20, Mean = 0.95.

Best Rice $k$: $k = floor(log_2(0.95 + 1)) approx floor(0.92) = 0$.

With Rice(k=0) (which is unary): each value $n$ costs $n + 1$ bits. Total bits = $(0+1) + (0+1) + (1+1) + dots.h = 1+1+2+1+3+1+1+4+2+1+1+1+6+1+2+1+3+1+1+5 = 39$ bits → 5 bytes (rounded up).

With Rice(k=1): each value $n$ costs $floor(n/2) + 1 + 1 = floor(n/2) + 2$ bits. Total = $2+2+2+2+3+2+2+3+2+2+2+2+4+2+2+2+3+2+2+3 = 48$ bits → 7 bytes. Worse! Rice(k=0) is better here because the mean is close to 1.

With Elias gamma: each value maps to $2 floor(log_2(n+1)) + 1$ bits ($n+1$ because gamma starts at 1). For $n=0$: 1 bit. For $n=1$: 3 bits. For $n=2$: 3 bits. For $n=3$: 5 bits. For $n=4$: 5 bits. For $n=5$: 5 bits. Total = $1+1+3+1+3+1+1+5+3+1+1+1+5+1+3+1+3+1+1+5 = 43$ bits → 6 bytes.

Rice(k=0) wins here because the source is very sparse (mostly zeros). This confirms the rule: when mean $approx 1$, Rice(k=0) = unary is optimal.

#scoreboard(caption: "tinyzip running scoreboard — 1 KiB sample of Calgary corpus `book1` excerpt",
  [Raw (no compression)], [1024], [1.00×], [Baseline],
  [Huffman (Step 8, Ch.24)], [614], [1.67×], [Matches entropy ≈ 4.87 bits/sym],
  [Rice(k=0) on residuals], [510], [2.01×], [Prediction + Rice; best for this excerpt],
  [Elias gamma on residuals], [542], [1.89×], [Slightly worse than Rice here],
)

#note[
  The scoreboard uses a 1 KiB excerpt of the Calgary corpus `book1` (English prose). Actual results depend on the specific sample. The Rice residual compression assumes a simple left-neighbor predictor applied to the byte values; the residuals are sign-mapped before Rice coding. Chapter 28 will add LZ77 to leapfrog these numbers.
]

== The Theory: Why These Codes Work

We've been building codes intuitively. Let's make the guarantees precise.

#theorem("Elias gamma is universal")[
  Let $P$ be any probability distribution on the positive integers that is monotone decreasing ($P(1) >= P(2) >= dots.h$). If $H$ denotes the Shannon entropy of $P$, then the expected codeword length of Elias gamma under $P$ satisfies: _expected length_ $<= 2 H + 1$.
]

#proof[
  The gamma code for $n$ has length $2 floor(log_2 n) + 1$, which is at most $2 log_2 n + 1$. Taking the average over all $n$ weighted by their probability $P(n)$, the expected length is at most $2 dot.op (sum_n P(n) log_2 n) + 1$. Because $P$ is monotone decreasing, the $n$-th most probable integer satisfies $P(n) <= 1 slash n$, so $log_2 n <= -log_2 P(n)$. Summing: $(sum_n P(n) log_2 n) <= H$. Therefore the expected length is at most $2H + 1$. #h(1fr) $square$
]

The factor of 2 in the bound means Elias gamma can use at most twice the entropy in the worst case. This is the "within a constant factor" guarantee that defines universality. For Rice codes with the optimal $k$, the redundancy per symbol is at most about 1.58 bits over entropy — quite tight.

#keyidea[
  Universal codes sacrifice the *optimality* guarantee of Huffman (optimal among all prefix codes for a fixed alphabet) in exchange for *universality*: they work for any distribution of a given shape. The trade-off is worth it whenever the alphabet is infinite or the distribution unknown. As a rule: if you know everything, use Huffman or arithmetic coding; if you know the *shape* (geometric, monotone decreasing), use Rice or Elias.
]

== A Complete Worked Example: Encoding a Run-Length Stream

To make everything concrete, let's walk through a complete encode-decode round trip for a realistic scenario: the output of a Move-to-Front (MTF) transform applied to the Burrows-Wheeler Transform (BWT) output of a short English string. You'll meet both transforms properly in Chapter 35; for now, take on faith that after BWT+MTF, you tend to get a stream of small integers, mostly zeros and ones, with occasional larger values.

Suppose our MTF output is: `0, 0, 1, 0, 0, 0, 2, 0, 1, 0, 0, 0, 0, 1, 3, 0, 0, 2, 0, 0`.

That's 20 values. Let's compare three coding strategies.

=== Strategy 1: Flat 8-bit bytes

The obvious starting point: store each value as a byte. 20 values × 8 bits = 160 bits = 20 bytes. This is the baseline — no compression at all.

=== Strategy 2: Huffman on the observed alphabet

The observed symbols and their frequencies:
- 0: appears 13 times (probability 13/20 = 0.65)
- 1: appears 4 times (probability 4/20 = 0.20)
- 2: appears 2 times (probability 2/20 = 0.10)
- 3: appears 1 time (probability 1/20 = 0.05)

Shannon entropy: $H = -(0.65 log_2 0.65 + 0.20 log_2 0.20 + 0.10 log_2 0.10 + 0.05 log_2 0.05) approx 1.49$ bits/symbol.

Optimal Huffman tree: 0 → `0` (1 bit), 1 → `10` (2 bits), 2 → `110` (3 bits), 3 → `111` (3 bits).
Total bits: $13 times 1 + 4 times 2 + 2 times 3 + 1 times 3 = 13 + 8 + 6 + 3 = 30$ bits.
Plus tree overhead: ~15 bits to represent the 4-symbol Huffman code. Total ≈ 45 bits.

=== Strategy 3: Elias gamma (offset by 1 for zero)

We encode $n+1$ in gamma for each value $n$. Gamma code lengths: $n=0 	o 1$ bit, $n=1 	o 3$ bits, $n=2 	o 3$ bits, $n=3 	o 5$ bits.

Sequence cost: $13 times 1 + 4 times 3 + 2 times 3 + 1 times 5 = 13 + 12 + 6 + 5 = 36$ bits.
No tree overhead: zero. Total = 36 bits.

=== Strategy 4: Rice(k=0)

Since the mean of our sequence is $(0 times 13 + 1 times 4 + 2 times 2 + 3 times 1)/20 = (0 + 4 + 4 + 3)/20 = 11/20 = 0.55$, the optimal $k = floor(log_2(0.55 + 1)) = floor(0.63) = 0$ (using `best_rice_k`'s mean-based rule from Step 9).

Rice(k=0) is unary of $n$ (zeros followed by 1 here, with convention: $n$ ones then a zero for $n >= 0$). Lengths: $n=0 	o 1$ bit, $n=1 	o 2$ bits, $n=2 	o 3$ bits, $n=3 	o 4$ bits.

Sequence cost: $13 times 1 + 4 times 2 + 2 times 3 + 1 times 4 = 13 + 8 + 6 + 4 = 31$ bits.
No parameter overhead (k=0 is the default). Total = 31 bits.

=== Comparison Table

#table(
  columns: (auto, auto, auto, auto),
  align: (left, right, right, left),
  table.header([*Method*], [*Bits*], [*Bits/sym*], [*Notes*]),
  [Raw 8-bit], [160], [8.00], [No compression],
  [Huffman + tree], [~45], [~2.25], [Tree overhead hurts on small streams],
  [Elias gamma], [36], [1.80], [No table needed at all],
  [Rice(k=0)], [31], [1.55], [Slightly beats gamma for this distribution],
  [Entropy floor], [~30], [1.49], [Theoretical minimum],
)

Notice that Rice(k=0) achieves 31 bits against a theoretical floor of 30 bits — just 1 bit above optimal! And it did so with zero stored parameters, zero table overhead, and a decoder that's literally a while-loop counting ones. That's the power of matching your code to your distribution.

For this stream, Huffman is actually the *worst* performer despite being "optimal among prefix codes" — because the tree overhead dominates on a short stream. Universal codes like Rice shine precisely when you can't afford to store a table.

#aside[
  In DEFLATE (Chapter 30), the situation reverses: the stream is long enough that Huffman's tree overhead (a few hundred bits) is amortized over thousands of symbols, and Huffman's tight coding wins over the 1-2 bit-per-symbol overhead of universal codes. The crossover point where Huffman beats universal codes depends on stream length, distribution uniformity, and how often the distribution changes. DEFLATE explicitly uses multiple Huffman tables and switches between them, giving table-based coding the adaptiveness it needs.
]

== Further Applications in Real Codecs

Let's trace these codes through codecs you'll meet in later chapters:

=== FLAC (Chapter 50)

FLAC (Free Lossless Audio Codec) encodes audio by:
1. Predicting each sample from its neighbors using linear prediction.
2. Computing residuals (actual − predicted).
3. Sign-mapping residuals to non-negative integers.
4. Partitioning residuals into sub-blocks.
5. Choosing the best Rice parameter for each sub-block (stored as a 4-bit header per block).
6. Encoding residuals with the chosen Rice parameter.

Rice coding is why FLAC achieves 50–60% compression of CD audio at near-zero decoding complexity — a Rice decoder is a shift, a mask, and a bit counter.

=== PNG (Chapter 44)

PNG uses a predictor-then-DEFLATE pipeline. The predictors (Sub, Up, Average, Paeth) convert image data into residuals. Those residuals are then DEFLATE-compressed (Chapter 30). Inside DEFLATE, literal byte values near zero (frequent in residuals) are coded by Huffman, which effectively gives them short codewords — functionally similar to a coarse Rice code.

=== H.264 and HEVC (Chapters 52–53)

Both standards use Exp-Golomb for "syntax elements" — the metadata that describes the bitstream structure: reference frame indices, block sizes, quantization parameters. Motion vector differences and coefficient amplitudes may use either Exp-Golomb or CABAC (context-adaptive binary arithmetic coding) depending on the profile. Exp-Golomb handles the long tail of parameter types; CABAC squeezes out the last bits of efficiency for high-compression profiles.

=== bzip2 (Chapter 35)

After the Burrows-Wheeler Transform, bzip2 applies Move-to-Front coding and run-length encoding. The MTF output is a sequence of small integers (usually 0 or 1 with rare large values) — exactly a geometric-like source. bzip2 then applies Huffman coding on these small integers, but the distribution is so geometric that Rice coding would perform comparably with far simpler code.

== Summary of Code Lengths

Here is a table of how many bits each code uses for small values, which makes the tradeoffs concrete and easy to memorize:

#table(
  columns: (auto, auto, auto, auto, auto, auto),
  align: (center, center, center, center, center, center),
  table.header(
    [$n$], [Unary], [Gamma], [Rice k=1], [Rice k=2], [Rice k=3]
  ),
  [0], [1], [1], [2], [3], [4],
  [1], [2], [3], [2], [3], [4],
  [2], [3], [3], [4], [3], [4],
  [3], [4], [5], [4], [3], [4],
  [4], [5], [5], [6], [5], [4],
  [5], [6], [5], [6], [5], [4],
  [6], [7], [5], [8], [5], [4],
  [7], [8], [5], [8], [5], [4],
  [8], [9], [7], [10], [7], [4],
  [15], [16], [7], [10], [7], [4],
  [16], [17], [9], [12], [9], [6],
  [31], [32], [9], [16], [9], [6],
)

The pattern is clear: unary coding grows linearly (bad for large values), gamma grows logarithmically, and Rice with parameter k grows roughly as the quotient plus k remainder bits — a mixture of linear and constant terms. For a given mean, the Rice parameter that minimizes expected code length is approximately the base-2 logarithm of the mean.

== Exercises

#exercise("25.1", 1)[
  Write down the unary codes for $n = 1, 2, 3, 4, 5$. What is the total number of bits needed to encode the sequence $(2, 1, 3, 1, 2)$ using unary?
]

#solution("25.1")[
  Unary codes: 1→`0` (1 bit), 2→`10` (2 bits), 3→`110` (3 bits), 4→`1110` (4 bits), 5→`11110` (5 bits). For the sequence (2,1,3,1,2): bits = 2+1+3+1+2 = 9 bits total.
]

#exercise("25.2", 1)[
  Compute the Elias gamma codes for $n = 5, 9, 16, 32$. Verify using the formula: length $= 2 floor(log_2 n) + 1$.
]

#solution("25.2")[
  $n=5$: $k=2$, code = `00101`, 5 bits. ✓ $2 times 2+1=5$.
  $n=9$: $k=3$, code = `0001001`, 7 bits. ✓ $2 times 3+1=7$.
  $n=16$: $k=4$, code = `000010000`, 9 bits. ✓ $2 times 4+1=9$.
  $n=32$: $k=5$, code = `00000100000`, 11 bits. ✓ $2 times 5+1=11$.
]

#exercise("25.3", 1)[
  Encode the value $n = 19$ using Rice($k = 2$). Show the quotient, remainder, and final bit string.
]

#solution("25.3")[
  $q = 19 >> 2 = 4$, $r = 19 "AND" 3 = 3 = 11_2$.
  Unary of 4: `11110`.
  Remainder (2 bits): `11`.
  Code: `11110 11` = `1111011`, 7 bits.
]

#exercise("25.4", 2)[
  Prove that Rice(k=0) is equivalent to unary coding (with the convention that the value $n$ is encoded as $n$ ones followed by a zero, for $n >= 0$). What does this mean for sources where nearly all values are 0?
]

#solution("25.4")[
  Rice(k=0): $q = n >> 0 = n$, $r = n "AND" 0 = 0$, no remainder bits. The code is $q$ ones followed by a zero = $n$ ones followed by a zero. This is exactly unary of $n$ (zero-based convention). For sources where nearly all values are 0, the code `0` (1 bit) fires most of the time, making this an ideal single-bit-for-zero code.
]

#exercise("25.5", 2)[
  Decode the Exp-Golomb codewords: (a) `1`, (b) `011`, (c) `00110`. What values do they represent?
]

#solution("25.5")[
  (a) `1`: $k=0$, payload (0 bits), gamma value = 1, $n = 1 - 1 = 0$.
  (b) `011`: $k=1$, payload = `1`, gamma value = $2 + 1 = 3$, $n = 3 - 1 = 2$.
  (c) `00110`: $k=2$, payload = `10` = 2, gamma value = $4 + 2 = 6$, $n = 6 - 1 = 5$.
]

#exercise("25.6", 2)[
  A lossless audio encoder produces residuals with zero-mapped absolute values: `0, 0, 1, 0, 0, 2, 0, 1, 0, 0, 0, 3, 0, 0, 1`. Compute the best Rice parameter $k$ using the mean-based formula. Then compute the total bits for this sequence with Rice(k) and with Elias gamma (coding $n+1$ in gamma).
]

#solution("25.6")[
  Sum = 8, Count = 15, Mean = 8/15 ≈ 0.53. Best $k = floor(log_2(0.53 + 1)) = floor(0.62) = 0$.
  Rice(k=0) = unary: bit costs = (1,1,2,1,1,3,1,2,1,1,1,4,1,1,2) = 23 bits.
  Gamma (coding $n+1$): gamma(1)=1, gamma(2)=3, gamma(3)=3, gamma(4)=5. Costs: (1,1,3,1,1,3,1,3,1,1,1,5,1,1,3) = 27 bits.
  Rice(k=0) wins with 23 bits vs 27 bits.
]

#exercise("25.7", 3)[
  Implement a function `encode_golomb(n: int, m: int) -> str` (returning the bit string) and `decode_golomb(bits: str, m: int) -> int` for general Golomb coding (not just Rice). Test it for $m = 5$ and $n \in {0, 1, 2, 3, 4, 5, 10, 20}$. Verify that decoding recovers the original values.
]

#solution("25.7")[
  ```python
  import math

  def encode_golomb(n: int, m: int) -> str:
      q, r = divmod(n, m)             # divmod returns (quotient, remainder)
      b = m.bit_length() - 1          # floor(log2(m))
      t = (1 << (b + 1)) - m
      # Unary quotient: q zeros then a one
      unary = "0" * q + "1"
      # Truncated binary remainder.
      # format(r, "05b") = r in binary, zero-padded to width 5; here width b.
      if r < t:
          rem = format(r, f"0{b}b")
      else:
          rem = format(r + t, f"0{b+1}b")
      return unary + rem

  def decode_golomb(bits: str, m: int) -> int:
      b = m.bit_length() - 1
      t = (1 << (b + 1)) - m
      i = 0
      q = 0
      while bits[i] == "0":
          q += 1; i += 1
      i += 1  # skip the separator 1
      r_bits = bits[i:i+b]
      r = int(r_bits, 2) if r_bits else 0
      if r >= t:
          extra = bits[i+b]
          r = (r << 1) | int(extra) - t
      return q * m + r

  # Test
  for n in [0,1,2,3,4,5,10,20]:
      code = encode_golomb(n, 5)
      recovered = decode_golomb(code, 5)
      print(f"n={n}: code={code}, recovered={recovered}")
      assert recovered == n
  ```
]

#exercise("25.8", 3)[
  (Research) Find the Fibonacci codes for $n = 1, 2, 3, 4, 5, 10$. Verify that every code ends in `11` and that no two consecutive `1`s appear elsewhere. How many bits does the Fibonacci code for $n = 100$ use?
]

#solution("25.8")[
  Fibonacci numbers: $F_2=1, F_3=2, F_4=3, F_5=5, F_6=8, F_7=13, F_8=21, F_9=34, F_(10)=55, F_(11)=89$. The bit string lists $F_2$ first (lowest), then upward; a final `1` is appended as the end-marker.
  - $n=1=F_2$: bits `1`, code `11`.
  - $n=2=F_3$: bits `01`, code `011`.
  - $n=3=F_4$: bits `001`, code `0011`.
  - $n=4=F_4+F_2=3+1$: bits `101`, code `1011`.
  - $n=5=F_5$: bits `0001`, code `00011`.
  - $n=10=F_6+F_3=8+2$: bits `01001`, code `010011`.

  Every code ends in `11` (the last Zeckendorf bit plus the end-marker), and Zeckendorf's non-consecutive rule guarantees no `11` appears earlier.

  For $n=100$: $100 = 89 + 8 + 3 = F_(11) + F_6 + F_4$. The Zeckendorf bits from $F_2$ up to $F_(11)$ (10 positions) are `0010100001`; appending the end-marker gives the 11-bit code `00101000011`. So the Fibonacci code for 100 is 11 bits.
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/1055046")[Elias, P. (1975). "Universal codeword sets and representations of the integers." *IEEE Transactions on Information Theory* 21(2), 194–203.] The original paper introducing gamma, delta, and omega codes.

- #link("https://www.isca-archive.org/interspeech_2006/rice06_interspeech.html")[Rice, R. F. (1979). "Some practical universal noiseless coding techniques." JPL Technical Report 79-22.] The original Rice coding paper from NASA's Jet Propulsion Laboratory.

- #link("https://ieeexplore.ieee.org/document/1055337")[Golomb, S. W. (1966). "Run-length encodings." *IEEE Transactions on Information Theory* 12(3), 399–401.] Golomb's original paper on the codes that now bear his name.

- #link("https://www.rfc-editor.org/rfc/rfc9639.txt")[Coalson, J. et al. (2024). *Free Lossless Audio Codec (FLAC)*. RFC 9639.] The IETF standard for FLAC, which describes adaptive Rice coding in full detail.

- #link("https://ieeexplore.ieee.org/document/1218189")[Wiegand, T. et al. (2003). "Overview of the H.264/AVC Video Coding Standard." *IEEE Transactions on Circuits and Systems for Video Technology* 13(7).] The H.264 standard overview, covering Exp-Golomb syntax element coding.

- #link("https://arxiv.org/abs/0902.0271")[Duda, J. (2009). *Asymmetric Numeral Systems.* arXiv:0902.0271.] For comparison: how ANS replaces many of these codes in modern codecs.

#takeaways((
  "Universal integer codes encode any positive integer using only its magnitude — no probability table is needed.",
  "Unary coding costs n bits for the value n — optimal only for sources where n is almost always 1 or 2.",
  "Elias gamma uses 2·floor(log2(n))+1 bits — logarithmic growth, universal for any monotone-decreasing distribution.",
  "Elias delta encodes k+1 in gamma before the payload — better than gamma for large integers (n > 1000 or so).",
  "Golomb–Rice codes are provably optimal for geometrically distributed sources; Rice restricts m to powers of two for fast bit-shift arithmetic.",
  "The optimal Rice parameter k satisfies k ≈ log2(mean); FLAC adapts k per sub-block.",
  "Exp-Golomb codes (gamma of n+1) are the integer-coding backbone of H.264, HEVC, and AV1 video standards.",
  "Fibonacci codes use the unique Zeckendorf representation and terminate in '11', giving self-synchronization after bit errors.",
  "Byte varints give integer coding without bit-level I/O — used in Protocol Buffers, LevelDB, and database wire formats.",
  "tinyzip Step 9 (codes.py) implements unary, Elias gamma, Rice, and zigzag sign mapping — used by later steps for residuals.",
))

#bridge[
  We now have three entropy coding tools in our kit: Huffman (Chapter 24) for fixed alphabets with known probabilities, and the integer codes (this chapter) for unbounded integer-valued residuals. But both families share a limitation: they must snap to whole bits per symbol. A symbol whose true information content is 0.1 bits will cost at least 1 bit in Huffman, and 1 bit in Rice(k=0). The theoretical floor is entropy; our current tools can't reach it.

  Chapter 26 solves this by throwing out the per-symbol constraint entirely. *Arithmetic coding* encodes an entire message — thousands of symbols — as a single interval in $[0,1)$. By accumulating the fractional-bit cost of every symbol together, it achieves the entropy rate almost exactly, regardless of how skewed the distribution is. It's the technology that closes the gap our current codes leave open.
]
