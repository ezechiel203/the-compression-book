#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Exponents, Logarithms, and Growth

#epigraph[
  "Seeing there is nothing that is so troublesome to mathematical practice ... than the multiplications, divisions, square and cubical extractions of great numbers ... I began therefore to consider ... by what certain and ready art I might remove those hindrances."
][John Napier, _Mirifici Logarithmorum Canonis Descriptio_ (1614)]

Here is a number so large you cannot picture it, and a trick so small it fits on a postcard. Fold a sheet of paper in half. Fold it again. Each fold doubles the thickness. Ordinary paper is about a tenth of a millimetre thick, so after one fold you have two layers, after two folds four, after ten folds a thousand-odd layers — a stack as tall as a coffee mug. Keep going, in your imagination, because you cannot in your hands. After forty-two folds the stack would reach the Moon. Not a metaphor; the actual arithmetic. Doubling forty-two times multiplies your tenth of a millimetre by $2^42$, which is about four million million, and four million million tenths of a millimetre is roughly the distance to the Moon.

That is *exponential growth*, and it is the most counter-intuitive force in mathematics. It is also, as it happens, the exact shape of the thing this whole book is about. When we say a file has been "compressed to four thousand bytes," we are really making a claim about a number of *possibilities* — and the number of possibilities a string of switches can name grows by doubling, fold after fold, bit after bit. To talk about that number sensibly we need its mirror image: a tool that takes a colossal count and hands back the small, friendly number of *foldings* it took to get there. That mirror is the *logarithm*, and a logarithm is, quite literally, the answer to the question "how many times did you double?"

A bit — the atom of all compression — is a logarithm. This chapter earns that sentence. By the end of it the strange formula at the heart of information theory, $-log_2 p$, will not be a wall of symbols but an old friend: the price, in foldings, of a surprise.

#recap[
  In Chapter 4 we built the number systems — binary, octal, hex — and met *exponents* in passing: $327 = 3 times 10^2 + 2 times 10^1 + 7 times 10^0$, and we noted that $n$ bits name $2^n$ different values, promising to return to that doubling rule "in full, in Chapter 7." This is Chapter 7. In Chapter 6 we learned the language of *functions* — a machine that takes an input and returns exactly one output — and of *bijections*, the perfectly reversible pairings that make a code decodable. Logarithms and exponentials are the two functions this book leans on hardest, and they are bijections of each other: each one perfectly undoes the other. We now build both from scratch.
]

#objectives((
  [Explain what an *exponent* is, compute powers by hand, and recite and *use* the three exponent rules (product, quotient, power-of-a-power).],
  [Define a *logarithm* as the inverse of an exponent — "the exponent you were looking for" — and read $log_2$, $log_10$, and $ln$ fluently.],
  [Use the single most useful property in the book: logarithms turn *multiplication into addition*, and explain why that is what makes them a tool for measuring information.],
  [Convert a logarithm from any base to any other with the change-of-base formula, and prove it.],
  [Tell *linear*, *polynomial*, and *exponential* growth apart on sight, and explain why exponential growth defeats every brute-force compressor.],
  [Explain, and justify from scratch, the book's keystone equation: a single bit is $log_2 2 = 1$, and the information in an event of probability $p$ is $-log_2 p$ bits.],
  [Prove three load-bearing facts: the product rule for exponents, the multiplication-into-addition law for logs, and the change-of-base formula.],
))

== Doubling, and the tyranny of small numbers on top

Start where the paper-folding started: with *repeated multiplication*. We met the shorthand in Chapter 4, but let us pin it down with the care it deserves, because everything in this chapter grows from this one seed.

When you multiply a number by itself again and again, writing out all the copies becomes silly fast. $2 times 2 times 2 times 2 times 2 times 2 times 2 times 2 times 2 times 2$ is ten twos; nobody wants to count them by eye. So we write $2^10$ instead. The big number on the bottom, $2$, is the *base* — the thing being multiplied. The small number floating on top, $10$, is the *exponent* (also called the *power* or the *index*) — and it does just one job: it *counts how many copies of the base are multiplied together*. Read $2^10$ as "two to the tenth," or "two to the power ten." Its value is $1024$.

#definition("Exponent (whole-number powers)")[
  For a number $b$ and a whole number $n >= 1$, the *power* $b^n$ means $b$ multiplied by itself $n$ times:
  $ b^n = underbrace(b times b times dots times b, n "copies"). $
  Here $b$ is the *base* and $n$ is the *exponent*. By separate convention (justified in the next box) $b^0 = 1$ for any $b != 0$, and $b^1 = b$.
]

The exponent is a tiny number doing enormous work. That is the whole drama of this chapter: the value $b^n$ is gigantic, but the exponent $n$ that summons it is small and tame. The folded paper reaches the Moon, but the exponent is only $42$. Hold onto that lopsidedness — it is exactly the lopsidedness that makes logarithms useful, and it is exactly why a 32-kilobyte window in a compressor (Chapter 30) can address billions of positions with a handful of bits.

Let us get fluent. The *powers of two* are the heartbeat of computing, so we will say them until they are reflex:

$ 2^0 = 1, quad 2^1 = 2, quad 2^2 = 4, quad 2^3 = 8, quad 2^4 = 16, quad 2^5 = 32, $
$ 2^6 = 64, quad 2^7 = 128, quad 2^8 = 256, quad 2^9 = 512, quad 2^10 = 1024. $

Notice the rhythm: each line is exactly *double* the one before, because to go from $2^n$ to $2^(n+1)$ you multiply by one more copy of $2$. That doubling is the engine. And notice $2^10 = 1024 approx 1000$ — this near-miss is why a "kilobyte" is sometimes $1000$ and sometimes $1024$ bytes, a confusion we will meet again. The powers of ten, meanwhile, you already know in your bones: $10^0 = 1$, $10^1 = 10$, $10^2 = 100$, and in general $10^n$ is "one followed by $n$ zeros." The exponent literally *counts the zeros*. That is the first quiet hint that an exponent is a kind of *length*.

#gomaths("Why anything-to-the-zero is 1, and what negative exponents mean")[
  The definition "multiply $b$ by itself $n$ times" only obviously makes sense for $n = 1, 2, 3, dots$. So why is $b^0 = 1$, and what could $b^(-1)$ possibly mean? We extend the definition by *insisting the pattern keep working*, the same trick we used for place value in Chapter 4.

  Walk down the powers of two and watch what happens at each step: you *halve*.
  $ 2^3 = 8, quad 2^2 = 4, quad 2^1 = 2, quad 2^0 = ?, quad 2^(-1) = ?, quad 2^(-2) = ? $
  Each step down divides by $2$: $8 -> 4 -> 2 -> dots$. To keep the rhythm, the step after $2$ must be $2 div 2 = 1$, so $2^0 = 1$. Continue: $1 div 2 = 1/2$, so $2^(-1) = 1/2$; then $2^(-2) = 1/4$. A *negative exponent means "one over the positive power"*: $b^(-n) = 1 / b^n$. This is not a separate rule to memorise — it is the only choice that keeps the halving pattern unbroken, and (as the next section shows) the only choice that keeps the exponent *rules* unbroken. Tiny check: $2^(-3) = 1/8 = 0.125$, and indeed $0.125 times 2^3 = 0.125 times 8 = 1$. ✓
  ]

So exponents already stretch in both directions: big positive exponents make huge numbers, negative exponents make tiny fractions, and $b^0 = 1$ sits exactly in the middle. A probability is a number between $0$ and $1$, which is to say a number you reach with a *negative* exponent of two — keep that thought; it is the seed of the entire information-content formula.

#checkpoint[
  Without a calculator: what is $2^16$? (Hint: you already know $2^8 = 256$, and $2^16 = 2^8 times 2^8$.)
][$2^16 = 256 times 256 = 65536$. This is why an "unsigned 16-bit integer" runs from $0$ to $65535$ — exactly $2^16$ distinct values, as we counted in Chapter 4.]

== The three rules that run the whole show

Exponents would be a curiosity if not for three short rules. These rules are the gears that make logarithms turn, so we will derive each one by *counting copies* — no memorisation, just looking. They are the only algebra this chapter needs.

=== Rule 1: multiplying powers adds the exponents

What is $2^3 times 2^4$? Refuse to compute it the long way; instead, *count*. $2^3$ is three twos in a row; $2^4$ is four twos in a row; multiply them and you have three-then-four twos all multiplied together — *seven* twos. So $2^3 times 2^4 = 2^7$. The exponents *added*: $3 + 4 = 7$.

#theorem("Product rule for exponents")[
  For any base $b$ and whole numbers $m, n$:
  $ b^m times b^n = b^(m+n). $
]

#proof[
  By the definition, $b^m$ is $m$ copies of $b$ multiplied together, and $b^n$ is $n$ copies. Writing the first group and then the second group, all multiplied, gives a single run of $m + n$ copies of $b$ — and a run of $m + n$ copies of $b$ is exactly what $b^(m+n)$ means. Multiplication is associative, so the grouping does not matter; only the *total count* of factors does. Hence $b^m times b^n = b^(m+n)$. #h(1fr)
]

This is the rule that matters most, because *it is the seed of the logarithm's superpower*. Stare at it: on the left, a *multiplication* of two quantities; on the right, an *addition* of their exponents. Exponents convert "times" into "plus." Hold that sentence up to the light. In a moment we will turn it inside out and get the single most useful fact in the book.

=== Rule 2: dividing powers subtracts the exponents

By the same counting, $2^7 div 2^3$ cancels three of the seven twos, leaving four: $2^7 / 2^3 = 2^4$, and $7 - 3 = 4$. In general $b^m / b^n = b^(m-n)$. Notice this immediately explains $b^0$ and negative exponents again: $b^n / b^n = b^(n-n) = b^0$, but any nonzero thing divided by itself is $1$, so $b^0 = 1$. The rules force it. And $b^0 / b^n = b^(0-n) = b^(-n)$, while $1 / b^n$ is the same division — so $b^(-n) = 1/b^n$, exactly as the halving pattern promised.

=== Rule 3: a power of a power multiplies the exponents

What is $(2^3)^4$? The outer exponent says "take $2^3$ and multiply it by itself four times": $2^3 times 2^3 times 2^3 times 2^3$. By Rule 1 the exponents add: $3 + 3 + 3 + 3 = 12$. So $(2^3)^4 = 2^12$, and $3 times 4 = 12$. In general $(b^m)^n = b^(m n)$: nesting *multiplies* the exponents.

#keyidea[
  The three exponent rules, in one breath: *times becomes plus* ($b^m b^n = b^(m+n)$), *divide becomes minus* ($b^m / b^n = b^(m-n)$), *nest becomes multiply* ($(b^m)^n = b^(m n)$). Every one of them is just "count the copies of the base." Everything else in this chapter — logarithms, change of base, the bit — is a consequence of these three lines.
]

#aside[
  These rules are *why* the exponent feels like a "length." Lengths add when you lay segments end to end ($3 + 4 = 7$), and exponents add when you lay powers end to end in a product. The exponent of a power is the moral equivalent of the *length* of the number written in a clever ruler. The logarithm, next, makes that ruler official.
]

#checkpoint[
  Simplify $(2^5 times 2^3) / 2^6$ to a single power of two, then give its value.
][Top: $2^5 times 2^3 = 2^8$ (Rule 1). Divide: $2^8 / 2^6 = 2^(8-6) = 2^2$ (Rule 2). Value $= 4$.]

== The logarithm: the exponent you were looking for

Now the turn. So far we have always been *given* the exponent and asked for the big number: "what is $2^10$?" — answer, $1024$. But compression constantly asks the *opposite* question. We are handed the big number — the count of possibilities, the size of a file, the rarity of an event — and we want to know *the exponent that produced it*. "Two to the *what* equals $1024$?" The answer is $10$, and that answer has a name. It is the *logarithm*.

#definition("Logarithm")[
  For a base $b > 1$ and a positive number $x$, the *logarithm of $x$ to base $b$*, written $log_b x$, is *the exponent to which you must raise $b$ to get $x$*. In symbols, $log_b x$ is the number $y$ such that
  $ b^y = x. $
  Equivalently: $log_b x$ and $b^y$ are inverse questions — $log_b (b^y) = y$ and $b^(log_b x) = x$. They perfectly undo each other.
]

Say it the friendly way: *a logarithm is an exponent in disguise.* When you see $log_2 1024$, do not panic — just ask yourself, slowly, "two to the what gives me $1024$?" The powers of two we drilled answer instantly: $2^10 = 1024$, so $log_2 1024 = 10$. The logarithm is simply the machine that reads off that little exponent for you. Three more, read aloud:

$ log_2 8 = 3 quad ("because" 2^3 = 8), $
$ log_10 1000 = 3 quad ("because" 10^3 = 1000), $
$ log_2 1 = 0 quad ("because" 2^0 = 1). $

That last one is worth a pause: *the log of $1$ is always $0$*, in every base, because anything to the power zero is one. We will read this, soon, as "an event that is certain carries zero information." And what about $log_b b$? That asks "$b$ to the what gives $b$?" — the answer is $1$, since $b^1 = b$. So $log_2 2 = 1$. Remember that number. It is, in disguise, *one bit*.

#gomaths("Reading log notation, and the three bases that matter")[
  The subscript on $log$ is the *base* — the thing being raised to a power. Three bases dominate, and each has a nickname:
  - $log_2$ — *binary logarithm*, "how many doublings?" The native log of computing and of this book. Sometimes written $"lg"$.
  - $log_10$ — *common logarithm*, "how many tens?", i.e. roughly "how many digits?". Often written just $log$ with no subscript in engineering. This is the one Henry Briggs built tables for in the 1620s.
  - $log_e$ — *natural logarithm*, written $ln$, where $e approx 2.71828$ is a special constant we meet in the growth section. It is "natural" because calculus loves it (Chapter 11).

  In this book, *whenever the base is unwritten, assume base 2*, because we are almost always counting bits. A worked read: $log_2 64$ means "two to the what is $64$?"; since $2^6 = 64$, the answer is $6$. And $log_10 10000$ means "ten to the what is $10000$?"; that is $4$ — which is also (one less than) the number of digits in $10000$. The common log of a number is, give or take, *how many digits it has*. That is not a coincidence; it is the whole point of logarithms, and we prove the digit-counting connection below.
  ]

#fig([The logarithm and the exponential are mirror images across the diagonal line $y = x$ — each perfectly undoes the other, as Chapter 6 defined for inverse functions. The exponential $2^x$ rockets upward; its mirror, $log_2 x$, rises ever more slowly, flattening as $x$ grows. Tiny inputs to the log (numbers near $0$) plunge to large negative values — the regime of rare events and large surprise.],
cetz.canvas({
  import cetz.draw: *
  // axes
  line((-0.2, 0), (4.4, 0), mark: (end: "stealth"), stroke: 0.6pt)
  line((0, -2.2), (0, 4.4), mark: (end: "stealth"), stroke: 0.6pt)
  content((4.5, -0.25), text(size: 8pt)[$x$])
  content((-0.3, 4.4), text(size: 8pt)[$y$])
  // diagonal y=x
  line((-1.6, -1.6), (4.1, 4.1), stroke: (paint: gray, dash: "dashed", thickness: 0.5pt))
  content((3.7, 3.4), text(size: 7pt, fill: gray)[$y=x$])
  // exponential y = 2^x  (sampled)
  let expc = ((-2,0.25),(-1,0.5),(0,1),(0.5,1.41),(1,2),(1.5,2.83),(2,4))
  line(..expc, stroke: 1pt + rgb("#0b5394"))
  content((2.05, 4.25), text(size: 7.5pt, fill: rgb("#0b5394"))[$2^x$])
  // logarithm y = log2 x  (mirror)
  let logc = ((0.25,-2),(0.5,-1),(1,0),(1.41,0.5),(2,1),(2.83,1.5),(4,2))
  line(..logc, stroke: 1pt + rgb("#0f766e"))
  content((4.1, 2.3), text(size: 7.5pt, fill: rgb("#0f766e"))[$log_2 x$])
  // tick at 1
  line((1,-0.08),(1,0.08), stroke: 0.6pt)
  content((1,-0.3), text(size: 7pt)[$1$])
}))

The picture tells the chapter's emotional story. The exponential climbs like a rocket; the logarithm, its mirror, climbs like a tired hiker — fast at first, then slower and slower, almost flat for huge inputs. *Multiplying the input to a logarithm only adds a little to the output.* Make $x$ ten times bigger and $log_10 x$ goes up by just $1$. Make a file a thousand times bigger and its bit-length grows by only $10$. The logarithm tames the gigantic. That taming is precisely the service compression theory needs.

#history[
  John Napier, a Scottish laird at Merchiston Castle, spent over twenty years grinding out his logarithms by hand and published _Mirifici Logarithmorum Canonis Descriptio_ — "A Description of the Wonderful Canon of Logarithms" — in *1614*: ninety pages of tables, fifty-seven of explanation. His goal was brutally practical: astronomers and navigators were drowning in the multiplication of huge sines and cosines, and Napier had found a way to *replace multiplication with addition* (the very property we are about to celebrate). The English mathematician Henry Briggs, electrified, made a four-day ride to Edinburgh in 1615 to meet him, and together they re-scaled the idea to base $10$; Briggs then computed tens of thousands of logarithms to fourteen decimal places. For three hundred years, until the electronic calculator, the logarithm table and its physical embodiment — the slide rule — were how humanity multiplied big numbers. Engineers put men on the Moon with slide rules. The word "logarithm" is Napier's own coinage, from Greek _logos_ (ratio/reckoning) and _arithmos_ (number).
]

== The superpower: logarithms turn multiplication into addition

This is the property that built navies, and it is the property that measures information. We meet it now in full.

Take the product rule for exponents, $b^m times b^n = b^(m+n)$, and translate it into the language of logarithms. Let $x = b^m$ and $y = b^n$. By the definition of logarithm, $m = log_b x$ and $n = log_b y$. The product rule says $x times y = b^(m+n)$, which means — reading off the exponent again — that $log_b (x y) = m + n = log_b x + log_b y$. We have just proved the most useful identity in the book.

#theorem("The product law of logarithms")[
  For any base $b > 1$ and positive numbers $x, y$:
  $ log_b (x y) = log_b x + log_b y. $
  Multiplication inside the log becomes *addition* outside. Likewise $log_b (x / y) = log_b x - log_b y$ (division becomes subtraction) and $log_b (x^k) = k log_b x$ (a power becomes a *multiplier*).
]

#proof[
  Write $x = b^m$ and $y = b^n$, so by definition $m = log_b x$ and $n = log_b y$. Then $x y = b^m b^n = b^(m+n)$ by the product rule for exponents (proved above). Taking $log_b$ of both sides and using that $log_b$ undoes $b^(dot)$, we get $log_b (x y) = m + n = log_b x + log_b y$. The quotient law follows identically from $b^m / b^n = b^(m-n)$, and the power law from $(b^m)^k = b^(m k)$ — that is, $log_b(x^k) = log_b(b^(m k)) = m k = k log_b x$. #h(1fr)
]

Why does anyone care that times becomes plus? Two reasons, three centuries apart.

The *first* reason is Napier's: addition is enormously easier than multiplication. To multiply two ugly seven-digit numbers, look up each one's logarithm in a table, *add* the two logarithms (a schoolchild can add), then look up which number has that summed logarithm. You have multiplied without ever multiplying. The slide rule is this idea made physical: two logarithmic rulers sliding past each other, *adding lengths* to perform multiplication. For 350 years this was the calculator.

The *second* reason is ours, and it is the soul of information theory. Probabilities *multiply* when independent events combine — the chance of two coin-flips both landing heads is $1/2 times 1/2 = 1/4$ (we will make this rigorous in Chapter 9). But we want a measure of *information* that *adds*: learning two independent facts should cost the sum of their individual costs, not the product. Multiplication for probabilities; addition for information. *The only mathematical bridge between "multiply" and "add" is the logarithm.* That is why information is measured in logarithms — not by taste or convention, but by necessity. Any sensible additive measure of surprise built on multiplicative probabilities is *forced* to be a logarithm. We will see this claim made precise in Chapter 18; here we have already laid its entire foundation.

#keyidea[
  Independent probabilities *multiply*; we want information to *add*; the logarithm is the unique function that turns multiplication into addition. Therefore information must be measured in logarithms. The whole of Shannon's theory hangs from this single hook — and you have just proved the hook.
]

#tryit[
  Convince yourself the superpower is real with numbers you can check. Take $x = 8$ and $y = 4$ in base $2$. Separately: $log_2 8 = 3$ and $log_2 4 = 2$, so their sum is $5$. Together: $x y = 32$, and $log_2 32 = 5$ because $2^5 = 32$. They match — multiplication ($8 times 4$) became addition ($3 + 2$). Now try the power law: $log_2(8^2) = log_2 64 = 6$, and indeed $2 times log_2 8 = 2 times 3 = 6$. The exponent $2$ jumped out front as a multiplier.
]

== Change of base: every logarithm is every other in disguise

A practical snag: your calculator, and Python's `math` module, give you $ln$ (natural log) and $log_10$, but compression wants $log_2$. Are we stuck? No — all logarithms are the *same shape*, differing only by a constant stretch. Converting between them is one clean formula.

#theorem("Change of base")[
  For bases $a, b > 1$ and any positive $x$,
  $ log_b x = (log_a x) / (log_a b). $
  In particular, to get a base-2 log from a natural log: $log_2 x = (ln x) / (ln 2)$, where $ln 2 approx 0.6931$.
]

#proof[
  Let $y = log_b x$, so by definition $b^y = x$. Take $log_a$ of both sides: $log_a (b^y) = log_a x$. By the power law (just proved), the left side is $y log_a b$. So $y log_a b = log_a x$, and dividing by $log_a b$ (which is positive, since $b > 1$) gives $y = (log_a x)/(log_a b)$. But $y$ was $log_b x$. #h(1fr)
]

The formula says: *to switch bases, divide by the log of the new base in the old base.* Since $log_a b$ is just a fixed number once $a$ and $b$ are chosen, changing base only *rescales* the logarithm by a constant. That is why the graph of $log_2 x$ and the graph of $log_10 x$ have the identical shape — one is just a vertically stretched copy of the other. A bit and a "decimal digit of information" (called a _nat_ for natural log, or a _ban_ for base 10) measure the same thing in different units, exactly as inches and centimetres measure the same length. The exchange rate is the change-of-base constant.

#gomaths("The number $e$ and the natural logarithm")[
  Why would anyone choose the lumpy base $e approx 2.71828$ instead of a clean $2$ or $10$? Because of *growth*. Imagine a bank that pays 100% interest a year. Compounded once, £1 becomes £2. Compounded twice a year (50% each half), you get $(1 + 1/2)^2 = £2.25$. Monthly: $(1 + 1/12)^12 approx £2.61$. Compounded *continuously* — every instant — the limit is exactly $e$ pounds: $e = lim_(n -> oo) (1 + 1/n)^n approx 2.71828$. Jacob Bernoulli stumbled on this constant studying compound interest in the late 1600s; Leonhard Euler named it $e$ in a 1731 letter and computed it to 18 places. Its magic, which you will see properly in Chapter 11, is that the exponential $e^x$ is the one curve whose *steepness equals its own height* — it grows in exact proportion to how big it already is, which is the mathematical signature of every population, epidemic, and savings account. The natural log $ln = log_e$ is its inverse, and it is the base in which the calculus of growth comes out cleanest. For us, $e$ mostly appears as the unit-conversion constant $ln 2 approx 0.693$ that bridges the mathematician's natural log and the engineer's bit.
  ]

=== Logarithms count digits — a worked sanity check

Here is a small skill that pays off whenever you eyeball a number. The common logarithm $log_10 x$ is, near enough, *one less than the number of digits in $x$*. Why? A number with $d$ digits sits between $10^(d-1)$ (the smallest $d$-digit number, a $1$ followed by $d-1$ zeros) and $10^d - 1$ (the largest). Taking $log_10$ across that range, $log_10 x$ lands between $d - 1$ and just under $d$. So the *integer part* of $log_10 x$ is $d - 1$, and the digit count is $floor(log_10 x) + 1$.

#gomaths("The floor function, $floor(x)$")[
  The two angle-brackets in $floor(x)$ mean *round down to the nearest whole number* — the "floor" you would stand on. Chop off whatever sits after the decimal point and keep the integer below: $floor(4.816) = 4$, $floor(19.93) = 19$, $floor(7) = 7$ (a whole number is already on its own floor). It is not ordinary rounding — $floor(4.9) = 4$, *not* $5$ — it always goes *down*. We use it here because "the integer part of a logarithm" is exactly the floor, and a count of digits or bits must be a whole number. (Its twin, the *ceiling* $ceil(x)$, rounds *up*; we will reach for it when we count how many whole bits a codeword needs.)
  ]

Try it: $x = 65536$ has five digits, and $log_10 65536 approx 4.816$ — integer part $4$, so $4 + 1 = 5$ digits. ✓ The same logic in base $2$ says the number of *bits* needed to write a whole number $x$ is $floor(log_2 x) + 1$. For $x = 65536 = 2^16$ that gives $floor(16) + 1 = 17$ bits — because $2^16$ itself is a $1$ followed by sixteen $0$s in binary, seventeen digits long. This "log counts the length" fact is why, all through this book, the *bit-length* of a quantity is its logarithm: a position in a 32 KB window ($2^15$ positions) needs $log_2 2^15 = 15$ bits to name; a file of $N$ bytes needs about $log_2 N$ bits just to write down *its own length*. Length is logarithm, everywhere you look.

#note[
  Before electronics, the logarithm's "length" nature was a physical object: the *slide rule*. Two rulers, each marked not evenly but *logarithmically* (so the distance from $1$ to $x$ is proportional to $log x$), slide past one another. Lining up lengths *adds* logarithms, and adding logarithms *multiplies* the numbers — so a sliding ruler multiplies. Generations of engineers wore one on their belt; the Apollo astronauts carried a Pickett slide rule to the Moon in 1969. When the pocket calculator arrived in the 1970s the slide rule died in a decade, but the idea never did: the logarithm is still how we turn the unmanageable products of probability into the friendly sums of bits.
]

== Three speeds of growth, and why one of them beats every compressor

We now have the vocabulary to talk precisely about *how fast things grow* — and growth is the hidden subject of all of compression, because the number of possible files of a given size grows exponentially, while any honest compressor can only ever shrink them a little. Let us line up the three growth rates a reader meets again and again in this book.

- *Linear growth*: add a fixed amount each step. $0, 5, 10, 15, 20, dots$. Plotted, a straight line. Doubling the input doubles the output. A file twice as long takes twice as long to scan — that is linear, written $O(n)$ in the Big-O language of Chapter 14.
- *Polynomial growth*: multiply by raising the input to a fixed power. $n^2$: $1, 4, 9, 16, 25, dots$. Faster than linear but still "civilised." Comparing every pair of items in a list of $n$ things costs about $n^2$ — quadratic.
- *Exponential growth*: multiply by a fixed factor each step, so the *input sits in the exponent*. $2^n$: $1, 2, 4, 8, 16, 32, dots$. Each step *doubles*. This is the paper folding to the Moon. Nothing polynomial can keep up; for large enough $n$, $2^n$ towers over $n^(1000)$.

#fig([Three growth rates from the same start. Linear ($n$) plods. Quadratic ($n^2$) curves up. Exponential ($2^n$) leaves the page almost immediately — by $n = 7$ it has lapped the others and is climbing vertically. This gap is why brute force fails and why we need the logarithm to measure exponential quantities at all.],
cetz.canvas({
  import cetz.draw: *
  let sx = 0.55
  let sy = 0.09
  line((-0.2,0),(8.2,0), mark:(end:"stealth"), stroke: 0.6pt)
  line((0,-0.2),(0,5.2), mark:(end:"stealth"), stroke: 0.6pt)
  content((8.3,-0.3), text(size:8pt)[$n$])
  // linear y=n*4 (clipped to ~ n)
  line((0,0),(8,8*sx*0.6), stroke: 1pt + rgb("#783f04"))
  content((8.0,8*sx*0.6+0.25), text(size:7.5pt, fill: rgb("#783f04"))[$n$])
  // quadratic n^2 (sampled, scaled)
  let q = ()
  for n in (0,1,2,3,4,5,6,7) { q.push((n*sx*1.0, n*n*sy*0.9)) }
  line(..q, stroke: 1pt + rgb("#0b5394"))
  content((7*sx*1.0+0.2, 7*7*sy*0.9), text(size:7.5pt, fill: rgb("#0b5394"))[$n^2$])
  // exponential 2^n (sampled, scaled, clipped)
  let e = ()
  for n in (0,1,2,3,4,5,6) { e.push((n*sx*1.0, calc.min(2*calc.pow(2,n)*sy*0.6, 5))) }
  line(..e, stroke: 1.1pt + rgb("#0f766e"))
  content((6*sx*1.0+0.25, 4.9), text(size:7.5pt, fill: rgb("#0f766e"))[$2^n$])
}))

Here is why this matters for us, stated as a theorem we can prove with nothing but counting (the full version is the "no free lunch" result of Chapter 8).

#theorem("There are exponentially many files, so no code shortens them all")[
  There are exactly $2^n$ distinct binary strings of length $n$. Any lossless code is a *bijection* (Chapter 6) — a reversible pairing — between inputs and outputs, so it cannot map two different inputs to the same output. Therefore it cannot map all $2^n$ inputs of length $n$ to outputs *shorter* than $n$, because there are only $2^0 + 2^1 + dots + 2^(n-1) = 2^n - 1$ strings shorter than $n$ — one too few.
]

#proof[
  Count the inputs. A binary string of length $n$ is $n$ independent choices of $0$ or $1$; by the doubling rule each added bit doubles the count, giving $2^n$ strings (the formal "multiplication principle" is Chapter 8). Count the *shorter* outputs: there are $2^k$ strings of each length $k = 0, 1, dots, n-1$, and $2^0 + 2^1 + dots + 2^(n-1) = 2^n - 1$ in total — a fact you can check by noticing each partial sum is one less than the next power of two ($1 = 2 - 1$, $1+2 = 4-1$, $1+2+4 = 8-1$). So there are $2^n$ inputs but only $2^n - 1$ strictly-shorter strings. A reversible code needs distinct outputs for distinct inputs; with fewer short slots than inputs, at least one input must get an output *no shorter* than itself. No code shrinks everything. #h(1fr)
]

This is the iron law beneath all compression, and it is pure exponentials: there are *exponentially many* possible files, the doubling is relentless, and any compressor that shortens some inputs must lengthen others. Compression is not magic that defeats this count; it is the art of spending the short codewords on the files that *actually occur* and letting the short codewords be "borrowed" from the astronomically many files that never will. The exponential explosion of possibilities is the enemy; the logarithm — measuring those possibilities on a humane scale — is the tool that lets us reason about it.

#misconception[A really clever algorithm could compress *any* file, even random ones, if it just tried hard enough.][The counting theorem above forbids it, with no appeal to cleverness. There are $2^n$ files of length $n$ and strictly fewer shorter strings, so *every* lossless compressor lengthens at least as many files as it shortens — averaged over all inputs, it can't win. Real compressors succeed only because real data is wildly *non-random*: English text, photos, and genomes occupy a vanishingly thin sliver of the $2^n$ possibilities. Compression bets on structure. On true randomness (or on already-compressed data) it must lose, and the loss is exactly the gap the logarithm measures.]

== A bit is a logarithm: the keystone of the book

Everything so far converges on one equation. We have claimed since Chapter 1 that information is measured in *bits*; we have used the word freely. Now we can say *exactly* what a bit is, in the language of logarithms, and the definition will feel inevitable.

Start with a question you can already answer. How many yes/no answers does it take to pin down one item out of a set of equally likely possibilities? With one yes/no question you split a set in half — so one question distinguishes $2$ possibilities. Two questions distinguish $2 times 2 = 4$. Three questions, $8$. To single out one possibility from $N$ equally likely ones, you need enough yes/no questions $k$ that $2^k >= N$ — that is, $k = log_2 N$ questions. *The number of bits is the logarithm, base 2, of the number of possibilities.* That is the entire idea.

#definition("Information content of an equally-likely choice")[
  If a symbol is drawn uniformly from an alphabet of $N$ equally likely possibilities, identifying it carries exactly
  $ log_2 N quad "bits" $
  of information — the number of yes/no questions an optimal questioner needs. One bit ($N = 2$) is the answer to a single fair yes/no question; $log_2 2 = 1$. A byte ($N = 256$) carries $log_2 256 = 8$ bits, which is why a byte is eight bits.
]

So far, "equally likely." But real data is *lopsided*: the letter "e" is common, "q" is rare. The leap Shannon made — and the leap this chapter has secretly been preparing you for the whole time — is to handle unequal probabilities. Suppose an event has probability $p$. If it were one of $N$ equally likely outcomes, its probability would be $p = 1/N$, so $N = 1/p$, and its information content would be $log_2 N = log_2 (1/p)$. By the quotient law, $log_2(1/p) = log_2 1 - log_2 p = 0 - log_2 p = -log_2 p$. There it is.

#keyidea[
  *The information content (or "surprise") of an event of probability $p$ is $-log_2 p$ bits.* A certain event ($p = 1$) carries $-log_2 1 = 0$ bits — no surprise, no information. A coin-flip ($p = 1/2$) carries $-log_2(1/2) = 1$ bit. A one-in-a-million event carries $-log_2(1/1000000) approx 20$ bits. Rare things are expensive; certain things are free. This single formula, $-log_2 p$, is the price tag on every symbol in every compressor in this book.
]

Look at how naturally the logarithm's properties make this *the only sensible choice*. The minus sign is not arbitrary: probabilities lie between $0$ and $1$, so their logarithms are negative (recall $log_2(1/2) = -1$); the minus flips surprise back to a positive number of bits. The *additivity* we fought for pays off here: two independent events of probabilities $p$ and $q$ together have probability $p q$ (probabilities multiply), and their combined surprise is $-log_2(p q) = -log_2 p - log_2 q$ (logs turn the product into a sum) — the surprises *add*, exactly as information should. And the formula reduces to the equally-likely case when all $p = 1/N$. Every requirement we placed on a measure of information is met by $-log_2 p$, and — this is the deep part — *only* by it. The logarithm is not one option among many; it is forced.

#tryit[
  Feel the formula on the alphabet. If all $26$ letters were equally likely, each would carry $log_2 26 approx 4.70$ bits. But they are not equal: Shannon estimated in 1951 that English, accounting for its lopsided letters and predictable patterns, runs closer to *1 to 1.5 bits per character* — far below $4.70$, and astronomically below the $8$ bits a naïve byte-per-letter spends. That enormous gap, between $8$ bits and ~$1.3$, is the *redundancy* compression exists to remove (Chapter 3). The logarithm is the ruler that lets us see the gap at all.
]

#checkpoint[
  A loaded die shows a "6" with probability $1/8$. How many bits of information does seeing a "6" carry? And a "1" with probability $1/2$?
][A "6": $-log_2(1/8) = log_2 8 = 3$ bits. A "1": $-log_2(1/2) = 1$ bit. The rarer outcome (the 6) is the more surprising and the more expensive to encode — exactly as a good code should arrange.]

We will not build the entropy formula $H = -sum p log_2 p$ in full until Chapter 18, but notice you now understand every piece of it: it is just the *average* of the per-symbol surprise $-log_2 p$, weighted by how often each symbol occurs. (The stretched-S symbol $sum$, read "sum," is just shorthand for "add these up over every symbol" — a piece of notation Chapter 11 unpacks properly; for now read $-sum p log_2 p$ as "add up $-p log_2 p$ across all the symbols.") The whole towering edifice of information theory rests on the one humble idea of this chapter — that a logarithm counts foldings.

== Logarithms and exponents in Python

We will compute these quantities constantly in `tinyzip`, so let us meet Python's tools for them, treating Python exactly as carefully as we treat the maths.

#gopython("Arithmetic operators, and the power operator $star.op star.op$")[
  Python does ordinary arithmetic with the symbols you expect: `+` add, `-` subtract, `*` multiply, `/` divide. Two are special. *Exponentiation* — "to the power of" — is written with a double star, `**`. So `2 ** 10` evaluates to `1024`, and `2 ** -1` evaluates to `0.5`. (The single star `*` is plain multiplication; the double star `**` is power. Don't confuse them — and recall the guide's warning that in prose we must escape a literal star.) The other special one is *integer division* `//`, which divides and throws away the remainder: `7 // 2` is `3`, not `3.5`. A tiny runnable snippet:
  ```python
  >>> 2 ** 10        # two to the tenth
  1024
  >>> 2 ** -3        # negative exponent -> a fraction
  0.125
  >>> 256 ** 0       # anything to the zero
  1
  ```
  The `>>>` is the prompt of Python's interactive shell — the REPL, which Chapter 15 introduces in full; you type after it and Python prints the answer.
  ]

#gopython("The math module, and import")[
  Python keeps its logarithm and exponential functions in a *module* called `math` — a labelled toolbox you switch on with the word `import`. After `import math`, you reach inside the toolbox with a dot: `math.log2(x)`. The key tools:
  - `math.log2(x)` — the *binary* logarithm $log_2 x$, the one we want most.
  - `math.log(x)` — the *natural* logarithm $ln x$ (base $e$) when called with one argument.
  - `math.log(x, b)` — the logarithm of `x` to *base* `b` (this is the change-of-base formula, done for you).
  - `math.log10(x)` — the common logarithm $log_10 x$.
  - `math.e` — the constant $e approx 2.71828$.
  ```python
  >>> import math
  >>> math.log2(1024)      # two to the WHAT is 1024?
  10.0
  >>> math.log2(0.125)     # surprise of a 1-in-8 event, with a sign flip
  -3.0
  >>> math.log(8, 2)       # change of base: log of 8 to base 2
  3.0
  ```
  Note the answers come back as `10.0`, not `10` — the trailing `.0` marks a *floating-point* number (a number that can carry a fractional part; Chapter 13 dissects how computers store these), because logarithms are usually not whole.
  ]

With those tools we can write, in one line each, the two functions every compressor needs: the *surprise* (information content) of an event, and a check of the doubling law.

#tryit[
  A foretaste of `tinyzip` (the real package skeleton is not built until Chapter 15; this is just an illustration you can type into the shell). Here is a function that turns a probability into a number of bits — the price tag $-log_2 p$ we just derived. This is the conversion that every later entropy coder (Huffman in Chapter 24, arithmetic coding in Chapter 26, ANS in Chapter 27) will spend its life trying to achieve.

  ```python
  import math

  def info_bits(p: float) -> float:
      """Information content of an event of probability p, in bits.

      This is Shannon's surprisal, -log2(p):
      a certain event (p = 1) costs 0 bits; a coin-flip (p = 0.5)
      costs 1 bit; a one-in-a-million event costs ~20 bits.
      """
      if not (0.0 < p <= 1.0):
          raise ValueError(f"probability must be in (0, 1], got {p}")
      return -math.log2(p)

  def bits_to_name(n_choices: int) -> float:
      """How many bits to single out one of n equally likely choices?"""
      if n_choices < 1:
          raise ValueError("need at least one choice")
      return math.log2(n_choices)
  ```

  The type hints `p: float` and `-> float` (a Python feature we will teach properly in Chapter 16) announce that this function eats a decimal number and returns one; they are documentation the reader — and the tools — can trust. A quick session shows the formula breathing:

  ```python
  >>> info_bits(1.0)        # certainty: no information
  0.0
  >>> info_bits(0.5)        # a fair coin: exactly one bit
  1.0
  >>> info_bits(1/256)      # one byte's worth of surprise
  8.0
  >>> round(info_bits(1/1_000_000), 1)   # one in a million
  19.9
  >>> bits_to_name(256)     # choices in a byte
  8.0
  ```

  We can already sketch the *total* cost of a message: add up `info_bits(p)` over its symbols. That sum is what the rest of the book learns to actually *emit* as bits. We have sketched the meter; the real `tinyzip` package, and the coders that try to hit this floor, come later.
  ]

#pitfall[
  `math.log2(0)` does not return a number — the logarithm of zero is undefined (there is no power of $2$ that gives $0$; the curve plunges toward minus-infinity but never arrives). In compression this matters: a symbol that *never occurs* has probability $0$ and infinite surprise, but it also never appears in the message, so it contributes nothing. Code must *guard the zero* — our `info_bits` rejects $p <= 0$ outright — and entropy code that sums $p log_2 p$ must treat the $p = 0$ term as $0$ (a convention justified because $p log_2 p -> 0$ as $p -> 0$, which the gentle calculus of Chapter 11 will confirm).
]

== Worked example: weighing a tiny message

Let us put every tool of the chapter to work on one concrete string, the kind of micro-example we will return to as the book's running sample. Take the six-character message `BANANA` — no, let us use `ABRACADABRA`, a fortune-teller's word, eleven letters long, because its lopsided letter frequencies show the logarithm earning its keep.

Count the letters: `A` appears $5$ times, `B` twice, `R` twice, `C` once, `D` once — eleven letters total. Treat each letter's *relative frequency* as its probability:

$ p(A) = 5/11, quad p(B) = p(R) = 2/11, quad p(C) = p(D) = 1/11. $

Now the per-letter surprise, $-log_2 p$, using the change-of-base in our heads or `math.log2`:

#table(columns: (auto, auto, auto, auto), inset: 6pt, align: (center, center, right, right),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Letter*], [*Count*], [*$p$*], [*Surprise $-log_2 p$ (bits)*]),
  [A], [5], [$5/11 approx 0.455$], [$1.14$],
  [B], [2], [$2/11 approx 0.182$], [$2.46$],
  [R], [2], [$2/11 approx 0.182$], [$2.46$],
  [C], [1], [$1/11 approx 0.091$], [$3.46$],
  [D], [1], [$1/11 approx 0.091$], [$3.46$],
)

Read the table as a sentence: the common `A` is cheap ($1.14$ bits — barely more than a coin-flip's worth of surprise), while the rare `C` and `D` are dear ($3.46$ bits each). A good code, which we build in Chapter 24, will honour exactly this: short codewords for `A`, long ones for `C` and `D`.

Now the *total* information in the message — add up each letter's surprise, which (because surprises add) is the same as multiplying each letter's surprise by how often it occurs:

$ "total bits" = 5(1.14) + 2(2.46) + 2(2.46) + 1(3.46) + 1(3.46) approx 25.0 "bits." $

Twenty-five bits. Compare that to the naïve cost of storing `ABRACADABRA` as one byte per letter: $11 times 8 = 88$ bits. The logarithm has just told us, before we have written a single line of a real codec, that there are at least $88 - 25 = 63$ bits of pure redundancy in the obvious encoding — a file three-and-a-half times larger than it needs to be. *That gap is the whole opportunity of compression, and the logarithm is the only instrument that can see it.*

#aside[
  Divide that $25.0$ bits by the $11$ letters and you get about $2.27$ bits per letter — this per-symbol average is precisely the *entropy* $H$ we will define formally in Chapter 18. You have computed an entropy without being told its name. Everything in Volume I has been quietly assembling this number; from Chapter 18 on, we spend the rest of the book trying to actually *reach* it with real bits.
]

#scoreboard(caption: "the entropy floor, foreseen",
  [Raw bytes (1 byte/letter)], [11 B], [1.00×], [88 bits — the naïve baseline],
  [Entropy floor ($-sum log_2 p$)], [≈3.1 B], [≈3.5×], [25.0 bits — the target no lossless coder can beat],
)

The scoreboard will fill with *real* compressors as the book proceeds; for now it records the destination. The "Bytes" for the floor — about $3.1$ — is just $25.0$ bits divided by $8$, a fractional byte we can only spend in full once arithmetic coding (Chapter 26) lets us emit fractional bits. The logarithm has drawn the finish line. The rest of the book is the race toward it.

== Takeaways

#takeaways((
  [An *exponent* counts how many copies of a base are multiplied: $b^n$ is $n$ copies of $b$. The exponent is tiny while $b^n$ is huge — that lopsidedness is the whole point.],
  [Three rules run everything: $b^m b^n = b^(m+n)$ (times → plus), $b^m / b^n = b^(m-n)$ (divide → minus), $(b^m)^n = b^(m n)$ (nest → times). Each is just "count the copies."],
  [A *logarithm* is the inverse: $log_b x$ is "$b$ to the what equals $x$?" — the exponent in disguise. $log_2 1024 = 10$, $log_2 2 = 1$, $log_b 1 = 0$ always.],
  [The superpower: $log_b(x y) = log_b x + log_b y$. Logarithms turn multiplication into addition — the only bridge between multiplicative probabilities and additive information.],
  [*Change of base*: $log_b x = (log_a x)/(log_a b)$. All logs are the same shape rescaled by a constant; bits, nats, and bans are just different units.],
  [*Exponential growth* ($2^n$) outruns any linear or polynomial growth. There are $2^n$ files of length $n$, so no lossless code can shorten them all — the iron law of compression.],
  [The keystone: information content of an event of probability $p$ is *$-log_2 p$ bits*. Certain = $0$ bits, coin-flip = $1$ bit, one-in-a-million ≈ $20$ bits. This price tag drives every coder in the book.],
))

== Exercises

#exercise("7.1", 1)[
  Without a calculator, evaluate each by reading it as "the exponent you were looking for": (a) $log_2 256$, (b) $log_2 1$, (c) $log_10 100000$, (d) $log_2 (1/16)$, (e) $log_5 125$.
]
#solution("7.1")[
  (a) $2^8 = 256$, so $log_2 256 = 8$. (b) Anything to the power $0$ is $1$, so $log_2 1 = 0$. (c) $10^5 = 100000$, so $log_10 100000 = 5$ — it counts the five zeros. (d) $1/16 = 2^(-4)$, so $log_2(1/16) = -4$ (a negative log, because the input is below $1$). (e) $5^3 = 125$, so $log_5 125 = 3$.
]

#exercise("7.2", 1)[
  Simplify each to a single power of two and give its numeric value: (a) $2^4 times 2^7$, (b) $2^20 / 2^14$, (c) $(2^3)^5$, (d) $2^10 times 2^(-3)$.
]
#solution("7.2")[
  (a) Product rule: $2^(4+7) = 2^11 = 2048$. (b) Quotient rule: $2^(20-14) = 2^6 = 64$. (c) Power-of-a-power: $2^(3 times 5) = 2^15 = 32768$. (d) Product rule with a negative exponent: $2^(10-3) = 2^7 = 128$.
]

#exercise("7.3", 2)[
  A friend insists that $log_2(x + y) = log_2 x + log_2 y$ — that the log of a *sum* is the sum of the logs. Show with a single numeric counterexample that this is false, and state the correct law it is being confused with.
]
#solution("7.3")[
  Take $x = y = 2$. Then $log_2(x + y) = log_2 4 = 2$, but $log_2 x + log_2 y = log_2 2 + log_2 2 = 1 + 1 = 2$ — by bad luck these *agree*, so choose better: take $x = 2, y = 6$. Then $log_2(2 + 6) = log_2 8 = 3$, while $log_2 2 + log_2 6 = 1 + 2.585 approx 3.585$. They differ, so the claimed law is false. The correct law applies to a *product*, not a sum: $log_2(x y) = log_2 x + log_2 y$. There is no simple rule for the log of a sum — that absence is exactly why entropy coders work symbol-by-symbol on products of probabilities, never on sums.
]

#exercise("7.4", 2)[
  Use the change-of-base formula to compute $log_2 10$ from a natural-log fact: you are told $ln 10 approx 2.3026$ and $ln 2 approx 0.6931$. What does the answer mean in plain words about how many *bits* it takes to store one *decimal digit*?
]
#solution("7.4")[
  Change of base: $log_2 10 = (ln 10)/(ln 2) approx 2.3026 / 0.6931 approx 3.32$. Meaning: one decimal digit (one of ten equally likely symbols $0$–$9$) carries $log_2 10 approx 3.32$ bits of information. So a decimal digit is worth about $3.32$ bits — which is why you can pack roughly three decimal digits into $10$ bits ($10 / 3.32 approx 3.01$), and why phone numbers and PINs are far less information-dense than they look.
]

#exercise("7.5", 2)[
  An event $A$ has probability $1/4$ and an independent event $B$ has probability $1/8$. (a) Find the information in $A$ alone and in $B$ alone, in bits. (b) Find the probability that both happen, and the information in "both happened." (c) Verify that the surprises add, and explain *which property of logarithms* guarantees they must.
]
#solution("7.5")[
  (a) $-log_2(1/4) = log_2 4 = 2$ bits for $A$; $-log_2(1/8) = log_2 8 = 3$ bits for $B$. (b) Independent events multiply: $P(A "and" B) = 1/4 times 1/8 = 1/32$, and $-log_2(1/32) = log_2 32 = 5$ bits. (c) $2 + 3 = 5$. ✓ The product law $log_2(p q) = log_2 p + log_2 q$ guarantees it: probabilities multiply, the logarithm converts that product into a sum, so the surprises add. This additivity is the whole reason information is measured with logarithms.
]

#exercise("7.6", 2)[
  The string `MISSISSIPPI` has letters with counts: M=1, I=4, S=4, P=2 (eleven letters). Treating relative frequencies as probabilities, compute the per-letter surprise $-log_2 p$ for each distinct letter, then the total information in the whole string. Compare to the naïve cost of $8$ bits per letter.
]
#solution("7.6")[
  Probabilities: $p(M) = 1/11$, $p(I) = p(S) = 4/11$, $p(P) = 2/11$. Surprises: $-log_2(1/11) = log_2 11 approx 3.46$ bits (M); $-log_2(4/11) = log_2(11/4) approx 1.46$ bits (I and S each); $-log_2(2/11) = log_2(11/2) approx 2.46$ bits (P). Total $= 1(3.46) + 4(1.46) + 4(1.46) + 2(2.46) approx 3.46 + 5.84 + 5.84 + 4.92 approx 20.1$ bits. Naïve cost: $11 times 8 = 88$ bits. The entropy floor is about $20.1$ bits — roughly $4.4times$ smaller — revealing about $68$ bits of removable redundancy. (Per-letter, that is $approx 1.82$ bits, the entropy $H$ of Chapter 18.)
]

#exercise("7.7", 3)[
  Prove from the exponent rules alone that $log_b(x^k) = k log_b x$ for any positive integer $k$, without invoking the product law as a black box — build it up by repeated use of the product law of *exponents*. Then explain why this "power becomes a multiplier" identity is what makes coding a symbol that repeats $k$ times cost $k$ times its single-occurrence price.
]
#solution("7.7")[
  Let $m = log_b x$, so $b^m = x$ by definition. Then $x^k = (b^m)^k = b^(m k)$ by the power-of-a-power rule (itself proved by applying the product law of exponents $k$ times: $b^m times b^m times dots = b^(m + m + dots) = b^(m k)$). Taking $log_b$ of $x^k = b^(m k)$ and using that $log_b$ undoes $b^(dot)$ gives $log_b(x^k) = m k = k log_b x$. For coding: if a symbol of probability $p$ occurs $k$ times independently, the joint probability is $p^k$, and the information is $-log_2(p^k) = -k log_2 p = k times (-log_2 p)$ — exactly $k$ copies of the single-symbol surprise. The power law is the formal reason "repeating a symbol $k$ times costs $k$ times as much," which is the whole basis of summing per-symbol bit-costs over a message.
]

#exercise("7.8", 3)[
  (Coding.) Using only the `math` module, write a Python function `message_bits(text: str) -> float` that returns the total information content of a string under the model "each character's probability equals its relative frequency in the string." Apply it to `"ABRACADABRA"` and confirm you get approximately the $25.0$ bits computed in the chapter. (You may use a `dict` to count — a lookup table from keys to values, which Chapter 16 covers in full; here a one-line `counts.get(ch, 0) + 1` tallies each character.)
]
#solution("7.8")[
  ```python
  import math

  def message_bits(text: str) -> float:
      n = len(text)
      if n == 0:
          return 0.0
      counts: dict[str, int] = {}
      for ch in text:                       # tally each character
          counts[ch] = counts.get(ch, 0) + 1
      total = 0.0
      for ch in text:                       # sum -log2(p) over all symbols
          p = counts[ch] / n
          total += -math.log2(p)
      return total

  # >>> round(message_bits("ABRACADABRA"), 1)
  # 25.0
  ```
  Each character contributes $-log_2(p)$ where $p$ is its frequency; summing over all eleven characters reproduces the chapter's $approx 25.0$ bits. Equivalently one could sum $"count" times (-log_2 p)$ over the *distinct* letters — the power law of Exercise 7.7 guarantees the two give the same total.
]

#exercise("7.9", 2)[
  (Digit/bit counting.) (a) How many *decimal* digits are in $2^64$? (You are told $log_10 2 approx 0.30103$.) (b) How many *bits* are needed to write the whole number one million in binary? Use the rule "length $= floor(log_b x) + 1$."
]
#solution("7.9")[
  (a) Number of digits $= floor(log_10 2^64) + 1 = floor(64 times 0.30103) + 1 = floor(19.266) + 1 = 19 + 1 = 20$ digits. (Indeed $2^64 = 18,446,744,073,709,551,616$, which has 20 digits.) (b) $log_2 1000000 = (log_10 1000000)/(log_10 2) = 6 / 0.30103 approx 19.93$, so $floor(19.93) + 1 = 20$ bits. Check: $2^19 = 524288 < 1000000 < 1048576 = 2^20$, so one million needs a $20$-bit number — confirmed.
]

#exercise("7.10", 3)[
  (The doubling intuition, made rigorous.) The chapter claimed a sheet of paper folded $42$ times reaches the Moon. The Moon is about $384,000$ km away; paper is about $0.1$ mm thick. (a) Write the thickness after $n$ folds as a formula. (b) Solve for the number of folds $n$ that first exceeds the Earth–Moon distance, using logarithms — show your use of the change-of-base or the product law. (c) Explain in one sentence why the answer is so astonishingly small.
]
#solution("7.10")[
  (a) Each fold doubles the thickness, so after $n$ folds the thickness is $t(n) = 0.1 "mm" times 2^n$. (b) We need $t(n) >= 384,000 "km"$. Convert to millimetres: $384,000 "km" = 384,000 times 10^6 "mm" = 3.84 times 10^11 "mm"$. So $0.1 times 2^n >= 3.84 times 10^11$, i.e. $2^n >= 3.84 times 10^12$. Take $log_2$ of both sides (it preserves the inequality since the log is increasing): $n >= log_2(3.84 times 10^12) = (log_10(3.84 times 10^12))/(log_10 2) approx 12.584 / 0.30103 approx 41.8$. The first whole number above $41.8$ is $42$, so $42$ folds suffice. (c) Because doubling is *exponential*: the thickness multiplies by $2$ every fold, and exponentials overrun any fixed target with a tiny exponent — the same reason a few dozen bits can name an astronomically large set of possibilities.
]

== Further reading

- John Napier, _Mirifici Logarithmorum Canonis Descriptio_ (1614) — the founding text; the preface (quoted in this chapter's epigraph) states the goal of replacing multiplication by addition. Scanned at the #link("https://archive.org/details/bim_early-english-books-1475-1640_mirifici-logarithmorum-c_napier-john_1614_0")[Internet Archive].
- "History of logarithms," #link("https://en.wikipedia.org/wiki/History_of_logarithms")[Wikipedia] — a reliable survey of Napier, Bürgi, and Briggs, and the move to base 10.
- "e (mathematical constant)," #link("https://en.wikipedia.org/wiki/E_(mathematical_constant)")[Wikipedia], and the MacTutor #link("https://mathshistory.st-andrews.ac.uk/HistTopics/e/")[history of $e$] — for Bernoulli's compound-interest discovery and Euler's 1731 naming.
- C. E. Shannon, "A Mathematical Theory of Communication," _Bell System Technical Journal_ (1948) — where $-log_2 p$ and the bit are born; we read it in depth in Chapter 18.
- C. E. Shannon, "Prediction and Entropy of Printed English," _Bell System Technical Journal_ (1951) — the source of the "1–1.5 bits per letter" estimate for English used in this chapter.

#bridge[
  We can now read the language of growth and measure surprise in bits with the formula $-log_2 p$. But that formula has a quiet assumption baked into it: that we *know* the probabilities, and that there is a fixed *number of possibilities* to begin with. Where do those counts come from? How many ways can you arrange a deck of cards, choose a committee, or fill a file? Chapter 8, *Counting and Combinatorics*, builds the machinery of counting — permutations, combinations, the multiplication principle — and uses it to prove, rigorously, the pigeonhole bound we sketched here: that no compressor can shrink every input. After that, Chapter 9 will give probability itself a firm foundation, so that the $p$ in $-log_2 p$ stops being a hand-wave and becomes a measured, principled thing.
]
