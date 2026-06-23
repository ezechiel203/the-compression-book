#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Sequences, Sums, and a Gentle Calculus

#epigraph[Mathematics is the art of giving the same name to different things.][Henri Poincaré]

Here is a magic trick that is not magic. Take a sheet of paper. Tear it in half and keep one piece. Tear that piece in half and keep one. Keep going forever. The pieces you have kept are $1/2$, then $1/4$, then $1/8$, then $1/16$, on and on — each one half the last. Now add them all up. Your gut says: infinitely many positive numbers, so the total must be infinite, right? Wrong. The total is exactly $1$ — one whole sheet of paper, the one you started with. An *infinite* sum of *positive* numbers can land on a *finite*, exact answer. That single, slightly unsettling fact is the engine behind half the formulas in this book.

We have been writing IOUs for two chapters. When we said a geometric source has expected value $1/p$, we summed an infinite list and just *asserted* the answer. When we found where a coin's variance peaks, we waved at "the slope is zero there." When we promised that entropy is a smooth, bending floor, we leaned on a property of curves we never defined. This chapter pays every debt. It is the last purely-mathematical stop before we meet Claude Shannon, and it hands us three tools we will use for the rest of the book:

- a clean shorthand for adding and multiplying long lists (the signs $sum$ and $product$), so the formulas to come read like sentences instead of hieroglyphics;
- the idea of a *limit* — what it means to chase a process forever and ask where it is heading — which tames infinite sums like the torn paper;
- the bare beginnings of *calculus*: the *slope* of a curve, why "slope zero" finds peaks and valleys, and how a thing called a *gradient* lets a machine feel its way downhill in the dark. That last idea, dressed up, is exactly how every neural compressor in Volume IV is trained, and how every modern video encoder decides where to spend its bits.

None of this requires talent you do not have. It requires pictures, tiny numbers, and patience. We will supply all three.

#recap[
In *Chapter 7* we made logarithms ordinary: $log_2 8 = 3$ because $2^3 = 8$, and a bit is just a logarithm. *Chapter 8* taught us to count, and introduced the summation sign $sum$ in passing. *Chapter 9* built probability from coins and dice. *Chapter 10* turned outcomes into numbers (random variables), and defined the *expectation* $EE[X] = sum_x x dot p(x)$ — a probability-weighted average that *is* the average cost of a code — together with *variance*, the spread around that average. Along the way Chapter 10 left three explicit IOUs: the infinite *geometric series* behind $EE[X] = 1\/p$, the meaning of a *slope* that locates where variance peaks, and the gentle *bending* of the logarithm. This chapter settles all three, and stocks the toolbox for *Chapter 12* (vectors and matrices) and the information theory of *Chapters 18–23*.
]

#objectives((
  [Read and write _summation_ ($sum$) and _product_ ($product$) notation fluently, and convert between a sum and a loop,],
  [Recognise an _arithmetic_ and a _geometric_ sequence, and sum a geometric series — including the infinite case — to a closed form,],
  [Explain what a _limit_ is in plain words and use it to make sense of "infinitely many pieces adding to a finite total,"],
  [Read the _slope_ of a curve as a rate of change, and compute the _derivative_ of simple functions with three basic rules,],
  [Use "the derivative is zero at a peak or valley" to _optimise_ — to find the input that minimises or maximises a quantity,],
  [Explain what a _partial derivative_ and a _gradient_ are, and how _gradient descent_ walks downhill to a minimum,],
  [Connect every one of these tools to a concrete compression task you will meet later in the book.],
))

== The signs that add and multiply long lists

Compression formulas are mostly bookkeeping over an alphabet: "for every symbol, do a little arithmetic, then combine." Written out in full, that bookkeeping is unreadable. Mathematicians long ago agreed on two compact signs for it, and once they click you will never want to go back.

=== Sigma: the summation sign

The capital Greek letter sigma, written $sum$, means *add these up*. It is a loop frozen into a single symbol. Below it you write where the counter starts; above it, where the counter stops; to the right, the recipe for each term.

$ sum_(i=1)^(5) i = 1 + 2 + 3 + 4 + 5 = 15. $

Read that aloud as "the sum, for $i$ from 1 to 5, of $i$." The letter $i$ is the *index* — a counter that ticks up one step at a time and then vanishes once the adding is done. It is private to the sum; you could rename it $k$ or $j$ and nothing changes. We met this sign briefly while counting in Chapter 8; here we make it permanent.

The recipe can be anything. If you have a list of numbers $x_1, x_2, x_3$ you write their total as $sum_(i=1)^(3) x_i$. If each term is a probability times a value, you get the most important sum in the book:

$ sum_(i=1)^(n) p_i x_i = p_1 x_1 + p_2 x_2 + dots.h + p_n x_n. $

That is the expectation from Chapter 10, now in its natural notation. When the range is obvious — "over every symbol $s$ in the alphabet" — we get lazy and write $sum_s$ with nothing above or below, meaning "add over all of them."

#gomaths("Reading and manipulating $sum$")[
Three habits make $sum$ effortless.

*Unrolling.* To understand any $sum$, write out its first two terms, a "$dots.h$", and its last term. For instance $sum_(k=0)^(n) 2^k = 2^0 + 2^1 + dots.h + 2^n = 1 + 2 + 4 + dots.h + 2^n$. (Notice the counter can start at $0$.)

*Pulling out constants.* If every term shares a common factor $c$ that does not depend on the index, it slides outside: $sum_(i=1)^(n) c dot x_i = c sum_(i=1)^(n) x_i$. Adding three copies of $(2 dot x_i)$ is the same as doubling the sum of three $x_i$. This single move untangles dozens of derivations later.

*Splitting.* A sum of two things is two sums: $sum_i (a_i + b_i) = sum_i a_i + sum_i b_i$. This is just "you can add a column of pairs by adding each column separately." It is exactly why expectation is *linear*, the property Chapter 10 used so freely.

A handy closed form we will reuse: the first $n$ whole numbers add to $sum_(i=1)^(n) i = (n(n+1))/2$. Check it at $n=5$: $(5 dot 6)/2 = 15$. The young Carl Friedrich Gauss reputedly found this in seconds as a schoolboy by pairing $1+100$, $2+99$, … — fifty pairs each summing to $101$.
]

#gopython("A $sum$ is a `for` loop (and Python's `sum`)")[
Mathematics and code agree perfectly here. The sum $sum_(i=1)^(5) i$ is a loop that accumulates a running total:

```python
total = 0
for i in range(1, 6):     # range(1, 6) yields 1, 2, 3, 4, 5
    total = total + i
print(total)              # 15
```

`range(1, 6)` produces the integers from 1 up to *but not including* 6 — Python's universal "start, stop" convention, which trips up every beginner once. The variable `total` starts at the sum's empty value, `0`, exactly as a $sum$ with no terms equals $0$.

Because this pattern is everywhere, Python gives you the built-in `sum`, and a *comprehension* to build the list of terms inline:

```python
print(sum(i for i in range(1, 6)))            # 15
probs  = [0.5, 0.3, 0.2]
values = [1,   2,   3]
ev = sum(p * x for p, x in zip(probs, values))   # 0.5*1 + 0.3*2 + 0.2*3
print(ev)                                          # 1.7  -- an expectation!
```

`zip` walks two lists in lockstep, handing you matched pairs `(p, x)`. The expression `p * x for p, x in zip(...)` is a *generator*: it produces each product on demand, and `sum` adds them. That one line is a literal transcription of $sum_i p_i x_i$ — the same expectation we will compute for every code in the book.
]

=== Pi: the product sign

Sigma's twin is the capital Greek letter pi, $product$, which means *multiply these together* instead of adding. Same grammar — start below, stop above, recipe to the right:

$ product_(i=1)^(4) i = 1 times 2 times 3 times 4 = 24. $

That particular product, "multiply the whole numbers from 1 to $n$," is so common it has its own name and symbol: the *factorial*, written $n!$. So $4! = 24$. We used factorials when counting arrangements in Chapter 8; now you can see $n! = product_(i=1)^(n) i$.

Why will we need products in a compression book? Because the probability of a whole *message* — a string of symbols drawn independently — is the *product* of the symbols' individual probabilities. If a file is the three independent symbols $s_1, s_2, s_3$ with probabilities $p_1, p_2, p_3$, the chance of seeing exactly that file is

$ P("file") = p_1 times p_2 times p_3 = product_(i=1)^(3) p_i. $

This product is the beating heart of every statistical compressor: a model that assigns a probability to each next symbol assigns, by multiplication, a probability to the entire file — and (as Chapter 18 will reveal) the ideal number of bits to store the file is the logarithm of one over that product.

#keyidea[
Logarithms turn $product$ into $sum$. Recall from Chapter 7 that $log(a times b) = log a + log b$. So the logarithm of a giant product of probabilities becomes a friendly *sum* of logarithms:
$ log product_(i=1)^(n) p_i = sum_(i=1)^(n) log p_i. $
This is not a footnote — it is *the* reason information theory measures everything in bits (logarithms). Multiplying thousands of tiny probabilities would underflow any computer to zero; adding their logarithms is stable and exact. Every real compressor works in log-space for precisely this reason. Hold onto this; it returns in force in Chapter 18.
]

#checkpoint[Write "the product of $(1 - p_i)$ for $i$ from 1 to $n$" in $product$ notation, and say in words what event it computes if each $p_i$ is the probability that symbol $i$ appears.][It is $product_(i=1)^(n) (1 - p_i)$. Since $1 - p_i$ is the probability that symbol $i$ does *not* appear, and the symbols are independent, the product is the probability that *none* of them appears at all.]

== Sequences: lists that march

A *sequence* is just an ordered list of numbers, possibly endless: a first term, a second, a third, forever. We write a generic sequence as $a_1, a_2, a_3, dots.h$, and call $a_n$ "the $n$-th term." Sequences are how we describe anything that proceeds step by step — the sizes of the torn paper pieces, the partial totals as a sum grows, the shrinking error of a compressor as it learns. Two shapes of sequence appear constantly, and they are worth naming.

#definition("Arithmetic and geometric sequences")[
A sequence is *arithmetic* if you get each term by *adding* a fixed step $d$ to the previous one: $a, a+d, a+2d, dots.h$. Example: $3, 7, 11, 15, dots.h$ (step $d = 4$). The terms grow in a straight line.

A sequence is *geometric* if you get each term by *multiplying* the previous one by a fixed ratio $r$: $a, a r, a r^2, a r^3, dots.h$. Example: $1, 1\/2, 1\/4, 1\/8, dots.h$ (ratio $r = 1\/2$) — our torn paper. The terms grow (or shrink) by a constant *factor*, which is the signature of exponential behaviour from Chapter 7.
]

The distinction matters because their *sums* behave completely differently, and the geometric one is the IOU we owe Chapter 10.

=== Summing a geometric series

Add up the first $n$ terms of a geometric sequence and you get a *geometric series*. There is a beautiful closed-form shortcut, and the trick to derive it is worth seeing once because it shows up disguised in arithmetic coding and in the analysis of hash tables.

#theorem("Finite geometric series")[
For any ratio $r != 1$ and any starting value $a$,
$ S_n = a + a r + a r^2 + dots.h + a r^(n-1) = a dot (1 - r^n)/(1 - r). $
]

#proof[
Write the sum out, then multiply the whole thing by $r$ and line the two up:
$ S_n &= a + a r + a r^2 + dots.h + a r^(n-1), \
  r S_n &= quad quad a r + a r^2 + dots.h + a r^(n-1) + a r^n. $
Subtract the second line from the first. Every middle term cancels its twin — this is a *telescoping* cancellation — leaving only the two ends:
$ S_n - r S_n = a - a r^n, quad "so" quad S_n (1 - r) = a(1 - r^n). $
Divide both sides by $(1 - r)$, legal because we assumed $r != 1$, and the formula falls out.
]

A quick sanity check on the torn paper, with $a = 1\/2$, $r = 1\/2$, $n = 4$: the formula gives $(1\/2) dot (1 - (1\/2)^4)/(1 - 1\/2) = (1\/2) dot (1 - 1\/16)/(1\/2) = 1 - 1\/16 = 15\/16$. And indeed $1\/2 + 1\/4 + 1\/8 + 1\/16 = 15\/16$. Four tears leave you one-sixteenth short of a whole sheet — exactly the picture.

#gomaths("Worked example: a geometric series by hand")[
Sum $3 + 6 + 12 + 24 + 48$. This is geometric with $a = 3$, $r = 2$, and $n = 5$ terms. Plug in:
$ S_5 = 3 dot (1 - 2^5)/(1 - 2) = 3 dot (1 - 32)/(-1) = 3 dot (-31)/(-1) = 3 times 31 = 93. $
Check by brute force: $3 + 6 = 9$, $+12 = 21$, $+24 = 45$, $+48 = 93$. The shortcut wins, and it wins by *more* the longer the list — summing a million-term geometric series is one division, not a million additions.
]

=== Arithmetic series and the telescoping trick

For completeness, the arithmetic cousin sums just as cleanly, and the *method* used to crack the geometric series — making terms cancel in pairs — deserves a name, because it recurs whenever a compressor analyses its own running cost.

An *arithmetic series* adds up a sequence that grows by a fixed step: $a + (a + d) + (a + 2d) + dots.h$. The shortcut is the one the schoolboy Gauss used: pair the first term with the last, the second with the second-to-last, and so on. Every pair sums to the same total, $("first" + "last")$, and there are $n\/2$ pairs, so

$ sum_(i=0)^(n-1) (a + i d) = n dot ("first" + "last")/2 = n dot (2a + (n-1) d)/2. $

In words: an arithmetic series equals *the number of terms times the average of the first and last*. Summing $1 + 2 + dots.h + 100$ is $100 times (1 + 100)/2 = 100 times 50.5 = 5050$ — Gauss's famous answer.

The cancellation we used to derive the geometric formula has its own name: a *telescoping sum*, one where consecutive terms knock each other out like the sections of a collapsing spyglass. The cleanest example: because $1/(k(k+1)) = 1/k - 1/(k+1)$, the sum

$ sum_(k=1)^(n) 1/(k(k+1)) = (1/1 - 1/2) + (1/2 - 1/3) + dots.h + (1/n - 1/(n+1)) = 1 - 1/(n+1). $

Every interior fraction appears once with a plus and once with a minus, so it vanishes, leaving only the two ends — and as $n -> infinity$ the tail $1/(n+1)$ heads to zero, so the infinite sum is exactly $1$. Telescoping is the analyst's favourite move: turn a fearsome sum into a subtraction of two endpoints. We will reach for it again when bounding how a coder's cost accumulates over a long file.

== Limits: chasing a process forever

Now we can settle the torn paper. What happens as the number of tears $n$ grows without bound? Look at the finite total $S_n = 1 - (1\/2)^n$ for our paper (taking $a = 1\/2$, $r = 1\/2$). As $n$ climbs — $1, 2, 3, dots.h$ — the piece $(1\/2)^n$ shrinks: $1\/2, 1\/4, 1\/8, dots.h$, smaller than any positive number you can name if you only tear long enough. So $S_n$ creeps up toward $1$ and never overshoots it. We say the *limit* of $S_n$, as $n$ goes to infinity, is $1$, and write

$ lim_(n -> infinity) S_n = 1. $

#definition("Limit (in plain words)")[
The *limit* of a sequence is the single number it gets and stays arbitrarily close to as you go further out. Formally: $L$ is the limit of $a_n$ if, for any tiny tolerance you pick, all the terms past some point sit within that tolerance of $L$. Casually: "where the sequence is heading." If no such single number exists (the terms run off to infinity, or hop around forever), the sequence has *no limit* — it *diverges*.
]

The arrow notation $n -> infinity$ reads "as $n$ tends to infinity." A limit is not "the last term" — there is no last term. It is the *destination* of an endless journey, which the journey may approach without ever arriving. That is the conceptual leap, and it is the one piece of genuinely new thinking in this chapter; everything else is arithmetic.

#keyidea[
A limit answers "where is this heading?" *without* requiring the process to ever stop. This is precisely the question a learning compressor faces: as it sees more of a file, its probability estimates wander toward the true frequencies. They may never land *exactly*, but they converge — and the *limit* is what they converge to. Convergence, the central word of all of machine learning, is just "the limit exists." We will say it again in Volume IV; it means nothing more than this.
]

A concrete taste of convergence in compression: an *adaptive* coder estimates a symbol's probability as a running frequency, $hat(p)_n = c_n \/ n$, where $c_n$ counts how often the symbol has appeared in the first $n$ positions. As $n$ grows, $hat(p)_n$ wanders, but it is *converging*: its limit is the symbol's true probability $p$. Suppose the truth is $p = 0.30$ and the early counts give $hat(p)_1 = 0$, $hat(p)_2 = 0.5$, $hat(p)_3 = 0.33$, $hat(p)_4 = 0.25$, $hat(p)_(10) = 0.30$, $hat(p)_(100) = 0.31$, $hat(p)_(1000) = 0.299$, … The early estimates lurch wildly — which is exactly why an adaptive compressor codes the *start* of a file poorly and improves as it goes. The estimate never lands *exactly* on $0.30$, yet it gets and stays arbitrarily close: $lim_(n->infinity) hat(p)_n = p$. That limit is the whole justification for trusting a learned model on long data, and the "warm-up cost" is the price of the early wandering.

=== The infinite geometric series

When the ratio $r$ is between $-1$ and $1$ (so each term shrinks toward zero), the finite formula has a clean limit, and it is the workhorse identity we have owed since Chapter 10.

#theorem("Infinite geometric series")[
If $abs(r) < 1$ then the infinite series converges:
$ sum_(k=0)^(infinity) r^k = 1 + r + r^2 + r^3 + dots.h = 1/(1 - r). $
More generally, $a + a r + a r^2 + dots.h = a/(1 - r)$.
]

#proof[
Start from the finite formula with $a = 1$: $S_n = (1 - r^n)/(1 - r)$. Because $abs(r) < 1$, the term $r^n$ shrinks to $0$ as $n -> infinity$ (a number smaller than 1 in size, multiplied by itself again and again, vanishes). So the numerator $1 - r^n$ heads to $1 - 0 = 1$, and
$ sum_(k=0)^(infinity) r^k = lim_(n->infinity) (1 - r^n)/(1 - r) = (1 - 0)/(1 - r) = 1/(1 - r). $
The torn paper is the case $a = r = 1\/2$: the *kept* pieces sum to $(1\/2)/(1 - 1\/2) = 1$, just as we tore.
]

#gomaths("Paying the Chapter 10 IOU: $EE[X] = 1\/p$ for a geometric source")[
A *geometric source* models "wait for the first success." Flip a biased coin with success probability $p$ each toss; let $X$ be the toss number of the first success. Then $P(X = k) = (1-p)^(k-1) p$ for $k = 1, 2, 3, dots.h$ — you need $k-1$ failures (each of probability $1-p$) followed by a success. Chapter 10 claimed $EE[X] = 1\/p$. Here is the payment. By the definition of expectation,
$ EE[X] = sum_(k=1)^(infinity) k dot (1-p)^(k-1) p = p sum_(k=1)^(infinity) k thin q^(k-1), quad "writing" q = 1 - p. $
We need $sum_(k=1)^infinity k thin q^(k-1)$. This is an infinite series with an extra factor of $k$; the slick way to get it is to *differentiate* the plain geometric series — a calculus move we unlock in the next section. The result is $sum_(k=1)^infinity k q^(k-1) = 1/(1-q)^2 = 1/p^2$. Therefore
$ EE[X] = p dot 1/p^2 = 1/p. $
So a coin that succeeds one time in ten ($p = 0.1$) takes, on average, $1\/0.1 = 10$ tosses for its first success — exactly the intuition, now proven. This same source models run-lengths, gaps between rare events, and the residuals that Golomb–Rice coding (Chapter 25) crushes.
]

#aside[
Not every infinite sum of shrinking positive terms converges. The *harmonic series* $1 + 1/2 + 1/3 + 1/4 + dots.h$ has terms that shrink to zero, yet its total is *infinite* — it grows without bound, just unbearably slowly (past a *billion* terms it has barely crawled past 21). The terms shrink, but not *fast enough*. Convergence is a race between how many terms you add and how quickly each one fades. Geometric series win that race because they fade *exponentially*; the harmonic series fades only linearly and loses. Telling these apart is a whole subject; for compression, the geometric case is the one that pays the rent.
]

#tryit[
Before we build coders that *rely* on these sums, let us write a tiny numerical check that the closed form really equals the brute-force sum — the kind of guard rail every careful programmer leaves behind. (This is a stand-alone snippet, not yet part of the `tinyzip` project, whose first build step lands in Chapter 15.) The function compares the brute-force partial sum against the formula.

```python
def geometric_sum(a: float, r: float, n: int) -> float:
    """Sum of a + a*r + ... + a*r**(n-1), the closed-form way."""
    if r == 1.0:
        return a * n                      # degenerate case: n equal terms
    return a * (1.0 - r**n) / (1.0 - r)

def geometric_sum_bruteforce(a: float, r: float, n: int) -> float:
    return sum(a * r**k for k in range(n))   # add the terms one by one

# They must agree -- a guard rail for the math we will lean on.
for r in (0.5, 0.9, 2.0):
    fast = geometric_sum(3.0, r, 12)
    slow = geometric_sum_bruteforce(3.0, r, 12)
    assert abs(fast - slow) < 1e-9, (r, fast, slow)
print("geometric sums verified")
```

The `assert` statement raises an error if its condition is false, so a silent formula bug becomes a loud crash. We will reuse this defensive habit — `assert` your invariants — throughout the project. Run it; it prints `geometric sums verified`.
]

== A gentle calculus: the slope of a curve

Everything so far has been about *adding*. The rest of the chapter is about *change* — and the rate at which things change. This is calculus, and it has a fearsome reputation it does not deserve. Strip away the jargon and calculus is one idea, repeated: *zoom in on a curve until it looks straight, then read its slope.*

We already know the slope of a straight line: "rise over run," how much the line climbs for each step you take to the right. The line $y = 3x$ climbs $3$ for every $1$ across, so its slope is $3$, everywhere. A curve is harder, because its steepness *changes* — a valley is steep on the sides and flat at the bottom. So we ask a sharper question: what is the slope *at one particular point* on the curve?

#fig([Zooming in on a curve at a point. From far away the curve bends; up close, near the point, it is indistinguishable from a straight line — the *tangent*. The slope of that line is the derivative at the point. Here the curve $y = x^2$ is flat at the bottom (slope 0) and steeper to the right (slope grows).], cetz.canvas({
  import cetz.draw: *
  // axes
  line((-0.3, 0), (3.2, 0), mark: (end: "stealth"))
  line((0, -0.3), (0, 3.4), mark: (end: "stealth"))
  content((3.35, 0), $x$)
  content((0, 3.6), $y$)
  // parabola y = x^2 / 2 (scaled to fit)
  let f(x) = calc.pow(x, 2) / 2.0
  let pts = ()
  let x = -0.1
  while x <= 2.6 {
    pts.push((x, f(x)))
    x = x + 0.05
  }
  line(..pts, stroke: 1.2pt + rgb("#0b5394"))
  content((2.5, 3.25), text(fill: rgb("#0b5394"))[$y = x^2$])
  // tangent at x = 2 : slope = 2 (since deriv of x^2/2 is x), point (2,2)
  let px = 2.0
  let py = f(px)
  line((px - 1.0, py - 1.0), (px + 0.9, py + 0.9), stroke: 1pt + rgb("#9a2617"))
  circle((px, py), radius: 0.06, fill: rgb("#9a2617"), stroke: none)
  content((px + 0.55, py - 0.45), text(size: 8pt, fill: rgb("#9a2617"))[tangent])
  // flat tangent at bottom
  line((-0.6, 0), (0.6, 0), stroke: 1pt + rgb("#0b6e4f"))
  circle((0, 0), radius: 0.06, fill: rgb("#0b6e4f"), stroke: none)
  content((0.9, 0.25), text(size: 8pt, fill: rgb("#0b6e4f"))[slope 0])
}))

The trick is the *tangent line*: the single straight line that just kisses the curve at our point, matching its direction there. The slope of that tangent line is what we mean by "the slope of the curve at that point." It has a name — the *derivative* — and a notation, and it is the single most useful number in applied mathematics.

#gomaths("The derivative as a limit of slopes")[
How do we *find* the tangent's slope? With a limit — which is why we built limits first. Pick our point at input $x$, height $f(x)$. Step a tiny distance $h$ to the right, to input $x + h$, height $f(x+h)$. The straight line through these two nearby points has the ordinary slope
$ "rise"/"run" = (f(x + h) - f(x))/h. $
This is the slope of a *secant* — a line cutting the curve at two points. Now shrink $h$ toward $0$: the two points slide together, and the secant pivots into the tangent. The derivative is the *limit* of that slope:
$ f'(x) = lim_(h -> 0) (f(x + h) - f(x))/h. $
The prime mark in $f'(x)$ reads "$f$ prime of $x$" and means "the derivative of $f$ at $x$." (You will also meet the notation $(d f)/(d x)$, read "dee-$f$ dee-$x$," which means the same thing.) Do not let the limit scare you; for the handful of functions we need, the answer is a one-line rule, derived once and reused forever.
]

Let us earn one such rule by hand, because seeing it done once removes the mystery for good. Take the parabola $f(x) = x^2$. Then
$ (f(x+h) - f(x))/h = ((x+h)^2 - x^2)/h = (x^2 + 2 x h + h^2 - x^2)/h = (2 x h + h^2)/h = 2x + h. $
Now let $h -> 0$: the leftover $h$ vanishes, and we are left with $f'(x) = 2x$. So the slope of $y = x^2$ at any point is *twice the input*. At $x = 0$ the slope is $0$ — dead flat, the bottom of the valley. At $x = 2$ the slope is $4$ — climbing steeply. That matches the picture exactly, and it is the entire idea of differentiation in one example.

=== Three rules that cover almost everything

You will almost never compute a derivative from the limit again. Three rules, plus two known derivatives, handle every function in this book. We state them plainly; the proofs are the same secant-slope limit, done once in any calculus text.

#definition("The derivative rules we need")[
Let $c$ be a constant and $f, g$ be functions.
+ *Constant rule.* The derivative of a constant is $0$. (A flat line has slope $0$.)
+ *Power rule.* The derivative of $x^n$ is $n thin x^(n-1)$. (So $x^2 -> 2x$, $x^3 -> 3 x^2$, and $x = x^1 -> 1$.)
+ *Constant-multiple and sum rules.* $ (c thin f)' = c thin f', quad (f + g)' = f' + g'. $ Derivatives, like sums, pull out constants and split across additions.
+ *Two special functions.* The exponential is its own derivative, $(e^x)' = e^x$, and the natural logarithm has derivative $(ln x)' = 1\/x$. These two power all of information theory and machine learning.
]

#gomaths("The number $e$ and why $(e^x)' = e^x$")[
The constant $e approx 2.71828$ is, after $0$ and $1$, the most important number in mathematics. Jacob Bernoulli stumbled on it in 1683 while asking a banker's question: if 100% yearly interest is paid in ever-smaller installments — half-yearly, monthly, daily, every instant — what does one dollar grow to in a year? Compounding $n$ times gives $(1 + 1\/n)^n$, and as $n -> infinity$ this *limit* settles on $e$. Leonhard Euler, around 1727–1731, named it, computed it to many digits, and revealed its magic property: the function $e^x$ grows at a rate exactly equal to its own height. Its slope *equals* its value, everywhere — that is what $(e^x)' = e^x$ says. No other function (besides multiples of it) does this. Because logarithms to base $e$ undo $e^x$, the natural log $ln x = log_e x$ inherits the clean derivative $1\/x$, and base-$e$ is why $ln$ haunts every entropy formula even when we *report* answers in base-2 bits (the two differ only by the fixed factor $log_2 e approx 1.4427$, from the change-of-base rule of Chapter 7).
]

#gomaths("Worked examples with the rules")[
Differentiate a few, slowly.

*Variance of a Bernoulli source.* Chapter 10 left the claim that $f(p) = p(1-p) = p - p^2$ peaks at $p = 1\/2$. Differentiate term by term: the derivative of $p$ is $1$ (power rule, $n=1$), the derivative of $p^2$ is $2p$, so
$ f'(p) = 1 - 2p. $
Set $f'(p) = 0$: $1 - 2p = 0$, giving $p = 1\/2$. The slope is zero there — the peak — paying a second Chapter 10 IOU.

*A cubic.* If $g(x) = 4 x^3 - 6 x + 7$, then $g'(x) = 12 x^2 - 6$ (power rule on each term, constant $7$ vanishes).

*Differentiating the geometric series.* Recall we needed $sum_(k=1)^infinity k thin q^(k-1)$ to prove $EE[X] = 1\/p$. Start from the known sum $sum_(k=0)^infinity q^k = 1/(1-q)$, valid for $abs(q) < 1$, and differentiate *both sides* with respect to $q$. The left side, term by term, gives $sum_(k=1)^infinity k thin q^(k-1)$ (the $k=0$ term is constant, so it drops). The right side: $1/(1-q) = (1-q)^(-1)$ has derivative $(1-q)^(-2) = 1/(1-q)^2$. Hence $sum_(k=1)^infinity k thin q^(k-1) = 1/(1-q)^2$, the identity we borrowed earlier. Calculus closed the loop on probability.
]

#gomaths("One more rule: the chain rule for nested functions")[
The three rules differentiate functions built by adding and multiplying. One common shape they miss is a function *inside* another — a *composition*, like $(y - hat(y))^2$, which is "square" wrapped around "subtract." The *chain rule* handles these: to differentiate an outer function of an inner one, multiply the outer derivative (with the inner left alone) by the inner derivative. In symbols, if $h(x) = f(g(x))$ then $h'(x) = f'(g(x)) dot g'(x)$ — "outer-prime times inner-prime."

A tiny example, the exact one we need next. Let $h = (y - hat(y))^2$ and differentiate with respect to $hat(y)$. The outer function is "square," whose derivative is "twice"; the inner function is $g = y - hat(y)$, whose derivative with respect to $hat(y)$ is $-1$ (the $y$ is a constant here, and $hat(y)$ has slope $1$). So
$ (d h)/(d hat(y)) = underbrace(2(y - hat(y)), "outer-prime") dot underbrace((-1), "inner-prime") = -2(y - hat(y)). $
The intuition: nudging $hat(y)$ a hair changes the inside by $-1$ as fast, and the square magnifies *that* change by $2(y-hat(y))$, so the two rates multiply. We will lean on this once for least squares and once more for bit allocation in the exercises; it is the last derivative rule the book needs, and gradient descent through a deep network is nothing but the chain rule applied thousands of times in a row.
]

#history[
Calculus was invented twice, independently and acrimoniously, in the 1660s–1680s: by Isaac Newton in England (who called it "the method of fluxions" and used it for gravity and motion) and by Gottfried Wilhelm Leibniz in Germany (who gave us the elegant $sum$-like $integral$ sign and the $(d y)/(d x)$ notation we still use). Their followers feuded for decades over priority. The modern verdict: both got there, Leibniz's *notation* won, and the limit-based definition we used above was made fully rigorous only ~150 years later by Cauchy and Weierstrass. You are learning the cleaned-up version that took the best minds in Europe two centuries to settle.
]

== Optimisation: finding the best with slope zero

Here is why we bothered. A vast amount of compression is *optimisation*: choosing the setting that makes something as small (or as large) as possible. How long should each codeword be to minimise the average bits? How should an encoder split its bit budget between two frames to minimise total distortion? What weights make a neural compressor predict best? Every one of these is "find the input that minimises a quantity," and calculus gives a startlingly simple compass.

#keyidea[
At the very bottom of a valley, or the very top of a hill, a smooth curve is momentarily *flat* — its slope is zero. So to find where a quantity is smallest or largest, find where its derivative is zero. These zero-slope spots are called *critical points* or *stationary points*. Solve $f'(x) = 0$, and the minimiser (or maximiser) is among the solutions. This one sentence is the workhorse of applied optimisation, and we already used it twice without ceremony.
]

A worked example we will care about for real. Suppose a noisy measurement of some true value $mu$ gives you readings $y_1, y_2, dots.h, y_n$, and you want the single number $hat(y)$ that is "closest" to all of them in the least-squares sense — minimising the total squared error
$ E(hat(y)) = sum_(i=1)^(n) (y_i - hat(y))^2. $
This is not an idle exercise: it is exactly the quantity a quantizer minimises when it picks a representative value for a cluster of inputs (Chapter 39), and it is the "distortion" half of every rate–distortion tradeoff (Chapter 21). Differentiate with respect to $hat(y)$. Using the rules — and the chain rule we just met, which gives the derivative of $(y_i - hat(y))^2$ as $-2(y_i - hat(y))$:
$ E'(hat(y)) = sum_(i=1)^(n) -2 (y_i - hat(y)) = -2 (sum_i y_i - n hat(y)). $
Set it to zero: $sum_i y_i - n hat(y) = 0$, so
$ hat(y) = 1/n sum_(i=1)^(n) y_i. $
The error-minimising single value is the plain *average* of the readings. Calculus just *proved* what your intuition guessed — and the proof generalises to cases where intuition fails completely. That is the power of having a compass instead of a hunch.

#pitfall[
Slope-zero finds *flat spots*, but not all flat spots are the bottom of the deepest valley. A function can have a small dip (a *local* minimum) that is not its true lowest point (the *global* minimum), and at a *saddle* the slope is zero yet you are at neither a peak nor a valley. For the simple, bowl-shaped (*convex*) functions in entropy coding and least-squares, the only critical point *is* the global minimum, so we are safe. But the bumpy error-landscapes of neural compressors (Volume IV) are riddled with local minima and saddles — which is exactly why training them is hard, and why the *walking-downhill* method we meet next, rather than solving $f' = 0$ outright, is what is actually used.
]

== When you cannot solve it: walking downhill

Setting $f'(x) = 0$ and solving works when the function is simple. But a neural compressor's error depends on *millions* of numbers at once, and there is no formula to solve. So we do something humbler and more powerful: we *walk downhill*. Stand somewhere on the error landscape, feel which way is down, take a small step, and repeat. Do it enough and you slide into a valley. To "feel which way is down" we need to extend the derivative from one input to many. That is the *gradient*.

#gomaths("Functions of several inputs, and partial derivatives")[
So far our functions took one number in and gave one out. Real problems take many numbers in: an error $E(w_1, w_2, dots.h, w_m)$ that depends on $m$ knobs at once. To find the slope of such a function we vary *one* knob at a time, holding the others frozen, and take the ordinary derivative. That is a *partial derivative*, written with a curly dee: $(partial E)/(partial w_1)$ means "the slope of $E$ as we nudge only $w_1$, keeping $w_2, dots.h$ fixed." It answers: "if I tweak this one knob a hair, how fast does the error change?"

Tiny example. Let $E(a, b) = a^2 + 3 b$. Nudging $a$ (freezing $b$, so $3b$ is constant): $(partial E)/(partial a) = 2a$. Nudging $b$ (freezing $a$, so $a^2$ is constant): $(partial E)/(partial b) = 3$. Each partial is just an ordinary derivative with the other letters treated as numbers.
]

#definition("The gradient")[
The *gradient* of a function $E(w_1, dots.h, w_m)$ is the list of all its partial derivatives, bundled into one arrow (a *vector*, the star of Chapter 12):
$ nabla E = ((partial E)/(partial w_1), (partial E)/(partial w_2), dots.h, (partial E)/(partial w_m)). $
The upside-down triangle $nabla$ is read "nabla" or "del." The gradient points in the direction of *steepest increase* — the compass needle aimed straight uphill — and its length says how steep. Its negative, $-nabla E$, therefore points straight *downhill*: the fastest way to *decrease* $E$. That single fact is the whole secret of training every model in this book.
]

#fig([Gradient descent on a bowl-shaped error landscape. The rings are contours of equal error (like a topographic map); the centre is the minimum. From a starting point, each step moves a little in the downhill direction $-nabla E$, scaled by the learning rate, spiralling into the valley.], cetz.canvas({
  import cetz.draw: *
  // concentric ellipses as contours
  for r in (1.7, 1.3, 0.95, 0.62, 0.32) {
    circle((0, 0), radius: r, stroke: 0.6pt + rgb("#7da7d0"))
  }
  circle((0, 0), radius: 0.05, fill: rgb("#0b6e4f"), stroke: none)
  content((0.0, -2.05), text(size: 8pt, fill: rgb("#0b6e4f"))[minimum])
  // descent path (decreasing steps toward centre)
  let pts = ((-1.55, 1.25), (-0.95, 0.62), (-0.5, 0.18), (-0.2, -0.02), (-0.05, 0.0))
  for i in range(pts.len() - 1) {
    line(pts.at(i), pts.at(i + 1), mark: (end: "stealth"),
         stroke: 1pt + rgb("#9a2617"))
  }
  circle(pts.at(0), radius: 0.05, fill: rgb("#9a2617"), stroke: none)
  content((-1.55, 1.55), text(size: 8pt, fill: rgb("#9a2617"))[start])
}))

#algo(
  name: "Gradient Descent",
  year: "1847",
  authors: "Augustin-Louis Cauchy (method of steepest descent); convergence studied by Haskell Curry, 1944",
  aim: "Find an input that (locally) minimises a smooth function of many variables, when no closed-form solution exists.",
  complexity: "One gradient evaluation per step; number of steps depends on the landscape and the step size.",
  strengths: "Needs only slopes, not a formula for the answer; scales to millions or billions of variables; the backbone of all deep learning.",
  weaknesses: "Can stall in a local minimum or on a flat saddle; sensitive to the step size; may zig-zag in stretched valleys.",
  superseded: "Refined, never replaced — Momentum, RMSProp, and Adam are all gradient descent with smarter step rules.",
)[
The recipe is three lines, repeated:
+ Start at some guess $w$ (often random).
+ Compute the gradient $nabla E(w)$ — the uphill direction.
+ Step against it: $w <- w - eta thin nabla E(w)$, where $eta$ (the Greek letter eta) is a small positive *learning rate* — the size of each step.

Repeat until the steps stop helping (the gradient is near zero, meaning the ground is flat — you have reached a valley). The learning rate $eta$ is the crucial dial: too small and you crawl; too large and you overshoot the valley and bounce out. Choosing it well is half the art of training a model.
]

#gopython("Gradient descent in eight lines")[
Watch the abstract idea become concrete code. We minimise the bowl $f(x) = (x - 3)^2$, whose minimum is obviously at $x = 3$, so we can check the machine's answer. Its derivative is $f'(x) = 2(x - 3)$.

```python
def f_prime(x: float) -> float:
    return 2.0 * (x - 3.0)        # the slope of (x-3)**2

x = 0.0                          # a wild starting guess
eta = 0.1                        # learning rate (step size)
for step in range(40):
    x = x - eta * f_prime(x)     # step downhill
print(round(x, 4))               # 3.0  -- it found the minimum!
```

Each pass nudges `x` against its slope. Where the slope is steep (far from 3) the steps are big; as `x` nears 3 the slope flattens and the steps shrink, easing it gently into the bottom. From a starting guess of `0.0` it homes in on `3.0`. Swap in a function of a thousand variables and a real gradient, and this *same* loop trains a neural image codec — there is genuinely no more magic to it than this.
]

#misconception[that calculus and "the slope is zero" are abstract academic tools with no place in a practical compression pipeline.][Every modern video encoder is, under the hood, an optimiser. When `x264` or an AV1 encoder decides how coarsely to quantize a block, it is minimising a cost $J = D + lambda R$ — distortion plus a price $lambda$ times the bit-rate — and the optimal $lambda$ and the optimal quantizer settings are found by exactly the zero-slope and downhill-walking reasoning of this chapter (Chapter 41 makes this explicit). And every learned codec in Volume IV is trained by the eight-line loop you just read, scaled up. Calculus is not background colour here; it is the machinery.]

#checkpoint[You are minimising $f(x) = (x - 3)^2$ with gradient descent and a learning rate $eta = 0.1$, starting at $x = 0$. What is $x$ after the *first* step?][The slope at $x=0$ is $f'(0) = 2(0 - 3) = -6$. The update is $x <- 0 - 0.1 times (-6) = 0 + 0.6 = 0.6$. The first step moves you from $0$ to $0.6$, heading toward the minimum at $3$, as it should.]

== The bending of a curve, and the last IOU

One debt remains: Chapter 10 promised that the logarithm's gentle *bending* matters, and that it underlies a fact called Jensen's inequality that pins down where entropy is largest. Bending is a second-order idea — it is about how the *slope itself* changes — and the derivative gives it to us cleanly.

If the derivative $f'(x)$ is the slope, then the *derivative of the derivative*, written $f''(x)$ and called the *second derivative*, is the rate at which the slope changes. Its sign tells you which way the curve bends:

- $f''(x) > 0$: the slope is *increasing*, so the curve bends *upward* like a bowl ($union$-shaped). Such a function is *convex*. A convex curve lies *below* the straight chord joining any two of its points — a bowl holds water.
- $f''(x) < 0$: the slope is *decreasing*, so the curve bends *downward* like a dome ($inter$-shaped). Such a function is *concave*. It lies *above* its chords — a dome sheds water.

#gomaths("Convex, concave, and why the logarithm is concave")[
Take $f(x) = ln x$. Its first derivative is $f'(x) = 1\/x$ (a slope that is always positive but *shrinking* as $x$ grows — the log climbs ever more lazily). Its second derivative is the derivative of $1\/x = x^(-1)$, which by the power rule is $-x^(-2) = -1\/x^2$. For every positive $x$ this is *negative*. So $ln$ is *concave* everywhere — a dome. The same holds for $log_2$, since it is just $ln$ scaled by a positive constant. This single fact — "log is concave" — is the geometric reason the entropy $H(X) = sum_x p(x) log_2(1\/p(x))$ is *maximised* by the uniform distribution (all symbols equally likely), and the reason no code can beat entropy on average. We will cash this out in full when we prove the source coding theorem in Chapter 19; here we have simply built the tool.
]

#theorem("Jensen's inequality (the idea)")[
If $f$ is *concave* (a dome) and $X$ is a random variable, then the function of the average is at least the average of the function:
$ f(EE[X]) >= EE[f(X)]. $
For a *convex* (bowl) function the inequality flips: $f(EE[X]) <= EE[f(X)]$.
]

#proof[
We argue the concave case by picture, which is honest because concavity *is* the picture. A concave curve lies on or above every chord joining two of its points. Take two values $x_1, x_2$ that $X$ might equal, with probabilities $w$ and $1 - w$. Their average input is $bar(x) = w x_1 + (1-w) x_2$, a point on the horizontal axis between them. The chord between $(x_1, f(x_1))$ and $(x_2, f(x_2))$, read at $bar(x)$, gives exactly the *average of the function values*, $w f(x_1) + (1-w) f(x_2) = EE[f(X)]$. Because the dome sits *above* its chord, the curve's own height there, $f(bar(x)) = f(EE[X])$, is at least as high. Hence $f(EE[X]) >= EE[f(X)]$. The general case (more than two values) follows by repeating the pairing, and the convex case is the same picture upside-down.
]

This is the "bending" Chapter 10 promised would matter, now made precise: concavity is exactly the property that lets us conclude things about *averages of curved quantities*, and curved quantities (logarithms of probabilities) are what every entropy bound is built from. With this, all three IOUs are paid in full.

#gopython("Optimal code lengths by minimising expected bits")[
Let us use *optimisation* — the chapter's marquee tool — to compute something a real compressor wants: the ideal codeword lengths. Chapter 19 will prove it; here we *discover* it numerically. (Still a stand-alone illustration; the `tinyzip` Huffman coder that realises these lengths arrives in Chapter 24.)

Suppose symbols have probabilities $p_1, dots.h, p_n$ and we may assign each a (real-valued) length $ell_i$ in bits. The expected length is $sum_i p_i ell_i$, and a valid prefix code must obey the *Kraft budget* $sum_i 2^(-ell_i) <= 1$ (proved in Chapter 19 — for now, take it as the rule that "short codewords are expensive"). Minimising expected length subject to that budget is a calculus optimisation, and its solution is the cleanest formula in the field:
$ ell_i^* = log_2(1/p_i) = -log_2 p_i. $
A symbol of probability $1\/8$ deserves $log_2 8 = 3$ bits; a probability-$1\/2$ symbol deserves $1$ bit. Plugging these ideal lengths back in gives expected length $sum_i p_i log_2(1\/p_i)$ — which is the *entropy* $H$. Let us verify the formula gives shorter expected length than any naive fixed length, on a tiny model:

```python
from math import log2

def ideal_lengths(pmf: dict[str, float]) -> dict[str, float]:
    """The expected-bits-minimising code length for each symbol."""
    return {s: -log2(p) for s, p in pmf.items() if p > 0.0}

def expected_length(pmf: dict[str, float],
                    lengths: dict[str, float]) -> float:
    return sum(pmf[s] * lengths[s] for s in pmf)

pmf = {"a": 0.5, "b": 0.25, "c": 0.125, "d": 0.125}
ideal = ideal_lengths(pmf)                 # {'a':1, 'b':2, 'c':3, 'd':3}
fixed = {s: 2.0 for s in pmf}              # naive: 2 bits each, always
print(round(expected_length(pmf, ideal), 4))   # 1.75  -- the entropy!
print(round(expected_length(pmf, fixed), 4))   # 2.0
```

The optimised code averages `1.75` bits per symbol; the naive fixed-width code averages `2.0`. The optimiser found a 12.5% saving, and the answer it found is *exactly the entropy*. This is the first time in the book that pure mathematics has handed us a compression *win* — and it came straight out of "minimise an expected sum." The Huffman coder of Chapter 24 is, in essence, the practical machine that realises these ideal lengths with whole-bit codewords.
]

#scoreboard(
  caption: "the entropy floor, derived by optimisation (4-symbol toy model)",
  [Fixed 2-bit code], [2.00 bits/sym], [1.00×], [naive baseline — every symbol the same width],
  [Ideal $-log_2 p$ lengths], [1.75 bits/sym], [0.875×], [the entropy $H$; minimises expected length],
)

#note[
We have quietly used a *vector* — the gradient is a list of numbers treated as one arrow — and an *integral*, hinted at as "the sum's continuous cousin," without developing either. *Chapter 12* builds vectors and matrices properly, turning the gradient into a first-class object and giving us the dot products and transforms behind the DCT and neural nets. The *integral* — area under a curve, the tool for continuous random variables and the Gaussian source — we develop only when we need it, at the gates of rate–distortion theory and signal processing in Volume III. We took only the calculus this book actually spends.
]

#takeaways((
  [The signs $sum$ (add) and $product$ (multiply) are loops frozen into symbols; a $sum$ is a `for` loop, and $log$ turns a $product$ of probabilities into a $sum$ of logs — the reason information theory lives in log-space.],
  [A *geometric series* $a + a r + a r^2 + dots.h$ sums to $a(1 - r^n)/(1 - r)$, and when $abs(r) < 1$ the *infinite* sum converges to $a/(1 - r)$ — the identity behind the geometric source's $EE[X] = 1\/p$.],
  [A *limit* is where a process is heading, even if it never arrives; convergence — the heartbeat of machine learning — means simply "the limit exists."],
  [The *derivative* $f'(x)$ is the slope of a curve at a point. Three rules (constant, power $x^n -> n x^(n-1)$, and constant-multiple/sum) plus $(e^x)' = e^x$ and $(ln x)' = 1\/x$ cover everything we need.],
  [To *optimise* — find a smallest or largest value — set the derivative to zero. This proves the error-minimising estimate is the average, and that Bernoulli variance peaks at $p = 1\/2$.],
  [When no formula solves it, *gradient descent* walks downhill: step against the gradient $-nabla E$ by a learning rate $eta$, repeat. It trains every neural codec in the book.],
  [A *concave* (dome) function lies above its chords; the logarithm is concave, which (via Jensen's inequality) is why uniform sources are hardest to compress.],
  [Minimising expected code length yields ideal lengths $ell_i = -log_2 p_i$ and an expected cost equal to the *entropy* — our first compression win from pure calculus, and a preview of Chapters 18–24.],
))

== Exercises

#exercise("11.1", 1)[
Write each of the following in $sum$ or $product$ notation: (a) $1 + 4 + 9 + 16 + 25$; (b) $2 times 4 times 6 times 8$; (c) the probability that $n$ independent symbols, with probabilities $p_1, dots.h, p_n$, all occur in order.
]
#solution("11.1")[
(a) $sum_(i=1)^(5) i^2$ — the squares of 1 through 5. (b) $product_(k=1)^(4) 2k$ — twice each of 1 through 4. (c) $product_(i=1)^(n) p_i$ — independence means probabilities multiply, exactly the "probability of a whole file" used by every statistical coder.
]

#exercise("11.2", 1)[
Unroll and evaluate $sum_(k=0)^(4) 3 dot (1\/2)^k$ by writing out all five terms and adding, then check your answer with the finite geometric-series formula.
]
#solution("11.2")[
Terms: $3 + 3\/2 + 3\/4 + 3\/8 + 3\/16 = 48\/16 + 24\/16 + 12\/16 + 6\/16 + 3\/16 = 93\/16 = 5.8125$. By formula with $a = 3$, $r = 1\/2$, $n = 5$: $3 dot (1 - (1\/2)^5)/(1 - 1\/2) = 3 dot (1 - 1\/32)/(1\/2) = 6 (31\/32) = 186\/32 = 93\/16$. They agree.
]

#exercise("11.3", 2)[
A run-length encoder outputs a "stop" symbol with probability $p = 1\/4$ after each item. The number of items in a run is geometric. What is the *average* run length? Then compute the infinite sum $sum_(k=0)^infinity (3\/4)^k$ directly and explain how the two answers relate.
]
#solution("11.3")[
The average run length (number of trials until the first "stop") is $EE[X] = 1\/p = 1\/(1\/4) = 4$ items. The infinite sum $sum_(k=0)^infinity (3\/4)^k = 1/(1 - 3\/4) = 1/(1\/4) = 4$ by the infinite geometric series. They match because $1\/p = 1\/(1-q) = sum_k q^k$ with $q = 1 - p = 3\/4$: the expected count of a geometric source is literally that geometric sum. The two "4"s are the same fact wearing two hats.
]

#exercise("11.4", 1)[
Differentiate, using the rules: (a) $f(x) = 5 x^4$; (b) $g(x) = x^3 - 2 x + 9$; (c) $h(x) = 7$; (d) $k(x) = e^x + ln x$.
]
#solution("11.4")[
(a) $f'(x) = 20 x^3$ (power rule: $5 times 4 x^3$). (b) $g'(x) = 3 x^2 - 2$ (the constant $9$ vanishes). (c) $h'(x) = 0$ (constant). (d) $k'(x) = e^x + 1\/x$ (the two special derivatives, added).
]

#exercise("11.5", 2)[
The function $f(x) = x^2 - 6 x + 11$ describes a cost. Find the value of $x$ that minimises it by setting $f'(x) = 0$, and compute the minimum cost. How do you know it is a minimum and not a maximum?
]
#solution("11.5")[
$f'(x) = 2x - 6 = 0$ gives $x = 3$. The minimum cost is $f(3) = 9 - 18 + 11 = 2$. It is a minimum because $f''(x) = 2 > 0$, so the curve bends upward (a bowl): the single critical point of an upward-bending parabola is its lowest point.
]

#exercise("11.6", 2)[
Show, by setting the derivative to zero, that $f(p) = -p ln p - (1-p) ln(1-p)$ (the "binary entropy," in nats) is maximised at $p = 1\/2$. You may use $(ln x)' = 1\/x$ and the fact that the derivative of $-(1-p)ln(1-p)$ with respect to $p$ is $ln(1-p) + 1$.
]
#solution("11.6")[
Differentiate: the derivative of $-p ln p$ is $-(ln p + p dot 1\/p) = -ln p - 1$. Adding the given piece, $f'(p) = (-ln p - 1) + (ln(1-p) + 1) = ln(1-p) - ln p = ln((1-p)/p)$. Set $f'(p) = 0$: $ln((1-p)/p) = 0$ means $(1-p)/p = 1$, so $1 - p = p$, giving $p = 1\/2$. The binary entropy peaks at the fair coin — the hardest distribution to compress — confirming the concavity argument from the chapter.
]

#exercise("11.7", 2)[
Run two steps of gradient descent by hand on $f(x) = (x - 5)^2$, with derivative $f'(x) = 2(x - 5)$, starting at $x = 1$ with learning rate $eta = 0.2$. Report $x$ after step 1 and after step 2. Is it moving toward $5$?
]
#solution("11.7")[
Step 1: $f'(1) = 2(1 - 5) = -8$; update $x <- 1 - 0.2 times (-8) = 1 + 1.6 = 2.6$. Step 2: $f'(2.6) = 2(2.6 - 5) = -4.8$; update $x <- 2.6 - 0.2 times (-4.8) = 2.6 + 0.96 = 3.56$. The sequence $1 -> 2.6 -> 3.56$ climbs toward the minimiser $x = 5$, with shrinking steps as the slope flattens — exactly the expected behaviour.
]

#exercise("11.8", 3)[
Let $E(a, b) = (a - 2)^2 + (b + 1)^2$. (a) Compute the two partial derivatives and the gradient $nabla E$. (b) At the point $(a, b) = (0, 0)$, write the gradient as a pair of numbers and the downhill direction $-nabla E$. (c) Where is the minimum, and what is the gradient there?
]
#solution("11.8")[
(a) $(partial E)/(partial a) = 2(a - 2)$ and $(partial E)/(partial b) = 2(b + 1)$, so $nabla E = (2(a-2), thin 2(b+1))$. (b) At $(0,0)$: $nabla E = (2(0-2), 2(0+1)) = (-4, 2)$; the downhill direction is $-nabla E = (4, -2)$, i.e. increase $a$, decrease $b$. (c) The minimum is where both partials vanish: $a = 2$, $b = -1$, and there $nabla E = (0, 0)$ — flat ground, the bottom of the bowl. This is the two-variable least-squares picture that a quantizer solves.
]

#exercise("11.9", 3)[
The infinite series $sum_(k=1)^infinity k thin q^(k-1)$ was claimed to equal $1/(1-q)^2$ for $abs(q) < 1$. Reproduce the derivation: start from $sum_(k=0)^infinity q^k = 1/(1-q)$ and differentiate both sides with respect to $q$. Then use it to confirm that a geometric source with $p = 0.2$ has mean $1\/p = 5$.
]
#solution("11.9")[
Left side: differentiating $sum_(k=0)^infinity q^k$ term by term gives $sum_(k=1)^infinity k thin q^(k-1)$ (the $k=0$ term is the constant $1$, whose derivative is $0$). Right side: $1/(1-q) = (1-q)^(-1)$ differentiates to $(1-q)^(-2) = 1/(1-q)^2$. So the series equals $1/(1-q)^2$. For the mean: $EE[X] = p sum_(k=1)^infinity k q^(k-1) = p dot 1/(1-q)^2 = p/p^2 = 1/p$. With $p = 0.2$, $q = 0.8$: $1/(1-0.8)^2 = 1/0.04 = 25$, and $EE[X] = 0.2 times 25 = 5 = 1\/0.2$. Confirmed.
]

#exercise("11.10", 3)[
A two-frame video encoder must split a budget of $R = 100$ bits between two frames. If frame 1 gets $r$ bits its distortion is $D_1(r) = 200\/(r + 1)$, and frame 2 gets the remaining $100 - r$ bits with distortion $D_2(r) = 200\/(101 - r)$. By symmetry, guess the $r$ that minimises total distortion $D_1 + D_2$, then confirm it by setting the derivative of $D_1(r) + D_2(r)$ to zero. (Use that the derivative of $200(r+1)^(-1)$ is $-200(r+1)^(-2)$.)
]
#solution("11.10")[
By symmetry the budget should split evenly, $r = 50$. To confirm, differentiate $D(r) = 200(r+1)^(-1) + 200(101 - r)^(-1)$: $D'(r) = -200(r+1)^(-2) + 200(101 - r)^(-2)$ (the second term's inner derivative $d/(d r)(101 - r) = -1$ flips the sign back to positive). Set $D'(r) = 0$: $(r+1)^(-2) = (101 - r)^(-2)$, so $r + 1 = 101 - r$, giving $2r = 100$, $r = 50$. Each frame gets 50 bits — the symmetric guess, now proven. This is *bit allocation*, the core of rate control, and it is solved by exactly the zero-slope reasoning of this chapter (Chapter 41).
]

== Further reading

- Grant Sanderson (3Blue1Brown), #link("https://www.3blue1brown.com/topics/calculus")[_Essence of Calculus_] — a free video series that builds derivatives, the chain rule, and $e$ from visual first principles; the best possible companion to this chapter's pictures.
- Silvanus P. Thompson, #link("https://www.gutenberg.org/ebooks/33283")[_Calculus Made Easy_] (1910, public domain) — the original "fear-not" calculus book, whose opening line ("What one fool can do, another can") is the spirit of this chapter; free on Project Gutenberg.
- Gilbert Strang, #link("https://ocw.mit.edu/courses/res-18-001-calculus-online-textbook-spring-2005/")[_Calculus_] (MIT OpenCourseWare, free PDF) — Chapters 1–4 for a rigorous but readable treatment of limits, derivatives, and optimisation.
- Augustin-Louis Cauchy (1847), _Méthode générale pour la résolution des systèmes d'équations simultanées_ — the two-page note that launched gradient descent; charming to skim in translation for the historical thrill of seeing the modern training loop in 19th-century French.
- David J. C. MacKay, #link("https://www.inference.org.uk/itila/book.html")[_Information Theory, Inference, and Learning Algorithms_] (Cambridge, free PDF) — read its convexity and Jensen's-inequality discussion (Chapter 2) once you have *Chapter 18* in hand, to see this chapter's "bending" become the source coding theorem.

#bridge[
Our purely-mathematical toolkit is now nearly complete: we can count, weigh chances, average, measure spread, sum endless lists, and walk downhill to a minimum. One shape of object kept appearing without a proper home — the *gradient* was a list of numbers we treated as a single arrow, and the "probability of a file" was begging to be a coordinate in some vast space. *Chapter 12 — Vectors, Matrices, and Linear Transformations* gives these lists a geometry: arrows you can add and stretch, dot products that measure alignment, and matrices that rotate and reshape whole spaces at once. That geometry is the language of the Discrete Cosine Transform that powers JPEG, of the wavelet transforms behind JPEG 2000, and of every layer of every neural network in Volume IV. After it, we will have earned every symbol Shannon is about to throw at us.
]
