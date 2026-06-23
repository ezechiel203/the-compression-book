#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Error-Correction Boundary

#epigraph[
  We may not be able to make our channels noiseless, but we can make our messages
  shout over the noise — by saying them in a smarter, more redundant way.
][after Claude Shannon, _A Mathematical Theory of Communication_, 1948]

A compact disc has a scratch across it the width of a sewing needle — perhaps
two-and-a-half millimetres of music simply gouged away, hundreds of thousands of
bits vaporised. You drop it in the player and it plays. No skip, no click, not a
single wrong note. The same disc, if you had stored the audio as a `.zip` file
and the player had unzipped it, would have refused to open at all — one flipped
bit and the decompressor throws up its hands.

That is the whole drama of this chapter in a single image. For the last
seventy-one chapters we have been *removing* every scrap of redundancy we could
find, because redundancy is wasted space and our job was to make files small. Now
we are going to spend an entire chapter putting redundancy *back in* — carefully,
deliberately, by the bit — because a maximally-compressed file is also a
maximally *fragile* one. Squeeze out every drop of slack and the file becomes a
house of cards: every bit now carries its full share of meaning, so every bit
you lose is meaning you cannot recover. The art of *error-correcting codes* is
the art of adding back exactly the right redundancy, in exactly the right shape,
so that noise bounces off.

This is not a contradiction. It is the other half of Shannon's 1948 paper, the
half most compression books quietly skip. Compression and error correction are
two sides of one coin — they are *duals* — and the seam where they meet is one of
the most beautiful and practically important boundaries in all of engineering.
We will walk right up to that seam, look at the four great families of codes that
live there (CRCs, Reed--Solomon, LDPC, and polar codes), and then visit the
places where compression and error correction are forced to hold hands: a QR code
on a coffee cup, a strand of DNA in a freezer, a voice on a glitchy call, the
flash chip in your phone.

#recap[
  In *Chapter 18* we measured information as entropy $H$, the irreducible floor for
  *removing* redundancy. In *Chapter 19* the Source Coding Theorem proved you cannot
  squeeze below $H$ bits per symbol without losing information. Then *Chapter 20*
  introduced the *other* direction: a noisy *channel* with *capacity* $C$, the
  *Noisy-Channel Coding Theorem* (you can communicate reliably at any rate below
  $C$), the *duality* between compression and error correction, and the
  *source--channel separation theorem* — the licence to design the two stages
  independently. This chapter cashes in those theorems: it builds the actual codes
  that add redundancy back, and shows exactly where separation succeeds and where
  it cracks. We lean on logarithms (*Ch. 7*), modular and binary arithmetic
  (*Ch. 4*), probability (*Ch. 9*), and a little vector/matrix thinking (*Ch. 12*).
]

#objectives((
  [Explain *why* a heavily compressed file is fragile, and state the
   *compress-then-protect* pattern that the separation theorem licenses — plus the
   four situations where that licence is revoked.],
  [Compute a *parity bit*, a *Hamming(7,4)* codeword, and the *Hamming distance* of
   a small code, and connect minimum distance to how many errors a code can detect
   and correct.],
  [Describe how a *CRC* detects errors with polynomial division, and why a CRC is a
   *detector*, not a *corrector*.],
  [Explain *Reed--Solomon* as evaluating a polynomial at many points, why it is
   ideal for *burst* errors and *erasures*, and where it lives (CDs, QR codes,
   RAID, satellites).],
  [Sketch how *LDPC* and *polar* codes approach the Shannon limit, and why one rules
   Wi-Fi/5G data and the other rules 5G control channels.],
  [Analyse the four *meeting points* — DNA storage, QR codes, Opus DRED, and flash —
   where compression and protection must be co-designed.],
))

== Why small means brittle

Let us make the opening image precise, because the intuition matters more than
any single code. Take the eight-character string `"aaaaaaaa"`. Stored raw in
ASCII (*Ch. 13*) it is eight bytes, sixty-four bits. Its entropy is essentially
zero — one symbol repeated — so a good compressor stores it in a handful of bits:
"the letter `a`, eight times." Now flip one bit of the *compressed* version. If
the bit you hit was the count, you now decompress to `aaaa` or `aaaaaaaaaaaaaaaa`.
If you hit the symbol, you get `bbbbbbbb`. One bit of damage, and the *entire*
message is wrong. Flip one bit of the *raw* sixty-four-bit version, by contrast,
and you get one slightly-off character among eight perfect ones. You can still
read it.

#keyidea[
  Redundancy is *error tolerance in disguise*. Natural data is full of redundancy
  (English text, photographs, audio), and that redundancy quietly absorbs damage —
  a typo in a sentence is still readable. Compression removes that slack to save
  space. So *the better you compress, the closer you push each bit to carrying its
  full meaning, and the less damage any single bit can absorb.* Perfect compression
  and zero error tolerance are the same condition, seen from two sides.
]

There is a clean way to see why this *must* be true, straight from *Chapter 22*'s
incompressibility argument. A truly optimal compressor maps messages to bit
strings such that *every* output string is a valid, distinct message — there are
no "gaps," no illegal codewords, because a gap would be wasted space the
compressor could have reclaimed. But error correction *needs* gaps. It works
precisely by leaving most bit strings *illegal*, so that when noise nudges a legal
codeword, it lands on an illegal one and the decoder can shout "that's wrong!" and
even guess the nearest legal codeword. A code with no illegal strings cannot
detect any error at all. Compression fills the space; error correction empties it.
They pull in opposite directions by construction.

#misconception[that a good compressor should also be robust to corruption, "for
free."][A good _lossless_ compressor is the *opposite* of robust: it is designed to
use every available bit string, which is exactly the property that makes it unable
to notice corruption. Robustness has to be added back as a *separate, deliberate
layer*. The only compressors that degrade gracefully are _lossy_ ones (Chapter 21
onward) whose bitstreams were _engineered_ to fail softly — and even those usually
ride on top of an error-correction layer underneath.]

#fig([Two layers, two opposite jobs. The *source coder* (compressor) squeezes the
message down toward its entropy $H$; the *channel coder* (error-correction
encoder) then expands it back out by a controlled amount to survive a channel of
capacity $C$. The decoder reverses both. This is the *separation* architecture of
Chapter 20.],
cetz.canvas({
  import cetz.draw: *
  let bx(x, y, w, h, label, col) = {
    rect((x,y), (x+w, y+h), fill: col, stroke: 0.6pt + rgb("#1a1a1a"), radius: 2pt)
    content((x+w/2, y+h/2), text(size: 7.5pt)[#label])
  }
  bx(0, 0, 1.8, 0.8, "message", rgb("#f4f6f8"))
  bx(2.2, 0, 2.0, 0.8, [source\ coder], rgb("#cfe3d8"))
  bx(4.6, 0, 2.2, 0.8, [channel\ coder], rgb("#cfe0f0"))
  bx(7.2, 0, 1.6, 0.8, "channel", rgb("#f0d9d6"))
  bx(9.2, 0, 2.2, 0.8, [channel\ decoder], rgb("#cfe0f0"))
  bx(11.8, 0, 2.0, 0.8, [source\ decoder], rgb("#cfe3d8"))
  bx(14.2, 0, 1.7, 0.8, "message", rgb("#f4f6f8"))
  line((1.8,0.4),(2.2,0.4), mark: (end: ">"))
  line((4.2,0.4),(4.6,0.4), mark: (end: ">"))
  line((6.8,0.4),(7.2,0.4), mark: (end: ">"))
  line((8.8,0.4),(9.2,0.4), mark: (end: ">"))
  line((11.4,0.4),(11.8,0.4), mark: (end: ">"))
  line((13.8,0.4),(14.2,0.4), mark: (end: ">"))
  content((3.2,1.15), text(size: 6.5pt, fill: rgb("#0b6e4f"))[remove redundancy])
  content((5.7,1.15), text(size: 6.5pt, fill: rgb("#0b5394"))[add redundancy])
  content((8.0,-0.5), text(size: 6.5pt, fill: rgb("#9a2617"))[noise enters here])
}))

== Compress, then protect — and when the licence is revoked

The fragility argument seems to say: *never* compress fully, always keep some
slack for safety. Shannon's separation theorem says something far more elegant and
useful. Recall the result from *Chapter 20*:

#theorem("Source–Channel Separation")[
  To send a source of entropy $H$ (bits/symbol) reliably over a channel of capacity
  $C$ (bits/use), it is *optimal* — loses nothing — to do the two jobs *separately*:
  first compress the source down to its entropy floor $H$, then independently apply
  an error-correcting code matched to the channel's capacity $C$. A combined
  ("joint source--channel") scheme can do no better. Reliable transmission is
  possible *if and only if* $H < C$.
]

This is the theorem that built the modern world. It says you may *fully* compress
first — squeeze to the bone, $H$ bits — and *then* add protection as a clean,
independent second stage. The two teams never have to talk. The JPEG committee
need not know whether their images travel over Wi-Fi, 5G, or a CD; the Wi-Fi
engineers need not know whether the bits are images, audio, or spreadsheets.
Every file format and every transmission standard you have ever used is built on
this separation. *Compress-then-protect* is not a compromise; it is provably
optimal — *in the limit*.

#keyidea[
  *Compress-then-protect.* Run the data through the best compressor you can (Volumes
  II--IV), then wrap the compressed bytes in an error-correcting code sized to the
  channel. Decoder side: correct errors *first*, then decompress the now-clean
  bytes. The fragility of compressed data is fine *because* the protection layer
  hands the decompressor a clean stream — the brittleness never gets tested.
]

But read the theorem's fine print: "in the limit." Separation is optimal only
when blocks can be arbitrarily long, delay is unbounded, and the channel is a
single, known, memoryless link. The real world violates all three constantly, and
that is precisely where this chapter earns its keep. There are *four* situations
where the licence to separate is revoked, and a clever engineer must let the two
layers talk:

+ *Short blocks / low latency.* Separation's optimality is asymptotic — it needs
  long codewords. A real-time voice call cannot wait a second to fill a long block;
  a control message in a phone network is a few dozen bits. At those lengths,
  jointly designed schemes beat the separated ideal. (This is why Opus DRED, later,
  bakes redundancy *into* the codec.)

+ *Networks, not links.* Shannon analysed one sender, one receiver, one channel.
  The Internet is a mesh of relays and broadcasts, and there separation is
  provably *not* optimal in general — the deep results of *network information
  theory* (still partly open in 2026) show joint coding can win.

+ *Unequal importance.* Separation assumes every bit is equally precious. But in a
  compressed bitstream some bits are catastrophic to lose (a header, a motion
  vector) and others merely cosmetic (a high-frequency texture coefficient).
  *Unequal error protection* — shielding the important bits more heavily — is a
  joint idea by definition.

+ *Lossy + perception.* When the goal is not bit-exactness but *looking/sounding
  right* (Chapter 21's rate--distortion--perception frontier), graceful degradation
  beats hard failure, and the codec itself should be built to fail softly.

#checkpoint[A satellite link drops to a capacity of $C = 0.5$ bits per channel use.
You must send a sensor source whose entropy is $H = 0.9$ bits per symbol, one
symbol per channel use. Can you transmit it reliably, no matter how clever your
codes?][No. Separation (and its converse) says reliable transmission requires
$H < C$, and here $0.9 < 0.5$ is false. You must either compress _lossily_ to push
the effective $H$ below $0.5$, send fewer symbols per channel use, or accept errors.
No error-correcting code can manufacture capacity that is not there.]

== The atoms of error correction: parity, distance, and Hamming

Before the famous codes, we need the two simplest ideas in the field, because
every later code is a sophisticated elaboration of them. The first is *parity*.

Take any block of bits and append one extra bit — the *parity bit* — chosen so
that the total number of `1`s is even. Send `1011` and you have three `1`s (odd),
so append a `1` to make four: `10111`. If the receiver counts an odd number of
`1`s, *at least one* bit flipped in transit. That is the entire mechanism behind
the humble parity bit that guarded computer memory and serial lines for decades.

#gomaths("Modular arithmetic and XOR")[
  *Modular arithmetic* is "clock arithmetic." Working _modulo 2_ means we only care
  whether a number is even ($0$) or odd ($1$), and we wrap around: $1 + 1 = 2$, but
  $2 mod 2 = 0$. So mod-2 addition is: $0+0=0$, $0+1=1$, $1+0=1$, $1+1=0$. That last
  line — same inputs give $0$, different inputs give $1$ — is _exactly_ the
  _exclusive-or_ (XOR) gate from *Chapter 5*, written $xor$. A parity bit is
  just the XOR of all the data bits: $1 xor 0 xor 1 xor 1 =
  1$. Mod-2 arithmetic is the bedrock of almost every error-correcting code, because
  computer bits _are_ numbers mod 2, and XOR is its own inverse: $a xor a =
  0$, so $(a xor b) xor b = a$. Damage by XOR, undo by XOR.
]

Parity *detects* a single error but cannot *locate* it, and so cannot fix it. If
you flip a second bit, parity is fooled — two flips look like none. To do better
we need the central concept of the whole field: *Hamming distance*, named for
Richard Hamming, who in 1947 at Bell Labs was so enraged that his weekend
computation jobs aborted on a single card-reader error that he invented codes that
*fix* errors rather than merely flagging them.

#definition("Hamming distance")[
  The *Hamming distance* between two equal-length bit strings is the number of
  positions in which they differ. $d(10110, 10011) = 2$ (positions 3 and 4 differ).
  The *minimum distance* $d_min$ of a _code_ — its set of legal codewords — is the
  smallest Hamming distance between any two distinct codewords.
]

Minimum distance is the single number that governs a code's power, via a fact so
clean it deserves a proof.

#theorem("Distance bounds")[
  A code with minimum distance $d_min$ can _detect_ up to $d_min - 1$ errors, and
  _correct_ up to $floor((d_min - 1)/2)$ errors, where $floor(dot)$ rounds down.
]

#proof[
  Picture each codeword as a point, and around it a ball of all strings within some
  Hamming radius. _Detection:_ if fewer than $d_min$ bits flip, the received word
  cannot have reached a _different_ legal codeword (the nearest one is $d_min$ away),
  so any non-zero error of size $< d_min$ lands on an illegal string and is caught —
  $d_min - 1$ detectable. _Correction:_ draw a ball of radius $t = floor((d_min -
  1)/2)$ around every codeword. Because any two codewords are at least $d_min >= 2t
  + 1$ apart, these balls _never overlap_. A received word with at most $t$ errors
  lies inside exactly one ball, so "decode to the nearest codeword" recovers the
  original unambiguously. With more than $t$ errors the balls could be escaped, and
  correctness is no longer guaranteed.
]

So distance buys power: to *correct* $t$ errors you need $d_min >= 2t+1$. Parity
has $d_min = 2$ (any two valid even-parity words differ in at least two places):
it detects $1$, corrects $floor(1/2) = 0$. Now Hamming's leap. He arranged *three*
parity bits so cleverly that their combined verdict spells out, in binary, the
*position* of the broken bit.

#fig([The *Hamming(7,4)* code. Three overlapping parity circles cover four data
bits; each parity bit makes its circle even. A single flipped bit violates a unique
combination of circles, and that combination, read as a binary number, _is_ the
address of the culprit.],
cetz.canvas({
  import cetz.draw: *
  circle((0,0), radius: 1.5, stroke: 0.8pt + rgb("#0b5394"))
  circle((1.4,0), radius: 1.5, stroke: 0.8pt + rgb("#0b6e4f"))
  circle((0.7,-1.2), radius: 1.5, stroke: 0.8pt + rgb("#783f04"))
  content((-0.9,0.7), text(size: 8pt)[$p_1$])
  content((2.3,0.7), text(size: 8pt)[$p_2$])
  content((0.7,-2.3), text(size: 8pt)[$p_3$])
  content((0.7,0.45), text(size: 8pt)[$d_4$])
  content((0.1,-0.55), text(size: 8pt)[$d_1$])
  content((1.3,-0.55), text(size: 8pt)[$d_2$])
  content((0.7,-1.05), text(size: 8pt)[$d_3$])
}))

Hamming(7,4) takes 4 data bits and emits 7-bit codewords; its minimum distance is
$3$, so it corrects any single error and detects any double. Let us run it once,
by hand, because seeing the syndrome point straight at the broken bit is the kind
of small miracle that makes the field click.

#gomaths("Working a Hamming(7,4) decode")[
  Lay the seven positions out so the _parity_ bits sit at the power-of-two slots and
  _data_ bits fill the rest: positions $1,2,4$ are parities $p_1,p_2,p_3$; positions
  $3,5,6,7$ are data $d_1,d_2,d_3,d_4$. Each parity covers the positions whose binary
  index has its bit set: $p_1$ (slot 1) covers $1,3,5,7$; $p_2$ (slot 2) covers
  $2,3,6,7$; $p_3$ (slot 4) covers $4,5,6,7$. Encode the data $1011$: \
  $p_1 = d_1 xor d_2 xor d_4 = 1 xor 0 xor 1 = 0$;
  $quad p_2 = d_1 xor d_3 xor d_4 = 1 xor 1 xor 1 = 1$;
  $quad p_3 = d_2 xor d_3 xor d_4 = 0 xor 1 xor 1 = 0$. \
  Codeword (positions $1..7$): $0,1,1,0,0,1,1$. Now flip position 5 in transit:
  received $0,1,1,0,#text(fill: rgb("#9a2617"))[$1$],1,1$. Recompute the three parity
  checks (the _syndrome_): check-1 over $1,3,5,7 = 0 xor 1
  xor 1 xor 1 = 1$; check-2 over $2,3,6,7 = 1 xor 1 xor
  1 xor 1 = 0$; check-4 over $4,5,6,7 = 0 xor 1 xor 1 xor
  1 = 1$. Read the syndrome as binary $s_4 s_2 s_1 = 101 = 5$. The syndrome literally
  _spells out 5_ — flip position 5 back, and you have repaired the word. That is
  Hamming's beautiful trick: the parity verdicts, read as a number, are the address
  of the wound.
]

The distance-bounds theorem promised that "decode to the *nearest* codeword" always
recovers the original when there are at most $t = floor((d_min - 1)/2)$ errors. That
rule is so simple we can write it in a few lines of Python, and watch it repair a
corrupted word for *any* small code — no algebra required, just counting
disagreements. It is slow (it scans every codeword), but it is the literal
definition of *minimum-distance decoding*, and seeing it run makes the theorem
tangible.

```python
def hamming(a: list[int], b: list[int]) -> int:
    # count positions where the two equal-length words disagree
    return sum(x != y for x, y in zip(a, b))

def decode_nearest(received: list[int],
                   codebook: list[list[int]]) -> list[int]:
    # return the legal codeword closest in Hamming distance
    return min(codebook, key=lambda c: hamming(received, c))

# the tiny code from Exercise 72.2, d_min = 3, corrects 1 error
codebook = [[0,0,0,0,0,0], [1,1,1,0,0,0],
            [0,0,0,1,1,1], [1,1,1,1,1,1]]
sent     = [1,1,1,0,0,0]
got      = [1,0,1,0,0,0]            # one bit flipped in position 2
print(decode_nearest(got, codebook))   # -> [1, 1, 1, 0, 0, 0], repaired
```

#pyrecall[`zip(a, b)` (Ch. 16) walks two lists in lockstep, pairing `a[0]` with
`b[0]`, and so on; `sum(x != y for ...)` adds up a stream of `True`/`False` values,
which Python counts as `1`/`0` — so it tallies the disagreements. `min(seq,
key=f)` returns the element of `seq` for which `f` is smallest, and the
`lambda c: ...` (Ch. 16) is a one-line throwaway function naming each candidate
codeword `c` — together they say "the codeword `c` minimising the distance."]

The `min(..., key=...)` call is Python's way of saying "of all these codewords, give
me the one for which `hamming(received, c)` is smallest" — exactly "find the nearest
legal codeword." Real decoders never enumerate the whole codebook (it is
astronomically large for useful codes); the genius of Reed--Solomon, LDPC, and polar
is *algebra and graph structure* that find the nearest codeword *without* the brute
search. But the *goal* is always this one line.

#history[
  Richard Hamming devised his codes around 1947--1950 at Bell Telephone
  Laboratories, in the same building and era as Shannon. Frustrated that a single
  mispunched relay would kill a weekend's batch job, he reasoned that a machine
  smart enough to _detect_ an error ought to be smart enough to _fix_ it. Bell
  initially withheld publication for patent reasons; the paper appeared in 1950.
  Hamming codes, and the "Hamming distance" idea, became the conceptual seed of the
  entire discipline of coding theory — and Hamming won the 1968 Turing Award.
]

== CRCs: cheap, powerful error *detection*

Now to the code you have used ten thousand times today without knowing it. Every
Ethernet frame, every ZIP and PNG and gzip file (the tinyzip _container_ of
*Chapter 17* ended with one!), every disk sector carries a *cyclic redundancy
check* — a CRC. A CRC does not *correct* anything. It is a brilliant *detector*: a
short checksum, typically 32 bits, computed so that almost any accidental
corruption changes it, letting the receiver say "this block is damaged — resend"
or "this archive is corrupt — refuse to open."

The trick is to treat the whole message as the coefficients of a giant polynomial
in mod-2 arithmetic, then take its *remainder* when divided by a fixed, carefully
chosen "generator" polynomial.

#gomaths("Polynomials over bits, and CRC division")[
  A _polynomial_ is just a sum of powered terms, like $x^3 + x + 1$. Over bits, each
  coefficient is $0$ or $1$, so a bit string _is_ a polynomial: $1011 -> x^3 + x +
  1$. We divide polynomials by long division, but with _mod-2_ arithmetic, so every
  subtraction is an XOR — no borrows, no carries. A CRC fixes a _generator_
  polynomial $G(x)$ of degree $r$ (CRC-32 uses a degree-32 one). To protect a
  message $M(x)$, you shift it up by $r$ bits (append $r$ zeros), divide by $G(x)$,
  and the _remainder_ $R(x)$ is the $r$-bit CRC. Transmit $M$ followed by $R$. The
  receiver re-divides the whole received block by $G$; if the remainder is _not_
  zero, the data is corrupt. Because XOR division is so regular, CRCs run at
  gigabytes per second in a few machine instructions.
]

Let us turn the crank once, by hand, on a tiny example, so the "remainder" is not
just a word. Take the generator $G = 1011$ (that is $x^3 + x + 1$, degree $r = 3$)
and the four-bit message $M = 1101$. Append $r = 3$ zeros to get the dividend
$1101000$, then XOR-divide by $1011$, aligning the generator under the leftmost
remaining `1` at each step:

#block(inset: (left: 10pt))[
```
 1101000   ← message with 3 appended zeros
 1011      ← G aligned under the leading 1
 ----
 0110000   ← XOR; bring down
  1011     ← G aligned under next leading 1
  ----
  0011000
   0000    ← leading bit is 0: skip (G does not fit)
   ----
   011000
    1011   ← G aligned
    ----
    01110
     1011  ← G aligned
     ----
     0101  ← remainder R = 101  (3 bits, since deg G = 3)
```
]

The CRC is the remainder $R = 101$. We transmit $M$ followed by $R$:
$1101#text(fill: rgb("#0b6e4f"))[$101$])$. By construction, the full transmitted
word $1101101$ is now *exactly divisible* by $G$ — its remainder is zero. The
receiver simply divides what it got by $G$; a zero remainder means "looks clean,"
and *any* non-zero remainder means "corrupted." That is the whole mechanism:
shift, divide, send the remainder, and re-divide on arrival.

Why is this any good? Because a well-chosen generator polynomial guarantees strong
properties: a CRC-$r$ catches *all* single-bit errors, all double-bit errors
(with the right $G$), any odd number of errors (if $G$ has $x+1$ as a factor),
and — crucially — *every burst error shorter than $r+1$ bits*. That last property
is gold, because real-world corruption tends to come in *bursts*: a scratch, a
dropout, a flaky connector hits *consecutive* bits. The burst guarantee is worth a
proper proof, because it explains *why* engineers pick the generator's degree to
match the worst burst they expect.

#theorem("CRC burst detection")[
  A CRC with a generator polynomial $G(x)$ of degree $r$ detects *every* error burst
  of length at most $r$ — that is, any corruption confined to $r$ or fewer
  consecutive bit positions is guaranteed to be caught.
]

#proof[
  Think of the error as a pattern $E(x)$ that is XORed into the transmitted word; the
  receiver's check fails exactly when $E(x)$ is *not* divisible by $G(x)$ (because the
  clean word is divisible, so the received remainder equals $E$'s remainder). A burst
  of length $L <= r$ confined to consecutive positions can be written $E(x) = x^j dot
  B(x)$, where $x^j$ shifts the burst to its position and $B(x)$ is a polynomial of
  degree at most $L - 1 < r$ with a non-zero constant term (its first and last burst
  bits are `1`). Now, $G(x)$ has degree $r$, and a standard CRC generator has a
  non-zero constant term, so $x^j$ shares no factor with $G$ — $G$ cannot divide
  $x^j$. And $G$ cannot divide $B(x)$ either, because $deg B < r = deg G$ and $B != 0$
  (a non-zero polynomial cannot be a multiple of one of strictly higher degree). Since
  $G$ shares no factor with $x^j$ and does not divide $B(x)$, it cannot divide their
  product $E(x) = x^j B(x)$ either. Hence the
  remainder is non-zero and the burst is detected.
]

#algo(
  name: "Cyclic Redundancy Check (CRC)", year: "1961",
  authors: "W. Wesley Peterson (and D. T. Brown)",
  aim: "Detect accidental corruption in stored or transmitted blocks, cheaply and at line rate.",
  complexity: [$O(n)$ over the message; table-driven or hardware versions process bytes/words at a time.],
  strengths: [Tiny overhead (e.g. 32 bits per block); catches all bursts shorter than $r{+}1$; all 1- and 2-bit errors; trivially fast in hardware.],
  weaknesses: [_Detection only_ — cannot fix anything; not cryptographically secure (an attacker can forge data with a valid CRC); blind to certain rare patterns that are multiples of $G$.],
  superseded: [Complemented (not replaced) by cryptographic hashes for security and by error _correction_ (Reed--Solomon, LDPC) when resend is impossible.],
)[
  CRCs are everywhere a system can afford to _ask for a retransmission_: Ethernet
  (CRC-32), the gzip/PNG/ZIP file footers, SATA, USB, and countless protocols. The
  insight: detection is far cheaper than correction, so when a back-channel exists
  ("please resend"), detect-and-retransmit beats forward correction.
]

#pitfall[A CRC is _not_ a security mechanism. It catches _accidental_ errors, not
_deliberate_ tampering: anyone can alter a file and recompute a matching CRC in
microseconds. For integrity against an adversary you need a _cryptographic_ hash or a
_message authentication code_ — a function deliberately built so that nobody can find
a different message with the same checksum without the secret key. (Compression and
cryptography are cousins but separate disciplines; we stay in our lane here.)
Confusing the two has sunk real protocols.]

== Reed--Solomon: the workhorse that saved the CD

If CRCs are the world's detector, *Reed--Solomon* (RS) codes are its great
*corrector*. They are the reason a scratched CD still plays, a damaged QR code
still scans, a failed drive in a RAID array loses no data, and the Voyager probes
phoned home from beyond Pluto. Irving Reed and Gustave Solomon published them in
1960 — five lonely pages in a SIAM journal — and they did not become practical for
nearly a decade, until decoders caught up. The idea is one of the prettiest in
engineering.

#keyidea[
  *Reed--Solomon in one sentence:* treat your $k$ data symbols as the coefficients
  of a polynomial, then transmit that polynomial's _value at $n > k$ different
  points_. Because any polynomial of degree $< k$ is _completely determined by any
  $k$ of its values_ (two points fix a line; three fix a parabola; $k$ points fix a
  degree-$(k{-}1)$ curve), you can lose up to $n - k$ of the transmitted values and
  _still reconstruct the curve_ — and hence the data — exactly.
]

That over-determination is the magic. Send $n = 255$ values of a curve that only
needs $k = 223$ to pin down, and you can lose *any* $32$ of them and rebuild
perfectly. Lose more and you cannot — but $32$ is a lot of slack, deliberately
sprinkled across the transmission.

#gomaths("Why $k$ points fix a degree-$(k{-}1)$ polynomial")[
  Through any $2$ distinct points there is exactly _one_ straight line ($y = a x +
  b$, two unknowns, two equations). Through any $3$ points in "general position"
  there is exactly one parabola ($y = a x^2 + b x + c$, three unknowns). In general,
  a polynomial of degree $k - 1$ has $k$ unknown coefficients, so $k$ value-equations
  determine it _uniquely_ — this is _polynomial interpolation_, and the formula that
  does it is _Lagrange interpolation_. Reed--Solomon turns this schoolbook fact into
  armour: encode by _evaluating_ a degree-$(k{-}1)$ polynomial at $n$ points; decode
  by _interpolating_ it back from any surviving $k$. The redundancy is the $n - k$
  extra evaluations.
]

There are two flavours of damage, and RS handles both, but with very different
budgets. An *erasure* is a symbol you know is missing (a CD reports "this sample
is unreadable"); you know *where* the hole is. An *error* is a symbol that is wrong
but *looks* fine — you must find *both* its location and its correct value. Finding
the location costs you, which is why:

#theorem("Reed–Solomon correction budget")[
  An RS code with $n$ total symbols and $k$ data symbols has minimum distance
  $d_min = n - k + 1$ (it is _maximum-distance separable_, the best any code can do).
  It can correct any $n - k$ _erasures_, or any $t$ _errors_ with $2t <= n - k$ — so
  twice as many erasures as errors, because erasures come with their location for
  free.
]

#proof[
  Two distinct data polynomials of degree $< k$ agree in at most $k - 1$ points
  (their difference is a non-zero degree-$<k$ polynomial, which has at most $k - 1$
  roots). So two distinct codewords, evaluated at all $n$ points, can coincide in at
  most $k - 1$ positions, i.e. they _differ_ in at least $n - (k-1) = n - k + 1$
  positions. Hence $d_min >= n - k + 1$. The _Singleton bound_ says $d_min <= n - k +
  1$ for _any_ code, so RS hits it exactly — it is optimal. By the distance bounds
  above, $d_min = n-k+1$ corrects $floor((n-k)/2)$ errors; with erasures' known
  positions the syndrome equations halve in number, doubling the budget to $n - k$
  erasures.
]

The proof leaned on the *Singleton bound* — the claim that *no* code, however
clever, can beat $d_min = n - k + 1$. It is worth proving on its own, because it
tells us Reed--Solomon is not just good but *provably optimal* for its rate: you
cannot squeeze more correction power out of $n - k$ redundant symbols than RS
already gives.

#theorem("Singleton bound")[
  For *any* block code with codewords of length $n$ carrying $k$ symbols of data
  (one of $q^k$ distinct messages, over an alphabet of size $q$), the minimum
  distance satisfies $d_min <= n - k + 1$.
]

#proof[
  Take all $q^k$ codewords and *delete* the last $d_min - 1$ symbol positions from
  every one of them, leaving strings of length $n - (d_min - 1)$. We claim the
  shortened strings are still *all distinct*. Suppose two codewords became equal after
  deletion; then before deletion they agreed everywhere except possibly within those
  $d_min - 1$ deleted positions, so they differed in at most $d_min - 1$ places — a
  Hamming distance strictly *less* than $d_min$, contradicting the definition of
  $d_min$. So the $q^k$ shortened strings are distinct strings of length $n - d_min +
  1$. But there are only $q^(n - d_min + 1)$ possible strings of that length, so we
  need $q^k <= q^(n - d_min + 1)$, i.e. $k <= n - d_min + 1$, which rearranges to
  $d_min <= n - k + 1$. Codes that hit this bound with equality (like RS) are called
  _maximum-distance separable_ — they extract the maximum possible protection from
  every redundant symbol.
]

There is one wrinkle we have glossed over. Doing Reed--Solomon with ordinary
school arithmetic — where a "symbol" could be any number $3, 4, 5, 6, dots$ — would
let values grow without bound and never fit in a fixed-size byte. Real codes do the
polynomial arithmetic inside a _finite field_, and that idea is worth one box,
because it is the algebraic floor every serious code stands on.

#gomaths("Finite fields and GF(256)")[
  A _field_ is just a number system where you can add, subtract, multiply, and
  _divide_ (except by zero) and the familiar rules still hold. The rationals and the
  reals are infinite fields. A _finite field_ — also called a _Galois field_, written
  $"GF"(q)$ — packs all four operations into a _finite_ set of $q$ values that _wraps
  around_ like a clock, so arithmetic never escapes the set. The simplest is
  $"GF"(2) = {0, 1}$, where addition is XOR and multiplication is AND — the mod-2
  world of every parity bit and CRC above (we met $"GF"(2)$ briefly in *Chapter 71*).

  Reed--Solomon over bytes uses $"GF"(256)$: exactly $256$ values, one per possible
  byte ($0$ to $255$). You cannot build it by plain "mod 256," because then some
  non-zero values have no multiplicative inverse (you could not divide). Instead each
  byte is treated as a tiny degree-$<8$ _polynomial_ over $"GF"(2)$, and multiplication
  is polynomial multiplication taken _modulo a fixed irreducible polynomial_ of degree
  $8$ — the same "divide and keep the remainder" trick as a CRC, which is why it stays
  inside $8$ bits. The payoff: every byte except $0$ has an inverse, so the
  interpolation and Gaussian-elimination steps a decoder needs are _always_ solvable,
  and every intermediate result is _still a single byte_. That is the whole reason
  Reed--Solomon's "evaluate a polynomial at $n$ points" plan works on real,
  fixed-width data: the field $"GF"(256)$ guarantees the arithmetic never overflows
  and never gets stuck.
]

A quick numeric taste shows the polynomial idea is concrete, not abstract. Suppose
$k = 2$ data symbols $(3, 1)$ define the line $f(x) = 3 + 1 dot x$ (so $f(0)=3$,
$f(1)=4$, $f(2)=5$, …, doing ordinary arithmetic for illustration). Transmit
$n = 4$ evaluations $f(0), f(1), f(2), f(3) = 3, 4, 5, 6$. Now lose *any* two of
them, say keep only $f(1) = 4$ and $f(3) = 6$. Two points fix a line: slope
$(6 - 4)/(3 - 1) = 1$, intercept $4 - 1 dot 1 = 3$, recovering $f(x) = 3 + x$ and
hence the original data $(3, 1)$ — exactly. We lost half the transmission and
reconstructed perfectly, because we sent twice as many points as the curve needed.
Real RS does this over a *finite field* $"GF"(256)$ (so each "symbol" is a byte and
the arithmetic wraps cleanly), but the geometry is identical: over-evaluate, then
interpolate back from the survivors.

#algo(
  name: "Reed–Solomon code", year: "1960",
  authors: "Irving S. Reed, Gustave Solomon",
  aim: "Correct symbol errors and erasures, especially bursts, by polynomial over-evaluation; an optimal (MDS) block code.",
  complexity: [Encode $O(n k)$ (or $O(n log n)$ with transforms); decode (Berlekamp--Massey + Chien + Forney) $O(n^2)$ or better.],
  strengths: [Optimal distance $n{-}k{+}1$; superb on _burst_ errors because each symbol is a whole byte (one burst damages few symbols); handles erasures at double rate; mature, fast hardware.],
  weaknesses: [Works on _symbols_ not bits, so scattered single-bit errors waste its budget; for the white-noise (AWGN) channel it falls short of capacity — beaten by LDPC/turbo at long block lengths.],
  superseded: [For random bit-noise channels, by LDPC/turbo/polar; but RS _still_ dominates storage, optical media, QR, RAID, and is layered _with_ convolutional codes (concatenation) on deep-space links.],
)[
  Reed--Solomon shines whenever errors clump. A scratch on a CD wipes thousands of
  _consecutive_ bits, but after de-_interleaving_ (the CD spreads each codeword's
  symbols far apart on the disc) those map to only a handful of damaged _symbols_ —
  well within RS's budget. The CD's _CIRC_ scheme is two interleaved RS codes; QR
  codes use RS over the byte-field $"GF"(256)$; RAID-6 is an RS code with two parity
  symbols; DVDs, Blu-ray, DSL, and the Voyager probes all lean on it.
]

The de-interleaving trick deserves a closer look, because it is the quiet hero
that turns RS from "good against scattered symbol errors" into "unbeatable against
real-world scratches." Suppose your RS code can fix at most $t$ damaged symbols per
codeword, but a physical scratch wipes out a *run* of, say, $5t$ consecutive
symbols. If those symbols all belonged to one codeword, you would be hopelessly
over budget. So before writing to the disc, you *interleave*: lay symbols from many
different codewords side by side, like shuffling several decks together, so that
any short physical run touches *at most one symbol from each codeword*. After
reading, you *de-interleave* (un-shuffle), and the giant burst is spread thin —
each codeword sees only one or two errors, comfortably inside its $t$-symbol
budget. Interleaving converts a *concentrated* burst into *scattered* single-symbol
errors, which is exactly the diet RS thrives on.

#note[Interleaving is *not* error correction by itself — it adds *no* redundancy and
fixes *nothing*. It is a *rearrangement* that reshapes the error pattern into one
the real code can handle. Coding theory is full of these "shapers" — interleavers,
the masking in QR codes, the bit-plane ordering in JPEG 2000 — that cost almost
nothing yet multiply the power of the code they wrap. Knowing *when* a problem is a
shaping problem versus a coding problem is half the craft.]

#history[
  Reed--Solomon sat on the shelf from 1960 until Elwyn Berlekamp's 1968 decoding
  algorithm (refined by James Massey) made it practical. Its first triumph was deep
  space: a concatenated RS+convolutional code flew on _Voyager_ (1977) and let
  grainy whispers from Neptune become crisp images. Then in 1982 the compact disc
  put a Reed--Solomon decoder in tens of millions of living rooms — the first time
  most people owned, unknowingly, a device doing real-time algebraic error
  correction. Today RS silicon ships in essentially every storage device on Earth.
]

== Approaching the Shannon limit: LDPC and polar codes

Reed--Solomon is optimal _as a block code with that structure_, but on the
classic *noisy bit channel* (think faint radio with Gaussian static), it does not
reach Shannon's capacity $C$.

#mathrecall[The _Gaussian_ (or _AWGN_, additive white Gaussian noise) channel — a
real wire or radio link that corrupts each transmitted level with bell-curve noise —
was introduced in *Chapter 20*, where its capacity is the Shannon--Hartley formula
$C = B log_2(1 + S\/N)$, and the Gaussian distribution itself got its own box in
*Chapter 21*. It is the standard model for "faint signal, random static," and the
channel where reaching capacity was hardest.] Here is the painful gap that haunted the field for
half a century. Shannon's 1948 theorem (*Chapter 20*) *proved* that codes exist
which transmit reliably at any rate below capacity $C$ — but his proof was
*non-constructive*. It showed such codes were overwhelmingly common if you picked a
giant codebook at *random*, without giving any way to *build* one you could
actually *decode*. A random codebook is useless in practice: decoding it means
comparing the received word against every one of astronomically many codewords, a
computation that explodes long before the block gets long enough to approach $C$.
So for decades there was a maddening twenty-percent-or-more gap between what the
theory promised and what real codes delivered, and closing it was the central open
problem of coding theory.

#keyidea[
  The challenge after Shannon was never "do good codes exist?" — he proved they do.
  It was "can we build codes that are *both* near-capacity *and* efficiently
  *decodable*?" The breakthrough in both LDPC and polar codes is *not* a cleverer
  codebook; it is a *clever decoding structure* — a sparse graph you can gossip over,
  or a recursive transform you can peel apart — that makes near-optimal decoding
  *cheap*. Decodability, not existence, was the wall.
]

For decades, getting *close* to $C$ on such channels seemed hopeless for exactly
that reason. Two breakthroughs — one a 1990s resurrection, one a 2008 invention —
finally crashed through the wall. They now carry your Wi-Fi, your 5G, your
satellite TV.

=== LDPC: a forgotten 1962 idea, rediscovered

*Low-Density Parity-Check* (LDPC) codes were Robert Gallager's 1962 MIT doctoral
thesis. The idea: use a *huge* block with *many* parity checks, but arrange each
check to touch only a *few* bits (hence "low-density"). Decoding is *iterative
belief propagation* — each bit and each parity check passes "messages" of soft
probabilistic opinion back and forth along a graph until the whole block settles
into a consistent, high-confidence answer. Gallager's idea was decades ahead of
the silicon needed to run it, and the field forgot it. In 1996, David MacKay and
Radford Neal *rediscovered* LDPC codes and showed they come breathtakingly close
to the Shannon limit. By then computers could finally afford the iteration.

#gomaths("Belief propagation, intuitively")[
  Imagine a Sudoku you solve by gossip. Each _cell_ (a received bit) has a hunch
  about its value, expressed as a _probability_, not a hard $0/1$ — a "soft" belief
  like "I'm $70%$ sure I'm a $1$." Each _constraint_ (a parity check that must come
  out even) listens to all its cells, then whispers back to each one: "given what
  your siblings told me, here's what _you_ should more likely be." Cells update
  their hunches, constraints re-whisper, round after round. Because the graph is
  _sparse_ (each check sees few bits, each bit sees few checks), these rumours
  rarely loop back on themselves quickly, so the gossip _converges_ to a confident,
  globally-consistent answer. That round-robin of soft probabilities is _belief
  propagation_ (a.k.a. the _sum--product algorithm_) — the same machinery that
  powers much of modern AI inference. Using _soft_ probabilities, not hard
  decisions, is the secret sauce that lets LDPC sip the last fraction of capacity.
]

#algo(
  name: "Low-Density Parity-Check (LDPC) code", year: "1962 / 1996",
  authors: "Robert G. Gallager (1962); rediscovered by David MacKay & Radford Neal (1996)",
  aim: "Approach Shannon capacity on noisy (especially Gaussian) channels via a sparse parity-check graph and iterative soft decoding.",
  complexity: [Encode can be made $O(n)$; decode $O(n times "iterations")$ of local message passing — highly parallel.],
  strengths: [Within a fraction of a decibel of capacity at long block lengths; massively parallel decoding; flexible rates; royalty-friendlier than turbo codes.],
  weaknesses: [Needs long blocks and many iterations to shine; an "error floor" at very low error rates; latency from iteration; complex code design.],
  superseded: [Not superseded — it _won_. LDPC is the data-channel code of Wi-Fi (since 802.11n/ac/ax), 5G data, DVB-S2 satellite, 10GBASE-T Ethernet, and modern flash.],
)[
  LDPC's comeback is one of coding theory's great stories: a thesis idea sits
  unbuildable for thirty-four years until Moore's Law catches up, then storms every
  standards body in a decade. It shares the iterative-decoding crown with _turbo
  codes_ (Berrou, Glavieux & Thitimajshima, 1993), which sparked the whole
  capacity-approaching revolution; LDPC mostly displaced turbo in newer standards
  for its parallelism and cleaner patents.
]

=== Polar codes: the first _proven_ capacity-achieving code

In 2008, Erdal Arıkan did something nobody had managed in the sixty years since
Shannon: he constructed a code, with an explicit, efficient algorithm, *proven*
to *achieve* capacity as the block length grows — not approach it empirically,
*reach* it by theorem. The mechanism is *channel polarization*, and it is gorgeous.

#keyidea[
  *Channel polarization.* Combine $N$ copies of a mediocre channel through a simple
  recursive XOR transform, then re-split them into $N$ _synthetic_ channels. As $N$
  grows, a magical thing happens: the synthetic channels _polarize_ — each becomes
  either _almost perfect_ (capacity near $1$) or _almost useless_ (capacity near
  $0$), with almost nothing in between. The fraction that turn perfect equals the
  original capacity $C$. So the recipe writes itself: send your real data bits
  through the _perfect_ synthetic channels, and "freeze" the useless ones to known
  values. You have routed information around the noise.
]

#gomaths("Polarization from two channels")[
  Take two uses of a noisy bit channel. Instead of sending bits $u_1, u_2$ directly,
  send $x_1 = u_1 xor u_2$ on the first and $x_2 = u_2$ on the second (one XOR
  — that is the whole transform). Now look at the two _synthetic_ channels the
  decoder sees. Decoding $u_1$ _first_, with $u_2$ still unknown, is _harder_ than a
  raw channel — it has noise from both uses piled on. But once $u_1$ is known,
  decoding $u_2$ is _easier_ — you get two noisy looks at it. One channel got worse,
  one got better: they pulled apart. Now nest this transform recursively, $log_2 N$
  levels deep, and the pulling-apart compounds until the channels are _fully_
  polarized into near-perfect and near-useless. The recursion is just a butterfly of
  XORs — cheap to build, $O(N log N)$ to decode by _successive cancellation_.
]

#algo(
  name: "Polar code", year: "2008",
  authors: "Erdal Arıkan",
  aim: "The first explicit, low-complexity codes mathematically _proven_ to achieve channel capacity as block length grows without bound.",
  complexity: [Encode and _successive-cancellation_ decode both $O(N log N)$; list decoding adds a factor $L$.],
  strengths: [Provably capacity-achieving; excellent at _short_ block lengths (with CRC-aided _successive-cancellation list_ decoding), which is exactly where 5G control messages live; deterministic structure.],
  weaknesses: [Plain successive-cancellation decoding is mediocre at finite lengths — needs CRC-aided _list_ decoding to compete; inherently somewhat serial; tricky rate-matching.],
  superseded: [Not superseded — adopted into _5G New Radio_ for the _control_ channels (2016), while LDPC took the _data_ channels; an active research front for 6G.],
)[
  The 3GPP standards committee's 2016 decision split the 5G coding crown: _LDPC_ for
  the high-throughput _data_ channel, _polar codes_ for the latency-critical,
  short-block _control_ channel — a perfect illustration of "different jobs, different
  codes." With CRC-aided successive-cancellation _list_ decoding (keep the $L$ best
  candidate paths, let the CRC pick the true one), polar codes shine precisely in the
  short-block regime where the separation theorem's asymptotics no longer hold.
]

#aside[Notice how the CRC reappears _inside_ the polar decoder — not to ask for a
resend, but to _pick the winner_ among $L$ candidate decodings. The humble detector
becomes a referee for the corrector. Detection and correction, supposedly separate
jobs, fuse in the modern decoder.]

#scoreboard(caption: "Four code families, at a glance",
  [Parity bit], [+1 bit], [—], [Detects 1; the simplest brick],
  [Hamming(7,4)], [+3/4 bits], [—], [Corrects 1 bit; the conceptual seed],
  [CRC-32], [+4 bytes/block], [—], [_Detects_ only; line-rate; ZIP/Ethernet],
  [Reed--Solomon], [tunable $n{-}k$], [—], [Corrects bursts/erasures; CD, QR, RAID],
  [LDPC], [tunable rate], [—], [Near-capacity; Wi-Fi/5G _data_, DVB-S2],
  [Polar], [tunable rate], [—], [Capacity-achieving; 5G _control_],
)

== Where the worlds meet (1): DNA data storage

Now we visit the four boundaries where compression and protection are forced to
co-design — the places the separation theorem's fine print bites. The first is the
most exotic: storing data in *DNA*, the subject of *Chapter 70*.

DNA is an astonishing storage medium — a gram can in principle hold _hundreds of
petabytes_ and last millennia in a cold, dry vault — but it is a *vicious*
channel. You *synthesise* strands (write) and *sequence* them (read), and both
steps make errors: substitutions, plus *insertions* and *deletions* of whole bases
("indels") that even shift everything downstream out of frame. Worse, you cannot
address a specific molecule; you read a soup of millions of fragments in random
order, some copied many times, some not at all — pure *erasures* and dropouts.

This is exactly the wrong channel for "compress to the bone, then bolt on
protection as an afterthought." Erlich and Zielinski's 2017 *DNA Fountain* (Science
355) showed the way: it pairs strong compression with a *fountain code* (an
erasure code, *Chapter 70*, that lets you generate limitless redundant droplets and
recover the file from _any_ sufficiently large subset that survives), and *then*
layers a Reed--Solomon code on top for the substitution errors. They reached around
215 petabytes per gram at roughly 85% of the channel's information capacity — a
co-designed stack, not a separated one.

Notice how every layer of this chapter resurfaces in a single DNA pipeline. The
*fountain code* is an *erasure* code — it answers the "molecules vanish from the
soup" problem, the same job RS does for CD samples, but tuned for a channel where
you cannot even count how many copies survived. The *Reed--Solomon* layer on top
answers the "a base got mis-read" problem (substitutions). The *constrained coding*
(*Chapter 70*) answers a problem the CD never had: the medium itself *rejects*
certain strings — a long run of identical bases (`AAAAAA`) confuses the sequencer,
and lopsided GC content destabilises the molecule — so the encoder must *avoid*
those patterns, which means deliberately *not* using some of the bit strings it
otherwise could. That last point is the deepest twist: constrained coding is
*redundancy you add not to fight noise, but to obey the physics of the medium*. It
is a third kind of "adding redundancy back," distinct from both detection and
correction.

#keyidea[
  The DNA channel forces _joint_ thinking on three fronts at once: (1) _compress_
  hard to minimise the (expensive!) bases you must synthesise; (2) obey _constraints_
  — balanced GC content, no long homopolymer runs — which is _constrained coding_,
  itself a redundancy-shaping discipline (*Chapter 70*); and (3) layer _erasure +
  error_ correction for the brutal dropout/indel channel. Compression and protection
  are not separable stages here; they are one interlocked design.
]

== Where the worlds meet (2): the QR code in your hand

Hold up your phone, point it at a QR code half-covered by a coffee ring, and it
still resolves. That everyday magic is *Reed--Solomon* plus a deliberate *anti-
compression* decision, and it is the cleanest illustration of this chapter's whole
thesis.

A QR code, standardised by Denso Wave in 1994, is a little channel-coded packet you
can photograph. Its payload is often a URL — already short, often _compressible_ —
yet the QR standard offers *four* error-correction levels that do the _opposite_ of
compression, trading data capacity for redundancy:

#table(columns: (auto, auto, 1fr), inset: 6pt, align: (center, center, left),
  fill: (_, r) => if r == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Level*], [*Recovers up to*], [*Use*]),
  [L], [~7%], [clean indoor screens],
  [M], [~15%], [the common default],
  [Q], [~25%], [industrial / dirty environments],
  [H], [~30%], [logo in the middle, outdoor, damaged],
)

Those percentages are Reed--Solomon redundancy: level H spends nearly a third of
the symbols on RS parity so that you can _destroy_ up to about 30% of the modules —
print a logo over the centre, smear it, tear a corner — and still decode. Notice the
deliberate inversion: the designers _added_ redundancy on purpose, sized to the
_physical_ channel (crumpling, dirt, bad light), precisely because the payload will
be photographed in the wild. The masking patterns that keep the image from drifting
all-black or forming false finder patterns are a _constrained-coding_ flavour
(*Chapter 70*) layered on top.

There is a lovely tension in that table. A short URL might be a few dozen bytes of
*compressible* text — a compression engineer's instinct is to *shrink* it. The QR
designer does the opposite, *inflating* it with up to 30% parity, because the
adversary here is not storage cost but the *physical world*: a thumbprint, a fold, a
glint of sun, a printer that smears. The "right" amount of redundancy is dictated
entirely by *where the code will live*. Print QR codes for a clean phone screen and
level L is plenty; etch them onto a factory part that will be photographed under oil
and grime, and you reach for level H. Same payload, wildly different redundancy —
because redundancy is a *contract with a channel*, not a property of the data.

#aside[The black square "finder patterns" in three corners are a _synchronisation_
code, not error correction — they let the scanner locate, rotate, and de-skew the
grid before RS decoding even begins. Coding theory is not only about fixing flipped
bits; it is also about _finding the frame_ in the first place — the same job the QR
finder pattern, the CD's interleaving, and a video stream's start codes all do.]

== Where the worlds meet (3): Opus DRED — redundancy _inside_ the codec

The third boundary is where the separation theorem's _latency_ exception bites
hardest: a live voice call. We met *Opus* in *Chapter 49* as the codec behind
WebRTC, Zoom, and Discord. On a real network, packets *drop* — Wi-Fi hiccups,
cellular handoffs, congestion — and a dropped packet is a hole in someone's
sentence. Classic separation says "let the lower network layer retransmit." But you
*cannot* wait for a retransmission in a real-time call; by the time the resend
arrives, the conversation has moved on. The latency budget _revokes_ the licence to
separate, so the redundancy must move *inside* the codec.

Opus already had a small tool for this: *LBRR* (Low-Bitrate Redundancy), which
tucks a low-quality copy of the *previous* frame into the current packet, so one
lost packet can be patched from its successor. But LBRR carries only *one* frame of
history and costs roughly two-thirds of the regular bitrate — expensive, and useless
against a *burst* of consecutive losses.

The 2024 breakthrough, shipped in *libopus 1.5* (released 4 March 2024), is *DRED*
— *Deep REDundancy*. Instead of stuffing in a coarse audio copy, DRED uses a
*rate--distortion-optimised variational autoencoder* (the learned-compression
machinery of *Chapter 57*) to encode a *highly compressed neural summary* of up to
*one second or more* of recent speech, computed every 40 ms and added to each
packet — at a cost of only about *one-fiftieth* of the regular bitrate. If a long
burst of packets is lost, the *first* packet to arrive carries a neural snapshot of
the speech you missed, and the decoder *synthesises* the gap, blending seamlessly
with the *Deep PLC* (neural packet-loss concealment) that fills the very edges.
DRED is being standardised at the IETF as an Opus extension.

#keyidea[
  DRED is _joint source--channel coding_ in the flesh. The redundancy is _not_ a
  separate parity layer bolted on by the network; it is a _learned, perceptually
  shaped_ redundancy generated _by the codec itself_, sized to the _speech_ and to
  the _loss pattern_. It works _because_ a neural model can summarise a second of
  speech into a few hundred bits — compression and protection fused into one learned
  module. This is the separation theorem's "short-block, low-latency, perceptual"
  exception, answered with 2024 machine learning.
]

#misconception[that adding redundancy for packet loss must cost a lot of
bitrate.][DRED adds up to a _second_ of recoverable redundancy for only about
one-fiftieth of the speech bitrate — because it does not store _audio_, it stores a
_learned latent summary_ that the decoder _regenerates_ speech from. The cheapness
comes from doing the protection in a _compressed, model-aware_ representation, not
in raw samples. Co-design beats bolt-on.]

== Where the worlds meet (4): flash memory and the silent ECC underneath

The last boundary is the one closest to you right now: the *flash* chip in your
phone, SSD, and memory card. Flash stores bits as trapped charge in tiny cells, and
that charge *leaks*, *disturbs* its neighbours when nearby cells are written, and
*wears out* after enough write cycles. Raw flash is, frankly, a *terrible* channel —
modern *QLC* flash (4 bits per cell, 16 charge levels crammed into one cell) can
arrive with _raw_ bit-error rates so high the data would be unusable without
correction. Every read you have ever done from flash passed through an
error-correcting decoder you never saw.

Early flash used *BCH* codes (an algebraic cousin of Reed--Solomon, working on
bits). As cells shrank and bits-per-cell climbed, BCH could not keep up, and the
industry moved to *LDPC* — the same capacity-approaching code as your Wi-Fi —
running *soft-decision* decoding: the controller doesn't just read "is this a 1 or
0" but "_how confident_ am I," feeding those soft probabilities into belief
propagation to claw back data from a channel near its limit. The error correction
is invisible, mandatory, and the only reason terabyte-class consumer flash is
possible at all.

There is a beautiful economic balance hiding in the flash controller, and it is the
whole chapter in miniature. The controller has a fixed amount of physical storage to
divide between *your data* and *parity*. Spend too little on parity and reads fail
as cells age; spend too much and you waste capacity you sold to the customer. So the
controller *measures* the channel — it tracks how worn each block is and how noisy
its reads have become — and *adapts* the code rate over the drive's life, adding more
LDPC parity to tired blocks and less to fresh ones. This is *rate adaptation*: the
amount of redundancy is not fixed at design time but tuned, continuously, to the
*measured* state of the channel. It is the operational answer to the question this
whole chapter circles: *how much redundancy is the right amount?* The answer is never
a constant; it is "exactly enough to push the residual error below your target, given
what the channel is doing right now."

And here is the punchline that ties the volume together: _the better a flash
controller compresses your data_ (many SSDs compress transparently, *Chapter 74*),
_the more it must protect it_ — because compression concentrates information, so a
given physical defect now corrupts more _meaning_. The compression team and the ECC
team, on the same chip, are forced to talk. The boundary between removing
redundancy and adding it back is not a wall between two volumes of a book; it is a
seam running through a single piece of silicon in your pocket.

Step back and the shape of the whole chapter comes into focus. We spent Volumes II
through IV learning to *empty* the message of redundancy, chasing the entropy floor
$H$. This chapter put redundancy *back* — but never blindly. Every code we met adds
the *minimum* redundancy needed to survive a *specific* channel: a CRC's handful of
bits for "is this block clean?"; RS's $n - k$ symbols sized to the worst expected
burst; LDPC and polar's carefully tuned rate sized to the channel's measured noise;
DRED's one-fiftieth overhead sized to a packet-loss pattern. The art is never "add
redundancy" in the abstract — it is *add exactly the redundancy this channel
demands, and not one bit more*, because every bit of protection is a bit you could
have spent on data. That is the same optimisation, viewed from the other side, that
compression has been performing all along. Removing redundancy and adding it back are
not opposites; they are the same discipline — *spend bits only where they buy you
something* — pointed in two directions.

#checkpoint[Your SSD transparently compresses data 2:1 before writing it to flash.
A physical defect corrupts a fixed-size 4 KB region of the chip. Did compression
make that defect _more_ or _less_ damaging to your files, and what must the
controller do about it?][_More_ damaging: those 4 KB now hold twice as much
_logical_ information, so a fixed physical wound destroys twice the meaning. The
controller must apply _stronger_ ECC (more LDPC parity) per stored byte to
compensate — exactly the compress-then-protect tension, on one chip. The denser you
pack meaning, the harder you must armour it.]

#takeaways((
  [Maximally compressed data is maximally _fragile_: compression and error correction
   are _duals_ (Chapter 20) — one empties the space of legal strings, the other
   deliberately leaves it half-empty so noise is visible and fixable.],
  [_Compress-then-protect_ is _provably optimal_ (source--channel separation) — but
   only asymptotically. The licence is _revoked_ by short blocks/low latency,
   networks, unequal bit importance, and perceptual goals.],
  [_Minimum Hamming distance_ $d_min$ governs everything: detect $d_min{-}1$ errors,
   correct $floor((d_min{-}1)/2)$. Parity gives $d_min{=}2$; Hamming(7,4) gives
   $d_min{=}3$ and locates the broken bit via its syndrome.],
  [_CRCs_ are cheap, line-rate _detectors_ (polynomial remainder mod 2) — great when
   you can ask for a resend; they fix nothing and are not secure.],
  [_Reed--Solomon_ corrects _bursts_ and _erasures_ optimally by polynomial
   over-evaluation ($d_min = n{-}k{+}1$); it saved the CD, scans your QR code, and
   guards RAID and deep space.],
  [_LDPC_ (sparse graph, belief propagation) and _polar_ codes (channel
   polarization, provably capacity-achieving) finally reached the Shannon limit —
   LDPC for Wi-Fi/5G _data_ and flash, polar for 5G _control_.],
  [At the _meeting points_ — DNA storage, QR codes, Opus DRED, flash — compression
   and protection are _co-designed_, not separated; the denser you pack meaning, the
   harder you must armour it.],
))

== Exercises

#exercise("72.1", 1)[
  You compress the string `"banana"` down to a few bits, and separately store it raw
  in ASCII. Argue, in two or three sentences, which version a single random bit-flip
  is _more likely to render unreadable_, and connect your answer to the chapter's
  "small means brittle" principle.
]
#solution("72.1")[
  The _compressed_ version is far more likely to be rendered unreadable. In the raw
  ASCII version, a single flipped bit corrupts at most one character (e.g. `banana`
  becomes `banaba`), leaving the rest perfectly readable — the natural redundancy of
  the format localises the damage. In the compressed version, a flipped bit may alter
  a length field or a code word and cascade through the rest of the decode, scrambling
  everything after it. This is the "small means brittle" principle: compression
  removes the slack that was silently absorbing damage, so each remaining bit carries
  closer to its full share of meaning and the loss of any one hurts more.
]

#exercise("72.2", 1)[
  A code has codewords ${000000, 111000, 000111, 111111}$. (a) What is its minimum
  Hamming distance? (b) How many errors can it _detect_? (c) How many can it
  _correct_?
]
#solution("72.2")[
  (a) Compare all pairs. $d(000000,111000)=3$, $d(000000,000111)=3$,
  $d(000000,111111)=6$, $d(111000,000111)=6$, $d(111000,111111)=3$,
  $d(000111,111111)=3$. The smallest is $3$, so $d_min = 3$.
  (b) Detect $d_min - 1 = 2$ errors. (c) Correct $floor((d_min-1)/2) = floor(2/2) = 1$
  error.
]

#exercise("72.3", 2)[
  Encode the 4-bit data word $1101$ (as $d_1 d_2 d_3 d_4$) with the Hamming(7,4) code
  from the chapter (parity bits at positions $1,2,4$; data at $3,5,6,7$; $p_1$ covers
  $1,3,5,7$, $p_2$ covers $2,3,6,7$, $p_3$ covers $4,5,6,7$). Then flip position $6$
  and show that the syndrome correctly identifies position $6$.
]
#solution("72.3")[
  Data $d_1 d_2 d_3 d_4 = 1101$. Parities: $p_1 = d_1 xor d_2 xor d_4 =
  1 xor 1 xor 1 = 1$; $p_2 = d_1 xor d_3 xor d_4 = 1
  xor 0 xor 1 = 0$; $p_3 = d_2 xor d_3 xor d_4 = 1
  xor 0 xor 1 = 0$. Codeword at positions $1..7$ is
  $1,0,1,0,1,0,1$. Flip position 6: received $1,0,1,0,1,#text(fill: rgb("#9a2617"))[$1$],1$.
  Syndrome checks: over $1,3,5,7$: $1 xor 1 xor 1 xor 1 = 0$;
  over $2,3,6,7$: $0 xor 1 xor 1 xor 1 = 1$; over $4,5,6,7$:
  $0 xor 1 xor 1 xor 1 = 1$. Read $s_4 s_2 s_1 = 110_2 = 6$.
  The syndrome is $6$ — exactly the flipped position. Flip it back to recover the
  codeword.
]

#exercise("72.4", 2)[
  A Reed--Solomon code is configured with $n = 255$ symbols and $k = 223$ data
  symbols (a real configuration used in deep-space and storage). (a) What is its
  minimum distance? (b) How many _erasures_ can it correct? (c) How many _errors_
  (wrong values at unknown positions)? (d) Explain in one sentence why (b) is twice
  (c).
]
#solution("72.4")[
  (a) $d_min = n - k + 1 = 255 - 223 + 1 = 33$. (b) It corrects $n - k = 32$
  erasures. (c) It corrects $floor((n-k)/2) = floor(32/2) = 16$ errors. (d) Erasures
  come with their _locations_ known for free, so the decoder need only solve for the
  missing _values_; errors require solving for both location _and_ value, which costs
  twice the redundancy per corrected symbol — hence half as many.
]

#exercise("72.5", 2)[
  Explain why a CRC is excellent at catching _burst_ errors but is, by design,
  useless for _correcting_ them. In what kind of system does "detect, then ask for a
  resend" beat "correct in place," and in what kind of system is it the wrong choice?
]
#solution("72.5")[
  A CRC with an $r$-bit generator is guaranteed to catch any burst of length at most
  $r$, because such a burst cannot be a multiple of the degree-$r$ generator
  polynomial, so it always leaves a non-zero remainder. But the CRC outputs only a
  _yes/no_ verdict — it carries nowhere near enough information to _locate and repair_
  the corrupted bits, which is a far harder, more expensive task. "Detect then resend"
  wins when a cheap, fast _back-channel_ exists and latency is tolerable (downloading
  a file, TCP over Ethernet): detection is cheap, and you simply re-request damaged
  blocks. It is the _wrong_ choice when no resend is possible or affordable — a CD
  (the data is gone forever), a live call (the moment has passed), deep space
  (round-trip is hours) — where you must use _forward_ error correction that fixes
  errors in place.
]

#exercise("72.6", 2)[
  The 5G standard uses _LDPC_ codes for the _data_ channel and _polar_ codes for the
  _control_ channel. Using the chapter's discussion, give two reasons this split
  makes engineering sense.
]
#solution("72.6")[
  (1) _Block length._ Data transmissions are large, so they form long codewords —
  exactly where LDPC's iterative belief propagation reaches near-capacity and its
  massive parallelism gives high throughput. Control messages are tiny (a few dozen
  bits), and the separation theorem's asymptotics no longer hold there; polar codes
  with CRC-aided successive-cancellation _list_ decoding are excellent in precisely
  this short-block regime. (2) _Priorities._ The data channel optimises raw throughput
  and tolerates LDPC's iteration latency; the control channel needs very low latency
  and very high reliability on short packets, which polar's structure and the
  CRC-as-referee list decoder deliver. Different jobs, different codes — the same
  lesson as RS-for-bursts versus LDPC-for-white-noise.
]

#exercise("72.7", 3)[
  _(Coding/conceptual.)_ In Python, write a function `parity(bits: list[int]) -> int`
  that returns the even-parity bit of a list of `0/1` integers using only the XOR idea
  from the chapter, and a function `check(bits: list[int], p: int) -> bool` that
  returns `True` if the received bits plus parity are consistent. Then explain why
  this scheme cannot tell _which_ bit flipped.
]
#solution("72.7")[
  ```python
  def parity(bits: list[int]) -> int:
      p = 0
      for b in bits:          # XOR all the data bits together
          p ^= b              # ^= is in-place XOR (mod-2 addition)
      return p                # 1 if an odd number of 1s, else 0

  def check(bits: list[int], p: int) -> bool:
      # consistent iff XOR of data XOR received-parity is 0 (even total)
      total = p
      for b in bits:
          total ^= b
      return total == 0       # True = looks error-free (even parity holds)
  ```
  The scheme reports only a single XOR-aggregate over _all_ positions, so it yields
  exactly one bit of information: "the number of 1s is even / odd." A single flip
  anywhere makes the total odd, but the verdict is identical no matter _which_
  position flipped — there is no per-position information to localise the error. To
  _locate_ (and thus correct) a flip you need _multiple, overlapping_ parity checks,
  as in Hamming(7,4), whose three checks together form a syndrome that addresses the
  culprit. Minimum distance $2$ detects $1$ and corrects $0$, exactly as the theory
  predicts.
]

#exercise("72.8", 3)[
  Opus DRED adds up to a second of recoverable speech for only about one-fiftieth of
  the regular bitrate, while classic per-frame redundancy (LBRR) costs about
  two-thirds of the bitrate for a _single_ frame. (a) Explain what makes DRED so much
  cheaper. (b) Argue why DRED is a violation — a productive one — of strict
  source--channel _separation_, referencing two of the chapter's four "revoked
  licence" conditions.
]
#solution("72.8")[
  (a) LBRR stores an actual coarse _audio_ copy of a frame, so its cost scales with
  the bitrate of audio. DRED instead stores a _learned latent summary_ produced by a
  rate--distortion-optimised variational autoencoder: a few hundred bits that the
  decoder _regenerates_ up to a second of speech from, using a neural model of how
  speech sounds. Because it transmits a _compressed, model-aware_ description rather
  than raw samples, it buys far more recoverable time per bit. (b) Strict separation
  would compress speech to its floor, then let an _independent_ network layer add
  protection (e.g. retransmission). DRED instead bakes the protective redundancy
  _into the codec_, shaped to the speech and the loss pattern. This is licensed by two
  of the chapter's exceptions: _short blocks / low latency_ (a live call cannot await
  a retransmission, so asymptotic separation does not apply) and _lossy + perceptual
  goals_ (the aim is speech that _sounds_ continuous, not bit-exactness, so a
  perceptually-shaped neural redundancy beats a generic parity layer).
]

== Further reading

- *C. E. Shannon (1948),* "A Mathematical Theory of Communication," _Bell System
  Technical Journal_ — the source of both the source-coding and channel-coding
  theorems, and the separation idea. #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[(canonical copy)]
- *R. W. Hamming (1950),* "Error Detecting and Error Correcting Codes," _Bell System
  Technical Journal_ 29 — the birth of distance-based correction.
- *I. S. Reed & G. Solomon (1960),* "Polynomial Codes over Certain Finite Fields,"
  _Journal of the SIAM_ 8(2) — five pages that armour the digital world.
- *R. G. Gallager (1962),* "Low-Density Parity-Check Codes," _IRE Transactions_ — and
  *D. MacKay & R. Neal (1996/1999),* the rediscovery. #link("https://www.inference.org.uk/mackay/itila/")[(MacKay's free textbook, _Information Theory, Inference, and Learning Algorithms_)]
- *E. Arıkan (2009),* "Channel Polarization: A Method for Constructing
  Capacity-Achieving Codes," _IEEE Trans. Information Theory_ 55(7). #link("https://arxiv.org/abs/0807.3917")[(arXiv:0807.3917)]
- *J.-M. Valin et al. (2024),* "DRED: Deep REDundancy Coding of Speech Using a
  Rate-Distortion-Optimized Variational Autoencoder." #link("https://arxiv.org/abs/2212.04453")[(arXiv:2212.04453)]; #link("https://opus-codec.org/release/stable/2024/03/04/libopus-1_5.html")[libopus 1.5 release notes]
- *Y. Erlich & D. Zielinski (2017),* "DNA Fountain Enables a Robust and Efficient
  Storage Architecture," _Science_ 355(6328). #link("https://www.science.org/doi/10.1126/science.aaj2038")[(Science)]

#bridge[
  We have seen _why_ the most compressed data needs the most careful armour, and met
  the codes that supply it. But shipping these ideas at the speed of a modern network
  — gigabytes per second, on real silicon — is its own art: interleaved rANS that
  flies through a CPU, branchless decoders, cache-aware match finders, and GPU and
  hardware offload. *Chapter 73, "Engineering Fast Codecs,"* leaves the theory and
  goes to where the bits-per-second are actually won.
]
