#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// local helper: a worked numeric example box (self-contained to this chapter)
#let example(body) = block(width: 100%, breakable: true,
  inset: (x: 10pt, y: 8pt), radius: 4pt, fill: rgb("#fbf7ef"),
  stroke: (left: 3pt + rgb("#783f04")), above: 9pt, below: 9pt)[
  #text(weight: "bold", fill: rgb("#783f04"))[Worked example.] #h(3pt) #body
]

= Compression as Intelligence: The Theory

#epigraph[Comprehension is compression.][Gregory Chaitin]

Here is a claim so bold it sounds like a slogan from a startup pitch deck, yet it is defended by some of the most careful theorists alive: _the ability to compress data well is the same thing as the ability to understand it, and understanding is what we mean by intelligence._ Push hard enough on that sentence and it threatens to dissolve one of the oldest mysteries we have. What is it to learn? What is it to know? The thesis of this chapter answers, with a straight face: *to learn is to find a shorter description.* A child who notices that the sky is blue every morning has compressed a thousand future observations into one rule. A physicist who writes $F = m a$ has compressed every falling apple and orbiting moon into five symbols. A neural network that drops its loss from $4.0$ to $1.0$ bits per token has, by the same measure, found three bits of structure in every token of human writing it could not see before.

This is the most ambitious idea in the whole book, and also the most contested. In the last chapter we watched neural audio codecs turn into the tokenizers that feed audio language models; before that, Chapter 23 promised an experiment in which a frozen language model out-compresses FLAC on audio and PNG on images, knowing nothing of sound or pictures. That was the _engineering_ punchline, and Chapter 62 will make it run. This chapter is the _theory_ underneath it. Just as importantly, it is the honest list of reasons the slogan might be wrong, or at least incomplete. I will build the case carefully, brick by brick, and then try to knock it down.

#recap[
This chapter is the theoretical capstone of a thread that runs through the whole book. In *Chapter 18* we defined Shannon entropy $H(X) = -sum_i p_i log_2 p_i$, the true unavoidable cost of a source, and self-information $-log_2 p$, the surprise of one symbol. In *Chapter 19* the Source Coding Theorem proved entropy is a hard _floor_. In *Chapter 20* we met the *Kullback--Leibler divergence* $D_("KL")(P parallel Q) >= 0$, the penalty for using the wrong model. In *Chapter 22* we met *Kolmogorov complexity* $K(x)$ (the length of the shortest program that prints $x$), the ideal, uncomputable compressed size, and *Solomonoff's* algorithmic probability. In *Chapter 23* we fused these into one identity: cross-entropy = expected code length, so a predictor _is_ a compressor and its training loss _is_ a code length; we also met *Rissanen's MDL* and the *Hutter Prize*. This chapter takes that identity to its logical extreme, through MDL, PAC-Bayes, Solomonoff's universal predictor, and Hutter's *AIXI*, and then weighs the counterarguments honestly.
]

#objectives((
  [Restate the *compression = prediction* identity as a precise statement about _learning_, not just coding, and explain why "to generalize is to compress."],
  [Use the *Minimum Description Length* principle as a working theory of inference, and prove the two-part code cannot be fooled by memorizing noise.],
  [Read a *PAC-Bayes / Occam* generalization bound and see, line by line, how a shorter description _provably_ implies better prediction on unseen data.],
  [Explain *Solomonoff induction* as the ideal learner: a Bayesian mixture over all programs, weighted by $2^(-"length")$, and state its optimality and its uncomputability.],
  [Sketch *AIXI*, Hutter's "most intelligent agent," as Solomonoff induction plus reward-seeking, and state precisely the sense in which it is optimal.],
  [State the *Hutter thesis* ("compression is equivalent to general intelligence") and marshal both the empirical evidence for it and the strongest honest counterarguments against it.],
))

== From coding to learning: the leap this chapter makes

Chapter 23 left us with an identity we should keep in front of us like a compass.

#keyidea[
*The number $-log_2 Q(x)$ is three things at once.* It is the *surprise* of outcome $x$ under model $Q$ (Chapter 18). It is the *number of bits* an ideal coder spends to record $x$ (Chapter 19, Chapter 26). And it is the *training loss* a machine-learning model pays on example $x$ (Chapter 23). One quantity, three names. Whenever you see one, the other two are standing silently behind it.
]

So far we have used this identity in a modest way: as a bridge between _coding_ and _probability_. This chapter makes a far bolder claim. It says the identity is also a bridge to _learning itself_: the very act of finding regularity in the world, which is what intelligence does, is _measured_ by how much you can compress.

Why should that be? Walk through it intuitively first; the mathematics comes after. Suppose I hand you a long string of digits and it begins $3.14159265358979...$. If you have never seen $pi$ before, the string looks random: to record the first thousand digits you must store all thousand. But if you _recognize_ it as $pi$, you can throw the thousand digits away and write a three-line program: "compute $pi$ to 1000 places; print it." Your recognition (your _understanding_) has collapsed a thousand symbols into three lines. The compression _is_ the understanding, made countable. A being that recognizes more patterns compresses more strings shorter. That, the thesis says, is the whole of it.

#aside[
The reverse is just as telling. A string your friend _cannot_ compress is, from your friend's point of view, _random_: there is no pattern they can exploit. "Random," in this theory, is not a property of the string in the world; it is a confession about the limits of the observer's understanding. The same string of stock prices is white noise to me and a printout of structure to a quant fund with a better model. Compressibility is in the eye (or the model) of the beholder. We made this precise in Chapter 22 with the incompressible strings; here we are giving it an epistemic reading.
]

=== "Generalize" and "compress" are the same verb

In machine learning the word everyone worships is *generalization*: a model that has truly _learned_ does well not on the data it was trained on (any lookup table can memorize that) but on _new_ data it has never seen. The deepest version of our thesis is that this prized ability is identical to compression. Let us see why, with a tiny story.

Two students sit an exam. Both score 100% on the practice questions they were given to study. Student A memorized the answer key word for word. Student B noticed the _rule_ behind the questions ("ah, these are all asking me to factor a quadratic") and learned the rule. On the practice set they are indistinguishable. On the _real_ exam, with new questions, Student A is lost and Student B sails through. We say Student B "understood" and Student A "crammed."

Now describe what each student carries in their head as a _file you must transmit_. Student A's knowledge is the full answer key: as long as the data itself, no compression. Student B's knowledge is one short rule, far shorter than the data it explains. The student who compressed is exactly the student who generalized. This is not an analogy that happens to line up. The rest of this chapter argues it is a theorem.

#checkpoint[Your friend claims they have "learned" a sequence of 10,000 coin flips by writing them all down in a notebook. Have they learned anything, in the compression sense? What length of description would count as genuine learning?][They have learned nothing: their "description" (the notebook) is as long as the data, zero compression, the answer-key strategy. Genuine learning would be a description _shorter_ than 10,000 bits, e.g. "a fair coin, flipped 10,000 times" (a few dozen bits), which would mean they had found real structure. If the flips really are fair and independent, no shorter description exists. That, correctly, means there was nothing to learn.]

== MDL as a theory of inference, not just coding

We met the *Minimum Description Length* principle in Chapter 23 as Rissanen's "Occam's razor with a bit-meter." There it was a tool for choosing a model. Here we promote it to a full _theory of inference_, a rule for deciding what to believe given evidence, and we prove the one property that makes it trustworthy.

#definition("Two-part MDL code")[
To describe a dataset $D$ using a model $M$ drawn from some set of candidate models, transmit two things: first the *model itself*, costing $L(M)$ bits; then the *data as seen through that model*, costing $L(D | M)$ bits (the bits of "surprise" left over once the model has explained the regularities). The total description length is
$ L(D) = L(M) + L(D | M). $
*MDL says: believe the model $M$ that makes this total smallest.*
]

The genius of the two parts is that they pull in opposite directions, and the tension is exactly the tension between under-fitting and over-fitting that plagues all of learning.

- A model that is _too simple_ (say "the data is just random noise") is cheap to state ($L(M)$ tiny) but explains nothing, so the leftover surprise $L(D | M)$ is enormous. It _under-fits_.
- A model that is _too complex_ (one that has a special case carved out for every single data point) drives the surprise $L(D|M)$ to nearly zero, but now _stating the model_ costs as many bits as the data itself. It _over-fits_, and the giant $L(M)$ term punishes it.

The minimum of the sum sits at the genuine regularity: complex enough to capture the real pattern, simple enough not to memorize the noise. And here is the property that makes MDL more than a heuristic.

#theorem("MDL cannot be fooled by memorizing noise")[
Let the model class include the "null" model $M_0$ that explains nothing, under which the data costs its raw length, $L(D | M_0) = L_0$ bits. Then *any* model $M$ that MDL prefers over $M_0$ must satisfy $L(M) + L(D|M) < L_0$, that is, $M$ together with its residual is _strictly shorter_ than the raw data. A model that merely memorizes the data, paying $L(M) approx L_0$ bits to specify itself, can never win.
]

#proof[
MDL selects the model minimizing $L(M) + L(D|M)$. The null model achieves $0 + L_0 = L_0$ (it costs nothing to state "no structure," and leaves all $L_0$ bits as surprise). So MDL prefers $M$ over $M_0$ only if $L(M) + L(D|M) < L_0$. Now suppose $M$ is a pure memorizer: it has, baked into its own description, a copy of the data, so that decoding is trivial and $L(D|M) approx 0$. But a description from which the data can be read off _is_ a description of the data, and by the counting argument of Chapter 8 (the pigeonhole bound: most strings of length $L_0$ have no description shorter than about $L_0$ bits) we must have $L(M) gt.tilde L_0$. Then $L(M) + L(D|M) gt.tilde L_0$, so $M$ does _not_ beat the null model. The only models that win are those whose _total_ description, structure plus residual, genuinely beats storing the raw data, i.e. those that have found real, transmissible structure. $qed$
]

Read that proof twice, because it is the mathematical heart of why "compression = learning" is not wishful thinking. *Noise is incompressible, so a model that fits noise cannot pay for itself in bits.* Over-fitting is not merely discouraged by some tuning knob you have to set by hand; it is _structurally impossible_ to profit from, because the currency is the bit and noise has no cheap description. You get regularization for free, with no validation set, no held-out data, no arbitrary penalty constant. The bit-meter does it automatically.

#misconception[MDL needs you to pick a regularization strength, like the $lambda$ in ridge regression or weight decay, so it is just another knob-twiddling method in disguise.][The whole point of MDL is that the trade-off is set by the _laws of coding_, not by a knob. The "penalty" on complex models is simply how many bits they cost to write down, and that is fixed once you fix the coding scheme. Different reasonable coding schemes give the famous $(1\/2) log_2 n$-per-parameter price we derived in Chapter 23, a number that falls out of the math, not out of cross-validation. The honest caveat is that _choosing the coding scheme_ for $L(M)$ is itself a modelling choice; MDL converts "pick a regularizer" into "pick how to describe your hypotheses," which is often more natural but not free.]

=== A worked MDL decision

#example[
You observe $n = 100$ bits from a source. Two hypotheses compete. $M_0$: "fair coin," $p = 1/2$, which costs $0$ bits to state (it is the default) and codes each bit at $-log_2(1/2) = 1$ bit, for $L(D | M_0) = 100$ bits. $M_1$: "biased coin with $p = 0.9$ of a 1," which costs, say, $7$ bits to state the parameter to reasonable precision, and (if the data really does contain $90$ ones and $10$ zeros) codes the data at $-90 log_2(0.9) - 10 log_2(0.1) approx 90(0.152) + 10(3.32) approx 13.7 + 33.2 = 46.9$ bits.

Compare totals: $M_0$ costs $0 + 100 = 100$ bits; $M_1$ costs $7 + 46.9 approx 53.9$ bits. MDL prefers $M_1$ by a wide margin, _and it has compressed the file from 100 bits to 54._ The act of choosing the better model and the act of compressing harder are, to the bit, the same act. Notice too that if the data had been a balanced $50$--$50$ split, $M_1$ would code it at $approx 100$ bits anyway plus the $7$-bit overhead, _losing_ to $M_0$, so MDL would correctly refuse the bias it cannot justify.
]

#history[
MDL was introduced by Jorma Rissanen at IBM in 1978 ("Modeling by Shortest Data Description"), building consciously on Ray Solomonoff's algorithmic probability (1964), Andrey Kolmogorov's complexity (1965), and Hirotugu Akaike's information criterion (1973). Rissanen spent the 1980s and 1990s sharpening the crude two-part code into "stochastic complexity" and the normalized maximum likelihood (NML) code, which removes the arbitrariness in how you spend bits on the model. Chris Wallace and David Boulton had independently reached a closely related idea, *Minimum Message Length* (MML), in 1968: a Bayesian cousin that, unusually for the era, was already a working clustering program. The two schools argued amicably for decades about whose code was "righter." For our purposes they agree on the slogan: the best explanation is the shortest one that still fits.
]

== PAC-Bayes: a shorter description provably predicts better

MDL says "prefer the shorter description" and gives a compelling argument that this avoids over-fitting. But a sceptic can still ask the killer question: _why should a hypothesis that is short and fits my data also work on data I have never seen?_ Compression is about the past (the data in hand); generalization is about the future (data yet to come). What licenses the leap from one to the other?

The bridge is a body of results in *learning theory* whose oldest member is literally called the *Occam's razor bound* (Blumer, Ehrenfeucht, Haussler, and Warmuth, 1987). Its modern, sharpest form lives inside the *PAC-Bayes* framework. We will state the idea precisely but gently, building every piece.

#gomaths("Probability of a bad event, and the union bound")[
We need two everyday facts about probability (Chapter 9). First, a probability is a number in $[0,1]$ measuring how often something happens; an event with probability $0.05$ happens about 1 time in 20. Second, the *union bound*: if you have several bad events, the chance that _at least one_ of them happens is _no more_ than the sum of their individual chances. In symbols, $PP("A or B or ...") <= PP(A) + PP(B) + ...$. Intuition: you are over-counting the overlaps, so the sum can only be too big, never too small. We use it to say: "if each of my many hypotheses is _individually_ unlikely to fool me, then it is unlikely that _any_ of them fools me." That single step is what turns a fit on past data into a promise about future data.
]

The proof also leans on one more fact: a measured average is, with high probability, _close_ to the true average it estimates. This is the single most useful idea in all of statistics, so it earns its own box.

#gomaths("Concentration: why averages stop wobbling (Hoeffding's inequality)")[
Flip a fair coin $10$ times and you might get $7$ heads: the measured fraction $0.7$ is far from the true $0.5$. Flip it $10{,}000$ times and you will get something very near $0.5$ almost every time. The measured average _concentrates_ around the true average as the sample grows; big random wobbles become vanishingly unlikely. *Hoeffding's inequality* (Wassily Hoeffding, 1963) makes this exact. If you average $n$ independent quantities each pinned to the range $[0,1]$ (for us, $n$ separate "was the hypothesis wrong on this example?" answers, each a $0$ or a $1$) then the chance the measured average $hat(e)$ misses the true average $e$ by more than a gap $t$ is at most
$ PP(e - hat(e) > t) <= e^(-2 n t^2). $
Read the right-hand side: it shrinks _fast_ as the sample $n$ grows and as the gap $t$ you demand grows. A small worked feel for it: with $n = 5000$ and $t = 0.1$, the bound is $e^(-2 dot 5000 dot 0.01) = e^(-100)$, astronomically tiny. A $5000$-example average will virtually never wander $0.1$ from the truth. This is the engine that lets a number measured on _past_ data (training error) testify about _future_ data (true error). We do not prove Hoeffding here; we use it as a tool, exactly as we use a calculator's square-root key.
]

Here is the setup, in plain words. You draw a training sample of $n$ examples at random from the real world. You pick a hypothesis $h$ from some countable list of candidate hypotheses. You measure its *training error* $hat(e)(h)$ (how often it is wrong on your sample). What you actually care about is its *true error* $e(h)$: how often it would be wrong on the whole world. The danger is that $h$ looks great on the sample by luck and is secretly terrible. The Occam bound controls exactly that danger, and it controls it using the _description length_ of $h$.

#theorem("Occam / PAC-Bayes generalization bound (countable form)")[
Fix in advance a code that assigns each hypothesis $h$ a description of $L(h)$ bits (so that $sum_h 2^(-L(h)) <= 1$, the Kraft inequality of Chapter 19). Draw $n$ examples independently. Then with probability at least $1 - delta$ over the draw of the sample, _every_ hypothesis $h$ simultaneously satisfies
$ e(h) <= hat(e)(h) + sqrt((L(h) ln 2 + ln(1\/delta)) / (2 n)). $
In words: the true error is at most the training error plus a penalty that *grows with the description length $L(h)$ and shrinks as you gather more data $n$.*
]

#proof[
Fix one hypothesis $h$. Its training error $hat(e)(h)$ is an average of $n$ independent $0/1$ "was it wrong?" outcomes, whose true mean is $e(h)$. *Hoeffding's inequality* (the concentration box above) says
$ PP(e(h) - hat(e)(h) > t) <= e^(-2 n t^2). $
Now we want this to hold for _all_ $h$ at once. Give hypothesis $h$ a personal failure-budget $delta_h = delta dot 2^(-L(h))$. Set its threshold $t_h$ so that $e^(-2 n t_h^2) = delta_h$, i.e. $t_h = sqrt((L(h) ln 2 + ln(1\/delta)) / (2n))$. By the union bound, the chance that _any_ hypothesis exceeds its own threshold is at most
$ sum_h delta_h = delta sum_h 2^(-L(h)) <= delta dot 1 = delta, $
where the last step is the Kraft inequality (the description lengths come from a real code, so their $2^(-L(h))$ sum to at most $1$). Therefore, with probability at least $1 - delta$, every $h$ obeys $e(h) <= hat(e)(h) + t_h$, which is the claim. $qed$
]

Stop and savour what just happened, because it is the rigorous core of the whole thesis. *The shorter your hypothesis (the smaller $L(h)$), the smaller the penalty, the tighter the guarantee that it will keep working on new data.* Compression on the training set literally _buys_ generalization to the test set, with a bound you can compute. The cheap bits you saved by describing your hypothesis briefly are the same bits that certify it will not embarrass you tomorrow. Occam's razor stops being a vague preference for simplicity and becomes a theorem with a $sqrt(L(h)\/n)$ in it.

#keyidea[
*Short description $arrow.r.double$ provable generalization.* If two hypotheses fit your data equally well, the one with the shorter description is guaranteed (with high probability) to have the smaller true error, by an amount you can bound. The compression you achieve is a _certificate_ of generalization.
]

#example[
Two spam filters both label your $n = 2{,}500$ training emails perfectly ($hat(e) = 0$), at confidence $delta = 0.01$ (so $ln(1\/delta) = ln 100 approx 4.6$). Filter A is a tidy rule set describable in $L_A = 200$ bits; Filter B is a sprawling tangle of special cases needing $L_B = 2000$ bits. The bound's penalty is $sqrt((L (0.693) + 4.6)\/5000)$. For A: $sqrt((138.6 + 4.6)\/5000) = sqrt(143.2\/5000) = sqrt(0.0286) approx 0.169$, so A's true error is _certified_ $<= 17%$. For B: $sqrt((1386 + 4.6)\/5000) = sqrt(1390.6\/5000) = sqrt(0.278) approx 0.527$, so B's guarantee is a useless $<= 53%$. Same flawless training performance, wildly different promises about tomorrow's email. The _only_ thing that differed was the description length. The shorter (more compressed) filter is the one you should trust on mail it has never seen.
]

#aside[
This is not a museum piece. In 2019, Zhou and colleagues used a compression-based PAC-Bayes bound to produce the first _non-vacuous_ generalization guarantees for real neural networks on ImageNet: bounds whose number is actually below $100%$ error, which sounds trivial until you learn that for decades the bounds for big nets were so loose they promised nothing at all. In 2022, Lotfi and co-authors (NYU) tightened these into "PAC-Bayes compression bounds so tight that they can explain generalization": the better they could _compress_ a trained network, the better their provable bound on its test error. The 40-year-old Occam bound, fed modern compression, finally said something true and useful about why deep learning works. The thesis of this chapter is doing real work in 2020s research, not just philosophy.]

#checkpoint[In the Occam bound, what happens to the generalization guarantee if you let your hypothesis be _as long as the data itself_ (the memorizer, $L(h) approx n$ bits)?][The penalty term $sqrt(L(h)\/2n) approx sqrt(n\/2n) = sqrt(1\/2) approx 0.71$ becomes enormous: about $0.71$ added to the error rate, which makes the bound vacuous (error could be anything up to $1$). The bound _refuses to certify the memorizer_, exactly as it should. Only hypotheses much shorter than the data ($L(h) << n$) get a meaningful guarantee. Compression and a useful bound stand or fall together.]

== Solomonoff: the ideal learner that compresses everything

MDL and PAC-Bayes are about choosing among _candidate_ models you wrote down in advance. But what is the _best possible_ learner, the one that considers _every_ hypothesis and holds nothing back? We met its outline in Chapter 22. Now we make it the centrepiece, because it is the purest statement of "compression = intelligence" anyone has ever written.

The idea is Ray Solomonoff's (1960--1964), and it is breathtakingly direct. To predict the next symbol of a data stream, consider _every computer program_ that could have produced the data seen so far. Believe each program in proportion to $2^(-("its length"))$: short programs are _a priori_ more plausible than long ones (that is Occam's razor, not assumed but built into the weights). Then average their predictions for the next symbol. That weighted average is your prediction.

#gomaths("Bayesian mixing over hypotheses")[
Bayes' rule (Chapter 9) tells you how to update belief with evidence. If you have several hypotheses $H_1, H_2, ...$ with prior beliefs $w_1, w_2, ...$ (positive numbers summing to $1$), and each hypothesis assigns a probability to the data, then after seeing data your belief in $H_i$ is reweighted in proportion to how well $H_i$ predicted that data. To predict the _next_ symbol you do not pick one winner; you take a _weighted vote_:
$ P("next" = x) = sum_i w_i^("now") dot P_(H_i)("next" = x), $
where $w_i^("now")$ is hypothesis $i$'s current (posterior) weight. Hypotheses that have predicted well so far get a louder vote. Solomonoff's move is simply to let the hypotheses be _all computable programs_, and to set the prior weight of a program to $2^(-"length")$.
]

#definition("Solomonoff's universal prior and induction")[
The *universal prior* assigns to a binary string $x$ the probability
$ M(x) = sum_(p : space U(p) = x...) 2^(-abs(p)), $
the sum over all programs $p$ that, run on a fixed universal computer $U$, output something _beginning with_ $x$, each weighted by $2^(-abs(p))$ where $abs(p)$ is the program's length in bits. *Solomonoff induction* predicts the next symbol using the conditional version of $M$: it is exact Bayesian prediction with $M$ as the prior. Because short programs dominate the sum, $M(x)$ is large precisely when $x$ has a short program, i.e. when $x$ is _compressible_. Up to a constant, $-log_2 M(x) approx K(x)$, the Kolmogorov complexity (Chapter 22): *the universal prior of a string is essentially $2$ to the minus its compressed length.*
]

That last line is the thesis in one equation. The _a priori_ probability of an observation, under the best possible prior, is $2^(-("its compressed length"))$. To assign probability is to compress; to compress is to assign probability. There is no seam between them at the ideal limit. Let us prove the half of that identity we can prove cheaply.

#theorem("Universal prior is at least 2 to the minus K(x)")[
For every string $x$, the universal prior satisfies $M(x) >= 2^(-K(x))$, where $K(x)$ is the length of the shortest program that prints $x$. Equivalently $-log_2 M(x) <= K(x)$: a compressible string is _at least_ that probable under the universal prior.
]

#proof[
By definition $K(x)$ is the length of _some_ shortest program $p^*$ with $U(p^*) = x$, so $abs(p^*) = K(x)$. The sum defining $M(x)$ ranges over _all_ programs that output something beginning with $x$, and $p^*$ is one of them. Every term in the sum is non-negative, so dropping all terms but the single term for $p^*$ can only decrease the sum:
$ M(x) = sum_(p: space U(p) = x...) 2^(-abs(p)) >= 2^(-abs(p^*)) = 2^(-K(x)). $
Taking $-log_2$ of both sides (a decreasing function, so the inequality flips) gives $-log_2 M(x) <= K(x)$. The matching upper bound $-log_2 M(x) >= K(x) - c$ for a constant $c$ is harder (it is the Coding Theorem of algorithmic information theory, Levin 1974), but the easy direction already shows the universal prior _rewards compressibility_: the shorter a string's program, the more probable it is. $qed$
]

And the predictive optimality is a genuine theorem, not a hope.

#theorem("Solomonoff's prediction bound (informal)")[
Suppose the data is actually generated by _any_ computable probability distribution $mu$. Then Solomonoff's predictor $M$ converges to $mu$'s predictions, and the _total_ extra prediction error it ever makes (summed over the entire infinite future) is bounded by a constant times $K(mu)$, the Kolmogorov complexity of the true source. The better-structured (more compressible) the true world, the fewer mistakes the universal learner ever makes, added up over all time.
]

#proof[
We sketch the engine; the full result is Solomonoff's (1978) and Hutter's. The squared error between $M$'s prediction and the truth $mu$, summed over all time steps, is controlled by the *KL divergence* $D_("KL")(mu parallel M)$ accumulated along the sequence (Chapter 20). Because $M$ is a Bayesian mixture that _includes_ $mu$ among its hypotheses with prior weight at least $2^(-K(mu))$ (the true source has _some_ shortest program, of length $K(mu)$), a standard mixture argument shows the total accumulated KL divergence (equivalently, the total excess code length $M$ ever pays over the true distribution) is at most $K(mu) ln 2$ bits. A finite bit-debt spread over infinitely many predictions forces the per-step error to zero. So $M$ learns _any_ computable environment, paying a one-time price equal to that environment's compressed description length. $qed$
]

#example[
Imagine three "worlds," each an endless bitstream. World 1 is "always output $1$": its rulebook is a one-line program, $K(mu_1)$ a handful of bits. World 2 is "output the binary digits of $pi$," a short but slightly longer program, $K(mu_2)$ a few hundred bits. World 3 is a fair-coin stream: _no_ rulebook shorter than the data itself, $K(mu_3) approx infinity$ per unit length. Solomonoff's bound says the universal learner's _total lifetime surprise_ is $approx K(mu) ln 2$ bits. So in World 1 it is fooled only a handful of times before predicting $1$ forever; in World 2 it pays a few hundred bits of tuition, then nails every digit of $pi$; in World 3 it never stops being surprised, because there was nothing to learn. The tuition bill _is_ the compressed size of the laws: cheap worlds are cheap to learn, incompressible worlds are unlearnable. That is the thesis, stated as a price in bits.
]

Look at what the bound _is_: the lifetime cost of learning the world equals the _compressed size of the world's rulebook_. A simple universe (short rulebook, small $K(mu)$) is cheap to learn; a complicated one is dear; an incompressible one cannot be learned at all because it has no rulebook. Intelligence-as-prediction and compression are not merely correlated here. They are the _same quantity_, $K(mu)$, appearing once as "how hard to learn" and once as "how hard to compress."

#pitfall[
Everything about Solomonoff induction is perfect except that you can never run it. $M(x)$ sums over _all_ programs, including ones that loop forever; deciding which ones halt is the *halting problem* (Chapter 22), which is uncomputable. So $M$ is not an algorithm. It is a mathematical object, a north star. Every real learner and every real compressor in this book is a _computable approximation_ to $M$: PPM\*, context mixing, a transformer, each restricts the program class and the search to something tractable, trading the universal guarantee for the ability to actually finish. Do not mistake the ideal for a method you can call.
]

#aside[
There is a hierarchy of approximations worth knowing. *Levin search* (Leonid Levin, 1973) makes Solomonoff computable by penalizing programs for _running time_ as well as length (replacing $2^(-abs(p))$ with a weighting that also charges for computation), which sidesteps the halting problem at the cost of universality over slow programs. The *speed prior* (Schmidhuber, 2002) formalizes this. These are the theoretical ancestors of the practical observation that real compressors must finish in your lifetime, so they can only ever approximate $K(x)$ "from above." Every compressed file you have ever made is an _upper bound_ on the true Kolmogorov complexity of its contents.
]

== AIXI: from compressing data to acting intelligently

Solomonoff induction is a perfect _predictor_. But intelligence, most people would say, is not only about predicting: it is about _acting_ to get what you want. In 2000, Marcus Hutter (then at IDSIA, later DeepMind and the Australian National University) took the final step, bolting Solomonoff's universal predictor onto sequential decision theory to define *AIXI*, an agent that is, in a precise mathematical sense, _the most intelligent agent that can be mathematically defined._

The construction is, once you have Solomonoff, almost inevitable.

#algo(
  name: "AIXI", year: "2000",
  authors: "Marcus Hutter",
  aim: "Define a single agent that behaves optimally in *every* computable environment, by combining universal prediction (Solomonoff) with reward-maximizing decision theory.",
  complexity: "Incomputable (worse than Solomonoff induction; even time-bounded variants are astronomically expensive).",
  strengths: "Provably Pareto-optimal across all computable environments; a precise mathematical definition of 'general intelligence'; needs no problem-specific tuning.",
  weaknesses: "Uncomputable; assumes a known reward signal and a clean agent/environment split; ignores the cost of its own thinking; reward can be 'gamed' (wireheading).",
  superseded: "Computable approximations: AIXItl, MC-AIXI-CTW (2011), and, in spirit, modern model-based reinforcement learning and world models.",
)[
  AIXI maintains Solomonoff's universal mixture $M$ as its _model of the world_. At each step it does what any rational agent should: it considers each action it could take, uses $M$ to predict the future stream of observations and *rewards* that action would lead to (averaged over all computable environments, weighted by $2^(-"length")$), and picks the action that maximizes its expected total future reward. It is "Solomonoff induction in the loop": predict the world with the universal prior, then act to maximize reward given that prediction. The single mixture $xi$ does all the learning; the surrounding "$max$ over actions" does all the deciding.
]

#gomaths("Expected value and choosing the best action")[
*Expected value* (Chapter 10) is a weighted average of outcomes, each weighted by its probability, i.e. the "average payoff" of a gamble. If action $a$ leads to reward $10$ with probability $0.3$ and reward $0$ with probability $0.7$, its expected reward is $0.3 times 10 + 0.7 times 0 = 3$. A rational agent facing a choice computes the expected total future reward of each action and picks the largest: this is the "$max_a EE[...]$" that sits at the center of decision theory. AIXI does exactly this, except its expectation is taken over _all computable environments at once_, weighted by Solomonoff's universal prior. That is the only new ingredient: an ordinary reward-maximizer wearing a universal model of the world.
]

#definition("The AIXI optimality property")[
Hutter proved AIXI is *Pareto-optimal*: there is no other agent that does at least as well as AIXI in _every_ computable environment and strictly better in _some_. You cannot build an agent that beats AIXI everywhere without losing to it somewhere. In this exact sense AIXI is _the_ most intelligent agent definable, not by opinion, but by a theorem about the space of all agents. It is the formal incarnation of the idea that there is a single, environment-independent notion of "doing the smartest possible thing."
]

This is where the chapter's thesis reaches its summit. *The most intelligent possible agent has, as its beating heart, the best possible compressor.* Strip AIXI down and what remains is Solomonoff's universal prior, which we showed is nothing but $2^(-("compressed length"))$. Hutter's own framing, the *Hutter thesis*, states it baldly: _general intelligence and optimal compression are equivalent._ To build a perfect compressor is to build a perfect inductor is (plus a reward signal) to build a perfect agent. The Hutter Prize (Chapter 23, Chapter 36) exists precisely to operationalize this: Hutter put up €500,000 of his own conviction that pushing the compression of Wikipedia is _the same problem_ as pushing toward AGI.

#history[
Hutter introduced AIXI in the December 2000 technical report "Towards a Universal Theory of Artificial Intelligence based on Algorithmic Probability and Sequential Decision Theory" (arXiv cs/0012011), and developed it fully in his 2005 book _Universal Artificial Intelligence_. With his student Shane Legg (later a co-founder of DeepMind) he distilled the idea into a formal _definition_ of machine intelligence (Legg & Hutter, "Universal Intelligence," 2007): an agent's intelligence is its expected reward, averaged over all computable environments weighted by their simplicity (i.e. by $2^(-"complexity")$). Smarter agents do well in more, and simpler, worlds. That this definition came from the same people who then helped build modern AI labs is not a coincidence; the compression-as-intelligence thesis was load-bearing in the intellectual founding of the field that produced today's LLMs.
]

#aside[
AIXI is uncomputable, but it has runnable descendants. *MC-AIXI-CTW* (Veness, Ng, Hutter, Uther, Silver, 2011) approximates AIXI with Monte-Carlo tree search for the planning and a *Context Tree Weighting* compressor (a real, fast, provably good sequence predictor straight out of Volume II's coding theory) for the universal model. With no game-specific code, the same agent learned to play Pac-Man, TicTacToe, and other games from reward alone. It is a literal demonstration of the thesis: a _compression algorithm_ (CTW), wrapped in a planner, _is_ a general-purpose learning agent. The compressor was doing the intelligence.
]

== The honest counterarguments

A book that only sold you the thesis would be propaganda. The "compression is intelligence" idea is powerful and partly true, but by 2026 the careful consensus is that it is a _necessary signature_ of intelligence, not a complete _definition_ of it. Here are the strongest objections, stated as fairly as I can make them, because the mark of understanding a beautiful idea is knowing exactly where it stops.

=== The model is not free (the accounting objection)

The most concrete objection is bookkeeping, and Chapter 23 already flagged it. When a 70-billion-parameter model compresses a gigabyte of Wikipedia to a few hundred megabytes, the model itself is _hundreds of gigabytes_. The honest, "two-part" MDL accounting (the same $L(M) + L(D|M)$ we proved you cannot cheat) says the _total_ description is the model plus the residual, and by that measure the giant model has not compressed a single file at all; it has merely _moved_ the bits into its weights. The win is real only when the model is _amortized_ over a corpus far larger than the model. This is not a footnote; it is the MDL theorem of this very chapter, applied honestly, biting the hand that fed it. A compressor that ships a 140 GB dictionary to shrink a 1 GB file is, in the only accounting that matters, an _expander_.

#misconception[An LLM that achieves 1 bit/byte on Wikipedia has compressed Wikipedia further than any classical codec, full stop.][Only if you _do not charge for the model_. The fair, MDL-honest figure adds the model's own description length to the file's. By that measure a frozen 70B model is vastly larger than the text it codes; it "wins" only when its cost is spread over a corpus much bigger than the model. The clean information-theoretic accounting (which is the thesis's own home turf) both _powers_ the LLM-compression results and _caps_ how much they can claim. The two-part code giveth and the two-part code taketh away.]

=== Intelligence may exceed prediction (the scope objection)

Even granting perfect compression, is _prediction_ really all of intelligence? Three doubts recur:

- *Action in a non-stationary, embedded world.* AIXI assumes a clean split between agent and environment, a fixed reward signal, and unlimited thinking time. Real intelligence is _embedded_: the agent is part of the world it models, its computations cost energy and time, and it can even modify itself. The moment you charge for the cost of thinking, the elegant optimality of AIXI evaporates, and the theory of _bounded_ rationality is far messier and far from settled.
- *Goals, not just predictions.* A perfect predictor of human text is not thereby _wise_, _moral_, or _aligned_. Solomonoff predicts; it does not choose what is worth predicting. AIXI patches this with an external reward, but where does the reward come from, and what stops the agent from "wireheading," i.e. seizing control of its own reward signal rather than doing the intended task? Compression is silent on what we _ought_ to want.
- *Reasoning that does not look like next-token statistics.* Some capabilities (multi-step logical deduction, genuine out-of-distribution generalization, planning over long horizons) may not be well captured by "make the next symbol less surprising on a fixed corpus." A system can have low bits-per-character and still fail a novel reasoning task; the map from compression to capability, while strong, is not the identity.

=== What the evidence actually shows

So is the thesis empirically confirmed or not? The most striking data point, from 2024, deserves to be quoted precisely. Yuzhen Huang, Jinghan Zhang, Zifei Shan, and Junxian He ("Compression Represents Intelligence Linearly," COLM 2024) evaluated 31 publicly available LLMs across 12 benchmarks spanning knowledge, coding, and mathematical reasoning. They found that a model's _compression efficiency_ on held-out text (its bits-per-character) correlates with its benchmark "intelligence" at a Pearson correlation of about $-0.95$, _nearly a straight line_. Better compressors are, very reliably, more capable models.

#gomaths("Reading a correlation coefficient")[
The *Pearson correlation* $r$ is a single number in $[-1, +1]$ measuring how close two quantities are to lying on a straight line (Chapter 10 introduced covariance; this is its normalized cousin). $r = +1$ means a perfect rising line, $r = -1$ a perfect falling line, $r = 0$ no linear relationship at all. Here $r approx -0.95$ is _falling_ (more bits-per-character = worse compression = lower intelligence, so the line slopes down) and _very nearly perfect_: about as tight a real-world relationship between two independently measured things as the social sciences ever see. It is strong evidence that compression _tracks_ capability. It does not, by itself, prove they are the _same thing_, because correlation is not identity.
]

That $-0.95$ is the strongest empirical wind in the thesis's sails. But read it carefully. It says _intelligence implies compression_: a model smart enough to ace benchmarks is, reliably, also a good compressor (which makes complete sense, since acing a language benchmark _requires_ modelling language well, and modelling language well _is_ compressing it). It does _not_ establish the converse, that _all_ intelligence _reduces_ to compression. The correlation is consistent with compression being a necessary signature of capability without being its full definition. The careful 2025--2026 reading is exactly this asymmetry: every capable model we have is a good compressor, but "good compressor" and "intelligent agent" are not yet shown to be the same set.

#keyidea[
*Where the thesis is strongest, and where it stops.* It is strongest as a statement about _learning and prediction_: to model a source well is, provably (MDL, PAC-Bayes, Solomonoff), to compress it well, and the best possible predictor _is_ the best possible compressor. It is on shakier ground as a complete theory of _agency and intelligence_: action under bounded resources, the origin of goals, alignment, and reasoning that escapes next-symbol statistics all live partly outside the compression frame. The equation "intelligence = compression" is a profound _identity at the level of induction_ and an _open conjecture_ at the level of full intelligence.
]

#fig([The thesis as a chain of equivalences, each link proved earlier in the book, and the place where the chain becomes a conjecture rather than a theorem.],
  cetz.canvas({
    import cetz.draw: *
    let mkbox(x, y, w, t) = {
      rect((x, y), (x + w, y + 0.9), radius: 3pt, stroke: rgb("#0b5394") + 0.8pt, fill: rgb("#eef4fb"))
      content((x + w/2, y + 0.45), box(width: calc.max(0.1, w - 0.4) * 1cm, inset: 2pt, align(center, text(size: 8pt)[#t])))
    }
    mkbox(0, 0, 3.0, "compress well")
    mkbox(3.6, 0, 3.0, "predict well")
    mkbox(7.2, 0, 3.4, "learn / generalize")
    line((3.0, 0.45), (3.6, 0.45), mark: (end: ">"), stroke: rgb("#0b6e4f") + 1pt)
    line((6.6, 0.45), (7.2, 0.45), mark: (end: ">"), stroke: rgb("#0b6e4f") + 1pt)
    content((3.3, 1.05), text(size: 6.5pt, fill: rgb("#0b6e4f"))[proved])
    content((6.9, 1.05), text(size: 6.5pt, fill: rgb("#0b6e4f"))[proved])
    mkbox(7.2, -1.6, 3.4, "act intelligently")
    line((8.9, 0), (8.9, -0.7), mark: (end: ">"), stroke: rgb("#9a2617") + 1pt)
    content((10.7, -0.35), text(size: 6.5pt, fill: rgb("#9a2617"))[conjecture])
  })
)

== A computational reading of the thesis

To make the philosophy concrete, here is the thesis as a few lines of Python you can run in your head. We have a compressor (any function turning data into shorter data and back) and we use _its output length_ as a measure of how much it "understands" each string. The shorter it compresses something, the more structure it has found.

#gopython("Functions, len(), and using bytes as data")[
A Python *function* is a named recipe: `def f(x): ...` defines it, `f(3)` runs it. `len(b)` gives the number of items in a sequence: for a `bytes` object (Chapter 17, a sequence of raw byte values $0$--$255$) it is the number of bytes. We compare two compressors by the length of what they emit. `zlib` is Python's built-in DEFLATE compressor (Chapter 30); we use it here only as a stand-in for "some real, computable approximation to the ideal compressor." The smaller `len(compress(data))`, the more regularity the compressor found, which, by this chapter's thesis, is the more it "understood."
]

```python
import os, zlib

def understanding_in_bits(data: bytes) -> int:
    """How many bits a real (approximate) compressor needs.
    Lower = more structure found = more 'understood'."""
    return len(zlib.compress(data, level=9)) * 8  # bytes -> bits

# Three strings, very different structure:
regular = b"3141592653589793" * 64        # a repeating, regular pattern
english = (b"Information theory teaches that to compress a message well is "
           b"to predict it well, and a model that predicts well has surely "
           b"learned the structure hidden inside the data it was shown.")
noise   = os.urandom(1024)                 # genuine random bytes, no pattern

for name, d in [("regular", regular), ("english", english), ("noise", noise)]:
    raw = len(d) * 8
    got = understanding_in_bits(d)
    print(f"{name:8s}: raw={raw:5d} bits  compressed={got:5d} bits  "
          f"structure found={100*(1-got/raw):4.0f}%")
```

Running this prints something close to (the `noise` line varies run to run):

```
regular : raw= 8192 bits  compressed=  264 bits  structure found=  97%
english : raw= 1456 bits  compressed=  992 bits  structure found=  32%
noise   : raw= 8192 bits  compressed= 8280 bits  structure found=  -1%
```

The regular string is almost entirely understood (compressed to near nothing); the English sentence is partly understood (zlib finds about a third of its structure, real, but a small model leaves most on the table); the random bytes are _not_ understood at all: compressing them actually makes them slightly bigger, the tell-tale sign of a string with no pattern this compressor can grasp. Swap `zlib` for a 70-billion-parameter language model and the English number would plummet; the bigger model "understands" English far more deeply, while the regular and noise numbers would barely move. *The compression ratio is a thermometer for understanding.* That single idea, made rigorous by MDL, certified by PAC-Bayes, idealized by Solomonoff, and turned into an agent by AIXI, is the whole of this chapter.

We can go one step further and show Solomonoff's _mixing_ idea in miniature: keep two rival models of a bitstream, weight each by how well it has predicted so far (its accumulated $2^(-"code length")$), and let the better predictor automatically take over. The total bits spent is the cross-entropy of the mixture (the compressed size), and watching it fall _is_ watching the learner learn.

#gopython("Loops accumulating a running total")[
A `for` loop (Chapter 15) walks through a sequence; a running variable accumulates a total as it goes (here, total bits and each model's weight). `math.log2(p)` is the base-2 logarithm (Chapter 7), so `-math.log2(p)` is the code length of an outcome of probability `p`. We keep two model weights, renormalize them each step (Bayesian updating, Chapter 9), and charge the _mixture's_ probability: exactly Solomonoff's weighted vote, shrunk from "all programs" to just two.
]

#pyrecall[A `lambda` (Chapter 16) is a one-line throwaway function; `lambda: 0.5` is the no-argument case, a function that takes nothing and always returns $0.5$, so `models["fair"]()` calls it and yields the constant $0.5$. We use it here only as a tidy way to bundle each model's "probability the next bit is a 1" behind a uniform `models[m]()` call.]

```python
import math

bits = b"\x01" * 40           # a very predictable stream: all ones
# Two rival models of P(next bit = 1):
models = {"fair": lambda: 0.5, "ones": lambda: 0.99}
w = {"fair": 0.5, "ones": 0.5}  # prior weights (Occam: start even)
total_bits = 0.0
for byte in bits:
    bit = byte & 1
    # Mixture prediction = weighted vote of the two models:
    p_one = sum(w[m] * models[m]() for m in w)
    p = p_one if bit == 1 else (1 - p_one)
    total_bits += -math.log2(p)         # bits the coder spends on this symbol
    # Bayesian update: reward whoever predicted this bit well
    for m in w:
        pm = models[m]() if bit == 1 else (1 - models[m]())
        w[m] *= pm
    z = sum(w.values())
    w = {m: w[m] / z for m in w}         # renormalize to sum to 1

print(f"total compressed size: {total_bits:.1f} bits for 40 bits raw")
print(f"final belief in 'ones' model: {w['ones']:.3f}")
```

This prints roughly `total compressed size: 1.6 bits for 40 bits raw` and `final belief in 'ones' model: 1.000`. The mixture started agnostic, watched the stream, _learned_ that the "ones" model predicts better, shifted almost all its weight onto it, and as a result compressed 40 raw bits into under 2, because after the very first symbol it was barely surprised at all. That falling bit-count is the learning curve and the compression curve at once. Scale "two models" up to "all computable programs" and you have Solomonoff induction; wrap a reward signal around it and you have AIXI. The toy and the ideal differ only in how many hypotheses they mix.

#scoreboard(caption: "Compression as a thermometer for 'understanding' (illustrative, this chapter's demo)",
  [Regular pattern], [264 bits], [3%], [near-perfectly understood: a short program exists],
  [English text (zlib)], [992 bits], [68%], [some structure found, but a small model],
  [English text (70B LLM)], [≈300 bits], [≈21%], [far more understood: Chapter 62],
  [Random bytes], [8280 bits], [101%], [no pattern grasped, incompressible to this model],
)

#takeaways((
  [*To learn is to compress.* Finding structure in data (the essence of learning and intelligence) is the same act as describing the data more briefly. Recognizing $pi$ collapses a thousand digits into three lines; the compression _is_ the understanding.],
  [*Generalization equals compression, provably.* The Occam / PAC-Bayes bound shows a hypothesis's true (future) error is at most its training error plus a penalty $prop sqrt(L(h)\/n)$. A shorter description literally buys a tighter guarantee on unseen data.],
  [*MDL cannot be fooled by noise.* Choosing the model that minimizes $L(M) + L(D|M)$ gives free regularization: noise is incompressible, so a model that fits noise cannot pay for itself in bits. Over-fitting becomes structurally unprofitable.],
  [*Solomonoff is the ideal learner.* Its universal prior assigns each string probability $approx 2^(-K(x))$: to predict optimally is to weight hypotheses by $2^(-"length")$. Its lifetime error is bounded by the _compressed size_ of the true world, $K(mu)$. It is perfect and uncomputable; every real learner approximates it.],
  [*AIXI is the ideal agent.* Solomonoff induction plus reward-maximizing decision theory yields the provably Pareto-optimal agent. Its core is the universal compressor: the Hutter thesis says optimal compression and general intelligence are equivalent.],
  [*Be honest about the limits.* The thesis is a _theorem_ for induction and prediction, but a _conjecture_ for full agency. Model-size accounting (the two-part code bites back), bounded resources, the origin of goals, and reasoning beyond next-symbol statistics all sit partly outside the compression frame. Compression is a _necessary signature_ of intelligence; whether it is the _whole_ of it remains open.],
))

== Exercises

#exercise("61.1", 1)[
In your own words, explain why "the student who memorized the answer key" has _not_ compressed anything, while "the student who learned the rule" has. Relate each to the term $L(M)$ in the two-part code, and say which student would do better on a fresh exam and why, in the language of this chapter.
]
#solution("61.1")[
The memorizer's "model" _is_ the answer key: a description as long as the data it explains, so $L(M) approx L(D)$ and the total description $L(M) + L(D|M)$ is no shorter than storing the raw data, zero compression. The rule-learner's model is one short rule, $L(M) << L(D)$, and once you know the rule the data's residual surprise $L(D|M)$ is small too, so the total is far shorter: real compression. On a fresh exam, the rule-learner wins, because (by the Occam/PAC-Bayes bound) a short hypothesis that fits the practice data has a small generalization penalty $prop sqrt(L(M)\/n)$, whereas the memorizer's enormous $L(M)$ gives a vacuous guarantee. It has no reason to work on questions it has not memorized. Compressing and generalizing are the same success here.
]

#exercise("61.2", 1)[
A friend says: "Random noise is the _most_ informative data there is, because every bit is a surprise, so a truly intelligent system should compress noise the best." Identify the confusion and correct it using the chapter's vocabulary (incompressibility, $K(x)$, what "understanding" means here).
]
#solution("61.2")[
The friend confuses _surprise_ with _understanding_. True random noise is maximally surprising bit-by-bit, yes, but that is exactly why it is _incompressible_: it has no shorter description, $K(x) approx abs(x)$, no program prints it but a verbatim copy. "Understanding," in this chapter, means finding a _short description_, i.e. compressing. There is nothing to understand in noise, no rule, no pattern, so an intelligent system compresses it the _worst_ (cannot beat storing it raw), not the best. A system that claimed to compress noise would either be lying or have detected hidden structure, meaning it was not truly random after all. Maximum surprise and maximum understanding are opposites here, not the same thing.
]

#exercise("61.3", 2)[
Using the worked MDL example as a template: you observe $n = 200$ bits containing $150$ ones and $50$ zeros. Compare the null model $M_0$ (fair coin, $0$ bits to state) against a biased model $M_1$ with $p = 0.75$ that costs $8$ bits to state. Compute both total description lengths $L(M) + L(D|M)$ and say which MDL prefers. (Use $log_2 0.75 approx -0.415$, $log_2 0.25 approx -2$.)
]
#solution("61.3")[
*Null $M_0$:* costs $0$ bits to state; codes each of $200$ bits at $1$ bit, so $L(D|M_0) = 200$ bits. Total $= 0 + 200 = 200$ bits.

*Biased $M_1$ ($p = 0.75$ for a $1$):* costs $8$ bits to state. The residual is $-150 log_2(0.75) - 50 log_2(0.25) = 150(0.415) + 50(2) = 62.25 + 100 = 162.25$ bits. Total $= 8 + 162.25 = 170.25$ bits.

MDL prefers $M_1$ ($170.25 < 200$). The bias is worth declaring: stating the model costs $8$ bits but saves about $38$ bits of residual, a net win of $approx 30$ bits, and that net saving _is_ the compression achieved by "understanding" the coin is biased.
]

#exercise("61.4", 2)[
In the Occam/PAC-Bayes bound $e(h) <= hat(e)(h) + sqrt((L(h) ln 2 + ln(1\/delta))\/(2n))$, suppose $hat(e)(h) = 0$ (perfect fit on the training set), $delta = 0.05$, and $n = 10000$ examples. Compute the bound on the true error for (a) a short hypothesis with $L(h) = 50$ bits and (b) a long one with $L(h) = 5000$ bits. What does the comparison say about preferring short hypotheses? (Use $ln 2 approx 0.693$, $ln(20) approx 3.0$.)
]
#solution("61.4")[
The penalty is $sqrt((L(h)(0.693) + 3.0)\/20000)$.

(a) $L(h) = 50$: numerator $= 50(0.693) + 3.0 = 34.65 + 3.0 = 37.65$; penalty $= sqrt(37.65\/20000) = sqrt(0.00188) approx 0.043$. So $e(h) <= 0 + 0.043 = 4.3%$, a strong guarantee.

(b) $L(h) = 5000$: numerator $= 5000(0.693) + 3.0 = 3465 + 3.0 = 3468$; penalty $= sqrt(3468\/20000) = sqrt(0.173) approx 0.416$. So $e(h) <= 41.6%$, nearly useless.

Both hypotheses fit the training data perfectly, yet the short one is _certified_ to err at most $4.3%$ on new data while the long one's guarantee is vacuous. The bound makes "prefer the shorter description" a quantitative, provable preference: compression buys generalization.
]

#exercise("61.5", 2)[
Explain, in the language of Solomonoff's prediction bound, why a "simple" universe is easier for an ideal learner than a "complicated" one. What single quantity governs the total lifetime prediction error, and what is its compression interpretation?
]
#solution("61.5")[
Solomonoff's bound says the total prediction error ever accumulated, when the true source is a computable distribution $mu$, is at most a constant times $K(mu)$: the Kolmogorov complexity of the true source, i.e. the length of the shortest program that _is_ the source's rulebook. A "simple" universe has a short rulebook (small $K(mu)$): the learner pays a small one-time bit-debt and then predicts almost perfectly forever. A "complicated" universe has a long rulebook (large $K(mu)$): more total error before convergence. An incompressible universe ($K(mu) approx$ its length) cannot be learned at all. The single governing quantity, $K(mu)$, is _exactly the compressed size of the world's laws_, so "easy to learn" and "easy to compress" are the same number, which is the chapter's thesis at the ideal limit.
]

#exercise("61.6", 2)[
AIXI is described as combining a universal predictor with reward-maximizing decision theory. Write one or two sentences each on: (a) which part of AIXI does the "learning," (b) which part does the "acting," and (c) why removing the reward signal would turn AIXI back into Solomonoff induction.
]
#solution("61.6")[
(a) *Learning:* Solomonoff's universal mixture $M$ (often written $xi$), the Bayesian average over all computable environments weighted by $2^(-"length")$, models the world and updates as observations arrive. (b) *Acting:* the "$max$ over actions" of expected total future reward: ordinary sequential decision theory, picking whichever action $M$ predicts will yield the most reward. (c) Without a reward signal there is nothing to maximize, so the decision layer has no job; all that remains is $M$ predicting the next observation, which is precisely Solomonoff induction. AIXI is therefore "Solomonoff induction plus a goal," and the compressor ($M$) is the part doing the intelligence in both.
]

#exercise("61.7", 3)[
The "accounting objection" says a 70B-parameter LLM that compresses a 1 GB file to 100 MB has not really compressed anything. Using the two-part MDL code $L(M) + L(D|M)$, state the honest total description length, explain when (and only when) the LLM genuinely compresses, and connect this to the MDL "cannot be fooled" theorem proved in this chapter.
]
#solution("61.7")[
The honest, MDL-fair size is $L(M) + L(D|M)$: the _model's own_ description length plus the coded residual. For a 70B model at, say, fp16, $L(M) approx 140$ GB, so $L(M) + L(D|M) approx 140 "GB" + 100 "MB" >> 1 "GB"$, far _larger_ than the raw file. By the two-part accounting the model has not compressed this file; it has moved bits into its weights (an "expander," not a compressor, for a single file). It genuinely compresses only when amortized over a corpus far larger than the model: if the same frozen model codes, say, $10$ TB of text, the $140$ GB is a one-time cost spread thin and the _per-corpus_ total beats classical codecs. This is the MDL "cannot be fooled" theorem applied honestly: a model can only win in total bits if its structure plus residual beats raw storage, so a memorizer (or an under-amortized giant) pays for itself in $L(M)$ and cannot profit. The thesis's own bookkeeping both powers and caps the LLM-compression claims.
]

#exercise("61.8", 3)[
Steel-man and then critique the Hutter thesis. (a) Give the strongest version of the argument that "optimal compression = general intelligence," citing the chapter's theorems. (b) Then give the two strongest honest objections, distinguishing "intelligence implies compression" from "compression implies intelligence." Use the $r approx -0.95$ result correctly.
]
#solution("61.8")[
(a) *Steel-man:* By the cross-entropy identity (Chapter 23), modelling a source is coding it; by MDL and the Occam/PAC-Bayes bound, the shortest description that fits provably generalizes best; by Solomonoff's bound, the optimal predictor's lifetime error is the compressed size $K(mu)$ of the true world; by AIXI's Pareto-optimality theorem, the optimal _agent_ is that predictor plus reward-seeking. So the best compressor is the best inductor is (with a goal) the best agent: intelligence and compression coincide at the ideal limit. The empirical $r approx -0.95$ between LLMs' bits-per-character and benchmark scores (Huang et al., 2024) is strong real-world corroboration.

(b) *Objections:* (1) *Direction.* The $-0.95$ correlation shows _intelligence implies compression_ (a capable model necessarily models/compresses language well) but not the converse that _all_ intelligence _reduces_ to compression; correlation is not identity. (2) *Scope and accounting.* AIXI assumes unbounded computation, a clean agent/environment split, and a given reward: drop any and optimality breaks; bounded rationality, the origin of goals, alignment/wireheading, and reasoning that does not reduce to next-symbol statistics sit outside the frame; and the two-part code shows the headline LLM "wins" only after amortizing a model that dwarfs the data. The fair verdict: compression is a _necessary signature_ of capable prediction and learning, proven; it is an _open conjecture_ as a complete account of agency and intelligence.
]

== Further reading

- Ray Solomonoff (1964), _A Formal Theory of Inductive Inference, Parts I & II_, Information and Control 7: the origin of algorithmic probability and universal prediction. #link("http://world.std.com/~rjs/1964pt1.pdf")[canonical link]
- Jorma Rissanen (1978), _Modeling by Shortest Data Description_, Automatica 14: the founding MDL paper.
- Anselm Blumer, Andrzej Ehrenfeucht, David Haussler, Manfred Warmuth (1987), _Occam's Razor_, Information Processing Letters 24: the first compression-to-generalization bound.
- Marcus Hutter (2000), _Towards a Universal Theory of Artificial Intelligence based on Algorithmic Probability and Sequential Decision Theory_: the AIXI technical report. #link("https://arxiv.org/abs/cs/0012011")[arXiv:cs/0012011]
- Marcus Hutter (2005), _Universal Artificial Intelligence: Sequential Decisions Based on Algorithmic Probability_, Springer: the full AIXI book.
- Shane Legg and Marcus Hutter (2007), _Universal Intelligence: A Definition of Machine Intelligence_, Minds and Machines 17(4). #link("https://arxiv.org/abs/0712.3329")[arXiv:0712.3329]
- Joel Veness, Kee Siong Ng, Marcus Hutter, William Uther, David Silver (2011), _A Monte-Carlo AIXI Approximation_, JAIR 40: MC-AIXI-CTW, a runnable AIXI built on a compressor.
- Wenda Zhou et al. (2019), _Non-Vacuous Generalization Bounds at the ImageNet Scale: A PAC-Bayesian Compression Approach_. #link("https://arxiv.org/abs/1804.05862")[arXiv:1804.05862]
- Sanae Lotfi et al. (2022), _PAC-Bayes Compression Bounds So Tight That They Can Explain Generalization_, NeurIPS. #link("https://arxiv.org/abs/2211.13609")[arXiv:2211.13609]
- Yuzhen Huang, Jinghan Zhang, Zifei Shan, Junxian He (2024), _Compression Represents Intelligence Linearly_, COLM 2024. #link("https://arxiv.org/abs/2404.09937")[arXiv:2404.09937]
- The Hutter Prize for Lossless Compression of Human Knowledge. #link("http://prize.hutter1.net/")[prize.hutter1.net]

#bridge[
We have argued, with theorems and with honest doubts, that to compress is to predict is to learn, and that the ideal compressor is, in a precise sense, the ideal agent's core model. That was the _theory_. The next chapter makes it _run_: we take a real autoregressive language model, read off its $P("next token")$, feed those probabilities to the arithmetic coder you built back in Chapter 26, and watch a chatbot turn into a state-of-the-art lossless compressor: `tinyzip`'s `llmzip` demo. The slogan of this chapter becomes the working code of the next.
]
