#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= A Python Primer III — Bytes, Bits, Files, and Binary I/O

#epigraph[All programming is an exercise in caching.][Terje Mathisen]

Here is a small, deflating fact that every beginner discovers the hard way. You spend a happy afternoon writing a compressor. It reads your text, counts the symbols, builds beautiful short codes for the common ones, and — on screen — prints a triumphant `"01101001..."`. You feel like a wizard. Then you try to *save the result to a file* and realise, with a sinking feeling, that you have been printing the *letters* `0` and `1`. A string `"01101001"` is eight characters, eight whole bytes, sixty-four bits — to spell out one byte's worth of actual information. Your "compressor" has made the file *eight times bigger*.

This chapter is the cure. It is the bridge between the comfortable world of Chapters 15 and 16 — text, lists, dictionaries, functions — and the unglamorous, exact, byte-level reality in which real compressed files actually live. A compressed file is not text. It is a stream of bytes, and inside those bytes is a stream of *bits* that do not respect byte boundaries at all: a Huffman code might be three bits long, the next five, the next eleven, packed shoulder to shoulder with no gaps. To emit such a file you must learn to think below the byte, to set and read individual bits, and to write the result as genuine binary — not as a string of ones and zeros, but as the bytes those bits actually are.

By the end of this chapter you will have built the two small machines that the entire rest of `tinyzip` depends on: a `BitWriter` that accepts bits one or several at a time and packs them tightly into bytes, and a `BitReader` that pulls them back out in the same order. Every codec in Volume II — Huffman, arithmetic coding, LZ77, DEFLATE — is, at the very bottom, a clever way of deciding *which* bits to feed these two machines. Get them right, and the rest is decoration.

#recap[
This is the last of our three Python chapters, and it cashes in everything the first two built. From *Chapter 15* we keep values, names, `if`, `while`, `for`, `range`, f-strings, and the walrus operator `:=` — which finally earns its keep here, reading a file chunk by chunk. From *Chapter 16* we keep lists, `dict`, `bytes` (which we met only briefly), functions with type hints like `def f(x: int) -> bytes`, `match`, and generators. We also lean hard on *Chapter 4* (binary place value), *Chapter 5* (the logic operators `and`, `or`, `xor`, `not`, now reborn as the _bitwise_ operators `&`, `|`, `^`, `~`), and especially *Chapter 13* (How Computers Represent Things), which gave us bytes, ASCII, two's-complement integers, and endianness. Chapter 13 told us _what_ the bytes mean; this chapter teaches Python to _read and write_ them.
]

#objectives((
  [Tell apart `str` (text) and `bytes` (raw data), and convert between them safely with `.encode()` and `.decode()`,],
  [Build and inspect immutable `bytes` and the mutable `bytearray`, indexing them to get integers `0`–`255`,],
  [Use the six _bitwise operators_ `&`, `|`, `^`, `~`, `<<`, `>>` to set, clear, test, and shift individual bits,],
  [Read and write real _binary files_ with `open(..., "rb")` / `"wb"`, and stream them in chunks with the walrus operator,],
  [Pack and unpack fixed-size integer fields with the `struct` module, choosing endianness on purpose,],
  [Convert between integers and bytes directly with `int.to_bytes` and `int.from_bytes`,],
  [Build, from scratch, a `BitWriter` and `BitReader` — the bit-level I/O engine the whole `tinyzip` project rests on,],
  [Write a complete, round-trip file header for `tinyzip` and verify that what you write is exactly what you read back.],
))

== Two kinds of sequence: `str` and `bytes`

In Chapter 15 we met the string, `str`, and treated it as our data. That was a useful simplification for learning loops and `if`-statements, but it hides a distinction that becomes critical the moment you touch a file. There are *two* fundamentally different kinds of sequence in Python, and confusing them is the single most common source of frustration when people first write real I/O code.

A `str` is a sequence of *characters* — abstract letters, digits, symbols, emoji. The string `"café"` has four characters, and Python does not commit to any particular pattern of bytes for them until you ask it to. A `bytes` object, by contrast, is a sequence of *raw 8-bit numbers*, each from 0 to 255 — exactly the bytes that live in memory and on disk. The string `"café"` is text; its UTF-8 encoding `b"caf\xc3\xa9"` is five bytes of data. One is the idea; the other is the physical representation. Compression lives entirely in the world of `bytes`.

#gopython("The `bytes` literal: `b\"...\"`")[
You write a `bytes` value by putting the letter `b` immediately before a quote — the byte-world cousin of the f-string's `f`. Inside, ordinary ASCII characters stand for their byte values, and any byte can be written explicitly as `\xHH`, two hex digits:

```python
>>> data = b"AB"          # two bytes: 65 and 66
>>> data
b'AB'
>>> len(data)
2
>>> b"\x00\xff"           # the bytes 0 and 255, written in hex
b'\x00\xff'
>>> b"hi\n"               # escapes work too: this is h, i, newline
b'hi\n'
```

A `bytes` literal looks like a string with a `b` glued on, and that is deliberate — but never forget the difference underneath. `b"AB"` is two *numbers*, 65 and 66, that happen to print as letters because they fall in the printable ASCII range. A byte like `\xff` (255) has no printable character, so Python shows it in hex. We will use `b"..."` constantly to write the magic numbers and headers of `tinyzip`'s file format.
]

The two types deliberately refuse to mix. You cannot add a `str` to a `bytes`, cannot search for one inside the other, cannot write a `str` to a file opened in binary mode. Python forces you to *convert on purpose*, and that friction is a feature: it stops you from accidentally treating text as raw data or vice versa, the bug behind a thousand mangled files and "mojibake" web pages.

#gopython("Crossing the bridge: `.encode()` and `.decode()`")[
To turn text into bytes you must choose an *encoding* — a rulebook mapping characters to byte sequences. The universal modern choice is UTF-8, which we met in Chapter 13. The string method `.encode()` applies it; the bytes method `.decode()` reverses it:

```python
>>> "café".encode("utf-8")      # text  -> bytes
b'caf\xc3\xa9'
>>> b'caf\xc3\xa9'.decode("utf-8")   # bytes -> text
'café'
>>> "café".encode("utf-8").__len__()
5
```

The `é` becomes *two* bytes (`\xc3\xa9`), which is why the four-character string `"café"` encodes to five bytes — the very point of Chapter 13's UTF-8 discussion, now in code. UTF-8 is the default, so `"café".encode()` works too. The rule to live by: *text comes in through `.encode()`, results go out through `.decode()`, and everything in between — every byte a compressor touches — is `bytes`.* If you ever see a `TypeError` complaining that you mixed `str` and `bytes`, you forgot to cross this bridge.
]

#pitfall[
A string of the characters `"0"` and `"1"` is *not* a sequence of bits. `"01000001"` is eight characters — eight bytes — that spell out a binary number for human eyes. The single byte it *represents* is `0b01000001 = 65 = b"A"`. Printing bits as text is a fine way to *debug*, but if you ever write those character-strings to a file as your "compressed output," you have inflated your data eightfold. Real bit-packing, which this chapter builds, turns eight bit-values into *one* byte.
]

#misconception[that a file "contains text."][Every file on disk is, without exception, a sequence of bytes — raw numbers 0–255. A "text file" is simply a file whose bytes happen to be a valid encoding of characters under some agreed scheme (usually UTF-8). A compressed file, an image, an executable: same bytes, different meaning. There is no text on a disk, only bytes and the conventions we read them with. This is why `tinyzip` opens every file in *binary* mode and never pretends otherwise.]

== Indexing bytes: a sequence of small integers

Here is the fact that makes `bytes` so natural for compression. When you index a single element of a `bytes` object, you do not get a one-character `bytes` back — you get a plain `int`, the numeric value of that byte, from 0 to 255. A `bytes` object is, for all practical purposes, an immutable list of small integers that prints itself prettily.

```python
>>> data = b"ABC"
>>> data[0]           # NOT b'A' — the integer 65
65
>>> data[1]
66
>>> data[-1]          # negative indexing works, as with strings
67
>>> for b in b"Hi":   # looping yields integers
...     print(b)
72
105
```

This is exactly what a compressor wants. It does not care that byte 65 prints as `"A"`; it cares that 65 is a *symbol* it can count, predict, and code. Looping over a `bytes` object hands you each byte's value directly, ready to drop into the frequency histogram we built in Chapter 16. The bridge functions `ord` and `chr` from Chapter 15 are no longer needed — the integers are right there.

#gopython("Slicing `bytes`: `data[i:j]`")[
Slicing, which you met for strings and lists in Chapter 16, works identically on `bytes` and gives you back a *shorter `bytes`* (not an int). The slice `data[i:j]` runs from position `i` up to *but not including* `j`:

```python
>>> data = b"compress"
>>> data[0:4]          # first four bytes
b'comp'
>>> data[4:]           # from position 4 to the end
b'ress'
>>> data[-3:]          # the last three bytes
b'ess'
>>> data[::2]          # every second byte (step of 2)
b'cmrs'
```

Note the asymmetry, and learn it cold: *indexing one position gives an `int`* (`data[0]` is `99`), but *slicing a range gives `bytes`* (`data[0:1]` is `b'c'`). This trips up everyone once. Slicing is how an LZ77 match finder will grab a window of recent bytes, and how our file reader will peel a header off the front of a stream.
]

#gomaths("Why bytes run 0 to 255")[
A byte is 8 bits, and each bit is an independent yes/no choice — a 0 or a 1. We proved in Chapter 4 (place value) and Chapter 8 (counting) that $n$ independent binary choices produce $2^n$ distinct patterns. For a byte, that is
$ 2^8 = 256 $
distinct patterns. We number them starting from zero, as Python numbers everything, so the values run $0, 1, 2, dots, 255$ — the largest being $2^8 - 1 = 255$. This is why every element of a `bytes` object is guaranteed to satisfy $0 <= b <= 255$, and why the moment a calculation tries to store 256 in a byte, something must give: it wraps to 0, the two's-complement wrap-around of Chapter 13. Keeping byte values inside $[0, 255]$ is a constant, quiet discipline in codec code.
]

== When you need to change bytes in place: `bytearray`

A `bytes` object is *immutable* — once made, it can never be altered, exactly like a `str` or a `tuple`. That is perfect for data you only read, but a compressor spends much of its life *building* output one byte at a time, and you cannot grow or edit an immutable thing. For that, Python offers the `bytearray`: a `bytes` object's mutable twin. It holds the same small integers 0–255, but you can append to it, change individual bytes, and grow it as you go.

#gopython("`bytearray`: the editable buffer")[
You create a `bytearray` from a `bytes` value, from a list of integers, or empty with a length. Unlike `bytes`, you can assign to a position and `.append()` new bytes:

```python
>>> buf = bytearray()         # an empty, growable buffer
>>> buf.append(65)            # add the byte 65 ("A")
>>> buf.append(66)
>>> buf
bytearray(b'AB')
>>> buf[0] = 90               # change a byte in place: 90 is "Z"
>>> buf
bytearray(b'ZB')
>>> bytearray([72, 105])      # build from a list of ints
bytearray(b'Hi')
>>> bytes(buf)                # freeze it back into immutable bytes
b'ZB'
```

A `bytearray` is to `bytes` what a `list` is to a `tuple`: the mutable version of the same idea. The pattern we will use everywhere is "build in a `bytearray`, then freeze with `bytes(...)` when done." `buf.append(value)` is how our `BitWriter` will emit each finished byte, and assigning `buf[i] = v` lets us patch a length field *after* we know the length — a trick every real file format uses.
]

#keyidea[
Three closely related types, one mental model. `bytes` is an *immutable* sequence of integers 0–255 (read-only data, like a finished compressed block). `bytearray` is the *mutable* version (a buffer you build up). Indexing either gives a plain `int`; slicing either gives back the same type. Reach for `bytearray` while constructing output, then call `bytes(...)` to freeze it. Everything `tinyzip` writes is born in a `bytearray` and dies as `bytes`.
]

#checkpoint[If `data = b"hello"`, what are the types and values of `data[1]` and `data[1:2]`?][`data[1]` is the *integer* `101` (the byte value of `"e"`). `data[1:2]` is the *bytes* object `b'e'`. Indexing one position yields an `int`; slicing a range yields `bytes`. Same byte, two different types.]

== Looking at the bytes: hex, hex dumps, and inspection

In Chapter 13 we promised that, by the time you could read a *hex dump*, you would have the literacy of a codec engineer. This is where Python makes that practical. The trouble with raw `bytes` is that most byte values do not correspond to a printable character — `b"\x03\xe8\x00\xff"` is a wall of escapes, hard to read and easy to mis-count. The universal cure, used by every debugger and file-inspection tool ever made, is to show each byte as *two hexadecimal digits*, in neat columns. Python gives us the conversions for free.

#gopython("`bytes.hex()` and `bytes.fromhex()`")[
The `bytes` type carries a `.hex()` method that renders every byte as two hex digits, and a matching `bytes.fromhex(...)` that reads such a string back into bytes. This is the cleanest way to *print*, *log*, or *paste* binary data:

```python
>>> b"\x03\xe8\x00\xff".hex()        # bytes -> readable hex text
'03e800ff'
>>> b"\x03\xe8".hex(" ")             # group with a separator
'03 e8'
>>> bytes.fromhex("03 e8 00 ff")     # hex text -> bytes (spaces ok)
b'\x03\xe8\x00\xff'
>>> bytes.fromhex("48656c6c6f")      # "Hello" in hex
b'Hello'
```

Each byte becomes exactly two hex digits because one hex digit is a *nibble* (4 bits) and a byte is two nibbles — the relationship from Chapter 4. Passing a separator to `.hex(" ")` spaces the bytes out for reading. `.hex()` is how `tinyzip`'s test output will show what it actually wrote, so a wrong byte leaps off the screen instead of hiding inside a string of escapes.
]

A *hex dump* is the classic side-by-side view: an address column, the raw bytes in hex, and an ASCII rendering of any printable bytes. It is how you read a file's true contents, and it is a dozen lines of the Python you already know. Writing one is the perfect exercise in `bytes` slicing, `range` with a step, and f-string formatting.

```python
def hexdump(data: bytes, width: int = 16) -> None:
    """Print a classic offset / hex / ASCII dump of data."""
    for off in range(0, len(data), width):          # one row per 16 bytes
        chunk = data[off:off + width]               # slice this row's bytes
        hexs = " ".join(f"{b:02x}" for b in chunk)  # each byte as 2 hex digits
        # printable ASCII (32..126) shown as-is; others as a dot
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print(f"{off:08x}  {hexs:<48}  {text}")
```

Feeding it our eight-byte header plus a little payload prints the kind of view a professional stares at all day:

```python
>>> hexdump(b"TZ\x01\x00\x00\x00\x00\x0e\xac\xf0")
00000000  54 5a 01 00 00 00 00 0e ac f0                     TZ........
```

Read across: offset `00000000`, then the bytes — `54 5a` is the magic `"TZ"`, `01` the version, `00` the method (0 = stored), `00 00 00 0e` the 4-byte length (14), and `ac f0` the payload. The ASCII column on the right shows `TZ` and dots for the unprintable bytes. *This* is the literacy the whole book has been building toward: you can now look at a blob of bytes and tell the story of each one — which is the size, which is the magic, which is the data.

#gomaths("Why one byte is exactly two hex digits")[
Hexadecimal is base 16: its digits are `0`–`9` then `a`–`f`, sixteen symbols in all. One hex digit therefore encodes $16 = 2^4$ values — exactly a *nibble*, 4 bits. A byte is 8 bits, which is two nibbles, so it takes exactly $8 \/ 4 = 2$ hex digits to write any byte, from `00` (0) to `ff` (255). This clean two-digits-per-byte fit is *why* programmers reach for hex rather than decimal when looking at raw data: the byte boundaries line up perfectly with the digit boundaries, so you can read a multi-byte field straight off the page. In decimal, where $255$ takes three digits and $7$ takes one, the columns would never line up. Hex is the natural notation for bytes precisely because $16 = 2^4$ divides 8 evenly.
]

#tryit[
Type the `hexdump` function into a file and run it on `b"Hello, tinyzip!\n"` and on `(1000).to_bytes(4, "big")`. In the first you will see the ASCII column spell out the message; in the second you will see `00 00 03 e8` — the big-endian 1000 — with dots in the ASCII column because those bytes are not printable. Now run it on `(1000).to_bytes(4, "little")` and watch the bytes reverse to `e8 03 00 00`. Seeing endianness with your own eyes makes it stick.
]

== Working below the byte: the bitwise operators

So far we have treated each byte as a single number. To compress, we must go one level deeper and manipulate the *individual bits* inside that number. Python gives us six operators for exactly this. They are the same logic operations we built truth tables for in Chapter 5 — `and`, `or`, `xor`, `not` — but applied *bit by bit, in parallel, across a whole number*. That is why they are called the *bitwise* operators, and why they have their own symbols, distinct from the logical `and`/`or`/`not`.

Here is the whole family at a glance. We will then take each one slowly, because these six symbols are the alphabet of all bit-level code.

#table(columns: (auto, 1fr, auto), inset: 6pt, align: (center, left, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Operator*], [*Name and meaning*], [*Example → result*]),
  [`&`], [bitwise AND — 1 only where *both* bits are 1], [`0b1100 & 0b1010` → `0b1000`],
  [`|`], [bitwise OR — 1 where *either* bit is 1], [`0b1100 | 0b1010` → `0b1110`],
  [`^`], [bitwise XOR — 1 where the bits *differ*], [`0b1100 ^ 0b1010` → `0b0110`],
  [`~`], [bitwise NOT — flip every bit], [`~0b1100` → `-13` (see below)],
  [`<<`], [left shift — move bits up, filling with 0], [`0b0011 << 2` → `0b1100`],
  [`>>`], [right shift — move bits down, dropping the low ones], [`0b1100 >> 2` → `0b0011`],
)

#gopython("Writing numbers in binary and hex: `0b` and `0x`")[
To talk about bits, you need to *write* numbers in binary. Python lets you write a number in binary by prefixing `0b`, and in hexadecimal (base 16, each digit a nibble) by prefixing `0x`. These are just different *spellings* of the same integer — Python stores and prints them as ordinary decimals unless you ask otherwise:

```python
>>> 0b1010          # binary 1010
10
>>> 0xFF            # hex FF
255
>>> 0b1010 == 10    # same number, two spellings
True
>>> bin(10)         # show an int's binary spelling (as a str)
'0b1010'
>>> hex(255)        # show its hex spelling
'0xff'
>>> f"{10:08b}"     # format as 8-bit binary, zero-padded
'00001010'
```

The last line is the workhorse for *debugging* bit code: `f"{value:08b}"` prints any value as exactly eight binary digits, padded with leading zeros, so you can *see* the bits line up. We will scatter these through `tinyzip`'s test output. Remember the Pitfall, though: `f"{10:08b}"` produces the *text* `'00001010'`, useful for your eyes — not the byte it represents.
]

=== AND, OR, XOR: combining two numbers bit by bit

The first three operators take two numbers and combine them one bit-position at a time, using the truth tables of Chapter 5. Line the two numbers up in binary; for each column, apply the rule; read off the result.

*AND* (`&`) puts a 1 in the result only where *both* inputs have a 1. Everywhere else, 0. Think of it as a filter: it keeps only the bits that are set in both numbers.

```python
>>> a = 0b1100      # 12
>>> b = 0b1010      # 10
>>> a & b           # 1 only in columns where BOTH are 1
8
>>> bin(a & b)
'0b1000'
```

*OR* (`|`) puts a 1 where *either* input has a 1 — it merges the set bits of both numbers. *XOR* (`^`, "exclusive or") puts a 1 only where the two bits *differ* — same gives 0, different gives 1.

```python
>>> bin(0b1100 | 0b1010)    # OR: union of the set bits
'0b1110'
>>> bin(0b1100 ^ 0b1010)    # XOR: 1 where they disagree
'0b110'
```

#fig([The three combining operators, applied column by column to `1100` and `1010`. AND keeps bits set in both; OR keeps bits set in either; XOR keeps bits where the two disagree.], cetz.canvas({
  import cetz.draw: *
  let cell(x, y, t, col) = { rect((x, y), (x+0.7, y+0.7), fill: col); content((x+0.35, y+0.35), text(size: 9pt)[#t]) }
  let lbl(x, y, t) = content((x, y+0.35), text(size: 8.5pt, fill: rgb("#0b5394"))[#t])
  let bits(y, row, col) = {
    for i in range(4) { cell(2 + i*0.7, y, row.at(i), col) }
  }
  // header row a and b
  lbl(1.2, 3.6, "a = 1100"); bits(3.6, ("1","1","0","0"), rgb("#eef4fb"))
  lbl(1.2, 2.8, "b = 1010"); bits(2.8, ("1","0","1","0"), rgb("#eef4fb"))
  lbl(1.2, 1.7, "a & b"); bits(1.7, ("1","0","0","0"), rgb("#eef9f3"))
  lbl(1.2, 0.9, "a | b"); bits(0.9, ("1","1","1","0"), rgb("#eef9f3"))
  lbl(1.2, 0.1, "a ^ b"); bits(0.1, ("0","1","1","0"), rgb("#eef9f3"))
}))

These three operators are not abstractions; they are the three jobs you do to bits all day:

- *Test a bit* (is bit number $k$ set?) with `&` against a mask that has a single 1 in position $k$.
- *Set a bit* (force bit $k$ to 1) with `|` against that same mask.
- *Flip a bit* (toggle bit $k$) with `^` against the mask.

A *mask* is just a number chosen so its set bits mark the positions you care about. We build masks with the shift operators, which we meet next.

=== Shifts: sliding bits left and right

The two shift operators move all the bits of a number sideways by a given number of positions. *Left shift* `x << k` slides every bit up by $k$ places, filling the vacated low positions with zeros — which, since each position up doubles the place value, is exactly multiplication by $2^k$. *Right shift* `x >> k` slides every bit down by $k$ places, dropping the bits that fall off the bottom — integer division by $2^k$.

```python
>>> 1 << 0          # a single 1 in position 0
1
>>> 1 << 3          # slide it up three places: 0b1000
8
>>> bin(1 << 3)
'0b1000'
>>> 0b1011_0000 >> 4    # slide down four places
11
>>> bin(0b10110000 >> 4)
'0b1011'
```

The expression `1 << k` is the most important idiom in this whole chapter: it builds a *mask* with a single 1 in position $k$ and 0 everywhere else. Want to test, set, or flip bit number 5 of a byte? The mask is `1 << 5`, which is `0b100000`, which is 32. Combine the mask with `&`, `|`, or `^`:

```python
>>> byte = 0b0000_0000     # all bits clear
>>> byte = byte | (1 << 5) # SET bit 5
>>> bin(byte)
'0b100000'
>>> bool(byte & (1 << 5))  # TEST bit 5 — is it set?
True
>>> bool(byte & (1 << 2))  # TEST bit 2 — clear
False
>>> byte = byte ^ (1 << 5) # FLIP bit 5 back to 0
>>> bin(byte)
'0b0'
```

This little vocabulary — `x | (1 << k)` to set, `x & (1 << k)` to test, `x ^ (1 << k)` to flip — is the beating heart of every bit-packer ever written, ours included. Read it until it is reflex: "shift a 1 into position $k$, then combine."

#gomaths("Shifting is multiplying and dividing by powers of two")[
In base 10, appending a zero multiplies by 10: $47 -> 470$. In base 2, appending a zero (shifting left by one) multiplies by 2. So shifting left by $k$ positions multiplies by $2^k$:
$ x << k = x times 2^k. $
For example `3 << 4` is $3 times 2^4 = 3 times 16 = 48$. Shifting right is the inverse, an integer (floor) division by $2^k$, discarding any remainder:
$ x >> k = floor(x / 2^k). $
So `48 >> 4` is `3` exactly, but `50 >> 4` is also `3` (the leftover 2 falls off the bottom). This is why right-shifting is the fast way to ask "how many whole groups of $2^k$?" — the same question floor division `//` answers, but a CPU does a shift in a single step. Compressors lean on shifts because they are both meaningful (place value) and blisteringly fast.
]

=== NOT, and a warning about Python's infinite integers

The last operator, *bitwise NOT* `~`, flips every bit: each 0 becomes 1 and each 1 becomes 0. On a fixed-width number this is simple, but Python integers, as we learned in Chapter 15, have *no fixed width* — they are conceptually infinitely wide. So `~x` flips infinitely many leading zeros into infinitely many leading ones, and by the two's-complement rule of Chapter 13 that infinite run of ones is a *negative* number. The clean identity is `~x == -x - 1`:

```python
>>> ~0          # flip all bits of zero
-1
>>> ~5          # -5 - 1
-6
>>> ~0b1100     # -12 - 1
-13
```

This surprises everyone the first time. The practical fix, whenever you want NOT to stay inside a byte, is to *mask back down* to 8 bits afterward with `& 0xFF` — AND against `0b11111111`, which keeps only the low 8 bits and discards the infinite sign extension:

```python
>>> (~0b1100) & 0xFF       # NOT, then keep only 8 bits
243
>>> bin((~0b1100) & 0xFF)  # 0b11110011 — the byte we expected
'0b11110011'
```

#pitfall[
`& 0xFF` is the seatbelt of byte-level Python. Because Python integers grow without limit, *any* operation that should stay inside a byte — a NOT, a left shift that might overflow, a subtraction that might go negative — can silently produce a value outside 0–255. Mask with `& 0xFF` (for one byte) or `& 0xFFFF` (for two) whenever you need a result to fit. Forgetting this mask is the most common bug in hand-written bit code, and the hardest to spot, because everything *looks* fine until a value quietly grows a 9th bit.
]

#aside[
The bitwise operators look like the logical ones — `&` versus `and`, `|` versus `or` — and beginners mix them constantly. The distinction is sharp: `and`/`or`/`not` work on whole *truth values* and short-circuit (Chapter 15), while `&`/`|`/`^`/`~` work on *every bit in parallel* and never short-circuit. `5 and 3` is `3` (truthiness); `5 & 3` is `1` (bit-by-bit AND of `101` and `011`). When you mean "combine these two conditions," use the words; when you mean "combine these bits," use the symbols. They are not interchangeable.
]

#checkpoint[Using a mask, how do you check whether bit 3 (counting from 0) of the byte `value` is set?][Build the mask `1 << 3` (which is `0b1000 = 8`), AND it against `value`, and test for non-zero: `bool(value & (1 << 3))`. If bit 3 is set the AND yields 8 (truthy); if it is clear the AND yields 0 (falsy). The same mask with `|` would *set* that bit, and with `^` would *flip* it.]

== Reading and writing real binary files

A compressor that cannot read a file and write a file is a toy. Python's gateway to the filesystem is one built-in function, `open`, which hands you a *file object* you can read from or write to. The crucial choice, for us, is the *mode*: whether you open the file in *text* mode or *binary* mode. We will almost always want binary.

#gopython("`open`, modes, and the `with` block")[
`open(path, mode)` returns a file object. The mode is a short string: `"r"` to read, `"w"` to write (creating or truncating), `"a"` to append — and, crucially, a `"b"` appended for *binary*. So `"rb"` means "read binary" and `"wb"` means "write binary." Binary mode reads and writes `bytes`; text mode reads and writes `str` and silently applies an encoding. For compression you *always* want binary, so you control every byte.

You should open files inside a `with` block, which guarantees the file is *closed* automatically when the block ends — even if an error is raised partway through:

```python
# Write some bytes to a file, then read them back.
with open("hello.bin", "wb") as f:    # "wb" = write binary
    f.write(b"\x01\x02\x03tinyzip")   # write() takes bytes

with open("hello.bin", "rb") as f:    # "rb" = read binary
    data = f.read()                   # read() returns all bytes
print(data)            # b'\x01\x02\x03tinyzip'
print(len(data))       # 10
```

The `with ... as f:` line opens the file and names it `f` for the indented block; when the block ends, Python closes `f` for you. This "open, use, auto-close" pattern is the correct, safe way to touch files, and we will use it for every read and write in `tinyzip`. Forgetting to close a file you wrote can leave its last bytes stranded in a buffer, never reaching the disk — a `with` block makes that impossible.
]

In binary mode, `f.write(data)` takes a `bytes` (or `bytearray`) and appends it to the file, returning how many bytes it wrote. `f.read()` with no argument slurps the *entire* file into one `bytes` object — fine for the small samples in this book. For large files you read in *chunks* instead, and here the walrus operator from Chapter 15 finally earns its place: `f.read(n)` returns up to `n` bytes, and an *empty* `bytes` (`b""`, which is falsy) when the file is exhausted.

```python
# Stream a file in 64 KB chunks, counting bytes without loading it all.
total = 0
with open("big.bin", "rb") as f:
    while chunk := f.read(65536):     # walrus: read, name, and test
        total += len(chunk)
print(f"{total} bytes")
```

Read that loop carefully, because it is the canonical shape of all streaming I/O. `chunk := f.read(65536)` reads up to 65,536 bytes, binds them to `chunk`, and *hands the same value to the `while`* to test. As long as a non-empty chunk comes back, the loop runs; when `read` returns the empty `b""`, the condition is falsy and the loop stops. This processes a file of any size using only a fixed 64 KB of memory — exactly how a real compressor streams gigabytes without choking. Without the walrus you would have to write the `read` twice, once before the loop and once at the bottom, and forgetting the second copy is a classic infinite-loop bug.

#gomaths("Why 65536? Powers of two as buffer sizes")[
The chunk size `65536` is not random: it is $2^16 = 65536$, exactly 64 *kibibytes* (KiB). I/O buffer sizes are nearly always powers of two — 4096 ($2^12$), 8192, 65536 — because the operating system moves data between disk and memory in power-of-two *pages* and *blocks*, and a buffer aligned to those boundaries is read and written most efficiently. You met $2^16 = 65536$ in Chapter 4 as the number of patterns in 16 bits; here it reappears as a comfortable I/O chunk. Choosing a power of two costs nothing and pleases the hardware, so it is the universal habit.
]

#pitfall[
Open files in *binary* mode (`"rb"`, `"wb"`) for anything you compress. Text mode (`"r"`, `"w"`) silently decodes bytes to characters on the way in and encodes them on the way out, *and* — on Windows — translates newline bytes, mangling any non-text data. A single byte `0x0D` rewritten by newline translation is enough to corrupt a compressed file beyond recovery. The rule is absolute: *compressed data is binary; open it binary.* The only files `tinyzip` opens in text mode are the human-readable sample inputs, and only when we explicitly want their characters.
]

#project("A binary round-trip sanity check")[
Before we pack a single bit, let us prove we can write bytes to disk and read back *exactly* what we wrote — the foundation everything else stands on. This little script writes a handful of bytes, reads them back, and asserts they match. (Earlier `tinyzip` steps built the package skeleton in *Chapter 15* and the histogram and typed helpers in *Chapter 16*; this short warm-up is the first code that touches the disk, the groundwork for our canonical *Step 3* — the bit-I/O engine — which follows.)

```python
# tinyzip/io_roundtrip.py — prove we can write and re-read bytes exactly.

def write_bytes(path: str, data: bytes) -> int:
    """Write data to path in binary mode; return bytes written."""
    with open(path, "wb") as f:
        return f.write(data)

def read_bytes(path: str) -> bytes:
    """Read the whole file at path in binary mode."""
    with open(path, "rb") as f:
        return f.read()

original = bytes(range(256))         # every byte value 0..255, once
written = write_bytes("all256.bin", original)
recovered = read_bytes("all256.bin")

print(f"Wrote {written} bytes")
print(f"Read back {len(recovered)} bytes")
assert recovered == original, "round-trip FAILED"
print("Round-trip OK — every byte survived.")
```

Running `python tinyzip/io_roundtrip.py` prints:

```
Wrote 256 bytes
Read back 256 bytes
Round-trip OK — every byte survived.
```

The star of this script is `bytes(range(256))`, which builds a `bytes` object holding *every* byte value 0 through 255 exactly once — the perfect torture test, because it includes the awkward bytes (0, 10, 13, 255) that text mode would corrupt. The `assert` statement is our safety net: it raises an error and stops the program if the recovered bytes differ from the original by even one bit. A compressor's deepest promise is *losslessness* — decompress(compress(x)) == x — and `assert recovered == original` is the smallest possible version of that promise, tested. We will lean on `assert` for every round-trip from here on.
]

#gopython("`assert`: stating what must be true")[
The `assert` statement checks that a condition is true and, if it is *not*, immediately stops the program with an `AssertionError` and your message. It is how you encode a fact your code depends on, so a violated assumption fails loudly instead of corrupting data silently:

```python
>>> x = 200
>>> assert 0 <= x <= 255, "byte out of range"   # passes, no output
>>> y = 300
>>> assert 0 <= y <= 255, "byte out of range"
Traceback (most recent call last):
  ...
AssertionError: byte out of range
```

When the condition holds, `assert` does nothing and the program continues; when it fails, you get a precise complaint pointing at the broken assumption. In compression code we assert the things that *must* never happen — a byte outside 0–255, a decompressed file that differs from the original — so bugs surface at the exact line where reality first diverged from our expectations, not three functions later.
]

== Integers to bytes and back: `to_bytes`, `from_bytes`, and `struct`

A file header is full of *numbers*: the original length, a version, a count of symbols, a checksum. Each must be written as a fixed number of bytes so the reader knows exactly how many to peel back off. We met the idea in Chapter 13 — multi-byte integers and the endianness that decides their byte order. Python gives us two clean ways to do the conversion: the integer methods `to_bytes`/`from_bytes` for one number at a time, and the `struct` module for packing several fields at once.

=== One number at a time: `int.to_bytes` and `int.from_bytes`

Every Python `int` carries a method `.to_bytes(length, byteorder)` that lays the number out across `length` bytes in the chosen order. Its mirror, the class method `int.from_bytes(data, byteorder)`, reads those bytes back into a number. Since Python 3.11 the `byteorder` defaults to `"big"` (most-significant byte first), but we will always state it, because a header that disagrees with its reader by one endianness is a header full of garbage.

```python
>>> (1000).to_bytes(2, "big")        # 1000 in 2 bytes, big-endian
b'\x03\xe8'
>>> (1000).to_bytes(2, "little")     # same number, bytes swapped
b'\xe8\x03'
>>> int.from_bytes(b'\x03\xe8', "big")   # read it back
1000
>>> int.from_bytes(b'\xe8\x03', "little")
1000
>>> (255).to_bytes(1, "big")         # fits in a single byte
b'\xff'
```

The number 1000 is `0x03E8` in hex. *Big-endian* writes the big end first: `\x03` then `\xe8`. *Little-endian* writes the little end first: `\xe8` then `\x03`. These are the same number, stored two ways — and a reader must use the *same* convention the writer did, or it reads 1000 as 59395. We met this exact split in Chapter 13; now we can perform it in one method call. The companion `.bit_length()` tells you the minimum bits a number needs, which is how you decide how many bytes a field must be:

```python
>>> (1000).bit_length()      # how many bits does 1000 need?
10
>>> (255).bit_length()
8
>>> (256).bit_length()       # one more bit — needs a 2nd byte
9
```

#gomaths("How many bytes does a number need?")[
A non-negative integer $n$ needs exactly
$ ceil((floor(log_2 n) + 1) / 8) $
bytes — the bit-length divided by 8, rounded up. The inner $floor(log_2 n) + 1$ is the *bit-length* (the position of the highest set bit, plus one), which we met as "a bit is a logarithm" in Chapter 7; Python computes it for you as `n.bit_length()`. Dividing by 8 and rounding up converts bits to whole bytes. For $n = 1000$: the bit-length is 10, and $ceil(10\/8) = 2$ bytes. For $n = 255$: bit-length 8, one byte; but $n = 256$ needs 9 bits, hence 2 bytes. This is the calculation a file format does when it must reserve a field wide enough to hold the largest value it will ever store — and getting it wrong by one byte is how formats overflow.
]

#pitfall[
`to_bytes` raises `OverflowError` if the number does not fit in the `length` you gave it: `(256).to_bytes(1, "big")` fails because 256 needs 9 bits. Always size the field for the *largest* value it could hold. For a length that might reach into the millions, four bytes ($2^32 approx 4.3$ billion) is the safe, conventional choice — which is exactly what `tinyzip`'s header will use for the original file size.
]

=== Several fields at once: the `struct` module

When a header has *many* fields — a 2-byte magic number, a 1-byte version, a 4-byte length — converting each by hand is tedious and error-prone. The `struct` module packs and unpacks a whole group in one call, driven by a tiny *format string* that names the type and order of each field. We saw `struct` briefly in Chapter 13; here is how `tinyzip` will actually use it.

#gopython("`struct.pack` and `struct.unpack`")[
A *format string* is a sequence of letters, each describing one field, with an optional leading character that sets the *endianness* for all of them. `struct.pack(fmt, *values)` turns the values into `bytes`; `struct.unpack(fmt, data)` turns the bytes back into a tuple of values.

```python
import struct

# > = big-endian; H = 2-byte unsigned; B = 1-byte unsigned; I = 4-byte unsigned
header = struct.pack(">HBI", 0x747A, 1, 1000)
print(header)            # b'tz\x01\x00\x00\x03\xe8'
print(len(header))       # 7 bytes: 2 + 1 + 4

magic, version, length = struct.unpack(">HBI", header)
print(magic, version, length)    # 29818 1 1000
```

The most useful format letters are `B` (1-byte unsigned, 0–255), `H` (2-byte unsigned, 0–65535), `I` (4-byte unsigned, up to ~4.3 billion), and `Q` (8-byte unsigned). A leading `>` means big-endian, `<` means little-endian; *always include one*, because the bare default also adds invisible padding you do not want. `struct.unpack` always returns a *tuple* (Chapter 16) — even for one field — so unpack into matching names. The number of bytes a format consumes is `struct.calcsize(fmt)`; for `">HBI"` it is 7. This one module turns the fiddly job of laying out a binary header into a single, readable line.
]

#table(columns: (auto, 1fr, auto), inset: 6pt, align: (center, left, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Letter*], [*Meaning*], [*Bytes*]),
  [`B`], [unsigned byte, 0–255], [1],
  [`H`], [unsigned short, 0–65 535], [2],
  [`I`], [unsigned int, 0–4 294 967 295], [4],
  [`Q`], [unsigned long long], [8],
  [`>` / `<`], [big- / little-endian prefix], [—],
)

#note[
`struct` and `to_bytes` overlap, and that is fine — pick by the situation. Use `int.to_bytes` for a *single* number, especially one whose width you compute at runtime. Use `struct.pack` for a *fixed group* of fields you write and read together, like a header — one format string documents the whole layout at a glance. `tinyzip` uses `struct` for its header and `to_bytes` for variable-width values inside the stream.
]

== The heart of it: a `BitWriter` and `BitReader`

Now we build the two machines this whole chapter has been driving toward. Everything so far — `bytes`, `bytearray`, the bitwise operators, `to_bytes` — was preparation for this. A `BitWriter` accepts *bits* (and small groups of bits) and packs them tightly into bytes, eight to a byte, with no wasted space. A `BitReader` does the exact inverse: it walks a `bytes` object and hands back the bits one or several at a time, in the same order they were written. These two classes are the bit-level I/O engine that Huffman, arithmetic coding, and DEFLATE will all plug into.

The problem they solve is precisely the one from this chapter's opening. A Huffman code for a common letter might be the three bits `101`; the next symbol's code might be the five bits `01100`. We must not waste a whole byte on each — we must lay them end to end: `101 01100 ...`, and only when eight bits have accumulated do we emit a finished byte. That bookkeeping — accumulate bits, emit a byte every eighth one, and at the very end *pad* the leftover bits out to a full byte — is exactly what the `BitWriter` automates.

=== The writer: packing bits into bytes

Here is the design. We keep a *buffer* (`bytearray`) of finished bytes, an *accumulator* (`acc`, an `int`) holding the bits not yet emitted, and a *count* (`nbits`) of how many bits are sitting in the accumulator. To write one bit, we shift the accumulator left by one (making room at the bottom) and OR in the new bit. Whenever the count reaches 8, we have a full byte: we mask off the low 8 bits, append them to the buffer, and reset.

#fig([The `BitWriter` accumulates bits in an integer, most-significant-first. As each eighth bit arrives, a finished byte is shifted out to the buffer. Leftover bits are zero-padded on `flush`.], cetz.canvas({
  import cetz.draw: *
  // accumulator cells
  let cell(x, t, col) = { rect((x, 1.2), (x+0.62, 1.82), fill: col); content((x+0.31, 1.51), text(size: 8pt)[#t]) }
  content((0.4, 1.51), text(size: 8.5pt, fill: rgb("#0b5394"))[acc:])
  let bits = ("1","0","1","0","1","1","0","0")
  for i in range(8) { cell(1.2 + i*0.62, bits.at(i), rgb("#eef4fb")) }
  content((4.3, 2.25), text(size: 7.5pt)[8 bits = one full byte])
  // arrow to buffer
  line((6.25, 1.51), (7.3, 1.51), mark: (end: ">"))
  content((6.75, 1.8), text(size: 7pt)[emit])
  rect((7.4, 1.2), (8.9, 1.82), fill: rgb("#eef9f3"))
  content((8.15, 1.51), text(size: 8pt)[buffer])
  // incoming bit
  content((2.0, 0.5), text(size: 8pt)[new bit enters at the right, after `acc <<= 1`])
  line((4.9, 0.7), (4.9, 1.15), mark: (end: ">"))
}))

#gopython("Defining a class: `class`, `__init__`, and `self`")[
A *class* bundles data and the functions that act on it into one named type — the natural way to package a stateful machine like our bit-writer. We met the idea in passing; here is the minimum you need to read one.

```python
class Counter:
    def __init__(self, start: int = 0) -> None:
        self.value = start          # an attribute, stored on the object

    def bump(self) -> None:
        self.value += 1             # methods act on self

c = Counter()        # creates an object; __init__ runs with start=0
c.bump()             # calls the method; self is c
c.bump()
print(c.value)       # 2
```

Three pieces to recognise. `class Name:` introduces the type. `__init__` is the *constructor* — it runs once when you create an object, setting up its starting state. `self` is the object itself, passed automatically as the first parameter of every method; `self.value` is a piece of data *stored on that object* (an *attribute*), surviving between calls. So an object is a little bundle of remembered state (`self.value`) plus actions (`bump`). Our `BitWriter` remembers its half-filled byte across many `write_bit` calls — exactly what an object is for.
]

#project("Step 3 · The `BitWriter` (in `bitio.py`)")[
Create `tinyzip/bitio.py`. This is the most important file in the whole project — every codec writes through it. (`Step 3` is `bitio.py`'s two classes, `BitWriter` here and `BitReader` next.)

```python
# tinyzip/bitio.py — bit-level output, packed MSB-first into bytes.

class BitWriter:
    """Accumulate bits and pack them tightly into bytes, MSB-first."""

    def __init__(self) -> None:
        self.buffer = bytearray()   # finished bytes
        self.acc = 0                # bits not yet emitted (an int)
        self.nbits = 0              # how many bits sit in acc

    def write_bit(self, bit: int) -> None:
        """Append a single bit (0 or 1)."""
        self.acc = (self.acc << 1) | (bit & 1)   # make room, drop bit in
        self.nbits += 1
        if self.nbits == 8:                       # a full byte is ready
            self.buffer.append(self.acc & 0xFF)
            self.acc = 0
            self.nbits = 0

    def write_bits(self, value: int, count: int) -> None:
        """Append the low `count` bits of value, most-significant first."""
        for i in range(count - 1, -1, -1):        # i = count-1 ... 0
            self.write_bit((value >> i) & 1)

    def flush(self) -> bytes:
        """Pad the final partial byte with zeros and return all bytes."""
        if self.nbits > 0:
            self.acc <<= (8 - self.nbits)         # left-pad to a full byte
            self.buffer.append(self.acc & 0xFF)
            self.acc = 0
            self.nbits = 0
        return bytes(self.buffer)
```

Three methods, and every line uses something from this chapter. `write_bit` shifts the accumulator left to make room (`<< 1`), ORs in the new bit (`| (bit & 1)`, the `& 1` guarding against a stray value), and — once eight bits have piled up — appends the finished byte to the `bytearray`, masking with `& 0xFF` for safety. `write_bits` emits a multi-bit value by walking its bits from the *highest* (position `count-1`) down to the lowest with `range(count-1, -1, -1)`, the descending range from Chapter 15, so the bits land most-significant-first — the order Huffman and DEFLATE expect. `flush` handles the loose ends: if the last byte is only partly filled, it shifts the bits up to pad the remainder with zeros, appends that final byte, and freezes the whole buffer to immutable `bytes`. *You must call `flush` at the end* — forget it and the final few bits never reach the output.
]

Watch the writer in action, packing the opening example's bits into real bytes:

```python
>>> from tinyzip.bitio import BitWriter
>>> w = BitWriter()
>>> w.write_bits(0b101, 3)     # three bits: 1 0 1
>>> w.write_bits(0b01100, 5)   # five more:  0 1 1 0 0
>>> w.flush()                  # 10101100 = one full byte
b'\xac'
>>> 0b10101100
172
```

Eight bits in, one byte out: `b'\xac'`, which is `0b10101100 = 172`. The three-bit code and the five-bit code were packed shoulder to shoulder into a *single* byte — no waste, no inflation. Compare that to the opening disaster, where the same bits as the text `"10101100"` would have been *eight* bytes. The `BitWriter` is the difference between a real compressor and an accidental expander.

=== The reader: pulling bits back out

The `BitReader` is the writer run backwards. It holds the source `bytes`, a position telling it which *byte* it is on, and a count of how many bits of the current byte it has already handed out. To read a bit, it isolates the next bit of the current byte (most-significant first, matching the writer) and advances. When all eight bits of a byte are spent, it moves to the next byte. The golden rule, the one that makes the whole scheme work, is that *the reader must pull bits in exactly the same order the writer pushed them* — most-significant first, byte by byte.

#project("Step 3 (cont.) · The `BitReader` (in `bitio.py`)")[
Add this class to `tinyzip/bitio.py`, beside the writer — the second half of `Step 3`.

```python
class BitReader:
    """Read bits back out of a bytes object, MSB-first."""

    def __init__(self, data: bytes) -> None:
        self.data = data            # the source bytes
        self.bytepos = 0            # which byte we are reading
        self.bitpos = 0             # how many bits of it we have used (0..7)

    def read_bit(self) -> int:
        """Return the next bit (0 or 1), or raise if we run out."""
        if self.bytepos >= len(self.data):
            raise EOFError("no more bits")
        byte = self.data[self.bytepos]              # an int, 0..255
        # MSB-first: bit 0 is the top (position 7), bit 1 is position 6, ...
        bit = (byte >> (7 - self.bitpos)) & 1
        self.bitpos += 1
        if self.bitpos == 8:                        # finished this byte
            self.bitpos = 0
            self.bytepos += 1
        return bit

    def read_bits(self, count: int) -> int:
        """Read `count` bits and assemble them into an integer, MSB-first."""
        value = 0
        for _ in range(count):
            value = (value << 1) | self.read_bit()  # shift up, append bit
        return value
```

`read_bit` looks at the current byte (`self.data[self.bytepos]`, an `int`), and extracts the wanted bit with the mask idiom: `(byte >> (7 - bitpos)) & 1` shifts the desired bit down to position 0 and isolates it with `& 1`. Reading position 7 first (then 6, 5, …) hands the bits back *most-significant first* — the same order the writer laid them down. After eight bits it rolls over to the next byte. `read_bits` rebuilds a multi-bit value by the mirror of the writer's loop: start at 0, and for each bit shift the accumulator up and OR the new bit in (`(value << 1) | read_bit()`). The `raise EOFError` guards the end of the stream, turning "read past the end" into a clear error rather than a silent wrong answer.
]

Now we can close the loop — write bits, read them back, and confirm they survived the journey:

```python
>>> from tinyzip.bitio import BitWriter, BitReader
>>> w = BitWriter()
>>> w.write_bits(0b101, 3)
>>> w.write_bits(0b01100, 5)
>>> packed = w.flush()
>>> r = BitReader(packed)
>>> r.read_bits(3)        # the first three bits back
5                          # 0b101
>>> r.read_bits(5)        # the next five
12                         # 0b01100
```

Out came `0b101` (5) and `0b01100` (12), the very values we wrote, in the very order we wrote them. The writer and reader are a matched pair: whatever sequence of `write_bits` calls you make, the same sequence of `read_bits` calls with the same counts retrieves it exactly. That guarantee — *write then read is the identity* — is the contract every codec in this book relies on.

#pitfall[
The `BitWriter` *pads* the final byte with zero bits so the output lands on a whole-byte boundary. The `BitReader` does not know those padding bits are padding — it will happily hand them back as if they were data. So a real format must tell the reader *when to stop*: either by storing the exact count of meaningful bits or symbols in the header (the approach `tinyzip` takes), or by writing an explicit end-of-stream marker. Never rely on "the file ended" to mean "the data ended" — there may be up to seven padding bits of lies after your last real bit.
]

#checkpoint[A `BitWriter` receives `write_bits(0b11, 2)` then `write_bits(0b1, 1)` and nothing more, then `flush()`. What single byte comes out, in binary?][The bits written are `1`, `1`, `1` — three bits. `flush` pads the remaining five positions with zeros, giving `11100000`, which is `0xE0` (224). A `BitReader` on this byte must be told to read only the first 3 bits; the trailing five zeros are padding, not data.]

#gopython("The `__repr__` method: making objects printable")[
When you `print` an object of your own class, Python shows something unhelpful like `<BitWriter object at 0x...>`. You can fix that by defining a `__repr__` method that returns a readable string — invaluable when debugging a half-filled writer:

```python
class BitWriter:
    # ... as before ...
    def __repr__(self) -> str:
        return f"BitWriter({len(self.buffer)} bytes, {self.nbits} pending)"

>>> w = BitWriter()
>>> w.write_bits(0b101, 3)
>>> w
BitWriter(0 bytes, 3 pending)
```

`__repr__` is one of Python's *special methods* — names wrapped in double underscores (sometimes read aloud as "dunder") that hook into the language's built-in behaviour. `__init__` constructs; `__repr__` prints; `__len__` answers `len(...)`. Adding a good `__repr__` to a stateful class like `BitWriter` turns mystifying debugging sessions into a glance: "ah, 3 bits still pending, that is why the flush matters."
]

== Putting it together: a real `tinyzip` container

We now have every piece to define `tinyzip`'s actual file format — the envelope that every later codec will fill. A real compressed file is not just a blob of packed bits; it is a *header* (telling the reader how to interpret what follows) plus the *payload* (the packed bits themselves). Let us build the smallest honest version and round-trip it through the disk.

The header will hold four fields: a 2-byte *magic number* `b"TZ"` (so a reader can recognise a `tinyzip` file and reject anything else), a 1-byte *version*, a 1-byte *method* code (which compression technique produced the payload — `0` for "stored, uncompressed" today, with Huffman, DEFLATE, and the rest claiming their own numbers in Volume II), and a 4-byte *original length* (the size of the data before compression, which a decoder needs to know when to stop). That is `struct.pack(">2sBBI", b"TZ", 1, method, n)` — where `2s` means "two raw bytes" and the two `B`s are the version and method — eight bytes of header, then the payload.

#project("Step 4 · The container: header + payload, round-tripped")[
This is the canonical `container.py` — the envelope every codec will fill. Its two functions, `write(method, payload, …)` and `read(…)`, lay down the magic + version + method + size header, write the payload, and read every field back, refusing anything that is not a valid `tinyzip` file.

```python
# tinyzip/container.py — a minimal tinyzip file: header + payload.
import struct
from tinyzip.bitio import BitWriter, BitReader

MAGIC = b"TZ"
VERSION = 1
METHOD_STORED = 0          # payload is raw/uncompressed (no coder yet)
HEADER = ">2sBBI"          # magic(2) + version(1) + method(1) + size(4) = 8 bytes

def write(path: str, method: int, payload: bytes, original_len: int) -> None:
    """Write a tinyzip container: header + payload."""
    header = struct.pack(HEADER, MAGIC, VERSION, method, original_len)
    with open(path, "wb") as f:
        f.write(header)
        f.write(payload)

def read(path: str) -> tuple[int, int, bytes]:
    """Read a tinyzip container; return (method, original_len, payload)."""
    with open(path, "rb") as f:
        header = f.read(8)                 # 2 + 1 + 1 + 4 = 8 header bytes
        payload = f.read()                 # everything after is payload
    magic, version, method, original_len = struct.unpack(HEADER, header)
    assert magic == MAGIC, f"not a tinyzip file: {magic!r}"
    assert version == VERSION, f"unknown version {version}"
    return method, original_len, payload

# --- demo: pack some bits, wrap them, round-trip the file ---
w = BitWriter()
for code in (0b101, 0b01100, 0b1111, 0b0):   # four codes, varied lengths
    w.write_bits(code, code.bit_length() or 1)
payload = w.flush()

write("demo.tz", METHOD_STORED, payload, original_len=14)
method, length, got = read("demo.tz")

print(f"method = {method}, original_len = {length}")
print(f"payload = {got!r} ({len(got)} bytes)")
assert got == payload, "payload round-trip FAILED"
print("Container round-trip OK.")
```

Running `python tinyzip/container.py` prints something like:

```
method = 0, original_len = 14
payload = b'\xb9\xe0' (2 bytes)
Container round-trip OK.
```

Every idea from this chapter is here, working together. `struct.pack(">2sBBI", ...)` lays out the header in eight bytes, big-endian, no guesswork. The `with open(..., "wb")` block writes header and payload as raw bytes. On the way back, `f.read(8)` peels exactly the header off the front, `f.read()` takes the rest as payload, and `struct.unpack` splits the header into its four fields. The two `assert`s make the reader *refuse* a file that is not a valid `tinyzip` (wrong magic) or a version it does not understand — the same self-defence every real format practises. The `method` byte is the hook every later step plugs into: when Chapter 24 adds Huffman it claims `method = 1`, Chapter 30's DEFLATE another number, and `read` hands that code back so a decoder knows which technique to reverse. Return method, length, and payload as a `tuple[int, int, bytes]` (the typed tuple of Chapter 16), and you have a container ready for any codec to fill. From Chapter 24 onward the "payload" stops being a demo and becomes a genuine Huffman or arithmetic-coded stream — but the envelope never changes.
]

#keyidea[
A compressed file is *header + payload*. The header is a small, fixed, self-describing preamble — magic number, version, and whatever the decoder needs to reverse the process (lengths, counts, a code table). The payload is the densely packed bitstream the `BitWriter` produced. Reading is the mirror: parse the header with `struct`, then feed the payload to a `BitReader`. Every format in this book, from `tinyzip` to PNG to JPEG to zstd, is a variation on this one shape.
]

#history[
The "magic number" at the start of a file — a fixed signature identifying its format — dates to the earliest Unix and is now near-universal: a PNG file begins with the bytes `\x89PNG`, a gzip file with `\x1f\x8b`, a ZIP archive with `PK` (the initials of its creator, Phil Katz, who released PKZIP in 1989). The trick is the same one our `b"TZ"` plays: spend a couple of bytes up front so a reader can instantly tell friend from foe and refuse to misinterpret a file it was never meant to open. It costs almost nothing and prevents a whole class of disasters.
]

== Guarding the data: a checksum

A real format does one more thing our minimal container skips: it *checks its own integrity*. Disks flip bits, networks drop bytes, and a compressed file with a single corrupted byte usually decompresses to garbage — or crashes. The standard defence is a *checksum*: a short number computed from all the data, stored in the file, and recomputed on read. If the two disagree, the reader knows the file is damaged and refuses to trust it, rather than handing you silent garbage. Every serious format carries one — gzip ends with a 4-byte CRC-32, PNG checksums every chunk, zstd stores an optional content checksum.

You do not have to invent one: Python's `zlib` module exposes the same CRC-32 that gzip and PNG use, as a one-line function. A *CRC* (cyclic redundancy check) is a clever bit-mixing function — we will not derive it here — that maps any `bytes` to a 32-bit number extremely sensitive to change: flip any single bit of the input and the CRC almost certainly changes.

#gopython("Catching errors: `try` / `except`")[
In Chapter 16 we learned to `raise` an error — to *signal* that something is wrong (`raise ValueError(...)`). Here we learn the other half: how to *catch* a raised error so the program can respond instead of crashing. You wrap the risky code in a `try` block, and follow it with `except` blocks naming the error types you are prepared to handle:

```python
>>> try:
...     stored = int.from_bytes(b"\x00\x00", "big")
...     if stored != 99:
...         raise ValueError("CRC mismatch")    # we signal a problem
... except ValueError as e:                      # ...and catch it here
...     print("Caught:", e)
Caught: CRC mismatch
```

If the `try` body raises a `ValueError`, Python jumps straight to the matching `except`, binds the error object to `e` (so `print(e)` shows its message), and continues — no crash. If no error is raised, the `except` is skipped entirely. This is exactly how a decoder reacts to a corrupt file: it *tries* to verify the checksum, and on failure *catches* the error to report "the file is corrupt" cleanly rather than dying with a stack trace.
]

#gopython("`zlib.crc32`: a one-call integrity check")[
`zlib.crc32(data)` returns a 32-bit integer (0 to about 4.3 billion) computed from every byte of `data`. The same input always gives the same number; almost any change gives a different one:

```python
>>> import zlib
>>> zlib.crc32(b"tinyzip")
668540858
>>> zlib.crc32(b"tinyzip")        # deterministic: same input, same CRC
668540858
>>> zlib.crc32(b"tinyziq")        # one byte changed (p -> q)
1356738348
>>> (zlib.crc32(b"tinyzip")).to_bytes(4, "big")   # store it as 4 bytes
b"'\xd9\x1f\xba"
```

Because the result is a 32-bit number, it fits in exactly four bytes — `to_bytes(4, "big")` is how you store it in a header or footer, and `int.from_bytes(..., "big")` reads it back. To *verify*, you recompute the CRC of the data you read and compare it to the stored value; equal means intact, unequal means corrupted. This is the whole mechanism behind "the file is corrupt" errors you have seen — a CRC that did not match.
]

#project("Step 5 · A CRC-32 integrity footer in the container")[
Let us harden the `container.py` from Step 4 by appending a 4-byte CRC-32 *footer*, computed over the payload, and verifying it on read — exactly what gzip does. These `write_checked`/`read_checked` functions live alongside `write`/`read` in the same `container.py`, reusing its `MAGIC`, `VERSION`, and `HEADER` constants.

```python
# tinyzip/container.py (continued) — header + payload + CRC-32 footer.
import zlib   # already: import struct; MAGIC, VERSION, HEADER from Step 4

def write_checked(path: str, method: int, payload: bytes, original_len: int) -> None:
    header = struct.pack(HEADER, MAGIC, VERSION, method, original_len)
    crc = zlib.crc32(payload)                      # checksum of the payload
    with open(path, "wb") as f:
        f.write(header)
        f.write(payload)
        f.write(crc.to_bytes(4, "big"))           # 4-byte CRC footer

def read_checked(path: str) -> tuple[int, int, bytes]:
    with open(path, "rb") as f:
        raw = f.read()
    header, body = raw[:8], raw[8:]                # 8-byte header (Step 4)
    payload, footer = body[:-4], body[-4:]         # last 4 bytes are the CRC
    magic, version, method, original_len = struct.unpack(HEADER, header)
    assert magic == MAGIC, f"not a tinyzip file: {magic!r}"
    stored_crc = int.from_bytes(footer, "big")
    actual_crc = zlib.crc32(payload)
    if stored_crc != actual_crc:                   # corruption check
        raise ValueError("CRC mismatch: file is corrupt")
    return method, original_len, payload

# round-trip, then deliberately corrupt one byte to prove the check fires
w = BitWriter(); w.write_bits(0b1011_0010, 8)
write_checked("checked.tz", METHOD_STORED, w.flush(), 14)
print(read_checked("checked.tz"))                  # (0, 14, b'\xb2')

with open("checked.tz", "r+b") as f:               # flip a payload byte
    f.seek(8); f.write(b"\x00")                     # offset 8 = first payload byte
try:
    read_checked("checked.tz")
except ValueError as e:
    print("Caught:", e)                            # Caught: CRC mismatch...
```

Running it prints the clean round-trip `(0, 14, b'\xb2')`, then — after we deliberately corrupt the payload byte at offset 8 — `Caught: CRC mismatch: file is corrupt`. (To corrupt one byte we open the file in `"r+b"` mode — *read-and-write binary*, which lets us overwrite in place without truncating — then `f.seek(8)` moves the write position to byte 8 and `f.write` overwrites just that one byte. The `try`/`except` around the second `read_checked` catches the `ValueError` the mismatch raises.) The checksum did its job: a single flipped byte was caught instead of being silently decompressed into nonsense. Notice the slicing that pulls the file apart: `raw[:8]` is the header, `raw[8:-4]` the payload, `raw[-4:]` the footer — negative indices make "the last four bytes" trivial. With magic number, version, method, length, payload, *and* a CRC footer, `tinyzip`'s container now has every structural piece a production format needs. From here on we only change what goes *inside* the payload.
]

#note[
A CRC-32 detects *accidental* corruption — bit flips from bad disks or flaky networks — but it does *not* protect against a deliberate attacker, who can corrupt the data and recompute a matching CRC. Guarding against tampering needs a cryptographic hash or signature, a different tool for a different threat. The 2024 xz-utils backdoor, which we study in Chapter 31, is a sobering reminder that a checksum proves a file is *intact*, never that it is *trustworthy*. For `tinyzip`'s purposes — catching honest corruption — CRC-32 is exactly right.
]

== A peek at the standard library: Python already ships compressors

Before we leave, it is worth knowing that Python's own standard library *already* contains several of the compressors this book will teach you to understand from the inside. They are not magic; by the end of Volume II you will know exactly what each one does. For now they serve two purposes: a quick way to *check your work*, and a preview of the scoreboard to come.

```python
>>> import gzip, zlib, bz2, lzma
>>> sample = b"banana bandana " * 50   # 750 bytes, very repetitive
>>> len(sample)
750
>>> len(zlib.compress(sample))         # DEFLATE (Chapter 30)
25
>>> len(bz2.compress(sample))          # BWT-based bzip2 (Chapter 35)
54
>>> len(lzma.compress(sample))         # LZMA / .xz (Chapter 31)
84
```

On this highly repetitive 750-byte sample, `zlib` (the DEFLATE we dissect in Chapter 30) crushes it to 25 bytes. That is the bar `tinyzip` is climbing toward — and every technique from Volume II onward will be a step up the ladder these built-in modules sit atop. Python 3.14 even added a brand-new `compression.zstd` module exposing Zstandard, the modern champion we reach in Chapter 32. You will not call these as black boxes for long; you are building the understanding to *re-implement* them.

#aside[
Python 3.14, released 7 October 2025, reorganised these modules under a new `compression` package — so `compression.gzip`, `compression.zstd`, and friends now sit together, with the old top-level names (`import gzip`) kept as aliases for compatibility. The headline addition was `compression.zstd`, bringing first-class Zstandard support to the standard library at last. We will keep using the familiar short names in this book, but if you see `from compression import zstd` in modern code, that is the 3.14 home for it.
]

#scoreboard(caption: "Our 750-byte repetitive sample, and where we stand",
  [Naive (no compression)], [750], [1.00×], [every byte stored as-is],
  [`tinyzip` (today)], [—], [—], [bit-I/O engine ready; no coder yet],
  [zlib / DEFLATE (Ch. 30)], [25], [30.0×], [the target we build toward],
  [bzip2 (Ch. 35)], [54], [13.9×], [BWT + entropy coding],
  [LZMA / .xz (Ch. 31)], [84], [8.9×], [big-dictionary range coding; header overhead dominates on tiny inputs],
)

Our own entry is still a dash — we have not coded a single *compression* technique yet, only the plumbing that lets us emit one. But that plumbing is the prerequisite for everything: without a `BitWriter` there is no Huffman output, no arithmetic stream, no DEFLATE block. We have built the printing press; the words come next.

#misconception[that a bigger, "more random-looking" file is always more compressed.][Compression and randomness are subtly opposite. A *well-compressed* file looks nearly random — its bytes are spread evenly, with little leftover pattern, precisely because the patterns have been squeezed out. But looking random does not *cause* compression; it is a *symptom* of it. A truly random file (say, output from a cryptographic generator) looks the same and cannot be compressed at all, because there is no pattern to remove — a fact we will prove rigorously in Chapter 8's counting argument and Chapter 22's incompressibility theorem. The lesson for now: the densely packed bytes our `BitWriter` emits *should* look random, and that is a good sign, not a worrying one.]

#tryit[
In the REPL, run `import zlib` and compress two 1000-byte samples: `zlib.compress(b"A" * 1000)` and `zlib.compress(bytes(__import__("random").randrange(256) for _ in range(1000)))`. The first — pure repetition — shrinks to a dozen-odd bytes; the second — random noise — comes back *slightly larger* than 1000 bytes. That gap, between perfect pattern and pure noise, is the entire playing field of this book.
]

#takeaways((
  [`str` is text (characters); `bytes` is raw data (integers 0–255). Cross between them only on purpose, with `.encode()` and `.decode()`. Compression lives entirely in `bytes`.],
  [Indexing a `bytes`/`bytearray` gives an `int`; slicing gives back `bytes`. Use the mutable `bytearray` to build output, then freeze with `bytes(...)`.],
  [The six bitwise operators `&`, `|`, `^`, `~`, `<<`, `>>` work on individual bits. The idioms `x | (1<<k)` (set), `x & (1<<k)` (test), `x ^ (1<<k)` (flip) are the alphabet of bit manipulation.],
  [Python integers are unbounded, so mask with `& 0xFF` whenever a result must stay inside a byte — the single most common bit-level bug.],
  [Open compressed files in *binary* mode (`"rb"`/`"wb"`) inside a `with` block. Stream large files in power-of-two chunks with `while chunk := f.read(n):`.],
  [Convert numbers to fixed-width bytes with `int.to_bytes` / `int.from_bytes`, or pack a whole header at once with `struct.pack` / `struct.unpack` — always choosing endianness explicitly.],
  [A `BitWriter` packs bits MSB-first into bytes (call `flush()` at the end!); a matched `BitReader` pulls them out in the same order. Write-then-read is the identity — the contract every codec depends on.],
  [A compressed file is *header + payload*: a small self-describing preamble (magic, version, lengths) followed by the packed bitstream. This one shape underlies every format in the book.],
))

== Exercises

#exercise("17.1", 1)[
Predict, then check in the REPL, the value and *type* of each: `b"data"[0]`, `b"data"[1:3]`, `b"data"[-1]`, and `bytes([104, 105]).decode()`. For the first three, say whether you get an `int` or a `bytes`, and why.
]
#solution("17.1")[
`b"data"[0]` is the `int` `100` (the byte value of `"d"`) — indexing one position yields an integer. `b"data"[1:3]` is the `bytes` `b"at"` — slicing a range yields bytes. `b"data"[-1]` is the `int` `97` (`"a"`), negative indexing from the end. `bytes([104, 105]).decode()` is the `str` `"hi"` — bytes 104 and 105 are `"h"` and `"i"`, decoded as UTF-8 text. The rule: index → `int`, slice → `bytes`, and `.decode()` crosses into `str`.
]

#exercise("17.2", 1)[
Using only the bitwise operators and a mask, write three one-line expressions: one that *sets* bit 2 of the byte `x`, one that *clears* (forces to 0) bit 2 of `x`, and one that *tests* whether bit 2 of `x` is set. (Clearing is the one we did not show directly — think about ANDing with the *inverse* of the mask.)
]
#solution("17.2")[
Set: `x | (1 << 2)`. Test: `bool(x & (1 << 2))`. Clear is the trick: AND with the inverse mask, `x & ~(1 << 2)`. The mask `1 << 2` is `0b00000100`; its inverse `~(1 << 2)` is `...11111011`, all ones except bit 2. ANDing leaves every other bit untouched and forces bit 2 to 0. If you want the result to stay inside a byte, write `x & ~(1 << 2) & 0xFF`, since `~` produces a negative (infinitely wide) integer in Python.
]

#exercise("17.3", 2)[
The number `300` does not fit in one byte. Compute its big-endian and little-endian two-byte representations *by hand* (in hex), then verify with `(300).to_bytes(2, "big")` and `(300).to_bytes(2, "little")`. Finally, explain in one sentence what `int.from_bytes(b"\x01\x2c", "little")` returns and why it is *not* 300.
]
#solution("17.3")[
In hex, $300 = 256 + 44$, which is `0x012C` — a high byte of `0x01` (1) and a low byte of `0x2C` (44). Big-endian writes the big end first: `b"\x01\x2c"`. Little-endian swaps the byte order: `b"\x2c\x01"`. Both `to_bytes` calls confirm this. The catch: `int.from_bytes(b"\x01\x2c", "little")` reads the *same* bytes but with the little-endian rule, so it treats the *first* byte `0x01` as the low byte and the second byte `0x2C` as the high byte: $44 times 256 + 1 = 11265$, not 300. The mismatch between the writer's endianness (big) and the reader's (little) corrupts the value — the exact disaster this exercise warns against.
]

#exercise("17.4", 2)[
Trace, bit by bit, what the following `BitWriter` calls produce, then give the final byte(s) from `flush()` in binary and hex:
```python
w = BitWriter()
w.write_bits(0b110, 3)
w.write_bits(0b10, 2)
w.write_bits(0b1, 1)
out = w.flush()
```
How many meaningful bits are there, how many padding bits does `flush` add, and what is `out`?
]
#solution("17.4")[
The bits written, in order, are `1 1 0`, then `1 0`, then `1` — six meaningful bits: `110101`. Six is not a multiple of eight, so `flush` pads with `8 - 6 = 2` zero bits, giving the full byte `11010100`. That is `0xD4` (212), so `out == b"\xd4"`, one byte. A `BitReader` recovering this data must be told to read only the first 6 bits; the trailing `00` are padding, not data — which is why a real format stores a bit or symbol count in its header.
]

#exercise("17.5", 2)[
Write a function `pack_nibbles(values: list[int]) -> bytes` that packs a list of 4-bit values (each 0–15) two-per-byte, the first in the high nibble and the second in the low nibble. For example `pack_nibbles([0xA, 0xB, 0xC, 0xD])` should return `b"\xab\xcd"`. Handle an odd-length list by leaving the final low nibble zero. Use only `bytearray`, shifts, and OR.
]
#solution("17.5")[
```python
def pack_nibbles(values: list[int]) -> bytes:
    out = bytearray()
    for i in range(0, len(values), 2):          # step by 2
        hi = values[i] & 0xF                     # first nibble
        lo = values[i + 1] & 0xF if i + 1 < len(values) else 0
        out.append((hi << 4) | lo)               # high nibble | low nibble
    return bytes(out)
```
Each byte is built by shifting the high nibble up four places (`hi << 4`) and ORing in the low nibble. The `& 0xF` masks each value to its four bits for safety; the `if i + 1 < len(values)` guard supplies a zero low nibble when the list has an odd length. Looping with `range(0, len(values), 2)` visits the list two at a time. This is a miniature bit-packer — the same shift-and-OR pattern the `BitWriter` uses, specialised to fixed 4-bit fields.
]

#exercise("17.6", 2)[
Add a method `bits_written(self) -> int` to `BitWriter` that returns the *total* number of bits written so far, counting both the bits already in finished bytes and the bits still pending in the accumulator. Why is this more useful to a compressor than `len(self.buffer)`?
]
#solution("17.6")[
```python
def bits_written(self) -> int:
    return len(self.buffer) * 8 + self.nbits
```
Each finished byte holds 8 bits (`len(self.buffer) * 8`), plus the `self.nbits` not yet emitted. This matters because a compressor's true output size is measured in *bits*, not bytes — the last byte is usually partly padding, so `len(self.buffer)` over- or under-counts the real cost by up to 7 bits. When comparing two codes to see which is shorter (the whole game of entropy coding), you must compare *bits*, and `bits_written` reports them exactly. It is also how `tinyzip` will report its compression ratio honestly, before flush rounds up to whole bytes.
]

#exercise("17.7", 2)[
Explain why the `BitReader` must read bits in the *same* order (most-significant-first) that the `BitWriter` wrote them. Construct a small concrete example where reading least-significant-first instead returns the wrong value, even though every byte on disk is identical.
]
#solution("17.7")[
The bytes on disk record only *which bits are set*, not the order they were meant to be read. The order is a *convention* the writer and reader must share. Example: write `write_bits(0b110, 3)` — MSB-first, the bits laid down are `1, 1, 0`, so after padding the byte is `11000000` (`0xC0`). A correct MSB-first reader doing `read_bits(3)` returns `1 1 0 = 0b110 = 6`. But a reader that pulled bits *least*-significant-first would read positions 0, 1, 2 of the byte as `0, 0, 0`... or, reading the low three bits, `0 0 0 = 0`. Same byte `0xC0`, different answer. Writer and reader must agree on bit order exactly as they must agree on endianness; MSB-first is simply the convention this book (and DEFLATE-style formats partly) adopts.
]

#exercise("17.8", 3)[
Design and implement a tiny self-describing format `pack_run(data: bytes) -> bytes` and its inverse `unpack_run(blob: bytes) -> bytes` that performs *run-length encoding* on bytes: replace each maximal run of an identical byte with a (count, value) pair, where count is a single byte 1–255. Include a 4-byte big-endian header giving the original length, and round-trip it. (This is a real, if simple, compressor — your first.)
]
#solution("17.8")[
```python
import struct

def pack_run(data: bytes) -> bytes:
    out = bytearray(struct.pack(">I", len(data)))    # 4-byte length header
    i = 0
    while i < len(data):
        value = data[i]
        run = 1
        while i + run < len(data) and data[i + run] == value and run < 255:
            run += 1
        out.append(run)                               # count (1..255)
        out.append(value)                             # the byte value
        i += run
    return bytes(out)

def unpack_run(blob: bytes) -> bytes:
    (orig_len,) = struct.unpack(">I", blob[:4])       # read the header
    out = bytearray()
    i = 4
    while i < len(blob):
        count, value = blob[i], blob[i + 1]
        out.extend(bytes([value]) * count)            # repeat the byte
        i += 2
    assert len(out) == orig_len, "length mismatch"
    return bytes(out)
```
The encoder scans `data`, measures each maximal run (capped at 255 so the count fits one byte), and emits a `(count, value)` pair. The 4-byte header (`struct.pack(">I", ...)`) records the original length so the decoder can verify the result with an `assert`. The decoder walks the pairs, repeating each byte `count` times with `bytes([value]) * count`. On runs of length 1 this format *expands* (2 bytes for 1) — RLE only wins on data with long runs, the lesson that motivates the smarter coders of Volume II. But it round-trips losslessly, which makes it, technically, your first complete compressor built on this chapter's tools.
]

#exercise("17.9", 1)[
The string `"résumé"` is 6 characters. Without running code, predict whether `"résumé".encode("utf-8")` produces 6, 7, or 8 bytes, and explain. Then state what `len(...)` of the result would be and why a fixed "one byte per character" assumption is dangerous.
]
#solution("17.9")[
`"résumé"` has two accented characters (`é` appears twice, each a non-ASCII character), and each `é` encodes to *two* bytes in UTF-8 (`\xc3\xa9`), as we saw with `"café"`. The four plain ASCII characters (`r`, `s`, `u`, `m`) are one byte each. So the total is $4 times 1 + 2 times 2 = 8$ bytes, and `len("résumé".encode("utf-8"))` is `8`, not `6`. Assuming one byte per character would under-allocate a buffer by two bytes and truncate or corrupt the text — exactly the bug that produces "mojibake." The safe rule: *measure the length of the encoded `bytes`, never the `str`*, when you care about storage.
]

#exercise("17.10", 3)[
A `BitReader` reading a stream that ends mid-byte will, after the last real bit, return *padding* bits as if they were data. Modify the `tinyzip` container so the reader stops at exactly the right bit. Propose two designs — (a) store an explicit "number of valid bits in the final byte" in the header, and (b) store the total symbol count — and argue which is more robust for a variable-length code like Huffman, where you do not know the bit count until after encoding.
]
#solution("17.10")[
*Design (a)*: add a 1-byte field holding `final_bits` ∈ 1–8, the number of meaningful bits in the last byte. The reader computes the total valid bit count as `(len(payload) - 1) * 8 + final_bits` and refuses to read past it. Simple, but it forces the encoder to know, at header-writing time, how many padding bits flush added — easy if you write the header *after* flushing. *Design (b)*: store the symbol count (or original length), and let the decoder stop once it has produced that many symbols, ignoring whatever bits remain. For a variable-length code like Huffman this is the more robust choice: the decoder reads codewords one at a time and simply *stops after the Nth symbol*, so trailing padding is never even examined — you never need to count bits at all. `tinyzip`'s header already carries `original_len` precisely so the decoder can stop on symbol count, which is why design (b) is the one the book adopts from Chapter 24 onward. Design (a) is the right tool only for fixed-width payloads where symbols and bits line up predictably.
]

== Further reading

- *The official Python tutorial and library reference* are the authoritative source for `bytes`, `bytearray`, file I/O, and `struct`. See the "Built-in Types" and `struct` pages of #link("https://docs.python.org/3/library/stdtypes.html")[the Python 3.14 documentation] and #link("https://docs.python.org/3/library/struct.html")[the `struct` module reference].
- *What's New in Python 3.14* documents the new `compression` package (including `compression.zstd`) and template strings: #link("https://docs.python.org/3/whatsnew/3.14.html")[docs.python.org/3/whatsnew/3.14.html].
- For the byte-level *formats* our container imitates, the canonical specifications are wonderfully readable: P. Deutsch, #link("https://www.rfc-editor.org/rfc/rfc1952.txt")[*GZIP File Format Specification v4.3* (RFC 1952)] shows a real magic number, header, and footer, and #link("https://www.rfc-editor.org/rfc/rfc1951.txt")[*DEFLATE Compressed Data Format* (RFC 1951)] shows how a real bitstream packs variable-length codes — exactly the job our `BitWriter` does, and the subject of Chapter 30.
- For a deeper, friendly tour of bit manipulation in Python, the *Python Bitwise Operators* chapter of any solid reference (or the `bitstring` library's documentation) generalises the hand-built `BitReader`/`BitWriter` we wrote here.

#bridge[
We now own the press: a `BitWriter` that packs bits as tightly as physics allows, a `BitReader` that reads them back, and a self-describing container to wrap them in. But we have not yet decided *which* bits to write — and that is the whole art of compression. The press is idle until we have something to print. With Volume I complete — the maths, the machines, and the Python all built from scratch — Chapter 18 finally turns to the question that started the field: in 1948, Claude Shannon asked exactly *how few* bits a message truly needs, and answered it with a single quantity, *entropy*. Once we can measure the information in a source, we will know precisely how many bits our `BitWriter` *should* emit — and every codec from Chapter 24 onward is a race to reach that floor.
]
