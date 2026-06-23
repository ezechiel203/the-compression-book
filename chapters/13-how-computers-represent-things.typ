#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= How Computers Represent Things

#epigraph[
  "There is no such thing as information in the abstract, apart from a physical representation."
][Rolf Landauer, _Physics Today_ (1991)]

Here is the puzzle that opens this chapter. You take a photograph, save it, and email it to a friend. Your friend opens the photo on a phone, a laptop, and a tablet, and it looks right on all three — even though those machines were built in different countries, by different companies, using different chips, running different operating systems. How does every machine agree on what that picture looks like? The answer, underneath all the software, is a social contract: a set of agreements about how to represent things as numbers, and how to represent numbers as patterns of bits. Every compressed file in the rest of this book — every Huffman code, every DEFLATE stream, every JPEG block — is ultimately a blob of bytes that only matters because of these agreements.

In the last chapter we built the mathematical plumbing: vectors, matrices, and transformations. In this chapter we build the physical plumbing: bits, bytes, words, integers, characters, and real numbers. By the end you will be able to read a hex dump of a file and tell the story of every byte — which ones are the size, which are the checksum, which are the data. That is the literacy every compressor engineer needs.

#recap[
  Chapter 4 gave us the binary number system: bits, place value, and base conversion. Chapter 5 gave us Boolean algebra: the AND, OR, XOR, and NOT operations that circuits run on bits. Chapter 12 gave us vectors as ordered lists of numbers — the structure every image and audio sample is stored as. Now we collect those pieces into the question "what does a real computer memory actually look like?" and answer it carefully, from scratch.
]

#objectives((
  [Define *bit*, *nibble*, *byte*, *word*, and *address*, and explain how a memory is just a numbered array of bytes.],
  [Represent unsigned integers in binary and explain how addition, overflow, and the range limit work.],
  [Represent signed integers using *two's complement* and show why it makes subtraction free.],
  [Explain what *characters* are, how ASCII encodes 128 of them in 7 bits, and why Unicode/UTF-8 was invented and how it works.],
  [Describe the structure of a *floating-point* number (IEEE 754), identify the sign, exponent, and mantissa, and explain what NaN, Inf, and denormals mean.],
  [Explain *endianness* and decode a little-endian or big-endian multi-byte value from a hex dump.],
  [Read and write small Python programs that inspect, pack, and unpack binary data using `struct` and `int.from_bytes`.],
))

== The memory model: a very long row of boxes

Before we talk about what the boxes hold, let us establish what they are.

Picture a machine's RAM as a very long row of identically sized boxes, numbered starting from zero. Each box holds a fixed amount of information, and the number on each box is called its *address*. The address is just an index — box number 0, box number 1, box number 2, all the way up to however many boxes the machine has. A modern laptop with 16 GB of RAM has about 17.2 billion boxes.

#definition("Bit and byte")[
  A *bit* is the smallest possible unit of information: one binary digit, either $0$ or $1$. A *byte* is a group of eight consecutive bits. Every box in a machine's RAM holds exactly one byte. The address of a box is the integer index of that box in the long row. An *address space* of $2^32$ bytes can address about $4.3 times 10^9$ (4.3 billion) individual bytes — roughly 4 gigabytes — and that is exactly why 32-bit machines had a 4 GB RAM limit that caused so much trouble in the early 2000s.
]

Eight bits per byte is not a law of physics. Early machines used bytes of 5, 6, or 9 bits. The 8-bit byte won partly because it is a power of two, which makes address arithmetic clean, and partly because the ASCII character encoding (which we will meet shortly) needs 7 bits, and 8 gives a comfortable margin. By the 1970s the 8-bit byte had won completely, and it is now so universal that the C language standard, the POSIX standard, and the IEEE 754 floating-point standard all assume it.

#keyidea[
  A computer's memory is a flat, numbered array of bytes. Every piece of data — an integer, a character, a pixel, a floating-point number, a compressed bitstream — is stored as some sequence of bytes at some starting address. The only question is: which bytes mean what?
]

#mathrecall[
  Throughout this chapter we write byte values in *hexadecimal* (base 16), using the `0x` prefix — exactly the notation built in Chapter 4. Recall that one hex digit (0–9, then A–F for 10–15) encodes four bits, so two hex digits encode one byte: `0x41` means $4 times 16 + 1 = 65$, whose bits are `0100 0001`. Hex is just a compact, human-readable way of writing the same bits.
]

=== Nibbles, words, and cache lines

Beyond the byte, several groupings come up constantly enough to have names.

- A *nibble* (also spelled *nybble*) is four bits — half a byte. One hex digit, 0–F, fits exactly in a nibble. You will mostly encounter nibbles when reading hex dumps.
- A *word* used to mean the natural size the CPU processes in one operation. On a 16-bit machine a word was 16 bits (2 bytes); on a 32-bit machine it was 32 bits (4 bytes); on today's 64-bit machines it is 64 bits (8 bytes). Unfortunately "word" still sometimes means 16 bits in older documentation. Always check.
- A *doubleword* or *dword* is 32 bits (4 bytes); a *quadword* or *qword* is 64 bits (8 bytes). These terms appear constantly in binary format specifications.
- A *cache line* is 64 bytes on most modern CPUs — the minimum amount of data that moves between RAM and the CPU's on-chip cache in a single transfer. Compressors that want to be fast try to access memory in units that respect cache line boundaries.

#fig([The memory hierarchy and unit sizes. A nibble is 4 bits (one hex digit), a byte is 8 bits, a word is 2–8 bytes depending on era, and a cache line groups 64 bytes. The flat row of addressed bytes is the only abstraction the hardware truly knows.],
cetz.canvas({
  import cetz.draw: *
  let ht = 0.55
  let labels = ("bit", "nibble", "byte", "word\n(64-bit)", "cache line")
  let widths = (0.18, 0.38, 0.75, 2.0, 5.6)
  let cols = (rgb("#0b5394"), rgb("#0f766e"), rgb("#783f04"), rgb("#9a2617"), rgb("#5b3a86"))
  let sublabels = ("1 bit", "4 bits", "8 bits", "64 bits", "512 bits")
  let startx = 0.2
  let y = 0.0
  for i in range(5) {
    let x = startx
    rect((x, y + float(i) * 0.95), (x + widths.at(i), y + float(i) * 0.95 + ht),
      fill: cols.at(i).lighten(75%), stroke: 0.7pt + cols.at(i))
    content((x + widths.at(i) / 2, y + float(i) * 0.95 + ht / 2),
      text(size: 7.5pt, fill: cols.at(i))[#labels.at(i): #sublabels.at(i)])
  }
}))

== Unsigned integers: the foundation

The simplest thing a byte can represent is a non-negative whole number from 0 to 255. Using the binary place-value system from Chapter 4, 8 bits give us $2^8 = 256$ distinct patterns (from `00000000` through `11111111`), which we map to the integers 0 through 255. This is an *unsigned integer* — unsigned because there is no sign bit, so every pattern is positive or zero.

=== Unsigned ranges

With $n$ bits you can represent $2^n$ different values, covering 0 through $2^n - 1$.

#fig([Unsigned integer ranges for common bit widths.],
cetz.canvas({
  import cetz.draw: *
  let rows = (
    ("8-bit (byte)", "0", "255", "256"),
    ("16-bit", "0", "65,535", "65,536"),
    ("32-bit", "0", "4,294,967,295", "≈4.3 billion"),
    ("64-bit", "0", "18,446,744,073,709,551,615", "≈1.8 × 10¹⁹"),
  )
  let ht = 0.5
  let cols = (2.0, 0.6, 2.6, 2.0)
  let headers = ("Type", "Min", "Max", "Count")
  let total_w = 7.2
  rect((0, 0), (total_w, ht), fill: rgb("#0b5394"), stroke: none)
  let cx = 0.1
  for i in range(4) {
    content((cx + cols.at(i)/2, ht/2), text(fill: white, weight: "bold", size: 8pt)[#headers.at(i)])
    cx = cx + cols.at(i)
  }
  for ri in range(4) {
    let y = -float(ri+1) * ht
    let fill = if calc.rem(ri, 2) == 0 { rgb("#f4f6f8") } else { white }
    rect((0, y), (total_w, y + ht), fill: fill, stroke: 0.3pt + rgb("#d0d7de"))
    let cx2 = 0.1
    for ci in range(4) {
      content((cx2 + cols.at(ci)/2, y + ht/2), text(size: 7.5pt)[#rows.at(ri).at(ci)])
      cx2 = cx2 + cols.at(ci)
    }
  }
}))

=== Overflow: when the count wraps

What happens when you have the maximum 8-bit value, `11111111` = 255, and add 1? Ordinary addition would give `100000000` — nine bits — but the ninth bit has nowhere to go in an 8-bit register. It simply disappears. The result is `00000000` = 0. The counter wraps around. This is *overflow*, and it is not a bug in the hardware: it is defined behavior that programmers must account for.

#pitfall[
  Overflow is silent in most programming languages. The expression `255 + 1` on a Python `int` gives `256`, because Python integers have unlimited size. But in C, on a *uint8\_t* (an 8-bit unsigned type), `255 + 1` gives `0`. In Java it gives `256` (because Java's `byte` is signed — more on that shortly). The compressor that treats a byte counter like a Python integer, then ships it in a 32-bit header field, will silently corrupt files as soon as a chunk exceeds 4 GB. This bug has burned real codecs. Always track the size of your integer types.
]

#gopython("Integer types and sizes in Python")[
  This is the book's first Python code. We taught Python nothing yet — that begins in earnest in Chapters 15–17 (the Python primer), where every feature is built from scratch. The `#gopython` boxes in this chapter are short previews you can safely skim; the main prose never depends on them. For now, just read the code as careful pseudocode with real syntax.

  Python's built-in `int` has unlimited precision — it will happily compute $2^{10000}$ without overflowing. But when we pack integers into binary files (Chapter 17) or work with raw bytes, we need to think about fixed-width types. The `struct` module and the `int.to_bytes`/`int.from_bytes` methods do the conversion. (A *method* like `n.to_bytes(...)` is just a function attached to a value, written after a dot; the `f"..."` strings in later boxes are *f-strings*, where anything in `{ }` is replaced by its value — both are covered properly in Chapter 15.)

  ```python
  # A one-byte unsigned integer
  n = 200
  raw = n.to_bytes(1, byteorder="little")   # b'\xc8'
  back = int.from_bytes(raw, byteorder="little")  # 200

  # What happens if we try to pack 256 into one byte?
  try:
      bad = (256).to_bytes(1, byteorder="little")
  except OverflowError as e:
      print(e)   # int too big to convert
  ```

  Python raises `OverflowError` here because it checks before packing. Real bugs happen when you write the check yourself and get it wrong. We will use `struct` and `int.to_bytes` throughout the tinyzip project to keep types explicit.
]

=== Addition in binary: a worked example

Let us add 75 + 84 in 8-bit binary to see overflow in action, and also to confirm that binary addition is just the carry-the-one rule from grade school, applied to twos instead of tens.

$75 = 64 + 8 + 2 + 1 = 01001011_2$

$84 = 64 + 16 + 4 = 01010100_2$

```
  0 1 0 0 1 0 1 1    (75)
+ 0 1 0 1 0 1 0 0    (84)
─────────────────
  1 0 0 1 1 1 1 1    (159)
```

No overflow here: 159 fits in 8 bits. But if we add 200 + 100:

$200 = 11001000_2$, $100 = 01100100_2$

```
  1 1 0 0 1 0 0 0    (200)
+ 0 1 1 0 0 1 0 0    (100)
─────────────────
1 0 0 1 0 1 1 0 0    (300 — needs 9 bits!)
```

The ninth bit (value 256) is lost. We are left with $0 0 1 0 1 1 0 0_2 = 44$. The overflow wrapped us: $200 + 100 equiv 44 space (mod 256)$.

#checkpoint[
  A protocol header stores a 32-bit unsigned packet counter. After how many packets does it overflow and return to zero?
][
  $2^{32} = 4{,}294{,}967{,}296$. At one million packets per second, the counter wraps after about 4,295 seconds — roughly 71 minutes. Protocols that run over a weekend without resetting, or that use faster networks, hit this wrap. That is why modern protocols like QUIC use 64-bit counters.
]

== Signed integers: two's complement

Most real data includes negative numbers. Temperatures can be below zero, audio samples swing positive and negative, coordinate offsets go left as well as right. We need a way to represent negative integers in bits. Several methods were tried historically; virtually every modern machine uses *two's complement*.

=== The intuition: a clock face

Picture a clock face with 256 positions, numbered 0 through 255. Going clockwise, 0, 1, 2, ..., 127, 128, ..., 255, and then it wraps back to 0. Now, what if we relabeled the upper half? Instead of calling position 128 "128," we call it "−128." Position 129 becomes "−127," all the way to position 255 becoming "−1." Position 0 stays "0," and positions 1 through 127 stay positive.

That is two's complement. The high half of the unsigned range is *reinterpreted* as negative numbers. The rule: if the most significant bit (the leftmost, highest-value bit) is 1, the number is negative. If it is 0, the number is non-negative.

#definition("Two's complement (n-bit)")[
  In *two's complement* with $n$ bits, a bit pattern $b_{n-1} b_{n-2} dots b_1 b_0$ represents the signed integer
  $ -b_{n-1} dot 2^{n-1} + b_{n-2} dot 2^{n-2} + dots + b_1 dot 2^1 + b_0 dot 2^0. $
  The most significant bit $b_{n-1}$ acts like a sign bit but with a *negative* place value: it contributes $-2^{n-1}$ if it is 1. The range of an $n$-bit two's complement integer is $[-2^{n-1},\; 2^{n-1}-1]$.
]

For 8 bits that is $[-128, +127]$. For 16 bits: $[-32768, +32767]$. For 32 bits: $[-2^{31}, 2^{31}-1] approx [-2.1 times 10^9, +2.1 times 10^9]$.

=== How to negate a number in two's complement

To negate a number, use this two-step recipe: (1) flip every bit (0 becomes 1, 1 becomes 0); (2) add 1. This is the *bitwise complement plus one* recipe. Example: negate $+5$ in 8 bits.

$+5 = 00000101_2$

Step 1 — flip bits: $11111010_2$

Step 2 — add 1: $11111010_2 + 00000001_2 = 11111011_2$

Check: decode $11111011_2$ with the signed formula. The MSB is 1, so it contributes $-128$. The remaining bits $1111011_2$ give $64 + 32 + 16 + 8 + 2 + 1 = 123$. Total: $-128 + 123 = -5$. Correct.

#theorem("Two's complement negation")[
  For any $n$-bit two's complement integer $x$ (except $x = -2^{n-1}$, which has no positive counterpart), the two-step recipe "flip all bits, then add 1" produces the $n$-bit representation of $-x$.
]

#proof[
  Let $x$ be represented by the bit pattern $B$. "Flip all bits" produces $overline(B)$. Notice that $B + overline(B) = (2^n - 1)$ (all ones) (every bit position gives 0+1=1). So $overline(B) = 2^n - 1 - B$. Adding 1: $overline(B) + 1 = 2^n - B$. But modulo $2^n$ (which is what $n$-bit arithmetic does), $2^n - B equiv -B$. So the recipe gives the $n$-bit representation of $-x$. The exception $x = -2^{n-1}$ fails because $+2^{n-1}$ requires $n+1$ bits — it overflows. #h(1fr)
]

=== Why subtraction is free

The beautiful pay-off of two's complement is that the same hardware circuit that does unsigned addition also does signed subtraction. To compute $A - B$, the CPU computes $A + (-B)$, and it gets $-B$ using the flip-and-add-one recipe. No separate subtraction circuitry needed. This was not obvious in the 1940s and is one reason two's complement won over the rival "sign-magnitude" and "ones' complement" encodings.

Let us watch it work on $7 - 5$ in 8 bits. First negate $5 = 00000101_2$: flip to $11111010_2$, add 1 to get $-5 = 11111011_2$. Now just *add* $7$ and $-5$:

```
  0 0 0 0 0 1 1 1    (7)
+ 1 1 1 1 1 0 1 1    (-5)
─────────────────
1 0 0 0 0 0 0 1 0    (carry out of bit 8 is discarded)
```

The ninth bit falls off the end (exactly the overflow behaviour we saw for unsigned addition), leaving $00000010_2 = 2$. And $7 - 5 = 2$. The hardware did one ordinary addition and threw away the carry; it never knew or cared that the operands were "signed."

#history[
  The earliest electronic computers used sign-magnitude: one bit for the sign (0 = positive, 1 = negative) and the remaining bits for the magnitude. This meant you needed two different adders — one for positive+positive and one for positive+negative. It also gave you two representations of zero: $+0$ and $-0$, which forced software to always check both. IBM's System/360 (1964) adopted two's complement for its integer arithmetic, and by the time C was standardized in 1989, two's complement was the assumption everywhere. The C23 standard (ISO/IEC 9899:2023) made it mandatory, finally eliminating the theoretical possibility of sign-magnitude or ones'-complement C implementations.
]

#gopython("Signed integers in Python and struct")[
  Python's plain `int` is always signed and unlimited. When you need a fixed-size signed integer — for writing a binary header, say — use `struct.pack`:

  ```python
  import struct

  # Pack -1 as a signed 8-bit integer
  raw = struct.pack("b", -1)      # b'\xff'
  # The single byte 0xFF = 11111111 is -1 in two's complement
  print(int.from_bytes(raw, byteorder="big", signed=True))   # -1
  print(int.from_bytes(raw, byteorder="big", signed=False))  # 255

  # Signed 32-bit little-endian
  raw2 = struct.pack("<i", -12345)
  back = struct.unpack("<i", raw2)[0]   # -12345
  ```

  Format codes: `"b"` = signed 8-bit, `"h"` = signed 16-bit, `"i"` = signed 32-bit, `"q"` = signed 64-bit. Uppercase versions (`"B"`, `"H"`, `"I"`, `"Q"`) are unsigned. The prefix `"<"` means little-endian; `">"` means big-endian (we will explain endianness in the next section).
]

=== Signed integer ranges in practice

#fig([Common signed integer types used in C, Java, and binary file formats.],
cetz.canvas({
  import cetz.draw: *
  let rows = (
    ("int8\_t / byte", "8", "−128", "127"),
    ("int16\_t / short", "16", "−32,768", "32,767"),
    ("int32\_t / int", "32", "−2,147,483,648", "2,147,483,647"),
    ("int64\_t / long", "64", "−9,223,372,036,854,775,808", "9,223,372,036,854,775,807"),
  )
  let ht = 0.5
  let cols = (2.1, 0.6, 2.4, 2.1)
  let headers = ("C type / alias", "Bits", "Min", "Max")
  let total_w = 7.2
  rect((0, 0), (total_w, ht), fill: rgb("#783f04"), stroke: none)
  let cx = 0.1
  for i in range(4) {
    content((cx + cols.at(i)/2, ht/2), text(fill: white, weight: "bold", size: 8pt)[#headers.at(i)])
    cx = cx + cols.at(i)
  }
  for ri in range(4) {
    let y = -float(ri+1) * ht
    let fill = if calc.rem(ri, 2) == 0 { rgb("#f4f6f8") } else { white }
    rect((0, y), (total_w, y + ht), fill: fill, stroke: 0.3pt + rgb("#d0d7de"))
    let cx2 = 0.1
    for ci in range(4) {
      content((cx2 + cols.at(ci)/2, y + ht/2), text(size: 7.2pt)[#rows.at(ri).at(ci)])
      cx2 = cx2 + cols.at(ci)
    }
  }
}))

== Characters: from ASCII to Unicode

Numbers are useful, but we also want to store text. The obvious approach: agree on a mapping from integers to characters, publish that mapping, and stick to it. If we all agree that 65 means 'A', then any machine that stores the byte `0x41` (which is 65 in hex) and reads it as a character gets 'A', no matter where it was made.

=== ASCII: 7 bits, 128 characters

The *American Standard Code for Information Interchange*, finalized in 1963, assigns a 7-bit integer (0–127) to each of 128 characters: the 26 uppercase and 26 lowercase English letters, ten digits, 32 punctuation and symbol characters, and 33 *control characters* (like newline, carriage return, tab, and the bell that made a teletype machine ring).

#fig([A compact ASCII table. Values 0–31 and 127 are control characters; 32 is space; 33–126 are printable. The letter 'A' is 65 (0x41), 'a' is 97 (0x61). Note: 'a' = 'A' + 32 — which is bit 5 set, so toggling bit 5 of any letter flips its case.],
cetz.canvas({
  import cetz.draw: *
  let pairs = (
    ("0x00–0x1F", "Control chars (NUL, BEL, BS, HT, LF, CR…)"),
    ("0x20", "Space (32)"),
    ("0x21–0x2F", "! \" # $ % & ' ( ) * + , - . /"),
    ("0x30–0x39", "0 1 2 3 4 5 6 7 8 9   (digits)"),
    ("0x3A–0x40", ": ; < = > ? @"),
    ("0x41–0x5A", "A B C … Z   (uppercase, 65–90)"),
    ("0x5B–0x60", "[ \\ ] ^ _ `"),
    ("0x61–0x7A", "a b c … z   (lowercase, 97–122)"),
    ("0x7B–0x7E", "{ | } ~"),
    ("0x7F", "DEL (127, delete)"),
  )
  let ht = 0.46
  for i in range(10) {
    let y = -float(i) * ht
    let fill = if calc.rem(i, 2) == 0 { rgb("#f4f6f8") } else { white }
    rect((0.0, y), (7.2, y + ht), fill: fill, stroke: 0.3pt + rgb("#d0d7de"))
    content((0.7, y + ht/2), text(size: 7.5pt, weight: "bold", fill: rgb("#0b5394"))[#pairs.at(i).at(0)])
    content((3.9, y + ht/2), text(size: 7.2pt)[#pairs.at(i).at(1)])
  }
}))

ASCII was designed for English. It has no accented characters (é, ñ, ü), no Chinese or Japanese glyphs, no Arabic script, no emoji. For decades, each country made its own extension, mapping the values 128–255 to their local characters. The result was dozens of incompatible *code pages*: Windows-1252 for Western Europe, ISO-8859-5 for Cyrillic, Shift-JIS for Japanese. Opening a file created with one code page on a machine configured for another gave you garbage — the famous *mojibake* ("character transformation" in Japanese). The internet made this problem acute, and in 1991 the solution was born.

#history[
  The first ASCII standard was published on June 17, 1963, by the American Standards Association — now ANSI. The code was designed to be sorted in a useful order: digits before uppercase before lowercase, control characters at the start. The teleprinter convention that 'A' = 65 and 'a' = 97 (a difference of 32 = $2^5$) was a deliberate choice: toggling bit 5 flips case. This trick appears in real compressors and search engines to this day.
]

=== Unicode and UTF-8: one encoding for every script on Earth

*Unicode* is a standard maintained by the Unicode Consortium (formed 1991) that assigns a unique integer — called a *code point* — to every character in every human writing system. As of Unicode 16.0 (September 2024), the standard defines 154,998 characters covering 168 scripts, including historical scripts like Linear B and Cuneiform, mathematical symbols, and over 3,600 emoji. Code points are written as U+XXXX in hex; 'A' is U+0041, '€' is U+20AC, '😀' is U+1F600.

Now, how do you store code points in bytes? The simplest approach is to use 4 bytes for every character (UTF-32). That works, but it wastes space: English text would balloon to four times its ASCII size, and most of the world's web traffic is in scripts that need only 1–3 bytes per character.

*UTF-8*, designed by Ken Thompson and Rob Pike in a single night in September 1992, is a variable-width encoding that solves this problem elegantly:

- Code points U+0000–U+007F (the ASCII range): stored in exactly 1 byte, identical to ASCII. English text stored in UTF-8 is byte-for-byte identical to ASCII.
- Code points U+0080–U+07FF (Latin extensions, Arabic, Hebrew, etc.): 2 bytes.
- Code points U+0800–U+FFFF (most of the BMP, including CJK): 3 bytes.
- Code points U+10000–U+10FFFF (emoji, rare scripts, mathematical alphanumerics): 4 bytes.

#gomaths("UTF-8 encoding scheme")[
  The bit layout of UTF-8 uses a clever prefix code to signal how many bytes follow. The patterns are:

  - 1-byte: `0xxxxxxx` (bit 7 = 0; 7 payload bits; code points 0–127)
  - 2-byte: `110xxxxx 10xxxxxx` (5 + 6 = 11 payload bits; code points 128–2047)
  - 3-byte: `1110xxxx 10xxxxxx 10xxxxxx` (4 + 6 + 6 = 16 bits; code points 0–65535)
  - 4-byte: `11110xxx 10xxxxxx 10xxxxxx 10xxxxxx` (3 + 6 + 6 + 6 = 21 bits; code points 0–1,114,111)

  A byte starting with `0` is a complete 1-byte character. A byte starting with `11` begins a multi-byte sequence; the number of leading `1`s tells you the total length. A byte starting with `10` is a *continuation byte* — a middle piece of a multi-byte character. This means you can always find the start of any character, even if you begin reading in the middle of a stream, and you can never mistake an ASCII byte for part of a multi-byte sequence.

  Example: encode '€' = U+20AC = 8364 in decimal = `0010 0000 1010 1100` in binary (13 bits). Needs 3 bytes:
  - Take 4 + 6 + 6 bits: `0010`, `000010`, `101100`.
  - Prefix: `1110_0010`, `10_000010`, `10_101100` = `0xE2 0x82 0xAC`.
]

UTF-8 became the dominant encoding on the web in 2008 and now accounts for over 98% of web pages. Every major operating system uses it as the default for new files. When a compressor reads text, it almost certainly encounters UTF-8 bytes — and a compressor that assumes ASCII (7-bit) will misclassify the high bytes of multi-byte characters, potentially degrading its model. PPM\* and the statistical models we will meet in Chapter 33 need to be Unicode-aware to work well on modern text.

#gopython("Strings and bytes in Python")[
  Python 3 keeps strings (type `str`) and raw bytes (type `bytes`) rigorously separate. A `str` is a sequence of Unicode code points. A `bytes` is a sequence of integers 0–255. You convert between them with `.encode()` and `.decode()`:

  ```python
  s = "Hello, 世界!"          # a str with Unicode
  b = s.encode("utf-8")       # bytes: b'Hello, \xe4\xb8\x96\xe7\x95\x8c!'
  print(len(s))    # 10 characters (code points)
  print(len(b))    # 16 bytes (the two CJK chars take 3 bytes each)

  # Inspect individual bytes
  for byte in b:
      print(f"{byte:3d}  0x{byte:02X}  {byte:08b}")

  # Decode back
  s2 = b.decode("utf-8")      # "Hello, 世界!"
  assert s == s2
  ```

  The important lesson: `len(s)` counts characters; `len(s.encode("utf-8"))` counts bytes. Compressors and binary format parsers operate on bytes. Always encode before measuring sizes. This distinction will matter in every chapter from here on.
]

=== Why character encoding matters for compression

If you feed a UTF-8 file to a compressor that thinks each byte is an independent symbol from a 256-symbol alphabet, it will work — but it will not model the structure of multi-byte characters. A context model that knows "a byte starting with `10` is always a continuation byte" can assign it high probability without wasting a bit on the thousands of byte values that can never appear there. The compression algorithms in Volumes II and III are byte-level; the neural and LLM-based methods in Volume IV can work at the code-point level and gain from Unicode structure. We will return to this in Chapter 33 (PPM) and Chapter 62 (LLMs).

== Floating-point numbers: real numbers in finite space

Integers are fine for counts and indices, but most interesting data — audio samples, pixel intensities, scientific measurements, neural network weights — involves numbers that are not whole. We need a way to represent fractions in bits.

=== The naive approach and why it fails

One approach: store a fixed number of bits for the integer part and a fixed number for the fractional part. This is called *fixed-point*. An 8.8 fixed-point number uses 8 bits for the integer part and 8 bits for the fraction, representing values in steps of $1/256 approx 0.004$. Fixed-point is still used in audio DSP and embedded systems where the range and precision requirements are known in advance. But it has a fatal limitation: it cannot represent both very small and very large numbers at the same time. A meteorologist needs to handle both the mass of a proton ($1.67 times 10^{-27}$ kg) and the mass of the Sun ($1.99 times 10^{30}$ kg) in the same program. Fixed-point cannot reach both ends.

The solution used by essentially all modern computing is *floating-point*, which represents numbers the way a scientist writes them: in the form $m times b^e$, where $m$ is a *mantissa* (or *significand*), $b$ is a base, and $e$ is an *exponent*. Instead of fixing the decimal point, we let it *float* — hence the name.

=== IEEE 754: the standard that unified floating-point

Before 1985, every computer manufacturer had its own floating-point format. Programs that ran correctly on an IBM machine gave wrong answers on a DEC machine. The nightmare ended with *IEEE 754-1985*, designed largely by William Kahan at UC Berkeley. It specified binary floating-point so precisely — right down to rounding rules for every operation — that a correctly implemented IEEE 754 program gives bit-for-bit identical results on any conforming machine. The 2008 revision (IEEE 754-2008) added decimal floating-point and half-precision; the 2019 revision is the current standard.

#algo(
  name: "IEEE 754 Binary Floating-Point",
  year: "1985 (revised 2008, 2019)",
  authors: "IEEE 754 committee, chaired by William Kahan (UC Berkeley)",
  aim: "Standardize binary floating-point representation and arithmetic, ensuring reproducible numerical results across all conforming hardware",
  complexity: "O(1) per arithmetic operation; hardware-implemented in every modern CPU and GPU",
  strengths: "Huge dynamic range; well-defined rounding; special values (NaN, Inf) enable graceful error handling; hardware support makes it fast",
  weaknesses: "Rounding errors accumulate in long calculations; not every decimal fraction has a finite binary representation (0.1 needs infinitely many binary digits, so it is stored only approximately); equality comparisons are treacherous",
  superseded: "Not superseded; extended by bfloat16 (ML), FP8 (ML inference), and posit arithmetic (proposed alternative)",
)[
  The three standard formats are *binary16* (half-precision, 16 bits), *binary32* (single-precision, 32 bits), and *binary64* (double-precision, 64 bits). The field layout is always sign | exponent | mantissa (fraction), with the exponent stored in *biased* form.
]

=== The structure of a 32-bit float

A *float* (IEEE 754 binary32) packs three fields into 32 bits:

#fig([IEEE 754 single-precision (32-bit) float bit layout. Bit 31 is the sign; bits 30–23 are the 8-bit biased exponent; bits 22–0 are the 23-bit fraction (mantissa). The hidden leading 1 bit gives 24 bits of effective precision.],
cetz.canvas({
  import cetz.draw: *
  let ht = 0.7
  let w_sign = 0.4
  let w_exp  = 2.0
  let w_frac = 4.8

  // sign
  rect((0, 0), (w_sign, ht), fill: rgb("#9a2617").lighten(70%), stroke: 0.7pt + rgb("#9a2617"))
  content((w_sign/2, ht/2), text(size: 7pt, fill: rgb("#9a2617"))[S])

  // exponent
  rect((w_sign, 0), (w_sign + w_exp, ht), fill: rgb("#0b5394").lighten(70%), stroke: 0.7pt + rgb("#0b5394"))
  content((w_sign + w_exp/2, ht/2), text(size: 7pt, fill: rgb("#0b5394"))[Exponent (8 bits)])

  // fraction
  rect((w_sign + w_exp, 0), (w_sign + w_exp + w_frac, ht),
    fill: rgb("#0f766e").lighten(70%), stroke: 0.7pt + rgb("#0f766e"))
  content((w_sign + w_exp + w_frac/2, ht/2), text(size: 7pt, fill: rgb("#0f766e"))[Fraction / Mantissa (23 bits)])

  // bit labels
  let positions = ((0.0, "31"), (0.4, "30"), (2.4, "23"), (2.4, "22"), (7.2, "0"))
  for (x, label) in positions {
    content((x, -0.25), text(size: 6.5pt)[#label])
    line((x, 0), (x, -0.15), stroke: 0.5pt)
  }

  // formula below
  content((3.6, -0.7), text(size: 8pt)[$(-1)^S times 1.f_(22) f_(21) dots f_0 times 2^(E-127)$])
  content((3.6, -1.05), text(size: 7pt, fill: rgb("#5b3a86"))[normal value formula (E = stored exponent, f = fraction bits)])
}))

The three fields mean:

- *Sign (1 bit)*: 0 = positive, 1 = negative. Always the most significant bit.
- *Exponent (8 bits)*: stored in *biased* form with bias 127. The stored value $E$ represents the true exponent $e = E - 127$. Stored value 0 and 255 are special (see below); usable values are 1–254, giving true exponents $-126$ to $+127$.
- *Fraction (23 bits)*: the binary digits *after* the leading 1. The full mantissa is $1.f_{22} f_{21} dots f_0$ — the "hidden bit" (the leading 1) is implicit and not stored, giving 24 bits of effective precision even though only 23 are stored.

The value of a *normal* float is:

$ v = (-1)^S times 1.f times 2^(E - 127) $

#gomaths("Bias in floating-point exponents")[
  Why store the exponent biased? Because biased encoding lets us compare two floats as if they were unsigned integers. If we stored the exponent in two's complement, comparing $1.5 times 2^{-3}$ to $1.0 times 2^{+1}$ would require looking at the sign of the exponent, which is messy. With bias 127, the stored exponent is always non-negative, and a simple unsigned integer comparison of the full 32-bit value correctly orders all finite positive floats. (Negative floats are trickier — their sign bits make unsigned comparison wrong — but the key property holds for positive values.)

  Example: the number $3.14$ in binary is approximately $11.001001_2$, which we normalize to $1.1001001 times 2^1$. The sign bit is 0 (positive). The true exponent is 1, so the stored exponent is $1 + 127 = 128 = 10000000_2$. The fraction field is the 23 bits after the decimal point: $10010001111010111000011_2$ (rounded). Full bit pattern: `0 10000000 10010001111010111000011`.
]

=== Special values: zero, infinity, and NaN

The exponents 0 and 255 (all zeros and all ones) are reserved for special cases:

- *Zero*: $E = 0$, fraction = 0. Sign bit gives $+0$ and $-0$. In IEEE 754 arithmetic, $+0 = -0$ for comparison purposes, though they differ bit-for-bit. Division by zero gives $±"Inf"$, not an error.
- *Denormals* (subnormals): $E = 0$, fraction $!= 0$. The formula changes: no hidden leading 1, and the true exponent is fixed at $-126$. Denormals let the standard represent numbers closer to zero than $2^{-126}$, at the cost of reduced precision. They are important for numerical robustness but can be slow on some hardware.
- *Infinity*: $E = 255$, fraction = 0. Represents $+infinity$ or $-infinity$. You get infinity from overflow or from $1.0 / 0.0$.
- *NaN* (Not a Number): $E = 255$, fraction $!= 0$. Represents undefined results: $0.0 / 0.0$, $sqrt(-1)$, $infinity - infinity$. NaN propagates: any arithmetic involving a NaN produces a NaN. Quiet NaNs propagate silently; signaling NaNs (rare) can trigger a hardware exception.

#misconception[
  "Floating-point numbers can represent any decimal fraction."
][
  They cannot. The fraction is stored in binary, and most decimal fractions are not exactly representable in binary. The famous example: $0.1$ in decimal. In binary, $0.1 = 0.000110011001100 dots_2$, repeating forever, the way $1/3 = 0.333 dots$ in decimal. The stored value is $0.1000000000000000055511151231257827021181583404541015625$ — close but not exact. This is why `0.1 + 0.2 != 0.3` in almost every programming language. For compression algorithms that process audio samples or scientific data, this matters: rounding errors accumulate, and a decompressor that uses slightly different arithmetic from the encoder can produce different results. The fix is careful design: use integers internally wherever possible, specify rounding modes, or use exact arithmetic libraries.
]

=== Common floating-point types

Beyond float32 and float64, two other formats deserve mention because they appear in media and machine-learning compression:

- *float16 (half-precision)*: 1 sign + 5 exponent + 10 fraction = 16 bits. Range roughly $±65504$; precision about 3 decimal digits. Used in neural network training (mixed-precision), some audio/image processing.
- *bfloat16*: 1 sign + 8 exponent + 7 fraction = 16 bits. Same exponent range as float32 but only 7 fraction bits (about 2 decimal digits of precision). Designed at Google for machine learning; the 8-bit exponent avoids the need for a separate float32 conversion layer. Widely used in ML accelerators (TPUs, modern NVIDIA GPUs). We will encounter bfloat16 again in Chapter 63 (model quantization).

#gopython("Floating-point inspection in Python")[
  Python's `float` is always a 64-bit double. To inspect the bits of a float, use `struct`:

  ```python
  import struct, math

  def float_bits(x: float) -> str:
      """Return the 32 IEEE-754 bits of x as a string of 0s and 1s."""
      [n] = struct.unpack("I", struct.pack("f", x))  # float → uint32
      return f"{n:032b}"

  for val in (1.0, -1.0, 0.1, math.inf, float("nan"), 0.0):
      bits = float_bits(val)
      print(f"{val:>12}  {bits[0]} {bits[1:9]} {bits[9:]}")
  ```

  Running this gives:
  ```
         1.0  0 01111111 00000000000000000000000
        -1.0  1 01111111 00000000000000000000000
         0.1  0 01111011 10011001100110011001101
         inf  0 11111111 00000000000000000000000
         nan  0 11111111 10000000000000000000000
         0.0  0 00000000 00000000000000000000000
  ```

  Notice that `1.0` has exponent bits `01111111` = 127, and true exponent $127 - 127 = 0$, so value = $1.0 times 2^0 = 1.0$. And `0.1` has exponent `01111011` = 123, true exponent $123 - 127 = -4$, and the fraction encodes the repeating pattern we just described.
]

=== Why floating-point matters for compression

Media codecs store everything — DCT coefficients, wavelet coefficients, spectrograms — as integers after quantization, precisely to avoid floating-point rounding headaches. But the road from signal to integer goes through floating-point arithmetic, and the choices made there affect both compression ratio and reconstructed quality. Scientific data (Chapter 66) often comes in float32 or float64 and must be compressed with care. And neural network weights (Chapters 56–64) are arrays of floats that must themselves be compressed, quantized, and transmitted — a topic where the bit structure we just built is directly relevant.

== Endianness: which byte comes first?

We have talked about multi-byte integers and floats, but we have not asked: in what order do the bytes get stored in memory? The answer depends on the *endianness* of the machine.

Consider the 32-bit integer `0x12345678` (a made-up value chosen for its obvious byte order). It has four bytes: `0x12`, `0x34`, `0x56`, `0x78`. At which memory address does each byte live?

- *Big-endian* (or *network byte order*): the most significant byte (`0x12`, the "big end") comes first, at the lowest address. Memory order: `12 34 56 78`.
- *Little-endian*: the least significant byte (`0x78`, the "little end") comes first, at the lowest address. Memory order: `78 56 34 12`.

#fig([Byte ordering for the 32-bit value 0x12345678 stored at address 0x1000. Big-endian stores the most significant byte first (at the lowest address); little-endian stores the least significant byte first.],
cetz.canvas({
  import cetz.draw: *
  let addr = ("1000", "1001", "1002", "1003")
  let big   = ("0x12", "0x34", "0x56", "0x78")
  let little = ("0x78", "0x56", "0x34", "0x12")
  let ht = 0.5
  let w  = 1.5

  // Big-endian
  content((3.0, 1.1), text(weight: "bold", size: 9pt)[Big-endian])
  for i in range(4) {
    rect((float(i)*w, 0.55), (float(i)*w + w - 0.05, 0.55 + ht),
      fill: rgb("#0b5394").lighten(75%), stroke: 0.7pt + rgb("#0b5394"))
    content((float(i)*w + w/2, 0.55 + ht/2), text(size: 8pt)[#big.at(i)])
    content((float(i)*w + w/2, 0.35), text(size: 7pt, fill: rgb("#783f04"))[0x#addr.at(i)])
  }

  // Little-endian
  content((3.0, -0.15), text(weight: "bold", size: 9pt)[Little-endian])
  for i in range(4) {
    rect((float(i)*w, -0.7), (float(i)*w + w - 0.05, -0.7 + ht),
      fill: rgb("#0f766e").lighten(75%), stroke: 0.7pt + rgb("#0f766e"))
    content((float(i)*w + w/2, -0.7 + ht/2), text(size: 8pt)[#little.at(i)])
    content((float(i)*w + w/2, -0.9), text(size: 7pt, fill: rgb("#783f04"))[0x#addr.at(i)])
  }
}))

=== Which machines use which?

- *Little-endian*: Intel/AMD x86 and x86-64 (all modern PCs and laptops), ARM (in its default, configurable mode), RISC-V. In practice, the vast majority of modern hardware is little-endian.
- *Big-endian*: IBM mainframes (z/Architecture), network protocols (hence "network byte order" = big-endian), old Motorola 68000 (classic Mac), Sun SPARC (classic workstations), PowerPC (big-endian mode). Most file formats that predate the x86 dominance — JPEG, PNG, AIFF, ZIP, many others — use big-endian for multi-byte fields.
- *Bi-endian*: ARM can run in either mode; modern ARM systems usually run little-endian. MIPS and PowerPC are also bi-endian.

The *POSIX* functions `htonl`/`htons`/`ntohl`/`ntohs` (host-to-network and network-to-host, for long and short) exist solely to swap bytes when needed, and `struct.pack` in Python lets you specify endianness with `"<"` (little) or `">"` (big).

#note[
  Endianness does *not* affect individual bytes. A single byte `0xA7` is just `0xA7` everywhere. Endianness only matters when multiple bytes together represent a single value. An 8-bit integer has no endianness; a 32-bit integer stored in four bytes has an endianness. This is why text encoded in pure ASCII (one character per byte) is endianness-neutral, but UTF-16 (two bytes per code point) needs a *byte-order mark* (BOM, U+FEFF) at the start of the file to indicate whether it is big- or little-endian.
]

=== Endianness in binary format specifications

Every binary format specification must state the endianness of its multi-byte fields. From the ZIP format specification:

> All multi-byte values in the ZIP specification are stored in little-endian (Intel) byte order.

From the PNG specification:

> All PNG integers are in big-endian byte order (network byte order).

From the WAVE audio format:

> Data is stored in little-endian byte order.

When you write a binary format parser — something every compressor needs — you must read the spec, get the endianness right, and use it consistently. Getting it wrong produces values that are byte-swapped, off by factors of 256 or 65536, and very hard to debug without a hex dump.

#gopython("Endianness with struct.pack / struct.unpack")[
  ```python
  import struct

  value = 0x12345678  # a 32-bit integer

  big_bytes    = struct.pack(">I", value)   # big-endian:    b'\x12\x34\x56\x78'
  little_bytes = struct.pack("<I", value)   # little-endian: b'\x78\x56\x34\x12'

  print(big_bytes.hex())     # 12345678
  print(little_bytes.hex())  # 78563412

  # Read a little-endian 32-bit int from bytes
  raw = bytes([0x78, 0x56, 0x34, 0x12])
  [n] = struct.unpack("<I", raw)
  print(hex(n))   # 0x12345678
  ```

  The format string `">I"` means: big-endian (`>`) unsigned 32-bit int (`I`). The `"<"` prefix forces little-endian. Format letter `"I"` = unsigned 32-bit; `"H"` = unsigned 16-bit; `"B"` = unsigned 8-bit. You will use this in almost every binary I/O task in the tinyzip project.
]

== Putting it all together: reading a hex dump

Let us end with a practical skill: reading a raw hex dump of bytes and narrating what they mean. Here is the first 16 bytes of a DEFLATE-compressed file (gzip format, which we will study in Chapter 30):

```
1F 8B 08 00 00 00 00 00 00 03
```

Byte by byte:

- `1F 8B`: the *magic number* identifying a gzip file. Every file format starts with a few bytes that are always the same, so software can identify the format without reading the extension.
- `08`: *compression method*. `08` means DEFLATE.
- `00`: *flags* byte. No flags set here.
- `00 00 00 00`: *modification time*, a 32-bit little-endian UNIX timestamp. Zero means "unknown."
- `00`: *extra flags* for the DEFLATE compressor.
- `03`: *operating system*. `03` means Unix/Linux. (This is why your gzip files look slightly different on Windows.)

Ten bytes of header, and we know the format, the method, the creation time, and the OS. All from the integer representations in this chapter: unsigned integers, little-endian multi-byte values, and a fixed magic number.

#gopython("Parsing a gzip header in Python")[
  ```python
  import struct, gzip, io

  def parse_gzip_header(data: bytes) -> dict:
      """Parse the 10-byte gzip fixed header."""
      if len(data) < 10:
          raise ValueError("Too short for a gzip header")
      magic, method, flags, mtime, xfl, os_id = struct.unpack("<2sBBIBB", data[:10])
      if magic != b"\x1f\x8b":
          raise ValueError(f"Not a gzip file: magic = {magic.hex()}")
      return {
          "magic":   magic.hex(),
          "method":  "DEFLATE" if method == 8 else f"unknown({method})",
          "flags":   f"0x{flags:02X}",
          "mtime":   mtime,  # Unix timestamp, 0 = unknown
          "xfl":     xfl,
          "os":      {0:"FAT",3:"Unix",7:"Mac",11:"NTFS"}.get(os_id, f"OS {os_id}"),
      }

  # Create a tiny gzip stream in memory
  buf = io.BytesIO()
  with gzip.GzipFile(fileobj=buf, mode="wb") as f:
      f.write(b"hello")
  buf.seek(0)
  raw = buf.read()

  header = parse_gzip_header(raw)
  for k, v in header.items():
      print(f"  {k:8s}: {v}")
  ```

  This is a real, working gzip header parser. It uses every concept from this chapter: magic numbers as unsigned integers, endianness (little-endian `"<"`), `struct.unpack` with a format string, and integer constants for OS IDs. When we build tinyzip's gzip-class core in Chapter 30, this function will be the decompressor's entry point.
]

#tryit[
  *A binary file inspector.* Before tinyzip can compress anything, it needs to read binary files byte-by-byte and display them. The tinyzip project proper begins in Chapter 15 (the package skeleton); for now, here is a self-contained utility that displays any file as a hex dump with a character sidebar — the standard tool every compressor developer reaches for when debugging a corrupted bitstream. Treat it as a warm-up you can run today, not yet an official project step.

  ```python
  # tinyzip/hexdump.py
  """Minimal hex dump utility for binary file debugging."""

  def hexdump(data: bytes, width: int = 16) -> None:
      """Print a hex dump of bytes, 'width' bytes per row."""
      for offset in range(0, len(data), width):
          chunk = data[offset : offset + width]
          # Hex portion: pairs of uppercase hex digits
          hex_part = " ".join(f"{b:02X}" for b in chunk)
          # ASCII sidebar: printable chars as-is, others as '.'
          asc_part = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
          # Right-pad the hex portion so sidebars line up
          print(f"  {offset:08X}  {hex_part:<{width*3}}  {asc_part}")

  def inspect_file(path: str) -> None:
      """Read a binary file and display its hex dump."""
      with open(path, "rb") as fh:
          data = fh.read()
      print(f"File: {path}  ({len(data)} bytes)")
      hexdump(data)

  if __name__ == "__main__":
      import sys
      inspect_file(sys.argv[1])
  ```

  Save this as `tinyzip/hexdump.py`. Run it on any file: `python tinyzip/hexdump.py /path/to/file`. You will see rows of 16 hex bytes and their ASCII printout, just like professional tools such as `xxd` or HxD. In Chapter 30, when we write the DEFLATE header, we will run hexdump on our output to verify every field is in the right place.
]

== Common patterns in binary formats

To close the loop, here are the conventions you will encounter in almost every binary format specification, stated once so we can reference them later:

=== Magic numbers and file signatures

Every well-designed binary format starts with a fixed byte sequence that identifies it. These are called *magic numbers* or *file signatures*:

- PNG: `89 50 4E 47 0D 0A 1A 0A` (the `89` ensures the file is binary, not text; `PNG` in ASCII follows)
- ZIP: `50 4B 03 04` (the letters `PK` for Phil Katz, the creator)
- JPEG: `FF D8 FF`
- PDF: `25 50 44 46` (`%PDF`)
- ELF (Linux executable): `7F 45 4C 46` (`\x7FELF`)
- gzip: `1F 8B`
- zstd frames: `FD 2F B5 28` (the Zstandard magic number, little-endian)
- Brotli streams: no fixed magic (it is designed to be embedded in other containers)

The file command on Unix reads these magic bytes to identify file types — no extension needed. Many formats choose magic bytes that include `0x00` (a null byte), because text editors would reject a file with embedded null bytes as "binary," preventing accidental corruption by text-mode file transfer.

=== Length-prefixed fields and CRCs

After the magic, most formats store fields as (length, data) pairs: first a fixed-size integer saying how many bytes of data follow, then the data itself. This lets a parser skip fields it does not understand without getting lost.

Many formats also include a *checksum* — usually a CRC-32 (cyclic redundancy check) or Adler-32 — that lets the decompressor detect corruption. The checksum is a function of all the data bytes; if even one bit flips in transit, the checksum will almost certainly disagree with the stored value. We will implement CRC-32 in Chapter 30.

=== Alignment and padding

CPUs read multi-byte values fastest when their address is a multiple of their size — a 32-bit int fastest at an address divisible by 4, a 64-bit double fastest at a multiple of 8. Some binary formats insert *padding bytes* to keep fields aligned. Others (like DEFLATE) pack bits so tightly that alignment is intentionally sacrificed for size. Compression formats generally prefer compactness over alignment, because the format's own decoder controls memory access patterns anyway.

#checkpoint[
  You find a file starting with the bytes `FF D8 FF E0`. What type of file is it? What does the `FF D8` mean?
][
  The magic bytes `FF D8 FF` identify a JPEG file. The third byte `FF` introduces an *EXIF* or *JFIF* application marker, and `E0` is the specific marker type `APP0` (JFIF application segment). So this is a standard JPEG file with JFIF metadata — which is the format most cameras and smartphones produce.
]

== Bit packing, flags, and bitmasks

One more pattern appears constantly in binary formats and compressor implementations: packing multiple small values into a single byte (or word) using *bit fields* and *bitmasks*. This is not just an efficiency trick — it is the primary language of protocol headers and codec flags.

=== Bitmasks and bitwise operations

Chapter 5 introduced the Boolean operations AND, OR, XOR, and NOT. When applied to integers, these operations work *bit by bit*, in parallel. The result of `a & b` (bitwise AND) has a 1 in position $i$ only when *both* `a` and `b` have a 1 there. The result of `a | b` (bitwise OR) has a 1 where *either* has a 1. `a ^ b` (XOR) has a 1 where they *differ*. `~a` (NOT / complement) flips every bit.

#gomaths("Bit shifting")[
  Two more operations are essential for bit manipulation. *Left shift* (`a << n`) moves every bit of `a` leftward by `n` positions, filling zeros on the right. Equivalently, `a << n` multiplies `a` by $2^n$. *Right shift* (`a >> n`) moves bits rightward; for unsigned values it fills zeros on the left, dividing by $2^n$ (rounding down).

  Examples with 8-bit values:
  - `00000001 << 3` = `00001000` = $1 times 2^3 = 8$
  - `10110100 >> 2` = `00101101` = $180 div 4 = 45$
  - `10110100 & 00001111` = `00000100` (keep only the low 4 bits — the nibble)
  - `10110100 | 00001111` = `10111111` (set the low 4 bits to all ones)
  - `10110100 ^ 11111111` = `01001011` (flip every bit — same as bitwise NOT)
]

A *mask* is a bit pattern designed to isolate or set specific bits. The idiom `(value >> shift) & mask` extracts a field from a packed byte. For example, the gzip flags byte has six defined bit positions, each controlling a feature:

```
Bit 0 (mask 0x01): FTEXT  — file is ASCII text
Bit 1 (mask 0x02): FHCRC  — header checksum present
Bit 2 (mask 0x04): FEXTRA — extra fields present
Bit 3 (mask 0x08): FNAME  — original filename present
Bit 4 (mask 0x10): FCOMMENT — comment present
Bits 5–7: reserved, must be zero
```

To test whether the original filename is present: `(flags & 0x08) != 0`. To set the FTEXT bit: `flags |= 0x01`. To clear the FHCRC bit: `flags &= ~0x02`. Every binary format uses some variant of this idiom.

=== A worked bitmap example

Suppose a tiny compression format packs four Boolean flags and a 4-bit depth value into a single byte header:

```
Bit 7:    endian flag (0=little, 1=big)
Bits 6–5: method (00=store, 01=RLE, 10=Huffman, 11=LZ77)
Bit 4:    checksum present
Bits 3–0: depth minus 1 (so values 1–16 fit in 4 bits, stored as 0–15)
```

The byte `10100110` would decode as:
- Bit 7 = 1 → big-endian
- Bits 6–5 = `01` → RLE compression
- Bit 4 = 0 → no checksum
- Bits 3–0 = `0110` = 6 → depth = 6 + 1 = 7

#gopython("Extracting bit fields")[
  ```python
  header_byte = 0b10100110  # = 0xA6 = 166

  endian    = (header_byte >> 7) & 0x1   # 1 = big-endian
  method    = (header_byte >> 5) & 0x3   # 0b01 = RLE
  has_crc   = (header_byte >> 4) & 0x1   # 0 = no checksum
  depth_m1  = header_byte & 0xF          # low 4 bits = 6
  depth     = depth_m1 + 1               # actual depth = 7

  method_names = {0: "store", 1: "RLE", 2: "Huffman", 3: "LZ77"}
  print(f"Endian: {'big' if endian else 'little'}")
  print(f"Method: {method_names[method]}")
  print(f"CRC: {'yes' if has_crc else 'no'}")
  print(f"Depth: {depth}")

  # Now re-pack the fields into a byte
  def pack_header(big_endian: bool, method: int, has_crc: bool, depth: int) -> int:
      return ((1 if big_endian else 0) << 7
              | (method & 0x3) << 5
              | (1 if has_crc else 0) << 4
              | ((depth - 1) & 0xF))

  rebuilt = pack_header(True, 1, False, 7)
  assert rebuilt == header_byte, f"Mismatch: {rebuilt:#04X} != {header_byte:#04X}"
  print(f"Rebuilt: {rebuilt:#010b}")
  ```

  This pattern — left-shift each field to its position, OR them together — appears in virtually every binary format encoder ever written. Master it and you can read or write any protocol on Earth.
]

=== Sign extension pitfall

One notorious bug when extracting bit fields: *sign extension*. If you mask out a 4-bit signed value and store it in a Python `int` (which is always signed), the bits look positive. But if you cast to a C `int8_t` or try to interpret the high bit as a sign bit, the value appears negative. Always be explicit about whether a field is signed or unsigned, and test boundary values (the maximum and the one-negative value, e.g., the 4-bit values 7 and 8 = $-8$).

#pitfall[
  In Python, `(-42) >> 3` gives $-6$ (arithmetic right shift — fills with 1s to preserve the sign), not $+26$. This can surprise programmers coming from C, where signed right shift is implementation-defined. If you want a logical (unsigned) right shift in Python, either mask first: `(n & 0xFF) >> 3` for an 8-bit value, or use a `uint` type from the `ctypes` module. Compressors that shift bit fields must be careful here.
]

== The whole picture: from signal to bytes

Let us trace the path from a real-world signal to the bytes we compress, tying together everything in this chapter.

*Scenario*: you record your voice at 44.1 kHz, 16-bit stereo (the compact-disc standard).

1. *Sampling*: the microphone produces a continuously varying voltage. An analog-to-digital converter samples it 44,100 times per second. Each sample is a number between $-1.0$ and $+1.0$.
2. *Quantization*: each sample is rounded to the nearest 16-bit signed two's complement integer — one of 65,536 possible values from $-32768$ to $+32767$. This is the first loss of information; we will study quantization in detail in Chapter 39.
3. *Packing*: stereo means two samples (left and right channel) per time step. At 44,100 samples/second × 2 channels × 2 bytes/sample, raw audio consumes $44100 times 2 times 2 = 176400$ bytes per second — about 10 MB per minute.
4. *Storage*: a WAVE file stores these bytes in little-endian order (the Windows/Intel convention), preceded by a header that tells the decoder the sample rate, bit depth, and number of channels.
5. *Compression*: a lossless codec (FLAC, Chapter 50) or lossy codec (MP3/Opus, Chapters 47–49) reads those bytes and shrinks them. The codec's decoder must know the byte layout of the input precisely.

Every step — the 16-bit signed integer, the two-byte little-endian order, the sample rate in the header — is one of the representations we studied today. A compressor that gets any of them wrong silently produces garbage.

#note[
  The choice of 44.1 kHz as the CD sampling rate is itself a compression story. The CD's architects digitized audio onto a modified video signal, and the video frame rate (25 Hz in Europe) times lines per frame times samples per line gave 44.1 kHz almost exactly. The slightly odd rate is a fossil from the transition between analog and digital video. History is full of these compression-driven decisions that got baked into standards forever.
]

#takeaways((
  [A computer's memory is a flat, addressed array of bytes. Every piece of data — integer, float, character, compressed bitstream — is a sequence of bytes at some address.],
  [*Unsigned integers* map $n$ bits to $2^n$ values (0 to $2^n-1$). Overflow wraps silently; always track your integer sizes.],
  [*Two's complement* represents signed integers by reinterpreting the high half of the unsigned range as negative. Negation is "flip bits, add 1." Subtraction uses the same hardware as addition.],
  [*ASCII* encodes 128 English characters in 7 bits. *Unicode* extends this to all human scripts; *UTF-8* encodes Unicode in 1–4 bytes per code point, is backward compatible with ASCII, and is the dominant encoding on the modern web.],
  [*IEEE 754* floats pack a sign bit, a biased exponent, and a fractional mantissa. Special patterns encode $±infinity$ and NaN. Most decimal fractions are not exactly representable in binary.],
  [*Endianness* determines which byte of a multi-byte value is stored first. Little-endian (LSB first) dominates modern hardware; big-endian (MSB first) is common in older file formats and network protocols. Always check the spec.],
  [Binary format headers combine magic numbers, unsigned fields, endianness, checksums, and length prefixes. Reading a hex dump and narrating the bytes is a core skill for anyone who works with compressed files.],
))

== Exercises

#exercise("13.1", 1)[
  A 10-second mono audio clip is recorded at 48 kHz with 24-bit samples. How many bytes does the raw (uncompressed) audio occupy? Express your answer in megabytes (to two decimal places). If each byte uses 8 bits, how many total bits is that?
]

#solution("13.1")[
  Samples: $48000 times 10 = 480{,}000$. Bytes per sample: $24 / 8 = 3$. Total bytes: $480{,}000 times 3 = 1{,}440{,}000$ bytes $= 1.44$ MB. Total bits: $1{,}440{,}000 times 8 = 11{,}520{,}000$ bits.
]

#exercise("13.2", 1)[
  Convert the 8-bit two's complement value `11010110` to a signed decimal integer. Show your work using the signed place-value formula.
]

#solution("13.2")[
  The MSB is 1, so this is negative. The signed formula gives: $-1 times 2^7 + 1 times 2^6 + 0 times 2^5 + 1 times 2^4 + 0 times 2^3 + 1 times 2^2 + 1 times 2^1 + 0 times 2^0 = -128 + 64 + 16 + 4 + 2 = -42$.
]

#exercise("13.3", 2)[
  The bytes `3F 80 00 00` appear in a binary file at a position that holds a big-endian IEEE 754 float32. What value do they represent? Identify the sign, exponent, and fraction fields and compute the result.
]

#solution("13.3")[
  In binary: `0 01111111 00000000000000000000000`. Sign = 0 (positive). Exponent bits = `01111111` = 127; true exponent = $127 - 127 = 0$. Fraction = all zeros. Value = $(-1)^0 times 1.0 times 2^0 = 1.0$. The bytes `3F 80 00 00` represent the floating-point value $1.0$.
]

#exercise("13.4", 2)[
  Write a Python function `twos_complement(n: int, bits: int) -> str` that takes a signed integer `n` and a bit width `bits`, and returns the two's complement bit string. Handle the edge cases `n = 0`, `n = -1`, and $n = -2^(b-1)$ (where $b$ is the bit width). Test it on `-42` with 8 bits (answer should match Exercise 13.2 in reverse).
]

#solution("13.4")[
  ```python
  def twos_complement(n: int, bits: int) -> str:
      """Return the two's complement bit string for signed integer n."""
      if not (-(2**(bits-1)) <= n <= 2**(bits-1) - 1):
          raise ValueError(f"{n} out of range for {bits}-bit signed integer")
      # Python's modular arithmetic handles negatives automatically
      unsigned = n % (2**bits)
      return f"{unsigned:0{bits}b}"

  # Tests
  print(twos_complement(0,   8))   # 00000000
  print(twos_complement(-1,  8))   # 11111111
  print(twos_complement(-128, 8))  # 10000000
  print(twos_complement(-42, 8))   # 11010110 ✓
  print(twos_complement(42,  8))   # 00101010
  ```
]

#exercise("13.5", 2)[
  The UTF-8 byte sequence `E2 82 AC` encodes a single Unicode character. Decode it by hand: identify the multi-byte pattern, extract the payload bits, and determine which Unicode code point it represents. What character is it?
]

#solution("13.5")[
  `0xE2` = `11100010` — starts with `1110`, so this is a 3-byte sequence. Pattern: `1110xxxx 10xxxxxx 10xxxxxx`. Payload bits: from `0xE2` = `0010`; from `0x82` = `000010`; from `0xAC` = `101100`. Concatenate: `0010 000010 101100` = `0010000010101100` = 0x20AC. That is U+20AC = `€`, the Euro sign.
]

#exercise("13.6", 2)[
  Write a Python function `to_utf8(codepoint: int) -> bytes` that encodes a single Unicode code point as UTF-8 without using Python's built-in `.encode()`. Handle all four byte-length cases (1, 2, 3, 4 bytes). Test it on `0x41` (A), `0x00E9` (é), `0x4E16` (世), and `0x1F600` (😀).
]

#solution("13.6")[
  ```python
  def to_utf8(cp: int) -> bytes:
      """Encode a Unicode code point as UTF-8 bytes."""
      if cp < 0 or cp > 0x10FFFF:
          raise ValueError(f"Invalid code point: U+{cp:04X}")
      if cp <= 0x7F:
          return bytes([cp])
      elif cp <= 0x7FF:
          b1 = 0xC0 | (cp >> 6)
          b2 = 0x80 | (cp & 0x3F)
          return bytes([b1, b2])
      elif cp <= 0xFFFF:
          b1 = 0xE0 | (cp >> 12)
          b2 = 0x80 | ((cp >> 6) & 0x3F)
          b3 = 0x80 | (cp & 0x3F)
          return bytes([b1, b2, b3])
      else:
          b1 = 0xF0 | (cp >> 18)
          b2 = 0x80 | ((cp >> 12) & 0x3F)
          b3 = 0x80 | ((cp >> 6) & 0x3F)
          b4 = 0x80 | (cp & 0x3F)
          return bytes([b1, b2, b3, b4])

  # Tests
  assert to_utf8(0x41)    == "A".encode("utf-8")     # b'A'
  assert to_utf8(0x00E9)  == "é".encode("utf-8")     # b'\xc3\xa9'
  assert to_utf8(0x4E16)  == "世".encode("utf-8")    # b'\xe4\xb8\x96'
  assert to_utf8(0x1F600) == "😀".encode("utf-8")   # b'\xf0\x9f\x98\x80'
  print("All tests passed")
  ```
]

#exercise("13.7", 1)[
  A 32-bit little-endian integer in a binary file is stored as the bytes `FF 0F 00 00`. What decimal integer do those four bytes represent? What would the same bytes mean as a big-endian integer?
]

#solution("13.7")[
  Little-endian: reassemble as `0x00000FFF` = $4095$. Big-endian: reassemble as `0xFF0F0000` = $4,278,517,760$. The same four bytes mean completely different numbers depending on endianness — a good reminder to always check the spec.
]

#exercise("13.8", 3)[
  Write a function `detect_encoding(data: bytes) -> str` that examines the first few bytes of `data` and returns a string identifying the character encoding: `"ASCII"` if all bytes are in 0–127, `"UTF-8"` if the data is valid UTF-8 (including ASCII), `"UTF-16-LE"` if it starts with `FF FE`, `"UTF-16-BE"` if it starts with `FE FF`, or `"BINARY"` otherwise. Do not use any standard library encoding-detection function; do it from first principles. Test it on a UTF-8 encoded file and a raw JPEG file (which will read as BINARY).
]

#solution("13.8")[
  ```python
  def detect_encoding(data: bytes) -> str:
      if len(data) >= 2 and data[:2] == b"\xff\xfe":
          return "UTF-16-LE"
      if len(data) >= 2 and data[:2] == b"\xfe\xff":
          return "UTF-16-BE"
      # Try to validate as UTF-8
      i = 0
      all_ascii = True
      while i < len(data):
          b = data[i]
          if b > 127:
              all_ascii = False
          if b & 0x80 == 0:          # 1-byte
              i += 1
          elif b & 0xE0 == 0xC0:    # 2-byte
              if i+1 >= len(data) or (data[i+1] & 0xC0) != 0x80:
                  return "BINARY"
              i += 2
          elif b & 0xF0 == 0xE0:    # 3-byte
              if i+2 >= len(data):  return "BINARY"
              if (data[i+1] & 0xC0) != 0x80: return "BINARY"
              if (data[i+2] & 0xC0) != 0x80: return "BINARY"
              i += 3
          elif b & 0xF8 == 0xF0:    # 4-byte
              if i+3 >= len(data):  return "BINARY"
              if (data[i+1] & 0xC0) != 0x80: return "BINARY"
              if (data[i+2] & 0xC0) != 0x80: return "BINARY"
              if (data[i+3] & 0xC0) != 0x80: return "BINARY"
              i += 4
          else:
              return "BINARY"      # invalid start byte
      return "ASCII" if all_ascii else "UTF-8"
  ```
]

#exercise("13.9", 3)[
  A signed 32-bit two's complement counter in a network packet starts at $2{,}147{,}483{,}640$ (very close to the maximum of $2{,}147{,}483{,}647$). Messages arrive at 10 per second. After how many seconds does the counter overflow? What is the counter's value immediately after overflow? Write a Python program that simulates 20 steps of this counter using a fixed 32-bit signed type (simulate the wrap by computing `n % (2**32)` and re-interpreting as signed), and print the first and last five values.
]

#solution("13.9")[
  The counter has $2{,}147{,}483{,}647 - 2{,}147{,}483{,}640 = 7$ steps until reaching the maximum, then 1 more step to overflow. At 10 per second, overflow happens after $8/10 = 0.8$ seconds. After overflow, the counter wraps from $+2^{31}-1$ to $-2^{31} = -2{,}147{,}483{,}648$.

  ```python
  def as_int32(n: int) -> int:
      """Interpret n modulo 2^32 as a signed 32-bit integer."""
      n = n % (2**32)
      if n >= 2**31:
          n -= 2**32
      return n

  start = 2_147_483_640
  values = [as_int32(start + i) for i in range(20)]
  print("First 5:", values[:5])
  print("Last  5:", values[15:])
  # First 5: [2147483640, 2147483641, ..., 2147483644]
  # Around step 8: wraps to −2147483648, then −2147483647, …
  ```
]

== Further reading

- #link("https://www.joelonsoftware.com/2003/10/08/the-absolute-minimum-every-software-developer-absolutely-positively-must-know-about-unicode-and-character-sets-no-excuses/")[Joel Spolsky, "The Absolute Minimum Every Software Developer Absolutely, Positively Must Know About Unicode and Character Sets" (2003)] — the best plain-English introduction to character encoding ever written.
- #link("https://unicode.org/standard/standard.html")[The Unicode Standard, current version (Unicode 16.0, 2024)] — the authoritative reference for all character assignments, UTF-8/16/32 encoding rules, and normalization.
- #link("https://ieeexplore.ieee.org/document/8766229")[IEEE 754-2019, *Standard for Floating-Point Arithmetic*] — the normative standard. Free to access through many university libraries.
- #link("https://floating-point-gui.de/")[Michael Borgwardt, "What Every Programmer Should Know About Floating-Point Arithmetic"] — an excellent web reference on FP pitfalls, rounding, and what `0.1 + 0.2 != 0.3` really means.
- #link("https://docs.python.org/3/library/struct.html")[Python `struct` module documentation] — the definitive reference for `struct.pack`/`unpack` format strings, covering all integer and float types and both endiannesses.
- #link("https://commandlinefanatic.com/cgi-bin/showarticle.cgi?article=art001")[Joshua Davies, "How Computers Represent Numbers"] — a clear, deep walkthrough of integer and floating-point formats, suitable for anyone who wants more derivation than this chapter provides.

#bridge[
  We now know what data *is* at the byte level: the agreements about integers, characters, floats, and byte order that let machines exchange meaning. But we have not yet asked: *how do we process* those bytes efficiently? Chapter 14 — Algorithms, Data Structures, and Complexity — builds the algorithmic toolkit that every compressor relies on: arrays, hash tables, trees, heaps, Big-O analysis, and the pseudocode notation we will use throughout the rest of the book. Once we have those, we will be fully equipped to build our first real compressor in Chapter 24.
]
