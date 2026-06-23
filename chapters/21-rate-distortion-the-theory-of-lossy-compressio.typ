#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Rate–Distortion: The Theory of Lossy Compression

#epigraph[There is a duality between the problem of transmitting information ... and a corresponding problem of reproducing a source within a prescribed fidelity criterion.][Claude E. Shannon, _Coding Theorems for a Discrete Source with a Fidelity Criterion_, 1959]

Here is a puzzle with a number you can almost taste. A song on a music CD stores each tiny slice of sound as a 16-bit number, 44,100 slices every second, two channels — about 1.4 million bits per second of audio. An MP3 of the very same song, the kind that filled the world's pockets in the 2000s, throws away more than ninety percent of those bits and yet, to almost every listener, sounds _identical_. Ten times smaller, and you cannot hear the difference. How is that not magic, or fraud?

It is neither. It is the central fact of lossy compression: most of the bits in a faithful recording carry detail that no human ear, eye, or brain will ever notice. The trick is to find those bits and burn them — _on purpose_. But that immediately raises a sharper, scarier question. If I am allowed to throw bits away, where is the line? How few bits can I possibly get away with if I promise the result will be "off" by no more than some small amount I am willing to tolerate? Is there a hard floor — a number, in bits, below which _no_ scheme on Earth can go without breaking my promise — the way entropy was a hard floor for lossless coding?

There is. Shannon found it, twice: a sketch in his founding 1948 paper and a full theory in 1959. It is a curve, not a single number, and it is the most important curve in all of media compression. Every JPEG you have ever opened, every video you have ever streamed, every voice call you have ever made is a heuristic attempt to ride along it. This chapter builds that curve from scratch — what it means, why it cannot be beaten, what it equals for the most important source in the world, how to compute it by hand and by machine, and how, in the 2020s, a third axis cracked it open and changed what "good enough" even means.

#recap[
In Chapter 18 we built _entropy_ $H(X) = -sum_x p(x) log_2 p(x)$, the average surprise of a source in bits. In Chapter 19 the _Source Coding Theorem_ turned $H(X)$ into a hard floor for _lossless_ compression: no code beats it, arithmetic coding reaches it. In Chapter 20 we forged _mutual information_ $I(X; Y) = H(X) - H(X|Y)$ — the bits one variable reveals about another — together with the _KL divergence_ $D_"KL"(p||q)$ (the wasted bits of a wrong model), and proved the _Noisy-Channel Theorem_: capacity $C = max_(p(x)) I(X;Y)$ is the ceiling for reliable communication. Chapter 20 also showed mutual information is _convex_ in the channel, and Chapter 11 gave us _Jensen's inequality_ for convex and concave functions. This chapter completes Shannon's grand picture. The floor $H$ assumed _perfect_ reconstruction. Now we deliberately allow error, and ask: how low can the rate go? The answer, beautifully, is _again a mutual information squeezed against a constraint_. We lean on logarithms (Chapter 7), probability and conditional probability (Chapter 9), expectation and variance (Chapter 10), $sum$ / $integral$ notation and convexity (Chapter 11), mutual information and KL divergence (Chapter 20), and Python dictionaries and loops (Chapters 15–16).
]

#objectives((
  [Define a _distortion measure_ $d(x, hat(x))$ and the _average distortion_ $EE[d(X, hat(X))]$, and explain why the choice of $d$ is the whole game.],
  [State the _rate–distortion function_ $R(D) = min I(X; hat(X))$ over all test channels meeting a distortion budget, and read off its shape: convex, decreasing, $R(D_max) = 0$.],
  [Prove the _converse_ (no codec beats $R(D)$) and understand the _achievability_ half, so you know $R(D)$ is an exact limit and not a guess.],
  [Derive the _Gaussian_ rate–distortion function $R(D) = 1/2 log_2(sigma^2 \/ D)$ and the "$6$ dB per bit" rule, and extend it to many coefficients by _reverse water-filling_.],
  [Run the _Blahut–Arimoto algorithm_ by hand and in Python to compute $R(D)$ for any discrete source and distortion measure.],
  [Explain the modern _rate–distortion–perception_ trade-off (Blau–Michaeli, 2019) and why "looks real" and "is close" are different, sometimes opposing, goals.],
))

== Distortion: putting a number on "how wrong"

Lossless compression had exactly one enemy — redundancy — and one promise: give the bits back, every single one. Lossy compression tears up that promise. The decompressor will hand you back something _close_ to the original but not equal to it, and the first thing we must do, before we can say anything precise, is agree on what "close" means. Without that, the question "how few bits?" has no answer, because you could always answer "zero — just return a black image" and shrug at the complaints.

So we need a number. Let the source emit a symbol $x$ (a pixel value, an audio sample, a letter), and let the reconstruction we hand back be $hat(x)$ (pronounced "x-hat"; the little hat means "our estimate of $x$"). A _distortion measure_ is simply a rule $d(x, hat(x))$ that returns a non-negative number saying how bad it is to have reproduced $x$ as $hat(x)$. Zero means perfect: $d(x, x) = 0$. The bigger the number, the worse the crime.

#definition("Distortion measure")[
A _distortion measure_ is a function $d : cal(X) times hat(cal(X)) -> [0, infinity)$ assigning to each source symbol $x$ and reconstruction symbol $hat(x)$ a cost $d(x, hat(x)) >= 0$, with $d(x, x) = 0$. Here $cal(X)$ is the source alphabet and $hat(cal(X))$ the reconstruction alphabet (often the same set). The cost of a whole message is the _average_ per-symbol distortion.
]

Three distortion measures do almost all the work in this book, and you should hold them in your hand like coins:

- *Squared error*, $d(x, hat(x)) = (x - hat(x))^2$. The workhorse. If a true pixel is $130$ and you reconstruct $134$, the distortion is $(130 - 134)^2 = 16$. Squaring punishes big errors far more than small ones — an error of $10$ costs $100$, but two errors of $5$ cost only $25 + 25 = 50$. Its average over a message is the _mean squared error_ (MSE), the single most-used number in all of signal processing.
- *Absolute error*, $d(x, hat(x)) = abs(x - hat(x))$. Gentler on outliers; the same $130$-vs-$134$ costs just $4$.
- *Hamming distortion*, $d(x, hat(x)) = 0$ if $x = hat(x)$ and $1$ otherwise. The right measure for symbols with no notion of "near" — letters, class labels, bits. Its average is exactly the _probability of error_, the fraction of symbols you got wrong.

#gomaths("Average distortion as an expectation")[
We never care about the distortion of one symbol in isolation; we care about the _average_ over the whole stream. In Chapter 10 we met the _expectation_ $EE[Z]$ of a quantity $Z$ — its probability-weighted average, $EE[Z] = sum_z p(z) z$. Distortion is exactly such a quantity. If the source symbol $X$ and the reconstruction $hat(X)$ are random, with joint probability $p(x, hat(x))$ of seeing the pair $(x, hat(x))$, then the _average distortion_ is

$ EE[d(X, hat(X))] = sum_x sum_(hat(x)) p(x, hat(x)) thin d(x, hat(x)). $

Tiny example. A coin-flip source: $X = 0$ or $1$ with probability $1/2$ each. Suppose our scheme always outputs $hat(X) = 0$. Under Hamming distortion, $d = 0$ when $X = 0$ (probability $1/2$) and $d = 1$ when $X = 1$ (probability $1/2$), so $EE[d] = 1/2 dot 0 + 1/2 dot 1 = 0.5$. We are wrong half the time, and the average distortion is $0.5$ — exactly the error probability. The expectation turns a per-symbol rule into one honest number for the whole source.
]

Why insist that the _choice_ of $d$ is "the whole game"? Because the same bitstream is wonderful under one measure and worthless under another. Squared error says a photo with a faint, uniform haze added everywhere is barely distorted; your eye says it looks washed-out and wrong. Squared error says a photo where ten percent of pixels are flipped to random values but the rest are perfect is _badly_ distorted; your eye, if those pixels are scattered as fine grain, may call it "a bit noisy" and move on. The number $d$ encodes a theory of what matters, and if that theory disagrees with the human looking at the screen, every bit you spent optimizing it was spent in the wrong place. Hold that thought — it returns at the end of the chapter as the deepest idea in modern compression.

#keyidea[
Lossy compression has no meaning until you fix a distortion measure $d(x, hat(x))$. It is not a technicality you bolt on at the end; it is the _definition_ of the problem. Change $d$ and you change which bits are precious and which are trash. The entire art of perceptual coding — JPEG's quantization tables, MP3's masking model, modern "generative" codecs — is the art of choosing a $d$ that matches human perception.
]

#misconception[More bits always means a better-looking result.][
Only if "better" is measured by the same $d$ the encoder optimized. A codec tuned to minimize squared error can spend its extra bits sharpening edges your eye does not care about while leaving a perceptually obvious color shift untouched. Two files of identical size, identical MSE, can look dramatically different to a person — because MSE is a _model_ of perception, and a crude one. "More bits" buys lower distortion _under the chosen measure_, not automatically lower _perceived_ error.
]

== The rate–distortion function: the floor for forgetting

Now the big question, made precise. Fix a source with distribution $p(x)$ and a distortion measure $d$. We are willing to tolerate an _average_ distortion of at most $D$. Across all conceivable schemes — every encoder, every codebook, every clever trick, real or imaginary — what is the _smallest possible rate_, in bits per symbol, that still keeps $EE[d(X, hat(X))] <= D$?

Shannon's answer is one of the great surprises of the field, because it does not mention encoders or codebooks at all. It is, once again, a mutual information.

Picture the encoder-plus-decoder, viewed from far away, as a black box that takes in $X$ and emits $hat(X)$. From the outside, all that box _does_ is define a conditional probability $p(hat(x) | x)$ — the chance that source symbol $x$ comes out reconstructed as $hat(x)$. Information theorists call this conditional distribution a _test channel_, because it looks exactly like the noisy channels of Chapter 20, only here we _get to design the noise_. A test channel that always returns $hat(x) = x$ has zero distortion but maximal information flow; a test channel that ignores its input and returns a constant has zero information flow but large distortion. In between lies a trade-off, and the quantity that measures "information flow" through the box is precisely the mutual information $I(X; hat(X))$ from Chapter 20 — the number of bits about $X$ that survive in $hat(X)$.

So Shannon's recipe is: among all test channels $p(hat(x)|x)$ whose average distortion stays within budget, find the one that lets through the _fewest_ bits.

#definition("Rate–distortion function")[
For a source $X tilde p(x)$ and distortion measure $d$, the _rate–distortion function_ is
$ R(D) = min_(p(hat(x)|x) : thin EE[d(X, hat(X))] <= D) thin I(X; hat(X)). $
The minimum is taken over every conditional distribution (test channel) $p(hat(x)|x)$ whose induced average distortion is at most $D$. $R(D)$ is measured in bits per source symbol.
]

Read that definition like a sentence: _produce a reconstruction that is as statistically cheap — as low in mutual information — as you can manage, subject to staying faithful enough._ It is the mirror image of channel capacity. Capacity was a $max$ of mutual information (push as many bits as possible through a fixed noisy channel); rate–distortion is a $min$ of mutual information (let as few bits as possible define a reconstruction we are willing to accept). Shannon saw this duality clearly — it is the "duality" in the epigraph — and it is why the same machinery, even the same algorithm, solves both.

#note[
A subtlety worth naming, because it confuses everyone once. In Chapter 20 we maximized $I(X;Y)$ over the _input_ distribution $p(x)$, holding the channel $p(y|x)$ fixed by physics. Here we _minimize_ $I(X;hat(X))$ over the _channel_ $p(hat(x)|x)$, holding the input $p(x)$ fixed by the source. Both are the same convex object — mutual information — optimized from opposite ends. Convexity (Chapter 11) is what guarantees the optimum is unique and findable, and it is exactly what the Blahut–Arimoto algorithm later in this chapter will exploit.
]

=== The shape of the curve

Even before computing $R(D)$ for any specific source, its silhouette is fixed by pure logic, and knowing the silhouette is half of understanding it.

#fig([The rate–distortion curve. Rate falls as you allow more distortion; it is convex (bows toward the origin) and hits zero at $D_max$, the distortion of sending nothing. Every real codec is a point on or above this curve.],
cetz.canvas({
  import cetz.draw: *
  // axes
  line((0,0),(6.2,0), mark: (end: ">"))
  line((0,0),(0,4.2), mark: (end: ">"))
  content((6.4,-0.1))[$D$]
  content((-0.35,4.2))[$R$]
  // the convex decreasing R(D) curve, sampled points (catmull through)
  let pts = ((0.25,3.8),(0.6,2.6),(1.1,1.75),(1.8,1.1),(2.8,0.55),(4.0,0.18),(5.0,0.0))
  catmull(..pts, stroke: 2pt + rgb("#0b5394"))
  content((2.2,2.6))[#text(fill: rgb("#0b5394"))[$R(D)$]]
  // D_max marker
  line((5.0,0),(5.0,-0.18))
  content((5.0,-0.45))[$D_max$]
  content((-0.45,3.8))[$R(0)$]
  // region labels
  content((4.0,2.6))[#text(size:8pt, fill: rgb("#9a2617"))[impossible]]
  content((4.0,2.25))[#text(size:8pt, fill: rgb("#9a2617"))[(below the curve)]]
  content((1.2,0.45))[#text(size:8pt, fill: rgb("#0b6e4f"))[achievable (on/above)]]
}))

Four facts, each one provable from the definition and each one intuitive:

- *It is decreasing.* Allow more distortion (larger $D$) and the constraint loosens, so the $min$ can only get smaller or stay equal. More slack, fewer bits. Always.
- *It hits zero.* There is a distortion $D_max$ at which $R = 0$ — you send _no_ bits at all and just output the single best fixed guess for every symbol. For squared error, that best fixed guess is the mean of the source, and $D_max$ is the source's variance. Beyond $D_max$, extra tolerated distortion is wasted: zero bits is already as cheap as it gets.
- *At $D = 0$ it returns the lossless floor.* For a discrete source, demanding zero distortion forces $hat(X) = X$, and then $I(X; hat(X)) = H(X)$ — exactly the entropy of Chapter 18. Rate–distortion contains lossless coding as its $D = 0$ corner. (For _continuous_ sources, $R(0) = infinity$: perfection costs infinitely many bits, because a real number carries infinite precision. This is why lossy compression is not a nicety for images and audio — it is a necessity.)
- *It is convex.* The curve bows toward the origin. Convexity has a concrete payoff: it means _time-sharing_ between two operating points never beats the curve. If you can hit $(D_1, R_1)$ and $(D_2, R_2)$, then by using the first scheme on a fraction of your data and the second on the rest, you can hit any point on the straight line between them — and convexity guarantees the true $R(D)$ lies on or below that line, so the curve is the genuine frontier.

The third fact — that the lossless floor $H(X)$ is the $D = 0$ corner — deserves a one-line proof, because it is the hinge that joins this chapter to Chapter 19.

#proof[
_(The $D = 0$ corner equals the entropy, for a discrete source under a distortion that is zero exactly when $x = hat(x)$.)_ At $D = 0$ the only test channels with zero average distortion are those that never make a mistake, i.e. $p(hat(x)|x) = 0$ whenever $hat(x) != x$ — so $hat(X) = X$ with probability $1$. For such a channel $H(hat(X)|X) = 0$ and $H(X|hat(X)) = 0$, hence
$ R(0) = min I(X; hat(X)) = I(X; X) = H(X) - H(X|X) = H(X) - 0 = H(X). $
The lossy floor at zero distortion is exactly the lossless floor of Chapter 19. $qed$
]

#checkpoint[A source has entropy $H(X) = 3$ bits and variance $sigma^2 = 10$ (under squared-error distortion). Without any formula beyond the four facts above, what are $R(0)$ and $D_max$?][$R(0) = H(X) = 3$ bits (zero distortion means lossless, whose floor is the entropy). And $D_max = sigma^2 = 10$: outputting the constant mean for every symbol incurs average squared error equal to the variance, and that is the cheapest possible — zero bits — so $R(10) = 0$.]

== Why the curve cannot be beaten: the source coding theorem with a fidelity criterion

A definition is just a definition until a theorem promises it means something operational. The rate–distortion function earns its name through Shannon's 1959 theorem, which comes — like every great limit in this book — in two halves that meet exactly.

#theorem("Rate–distortion theorem (Shannon, 1959)")[
Let a memoryless source $X$ have rate–distortion function $R(D)$. Then:
_(Achievability.)_ For any rate $R > R(D)$ and any $epsilon > 0$, there exists, for all long enough block lengths $n$, a code mapping length-$n$ source blocks to $2^(n R)$ reconstruction blocks with average distortion at most $D + epsilon$.
_(Converse.)_ Conversely, _no_ code of rate $R < R(D)$ can achieve average distortion $<= D$. $R(D)$ is the exact _infimum_ of achievable rates at distortion $D$ — the greatest lower bound, the number you can approach as closely as you like from above but never beat.
]

Two halves, one meaning: $R(D)$ is not "a good lower bound we found" — it is the _exact_ boundary between the possible and the impossible. Below it, no scheme can keep its fidelity promise, no matter how clever. Above it, schemes exist. Let us prove each half at the level of honesty this book demands: the converse fully, the achievability in its essential idea.

=== The converse: nobody gets below the curve

The converse is the half that matters most to a working engineer, because it is the one that says "stop trying — it cannot be done." Its proof is a short, beautiful chain of inequalities, every link of which we already built in Chapters 18–20.

#proof[
Suppose some code takes a block of $n$ source symbols $X^n = (X_1, ..., X_n)$ and produces reconstructions $hat(X)^n$ using at most $n R$ bits, with average distortion $1/n sum_(i=1)^n EE[d(X_i, hat(X)_i)] <= D$. We show $R >= R(D)$.

The number of bits the code emits is at least the information the reconstruction carries about the source, so
$ n R >= H(hat(X)^n) >= I(X^n; hat(X)^n). $
The first inequality is just the source coding theorem of Chapter 19: you cannot describe $hat(X)^n$ in fewer than $H(hat(X)^n)$ bits, and a fixed-rate code spends $n R$. The second is because $I(X^n; hat(X)^n) = H(hat(X)^n) - H(hat(X)^n | X^n) <= H(hat(X)^n)$, since conditional entropy is non-negative.

Now we peel the block apart, one symbol at a time. Because the source is memoryless ($X_1, ..., X_n$ independent), the whole block leaks _at least_ as much information as the sum of its symbols leaking individually:
$ I(X^n; hat(X)^n) >= sum_(i=1)^n I(X_i; hat(X)_i). $
Here is the one-line reason. Write $I(X^n; hat(X)^n) = H(X^n) - H(X^n | hat(X)^n)$. Since the $X_i$ are independent, $H(X^n) = sum_i H(X_i)$ exactly (the surprise of independent things adds — Chapter 18). And "conditioning only reduces entropy" (Chapter 20) means that knowing the _whole_ reconstruction tells you at least as much about $X_i$ as knowing nothing, so $H(X^n | hat(X)^n) = sum_i H(X_i | hat(X)^n, X_(<i)) <= sum_i H(X_i | hat(X)_i)$. Subtracting the smaller second sum from the equal first sum gives the inequality. The block's leak is bounded below by its symbols' leaks because correlation in the _reconstruction_ can only help a per-symbol decoder, never hurt it.

For each symbol, the test channel it induces has _some_ average distortion $D_i = EE[d(X_i, hat(X)_i)]$, and by the very _definition_ of $R(D)$ as a minimum over all test channels meeting a distortion budget, that symbol's mutual information cannot be smaller than $R(D_i)$:
$ I(X_i; hat(X)_i) >= R(D_i). $
Chaining everything:
$ n R >= sum_(i=1)^n I(X_i; hat(X)_i) >= sum_(i=1)^n R(D_i) = n dot (1/n sum_i R(D_i)). $
Finally, $R(D)$ is _convex_ (we will earn this fact in the next section, but it is true). By Jensen's inequality for convex functions (Chapter 11, flipped from the concave case), the average of the $R(D_i)$ is at least $R$ of the average distortion:
$ 1/n sum_i R(D_i) >= R(1/n sum_i D_i) >= R(D), $
where the last step uses that $R$ is decreasing and the average distortion $1/n sum_i D_i <= D$. Putting it together, $R >= R(D)$. No code of rate below $R(D)$ can meet distortion $D$. $qed$
]

That chain — _bits $>=$ mutual information $>=$ sum of per-symbol mutual informations $>=$ sum of $R(D_i)$ $>=$ $R(D)$_ — is the whole converse. Notice it used nothing about _how_ the code works. It is a law about information itself, which is why it binds every codec ever built and every codec anyone ever will build.

=== Achievability: why the floor is actually reachable

The converse says you cannot go below $R(D)$. Achievability says you can get arbitrarily close — and its proof is one of the boldest ideas Shannon ever had: build the codebook _at random_ and prove the average random codebook works.

#proof[
_(Sketch — the random-coding argument.)_ Fix the optimal test channel $p^*(hat(x)|x)$ that achieves $R(D)$, and let $p^*(hat(x))$ be the reconstruction distribution it induces. Generate a codebook of $2^(n R)$ reconstruction blocks $hat(X)^n$ by drawing every symbol of every codeword independently from $p^*(hat(x))$ — pure random noise, shaped only by the optimal output distribution.

To encode a source block $x^n$, search the codebook for any codeword $hat(x)^n$ that is _jointly typical_ with $x^n$ — informally, a codeword that "looks like" a plausible output of the optimal test channel fed with $x^n$. (Chapter 19's typical set was about _single_ sequences whose per-symbol surprisal matches the entropy; joint typicality is the same idea applied to _pairs_ $(x^n, hat(x)^n)$, asking that the pair occur together about as often as the optimal channel says it should.) The _Asymptotic Equipartition Property_ from Chapter 19 (the law of large numbers for information) guarantees two things at once. First, any jointly typical pair has per-symbol distortion close to the target $D$, so _if_ we find a match, the distortion promise is kept. Second — the heart of it — the probability that a _single_ random codeword is jointly typical with $x^n$ is about $2^(-n I(X; hat(X)))$. With $2^(n R)$ independent codewords to try, the expected number of matches is about $2^(n R) dot 2^(-n I) = 2^(n(R - I))$. As long as $R > I(X;hat(X)) = R(D)$, this is exponentially large, so the probability of finding _no_ match vanishes as $n -> infinity$.

Therefore the average distortion of the random codebook approaches $D$, and since the _average_ over random codebooks is good, _at least one specific codebook_ is at least as good. That codebook is the existence proof. $qed$
]

#aside[
The random-coding argument is gloriously non-constructive: it proves a near-optimal codebook _exists_ without telling you a single entry of it. Shannon used the identical trick for channel capacity in 1948. For sixty years, "we know it exists but cannot build it" defined the gap between information theory and engineering — a gap that vector quantization (Chapter 39), then trained neural codecs (Chapter 57), spent decades narrowing. The theory says where the finish line is; the rest of the book is the race to reach it.
]

#keyidea[
The rate–distortion theorem is the lossy twin of Chapter 19's source coding theorem. There, $H(X)$ was the exact floor for _zero_ distortion. Here, $R(D)$ is the exact floor for _at most $D$_ distortion. Same logic (converse by an information inequality, achievability by random typical codes), one extra knob: the distortion budget $D$. Lossless coding is just the corner $D = 0$ of a vastly larger landscape.
]

== The Gaussian source: the most important curve in the world

Abstract definitions are fine, but engineers want a formula they can put a ruler against. There is exactly one source for which $R(D)$ has a clean closed form, and by a stroke of luck it is also the single most useful model in all of signal processing: the _Gaussian_ source. After a good transform decorrelates a signal (Chapters 37–38), the leftover coefficients look astonishingly like independent Gaussian noise, so the Gaussian $R(D)$ is the yardstick against which every real codec is measured.

#gomaths("The Gaussian (normal) distribution and differential entropy")[
The _Gaussian_ (or _normal_) distribution is the famous bell curve. A Gaussian random variable with mean $0$ and variance $sigma^2$ takes the value $x$ with probability _density_
$ p(x) = 1/(sqrt(2 pi sigma^2)) thin e^(-x^2 \/ (2 sigma^2)). $
The variance $sigma^2$ (Chapter 10) is its spread: small $sigma^2$ is a tall thin spike, large $sigma^2$ a wide flat hill. It is the bell you get whenever many small independent effects add up (the Central Limit Theorem), which is why it models so much real-world noise.

For a _continuous_ source we cannot use ordinary entropy (a real number carries infinite precision, so $H$ would be infinite). Instead Chapter 18's entropy generalizes to _differential entropy_, $h(X) = -integral p(x) log_2 p(x) dif x$ — the same formula with a sum replaced by an integral (Chapter 11). The one fact we need is a famous result: among _all_ distributions with a given variance $sigma^2$, the Gaussian has the _largest_ differential entropy, namely
$ h(X) = 1/2 log_2 (2 pi e thin sigma^2) thin "bits." $
The Gaussian is the "most random," hardest-to-compress source of its variance — the worst case. That is precisely why it is the right yardstick: beat the Gaussian and you beat everything tamer.
]

For a Gaussian source of variance $sigma^2$ under squared-error distortion, the rate–distortion function is exactly

$ R(D) = cases(
  1/2 log_2 (sigma^2 / D) & "for " 0 <= D <= sigma^2,
  0 & "for " D > sigma^2.
) $

This little formula is worth memorizing; let us both derive it and feel it.

#proof[
_(Why $R(D) = 1/2 log_2(sigma^2\/D)$.)_ We prove the converse direction (the matching achievability uses the random-coding argument above). Take any test channel with $EE[(X - hat(X))^2] <= D$. Write the error $Z = X - hat(X)$. Then
$ I(X; hat(X)) = h(X) - h(X | hat(X)) = h(X) - h(X - hat(X) | hat(X)) >= h(X) - h(Z). $
The middle step is because subtracting the known $hat(X)$ does not change conditional entropy; the inequality is because conditioning only reduces entropy ($h(Z|hat(X)) <= h(Z)$, Chapter 20). Now $h(X) = 1/2 log_2(2 pi e thin sigma^2)$ from the box. And $Z$ has variance at most $D$ (its mean-square is the distortion), so by the maximum-entropy property $h(Z) <= 1/2 log_2(2 pi e thin D)$. Substituting,
$ I(X; hat(X)) >= 1/2 log_2(2 pi e thin sigma^2) - 1/2 log_2(2 pi e thin D) = 1/2 log_2 (sigma^2 / D). $
The minimum over all valid test channels is therefore at least $1/2 log_2(sigma^2\/D)$, and a Gaussian test channel achieves it with equality. $qed$
]

Now feel it. Three readings of the same formula:

- *At $D = sigma^2$:* $R = 1/2 log_2 1 = 0$ bits. If you tolerate distortion equal to the full variance, send nothing and output the mean — exactly $D_max$ from before.
- *Halving the distortion costs half a bit... no — costs a fixed amount.* Replace $D$ by $D\/2$: the rate rises by $1/2 log_2 2 = 1/2$ bit. Every _halving_ of distortion costs a flat half-bit per sample, forever. There is no point of diminishing returns and no bargain — the exchange rate is constant. This is the engine behind every "one more quality level costs about the same again" experience you have ever had with a codec.
- *The "6 dB per bit" rule.* Engineers measure fidelity in decibels of signal-to-noise ratio, $"SNR" = 10 log_10(sigma^2\/D)$. Spending one extra _bit_ per sample means $R$ rises by $1$, i.e. $1/2 log_2(sigma^2\/D)$ rises by $1$, i.e. $sigma^2\/D$ quadruples. Quadrupling the SNR ratio is $10 log_10 4 approx 6.02$ dB. So: *each bit per sample buys about 6 dB of quality.* This back-of-envelope rule is wired into the reflexes of every audio and video engineer alive.

#mathrecall[
A _decibel_ (dB) is just a unit for ratios, built from the common logarithm $log_10$ of Chapter 7. For a _power_ ratio like signal-to-noise, the rule is $"value in dB" = 10 log_10("ratio")$. Each $times 10$ in the ratio is $+10$ dB; a $times 2$ is $10 log_10 2 approx 3$ dB; a $times 4$ is $approx 6$ dB. Decibels turn the multiplications of fidelity into the additions our ears and eyes actually perceive — which is exactly why engineers quote SNR this way.
]

#fig([The Gaussian $R(D) = 1/2 log_2(sigma^2\/D)$ for $sigma^2 = 1$. Rate climbs without bound as distortion $-> 0$ (perfection is infinitely expensive) and reaches zero at $D = sigma^2$.],
cetz.canvas({
  import cetz.draw: *
  let sx = 5.2   // x scale: D in [0,1] -> [0,sx]
  let sy = 1.1   // y scale per bit
  line((0,0),(sx+0.6,0), mark: (end: ">"))
  line((0,0),(0,3.6), mark: (end: ">"))
  content((sx+0.85,-0.05))[$D$]
  content((-0.35,3.6))[$R$]
  // curve R = 0.5*log2(1/D) for D in [0.06,1]
  let f(d) = 0.5*calc.log(1.0/d, base:2)
  let pts = ()
  let d = 0.06
  while d <= 1.0001 {
    pts.push((d*sx, calc.max(f(d),0.0)*sy))
    d = d + 0.02
  }
  line(..pts, stroke: 2pt + rgb("#0b5394"))
  content((sx,-0.32))[$sigma^2$]
  content((2.6,2.4))[#text(fill: rgb("#0b5394"))[$R(D)=1/2 log_2 sigma^2/D$]]
}))

== Many coefficients at once: reverse water-filling

Real signals are not one Gaussian; after a transform they are _many_ independent Gaussians of _different_ variances — a few big, loud coefficients and a long tail of small, quiet ones. Given a total distortion budget to spread across all of them, how should you allocate it? Pour all your fidelity into the loud ones? Share equally? The optimal answer has a name so vivid it sticks forever: _reverse water-filling_.

Suppose we have $n$ independent Gaussian coefficients with variances $sigma_1^2, ..., sigma_n^2$, and we want the cheapest total rate for a total distortion budget $D = sum_i D_i$. Each coefficient on its own costs $1/2 log_2(sigma_i^2 \/ D_i)$ bits for its share $D_i$. Minimizing the total rate subject to the budget (a Lagrange-multiplier calculation, Chapter 11) yields a strikingly simple rule.

#theorem("Reverse water-filling (parallel Gaussian source)")[
For independent Gaussians of variances $sigma_i^2$, there is a single _water level_ $theta > 0$ such that the optimal per-coefficient distortion is
$ D_i = min(theta, sigma_i^2), $
and the total rate is $R = sum_i 1/2 log_2(sigma_i^2 \/ D_i) = sum_(i : sigma_i^2 > theta) 1/2 log_2(sigma_i^2 \/ theta)$. The level $theta$ is chosen so the distortions sum to the budget: $sum_i min(theta, sigma_i^2) = D$.
]

Here is the picture that names it. Stand each coefficient's variance $sigma_i^2$ as a vertical bar. Now flood the whole landscape with water up to a common level $theta$:

#fig([Reverse water-filling. Variances are bars; water floods to a common level $theta$. A drowned coefficient ($sigma_i^2 < theta$, here bar 4) is spent entirely on distortion and gets _zero bits_. For the others, distortion is the water depth $theta$ and bits are paid only for the part of the bar _above_ the waterline.],
cetz.canvas({
  import cetz.draw: *
  let bars = (2.8, 1.9, 2.4, 0.7, 1.5)
  let theta = 1.1
  let w = 0.9
  let gap = 0.35
  // water level line across
  let total = bars.len()*(w+gap)
  // draw bars
  for (i, h) in bars.enumerate() {
    let x0 = i*(w+gap)
    // full variance bar (outline)
    rect((x0,0),(x0+w,h), stroke: 0.8pt + rgb("#783f04"))
    // water portion (distortion = min(theta,h))
    let wl = calc.min(theta, h)
    rect((x0,0),(x0+w,wl), fill: rgb("#0b5394").lighten(55%), stroke: none)
    // labels
    content((x0+w/2,-0.28))[#text(size:8pt)[$sigma_#(i+1)^2$]]
  }
  // water level line
  let span = total - gap
  line((-0.15,theta),(span + 0.15,theta), stroke: (paint: rgb("#0b5394"), dash: "dashed"))
  content((span + 0.6,theta))[$theta$]
  content((1.3, 2.95))[#text(size:8pt, fill: rgb("#783f04"))[bits paid above $theta$]]
}))

The rule reads off the picture:

- *A loud coefficient* ($sigma_i^2 > theta$, a bar sticking out of the water) gets distortion exactly $theta$ — flooded up to the line — and pays $1/2 log_2(sigma_i^2\/theta)$ bits for the part above water. Loud coefficients get the bits.
- *A quiet coefficient* ($sigma_i^2 <= theta$, a bar fully underwater) gets distortion equal to its _entire_ variance and pays _zero bits_. It is abandoned: you spend none of your budget describing it and just output its mean (zero). This is exactly why high-frequency JPEG coefficients quantize to zero and vanish — they are the drowned bars.

Why "reverse"? In the classical _water-filling_ for channel capacity (the dual problem), you pour _power_ into the strongest channels and starve the weak ones. Here you pour _distortion_ down to a common floor and starve the weak coefficients of _bits_. Same picture, opposite resource. Shannon's duality, made literally visible.

#tryit[
Take three coefficients with variances $sigma^2 = (4, 1, 0.25)$ and a water level $theta = 1$. Then $D = (min(1,4), min(1,1), min(1,0.25)) = (1, 1, 0.25)$, a total distortion budget of $2.25$. The rates are $1/2 log_2(4\/1) = 1$ bit, $1/2 log_2(1\/1) = 0$ bits, and $1/2 log_2(0.25\/0.25) = 0$ bits — total $1$ bit per sample, all spent on the single loud coefficient. The two quiet ones are free riders, reconstructed as zero. That, in three numbers, is why energy compaction (Chapter 38) is worth so much: concentrate the variance into a few coefficients and water-filling spends bits on almost nothing.
]

== Computing R(D) for any source: the Blahut–Arimoto algorithm

The Gaussian formula is a gift, but most real sources are not Gaussian and have no closed form. For a general discrete source with a general distortion measure, $R(D)$ is the answer to a constrained minimization over all test channels — and in 1972 two researchers, working independently, found a beautifully simple iterative algorithm that solves it. Suguru Arimoto attacked the dual problem of channel capacity; Richard Blahut handled the rate–distortion side. Their methods turned out to be two faces of one idea, and the field has called it the _Blahut–Arimoto algorithm_ ever since.

#algo(
  name: "Blahut–Arimoto algorithm",
  year: "1972",
  authors: "Suguru Arimoto (capacity); Richard E. Blahut (rate–distortion)",
  aim: "Numerically compute the rate–distortion function R(D) of a discrete source (or, dually, channel capacity) by alternating minimization.",
  complexity: "O(|X| · |X̂|) per iteration; linear, monotone convergence guaranteed by convexity.",
  strengths: "Simple, provably convergent, needs only the source p(x) and the distortion matrix; no calculus at runtime.",
  weaknesses: "Solves one Lagrange point per run (you sweep the multiplier s to trace the curve); slow tail convergence; for continuous sources you must discretize.",
  superseded: "Still standard; modern variants accelerate it (squeezing, 2008) or replace it with neural estimators for high dimensions (2023–2025).",
)[
The algorithm exploits a reformulation of $R(D)$ as a _double_ minimization over both the test channel _and_ an auxiliary output distribution. Holding one fixed and optimizing the other has a closed-form solution each way; alternating between them slides downhill to the unique (convexity!) optimum.
]

The key is to stop fighting the constraint $EE[d] <= D$ directly and instead introduce a price. Pick a number $s >= 0$ — think of it as the _exchange rate_ between bits and distortion — and minimize the combined cost $I(X; hat(X)) + s dot EE[d(X, hat(X))]$ with no constraint at all. This is a _Lagrangian_, and the slope of the $R(D)$ curve at the resulting point is exactly $-s$. Sweep $s$ from $0$ to large and you trace the whole curve, point by point. (We will meet this same Lagrangian trick again, doing real encoder work, in Chapter 41 on rate–distortion _optimization_.)

#gomaths("Lagrange multipliers in one breath")[
You want to minimize a cost $f$ subject to a constraint $g <= D$. The trick: build a new, _unconstrained_ function $f + s dot g$ for some price $s >= 0$, and minimize _that_. If you pick the right $s$, the minimizer of $f + s g$ also satisfies the constraint, and it is optimal. Intuitively, $s$ is how many units of $f$ you would trade for one unit of relaxing the constraint — the "price" of the constraint. As you raise $s$, the optimizer cares more about keeping $g$ small. Sweeping $s$ over its whole range sweeps the constraint level $D$ over its whole range, tracing the trade-off curve. That is the entire idea behind both Blahut–Arimoto here and Lagrangian RDO in Chapter 41.
]

For a fixed price $s$, the algorithm alternates two update steps until they stop changing. Let $q(hat(x))$ be the current guess at the output (reconstruction) distribution. Then:

$ "(channel step)" quad p(hat(x)|x) = (q(hat(x)) thin e^(-s thin d(x, hat(x)))) / (sum_(hat(x)') q(hat(x)') thin e^(-s thin d(x, hat(x)'))), $
$ "(output step)" quad q(hat(x)) = sum_x p(x) thin p(hat(x)|x). $

Read the channel step: a reconstruction symbol $hat(x)$ is favored for source $x$ when it is _popular_ (large $q(hat(x))$) _and cheap_ (small distortion $d(x, hat(x))$, so $e^(-s d)$ is near $1$). High distortion is punished exponentially. The output step just recomputes how often each reconstruction is used. Each pass provably lowers the Lagrangian, and convexity guarantees there is only one valley to fall into.

#project("Extending model.py — a from-scratch rate–distortion calculator")[
This is an _analysis tool_, not a new codec step (Ch 21 adds no numbered `tinyzip` milestone — the lossy coders themselves arrive in Volume III). It extends the `model.py` module that already holds `entropy()` and `cross_entropy()` (Chapters 18–20): until now `tinyzip` has been a strictly _lossless_ toolkit, and we give it the ability to _know the lossy floor_ — compute $R(D)$ for any small source, so later we can measure how close our lossy schemes get. Here is Blahut–Arimoto in plain Python 3.14.

```python
import math

def blahut_arimoto(
    p: list[float],            # source distribution p(x), len = |X|
    dist: list[list[float]],   # distortion matrix dist[x][xhat]
    s: float,                  # Lagrange price (>= 0); bigger s -> lower D
    iters: int = 200,
) -> tuple[float, float]:
    """Return (rate_bits, distortion) at Lagrange multiplier s."""
    nx = len(p)
    nh = len(dist[0])
    q = [1.0 / nh] * nh                       # start: uniform output guess
    w = [[math.exp(-s * dist[x][h]) for h in range(nh)] for x in range(nx)]

    for _ in range(iters):
        # channel step: p(xhat | x), normalised per source symbol
        cond = []
        for x in range(nx):
            num = [q[h] * w[x][h] for h in range(nh)]
            z = sum(num)
            cond.append([n / z for n in num])
        # output step: q(xhat) = sum_x p(x) p(xhat|x)
        q = [sum(p[x] * cond[x][h] for x in range(nx)) for h in range(nh)]

    # read off rate and distortion at convergence
    rate = 0.0
    distortion = 0.0
    for x in range(nx):
        for h in range(nh):
            pij = p[x] * cond[x][h]
            if pij > 0 and q[h] > 0:
                rate += pij * math.log2(cond[x][h] / q[h])
            distortion += pij * dist[x][h]
    return rate, distortion
```

The `list[float]` and `list[list[float]]` are Python 3.14 _type hints_ (Chapter 16): they document that `p` is a list of floats and `dist` a list of lists of floats. They are checked by tools, not enforced at runtime, but they make the contract obvious.
```python
# A binary source, p(0)=p(1)=1/2, Hamming distortion.
p = [0.5, 0.5]
D_matrix = [[0.0, 1.0], [1.0, 0.0]]     # 0 on the diagonal, 1 off it
for s in (0.0, 1.0, 2.0, 4.0, 8.0):
    R, D = blahut_arimoto(p, D_matrix, s)
    print(f"s={s:>4}:  R={R:.4f} bits   D={D:.4f}")
```
Run it and the printed `(R, D)` pairs land exactly on the curve we are about to compute by hand — proof that the code and the theory agree.
]

#gopython("Nested lists as matrices, and exp/log2")[
A _matrix_ in plain Python is just a list whose entries are themselves lists — a list of rows. `dist[x][h]` reads row `x`, column `h`. We built one with a _nested comprehension_, `[[expr for h in ...] for x in ...]`: the inner brackets build a row, the outer brackets collect the rows. From the `math` module, `math.exp(t)` is $e^t$ (the natural exponential, Chapter 7) and `math.log2(t)` is $log_2 t$ (the base-2 logarithm we measure bits in). Tiny check:

```python
import math
M = [[0.0, 1.0], [1.0, 0.0]]   # a 2x2 distortion matrix
print(M[0][1])                 # 1.0  -> cost of reconstructing 0 as 1
print(round(math.exp(-2 * M[0][1]), 4))  # 0.1353 = e^(-2)
```
]

=== Worked by hand: the binary source

Let us close the loop and compute one $R(D)$ entirely on paper, then watch the algorithm reproduce it. Take the fairest source there is — a fair coin, $p(0) = p(1) = 1/2$ — under Hamming distortion, where $d = 0$ if you guess right and $1$ if you guess wrong. Average distortion is then exactly the probability of guessing wrong. What is $R(D)$?

The answer is one of the cleanest formulas in the subject:

$ R(D) = cases(
  1 - H_2(D) & "for " 0 <= D <= 1/2,
  0 & "for " D > 1/2,
) $

where $H_2(D) = -D log_2 D - (1-D) log_2(1-D)$ is the _binary entropy function_ from Chapter 18 — the entropy of a biased coin that lands heads with probability $D$.

#gomaths("Reading the binary R(D) formula")[
Start at the corners. At $D = 0$ (insist on zero errors), $H_2(0) = 0$, so $R(0) = 1 - 0 = 1$ bit — you must send the full bit, because a fair coin has exactly $1$ bit of entropy and lossless coding cannot do better (Chapter 19). At $D = 1/2$ (tolerate being wrong half the time), $H_2(1/2) = 1$, so $R(1/2) = 1 - 1 = 0$ bits — guess a constant, be right half the time for free. In between, $R$ slides smoothly from $1$ down to $0$, and the shape is convex.

The interpretation of $1 - H_2(D)$ is gorgeous. Think of the lossy code as deliberately passing your fair coin through a "noisy channel" that flips it with probability $D$. The flips _are_ your distortion. The information that survives the flipping — the bits the reconstruction still tells you about the source — is exactly $1 - H_2(D)$, the capacity of a binary symmetric channel with crossover $D$ (Chapter 20). Rate–distortion and channel capacity meet in a single formula.
]

Now the numbers. Compute $R(D)$ at a few distortions, by hand, and alongside them the value the Blahut–Arimoto code prints:

#scoreboard(caption: "Fair binary source, Hamming distortion — theory vs. Blahut–Arimoto",
  [$D = 0.0$], [$R = 1.000$], [—], [insist on perfection: full 1 bit (lossless floor)],
  [$D = 0.10$], [$R = 0.531$], [$s approx 3.17$], [$1 - H_2(0.1) = 1 - 0.469$],
  [$D = 0.25$], [$R = 0.189$], [$s approx 1.58$], [$1 - H_2(0.25) = 1 - 0.811$],
  [$D = 0.50$], [$R = 0.000$], [$s = 0$], [tolerate 50% error: send nothing],
)

Every "theory" entry comes from plugging $D$ into $1 - H_2(D)$; every algorithm run, started from a uniform guess and swept over the price $s$, converges to the same numbers to four decimals. The code and the closed form are the same object seen two ways — and now `tinyzip` owns a tool that will tell us, in Volume III, exactly how many bits any lossy scheme is leaving on the table.

#checkpoint[Using $R(D) = 1 - H_2(D)$, roughly how many bits per symbol does the fair binary source need if you are willing to be wrong $1$ time in $5$ ($D = 0.2$)? ($H_2(0.2) approx 0.722$.)][$R(0.2) = 1 - 0.722 = 0.278$ bits per symbol — you can compress a fair coin to barely over a quarter-bit each if a 20% error rate is acceptable. That is the power of allowing distortion: a source that was incompressible losslessly becomes very compressible the instant you relax perfection.]

== The third axis: rate, distortion, and now perception

For sixty years the story stopped here: two axes, rate and distortion, and a convex curve trading one for the other. Then a quiet crisis arrived with the deep-learning codecs of the late 2010s. Engineers built neural compressors that achieved _lower distortion_ (lower MSE) than anything before — and the images looked _worse_. Blurry, plasticky, lifeless. Meanwhile other networks, with _higher_ MSE, produced images that looked stunningly real. Squared error and the human eye were openly disagreeing, and the two-axis theory had no room to even describe the conflict.

In 2019 Yochai Blau and Tomer Michaeli named the missing axis and proved it was real. The insight: "distortion" (how far the reconstruction is from _this particular original_, measured pixel by pixel) and "perceptual quality" (how much the reconstruction _looks like a real image at all_, regardless of which original it came from) are _different things_, and you cannot maximize both at once.

#definition("Perceptual quality (distributional)")[
_Distortion_ compares each reconstruction $hat(X)$ to its own source $X$, e.g. $EE[(X - hat(X))^2]$. _Perceptual quality_ instead compares the _whole distribution_ of reconstructions to the distribution of real images: it is high when $p_(hat(X))$, the statistics of all outputs, is close to $p_X$, the statistics of natural images — measured by a divergence like the KL divergence of Chapter 20 or a Wasserstein distance. A blurry image can be _close on average_ to its original (low distortion) yet obviously fake (no real photo is that smooth) — low perceptual quality. The two are genuinely separate knobs.
]

#theorem("Rate–distortion–perception trade-off (Blau–Michaeli, 2019)")[
Constraining the perceptual quality to be high (forcing the output distribution to match the source distribution) _raises_ the rate–distortion curve: at any fixed rate, demanding realism forces you to accept higher distortion, and at any fixed distortion, realism costs more rate. There is a genuine three-way trade-off $R(D, P)$ among rate, distortion $D$, and perception $P$; you cannot have all three at their best.
]

The proof in their paper is for a Bernoulli (biased-coin) source, computed in closed form, and the conclusion is counterintuitive enough to be worth saying plainly: *pushing distortion all the way to zero can make an image look worse, and deliberately allowing a small, carefully-shaped distortion can make it look dramatically better.* The reason is that a low-bitrate encoder _must_ throw detail away; it can either leave the result smooth and faithful-on-average (low distortion, fake-looking) or _hallucinate_ plausible new detail — grass, skin pores, fabric texture — that was not in the original but is statistically right for the scene (higher distortion, photo-real). The "wrong" detail is wrong pixel by pixel yet right perceptually.

#keyidea[
"Close to the original" and "looks real" are not the same goal, and at low bitrates they fight. Classical codecs (JPEG, HEVC) optimize distortion and go soft and blocky when starved of bits. Generative codecs (Volume IV) optimize _perception_ and stay sharp by inventing realistic detail — trading per-pixel accuracy for believability. The rate–distortion–perception triangle is the theory that makes this trade-off precise, and it is the bridge from Shannon's 1959 world to the diffusion-based codecs of the 2020s.
]

#history[
Shannon practically predicted this in 1959. His whole framing was "a source _within a prescribed fidelity criterion_" — fidelity, not pixel-error — and he warned that choosing the right distortion measure was the heart of the problem. For decades engineers used squared error anyway, because it was tractable and they had no better handle on perception. The Blau–Michaeli result of 2019, and the wave of work it launched — coding theorems for $R(D, P)$ (Theis & Wagner 2021; Chen and collaborators 2022–2024), the role of common randomness, Wasserstein-space formulations (2024–2025), and training-free diffusion traversals of the trade-off (2026) — are, in a real sense, the field finally taking Shannon's own warning seriously. The "right distortion measure" he gestured at in 1959 turned out to need a second axis he did not have the tools to name.
]

#misconception[A "generative" codec that invents realistic detail is cheating — it is making up data that was never there.][
It is making up data — but so, in a milder way, does _every_ lossy codec. JPEG "invents" the smooth ramp it uses to replace the texture it discarded; that ramp was never in the original either. The honest question is not "did it invent?" but "did it invent _statistically plausible_ detail or misleading detail?" For entertainment and communication, plausible invented texture that looks right is often exactly what you want. For evidence, medicine, or science, _any_ invention can be dangerous — which is why those domains keep using low-distortion (and often lossless) codecs. The rate–distortion–perception theory does not bless hallucination; it tells you precisely what you are trading for it.
]

#takeaways((
  [Lossy compression is meaningless without a _distortion measure_ $d(x, hat(x))$; the average distortion $EE[d]$ is the one honest number, and the choice of $d$ decides which bits are precious.],
  [The _rate–distortion function_ $R(D) = min_(p(hat(x)|x): EE[d] <= D) I(X; hat(X))$ is the exact floor on bits per symbol at distortion $D$ — a $min$ of mutual information, the mirror of channel capacity's $max$.],
  [$R(D)$ is convex, decreasing, equals the entropy $H(X)$ at $D = 0$ (discrete) or $infinity$ (continuous), and hits $0$ at $D_max = sigma^2$. Shannon's theorem makes it operational: a hard converse below, random-coding achievability above.],
  [For a Gaussian source, $R(D) = 1/2 log_2(sigma^2\/D)$: each halving of distortion costs a flat half-bit, and each bit buys $approx 6$ dB of SNR.],
  [For many independent Gaussians, _reverse water-filling_ pours distortion to a common level $theta$: loud coefficients get the bits, drowned ones get _zero_ — the theory behind energy compaction and zeroed JPEG coefficients.],
  [The _Blahut–Arimoto algorithm_ (1972) computes $R(D)$ for any discrete source by alternating two closed-form steps, sweeping a Lagrange price $s$ to trace the curve.],
  [The _rate–distortion–perception_ trade-off (Blau–Michaeli, 2019) adds a third axis: "looks real" and "is close" conflict at low bitrates, formalizing why generative codecs hallucinate plausible detail.],
))

== Exercises

#exercise("21.1", 1)[
A grayscale source has pixel variance $sigma^2 = 256$ under squared-error distortion. (a) What is $D_max$, the distortion at which $R = 0$? (b) What single value would the rate-$0$ encoder output for every pixel, and why? (c) If the source entropy is $H(X) = 7.2$ bits, what is $R(0)$?
]
#solution("21.1")[
(a) $D_max = sigma^2 = 256$: outputting the mean for every pixel gives average squared error equal to the variance, and zero bits is already the cheapest, so $R = 0$ there. (b) The _mean_ of the source — under squared error the constant that minimizes $EE[(X - c)^2]$ is $c = EE[X]$, the mean. (c) Zero distortion forces $hat(X) = X$, so $R(0) = H(X) = 7.2$ bits per pixel (the lossless floor of Chapter 19).
]

#exercise("21.2", 1)[
Explain in your own words why the rate–distortion curve $R(D)$ must be _decreasing_, using only the definition $R(D) = min_(EE[d] <= D) I(X; hat(X))$. Why can it never go _up_ as $D$ increases?
]
#solution("21.2")[
A larger $D$ enlarges the set of test channels you are allowed to choose from (every channel meeting budget $D_1$ also meets a larger budget $D_2 > D_1$). Minimizing over a _bigger_ set can only give an equal or smaller minimum — you never lose options by relaxing a constraint. So $R(D_2) <= R(D_1)$: the curve can stay flat or fall, never rise. More tolerated distortion can only make the cheapest acceptable scheme cheaper.
]

#exercise("21.3", 2)[
A Gaussian source has variance $sigma^2 = 100$. (a) What rate $R$ is needed for distortion $D = 25$? (b) For distortion $D = 6.25$? (c) By how many bits did the rate increase from (a) to (b), and how does that match the "halving distortion costs a fixed amount" rule? (d) Convert each rate to an approximate SNR in dB.
]
#solution("21.3")[
(a) $R = 1/2 log_2(100\/25) = 1/2 log_2 4 = 1$ bit. (b) $R = 1/2 log_2(100\/6.25) = 1/2 log_2 16 = 2$ bits. (c) The increase is $1$ bit. Distortion fell from $25$ to $6.25$, a factor of $4$ — that is _two_ halvings, and each halving costs $1/2$ bit, so $2 times 1/2 = 1$ bit. It matches exactly. (d) SNR $= 10 log_10(sigma^2\/D)$: (a) $10 log_10 4 approx 6.0$ dB, (b) $10 log_10 16 approx 12.0$ dB — and indeed one extra bit added $approx 6$ dB.
]

#exercise("21.4", 2)[
You have three independent Gaussian coefficients with variances $sigma^2 = (9, 4, 1)$ and you set the reverse water-filling level to $theta = 4$. (a) Find the per-coefficient distortions $D_i$. (b) Find the per-coefficient rates. (c) What is the total rate and total distortion? (d) Which coefficient(s) are "drowned" and get zero bits?
]
#solution("21.4")[
(a) $D_i = min(theta, sigma_i^2) = (min(4,9), min(4,4), min(4,1)) = (4, 4, 1)$. (b) $R_i = 1/2 log_2(sigma_i^2\/D_i) = (1/2 log_2(9\/4), 1/2 log_2(4\/4), 1/2 log_2(1\/1)) = (1/2 log_2 2.25, 0, 0) approx (0.585, 0, 0)$ bits. (c) Total rate $approx 0.585$ bits; total distortion $4 + 4 + 1 = 9$. (d) The second and third coefficients are drowned ($sigma_i^2 <= theta$): they get $0$ bits and are reconstructed as their mean. Only the loud first coefficient is coded.
]

#exercise("21.5", 2)[
For the fair binary source under Hamming distortion, $R(D) = 1 - H_2(D)$ for $0 <= D <= 1/2$, where $H_2(D) = -D log_2 D - (1-D) log_2(1-D)$. (a) Compute $R(0.1)$ given $H_2(0.1) approx 0.469$. (b) Compute $R(0.3)$ given $H_2(0.3) approx 0.881$. (c) A friend claims they compressed a fair coin to $0.4$ bits per flip with only $5\%$ errors. Using $H_2(0.05) approx 0.286$, show this is impossible.
]
#solution("21.5")[
(a) $R(0.1) = 1 - 0.469 = 0.531$ bits. (b) $R(0.3) = 1 - 0.881 = 0.119$ bits. (c) At $D = 0.05$ the floor is $R(0.05) = 1 - H_2(0.05) = 1 - 0.286 = 0.714$ bits per flip. The converse of the rate–distortion theorem forbids any rate below $0.714$ bits at $5\%$ error, so $0.4$ bits is impossible — the friend either has more than $5\%$ errors or is mistaken. No scheme beats $R(D)$.
]

#exercise("21.6", 3)[
Prove that $R(D)$ is convex in $D$. _(Hint: take two operating points $(D_1, R(D_1))$ and $(D_2, R(D_2))$ with their optimal test channels $p_1, p_2$. Build a new test channel by mixing: with probability $lambda$ use $p_1$, with probability $1 - lambda$ use $p_2$. Use the facts from Chapter 20 that mutual information is convex in the channel for a fixed input, and that average distortion is linear in the channel.)_
]
#solution("21.6")[
Let $D_lambda = lambda D_1 + (1-lambda) D_2$ for $lambda in [0,1]$. Take the optimal test channels $p_1$ achieving $R(D_1)$ and $p_2$ achieving $R(D_2)$, and form the mixed channel $p_lambda = lambda p_1 + (1-lambda) p_2$. Average distortion is _linear_ in the channel: the distortion of $p_lambda$ is $lambda D_1 + (1-lambda) D_2 = D_lambda$, so $p_lambda$ is a valid test channel for budget $D_lambda$. Mutual information $I(X; hat(X))$ is _convex_ in the channel $p(hat(x)|x)$ for fixed source $p(x)$ (Chapter 20), so $I_(p_lambda) <= lambda I_(p_1) + (1-lambda) I_(p_2) = lambda R(D_1) + (1-lambda) R(D_2)$. Since $R(D_lambda)$ is the _minimum_ over all valid channels and $p_lambda$ is one such channel, $R(D_lambda) <= I_(p_lambda) <= lambda R(D_1) + (1-lambda) R(D_2)$. That is exactly the convexity inequality. $qed$
]

#exercise("21.7", 3)[
Using the `blahut_arimoto` function from the project box, compute $R(D)$ for a _biased_ binary source with $p(0) = 0.8$, $p(1) = 0.2$ under Hamming distortion. (a) Write the few lines that sweep $s$ over $(0, 1, 2, 4, 8)$ and print $(R, D)$. (b) What is $R(0)$ for this source, and how does it compare to the fair-coin value of $1$ bit? (c) Explain why a biased source needs _fewer_ bits than a fair one at every distortion level.
]
#solution("21.7")[
(a)
```python
p = [0.8, 0.2]
D_matrix = [[0.0, 1.0], [1.0, 0.0]]
for s in (0.0, 1.0, 2.0, 4.0, 8.0):
    R, D = blahut_arimoto(p, D_matrix, s)
    print(f"s={s:>4}:  R={R:.4f} bits   D={D:.4f}")
```
(b) $R(0) = H(X) = H_2(0.8) = -0.8 log_2 0.8 - 0.2 log_2 0.2 approx 0.722$ bits — less than the fair coin's $1$ bit, because a biased source is already less surprising (Chapter 18). (c) At every $D$, the biased source has lower entropy and is more predictable, so fewer bits are needed to pin it down to the same fidelity; its whole $R(D)$ curve sits below the fair coin's. Predictability is compressibility, lossy or lossless.
]

#exercise("21.8", 3)[
The rate–distortion–perception trade-off says forcing the output distribution to match the source distribution raises the rate–distortion curve. (a) In one or two sentences, explain why a codec optimizing _only_ squared error tends to produce blurry images at low bitrates. (b) Explain how a generative codec achieves sharp output at the same bitrate, and what it sacrifices. (c) Name one application where you would _refuse_ the generative trade-off and demand low distortion instead, and say why.
]
#solution("21.8")[
(a) At low bitrates the encoder must discard detail; to minimize _average_ squared error over all the possibilities consistent with the few bits sent, the safest bet is the _average_ of those possibilities — and averaging textures together blurs them. Minimizing MSE literally rewards hedging toward a smooth mean. (b) A generative codec instead samples one _plausible_ sharp reconstruction whose statistics match real images (high perceptual quality), inventing detail that is statistically right but not pixel-accurate; it sacrifices per-pixel fidelity (higher distortion) for realism. (c) Medical imaging, scientific/forensic evidence, or any setting where invented detail could mislead a diagnosis or a decision — there, hallucinated texture is a hazard, and low-distortion (or lossless) coding is required even at the cost of more bits.
]

== Further reading

- Claude E. Shannon, #link("https://ieeexplore.ieee.org/document/1057459")[_Coding Theorems for a Discrete Source with a Fidelity Criterion_], IRE National Convention Record, Part 4 (1959), 142–163 — the paper that founded rate–distortion theory and defined $R(D)$.
- Thomas M. Cover and Joy A. Thomas, _Elements of Information Theory_ (2nd ed., Wiley, 2006), Chapter 10 — the modern textbook treatment: the converse, achievability, the Gaussian source, reverse water-filling, and Blahut–Arimoto, all rigorous.
- Toby Berger, _Rate Distortion Theory: A Mathematical Basis for Data Compression_ (Prentice-Hall, 1971) — the classic monograph that systematized the whole subject.
- Richard E. Blahut, _Computation of Channel Capacity and Rate-Distortion Functions_, IEEE Transactions on Information Theory, 18 (1972), 460–473 — the rate–distortion half of the Blahut–Arimoto algorithm (Suguru Arimoto's companion capacity paper appeared in the same volume).
- Yochai Blau and Tomer Michaeli, #link("https://proceedings.mlr.press/v97/blau19a.html")[_Rethinking Lossy Compression: The Rate-Distortion-Perception Tradeoff_], ICML 2019 — the paper that added the third axis and reframed perceptual compression.
- Lucas Theis and Aaron B. Wagner, #link("https://arxiv.org/abs/2104.13662")[_A Coding Theorem for the Rate-Distortion-Perception Function_] (2021), and the follow-up Wasserstein-space and common-randomness analyses (2022–2025) — the operational theory behind generative codecs.

#bridge[
We now own the full Shannon landscape: the lossless floor $H$ (Chapter 19), the communication ceiling $C$ (Chapter 20), and the lossy frontier $R(D)$ — together with its modern third axis. We have proved where the prizes are. But this whole volume has been _theory_: limits, bounds, what is possible. We have not yet built a single real lossy compressor, because the schemes that actually approach $R(D)$ — transforms that decorrelate, quantizers that round, and the perceptual models that choose _which_ distortion to accept — belong to the engineering volumes ahead. Chapter 22 first finishes the foundations with _Kolmogorov complexity_: the ultimate, uncomputable compressor that asks not "how surprising is this source?" but "what is the shortest program that prints this exact string?" — the deepest limit of all, and the one no algorithm can ever reach.
]
