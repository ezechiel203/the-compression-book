#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// local helper: a lightly-set worked-example block (uses only built-ins)
#let worked(body) = block(width: 100%, breakable: true, inset: (x: 10pt, y: 8pt),
  radius: 4pt, fill: rgb("#fbf7ef"), stroke: (left: 3pt + rgb("#783f04")),
  above: 9pt, below: 9pt)[#body]

= Kolmogorov Complexity and Algorithmic Information

#epigraph[The complexity of a string is the length of the shortest program that produces it. A string is random if it cannot be produced by a program shorter than itself.][Gregory Chaitin, paraphrasing the central idea of algorithmic information theory]

Look at these two strings of 32 characters each:

#align(center)[
  `01010101010101010101010101010101` \
  `11010000100110010110100110001111`
]

Both are 32 bits long. If you measured them with Shannon's entropy (the great number we built over the last four chapters) and treated each as "a source emitting zeros and ones with probability one-half each," the two would look _identical_: 32 bits of pure information, take it or leave it. And yet your eye already knows better. The first string is "zero-one, repeated sixteen times." You can describe it in a sentence and reconstruct it perfectly. The second string is just... noise. To describe it, the shortest thing you can say is, more or less, the string itself: `11010000100110010110100110001111`. There is nothing to grab onto, no pattern to abbreviate.

Shannon's theory, for all its power, _cannot tell these two strings apart_, because Shannon's theory is about _sources_: about probabilities, averages, ensembles of messages that might have been sent. It has nothing whatsoever to say about a single, individual, already-given string sitting on your desk. But surely the first string is "simpler" than the second in some absolute, God's-honest sense that has nothing to do with probabilities. Surely "the amount of information in an object" should be a property of _the object itself_, not of some imaginary lottery it was drawn from.

That hunch is correct, and chasing it leads to one of the most beautiful and most humbling ideas in all of mathematics. Three people - a young American named Ray Solomonoff, the towering Soviet mathematician Andrey Kolmogorov, and a teenage Argentine-American prodigy named Gregory Chaitin - arrived at it independently between 1960 and 1965. Their idea: *the true information content of an object is the length of the shortest computer program that produces it.* This number is called the *Kolmogorov complexity*, and it is, in a precise and provable sense, the ultimate limit of compression: the size of the smallest possible compressed file, the one no clever trick will ever beat. It is the perfect compressor we have been chasing since Chapter 1.

There is just one catch, and it is a doozy: this perfect compressor _cannot be built_. Not "is hard to build," not "we haven't figured it out yet." It is _provably impossible_, forever, for fundamental logical reasons twinned with Gödel's incompleteness theorem and the unsolvability of the halting problem. This chapter is the story of that magnificent, unreachable ideal: what it is, why it is exactly the right definition, why it is uncomputable, and why it quietly governs everything every real compressor does - even though we can never touch it.

#recap[
In Chapter 18 we built Shannon's *entropy* $H(X) = -sum_x p(x) log_2 p(x)$, the average surprise of a _source_, in bits. In Chapter 19 the *Source Coding Theorem* turned that number into a hard floor: no lossless code beats $H(X)$ bits per symbol on average, and arithmetic coding reaches it. In Chapter 8 we met *counting* and the *pigeonhole principle* - the proof that no compressor can shrink every input. In Chapters 13--17 we learned how data becomes *bytes* and wrote real *Python*; in Chapter 14 we met *algorithms*, *pseudocode*, and the idea that a program is a finite list of instructions. This chapter changes the subject from _sources_ (probability distributions) to _individual objects_ (single strings), and from _coders_ to _programs_. We lean on logarithms (Chapter 7), the pigeonhole bound (Chapter 8), and your growing Python fluency. Next chapter ties this ideal back to the practical world of prediction and learning.
]

#objectives((
  [Explain why Shannon entropy cannot measure the information in a _single_ object, and what question Kolmogorov complexity answers instead.],
  [Define the *Kolmogorov complexity* $K(x)$ as the length of the shortest program that prints $x$ and halts, and compute it intuitively for simple strings.],
  [State and *prove* the *Invariance Theorem* (why the choice of programming language changes $K(x)$ by at most a constant) and explain why that makes the definition meaningful.],
  [Prove by *counting* that *most strings are incompressible* (random), and that a random string's own bits are its shortest description.],
  [Prove that $K(x)$ is *uncomputable* - that no program can calculate it - using the *Berry paradox*, and connect this to Gödel and the halting problem.],
  [Define *algorithmic probability* and the *universal prior*, see how Occam's razor falls out as a theorem, and understand why $K$ is the unreachable north star every real compressor approximates.],
))

== Two strings, one ruler that fails

Let us be precise about why Shannon's beautiful machinery goes silent in front of a single string. Shannon's entropy $H(X)$ is a property of a *random variable* $X$: a source with a probability distribution. To even write down $H(X)$ you must first answer "what are the possible messages, and how likely is each?" The entropy then tells you the _average_ number of bits to encode messages drawn from that distribution, over many draws.

But now I hand you _one specific string_ - say the second one above, `11010000100110010110100110001111` - and ask, "how much information is _in this_?" The question has no answer in Shannon's framework, because a single fixed string is not a random variable. There is no distribution. The string just _is_. You could _pretend_ it was drawn from some source, but which one? If I claim it came from a source that emits exactly that string with probability one, then its self-information is $-log_2 1 = 0$ bits - it carries no information at all, because it was certain! That is obviously absurd, and it exposes the gap: *Shannon information depends on a chosen distribution, and for a lone object the choice is arbitrary.*

#keyidea[
Shannon entropy measures the information of a *source* - a probability distribution over many possible messages. Kolmogorov complexity measures the information of a single *object*, one specific string, with no probability anywhere in sight. The first asks "on average, how surprising is the next message from this machine?" The second asks "how short a recipe completely reconstructs _this exact thing_?" They are different questions, and the second is the one your intuition about "`0101...` is simpler than noise" was secretly asking all along.
]

The escape from the trap is to stop talking about probability and start talking about _description_. Forget where the string "came from." Ask instead: *what is the shortest complete instruction I could give a computer so that it prints this string and nothing else?* For `01010101010101010101010101010101`, the instruction is short: "print `01` sixteen times." For the noisy string, the shortest honest instruction seems to be "print `11010000100110010110100110001111`" - you have to spell it out, because there is no shorter way to pin it down. The _length_ of that shortest instruction is a number attached to the object itself, owing nothing to any imagined lottery. That number is what we are after.

#history[
The idea was discovered three times, independently, in five years. *Ray Solomonoff* (1926--2009), an American working largely outside academia, got there first: in a 1960 technical report and then his 1964 two-part paper _A Formal Theory of Inductive Inference_, he introduced "algorithmic probability" while trying to formalize how a machine could learn and predict. Compression was, for him, a means to the end of _induction_. *Andrey Kolmogorov* (1903--1987), the greatest probabilist of the twentieth century (and the man who put probability itself on rigorous axiomatic foundations in 1933), arrived at the same descriptive-complexity idea around 1963--1965, publishing in the Soviet journal _Problems of Information Transmission_; his towering name is the one that stuck to the quantity. And *Gregory Chaitin* (born 1947) reached it as a _teenager_, submitting his foundational paper to the _Journal of the ACM_ in October 1966 (it appeared in 1969), and went on to mine its deepest and strangest consequences for decades. Because all three share the credit, the field is most fairly called *algorithmic information theory*; the central number is sometimes written "Kolmogorov--Chaitin complexity" or "algorithmic complexity" to spread the honor.
]

== The definition: information as program length

To make "shortest program" precise, we need to fix what "program" and "computer" mean. The natural choice (the one Chapter 14 quietly prepared you for) is the most general notion of computation we have: a *universal computer*, a machine that can run any program in any language - a Turing machine, or equivalently your laptop running Python, given unlimited memory and time. A program is a finite string of bits that the machine reads and executes; if it halts, it leaves some output behind. We measure the program's *length* in bits.

#definition("Kolmogorov complexity")[
Fix a universal computer $U$. The *Kolmogorov complexity* of a string $x$, written $K_U (x)$ (or just $K(x)$), is the length, in bits, of the *shortest program* $p$ that, when run on $U$ with no input, prints exactly $x$ and then halts:
$ K_U (x) = min { abs(p) : U(p) = x }, $
where $abs(p)$ is the bit-length of the program $p$ and $U(p)$ is what $U$ outputs when it runs $p$. The minimizing program $p^*$ is the *shortest description* of $x$; we say $x$ is *incompressible* (or *algorithmically random*) when $K(x)$ is essentially as large as $abs(x)$ itself - when the string is its own shortest description.
]

#gomaths("Reading the min and the |·| notation")[
Two pieces of notation appear in the definition; both are friendly.

The vertical bars $abs(p)$ mean "the length of $p$." If $p$ is the bit-string `1011`, then $abs(p) = 4$. (Same bars we used for absolute value, reused here for "size of"; context tells them apart.)

The symbol $min{ dots }$ means "the smallest value in this set." The set ${ abs(p) : U(p) = x }$ is read "the collection of lengths $abs(p)$, ranging over all programs $p$ for which $U$ prints $x$." So $min$ of that set is the length of the _shortest_ such program. For example, $min{5, 2, 9, 2, 7} = 2$. Many programs print $x$ (you can always pad a program with junk that does nothing); $K(x)$ is the length of the very shortest one.
]

Let us get a feel for $K$ by estimating it for a few strings, the way a physicist estimates orders of magnitude.

#worked[
*A highly regular string.* Take the string of one million zeros, $x = underbrace(0 0 0 dots 0, "1 000 000 of them")$. A program that prints it is essentially "`for i in range(1000000): print('0')`". The _only_ part of that program that grows with the string is the number one million, and a number $n$ can be written down in about $log_2 n$ bits (Chapter 7: it takes $log_2 n$ bits to name one of $n$ things). So
$ K(underbrace(0 dots 0, n)) <= log_2 n + c, $
for some small constant $c$ that covers the fixed boilerplate ("`for ... print`"). For a million zeros that is about $20$ bits plus a small constant - _vastly_ smaller than the million bits of the string itself. Highly regular strings are highly compressible: $K$ is tiny.
]

#worked[
*The digits of $pi$.* The first million binary digits of $pi$ look, to any statistical test, _completely random_: Shannon entropy near maximal, every block of bits about equally frequent. Yet $K$ of those million digits is _tiny_: there is a short, fixed program (a few hundred bytes implementing a spigot algorithm) that prints as many digits of $pi$ as you ask for. The recipe is "compute $pi$ to $n$ bits and print them," whose length is again about $log_2 n + c$. This is the punchline of Kolmogorov complexity that Shannon can never see: *a string can be statistically random yet algorithmically trivial.* Pseudo-randomness is exactly this - output that looks random but has a short generating program. The seed is the short description.
]

#worked[
*A genuinely random string.* Flip a fair coin $n$ times and write down the bits. With overwhelming probability (we will _prove_ this in a moment), there is no program shorter than about $n$ bits that prints your sequence. The shortest description is the sequence itself, give or take a constant. For such a string, $K(x) approx abs(x)$. It is *incompressible.* This is what "random" _means_ in algorithmic information theory: not "drawn from a distribution," but "having no short description, no exploitable pattern, nothing to abbreviate."
]

#note[
There is always a cheap upper bound. Whatever $x$ is, you can print it with the program "print the following literal string: $x$." That program is $x$ itself plus a fixed wrapper of constant length $c$. Hence for _every_ string,
$ K(x) <= abs(x) + c. $
Nobody is ever forced to pay more than (essentially) the raw length: the question is always how far _below_ $abs(x)$ you can get. Compression is the art of finding $K(x) < abs(x)$; the pigeonhole principle of Chapter 8 guaranteed that you cannot win for _every_ $x$, and now we will see exactly how rarely you win.
]

== The Invariance Theorem: why the language barely matters

A nagging worry should be bothering you. The definition of $K(x)$ began "fix a universal computer $U$." But there are infinitely many computers and infinitely many programming languages! The shortest program to print our string in Python might be a different length than the shortest in C, or in some bizarre custom machine code I invent tonight with a one-byte instruction that prints exactly your favorite string. If $K(x)$ depends on which machine I pick, then it is not a property of the object $x$ at all. It is a property of my arbitrary choice of computer, and the whole grand idea collapses into bookkeeping.

The *Invariance Theorem* is what saves the day, and it is the foundational result of the entire field. It says: the choice of universal machine changes $K(x)$ by *at most an additive constant* - a constant that depends on the two machines but *not on $x$*. So for long strings, where $K(x)$ grows large, the choice of language is a rounding error. Kolmogorov complexity is, up to a fixed additive constant, an intrinsic property of the object.

#theorem("Invariance Theorem (Solomonoff-Kolmogorov)")[
For any two universal computers $U$ and $V$, there is a constant $c_(U,V)$ (depending only on $U$ and $V$, never on the string) such that for every string $x$,
$ abs(K_U (x) - K_V (x)) <= c_(U,V). $
]

The idea behind the proof is the single most important trick in the subject, so let us build it slowly. What makes a computer _universal_? It is that it can *simulate any other computer*. Your laptop is universal: it can run a Python interpreter, which is a program that reads other programs (Python source) and executes them. A Python interpreter is exactly a "simulator for the Python machine," written for the laptop machine. This is the lever.

#keyidea[
A universal machine $U$ can run an *interpreter* for any other machine $V$. That interpreter is a fixed program of some fixed length $c$. To make $U$ reproduce whatever $V$ does on a program $q$, you hand $U$ the bundle "interpreter-for-$V$, followed by $q$." So _any_ program $q$ that works on $V$ becomes a program of length $abs(q) + c$ that works on $U$. The cost of switching machines is one fixed interpreter, paid once, independent of the data.
]

#proof[
Let $V$ be any universal machine and let $p^*$ be the shortest program for $x$ on $V$, so $abs(p^*) = K_V (x)$. Because $U$ is universal, there exists a fixed program $I_V$ - an _interpreter_ that makes $U$ simulate $V$ - of some constant length $c = abs(I_V)$, not depending on $x$. Now form the program $I_V p^*$ for $U$: first the interpreter, then the $V$-program. Running it, $U$ simulates $V$ running $p^*$, which prints $x$. So $I_V p^*$ is _a_ program that makes $U$ print $x$, of length $abs(I_V) + abs(p^*) = c + K_V (x)$. The _shortest_ $U$-program can only be shorter, so
$ K_U (x) <= K_V (x) + c. $
By the identical argument with the roles of $U$ and $V$ swapped (using an interpreter for $U$ written for $V$), $K_V (x) <= K_U (x) + c'$ for some constant $c'$. Putting both together, $abs(K_U (x) - K_V (x)) <= max(c, c')$, a constant depending only on the two machines.
]

#fig([Switching machines costs one fixed interpreter. The shortest $V$-program $p^*$ for $x$, prefixed by the constant-length interpreter $I_V$, becomes a $U$-program for $x$. The extra cost $c$ does not depend on $x$ - so for long strings it vanishes into the noise.],
cetz.canvas({
  import cetz.draw: *
  // V-program
  rect((0,0),(2.6,0.7), fill: rgb("#eef4fb"), stroke: rgb("#0b5394"))
  content((1.3,0.35))[#box(width: 2.2cm, inset: 2pt, align(center, text(size: 8pt)[$p^*$ on $V$, length $K_V(x)$]))]
  // arrow
  line((2.9,0.35),(3.9,0.35), mark: (end: ">"))
  // U-program = interpreter + p*
  rect((4.2,0),(5.5,0.7), fill: rgb("#fff3e0"), stroke: rgb("#783f04"))
  content((4.85,0.35))[#box(width: 0.9cm, inset: 2pt, align(center, text(size: 8pt)[$I_V$ ($c$)]))]
  rect((5.5,0),(8.1,0.7), fill: rgb("#eef4fb"), stroke: rgb("#0b5394"))
  content((6.8,0.35))[#box(width: 2.2cm, inset: 2pt, align(center, text(size: 8pt)[$p^*$, length $K_V(x)$]))]
  content((6.15,-0.5))[#box(width: 3.6cm, inset: 2pt, align(center, text(size: 8pt)[program on $U$, length $K_V(x)+c$]))]
}))

#aside[
The constant $c_(U,V)$ can be _large_ in practice - an interpreter for a baroque machine might be megabytes. The theorem does not promise that $K$ is the _same_ in every language for short strings; for a 10-bit string the "constant" could dwarf the complexity. What it promises is that the constant does not _grow with the data_. As strings get long, $K(x)$ grows without bound while the fudge factor stays fixed, so the relative error shrinks to zero. This is why algorithmic information theory makes its strongest statements _asymptotically_, about long strings - exactly where compression matters most.
]

#checkpoint[Why does the Invariance Theorem require both machines to be _universal_? What goes wrong if $V$ is some weak, non-universal gadget?][If $V$ is not universal, $U$ might not be able to simulate it _with a single fixed interpreter_ - or worse, a non-universal $V$ might be unable to print some strings at all, making $K_V (x)$ infinite for those. Universality is exactly the property "can simulate any machine," which is what lets each machine emulate the other at a constant fixed cost. Only among universal machines is $K$ pinned down up to an additive constant.]

== Most strings are incompressible (a counting proof)

We have seen that _some_ strings (a million zeros, the digits of $pi$) are wildly compressible. Optimists might hope that with enough cleverness, _every_ string could be squeezed. Chapter 8's pigeonhole principle already told us that is impossible. Kolmogorov complexity lets us say something far sharper and more shocking: not only can we not compress everything - *almost nothing* is compressible. The overwhelming majority of strings are essentially incompressible. Random is the _norm_; structure is the rare exception.

The proof is pure counting, and it is gorgeous. The whole argument rests on one lopsided fact: there are _far more long strings than short programs_.

#gomaths("Counting bit-strings: the geometric-series headcount")[
How many bit-strings are there of length _exactly_ $k$? Each of the $k$ positions is independently $0$ or $1$, so by the multiplication principle (Chapter 8) there are $2^k$ of them. How many bit-strings of length _less than_ $n$ (that is, length $0, 1, 2, dots, n-1$)? Add them up:
$ 2^0 + 2^1 + 2^2 + dots + 2^(n-1) = 2^n - 1. $
That clean identity - the sum of powers of two up to $2^(n-1)$ is one short of $2^n$ - is worth committing to memory. (Quick check: $2^0+2^1+2^2 = 1+2+4 = 7 = 2^3 - 1$. ✓) The takeaway: there are *fewer than $2^n$ programs of length below $n$*, but there are *exactly $2^n$ strings of length $n$*. Strictly more strings than short programs, and that gap is the entire proof.
]

#theorem("Incompressibility")[
For every length $n$ and every "compression budget" $d >= 1$, the number of strings $x$ of length $n$ with $K(x) < n - d$ is less than $2^(n-d)$. Consequently, the fraction of length-$n$ strings compressible by even $d$ bits is below $2^(-d)$: at most $1/2$ can be shrunk by $1$ bit, at most $1/256$ by $8$ bits, at most one in a million by $20$ bits.
]

#proof[
A string $x$ has $K(x) < n - d$ exactly when _some_ program shorter than $n - d$ bits prints it. So every such "compressible" string is the output of some program of length $0, 1, dots, (n-d-1)$. By the headcount above, the number of programs of length less than $n - d$ is at most $2^(n-d) - 1 < 2^(n-d)$. Each program, when run, prints _at most one_ string (a deterministic machine has one output). Therefore _at most_ $2^(n-d)$ distinct strings can have $K(x) < n - d$ - no matter how long they are. Now there are $2^n$ strings of length $n$ in total, so the fraction that are compressible by $d$ or more bits is at most $2^(n-d) \/ 2^n = 2^(-d)$.
]

Read that conclusion again, because it is one of the most underappreciated facts in computing. *At least half of all strings cannot be compressed by even a single bit.* At least $255/256$ of them cannot be shortened by even one byte. The "compressible" strings - the ones with patterns, with structure, with short descriptions - form a vanishingly thin sliver of the space of all possible strings. So how on earth does compression _work at all_ in practice, given that it provably fails on almost everything?

#keyidea[
Compression works in practice not because most _strings_ are compressible (they aren't), but because the strings humans actually produce and store are an astronomically biased, structured subset of all possible strings. English text, photographs, audio, source code, genomes: these live in the tiny compressible sliver, because they are generated by lawful processes (grammar, optics, physics, biology) that leave exploitable regularities. A compressor is a bet that its input came from that structured sliver. Feed it the output of a good random-number generator and it will fail - sometimes _expand_ the file - exactly as the counting theorem demands. Random data has no short description because $K(x) approx abs(x)$; there is nothing to remove.
]

#misconception[A good enough compressor - or a future AI - could shrink any file, including already-compressed or encrypted ones, if it were just clever enough.][The incompressibility theorem forbids it, permanently, with a counting argument no cleverness can dodge. If a lossless compressor maps some inputs to shorter outputs, the pigeonhole principle (Chapter 8) forces it to map _others_ to longer outputs - the mapping must be one-to-one to be reversible, and you cannot fit $2^n$ distinct inputs into fewer than $2^n$ distinct outputs. Well-compressed and encrypted files already sit at $K(x) approx abs(x)$: they look random, so there is no pattern left to exploit, and any "recompression" tool that claims to shrink them further is either lying, lossy, or secretly storing the difference somewhere else. This is not an engineering limitation; it is arithmetic.]

#note[
The incompressibility theorem is also a working _proof technique_, called the *incompressibility method*. To show that "most inputs" force an algorithm into its worst case, you argue: if the algorithm did well on input $x$, then the record of its run would be a short description of $x$, making $K(x)$ small - but most $x$ have large $K(x)$, contradiction. It is a slick way to prove lower bounds and average-case results without fiddly probability, and it appears throughout the analysis of algorithms.
]

== The catastrophe: $K$ is uncomputable

Here is the perfect compressor, defined and well-behaved. $K(x)$ is the exact, machine-independent (up to a constant), ultimate compressed size of any object. So let us build it! Write a program `kolmogorov(x)` that, given a string $x$, returns $K(x)$ - and we will have the optimal compressor, the holy grail of Chapter 1, in our hands.

We cannot. No such program exists, and the proof that it cannot exist is one of the jewels of twentieth-century logic. *Kolmogorov complexity is uncomputable*: there is no algorithm that takes a string $x$ and outputs $K(x)$, ever, for all inputs. The function is perfectly well _defined_ - every string has a definite shortest program - but no mechanical procedure can _compute_ it. This is not a temporary state of ignorance; it is a theorem, as permanent as $2 + 2 = 4$.

There are two beautiful routes to this result. The first runs through a 113-year-old paradox about words.

#aside[
*The Berry paradox* is named for G. G. Berry, an Oxford librarian who suggested it to Bertrand Russell around 1906. Consider the phrase: "*the smallest positive integer not nameable in fewer than twelve words.*" There are only finitely many phrases of eleven words or fewer (the dictionary is finite), so they can name only finitely many integers; some integers escape them, and there must be a _smallest_ such integer. But - gotcha - we just named that integer with the eleven-word phrase in quotes! It is, and is not, nameable in under twelve words. The paradox lives in the slippery word "nameable." Chaitin's genius was to replace the vague "nameable in $k$ words" with the rigorous "printable by a $k$-bit program" - and turn a parlor trick into a hard theorem.
]

#theorem("Uncomputability of $K$ (Chaitin / Berry form)")[
There is no algorithm that, given any string $x$, computes $K(x)$.
]

#proof[
Suppose, for contradiction, that some program `K(·)` _does_ compute Kolmogorov complexity - it halts on every input and returns the correct value. We will use it to build a program that does something impossible.

Pick a large number $m$. Consider this program, call it $B$: "*search through all strings $x$ in order of length (then alphabetically), computing `K(x)` for each, and print the first string $x$ you find with `K(x)` $>= m$.*" Such a string exists - the incompressibility theorem just proved that strings of high complexity are abundant - so $B$ halts and prints some specific string $x_0$ with $K(x_0) >= m$.

Now, how long is the program $B$? It consists of a _fixed_ chunk of code (the search loop and the call to `K`) plus the number $m$ written out, which takes about $log_2 m$ bits. So
$ abs(B) <= log_2 m + c $
for some constant $c$ that does not depend on $m$. But $B$ _prints $x_0$_, so $B$ is _a_ program for $x_0$, which means $x_0$'s shortest program is no longer than $B$:
$ K(x_0) <= abs(B) <= log_2 m + c. $
Yet by construction $K(x_0) >= m$. Chain them: $m <= K(x_0) <= log_2 m + c$, i.e. $m <= log_2 m + c$. For all large enough $m$ this is _false_ - $log_2 m$ grows agonizingly slower than $m$, so eventually $m$ overtakes $log_2 m + c$ and the inequality breaks. The only assumption we made was that `K` exists and is computable. That assumption must be wrong. $K$ is uncomputable.
]

Sit with the shape of that argument. We assumed we could _compute_ complexity, and used it to write a _short_ program that names a _provably complex_ object: a short description of something that has no short description. That is the Berry paradox, made of bits instead of words, and it detonates the assumption. The very ability to measure incompressibility would let you compress the incompressible.

#keyidea[
The deep reason $K$ is uncomputable: to be _sure_ you have found the shortest program for $x$, you would have to run every shorter program and check whether it prints $x$. But some of those programs *never halt* - they loop forever - and you can never be sure, in finite time, that a running program will not eventually stop and print $x$. Deciding "will this program halt?" is the *halting problem*, proved unsolvable by Alan Turing in 1936. Uncomputability of $K$ is the halting problem wearing a compression costume.
]

#history[
This same machinery gives *Chaitin's incompleteness theorem* (1971), a startling cousin of Gödel's 1931 result. Chaitin showed that for any fixed formal mathematical system (any consistent set of axioms and rules, like the arithmetic we all trust), there is a constant $L$ - roughly the "complexity of the axioms" - such that *the system can never prove any statement of the form "$K(x) > L$" for any specific string $x$*. In plain words: a mathematical theory of complexity $L$ can certify that individual objects are random only up to its own complexity, and no further. Mathematics cannot prove that any specific string is much more complex than mathematics itself. Gödel showed there are true statements no system can prove; Chaitin pinpointed an _infinite, concrete family_ of them - "this string is random" - and tied the boundary directly to information content. Truth outruns proof, and the gap is measured in bits.
]

#aside[
Chaitin pushed further to his famous constant *$Omega$* (read "omega"), the *halting probability*: the probability that a program whose bits are chosen by coin flips eventually halts. $Omega$ is a single, perfectly definite real number between $0$ and $1$. It is *uncomputable* and *algorithmically random*: its binary digits have no pattern, no formula, no shortcut. Knowing the first $n$ digits of $Omega$ would let you solve the halting problem for all programs up to $n$ bits and settle famous open conjectures. $Omega$ is, in a sense, all of mathematics' hardest yes/no questions compressed into the bits of one number that no one can ever fully write down. It is the most concentrated incompressible object we know how to point at.
]

#pitfall[
"Uncomputable" does not mean "unknowable in every instance." For _specific_ simple strings you can often _prove_ an exact value or tight bound on $K$ by exhibiting a short program (upper bound) and arguing no shorter one works (lower bound). What is impossible is a _single algorithm that works for all inputs_. Likewise, $K(x)$ can always be _approximated from above_: any compressor that shrinks $x$ to $L$ bits proves $K(x) <= L + c$. You can keep finding shorter programs and watch your upper bound descend - you simply can never know you have reached the bottom, because the descent might continue via some program you have not thought to try, and you can never rule out the non-halting ones.
]

== Compressing is approximating $K$ from above

That last pitfall contains the bridge from this lofty theory back to the working compressors of this book. Every real compressor is a _computable upper bound_ on $K$. When `gzip` turns a 1000-byte file into 300 bytes, it has _proven_ that $K(x) <= 300 dot 8 + c$ bits: the decompressor plus the 300 bytes constitute a program that prints $x$. A better compressor finds a shorter program - a tighter upper bound. The unreachable floor underneath all of them is $K(x)$ itself.

So Kolmogorov complexity reframes the _entire field_. Building a better compressor _is_ searching for shorter descriptions: climbing down toward $K(x)$, a floor we can approach but, by the uncomputability theorem, never certify we have hit. The history of compression in the rest of this book - Huffman, LZ, PPM, context mixing, neural codecs - is the history of richer and richer _families_ of short programs, each family a computable, restricted stand-in for the universal but unreachable "all programs."

Let us make the "compression is an upper bound on $K$" idea concrete and runnable. We will estimate the algorithmic complexity of several strings by the only honest computable proxy we have - *their compressed size under a real compressor* - and watch it separate the regular from the random exactly as theory predicts.

#gopython("The standard-library zlib module and len()")[
Python ships with `zlib`, an implementation of the DEFLATE compressor (the engine inside `gzip` and PNG; we dissect it in Chapter 30). Two pieces we need:

- `data.encode()` turns a text `str` into a `bytes` object - the raw 8-bits-per-character byte form (Chapter 17). Compressors work on bytes, not characters.
- `zlib.compress(b)` takes a `bytes` object and returns a shorter (we hope) `bytes` object: the compressed form.
- `len(b)` returns the number of bytes in `b`. (We met `len` on lists in Chapter 16; it works on `bytes` too.)

```python
import zlib
raw = ("AB" * 1000).encode()   # 2000 bytes, very regular
print(len(raw), len(zlib.compress(raw)))   # 2000  ~  20
```
The compressed length is our computable, always-an-upper-bound estimate of $K$: it can only _overstate_ the true shortest program, never understate it.
]

#tryit[
*A Kolmogorov-complexity estimator (illustrative -- not a `tinyzip` step).* `tinyzip` has, so far, the bit-level I/O of Chapter 17 and the entropy meter of Chapters 18--19. Because $K$ itself is uncomputable, this chapter adds nothing to the package's pipeline; instead, here is a small stand-alone diagnostic - a _complexity probe_ that ranks inputs by how compressible they are. It is not a compressor; it is a lens that tells us how much structure a file contains, exactly the question $K$ asks, answered by a computable upper bound.

```python
import zlib

def k_estimate(data: bytes) -> int:
    """Upper-bound estimate of Kolmogorov complexity, in bits.

    Returns 8 * (compressed byte length). Always an OVER-estimate of
    the true K(data): the decompressor + this output is one program
    that reproduces `data`, so K(data) <= this value + a constant.
    """
    return 8 * len(zlib.compress(data, level=9))

def compressibility(data: bytes) -> float:
    """Fraction of bits that look removable: 1.0 = all structure,
    0.0 = looks incompressible (random)."""
    if len(data) == 0:
        return 0.0
    raw_bits = 8 * len(data)
    return 1.0 - k_estimate(data) / raw_bits
```

#pyrecall[
Inside an f-string (Chapter 15), a value can carry a _format spec_ after a colon: `f"{name:9}"` pads `name` to width 9, `f"{n:5}"` right-aligns a number in a 5-wide column, and `f"{x:.3f}"` prints `x` rounded to 3 decimal places. The spec only controls _layout_, never the value. `os.urandom(k)` (from the standard `os` module) returns `k` bytes drawn from the operating system's cryptographic random source - about as close to "no pattern" as a real file gets.
]

Now feed it three classic inputs - pure structure, real text, and the output of a good random generator - and watch the incompressibility theorem come alive:

```python
import os

periodic = b"01" * 5000                 # highly regular
english  = (b"the quick brown fox " * 250)  # real-language structure
random_b = os.urandom(10000)            # cryptographic noise: K ~ length

for name, d in [("periodic", periodic),
                ("english", english),
                ("random", random_b)]:
    print(f"{name:9} bytes={len(d):5}  "
          f"K_est_bits={k_estimate(d):6}  "
          f"compressibility={compressibility(d):.3f}")
```

Typical output:

```
periodic  bytes=10000  K_est_bits=   640  compressibility=0.992
english   bytes= 5000  K_est_bits=  2304  compressibility=0.942
random    bytes=10000  K_est_bits= 80224  compressibility=-0.003
```

The periodic string collapses to almost nothing - tiny $K$. English text compresses well but not to nothing: real structure, real residual. And `os.urandom`'s output _refuses_ to shrink; its estimate even ticks _above_ the raw size (a negative "compressibility"), because DEFLATE adds a few bytes of header it can never earn back on truly random data. That overshoot is the incompressibility theorem made visible: on random input, a lossless compressor must, on average, _lose_. There is no pattern to remove, so the only honest description is the data itself.
]

#tryit[
Run the probe on files you have lying around: a `.txt` of a novel, a `.png` photo, an already-`gzip`ped archive, an `.mp3`. You will find text and raw bitmaps compress a lot, while the `.png`, the `.gz`, and the `.mp3` barely budge. They are _already_ near their $K$, having been squeezed once already. Compressing a compressed file is trying to find structure that a previous tool already spent. The estimate `k_estimate` is your handheld Kolmogorov-complexity meter: a computable shadow of an uncomputable ideal.
]

== Algorithmic probability and the universal prior

We opened by banishing probability - Kolmogorov complexity is about lone objects, not distributions. But Solomonoff's original motivation was _prediction_, and prediction needs probabilities. So we now perform a small miracle: we _build a probability distribution out of program lengths_, and it turns out to be the best possible prior for learning, with Occam's razor baked in as a theorem rather than a preference.

The idea is disarmingly simple. Imagine feeding a universal machine a program whose bits are decided by fair coin flips. Sometimes the random bits form a program that halts and prints some string $x$; sometimes they loop forever and print nothing. Define the *algorithmic probability* of $x$ as the chance that this coin-flipping process produces $x$.

#definition("Algorithmic probability and the universal prior")[
The *algorithmic probability* of a string $x$ is
$ P(x) = sum_(p : U(p) = x) 2^(-abs(p)), $
the sum, over _every_ program $p$ that prints $x$, of $2^(-abs(p))$. A program of length $abs(p)$ - bits chosen by coin flips - occurs with probability $2^(-abs(p))$, so $P(x)$ is the total probability mass of all the ways a random program could produce $x$. The distribution $P$ is called the *universal prior* (or _Solomonoff prior_), and it is the best a priori guess about an unknown source you can make before seeing any data.
]

#gomaths("Why $2^(-abs(p))$ is the probability of a program")[
If you produce program bits by flipping a fair coin, each specific bit-string of length $L$ has probability $(1/2)^L = 2^(-L)$ - it is one particular outcome among $2^L$ equally likely ones (Chapter 9). So a program $p$ of length $abs(p)$ "occurs by chance" with probability $2^(-abs(p))$. Short programs are _exponentially_ more probable than long ones: an 8-bit program is $2^(20) approx$ a million times likelier than a 28-bit program. When we sum $2^(-abs(p))$ over all programs that print $x$, the _shortest_ program - the one of length $K(x)$ - contributes by far the largest single term, $2^(-K(x))$, and dominates the sum. (A technicality: to make the total mass over all $x$ at most $1$, one uses "prefix-free" programs, where no program is a prefix of another; this is the same Kraft-inequality bookkeeping from Chapter 19. We gloss over it - the intuition is exactly right.)
]

Now look at what that domination says. Because the shortest program dominates the sum,
$ P(x) approx 2^(-K(x)), quad "equivalently" quad K(x) approx -log_2 P(x). $
This is the bridge back to Shannon, and it is breathtaking. Recall from Chapter 18 that an event of probability $P$ carries $-log_2 P$ bits of surprisal, and an ideal code spends $-log_2 P$ bits on it. Here, $-log_2 P(x)$ - the ideal code length under the universal prior - is (essentially) $K(x)$, the shortest program. *The two definitions of "information content," Shannon's $-log_2 P$ and Kolmogorov's shortest program, coincide* - once the probability $P$ is the universal one built from program lengths. Algorithmic information theory and Shannon's theory are two views of a single mountain.

#mathrecall[
The notation $O(1)$, from *Big-O* (Chapter 14), means "some bounded quantity that does not grow with the input" - here, a constant fudge term independent of the string $x$. Writing "$=K(x) + O(1)$" is shorthand for "equals $K(x)$ plus or minus a fixed constant," the same up-to-a-constant slack the Invariance Theorem gave us.
]

#theorem("Occam's razor as a theorem")[
Under the universal prior, simpler hypotheses are automatically more probable: a string $x$ with a short description ($K(x)$ small) has high prior probability $P(x) approx 2^(-K(x))$, while a string with no short description has exponentially small prior probability. The preference for simplicity is not an aesthetic assumption added by hand - it is a _consequence_ of weighting every explanation by $2^(-"its length")$.
]

#proof[
The shortest program for $x$ has length $K(x)$, so it contributes a term $2^(-K(x))$ to the sum $P(x) = sum_(p: U(p)=x) 2^(-abs(p))$. Since every term is non-negative, the whole sum is _at least_ that one term: $P(x) >= 2^(-K(x))$. In the other direction, the shortest program dominates - the remaining programs are all longer, so their contributions $2^(-abs(p))$ are smaller and (under the prefix-free convention) sum to at most a constant multiple of the largest term. Hence $P(x) <= c dot 2^(-K(x))$ for a fixed constant $c$. Combining, $2^(-K(x)) <= P(x) <= c dot 2^(-K(x))$, so $P(x)$ and $2^(-K(x))$ agree up to a constant factor; equivalently $-log_2 P(x) = K(x) + O(1)$. Now compare two strings $x$ (simple, small $K$) and $z$ (complex, large $K$): their prior probabilities are in ratio roughly $2^(K(z) - K(x))$, exponentially favoring the simpler one. Simplicity wins by arithmetic, not by decree.
]

#keyidea[
*Solomonoff induction* is the prediction rule you get from the universal prior: to predict the next symbol of a stream, weight every program consistent with the data seen so far by $2^(-"length")$ and let them vote. It is provably the best possible universal predictor - its total prediction error over any computable source is bounded by that source's Kolmogorov complexity, a finite number. It is the perfect learner. And it is, of course, *uncomputable*, inheriting the catastrophe of $K$. So it is a north star, not a navigation system: every practical learning algorithm and every practical compressor is a _computable approximation_ to this incomputable optimum, trading universality for the ability to actually run. We pick up this thread - compression as prediction as learning - in the very next chapter.
]

#algo(
  name: "Solomonoff induction (universal prediction)",
  year: "1964",
  authors: "Ray Solomonoff",
  aim: "Predict the next symbol of any computable sequence optimally, with no prior knowledge of the source, by Bayesian mixing over all programs.",
  complexity: "Uncomputable (sums over all halting programs); approximated in practice by restricted model classes.",
  strengths: "Provably optimal universal predictor; cumulative error bounded by the source's Kolmogorov complexity; Occam's razor built in; needs no hand-chosen prior, model, or regularizer.",
  weaknesses: "Uncomputable, so never runnable as written; the universal prior depends on the reference machine up to a constant; astronomically expensive even to approximate.",
  superseded: "Approximated by every practical predictor - PPM, context mixing, neural language models - each a computable, restricted stand-in (Chapters 33--34, 56--62).",
)[
  The recipe in one breath: maintain a probability for every program weighted by $2^(-"length")$; after each observed symbol, discard programs that disagree with the data and renormalize; predict the next symbol by the surviving programs' weighted vote. Because short programs carry most of the weight, the predictor effectively bets on the _simplest explanation still consistent with the evidence_ - and provably converges to the truth for _any_ computable source. It is the theoretical ceiling that the entire arc of this book, from Huffman to large language models, climbs toward.
]

== A glimpse of conditional and relative complexity

One refinement is worth meeting, because it makes Kolmogorov complexity into a full _theory of shared information_ mirroring Shannon's. We can ask for the shortest program that prints $x$ _when it is allowed to use a second string $y$ as free input_.

#definition("Conditional Kolmogorov complexity")[
The *conditional Kolmogorov complexity* $K(x | y)$ is the length of the shortest program that, given $y$ as input, prints $x$ and halts. It measures the information in $x$ that is _not already present in $y$_ - the cost of describing $x$ to someone who already knows $y$.
]

This mirrors Shannon's conditional entropy $H(X|Y)$ from Chapter 18 exactly: both measure "how much new information is in $X$ once $Y$ is known." If $x$ and $y$ are near-identical files (two drafts of a document), then $K(x | y)$ is tiny - you only need to describe the _edits_. That is precisely the principle behind _delta compression_ and version control: store $y$ once, then store cheap descriptions $K(x | y)$ of every other version. The *algorithmic mutual information* $K(x) - K(x|y)$ - how much knowing $y$ shortens the description of $x$ - is the algorithmic twin of Shannon's mutual information from Chapter 20. The two theories run in perfect parallel: entropy ↔ complexity, conditional entropy ↔ conditional complexity, mutual information ↔ algorithmic mutual information. Where Shannon averages over a source, Kolmogorov pins down the single object - and a deep theorem says the two agree, on average, up to lower-order terms.

#checkpoint[Two files: $x$ is a 1 GB movie, and $y$ is the _same_ movie with the brightness nudged up by one notch on every pixel. Is $K(x | y)$ closer to $1$ GB or to a few hundred bytes?][A few hundred bytes. Given $y$, the program "take $y$ and subtract one notch of brightness from every pixel" reconstructs $x$ exactly, and that program is tiny - it does not grow with the size of the movie. Almost all of $x$'s information is _already in $y$_; only the rule relating them is new. This is why differential and delta coding can be astonishingly effective when two versions are nearly identical, and it is the formal reason `git` stores history so cheaply.]

== The unreachable star that guides everything

Step back and see what we have. Kolmogorov complexity $K(x)$ is the *true* information content of an individual object: the length of its shortest program, the size of the best possible compressed file, machine-independent up to a constant by the Invariance Theorem. It is the perfect, universal, ultimate compressor - and it is _uncomputable_, fenced off forever by the same logic that gives us Gödel's incompleteness and Turing's halting problem. Most strings are incompressible; the ones we care about are a thin, structured sliver. And from program lengths we can even rebuild probability - the universal prior - recovering Occam's razor as a theorem and Shannon's $-log_2 P$ as a shadow of the shortest program.

So why spend a whole chapter on a compressor we can never build? Because it is the _reference point for the entire field_. Every technique in the rest of this book - every Huffman tree, every LZ match, every neural network - is a computable, restricted bet on a _family_ of short programs, an approximation creeping toward $K(x)$ from above. Knowing the floor exists, knowing exactly why it is unreachable, and knowing that "compress better" means "find a shorter program" turns a grab-bag of tricks into a single coherent science. The Hutter Prize (Chapter 36) literally pays cash for inching the compressed size of Wikipedia closer to its unknown $K$, on the explicit bet - Marcus Hutter's bet - that approaching algorithmic complexity _is_ approaching intelligence. The current record stands at about 110.8 MB on the 1 GB `enwik9` benchmark (fx2-cmix, by Kaido Orav and Byron Knoll, recognized in 2024). Every megabyte shaved is a step toward a star we will never reach but cannot stop walking toward.

#scoreboard(caption: "Kolmogorov complexity reframes the whole scoreboard",
  [Raw `enwik8` (Wikipedia sample)], [100,000,000], [1.00×], [The object whose $K$ we are chasing],
  [`gzip` / DEFLATE (Chapter 30)], [≈36,400,000], [2.75×], [A weak, fast upper bound on $K$],
  [PPM / context mixing (Chs. 33--34)], [≈21,000,000], [4.8×], [A much tighter upper bound],
  [`fx2-cmix`-class (context mixing)], [≈16,900,000], [5.9×], [Best-known computable bound (the same engine sets the 110.8 MB enwik9 record)],
  [True $K(x)$], [_unknowable_], [--], [The uncomputable floor under all of them],
)

#takeaways((
  [*Kolmogorov complexity* $K(x)$ is the length of the shortest program that prints $x$ - the true, intrinsic information content of a _single object_, where Shannon entropy measures only a _source_.],
  [The *Invariance Theorem* makes $K$ meaningful: changing the programming language changes $K(x)$ by at most a fixed constant, because any universal machine can simulate any other with one fixed-length interpreter.],
  [By a *counting* argument, *almost all strings are incompressible*: at most a fraction $2^(-d)$ of length-$n$ strings can be shrunk by $d$ bits. Compression works only because real data is a tiny, structured subset of all strings.],
  [$K(x)$ is *uncomputable* - no algorithm computes it - provable via the *Berry paradox* and tied to Gödel's incompleteness, Chaitin's $Omega$, and Turing's halting problem.],
  [Every real compressor is a *computable upper bound* on $K$; "compress better" literally means "find a shorter program," forever approaching but never certifying the floor.],
  [The *universal prior* $P(x) approx 2^(-K(x))$ rebuilds probability from program lengths, derives *Occam's razor* as a theorem, and makes Shannon's $-log_2 P$ and Kolmogorov's shortest program two views of one quantity.],
))

== Exercises

#exercise("22.1", 1)[
Two 16-bit strings: $a = $ `1010101010101010` and $b = $ `1100100100001111`. In Shannon's framework, treating each as a draw from a fair coin, how many bits of self-information does each carry? Then argue informally which has the smaller _Kolmogorov_ complexity and why the two measures disagree.
]
#solution("22.1")[
Under a fair-coin source each specific 16-bit string has probability $2^(-16)$, so its self-information is $-log_2 2^(-16) = 16$ bits - _identical_ for both. Shannon cannot tell them apart. But $a$ is "`10` repeated 8 times," describable by a short program ("print `10` eight times"), so $K(a)$ is small - well under 16 bits plus the constant. The string $b$ has no obvious pattern; its shortest description is likely close to itself, so $K(b) approx 16 + c$. The measures disagree because Shannon information is a property of the _assumed source_ (here uniform, so both look maximal), while Kolmogorov complexity is a property of the _individual object's structure_.
]

#exercise("22.2", 1)[
Estimate $K(x)$ to within a constant for: (a) the string of $n$ copies of the byte `0xFF`; (b) the first $n$ binary digits of $sqrt(2)$; (c) a string of $n$ truly random coin flips. For each, say whether $K$ grows like $log n$, like $n$, or stays constant, and justify in one sentence.
]
#solution("22.2")[
(a) $K approx log_2 n + c$: a loop "print `0xFF` $n$ times" whose only growing part is the number $n$ (about $log_2 n$ bits). (b) $K approx log_2 n + c$: a fixed program computes $sqrt(2)$ to any precision; only "$n$" grows. Like $pi$, it is statistically random but algorithmically trivial. (c) $K approx n$: with overwhelming probability there is no program shorter than the string itself (incompressibility theorem), so $K$ grows linearly in $n$ - the string is its own shortest description.
]

#exercise("22.3", 2)[
Use the counting theorem to answer precisely: of all $2^(20)$ strings of length $20$, at most how many can be compressed to $15$ bits or fewer? What fraction is that? Then state the largest $d$ for which you can guarantee that _at least one_ length-$20$ string is incompressible by $d$ bits.
]
#solution("22.3")[
Strings with $K(x) <= 15$ are outputs of programs of length $0,1,dots,15$, of which there are $2^(16) - 1 < 2^(16) = 65{,}536$. So at most $65{,}535$ of the $2^(20) = 1{,}048{,}576$ strings compress to $15$ bits or fewer - a fraction below $2^(16)\/2^(20) = 2^(-4) = 1\/16 approx 6.25%$. For incompressibility: the number of programs shorter than $20$ bits is at most $2^(20)-1 < 2^(20)$, so at least one length-$20$ string has $K(x) >= 20$ - incompressible by $d = 0$ bits (cannot be shortened at all). More strongly, fewer than $2^(20-d)$ strings have $K < 20-d$, so a positive fraction resists any fixed $d$; at least one string is fully incompressible.
]

#exercise("22.4", 2)[
Spell out, in your own words, why the program $B$ in the Berry-paradox proof has length only about $log_2 m + c$. Which part of $B$ is constant, and which part grows with $m$? Then explain the single line where the contradiction springs.
]
#solution("22.4")[
$B$ is "search all strings in length order, compute `K` of each, print the first with `K` $>= m$." The _constant_ part is the code: the search loop and the (assumed) subroutine `K`, whose size does not depend on $m$. The only part that _grows_ is the literal number $m$ embedded in the comparison "`K(x) >= m`", and writing $m$ costs about $log_2 m$ bits. So $abs(B) <= log_2 m + c$. The contradiction springs at $K(x_0) <= abs(B)$: since $B$ prints $x_0$, $x_0$ has a program of length $abs(B)$, so $K(x_0) <= log_2 m + c$; but $B$ chose $x_0$ to satisfy $K(x_0) >= m$. Thus $m <= log_2 m + c$, false for large $m$. The false inequality kills the assumption that `K` is computable.
]

#exercise("22.5", 2)[
A friend sells "RecompressPro," claiming it shrinks _any_ file by at least 10%, including files it has already shrunk. Using the pigeonhole principle (Chapter 8), prove this is impossible. What happens if you run a real lossless compressor on its own output, repeatedly?
]
#solution("22.5")[
A lossless compressor must be _injective_ (one-to-one): distinct inputs map to distinct outputs, or decompression is ambiguous. Suppose it shrank every $n$-bit file to at most $0.9n$ bits. Then all $2^n$ inputs of length $n$ map into the set of strings of length $<= 0.9n$, of which there are fewer than $2^(0.9n + 1)$. For large $n$, $2^(0.9n+1) < 2^n$, so two inputs collide - contradicting injectivity. Hence no compressor shrinks everything; some inputs must grow. Running a real compressor repeatedly on its own output: after one or two passes the data sits near its $K$ (looks random), and further passes _stop helping_ and eventually _add_ header bytes - the size plateaus, then creeps up.
]

#exercise("22.6", 2)[
Using `zlib`, write a Python function `most_structured(files: list[bytes]) -> bytes` that returns whichever input has the _lowest_ estimated Kolmogorov complexity per byte (i.e. compresses best). Explain why this is only an _upper-bound_ proxy for $K$ and can never be exact.
]
#solution("22.6")[
```python
import zlib

def most_structured(files: list[bytes]) -> bytes:
    def cost_per_byte(d: bytes) -> float:
        if len(d) == 0:
            return 0.0
        return len(zlib.compress(d, 9)) / len(d)
    return min(files, key=cost_per_byte)
```
`min(files, key=...)` (Chapter 16) returns the element with the smallest key. The compressed size is only an _upper bound_ on $K$: the decompressor plus the compressed bytes form _one particular_ program that reproduces the data, so $K <= 8 dot ("compressed length") + c$. A shorter program might exist that `zlib` (a restricted family - LZ77 + Huffman only) cannot find; and by the uncomputability theorem, _no_ procedure can certify the true minimum, because ruling out shorter programs runs into the halting problem.
]

#exercise("22.7", 3)[
Show that the universal prior makes simple objects more probable by computing a toy version. Suppose the only programs are: a 2-bit program printing `A`, a 4-bit program printing `B`, and a 7-bit program printing `C` (each the unique shortest for its output, prefix-free). Compute the unnormalized algorithmic probabilities $2^(-abs(p))$ and the implied $-log_2 P$ for each. Which object is "simplest," and how does its rank match its program length?
]
#solution("22.7")[
$P(A) = 2^(-2) = 0.25$, $P(B) = 2^(-4) = 0.0625$, $P(C) = 2^(-7) = 0.0078125$. The implied code lengths $-log_2 P$ are exactly the program lengths: $2$, $4$, $7$ bits respectively - confirming $K(x) approx -log_2 P(x)$. $A$ is "simplest": shortest program, highest prior probability. The ranking by probability ($A > B > C$) is the exact _reverse_ of the ranking by program length ($A < B < C$), which is Occam's razor falling out as arithmetic: shorter description ⟺ higher prior probability. (Normalizing by the total $0.25+0.0625+0.0078125 = 0.3203125$ rescales but preserves the order.)
]

#exercise("22.8", 3)[
Conditional complexity. Let $x$ be a 1000-character English paragraph and let $y$ be the _same_ paragraph with every letter shifted up by one in the alphabet (a Caesar cipher, $a -> b$, $z -> a$). Argue that $K(x | y)$ is tiny - a constant, independent of the paragraph's length - and explain what this says about why "structure shared between two files" should be stored only once.
]
#solution("22.8")[
Given $y$, the program "shift every letter of $y$ _down_ by one in the alphabet (with wraparound)" prints $x$ exactly. That program is a _fixed_ size - a few lines describing the shift rule - and crucially does _not_ grow with the paragraph's length: a 10-character or a 10-million-character paragraph needs the same tiny decoder. Hence $K(x | y) <= c$, a constant. This means $x$ contains essentially _no_ information beyond $y$; they share almost all their structure. The lesson: when many files share structure (versions, translations, encodings of one source), store the shared part once and store only the cheap conditional descriptions $K(x_i | y)$ of the differences - the principle behind delta compression, deduplication, and version control like `git`.
]

== Further reading

- #link("https://archive.org/details/bstj30-1-50")[Shannon, C. E. (1951). _Prediction and Entropy of Printed English_. Bell System Technical Journal 30.] -- Shannon's own foray into measuring the redundancy of a real source, the empirical cousin of $K$.
- #link("http://world.std.com/~rjs/1964pt1.pdf")[Solomonoff, R. J. (1964). _A Formal Theory of Inductive Inference, Parts I & II_. Information and Control 7.] -- the first appearance of algorithmic probability and the universal prior.
- #link("https://www.tandfonline.com/doi/abs/10.1080/00207166808803030")[Kolmogorov, A. N. (1965). _Three Approaches to the Quantitative Definition of Information_. Problems of Information Transmission 1(1).] -- the paper that named the field; remarkably readable.
- #link("https://dl.acm.org/doi/10.1145/321495.321506")[Chaitin, G. J. (1969). _On the Length of Programs for Computing Finite Binary Sequences_. Journal of the ACM 16(3).] -- the third independent discovery, and the gateway to Chaitin's incompleteness and $Omega$.
- #link("https://link.springer.com/book/10.1007/978-0-387-49820-1")[Li, M. & Vitányi, P. (2008). _An Introduction to Kolmogorov Complexity and Its Applications_ (3rd ed.). Springer.] -- the definitive textbook, rigorous and complete; the place to go deeper on every proof here.
- #link("https://arxiv.org/abs/0712.3329")[Legg, S. & Hutter, M. (2007). _Universal Intelligence: A Definition of Machine Intelligence_.] -- the formal argument, behind the Hutter Prize, that compression and intelligence are one.

#bridge[
We have met the perfect compressor and proved we can never build it. But the universal prior whispered something we could not ignore: $K(x) approx -log_2 P(x)$ - _shortest program_ and _ideal code length under the best probability model_ are the same quantity. That identity is the hinge of the entire modern field. In Chapter 23 we cash it in: we show that *to compress is to predict is to learn*, that the cross-entropy a machine-learning model minimizes _is_ a compressed file size, and that Rissanen's Minimum Description Length principle turns Occam's razor into a practical, computable model-selection rule. The uncomputable ideal of this chapter becomes, next chapter, the working engine of everything from `gzip` to GPT.
]
