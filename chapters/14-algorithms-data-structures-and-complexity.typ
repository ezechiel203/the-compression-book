#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Algorithms, Data Structures, and Complexity

#epigraph[
  "An algorithm must be seen to be believed."
][Donald Knuth, _The Art of Computer Programming_]

Picture a phone book — the fat paper kind, a million names in alphabetical order. I ask you to find "Petra Nowak." You would never start at the first page and read every name in turn; you would flip to the middle, see whether "Nowak" comes before or after, throw away half the book, and repeat. In maybe twenty flips you have her. Now picture the same million names dumped in a shoebox in no order at all. The middle-flip trick is useless; you are back to reading them one by one, and on a bad day you read all million.

Same names. Same question. The difference between twenty steps and a million steps was not how clever you are — it was how the data was _arranged_, and what _procedure_ you ran against that arrangement. That, in one sentence, is this entire chapter. A *data structure* is how you arrange information so you can get at it; an *algorithm* is the step-by-step procedure you run; and *complexity* is the honest accounting of how the cost grows as the data gets big. Every compressor in this book is, underneath the mathematics, a marriage of the two: a Huffman coder is a clever tree, an LZ77 matcher is a clever search, an arithmetic coder is a clever loop. You cannot understand _why_ one codec is fast and another is slow — or why `gzip` finishes in a blink while a record-setting compressor chews on the same file for an hour — without the language of this chapter.

#recap[
  We have spent thirteen chapters assembling the raw materials. In Chapter 4 we learned that $n$ bits name exactly $2^n$ things, and met the *byte* — eight bits, $256$ values. Chapter 6 gave us *sets* (collections of distinct things), *functions* (rules turning each input into exactly one output), and *bijections* (perfect one-to-one pairings — what a lossless compressor must be). Chapter 7 made *exponents* and *logarithms* second nature, and showed why halving a search space $n$ times takes about $log_2 n$ steps — the phone-book trick, named. Chapter 8 taught us to *count possibilities* and proved the no-magic-box theorem by counting. Chapter 11 introduced $sum$ (sigma) summation notation and the idea of a function's _growth rate_. And Chapter 13 (the chapter just gone) showed how real data becomes *bytes* — bits, integers, ASCII, the actual material our structures will hold. This chapter spends all of it: complexity _is_ growth rate from Chapter 11 wearing work-clothes; the structures _are_ sets and functions made concrete; and the searching and sorting we do _are_ the logarithms of Chapter 7 in action.
]

#objectives((
  [Say precisely what an *algorithm* is, and read *pseudocode* — the half-English, half-code way we write procedures before committing to a language.],
  [Read and write *Big-O notation* from scratch: what $O(n)$, $O(log n)$, $O(n log n)$, and $O(n^2)$ actually mean, where the notation came from, and how to find the Big-O of a piece of code by eye.],
  [Tell the difference between *worst-case*, *best-case*, and *average-case* cost, and why we usually quote the worst.],
  [Understand the core *data structures* every codec leans on — *arrays*, *linked lists*, *stacks*, *queues*, *hash tables*, *trees*, *heaps* and *priority queues* — knowing for each what it is good at and what it is bad at.],
  [Reason about *time* versus *space* and see why compression is one long negotiation between the two.],
  [Read Python that builds and uses these structures (`list`, `dict`, `deque`, `heapq`), so that when `tinyzip` needs a priority queue or a hash table later, the code is already familiar.],
  [Point to the exact place each structure resurfaces later in the book — the Huffman tree in Chapter 24, the hash chains of DEFLATE in Chapter 30, the suffix structures of the BWT in Chapter 35.],
))

== What is an algorithm?

The word sounds technical, even forbidding, but you have followed algorithms all your life. A cooking recipe is an algorithm. Long division — the procedure you learned in school for dividing big numbers by hand — is an algorithm, and a famous one. The instructions for assembling flat-pack furniture are an algorithm (a badly written one). The common thread is this: a finite list of unambiguous steps that, started from some input, always finishes and produces the answer.

#definition("Algorithm")[
  An *algorithm* is a finite, unambiguous, step-by-step procedure that takes some *input*, carries out a definite sequence of operations, and *halts* after finitely many steps with the correct *output*. "Unambiguous" means a step leaves no room for interpretation; "finite" means it cannot run forever; "halts" means it actually stops.
]

The word itself is a fossil. It comes from *al-Khwārizmī*, a Persian scholar at the House of Wisdom in Baghdad around the year 820, whose book on calculating with the Hindu–Arabic numerals (the very digits 0–9 we still use) was so influential that medieval Europe latinised his name to _algorismus_ and used it to mean "the art of calculating." The same book gave us the word *algebra*, from _al-jabr_. So when you do arithmetic, you are quietly honouring a ninth-century Baghdad mathematician.

#history[
  The first algorithm written deliberately for a _machine_ is usually credited to *Ada Lovelace*, who in 1843 published a step-by-step method for the (never-built) Analytical Engine to compute the Bernoulli numbers — a table of fractions that show up all over mathematics. She also saw, more than a century early, that such a machine could manipulate _any_ symbols, not just numbers: "The engine might compose elaborate and scientific pieces of music." She was describing software before there was hardware to run it.
]

What turns a procedure into a _useful_ algorithm is that it works for _every_ input of its kind, not just one. Long division divides _any_ two whole numbers; it does not need a fresh idea for each pair. Compression algorithms are the same: Huffman's method (Chapter 24) builds an optimal code for _any_ set of symbol frequencies you hand it. The procedure is fixed; the input varies; the answer is always right. That generality is what we are buying.

=== Pseudocode: writing a procedure before choosing a language

Before we commit an algorithm to Python or any real language — with all its punctuation and fuss — we sketch it in *pseudocode*: a half-English, half-code shorthand that captures the _logic_ and ignores the _ceremony_. Pseudocode has no official grammar; its only rule is that a human can read it without ambiguity. Here, for instance, is the phone-book trick — properly called *binary search* — written as pseudocode:

```
BINARY-SEARCH(A, target):
    lo ← 1
    hi ← length of A           # A is sorted in increasing order
    while lo ≤ hi:
        mid ← floor((lo + hi) / 2)
        if A[mid] = target:
            return mid          # found it, at position mid
        else if A[mid] < target:
            lo ← mid + 1        # target is in the upper half
        else:
            hi ← mid - 1        # target is in the lower half
    return NOT-FOUND
```

Read it slowly. `A` is our sorted list (the names). `lo` and `hi` mark the part of the list we are still searching — at the start, the whole thing. The arrow `←` means "becomes" (assignment: the left-hand name now holds the right-hand value). We look at the middle element `A[mid]`; if it is our target we are done; if our target is bigger, everything from `mid` down is too small, so we move `lo` up past `mid`; otherwise we move `hi` down. Each pass throws away half of what remains. The indented block under `while` repeats as long as the condition `lo ≤ hi` holds — that indentation _is_ the loop body, a convention we will keep.

#keyidea[
  Pseudocode lets you reason about the _shape_ of a procedure — its loops, its choices, its repetition — without drowning in the syntax of a particular language. Every algorithm in this book first appears as pseudocode, then (when it joins `tinyzip`) as real, runnable Python. Get fluent at reading the pseudocode and the Python will feel like a translation, not a new language.
]

#gopython("Reading your first Python: variables, `while`, `if`")[
  Python is the language we build `tinyzip` in, and Chapters 15–17 will teach it properly. For now you only need to _read_ it. Here is the same binary search, in Python 3.14:

  ```python
  def binary_search(a: list[int], target: int) -> int:
      lo = 0                       # Python counts positions from 0
      hi = len(a) - 1              # len(a) is the number of items
      while lo <= hi:              # repeat while this is true
          mid = (lo + hi) // 2     # // is whole-number division
          if a[mid] == target:     # == asks "are these equal?"
              return mid           # hand back the position, stop
          elif a[mid] < target:    # "else if"
              lo = mid + 1
          else:
              hi = mid - 1
      return -1                    # -1 is our "not found" signal
  ```

  Line by line: `def` _defines_ a function named `binary_search`; the words in parentheses are its *inputs* (Python calls them _parameters_), and `-> int` promises it hands back a whole number. `=` stores a value in a name (`lo = 0` makes `lo` hold zero). `len(a)` counts the items in the list `a`. Python numbers list positions starting at *0*, not 1 — so the first item is `a[0]` — which is why `hi` starts at `len(a) - 1`. The `while` line repeats the indented block beneath it as long as `lo <= hi` is true. `//` is _floor division_ (divide and throw away any remainder), `==` tests equality (a single `=` would mean "store", a classic beginner trap), and `return` ends the function and gives back a value. We will meet every one of these pieces again, slowly, in the Python primer chapters.
]

== Measuring cost: the idea of complexity

We now have two ways to find a name — read every entry, or binary-search a sorted list. Both are correct. One is wildly faster. To say _how_ much faster, and to make that statement survive faster computers and bigger phone books, we need a way to measure an algorithm's cost that does not depend on the machine, the programming language, or the time of day.

The naive idea — "time it with a stopwatch" — fails immediately. A laptop from 2026 runs the same code a thousand times faster than a laptop from 2006; timing tells you about the _machine_, not the _algorithm_. So we measure something the machine cannot change: the _number of basic steps_ the algorithm takes, as a function of the input size. Call the input size $n$ (a million names means $n = 1000000$). Reading every entry takes about $n$ steps. Binary search takes about $log_2 n$ steps, because each step halves what remains. For a million names that is $1000000$ versus about $20$. _That_ ratio is a property of the algorithms, true on any machine, in any year.

#gomaths("Why halving gives a logarithm")[
  We met logarithms in Chapter 7: $log_2 n$ is "how many times you can halve $n$ before reaching 1," equivalently "the power you must raise 2 to in order to get $n$." Binary search halves its search range every step. Start with $n$ items; after one step about $n/2$ remain; after two, $n/4$; after $k$ steps, $n / 2^k$. The search ends when one item is left, i.e. when $n / 2^k approx 1$, which means $2^k approx n$, which means $k approx log_2 n$. So the _number of halving steps is the logarithm of the size_. A million ($approx 2^20$) needs about 20 steps; a billion ($approx 2^30$) needs about 30. Doubling the data adds a _single_ step. That gentle growth is the whole reason sorted data is precious.
]

But "about $n$ steps" and "about $log_2 n$ steps" are still a little vague — do we count the `+1`, the comparison, the assignment? It turns out we should _not_ sweat those details, and there is a beautiful notation that tells us exactly which details to ignore and which to keep. It is called Big-O, and it is the single most useful piece of vocabulary a programmer owns.

== Big-O notation from scratch

Big-O notation answers one question: *as the input grows without bound, how does the cost grow?* It deliberately throws away two kinds of detail that do not matter for that question — constant factors, and lower-order terms — and keeps the one thing that does: the _dominant growth rate_. Let us build it up with no hand-waving.

Suppose careful counting shows an algorithm does exactly $f(n) = 3n^2 + 50n + 200$ basic operations on an input of size $n$. Which term matters? Watch what happens as $n$ grows:

#fig([How the three terms of $3n^2 + 50n + 200$ compare as $n$ grows. By $n = 1000$ the $n^2$ term utterly dominates; the other two are rounding error.],
  table(columns: 5, inset: 5pt, align: (right, right, right, right, right),
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
    table.header([$n$], [$3n^2$], [$50n$], [$200$], [share from $n^2$]),
    [$1$], [$3$], [$50$], [$200$], [$1.2%$],
    [$10$], [$300$], [$500$], [$200$], [$30%$],
    [$100$], [$30000$], [$5000$], [$200$], [$85%$],
    [$1000$], [$3000000$], [$50000$], [$200$], [$98.4%$],
    [$10^6$], [$3 times 10^12$], [$5 times 10^7$], [$200$], [$99.998%$],
  ))

By the time $n$ is large, the $3n^2$ term is essentially the _whole_ cost; the $50n$ and the $200$ are noise. And the constant $3$ in front? It rescales the whole curve but does not change its _shape_ — a machine twice as fast erases it. So for the purpose of "how does cost grow with $n$," all that survives is _$n$ squared_. We write this $O(n^2)$, read "big-oh of $n$ squared" or "order $n$ squared," and we say the algorithm _runs in quadratic time_.

#definition("Big-O notation (informal, the working definition)")[
  We say an algorithm's running time is $O(g(n))$ — "order $g(n)$" — if, for all large enough $n$, its number of steps is at most a constant multiple of $g(n)$. In words: $g(n)$ is an _upper bound on the growth rate_, ignoring constant factors and small-$n$ wobbles. To find the $O(dot)$ of a count like $3n^2 + 50n + 200$: (1) drop all but the fastest-growing term, leaving $3n^2$; (2) drop the constant factor, leaving $n^2$; (3) write $O(n^2)$.
]

#gomaths("Big-O, stated carefully")[
  The precise definition, which you can now appreciate, is: $f(n) = O(g(n))$ means there exist a constant $c > 0$ and a size $n_0$ such that $f(n) <= c dot g(n)$ for every $n >= n_0$. The phrase "for every $n >= n_0$" is the "for all large enough $n$" part; the $c$ is the "ignoring constant factors" part. Example: is $3n^2 + 50n + 200 = O(n^2)$? Take $c = 4$. For all $n >= 51$ we have $50n <= n^2$ and $200 <= n^2$, so $3n^2 + 50n + 200 <= 3n^2 + n^2 + n^2 = 5n^2$ — fine, take $c = 5$, $n_0 = 51$, and the inequality $f(n) <= 5 n^2$ holds. The bound is verified. Two sibling notations complete the family: $Omega(g(n))$ (big-omega) is a _lower_ bound — at least order $g$ — and $Theta(g(n))$ (big-theta) means _both_ at once, the growth is _exactly_ order $g$. Binary search is $Theta(log n)$: never more, never fewer, than about $log n$ steps in the worst case.
]

#algo(
  name: "Big-O notation",
  year: "1894 / 1976",
  authors: "Paul Bachmann (1894), Edmund Landau (1909), adapted to computing by Donald Knuth (1976)",
  aim: "Describe how an algorithm's resource use (time or memory) grows with input size, independent of machine speed or constant factors.",
  complexity: "—",
  strengths: "Machine-independent; composable; predicts behaviour at scale; the universal language for comparing algorithms.",
  weaknesses: "Hides constant factors that matter in practice (a $20n$ algorithm can beat a $n log n$ one for small $n$); says nothing about real wall-clock time; worst-case can be pessimistic.",
  superseded: "Still universal; refined by amortised and average-case analysis where needed.",
)[
  The capital $O$ stands for the German _Ordnung_, "order [of magnitude]," and was introduced by the number theorist Paul Bachmann in 1894 and popularised by Edmund Landau — hence "Bachmann–Landau notation." For decades it lived only in pure mathematics, describing how error terms shrink. It was *Donald Knuth* who, in a 1976 note ("Big Omicron and Big Omega and Big Theta") and across his monumental _The Art of Computer Programming_, deliberately repurposed it for analysing algorithms and added the companion notations $Omega$ (lower bound) and $Theta$ (tight bound). That act gave computer science its measuring stick. When anyone today says an algorithm "is $O(n log n)$," they are speaking Knuth's adaptation of Bachmann's notation.
]

=== The complexity zoo: the handful of growth rates you will ever meet

Almost every algorithm you encounter falls into one of a small number of complexity classes. Learn these seven by feel and you can size up most code on sight. Here they are, from fastest-growing-is-best to worst, with a concrete sense of what each does to a million-item input.

#fig([The growth rates that matter, with steps for $n = 1{,}000{,}000$. The jump from $O(n log n)$ to $O(n^2)$ is the cliff that separates "runs instantly" from "go get coffee."],
  table(columns: 4, inset: 5pt, align: (left, left, right, left),
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
    table.header([Notation], [Name], [Steps at $n=10^6$], [Where you see it]),
    [$O(1)$], [constant], [$1$], [Look up `array[i]`; push to a stack.],
    [$O(log n)$], [logarithmic], [$approx 20$], [Binary search; heap insert.],
    [$O(n)$], [linear], [$10^6$], [Scan a file once; count byte frequencies.],
    [$O(n log n)$], [linearithmic], [$approx 2 times 10^7$], [Good sorting; building a Huffman code.],
    [$O(n^2)$], [quadratic], [$10^12$], [Naïve sort; comparing all pairs.],
    [$O(2^n)$], [exponential], [astronomically huge], [Trying every subset; brute-forcing keys.],
    [$O(n!)$], [factorial], [beyond astronomical], [Trying every ordering (the travelling salesman).],
  ))

The numbers in that middle column are not a curiosity; they are a wall. At a billion simple operations per second — roughly a modern core — an $O(n)$ pass over a million items takes a millisecond, an $O(n log n)$ sort takes about twenty milliseconds, and an $O(n^2)$ algorithm takes about a thousand seconds: _seventeen minutes_ versus a blink. Push to a billion items and the quadratic algorithm would run for over thirty years. This is why, when we build the match-finder for LZ77 in Chapter 28 and DEFLATE in Chapter 30, an enormous amount of cleverness goes into avoiding the "compare every position against every other position" trap that would make it $O(n^2)$ and therefore useless on real files.

#pitfall[
  Big-O hides constant factors, and sometimes they bite. An algorithm that is $O(n)$ but does fifty expensive operations per item can be slower _in practice_, for the file sizes you actually have, than an $O(n log n)$ one that does two cheap operations per step. Big-O tells you who wins _eventually_, as $n -> infinity$; it does not promise who wins on your particular 4 KB file. Real codec engineering lives exactly in this gap — which is why benchmarks (Chapter 36) exist alongside theory.
]

=== Worst, best, and average case

There is one more subtlety. An algorithm's cost can depend not just on the _size_ of the input but on its _contents_. Binary search, in the lucky case, finds the target on the very first middle-guess — that is the _best case_, $O(1)$, one step. In the unlucky case it halves all the way down — the _worst case_, $O(log n)$. And averaged over all positions the target might be in, it is still $O(log n)$. We almost always quote the *worst case*, for a simple reason: it is a _guarantee_. If I tell you an algorithm is $O(n log n)$ in the worst case, you know it can _never_ blow up on you, no matter how nasty the input. Best-case figures are nearly worthless (any algorithm looks great on its luckiest input), and average-case figures require you to assume a distribution over inputs, which is often a fiction.

#checkpoint[
  A friend's algorithm scans a list of $n$ items, and for _each_ item it does a binary search in a sorted list of the same $n$ items. What is the overall worst-case complexity?
][
  Outer scan: $n$ items. For each, a binary search: $O(log n)$. Multiply the nested costs: $n times O(log n) = O(n log n)$. Nested loops _multiply_ their counts — a rule we use constantly when reading code.
]

=== Reading the Big-O straight off the code

You rarely count operations as carefully as we did for $3n^2 + 50n + 200$. In practice you read structure. A few rules cover most cases:

- A *straight line of work* with no loop is $O(1)$ — constant, however many statements, as long as the count does not grow with $n$.
- A *single loop* that runs $n$ times is $O(n)$.
- A *loop inside a loop*, each running $n$ times, is $O(n times n) = O(n^2)$ — nested loops multiply.
- A loop that *halves* its range each pass is $O(log n)$.
- *Sequential* (not nested) blocks _add_, and then you keep only the biggest: an $O(n)$ pass followed by an $O(n^2)$ pass is $O(n^2)$.

Here is a tiny example to read. What is its complexity?

```python
def has_duplicate(items: list[int]) -> bool:
    for i in range(len(items)):          # runs n times
        for j in range(i + 1, len(items)):  # runs up to n times
            if items[i] == items[j]:     # O(1) check
                return True
    return False
```

Two nested loops, each up to $n$ long, with $O(1)$ work inside: that is $O(n^2)$. This `has_duplicate` compares every pair, and for a million items it would do roughly half a trillion comparisons — minutes of work. In a moment we will see how a _hash table_ crushes this same problem to $O(n)$: a thousandfold-plus speed-up that comes entirely from choosing a better data structure. That is the lesson the whole chapter is circling toward.

#gopython("`for`, `range`, and the `list`")[
  Three pieces of Python appear above. A *list* is Python's everyday ordered collection, written with square brackets: `items = [5, 2, 9, 2]` holds four numbers in order, reachable by position as `items[0]` (the `5`) through `items[3]` (the second `2`). `len(items)` gives `4`. The `for` loop walks through a sequence, binding each value in turn to a name: `for x in items:` runs its body once with `x = 5`, then `x = 2`, and so on. `range(n)` manufactures the whole numbers `0, 1, 2, ..., n-1` — exactly the valid positions of an $n$-item list — so `for i in range(len(items)):` visits each position. `range(i + 1, len(items))` starts at `i + 1` instead of `0`, which is how the inner loop above avoids comparing an item with itself or re-checking a pair. Lists and `for`/`range` are the bread and butter of `tinyzip`; Chapter 16 gives them the full treatment.
]

== The toolbox: data structures

An algorithm is only as fast as the data it works on lets it be. A *data structure* is a deliberate arrangement of data in memory, chosen so that the operations you care about — looking up, inserting, deleting, finding the smallest — are cheap. There is no universally best structure; each one is a bargain, fast at some things and slow at others, and the art is matching the structure to the job. We now tour the structures every compressor relies on, building each from the ground up and tagging each operation with its Big-O cost.

=== The array: the bedrock

The simplest structure is the one your computer's memory already _is_. An *array* is a block of equal-sized slots laid end to end in memory, numbered from 0. Because the slots are equal-sized and contiguous, the computer can find slot number `i` by pure arithmetic — "start address, plus `i` times slot-size" — without looking at any other slot. That is the array's superpower: *random access in $O(1)$*. Slot 5 and slot 5,000,000 cost exactly the same to reach.

#fig([An array of bytes. Each cell is one slot; the index below it is its position. Reaching any cell is one arithmetic step — $O(1)$ — because the address is computed, not searched.],
  cetz.canvas({
    import cetz.draw: *
    let vals = ("72","101","108","108","111")
    for (i, v) in vals.enumerate() {
      rect((i*1.3, 0), (i*1.3 + 1.2, 0.9), fill: c-accent.lighten(80%))
      content((i*1.3 + 0.6, 0.45))[#text(size: 9pt)[#v]]
      content((i*1.3 + 0.6, -0.35))[#text(size: 8pt, fill: c-accent2)[\[#i\]]]
    }
    content((3.2, 1.4))[#text(size: 8pt)[address = base + i × slotsize]]
  }))

What an array is _bad_ at is changing its size and shifting things around. To insert a new value at the front, every existing element must shuffle one slot to the right to make room — that is $n$ moves, $O(n)$. Deleting from the front is the same. So arrays are superb when you mostly _read by position_ and rarely insert in the middle, and poor when you constantly insert and delete at the front. In compression, arrays (and their Python cousin, the `list`) are everywhere: the 256-entry frequency table that counts how often each byte value appears is an array, indexed directly by the byte value — count byte `b` by doing `freq[b] += 1`, an $O(1)$ step we will run for every byte of the input.

#note[
  This chapter is `tinyzip` _groundwork_, not a build step — the project's first real code arrives in Chapter 15, where we lay down the package skeleton, and its first helper, `utils.histogram`, in Chapter 16. But the byte-frequency table is the perfect illustration of "the array is the right structure," so here is a preview of exactly that helper. Every entropy coder in this book starts the same way: count how often each of the 256 possible byte values appears, in an array indexed directly by the byte value.

  ```python
  def histogram(data: bytes) -> list[int]:
      """Return a 256-slot table: freq[b] = how many times byte b appears."""
      freq = [0] * 256          # an array of 256 zeros, indexed 0..255
      for b in data:            # b takes each byte value, an int 0..255
          freq[b] += 1          # O(1) bump of slot b
      return freq
  ```

  The whole function is one pass over the data — $O(n)$ for $n$ bytes — with an $O(1)$ array bump inside the loop. You cannot count frequencies faster than reading every byte once, so this is optimal. (`bytes` is Python's type for raw binary data, a read-only array of integers each in $0..255$; iterating it with `for b in data` hands you those integers directly. Chapter 17 builds the binary-I/O toolkit around `bytes` in full.) This is the `utils.histogram` we will formally add to `tinyzip` in Chapter 16; from Chapter 24 onward it feeds Huffman, arithmetic, and ANS coding alike.
]

=== The linked list: cheap insertion, costly lookup

The array's weakness — expensive insertion — is the *linked list's* strength. Instead of one contiguous block, a linked list scatters its elements anywhere in memory and threads them together with pointers: each *node* holds a value _and_ the address of the next node, like a paper chase where each clue tells you where the next clue is hidden. To insert a new node, you do not shuffle anything; you just re-thread two pointers — the previous node now points at the newcomer, and the newcomer points at what used to come next. That is $O(1)$ insertion, anywhere, once you are standing at the spot.

#fig([A linked list. Each node holds a value and an arrow to the next; the last points at nothing (∅). Inserting between two nodes re-threads two arrows — $O(1)$ — but reaching the $k$-th node means following $k$ arrows — $O(n)$.],
  cetz.canvas({
    import cetz.draw: *
    let vals = ("H","e","l","o")
    for (i, v) in vals.enumerate() {
      rect((i*2.4, 0), (i*2.4 + 1.0, 0.9), fill: c-key.lighten(80%))
      content((i*2.4 + 0.5, 0.45))[#text(size: 10pt)[#v]]
      if i < vals.len() - 1 {
        line((i*2.4 + 1.0, 0.45), (i*2.4 + 2.4, 0.45), mark: (end: ">"))
      }
    }
    content((vals.len()*2.4 - 0.6, 0.45))[#text(size: 11pt)[∅]]
  }))

The price is the mirror image of the array's. There is no arithmetic shortcut to the $k$-th node; you must start at the head and follow $k$ arrows, one at a time — *$O(n)$ lookup by position*. So the array and the linked list are exact trade-offs: the array gives instant lookup but slow insertion; the linked list gives instant insertion but slow lookup. Knowing which operation your algorithm does _often_ tells you which structure to pick. (Python's built-in `list`, despite the name, is actually an array under the hood; true linked behaviour comes from `collections.deque`, which we meet next.)

=== Stacks and queues: order of service

Some structures are defined not by _how_ they store data but by the _order_ in which they hand it back. Two are fundamental.

A *stack* is "last in, first out" (LIFO) — like a stack of plates, you add to the top and remove from the top, so the most recently added item is the first to leave. Its two operations are *push* (add to top) and *pop* (remove from top), both $O(1)$. Stacks appear wherever you must remember "what to do when I get back," especially in anything _recursive_ or _nested_: undo histories, expression parsing, and — crucially for us — the inverse Burrows–Wheeler transform and the tree-walks inside Huffman decoding (Chapters 24 and 35) lean on stack-like bookkeeping.

A *queue* is "first in, first out" (FIFO) — like a line at a shop, the earliest arrival is served first. Its operations are *enqueue* (join the back) and *dequeue* (leave the front), both $O(1)$ when built well. Queues model fair, in-order processing: streaming buffers, the sliding window of LZ77 (oldest bytes leave the window first, Chapter 28), and breadth-first walks over trees.

#fig([Stack (LIFO) versus queue (FIFO). The stack pushes and pops at the same end; the queue adds at the back and removes from the front. Both do their core operations in $O(1)$.],
  cetz.canvas({
    import cetz.draw: *
    // stack
    content((1, 3.3))[#text(size: 9pt, weight: "bold")[Stack — LIFO]]
    for (i, v) in ("A","B","C").enumerate() {
      rect((0.4, i*0.7), (1.6, i*0.7 + 0.6), fill: c-note.lighten(80%))
      content((1.0, i*0.7 + 0.3))[#text(size: 9pt)[#v]]
    }
    line((2.0, 1.9), (3.0, 1.9), mark: (end: ">", start: ">"))
    content((2.5, 2.3))[#text(size: 7.5pt)[push/pop]]
    // queue
    content((6.2, 3.3))[#text(size: 9pt, weight: "bold")[Queue — FIFO]]
    for (i, v) in ("A","B","C").enumerate() {
      rect((4.6 + i*1.1, 1.0), (5.6 + i*1.1, 1.6), fill: c-accent.lighten(80%))
      content((5.1 + i*1.1, 1.3))[#text(size: 9pt)[#v]]
    }
    line((4.4, 1.3), (4.0, 1.3), mark: (end: ">"))
    content((4.0, 1.75))[#text(size: 7.5pt)[out (front)]]
    line((8.0, 1.3), (8.6, 1.3), mark: (start: ">"))
    content((8.5, 1.75))[#text(size: 7.5pt)[in (back)]]
  }))

#gopython("`collections.deque` — a fast stack and queue")[
  A plain Python `list` makes a fine stack: `s.append(x)` pushes, `s.pop()` pops, both $O(1)$. But using a list as a _queue_ is a trap — removing from the front, `s.pop(0)`, shifts every other element left, an $O(n)$ blunder. For queues, Python gives you `deque` (a "double-ended queue," pronounced "deck") from the `collections` module:

  ```python
  from collections import deque
  q = deque()           # an empty double-ended queue
  q.append("A")         # join the back     -> deque(["A"])
  q.append("B")         #                   -> deque(["A","B"])
  first = q.popleft()   # leave the front   -> first == "A"
  ```

  `append` and `popleft` are both $O(1)$, so a `deque` is the right structure whenever `tinyzip` needs a FIFO buffer — for example the sliding window of bytes in our LZ77 work later. The line `from collections import deque` is an _import_: it pulls a tool out of Python's standard library so you can use it by name.
]

=== The hash table: instant lookup by key

So far we look things up either by _position_ (arrays, $O(1)$) or by _walking_ (linked lists, $O(n)$). But often we want to look something up by a _key_ that is not a position — "has the word `the` appeared before?", "what code did I assign to this three-byte sequence?" The structure that does this in $O(1)$ _on average_ is the *hash table*, and it is, quietly, one of the most important inventions in computing.

The idea is a magic trick built on a humble function. A *hash function* takes a key of any kind — a string, a number, a chunk of bytes — and scrambles it into a number in a fixed range, say $0$ to $m - 1$. We keep an array of $m$ buckets, and we store each key in the bucket its hash function points to. To look a key up later, we hash it again — the _same_ key always hashes to the _same_ bucket — and look only in that one bucket. We never search the whole table; the hash function _computes_ where to look, just as the array index did. That is the $O(1)$.

#fig([A hash table. The hash function maps each key to a bucket index; lookups recompute the hash and visit only that bucket. Two keys landing in the same bucket — a _collision_ — are chained together in a short linked list.],
  cetz.canvas({
    import cetz.draw: *
    content((1.2, 3.4))[#text(size: 8.5pt)[keys]]
    for (i, k) in ("\"cat\"","\"dog\"","\"emu\"").enumerate() {
      content((1.2, 2.6 - i*0.8))[#text(size: 9pt, font: ("DejaVu Sans Mono",))[#k]]
    }
    content((3.6, 3.4))[#text(size: 8.5pt)[hash]]
    for i in range(3) { line((2.2, 2.6 - i*0.8), (4.4, 2.4 - i*0.9), mark: (end: ">")) }
    content((3.6, 0.0))[#text(size: 7.5pt, fill: c-accent2)[h(key) mod m]]
    content((6.0, 3.4))[#text(size: 8.5pt)[buckets]]
    for i in range(4) {
      rect((5.4, 2.0 - i*0.7), (6.6, 2.6 - i*0.7), fill: c-warn.lighten(82%))
      content((7.0, 2.3 - i*0.7))[#text(size: 7.5pt, fill: c-accent2)[\[#i\]]]
    }
  }))

The catch is *collisions*: two different keys can hash to the same bucket. A good hash function spreads keys so evenly that collisions are rare, and when they do happen we handle them — most simply by keeping a tiny linked list in each bucket (this is called _chaining_) and walking it. As long as the table is not too full and the hash spreads well, each bucket holds about one item, so lookups, insertions, and deletions are all $O(1)$ _on average_. The "on average" matters: in a pathological worst case where every key collides, a hash table degrades to a single linked list and $O(n)$ — but with a decent hash function this essentially never happens by accident.

Now we can cash the promise from earlier. Remember `has_duplicate`, the $O(n^2)$ pair-checker? With a hash table — Python's `set`, a hash table that just stores keys — it collapses to a single pass:

```python
def has_duplicate(items: list[int]) -> bool:
    seen: set[int] = set()       # an empty hash table of "things I've seen"
    for x in items:              # one pass: O(n)
        if x in seen:            # O(1) average membership test
            return True
        seen.add(x)              # O(1) average insertion
    return False
```

One loop, $O(1)$ work inside, total $O(n)$. On a million items this is the difference between a millisecond and several minutes — and the _only_ thing we changed was the data structure. This is the chapter's thesis in a single example: *the right structure can change an algorithm's entire complexity class.*

Hash tables are woven through compression. LZ77 and DEFLATE (Chapters 28, 30) find repeated strings by hashing short byte-sequences and keeping, in a hash table, a list of every place each sequence was last seen — turning "have I seen these three bytes before, and where?" into an $O(1)$ question. LZW (Chapter 29) stores its growing dictionary of byte-strings in a hash table. Without hash tables, none of these would run at practical speed.

#gomaths("What makes a hash function 'good'")[
  A hash function $h$ maps keys to bucket numbers $0, 1, ..., m-1$. We want two things. First, _determinism_: the same key must always give the same number, or lookup is impossible. Second, _uniform spreading_: keys should scatter across buckets as evenly as if chosen at random, so no bucket gets crowded. A classic toy hash for a string treats its bytes $b_1, b_2, ..., b_k$ as digits of a number in some base $a$ and reduces modulo $m$:
  $ h = (b_1 a^(k-1) + b_2 a^(k-2) + dots.c + b_k) mod m. $
  The "mod $m$" (remainder after dividing by $m$, from Chapter 4) folds the big number back into the bucket range; a well-chosen base $a$ and a prime $m$ make different strings collide rarely. Real hash functions are more elaborate and battle-tested, but this captures the spirit: _mix the key's bits thoroughly, then take a remainder_.
]

#misconception[Hash tables are always $O(1)$, so they are always the fastest choice.][
  The $O(1)$ is an _average_ over good hash behaviour, not a guarantee. A bad hash function, or an adversary who deliberately feeds colliding keys, can drive a hash table to $O(n)$ per operation — a real denial-of-service technique. And the constant factor hidden in that $O(1)$ — computing the hash, chasing a pointer to the bucket — can make a hash table _slower_ than a plain array scan for small collections. Hash tables shine when the key set is large and the keys are not simple positions; for a 256-entry byte table, the humble array wins every time.
]

#gopython("`dict` and `set` — Python's built-in hash tables")[
  Two of Python's most-used types are hash tables in disguise. A *set* stores unique keys; `seen = set()` makes an empty one, `seen.add(x)` inserts, and `x in seen` tests membership — all $O(1)$ on average. A *dict* (dictionary) stores key-to-value _pairs_, like a real dictionary mapping words to definitions:

  ```python
  code: dict[str, str] = {}     # empty dict, keys are str, values are str
  code["e"] = "0"               # store: the key "e" maps to "0"
  code["t"] = "10"              # store another pair
  print(code["e"])              # look up by key -> prints "0"
  print("t" in code)            # membership test -> True
  ```

  The type hint `dict[str, str]` reads "a dict whose keys are strings and whose values are strings" — modern Python 3.14 style, which Chapter 16 explains fully. `dict` is exactly the structure a Huffman _decoder_ uses to map each bit-pattern back to its symbol, and the structure LZW uses for its dictionary. When you reach for "look something up by a key, fast," you reach for `dict`.
]

=== Trees: hierarchy and the shape of a code

Everything so far has been _flat_ — a line of slots, a chain of nodes, a row of buckets. A *tree* is the first structure with _shape_. It is a branching hierarchy: one *root* node at the top, each node holding *children* below it, every child reachable by exactly one path from the root, and no loops. The picture is an upside-down family tree, or the folder structure on your computer (a folder contains files and sub-folders, which contain more, and so on). Nodes with no children are *leaves*; the number of steps from the root down to the deepest leaf is the tree's *height*.

#fig([A small *binary tree* (each node has at most two children). The root is on top; leaves are shaded. The path from the root to any leaf spells out a sequence of left/right turns — the idea behind every prefix code.],
  cetz.canvas({
    import cetz.draw: *
    let node(x, y, lbl, leaf: false) = {
      circle((x, y), radius: 0.32, fill: if leaf { c-key.lighten(70%) } else { c-accent.lighten(75%) })
      content((x, y))[#text(size: 8.5pt)[#lbl]]
    }
    line((0,0),(-2,-1.4)); line((0,0),(2,-1.4))
    line((-2,-1.4),(-3,-2.8)); line((-2,-1.4),(-1,-2.8))
    line((2,-1.4),(1,-2.8)); line((2,-1.4),(3,-2.8))
    node(0,0,"•")
    node(-2,-1.4,"•"); node(2,-1.4,"•")
    node(-3,-2.8,"a", leaf: true); node(-1,-2.8,"b", leaf: true)
    node(1,-2.8,"c", leaf: true); node(3,-2.8,"d", leaf: true)
    content((-1.6,-0.5))[#text(size: 7.5pt, fill: c-warn)[0]]
    content((1.6,-0.5))[#text(size: 7.5pt, fill: c-warn)[1]]
    content((-3.0,-2.0))[#text(size: 7.5pt, fill: c-warn)[0]]
    content((-1.0,-2.0))[#text(size: 7.5pt, fill: c-warn)[1]]
  }))

Trees matter to us more than any other structure, because *a prefix code is a binary tree*. This is the heart of Chapter 24, but you can see it now. Label every left branch `0` and every right branch `1`. Put each symbol on a leaf. The codeword for a symbol is the string of `0`s and `1`s you read off on the way down from the root to its leaf. In the figure, `a` is `00`, `b` is `01`, `c` is `10`, `d` is `11`. Because every symbol sits on a _leaf_ — never on the path to another symbol — no codeword is a prefix of another, which is exactly what lets a decoder read a stream of bits and know precisely where one symbol ends and the next begins. Huffman's algorithm is nothing but a recipe for _building the best-shaped such tree_ from symbol frequencies, putting common symbols on shallow leaves (short codes) and rare ones on deep leaves (long codes). Trees also underlie the quadtrees that carve up video frames in HEVC (Chapter 53) and the parse trees of more elaborate codecs.

A well-balanced binary tree of $n$ leaves has height about $log_2 n$, which is why tree operations — searching a sorted _binary search tree_, walking root-to-leaf — are typically $O(log n)$. A tree gone wrong (every node with one child) degenerates into a linked list of height $n$ and loses the advantage; keeping trees balanced is a craft of its own that we will not need in full, because the trees compression builds are balanced _by construction_.

=== Heaps and priority queues: always grab the smallest

We save the most important structure for `tinyzip` for last, because Huffman's algorithm depends on it utterly. The task it solves: maintain a changing collection of items so that, at any moment, you can pull out the _smallest_ (or largest) one cheaply — and keep doing so as you add more.

You could keep the collection sorted and grab the front, but re-sorting after every insertion is wasteful. You could scan for the minimum each time — $O(n)$ per grab. The structure that does it in $O(log n)$ is the *heap*, and a heap used this way is called a *priority queue*: a queue where items leave not by arrival order but by _priority_ (smallest first).

A *binary heap* is a binary tree with one simple rule, the *heap property*: every parent is smaller than or equal to its children (for a "min-heap"). The smallest item is therefore always sitting at the root, free to grab in $O(1)$. When you remove it, you patch the hole by moving the last leaf up to the root and letting it "sink" — repeatedly swapping with its smaller child until the heap property holds again, which takes at most the tree's height, $O(log n)$, steps. Inserting works in reverse: drop the new item at the bottom and let it "bubble up" past any larger parents, again $O(log n)$. Cleverly, a heap needs no pointers at all — it packs the tree into a plain array, with the children of slot $i$ living at slots $2i+1$ and $2i+2$. It is a tree wearing an array's body.

#fig([A min-heap: every parent ≤ its children, so the minimum (1) is always at the root, removable in $O(1)$. Insert and remove cost $O(log n)$ — the height. Huffman repeatedly removes the two smallest frequencies and inserts their sum.],
  cetz.canvas({
    import cetz.draw: *
    let node(x, y, lbl) = { circle((x, y), radius: 0.32, fill: c-note.lighten(72%)); content((x, y))[#text(size: 9pt)[#lbl]] }
    line((0,0),(-1.8,-1.3)); line((0,0),(1.8,-1.3))
    line((-1.8,-1.3),(-2.8,-2.5)); line((-1.8,-1.3),(-0.8,-2.5))
    line((1.8,-1.3),(0.8,-2.5))
    node(0,0,"1")
    node(-1.8,-1.3,"3"); node(1.8,-1.3,"5")
    node(-2.8,-2.5,"4"); node(-0.8,-2.5,"8"); node(0.8,-2.5,"6")
  }))

Why does Huffman need exactly this? To build an optimal code, Huffman repeatedly does: _take the two least-frequent symbols, merge them into a combined node whose frequency is their sum, and put that back_. "Take the two least-frequent" is two removals of the minimum; "put the merged node back" is an insertion. With $n$ symbols this is about $n$ rounds, each costing $O(log n)$ heap operations, for $O(n log n)$ overall — fast enough to build a code for a whole file in a heartbeat. Try it with a sorted list instead and every round costs $O(n)$, dragging the whole thing to $O(n^2)$. The heap is _why_ Huffman is practical.

#algo(
  name: "Binary heap (priority queue)",
  year: "1964",
  authors: "J. W. J. Williams (for Heapsort)",
  aim: "Maintain a collection so the minimum (or maximum) is always retrievable in $O(1)$, with $O(log n)$ insertion and removal.",
  complexity: "find-min $O(1)$; insert $O(log n)$; remove-min $O(log n)$; build from $n$ items $O(n)$.",
  strengths: "Tiny memory (just an array, no pointers); the perfect engine for 'repeatedly grab the smallest'; underpins Huffman, Dijkstra's shortest paths, event simulation.",
  weaknesses: "Only gives you the extreme element — no fast search for an arbitrary value; not sorted internally.",
  superseded: "Still standard; specialised variants (Fibonacci, pairing heaps) exist for niche needs.",
)[
  Invented by J. W. J. Williams in 1964 as the engine of his _Heapsort_ algorithm, the binary heap is the textbook priority queue. Its genius is fitting a tree into a flat array via the index arithmetic "children of $i$ are at $2i+1$ and $2i+2$," giving tree-shaped logic with array-tight memory and cache behaviour. Python ships it as the `heapq` module — the exact tool `tinyzip` will use to build Huffman codes in Chapter 24.
]

#gopython("`heapq` — the priority queue `tinyzip` needs")[
  Python does not have a separate heap _type_; instead the `heapq` module turns an ordinary `list` into a min-heap in place. The two operations you need are `heappush` (insert) and `heappop` (remove and return the smallest):

  ```python
  import heapq
  h: list[int] = []            # an ordinary list, used as a heap
  heapq.heappush(h, 5)         # h is now a heap containing 5
  heapq.heappush(h, 1)
  heapq.heappush(h, 8)
  smallest = heapq.heappop(h)  # returns 1, the minimum  -> O(log n)
  next_one = heapq.heappop(h)  # returns 5
  ```

  `heapq` compares items to decide which is "smallest," so if you push *tuples* — `(frequency, symbol)` pairs, written with parentheses — it orders them by frequency first, exactly what Huffman wants. Here is the shape of the merge loop you will flesh out in Chapter 24:

  ```python
  import heapq
  def build_huffman_skeleton(freq: dict[str, int]) -> None:
      heap = [(count, sym) for sym, count in freq.items()]  # one tuple per symbol
      heapq.heapify(heap)                 # turn the list into a heap, O(n)
      while len(heap) > 1:                # until one node remains
          lo1 = heapq.heappop(heap)       # smallest frequency
          lo2 = heapq.heappop(heap)       # next smallest
          merged = (lo1[0] + lo2[0], ...) # combined node: summed frequency
          heapq.heappush(heap, merged)    # put it back, O(log n)
  ```

  `heapify` builds a heap from a whole list in one $O(n)$ shot; the `while` loop runs about $n$ times, each round doing two $O(log n)$ pops and one $O(log n)$ push, giving the $O(n log n)$ we predicted. The `...` is a placeholder for the child links we will fill in when we build the real tree. The point for now: the priority queue Huffman lives on is three lines of `heapq`.
]

== Two algorithms in full: searching and sorting

Data structures hold data; algorithms _do_ things to it. Two tasks come up so relentlessly — finding an item, and putting items in order — that their algorithms are worth meeting head-on. We have already met binary search; its partner is sorting, and the two are intimate, because _binary search only works on sorted data_, so something must do the sorting first.

=== A worked sort: why $O(n log n)$ beats $O(n^2)$

The obvious way to sort is the way you might sort a hand of cards: repeatedly find the smallest remaining item and place it next. With $n$ items you make $n$ passes, each scanning up to $n$ items for the minimum — that is $n times n = O(n^2)$, _selection sort_. Correct, simple, and hopeless on large data.

The breakthrough idea is *divide and conquer*: split the list in half, sort each half (by the same method, applied to itself — a _recursive_ call), then _merge_ the two sorted halves into one.

#gopython("Recursion: a procedure that calls itself")[
  A procedure is *recursive* when, to solve a problem, it calls _itself_ on a smaller version of the same problem. It sounds circular, but it is not, because each call works on _less_ data and there is always a _base case_ small enough to answer outright — so the chain of calls is finite and must end. Factorials are the classic illustration: $n! = n times (n-1)!$ (Chapter 8), with the base case $0! = 1$.

  ```python
  def factorial(n: int) -> int:
      if n == 0:            # base case: stop here, no further call
          return 1
      return n * factorial(n - 1)   # recursive call on a smaller n
  ```

  Asked for `factorial(3)`, Python computes `3 * factorial(2)`, which needs `2 * factorial(1)`, which needs `1 * factorial(0)`; the base case returns `1`, and the answers unwind back up: `1, 1, 2, 6`. Merge sort is recursive in the same shape: to sort a list, sort its two halves (the smaller subproblems) and merge — with the base case being a one-item list, which is already sorted. Behind the scenes each pending call waits on a *stack* (the structure we met earlier), which is why recursion and stacks are two faces of one idea.
] Merging two sorted lists is cheap — walk both with a finger on each, repeatedly taking the smaller front item — costing one $O(n)$ pass. The splitting goes $log_2 n$ levels deep (halving until single items, which are trivially sorted), and each level does $O(n)$ total merging work, for $O(n log n)$ in all. This is *merge sort*, and that $n log n$ is no accident: it can be _proved_ that no comparison-based sort can beat it.

#fig([Merge sort on `[3,1,2]` versus selection sort, on a list of $n$. Merge sort's $log n$ levels of $O(n)$ merging give $O(n log n)$; selection sort's $n$ scans of $O(n)$ give $O(n^2)$. For $n = 10^6$ that is ~20 million steps versus a trillion.],
  table(columns: 3, inset: 5pt, align: (left, right, right),
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
    table.header([Sort], [Worst-case time], [In one line]),
    [Selection sort], [$O(n^2)$], [Repeatedly scan for the minimum.],
    [Merge sort], [$O(n log n)$], [Split, sort halves, merge.],
    [Quicksort], [$O(n^2)$ worst, $O(n log n)$ usual], [Partition around a pivot, recurse.],
    [Heapsort], [$O(n log n)$], [Build a heap, pop the min $n$ times.],
  ))

#theorem("The comparison-sorting lower bound")[
  Any sorting algorithm that orders items _only_ by comparing pairs must, in the worst case, make at least about $n log_2 n$ comparisons. No comparison sort can be asymptotically faster than $O(n log n)$.
]

#proof[
  There are $n!$ possible orderings of $n$ distinct items (Chapter 8: $n$ choices for first, $n-1$ for second, and so on). A correct sort must be able to reach _every_ one of them, since any could be the right answer. Each comparison has two outcomes (less, or not), so a sequence of $k$ comparisons can distinguish at most $2^k$ different cases — picture a binary decision tree of depth $k$, with at most $2^k$ leaves. To tell all $n!$ orderings apart we need $2^k >= n!$, hence $k >= log_2(n!)$. By Stirling's estimate $log_2(n!) approx n log_2 n - n log_2 e$, which grows like $n log_2 n$. So _some_ input forces at least about $n log_2 n$ comparisons, and no comparison sort can beat that order. (This is why merge sort and heapsort, both $O(n log n)$, are essentially optimal — and why beating $n log n$ requires _not_ comparing, e.g. counting sort, which uses the array trick from earlier.)
]

#gomaths("Why $log_2(n!)$ grows like $n log_2 n$ (Stirling, lightly)")[
  The proof leaned on the fact that $log_2(n!) approx n log_2 n$. You can see _why_ without the famous (and heavier) *Stirling's approximation* $n! approx sqrt(2 pi n) (n/e)^n$. Recall from Chapter 7 that the logarithm of a product is the _sum_ of the logarithms. Since $n! = n times (n-1) times dots.c times 1$,
  $ log_2(n!) = log_2 n + log_2(n-1) + dots.c + log_2 1. $
  That is a sum of $n$ terms, and every term is _at most_ $log_2 n$, so the whole sum is at most $n log_2 n$. Going the other way, the largest _half_ of the terms (from $n/2$ up to $n$) are each at least $log_2(n/2) = log_2 n - 1$, and there are $n/2$ of them, so the sum is at least about $(n/2)(log_2 n - 1)$ — again of order $n log_2 n$. Squeezed from both sides, $log_2(n!)$ must grow like $n log_2 n$. Stirling's formula just sharpens the constant; the order is all the proof needs.
]

That last parenthesis matters for compression. The counting we did to build a frequency table is, in disguise, a _non-comparison_ sort: by bucketing each byte directly into `freq[b]`, we order all 256 possible values in a single $O(n)$ pass, sidestepping the $n log n$ wall because we never compare — we index. Knowing _when_ you can escape a lower bound by changing the rules of the game is exactly the kind of judgment this chapter is training.

== Time versus space: the compressor's eternal bargain

Every choice in this chapter has had a hidden second axis. We have measured _time_ (steps), but algorithms also cost _space_ (memory), and the two trade against each other constantly. The hash table that made duplicate-detection $O(n)$ in time _spent_ $O(n)$ in memory to hold the `seen` set — we bought speed with space. A heap packed into an array uses less memory than a pointer-based tree but is fiddlier to reason about. This tension is not a footnote in compression; it _is_ compression's central drama.

#keyidea[
  *Compression is a time–space–ratio negotiation with no free lunch.* A bigger dictionary or a larger search window finds more redundancy (better ratio) but needs more memory and more time to search. A richer statistical model predicts better (smaller output) but is slower to update. The whole landscape of codecs — from `LZ4`, which spends almost no time or memory for a modest ratio, to `cmix`, which spends gigabytes of RAM and hours of CPU for the record ratio (Chapter 34) — is just engineers picking different points on this trade-off surface for different needs.
]

You will see this bargain made explicit again and again. LZ77's window size (Chapter 28) trades memory for ratio. Arithmetic coding (Chapter 26) trades a little speed for hitting the entropy floor more tightly than Huffman. ANS (Chapter 27) was celebrated precisely because it broke an _apparent_ trade-off, delivering arithmetic-coding ratios at Huffman-like speed. And the giant neural compressors of Volume IV trade staggering amounts of computation for the best ratios known — the time–space dial turned to one extreme. Every one of these is the same bargain you just met, written large.

#aside[
  Python 3.14, released on 7 October 2025, even ships a brand-new `compression.zstd` module in its standard library — the Zstandard codec (Chapter 32) built right in. We will not use it for `tinyzip` (the whole point is to build our own), but it is a sign of how central these algorithms have become: a compression algorithm that was research in 2016 is a batteries-included part of the language a decade later. The same release also makes `bytes`-and-`int` heavy code faster, which our hand-built codecs will quietly benefit from.
]

=== A structures cheat-sheet

Keep this table within reach; it is the whole toolbox on one page, with the operation each structure makes cheap, and the chapter where it returns.

#fig([The data-structure toolbox, by cost of the core operations and by where each one resurfaces in this book. "avg" marks an average-case bound that can degrade in the worst case.],
  table(columns: 5, inset: 5pt, align: (left, center, center, center, left),
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
    table.header([Structure], [Lookup], [Insert], [Remove-min], [Returns in the book]),
    [Array / `list`], [$O(1)$ by index], [$O(n)$], [$O(n)$], [Frequency tables; every codec.],
    [Linked list], [$O(n)$], [$O(1)$], [$O(n)$], [Hash-bucket chains; LZ chains.],
    [Stack], [—], [$O(1)$], [—], [Decoder bookkeeping; BWT inverse (35).],
    [Queue / `deque`], [—], [$O(1)$], [—], [LZ77 sliding window (28).],
    [Hash table / `dict`], [$O(1)$ avg], [$O(1)$ avg], [—], [LZ/LZW match finding (28–30).],
    [Binary tree], [$O(log n)$], [$O(log n)$], [—], [Huffman/prefix codes (24); quadtrees (53).],
    [Heap / `heapq`], [—], [$O(log n)$], [$O(log n)$], [Building Huffman codes (24).],
  ))

#checkpoint[
  You must repeatedly pull the lowest-frequency symbol from a changing set of symbols, merging two at a time. Which structure makes this $O(log n)$ per step instead of $O(n)$, and which Python module provides it?
][
  A *min-heap* (priority queue), provided by Python's `heapq` module. Removing the minimum and inserting the merged node are each $O(log n)$; a sorted list or a linear scan would make each step $O(n)$. This is precisely the Huffman build loop.
]

#takeaways((
  [An *algorithm* is a finite, unambiguous, halting procedure; we sketch it in *pseudocode* before writing real Python.],
  [*Big-O notation* measures how cost _grows_ with input size $n$, dropping constant factors and lower-order terms. The classes to know by heart: $O(1)$, $O(log n)$, $O(n)$, $O(n log n)$, $O(n^2)$, $O(2^n)$.],
  [Read complexity off code by structure: single loop $O(n)$, nested loops multiply to $O(n^2)$, halving gives $O(log n)$; quote the *worst case* because it is a guarantee.],
  [Each data structure is a bargain. *Arrays* give $O(1)$ indexed access but slow insertion; *linked lists* the reverse; *stacks/queues* fix the order of service; *hash tables* give $O(1)$-average lookup by key; *trees* give hierarchy and prefix codes; *heaps* give the smallest element in $O(log n)$.],
  [Choosing the right structure can change an algorithm's whole complexity class — duplicate detection drops from $O(n^2)$ to $O(n)$ just by using a hash set.],
  [No comparison sort beats $O(n log n)$; counting (the frequency-table trick) escapes that wall by indexing instead of comparing.],
  [Compression is one long *time–space–ratio* negotiation; every codec in this book is a different point on that trade-off surface.],
  [`tinyzip`'s coming machinery is already in hand: the frequency *array*, the `deque` window, the `dict` for dictionaries and decode tables, and the `heapq` priority queue for Huffman.],
))

== Exercises

#exercise("14.1", 1)[
  Sort these growth rates from slowest-growing to fastest, for large $n$: $O(n^2)$, $O(log n)$, $O(2^n)$, $O(n)$, $O(1)$, $O(n log n)$. Then say, in plain words, which one you would most want an algorithm's running time to be, and which one you would most fear.
]
#solution("14.1")[
  Slowest to fastest growing: $O(1) < O(log n) < O(n) < O(n log n) < O(n^2) < O(2^n)$. You most _want_ $O(1)$ (constant — the cost never grows with input size, the holy grail). You most _fear_ $O(2^n)$ (exponential — adding one item _doubles_ the work, so even modest inputs become uncomputable). Note $O(1)$ is the _slowest-growing_ and therefore the _best_; "slow growth" is good when we are talking about cost.
]

#exercise("14.2", 1)[
  A function does the following on a list of $n$ items: first one loop that runs $n$ times, then _separately_ a pair of nested loops each running $n$ times. Give the overall Big-O. Explain why the first loop "disappears" from the answer.
]
#solution("14.2")[
  The first loop is $O(n)$; the nested pair is $O(n times n) = O(n^2)$. They are _sequential_ (one after the other, not nested), so their costs _add_: $O(n) + O(n^2)$. In a sum we keep only the fastest-growing term, so the total is $O(n^2)$. The first loop "disappears" because for large $n$ the $n^2$ term dwarfs the $n$ term — doing $n$ extra steps on top of $n^2$ steps changes the total by a vanishing fraction.
]

#exercise("14.3", 2)[
  You have a 10-million-byte file. Algorithm A scans it once: $O(n)$. Algorithm B compares every byte position against every other: $O(n^2)$. Assuming a billion simple operations per second, estimate the running time of each. What does this tell you about why LZ77 match-finders (Chapter 28) cannot afford to be $O(n^2)$?
]
#solution("14.3")[
  Here $n = 10^7$. Algorithm A: about $10^7$ operations $div 10^9$ per second $= 0.01$ s — a hundredth of a second. Algorithm B: about $(10^7)^2 = 10^14$ operations $div 10^9 = 10^5$ seconds $approx 27.8$ hours. A naïve "compare all pairs" match finder would take over a day on a 10 MB file — absurd. This is why LZ77 implementations use _hash tables_ (and hash chains) to jump straight to plausible matches, keeping the search close to $O(n)$ instead of $O(n^2)$. The data structure is what makes the codec usable.
]

#exercise("14.4", 2)[
  Explain, in your own words, why a hash table's lookup is $O(1)$ "on average" rather than guaranteed $O(1)$. Describe a specific situation in which it would degrade, and what the cost becomes then.
]
#solution("14.4")[
  Lookup is $O(1)$ on average because a good hash function spreads keys evenly, so each bucket holds about one item and you examine only that bucket. It is not _guaranteed_ because of *collisions*: if many keys hash to the same bucket, that bucket becomes a long linked list you must walk. In the pathological worst case — a bad hash function, or an adversary deliberately choosing keys that all collide — every key lands in one bucket and the table degrades to a single linked list, making lookup $O(n)$. (This is a real attack, called hash flooding, which is why production hash tables randomise their hash functions.)
]

#exercise("14.5", 2)[
  Write pseudocode (not necessarily Python) for an algorithm that takes a list of bytes and returns the byte value that occurs most often. State its time and space complexity, and identify which data structure makes it efficient.
]
#solution("14.5")[
  ```
  MOST-COMMON-BYTE(data):
      freq ← array of 256 zeros        # the array trick
      for each byte b in data:
          freq[b] ← freq[b] + 1        # O(1) bump
      best ← 0
      for v from 0 to 255:
          if freq[v] > freq[best]:
              best ← v
      return best
  ```
  The first loop is $O(n)$ over the $n$ bytes; the second is a fixed 256 iterations, $O(1)$ in $n$. Total time $O(n)$; space $O(1)$ (the table is a fixed 256 slots regardless of file size). The efficient structure is the *array* `freq`, indexed directly by byte value — the same frequency-table idea every entropy coder begins with.
]

#exercise("14.6", 2)[
  A min-heap with these values is built by inserting them one at a time in this order: $7, 3, 9, 1, 5$. Draw (or describe) the heap after all five insertions, and give the result of two successive remove-min operations. State the cost of each operation in Big-O.
]
#solution("14.6")[
  After inserting all five, the minimum, $1$, sits at the root; a valid min-heap is: root $1$, its children $3$ and $9$, and under $3$ the leaves $7$ and $5$ (one valid shape — heaps are not unique, only the parent-≤-children property must hold, and $1$ must be the root). First remove-min returns $1$; the heap re-settles with $3$ at the root (children $5$ and $9$, leaf $7$). Second remove-min returns $3$. Each insertion and each remove-min is $O(log n)$ — here $log_2 5 approx 2.3$, so two or three swaps at most per operation. Finding the minimum (reading the root) is $O(1)$.
]

#exercise("14.7", 3)[
  Prove that no comparison-based sorting algorithm can have a worst-case running time better than $O(n log n)$. (Sketch the decision-tree argument; you may quote that there are $n!$ orderings and that $log_2(n!)$ grows like $n log_2 n$.)
]
#solution("14.7")[
  Model any comparison sort as a binary _decision tree_: each internal node is a comparison "is $x < y$?" with two outcomes (left/right), and each leaf is a final ordering the algorithm can output. To be correct, the tree must have a leaf for _every_ possible ordering of the $n$ inputs, and there are $n!$ such orderings (Chapter 8). A binary tree of height $h$ has at most $2^h$ leaves, so we need $2^h >= n!$, i.e. $h >= log_2(n!)$. The height $h$ is the worst-case number of comparisons (the longest root-to-leaf path). By Stirling's approximation $log_2(n!) approx n log_2 n - 1.44 n$, which grows like $n log_2 n$. Hence the worst-case comparison count is at least about $n log_2 n$, so no comparison sort can be asymptotically faster than $O(n log n)$. $square$
]

#exercise("14.8", 3)[
  The Huffman build loop runs about $n$ rounds, each doing two heap removals and one heap insertion. Show that the total cost is $O(n log n)$. Then argue what the cost would be if a _sorted list_ were used instead of a heap, and by how much that changes the complexity class.
]
#solution("14.8")[
  With a heap, each removal and each insertion is $O(log n)$ (height of the heap). A round does three such operations: $3 times O(log n) = O(log n)$ per round. There are about $n$ rounds, so the total is $n times O(log n) = O(n log n)$. (Building the initial heap with `heapify` is a one-time $O(n)$, which does not change the dominant $O(n log n)$.) With a _sorted list_ instead: removing the two smallest is cheap ($O(1)$ from the front), but _inserting_ the merged node in sorted position requires shifting elements, $O(n)$ per round. Then $n$ rounds $times O(n) = O(n^2)$. So replacing the heap with a sorted list pushes Huffman from $O(n log n)$ up to $O(n^2)$ — a whole complexity class slower, and the practical difference between instant and sluggish on a large alphabet.
]

#exercise("14.9", 3)[
  Compression is described in this chapter as a "time–space–ratio negotiation with no free lunch." Pick two codecs mentioned in the book's outline (e.g. `LZ4` and `cmix`) and describe, qualitatively, where each sits on this trade-off, and why a single "best" compressor cannot exist. Connect your answer to Big-O where you can.
]
#solution("14.9")[
  `LZ4` sits at the "cheap" corner: tiny memory, very fast (close to a single $O(n)$ pass with minimal per-byte work), accepting a modest compression ratio in exchange. `cmix` sits at the opposite "expensive" corner: it mixes many statistical models, using gigabytes of RAM and very high per-symbol computation (a large constant factor on top of its asymptotic cost), to reach record ratios at the price of hours of runtime. No single best compressor can exist because the axes _conflict_: squeezing more redundancy out generally demands a larger model or window (more space) and more work per symbol (more time), so improving ratio costs time and/or space. The right choice depends on the use case — `LZ4` for a real-time network stream where latency rules, `cmix` for an offline archival benchmark where only the final size matters. Big-O captures part of this (a bigger window can turn an $O(n)$ search into something slower), but the _constant factors_ Big-O hides — memory footprint, per-byte work — are exactly where much of this trade-off actually lives, which is why benchmarks (Chapter 36) sit alongside the theory.
]

== Further reading

- *The canonical reference.* Donald E. Knuth, _The Art of Computer Programming_ (Addison-Wesley, ongoing since 1968) — Volumes 1 and 3 cover fundamental structures, sorting, and searching, and are where Big-O analysis of algorithms was made rigorous. Knuth's 1976 note that fixed the $O$/$Omega$/$Theta$ notation: #link("https://dl.acm.org/doi/10.1145/1008328.1008329")["Big Omicron and Big Omega and Big Theta," ACM SIGACT News 8(2)].
- *The standard textbook.* Cormen, Leiserson, Rivest & Stein, _Introduction to Algorithms_ (4th ed., MIT Press, 2022) — the universal "CLRS," with heaps, hash tables, and the comparison-sort lower bound proved in full.
- *The original heap paper.* J. W. J. Williams, "Algorithm 232: Heapsort," _Communications of the ACM_ 7(6), 1964 — where the binary heap was born.
- *Python's own tools.* The standard-library docs for #link("https://docs.python.org/3/library/heapq.html")[`heapq`], #link("https://docs.python.org/3/library/collections.html")[`collections` (`deque`)], and #link("https://docs.python.org/3/whatsnew/3.14.html")["What's New in Python 3.14"] (7 October 2025), which introduced the built-in `compression.zstd` module.
- *History of the word.* For al-Khwārizmī and the origins of "algorithm" and "algebra," see the _MacTutor History of Mathematics_ archive, #link("https://mathshistory.st-andrews.ac.uk/Biographies/Al-Khwarizmi/")[entry on al-Khwārizmī].

#bridge[
  We now have the two spines a working programmer needs: in Chapter 13 we saw how real data becomes _bytes_, and here we built the _algorithms and structures_ that manipulate them — the array, the hash table, the heap, and the language of Big-O to weigh them. What is missing is fluency in the language we will actually _write_ these in. The next three chapters are a Python primer from absolute zero: Chapter 15 covers values, types, and control flow; Chapter 16 the data structures (`list`, `dict`, `set`) and functions we have been previewing; and Chapter 17 the raw bits-and-bytes I/O — the `BitReader` and `BitWriter` — that lets `tinyzip` finally emit real compressed files. After that, Volume I closes by meeting Shannon, and the entropy floor those structures were always built to chase.
]




