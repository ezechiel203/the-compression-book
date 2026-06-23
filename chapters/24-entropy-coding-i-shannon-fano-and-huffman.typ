#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// local helper: a lightly-set worked-example block (built-ins only)
#let worked(body) = block(width: 100%, breakable: true, inset: (x: 10pt, y: 8pt),
  radius: 4pt, fill: rgb("#fbf7ef"), stroke: (left: 3pt + rgb("#783f04")),
  above: 9pt, below: 9pt)[#body]

= Entropy Coding I: Shannon–Fano and Huffman

#epigraph[I remember thinking, with a sort of revulsion, that there was no way to do it. So I threw it in the wastebasket. And as I was on my way to the wastebasket, I got the idea.][David A. Huffman, recalling the night in 1951 he abandoned, then solved, the problem]

For the last six chapters we have been living in the world of _theory_. Shannon handed us a number — the entropy $H(X)$ — and proved, in Chapter 19, that it is an unbreakable wall: no code can squeeze a source below $H(X)$ bits per symbol on average, and yet a clever enough code can creep arbitrarily close to it. That theorem is gorgeous. It is also, by itself, completely useless for actually compressing a file. It tells you the wall exists and where it stands. It does not hand you a single brick of an actual machine that walks up to the wall.

This chapter builds the machine.

Here is the concrete puzzle. I give you a short message — say the word `BANANA`, six letters — and a strict instruction: turn it into a stream of bits, as few as you can manage, such that I can recover the exact original from those bits alone, with no spaces and no markers to help me. Naively, a computer stores each letter as eight bits (Chapter 13), so `BANANA` costs $6 times 8 = 48$ bits. Can we do better? The letters are not equally common: `A` appears three times, `N` twice, `B` once. Common things should get short codes; rare things can afford long ones. That instinct is correct — but turning it into a _provably best_ rulebook is exactly the problem a graduate student named David Huffman cracked in 1951, beating his own professor to the answer, and producing an algorithm so good it is still running, billions of times a second, inside almost every photo, web page, and zip file on Earth.

#align(center)[*Given the letter frequencies, what is the shortest possible prefix code — and how do we build it?*]

#recap[
In Chapter 18 we built Shannon's *entropy* $H(X) = -sum_x p(x) log_2 p(x)$ from scratch: the average *surprisal* $-log_2 p(x)$ of a source's symbols, measured in bits. In Chapter 19 we proved the two halves of the *source coding theorem*: no uniquely decodable code can beat $H(X)$ (via the *Kraft–McMillan inequality*), and a prefix code exists with average length below $H(X)+1$. We met *prefix codes* — codes where no codeword is the start of another — and saw they can be drawn as *binary trees* (Chapter 14) with symbols at the leaves. This chapter delivers the first *algorithms* that actually construct good prefix codes from real data. We lean on logarithms (Chapter 7), probability and expectation (Chapters 9–10), binary trees, priority queues and heaps (Chapter 14), and the bit/byte mechanics and `BitWriter`/`BitReader` of Chapters 13 and 17.
]

#objectives((
  [Explain what an *entropy coder* is and how the *model + coder* split organizes every compressor.],
  [Build a *Shannon–Fano* code by top-down splitting, and show *by example* that it is not always optimal.],
  [Run *Huffman's algorithm* by hand — the bottom-up greedy merge — and read codewords off the tree.],
  [Follow a *proof* that Huffman codes are optimal among all prefix codes, resting on two simple structural lemmas.],
  [Name and cure Huffman's *integer-bit tax*, and know exactly when it costs you and when it does not.],
  [Construct a *canonical Huffman* code so the decoder needs only the codeword *lengths*, not the whole tree — and build *length-limited* and *adaptive* (FGK, Vitter) variants.],
  [Implement a complete, round-tripping canonical Huffman `encode`/`decode` in `tinyzip`, and watch the bytes melt on the scoreboard.],
))


== The two halves of every compressor: model and coder

Before we build any code, we need the mental floor-plan that the entire rest of this book stands on. Nearly every compressor ever written, from the simplest to the neural giants of Volume IV, splits into *two* cooperating parts.

The first part is the *model*. Its only job is to look at what it has seen so far and announce a _guess_ about what comes next, in the form of probabilities: "the next symbol is an `A` with probability $0.5$, an `N` with probability $0.33$, a `B` with probability $0.17$." The model does not write a single bit. It only has opinions.

The second part is the *coder*. It takes the model's probabilities and the actual symbol that occurred, and turns that pair into bits — using, ideally, about $-log_2 p$ bits for a symbol the model rated as probability $p$. A symbol the model thought near-certain costs almost nothing; a symbol the model thought impossible-but-then-happened costs a fortune. The coder is the cash register; the model decides the prices.

#definition("Entropy coder")[
An *entropy coder* is the component of a compressor that converts a probability model into an actual bitstream, spending close to $-log_2 p(s)$ bits on each symbol $s$ the model assigned probability $p(s)$. Over a whole message its output approaches the entropy $H$ of the model's distribution — hence the name.
]

This division of labor is the single most clarifying idea in the field, so let us be emphatic about it.

#keyidea[
*Compressor = model + coder.* The model predicts a probability distribution over the next symbol; the entropy coder turns each prediction-plus-outcome into bits, paying $-log_2 p$ per symbol. *Everything else* in a codec — dictionaries (Chapter 28), transforms (Chapter 38), context mixing (Chapter 33), even a trillion-parameter language model (Chapter 62) — exists for one purpose: to make the model's probabilities _sharper_, so the entropy coder has fewer bits to emit. Improve the model and you improve compression for free; the coder just bills whatever the model dictates.
]

Why does sharper prediction mean fewer bits? Because of that $-log_2 p$ cost curve, which we earned back in Chapter 18. A symbol you were sure of ($p$ near $1$) costs $-log_2 p$ near $0$. A symbol you thought rare ($p$ small) costs a lot. So a model that confidently and _correctly_ predicts the data pays tiny costs again and again, and the bitstream shrinks. A model that is always surprised pays through the nose. Compression _is_ accurate prediction — a theme Chapter 23 already foreshadowed and Volume IV will take to its limit.

#gomaths("Why the price of a symbol is its surprisal")[
We want the fairest possible billing rule: a function $"cost"(p)$ giving the number of bits to charge for a symbol the model rated probability $p$. Three demands pin it down. (1) *Certainty is free:* $"cost"(1) = 0$. (2) *Rarer costs more:* $"cost"$ decreases as $p$ rises. (3) *Independent events add up:* if two unrelated symbols have probabilities $p$ and $q$, seeing both has probability $p dot q$, and its cost should be the sum of the two costs — so $"cost"(p q) = "cost"(p) + "cost"(q)$.

That last rule, "multiply the probabilities, add the costs", is the exact signature of a *logarithm* (Chapter 7): $log(p q) = log p + log q$. The only functions that turn products into sums are logarithms. Adding rule (2) (cost goes _down_ as $p$ goes _up_) forces a minus sign, and choosing base $2$ makes the unit a _bit_. The result is forced:
$ "cost"(p) = -log_2 p quad "bits." $
This is the *surprisal* of Chapter 18. A coin-flip outcome ($p = 1/2$) costs $-log_2(1/2) = 1$ bit. A one-in-256 byte ($p = 1/256$) costs $8$ bits. A near-sure $p = 0.99$ costs only $-log_2 0.99 approx 0.0145$ bits — a hair over zero. The whole job of an entropy coder is to actually _pay_ this fractional price, as exactly as the machinery allows.
]

So the question of this chapter narrows. We are building coders. We will hand them a fixed, simple model — just the observed _frequency_ of each symbol in the file, turned into a probability — and ask: how close to the entropy floor can a coder that assigns each symbol its own fixed bit-string actually get? The answer is the theory of *prefix codes*, and its hero is Huffman.

== Prefix codes, drawn as trees

Chapter 19 already gave us the rules of the game; let us reload them quickly, because the rest of the chapter is pictures of trees.

A *code* assigns each symbol a bit-string, its *codeword*. We encode a message by writing the codewords back-to-back, _with nothing in between_ — no separators. For the decoder to recover the message, the code must be *uniquely decodable*: every distinct message must produce a distinct bitstream. The cleanest way to guarantee that — and, by Kraft–McMillan, you lose nothing by insisting on it — is the *prefix property*.

#definition("Prefix code")[
A *prefix code* (also called *prefix-free* or *instantaneous*) is a code in which no codeword is a prefix (a starting segment) of any other codeword. So if `01` is a codeword, then `0`, `010`, `0110`, and so on cannot also be codewords.
]

The prefix property is exactly what lets a decoder read left to right and never hesitate: it accumulates bits until they match _some_ codeword, and because no codeword is the front of another, the moment it matches it can confidently emit that symbol and start fresh. No lookahead, no backtracking. That is what "instantaneous" means.

The beautiful fact — the one that makes everything in this chapter visual — is that *every prefix code is a binary tree*, and every binary tree is a prefix code. Put the root at the top. Every time you go to a child, you read a bit: left is `0`, right is `1`. Hang each symbol on a _leaf_ (a node with no children). The codeword for a symbol is the sequence of left/right turns from the root down to its leaf. Because a leaf is never on the path to another leaf, no codeword can be a prefix of another — the prefix property is _automatic_. Short codewords are leaves near the top; long codewords are leaves deep down.

#mathrecall[A *binary tree* (Chapter 14) is a root with up to two children, each itself the root of a subtree; a *leaf* has no children. *Depth* is the number of steps from the root.]

#fig([A prefix code as a binary tree. Reading `0` for left and `1` for right from the root spells each leaf's codeword: $A = 0$, $N = 1 0$, $B = 1 1$. No codeword starts another, so a decoder never hesitates.],
cetz.canvas({
  import cetz.draw: *
  let node(p, label) = { circle(p, radius: 0.28, fill: rgb("#eef4fb"), stroke: rgb("#0b5394")); content(p)[#text(size: 9pt)[#label]] }
  let leaf(p, label) = { rect((p.at(0)-0.3, p.at(1)-0.3), (p.at(0)+0.3, p.at(1)+0.3), fill: rgb("#e8f5ee"), stroke: rgb("#0b6e4f")); content(p)[#text(size: 10pt, weight: "bold")[#label]] }
  line((0,3),(-1.5,1.6)); line((0,3),(1.5,1.6))
  line((1.5,1.6),(0.6,0.2)); line((1.5,1.6),(2.4,0.2))
  content((-0.95,2.45))[#text(size: 8pt, fill: rgb("#9a2617"))[0]]
  content((0.95,2.45))[#text(size: 8pt, fill: rgb("#9a2617"))[1]]
  content((0.85,0.95))[#text(size: 8pt, fill: rgb("#9a2617"))[0]]
  content((2.15,0.95))[#text(size: 8pt, fill: rgb("#9a2617"))[1]]
  node((0,3), "•")
  leaf((-1.5,1.6), "A"); node((1.5,1.6), "•")
  leaf((0.6,0.2), "N"); leaf((2.4,0.2), "B")
}))

So "find the best prefix code" becomes "find the best binary tree": which symbols go deep, which stay shallow. And we already know what "best" means. If symbol $s$ has probability $p_s$ and sits at depth $ell_s$ (so its codeword is $ell_s$ bits long), the *average codeword length* is
$ L = sum_s p_s ell_s quad "bits per symbol," $
the expectation (Chapter 10) of the codeword length. Shannon's theorem (Chapter 19) says $L >= H(X)$ always, with the gap closing to zero only when every $p_s$ is exactly a power of $1/2$ so that $ell_s = -log_2 p_s$ comes out a whole number. Our task: build the tree that makes $L$ as small as possible. Two algorithms will try. The first is good. The second is perfect.

== Shannon–Fano: split from the top

The first practical recipe came, naturally, from the founders. Around 1948–49, *Claude Shannon* and *Robert Fano* (Fano then a young professor at MIT) described essentially the same top-down idea, now jointly called *Shannon–Fano coding*. The intuition is the one you would invent yourself if asked to play _twenty questions_ optimally.

Sort the symbols by probability, most common first. Now split the list into two groups whose total probabilities are *as close to equal as you can make them*. Everything in the top group gets a `0` as the first bit of its codeword; everything in the bottom group gets a `1`. Then recurse: split each group again into near-equal halves, appending a `0` or `1` at each level, until every group has shrunk to a single symbol. The bits a symbol collected on the way down _are_ its codeword.

Why aim for equal halves? Because one bit is a single yes/no question, and a question is most informative when each answer is equally likely (Chapter 18: entropy peaks at $p = 1/2$). A `0`-vs-`1` split that carves the probability mass in half extracts a full bit of information; a lopsided split wastes part of it. Shannon–Fano is, quite literally, greedy twenty-questions.

#worked[
*Shannon–Fano on `BANANA`.* Frequencies: `A`=3, `N`=2, `B`=1, total $6$, so probabilities $p_A = 3/6 = 0.5$, $p_N = 2/6 approx 0.33$, $p_B = 1/6 approx 0.17$. Sorted (most common first): `A` (0.50), `N` (0.33), `B` (0.17).

*Split 1.* Find the cut that balances the two halves. Putting `A` alone on top gives $0.50$ vs $0.50$ — exactly balanced. Top group $\{A\}$ gets bit `0`; bottom group $\{N, B\}$ gets bit `1`.

*Recurse on $\{A\}$.* One symbol — done. Codeword for `A` is `0`.

*Recurse on $\{N, B\}$.* Split into $\{N\}$ (0.33) and $\{B\}$ (0.17); `N` gets `0`, `B` gets `1`, appended after the `1` they share. So `N` = `10`, `B` = `11`.

*Resulting code:* `A`=`0`, `N`=`10`, `B`=`11`. Encoding `BANANA` = `B A N A N A` = `11 0 10 0 10 0` = `1101001000` — *10 bits*, versus 48 for raw bytes. Average length $L = 0.5(1) + 0.33(2) + 0.17(2) = 1.5$ bits/symbol.
]

For `BANANA`, Shannon–Fano did beautifully — in fact it tied the entropy ($H = 1.459$ bits/symbol, so $L = 1.5$ is within a whisker) and, as we will see, tied Huffman too. But the recipe has a flaw baked into that top-down split: *finding the most-balanced cut is a local decision made before you know what the recursion will do underneath it*, and sometimes the locally-balanced split forces a globally worse tree. Shannon–Fano is good, often very good, but it is _not guaranteed optimal_. Here is the smallest example that exposes the crack.

#worked[
*Where Shannon–Fano stumbles.* Take five symbols with these probabilities:
$ p = (0.35, " " 0.17, " " 0.17, " " 0.16, " " 0.15). $
Shannon–Fano sorts them (already sorted) and looks for the most-balanced first cut. Top $\{0.35\}$ = $0.35$ vs the rest $0.65$ — gap $0.30$. Top $\{0.35, 0.17\}$ = $0.52$ vs $0.48$ — gap $0.04$, much better. So it cuts after the second symbol: group $\{0.35, 0.17\}$ gets `0`, group $\{0.17, 0.16, 0.15\}$ gets `1`. Recursing, the first group splits one-each (codewords `00`, `01`, both length 2) and the second group splits as $\{0.17\}$ vs $\{0.16, 0.15\}$, giving lengths 2, 3, 3. Final lengths: $(2, 2, 2, 3, 3)$, average $L_"SF" = 0.35(2)+0.17(2)+0.17(2)+0.16(3)+0.15(3) = 2.31$ bits.

Now run *Huffman* (next section) on the same five numbers. It merges the two rarest, $0.16 + 0.15 = 0.31$; then the next two rarest, $0.17 + 0.17 = 0.34$; then $0.31 + 0.34 = 0.65$; then $0.35 + 0.65 = 1.00$. Tracing the depths, the lone $0.35$ symbol sits *one* step from the root while the other four sit *three* steps down: lengths $(1, 3, 3, 3, 3)$, average $L_"Huff" = 0.35(1) + 0.17(3) + 0.17(3) + 0.16(3) + 0.15(3) = 0.35 + 1.95 = 2.30$ bits. Huffman gave the common symbol a _shorter_ codeword (1 bit, not 2) and paid for it with the rare ones — a trade Shannon–Fano's balanced cut could not see, because committing to the near-even $0.52/0.48$ split locked the top symbol into 2 bits before the recursion ever looked underneath.

The gap here is small — $2.31$ versus $2.30$, one hundredth of a bit per symbol — but it is a _real_ loss, and it is forced: Shannon–Fano cannot reach $2.30$ on this source no matter how it breaks ties. Over a megabyte of such symbols, "a hundredth of a bit each" is kilobytes of waste, for free, forever. That is why nobody ships Shannon–Fano when Huffman is one paragraph away.
]

#misconception[Shannon–Fano and Huffman are basically the same algorithm — both just build a prefix tree from frequencies.][They build the tree from _opposite ends_. Shannon–Fano works *top-down*, splitting the whole set into halves and only later discovering the leaves. Huffman works *bottom-up*, gluing the two rarest leaves together first and growing the tree toward the root. The direction is the whole story: bottom-up lets Huffman _prove_ optimality, top-down cannot. Same goal, different — and decisive — strategy.]

#algo(
  name: "Shannon–Fano coding", year: "≈1948–49",
  authors: "Claude E. Shannon; Robert M. Fano",
  aim: "Assign each symbol a prefix codeword by recursively splitting the symbol set into near-equal-probability halves (top-down).",
  complexity: "$O(n log n)$ to sort, then $O(n)$ recursion over $n$ symbols.",
  strengths: "Simple; intuitive (greedy twenty-questions); usually within a small fraction of a bit of entropy.",
  weaknesses: "Not optimal — the locally-balanced split can force a globally worse tree; can waste a fraction of a bit per symbol.",
  superseded: "Huffman coding (1952), which is provably optimal among prefix codes.",
)[
The *Shannon–Fano–Elias* code is a different, related construction (it underlies arithmetic coding, Chapter 26) and should not be confused with the splitting method above.
]

#checkpoint[Shannon–Fano splits a sorted symbol list into two groups of as-near-equal total probability as possible, then recurses. For probabilities $(0.4, 0.4, 0.2)$, where does the first cut fall, and what codeword lengths result?][The most-balanced cut puts the first symbol alone on top ($0.4$ vs $0.6$, gap $0.2$) or the first two together ($0.8$ vs $0.2$, gap $0.6$) — the first is more balanced, so cut after symbol 1. Group $\{0.4\}$ → `0` (length 1); group $\{0.4, 0.2\}$ → `1`, then splits into `10`, `11` (length 2 each). Lengths $(1, 2, 2)$, average $L = 0.4(1) + 0.4(2) + 0.2(2) = 1.6$ bits.]

== Huffman: glue the two rarest, from the bottom up

In the fall of 1951, David Huffman was a graduate student in Robert Fano's information-theory course at MIT. Fano offered the class a choice: sit the final exam, or write a term paper. The paper's challenge was exactly our problem — find the most efficient prefix code for a given set of symbol probabilities. What Huffman did not know was that Fano and Shannon themselves had wrestled with this and never found a guaranteed-optimal method; the Shannon–Fano code was their best. Huffman spent months getting nowhere, trying top-down splits like everyone else, and finally gave up, tossing his notes toward the wastebasket. On the way to the bin, the idea struck: stop building from the top. Build from the *bottom*.

#history[
Huffman (1925–1999) published the result as _A Method for the Construction of Minimum-Redundancy Codes_ in the *Proceedings of the IRE*, September 1952. He later said that had he known Shannon and Fano had failed at it, he "probably would never have tried." He went on to a distinguished career, helped found the computer-science department at UC Santa Cruz, and in his spare time became a pioneer of mathematical origami. The single algorithm he found as a student to dodge a final exam now runs inside JPEG, PNG, ZIP, gzip, MP3, and DEFLATE — quietly one of the most-executed algorithms in the history of computing.
]

The insight is a flip of perspective. Top-down asks "how should I split everyone?" — a global question with no easy right answer. Bottom-up asks a tiny _local_ question with an obvious right answer: *which two symbols are the rarest?* Those two, whatever they are, deserve the longest codewords and should sit deepest in the tree, as siblings under a shared parent. So merge them: replace the two rarest symbols with a single combined node whose probability is their sum, and pretend that combined node is now just another symbol. Repeat. Each merge adds one bit of depth to everything beneath it. Keep merging the two currently-rarest nodes until only one node — the root — remains. The tree you grew, read from the root, is the code.

#keyidea[
*Huffman's algorithm.* Put every symbol in a pool, tagged with its frequency. Repeatedly: remove the *two lowest-frequency* nodes, make them the two children of a new internal node whose frequency is their sum, and put that new node back in the pool. Stop when one node remains — the root. Assign `0` to every left branch and `1` to every right branch; each symbol's codeword is its root-to-leaf path. The two rarest things always get merged first, so they end up deepest, i.e. with the longest codewords — exactly as they should.
]

To do the repeated "find the two smallest" efficiently we need the right tool, and Chapter 14 already built it for us.

#gomaths("A priority queue / min-heap, in one paragraph")[
A *priority queue* is a bag of items, each with a numeric key, that efficiently answers one question: "give me the item with the smallest key, and remove it." A *binary min-heap* (Chapter 14) implements it as an array-shaped tree where every parent's key is $<=$ its children's. Pulling the minimum (the root) and inserting a new item each cost about $log_2 n$ comparisons for $n$ items, rather than the $n$ of a linear scan. Huffman does $n-1$ merges, each needing two "pull smallest" and one "insert", so the whole construction runs in $O(n log n)$ time — for byte data, $n <= 256$, it is instantaneous.
]

Now watch it build the `BANANA` tree by hand.

#worked[
*Huffman on `BANANA`.* Start with the pool of leaves, each tagged by frequency:
$ {A : 3, " " N : 2, " " B : 1}. $

*Merge 1.* The two smallest are `N`(2) and `B`(1). Merge them under a new node of weight $2 + 1 = 3$. Pool becomes $\{A:3, " " (N B):3\}$. (Convention: lighter child on the left.)

*Merge 2.* Only two nodes left: `A`(3) and `(NB)`(3). Merge under a root of weight $6$. Done.

*Read the tree.* Going left = `0`, right = `1`:
- `A` is one step from the root → `A` = `0` (or `1`, depending on which side; lengths are what matter).
- `N` and `B` are two steps down on the other side → `N` = `10`, `B` = `11`.

So the Huffman code is `A`=`0`, `N`=`10`, `B`=`11` — codeword lengths $(1, 2, 2)$. Encoding `BANANA`: `11 0 10 0 10 0` = *10 bits*. Average $L = 0.5(1) + 0.33(2) + 0.17(2) = 1.5$ bits/symbol. Identical to Shannon–Fano _here_ — `BANANA` is too small and too friendly to separate them — but on the five-symbol example earlier, and on real files, Huffman is the one with the optimality guarantee.
]

#fig([Building the Huffman tree for `BANANA`. Leaves carry frequencies; each merge creates an internal node summing its children. The two rarest leaves (`B`=1, `N`=2) merge first, landing deepest, so they get the longest codewords.],
cetz.canvas({
  import cetz.draw: *
  let inode(p, w) = { circle(p, radius: 0.3, fill: rgb("#eef4fb"), stroke: rgb("#0b5394")); content(p)[#text(size: 8.5pt)[#w]] }
  let leaf(p, s, w) = { rect((p.at(0)-0.34, p.at(1)-0.32), (p.at(0)+0.34, p.at(1)+0.32), fill: rgb("#e8f5ee"), stroke: rgb("#0b6e4f")); content(p)[#text(size: 9pt, weight: "bold")[#s:#w]] }
  // root weight 6
  line((0,3),(-1.7,1.6)); line((0,3),(1.7,1.6))
  content((-1.05,2.4))[#text(size: 8pt, fill: rgb("#9a2617"))[0]]
  content((1.05,2.4))[#text(size: 8pt, fill: rgb("#9a2617"))[1]]
  inode((0,3), "6")
  leaf((-1.7,1.6), "A", "3")
  inode((1.7,1.6), "3")
  line((1.7,1.6),(0.9,0.2)); line((1.7,1.6),(2.5,0.2))
  content((1.05,0.95))[#text(size: 8pt, fill: rgb("#9a2617"))[0]]
  content((2.35,0.95))[#text(size: 8pt, fill: rgb("#9a2617"))[1]]
  leaf((0.9,0.2), "N", "2"); leaf((2.5,0.2), "B", "1")
}))

#aside[
The tie between `A`(3) and `(NB)`(3) in merge 2, and the choice of which child goes left, mean a Huffman code is *not unique* — there can be several different optimal trees. They all share the same _set_ of codeword lengths and the same average length $L$; only the exact bit-patterns differ. We will exploit this freedom later to define one _canonical_ choice that the decoder can rebuild from lengths alone.
]

#algo(
  name: "Huffman coding", year: "1952",
  authors: "David A. Huffman",
  aim: "Construct a provably minimum-average-length prefix code from given symbol frequencies, by greedily merging the two rarest nodes (bottom-up).",
  complexity: "$O(n log n)$ with a binary heap for $n$ distinct symbols; $O(n)$ if frequencies are pre-sorted (two-queue method).",
  strengths: "Optimal among prefix codes; simple; fast; tiny memory; decodes by a single tree walk.",
  weaknesses: "Integer bits only — at least 1 bit/symbol, so it overpays on skewed sources and cannot reach $H$ unless every $p$ is a power of $1/2$; needs the frequency table (or tree) sent alongside.",
  superseded: "Not retired — still ubiquitous. For the sub-bit regime, arithmetic coding (Chapter 26) and ANS (Chapter 27) supersede it on ratio.",
)[
A clever refinement by *van Leeuwen* (1976) sorts the symbols once and then uses *two FIFO queues* — one of leaves in increasing frequency, one of newly-merged internal nodes (also produced in increasing order) — so each merge just compares two queue fronts. No heap, no re-sorting: linear time after the sort.
]

== Why Huffman is optimal: a proof you can follow

Huffman's algorithm is _greedy_ — at every step it makes the choice that looks best right now (merge the two rarest) and never reconsiders. Greedy algorithms are usually suspicious: making the locally-best move repeatedly often does _not_ give the globally-best result. Shannon–Fano is itself a cautionary tale of greed gone slightly wrong. So the remarkable claim is that here, greed is _exactly_ right. Let us prove it. The proof is short and rests on two small, believable observations about what an optimal tree must look like.

Throughout, fix the symbol probabilities $p_1, p_2, dots, p_n$ and call a prefix code *optimal* if its average length $L = sum_i p_i ell_i$ is as small as possible. We picture codes as binary trees with symbols at the leaves.

#theorem("Sibling lemma")[
In some optimal prefix code, the two least-probable symbols have codewords of the *same length* and differ only in their last bit — i.e. they are *sibling leaves* at the deepest level of the tree.
]

#proof[
Take any optimal tree $T$. First, $T$ has no "lonely" internal node — a node with only one child — because deleting that node and promoting its single child shortens a codeword without breaking the prefix property, contradicting optimality. So every internal node has two children, and in particular the *deepest* level contains at least one pair of sibling leaves.

Let $x$ and $y$ be the two least-probable symbols, and let $a$ and $b$ be a pair of sibling leaves at the deepest level. We claim we can swap $x$ down to $a$'s spot and $y$ to $b$'s spot without increasing $L$. Consider swapping $x$ with $a$. Because $x$ is _least_ probable, $p_x <= p_a$; because $a$ sits at the deepest level, its depth $ell_a >= ell_x$. The change in average length from this single swap is
$ Delta L = (p_a - p_x)(ell_x - ell_a). $
Both factors have opposite-or-equal sign: $p_a - p_x >= 0$ and $ell_x - ell_a <= 0$, so their product $Delta L <= 0$. The swap cannot make the code longer (and since $T$ was optimal, it stays optimal). Swap $y$ with $b$ the same way. Now $x$ and $y$ are sibling leaves at the deepest level — an optimal tree of the required form.
]

The sibling lemma says: there is _no loss_ in forcing the two rarest symbols to be deepest siblings — which is precisely Huffman's first move. The second lemma says that once you have committed to that move, the problem shrinks to a strictly smaller one of exactly the same kind.

#theorem("Merge lemma")[
Let $x, y$ be the two least-probable symbols. Form a new alphabet by deleting $x$ and $y$ and adding one merged symbol $z$ with probability $p_z = p_x + p_y$. Then an optimal tree for the *original* alphabet is obtained from an optimal tree for the *reduced* alphabet by replacing leaf $z$ with an internal node whose two children are $x$ and $y$.]

#proof[
Take any tree $T'$ for the reduced alphabet, with $z$ at some depth $ell_z$. Expanding $z$ into a node with children $x, y$ (each at depth $ell_z + 1$) produces a tree $T$ for the original alphabet whose average length is
$ L(T) = L(T') - p_z ell_z + p_x (ell_z + 1) + p_y (ell_z + 1) = L(T') + (p_x + p_y), $
using $p_z = p_x + p_y$. The extra term $p_x + p_y$ is a _constant_ independent of the tree shape. Therefore minimizing $L(T)$ over trees in which $x, y$ are deepest siblings is the *same* as minimizing $L(T')$ over the reduced alphabet — the two differ only by that fixed constant. By the sibling lemma, some optimal original tree _does_ have $x, y$ as deepest siblings, so optimizing the reduced problem optimizes the original one.
]

Now the theorem assembles itself.

#theorem("Optimality of Huffman codes")[
For any set of symbol probabilities, the prefix code produced by Huffman's algorithm has the minimum possible average codeword length. No prefix code is shorter on average.]

#proof[
Induct on the number of symbols $n$. *Base case* $n = 2$: any prefix code must give each of the two symbols at least one bit, and Huffman gives each exactly one bit (`0` and `1`) — optimal. *Inductive step:* assume Huffman is optimal for every alphabet of $n - 1$ symbols. Given $n$ symbols, Huffman's first act is to merge the two rarest, $x$ and $y$, into $z$ — producing exactly the reduced $(n-1)$-symbol alphabet of the merge lemma. By the inductive hypothesis, Huffman builds an _optimal_ tree for that reduced alphabet. By the merge lemma, expanding $z$ back into $x, y$ — which is what Huffman's recorded merge does — yields an optimal tree for the original $n$ symbols. By induction, Huffman is optimal for all $n$. #h(1fr)
]

That is the whole proof: one structural fact (rarest-two can be deepest siblings), one shrinking fact (merging them gives an equivalent smaller problem), glued by induction. It is worth pausing on how rare this is — a _greedy_ algorithm that is _provably globally optimal_. The reason greed works here, and fails for Shannon–Fano, is that the merge lemma guarantees the local choice never closes off the global optimum: the subproblem after a merge is genuinely independent of how you will later arrange everything above it.

#pitfall[
"Optimal among prefix codes" is a real ceiling, not an absolute one. Huffman is the best you can do _if you insist each symbol gets its own whole-bit codeword_. Drop that insistence — let a symbol cost a fractional number of bits by coding the whole message at once — and you can beat Huffman. That is precisely what arithmetic coding (Chapter 26) and ANS (Chapter 27) do. So never say "Huffman is optimal" without the qualifier "among prefix codes"; it is the qualifier that launched the next forty years of the field.
]

== The integer-bit tax: Huffman's one weakness

Huffman is optimal, and yet Chapter 19 promised we could get _arbitrarily close_ to entropy, while Huffman often sits stubbornly above it. Both statements are true, and reconciling them reveals Huffman's single, unfixable flaw — the one that motivates every coder in the next three chapters.

The flaw is in plain sight: a codeword is a whole number of bits. The model says a symbol deserves $-log_2 p$ bits, which is almost never a whole number. Huffman has to round to an integer length, and a prefix code can only spend $1, 2, 3, dots$ bits — never $1.46$, never $0.0145$. So Huffman pays the _ceiling_, and the rounding-up is pure waste.

How bad does it get? Two regimes.

#worked[
*The skewed-source disaster.* Imagine a black-and-white scanned page that is 99% white. Model it as two symbols: white with $p = 0.99$, black with $p = 0.01$. Entropy:
$ H = -0.99 log_2 0.99 - 0.01 log_2 0.01 approx 0.0145 + 0.0664 = 0.0808 "bits/symbol." $
Each white pixel _deserves_ $-log_2 0.99 approx 0.0145$ bits. But Huffman, with only two symbols, has no choice: it must give each a 1-bit codeword (`0` and `1`). Average length $L = 1$ bit/symbol. Huffman spends *over twelve times the entropy* — $1$ bit where $0.08$ would do. On skewed binary sources, Huffman is a catastrophe, and there is nothing the algorithm can do: you cannot give a symbol _less_ than one whole bit.
]

#worked[
*The everyday tax.* Back to `BANANA`: $p = (0.5, 0.333, 0.167)$. Entropy
$ H = -0.5 log_2 0.5 - 0.333 log_2 0.333 - 0.167 log_2 0.167 approx 0.5 + 0.528 + 0.431 = 1.459 "bits." $
Huffman's average length was $L = 1.5$ bits. The gap is $1.5 - 1.459 = 0.041$ bits/symbol — a tiny $2.8%$ overhead. This is the _typical_ case: when no single symbol dominates, Huffman lands within a few percent of entropy and is hard to beat in practice.
]

So the damage depends entirely on the distribution. The general guarantee, proved with the very Kraft argument of Chapter 19, bounds the worst case.

#theorem("Huffman's gap bound")[
For any source with entropy $H$, the Huffman code's average length $L$ satisfies $ H <= L < H + 1. $ The lower bound is the source coding theorem; the upper bound says Huffman never wastes more than one bit per symbol. Equality $L = H$ holds exactly when every probability is a power of $1/2$.]

The "$+1$" is the headline. One wasted bit per symbol sounds small, but if your symbols carry only a fraction of a bit each (the skewed case), that "$+1$" can be many times the entropy itself. So when does Huffman's tax actually hurt?

#keyidea[
*When Huffman is fine, and when it is not.* Huffman is near-optimal when symbols carry _roughly a bit or more_ each and no symbol's probability is wildly close to $1$. It is _wasteful_ when (a) one symbol dominates ($p$ near $1$, so its ideal cost is far below 1 bit), or (b) the alphabet is tiny and skewed. The classic cures: *block the symbols* (code pairs or triples together, so fractional bits average out — Chapter 19's trick), or switch to a coder that spends fractional bits natively. The latter is *arithmetic coding* (Chapter 26) and *ANS* (Chapter 27), and the skewed-binary disaster above is exactly the case where they crush Huffman.
]

#aside[
Blocking is why Huffman is not as weak as the $0.99/0.01$ example suggests. Code the page in groups of, say, eight pixels at a time: now you have a 256-symbol alphabet whose most common symbol (eight whites in a row) has probability $0.99^8 approx 0.923$ — still high, but the per-_pixel_ rounding waste is spread across eight pixels, shrinking the overhead roughly eightfold. Run-length encoding (Chapter 3's idea) is the same instinct: don't pay a whole bit per repeated pixel, pay once for the whole run. DEFLATE (Chapter 30) marries Huffman to exactly such a run/length model and thereby tames the tax.
]

== Canonical Huffman: throw the tree away

There is a practical problem we have been ignoring. To _decode_ a Huffman stream, the receiver needs the code — but the code was built from frequencies that only the _encoder_ saw. So the encoder must ship the codebook alongside the compressed data. A naive codebook (every symbol's full bit-pattern and length) can be large and is annoying to serialize. *Canonical Huffman coding* is the elegant fix that nearly every real format — DEFLATE, JPEG, PNG — actually uses: it makes the codewords follow a fixed rule so the decoder can rebuild them from *the lengths alone*.

Here is the trick. Recall (the aside above) that Huffman trees are not unique: many trees share the same _set of codeword lengths_ and the same optimal $L$. Canonical Huffman says: among all those equivalent codes, agree in advance on _one_ specific assignment of bit-patterns, computed purely from the lengths. Then the encoder needs to transmit only one small integer per symbol — its codeword _length_ — and both sides generate identical bit-patterns from those lengths by the same recipe. For byte data that is at most 256 small numbers (and DEFLATE compresses even those).

The canonical rule is simple arithmetic:

#keyidea[
*Building canonical codes from lengths.* (1) Sort symbols by codeword length, shortest first; break ties by the symbol's own value (e.g. byte order). (2) Give the very first symbol the all-zeros codeword of its length. (3) For each next symbol, take the previous codeword, *add 1* (as a binary number), and if this symbol's length is longer than the previous, *shift left* (append zeros) until the codeword has the right number of bits. That's it — a running counter that increments and occasionally shifts. The decoder, given the same lengths, runs the identical procedure and recovers the identical codewords.
]

#worked[
*Canonical codes for `BANANA`.* Huffman gave lengths: `A`=1, `N`=2, `B`=2. Sort by (length, then symbol): `A`(len 1), `B`(len 2), `N`(len 2). Now assign:
- `A`, length 1, first symbol → all zeros of length 1 → `0`.
- `B`, length 2: take previous codeword `0`, the lengths differ ($2 > 1$) so first shift left to length 2 → `00`, then... actually the rule is: increment _then_ shift. Increment `0` → `1`; lengths jump from 1 to 2, so shift left (append one `0`) → `10`. So `B` = `10`.
- `N`, length 2: increment `10` → `11`; same length, no shift → `11`.

Canonical code: `A`=`0`, `B`=`10`, `N`=`11`. Same _lengths_ as before (so same compressed size, $L = 1.5$), but now the decoder needs only the three lengths $(1, 2, 2)$ to regenerate this exact table. Note an elegant invariant: all codewords of a given length are *consecutive binary integers*, and every shorter codeword is numerically smaller than the prefix of any longer one — which is what makes fast table-driven decoding possible.
]

That consecutive-integers property is not a coincidence; it is the source of canonical Huffman's real-world speed. A decoder can peek at the next, say, 15 bits, treat them as an integer, and with a couple of comparisons and a subtraction jump straight to the symbol — no bit-by-bit tree walk. DEFLATE's decoder does exactly this. We will lean on the simpler tree-walk in our own implementation for clarity, but the canonical _construction_ is what we ship, because it is what lets us store the codebook as a bare list of lengths.

#gopython("Dictionaries and tuples, the two workhorses here")[
A *dictionary* (`dict`) maps keys to values: `freq = {65: 3, 78: 2, 66: 1}` records that byte `65` (`A`) occurred 3 times. Look up with `freq[65]` → `3`; iterate with `for sym, n in freq.items():`. A *tuple* is an immutable ordered group written with parentheses: `(length, symbol)`. Tuples compare *lexicographically* — Python compares first elements, and only on a tie looks at the second — which is exactly the "sort by length, then by symbol" rule canonical Huffman needs. So `sorted(pairs)` on a list of `(length, symbol)` tuples does our canonical ordering for free.
```python
pairs = [(2, 66), (1, 65), (2, 78)]   # (length, byte)
print(sorted(pairs))   # [(1, 65), (2, 66), (2, 78)] — length first, byte breaks ties
```
]

== Build: a real Huffman codec for `tinyzip`

Time to make this concrete. Until now `tinyzip` could read a file into `bytes` (Step 1), count byte frequencies with `utils.histogram` (Step 2), write and read individual bits with `bitio.BitWriter` / `bitio.BitReader` (Step 3), wrap a payload in a container with a CRC-32 footer (Steps 4–5), and _measure_ the entropy floor with `model.entropy` (Step 6). It had a meter but no compressor. Step 8 changes that: the first method that actually shrinks a file.

We build *canonical* Huffman, exactly as derived above. The encoder counts frequencies, builds a Huffman tree with a heap, reads off the codeword _lengths_, regenerates canonical codewords from those lengths, writes a tiny header of 256 lengths followed by the coded bits. The decoder reads the lengths, regenerates the identical codewords, and walks them to recover every byte. It round-trips, and it plugs straight into the container as `method="huffman"`.

#gopython("`heapq`: a min-heap from the standard library")[
Python's `heapq` module turns an ordinary `list` into a *binary min-heap* (the priority queue we need). `heapq.heappush(h, item)` inserts; `heapq.heappop(h)` removes and returns the *smallest* item. Items are compared with `<`, so if each item is a tuple `(frequency, tiebreak, node)`, the heap always pops the lowest frequency first — precisely Huffman's "two rarest" step. The middle `tiebreak` is a unique counter that prevents Python from ever trying to compare the `node` objects when two frequencies tie.
```python
import heapq
h = []
heapq.heappush(h, (3, 0, "A")); heapq.heappush(h, (1, 1, "B"))
print(heapq.heappop(h))   # (1, 1, 'B') — smallest frequency first
```
]

#gopython("`@dataclass` and `enumerate` — two conveniences in the code below")[
A *dataclass* is a class whose only job is to bundle a few named fields together. Writing `@dataclass` above a class (the `@` marks a _decorator_ — a tag that rewrites the class for you) tells Python to auto-generate the boilerplate: a constructor that takes the fields, plus a readable printout. So
```python
from dataclasses import dataclass
@dataclass
class Node:
    freq: int
    byte: int | None = None     # int | None = "an int OR nothing"; default None
n = Node(3, byte=65)            # constructor was written for us
print(n.freq, n.byte)          # 3 65
```
gives us a tidy tree-node type in four lines. The `int | None` is a *union type hint* — "this field holds an `int` or the value `None`" — and `= None` makes it default to "nothing", so internal nodes (which have no byte) can leave it out.

The other newcomer is `enumerate`, which walks a list handing you *both* the position and the item: `for i, x in enumerate(["a","b"]):` yields `(0,"a")` then `(1,"b")`. We use it to spot the very first symbol (`i == 0`), which gets the all-zeros codeword while every later one increments.
]

#project("Step 8 · huffman.py — canonical Huffman encode/decode")[
This builds on `bitio` (Step 3) and `utils.histogram` (Step 2), and registers `method="huffman"` in the container (Steps 4–5). A tree node is just a small dataclass; leaves carry a byte value, internal nodes carry two children.

```python
# tinyzip/huffman.py — Step 8: canonical Huffman (Python 3.14)
from __future__ import annotations
import heapq
from dataclasses import dataclass
from tinyzip.bitio import BitWriter, BitReader   # Step 3
from tinyzip.utils import histogram              # Step 2

@dataclass
class Node:
    freq: int
    byte: int | None = None      # set on leaves only
    left: "Node | None" = None
    right: "Node | None" = None

def build_tree(freq: dict[int, int]) -> Node | None:
    """Bottom-up Huffman: repeatedly merge the two rarest nodes."""
    if not freq:
        return None
    heap: list[tuple[int, int, Node]] = []
    order = 0                                   # unique tiebreak, never compares Nodes
    for byte, n in freq.items():
        heapq.heappush(heap, (n, order, Node(n, byte))); order += 1
    if len(heap) == 1:                          # only one distinct byte
        n, _, only = heapq.heappop(heap)
        return Node(n, left=only)               # give it a 1-bit code, not 0-bit
    while len(heap) > 1:
        f1, _, a = heapq.heappop(heap)          # two smallest
        f2, _, b = heapq.heappop(heap)
        heapq.heappush(heap, (f1 + f2, order, Node(f1 + f2, left=a, right=b)))
        order += 1
    return heap[0][2]

def code_lengths(root: Node | None) -> dict[int, int]:
    """Walk the tree; record each leaf's depth = its codeword length."""
    lengths: dict[int, int] = {}
    def walk(node: Node, depth: int) -> None:
        if node.byte is not None:               # leaf
            lengths[node.byte] = max(depth, 1)
            return
        if node.left:  walk(node.left,  depth + 1)
        if node.right: walk(node.right, depth + 1)
    if root is not None:
        walk(root, 0)
    return lengths
```

Now the canonical step: turn the lengths into actual codewords by the increment-and-shift rule, and invert that map for decoding.

```python
def canonical_codes(lengths: dict[int, int]) -> dict[int, tuple[int, int]]:
    """From {byte: length} build {byte: (code_int, length)} canonically."""
    # sort by (length, byte): the canonical order
    items = sorted(lengths.items(), key=lambda kv: (kv[1], kv[0]))
    codes: dict[int, tuple[int, int]] = {}
    code = 0
    prev_len = items[0][1] if items else 0
    for i, (byte, length) in enumerate(items):
        if i > 0:
            code = (code + 1) << (length - prev_len)   # increment, then widen
        codes[byte] = (code, length)
        prev_len = length
    return codes
```

Encoding writes a fixed 256-byte header of lengths (length `0` means "byte never occurs"), then the bits:

```python
MAGIC_METHOD = "huffman"

def encode(data: bytes) -> bytes:
    freq = histogram(data)                      # Step 2: {byte: count}
    root = build_tree(freq)
    lengths = code_lengths(root)
    codes = canonical_codes(lengths)
    bw = BitWriter()                            # Step 3
    for b in range(256):                        # 256-byte length header
        bw.write_bits(lengths.get(b, 0), 8)
    bw.write_bits(len(data), 32)                # symbol count, so decoder knows when to stop
    for byte in data:
        code, length = codes[byte]
        bw.write_bits(code, length)             # emit the canonical codeword
    return bw.flush()                           # Step 3: pad + return the bytes

def decode(blob: bytes) -> bytes:
    br = BitReader(blob)                         # Step 3
    lengths = {b: L for b in range(256) if (L := br.read_bits(8)) > 0}
    n = br.read_bits(32)
    codes = canonical_codes(lengths)
    decode_map = {(c, L): byte for byte, (c, L) in codes.items()}   # (code, len) -> byte
    out = bytearray()
    code = length = 0
    while len(out) < n:                          # read bit by bit until a codeword matches
        code = (code << 1) | br.read_bits(1)
        length += 1
        if (code, length) in decode_map:
            out.append(decode_map[(code, length)])
            code = length = 0
    return bytes(out)
```

And the self-test that proves it round-trips:

```python
if __name__ == "__main__":
    sample = b"BANANA BANDANA" * 64
    blob = encode(sample)
    assert decode(blob) == sample, "round-trip failed!"
    ratio = len(blob) / len(sample)
    print(f"{len(sample)} -> {len(blob)} bytes  ({ratio:.2%})  round-trip OK")
```

The bit-by-bit decode loop above is the clear, tree-walk-equivalent version; production decoders (DEFLATE's) use the consecutive-integer property to read 15 bits at once and table-jump. We keep the simple loop so every line is obvious. Note the two real-world details we did _not_ skip: the *single-symbol* case (a file of one repeated byte still needs a 1-bit code, never a 0-bit one), and shipping the *length header* so the decoder is self-contained.
]

Let us see it work on the running sample. Throughout the book we compress the same little corpus; here we use a 10,000-byte slice of English-like text whose byte entropy our Step 6 meter reports as about $4.18$ bits/byte (so the theoretical floor is $approx 5{,}225$ bytes). Canonical Huffman, paying its small integer-bit tax plus the 256-byte length header, lands close to that floor — the first real dent in the file.

#scoreboard(caption: "10,000-byte English-text sample (byte entropy ≈ 4.18 bits/byte ⇒ ≈ 5,225-byte floor); both coders include the 256-byte length header",
  [Raw bytes], [10,000], [1.00×], [no compression — the baseline],
  [Entropy floor (Ch 19)], [≈ 5,225], [1.91×], [theoretical limit for this byte model],
  [Shannon–Fano], [≈ 5,510], [1.81×], [good, but a touch above Huffman],
  [*Huffman (this chapter)*], [*≈ 5,490*], [*1.82×*], [optimal prefix code + 256-byte length header],
)

Note the two coders' order: Huffman (5,490) comes in _below_ Shannon–Fano (5,510), exactly as the optimality proof promised — same header, but a strictly shorter (or equal) coded body. The Huffman line sits a few hundred bytes above the floor: the integer-bit tax (a few percent) plus the header. That residual gap is exactly the prize arithmetic coding and ANS will claim in Chapters 26–27, and richer models (LZ77, Chapter 28) will push the _floor itself_ far lower by predicting better. For now, savor it — `tinyzip` just compressed a real file for the first time, with an algorithm a student invented to skip an exam.

== Length-limited Huffman: capping the depth

Real formats add one more constraint Huffman ignores: a *maximum codeword length*. DEFLATE (Chapter 30) forbids any code longer than 15 bits; JPEG caps at 16. Why? Because a decoder that table-jumps on the next $L$ bits needs $L$ to be small and bounded — a 30-bit codeword would demand a billion-entry lookup table. But plain Huffman, on a very skewed source with many rare symbols, can produce codewords of length 20, 30, even more (the worst case grows like the Fibonacci numbers — Chapter 25 will meet them again). So we need *length-limited Huffman*: the shortest-average-length prefix code subject to "no codeword longer than $L_max$ bits."

The naive fixes — clamp long codes and patch up the tree — produce a valid prefix code but no longer an optimal one. The exact, optimal solution is the gorgeous *package-merge algorithm* of *Lawrence Larmore* and *Daniel Hirschberg* (Journal of the ACM, July 1990). It reframes the problem as a *coin collector's problem*: you must "pay" a total of $n - 1$ using coins of denominations $2^{-1}, 2^{-2}, dots, 2^{-L_max}$ (one bit of Kraft budget at each allowed depth), each coin carrying a cost equal to a symbol's probability, and you want the cheapest way to pay — which turns out to assign each symbol its optimal length-limited depth. It runs in $O(n L_max)$ time. We will not implement it here, but its existence matters: it is _why_ DEFLATE can promise a 15-bit cap and still be essentially optimal.

#algo(
  name: "Package-merge (length-limited Huffman)", year: "1990",
  authors: "Lawrence L. Larmore; Daniel S. Hirschberg",
  aim: "Build the minimum-average-length prefix code subject to a maximum codeword length L-max.",
  complexity: "O(n · L-max) time, O(n) space.",
  strengths: "Optimal under the length cap; exact, not a heuristic; used by real formats needing bounded codes.",
  weaknesses: "More complex than plain Huffman; the cap costs a sliver of ratio when it binds.",
  superseded: "Still the standard for length-limited coding; faster approximate variants exist for huge alphabets.",
)[
Many production encoders use a cheap heuristic (build a normal Huffman tree, then iteratively shorten over-long codes and lengthen short ones to restore the Kraft equality) which is _near_-optimal and simpler; package-merge is the exact gold standard when ratio matters most.
]

== Adaptive Huffman: learning the code as you go

So far our codec makes *two passes*: one to count frequencies, one to encode — and it must transmit the frequency table (our 256 lengths). For streaming data you cannot see twice, or when the table's overhead bites, there is a one-pass alternative: *adaptive* (or *dynamic*) Huffman, where _encoder and decoder maintain identical, evolving Huffman trees_ and update them after every symbol. No table is sent; the decoder, having seen the same prefix of symbols, has built the same tree, so it always knows the current code. The price is that early symbols are coded with a poor (barely-trained) tree, and every step costs a tree update.

The first workable scheme is *Algorithm FGK*, named for *Newton Faller* (1973), *Robert Gallager* (1978), and *Donald Knuth* (1985), who each added a piece. Its key device is the *sibling property* (Gallager): a Huffman tree is valid exactly when its nodes can be numbered so that each node's number is $<=$ its parent's, and the numbers increase level by level. FGK keeps a node's _weight_ equal to how often its symbol has appeared so far; when a symbol arrives, it increments that leaf's weight and, to preserve the sibling property, may *swap* the node with the highest-numbered node of equal weight before bubbling the increment up toward the root. New, never-before-seen symbols enter through a special zero-weight *NYT* ("not yet transmitted") leaf, which splits to admit them. Every increment-and-swap is $O("tree depth")$, so the whole stream costs $O(L)$ for $L$ total bits.

*Jeffrey Scott Vitter* sharpened FGK in 1987 (his "Algorithm $Lambda$", _Journal of the ACM_). FGK's updates can leave the tree lopsided and occasionally swap a node more than necessary; Vitter's variant adds a smarter invariant on the node numbering that keeps the tree as balanced as possible and guarantees the code is, at every step, _as good as the static Huffman code for the counts seen so far, plus at most one extra bit per symbol_. Concretely, where FGK can emit roughly $2 S + t$ bits ($S$ = the optimal static size, $t$ = the message length), Vitter holds it to about $S + t$ — provably closer to optimal, and with fewer tree rearrangements.

#algo(
  name: "Adaptive Huffman (FGK / Vitter Λ)", year: "1973–1987",
  authors: "Faller (1973), Gallager (1978), Knuth (1985); Vitter (1987)",
  aim: "Maintain an evolving Huffman tree in one pass so encoder and decoder stay in sync without transmitting a frequency table.",
  complexity: "$O(d)$ per symbol for tree depth $d$; one pass over the data.",
  strengths: "Single pass; no codebook to send; adapts to local statistics; ideal for streaming.",
  weaknesses: "Per-symbol update overhead; poor on early symbols; still pays the integer-bit tax; trickier to implement correctly.",
  superseded: "Adaptive *arithmetic* coding and adaptive ANS dominate where adaptivity matters most (Chapters 26–27).",
)[
Vitter's $Lambda$ algorithm keeps the tree's leaves numbered so that, among nodes of equal weight, the leaves come before the internal nodes — the extra invariant that bounds the per-symbol overhead to under one bit above the running static optimum.
]

#checkpoint[Why does adaptive Huffman not need to transmit a frequency table, while our two-pass canonical Huffman does?][Because the decoder builds the _same_ tree the encoder does, from the _same_ history. After each decoded symbol the decoder applies the identical update rule, so it always holds the current code without being told it. Two-pass canonical Huffman, by contrast, derives the code from the _whole_ file's counts — which the decoder has not seen — so the encoder must ship those counts (our 256 lengths) up front.]

#takeaways((
  [Every compressor splits into a *model* (predicts symbol probabilities) and an *entropy coder* (spends $approx -log_2 p$ bits per symbol). Sharper model ⇒ fewer bits, for free.],
  [A *prefix code* is a binary tree with symbols at the leaves; its average length is $L = sum_s p_s ell_s$, and $L >= H(X)$ always.],
  [*Shannon–Fano* splits top-down into near-equal halves — simple and good, but _not_ optimal.],
  [*Huffman* merges the two rarest nodes bottom-up and is *provably optimal among prefix codes*, proved via the sibling and merge lemmas plus induction.],
  [Huffman's flaw is the *integer-bit tax*: $H <= L < H + 1$. It is near-optimal when symbols carry $approx$ a bit or more, but wasteful on skewed sources (a 99%-white page: $L = 1$ vs $H approx 0.08$). Cures: block symbols, or use arithmetic/ANS coding.],
  [*Canonical Huffman* fixes codewords by an increment-and-shift rule so the decoder rebuilds them from *lengths alone* — what DEFLATE, JPEG, and PNG actually ship.],
  [*Length-limited* Huffman (package-merge, 1990) caps codeword length optimally; *adaptive* Huffman (FGK, Vitter) learns the code in one pass with no transmitted table.],
  [`tinyzip` now has its first real compressor: a round-tripping canonical Huffman `encode`/`decode` registered as `method="huffman"`.],
))

== Exercises

#exercise("24.1", 1)[
A source has four symbols with probabilities $p = (0.5, 0.25, 0.125, 0.125)$. Compute the entropy $H$, then build a Huffman code by hand and give its average length $L$. What is special about this source, and what does it imply about the gap $L - H$?
]
#solution("24.1")[
$H = 0.5(1) + 0.25(2) + 0.125(3) + 0.125(3) = 0.5 + 0.5 + 0.375 + 0.375 = 1.75$ bits. Huffman merges the two 0.125 symbols (→ 0.25), then the two 0.25 nodes (→ 0.5), then the two 0.5 nodes (→ root), giving lengths $(1, 2, 3, 3)$. Average $L = 0.5(1)+0.25(2)+0.125(3)+0.125(3) = 1.75$ bits. The source is special: *every probability is a power of $1/2$*, so each symbol's ideal length $-log_2 p$ is already a whole number ($1, 2, 3, 3$). Huffman hits them exactly and $L - H = 0$ — the only situation where a prefix code reaches the entropy floor.
]

#exercise("24.2", 1)[
Explain in one or two sentences why no Huffman tree can have an internal node with exactly one child. Use it to argue that the two least-probable symbols always end up as siblings.
]
#solution("24.2")[
If an internal node had a single child, you could delete that node and promote the child one level up, shortening every codeword beneath it by one bit without breaking the prefix property — contradicting optimality (and Huffman always merges in _pairs_, so it never creates a one-child node in the first place). Hence every internal node has two children, the deepest level holds at least one sibling pair, and the sibling lemma shows the two rarest symbols can be moved to that deepest pair without increasing $L$.
]

#exercise("24.3", 2)[
Take the five-symbol source $p = (0.30, 0.25, 0.20, 0.15, 0.10)$. (a) Build the Huffman code and report the codeword lengths and $L$. (b) Compute $H$ and the gap $L - H$. (c) Now build a *canonical* Huffman code from your lengths.
]
#solution("24.3")[
(a) Merge $0.10 + 0.15 = 0.25$; pool $(0.30, 0.25, 0.20, 0.25)$. Merge $0.20 + 0.25 = 0.45$ (taking the two smallest, $0.20$ and one $0.25$); pool $(0.30, 0.25', 0.45)$. Merge $0.25 + 0.30 = 0.55$; pool $(0.45, 0.55)$. Merge → root. Tracing depths gives lengths $(2, 2, 2, 3, 3)$ for the symbols in probability order. $L = 0.30(2)+0.25(2)+0.20(2)+0.15(3)+0.10(3) = 1.5 + 0.75 = 2.25$ bits. (b) $H = -[0.30 log_2 0.30 + 0.25 log_2 0.25 + 0.20 log_2 0.20 + 0.15 log_2 0.15 + 0.10 log_2 0.10] approx 2.228$ bits, gap $approx 0.022$ bits — Huffman is within $1%$. (c) Sort by (length, symbol): three length-2 symbols then two length-3. Canonical codes: `00`, `01`, `10` (length 2); then increment `10`→`11`, shift left → `110`, and `111` (length 3). So the codewords are `00, 01, 10, 110, 111`.
]

#exercise("24.4", 2)[
A binary source emits `0` with probability $0.9$ and `1` with probability $0.1$. (a) What is $H$? (b) What does Huffman do, and what is its $L$? (c) Now *block* pairs of symbols into a 4-symbol alphabet ($p_{00}=0.81$, etc.), build Huffman on the pairs, and report the bits _per original symbol_. Did blocking help?
]
#solution("24.4")[
(a) $H = -0.9 log_2 0.9 - 0.1 log_2 0.1 approx 0.137 + 0.332 = 0.469$ bits. (b) With two symbols Huffman must give each 1 bit, so $L = 1$ bit/symbol — more than double the entropy. (c) Pair probabilities: $00 → 0.81$, $01 → 0.09$, $10 → 0.09$, $11 → 0.01$. Huffman lengths: $00 →1$, then $01, 10 → 2, 3$ish — building it: merge $0.01 + 0.09 = 0.10$, then $+0.09 = 0.19$, then $+0.81$. Lengths come out $(1, 2, 3, 3)$ giving $L_"pair" = 0.81(1) + 0.09(2) + 0.09(3) + 0.01(3) = 0.81 + 0.18 + 0.27 + 0.03 = 1.29$ bits per _pair_ = $0.645$ bits per original symbol. Blocking cut the cost from $1.0$ to $0.645$ — much closer to $H = 0.469$. Blocking pairs of pairs would close most of the rest of the gap.
]

#exercise("24.5", 2)[
In our `tinyzip` `encode`, we always write a 256-byte header of codeword lengths. For a file of 10 distinct bytes repeated many times, this header is mostly zeros and wasteful. Propose (in words, or sketch the code) a more compact way to transmit the lengths, and say what the decoder must change.
]
#solution("24.5")[
Several options. (1) *Count + list:* write a 1-byte count $k$ of distinct symbols, then $k$ pairs of `(byte, length)` — here $1 + 10 times 2 = 21$ bytes instead of 256. (2) *Run-length the length array:* DEFLATE does this, coding runs of equal lengths (especially runs of zero) with their own small code. (3) *Compress the 256 lengths themselves* with a tiny fixed code, since most are 0. The decoder must change to read the chosen format: for option (1) it reads $k$, then $k$ `(byte, length)` pairs, then reconstructs `lengths` (all other bytes implicitly length 0) before calling `canonical_codes`. The coded-bits and decode loop are untouched — only the header serialization differs.
]

#exercise("24.6", 2)[
Prove the upper half of Huffman's gap bound, $L < H + 1$, for _any_ source — not just for Huffman, but for the Shannon code that assigns symbol $s$ the length $ell_s = ceil(-log_2 p_s)$. (Huffman, being optimal, can only do better.)
]
#solution("24.6")[
For the Shannon code, $ell_s = ceil(-log_2 p_s) < -log_2 p_s + 1$ (the ceiling adds less than 1). First check it is a valid prefix code via Kraft (Chapter 19): $sum_s 2^{-ell_s} <= sum_s 2^{log_2 p_s} = sum_s p_s = 1$, so the lengths are achievable. Its average length is $L = sum_s p_s ell_s < sum_s p_s (-log_2 p_s + 1) = H + sum_s p_s = H + 1$. Since Huffman is optimal among prefix codes, its $L$ is $<=$ this Shannon code's, hence also $< H + 1$. Combined with the source coding theorem's $L >= H$, we get $H <= L < H + 1$.
]

#exercise("24.7", 3)[
Implement `decode` so that instead of reading one bit at a time, it uses the *consecutive-integer* property of canonical codes: precompute, for each length $ell$, the smallest code value at that length, and decode by reading bits, comparing the accumulated value against the range of codes for the current length, and table-jumping. Describe the data structures and why this is faster than the bit-by-bit loop.
]
#solution("24.7")[
For each length $ell$ used, record `first_code[ell]` (the numeric value of the first canonical codeword of that length) and `first_symbol_index[ell]` (its position in the symbol list sorted by (length, byte)). To decode: read bits into an accumulator `cur`, incrementing `ell` each bit; at each step check whether `cur` lies in this length's range, i.e. `cur - first_code[ell] < (number of codes of length ell)`. If so, the symbol is `sorted_syms[first_symbol_index[ell] + (cur - first_code[ell])]` — a direct array index, no tree walk. It is faster because the inner test is a subtraction and comparison rather than a dictionary lookup per bit, and real decoders push further by reading a fixed $L_"max"$ bits at once and indexing a flat table, decoding each symbol in $O(1)$ regardless of its length. The correctness rests on canonical codes of each length being _consecutive integers_, larger than all shorter codes' prefixes.
]

#exercise("24.8", 3)[
Adaptive Huffman maintains the *sibling property*: nodes can be numbered $1, 2, dots$ in non-decreasing weight order, reading each level left to right then moving up, with each node's number below its parent's. Argue why a tree with this property is a valid Huffman (optimal-for-its-weights) tree, and explain why incrementing a leaf's weight might violate it — motivating the swap step.
]
#solution("24.8")[
Gallager's theorem states that a binary prefix tree is a Huffman tree for its leaf weights *if and only if* it has the sibling property. Intuitively, the numbering being non-decreasing in weight while increasing up the tree means no rearrangement could lower the weighted path length — exactly the local-optimality Huffman guarantees. When you increment one leaf's weight by 1, that leaf may now outweigh some node with a _higher_ number (one that should, by the property, be at least as heavy). That breaks the non-decreasing ordering. The fix is to *swap* the just-incremented node with the highest-numbered node of the _old_ weight (so the numbering order is restored), then move up to the parent and repeat. The swap keeps the tree a valid Huffman tree at every step without rebuilding it from scratch — the heart of FGK and Vitter.
]

== Further reading

- #link("https://ieeexplore.ieee.org/document/4051119")[Huffman, D. A. (1952). _A Method for the Construction of Minimum-Redundancy Codes._ Proceedings of the IRE 40(9), 1098–1101.] — the original three-page paper; remarkably readable.
- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon, C. E. (1948). _A Mathematical Theory of Communication._ Bell System Technical Journal 27.] — §9 sketches the Shannon–Fano construction and the entropy bound.
- #link("https://www.ittc.ku.edu/~jsv/Papers/Vit87.jacmACMversion.pdf")[Vitter, J. S. (1987). _Design and Analysis of Dynamic Huffman Codes._ Journal of the ACM 34(4), 825–845.] — the definitive adaptive-Huffman ($Lambda$) algorithm and its bounds.
- #link("https://link.springer.com/chapter/10.1007/BFb0015404")[Larmore, L. L. & Hirschberg, D. S. (1990). _A Fast Algorithm for Optimal Length-Limited Huffman Codes._ Journal of the ACM 37(3), 464–473.] — the package-merge algorithm behind DEFLATE's 15-bit cap.
- #link("https://www.rfc-editor.org/rfc/rfc1951.txt")[Deutsch, P. (1996). _DEFLATE Compressed Data Format Specification v1.3._ RFC 1951.] — §3.2 specifies canonical Huffman from lengths exactly as we built it; the real thing.

#bridge[
Huffman is optimal — _among prefix codes_ — and that italicized qualifier is its undoing. It cannot spend a fraction of a bit, so on skewed sources it bleeds, and even at its best it floats up to a full bit above entropy. The next family of coders attacks that gap from a different angle: instead of one codeword per symbol, they cleverly pack _many_ symbols' fractional costs together. Chapter 25 starts gently, with *integer and universal codes* — unary, Elias, Golomb–Rice — for the common case where you know the _shape_ of a distribution (it falls off geometrically) but not its exact probabilities, and where building a Huffman table would be overkill. Then Chapter 26 takes the decisive leap: *arithmetic coding*, which encodes an entire message as a single number and finally pays the true fractional price, erasing Huffman's integer-bit tax for good.
]
