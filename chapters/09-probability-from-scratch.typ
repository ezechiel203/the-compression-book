#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Probability From Scratch

#epigraph[The theory of probabilities is at bottom nothing but common sense reduced to calculus.][Pierre-Simon Laplace, _Théorie analytique des probabilités_, 1812]

A friend offers you a bet. They will flip a fair coin three times. If it comes up heads at least twice, you win a dollar; otherwise you pay a dollar. Should you take it? A second friend, less honest, says: "I just flipped a coin twice and at least one was heads. What's the chance _both_ were heads?" Most people blurt out "one half" — and most people are wrong. A third friend, a doctor, tells you a test for a rare disease is "99% accurate," you test positive, and you panic — even though there is an excellent chance you are perfectly healthy.

These three little puzzles share one secret. Each is really a question about _counting the ways the world could be_ and asking what fraction of those ways match what you care about. That is the whole of probability. By the end of this chapter you will solve all three from first principles, with nothing more than fractions and careful bookkeeping — and you will see, in the final section, why a coin that is _predictable_ is a coin that can be _compressed_, and a coin that is perfectly unpredictable cannot be compressed at all.

This is one of the most important chapters in Volume I. Everything we build later — entropy, the source coding theorem, arithmetic coding, the claim that a good language model is a good compressor — is written in the language of probability. We are going to learn that language slowly, from coins and dice, assuming you have never seen it before.

#recap[
In Chapter 7 we met logarithms, and saw the strange promise that "a bit is a logarithm." In Chapter 8 we learned to _count_: the multiplication principle (if one choice has $m$ options and the next has $n$, together they have $m times n$), permutations and combinations, and the pigeonhole bound that proves no compressor can shrink every file. Probability is built directly on top of that counting machinery. Where Chapter 8 asked _"how many ways?"_, this chapter asks _"what fraction of those ways?"_ — and that fraction, between 0 and 1, is a probability. Keep your combinations $binom(n, k)$ close at hand; we will lean on them constantly.
]

#objectives((
  [State precisely what a _sample space_, an _event_, and a _probability_ are, and compute probabilities by counting equally likely outcomes.],
  [Use the three axioms of probability (Kolmogorov, 1933) and derive the addition rule, the complement rule, and the inclusion–exclusion formula.],
  [Define and compute _conditional probability_ $P(A | B)$, recognise _independence_, and avoid the classic traps that fool almost everyone.],
  [State and apply _Bayes' rule_, and use it to overturn your gut feeling about the "99% accurate" medical test.],
  [Connect a probability distribution to _surprise_ and _predictability_ — the bridge that carries us into information theory and the whole rest of the book.],
))

== What probability measures, and where it comes from

Start with the simplest random thing in the world: a coin. We flip it. Before it lands we do not know what it will show. After it lands we do. Probability is a number we attach _before_ — a number that captures how strongly we should expect each possible result.

Here is the first idea, and it is almost embarrassingly simple. List every outcome that could happen, in a way that leaves nothing out and counts nothing twice. For a single coin flip, that list is just two things: _heads_ and _tails_. We write the list as a set:

$ S = {"heads", "tails"}. $

#definition("Sample space")[The *sample space* $S$ of an experiment is the set of all possible outcomes, where every run of the experiment produces exactly one of them. Each member of $S$ is an *outcome* (or *sample point*).]

#gomaths("Sets and the symbols ∈ and |·|")[
A *set* is just a collection of distinct things, written between curly braces. The order does not matter and repeats are not allowed: ${"heads", "tails"}$ and ${"tails", "heads"}$ are the same set. Chapter 6 built sets carefully; here we only need three pieces of notation.

The symbol $in$ means *"is an element of."* So $"heads" in S$ reads "heads is in the set $S$." The notation $abs(S)$ (vertical bars around a set) means *the size of the set* — how many elements it has. For our coin, $abs(S) = 2$. The empty set, written $emptyset$, is the set with nothing in it, so $abs(emptyset) = 0$.

A tiny example. If $S = {1, 2, 3, 4, 5, 6}$ (the faces of a die), then $3 in S$ is true, $7 in S$ is false, and $abs(S) = 6$.
]

Now, the thing we usually _care_ about is rarely a single outcome. We care about questions like "did the die show an even number?" An even number could be a 2, a 4, or a 6 — three different outcomes, all of which make the answer "yes." We bundle those together into an *event*.

#definition("Event")[An *event* is any subset of the sample space — any collection of outcomes we have grouped together because we care about whether one of them happened. The event "the die is even" is the subset ${2, 4, 6}$. An event *occurs* on a given run if the outcome that happened is one of the outcomes in the event.]

So far this is pure vocabulary. Where does the actual _number_ — the probability — come from? In the friendliest case, every outcome is equally likely, and then probability is nothing but a fraction.

#keyidea[
When all outcomes in the sample space are *equally likely*, the probability of an event $A$ is the count of outcomes in $A$ divided by the count of outcomes in all of $S$:
$ P(A) = abs(A) / abs(S) = ("number of outcomes where " A "happens") / ("total number of outcomes"). $
This is sometimes called the *classical definition* of probability, going back to Laplace. It turns every probability question into a counting question — which is exactly why we spent Chapter 8 learning to count.
]

Let us use it immediately. A fair die has $S = {1,2,3,4,5,6}$, so $abs(S) = 6$. The event "even" is $A = {2,4,6}$, so $abs(A) = 3$, and

$ P("even") = 3 / 6 = 1 / 2. $

The event "rolls a number greater than 4" is $B = {5, 6}$, so $P(B) = 2 \/ 6 = 1\/3$. The event "rolls a 7" is the empty set $emptyset$ (impossible on a six-sided die), so its probability is $0 \/ 6 = 0$. And the event "rolls some number from 1 to 6" is all of $S$, with probability $6 \/ 6 = 1$.

Notice what just happened: probabilities came out between 0 and 1, with 0 meaning _impossible_ and 1 meaning _certain_. That is not a coincidence — it is forced by the definition, since $abs(A)$ can never be negative and can never exceed $abs(S)$. These two anchors, 0 for impossible and 1 for certain, are worth burning into memory now.

#pitfall[
The fraction-counting rule works *only when the outcomes are equally likely.* A common blunder: "A basketball game ends in a win or a loss, that's two outcomes, so the probability of winning is one half." Nonsense — the two outcomes are not equally likely (it depends on the teams!). Equally-likely counting is the right tool for fair coins, fair dice, well-shuffled cards, and lottery balls. For anything else we will need probabilities that come from data or from a model, not from naive counting. Keep this caveat in your pocket; it returns the moment we talk about real data.
]

#aside[
The word "probability" hides a genuine philosophical fork that working compression engineers quietly step over every day. One camp (the *frequentists*) says $P(A)$ is the long-run fraction of times $A$ happens if you repeat the experiment forever. Another camp (the *Bayesians*) says $P(A)$ is a degree of belief, a number measuring how strongly you should expect $A$ given what you know. For coins and dice the two agree. For "the probability the next character in this file is the letter e," the Bayesian reading is the natural one — and, as we will see in Chapter 23, it is the reading that makes "compression = prediction" precise. We will use whichever picture is clearer and never lose sleep over the divide.
]

#history[
Although people had gambled for millennia, probability as a _mathematics_ was born startlingly late, in a 1654 exchange of letters between two French mathematicians, Blaise Pascal (then 31) and Pierre de Fermat (then 47). A gambler, the Chevalier de Méré, had asked Pascal how to fairly split the pot of an interrupted game of chance — the famous "problem of points." Pascal and Fermat solved it two different ways (Fermat by listing all the ways the game could finish, Pascal by his arithmetic triangle) and in doing so invented the notion of _expected value_ and, with it, the field. It would be another 279 years before Andrey Kolmogorov, in 1933, gave probability the rigorous set-theoretic foundation we are about to meet.
]

=== The frequency view: what probability looks like in the long run

The counting definition is clean but a little abstract. There is a second picture that makes probability tangible, and it is the one that connects directly to data files and to compression. Imagine flipping a fair coin not once but ten thousand times, and keeping a running tally of the _fraction_ that came up heads. Early on the fraction jumps around wildly — after two flips it might be 0%, 50%, or 100%. But as the flips pile up, the fraction settles, drifting closer and closer to $1\/2$ and refusing to leave. This is the *law of large numbers*, and it is the bridge between the abstract number $P("heads") = 1\/2$ and the messy real world.

#keyidea[
The *law of large numbers* says: if you repeat an experiment many times independently, the observed fraction of times an event $A$ happens converges to its probability $P(A)$. Probability is the value the long-run frequency homes in on. This is why we can _measure_ a probability we don't know — by collecting data and counting — and it is exactly what a compressor does when it counts how often each byte appears in a file.
]

Let us watch it happen. The cleanest way to _see_ a probabilistic idea is to simulate it, and the cleanest tool for that is a few lines of Python. Don't worry if you have never written code; we will explain every new piece in a #gopython box as it appears, and the prose will make complete sense even if you skip the code entirely.

#gopython("Variables, the random module, and for-loops")[
A Python *variable* is a name that holds a value: `heads = 0` makes the name `heads` stand for the number 0, and `heads = heads + 1` increases it by one. The `import random` line pulls in Python's built-in toolbox for randomness. Inside it, `random.random()` returns a fresh random decimal between 0 and 1 each time you call it — uniformly, so it is below `0.5` exactly half the time. That gives us a fair coin: "below `0.5`" means heads.

A *for-loop* repeats a block of code. `for i in range(10):` runs the indented lines ten times, with `i` taking the values `0, 1, 2, ... , 9` in turn. The colon and the indentation are how Python marks "this block belongs to the loop." Here is a complete, runnable coin simulator:

```python
import random

def fraction_heads(n: int) -> float:
    """Flip a fair coin n times; return the fraction that were heads."""
    heads = 0
    for _ in range(n):           # repeat n times; we ignore the counter
        if random.random() < 0.5:  # 'heads' with probability 1/2
            heads = heads + 1
    return heads / n             # observed frequency

for n in (10, 100, 1000, 100_000):
    print(n, fraction_heads(n))
```

A typical run prints something like `10 0.4`, `100 0.55`, `1000 0.508`, `100000 0.50018`. The more flips, the closer to `0.5`. (The underscore in `100_000` is just a digit separator for readability — Python ignores it. The `_` used as the loop variable is the customary name for "a value I don't care about.")
]

That last column — `0.5`, then `0.50018` — _is_ the law of large numbers, printed to your screen. The probability $1\/2$ was hiding inside the coin all along; ten flips barely reveal it, but a hundred thousand pin it down to three decimal places. The same machinery, pointed at a real file instead of a coin, is how a compressor discovers that the letter `e` has probability about $0.12$ in English text and the letter `q` about $0.001$. Those measured frequencies are the raw material every entropy coder works from.

#checkpoint[A bag holds 3 red marbles and 5 blue marbles, all equally likely to be drawn. What is the probability of drawing a red marble? If you drew with replacement 8000 times, roughly what fraction would be red?][The sample space has $3 + 5 = 8$ equally likely outcomes; red is 3 of them, so $P("red") = 3\/8 = 0.375$. By the law of large numbers, about 37.5% of 8000 draws — roughly 3000 — would be red.]

== The rules of the game: three axioms and what follows

Counting fractions is a fine way to _start_, but real sources are not fair dice. The probability the next pixel is slightly brighter than the last is not $1\/2$; the probability a DNA base is `A` is not $1\/4$. We need a framework that works for _any_ assignment of probabilities, not just equally likely ones. In 1933 Kolmogorov gave us exactly that, by boiling probability down to three simple rules — the *axioms*. Everything else in this chapter is squeezed out of these three.

#definition("The probability axioms (Kolmogorov, 1933)")[
A *probability* is a way of assigning to every event $A$ a number $P(A)$ obeying three rules:
+ *Non-negativity.* $P(A) >= 0$ for every event $A$. Probabilities are never negative.
+ *Normalisation.* $P(S) = 1$. _Something_ in the sample space is certain to happen.
+ *Additivity.* If two events $A$ and $B$ are *mutually exclusive* (they share no outcomes, so they cannot both happen on the same run), then $P(A "or" B) = P(A) + P(B)$. The probabilities of non-overlapping events simply add.
]

These three lines are deceptively powerful. Watch how much falls out of them. Throughout, we write $A^c$ (read "$A$ complement") for the event "$A$ does _not_ happen" — all the outcomes _not_ in $A$.

#gomaths("Set operations: union, intersection, complement")[
Events are sets, and we combine them with three operations from Chapter 6.
- *Union* $A union B$ ("$A$ or $B$") is the set of outcomes in $A$, in $B$, or in both. Rolling "even _or_ greater-than-4" gives ${2,4,6} union {5,6} = {2,4,5,6}$.
- *Intersection* $A inter B$ ("$A$ and $B$") is the set of outcomes in _both_. "even _and_ greater-than-4" gives ${2,4,6} inter {5,6} = {6}$.
- *Complement* $A^c$ ("not $A$") is everything in $S$ but not in $A$. If $A = {2,4,6}$ on a die, then $A^c = {1,3,5}$.

Two events are *mutually exclusive* (or *disjoint*) when $A inter B = emptyset$ — no shared outcomes. In probability-speak, additivity applies exactly when events are disjoint.
]

*The complement rule.* An event $A$ and its complement $A^c$ are mutually exclusive (an outcome can't be both in $A$ and not in $A$), and together they make up all of $S$. So by axioms 3 and 2, $P(A) + P(A^c) = P(S) = 1$, which rearranges to

$ P(A^c) = 1 - P(A). $

This tiny rule is a workhorse. The probability of "at least one head in three flips" is annoying to count directly, but its complement, "no heads at all," is a single easy outcome. We will cash that in shortly.

*The addition rule for overlapping events.* Axiom 3 only adds probabilities when events _don't_ overlap. What if they do? Consider drawing one card from a 52-card deck. Let $A$ = "the card is a heart" ($P(A) = 13\/52$) and $B$ = "the card is a queen" ($P(B) = 4\/52$). If we naively add, $13\/52 + 4\/52 = 17\/52$, we have counted the queen of hearts _twice_ — once as a heart, once as a queen. We must subtract the overlap back out:

$ P(A union B) = P(A) + P(B) - P(A inter B). $

Here $P(A inter B) = 1\/52$ (only the queen of hearts is both), so $P("heart or queen") = 13\/52 + 4\/52 - 1\/52 = 16\/52 = 4\/13$. This is the *inclusion–exclusion principle*, and it is just careful bookkeeping: add the pieces, then remove what you double-counted.

#theorem("Inclusion–exclusion for two events")[For any two events $A$ and $B$, $ P(A union B) = P(A) + P(B) - P(A inter B). $]

#proof[
Split $A union B$ into three mutually exclusive pieces: outcomes in $A$ only, outcomes in $B$ only, and outcomes in both ($A inter B$). Call their probabilities $a$, $b$, and $c$. Since these three pieces are disjoint and cover $A union B$, axiom 3 (applied twice) gives $P(A union B) = a + b + c$. Now $P(A)$ covers the "$A$ only" and "both" pieces, so $P(A) = a + c$; likewise $P(B) = b + c$. Therefore
$ P(A) + P(B) - P(A inter B) = (a + c) + (b + c) - c = a + b + c = P(A union B). $
The subtraction of $P(A inter B) = c$ is precisely the removal of the double-counted overlap.
]

(When $A$ and $B$ _are_ mutually exclusive, $A inter B = emptyset$ and $P(A inter B) = 0$, so the formula collapses back to plain additivity. Inclusion–exclusion is the general law; axiom 3 is its special case.)

#checkpoint[In a class, $P("plays guitar") = 0.30$, $P("plays piano") = 0.20$, and $P("plays both") = 0.05$. What fraction plays at least one of the two instruments?][By inclusion–exclusion, $P("guitar or piano") = 0.30 + 0.20 - 0.05 = 0.45$. Forty-five percent play at least one.]

=== Why the probabilities of a whole alphabet must sum to one

There is one consequence of the axioms that we will use on literally every page of the rest of the book, so let us pin it down explicitly. Suppose the sample space breaks into a complete list of separate, non-overlapping outcomes — say the symbols of an alphabet, $S = {x_1, x_2, dots, x_m}$, where every run produces exactly one symbol. Because the outcomes are mutually exclusive and together they _are_ all of $S$, additivity (applied repeatedly) plus normalisation forces

$ P(x_1) + P(x_2) + dots.c + P(x_m) = P(S) = 1. $

In words: *the probabilities of a complete set of mutually exclusive outcomes always add up to exactly 1.* A list of non-negative numbers that sums to 1 is called a *probability distribution*, and it is the central object of compression — it is precisely what the `symbol_probabilities` sketch at the end of this chapter returns, and precisely what an entropy coder consumes. If your numbers don't sum to 1, you don't have a probability distribution, and no amount of clever coding will rescue you; a simple `is_distribution` check exists to catch exactly that mistake.

This sum-to-one law also gives a quick sanity reflex. The five letters of `abracadabra` had probabilities $0.455, 0.182, 0.091, 0.091, 0.182$; add them and you get $1.001$ — off only by rounding, reassuringly close to 1. Whenever you compute a distribution by hand or in code, _add the pieces up_ as a check. A distribution that sums to $0.8$ or $1.3$ is a bug, every single time.

#gomaths("∑ notation: a compact way to add a list")[
Writing $P(x_1) + P(x_2) + dots.c + P(x_m)$ gets tiresome, so mathematicians use the *summation symbol* $sum$ (capital Greek "sigma"), a compact shorthand for "add up a whole list." The expression
$ sum_(i=1)^(m) P(x_i) = P(x_1) + P(x_2) + dots.c + P(x_m) $
reads "sum, as $i$ runs from 1 to $m$, of $P(x_i)$" — start $i$ at 1, plug it in, add the result, bump $i$ up, repeat until $i = m$. So the sum-to-one law is just $sum_(i=1)^m P(x_i) = 1$. Chapter 11 develops $sum$ in full; for now read it as "add up all of these." A tiny example: $sum_(i=1)^3 i^2 = 1^2 + 2^2 + 3^2 = 1 + 4 + 9 = 14$.
]

== Many flips at once: the multiplication rule and independence

A coin flipped once is dull. The interesting questions — and the ones compression cares about — involve _sequences_: many flips, many die rolls, a whole string of characters. To handle sequences we need to know how to combine the probabilities of separate events. The key word is *independence*.

Two events are *independent* when knowing that one happened tells you nothing about whether the other happened. A coin has no memory: the second flip doesn't care how the first landed. Drawing two cards _without_ putting the first back, though, is _not_ independent — removing a card changes what's left. The distinction matters enormously.

#keyidea[
For *independent* events $A$ and $B$, the probability that _both_ happen is the product of their individual probabilities:
$ P(A "and" B) = P(A) times P(B). $
For three or more independent events you keep multiplying: $P(A "and" B "and" C) = P(A) P(B) P(C)$, and so on. Probabilities of independent events _multiply_; this is the deepest reason logarithms (Chapter 7) keep appearing in compression, because logarithms turn those products into sums.
]

This is really the multiplication principle of Chapter 8 wearing a probability costume. To flip three heads in a row with a fair coin:

$ P("HHH") = 1/2 times 1/2 times 1/2 = 1/8. $

Why $1\/8$? Because three flips have $2 times 2 times 2 = 8$ equally likely outcomes — `HHH, HHT, HTH, HTT, THH, THT, TTH, TTT` — and exactly one of them is `HHH`. The multiplication rule and the counting-of-sequences give the same answer, as they must.

#gomaths("Powers and the product symbol ∏")[
When you multiply the same number by itself $n$ times you get a *power*: $2 times 2 times 2 = 2^3 = 8$, and in general $(1\/2)^n$ for $n$ fair coin flips all matching. Chapter 7 built powers and their logarithm; we use them constantly here because independent flips multiply.

For longer products we use the *product symbol* $product$ (capital Greek "pi"), the multiplication twin of the summation $sum$ we met a few pages ago: where $sum$ adds a list, $product$ multiplies one. The expression
$ product_(i=1)^(n) p_i = p_1 times p_2 times dots.c times p_n $
just means "multiply together $p_1$ through $p_n$." So the probability of a specific sequence of $n$ independent events, the $i$-th having probability $p_i$, is $product_(i=1)^n p_i$. If every $p_i$ equals $1\/2$, this is $(1\/2)^n$.
]

Now we can answer the first puzzle from the chapter's opening. _Flip a fair coin three times; what is the probability of at least two heads?_ The slick route uses the complement rule. "At least two heads" is the opposite of "zero or one head." But it is even easier to just count, since all 8 sequences are equally likely. The sequences with two or more heads are `HHH, HHT, HTH, THH` — four of them. So

$ P("at least two heads") = 4/8 = 1/2. $

The bet from the opening is exactly fair: you win half the time, lose half the time, so on average you break even. Decline it only if you dislike risk for its own sake.

#misconception[Independent events that haven't happened "for a while" become more likely — after five tails in a row, a head is "due."][This is the *gambler's fallacy*, and it is wrong because the coin has no memory. Each flip is independent: $P("heads") = 1\/2$ on the sixth flip regardless of the previous five. The five tails already happened; they change nothing about the future. What _is_ true (the law of large numbers) is that over a huge number of flips the _fraction_ of heads approaches $1\/2$ — but it does so by swamping early imbalances with sheer volume, never by "correcting" them. Casinos have grown rich on people who confuse these two facts.]

=== When events are *not* independent: conditional probability

Independence is the easy case. The world is usually tangled: the probability the next pixel is dark depends heavily on whether the _last_ pixel was dark; the probability the next letter is `u` skyrockets if the last letter was `q`. To capture "the probability of $A$ _given that_ $B$ has happened," we need *conditional probability* — and this single idea is, without exaggeration, the engine of modern compression.

#definition("Conditional probability")[
The *conditional probability* of $A$ given $B$, written $P(A | B)$ and read "$P$ of $A$ given $B$," is the probability that $A$ happens once we already know $B$ happened. As long as $P(B) > 0$,
$ P(A | B) = P(A inter B) / P(B). $
]

The formula looks abstract, so build the intuition first. Learning that $B$ happened _shrinks your world_: outcomes outside $B$ are now off the table. So you rescale. Among the outcomes still possible (those in $B$, total probability $P(B)$), what fraction also make $A$ true (those in $A inter B$)? That ratio is $P(A | B)$. The vertical bar literally means "restrict attention to the world where the thing after the bar is true."

#fig([The vertical bar conditions on $B$: it throws away everything outside $B$ and asks what fraction of the remaining world (shaded) is also in $A$. That fraction is $P(A | B) = P(A inter B) \/ P(B)$.],
cetz.canvas({
  import cetz.draw: *
  // sample space box
  rect((0,0),(7,4), stroke: 0.8pt + gray, name: "S")
  content((6.5,3.6))[#text(size: 9pt)[$S$]]
  // circle B (the conditioned world)
  circle((2.5,2), radius: 1.7, stroke: 1pt + rgb("#0b5394"), fill: rgb("#0b5394").lighten(85%))
  content((1.3,3.2))[#text(size: 9pt, fill: rgb("#0b5394"))[$B$]]
  // circle A overlapping
  circle((4.4,2), radius: 1.4, stroke: 1pt + rgb("#9a2617"), name: "A")
  content((5.4,3.0))[#text(size: 9pt, fill: rgb("#9a2617"))[$A$]]
  // overlap shaded darker
  content((3.5,2))[#text(size: 8pt)[$A inter B$]]
  content((3.5,-0.6))[#text(size: 8.5pt)[Given $B$: only the blue world remains; how much of it is also $A$?]]
}))

Let us make it concrete with a fair die. Roll it once. Let $A$ = "the result is a 2" and $B$ = "the result is even." Without any information, $P(A) = 1\/6$. But suppose a friend peeks and tells you only that the roll was even. Now your world has shrunk to ${2, 4, 6}$ — three equally likely outcomes — and the 2 is one of them. So

$ P(A | B) = P("rolled a 2 and even") / P("even") = (1\/6) / (3\/6) = 1/3. $

Knowing it was even _raised_ the probability of a 2 from $1\/6$ to $1\/3$. Information changed the odds. That is the whole point: *conditioning on what you have already seen sharpens your prediction of what comes next* — and a sharper prediction, we will prove in Chapters 18 and 26, means fewer bits.

#keyidea[
Rearranging the definition of conditional probability gives the *general multiplication rule*, valid whether or not the events are independent:
$ P(A inter B) = P(B) times P(A | B). $
And independence is now just the special case where conditioning changes nothing: $A$ and $B$ are independent exactly when $P(A | B) = P(A)$ (knowing $B$ tells you nothing about $A$), which makes the rule collapse to $P(A inter B) = P(B) P(A)$. Independence isn't a separate idea bolted on — it is the boundary case of conditional probability where the bar does nothing.
]

#aside[
This is the moment the entire book pivots toward, even though we are still rolling dice. A compressor scanning a file is forever computing conditional probabilities: $P("next byte is" x | "the bytes seen so far")$. A "model" in compression is _precisely_ a recipe for those conditional probabilities. gzip's model is crude (it conditions on whether a short run of recent bytes has appeared before); a large language model's is extraordinarily refined (it conditions on thousands of previous tokens). They differ only in the quality of the conditional probabilities they produce — and, as Chapter 23 will make exact, better conditional probabilities are better compression, full stop.
]

#checkpoint[Two fair coins are flipped. Given that _at least one_ is heads, what is the probability that _both_ are heads?][The sample space is ${"HH, HT, TH, TT"}$, all equally likely. "At least one head" rules out `TT`, leaving three outcomes ${"HH, HT, TH"}$. Of those, only `HH` has both heads. So $P("both" | "at least one") = 1\/3$, not $1\/2$ — this is the second opening puzzle, and the surprise is that conditioning on "at least one" is _not_ the same as being told about one specific coin.]

== Bayes' rule: flipping the conditional around

Conditional probability has a direction to it. $P("test positive" | "sick")$ — how often a sick person tests positive — is a property of the test, easy to measure in a lab. But what you actually want to know when you get a result is the _reverse_: $P("sick" | "test positive")$ — given that I tested positive, how likely am I to be sick? These two are _not_ the same number, and confusing them is one of the most consequential mistakes a human being can make. The tool that converts one into the other is *Bayes' rule*, and it is just two lines of algebra with life-or-death consequences.

#theorem("Bayes' rule")[For events $A$ and $B$ with $P(B) > 0$, $ P(A | B) = (P(B | A) thin P(A)) / P(B). $]

#proof[
Recall the general multiplication rule from the previous section, written two ways. Conditioning on $B$: $P(A inter B) = P(B) thin P(A | B)$. Conditioning instead on $A$: $P(A inter B) = P(A) thin P(B | A)$. The left-hand sides are identical — "$A$ and $B$" is the same event regardless of which we condition on — so the right-hand sides are equal:
$ P(B) thin P(A | B) = P(A) thin P(B | A). $
Divide both sides by $P(B)$ (allowed, since $P(B) > 0$) and you have Bayes' rule.
]

Two lines. But notice what it does: it lets you compute the hard direction, $P(A | B)$, from the easy direction, $P(B | A)$, plus the _base rate_ $P(A)$ — how common $A$ is to begin with. That base rate is the piece human intuition systematically forgets, and forgetting it is the engine of the famous medical-test paradox.

#gomaths("The law of total probability")[
To use Bayes' rule we usually need the denominator $P(B)$, and often the cleanest way to get it is to split $B$ across a case and its complement. If $A$ and $A^c$ together cover everything (they always do), then every way $B$ can happen falls into "$B$ with $A$" or "$B$ with $A^c$" — two disjoint pieces. So
$ P(B) = P(B | A) thin P(A) + P(B | A^c) thin P(A^c). $
This is the *law of total probability*: the overall chance of $B$ is the weighted average of its chance under each scenario, weighted by how likely each scenario is. Tiny example: if it rains on 30% of days, and you carry an umbrella 90% of rainy days but only 10% of dry days, then your overall umbrella rate is $0.9 times 0.3 + 0.1 times 0.7 = 0.27 + 0.07 = 0.34$.
]

=== The "99% accurate" test that probably isn't telling you what you think

Now we slay the third opening puzzle. A disease afflicts 1 in 1000 people, so the base rate is $P("sick") = 0.001$. A test is "99% accurate" in the following precise sense: it correctly flags 99% of sick people ($P("positive" | "sick") = 0.99$) and correctly clears 99% of healthy people, so it falsely alarms 1% of the healthy ($P("positive" | "healthy") = 0.01$). You test positive. What is the probability you are actually sick?

Most people, including many doctors, answer "99%." Let us compute the truth with Bayes' rule. First the denominator, by the law of total probability:

$ P("positive") = underbrace(0.99 times 0.001, "true positives") + underbrace(0.01 times 0.999, "false positives") = 0.00099 + 0.00999 = 0.01098. $

Now Bayes:

$ P("sick" | "positive") = (P("positive" | "sick") thin P("sick")) / P("positive") = (0.99 times 0.001) / 0.01098 = 0.00099 / 0.01098 approx 0.090. $

About *9%*. Despite the scary-sounding "99% accurate," a positive result means you are roughly 9% likely to be sick and 91% likely to be fine. Why so low? Because the disease is rare. Out of 100{,}000 people, only 100 are sick (and ~99 of them test positive), while 99{,}900 are healthy — and 1% of _those_, about 999 people, also test positive. The false alarms (999) swamp the true alarms (99) by ten to one. The base rate $P("sick") = 0.001$ is doing all the work, and it is exactly the number intuition throws away.

#fig([Why a positive result is mostly a false alarm when the disease is rare. Of 100{,}000 people, the few true positives (dark) are drowned out by far more false positives (light) drawn from the enormous healthy majority.],
cetz.canvas({
  import cetz.draw: *
  // healthy group bar
  rect((0,2),(9,3), fill: rgb("#0b6e4f").lighten(80%), stroke: 0.6pt + gray)
  content((4.5,2.5))[#text(size: 8.5pt)[99,900 healthy]]
  // false positives slice
  rect((0,2),(0.09*9,3), fill: rgb("#9a2617").lighten(55%), stroke: 0.6pt + gray)
  content((4.5,1.55))[#text(size: 7.5pt, fill: rgb("#9a2617"))[~999 of them test positive (false alarms)]]
  // sick group bar (tiny)
  rect((0,0),(0.5,1), fill: rgb("#0b5394").lighten(40%), stroke: 0.6pt + gray)
  content((2.4,0.5))[#text(size: 8pt)[100 sick → ~99 test positive (true)]]
  content((4.5,3.4))[#text(size: 8.5pt, weight: "bold")[Out of 100,000 people]]
}))

#pitfall[
The error here has a name: the *base-rate fallacy* (or *prosecutor's fallacy* in courtrooms). It is the habit of reporting $P("positive" | "sick")$ — a property of the test — when the decision actually needs $P("sick" | "positive")$ — a property of _you_. The two diverge wildly whenever the base rate is far from 50%. This is why doctors confirm rare-disease positives with a second, independent test: a second positive multiplies the evidence and pushes the posterior probability up to where intuition expected it all along. Bayes' rule is the only honest way to combine a base rate with a piece of evidence.
]

#history[
The rule is named for the Reverend Thomas Bayes (c. 1701–1761), an English Presbyterian minister and amateur mathematician. He never published it: his "An Essay Towards Solving a Problem in the Doctrine of Chances" was found among his papers after his death and read to the Royal Society in 1763 by his friend Richard Price, then printed in 1764. For nearly two centuries "Bayesian" methods were viewed with suspicion as unscientifically subjective. Their rehabilitation — driven by Laplace, who rediscovered and vastly generalised the idea, and in the computer era by the realisation that _learning_ is just Bayesian updating — is one of the great rehabilitations in the history of science. Every spam filter, every modern compressor's adaptive model, and every language model is, at bottom, doing Bayes.
]

=== A model is a probability — and you can already read one

We now have everything we need to sketch the thing every compressor secretly contains: a *model* that assigns a probability to each possible next symbol, learned by counting. Let us build a tiny one over the bytes of a file. This is a preview of the statistical heart `tinyzip` will grow once the project proper begins in Volume I's Python chapters; we will not encode anything yet (that waits for the entropy coders of Volume II), but we will produce the exact kind of probabilities those coders will consume.

#gopython("Dictionaries and the Counter")[
A *dictionary* (`dict`) maps keys to values, written `{key: value, ...}`. `counts = {97: 3, 98: 1}` says "byte 97 appeared 3 times, byte 98 once." You read a value with `counts[97]` and the modern type hint for "a dict from int keys to int values" is `dict[int, int]`.

Counting occurrences is so common that Python ships a ready-made tool, `Counter`, in the `collections` module. `Counter(data)` walks through `data` and tallies how often each item appears, returning a dict-like object. The `.items()` method then hands back each `(key, count)` pair so a `for` loop can visit them. Here is a complete frequency-to-probability model:

```python
from collections import Counter

def symbol_probabilities(data: bytes) -> dict[int, float]:
    """Estimate P(byte) for each byte value by counting frequencies."""
    counts: dict[int, int] = Counter(data)   # how often each byte appears
    total = len(data)                        # total number of bytes
    return {byte: c / total for byte, c in counts.items()}

sample = b"abracadabra"
probs = symbol_probabilities(sample)
for byte, p in sorted(probs.items()):
    print(chr(byte), round(p, 3))
```

The `{... for ... in ...}` is a *dictionary comprehension* — a compact way to build a dict by transforming each item; here it divides every count by the total to turn it into a probability. The output for `b"abracadabra"` (length 11) is `a 0.455`, `b 0.182`, `c 0.091`, `d 0.091`, `r 0.182`. Those five numbers sum to 1, exactly as the normalisation axiom demands — they form a genuine probability distribution over the alphabet.
]

This little `symbol_probabilities` is, conceptually, the project's first _model_: a function that turns raw bytes into a probability distribution by the law of large numbers, counting frequencies as estimates of true probabilities. Every entropy coder we build later — Huffman in Chapter 24, arithmetic coding in Chapter 26, ANS in Chapter 27 — will start by calling something like it to learn the distribution it then encodes against. (We are only previewing the idea here; `tinyzip` itself does not begin until the Python primer of Chapters 15–17, and its frequency tools land in Chapter 16. So treat this as illustration, not yet a build step.)

One more habit worth seeing now: a sanity check that a dictionary really _is_ a distribution. It encodes Kolmogorov's first two axioms directly — every probability $>= 0$, and they sum to 1.

```python
def is_distribution(probs: dict[int, float], tol: float = 1e-9) -> bool:
    """Sanity check: probabilities are non-negative and sum to 1."""
    return all(p >= 0 for p in probs.values()) and \
           abs(sum(probs.values()) - 1.0) <= tol

assert is_distribution(symbol_probabilities(b"abracadabra"))
```

Here `all(...)` is `True` only when its condition holds for every item, and `tol` lets tiny floating-point rounding slip by (recall from the sum-to-one law that `abracadabra`'s probabilities added to $1.001$, not a clean $1$). A check like this means a broken model can never silently poison a coder downstream — a small habit that pays off across the whole book.

== From probability to surprise: the bridge to compression

We have built the machinery. Before we close, let us spend it on the one connection that justifies the whole chapter's place in a book about compression. We will not develop it fully here — that is the job of Chapters 18 through 23 — but the seed is plantable now, with nothing beyond what we already have.

Think again about predictability. A coin that always lands heads ($P("heads") = 1$) is perfectly predictable: every flip tells you nothing you didn't already know. A fair coin ($P = 1\/2$ each way) is maximally unpredictable: every flip is a genuine surprise. Somewhere in between lives a biased coin, say $P("heads") = 0.9$ — usually heads, occasionally a jolt of tails.

Here is the leap. _Compression is the art of spending few bits on the predictable and saving your bits for the surprising._ If a symbol is almost certain, seeing it should cost almost nothing to record; if a symbol is rare, it carries a lot of news and deserves more bits. The natural way to measure the "amount of surprise" in an outcome of probability $p$ turns out to be its logarithm — specifically $log_2(1\/p)$, the very quantity Chapter 7 hinted at when it said "a bit is a logarithm."

#keyidea[
The *surprise* (or *self-information*) of an outcome with probability $p$ is $log_2(1\/p) = -log_2 p$ bits. A certain event ($p = 1$) carries $log_2 1 = 0$ bits of surprise — no news. A one-in-a-million event ($p = 10^(-6)$) carries about $20$ bits. Rare things are surprising; surprising things cost bits; and the _average_ surprise of a source, $sum_x p(x) log_2(1\/p(x))$, is its *entropy* — the exact number of bits per symbol that the best possible compressor must spend. This is Shannon's 1948 masterstroke, and we now have every ingredient to understand it.
]

#gomaths("Expected value: a probability-weighted average")[
"Average surprise" needs a precise meaning, and it is the idea Pascal and Fermat invented in 1654: *expected value*. If a quantity takes value $v_1$ with probability $p_1$, value $v_2$ with probability $p_2$, and so on, its expected value is
$ EE[V] = sum_i p_i thin v_i = p_1 v_1 + p_2 v_2 + dots.c $
— each possible value weighted by how likely it is. It is the long-run average you would see if you repeated the experiment forever (there is the law of large numbers again). Example: a die's expected value is $1(1\/6) + 2(1\/6) + dots.c + 6(1\/6) = 21\/6 = 3.5$. You will never roll a 3.5, but that is the average of many rolls. Entropy is just the expected value of surprise, $EE[log_2(1\/p)]$ — Chapter 10 develops expectation in full, and Chapter 18 turns it into the entropy of a source.
]

Let us make the predictability-equals-compressibility claim concrete with a number we can compute right now. Take the biased coin, $P("heads") = 0.9$, $P("tails") = 0.1$. The surprise of a head is $log_2(1\/0.9) approx 0.152$ bits; the surprise of a tail is $log_2(1\/0.1) approx 3.322$ bits. The _average_ surprise per flip is

$ EE[ "surprise" ] = 0.9 times 0.152 + 0.1 times 3.322 approx 0.137 + 0.332 = 0.469 "bits." $

Read that again: a biased coin can, in principle, be recorded in about *0.47 bits per flip* — less than half a bit — even though writing down "H" or "T" naively costs a full bit. A _fair_ coin, by contrast, has average surprise $0.5 times 1 + 0.5 times 1 = 1$ bit per flip exactly — and cannot be compressed below one bit. The more lopsided (predictable) the coin, the lower its entropy, and the more it can be squeezed. The more balanced (unpredictable), the closer to the incompressible one-bit ceiling. _Predictability is compressibility._ That sentence is the thesis of the entire book, and you just computed it from probabilities you learned to count three sections ago.

#checkpoint[A source emits one of four symbols, each with probability $1\/4$. What is the surprise of each symbol, and the average surprise (entropy) of the source?][Each symbol has probability $1\/4$, so its surprise is $log_2(1\/(1\/4)) = log_2 4 = 2$ bits. Since every symbol carries exactly 2 bits, the average is also $2$ bits per symbol. That matches intuition: four equally likely options need exactly 2 yes/no questions ($2^2 = 4$) to pin down — and cannot be compressed below 2 bits each.]

To make the link between probability and saved bytes vivid, return to `abracadabra`. Our frequency model gave $P(a) = 5\/11, P(b) = P(r) = 2\/11, P(c) = P(d) = 1\/11$. The surprise of each letter is its $log_2(1\/p)$: an `a` carries $log_2(11\/5) approx 1.14$ bits, a `b` or `r` carries $log_2(11\/2) approx 2.46$ bits, and the rare `c` or `d` carries $log_2(11\/1) approx 3.46$ bits. The average surprise, weighted by how often each letter actually appears, is

$ sum_x p(x) log_2 1/p(x) = 5/11 (1.14) + 2/11 (2.46) + 2/11 (2.46) + 1/11 (3.46) + 1/11 (3.46) approx 2.04 "bits/symbol." $

Stored naively as one byte per character, `abracadabra` costs $11 times 8 = 88$ bits. Stored at its entropy of about $2.04$ bits per character, it would cost only about $11 times 2.04 approx 22.5$ bits — a fourfold shrink, and that figure is not a clever trick but a _hard floor_ set entirely by the probability distribution we counted. No encoder, however ingenious, can beat $2.04$ bits per symbol for this source with this model. Every chapter of Volume II is, in one way or another, an attempt to actually _reach_ this floor that probability alone has already revealed. The numbers $5\/11$ and $1\/11$ that we got by plain counting in this chapter are, quite literally, the budget the rest of the book must spend within.

#note[
We just used Shannon's entropy formula, $H = sum_x p(x) log_2(1\/p(x))$, before formally meeting it — a small preview, justified because every piece (probabilities that sum to one, surprise as $log_2(1\/p)$, expected value as a weighted average) is something this chapter built from scratch. When the formula returns in Chapter 18 with its proper name and a proof that it is the unavoidable floor, you will recognise it as an old friend rather than a new mystery. That is the plan of the whole book: each idea is quietly seeded a chapter or two before it is demanded.
]

== A fully worked example: the three-card swindle

Let us close the body with one richer worked problem that exercises everything: counting, the multiplication rule, conditioning, and Bayes. It is a classic hustle.

A bag holds three cards. One is red on both sides (RR), one is white on both sides (WW), and one is red on one side and white on the other (RW). You draw a card at random, look at one side without flipping it, and see *red*. The hustler bets you even money that the _other_ side is white. Should you take the bet?

The naive argument: "The card is either RR or RW (it can't be WW, since I see red), and those are two cases, so the other side is white half the time. Even money is fair." This reasoning is wrong, and Bayes shows exactly why.

Set $A$ = "the card is RR" and $B$ = "the visible side is red." We want $P("other side white" | "visible red")$, which equals $P("card is RW" | B)$, since only the RW card has a white reverse. The base rates: each card is equally likely to be drawn, so $P("RR") = P("WW") = P("RW") = 1\/3$. The likelihoods — the chance of seeing red, given each card:

$ P(B | "RR") = 1 quad (#text[both sides red]), wide P(B | "RW") = 1/2, wide P(B | "WW") = 0. $

By the law of total probability, the overall chance of seeing red is

$ P(B) = 1 times 1/3 + 1/2 times 1/3 + 0 times 1/3 = 1/3 + 1/6 = 1/2. $

Now Bayes, for the RW card:

$ P("RW" | B) = (P(B | "RW") thin P("RW")) / P(B) = ((1\/2)(1\/3)) / (1\/2) = (1\/6) / (1\/2) = 1/3. $

The other side is white only *one third* of the time — so the hustler wins two times out of three at even money. _Decline the bet._ The flaw in the naive argument is that it treated "RR" and "RW" as equally likely _after_ seeing red, but they are not: the RR card has _two_ red sides that could have shown, while the RW card has only _one_, so seeing red is twice as much evidence for RR as for RW. Counting _sides_, not _cards_, is the honest sample space — and Bayes' rule did that bookkeeping for us automatically. This is the same structure as the medical test: the evidence weighs the hypotheses by how _readily_ each would have produced what you saw.

#takeaways((
  [A *sample space* $S$ lists all outcomes; an *event* is a subset of $S$; a *probability* assigns each event a number in $[0,1]$, with 0 = impossible and 1 = certain.],
  [When outcomes are *equally likely*, $P(A) = abs(A) \/ abs(S)$ — probability is counting. The *law of large numbers* says observed frequencies converge to true probabilities, which is how a compressor _measures_ them.],
  [Kolmogorov's three axioms (non-negativity, normalisation, additivity) generate everything: the *complement rule* $P(A^c) = 1 - P(A)$ and *inclusion–exclusion* $P(A union B) = P(A) + P(B) - P(A inter B)$.],
  [Independent events *multiply*: $P(A "and" B) = P(A)P(B)$. Beware the *gambler's fallacy* — independent trials have no memory.],
  [*Conditional probability* $P(A | B) = P(A inter B) \/ P(B)$ rescales the world to where $B$ is true. It is the engine of compression: a model is just a recipe for $P("next symbol" | "past")$.],
  [*Bayes' rule* $P(A | B) = P(B|A) P(A) \/ P(B)$ flips a conditional around and forces you to respect the *base rate*. Ignoring base rates produces the medical-test paradox: a "99% accurate" positive can still mean 9% sick.],
  [*Surprise* $= log_2(1\/p)$ measures the news in an outcome; its average (expected value) is *entropy*, the bit-cost of the best compressor. Predictable sources have low entropy and compress well; unpredictable ones cannot be squeezed.],
))

== Exercises

#exercise("9.1", 1)[
A fair six-sided die is rolled once. Write the sample space, then compute (a) $P("the result is odd")$, (b) $P("the result is at least 5")$, and (c) $P("the result is a multiple of 3")$. For each, name the event as a subset of $S$.
]
#solution("9.1")[
$S = {1,2,3,4,5,6}$, $abs(S) = 6$. (a) Odd $= {1,3,5}$, so $P = 3\/6 = 1\/2$. (b) At least 5 $= {5,6}$, so $P = 2\/6 = 1\/3$. (c) Multiples of 3 $= {3,6}$, so $P = 2\/6 = 1\/3$.
]

#exercise("9.2", 1)[
In a standard 52-card deck, let $A$ = "the card is a face card (J, Q, or K)" and $B$ = "the card is a spade." Compute $P(A)$, $P(B)$, $P(A inter B)$, and then $P(A union B)$ using inclusion–exclusion.
]
#solution("9.2")[
There are 12 face cards, so $P(A) = 12\/52 = 3\/13$. There are 13 spades, so $P(B) = 13\/52 = 1\/4$. The face-card spades are J♠, Q♠, K♠ — three cards — so $P(A inter B) = 3\/52$. By inclusion–exclusion, $P(A union B) = 12\/52 + 13\/52 - 3\/52 = 22\/52 = 11\/26 approx 0.423$.
]

#exercise("9.3", 1)[
A coin is biased with $P("heads") = 0.8$. It is flipped three times, the flips independent. Compute (a) $P("all three heads")$ and (b) $P("at least one tail")$. Hint: use the complement rule for part (b).
]
#solution("9.3")[
(a) By independence, $P("HHH") = 0.8 times 0.8 times 0.8 = 0.512$. (b) "At least one tail" is the complement of "all heads," so $P = 1 - 0.512 = 0.488$.
]

#exercise("9.4", 2)[
Two fair dice are rolled and their values added. (a) How many equally likely outcomes are in the sample space? (b) Compute $P("sum equals 7")$ and $P("sum equals 2")$. (c) Are the events "sum is 7" and "first die is a 1" independent? Justify with numbers.
]
#solution("9.4")[
(a) Each die has 6 faces and they are independent, so $6 times 6 = 36$ equally likely ordered outcomes. (b) Sum 7 occurs for $(1,6),(2,5),(3,4),(4,3),(5,2),(6,1)$ — 6 ways — so $P = 6\/36 = 1\/6$. Sum 2 occurs only for $(1,1)$, so $P = 1\/36$. (c) $P("sum 7") = 1\/6$ and $P("first die 1") = 1\/6$. The intersection is just $(1,6)$, so $P("both") = 1\/36 = (1\/6)(1\/6)$. Since the product equals the joint probability, the two events _are_ independent — a small surprise, true only for the sum 7.
]

#exercise("9.5", 2)[
A standard deck is shuffled and two cards are drawn *without replacement*. Compute $P("both are aces")$. Then explain in one sentence why this is _not_ $(4\/52)^2$.
]
#solution("9.5")[
By the general multiplication rule, $P("both aces") = P("first ace") times P("second ace" | "first ace") = 4\/52 times 3\/51 = 12\/2652 = 1\/221 approx 0.0045$. It is not $(4\/52)^2$ because the draws are not independent: removing the first ace leaves only 3 aces among 51 cards, so the second conditional probability is $3\/51$, not $4\/52$.
]

#exercise("9.6", 2)[
A spam filter knows that 40% of incoming email is spam. The word "free" appears in 60% of spam messages but only 5% of legitimate messages. An email contains the word "free." Use Bayes' rule to compute the probability it is spam.
]
#solution("9.6")[
Let $A$ = spam ($P(A) = 0.40$, so $P(A^c) = 0.60$) and $B$ = contains "free". Likelihoods: $P(B|A) = 0.60$, $P(B|A^c) = 0.05$. By total probability, $P(B) = 0.60 times 0.40 + 0.05 times 0.60 = 0.24 + 0.03 = 0.27$. Then $P(A | B) = (0.60 times 0.40)\/0.27 = 0.24\/0.27 approx 0.889$. About 89% likely spam.
]

#exercise("9.7", 2)[
A source emits symbols `A`, `B`, `C` with probabilities $0.5$, $0.25$, $0.25$. (a) Compute the surprise (in bits) of each symbol. (b) Compute the average surprise (entropy) of the source. (c) Compare it to a source where all three symbols are equally likely — which compresses better, and why?
]
#solution("9.7")[
(a) Surprise of `A` $= log_2(1\/0.5) = 1$ bit; of `B` $= log_2(1\/0.25) = 2$ bits; of `C` $= 2$ bits. (b) Average $= 0.5(1) + 0.25(2) + 0.25(2) = 0.5 + 0.5 + 0.5 = 1.5$ bits/symbol. (c) For three equally likely symbols each has probability $1\/3$ and surprise $log_2 3 approx 1.585$ bits, so entropy $approx 1.585$ bits/symbol. The skewed source (1.5 bits) compresses _better_ because it is more predictable — `A` arriving half the time carries little surprise, so we can spend fewer bits on it.
]

#exercise("9.8", 2)[
Modify `symbol_probabilities` from this chapter so that it never returns a probability of exactly zero for any byte value 0–255, even if that byte never appears in the data. (This "smoothing" matters because a real encoder cannot spend $log_2(1\/0) = infinity$ bits on an unexpected symbol.) Describe in words, or in Python, a simple scheme.
]
#solution("9.8")[
Use *add-one (Laplace) smoothing*: pretend every one of the 256 byte values was seen one extra time before counting the data. In Python: start `counts` at `{b: 1 for b in range(256)}`, add the data's tallies on top, and divide each by `total + 256`. Now every byte has a count of at least 1, so every probability is strictly positive and finite-cost to encode, while frequencies still dominate once the data is large (the law of large numbers). This is exactly how real adaptive coders avoid the "infinite surprise" of a never-before-seen symbol.
]

#exercise("9.9", 3)[
*The Monty Hall problem.* On a game show, a prize hides behind one of three doors. You pick door 1. The host, who knows where the prize is, opens a _different_ door (2 or 3) that he knows is empty, and offers you the chance to switch to the remaining unopened door. Using conditional probability or a full enumeration, compute the probability of winning if you switch versus if you stay. Explain the result.
]
#solution("9.9")[
Switching wins with probability $2\/3$; staying wins with probability $1\/3$. Enumerate by where the prize is (each $1\/3$): if it is behind door 1 (your pick), switching loses; if behind door 2 or door 3, the host is forced to reveal the other empty door and switching lands on the prize. So switching wins in 2 of the 3 equally likely prize placements. The key is that the host's choice is _not_ independent of the prize location — he never opens the prize door — so opening a door injects information. Conditioning on "host opened an empty door he was forced to choose" leaves the switch door carrying the full $2\/3$ probability that your original pick was wrong.
]

#exercise("9.10", 3)[
A biased coin has unknown heads-probability $p$. You flip it 10 times and observe 7 heads. (a) Under the equally-likely-naive view you might guess $p = 0.5$; using the data, what is the most natural estimate of $p$, and which principle of this chapter justifies it? (b) The exact probability of seeing _exactly_ 7 heads in 10 flips, for a given $p$, is $binom(10, 7) p^7 (1-p)^3$. Explain where each piece of that formula comes from, using the multiplication rule and Chapter 8's combinations.
]
#solution("9.10")[
(a) The natural estimate is the observed frequency $hat(p) = 7\/10 = 0.7$, justified by the law of large numbers: frequencies converge to probabilities, so the best single-number guess from data is the frequency itself. (b) For one _specific_ sequence with 7 heads and 3 tails, independence makes the flips multiply: $p^7 (1-p)^3$ (seven heads each contributing $p$, three tails each contributing $1-p$). But there are $binom(10,7) = 120$ different orderings of which flips are the heads (Chapter 8's combinations), and these orderings are mutually exclusive, so by additivity we add 120 equal terms — giving the factor $binom(10,7)$ in front. The combination counts the _arrangements_; the powers give each arrangement's probability.
]

== Further reading

- *Pascal–Fermat correspondence (1654).* The founding letters on the "problem of points." A readable modern transcription: #link("https://www.york.ac.uk/depts/maths/histstat/pascal.pdf")[York University, "Fermat and Pascal on Probability"]. This is where expected value — and the field — began.
- *Thomas Bayes (1763/1764),* "An Essay Towards Solving a Problem in the Doctrine of Chances," _Philosophical Transactions of the Royal Society_. Read to the Society by Richard Price after Bayes' death; the original statement of the rule that bears his name. Overview: #link("https://en.wikipedia.org/wiki/An_Essay_Towards_Solving_a_Problem_in_the_Doctrine_of_Chances")[Wikipedia summary].
- *A. N. Kolmogorov (1933),* _Grundbegriffe der Wahrscheinlichkeitsrechnung_ (translated as _Foundations of the Theory of Probability_, Chelsea, 1956). The three-axiom foundation we used all chapter. Slim, austere, and the bedrock of all later probability.
- *C. E. Shannon (1948),* "A Mathematical Theory of Communication," _Bell System Technical Journal_ 27. The paper that turns the "surprise = $log_2(1\/p)$" idea of our final section into entropy and the source coding theorem. We meet it head-on in Chapter 18. (`papers/shannon-1948-mathematical-theory-communication.pdf`.)
- For a gentle, modern, free textbook treatment, see *Grinstead & Snell, "Introduction to Probability"* (American Mathematical Society, open access) — every idea in this chapter, worked at leisure with hundreds of examples.

#bridge[
We now have probabilities, conditioning, and Bayes — but in this chapter outcomes were _labels_ ("heads," "the queen of hearts"). The next chapter, *Random Variables, Expectation, and Variance*, attaches _numbers_ to outcomes so we can average them and measure their spread. Expectation, which we glimpsed as "average surprise," becomes the cost of a code; variance measures how erratic a source is. With random variables in hand, the geometric and Bernoulli sources we will compress stop being toys and become precise objects — and Chapter 18 will finally collect the average surprise we computed here into the single most important quantity in the book: Shannon's entropy.
]
