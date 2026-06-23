## Foundations: Information Theory and What Compression Actually Is

Before any algorithm, there is a single question: *how small can a message possibly get?* The answer was given in one stroke in 1948, and almost everything in this guide is a story about chasing that limit, working around it, or pretending it doesn't apply.

### Shannon 1948 and the birth of the bit

In July and October 1948, Claude Shannon, a 32-year-old mathematician at Bell Labs, published "A Mathematical Theory of Communication" in two parts of the *Bell System Technical Journal*. It built on earlier quantitative work by Harry Nyquist (1924) and Ralph Hartley (1928), but Shannon's synthesis was a true founding act: it introduced the word **bit** (binary digit, a coinage he credited to John Tukey), modeled an information source as a **random process**, and proved exactly how much that process could be compressed.

Shannon's first move was to refuse to care about *meaning*. A message is just a sequence of symbols drawn from some probability distribution. The right way to measure information, he argued, is to measure **surprise**. If a symbol $x$ occurs with probability $p(x)$, its **self-information** (or **surprisal**) is

$$ i(x) = \log_2 \frac{1}{p(x)} = -\log_2 p(x) \quad \text{bits.}$$

A certain event ($p=1$) carries zero bits — telling you the sun rose is worthless. A one-in-a-million event carries about 20 bits. Averaging surprisal over the source gives the **entropy**:

$$ H(X) = \sum_x p(x)\,\log_2 \frac{1}{p(x)} = -\sum_x p(x)\log_2 p(x). $$

Entropy is maximized when the distribution is uniform (every symbol equally likely, nothing predictable) and is zero when one symbol is certain. It is, concretely, the *average number of yes/no questions* you'd need to pin down a symbol if you asked optimally.

### The source coding theorem: entropy is the floor

Shannon's **source coding theorem** (also called the noiseless coding theorem) makes entropy operational. It says: to encode symbols from a source $X$ losslessly, the average code length per symbol $\bar{L}$ obeys

$$ \bar{L} \ge H(X), $$

and you can get arbitrarily close to $H(X)$ by coding long enough blocks. So entropy is simultaneously a **lower bound** (you can never do better on average) and an **achievable target** (you can get as close as you like). This dual nature is the whole game. Every lossless compressor is, at heart, an attempt to spend $-\log_2 p(x)$ bits on each event $x$ — short codewords for likely things, long codewords for rare things.

This immediately defines **redundancy**: the gap between how many bits a representation actually uses and the entropy floor. English text stored as 8 bits per character is wildly redundant, because its true entropy is closer to ~1–1.5 bits per character (a figure Shannon himself estimated in 1951 by having humans guess the next letter). Compression is the systematic removal of that gap.

### What "beating entropy" does and doesn't mean

Newcomers constantly ask whether some clever codec "beats Shannon." It cannot — *for a fixed source model*. That caveat is the key. The bound $H(X)$ is defined relative to a probability model $p$. If your model is wrong, you pay a penalty exactly equal to the **Kullback–Leibler divergence** $D_{\mathrm{KL}}(p\,\|\,q)$ between the true distribution $p$ and your assumed $q$: coding with the wrong model costs $H(p) + D_{\mathrm{KL}}(p\|q)$ bits per symbol. So "beating" a compressor never means beating entropy; it means finding a *better model* — a $q$ closer to the real $p$, or exploiting structure (correlations between symbols) that a simpler model ignored. gzip and a 70-billion-parameter language model both ultimately emit bits at the $-\log_2 q(x)$ rate; they differ only in how good their $q$ is.

### Lossless vs. lossy: two different promises

Everything above concerns **lossless** compression: the decompressor reconstructs the input *bit-for-bit*. This is mandatory for text, executables, and archives, and it is the regime where entropy reigns.

**Lossy** compression makes a different bargain: it is allowed to discard information, returning an approximation rather than the original. JPEG images, MP3 audio, and H.264 video are lossy. The governing theory here is not the source coding theorem but **rate–distortion theory**, also from Shannon (developed in 1948 and formalized in his 1959 paper). It answers: given that I tolerate distortion $D$ (under some chosen error measure), what is the minimum bit rate $R(D)$? Lossy codecs win enormously precisely because they throw away what human eyes and ears can't perceive — perceptual redundancy, not just statistical redundancy. We will return to rate–distortion when we reach media codecs; for now, note that "lossless" and "lossy" are separate universes with separate fundamental limits.

### Kolmogorov complexity: the other definition of information

Shannon's entropy is about a *source* — a random process with a distribution. But what is the information content of a *single, fixed* object, like the specific string of digits of $\pi$? Independently, Ray Solomonoff (1960/1964, motivated by formalizing inductive inference), Andrey Kolmogorov (1965), and Gregory Chaitin (1966/1969) arrived at **algorithmic information theory**. The **Kolmogorov complexity** $K(x)$ of a string $x$ is the length of the *shortest program* (on a fixed universal Turing machine) that outputs $x$ and halts.

This is profound. A billion digits of $\pi$ have enormous Shannon entropy if you treat them as random, but tiny Kolmogorov complexity — a few lines of code generate them. $K(x)$ is the ultimate, absolute notion of "the compressed size" of an individual object: its shortest possible description. The **invariance theorem** shows $K$ depends on the choice of machine only up to an additive constant, so it's well-defined asymptotically.

The catch is fatal in practice: **Kolmogorov complexity is uncomputable.** No algorithm can take an arbitrary $x$ and return $K(x)$; this follows from the undecidability of the halting problem (you can't generally know whether a candidate short program halts). Chaitin sharpened this with his constant $\Omega$, the halting probability — a specific, perfectly definable real number that is provably uncomputable. So the perfect compressor exists as a mathematical object but can never be built. Every real compressor is a *computable approximation* to this unreachable ideal, and the entire field is the study of good, tractable approximations.

### The unifying mental model: compression = prediction

Tie the threads together and a single idea emerges, the one the rest of this guide rests on: **lossless compression is exactly equivalent to probabilistic prediction.** If you have a model that assigns probability $q(x_{n}\mid x_1\dots x_{n-1})$ to the next symbol, an **arithmetic coder** (which we'll cover in depth later) will encode the actual sequence in essentially $\sum -\log_2 q(x_n\mid\dots)$ bits — and conversely, any compressor implicitly *is* a predictor, since its codeword lengths define a distribution $q(x)=2^{-\ell(x)}$. Better prediction is better compression, and vice versa, with mathematical exactness.

This equivalence is not a metaphor; it has become a working tool. DeepMind and Meta's "Language Modeling Is Compression" (Delétang et al., ICLR 2024) drove the point home: a large language model wrapped in an arithmetic coder is a state-of-the-art *general* compressor. Chinchilla 70B compressed ImageNet image patches to 43.4% (beating PNG's 58.5%) and LibriSpeech audio to 16.4% (beating FLAC's 30.3%) — despite being trained only on text — because it is simply a very good next-symbol predictor. Subsequent work (e.g. through 2025–2026) uses compression rate as a clean, gameable-resistant metric for model quality. The slogan to carry forward: **to compress well is to understand the data's structure, and to understand structure is to predict it.** Everything else is engineering toward that limit.