#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Shannon and the Birth of Information Theory

#epigraph[The fundamental problem of communication is that of reproducing at one point either exactly or approximately a message selected at another point.][Claude E. Shannon, _A Mathematical Theory of Communication_, 1948]

Play a game with me. I am thinking of a letter of the alphabet, and you must discover which one by asking yes-or-no questions. "Is it a vowel?" "Is it in the first half of the alphabet?" You keep narrowing things down until only one letter remains. How many questions will you need?

If you are clever, the answer is about five, because five yes/no answers can distinguish $2^5 = 32$ possibilities, and the alphabet has only 26 letters. But now change the game. Suppose I am not picking letters at random. Suppose I am picking the _next letter of an English sentence_, and the sentence so far reads "the quick brown fo\_". Now you barely need to ask at all. The next letter is almost certainly `x`. One question, maybe none, settles it.

Same alphabet, wildly different number of questions. Why? Because the second situation is _predictable_, and the first is not. And here is the thunderbolt that this chapter is built around: the average number of yes/no questions you need is _exactly_ the number of bits it takes to store the answer, and that number has a name. It is called the *entropy*. In 1948 a quiet 32-year-old at Bell Labs named Claude Shannon wrote down a single formula for it, proved that it is the unbreakable floor on how small any message can be squeezed, and in doing so invented the entire science that this book is about. Everything we have built (logarithms, probability, expectation) has been preparation for this one chapter. Let us go and meet the most important equation in compression.

#recap[
In Chapter 7 we learned that a *logarithm* answers "what power do I raise the base to?", that $log_2 N$ counts the yes/no questions needed to pick one item out of $N$, and the strange promise that "a bit is a logarithm." In Chapter 9 we built *probability* from coins and dice: a sample space, the probability $p(x)$ of an outcome, conditional probability $p(x | y)$, and independence. In Chapter 10 we met the *expected value* $EE[X] = sum_x p(x) dot x$, the probability-weighted average we called "the cost of a code." This chapter fuses those three threads. Self-information will be a logarithm of a probability; entropy will be the expected value of that self-information. Keep $log_2$, $p(x)$, and $EE[dot]$ close at hand; we use all three on nearly every page.
]

#objectives((
  [Define the *self-information* (surprisal) of an event and explain, from first principles, why surprise must be the logarithm of one over its probability.],
  [Define *Shannon entropy* $H(X)$, compute it for real distributions, and read it three ways: average surprise, average yes/no questions, and the bit-floor on lossless coding.],
  [Prove that entropy is *maximised by the uniform distribution* and *zero for a certain outcome*, and bound it by $0 <= H(X) <= log_2 n$.],
  [Define *joint entropy* $H(X, Y)$ and *conditional entropy* $H(Y | X)$, and prove the *chain rule* $H(X, Y) = H(X) + H(Y | X)$.],
  [Prove that *conditioning never increases entropy* ($H(Y | X) <= H(Y)$) and explain why this single fact is the reason context-based compression works.],
  [Estimate the entropy of a real data source in Python and connect it to the redundancy that every compressor in this book attacks.],
))

== 1948: the year information became a number

For most of human history, "information" was a vague, literary word. You could have _more_ or _less_ of it, but nobody could say how much a telegram, a photograph, or a spoken sentence actually contained, not in numbers, not in units. There was no ruler for information. Then, in the July and October 1948 issues of the _Bell System Technical Journal_, Claude Shannon published a 79-page paper, _A Mathematical Theory of Communication_, that handed the world that ruler. Scientific American would later call it "the Magna Carta of the Information Age," and the description is not hyperbole. Almost every idea in this book is a footnote to that paper.

#history[
*Claude Elwood Shannon* (1916–2001) was a Bell Labs mathematician and engineer, already famous for a 1937 master's thesis (written at MIT, at age 21) that showed Boolean algebra (the logic of Chapter 5) could describe electrical switching circuits, the idea underneath every digital computer ever built. The 1948 paper built on two earlier Bell Labs results: *Harry Nyquist* (1924) and *Ralph Hartley* (1928) had each argued that the information in a message should grow with the _logarithm_ of the number of possible messages. Shannon's leap was to bring _probability_ into it: messages are not all equally likely, and that asymmetry is exactly what makes compression possible. He also gave the field its unit. The word *bit* (short for "binary digit") appears in print, for the first time anywhere, in that paper; Shannon credited the coinage to his Bell Labs colleague *John Tukey* (the same Tukey who later co-invented the Fast Fourier Transform we meet in Chapter 37).
]

#aside[
When Shannon needed a name for his new quantity $-sum p log p$, he was unsure what to call it. The polymath *John von Neumann*, the story goes, told him: "Call it entropy. For two reasons. First, your function already goes by that name in statistical mechanics. Second, and more importantly, nobody really knows what entropy is, so in a debate you will always have the advantage." Whether the quip is literally true or polished by retelling, the name _entropy_ stuck, and the collision with physics is no accident, as we will see.
]

Shannon's first and most radical move was to throw away _meaning_. To an engineer building a telephone or a telegraph, he argued, the _meaning_ of a message is irrelevant; what matters is only that the message was _selected_ from some set of possible messages, and the job of the system is to reproduce that selection at the far end. So Shannon modelled an information source not as a poet or a sensor but as a *random process*: a machine that spits out symbols (letters, pixels, audio samples) each drawn according to some probability distribution. Once you accept that model, the question "how much information is in this message?" becomes a precise question about that distribution, and it has a precise answer.

This is the deepest reason the *model + coder* split we sketched in Chapter 1 is the very shape of the theory, and not merely an engineering convenience. The _model_ is the probability distribution $p$ you assign to the source; the _coder_ is the machine that turns those probabilities into bits. Shannon's 1948 paper is, in effect, the proof that once the model is fixed, the coder's best possible average performance is _completely determined_: it equals the entropy of the model, and not one bit less. All the ingenuity left over goes into building better models. Hold that thought; it returns as the organising principle of the entire book.

#misconception[Shannon's entropy and the entropy of thermodynamics (the "disorder" of physics, the thing that always increases) are the same quantity, so information theory is really a branch of physics.][They share a formula and a name. Shannon's $-sum p log p$ is Boltzmann's and Gibbs' entropy to the letter, which is why von Neumann suggested the word, but they answer different questions and live in different universes of application. Thermodynamic entropy counts the microscopic states consistent with a gas's temperature and pressure; Shannon entropy counts the bits needed to pin down a symbol from a source. The mathematics is identical because both ask "how many equally likely possibilities, on a log scale?", and there are genuine, profound bridges between them (Landauer's principle, which says erasing one bit costs at least $k T ln 2$ joules of heat, is the most famous). But you do not need a single fact from physics to use Shannon entropy to compress a file, and this book treats it purely as the bit-counting tool it is. The shared name is a deep coincidence, not a dependency.]

== Surprise, measured: self-information

Begin with a single event, not a whole source. Someone tells you a fact. How much did you _learn_? Shannon's insight is that what you learn is exactly how _surprised_ you are, and surprise is governed entirely by probability.

Consider three announcements. "The sun rose this morning." You learn essentially nothing; the event was certain, $p approx 1$. "It is raining in the city." Mildly informative; perhaps $p = 1\/4$. "You have won a one-in-a-million lottery." Enormously informative; $p = 1\/1{,}000{,}000$. The pattern is unmistakable: *the less probable an event, the more information its occurrence carries.* Information must therefore be a _decreasing_ function of probability. A certain event ($p = 1$) must carry _zero_ information. And there is one more requirement, the one that pins the function down completely.

Suppose two _independent_ things happen: you flip a fair coin (heads, $p = 1\/2$) and, separately, roll a fair die (a four, $p = 1\/6$). How much information in the combined announcement "heads and a four"? Intuitively, the information should _add up_: the coin told you one thing, the die told you another, and they have nothing to do with each other. But probabilities of independent events _multiply_: $p("heads and four") = 1\/2 times 1\/6 = 1\/12$. So we need a function $i(p)$ that turns the _multiplication_ of probabilities into the _addition_ of information. We met exactly one such function in Chapter 7. The logarithm.

#gomaths("Why the logarithm is the only honest choice")[
We met logarithms in Chapter 7. The single property we lean on here is the *product rule*:
$ log(a times b) = log a + log b. $
The logarithm is essentially the _only_ continuous function that turns multiplication into addition. Shannon wanted a measure of information $i(x)$ obeying three commonsense rules:
+ $i(x)$ depends only on the probability $p(x)$, and decreases as $p$ grows (rarer = more informative).
+ $i(x) = 0$ when $p(x) = 1$ (a certain event teaches you nothing).
+ For independent events, information adds: $i("both") = i(x) + i(y)$ whenever $p("both") = p(x) p(y)$.

A short argument (sketched in Exercise 18.6) shows these three rules force
$ i(x) = -log_b p(x) = log_b 1/(p(x)) $
for some base $b$. The base only rescales the answer, like choosing inches versus centimetres. Choose base $b = 2$ and the unit is the *bit*; choose base $e$ and the unit is the *nat*; choose base 10 and it is the *hartley* (after Ralph Hartley). This book always uses base 2, since we are counting bits.
]

#definition("Self-information / surprisal")[
The *self-information* (or *surprisal*) of an event $x$ that occurs with probability $p(x) > 0$ is
$ i(x) = log_2 1/(p(x)) = -log_2 p(x) quad "bits." $
It measures how much you learn when $x$ happens, in bits, or equivalently, how _surprised_ you should be.
]

Let us read that formula until it feels obvious. The fraction $1\/p(x)$ is large when $p(x)$ is small, so rare events have large self-information. Good: rare events are surprising. The logarithm then converts that into a count of bits. A fair coin's outcome has $p = 1\/2$, so $i = log_2 2 = 1$ bit: one flip, one bit, exactly as the word "bit" promises. An event with $p = 1\/1{,}000{,}000$ has $i = log_2 1{,}000{,}000 approx 19.93$ bits, about twenty yes/no questions' worth of surprise, which is why winning the lottery feels like such news. And a certain event, $p = 1$, has $i = log_2 1 = 0$ bits: telling you the sun rose conveys nothing, precisely as it should.

#checkpoint[A fair six-sided die is rolled. How many bits of self-information does the outcome "I rolled a 3" carry? What about a loaded die where 3 comes up with probability $1\/2$?][For the fair die, $p(3) = 1\/6$, so $i = log_2 6 approx 2.585$ bits. For the loaded die, $p(3) = 1\/2$, so $i = log_2 2 = 1$ bit. The loaded die's "3" is far less surprising (it happens half the time) so it carries far less information when it occurs.]

== Entropy: the average surprise of a source

Self-information measures one event. But a _source_ does not emit one event; it emits a long stream of symbols, each drawn from some alphabet according to a distribution. If we are going to design a code (a way of writing each symbol down in bits) what we care about is not the cost of any single symbol but the _average_ cost per symbol over the whole stream. That average is the entropy.

Here is the reasoning, and it is just Chapter 10's expected value applied to Chapter 18's surprisal. Symbol $x$ occurs a fraction $p(x)$ of the time, and each time it occurs it carries $i(x) = -log_2 p(x)$ bits of information. So the long-run average information per symbol is each surprisal weighted by how often it happens:

$ H(X) = sum_(x) p(x) dot i(x) = sum_(x) p(x) log_2 1/(p(x)) = -sum_(x) p(x) log_2 p(x). $

#gomaths("Reading the entropy formula piece by piece")[
The capital sigma, $sum_x$, says "add up the following expression, once for each symbol $x$ in the alphabet" (Chapter 11). Inside the sum, for each symbol we compute $p(x) log_2 (1\/p(x))$: its probability times its surprisal. The leading minus sign in the form $-sum p log_2 p$ is there only because $log_2 p(x)$ is negative for $p(x) < 1$ (the log of a number below 1 is negative), and we want $H$ to come out positive. The two written forms are identical: $log_2(1\/p) = -log_2 p$.

One subtlety: what if some symbol has $p(x) = 0$? Then $log_2 0$ is $-infinity$ and the product $0 times (-infinity)$ looks undefined. By convention we set $0 log_2 0 = 0$, which is the correct limit (as $p -> 0$, the term $p log_2 (1\/p) -> 0$). Intuitively: a symbol that never occurs contributes nothing to the average. So we simply skip zero-probability symbols.
]

#definition("Shannon entropy")[
The *entropy* of a discrete random variable $X$ with possible values $x_1, ..., x_n$ and probabilities $p(x_1), ..., p(x_n)$ is
$ H(X) = -sum_(i=1)^(n) p(x_i) log_2 p(x_i) quad "bits per symbol," $
with the convention $0 log_2 0 = 0$. It is the *expected self-information* $EE[i(X)]$ of the source: the average number of bits of surprise per symbol.
]

A warning about notation that trips up every newcomer: we write $H(X)$, but $H$ does _not_ depend on the _values_ $X$ takes, only on their _probabilities_. The entropy of a fair coin is 1 bit whether its faces read "heads/tails," "0/1," or "win a million dollars/lose a million dollars." Entropy measures uncertainty about _which_ outcome, never the outcomes' magnitudes. (This is the sharp difference from the _variance_ of Chapter 10, which cares enormously about magnitudes.)

=== A worked example: the four-symbol source

Let us compute a real entropy by hand. Imagine a source that emits four symbols, call them `A`, `B`, `C`, `D`, with these probabilities:

$ p(A) = 1/2, quad p(B) = 1/4, quad p(C) = 1/8, quad p(D) = 1/8. $

(Check: $1\/2 + 1\/4 + 1\/8 + 1\/8 = 1$. Good, a valid distribution.) Each probability is a clean power of two, so each surprisal is a whole number of bits:

#table(columns: (auto, auto, auto, auto), inset: 6pt, align: (center, center, center, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Symbol*], [$p(x)$], [$i(x) = -log_2 p(x)$], [$p(x) dot i(x)$]),
  [`A`], [$1\/2$], [$1$ bit], [$0.500$],
  [`B`], [$1\/4$], [$2$ bits], [$0.500$],
  [`C`], [$1\/8$], [$3$ bits], [$0.375$],
  [`D`], [$1\/8$], [$3$ bits], [$0.375$],
)

Add the last column: $H(X) = 0.5 + 0.5 + 0.375 + 0.375 = 1.75$ bits per symbol. Now stare at this number. A naive code would spend 2 bits per symbol on a four-letter alphabet ($2^2 = 4$). But the entropy says the _true_ average information is only 1.75 bits. There are 0.25 bits of waste per symbol (_redundancy_) that a good code could remove. And in fact a beautiful code exists here: assign `A` the codeword `0` (1 bit), `B` the codeword `10` (2 bits), `C` the codeword `110`, and `D` the codeword `111` (3 bits each). The average length of this code is

$ 1 dot 1/2 + 2 dot 1/4 + 3 dot 1/8 + 3 dot 1/8 = 1.75 "bits," $

hitting the entropy _exactly_. This is no coincidence: the codeword for symbol $x$ has length precisely $i(x) = -log_2 p(x)$, spending short codes on common symbols and long codes on rare ones. That is the master recipe behind Huffman coding (Chapter 24), arithmetic coding (Chapter 26), and every entropy coder in this book. Entropy is not an abstraction; it is the bit budget those coders are racing to meet.

#keyidea[
Entropy $H(X)$ is the *floor* on lossless compression: no code can use fewer than $H(X)$ bits per symbol on average. The recipe to reach the floor is "spend $-log_2 p(x)$ bits on symbol $x$": short codes for likely symbols, long codes for rare ones. The gap between the bits a representation _actually_ uses and the entropy floor is called *redundancy*, and removing it is what every lossless compressor does. We will _prove_ the floor in Chapter 19 (the source coding theorem); this chapter establishes what the floor _is_.
]

#note[
Entropy is a _rate_ (bits _per symbol_), not a total. To get the information content of a whole message of $N$ independent symbols, multiply: the message carries about $N dot H(X)$ bits in total, and that is the smallest file (in bits) it could be stored in. Our four-symbol source over a 1000-symbol message needs about $1750$ bits, or roughly $219$ bytes, versus the $250$ bytes a flat 2-bits-each scheme would use. The "per symbol" framing matters because it lets us compare sources of different lengths on equal footing, and because the source coding theorem (Chapter 19) is stated as a per-symbol limit that becomes _tight_ precisely as $N$ grows large. One subtlety we are postponing: this multiply-by-$N$ rule assumes the symbols are _independent_. When they are correlated, as in real text, the true total is governed by the chain-rule sum of conditional entropies, which is smaller. The number $H(X)$ alone is the floor only for an order-0, memoryless view of the source.
]

=== Entropy as the twenty-questions game

The opening puzzle was about yes/no questions, and now we can close the loop. A yes/no question splits the possibilities into two groups; the answer (one bit) tells you which group. The best possible questioning strategy asks questions whose answers are as close to a coin flip as possible, each question worth a full, unwasted bit. Shannon's theorem says that the _minimum average number of perfectly chosen yes/no questions_ needed to identify a symbol equals the entropy $H(X)$ (to within one question, with the slack vanishing as you ask about long blocks at once).

In the four-symbol example, the optimal questions are: "Is it `A`?" (yes half the time, and you are done in one question); if no, "Is it `B`?"; if no, "Is it `C`?". The number of questions is 1 for `A`, 2 for `B`, 3 for `C` or `D`, exactly the codeword lengths and exactly $i(x)$. Average: 1.75 questions. The same number wears three costumes: average surprise, average code length, average yes/no questions. When you next see $H(X)$, hear "the price of this source in bits."

#fig([The optimal yes/no questioning strategy for the four-symbol source. Each leaf's depth equals the symbol's codeword length and its self-information $i(x) = -log_2 p(x)$. Common symbols sit shallow (cheap); rare symbols sit deep (expensive). The probability-weighted average depth is the entropy, $1.75$ bits.],
cetz.canvas({
  import cetz.draw: *
  let node(pos, label) = {
    circle(pos, radius: 0.32, fill: rgb("#eef4fb"), stroke: 0.7pt + rgb("#0b5394"))
    content(pos, text(size: 8pt)[#label])
  }
  // root
  node((0, 0), "?")
  // level 1
  node((-2.4, -1.4), [A])
  node((1.4, -1.4), "?")
  line((-0.25, -0.28), (-2.15, -1.18))
  line((0.25, -0.28), (1.15, -1.18))
  content((-1.55, -0.6), text(size: 7pt, fill: rgb("#9a2617"))[yes])
  content((0.95, -0.6), text(size: 7pt, fill: rgb("#0b6e4f"))[no])
  // level 2
  node((-0.4, -2.8), [B])
  node((2.8, -2.8), "?")
  line((1.18, -1.66), (-0.18, -2.6))
  line((1.62, -1.66), (2.6, -2.6))
  content((0.2, -2.05), text(size: 7pt, fill: rgb("#9a2617"))[yes])
  content((2.4, -2.05), text(size: 7pt, fill: rgb("#0b6e4f"))[no])
  // level 3
  node((1.9, -4.2), [C])
  node((3.8, -4.2), [D])
  line((2.6, -3.06), (2.05, -3.95))
  line((3.0, -3.06), (3.65, -3.95))
  content((1.95, -3.5), text(size: 7pt, fill: rgb("#9a2617"))[yes])
  content((3.75, -3.5), text(size: 7pt, fill: rgb("#0b6e4f"))[no])
}))

#algo(
  name: "Shannon entropy",
  year: "1948",
  authors: "Claude E. Shannon",
  aim: "Measure, in bits per symbol, the average information of a source, thereby giving the exact lower bound on its lossless compressed size.",
  complexity: "Θ(n) in the alphabet size n to evaluate, given the probabilities.",
  strengths: "Single number; exactly characterises the lossless floor; additive over independent sources; basis of every entropy coder.",
  weaknesses: "Requires a probability model; assumes a known source; the independent-symbols value ignores correlations between symbols (which conditional entropy then captures).",
  superseded: "Extended, never replaced. Conditional and joint entropy, differential entropy for continuous sources, and rate-distortion R(D) for lossy coding (Chapter 21) all build on it.",
)[
  Entropy is not an algorithm in the sorting-and-searching sense; it is the _quantity_ that the algorithms of Volume II compute against. Knowing $H(X)$ tells you, before you write a single line of a codec, how well any lossless codec _could_ possibly do on that source. If your compressor outputs close to $H(X)$ bits per symbol, stop optimising the entropy stage. You are near the wall.
]

== How big can entropy get? The bounds

Two questions present themselves immediately. What is the _smallest_ entropy a source can have, and what is the _largest_? The answers are clean, intuitive, and worth proving, because the proofs teach the two facts that the whole theory leans on: entropy is never negative, and uncertainty is greatest when nothing is predictable.

#theorem("Non-negativity")[For any source, $H(X) >= 0$, with equality if and only if some symbol is certain (one $p(x_i) = 1$ and the rest are $0$).]

#proof[
Each probability satisfies $0 <= p(x) <= 1$. For such a $p$, the surprisal $-log_2 p(x) >= 0$ (the log of a number in $(0, 1]$ is $<= 0$, so its negative is $>= 0$). Therefore every term $p(x) dot (-log_2 p(x))$ in the sum is a non-negative number times a non-negative number, hence non-negative. A sum of non-negative terms is non-negative, so $H(X) >= 0$.

When is it _exactly_ zero? A sum of non-negative terms is zero only if every term is zero. The term for symbol $x$ is zero either when $p(x) = 0$ (the symbol never occurs) or when $-log_2 p(x) = 0$, i.e. $p(x) = 1$. Since the probabilities must sum to 1, the only way for every symbol to have probability 0 or 1 is for exactly one symbol to have probability 1 and the rest 0: a _certain_ source. A source with no uncertainty carries no information: there is nothing to learn, nothing to compress, zero bits.
]

The upper bound is the more surprising one. It says uncertainty is maximised when every outcome is equally likely (the uniform distribution) and then the entropy is exactly $log_2 n$, the number of yes/no questions needed to pick one of $n$ equally likely things, which is precisely Hartley's 1928 measure. Predictability of _any_ kind lowers the entropy below this ceiling.

#theorem("Maximum entropy")[For a source over an alphabet of $n$ symbols, $H(X) <= log_2 n$, with equality if and only if the distribution is uniform, $p(x_i) = 1\/n$ for all $i$.]

We will prove this with a small, reusable tool: *Gibbs' inequality*, itself one of the most useful facts in the book, which reappears (as the non-negativity of the Kullback-Leibler divergence) in Chapter 20.

#mathrecall[The proof switches from base-2 logs to the *natural logarithm* $ln$, the logarithm in the special base $e approx 2.718$ that we met in Chapter 7. The two bases differ only by a fixed scaling, the *change-of-base* rule: $log_2 t = ln t \/ ln 2$, where $ln 2 approx 0.693$. Because $1\/ln 2 > 0$ is just a positive constant, multiplying or dividing an inequality by it never flips the direction, so anything we prove with $ln$ holds for $log_2$ too. We use $ln$ here only because it has the cleanest tangent line, as the next box shows.]

#gomaths("The key trick: ln x ≤ x − 1")[
Everything rests on one fact about the natural logarithm: for every $x > 0$,
$ ln x <= x - 1, $
with equality only at $x = 1$. Why is it true? The curve $y = ln x$ and the line $y = x - 1$ touch at $x = 1$ (both equal 0 there, and both have slope 1 there, since the derivative of $ln x$ is $1\/x$, equal to 1 at $x=1$). Because $ln x$ is _concave_ (it bends downward, since its slope $1\/x$ always decreases), it lies entirely _below_ its tangent line. That tangent line at $x = 1$ is exactly $y = x - 1$. Hence $ln x <= x - 1$ everywhere, touching only at $x = 1$. We will use this to compare two distributions.
]

#theorem("Gibbs' inequality")[For any two probability distributions $p$ and $q$ over the same $n$ symbols,
$ -sum_(i) p(x_i) log_2 p(x_i) <= -sum_(i) p(x_i) log_2 q(x_i), $
with equality if and only if $p = q$ everywhere. In words: coding $p$'s data with the _wrong_ model $q$ costs at least as much as coding it with the right model $p$.]

#proof[
Look at the difference between the two sides (the right minus the left). Pulling both logs together and switching to natural logs (recall $log_2 t = ln t \/ ln 2$, so we can factor out the positive constant $1\/ln 2$):
$ sum_i p(x_i) log_2 p(x_i)/(q(x_i)) = 1/(ln 2) sum_i p(x_i) ln p(x_i)/(q(x_i)). $
We want to show this is $>= 0$. Equivalently, show the _negative_ is $<= 0$:
$ 1/(ln 2) sum_i p(x_i) ln q(x_i)/(p(x_i)) <= 0. $
Apply the trick from the box with $x = q(x_i)\/p(x_i)$: since $ln x <= x - 1$,
$ sum_i p(x_i) ln q(x_i)/(p(x_i)) <= sum_i p(x_i) ( q(x_i)/(p(x_i)) - 1 ) = sum_i q(x_i) - sum_i p(x_i) = 1 - 1 = 0. $
Both distributions sum to 1, so the right side is $1 - 1 = 0$. Dividing by the positive constant $ln 2$ keeps the inequality, giving exactly what we wanted. Equality holds only when $q(x_i)\/p(x_i) = 1$ for every $i$, i.e. $p = q$.
]

Now the maximum-entropy theorem falls out in one line.

#proof[
(Maximum entropy.) Take $q$ to be the _uniform_ distribution, $q(x_i) = 1\/n$. Gibbs' inequality gives
$ H(X) = -sum_i p(x_i) log_2 p(x_i) <= -sum_i p(x_i) log_2 1/n = log_2 n dot sum_i p(x_i) = log_2 n. $
The last step used $sum_i p(x_i) = 1$. Equality holds (by the equality condition of Gibbs') exactly when $p$ is itself uniform. So a source over $n$ symbols can carry at most $log_2 n$ bits per symbol, achieved only when all symbols are equally likely.
]

Putting the two theorems together, for any source over $n$ symbols:
$ 0 <= H(X) <= log_2 n. $
The left end is a source with nothing to say; the right end is a source that is maximally unpredictable, pure noise and the hardest thing to compress. Every real source lives strictly between, and the distance below $log_2 n$ is the redundancy that compression harvests. A page of English over its 27-symbol alphabet (26 letters plus space) could carry up to $log_2 27 approx 4.75$ bits per character; Shannon's own 1951 experiments (next section) showed it actually carries closer to 1 to 1.5. That gap (roughly 3 bits per character thrown away by naive storage) is why text compresses so well.

=== The binary entropy function

The most important special case is a source with just two symbols: a biased coin that lands heads with probability $p$ and tails with probability $1 - p$. Its entropy, written $H(p)$ as a function of the single number $p$, is the *binary entropy function*:

$ H(p) = -p log_2 p - (1 - p) log_2 (1 - p). $

#fig([The binary entropy function $H(p)$. A coin is hardest to compress when it is fair ($p = 0.5$, entropy $1$ bit) and trivially compressible when it is heavily biased ($p$ near $0$ or $1$, entropy near $0$). Bias in either direction is what compression feeds on.],
cetz.canvas({
  import cetz.draw: *
  // axes
  line((0, 0), (6.2, 0), mark: (end: ">"))
  line((0, 0), (0, 3.4), mark: (end: ">"))
  content((6.4, -0.05), text(size: 8pt)[$p$])
  content((-0.45, 3.4), text(size: 8pt)[$H(p)$])
  // ticks
  content((0, -0.32), text(size: 7pt)[$0$])
  content((3, -0.32), text(size: 7pt)[$0.5$])
  content((6, -0.32), text(size: 7pt)[$1$])
  content((-0.35, 3.0), text(size: 7pt)[$1$])
  line((3, 0), (3, -0.1)); line((6, 0), (6, -0.1))
  line((0, 3.0), (-0.1, 3.0))
  // H(p) curve: sample points, x = 6p, y = 3*H
  let pts = ()
  let n = 40
  for k in range(1, n) {
    let p = k / n
    let h = -p * calc.log(p, base: 2) - (1 - p) * calc.log(1 - p, base: 2)
    pts.push((6 * p, 3 * h))
  }
  line(..pts, stroke: 1.2pt + rgb("#0b5394"))
  // dashed at peak
  line((3, 0), (3, 3.0), stroke: (paint: rgb("#9a2617"), dash: "dashed", thickness: 0.6pt))
  circle((3, 3.0), radius: 0.06, fill: rgb("#9a2617"), stroke: none)
}))

The curve tells the whole compression story in one picture. It is symmetric (a coin biased 90% heads is exactly as compressible as one biased 90% tails), it peaks at 1 bit when $p = 0.5$, and it plunges toward 0 as the coin becomes lopsided. A coin that is 99% heads has entropy $H(0.99) approx 0.08$ bits, so you could store a thousand such flips in about 80 bits, because they are almost all heads and the rare tails are the only surprises worth recording. Bias equals compressibility.

#checkpoint[A biased coin lands heads $3\/4$ of the time. What is its entropy? Is it more or less compressible than a fair coin?][$H(3\/4) = -(3\/4)log_2(3\/4) - (1\/4)log_2(1\/4) = (3\/4)(0.415) + (1\/4)(2) = 0.311 + 0.5 = 0.811$ bits. That is well below the fair coin's 1 bit, so the biased coin is _more_ compressible: its predictability (it usually says "heads") leaves less than a full bit of genuine surprise per flip.]

== Two symbols at once: joint and conditional entropy

So far each symbol stood alone. But real data is _correlated_: in English, a `q` is almost always followed by a `u`; in an image, a pixel looks much like the pixel beside it; in audio, this sample resembles the last. These correlations are pure gold for compression. If knowing the previous symbol tells you a lot about the next one, you barely need to spend any bits on the next one. To make that precise we need entropy for _pairs_ of symbols, and entropy for _one symbol given another_.

Let $X$ and $Y$ be two sources (say, two consecutive letters of text). The *joint entropy* measures the total uncertainty in the _pair_ $(X, Y)$ taken together. It is just the entropy of the combined symbol, using the joint probability $p(x, y)$, the probability that $X = x$ _and_ $Y = y$:

$ H(X, Y) = -sum_(x) sum_(y) p(x, y) log_2 p(x, y). $

#mathrecall[The *joint probability* $p(x, y)$ from Chapter 9 is the chance that both $X = x$ and $Y = y$ happen. The *conditional probability* $p(y | x) = p(x, y) \/ p(x)$ is the chance that $Y = y$ once you already know $X = x$. One more piece of vocabulary we need below: the *marginal* probability $p(x)$ is what you get by "summing out" the other variable, $p(x) = sum_y p(x, y)$: add up the joint probabilities over every value $Y$ could take, and the $Y$ part "averages away", leaving the plain probability of $X$ alone. (The name comes from the old habit of writing these row-and-column totals in the _margin_ of a probability table.)]

The *conditional entropy* $H(Y | X)$ measures something subtler and far more useful: _how much uncertainty remains about $Y$ once you already know $X$._ This is the heart of context-based compression. For a fixed known value $X = x$, the leftover uncertainty in $Y$ is just an ordinary entropy computed with the conditional distribution $p(y | x)$: call it $H(Y | X = x) = -sum_y p(y | x) log_2 p(y | x)$. But $X$ itself is random, so we average this over all the values $x$ might take, weighted by how often each occurs:

$ H(Y | X) = sum_(x) p(x) dot H(Y | X = x) = -sum_(x) sum_(y) p(x, y) log_2 p(y | x). $

#definition("Joint and conditional entropy")[
For sources $X, Y$ with joint distribution $p(x, y)$:
- *Joint entropy:* $H(X, Y) = -sum_(x, y) p(x, y) log_2 p(x, y)$, the total uncertainty of the pair.
- *Conditional entropy:* $H(Y | X) = -sum_(x, y) p(x, y) log_2 p(y | x)$, the average uncertainty remaining in $Y$ after $X$ is revealed.
]

=== The chain rule: uncertainty splits into pieces

Now comes the single most useful identity in the whole subject, and it says something your intuition already believes. The total uncertainty in a pair $(X, Y)$ equals the uncertainty in the first symbol _plus_ the uncertainty left in the second once you know the first. Information adds up, stage by stage.

#theorem("Chain rule for entropy")[
$ H(X, Y) = H(X) + H(Y | X). $
The joint uncertainty of two sources is the uncertainty of the first plus the conditional uncertainty of the second given the first.]

#proof[
Start from the right-hand side's hidden structure and the definition of conditional probability, $p(x, y) = p(x) dot p(y | x)$. Take $log_2$ of both sides: $log_2 p(x, y) = log_2 p(x) + log_2 p(y | x)$. Now multiply by $-p(x, y)$ and sum over all pairs $(x, y)$:
$ H(X, Y) = -sum_(x, y) p(x, y) log_2 p(x, y) = -sum_(x, y) p(x, y) log_2 p(x) - sum_(x, y) p(x, y) log_2 p(y | x). $
The second sum is, by definition, $H(Y | X)$. For the first sum, note $log_2 p(x)$ does not involve $y$, so we can collapse the inner sum over $y$: $sum_y p(x, y) = p(x)$ (summing the joint distribution over all values of $Y$ gives the marginal of $X$). Hence the first sum becomes $-sum_x p(x) log_2 p(x) = H(X)$. Adding the two pieces:
$ H(X, Y) = H(X) + H(Y | X). $
]

By the identical argument starting from $p(x, y) = p(y) p(x | y)$, we also get $H(X, Y) = H(Y) + H(X | Y)$. You may peel off either symbol first. The rule extends to any number of sources, peeling one symbol at a time:
$ H(X_1, X_2, ..., X_n) = H(X_1) + H(X_2 | X_1) + H(X_3 | X_1, X_2) + dots + H(X_n | X_1, ..., X_(n-1)). $
This telescoping form is _exactly_ how a real compressor thinks. It processes a stream left to right, and at each position it pays $H(X_k | X_1, ..., X_(k-1))$ bits: the cost of the next symbol _given everything seen so far_. A compressor with a good model of "what comes next given the context" is a compressor that drives each of these terms down. We will meet this idea again and again: in PPM (Chapter 33), in context mixing (Chapter 34), and at full force in language-model compression (Chapter 62).

=== A worked example: the cost of the letter after `q`

Make the chain rule concrete with the most famous correlation in English: the letter following `q`. Imagine a toy source where the previous letter $X$ is `q` one time in a hundred ($p(X = q) = 0.01$) and "some other letter" the other 99 times. We care about the next letter $Y$. After a non-`q`, the next letter is wide open; model it, generously, as carrying $H(Y | X = "non-q") = 4$ bits of uncertainty (close to the full alphabet). But after a `q`, the next letter is `u` with probability, say, $0.99$ and "something else" (as in "Qatar" or "qi") with probability $0.01$. That residual uncertainty is tiny:

$ H(Y | X = q) = -0.99 log_2 0.99 - 0.01 log_2 0.01 approx 0.0144 + 0.0664 = 0.081 "bits." $

Now average over the two contexts, weighting by how often each occurs. This is the conditional entropy:

$ H(Y | X) = p(q) dot H(Y | X = q) + p("non-q") dot H(Y | X = "non-q") = 0.01(0.081) + 0.99(4) = 3.96 "bits." $

A coder _blind_ to context pays about $4$ bits for every letter, including the `u` after a `q`. A coder that conditions on the previous letter pays only $0.081$ bits for that `u` (it was almost certain) and so pays $3.96$ bits on average across the stream. The saving is small here only because `q` is rare; pile up _all_ such correlations across the whole language (every letter pair, every word, every grammatical habit) and the conditional entropy collapses from ~4 bits toward Shannon's measured ~1.3. Each correlation you model is a term in the chain rule you drive down. _This is the entire business model of compression._

=== Conditioning never hurts: why context wins

Here is the fact that justifies the entire enterprise of context modelling, and it is exactly what your gut expects: *knowing more can only reduce (or leave unchanged) your average uncertainty.* Learning the previous letter can never, on average, make you _more_ confused about the next one.

#theorem("Conditioning reduces entropy")[$H(Y | X) <= H(Y)$, with equality if and only if $X$ and $Y$ are independent.]

#proof[
Consider the difference $H(Y) - H(Y | X)$. Expanding both terms over the joint distribution (using $p(y) = sum_x p(x, y)$ to write $H(Y)$ as a double sum):
$ H(Y) - H(Y | X) = -sum_(x, y) p(x, y) log_2 p(y) + sum_(x, y) p(x, y) log_2 p(y | x) = sum_(x, y) p(x, y) log_2 (p(y | x))/(p(y)). $
Writing $p(y | x) = p(x, y)\/p(x)$, the ratio inside is $p(x, y) \/ (p(x) p(y))$, so
$ H(Y) - H(Y | X) = sum_(x, y) p(x, y) log_2 (p(x, y))/(p(x) p(y)). $
This quantity is the *mutual information* $I(X; Y)$, the formal star of Chapter 20, and the same Gibbs/$ln x <= x - 1$ trick we used above shows it is always $>= 0$. (Treat $p(x, y)$ as the "true" distribution and the product $p(x) p(y)$ as the "model"; Gibbs' inequality gives the result directly.) Equality holds exactly when $p(x, y) = p(x) p(y)$ for all pairs, that is, when $X$ and $Y$ are *independent*, in which case knowing $X$ tells you nothing about $Y$. Therefore $H(Y | X) <= H(Y)$.
]

#keyidea[
*Context can only help.* The inequality $H(Y | X) <= H(Y)$ is the mathematical promise behind every context-based compressor in this book. A coder that predicts the next symbol _without_ context pays $H(Y)$ bits; one that conditions on the previous symbol pays only $H(Y | X)$, and the savings is exactly the mutual information $I(X; Y)$, the correlation measured in bits. This is why `qu` compresses so well, why neighbouring pixels are coded together, and why a language model that conditions on thousands of previous tokens crushes one that looks only at the current byte.
]

#misconception[More context always means smaller files, so I should always condition on as much history as possible.][On average, in theory, more conditioning never _increases_ entropy. That is the theorem. But two real-world catches bite. First, the theorem is about the _true_ probabilities; a real compressor must _estimate_ them from finite data, and a huge context has so many possible histories that each is seen only a few times, giving noisy estimates (the "context dilution" or sparse-data problem that PPM's escape mechanism, Chapter 33, exists to fix). Second, the model that maps context to predictions must itself be stored or computed, and a giant context can cost more to describe than it saves, which is the model-cost tradeoff that becomes the Minimum Description Length principle of Chapter 23. Conditioning helps in the ideal limit; engineering decides how much you can actually afford.]

== Measuring entropy in Python

Theory is sharper when you can compute it. Let us write a few lines of Python that take any data and report its entropy, turning the abstract floor into a concrete number we can read off real files. We use only tools from the Python primers (Chapters 15–17): a `Counter` to tally symbols (Chapter 16), a comprehension to build the sum, and the `math.log2` function.

#gopython("collections.Counter and math.log2")[
A *`Counter`* (from Python's `collections` module) is a dictionary specialised for counting. You hand it any sequence and it returns, for each distinct element, how many times it appeared:
```python
from collections import Counter
counts = Counter("mississippi")
print(counts)          # Counter({'i': 4, 's': 4, 'p': 2, 'm': 1})
print(counts["s"])     # 4
print(counts.total())  # 11  (sum of all counts, Python 3.10+)
```
The function *`math.log2(x)`* returns the base-2 logarithm of `x`, exactly the $log_2$ of our formulas:
```python
import math
print(math.log2(8))    # 3.0      because 2**3 == 8
print(math.log2(0.5))  # -1.0     because 2**-1 == 0.5
```
In the project we tally the symbols with `tinyzip`'s own `histogram()` helper (Step 2, Chapter 16), which is itself just a thin wrapper around this counting idea, then turn counts into probabilities by dividing by the total and sum $-p log_2 p$ over the symbols that actually appear (so we never call `log2(0)`).
]

#project("Step 6 - model.entropy: the entropy meter")[
This is canonical *Step 6* of the `tinyzip` build (the step shared between this chapter and Chapter 19). Every compressor we build from Chapter 24 onward will want to know the entropy of its input, both to set expectations ("this is the floor; how close did I get?") and to drive modelling decisions. So we start the project's `model.py` module, the home of all things probabilistic, with a small, reusable entropy meter. It reuses `utils.histogram` from Step 2 (Chapter 16), the byte tally we already built, rather than re-counting from scratch. Drop this in `tinyzip/model.py`:

```python
"""tinyzip.model - probability and information measures for tinyzip."""
import math

from tinyzip.utils import histogram   # Step 2 (Ch 16): byte -> count


def entropy(data: bytes) -> float:
    """Return the order-0 Shannon entropy of `data`, in bits per symbol.

    This is the lossless floor for any codec that treats each byte
    independently (ignores correlations between neighbouring bytes).
    """
    if not data:                       # empty input has no symbols
        return 0.0
    counts = histogram(data)           # byte value (0..255) -> how many times
    n = len(data)                      # total number of symbols
    h = 0.0
    for count in counts.values():
        p = count / n                  # probability of this byte value
        h -= p * math.log2(p)          # accumulate  -p * log2(p)
    return h


def ideal_size_bytes(data: bytes) -> float:
    """Smallest possible size (bytes) at the order-0 entropy floor."""
    return entropy(data) * len(data) / 8
```

Try it on a few inputs to see the theory breathe:

```python
>>> from tinyzip.model import entropy, ideal_size_bytes
>>> entropy(b"AAAAAAAA")              # one symbol, certain
0.0
>>> entropy(bytes([0, 1, 2, 3]) * 64) # four symbols, uniform
2.0
>>> entropy(b"mississippi")
1.8209...                            # the famous example
>>> text = open("book.txt", "rb").read()
>>> entropy(text)                    # English prose
4.5...                              # bits per byte, ~ Shannon's letters
>>> ideal_size_bytes(text) / len(text)
0.57                                # can't beat ~57% with an order-0 model
```

Two lessons jump out. The constant string has entropy `0.0`, perfectly compressible. The four-symbol uniform stream hits exactly `2.0` bits, the $log_2 4$ ceiling. English text lands near 4.5 bits per byte, so storing it as 8 bits per byte wastes nearly half. Note the phrase "order-0": this meter treats each byte _independently_, so it sees only the letter-frequency redundancy, not the `qu`-style correlations. The chain rule told us those correlations are extra, conditional redundancy our order-0 meter is blind to. Capturing them is the job of the higher-order models in Volume II, and the gap between this number and the true entropy is the prize they chase.
]

#tryit[
Run `entropy()` on three files of your own: a plain-text essay, an already-compressed `.zip` or `.jpg`, and a recording of silence or a solid-colour image. The essay should land around 4.5–5 bits/byte (lots of redundancy). The compressed file should sit just under 8.0 bits/byte. A successful compressor has already pushed it _to_ the floor, leaving almost nothing for an order-0 model to find (trying to recompress it is nearly hopeless). The silence/solid file should be near 0. You have just measured, with ten lines of code, the thing Shannon defined in 1948.]

== The entropy of English, and the meaning of redundancy

In 1951 Shannon ran one of the most charming experiments in the history of science to pin down a number our entropy meter only half-measures: the true entropy of printed English. He could not write down the probability of every letter given every possible preceding context (no one could) so he used a living model that already knew it: a human being. He showed people text up to some point and asked them to _guess the next letter_, recording how many guesses they needed. A good guesser nails common continuations instantly (after "th" you guess "e" and are usually right) and struggles only at genuine surprises. From the distribution of guess-counts, Shannon bounded the per-letter entropy of English at roughly *1 to 1.5 bits per character*, far below the $log_2 27 approx 4.75$ bits an order-0 model allows and a universe below the 8 bits per byte of naive ASCII storage.

That gap has a name we have used loosely and can now define exactly.

#definition("Redundancy")[
The *redundancy* of a representation is the difference between the number of bits it actually spends per symbol and the source's entropy:
$ "redundancy" = bar(L) - H(X) >= 0, $
where $bar(L)$ is the average code length. It is the compressible slack: the bits a perfect coder would remove. A representation with zero redundancy is _incompressible_; it already sits on the entropy floor.
]

English text stored as ASCII spends 8 bits per character against a true entropy near 1.3: a redundancy of roughly 6.7 bits per character, meaning more than 80% of an English text file is, in principle, removable. This is why text compressors routinely shrink prose to a fifth of its size or less. And it is why Shannon's 1951 number is not a curiosity but a target: every text compressor in this book, from Huffman to PPM to a 70-billion-parameter language model, is an attempt to reach the 1.3-bit floor that Shannon measured by asking people to play "guess the next letter." The language model is just a vastly better guesser than the human volunteers were.

#aside[
The same experiment, run today against a large language model instead of a human, gives a sharper estimate, and the connection is now literal. A language model assigns a probability to every possible next token; the negative log of the probability it gave to the _actual_ next token is exactly the self-information you pay to encode it. Average that over a corpus and you have measured the model's cross-entropy, which _is_ its compression rate. Chapter 62 makes this precise and shows that pairing such a model with an arithmetic coder yields a record-setting general compressor. Shannon's 1951 parlour game and the 2024 Hutter Prize record (110,793,128 bytes of Wikipedia, by `fx2-cmix`) are the same experiment, seventy-three years apart.]

#scoreboard(caption: "the entropy floor for our running text sample (order-0)",
  [Raw bytes (ASCII)], [8.00 bits/sym], [1.00×], [no modelling at all, the baseline],
  [Order-0 entropy floor], [~4.5 bits/sym], [~0.57×], [best _any_ per-byte code can do (this chapter)],
  [True entropy (Shannon 1951)], [~1.3 bits/sym], [~0.16×], [needs context; chased in Volume II],
)

The scoreboard captures the whole arc ahead. We have not built a compressor in this chapter. We have built the _ruler_ that tells every future compressor how well it could possibly do, and how much room remains. The order-0 floor (~4.5 bits) is what a frequency-based code like Huffman will approach in Chapter 24. The true floor (~1.3 bits) is what context models spend the rest of Volume II reaching for. The distance between them is the chain rule's conditional redundancy, made visible.

#takeaways((
  [The *self-information* of an event is $i(x) = -log_2 p(x)$ bits: rare events are surprising and informative, certain events carry zero bits. The logarithm is forced by the rule that information from independent events must add.],
  [*Shannon entropy* $H(X) = -sum_x p(x) log_2 p(x)$ is the expected self-information. Read it three ways: average surprise, average optimal yes/no questions, and the bit-floor on lossless coding.],
  [Entropy is bounded: $0 <= H(X) <= log_2 n$. It is zero only for a certain source and maximal only for a uniform one. *Predictability of any kind lowers entropy*, and that lowering is the compressible redundancy.],
  [The *binary entropy function* $H(p)$ peaks at 1 bit for a fair coin and collapses toward 0 as a coin becomes biased: bias is compressibility.],
  [*Joint* and *conditional* entropy extend the idea to correlated symbols, and the *chain rule* $H(X, Y) = H(X) + H(Y | X)$ shows uncertainty splits stage by stage, which is exactly how a streaming compressor pays its bits.],
  [*Conditioning never increases entropy*: $H(Y | X) <= H(Y)$, with the savings equal to the mutual information. This is the theorem that makes context-based compression work.],
  [English carries only ~1.3 bits per character (Shannon, 1951) against 8 bits of naive storage. That redundancy is what every text compressor in this book attacks.],
))

== Exercises

#exercise("18.1", 1)[
A weather source emits one of four symbols each day: `sun` with probability $1\/2$, `cloud` with $1\/4$, `rain` with $1\/8$, and `snow` with $1\/8$. (a) Compute the self-information of each symbol in bits. (b) Compute the entropy $H(X)$. (c) Design a binary prefix code whose codeword lengths equal each symbol's self-information, and verify its average length equals $H(X)$.]
#solution("18.1")[
(a) $i("sun") = log_2 2 = 1$, $i("cloud") = log_2 4 = 2$, $i("rain") = i("snow") = log_2 8 = 3$ bits. (b) $H = (1\/2)(1) + (1\/4)(2) + (1\/8)(3) + (1\/8)(3) = 0.5 + 0.5 + 0.375 + 0.375 = 1.75$ bits/symbol. (c) Assign `sun`$=$`0`, `cloud`$=$`10`, `rain`$=$`110`, `snow`$=$`111`. Lengths 1, 2, 3, 3 match the self-informations. Average length $= (1\/2)(1)+(1\/4)(2)+(1\/8)(3)+(1\/8)(3) = 1.75$ bits $= H$. The code is a prefix code (no codeword is a prefix of another), so it is uniquely decodable, and it hits the floor exactly because every probability is a power of two.]

#exercise("18.2", 1)[
Explain in plain words why a source that always emits the same symbol has entropy 0, and why a fair coin has entropy exactly 1 bit. Then state which of these two sources is impossible to compress and which is trivial to compress, and why those are different things.]
#solution("18.2")[
A constant source has one symbol with probability 1, giving $i = -log_2 1 = 0$ and $H = 0$: there is no surprise, nothing to learn, nothing to send. It is _trivially_ compressible (a few bits say "repeat `X` forever"). A fair coin has two equally likely outcomes, each with $i = 1$ bit, so $H = 1$ bit; it is at the maximum for two symbols and is _impossible to compress below 1 bit per flip_: every outcome is a genuine, irreducible surprise. The distinction: the constant source has zero entropy and so almost nothing to store; the fair coin has maximal (for its alphabet) entropy and so cannot be shrunk. "Trivial to compress" means low entropy; "impossible to compress" means the data is already at its entropy floor.]

#exercise("18.3", 2)[
A biased coin lands heads with probability $p$. (a) Write its entropy $H(p)$. (b) Using calculus (Chapter 11), show that $H(p)$ is maximised at $p = 1\/2$. (c) Evaluate $H(0.1)$ and explain why a stream of such coin flips can be compressed to about a tenth of its naive size.]
#solution("18.3")[
(a) $H(p) = -p log_2 p - (1-p) log_2 (1-p)$. (b) Differentiate (using $dif/(dif p)[p log_2 p] = log_2 p + 1\/ln 2$): $H'(p) = -log_2 p + log_2 (1-p) = log_2((1-p)\/p)$. Setting $H'(p) = 0$ gives $(1-p)\/p = 1$, i.e. $p = 1\/2$. The second derivative is negative there (the curve is concave), so it is a maximum, with $H(1\/2) = 1$ bit. (c) $H(0.1) = -0.1 log_2 0.1 - 0.9 log_2 0.9 approx 0.1(3.322) + 0.9(0.152) = 0.332 + 0.137 = 0.469$ bits. Naive storage spends 1 bit per flip; the entropy floor is ~0.47 bits, so a good coder shrinks the stream to under half. The long runs of "heads" are highly predictable and nearly free to encode.]

#exercise("18.4", 2)[
Two correlated bits: $p(0,0) = 1\/2$, $p(1,1) = 1\/4$, $p(0,1) = 1\/8$, $p(1,0) = 1\/8$. Compute (a) the joint entropy $H(X, Y)$, (b) the marginal $H(X)$, and (c) the conditional entropy $H(Y | X)$ via the chain rule. Confirm $H(Y | X) <= H(Y)$.]
#solution("18.4")[
(a) $H(X,Y) = -[1/2 log_2 1/2 + 1/4 log_2 1/4 + 1/8 log_2 1/8 + 1/8 log_2 1/8] = 1/2 + 1/2 + 3/8 + 3/8 = 1.75$ bits. (b) Marginals of $X$: $p(X=0) = 1/2 + 1/8 = 5/8$, $p(X=1) = 1/4 + 1/8 = 3/8$. $H(X) = -(5/8)log_2(5/8) - (3/8)log_2(3/8) = (5/8)(0.678) + (3/8)(1.415) = 0.424 + 0.531 = 0.954$ bits. (c) Chain rule: $H(Y|X) = H(X,Y) - H(X) = 1.75 - 0.954 = 0.796$ bits. For the check, marginals of $Y$: $p(Y=0) = 1/2 + 1/8 = 5/8$, $p(Y=1) = 3/8$, so $H(Y) = 0.954$ bits as well. Indeed $H(Y|X) = 0.796 <= 0.954 = H(Y)$: knowing $X$ removed about $0.158$ bits of uncertainty about $Y$, which is the mutual information (the correlation in bits).]

#exercise("18.5", 2)[
Using the `tinyzip` entropy meter from Step 6 (`model.entropy`), predict (without running it) the order-0 entropy in bits/symbol of: (a) `b"\x00" * 1000`; (b) `bytes(range(256)) * 4`; (c) a 1000-byte string drawn uniformly at random from the 16 hex digits `b"0123456789abcdef"`. Then state, for each, the smallest possible file size at the floor.]
#solution("18.5")[
(a) One symbol, certain: $H = 0$ bits/symbol; ideal size $= 0$ bytes (a constant run). (b) 256 symbols, each appearing equally often: uniform over 256, $H = log_2 256 = 8$ bits/symbol; ideal size $= 8 times 1024 \/ 8 = 1024$ bytes. There is _no_ compression here; it is already at the byte ceiling. (c) 16 equally likely symbols: $H = log_2 16 = 4$ bits/symbol; ideal size $= 4 times 1000 \/ 8 = 500$ bytes, exactly half, because each hex character needs only 4 of its 8 stored bits.]

#exercise("18.6", 3)[
Derive the self-information formula from its axioms. Suppose a function $i(p)$ defined for $0 < p <= 1$ satisfies: (i) $i$ is continuous; (ii) $i(1) = 0$; and (iii) $i(p dot q) = i(p) + i(q)$ for all $p, q$ (independent events add). Show that $i(p) = -c log p$ for some constant $c > 0$, and explain how the choice of $c$ (equivalently, the log base) sets the unit of information.]
#solution("18.6")[
Property (iii), $i(p q) = i(p) + i(q)$, is the *Cauchy functional equation* in multiplicative form. Substitute $p = e^(-u)$, $q = e^(-v)$ and define $g(u) = i(e^(-u))$; then (iii) becomes $g(u + v) = g(u) + g(v)$, the additive Cauchy equation. With continuity (i), its only solutions are linear: $g(u) = c u$ for a constant $c$. Translating back, $i(p) = g(-ln p) = -c ln p$. Property (ii) is automatic since $ln 1 = 0$. Because $i$ must _decrease_ in $p$ (rarer is more informative) and $ln p < 0$ for $p < 1$, we need $c > 0$. Finally, $-c ln p = -(c ln 2) log_2 p$, so choosing $c = 1\/ln 2$ (base-2 logs) gives the unit *bit*, $c = 1$ (natural logs) gives the *nat*, and $c = 1\/ln 10$ gives the *hartley*. The base is just a unit choice; the _shape_ $-log p$ is forced by the three axioms.]

#exercise("18.7", 3)[
Prove that for any source over $n$ symbols, $H(X) <= log_2 n$, using Gibbs' inequality with the uniform distribution $q(x) = 1\/n$, and state precisely when equality holds. Then explain why this gives a one-line proof that the most-compressible-resistant source over a fixed alphabet is the uniform (white-noise) one.]
#solution("18.7")[
Gibbs' inequality states $-sum_i p_i log_2 p_i <= -sum_i p_i log_2 q_i$ for any distribution $q$. Take $q_i = 1\/n$ (uniform). The right side is $-sum_i p_i log_2 (1\/n) = (log_2 n) sum_i p_i = log_2 n$, using $sum_i p_i = 1$. Hence $H(X) = -sum_i p_i log_2 p_i <= log_2 n$. By the equality condition of Gibbs', equality holds iff $p = q$, i.e. iff $p_i = 1\/n$ for all $i$: the uniform distribution. Interpretation: among all sources over an $n$-symbol alphabet, the uniform one has the largest entropy, $log_2 n$, and therefore the highest floor and the least removable redundancy. A uniform source is "white noise": maximally unpredictable, the worst case for any compressor, which can do no better than $log_2 n$ bits per symbol.]

#exercise("18.8", 3)[
("Entropy is concave.") Let $p$ and $r$ be two distributions over the same alphabet, and let $m = lambda p + (1 - lambda) r$ be their mixture for some $0 <= lambda <= 1$ (so $m$ is a valid distribution). Argue _informally but convincingly_, using the "conditioning reduces entropy" theorem, that $H(m) >= lambda H(p) + (1 - lambda) H(r)$: mixing two sources never produces _less_ uncertainty than the average of their separate uncertainties. (Hint: imagine a hidden coin with bias $lambda$ that selects which source to draw from.)]
#solution("18.8")[
Introduce a hidden selector $S$: a coin that comes up "use $p$" with probability $lambda$ and "use $r$" with probability $1 - lambda$. Let $Y$ be the symbol actually drawn, from $p$ if $S$ chose $p$ and from $r$ otherwise. Then the _marginal_ distribution of $Y$ is exactly the mixture $m = lambda p + (1-lambda) r$, so $H(Y) = H(m)$. The _conditional_ entropy $H(Y | S)$ averages the entropy within each chosen source: $H(Y | S) = lambda H(p) + (1 - lambda) H(r)$. By the theorem that conditioning reduces entropy, $H(Y | S) <= H(Y)$, i.e. $lambda H(p) + (1 - lambda) H(r) <= H(m)$. This is concavity. Intuitively: revealing _which_ source produced each symbol can only reduce your average uncertainty, so hiding that selector (i.e. just mixing) leaves uncertainty at least as high as the within-source average. Mixing distinct sources blurs them together and raises entropy.]

== Further reading

- Claude E. Shannon, #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[_A Mathematical Theory of Communication_], Bell System Technical Journal 27 (1948), 379–423 & 623–656. The founding paper; Part I, Sections 6–7 define entropy. Astonishingly readable for so foundational a work.
- Claude E. Shannon, #link("https://archive.org/details/bstj30-1-50")[_Prediction and Entropy of Printed English_], Bell System Technical Journal 30 (1951), 50–64. The "guess the next letter" experiment that bounded English at ~1–1.5 bits/character.
- Thomas M. Cover and Joy A. Thomas, _Elements of Information Theory_ (2nd ed., Wiley, 2006), Chapter 2. The modern standard treatment of entropy, joint/conditional entropy, and the chain rule, with full rigour.
- David J. C. MacKay, #link("https://www.inference.org.uk/itila/")[_Information Theory, Inference, and Learning Algorithms_] (Cambridge, 2003), Chapters 2–4. Gloriously intuitive, free online, with the same "twenty questions" spirit as this chapter.
- Jimmy Soni and Rob Goodman, _A Mind at Play: How Claude Shannon Invented the Information Age_ (Simon & Schuster, 2017). The definitive biography, for the human story behind the equation.

#bridge[
We have the ruler. We proved that no lossless code can beat $H(X)$ bits per symbol _on average_, but only by waving at an example where the probabilities were tidy powers of two. _Can the floor always be reached?_ What if the probabilities are awkward, like $1\/3$, whose self-information $log_2 3 approx 1.585$ is not a whole number of bits? You cannot emit 1.585 bits. Chapter 19, _The Source Coding Theorem_, answers this head-on: it introduces *prefix codes* and the *Kraft–McMillan inequality* (which says exactly which sets of codeword lengths are possible), the idea of *typical sequences*, and then proves Shannon's noiseless source coding theorem: by coding long _blocks_ of symbols at once, you can squeeze the per-symbol cost as close to $H(X)$ as you like. The floor we measured here is real, it is tight, and Chapter 19 shows you how to stand on it.
]
