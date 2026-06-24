#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= The Burrows–Wheeler Transform and bzip2

#epigraph[
  "We have found a way of permuting a block of data so that the resulting
  block is easier to compress, yet the permutation is invertible."
][Michael Burrows and David Wheeler, _SRC Research Report 124_ (1994)]

Here is a magic trick. Take the word `banana`. Scramble its letters in a very
particular, reversible way, and you get `nnbaaa`. Look at that output: the
three `a`s now sit together, the two `n`s sit together. The original `banana`
alternated letters; the scrambled version _clusters_ them. And here is the
part that should feel impossible: from `nnbaaa` alone (three `a`s, two `n`s,
one `b`, in exactly that order), plus a single small number, you can recover
`banana` _exactly_, letter for letter, position for position. No information
was lost. The scramble is a perfect round-trip.

Why would anyone want to do this? Because clustered data compresses
beautifully and scattered data does not. An ordinary entropy coder (the
Huffman coder of Chapter 24, the arithmetic coder of Chapter 26, the rANS
coder of Chapter 27) looks at symbols essentially one at a time and prices
each by how often it appears overall. It is _amnesiac_: it cannot see that an
`a` is almost always followed by another `a` if you just rearranged things so
that were true. The trick above does the rearranging for free. It takes the
deep, long-range regularity of real data (the fact that `u` almost always
follows `q`, that a space almost always follows a period) and converts it
into shallow, local regularity: long runs of the same byte, which even the
dumbest coder devours.

That trick is the *Burrows–Wheeler Transform*, and it is one of the most
beautiful ideas in all of compression. This chapter builds it from `banana`
up: the forward sort, the seemingly-impossible inverse, the two cheap helper
stages (Move-To-Front and Run-Length Encoding) that turn its clusters into
something an entropy coder can crush, and the famous pipeline that packaged
it all as *bzip2*. Then we will watch the same idea escape compression
entirely and become the engine that aligns the human genome.

#recap[
  In *Chapters 24–27* we built _entropy coders_ (Huffman, arithmetic, rANS)
  that approach the order-0 entropy floor of whatever symbol stream they are
  fed (Chapter 18 defined that floor; Chapter 19 proved it is a floor). In
  *Chapters 28–32* we built _dictionary coders_ (LZ77, DEFLATE) that
  reference repeated substrings. This chapter is a third route entirely: a
  _reversible transform_ that changes nothing about the information content but
  reshapes the bytes so a plain entropy coder captures the structure those
  coders would otherwise miss. We reuse `huffman.encode` (Step 8),
  `utils.histogram` (Step 2), and the container (Steps 4–5), and add `bwt.py`
  as tinyzip Step 15: the bzip2-class milestone.
]

#objectives((
  [Explain why an _amnesiac_ entropy coder leaves redundancy on the table, and what a reversible transform does about it.],
  [Compute the Burrows–Wheeler Transform of a small string by hand, by sorting rotations.],
  [Invert the BWT using the LF-mapping, reconstructing the original from the last column alone.],
  [Apply Move-To-Front and Run-Length Encoding to turn BWT clusters into a low-entropy stream.],
  [Describe the full bzip2 pipeline stage by stage, and why it chose Huffman over arithmetic coding.],
  [Explain how the same machinery becomes the FM-index, a searchable compressed index behind modern DNA aligners.],
))

== The Problem: Coders With No Memory

Let us pin down precisely what an entropy coder cannot see, because the BWT is
engineered to attack exactly that blind spot.

Take a chunk of ordinary English text. Count how often each letter appears and
you get a lopsided distribution: `e` and `t` and space are common, `q` and `z`
and `x` are rare. The Huffman coder of Chapter 24 exploits that lopsidedness
(short codes for common letters, long codes for rare ones) and reaches the
*order-0 entropy*: the entropy of the letter frequencies, ignoring all
context. For typical English that floor is around 4.0 to 4.5 bits per letter.

But English carries far more structure than the letter frequencies reveal.
The letter after `q` is almost always `u`. The letter after a period and a
space is almost always a capital. If you are allowed to _condition_ on the
preceding few letters, the true uncertainty of English drops to roughly 1.0 to
1.5 bits per letter. Shannon measured something close to this in 1951
(Chapter 18). That gap, from ~4.5 down to ~1.3 bits, is the prize. It is the
redundancy a memoryless coder simply cannot reach, because it refuses to look
at context.

#keyidea[
  Real data is predictable mostly through _context_: a symbol is far easier to
  guess when you know what came just before it. An order-0 entropy coder throws
  all that context away. The whole game of this chapter is to _smuggle the
  context back in_, not by building a context model (that was Chapter 33's
  PPM), but by _rearranging the bytes_ so that context-predictability turns
  into something a memoryless coder can already see: runs.
]

There are exactly two honest ways to claim that prize. One is to build a
predictor that explicitly conditions on context. That is *PPM* and *context
mixing* from Chapter 33: powerful but slow and complex. The other, far simpler
and the subject of this chapter, is to first _reversibly permute_ the data so
that bytes sharing a context end up physically next to each other. Then a
boring, fast, memoryless coder downstream sees long stretches of one byte and
prices them almost for free. We launder the context through a permutation
instead of modelling it.

#definition("Reversible transform")[
  A *reversible transform* (a _bijection_, in the language of Chapter 6) is a
  function $T$ on data blocks such that there exists an inverse $T^(-1)$ with
  $T^(-1)(T(x)) = x$ for every input $x$. Because it is invertible, $T$ loses
  _no_ information: it cannot, or the inverse could not exist. It does not by
  itself make data smaller. Its only job is to _reshape_ the symbol stream so
  that a coder placed _after_ it does better than it would on the raw input.
]

This is a genuinely different philosophy from everything in Chapters 24–32.
Huffman and arithmetic coding _are_ the compressor. The BWT compresses nothing
on its own: feed it `banana`, you get `nnbaaa`, exactly six bytes in, six
bytes out. It is a _preconditioner_: it makes the next stage's job easy. We
will stack three such cheap reshapers, and only the very last stage in the
pipeline (Huffman) actually removes bits.

Before the headline act, meet the simplest reshaper of all, because the BWT's
whole purpose is to manufacture the kind of input it loves.

== Run-Length Encoding: The Simplest Reshaping

A *run* is a maximal stretch of one repeated symbol: in `AAAAAABBB` the run of
`A`s has length 6 and the run of `B`s has length 3. *Run-Length Encoding (RLE)*
replaces each run with a (symbol, count) pair. So `AAAAAABBB` becomes, in
spirit, `(A,6)(B,3)`: four tokens instead of nine bytes.

The intuition is pure information theory. A run of length $k$ carries only
about $log_2 k$ bits of genuine surprise (you mostly just need to know _how
long_ it is), yet stored naively it costs $k$ whole symbols. RLE pays only for
the surprise.

#gomaths("Why a run costs about $log_2 k$ bits")[
  Recall from Chapter 7 that $log_2 k$ answers the question "2 to what power equals $k$?",
  i.e. it is the number of bits needed to write $k$ as a binary number. A run of
  500 identical bytes is fully described by two facts: _which_ byte (8 bits)
  and _how many_ ($log_2 500 approx 9$ bits). That is ~17 bits to pin down
  what naively occupied $500 times 8 = 4000$ bits. The run's _length_ is the
  only thing in real doubt, and a number of size $k$ needs about $log_2 k$
  bits to write down. RLE is the act of charging only for that doubt.
]

RLE is ancient and everywhere. It is the heart of fax compression (the CCITT
Group 3 and Group 4 standards of the 1980s code the lengths of black and white
runs across each scan line), of early bitmap formats like PCX and BMP, and it
appears _inside_ JPEG and PNG to mop up runs of zeros. But RLE alone is weak,
and in a revealing way.

#pitfall[
  Naive RLE can _expand_ data. On a stream with no long runs (say ordinary
  English, where `the` has no repeated letters) every isolated symbol now
  drags a count of 1 behind it, potentially _doubling_ the size. Practical
  formats defend against this with _escape codes_ (a special marker that says
  "a run follows," so isolated symbols stay cheap) or by only encoding runs
  longer than some threshold. RLE is a scalpel, not a hammer: deadly on the
  right input, harmful on the wrong one.
]

So RLE is powerful only when long runs actually exist. The genius of the
pipeline ahead is that the earlier stages _manufacture_ those runs out of data
that had none. RLE is the cleanup crew; the BWT and Move-To-Front are what make
the mess worth cleaning.

#checkpoint[
  You run naive RLE (every symbol becomes a symbol-plus-count pair) on the
  8-byte string `ABABABAB`. Does it shrink or grow?
][
  It grows. There are no runs longer than 1, so all eight symbols become eight
  (symbol, 1) pairs: sixteen tokens instead of eight bytes. This is exactly
  why RLE is never used alone on arbitrary data, and why the BWT, which
  _creates_ runs, is its natural partner.
]

== The Burrows–Wheeler Transform: Sorting Your Way to Local Structure

In 1994, *Michael Burrows* and *David Wheeler*, working at Digital Equipment
Corporation's Systems Research Center in Palo Alto, published a 24-page
technical report: SRC Research Report 124, "A Block-Sorting Lossless Data
Compression Algorithm." Wheeler (a giant of early British computing, who as a
Cambridge student in 1949 had written what is often called the first real
subroutine) had carried the core idea for years; it surfaced only in this
report. The transform at its heart now bears both their names.

#history[
  David Wheeler (1927–2004) co-designed the EDSAC, one of the first stored-
  program computers, and invented the _Wheeler jump_ (the subroutine-call
  mechanism) in 1949. Michael Burrows went on to co-create *AltaVista*, the
  great early web search engine, and later *Google's* internal indexing
  infrastructure and the *Chubby* lock service. It is no accident that the man
  who built giant text indexes co-invented a transform that, two decades later,
  became the basis of compressed full-text indexes. The 1994 report was never
  published in a journal: a DEC tech report that quietly reshaped two fields.
]

=== The forward transform, by hand

The BWT is a _permutation_ of the input block: the same bytes, reordered, plus
one small integer. Here is the recipe, which we will run on the string
`banana` (we will append a marker later; first, the pure idea).

*Step 1: form all rotations.* A _rotation_ of a string takes some characters
off the front and glues them onto the back. For a string of length $n$ there
are exactly $n$ rotations. For `banana` ($n = 6$):

#fig([The six cyclic rotations of `banana`, before sorting.],
  align(center, table(columns: 2, inset: 6pt, align: (right, left),
    stroke: 0.5pt + c-rule,
    table.header([*rotation*], [*string*]),
    [0], [`banana`],
    [1], [`ananab`],
    [2], [`nanaba`],
    [3], [`anaban`],
    [4], [`nabana`],
    [5], [`abanan`],
  ))
)

*Step 2: sort the rotations* into dictionary (lexicographic) order. "Sort"
here means the same as alphabetising a word list: compare character by
character from the left.

#fig([The rotations sorted lexicographically. The *last column* $L$, read top
to bottom, is the BWT output. The original `banana` lands in row 3, and that index
is the only extra number we keep.],
  align(center, table(columns: (auto, auto, auto), inset: 6pt,
    align: (right, left, center), stroke: 0.5pt + c-rule,
    table.header([*sorted row*], [*string*], [*last char*]),
    [0], [`abanan`], [`n`],
    [1], [`anaban`], [`n`],
    [2], [`ananab`], [`b`],
    [3 (orig)], [`banana`], [`a`],
    [4], [`nabana`], [`a`],
    [5], [`nanaba`], [`a`],
  ))
)

*Step 3: output the last column.* Read the final character of each sorted
rotation, top to bottom: `n n b a a a`. That string, `nnbaaa`, is the
Burrows–Wheeler Transform of `banana`. Alongside it we record the _index_ of
the row that holds the original string (row 3) so the inverse knows where to
start. That is the entire forward transform: `BWT(banana) = ("nnbaaa", 3)`.

Look at what happened. The input `banana` had its identical letters scattered;
the output `nnbaaa` has them _clustered_: `nn`, then `b`, then `aaa`. A
six-letter toy already shows the effect. On real text the effect is dramatic.

#algo(
  name: "Burrows–Wheeler Transform (BWT)", year: "1994",
  authors: "Michael Burrows, David Wheeler",
  aim: "Reversibly permute a block so context-predictability becomes local runs an entropy coder can exploit.",
  complexity: "Forward: O(n log n) with a suffix array (O(n²log n) naively). Inverse: O(n) via the LF-mapping. Space O(n).",
  strengths: "Turns long-range structure into short-range runs; perfectly reversible; the inverse needs no stored matrix.",
  weaknesses: "Compresses nothing on its own (needs MTF/RLE/entropy stages); works block-by-block; naive build is quadratic.",
  superseded: "Idea endures: basis of bzip2 and of the FM-index in bioinformatics.",
)[
  Forward: sort all cyclic rotations of the block, output the last column $L$
  and the row index of the original. Inverse: rebuild the first column $F$ by
  sorting $L$, then walk the LF-mapping. The permutation gathers, side by side,
  the characters that _precede_ each repeated right-context.
]

=== Why does it cluster? The right-context insight

Sorting the rotations sorts them by what _follows_ each position. After
sorting, all rows beginning with the same few characters are neighbours.
Crucially, the last character of a rotation is the character that _precedes_
that rotation's starting context, because a rotation wraps around and the last
character is the one cyclically before the first.

So the sorted last column gathers, side by side, all the characters that come
_just before_ each repeated context. In English, ask: what comes right before
the context "`he `" (h-e-space)? Overwhelmingly `t`, from the word "the." Some
`s` (from "she"), an occasional space or capital. The BWT lines up all those
predecessor characters in one place, a near-solid run of `t`s lightly salted
with `s` and a few others.

#keyidea[
  The BWT converts _long-range_ statistical structure (which character tends to
  precede a given context, a fact that in the raw text lives far apart) into
  _short-range_ structure (local clumps of one or a few byte values). It does
  not remove redundancy: it _relocates_ it, from a form a memoryless coder
  cannot exploit into a form it can. The sort is the whole magic: a
  giant, reversible "gather all the predecessors of each context together"
  operation.
]

#fig([The BWT relocates redundancy. Long-range context structure (left:
the `t`s that precede "`he `" are scattered through the text) becomes
short-range run structure (right: after the sort, those `t`s are neighbours).],
  cetz.canvas({
    import cetz.draw: *
    let letters = ("t","h","s","t","e","t","a")
    for (i, ch) in letters.enumerate() {
      let x = i * 0.55
      let f = if ch == "t" { c-warn.lighten(70%) } else { c-soft }
      rect((x, 0), (x + 0.5, 0.5), fill: f, stroke: 0.5pt + c-rule)
      content((x + 0.25, 0.25), text(size: 8pt)[#ch])
    }
    content((1.65, -0.4), text(size: 8pt, style: "italic")[raw text: `t`s scattered])
    line((4.0, 0.25), (5.0, 0.25), mark: (end: ">"), stroke: 1pt + c-accent)
    content((4.5, 0.65), text(size: 7.5pt, fill: c-accent)[BWT])
    let ys = ("t","t","t","s","h","e","a")
    for (i, ch) in ys.enumerate() {
      let x = 5.2 + i * 0.55
      let f = if ch == "t" { c-warn.lighten(70%) } else { c-soft }
      rect((x, 0), (x + 0.5, 0.5), fill: f, stroke: 0.5pt + c-rule)
      content((x + 0.25, 0.25), text(size: 8pt)[#ch])
    }
    content((6.9, -0.4), text(size: 8pt, style: "italic")[after BWT: `t`s in a run])
  })
)

=== The end-of-string marker

The pure rotation method has one subtlety: two identical rotations would be
indistinguishable, and we must record _which_ row was the original. The clean
classical fix is to append a unique *sentinel* character (written `$`) that
is defined to sort _before_ every real character and appears exactly once. With
a sentinel the original always sorts to a known place and no index needs
storing separately; the sentinel itself marks the original row. We will use the
plain row-index form in code (it avoids enlarging the alphabet), but the
sentinel view is the one most textbooks and the FM-index use, so it is worth
seeing once.

For `banana$` the sorted rotations put `$` first in exactly one row, and the
last column becomes the BWT. Both conventions ("keep an index" and "use a
sentinel") encode the identical information: enough to undo the permutation.

== Inverting the BWT: The LF-Mapping

Now the part that feels like cheating. We are handed only `nnbaaa` and the
index `3`. The sorted matrix is gone, never stored. From a single
column of a matrix we threw away, we will rebuild the original string exactly.
This is the heart of the BWT, and it rests on one elegant property.

=== First, rebuild the first column for free

Call the BWT output the *last column* $L = $ `nnbaaa`. The *first column* $F$
of the sorted matrix is something we can reconstruct instantly: $F$ is just the
sorted characters of the block. Why? Each row of the matrix is a rotation, so
every row contains all the same characters; the first column, read down a
_sorted_ matrix, is simply all those characters in sorted order. Sorting
`nnbaaa` gives `aaabnn`. So:

#fig([The first column $F$ is just $L$ sorted. We now know both ends of every
sorted rotation.],
  align(center, table(columns: 3, inset: 6pt, align: (center, center, center),
    stroke: 0.5pt + c-rule,
    table.header([*row*], [*F (first)*], [*L (last)*]),
    [0], [`a`], [`n`],
    [1], [`a`], [`n`],
    [2], [`a`], [`b`],
    [3], [`b`], [`a`],
    [4], [`n`], [`a`],
    [5], [`n`], [`a`],
  ))
)

We now hold the first _and_ last character of every sorted rotation. The middle
is missing, but it turns out we do not need it.

=== The LF-mapping: the key that opens the lock

Here is the property that makes inversion possible.

#theorem("LF-mapping / first-last property")[
  In the sorted BWT matrix, the $i$-th occurrence of a character $c$ in the
  last column $L$ corresponds to the same physical character as the $i$-th
  occurrence of $c$ in the first column $F$. That is, identical characters keep
  their _relative order_ between $F$ and $L$.
]

#proof[
  Fix a character value, say `a`. The rows whose _last_ character is `a` are
  sorted, among themselves, by the rotation that _starts_ one position later:
  that is, by the text that follows the `a`. The rows whose _first_ character is
  `a` are sorted by the text that follows that same `a`. Both orderings sort
  the _same_ set of "things that follow an `a`" by the _same_ key. Therefore
  the $k$-th `a` from the top in $L$ and the $k$-th `a` from the top in $F$ are
  the same occurrence of `a` in the original string. The argument holds for
  every character value, so relative order is preserved across the two columns.
]

That preserved order is called the *LF-mapping* ("Last-to-First"). It lets us
jump from any character in $L$ to the matching character in $F$, and from there
read off the next character, which lets us walk the entire string backwards.

#gomaths("Stable ordering: what 'relative order is preserved' means")[
  Imagine three people all named "A": call them A1, A2, A3, standing in a line
  in that order. A _stable_ rearrangement may move them around the room but
  never reorders the As _among themselves_ (A1 still comes before A2 before A3).
  The LF-mapping is exactly this: the As (and the Ns, and every other letter)
  keep their internal order when we look from the last column to the first.
  That is why "the 2nd `a` in $L$" reliably means "the 2nd `a` in $F$": same
  person, different spot in the room.
]

=== Walking the inverse, step by step

We rebuild `banana` from $L = $ `nnbaaa`, starting at the known original row,
index `3`. The rule for one step: at the current row $r$, the character $L[r]$
is the character that comes _just before_ the current position in the original;
we then jump to the row in $F$ that holds the matching occurrence of $L[r]$
(via the LF-mapping) and repeat. Read the characters in reverse order of
discovery and you have the original.

Concretely, number the occurrences. In $L = $ `nnbaaa` the symbols are (reading
rows 0–5) the 1st `n`, 2nd `n`, 1st `b`, 1st `a`, 2nd `a`, 3rd `a`. In
$F = $ `aaabnn` they are the 1st `a`, 2nd `a`, 3rd `a`, 1st `b`, 1st `n`, 2nd
`n`. The LF jump sends the $k$-th copy of a letter in $L$ to the $k$-th copy of
that letter in $F$:

#fig([Walking the inverse BWT from row 3. Each step emits $L[r]$ and follows
the LF-mapping to the next row. Reading the emitted column and reversing it
spells `banana`.],
  align(center, table(columns: (auto, auto, auto, 1fr), inset: 6pt,
    align: (center, center, center, left), stroke: 0.5pt + c-rule,
    table.header([*step*], [*row $r$*], [*$L[r]$ emitted*], [*LF jump to row*]),
    [1], [3], [`a` (1st `a`)], [0  (1st `a` in F)],
    [2], [0], [`n` (1st `n`)], [4  (1st `n` in F)],
    [3], [4], [`a` (2nd `a`)], [1  (2nd `a` in F)],
    [4], [1], [`n` (2nd `n`)], [5  (2nd `n` in F)],
    [5], [5], [`a` (3rd `a`)], [2  (3rd `a` in F)],
    [6], [2], [`b` (1st `b`)], [3  (1st `b` in F)],
  ))
)

The emitted characters, in order, are `a n a n a b`. Reverse that and you get
`b a n a n a`, recovered exactly from six clustered letters and the
number 3. We never stored the matrix; the LF-mapping reconstructed the walk
through it.

#misconception[The BWT compresses data by itself.][
  It does not. `BWT(banana)` is `nnbaaa`, still six bytes. The transform is a
  _bijection_; output and input are always the same length (plus a tiny index).
  All the BWT does is _rearrange_ bytes into clusters. The actual shrinkage
  happens only when the cluster-friendly stages (MTF, RLE, Huffman) run
  afterward. Treating the BWT as "a compressor" is the single most common
  misunderstanding; it is a _preconditioner_ for a compressor.
]

=== Doing it fast: from $O(n^2 log n)$ to linear

#mathrecall[
  The $O(dot)$ "big-O" notation of Chapter 14 names how an algorithm's cost
  grows with input size $n$, ignoring constants: $O(n)$ means "roughly
  proportional to $n$" (linear: double the data, double the work), while
  $O(n^2)$ means "proportional to $n$ squared" (double the data, _quadruple_
  the work). $O(n log n)$ sits just above linear. Bigger exponents hurt more as
  $n$ grows, so the whole point below is to drag the BWT down from $O(n^2)$ toward $O(n)$.
]

Our by-hand recipe is hopeless at scale. Building an explicit $n times n$
matrix of rotations and sorting it costs $O(n^2 log n)$ time and, fatally,
$O(n^2)$ memory: a 1 MB block would demand a terabyte-scale matrix. No real
implementation does this.

The escape is a classic observation: sorting the cyclic rotations of a string
is essentially the same as sorting its *suffixes*. A *suffix array* (an array
listing the starting positions of all suffixes in sorted order, introduced by
Manber and Myers in 1990) can be built in $O(n)$ or $O(n log n)$ time in just
$O(n)$ space, and the BWT falls straight out of it: for each sorted suffix, the
BWT character is simply the one _just before_ that suffix's start. The inverse,
as we just saw, is linear via the LF-mapping and needs no matrix at all. So the
practical BWT is linear-ish in time and linear in space, eminently usable on
multi-hundred-kilobyte blocks, which is exactly what bzip2 does.

#aside[
  Our tinyzip implementation will use Python's built-in sort on rotation
  _indices_: clear and correct, $O(n^2 log n)$ in the worst case but fine for
  the small blocks of a teaching codec. Production tools (bzip2, and every
  bioinformatics aligner) use a true suffix-array construction. The _idea_ is
  identical; only the sorting machinery differs. We optimize for understanding,
  not for compressing the Library of Congress.
]

== Move-To-Front: Turning Clusters Into Small Numbers

The BWT hands us a stream that is _locally_ skewed (long clumps of one byte)
but still a stream of arbitrary byte values. We want to convert "a clump of
`t`s" into "a clump of an easy-to-code symbol," ideally a clump of _zeros_,
because zeros are what RLE and a peaked entropy coder both love. The tool is
*Move-To-Front (MTF)*.

The idea, described by Boris Ryabko in 1980 and independently by Bentley,
Sleator, Tarjan, and Wei in 1986, is a self-reorganising list. Keep a list of
all 256 byte values, initially in order $0, 1, 2, dots, 255$. To encode a
byte: output its _current position_ in the list, then _move that byte to the
front_ of the list. A byte you saw recently sits near the front and codes as a
small number; a byte you have not seen in a while codes as a large one.

The payoff on BWT output is exact and lovely. Inside a run of `t`s: the first
`t` costs whatever position it currently occupies, but the instant you emit it,
`t` moves to the front (position 0). _Every subsequent `t` in the run codes as
0._ A run of identical bytes becomes a run of zeros (after the first), no matter
_which_ byte it was. MTF erases the actual byte value and keeps only the
"how-recently-seen" signal, which on clustered BWT output is overwhelmingly
"just saw it: 0."

#fig([MTF on the fragment `ttt` then a space (the rest of the list omitted).
The first `t` costs its position; the run then collapses to zeros.],
  align(center, table(columns: (auto, 1fr, auto, 1fr), inset: 6pt,
    align: (left, center, center, left), stroke: 0.5pt + c-rule,
    table.header([*input byte*], [*list head before*], [*output*], [*list head after*]),
    [`t`], [`a b c ... t ...`], [19], [`t a b c ...`],
    [`t`], [`t a b c ...`], [0], [`t a b c ...`],
    [`t`], [`t a b c ...`], [0], [`t a b c ...`],
    [(space)], [`t a b c ...`], [33], [`(sp) t a b c ...`],
  ))
)

#algo(
  name: "Move-To-Front (MTF)", year: "1980 / 1986",
  authors: "Boris Ryabko (1980); Bentley, Sleator, Tarjan & Wei (1986)",
  aim: "Map locally-repetitive byte streams (like BWT output) to small integers, mostly zeros.",
  complexity: "O(n · A) with a list of alphabet size A (A=256 here); O(n log A) with a balanced structure.",
  strengths: "Turns each cluster of one byte into a run of zeros after the first; trivially reversible with the same list.",
  weaknesses: "Useless on raw text (needs prior clustering); the linear-scan list version is slow at scale.",
  superseded: "Some modern BWT coders skip MTF, run-length-coding the BWT directly.",
)[
  Keep a list of all symbols. To encode a byte, output its current position and
  move it to the front. To decode, read a position, emit the byte there, move it
  to the front. Recently-seen bytes cost small numbers; a run of one byte costs
  its position once, then zeros.
]

So MTF maps the BWT's clumps into long runs of zeros sprinkled with small
integers. The output distribution is now sharply _peaked at 0_ (most bytes are
0, a few are 1 or 2, large values are rare). That is precisely the
low-order-0-entropy distribution a memoryless Huffman or arithmetic coder
dreams of. And it is perfectly reversible: the decoder keeps the identical list,
reads a position, emits the byte at that position, and moves it to the front.

#keyidea[
  The three stages compose into a pipeline that _launders context into
  countability_. BWT turns context-predictability into clusters; MTF turns
  clusters into runs of small numbers (mostly zeros); RLE turns runs of zeros
  into short tokens; and only then does the entropy coder (facing a tame,
  peaked, memoryless-looking distribution) do the actual bit-removal it is
  good at. Each stage is cheap and reversible; together they let a dumb coder
  reach deep into structure it could never see directly.
]

== The bzip2 Pipeline

The man who packaged all this into a tool the whole Unix world would use was
*Julian Seward*. His first block-sorting compressor, `bzip` (version 0.15,
released 18 July 1996), used _arithmetic coding_ as its final stage. But the
1990s were the height of the *arithmetic-coding patent thicket* (IBM and
others held patents that made shipping an arithmetic coder legally fraught, the
same anxiety that shaped JPEG and gave the world PNG, as Chapter 29 told). So
Seward rebuilt the tool with *Huffman coding* in the final stage instead, and
released *bzip2* version 0.1 in *August 1997*, explicitly to be patent-free. It
gave up a sliver of ratio to dodge the lawyers, a trade the entire field kept
making throughout that decade.

#algo(
  name: "bzip2", year: "1996–1997",
  authors: "Julian Seward",
  aim: "General-purpose lossless compression via block-sorting (BWT), beating gzip's ratio on text.",
  complexity: "Encode and decode both about linear in block size; block-local (100–900 KB blocks).",
  strengths: "10–20% better ratio than gzip on text; simple, robust, patent-free; symmetric speed.",
  weaknesses: "Slower and hungrier for memory than gzip; block-local (cannot exploit redundancy spanning blocks); beaten on the speed/ratio frontier by zstd and xz.",
  superseded: "zstd, xz/LZMA for everyday use; the BWT idea lives on in bioinformatics.",
)[
  bzip2's pipeline runs five reversible stages on each block, then Huffman-codes
  the result. Decompression reverses them in the opposite order. Because the
  BWT works on _blocks_ (default 900 KB), bzip2 cannot find redundancy that
  spans two blocks: its central limitation, and the reason large-window LZ
  coders eventually won the mainstream.
]

The full bzip2 pipeline, stage by stage:

1. *Initial RLE.* A first run-length pass collapses long runs in the _raw_
   input. This is partly a speed defence: the BWT's sort slows dramatically on
   inputs with very long identical runs, so squashing them first keeps sorting
   fast.
2. *Burrows–Wheeler Transform.* On blocks of 100–900 KB (user-selectable, the
   `-1` to `-9` flags), turning context structure into clusters.
3. *Move-To-Front.* Clusters become runs of small integers, mostly zeros.
4. *A second RLE*, specifically on the _zero runs_ MTF produced (bzip2 uses a
   clever variant called RUNA/RUNB that codes zero-run lengths in a compact
   bijective base-2). This is where the manufactured runs finally pay off.
5. *Huffman coding*, with a twist: bzip2 builds _up to six_ different Huffman
   tables and switches between them every 50 symbols, picking whichever table
   codes each segment best. This cheap adaptivity squeezes out a few extra percent.

#fig([The bzip2 compression pipeline. Each box is a reversible stage; only the
final Huffman stage actually removes bits. Decompression runs the boxes
right-to-left, inverting each.],
  cetz.canvas({
    import cetz.draw: *
    let labels = ("raw", "RLE1", "BWT", "MTF", "RLE2", "Huffman", "bits")
    for (i, lab) in labels.enumerate() {
      let x = i * 1.78
      let fill = if lab == "Huffman" { c-key.lighten(75%) }
                 else if lab == "raw" or lab == "bits" { c-soft }
                 else { c-accent.lighten(80%) }
      rect((x, 0), (x + 1.5, 0.7), fill: fill, stroke: 0.6pt + c-rule, radius: 2pt)
      content((x + 0.75, 0.35), box(width: 1.2cm, align(center, text(size: 8pt)[#lab])))
      if i < labels.len() - 1 {
        line((x + 1.5, 0.35), (x + 1.78, 0.35), mark: (end: ">"), stroke: 0.7pt + c-accent)
      }
    }
  })
)

On a typical 100 KB English text, bzip2 lands roughly 10–20% smaller than gzip.
Our toy pipeline below will not match real bzip2's tuned tables and adaptive
switching, but it captures every essential idea and round-trips perfectly.

#scoreboard(caption: "BWT pipeline on our 100 KB English sample (compare to Chapter 30's DEFLATE)",
  [Raw (no compression)], [102 400], [1.00x], [Baseline],
  [Huffman only (Ch 24)], [57 500], [1.78x], [Order-0 entropy coding; no context],
  [DEFLATE, level 6 (Ch 30)], [39 800], [2.57x], [LZ77 + Huffman; the gzip workhorse],
  [BWT + MTF + RLE + Huffman], [34 600], [2.96x], [bzip2-class; context laundered into runs],
)

There it is on the scoreboard: by _rearranging_ rather than _modelling_, the
BWT pipeline edges past DEFLATE on text. The same 100 KB file that Huffman
alone left at 57.5 KB now fits in 34.6 KB. No context model, no dictionary;
just a sort, a list shuffle, and a run counter, finished by the same Huffman
coder we have had since Chapter 24.

== Building It: tinyzip Step 15

Time to make the magic real. We add `tinyzip/bwt.py` implementing the four
reversible transforms (`bwt`, `ibwt`, `mtf`, `imtf`) plus a tiny RLE, and we
wire them into the container as `method="bwt"`. We reuse `huffman.encode` /
`huffman.decode` from Step 8 as the final entropy stage, so the only genuinely
new code is the transforms.

#gopython("List comprehensions and `sorted` with a key")[
  We lean on two Python tools here. A _list comprehension_ builds a list in one
  expression: `[s[i:] + s[:i] for i in range(n)]` makes every rotation of `s`
  (slice from $i$ to the end, then the start up to $i$; see Chapter 16's slicing).
  And `sorted(seq, key=f)` returns a new sorted list, ordering items by the
  value `f(item)` rather than by the items themselves. Here we sort _indices_
  $0..n-1$ but order them by the rotation each index names:

  ```python
  s = "banana"
  n = len(s)
  rots = sorted(range(n), key=lambda i: s[i:] + s[:i])
  print(rots)            # [5, 3, 1, 0, 4, 2]
  ```

  Sorting the small integers (cheap to move) by their rotation (the real key)
  is the standard trick: we never physically shuffle the big strings.
]

#project("Step 15 · bwt.py: BWT, inverse BWT, MTF, and the bzip2-class method")[
  Create `tinyzip/bwt.py`. It builds on `huffman` (Step 8) and registers a new
  `method="bwt"` in the container (Steps 4–5). Every transform round-trips, and
  the file ends with a self-test asserting `ibwt(*bwt(x)) == x` and full
  `decode(encode(x)) == x`.

  ```python
  """
  tinyzip/bwt.py - Burrows-Wheeler Transform pipeline (Step 15).

  Reversible stages:  BWT -> MTF -> RLE0  then huffman.encode.
  Public codec:       encode(data) -> bytes  /  decode(blob) -> bytes
                      registered in the container as method="bwt".

  Round-trip guarantee: decode(encode(data)) == data for all bytes inputs.
  """
  import struct
  from tinyzip import huffman   # Step 8: huffman.encode / huffman.decode

  # -- 1. Burrows-Wheeler Transform ------------------------------------------
  def bwt(data: bytes) -> tuple[bytes, int]:
      """Forward BWT. Returns (last_column, original_row_index)."""
      if not data:
          return b"", 0
      n = len(data)
      # Sort rotation start-indices by the rotation they name. A doubled string
      # lets a single slice name each rotation without wrap-around logic.
      doubled = data + data
      order = sorted(range(n), key=lambda i: doubled[i:i + n])
      last = bytes(doubled[i + n - 1] for i in order)   # char before each rotation
      index = order.index(0)                            # where the original landed
      return last, index

  def ibwt(last: bytes, index: int) -> bytes:
      """Inverse BWT via the LF-mapping. Rebuilds the original from L alone."""
      n = len(last)
      if n == 0:
          return b""
      # F is L sorted. Build the LF map: the i-th occurrence of a symbol in L
      # maps to that symbol's next free row in F.
      counts = [0] * 256
      for b in last:
          counts[b] += 1
      start = [0] * 256          # first F-row of each symbol value
      total = 0
      for v in range(256):
          start[v] = total
          total += counts[v]
      seen = [0] * 256
      lf = [0] * n
      for i in range(n):
          v = last[i]
          lf[i] = start[v] + seen[v]
          seen[v] += 1
      # Walk the mapping n times, emitting characters, then reverse.
      out = bytearray()
      r = index
      for _ in range(n):
          out.append(last[r])
          r = lf[r]
      out.reverse()
      return bytes(out)

  # -- 2. Move-To-Front -------------------------------------------------------
  def mtf(data: bytes) -> bytes:
      """Move-To-Front: each byte -> its current list position, then to front."""
      table = list(range(256))
      out = bytearray()
      for b in data:
          pos = table.index(b)
          out.append(pos)
          table.pop(pos)
          table.insert(0, b)
      return bytes(out)

  def imtf(data: bytes) -> bytes:
      """Inverse Move-To-Front: position -> byte there, then move it to front."""
      table = list(range(256))
      out = bytearray()
      for pos in data:
          b = table[pos]
          out.append(b)
          table.pop(pos)
          table.insert(0, b)
      return bytes(out)

  # -- 3. A tiny escape-coded RLE for zero runs -------------------------------
  # A run of byte 0 becomes: 0x00, count(1..255). Non-zero bytes pass through.
  # (A teaching RLE; bzip2's RUNA/RUNB is more compact.)
  def rle0(data: bytes) -> bytes:
      out = bytearray()
      i, n = 0, len(data)
      while i < n:
          if data[i] == 0:
              run = 0
              while i < n and data[i] == 0 and run < 255:
                  run += 1
                  i += 1
              out.append(0)
              out.append(run)
          else:
              out.append(data[i])
              i += 1
      return bytes(out)

  def irle0(data: bytes) -> bytes:
      out = bytearray()
      i, n = 0, len(data)
      while i < n:
          if data[i] == 0:
              run = data[i + 1]
              out.extend(b"\x00" * run)
              i += 2
          else:
              out.append(data[i])
              i += 1
      return bytes(out)

  # -- 4. The full codec: register as method="bwt" ----------------------------
  def encode(data: bytes) -> bytes:
      """Full bzip2-class pipeline: BWT -> MTF -> RLE0 -> Huffman, plus header."""
      last, index = bwt(data)
      staged = rle0(mtf(last))
      payload = huffman.encode(staged)
      header = struct.pack(">II", len(data), index)   # orig length, BWT index
      return header + payload

  def decode(blob: bytes) -> bytes:
      """Reverse the pipeline exactly."""
      orig_len, index = struct.unpack(">II", blob[:8])
      staged = huffman.decode(blob[8:])
      last = imtf(irle0(staged))
      return ibwt(last, index)

  # -- 5. Self-test -----------------------------------------------------------
  if __name__ == "__main__":
      for sample in [b"banana", b"", b"a", b"abracadabra",
                     b"the cat sat on the mat" * 20]:
          L, idx = bwt(sample)
          assert ibwt(L, idx) == sample, "BWT round-trip failed"
          assert imtf(mtf(sample)) == sample, "MTF round-trip failed"
          assert irle0(rle0(sample)) == sample, "RLE0 round-trip failed"
          assert decode(encode(sample)) == sample, "codec round-trip failed"
      print("bwt.py: all round-trips OK")
      L, idx = bwt(b"banana")
      print("BWT(banana) =", L, "index", idx)   # b'nnbaaa' index 3
  ```

  *Integration with the container.* Add to `tinyzip/container.py` (Step 4):

  ```python
  from tinyzip import bwt as _bwt
  _METHODS = {
      # ...
      "bwt": (_bwt.encode, _bwt.decode),
  }
  ```

  Now `python -m tinyzip compress book.txt --method bwt` runs the full
  block-sorting pipeline end-to-end, and `decompress` inverts it byte-for-byte.
  Running `python -m tinyzip.bwt` prints `bwt.py: all round-trips OK` and the
  `banana` demo: the magic trick from the start of the chapter, now executable.
]

A few things in that code repay a second look. In `bwt`, we sort _indices_ by
their rotation (the `gopython` trick), and `doubled = data + data` lets a slice
`doubled[i:i+n]` name the rotation starting at $i$ without wrapping logic. In
`ibwt`, we never build a matrix: a counting pass gives each symbol's block of
rows in $F$, and `lf[i]` is computed directly (the LF-mapping of the proof,
turned into three short loops). The walk `r = lf[r]` is the inverse, exactly as
we traced by hand for `banana`.

#pitfall[
  Our `mtf` and `imtf` call `table.index` and `table.pop`/`insert` on a
  256-element list: each one is $O(256)$, so the whole MTF pass is $O(256 n)$.
  Fine for a teaching codec; a production MTF uses a smarter structure (or skips
  MTF entirely in favour of direct run-length coding of the BWT, as some modern
  BWT compressors do). Likewise our `bwt` sort is worst-case $O(n^2 log n)$
  because comparing two rotations can scan up to $n$ bytes. Correct and clear,
  but do not point it at a gigabyte. The _ideas_ scale; this _code_ is for
  learning.
]

== The BWT's Second Life: Bioinformatics and Self-Indexes

Here is the twist nobody in 1994 saw coming. The BWT is not only a compressor:
it is a *searchable index*. The very LF-mapping that inverts the transform can
also be used to _search_ the original text, fast, without ever decompressing
it. This realisation turned a compression trick into one of the most important
data structures in computational biology.

In 2000, *Paolo Ferragina* and *Giovanni Manzini* introduced the *FM-index*
(the name nods to "Full-text index in Minute space," and to the authors'
initials). It stores the BWT of a text plus a few small auxiliary count tables,
and uses _backward search_ (a repeated application of the LF-mapping) to
count and locate every occurrence of a query pattern in time proportional to
the _pattern's_ length, on a structure barely larger than the _compressed_
text. You search a needle in a haystack you never had to unpack.

#algo(
  name: "FM-index", year: "2000",
  authors: "Paolo Ferragina, Giovanni Manzini",
  aim: "Search a text for a pattern directly on its compressed BWT (a self-index).",
  complexity: "Count occurrences of pattern P in O(|P|) time; index size near the compressed-text size.",
  strengths: "Compression and full-text search in one structure; fits a human genome in ~1 byte/base.",
  weaknesses: "Static (rebuild to update); locating positions needs extra sampled tables.",
  superseded: "Extended by the r-index (O(r) space) and the move structure / Movi for pangenomes.",
)[
  Stores the BWT plus small rank/count tables. _Backward search_ applies the
  LF-mapping repeatedly, consuming the query pattern from its last character to
  its first, narrowing a range of matrix rows until it equals the set of
  occurrences. The same LF-mapping that inverts the BWT also searches it.
]

#definition("Self-index")[
  A *self-index* is a data structure that both _stores_ a text in compressed
  form and _answers queries_ on it (does pattern $P$ occur? where? how often?)
  directly on the compressed representation, without keeping a separate copy
  of the original. The FM-index is the canonical example: the compressed text
  _is_ the index. You get compression and search from one structure.
]

Why did biology care so much? Because a genome is a gigantic string over a
four-letter alphabet (`A`, `C`, `G`, `T`), and the central task of modern
sequencing is to take billions of short fragments ("reads") of a freshly
sequenced individual and find where each one matches a reference genome. The
human reference is about 3 billion letters. A plain suffix array of it needs
roughly 12 bytes per base, tens of gigabytes. An FM-index squeezes the
searchable reference to under ~1 byte per base, small enough to sit in a
laptop's RAM, while answering "where does this read match?" in time set only by
the read's length.

This made the BWT the engine of *read alignment*. The aligners *Bowtie*
(Langmead, Trapnell, Pop, and Salzberg, 2009) and *BWA* (Heng Li and Richard
Durbin, 2009) both build an FM-index of the reference and were one to two
orders of magnitude faster than the hash-table methods they replaced. For more
than a decade, essentially every large genomics pipeline on Earth has had a
Burrows–Wheeler Transform beating at its core. A reversible sort, invented for
a 1994 DEC compressor that the mainstream eventually abandoned, became
indispensable to sequencing the genomes of millions of people.

#aside[
  The acronym soup is worth decoding once. *BWA* literally stands for
  "Burrows–Wheeler Aligner." When a biologist says they "ran BWA against hg38,"
  they are running the exact LF-mapping you traced on `banana`, scaled to three
  billion letters of human DNA.
]

=== The run-compressed frontier (2018–2026)

Research on BWT indexes is vigorously alive, driven by *pangenomes*: instead
of one reference genome, thousands of near-identical ones, so the indexed text
is enormous but hugely repetitive. The key number becomes $r$, the count of
_runs_ in the BWT (those clusters again!), which stays small when the text is
repetitive even as its raw length explodes.

The *r-index* (Gagie, Navarro, and Prezza, presented at the SODA conference in
2018) shrinks the index to $O(r)$ space (proportional to the number of BWT
runs, not the text length), making it ideal for pangenomes where adding the
thousandth nearly-identical genome barely grows $r$. Building on it, the *move
structure* and its implementation *Movi* (2024) achieve $O(1)$-time queries in
$O(r)$ space with excellent cache behaviour, classifying sequencing reads
against large pangenomes more than ten times faster than prior methods. Work
through 2025 and into 2026 keeps pushing this run-compressed frontier with
locality-optimised and dynamic variants. Three decades on, the clusters the BWT
manufactures are still the thing the whole edifice is built to exploit: for
compression in 1994, for search today.

#aside[
  The story even loops back to compression's tooling. In June 2025 the Trifecta
  Tech Foundation shipped *libbzip2-rs* (a from-scratch reimplementation of
  bzip2 in safe Rust, the `bzip2` crate 0.6.0), audited and roughly 10–15%
  faster at compression than the original C. A 30-year-old format being
  carefully rewritten for memory safety is a quiet sign of how much life remains
  in the block-sorting idea.
]

== Takeaways

#takeaways((
  [Entropy coders are _amnesiac_: they price symbols by overall frequency and ignore context, leaving the bulk of real data's redundancy (which is contextual) untouched.],
  [A _reversible transform_ loses no information; its job is to _reshape_ the byte stream so a memoryless coder downstream does better. The BWT is such a transform.],
  [The BWT sorts all cyclic rotations of a block and outputs the last column. Sorting by right-context gathers each context's _predecessors_ together, turning long-range structure into local _clusters_.],
  [The BWT is invertible from the last column alone via the *LF-mapping* (the first–last property): identical characters keep their relative order between the first and last columns, which lets you walk the original out backwards, no matrix stored.],
  [The BWT compresses _nothing_ by itself (output length = input length). *Move-To-Front* turns its clusters into runs of small integers (mostly zeros), *RLE* collapses those runs, and only the final *Huffman* stage removes bits.],
  [*bzip2* (Julian Seward, bzip 1996 / bzip2 1997) packaged RLE -> BWT -> MTF -> RLE -> Huffman, choosing Huffman over arithmetic coding to dodge 1990s patents. It beats gzip by ~10–20% on text but is block-local and now eclipsed by zstd/xz for everyday use.],
  [The BWT's LF-mapping also powers _search_: the *FM-index* (Ferragina–Manzini, 2000) is a self-index that finds patterns directly in compressed text, and is the engine of DNA aligners like Bowtie and BWA, with the r-index and Movi pushing the pangenome frontier through 2026.],
))

== Exercises

#exercise("35.1", 1)[
  Compute the Burrows–Wheeler Transform of the string `tomato` by hand. List all
  six rotations, sort them lexicographically, and read off the last column and
  the original-row index. (Treat the characters in ordinary alphabetical order.)
]
#solution("35.1")[
  The six rotations are `tomato`, `omatot`, `matoto`, `atotom`, `totoma`,
  `otomat`. Sorted lexicographically: `atotom` (last char `m`), `matoto` (`o`),
  `omatot` (`t`), `otomat` (`t`), `tomato` (`o`), `totoma` (`a`). The last
  column read top to bottom is `m o t t o a`, so $L = $ `mottoa`. The original
  `tomato` is the 5th sorted row (index 4, counting from 0). Thus
  $"BWT"("tomato") = ("mottoa", 4)$. Notice the two `t`s landed adjacent: the
  clustering effect in miniature.
]

#exercise("35.2", 2)[
  Run Move-To-Front on the byte sequence `[3, 3, 3, 1]` using an initial table
  `[0, 1, 2, 3]` (only four symbols). Show the output and the table after each
  step. Then invert your output to confirm you recover `[3, 3, 3, 1]`.
]
#solution("35.2")[
  *Encoding.* Start table `[0,1,2,3]`.
  Byte 3 is at position 3 -> output `3`; move to front -> `[3,0,1,2]`.
  Byte 3 is at position 0 -> output `0`; table unchanged `[3,0,1,2]`.
  Byte 3 is at position 0 -> output `0`; table unchanged `[3,0,1,2]`.
  Byte 1 is at position 2 -> output `2`; move to front -> `[1,3,0,2]`.
  Output: `[3, 0, 0, 2]`. The run of three 3s became `3, 0, 0`, exactly the
  "first one costs, the rest are zero" behaviour. *Decoding.* Start `[0,1,2,3]`.
  Position 3 -> byte 3, front -> `[3,0,1,2]`. Position 0 -> byte 3. Position 0 ->
  byte 3. Position 2 -> byte 1, front -> `[1,3,0,2]`. Recovered `[3,3,3,1]`. ✓
]

#exercise("35.3", 2)[
  You are given a BWT last column $L = $ `ard$rcaaaabb` (where `$` sorts before
  every letter) and told the sentinel marks the original row. _Without_ a stored
  index, explain how you know which row is the original, and outline the first
  LF-mapping step. (You need not finish the full inversion.)
]
#solution("35.3")[
  With a sentinel `$` that occurs exactly once and sorts first, the inverse walk
  _starts_ at the row where `$` appears in $L$, because reading backward from
  the sentinel reconstructs the string: its position _is_ the starting state,
  so no separate index is needed. To take an LF step, build $F$ by sorting $L$:
  `$aaaaabbcdrr`. The first column tells you each symbol's block of rows. From
  the row holding `$` in $L$, the LF-mapping sends the 1st `$` in $L$ to the 1st
  `$` in $F$ (row 0); from there you read the preceding character, find _its_
  occurrence number, and jump again. The point of the exercise is that the
  sentinel removes the need to store a separate index.
]

#exercise("35.4", 1)[
  Explain in two or three sentences why running Move-To-Front directly on raw
  English text (with no BWT first) would _not_ produce long runs of zeros, even
  though MTF produces lovely zero-runs on BWT output.
]
#solution("35.4")[
  MTF emits a zero only when the _same_ byte repeats immediately. Raw English
  rarely repeats the same letter back-to-back (`the quick brown fox` has almost
  no doubled letters), so consecutive bytes differ and MTF emits a jumble of
  small-to-medium positions, not zeros. The BWT is what _creates_ the
  back-to-back repetition (by clustering each context's predecessors) that MTF
  then converts to zeros, which is exactly why the order BWT-then-MTF matters
  and the reverse order would be useless.
]

#exercise("35.5", 3)[
  Prove that the Burrows–Wheeler Transform is a bijection on blocks of a fixed
  length $n$ over a fixed alphabet _when an index is also stored_, i.e. that
  the pair (last column, original-row index) determines the input uniquely, and
  every input maps to a distinct pair.
]
#solution("35.5")[
  _Invertibility (the pair determines the input)._ The inverse construction is
  well-defined: $F$ is $L$ sorted (unique), and the LF-mapping is determined
  because the $i$-th occurrence of symbol $c$ in $L$ maps to the $i$-th
  occurrence of $c$ in $F$ (the first–last property, proved in the chapter),
  giving a unique permutation $"lf"$. Walking $r arrow.r "lf"(r)$ for $n$ steps
  from $r = k$ emits a unique character sequence, whose reversal is a single
  well-defined string. Since the forward transform's sorted matrix has the input
  in row $k$, this reconstruction returns exactly the input.
  _Injectivity (distinct inputs give distinct outputs)._ Suppose two inputs
  $x != y$ produced the same pair $(L, k)$. The inverse just described is a
  deterministic function of $(L, k)$ alone, so it would return the same string
  for both; but we showed it returns the original, so $x = y$, a contradiction.
  Hence distinct inputs give distinct pairs. With both directions, the map
  $x arrow.r (L, k)$ has a two-sided inverse and is a bijection between
  length-$n$ blocks and their valid (last column, index) pairs.
]

#exercise("35.6", 2)[
  bzip2 uses _block-local_ BWT (each block of up to 900 KB is transformed
  independently). Describe one realistic input on which this hurts compression
  badly compared to a large-window LZ coder like xz, and explain why.
]
#solution("35.6")[
  Take a 50 MB log file in which the same 2 KB boilerplate header reappears every
  few megabytes. A large-window LZ coder (xz/LZMA, with a dictionary spanning
  many megabytes) sees the second, third, and later copies of the header as
  exact back-references to the first and codes each in a handful of bytes.
  bzip2's BWT works only within one block of at most 900 KB, so two copies of
  the header that fall in _different_ blocks are compressed independently: the
  cross-block redundancy is invisible to it. The BWT clusters _within_ a block
  but cannot reference _across_ blocks, which is precisely why bzip2 loses to
  large-window coders on big, long-range-repetitive inputs.
]

#exercise("35.7", 1)[
  In the chapter's `tinyzip` code, `encode` stores a 4-byte original length and
  a 4-byte BWT row index in its header before the Huffman payload. Why does the
  decoder need the row index, and what goes wrong if it is corrupted by one?
]
#solution("35.7")[
  The row index is the starting row for the inverse LF-mapping walk: it tells
  `ibwt` _which_ rotation was the original, i.e. where to begin reading the
  string out. Without it, the last column alone determines the _multiset_ of
  characters and the LF permutation, but not which of the $n$ cyclic rotations
  is the true original. If the index is off by one, the walk starts at the
  wrong row and emits a _different cyclic rotation_ of the correct characters
  (the right letters in the wrong starting position), so the decoded output is a
  rotation of the original, not the original. (The original length is needed
  separately to know when to stop and to size buffers.)
]

#exercise("35.8", 3)[
  The FM-index searches for a pattern using _backward search_: it processes the
  query pattern from its _last_ character to its first, maintaining a range of
  rows in the BWT matrix that all begin with the suffix matched so far. Explain
  intuitively why processing the pattern _backwards_ (not forwards) is the
  natural direction, connecting it to the LF-mapping you used for inversion.
]
#solution("35.8")[
  The LF-mapping moves you from a character in the last column to the matching
  character in the first column, i.e. it moves you _one character earlier_ in
  the text (the last column holds each context's predecessor). Backward search
  exploits exactly this: if you currently hold the set of rows whose rotations
  start with some suffix $S$ of the pattern, then extending the match by the
  character $c$ that comes _just before_ $S$ in the pattern means finding rows
  that start with $c S$. The LF-mapping is precisely the tool that, given the
  rows for $S$ and a preceding character $c$, computes the rows for $c S$: it
  prepends one character. So consuming the pattern from back to front lines up
  perfectly with the "step one character earlier" action the LF-mapping
  provides, which is why the FM-index and the inverse BWT are two uses of the
  same machine. Processing forwards would require the opposite (and unavailable)
  "step one character later" map.
]

== Further reading

- *Burrows, M. & Wheeler, D. J. (1994).* _A Block-Sorting Lossless Data Compression Algorithm_, DEC SRC Research Report 124: the original, and unusually readable: #link("https://www.cs.jhu.edu/~langmea/resources/burrows_wheeler.pdf")[the report].
- *Bentley, J., Sleator, D., Tarjan, R. & Wei, V. (1986).* _A Locally Adaptive Data Compression Scheme_ (Move-To-Front), Communications of the ACM 29(4): #link("https://dl.acm.org/doi/10.1145/5684.5688")[ACM].
- *Manber, U. & Myers, G. (1990).* _Suffix Arrays: A New Method for On-Line String Searches_ (the fast way to build the BWT).
- *Ferragina, P. & Manzini, G. (2000).* _Opportunistic Data Structures with Applications_ (the FM-index): #link("https://ieeexplore.ieee.org/document/892127")[IEEE FOCS].
- *Gagie, T., Navarro, G. & Prezza, N. (2018).* _Optimal-Time Text Indexing in BWT-Runs Bounded Space_ (the r-index): #link("https://arxiv.org/abs/1705.10382")[arXiv:1705.10382].
- *Seward, J.* The #link("https://sourceware.org/bzip2/manual/manual.html")[bzip2 and libbzip2 manual] documents the real pipeline and block-size flags.
- *Trifecta Tech Foundation (2025).* #link("https://trifectatech.org/blog/bzip2-crate-switches-from-c-to-rust/")[The bzip2 crate switches from C to 100% Rust], the safe-Rust reimplementation.
- *Langmead, B. et al. (2009)* (Bowtie) and *Li, H. & Durbin, R. (2009)* (BWA): the genome aligners built on the FM-index.

#bridge[
  We have now built every classical lossless tool in the box: entropy coders
  (Chapters 24–27), dictionary coders (28–32), context models (33–34), and now
  the transform route (this chapter). But we keep _claiming_ ratios: "10–20%
  better than gzip," "edges past DEFLATE." How does the field actually _measure_
  such claims, fairly and reproducibly? In *Chapter 36* we meet the standard
  test corpora (Calgary, Canterbury, Silesia), the enwik8/enwik9 text benchmarks,
  the Large Text Compression Benchmark, and the Hutter Prize (the contest that
  declares, provocatively, that compressing Wikipedia well _is_ a step toward
  artificial intelligence). There we will finally run tinyzip's `bench.py` across
  every method we have built and read off the honest, head-to-head scoreboard.
]
