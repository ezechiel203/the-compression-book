#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Asymmetric Numeral Systems (ANS)

#epigraph[
  "I just wanted a cheaper alternative to arithmetic coding. It turned out to be
  something more — and I decided it should belong to everyone."
][Jarosław (Jarek) Duda, paraphrasing his ANS papers, 2009–2013]

For sixty years the field of compression lived with an uncomfortable truth that
felt almost like a law of nature. You could have a coder that was *fast*, or a
coder that was *small*, but not both at once. Huffman coding (Chapter 24) was
blazing fast — a table lookup per symbol — but it wasted bits, because it could
only ever spend a whole number of bits on each symbol. Arithmetic coding
(Chapter 26) spent exactly the right *fractional* number of bits and squeezed a
message down to the entropy floor — but it paid for that precision with a
multiply and a divide on every single symbol, which made it slow and, for a
generation, legally radioactive thanks to a thicket of patents.

Everybody assumed the trade-off was fundamental. Then, in 2009, a physicist in
Kraków who was not even a compression specialist posted a short paper to the
arXiv with an outrageous claim: you can have both. You can hit the
arithmetic-coding ratio at the Huffman speed. The trick was not a clever
engineering hack on top of the old methods. It was a completely new way of
*thinking* about what it means to write information into a number — a reinvention
of the humble idea of a *numeral system*, the thing you learned in third grade
when you learned that "237" means two hundreds, three tens, and seven ones.

This chapter is the story of that idea: *Asymmetric Numeral Systems*, or ANS. By
the end you will understand how it works from the ground up, you will encode and
decode a real message by hand, and you will swap the entropy stage of our
`tinyzip` compressor over to a working rANS coder in Python. We will also tell
the very human story of how Duda gave his invention away to the public domain —
and how two of the largest companies on earth nonetheless tried to patent it.

#recap[
  In *Chapter 18* we defined the *entropy* $H(X) = -sum_i p_i log_2 p_i$ as the
  average number of bits a perfect coder must spend per symbol, and in *Chapter
  19* the *source coding theorem* proved that $H$ is a hard floor nobody can beat.
  *Chapter 24* gave us *Huffman coding*, optimal among codes that spend whole
  bits — and therefore stuck paying an "integer-bit tax". *Chapter 26* gave us
  *arithmetic coding*, which escapes that tax by encoding the whole message as
  one shrinking interval of $[0,1)$, reaching $H$ almost exactly but needing a
  multiply and divide per symbol. We also met *range coding*, the byte-oriented
  cousin that powers LZMA. This chapter introduces a third way to reach the floor
  — one that keeps arithmetic coding's accuracy but throws away its slowness.
]

#objectives((
  [Explain what a *numeral system* really is, and how making it _asymmetric_ turns it into an entropy coder.],
  [Encode and decode a message by hand with *uABS*, the simplest binary ANS.],
  [Describe *rANS* and *tANS*, why rANS uses one multiply where arithmetic coding uses two, and why tANS uses _none_.],
  [Explain why ANS is naturally *LIFO* (last-in, first-out) and what that forces an implementation to do.],
  [Understand *normalization* (renormalization) — the rule that keeps the state from overflowing.],
  [Implement a correct, round-tripping rANS coder in Python and plug it into `tinyzip`.],
  [Recount ANS's real-world adoption (Zstandard, LZFSE, JPEG XL) and the patent fights it survived.],
))

== The one idea: a numeral system that knows the odds

Let us start not with compression but with counting, because ANS is, at heart,
just a strange way of writing numbers.

Think about what the decimal number "237" actually *is*. It is a compact recipe
for a quantity. Reading it left to right, each digit is worth ten times the one
to its right: $2 times 100 + 3 times 10 + 7 times 1 = 237$. The base-10 system
lets us pack any natural number into a short string of digits, and — this is the
part we never think about — it lets us pull the digits back out again, one at a
time, perfectly. Given the number 237, I can recover its last digit (7) by taking
the remainder when I divide by 10, and I can throw that digit away by doing the
integer division $237 div 10 = 23$. Push a digit on, pop a digit off. A numeral
system is a reversible machine for stuffing symbols into a single number.

#gomaths("Integer division and remainder (mod)")[
  Two operations run through this entire chapter, so let us pin them down. When
  you divide one whole number by another and refuse to use fractions, you get a
  *quotient* and a *remainder*. Dividing 237 by 10: the quotient is 23 (ten goes
  into 237 twenty-three times) and the remainder is 7 (what is left over). We
  write these as
  $ 237 div 10 = 23 quad (#text[integer division, written] floor(237 \/ 10)), $
  $ 237 mod 10 = 7 quad (#text[the remainder, "237 mod 10"]). $
  The bracket symbol $floor(dot)$ means "round down to the nearest whole number".
  The two always fit together by the identity
  $ x = (x div b) times b + (x mod b), $
  which just says: the part you divided out, times the base, plus the leftover,
  rebuilds the original. For $x=237, b=10$: $23 times 10 + 7 = 237$. ✓ In Python
  these are the `//` and `%` operators, which we will lean on constantly.
]

Now here is the question that unlocks ANS. In base 10, every digit gets an *equal*
slice of the number line: exactly one tenth of all numbers end in 0, one tenth
end in 1, and so on. The system treats all ten digits as equally likely. But what
if they are *not* equally likely? What if I am writing a message where the symbol
`a` shows up 90% of the time and the symbol `b` only 10%? An honest numeral system
for that message should give `a` a *big* slice of the number line and `b` only a
*small* one — because, as Shannon taught us in Chapter 18, a common symbol carries
little information and deserves few bits, while a rare symbol carries a lot and
deserves many.

That is the whole idea, and it is worth saying slowly because everything follows
from it:

#keyidea[
  *ANS is a numeral system whose digits are unequal.* Each symbol $s$ is given a
  fraction of the number line equal to its probability $p_s$. Writing a likely
  symbol grows the number only a little (cheap, few bits); writing a rare symbol
  grows it a lot (expensive, many bits). Because each step is reversible — push a
  symbol on, later pop it off — the single growing number *is* the compressed
  message. We call the number the *state*, written $x$.
]

The word "asymmetric" in the name refers exactly to this: a normal numeral system
is *symmetric* — all digits the same size — whereas ANS deliberately makes the
digit slices *asymmetric*, sized to the odds. The "numeral systems" part is the
promise that, despite the asymmetry, we still get a clean reversible
push/pop machine for packing symbols into one number.

To see the push/pop machine of an *ordinary* base-10 numeral system in code —
before we make it asymmetric — here it is in three lines of Python. Pushing a
digit $d$ does `x = x * 10 + d`; popping pulls the last digit back out and shrinks
the number:

```python
def push(x: int, d: int) -> int:   # write digit d onto x  (base 10)
    return x * 10 + d

def pop(x: int) -> tuple[int, int]: # read the last digit, shrink x
    return x // 10, x % 10          # (new_x, recovered_digit)

x = 0
for d in (2, 3, 7):    x = push(x, d)   # x becomes 237
x, last = pop(x)                        # x = 23, last = 7  -> perfect inverse
```

ANS is precisely this `push`/`pop` pair — but with `* 10` replaced by a step that
multiplies by roughly $1 slash p_s$, so likely symbols grow $x$ less than rare
ones. Hold this snippet in mind: everything that follows is a variation on it.

#history[
  *Jarosław (Jarek) Duda* is a Polish physicist and computer scientist at the
  Jagiellonian University in Kraków. He developed the ANS family between roughly
  2006 and 2014, posting the first paper to the arXiv in 2009 (arXiv:0902.0271)
  and the definitive treatment in 2013 (arXiv:1311.2540, with the gloriously
  literal subtitle "_entropy coding combining speed of Huffman coding with
  compression rate of arithmetic coding_"). Duda was not trying to start a
  revolution; he was looking for a cheaper alternative to arithmetic coding for
  his own work. He deliberately published ANS into the public domain, refusing to
  patent it, so that anyone could use it freely. That decision, and the corporate
  attempts to undo it, become a major part of this chapter's story.
]

== From odds to slices: building uABS by hand

The simplest member of the ANS family handles an alphabet of just two symbols,
`0` and `1`. It is called *uABS* — _uniform binary_ ANS — and it is the cleanest
place to see the machine work, because we can write its rule as a single direct
formula and crank it by hand.

Suppose our two symbols are `0` and `1`, and symbol `1` has probability $p$ (so
`0` has probability $1-p$). The state $x$ is a non-negative integer that starts
small and grows as we encode. uABS works by deciding, for *every* integer state
$x = 0, 1, 2, 3, dots$, which symbol "owns" that slot. We hand a $p$ fraction of
the slots to symbol `1` and the remaining $1-p$ fraction to symbol `0`, spread out
as evenly as possible so the odds stay honest at every scale.

The cleanest way to assign the slots uses a running count. For each candidate
state $x$, compute how many `1`-slots should have appeared by the time we reach
$x$; if that count ticks up at $x$, the slot belongs to `1`, otherwise to `0`. In
formula form, slot $x$ belongs to symbol `1` exactly when
$ ceil((x+1) p) - ceil(x p) = 1, $
where $ceil(dot)$ means "round *up*". Do not worry about memorizing this; the
point is only that it sprinkles the `1`-slots through the number line at a steady
rate of $p$ per step.

#gomaths("Rounding up: the ceiling function")[
  The *ceiling* of a number, written $ceil(y)$, is the smallest whole number that
  is not less than $y$ — you round *up*. So $ceil(2.1) = 3$, $ceil(2.9) = 3$, and
  $ceil(3.0) = 3$ (a whole number rounds to itself). Its partner, the *floor*
  $floor(y)$ from the box above, rounds *down*: $floor(2.9) = 2$. The expression
  $ceil((x+1)p) - ceil(x p)$ asks: "between $x$ and $x+1$, did the running tally
  $x p$ cross a whole-number boundary?" If yes, this slot is a `1`; the tally
  crosses at a rate of $p$ boundaries per step, so a fraction $p$ of the slots are
  `1`s. Exactly the asymmetry we wanted.
]

Let us make it concrete with $p = 0.3$, meaning symbol `1` happens 30% of the
time. Computing which symbol owns each state from $x=0$ upward:

#fig([uABS slot ownership for $p=0.3$. Each integer state $x$ is "owned" by one
symbol. About 30% of slots belong to `1`, spread evenly. (Computed from the running
tally $ceil((x+1)p) - ceil(x p)$.)],
table(columns: 13, inset: 5pt, align: center,
  table.header([*state $x$*],[0],[1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11]),
  [*owner*], [1],[0],[0],[1],[0],[0],[1],[0],[0],[0],[1],[0]),
)

The pattern of owners is `1 0 0 1 0 0 1 0 0 0 1 0 …` — roughly one `1` for every
two or three `0`s, which is the 30/70 split we asked for, sprinkled evenly. (The
exact spacing wobbles by one here and there; that is the integer rounding doing its
best to honor a 0.3 fraction with whole slots.)

Now: *encoding*. Encoding takes the current state $x$ and a symbol $s$, and
produces a *new, larger* state $x'$ — the next state, larger than where we are,
whose slot is owned by $s$. The decode is the inverse: from $x'$, look up who owns
that slot (that recovers $s$), then walk back down to the previous state $x$. The
lovely property is that *the owner of the slot tells the decoder which symbol was
just written* — no extra information needed. The symbol is hidden in the
arithmetic of the state itself.

#keyidea[
  *Encoding grows the state; decoding shrinks it.* Crucially, decoding recovers
  symbols in the *reverse* order they were encoded — because to shrink the state
  you must undo the *last* growth first. This is the famous *LIFO* (last-in,
  first-out) nature of ANS: it works like a stack of plates. We will have to plan
  around it.
]

=== A tiny worked encode and decode

Let us hand-encode the two-symbol message `1 0 1` with $p=0.3$. We will drive
everything straight off the ownership table above — no closed-form magic, just the
two operations a numeral system always offers:

- *Encode* symbol $s$ from state $x$: treat the current state $x$ as a *counter*,
  and let the new state $x'$ be *the $x$-th slot owned by $s$* (counting that
  symbol's own slots as $0, 1, 2, dots$). Common symbols own many slots packed
  close together, so their $x$-th slot is a modest number (small jump); rare
  symbols own few, widely spaced slots, so their $x$-th slot is a large number (big
  jump). That distance *is* the asymmetry.
- *Decode* from state $x'$: read who owns slot $x'$ — that recovers $s$ — then
  count how many of $s$'s slots came strictly before $x'$; that count is the
  previous state $x$. The owner lookup and the count are exact inverses of the
  encode.

It helps to list, from the table, the slots each symbol owns, in order:
the *`1`-slots* are $0, 3, 6, 10, 13, 16, dots$ and the *`0`-slots* are
$1, 2, 4, 5, 7, 8, 9, dots$. To make the jumps visible we start from state $x = 2$.
Encoding `1`, then `0`, then `1`:

#fig([Hand-tracing uABS encoding of the message `1 0 1` with $p = 0.3$, starting
at $x = 2$. Each step looks up the $x$-th slot owned by the symbol; rare symbol `1`
lands far out, common symbol `0` lands close.],
table(columns: 4, inset: 6pt, align: (center, center, left, center),
  table.header([*step*], [*symbol $s$*], [*"the $x$-th slot owned by $s$"*], [*new state $x$*]),
  [start], [—], [—], [2],
  [1], [`1`], [the 2nd `1`-slot ($0,3,bold(6),…$) is 6], [6],
  [2], [`0`], [the 6th `0`-slot ($1,2,4,5,7,8,bold(9),…$) is 9], [9],
  [3], [`1`], [the 9th `1`-slot is 30], [30],
))

So the message `1 0 1` compresses to the single number $x = 30$. Notice the
*asymmetry* in action: the first `1` jumped the state from 2 to 6 and the second
`1` jumped it from 9 to 30 — big leaps, because `1` is rare and expensive. The `0`
in the middle moved the state only from 6 to 9 — a short hop, because `0` is common
and cheap. The final number 30, written in binary as `11110`, is our compressed
message. On a long message these fractional savings accumulate into a real win, as
we will see.

Now *decoding*, which runs the message back out in reverse (`1`, then `0`, then
`1`) and shrinks the state back to 2. The decode rule reads the slot owner to get
the symbol, then counts back to the previous sub-state. Reading from $x = 30$:

#fig([Hand-tracing uABS decoding from state $x = 30$. We recover symbols in reverse
order (`1`, `0`, `1`) and shrink the state back to the start. The owner of the
current slot tells us the symbol; counting that symbol's slots gives the prior
state.],
table(columns: 4, inset: 6pt, align: (center, center, left, center),
  table.header([*step*], [*state $x$*], [*owner of slot $x$ → symbol*], [*prior state*]),
  [1], [30], [slot 30 is a `1`-slot → emit `1`], [9],
  [2], [9], [slot 9 is a `0`-slot → emit `0`], [6],
  [3], [6], [slot 6 is a `1`-slot → emit `1`], [2],
))

Working from $x=30$: slot 30 is owned by `1`, so we emit `1`; counting the
`1`-slots strictly below 30 ($0,3,6,10,13,16,20,23,26$) gives 9 of them, so the
prior state was 9. From $x=9$: slot 9 is owned by `0`, emit `0`; the `0`-slots
below 9 are $1,2,4,5,7,8$, six of them, so the prior state was 6. From $x=6$: slot
6 is owned by `1`, emit `1`; the `1`-slots below 6 are $0,3$, two of them, so we
count back to the starting state 2. The decoder emitted `1 0 1` in the *reverse* of
encoding order; in practice we feed the encoder the message backwards so the decoder
reads it forwards (more on this below). The state returned to exactly 2, confirming
a perfect, lossless round-trip. *No fractions, no intervals, no multiply-and-divide
pair — just a slot lookup and a count.* That is the magic of ANS in miniature.

For completeness, here is the whole uABS coder as runnable Python — a direct
transcription of the owner test, the "$x$-th slot owned by $s$" encode, and the
"count back" decode. It round-trips any list of bits:

```python
from math import ceil

def owner(x: int, p: float) -> int:           # which symbol owns slot x?
    return 1 if ceil((x + 1) * p) - ceil(x * p) == 1 else 0

def nth_slot(k: int, s: int, p: float) -> int:  # the k-th slot owned by symbol s
    x, count = 0, 0
    while True:
        if owner(x, p) == s:
            if count == k:
                return x
            count += 1
        x += 1

def rank(x: int, p: float) -> int:            # how many of owner(x)'s slots precede x
    s = owner(x, p)
    return sum(1 for y in range(x) if owner(y, p) == s)

def uabs_encode(bits: list[int], p: float) -> int:
    x = 0
    for s in reversed(bits):                  # LIFO: feed backwards
        x = nth_slot(x, s, p)                 # go to the x-th slot owned by s
    return x

def uabs_decode(x: int, n: int, p: float) -> list[int]:
    out = []
    for _ in range(n):
        out.append(owner(x, p))               # the owner is the symbol
        x = rank(x, p)                         # count back to the prior state
    return out                                # forward order, since we encoded reversed
```

These loops are deliberately literal — they walk the slots one at a time so you can
*see* the definition rather than a packed formula. (Real coders, as we will see,
use the constant-time `rANS` arithmetic below instead of scanning slots; the
worked hand-trace above starts at $x = 2$ to show the jumps, whereas this code
starts a fresh message at $x = 0$.)

#checkpoint[
  In the encode trace, the common symbol `0` moved the state only from 6 to 9,
  while each rare `1` made a much bigger jump. Does that small move mean a `0` costs
  less than 1 bit?
][Yes — and that is the whole point. A symbol of probability $0.7$ deserves
$-log_2 0.7 approx 0.515$ bits, and indeed the `0` grew the state by a factor of
only $9 slash 6 = 1.5$, i.e. $log_2 1.5 approx 0.585$ bits — well under one bit,
close to the ideal $0.515$ once the rounding averages out over many symbols. Each
`1`, by contrast, grew the state by a factor of about 3 ($-log_2 0.3 approx 1.74$
bits). ANS spends *fractional* bits per symbol, amortized across the message —
exactly like arithmetic coding, and exactly what Huffman cannot do.]

== Why the state grows by the right number of bits

We have seen the state grow. Now let us see *why* it grows by exactly the number
of bits Shannon's theorem demands — this is the one place a little algebra repays
us enormously, because it shows ANS is not a lucky hack but a coder that provably
hits the entropy floor.

Here is the key relationship. Recall (Chapter 4) that a non-negative integer $x$
needs about $log_2 x$ bits to write down — the number 9 needs $log_2 9 approx 3.17$
bits, which we round up to 4 (`1001`). So *the size of the state, measured in bits,
is $log_2 x$, and that is the size of our compressed message so far.* Every time
we encode a symbol $s$ and the state grows from $x$ to $x'$, the message grows by
$ log_2 x' - log_2 x = log_2 (x' / x) #text[ bits.] $

#gomaths("A logarithm of a ratio is a difference of logarithms")[
  One rule from Chapter 7 does all the work here: $log(a/b) = log a - log b$.
  In words, *dividing inside a log becomes subtracting outside it.* So the bits
  added when the state goes from $x$ to $x'$ is
  $log_2 x' - log_2 x = log_2(x'/x)$. If the state roughly *doubles*, you have
  added $log_2 2 = 1$ bit; if it grows by a factor of 10, you added
  $log_2 10 approx 3.32$ bits. The cost of a symbol is just the log of how much it
  stretched the state.
]

Now, what is the growth factor $x'/x$ for a symbol $s$ of probability $p_s$? By
construction, symbol $s$ owns a fraction $p_s$ of all the slots, spread evenly. To
reach "the next $s$-slot" you must skip past roughly $1/p_s$ slots (if one slot in
every $1/p_s$ belongs to $s$). So encoding $s$ multiplies the state by about
$1/p_s$:
$ x' approx x / p_s, wide #text[so the cost is ] log_2(x'/x) approx log_2(1/p_s) = -log_2 p_s. $

And there it is. The number of bits ANS spends on a symbol of probability $p_s$ is
$-log_2 p_s$ — which Chapter 18 named the symbol's *surprisal*, its ideal
information content. Sum that over the whole message and you get exactly the
entropy $H$. ANS reaches the Shannon floor, symbol by symbol, with the cost paid
in the growth of one integer.

#theorem("uABS reaches the entropy floor")[
  Encoding a sequence of symbols with ANS, where each symbol $s$ of probability
  $p_s$ multiplies the state by approximately $1/p_s$, produces a final state $x$
  whose bit-length $log_2 x$ approaches the message's total surprisal
  $sum_s -log_2 p_s$, i.e. its entropy. The only excess is a tiny, bounded rounding
  loss from the integer slot assignment.
]

#proof[
  Start from state $x_0$ and encode symbols $s_1, s_2, dots, s_n$, producing states
  $x_1, x_2, dots, x_n$. Each step multiplies the state by approximately the
  reciprocal probability: $x_i approx x_(i-1) \/ p_(s_i)$. Chaining all $n$ steps,
  $ x_n approx x_0 dot 1/(p_(s_1)) dot 1/(p_(s_2)) dots 1/(p_(s_n))
        = x_0 / (product_(i=1)^n p_(s_i)). $
  Take $log_2$ of both sides and use the "log of a product is a sum of logs" rule
  from Chapter 7:
  $ log_2 x_n approx log_2 x_0 + sum_(i=1)^n (-log_2 p_(s_i)). $
  The leading $log_2 x_0$ is the fixed cost of the starting state — a handful of
  bits paid once, negligible on a long message. The sum is precisely the total
  surprisal of the message, whose per-symbol average is the entropy $H$ (Chapter
  18). Hence the compressed size $log_2 x_n$ approaches $n H$, the source coding
  bound (Chapter 19). The approximations come only from the integer rounding in
  slot assignment, which the 2009 and 2013 analyses show contributes a bounded
  loss — in practice a fraction of a percent. $qed$
]

#misconception[
  ANS is just arithmetic coding with extra steps.
][They share the same *goal* — reach the entropy floor with fractional bits — and
the same theoretical limit, but the *machinery* is genuinely different. Arithmetic
coding tracks an *interval* $[#text[low], #text[high])$ and needs the current
symbol's probability *and* its cumulative position, costing a multiply *and* a
divide per symbol. ANS tracks a *single integer state* and, in its rANS form,
needs only *one* multiply per symbol; in its tANS form, *none at all* — just a
table lookup. That asymmetry in cost is the entire reason ANS displaced arithmetic
coding in modern codecs.]

== rANS: ANS for a real alphabet

uABS is beautiful but only handles two symbols. Real data has 256 possible byte
values. The variant that scales up to a full alphabet — and the one you will
actually implement — is *rANS*, the _range_ variant of ANS. It is the workhorse
inside Zstandard, JPEG XL, and most modern uses of ANS.

rANS replaces the per-symbol slot formulas with *quantized frequencies*. Here is
the setup, and it is the same trick every practical entropy coder uses (we saw it
in arithmetic coding, Chapter 26): we approximate the real probabilities by
integer *frequency counts* that all share a common denominator $M$, where $M$ is a
power of two (say $M = 2^12 = 4096$, the exact value JPEG XL uses).

For each symbol $s$ we store two integers:
- $F_s$ — its *frequency*: how many of the $M$ slots belong to $s$. The
  probability is $p_s = F_s slash M$, so we choose $F_s approx p_s times M$.
- $B_s$ — its *cumulative base*: the total frequency of all symbols *before* $s$,
  i.e. $B_s = F_0 + F_1 + dots + F_(s-1)$. This marks where $s$'s block of slots
  begins.

All the $F_s$ must sum to exactly $M$. The slots $0 dots M-1$ are carved into
contiguous blocks: symbol $s$ owns slots $B_s, B_s + 1, dots, B_s + F_s - 1$.

#fig([The rANS slot layout for a 3-symbol alphabet with $M = 8$. Frequencies
$F = (4, 3, 1)$ mean `a` owns 4 of the 8 slots, `b` owns 3, `c` owns 1. The bases
$B = (0, 4, 7)$ mark where each block starts. A common symbol gets a wide block
(cheap); a rare one gets a narrow block (expensive).],
cetz.canvas({
  import cetz.draw: *
  let labels = ("a","a","a","a","b","b","b","c")
  let cols = (rgb("#cfe3f5"), rgb("#cfe3f5"), rgb("#cfe3f5"), rgb("#cfe3f5"),
              rgb("#d8ecdd"), rgb("#d8ecdd"), rgb("#d8ecdd"), rgb("#f6dcd6"))
  for i in range(8) {
    rect((i, 0), (i+1, 1), fill: cols.at(i), stroke: 0.6pt)
    content((i+0.5, 0.5))[#labels.at(i)]
    content((i+0.5, -0.35))[#text(size: 8pt)[#i]]
  }
  content((2, 1.45))[#text(size: 8pt)[$F_a=4, B_a=0$]]
  content((5.5, 1.45))[#text(size: 8pt)[$F_b=3, B_b=4$]]
  content((7.5, 1.85))[#text(size: 8pt)[$F_c=1$]]
  content((7.5, 1.45))[#text(size: 8pt)[$B_c=7$]]
}))

With this table, rANS has a clean pair of formulas — the same ones every
implementation uses. To *encode* symbol $s$ into state $x$, producing new state
$x'$:
$ x' = C(s, x) = floor(x / F_s) times M + B_s + (x mod F_s). $
To *decode* — recover the symbol and shrink the state back — first find the slot
$ #text[slot] = x mod M, $
look up which symbol owns it (whose block contains that slot — that is your
recovered $s$), then invert:
$ x = D(x') = F_s times floor(x' / M) + (x' mod M) - B_s. $

These two are exact inverses (you will prove it in the exercises). Let us unpack
the encode formula in words, because it is the heart of rANS:

#keyidea[
  The rANS encode step $x' = floor(x slash F_s) times M + B_s + (x mod F_s)$ does
  three things at once. It *grows the state by roughly the factor $M slash F_s =
  1 slash p_s$* (the $floor(x slash F_s) times M$ part), which is the
  $-log_2 p_s$ bits the symbol costs. It *records which symbol* this was, by
  landing the new state in $s$'s slot-block (the $+ B_s + (x mod F_s)$ part, which
  always falls in the range $[B_s, B_s + F_s)$ modulo $M$). And it does both with
  *one division, one multiplication, and one modulo* — and on decode, *one*
  multiplication. Half the arithmetic of an arithmetic coder.
]

=== A worked rANS encode

Let us encode the message `a c` using the table from the figure: alphabet
`a, b, c`, frequencies $F = (4, 3, 1)$, bases $B = (0, 4, 7)$, total $M = 8$.
Start the state at $x = M = 8$ (a common, safe starting value).

#fig([Worked rANS encoding with $F=(4,3,1)$, $B=(0,4,7)$, $M=8$, starting at
$x=8$.],
table(columns: 4, inset: 6pt, align: (center, center, left, center),
  table.header([*step*], [*symbol*], [*$x' = floor(x slash F_s) dot M + B_s + (x mod F_s)$*], [*new $x$*]),
  [start], [—], [—], [8],
  [1], [`a`], [$floor(8/4) dot 8 + 0 + (8 mod 4) = 2 dot 8 + 0 + 0 = 16$], [16],
  [2], [`c`], [$floor(16/1) dot 8 + 7 + (16 mod 1) = 16 dot 8 + 7 + 0 = 135$], [135],
))

The state went $8 → 16 → 135$. Encoding `a` (probability $4/8 = 1/2$) doubled the
state — exactly the 1 bit a half-probability symbol deserves. Encoding `c`
(probability $1/8$) multiplied the state by more than 8 — the $log_2 8 = 3$ bits a
one-in-eight symbol deserves. The asymmetry is doing precisely its job.

To decode from $x = 135$: the slot is $135 mod 8 = 7$, which lies in `c`'s block
($B_c = 7$), so we recover `c`; inverting gives
$x = 1 times floor(135 slash 8) + (135 mod 8) - 7 = 1 times 16 + 7 - 7 = 16$. From
16, the slot is $16 mod 8 = 0$, in `a`'s block, recover `a`; invert to
$x = 4 times 2 + 0 - 0 = 8$. We are back to the start, having read out `c` then
`a` — reverse order, as promised.

#algo(
  name: "rANS (range Asymmetric Numeral Systems)",
  year: "2013",
  authors: "Jarosław Duda",
  aim: "Reach the arithmetic-coding ratio for a multi-symbol alphabet using a single integer state and only one multiply per symbol.",
  complexity: "O(1) per symbol: one mul, one div, one mod on encode; one mul on decode, plus a slot→symbol lookup.",
  strengths: "Near-optimal ratio; far faster than arithmetic coding; supports adaptive frequencies; SIMD-friendly via interleaving.",
  weaknesses: "Operates LIFO, so encoder must process the buffer backwards; needs a normalization rule to bound the state.",
  superseded: "Not superseded — current state of the art, alongside its sibling tANS.",
)[
  rANS keeps a single state integer $x$. Encoding symbol $s$ with quantized
  frequency $F_s$, base $B_s$, total $M$ (a power of two) applies
  $x' = floor(x slash F_s) dot M + B_s + (x mod F_s)$, after first emitting low
  bytes of $x$ to keep it in a working range (normalization). Decoding reads the
  slot $x mod M$, maps it to a symbol, then inverts. Because the multiply by $M$
  is a bit-shift (M is a power of two) and the symbol lookup is a small table,
  rANS runs at speeds competitive with Huffman while compressing like arithmetic
  coding.
]

== Normalization: keeping the state from exploding

There is one practical problem we have glossed over. Every symbol *multiplies* the
state, so after a few thousand symbols $x$ would be an astronomically large
integer with thousands of digits — far too big to hold in a 32- or 64-bit machine
word, and slow to do arithmetic on. Real coders cannot let the state grow without
limit.

The fix is *normalization* (also called *renormalization*): we keep the state
penned inside a fixed window, say $[L, b dot L)$ where $L$ is a chosen lower bound
and $b$ is the radix we emit in (commonly $b = 256$, i.e. one byte at a time). Just
before encoding a symbol would push the state at or above the top of its allowed
range, we *shovel out the low byte of the state into the output stream*, which
shrinks the state back down, and only then apply the encode step. Decoding does the
mirror image: when the state drops below $L$, we *pull bytes back in* from the
stream to refill it.

#keyidea[
  *Normalization is how a single bounded integer can carry an unbounded message.*
  Think of the state as a small bucket that must stay between a low-water mark $L$
  and a high-water mark. Encoding pours in; when it would overflow, you ladle the
  excess (the low byte) into the output and keep going. Decoding is the reverse:
  when the bucket runs low, you scoop a byte back from the stream. The output
  stream is the overflow record; the state is just the small working remainder.
]

The output bytes that get shoveled out form the actual compressed file, in reverse
order (LIFO again). At the very end of encoding, you flush the remaining state. To
decode, you initialize the state from the flushed value and pull bytes back as
needed. The arithmetic stays in machine words the whole time, which is exactly why
rANS is fast: no big-integer library, just shifts, masks, and one multiply.

#pitfall[
  The single most common rANS bug is getting the *normalization order* wrong: you
  must emit bytes to bring the state *below the threshold before* applying the
  encode transform, and the exact threshold depends on $F_s$ (it is proportional
  to $F_s$). Emit at the wrong moment and the round-trip silently corrupts. The
  fix is to always test `decode(encode(x)) == x` on random inputs — a property
  test, not a single example — before trusting your coder. Our `tinyzip` step
  below does exactly this.
]

== tANS: when one multiply is one too many

rANS uses *one* multiply per symbol. For the absolute fastest paths — think
decompressing gigabytes per second — even that one multiply is sometimes too much.
The answer is *tANS*, the _table_ variant, and it is the form Duda's 2013 paper is
most famous for.

The insight: if the frequencies $F_s$ are fixed for the whole message (a *static*
model), then the entire encode and decode behaviour — every possible
(state, symbol) → (new state, output bits) transition — can be *precomputed once*
and baked into a small lookup table. At run time, encoding or decoding a symbol
becomes a *table lookup, a shift, and a comparison*. No multiply. No divide. It is
literally a *finite-state machine*: the state is one of a few hundred or thousand
values, and each symbol drives a transition to the next state while spitting out a
few bits.

#gomaths("Finite-state machine")[
  A *finite-state machine* (FSM) is one of the most basic ideas in computer
  science: a system that is always in exactly one of a finite set of *states*, and
  that *transitions* to another state in response to an input. A turnstile is an
  FSM (locked → unlocked → locked); so is a traffic light (green → yellow → red →
  green). tANS turns entropy coding into an FSM: the "state" is the small ANS
  state integer, the "input" is the next symbol, and each transition both moves to
  a new state and emits some output bits. Because every transition is
  precomputed, running the machine is pure table lookup — the fastest thing a
  computer can do.
]

Building that table is mostly about *spreading* each symbol's slots across the
states as evenly as possible — the better the spread, the closer to entropy. A
minimal spreading step (the idea behind Zstandard's table builder) looks like
this:

#pyrecall[
  `enumerate(freqs)` walks a list handing you *both* the index and the item —
  `for sym, f in enumerate(freqs)` gives symbol `0` with its frequency, then `1`,
  and so on. We met it in Chapter 24; here `sym` is the symbol and `f` its slot
  count.
]

```python
def spread_symbols(freqs: list[int], table_bits: int) -> list[int]:
    size = 1 << table_bits                 # number of states, e.g. 4096
    table = [0] * size                     # slot -> which symbol owns it
    step = (size >> 1) + (size >> 3) + 3   # an odd stride that visits all slots
    pos = 0
    for sym, f in enumerate(freqs):
        for _ in range(f):                 # place this symbol f times
            table[pos] = sym
            pos = (pos + step) % size      # hop around the table
    return table                           # the static FSM's symbol map
```

The odd `step` walks the whole table in a scattered order, so each symbol's slots
end up sprinkled rather than clumped — exactly the even spreading that keeps the
finite-state machine near the entropy floor. From `table` one then precomputes the
new-state and output-bits for every transition, and tANS is ready to run with no
multiplies at all.

This spreading idea is exactly the structure used inside Zstandard's "FSE" (Finite
State Entropy) stage and inside JPEG XL. The price of tANS's speed is that the
model must be
*static* — you fix the frequencies, build the table, and cannot cheaply change the
probabilities mid-stream. rANS, by contrast, can adapt its frequencies on the fly
(at the cost of that one multiply), which is why a coder will often use rANS when
the statistics drift and tANS when they are stable. Both reach essentially the
same ratio.

#algo(
  name: "tANS (table-based / tabled ANS)",
  year: "2013",
  authors: "Jarosław Duda",
  aim: "Entropy-code a static-probability source with zero multiplications per symbol, using a precomputed finite-state-machine table.",
  complexity: "O(1) per symbol: one table lookup, one shift, one compare. Table build is a one-time O(M) cost.",
  strengths: "Fastest entropy coder known at this ratio; ideal for decode-heavy workloads (Zstandard FSE, JPEG XL); branch-light.",
  weaknesses: "Static model only — changing probabilities means rebuilding the table; table costs memory; ratio depends on careful table construction.",
  superseded: "Current state of the art for static-model entropy coding.",
)[
  tANS precomputes, for a fixed frequency table, a transition table mapping each
  (state, symbol) pair to a new state plus the bits to emit. Encoding and decoding
  then walk this finite-state machine. The quality of the table — how the symbols
  are *spread* across the states — determines how close the coder gets to entropy;
  the 2013 paper and later work (including a 2025 result on provably optimal
  tables) refine that spreading. tANS is what people usually mean when they say
  "ANS is as fast as Huffman": a tANS step is about as cheap as a Huffman
  table-decode step, but pays fractional bits like arithmetic coding.
]

#aside[
  The names can be confusing. "ANS" is the *family*. "uABS" is the simple binary
  member. "rANS" is the *range* variant for multi-symbol alphabets (one multiply).
  "tANS" is the *table* variant (no multiply, static model). Zstandard's "FSE" is
  an implementation of tANS. When someone says "the codec uses ANS", they almost
  always mean rANS or tANS depending on whether the model adapts.
]

== Building it: rANS in `tinyzip`

Time to make it real. Back in Chapter 26 we gave `tinyzip` an arithmetic coder in
`arithmetic.py`. Now we add `ans.py` — a working rANS encoder and decoder. This is
*Step 11* of the project.

#pyrecall[
  We will use `bytes` (an immutable sequence of integers $0$–$255$), the
  `bytearray` (its mutable cousin) with `.append()`, integer `//` (floor division)
  and `%` (modulo), the bit-shift `<<` and `>>`, and Python's arbitrary-precision
  `int`. All were introduced in the Python primers (Chapters 15–17). The one new
  idea is building a small *cumulative-frequency table*, which the next box
  explains.
]

#gopython("Building a frequency table from data")[
  To rANS-code bytes we first need each byte's quantized frequency $F_s$ and base
  $B_s$. We start from the raw counts (a `dict[int,int]` mapping byte → count,
  exactly the `histogram()` helper `tinyzip` built in Chapter 16), then scale the
  counts so they sum to a power of two $M$, fixing up rounding so no nonzero symbol
  gets frequency 0:
  ```python
  def make_freqs(counts: dict[int, int], total_bits: int = 12
                 ) -> tuple[list[int], list[int], int]:
      M = 1 << total_bits                 # e.g. 4096; the common denominator
      n = sum(counts.values()) or 1
      freqs = [0] * 256
      for sym, c in counts.items():
          freqs[sym] = max(1, (c * M) // n)   # never round a real symbol to 0
      # fix rounding so the frequencies sum to exactly M
      biggest = max(range(256), key=lambda s: freqs[s])
      freqs[biggest] += M - sum(freqs)    # absorb the slack into the top symbol
      bases = [0] * 257                   # cumulative bases B_s
      for s in range(256):
          bases[s + 1] = bases[s] + freqs[s]
      return freqs, bases, M
  ```
  `1 << total_bits` is "1 shifted left 12 places" $= 2^12 = 4096$. The list
  `freqs` holds $F_s$ for every byte value; `bases` holds the running totals $B_s$.
  We force every symbol that actually appears to have $F_s >= 1$ so it stays
  decodable.
]

Here is the core of `ans.py`. We keep the state in a 32-bit working range and
renormalize one byte at a time (radix $b = 256$). The encoder, because of LIFO,
walks the input *backwards* and the decoder reads the resulting bytes *forwards*.

#project("Step 11 · rANS encode/decode in `ans.py`")[
  We reuse `utils.histogram` from Chapter 16 (Step 2). The two workhorse functions
  are `rans_encode(data: bytes) -> bytes` and `rans_decode(blob: bytes) -> bytes`,
  each round-tripping. To match the package convention every codec follows —
  `huffman.encode`/`decode` (Chapter 24) and `arithmetic.encode`/`decode`
  (Chapter 26) — `ans.py` also exposes the same public `encode(data: bytes) -> bytes`
  and `decode(blob: bytes) -> bytes` names (thin aliases at the bottom of the file),
  so the container (Chapter 17) can dispatch on them uniformly and tag the payload
  with `method="rans"`.

  ```python
  # tinyzip/ans.py  — Step 11: rANS entropy coder
  from .utils import histogram          # Step 2 (Ch16): byte -> count

  RANS_L  = 1 << 23        # lower bound of the normalized state window
  M_BITS  = 12             # frequency precision: M = 2**12 = 4096
  M       = 1 << M_BITS

  def make_freqs(data: bytes) -> tuple[list[int], list[int]]:
      counts = histogram(data)                 # dict[int,int]
      n = sum(counts.values()) or 1
      freqs = [0] * 256
      for sym, c in counts.items():
          freqs[sym] = max(1, (c * M) // n)
      freqs[max(range(256), key=lambda s: freqs[s])] += M - sum(freqs)
      bases = [0] * 257
      for s in range(256):
          bases[s + 1] = bases[s] + freqs[s]
      return freqs, bases

  def rans_encode(data: bytes) -> bytes:
      freqs, bases = make_freqs(data)
      out = bytearray()
      x = RANS_L
      for sym in reversed(data):               # LIFO: encode backwards
          f, b = freqs[sym], bases[sym]
          x_max = ((RANS_L >> M_BITS) << 8) * f # renorm threshold for this symbol
          while x >= x_max:                     # shovel out low bytes
              out.append(x & 0xFF)
              x >>= 8
          x = ((x // f) << M_BITS) + b + (x % f)  # the rANS encode step
      header = bytearray()                     # serialize the freq table
      for s in range(256):
          header.append(freqs[s] & 0xFF)
          header.append((freqs[s] >> 8) & 0xFF)
      header += x.to_bytes(4, "little")        # flush final state
      header += len(data).to_bytes(4, "little")
      return bytes(header) + bytes(out)

  def rans_decode(blob: bytes) -> bytes:
      freqs = [blob[2*s] | (blob[2*s+1] << 8) for s in range(256)]
      bases = [0] * 257
      for s in range(256):
          bases[s + 1] = bases[s] + freqs[s]
      x = int.from_bytes(blob[512:516], "little")
      n = int.from_bytes(blob[516:520], "little")
      stream = blob[520:]
      pos = len(stream) - 1                     # read renorm bytes backwards
      slot2sym = bytearray(M)                   # slot -> symbol lookup
      for s in range(256):
          for k in range(bases[s], bases[s + 1]):
              slot2sym[k] = s
      out = bytearray()
      for _ in range(n):
          slot = x & (M - 1)                    # x mod M  (M is a power of two)
          sym = slot2sym[slot]
          f, b = freqs[sym], bases[sym]
          x = f * (x >> M_BITS) + slot - b      # the rANS decode step
          while x < RANS_L and pos >= 0:        # pull bytes back in
              x = (x << 8) | stream[pos]
              pos -= 1
          out.append(sym)
      return bytes(out)

  # public API, matching huffman.py / arithmetic.py (Ch24, Ch26)
  encode = rans_encode
  decode = rans_decode

  if __name__ == "__main__":                    # tiny self-test
      sample = b"abracadabra! " * 50
      blob = rans_encode(sample)
      assert rans_decode(blob) == sample, "round-trip failed!"
      print(f"{len(sample)} bytes -> {len(blob)} bytes  (rANS round-trips OK)")
  ```

  The two lines marked "the rANS encode/decode step" are exactly the $C(s,x)$ and
  $D(x)$ formulas from the worked example — note `<< M_BITS` is the multiply-by-$M$
  (a shift, since $M$ is a power of two) and `& (M - 1)` is the mod-$M$ (a mask).
  Everything else is plumbing: the frequency table, the normalization (the two
  `while` loops), and the LIFO bookkeeping (`reversed`, reading `stream`
  backwards). Run `python -m tinyzip.ans` and it prints a passing round-trip.
]

#gopython("`reversed()` and why we encode backwards")[
  `reversed(data)` yields the elements of `data` from last to first without copying
  the whole thing:
  ```python
  for c in reversed(b"abc"):
      print(c)          # prints 99, 98, 97  (i.e. 'c', 'b', 'a')
  ```
  ANS decodes LIFO — it recovers the *last-encoded* symbol *first*. So to make the
  decoder emit the message in the *correct forward order*, the encoder must feed it
  the message *backwards*. That single `reversed()` call is how `tinyzip` arranges
  the stack so it pops in the order the reader expects. Forget it and your message
  comes out reversed — a classic ANS rite of passage.
]

=== Does it actually win? The scoreboard

Let us run our running sample through the new coder. We reuse the same
10,000-byte excerpt of English text that *Chapter 24* compressed with Huffman,
whose byte histogram has entropy $H approx 4.18$ bits/byte — so the information
floor is about $10000 times 4.18 slash 8 approx 5225$ bytes. Here is where rANS
lands relative to the coders we have built:

#scoreboard(caption: "10,000-byte English text sample; lower is better",
  [Raw (no compression)], [10,000], [1.00×], [the baseline: 8 bits/byte],
  [Huffman (Ch 24)], [≈ 5,490], [1.82×], [optimal _integer_-bit code; pays the rounding tax],
  [Arithmetic (Ch 26)], [≈ 5,232], [1.91×], [hits the floor; adaptive model, no table sent],
  [*rANS (Ch 27)*], [*≈ 5,746*], [*1.74×*], [*floor-tight body, but ships a 512-byte static freq table*],
  [Entropy floor $H$], [≈ 5,225], [1.91×], [Shannon's limit for this order-0 model],
)

The headline result needs one honest footnote. rANS's _coded body_ lands right on
the entropy floor — its per-symbol cost is $-log_2 p_s$, exactly like arithmetic
coding, and on this sample the body is within a handful of bytes of the 5,225-byte
limit. The reason the rANS _file_ is a touch larger than arithmetic coding's here
is not the coder; it is the *model delivery*. Our `tinyzip` arithmetic coder uses
an _adaptive_ model (Chapter 26) that both sides rebuild on the fly, so it
transmits no probability table. Our `ans.py`, to keep the code short, uses a
_static_ model and serializes a 512-byte frequency table into the header. On a
10,000-byte file that fixed 512-byte tax dominates the comparison; on a megabyte
file it vanishes into the noise and rANS and arithmetic coding land within bytes of
each other — at a fraction of the per-symbol cost.

#keyidea[
  *Coder versus container.* The scoreboard measures whole files, but the
  chapter's claim — _rANS reaches the arithmetic-coding ratio_ — is about the
  *coded body*, the bits spent on the symbols themselves. There rANS and
  arithmetic coding are neck-and-neck at the entropy floor. The 512-byte gap above
  is pure table-shipping overhead, an artifact of choosing a static model for a
  short teaching example, not a property of ANS. Real ANS codecs amortize or
  compress that table away; Zstandard, for one, packs the frequency table into a
  handful of bytes.
]

#checkpoint[
  Why does rANS not get the _body_ *below* 5,225 bytes, the entropy floor for this
  sample?
][Because 5,225 bytes is the Shannon limit for an *order-0 model* — one that treats
each byte independently with fixed probabilities. No entropy coder can beat the
floor of the model it is given (Chapter 19). To go lower you must give the coder a
*better model* — one that uses context, like predicting each byte from the
previous one. That is the job of the modeling chapters (PPM, context mixing) still
to come; the entropy coder's job is only to spend exactly the bits the model
asks for, and rANS does that essentially perfectly.]

== The human story: a gift, and two attempts to take it back

ANS is not only a beautiful algorithm; it is a parable about who owns ideas.

Duda did something unusual: he deliberately placed ANS in the *public domain*,
refusing to patent it, and actively encouraged the world to build on it freely.
That generosity paid off in adoption that was remarkably swift and broad. In 2015,
*Facebook* shipped *Zstandard* (zstd) — now one of the most widely deployed
compressors on earth, in the Linux kernel, databases, and package managers — using
ANS (the tANS-based "FSE" stage) for entropy coding. The same year, *Apple*
released *LZFSE*, an ANS-based codec used deep inside iOS and macOS. And the JPEG
committee's next-generation image format, *JPEG XL* (developed from 2017, with its
core specification finalized around 2021–2022), uses *rANS* with a 32-bit state and
12-bit frequency precision — the very parameters our `tinyzip` coder mirrors. ANS
also turned up in genomics (the CRAM format), in Google, Microsoft, Dropbox, and
Pixar pipelines, and across countless smaller projects.

#history[
  Then came the patent drama — a near-replay of the arithmetic-coding patent saga
  from Chapter 26. Around 2015, *Google* filed a patent application covering an
  ANS-based coefficient-coding scheme ("Mixed Boolean-Token ANS"), at a time when
  Duda had been helping Google with video compression. After Duda objected
  publicly and the *Electronic Frontier Foundation* (EFF) took up the cause, the
  US Patent Office issued rejections, and *Google abandoned* the application around
  2018. The story did not end there. On *25 January 2022*, *Microsoft* was granted
  US patent 11,234,023, "Features of range asymmetric number system encoding and
  decoding" (filed 28 June 2019), covering certain rANS modifications — provoking
  alarm in the compression community that the public-domain gift was again being
  fenced off. Duda has consistently maintained that the *core* ANS methods are
  prior art and free for all; the disputes concern specific narrow modifications.
  The episode is a vivid reminder of a theme running through this entire volume:
  the cleanest algorithm in the world still has to survive the patent system.
]

#aside[
  Research on ANS is still active. A 2025 paper by Steiner, De Vita, and Bezati,
  "Optimal tables for asymmetric numeral systems" (arXiv:2504.18541), gives
  algorithms that build provably optimal tANS tables — tightening the last
  fraction of a percent of entropy loss from the table-spreading step. Sixteen
  years after Duda's first paper, people are still finding ways to squeeze ANS
  closer to the Shannon floor.
]

== Putting it together

ANS completes the entropy-coding story of this volume. We now have three ways to
turn a probability model into bits, and we understand the trade-offs precisely:
Huffman (fast, but pays an integer-bit tax), arithmetic coding (optimal, but two
expensive operations per symbol), and ANS (optimal *and* fast, paying one
operation per symbol in rANS or none in tANS). For new general-purpose and image
codecs built since 2015, ANS is the default choice, and understanding it is no
longer optional for anyone serious about compression.

#takeaways((
  [*ANS is an asymmetric numeral system*: a reversible way to pack symbols into one growing integer (the _state_), giving each symbol a slice of the number line equal to its probability.],
  [Encoding a symbol of probability $p_s$ multiplies the state by about $1 slash p_s$, which adds $-log_2 p_s$ bits — the surprisal. Summed over a message, this hits the entropy floor.],
  [ANS is naturally *LIFO*: the decoder recovers symbols in reverse order, so the encoder must process the buffer backwards.],
  [*uABS* is the simple two-symbol member; *rANS* scales to a full alphabet with one multiply per symbol; *tANS* precomputes a finite-state-machine table and uses _no_ multiply, at the cost of a static model.],
  [*Normalization* keeps the state inside a fixed window by shoveling low bytes to the output (encode) and pulling them back (decode), so one machine-word state can carry an arbitrarily long message.],
  [rANS *matches arithmetic coding's ratio at Huffman-class speed* — the trade-off everyone thought was fundamental simply collapsed.],
  [ANS powers *Zstandard, LZFSE, and JPEG XL*. Duda gave it to the public domain; Google's patent attempt was abandoned (\~2018) and Microsoft's was granted (2022), echoing the old arithmetic-coding patent wars.],
))

== Exercises

#exercise("27.1", 1)[
  In your own words, explain why a *common* symbol grows the ANS state by a small
  amount while a *rare* symbol grows it by a large amount. Connect your answer to
  the idea of *surprisal* from Chapter 18.
]
#solution("27.1")[
  ANS gives symbol $s$ a fraction $p_s$ of the slots, so to reach the next $s$-slot
  the state must roughly multiply by $1 slash p_s$. A common symbol has large
  $p_s$, so $1 slash p_s$ is small — the state barely grows, adding few bits. A
  rare symbol has tiny $p_s$, so $1 slash p_s$ is large — the state jumps, adding
  many bits. The bits added are $log_2(1 slash p_s) = -log_2 p_s$, which is
  precisely the surprisal: the rarer the symbol, the more information it carries,
  the more bits it costs. ANS spends exactly the surprisal on each symbol.
]

#exercise("27.2", 1)[
  Using the uABS slot machine with $p = 0.3$ — recall the `0`-slots are
  $1, 2, 4, 5, 7, 8, 9, dots$ — encode the message `0 0` starting from state
  $x = 0$ by sending each `0` to "the $x$-th `0`-slot". What final state do you get,
  how many bits is it, and why is that so small?
]
#solution("27.2")[
  Encoding the first `0` from $x = 0$ means "go to the 0-th `0`-slot", which is the
  first one listed, state 1. So $x = 1$. Encoding the second `0` from $x = 1$ means
  "go to the 1st `0`-slot", which is state 2. So the final state is $x = 2$, binary
  `10` — just 2 bits for two symbols. That is *less* than one whole bit per symbol,
  which is exactly right: each `0` has probability $0.7$ and deserves only
  $-log_2 0.7 approx 0.515$ bits. A whole-bit coder like Huffman could never spend
  half a bit on a symbol; uABS does it by letting the common `0` make only tiny
  hops between its densely-packed slots.
]

#exercise("27.3", 2)[
  Take the rANS table $F = (4, 3, 1)$, $B = (0, 4, 7)$, $M = 8$ from the chapter.
  Starting from $x = 8$, encode the single symbol `b` with
  $x' = floor(x slash F_s) dot M + B_s + (x mod F_s)$. Then decode your $x'$ back:
  find the slot $x' mod 8$, identify the symbol, and invert. Show every step.
]
#solution("27.3")[
  *Encode `b`* ($F_b = 3, B_b = 4$): $x' = floor(8 slash 3) dot 8 + 4 + (8 mod 3)
  = 2 dot 8 + 4 + 2 = 16 + 6 = 22$. *Decode from $x' = 22$:* slot $= 22 mod 8 = 6$.
  Which block contains slot 6? `b` owns slots $4, 5, 6$ (since $B_b = 4, F_b = 3$),
  so the symbol is `b`. ✓ Invert: $x = F_b dot floor(22 slash 8) + (22 mod 8) - B_b
  = 3 dot 2 + 6 - 4 = 6 + 2 = 8$. We recovered the original state $x = 8$. ✓
]

#exercise("27.4", 2)[
  Explain, with a concrete example, why ANS must operate *LIFO*. If you encode the
  message `A B C` (in that order), in what order does a straightforward ANS decoder
  recover the symbols, and what is the standard fix so the decoded output reads
  `A B C`?
]
#solution("27.4")[
  Each encode step grows the state by stacking the new symbol "on top". To shrink
  the state you must undo the *most recent* growth first — like removing the top
  plate from a stack. So if you encode `A`, then `B`, then `C`, the decoder peels
  them off as `C`, then `B`, then `A` — reverse order (last-in, first-out). The
  standard fix is to *feed the encoder the message backwards* (encode `C B A`), so
  that the decoder's reverse readout produces `A B C` in the correct forward order.
  Our `tinyzip` coder does this with the single `reversed(data)` call in
  `rans_encode`.
]

#exercise("27.5", 2)[
  The chapter says rANS does "half the arithmetic" of an arithmetic coder. Count
  the per-symbol operations: list what arithmetic coding does per symbol (from
  Chapter 26) versus what rANS encode and rANS decode each do. Why does making $M$
  a power of two matter for this comparison?
]
#solution("27.5")[
  Arithmetic coding updates an interval $[#text[low], #text[high])$ per symbol,
  needing a *multiply* (to scale the range) and a *divide* (to map the
  cumulative frequency into the range) — two costly operations. rANS *encode* does
  one divide ($x slash F_s$), one multiply (by $M$), and one mod; rANS *decode*
  does one multiply ($F_s dot (x >> M\_"BITS")$). Making $M = 2^k$ a power of two
  turns the "multiply by $M$" into a cheap *bit-shift* and the "mod $M$" into a
  cheap *bit-mask*, so the only genuine multiply/divide left is the one involving
  $F_s$. That is why rANS is roughly half the real arithmetic cost of an
  arithmetic coder, and tANS (table lookup) removes even that.
]

#exercise("27.6", 2)[
  Run the `tinyzip` `ans.py` self-test from the chapter, then modify the test to
  feed it (a) a single repeated byte `b"x" * 1000`, and (b) random bytes
  `bytes(random.randrange(256) for _ in range(1000))`. For each, predict whether
  rANS compresses well or poorly *before* running it, then check. Explain the
  results using entropy.
]
#solution("27.6")[
  (a) `b"x" * 1000` has entropy near 0 bits/byte — one symbol with probability 1 —
  so rANS should compress it to almost nothing (just the frequency table, final
  state, and a few normalization bytes). (b) Uniform random bytes have entropy
  $approx 8$ bits/byte (every value equally likely), the maximum, so rANS *cannot*
  shrink the payload at all — the output will be about as large as the input (in
  fact slightly larger, because of the frequency-table header). This demonstrates
  the central law (Chapter 19): an entropy coder can only spend the bits the model
  dictates, and random data has no redundancy for any order-0 model to remove.
]

#exercise("27.7", 3)[
  *Prove* that the rANS encode and decode formulas are exact inverses. That is,
  show that if $x' = floor(x slash F_s) dot M + B_s + (x mod F_s)$, then decoding —
  reading slot $= x' mod M$, recovering $s$ (the symbol whose block contains that
  slot), and computing $F_s dot floor(x' slash M) + (x' mod M) - B_s$ — returns
  exactly $x$. (Hint: use $0 <= x mod F_s < F_s$ and $0 <= B_s + (x mod F_s) < M$.)
]
#solution("27.7")[
  Write $q = floor(x slash F_s)$ and $r = x mod F_s$, so $x = q F_s + r$ with
  $0 <= r < F_s$. Then $x' = q M + B_s + r$. Since $0 <= B_s + r < M$ (because
  $B_s + F_s <= M$ and $r < F_s$), the quotient and remainder of $x'$ by $M$ are
  clean: $floor(x' slash M) = q$ and $x' mod M = B_s + r$. The slot $x' mod M =
  B_s + r$ lies in $[B_s, B_s + F_s)$, which is exactly $s$'s block, so the decoder
  recovers the correct symbol $s$. Now compute the decode formula: $F_s dot
  floor(x' slash M) + (x' mod M) - B_s = F_s dot q + (B_s + r) - B_s = q F_s + r =
  x$. The original state is recovered exactly. $qed$
]

#exercise("27.8", 3)[
  Compare *rANS* and *tANS* as engineering choices. Give one realistic scenario
  where you would prefer rANS and one where you would prefer tANS, and justify each
  in terms of (i) whether the probabilities change during the stream and (ii) the
  cost per symbol. Then explain why Zstandard's "FSE" stage is a tANS, not an rANS.
]
#solution("27.8")[
  *Prefer rANS* when the probabilities *adapt* mid-stream — for example, a general
  archiver whose statistics drift as the file's content changes, or a coder
  feeding from an adaptive model. rANS pays one multiply per symbol but can change
  $F_s$ at any time without rebuilding anything. *Prefer tANS* when the
  probabilities are *fixed for a block* and raw decode speed is paramount — for
  example, decompressing a Zstandard or JPEG XL stream where each block has a
  static, transmitted frequency table. tANS precomputes a finite-state-machine
  table, so each symbol costs only a lookup, a shift, and a compare — no multiply.
  Zstandard's FSE is a tANS because zstd builds a fixed frequency table per block
  and then decodes that block at maximum speed; the static-model restriction is
  exactly satisfied, and the payoff is gigabyte-per-second decoding.
]

== Further reading

- Jarosław Duda (2009), _Asymmetric Numeral Systems_, the original paper:
  #link("https://arxiv.org/abs/0902.0271")[arXiv:0902.0271].
- Jarosław Duda (2013), _Asymmetric Numeral Systems: Entropy Coding Combining
  Speed of Huffman Coding with Compression Rate of Arithmetic Coding_:
  #link("https://arxiv.org/abs/1311.2540")[arXiv:1311.2540] — the definitive
  treatment of uABS, rANS, and tANS.
- Steiner, De Vita & Bezati (2025), _Optimal Tables for Asymmetric Numeral
  Systems_: #link("https://arxiv.org/abs/2504.18541")[arXiv:2504.18541] — provably
  optimal tANS table construction.
- Fabian Giesen, _rANS in practice_ (2015), a famously clear engineering account
  of interleaving and SIMD:
  #link("https://fgiesen.wordpress.com/2015/12/21/rans-in-practice/")[ryg blog].
- The Register (2022), _Alarm raised after Microsoft wins data-encoding patent_:
  #link("https://www.theregister.com/2022/02/17/microsoft_ans_patent/")[on the rANS patent].
- The Zstandard format specification (RFC 8878) for the FSE/tANS entropy stage:
  #link("https://www.rfc-editor.org/rfc/rfc8878")[RFC 8878].

#bridge[
  We have now mastered the *entropy coders* — the machines that turn probabilities
  into bits as efficiently as theory allows: Huffman, arithmetic, range, and ANS.
  But all of them are only as good as the *model* feeding them probabilities, and
  so far our models have been simple order-0 histograms. The next great leap in
  compression came from a completely different direction: instead of modeling
  *which symbols* are likely, what if we exploited the fact that real data
  *repeats itself* — that long stretches of text, code, and images are copies of
  things we have already seen? *Chapter 28* opens the door to *dictionary coding*
  and the Lempel–Ziv family (LZ77 and LZ78), the idea behind almost every
  general-purpose compressor you use every day, from `gzip` to `zstd` itself.
]
