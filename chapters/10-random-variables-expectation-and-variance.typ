#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Random Variables, Expectation, and Variance

#epigraph[The expected value of a quantity is the long-run average of what you would actually get if you measured it again and again.][a working definition we will earn, line by line]

Imagine a tiny game. I flip a fair coin. Heads, you win one dollar; tails, you lose one dollar. Play it once and the result is a coin-toss, literally. But play it a thousand times and something steady appears out of the noise: you end up roughly where you started, give or take. Now change the payouts. Heads pays three dollars, tails costs one. Suddenly the game is worth playing, and you can say *how much* it is worth (about one dollar per flip) before you have flipped even once.

That number, the worth-per-flip computed *before* anything happens, is the single most important idea in this chapter, and one of the most important in the whole book. It is called the *expectation*, or the *expected value*. When we finally build real compressors, the question we will ask about every code is exactly this game in disguise: "If I assign these codeword lengths to these symbols, how many bits will this cost me *on average*, per symbol, over a long file?" The average cost of a code is an expectation. The famous quantity *entropy* (the floor below which no code can squeeze) is an expectation too. Get comfortable with expectation here, on coins and dice, and the deep theorems three chapters from now will feel like old friends.

But an average alone can lie. Two games can have the very same expected payout while one is a gentle ride and the other a heart-stopping gamble. To tell them apart we need a second number that measures *spread*: how wildly the outcomes scatter around the average. That number is the *variance*, and its square root, the *standard deviation*, is the everyday "give or take" you already used a paragraph ago without naming it. Expectation tells you *where*; variance tells you *how much you can trust it*.

To talk about either, we first need a clean way to turn messy real-world outcomes (heads, tails, the letter that comes next in a file) into plain numbers we can average. That bridge is called a *random variable*. It is the first thing we build.

#recap[
In *Chapter 7* we made logarithms second nature: a logarithm is just "how many bits," and $log_2 8 = 3$ because $2^3 = 8$. In *Chapter 8* we counted: permutations, combinations, and the multiplication principle. In *Chapter 9* we built probability from coins and dice: sample spaces, events, the rule that probabilities are numbers between 0 and 1 that sum to 1, plus conditional probability and independence. This chapter stands squarely on Chapter 9: a random variable is built on a sample space, and an expectation is a probability-weighted sum. We will also lean on the $sum$ (sigma) summation notation introduced alongside the counting work; if it still feels new, the first Go-Further box below rebuilds it from scratch.
]

#objectives((
  [Explain what a _random variable_ is and tell a _discrete_ one from a _continuous_ one,],
  [Write a _probability distribution_ as a table and check that it is valid,],
  [Compute an _expectation_ (expected value) as a probability-weighted average, and read it as the average cost of a code,],
  [Use the _linearity of expectation_ to compute averages of sums without breaking a sweat,],
  [Compute _variance_ and _standard deviation_ and explain what "spread" buys you,],
  [Recognise and use the two source models we will compress all book long: the _Bernoulli_ (biased-coin) source and the _geometric_ source,],
  [State, in plain words, why expectation is the hinge between probability and every compression bound to come.],
))

== From outcomes to numbers: the random variable

Probability, as we built it in Chapter 9, deals in *outcomes*: heads or tails, the face of a die, the next byte to arrive in a file. Outcomes are not always numbers. "Heads" is not a number. But to *average* anything we need numbers, because you cannot take the average of "heads, heads, tails." So the very first move is to attach a number to every outcome. That attachment is the whole idea of a random variable.

#definition("Random variable")[
A *random variable* is a rule that assigns a number to every outcome in a sample space. We write random variables with capital letters near the end of the alphabet, like $X$, $Y$, $Z$, and the particular numbers they can take with small letters, like $x$. If the outcome is $omega$ (the Greek letter omega, our generic name for "one outcome"), then $X(omega)$ is the number the rule hands back.
]

Despite the intimidating name, a random variable is *not* random and *not* a variable in the algebra sense. It is a plain, fixed function: a lookup table from outcomes to numbers. The randomness lives in *which outcome occurs*; the rule itself never changes. Calling it a "variable" is a 100-year-old historical accident we are stuck with. Read "random variable" as "a number we read off whatever happens."

A concrete example. Flip a coin twice. The sample space, the list of everything that can happen, is

$ S = {"HH", "HT", "TH", "TT"}. $

Let $X$ be the number of heads. Then $X$ is the rule

$ X("HH") = 2, quad X("HT") = 1, quad X("TH") = 1, quad X("TT") = 0. $

The outcome "HT" is not a number, but $X("HT") = 1$ is. Now we can average heads across many double-flips, because heads has been turned into the countable numbers 0, 1, 2.

#gomaths("Summation notation: the $sum$ sign")[
We will add up long lists constantly, so we use a shorthand. The capital Greek letter sigma, $sum$, means "add these up." Underneath it you write where to start; on top, where to stop; to the right, the thing to add, with a counter that changes each step. For example,

$ sum_(i=1)^(4) i = 1 + 2 + 3 + 4 = 10. $

Read it aloud as "the sum, for $i$ running from 1 to 4, of $i$." The letter $i$ is just a counter; it disappears once the addition is done. If the thing to the right is $p_i times x_i$, then

$ sum_(i=1)^(3) p_i x_i = p_1 x_1 + p_2 x_2 + p_3 x_3. $

That single line, a sum of "probability times value," is the entire formula for expectation, so it is worth saying slowly. Sometimes we write $sum_x$ with no top or bottom, meaning "add over every value $x$ that $X$ can take." Same idea, lazier bookkeeping.
]

=== Discrete versus continuous

Random variables come in two flavours, and almost everything in this book lives in the first.

A random variable is *discrete* when its possible values can be listed one by one, even if the list never ends: 0, 1, 2, 3, ... . The number of heads in two flips (0, 1, or 2), the face of a die (1 through 6), the next byte of a file (one of 256 values), the length in bits that a code assigns to a symbol: all discrete. You can point at each value and there is a clear "next one."

A random variable is *continuous* when it can take any value in a range, with no gaps and no "next one." The exact height of a person, the precise voltage on a wire, the true brightness of a pixel before it is rounded: these can be 1.7, or 1.70001, or anything between. Between any two values there is always another.

#keyidea[
Compression is overwhelmingly a *discrete* business: files are made of bytes, codewords are made of bits, symbols come from finite alphabets. So we will spend almost all our energy on discrete random variables, where sums ($sum$) do the work. Continuous variables (needed later for the lossy, signal-processing side of the book: sampling, quantization, the Gaussian source) replace those sums with an idea from calculus called the _integral_, which we develop gently in *Chapter 11* and use seriously when we reach rate-distortion theory and transform coding. For now: list the values, attach probabilities, add.
]

#checkpoint[Is "the number of times the letter `e` appears on a randomly chosen page of a book" discrete or continuous? What about "the exact ink area, in square millimetres, covered by that letter"?][The *count* of `e`s is discrete: you can list its possible values 0, 1, 2, 3, ... . The *ink area* is continuous: it could be any real number in some range, like 4.013 mm², with no smallest gap between possibilities.]

== The probability distribution: a table of weights

Knowing the values a random variable *can* take is half the story. The other half is *how likely* each value is. That bundle (every value paired with its probability) is the *probability distribution* of the random variable. For a discrete variable we can simply write it as a table.

Back to two coin flips with $X$ = number of heads, assuming a fair coin so each of the four outcomes HH, HT, TH, TT has probability $1/4$ (this is exactly the equally-likely-outcomes reasoning from Chapter 9). We collect outcomes by the value of $X$:

#align(center, table(
  columns: (auto, auto, auto),
  inset: 7pt, align: (center, left, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Value $x$*], [*Which outcomes*], [*Probability $P(X = x)$*]),
  [0], [TT], [$1\/4$],
  [1], [HT, TH], [$2\/4 = 1\/2$],
  [2], [HH], [$1\/4$],
))

We write $P(X = x)$, read "the probability that $X$ equals $x$," for the weight on value $x$. The whole table together is often called a *probability mass function*, abbreviated *PMF*, because it tells you how much probability "mass" sits on each value. (The word "mass" is a physical metaphor: think of probability as one kilogram of clay you must distribute across the values; the PMF says how much clay goes on each.)

#definition("Probability mass function (PMF)")[
For a discrete random variable $X$, its *probability mass function* is the function $p$ defined by $p(x) = P(X = x)$, the probability that $X$ takes the particular value $x$. A valid PMF obeys two rules, both inherited directly from the probability axioms of Chapter 9:
- every weight is between 0 and 1: $0 <= p(x) <= 1$ for all $x$;
- the weights add up to exactly 1: $sum_x p(x) = 1$.
]

The second rule is just bookkeeping with a deep meaning: *something* must happen, so all the probability mass, summed, is one whole unit. In our table, $1/4 + 1/2 + 1/4 = 1$. Good. If a "distribution" someone hands you sums to $0.9$ or $1.2$, it is broken, a flag we will actually check in code in a moment.

#pitfall[
A PMF gives the probability that $X$ *equals* a value. For continuous random variables this single-value probability is always *zero* (the chance a height is *exactly* 1.700000... m, to infinite precision, is nil), so continuous variables are described by a *density* over ranges instead, not a mass on points. Do not mix the two pictures. In this chapter everything is discrete, so "the probability that $X = x$" is an honest, usually-nonzero number, and our tables are exactly right.
]

#pyrecall[
From *Chapter 16*: a Python *dictionary* (`dict`) stores key->value pairs, written with curly braces and colons, and is the natural container for a PMF: the key is the value, the stored number is its probability. `pmf[1]` looks up the weight on value `1`; `pmf.values()` hands back just the probabilities; the built-in `sum(...)` adds them; and the type hint `dict[int, float]` documents that keys are integers and values floats.

```python
# PMF of X = number of heads in two fair coin flips
pmf: dict[int, float] = {0: 0.25, 1: 0.5, 2: 0.25}

print(pmf[1])              # weight on value 1     ->  0.5
print(sum(pmf.values()))   # add all the weights   ->  1.0
```
]

Here is a small, honest function that checks whether a distribution is valid. This kind of guardrail matters in real compression code: a buggy model that does not sum to 1 will silently corrupt an arithmetic coder later on.

```python
def is_valid_pmf(pmf: dict[int, float], tol: float = 1e-9) -> bool:
    """True if every weight is in [0, 1] and they sum to 1 (within tol)."""
    for p in pmf.values():
        if p < 0.0 or p > 1.0:
            return False
    return abs(sum(pmf.values()) - 1.0) < tol

print(is_valid_pmf({0: 0.25, 1: 0.5, 2: 0.25}))   # True
print(is_valid_pmf({0: 0.3, 1: 0.5, 2: 0.3}))     # False: sums to 1.1
```

The `tol` (tolerance) argument deserves a word: because computers store fractions in finite binary, sums like $0.1 + 0.2$ can land at $0.30000000000000004$ instead of $0.3$. We will study exactly why in *Chapter 13* (floating point). For now we simply never test floats for *exact* equality; we ask whether they are within a hair (`1e-9`, i.e. $10^(-9)$) of the target. This is a habit, not a nicety. Forget it and your "valid PMF" check will reject perfectly good distributions at random.

== Expectation: the average you can compute before rolling

Now the centrepiece. The *expectation* of a random variable is its long-run average: the number you would converge to if you ran the experiment forever and averaged all the results. The miracle is that you can compute it *in advance*, from the distribution alone, without running anything.

Here is the reasoning, built from the ground up so nothing is taken on faith. Suppose you play the two-coin game $N$ times, where $N$ is huge: say a million. How many heads do you expect *on average* per game? Of those million games, about a quarter will show 0 heads, about half will show 1, about a quarter will show 2. Those are exactly the probabilities in our table. So the *total* number of heads across all games is approximately

$ underbrace((1/4 N) times 0, "the 0-head games") + underbrace((1/2 N) times 1, "the 1-head games") + underbrace((1/4 N) times 2, "the 2-head games"). $

Divide by $N$ to get the average *per game*, and the $N$ cancels everywhere:

$ "average" approx 1/4 times 0 + 1/2 times 1 + 1/4 times 2 = 0 + 1/2 + 1/2 = 1. $

So on average you get one head per two flips, which is exactly what your gut said. Notice what survived the cancellation: each *value* multiplied by its *probability*, all added up. That is the definition.

#definition("Expectation (expected value)")[
The *expectation* of a discrete random variable $X$, written $EE[X]$ (read "E of X") and sometimes $mu$ (the Greek letter mu, for "mean"), is the probability-weighted sum of its values:
$ EE[X] = sum_x x dot P(X = x) = sum_x x dot p(x). $
It is also called the *expected value*, the *mean*, or the *average* of $X$. It need not be a value $X$ can actually take.
]

That last sentence is worth a pause. The expected number of heads is 1, which *is* possible. But the expected value of a single fair die roll is

$ EE[X] = 1 times 1/6 + 2 times 1/6 + 3 times 1/6 + 4 times 1/6 + 5 times 1/6 + 6 times 1/6 = 21/6 = 3.5, $

and you will never, ever roll a 3.5. "Expected value" is a misleading name; it does *not* mean the value you should expect to see on any one roll. It means the value the *average* of many rolls homes in on. The 17th-century gamblers who invented the idea were after exactly this: the fair price of a bet, not a prediction of the next throw.

#gomaths("Weighted average vs. plain average")[
A *plain* average treats every item equally: the average of 2, 4, 9 is $(2 + 4 + 9)\/3 = 5$. A *weighted* average lets some items count more, according to weights that sum to 1. If 2 has weight $0.5$, 4 has weight $0.2$, and 9 has weight $0.3$, the weighted average is

$ 0.5 times 2 + 0.2 times 4 + 0.3 times 9 = 1.0 + 0.8 + 2.7 = 4.5. $

The plain average is just the special case where every weight is equal (here, $1\/3$ each). Expectation is precisely a weighted average where the weights are the probabilities: common values pull the average toward themselves, rare values barely tug. Keep this picture: *$EE[X]$ is the balance point of the distribution*, the spot where the table of weights would balance on a fingertip.
]

#fig([Expectation as a balance point. Bars show the probability on each value of "number of heads in two fair flips"; the triangle marks $EE[X] = 1$, the spot where the weighted seesaw balances.], cetz.canvas({
  import cetz.draw: *
  // axis
  line((0, 0), (6.4, 0), stroke: 0.8pt)
  // bars at x=1 (val 0), x=3 (val 1), x=5 (val 2)
  let bar(cx, h, lbl, plbl) = {
    rect((cx - 0.45, 0), (cx + 0.45, h), fill: rgb("#cfe0f0"), stroke: 0.6pt + rgb("#0b5394"))
    content((cx, -0.35))[#text(size: 8pt)[#lbl]]
    content((cx, h + 0.28))[#text(size: 8pt)[#plbl]]
  }
  bar(1, 1.0, [0], [1/4])
  bar(3, 2.0, [1], [1/2])
  bar(5, 1.0, [2], [1/4])
  // balance point at value 1 -> x = 3
  line((3, -0.05), (2.7, -0.7), stroke: 0.9pt + rgb("#9a2617"))
  line((3, -0.05), (3.3, -0.7), stroke: 0.9pt + rgb("#9a2617"))
  content((3, -1.05))[#text(size: 8pt, fill: rgb("#9a2617"))[$EE[X]=1$]]
  content((6.2, -0.35))[#text(size: 8pt)[value $x$]]
}))

Let us turn the definition straight into code. The expectation is a sum over the PMF of value-times-weight: a perfect job for a Python *generator expression* inside `sum`.

#pyrecall[
From *Chapter 16*: a *generator expression* `expr for item in collection`, wrapped in `sum(...)`, adds values one at a time without building a list. Here `pmf.items()` yields each `(key, value)` pair, the names `x, p` *unpack* it into value and probability, and `sum` accumulates $x times p$, which is the formula $sum_x x dot p(x)$ transcribed almost symbol-for-symbol.

```python
pmf: dict[int, float] = {0: 0.25, 1: 0.5, 2: 0.25}
mean = sum(x * p for x, p in pmf.items())
print(mean)        # 1.0
```
]

```python
def expectation(pmf: dict[float, float]) -> float:
    """E[X] = sum over values of value * probability."""
    return sum(x * p for x, p in pmf.items())

die = {1: 1/6, 2: 1/6, 3: 1/6, 4: 1/6, 5: 1/6, 6: 1/6}
print(expectation(die))                     # 3.5
print(expectation({0: 0.25, 1: 0.5, 2: 0.25}))   # 1.0
```

#tryit[
Change the die to a *loaded* one where 6 comes up half the time and the other five faces split the rest equally (each $1/10$). Predict the mean before you run it: will it move up or down from 3.5? Then check: `{1:.1,2:.1,3:.1,4:.1,5:.1,6:.5}` gives $EE[X] = (1+2+3+4+5) times 0.1 + 6 times 0.5 = 1.5 + 3.0 = 4.5$. Loading the high face dragged the balance point up, exactly as the seesaw picture predicts.
]

=== Expectation of a function: the law of the unconscious statistician

Often we do not want the average of $X$ itself but the average of *something computed from* $X$: the average of $X^2$, or the average codeword length, which is some length-function of the symbol. Do we need a whole new distribution for the new quantity? Happily, no. To average $g(X)$ (any function $g$ of $X$), you weight $g(x)$ by the *same* old probabilities:

$ EE[g(X)] = sum_x g(x) dot p(x). $

This rule has a wonderful nickname: the *law of the unconscious statistician*, because you can apply it half-asleep without re-deriving the distribution of $g(X)$. We will use it immediately for variance (where $g(x) = (x - mu)^2$) and, in Chapter 18, for entropy (where $g(x) = -log_2 p(x)$, the "surprise" of a symbol).

#keyidea[
*Expectation is the average cost of a code.* Suppose a code assigns to symbol $x$ a codeword of length $ell(x)$ bits, and symbol $x$ appears with probability $p(x)$. Then the *average number of bits per symbol* the code spends on a long file is, by the law above,
$ EE[ell(X)] = sum_x ell(x) dot p(x). $
This is *the* number that ranks codes against each other. A good code makes $EE[ell(X)]$ small by giving short codewords to common symbols and long ones to rare ones. Shannon's source coding theorem (*Chapter 19*) will prove that $EE[ell(X)]$ can never drop below a specific expectation called the *entropy*, $H(X) = sum_x p(x) log_2 (1\/p(x))$: itself the expected "surprise" per symbol. Every compression bound in this book is, underneath, a statement about an expectation. You are learning the grammar of the entire subject right now.
]

The single most useful place to turn this into running code is the *average cost of a code*, the very ruler we will judge every future compressor with. `tinyzip` has no entropy coder yet (those arrive in Volume II, and the project's first real codec, Huffman, is built in *Chapter 24*), so this is illustrative groundwork rather than a formal project step; but the function below is exactly the expectation $EE[ell(X)]$, made concrete.

```python
def avg_code_length(
    code: dict[str, str],            # symbol -> binary codeword, e.g. {"a": "0"}
    freq: dict[str, int],            # symbol -> count in the file
) -> float:
    """Expected codeword length in bits per symbol: sum p(x) * len(codeword(x))."""
    total = sum(freq.values())
    if total == 0:
        return 0.0
    return sum((freq[s] / total) * len(code[s]) for s in freq)

# A toy 4-symbol file and a hand-made prefix code.
freq = {"a": 50, "b": 25, "c": 15, "d": 10}    # 100 symbols total
code = {"a": "0", "b": "10", "c": "110", "d": "111"}
print(avg_code_length(code, freq))   # 0.5*1 + 0.25*2 + 0.15*3 + 0.10*3 = 1.75 bits/symbol
```

The probabilities here come from *counting*: `freq[s] / total` turns a raw count into an estimated probability, the empirical PMF. The result, 1.75 bits per symbol, says this code would store the 100-symbol file in about 175 bits instead of the 200 bits a flat 2-bit-per-symbol code would use. When we build a real Huffman coder in *Chapter 24*, this exact expected-length calculation will confirm that Huffman's average length sits just above the entropy floor.

== Linearity of expectation: the most useful trick in the book

Expectation has a property so handy it feels like cheating. The expectation of a *sum* of random variables is the *sum* of their expectations, and this holds *always*, whether or not the variables are independent, whether or not they interact, no matter how tangled their joint behaviour is. In symbols, for any random variables $X$ and $Y$ and any plain numbers $a$ and $b$:

$ EE[a X + b Y] = a EE[X] + b EE[Y]. $

This is *linearity of expectation*. Let us prove the heart of it, that $EE[X + Y] = EE[X] + EE[Y]$, because the proof is short, honest, and shows exactly why independence is *not* needed.

#theorem("Linearity of expectation")[
For any two random variables $X$ and $Y$ defined on the same sample space, and any constants $a, b$, we have $EE[a X + b Y] = a EE[X] + b EE[Y]$.
]

#proof[
Work outcome by outcome over the sample space $S$. Recall that the most basic form of expectation sums over *outcomes* $omega$, each weighted by its probability $P(omega)$: $EE[X] = sum_omega X(omega) P(omega)$. (This equals the value-weighted form $sum_x x p(x)$, grouping outcomes by their value to collect equal terms.) Then
$ EE[X + Y] = sum_omega (X(omega) + Y(omega)) P(omega). $
Split the sum: addition lets us regroup freely:
$ = sum_omega X(omega) P(omega) + sum_omega Y(omega) P(omega) = EE[X] + EE[Y]. $
Pulling constants out is the same one line: $EE[a X] = sum_omega a X(omega) P(omega) = a sum_omega X(omega) P(omega) = a EE[X]$. Combining gives $EE[a X + b Y] = a EE[X] + b EE[Y]$. Nowhere did we assume $X$ and $Y$ are independent, since every step is just regrouping a finite sum. #h(1fr)
]

Why is this such a gift? Because hard averages dissolve into easy ones. Watch.

*Worked example: heads in 100 flips.* Flip a fair coin 100 times; let $X$ be the total number of heads. Computing the distribution of $X$ directly means wrestling with the binomial coefficients from Chapter 8. $P(X = 50)$ involves $binom(100, 50)$, a 30-digit number. But we only want the *average*. Write $X = X_1 + X_2 + dots.c + X_(100)$, where $X_i$ is 1 if flip $i$ is heads and 0 if tails. Each $X_i$ has expectation $EE[X_i] = 1 times 1/2 + 0 times 1/2 = 1/2$. By linearity,

$ EE[X] = EE[X_1] + dots.c + EE[X_(100)] = 100 times 1/2 = 50. $

Fifty heads on average, derived in one line, with no binomial coefficients in sight. The flips happen to be independent here, but linearity would have given the same answer even if the coin had a memory.

#gomaths("Indicator random variables")[
The little $X_i$ above, "1 if this thing happens, 0 if it doesn't," is called an *indicator random variable*, because it *indicates* whether an event occurred. It is the simplest possible random variable, and it has a beautiful property: its expectation *equals the probability of the event it indicates*. If $X_i = 1$ with probability $p$ and $0$ otherwise, then
$ EE[X_i] = 1 times p + 0 times (1 - p) = p. $
So "average of an indicator" and "probability of the event" are the *same number*. This lets you compute expectations by chopping a complicated count into a sum of yes/no questions, averaging each (which is just its probability), and adding: the standard recipe powered by linearity. We will use it again the moment we meet the Bernoulli source.
]

#misconception[Expectation only adds up nicely when the random variables are independent.][Linearity of expectation *never* requires independence: the proof above regroups a sum and never multiplies probabilities. Independence is needed for a *different* rule, about *products*: $EE[X Y] = EE[X] EE[Y]$ holds only when $X$ and $Y$ are independent. And, as we will see next, independence is what makes *variances* add. Keep the three straight: sums of expectations always add; products of expectations need independence; sums of variances need independence.]

== Variance: how much the average can be trusted

Two lotteries each have an expected payout of zero dollars. In the first, every ticket wins or loses a single cent. In the second, you either lose your house or win a mansion. Same expectation, wildly different experience. Expectation alone cannot tell them apart, so we need a number for *spread*.

The natural idea: measure how far, on average, $X$ lands from its mean $mu = EE[X]$. The raw distance $X - mu$ is no good as it stands, because its average is *always zero*. The overshoots and undershoots cancel by the very definition of the balance point. To stop the cancellation we *square* the distance before averaging, turning every deviation positive. The result is the *variance*.

#theorem("Mean deviation vanishes")[
For any random variable with finite mean $mu = EE[X]$, the average deviation from the mean is zero: $EE[X - mu] = 0$.
]
#proof[
Here $mu$ is a fixed number, not random, so its expectation is itself: $EE[mu] = mu$ (a constant equals its own average). Apply linearity of expectation to the difference:
$ EE[X - mu] = EE[X] - EE[mu] = mu - mu = 0. $
This is precisely why a *raw* average deviation is useless as a spread measure. It is rigged to be zero for every distribution, which is why we must square before averaging. #h(1fr)
]

#gomaths("How constants behave under expectation and variance")[
Two small rules tidy up almost every calculation, both flowing from linearity. For any constant number $c$ (one that is not random):
- *Shifting:* adding $c$ to everything shifts the mean by $c$ but leaves the spread untouched: $EE[X + c] = EE[X] + c$, yet $"Var"(X + c) = "Var"(X)$. Sliding a distribution sideways does not change how spread out it is.
- *Scaling:* multiplying by $c$ scales the mean by $c$ and the variance by $c^2$: $EE[c X] = c thin EE[X]$ and $"Var"(c X) = c^2 "Var"(X)$. The $c^2$ appears because variance lives in *squared* units; the standard deviation, back in normal units, scales by plain $abs(c)$: $sigma_(c X) = abs(c) thin sigma_X$.

Tiny check with the fair die ($mu = 3.5$, $sigma approx 1.71$): double every face to make a 2-4-6-8-10-12 die. Its mean is $2 times 3.5 = 7$ and its standard deviation is $2 times 1.71 = 3.42$, both doubled, exactly as the scaling rule promises. These rules are the workhorses behind the $sigma\/sqrt(n)$ law you are about to meet.
]

#definition("Variance and standard deviation")[
The *variance* of a random variable $X$ with mean $mu = EE[X]$ is the expected squared deviation from the mean:
$ "Var"(X) = EE[(X - mu)^2] = sum_x (x - mu)^2 dot p(x). $
It is often written $sigma^2$ (sigma squared). Because we squared, variance carries *squared units* (dollars², bits²), which is awkward to interpret, so we usually take its square root to get back to the original units. That square root is the *standard deviation*:
$ sigma = sqrt("Var"(X)). $
The standard deviation is the honest "give or take": the typical distance of $X$ from its mean.
]

*Worked example: the two dice.* Take an ordinary fair die ($mu = 3.5$). Its variance is
$ "Var"(X) = (1 - 3.5)^2 dot 1/6 + (2 - 3.5)^2 dot 1/6 + dots.c + (6 - 3.5)^2 dot 1/6. $
The squared deviations are $6.25, 2.25, 0.25, 0.25, 2.25, 6.25$, summing to $17.5$; divide by 6 to get $"Var"(X) = 17.5\/6 approx 2.92$, so $sigma approx 1.71$. A roll typically lands about 1.7 away from 3.5, which matches intuition. Now imagine a strange die painted with three 1s and three 6s. Its mean is still $3.5$, but every roll is $2.5$ away, so $"Var" = 2.5^2 = 6.25$ and $sigma = 2.5$. Same mean, larger spread: exactly the lottery distinction, now quantified.

=== A faster formula (and a clean proof)

Computing variance straight from the definition means knowing $mu$ first, then sweeping the data a second time to accumulate squared deviations. There is a one-pass shortcut, and proving it is a tidy exercise in the tools we just built.

#theorem("Computational formula for variance")[
$ "Var"(X) = EE[X^2] - (EE[X])^2. $
In words: the variance is "the mean of the square minus the square of the mean."
]

#proof[
Start from the definition and expand the squared bracket, treating $mu = EE[X]$ as the constant it is:
$ "Var"(X) = EE[(X - mu)^2] = EE[X^2 - 2 mu X + mu^2]. $
Now apply linearity of expectation, which lets us split the sum and pull constants ($mu$ and $mu^2$) outside:
$ = EE[X^2] - 2 mu thin EE[X] + mu^2. $
But $EE[X] = mu$, so the middle term is $-2 mu dot mu = -2 mu^2$, and the formula collapses:
$ = EE[X^2] - 2 mu^2 + mu^2 = EE[X^2] - mu^2 = EE[X^2] - (EE[X])^2. $
#h(1fr)
]

Let us re-do the fair die with the shortcut. We need $EE[X^2] = sum x^2 p(x) = (1 + 4 + 9 + 16 + 25 + 36)\/6 = 91\/6 approx 15.17$. Then $"Var"(X) = 15.17 - 3.5^2 = 15.17 - 12.25 = 2.92$. Same answer, one pass. (A caution for *Chapter 13*: on a computer, this fast formula can lose accuracy when $EE[X^2]$ and $(EE[X])^2$ are both large and nearly equal. Subtracting two big close numbers magnifies rounding error. For teaching it is perfect; production statistics often prefer a numerically stabler method. We flag it now and return to it when we study floating point.)

We can compute both moments in a single sweep and combine them. The function returns *two* numbers at once as a *tuple* (the comma-separated bundle from *Chapter 16*), which the caller unpacks with a matching comma:

```python
def mean_and_variance(pmf: dict[float, float]) -> tuple[float, float]:
    mu  = sum(x * p for x, p in pmf.items())          # E[X]
    ex2 = sum(x * x * p for x, p in pmf.items())       # E[X^2]
    return mu, ex2 - mu * mu                            # (mean, variance)

die = {k: 1/6 for k in range(1, 7)}
mu, var = mean_and_variance(die)        # unpack the returned tuple
print(mu, var)                          # 3.5  2.9166666666666665
```

#pyrecall[
From *Chapter 16*: `{k: 1/6 for k in range(1, 7)}` is a *dict comprehension* that builds the die's PMF on the fly, pairing each face `k` in `range(1, 7)` (the integers 1 through 6) with weight `1/6`. The return type hint `tuple[float, float]` documents that two floats come back, and tuple unpacking, `mu, var = ...`, splits them across two names, the same move used on `pmf.items()` above.
]

=== Variance of a sum, and why $sqrt(n)$ rules the world

Variances do not always add. When the pieces are *independent*, they do:

$ "Var"(X + Y) = "Var"(X) + "Var"(Y) quad ("only if " X, Y " independent"). $

This single fact explains a pattern you will meet again and again in compression and in life. Suppose you average $n$ independent measurements, each with variance $sigma^2$. The *sum* has variance $n sigma^2$ (variances add). The *average* divides the sum by $n$; and scaling a variable by a constant $c$ multiplies its variance by $c^2$ (because variance lives in squared units), so dividing by $n$ multiplies the variance by $1\/n^2$. Net result: the average of $n$ independent measurements has variance $n sigma^2 dot (1\/n^2) = sigma^2 \/ n$, hence standard deviation

$ sigma_"average" = sigma \/ sqrt(n). $

The spread of an average shrinks like one over the *square root* of the sample size. Want to halve your uncertainty? You need *four* times as much data. This $sqrt(n)$ law is why a long file's measured symbol frequencies converge to the true probabilities (so our `freq[s] / total` estimates get trustworthy as files grow), why benchmark timings need many runs to stabilise, and why the "law of large numbers" (the promise that averages settle down) has teeth. We will lean on it the moment we argue that entropy is achievable *on average* over long messages.

#note[
There is a quick quantitative version of "the average settles down" called *Chebyshev's inequality*: for any random variable, the probability of landing more than $k$ standard deviations from the mean is at most $1\/k^2$. So *at most* a quarter of the time are you beyond 2sigma, at most a ninth beyond 3sigma: true for *every* distribution, no bell-curve assumption needed. It is the blunt-instrument guarantee behind the law of large numbers, and we will sharpen it into the "typical set" (the small club of probable messages that carries essentially all the probability) when we prove the source coding theorem in *Chapter 19*.
]

#checkpoint[A code spends 1.75 bits per symbol on average, with a standard deviation of 0.9 bits per symbol on a single symbol. You encode a file of 10 000 symbols. Very roughly, how tightly does the *total* size cluster around $10000 times 1.75 = 17500$ bits?][Total bits is a sum of 10 000 (roughly independent) per-symbol costs, so its variance is about $10000 times 0.9^2$ and its standard deviation about $sqrt(10000) times 0.9 = 100 times 0.9 = 90$ bits. The total clusters around 17 500 bits give-or-take ~90 bits, a relative wobble of about half a percent. The per-symbol cost is noisy, but the $sqrt(n)$ law makes the *file* size remarkably predictable. This is why average code length is such a useful single number.]

== Two sources we will compress all book long

Compression is the art of modelling the source that produced your data and exploiting that model. Two probability distributions show up so often that they deserve names and faces now, so that later chapters can say "geometric source" without ceremony. Both are discrete; both have tidy expectations and variances we can derive with the tools above.

=== The Bernoulli source: the biased coin

A *Bernoulli random variable* is the humblest of all: it is 1 with probability $p$ and 0 with probability $1 - p$. That is the whole thing, a single biased coin flip, the indicator variable from earlier promoted to centre stage. Its parameter $p$ is the probability of the "1" (often called a "success").

#definition("Bernoulli distribution")[
$X$ is *Bernoulli with parameter $p$*, written $X tilde "Bernoulli"(p)$, when $P(X = 1) = p$ and $P(X = 0) = 1 - p$, for some $p$ with $0 <= p <= 1$. (The squiggle $tilde$ is read "is distributed as"; $X tilde "Bernoulli"(p)$ just says "$X$ follows the Bernoulli distribution with parameter $p$": a standard shorthand we will reuse for every named distribution.)
]

Its expectation and variance fall straight out of our formulas:
$ EE[X] = 1 dot p + 0 dot (1 - p) = p, quad EE[X^2] = 1^2 dot p + 0^2 dot (1-p) = p, $
$ "Var"(X) = EE[X^2] - (EE[X])^2 = p - p^2 = p(1 - p). $

That variance $p(1-p)$ tells a story. It is zero when $p = 0$ or $p = 1$, meaning a coin that always lands the same way has no spread and, crucially, no surprise and nothing to compress beyond a constant. It is largest at $p = 1/2$, the fair coin, where outcomes are maximally unpredictable. That peak at $p = 1/2$ is your first glimpse of a theme the entropy chapters will hammer home: *a fair coin is the hardest thing to compress*. A stream of bits that is 99% zeros (a sparse bitmap, a black-and-white scan, the sign bits of quiet audio) is a Bernoulli source with small $p$: low variance, low entropy, gloriously squeezable. We will compress exactly such streams with run-length and arithmetic coding in Volume II.

#aside[The distribution is named for Jacob Bernoulli (1655--1705), whose posthumous 1713 book _Ars Conjectandi_ ("The Art of Conjecturing") contained the first law of large numbers: the original proof that averages of many trials settle toward the expectation. The biased coin you just met is, in a real sense, where mathematical probability began.]

=== The geometric source: waiting for the first success

Now flip that biased coin *repeatedly* and ask: how many flips until the first head? You might get a head immediately (1 flip), or after a tail then a head (2 flips), or after a long unlucky run. The count of flips up to and including the first success is a *geometric random variable*. Its values are $1, 2, 3, dots$, unbounded, a first example of a discrete variable with infinitely many possible values.

To get the probability of exactly $k$ flips, you need $k - 1$ failures (each with probability $1 - p$) followed by one success (probability $p$). Because flips are independent, you *multiply* (the independence-means-multiply rule from Chapter 9):

$ P(X = k) = (1 - p)^(k - 1) dot p, quad k = 1, 2, 3, dots $

#definition("Geometric distribution")[
$X$ is *geometric with parameter $p$*, written $X tilde "Geometric"(p)$, when $P(X = k) = (1-p)^(k-1) p$ for $k = 1, 2, 3, dots$. It models the number of independent trials, each succeeding with probability $p$, up to and including the first success. Its expectation is
$ EE[X] = 1 / p, $
and its variance is $"Var"(X) = (1 - p) \/ p^2$.
]

The mean $1\/p$ is wonderfully intuitive: if a head comes up one time in ten ($p = 0.1$), you wait *ten* flips on average. If success is certain ($p = 1$), you wait exactly one. (The geometric series that proves $EE[X] = 1\/p$, adding up $k (1-p)^(k-1) p$ over all $k$, uses the infinite-sum machinery we develop in *Chapter 11*; we quote the result here and prove it there, so the Prime Directive is kept.)

The variance $(1-p)\/p^2$ tells the same story from the spread side. When success is rare ($p$ small), $p^2$ in the denominator is tiny, so the variance balloons: not only do you *wait long on average*, but your waits are wildly unpredictable, sometimes a quick success, sometimes a punishing drought. When $p -> 1$ the variance falls to 0: a sure thing has no spread. Concretely, for $p = 0.1$ the mean is 10 flips but the standard deviation is $sqrt(0.9)\/0.1 approx 9.5$ flips, almost as large as the mean itself, a hallmark of these long-tailed waiting times. This heavy tail is precisely why a code for geometric data must be prepared, however rarely, for a large value, and it is what Golomb-Rice codes handle gracefully.

#fig([The geometric distribution with $p = 0.4$. Probability decays by a constant factor $(1-p)$ at every step: each bar is $0.6 times$ the one before. This steady exponential decay is exactly the shape Golomb-Rice codes are built to match.], cetz.canvas({
  import cetz.draw: *
  line((0, 0), (7.2, 0), stroke: 0.8pt)
  let p = 0.4
  let q = 0.6
  let prob = p
  for k in range(0, 7) {
    let cx = 0.6 + k * 0.95
    let h = prob * 5.0
    rect((cx - 0.3, 0), (cx + 0.3, h), fill: rgb("#d9ead3"), stroke: 0.6pt + rgb("#0b6e4f"))
    content((cx, -0.32))[#text(size: 8pt)[#(k + 1)]]
    prob = prob * q
  }
  content((3.6, -0.78))[#text(size: 8pt)[number of flips until first head, $k$]]
}))

Why does the geometric distribution matter so much for compression? Because *residuals*, the small leftover errors after a predictor has done its best, are very often geometric (or its symmetric cousin, the two-sided Laplacian). When you predict each pixel from its neighbour, or each audio sample from the last one (Chapter 40's differential coding), most predictions are nearly right, so most residuals are 0 or $plus.minus 1$, and large residuals get exponentially rarer: precisely the geometric shape. There is a family of codes, *Golomb-Rice codes* (*Chapter 25*), that is provably optimal for geometric sources, which is why it shows up inside FLAC, JPEG-LS, and countless sensor and time-series compressors. The distribution you just met is the reason those codes exist.

#gopython("Building the geometric PMF (and a runaway-tail caution)")[
A geometric distribution has infinitely many values, but its tail decays exponentially, so in practice we *truncate* once the leftover probability is negligible. A `while` loop with the walrus operator `:=` (which assigns *and* tests in one breath: recall it from *Chapter 15*) does this neatly:

```python
def geometric_pmf(p: float, cutoff: float = 1e-6) -> dict[int, float]:
    """PMF of Geometric(p), truncated once weights fall below cutoff."""
    pmf: dict[int, float] = {}
    k = 1
    while (weight := (1 - p) ** (k - 1) * p) > cutoff:
        pmf[k] = weight
        k += 1
    return pmf

g = geometric_pmf(0.4)
print(len(g))                       # ~22 values cover essentially all the mass
print(round(sum(g.values()), 6))    # ~1.0 (a sliver of tail is dropped)
print(round(expectation(g), 3))     # ~2.5  ==  1/p  ==  1/0.4
```

The expression `(weight := ...)` computes the next bar's probability, stores it in `weight`, and immediately compares it to `cutoff`, so the loop stops automatically once the bars become invisibly small. The recovered mean, $2.5$, matches $1\/p = 1\/0.4$ to three decimals, confirming both our formula and our code. Truncating an infinite distribution is a real compression skill: every practical entropy coder caps its tables somewhere and accounts for the dropped mass.
]

== The throughline: expectation is the language of compression

Step back and notice what we have actually assembled. A *random variable* turns outcomes into numbers. A *distribution* weights those numbers. An *expectation* averages a quantity against those weights, and the quantity we will care about, over and over, is *codeword length in bits*. Compression, reduced to a slogan, is: *choose codeword lengths $ell(x)$ to make $EE[ell(X)] = sum_x p(x) ell(x)$ as small as possible.* Everything else (Huffman trees, arithmetic coding, ANS, the whole tower of Volume II) is engineering in service of that one expectation.

And the floor on that expectation has a name you can now parse symbol by symbol. Shannon defined the *entropy* of a source as

$ H(X) = EE[-log_2 p(X)] = sum_x p(x) dot log_2 (1 / p(x)). $

Read it with the eyes this chapter gave you. The term $log_2(1\/p(x))$ is the *surprise* of seeing symbol $x$: large for rare symbols, small for common ones, measured in bits because it is a base-2 logarithm (Chapter 7). Entropy is the *expectation of surprise*: the average number of bits of genuine information per symbol. It is just another weighted average, computed by the very same $sum_x (dots) p(x)$ pattern as $EE[X]$ and $"Var"(X)$. When Chapter 18 unveils entropy and Chapter 19 proves no code beats it, you will not be meeting a new kind of object. You will only be feeding a new function into the averaging machine you built today.

#history[
The expectation is older than calculus. In 1654, prompted by a gambler's puzzle about how to split the stakes of an interrupted game, Blaise Pascal and Pierre de Fermat exchanged letters that founded probability, and the quantity they computed was the *fair value* of each player's position: an expectation. Christiaan Huygens turned their correspondence into the first printed treatise on probability in 1657, _De Ratiociniis in Ludo Aleae_ ("On Reasoning in Games of Chance"), whose very first proposition is a rule for expected value. Variance came much later, named by Ronald Fisher in 1918. So when you compute the average cost of a code, you are using a tool refined over three and a half centuries, first to price bets, eventually to price *bits*.
]

#keyidea[
One last connection, quietly important. Entropy is an expectation of a *curved* function of the probabilities (the logarithm), and curved functions interact with averaging in a one-sided way captured by *Jensen's inequality*: roughly, "the average of a curve is below the curve of the average" for a downward-bending (concave) function like $log$. That single inequality is the engine behind two pillars to come: the proof that entropy is the true lower bound on code length (*Chapter 19*), and the proof that the cross-entropy of a *wrong* model always exceeds the true entropy (*Chapter 23*), which is exactly why a better predictor compresses better. We will build Jensen's inequality carefully when we need it; file it away as "averaging and bending do not commute, and compression lives in the gap."
]

#takeaways((
  [A _random variable_ is a fixed rule turning each outcome into a number; it is neither random nor a variable. _Discrete_ ones (our bread and butter) take listable values; _continuous_ ones fill a range and wait for calculus.],
  [A _probability distribution_ (PMF for discrete variables) pairs each value with a weight; valid weights lie in $[0,1]$ and sum to 1.],
  [_Expectation_ $EE[X] = sum_x x thin p(x)$ is the probability-weighted average, the balance point of the distribution and the number you converge to over many trials.],
  [The average cost of a code, $EE[ell(X)] = sum_x p(x) ell(x)$, is an expectation; minimising it is the whole job of an entropy coder, and entropy $H(X) = EE[-log_2 p(X)]$ is the same machine applied to surprise.],
  [_Linearity of expectation_ ($EE[a X + b Y] = a EE[X] + b EE[Y]$) holds always, independence or not, and turns hard averages into easy ones via indicator variables.],
  [_Variance_ $"Var"(X) = EE[(X-mu)^2] = EE[X^2] - mu^2$ measures spread; its root, the _standard deviation_ $sigma$, is the honest "give or take." Independent variances add, so an average's spread shrinks like $sigma\/sqrt(n)$.],
  [The _Bernoulli($p$)_ source (biased coin) has mean $p$ and variance $p(1-p)$, peaking in unpredictability at $p=1\/2$. The _Geometric($p$)_ source (wait-for-first-success) has mean $1\/p$ and an exponentially decaying tail: the natural shape of prediction residuals and the reason Golomb-Rice codes exist.],
))

== Exercises

#exercise("10.1", 1)[
A four-sided die (faces 1--4) is fair. Let $X$ be the face shown. Write the PMF as a table, verify it sums to 1, and compute $EE[X]$ by hand.
]
#solution("10.1")[
Each face has probability $1\/4$, so the PMF is $P(X=k) = 1\/4$ for $k in {1,2,3,4}$; the weights sum to $4 times 1\/4 = 1$. The expectation is $EE[X] = (1+2+3+4) times 1\/4 = 10\/4 = 2.5$. As with the six-sided die, the mean ($2.5$) is not a face the die can show: it is the balance point.
]

#exercise("10.2", 1)[
A coin lands heads with probability $0.8$. Let $X = 1$ for heads, $0$ for tails. Compute $EE[X]$ and $"Var"(X)$. Is this coin easier or harder to compress than a fair one, and why?
]
#solution("10.2")[
This is Bernoulli($0.8$): $EE[X] = 0.8$ and $"Var"(X) = p(1-p) = 0.8 times 0.2 = 0.16$. A fair coin has variance $0.5 times 0.5 = 0.25$, larger. The biased coin is *easier* to compress: its outcomes are more predictable (mostly heads), so it carries less surprise per flip and a good coder can spend well under one bit per flip on average. Maximum variance, and maximum incompressibility, occur at $p = 1\/2$.
]

#exercise("10.3", 2)[
A simple file uses four symbols with probabilities $p(a)=0.5$, $p(b)=0.25$, $p(c)=0.125$, $p(d)=0.125$. Two codes are proposed. Code A: `a`->`0`, `b`->`10`, `c`->`110`, `d`->`111`. Code B: a flat 2 bits each. Compute the expected bits per symbol for each and say which wins.
]
#solution("10.3")[
Code A: $EE[ell] = 0.5(1) + 0.25(2) + 0.125(3) + 0.125(3) = 0.5 + 0.5 + 0.375 + 0.375 = 1.75$ bits/symbol. Code B: $EE[ell] = 2$ bits/symbol flat. Code A wins, saving $0.25$ bits per symbol on average by giving the common symbol `a` a short codeword. (Bonus: the entropy here is $0.5(1) + 0.25(2) + 0.125(3) + 0.125(3) = 1.75$ bits too: Code A is *optimal*, hitting the floor exactly, because every probability is a power of $1\/2$.)
]

#exercise("10.4", 2)[
Prove, using linearity of expectation only, that for the sum $S = X_1 + dots.c + X_n$ of $n$ Bernoulli($p$) indicators, $EE[S] = n p$. Why does the argument not require the flips to be independent?
]
#solution("10.4")[
Each indicator has $EE[X_i] = 1 dot p + 0 dot (1-p) = p$. By linearity, $EE[S] = EE[X_1] + dots.c + EE[X_n] = underbrace(p + dots.c + p, n "times") = n p$. Linearity regroups a single sum over outcomes (see the chapter's proof) and never multiplies probabilities, so it holds regardless of dependence: the $X_i$ could be correlated and $EE[S] = n p$ would still stand. (Independence *would* be needed to compute $"Var"(S) = n p(1-p)$, which relies on variances adding.)
]

#exercise("10.5", 2)[
Use the computational formula $"Var"(X) = EE[X^2] - (EE[X])^2$ to find the variance of a Bernoulli($p$) variable, and confirm it equals $p(1-p)$.
]
#solution("10.5")[
For Bernoulli($p$), values are 0 and 1, so $X^2 = X$ (since $0^2 = 0$ and $1^2 = 1$). Hence $EE[X^2] = EE[X] = p$. Then $"Var"(X) = EE[X^2] - (EE[X])^2 = p - p^2 = p(1 - p)$, matching the chapter. The trick $X^2 = X$ for 0/1 variables is worth remembering: it reappears whenever indicators are involved.
]

#exercise("10.6", 2)[
A geometric source has $p = 0.25$. Without summing an infinite series, state $EE[X]$. Then estimate how many flips you would need before the probability of *still* waiting drops below 1%.
]
#solution("10.6")[
$EE[X] = 1\/p = 1\/0.25 = 4$ flips on average. The probability of still waiting after $k$ flips is the chance of $k$ straight failures, $(1-p)^k = 0.75^k$. We want $0.75^k < 0.01$. Taking $log_2$ of both sides (Chapter 7): $k > log_2(0.01) \/ log_2(0.75) approx (-6.64) \/ (-0.415) approx 16$. So after about 16 flips, fewer than 1% of trials are still waiting: the exponential tail dies fast, which is exactly why geometric residuals compress so well.
]

#exercise("10.7", 2)[
Write a Python function `entropy(pmf: dict[str, float]) -> float` that returns $H(X) = sum_x p(x) log_2(1\/p(x))$, skipping any symbol with probability 0 (since $0 times log_2(1\/0)$ is defined as 0). Test it on a fair coin (`{"H":0.5,"T":0.5}`) and confirm it returns 1.0.
]
#solution("10.7")[
```python
from math import log2

def entropy(pmf: dict[str, float]) -> float:
    return sum(p * log2(1 / p) for p in pmf.values() if p > 0.0)

print(entropy({"H": 0.5, "T": 0.5}))   # 1.0
print(entropy({"H": 0.8, "T": 0.2}))   # ~0.7219 -- less than 1, biased coin
```
The `if p > 0.0` guard skips zero-probability symbols, avoiding division by zero, and matches the mathematical convention $0 log 0 = 0$. The fair coin returns exactly 1.0 bit (its maximum) while the biased coin returns less, confirming that predictability lowers entropy. This is the same `sum(... for ...)` pattern as `expectation`, fed surprise instead of value.
]

#exercise("10.8", 3)[
Show that among all Bernoulli sources, variance $p(1-p)$ is maximised at $p = 1\/2$. (Hint: you may use the fact, from the gentle calculus to come, that a smooth function peaks where its slope is zero; or argue by symmetry and trying values.)
]
#solution("10.8")[
By symmetry, $p(1-p)$ is unchanged if you swap $p$ and $1-p$, so any maximum must sit at the symmetric point $p = 1\/2$. Checking: $f(p) = p - p^2$ has slope $f'(p) = 1 - 2p$ (using the derivative rules of *Chapter 11*), which is zero exactly at $p = 1\/2$, and the function bends downward, so that point is a maximum. The value there is $1\/2 times 1\/2 = 1\/4$, larger than at any other $p$ (e.g. $0.8 times 0.2 = 0.16$). The fair coin is both maximally variable and, as the entropy chapters confirm, maximally incompressible.
]

#exercise("10.9", 3)[
You estimate a symbol's probability by counting its occurrences in a file of $n$ symbols. Treat each position as an independent Bernoulli($p$) indicator for "is this the symbol?". Using the $sigma\/sqrt(n)$ law, explain why the *estimated* probability $hat(p) = "count"\/n$ becomes more trustworthy as the file grows, and roughly how many symbols you need to pin $hat(p)$ to within $plus.minus 0.01$ of the truth when $p approx 0.5$.
]
#solution("10.9")[
The count is a sum of $n$ independent Bernoulli($p$) indicators, with variance $n p(1-p)$; dividing by $n$ gives $hat(p)$ a variance of $p(1-p)\/n$, hence standard deviation $sqrt(p(1-p)\/n)$. As $n$ grows, this shrinks like $1\/sqrt(n)$, so $hat(p)$ homes in on $p$. To reach $sigma approx 0.01$ at $p = 0.5$: solve $sqrt(0.25\/n) = 0.01$, i.e. $0.25\/n = 0.0001$, so $n = 2500$. About 2 500 symbols pin the probability to roughly $plus.minus 0.01$. This is precisely why adaptive compressors trust their statistics more as a file unfolds, and why they are shaky at the very start.
]

#exercise("10.10", 3)[
A "two-sided geometric" (a crude Laplacian) models prediction residuals: $P(X = 0) = a$, and for each $m = 1, 2, 3, dots$, $P(X = m) = P(X = -m) = b dot r^(m)$ for some decay $0 < r < 1$. Argue from symmetry that $EE[X] = 0$, and explain in words why this distribution (peaked at 0, symmetric, exponentially decaying) is the ideal customer for a compressor that codes small numbers in few bits.
]
#solution("10.10")[
For every positive value $m$ with weight $b r^m$ there is a mirror-image value $-m$ with the *same* weight, so in the sum $EE[X] = sum_x x p(x)$ the terms $(+m)(b r^m)$ and $(-m)(b r^m)$ cancel in pairs, and the $x = 0$ term contributes nothing. Hence $EE[X] = 0$. The distribution is ideal for compression because almost all its mass sits on 0 and $plus.minus 1$ (a good predictor is usually nearly right), and large residuals are exponentially rare. A code that spends very few bits on small magnitudes and progressively more on large ones, exactly what Golomb-Rice and signed-Exp-Golomb codes (*Chapter 25*) do, therefore achieves a tiny *expected* length. This is the statistical reason predict-then-residual-code pipelines (JPEG-LS, FLAC, video motion residuals) work.
]

== Further reading

- #link("https://www.youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab")[Grant Sanderson (3Blue1Brown), _Probability_ series] -- superb visual intuition for distributions, expectation, and the law of large numbers, free on YouTube.
- Charles M. Grinstead and J. Laurie Snell, #link("https://math.dartmouth.edu/~prob/prob/prob.pdf")[_Introduction to Probability_] (open access, AMS) -- chapters 1, 6, and 8 cover discrete random variables, expectation, variance, and the law of large numbers rigorously yet readably.
- Thomas M. Cover and Joy A. Thomas, _Elements of Information Theory_ (2nd ed., Wiley, 2006), Chapter 2 -- the canonical bridge from expectation to entropy; read it after *Chapter 18* to see today's tools become information theory.
- Christiaan Huygens, _De Ratiociniis in Ludo Aleae_ (1657) -- the first printed treatise on probability, whose opening proposition is the expected-value rule; charming to skim in translation for the historical thrill.
- David J. C. MacKay, #link("https://www.inference.org.uk/itila/book.html")[_Information Theory, Inference, and Learning Algorithms_] (Cambridge, free PDF), Chapter 2 -- distributions and expectations framed from the very start as tools for compression and inference.

#bridge[
We can now turn outcomes into numbers, weigh them, average them, and measure their spread, and we have seen that the average cost of a code, and entropy itself, are nothing more exotic than expectations. But several quantities we leaned on were quietly deferred: the geometric series that gives $EE[X] = 1\/p$, the meaning of a function's *slope* that lets us find where variance peaks, and the smooth bending of the logarithm behind Jensen's inequality. *Chapter 11: Sequences, Sums, and a Gentle Calculus* pays those debts. It demystifies $sum$ and $product$ once and for all, tames infinite sums, and builds just enough calculus (slopes, limits, optimisation, and a first gradient) to carry us through rate-distortion optimisation and, much later, the training of neural compressors. After that, our mathematical toolkit is complete enough to meet Shannon head-on.
]
