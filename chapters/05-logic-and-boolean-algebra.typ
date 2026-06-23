#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Logic and Boolean Algebra

#epigraph[The design of switching circuits is essentially a problem in logic.][Claude Shannon, _A Symbolic Analysis of Relay and Switching Circuits_, 1938]

In 1937 a 21-year-old graduate student at MIT sat down to tidy up a mess. The mess was Vannevar Bush's _differential analyzer_, a room-sized mechanical computer wired together from hundreds of relays — little electromagnetic switches that clack open and shut. Each relay was either letting current through or not. Engineers designed these tangles by hand, by intuition, by trial and error, and nobody could say whether a given web of relays was the _simplest_ one that did the job, or even whether it did the job at all.

The student noticed something that everyone before him had missed. A relay has exactly two states — on or off — and so does a statement in a strange branch of mathematics that an English schoolteacher named George Boole had dreamed up almost a century earlier, where every sentence is either _true_ or _false_ and nothing in between. Boole had built an entire algebra out of truth and falsehood, complete with its own version of "plus" and "times". The student — Claude Shannon, whom you will meet again and again in this book — realised that Boole's true/false algebra and the engineer's on/off relays were _the same thing wearing two costumes_. A circuit of switches could compute any logical statement, and any logical statement could be wired up as a circuit. His master's thesis, often called the most important master's thesis of the twentieth century, is the reason the device you are reading this on exists.

That single idea — that *the on/off bit and the true/false statement are one and the same* — is the hinge on which all of computing turns, and it is the subject of this chapter. We will build Boole's algebra from absolutely nothing, watch it become the wiring diagram of a computer, and then collect the handful of identities (De Morgan's laws, the absorption law, the XOR trick) that a compression engineer reaches for almost every day.

#recap[
  In Chapter 3 we learned that all data is built from _symbols_ drawn from an _alphabet_, and that the smallest possible alphabet has just two symbols. In Chapter 4 we wrote numbers in that two-symbol alphabet — _binary_ — and called each symbol a *bit*, a $0$ or a $1$. We even built two's-complement negatives by flipping bits. That left an obvious question dangling: a bit can _store_ a $0$ or a $1$, but can it _compute_? Can we make bits reason, decide, and combine? This chapter answers yes, and shows exactly how.
]

#objectives((
  [Read and write the truth tables for the operations NOT, AND, OR, XOR, NAND, and NOR.],
  [Translate an everyday English sentence into a Boolean expression and back again.],
  [Use the laws of Boolean algebra — commutativity, distributivity, De Morgan's laws, absorption — to simplify an expression, and prove why each law holds.],
  [Explain why NAND alone (or NOR alone) can build _every_ possible logic circuit.],
  [See how a logic gate is just a Boolean operation made of transistors, and why a bit and a truth value are the same object.],
  [Recognise XOR and parity as the workhorses behind error detection, encryption, and the filters inside real compressors like PNG.],
))

== Two values, and the algebra of certainty

Ordinary algebra — the algebra you met in school, with its $x$ and $y$ — lets its letters stand for _any_ number at all. $x$ might be $3$, or $-17$, or $0.5$, or a billion. Boolean algebra is the same game played on a board with only two squares. Every quantity is one of exactly two values, and there is nothing else to choose from. We will write those two values as

$ 0 quad "and" quad 1, $

and read them, depending on the story we are telling, as *false* and *true*, or as *off* and *on*, or as _no_ and _yes_, or as the two bits from Chapter 4. They are all the same two values. Throughout this chapter, "$0$ means false, $1$ means true" — burn that in. The whole reason the subject is useful is that this tiny two-value world turns out to describe both human reasoning _and_ electrical switches _and_ the bits in a file, all at once.

#keyidea[
  A *Boolean variable* is a name — say $A$ — that stands for one of the two values $0$ or $1$. A *Boolean operation* takes one or more such variables and produces another $0$ or $1$. That is the entire vocabulary. Because there are only two values, we can describe any operation completely by simply _listing what it does in every case_. That list is called a *truth table*, and it is the most honest, most foolproof tool in this chapter: there is nowhere for a mistake to hide.
]

Let us meet the three operations that everything else is built from. They are named after three English words you already use every day — *not*, *and*, *or* — and each one means almost exactly what the English word means.

=== NOT: the flip

The simplest operation takes a single value and flips it. If the input is true, the output is false; if the input is false, the output is true. This is *NOT*, also called _negation_ or _logical complement_. In English: "It is _not_ raining" is true precisely when "It is raining" is false. We write NOT of $A$ in several interchangeable ways — $not A$, or $overline(A)$ (a bar over the top), or $A'$ (a little prime). We will mostly use the bar, $overline(A)$, because it is compact and it is what most circuit diagrams use.

Here is its truth table. The left column lists every possible input; the right column gives the output.

#align(center, table(columns: 2, inset: 7pt, align: center,
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([$A$], [$overline(A)$]),
  [$0$], [$1$],
  [$1$], [$0$],
))

Two rows, because a single bit has only two possible values. Notice a fact we will use constantly: flipping twice gets you back where you started. $overline(overline(A)) = A$. Negating "it is raining" gives "it is not raining"; negating _that_ gives "it is not the case that it is not raining" — which is just "it is raining" again. This is the *double-negation law*, and it is your first Boolean identity.

=== AND: both must hold

*AND* takes two values and outputs $1$ only when _both_ inputs are $1$. In English: "I will go outside AND it is sunny" is true only in the single case where I do go outside _and_ it is in fact sunny; if either part fails, the whole sentence fails. We write AND of $A$ and $B$ as $A and B$, or — borrowing from ordinary multiplication — simply as $A B$ or $A dot B$. That multiplication notation is not an accident, as we are about to see.

#align(center, table(columns: 3, inset: 7pt, align: center,
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([$A$], [$B$], [$A and B$]),
  [$0$], [$0$], [$0$],
  [$0$], [$1$], [$0$],
  [$1$], [$0$], [$0$],
  [$1$], [$1$], [$1$],
))

Four rows now, because two bits have $2 times 2 = 4$ possible combinations. Look at the output column read as ordinary arithmetic: $0, 0, 0, 1$. That is _exactly_ what you get if you multiply the two inputs together: $0 times 0 = 0$, $0 times 1 = 0$, $1 times 0 = 0$, $1 times 1 = 1$. *AND is multiplication of bits.* This is the first half of why Boole called his system an _algebra_.

=== OR: at least one must hold

*OR* takes two values and outputs $1$ when _at least one_ input is $1$. In English: "I will take an umbrella OR a raincoat" is satisfied if I take the umbrella, or the raincoat, or both — it fails only if I take neither. We write OR of $A$ and $B$ as $A or B$, or, again borrowing from arithmetic, as $A + B$.

#align(center, table(columns: 3, inset: 7pt, align: center,
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([$A$], [$B$], [$A or B$]),
  [$0$], [$0$], [$0$],
  [$0$], [$1$], [$1$],
  [$1$], [$0$], [$1$],
  [$1$], [$1$], [$1$],
))

The output column is $0, 1, 1, 1$. That is _almost_ ordinary addition — except for the very last row, where $1 + 1$ ought to be $2$, but in Boolean OR it is $1$. There is no "$2$" in a two-value world; once a statement is true, piling on more reasons does not make it "more true". So OR is addition with the rule "anything $1$ or bigger counts as $1$". This little wrinkle is the single most common trap for newcomers, so we give it a name and a warning.

#pitfall[
  Boolean OR is _not_ the same as the "either...or" of casual English, and it is _not_ ordinary addition. In everyday speech "Do you want tea or coffee?" usually means _one_ but not both — that is the _exclusive_ or, which we will meet shortly as XOR. The OR of logic and circuits is the _inclusive_ or: it is happy with one, the other, or both. And while $1 or 1 = 1$ looks like $1 + 1 = 2$ gone wrong, remember there is no value $2$ to land on. Treat $+$ in Boolean algebra as "OR", never as grade-school addition, or you will get nonsense.
]

#gomaths("Why we reuse the symbols + and ×")[
  It can feel like a dirty trick to write OR as "$+$" and AND as "$times$" when they are not really the addition and multiplication you grew up with. Mathematicians do this on purpose. When two different systems obey _the same structural rules_ — the same commutative law, the same distributive law — it is enormously useful to use the same notation, because every habit of thought you built up doing ordinary algebra transfers across for free.

  And the match is uncannily good. In ordinary arithmetic, $a times (b + c) = a times b + a times c$ (this is the distributive law). In Boolean algebra, $A and (B or C) = (A and B) or (A and C)$ — the very same shape. Multiplication distributes over addition in both worlds. We will prove the Boolean version later in this chapter. The one place the analogy _breaks_ is $1 or 1 = 1$ (ordinary addition says $2$) and, surprisingly, a _second_ distributive law that ordinary numbers do not have: in Boolean algebra, addition _also_ distributes over multiplication, $A or (B and C) = (A or B) and (A or C)$. Try that with ordinary numbers — $2 + (3 times 4) = 14$ but $(2+3) times (2+4) = 30$ — and it fails. Boolean algebra is _more_ symmetric than ordinary arithmetic, not less.
]

#history[
  *George Boole* (1815–1864) was a largely self-taught English mathematician — the son of a shoemaker, who never held a university degree yet became the first professor of mathematics at Queen's College, Cork. In _The Mathematical Analysis of Logic_ (1847) and his masterwork _An Investigation of the Laws of Thought_ (1854), he argued that the rules of reasoning itself could be written as equations and solved like algebra. His contemporary and admirer *Augustus De Morgan* (1806–1871) supplied the two transformation laws that bear his name. Both men thought they were studying the machinery of the human mind; neither could have guessed that ninety years later their "algebra of thought" would become the blueprint for every digital computer ever built. Boole died at 49 of pneumonia, after his wife — following a folk remedy — wrapped him in wet blankets to cure a chill caught walking through the rain. He never saw a single circuit.
]

== Building sentences: expressions and their tables

Single operations are not very interesting on their own. The power comes from _combining_ them, exactly as we combine $+$, $-$, and $times$ in ordinary algebra to build expressions like $3x + 2y$. A *Boolean expression* is any legal combination of variables and the operations NOT, AND, OR. For example,

$ F = (A and B) or overline(C) $

is read aloud as "$F$ equals: ($A$ and $B$), or, not-$C$." It is a recipe that, given values for $A$, $B$, and $C$, produces a single output value for $F$.

How do we know what $F$ does? We do the only thing Boolean algebra ever really asks of us: we build its truth table by trying _every_ combination of inputs. Three variables means $2 times 2 times 2 = 8$ rows. For each row we compute the inner pieces first (just like doing the brackets first in ordinary arithmetic), then combine them.

#align(center, table(columns: 6, inset: 6pt, align: center,
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([$A$], [$B$], [$C$], [$A and B$], [$overline(C)$], [$F = (A and B) or overline(C)$]),
  [$0$],[$0$],[$0$],[$0$],[$1$],[$1$],
  [$0$],[$0$],[$1$],[$0$],[$0$],[$0$],
  [$0$],[$1$],[$0$],[$0$],[$1$],[$1$],
  [$0$],[$1$],[$1$],[$0$],[$0$],[$0$],
  [$1$],[$0$],[$0$],[$0$],[$1$],[$1$],
  [$1$],[$0$],[$1$],[$0$],[$0$],[$0$],
  [$1$],[$1$],[$0$],[$1$],[$1$],[$1$],
  [$1$],[$1$],[$1$],[$1$],[$0$],[$1$],
))

Reading the final column tells the whole story of $F$: it is true in five of the eight cases. Notice how we listed the inputs in the left three columns: they count up in binary from $000$ to $111$, exactly the numbers $0$ through $7$ from Chapter 4. That is the standard, foolproof way to be _sure_ you have covered every case and missed none — let the input columns count in binary.

#gomaths("Counting the rows: why 2 to the n")[
  How many rows does a truth table have? Each variable can be $0$ or $1$ — two choices. With one variable, $2$ rows. Add a second variable and _each_ of those $2$ rows splits into $2$ (the new variable $0$ or $1$), giving $2 times 2 = 4$. A third variable doubles it again to $8$. In general, $n$ variables give

  $ 2 times 2 times dots times 2 quad (n "times") = 2^n $

  rows. This is the same "powers of two" pattern from Chapter 4, and it is the first whiff of an idea that will haunt the rest of this book: things built from independent binary choices grow _exponentially_. Ten yes/no questions already make $2^10 = 1024$ possible answers; twenty make over a million. We will count this way again when we count messages, codes, and the size of search spaces. (We meet the general rules of counting head-on in Chapter 8.)
]

#checkpoint[How many rows would the truth table for an expression in _five_ variables have? And how many distinct expressions in those five variables are even possible?][$2^5 = 32$ rows. Each of the $32$ rows can independently output $0$ or $1$, so the number of distinct truth tables — and hence distinct Boolean functions — is $2^32 = 4{,}294{,}967{,}296$, over four billion. With more variables this explodes so fast that we can never just "try them all", which is exactly why we need _laws_ to simplify expressions instead.]

Translating English into Boolean expressions is a skill worth practising, because it is how a vague human requirement becomes something a machine can check. "Let the alarm sound if a window is open AND the system is armed, but NOT if the override switch is on" becomes

$ "Alarm" = (W and S) and overline(R), $

where $W$, $S$, $R$ are $1$ when the window is open, the system is armed, and the override is on, respectively. Every "and" becomes $and$, every "or" becomes $or$, every "not" becomes a bar, and the brackets capture the grouping. Once the sentence is an expression, its truth table tells you _exactly_ when the alarm sounds, with no ambiguity and no arguing.

#aside[
  The order in which operations apply matters, just as $2 + 3 times 4$ means $2 + 12$ and not $5 times 4$. The Boolean convention mirrors arithmetic: NOT binds tightest, then AND (the "multiplication"), then OR (the "addition"). So $A or B and C$ means $A or (B and C)$, not $(A or B) and C$. When in doubt, add brackets — they are free and they prevent bugs. Real hardware-description languages and programming languages follow this same precedence, which is one more reason the arithmetic analogy earns its keep.
]

== From truth tables to silicon: logic gates

So far this is pure mathematics — symbols on a page. Shannon's leap was to notice that each Boolean operation can be _physically built_ out of switches, and that the switch's two states (current flowing / not flowing) play the roles of $1$ and $0$. A small circuit that performs one Boolean operation is called a *logic gate*, and gates are the atoms from which every processor, memory chip, and graphics card is assembled. Modern gates are made not of clacking relays but of *transistors* — tiny electronic switches with no moving parts, billions of which fit on a chip the size of a fingernail — but the logic is identical to what Shannon drew in 1937.

Each gate has a standard drawn symbol, and engineers read circuit diagrams the way musicians read scores. Here are the three fundamental gates that match our three operations.

#fig([The three fundamental logic gates. Signals flow left to right; each gate computes one Boolean operation on its inputs. The small circle (a "bubble") always means "invert the output" — that is where the NOT lives.],
  cetz.canvas({
    import cetz.draw: *
    set-style(stroke: 0.9pt)
    // ---- NOT gate (triangle + bubble) ----
    line((0,4.2),(0.7,4.2))
    line((0.7,3.85),(0.7,4.55),(1.55,4.2),close: true)
    circle((1.68,4.2), radius: 0.13)
    line((1.81,4.2),(2.5,4.2))
    content((0.45,4.85))[A]
    content((2.2,4.85))[$overline(A)$]
    content((1.1,3.3))[NOT (inverter)]

    // ---- AND gate (flat back, round front) ----
    line((0,1.9),(0.7,1.9))
    line((0,1.1),(0.7,1.1))
    line((0.7,0.8),(0.7,2.2))
    line((0.7,2.2),(1.3,2.2))
    arc((1.3,2.2), start: 90deg, stop: -90deg, radius: 0.7)
    line((0.7,0.8),(1.3,0.8))
    line((2.0,1.5),(2.6,1.5))
    content((0.42,2.55))[A]
    content((0.42,0.45))[B]
    content((2.35,1.95))[$A and B$]
    content((1.1,-0.1))[AND]

    // ---- OR gate (curved back, pointed front) ----
    line((4.0,1.9),(4.85,1.9))
    line((4.0,1.1),(4.85,1.1))
    bezier((4.7,2.2),(4.7,0.8),(5.0,1.5))
    bezier((4.7,2.2),(5.95,1.5),(5.3,2.2))
    bezier((4.7,0.8),(5.95,1.5),(5.3,0.8))
    line((5.95,1.5),(6.5,1.5))
    content((4.35,2.55))[A]
    content((4.35,0.45))[B]
    content((6.25,1.95))[$A or B$]
    content((5.1,-0.1))[OR]
  })
)

A processor is, at bottom, an unimaginably large arrangement of these gates — a modern chip holds tens of billions of transistors, wired into gates, wired into adders and comparators and memory cells. And every one of those structures is described, designed, and _verified_ using the Boolean algebra we are building right now. When an engineer wants to know whether two circuits do the same thing, they do not test every input by hand; they prove the two Boolean expressions are _equal_ using laws. Which is why the laws are the heart of the matter.

#misconception[Computers are complicated because the operations inside them are complicated.][The operations are breathtakingly _simple_ — NOT, AND, OR on single bits, and that is essentially all. The complexity is entirely in the _number_ of these trivial operations and how they are arranged, not in any single step. A computer is not a clever machine doing hard things; it is a relentless machine doing billions of childishly easy things per second. This is the deepest lesson of Boole and Shannon, and it echoes through compression: every codec in this book, however sophisticated it sounds, decomposes into a torrent of simple, exact, bit-level operations.]

=== Any truth table can be built: the sum of products

We have been going from expressions _to_ truth tables. The reverse direction is just as important and slightly magical: given _any_ truth table you like — any list of which input combinations should output $1$ — there is a mechanical recipe to write down a Boolean expression, and hence a circuit, that produces exactly it. This is the guarantee that lets a designer say "here is the behaviour I want" and get a circuit for free.

The recipe is called the *sum of products* (sometimes _disjunctive normal form_), and it works like this. Look at every row of the truth table whose output is $1$. For each such row, write a single AND-term that is true _only_ in that exact row: include each variable plain if it is $1$ in that row, or barred if it is $0$. Then OR all those terms together. Because each AND-term lights up for precisely one input combination, the OR of them lights up for precisely the combinations you wanted, and no others.

Take a concrete target: suppose we want a function $F$ of three variables that is $1$ exactly on the rows $A B C = 001$, $A B C = 110$, and $A B C = 111$, and $0$ everywhere else. Walk the recipe:

- Row $001$ ($A=0, B=0, C=1$): the term that is true only here is $overline(A) and overline(B) and C$.
- Row $110$ ($A=1, B=1, C=0$): the term is $A and B and overline(C)$.
- Row $111$ ($A=1, B=1, C=1$): the term is $A and B and C$.

OR them:

$ F = (overline(A) and overline(B) and C) or (A and B and overline(C)) or (A and B and C). $

Check any row and you will find the formula agrees with the table — for instance at $A B C = 110$ only the middle term is true, so $F = 1$, exactly as required. (We could now _simplify_ this with the laws of the next section: the last two terms share $A and B$ and the $overline(C) or C$ collapses to $1$, giving $F = (overline(A) and overline(B) and C) or (A and B)$. Same function, fewer gates — the whole game of the next section in miniature.)

#keyidea[
  *Every Boolean function can be written with only NOT, AND, OR.* The sum-of-products recipe proves it constructively: read off the $1$-rows, AND-build a term for each, OR them together. Keep this fact in your pocket: when we prove later in this chapter that a single gate type (NAND) can build _everything_, the only thing we will need is that NAND can imitate NOT, AND, and OR — because sum-of-products has already guaranteed those three suffice for any function at all. It is also the reason a designer never has to be clever to get _correct_ hardware: correctness is mechanical; cleverness is only for making it _small_.
]

== The laws of Boolean algebra

Just as ordinary algebra has rules ($a + b = b + a$, and so on) that let you rearrange expressions without changing their value, Boolean algebra has its own rulebook. Each law says "this expression and that expression always produce the same output, for every input." Because there are only finitely many inputs, we can _prove_ any such law completely, with total certainty, just by checking that both sides have the same truth table. That is a luxury ordinary algebra never has — you cannot check $a + b = b + a$ for every pair of real numbers, because there are infinitely many. In Boolean algebra, exhaustive checking is a valid, airtight proof. Let us collect the laws and prove the interesting ones.

#definition[Logical equivalence][Two Boolean expressions are *equivalent*, written with $=$, when they produce the same output value for every possible assignment of $0$/$1$ to their variables — that is, when they have identical truth tables.]

Here is the core rulebook. In each line, $A$, $B$, $C$ are any Boolean variables, $0$ is constant-false, and $1$ is constant-true.

#align(center, table(columns: (auto, 1fr, 1fr), inset: 7pt, align: (left, center, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([*Law*], [*AND form*], [*OR form*]),
  [Identity],        [$A and 1 = A$],            [$A or 0 = A$],
  [Null (domination)],[$A and 0 = 0$],           [$A or 1 = 1$],
  [Idempotent],      [$A and A = A$],            [$A or A = A$],
  [Complement],      [$A and overline(A) = 0$],  [$A or overline(A) = 1$],
  [Commutative],     [$A and B = B and A$],      [$A or B = B or A$],
  [Associative],     [$(A and B) and C = A and (B and C)$], [$(A or B) or C = A or (B or C)$],
  [Distributive],    [$A and (B or C) = (A and B) or (A and C)$], [$A or (B and C) = (A or B) and (A or C)$],
  [Absorption],      [$A and (A or B) = A$],     [$A or (A and B) = A$],
  [De Morgan],       [$overline(A and B) = overline(A) or overline(B)$], [$overline(A or B) = overline(A) and overline(B)$],
))

Stare at this table for a moment and a beautiful pattern jumps out: every law comes in a _pair_, and you can turn one into the other by swapping AND with OR _and_ swapping $0$ with $1$ throughout. This is the *principle of duality*, and it means you only ever have to remember (and prove) _half_ of Boolean algebra; the other half comes for free by swapping. It is one of the most elegant facts in all of mathematics, and it falls straight out of the symmetry we noticed earlier.

#keyidea[
  *Duality.* Take any true Boolean equation. Swap every $and$ for $or$, every $or$ for $and$, every $0$ for $1$, and every $1$ for $0$ (leave the variables and the bars alone). The result is _also_ a true equation. So "$A and 1 = A$" and "$A or 0 = A$" are two readings of one truth, and proving one proves the other by symmetry.
]

=== Proving the absorption law

Let us prove the absorption law $A or (A and B) = A$, both because it is genuinely surprising — the $B$ simply _vanishes_ — and because it shows two proof styles you will reuse forever: the brute-force truth table, and the slicker algebraic derivation.

#theorem[Absorption law][For all Boolean values $A$ and $B$, $quad A or (A and B) = A.$]

#proof[
  *Method 1 — exhaustion.* There are only $2 times 2 = 4$ cases. We compute the left-hand side in each:

  #align(center, table(columns: 4, inset: 6pt, align: center,
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
    table.header([$A$], [$B$], [$A and B$], [$A or (A and B)$]),
    [$0$],[$0$],[$0$],[$0$],
    [$0$],[$1$],[$0$],[$0$],
    [$1$],[$0$],[$0$],[$1$],
    [$1$],[$1$],[$1$],[$1$],
  ))

  The final column is $0, 0, 1, 1$ — identical to the $A$ column. Since the two sides agree in every one of the only four possible cases, they are equal. #h(1fr)
]

#proof[
  *Method 2 — algebra.* We chain together laws we have already accepted, justifying each step:
  $
  A or (A and B) &= (A and 1) or (A and B) quad &&"(identity law: " A = A and 1")" \
                 &= A and (1 or B)            quad &&"(distributive law, factoring out " A")" \
                 &= A and 1                   quad &&"(null law: " 1 or B = 1")" \
                 &= A.                         quad &&"(identity law again)"
  $
  Both methods reach the same conclusion. The truth table is unarguable but blind; the algebra explains _why_ the law holds — $B$ is absorbed because "$A$ or anything-times-$A$" never escapes the orbit of $A$ itself.
]

This pairing of styles is worth internalising. When you just need to be _sure_, a truth table is the safest tool in the world — it cannot lie, because it checks everything. When you need to _simplify_ a big expression down to something a circuit can implement cheaply, you reach for the algebraic laws. Real chip-design and circuit-verification software does both: it uses the algebra to simplify and the exhaustive check (in clever, compressed forms) to verify.

== De Morgan's laws: the most useful identity you'll ever learn

Of all the laws in the table, the pair named after Augustus De Morgan earns its own section, because a working engineer reaches for it more than any other. In words:

#keyidea[
  *De Morgan's laws.* "NOT (A AND B)" equals "(NOT A) OR (NOT B)", and "NOT (A OR B)" equals "(NOT A) AND (NOT B)". In symbols:
  $ overline(A and B) = overline(A) or overline(B), quad quad overline(A or B) = overline(A) and overline(B). $
  The plain-English rule of thumb: *to push a NOT through a bracket, flip every AND to OR (and every OR to AND), and negate each piece.* The bar "breaks", and AND/OR swap underneath it.
]

This matches intuition once you say it aloud. "It is _not_ the case that (it is raining AND it is cold)" means "either it isn't raining, _or_ it isn't cold" (at least one of the two conditions failed). And "it is _not_ the case that (I have tea OR coffee)" means "I have _neither_ tea _nor_ coffee" — I lack tea AND I lack coffee. The negation turns the "and" into an "or" and vice versa. Let us prove the first law the foolproof way.

#theorem[De Morgan's first law][For all Boolean $A, B$: $quad overline(A and B) = overline(A) or overline(B).$]

#proof[
  We tabulate both sides over all four input combinations and check they agree column-for-column.

  #align(center, table(columns: 7, inset: 6pt, align: center,
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
    table.header([$A$], [$B$], [$A and B$], [$overline(A and B)$], [$overline(A)$], [$overline(B)$], [$overline(A) or overline(B)$]),
    [$0$],[$0$],[$0$],[$1$],[$1$],[$1$],[$1$],
    [$0$],[$1$],[$0$],[$1$],[$1$],[$0$],[$1$],
    [$1$],[$0$],[$0$],[$1$],[$0$],[$1$],[$1$],
    [$1$],[$1$],[$1$],[$0$],[$0$],[$0$],[$0$],
  ))

  The fourth column ($overline(A and B)$) and the seventh column ($overline(A) or overline(B)$) are identical: $1, 1, 1, 0$. The two expressions agree on every input, so they are equal. The second law follows immediately by duality (or by an identical four-row table). #h(1fr)
]

Why does this matter so much in practice? Two reasons that recur throughout compression and computing.

First, *De Morgan lets you trade gate types.* If your hardware has plenty of one kind of gate and a shortage of another, De Morgan's laws let you rewrite a circuit to use what you have. We are about to see the most dramatic version of this: that a single gate type, NAND, can be made to do _everything_.

Second, *De Morgan is how you negate a complicated condition correctly* — a thing programmers get wrong constantly. The opposite of "the file is open AND not empty" is _not_ "the file is closed AND empty"; it is "the file is closed OR empty". Negating a compound condition flips the connective. Get this wrong in a decompressor's bounds-check and you have a security bug; get it right and you sleep at night.

#gopython("Booleans, and/or/not, and the operators & | ^ ~")[
  Python has Boolean values written `True` and `False` (capitalised). The logical operators read like English: `and`, `or`, `not`.

  ```python
  A = True
  B = False
  print(A and B)   # False — both must be True
  print(A or B)    # True  — at least one is True
  print(not A)     # False — the flip
  ```

  Python also lets you treat `True`/`False` as the numbers `1`/`0`, which makes the "AND is multiply, OR is add-then-clamp" analogy literal:

  ```python
  print(int(True) + int(True))   # 2, ordinary addition
  print(True & True)             # True — bitwise AND on single bits
  ```

  Those last symbols — `&` (AND), `|` (OR), `^` (XOR), `~` (NOT) — are the *bitwise* operators. Instead of acting on one True/False, they act on _every bit of an integer at once, in parallel_. We rely on this heavily when `tinyzip` packs bits into bytes. For example `0b1100 & 0b1010` computes AND on each of the four bit-positions, giving `0b1000`:

  ```python
  print(bin(0b1100 & 0b1010))   # 0b1000  (AND, position by position)
  print(bin(0b1100 | 0b1010))   # 0b1110  (OR)
  print(bin(0b1100 ^ 0b1010))   # 0b0110  (XOR — differing bits)
  ```

  Do not confuse the word-operators (`and`, `or`, `not`, which work on whole True/False values) with the symbol-operators (`&`, `|`, `^`, `~`, which work bit-by-bit on integers). Chapter 4 introduced `0b...` binary literals and `bin()`; here they let us _see_ Boolean algebra happening across all bits simultaneously.
]

#gopython("Comprehensions, generator expressions, and enumerate")[
  Chapter 4 showed the `for` loop, which walks through a collection one item at a time. Python has a compact shorthand for "loop over a collection and collect a value from each item" called a *comprehension*. Instead of

  ```python
  squares = []
  for n in range(4):
      squares.append(n * n)     # squares becomes [0, 1, 4, 9]
  ```

  you write the same thing on one line, reading almost like English — "`n*n` for each `n` in `range(4)`":

  ```python
  squares = [n * n for n in range(4)]   # [0, 1, 4, 9]
  ```

  (`range(4)` is the numbers `0, 1, 2, 3`, from Chapter 4.) Drop the square brackets and you get a *generator expression*, which produces the same values one at a time without building a whole list in memory — handy for feeding a function like `bytes(...)`, `sum(...)`, or `all(...)`. The function `all(...)` returns `True` only if _every_ value it receives is true (a software echo of the AND we just studied — AND of a whole stream of conditions):

  ```python
  print(all(x > 0 for x in [3, 1, 4]))   # True  — every item is positive
  ```

  Finally, `enumerate(data)` walks a collection while also handing you a running position number: it yields pairs `(0, first_item), (1, second_item), …`. Writing `for i, d in enumerate(data)` unpacks each pair into a position `i` and the item `d` at once. We use all three of these next, and constantly throughout `tinyzip`.
]

#tryit[
  `tinyzip`, the compressor we build across this book, does not get its first real code until the Python-primer chapters (15–17) and Chapter 24's Huffman coder — so this is not yet a numbered project step. But we can still cement bit-level Boolean operations with a tiny, testable helper that foreshadows the bit-twiddling to come. A *mask* is an integer used to pick out specific bits with AND. Clearing the low `k` bits of a value, then checking the result, is a one-liner we will reuse when aligning the bit-buffer to byte boundaries.

  ```python
  def clear_low_bits(value: int, k: int) -> int:
      """Set the lowest k bits of `value` to 0, leaving higher bits intact."""
      mask = ~((1 << k) - 1)        # ...1111000  (k zeros at the bottom)
      return value & mask

  # De Morgan, made executable: ~(a & b) must equal (~a) | (~b)
  # for every pair of bytes. We TEST a law instead of trusting it.
  def demorgan_holds(a: int, b: int) -> bool:
      mask = 0xFF                                  # work within one byte
      left  = (~(a & b)) & mask
      right = ((~a) | (~b)) & mask
      return left == right

  assert clear_low_bits(0b1011_0111, 4) == 0b1011_0000
  assert all(demorgan_holds(a, b) for a in range(256) for b in range(256))
  print("Boolean foundations verified for tinyzip.")
  ```

  The second `assert` exhaustively checks De Morgan's first law across all $256 times 256 = 65{,}536$ byte pairs — the same brute-force proof we did by hand, now done by the machine in a blink. This pattern, _encode a law as a test and verify it exhaustively_, is exactly how real codec authors guard against subtle bit-twiddling bugs.
]

== One gate to rule them all: NAND and NOR

We have been treating NOT, AND, OR as three separate primitives. But notice we can _combine_ them. Two especially important combinations are AND-then-NOT and OR-then-NOT:

- *NAND* ("not-and") outputs the opposite of AND: it is $1$ except when both inputs are $1$. Written $overline(A and B)$.
- *NOR* ("not-or") outputs the opposite of OR: it is $1$ only when both inputs are $0$. Written $overline(A or B)$.

#align(center, grid(columns: 2, column-gutter: 24pt,
  table(columns: 3, inset: 6pt, align: center,
    fill: (_, row) => if row == 0 { c-warn.lighten(85%) },
    table.header([$A$], [$B$], [$A "NAND" B$]),
    [$0$],[$0$],[$1$], [$0$],[$1$],[$1$], [$1$],[$0$],[$1$], [$1$],[$1$],[$0$]),
  table(columns: 3, inset: 6pt, align: center,
    fill: (_, row) => if row == 0 { c-warn.lighten(85%) },
    table.header([$A$], [$B$], [$A "NOR" B$]),
    [$0$],[$0$],[$1$], [$0$],[$1$],[$0$], [$1$],[$0$],[$0$], [$1$],[$1$],[$0$]),
))

These look like mere conveniences, but they hide a stunning fact: *NAND all by itself can build every possible logic circuit.* You do not need separate AND, OR, and NOT gates at all — give an engineer a bucket of identical NAND gates and they can wire up anything a computer can compute. The same is true of NOR alone. A single, repeated, dirt-simple gate is _universal_. This is why real chips are often built mostly from one kind of gate: manufacturing one component a billion times is far cheaper than juggling three.

#theorem[Functional completeness of NAND][Every Boolean function can be expressed using only NAND operations.]

#proof[
  It is enough to build NOT, AND, and OR out of NAND, because we already proved (with the sum-of-products construction earlier in this chapter) that those three can express any Boolean function whatsoever. So if NAND can imitate all three, NAND can imitate anything. We build each:

  *NOT* from NAND: feed the same input into both holes of a NAND.
  $ A "NAND" A = overline(A and A) = overline(A) quad ("idempotent law:" A and A = A). $
  So a NAND with its inputs tied together is an inverter.

  *AND* from NAND: NAND is "AND then NOT", so NOT-ing it again undoes the inversion. Using the NOT we just built,
  $ (A "NAND" B) "NAND" (A "NAND" B) = overline(overline(A and B)) = A and B. $

  *OR* from NAND: by De Morgan, $A or B = overline(overline(A) and overline(B)) = overline(A) "NAND" overline(B)$. So invert each input with a NAND, then NAND the two results:
  $ (A "NAND" A) "NAND" (B "NAND" B) = overline(A) "NAND" overline(B) = overline(overline(A) and overline(B)) = A or B. $

  Having reconstructed NOT, AND, and OR purely from NAND gates, and knowing those three suffice for every Boolean function, we conclude NAND alone is functionally complete. The identical argument with the dual law $A and B = overline(overline(A) or overline(B))$ proves NOR is complete too. #h(1fr)
]

#fig([NOT built from a single NAND gate (inputs tied together), and AND built from two NANDs (a NAND followed by an inverting NAND). Every other gate follows the same way. The bubble on the output is the NAND's built-in inversion.],
  cetz.canvas({
    import cetz.draw: *
    set-style(stroke: 0.9pt)
    let nand(x, y, lbl) = {
      line((x, y + 0.4), (x + 0.6, y + 0.4))
      arc((x + 0.6, y + 0.4), start: 90deg, stop: -90deg, radius: 0.4)
      line((x, y - 0.4), (x, y + 0.4))
      line((x, y - 0.4), (x + 0.6, y - 0.4))
      circle((x + 1.13, y), radius: 0.11)
    }
    // NOT from one NAND
    line((0,2.0),(0.4,2.2)); line((0,1.6),(0.4,1.4))
    line((0.2,2.2),(0.2,1.4))   // tie inputs
    line((0.2,2.2),(0.4,2.2)); line((0.2,1.4),(0.4,1.4))
    nand(0.4,1.8,"")
    line((1.65,1.8),(2.2,1.8))
    content((0.0,1.8))[A]
    content((2.45,1.8))[$overline(A)$]
    content((1.1,0.85))[NOT = NAND(A,A)]

    // AND from two NANDs
    line((4.0,2.2),(4.4,2.2)); line((4.0,1.4),(4.4,1.4))
    nand(4.4,1.8,"")
    line((5.65,1.8),(6.0,1.8))
    line((5.85,1.95),(5.85,1.65))   // tie inputs of 2nd
    line((5.85,1.95),(6.0,1.95)); line((5.85,1.65),(6.0,1.65))
    nand(6.0,1.8,"")
    line((7.25,1.8),(7.7,1.8))
    content((3.7,2.2))[A]; content((3.7,1.4))[B]
    content((8.0,1.8))[$A and B$]
    content((5.8,0.85))[AND = NAND then invert]
  })
)

#aside[
  The Apollo Guidance Computer that took astronauts to the Moon in 1969 was built almost entirely from a single part: about $5{,}600$ identical three-input NOR gates, packed into integrated circuits. NASA chose one gate type on purpose — fewer distinct parts meant fewer ways to fail, and every chip could be tested the same way. Boole's "algebra of thought", routed through Shannon's switches, quite literally flew to the Moon as a pile of identical NORs.
]

== Exclusive-or: the compressor's favourite gate

There is one more operation we must single out, because it appears _everywhere_ in compression, cryptography, and error-correction: *exclusive-or*, written *XOR* and denoted $A xor B$ (the circled-plus symbol $xor$, read "ex-or"). XOR outputs $1$ when the inputs are _different_, and $0$ when they are the _same_. It is the "one or the other, but not both" that ordinary English usually means by "or".

#align(center, table(columns: 4, inset: 7pt, align: center,
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([$A$], [$B$], [$A xor B$], [in words]),
  [$0$],[$0$],[$0$],[same → 0],
  [$0$],[$1$],[$1$],[differ → 1],
  [$1$],[$0$],[$1$],[differ → 1],
  [$1$],[$1$],[$0$],[same → 0],
))

In terms of our basic operations, $A xor B = (A and overline(B)) or (overline(A) and B)$ — "($A$ but not $B$) or (not $A$ but $B$)", which is precisely "exactly one of them". But the reason engineers love XOR is a cluster of magical-looking properties that fall straight out of its truth table:

- *Self-inverse:* $A xor A = 0$. A value XOR-ed with itself cancels to zero.
- *Identity:* $A xor 0 = A$. XOR-ing with zero changes nothing.
- *Reversible:* if $C = A xor B$, then $C xor B = A$ _and_ $C xor A = B$. XOR is its own undo button.

That last property is the crown jewel. Because XOR-ing twice by the same value returns the original, XOR is the simplest possible _reversible_ transformation — and reversibility is the absolute, non-negotiable requirement of all lossless compression. If a compressor scrambles your data with some operation, it had better be able to unscramble it _exactly_; XOR offers a whole family of such perfectly-reversible scrambles for free.

#theorem[XOR is self-inverse][For all Boolean $A$ and $B$: if $C = A xor B$ then $C xor B = A$.]

#proof[
  Substitute and use associativity of XOR plus the two facts $B xor B = 0$ and $X xor 0 = X$:
  $ C xor B = (A xor B) xor B = A xor (B xor B) = A xor 0 = A. $
  Each step is justified: regrouping by associativity, then the self-inverse law collapses $B xor B$ to $0$, then the identity law removes it. The same chain shows $C xor A = B$. #h(1fr)
]

Where does this show up in real compression? In more places than you would believe:

- *PNG image filters.* Before PNG hands a row of pixels to its DEFLATE compressor (Chapter 30), it often replaces each pixel with the _difference_ from a neighbouring pixel. On the encode side that difference is computed; on the decode side it is added back. The very same "transform now, exactly undo later" pattern that XOR embodies is the soul of every reversible filter, and PNG's "Paeth" and "Sub" filters are built on it. Smooth images become long runs of small numbers — which compress beautifully.
- *Delta and XOR encoding* of time series and columnar data (Chapters 67 and 68). When successive values barely change, storing $x_i xor x_(i-1)$ turns a stream of big similar numbers into a stream of mostly-zero bits, and zeros are cheap to compress.
- *Checksums and parity* (next section, and Chapter 72's error-correction boundary). The parity of a block of bits is just all of them XOR-ed together.
- *The one-time pad*, the only provably unbreakable cipher, is nothing but message XOR key. Encryption and compression are cousins; both reshape redundancy, and both lean on reversible bit operations.

#gopython("XOR in Python, and round-tripping bytes")[
  Python's XOR operator is the caret `^`. On single bits it matches the truth table; on whole integers it XORs every bit position in parallel, just like `&` and `|`.

  ```python
  print(5 ^ 3)            # 6   (0b101 ^ 0b011 = 0b110)
  print(5 ^ 3 ^ 3)        # 5   — XOR-ing by 3 twice cancels out
  ```

  That cancellation is the reversibility we proved. Here it round-trips a whole message through a repeating key — a toy cipher that also illustrates the exact-undo property every lossless codec needs:

  ```python
  def xor_bytes(data: bytes, key: bytes) -> bytes:
      return bytes(d ^ key[i % len(key)] for i, d in enumerate(data))

  msg = b"compression"
  key = b"\x2a"                       # a single byte, repeated
  scrambled = xor_bytes(msg, key)
  recovered = xor_bytes(scrambled, key)   # XOR again with the SAME key
  assert recovered == msg                 # perfect round-trip
  print(scrambled, "->", recovered)
  ```

  The `i % len(key)` cycles through the key (the `%` is remainder, from Chapter 4); `enumerate` hands us each byte together with its position `i`. The crucial line is that XOR-ing a second time with the same key gives the message back _exactly_ — bit-for-bit, no loss. That guarantee is what separates a compressor you can trust from one you cannot.
]

== Parity: Boolean algebra catches a flipped bit

XOR-ing _many_ bits together computes their *parity* — whether the number of $1$s among them is even or odd. The parity of bits $b_1, b_2, dots, b_n$ is $b_1 xor b_2 xor dots xor b_n$, which is $0$ when an even number of them are $1$, and $1$ when an odd number are. This single extra bit is the cheapest error-detection scheme ever invented, and it guarded telegraphs, tape drives, and memory chips for decades.

The idea: append to your data one extra *parity bit*, chosen so the _total_ number of $1$s (data plus parity) is always even. If a single bit gets corrupted in transit — flipped from $0$ to $1$ or back — the count of $1$s becomes odd, the parity check fails, and the receiver _knows_ something broke (though not which bit). It works because flipping any one bit flips the overall parity, and XOR captures exactly that.

#align(center, table(columns: 3, inset: 7pt, align: center,
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) },
  table.header([Data bits], [Parity bit ($=$ XOR of data)], [Transmitted (always even \# of 1s)]),
  [`1011`], [$1 xor 0 xor 1 xor 1 = 1$], [`1011` `1`],
  [`1100`], [$1 xor 1 xor 0 xor 0 = 0$], [`1100` `0`],
  [`0000`], [$0$], [`0000` `0`],
))

Take the first row: data `1011` has three $1$s (odd), so the parity bit is $1$, making four $1$s total (even). If the receiver counts an _odd_ number of $1$s, a bit flipped. Compression and error-correction sit on opposite banks of the same river — compression _removes_ redundancy to shrink data, error-correction _adds_ carefully-shaped redundancy to survive damage — and Chapter 72 explores exactly where that boundary lies. Both, you now see, are built from the very same Boolean atoms. The XOR that powers parity here is the same XOR that powers PNG's filters and the one-time pad; one humble gate, reused everywhere.

#checkpoint[A sender uses even parity. You receive the eight bits `0110_1101` where the last bit is the parity bit. Was the message corrupted (assuming at most one bit flipped)?][The seven data bits `0110110` contain four $1$s; the received parity bit is `1`. Total $1$s including the parity bit: $4 + 1 = 5$, which is _odd_. Even parity demands an even total, so the check fails — at least one bit was corrupted in transit. (Parity tells you _that_ an odd number of bits flipped, never _which_; catching and fixing the error needs the richer codes of Chapter 72.)]

== Putting it together: Boolean simplification in action

Let us end the body with a worked example that uses several laws at once, because simplification is the skill that turns Boolean algebra from a curiosity into a tool. Real circuit designers and compiler writers do exactly this: take a sprawling expression and grind it down to the smallest equivalent one, because fewer operations mean fewer gates, less power, and faster code.

#definition[Tautology and contradiction][An expression that is _always_ $1$, for every input, is a *tautology* (it equals the constant $1$). One that is _always_ $0$ is a *contradiction* (it equals $0$). Simplification often reveals that a fearsome-looking expression is secretly one of these.]

Suppose we are handed the condition
$ F = (A and B) or (A and overline(B)) or (overline(A) and B) $
and asked to wire it up with as few gates as possible. We simplify step by step, naming every law:

$
F &= (A and B) or (A and overline(B)) or (overline(A) and B) \
  &= [A and (B or overline(B))] or (overline(A) and B) quad &&"(distributive, factor " A "from first two terms)" \
  &= [A and 1] or (overline(A) and B)                  quad &&"(complement law: " B or overline(B) = 1")" \
  &= A or (overline(A) and B)                            quad &&"(identity law: " A and 1 = A")" \
  &= (A or overline(A)) and (A or B)                    quad &&"(distributive, the OR-form)" \
  &= 1 and (A or B)                                      quad &&"(complement law: " A or overline(A) = 1")" \
  &= A or B.                                             quad &&"(identity law: " 1 and X = X")"
$

A three-term, five-operation monster collapses into a single OR gate. The original would have needed several ANDs, a NOT, and two ORs; the simplified version needs _one gate_. That is not a cosmetic win — across a chip with billions of such expressions, or across a decompression inner loop run trillions of times, it is the difference between a product that ships and one that doesn't. And we reached it with nothing but the laws in our table, each step provable by a four-row truth check if we ever doubted it.

#note[
  Doing this by hand is fine for three or four variables. Beyond that, engineers reach for systematic tools — *Karnaugh maps* for a handful of variables, and the *Quine–McCluskey* algorithm or modern *binary decision diagrams* (BDDs) for many. We will not need those tools in this book, but it is worth knowing they exist and that they are pure, mechanical Boolean algebra: the same laws you just used, applied by a machine. The deep point stands — every one of them rests on the handful of identities in our little table.
]

#takeaways((
  [Boolean algebra is ordinary algebra restricted to two values, $0$ (false/off) and $1$ (true/on) — the very bits of Chapter 4, now able to _compute_, not just store.],
  [Three operations suffice for everything: NOT (flip), AND (both, like multiply), OR (at least one, like add-then-clamp). Any operation is fully described by its _truth table_, and an $n$-variable table has $2^n$ rows.],
  [The laws of Boolean algebra (identity, null, complement, commutative, associative, distributive, absorption, De Morgan) come in dual pairs — swap AND↔OR and 0↔1 — so you need remember only half, and any law is provable by exhaustive truth table.],
  [De Morgan's laws — $overline(A and B) = overline(A) or overline(B)$ — are the everyday workhorse: they push a NOT through a bracket by flipping AND↔OR, and they let you correctly negate compound conditions in code.],
  [A single gate type, NAND (or NOR), is _functionally complete_: it can build every possible circuit. Computers are vast arrangements of trivially-simple identical parts.],
  [XOR (different → 1) is reversible — XOR-ing twice by the same value restores the original — which makes it the beating heart of reversible filters (PNG), delta/XOR encoding, parity error-detection, and the one-time pad. The exact "transform then perfectly undo" property is the soul of all lossless compression.],
))

== Exercises

#exercise("5.1", 1)[
  Write the truth table for $F = overline(A) or B$ (this expression is the logician's "if $A$ then $B$"). In how many of the four rows is $F$ true? Describe in one plain-English sentence when $F$ is _false_.
]
#solution("5.1")[
  $F = overline(A) or B$ over all inputs:
  #align(center, table(columns: 4, inset: 5pt, align: center,
    table.header([$A$],[$B$],[$overline(A)$],[$F$]),
    [0],[0],[1],[1], [0],[1],[1],[1], [1],[0],[0],[0], [1],[1],[0],[1]))
  $F$ is true in three of the four rows. It is false in exactly one case: when $A = 1$ and $B = 0$ — i.e. "if $A$ then $B$" is broken only when $A$ holds but $B$ fails to follow.
]

#exercise("5.2", 1)[
  Using AND, OR, NOT and brackets, translate into a Boolean expression: "The download starts if the user is logged in and either has a subscription or a free trial that has not expired." Use $L$ (logged in), $S$ (subscription), $T$ (free trial active).
]
#solution("5.2")[
  $"Download" = L and (S or T)$. The "and" after "logged in" is the outer AND; the "either...or" is the inner OR. ("Free trial that has not expired" is captured by letting $T = 1$ mean the trial is _active_; if instead you had a variable $E$ = "expired", you would write $T and overline(E)$ in its place.)
]

#exercise("5.3", 2)[
  Prove the absorption law's OR-form, $A and (A or B) = A$, two ways: (a) with a full truth table, and (b) algebraically using the laws in the chapter's table. Name each law you use in part (b).
]
#solution("5.3")[
  *(a)* Truth table over $A, B$: compute $A or B$ then $A and (A or B)$. Rows give final column $0,0,1,1$, matching $A$.
  #align(center, table(columns: 4, inset: 5pt, align: center,
    table.header([$A$],[$B$],[$A or B$],[$A and (A or B)$]),
    [0],[0],[0],[0], [0],[1],[1],[0], [1],[0],[1],[1], [1],[1],[1],[1]))
  *(b)* $A and (A or B) = (A or 0) and (A or B)$ (identity, $A = A or 0$) $= A or (0 and B)$ (distributive, OR-form, factoring $A$) $= A or 0$ (null law, $0 and B = 0$) $= A$ (identity). This is the exact dual of the AND-form proved in the chapter, as duality promised.
]

#exercise("5.4", 2)[
  Use De Morgan's laws to rewrite $overline((A or B) and C)$ so that no bar covers more than a single variable. Show each step.
]
#solution("5.4")[
  Push the outer bar through the AND first: $overline((A or B) and C) = overline((A or B)) or overline(C)$ (De Morgan, AND-form). Then push the remaining bar through the inner OR: $overline(A or B) = overline(A) and overline(B)$ (De Morgan, OR-form). Combining: $overline((A or B) and C) = (overline(A) and overline(B)) or overline(C)$. Every bar now sits over a single variable.
]

#exercise("5.5", 2)[
  Build the *OR* operation using only NAND gates, and verify your construction with a truth table. (Hint: $A or B = overline(A) "NAND" overline(B)$, and you already know how to make NOT from NAND.)
]
#solution("5.5")[
  Three NANDs: invert $A$ with NAND($A,A$), invert $B$ with NAND($B,B$), then NAND those two results. The final gate computes $overline(overline(A)) and overline(overline(B))$ negated — i.e. $overline(overline(A) and overline(B))$, which by De Morgan is $A or B$.
  #align(center, table(columns: 5, inset: 5pt, align: center,
    table.header([$A$],[$B$],[$overline(A)$],[$overline(B)$],[$overline(overline(A) and overline(B))$]),
    [0],[0],[1],[1],[0], [0],[1],[1],[0],[1], [1],[0],[0],[1],[1], [1],[1],[0],[0],[1]))
  The last column $0,1,1,1$ is exactly OR. Verified.
]

#exercise("5.6", 1)[
  Compute the parity (even/odd) bit needed to give _even_ parity for the data `1101011`. Then, treating parity as repeated XOR, confirm your answer equals $1 xor 1 xor 0 xor 1 xor 0 xor 1 xor 1$.
]
#solution("5.6")[
  `1101011` has five $1$s — odd — so the parity bit must be $1$ to make the total ($5 + 1 = 6$) even. As XOR: $1 xor 1 = 0$, $xor 0 = 0$, $xor 1 = 1$, $xor 0 = 1$, $xor 1 = 0$, $xor 1 = 1$. The running XOR is $1$, matching the parity bit. (XOR-ing all bits yields $1$ exactly when there is an odd number of $1$s.)
]

#exercise("5.7", 2)[
  Prove that XOR is *associative*: $(A xor B) xor C = A xor (B xor C)$ for all Boolean $A, B, C$. (A full eight-row truth table is the cleanest route.)
]
#solution("5.7")[
  Both sides equal $1$ exactly when an _odd_ number of $A, B, C$ are $1$. Tabulating all eight rows: the result is $1$ for inputs $001, 010, 100, 111$ (one or three ones) and $0$ otherwise — and this holds whichever way the brackets group, since "odd count of ones" does not care about grouping. The two columns match in all eight rows, so XOR is associative. This is why writing $A xor B xor C$ without brackets is unambiguous, and why parity-of-many-bits is well defined.
]

#exercise("5.8", 3)[
  A *half-adder* adds two single bits $A$ and $B$, producing a _sum_ bit $S$ and a _carry_ bit $C$ (because $1 + 1 = 10$ in binary, from Chapter 4). Work out the truth table for $S$ and $C$, then express each as a Boolean formula in $A$ and $B$. What two gates does a half-adder need?
]
#solution("5.8")[
  Binary single-bit addition: $0+0=00$, $0+1=01$, $1+0=01$, $1+1=10$.
  #align(center, table(columns: 4, inset: 5pt, align: center,
    table.header([$A$],[$B$],[$C$ (carry)],[$S$ (sum)]),
    [0],[0],[0],[0], [0],[1],[0],[1], [1],[0],[0],[1], [1],[1],[1],[0]))
  The sum column $0,1,1,0$ is exactly XOR: $S = A xor B$. The carry column $0,0,0,1$ is exactly AND: $C = A and B$. So a half-adder is one XOR gate (sum) plus one AND gate (carry). This is the literal Boolean seed of all computer arithmetic — chain half-adders into full-adders and you can add any two binary numbers, exactly as Shannon foresaw in 1937.
]

#exercise("5.9", 3)[
  Simplify $F = (A or B) and (A or overline(B)) and (overline(A) or B)$ to as few operations as possible, naming each law. (Compare with the worked AND/OR example in the chapter — this is its dual.)
]
#solution("5.9")[
  $F = [(A or B) and (A or overline(B))] and (overline(A) or B)$. The first bracket: $(A or B) and (A or overline(B)) = A or (B and overline(B))$ (distributive, OR-form) $= A or 0$ (complement) $= A$ (identity). So $F = A and (overline(A) or B) = (A and overline(A)) or (A and B)$ (distributive) $= 0 or (A and B)$ (complement) $= A and B$ (identity). The three-clause expression reduces to a single AND, $F = A and B$.
]

#exercise("5.10", 3)[
  *(Reversibility and compression.)* A "filter" $f$ takes a byte and returns a byte. For a compressor to use $f$ as a lossless pre-transform, $f$ must be *invertible*: there must be an exact undo. (i) Explain why $g(x) = x xor 42$ is invertible and give its inverse. (ii) Explain why $h(x) = x and 42$ is _not_ invertible, by exhibiting two inputs that collide. (iii) In one sentence, relate this to why lossless codecs may XOR or subtract neighbours but must never simply AND data away.
]
#solution("5.10")[
  *(i)* $g(x) = x xor 42$ is its own inverse: $g(g(x)) = (x xor 42) xor 42 = x xor (42 xor 42) = x xor 0 = x$ (self-inverse and identity laws). So applying $g$ twice recovers $x$ — invertible, inverse is $g$ itself.
  *(ii)* $h(x) = x and 42$ forces every bit where $42 = #raw("0b00101010")$ has a $0$ to become $0$, destroying that information. For instance $h(0) = 0$ and $h(16) = 16 and 42 = 0$ as well (the bit worth $16$ is a $0$ in $42 = 32 + 8 + 2$): two different inputs, $0$ and $16$, map to the same output $0$. With a collision there is no way to undo $h$ — it is not invertible.
  *(iii)* Lossless compression must perfectly reconstruct the original, so its transforms must be _reversible_ (bijections like XOR or add/subtract-neighbour); an operation like AND that can map distinct inputs to the same output throws information away irretrievably and can only belong in _lossy_ compression.
]

== Further reading

- Claude E. Shannon (1938), _A Symbolic Analysis of Relay and Switching Circuits_, Transactions of the AIEE 57(12) — the master's thesis that married Boolean algebra to electrical switching and launched digital design. #link("https://dspace.mit.edu/handle/1721.1/11173")[MIT DSpace].
- George Boole (1854), _An Investigation of the Laws of Thought_ — the founding text, surprisingly readable, freely available. #link("https://www.gutenberg.org/ebooks/15114")[Project Gutenberg].
- Augustus De Morgan (1847), _Formal Logic_ — where the transformation laws first appear in print.
- For the engineering side, any introductory digital-logic text (e.g. Harris & Harris, _Digital Design and Computer Architecture_) develops gates, NAND-completeness, and Karnaugh-map simplification at length.

#bridge[
  We can now make bits _compute_ — flip them, combine them, and reason about them with airtight certainty. But every truth table, every $2^n$, every "number of distinct functions" answer leaned on a quiet idea we used without defining: _collecting things and counting them_. To talk precisely about alphabets, codes, and "the set of all messages of length $n$", we need the grammar of mathematics itself — *sets*, the functions that map between them, and the special functions (one-to-one, onto) that a _code_ must be to be decodable. Chapter 6 builds that grammar from scratch, and in doing so quietly lays the foundation for why some codes can be undone and others cannot — the question Exercise 5.10 only began to answer.
]
