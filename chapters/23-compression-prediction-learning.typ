#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// local helper: a worked numeric example box (self-contained to this chapter)
#let example(body) = block(width: 100%, breakable: true,
  inset: (x: 10pt, y: 8pt), radius: 4pt, fill: rgb("#fbf7ef"),
  stroke: (left: 3pt + rgb("#783f04")), above: 9pt, below: 9pt)[
  #text(weight: "bold", fill: rgb("#783f04"))[Worked example.] #h(3pt) #body
]

= Compression = Prediction = Learning

#epigraph[Probability theory is nothing but common sense reduced to calculation. A good compressor is nothing but a good bookmaker who never gets to take the other side of the bet.][after Pierre-Simon Laplace]

Here is a parlour trick that should not work, and does. Take a chatbot — a large language model, the kind that writes emails and bad poetry. It has never been told what an audio file is. It has never heard a sound. Now feed it a recording of a person reading a book aloud, one byte at a time, and ask it only the question it was built to answer: _given everything so far, what byte comes next?_ Turn each of its guesses into bits with the arithmetic coder you will meet in Chapter 26, and stack those bits into a file. When DeepMind actually ran this experiment in 2023, the resulting file was *16.4%* of the original size. FLAC — a codec engineered by audio specialists over years, the subject of Chapter 50 — managed only *30.3%*. A text model, knowing nothing of sound, beat the audio experts at their own game by nearly two to one.

That is not a fluke, and it is not magic. It is the single most important idea in this book finally made visible. This chapter is the hinge. Behind us lie twenty-two chapters of mathematics, history, and information theory. Ahead lie the neural codecs and the LLM compressors of Volumes IV and V. The thing that connects the two halves — the thesis the whole modern field is built on — is an equation you already have all the pieces for:

$ "to compress well" = "to predict well" = "to have learned the structure." $

Not three similar activities. Up to a gap we can measure to the bit, _the same activity, written three ways._ Once you see it, the leap from a Huffman tree to GPT stops being a leap. It becomes one idea pursued with ever-better models.

#recap[
In *Chapter 18* we defined the entropy $H(X) = -sum_i p_i log_2 p_i$ as a source's true unavoidable cost, and self-information $-log_2 p$ as the surprise of one symbol. In *Chapter 19* the Source Coding Theorem proved entropy is a hard _floor_: no lossless code beats it on average. In *Chapter 20* we met the *Kullback–Leibler divergence* $D_("KL")(P parallel Q)$ as the "distance" from one distribution to another, always $>= 0$. In *Chapter 22* we met *Kolmogorov complexity* $K(x)$ — the length of the shortest program that prints $x$ — the ideal, uncomputable compressed size. This chapter fuses all four into one machine: a predictor _is_ a compressor, its training loss _is_ a code length, and its modelling error _is_ wasted bits, measured in exactly the same units.
]

#objectives((
  [State and explain the *cross-entropy = expected code length* identity, and prove that your wasted bits equal $D_("KL")(P parallel Q)$ exactly.],
  [Explain *universal coding*: how to compress a source whose statistics you do not know in advance, and why the excess cost (redundancy) shrinks as the message grows.],
  [Apply the *Krichevsky–Trofimov* "add one-half" estimator and quote the famous $1/2 log_2 n$ price per parameter.],
  [State Rissanen's *Minimum Description Length (MDL)* principle, $L("model") + L("data" | "model")$, and use it to explain why over-fitting is self-penalising.],
  [Connect *Solomonoff induction* and Kolmogorov complexity to the practical compressors of this book as computable approximations to an uncomputable ideal.],
  [Read the modern evidence — the Hutter Prize and DeepMind's "Language Modeling Is Compression" — as a direct empirical test of the thesis.],
))

== The one identity that fuses coding and probability

Let us start where Chapter 19 left us, but turn the telescope around. There we asked: given a source, how short can a code be? Now we ask the reverse: given a *code*, what source does it secretly believe in?

Recall the bridge from entropy coding. An ideal lossless code spends $-log_2 p$ bits on a symbol of probability $p$. A symbol you expect (large $p$) is cheap; a rare one (small $p$) is dear. Chapter 26 will show that arithmetic coding achieves this *for any probabilities you hand it*, to within a fraction of a bit over a whole message — so we may pretend, with negligible error, that the cost is exactly $-log_2 p$ per symbol. That little formula is a two-way street, and it is the most important door in the book.

#keyidea[
*A probability model and a compressor are the same object, mechanically interchangeable.* Give me a model — a function $Q$ that assigns a probability $Q(x)$ to each possible next symbol $x$ — and I will build you a compressor that spends $-log_2 Q(x)$ bits on the symbol that actually occurs. Give me a compressor that spends $L(x)$ bits on symbol $x$, and I will read off the model it must believe: $Q(x) = 2^(-L(x))$. There is no daylight between "predicting $x$" and "coding $x$ cheaply." They are one act.
]

Walk through the door slowly, because everything else in the chapter is just consequences of it. Suppose your model assigns the next byte the probability $Q = 1/4$. The coder spends $-log_2 (1/4) = 2$ bits. Now suppose a smarter model — one that has noticed more structure — assigns that _same_ byte $Q = 1/2$. The coder spends $-log_2 (1/2) = 1$ bit. The smarter model saw the byte coming more clearly, so it paid less to record it. *Better prediction is literally fewer bits.* Not by analogy. By the formula.

#gomaths("Logarithms as bit-counters — a 60-second refresher")[
A logarithm undoes an exponent (Chapter 7). $log_2 8 = 3$ because $2^3 = 8$. The intuition you need here: $-log_2 p$ is "how many bits to name one outcome among $1\/p$ equally-likely ones." If $p = 1\/8$, there are 8 equally-likely possibilities, and 3 bits ($2^3 = 8$) name them. The minus sign is just because probabilities are $<= 1$, so their logs are negative, and code lengths must be positive. Three facts we lean on:
- $log_2 (1) = 0$ (a certain symbol costs $0$ bits — you knew it already),
- $log_2 (a b) = log_2 a + log_2 b$ (logs turn the multiplication of independent probabilities into the _addition_ of bits — this is why total code length adds up),
- $-log_2 p$ grows without bound as $p -> 0$ (a near-impossible event, if it happens, costs a fortune to record).
]

=== Cross-entropy: what you actually pay when your model is wrong

In the real world your model $Q$ is never perfect. The data is _truly_ generated by some distribution $P$ that you do not know, while your compressor codes _as if_ the distribution were $Q$. What is the bill?

The data symbol $x$ shows up with its true frequency $P(x)$, and each time it does you are charged $-log_2 Q(x)$ bits by your model. The average cost per symbol is therefore a weighted sum: take each possible symbol, weight its charge by how often it _really_ occurs, and add up. That average has a name.

#gomaths("Expectation — the weighted average")[
Suppose a quantity takes value $v_1$ a fraction $p_1$ of the time, $v_2$ a fraction $p_2$ of the time, and so on. Its long-run average — its *expectation*, written $EE[v]$ — is not the plain average $(v_1 + v_2 + ...)\/n$ but the _weighted_ one: $ EE[v] = sum_x p_x v_x = p_1 v_1 + p_2 v_2 + ... $ Each value is weighted by how often it occurs. _Tiny example:_ a game pays \$10 with probability $0.2$ and \$0 with probability $0.8$. Its expected payout is $0.2 times 10 + 0.8 times 0 = \$2$ per play — even though you _never_ actually win \$2 on a single play. Cross-entropy is exactly this kind of weighted average, with $v_x = -log_2 Q(x)$ (the bits charged for symbol $x$) and weights $p_x = P(x)$ (how often $x$ really happens). We met expectation properly in Chapter 10; here it is the cost of a code.
]

#definition("Cross-entropy")[
The *cross-entropy* of the true distribution $P$ relative to the model $Q$ is the average number of bits per symbol you pay when reality is $P$ but you code using $Q$:
$ H(P, Q) = -sum_x P(x) log_2 Q(x). $
When $Q = P$ exactly, this collapses to the ordinary entropy $H(P)$ of Chapter 18 — you pay the unavoidable floor and not one bit more.
]

Now for the result that the entire field stands on. We can split the cross-entropy into two clean pieces: the part you could never have avoided, and the part that is purely your fault.

#theorem("Cross-entropy decomposition")[
For any true distribution $P$ and any model $Q$ over the same symbols,
$ H(P, Q) = H(P) + D_("KL")(P parallel Q), $
where $H(P) = -sum_x P(x) log_2 P(x)$ is the source entropy and $D_("KL")(P parallel Q) = sum_x P(x) log_2 (P(x) \/ Q(x)) >= 0$ is the Kullback–Leibler divergence of Chapter 20.
]

#proof[
Start from the definition and multiply inside the logarithm by $P(x)\/P(x) = 1$, which changes nothing:
$ H(P,Q) = -sum_x P(x) log_2 Q(x) = -sum_x P(x) log_2 (Q(x) (P(x))/(P(x))). $
Split the logarithm of a product into a sum of logarithms (the second fact from the refresher box):
$ = -sum_x P(x) [log_2 P(x) + log_2 (Q(x))/(P(x))] = underbrace(-sum_x P(x) log_2 P(x), H(P)) + underbrace(sum_x P(x) log_2 (P(x))/(Q(x)), D_("KL")(P parallel Q)). $
The first sum is exactly $H(P)$. The second is exactly $D_("KL")(P parallel Q)$. We proved in Chapter 20 (Gibbs' inequality) that $D_("KL") >= 0$, with equality only when $Q = P$ everywhere. $square$
]

Read the theorem as a bill with two line items.

#keyidea[
*Your wasted bits are your modelling error, in the same units.* The best you could ever do is $H(P)$, the source's true entropy — Shannon's floor, which no code beats. Every bit you spend _above_ that floor is exactly $D_("KL")(P parallel Q)$: a precise, non-negative measure of how wrong your model is. Improving the model means shrinking the KL term and nothing else; the floor $H(P)$ does not move. Compression research _is_ the project of driving $D_("KL")(P parallel Q) -> 0$.
]

#example[
*A loaded coin you mis-model.* A source emits `H` with true probability $P("H") = 0.9$ and `T` with $P("T") = 0.1$. Its true entropy is
$ H(P) = -0.9 log_2 0.9 - 0.1 log_2 0.1 approx 0.137 + 0.332 = 0.469 "bits/flip". $
Suppose your model wrongly believes the coin is fair: $Q("H") = Q("T") = 0.5$. Then you pay $-log_2 0.5 = 1$ bit for _every_ flip, so $H(P,Q) = 1.000$ bit/flip. The waste is
$ D_("KL")(P parallel Q) = 0.9 log_2 (0.9)/(0.5) + 0.1 log_2 (0.1)/(0.5) approx 0.763 - 0.232 = 0.531 "bits/flip", $
and indeed $0.469 + 0.531 = 1.000$. The numbers close to the bit. You are burning $0.531$ bits per flip — over half a bit — purely because your model has not _learned_ that the coin is loaded. Learn the true bias and that waste vanishes.
]

=== The punchline for machine learning

Now watch the second door open by itself. When a modern machine-learning model trains — a language model, an image network, anything — it minimises a quantity called the *log loss* or *cross-entropy loss*: for each symbol the data actually shows, it adds up $-log_2 Q(x)$ and tries to make that total small. But $-log_2 Q(x)$ _is the code length_ you would pay to transmit that symbol using the model. They are the same number.

#keyidea[
*Training a predictor to minimise log loss is, with no reinterpretation whatsoever, training a compressor to minimise file size.* A language model fitting next-token cross-entropy on a corpus is being optimised to make the compressed corpus as small as possible. "Predict the next symbol well" and "compress the stream short" are not analogous goals — they are the _identical_ objective, written in two notations. The loss curve a researcher watches descend during training _is_ a compression curve.
]

#misconception[
"Compression is about cleverly packing bits; prediction is about machine learning. They share some maths but are really different jobs."
][
They are the same job. Any compressor implies a predictor ($Q(x) = 2^(-L(x))$) and any predictor implies a compressor ($L(x) = -log_2 Q(x)$). The only reason they _look_ different is historical: one community measured success in bytes, the other in loss. The cross-entropy identity shows the scoreboards are the same scoreboard in different units. This is why a model trained only to chat can compress audio: chatting well and compressing well are one skill.
]

#checkpoint[
Your model assigns the next character probability $Q = 0.01$, but the character was actually very common. Did you over-pay or under-pay, and by roughly how much versus a model that assigned it $0.5$?
][
You over-paid badly. At $Q = 0.01$ the cost is $-log_2 0.01 approx 6.64$ bits; at $Q = 0.5$ it is $1$ bit. A confident-but-wrong prediction is punished savagely — about $5.6$ extra bits for this one character. This asymmetry (cheap when right, ruinous when overconfident and wrong) is exactly why good compressors hedge.
]

=== The gambler's view: a compressor is a bookmaker

There is a third face of the same identity, and it is the one that makes the whole thing feel _inevitable_ rather than merely true. Imagine you are betting on the next symbol. Before each symbol arrives you spread \$1 of stake across the possible outcomes in proportion to your model $Q$: you put $Q(x)$ dollars on outcome $x$. The bookmaker pays _fair odds_ — if you bet $Q(x)$ on $x$ and $x$ occurs, your stake is multiplied by $1\/Q(x)$. Reinvest everything, every round. This is the *Kelly gambling* setup, and it is secretly identical to compression.

#gomaths("Multiplying gains and the doubling rate")[
When you reinvest, gains _multiply_ rather than add. If your wealth is multiplied by factors $g_1, g_2, ..., g_n$ over $n$ rounds, your final wealth is the _product_ $g_1 g_2 ... g_n$, written $product_(t=1)^n g_t$. Products are awkward, so we take logarithms, which turn the product into a _sum_: $log_2 (product_t g_t) = sum_t log_2 g_t$. The average of $log_2 g_t$ per round is called the *doubling rate* $W$ — the number of times per round your money (on average) doubles. _Tiny example:_ if your wealth multiplies by $4$, then by $1$, then by $4$, the product is $16 = 2^4$, and over $3$ rounds the doubling rate is $4\/3 approx 1.33$ doublings/round. The product/sum bridge here is the very same logarithm trick that turns multiplied probabilities into added bits.
]

In this betting game, the symbol $x$ multiplies your wealth by $1\/Q(x)$. By the doubling-rate box, your log-wealth grows by $log_2 (1\/Q(x)) = -log_2 Q(x)$ each round — _which is exactly the code length the compressor spends on $x$._ The bits a compressor _spends_ are the log-dollars a gambler with the same model _wins_. Compressing the data short and getting rich betting on it are the identical skill.

#example[
*Betting your way to the entropy floor.* The 90/10 coin again, and a gambler who has learned the true bias, betting $Q("H") = 0.9$, $Q("T") = 0.1$. On a head (90% of rounds) wealth multiplies by $1\/0.9 approx 1.111$; on a tail by $1\/0.1 = 10$. The average log-growth per flip is $0.9 log_2 (1.111) + 0.1 log_2 (10) approx 0.9(0.152) + 0.1(3.322) = 0.137 + 0.332 = 0.469$ doublings/flip. That number is _exactly_ the entropy $H(P) = 0.469$ — the gambler's optimal growth rate equals the compressor's optimal code length, to the last decimal. A gambler who mis-modelled the coin as fair would grow at only $1 - H(P,Q) = 1 - 1.0 = 0$... but that is a story for the exercises. The point stands: model error costs the gambler exactly the bits it costs the coder.
]

#theorem("Gambling and coding grow at the same rate")[
A gambler who reinvests at fair odds using model $Q$ achieves an expected doubling rate of $W(Q) = log_2 |cal(A)| - H(P, Q)$ on an alphabet $cal(A)$, while a coder using the same $Q$ spends $H(P,Q)$ bits per symbol. Maximising wealth-growth and minimising code length are the _same_ optimisation, both solved by $Q = P$.
]

#proof[
Per round, wealth multiplies by $1\/Q(x)$ when $x$ occurs (fair odds against a uniform book of size $|cal(A)|$ contribute a constant $|cal(A)|$ factor; absorb it). The expected log-growth is $EE_P [log_2 (1\/Q(x))] = -sum_x P(x) log_2 Q(x) $ adjusted by the constant, $= log_2|cal(A)| - H(P,Q)$. This is _largest_ exactly when $H(P,Q)$ is _smallest_; and by the no-model-beats-the-truth theorem proven later, $H(P,Q)$ is minimised uniquely at $Q = P$, giving doubling rate $log_2|cal(A)| - H(P)$. So the wealth-maximising bet and the bit-minimising code are one and the same, both equal to the truth. $square$
]

#aside[
This gambling–coding duality is due to John Kelly Jr. (1956), a colleague of Shannon's at Bell Labs, who realised that Shannon's channel capacity was also the maximum rate at which a gambler with inside information could grow money. Information theory, compression, and getting rich at the racetrack are three views of one staircase of logarithms. We will not pursue the betting thread further, but keep it in mind: whenever you see $-log_2 Q$, you may read it as "bits paid" _or_ "log-dollars won" — your choice.
]

== Universal coding: compressing without knowing the source

The identity has a catch it quietly assumed, and we must face it honestly. To pay only $H(P)$ — to drive the KL waste to zero — you would need the _true_ distribution $P$. You never have it. A photograph, an English novel, a genome, a log file: each comes from a source whose statistics nobody handed you in advance. So a real compressor faces a sharper problem than "code optimally for a known $P$." It must do nearly as well as the best code _in some family_, no matter which member of that family actually produced the data. This is the problem of *universal coding*, and its solution is the seed from which every adaptive compressor in this book grows.

#definition("Universal code")[
A code is *universal* for a class of sources if, for _every_ source in the class, its average cost per symbol approaches that source's entropy $H(P)$ as the message length $n -> infinity$. The gap between what you spent and the ideal $n dot H(P)$ is called the *redundancy*. A universal code drives the _per-symbol_ redundancy to zero without being told which source it faces.
]

The trick is *adaptation*, and it is beautifully simple. Process the stream left to right. At each position, predict the next symbol using only the statistics of what you have already seen. Code that symbol with your current prediction. Update your counts. Repeat. Early on you predict badly and overpay; but every symbol teaches you a little, your model creeps toward the truth, and the per-symbol overpayment shrinks. The redundancy is the tuition you pay to _learn the source while compressing it_ — and the theory says the tuition, spread over a long message, goes to zero.

#note[
This is exactly the structure of the adaptive coders you will build later: adaptive Huffman (Chapter 24), the adaptive arithmetic coder (Chapter 26), PPM and context mixing (Chapter 33), and the context-mixing champions (Chapter 34). They differ only in _how_ they predict the next symbol from the past. The universal-coding theory in this section is the promise that such "predict, code, update" loops can be near-optimal. Everything after this is engineering on that promise.
]

=== Laplace, Krichevsky–Trofimov, and the price of a parameter

Make it concrete with the simplest possible learner. The source emits bits, `0` or `1`, with some fixed but unknown probability of a `1`. You have seen $n$ bits so far, of which $k$ were `1`. What probability should you assign to the _next_ bit being `1`?

The naïve answer — "use the frequency $k\/n$" — is a disaster. Suppose you have seen ten `0`s and no `1`s. Frequency says $Q(1) = 0\/10 = 0$. Then if a `1` _does_ appear, the coder must spend $-log_2 0 = infinity$ bits. One surprise and your file is infinitely large. A predictor must never assign probability exactly zero to anything that can happen. So we _smooth_: pretend we saw a few imaginary symbols of each kind before the data started.

#definition("Add-β smoothing (Laplace / KT)")[
After observing $k$ ones in $n$ bits, predict the next bit is a `1` with probability
$ Q(1) = (k + beta)/(n + 2 beta). $
The constant $beta > 0$ is the imaginary head-start given to every symbol. *Laplace's rule* (1812) uses $beta = 1$ (add-one smoothing). The *Krichevsky–Trofimov (KT) estimator* (1981) uses $beta = 1\/2$ — the "add one-half" rule — which is provably the best choice for minimising worst-case redundancy.
]

#history[
The add-one rule is Pierre-Simon Laplace's *rule of succession* from 1812: having seen the sun rise $n$ times, the probability it rises tomorrow is $(n+1)\/(n+2)$ — never quite $1$, because certainty is never earned from finite data. Raphail Krichevsky and Victor Trofimov sharpened the constant to $1\/2$ in 1981 and proved it optimal for universal coding. The same $beta = 1\/2$ reappears as the *Jeffreys prior* in Bayesian statistics — three communities, one number, because it is the same idea about learning from counts.
]

#example[
*The add-one-half learner in action.* The source is a biased bit-source. We have seen the prefix `1 1 0 1`. Using KT ($beta = 1\/2$), predict and code each bit in turn, starting from no data ($k = 0, n = 0$):
- Bit 1 is `1`: predicted $Q(1) = (0 + 0.5)\/(0 + 1) = 0.5$. Cost $-log_2 0.5 = 1.00$ bit. Update: $k=1, n=1$.
- Bit 2 is `1`: predicted $Q(1) = (1 + 0.5)\/(1 + 1) = 0.75$. Cost $-log_2 0.75 approx 0.42$ bit. Update: $k=2, n=2$.
- Bit 3 is `0`: predicted $Q(0) = 1 - (2 + 0.5)\/(2 + 1) = 1 - 0.833 = 0.167$. Cost $-log_2 0.167 approx 2.58$ bits. Update: $k=2, n=3$.
- Bit 4 is `1`: predicted $Q(1) = (2 + 0.5)\/(3 + 1) = 0.625$. Cost $-log_2 0.625 approx 0.68$ bit.
Total: $1.00 + 0.42 + 2.58 + 0.68 = 4.68$ bits for 4 bits. We are over the raw 4 bits because the source is short and the lone `0` surprised us — but on a long run of a strongly biased source, the per-bit cost converges toward the source's entropy. That convergence _is_ universality.
]

The headline result of universal coding puts a price tag on learning itself.

#theorem("KT redundancy bound (informal)")[
For an unknown source with $k$ free parameters, coded adaptively over $n$ symbols with the KT estimator, the total redundancy above the ideal $n dot H(P)$ grows like
$ k/2 log_2 n + O(1) "bits". $
That is, learning each parameter from data costs about $1/2 log_2 n$ extra bits over the whole message — and no universal scheme can do asymptotically better.
]

#keyidea[
*Learning is not free, and its price is exactly $1/2 log_2 n$ bits per parameter.* The number is tiny and grows only _logarithmically_ in the message length: over a megabyte ($n approx 10^6$), a parameter costs about $1/2 log_2 10^6 approx 10$ bits to learn — utterly negligible next to the millions of bits in the file. This is why adaptation works so well in practice: the tuition is real but cheap, and it is amortised over the whole stream. Remember the number $1/2 log_2 n$ — it will reappear, unchanged, when Rissanen builds MDL, and again in statistics as the BIC penalty. The same number three times, because it is the same idea three times.
]

=== Coding a whole message: the chain rule of code length

So far we have priced one symbol at a time. A real message is a _sequence_, and the adaptive loop predicts each symbol from the ones before it. How do the per-symbol costs add up into a total file size? Through the simplest and most useful identity about sequences of probabilities: the *chain rule*.

#gomaths("The chain rule: a sequence's probability is a product of conditionals")[
The probability of a whole sequence $x_1 x_2 ... x_n$ can be peeled apart one symbol at a time. The probability of the pair $(x_1, x_2)$ is "probability of $x_1$" times "probability of $x_2$ _given_ $x_1$", written $P(x_2 | x_1)$ (the vertical bar reads "given"). Extending this all the way:
$ P(x_1 ... x_n) = P(x_1) dot P(x_2 | x_1) dot P(x_3 | x_1 x_2) dots = product_(t=1)^n P(x_t | x_1 ... x_(t-1)). $
We met conditional probability in Chapter 9. _Why it matters here:_ take $-log_2$ of both sides and the product becomes a sum (the log trick again):
$ -log_2 P(x_1 ... x_n) = sum_(t=1)^n -log_2 P(x_t | x_1 ... x_(t-1)). $
The total code length for the whole message is just the _sum_ of the per-symbol surprises, each one conditioned on everything seen so far. This is precisely what an adaptive "predict-then-code" loop computes.
]

#keyidea[
*An adaptive compressor that predicts each symbol from the past and codes it is, mechanically, assigning the whole message the probability $product_t Q(x_t | "past")$ and spending $-log_2$ of it in bits.* The "predict, code, update" loop and "multiply the conditional probabilities, take minus-log" are the same computation. A next-symbol predictor _is_ a whole-sequence model.
]

#example[
*Three symbols, one total.* A tiny adaptive model predicts a 3-symbol message and assigns, in turn, $Q(x_1) = 0.5$, then $Q(x_2 | x_1) = 0.25$, then $Q(x_3 | x_1 x_2) = 0.8$. The whole-message probability is $0.5 times 0.25 times 0.8 = 0.1$, and the total code length is $-log_2 0.1 approx 3.32$ bits — which equals the sum of the parts: $1 + 2 + 0.32 = 3.32$ bits. The product of probabilities and the sum of bit-costs agree, exactly as the chain rule promises. A real LLM does this for thousands of tokens; the arithmetic is identical, only longer.
]

=== tinyzip learns the source for itself

We can turn the "predict, code, update" loop into a few lines of Python and _watch_ the cross-entropy fall as the model learns. This is the smallest possible universal compressor: an adaptive bit-model that knows nothing at the start and tightens with every bit it sees. It also previews, in miniature, exactly what every adaptive coder in later chapters does.

#pyrecall[In Step 6 (Chapters 18–19) we started `tinyzip/model.py` — the project's home for "all things probabilistic" — with the `entropy(data) -> float` meter that reuses `utils.histogram` (Step 2, Chapter 16). We `import` nothing new here; we simply _add_ to the same `model.py`, because the whole point of the project is that each step builds on the last.]

#gopython("Functions, type hints, and the math module")[
A *function* packages a computation under a name. In Python 3.14 we annotate the inputs and output with *type hints* — `bits: list[int]` means "a list whose entries are integers", and `-> float` means "this function returns a decimal number". Hints are documentation the reader (and tools) can trust; Python does not enforce them at run time. `from math import log2` borrows the base-2 logarithm. A tiny example:
```python
from math import log2

def cost(p: float) -> float:        # bits to code a symbol of probability p
    return -log2(p)

print(cost(0.5))   # -> 1.0
print(cost(0.25))  # -> 2.0
```
The `for` loop walks a list item by item; `+=` adds-in-place; an f-string like `f"{x:.3f}"` prints `x` rounded to 3 decimals.
]

#project("Step 7 · model.AdaptiveBitModel — the Krichevsky–Trofimov predictor")[
This is canonical *Step 7* of the `tinyzip` build. We give `model.py` its first _learner_: an `AdaptiveBitModel` that models a stream of bits with the Krichevsky–Trofimov estimator — start with imaginary half-counts, predict, then after each real bit, update. This is the predictor that the adaptive arithmetic coder of Chapter 26 will plug in to actually emit bits; here we let it score its own cost in bits, which by the identity _is_ the cross-entropy of the model against the data. No probabilities are given to it; it learns them. Append to `tinyzip/model.py` (alongside Step 6's `entropy`):

```python
from math import log2


class AdaptiveBitModel:
    """A Krichevsky–Trofimov (add-0.5) predictor for a binary source.

    It is told nothing about the bias and learns it as it goes, so it
    is a universal compressor for a memoryless binary source. The same
    object drives the adaptive arithmetic coder of Chapter 26.
    """

    def __init__(self) -> None:
        self.n0: float = 0.5    # imaginary count of zeros seen so far
        self.n1: float = 0.5    # imaginary count of ones seen so far

    def p1(self) -> float:
        """Current prediction that the next bit is a 1."""
        return self.n1 / (self.n0 + self.n1)

    def update(self, bit: int) -> None:
        """Learn from the bit we just saw (bump its counter)."""
        if bit == 1:
            self.n1 += 1
        else:
            self.n0 += 1


def kt_codelength(bits: list[int]) -> float:
    """Total bits an `AdaptiveBitModel` spends coding `bits`."""
    model = AdaptiveBitModel()
    total = 0.0                         # bits emitted so far
    for b in bits:
        p1 = model.p1()                 # current prediction for "next bit is 1"
        p = p1 if b == 1 else 1 - p1
        total += -log2(p)               # pay the code length for this bit
        model.update(b)                 # learn from it
    return total
```

Now watch it learn a bias it was never told:

```python
>>> import random
>>> from tinyzip.model import kt_codelength
>>> random.seed(0)
>>> data = [1 if random.random() < 0.9 else 0 for _ in range(10_000)]
>>> bits_used = kt_codelength(data)
>>> print(f"{bits_used/len(data):.4f} bits/symbol")   # -> ~0.456
```

The true entropy of a 90/10 source is $H = 0.469$ bits/symbol (we computed it earlier). The model, told _nothing_, spends about $0.456$ bits/symbol on this particular 10,000-bit draw — essentially _at_ the Shannon floor (this sample happened to skew slightly above 90% ones, so its empirical entropy dips a touch below $0.469$). The redundancy — the gap between what it spends and the ideal for the bias it _eventually_ learns — is only the $1/2 log_2 n approx 11$ bits the theory predicts for one parameter, a vanishing $approx 0.001$ bits/symbol. It _learned the bias for free_, near the floor. Feed it the bit-expansion of any file and you have a real, if humble, universal compressor — and in Chapter 26 the very same `AdaptiveBitModel` becomes the brain of a working arithmetic coder.
]

#checkpoint[
In `AdaptiveBitModel.__init__`, why do we initialise `n0` and `n1` to `0.5` rather than `0`?
][
To avoid ever predicting probability $0$. With `n0 = n1 = 0` the first bit would have `p1 = 0/0` (undefined), and after seeing only ones, a zero would get probability $0$ and cost $-log_2 0 = infinity$ bits — an infinite file. The half-count is the KT smoothing that keeps every prediction strictly between $0$ and $1$.
]

The model above has just _one_ counter pair — it learns a single global bias. The leap to a _good_ compressor is to keep _many_ counter pairs, one for each "context" (each recent history), so the prediction depends on what just happened. That bookkeeping needs a data structure that maps a context to its counts.

#gopython("Dictionaries — mapping keys to values")[
A *dictionary* (`dict`) stores key→value pairs and looks a value up by its key in roughly constant time (Chapter 14's hash table). You write it with braces: `counts = {0: [0.5, 0.5], 1: [0.5, 0.5]}` maps the key `0` to a two-element list and the key `1` to another. Read with `counts[0]`, write with `counts[0][1] += 1`, test membership with `if k in counts`. A tiny example:
```python
ctx: dict[int, list[float]] = {0: [0.5, 0.5], 1: [0.5, 0.5]}
ctx[1][0] += 1                 # saw a 0 after a 1; bump that counter
print(ctx[1])                  # -> [1.5, 0.5]
```
The type hint `dict[int, list[float]]` reads "a dictionary whose keys are integers and whose values are lists of decimals". Dictionaries are how every context model in this book — order-$k$ adaptive coders, PPM and context mixing (Chapter 33), the context-mixing champions (Chapter 34) — remembers "what usually follows _this_ history".
]

== Rissanen's MDL: Occam's razor with a bit-meter

We now have a precise way to score _data_ given a model. But which model should we pick in the first place? A polynomial of degree 2 or degree 20? A "memory" model that predicts the next symbol from the last 1 symbol or the last 5 (an _order-1_ versus _order-5_ model, of the kind we just built)? Bigger models always fit the _seen_ data better — a degree-20 curve can thread every training point exactly — yet we feel in our bones that the wiggly degree-20 fit has "memorised noise" and will predict the _future_ badly. How do we make that intuition exact, without hand-tuned penalties or a held-out validation set?

In 1978, Jorma Rissanen, then at IBM, gave the answer in a paper with a quietly revolutionary title: *"Modeling by Shortest Data Description."* It coined the *Minimum Description Length* principle, and it is Occam's razor with a bit-meter bolted on.

#keyidea[
*The best model is the one that lets you describe the data in the fewest total bits — counting the cost of stating the model itself.* To send the data to a friend, you transmit two things: first the _model_ (the regularities you found), then the _residual_ (the data's leftover surprises once the model explains the rest). MDL says: minimise the sum.
]

#definition("Minimum Description Length (two-part code)")[
Among candidate models, choose the one minimising the total description length
$ L_"total" = underbrace(L("model"), "cost to state the hypothesis") + underbrace(L("data" | "model"), "cost of the residual"). $
The second term is the code length of the data _given_ the model — by our identity, $-log_2 Q("data")$. The first term is the cost of describing the model precisely enough that the receiver can decode.
]

This single sum resolves the over-fitting puzzle automatically, with no knob to turn.

#fig([The MDL trade-off. Too-simple models leave a large residual (under-fit); too-complex models cost too much to state and merely memorise noise (over-fit). The shortest _total_ description sits at the genuine regularity in the data.],
cetz.canvas({
  import cetz.draw: *
  // axes
  line((0,0),(8,0), mark: (end: ">"))
  line((0,0),(0,4.6), mark: (end: ">"))
  content((8.2,-0.1))[model complexity]
  content((0.1,4.9))[bits]
  // model cost: rising line
  line((0.4,0.4),(7.4,4.1), stroke: (paint: rgb("#0b5394"), dash: "dashed"))
  content((6.6,4.1))[#text(size: 8pt, fill: rgb("#0b5394"))[L(model)]]
  // residual cost: falling curve (approx)
  line((0.4,4.2),(1.6,2.6),(3.0,1.6),(5.0,0.9),(7.4,0.5),
       stroke: (paint: rgb("#9a2617"), dash: "dotted"))
  content((6.4,0.55))[#text(size: 8pt, fill: rgb("#9a2617"))[L(data|model)]]
  // total: U-shaped
  line((0.4,4.6),(1.6,3.1),(3.0,2.6),(4.2,2.9),(5.6,3.5),(7.4,4.4),
       stroke: (paint: rgb("#0b6e4f"), thickness: 1.4pt))
  content((2.4,3.4))[#text(size: 8pt, fill: rgb("#0b6e4f"))[total]]
  // optimum marker
  circle((3.0,2.6), radius: 0.08, fill: rgb("#0b6e4f"), stroke: none)
  line((3.0,0),(3.0,2.6), stroke: (paint: rgb("#0b6e4f"), dash: "loosely-dotted"))
  content((3.0,-0.35))[#text(size: 8pt)[best]]
}))

A model that is too _simple_ cannot capture the regularities, so the residual $L("data" | "model")$ blows up — it _under-fits_. A model that is too _complex_ costs a fortune to state, $L("model")$, and the bits it "saves" on the residual are just memorised noise — it _over-fits_. The minimum of the sum sits squarely on the genuine structure in the data. And here is the quiet miracle:

#keyidea[
*Over-fitting is self-penalising in the currency of bits.* Noise, by Chapter 22's definition, is _incompressible_: a model that "explains" random fluctuations cannot encode them any shorter than listing them outright, so the bits it spends stating those extra parameters are never repaid in the residual. MDL needs no arbitrary regularisation constant, no held-out set, no prior pulled from thin air. The bit is the universal currency, and the desire for short descriptions _is_ the desire to generalise.
]

#example[
*Fitting points with a polynomial, MDL-style.* You have 11 data points that lie roughly on a straight line, with small measurement jitter. A line (2 parameters: slope, intercept) leaves a modest residual. A degree-10 polynomial (11 parameters) threads all 11 points _exactly_ — residual zero! Naïve fitting prefers the polynomial. But MDL counts the cost of _stating_ 11 high-precision coefficients: at roughly $1/2 log_2 n$ bits per parameter (there is that number again), describing the wiggly model costs far more than the handful of bits the line leaves in its residual. MDL picks the line — and the line is what predicts the _next_ point well. The bit-meter encoded "don't trust a fit more complicated than the data warrants" without anyone telling it to.
]

#history[
Rissanen credited Solomonoff, Kolmogorov, and Chaitin (Chapter 22) for the underlying idea that description length is the right measure of a hypothesis, and the statistician Hirotugu Akaike for the model-selection spirit, but he developed MDL independently and gave it teeth. Through the 1980s and 1990s he refined the crude two-part code into *stochastic complexity* and the *normalized maximum likelihood* (NML) code — the provably best single code for a whole model class. Strikingly, the crude two-part form already recovers the $1/2 log n$-per-parameter penalty from universal coding, and the very same penalty appears in Gideon Schwarz's *Bayesian Information Criterion* (BIC, 1978, the same year). Three roads, one toll: $1/2 log_2 n$ per parameter.
]

=== Two ways to send the model — and why they meet

There is a subtlety worth airing, because it dissolves a common worry. The two-part code says "send the model, then the residual." But _which_ model, and how do you encode a continuous parameter like a probability $theta = 0.73$ in a finite number of bits? You cannot send infinite precision. The resolution is one of the prettiest results in the area: you don't have to send a model at all.

Instead of committing to a single best $theta$, average over _all_ of them, weighted by a *prior* — a starting belief, fixed before seeing any data, about how plausible each value of $theta$ is (the same "prior" that fed Bayes' rule back in Chapter 9).

#mathrecall[The $integral dots "d" theta$ sign is the *integral* — the "continuous cousin of the sum" we met in passing in *Chapter 11*. Where $sum_x$ adds up a contribution from each value in a _discrete_ list, $integral dots "d" theta$ adds up a contribution from every value of a _continuous_ knob $theta$ (here a probability that can be any real number in $[0,1]$). Read $integral f(theta) "d" theta$ as "sweep $theta$ across its whole range and total up $f(theta)$." Everything below works exactly as it would with a $sum$.]

This gives a *mixture code* (also called a Bayesian or marginal-likelihood code): assign the data the probability $ Q("data") = integral P("data" | theta) w(theta) "d" theta, $ where $w(theta)$ is a prior over the parameter. Its code length is $-log_2 Q("data")$. No parameter is ever transmitted — yet the receiver can decode, because both sides agree on the prior in advance. Remarkably, the mixture code's length comes out _almost identical_ to the best two-part code's, both equal to "fit the best $theta$, then pay $1/2 log_2 n$ per parameter," up to a small constant.

#theorem("Two-part and mixture codes agree (informal)")[
For a smooth $k$-parameter model class over $n$ symbols, both the best two-part code and the Bayesian mixture code assign the data a length of $ -log_2 P("data" | hat(theta)) + k/2 log_2 n + O(1) "bits", $ where $hat(theta)$ is the best-fitting parameter. The two recipes — "send a quantised model then the residual" and "average over all models" — reach the same length.
]

#proof[
_Sketch._ Discretise each parameter to a grid of spacing proportional to $1\/sqrt(n)$ — the natural scale at which $n$ samples can distinguish parameter values (finer is wasted precision; coarser loses fit). Each of the $k$ parameters then needs about $1/2 log_2 n$ bits to name its grid cell, costing $k/2 log_2 n$ bits for the model, plus $-log_2 P("data" | hat(theta))$ for the residual at the best grid point. The mixture code, expanded by Laplace's method around the peak of the likelihood, contributes a $sqrt((2pi)^k \/ det(n I))$ "width" factor whose logarithm is _also_ $-k/2 log_2 n + O(1)$, with opposite sign because it _credits_ the spread. The two bookkeepings meet at the same total. $square$
]

#keyidea[
*You never actually have to transmit a model.* A predictive coder that mixes over hypotheses — exactly what the KT estimator and Solomonoff induction do — pays the model cost _implicitly_, smeared across the stream as the $1/2 log_2 n$-per-parameter redundancy. This is why adaptive "predict, code, update" coders need no separate "header" describing the source: the learning cost is already baked into the bits. MDL's two-part picture and the adaptive predictor are the same code wearing different clothes.
]

#example[
*The implicit model tax, numerically.* Code a 1,000-bit sample from an unknown biased coin (one parameter, $k = 1$) two ways. _Two-part:_ first transmit the bias quantised to a $1\/sqrt(1000) approx 0.032$ grid — about $1/2 log_2 1000 approx 5$ bits — then the residual at that bias. _Mixture (KT):_ transmit nothing extra; just run the add-one-half predictor. Both land within a bit or two of each other and within about $5$ bits of the ideal $1000 dot H(P)$. The "$5$ bits" is the price of _not knowing_ the coin's bias in advance — the same $1/2 log_2 n$ we have now met for the third time. The model tax is real, small, and unavoidable, whichever way you choose to pay it.
]

== Solomonoff: the ideal predictor that compresses everything

Push MDL to its logical extreme and you reach the most beautiful — and most uncomputable — object in the whole theory. MDL asked us to pick the shortest description from some _chosen family_ of models. But why restrict to a family at all? What is the shortest description, full stop — over _every_ conceivable model, every program in every language?

Between 1960 and 1964, Ray Solomonoff asked exactly this: what is the _best possible_ prior over all data sequences, before you have seen anything? His answer, *algorithmic probability*, is the deepest justification of Occam's razor ever given. Consider every program that could run on a universal computer (Chapter 22's universal Turing machine) and happens to output your string $x$. Weight each such program by $2^(-"its length")$ — short programs count heavily, long ones barely at all — and sum. That total is the algorithmic probability of $x$.

#definition("Algorithmic probability and Solomonoff induction")[
The *algorithmic probability* of a string $x$ is $ P_M (x) = sum_(p : M(p) = x) 2^(-|p|), $ the sum over all programs $p$ that make the universal machine $M$ print $x$, weighted by program length $|p|$. *Solomonoff induction* predicts the next symbol by Bayesian updating with this prior — equivalently, by mixing the predictions of _all_ programs, each weighted by how short it is and how well it has fit the data so far.
]

Two threads from earlier chapters now braid together. The negative logarithm of algorithmic probability is essentially the *Kolmogorov complexity* $K(x)$ of Chapter 22 — the length of the _shortest_ program that prints $x$, because the shortest program dominates the sum. So $K(x)$ is the true, model-free, ultimate compressed size of an object: the floor beneath all floors. And Solomonoff induction is, in a precise theorem, the optimal universal predictor.

#theorem("Optimality of Solomonoff induction (informal)")[
For any computable source generating the data, the _total_ prediction error of Solomonoff induction — summed over the whole infinite future — is bounded by a constant times $K("source")$, the Kolmogorov complexity of the program that generates the data. No computable predictor can do essentially better on all computable sources.
]

#keyidea[
*The perfect compressor and the perfect learner are one object — and we can never build it.* Solomonoff induction compresses every computable source to its Kolmogorov complexity and predicts every computable source near-perfectly. It is the north star of both fields, simultaneously. The catch, proved in Chapter 22, is fatal in practice: $K(x)$ is *uncomputable* — no algorithm computes it in general (a corollary of the halting problem), and the sum over all programs cannot be evaluated. Solomonoff induction is an _ideal_, not a recipe.
]

#keyidea[
*Every real compressor and every real learning algorithm is a computable approximation to this one uncomputable optimum.* Huffman, LZ77, PPM, JPEG, a neural net, an LLM — each trades a slice of universality for tractability, replacing "mix over _all_ programs" with "use _this_ tractable model." The history of compression in the chapters ahead is the history of better and better approximations to Solomonoff's ideal. That is why the field has a single arc: everyone is climbing the same unreachable mountain.
]

#aside[
Marcus Hutter combined Solomonoff induction with sequential decision theory to define *AIXI* (2000), a single equation describing a theoretically optimal — and equally uncomputable — universal agent. We will sketch AIXI and the "compression as intelligence" thesis properly in Chapter 61. For now, hold the headline: the optimal _predictor_ and the optimal _agent_ both bottom out in the same algorithmic-probability prior.
]

== Why this is the hinge of the modern era

The equivalence in this chapter is not folklore or hand-waving. Since the 2000s it has become an explicit research programme — and even a cash _benchmark_.

#algo(
  name: "The compression–prediction–learning thesis",
  year: "1978–2024",
  authors: "Solomonoff; Rissanen; Hutter; Delétang et al.",
  aim: "Establish that lossless compression, sequence prediction, and learning are one task, and measure progress on it directly.",
  complexity: "Encoder/decoder cost dominated by the predictor; LLM coders run 10–100× slower and heavier than classical codecs.",
  strengths: "A single yardstick (bits) unifies coding, statistics, and machine learning; better predictors give better compression for free.",
  weaknesses: "The optimum (Solomonoff/Kolmogorov) is uncomputable; the best practical predictors are enormous and slow; model size can dwarf the file unless amortised.",
  superseded: "Not superseded — it is the organising principle of Volumes IV–V.",
)[
*The Hutter Prize.* Launched in 2006 by Marcus Hutter (since 2020 targeting `enwik9`, a 1 GB excerpt of English Wikipedia), the prize pays cash for compressing human knowledge _precisely because_ Hutter argues compression and intelligence are the same. As of June 2026 the record stands at *110,793,128 bytes* — about 110.8 MB, an 8.9× ratio — set by Kaido Orav and Byron Knoll's *fx2-cmix*, accepted in October 2024. The winning techniques read like a tour of this book: context mixing (Chapter 33) carried to the extreme by the cmix lineage (Chapter 34), NLP-driven preprocessing, and embeddings to reorder articles so similar text sits together.

*"Language Modeling Is Compression."* In 2023, Google DeepMind (Grégoire Delétang, Anian Ruoss, Joel Veness, Marcus Hutter, and colleagues; published at ICLR 2024) closed the loop empirically. Pairing a 70-billion-parameter *Chinchilla* language model with an arithmetic coder, they compressed:
- *LibriSpeech audio* to *16.4%* of raw size — beating FLAC's *30.3%* (Chapter 50);
- *ImageNet image patches* to *43.4%* — beating PNG's *58.5%* (Chapter 44).
A model trained only on text, with no notion of sound or pixels, out-compressed the specialist codecs — because, as this chapter proves, predicting the next byte well _is_ compressing well, whatever the bytes mean.
]

#pitfall[
The thesis says better prediction gives better _ratio_, not better _practicality_. DeepMind's "compressor" is 10–100× slower and heavier than gzip, and the 70B-parameter model is itself far larger than any single file it compresses — the win only counts if the model is amortised over an enormous corpus, or if the receiver already has the model. The identity is about the _bits_, not the _watts_. Volumes IV–V wrestle constantly with this gap between the theoretical ceiling and the engineering floor.
]

#misconception[
"DeepMind's result means LLMs are about to replace zip and JPEG."
][
No. It is a _proof of principle_ that prediction quality translates directly into compression ratio, exactly as the cross-entropy identity demands. For everyday use, the energy, latency, and model-size costs are prohibitive — gzip compresses a megabyte in milliseconds on a phone; a 70B model needs a datacentre GPU. The result reshapes how we _think_ about compression (as learning), not what runs in your browser tomorrow. Specialised neural codecs (Chapters 57–60) aim to capture some of the ratio at a fraction of the cost.
]

The conceptual verdict, though, is settled. A neural network minimising next-token log loss _is_ a universal coder hunting for the source's true distribution; its loss curve _is_ a compression curve; its generalisation _is_ the discovery of genuine, compressible structure. Everything in Volumes IV and V — learned image codecs, neural audio tokenizers, LLM compressors, "compression as intelligence" — is this chapter's one identity, finally given enough compute to bite.

It is worth pausing on how _old_ this idea is, to feel how patiently it waited for the machinery to catch up. Solomonoff sketched the perfect predictor in 1960, before there was a single useful neural network. Rissanen named MDL in 1978, when "training a model" meant fitting a handful of coefficients by hand. Krichevsky and Trofimov pinned the price of learning a parameter — $1/2 log_2 n$ bits — in 1981. None of them could run the experiment that would have made it visceral; the models were too weak and the computers too small. What changed between then and the parlour trick that opened this chapter was not the theory but the predictor: forty years of better models climbing the same mountain, until one of them could predict the next byte of _anything_ — text, audio, images — well enough that the bits it saved became impossible to ignore. The thesis was true the whole time. We only just built a model good enough to watch it work.

#scoreboard(caption: "the running 100 KB English-text sample, methods so far and the ceiling this chapter reveals",
  [Raw (no compression)], [100,000], [1.00×], [the baseline byte stream],
  [Static order-0 (Huffman-class)], [≈57,600], [1.74×], [model = global letter frequencies (Chapters 18, 24)],
  [Adaptive order-0 (KT + arithmetic)], [≈57,400], [1.74×], [learns the frequencies on the fly — this chapter's loop],
  [Order-3 context model], [≈40,000], [2.50×], [a _better predictor_ → fewer bits (preview of Chapter 33)],
  [LLM + arithmetic coding], [≈14,000], [7.1×], [a vastly better predictor (preview of Chapter 62)],
  [Kolmogorov $K(x)$], [unknowable], [—], [the uncomputable floor beneath all of the above],
)

The scoreboard tells the whole story of the book in one column of numbers: every improvement in ratio is an improvement in _prediction_, and the bottom row is the ideal we approach but can never reach.

== One more proof: why a correct model is unbeatable on average

Before the exercises, we tie a bow on the central claim with a short, self-contained theorem — the formal version of "you cannot beat the truth, on average."

#theorem("No model beats the true distribution, in expectation")[
Let the data be drawn from the true distribution $P$. Among all models $Q$, the expected per-symbol code length $H(P, Q)$ is minimised _uniquely_ by $Q = P$, where it equals $H(P)$.
]

#proof[
From the decomposition theorem, $H(P, Q) = H(P) + D_("KL")(P parallel Q)$. The term $H(P)$ does not depend on $Q$, so minimising $H(P,Q)$ over $Q$ is the same as minimising $D_("KL")(P parallel Q)$. By Gibbs' inequality (Chapter 20), $D_("KL")(P parallel Q) >= 0$ with equality if and only if $Q = P$. Hence $H(P,Q) >= H(P)$ always, with equality exactly when the model is the truth. $square$
]

This is the formal heart of the chapter: *the best possible predictor is the true distribution, and using it costs exactly the entropy — Shannon's floor — and not one bit more.* Every practical compressor is a struggle to approximate that unreachable, true $P$, and its excess cost over the floor is, to the bit, how far its model still is from reality.

#takeaways((
  [A probability model and a compressor are the _same object_: a model that assigns $Q(x)$ implies a code of length $-log_2 Q(x)$, and any code of length $L(x)$ implies the model $Q(x) = 2^(-L(x))$.],
  [*Cross-entropy = expected code length*: $H(P,Q) = H(P) + D_("KL")(P parallel Q)$. The entropy $H(P)$ is the unavoidable floor; the KL divergence is your wasted bits — your modelling error, in the same units.],
  [Minimising a machine-learning model's *log loss* is _identical_ to minimising the compressed size of its data. The loss curve is a compression curve.],
  [*Universal coding* compresses a source of unknown statistics by adapting — predict, code, update — and its redundancy per symbol vanishes as the message grows.],
  [The *Krichevsky–Trofimov* "add one-half" estimator learns a source's parameters at a price of about $1/2 log_2 n$ bits each — the same number that appears in MDL and in the BIC.],
  [*MDL* picks the model minimising $L("model") + L("data"|"model")$; over-fitting is self-penalising because noise is incompressible. No tuning constant needed.],
  [*Solomonoff induction* is the perfect, uncomputable predictor-compressor; $K(x)$ is the ultimate compressed size. Every real codec and learner is a computable approximation to it.],
  [The thesis is now empirical: the Hutter Prize (110.8 MB on `enwik9`, fx2-cmix, 2024) and DeepMind's "Language Modeling Is Compression" (2023) show better prediction directly buys better ratio.],
))

== Exercises

#exercise("23.1", 1)[
Your model assigns the next byte probability $Q = 1\/16$, but the byte turned out to be common. (a) How many bits did the coder spend on it? (b) A better model would have assigned it $Q = 1\/2$ — how many bits then? (c) How many bits were _wasted_ by the worse model on this one byte?
]
#solution("23.1")[
(a) $-log_2 (1\/16) = 4$ bits. (b) $-log_2 (1\/2) = 1$ bit. (c) $4 - 1 = 3$ wasted bits on this byte — the over-confident-and-wrong penalty. Over a long file, that per-symbol waste is the KL divergence between the two models against the true frequencies.
]

#exercise("23.2", 1)[
A source emits one of four symbols with true probabilities $P = (1\/2, 1\/4, 1\/8, 1\/8)$. (a) Compute its entropy $H(P)$. (b) You code it with a uniform model $Q = (1\/4, 1\/4, 1\/4, 1\/4)$. Compute the cross-entropy $H(P, Q)$. (c) Verify $H(P,Q) - H(P) = D_("KL")(P parallel Q)$.
]
#solution("23.2")[
(a) $H(P) = 1\/2 dot 1 + 1\/4 dot 2 + 1\/8 dot 3 + 1\/8 dot 3 = 0.5 + 0.5 + 0.375 + 0.375 = 1.75$ bits. (b) Under uniform $Q$, every symbol costs $-log_2 (1\/4) = 2$ bits, so $H(P,Q) = 2.00$ bits. (c) The waste is $2.00 - 1.75 = 0.25$ bits; directly, $D_("KL") = sum P log_2 (P\/Q) = 1\/2 log_2 2 + 1\/4 log_2 1 + 1\/8 log_2 (1\/2) + 1\/8 log_2 (1\/2) = 0.5 + 0 - 0.125 - 0.125 = 0.25$ bits. They match.
]

#exercise("23.3", 2)[
Run the KT estimator ($beta = 1\/2$) by hand on the bit string `0 0 0 1`. Starting from $n_0 = n_1 = 0.5$, give the predicted probability of each bit as it occurs and the total code length. Is the total above or below 4 bits, and why?
]
#solution("23.3")[
- Bit `0`: $Q(0) = 0.5\/1 = 0.5$, cost $1.00$. Update $n_0 = 1.5$.
- Bit `0`: $Q(0) = 1.5\/2 = 0.75$, cost $approx 0.415$. Update $n_0 = 2.5$.
- Bit `0`: $Q(0) = 2.5\/3 approx 0.833$, cost $approx 0.263$. Update $n_0 = 3.5$.
- Bit `1`: $Q(1) = 0.5\/4 = 0.125$, cost $3.00$. 
Total $approx 1.00 + 0.415 + 0.263 + 3.00 = 4.68$ bits — _above_ 4, because the lone `1` was a surprise to a model that had grown confident in `0`s. On a longer, consistently biased string the per-bit cost would fall well below 1.
]

#exercise("23.4", 2)[
Explain, using the two-part code, why a lookup table that simply _memorises_ a training set of random coin flips is a terrible model under MDL even though it predicts the training data perfectly. What does $L("model")$ look like, and what happens to total description length on _new_ data?
]
#solution("23.4")[
A memorising table has $L("data"|"model") = 0$ on the training set, but $L("model")$ must literally store every flip — so $L("model") approx$ the raw size of the data, and the _total_ $L("model") + L("data"|"model")$ is no smaller than just sending the raw flips. MDL therefore gives it no credit: it has found no _regularity_, only re-described the data. On new data the table predicts nothing useful (random flips have no structure to exploit), so it generalises no better than chance. This is the bit-currency statement of "memorisation is not learning."
]

#exercise("23.5", 2)[
A friend claims to have written a program that, for _every_ file, outputs a strictly smaller file from which the original can be recovered. Using the compression–prediction identity and counting, prove this is impossible. (Hint: think about what model such a compressor implies, and recall Chapter 8's pigeonhole/counting bound.)
]
#solution("23.5")[
A lossless compressor is an _injective_ map from files to codewords (different files must decode differently). There are $2^n$ files of length exactly $n$ bits but only $2^n - 1$ shorter codewords (lengths $0$ to $n-1$). By the pigeonhole principle (Chapter 8) the map cannot send all $2^n$ files to strictly shorter, distinct codewords — at least one file must stay the same length or grow. Equivalently, by Kraft (Chapter 19) the implied model $Q(x) = 2^(-L(x))$ would have to sum to more than $1$, which no probability distribution can. So no compressor shrinks _everything_; it can only shrink the _predictable_ files and must expand the rest.
]

#exercise("23.6", 2)[
The Krichevsky–Trofimov redundancy bound says learning $k$ parameters costs about $(k\/2) log_2 n$ extra bits over $n$ symbols. (a) For a single-parameter source ($k = 1$) over a 1 MB file ($n = 8 times 10^6$ bits), estimate the extra bits. (b) Express this as a per-bit overhead and comment on whether adaptation is "expensive."
]
#solution("23.6")[
(a) $(1\/2) log_2 (8 times 10^6) = (1\/2) dot 22.9 approx 11.5$ extra bits over the whole file. (b) Per bit that is $11.5 \/ (8 times 10^6) approx 1.4 times 10^(-6)$ bits — utterly negligible. Adaptation is essentially free: the logarithmic growth of the tuition means even billions of symbols cost only a few dozen bits per parameter to learn. This is the quantitative reason adaptive coders dominate practice.
]

#exercise("23.7", 3)[
Prove that for _any_ two distributions $P$ and $Q$ over the same finite alphabet, $H(P, Q) >= H(P)$, with equality iff $Q = P$. You may use the inequality $ln x <= x - 1$ for $x > 0$ (equality iff $x = 1$). (This re-proves Gibbs' inequality from scratch — the engine of the whole chapter.)
]
#solution("23.7")[
We show $D_("KL")(P parallel Q) = sum_x P(x) log_2 (P(x)\/Q(x)) >= 0$. Convert to natural logs (a positive constant factor $1\/ln 2$, which does not change the sign): consider $-D = sum_x P(x) ln (Q(x)\/P(x))$. Apply $ln x <= x - 1$ with $x = Q(x)\/P(x)$:
$ -D <= sum_x P(x) ((Q(x))/(P(x)) - 1) = sum_x Q(x) - sum_x P(x) = 1 - 1 = 0. $
So $-D <= 0$, i.e. $D >= 0$. Equality in $ln x <= x-1$ requires $x = 1$ for every term, i.e. $Q(x) = P(x)$ for all $x$. Since $H(P,Q) = H(P) + D\/ln 2 dot ln 2 = H(P) + D_("KL")$, we get $H(P,Q) >= H(P)$ with equality iff $Q = P$. $square$
]

#exercise("23.8", 3)[
Modify the `kt_codelength` function from Step 7 into a function `kt_order1(bits)` that conditions each prediction on the _previous_ bit (an order-1 model: keep one `AdaptiveBitModel`-style counter pair for "previous bit was 0" and another for "previous bit was 1"). Explain in one sentence, using this chapter's identity, why an order-1 model can never do _worse_ in expectation than the order-0 model on a source with memory — and when it does strictly better.
]
#solution("23.8")[
```python
from math import log2

def kt_order1(bits: list[int]) -> float:
    # one (n0, n1) counter pair per previous-bit context
    ctx = {0: [0.5, 0.5], 1: [0.5, 0.5]}
    prev = 0                      # assume a leading 0 as the initial context
    total = 0.0
    for b in bits:
        n0, n1 = ctx[prev]
        p1 = n1 / (n0 + n1)
        p = p1 if b == 1 else 1 - p1
        total += -log2(p)
        ctx[prev][b] += 1         # update the counter for this context
        prev = b
    return total
```
A conditional model can match the order-0 model exactly (if the two contexts converge to the same statistics), and beats it whenever the next bit genuinely depends on the previous one — because conditioning shrinks the true conditional entropy $H(X_t | X_(t-1)) <= H(X_t)$, and by the identity lower attainable entropy means a shorter code. It does _strictly_ better precisely when the source has memory, i.e. when adjacent bits are correlated; the saved bits equal the mutual information between consecutive symbols (Chapter 20).
]

== Further reading

- Rissanen, J. (1978). _Modeling by Shortest Data Description._ Automatica 14(5), 465–471. #link("https://doi.org/10.1016/0005-1098(78)90005-5")[doi:10.1016/0005-1098(78)90005-5] — the founding MDL paper.
- Grünwald, P. (2007). _The Minimum Description Length Principle._ MIT Press; and the gentler #link("https://arxiv.org/abs/math/0406077")[_A Tutorial Introduction to the MDL Principle_ (arXiv:math/0406077)].
- Solomonoff, R. J. (1964). _A Formal Theory of Inductive Inference, Parts I & II._ Information and Control 7. #link("http://world.std.com/~rjs/1964pt1.pdf")[canonical PDF] — the origin of algorithmic probability.
- Krichevsky, R. & Trofimov, V. (1981). _The Performance of Universal Encoding._ IEEE Transactions on Information Theory 27(2), 199–207 — the "add one-half" estimator and its redundancy bound.
- Delétang, G., Ruoss, A., Veness, J., Hutter, M., et al. (2024). _Language Modeling Is Compression._ ICLR 2024. #link("https://arxiv.org/abs/2309.10668")[arXiv:2309.10668] — the empirical closing of the loop.
- Hutter, M. (2006–). _The Hutter Prize for Lossless Compression of Human Knowledge._ #link("http://prize.hutter1.net/")[prize.hutter1.net] — compression as a benchmark for intelligence.
- Cover, T. M. & Thomas, J. A. (2006). _Elements of Information Theory_, 2nd ed., chapters on universal coding and Kolmogorov complexity — the standard graduate reference.

#bridge[
We have proven the thesis: to compress is to predict is to learn, and the wasted bits are the modelling error to the last decimal. But a thesis is not a codec. The next volume turns the identity into machinery. Chapter 24 builds the first _practical_ optimal coder — David Huffman's 1952 greedy tree, the algorithm that turns a fixed model into the shortest possible prefix code, and the first time the bytes really start to melt on our scoreboard. The chase for the true $P$ begins in earnest.
]
