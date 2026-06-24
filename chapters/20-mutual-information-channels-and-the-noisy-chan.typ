#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Mutual Information, Channels, and the Noisy-Channel Theorem

#epigraph[The fundamental problem of communication is that of reproducing at one point either exactly or approximately a message selected at another point. Frequently the messages have _meaning_... These semantic aspects of communication are irrelevant to the engineering problem.][Claude E. Shannon, _A Mathematical Theory of Communication_, 1948]

Here is a puzzle that seems to have an obvious wrong answer. You want to send a photo to a friend across a wireless link that randomly corrupts one bit in ten. You have two tools. The first is a _compressor_, which works hard to throw away every wasted, predictable bit so the photo is as small as possible. The second is an _error-corrector_, which works hard to add back carefully chosen extra bits so that, even after the channel mangles a tenth of them, your friend can reconstruct the original perfectly. One tool _removes_ redundancy; the other _adds_ it. They look like sworn enemies, each undoing the other's work.

So which do you reach for first, and does the order matter? Should the two tools be designed together, by one team that understands both the photo and the wireless link? Or can a compressor that has never heard of radios, and an error-corrector that has never seen a photo, be bolted together in series and still be optimal? The answer is one of the most beautiful results in all of engineering. It turns out that one number - a single quantity, measured in bits - governs _both_ tools at once. Strip a photo down until every bit counts, or fortify a message until it survives a storm of noise: you are, astonishingly, measuring the same thing from two sides. That number is _mutual information_, and this chapter is the story of how it ties the two halves of Shannon's 1948 masterpiece into one knot.

#recap[
In Chapter 18 we built Shannon's _entropy_ $H(X) = -sum_x p(x) log_2 p(x)$ (the average surprise of a source, in bits) together with _joint entropy_ $H(X,Y)$, _conditional entropy_ $H(Y|X)$, and the _chain rule_ $H(X,Y) = H(X) + H(Y|X)$. In Chapter 19 we turned entropy into a hard limit: the _Source Coding Theorem_ proved $H(X)$ is the exact floor for lossless compression. No prefix code beats it (Kraft--McMillan), and arithmetic coding reaches it. That whole story was about _removing_ redundancy from a clean, error-free pipe. This chapter finishes Shannon's paper by asking the opposite question: what if the pipe is _noisy_? It discovers that the two questions share one measuring stick. We lean on logarithms (Chapter 7), probability and conditional probability (Chapter 9), expectation (Chapter 10), $sum$-notation and a pinch of concavity (Chapter 11), and Python dictionaries (Chapter 16).
]

#objectives((
  [Define _relative entropy_ (KL divergence) $D_"KL"(p||q)$, explain why it is exactly the number of bits a wrong model wastes, and prove it is never negative.],
  [Define _mutual information_ $I(X;Y)$ three equivalent ways and read all three meanings: redundancy, channel throughput, and distance from independence.],
  [State and use the _data-processing inequality_: why "computing on data cannot create information."],
  [Model a noisy medium as a _channel_ $p(y|x)$ and compute the _capacity_ of the binary symmetric and binary erasure channels by hand.],
  [State the _Noisy-Channel Coding Theorem_ and explain its sphere-packing proof, the exact mirror of the Source Coding Theorem.],
  [State the _source--channel separation theorem_, explain why it makes the whole digital world modular, and name precisely where it breaks (short blocks, networks, semantic goals).],
  [Compute KL divergence, mutual information, and capacity in Python, and add an entropy/divergence "model meter" to `tinyzip`.],
))

== Relative entropy: the exact cost of a wrong model

Chapter 19 left a small debt unpaid. When you compress data with a code built for the _wrong_ probabilities (believing symbol $x$ has probability $q(x)$ when its true probability is $p(x)$) you do not merely "do a little worse." You overpay by a precise, computable number of bits, and that number has a name: the _Kullback--Leibler divergence_, or _relative entropy_. I pay that debt now, because this one quantity is the seed from which mutual information, channel capacity, and half of modern machine learning all grow.

Recall the central fact from Chapter 19: the ideal codeword length for a symbol of true probability $p(x)$ is $-log_2 p(x)$ bits. But suppose you do not _know_ the truth $p$; you only have an estimate $q$, and you build your code as if $q$ were correct, spending $-log_2 q(x)$ bits on symbol $x$. How much does this mistake cost, _on average_, when symbols actually arrive according to the true $p$?

The average number of bits you actually spend is the _cross-entropy_ of $p$ relative to $q$:

$ H(p, q) = -sum_x p(x) log_2 q(x). $

Read it slowly. The symbols arrive with frequency $p(x)$ - that is the true world - but you pay $-log_2 q(x)$ bits for each, because that is the code you built from your wrong beliefs. The cross-entropy is what you _actually_ pay. The best you _could_ have paid, with the correct code, is the entropy $H(p) = -sum_x p(x) log_2 p(x)$ (Chapter 18). The difference between what you pay and what you could have paid is the pure waste:

$ D_"KL"(p || q) = H(p, q) - H(p) = sum_x p(x) log_2 (p(x))/(q(x)). $

#definition("Relative entropy / Kullback–Leibler divergence")[
For two probability distributions $p$ and $q$ over the same alphabet, the _relative entropy_ of $p$ with respect to $q$ is
$ D_"KL"(p || q) = sum_x p(x) log_2 (p(x))/(q(x)) quad "bits." $
It is the average number of _extra_ bits per symbol you pay by coding a source whose true distribution is $p$ using a code optimized for $q$. By convention $0 dot log_2 (0\/q) = 0$; and if $q(x) = 0$ while $p(x) > 0$, the divergence is $+infinity$: you assigned an infinitely long codeword to something that actually happens.
]

Two properties make this the workhorse of the whole field. First, it is _never negative_: $D_"KL"(p || q) >= 0$ always, with equality _if and only if_ $p$ and $q$ are identical. You can never come out ahead by using the wrong model; the best case is to use the right one and waste nothing. Second, it is _not symmetric_: in general $D_"KL"(p || q) != D_"KL"(q || p)$. The cost of believing $q$ when the truth is $p$ differs from the cost of believing $p$ when the truth is $q$. For that reason it is called a _divergence_, not a _distance_ (a distance would have to be symmetric). The asymmetry is not a defect; it reflects the real fact that the penalty for a wrong model depends on which way the error runs.

#gomaths("Concave functions and Jensen's inequality")[
The non-negativity of $D_"KL"$ rests on one geometric fact about the logarithm, worth seeing from scratch.

A function is _concave_ if it "bulges upward," like the top of a hill: the curve always lies _above_ any straight line (chord) drawn between two of its points. The logarithm is concave - sketch $log_2 x$ and you will see it bend over, rising ever more slowly. Indeed $log_2 4 = 2$ and $log_2 16 = 4$, but their midpoint input $10$ gives $log_2 10 approx 3.32$, which is _more_ than the average $(2+4)/2 = 3$ of the two outputs. Averaging the inputs first beats averaging the outputs.

That observation, stated for any weighted average, is _Jensen's inequality_. For a concave function $g$ and any weights $w_i >= 0$ summing to $1$,
$ g(sum_i w_i z_i) >= sum_i w_i g(z_i). $
In words: _the function of the average is at least the average of the function_ (for concave $g$; the inequality flips for convex, valley-shaped functions). Writing $EE[Z] = sum_i w_i z_i$ for the weighted average (the _expectation_ of Chapter 10), this is the compact $g(EE[Z]) >= EE[g(Z)]$. The upward bulge of the log rewards you for not spreading the inputs out.
]

#theorem("Gibbs' inequality (non-negativity of KL divergence)")[
For any two distributions $p$ and $q$ on the same alphabet, $D_"KL"(p || q) >= 0$, with equality if and only if $p(x) = q(x)$ for every $x$.
]

#proof[
Look at the _negative_ of the divergence and apply Jensen. Using $log_2(a\/b) = -log_2(b\/a)$,
$ -D_"KL"(p || q) = sum_x p(x) log_2 (q(x))/(p(x)). $
The right side is a weighted average (weights $p(x)$, summing to $1$) of the quantity $log_2(q(x)\/p(x))$. Since $log_2$ is concave, Jensen gives
$ sum_x p(x) log_2 (q(x))/(p(x)) <= log_2 (sum_x p(x) dot (q(x))/(p(x))) = log_2 (sum_x q(x)) = log_2 1 = 0. $
Inside the final logarithm the $p(x)$ cancels and the $q(x)$ sum to $1$. So $-D_"KL"(p||q) <= 0$, i.e. $D_"KL"(p||q) >= 0$. Equality in Jensen holds only when the averaged quantity $q(x)\/p(x)$ is the same constant for every $x$; since both distributions sum to $1$, that constant must be $1$, forcing $p = q$.
]

This little proof is the engine behind nearly every lower bound in the book, including the converse half of the Source Coding Theorem of Chapter 19. (Any code's average length is $overline(L) = H(p) + D_"KL"(p || q)$, where $q(x) = 2^(-ell(x))$ is the code's implied model; since $D_"KL" >= 0$, we get $overline(L) >= H(p)$, so no code beats entropy.)

=== Worked example: the lazy engineer

It pays to translate the divergence into something you can feel. A source emits two symbols, $A$ and $B$, with true probabilities $p(A) = 0.9$, $p(B) = 0.1$. A lazy engineer assumes a fair coin, $q(A) = q(B) = 0.5$, and builds a one-bit code: one bit per symbol. The true entropy is $H(p) = H_2(0.9) approx 0.469$ bits (writing $H_2$ for the binary entropy function of Chapter 18), so the ideal code spends under half a bit per symbol - yet our engineer spends a full bit. The waste is exactly the divergence:

$ D_"KL"(p || q) = 0.9 log_2 (0.9)/(0.5) + 0.1 log_2 (0.1)/(0.5) approx 0.9(0.848) + 0.1(-2.322) approx 0.531 quad "bits/symbol." $

And sure enough $H(p) + D_"KL"(p || q) approx 0.469 + 0.531 = 1.000$ bit/symbol, exactly the cross-entropy, exactly what the one-bit code costs. The divergence is the gap, in bits, between the engineer's ignorance and the truth. Every improvement in a real compressor's model - `gzip` to PPM to a neural network - is a campaign to drag the model's $q$ toward the source's $p$, shrinking $D_"KL"(p || q)$ toward zero.

#keyidea[
_Wasted bits equal modelling error._ Coding a source $p$ with a code built for $q$ costs $H(p) + D_"KL"(p || q)$ bits per symbol. The first term is unavoidable: the entropy floor. The second, $D_"KL"(p || q) >= 0$, is the avoidable penalty for being wrong, exactly zero only when your model is the truth. This single identity is _why_ better prediction means better compression, the thread running from Huffman all the way to large language models in Volume IV.
]

#misconception[that KL divergence is a kind of distance, so $D_"KL"(p||q)$ and $D_"KL"(q||p)$ should be roughly equal.][They can differ wildly. Take $p = (0.5, 0.5)$ and $q = (0.99, 0.01)$. Then $D_"KL"(p||q) = 0.5 log_2 (0.5\/0.99) + 0.5 log_2 (0.5\/0.01) approx 0.5(-0.99) + 0.5(5.64) approx 2.32$ bits, but $D_"KL"(q||p) = 0.99 log_2(0.99\/0.5) + 0.01 log_2(0.01\/0.5) approx 0.99(0.99) + 0.01(-5.64) approx 0.92$ bits. Believing the lopsided $q$ when the truth is the fair $p$ is far costlier than the reverse, because $q$ assigns a near-impossible probability $0.01$ to an event the truth produces half the time, and that surprise then costs a huge $-log_2 0.01 approx 6.6$ bits every time it (often) happens.]

#checkpoint[A model assigns probabilities $q = (1/4, 1/4, 1/4, 1/4)$ to four symbols, but the true distribution is $p = (1/2, 1/4, 1/8, 1/8)$. How many bits per symbol does the model waste?][The uniform model spends $log_2 4 = 2$ bits on every symbol, so its cross-entropy is $2$ bits. The true entropy is $H(p) = 1/2(1) + 1/4(2) + 1/8(3) + 1/8(3) = 1.75$ bits. The waste is $D_"KL"(p||q) = 2 - 1.75 = 0.25$ bits per symbol.]


== Mutual information: the bits one thing tells you about another

We are one short step from the quantity that runs this entire chapter. Mutual information answers a question that sounds almost philosophical but turns out to be perfectly concrete: _when I learn the value of one random variable, how many bits do I learn about another?_

Start from the chain rule of Chapter 18. The joint entropy of two variables splits as $H(X, Y) = H(X) + H(Y | X)$: the total surprise in the pair is the surprise in $X$ plus the _leftover_ surprise in $Y$ once $X$ is known. Chapter 18 also showed that conditioning never increases entropy: $H(Y | X) <= H(Y)$. So learning $X$ shrinks your uncertainty about $Y$ from $H(Y)$ down to $H(Y | X)$. The amount of the shrinkage is the information $X$ carries about $Y$:

$ I(X; Y) = H(Y) - H(Y | X). $

#definition("Mutual information")[
The _mutual information_ between random variables $X$ and $Y$ is the reduction in uncertainty about one from learning the other:
$ I(X; Y) = H(Y) - H(Y | X) = H(X) - H(X | Y) = H(X) + H(Y) - H(X, Y). $
It is measured in bits, is always non-negative, and is _symmetric_: $I(X; Y) = I(Y; X)$. It is zero if and only if $X$ and $Y$ are independent.
]

The symmetry is genuinely surprising the first time you meet it, so let us prove the three forms really are equal.

#theorem("Equivalent forms of mutual information")[
For any two random variables, $I(X;Y) = H(X) + H(Y) - H(X,Y) = H(Y) - H(Y|X) = H(X) - H(X|Y)$. In particular $I(X;Y) = I(Y;X)$: mutual information is symmetric.
]

#proof[
Start from the chain rule of Chapter 18, written both ways for the same pair: $H(X,Y) = H(X) + H(Y|X)$ and $H(X,Y) = H(Y) + H(X|Y)$ (the joint surprise is one variable's surprise plus the other's leftover, and it cannot matter which we name first). Rearranging the first gives $H(Y|X) = H(X,Y) - H(X)$, so
$ H(Y) - H(Y|X) = H(Y) - H(X,Y) + H(X) = H(X) + H(Y) - H(X,Y). $
Rearranging the second gives $H(X|Y) = H(X,Y) - H(Y)$, so
$ H(X) - H(X|Y) = H(X) - H(X,Y) + H(Y) = H(X) + H(Y) - H(X,Y), $
the _same_ middle expression. Hence all three forms equal $H(X) + H(Y) - H(X,Y)$, which is visibly unchanged when $X$ and $Y$ swap places. So $I(X;Y) = I(Y;X)$.
]

The middle expression $H(X) + H(Y) - H(X,Y)$ is the cleanest: it is the two circles' areas minus their union, i.e. their overlap in the Venn picture. The number of bits that knowing the weather tells you about the barometer reading is _exactly_ the number of bits that knowing the barometer reading tells you about the weather. Information is mutual. It lives in the _relationship_ between the two variables, not in either one alone. That is why the colon notation $I(X; Y)$, rather than an asymmetric arrow, is standard.

There is a second, illuminating way to write mutual information that connects it straight back to the previous section. Two variables are independent exactly when their joint distribution factorizes, $p(x, y) = p(x) p(y)$. A natural way to measure how _far_ they are from independent is to ask how badly the true joint $p(x, y)$ differs from the pretend-they're-independent product $p(x) p(y)$. We now have the perfect tool for the gap between two distributions: the KL divergence.

$ I(X; Y) = D_"KL"(p(x, y) || p(x) p(y)) = sum_x sum_y p(x, y) log_2 (p(x, y))/(p(x) p(y)). $

Mutual information is the relative entropy between the real joint distribution and the fictional independent one. This instantly explains both of its key properties: it is $>= 0$ because every KL divergence is (Gibbs' inequality above), and it is $0$ exactly when $p(x, y) = p(x) p(y)$, exactly when $X$ and $Y$ are independent and knowing one tells you nothing about the other. The more strongly two variables are coupled, the more their joint deviates from the independent product, and the larger the mutual information.

#fig([The two-circle (Venn) picture of entropy. The whole shape is $H(X,Y)$; the overlap is $I(X;Y)$; the crescents are the conditional entropies $H(X|Y)$ and $H(Y|X)$.], cetz.canvas({
  import cetz.draw: *
  circle((0,0), radius: 1.6, fill: rgb("#0b539420"), stroke: rgb("#0b5394"))
  circle((1.8,0), radius: 1.6, fill: rgb("#78340420"), stroke: rgb("#783f04"))
  content((-0.9, 0))[$H(X|Y)$]
  content((2.7, 0))[$H(Y|X)$]
  content((0.9, 0))[$I(X;Y)$]
  content((-0.6, 1.85))[$H(X)$]
  content((2.4, 1.85))[$H(Y)$]
  content((0.9, -2.15), box(width: 4.5cm, inset: 2pt, align(center, text(size: 8pt)[$H(X,Y)$ = everything inside either circle])))
}))

#gomaths("Reading the Venn picture of entropy")[
Information theorists draw entropies as a two-circle Venn diagram, and it is the fastest way to keep the relationships straight. Draw a circle for $H(X)$ (all the uncertainty in $X$) overlapping a circle for $H(Y)$.

- The _whole picture_ (everything inside either circle) is the joint entropy $H(X, Y)$.
- The _overlap_ (the lens where the circles cross) is the mutual information $I(X; Y)$: the shared uncertainty.
- The _left crescent_ (in $X$ but not the overlap) is $H(X | Y)$: what is left in $X$ after $Y$ is known.
- The _right crescent_ is $H(Y | X)$.

Every identity is just a statement about areas. "$H(X) = I(X;Y) + H(X|Y)$" says the left circle equals its overlap plus its crescent. "$H(X,Y) = H(X) + H(Y) - I(X;Y)$" says the union equals the sum of the two circles minus their double-counted overlap. (The picture is a genuine guide but not perfect: for three or more variables the analogous triple overlap can be _negative_, which has no honest area meaning. For two variables it is exact and trustworthy.)
]

=== Worked example: a bit down a noisy wire

Let us put a number on it. Take a binary symmetric source: $X$ is a fair bit ($p(0) = p(1) = 1/2$), and $Y$ is a copy of $X$ flipped with probability $f = 0.1$ - think of $X$ sent down a slightly noisy wire and $Y$ received. Then $H(X) = 1$ bit. Given $X$, the variable $Y$ is just "flip with probability $0.1$," so $H(Y | X) = H_2(0.1) approx 0.469$ bits. The mutual information is

$ I(X; Y) = H(Y) - H(Y | X) = 1 - 0.469 = 0.531 quad "bits." $

Although you send one full bit, the receiver learns only about $0.531$ bits about your intended bit. The noise ate the other $0.469$. That number, $0.531$ bits per use, becomes the _capacity_ of this channel in the next section: the hard ceiling on how fast you can communicate reliably across it.

It is worth grinding through the _other_ formula, $I(X;Y) = sum_(x,y) p(x,y) log_2 [p(x,y) \/ (p(x) p(y))]$, on this same example, to check the symmetry claim and to watch the divergence interpretation pay off. With a uniform input and $f = 0.1$, the four joint probabilities are $p(0,0) = p(1,1) = 1/2 dot 0.9 = 0.45$ (sent correctly) and $p(0,1) = p(1,0) = 1/2 dot 0.1 = 0.05$ (flipped). The marginals are all $1/2$, so each independent product $p(x)p(y) = 1\/4 = 0.25$. Then

$ I(X;Y) = 2 dot 0.45 log_2 (0.45)/(0.25) + 2 dot 0.05 log_2 (0.05)/(0.25) approx 0.9(0.848) + 0.1(-2.322) approx 0.531 quad "bits," $

the very same $0.531$. Notice this is _identical_ arithmetic to the lazy-engineer KL example, because the joint distribution here happens to coincide with that $p$-versus-$q$ comparison. The two routes to mutual information, "drop in conditional entropy" and "divergence from independence," agree to the last decimal, exactly as the theory promised. The symmetry $I(X;Y) = I(Y;X)$ is visible too: the formula is unchanged when you swap $x$ and $y$.

#keyidea[
Mutual information $I(X; Y)$ is _one number with three readings_. (1) _Compression:_ the redundancy _between_ two variables - bits you can save on $Y$ by exploiting your knowledge of $X$. (2) _Channels:_ the bits about the input that survive to the output, i.e. the throughput. (3) _Statistics:_ how far the pair is from independent, $D_"KL"(p(x,y) || p(x)p(y))$. The rest of this chapter shows that these three readings are not analogies: they are the _same theorem_ seen from three sides.
]

#gopython("dict, .get(), and summing over a joint table")[
A _dictionary_ (`dict`, Chapter 16) maps keys to values. We store a joint distribution as a dict whose keys are pairs `(x, y)` and whose values are probabilities. The method `d.get(k, 0.0)` returns `d[k]` if the key exists, else the fallback `0.0` - handy for marginals we build up by addition. `from math import log2` imports the base-2 logarithm. A `for (x, y), pxy in joint.items():` loop unpacks each key-pair and its value at once.

```python
from math import log2

joint = {(0,0): 0.45, (1,1): 0.45, (0,1): 0.05, (1,0): 0.05}

px: dict[int, float] = {}   # marginal of X
py: dict[int, float] = {}   # marginal of Y
for (x, y), pxy in joint.items():
    px[x] = px.get(x, 0.0) + pxy
    py[y] = py.get(y, 0.0) + pxy

print(px, py)   # {0: 0.5, 1: 0.5} {0: 0.5, 1: 0.5}
```

Each marginal is the row/column sum of the joint table. With the marginals in hand, mutual information is one more loop - coming up in the project box.
]

=== The data-processing inequality: you can't compute information into existence

One consequence of mutual information is so useful, and so often forgotten, that it deserves its own statement. Suppose information flows in a chain: $X$ influences $Y$, and $Y$ alone influences $Z$, with $Z$ depending on $X$ only _through_ $Y$. Mathematicians say $X -> Y -> Z$ form a _Markov chain_: once you know $Y$, the value of $Z$ carries no further trace of $X$. Post-processing $Y$ can only lose information about $X$.

#gomaths("Markov chains: depending on the past only through the present")[
A _Markov chain_, written $X -> Y -> Z$, is a sequence of random variables in which each one depends on the whole past _only through the one immediately before it_. Concretely, once you know $Y$, the value of $X$ tells you nothing further about $Z$:
$ p(z | x, y) = p(z | y). $
The intuition is a relay race: $X$ hands its baton to $Y$, and $Y$ alone hands it to $Z$. $Z$ never sees $X$ directly. A practical example: $X$ = today's weather, $Y$ = a photo of the sky you take, $Z$ = a friend's guess from the photo. The friend's guess $Z$ depends on the real weather $X$ only _through_ the photo $Y$; hand them the photo and the actual sky outside becomes irrelevant. This "memoryless" structure (named for the mathematician Andrey Markov) is exactly the shape of a processing pipeline, where data flows forward stage by stage, and it is all we need for the inequality below.
]

#gomaths("Conditional mutual information and the chain rule")[
Just as we measured the leftover surprise in $Y$ _after_ learning $X$ with the conditional entropy $H(Y|X)$ (Chapter 18), we can measure the information $Z$ carries about $X$ _after_ a third variable $Y$ is already known. This is the _conditional mutual information_:
$ I(X; Z | Y) = H(X | Y) - H(X | Y, Z). $
Read it as: of the uncertainty about $X$ that survives knowing $Y$, how much does additionally learning $Z$ remove? Like ordinary mutual information it is an average of KL divergences, so it too is _never negative_: $I(X; Z | Y) >= 0$. And it obeys a _chain rule_, the exact twin of the entropy chain rule. The information a _pair_ $(Y, Z)$ carries about $X$ splits into "what $Y$ tells you" plus "what $Z$ adds once $Y$ is known":
$ I(X; (Y, Z)) = I(X; Y) + I(X; Z | Y). $
Because we may name the two pieces in either order, it also equals $I(X; Z) + I(X; Y | Z)$. These two facts, non-negativity and the chain rule, are all the proof below needs.
]

#theorem("Data-processing inequality")[
If $X -> Y -> Z$ is a Markov chain (so $Z$ depends on $X$ only through $Y$), then $I(X; Z) <= I(X; Y)$. No function or random transformation applied to $Y$ can increase the information $Y$ already carries about $X$.
]

#proof[
Expand the mutual information between $X$ and the _pair_ $(Y, Z)$ two ways, using the chain rule for mutual information (the same additive bookkeeping as the entropy chain rule):
$ I(X; (Y,Z)) = I(X; Y) + I(X; Z | Y) = I(X; Z) + I(X; Y | Z). $
Here $I(X; Z | Y)$ is the information $Z$ adds about $X$ _once $Y$ is known_. But the Markov property says exactly that once $Y$ is known, $Z$ tells you nothing more about $X$: $I(X; Z | Y) = 0$. So the first expansion reads $I(X; (Y,Z)) = I(X; Y)$. The second expansion has $I(X; Y | Z) >= 0$, because every (conditional) mutual information is non-negative - it too is an average of KL divergences. Therefore
$ I(X; Y) = I(X; Z) + I(X; Y | Z) >= I(X; Z), $
which is the claim.
]

In plain words: _post-processing cannot create information_. Once $Y$ has captured everything it is going to capture about $X$, no further computation on $Y$ - filtering, transforming, running it through a neural network - can recover more about $X$ than $Y$ already held. You can only lose information, or at best break even. This is the rigorous reason a corrupted file cannot be "enhanced" back to its original beyond what the corruption left intact, why a lossy thumbnail cannot be losslessly restored to the full image (a fact we lean on hard in Chapter 21's rate--distortion theory), and why the television trope of "zoom and enhance" conjuring detail that was never captured is, information-theoretically, a fantasy. It is also a quiet sanity check on every machine-learning pipeline: the features you extract can only throw information away relative to the raw input; the art is in throwing away only the part you do not need.


== Channels: modelling the noisy world

Compression assumes a clean pipe: whatever bits you write, the decoder reads back exactly. Reality is messier. Bits flip on a scratched disc, fade on a long wire, get corrupted by interference on a wireless link, or are misread off worn flash memory. To reason about communication in the presence of such corruption, Shannon modelled the medium itself as a probabilistic object: a _channel_.

#definition("Discrete memoryless channel")[
A _discrete memoryless channel_ (DMC) takes an input symbol $x$ from an input alphabet and emits an output symbol $y$ from an output alphabet, according to a fixed _transition probability_ $p(y | x)$ - the probability that $y$ comes out when $x$ goes in. _Memoryless_ means each use of the channel is independent of the others: the noise has no memory of past symbols. The channel is fully described by the table of numbers $p(y | x)$.
]

The simplest and most important example is the _binary symmetric channel_ (BSC). Its input and output are both single bits. With probability $1 - f$ the bit passes through untouched; with probability $f$ (the _crossover probability_) it is flipped. So $p(0 | 0) = p(1 | 1) = 1 - f$ and $p(1 | 0) = p(0 | 1) = f$. This is the canonical model of a wire that occasionally lies, and we use it as our running example because everything about it can be computed by hand.

A second standard model is the _binary erasure channel_ (BEC). Here a transmitted bit either arrives correctly or is _erased_, replaced by a known "I didn't receive this" symbol, often written `?`. Crucially, an erasure is honest: the receiver knows _which_ bits are missing, it just doesn't know their values. This models packet loss on the internet (a dropped packet is an erasure, not a flipped bit) and is, in a precise sense, easier to deal with than the BSC, because knowing _where_ the damage is removes half the problem.

#fig([Two channels as little probability machines. Left: the binary symmetric channel - each bit flips with probability $f$. Right: the binary erasure channel - each bit is erased to `?` with probability $e$, else passes through.], cetz.canvas({
  import cetz.draw: *
  // BSC
  content((0, 2.0))[$0$]; content((2, 2.0))[$0$]
  content((0, 0.4))[$1$]; content((2, 0.4))[$1$]
  line((0.25, 2.0), (1.75, 2.0), mark: (end: ">"))
  line((0.25, 0.4), (1.75, 0.4), mark: (end: ">"))
  line((0.25, 1.85), (1.75, 0.55), mark: (end: ">"), stroke: rgb("#9a2617"))
  line((0.25, 0.55), (1.75, 1.85), mark: (end: ">"), stroke: rgb("#9a2617"))
  content((1.0, 2.25))[$1-f$]
  content((1.0, 1.25))[$f$]
  content((1.0, -0.4))[BSC]
  // BEC
  content((5, 2.0))[$0$]; content((7, 2.4))[$0$]
  content((5, 0.4))[$1$]; content((7, 0.0))[$1$]
  content((7, 1.2))[$?$]
  line((5.25, 2.0), (6.75, 2.35), mark: (end: ">"))
  line((5.25, 0.4), (6.75, 0.05), mark: (end: ">"))
  line((5.25, 1.9), (6.75, 1.25), mark: (end: ">"), stroke: rgb("#783f04"))
  line((5.25, 0.5), (6.75, 1.15), mark: (end: ">"), stroke: rgb("#783f04"))
  content((6.2, 2.5))[$1-e$]
  content((6.2, 1.7))[$e$]
  content((6.0, -0.4))[BEC]
}))

#gomaths("Conditional-probability tables, read as a channel")[
A channel is just a small table of conditional probabilities, and reading it is a skill worth a moment. For a BSC with crossover $f = 0.1$:

#table(columns: 3, align: center,
  [], [output $0$], [output $1$],
  [input $0$], [$0.9$], [$0.1$],
  [input $1$], [$0.1$], [$0.9$],
)

Each _row_ is a probability distribution over outputs for a fixed input, so each row sums to $1$ (here $0.9 + 0.1 = 1$). The diagonal entries are "transmitted correctly"; the off-diagonal entries are errors. To _use_ the table you also need the _input_ distribution (how often you actually send $0$ versus $1$), and from those two you compute everything: the output distribution $p(y) = sum_x p(x) p(y|x)$, the joint $p(x, y) = p(x) p(y | x)$, and hence the mutual information $I(X; Y)$. The channel table is the _physics_; the input distribution is the _choice you get to make_; capacity is the best choice.
]

== Channel capacity: the most you can push through

We have a channel, described by its transition table $p(y | x)$. We have a measuring stick, $I(X; Y)$, that tells us how many bits about the input survive to the output. But $I(X; Y)$ depends on _two_ things: the channel (fixed, the physics) and the input distribution $p(x)$ (ours to choose - we decide how often to send each symbol). So we get to optimize. We feed the channel the input distribution that lets the most information through, and the resulting maximum is the channel's _capacity_.

#definition("Channel capacity")[
The _capacity_ of a discrete memoryless channel is the largest mutual information achievable over all choices of input distribution:
$ C = max_(p(x)) I(X; Y) quad "bits per channel use." $
It is a property of the channel alone - the maximization removes the dependence on the input - and it sets the speed limit for reliable communication, as the next section's theorem makes precise.
]

Let us compute the capacity of our two example channels, because the formulas are clean and instructive.

For the _binary symmetric channel_ with crossover $f$, symmetry makes the optimal input the uniform one ($p(0) = p(1) = 1/2$): there is no reason to favour either bit when the channel treats them identically. With a uniform input the output is also uniform, so $H(Y) = 1$ bit. And given the input, the output is "flip with probability $f$," so $H(Y | X) = H_2(f)$. Therefore

$ C_"BSC" = 1 - H_2(f) = 1 - [-f log_2 f - (1 - f) log_2 (1 - f)] quad "bits per use." $

Sanity-check the extremes. A perfect wire ($f = 0$) gives $H_2(0) = 0$, so $C = 1$ bit per use. A maximally noisy wire ($f = 0.5$) gives $H_2(0.5) = 1$, so $C = 0$: the output is a fair coin _no matter what you send_, input and output are independent, and not a single bit gets through. (A wire that flips with probability _greater_ than $0.5$ is not worse but better: relabel the outputs, flipping every bit, and you have a wire with crossover $1 - f < 0.5$. The channel that destroys all information is the one at exactly $f = 0.5$.) For our running $f = 0.1$ example, $C = 1 - H_2(0.1) approx 1 - 0.469 = 0.531$ bits per use, the very number we computed as the mutual information earlier, now revealed as the capacity.

For the _binary erasure channel_ with erasure probability $e$, the answer is even prettier: $C_"BEC" = 1 - e$. The intuition is exact. A fraction $e$ of your bits are erased, and since the receiver knows _which_, those bits are simply lost and the rest get through perfectly; on average a fraction $1 - e$ of bits survive intact, and that is the capacity. The erasure channel is "honest noise," and honesty is worth a lot: a BEC with $e = 0.1$ has capacity $0.9$, far above the BSC's $0.531$ at the same damage rate, precisely because knowing _where_ the errors are is most of the battle.

#tryit[
Convince yourself the BSC is harsher than the BEC by thinking about _why_. On the erasure channel you are told exactly which bits to distrust. On the symmetric channel a flipped bit looks identical to a correct one. You must figure out _both_ which bits are wrong _and_ what they should have been, using only redundancy you built into the message. Locating the errors is itself expensive in bits, and that extra cost is the gap between $1 - e$ and $1 - H_2(f)$. This is why systems that can arrange for erasures (internet packets with sequence numbers, so a lost packet announces itself) are designed to do so.
]

For completeness, here is the capacity of the symmetric channel proved properly, including the claim, used above, that the uniform input is optimal.

#theorem("Capacity of the binary symmetric channel")[
The binary symmetric channel with crossover probability $f$ has capacity $C_"BSC" = 1 - H_2(f)$ bits per channel use, achieved by the uniform input $p(0) = p(1) = 1/2$.
]

#proof[
For _any_ input distribution, write $I(X;Y) = H(Y) - H(Y|X)$. The second term is easy and input-independent: given the input bit, the output is "flip with probability $f$," so $H(Y | X = 0) = H(Y | X = 1) = H_2(f)$, and therefore $H(Y|X) = H_2(f)$ whatever the input distribution. So maximizing $I(X;Y)$ is the same as maximizing $H(Y)$ alone. Now $Y$ is a single bit, and the entropy of a bit is at most $1$, with equality exactly when $Y$ is uniform. Can we make $Y$ uniform? Feed in the uniform input $p(0)=p(1)=1/2$; then $p(Y=0) = 1/2(1-f) + 1/2 f = 1/2$, so $Y$ is indeed uniform and $H(Y) = 1$. Thus $max H(Y) = 1$ is attained, and
$ C_"BSC" = max_(p(x)) I(X;Y) = 1 - H_2(f). $
Since no input can push the bit $Y$ above entropy $1$, no input beats the uniform one, which proves it optimal.
]

#history[
The capacity formula $C = max_(p(x)) I(X; Y)$ and the proof that it is achievable are the climax of Part I of Shannon's 1948 paper, the same paper that gave us entropy and the Source Coding Theorem. Before Shannon, engineers believed that to make a noisy line more reliable you had to either slow down or shout louder (raise power), and that driving the error rate to zero meant driving the rate to zero. Shannon proved this folklore wrong: for _any_ rate below capacity, the error probability can be pushed arbitrarily close to zero _without_ slowing down, purely by clever coding over long blocks. The community took years to fully believe it and decades to build codes that approach it.
]


== The Noisy-Channel Coding Theorem

Now the payoff. We defined capacity as a number computed from the channel's probability table. Shannon's second theorem makes that number _operational_, exactly as the Source Coding Theorem made entropy operational: capacity is not merely _a_ quantity associated with the channel, it is _the_ sharp threshold separating "reliable communication is possible" from "reliable communication is impossible."

#theorem("Noisy-Channel Coding Theorem (Shannon, 1948)")[
Let a discrete memoryless channel have capacity $C$ bits per use. Then:
(i) _Achievability._ For every rate $R < C$ and every $epsilon > 0$, there is a block code of some length $n$ that transmits at rate $R$ bits per channel use with probability of decoding error below $epsilon$. Reliable communication is possible at every rate below capacity.
(ii) _Converse._ For every rate $R > C$, the probability of error is bounded away from zero and cannot be made small, no matter how the code is designed. Reliable communication above capacity is impossible.
]

The structure mirrors the Source Coding Theorem precisely, and the parallel is the deepest idea in the chapter. There, entropy $H$ was a _floor_ you could approach from above but never go below. Here, capacity $C$ is a _ceiling_ you can approach from below but never exceed. In both cases the bound is tight from both sides: provably impossible to beat, yet provably reachable in the limit of long blocks. And in both cases the long-block limit does the heavy lifting: just as the Source Coding Theorem needed long blocks of source symbols to squeeze out the last fractional bit, the Channel Coding Theorem needs long blocks of channel uses to average out the noise.

=== Why it is true: the random-coding argument

The proof of achievability is one of the most elegant arguments in applied mathematics, and the intuition is graspable without heavy machinery. It also explains a phrase you will hear constantly - "random coding" - that sounds paradoxical (how can _random_ codes be _good_?) until you see the trick.

Here is the idea. We want to send one of $M = 2^(n R)$ possible messages using $n$ channel uses. To each message we assign a _codeword_: a length-$n$ block of input symbols. Shannon's audacious move was to choose every codeword _completely at random_, by independent coin flips drawn from the capacity-achieving input distribution. He then asked not "is this particular random codebook good?" but "what is the _average_ error probability, averaged over all possible random codebooks?" If the average is small, then _at least one_ codebook must be at least as good as the average - so a good code provably exists, even though we never constructed it.

Why does it work? Think back to the _typical set_ of Chapter 19. When you send a codeword $x^n$ through the channel, the output $y^n$ is, with overwhelming probability, _jointly typical_ with the input you sent - it falls into a predictable "cloud" of likely outputs around that input. The decoder's job is to look at the received $y^n$ and decide which codeword's cloud it landed in. Errors happen only when $y^n$ accidentally also looks jointly typical with some _other_ codeword's cloud. Now count: the total number of typical output sequences is about $2^(n H(Y))$, and each input codeword's cloud of plausible outputs has size about $2^(n H(Y | X))$. So the number of _disjoint_ clouds you can pack into the output space without overlap is roughly

$ (2^(n H(Y)))/(2^(n H(Y | X))) = 2^(n (H(Y) - H(Y | X))) = 2^(n I(X; Y)). $

There it is. You can reliably distinguish about $2^(n I(X; Y))$ messages - and maximizing $I(X; Y)$ over the input gives $2^(n C)$. If you try to cram in more than $2^(n C)$ messages, their output clouds must overlap, and the decoder cannot tell them apart: errors become unavoidable. That is the converse. If you use fewer, the clouds can be kept (almost surely) disjoint, and as $n -> infinity$ the overlap probability vanishes: that is achievability. Capacity is, quite literally, _how many non-overlapping clouds fit in the output space, per channel use_.

#fig([Sphere-packing. Each codeword (dot) blossoms into a cloud of likely received sequences of size $approx 2^(n H(Y|X))$. The whole output space holds $approx 2^(n H(Y))$ typical sequences. The number of non-overlapping clouds (distinguishable messages) is the ratio $approx 2^(n I(X;Y))$.], cetz.canvas({
  import cetz.draw: *
  rect((0,0),(7,4), stroke: rgb("#0b5394"))
  content((3.5, 4.35), box(width: 6.5cm, inset: 2pt, align(center, text(size: 8pt)[output space $approx 2^(n H(Y))$ sequences])))
  let cs = ((1.2,1.0),(3.0,0.9),(5.2,1.1),(1.5,2.8),(3.7,2.9),(5.6,2.8),(2.4,1.9),(4.6,2.0))
  for c in cs {
    circle(c, radius: 0.62, fill: rgb("#0b539418"), stroke: rgb("#783f04"))
    circle(c, radius: 0.05, fill: rgb("#783f04"))
  }
  content((5.5, 0.45), box(width: 2.8cm, inset: 2pt, align(center, text(size: 8pt)[cloud $approx 2^(n H(Y|X))$])))
}))

#keyidea[
The Channel Coding Theorem is a _sphere-packing_ statement in disguise. Each codeword, sent through the channel, blossoms into a fuzzy cloud of likely received sequences of size $approx 2^(n H(Y|X))$. The output space holds $approx 2^(n H(Y))$ typical sequences. The number of clouds you can pack without overlap (hence the number of distinguishable messages) is the ratio $approx 2^(n I(X;Y))$, maximized to $2^(n C)$. Below capacity the clouds stay separate; above it they collide and errors are forced. This is the exact mirror of the Source Coding Theorem's "only $2^(n H)$ typical messages exist."
]

#pitfall[
Shannon's proof is _non-constructive_: it proves a good code _exists_ without telling you how to build one, and the "random codebook" it conjures is uselessly large to store and decode (a lookup table with $2^(n R)$ entries). Closing the gap between Shannon's existence proof and practical, efficiently-decodable codes that actually approach capacity took _half a century_: Hamming and Reed--Muller codes in the 1950s, convolutional and Reed--Solomon codes, then the breakthroughs of turbo codes (Berrou, 1993) and the rediscovery of Gallager's LDPC codes (1960; revived 1996), and finally Arıkan's polar codes (2008), the first with a clean proof of _provably_ achieving capacity, and now the code protecting the control channels of every 5G phone. We meet these in the error-correction chapter of a later volume. The theorem promised the destination in 1948; the road took fifty years to build.
]

=== The continuous case: the Shannon–Hartley formula

The version most engineers actually quote concerns a _continuous_ channel - a real wire or radio link carrying an analog waveform corrupted by additive Gaussian noise, constrained by a fixed transmit power and a fixed bandwidth. For that channel the capacity has a famous closed form, the _Shannon--Hartley theorem_:

$ C = B log_2 (1 + S/N) quad "bits per second," $

where $B$ is the bandwidth in hertz and $S\/N$ is the signal-to-noise power ratio. This one equation underlies the design of modems, Wi-Fi, cellular networks, and deep-space links. Every time an engineer trades bandwidth for power, or estimates the maximum bit rate of a link, this is the formula in play. Its message is sobering and liberating at once: capacity grows only _logarithmically_ with signal power (doubling power adds a fixed amount, not a doubling, to the rate) but _linearly_ with bandwidth (more spectrum is the cheap way to go faster). It connects Shannon's abstract theory back to Hartley's 1928 work that the early chapters of this book described, now on a rigorous footing.

#gomaths("Where the log in Shannon–Hartley comes from")[
You do not need calculus to feel why the capacity of a power-limited, noisy analog channel is _logarithmic_ in the signal-to-noise ratio. Picture transmitting by choosing a voltage level. Noise of typical size $sqrt(N)$ blurs each level into a fuzzy band of that width, so two levels are reliably distinguishable only if they sit more than about $sqrt(N)$ apart. Your total signal swing is limited by the power budget to about $sqrt(S + N)$. So the number of _distinguishable_ levels you can fit is roughly
$ (sqrt(S + N))/(sqrt(N)) = sqrt(1 + S/N). $
Each use of the channel therefore conveys $log_2 sqrt(1 + S\/N) = 1/2 log_2(1 + S\/N)$ bits - distinguishable levels turn into bits via the logarithm, exactly as $N$ equally-likely outcomes cost $log_2 N$ bits (Chapter 7). Multiply by the number of independent uses per second a bandwidth $B$ allows - the sampling theorem of Chapter 37 gives $2 B$ of them - and the factors $1\/2$ and $2$ cancel to yield $C = B log_2(1 + S\/N)$. The log is, once again, "counting distinguishable possibilities."
]

#aside[For our running BSC at $f = 0.1$, the capacity $0.531$ bits per use means that to push, say, one million reliable bits across this wire you must use it at least $1{,}000{,}000 \/ 0.531 approx 1{,}883{,}000$ times - you pay nearly a $1.9 times$ overhead in raw channel uses, all of it spent on error-correction redundancy, just to undo a $10%$ flip rate. Cleaner wires are dramatically cheaper.]

#algo(
  name: "Noisy-Channel Coding Theorem",
  year: "1948",
  authors: "Claude E. Shannon (Bell Labs)",
  aim: "Determine the maximum rate of reliable (vanishing-error) communication over a noisy channel, and prove it is achievable.",
  complexity: "Capacity is a single maximization $C = max_(p(x)) I(X;Y)$; for standard channels it is closed-form -- BSC $1-H_2(f)$, BEC $1-e$, AWGN $B log_2(1+S\/N)$.",
  strengths: "Exact, tight threshold (achievable below $C$, impossible above); the foundational result of all communications engineering; the random-coding proof is general and powerful.",
  weaknesses: "Achievability proof is non-constructive (proves good codes exist, not how to build them); assumes asymptotically long blocks, so it understates the cost at the short blocklengths real low-latency systems use.",
  superseded: "Never superseded; refined by finite-blocklength theory (Polyanskiy--Poor--Verdú, 2010) quantifying the short-block penalty, and realized in practice by turbo (1993), LDPC (1960/1996) and polar (2008) codes that approach $C$ efficiently.",
)[
This is the second of Shannon's two pillars. Where the Source Coding Theorem fixed the floor for _removing_ redundancy ($H$), the Channel Coding Theorem fixes the ceiling for _adding_ structured redundancy back ($C$). The bridge between them is mutual information, and the next section's separation theorem shows the two can be designed independently - the architectural decision that shaped every digital communication system since.
]


== Compression and error-correction are duals

Step back and look at what we have built. The Source Coding Theorem (Chapter 19) is about _squeezing out_ redundancy: a good compressor maps a redundant source to a stream of near-uniform, near-independent bits, each carrying close to a full bit of information, with the floor set by entropy $H$. The Channel Coding Theorem (this chapter) is about _putting redundancy back_: a good channel code maps each message to a longer codeword whose extra, carefully-structured bits let the receiver detect and correct the channel's errors, with the ceiling set by capacity $C$.

These are mirror images. Compression seeks the _most informative_ representation: strip every predictable bit, because a predictable bit is a wasted bit. Channel coding seeks the _most robust_ representation, adding back predictable, structured bits, because in a noisy world that very predictability lets the receiver catch and repair mistakes. The compressor's output, ideally, looks like random noise (maximum information density, no exploitable pattern); the channel coder's output, ideally, has _exactly the right amount_ of exploitable pattern to survive the noise. One drives toward randomness; the other away from it. The unit of account on both sides is the bit, calibrated by mutual information.

#keyidea[
_Compression and error-correction are two directions along one axis._ Compression removes redundancy until the data is maximally informative (rate $-> H$ from above). Error-correction adds structured redundancy until the data is maximally robust (rate $-> C$ from below). Both are governed by mutual information; both have a tight Shannon limit; both approach that limit only by coding over long blocks. They are duals, not rivals - and the next result says they can even be done in separate, independently-designed boxes.
]

== The source–channel separation theorem

We now reach the keystone - the result that justifies the architecture of essentially every digital system you have ever used. You want to send a source (say, a photograph) across a noisy channel (say, a Wi-Fi link). You have two jobs: _compress_ the photo (Source Coding Theorem) and _protect_ it against channel errors (Channel Coding Theorem). Must these be designed together, as one giant joint optimization considering source and channel simultaneously? Or can you build two separate boxes - a compressor that knows nothing about the channel, and an error-corrector that knows nothing about the source - wire them in series, and lose nothing?

Shannon's answer is the _source--channel separation theorem_, and it is a small miracle.

#theorem("Source–channel separation (Shannon, 1948)")[
A source with entropy rate $H$ (bits per source symbol) can be transmitted reliably over a channel of capacity $C$ (bits per channel use), at a ratio of $rho$ channel uses per source symbol, _if and only if_ $H < rho C$. This optimum is achieved by a _separated_ architecture: first compress the source to its entropy with a source code that ignores the channel, then protect the compressed bits with a channel code that ignores the source. No _joint_ source--channel scheme can do better in the limit of long blocks.
]

Read what this says. The condition $H < rho C$ is just "the bits you need to send (entropy) must fit within the bits the channel can carry (capacity, times the number of uses you get)." Bits are bits: once the source has been crushed down to a clean stream of $H$ bits per symbol, the channel coder does not need to know or care that they came from a photograph rather than a stock ticker or a genome. It just sees an incompressible bitstream and protects it. The two boxes communicate through a single, universal interface (_the bit_), and neither needs to know anything about the other's job.

#fig([The separated architecture, sanctioned by the separation theorem. The two boxes meet only at the bitstream. Source coder ignores the channel; channel coder ignores the content.], cetz.canvas({
  import cetz.draw: *
  let bx(x, y, w, h, lbl) = {
    rect((x,y),(x+w,y+h), fill: c-soft, stroke: rgb("#0b5394"))
    content((x+w/2, y+h/2), box(width: (w - 0.4) * 1cm, inset: 1pt, align(center, text(size: 8pt)[#lbl])))
  }
  content((-0.2, 0.5))[photo]
  line((0.5, 0.5), (1.0, 0.5), mark: (end: ">"))
  bx(1.0, 0.0, 2.0, 1.0)[source\ coder]
  line((3.0, 0.5), (3.6, 0.5), mark: (end: ">"))
  content((3.3, 0.85))[$H$ bits]
  bx(3.6, 0.0, 2.0, 1.0)[channel\ coder]
  line((5.6, 0.5), (6.2, 0.5), mark: (end: ">"))
  bx(6.2, 0.0, 1.6, 1.0)[noisy\ channel]
  line((7.8, 0.5), (8.4, 0.5), mark: (end: ">"))
  content((8.9, 0.5))[$dots.c$]
}))

This is why the engineering world is organized as it is. JPEG does not know whether its output will travel over Wi-Fi, 5G, a fibre cable, or a scratched DVD; it just produces compressed bits. The channel codes (the LDPC code in Wi-Fi, the polar code in 5G control channels) do not know whether the bits they protect are an image, a video, a voice call, or an email; they just protect bits. This clean layering - compress here, protect there, never the twain shall meet - is not merely a convenient convention. Shannon _proved_ it costs nothing, asymptotically. The modularity that lets separate teams build the entire digital stack with separate standards is a theorem.

#history[
The separation theorem is the unsung hero of Shannon's 1948 paper. Entropy and capacity get the glory, but separation is what made them _composable_ into an engineering discipline. Without it, every codec would have to be co-designed with every channel: JPEG-for-Wi-Fi, JPEG-for-DVD, JPEG-for-5G as separate, incompatible objects. With it, "compress" and "transmit reliably" became independent product categories, independent research communities, and independent chapters of this book. It is the reason a compression book can largely _ignore_ channels: separation grants us the right to assume a clean pipe and optimize against entropy alone.
]

=== When separation breaks down

Like every theorem, separation comes with fine print, and the fine print is exactly where the interesting modern work happens. The guarantee is _asymptotic_: it holds in the limit of infinitely long blocks. The moment you have finite, and especially _short_, blocks, separation is no longer optimal, and a jointly-designed source--channel code can beat the two-box architecture.

The reasons are worth understanding, because they explain a wave of recent research. First, _short blocks_: real-time systems - a video call, a control loop, a self-driving car's sensor link - cannot wait to accumulate a long block before sending. At short blocklengths the source coder cannot quite reach $H$, the channel coder cannot quite reach $C$, and the two penalties _compound_ rather than cancel; a joint code that shares one block of redundancy across both jobs can do strictly better. The finite-blocklength theory of Polyanskiy, Poor, and Verdú (2010) made this penalty precise, and analyses of joint source--channel coding show its second-order rate penalty is strictly smaller than the separated scheme's. Second, _graceful degradation_: a separated system has a cliff. Below the channel-code threshold it works perfectly; above it the decoder fails catastrophically and you get nothing. A joint, analog-style code (think old analog TV fading smoothly to snow rather than freezing) degrades gracefully as the channel worsens, which is often what users actually want. Third, the separation theorem assumes a _single, known, stationary_ point-to-point channel; for networks with multiple users, feedback, or unknown and varying channels, separation can provably fail.

#note[
These cracks in separation are not academic footnotes in 2026 - they are an active frontier. _Deep joint source--channel coding_ (DeepJSCC) trains a neural network to map an image (or video, or text) _directly_ to channel inputs and back, skipping the explicit "compress then protect" pipeline, and beating separated designs in the short-blocklength, low-latency regime that 6G targets; recent variants (SwinJSCC, MambaJSCC, and digital DeepJSCC) push this hard. It sits under the banner of _semantic communication_: transmit what the message _means_ for the receiver's task, not a bit-exact reconstruction - a deliberate inversion of Shannon's opening decision to ignore meaning. We return to this in the book's forward-looking chapters on learned and neural compression (Volume IV). The lesson for now: separation is the right default and the reason the whole stack is modular, but it is a _limit_ theorem, and the limit is exactly where its guarantees soften.
]

== Putting it together: a worked end-to-end story

Let us trace one concrete message through the whole machinery, so the three theorems lock into a single picture.

Imagine sending a long English text file across a binary symmetric channel with crossover $f = 0.1$ (capacity $C = 1 - H_2(0.1) approx 0.531$ bits per channel use). The text has an entropy rate of, say, about $H approx 1.3$ bits per character (Shannon's own estimate, from Chapter 18).

_Step 1 - source coding (remove redundancy)._ A good compressor (an arithmetic coder driven by a strong language model, Volumes II and IV) squeezes the text from its raw $8$ bits per character down toward its entropy rate of about $1.3$ bits per character. The output is now almost incompressible: nearly uniform, nearly independent bits, each carrying close to a full bit of information. We have walked up to the entropy floor from above. Mutual information's first reading ("redundancy you can exploit") was the fuel: every predictable correlation in English was a bit of mutual information between characters that the model cashed in.

_Step 2 - channel coding (add structured redundancy)._ Those $1.3$ bits per character of clean information must now cross a wire that flips $10%$ of bits. Sending them raw would corrupt about one bit in ten - catastrophic for compressed data, where a single flipped bit can derail the whole decode. So a channel code expands the stream, adding parity bits, until the rate per channel use drops below capacity $C approx 0.531$. By the Channel Coding Theorem, with long enough blocks the receiver then recovers the compressed bits with vanishing error. We have walked up to the capacity ceiling from below. Mutual information's second reading ("bits that survive the channel") set the ceiling.

_Step 3 - the bookkeeping (separation)._ How many channel uses does each character cost? We must fit $H approx 1.3$ bits through a channel carrying $C approx 0.531$ bits per use, so we need at least $rho = H \/ C approx 1.3 \/ 0.531 approx 2.45$ channel uses per character. The separation theorem ($H < rho C$) guarantees this is not only necessary but _sufficient_: with $rho$ a hair above $2.45$, reliable transmission is possible. We got here by designing compressor and channel code in total ignorance of each other, meeting only at the bitstream. The compressor never knew $f = 0.1$; the channel code never knew the bits were English.

_Step 4 - the honest asterisk._ If this were a live, low-latency link - a video call instead of a file transfer - Step 3's clean separation would leave a little performance on the table, and a jointly-trained DeepJSCC system could do measurably better by sharing redundancy across the two jobs. For a bulk file transfer with long blocks, separation is essentially perfect and the two-box design is exactly right. Knowing which regime you are in is the engineering judgment the theory equips you to make.

#tryit[
Redo the bookkeeping for a cleaner channel. Suppose the wire flips only $f = 0.01$ of bits, so $C = 1 - H_2(0.01) approx 1 - 0.081 = 0.919$ bits per use. Now each $1.3$-bit character needs only $rho approx 1.3 \/ 0.919 approx 1.41$ channel uses instead of $2.45$. A cleaner channel buys back channel uses _linearly_ in capacity - and capacity, recall from Shannon--Hartley, climbs only _logarithmically_ with transmit power. That asymmetry (cheap to add bandwidth, expensive to add power) is the quiet economic law behind half of wireless engineering.
]


== Measuring it in code

This chapter's quantities are not just blackboard objects - they are a few lines of Python each, and they give `tinyzip` a _diagnostic_ it has lacked. Until now we have built compressors; here we build the _meter_ that tells us how good a compressor's _model_ is, in the only currency that matters: wasted bits. The meter is exactly $D_"KL"(p || q)$, the gap between a model's cross-entropy and the true entropy.

#project("Extending model.py -- KL divergence and mutual information")[
This chapter has _no new canonical `tinyzip` step_ - the package's entropy meter, `model.entropy()` and `model.cross_entropy()`, was already built back in Step 6 (Chapters 18--19), and we reuse it verbatim rather than rewrite it. What we add here are the two _new_ diagnostics this chapter forged, dropped into the same `model.py` module beside their siblings: `kl_divergence` (the wasted-bits meter) and `mutual_information` (how much two streams know about each other). These are the numbers every later compressor's _model_ will be judged by.

First, recall the two functions Step 6 already gave us - we `import` them, we do not redefine them:

```python
# Already in tinyzip/model.py since Step 6 (Chapters 18-19):
#     entropy(p)      -> H(p)      = -sum p(x) log2 p(x)
#     cross_entropy(p, q) -> H(p,q) = -sum p(x) log2 q(x)
from tinyzip.model import entropy, cross_entropy

Dist = dict[int, float]                 # symbol -> probability
```

Recall too that Step 6's `cross_entropy` honestly returns `float("inf")` when the model `q` assigns probability zero to a symbol that really occurs - the $+infinity$ from the definition box made concrete: a code that calls a real event impossible can never encode it. With those in hand, the wasted-bits meter is a single subtraction, exactly the identity $D_"KL"(p||q) = H(p,q) - H(p)$ from this chapter:

```python
def kl_divergence(p: Dist, q: Dist) -> float:
    """D_KL(p || q) >= 0: the wasted bits/symbol. Zero iff q == p."""
    return cross_entropy(p, q) - entropy(p)
```

Now mutual information, straight from the divergence-from-independence formula, reusing the marginal-building loop from the earlier Python box:

```python
Joint = dict[tuple[int, int], float]    # (x, y) -> probability

def mutual_information(joint: Joint) -> float:
    """I(X;Y) = sum p(x,y) log2[ p(x,y) / (p(x) p(y)) ], in bits."""
    px: dict[int, float] = {}
    py: dict[int, float] = {}
    for (x, y), pxy in joint.items():
        px[x] = px.get(x, 0.0) + pxy
        py[y] = py.get(y, 0.0) + pxy
    info = 0.0
    for (x, y), pxy in joint.items():
        if pxy > 0.0:
            info += pxy * log2(pxy / (px[x] * py[y]))
    return info
```

A quick self-test against this chapter's hand-computed numbers:

```python
true = {0: 0.9, 1: 0.1}
lazy = {0: 0.5, 1: 0.5}
print(round(entropy(true), 3))             # 0.469  (the floor)
print(round(cross_entropy(true, lazy), 3)) # 1.0    (one bit, as the lazy code spends)
print(round(kl_divergence(true, lazy), 3)) # 0.531  (the wasted bits)

bsc = {(0,0): 0.45, (1,1): 0.45, (0,1): 0.05, (1,0): 0.05}
print(round(mutual_information(bsc), 3))    # 0.531  (= capacity of the BSC at f=0.1)
```

Every number matches the arithmetic we did by hand. From here on, whenever `tinyzip` gains a smarter model, you can _quantify_ the improvement: feed the old and new model distributions to `kl_divergence` against the true symbol frequencies and watch the wasted bits fall.
]

And the channel side - capacity of the two model channels - is just as short, and lets you draw the capacity curve $1 - H_2(f)$ for yourself:

#gopython("Default-argument functions and a capacity curve")[
A function can give a parameter a _default_, used when the caller omits it: `def binary_entropy(p, eps=1e-12)`. Here `eps` guards $log_2 0$. The body uses an `if` to return $0$ at the degenerate endpoints. We then sweep `f` over a list comprehension to tabulate capacity.

```python
from math import log2

def binary_entropy(p: float) -> float:
    """H2(p) = -p log2 p - (1-p) log2(1-p); the per-bit noise cost."""
    if p <= 0.0 or p >= 1.0:
        return 0.0
    return -p * log2(p) - (1 - p) * log2(1 - p)

def bsc_capacity(f: float) -> float:
    return 1.0 - binary_entropy(f)          # bits per channel use

def bec_capacity(e: float) -> float:
    return 1.0 - e                          # bits per channel use

for f in [0.0, 0.01, 0.1, 0.25, 0.5]:
    print(f, round(bsc_capacity(f), 3))
# 0.0 1.0 / 0.01 0.919 / 0.1 0.531 / 0.25 0.189 / 0.5 0.0
```

The curve plunges to $0$ at $f = 0.5$ (a pure coin, no information) and rises symmetrically back toward $1$ as $f -> 1$ (a wire that _always_ flips is as good as a clean one - just invert every received bit).
]

The meter does not change a single compressed byte, so the scoreboard's totals stand exactly where Chapter 19 left them. What it changes is your _understanding_ of those totals: every byte above the entropy floor on that scoreboard is, we can now say precisely, a payment of $D_"KL"(p || q)$ for a model that is not yet the truth.

#scoreboard(caption: "unchanged bytes, newly explained -- the gap above the floor is exactly KL divergence",
  [Entropy floor $H$ (Ch. 19)], [n/a], [n/a], [the unbeatable target, $H(p)$ bits/symbol],
  [Any real coder], [n/a], [$> H$], [overspend $= D_"KL"(p||q)$, the model's error in bits],
  [Channel overhead], [n/a], [$times 1\/C$], [error-correction multiplies size by $1\/C$ on a noisy link],
)

#takeaways((
  [_Relative entropy $D_"KL"(p || q) = sum_x p(x) log_2 (p(x)\/q(x)) >= 0$ is the exact number of bits you waste_ by coding a source $p$ with a model $q$. It is zero only when $q = p$ (Gibbs' inequality, via Jensen), never negative, and not symmetric. "Better compression" always means "smaller $D_"KL"$" - a better model, never a broken floor.],
  [_Mutual information $I(X; Y) = H(Y) - H(Y|X) = D_"KL"(p(x,y) || p(x)p(y))$ is one number with three faces_: redundancy you can exploit (compression), bits that survive a channel (communication), and distance from independence (statistics). It is symmetric, non-negative, and zero exactly when $X, Y$ are independent.],
  [_The data-processing inequality ($I(X;Z) <= I(X;Y)$ for $X -> Y -> Z$) says computation cannot create information_ - the rigorous reason "zoom and enhance" is fiction and a lossy thumbnail cannot be losslessly restored.],
  [_A channel is a transition table $p(y|x)$; its capacity $C = max_(p(x)) I(X;Y)$ is the most information it carries per use._ Closed forms: BSC $= 1 - H_2(f)$, BEC $= 1 - e$, Gaussian $= B log_2(1 + S\/N)$.],
  [_The Noisy-Channel Coding Theorem makes $C$ a tight ceiling_: reliable communication is possible below $C$ and impossible above it. The proof is sphere-packing - only about $2^(n C)$ non-overlapping output "clouds" fit, the exact mirror of the Source Coding Theorem's $2^(n H)$ typical messages.],
  [_Compression and error-correction are duals_: one strips redundancy toward the floor $H$ to maximize information density; the other adds structured redundancy up toward the ceiling $C$ to maximize robustness. Mutual information calibrates both.],
  [_The source--channel separation theorem ($H < rho C$) proves you can compress and protect in two independent boxes_ with no asymptotic loss - the theorem that makes the whole digital stack modular. It frays at short blocklengths, over networks, and for semantic goals, which is exactly where joint and learned (DeepJSCC) coding now lives.],
))

== Exercises

#exercise("20.1", 1)[
A source has true distribution $p = (1/2, 1/4, 1/4)$ over three symbols, but you model it as uniform $q = (1/3, 1/3, 1/3)$. Compute $H(p)$, the cross-entropy $H(p, q)$, and the wasted bits $D_"KL"(p || q)$. Verify that the three numbers satisfy $H(p,q) = H(p) + D_"KL"(p||q)$.
]
#solution("20.1")[
$H(p) = 1/2 dot 1 + 1/4 dot 2 + 1/4 dot 2 = 1.5$ bits. The uniform code spends $log_2 3 approx 1.585$ bits on every symbol, so $H(p, q) = log_2 3 approx 1.585$ bits. Then $D_"KL"(p||q) = 1.585 - 1.5 = 0.085$ bits/symbol. Check: $H(p) + D_"KL" = 1.5 + 0.085 = 1.585 = H(p,q)$. The lazy uniform model wastes only about $0.085$ bits here because $p$ is already fairly flat.
]

#exercise("20.2", 2)[
Show by direct computation that KL divergence is asymmetric. Let $p = (3/4, 1/4)$ and $q = (1/4, 3/4)$. Compute both $D_"KL"(p || q)$ and $D_"KL"(q || p)$. Are they equal? Explain in one sentence why, by the _symmetry_ of these two particular distributions, you might have _guessed_ they would be equal here - and why that guess turns out correct for this special pair even though KL is asymmetric in general.
]
#solution("20.2")[
$D_"KL"(p||q) = 3/4 log_2 (3\/4)/(1\/4) + 1/4 log_2 (1\/4)/(3\/4) = 3/4 log_2 3 + 1/4 log_2 (1\/3) = 3/4(1.585) - 1/4(1.585) = 1/2 log_2 3 approx 0.792$ bits. By the same arithmetic with $p$ and $q$ swapped, $D_"KL"(q||p) = 3/4 log_2 3 + 1/4 log_2(1\/3) = 0.792$ bits too. They _are_ equal here. The reason is that $q$ is the mirror image of $p$ (swap the two symbols), so the two divergences are computed from the identical multiset of ratios ${3, 1/3}$ with the identical weights ${3/4, 1/4}$ - a symmetry of _this pair_, not of KL itself. For a generic pair, e.g. the $p,q$ in the chapter's myth box, they differ.
]

#exercise("20.3", 1)[
A binary symmetric channel flips bits with probability $f = 0.2$. What is its capacity in bits per channel use? If instead the channel were a binary erasure channel that erases with the same probability $e = 0.2$, what would its capacity be? Which is larger, and state the one-sentence reason.
]
#solution("20.3")[
$H_2(0.2) = -0.2 log_2 0.2 - 0.8 log_2 0.8 approx 0.2(2.322) + 0.8(0.322) approx 0.722$ bits, so $C_"BSC" = 1 - 0.722 = 0.278$ bits/use. The BEC gives $C_"BEC" = 1 - 0.2 = 0.8$ bits/use. The erasure channel's capacity is far larger because the receiver _knows which_ bits are missing; on the BSC a flipped bit is indistinguishable from a correct one, so the decoder must spend bits both locating and correcting errors.
]

#exercise("20.4", 2)[
Use the data-processing inequality to settle a practical argument. A friend claims that by running a JPEG image (already lossy) through a sharpening filter and an "AI upscaler," they can recover detail that the original JPEG threw away. Let $X$ be the original raw photo, $Y$ the JPEG, and $Z$ the upscaled-and-sharpened result, with $X -> Y -> Z$. What does the data-processing inequality say about $I(X; Z)$ versus $I(X; Y)$, and what does that imply about the friend's claim?
]
#solution("20.4")[
Since $Z$ is computed from $Y$ alone (the upscaler never sees the raw $X$), $X -> Y -> Z$ is a Markov chain, so $I(X; Z) <= I(X; Y)$. The processed image can contain _no more_ information about the original raw photo than the JPEG already held - every operation can only preserve or destroy information about $X$, never add it. So any "detail" the upscaler produces is _invented_, not _recovered_: it may look plausible, but it cannot be information about the true original that the JPEG had already discarded. The friend's claim, taken as "recovering lost original detail," is impossible.
]

#exercise("20.5", 2)[
Prove that $I(X; Y) <= H(X)$ and $I(X; Y) <= H(Y)$ - mutual information can never exceed either variable's own entropy. Then state what it means, in words, when $I(X; Y) = H(X)$ exactly.
]
#solution("20.5")[
From the definition $I(X;Y) = H(X) - H(X|Y)$. Conditional entropy is non-negative ($H(X|Y) >= 0$, since it is an average of ordinary entropies, each $>= 0$), so $I(X;Y) = H(X) - H(X|Y) <= H(X)$. By the symmetric form $I(X;Y) = H(Y) - H(Y|X) <= H(Y)$ likewise. Equality $I(X;Y) = H(X)$ holds exactly when $H(X|Y) = 0$, i.e. when $Y$ determines $X$ completely - once you know $Y$ there is _no_ residual uncertainty about $X$, so $Y$ carries _all_ of $X$'s information.
]

#exercise("20.6", 3)[
Compute the mutual information of a binary erasure channel with uniform input. Let $X in {0,1}$ with $p(0)=p(1)=1/2$, and let the channel erase with probability $e$, so $Y in {0, 1, ?}$. Build the joint distribution $p(x,y)$, find the marginals $p(y)$, and compute $I(X;Y)$ from $H(X) - H(X|Y)$. Confirm you get $1 - e$, the stated capacity.
]
#solution("20.6")[
The joint: $p(0,0) = p(1,1) = 1/2 (1-e)$ (sent and survived); $p(0,?) = p(1,?) = 1/2 e$ (erased); $p(0,1) = p(1,0) = 0$ (no flips). Marginals of $Y$: $p(0) = p(1) = 1/2(1-e)$ and $p(?) = e$. Now $H(X|Y)$: when $Y = 0$ or $Y = 1$ (probability $1-e$ total), $X$ is known exactly, contributing $0$; when $Y = ?$ (probability $e$), $X$ is still a uniform bit, contributing $H_2(1/2) = 1$ bit. So $H(X|Y) = (1-e) dot 0 + e dot 1 = e$. With $H(X) = 1$, we get $I(X;Y) = 1 - e$ - exactly the BEC capacity. The uniform input is optimal by symmetry, so $C_"BEC" = 1 - e$.
]

#exercise("20.7", 2)[
Using the `model.py` functions from the project box (`kl_divergence`, reusing Step 6's `entropy`/`cross_entropy`), write a few lines that take a true distribution `p` and _two_ candidate models `q1`, `q2`, and print which model wastes fewer bits and by how much. Then apply it to `p = {0: 0.7, 1: 0.2, 2: 0.1}`, `q1 = {0: 0.5, 1: 0.3, 2: 0.2}`, `q2 = {0: 0.8, 1: 0.15, 2: 0.05}` and say which model is better.
]
#solution("20.7")[
```python
def compare(p, q1, q2):
    d1, d2 = kl_divergence(p, q1), kl_divergence(p, q2)
    better = "q1" if d1 < d2 else "q2"
    print(f"q1 wastes {d1:.4f}, q2 wastes {d2:.4f}; {better} is better by {abs(d1-d2):.4f} bits/sym")

p  = {0: 0.7, 1: 0.2, 2: 0.1}
q1 = {0: 0.5, 1: 0.3, 2: 0.2}
q2 = {0: 0.8, 1: 0.15, 2: 0.05}
compare(p, q1, q2)
```
Numerically, $D_"KL"(p||q_1) approx 0.099$ bits and $D_"KL"(p||q_2) approx 0.042$ bits, so `q2` is the better model - it is closer to the true skew of `p` (heavier on symbol $0$). The program prints that `q2` wins by about $0.057$ bits/symbol.
]

#exercise("20.8", 3)[
The separation theorem says a source of entropy rate $H$ crosses a channel of capacity $C$ using $rho > H\/C$ channel uses per symbol. Consider a DNA-like source over four symbols with entropy rate $H = 1.9$ bits/symbol, sent over a BSC with $f = 0.05$. (a) Compute $C$ and the minimum channel uses per symbol $rho_min = H\/C$. (b) The link runs at $10^6$ channel uses per second; what is the maximum reliable source-symbol rate? (c) In one or two sentences, explain when you would _abandon_ the separated design this calculation assumes.
]
#solution("20.8")[
(a) $H_2(0.05) = -0.05 log_2 0.05 - 0.95 log_2 0.95 approx 0.05(4.322) + 0.95(0.074) approx 0.286$ bits, so $C = 1 - 0.286 = 0.714$ bits/use. Then $rho_min = 1.9 \/ 0.714 approx 2.66$ channel uses per source symbol. (b) At $10^6$ uses/s, the maximum reliable symbol rate is $10^6 \/ 2.66 approx 376{,}000$ source symbols per second. (c) You would abandon separation for a _jointly_-designed (e.g. DeepJSCC) code when blocks must be very short and latency is tight - a live video call or a control loop - or over a multi-user/varying network, where the asymptotic, single-channel assumptions behind separation no longer hold and a joint code can do strictly better or degrade more gracefully.
]

== Further reading

The primary source remains Shannon's own paper; the channel-coding theorem and the capacity formula are the climax of its first part, and the treatment of continuous channels and the $B log_2(1 + S\/N)$ law are in its second part.

- Claude E. Shannon, #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[_A Mathematical Theory of Communication_], Bell System Technical Journal, 27 (1948), 379–423 and 623–656 - the noisy-channel coding theorem and the Gaussian-channel capacity.
- Solomon Kullback and Richard Leibler, _On Information and Sufficiency_, Annals of Mathematical Statistics, 22 (1951), 79–86 - the paper that introduced the divergence now bearing their names.
- Yury Polyanskiy, H. Vincent Poor and Sergio Verdú, _Channel Coding Rate in the Finite Blocklength Regime_, IEEE Transactions on Information Theory, 56 (2010), 2307–2359 - what reliable communication costs at the short blocklengths real systems use, where separation's asymptotic optimality frays.
- Eirina Bourtsoulatze, David Burth Kurka and Deniz Gündüz, #link("https://arxiv.org/abs/2211.08747")[_Deep Joint Source-Channel Coding for Semantic Communications_], and the broader DeepJSCC literature - the 2020s revival of joint source--channel coding with neural networks, the practical face of "separation breaks at short blocks."
- Thomas M. Cover and Joy A. Thomas, _Elements of Information Theory_ (2nd ed., Wiley, 2006) - chapters 2, 7, and 8 develop relative entropy, channel capacity, and the channel coding theorem rigorously.
- David J. C. MacKay, #link("https://www.inference.org.uk/itila/")[_Information Theory, Inference, and Learning Algorithms_] (Cambridge, 2003), Part II - especially good on the sphere-packing intuition and on actually-constructible capacity-approaching codes.

#bridge[
We have now mapped the two extremes Shannon staked out: the floor $H$ below which lossless compression cannot go, and the ceiling $C$ above which reliable communication cannot go. But every interesting medium - a photograph, a song, a film - lives in between, where we deliberately _throw information away_ in exchange for fewer bits. How few bits can you spend if you are willing to tolerate a little distortion? That trade-off has its own exact theory, and its own Shannon limit: the _rate--distortion function_ $R(D)$. Chapter 21 builds it, using the very mutual information we just forged - for $R(D)$ turns out to be, once again, a mutual information squeezed against a constraint.
]
