#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Dictionary Coding II: LZW and the Patent Wars

#epigraph[
  "The ability to get a patent on an algorithm seems dangerous: it could be used to
  prevent the use of a standard method by anyone but the patent holder."
][_Donald Knuth, 1994, in a letter opposing software patents_]

On December 28, 1994 (the day after Christmas, when most software engineers
were eating leftovers), a document appeared on the CompuServe online service
that quietly detonated a bomb under the internet. It announced that the
Lempel-Ziv-Welch algorithm, the engine inside the GIF image format that had
been powering the visual web for seven years, was subject to a patent owned by
Unisys Corporation. Anyone writing software that created or displayed GIF images
would now have to pay a licensing fee.

The internet did not take this well.

Over the next several years, a community that had built its visual culture on
freely-shared GIFs found itself caught between two corporations and a
seventeen-year-old patent. The backlash created PNG, the lossless image format
that would eventually displace GIF for most non-animated uses, and permanently
changed how the open-source world thought about intellectual property. All of it
traces back to a single clever tweak of the LZ78 algorithm by a man named Terry
Welch, published ten years earlier.

In this chapter we dissect LZW: its elegant table-building trick, how it quietly
powered most of the early internet's data transfer, and how one patent turned an
engineering success story into a cautionary tale that engineers still cite today.

#recap[
  In *Chapter 28* we met LZ77 and LZ78, Abraham Lempel and Jacob Ziv's two
  complementary approaches to dictionary coding. LZ77 uses a sliding window as
  an implicit dictionary. LZ78 builds an explicit table of phrases as it reads
  the input, emitting *(index, next\_symbol)* pairs. Both schemes are
  *universal*: they converge to the source's entropy rate with no prior knowledge
  of the statistics. This chapter picks up immediately from LZ78 and shows how
  Terry Welch simplified it into LZW, then follows the consequences of that
  simplification all the way to a patent war and the birth of PNG.
  In *Chapter 30* we will return to the LZ77 branch and build DEFLATE, the
  compressed data engine of gzip, ZIP, and PNG's own compression layer.
]

#objectives((
  "Explain how LZW modifies LZ78 to emit only dictionary indices (no trailing symbol).",
  "Trace a complete LZW encoding and decoding by hand on a small example.",
  "Understand why the decoder can always reconstruct the same table as the encoder, even though it receives only indices.",
  "Explain the special LZW tweak that handles the W+first(W) edge case in decoding.",
  "Read the LZW algorithm profile and explain its time and space complexity.",
  "Describe where LZW appeared: Unix compress, GIF, TIFF, and V.42bis.",
  "Tell the story of the Unisys patent, the GIF licensing crisis, and the creation of PNG.",
  "Place LZW in the wider LZ family map and understand when each branch is preferred.",
))

== From LZ78 to LZW: One Clever Simplification

Recall LZ78 from Chapter 28. It builds a dictionary of phrase strings as it
reads the input. At each step it finds the longest phrase $W$ already in the
dictionary, then emits the pair *(index of W, next symbol)*. It then inserts
the concatenation $W +$ "next symbol" into the dictionary as a new entry.

Terry Welch, a computer scientist at the Sperry Corporation in Sudbury,
Massachusetts, published a refinement in the June 1984 issue of _IEEE Computer_.
His paper was titled "A Technique for High-Performance Data Compression." The
simplification he made sounds almost trivially small:

#keyidea[
  *LZW emits only the dictionary index.* The "next symbol" is no longer sent
  separately. Instead, the new dictionary entry is built from two consecutive
  indices: the current match $W$ plus the *first character of the next match*.
  This means the decoder can rebuild the same dictionary purely from the stream
  of indices, without any extra characters in the stream.
]

Why does this matter? In LZ78, every output token is a pair: index plus a
character. LZW replaces every pair with a single index. On an alphabet of 256
byte values, a typical text file might have thousands of output tokens; shaving
the character byte from every one of them saves a meaningful fraction of space.
More importantly, the single-token output is extremely clean and regular, which
made LZW very appealing for hardware implementation. That was exactly what Welch needed,
because he was designing it for high-performance disk controllers, not general
software.

=== The LZW Dictionary at Startup

LZW pre-fills the dictionary with one entry for every possible single symbol.
For a byte-based compressor operating on 256 possible byte values, the initial
dictionary has 256 entries, numbered 0 through 255. Entry $k$ contains the
single-byte string $[k]$.

When we start encoding, entries 0–255 are already known to both the encoder and
the decoder. Neither side needs to communicate them. This shared starting point
is what makes the index-only protocol work: the decoder always knows what entries
0–255 mean, and it builds all higher entries from the received indices, exactly
as the encoder built them.

#definition("LZW dictionary")[
  A table $D$ mapping integer *codes* to byte strings (*phrases*).
  At initialization: $D[k] = [k]$ for $k in {0, 1, dots, 255}$.
  The next free code is $N = 256$ at the start.
  During encoding, each new phrase found is added as $D[N]$ and $N$ is
  incremented.
]

=== LZW Encoding: Step by Step

Here is the algorithm in plain English, then we will trace a worked example.

```
LZW-ENCODE(input):
  Initialize D[0..255] = single-byte strings.
  N ← 256   # next free code
  W ← ""    # current phrase being extended
  for each byte c in input:
    if W + c is in D:
      W ← W + c          # can extend: keep going
    else:
      emit code(W)        # output code for current phrase
      D[N] ← W + c       # add new phrase to dictionary
      N ← N + 1
      W ← [c]            # restart from single byte c
  emit code(W)            # flush remaining phrase
```

The key invariant: we emit a code only when we cannot extend the current phrase
any further. The new dictionary entry is the phrase we just matched, extended by
the first character that broke the match.

=== A Worked Encoding

Let us encode the string `ABABABAB` using LZW on an alphabet of just three
characters: A (code 0), B (code 1), \# (end-of-string, code 2).
Dictionary starts as: 0→A, 1→B, 2→\#. Next free code: 3.

#align(center)[
  #text(size: 8pt)[
  #table(
    columns: (auto, auto, 1fr, auto, 1fr),
    inset: 5pt,
    align: (left, center, left, center, left),
    fill: (_, row) => if row == 0 { rgb("#dde5f0") } else { none },
    [*Step*], [*c*], [*W + c in D?*], [*Emit*], [*New entry*],
    [1], [A], [A: yes], [-], [W="A"],
    [2], [B], [AB: no], [code(A) = 0], [D[3]="AB", W="B"],
    [3], [A], [BA: no], [code(B) = 1], [D[4]="BA", W="A"],
    [4], [B], [AB: yes (D[3])], [-], [W="AB"],
    [5], [A], [ABA: no], [code(AB) = 3], [D[5]="ABA", W="A"],
    [6], [B], [AB: yes (D[3])], [-], [W="AB"],
    [7], [A], [ABA: yes (D[5])], [-], [W="ABA"],
    [8], [B], [ABAB: no], [code(ABA) = 5], [D[6]="ABAB", W="B"],
    [flush], [-], [-], [code(B) = 1], [done],
  )
  ]
]

The encoder outputs the code sequence: *0, 1, 3, 5, 1*.

Five codes cover eight characters. But the real win comes when the same patterns
repeat many more times: entries like "ABABABAB" eventually get their own single
code, and very long repetitive strings compress dramatically.

#checkpoint[
  After Step 4, why does the encoder know to look for "ABA" rather than just
  "A" at step 5?
][
  Because at the end of Step 4 the current phrase $W$ was updated to "AB" (the
  phrase found in Step 3). The encoder reads the next character (A at Step 5)
  and checks whether W+"A" = "ABA" is in the dictionary. It is not yet, so it
  emits code(AB)=3, adds D[5]="ABA", and resets W="A".
]

=== LZW Decoding: Rebuilding the Table

Decoding is the really elegant part. The decoder starts with the same
initialization (D[0..255] = single bytes) and receives only the stream of
codes, with no extra characters. Yet it can reconstruct the *exact same* dictionary,
because it uses each received code to figure out what string the encoder would
have added.

```
LZW-DECODE(codes):
  Initialize D[0..255] = single-byte strings.
  N ← 256
  prev ← first code in stream
  emit D[prev]
  for each subsequent code c in stream:
    if c < N:
      entry ← D[c]
    else:              # c == N (the special edge case)
      entry ← D[prev] + first_byte(D[prev])
    emit entry
    D[N] ← D[prev] + first_byte(entry)
    N ← N + 1
    prev ← c
```

Let us decode `0, 1, 3, 5, 1`:

#align(center)[
  #text(size: 8pt)[
  #table(
    columns: (auto, auto, 1fr, 1fr),
    inset: 5pt,
    align: (center, left, left, left),
    fill: (_, row) => if row == 0 { rgb("#dde5f0") } else { none },
    [*Code*], [*Output*], [*New entry added*], [*D after*],
    [0], [A], [-], [prev="A"],
    [1], [B], [D[3]="A"+"B"="AB"], [prev="B"],
    [3], [AB (D[3])], [D[4]="B"+"A"="BA"], [prev="AB"],
    [5], [ABA (D[5])], [D[5]="AB"+"A"="ABA"], [prev="ABA"],
    [1], [B], [D[6]="ABA"+"B"="ABAB"], [done],
  )
  ]
]

Output: A, B, AB, ABA, B → "A"+"B"+"AB"+"ABA"+"B" = `ABABABAB`. ✓

The decoder perfectly reconstructed the original string by rebuilding exactly
the same dictionary the encoder built, purely from the received indices.

=== The Edge Case: When the Decoder Sees a Code It Has Not Yet Added

There is one subtle trap in LZW decoding. It arises when the encoder adds a
new entry $D[N]$ and then *immediately emits code N* as the very next output.
At the moment the decoder receives code $N$, it has not yet added $D[N]$ to its
own table (it does that *after* processing each code). So the decoder receives a
code it does not yet know.

#pitfall[
  If the decoder receives a code $c$ such that $c$ equals $N$ (the *next* free
  index), the table entry does not yet exist. This happens when the encoder sees
  a pattern of the form $W W[0] W$ (the current phrase repeated, starting with
  its own first character). The decoder must handle this specially.
]

Fortunately, there is a clean solution. The entry that the encoder would have
added is always `D[prev]` + `first_byte(D[prev])`, the previous phrase extended
by its own first character. The decoder can compute this without looking it up:

```python
if c == N:                              # the edge case
    entry = D[prev] + D[prev][0:1]     # D[prev] + its own first byte
```

This is often called the "KwKwK" problem (for a phrase like "abababab"
compressed in the right way): the decoder uses its knowledge of the previous
entry to bootstrap the missing one. Once you understand it, it is elegant. But
every LZW implementation that does not handle this case has a latent bug.

#note[
  *What is a "trie"?* The algorithm profiles below describe the LZ78 dictionary
  as a _trie_ (pronounced "try", from re*trie*val). A trie is a tree in which
  each node represents one character and each path from the root spells out a
  string. To store the phrases `AB`, `ABA`, and `BA`, you walk down from the
  root: an `A` branch leads to a node, from which a `B` branch leads to the node
  marking `AB`, from which an `A` branch leads to the node marking `ABA`; a
  separate `B` branch from the root leads to `BA`. Because shared prefixes share
  the same path, checking whether `W + c` is already stored is just "from the
  node for `W`, is there a child edge labelled `c`?": a single step, no
  searching. That is exactly the lookup LZ78 and LZW need on every input byte. In
  our Python code we get the same one-step lookup more simply by using a `dict`
  keyed on the whole phrase (the hash table from Chapter 14), but a trie
  is the classic textbook structure and the one the original papers describe.
]

#algo(
  name: "LZ78",
  year: "1978",
  authors: "Jacob Ziv and Abraham Lempel (Technion, Israel)",
  aim: "Universal lossless compression via an explicit phrase dictionary built during encoding; emits (index, next-symbol) pairs",
  complexity: "Encoding and decoding O(n) average; dictionary space O(k) entries where k grows up to a chosen ceiling",
  strengths: "Provably asymptotically optimal; no sliding window; dictionary is an explicit trie so lookup is exact; self-adapting to source statistics",
  weaknesses: "Emitting the 'next symbol' after every index wastes bits; explicit dictionary uses more memory than a sliding window; not as good on short or structured binary data as LZ77",
  superseded: "LZW (a refinement, 1984); in practice LZ77-based codecs dominate. LZ78 itself is rarely used directly in production software.",
)[
  LZ78 was Lempel and Ziv's second universal compression scheme, published one
  year after LZ77. Where LZ77 references positions in a recent window, LZ78
  builds a trie of phrases seen so far, indexed by integer codes. At each step
  it finds the longest phrase in the trie that matches the input, emits *(code,
  next-byte)*, and inserts the extension into the trie. Because both sides start
  from the same empty trie and follow identical rules, no dictionary needs to be
  transmitted, a key advantage over static dictionary methods.
]

#algo(
  name: "LZW (Lempel-Ziv-Welch)",
  year: "1984",
  authors: "Terry A. Welch (Sperry Corporation)",
  aim: "Lossless universal data compression via adaptive dictionary of variable-length phrases; encoder emits only phrase indices, no trailing symbols",
  complexity: "Encoding O(n) average time; decoding O(n); space O(k·L) where k is dictionary size and L is max phrase length",
  strengths: "Simple; fast in hardware; no prior statistics needed; good on repetitive byte streams; one-pass adaptive",
  weaknesses: "Variable-width code output complicates bit-level implementation; dictionary can fill (requires reset or pruning); poor on already-compressed data or random bytes; covered by patents 1985–2004",
  superseded: "For general use: DEFLATE (Ch. 30), LZMA (Ch. 31), Zstandard (Ch. 32). For images: PNG (DEFLATE-based). LZW survives in TIFF (optional), PDF (optional), and older GIF files.",
)[
  LZW pre-loads the dictionary with all 256 single-byte entries (codes 0–255).
  Encoding greedily extends the current phrase until the extension is not in the
  dictionary, then outputs the current phrase's code and inserts the extension as
  a new entry. Decoding mirrors this exactly, reconstructing the same dictionary
  from codes alone. The only non-obvious step is handling the case where the
  decoder receives a code equal to the next-to-be-assigned index (the KwKwK
  edge case).
]

== Variable-Width Codes and the 12-Bit Ceiling

In the worked example above we used small code values for clarity. In a real
implementation the codes grow as the dictionary grows, and we must decide how
many bits each code uses.

LZW implementations typically start with codes one bit wider than the minimum
needed to represent all initial entries. For a 256-byte alphabet the initial
dictionary has 256 entries (codes 0–255), so we need 8 bits. LZW starts at 9
bits. When the dictionary fills past 512 entries it switches to 10-bit codes;
past 1024 it uses 11-bit codes; and past 2048 it uses 12-bit codes.

Most implementations cap the code width at 12 bits (giving a maximum of 4096
dictionary entries). When the dictionary fills to 4096 entries, the encoder has
two choices:

1. *Clear and restart:* emit a special "clear code," reset the dictionary to its
   initial state, and start fresh. This is what GIF requires.
2. *Freeze and keep using:* stop adding new entries, keep using the full
   dictionary. This tends to work better on data that has settled into a stable
   distribution.

The GIF format uses the clear-and-restart strategy. It defines two reserved
codes:
- The *clear code* (= $2^"min-code-size"$) tells the decoder to reset the table.
- The *end-of-information code* (= clear code + 1) marks the end of the image
  data stream.

All other codes refer to dictionary entries.

#gopython("Variable-width bit writing")[
  Packing codes of different widths into a byte stream is trickier than it
  sounds. Each code might not land on a byte boundary. We need a small
  accumulator that collects bits and flushes full bytes.

  ```python
  def write_codes(codes: list[int], code_width: int) -> bytes:
      """Pack a list of integer codes into a byte stream, LSB-first."""
      buf = bytearray()
      acc = 0          # bit accumulator
      bits_in_acc = 0  # how many bits are pending
      for code in codes:
          acc |= (code << bits_in_acc)
          bits_in_acc += code_width
          while bits_in_acc >= 8:
              buf.append(acc & 0xFF)   # emit low 8 bits
              acc >>= 8
              bits_in_acc -= 8
      if bits_in_acc > 0:             # flush remaining bits
          buf.append(acc & 0xFF)
      return bytes(buf)
  ```

  GIF stores codes *least-significant bit first* within each byte, unlike most
  other formats that pack MSB-first. When implementing a GIF decoder, always
  check the bit order! The `tinyzip` `BitWriter` from Chapter 17
  (Step 3) handles configurable bit order.
]

== A Complete Python Implementation

Let us implement LZW compression and decompression in Python 3.14. This is
illustrative code, not the tinyzip project step (Chapter 29 has no assigned
tinyzip step), but a complete, self-testing pair of functions that demonstrates
every concept we have discussed.

#gopython("dict with tuple keys")[
  Python `dict` can use any *hashable* value as a key, including `bytes` or
  `tuple[int, ...]`. Here we use `bytes` objects as dictionary keys because
  phrases in LZW are byte strings. Looking up whether `W + c` (where `W` is
  `bytes` and `c` is `bytes`) is in `D` is a single `O(1)` hash lookup.

  ```python
  d: dict[bytes, int] = {}
  d[b"AB"] = 3           # phrase b"AB" maps to code 3
  b"AB" in d             # True
  b"AC" in d             # False
  ```
]

```python
# lzw_demo.py - a standalone LZW encode / decode demonstration
# Not a tinyzip project step; no #project block needed here.

def lzw_encode(data: bytes, max_bits: int = 12) -> list[int]:
    """Encode `data` with LZW, returning a list of integer codes.

    max_bits: maximum code width in bits (typically 12 or 15).
    Returns codes including a leading CLEAR and trailing EOI sentinel.
    """
    # initialize dictionary
    dict_size = 256
    table: dict[bytes, int] = {bytes([i]): i for i in range(dict_size)}

    CLEAR = dict_size          # 256
    EOI   = dict_size + 1     # 257
    next_code = dict_size + 2  # next free code after CLEAR and EOI
    max_code = (1 << max_bits) - 1

    codes: list[int] = [CLEAR]   # always start with CLEAR

    W = b""
    for byte_val in data:
        c = bytes([byte_val])
        if W + c in table:
            W = W + c
        else:
            codes.append(table[W])
            if next_code <= max_code:
                table[W + c] = next_code
                next_code += 1
            elif next_code > max_code:
                # dictionary full: emit CLEAR and reset
                codes.append(CLEAR)
                table = {bytes([i]): i for i in range(256)}
                next_code = dict_size + 2
            W = c

    if W:
        codes.append(table[W])
    codes.append(EOI)
    return codes


def lzw_decode(codes: list[int], max_bits: int = 12) -> bytes:
    """Decode an LZW code sequence back to the original bytes."""
    dict_size = 256
    CLEAR = dict_size
    EOI   = dict_size + 1
    max_code = (1 << max_bits) - 1

    def make_table() -> dict[int, bytes]:
        t: dict[int, bytes] = {i: bytes([i]) for i in range(dict_size)}
        t[CLEAR] = b""
        t[EOI]   = b""
        return t

    table = make_table()
    next_code = dict_size + 2

    output = bytearray()
    prev = b""

    for code in codes:
        if code == CLEAR:
            # reset
            table = make_table()
            next_code = dict_size + 2
            prev = b""
            continue
        if code == EOI:
            break

        if code in table:
            entry = table[code]
        elif code == next_code:
            # KwKwK edge case: code not yet in table
            entry = prev + prev[0:1]
        else:
            raise ValueError(f"Bad LZW code {code}")

        output.extend(entry)

        if prev and next_code <= max_code:
            table[next_code] = prev + entry[0:1]
            next_code += 1

        prev = entry

    return bytes(output)


# self-test
if __name__ == "__main__":
    samples = [
        b"ABABABABABABABAB",
        b"hello world hello world",
        b"\x00" * 100,
        b"the quick brown fox jumps over the lazy dog",
    ]
    for original in samples:
        codes = lzw_encode(original)
        recovered = lzw_decode(codes)
        assert recovered == original, f"Round-trip failed: {original!r}"
        ratio = len(codes) * 2 / len(original)   # codes as 16-bit ints
        print(f"{len(original):4d} bytes → {len(codes):4d} codes  ratio={ratio:.2f}  {'OK' if recovered==original else 'FAIL'}")
```

Running this on `b"ABABABABABABABAB"` (16 bytes) produces 9 codes: 7
data codes plus the leading CLEAR and trailing EOI sentinels. That is a ratio below 1.0
even with 16-bit code storage. On the 43-byte pangram, where almost nothing
repeats, it produces 43 codes: no gain at all. LZW needs longer repetitions to
shine, which is exactly why the highly repetitive `b"\x00" * 100` collapses to
just 16 codes.

#checkpoint[
  In `lzw_decode`, why does the line `entry = prev + prev[0:1]` correctly
  reconstruct the missing entry?
][
  When the decoder receives a code equal to `next_code`, it means the encoder
  just added that entry and *immediately* used it. The encoder adds new entries
  as `table[next_code] = W + first_byte(next_output)`. When the encoder emits
  code `next_code`, the "next output" is the entry itself, so the new entry is
  `prev + first_byte(new_entry)` = `prev + first_byte(prev)` (since the new
  entry starts with `prev`). The decoder computes this directly.
]

== Where LZW Lived: compress, GIF, TIFF, and V.42bis

In the years between 1984 and the patent controversy, LZW spread across
computing in four distinct ecosystems. Understanding each one helps explain why
the 1994 patent enforcement announcement hit so hard. LZW was not some obscure
algorithm buried in one product. It was everywhere.

=== Unix compress (1986)

The first major software deployment of LZW was the Unix `compress` utility,
which appeared around 1985–1986. `compress` stored files in the `.Z` format
(not to be confused with `.zip`). It used 9-to-16-bit variable-width LZW codes
and became standard on virtually every Unix system for more than a decade.
System administrators used it to shrink log files, software distributions, and
disk backups.

`compress` was fast, simple, and good enough. It did not use Huffman coding on
top of its LZW output, which left some compression ratio on the table, but for
the machines of the mid-1980s, the simplicity was a feature.

#history[
  When gzip was released in 1992 (using the patent-free DEFLATE algorithm),
  it was explicitly positioned as a replacement for `compress`. Peter Deutsch,
  who wrote the DEFLATE spec (RFC 1951), and Jean-loup Gailly, the primary
  author of gzip, were both aware of the patent risk around LZW and deliberately
  chose a different algorithmic path. Their foresight saved the internet from
  a second patent crisis.
]

=== GIF: the Graphical Web (1987)

Steve Wilhite, a software engineer at CompuServe, designed the *Graphics
Interchange Format* in 1987. CompuServe was then one of the largest online
services in the United States, the "internet" most Americans used before the
web proper existed. Wilhite needed a way to transmit color images over slow
dial-up modems. LZW was fast, it compressed palette-indexed image data well,
and it was patent-free (or so everyone believed in 1987).

GIF stores images as a palette of up to 256 colors (a *color lookup table*)
plus a grid of pixel indices, each index pointing into the palette. The pixel
index stream is then LZW-compressed. This two-stage encoding (palette
quantization followed by LZW compression of the index stream) works extremely
well on images with large flat areas of uniform color (cartoons, logos, charts)
and poorly on photographic images with thousands of distinct colors.

There are actually two GIF versions: GIF 87a (the original) and GIF 89a (1989),
which added support for animated sequences, transparent colors, and per-frame
delays. The animated GIF became a staple of early web culture, and GIF 89a
is still what dominates the animated-image web today.

#fig(
  [How a GIF encodes a simple two-color image: the pixel indices (0=white, 1=black) are run through LZW before being packed into the file.],
  cetz.canvas({
    import cetz.draw: *
    // pixel grid
    let colors_grid = ((1,0,0,1),(0,1,1,0),(0,1,1,0),(1,0,0,1))
    let cell = 0.55
    for (ri, row) in colors_grid.enumerate() {
      for (ci, v) in row.enumerate() {
        let x = ci * cell
        let y = -ri * cell
        let fill_color = if v == 1 { black } else { white }
        rect((x, y), (x + cell, y - cell),
          fill: fill_color, stroke: 0.5pt + gray)
      }
    }
    // pixel indices label
    content((2.5, -0.4), box(width: 2.8cm, inset: 1pt, align(center, text(size: 8pt)[Index stream:\ `1,0,0,1,0,1,1,0,...`])))
    // arrow
    line((2.2, -0.8), (3.4, -0.8), mark: (end: "straight"), stroke: 1pt)
    // LZW box
    rect((3.5, -0.4), (5.2, -1.2), fill: rgb("#dde5f0"), stroke: 1pt)
    content((4.35, -0.8))[LZW]
    // codes
    line((5.2, -0.8), (6.2, -0.8), mark: (end: "straight"), stroke: 1pt)
    content((6.5, -0.8), text(size: 8pt)[Codes\ to file])
    // palette box on left
    rect((-1.8, 0.3), (-0.1, -1.1), fill: rgb("#fff8e7"), stroke: 1pt)
    content((-0.95, -0.4), box(width: 1.3cm, inset: 1pt, align(center, text(size: 7pt)[Palette:\ 0=white\ 1=black])))
  })
)

=== TIFF: Professional Print (1988 onward)

The *Tagged Image File Format* (TIFF), developed by Aldus Corporation for
desktop publishing applications, adopted LZW compression as an optional
compression scheme. TIFF was the dominant format for scanned documents,
professional photographs, and prepress workflows throughout the 1990s. LZW
support in TIFF meant that high-resolution grayscale and color scans could be
stored more compactly without losing a single pixel.

After the patent issue became public, many TIFF writers deliberately omitted LZW
and switched to PackBits (a simple run-length encoder) or uncompressed storage.
TIFF with LZW still exists today (the patents have expired) and is supported in
software like LibTIFF and ImageMagick.

=== V.42bis: Squeezing the Modem (1990)

The *V.42bis* standard, published by the ITU-T (then CCITT) in 1990, specified
LZW as the compression algorithm for modems. If both ends of a dial-up connection
supported V.42bis, they could compress data on the fly as it passed through the
modem hardware. A 14.4 kbps modem with V.42bis could transfer data at an
effective throughput of 57.6 kbps on compressible text: a free 4× speedup.

V.42bis was significant because it was in *hardware* and completely transparent
to the software on both sides. Applications never knew compression was happening.
This is a perfect example of LZW's appeal for Welch's original application:
hardware-friendly, fast, and requiring no cooperation from the sender's software.

== The Patent: US 4,558,302

Terry Welch filed the patent application on June 20, 1983, almost a year before
his IEEE article appeared. US Patent 4,558,302 was issued to Terry A. Welch on
December 10, 1985, and assigned to Sperry Corporation. When Sperry merged with
Burroughs Corporation in 1986 to form *Unisys*, the patent came along.

For years, almost no one paid attention to the patent. CompuServe adopted LZW
for GIF in 1987 without knowing about it. Unix `compress` spread across the
world. V.42bis was standardized internationally. The ITU-T apparently did not
notice either. LZW was treated as a contribution to the public domain of ideas.

#aside[
  Terry Welch himself was not personally involved in the patent enforcement.
  He died in 1988, just four years after his landmark paper appeared. The
  enforcement actions were entirely a business decision by Unisys, not by the
  algorithm's inventor.
]

Then, in 1993, Unisys discovered that their patent covered GIF. They quietly
negotiated a licensing agreement with CompuServe. That agreement might have
remained private. On December 28, 1994, CompuServe announced it
to all GIF-using software developers, and the announcement landed like a
grenade. Here is the essence of what it said: software that creates or reads GIF
files needed a commercial license from Unisys, and developers who had already
shipped such software might owe back royalties.

=== The Internet's Response

The reaction on Usenet and early mailing lists was volcanic. Engineers who had
written GIF display code for free, as open-source contributions, found themselves
potentially liable. Shareware authors who had built simple image viewers were
contacted by Unisys lawyers. Large companies like Microsoft negotiated their own
licenses quietly; small developers and open-source projects had no money for
lawyers.

The League for Programming Freedom organized the *"Burn All GIFs"* campaign,
a symbolic call to switch away from GIF entirely. In 1999 a second wave of
enforcement began, targeting *all* companies running websites that displayed GIFs,
not just the software makers. Unisys demanded royalties from anyone using a web
server that served GIF images. The phrase "patent troll" entered everyday
engineering vocabulary in no small part because of this campaign.

#history[
  Unisys also held a European patent, as well as patents in the United Kingdom,
  France, Germany, Italy, Japan, and Canada, all filed in 1983 or 1984, all
  expiring 20 years after filing. The US patent expired on June 20, 2003.
  European and other patents expired in 2004. From mid-2004 onward, LZW was
  completely free to use worldwide. The full patent period lasted almost exactly
  20 years, an entire generation of software development.
]

=== The Birth of PNG

On January 4, 1995, just one week after the CompuServe announcement, a
software developer named Thomas Boutell posted a message to the Usenet newsgroup
`comp.graphics`. He proposed a completely new, patent-free image format that
would replace GIF. He called his draft "PBF" (Portable Bitmap Format).

The response was immediate. Within days, a collaborative effort involving dozens
of engineers had begun. Oliver Fromme suggested renaming the format PING
(a recursive acronym: "PING Is Not GIF"), which was then shortened to PNG
(Portable Network Graphics). The format was designed with several explicit
anti-patent goals:

- *Lossless compression using DEFLATE, not LZW.* DEFLATE (Chapter 30) was
  already in the public domain via RFC 1951 and the zlib library.
- *True-color support:* up to 48 bits per pixel, versus GIF's 8 bits (256
  colors).
- *Alpha transparency:* smooth transparency per-pixel, unlike GIF's binary
  on/off transparency.
- *Better interlacing:* Adam7 interlacing for progressive display.
- *No animation:* the designers deliberately omitted animation to keep the
  format simple. (Animation came later with APNG, an unofficial extension.)

The World Wide Web Consortium approved the PNG specification on October 1, 1996.
RFC 2083 followed in January 1997. PNG used DEFLATE for its compression layer,
specifically the zlib format described in RFC 1950. No patents, no royalties,
no lawyers.

#fig(
  [GIF vs PNG: a comparison of key properties that drove the switch after 1995.],
  cetz.canvas({
    import cetz.draw: *
    let col1 = 0.0
    let col2 = 3.5
    let row_h = 0.65
    // headers
    content((col1 + 1.5, 0.3), text(size: 9pt, weight: "bold")[GIF])
    content((col2 + 1.5, 0.3), text(size: 9pt, weight: "bold")[PNG])
    line((-0.2, 0.0), (7.2, 0.0), stroke: 0.8pt)
    let rows = (
      ("Compression", "LZW (patented)", "DEFLATE (free)"),
      ("Max colors", "256 (8-bit palette)", "16.7M+ (true color)"),
      ("Transparency", "1-bit (on/off)", "8-bit alpha channel"),
      ("Patent risk", "Yes (1985–2004)", "None"),
      ("Animation", "Yes (GIF 89a)", "No (APNG unofficial)"),
    )
    for (i, (label, gif_val, png_val)) in rows.enumerate() {
      let y = -(i + 1) * row_h
      let fill_c = if calc.rem(i, 2) == 0 { rgb("#f4f6f8") } else { white }
      rect((-0.2, y), (7.2, y - row_h), fill: fill_c, stroke: none)
      content((-0.1, y - row_h / 2), anchor: "west", box(width: 2.6cm, inset: 1pt, text(size: 8pt, style: "italic")[#label]))
      content((col1 + 1.5, y - row_h / 2), box(width: 2.8cm, inset: 1pt, align(center, text(size: 8pt)[#gif_val])))
      content((col2 + 1.5, y - row_h / 2), box(width: 2.8cm, inset: 1pt, align(center, text(size: 8pt)[#png_val])))
    }
    line((-0.2, -rows.len() * row_h), (7.2, -rows.len() * row_h), stroke: 0.5pt)
    // vertical dividers
    line((3.0, 0.0), (3.0, -rows.len() * row_h), stroke: 0.5pt + rgb("#d0d7de"))
    line((6.5, 0.0), (6.5, -rows.len() * row_h), stroke: 0.5pt + rgb("#d0d7de"))
  })
)

#keyidea[
  PNG's success demonstrates something important: *technical* quality is not
  enough to decide which formats win. GIF survived and continued to be used for
  animated images for decades *after* PNG appeared, purely because PNG did not
  support animation and GIF did. The formats settled into a coexistence based on
  their non-overlapping features, not on compression merit alone.
]

== Mapping the Wider LZ Family

Now that we have seen both branches of the LZ family (LZ77/LZSS in Chapter 28
and LZ78/LZW in this chapter), it is worth mapping the whole family tree. Later
chapters will visit several of these descendants in detail.

#fig(
  [The LZ algorithm family tree. Solid arrows mean "descends from / is a direct refinement of." The two root ideas (LZ77 and LZ78) are shown at the top.],
  cetz.canvas({
    import cetz.draw: *
    // LZ77 branch
    content((0.0, 5.0), box(stroke: 1pt, inset: 5pt, fill: rgb("#dde5f0"))[LZ77 (1977)])
    content((0.0, 3.8), box(stroke: 1pt, inset: 5pt, fill: rgb("#e8f0e8"))[LZSS (1982)])
    line((0.0, 4.72), (0.0, 4.1), mark: (end: "straight"), stroke: 1pt)
    content((-1.5, 2.6), box(stroke: 1pt, inset: 4pt, fill: rgb("#f0f8e8"))[DEFLATE (1991)])
    content((1.5, 2.6), box(stroke: 1pt, inset: 4pt, fill: rgb("#f0f8e8"))[LZS (1995)])
    line((0.0, 3.52), (-1.5, 2.85), mark: (end: "straight"), stroke: 1pt)
    line((0.0, 3.52), (1.5, 2.85), mark: (end: "straight"), stroke: 1pt)
    content((-3.0, 1.4), box(stroke: 1pt, inset: 4pt, fill: rgb("#fff0d8"))[LZ4 (2011)])
    content((-1.5, 1.4), box(stroke: 1pt, inset: 4pt, fill: rgb("#fff0d8"))[Brotli (2015)])
    content((0.0, 1.4), box(stroke: 1pt, inset: 4pt, fill: rgb("#fff0d8"))[zstd (2016)])
    content((1.5, 1.4), box(stroke: 1pt, inset: 4pt, fill: rgb("#fff0d8"))[LZMA (1998)])
    line((-1.5, 2.32), (-3.0, 1.7), mark: (end: "straight"), stroke: 1pt)
    line((-1.5, 2.32), (-1.5, 1.7), mark: (end: "straight"), stroke: 1pt)
    line((-1.5, 2.32), (0.0, 1.7), mark: (end: "straight"), stroke: 1pt)
    line((-1.5, 2.32), (1.5, 1.7), mark: (end: "straight"), stroke: 1pt)

    // LZ78 branch
    content((5.0, 5.0), box(stroke: 1pt, inset: 5pt, fill: rgb("#dde5f0"))[LZ78 (1978)])
    content((5.0, 3.8), box(stroke: 1pt, inset: 5pt, fill: rgb("#e8f0e8"))[LZW (1984)])
    line((5.0, 4.72), (5.0, 4.1), mark: (end: "straight"), stroke: 1pt)
    content((3.8, 2.6), box(stroke: 1pt, inset: 4pt, fill: rgb("#f0f8e8"))[compress (1986)])
    content((5.8, 2.6), box(stroke: 1pt, inset: 4pt, fill: rgb("#f0f8e8"))[GIF (1987)])
    content((5.0, 1.4), box(stroke: 1pt, inset: 4pt, fill: rgb("#fff0d8"))[TIFF LZW])
    content((3.5, 1.4), box(stroke: 1pt, inset: 4pt, fill: rgb("#fff0d8"))[V.42bis])
    line((5.0, 3.52), (3.8, 2.85), mark: (end: "straight"), stroke: 1pt)
    line((5.0, 3.52), (5.8, 2.85), mark: (end: "straight"), stroke: 1pt)
    line((5.8, 2.32), (5.0, 1.7), mark: (end: "straight"), stroke: 1pt)
    line((3.8, 2.32), (3.5, 1.7), mark: (end: "straight"), stroke: 1pt)
  })
)

=== LZ77 Branch: The Sliding-Window Family

The LZ77 branch dominates general-purpose compression today. Its key variants:

*LZSS (Lempel-Ziv-Storer-Szymanski, 1982):* A cleanup of LZ77 that omits
references shorter than the break-even point (where a reference costs more bits
than emitting the literal). This made LZ77 practical for software. Chapter 28
covered LZSS in detail.

*DEFLATE (Phil Katz, 1991):* LZ77 with hash-chain match finding, followed by
Huffman coding of the token stream. The engine of gzip, ZIP, zlib, and PNG.
Chapter 30 builds this in detail.

*LZ4 (Yann Collet, 2011):* An extremely fast LZ77 variant that omits entropy
coding entirely. Match finding uses a simple hash table, and output is a stream
of (literal run, back-reference) pairs with fixed-width length and offset fields.
Decoding is essentially a memory copy loop, extremely fast on modern CPUs.
Chapter 32 discusses LZ4.

*Brotli (Google, 2013–2015; RFC 7932):* LZ77 plus Huffman coding plus a
120 KB static dictionary of common web tokens. Targets web asset compression.
Chapter 32.

*Zstandard (Meta, 2016; RFC 8878):* LZ77 plus FSE (finite-state entropy, a
tANS-based coder). Tunable levels from −7 to 22. The modern default for
infrastructure. Chapter 32.

*LZMA (Igor Pavlov, 1998):* LZ77 with a very large dictionary (up to gigabytes)
and a range coder with elaborate context models. The engine of 7-Zip and xz.
Chapter 31.

=== LZ78 Branch: The Explicit-Table Family

The LZ78 branch is smaller and less dominant today, partly because of the patent
history and partly because LZ77-based approaches tend to achieve better ratios at
comparable speeds.

*LZW (Terry Welch, 1984):* The main LZ78 descendant covered in this chapter.
Still alive in legacy formats (TIFF, PDF, GIF).

*LZC:* The variant used in Unix `compress`, with configurable maximum code width
(9 to 16 bits).

*LZT:* A table-clearing variant that removes the least-recently-used entry when
the table is full, instead of clearing all entries. Better on data with drifting
statistics, at the cost of decoder complexity.

*LZTrie and Re-Pair:* Academic extensions studied in the context of compressed
data structures, relevant to the bioinformatics and text indexing communities.
The closely related machinery of compressed text indexing (suffix arrays and
the FM-index) is covered in Chapter 35 alongside the Burrows-Wheeler Transform.

=== Why Did the LZ77 Branch Win?

If LZ78/LZW is simpler and faster in hardware, why did LZ77 take over? Several
reasons:

1. *The patent shadow:* Between 1994 and 2004, LZW was legally hazardous.
   Open-source developers avoided it. The post-DEFLATE world of gzip, zlib, and
   PNG cemented LZ77 as the standard before LZW expired.

2. *Better compression on most real data:* LZ77's sliding window allows it to
   reference any position in the recent past, not just the phrases explicitly
   catalogued in the dictionary. On data with long-distance repetitions it
   outperforms LZW, which can only reference its current table.

3. *Composability:* Stacking LZ77 + entropy coding (DEFLATE) gives better
   results than LZW alone, because the token stream produced by LZ77 still has
   exploitable statistics that Huffman or arithmetic coding can compress further.
   LZW already "uses up" the entropy in its variable-width codes.

4. *Engineering momentum:* Phil Katz released DEFLATE and the gzip source code
   as essentially public domain. The zlib library (Gailly and Adler) made it
   trivial to embed in any project. Open, free, and good beats patented, free
   (eventually) but legally risky.

#misconception[
  "LZW is obsolete and no longer used."
][
  LZW is very much alive in legacy formats. TIFF files produced by professional
  scanners, PDF files with LZW-compressed streams, and of course animated GIFs
  (which remain enormously popular on social media) all use LZW. Modern decoders
  must support it. The algorithm is not "deprecated": it simply lost its
  dominant position in new format design, while surviving in established formats
  where backward compatibility matters more than algorithmic fashion.
]

== Compression Numbers: How LZW Compares

To calibrate intuition, here are typical compression ratios for LZW on different
types of data, using a 12-bit dictionary (4096 entries maximum):

#scoreboard(
  caption: "LZW on typical data (12-bit codes, 4096-entry dictionary)",
  [Uncompressed English text], [100%], [1.00×], [English runs ~4.5 bits/char entropy],
  [LZW on English text], [~58%], [~1.72×], [Dictionary fills fast; ratio varies 45–65%],
  [LZW on binary executables], [~65%], [~1.54×], [Less repetition than text],
  [LZW on GIF palette image], [~40%], [~2.5×], [Flat-color images compress very well],
  [LZW on already-compressed], [~102%], [~0.98×], [Near-random bytes; slight expansion],
  [gzip -6 on English text], [~37%], [~2.7×], [DEFLATE clearly outperforms LZW],
)

The key observation: LZW is noticeably worse than DEFLATE on text because it
lacks a second-stage entropy coder. The codes LZW produces are not uniform in
frequency: some phrases are much more common than others. Huffman coding,
as used in DEFLATE, exploits that non-uniformity. LZW passes up that
opportunity.

On palette-indexed images with large flat areas (GIF's sweet spot), LZW does
well because runs of the same color index build very long repeated sequences,
and the 12-bit dictionary captures them efficiently.

== The Legacy of the Patent Wars

The GIF/LZW episode left several lasting marks on the computing world, most of
them positive:

*Open standards culture:* The patent shock catalyzed a shift toward deliberately
open, unencumbered standards. The W3C adopted explicit policies requiring
royalty-free implementations of all web standards. RFC processes began including
patent disclosures. The open-source movement used the GIF/LZW episode for years
as a recruiting argument for patent-free code.

*PNG's technical improvements:* PNG is genuinely better than GIF in almost
every technical dimension except animation. It supports true color, alpha
transparency, and better compression. If the patent crisis had not occurred,
there would have been no market pressure to create PNG, and the web might have
remained stuck with 256-color images well into the 2000s.

*The APNG question:* PNG's lack of animation support left GIF as the only
portable animated image format for over a decade. APNG (Animated PNG) was
proposed in 2004 and finally achieved broad browser support around 2017–2019.
WebP (Google, 2010) added animation support too. But the animated GIF endured
and thrives on social media to this day. Format inertia is a powerful force that
technical inferiority alone cannot overcome.

*Sensitivity to software patents in compression:* The compression community
became acutely aware of patent risks. When Zstandard was designed, one of the
explicit engineering values was making sure the algorithm was well-documented and
the reference implementation was patent-free. When HEVC video compression turned
out to have a similarly messy patent landscape in the 2010s, the industry
responded by creating AV1, a deliberately open, royalty-free alternative
(Chapter 54).

The arc is consistent: patented formats create friction, open alternatives arise,
and the open alternatives eventually win in the long run. LZW and GIF were
simply the first large-scale proof of that dynamic in the internet era.

#history[
  Steve Wilhite, the creator of GIF, received a Webby Award for lifetime
  achievement in 2013, 26 years after he invented the format. In his brief
  acceptance speech (Webby Award rules allow only five words), he chose to settle
  a long-running internet debate: "It's pronounced JIF," he said.
  Whether he was right remains one of computing's most contentious unresolved
  questions.
]

== LZW in GIF: The Pixel-Level Mechanics

For completeness, let us look at exactly how GIF applies LZW at the image level,
because the GIF format has some twists not present in a generic LZW compressor.

=== Minimum Code Size and the Color Table

A GIF image has a *color table* (the palette) with $2^k$ entries, where $k$ is
typically 1 to 8. The index of each pixel into this palette is what gets
compressed. The LZW *minimum code size* is the number of bits per palette index
- typically $k$ or $k+1$ (GIF adds one extra bit to accommodate the CLEAR and EOI
codes without overlapping valid palette indices).

For a 256-color image ($k=8$), the minimum code size is 8. Initial codes 0–255
represent palette indices. Code 256 is the CLEAR code; code 257 is the
end-of-information code. LZW encoding starts at 9-bit codes and widens as the
dictionary grows.

=== Sub-block Packaging

GIF does not store the LZW-compressed bit stream raw. It packages it in
*sub-blocks*, each of which begins with a length byte (1–255) indicating how
many data bytes follow. A zero-length sub-block terminates the image data. This
sub-block structure was designed to allow GIF parsers to skip unknown extension
blocks without understanding their content, a forward-compatibility feature.

=== Bit Order

GIF packs bits into bytes in *LSB-first* (least-significant bit first) order.
This is opposite to most other binary formats (which are MSB-first). Every GIF
decoder must handle this. The first code's least-significant bit goes into the
first bit (bit 0) of the first byte. This detail is a common source of bugs in
from-scratch GIF implementations.

#gopython("Bytes and bit manipulation in Python")[
  Extracting LSB-first codes from a byte stream:

  ```python
  def read_lzw_codes_lsb(data: bytes, code_width: int) -> list[int]:
      """Read variable-width codes from bytes in LSB-first order."""
      codes: list[int] = []
      acc = 0
      bits_in_acc = 0
      byte_pos = 0
      while byte_pos < len(data):
          # accumulate bits from the next byte (LSB-first)
          acc |= data[byte_pos] << bits_in_acc
          bits_in_acc += 8
          byte_pos += 1
          while bits_in_acc >= code_width:
              codes.append(acc & ((1 << code_width) - 1))
              acc >>= code_width
              bits_in_acc -= code_width
      return codes

  # Example: decode 2 codes of width 9 from bytes 0x00, 0x01
  result = read_lzw_codes_lsb(bytes([0b00000000, 0b00000001]), 9)
  # First 9 bits: 000000000 → code 0
  # Next 9 bits: but only 7 bits remain, need more bytes for a real case
  ```

  Notice we use `acc |= data[byte_pos] << bits_in_acc`: each new byte's bit 0
  goes into the current accumulator at position `bits_in_acc`, which is *higher*
  than all the bits already in `acc`. This is the LSB-first convention.
]

== The LZW Decompression Race: A Brief History of Implementations

One interesting side effect of the GIF/LZW situation is the careful attention
paid to LZW *decompression* performance, since browsers needed to display GIF
images as fast as possible. The naive table-based approach described in this
chapter is straightforward but allocates many small string objects. Two
optimizations became standard:

=== Suffix Array Representation

Instead of storing phrases as Python `bytes` objects (which require heap
allocation for each entry), production decoders represent the dictionary as
two parallel arrays:

- `suffix[code]` = the last character of phrase `code`
- `prefix[code]` = the code for "phrase `code` minus its last character"

To decode a code, follow the `prefix` chain back to a single-character code
(a base case in 0–255), collecting `suffix` values along the way, then reverse.

```python
def lzw_decode_fast(codes: list[int]) -> bytes:
    """LZW decode using suffix/prefix arrays for efficiency."""
    MAX = 4096
    suffix = list(range(256)) + [0] * (MAX - 256)
    prefix = list(range(256)) + [0] * (MAX - 256)
    # initialize: codes 0..255 are single-byte phrases (prefix=self, suffix=self)

    CLEAR = 256
    EOI   = 257
    next_code = 258
    output = bytearray()
    prev = -1

    def decode_string(code: int) -> bytes:
        """Follow prefix chain to reconstruct phrase."""
        result = bytearray()
        c = code
        while c >= 256:
            result.append(suffix[c])
            c = prefix[c]
        result.append(c)   # base single-byte code
        result.reverse()
        return bytes(result)

    for code in codes:
        if code == CLEAR:
            next_code = 258
            prev = -1
            continue
        if code == EOI:
            break
        if prev == -1:
            output.extend(bytes([code]))
            prev = code
            continue

        if code < next_code:
            entry = decode_string(code)
        else:
            # KwKwK edge case
            prev_str = decode_string(prev)
            entry = prev_str + prev_str[0:1]

        output.extend(entry)

        if next_code < MAX:
            suffix[next_code] = entry[0]
            prefix[next_code] = prev
            next_code += 1

        prev = code

    return bytes(output)
```

The suffix/prefix representation uses two fixed arrays of 4096 integers, with no
heap allocation per phrase and much better cache behavior.

=== Dictionary Reuse

When the maximum dictionary size is reached and a CLEAR code is emitted, the
naive approach allocates a fresh dictionary. Production implementations simply
reset the `next_code` pointer and reuse the arrays; the old entries are
overwritten as new ones are added.

These optimizations transformed LZW from "academically neat" to "fast enough to
decode GIF frames in real-time on the hardware of 1990."

#aside[
  Modern GIF decoding speed is dominated by color conversion and palette lookup,
  not LZW decompression itself. A 1,000 × 1,000 pixel GIF has one million pixel
  indices to decompress and one million palette lookups to perform. The
  bottleneck has moved entirely to memory bandwidth.
]

== Thinking About LZW Compression Quality

Let us think carefully about *when* LZW works well and when it does not, because
the answer illuminates the design of every compressor that came after it.

=== When LZW Works Well

LZW works best when:

1. *Long repeated patterns exist.* The dictionary builds up long phrases, and
   those phrases recur. This is typical for palette-indexed images (GIF sweet
   spot), DNA sequences with repeated motifs, simple log files with repeated
   lines, and source code with repeated identifiers.

2. *The distribution is stable across the input.* LZW's dictionary fills up and
   then either freezes or clears. If the statistics of the data change sharply
   (e.g., one half of the file is English text and the other half is binary
   data), the dictionary built in the first half is unhelpful for the second.
   A clear-and-restart policy handles this but wastes the accumulated knowledge.

3. *Hardware simplicity matters.* LZW has no entropy-coding stage, no Huffman
   tree, no arithmetic state. It is a single table lookup per symbol. For the
   modem hardware of 1990, this simplicity was invaluable.

=== When LZW Struggles

LZW struggles when:

1. *The input is already compressed or random.* No repeated patterns means no
   useful dictionary entries. LZW will still try to compress, building a
   dictionary of meaningless byte pairs, and may even expand the data slightly.

2. *Short-range patterns dominate.* LZ77's sliding window is better at
   short-range repetitions because it can reference them directly without
   building a full table entry. LZW needs to see each pattern multiple times
   before the dictionary entry pays off.

3. *The dictionary ceiling is hit frequently.* On long inputs with diverse
   vocabulary (an English novel), the 12-bit dictionary fills quickly. Each
   CLEAR event throws away hard-won knowledge. Increasing the maximum code
   width helps but uses more bits per code.

#keyidea[
  The fundamental limitation of LZW is the absence of a second-stage entropy
  coder. The codes LZW emits have wildly different frequencies: some phrases
  recur thousands of times, while others appear only once, yet every code gets the same
  number of bits regardless. DEFLATE solves this by applying Huffman coding to
  the LZ77 token stream, squeezing out the remaining symbol-frequency redundancy.
  That is why DEFLATE beats LZW on almost every realistic input.
]

#gomaths("Variable-width code efficiency")[
  Suppose LZW produces a sequence of codes where half are 9-bit codes (the
  common phrases) and half are 12-bit codes (the rare ones). The average code
  width is $(9 + 12)/2 = 10.5$ bits per code.

  Now suppose we Huffman-coded those same codes. The common ones would get
  short codes (maybe 7 or 8 bits) and the rare ones would get longer codes
  (maybe 13 or 14 bits). If the top 20% of codes account for 80% of occurrences
  (a *Zipf-like* distribution), Huffman coding would save perhaps 1–2 bits per
  code on average.

  (*Zipf's law*, named after the linguist George Zipf, is the empirical
  observation that in many real datasets a handful of items are wildly more
  common than the rest: the most frequent item appears about twice as often as
  the second, three times as often as the third, and so on. Word frequencies in
  English, city sizes, and the codes a dictionary coder
  emits all follow roughly this shape. A few phrases dominate; most are rare.
  That lopsidedness is precisely what a second-stage entropy coder feeds on.)

  On a file producing 100,000 LZW codes, that is 100,000 to 200,000 fewer bits:
  12 to 25 KB of savings. For a file that started as, say, 200 KB of English
  text, that is a 6–12% improvement. This is exactly the gap between LZW and
  DEFLATE's typical performance on text.
]

== Chapter Summary: LZW in Context

LZW was a brilliant simplification of LZ78: cleaner, faster in hardware, and
good enough to dominate data transmission for a decade. It powered the dial-up
modem era (V.42bis), the early graphical internet (GIF), professional imaging
(TIFF), and Unix system administration (compress). That is an impressive record.

Its downfall was not technical but legal. The patent created seventeen years of
friction, during which the open-source world built and refined DEFLATE-based
tools that ultimately surpassed LZW on almost every technical measure. By the
time the patent expired in 2003–2004, DEFLATE, gzip, zlib, and PNG were deeply
embedded in every part of the internet. LZW had lost the race to its own
patent-driven exile.

The story is not entirely sad. The GIF/LZW crisis made the internet more open:
PNG is genuinely better than GIF (except for animation), DEFLATE is genuinely
better than LZW, and the open-standards culture that hardened around the crisis
continues to benefit computing today.

In the next chapter we cross to the LZ77 branch and build *DEFLATE* from its
component parts: the hash-chain match finder, the dynamic Huffman tree, and the
block structure that lets gzip handle streams of arbitrary length. That is the
compressor that actually won.

#takeaways((
  "LZW modifies LZ78 by emitting only dictionary indices (no trailing symbol), making the encoder output cleaner and hardware-friendly.",
  "Both encoder and decoder maintain identical dictionaries by starting from the same 256-entry initialization and building new entries from received codes.",
  "The 'KwKwK' edge case occurs when the decoder receives a code equal to the next-to-be-assigned index; the entry is reconstructed as the previous phrase extended by its own first byte.",
  "LZW appeared in Unix compress, GIF (1987), TIFF, and V.42bis; it was ubiquitous in the 1990s.",
  "The Unisys patent (US 4,558,302, December 1985) covered LZW. After enforcement began in December 1994, PNG was designed in January 1995 as a royalty-free alternative using DEFLATE.",
  "PNG uses DEFLATE (LZ77 + Huffman), which is both patent-free and technically superior to LZW on most data.",
  "LZW's key weakness is the absence of a second-stage entropy coder: variable-frequency codes are all emitted at the same width, leaving exploitable redundancy.",
  "The GIF/LZW episode catalyzed the open-standards and royalty-free culture that shapes internet format design to this day.",
))

== Exercises

#exercise("29.1", 1)[
  Trace the LZW encoding of the string `AAABBBAAABBB` on an alphabet of
  (A=0, B=1, \#=2). Show each step: the current phrase W, the character c read,
  whether W+c is in the dictionary, the emitted code (if any), and the new
  dictionary entry added. What is the final output code sequence?
]
#solution("29.1")[
  Start: D = \{0:A, 1:B, 2:\#\}, next free code = 3, W = "".

  Step 1: c=A. W+c = "A" -- in D (code 0). W = "A".
  Step 2: c=A. W+c = "AA" -- not in D. Emit 0 (A). D[3]="AA". W="A".
  Step 3: c=A. W+c = "AA" -- in D (code 3). W = "AA".
  Step 4: c=B. W+c = "AAB" -- not in D. Emit 3 (AA). D[4]="AAB". W="B".
  Step 5: c=B. W+c = "BB" -- not in D. Emit 1 (B). D[5]="BB". W="B".
  Step 6: c=B. W+c = "BB" -- in D (code 5). W = "BB".
  Step 7: c=A. W+c = "BBA" -- not in D. Emit 5 (BB). D[6]="BBA". W="A".
  Step 8: c=A. W+c = "AA" -- in D (code 3). W = "AA".
  Step 9: c=A. W+c = "AAA" -- not in D. Emit 3 (AA). D[7]="AAA". W="A".
  Step 10: c=B. W+c = "AB" -- not in D. Emit 0 (A). D[8]="AB". W="B".
  Step 11: c=B. W+c = "BB" -- in D (code 5). W = "BB".
  Step 12: c=B. W+c = "BBB" -- not in D. Emit 5 (BB). D[9]="BBB". W="B".
  Flush: Emit 1 (B).

  Output sequence: *0, 3, 1, 5, 3, 0, 5, 1*.
  Eight codes for twelve characters.
]

#exercise("29.2", 1)[
  Decode the LZW code sequence `0, 1, 3, 4, 1` on an alphabet of (A=0, B=1, \#=2).
  Show the dictionary state after processing each code, the output produced, and
  how the final output string is assembled.
]
#solution("29.2")[
  Init: D = \{0:A, 1:B, 2:\#\}, next=3, prev=none.

  Code 0: output "A". prev="A".
  Code 1: entry=D[1]="B". output "B". D[3] = prev + entry[0] = "A"+"B" = "AB". next=4. prev="B".
  Code 3: entry=D[3]="AB". output "AB". D[4] = prev + entry[0] = "B"+"A" = "BA". next=5. prev="AB".
  Code 4: entry=D[4]="BA". output "BA". D[5] = prev + entry[0] = "AB"+"B" = "ABB". next=6. prev="BA".
  Code 1: entry=D[1]="B". output "B". D[6] = prev + entry[0] = "BA"+"B" = "BAB". next=7. prev="B".

  Total output: "A" + "B" + "AB" + "BA" + "B" = "ABABBAB".
]

#exercise("29.3", 2)[
  Explain the KwKwK edge case in LZW decoding. Construct a specific byte string
  that triggers this edge case when compressed with LZW. Trace both the encoding
  and decoding to show how the edge case arises and is resolved. Your example must
  have at least 6 characters.
]
#solution("29.3")[
  The KwKwK edge case occurs when the decoder receives a code equal to
  `next_code`, the index that will be assigned to the *next* new entry, which
  the decoder has not added yet. It happens whenever the encoder *defines* a new
  phrase and then emits its code *as the very next output*. Concretely, this
  arises for input of the form `c X c X c` (a character, some block, the same
  character, the same block, that character again): the encoder defines the
  phrase `c X c`, then immediately matches and emits it. The simplest such input
  is a run of one repeated character.

  *Triggering input:* `AAAAAA` on alphabet (A=0). Six characters, easily clears
  the six-character requirement.

  Encoding (start: D=\{0:A\}, next=3, W=""):
  - c=A → W="A"
  - c=A: "AA" not in D → *emit 0*, D[3]="AA", W="A"
  - c=A: "AA" in D (code 3) → W="AA"
  - c=A: "AAA" not in D → *emit 3*, D[4]="AAA", W="A"
  - c=A: "AA" in D (code 3) → W="AA"
  - c=A: "AAA" in D (code 4) → W="AAA"
  - Flush: *emit 4* (AAA)

  Output codes: *0, 3, 4*.

  Decoding `0, 3, 4` (start: D=\{0:A\}, next=3):
  - Code 0: first code → output "A", prev="A".
  - Code 3: is $3 < "next"=3$? *No: code equals next, triggering the edge case.* The entry
    D[3] does not exist in the decoder's table yet. Reconstruct it as
    `D[prev] + first(D[prev])` = "A"+"A" = "AA". Output "AA". Now add
    D[3] = D[prev]+first(entry) = "A"+"A" = "AA". next=4, prev="AA".
  - Code 4: is $4 < "next"=4$? *No: the edge case again.* Reconstruct
    `D[prev] + first(D[prev])` = "AA"+"A" = "AAA". Output "AAA". Add
    D[4] = "AA"+"A" = "AAA". next=5, prev="AAA".
  - Total output: "A"+"AA"+"AAA" = "AAAAAA". ✓

  Both code 3 and code 4 hit the edge case, and in each instance the formula
  `entry = D[prev] + D[prev][0:1]` rebuilds the missing phrase exactly. This is
  why every correct LZW decoder must check for `code == next_code` *before*
  looking the code up in its table.
]

#exercise("29.4", 2)[
  The LZW algorithm uses a maximum code width (often 12 bits, giving 4096 entries).
  When the dictionary fills up, one strategy is to emit a CLEAR code and start fresh.
  Another is to freeze the dictionary (stop adding entries) and keep using existing ones.

  (a) Give an example of a data type where freeze-and-keep performs better than
  clear-and-restart. (b) Give an example where clear-and-restart performs better.
  (c) Explain why GIF chose clear-and-restart rather than freeze-and-keep.
]
#solution("29.4")[
  (a) *Freeze-and-keep is better* for data with a *stable, bounded vocabulary*, for example, a log file that repeatedly writes the same set of messages in the same order. Once the dictionary captures all recurring phrases, freezing preserves them. A clear would discard useful entries and require re-learning.

  (b) *Clear-and-restart is better* for data whose statistics change dramatically, for example, a file that is half English text and half compiled binary code. The dictionary built in the first half is useless in the second. A clear at the transition point lets the dictionary adapt to the new statistics.

  (c) GIF images are typically small enough that the 4096-entry dictionary is rarely hit, and when it is, the image is nearly done. Clear-and-restart is simpler to implement in both encoder and decoder, and GIF was designed for hardware decoders of the late 1980s where simplicity was essential. GIF images can also be interleaved with CLEAR codes at the encoder's discretion (not only when the table is full), giving the encoder flexibility to reset whenever it detects a drop in compression ratio.
]

#exercise("29.5", 2)[
  Write a Python function `lzw_compress_ratio(data: bytes) -> float` that
  encodes `data` using the `lzw_encode` function from this chapter and returns
  the compression ratio (output\_bits / input\_bits). Assume each output code
  uses exactly `ceil(log2(max_code))` bits (not variable-width). Test your
  function on:
  (a) `b"ABCABCABC" * 10` (90 bytes),
  (b) `bytes(range(256))` (256 bytes of all distinct values),
  (c) `b"A" * 256` (256 identical bytes).
  For each, is the ratio above or below 1.0? Explain why.
]
#solution("29.5")[
  ```python
  import math
  # Assumes lzw_encode is imported from the demo code in this chapter.

  def lzw_compress_ratio(data: bytes, max_bits: int = 12) -> float:
      codes = lzw_encode(data, max_bits=max_bits)
      # Use fixed-width codes at the maximum width for simplicity
      bits_out = len(codes) * max_bits
      bits_in  = len(data) * 8
      return bits_out / bits_in

  for label, data in [
      ("ABC*10", b"ABCABCABC" * 10),
      ("0..255", bytes(range(256))),
      ("A*256", b"A" * 256),
  ]:
      r = lzw_compress_ratio(data)
      print(f"{label}: ratio = {r:.3f}  ({'expansion' if r > 1 else 'compression'})")
  ```

  Expected results:
  - `ABC*10` (90 bytes, highly repetitive): ratio ≈ 0.60 (compression). After the
    first pass through `ABCABC...`, the dictionary holds "ABC", "BCA", "CAB", etc.
    and long phrases are emitted as single codes.
  - `bytes(range(256))` (256 all-distinct bytes): ratio > 1.0 (slight expansion).
    No repetitions; every byte is a new phrase. With 12-bit output codes and 8-bit
    input, the ratio is approximately 12/8 = 1.5, significant expansion.
  - `A*256` (256 identical bytes): ratio ≈ 0.20 (strong compression). After the
    first few bytes, the dictionary quickly builds "AA", "AAA", "AAAA", etc. and
    the entire run is encoded in very few codes.
]

#exercise("29.6", 3)[
  *Patent-free design exercise.* You are designing a new compressed image format
  in 1995. LZW is patented. You want a format that:
  (a) Compresses GIF-style palette-indexed images at least as well as LZW,
  (b) Is unambiguously patent-free, and
  (c) Can be decoded in hardware with modest resources.

  Describe your compression scheme in detail. Which algorithm would you choose?
  How would you handle the color table? What code sizes would you use? What
  are the trade-offs compared to LZW? (You may describe the approach that was
  actually used for PNG, or propose a different valid design.)
]
#solution("29.6")[
  *Design: DEFLATE-based palette image compression (the PNG approach)*

  Choose DEFLATE (LZ77 + Huffman coding) as the compression algorithm. DEFLATE
  was specified in RFC 1951 by Philip Katz and Peter Deutsch, with zlib bindings
  in RFC 1950, completely unencumbered.

  *Handling the color table:* Store the color table (palette) as uncompressed
  RGB triples at the start of the file, just as GIF does. The image data is
  stored as one palette index per pixel, just as in GIF.

  *Pre-filtering:* Before compressing, apply a *filter* to each row of pixels.
  PNG defines five filters: None, Sub (difference from left neighbor), Up
  (difference from row above), Average (average of left and above), and Paeth
  (a predictor mixing left, above, and upper-left). The encoder picks the filter
  that minimizes the entropy of the filtered row. For images with smooth gradients
  or repetitive patterns, filters dramatically increase DEFLATE's effectiveness.
  This is unique to PNG and LZW does not have an equivalent.

  *Compression:* Apply DEFLATE to the filtered byte stream. Use a 32 KB sliding
  window (LZ77 back-references up to 32 KB back) plus Huffman coding of the
  (literal, length, distance) token stream.

  *Code sizes:* DEFLATE uses variable-width Huffman codes (1–15 bits) and LZ77
  back-reference distances up to 32 KB, much larger than LZW's 12-bit limit of
  4096 dictionary entries.

  *Trade-offs vs. LZW:*
  - Better compression, especially for photographic/complex images.
  - Filters allow DEFLATE to exploit inter-pixel correlations that LZW cannot.
  - Decoding requires a Huffman tree and LZ77 back-reference buffer, which is
    slightly more complex than LZW's table lookup.
  - No patent issues.
  - Supports true 24-bit or 48-bit color (PNG), not limited to 256-color palettes.

  This is exactly what PNG did, and it proved technically superior in every
  dimension where technical measures matter.
]

== Further Reading

- #link("https://ieeexplore.ieee.org/document/1659158")[Welch, T. A. (1984). "A Technique for High-Performance Data Compression." _IEEE Computer_, 17(6), 8--19.] The original LZW paper; short, readable, and historically important.

- #link("https://en.wikipedia.org/wiki/Lempel%E2%80%93Ziv%E2%80%93Welch")[Lempel-Ziv-Welch on Wikipedia.] Good overview including the GIF history and patent timeline.

- #link("https://groups.csail.mit.edu/mac/projects/lpf/Patents/Gif/Gif.html")[The Unisys/CompuServe GIF Controversy, League for Programming Freedom.] Primary source documents from the 1994–1995 patent enforcement period.

- #link("https://groups.csail.mit.edu/mac/projects/lpf/Patents/Gif/origCompuServe.html")[Original CompuServe GIF Patent Announcement (December 1994).] The actual announcement text that triggered the patent war.

- #link("http://www.libpng.org/pub/png/pnghist.html")[History of the PNG Format, libpng.org.] A detailed chronology of PNG's creation from January 1995 through the W3C approval.

- #link("https://www.rfc-editor.org/rfc/rfc1951.txt")[RFC 1951: DEFLATE Compressed Data Format Specification.] The patent-free alternative that PNG chose, and that the internet still runs on today.

- #link("https://giflib.sourceforge.net/whatsinagif/lzw_image_data.html")[What's In a GIF: LZW Image Data.] A detailed walkthrough of exactly how GIF applies LZW at the byte level, including sub-block packaging.

- #link("https://www.eecis.udel.edu/~amer/CISC651/lzw.and.gif.explained.html")[LZW and GIF Explained, by Steve Blackstock.] A classic tutorial on LZW and its GIF application, widely used for its clarity.

- #link("https://ieeexplore.ieee.org/document/1055934")[Ziv, J. & Lempel, A. (1978). "Compression of Individual Sequences via Variable-Rate Coding" (LZ78). _IEEE Transactions on Information Theory_, 24(5).] The LZ78 paper that LZW descends from.

#bridge[
  LZW showed that dictionary coding could power a visual medium, but it also
  showed the limits of a table-based approach without a second entropy-coding
  stage. In *Chapter 30* we build *DEFLATE*, the algorithm that fixed both of
  those limits. DEFLATE combines LZ77's sliding-window back-references (from
  Chapter 28) with dynamic Huffman coding (Chapter 24) and a block structure
  that handles arbitrary-length streams. It is the compressor behind gzip, zlib,
  ZIP, and PNG. Three decades after its creation, it remains one of the
  most deployed pieces of software in human history. We will build it from
  scratch, one component at a time, and add it as Step 13 of tinyzip: your
  first gzip-class compressor.
]
