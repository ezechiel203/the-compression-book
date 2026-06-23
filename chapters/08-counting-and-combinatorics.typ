#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Counting and Combinatorics

#epigraph[
  "There are only so many tunes. The trick is the order you play them in."
][a jazz musician, quoted often, attributed never]

Here is a bet you should never take, no matter how good the odds sound. I hand you a magic box. Feed any file into it — a photo, a song, a novel, last year's tax return — and the box gives you back a *smaller* file, every single time, with nothing lost: you can always feed the small file back in reverse and recover the original exactly. Every file, smaller. Always. No exceptions.

It sounds like the dream of compression itself, and people have tried to sell exactly this box — to investors, to the patent office, to gullible magazines — for over fifty years. The box is a fraud. Not "probably a fraud," not "fraud unless they're very clever." It is *impossible*, the way a triangle with four corners is impossible, and the proof that it is impossible needs no physics, no engineering, no knowledge of any particular compression method. It needs only one idea: *counting*. If you can count chairs and count people, you can prove that the magic box cannot exist. By the end of this chapter you will be able to prove it yourself, on a napkin, to anyone who tries to sell you the box.

That is the secret life of counting. It looks like the most childish branch of mathematics — anyone can count — and yet it draws the hard outer wall around the entire field of compression. Every limit in this book, every "you cannot do better than this," is at bottom a counting argument. Shannon's famous entropy bound, which we meet in Chapter 18, is counting in a velvet glove. So before we can honestly talk about how *well* we can compress, we have to learn to count properly: not "one, two, three" counting, but the counting of *possibilities* — how many ways can things be arranged, chosen, ordered, lined up? That craft has a name, *combinatorics*, and it is the subject of this chapter.

#recap[
  We have been building the toolkit a compressor needs. In Chapter 4 we learned that $n$ bits can name exactly $2^n$ different things — the doubling rule — and met the *byte*, eight bits, $256$ values. In Chapter 5 we built logic and the idea of distinct cases. In Chapter 6 we made *sets* (collections of distinct things), *functions* (rules that turn each input into exactly one output), and the all-important *bijection* (a perfect one-to-one pairing, an input for every output and vice versa) — and we noted that a lossless compressor *must* be a bijection, because if two different files compressed to the same thing, you could never tell them apart on the way back. In Chapter 7 we mastered *exponents* and *logarithms*, the language of growth, and saw why "a bit is a logarithm." This chapter spends all of that. Counting *is* the doubling rule generalised; the no-magic-box theorem *is* the bijection idea made quantitative; and the numbers we count will turn out to be exactly the $2^n$ from Chapter 4, wearing new clothes.
]

#objectives((
  [Use the *multiplication principle* to count step-by-step choices, and the *addition principle* to count separate cases — the two atoms of all counting.],
  [Compute *factorials* and explain why $0! = 1$ is forced, not chosen.],
  [Count *permutations* (orderings) and *combinations* (selections), know exactly when order matters, and convert fluently between them.],
  [Read and use the *binomial coefficient* $binom(n, k)$, build Pascal's triangle, and connect it to the $2^n$ subsets of a set.],
  [State and prove the *pigeonhole principle*, the humblest theorem in mathematics, in both its plain and its sharpened forms.],
  [Prove the *counting bound*: no lossless compressor can shrink every input — and prove the sharper fact that if it shrinks even one file, it must enlarge another.],
  [Count strings, files, and messages, and connect every count back to bits, bytes, and the entropy we will meet in Chapter 18.],
  [Read Python that counts for you — `math.factorial`, `math.perm`, `math.comb`, and the `itertools` generators — and check hand calculations against it.],
))

== The two atoms of counting

All of combinatorics — every formula in this chapter, every limit later in the book — is built from just two rules. They are so simple you already use them without naming them. We are going to name them, because naming a tool lets you reach for it on purpose.

=== The multiplication principle: choices in a row

Imagine you are getting dressed. You own $3$ shirts and $4$ pairs of trousers. How many different outfits can you make? Pick a shirt — $3$ ways. *For each* of those, pick trousers — $4$ ways. Lay it out as a little branching tree: from each of the $3$ shirts grow $4$ branches, so there are $3 times 4 = 12$ outfits in all. You did not have to list them; you multiplied.

#fig([The multiplication principle as a tree. From a root, $3$ shirt-branches; from each shirt, $4$ trouser-branches; $3 times 4 = 12$ leaves, one per outfit.],
  cetz.canvas({
    import cetz.draw: *
    circle((0, 0), radius: 0.12, fill: c-accent2)
    let shirts = (3, 0, -3)
    for (si, sy) in shirts.enumerate() {
      line((0.12, 0), (3, sy))
      circle((3, sy), radius: 0.10, fill: c-accent)
      for ti in range(4) {
        let ty = sy + 1.05 - ti * 0.7
        line((3.1, sy), (6, ty))
        circle((6, ty), radius: 0.06, fill: c-key)
      }
    }
    content((0, -3.7))[#text(size: 8pt)[start]]
    content((3, -3.7))[#text(size: 8pt)[shirt (3 ways)]]
    content((6, -3.7))[#text(size: 8pt)[trousers (4 each)]]
  }))

That is the whole rule.

#definition("Multiplication principle")[
  If a thing is done in a sequence of independent steps, and step $1$ can be done in $n_1$ ways, step $2$ in $n_2$ ways (no matter how step $1$ went), and so on up to step $k$ in $n_k$ ways, then the whole sequence can be done in
  $ n_1 times n_2 times dots.c times n_k $
  ways. "Independent" here means the *number* of choices at each step does not change depending on earlier choices — it can be a different *set* of choices, as long as the count is the same.
]

The multiplication principle is where the doubling rule of Chapter 4 was hiding all along. Why does an $n$-bit number have $2^n$ possible values? Because writing it is a sequence of $n$ steps — choose the first bit ($2$ ways: $0$ or $1$), choose the second ($2$ ways), and so on $n$ times. By the multiplication principle that is $2 times 2 times dots.c times 2$, with $n$ twos, which is exactly $2^n$. The famous formula was a counting argument the whole time.

#keyidea[
  *When a task is "do this, then that, then the other," you multiply the counts.* This single move — multiply the number of choices at each independent step — is the engine under every formula in this chapter. If you remember nothing else, remember to multiply down a chain of choices.
]

Let us push it. How many three-letter "words" can you spell with our $26$-letter alphabet if letters may repeat (so `AAA` and `BOB` both count)? Three steps, $26$ choices each: $26 times 26 times 26 = 26^3 = 17576$. How many car number plates of the form letter-letter-digit-digit-digit? That is $26 times 26 times 10 times 10 times 10 = 676000$. Notice the steps did not all have the same number of choices — the rule never required that. You just multiply whatever the counts are.

A worked example we will reuse. Suppose a tiny file is exactly $3$ bytes long. How many such files exist? Each byte is one independent step with $256$ choices (Chapter 4), so $256 times 256 times 256 = 256^3 = 16777216$ — about $16.8$ million distinct $3$-byte files. Equivalently, a $3$-byte file is $24$ bits, and $2^24 = 16777216$ agrees to the digit, because $256^3 = (2^8)^3 = 2^24$. The two ways of slicing the same count — "three steps of $256$" and "twenty-four steps of $2$" — must land on the same number, and they do. This habit of computing one count two different ways and demanding they agree is not just a check; it is, as we will see, the beating heart of every proof in combinatorics.

#gomaths("Exponents as repeated multiplication, revisited")[
  We met exponents in Chapters 4 and 7; combinatorics leans on them constantly, so here is the one-line reminder. The notation $b^n$ means "$b$ multiplied by itself $n$ times": $2^3 = 2 times 2 times 2 = 8$, and $10^5 = 100000$. When every step of a multiplication-principle count offers the *same* number $b$ of choices, and there are $n$ steps, the product $b times b times dots.c times b$ ($n$ copies) is exactly $b^n$. So "how many length-$n$ strings over a $b$-symbol alphabet?" always has the same tidy answer: $b^n$. Bits are the case $b = 2$.
]

=== The addition principle: separate cases

The multiplication principle handles "and then." Its twin handles "or." Suppose you want a snack, and the kitchen has $3$ kinds of fruit and $5$ kinds of biscuit. You will eat *one* snack — a fruit *or* a biscuit, not both. How many choices? Not $3 times 5$; you are not pairing them. You are picking from one pile *or* the other, so you *add*: $3 + 5 = 8$ possible snacks.

#definition("Addition principle")[
  If a thing can be done by choosing exactly one of several *non-overlapping* groups of options, and the groups have $n_1, n_2, dots, n_k$ options respectively (with no option appearing in two groups), then the number of ways to do it is
  $ n_1 + n_2 + dots.c + n_k. $
  The catch is the word *non-overlapping*: the groups must share nothing, or you would count the shared options twice.
]

The whole art is telling "and" from "or." A useful habit: read your task aloud. Every "and then I also choose…" is a multiplication; every "it's either this kind or that kind…" is an addition. Mix them freely. *How many three-character passwords are either all-letters or all-digits?* All-letters is $26 times 26 times 26$ (three ands), all-digits is $10 times 10 times 10$ (three more ands), and "either/or" joins them with a plus: $26^3 + 10^3 = 17576 + 1000 = 18576$.

#pitfall[
  The addition principle *demands* non-overlapping groups. "How many numbers from $1$ to $100$ are divisible by $2$ or by $5$?" is *not* $50 + 20 = 70$, because numbers like $10$, $20$, $30$ are divisible by *both* and got counted twice. The fix is the *inclusion–exclusion* idea: add the groups, then subtract the overlap. Here $50 + 20 - 10 = 60$ (the $10$ multiples of $10$ are the overlap). Whenever your "or" piles can share members, watch for double counting — it is the single most common counting mistake, and it bites compression engineers who tally file types or symbol classes.
]

#checkpoint[
  A diner offers a "build your meal": one of $4$ starters, then one of $6$ mains, then either a coffee or a tea. How many distinct meals? And separately: how many ways to pick just *one* item from the whole menu (any single starter, main, or drink) to nibble?
][The full meal is three independent steps joined by "and": $4 times 6 times 2 = 48$ meals. Picking a single item is "or" across non-overlapping groups: $4 + 6 + 2 = 12$ items. Same numbers, opposite operations — because "and" multiplies and "or" adds.]

== Factorials: the number of orderings

Now a special, supremely useful count. Suppose $5$ runners finish a race and we record the finishing order. How many different orders are possible? Use the multiplication principle. The first place can go to any of the $5$ runners. *Once first place is taken*, only $4$ runners remain for second. Then $3$ for third, $2$ for fourth, and the last runner is forced into fifth — $1$ way. So the number of orderings is
$ 5 times 4 times 3 times 2 times 1 = 120. $
This "count down to one" product is so common it earns its own symbol and name: the *factorial*, written with an exclamation mark.

#definition("Factorial")[
  For a whole number $n >= 1$, the *factorial* of $n$, written $n!$ and read "$n$ factorial," is the product of all the whole numbers from $n$ down to $1$:
  $ n! = n times (n-1) times (n-2) times dots.c times 2 times 1. $
  By special convention $0! = 1$. So $1! = 1$, $2! = 2$, $3! = 6$, $4! = 24$, $5! = 120$, $6! = 720$.
]

That $0! = 1$ looks like a fudge. It is not — it is *forced*, and here are two reasons. First, the pattern. Notice that $n! = n times (n-1)!$ — for example $5! = 5 times 4!$. Run that backwards: $4! = 5! div 5 = 24$, $3! = 4! div 4 = 6$, $2! = 3! div 3 = 2$, $1! = 2! div 2 = 1$, and one more step gives $0! = 1! div 1 = 1$. The pattern *demands* the value $1$. Second, the meaning: $n!$ counts the orderings of $n$ things, and there is exactly *one* way to arrange *nothing* — the empty arrangement. Zero things, one ordering. Both roads land on $0! = 1$.

#keyidea[
  $n!$ is *the number of ways to put $n$ distinct things in a row*. Whenever you catch yourself asking "in how many orders…?", the answer involves a factorial. And $0! = 1$ is not a courtesy; it is what the recursion $n! = n(n-1)!$ and "one way to arrange nothing" both insist upon.
]

Factorials explode. This is worth feeling in your bones, because that explosion is the source of compression's hardest limits and its most dangerous brute-force traps.

#table(columns: (auto, auto, 1fr), inset: 6pt, align: (right, right, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*$n$*], [*$n!$*], [*how big is that?*]),
  [1], [1], [trivial],
  [5], [120], [orders of $5$ runners],
  [10], [$3{,}628{,}800$], [orders of a small class — already millions],
  [13], [$6{,}227{,}020{,}800$], [more than the human population],
  [20], [$approx 2.43 times 10^18$], [more than seconds since the dinosaurs],
  [52], [$approx 8.07 times 10^67$], [orderings of a shuffled deck of cards],
)

That last row deserves a pause. Shuffle a deck of $52$ cards properly and you almost certainly hold an ordering that *has never existed before in the history of the universe and never will again*. There are $52!$ orderings — about $8 times 10^67$ — and even if every human who ever lived had shuffled a deck once a second since the Big Bang, we would have produced a vanishingly tiny scratch on that number. Factorials are how counting reaches astronomical scales from humble beginnings.

#aside[
  Why do we care about this explosion in a compression book? Because the naive way to compress would be: "try every possible shorter file and see which one decodes to my data." For a mere $100$-byte file there are vastly more candidates than atoms in the observable universe. The factorial-and-exponential explosion of possibilities is precisely why brute force is hopeless and why we need *clever* algorithms — and, as we will see at the end of this chapter, why the perfect compressor is forbidden outright.
]

#gopython("Letting the computer count: math.factorial")[
  Python ships with a `math` module — a toolbox of mathematical functions you turn on with `import math`. One of its tools is `factorial`. You call it by writing the toolbox name, a dot, the tool name, and the input in parentheses:

  ```python
  import math
  print(math.factorial(5))    # 120
  print(math.factorial(0))    # 1   -- Python agrees: 0! = 1
  print(math.factorial(52))   # 80658175170943878571660636856403766975289505440883277824000000000000
  ```

  That last line prints all $68$ digits of $52!$ with no rounding. Most languages would overflow and give nonsense; Python's whole numbers (its `int` type) grow as large as your memory allows — a feature called *arbitrary precision*. For a book about exact bit counts, that is exactly the safety net we want: when we compute "how many possible files of this size," Python will not silently lie to us.
]

== Permutations: orderings of a chosen few

A factorial counts the orderings of *all* your things. But often you order only *some* of them. A club of $10$ members must elect a President, a Secretary, and a Treasurer — three *distinct* posts, and one person cannot hold two. How many outcomes? Multiplication principle: $10$ choices for President, then $9$ left for Secretary, then $8$ for Treasurer: $10 times 9 times 8 = 720$. We picked $3$ people *and put them in order* (the posts are distinguishable), drawing from $10$. That is a *permutation*.

#definition("Permutation")[
  A *permutation* of $k$ items chosen from $n$ distinct items is an *ordered* selection: you pick $k$ of the $n$ and arrange them in a sequence. The number of such permutations is written $P(n, k)$ (read "$n$ pick $k$" or "the number of $k$-permutations of $n$") and equals
  $ P(n, k) = underbrace(n times (n-1) times dots.c times (n-k+1), k "factors") = (n!)/((n-k)!). $
]

Why does $n! div (n-k)!$ equal that descending product? Write out $n! = n times (n-1) times dots.c times 1$. Dividing by $(n-k)! = (n-k) times dots.c times 1$ cancels the entire *tail* — everything from $(n-k)$ downward — leaving exactly the top $k$ factors $n times (n-1) times dots.c times (n-k+1)$. The factorial form is just a compact way to write "multiply the top $k$ numbers." For our election, $P(10,3) = 10! div 7! = 10 times 9 times 8 = 720$, matching the step-by-step count.

A vital special case: when $k = n$, we are ordering *all* the items, and $P(n, n) = n! div 0! = n! div 1 = n!$. The factorial is just the all-of-them permutation. (See $0! = 1$ doing quiet, essential work — without it this formula would break.)

Here is a worked example that will matter for compression. A *dictionary coder* (Chapters 28–32) sometimes needs to know how many distinct orderings a short block of symbols can take. Suppose a $4$-symbol window holds four *different* bytes and we ask in how many orders they could have arrived. That is $P(4,4) = 4! = 24$. Now suppose instead we pick which $2$ of those $4$ bytes form an ordered pair to seed a hash — that is $P(4,2) = 4 times 3 = 12$. Tiny counts like these decide how big a lookup table a codec must reserve.

== Combinations: when order does not matter

Now change the club's task. Instead of three distinct posts, they pick a committee of $3$ — three equal members, no ranks. How many committees? It is *not* $720$. The ordered count treated "Alice, then Bob, then Carol" as different from "Carol, then Bob, then Alice," but as a *committee* those are the *same three people*. We over-counted. By how much? Every committee of $3$ people can be written in $3! = 6$ different orders, so the ordered count is exactly $6$ times too big. Divide it out:
$ "committees" = (P(10,3))/(3!) = 720 / 6 = 120. $
This "pick a group, order does not matter" count is a *combination*.

#definition("Combination, and the binomial coefficient")[
  A *combination* of $k$ items chosen from $n$ distinct items is an *unordered* selection — a subset of size $k$. The number of them is written $binom(n, k)$ (read "$n$ choose $k$") and equals
  $ binom(n, k) = (P(n,k))/(k!) = (n!)/(k! (n-k)!). $
  The symbol $binom(n, k)$ is also called the *binomial coefficient*. It is always a whole number, even though the formula is a ratio of factorials.
]

#keyidea[
  *The one question that decides everything: does order matter?* If "A then B" differs from "B then A" (race finishes, passwords, post-holders), you want a *permutation* and you do *not* divide. If "A and B" is the same group as "B and A" (committees, hands of cards, subsets, sets of files), you want a *combination* and you *divide by $k!$* to kill the over-counting. Permutation, then divide by $k!$, gives combination. That single relationship, $binom(n,k) = P(n,k) div k!$, ties the two together.
]

#misconception[that permutations and combinations are basically the same idea with interchangeable formulas.][They differ by exactly the factor $k!$, and choosing the wrong one is the most common counting error there is. A permutation *records the order*; a combination *forgets it*. The lottery is the textbook trap: if a draw picks $6$ balls from $49$ and you must match the *set* of numbers (order on the machine is irrelevant), the count is the combination $binom(49,6) = 13983816$, not the permutation $P(49,6) = 10068347520$. Using the permutation would overstate the number of distinct tickets by a factor of $6! = 720$ and make your odds look $720$ times worse than they are. Whenever a problem says "the order doesn't matter," or you are choosing a *set*, divide the permutation count by $k!$ — or you will be off by exactly that factor, every time.]

Combinations are everywhere in compression. *How many ways can a $5$-bit number contain exactly two $1$s?* That is choosing *which* $2$ of the $5$ positions hold the ones — order among the positions does not matter, a set of positions is a set — so $binom(5, 2) = (5 times 4)/(2 times 1) = 10$. Indeed: `11000, 10100, 10010, 10001, 01100, 01010, 01001, 00110, 00101, 00011` — count them, ten. This little fact, "the number of $n$-bit strings with exactly $k$ ones is $binom(n,k)$," is the bridge from combinatorics to information theory, and we will lean on it hard.

#gomaths("Reading and simplifying $binom(n,k)$ by hand")[
  Do *not* compute the giant factorials and then divide — for $binom(52,5)$ that would mean handling $52!$, a $68$-digit monster. Instead use the *descending form*: $binom(n,k)$ has $k$ factors on top, counting down from $n$, over $k!$ on the bottom:
  $ binom(52, 5) = (52 times 51 times 50 times 49 times 48)/(5 times 4 times 3 times 2 times 1) = (311875200)/(120) = 2598960. $
  So there are about $2.6$ million distinct $5$-card poker hands. Two shortcuts worth knowing. *Symmetry:* $binom(n,k) = binom(n, n-k)$, because choosing which $k$ to *include* is the same as choosing which $n-k$ to *leave out* — so $binom(10,7) = binom(10,3) = 120$, and you compute the easier one. *Edges:* $binom(n,0) = 1$ (one way to choose nothing — the empty set) and $binom(n,n) = 1$ (one way to choose everything), and $binom(n,1) = n$.
]

#gopython("math.perm and math.comb")[
  The `math` module counts permutations and combinations directly, so you never hand-build the formula:

  ```python
  import math
  print(math.perm(10, 3))   # 720   -- ordered: P(10,3)
  print(math.comb(10, 3))   # 120   -- unordered: C(10,3)
  print(math.comb(52, 5))   # 2598960   -- poker hands
  print(math.comb(5, 2))    # 10    -- 5-bit strings with two 1s
  print(math.comb(10, 7) == math.comb(10, 3))   # True  -- symmetry
  ```

  `math.perm(n, k)` returns $P(n,k)$ and `math.comb(n, k)` returns $binom(n,k)$. Both refuse nonsense gracefully — ask for `math.comb(3, 5)` (choose $5$ from only $3$) and you get `0`, which is the honest answer: there are zero ways. These are the fastest, most reliable way to check any hand calculation in this chapter.
]

== Counting with constraints: the art of not double-counting

Real counting problems rarely arrive as a clean "choose $k$ from $n$." They come tangled — "at least one," "no two adjacent," "either this or that but watch the overlap." The professional's toolkit for untangling them is small but sharp: *count the complement*, and *inclusion–exclusion*. Both will reappear, in disguise, when codecs tally how many symbols, runs, or matches a buffer can hold, so they are worth a careful pass.

=== Counting the complement

Often the thing you want is hard to count head-on but its *opposite* is easy. The move: count *everything*, count the *unwanted* cases, and subtract. We already used it for "at least one $1$-bit": instead of summing $binom(8,1) + binom(8,2) + dots.c + binom(8,8)$, we counted all $256$ bytes and removed the single byte with *no* ones, getting $255$. The unwanted case was a lone outlier, trivial to count; the wanted case was a sprawling sum. Always ask: *is the opposite smaller?*

A compression-flavoured example. A simple codec packs data into $4$-byte blocks and treats a block as "interesting" if it is *not* constant (not all four bytes equal). How many of the $256^4$ possible blocks are interesting? Counting the interesting ones directly is a headache. Counting *constant* blocks is a breeze: a constant block is determined entirely by its single repeated byte value, so there are exactly $256$ of them. Hence interesting blocks number $256^4 - 256 = 4294967296 - 256 = 4294967040$. The complement turned a hard count into a subtraction.

#keyidea[
  *When "what you want" is awkward, count "what you don't want" and subtract from the total.* The complement trick is the counting equivalent of proof by contradiction — sneak up on the answer from behind. It is especially powerful for "at least one" conditions, whose opposite is the single tidy case "none."
]

=== Inclusion–exclusion: paying back the double count

The addition principle demanded *non-overlapping* groups. When groups *do* overlap, naively adding them counts the shared members twice, and you must pay the overlap back. For two overlapping groups $A$ and $B$, the count of "in $A$ or in $B$" is
$ |A "or" B| = |A| + |B| - |A "and" B|, $
where $|dot|$ means "the number of things in." You add both groups, then subtract the overlap once, because it was added twice. (We met this in the divisible-by-$2$-or-$5$ pitfall earlier; here we name it and prove it.)

#theorem("Inclusion–exclusion for two sets")[
  For any two finite sets $A$ and $B$, the size of their union is
  $ |A union B| = |A| + |B| - |A inter B|, $
  where $A union B$ is everything in $A$ or $B$ (or both) and $A inter B$ is what they share.
]

#proof[
  Count each element of $A union B$ and check it contributes exactly $1$ to the right-hand side. An element in $A$ only is counted once by $|A|$, not at all by $|B|$ or $|A inter B|$: total $1$. By symmetry an element in $B$ only also contributes $1$. An element in *both* $A$ and $B$ is counted by $|A|$ (once) *and* by $|B|$ (once), giving $2$, but then $-|A inter B|$ subtracts it once, leaving $2 - 1 = 1$. Every element of the union contributes exactly $1$, and nothing outside the union contributes, so the right-hand side equals $|A union B|$. #h(1fr)
]

Let us run the earlier numbers cleanly. Among the integers $1$ to $100$: multiples of $2$ form a set $A$ with $|A| = 50$; multiples of $5$ form $B$ with $|B| = 20$; their overlap (multiples of $10$) has $|A inter B| = 10$. So "divisible by $2$ or $5$" is $50 + 20 - 10 = 60$, and — using the complement trick on top — the count *coprime to $10$ in spirit* (divisible by neither) is $100 - 60 = 40$. Two tools, stacked, crack a problem neither solves alone.

#gomaths("Set-union notation, in one breath")[
  From Chapter 6: $A union B$ (say "$A$ union $B$") is the set of things in $A$, in $B$, or in both — the merge. $A inter B$ ("$A$ intersect $B$") is the set of things in *both* — the overlap. The bars $|A|$ count members. Inclusion–exclusion is just bookkeeping on these: merge sizes overshoot by exactly the overlap, so subtract it. For *three* overlapping sets the pattern continues: add the three singles, subtract the three pairwise overlaps, add back the one triple overlap — alternating $+,-,+$. We will only need the two-set version in this volume.
]

#checkpoint[
  In a survey of $40$ people, $25$ like tea, $18$ like coffee, and $9$ like both. How many like tea *or* coffee? How many like *neither*?
][Tea or coffee, by inclusion–exclusion: $25 + 18 - 9 = 34$ (subtract the $9$ double-counted "both" people). Neither, by the complement: $40 - 34 = 6$.]

== Pascal's triangle and the sum of all subsets

The binomial coefficients arrange themselves into one of the most beautiful objects in mathematics: *Pascal's triangle*. Start with a $1$ at the top. Each new row begins and ends with $1$, and every inner number is the *sum of the two numbers diagonally above it*. Row $n$ (counting from $0$) lists $binom(n,0), binom(n,1), dots, binom(n,n)$.

#fig([Pascal's triangle, rows $0$ to $5$. Each interior entry is the sum of the two above it; row $n$ holds $binom(n,0)$ through $binom(n,n)$. The numbers in row $n$ sum to $2^n$.],
  cetz.canvas({
    import cetz.draw: *
    let tri = (
      (1,),
      (1, 1),
      (1, 2, 1),
      (1, 3, 3, 1),
      (1, 4, 6, 4, 1),
      (1, 5, 10, 10, 5, 1),
    )
    for (r, row) in tri.enumerate() {
      for (c, v) in row.enumerate() {
        let x = c * 1.2 - r * 0.6
        let y = -r * 0.85
        content((x, y))[#text(size: 10pt)[#v]]
      }
      content((3.4, -r * 0.85))[#text(size: 8pt, fill: c-accent2)[sum $= #calc.pow(2, r)$]]
    }
  }))

Two facts about this triangle pay for the whole section.

#theorem("Pascal's rule")[
  For $0 < k < n$, $ binom(n, k) = binom(n-1, k-1) + binom(n-1, k). $
]

#proof[
  We count the $k$-subsets of an $n$-element set ${a_1, dots, a_n}$ two ways. The left side, $binom(n,k)$, is their total number by definition. For the right side, fix one element — say $a_n$ — and split every $k$-subset into two non-overlapping cases (addition principle). *Case 1: the subset contains $a_n$.* Then its other $k-1$ members are chosen from the remaining $n-1$ elements, giving $binom(n-1, k-1)$ such subsets. *Case 2: the subset does not contain $a_n$.* Then all $k$ members come from the remaining $n-1$ elements, giving $binom(n-1, k)$. Every $k$-subset is in exactly one case, so by the addition principle the total is $binom(n-1,k-1) + binom(n-1,k)$. Two counts of the same thing must agree. #h(1fr)
]

That proof is your first taste of a *combinatorial proof* — proving an identity not by grinding algebra but by counting one set of things two different ways and noticing the answers must match. It is the signature move of the subject, and it is exactly the style of argument that will forbid the magic box.

Now the fact that ties combinatorics back to Chapter 4 with a satisfying click.

#theorem("The subset-counting identity")[
  A set of $n$ distinct elements has exactly $2^n$ subsets in total, and therefore
  $ binom(n,0) + binom(n,1) + binom(n,2) + dots.c + binom(n,n) = 2^n. $
]

#proof[
  Count the subsets of an $n$-element set two ways. *First way:* build a subset by walking through the $n$ elements and, for each one, deciding *in or out* — $2$ choices per element, $n$ independent elements, so by the multiplication principle $2 times 2 times dots.c times 2 = 2^n$ subsets. *Second way:* group the subsets by their size. The number with exactly $k$ elements is $binom(n,k)$ by definition, and a subset has some size between $0$ and $n$, so by the addition principle the total is $binom(n,0) + binom(n,1) + dots.c + binom(n,n)$. Both ways count all subsets, so the two expressions are equal. #h(1fr)
]

#keyidea[
  *Each row of Pascal's triangle sums to a power of two.* That is not a coincidence — it is the same $2^n$ from Chapter 4, because choosing a subset is making $n$ independent in/out decisions, exactly like writing $n$ bits. A subset of $n$ things and an $n$-bit string are the *same object* (a $1$ where an element is "in," a $0$ where it is "out"). Counting subsets and counting bit-strings are one activity. Hold onto this: it is the hinge of the entire chapter.
]

#checkpoint[
  Without summing term by term, what is $binom(8,0) + binom(8,1) + dots.c + binom(8,8)$? And what does that number have to do with a *byte*?
][By the subset-counting identity it is $2^8 = 256$. That is exactly the number of values a byte (8 bits) can hold, from Chapter 4 — because each of the $8$ bits is an independent in/out choice, and summing $binom(8,k)$ over all $k$ just regroups those same $256$ bytes by how many $1$-bits they contain.]

Our compressor `tinyzip` is still gathering its mathematical tools — the first real codec, and the project's first numbered build step, arrives in Chapter 24 (Huffman coding). This chapter adds no `tinyzip` step of its own; the canonical step numbers are reserved for chapters that ship code into the package. But counting is something we can *use right now* to keep ourselves honest, so here is a little illustrative script — not part of the official `tinyzip` build, just a sanity-checker — that reports how many distinct files of a given size exist, so we can test any claim about compression against the cold arithmetic.

#tryit[
  A few reading notes, since the full Python primer is still chapters away (Chapters 15--17). The word `def` *defines a function* — a named recipe that takes inputs in parentheses and hands back a result with `return`; we met `def` already in Chapter 7's foretaste box. Type hints like `n: int` and `-> int` simply say "this expects a whole number and returns a whole number" — Python ignores them at runtime, but they document intent. The line `for length in range(max_bytes + 1):` repeats the indented body once for each value `length` takes from `0` up to `max_bytes` (`range(N)` walks $0, 1, dots, N-1$), so it is the addition principle written as a loop. The final `if __name__ == "__main__":` is a Python idiom meaning "only run the lines below when this file is launched directly" — a self-test that fires when you run the script but stays quiet when another file imports it. None of this is needed to follow the counting; it just lets the machine confirm our arithmetic.

  ```python
  import math

  def num_files(num_bytes: int) -> int:
      """How many distinct files are exactly num_bytes long?
      Each byte holds one of 256 values, chosen independently."""
      return 256 ** num_bytes        # 256 = 2**8 values per byte

  def num_files_up_to(max_bytes: int) -> int:
      """How many files have length 0, 1, ..., up to max_bytes?
      Addition principle: sum the count for each separate length."""
      total = 0
      for length in range(max_bytes + 1):   # 0, 1, ..., max_bytes
          total += num_files(length)
      return total

  def bits_with_k_ones(n: int, k: int) -> int:
      """How many n-bit strings contain exactly k ones? Choose the positions."""
      return math.comb(n, k)

  if __name__ == "__main__":
      print(num_files(1))            # 256
      print(num_files(10))           # 1208925819614629174706176  (~1.2e24)
      print(bits_with_k_ones(8, 2))  # 28  -- bytes with exactly two 1-bits
  ```

  `num_files` is the multiplication principle in one line: $256^("num_bytes")$. `num_files_up_to` is the addition principle: lengths are non-overlapping cases, so we sum. The very next section uses exactly these counts to *prove* that no compressor can shrink every file — the code and the theorem are the same counting argument, one in Python and one in prose.
]

== The pigeonhole principle: the humblest theorem

We now have everything we need for the chapter's promised payoff. The tool that finishes the job is so obvious it sounds like a joke, yet mathematicians give it a dignified name: the *pigeonhole principle*.

#theorem("Pigeonhole principle")[
  If you place $n$ objects into $m$ boxes and $n > m$ (more objects than boxes), then at least one box must contain two or more objects.
]

#proof[
  Suppose, to the contrary, that every box held *at most one* object. Then the total number of objects spread across the $m$ boxes could be at most $1 + 1 + dots.c + 1 = m$ (one per box, by the addition principle). But we were given $n$ objects with $n > m$, so we have more objects than that ceiling allows — a contradiction. Hence some box holds at least two. #h(1fr)
]

That is the entire theorem. If $13$ people are in a room, two of them share a birth month, because there are only $12$ months and $13 > 12$. If you own $10$ pairs of socks (so $11$ socks pulled blindly from a drawer in the dark), two must match, because there are only $10$ colours. It feels too trivial to be useful. It is, in fact, one of the most powerful proof tools in mathematics — and it is about to slam the door on the magic box forever.

#history[
  The principle is often credited to the German mathematician Peter Gustav Lejeune Dirichlet, who used it in 1834 under the name *Schubfachprinzip* — the "drawer principle." (Hence its other name, *Dirichlet's drawer principle*.) The homely "pigeons and pigeonholes" image came later in English. Dirichlet used it to prove deep facts in number theory; that a tool from 1834 number theory turns out to govern the limits of digital compression is one of those quiet unities that make mathematics worth studying.
]

#aside[
  There is a *sharpened* form worth knowing. If you put $n$ objects into $m$ boxes, some box must contain at least $ceil(n/m)$ objects. The symbol $ceil(x)$ is the *ceiling* of $x$: round $x$ *up* to the next whole number (so $ceil(11.1) = 12$ and $ceil(4) = 4$); we will use it again at the end of the chapter to price messages in whole bits. With $n = 100$ objects in $m = 9$ boxes, some box has at least $ceil(100/9) = ceil(11.1) = 12$. The plain principle is just this with the mild claim "at least $2$" when $n > m$. We will only need the plain form for the compression theorem, but the sharp form is what professionals reach for.
]

== The counting bound: why no compressor shrinks everything

Here it is — the theorem that makes the magic box a fraud. We will state it, prove it with nothing but counting and pigeonholes, and then unpack exactly what it does and does not forbid (because the misreadings of this theorem are themselves a small industry).

First, recall the non-negotiable fact from Chapter 6: a *lossless* compressor must be a *bijection* on the files it handles — or at the very least *injective* (one-to-one), meaning no two different inputs are ever sent to the same output. If two different files `A` and `B` both compressed to the same output `C`, then on decompression, faced with `C`, the machine could not know whether to return `A` or `B`. Lossless means *perfectly reversible*, and reversibility *is* one-to-one-ness. Keep that single requirement in hand; the rest is counting.

#theorem("The counting bound — no universal shrinker")[
  No lossless compression scheme can map *every* possible input file to a strictly shorter output. For any lossless compressor, there exists at least one file whose output is at least as long as the input. Moreover, if the compressor makes even *one* file strictly shorter, then it must make at least one *other* file strictly longer.
]

#proof[
  Measure files in bits, and consider all files of length *up to* $n$ bits. How many are there? By the multiplication and addition principles, the number of files of length exactly $k$ bits is $2^k$, so the number of files of length $0$ up to $n$ bits is
  $ 2^0 + 2^1 + dots.c + 2^n = 2^(n+1) - 1, $
  a finite pile of "pigeons." (That sum is the all-ones binary number with $n+1$ digits; see Chapter 4.)

  Now suppose, for contradiction, that our compressor shrank *every* file of length up to $n$ — that is, mapped each input of length $k <= n$ to some strictly shorter output, of length at most $k - 1$, hence of length at most $n - 1$. The possible *outputs* are then files of length $0$ up to $n - 1$ bits, and there are only
  $ 2^0 + 2^1 + dots.c + 2^(n-1) = 2^n - 1 $
  of those — the "pigeonholes." Compare the two counts: we have $2^(n+1) - 1$ inputs forced into at most $2^n - 1$ outputs, and since $2^(n+1) - 1 > 2^n - 1$, there are strictly more inputs than outputs. By the pigeonhole principle, two different inputs must collide on the same output. But a colliding pair destroys reversibility — the decompressor cannot recover both — so the compressor is *not lossless*. Contradiction. Therefore no lossless compressor shrinks every file.

  The sharper claim follows the same way. The compressor is injective, so it is a one-to-one matching of the $2^(n+1)-1$ short files onto distinct files. If it sends some file to a *shorter* output, that shorter slot is now occupied; because the matching is one-to-one and the short slots are finite, the displaced files must land *somewhere*, and counting slots shows at least one file is pushed to a *longer* output. You cannot give one file a shorter codeword without lengthening another — the bits have to go somewhere. #h(1fr)
]

#keyidea[
  *Compression is a zero-sum rearrangement of a fixed pile of names.* There are exactly $2^n$ possible $n$-bit files and exactly $2^n$ possible $n$-bit codewords — the same number, by the doubling rule. A compressor just *re-pairs* files with codewords. Hand short codewords to some files and you have spent them; other files are forced onto long codewords. No scheme escapes this, because it is pure counting: $2^(n+1)-1$ pigeons will never fit into $2^n - 1$ holes.
]

#misconception[that a good enough algorithm could compress any file, and compress already-compressed files again and again down to nearly nothing.][The counting bound forbids it absolutely. Each round of a real lossless compressor is a one-to-one map, so re-compressing cannot keep shrinking — if it did forever, you would eventually map a huge set of files into a tiny set, colliding by pigeonhole and breaking reversibility. This is why zipping a `.zip` file usually makes it *slightly larger*, not smaller: the data is already near the bottom of its possibility pile, and the second compressor's own overhead (headers, tables) tips it over. The "infinite compression" or "compress anything" products sold over the decades were all, without exception, mathematically impossible — and the proof is the counting you just did.]

So why does compression *work at all*, if it cannot shrink everything? Because we never feed compressors *random* files. Real data — English text, photographs, audio, program code — is a microscopically tiny, highly structured corner of the gigantic space of all possible files. A compressor is built to hand *short* codewords to the files that actually occur (the structured ones) and pay for it with *long* codewords on the files that essentially never occur (the random-looking ones). It robs the improbable to pay the probable. The counting bound does not say compression is impossible; it says compression must be *selective* — and the art of the entire field is choosing *which* files to favour.

#keyidea[
  *Compression is not magic shrinkage; it is a bet on which files are likely.* A good compressor assigns short codes to probable inputs and long codes to improbable ones. It wins on real data precisely because real data is rare and patterned. This is the seed of Shannon's entropy (Chapter 18): the best you can do is spend about $log_2(1 div p)$ bits on a file of probability $p$ — short codes for likely files, long for unlikely — and counting is what makes that trade unavoidable.
]

#checkpoint[
  A start-up claims their app losslessly compresses *any* $1$-megabyte file to at most $900$ kilobytes. Using only counting, why can you be certain they are wrong before testing a single file?
][There are $2^("8,388,608")$ distinct $1$-MB files (a megabyte is $2^20$ bytes $= 8388608$ bits, each independently $0$ or $1$). The claimed outputs are files of at most $900$ KB, and there are far fewer of those — only about $2^("7,372,800")$ up to that length, an astronomically smaller pile. More inputs than outputs forces a pigeonhole collision, which breaks losslessness. The claim is impossible by counting alone, no test required.]

== Counting messages: from possibilities to bits

The counting bound told us *how many* files there are. The same counting also tells us *how many bits a message needs* — and that is the doorway into Chapter 18. The link is the doubling rule read backwards. We know $n$ bits name $2^n$ things; turn it around and ask: to name $M$ distinct things, how many bits do I need? The answer is the *logarithm* from Chapter 7.

#gomaths("From a count to a bit-length: the ceiling of a log")[
  If you must give a distinct binary name to each of $M$ different items, you need $b$ bits where $2^b >= M$ — enough room for all $M$. The smallest such $b$ is $b = ceil(log_2 M)$: take the base-$2$ logarithm of the count and round *up* (the ceiling $ceil(dot)$ from the pigeonhole aside) to the next whole number — you cannot buy a fractional bit. For $M = 256$ items, $log_2 256 = 8$ exactly, so $8$ bits — a byte — names them with none to spare. For $M = 1000$, $log_2 1000 approx 9.97$, so $ceil(9.97) = 10$ bits, and indeed $2^10 = 1024 >= 1000$ with a little slack. *Counting a possibility space and taking its log is how you price a message in bits* — the move at the heart of every chapter to come.
]

So combinatorics quietly sets the cost of everything. *How many bits to record one shuffle of a $52$-card deck?* There are $52!$ orderings, so you need $ceil(log_2(52!)) approx ceil(225.6) = 226$ bits — about $29$ bytes — and not one bit fewer can losslessly distinguish all shuffles. Pause on how good a deal that is: a naive recording might list all $52$ cards by name, spending a byte per card, $52$ bytes — but counting reveals the *true* cost is only $29$ bytes, because most of those $52$-byte sequences are nonsense (they repeat cards or omit them) and a shuffle can never be one of them. The gap between $52$ bytes and $29$ bytes is *exactly the redundancy* a good compressor would remove, and counting is what told us, in advance and with certainty, that $29$ bytes is the floor and not a fraction less. *How many bits to record which $5$ of $52$ cards make a poker hand, order irrelevant?* That is $binom(52,5) = 2598960$ possibilities, needing $ceil(log_2 2598960) = 22$ bits. The count of possibilities, run through a logarithm, *is* the irreducible size of the message. Counting and compression are the same subject seen from two sides.

#gopython("Generating every possibility: the itertools toolbox")[
  Counting tells you *how many*; sometimes you want to *see them all*. Python's `itertools` module manufactures the actual arrangements, one at a time, without storing them all in memory (it yields them lazily, a *generator*). Two of its tools mirror this chapter exactly:

  ```python
  import itertools, math

  # permutations: ordered arrangements (order matters)
  perms = list(itertools.permutations("ABC", 2))
  print(perms)        # [('A','B'),('A','C'),('B','A'),('B','C'),('C','A'),('C','B')]
  print(len(perms), math.perm(3, 2))     # 6 6  -- count matches P(3,2)

  # combinations: unordered selections (order does NOT matter)
  combs = list(itertools.combinations("ABC", 2))
  print(combs)        # [('A','B'),('A','C'),('B','C')]
  print(len(combs), math.comb(3, 2))     # 3 3  -- count matches C(3,2)
  ```

  Notice `permutations` lists `('A','B')` *and* `('B','A')` — order matters, six results. `combinations` lists only `('A','B')` — order is ignored, three results, exactly $6 div 2! = 3$. Wrapping a generator in `list(...)` runs it to the end and collects the results into a list so you can print them. Whenever a formula in this chapter feels abstract, generate the small cases with `itertools` and *count them by eye* — the formula and the list will always agree.
]

#tryit[
  Open a Python prompt and run `len(list(itertools.permutations(range(5))))`. You should get $120 = 5!$. Now try `range(6)` and watch it jump to $720$, then `range(8)` for $40320$. Feel how fast the factorial climbs — and resist `range(20)`, which would try to build $2.4 times 10^18$ tuples and never finish. That wall is the same explosion that makes brute-force compression hopeless.
]

#note[
  A subtlety we have quietly assumed: in this chapter every item being arranged was *distinct* (different runners, different cards, different bytes). When items *repeat* — the letters of `MISSISSIPPI`, or a file full of one byte value — the naive counts over-count, and you divide by the factorials of the repeats. We will not need the repeated-item formulas to state compression's limits, and Chapter 9 (probability) reframes the whole question in terms of likelihoods rather than raw counts, which turns out to be the more powerful lens for real, lopsided data. For now, the distinct-item counts give us the clean outer bounds we came for.
]

#takeaways((
  [*Two atoms.* "And then" multiplies counts (multiplication principle); "either/or" over non-overlapping cases adds them (addition principle). Watch for double-counting when "or" piles overlap.],
  [*Factorial.* $n! = n(n-1)dots.c 1$ counts the orderings of $n$ distinct things; $0! = 1$ is forced by the recursion $n! = n(n-1)!$ and by "one way to arrange nothing."],
  [*Permutations vs combinations.* If order matters, $P(n,k) = n! div (n-k)!$. If order does not, divide out the over-count: $binom(n,k) = P(n,k) div k! = n! div (k!(n-k)!)$.],
  [*Subsets are bit-strings.* A subset of $n$ things is an $n$-bit in/out string, so there are $2^n$ of them, and $sum_k binom(n,k) = 2^n$ — each row of Pascal's triangle sums to a power of two.],
  [*Pigeonhole.* More objects than boxes forces two into one box. Trivial to state, decisive in use.],
  [*The counting bound.* No lossless compressor shrinks every file; if it shortens one, it must lengthen another. Compression is a zero-sum re-pairing of a fixed pile of names — it works only by betting on which files are likely.],
  [*Possibilities price messages.* To name $M$ things you need $ceil(log_2 M)$ bits; counting a possibility space and taking its log gives the irreducible message size — the bridge to entropy in Chapter 18.],
))

== Exercises

#exercise("8.1", 1)[
  A café offers $3$ sizes of coffee, $4$ syrups (or none), and milk *or* no milk. How many distinct drinks are possible? Identify which steps are "and" (multiply) and which choice is hidden inside one of them.
]
#solution("8.1")[
  Three independent "and" steps: size ($3$ ways), syrup ($4$ syrups *plus* the "none" option $= 5$ ways), milk ($2$ ways: milk or not). By the multiplication principle $3 times 5 times 2 = 30$ drinks. The hidden choice is that "or none" adds one to the syrup count ($4 + 1 = 5$) before it enters the product.
]

#exercise("8.2", 1)[
  Compute by hand, using the descending-product shortcut (do not expand the full factorials): (a) $P(7,3)$, (b) $binom(7,3)$, (c) $binom(7,4)$. What relationship between (b) and (c) did you expect before computing, and why?
]
#solution("8.2")[
  (a) $P(7,3) = 7 times 6 times 5 = 210$. (b) $binom(7,3) = 210 div 3! = 210 div 6 = 35$. (c) $binom(7,4) = (7 times 6 times 5 times 4) div 4! = 840 div 24 = 35$. We expected (b) $=$ (c) by symmetry $binom(n,k) = binom(n,n-k)$: choosing which $3$ of $7$ to include is the same as choosing which $4$ to exclude.
]

#exercise("8.3", 1)[
  Prove from the recursion alone that $0! = 1$, and then explain in one sentence why the combination formula $binom(n,n) = n! div (n!\, 0!)$ would give the wrong answer if instead we declared $0! = 0$.
]
#solution("8.3")[
  The recursion is $n! = n times (n-1)!$. Setting $n = 1$ gives $1! = 1 times 0!$, and since $1! = 1$ we get $1 = 1 times 0!$, forcing $0! = 1$. If we wrongly set $0! = 0$, then $binom(n,n) = n! div (n! times 0!) = n! div 0$, a division by zero — undefined nonsense — whereas the correct $0! = 1$ gives $binom(n,n) = n! div n! = 1$, the right answer (one way to choose everything).
]

#exercise("8.4", 2)[
  How many $8$-bit bytes contain *exactly three* $1$-bits? How many contain *at least* one $1$-bit? Express each as binomial coefficients and give the numbers.
]
#solution("8.4")[
  Exactly three ones: choose which $3$ of the $8$ positions are ones, $binom(8,3) = (8 times 7 times 6) div 6 = 56$. At least one one: easier to count the *complement*. There is exactly one byte with *zero* ones (`00000000`), and $2^8 = 256$ bytes total, so at-least-one is $256 - 1 = 255$. (Equivalently $sum_(k=1)^8 binom(8,k) = 2^8 - binom(8,0) = 255$.)
]

#exercise("8.5", 2)[
  Using the subset–bitstring correspondence, prove that a set with $n$ elements has $2^n$ subsets by a direct "in or out" argument, and state what the empty set and the full set correspond to as bit-strings.
]
#solution("8.5")[
  Build a subset by deciding, for each of the $n$ elements in turn, whether it is *in* ($1$) or *out* ($0$). These are $n$ independent $2$-way choices, so by the multiplication principle there are $2 times 2 times dots.c times 2 = 2^n$ subsets, and each corresponds to a unique $n$-bit string (and vice versa), a bijection. The empty set is the all-zeros string `00...0` (nothing in); the full set is the all-ones string `11...1` (everything in).
]

#exercise("8.6", 2)[
  A "lossless super-compressor" claims to turn every $3$-bit file into a $2$-bit file. List all $3$-bit files and all $2$-bit files, count both, and use the pigeonhole principle to point to the exact contradiction.
]
#solution("8.6")[
  There are $2^3 = 8$ three-bit files (`000` through `111`) and only $2^2 = 4$ two-bit files (`00`,`01`,`10`,`11`). Mapping $8$ inputs into $4$ outputs puts more pigeons ($8$) than holes ($4$), so by the pigeonhole principle at least two of the eight inputs share one output. Those two inputs are now indistinguishable on decompression, so the scheme cannot be lossless. The claim is impossible.
]

#exercise("8.7", 2)[
  Prove Pascal's rule $binom(n,k) = binom(n-1,k-1) + binom(n-1,k)$ *algebraically* from the factorial formula (a different proof from the combinatorial one in the text), for $0 < k < n$.
]
#solution("8.7")[
  Start from the right: $binom(n-1,k-1) + binom(n-1,k) = ((n-1)!)/((k-1)!(n-k)!) + ((n-1)!)/(k!(n-1-k)!)$. Give both a common denominator $k!(n-k)!$. The first term becomes $((n-1)! times k)/(k!(n-k)!)$ (multiplying top and bottom by $k$); the second becomes $((n-1)! times (n-k))/(k!(n-k)!)$ (multiplying by $n-k$). Add the numerators: $(n-1)!(k + (n-k)) = (n-1)! times n = n!$. So the sum is $n! div (k!(n-k)!) = binom(n,k)$.
]

#exercise("8.8", 2)[
  How many bits are needed to losslessly record which specific $5$ books a reader chose from a shelf of $30$ (order irrelevant)? Show the count and the bit-length, and explain why you round *up*.
]
#solution("8.8")[
  The number of choices is $binom(30,5) = (30 times 29 times 28 times 27 times 26) div 120 = 142506$. The bit-length is $ceil(log_2 142506)$. Since $2^17 = 131072$ and $2^18 = 262144$, we have $log_2 142506$ between $17$ and $18$, so $ceil(dots) = 18$ bits. We round *up* because $17$ bits name only $131072$ items — too few for $142506$ — so we need the next whole bit to give every selection a distinct name; you cannot buy a fractional bit.
]

#exercise("8.9", 3)[
  Prove the sharpened counting claim in full: if a lossless compressor maps some file to a strictly shorter output, then among files of length up to $n$ bits, at least one is mapped to a strictly *longer* output (for $n$ large enough to contain the shortened file). Argue purely by counting one-to-one slots.
]
#solution("8.9")[
  Fix $n$ large enough that the shortened file has length $<= n$. Consider the $S = 2^(n+1) - 1$ files of length $0..n$. A lossless compressor is injective, so it sends these $S$ files to $S$ *distinct* outputs. Partition outputs by length: there are $2^0 + dots.c + 2^n = S$ output slots of length $<= n$ in total — exactly as many slots as files. Now suppose, for contradiction, that *no* file of length $<= n$ is mapped to length $> n$; then all $S$ outputs land in those $S$ short slots, a perfect one-to-one filling. But we assumed one file was mapped *strictly shorter* than its own length: that file vacates its "same-length-or-longer" region and occupies a shorter slot, so by injectivity some other file is displaced. Since every short slot would have to be filled exactly once, the displaced file cannot fit among length-$<= n$ slots without colliding — contradicting that all outputs stayed $<= n$. Hence at least one file must spill to length $> n$, i.e. be made strictly longer. The bits saved on one file are paid for by another.
]

#exercise("8.10", 3)[
  A run-length idea: a binary file is described instead by listing the *lengths* of its alternating runs of $0$s and $1$s. Count how many binary strings of length $8$ have *exactly $3$ runs* (maximal blocks of one symbol), and explain why this counting connects to why run-length encoding helps on some files and hurts on others.
]
#solution("8.10")[
  A length-$8$ string with exactly $3$ runs is determined by (a) the symbol of the first run ($2$ choices: starts with $0$ or $1$) and (b) where the $2$ run-boundaries fall among the $7$ gaps between the $8$ positions, choosing $2$ of those $7$ gaps to be "change points": $binom(7,2) = 21$. By the multiplication principle that is $2 times 21 = 42$ strings. *Connection:* only $42$ of the $256$ length-$8$ strings have as few as $3$ runs — these are the "smooth" files run-length encoding shrinks. The vast majority have many runs, where listing run-lengths costs *more* than the original. That split — a few files helped, most hurt — is the counting bound in miniature: RLE is a bet that the data is run-smooth, and it loses that bet on most of the possibility space.
]

== Further reading

- Wikipedia, #link("https://en.wikipedia.org/wiki/Lossless_compression")[_Lossless compression_] — the "Limitations" section gives the counting/pigeonhole argument in compact form; a good cross-check of this chapter's central proof.
- Wikipedia, #link("https://en.wikipedia.org/wiki/Pigeonhole_principle")[_Pigeonhole principle_] — history (Dirichlet's 1834 drawer principle), the sharpened form, and a gallery of surprising applications.
- Richard A. Brualdi, _Introductory Combinatorics_ — a classic, friendly textbook on permutations, combinations, the binomial theorem, and inclusion–exclusion, if you want to go deeper than this chapter.
- The Python documentation, #link("https://docs.python.org/3/library/itertools.html")[_itertools_] and #link("https://docs.python.org/3/library/math.html")[_math_] — authoritative reference for `permutations`, `combinations`, `factorial`, `perm`, and `comb`, with the exact counting formulas each one obeys.

#bridge[
  Counting gave us hard walls: there are only so many files, and a compressor can only re-pair them, never conjure free space. But raw counting treats every file as equally worth worrying about — and that is *not* how the world works. The files that actually occur are wildly lopsided: the letter `e` is everywhere, `q` is rare, a photo of the sky is far likelier than random static. To turn "how many possibilities" into "how *likely* is each," we need a new and more flexible language: *probability*. Chapter 9 builds it from coins and dice, from scratch, and with it we will replace crude counts with weighted ones — the exact upgrade that, in Chapter 18, becomes Shannon's entropy and the true floor of compression.
]
