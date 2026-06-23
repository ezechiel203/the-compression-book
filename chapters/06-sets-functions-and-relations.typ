#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Sets, Functions, and Relations

#epigraph[A set is a Many that allows itself to be thought of as a One.][Georg Cantor, the founder of set theory, c. 1883]

Here is a riddle that sounds like a children's joke but hides the deepest idea in this chapter. Suppose I hand you a code: a little rulebook that turns letters into strings of bits, so that you can store a message in a computer and later read it back. You send me `A`, I write down `01`; you send me `B`, I write down `0110`; you send me `C`, I write down `10`. Now I receive the bits `0110`. What did you send me — a single `B`, or an `A` followed by a `C`? I have no way to tell. The bits `0110` could be `B`, or they could be `01` then `10`, which is `A` then `C`. The message is _ambiguous_. My beautiful code is broken, and no amount of cleverness will un-break it, because the flaw is not in my decoder — it is in the _shape of the mapping itself_.

That riddle is the reason this chapter exists. Every compressor in this book is, at its heart, a machine that maps one collection of things onto another: messages onto bit-strings, symbols onto codewords, pixels onto numbers, numbers back onto pixels. Whether such a machine works — whether you can always undo it, whether two different messages can ever collide into the same output, whether the output covers everything it needs to — is not a question of programming. It is a question about the _structure_ of the mapping, and there is a precise, beautiful, two-thousand-year-old language for asking and answering it. That language is the language of *sets*, *functions*, and *relations*. By the end of this chapter you will be able to look at any code and say, with a proof in hand, "this one is decodable" or "this one is doomed". You will have met the single most important word in the theory of lossless compression — *bijection* — and you will understand why a compressor that loses nothing is exactly a bijection wearing work clothes.

#recap[
  In Chapter 3 we learned that all data is built from *symbols* drawn from an *alphabet*, and that a *message* is a string of those symbols. In Chapter 4 we wrote numbers in the two-symbol alphabet $\{0, 1\}$ and named each symbol a *bit*. In Chapter 5 we built Boolean algebra and saw that a bit can not only store a value but compute one. Underneath all of that, we kept quietly using ideas we never named: an "alphabet" is a _set_; encoding a symbol is applying a _function_; "this codeword belongs to that symbol" is a _relation_. This chapter names those ideas, builds them from nothing, and turns them into tools sharp enough to prove a compressor correct.
]

#objectives((
  [Write down a set, test membership, and combine sets with union, intersection, difference, and complement — and read every symbol ($in$, $subset.eq$, $union$, $inter$, $emptyset$) fluently.],
  [Form ordered pairs and the Cartesian product, and use them to build relations.],
  [Define a function precisely as a special kind of relation, and tell a genuine function from an impostor.],
  [Decide whether a function is *injective* (one-to-one), *surjective* (onto), or *bijective* (both) — and explain in plain words what each property means for a code.],
  [Prove that a function has an *inverse* exactly when it is a bijection, and connect that single fact to the meaning of "lossless".],
  [Use the *pigeonhole principle* to prove that no compressor can shrink every possible input — your first impossibility result.],
  [Count the size of a power set and a product, and reason about why some infinities are bigger than others.],
))

== Sets: the bag that holds everything

Start with the most innocent idea in mathematics, so innocent that it feels like cheating to call it mathematics at all. A *set* is a collection of distinct things, considered as a single object. The things inside are the set's *elements* (or *members*). That is the whole definition. A set can hold numbers, letters, words, colours, other sets, anything — and we draw the boundary of the collection with curly braces.

$ S = {2, 3, 5, 7} $

This says: $S$ is the set whose elements are the numbers $2$, $3$, $5$, and $7$. To ask whether something is in a set, we use the symbol $in$, which you read as "is an element of" or simply "is in":

$ 3 in S quad ("true: " 3 "is one of the four listed") $
$ 4 in.not S quad ("false: " 4 "is not listed; the slash means \"not in\"") $

Two rules give sets their peculiar, useful character, and both follow from the words "collection of _distinct_ things considered as a single object".

#keyidea[
  *A set has no order and no duplicates.* The set ${2, 3, 5}$ is the very same set as ${5, 2, 3}$ — rearranging the list changes nothing, because a set is defined purely by _which_ things are in it, not by how they are arranged or how many times you wrote them. And ${2, 2, 3}$ is just ${2, 3}$: writing an element twice does not put it in twice. A set is a question with only yes/no answers — "is this thing in?" — never "where?" or "how many times?".
]

This is exactly the right tool for an alphabet. When we said in Chapter 3 that the English alphabet is $\{a, b, c, ..., z\}$, we meant a _set_: the letters have no inherent order for the purpose of "which symbols may appear" (the alphabetical order is extra structure we add later, a _relation_, as we will see), and no letter appears twice. The set of bytes is $\{0, 1, 2, ..., 255\}$. The set of bits is $\{0, 1\}$. Every alphabet in this book is a set.

=== Describing a set: by list or by rule

We have two ways to pin down a set. The first, *roster notation*, simply lists the elements: $\{2, 3, 5, 7\}$. This is perfect when the set is small. But how would you list the set of all even numbers? You cannot — it never ends. So we use the second way, *set-builder notation*, which describes the elements by a _rule_ they must satisfy:

$ E = { n : n "is a whole number and " n "is even" } $

Read the colon as "such that". The whole thing reads: "$E$ is the set of all $n$ such that $n$ is a whole number and $n$ is even." The part before the colon names a typical element; the part after states the membership test. Some books use a vertical bar instead of a colon, writing $\{n | n "is even"\}$; the two mean exactly the same thing. Set-builder notation is how we will describe enormous or infinite sets precisely — "the set of all messages of length $8$", "the set of all valid codewords" — without ever writing them out.

#gomaths("Reading set notation out loud")[
  Mathematical symbols are frightening only until you hear them as ordinary words. Here is the whole vocabulary of this chapter, with the English you should say in your head:

  #table(columns: (auto, 1fr), inset: 6pt, align: (center + horizon, left + horizon),
    fill: (_, row) => if row == 0 { c-math.lighten(80%) },
    table.header([*Symbol*], [*Read it as*]),
    [$x in A$], [“$x$ is in $A$”, “$x$ is an element of $A$”],
    [$x in.not A$], [“$x$ is not in $A$”],
    [${...}$], [“the set containing …”],
    [$:$ or $|$], [“such that”],
    [$emptyset$], [“the empty set” (a set with nothing in it)],
    [$A subset.eq B$], [“$A$ is a subset of $B$” (every element of $A$ is also in $B$)],
    [$A union B$], [“$A$ union $B$” (everything in either one)],
    [$A inter B$], [“$A$ intersect $B$” (everything in both)],
    [$abs(A)$], [“the size of $A$” (how many elements it has)],
  )

  None of these is a calculation you have to _perform_; each is a fact you _read_. When a line of mathematics looks like a wall, slow down and translate it symbol by symbol into the middle column. The wall becomes a sentence.
]

=== The empty set, subsets, and the universe

One special set holds _nothing_: the *empty set*, written $emptyset$ or $\{\}$. It feels like a technicality, but it is as indispensable as zero. "The set of three-letter English words that contain no vowels" is the empty set; "the messages a broken decoder can read correctly" might be the empty set; and as we will see, $emptyset$ is the natural answer to "what do these two sets have in common?" when they share nothing.

We say $A$ is a *subset* of $B$, written $A subset.eq B$, when _every_ element of $A$ is also an element of $B$. The set of vowels $\{a, e, i, o, u\}$ is a subset of the whole alphabet. Every set is a subset of itself (vacuously, every element of $A$ is in $A$), and the empty set is a subset of _every_ set (there are no elements of $emptyset$ that could fail the test, so the test passes by default — a pattern logicians call *vacuously true*). When $A subset.eq B$ but $A$ is not all of $B$, we say $A$ is a *proper subset* and may write $A subset B$.

Often every set in a discussion lives inside one big fixed set called the *universe*, written $U$ — for us it might be "all bytes", or "all messages of length $8$". Inside a universe, the *complement* of $A$, written $overline(A)$ or $A^c$, is everything in the universe that is _not_ in $A$:

$ overline(A) = { x in U : x in.not A } $

If our universe is the digits $\{0, 1, ..., 9\}$ and $A = \{0, 2, 4, 6, 8\}$ is the even digits, then $overline(A) = \{1, 3, 5, 7, 9\}$, the odd digits. Notice that this is the very same "flip" — the NOT — you met in Chapter 5, now operating on _membership_ instead of on a single bit. "Is $x$ in $A$?" is a true/false question, and the complement answers the negation of it. The two spines of the book have just touched: Boolean logic and set theory are the same algebra, one acting on truth values and the other on membership.

== Combining sets: union, intersection, difference

Three operations let us build new sets from old ones, and all three are just the logical words *or*, *and*, *and-not* from Chapter 5 applied to membership.

The *union* $A union B$ collects everything that is in $A$ _or_ in $B$ (or both):
$ A union B = { x : x in A "or" x in B }. $

The *intersection* $A inter B$ collects everything that is in $A$ _and_ in $B$:
$ A inter B = { x : x in A "and" x in B }. $

The *difference* $A minus B$ (also written $A backslash B$) collects everything that is in $A$ but _not_ in $B$:
$ A minus B = { x : x in A "and" x in.not B }. $

Let us make these concrete with two small sets. Let $A = \{1, 2, 3, 4\}$ and $B = \{3, 4, 5, 6\}$.

#table(columns: (auto, auto, 1fr), inset: 7pt, align: (left + horizon, center + horizon, left + horizon),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([*Operation*], [*Result*], [*Why*]),
  [$A union B$], [$\{1,2,3,4,5,6\}$], [everything in either set; $3$ and $4$ are not written twice],
  [$A inter B$], [$\{3, 4\}$], [only the elements that appear in _both_],
  [$A minus B$], [$\{1, 2\}$], [in $A$, and not in $B$],
  [$B minus A$], [$\{5, 6\}$], [in $B$, and not in $A$ — note $A minus B != B minus A$],
)

A picture makes the relationships leap out. The standard one is a *Venn diagram*: each set is a circle, and the region where circles overlap is the intersection.

#fig([A Venn diagram of $A = \{1,2,3,4\}$ and $B = \{3,4,5,6\}$. The overlap is the intersection $\{3,4\}$; the left crescent is $A minus B = \{1,2\}$; the right crescent is $B minus A = \{5,6\}$; the whole shaded area is the union.],
cetz.canvas({
  import cetz.draw: *
  circle((0,0), radius: 1.6, stroke: c-accent + 1pt)
  circle((1.8,0), radius: 1.6, stroke: c-accent2 + 1pt)
  content((-0.9, 1.4))[*A*]
  content((2.7, 1.4))[*B*]
  content((-0.55, 0))[$1, 2$]
  content((0.9, 0))[$3, 4$]
  content((2.35, 0))[$5, 6$]
  content((0.9, -2.1))[#text(size: 9pt)[overlap $= A inter B$]]
}))

#checkpoint[With $A = \{1,2,3,4\}$ and $B = \{3,4,5,6\}$ as above, what is $(A union B) minus (A inter B)$, and what everyday idea does that operation capture?][It is $\{1, 2, 5, 6\}$ — the elements in exactly one of the two sets, never both. This is the *symmetric difference*, and it is set theory's version of the XOR operation from Chapter 5: "in $A$ or in $B$, but not in both".]

These operations obey laws that should feel familiar, because they are the De Morgan's laws from Chapter 5 in a new costume. For example, $overline(A union B) = overline(A) inter overline(B)$: the things that are _not_ (in $A$ or $B$) are exactly the things that are (not in $A$) _and_ (not in $B$). If you replace "set" with "statement", $union$ with OR, $inter$ with AND, and the bar with NOT, you get precisely the Boolean identity you already proved. We will not re-prove it; we earned it once already.

== Ordered pairs and the Cartesian product

A set forgets order, and that is usually a feature. But sometimes order is the whole point. The grid reference "column 3, row 7" is not the same as "column 7, row 3"; the pixel at $(x, y)$ is not the pixel at $(y, x)$; the code rule "symbol `A` maps to bits `01`" pairs a specific symbol with a specific output, and the direction matters. For this we need a gadget that _does_ remember order: the *ordered pair*, written with round brackets, $(a, b)$. The defining property is exactly the one a set lacks:

$ (a, b) = (c, d) quad "exactly when" quad a = c "and" b = d. $

So $(3, 7) != (7, 3)$, even though as _sets_ $\{3, 7\} = \{7, 3\}$. The first slot and the second slot are different jobs.

Now we can build, from two sets, the set of _all_ ordered pairs you can form by taking a first element from one and a second element from the other. This is the *Cartesian product*, named for René Descartes, whose coordinate grid is its most famous instance:

$ A times B = { (a, b) : a in A "and" b in B }. $

#definition("Cartesian product")[Given sets $A$ and $B$, their *Cartesian product* $A times B$ is the set of all ordered pairs $(a, b)$ whose first element comes from $A$ and whose second element comes from $B$.]

A tiny example shows the machinery. Let $A = \{a, b\}$ (two symbols) and $B = \{0, 1\}$ (two bits). Then

$ A times B = { (a,0), (a,1), (b,0), (b,1) }, $

four pairs in all. And four is no accident: there are $2$ choices for the first slot and $2$ for the second, and $2 times 2 = 4$. This is the *multiplication principle*, which is exactly why the operation is called a _product_:

#keyidea[
  The size of a Cartesian product is the product of the sizes: $abs(A times B) = abs(A) times abs(B)$. If $A$ has $m$ elements and $B$ has $n$ elements, then $A times B$ has $m n$ pairs — one for each way of choosing a first element _and_ a second element. (We will count far more elaborate things in Chapter 8, but every count in this book traces back to this one rule.)
]

The product of a set with itself, $A times A$, is written $A^2$. The set of all pixel coordinates on a $1920 times 1080$ screen is a product: $\{0, ..., 1919\} times \{0, ..., 1079\}$, which has $1920 times 1080 = 2{,}073{,}600$ pairs — the famous "two megapixels". And the set of all $8$-bit bytes is the eightfold product $\{0,1\}^8$, with $2^8 = 256$ elements, which is precisely why a byte has $256$ possible values. The Cartesian product is the formal reason that "more slots multiply, not add".

#gopython("Sets and tuples in Python")[
  Python has both ideas built in, and gives them the obvious names. A *set* is written with curly braces and behaves exactly like the mathematical object: unordered, no duplicates, fast membership tests.

  ```python
  A = {1, 2, 3, 4}
  B = {3, 4, 5, 6}
  print(3 in A)        # True  — membership test, the 'in' operator
  print(A | B)         # {1, 2, 3, 4, 5, 6}   union
  print(A & B)         # {3, 4}               intersection
  print(A - B)         # {1, 2}               difference
  print(A ^ B)         # {1, 2, 5, 6}         symmetric difference (XOR)
  print({2, 2, 3})     # {2, 3} — the duplicate 2 simply vanishes
  ```

  An *ordered pair* (and more generally an ordered list of fixed length) is a *tuple*, written with round brackets. Tuples remember order and may repeat:

  ```python
  p = (3, 7)
  q = (7, 3)
  print(p == q)        # False — order matters in a tuple
  print(p[0], p[1])    # 3 7   — index 0 is the first slot
  ```

  The Cartesian product is one line with the `product` helper from the `itertools` module:

  ```python
  from itertools import product
  A = {"a", "b"}
  B = {0, 1}
  print(set(product(A, B)))
  # {('a', 0), ('a', 1), ('b', 0), ('b', 1)}  — four pairs
  ```

  These are not toys: `tinyzip` will store an alphabet as a `set`, a histogram of symbol counts as a `dict` (next box), and a code rule as a mapping from symbols to bit-strings. The whole machine is sets and functions in Python clothing.
]

== Relations: the most general kind of connection

We now have the two ingredients we need to define the central objects of the chapter. A *relation* is the most general way to say that some things are connected to some other things. The trick is to notice that "$a$ is related to $b$" is just a statement about the _pair_ $(a, b)$ — it is either true or false. So a relation is captured completely by collecting all the pairs for which it is true.

#definition("Relation")[A *relation* from a set $A$ to a set $B$ is any subset $R subset.eq A times B$. We write $a R b$ (read "$a$ is related to $b$") to mean $(a, b) in R$.]

That is the entire definition, and its generality is the point. "Is less than" is a relation on numbers: it is the set of all pairs $(a, b)$ with $a < b$, so $(2, 5)$ is in it and $(5, 2)$ is not. "Is the parent of" is a relation on people. "Decodes to" is a relation from bit-strings to messages. Because a relation is just _a set of pairs_, it can connect one thing to many, or many to one, or anything to nothing. It imposes no discipline at all. And that total freedom is exactly why a raw relation is too wild to be a code. To get a code, we must tame it — and the tamed version is called a function.

Before we tame it, one family of relations deserves a name, because the very first useful one — the alphabetical order we set aside earlier — is a member of it. A relation _on a single set_ $A$ (that is, $R subset.eq A times A$) can have nice properties:

- *reflexive*: every element relates to itself, $a R a$ for all $a$ (e.g. "$<=$": every number is $<=$ itself).
- *symmetric*: if $a R b$ then $b R a$ (e.g. "is a sibling of"; but "$<$" is _not_ symmetric).
- *transitive*: if $a R b$ and $b R c$ then $a R c$ (e.g. "$<$": if $a<b$ and $b<c$ then $a<c$).

A relation that is reflexive, symmetric, _and_ transitive is an *equivalence relation*, and it carves a set into non-overlapping *equivalence classes* — clumps of mutually-related things. "Has the same remainder when divided by $2$" splits the whole numbers into two classes, the evens and the odds. This clumping idea will return when we group symbols by context in later chapters; for now, just notice that a single, simple definition — a set of pairs with three properties — captures the everyday notion of "sorting things into bins".

== Functions: a rule with no surprises

Most relations are too loose to be useful as a transformation. If "decodes to" related the bits `0110` to _both_ `B` and to `AC`, we would be stuck — which is precisely the broken code from the opening riddle. A *function* is a relation with one extra promise that rules out exactly that kind of surprise.

#definition("Function")[A *function* $f$ from a set $A$ to a set $B$, written $f: A -> B$, is a relation from $A$ to $B$ such that *every element of $A$ is paired with exactly one element of $B$*. The set $A$ is the *domain* (the legal inputs); $B$ is the *codomain* (the pool of possible outputs). For each input $a$, the single output is written $f(a)$.]

Two words in that definition do all the work: *every* and *exactly one*. "Every element of $A$" means the function must give an answer for _all_ legal inputs — no input is left undefined. "Exactly one element of $B$" means each input gets a _single_ answer — no input maps to two different outputs. A function is a vending machine you can trust: press button `A` and you always get the same item, every time, and every button gives _something_.

#fig([Left: a genuine function — every input on the left has exactly one arrow leaving it. Right: not a function — the input $2$ fires two arrows (an input with two outputs), which a function forbids.],
cetz.canvas({
  import cetz.draw: *
  // left: valid function
  content((0.5, 2.6))[#text(size: 9pt)[a function]]
  for (i, y) in ((0,2),(1,1),(2,0)) {
    circle((0, y), radius: 0.13, fill: c-accent, stroke: none)
    content((-0.4, y))[#str(i)]
  }
  for (i, y) in (("x",2),("y",1),("z",0)) {
    circle((2, y), radius: 0.13, fill: c-accent2, stroke: none)
    content((2.4, y))[#i]
  }
  line((0,2),(2,1), stroke: c-accent)
  line((0,1),(2,2), stroke: c-accent)
  line((0,0),(2,1), stroke: c-accent)
  // right: not a function
  content((5.5, 2.6))[#text(size: 9pt)[NOT a function]]
  for (i, y) in ((0,2),(1,1),(2,0)) {
    circle((5, y), radius: 0.13, fill: c-accent, stroke: none)
    content((4.6, y))[#str(i)]
  }
  for (i, y) in (("x",2),("y",1),("z",0)) {
    circle((7, y), radius: 0.13, fill: c-accent2, stroke: none)
    content((7.4, y))[#i]
  }
  line((5,2),(7,2), stroke: c-accent)
  line((5,1),(7,1), stroke: c-accent)
  line((5,0),(7,2), stroke: c-warn + 1.2pt)
  line((5,0),(7,0), stroke: c-warn + 1.2pt)
}))

Encoding a single symbol is a function: it takes a symbol from the alphabet (the domain) and returns a codeword (in the codomain). The requirement that a function gives _exactly one_ output per input is just the demand that our encoder be deterministic — that `A` always encodes to the same bits. The requirement that it gives an output for _every_ input is the demand that our encoder never chokes on a legal symbol. These are not pedantic rules; they are the minimum standard for a transformation to be usable at all.

One more piece of vocabulary, because it is the crux of everything that follows. The *image* (or *range*) of a function is the set of outputs it actually produces — which may be smaller than the whole codomain:

$ "image"(f) = { f(a) : a in A } subset.eq B. $

The codomain is where outputs are _allowed_ to land; the image is where they _actually_ land. A code might declare its codomain to be "all bit-strings", yet only ever emit a handful of them; that handful is the image. Keeping these two straight is the secret to the next section.

#gopython("Functions as dicts, and def")[
  Python gives you two ways to write a function, and both matter for `tinyzip`.

  The first is a `def`, a rule expressed as steps. The arrow-like `->` in the header is a *type hint* announcing the codomain — here, the function takes an `int` and returns an `int`:

  ```python
  def square(x: int) -> int:
      return x * x

  print(square(5))    # 25 — exactly one output for the input 5
  ```

  The second is a `dict` (dictionary), which stores a function as an explicit table of input-output pairs — perfect for a code, where the "rule" is just a lookup. The keys are the domain, the values are the outputs:

  ```python
  code: dict[str, str] = {"A": "0", "B": "10", "C": "11"}
  print(code["B"])         # "10" — look up the codeword for B
  print(list(code.keys())) # ['A', 'B', 'C']   — the domain
  print(list(code.values()))# ['0', '10', '11'] — the image
  ```

  A `dict` enforces the function rule for us automatically: each key appears once and maps to one value, so "every input has exactly one output" is guaranteed by the data structure itself. The type hint `dict[str, str]` (a Python 3.9+ syntax, standard in 3.14) reads "a dictionary whose keys are strings and whose values are strings" — it is the codomain and domain written down for the reader and for tools that check your code.
]

== The three properties that decide a code

We have reached the heart of the chapter. A function is a trustworthy one-way machine. But a _compressor_ needs more: it needs to be _undoable_. You compress a file, you store the small version, and later you must reconstruct the original _exactly_ — not something close, not something ambiguous, the very same bytes. Whether a function can be undone, and undone uniquely, comes down to three properties. Two of them are the make-or-break properties; the third is their union.

=== Injective: no collisions

A function is *injective* (or *one-to-one*) when different inputs always produce different outputs. Equivalently: no two distinct inputs ever collide onto the same output.

#definition("Injective (one-to-one)")[A function $f: A -> B$ is *injective* if, whenever $f(a_1) = f(a_2)$, it must be that $a_1 = a_2$. In words: distinct inputs give distinct outputs — there are no collisions.]

Why does a compressor care? Because if two _different_ files compressed to the _same_ output, then when you tried to decompress that output you could not possibly know which of the two originals to give back. The information needed to tell them apart was destroyed. Injectivity is precisely the promise "I never throw away the difference between two inputs". A function that fails to be injective is _lossy_ on those two inputs — and that is fine for a JPEG, which is allowed to lose detail, but fatal for a `.zip`, which is not.

Concretely, the function "double it", $f(n) = 2n$, is injective: if $2 a = 2 b$ then $a = b$, always. But "last digit", $g(n) = n mod 10$, is _not_: $g(13) = 3 = g(23)$, two different inputs colliding onto one output. Knowing only "$g$ gave me $3$" you cannot recover whether the input was $13$, $23$, $3$, or $1003$. The difference is gone.

#mathrecall[$n mod 10$ ("$n$ modulo $10$") means the _remainder_ when $n$ is divided by $10$ — the same remainder you collected when converting bases in Chapter 4. For example $23 mod 10 = 3$, because $23 = 2 times 10 + 3$. The remainder is always one of $0, 1, ..., 9$.]

=== Surjective: nothing wasted

A function is *surjective* (or *onto*) when every element of the codomain is hit by _at least one_ input — when the image fills the whole codomain, leaving no unused outputs.

#definition("Surjective (onto)")[A function $f: A -> B$ is *surjective* if for every $b in B$ there is at least one $a in A$ with $f(a) = b$. In words: every possible output is actually produced; the image equals the whole codomain.]

Surjectivity is about _coverage_. If we declare our codomain to be "all $3$-bit strings" but our code only ever emits five of the eight possible strings, the function is not surjective onto that codomain — three codewords sit unused. That is not a disaster (it is wasted space, a clue we could compress harder), but it tells us something real: a non-surjective code is leaving capacity on the table. The deepest theorems of compression, which we will meet in Volume I's information-theory chapters, are essentially statements about making a code as close to surjective as possible without breaking injectivity.

=== Bijective: the perfect, reversible match

When a function is _both_ injective and surjective, something wonderful happens: it pairs up the two sets perfectly. Every input goes to a distinct output (injective), and every output is reached (surjective), so the elements of $A$ and the elements of $B$ stand in flawless one-for-one correspondence — like a dance where everyone has exactly one partner and nobody sits out.

#definition("Bijective (one-to-one correspondence)")[A function $f: A -> B$ is *bijective* if it is both injective and surjective. A bijection sets up a perfect pairing: each element of $A$ matches exactly one element of $B$, and each element of $B$ matches exactly one element of $A$.]

#keyidea[
  *A lossless compressor is a bijection.* Compression maps each original file to a compressed file; decompression must recover the original _exactly_ and _uniquely_. That is only possible when the compression map is injective (no two files collide, so decompression is unambiguous) and its decompressor covers every compressed file it might receive. The reversible core of every `.zip`, `.gz`, `.png`, and `.flac` is, mathematically, a bijection between a set of inputs and a set of outputs. When someone tells you a program "compresses any file", the word _bijection_ is the hammer that breaks the claim — as we will prove in a moment.
]

#fig([The three properties as arrow pictures. Injective: distinct inputs, distinct outputs (an output may be missed). Surjective: every output is hit (two inputs may share one). Bijective: a perfect pairing — both at once.],
cetz.canvas({
  import cetz.draw: *
  let dots(x, ys, col) = {
    for y in ys { circle((x, y), radius: 0.11, fill: col, stroke: none) }
  }
  // injective
  content((0.5, 2.5))[#text(size: 9pt)[injective]]
  dots(0, (0,1,2), c-accent); dots(1.4, (-0.3,0.4,1.1,1.8,2.2), c-accent2)
  line((0,2),(1.4,2.2)); line((0,1),(1.4,1.1)); line((0,0),(1.4,0.4))
  // surjective
  content((4, 2.5))[#text(size: 9pt)[surjective]]
  dots(3.5, (-0.3,0.4,1.1,1.8,2.2), c-accent); dots(4.9, (0,1,2), c-accent2)
  line((3.5,2.2),(4.9,2)); line((3.5,1.8),(4.9,2)); line((3.5,1.1),(4.9,1)); line((3.5,0.4),(4.9,0)); line((3.5,-0.3),(4.9,0))
  // bijective
  content((7.5, 2.5))[#text(size: 9pt)[bijective]]
  dots(7, (0,1,2), c-accent); dots(8.4, (0,1,2), c-accent2)
  line((7,2),(8.4,2)); line((7,1),(8.4,1)); line((7,0),(8.4,0))
}))

#misconception[A program could compress every possible file by at least one bit.][This is impossible, and the reason is pure set theory — the *pigeonhole principle*, which we prove below. There are simply fewer short outputs than there are inputs, so some inputs must collide, and collisions destroy injectivity, and a compressor without injectivity cannot be losslessly reversed. Every "universal compressor" advertisement is selling a perpetual-motion machine.]

== The inverse, and why bijection is exactly reversibility

We keep saying a bijection is "reversible". Let us make that precise and _prove_ it, because the proof is the mathematical bedrock under the word "lossless".

To reverse a function $f: A -> B$ means to find a second function $f^(-1): B -> A$ (read "$f$ inverse") that perfectly undoes it: feed an output back in and get the original input out. Formally, $f^(-1)(f(a)) = a$ for every $a$, and $f(f^(-1)(b)) = b$ for every $b$. The big claim is that such an undoing function exists exactly when $f$ is a bijection — no more, no less.

#theorem("Inverse exists iff bijection")[A function $f: A -> B$ has a two-sided inverse $f^(-1): B -> A$ if and only if $f$ is bijective.]

#proof[
  We must argue both directions, because "if and only if" is two claims in one.

  *(If $f$ is a bijection, an inverse exists.)* Take any $b in B$. Because $f$ is surjective, there is _at least one_ $a in A$ with $f(a) = b$. Because $f$ is injective, there is _at most one_ such $a$ (two different ones would mean two inputs colliding onto $b$, which injectivity forbids). "At least one" and "at most one" together give _exactly one_. So the rule "send $b$ to that unique $a$" assigns exactly one output to every input $b$ — it is a genuine function, which we name $f^(-1)$. By construction $f^(-1)(f(a)) = a$ and $f(f^(-1)(b)) = b$, so it undoes $f$ from both sides.

  *(If an inverse exists, $f$ is a bijection.)* Suppose some $f^(-1)$ undoes $f$. First, $f$ is injective: if $f(a_1) = f(a_2)$, apply $f^(-1)$ to both sides to get $a_1 = f^(-1)(f(a_1)) = f^(-1)(f(a_2)) = a_2$, so the inputs were equal after all — no collisions. Second, $f$ is surjective: given any $b in B$, the element $a = f^(-1)(b)$ satisfies $f(a) = f(f^(-1)(b)) = b$, so $b$ is hit. Injective and surjective means bijective.
]

That two-line proof is, no exaggeration, the reason `.zip` files work. "Lossless" is an English word; *bijective* is its mathematical body; and the theorem says the two are the same thing. A decompressor _is_ the inverse function $f^(-1)$. It exists, and is unique and well-defined, precisely when the compressor $f$ is a bijection. If an engineer ever shows you a "lossless" scheme, you now know the exact question to ask: _is the encoding map injective, and does the decoder cover its whole input?_ If yes, it is a bijection and it works; if no, it is broken, and you can say so with a proof.

#aside[The words *injection*, *surjection*, and *bijection* are surprisingly modern. They were coined in the mid-twentieth century by the secretive French collective writing under the single pen name *Nicolas Bourbaki*, who rebuilt much of mathematics on the precise language of sets and maps. ("Bourbaki" was not a person — it was a rotating group of brilliant mathematicians who published as one.) The English word _injection_ as a mathematical noun is first recorded slightly earlier, with Saunders Mac Lane in 1950. Before this vocabulary settled, people said the clumsier "one-to-one" and "onto", which we still use as friendly synonyms.]

== Composition: chaining maps, chaining stages

Real compressors are pipelines: a transform stage feeds a modelling stage feeds an entropy-coding stage. Mathematically, feeding the output of one function into the next is *composition*. Given $f: A -> B$ and $g: B -> C$, their composition $g compose f$ (read "$g$ after $f$") is the function $A -> C$ defined by doing $f$ first and $g$ second:

$ (g compose f)(a) = g(f(a)). $

The order reads right-to-left, like nested parentheses: $f$ is closest to the input $a$, so $f$ happens first. A four-stage codec is just $g_4 compose g_3 compose g_2 compose g_1$. And here is the property that makes pipelines safe to build:

#theorem("Composition of bijections")[If $f: A -> B$ and $g: B -> C$ are both bijections, then $g compose f: A -> C$ is a bijection, and its inverse is $(g compose f)^(-1) = f^(-1) compose g^(-1)$ — undo the stages in reverse order.]

#proof[
  We show $g compose f$ is injective and surjective. *Injective:* if $(g compose f)(a_1) = (g compose f)(a_2)$, that is $g(f(a_1)) = g(f(a_2))$. Apply $g^(-1)$ (which exists since $g$ is a bijection) to get $f(a_1) = f(a_2)$; apply $f^(-1)$ to get $a_1 = a_2$. *Surjective:* take any $c in C$. Since $g$ is surjective, some $b$ has $g(b) = c$; since $f$ is surjective, some $a$ has $f(a) = b$; then $(g compose f)(a) = g(f(a)) = g(b) = c$. Both properties hold, so the composite is a bijection. The inverse formula is just "socks before shoes, so shoes off before socks": $(f^(-1) compose g^(-1))(g(f(a))) = f^(-1)(g^(-1)(g(f(a)))) = f^(-1)(f(a)) = a$.
]

This is the licence under which `tinyzip` will be assembled: as long as every reversible stage is individually a bijection, the whole pipeline is a bijection, and the decompressor is the stages run backwards. Lose that property at any one stage and the whole archive becomes unrecoverable. The "reverse order" detail — undo the _last_ stage first — is exactly why a decoder's code reads like the encoder's code turned upside down, a symmetry you will see again and again.

#tryit[
  This chapter has no `tinyzip` build step of its own — the project's Python skeleton does not begin until Chapter 15, once we have learned the language. But the ideas here are so central that it is worth seeing them in code _right now_, as a preview. Below are the two functions that ask the make-or-break questions of this chapter — _is this code safe to use?_ — written with the sets and dicts exactly as the theory prescribes. (When `tinyzip` reaches its real Huffman coder in Chapter 24, this is precisely the check it will run.)

  ```python
  def is_injective(code: dict[str, str]) -> bool:
      """A code (symbol -> codeword) is injective when no two
      symbols share a codeword: the number of distinct codewords
      equals the number of symbols."""
      codewords = list(code.values())
      return len(set(codewords)) == len(codewords)

  def image(code: dict[str, str]) -> set[str]:
      """The set of codewords the code can actually emit."""
      return set(code.values())
  ```

  The trick in `is_injective` is pure set theory: turning the list of codewords into a `set` deletes duplicates (a set has no duplicates, as we learned). If two symbols mapped to the same codeword, the set would be _shorter_ than the list, and the lengths would disagree. We test it on the broken code from the very first page of this chapter and on a fixed version:

  ```python
  broken = {"A": "01", "B": "0110", "C": "10"}   # the opening riddle
  good   = {"A": "0",  "B": "10",   "C": "11"}
  print(is_injective(broken))   # True  — symbol map has no dup codewords...
  print(is_injective(good))     # True
  ```

  But injectivity of the _symbol_ map is not enough! The opening riddle was broken not because two symbols shared a codeword, but because two _messages_ collided once we glued codewords together (`AC` and `B` both became `0110`). That deeper property — that every _sequence_ of codewords decodes one way — is called the *prefix property*, and it is the subject of Chapter 19's Kraft–McMillan inequality. We flag it here so the gap is visible; `tinyzip`'s real codes (Huffman, in Chapter 24) will be built to close it. For now we have the right vocabulary and a test for the first, necessary condition.
]

== The pigeonhole principle: your first impossibility proof

We promised to prove that no compressor shrinks everything. The tool is so simple it sounds like a nursery rhyme, yet it is one of the most powerful weapons in all of mathematics. It is called the *pigeonhole principle*.

#theorem("Pigeonhole principle")[If you place $n$ objects into $m$ boxes and $n > m$, then at least one box contains two or more objects.]

#proof[
  Suppose, for contradiction, that no box held two or more objects. Then every box holds at most one object, so the total number of objects is at most the number of boxes, $m$. But we placed $n$ objects, and $n > m$, so $n <= m$ — a contradiction. Hence some box must hold at least two objects.
]

The name is literal: if $10$ pigeons fly into $9$ pigeonholes, some hole holds two pigeons. It feels too obvious to be useful. Watch it demolish the dream of universal compression.

#theorem("No lossless compressor shrinks every input")[Let $f$ be any lossless (injective) compression scheme that maps files to files. Then $f$ cannot make _every_ possible input strictly shorter. In fact, among all files of length up to $n$ bits, at least one is mapped to an output no shorter than itself.]

#proof[
  Count the boxes and the pigeons. Consider all input files of exactly $n$ bits: there are $2^n$ of them (each of the $n$ positions is independently $0$ or $1$ — the Cartesian-product count from earlier). Suppose, for contradiction, that $f$ compresses every one of them to _strictly fewer_ than $n$ bits. The outputs are then files of length $0, 1, 2, ..., n-1$ bits. How many such shorter files are there in total? A file of length $k$ has $2^k$ possibilities, so the total is
  $ 2^0 + 2^1 + dots.c + 2^(n-1) = 2^n - 1, $
  one fewer than $2^n$. (That last sum is a geometric series; if the identity is unfamiliar, the box below proves it.) So we have $2^n$ pigeons (the inputs) trying to fit into $2^n - 1$ pigeonholes (the strictly-shorter outputs). By the pigeonhole principle, two different inputs must land on the same output. But $f$ is injective — two inputs can never share an output. Contradiction. Therefore $f$ cannot compress every $n$-bit file; at least one input comes out no shorter.
]

#gomaths("The geometric series $1 + 2 + 4 + dots.c + 2^(n-1) = 2^n - 1$")[
  Why does doubling and adding land one short of the next power? Here is the slick one-line argument. Call the sum $S$:
  $ S = 1 + 2 + 4 + dots.c + 2^(n-1). $
  Double both sides — every term moves up to the next power:
  $ 2 S = 2 + 4 + 8 + dots.c + 2^n. $
  Now subtract the first line from the second. Almost everything cancels in the middle: the $2, 4, ..., 2^(n-1)$ appear in both. What survives is the new top term $2^n$ from the doubled line and the lost bottom term $1$ from the original:
  $ 2S - S = 2^n - 1, quad "so" quad S = 2^n - 1. $
  Concretely, $1 + 2 + 4 = 7 = 2^3 - 1$, and $1 + 2 + 4 + 8 = 15 = 2^4 - 1$. There is also a binary-flavoured intuition you will love after Chapter 4: $2^n - 1$ written in binary is $n$ ones in a row ($1111$ is $15$), and a string of $n$ ones is exactly "all the place-values from $2^0$ up to $2^(n-1)$ added together". The sum _is_ its own answer.
]

#keyidea[
  *The counting bound is undefeatable.* No algorithm, no AI, no quantum trick can compress every input, because the obstruction is not about cleverness — it is about there being more inputs than short outputs, a fact of pure arithmetic. What real compressors do instead is shrink the inputs we _actually encounter_ (English text, photos, code) by making _other_, unlikely inputs (random noise) slightly _larger_. Compression is a bet that the world is not random, and the pigeonhole principle is the receipt proving the bet has a cost. We will return to this bound, dressed up as the source coding theorem, in Chapter 19.
]

#pitfall[Do not confuse "cannot shrink _every_ input" with "cannot shrink _any_ input". The theorem forbids only the universal claim. A good compressor shrinks the _vast majority_ of real-world files dramatically; it merely must, in exchange, leave at least one possible file no smaller. Since that one file is almost always meaningless noise nobody will ever store, the trade is overwhelmingly worth it. Impossibility of the universal does not dent the usefulness of the practical.]

== How big is a set? Finite, infinite, and counting

We have leaned on $abs(A)$, "the size of $A$", as if it were obvious. For finite sets it is: the set $\{2, 3, 5, 7\}$ has size $4$, just count them. But sets can be infinite, and Cantor's astonishing discovery — that some infinities are _bigger_ than others — is both beautiful and quietly relevant to compression, so we close with it.

The clean way to compare sizes without counting is the bijection itself. Two sets have the *same size* exactly when there is a bijection between them — a perfect pairing with nobody left over. For finite sets this just recovers ordinary counting. But it keeps working for infinite sets, where counting is impossible, and there it delivers shocks. The whole numbers $\{0, 1, 2, 3, ...\}$ and the _even_ whole numbers $\{0, 2, 4, 6, ...\}$ have the _same_ size, because $f(n) = 2n$ is a bijection between them — even though the evens are a proper subset! An infinite set can be the same size as a part of itself, a property the mathematician Richard Dedekind used to _define_ what "infinite" means.

A set that can be paired up with the counting numbers is called *countable*. The integers are countable; so, more surprisingly, are the fractions. But Cantor proved in 1873–74 that the set of all infinite bit-strings is _not_ countable — there are strictly more of them than there are counting numbers, a strictly bigger infinity. The proof (his famous *diagonal argument*) is the ancestor of the pigeonhole reasoning we just used, and the reason it matters to us is this: there are uncountably many possible infinite data streams but only countably many programs to generate them, so _almost every_ infinite stream is incompressible. That sentence will become the foundation of Kolmogorov complexity in Chapter 22; we plant the seed here.

#gomaths("Power sets and $2^n$")[
  Given a set $A$, its *power set* $cal(P)(A)$ is the set of _all subsets_ of $A$ — including the empty set and $A$ itself. For $A = \{x, y\}$:
  $ cal(P)(A) = { emptyset, {x}, {y}, {x, y} }, $
  four subsets. The pattern is exact and important: a set with $n$ elements has exactly $2^n$ subsets, so $abs(cal(P)(A)) = 2^(abs(A))$. The reason is a Cartesian-product count in disguise: to build a subset, you make $n$ independent yes/no decisions ("is element $1$ in? is element $2$ in? …"), and $n$ binary choices give $2^n$ outcomes — the same $\{0,1\}^n$ that gave a byte its $256$ values. Each subset corresponds to one $n$-bit "membership string": a $1$ in position $i$ means "element $i$ is in". This is why the power set of an alphabet, the set of all possible "which symbols are present" answers, has $2^("alphabet size")$ members, and it is the combinatorial engine we will rev up properly in Chapter 8.
]

#history[Set theory itself was born of one stubborn man's obsession. Georg Cantor (1845–1918), working largely alone in the 1870s and 1880s, insisted that infinity could be measured and that there was a whole hierarchy of ever-larger infinities. His contemporaries were appalled — the towering Leopold Kronecker called Cantor a "corrupter of youth" and blocked his career — and Cantor suffered for it. Yet within a generation his "naive" set theory had become the common language of _all_ mathematics, the soil in which functions, relations, probability (Chapter 9), and information theory itself would grow. David Hilbert, the leading mathematician of the age, declared: "No one shall expel us from the paradise that Cantor has created."]

#scoreboard(caption: "vocabulary unlocked — no bytes melted yet, but the tools are now in hand",
  [Concept], [Symbol], [—], [What it buys us],
  [Set / membership], [$in$, ${...}$], [—], [a precise alphabet],
  [Cartesian product], [$A times B$], [—], [why slots multiply ($256 = 2^8$)],
  [Function], [$f: A -> B$], [—], [a deterministic encoder],
  [Injective], [one-to-one], [—], [no collisions = no information lost],
  [Bijective], [$f^(-1)$ exists], [—], [*lossless* = reversible, proved],
  [Pigeonhole], [$n > m$], [—], [no universal compressor exists],
)

#takeaways((
  [A *set* is an unordered, duplicate-free collection; membership ($in$) is its only question. Alphabets, codewords, and messages are all sets.],
  [The *Cartesian product* $A times B$ is the set of ordered pairs; its size multiplies, $abs(A times B) = abs(A) times abs(B)$ — the reason an $8$-bit byte has $2^8 = 256$ values.],
  [A *function* is a relation that gives every input *exactly one* output: a deterministic, total rule — the mathematical shape of an encoder.],
  [*Injective* = no two inputs collide (lossless on those inputs); *surjective* = every output is used (no wasted capacity); *bijective* = both = a perfect, reversible pairing.],
  [A function has an *inverse* if and only if it is a *bijection*. This is the exact mathematical meaning of "lossless": a decompressor _is_ the inverse function.],
  [Composing bijections gives a bijection, undone in reverse order — the licence to build multi-stage codecs whose decoder is the encoder run backwards.],
  [The *pigeonhole principle* proves no lossless compressor can shrink every input: there are more inputs than short outputs, so some must collide, and collisions are forbidden. Compression is a bet that the world is not random.],
))

== Exercises

#exercise("6.1", 1)[
  Let $A = \{1, 2, 3, 4, 5\}$ and $B = \{2, 4, 6\}$. Write out, by listing every element: (a) $A union B$, (b) $A inter B$, (c) $A minus B$, (d) $B minus A$, and (e) the symmetric difference, the elements in exactly one of the two sets.
]
#solution("6.1")[
  (a) $A union B = \{1, 2, 3, 4, 5, 6\}$. (b) $A inter B = \{2, 4\}$. (c) $A minus B = \{1, 3, 5\}$. (d) $B minus A = \{6\}$. (e) Symmetric difference $= (A minus B) union (B minus A) = \{1, 3, 5, 6\}$.
]

#exercise("6.2", 1)[
  How many ordered pairs are in $\{a, b, c\} times \{0, 1\}$? List them, then state the general rule for $abs(A times B)$ and use it to say how many pairs are in $\{0,1,...,9\} times \{0,1,...,9\}$ (the set of two-digit "coordinates").
]
#solution("6.2")[
  There are $3 times 2 = 6$ pairs: $(a,0), (a,1), (b,0), (b,1), (c,0), (c,1)$. The rule is $abs(A times B) = abs(A) times abs(B)$. For $\{0,...,9\} times \{0,...,9\}$ that is $10 times 10 = 100$ pairs — exactly the hundred values $00$ through $99$.
]

#exercise("6.3", 2)[
  For each function from the whole numbers to the whole numbers, say whether it is injective, surjective, both (bijective), or neither, and justify in one sentence: (a) $f(n) = n + 3$; (b) $g(n) = n^2$; (c) $h(n) = floor(n \/ 2)$ (the brackets $floor(dot.c)$ mean "round down to the nearest whole number" — i.e. integer division, e.g. $h(7) = 3$).
]
#solution("6.3")[
  (a) $f(n) = n+3$ is *injective* (different $n$ give different $n+3$) but, over the whole numbers $\{0,1,2,...\}$, _not_ surjective ($0$, $1$, $2$ are never outputs), so not bijective. (b) $g(n) = n^2$ is *injective* on the non-negative whole numbers but not surjective ($2, 3, 5, ...$ are never hit), so not bijective. (c) $h(n) = floor(n\/2)$ is *surjective* (every $m$ is hit, e.g. by $n = 2m$) but not injective ($h(6) = h(7) = 3$), so not bijective.
]

#exercise("6.4", 2)[
  A code maps four symbols to bit-strings: $w("A") = 0$, $w("B") = 1$, $w("C") = 00$, $w("D") = 01$. Is the symbol-to-codeword map injective? Now decode the received stream $0001$ — find _two_ different symbol sequences that produce it, and explain which property from this chapter the code violates as a _message_ code.
]
#solution("6.4")[
  The symbol map _is_ injective: the four codewords $0, 1, 00, 01$ are all distinct. But as a message code it is broken. The stream $0001$ can be read as $C, D$ (which is $00$ then $01$) or as $A, A, A, B$ (which is $0, 0, 0, 1$). So the map from _sequences of symbols_ to _bit-strings_ is not injective — two messages collide on $0001$. The flaw is that codewords are prefixes of others (`A`=`0` is a prefix of `C`=`00`); fixing it requires the *prefix property* of Chapter 19. Injectivity of the symbol map alone does not guarantee a decodable code.
]

#exercise("6.5", 2)[
  Prove that the function $f(n) = 2n + 1$ from the whole numbers to the _odd_ whole numbers $\{1, 3, 5, 7, ...\}$ is a bijection, and write down its inverse $f^(-1)$.
]
#solution("6.5")[
  *Injective:* if $2 a + 1 = 2 b + 1$ then $2a = 2b$ so $a = b$. *Surjective:* any odd number $m$ can be written $m = 2k + 1$ for the whole number $k = (m-1)\/2$, and $f(k) = m$; so every odd number is hit. Both hold, so $f$ is a bijection. Its inverse undoes "double and add one" by "subtract one and halve": $f^(-1)(m) = (m - 1)\/2$. Check: $f^(-1)(f(n)) = ((2n+1) - 1)\/2 = n$. ✓
]

#exercise("6.6", 1)[
  Use the pigeonhole principle to prove: among any $13$ people, at least two were born in the same month. Identify clearly what the pigeons are and what the holes are.
]
#solution("6.6")[
  The pigeons are the $13$ people; the holes are the $12$ months. Each person is placed in the hole of their birth month. Since $13 > 12$ (more pigeons than holes), the pigeonhole principle guarantees that at least one month-hole contains two or more people — i.e. at least two people share a birth month.
]

#exercise("6.7", 2)[
  List the entire power set $cal(P)(A)$ of $A = \{r, g, b\}$ (think of it as "every possible subset of the three colour channels"). How many subsets are there, and how does that match the formula $2^(abs(A))$?
]
#solution("6.7")[
  $cal(P)(A) = \{ emptyset, \{r\}, \{g\}, \{b\}, \{r,g\}, \{r,b\}, \{g,b\}, \{r,g,b\} \}$ — eight subsets. Since $abs(A) = 3$, the formula gives $2^3 = 8$. ✓ Each subset corresponds to a $3$-bit "is-it-in" string: e.g. $\{r, b\}$ is $101$ (r yes, g no, b yes), and there are $2^3 = 8$ such strings.
]

#exercise("6.8", 3)[
  Adapt the pigeonhole proof from the chapter to show a sharper statement: no lossless compressor can map _all_ files of length $<= n$ bits to files of length $<= n - 1$ bits. (Hint: count the pigeons as all inputs of length $0$ through $n$, and the holes as all outputs of length $0$ through $n-1$.)
]
#solution("6.8")[
  Pigeons: every input file of length $0, 1, ..., n$ bits. Their count is $2^0 + 2^1 + dots.c + 2^n = 2^(n+1) - 1$ (geometric series). Holes: every output file of length $0, 1, ..., n-1$ bits, counting $2^0 + dots.c + 2^(n-1) = 2^n - 1$. Since $2^(n+1) - 1 > 2^n - 1$ (indeed nearly double), there are far more pigeons than holes, so by the pigeonhole principle two distinct inputs share an output. A lossless (injective) compressor forbids that collision — contradiction. Hence no lossless compressor can squeeze every file of length $<= n$ into length $<= n-1$.
]

#exercise("6.9", 2)[
  Decide whether each relation on the set of all people is an equivalence relation by testing reflexivity, symmetry, and transitivity: (a) "was born in the same year as"; (b) "is at least as tall as"; (c) "is a sibling of" (sharing at least one parent, and counting nobody as their own sibling).
]
#solution("6.9")[
  (a) "Born in the same year as" is *reflexive* (you share your own birth year), *symmetric*, and *transitive* — an *equivalence relation*; its classes are the birth-year cohorts. (b) "At least as tall as" is reflexive and transitive but _not_ symmetric (if I am taller than you, you are not taller than me), so *not* an equivalence relation (it is a different beast, a _partial order_). (c) "Sibling of" is *not* reflexive (you are not your own sibling, by the stated convention) and not transitive in edge cases (half-siblings), so *not* an equivalence relation.
]

#exercise("6.10", 3)[
  In Python, write a function `composes(f, g)` that takes two codes given as `dict[str, str]` and returns the composed code as a new dict, applying `f` first then `g` to each symbol — but only for symbols where the chained lookup is defined. Then explain, using the composition theorem, under what condition the composed code is guaranteed injective.
]
#solution("6.10")[
  ```python
  def composes(f: dict[str, str], g: dict[str, str]) -> dict[str, str]:
      result: dict[str, str] = {}
      for symbol, mid in f.items():      # f maps symbol -> mid
          if mid in g:                   # only if g can continue
              result[symbol] = g[mid]    # g maps mid -> final
      return result
  ```
  By the composition theorem, if both `f` and `g` are injective on the relevant domains, the composite is injective: a collision in `g(f(x))` would force a collision in `f` (since `g` is injective, equal outputs mean equal inputs to `g`, i.e. equal `f(x)`; then `f` injective forces equal `x`). So the composed code is guaranteed injective whenever each stage is individually injective — the exact licence that lets `tinyzip` chain reversible stages without re-checking the whole pipeline.
]

== Further reading

- *Naive Set Theory*, Paul R. Halmos (1960) — the friendliest serious introduction to sets, functions, and relations ever written; short, witty, and assumes nothing.
- *How to Prove It: A Structured Approach*, Daniel J. Velleman — teaches the exact proof style (injective/surjective/bijective, "if and only if") used in this chapter, from scratch.
- Georg Cantor's diagonal argument and the birth of set theory: #link("https://en.wikipedia.org/wiki/Cantor%27s_diagonal_argument")[the diagonal argument] and #link("https://en.wikipedia.org/wiki/Georg_Cantor")[Cantor's biography] give the human story behind the uncountable.
- On the pigeonhole principle and its history (Dirichlet's 1834 _Schubfachprinzip_, the term "pigeonhole" coined by R. M. Robinson in 1940): #link("https://en.wikipedia.org/wiki/Pigeonhole_principle")[the pigeonhole principle].
- Forward to the payoff: the counting-bound impossibility result we proved here returns, fully dressed, as Shannon's source coding theorem in Chapter 19, and as Kolmogorov complexity in Chapter 22.

#bridge[
  We can now speak the grammar of mathematics: sets, products, functions, and the all-important bijection that _is_ losslessness. But notice how often the number $2^n$ keeps appearing — $256$ byte values, $2^n$ subsets, $2^n$ files of length $n$. That explosive doubling, and its tamer inverse, are the next tool we need. In Chapter 7 we meet *exponents and logarithms*: we will learn why a "bit" is literally a logarithm, how multiplying turns into adding, and how to measure the size of a set not by counting its elements but by counting the _yes/no questions_ needed to single one out. That measure has a name you have been waiting for — _information_ — and it is the doorway to everything Shannon built.
]
