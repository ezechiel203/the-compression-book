#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Arithmetic Coding

#epigraph[The idea of arithmetic coding is to represent a message by an interval of real numbers between 0 and 1.][Ian H. Witten, Radford M. Neal, and John G. Cleary, _Arithmetic Coding for Data Compression_, 1987]

Here is a puzzle that broke Huffman's heart. Suppose you are compressing a long stream of coin flips from a very biased coin — say it lands heads $99%$ of the time. Information theory, which we built in Chapter 18, is crystal clear about the price: a head, being almost certain, deserves only $-log_2 0.99 approx 0.0145$ bits, and a tail deserves $-log_2 0.01 approx 6.64$ bits. Over a thousand flips that averages to about $80.8$ bits total — the *entropy* of the source, the floor below which Chapter 19 proved no honest coder may go.

Now hand the job to the best prefix code in the world, Huffman's, which we will meet in full in Chapter 24. Huffman must give each symbol a whole number of bits. There are only two symbols, so the shortest codeword it can possibly assign is *one bit* — to heads, and one bit to tails. A thousand flips therefore cost a thousand bits. The theory said $81$; Huffman charged $1000$. It overpaid by more than *twelvefold*, and no amount of cleverness inside the Huffman framework can fix it, because the leak is structural: you cannot spend $0.0145$ of a bit when your smallest coin is worth a whole bit.

This chapter is about the coder that _can_ spend a fraction of a bit. Its trick is so simple to state and so slippery to believe that it took the field almost twenty-five years to make it work in a real computer: instead of giving each symbol its own little code, *encode the entire message as a single number* — one point on the number line between 0 and 1, chosen so precisely that reading it back replays the whole message. That coder is *arithmetic coding*, and by the end of this chapter you will have built one in Python that hits the entropy floor of that biased coin almost exactly, that plugs straight into the `tinyzip` container we assembled in Chapter 17, and that you understand down to the last carry bit.

#recap[
We lean on four earlier results. From Chapter 7, the *logarithm*: $log_2 N$ is the number of bits needed to single out one item from $N$ equally likely ones, and $-log_2 p$ is the "ideal" length of a symbol of probability $p$. From Chapter 9, *probability* — distributions $p(x)$, and that independent probabilities _multiply_. From Chapter 18, *entropy* $H(X) = -sum_x p(x) log_2 p(x)$, the average ideal length, and from Chapter 19 the *source coding theorem*: $H$ is the unbeatable floor and is reachable in the limit. From Chapter 23 came the thesis that _a sharper model means fewer bits_, and the _Krichevsky–Trofimov_ "predict, code, update" idea whose byte-level cousin we build here. And from Chapter 17 we carry the working `BitWriter`, `BitReader`, and the `tinyzip` `container` (its `write`/`read` and `write_checked`/`read_checked`) — the plumbing this chapter fills with a genuinely near-optimal payload.
]

#objectives((
  [Explain the *interval* picture of arithmetic coding: a message is a sub-interval of $[0, 1)$ whose width equals the product of its symbols' probabilities.],
  [Encode and decode a short message _by hand_ with infinite-precision arithmetic, and see why the bit cost equals $-log_2("width") approx H$.],
  [Understand *renormalization* (rescaling the interval and shipping settled bits) and the *carry / underflow* problem, and how the E1/E2/E3 rules from Witten–Neal–Cleary solve it in fixed-precision integers.],
  [Distinguish *arithmetic coding* from *range coding* and from *binary arithmetic coding* (CABAC / the MQ-coder), and say where each is used.],
  [Recount the *patent saga* that kept the better algorithm out of JPEG for a generation, and why it still shapes which codecs you use today.],
  [Implement a complete, integer, adaptive arithmetic coder in `tinyzip` (`arithmetic.py`) that round-trips any `bytes` and beats Huffman on skewed data.],
))

== The one-number idea

Forget bits for a moment and think about the number line between 0 and 1 — every real number $0 <= x < 1$, an interval we write $[0, 1)$ (the square bracket includes 0, the round bracket excludes 1). Arithmetic coding's whole philosophy is this: *a message is a point in $[0, 1)$, and to send the message you send a number close enough to that point.* The more symbols in the message, the more precisely you must pin the point down, and the cost in bits is exactly the cost of that precision.

Let us make it concrete with a three-symbol alphabet — say the letters `A`, `B`, `C` — with probabilities $p(A) = 0.5$, $p(B) = 0.3$, $p(C) = 0.2$. (They sum to 1, as probabilities must.) We carve the interval $[0, 1)$ into three slices, one per symbol, each as wide as its probability and stacked in a fixed agreed order:

#fig([The unit interval split by symbol probability. `A` owns $[0, 0.5)$, `B` owns $[0.5, 0.8)$, `C` owns $[0.8, 1.0)$. The width of each slice _is_ its probability.], cetz.canvas({
  import cetz.draw: *
  let w = 10
  rect((0,0),(w*0.5,0.8), fill: rgb("#cfe2f3"))
  rect((w*0.5,0),(w*0.8,0.8), fill: rgb("#fce5cd"))
  rect((w*0.8,0),(w,0.8), fill: rgb("#d9ead3"))
  content((w*0.25,0.4))[*A* (0.5)]
  content((w*0.65,0.4))[*B* (0.3)]
  content((w*0.9,0.4))[*C* (0.2)]
  line((0,0),(0,-0.25)); content((0,-0.5))[0.0]
  line((w*0.5,0),(w*0.5,-0.25)); content((w*0.5,-0.5))[0.5]
  line((w*0.8,0),(w*0.8,-0.25)); content((w*0.8,-0.5))[0.8]
  line((w,0),(w,-0.25)); content((w,-0.5))[1.0]
}))

To encode a _message_, we do the same carving again and again, each time inside the slice we have already chosen. Read each symbol; zoom into its slice; treat that slice as the new "whole" and carve it into the same three proportions; read the next symbol; zoom again. The interval only ever shrinks, and after the last symbol we are left with one tiny final interval. _Any_ number inside that final interval encodes the message — so we pick the one that is cheapest to write in binary, and send it. Decoding reverses the zoom: see which slice the number fell in, emit that symbol, rescale, and repeat.

Notice the bookkeeping we need. At every step the current interval is described by two numbers, its `low` end and its `high` end (or equivalently `low` and a `width`). To split it we need, for the incoming symbol, the fraction of the line _below_ it and the fraction _at or below_ it — the running sums of probability. Those running sums have a name we met in spirit in Chapter 9: the *cumulative distribution*.

#gomaths("Cumulative probability (the running total)")[
Line your symbols up in a fixed order $s_0, s_1, s_2, dots$ Then the *cumulative probability* of symbol $s_k$ is the total probability of all symbols _before_ it:
$ C(s_k) = sum_(j < k) p(s_j). $
It answers "how far along the $[0,1)$ line does $s_k$'s slice _begin_?" The slice for $s_k$ is then the half-open interval $[ C(s_k), space C(s_k) + p(s_k) )$ — it starts at the running total and is $p(s_k)$ wide.

For our alphabet ($p(A)=0.5, p(B)=0.3, p(C)=0.2$):
$ C(A) = 0, quad C(B) = 0.5, quad C(C) = 0.5 + 0.3 = 0.8. $
So `A` lives in $[0, 0.5)$, `B` in $[0.5, 0.8)$, `C` in $[0.8, 1.0)$ — exactly the figure above. The cumulative total $C$ tells you where a slice _starts_; the probability $p$ tells you how _wide_ it is. Those two numbers per symbol are all an arithmetic coder ever needs.
]

== Encoding by hand: the message `BAC`

Let us encode `BAC` with infinite-precision arithmetic — pencil, paper, and patience — so the mechanism is undeniable before we worry about making a computer do it. We keep a running `low` and `high`; they start at the full interval.

$ "low" = 0.0, quad "high" = 1.0, quad "width" = "high" - "low" = 1.0. $

*Symbol 1 is `B`.* Inside the current interval, `B`'s slice runs from $C(B) = 0.5$ to $C(B) + p(B) = 0.8$ of the way across. We update by sliding and scaling:
$ "new low" &= "low" + "width" times C(B) = 0.0 + 1.0 times 0.5 = 0.5, \
  "new high" &= "low" + "width" times (C(B) + p(B)) = 0.0 + 1.0 times 0.8 = 0.8. $
Now $"low" = 0.5$, $"high" = 0.8$, $"width" = 0.3$. We have zoomed into `B`'s slice; the interval is exactly $p(B) = 0.3$ wide, as promised.

*Symbol 2 is `A`.* Within $[0.5, 0.8)$, `A`'s slice runs from $C(A) = 0.0$ to $C(A) + p(A) = 0.5$ of the way across:
$ "new low" &= 0.5 + 0.3 times 0.0 = 0.5, \
  "new high" &= 0.5 + 0.3 times 0.5 = 0.65. $
Now $"low" = 0.5$, $"high" = 0.65$, $"width" = 0.15 = 0.3 times 0.5 = p(B) times p(A)$. The widths are _multiplying_, just as independent probabilities do.

*Symbol 3 is `C`.* Within $[0.5, 0.65)$, `C`'s slice runs from $C(C) = 0.8$ to $1.0$ of the way across:
$ "new low" &= 0.5 + 0.15 times 0.8 = 0.62, \
  "new high" &= 0.5 + 0.15 times 1.0 = 0.65. $
Final interval: $[0.62, 0.65)$, width $0.03 = 0.3 times 0.5 times 0.2 = p(B) p(A) p(C)$.

#fig([Three successive zooms encoding `BAC`. Each step picks the incoming symbol's slice of the current interval; the interval shrinks from width 1 to 0.3 to 0.15 to 0.03. Any number in the final $[0.62, 0.65)$ encodes `BAC`.], cetz.canvas({
  import cetz.draw: *
  let bar(y, lo, hi, lab) = {
    let w = 9
    rect((0,y),(w,y+0.6), stroke: gray)
    rect((w*lo,y),(w*hi,y+0.6), fill: rgb("#fce5cd"))
    content((w+1.6, y+0.3))[#lab]
  }
  bar(3, 0.5, 0.8, [after `B`: $[0.5,0.8)$])
  bar(1.5, 0.5, 0.65, [after `A`: $[0.5,0.65)$])
  bar(0, 0.62, 0.65, [after `C`: $[0.62,0.65)$])
  content((-1.0,3.3))[Step 1]
  content((-1.0,1.8))[Step 2]
  content((-1.0,0.3))[Step 3]
}))

Now the punchline. To transmit `BAC` we need only send _some_ number inside $[0.62, 0.65)$ — for instance $0.625$, which in binary is exactly $0.101_2$ (since $0.5 + 0.125 = 0.625$). Three bits: `101`. The decoder, knowing the same probabilities, will find that $0.625$ lands in `B`'s slice, then (after rescaling) in `A`'s, then in `C`'s, and recover `BAC` perfectly. We will walk that decode in a moment.

Was three bits a good price? The information content of `BAC` is
$ -log_2(p(B) p(A) p(C)) = -log_2(0.03) approx 5.06 "bits." $
So the ideal cost is about $5.06$ bits and we got lucky finding a $3$-bit number that happened to fall inside; on a longer message the slack vanishes and the cost converges to within a hair of $-log_2("final width")$, which is exactly the sum of the symbols' surprisals — the entropy. _That_ is the whole miracle: the cost of the message equals the negative log of the final interval's width, and that width is the product of all the symbol probabilities, so the cost is the sum of $-log_2 p$ over the message, with no per-symbol rounding to whole bits.

#keyidea[
Arithmetic coding never assigns a code to a symbol. It assigns one interval to the _whole message_, of width equal to the product of all the symbol probabilities, and then spends $approx -log_2("width")$ bits naming a point inside it. Because there is no per-symbol rounding, a symbol of probability $0.99$ genuinely costs about $0.0145$ bits — the fractional bits are pooled across the message and paid in one lump at the end. This is precisely the leak that sinks Huffman, sealed.
]

#gomaths("Why minus-log-width bits suffice to name a point")[
Suppose the final interval has width $w$. How many bits does it take to pick a number guaranteed to land inside it? Chop $[0,1)$ into $2^b$ equal pieces, each of width $1\/2^b$; a binary fraction with $b$ digits names one such piece. To be _sure_ at least one of these grid points lies in an interval of width $w$, you need the grid spacing $1\/2^b$ to be at most $w$ (give or take one extra bit for alignment), i.e. $2^b >= 1\/w$, i.e.
$ b >= log_2 (1/w) = -log_2 w. $
So an interval of width $w$ costs about $-log_2 w$ bits to specify — at most $-log_2 w + 2$ once you account for the alignment slack. Since $w$ is the product of the message's symbol probabilities, $-log_2 w = sum_i -log_2 p_i$, the total surprisal, which averages to the entropy $H$. The "$+2$" is a fixed overhead for the _entire message_, so per symbol it melts to nothing as the message grows. That vanishing overhead is the formal reason arithmetic coding reaches the Chapter 19 floor.
]

== Decoding by hand: getting `BAC` back

The decoder receives the number $0.625$ and the same probability table, and nothing else — not even the message length yet (we will deal with stopping shortly). It repeats the _same_ carving and asks, at each step, which slice the number fell into.

*Step 1.* Is $0.625$ in `A`'s slice $[0, 0.5)$, `B`'s $[0.5, 0.8)$, or `C`'s $[0.8, 1.0)$? It is in $[0.5, 0.8)$ — so the first symbol is *`B`*. Now we must "remove" `B` to see the next symbol. Undo the slide-and-scale: subtract `B`'s start and divide by `B`'s width.
$ "new value" = (0.625 - C(B)) / p(B) = (0.625 - 0.5) / 0.3 = 0.41666dots $

*Step 2.* Is $0.41666$ in `A` $[0,0.5)$, `B` $[0.5,0.8)$, or `C` $[0.8,1.0)$? In $[0, 0.5)$ — the second symbol is *`A`*. Remove `A`:
$ "new value" = (0.41666 - C(A)) / p(A) = (0.41666 - 0.0) / 0.5 = 0.83333dots $

*Step 3.* Is $0.83333$ in `A`, `B`, or `C`? In $[0.8, 1.0)$ — the third symbol is *`C`*. We have recovered *`B`, `A`, `C`* — exactly the message.

The decoder is the encoder run backwards: the encoder _narrows_ the interval by the incoming symbol; the decoder _widens_ (un-scales) the received number by the symbol it just identified. The same two numbers per symbol — cumulative start $C$ and width $p$ — drive both directions.

#checkpoint[Using the same table $p(A)=0.5, p(B)=0.3, p(C)=0.2$, which symbol does the decoder emit first if it receives the number $0.93$? And the second?][$0.93$ lies in `C`'s slice $[0.8, 1.0)$, so the first symbol is `C`. Remove `C`: $(0.93 - 0.8)\/0.2 = 0.65$, which lies in `B`'s slice $[0.5, 0.8)$, so the second symbol is `B`.]

#misconception[Arithmetic coding needs perfect real-number arithmetic — those endless decimals like $0.41666dots$ — so it can only ever be an idealisation, not something a real, finite computer can do.][This was exactly the objection that stalled the idea for two decades after Elias sketched it. The resolution, which fills the next two sections, is _renormalization_: you do not keep the full-precision number. As soon as the high and low ends of the interval agree on their leading binary digit, that digit can never change again, so you _ship it out_ and _shift it away_, rescaling the interval back up to fill the register. The arithmetic stays inside fixed-width integers forever; the "infinite precision" is an illusion produced by streaming the settled digits as you go. Real arithmetic coders use nothing but ordinary 32- or 64-bit integer add, subtract, multiply, and shift.]

Before we build the real, fixed-precision coder, it is worth seeing the _idealised_ version in Python — a direct transcription of the by-hand `BAC` walk, using ordinary floating-point `low`/`high`. It is not a usable codec (floats run out of precision after a dozen or so symbols, and that is exactly the flaw renormalization fixes), but it makes the interval idea concrete in code:

```python
# Idealised, NON-production arithmetic coder (floats, short messages only).
P  = {"A": 0.5, "B": 0.3, "C": 0.2}              # probabilities
C  = {"A": 0.0, "B": 0.5, "C": 0.8}              # cumulative starts

def encode_interval(msg: str) -> tuple[float, float]:
    low, high = 0.0, 1.0
    for sym in msg:
        width = high - low
        high = low + width * (C[sym] + P[sym])    # narrow to the top of the slice
        low  = low + width * C[sym]               # ... and the bottom
    return low, high                              # any x in [low, high) encodes msg

def decode_interval(x: float, n: int) -> str:
    out = []
    for _ in range(n):
        for sym in "ABC":                         # which slice holds x?
            if C[sym] <= x < C[sym] + P[sym]:
                out.append(sym)
                x = (x - C[sym]) / P[sym]          # rescale, removing this symbol
                break
    return "".join(out)

lo, hi = encode_interval("BAC")
print(lo, hi)                       # 0.62 0.65  — the interval we found by hand
print(decode_interval(0.625, 3))    # BAC
```

Run it and you get the interval $[0.62, 0.65)$ and the message `BAC` back — the pencil-and-paper computation, exactly. The whole rest of the engineering in this chapter exists to do this same thing in bounded integers so it works on messages of any length.

== A short history: from an unworkable idea to a working coder

The interval idea did not arrive fully formed. It was assembled over a quarter of a century by people who each fixed one fatal flaw in the version before them.

#history[
The seed is usually credited to *Peter Elias* around 1960–1963, a colleague of Shannon's at MIT. Elias never published it; it survives because *Norman Abramson* described it, attributing it to Elias, in his 1963 textbook _Information Theory and Coding_. Elias's scheme was mathematically perfect and practically useless: it required arithmetic of unbounded precision — numbers that grew one digit longer for every symbol of the message — so a long file demanded an impossibly long number. For more than a decade it was a beautiful footnote.

The breakthrough came in 1976, independently and almost simultaneously, from two researchers. *Richard Pasco*, in his Stanford PhD thesis, and *Jorma Rissanen*, at IBM, each showed how to do the coding in _fixed_ precision by streaming out the high-order digits as soon as they settled — the renormalization trick. Rissanen and *Glen Langdon* then wrote the paper that named and systematised the field, _Arithmetic Coding_, in the _IBM Journal of Research and Development_ in 1979. But these early papers were dense and the code was subtle; arithmetic coding remained a specialist's art.

What turned it into common engineering knowledge was a single, famously lucid 1987 paper: *Ian Witten, Radford Neal, and John Cleary*, _Arithmetic Coding for Data Compression_, in _Communications of the ACM_ (volume 30, number 6, pages 520–540). It shipped complete, working, well-commented C source for an integer arithmetic coder with an adaptive model, and it explained the underflow problem and its fix so clearly that essentially every arithmetic coder written since is a descendant of it. The integer coder you build later in this chapter is, in its bones, the Witten–Neal–Cleary coder.
]

== Going fixed-precision: the interval as two integers

To run forever in bounded memory, we replace the real numbers $"low"$ and $"high"$ with two integers in a fixed range, say $[0, 2^16)$ — that is, $16$-bit integers from $0$ to $65535$. Think of these integers as binary fractions: the integer $L$ stands for the fraction $L \/ 2^16$. The whole interval $[0, 1)$ becomes the integer interval $[0, 65536)$, with $"low"$ starting at $0$ and $"high"$ starting at $65535$ (the largest value we can hold, standing for "just under 1").

To split this integer interval by a symbol whose cumulative range is $[c, c + f)$ out of a total count $T$ (we now use _integer counts_ instead of real probabilities — symbol $s$ has count $f$, and $T$ is the sum of all counts), we compute, with $"range" = "high" - "low" + 1$:
$ "new low" &= "low" + floor("range" times c \/ T), \
  "new high" &= "low" + floor("range" times (c + f) \/ T) - 1. $
These are pure integer operations: a multiply, an integer divide (floor division, which we met as `//` in Chapter 15), an add, a subtract. No floats anywhere.

#gomaths("Floor division and why we never touch a float")[
*Floor division*, written `//` in Python, divides and throws away any remainder, rounding _down_ to the nearest whole number: $17 \/\/ 5 = 3$ (because $5 times 3 = 15 <= 17 < 20$), and $7 \/\/ 2 = 3$. It is the integer cousin of the real division `/`.

Arithmetic coding leans on it because real division would reintroduce the fractions we are trying to escape. By writing every interval split as `low + range * c // T`, the result is _always_ an exact integer, computed identically on every machine. This determinism is not a nicety — it is essential. The decoder must reproduce the encoder's arithmetic _bit for bit_, and floating-point math notoriously rounds differently across hardware and compilers. Integer floor division gives the one thing a codec cannot live without: the encoder and decoder agreeing on every single value, always.
]

Two integers, $L$ and $H$, that keep narrowing — but they live in only $16$ bits, so they cannot narrow forever before colliding. That is where renormalization rescues us.

== Renormalization: shipping the settled bits

Watch what happens to $L$ and $H$ as the interval shrinks. Once the interval is entirely inside the bottom _half_ of the range, $[0, 2^15)$, both $L$ and $H$ have a leading binary digit of $0$ — and crucially, _no future symbol can ever change that_, because the interval only shrinks, never grows or moves out of the half it is in. The leading $0$ is *settled*. So we do three things at once: output a `0` bit, throw that bit away by shifting both $L$ and $H$ left by one (which doubles the interval, refilling the register), and shift a fresh $1$ into the low end of $H$ (keeping it the "all ones below" upper bound). Symmetrically, if the interval is entirely in the _top_ half $[2^15, 2^16)$, both share a leading $1$: output a `1` bit, subtract the half to bring it down, and shift left.

#fig([Renormalization. When the interval sits wholly in the lower half, the top bit is a settled `0`; when wholly in the upper half, a settled `1`. Emit that bit, double the interval (shift left), and continue. This keeps the interval "stretched" across the register so the integers never collapse.], cetz.canvas({
  import cetz.draw: *
  let box(x, lab, col) = {
    rect((x,0),(x+3,2.4), stroke: gray)
    line((x,1.2),(x+3,1.2), stroke: (dash:"dashed", paint: gray))
    content((x+1.5, 2.7))[#lab]
  }
  box(0, [lower half], none)
  rect((0,0),(3,1.2), fill: rgb("#cfe2f3"))
  content((1.5,0.6))[interval]
  content((1.5,1.8))[(top bit 0)]
  box(4.5, [upper half], none)
  rect((4.5,1.2),(7.5,2.4), fill: rgb("#d9ead3"))
  content((6.0,1.8))[interval]
  content((6.0,0.6))[(top bit 1)]
  content((10.0,1.2))[emit bit, then double →]
}))

This is the trick that defeats the infinite-precision objection: every time the interval threatens to get too small to represent, we have just emitted a settled bit and stretched the interval back to full width. The integers never run out of resolution because we keep harvesting and discarding their settled high-order bits as a _bitstream_ — and that bitstream _is_ the compressed output.

== The carry problem (underflow) and the E3 fix

There is one devilish case left, and it is the subtlety that the 1987 paper made famous. What if the interval straddles the exact middle — $L$ is just below $2^15$ and $H$ is just above it — and stays straddling, getting narrower and narrower right around the midpoint? Then $L$ looks like $0 1 1 1 1 dots$ and $H$ looks like $1 0 0 0 0 dots$. They do _not_ share a leading bit, so neither the lower-half nor the upper-half rule fires; yet the interval is shrinking dangerously, converging on the middle from both sides. This is the *underflow* (or *near-convergence*) case, and if you ignore it the integers eventually collide and the coder breaks.

The fix is elegant. When the interval sits in the _middle half_ $[2^14, 3 dot 2^14)$ — straddling the midpoint — we do not yet know whether the settled bit will be a `0` or a `1`, but we know the _next_ bit after it will be the _opposite_. So we delete the second bit (which is doing nothing but pin us near the middle), expand the interval around the midpoint, and remember that we owe one *pending* bit. Concretely: subtract $2^14$ from $L$ and $H$ to recentre, shift left, and increment a counter `pending` of bits we owe. Later, when a real `0` or `1` finally settles and is emitted, we flush the pending bits as its _complement_: emit the settled bit, then emit `pending` copies of the opposite bit. Witten–Neal–Cleary call the three rescaling rules *E1* (lower half), *E2* (upper half), and *E3* (middle straddle); E3 is the one that handles the carry.

#keyidea[
Three renormalization rules keep the integers from collapsing. *E1*: interval in the lower half → emit `0` (plus pending `1`s), double. *E2*: interval in the upper half → emit `1` (plus pending `0`s), double. *E3*: interval straddling the midpoint (middle half) → emit nothing yet, recentre around the midpoint, double, and increment the pending counter. The pending counter is the coder's memory of "a bit is coming but I don't know its value yet"; when the value finally settles, the pending bits are flushed as its complement. Master E1/E2/E3 and you have mastered the only genuinely tricky part of arithmetic coding.
]

#pitfall[
A classic bug: forgetting that *order matters* when flushing pending bits. The pending bits are emitted _after_ the settled bit and as its _opposite_ — emit the settled bit first, then `pending` copies of its complement, then reset `pending` to zero. Reverse the order, or emit the wrong polarity, and the decoder silently drifts off course several symbols later, producing plausible-looking garbage that is maddening to trace back to its true cause. When an arithmetic coder "almost works", suspect the pending-bit logic first.
]

#aside[
The same near-convergence trouble has a beautifully physical analogy in long division you may have done by hand: when you keep getting a quotient digit "right on the boundary" and have to carry, the carry can ripple back through digits you thought were finished. Arithmetic coding's pending-bit counter is exactly a deferred carry — it holds the ripple until the ambiguity resolves, then releases it all at once. Carries that propagate backwards through already-emitted output are the reason naïve implementations are wrong, and the pending counter is the standard cure.
]

== The algorithm, profiled

#algo(
  name: "Arithmetic coding", year: "1976 (practical); 1960s (Elias)",
  authors: "P. Elias (idea); R. Pasco & J. Rissanen (finite precision, 1976); Witten, Neal & Cleary (1987 reference implementation)",
  aim: "Code a whole message as one interval of [0,1), spending exactly −log₂ p bits per symbol with no integer-bit rounding.",
  complexity: "O(n) time for n symbols; a few integer multiply/divide/shift per symbol; O(1) state.",
  strengths: "Reaches the entropy bound to within a fixed per-message overhead; handles fractional bits and extreme skew gracefully; cleanly separates model from coder, so it pairs with any adaptive predictor.",
  weaknesses: "Per-symbol multiply and divide make it slower than table-based codes; the renormalization / carry logic is fiddly and historically bug-prone; encumbered by patents for ~25 years.",
  superseded: "Range coding (byte-wise variant) and Asymmetric Numeral Systems (Chapter 27) for speed; still used directly in CABAC, JPEG 2000, and learned codecs.",
)[
Arithmetic coding is the first coder in this book that genuinely _reaches_ the Chapter 19 floor rather than merely approaching it from a whole-bit distance. Its enduring importance is the clean *model / coder split*: the coder asks the model only for $C(s)$ and $p(s)$ (or integer counts) for each symbol and never cares where they came from, so the same coder serves a static table, an adaptive frequency count, a context model, or — as in Chapter 62 — a neural network predicting the next token.
]

== Range coding: the same idea, byte at a time

If arithmetic coding emits the settled output one _bit_ at a time, *range coding* emits it one _byte_ (or even one _digit in any base_) at a time, and frames the interval as an integer "range" rather than a fraction of $[0,1)$. Mathematically it is the same algorithm; the differences are entirely in the renormalization bookkeeping (you shift out eight bits at a stroke) and a slightly looser handling of the carry, which costs a vanishing fraction of a bit but runs faster on byte-oriented hardware.

#algo(
  name: "Range coding", year: "1979",
  authors: "G. Nigel N. Martin (Video & Data Recording Conference, Southampton, July 1979)",
  aim: "Arithmetic coding reformulated to emit whole bytes and operate on an integer range, for speed and simpler renormalization.",
  complexity: "O(n); one multiply/divide per symbol, byte-wise output.",
  strengths: "Faster byte-at-a-time renormalization; historically believed to sit outside the core IBM binary-coder patents, so it became the pragmatic near-entropy coder of the 1990s–2000s.",
  weaknesses: "A sliver less efficient than bit-exact arithmetic coding because of the coarser carry handling; still needs a multiply/divide per symbol.",
  superseded: "ANS (Chapter 27) for many modern uses, but range coding still drives LZMA (Chapter 31) and others.",
)[
Martin described range coding the same year as Rissanen and Langdon's IBM paper but framed it so differently that, crucially, it appeared to dodge the patent thicket then forming around binary arithmetic coding. That perception — as much as the speed — is why range coding, not "arithmetic coding" by name, became the entropy back-end of *LZMA* (7-Zip, Chapter 31), *PPMd*, and a generation of high-ratio coders. The lesson that the _legal_ status of an algorithm can matter as much as its _mathematical_ status will recur throughout this book.
]

== Binary arithmetic coding: CABAC and the MQ-coder

There is a special case worth its own name. If your alphabet has only _two_ symbols — a `0` and a `1`, called *bins* — then the cumulative table collapses to a single number, the probability of the less-probable bit, and the per-symbol multiply can be replaced by a tiny lookup table. This *binary arithmetic coder* is the workhorse inside modern media codecs: you first _binarize_ everything (turn each syntax element into a string of bits), then feed those bits to the binary coder, each with its own adaptively estimated probability drawn from a _context_ chosen by the bit's surroundings.

#algo(
  name: "CABAC (Context-Adaptive Binary Arithmetic Coding)", year: "2003",
  authors: "Detlev Marpe, Heiko Schwarz, Thomas Wiegand (Fraunhofer HHI), for H.264/AVC",
  aim: "Squeeze video syntax to near-entropy by binarizing every element and coding each bit with a context-selected, adaptively updated probability through a multiply-free binary arithmetic coder.",
  complexity: "O(bits); table-driven state transitions, no per-bit multiply.",
  strengths: "≈ 9–14% bitrate saving over the simpler CAVLC at the same quality; superb adaptation; multiply-free, hardware-friendly core.",
  weaknesses: "Strictly serial (each bit's context depends on previous decisions), so it is hard to parallelize and a throughput bottleneck in high-resolution decoders.",
  superseded: "Refined but not replaced: H.265/HEVC and H.266/VVC (Chapter 53) use evolved CABAC variants.",
)[
CABAC is why your phone's video looks as good as it does at the bitrate it uses. Its sibling, the *MQ-coder*, is the binary arithmetic coder inside *JPEG 2000* (Chapter 43) and is itself a descendant of IBM's patented *Q-coder* and *QM-coder*. All of them share the multiply-free, context-driven, binary core — the most-deployed form of arithmetic coding on Earth, running billions of times a second across the world's screens.
]

#history[
The *patent saga* is the reason most people have never knowingly used arithmetic coding, even though they use CABAC constantly. When *JPEG* was standardised in 1992 it specified _two_ entropy back-ends: a Huffman mode and an arithmetic-coding mode about $5$–$10%$ smaller. But IBM, Mitsubishi, and AT&T held a thicket of patents on the arithmetic-coding variants (notably the QM-coder, US 4,905,297, filed 1988). The Independent JPEG Group's free 1991 library shipped Huffman only, and chronic licensing fear meant virtually no JPEG decoder in the world ever supported the arithmetic mode. The _better_ algorithm was standardised, documented, and effectively unused — for decades — purely because of patents. Most of the core patents expired around 2007; by then the ecosystem had calcified around Huffman, and the saving was lost to history. It is the cleanest cautionary tale in compression: a superior, standardised technique can lose simply because it is legally radioactive. The same dynamic, as we will see in Chapter 27, nearly repeated with ANS.
]

#misconception[Range coding and arithmetic coding are fundamentally different algorithms that just happen to compress similarly.][They are the _same_ algorithm wearing different clothes. Both maintain a narrowing interval and ship out settled high-order digits; range coding ships them a byte at a time and frames the interval as an integer range, while classic arithmetic coding ships them a bit at a time as a fraction of $[0,1)$. The distinction that actually mattered historically was not mathematical but legal — range coding was believed to sit outside the binary-coder patents — and, secondarily, that byte-wise output is faster. Under the hood they reach the same entropy floor by the same interval-narrowing logic.]

== Building it: an integer arithmetic coder for `tinyzip`

Now we turn the theory into the real thing. We are implementing *Step 10* of the project: a new module `tinyzip/arithmetic.py` with an `ArithmeticEncoder` and an `ArithmeticDecoder` that round-trip any `bytes`. They will use the `BitWriter` and `BitReader` we built in Chapter 17 — unchanged, by their exact names — and a tiny *adaptive frequency model* so we need not transmit a probability table.

We will work over a $32$-bit register: $"TOP" = 2^32$. The interval is held as two integers `low` and `high` in $[0, 2^32)$. Three named bounds drive the E1/E2/E3 rules: `HALF` $= 2^31$, `QUARTER` $= 2^30$, and `THREE_Q` $= 3 dot 2^30$.

#gopython("Bit-shift constants and big integers in Python")[
Python integers are *arbitrary precision* — they never overflow, so the $32$-bit arithmetic here is automatic; we just have to _mask_ deliberately when we want to stay in range. We write the power-of-two bounds with the left-shift operator `<<` from Chapter 17: `1 << 32` means $1$ shifted left $32$ places, i.e. $2^32$. So:

```python
TOP     = 1 << 32          # 4294967296
HALF    = 1 << 31          # 2147483648
QUARTER = 1 << 30          # 1073741824
THREE_Q = 3 * QUARTER      # 3221225472
MASK    = TOP - 1          # 0xFFFFFFFF, the low 32 bits
```

`MASK = TOP - 1` is thirty-two `1` bits; writing `x & MASK` keeps only the low $32$ bits of `x`, our way of "pretending" to be a $32$-bit register on top of Python's unbounded integers.
]

First, the *model*: an adaptive frequency table over the $256$ possible byte values plus one extra symbol, `EOF`, that marks end-of-stream so the decoder knows when to stop. Every symbol starts with a count of $1$ (so nothing ever has probability zero — a zero-width slice would be uncodeable), and after coding each symbol we bump its count. This is the simple "add-one" adaptive model; it is a cousin of the Krichevsky–Trofimov estimator from Chapter 23, which adds one-half instead of one.

#project("Step 10 · `arithmetic.py` — the adaptive model")[
Create `tinyzip/arithmetic.py`. Start with the frequency model. It answers exactly the two questions the coder asks: for a symbol, its cumulative start and the total; and, for decoding, which symbol owns a given scaled value.

```python
# tinyzip/arithmetic.py — integer arithmetic coding for tinyzip.
from tinyzip.bitio import BitWriter, BitReader

EOF = 256                       # one past the 256 byte values: end marker
NSYM = 257                      # 256 bytes + EOF

class FrequencyModel:
    """Adaptive 'add-one' counts over 257 symbols (0..255 and EOF)."""

    def __init__(self) -> None:
        self.freq: list[int] = [1] * NSYM     # every symbol starts at 1
        self.total: int = NSYM                # running sum of freq

    def cumulative(self, sym: int) -> tuple[int, int, int]:
        """Return (cum_low, cum_high, total) for symbol `sym`."""
        low = sum(self.freq[:sym])            # counts strictly before sym
        return low, low + self.freq[sym], self.total

    def find(self, scaled: int) -> int:
        """Return the symbol whose cumulative slice contains `scaled`."""
        cum = 0
        for sym in range(NSYM):
            if cum + self.freq[sym] > scaled:
                return sym
            cum += self.freq[sym]
        raise ValueError("scaled value out of range")

    def update(self, sym: int) -> None:
        """Make `sym` likelier next time, keeping totals bounded."""
        self.freq[sym] += 32                  # a brisk learning rate
        self.total += 32
        if self.total >= QUARTER:             # rescale before it gets large
            self.total = 0
            for s in range(NSYM):
                self.freq[s] = (self.freq[s] >> 1) | 1   # halve, keep >= 1
                self.total += self.freq[s]
```

`cumulative(sym)` returns the half-open count range $[C(s), C(s)+f(s))$ and the total $T$ — the integer version of "where the slice starts and how wide it is." `find(scaled)` is the decoder's inverse: given a value scaled into $[0, T)$, it walks the table to find which symbol's slice contains it. `update` adds $32$ to the chosen symbol's count (a faster adaptation than $+1$) and, to stop the totals growing without bound, periodically *halves* every count — the `>> 1` shift — while OR-ing in a `1` so no count ever falls to zero. The constant `QUARTER` is defined just below with the coder bounds.
]

The model is deliberately simple and shared by both encoder and decoder, which is the whole point: because both sides run the _identical_ adaptive update in lock-step, the decoder always has the same probability table the encoder used, _without a single byte of table being transmitted_. Now the encoder, with the E1/E2/E3 renormalization in full.

#project("Step 10 · `arithmetic.py` — the encoder")[
Add the bounds and the encoder to the same file.

```python
TOP     = 1 << 32
HALF    = 1 << 31
QUARTER = 1 << 30
THREE_Q = 3 * QUARTER
MASK    = TOP - 1

class ArithmeticEncoder:
    def __init__(self) -> None:
        self.low = 0
        self.high = MASK              # 0xFFFFFFFF: the full interval
        self.pending = 0              # bits we owe (E3 underflow)
        self.out = BitWriter()

    def _emit(self, bit: int) -> None:
        """Emit a settled bit, then the pending bits as its complement."""
        self.out.write_bit(bit)
        while self.pending > 0:
            self.out.write_bit(bit ^ 1)
            self.pending -= 1

    def encode(self, data: bytes) -> bytes:
        model = FrequencyModel()
        for byte in data:
            self._encode_symbol(model, byte)
        self._encode_symbol(model, EOF)        # mark the end
        # flush: emit a final bit that pins a point inside the interval
        self.pending += 1
        self._emit(1 if self.low >= QUARTER else 0)
        return self.out.flush()

    def _encode_symbol(self, model: "FrequencyModel", sym: int) -> None:
        cum_low, cum_high, total = model.cumulative(sym)
        span = self.high - self.low + 1
        self.high = self.low + span * cum_high // total - 1
        self.low  = self.low + span * cum_low  // total
        model.update(sym)
        # renormalize: E1 / E2 / E3
        while True:
            if self.high < HALF:                       # E1: lower half
                self._emit(0)
            elif self.low >= HALF:                      # E2: upper half
                self._emit(1)
                self.low  -= HALF
                self.high -= HALF
            elif self.low >= QUARTER and self.high < THREE_Q:  # E3: middle
                self.pending += 1
                self.low  -= QUARTER
                self.high -= QUARTER
            else:
                break                                   # nothing settled
            self.low  = (self.low  << 1) & MASK
            self.high = ((self.high << 1) | 1) & MASK   # shift 1 into high
```

This is the entire encoder, and every line maps onto something we explained. `_encode_symbol` narrows `[low, high]` to the symbol's count-slice using integer floor division (`//`), updates the model, then renormalizes in a loop. *E1* fires when the whole interval is below `HALF` (top bit settled `0`); *E2* when it is at or above `HALF` (top bit settled `1`), subtracting `HALF` to bring it down; *E3* — the underflow case — when it straddles the midpoint inside the middle half, where we record a pending bit and recentre by subtracting `QUARTER`. After any of the three, we double the interval with a left shift, masking to $32$ bits and shifting a `1` into the bottom of `high`. The final flush emits one more bit (plus its pending complement) to nail down a point inside the surviving interval.
]

Watch the symmetry: the decoder is this same machine running forward, but instead of _emitting_ settled bits it _reads_ them into a `code` register and compares the register against the interval to recover each symbol.

#project("Step 10 · `arithmetic.py` — the decoder")[
Add the decoder, then a one-line public API. It mirrors the encoder bit-for-bit.

```python
class ArithmeticDecoder:
    def __init__(self, payload: bytes) -> None:
        self.low = 0
        self.high = MASK
        self.inp = BitReader(payload)
        self.code = 0
        for _ in range(32):                  # prime the 32-bit code register
            self.code = (self.code << 1) | self._next_bit()

    def _next_bit(self) -> int:
        try:
            return self.inp.read_bit()
        except EOFError:
            return 0                          # past the end: feed zeros

    def decode(self) -> bytes:
        model = FrequencyModel()
        out = bytearray()
        while True:
            span = self.high - self.low + 1
            total = model.total
            # which count-slot does `code` fall in?
            scaled = ((self.code - self.low + 1) * total - 1) // span
            sym = model.find(scaled)
            if sym == EOF:
                return bytes(out)
            out.append(sym)
            cum_low, cum_high, _ = model.cumulative(sym)
            self.high = self.low + span * cum_high // total - 1
            self.low  = self.low + span * cum_low  // total
            model.update(sym)
            while True:                        # SAME E1/E2/E3, but read bits
                if self.high < HALF:
                    pass
                elif self.low >= HALF:
                    self.low  -= HALF; self.high -= HALF; self.code -= HALF
                elif self.low >= QUARTER and self.high < THREE_Q:
                    self.low  -= QUARTER; self.high -= QUARTER
                    self.code -= QUARTER
                else:
                    break
                self.low  = (self.low  << 1) & MASK
                self.high = ((self.high << 1) | 1) & MASK
                self.code = ((self.code << 1) | self._next_bit()) & MASK

def encode(data: bytes) -> bytes:
    return ArithmeticEncoder().encode(data)

def decode(payload: bytes) -> bytes:
    return ArithmeticDecoder(payload).decode()
```

The decoder primes a $32$-bit `code` register from the first thirty-two payload bits, then repeats: compute which count-slot `code` occupies with the inverse scaling `((code − low + 1)·total − 1) // span`, ask the model `find` for the owning symbol, stop on `EOF`, otherwise emit the byte, narrow the interval _exactly as the encoder did_, update the _same_ model, and renormalize while _reading_ fresh bits into `code`. Because the renormalization mirrors the encoder's E1/E2/E3 step for step and the model updates identically, `code` always sits inside `[low, high]`, and the symbol it selects is always the one the encoder put there.
]

The one line in that decoder worth lingering on is the inverse scaling, `scaled = ((code - low + 1) * total - 1) // span`. It is just the encoder's narrowing run backwards. The encoder placed `code` somewhere inside `[low, high]`; its offset from `low` is `code - low`, a number between $0$ and `span - 1`. We want to know what _fraction_ of the way across the interval that is, expressed on the model's count scale $[0, "total")$ rather than on the raw $[0, "span")$ scale — because that is the scale `model.find` walks. So we map the offset through the same `· total // span` ratio the encoder used to lay the slices down. The `+ 1` and `- 1` are the careful rounding that keeps `scaled` strictly inside the slot the encoder chose even at the slice boundaries; drop them and a `code` sitting exactly on a boundary can round into the neighbouring symbol and the decode derails. It is the exact algebraic inverse of `low + span * cum_low // total`, no more and no less.

#note[
The boundary rounding (`+ 1`/`- 1`) and the renormalization order must match the encoder's _to the bit_. This is why arithmetic coders are traditionally shipped as a tested encoder/decoder _pair_, like the Witten–Neal–Cleary C in their 1987 paper, rather than re-derived from scratch: a single off-by-one in this formula produces a codec that round-trips short inputs by luck and corrupts long ones, the worst kind of bug to find. When you write your own, test it on thousands of random `bytes` of every length, not just on `b"ABRACADABRA"`.
]

#pyrecall[
The self-test reuses two tools from Chapter 16: `bytearray`, the _mutable_ cousin of `bytes` that lets the decoder `append` bytes one at a time before freezing the result with `bytes(out)`; and `collections.Counter`, which tallies how often each byte value appears in one call (`Counter(data)`), giving us the frequency table the entropy formula needs.
]

#project("Step 10 · `arithmetic.py` — the round-trip self-test")[
Finally, the self-test every `tinyzip` codec ships with — `decode(encode(x)) == x` — plus a peek at how close we land to the entropy floor on skewed data.

```python
if __name__ == "__main__":
    import math
    from collections import Counter

    def entropy_bits(data: bytes) -> float:
        n = len(data)
        counts = Counter(data)
        return -sum(c * math.log2(c / n) for c in counts.values())

    # 1) round-trip a variety of inputs
    for sample in [b"", b"A", b"ABRACADABRA",
                   b"the quick brown fox" * 20,
                   bytes([0]) * 990 + bytes([1]) * 10]:   # 99% zeros
        packed = encode(sample)
        assert decode(packed) == sample, "round-trip FAILED"
    print("All round-trips OK.")

    # 2) compare to the entropy floor on the skewed coin
    coin = bytes([0]) * 990 + bytes([1]) * 10
    packed = encode(coin)
    print(f"input   : {len(coin)} bytes")
    print(f"entropy : {entropy_bits(coin)/8:8.2f} bytes (floor)")
    print(f"arith   : {len(packed):8d} bytes")
```

Running `python tinyzip/arithmetic.py` prints something close to:

```
All round-trips OK.
input   : 1000 bytes
entropy :    10.10 bytes (floor)
arith   :       22 bytes
```

The empty string, a single byte, a repetitive sentence, and the $99%$-zeros coin all survive the round-trip exactly. And on the skewed coin — Huffman's nightmare — the arithmetic coder lands at about $22$ bytes against an entropy floor of $approx 10$ bytes. The gap is the adaptive model _warming up_: it begins believing every byte equally likely and must _learn_ the $99\/1$ skew over the first stretch of data, mispricing those early symbols; a static model told the true probabilities up front would land far closer to the floor. Even so, Huffman would have spent $1000$ bits $= 125$ bytes here — so the fractional-bit coder is already nearly $6×$ smaller, and on longer skewed streams the warm-up cost amortises away toward the entropy floor.
]

#pitfall[
The decoder _must_ run the exact same `model.update` calls in the exact same order as the encoder, because the model is adaptive and shared only by reconstruction, never by transmission. Add a stray update, skip one, or change the learning-rate constant on one side, and the two tables drift apart; the decoder then narrows to the wrong interval and the output diverges — usually several symbols _after_ the real mistake, which is what makes such bugs so hard to localise. Golden rule: encoder and decoder must be byte-for-byte mirror images in both their arithmetic and their model updates.
]

This module slots straight into the `tinyzip` container from Chapter 17: the `encode`/`decode` here produce and consume the `bytes` _payload_, and `container.write("file.tz", method, encode(data), original_len=len(data))` wraps it with the magic/version/method/size header — or `container.write_checked(...)`, the Step 5 variant, to add the CRC-32 footer. Here `method` is arithmetic coding's own slot in the container's method byte (Chapter 24's Huffman claimed `method="huffman"` before it; this is the next one along). It is now a genuine `method="arithmetic"` codec, the first in the project to actually _reach_ the entropy floor.

== Why it really reaches the floor (a short proof)

We claimed arithmetic coding's overhead is a fixed constant for the _whole_ message. Let us prove the bound that makes the claim precise, using only the logarithm facts from Chapter 7 and the source-coding view from Chapter 19.

#theorem("Arithmetic coding overhead")[
For a message of $n$ symbols whose model assigns it total probability $P = product_(i=1)^n p_i$ (so $P$ is the width of the final interval), an arithmetic coder emits at most $-log_2 P + 2$ bits. Hence its average length per symbol exceeds the entropy by at most $2\/n$ bits, which tends to $0$ as $n -> infinity$.
]

#proof[
The encoder's final interval $[L, H)$ has width $W = H - L = P$ (each symbol multiplies the width by its probability; renormalization only rescales, it never changes the _product_ of probabilities the interval represents). To transmit the message it is enough to output a binary fraction $x$ that lies inside $[L, H)$, because the decoder, replaying the same interval splits, will recover every symbol from any such $x$.

How short can such an $x$ be? Take the value $x = ceil(L dot 2^b) \/ 2^b$ — round $L$ _up_ to the nearest multiple of $2^(-b)$. This $x$ has at most $b$ bits after the point. It satisfies $x >= L$ by construction, and $x < L + 2^(-b)$ because rounding up moves us by less than one grid step. So $x$ lands inside $[L, H)$ provided the grid step does not overshoot the interval, i.e. provided $2^(-b) <= W$. Solving $2^(-b) <= W$ gives $b >= -log_2 W = -log_2 P$.

Choosing the smallest such integer $b = ceil(-log_2 P) <= -log_2 P + 1$, plus at most one extra bit for the rounding-up alignment, the coder emits at most $-log_2 P + 2$ bits. Since $-log_2 P = sum_i -log_2 p_i$ is the message's total surprisal, and dividing by $n$ gives an average of at most $(sum_i -log_2 p_i)\/n + 2\/n$, the per-symbol cost is within $2\/n$ bits of the model's entropy. The "$+2$" is paid once for the whole message; per symbol it vanishes.
]

So arithmetic coding does not merely _approach_ the Chapter 19 floor in some hand-wavy limit — it provably sits within two bits of it for any message at all, with the gap per symbol shrinking like $1\/n$. The remaining distance to true optimality is then entirely the _model's_ fault, never the coder's: if your $p_i$ match the source, you hit entropy; sharpen the model (Chapters 23, 33, 62) and the same coder rides it down. That is the deep reason every modern statistical compressor keeps an arithmetic-style coder at its core and spends its ingenuity on the model.

#scoreboard(caption: "the 1,000-byte skewed coin (990 zeros, 10 ones)",
  [Raw], [1000], [1.00×], [no compression],
  [Huffman (Ch. 24)], [125], [8.0×], [1 bit/symbol — stuck at the integer floor],
  [Arithmetic (this chapter)], [22], [45×], [fractional bits paid; ≈10 B floor, rest is model warm-up],
)

On a source this skewed the difference between "whole bits" and "fractional bits" is the difference between $125$ bytes and $22$ — nearly $6×$, and it would be a full order of magnitude with a static model told the true odds — because the dominant symbol deserves a tiny fraction of a bit that Huffman simply cannot spend. On ordinary English text the gap is far smaller (a few percent), which is exactly why Huffman survived for decades: its weakness only screams on skewed or near-deterministic sources. But those sources are everywhere once you add a good _model_ — a sharp predictor makes _every_ symbol near-certain, and that is precisely the regime where arithmetic coding wins and Huffman cannot follow.

#takeaways((
  [Arithmetic coding represents the _whole message_ as one sub-interval of $[0,1)$, of width equal to the product of the symbol probabilities, and names a point inside it in $approx -log_2("width")$ bits — reaching the entropy floor with no per-symbol bit rounding.],
  [Encoding narrows `[low, high]` by each symbol's cumulative slice; decoding asks which slice the received number falls in. Both need only two numbers per symbol: the cumulative start $C(s)$ and the count/width $p(s)$.],
  [_Renormalization_ keeps it in fixed-precision integers: when the interval settles into the lower half (E1) or upper half (E2), emit the settled bit and double; the _underflow_ straddle (E3) defers a _pending_ bit until its value is known.],
  [It provably costs at most $-log_2 P + 2$ bits for the whole message, so the per-symbol overhead vanishes as $1\/n$ — the residual gap to optimal is the model's, not the coder's.],
  [_Range coding_ is the same algorithm emitting bytes (LZMA, PPMd); _binary arithmetic coding_ (CABAC in H.264/HEVC/VVC, the MQ-coder in JPEG 2000) is its most-deployed form.],
  [A patent thicket kept the arithmetic mode out of JPEG for a generation, handing the field to Huffman — a lesson that the legal status of an algorithm can decide its fate as surely as its math.],
))

== Exercises

#exercise("26.1", 1)[
Using the table $p(A)=0.5, p(B)=0.3, p(C)=0.2$ with $C(A)=0, C(B)=0.5, C(C)=0.8$, encode the message `AC` by hand. Give the final interval $[L, H)$ and one binary fraction inside it.
]
#solution("26.1")[
Start $[0,1)$, width $1$. Symbol `A`: new interval $[0 + 1·0, space 0 + 1·0.5) = [0, 0.5)$, width $0.5$. Symbol `C`: within $[0,0.5)$, `C`'s slice is $[0.8, 1.0)$ of it, so $L = 0 + 0.5·0.8 = 0.4$, $H = 0 + 0.5·1.0 = 0.5$; final interval $[0.4, 0.5)$, width $0.1$. A convenient binary fraction inside it is $0.4375 = 0.0111_2$ (since $0.25+0.125+0.0625$), i.e. the bits `0111`; $0.5 = 0.1_2$ is _not_ inside because the interval excludes its right end. (Ideal cost $-log_2 0.1 approx 3.32$ bits.)
]

#exercise("26.2", 1)[
A decoder uses the same table and receives the number $0.27$. Decode the first _three_ symbols by hand, showing the rescaled value at each step.
]
#solution("26.2")[
Step 1: $0.27 in [0,0.5)$ → `A`. Rescale: $(0.27-0)\/0.5 = 0.54$. Step 2: $0.54 in [0.5,0.8)$ → `B`. Rescale: $(0.54-0.5)\/0.3 = 0.1333$. Step 3: $0.1333 in [0,0.5)$ → `A`. First three symbols: `A`, `B`, `A`.
]

#exercise("26.3", 2)[
Explain in your own words why a symbol of probability $0.99$ costs about $0.0145$ bits in arithmetic coding but a whole bit in any prefix (Huffman) code. What feature of arithmetic coding makes the fractional cost possible?
]
#solution("26.3")[
$-log_2 0.99 approx 0.0145$ bits is the ideal cost. A prefix code assigns each symbol a fixed codeword of a _whole number_ of bits, and the shortest possible codeword is one bit, so $0.99$-probable symbol must pay at least $1$ bit — a $69×$ overpayment. Arithmetic coding never assigns a per-symbol codeword; it multiplies the running interval width by $0.99$, shrinking it by only $-log_2 0.99 approx 0.0145$ bits' worth. Because the cost is the _total_ $-log_2("width")$ paid once at the end, fractional per-symbol contributions accumulate and are amortised across the whole message, so a near-certain symbol genuinely contributes a tiny fraction of a bit.
]

#exercise("26.4", 2)[
In the integer coder, the E3 (underflow) rule fires when `QUARTER <= low` and `high < THREE_Q`. Describe in words the state of the interval when this happens, and explain why we cannot yet output a bit — but _can_ safely delete one.
]
#solution("26.4")[
The interval straddles the midpoint `HALF`, sitting inside the middle half $[2^30, 3·2^30)$: `low` is in the upper part of the lower half and `high` is in the lower part of the upper half. The leading bits of `low` and `high` _differ_ (`low` starts `01…`, `high` starts `10…`), so the top bit is not yet settled and no output bit can be produced. But whatever that top bit turns out to be, the _second_ bit will be its opposite — the interval is pinned near the middle — so the second bit carries no independent information yet. We delete it by subtracting `QUARTER` and doubling, recording a _pending_ bit; when the top bit finally settles to $b$, we emit $b$ followed by the pending bits as $overline(b)$ (its complement).
]

#exercise("26.5", 2)[
Why does the `FrequencyModel` initialise every count to $1$ rather than $0$? What goes wrong, mathematically and in the code, if some symbol has count $0$ when the encoder meets it?
]
#solution("26.5")[
A count of $0$ gives the symbol probability $0$, hence a _zero-width_ slice $[C(s), C(s))$ — there is no number to put inside it, so the symbol is literally uncodeable; equivalently its ideal length is $-log_2 0 = infinity$ bits. In the code, `cum_low == cum_high`, so after narrowing, `high` becomes less than `low` and the interval is empty (or inverted), corrupting all further coding. Initialising every count to $1$ (the "add-one" / Laplace rule, a coarse cousin of the Krichevsky–Trofimov $+1\/2$ from Chapter 23) guarantees every symbol always has positive probability, so any byte can be coded even the first time it appears.
]

#exercise("26.6", 2)[
The chapter's coder transmits no probability table, yet the decoder reconstructs the same probabilities the encoder used. How is that possible? What is the one rule the two sides must obey for it to work?
]
#solution("26.6")[
Both sides start from the _identical_ initial model (all counts $1$) and apply the _identical_ adaptive update after each symbol, in the same order. The encoder updates _after_ coding a symbol; the decoder updates _after_ decoding the same symbol; so at every step the decoder's table matches the table the encoder used to code the _next_ symbol. No table needs to be sent because it is recomputed in lock-step on both sides. The one rule: encoder and decoder must perform exactly the same model updates (same increments, same rescaling, same order) — any divergence desynchronises the tables and the decode diverges.
]

#exercise("26.7", 3)[
Range coding and classic bit-wise arithmetic coding are "the same algorithm." Yet range coding became the entropy back-end of LZMA while the JPEG arithmetic mode languished unused. Give the two distinct reasons (one technical, one not) and explain which mattered more historically.
]
#solution("26.7")[
Technical reason: range coding emits output a _byte_ at a time and frames the interval as an integer range, giving faster renormalization on byte-oriented hardware (at the cost of a vanishing fraction of a bit). Non-technical reason: range coding, as formulated by Martin (1979), was widely believed to fall _outside_ the IBM/Mitsubishi/AT&T patents covering binary arithmetic coders (e.g. the QM-coder, US 4,905,297), whereas JPEG's arithmetic mode was thought to be encumbered. Historically the _patent_ status mattered more: the JPEG arithmetic mode was standardised and documented but went essentially unused for decades purely from licensing fear, while range coding was adopted freely in LZMA, 7-Zip, and many others. Speed was a bonus; legal freedom was decisive.
]

#exercise("26.8", 3)[
Modify the self-test idea (no need to run it) to estimate the _per-byte_ overhead of the coder versus the entropy floor as the message length $n$ grows. Predict, from the chapter's theorem, how that overhead should behave, and explain what would happen to the measured overhead if you made the model's learning rate (the `+32`) much larger or much smaller.
]
#solution("26.8")[
Encode the same _source_ at increasing lengths $n$ (e.g. $n = 10^2, 10^3, 10^4, 10^5$ of the skewed coin) and plot $("bits emitted")\/n - H$ against $n$. By the theorem the coder overhead is at most $2\/n$ bits total over entropy from the _coder_, so it should fall like $1\/n$ toward zero — the curve approaches the model's cross-entropy. The remaining gap is the _model's_ learning cost: too small a learning rate makes the adaptive table slow to track the true $99\/1$ skew, so early symbols are mispriced and overhead stays higher for longer; too large a learning rate over-reacts to noise and to the periodic halving, also raising overhead and risking instability. There is an intermediate rate that minimises total bits — a recurring theme: the coder is near-optimal, so all real tuning is in the model.
]

== Further reading

- *Witten, I. H., Neal, R. M. & Cleary, J. G. (1987).* _Arithmetic Coding for Data Compression._ Communications of the ACM 30(6), 520–540. The canonical, supremely readable reference implementation — read this if you read nothing else. #link("https://dl.acm.org/doi/10.1145/214762.214771")[ACM] (open copy in `papers/witten-neal-cleary-1987-arithmetic-coding.pdf`).
- *Rissanen, J. & Langdon, G. G. (1979).* _Arithmetic Coding._ IBM Journal of Research and Development 23(2), 149–162. The paper that named and systematised the field. #link("https://ieeexplore.ieee.org/document/5390511")[IEEE]
- *Pasco, R. (1976).* _Source Coding Algorithms for Fast Data Compression._ PhD thesis, Stanford. The independent finite-precision breakthrough.
- *Moffat, A., Neal, R. M. & Witten, I. H. (1998).* _Arithmetic Coding Revisited._ ACM Transactions on Information Systems 16(3), 256–294. The careful, low-overhead modern integer formulation. #link("https://dl.acm.org/doi/10.1145/290159.290162")[ACM]
- *Marpe, D., Schwarz, H. & Wiegand, T. (2003).* _Context-Based Adaptive Binary Arithmetic Coding in the H.264/AVC Video Compression Standard._ IEEE Transactions on Circuits and Systems for Video Technology 13(7), 620–636. The most-deployed arithmetic coder on Earth. #link("https://ieeexplore.ieee.org/document/1218195")[IEEE]
- *Martin, G. N. N. (1979).* _Range Encoding: An Algorithm for Removing Redundancy from a Digitised Message._ Video & Data Recording Conference, Southampton. The origin of range coding.

#bridge[
Arithmetic coding reaches the entropy floor — but pays for it with a multiply and a divide per symbol, making it the _slow_ champion. For thirty years the field believed you had to choose: Huffman's speed _or_ arithmetic's ratio, never both. In Chapter 27 we meet the algorithm that finally broke that trade-off — *Asymmetric Numeral Systems (ANS)*, Jarek Duda's 2009–2013 breakthrough, which delivers arithmetic-coding compression at roughly Huffman speed by encoding the whole message into a single growing _number_ and precomputing the work into a lookup table. We will see why zstd, LZFSE, and JPEG XL all adopted it within a few years — and how it, too, nearly fell into a patent trap.
]
