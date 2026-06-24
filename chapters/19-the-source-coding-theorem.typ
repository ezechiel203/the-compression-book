#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

// local helper: a lightly-set worked-example block (uses only built-ins)
#let worked(body) = block(width: 100%, breakable: true, inset: (x: 10pt, y: 8pt),
  radius: 4pt, fill: rgb("#fbf7ef"), stroke: (left: 3pt + rgb("#783f04")),
  above: 9pt, below: 9pt)[#body]

= The Source Coding Theorem

#epigraph[The fundamental problem of communication is that of reproducing at one point either exactly or approximately a message selected at another point.][Claude Shannon, _A Mathematical Theory of Communication_, 1948]

In Chapter 18 we met a number. For any source that emits symbols with known probabilities, there is a single quantity (the entropy $H(X)$) that measures, in bits, the average surprise of the next symbol. We computed it for coins, for dice, for the letters of English. We called it the "average number of yes/no questions" you would need to pin a symbol down. It was a lovely number. But so far it has been just that: a number attached to a probability distribution, sitting there, beautiful and inert.

This chapter is where that number comes alive and starts giving orders.

Here is the puzzle that will drive everything. Suppose I hand you a source - say a weird four-sided die that lands on $A$ half the time, $B$ a quarter of the time, and $C$ or $D$ one-eighth each. You want to write down a long sequence of its rolls using as few bits as you possibly can, so that a friend on the far end can reconstruct the exact sequence, roll for roll, with no mistakes. You are allowed to be clever. You may give common symbols short codes and rare symbols long codes. You may even code whole blocks of rolls at once. The question is brutally simple:

#align(center)[*How few bits per roll can you get away with, and who says so?*]

Two answers are possible, and they could not be more different. Maybe there is no real limit. Maybe a sufficiently ingenious coding scheme could shrink the data forever, halving it, halving it again, down toward nothing. Or maybe there is a wall: a hard floor below which no scheme, however clever, can ever go, not now, not in a thousand years of research. If there is a wall, where exactly is it? And is it a wall you can actually reach, or merely approach like a runner closing on a finish line that keeps inching away?

The answer, proved by Shannon in 1948 and sharpened by others over the following decade, is one of the most satisfying results in all of science. There _is_ a wall. It is _exactly_ the entropy $H(X)$ - the very number we computed last chapter. You can never beat it. And you can get as close to it as you like. That double statement - *unbeatable yet achievable* - is the *source coding theorem*, and earning it, brick by brick, is the work of this chapter.

#recap[
In Chapter 18 we built Shannon's entropy from scratch. We defined the *surprisal* of a symbol $x$ as $-log_2 p(x)$ bits (the rarer the symbol, the bigger the surprise) and the *entropy* of a source as the average surprisal, $H(X) = -sum_x p(x) log_2 p(x)$. We saw entropy peaks when every symbol is equally likely and drops to zero when one symbol is certain. We will lean on logarithms (Chapter 7), on probability and expectation (Chapters 9 and 10), on the counting and pigeonhole arguments of Chapter 8, and on the binary trees of Chapter 14. This chapter turns the _number_ $H(X)$ into a _law_ about codes.
]

#objectives((
  [Explain what a *code* is, and the difference between a *uniquely decodable* code and a *prefix code*, with pictures and examples.],
  [State and *prove* the *Kraft inequality* for prefix codes, and the *Kraft--McMillan* extension to all uniquely decodable codes, showing prefix codes lose nothing.],
  [Prove that the *average length of any uniquely decodable code is at least $H(X)$*, the entropy floor, and find exactly when equality holds.],
  [Build a code whose average length is *less than $H(X) + 1$*, closing the gap from above, and shrink that "+1" to nothing by coding *blocks*.],
  [Understand the *Asymptotic Equipartition Property (AEP)* and the *typical set*: why long messages concentrate onto roughly $2^(n H)$ near-equally-likely sequences.],
  [Assemble these into the full *source coding theorem* and explain what "you cannot beat entropy" really means, and what it does *not* mean.],
))

== What exactly is a code?

Before we can prove anything about codes, we have to say precisely what one is. The word gets thrown around loosely, so let us be careful, because the whole theorem lives or dies on a single subtle requirement.

A *source* produces symbols from a fixed menu called the *alphabet*. Our four-sided die has alphabet $\{A, B, C, D\}$. The letters of written English form an alphabet of 26 (or, with spaces and punctuation, a few dozen). The bytes of a computer file form an alphabet of 256. A *code* is simply a rulebook that replaces each source symbol with a string of bits - its *codeword*. Encoding a message means looking up each symbol and writing down its codeword, one after another, with no separators, no commas, nothing between them. That last detail (*no separators*) is the crux of the whole story, as we are about to see.

#definition("Code")[
A (binary) *code* for an alphabet $cal(A)$ is a function $C$ that assigns to each symbol $x in cal(A)$ a finite string of bits $C(x)$, called its *codeword*. The *length* of the codeword $C(x)$, written $ell(x)$, is the number of bits in it. To encode a message $x_1 x_2 dots x_n$, we *concatenate*: we output $C(x_1)$ then $C(x_2)$ then $dots$ then $C(x_n)$, with nothing in between.
]

Let us try one. Take the alphabet $\{A, B, C, D\}$ and the tempting little code

#align(center)[$C(A) = 0, quad C(B) = 1, quad C(C) = 0 1, quad C(D) = 1 0.$]

It looks economical, with only one or two bits each. Now I encode the message $C$ and send you the bits `01`. You receive `01` and try to decode. Was it the single symbol $C$? Or was it $A$ followed by $B$? Both encode to exactly `01`. You have no way to tell. The code is *ambiguous*: two different messages produce the identical bitstream, so the receiver cannot recover the original. A code like that is worthless for compression, no matter how short its codewords, because it does not actually preserve the message.

This gives us the one non-negotiable requirement.

#definition("Uniquely decodable")[
A code is *uniquely decodable* if every distinct message produces a distinct bitstream. Equivalently: any bitstream that the code can produce can be split back into source symbols in *exactly one* way. No two different sequences of symbols ever collide on the same bits.
]

#keyidea[
Compression is not about making codewords short. It is about making codewords short _while remaining uniquely decodable_. The little $\{0, 1, 01, 10\}$ code has the shortest possible codewords and is completely useless, because it loses information. Unique decodability is the price of admission; everything in this chapter is about how cheap we can make the bits _given_ that price.
]

=== Prefix codes: decoding without backtracking

There is a special, well-behaved family of uniquely decodable codes, and it turns out we never need anything else. They are the *prefix codes* (also called "prefix-free" codes or "instantaneous" codes - three names for one idea).

#definition("Prefix code")[
A code is a *prefix code* if no codeword is a *prefix* (a starting chunk) of any other codeword. That is, no codeword appears at the very beginning of a longer codeword.
]

Why does that property help? It lets you decode *on the fly*, reading left to right, committing to a symbol the instant you have seen a complete codeword, never needing to look ahead or take anything back. Consider the prefix code

#align(center)[$C(A) = 0, quad C(B) = 1 0, quad C(C) = 1 1 0, quad C(D) = 1 1 1.$]

No codeword starts another: `0` is not the start of `10`, `110`, or `111`; `10` is not the start of `110` or `111`; and so on. Now decode the stream `0111100`. Read the first bit: `0` - that is a complete codeword, it is $A$, and crucially nothing longer starts with `0`, so we can commit immediately. Next bits: `1`, not yet a codeword; `11`, still not; `111` - that is $D$. Then `0` - that is $A$. Then `0` again - another $A$. The message was $A, D, A, A$, recovered with zero ambiguity and zero backtracking. That "commit the instant you finish a codeword" behavior is why prefix codes are also called *instantaneous*.

#fig([A prefix code drawn as a binary tree. Reading a bit means stepping left (`0`) or right (`1`); each leaf is a codeword. Because symbols live only at _leaves_, never at internal nodes, no codeword can be a prefix of another.],
cetz.canvas({
  import cetz.draw: *
  let node(p, lbl, leaf: false) = {
    if leaf {
      circle(p, radius: 0.28, fill: rgb("#cdeccd"), stroke: rgb("#0b6e4f"))
    } else {
      circle(p, radius: 0.20, fill: rgb("#e8eef7"), stroke: rgb("#0b5394"))
    }
    content(p, text(size: 8pt)[#lbl])
  }
  // root
  node((0,0), "")
  // level 1
  node((-2,-1.3), "", )
  node((2,-1.3), "")
  line((0,0),(-2,-1.3)); content((-1.3,-0.55), text(size:8pt, fill: rgb("#0b5394"))[0])
  line((0,0),(2,-1.3)); content((1.3,-0.55), text(size:8pt, fill: rgb("#0b5394"))[1])
  // A leaf on left
  node((-2,-2.6), "A", leaf: true)
  line((-2,-1.3),(-2,-2.6))
  // right subtree internal
  node((0.6,-2.6), "")
  node((3.4,-2.6), "")
  line((2,-1.3),(0.6,-2.6)); content((1.0,-1.95), text(size:8pt, fill: rgb("#0b5394"))[0])
  line((2,-1.3),(3.4,-2.6)); content((3.0,-1.95), text(size:8pt, fill: rgb("#0b5394"))[1])
  // B leaf
  node((0.6,-3.9), "B", leaf: true)
  line((0.6,-2.6),(0.6,-3.9))
  // C, D leaves
  node((2.6,-3.9), "C", leaf: true)
  node((4.2,-3.9), "D", leaf: true)
  line((3.4,-2.6),(2.6,-3.9)); content((2.7,-3.25), text(size:8pt, fill: rgb("#0b5394"))[0])
  line((3.4,-2.6),(4.2,-3.9)); content((4.1,-3.25), text(size:8pt, fill: rgb("#0b5394"))[1])
}))

That tree picture, which we first drew for Huffman-style codes in Chapter 14, is the right mental model for the rest of the chapter. A binary prefix code _is_ a binary tree: start at the root, a `0` bit steps left, a `1` bit steps right, and every symbol sits at a *leaf*. Following any codeword traces a path from the root down to a leaf. The prefix property is exactly the statement that *symbols live only at leaves, never at internal nodes*, because if a symbol sat at an internal node, its path would be the beginning of every path passing through it, meaning its codeword would be a prefix of others.

#note[
Every prefix code is uniquely decodable (we just decoded one without a hiccup), but the reverse is false: there exist uniquely decodable codes that are *not* prefix codes. A classic example is $\{0, 0 1, 0 1 1\}$: here `0` _is_ a prefix of `01`, so it is not a prefix code, yet it can still be decoded uniquely if you are willing to read ahead. We will see shortly (the Kraft--McMillan theorem) that such non-prefix codes buy you absolutely nothing. For any uniquely decodable code there is a prefix code with the *same codeword lengths*. So we lose no generality by restricting attention to prefix codes and we gain instantaneous decoding for free.
]

#checkpoint[Is the code $C(A)=0, C(B)=1 0, C(C)=1 1, C(D)=0 1$ a prefix code? Decode the stream `0101`.][
It is *not* a prefix code: the codeword for $A$, `0`, is a prefix of the codeword for $D$, `01`. Watch what that breakage does to `0101`. One clean reading is $D, D$ (`01` then `01`). But a decoder reading left-to-right grabs the first `0` and, since `0` is a complete codeword, commits to $A$; now it faces `101`, reads `10` as $B$, and is left holding a stray `1` that begins no codeword. So the same bits parse two different ways ($D,D$ versus $A,B,dots$): the stream is ambiguous, and a left-to-right decoder cannot commit safely. Both failures - ambiguity and the inability to decode instantly - flow directly from the broken prefix property.
]

== The Kraft inequality: a budget on codeword lengths

Here is a question that sounds like it should have a complicated answer but has a stunningly clean one. Suppose I tell you I want a prefix code with four symbols, and I demand the codeword lengths $1, 2, 3, 3$ bits. Can such a code exist? What about lengths $1, 1, 2, 2$? Or $2, 2, 2, 2$? Is there a simple test, looking only at the list of lengths and never mind the actual bits, that tells me whether a prefix code with those lengths is even possible?

There is, and it is the *Kraft inequality*. It is the single most important structural fact about codes, and it is the hinge on which the entire source coding theorem swings. Leon Kraft stated it in his 1949 MIT master's thesis (he credited the underlying analysis to Raymond Redheffer); Brockway McMillan extended it to all uniquely decodable codes in 1956. Together it is the *Kraft--McMillan inequality*.

#theorem("Kraft inequality")[
A binary prefix code with codeword lengths $ell_1, ell_2, dots, ell_m$ exists *if and only if*
$ sum_(i=1)^m 2^(-ell_i) <= 1. $
Moreover, if the inequality holds, you can actually construct such a code.
]

Before the proof, let us feel what the inequality is saying. Each codeword of length $ell$ contributes a "cost" of $2^(-ell)$ to a budget that may total at most $1$. A short codeword is expensive: a 1-bit codeword costs $2^(-1) = 1/2$, eating half the entire budget in one bite. A long codeword is cheap: a 10-bit codeword costs $2^(-10) = 1/1024$, almost nothing. So the inequality is a *conservation law*: short codewords are a scarce resource, and you can only have so many of them. Want lots of 1-bit codewords? You get at most two ($1/2 + 1/2 = 1$), and then your budget is gone. This is the mathematical reason you cannot make every codeword short - exactly the tension at the heart of compression.

Let us test our three candidate length-lists:

#gomaths("Negative exponents and the sum symbol ∑")[
Two pieces of notation power this whole section. First, a *negative exponent* just means "one over": $2^(-1) = 1/2 = 0.5$, $2^(-2) = 1/4 = 0.25$, $2^(-3) = 1/8 = 0.125$. Each step the exponent drops by one, the value halves. (We built this in Chapter 7; the rule is $2^(-n) = 1/(2^n)$.)

Second, the *summation symbol* $sum$ (capital Greek "sigma") is shorthand for "add these up." The expression $sum_(i=1)^m a_i$ means "let $i$ run from $1$ to $m$, and add up all the $a_i$." So $sum_(i=1)^3 2^(-ell_i)$ with lengths $ell_1=1, ell_2=2, ell_3=2$ means $2^(-1)+2^(-2)+2^(-2) = 1/2 + 1/4 + 1/4 = 1$. That is all $sum$ ever does: it is a compact "for each item, add its contribution."
]

- Lengths $1, 2, 3, 3$: the Kraft sum is $1/2 + 1/4 + 1/8 + 1/8 = 1$. Right at the budget: *possible*. (Our tree picture earlier, with lengths $1, 2, 3, 3$ for $A, B, C, D$, is exactly such a code.)
- Lengths $1, 1, 2, 2$: the sum is $1/2 + 1/2 + 1/4 + 1/4 = 3/2 > 1$. *Impossible*. Two 1-bit codewords already spend the whole budget; there are no bits left for anything else.
- Lengths $2, 2, 2, 2$: the sum is $1/4 + 1/4 + 1/4 + 1/4 = 1$. *Possible* - this is just the four 2-bit strings `00`, `01`, `10`, `11`, a perfectly good fixed-length code.

#worked[*Worked example - designing a code from a wish list.* You want codewords of lengths $2, 2, 2, 3, 3$ for five symbols. Kraft sum: $1/4+1/4+1/4+1/8+1/8 = 3/4 + 1/4 = 1 <= 1$. Feasible. To build it, list the depth-by-depth slots of a binary tree and assign greedily, shortest first: give the three length-2 symbols `00`, `01`, `10`; the slot `11` is still free, so split it into `110` and `111` for the two length-3 symbols. Done - a valid prefix code, no codeword a prefix of another. The Kraft sum being _exactly_ 1 told us in advance the tree would be "full," with no wasted leaves.]

=== Proving the Kraft inequality

We prove the theorem in two directions, because "if and only if" is two claims welded together: (1) *any* prefix code obeys the inequality, and (2) *whenever* the inequality holds, a prefix code can be built. The tree picture makes both almost visual.

#proof[
*Direction 1 - every prefix code satisfies $sum_i 2^(-ell_i) <= 1$.*

Draw the code as a binary tree, and let $ell_max$ be the length of the longest codeword. Now imagine the *full* binary tree of depth $ell_max$, the tree where _every_ path of length $ell_max$ exists. This full tree has exactly $2^(ell_max)$ leaves at the bottom level (two choices per bit, $ell_max$ times: $2 times 2 times dots = 2^(ell_max)$).

Each codeword in our prefix code sits at some node at depth $ell_i$. Consider the codeword of length $ell_i$. How many of the $2^(ell_max)$ bottom-level leaves lie *underneath* it - that is, how many length-$ell_max$ strings start with this codeword? Every such string is the codeword followed by $ell_max - ell_i$ free bits, so there are $2^(ell_max - ell_i)$ of them.

Here is the punchline. Because the code is *prefix-free*, no codeword sits underneath another, so these sets of bottom-level descendants *never overlap*: each bottom leaf is claimed by at most one codeword. Adding up the claimed leaves over all codewords cannot exceed the total number of leaves:
$ sum_(i=1)^m 2^(ell_max - ell_i) <= 2^(ell_max). $
Divide both sides by $2^(ell_max)$:
$ sum_(i=1)^m 2^(-ell_i) <= 1. $
That is the inequality. The prefix property did all the work: it is exactly what guaranteed the descendant-sets do not overlap.
]

#fig([Why the Kraft sum stays under budget. In the full depth-3 tree (8 bottom leaves), the codeword `0` (length 1) claims $2^(3-1)=4$ bottom leaves; `10` (length 2) claims $2^(3-2)=2$; `110` and `111` claim $1$ each. Total claimed: $4+2+1+1 = 8 = 2^3$. Prefix-freeness means no leaf is double-claimed.],
cetz.canvas({
  import cetz.draw: *
  // 8 bottom slots
  for i in range(8) {
    let x = i*0.95
    rect((x,0),(x+0.8,0.7), fill: rgb("#f4f6f8"), stroke: rgb("#d0d7de"))
    content((x+0.4,0.35), text(size:6.5pt)[#{
      let s = ""
      let n = i
      for b in range(3) { s = (if calc.rem(n,2)==0 {"0"} else {"1"}) + s; n = calc.quo(n,2) }
      s
    }])
  }
  // brackets indicating ownership
  line((0,0.95),(3.75,0.95), stroke: 1.2pt+rgb("#0b6e4f"))
  content((1.85,1.25), text(size:7.5pt, fill: rgb("#0b6e4f"))[`0` claims 4])
  line((3.8,0.95),(5.65,0.95), stroke: 1.2pt+rgb("#783f04"))
  content((4.7,1.25), text(size:7.5pt, fill: rgb("#783f04"))[`10` claims 2])
  line((5.7,0.95),(6.55,0.95), stroke: 1.2pt+rgb("#9a2617"))
  content((6.1,1.5), text(size:7pt, fill: rgb("#9a2617"))[`110`])
  line((6.65,0.95),(7.5,0.95), stroke: 1.2pt+rgb("#5b3a86"))
  content((7.05,1.25), text(size:7pt, fill: rgb("#5b3a86"))[`111`])
}))

#proof[
*Direction 2 - if $sum_i 2^(-ell_i) <= 1$, a prefix code with those lengths exists.*

This is a construction, so we build the code. Sort the desired lengths in increasing order, $ell_1 <= ell_2 <= dots <= ell_m$. We assign codewords greedily, one at a time, always taking the next available "slot."

Think again of the full tree of depth $ell_max$ with its $2^(ell_max)$ bottom leaves, and process the codewords shortest-first. When we are about to place the $j$-th codeword (length $ell_j$), the codewords already placed, $1$ through $j-1$, have together blocked off $sum_(i<j) 2^(ell_max - ell_i)$ of the bottom leaves (each length-$ell_i$ codeword reserves a contiguous block of $2^(ell_max - ell_i)$ of them). Since
$ sum_(i<j) 2^(-ell_i) <= sum_(i=1)^m 2^(-ell_i) <= 1, $
multiplying by $2^(ell_max)$ shows the blocked leaves number strictly fewer than $2^(ell_max)$ - there is at least one bottom leaf still free. Pick the first free block of $2^(ell_max - ell_j)$ consecutive bottom leaves (sorting by length guarantees a clean block is available) and make the depth-$ell_j$ node above it our new codeword. Because we always take a fresh, unclaimed block, the new codeword has no already-placed codeword above it (it is not extending an existing one) and none below it yet, so the prefix property is preserved at every step. Continue until all $m$ codewords are placed. The result is a prefix code with exactly the requested lengths.
]

#keyidea[
The Kraft inequality is a two-way bridge. *Direction 1* says lengths from a real code must be "affordable." *Direction 2* says any affordable wish-list of lengths can be _realized_ as a real prefix code. Together they let us stop thinking about messy bit-strings entirely and reason purely about *lengths and the single number $sum_i 2^(-ell_i)$*. Every proof for the rest of the chapter exploits this: we will choose lengths first, check they fit the budget, and trust Kraft to hand us the actual code.
]

=== Kraft--McMillan: prefix codes lose nothing

We promised earlier that non-prefix uniquely decodable codes buy you nothing. Now we can prove it. McMillan's 1956 result extends the Kraft bound to _every_ uniquely decodable code, not just prefix ones. The consequence is liberating: since the entropy floor we are about to prove depends only on the Kraft sum, and _all_ uniquely decodable codes obey the same bound, we may forever restrict our attention to prefix codes without giving up a single bit of performance.

#theorem("Kraft--McMillan")[
The codeword lengths $ell_1, dots, ell_m$ of *any* uniquely decodable binary code satisfy $sum_i 2^(-ell_i) <= 1$. Conversely, any lengths obeying this can be realized by a prefix code. Hence every uniquely decodable code has a prefix code with identical lengths.
]

#proof[
The clever trick is to raise the Kraft sum to a power and count. Let $S = sum_(i=1)^m 2^(-ell_i)$, and let $ell_max$ be the longest codeword length. For any whole number $k$, expand the $k$-th power:
$ S^k = (sum_(i=1)^m 2^(-ell_i))^k = sum_(i_1) sum_(i_2) dots sum_(i_k) 2^(-(ell_(i_1) + ell_(i_2) + dots + ell_(i_k))). $
Each term corresponds to a choice of $k$ symbols $i_1, dots, i_k$ - i.e. to a *message of length $k$* - and its exponent is the *total bit-length* of that message's encoding. Group the terms by total length $j$. The total length ranges from $k$ (all codewords length 1) up to $k thin ell_max$. Letting $a_j$ be the number of length-$k$ messages whose encoding is exactly $j$ bits long,
$ S^k = sum_(j=k)^(k thin ell_max) a_j thin 2^(-j). $
Now invoke *unique decodability*: distinct messages must give distinct bitstreams. So the $a_j$ messages encoding to $j$ bits map to $a_j$ _distinct_ $j$-bit strings, and there are only $2^j$ such strings in total. Therefore $a_j <= 2^j$, giving $a_j thin 2^(-j) <= 1$ and
$ S^k <= sum_(j=k)^(k thin ell_max) 1 = k thin ell_max - k + 1 <= k thin ell_max. $
So $S^k <= k thin ell_max$ for *every* $k$. If $S$ were bigger than $1$, the left side $S^k$ would grow exponentially in $k$ while the right side grows only linearly - impossible for large $k$. (Take $k$-th roots: $S <= (k thin ell_max)^(1\/k)$, and the right side $-> 1$ as $k -> infinity$.) Hence $S <= 1$. The converse is just Direction 2 of the Kraft theorem, which already produces a prefix code.
]

#history[
Leon G. Kraft proved the prefix-code version in his 1949 MIT master's thesis, _A Device for Quantizing, Grouping, and Coding Amplitude-Modulated Pulses_, explicitly crediting the key analysis to his classmate Raymond Redheffer. Brockway McMillan, a Bell Labs colleague of Shannon's, published the uniquely-decodable generalization in 1956, attributing the prefix special case to a 1955 remark by the probabilist Joseph L. Doob. The names stuck together as "Kraft--McMillan," a tidy example of how a clean idea accretes its discoverers.
]

#pitfall[
The Kraft inequality is a statement about *lengths*, not about which specific bits you choose. Two different prefix codes can share the exact same length list and the exact same Kraft sum. So when we minimize average length below, we are really choosing a _length list_ subject to $sum_i 2^(-ell_i) <= 1$; the actual codewords are then handed to us, for free, by Kraft's construction. Forgetting this and fixating on the bit patterns is the commonest way to get tangled.
]

== The entropy floor: you cannot beat $H(X)$

Now the payoff. We have a source $X$ that emits symbol $i$ with probability $p_i$, and a uniquely decodable code assigning symbol $i$ a codeword of length $ell_i$. The *average codeword length*, the average number of bits per symbol we actually spend, is the expectation

$ L = EE[ell] = sum_(i=1)^m p_i thin ell_i. $

This is the quantity we want to make small. The first half of the source coding theorem says we cannot make it smaller than the entropy.

#mathrecall[The *expectation* $EE[ell] = sum_i p_i ell_i$ (Chapter 10) is the long-run average of $ell$ when symbol $i$ shows up a fraction $p_i$ of the time: weight each value by how often it occurs, then add.]

#theorem("Noiseless source coding - lower bound")[
For *any* uniquely decodable code for a source $X$ with entropy $H(X)$, the average length satisfies
$ L = sum_i p_i thin ell_i >= H(X), $
with equality *if and only if* $ell_i = -log_2 p_i$ for every symbol - that is, exactly when every probability is a power of $1\/2$ and you spend the surprisal on each symbol.
]

To prove this cleanly we need one small, beautiful inequality about logarithms - the workhorse behind essentially every lower bound in information theory.

#gomaths("Gibbs' inequality (and the log-sum trick)")[
Start from a fact you can see by drawing the curve $ln x$: it lies _below_ its tangent line at $x = 1$, which is the line $y = x - 1$. So for every positive $x$,
$ ln x <= x - 1, $
with equality only at $x = 1$. (Check: at $x=1$ both sides are $0$; the curve bends downward away from the straight line everywhere else.) Switching from natural log $ln$ to base-2 $log_2$ just multiplies by the positive constant $1\/ln 2 approx 1.4427$, so the direction of the inequality is unchanged: $log_2 x <= (x-1)\/ln 2$.

From this single fact follows *Gibbs' inequality*: for any two probability lists $p_1, dots, p_m$ and $q_1, dots, q_m$ (each non-negative, each summing to 1),
$ -sum_i p_i log_2 p_i <= -sum_i p_i log_2 q_i, $
i.e. the true entropy is the _smallest_ average surprisal you can achieve, and using any _wrong_ distribution $q$ in place of $p$ only costs you more. We will use exactly this with a cleverly chosen $q$.
]

#proof[
Consider the gap $L - H(X)$ and show it is never negative. Write everything as one sum:
$ L - H(X) = sum_i p_i ell_i - (- sum_i p_i log_2 p_i) = sum_i p_i ell_i + sum_i p_i log_2 p_i. $
Since $ell_i = -log_2 2^(-ell_i) = log_2 (1 \/ 2^(-ell_i))$, rewrite $p_i ell_i = p_i log_2 (1\/2^(-ell_i))$ and combine the two sums:
$ L - H(X) = sum_i p_i log_2 (p_i / 2^(-ell_i)). $
Now flip the sign by inverting the fraction, $log_2(p_i\/2^(-ell_i)) = - log_2(2^(-ell_i)\/p_i)$, and apply the bound $log_2 x <= (x-1)\/ln 2$ from the box with $x = 2^(-ell_i)\/p_i$:
$ - (L - H(X)) = sum_i p_i log_2 (2^(-ell_i) / p_i) <= 1/(ln 2) sum_i p_i ((2^(-ell_i))/p_i - 1) = 1/(ln 2)(sum_i 2^(-ell_i) - sum_i p_i). $
The first sum is the Kraft sum, which is $<= 1$ by Kraft--McMillan; the second is $sum_i p_i = 1$. So the bracket is $<= 1 - 1 = 0$, hence $-(L - H(X)) <= 0$, i.e.
$ L - H(X) >= 0. $
*Equality* requires two things at once: the Kraft sum must equal $1$ (the code wastes no leaves), and the log-bound must be tight at every term, which happens only when $2^(-ell_i)\/p_i = 1$, i.e. $ell_i = -log_2 p_i$. So you hit the floor exactly when you can afford to spend the surprisal $-log_2 p_i$ as an integer number of bits on every symbol.
]

#keyidea[
*Entropy is a lower bound on bits per symbol that no uniquely decodable code can break.* The proof is just two ingredients you already own: the Kraft sum is at most 1 (a budget), and $log x <= x - 1$ (a tangent line). Everything mystical about "you can't beat Shannon" reduces to those two elementary facts.
]

#worked[*Worked example - the floor for our four-sided die.* The die has $p = (1/2, 1/4, 1/8, 1/8)$ for $A, B, C, D$. Its entropy is
$ H = 1/2 log_2 2 + 1/4 log_2 4 + 1/8 log_2 8 + 1/8 log_2 8 = 1/2(1) + 1/4(2) + 1/8(3) + 1/8(3) = 0.5 + 0.5 + 0.375 + 0.375 = 1.75 "bits." $
The lower-bound theorem says no code averages below $1.75$ bits per roll. And the surprisals $-log_2 p_i$ are $1, 2, 3, 3$ - all whole numbers! So the equality condition is met: the prefix code $A -> $ `0`, $B -> $ `10`, $C -> $ `110`, $D -> $ `111` (lengths $1,2,3,3$) averages $1/2(1)+1/4(2)+1/8(3)+1/8(3) = 1.75$ bits exactly. This source hits its own floor on the nose. Most sources are not so lucky, as we see next.]

== Reaching the floor from above: the $H(X) + 1$ guarantee

The lower bound told us we can never spend fewer than $H(X)$ bits per symbol. But is the floor _reachable_, or just a teasing limit nobody can touch? Our four-sided die hit it exactly - but only because all its probabilities were powers of $1\/2$, so the ideal lengths $-log_2 p_i$ came out as whole numbers. What about a realistic source, where $-log_2 p_i$ is some ugly fraction like $2.37$ bits? You cannot emit $2.37$ bits; codewords come in whole bits. You are forced to *round*, and rounding costs something.

The good news is that rounding costs at most one bit per symbol, ever. This is the *achievability* half: it says a simple, constructive code gets within one bit of the floor for _any_ source.

#theorem("Noiseless source coding - upper bound")[
For any source $X$ there is a prefix code (the *Shannon code*) whose average length satisfies
$ H(X) <= L < H(X) + 1. $
]

#proof[
The ideal length for symbol $i$ is $-log_2 p_i$, which may be fractional. Round it _up_ to the nearest whole number: set
$ ell_i = ceil(-log_2 p_i), $
where $ceil(dot)$ is the *ceiling* (round up to the next integer). First, are these lengths even legal? Check the Kraft budget. Rounding up means $ell_i >= -log_2 p_i$, so $2^(-ell_i) <= 2^(log_2 p_i) = p_i$, and therefore
$ sum_i 2^(-ell_i) <= sum_i p_i = 1. $
The Kraft sum is within budget, so by Kraft's construction a prefix code with these lengths *exists*. Now bound its average length. Rounding up adds less than one full bit, $ell_i = ceil(-log_2 p_i) < -log_2 p_i + 1$, so
$ L = sum_i p_i ell_i < sum_i p_i (-log_2 p_i + 1) = (- sum_i p_i log_2 p_i) + sum_i p_i = H(X) + 1. $
And $L >= H(X)$ is the lower bound we already proved. Together, $H(X) <= L < H(X)+1$.
]

#gomaths("The ceiling function ⌈·⌉")[
The *ceiling* of a number, written $ceil(x)$, is "round up to the nearest whole number." So $ceil(2.0) = 2$, $ceil(2.37) = 3$, $ceil(2.99) = 3$, $ceil(5) = 5$. It never rounds down. Its partner is the *floor* $floor(x)$, "round down": $floor(2.37) = 2$. The key fact we used is that rounding up adds strictly less than 1: $x <= ceil(x) < x + 1$. That single inequality is the entire reason the penalty above is "$+1$" and not something worse.
]

The code that picks $ell_i = ceil(-log_2 p_i)$ is the *Shannon code* (1948). A close cousin, *Shannon--Fano coding*, picks lengths the same way but assigns the actual bits by a top-down splitting rule; both land in the $[H, H+1)$ window. Neither is _optimal_ - Huffman's 1952 algorithm, which we devote Chapter 24 to, finds the genuinely shortest prefix code and usually does better than the Shannon code. Shannon's code is enough to _prove_ the floor is reachable, which is all the theorem needs. We profile it formally:

#algo(
  name: "Shannon code (and Shannon--Fano)",
  year: "1948 / 1949",
  authors: "Claude Shannon; Robert Fano (the splitting variant)",
  aim: "Build a prefix code whose average length provably lands within 1 bit of the source entropy, proving the floor is achievable.",
  complexity: "O(m log m) to sort m symbols by probability; O(m) to assign lengths.",
  strengths: "Dead simple; constructive proof of the achievability bound; lengths come straight from −log₂ pᵢ.",
  weaknesses: "Not optimal - the rounding wastes up to ~1 bit/symbol; on skewed sources it can be noticeably worse than Huffman.",
  superseded: "Huffman coding (1952, optimal prefix code, Chapter 24); arithmetic coding & ANS for sub-bit accuracy (Chapters 26–27).",
)[
  Compute each ideal length $ell_i = ceil(-log_2 p_i)$, confirm $sum_i 2^(-ell_i) <= 1$ (it always holds), then hand the lengths to Kraft's greedy tree-builder. Shannon used this code purely as a _proof device_; in practice you would reach for Huffman or, to erase even the rounding loss, arithmetic coding.
]

#misconception[A good enough algorithm can compress any data below its entropy.][No uniquely decodable code can average below $H(X)$ - that is the lower bound we just proved, airtight, with no escape hatch. What clever algorithms _actually_ do is one of two things: (1) shave the leftover gap between $H$ and $H+1$ down toward zero (Huffman, arithmetic coding), or (2) discover that the _true_ entropy is far lower than a naive per-symbol count suggested, by modelling correlations between symbols. "Beating gzip" always means a better _model_, i.e. a lower $H$, never beating the floor of the model you share.]

== Killing the "+1": coding in blocks

A gap of "less than 1 bit per symbol" sounds tiny, and often it is. But for a very predictable source it can be embarrassing. Imagine a biased coin that lands heads with probability $0.99$. Its entropy is

$ H = -0.99 log_2 0.99 - 0.01 log_2 0.01 approx 0.0808 "bits per flip." $

The true information content is under a tenth of a bit per flip. Yet _any_ code on single flips must give each of "heads" and "tails" a codeword of at least 1 bit (you cannot have a codeword of zero bits). So the best per-symbol code spends a full $1.0$ bit per flip - more than *twelve times* the entropy! The "+1" guarantee is technically satisfied ($1.0 < 0.0808 + 1$), but it is a catastrophe in practice. Symbol-by-symbol coding simply cannot express "a fraction of a bit."

The fix is one of the cleverest ideas in the subject: *stop coding one symbol at a time. Code blocks of $n$ symbols as if each block were a single super-symbol.*

#keyidea[
Treat a *block* of $n$ consecutive source symbols as one symbol drawn from a giant alphabet of all $m^n$ possible blocks. Apply the Shannon code to _that_ alphabet. The unavoidable "+1 bits" penalty is now spent *once per block of $n$*, so per original symbol it is only $1\/n$ bits, and that shrinks to nothing as $n$ grows.
]

Let us make it precise. Suppose the source is *memoryless*: successive symbols are independent (each draw is fresh, like rolling the die again, with no influence from previous rolls). Then a block $bold(x) = (x_1, dots, x_n)$ has probability $p(bold(x)) = p(x_1) p(x_2) dots p(x_n)$, and a standard fact about entropy (the additivity we will lean on, proved in Chapter 18's chain rule) gives the entropy of the block-source:

$ H(X_1, dots, X_n) = n thin H(X). $

Now apply the Shannon-code bound to the block alphabet. Its average length $L_n$ (in bits *per block*) obeys $H(X_1,...,X_n) <= L_n < H(X_1,...,X_n) + 1$, i.e. $n H(X) <= L_n < n H(X) + 1$. Divide everything by $n$ to get the average length *per original symbol*, call it $L_n \/ n$:

$ H(X) <= L_n / n < H(X) + 1/n. $

#gomaths("Limits: what \"→ 0 as n grows\" means")[
The expression $1\/n$ gets smaller and smaller as $n$ gets larger: $1\/1 = 1$, $1\/10 = 0.1$, $1\/1000 = 0.001$, and so on. We say "$1\/n -> 0$ as $n -> infinity$" ($->$ is read "tends to," $infinity$ is "grows without bound"). It means: name any tiny positive target you like - say $0.0001$ - and from some point on, $1\/n$ stays below it forever (here, for all $n > 10000$). The per-symbol cost $L_n\/n$ is squeezed between $H(X)$ below and $H(X) + 1\/n$ above; as the upper squeeze descends to $H(X)$, the cost is *forced* down onto $H(X)$ itself.
]

There it is. The floor is not merely a lower bound but a *limit you can reach as closely as you wish*, just by coding long enough blocks. For our 0.99 coin: code blocks of $n = 100$ flips and the per-flip overhead is at most $1\/100 = 0.01$ bit, so you spend under $0.0808 + 0.01 approx 0.09$ bits per flip instead of $1.0$, better than a tenfold improvement achieved by nothing more than grouping. This squeeze, $H <= L_n\/n < H + 1\/n$, is the engine of the whole achievability story.

#worked[*Worked example - blocking the 0.99 coin, $n=2$.* The four blocks and their probabilities: $H H: 0.9801$, $H T: 0.0099$, $T H: 0.0099$, $T T: 0.0001$. Ideal block lengths $ceil(-log_2 p)$: $ceil(0.029)=1$, $ceil(6.66)=7$, $ceil(6.66)=7$, $ceil(13.3)=14$. Average bits per *block* $L_2 = 0.9801(1)+0.0099(7)+0.0099(7)+0.0001(14) approx 0.9801 + 0.0693 + 0.0693 + 0.0014 approx 1.120$, so per flip $L_2\/2 approx 0.56$ bits - already far below the $1.0$ of single-flip coding, with $n$ only $2$. Push $n$ higher and it slides toward $0.0808$.]

== The deeper reason: typical sequences and the AEP

Block coding _works_, but the proof above feels like an accounting trick: round up, divide by $n$, watch the penalty melt. Shannon saw something far more profound underneath, an idea that explains *why* entropy is the magic number and that reappears, dressed differently, in every corner of information theory. It is the *Asymptotic Equipartition Property*, or *AEP*, and its star is the *typical set*.

Here is the intuition. Flip our 0.99 coin $n = 1000$ times. There are $2^1000$ possible outcome sequences - an astronomically large number. But you will almost never _see_ most of them. A sequence with 500 heads and 500 tails is possible, yet wildly improbable for this biased coin; you will overwhelmingly see sequences with _about_ 990 heads and _about_ 10 tails, because that is what a 0.99 coin does. The outcomes you actually encounter cluster into a comparatively tiny family of "typical" sequences. The AEP makes this precise and, astonishingly, pins the size of that family at almost exactly $2^(n H)$.

#definition("Typical set")[
Fix a small tolerance $epsilon > 0$. The *typical set* $A_epsilon^((n))$ is the collection of length-$n$ sequences $bold(x)$ whose per-symbol surprisal is within $epsilon$ of the entropy:
$ abs(-1/n log_2 p(bold(x)) - H(X)) <= epsilon. $
Equivalently, a typical sequence has probability $p(bold(x))$ sandwiched as $2^(-n(H+epsilon)) <= p(bold(x)) <= 2^(-n(H-epsilon))$: every typical sequence is *roughly equally likely*, each with probability about $2^(-n H)$.
]

#theorem("Asymptotic Equipartition Property")[
For a memoryless source, as $n -> infinity$:
+ The probability that the emitted sequence lies in the typical set approaches $1$. (Almost every sequence you actually see is typical.)
+ The number of typical sequences is at most $2^(n(H + epsilon))$ and, for large $n$, at least $(1-epsilon) 2^(n(H-epsilon))$. (There are about $2^(n H)$ of them.)
]

#proof[
*Why typical sequences carry almost all the probability.* The surprisal of a block is $-log_2 p(bold(x)) = -log_2 product_i p(x_i) = sum_i (-log_2 p(x_i))$, a *sum* of $n$ independent per-symbol surprisals. Each per-symbol surprisal $-log_2 p(x_i)$ has, by definition, average value $H(X)$ (entropy _is_ the average surprisal). So $-1/n log_2 p(bold(x))$ is an *average of $n$ independent draws* of a quantity whose mean is $H(X)$. By the Law of Large Numbers (Chapter 10) - averages of many independent draws cluster around the true mean - this quantity converges to $H(X)$, so the probability it lands within $epsilon$ of $H(X)$ goes to $1$. That probability is _exactly_ the probability of being typical.

*Why there are about $2^(n H)$ of them.* Every typical sequence has probability at least $2^(-n(H+epsilon))$. Since all probabilities of typical sequences add up to at most $1$,
$ 1 >= sum_(bold(x) in A_epsilon^((n))) p(bold(x)) >= abs(A_epsilon^((n))) dot 2^(-n(H+epsilon)), $
which rearranges to $abs(A_epsilon^((n))) <= 2^(n(H+epsilon))$ - an upper bound on the count. For the lower bound, once $n$ is large the typical set carries probability at least $1 - epsilon$; since each typical sequence has probability at most $2^(-n(H-epsilon))$, you need at least $(1-epsilon) 2^(n(H-epsilon))$ of them to accumulate that much probability. Sandwiched, the count is $approx 2^(n H)$.
]

Now stand back and see the payoff. The AEP is a *coding strategy in disguise*, and it gives a second, gorgeous proof of the source coding theorem:

#keyidea[
Out of the $m^n = 2^(n log_2 m)$ conceivable length-$n$ sequences, only about $2^(n H)$ are *typical*, and the rest almost never happen. So here is a compressor: number the typical sequences $0, 1, 2, dots$ and transmit a sequence by sending its number. A number up to $2^(n H)$ takes about $n H$ bits to write down, that is $H$ bits *per symbol*. The atypical sequences we handle with a longer fallback code, but since they occur with vanishing probability, their cost averages to nothing. The result is $approx H$ bits per symbol, the floor, reached. _Entropy is the floor because it is the exponent in the count of sequences that actually occur._
]

#fig([The space of all $2^(n log_2 m)$ length-$n$ sequences. The typical set is a vanishingly small sliver, only $approx 2^(n H)$ sequences, yet it captures essentially all the probability. Compression means giving the sliver short numbers.],
cetz.canvas({
  import cetz.draw: *
  rect((0,0),(8,3.2), fill: rgb("#f4f6f8"), stroke: rgb("#d0d7de"))
  content((4,2.85), box(width: 7.6cm, inset: 2pt, align(center, text(size: 8pt, fill: rgb("#777"))[all $2^(n log_2 m)$ sequences (almost all near-impossible)])))
  // typical sliver
  rect((0.5,0.4),(3.2,1.9), fill: rgb("#cdeccd"), stroke: rgb("#0b6e4f"))
  content((1.85,1.45), box(width: 2.3cm, inset: 2pt, align(center, text(size: 8pt, fill: rgb("#0b6e4f"))[typical set])))
  content((1.85,1.0), box(width: 2.3cm, inset: 2pt, align(center, text(size: 7.5pt, fill: rgb("#0b6e4f"))[$approx 2^(n H)$])))
  content((1.85,0.62), box(width: 2.3cm, inset: 2pt, align(center, text(size: 7pt, fill: rgb("#0b6e4f"))[prob. $approx 1$])))
}))

#aside[
The AEP is the information-theory twin of a phenomenon physicists call the _equipartition_ of energy and statisticians call _concentration of measure_: in high dimensions, "almost everything" piles up in a thin shell. Shannon's typical set, Boltzmann's entropy in thermodynamics, and the modern "concentration" inequalities behind machine-learning generalization bounds are all the same law of large numbers wearing different costumes. That $H$ in $S = k log W$ on Boltzmann's tombstone and the $H$ in $2^(n H)$ here are not a coincidence.
]

== Putting it together: the source coding theorem

We can now state the full result, both halves at once, exactly as Shannon left it. This is the headline of the chapter and one of the cornerstones of the digital age.

#theorem("Shannon's Source Coding Theorem (Noiseless, 1948)")[
Let $X$ be a memoryless source with entropy $H(X)$ bits per symbol. Then:
+ *(Converse / lower bound.)* Every uniquely decodable code has average length $L >= H(X)$. No lossless scheme can do better, ever.
+ *(Achievability / upper bound.)* For any $epsilon > 0$ there is a code (e.g. Shannon coding on blocks of length $n$) whose average length per symbol satisfies $L_n\/n < H(X) + epsilon$. The floor is reachable to any precision.
Therefore the *minimum achievable rate* for lossless coding of $X$ is exactly $H(X)$ bits per symbol.
]

Read those two clauses together and the puzzle from the opening page is fully answered. *There is a wall, and it is at $H(X)$.* You cannot tunnel under it (clause 1). You can press right up against it (clause 2). The entropy we computed in Chapter 18 was never just a number measuring surprise. It is the precise, unbeatable cost of storing or transmitting the source, in bits, full stop.

#note[
Everything here assumed a *memoryless* source: independent symbols with known probabilities. Real data (English, images, code) has rich *dependencies*. The letter `q` is almost always followed by `u`; a blue pixel sits next to other blue pixels. For such sources the right floor is the *entropy rate* $H(cal(X)) = lim_(n->infinity) 1/n H(X_1, dots, X_n)$, the per-symbol entropy of ever-longer blocks, and the theorem generalizes (for stationary ergodic sources, via the Shannon--McMillan--Breiman theorem) with the entropy rate in place of $H(X)$. The practical catch is brutal and is the whole rest of this book: you almost never _know_ the true distribution, so real compressors must _estimate_ it as they go. That gap between the known floor and the unknown true model is where Huffman, LZ77, PPM, and neural language models all live.
]

#checkpoint[A source has entropy $H = 3.2$ bits/symbol. You code single symbols with a Shannon code. What is the most bits per symbol you might spend? Now you code blocks of $n=8$. What is the new worst case?][Single symbols: under $H + 1 = 4.2$ bits. Blocks of 8: under $H + 1\/8 = 3.2 + 0.125 = 3.325$ bits per symbol. Bigger blocks, tighter to the floor.]

== Building it in `tinyzip`: measuring the floor

Theory is only believable when you can _watch_ it. Let us add a small, honest tool to `tinyzip` (the compressor we have been assembling since Chapter 15): given any file, it computes the order-0 entropy floor, then builds the Shannon code and reports how close to the floor it actually gets. This is the diagnostic every compression engineer reaches for first. Before you optimize a coder, you measure the wall you are aiming at.

#pyrecall[In Step 6 (Chapter 18) we already wrote `tinyzip/model.py` with `entropy(data) -> float`, which reuses `utils.histogram` (Step 2, Chapter 16) to tally byte counts. We `import` it here rather than re-deriving entropy - the whole point of the project is that each step builds on the last.]

#gopython("The ceiling math.ceil and reusing histogram")[
Two ingredients are new this step. `math.ceil(x)` rounds _up_ to the next whole number - `ceil(2.37)` is `3`, `ceil(2.0)` is `2` - which is exactly the $ceil(dot)$ of the Shannon length $ell_i = ceil(-log_2 p_i)$. And `utils.histogram(data)` (Chapter 16) returns a `dict[int,int]` mapping each byte value `0..255` to how many times it appears, e.g. `histogram(b"banana")` is `{98:1, 97:3, 110:2}`. We reuse it instead of re-counting, so every function below shares one tally. A tiny taste:
```python
from math import ceil, log2
from tinyzip.utils import histogram   # Step 2 (Ch 16)
counts = histogram(b"banana")          # {b:1, a:3, n:2}
p_a = counts[ord("a")] / sum(counts.values())   # 3/6 = 0.5
print(ceil(-log2(p_a)))                # ceil(1.0) = 1 -> 'a' gets a 1-bit codeword
```
]

#project("Step 6 (continued) · model - the Shannon coder")[
This continues canonical *Step 6* (begun in Chapter 18, which gave `model.py` its `entropy` meter). We now add a *Shannon code* to the same `model.py` module: lengths $ell_i = ceil(-log_2 p_i)$, the construction whose achievability we just proved. We `import` `entropy` from Step 6 and `histogram` from Step 2 - no re-counting, no duplicated entropy - and verify in real bytes that the average length lands in the promised window $[H, H+1)$ and that the Kraft sum stays within budget. Append to `tinyzip/model.py`:

```python
from math import ceil, log2

from tinyzip.utils import histogram   # Step 2 (Ch 16): byte -> count
# entropy() already lives in this module from Step 6 (Ch 18)


def shannon_lengths(data: bytes) -> dict[int, int]:
    """Shannon code lengths l_i = ceil(-log2 p_i) for each byte value."""
    n = len(data)
    counts = histogram(data)                       # reuse Step 2's tally
    return {sym: ceil(-log2(c / n)) for sym, c in counts.items()}


def average_length(data: bytes, lengths: dict[int, int]) -> float:
    """Average bits/byte this code actually spends on THIS data."""
    n = len(data)
    counts = histogram(data)
    return sum((c / n) * lengths[sym] for sym, c in counts.items())


def kraft_sum(lengths: dict[int, int]) -> float:
    """Sum of 2^-l_i; must be <= 1 for a prefix code to exist (Kraft)."""
    return sum(2 ** (-length) for length in lengths.values())


if __name__ == "__main__":
    sample = b"the quick brown fox jumps over the lazy dog. " * 20
    h = entropy(sample)                            # Step 6, Ch 18
    lengths = shannon_lengths(sample)
    avg = average_length(sample, lengths)
    print(f"entropy floor H      = {h:.4f} bits/byte")
    print(f"Shannon avg length L = {avg:.4f} bits/byte")
    print(f"H <= L < H+1 ?         {h <= avg < h + 1}")
    print(f"Kraft sum            = {kraft_sum(lengths):.4f}  (<= 1 required)")
```

Run it and you will see something like `entropy floor H = 4.16`, `Shannon avg length L = 4.54`, `H <= L < H+1 ? True`, `Kraft sum = 0.83`. The theorem is not an abstraction. It is a `True` printed by your own code. The leftover gap (here ~0.38 bits) is exactly what Huffman (Chapter 24) and arithmetic coding (Chapter 26) will claw back. Notice the Kraft sum is comfortably under 1: the Shannon code "wastes" a little budget, which is precisely why it is not optimal.
]

#scoreboard(caption: "the floor we are aiming at (1 000-byte English sample)",
  [Raw (ASCII, 8 bits/byte)], [1000], [1.00×], [no compression - the starting point],
  [Order-0 entropy floor $H$], [≈520], [1.92×], [theoretical wall for symbol-independent coding],
  [Shannon code (this chapter)], [≈565], [1.77×], [within +1 bit/symbol; proves the floor is reachable],
  [Huffman (Chapter 24)], [≈525], [1.90×], [optimal prefix code - almost hits the floor],
)

The scoreboard tells the story of the next several chapters at a glance. The raw file is the dumb baseline. The entropy floor $H$ is the wall this chapter located. The Shannon code _reaches_ that wall to within a bit, proving it is real and touchable. Every technique to come is a campaign either to squeeze the last fractional bit out of the gap (Huffman, arithmetic coding, ANS) or to *lower the wall itself* by finding a better model of the data (LZ, PPM, neural predictors), because, as the closing identity of Volume I will insist, a lower entropy is just a better prediction.

#takeaways((
  [A *code* assigns bits to symbols; it is useful only if *uniquely decodable* (distinct messages give distinct bitstreams). *Prefix codes* (no codeword starts another) are uniquely decodable _and_ decode instantly; they are binary trees with symbols at the leaves.],
  [The *Kraft inequality* $sum_i 2^(-ell_i) <= 1$ is the exact budget on codeword lengths: a prefix code with given lengths exists iff the sum fits. *Kraft--McMillan* extends it to all uniquely decodable codes, so restricting to prefix codes costs nothing.],
  [*Lower bound:* every uniquely decodable code has average length $L >= H(X)$. The proof is just Kraft plus the tangent-line fact $log x <= x-1$. Equality holds exactly when every $-log_2 p_i$ is a whole number.],
  [*Upper bound:* the Shannon code with lengths $ceil(-log_2 p_i)$ gives $H(X) <= L < H(X)+1$ - the floor is reachable within one bit.],
  [*Block coding* spends that "+1" once per $n$-symbol block, so per-symbol overhead is $1\/n -> 0$: the floor is a limit you can approach as closely as you wish.],
  [The *AEP* explains _why_: out of $m^n$ sequences only $approx 2^(n H)$ are *typical*, yet they carry almost all the probability. Numbering the typical sequences costs $approx n H$ bits, i.e. $H$ per symbol.],
  [Putting both halves together is *Shannon's source coding theorem*: the minimum lossless rate is exactly $H(X)$. "You cannot beat entropy" is literally true _for a fixed model_. Beating a compressor means finding a better model, i.e. a lower $H$.],
))

== Exercises

#exercise("19.1", 1)[
For the alphabet $\{A,B,C,D,E\}$, decide for each length-list whether a prefix code exists, by computing its Kraft sum: (a) $1,2,3,4,4$; (b) $2,2,2,2,2$; (c) $1,2,2,3,3$. For any feasible one, actually write down a valid set of codewords.
]
#solution("19.1")[
(a) $1\/2 + 1\/4 + 1\/8 + 1\/16 + 1\/16 = 1$. Feasible (full tree). Codewords e.g. `0, 10, 110, 1110, 1111`.
(b) $5 times 1\/4 = 5\/4 > 1$. *Infeasible* - only four 2-bit strings exist, you cannot fit five.
(c) $1\/2 + 1\/4 + 1\/4 + 1\/8 + 1\/8 = 5\/4 > 1$. *Infeasible*: a 1-bit codeword eats half the budget, then two 2-bit codewords finish it, leaving nothing for the length-3 pair.
]

#exercise("19.2", 1)[
A source emits four symbols with probabilities $1\/2, 1\/4, 1\/8, 1\/8$. (a) Compute $H(X)$. (b) Give a prefix code that achieves $L = H(X)$ exactly, and explain in one sentence why exact equality is possible here.
]
#solution("19.2")[
(a) $H = 1\/2(1) + 1\/4(2) + 1\/8(3) + 1\/8(3) = 1.75$ bits. (b) Code `0, 10, 110, 111` (lengths $1,2,3,3$) gives $L = 1.75$. Equality is possible because every probability is a power of $1\/2$, so the ideal lengths $-log_2 p_i = 1,2,3,3$ are already whole numbers, with no rounding loss.
]

#exercise("19.3", 2)[
A biased coin shows heads with probability $0.9$. (a) Find $H(X)$. (b) What is the best average length of a code that codes single flips? (c) By how much (in bits/flip) does single-flip coding overpay? (d) If you code blocks of $n$ flips, what is the guaranteed upper bound on bits per flip as a function of $n$?
]
#solution("19.3")[
(a) $H = -0.9 log_2 0.9 - 0.1 log_2 0.1 approx 0.469$ bits/flip. (b) Single flips need a 1-bit codeword each, so $L = 1.0$ bit/flip (you cannot do better than one bit for a two-symbol alphabet). (c) Overpay $approx 1.0 - 0.469 = 0.531$ bits/flip - more than double the entropy. (d) Block coding guarantees $L_n\/n < H + 1\/n approx 0.469 + 1\/n$; as $n$ grows this slides to $0.469$.
]

#exercise("19.4", 2)[
Prove that if a prefix code has Kraft sum *strictly less than 1*, then the code is *not* optimal: you can shorten at least one codeword by one bit and still have a valid prefix code. (Hint: a strict inequality means the code tree has a "spare" leaf.)
]
#solution("19.4")[
If $sum_i 2^(-ell_i) < 1$, then by the leaf-counting argument the codewords claim strictly fewer than $2^(ell_max)$ bottom leaves, so the tree has an internal node with a missing child - a "dangling" branch. Take the longest codeword $ell_max$; its sibling slot is either empty or part of the spare. We can re-attach the longest codeword one level higher (drop its last bit), which keeps the prefix property (the shortened word still occupies a leaf, none of its prefixes is a codeword) and strictly reduces that codeword's length, hence reduces $L$. So any code with Kraft sum $< 1$ can be improved; optimal prefix codes always have Kraft sum exactly $1$.
]

#exercise("19.5", 2)[
Using $log_2 x <= (x-1)\/ln 2$, prove *Gibbs' inequality*: for probability lists $p$ and $q$, $-sum_i p_i log_2 p_i <= -sum_i p_i log_2 q_i$, with equality iff $q_i = p_i$ for all $i$. (This is the engine of the entropy lower bound.)
]
#solution("19.5")[
The difference is $sum_i p_i log_2 q_i - sum_i p_i log_2 p_i = sum_i p_i log_2 (q_i\/p_i)$ (sum over $i$ with $p_i > 0$). Apply $log_2 x <= (x-1)\/ln 2$ with $x = q_i\/p_i$: $sum_i p_i log_2(q_i\/p_i) <= 1\/ln 2 sum_i p_i (q_i\/p_i - 1) = 1\/ln 2 (sum_i q_i - sum_i p_i) <= 1\/ln 2 (1 - 1) = 0$. So $sum_i p_i log_2 q_i - sum_i p_i log_2 p_i <= 0$, which rearranges to the claim. Equality needs $x = 1$ in every term, i.e. $q_i = p_i$ for all $i$.
]

#exercise("19.6", 2)[
A "comma code" (unary code) separates symbols with an explicit marker: encode symbol number $k$ as $k-1$ ones followed by a single zero, so symbol $1$ is `0`, symbol $2$ is `10`, symbol $3$ is `110`, and so on. (a) Verify it is a prefix code. (b) Compute its Kraft sum for an infinite alphabet. (c) For what probability distribution is this code _optimal_ (hits the floor)?
]
#solution("19.6")[
(a) The only place a `0` appears is at the end of a codeword, so a complete codeword is recognizable the instant you hit a `0`; no codeword is a prefix of another. Prefix code. (b) Codeword $k$ (for $k = 1, 2, 3, dots$) has length $k$, so the Kraft sum is $sum_(k=1)^infinity 2^(-k) = 1\/2 + 1\/4 + 1\/8 + dots = 1$. Exactly 1 - a full tree. (c) It hits the floor when $ell_k = -log_2 p_k$, i.e. $p_k = 2^(-k)$: the geometric distribution $1\/2, 1\/4, 1\/8, dots$. For that source the comma (unary) code is optimal.
]

#exercise("19.7", 3)[
Code blocks of $n=2$ symbols for the source $p = (0.7, 0.2, 0.1)$ over $\{A,B,C\}$, assuming independence. (a) Compute $H(X)$ for one symbol. (b) List the nine pair-probabilities and the Shannon length $ceil(-log_2 p)$ for each. (c) Compute the average bits per *original symbol* and confirm it lies in $[H, H + 1\/2)$.
]
#solution("19.7")[
(a) $H = -0.7 log_2 0.7 - 0.2 log_2 0.2 - 0.1 log_2 0.1 approx 0.360 + 0.464 + 0.332 = 1.157$ bits.
(b) Pairs (prob, length $ceil(-log_2 p)$): $A A$ ($0.49$, $2$); $A B$ and $B A$ ($0.14$, $3$); $A C$, $C A$ ($0.07$, $4$); $B B$ ($0.04$, $5$); $B C$, $C B$ ($0.02$, $6$); $C C$ ($0.01$, $7$).
(c) $L_2 = 0.49(2) + 2(0.14)(3) + 2(0.07)(4) + 0.04(5) + 2(0.02)(6) + 0.01(7) = 0.98 + 0.84 + 0.56 + 0.20 + 0.24 + 0.07 = 2.89$ bits/pair, so $L_2\/2 approx 1.445$ bits/symbol. Check: $H = 1.157 <= 1.445 < H + 1\/2 = 1.657$. Inside the window. (Single-symbol Shannon coding would give worst case near $H + 1 = 2.157$; blocking already tightened it.)
]

#exercise("19.8", 3)[
*The AEP, concretely.* For the source $p = (0.8, 0.2)$ over $\{0,1\}$ and $n = 1000$: (a) compute $H(X)$ and the typical-set size estimate $2^(n H)$ (as a power of 2). (b) The total number of length-1000 binary strings is $2^1000$. What fraction (as a power of 2) of all strings is typical? (c) In words, explain how a compressor exploits this to reach $approx H$ bits/symbol.
]
#solution("19.8")[
(a) $H = -0.8 log_2 0.8 - 0.2 log_2 0.2 approx 0.2575 + 0.4644 = 0.7219$ bits. Typical-set size $approx 2^(1000 times 0.7219) = 2^(721.9)$.
(b) Fraction $approx 2^(721.9) \/ 2^1000 = 2^(-278.1)$ - an unimaginably tiny sliver, yet it holds almost all the probability.
(c) Assign each of the $approx 2^(721.9)$ typical sequences a distinct index; an index needs $approx 721.9$ bits $= 0.7219 times 1000$, i.e. $approx H$ bits per symbol. Atypical sequences get a longer fallback encoding, but since their total probability $-> 0$, they add negligibly to the average. Net rate $-> H$.
]

== Further reading

- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon, C. E. (1948). _A Mathematical Theory of Communication._] - Part I contains the source coding theorem and the typical-sequence argument in Shannon's own astonishingly clear prose. Sections 7--9 are the heart of this chapter.
- #link("https://en.wikipedia.org/wiki/Kraft%E2%80%93McMillan_inequality")[Kraft, L. (1949) and McMillan, B. (1956).] - the prefix and uniquely-decodable forms of the length budget; the proofs above follow McMillan's power-sum counting argument.
- Cover, T. M. & Thomas, J. A. _Elements of Information Theory_ (2nd ed., 2006), Chapters 3 (AEP) and 5 (Data Compression) - the standard modern treatment; our entropy-bound and AEP proofs mirror its Theorems 5.3.1 and 3.1.2.
- MacKay, D. J. C. _Information Theory, Inference, and Learning Algorithms_ (2003), Chapters 4--5 - freely available online, with an especially friendly geometric picture of typicality and the "source coding as a game" framing.

#bridge[
We now know the floor _exists_ and equals $H(X)$, and that a code can press right up against it. But the source coding theorem assumed something enormous: that the symbols are *independent* and that we *know* their probabilities. Strip that away - let symbols depend on each other, let the source feed signal into a _noisy_ channel that randomly corrupts bits - and a second, dual question appears: how much information can you reliably push _through_ noise? Chapter 20 builds the other half of Shannon's 1948 masterpiece: *mutual information*, the *capacity* of a channel, and the noisy-channel coding theorem - the surprising mirror image of everything we just proved, where the game becomes _adding_ redundancy rather than removing it.
]
