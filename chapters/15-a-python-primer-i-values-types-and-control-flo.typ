#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= A Python Primer I: Values, Types, and Control Flow

#epigraph[Programs must be written for people to read, and only incidentally for machines to execute.][Harold Abelson, _Structure and Interpretation of Computer Programs_]

Here is a confession that should put you at ease. The entire `tinyzip` project we will build across this book (a real, working compressor that squeezes files and grows them back to the byte) leans on only a small handful of Python ideas. A few kinds of value: whole numbers, fractions, text, true-or-false. A few ways to name things. A way to ask a question and act on the answer. A way to repeat. That is very nearly the whole toolbox, and you can fit it in your head.

So why does code look so forbidding from the outside? Because every program is written in a tiny, exact dialect, and a single misplaced character can stop it cold. The cure is not cleverness. It is *familiarity*. The way you became fluent at reading English was not by memorising a dictionary but by seeing the same small words a thousand times until they stopped being symbols and started being meaning. This chapter does that for the small words of Python. By the end, a line like `if count > 0: print(count)` will read as plainly to you as "if the count is above zero, show it."

We pick Python for three honest reasons. It reads almost like careful English, so it gets out of the way of the *ideas*, which are the real subject of this book. It is the language the whole compression-and-machine-learning world actually writes in, so when we later reach neural codecs in Volume IV you will already speak the local tongue. And it comes with a real compressor or two built right in. By the end of this book you will understand the machinery underneath them, and Python's own standard library will be a place you go to check your work.

We will use *Python 3.14*, released on 7 October 2025. You do not need to memorise version numbers, but it is worth knowing this one is modern: it even ships a brand-new `compression.zstd` module for the Zstandard algorithm we will meet in Chapter 32. We will write in the clean, current style (the type hints, the f-strings, the `match` statements) so that what you learn here is what you will see in real code for years to come.

#recap[
This is the first of three Python chapters, and it is where the book's *second spine* begins: Python taught from scratch, exactly the way we have taught the maths. In *Chapter 4* we built binary numbers and saw that a *bit* is a single 0-or-1 choice; Python's integers are made of those bits, and we will lean on that. In *Chapter 5* we built the logic of `and`, `or`, `not`, and `xor` with truth tables; Python spells those operators almost identically, and this chapter cashes that in. From *Chapter 7* we keep the idea that a logarithm is "how many bits," and from *Chapter 13* (How Computers Represent Things) we keep bytes, ASCII, and two's-complement integers. Python sits one comfortable layer above all of that. We need no compression theory here; we are sharpening the single tool, the Python language, that every later build chapter will swing.
]

#objectives((
  [Run Python in the _REPL_ and in a _script_, and read its output,],
  [Tell apart the four core _value types_ (`int`, `float`, `str`, `bool`) and convert between them on purpose,],
  [Bind values to _names_ with `=`, and explain why a name is a label, not a box,],
  [Use the arithmetic, comparison, and logical _operators_, including integer division `//`, remainder `%`, and power `**`,],
  [Build readable text with _f-strings_ and call basic _functions_ like `print`, `len`, and `input`,],
  [Steer a program with `if` / `elif` / `else`, and repeat work with `while` and `for` over a `range`,],
  [Use the _walrus operator_ `:=` to name a value in the middle of a test,],
  [Write and run the first three real `tinyzip` scripts: a byte counter, a frequency histogram, and a run-length toy.],
))

== Two ways to run Python: the REPL and the script

Before a single idea about values, you need somewhere to *try things*. Python gives you two. They are not rivals; you will use both every day.

The first is the *REPL*, a four-letter acronym worth unpacking because the four letters are exactly what it does. *R*ead: it reads one line you type. *E*val: it evaluates that line, working out what it means. *P*rint: it prints the answer back. *L*oop: it goes round again, waiting for your next line. It is a conversation. You type a scrap of Python, press Enter, and Python answers instantly. There is no better place to poke at a new idea and see what it does.

You start it by running `python` (or `python3` on some systems) at your terminal. It greets you with three characters, `>>>`, called the *prompt*, meaning "your turn." Whatever follows `>>>` in this book is something *you* type; a line with no prompt is Python's *answer*.

```python
>>> 2 + 2
4
>>> 17 * 23
391
>>> "compress" + "ion"
'compression'
```

Three conversations. You asked for two plus two and Python said four. You asked for seventeen times twenty-three and it did the multiplication. You glued two pieces of text together (more on that soon) and got one. The REPL is your laboratory bench; reach for it whenever you wonder "what would Python do here?"

The second way is the *script*: a plain text file, by convention ending in `.py`, holding many lines of Python to be run top to bottom, all at once. This is how real programs, including `tinyzip`, are stored and shared. You write the file once, save it, and run the whole thing as often as you like with `python myfile.py`. The REPL is for exploring; the script is for keeping.

There is one visible difference that surprises everyone at first. In the REPL, typing `2 + 2` shows `4` because the REPL prints every answer for you. In a script, the same line computes 4 and then silently throws it away. A script only shows what you *explicitly* ask it to show, with the `print` function we meet shortly. Keep that distinction in mind and a hundred small confusions vanish.

How does Python find and run a script? You hand the file to the interpreter: typing `python tinyzip/count_bytes.py` at your terminal means "run the Python interpreter, and feed it this file." Python reads the file from the first line to the last, carrying out each instruction in order, and then exits. There is no "main" ceremony to learn, no compilation step to wait through, no separate "build": write, save, run, see the result. That tight loop, from idea to output in seconds, is a large part of why Python is such a comfortable language to *learn* in, and why every build chapter of this book will simply ask you to run a small script and read what it prints. You will spend far more time thinking about compression than wrestling with the language, which is exactly the balance we want.

#gopython("Comments and the `#` sign")[
Any text after a `#` on a line is a *comment*: Python ignores it utterly. Comments are notes to humans (your future self, mostly) explaining *why* a line exists. They never affect what the program does.

```python
# This whole line is a note; Python skips it.
total = 391   # everything after the # is also ignored
```

Use them to explain intent, not to restate the obvious. `x = x + 1  # add one to x` is noise; `x = x + 1  # advance past the matched byte` earns its keep. Throughout this book, the `#` notes inside code are there to teach.
]

#tryit[
Open a terminal and type `python`. At the `>>>` prompt, try `2 ** 10` (two to the tenth power). You should see `1024`, the number of bytes in a kibibyte, and a number that will haunt this book happily. Then type `quit()` and press Enter to leave. You have now run Python.
]

== Values and their types

Everything Python works with is a *value*: a single piece of data. The number `42` is a value. The text `"hello"` is a value. The truth-or-falsehood `True` is a value. And every value has a *type*, a category that decides what the value *can do*. You can divide one number by another; you cannot divide one word by another. The type is the rulebook for the value.

There are four core types you must know cold, because almost everything else is built from them. We take them one at a time, with the REPL as our bench.

=== Integers: `int`

An *integer* is a whole number, positive, negative, or zero: `-3`, `0`, `7`, `1024`. Its type is called `int`. Integers are the bread of compression: byte values run 0 to 255, codeword lengths are whole bits, counts of symbols are whole numbers. You will use `int` more than anything else.

```python
>>> 255
255
>>> -3
-3
>>> 1_000_000
1000000
```

That last one shows a small kindness: you may sprinkle underscores into a long number to group the digits, exactly as you would write a comma in "1,000,000". Python ignores the underscores; they are purely for your eyes. `1_000_000` and `1000000` are the very same value.

Here is a fact that will matter later and delights newcomers: Python integers have *no size limit*. In most languages an integer overflows once it grows past a fixed number of bits (we saw two's-complement wrap-around in Chapter 13). Python simply grows the number as large as your memory allows.

```python
>>> 2 ** 1000
10715086071862673209484250490600018105614048117055336074437503883703510511249361224931983788156958581275946729175531468251871452856923140435984577574698574803934567774824230985421074605062371141877954182153046474983581941267398767559165543946077062914571196477686542167660429831652624386837205668069376
```

Two raised to the thousandth power, computed exactly, every digit. We just printed a 302-digit number without breaking a sweat. When we build entropy calculations and arithmetic coders later, this freedom from overflow will quietly save us from a whole class of bugs.

#gopython("Asking a value its type: the `type` function")[
Whenever you are unsure what kind of value you are holding (and you will be, especially when data arrives from a file) ask Python directly with the `type` function. It hands back the value's type, which you can print or compare:

```python
>>> type(42)
<class 'int'>
>>> type(3.14)
<class 'float'>
>>> type("hi")
<class 'str'>
>>> type(42) == int       # is this an integer?
True
```

The word `class` in the output is just Python's formal name for "type." We will not need full classes until much later, so read `<class 'int'>` as simply "this is an `int`." When a calculation misbehaves, `type(...)` is the first diagnostic to reach for: nine times out of ten the surprise is that a value you thought was a number is secretly a `str`.
]

#gomaths("Powers and the `**` operator")[
We met exponents properly in Chapter 7. A quick reminder, because Python uses them constantly. The expression $2^(10)$ means "multiply 2 by itself 10 times": $2 times 2 times dots times 2 = 1024$. The little raised number is the *exponent*; it counts the multiplications. In Python you cannot write a raised number, so the power operator is two stars, `**`:

```python
>>> 2 ** 10
1024
>>> 10 ** 3
1000
```

Read `2 ** 10` as "two to the tenth." Because a bit is a yes/no choice, $n$ bits make $2^n$ different patterns. `2 ** 8` is `256`, the number of distinct bytes, so `**` and bit-counting are old friends.
]

=== Floating-point numbers: `float`

Not every number is whole. A probability might be `0.25`; an average codeword length might be `2.7` bits. A number with a decimal point is a *floating-point* number, type `float`. The name comes from the decimal point being allowed to "float" to wherever it is needed: `3.14`, `0.0001`, `2500000.0` are all floats.

```python
>>> 0.25
0.25
>>> 3.0
3.0
>>> 1.5 + 2.5
4.0
```

Notice `3.0`: the `.0` is what tells Python (and you) that this is a float, not the integer `3`. They are different types with different behaviour, and the dot is the tell. Adding two floats gives a float; the answer above is `4.0`, not `4`.

Floats carry a famous wart that you must know about now, because it will bite you in compression code if you do not. They cannot store most decimals *exactly*: they keep only a fixed number of binary digits, so they round.

```python
>>> 0.1 + 0.2
0.30000000000000004
```

That trailing `...04` is not a Python bug; it is the unavoidable price of squeezing endless decimals into finite bits, the same lesson Chapter 13 taught about floating point. The practical rule: *never test two floats for exact equality.* `0.1 + 0.2 == 0.3` is `False`, to everyone's surprise. When we need exact arithmetic (entropy coding sometimes does) we reach for integers instead, which is one more reason Python's unbounded `int` is a gift.

#pitfall[
Mixing types quietly turns integers into floats. `6 / 2` gives `3.0`, a float, not `3`, because the single-slash `/` *always* produces a float in Python 3, even when the division comes out even. If you truly want a whole-number result, use the double slash `//`, which we meet two pages on. Watch your dots.
]

=== Text: `str`

A *string* is a piece of text: a sequence of characters. Its type is `str` (short for "string", as in a string of beads). You write a string by wrapping characters in quotes. Single `'...'` or double `"..."` both work, as long as the pair matches.

```python
>>> "hello"
'hello'
>>> 'tinyzip'
'tinyzip'
>>> "the letter A"
'the letter A'
```

Strings are how text data enters our compressors before it becomes raw bytes. The word `"banana"` is a string with a lot of repetition, exactly the kind of redundancy compression feeds on. You can glue strings together with `+` (called *concatenation*) and repeat one with `*`:

```python
>>> "ab" + "cd"
'abcd'
>>> "na" * 4
'nananana'
>>> "=" * 20
'===================='
```

That last trick, a character times a number, is the quickest way to draw a divider line, and we will use it to format `tinyzip`'s reports.

#gopython("Indexing a string: `s[i]` and counting from zero")[
A string is an ordered sequence, so you can reach in and pull out a single character by its *position*, written in square brackets. The catch (the single most common off-by-one trap in all of programming) is that Python counts positions *from zero*, not one:

```python
>>> word = "banana"
>>> word[0]        # the FIRST character is at position 0
'b'
>>> word[1]
'a'
>>> word[5]        # the last of six characters is at position 5
'a'
>>> word[-1]       # negative counts from the end: the last one
'a'
```

So a six-character string has positions 0 through 5, and `word[6]` is past the end. Asking for it raises an `IndexError`. Negative indices are a Python kindness: `word[-1]` is the last character, `word[-2]` the second-to-last, without having to compute the length. This `s[i]` notation is how our compressors will scan a buffer one character at a time, and `range(len(s))` (positions 0 to length−1) is the loop that visits them all.
]

#gopython("From character to number and back: `ord` and `chr`")[
Underneath, every character is really a number: its code point, the ASCII and Unicode values we built in Chapter 13. Two functions cross that bridge. `ord` takes a one-character string and returns its number; `chr` takes a number and returns the character:

```python
>>> ord("A")       # what number IS the letter A?
65
>>> ord("a")
97
>>> chr(65)        # what character is number 65?
'A'
>>> chr(97 + 1)    # arithmetic on characters, via their numbers
'b'
```

So `chr(ord("a") + 1)` is `"b"`. You can do *arithmetic* on letters by passing through their numbers. This matters enormously for compression: a codec does not really see letters, it sees the *byte values* 0–255, and `ord`/`chr` are how our early, character-based `tinyzip` code reaches the same numbers a byte-based codec works with. When Chapter 17 swaps strings for raw bytes, this is the bridge we cross.
]

#gopython("Quotes inside strings and escape characters")[
What if your text *contains* a quote? Two cures. First, use the *other* kind of quote on the outside: `"it's fine"` works because the outer quotes are double and the apostrophe is single. Second, put a backslash before the awkward character to *escape* it, telling Python "this is literal text, not punctuation":

```python
>>> 'it\'s fine'
"it's fine"
>>> "line one\nline two"
line one
line two
```

`\n` is the most important escape: it means *newline*, the invisible character that ends a line of text. We met it in Chapter 13 as byte value 10. When `print` shows a string, `\n` makes it jump to a fresh line. `\t` is a tab. `\\` is a single literal backslash. These escapes let one line of source code stand for text that spans several lines on screen.
]

=== Truth values: `bool`

The last core type has only two values in the entire universe: `True` and `False`. This is the *Boolean* type, `bool`, named for George Boole, whose algebra of logic we built from scratch in Chapter 5. A Boolean is the answer to a yes/no question: Is this number positive? Are these two bytes equal? Did the match succeed? Every decision a program makes comes down, in the end, to a `bool`.

```python
>>> True
True
>>> 5 > 3
True
>>> 5 > 10
False
>>> 2 + 2 == 5
False
```

The capital letters matter: `True` and `False`, not `true` or `TRUE`. Notice how `5 > 3` *computes* a Boolean. You rarely type `True` directly; you ask a question whose answer is a Boolean. That double-equals `==`, meaning "is equal to," is the single most common source of beginner bugs, because it is so easily confused with the single `=` that *names* things. We will draw that line sharply in a moment. For now, hold the picture: four types (whole numbers, decimals, text, and truth) and almost all of `tinyzip` is built from them.

#checkpoint[What type does each of these have: `42`, `4.2`, `"42"`, `4 == 2`?][In order: `int` (whole number), `float` (has a decimal point), `str` (in quotes, so it is text: the *characters* four and two, not the number), and `bool` (a comparison, whose answer is `False`).]

== Names: binding values to labels

A program that could only compute throwaway answers in the REPL would be useless. We need to *remember* values and refer to them later by name. In Python you do this with the single equals sign, `=`, called *assignment*:

```python
>>> total = 391
>>> total
391
>>> total + 9
400
```

The first line says: "compute the value `391`, and attach the name `total` to it." After that, wherever you write `total`, Python reads `391`. We say the name is *bound* to the value, or that we have *assigned* `391` to `total`.

It is tempting to picture `total` as a box that the number `391` is dropped into (almost every beginner does). Resist that picture; it will mislead you later. The truer picture is that the *value* `391` exists somewhere in memory, and the *name* `total` is a sticky label pointing at it. The label is not the value; it is an arrow to the value. This matters because two names can point at the *same* value, and because reassigning a name just moves its arrow without disturbing the old value.

#fig([A name is a label pointing at a value, not a box holding it. Reassigning the label moves the arrow.], cetz.canvas({
  import cetz.draw: *
  // value boxes
  rect((4,0),(6,0.9), fill: rgb("#eef4fb"))
  content((5,0.45))[`391`]
  rect((4,-1.6),(6,-0.7), fill: rgb("#eef4fb"))
  content((5,-1.15))[`400`]
  // name labels
  content((0.3,0.45))[`total`]
  line((1.0,0.45),(3.9,0.45), mark: (end: ">"))
  content((2.4,0.8), text(size: 7pt)[points at])
}))

The rules for a legal name are simple. It may use letters, digits, and the underscore `_`, but may not *start* with a digit, and may not be one of Python's reserved words like `if` or `for`. By strong convention (one we will follow all book long) multi-word names are written in `snake_case`: all lowercase, words joined by underscores, like `byte_count` or `symbol_frequency`. This is not a rule Python enforces; it is a courtesy to human readers, and good code is dense with it.

A name can be *reassigned* at any time, and the new value need not even be the same type:

```python
>>> x = 10
>>> x = x + 5
>>> x
15
```

That middle line looks like a contradiction in mathematics (`x = x + 5` has no solution!) but it is not an equation. Read `=` as "becomes," not "equals." The line says: "take the current value of `x` (which is 10), add 5 to get 15, then make the name `x` point at 15." The old 10 is discarded. This "take the value, change it, store it back" pattern is the heartbeat of nearly every loop we will write.

The label-not-box picture pays off the moment two names meet. Watch:

```python
>>> a = 100
>>> b = a          # b now points at the SAME value a points at
>>> a = 200        # move only a's arrow; b is untouched
>>> b
100
```

Assigning `b = a` did not copy the number into a fresh box; it pointed `b` at whatever `a` was pointing at. Then `a = 200` moved *only* `a`'s arrow to a new value, leaving `b` still aimed at the original `100`. For the simple, unchangeable values of this chapter (numbers, strings, Booleans) this never bites you, because you can never alter the value `100` itself, only move arrows around. But in Chapter 16, when we meet *lists* whose contents *can* be changed in place, this same picture explains a famous class of surprises. Learn the arrow now and those surprises will look obvious later.

#gopython("Augmented assignment: `+=` and friends")[
Because `x = x + 5` is so common, Python offers a shorthand: `x += 5` means exactly the same thing. "Increase `x` by 5." Every arithmetic operator has such a partner:

```python
>>> count = 0
>>> count += 1      # same as count = count + 1
>>> count += 1
>>> count
2
>>> total = 100
>>> total -= 30     # subtract 30
>>> total *= 2      # double it
>>> total
140
```

We will lean on `count += 1` constantly when we tally how often each byte appears in a file, the first real step toward compression, since a compressor must know which symbols are common.
]

#pitfall[
`=` and `==` are *not* the same and confusing them is the most common beginner error in any language. A single `=` *assigns*: `x = 5` makes `x` mean 5. A double `==` *asks*: `x == 5` is a question whose answer is `True` or `False`. "One equals to set, two equals to test." Say it until it sticks.
]

== Operators: doing things to values

You have already seen operators sneak in: `+`, `*`, `>`. Let us lay them out properly, in three families. An *operator* is a symbol that combines values into a new value.

=== Arithmetic operators

These do maths. Most are obvious; two have a twist worth dwelling on.

#table(columns: (auto, 1fr, auto), inset: 6pt, align: (center, left, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Operator*], [*Meaning*], [*Example → result*]),
  [`+`], [add], [`7 + 3` → `10`],
  [`-`], [subtract], [`7 - 3` → `4`],
  [`*`], [multiply], [`7 * 3` → `21`],
  [`/`], [divide (always a float)], [`7 / 2` → `3.5`],
  [`//`], [floor divide (whole part)], [`7 // 2` → `3`],
  [`%`], [remainder (modulo)], [`7 % 2` → `1`],
  [`**`], [power], [`7 ** 2` → `49`],
)

The two stars `**` for powers we met above. The two that newcomers must truly understand are `//` and `%`, because they appear in nearly every byte-level routine in this book.

The double slash `//` is *floor division*: it divides and then throws away any fractional part, keeping only the whole number below. `7 // 2` is `3`, because 2 goes into 7 three whole times. The percent sign `%` is the *remainder* (its proper name is *modulo*): it gives what is *left over* after that division. `7 % 2` is `1`, because after taking out three 2s from 7, one is left. Together they answer "how many whole times, and how much left over": the exact question you ask when packing bits into bytes.

```python
>>> 17 // 5      # how many whole 5s fit in 17?
3
>>> 17 % 5       # what is left over?
2
>>> (3 * 5) + 2  # check: 3 fives plus the remainder 2
17
```

#gomaths("Modulo and remainders")[
The *modulo* operation answers: after dividing $a$ by $b$ and taking only whole groups, how much is left? Formally, $a mod b$ is the remainder $r$ with $0 <= r < b$ such that $a = q times b + r$ for some whole quotient $q$. A few that recur in compression:

- `n % 8` tells you a bit's position *within* its byte (bytes hold 8 bits, so positions cycle 0–7).
- `n % 256` wraps any integer into a single byte value 0–255, exactly the two's-complement wrap of Chapter 13.
- `n % 2` is `0` for even numbers and `1` for odd. A one-line evenness test.

Modulo is the arithmetic of *cycles* and *wrapping*: clock faces, byte boundaries, and ring buffers all run on it. We will use `% 256` the moment we touch real bytes.
]

#tryit[
In the REPL, predict then check: `23 // 4`, `23 % 4`, `100 % 10`, `100 % 7`. The pattern to internalise: `a // b` and `a % b` are the two halves of one division, the whole part and the leftover.
]

=== Comparison operators

These ask questions and answer with a `bool`. We met these as the relations of Chapter 6 and the logic of Chapter 5; here is how Python spells them.

#table(columns: (auto, 1fr, auto), inset: 6pt, align: (center, left, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Operator*], [*Asks*], [*Example → result*]),
  [`==`], [equal?], [`3 == 3` → `True`],
  [`!=`], [not equal?], [`3 != 4` → `True`],
  [`<`], [less than?], [`3 < 4` → `True`],
  [`>`], [greater than?], [`3 > 4` → `False`],
  [`<=`], [less or equal?], [`3 <= 3` → `True`],
  [`>=`], [greater or equal?], [`4 >= 5` → `False`],
)

Two spellings deserve a note. Equality is `==` (double), because single `=` is already taken for assignment. "Not equal" is `!=`, read aloud as "bang equals" or "not equal": the exclamation mark is Python's "not." Everything else matches the maths you already know. A pleasant Python bonus is that you may *chain* comparisons the way mathematicians do:

```python
>>> x = 7
>>> 0 <= x < 256       # is x a valid byte value?
True
>>> 1 < 5 < 3
False
```

`0 <= x < 256` reads exactly as it would on paper, "is `x` at least 0 and below 256?", and is the natural way to check that a number is a legal byte. Most languages forbid this; Python encourages it.

=== Logical operators

To combine Booleans, Python uses three plain English words, `and`, `or`, `not`, the very connectives whose truth tables we built in Chapter 5.

```python
>>> (5 > 3) and (2 > 1)
True
>>> (5 > 3) and (2 > 9)
False
>>> (5 > 3) or (2 > 9)
True
>>> not (5 > 3)
False
```

`and` is `True` only when *both* sides are; `or` is `True` when *at least one* side is; `not` flips a Boolean to its opposite. These let you build rich conditions out of simple questions: "the byte is a letter *and* it is lowercase," or "we hit the window end *or* ran out of input."

#gopython("Truthiness: when non-Booleans act like `True` or `False`")[
Python lets you use *any* value where a Boolean is expected, and quietly decides whether it counts as "true." The rule is short: *empty* and *zero* things are false; everything else is true.

```python
>>> bool(0)        # zero is false
False
>>> bool(42)       # any non-zero number is true
True
>>> bool("")       # the empty string is false
False
>>> bool("hi")     # any non-empty string is true
True
```

So `if data:` quietly means "if `data` is non-empty," and `while remaining:` means "while there is anything left." This *truthiness* makes loops and tests read like English, but beware: `if x:` and `if x == True:` are not always the same question, so when you mean "is this exactly true," compare explicitly.
]

There is one more thing to know about logic: `and` and `or` are *lazy* (the proper word is *short-circuiting*). Python evaluates the left side first and, if that already settles the answer, never even looks at the right. In `x != 0 and total / x > 1`, if `x` is zero the left side is `False`, so Python skips the division entirely, thereby dodging a divide-by-zero crash. We will use this exact guard later.

A word on *precedence*: the order Python applies operators when you mix them follows the same "multiply before you add" rule you learned in school. Powers bind tightest, then `*` `/` `//` `%`, then `+` `-`, then the comparisons, then `not`, then `and`, then `or`. So `2 + 3 * 4` is `14`, not `20`, and `5 > 3 and 2 > 1` groups as `(5 > 3) and (2 > 1)` without any parentheses at all. The rules are sensible, but you do not have to memorise them: when in doubt, add parentheses to say exactly what you mean. `(a + b) * c` can never be misread, and clear code beats clever code every time. Throughout this book we parenthesise generously, precisely so a reader new to Python never has to pause and recall the precedence table.

== Showing and reading: `print`, `input`, and functions

A script that computes silently is no use; it must *speak*. The way it speaks is the `print` *function*. A function is a named, reusable piece of work you *call* by writing its name followed by parentheses, with the things it should act on (its *arguments*) inside:

```python
>>> print("Hello, tinyzip!")
Hello, tinyzip!
>>> print(2 + 2)
4
>>> print("bytes:", 391)
bytes: 391
```

`print` writes its arguments to the screen, separated by spaces, then moves to a new line. Give it several arguments separated by commas and it prints them in a row. This is how every `tinyzip` script will report its results.

#gopython("Keyword arguments: tuning `print` with `sep` and `end`")[
Some function arguments are passed *by name*, in the form `name=value`, and are called *keyword arguments*. They tune optional behaviour. `print` has two you will use: `sep`, the separator placed *between* arguments (a space by default), and `end`, what is printed *after* the last one (a newline `"\n"` by default).

```python
>>> print("a", "b", "c")              # defaults: spaces, then newline
a b c
>>> print("a", "b", "c", sep="-")     # join with dashes instead
a-b-c
>>> print("no newline", end=" ")      # stay on the same line
>>> print("same line")
no newline same line
```

Setting `end=" "` is the trick that keeps a sequence of `print` calls on a single line, exactly what we use to print a Collatz sequence side by side in this chapter's exercises. Keyword arguments will reappear when we write our *own* functions in Chapter 16; for now, just read `sep="-"` as "with the separator set to a dash."
]

You have already used other functions without naming them so. `len` reports how long something is; `bool`, `int`, `float`, and `str` *convert* a value from one type to another:

```python
>>> len("banana")        # how many characters?
6
>>> int("42")            # text "42" → the number 42
42
>>> str(42)              # the number 42 → text "42"
'42'
>>> float(3)             # the integer 3 → the float 3.0
3.0
>>> int(3.9)             # float → int chops toward zero
3
```

Those conversions matter more than they look. Text read from a file arrives as a `str`; to do arithmetic you must `int(...)` it first. And `int(3.9)` is `3`, not `4`: converting a float to an int *truncates* (chops the fraction), it does not round. To round properly, there is a separate `round` function. Knowing exactly which way a conversion bends is the difference between correct and almost-correct compression code.

#gopython("Rounding on purpose: the `round` function")[
Because `int(3.9)` *chops* down to `3`, you need a different tool when you want true rounding to the nearest whole number: `round`.

```python
>>> round(3.9)         # nearest whole number
4
>>> round(3.2)
3
>>> round(2.718, 2)    # keep 2 decimal places
2.72
>>> round(255 / 2)     # 127.5 -> nearest even: 128
128
```

A second argument says *how many decimal places* to keep, which is handy for reporting bit-rates without an f-string. One genuine surprise: Python rounds a tie (a trailing `.5`) to the nearest *even* number: `round(0.5)` is `0`, `round(2.5)` is `2`. This "banker's rounding" avoids a slow upward drift when you round many numbers, and it matters in quantization, the lossy step we reach in Chapter 39. For now: `int` truncates, `round` rounds, and the two disagree on every fraction.
]

#gopython("`len` - the length of any sequence")[
The `len` function returns *how many items* a sequence holds: characters in a string and (in Chapter 16) elements in a list. It is the most-used function in this book after `print`:

```python
>>> len("banana")
6
>>> len("")            # the empty string has length 0
0
>>> len("a" * 100)
100
```

`len` underpins two patterns you will write hundreds of times. To loop over every position of a sequence: `for i in range(len(s)):` walks `i` from `0` to `len(s) - 1`, exactly the valid index range. To check whether there is anything to process at all: `if len(data) > 0:`, or, leaning on truthiness, simply `if data:`. Because a compressed file's job is to make `len(output)` smaller than `len(input)`, `len` is also how `tinyzip` will *measure its own success* on every run.
]

#gopython("`input` - reading from the keyboard")[
The `input` function pauses the program, shows an optional prompt, waits for the user to type a line and press Enter, then hands back what they typed *as a string*:

```python
name = input("What file? ")     # waits; user types: data.txt
print("Compressing", name)      # → Compressing data.txt
```

The catch that trips everyone: `input` *always* returns a `str`, even if the user types digits. To get a number you must convert: `count = int(input("How many? "))`. Forget the `int(...)` and you will try to do arithmetic on text and get a confusing error. We will use `input` sparingly (files, not typing, feed real compressors) but it is the quickest way to make a script interactive.
]

== Building text the modern way: f-strings

Printing `"bytes:", 391` with commas works, but it is clumsy when you want to weave numbers into a sentence. Python's elegant answer is the *f-string* (formatted string), introduced in Python 3.6 and now the universal way to build text. You put the letter `f` immediately before the opening quote, and then *anywhere inside* you may drop a value in curly braces `{...}`:

```python
>>> count = 391
>>> ratio = 0.62
>>> f"Wrote {count} bytes."
'Wrote 391 bytes.'
>>> f"{count} bytes at ratio {ratio}."
'391 bytes at ratio 0.62.'
```

Inside the braces you may put any expression, not just a name. Python computes it and drops the result into the text:

```python
>>> original = 1000
>>> compressed = 620
>>> f"Saved {original - compressed} bytes ({100 * compressed / original}%)."
'Saved 380 bytes (62.0%).'
```

The braces also accept a *format specifier* after a colon, which controls how the value is displayed: how many decimal places, how wide a column, what padding. Two you will use constantly:

```python
>>> ratio = 0.6231957
>>> f"ratio = {ratio:.2f}"        # 2 digits after the point
'ratio = 0.62'
>>> f"|{42:>6}|"                  # right-align in 6 columns
'|    42|'
>>> f"|{42:<6}|"                  # left-align in 6 columns
'|42    |'
```

`:.2f` says "show this as a float with two decimal places," perfect for percentages and bit-rates that would otherwise sprawl. `:>6` and `:<6` pad a value into a fixed width so columns line up, which is how we will make `tinyzip`'s scoreboard tables readable. F-strings are a small feature with a huge payoff: nearly every line of output in this book is built with one.

#aside[
Python 3.14 added a sibling, the *t-string* (template string, written with a `t` instead of `f`), for advanced cases where you want to inspect or transform the pieces of a string *before* they are stitched together, useful for safely building HTML or SQL. We will not need t-strings for `tinyzip`, but it is worth knowing the family has grown, so that `t"..."` in modern code does not surprise you.
]

#checkpoint[What does `f"{3 + 4} and {2 ** 3}"` produce?][The string `'7 and 8'`. Each pair of braces holds an expression; Python evaluates `3 + 4` to `7` and `2 ** 3` to `8`, then drops the results into the text.]

#gopython("`import`: borrowing code the standard library already wrote")[
Python ships with a vast *standard library* (hundreds of ready-made tools) and `import` is how you reach for one. Writing `import sys` at the top of a file makes the `sys` module available, and from then on `sys.argv` means "the `argv` thing inside `sys`." You are not copying code; you are pointing at it, the same label-not-box idea from before.

```python
>>> import math          # the maths toolbox
>>> math.sqrt(144)       # reach inside it with a dot
12.0
```

The `cli.py` below also wraps its work in `def main(): ...`, a *function definition* (`def` names a reusable block; `return` ends it early). We meet writing our own functions properly in Chapter 16; here, read `def main():` as simply "here is the block to run," and the `if __name__ == "__main__": main()` line at the bottom as "run that block when this file is launched directly."
]

#project("Step 1 · The `tinyzip` package skeleton")[
Time to lay `tinyzip`'s first stones. Every Python project of any size lives in a *package*, a folder of related `.py` files that travel together. Make a folder named `tinyzip`, and inside it create three files. The first, `__init__.py`, may be empty; its mere presence tells Python "this folder is a package," so that later chapters can write `from tinyzip.utils import histogram`. The second, `count_bytes.py`, is the script below. The third, `cli.py`, is the tiny command-line front door that every later step will grow.

```python
# tinyzip/__init__.py - marks this folder as a package.
__version__ = "0.1"
```

Now the byte counter. The most basic fact about any data is how many characters (and so, naively, how many bytes) it holds, the very number a compressor must shrink.

```python
# tinyzip/count_bytes.py - our first script.
# Counts the characters in a fixed sample string and reports it.

sample = "banana bandana"        # our running toy data (a str)

length = len(sample)             # len() counts the characters
print(f"Sample: {sample!r}")     # !r shows the quotes, for clarity
print(f"Length: {length} characters")

# A crude "size in bits" if every character took a full byte:
print(f"Naive size: {length * 8} bits ({length} bytes)")
```

Run it with `python tinyzip/count_bytes.py`. You should see:

```
Sample: 'banana bandana'
Length: 14 characters
Naive size: 112 bits (14 bytes)
```

Three new things earn their place here. The `!r` inside `{sample!r}` asks for the *representation*, showing the string *with its quotes* so you can see exactly where it begins and ends. The arithmetic `length * 8` is our naive baseline: 8 bits per character, no compression at all. That number, *112 bits*, is the bar every later technique must beat. We have just established `tinyzip`'s first scoreboard entry: the do-nothing size. Everything from here is the art of making it smaller.

Finally, the front door. A real tool does not hard-code its sample; it reads a *file* the user names. The canonical first job of `cli.py` is exactly that: take a filename, read the file's raw contents, and report their size. We keep it to the few tools this chapter has taught, with one new pair, `open` and `read`, that we will study properly in Chapter 17.

```python
# tinyzip/cli.py - the command-line front door.
import sys                          # gives us the words typed after the script

def main() -> None:
    if len(sys.argv) < 2:           # sys.argv[0] is the script's own name
        print("usage: python -m tinyzip <file>")
        return
    path = sys.argv[1]              # the first word the user typed
    data = open(path, "rb").read()  # read the WHOLE file as raw bytes
    print(f"{path}: {len(data)} bytes")

if __name__ == "__main__":          # only run when launched, not imported
    main()
```

Run it with `python tinyzip/cli.py count_bytes.py` and it prints that file's size in bytes. Three pieces are genuinely new and worth a sentence each. `sys.argv` is the *list of words* typed on the command line (`sys.argv[0]` is the script's name and `sys.argv[1]` is the first thing after it), which is how a program receives input from the outside world without `input`. The `"rb"` in `open(path, "rb")` means "read, in *binary* mode," handing back the file's exact bytes rather than decoded text; `len(data)` then counts those bytes. We are skating one step ahead of ourselves here. *Bytes*, files, and binary I/O are the whole subject of Chapter 17, where `open`/`read` get the careful treatment they deserve. But this lets `tinyzip` do, on day one, the real thing a compressor does: open a file and measure it. From here on, every build chapter adds one function to this skeleton.
]

== Making decisions: `if`, `elif`, `else`

So far our programs run straight through, every line, every time. Real programs *choose*: do this when the byte is a letter, that when it is a digit; emit a short code when the symbol is common, a long one when it is rare. Choice is the first half of what makes code more than a calculator, and in Python it is spelled `if`.

```python
count = 7
if count > 0:
    print("There is data.")
    print("Let us compress it.")
```

Read it as English: "if the count is above zero, then do the indented lines." Two pieces of Python grammar appear here, and they govern *every* control structure in the language, so we slow down for them.

The first is the *colon*. The line `if count > 0:` ends in a colon, which announces "a block of dependent code follows." Every `if`, `while`, `for`, function, and class header ends in a colon. Forget it and Python stops with a `SyntaxError`. The colon is Python saying "...and here is what depends on that."

The second, and the one that makes Python unmistakable, is *indentation*. The two `print` lines are pushed in from the left, by convention exactly *four spaces*, and that indentation is *the only thing* that marks them as belonging to the `if`. Most languages use curly braces `{ }` to group lines; Python uses whitespace. Lines indented to the same depth form a *block* and run together. When the indentation steps back out, the block is over.

#pitfall[
Indentation in Python is *meaning*, not decoration. Mixing tabs and spaces, or being sloppy by a space, changes which lines belong to which block. Python will either error out or, worse, silently do the wrong thing. Pick *four spaces* per level and never mix in tabs. Every good editor can be set to insert four spaces when you press Tab; do that once and forget about it.
]

The condition after `if` is anything that evaluates to a Boolean: a comparison, a logical combination, or a truthy value. When it is `True`, the block runs; when `False`, the block is skipped entirely.

#gopython("Reading an error message: the traceback")[
You *will* make mistakes. Everyone does, constantly. The most useful skill of all is reading Python's complaint, called a *traceback*. When something goes wrong, Python stops and prints the file, the line, and the kind of error:

```python
>>> word = "banana"
>>> word[99]
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
IndexError: string index out of range
```

Read it *from the bottom up*. The last line is the headline: the *error type* (`IndexError`) and a plain-English reason (`string index out of range`, meaning we asked for position 99 of a 6-character word). The lines above point at *where* it happened. A few you will meet often: `SyntaxError` (you mistyped the grammar, a missing colon or quote), `NameError` (you used a name you never assigned), `TypeError` (you mixed incompatible types, like adding a number to a string), and `IndexError` (you reached past the end of a sequence). The error is not a scolding; it is a precise map to the bug. If a program *hangs* instead of erroring (usually an infinite loop) press `Ctrl-C` to interrupt it. Learning to read tracebacks calmly is the difference between an hour of frustration and a thirty-second fix.
]

To handle the "otherwise" case, add an `else`:

```python
length = 0
if length > 0:
    print("Compressing", length, "characters.")
else:
    print("Nothing to do - the file is empty.")
```

Exactly one of the two blocks runs: the `if` block when the condition holds, the `else` block when it does not. When you have *several* mutually exclusive cases, you chain them with `elif` (a contraction of "else if"), as many as you like, with an optional final `else` to catch everything that slipped through:

```python
byte = 200
if byte < 32:
    print("control character")
elif byte < 127:
    print("printable ASCII")
elif byte < 160:
    print("more control codes")
else:
    print("extended / high byte")
```

Python checks the conditions top to bottom and runs the block for the *first* one that is `True`, then skips all the rest. Because `byte` is 200, the first three tests fail and the `else` block runs, printing "extended / high byte." The order matters: each `elif` may assume all the earlier conditions were false, which is why we can write `byte < 127` without also writing `byte >= 32`.

#fig([An `if` / `elif` / `else` ladder: Python takes the first branch whose test is true and skips the rest.], cetz.canvas({
  import cetz.draw: *
  let drect(x,y,w,t,col) = { rect((x,y),(x+w,y+0.8), fill: col); content((x+w/2,y+0.4), pad(x: 2pt, align(center, text(size:8pt)[#t]))) }
  drect(0,3,3.4,"if byte < 32 ?", rgb("#eef4fb"))
  drect(0,1.6,3.4,"elif byte < 127 ?", rgb("#eef4fb"))
  drect(0,0.2,3.4,"elif byte < 160 ?", rgb("#eef4fb"))
  drect(0,-1.2,3.4,"else", rgb("#fbf7ef"))
  let res(y,t) = { rect((4.4,y),(8.0,y+0.8), fill: rgb("#eef9f3")); content((6.2,y+0.4), pad(x: 2pt, align(center, text(size:8pt)[#t]))) }
  res(3,"control char")
  res(1.6,"printable ASCII")
  res(0.2,"more controls")
  res(-1.2,"extended / high")
  for y in (3,1.6,0.2,-1.2) { line((3.4,y+0.4),(4.4,y+0.4), mark:(end:">")) }
  content((1.7,4.1), text(size:7pt, fill: rgb("#0b5394"))[checked top to bottom])
}))

#tryit[
Write a tiny grading script in the REPL spirit: set `score = 73`, then print `"A"` if it is at least 90, `"B"` if at least 80, `"C"` if at least 70, else `"F"`. With `73` you should land on `"C"`. Notice how the `elif` order lets you write `>= 80` without re-stating `< 90`.
]

== Repeating work: the `while` loop

Choice is half of control; *repetition* is the other half. Compression is repetition incarnate: you process byte after byte, symbol after symbol, match after match, for as long as data remains. Python has two looping tools. The first is the `while` loop, which repeats a block *as long as a condition stays true*.

```python
count = 5
while count > 0:
    print(count)
    count -= 1     # crucial: move toward the stop condition
print("Lift-off!")
```

This prints 5, 4, 3, 2, 1, then "Lift-off!". The shape mirrors `if`: a header ending in a colon, then an indented block. The difference is that after the block runs, Python loops *back* to re-check the condition. As long as `count > 0` holds, the block runs again. When `count` finally reaches 0, the condition is `False`, the loop ends, and the program continues with the un-indented line after it.

The single most important line in that loop is `count -= 1`. It nudges the loop *toward* its ending. Leave it out and `count` stays 5 forever, the condition is always true, and the loop runs without end. That is an *infinite loop*, the classic beginner trap. Every `while` loop must, somewhere in its body, change something that the condition depends on. Ask yourself, every time: "what makes this stop?"

#pitfall[
An infinite loop is a `while` whose condition never becomes false. If you run a program and it just hangs, printing forever or doing nothing, you have probably written one. Press `Ctrl-C` to interrupt it, then look for the variable in your condition and make sure the loop body actually changes it. "What makes this stop?" is the question that prevents most loop bugs.
]

`while` shines when you do not know in advance how many repetitions you need. You loop until *something happens*: until the input runs dry, until a match is found, until a value falls below a threshold. Here is a pattern straight out of number work, halving a value until it is small, exactly the shape of counting how many bits a number needs:

```python
n = 1000
bits = 0
while n > 0:
    n //= 2        # floor-divide by 2, dropping the lowest bit
    bits += 1
print(f"1000 needs {bits} bits")   # → 1000 needs 10 bits
```

Each pass strips one binary digit (using the floor division `//` we met earlier) and tallies it. The loop stops when `n` hits 0. This is the live, runnable cousin of the "a bit is a logarithm" idea from Chapter 7: the number of halvings to reach zero is essentially $log_2$ of the starting value.

== Repeating a known number of times: `for` and `range`

Very often you *do* know the shape of the repetition: "do this once for each character in the string," "do this for each number from 0 to 255." For that, Python offers the `for` loop, which walks through a collection of items one at a time, handing you each in turn.

```python
for letter in "banana":
    print(letter)
```

This prints `b`, `a`, `n`, `a`, `n`, `a`, each on its own line. Read it as "for each letter in the string 'banana', do the block." On each pass, the name `letter` is bound to the next character, and the block runs with that value. A string is a sequence of characters, so a `for` loop over a string visits each character. That is precisely how a compressor scans its input.

When you want to repeat a fixed number of times, or count through integers, you pair `for` with `range`, a built-in that produces a sequence of whole numbers:

```python
>>> for i in range(5):
...     print(i)
0
1
2
3
4
```

The crucial, much-tripped-over fact: `range(5)` produces `0, 1, 2, 3, 4`. It *starts at 0* and *stops just before 5*, giving exactly five numbers. This "start at zero, stop before the top" convention runs through all of Python, and once it clicks it stops surprising you. `range` has three forms, growing in power:

#table(columns: (auto, 1fr, auto), inset: 6pt, align: (left, left, left),
  fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
  table.header([*Form*], [*Produces*], [*Numbers*]),
  [`range(5)`], [0 up to (not including) 5], [0 1 2 3 4],
  [`range(2, 6)`], [2 up to (not including) 6], [2 3 4 5],
  [`range(0, 10, 2)`], [0 to 10, stepping by 2], [0 2 4 6 8],
)

The three-argument form, `range(start, stop, step)`, is a workhorse: `range(0, 256)` walks every byte value, and `range(7, -1, -1)` counts *down* from 7 to 0 (stepping by -1), the order in which we will emit the 8 bits of a byte, most-significant first.

#gopython("`range` is lazy - it does not build a list")[
A subtle but important point: `range(1_000_000)` does *not* create a million numbers in memory. A `range` is a *lazy* recipe: it remembers only its start, stop, and step, and produces each number the instant the loop asks for the next one. This is why `range(10 ** 12)` is harmless even though a trillion numbers would never fit in your machine.

```python
>>> range(5)            # not a list - a compact recipe
range(0, 5)
>>> list(range(5))      # force it to hand over all its numbers
[0, 1, 2, 3, 4]
```

If you ever want to *see* the numbers a range will produce, wrap it in `list(...)`, as above (we meet lists fully in Chapter 16). Otherwise, leave it lazy: looping over a bare `range` is the memory-thrifty habit, and it is exactly how we will walk over every byte of a large file without loading the file's worth of position counters at once.
]

#gopython("`for` versus `while`: which to reach for")[
A simple rule of thumb decides between Python's two loops:

- Use `for` when you know *what you are looping over*: a string's characters, the numbers `range(256)`, the items of a list. The loop variable is handed to you; you cannot forget to advance it, so `for` loops cannot accidentally run forever.
- Use `while` when you loop *until a condition changes* and do not know the count in advance: until input is exhausted, until a match is found, until a value crosses a threshold.

In practice you will write `for` loops far more often, because most data comes as a sequence you want to visit once each. We will use `while` chiefly for bit-level work, where we loop "until the buffer is full" or "while bits remain."
]

#gomaths("Sums as loops: connecting $sum$ to `for`")[
The summation sign $sum$ from Chapter 9 and the `for` loop are the same idea in two notations. The mathematician's

$ S = sum_(i=1)^(n) i $

means "start a running total at 0, then for each $i$ from 1 to $n$, add $i$ to it." That sentence *is* a `for` loop:

```python
n = 100
total = 0
for i in range(1, n + 1):    # i = 1, 2, ..., 100
    total += i
print(total)                 # → 5050
```

Note `range(1, n + 1)` to *include* `n`, since `range` stops one short of its top. Whenever you see $sum$ in a later chapter, picture this loop: a running total fed one term at a time. Entropy, $H = -sum p_i log_2 p_i$, is exactly such a sum. The two are interchangeable, and being able to read each as the other is a quiet superpower.
]

#checkpoint[How many numbers does `range(3, 12, 3)` produce, and what are they?][Three numbers: `3, 6, 9`. It starts at 3, steps by 3, and stops *before* 12, so 12 itself is never reached, and 9 is the last value.]

== Steering inside a loop: `break`, `continue`, and the loop-`else`

Two small keywords give loops fine control. `break` *stops the loop immediately*, jumping out even if items remain, perfect for "search until found, then quit." `continue` *skips the rest of the current pass* and jumps straight to the next item, perfect for "ignore the ones I do not care about."

```python
# Find the first vowel in a word and stop looking.
word = "rhythm"
for letter in word:
    if letter in "aeiou":
        print("First vowel:", letter)
        break
else:
    print("No vowels at all!")
```

Two things to savour. `break` lets us quit the instant we succeed, instead of pointlessly scanning the rest, the same instinct behind a compressor that stops extending a match once it fails. Python also has an unusual flourish: a `for` (or `while`) loop may carry its *own* `else`, which runs only if the loop finished *without* hitting a `break`. Here, since "rhythm" has no `a e i o u`, the loop never breaks, so the `else` fires and prints "No vowels at all!". Read the loop-`else` as "and if we never broke out early." It is the cleanest way to say "I searched the whole thing and found nothing."

`continue` earns its keep when you want to process most items but skip a few:

```python
# Sum only the odd numbers from 1 to 10.
total = 0
for n in range(1, 11):
    if n % 2 == 0:      # even? then...
        continue        # ...skip to the next n
    total += n
print(total)            # → 25  (1+3+5+7+9)
```

When `n` is even, `continue` leaps past the `total += n` line to the next pass. The result tallies only the odds. You could equally have written `if n % 2 == 1: total += n`; `continue` is a matter of taste, useful mainly when the "skip" condition is simple but the work to skip is long.

== Naming a value mid-test: the walrus operator `:=`

One last piece of grammar rounds out our control-flow toolkit, and it is genuinely handy in loops. Normally assignment with `=` is a *statement*: it stands alone on its own line and produces no value you can use. But sometimes you want to compute a value and test it in the same breath. The *walrus operator*, written `:=` (it looks like the eyes and tusks of a walrus, hence the name), does exactly that: it assigns a value to a name *and* hands that value back so the surrounding expression can use it.

```python
# Without the walrus: compute, then test, in two steps.
remaining = len(data)
while remaining > 0:
    ...                       # do work
    remaining = len(data)     # easy to forget to repeat this!

# With the walrus: compute and test in one line.
while (remaining := len(data)) > 0:
    ...                       # remaining is now usable inside
```

The expression `(remaining := len(data))` does two jobs at once: it sets `remaining` to the length, and its *value* is that same length, which the `> 0` then tests. This keeps the computation and the test together, removing the duplicated line that is so easy to forget. The walrus, added in Python 3.8, shines whenever you read a value, name it, and immediately branch on it. Reading a chunk from a file and looping "while a chunk was actually returned" is the canonical case, and we will use it when `tinyzip` reads real files in Chapter 17.

#pitfall[
The walrus needs its parentheses in most positions: write `while (n := next_value()) > 0:`, not `while n := next_value() > 0:`, which Python reads in a confusing order. When in doubt, wrap the `:=` part in parentheses. Do not overuse it. If naming the value on its own line reads more clearly, do that instead. The walrus is a scalpel, not a hammer.
]

#aside[
The walrus operator was one of the most hotly debated additions in Python's history. The argument over it in 2018 was heated enough that Python's creator, Guido van Rossum, stepped down as the language's "Benevolent Dictator for Life" shortly after it was accepted. A two-character operator helped end a 27-year reign. Syntax matters to people.
]

== A worked example: counting character frequencies by hand

A compressor's first question about any data is: *which symbols are common, and which are rare?* Common symbols deserve short codes; rare ones can afford long ones. That is the whole secret of entropy coding, which we reach in Volume II. Before we can code anything, we must *count*. The script below counts how often each character appears in our sample, using only the `for` loop, `if`, and assignment you now know.

This is a *worked example*, not a numbered `tinyzip` step: the real, reusable `histogram()` function is canonically built in *Chapter 16*, once we have the right container (Python's `dict`) for the job. We do it the long way here on purpose, to cement the basics. Chapter 16 will open by showing how painful this hand-rolled version is, then collapse it to a single line.

```python
# tinyzip/histogram.py - count each character's frequency.

sample = "banana bandana"

# Walk the sample once, building a parallel pair of lists by hand.
# (Chapter 16's dict will make this far shorter - for now, basics only.)
seen_chars = ""          # characters we have encountered, in order
counts = []              # counts[i] is how many times seen_chars[i] appears

for ch in sample:
    if ch in seen_chars:
        # Find where we recorded it and bump that count.
        index = 0
        for i in range(len(seen_chars)):
            if seen_chars[i] == ch:
                index = i
        counts[index] += 1
    else:
        # First time we have seen this character.
        seen_chars += ch
        counts += [1]    # append a new count of 1

# Report, neatly aligned with an f-string format specifier.
print(f"{'char':>6} {'count':>6}")
for i in range(len(seen_chars)):
    shown = seen_chars[i] if seen_chars[i] != " " else "<spc>"
    print(f"{shown:>6} {counts[i]:>6}")
```

Running `python tinyzip/histogram.py` prints:

```
  char  count
     b      2
     a      6
     n      4
   <spc>      1
   d      1
```

Read the result like a compressor would. The letter `a` appears six times, `n` four. These are the workhorses that *must* get short codes. The space, `b`, and `d` appear once each and can afford long ones. This little table is the raw material of every entropy coder in this book; in Chapter 24 we will feed exactly such counts to Huffman's algorithm and watch the bits melt. For now, savour that you built a frequency model with nothing but `for`, `if`, `+=`, and an f-string.

#scoreboard(caption: "tinyzip baseline (sample = \"banana bandana\", 14 chars)",
  [No compression (8 bits/char)], [112 bits], [1.00×], [The bar to beat; every char a full byte],
  [Frequency model built], [n/a], [n/a], [Counts in hand; coding starts in Ch. 24],
)

== Putting it together: a run-length toy

We have enough Python now to write a *real, if tiny, compression idea* end to end, using no new concepts beyond the ones from this chapter. The idea is *run-length encoding* (RLE): when the same character repeats many times in a row, instead of writing it out, write the character once and a count. `"aaaa"` becomes `"a4"`. It is the simplest compression there is, and it is genuinely used in fax machines, in the PNG image format we will study in Chapter 44, and in the bzip2 pipeline of Chapter 35. We meet it properly there; here it is a worked example to flex every muscle this chapter built.

```python
# tinyzip/rle_toy.py - run-length encode a string.

data = "aaabbbbbcaaaa"

encoded = ""           # we will build the compressed text here
i = 0
while i < len(data):
    ch = data[i]
    run = 1
    # Count how far the run of this same character extends.
    while i + run < len(data) and data[i + run] == ch:
        run += 1
    encoded += ch + str(run)    # emit the char and its run length
    i += run                    # jump past the whole run

print(f"Original : {data!r}  ({len(data)} chars)")
print(f"Encoded  : {encoded!r}  ({len(encoded)} chars)")

if len(encoded) < len(data):
    saved = len(data) - len(encoded)
    print(f"Saved {saved} characters.")
else:
    print("No saving - runs too short. (RLE can grow data!)")
```

This combines nearly everything: a `while` loop over the data, a *nested* `while` to measure each run (guarded by short-circuiting `and` so we never index past the end), string concatenation, `str(...)` conversion to turn the run count into text, an f-string report, and an `if`/`else` to judge the result. Run it:

```
Original : 'aaabbbbbcaaaa'  (13 chars)
Encoded  : 'a3b5c1a4'  (8 chars)
```

Thirteen characters down to eight, a genuine saving, because the data had long runs. But the `else` branch hints at a deep truth: on data *without* runs, like `"abcdef"`, RLE produces `"a1b1c1d1e1f1"`, which is *twice* the size. No compressor wins on every input; that impossibility was proved by the counting argument in Chapter 8, and RLE is its most vivid small example. A real codec uses RLE only where it helps and switches it off where it hurts, a judgment we will automate later.

It is worth pausing on how much this twenty-line script already does. It is a fair miniature of every compressor to come. It *scans* its input left to right with an outer loop. It *recognises a pattern* (here, a run of identical characters) with an inner loop. It *emits a shorter description* of that pattern when one exists. And it *measures itself*, comparing input and output length to judge whether it won. Scan, model, emit, measure: those four verbs are the skeleton of Huffman coding, of LZ77, of arithmetic coding, of every technique in Volume II. The models grow vastly more clever, but the shape stays. You have, with nothing but `if` and `while` and a handful of string operations, written a real compressor, a humble one, but real. Everything ahead is variations on this theme, each squeezing a little more redundancy out of the data than the last.

#misconception[A good enough compressor can shrink any file.][No algorithm shrinks every possible input. Chapter 8's pigeonhole counting forbids it. Our RLE toy is the proof in miniature: it halves `"aaaa..."` but *doubles* `"abcdef"`. Every real compressor, including the ones you use daily, can grow some inputs; they win only by being aimed at the data that actually occurs.]

#keyidea[
The whole of Python's control flow is three moves: *choose* with `if`/`elif`/`else`, *repeat-until* with `while`, and *repeat-over* with `for`. Combine them with the four value types and a handful of operators, and you can express any computation at all, including every compressor in this book. The cleverness lives in the *ideas*; the language stays small. That is exactly why we chose it.
]

#history[
Python was created by Guido van Rossum over the Christmas holiday of 1989 in the Netherlands, as a successor to a teaching language called ABC, and first released in February 1991. He named it not after the snake but after the British comedy troupe Monty Python's Flying Circus, which is why Python's documentation is sprinkled with spam, dead parrots, and silly walks. Thirty-five years on it is, by most measures, the most widely used programming language on Earth, and the lingua franca of the machine-learning world that now sits at compression's frontier. The clean, readable design you have been learning (significant indentation, English-like keywords, "one obvious way to do it") was deliberate from day one. It is why this book can teach compression *and* its implementation in the same breath.
]

#takeaways((
  [Python offers two homes: the *REPL* (`>>>`) for instant experiments, and *scripts* (`.py` files) run top to bottom for keeping. A script only shows what you `print`.],
  [Four core *types* carry almost everything: `int` (unbounded whole numbers), `float` (decimals that round, so never test them for exact equality), `str` (text in quotes), and `bool` (`True`/`False`).],
  [A *name* is a label pointing at a value, bound with `=` ("becomes"), never confused with `==` ("is equal to?"). `snake_case` for multi-word names.],
  [Operators come in three families: arithmetic (note `//` floor-divide and `%` remainder), comparison (which yield `bool`), and logical (`and`, `or`, `not`, which short-circuit).],
  [*f-strings* (`f"...{value}..."`) weave values into text, with `:.2f` and `:>6` for formatting, and are the backbone of every report we print.],
  [Control flow is three moves: `if`/`elif`/`else` to *choose*, `while` to *repeat until a condition changes*, `for ... in range(...)` to *repeat over* a known sequence. Indentation (four spaces) marks the blocks.],
  [`break`, `continue`, the loop-`else`, and the walrus `:=` give loops fine control. Every `while` must change something its condition depends on, or it never stops.],
  [We built three real `tinyzip` scripts (a byte counter, a frequency histogram, and a run-length toy), proving that genuine compression ideas need only the small toolbox of this chapter.],
))

== Exercises

#exercise("15.1", 1)[
Predict the *type* (`int`, `float`, `str`, or `bool`) of each value, then check in the REPL: (a) `7 // 2`, (b) `7 / 2`, (c) `"7" + "2"`, (d) `7 > 2`, (e) `7 == 7.0`, (f) `str(7) * 3`.
]
#solution("15.1")[
(a) `int`: floor division of two ints stays an int: `3`. (b) `float`: single `/` always gives a float: `3.5`. (c) `str`: concatenating two strings: `'72'` (text glued, *not* added). (d) `bool`: a comparison: `True`. (e) `bool`: `True`; numerically `7` equals `7.0` even though one is `int` and one is `float`. (f) `str`: `str(7)` is `'7'`, repeated three times: `'777'`.
]

#exercise("15.2", 1)[
Without running it, say what this prints, and explain the loop-`else`:
```python
for n in range(2, 8):
    if n == 5:
        break
    print(n)
else:
    print("done")
```
]
#solution("15.2")[
It prints `2`, then `3`, then `4`, each on its own line. When `n` reaches `5` the `break` fires and the loop stops. Because the loop ended via `break`, the loop-`else` does *not* run, so `"done"` is never printed. The loop-`else` runs only when a loop finishes without breaking.
]

#exercise("15.3", 1)[
Explain in one sentence each why (a) `x = x + 1` is not a contradiction, and (b) `0.1 + 0.2 == 0.3` is `False`.
]
#solution("15.3")[
(a) `=` means "becomes," not "equals": the line takes the current value of `x`, adds 1, and rebinds the name `x` to the new value. It is an instruction, not an equation. (b) Floats store only a fixed number of binary digits, so `0.1` and `0.2` are each stored slightly inexactly; their sum lands at `0.30000000000000004`, which is not bit-for-bit equal to the stored `0.3`.
]

#exercise("15.4", 2)[
Write a `for` loop that prints every byte value from 0 to 255 that is a printable ASCII letter, that is, in the range `65`–`90` (A–Z) or `97`–`122` (a–z), together with the letter it represents. (Hint: the function `chr(n)` turns a byte value into its character; we met ASCII in Chapter 13.)
]
#solution("15.4")[
```python
for n in range(256):
    if (65 <= n <= 90) or (97 <= n <= 122):
        print(n, chr(n))
```
The chained comparisons `65 <= n <= 90` read like maths and test each range; the `or` accepts either the uppercase or the lowercase band; `chr(n)` recovers the character. The loop visits all 256 byte values but prints only the 52 letters.
]

#exercise("15.5", 2)[
Using a `while` loop and floor division `//`, count how many decimal digits an integer `n` has (assume `n > 0`). Test it on `7`, `42`, and `1000` (which should give 1, 2, and 4).
]
#solution("15.5")[
```python
n = 1000
digits = 0
while n > 0:
    n //= 10        # drop the last decimal digit
    digits += 1
print(digits)       # 1000 -> 4
```
Each pass removes one decimal digit by floor-dividing by 10 and tallies it; the loop stops when `n` reaches 0. (Dividing by 2 instead would count *binary* digits, the bit length, as in the chapter's logarithm example.)
]

#exercise("15.6", 2)[
Rewrite this two-line read-and-test using the walrus operator `:=` so the length is computed once, inside the `while` header:
```python
remaining = len(buffer)
while remaining > 0:
    print(remaining)
    buffer = buffer[1:]        # drop the first character
    remaining = len(buffer)
```
]
#solution("15.6")[
```python
while (remaining := len(buffer)) > 0:
    print(remaining)
    buffer = buffer[1:]        # drop the first character
```
The walrus computes `len(buffer)`, binds it to `remaining`, and yields that value for the `> 0` test, all in the header. This removes the duplicated `remaining = len(buffer)` line (the easy-to-forget one), because the length is recomputed automatically at the top of every pass. (`buffer[1:]` is slicing, which we cover fully in Chapter 16; here it just drops the first character.)
]

#exercise("15.7", 2)[
Our run-length toy from the chapter *grows* data with no runs. Write an `if` test that, given the original string `data` and the encoded string `encoded`, prints `"keep raw"` when encoding did not help (encoded is the same length or longer) and `"keep encoded"` otherwise. Why must a real codec store a flag saying which choice it made?
]
#solution("15.7")[
```python
if len(encoded) < len(data):
    print("keep encoded")
else:
    print("keep raw")
```
A real codec must record *which* form it stored, a single flag bit, because the decoder, seeing only the stored bytes, has no other way to know whether to run the RLE decoder or copy the bytes verbatim. That one flag bit is the small, honest overhead of being allowed to pick the better of two options, and it is why no scheme compresses every input (Chapter 8).
]

#exercise("15.8", 2)[
Write a loop that computes the sum $sum_(i=1)^(100) i^2$ (the squares of 1 through 100) and prints it. Then explain how this `for` loop corresponds, term by term, to the $sum$ notation.
]
#solution("15.8")[
```python
total = 0
for i in range(1, 101):     # 1, 2, ..., 100  (101 excluded)
    total += i ** 2
print(total)                # 338350
```
The $sum$ sign says "start a running total at 0, and for each $i$ from 1 to 100, add the term $i^2$." That is exactly the loop: `total` is the running total starting at 0; `range(1, 101)` supplies $i = 1, 2, dots, 100$; and `total += i ** 2` adds each term $i^2$. The `+ 1` in `101` is needed because `range` stops one short of its top.
]

#exercise("15.9", 3)[
Write a complete script that, given a string `text`, finds and prints the *single most common character* and how many times it occurs, using only the tools of this chapter (`for`, `if`, assignment, comparison). Build the frequency information by hand as in the histogram project, then make a second pass to find the maximum. Test it on `"mississippi"` (answer: `i` and `s` tie at 4; print whichever your loop finds first).
]
#solution("15.9")[
```python
text = "mississippi"
seen = ""
counts = []
for ch in text:                      # build frequencies
    if ch in seen:
        for i in range(len(seen)):
            if seen[i] == ch:
                counts[i] += 1
    else:
        seen += ch
        counts += [1]

best_char = ""                       # find the maximum
best_count = 0
for i in range(len(seen)):
    if counts[i] > best_count:
        best_count = counts[i]
        best_char = seen[i]

print(f"Most common: {best_char!r} ({best_count} times)")
```
The first loop builds parallel `seen`/`counts` lists exactly as the histogram project did. The second loop sweeps them, keeping `best_count` and `best_char` updated whenever it finds a strictly larger count, the classic "track the best so far" pattern. Because the test is *strictly* greater (`>`), the *first* of any tie wins; for `"mississippi"` that is `s` if `s` is encountered before `i` reaches 4, but the printed answer depends on scan order. This "find the most frequent symbol" is the seed of every greedy code-assignment algorithm to come.
]

#exercise("15.10", 3)[
A *Collatz* sequence starts at any positive integer `n` and repeats: if `n` is even, halve it; if odd, compute `3 * n + 1`; stop when it reaches 1. Write a `while` loop that prints the sequence for `n = 27` and counts how many steps it takes to reach 1. (This famously takes 111 steps, a good test of your loop and a reminder that "what makes this stop?" is sometimes a deep question.)
]
#solution("15.10")[
```python
n = 27
steps = 0
while n != 1:
    print(n, end=" ")
    if n % 2 == 0:
        n //= 2
    else:
        n = 3 * n + 1
    steps += 1
print(f"\nReached 1 in {steps} steps.")   # 111 steps
```
The loop tests `n != 1` and stops when `n` reaches 1; each pass uses `n % 2 == 0` to branch between halving (`n //= 2`) and the odd step (`3 * n + 1`), tallying `steps`. The `end=" "` argument to `print` keeps the sequence on one line by replacing the usual newline with a space. Whether *every* starting `n` eventually reaches 1 is the unsolved Collatz conjecture, so in general "what makes this stop?" can be a genuinely hard question, even when the loop is three lines long.
]

== Further reading

- #link("https://docs.python.org/3/tutorial/")[The Python Tutorial]: the official, free, gentle tour of the language, kept current for Python 3.14. The "Informal Introduction" and "More Control Flow Tools" sections cover exactly this chapter's ground.
- #link("https://docs.python.org/3/whatsnew/3.14.html")[What's New in Python 3.14]: the release notes for the version we use, including t-strings (PEP 750), free-threading (PEP 779), and the new `compression.zstd` module (PEP 784) we will meet in Chapter 32.
- #link("https://peps.python.org/pep-0008/")[PEP 8 - Style Guide for Python Code]: the community's conventions, including `snake_case` and four-space indentation. Reading code is easier when everyone writes it the same way.
- #link("https://peps.python.org/pep-0572/")[PEP 572 - Assignment Expressions]: the proposal that added the walrus operator `:=`, with the design rationale and the debate that surrounded it.
- Mark Lutz, _Learning Python_ (O'Reilly): a thorough, beginner-friendly treatment if you want a second voice on the fundamentals, with far more examples than we have room for.

#bridge[
You can now read and write the *control* of a program: its values, its choices, its loops. But `tinyzip`'s histogram project fought with one hand tied. Counting characters by hand in parallel lists was painful, because we lacked the right *container* for the job. In *Chapter 16* we fix that. We meet Python's real data structures (*lists*, *tuples*, *dictionaries*, and *sets*) that hold many values at once; *slicing* to grab pieces of them; *comprehensions* that build them in a single readable line; and *functions* of our own, with *type hints* like `dict[int, int]`, so our code says what it means. The histogram that took twenty lines here will collapse to three. With those containers in hand, and the *bytes* and *files* of Chapter 17 after them, `tinyzip` will be ready to read real files and emit real compressed bits, and Volume II's first true codec, Huffman, will be within reach.
]
