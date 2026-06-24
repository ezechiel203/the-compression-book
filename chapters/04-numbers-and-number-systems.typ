#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Numbers and Number Systems

#epigraph[
  "The whole of arithmetic now appeared within the grasp of mechanism."
][Charles Babbage, _Passages from the Life of a Philosopher_ (1864)]

Hold up two hands and you can count to ten. That is not a law of mathematics. It is an accident of anatomy. If our ancestors had grown eight fingers, you would be reading a book whose computers run on base 8 and whose programmers argue about octal the way ours argue about hex. The number *ten* has no special powers. It is just the size of the club we happened to count on.

Here is the puzzle that opens this chapter. A computer has no fingers at all. Deep inside, every chip is a vast city of tiny switches, and a switch knows only two states: *on* or *off*, current or no current, the way a light switch on your wall is either up or down. From that brutal poverty (two states, nothing more) a machine must somehow represent the number of atoms in the sun, the blue of a summer sky, the opening chord of a song, the letter you are reading right now. How? And, for our purposes: when we say a file is "compressed to 4,196 bytes," what *is* a byte, what is a bit, and how do those switches add up to a number we can shrink?

That is the whole job of this chapter. We will start from the most ordinary thing you know (counting on your fingers) and rebuild it so carefully that by the end you will read binary, octal, and hexadecimal the way you read English, convert between them by hand, and understand exactly how a computer stores a negative number without ever writing a minus sign. None of it requires anything you didn't learn by ninth grade. It only requires that we slow down and look hard at something we usually take for granted.

#recap[
  In Chapter 1 we met the grand idea of compression: a *model* that predicts data and a *coder* that writes down the surprises, shrinking files without losing them. In Chapter 2 we walked the history from Morse to the modern codecs, and in Chapter 3 we drew the line between *information* and *data*: data is the physical stuff (the symbols, the marks, the switches) that carries information. We kept saying "bits" and "bytes" as if you already knew them. Now we pay that debt. This chapter builds the number systems those bits and bytes live in, completely from scratch, so that every later chapter can talk about a 32 KB window or an 8-bit sample and mean something precise.
]

#objectives((
  [Explain what *place value* really is, and why it (not the digits) is the deep idea behind every number system.],
  [Read and write numbers in *binary* (base 2), *octal* (base 8), and *hexadecimal* (base 16), and say why a computer prefers base 2.],
  [Convert any whole number between decimal, binary, octal, and hex by hand, in both directions, and check your work.],
  [Convert fractions and explain why $0.1$ in decimal has no exact binary form, a fact that haunts compression of scientific data.],
  [Count *bits*, *nibbles*, *bytes*, and *words*, and compute how many distinct values a given number of bits can hold.],
  [Represent negative whole numbers in *two's complement*, the scheme almost every real computer uses, and prove why it works.],
  [Prove three small but load-bearing facts: the place-value formula, the doubling rule for bits, and the two's-complement negation identity.],
))

== Counting before there were numbers

Long before anyone wrote a numeral, people *counted*. A shepherd with a flock and no word for "forty-seven" could still keep his sheep honest: each morning, as a sheep left the pen, he dropped a pebble into a pouch; each evening, as a sheep returned, he took one out. An empty pouch at dusk meant every sheep was home. He never *named* the number forty-seven, yet he tracked it perfectly. The Latin word for pebble is _calculus_, which is where our word *calculate* comes from. Counting is older than arithmetic, and arithmetic is older than writing.

The pebble trick reveals something. The shepherd used a *one-to-one correspondence*: one pebble for one sheep. This is counting in its purest form, pairing the thing you want to count with tokens you already understand. A tally on a cave wall does the same: one scratch, one thing. Five thousand years ago in Mesopotamia, clerks pressed marks into wet clay; the marks were tokens for jars of oil and bushels of grain. The marks *were* the data; the count of grain *was* the information. (You will recognise that distinction from Chapter 3.)

Tally marks have a fatal flaw, though, and spotting it is the first real idea of this chapter. To write the number two hundred, you would scratch two hundred marks. To write two million, you would die of old age first. Tally marks grow as fast as the thing they count. They do not *compress*. We need numerals that grow *slowly*, where huge numbers take few symbols. The trick that makes that possible is the single most important idea in this chapter, and we turn to it now.

#keyidea[
  Counting is pairing things with tokens. *Numerals* are a written shorthand for counts. A _good_ numeral system lets enormous numbers be written with very few symbols. It compresses the count. Tally marks fail at this; place value succeeds spectacularly. Everything else in this chapter is a variation on that one triumph.
]

== Place value: the idea worth a civilisation

Look hard at the number $327$. Read it aloud: "three hundred twenty-seven." You just did something so automatic you never noticed it. The leftmost $3$ does not mean "three." It means *three hundreds*. The middle $2$ means *two tens*. The rightmost $7$ means *seven ones*. The very same digit means different amounts depending on *where it sits*. That is *place value*, and it is a genuinely deep idea, so deep that the Romans, for all their roads and aqueducts, never had it, which is why multiplying `MMMCDXXVII` by `XLII` was a job for specialists.

Let us write out exactly what $327$ means. Going right to left, each position is worth ten times the one before it:

$ 327 = 3 times 100 + 2 times 10 + 7 times 1 = 3 times 10^2 + 2 times 10^1 + 7 times 10^0. $

#gomaths("Powers and exponents")[
  An *exponent* is just repeated multiplication written in shorthand. The little raised number (the *exponent*) counts how many copies of the *base* you multiply together. So $10^3 = 10 times 10 times 10 = 1000$ (three tens), and $2^4 = 2 times 2 times 2 times 2 = 16$ (four twos). Read $10^3$ as "ten to the third" or "ten cubed."

  Two facts we will lean on. First, *anything to the power zero is one*: $10^0 = 1$, $2^0 = 1$, $16^0 = 1$. That looks like a trick, but it falls out of a pattern. Watch the powers of ten *shrink*: $10^3 = 1000$, $10^2 = 100$, $10^1 = 10$, and each step divides by ten, so the next step, $10^0$, must be $10 div 10 = 1$. The zero power is the "ones" slot. Second, multiplying two powers of the same base *adds* the exponents: $10^2 times 10^3 = 10^(2+3) = 10^5$, because you are just lining up two-tens-then-three-tens in a row. We meet this rule again, in full, in Chapter 7; here we only need the two facts above. A tiny check: $2^0 + 2^1 + 2^2 + 2^3 = 1 + 2 + 4 + 8 = 15$.
]

So $327$ in base ten is really a tidy sum of digits times powers of ten. The digits answer "how many of each power?" and the powers do the heavy lifting. The reason ten is the base is the fingers we started with, nothing more. Pick any base you like and the same machine runs.

#definition("Positional numeral system")[
  Choose a whole number $b >= 2$, the *base* (or *radix*). Allow exactly $b$ digit symbols, standing for the values $0, 1, 2, dots, b-1$. Then a string of digits $d_k d_(k-1) dots d_1 d_0$ denotes the number
  $ d_k b^k + d_(k-1) b^(k-1) + dots + d_1 b^1 + d_0 b^0. $
  The position of a digit, counted from the right starting at $0$, is its *place*; the value of a place is $b$ raised to that place. Base ten is the everyday case ($b = 10$, digits $0$–$9$).
]

Two things deserve a hard stare. First, a base-$b$ system needs *exactly* $b$ digit symbols, no more, no fewer. Base ten has ten ($0$ through $9$); there is deliberately no single symbol for "ten," because ten is written by *moving to a new place*: $10$. Second, the largest digit is always $b - 1$, never $b$. In base ten the biggest digit is $9$; the moment you would need a "ten," you carry. That carry ("I have run out of digits, so I bump the next place up by one and reset to zero") is the heartbeat of every counting system. A car's odometer rolling from $0 0 9$ to $0 1 0$ is place value in steel.

#theorem("Place-value expansion is unique")[
  For any base $b >= 2$ and any whole number $n >= 0$, there is exactly one way to write $n$ as a sum $sum_(i=0)^k d_i b^i$ with each digit $d_i$ in ${0, 1, dots, b-1}$ and the top digit $d_k != 0$ (except that $n = 0$ is written as the single digit $0$).
]

#proof[
  We show you can always *find* such digits and that you can find only *one* set. To find them, repeatedly divide by $b$. Divide $n$ by $b$; the remainder is a number between $0$ and $b - 1$: that is your rightmost digit $d_0$. The quotient is what is left over in the higher places; divide *it* by $b$ to get $d_1$, and so on, until the quotient reaches $0$. Each remainder is a legal digit by construction, so the process produces a valid expansion, and because each division strictly shrinks the quotient, it must stop. That proves existence.

  For uniqueness, suppose $n$ had two different digit strings. Look at the rightmost place where they differ. Everything to the right of that place contributes the same amount in both (they agree there), and everything from that place leftward is a multiple of $b^i$ for that place's power $b^i$. But the digit in that place is exactly the remainder of $(n - "lower places") div b^i$ modulo $b$, and a remainder is unique, since a number divided by $b$ has only one remainder. So the two digits must be equal after all, contradicting the assumption that they differed. Hence the expansion is unique. #h(1fr)
]

That "repeatedly divide by the base, collect the remainders" recipe is not merely a proof device. It is the actual algorithm we will use all chapter to convert numbers into any base. Tuck it away; we are about to run it many times.

#checkpoint[
  In base ten, what is the largest digit, and what number forces a carry into a brand-new leftmost place when you start from $999$ and add one?
][The largest digit is $9$ (always $b - 1$, and here $b = 10$). Adding one to $999$ makes every place roll over ($9 -> 0$ with a carry, three times), producing $1000$, a number with a new fourth place. That cascade of carries is exactly what place value is built to handle.]

== Why a computer counts in twos

Now we earn the chapter's central move. A computer is built from switches, and a switch has two stable states. We could try to build a switch with ten distinguishable states, say ten different voltage levels on a wire from $0$ to $9$ volts, and run base ten directly. People tried. It is a nightmare. Wires pick up noise; a $5$-volt level sags to $4.6$ or spikes to $5.3$, and now your circuit cannot tell a "five" from a "four" or a "six." With ten levels crammed into a few volts, the gaps are tiny and the errors constant.

Two states fixes everything. Make "off" mean roughly zero volts and "on" mean roughly the supply voltage, with a wide no-man's-land between. Now a sag or a spike has to cross a huge gap before it flips the reading. The hardware becomes cheap, fast, and stubbornly reliable. So computers count in *base 2* (*binary*), not because two is mathematically special, but because two states are the easiest thing in the universe to build and keep honest. Every "deep" fact about computers traces back to this very practical compromise.

In base 2 the rules are identical to base ten; only the base changes. There are exactly two digits, $0$ and $1$. Each one is a *bit*, short for *binary digit*, a name coined by the statistician John Tukey and made famous by Claude Shannon (whom we will meet properly in Chapter 18). The places are now powers of *two*: $1, 2, 4, 8, 16, 32, dots$, each double the last. So the binary string $101$ means

$ 101_2 = 1 times 2^2 + 0 times 2^1 + 1 times 2^0 = 4 + 0 + 1 = 5. $

The little subscript $2$ is our way of shouting "read this in base 2!" so nobody mistakes $101_2$ (which is five) for the decimal $101$ (one hundred one). Where the base is obvious we drop it. When in doubt, label.

#definition("Bit, and binary")[
  A *bit* is a single binary digit: it is either $0$ or $1$. *Binary* is the base-2 positional system: its places, from the right, are worth $2^0 = 1$, $2^1 = 2$, $2^2 = 4$, $2^3 = 8$, $2^4 = 16$, and so on, each twice the one before. A binary number is a string of bits, and its value is the sum of the place values where a $1$ appears.
]

#fig([The place values of an 8-bit binary number. Each box is one bit; the value printed above it is that place's worth ($2^"position"$). The byte shown, $0 1 0 0 1 0 1 1$, equals $64 + 8 + 2 + 1 = 75$.],
  cetz.canvas({
    import cetz.draw: *
    let bits = (0, 1, 0, 0, 1, 0, 1, 1)
    let vals = (128, 64, 32, 16, 8, 4, 2, 1)
    for i in range(8) {
      let x = i * 1.35
      rect((x, 0), (x + 1.2, 1.0), fill: if bits.at(i) == 1 { rgb("#cfe3f3") } else { white })
      content((x + 0.6, 0.5))[#text(size: 13pt)[#bits.at(i)]]
      content((x + 0.6, 1.32))[#text(size: 8pt, fill: rgb("#0b5394"))[#vals.at(i)]]
      content((x + 0.6, -0.32))[#text(size: 7pt, fill: rgb("#783f04"))[$2^#(7 - i)$]]
    }
    content((5.4, -1.0))[#text(size: 9pt)[value $= 64 + 8 + 2 + 1 = 75$]]
  }))

Counting in binary, then, goes exactly like an odometer with only two figures on each wheel. Start at $0$. Add one: $1$. Add one again, but $1$ is the biggest binary digit, so it rolls over to $0$ and carries, giving $10$ (which is *two*, not ten). Keep going: $11$ (three), then a double carry to $100$ (four), $101$ (five), $110$ (six), $111$ (seven), $1000$ (eight). Notice the pattern: a binary number made of all ones, like $111$, is one less than the next power of two. Specifically, $111_2 = 8 - 1 = 7$. That little fact ("all ones is one below the next power of two") will save you arithmetic again and again.

#table(columns: (auto, auto, auto, auto), inset: 6pt, align: (right, right, right, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Decimal*], [*Binary*], [*Powers present*], [*Read as*]),
  [0], [`0`], [–], [zero],
  [1], [`1`], [$2^0$], [one],
  [2], [`10`], [$2^1$], [two],
  [3], [`11`], [$2^1 + 2^0$], [three],
  [4], [`100`], [$2^2$], [four],
  [5], [`101`], [$2^2 + 2^0$], [five],
  [6], [`110`], [$2^2 + 2^1$], [six],
  [7], [`111`], [$2^2 + 2^1 + 2^0$], [seven],
  [8], [`1000`], [$2^3$], [eight],
)

#aside[
  There is an old programmer's joke: "There are 10 kinds of people in the world: those who understand binary, and those who don't." It only lands once you read $10$ as *two*. If you smiled, you have already internalised that the symbols $1$ and $0$ mean nothing until you know the base. That is the whole lesson of this chapter wrapped in a groan.]

== Converting decimal to binary, by hand

We already have the algorithm. It fell out of the uniqueness proof above. To write a decimal number in binary, *repeatedly divide by 2 and read the remainders from bottom to top*. Let us convert $75$ to binary, the same number from our figure, and watch it work.

Divide and record the remainder each time. The remainder is always $0$ or $1$, which is exactly one bit:

#table(columns: (auto, auto, auto, auto), inset: 6pt, align: (right, right, right, right),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Step*], [*Divide*], [*Quotient*], [*Remainder (bit)*]),
  [1], [$75 div 2$], [$37$], [`1`],
  [2], [$37 div 2$], [$18$], [`1`],
  [3], [$18 div 2$], [$9$], [`0`],
  [4], [$9 div 2$], [$4$], [`1`],
  [5], [$4 div 2$], [$2$], [`0`],
  [6], [$2 div 2$], [$1$], [`0`],
  [7], [$1 div 2$], [$0$], [`1`],
)

Stop when the quotient hits $0$. Now read the remainder column *upward*, from the last division to the first: $1 0 0 1 0 1 1$. So $75 = 1001011_2$. Check it the easy way, by adding the place values where a $1$ sits: $64 + 8 + 2 + 1 = 75$. It matches. Reading the remainders bottom-to-top feels backwards the first time; the reason is that the *first* division peels off the *smallest* place (the ones bit), and the *last* division gives the *largest* place (the top bit), so the bits come out least-significant first and must be reversed.

#keyidea[
  *Two directions, two recipes.* To go *from* base $b$ *to* decimal, multiply each digit by its place value and add (the definition). To go *from* decimal *to* base $b$, repeatedly divide by $b$ and read the remainders backwards. These two recipes ("weigh and sum" one way, "divide and collect" the other) convert between decimal and *any* base. Learn them once; they never change.
]

There is a second, often faster way for binary specifically: *subtract the biggest power of two you can, repeatedly.* The powers of two are $1, 2, 4, 8, 16, 32, 64, 128, 256, dots$. To convert $75$: the biggest power $<= 75$ is $64$, so place a $1$ in the $64$s place and subtract, leaving $11$. The biggest power $<= 11$ is $8$, so a $1$ in the $8$s place, leaving $3$. Then $2$ fits ($1$ in the $2$s place, leaving $1$), then $1$ fits ($1$ in the ones place, leaving $0$). Every place we skipped gets a $0$. Reading the places $64, 32, 16, 8, 4, 2, 1$ we get $1, 0, 0, 1, 0, 1, 1$, the same $1001011_2$. Use whichever method your brain likes; they cannot disagree, because the place-value expansion is unique.

#checkpoint[
  Convert the decimal number $44$ to binary using the divide-by-two method, then check by summing place values.
][Dividing: $44 div 2 = 22$ r $0$; $22 div 2 = 11$ r $0$; $11 div 2 = 5$ r $1$; $5 div 2 = 2$ r $1$; $2 div 2 = 1$ r $0$; $1 div 2 = 0$ r $1$. Reading remainders bottom-to-top: $101100_2$. Check: $32 + 8 + 4 = 44$. Correct.]

== Bits, nibbles, bytes, and words

A single bit is a tiny thing: it answers exactly one yes-or-no question. On its own it can tell you whether a light is on, a box is ticked, a coin came up heads. To say anything richer we gather bits into groups, and the groups have names that you will meet in every compression format for the rest of the book.

How much can a group of bits say? Here is the rule, and it is worth proving because the whole field of compression lives or dies on it. With $n$ bits you can make exactly $2^n$ different patterns, and so represent $2^n$ different values.

#theorem("The doubling rule for bits")[
  A string of $n$ bits has exactly $2^n$ distinct possible patterns.
]

#proof[
  Build the string one bit at a time and count as you go. With one bit you have $2$ patterns: `0` and `1`. Now suppose a string of length $n$ already has some number of patterns; call it $P$. Extend every one of those patterns by one more bit. That new bit can be either `0` or `1`, so each old pattern becomes *two* new patterns of length $n + 1$ (one ending in `0`, one ending in `1`), and no two of these collide, because they differ either in the old part or in the final bit. So the count doubles at every step: $1$ bit gives $2$, then $4$, then $8$, then $16$. Starting from $2^1 = 2$ and doubling $n - 1$ more times lands on $2^n$. (And the empty string, $n = 0$, has the single "pattern" of nothing at all, matching $2^0 = 1$.) #h(1fr)
]

This single theorem is why a byte holds $256$ values and why an "8-bit" colour channel has $256$ shades. Looking further ahead, it also explains why no compressor can shrink every file: there simply aren't enough short bit-strings to go around, a *counting bound* we will prove rigorously in Chapter 8. For now, just internalise the table: each extra bit *doubles* your reach.

#table(columns: (auto, auto, 1fr), inset: 6pt, align: (right, right, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Bits ($n$)*], [*Distinct values ($2^n$)*], [*Enough to label…*]),
  [1], [2], [a coin flip],
  [2], [4], [the four card suits],
  [3], [8], [the eight points of a compass],
  [4], [16], [one hexadecimal digit (soon!)],
  [8], [256], [a byte: every value $0$–$255$],
  [10], [1 024], [≈ a "kilo" of things],
  [16], [65 536], [a "short" integer; a CD-audio sample],
  [32], [4 294 967 296], [≈ 4.3 billion: IPv4 addresses],
)

Now the names. Four bits are a *nibble* (yes, really, half a byte, and the pun is intentional). One nibble holds $2^4 = 16$ values, which is exactly why hexadecimal, coming up next, fits a nibble like a glove. Eight bits are a *byte*, the workhorse unit of computing: $2^8 = 256$ values, enough for every letter, digit, and punctuation mark of early computing with room to spare. The byte is the smallest chunk most computers will hand you individually; you address memory and measure files in bytes, not bits. A group the processor likes to chew in one bite is a *word*, whose width depends on the machine (modern laptops and phones use 64-bit words), so "word" is a relative term while "byte" is nailed down at eight bits.

#definition("Nibble, byte, word")[
  A *nibble* is a group of $4$ bits ($16$ possible values). A *byte* is a group of $8$ bits ($256$ possible values) and is the standard addressable unit of storage; file sizes are counted in bytes. A *word* is the natural group of bits a particular processor operates on at once (commonly $16$, $32$, or $64$ bits); its width is a property of the machine, not a fixed number.
]

#note[
  When a download says "8 MB" it means about eight million *bytes*; when your internet plan says "100 Mbps" it means a hundred million *bits* per second. Bytes are usually written with a capital `B`, bits with a lowercase `b`. Since a byte is eight bits, that "100 Mbps" line delivers only about $12.5$ MB each second. Marketers love quoting the bigger-sounding bit number. Compression, mercifully, is almost always measured in bytes, the unit that matches what a file actually occupies on disk.
]

#gopython("Reading a byte's value in Python")[
  Python is the language we will build `tinyzip` in across this book, and we will teach it from zero, one feature at a time, exactly as we teach the maths. Today's morsel: Python already speaks every base in this chapter. You write a literal number in binary by prefixing `0b`, in octal with `0o`, and in hexadecimal with `0x`. Type a few lines into the Python prompt (the `>>>` is Python inviting you to type; you don't type it yourself):

  ```python
  >>> 0b1001011        # binary for seventy-five
  75
  >>> 0x4B             # hexadecimal for seventy-five
  75
  >>> bin(75)          # turn a number into its binary text
  '0b1001011'
  >>> 75 == 0b1001011 == 0x4B   # all three are the SAME number
  True
  ```

  The `#` starts a *comment*, a note for humans that Python ignores. The lesson: $75$, `0b1001011`, and `0x4B` are three spellings of one value. The base is just how we *wrote* it down; the number underneath is the same. We will explain `bin()`, strings (the quoted text), and `==` properly in the Python-primer chapters (15–17); here, just notice that the machine agrees with our hand arithmetic.
]

== Octal and the trouble with long binary

Binary is perfect for machines and miserable for humans. Quick: is $1010110110010111$ bigger or smaller than $1010110101010111$? Your eyes glaze; the bits blur; you lose count of the zeros. We need a shorthand that a person can read at a glance but that still maps cleanly onto bits. The trick is to group bits into fixed-size bundles and give each bundle its own symbol.

Group binary digits into *threes* and you have invented *octal*, base 8. Why threes? Because three bits make exactly $2^3 = 8$ patterns, which is precisely the eight digits of base 8: $0, 1, 2, 3, 4, 5, 6, 7$. Each group of three bits becomes one octal digit, and back again, with no arithmetic required. Just a lookup.

#table(columns: (auto, auto), inset: 5pt, align: (center, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*3 bits*], [*Octal digit*]),
  [`000`], [0], [`001`], [1], [`010`], [2], [`011`], [3],
  [`100`], [4], [`101`], [5], [`110`], [6], [`111`], [7],
)

To turn a binary number octal, split it into threes *from the right* (padding the left with zeros if needed) and replace each triple. Take $1001011_2$ (our friend $75$). Split from the right: $1 | 001 | 011$, pad the short left group to $001 | 001 | 011$, then translate: $1, 1, 3$. So $75 = 113_8$. Check by place value, with octal places worth $1, 8, 64$: $1 times 64 + 1 times 8 + 3 times 1 = 64 + 8 + 3 = 75$. It holds.

Octal had its heyday on early machines whose word sizes were multiples of three bits (the PDP-8, for instance, used 12-bit words that split into four neat octal digits). You will still meet octal in one stubborn corner of modern life: Unix file permissions, where `chmod 755` is three octal digits, each a triple of yes/no bits for read, write, and execute. But for most of computing, octal lost a beauty contest to a rival that groups bits into *fours* instead of threes, and four is the magic number because four bits is a nibble and two nibbles is a byte. That rival is hexadecimal.

== Hexadecimal: the language byte-watchers speak

Group bits into *fours* and you get *hexadecimal*, base 16, universally shortened to *hex*. Four bits make $2^4 = 16$ patterns, so base 16 needs sixteen digit symbols. We have only ten numerals ($0$–$9$), so hex borrows the first six letters of the alphabet for the values ten through fifteen: `A` is ten, `B` eleven, `C` twelve, `D` thirteen, `E` fourteen, `F` fifteen. (Lower-case `a`–`f` mean the same; case is just style.) That is the only thing that ever trips people up about hex, and once you've memorised "`A` is ten, `F` is fifteen," you own it.

#table(columns: (auto, auto, auto), inset: 5pt, align: (center, center, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*4 bits*], [*Hex*], [*Decimal*]),
  [`0000`], [`0`], [0], [`0001`], [`1`], [1], [`0010`], [`2`], [2], [`0011`], [`3`], [3],
  [`0100`], [`4`], [4], [`0101`], [`5`], [5], [`0110`], [`6`], [6], [`0111`], [`7`], [7],
  [`1000`], [`8`], [8], [`1001`], [`9`], [9], [`1010`], [`A`], [10], [`1011`], [`B`], [11],
  [`1100`], [`C`], [12], [`1101`], [`D`], [13], [`1110`], [`E`], [14], [`1111`], [`F`], [15],
)

Here is why programmers reach for hex constantly: *one hex digit is exactly one nibble, so two hex digits are exactly one byte.* A byte ranges over $0$–$255$, which is precisely `00` to `FF` in hex, always two digits, never more, never fewer. That tidy fit makes hex the natural script for anything byte-level: memory dumps, colour codes (the web's `#FF8800` is three bytes for red, green, and blue), file signatures, and the headers of every compression format you will dissect later in this book. When you open a `.png` or `.gz` file in a hex editor, you are reading bytes two hex digits at a time.

Let us convert our running number. $75$ in binary is $0100 | 1011$ (padded to eight bits, split into two nibbles). The left nibble $0100$ is $4$; the right nibble $1011$ is $11$, which is `B`. So $75 = "4B"_16$, written `0x4B` in code. Check by place value, with hex places worth $1, 16, 256$: $4 times 16 + 11 times 1 = 64 + 11 = 75$. That holds. Notice too how the byte we drew way back in the figure, `01001011`, is just "4B" seen through nibble glasses.

#history[
  The word *hexadecimal* is a Greek–Latin mongrel ("hexa-" for six from Greek, "-decimal" for ten from Latin) that purists grumble about to this day; the tidier all-Greek *sexadecimal* never caught on. The notation has older roots than people assume: a base-16 system was floated by the English schoolmaster Thomas Wright Hill back in 1845, and the word "hexadecimal" itself appears in computing as early as 1950, attached to the Standards Eastern Automatic Computer (SEAC). The convention that *won* (using the letters `A` through `F` for ten through fifteen) was popularised by IBM around 1963 and cemented as the de-facto standard from 1966 onward, in the wake of the Fortran IV manual for the IBM System/360. Earlier machines had experimented with other symbols entirely; the Bendix G-15 of 1956, for example, used the letters `u` through `z`. We take `A`–`F` for granted now, but it was a choice, and not an obvious one.
]

#keyidea[
  *Hex is just binary wearing a compact suit.* Because $16 = 2^4$, each hex digit stands for exactly four bits; no arithmetic is needed to convert, only a 16-row lookup. Two hex digits = one byte = the unit files are measured in. This is why hex, not octal and not decimal, is the working language of everyone who handles raw bytes directly, including everyone who builds a compressor.
]

#misconception[Hexadecimal is some exotic, advanced kind of number, fundamentally different from "normal" numbers.][Hex is the *same* numbers you have always known, written in base 16 instead of base 10. `0xFF` and $255$ are not cousins; they are the identical number in two outfits. The only genuinely new thing is using six letters as extra digits, and that is a notational convenience, not a new mathematics. A compressed file's size of $4196$ bytes is `0x1064` bytes; same count, different spelling.]

#checkpoint[
  Convert the byte `11101010` to hexadecimal, then to decimal, using nibbles.
][Split into nibbles: `1110` and `1010`. From the table, `1110` is `E` (fourteen) and `1010` is `A` (ten). So the byte is `0xEA`. In decimal, $14 times 16 + 10 = 224 + 10 = 234$. (Sanity check by summing set bits: $128 + 64 + 32 + 8 + 2 = 234$.)]

== Converting between any two bases

You now hold a master key. Every conversion in computing is some combination of two moves you already know:

+ *To decimal:* weigh each digit by its place value and add. (This is just the definition of a positional system.)
+ *From decimal:* divide repeatedly by the target base and read remainders bottom-to-top.

And one shortcut: *between binary, octal, and hex, never go through decimal at all*, just regroup the bits, since $8 = 2^3$ and $16 = 2^4$. Let us drill each route with a fresh, larger number so the methods stick. Take decimal $1{,}000$.

*Decimal to hex (divide by 16):* $1000 div 16 = 62$ remainder $8$; $62 div 16 = 3$ remainder $14$ (which is `E`); $3 div 16 = 0$ remainder $3$. Reading remainders bottom-to-top: `3`, `E`, `8`, so $1000 = "3E8"_16$. Check: $3 times 256 + 14 times 16 + 8 = 768 + 224 + 8 = 1000$. ✓

*Hex to binary (expand each digit to a nibble):* `3` is `0011`, `E` is `1110`, `8` is `1000`. Stitch them together: $0011 1110 1000$, i.e. $1111101000_2$ once we drop the leading zeros. Check by summing: $512 + 256 + 128 + 64 + 32 + 8 = 1000$. ✓

*Binary to octal (regroup into threes):* take $1111101000_2$ and split from the right into triples: $1 | 111 | 101 | 000$, pad the left group to $001$: $001 | 111 | 101 | 000 = 1, 7, 5, 0$. So $1000 = 1750_8$. Check: $1 times 512 + 7 times 64 + 5 times 8 + 0 = 512 + 448 + 40 = 1000$. ✓

Four bases, one number, and every answer agrees, because, by our uniqueness theorem, they *must*. That is the quiet power of place value: change the base and the *spelling* changes, but the number underneath is rock-solid. Notice especially how binary→hex and binary→octal needed *no division at all*, only regrouping. When you see a programmer rattle off "that's `0x3E8`" while staring at a binary dump, this nibble-regrouping is the trick. There is no arithmetic involved, just slicing the bits into fours.

#table(columns: (auto, auto, auto, auto, 1fr), inset: 6pt, align: (center, center, center, center, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Decimal*], [*Binary*], [*Octal*], [*Hex*], [*How read*]),
  [75], [`1001011`], [`113`], [`4B`], [our running byte],
  [255], [`11111111`], [`377`], [`FF`], [the biggest byte],
  [1000], [`1111101000`], [`1750`], [`3E8`], [worked above],
  [4096], [`1000000000000`], [`10000`], [`1000`], [exactly $2^12$],
)

#aside[
  That last row is a gift. $4096 = 2^12$ is `0x1000` in hex (a one followed by three zeros) because each hex zero "absorbs" four bits, and $12 = 4 times 3$. The same logic makes $256 = 2^8$ equal to `0x100` and $16 = 2^4$ equal to `0x10`. Whenever an exponent of two is a multiple of four, its hex form is a clean power-of-sixteen "1 followed by zeros." Memorise a handful ($2^8 = "100"$, $2^12 = "1000"$, $2^16 = "10000"$ in hex) and you will read memory sizes without a calculator forever.]

== Fractions, and the number that won't sit still

So far, whole numbers. But data is full of fractions: a temperature of $0.1$ degrees, an audio sample at $0.5$ of full volume, a probability of $0.3$. Place value handles fractions by continuing the powers *past the dot*, into negative exponents. In decimal, the places to the right of the point are worth $10^(-1) = 1\/10$, $10^(-2) = 1\/100$, and so on. So $0.327 = 3\/10 + 2\/100 + 7\/1000$.

#gomaths("Negative exponents are reciprocals")[
  We met positive exponents as repeated multiplication. A *negative* exponent means "divide instead of multiply": it is the reciprocal (the "one-over") of the positive power. So $10^(-1) = 1\/10 = 0.1$, and $2^(-1) = 1\/2 = 0.5$, and $2^(-3) = 1\/2^3 = 1\/8 = 0.125$. Why? Keep the doubling-pattern going *downward* past zero: $2^2 = 4$, $2^1 = 2$, $2^0 = 1$, and each step halves, so the next step $2^(-1)$ must be $1 div 2 = 0.5$, then $2^(-2) = 0.25$, then $2^(-3) = 0.125$. The places after a binary point are therefore worth $1\/2, 1\/4, 1\/8, 1\/16, dots$ (halves, quarters, eighths). A quick check: $0.5 + 0.25 = 0.75$, which in binary is $0.11_2$.
]

In binary, the places after the *binary point* are worth $1\/2, 1\/4, 1\/8, 1\/16, dots$. So the binary fraction $0.101_2$ means $1\/2 + 0 + 1\/8 = 0.5 + 0.125 = 0.625$. To convert a decimal fraction *to* binary we mirror the whole-number recipe, but instead of dividing we *multiply by two and harvest the whole-number part each time*. Convert $0.625$:

#table(columns: (auto, auto, auto), inset: 6pt, align: (right, right, center),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Multiply by 2*], [*Result*], [*Bit harvested*]),
  [$0.625 times 2$], [$1.25$], [`1`],
  [$0.25 times 2$], [$0.50$], [`0`],
  [$0.50 times 2$], [$1.00$], [`1`],
)

Read the harvested bits *top to bottom* (the reverse of the whole-number rule, because here the first bit is the *largest* fractional place): $0.625 = 0.101_2$. We stopped because the leftover fraction hit exactly $0$. That clean stop is the happy case. The unhappy case is more important for our purposes, and it is the most revealing example in this whole chapter for anyone who will ever compress scientific data.

Try to convert the innocent-looking $0.1$ to binary:

#table(columns: (auto, auto, 1fr), inset: 6pt, align: (right, right, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Multiply by 2*], [*Result*], [*Bit harvested*]),
  [$0.1 times 2$], [$0.2$], [`0`],
  [$0.2 times 2$], [$0.4$], [`0`],
  [$0.4 times 2$], [$0.8$], [`0`],
  [$0.8 times 2$], [$1.6$], [`1`],
  [$0.6 times 2$], [$1.2$], [`1`],
  [$0.2 times 2$], [$0.4$], [`0` (repeats from $0.2$)],
)

The leftover fraction returns to $0.2$ and the whole block `0011` repeats forever: $0.1 = 0.0001100110011001dots_2$, a *non-terminating, repeating binary fraction*. The decimal $0.1$ (which looks so finite and tidy on paper) simply has *no exact representation in binary*, the way $1\/3 = 0.3333dots$ has no exact representation in decimal. The reason is pure arithmetic: a fraction terminates in base $b$ only when its denominator's prime factors all divide $b$. In base $10 = 2 times 5$, denominators built from $2$s and $5$s terminate; in base $2$, only denominators that are powers of two terminate. The denominator of $1\/10$ contains a $5$, and $5$ does not divide $2$, so $0.1$ can never close in binary. No amount of cleverness fixes this; it is a fact about the numbers themselves.

#pitfall[
  This is not a quirky curiosity. It bites real software daily. Because a computer must *stop* the infinite binary expansion of $0.1$ somewhere (we will see exactly how when we reach floating-point in Chapter 13), it stores a number a hair away from $0.1$. That is why, in nearly every programming language, `0.1 + 0.2` does not equal `0.3` exactly but something like `0.30000000000000004`. For compression this matters enormously: a scientific dataset full of values that "should" be $0.1$ may, after rounding, yield a thousand *slightly different* bit-patterns. A compressor that expects repetition then sees apparent randomness and fails. That is precisely why specialised floating-point and error-bounded codecs (Chapter 66) exist. The humble inability of $0.1$ to sit still in binary is a multi-billion-dollar problem in disguise.
]

#tryit[
  The compressors we build later will, sooner or later, need to print bytes in hex for debugging and to reason about values in binary. The most basic literacy of all is converting between bases, so let us make this chapter's two recipes runnable. We will write two tiny functions by hand (even though Python has built-ins) because *implementing the divide-and-collect algorithm yourself* cements it. We will lean on Python's own tools later; for now we re-derive the wheel to understand it.

  This is a warm-up sketch, not yet part of the real `tinyzip` package. That project proper starts in Chapter 15, where we lay down the package skeleton. Think of the code below as finger exercises in base conversion that you can type straight into the Python prompt.

  ```python
  # base conversion warm-up  -  Chapter 4 (run it in the REPL)

  DIGITS = "0123456789ABCDEF"   # symbol for each value 0..15

  def to_base(n: int, base: int) -> str:
      """Write the whole number n in the given base (2..16) as text."""
      if n == 0:
          return "0"
      out = ""
      while n > 0:
          n, r = divmod(n, base)   # divmod gives (quotient, remainder)
          out = DIGITS[r] + out    # prepend: builds the string right-to-left
      return out

  def from_base(text: str, base: int) -> int:
      """Read text written in the given base back into a whole number."""
      value = 0
      for ch in text:
          value = value * base + DIGITS.index(ch.upper())
      return value
  ```

  The encoder is the divide-and-collect proof made executable: `divmod(n, base)` does one division and hands back both the quotient and the remainder, and prepending the digit (`out = DIGITS[r] + out`) does the "read remainders backwards" step automatically. The decoder is the weigh-and-sum definition: each new digit multiplies the running total by the base and adds itself, a slick rearrangement of place value sometimes called *Horner's method*. A quick check confirms our hand work from this chapter:

  ```python
  >>> to_base(75, 2),  to_base(75, 16),  to_base(1000, 16)
  ('1001011', '4B', '3E8')
  >>> from_base("3E8", 16),  from_base("1750", 8)
  (1000, 1000)
  ```

  Both numbers round-trip and match every conversion we did by hand. With these two helpers you can show any value in any base, exactly the perspective we will want when we start emitting and inspecting real compressed bytes from Chapter 15 onward. The type hints (`n: int`, `-> str`) and the `for` loop get their full from-scratch treatment in Chapters 15–16; read them here as plain English: "n is a whole number; this returns text."
]

== Negative numbers without a minus sign

Everything so far has been about whole numbers that are zero or bigger. But data needs negatives, too: a temperature below freezing, an audio sample that swings below the centre line, the *difference* between two pixels that a compressor stores instead of the pixels themselves (a trick we will use constantly from Chapter 25 onward). The problem is stark: a byte is eight switches, each on or off. There is no slot for a minus sign, no "negative switch." So how does a machine of pure on/off bits hold a $-5$?

The naive idea is to steal one bit to mean the sign, say leftmost bit $1$ means "negative." This is called *sign-and-magnitude*, and it is how we humans write numbers (a `-` then the size). It works, but it is a headache for the hardware, and it has an embarrassing flaw: it gives you *two zeros*. The pattern `00000000` is "positive zero" and `10000000` is "negative zero," two different bit patterns for the same nothing. Worse, the circuit that adds numbers now has to check the sign bits and branch, making addition slow and fiddly. Early computer designers wanted something better, and they found something almost magical.

The winning scheme is *two's complement*, and the idea behind it is a clock. Picture a 12-hour clock face. If it is 3 o'clock and you wind the hands *back* 4 hours, you land on 11. But you'd reach the very same 11 by winding *forward* 8 hours, because $3 + 8 = 11$ and going forward 8 is the same as going back 4 on a 12-hour wheel ($8 = 12 - 4$). On a clock, "minus 4" and "plus 8" are the same motion. Two's complement plays exactly this trick with bits: on an $n$-bit wheel of $2^n$ positions, it represents $-x$ by the forward step $2^n - x$. Subtraction becomes addition that is allowed to wrap around, and wrapping around is *free* in hardware, because an 8-bit adder naturally throws away any 9th bit that overflows.

#gomaths("Modular arithmetic: clock math")[
  *Modular arithmetic* is arithmetic that wraps around a fixed circle of numbers, exactly like a clock. On a 12-hour clock the numbers are $0$ through $11$, and after $11$ you are back to $0$. We write "$15 = 3 ("mod" 12)$" to mean "$15$ and $3$ land on the same spot on a 12-circle," because $15 - 3 = 12$ is a whole number of full laps. To reduce any number "mod 12," divide by $12$ and keep only the remainder: $15 div 12$ leaves remainder $3$, so $15 = 3 ("mod" 12)$. For $n$-bit computer arithmetic the circle has $2^n$ positions ($0$ up to $2^n - 1$), and every result is automatically taken "mod $2^n$": anything that overflows past the top simply wraps to the bottom. A tiny check on an 8-bit wheel ($2^8 = 256$): $255 + 1 = 256 = 0 ("mod" 256)$, so adding one to the all-ones byte rolls it over to all zeros, just like an odometer.
]

#definition("Two's complement")[
  Fix a width of $n$ bits. The $2^n$ bit-patterns are split down the middle: a pattern whose leftmost bit is $0$ is read as the ordinary non-negative value it would have unsigned (ranging $0$ to $2^(n-1) - 1$); a pattern whose leftmost bit is $1$ is read as that unsigned value *minus* $2^n$ (ranging $-2^(n-1)$ down to $-1$). Equivalently, the value of bits $b_(n-1) dots b_1 b_0$ is
  $ -b_(n-1) 2^(n-1) + b_(n-2) 2^(n-2) + dots + b_1 2^1 + b_0 2^0, $
  in which *only the top bit carries a minus sign* and every other bit is its usual positive place value.
]

For an 8-bit byte that means the range runs from $-128$ to $+127$. The leftmost bit is the "sign," but it is not merely a flag. It is a *place* worth $-128$, while the other seven places are the usual $+64, +32, dots, +1$. Let us decode `11111011`. Top bit is set, so it contributes $-128$; the remaining bits `1111011` contribute $64 + 32 + 16 + 8 + 0 + 2 + 1 = 123$. Total: $-128 + 123 = -5$. So `11111011` *is* negative five. No minus sign anywhere, just eight switches and an agreement about what the leftmost one means.

#fig([The 8-bit two's-complement number line drawn as a wheel of $256$ positions. Patterns with a leading `0` (right half) are $0$ to $+127$; patterns with a leading `1` (left half) are $-128$ to $-1$. Adding $1$ moves one step clockwise; the only "seam" is between $+127$ and $-128$.],
  cetz.canvas({
    import cetz.draw: *
    circle((0, 0), radius: 2.0, stroke: 0.8pt + rgb("#0b5394"))
    // mark a few key points
    let pts = (
      (0, "00000000", "0"),
      (45, "00111111", "+63"),
      (90, "01111111", "+127"),
      (135, "10000000", "-128"),
      (180, "10111111", "-65"),
      (225, "11000000", "-64"),
      (315, "11111011", "-5"),
    )
    for (ang, bits, lab) in pts {
      let x = 2.0 * calc.cos(ang * 1deg)
      let y = 2.0 * calc.sin(ang * 1deg)
      circle((x, y), radius: 0.06, fill: rgb("#0b5394"))
      content((x * 1.45, y * 1.45))[#text(size: 7.5pt)[#lab]]
    }
    content((0, 0))[#text(size: 8pt, fill: rgb("#783f04"))[mod 256]]
    line((1.55, 1.25), (1.25, 1.55), stroke: 1.2pt + rgb("#9a2617"))
    content((2.5, 1.9))[#text(size: 7pt, fill: rgb("#9a2617"))[seam]]
  }))

Why is this scheme so useful? The answer comes from looking at the flaws of sign-and-magnitude and seeing each turned into a virtue. First, *there is only one zero*: `00000000` is zero, and nothing else is, so no wasted pattern and no "is it plus-zero or minus-zero?" confusion. Second, *the whole range is used*: all $256$ bytes mean a distinct number, from $-128$ to $127$, with nothing wasted. Third, *addition just works*. To compute $-5 + 7$, add the bytes `11111011` ($-5$) and `00000111` ($+7$) column by column, just like grade-school addition but in binary, carrying a $1$ whenever a column sums to two:

#align(center, block(inset: (y: 4pt))[#raw("   11111011   (-5)
 + 00000111   (+7)
 ------------
  100000010")])

The sum has nine bits, but a byte only holds eight, so that leftmost $1$ simply falls off the end (it is the overflow the clock-wheel throws away), leaving `00000010`, which is $+2$. And $-5 + 7 = 2$ is exactly right. The hardware never checks a sign or branches; the same adder that does $5 + 7$ does $-5 + 7$. That uniformity is why, ever since John von Neumann sketched it in his 1945 EDVAC report and the 1949 EDSAC machine put it into silicon, virtually every computer ever built represents signed integers in two's complement.

There is a beautifully simple recipe to *negate* a number in two's complement: *flip every bit, then add one.* To get $-5$, start from $+5 = $ `00000101`, flip all bits to get `11111010`, and add one to land on `11111011`, exactly the $-5$ we decoded earlier. The same recipe run again gets you back: flip `11111011` to `00000100`, add one for `00000101`, which is $+5$. Negation is its own inverse, as it must be, since $-(-5) = 5$. Let us prove the recipe actually computes the negative, because it looks like sorcery and is not.

#theorem("Flip-and-add-one negates")[
  In $n$-bit two's complement, if you take any number $x$, flip every bit, and add $1$, the result represents $-x$ (modulo $2^n$).
]

#proof[
  Look at what "flip every bit" does numerically. A byte and its bit-flip, added together, set every position to $1$: wherever $x$ has a $0$ the flip has a $1$, and vice versa. The all-ones $n$-bit number is $2^n - 1$ (recall "all ones is one below the next power of two"). So if we write $overline(x)$ for the bit-flip of $x$, then
  $ x + overline(x) = 2^n - 1. $
  Rearrange to isolate the flip: $overline(x) = 2^n - 1 - x$. Now add the promised $1$:
  $ overline(x) + 1 = 2^n - x. $
  But on the $n$-bit wheel everything is taken modulo $2^n$, and $2^n - x$ is exactly $-x ("mod" 2^n)$: winding *forward* $2^n - x$ steps is the same as winding *back* $x$ steps, our clock trick from the start of this section. Therefore flip-and-add-one produces $-x$. #h(1fr)
]

#checkpoint[
  Using flip-and-add-one, find the 8-bit two's-complement pattern for $-1$. Then decode it back to check.
][Start from $+1 = $ `00000001`. Flip every bit: `11111110`. Add one: `11111111`. So $-1$ is the all-ones byte. Decode to check: top bit gives $-128$, the rest give $64+32+16+8+4+2+1 = 127$, and $-128 + 127 = -1$. ✓ (It is satisfying that $-1$ is "all switches on," sitting one step counter-clockwise from $0$ on the wheel.)]

#aside[
  This is why a byte read as $129$ in one context and $-127$ in another can be the *same eight bits* `10000001`. Whether `10000001` means $129$ (unsigned) or $-127$ (two's complement) is not in the bits. It is in the *agreement* about how to read them. When you dissect a real file format later in this book, half the battle is knowing which interpretation each field expects. The bits never tell you; the specification does.]

#gopython("How Python shows you the bytes")[
  Python's everyday integers are not fixed-width. They grow as large as your memory allows, so they never overflow. But real files use fixed-width bytes, and Python lets you reach them. The `bytes` type is an immutable row of byte values ($0$–$255$); indexing it with `[0]` pulls out the first value as a plain integer. To see two's-complement behaviour you ask explicitly, with `int.from_bytes` and its `signed=` switch:

  ```python
  >>> b = bytes([0b11111011])     # one byte: the pattern 11111011
  >>> b[0]                        # read it as an UNSIGNED value
  251
  >>> int.from_bytes(b, signed=True)   # read the SAME byte as SIGNED
  -5
  ```

  One byte, `11111011`; two readings, $251$ and $-5$. That is the chapter's whole point in three lines. The `signed=True` flag is Python doing the "top bit is worth $-128$" arithmetic for you. We will meet `bytes`, indexing, and these conversion methods in full in Chapter 17, where `tinyzip` starts writing genuine binary files; for now, savour that the language confirms by hand what we proved on paper.
]

== Putting it together: reading a real header

Let us cash in everything at once on a scrap of a real file. Open almost any GZIP-compressed file (the `.gz` you will build in Chapter 30) in a hex editor and the first two bytes read `1F 8B`. That is hexadecimal; expand each digit to a nibble and you have the bits `00011111 10001011`. As unsigned bytes they are $31$ and $139$, the magic numbers that announce "this is a gzip stream." The very next byte, `08`, names the compression method (8 = DEFLATE). You just parsed a file format using only this chapter's tools: hex for the eye, nibbles for the bits, place value for the decimal meaning. Every codec in this book begins with bytes like these, and you can now read them cold. That is what the rest of the book is built on.

#takeaways((
  [*Place value is the whole game.* A digit's worth is its symbol times the base raised to its position. Change the base, and only the spelling changes. The number underneath is unique (we proved it).],
  [*Computers use base 2 for engineering, not magic:* two switch-states are cheap and noise-proof. A *bit* is one binary digit; $n$ bits hold exactly $2^n$ values (the doubling rule, also proved).],
  [*Hexadecimal is binary in a compact suit.* One hex digit = one nibble (4 bits); two hex digits = one byte = the unit files are measured in. It is the working language of everyone who handles raw bytes.],
  [*Convert with two recipes:* "weigh and sum" to reach decimal, "divide and collect remainders" to leave it. Just regroup bits (no arithmetic) between binary, octal, and hex.],
  [*Some fractions never terminate in binary*, $0.1$ chief among them, because $5$ does not divide $2$. This single fact forces approximations that complicate the compression of scientific and audio data.],
  [*Two's complement* stores negatives with no sign symbol: the top bit's place is worth $-2^(n-1)$. It gives one zero, the full range, and free addition. "Flip the bits, add one" negates (proved). A byte can therefore read as $251$ or $-5$ depending only on the agreement about how to interpret it.],
))

== Exercises

#exercise("4.1", 1)[
  Convert the decimal number $206$ to (a) binary, (b) octal, and (c) hexadecimal. Show the divide-and-collect steps for the binary form, then obtain the octal and hex forms by regrouping the bits rather than dividing again.
]
#solution("4.1")[
  Divide-by-two: $206->103$ r$0$; $103->51$ r$1$; $51->25$ r$1$; $25->12$ r$1$; $12->6$ r$0$; $6->3$ r$0$; $3->1$ r$1$; $1->0$ r$1$. Bottom-to-top: $11001110_2$. Check: $128+64+8+4+2=206$. *Octal:* group in threes from the right, $11|001|110 -> 011|001|110 = 3,1,6 = 316_8$ (check $3 times 64 + 1 times 8 + 6 = 206$). *Hex:* group in fours, $1100|1110 = "C","E" = "CE"_16$ (check $12 times 16 + 14 = 206$).
]

#exercise("4.2", 1)[
  A colour on the web is written `#1E90FF` (this one is "dodger blue"), three bytes giving the red, green, and blue intensities. Convert each of the three bytes to decimal. Which channel is strongest?
]
#solution("4.2")[
  Split into byte pairs: `1E`, `90`, `FF`. Red $= 1 times 16 + 14 = 30$. Green $= 9 times 16 + 0 = 144$. Blue $= 15 times 16 + 15 = 255$. Blue is strongest (maxed out at $255$), green is moderate, and red is faint, which is why the colour reads as a vivid blue.
]

#exercise("4.3", 2)[
  How many distinct values can $12$ bits represent? How many bytes is that (rounding up to whole bytes)? If you needed to label every distinct word in a $50{,}000$-word dictionary, what is the smallest number of bits that suffices, and why?
]
#solution("4.3")[
  $12$ bits give $2^12 = 4096$ values, which spans one-and-a-half bytes (12 bits $=$ 1.5 bytes; rounded up to whole bytes you would store it in 2 bytes). For the dictionary you need $2^n >= 50000$. Since $2^15 = 32768 < 50000 <= 65536 = 2^16$, you need $n = 16$ bits. Fifteen bits ($32{,}768$ labels) fall short; sixteen ($65{,}536$) suffice with room to spare. (This "smallest $n$ with $2^n >=$ count" is the seed of the $log_2$ idea that drives all of entropy coding, developed in Chapters 7 and 18.)
]

#exercise("4.4", 2)[
  Convert the decimal fraction $0.375$ to binary using the multiply-by-two method. Then explain, in one sentence, why $0.375$ terminates in binary but $0.3$ does not.
]
#solution("4.4")[
  $0.375 times 2 = 0.75$ (bit `0`); $0.75 times 2 = 1.5$ (bit `1`); $0.5 times 2 = 1.0$ (bit `1`); leftover $0$, stop. Top-to-bottom: $0.011_2$. Check: $1\/4 + 1\/8 = 0.375$. It terminates because $0.375 = 3\/8$ and the denominator $8 = 2^3$ is a power of two; $0.3 = 3\/10$ has a denominator containing the factor $5$, which does not divide $2$, so its binary expansion repeats forever.
]

#exercise("4.5", 2)[
  Decode the 8-bit two's-complement byte `10010110` to a decimal value. Then negate it with "flip the bits and add one," and decode the result to confirm you get the opposite sign.
]
#solution("4.5")[
  Top bit set, so it contributes $-128$; the rest `0010110` give $16+4+2=22$. Value $= -128 + 22 = -106$. Negate: flip to `01101001`, add one to get `01101010`. Decode: top bit clear, value $= 64+32+8+2 = 106$. So `10010110` is $-106$ and its negation is $+106$. ✓
]

#exercise("4.6", 1)[
  Explain to a friend, in plain words and without using the word "logarithm," why a computer uses base 2 rather than base 10 inside its circuits.
]
#solution("4.6")[
  A computer is built from switches, and a switch reliably knows only two states: on or off. Two states are easy to tell apart even when the electrical signal is noisy, because "on" and "off" sit far apart with a wide safety gap between them. Trying to use ten distinct voltage levels (for base 10) would cram those levels close together, so a little electrical noise could turn a "5" into a "4" or "6." Base 2 trades a little human convenience for enormous reliability and cheapness in the hardware.
]

#exercise("4.7", 3)[
  Prove that in $n$-bit two's complement the single value $-2^(n-1)$ (the most negative number) has no positive counterpart inside the same $n$ bits. In other words, "flip and add one" applied to it gives back *itself*. What does this tell you about the symmetry of the representable range?
]
#solution("4.7")[
  The most negative number is `1` followed by $n-1$ zeros, e.g. `10000000` for $n=8$, representing $-128$. Flip every bit: `01111111`. Add one: this rolls all the ones over and carries up to `10000000`, the original pattern. So negation returns the same byte, meaning $-(-128)$ "is" $-128$ inside 8 bits: there is no $+128$ to represent (it would need a 9th bit). This shows the two's-complement range is *asymmetric*: with $2^n$ patterns and one of them spent on zero, the negatives outnumber the positives by exactly one ($-2^(n-1)$ up to $2^(n-1)-1$). Code that blindly negates can therefore overflow on this one value, a classic real-world bug.
]

#exercise("4.8", 2)[
  Using the `to_base` and `from_base` functions from this chapter's base-conversion warm-up, predict the output of `to_base(255, 2)`, `to_base(4096, 16)`, and `from_base("FF", 16)`. Then state the general rule for what `to_base(2**k, 16)` looks like when $k$ is a multiple of $4$.
]
#solution("4.8")[
  `to_base(255, 2)` $=$ `'11111111'` (eight ones, since $255 = 2^8 - 1$). `to_base(4096, 16)` $=$ `'1000'` (because $4096 = 2^12 = 16^3$). `from_base("FF", 16)` $= 255$. General rule: when $k$ is a multiple of $4$, $2^k = 16^(k\/4)$, so its hex form is the digit `1` followed by exactly $k\/4$ zeros, e.g. $2^8 ->$ `100`, $2^12 ->$ `1000`, $2^16 ->$ `10000`.
]

#exercise("4.9", 3)[
  A naive "compressor" stores each number from $0$ to $999$ as its decimal text in ASCII (one byte per character, e.g. `"42"` is two bytes), terminated by a newline byte. A smarter scheme stores each number in the fewest *whole bytes* of plain binary. For the specific value $537$, how many bytes does each scheme use, and what is the ratio? Generalise: roughly how many *times* larger is the ASCII-decimal form than tight binary for three-digit numbers?
]
#solution("4.9")[
  *ASCII:* `537` is three characters plus a newline $= 4$ bytes. *Binary:* $537 <= 1023 = 2^10 - 1$ but $537 > 255$, so it needs $10$ bits, i.e. $2$ bytes (since $2^16$ covers it and $2^8$ does not; the smallest whole-byte container is 2 bytes). Ratio $= 4\/2 = 2times$. In general a three-digit number needs up to $4$ ASCII bytes but fits in $2$ binary bytes (values up to $999 < 1024 = 2^10$), so ASCII-decimal is about $2times$ larger: a 50% overhead paid purely for the choice of representation, before any real compression begins. This is exactly why, as Chapter 3 warned, *serialization choices* set the ceiling on how well a compressor can do.
]

#exercise("4.10", 2)[
  Octal uses groups of three bits and hex uses groups of four. Suppose a hypothetical "base-32" notation grouped *five* bits per symbol. (a) How many symbol values would it need? (b) Why can't we cleanly group binary into a base-10 (decimal) symbol the way we group into octal or hex? (c) Which property of $8$, $16$, and $32$ (but not $10$) makes clean bit-grouping possible?
]
#solution("4.10")[
  (a) Five bits give $2^5 = 32$ patterns, so base-32 needs $32$ symbols (commonly $0$–$9$ then $A$–$V$). (b) Decimal cannot be reached by regrouping bits because $10$ is *not* a power of two: there is no whole number $k$ with $2^k = 10$, so no fixed bundle of bits maps exactly onto one decimal digit; you are forced to do real division instead. (c) The clean-grouping property is being a *power of two*: $8 = 2^3$, $16 = 2^4$, $32 = 2^5$. Any base that is a power of two regroups directly with bits; bases that are not (like $10$) require arithmetic.
]

== Further reading

- *On the deep idea of place value and its history:* Georges Ifrah, _The Universal History of Numbers_ (Wiley, 2000). A sweeping, readable account of how humanity climbed from tally marks to positional notation, the single invention this chapter rests on.

- *On hexadecimal's origins and the `A`–`F` convention:* the #link("https://en.wikipedia.org/wiki/Hexadecimal")[Wikipedia entry on Hexadecimal] collects the primary sources, including the 1845 base-16 proposal, the 1950 SEAC usage, and IBM's 1963 standardisation discussed in this chapter's historical note.

- *On two's complement and why every machine adopted it:* John von Neumann's 1945 _First Draft of a Report on the EDVAC_ is where the idea enters computing; the #link("https://en.wikipedia.org/wiki/Two%27s_complement")[Wikipedia entry on Two's complement] traces the path from von Neumann to the 1949 EDSAC and onward.

- *On why $0.1$ won't sit still*, and what computers do about it: David Goldberg, _What Every Computer Scientist Should Know About Floating-Point Arithmetic_ (ACM Computing Surveys, 1991). The canonical reference, which we revisit when Chapter 13 builds floating point in full.

#bridge[
  We can now read, write, and convert numbers in any base, count bits and bytes, and store negatives in two's complement. But numbers are only switches arranged in patterns. The next layer up asks how those switches *reason*. In Chapter 5 we build *logic and Boolean algebra* from zero: how a single bit can mean true or false, how `AND`, `OR`, `NOT`, and `XOR` combine bits into decisions, and how the very same gates that compute logic also do the binary arithmetic we just learned. The two's-complement adder we waved at (the one that handles negatives without any special-casing) is built from exactly those gates. Time to open it up.
]





