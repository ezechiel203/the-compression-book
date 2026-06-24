#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= A Python Primer II: Data Structures, Functions, and Iterators

#epigraph[Bad programmers worry about the code. Good programmers worry about data structures and their relationships.][Linus Torvalds]

At the end of the last chapter we built a frequency histogram for `tinyzip` - the single most important measurement a compressor makes, because short codes belong to common symbols and long codes to rare ones. And it *fought us*. To count how often each character appeared, we kept two lists marching in lock-step: one of the characters we had seen, one of their counts, and an inner loop hunting through the first to find where to bump the second. Twenty lines, two nested loops, and a faint sense that the language was making us do the machine's job by hand.

There was nothing wrong with our logic. There was something wrong with our *container*. We were storing a mapping (from each character to its count) in a structure that has no idea what a mapping is. This chapter hands us the right tools. By its end, that entire twenty-line histogram collapses to a single, transparent line:

```python
from collections import Counter
counts = Counter("banana bandana")
```

and reads as plainly as the English sentence "count the characters." That is the difference a data structure makes, and it is the difference between code that merely works and code you can think in. Linus Torvalds, who has spent decades reading more code than almost anyone alive, put it bluntly in the epigraph: worry about the *data*, and the code follows. This chapter is where `tinyzip` stops being a toy and starts being a tool, because we finally give it the containers, the named functions, and the iterators that every real codec is built from.

#recap[
In *Chapter 15* we learned Python's *control*: the four core value types (`int`, `float`, `str`, `bool`), names bound with `=`, the three operator families, f-strings, and the three moves of control flow (`if`/`elif`/`else` to choose, `while` to repeat-until, `for ... in range(...)` to repeat-over). We wrote three real `tinyzip` scripts with nothing but those, and met their limit: counting by hand in parallel lists. We also keep, from *Chapter 14* (Algorithms, Data Structures, and Complexity), the *ideas* of arrays, hash tables, and the cost of operations (Big-O) taught there in the abstract; this chapter is where those ideas become Python you can run. From *Chapter 13* we keep bytes and ASCII; from *Chapter 9* the notion of a frequency model. No new compression theory is needed here - we are still sharpening the single tool, Python, that every build chapter swings.
]

#objectives((
  [Store many values at once in the four workhorse containers - `list`, `tuple`, `dict`, `set` - and choose the right one for a job,],
  [Reach into sequences with _slicing_ (`s[a:b:c]`), and understand why a slice copies,],
  [Build containers in one readable line with _comprehensions_, and know when to prefer a generator,],
  [Write your own _functions_ with `def`, give them default and keyword arguments, and return values,],
  [Annotate code with _type hints_ like `dict[int, int]` so it documents itself,],
  [Split code into _modules_ and `import` from them, including Python's batteries (`collections.Counter`),],
  [Explain the _iterator_ protocol, write a _generator_ with `yield`, and see why it streams data without hoarding memory,],
  [Branch on the _shape_ of data with the `match` statement,],
  [Refactor `tinyzip`'s histogram into a typed, tested `histogram()` helper and a small reusable utilities module.],
))

== The list: an ordered, changeable shelf

The first and most-used container is the *list*: an ordered collection of values, written inside square brackets with commas between the items. Unlike a string, which can only hold characters, a list can hold *anything* - numbers, strings, Booleans, even other lists - and you may mix types freely.

```python
>>> counts = [2, 6, 4, 1, 1]
>>> counts
[2, 6, 4, 1, 1]
>>> mixed = [255, "byte", True, 3.14]
>>> mixed
[255, 'byte', True, 3.14]
>>> empty = []           # a list with nothing in it yet
>>> empty
[]
```

Think of a list as a numbered shelf. Each slot has a *position* (an index), and exactly as with strings in Chapter 15, the positions start at *zero*. You read a slot with square brackets, and because a list is *changeable* (the proper word is *mutable*), you may also write into a slot, replacing what was there:

```python
>>> counts = [2, 6, 4, 1, 1]
>>> counts[0]            # the FIRST item, at index 0
2
>>> counts[-1]           # negative counts from the end: the last
1
>>> counts[1] = 99       # write into slot 1, replacing the 6
>>> counts
[2, 99, 4, 1, 1]
>>> len(counts)          # how many items? (Chapter 15's len, again)
5
```

That ability to *change a value in place* is the great divide between a list and the values of Chapter 15. You could never alter the number `6` itself; you could only point a name at a different number. A list is different: the shelf stays put, and you rearrange what sits on it. This is enormously useful (a compressor's frequency table, its sliding window, its output buffer are all lists that change as the data streams by), but it carries a famous trap that we will disarm in a moment.

#gopython("Growing and shrinking a list: `append`, `pop`, and methods")[
A list would be useless if it could never change size. Lists *grow* with `append`, which adds one item to the end, and *shrink* with `pop`, which removes and hands back the last item:

```python
>>> stack = []
>>> stack.append(10)     # stack is now [10]
>>> stack.append(20)     # stack is now [10, 20]
>>> stack.append(30)     # stack is now [10, 20, 30]
>>> stack.pop()          # removes and returns the LAST item
30
>>> stack
[10, 20]
```

The dot in `stack.append(10)` introduces a new idea: a *method*. A method is just a function that *belongs to* a value and acts on it - you call it by writing the value, a dot, the method's name, and parentheses. `stack.append(10)` means "tell this particular list to append 10 to itself." Strings have methods too (`"HI".lower()` gives `'hi'`), but lists are where methods earn their keep. A few you will use constantly: `lst.append(x)` adds to the end, `lst.pop()` removes from the end, `lst.insert(i, x)` squeezes `x` in at position `i`, `lst.extend(other)` tacks a whole second list on, and `lst.sort()` puts the items in order. Notice that `append`, `pop`, and `sort` change the list *in place* and (mostly) return `None` - they are commands, not questions. This `append`-to-grow, `pop`-to-shrink pair is exactly the *stack* data structure we met in Chapter 14, and we will lean on it for everything from Huffman tree-building to undo-style backtracking.
]

A `for` loop walks a list as naturally as it walked a string in Chapter 15, handing you each item in turn - which is how `tinyzip` will sweep a buffer of byte values:

```python
counts = [2, 6, 4, 1, 1]
total = 0
for c in counts:        # c takes each value in turn
    total += c
print(total)            # → 14  (the length of "banana bandana")
```

You can also build a list by repeated `append`, the workhorse pattern for turning a stream of values into a collection you can measure and re-scan:

```python
# Collect the byte value of every character in a string.
text = "Hi!"
byte_values = []
for ch in text:
    byte_values.append(ord(ch))   # ord() from Chapter 15
print(byte_values)                # → [72, 105, 33]
```

#pitfall[
A list name is a *label pointing at the shelf*, not a copy of it - exactly the arrow picture from Chapter 15, but now it bites, because the shelf can change. Watch:

```python
>>> a = [1, 2, 3]
>>> b = a              # b points at the SAME list as a
>>> b.append(4)        # change the list through b...
>>> a                  # ...and a sees it too!
[1, 2, 3, 4]
```

Because `b = a` copied the *arrow*, not the shelf, `a` and `b` are two names for *one* list, and a change through either is seen through both. When you genuinely want a separate copy, ask for one: `b = a.copy()` (or `b = a[:]`, a full slice - coming next). This shared-mutable-state surprise is the single most common bug for newcomers, and being forewarned is being forearmed.
]

== Slicing: grabbing a piece of a sequence

Reading one item with `s[i]` is useful; reading a *run* of items at once is essential. *Slicing* extracts a contiguous piece of any sequence - a string or a list - using the colon notation `s[start:stop]`. It returns a new sequence containing the items from `start` up to *but not including* `stop`, the same half-open convention as `range` in Chapter 15.

```python
>>> s = "compression"
>>> s[0:7]              # positions 0,1,2,3,4,5,6 - stop 7 excluded
'compres'
>>> s[3:7]             # from 3 up to (not including) 7
'pres'
>>> nums = [10, 20, 30, 40, 50]
>>> nums[1:4]          # items at positions 1, 2, 3
[20, 30, 40]
```

Both ends are optional, and leaving one out means "to the very end" or "from the very start" - which gives slicing much of its everyday power:

```python
>>> s = "compression"
>>> s[:4]              # from the start up to position 4
'comp'
>>> s[4:]             # from position 4 to the end
'ression'
>>> s[-3:]            # the last three characters
'ion'
>>> s[:]              # a full copy - start and stop both omitted
'compression'
```

That last form, `s[:]`, copies the whole sequence - which is exactly the list-copy cure from the previous pitfall. There is a third, optional number too: the *step*, written `s[start:stop:step]`, mirroring `range`'s third argument. A step of 2 takes every other item; a step of −1 walks *backwards*, which is the cleanest way in all of Python to reverse a sequence:

```python
>>> s = "compression"
>>> s[::2]             # every second character
'cmrsin'
>>> s[::-1]           # step backwards: the whole thing reversed
'noisserpmoc'
>>> nums = [10, 20, 30, 40, 50]
>>> nums[::-1]
[50, 40, 30, 20, 10]
```

Slicing will be everywhere in `tinyzip`. When LZ77 (Chapter 28) finds that the next few bytes already appeared earlier in the data, it copies them with a slice. When a `BitReader` (Chapter 17) needs the next chunk of a buffer, it takes a slice. And `data[i:i+match_len]` ("the `match_len` bytes starting at position `i`") is the single most common idiom in dictionary compression. Learn slicing well and half of LZ-family code stops looking mysterious.

#gomaths("Half-open intervals: why `stop` is excluded")[
Both `range` and slicing share a convention that feels odd until it clicks: the *start* is included, the *stop* is excluded. Mathematicians write this as the *half-open interval* $[a, b)$ - the square bracket includes $a$, the round bracket excludes $b$. It contains every number $x$ with $a <= x < b$.

Why exclude the top? Three small miracles follow. First, the *length* of a slice is simply $"stop" - "start"$ - `s[3:7]` has $7 - 3 = 4$ items, no "+1" to remember. Second, slices *join up cleanly*: `s[0:3]` and `s[3:7]` together cover `s[0:7]` with no gap and no overlap, because the shared boundary `3` belongs to exactly one of them. Third, `s[:k]` and `s[k:]` split any sequence into two pieces at position `k` with nothing lost or duplicated. This is why every well-designed indexing scheme in computing, from array slices to byte ranges in HTTP, uses half-open intervals. Once you feel *why*, the "stop is excluded" rule stops being a gotcha and becomes a convenience.
]

#checkpoint[Given `s = "banana"`, what are `s[1:4]`, `s[:2]`, `s[-2:]`, and `s[::-1]`?][In order: `'ana'` (positions 1,2,3), `'ba'` (start up to position 2), `'na'` (the last two), and `'ananab'` (the whole string reversed by a step of −1).]

== The tuple: a fixed, unchangeable record

A *tuple* is a list's quieter sibling: an ordered collection, written with parentheses (or just commas), that *cannot be changed* after it is made. Once built, you cannot append to it, pop from it, or overwrite a slot. That sounds like a pure loss (why want a list you can't edit?), but the immovability is precisely the point.

```python
>>> point = (3, 4)        # a tuple of two numbers
>>> point[0]              # you read it just like a list
3
>>> point[1]
4
>>> point[0] = 99         # but you may NOT change it
Traceback (most recent call last):
  ...
TypeError: 'tuple' object does not support item assignment
```

Reach for a tuple whenever a clutch of values belongs *together as one thing* and should not drift apart or mutate underfoot: a coordinate `(x, y)`, an RGB colour `(255, 128, 0)`, a date `(2025, 10, 7)`, or an LZ77 match written as `(distance, length)`. The fixedness documents your intent ("these three numbers are one record, not a growable list") and lets Python store the tuple more compactly and, crucially, lets it serve as a *dictionary key*, which a list can never do - a privilege we will cash in shortly.

Tuples enable one of Python's most beloved conveniences, *unpacking*: assigning several names at once by matching them against a tuple's shape.

```python
>>> point = (3, 4)
>>> x, y = point          # unpack: x becomes 3, y becomes 4
>>> x
3
>>> y
4
>>> a, b = b, a           # the famous one-line swap (no temp needed!)
```

That last line swaps two names in a single, readable stroke - Python builds the tuple `(b, a)` on the right, then unpacks it into `a, b` on the left. No scratch variable, no three-step shuffle. Unpacking also makes loops over paired data read beautifully, as we will see the instant we meet dictionaries.

#gopython("Returning several values at once with a tuple")[
A function (which we build properly later in this chapter) can hand back only *one* value - but if that one value is a tuple, you have effectively returned several. This is the idiomatic Python way to return, say, both a quotient and a remainder, or both a match's distance and its length:

```python
>>> def divide(a, b):
...     return a // b, a % b      # returns the tuple (quotient, remainder)
...
>>> q, r = divide(17, 5)          # unpack the returned tuple
>>> q
3
>>> r
2
```

The built-in `divmod(17, 5)` does exactly this, returning `(3, 2)`. Notice how the calling code reads: `q, r = divide(...)` says "this gives me a quotient and a remainder," which is far clearer than fishing items out by index. When `tinyzip`'s match finder returns `(distance, length)`, the caller will write `dist, length = find_matches(...)` and the code will document itself.
]

== The dictionary: the right tool for a frequency table

Here is the container that should have built our histogram all along. A *dictionary* (`dict` for short) stores a collection of *key-value pairs*: it maps each *key* to a *value*, and lets you look up any value instantly by its key. Where a list answers "what is at position 7?", a dictionary answers "what value goes with the key `'a'`?" - and for a frequency table, that is exactly the question. You write one with curly braces, each pair as `key: value`:

```python
>>> counts = {"a": 6, "n": 4, "b": 2}
>>> counts["a"]            # look up the value for key "a"
6
>>> counts["n"]
4
>>> counts["z"]            # a key that isn't there raises an error
Traceback (most recent call last):
  ...
KeyError: 'z'
```

A dictionary is changeable like a list - you can add, overwrite, and remove pairs - but you index it by *key*, not by position. Assigning to a key that does not yet exist *creates* the pair; assigning to one that does *overwrites* it:

```python
>>> counts = {"a": 6, "n": 4}
>>> counts["b"] = 2        # add a brand-new pair
>>> counts["a"] = 7        # overwrite the existing value for "a"
>>> counts
{'a': 7, 'n': 4, 'b': 2}
>>> "n" in counts          # is there a pair with key "n"?
True
>>> len(counts)            # how many pairs?
3
```

This is the natural home for a mapping, and a frequency table *is* a mapping - from each symbol to its count. The clumsy parallel-lists dance of Chapter 15, with its inner loop hunting for "where did I record this character," vanishes entirely, because a dictionary *is* the lookup. Here is the histogram, rebuilt the right way:

```python
# Count each character's frequency - the dict way.
sample = "banana bandana"
counts = {}                       # an empty dictionary
for ch in sample:
    if ch in counts:              # have we seen this character before?
        counts[ch] += 1           # yes: bump its count
    else:
        counts[ch] = 1            # no: start it at 1
print(counts)
# → {'b': 2, 'a': 6, 'n': 4, ' ': 1, 'd': 1}
```

Compare that to the twenty-line, doubly-nested version we suffered through last chapter. Same result, a third the length, and it reads like its own explanation: "for each character, if we've seen it, add one; otherwise start it at one." The dictionary did the bookkeeping that we did by hand before. This is the payoff Torvalds promised in the epigraph: pick the data structure that matches the problem, and the code almost writes itself.

#gopython("Looping over a dictionary: `.items()`, `.keys()`, `.values()`")[
You rarely want only the keys or only the values of a dictionary - you usually want both together. Three methods give you the three views, and `.items()` is the one you will reach for most, because it hands you each *pair* as a tuple you can unpack:

```python
>>> counts = {"a": 6, "n": 4, "b": 2}
>>> for ch, n in counts.items():       # unpack each (key, value) pair
...     print(ch, "appears", n, "times")
a appears 6 times
n appears 4 times
b appears 2 times
>>> list(counts.keys())                # just the keys
['a', 'n', 'b']
>>> list(counts.values())              # just the values
[6, 4, 2]
>>> sum(counts.values())               # total characters: 6+4+2 = 12
12
```

The pattern `for key, value in d.items():` - looping while unpacking each pair - is one of the most common lines in all of Python, and certainly in this book. We will write it to sum a frequency table, to walk a code table mapping symbols to bit-strings, to dump a header. Note also `sum(counts.values())`, which adds up every count to recover the total symbol count - a one-liner we will use to turn counts into probabilities when we compute entropy in Volume II.
]

#gomaths("A dictionary _is_ a function on a finite set")[
Chapter 6 defined a *function* as a rule that assigns to each input exactly one output. A Python dictionary is precisely that, made concrete: its keys are the *domain* (the allowed inputs), and it maps each key to exactly one value (the output). `counts = {"a": 6, "n": 4}` is the function $f$ with $f("a") = 6$ and $f("n") = 4$, and `counts["a"]` is just evaluating $f("a")$. The rule that a function gives *one* output per input is why a key cannot appear twice: assigning `counts["a"] = 7` does not add a second `"a"`, it *replaces* the old output, keeping the mapping single-valued. So every time you build a frequency table, a code table, or a translation table, you are tabulating a finite mathematical function - and the dictionary is the most honest data structure for it.
]

Two properties of dictionaries are worth fixing in your mind because both matter for compression. First, *keys must be unchangeable*: you may use a string, a number, or a tuple as a key, but never a list, because Python needs the key to stay put so it can find the pair again. (This is exactly why the previous section made a fuss about tuples being valid keys: an LZ77 match `(distance, length)` can be a key; a list `[distance, length]` cannot.) Second, since Python 3.7 a dictionary *remembers the order in which you inserted its pairs* - when you loop over it, the pairs come back in insertion order, not random order. That guarantee, now a permanent part of the language, means a frequency table built by scanning a file preserves first-seen order, which makes debugging output predictable and reproducible.

#aside[
Under the hood, a dictionary is a *hash table* - the data structure Chapter 14 introduced - which is why looking up `counts["a"]` is almost instant no matter how many pairs the dictionary holds. Python computes a number (a *hash*) from the key, uses it to jump straight to the right slot, and reads the value, all in roughly constant time: the $O(1)$ of Chapter 14. The clumsy histogram of Chapter 15 was slow precisely because its inner loop searched the parallel list from the start every time - $O(n)$ per character. Swapping the list for a dict did not just shorten the code; it made it asymptotically faster. Good data structures buy speed *and* clarity at once.
]

#gopython("`dict.get`: a lookup with a fallback")[
The `if ch in counts:` / `else:` two-step for "bump it or start it at 1" is so common that dictionaries offer a shortcut. The `get` method looks up a key but, instead of crashing on a missing key, returns a *default* value you supply:

```python
>>> counts = {"a": 6}
>>> counts.get("a", 0)        # "a" is present: return its value
6
>>> counts.get("z", 0)        # "z" is absent: return the default 0
0
```

This collapses the whole if/else into one line, because "the current count, or 0 if we've never seen it" is exactly `counts.get(ch, 0)`:

```python
counts = {}
for ch in sample:
    counts[ch] = counts.get(ch, 0) + 1   # one line, no if/else
```

Read it as "set this character's count to its old count (or zero) plus one." This is the idiomatic Python frequency-counter, and you will see it in real codec source code constantly. We are now *three lines* from the twenty we started the book's previous chapter with - and we are about to reach one.
]

== The set: membership without duplicates

The fourth container is the *set*: an unordered collection of *distinct* values, with no duplicates and no positions. It is the computer's version of the mathematical set from Chapter 6 - a bag where each item appears at most once, and the only questions you ask are "is this in here?" and "what's the combined collection?". You write a set with curly braces like a dictionary, but with bare values instead of key-value pairs:

```python
>>> seen = {3, 1, 4, 1, 5, 9, 2, 6, 5}
>>> seen                      # duplicates silently dropped, order not kept
{1, 2, 3, 4, 5, 6, 9}
>>> 4 in seen                 # fast membership test
True
>>> 7 in seen
False
```

The duplicate `1` and `5` simply vanish - a set keeps one of each. The killer feature is that `in` on a set is *fast*, the same near-instant hash-table lookup as a dictionary key, so a set is the right tool whenever you need to ask "have I seen this before?" over and over. The clumsy `if ch in seen_chars:` of Chapter 15's histogram searched a string from the start every time; a set answers the same question in roughly constant time.

```python
>>> letters = set("mississippi")    # build a set from a string
>>> letters
{'m', 'i', 's', 'p'}
>>> len(letters)                    # how many DISTINCT characters?
4
```

That `len(set(text))` idiom - the number of distinct symbols in some data - is genuinely useful in compression: it is the size of the *alphabet*, and the alphabet size sets a floor on how many bits a fixed-length code must spend per symbol. Eleven characters in `"mississippi"`, but only four distinct ones, so two bits per symbol suffice for a naive code. Sets also do the union, intersection, and difference of Chapter 6 directly, with operators that mirror the maths:

```python
>>> a = {1, 2, 3}
>>> b = {3, 4, 5}
>>> a | b              # union: everything in either
{1, 2, 3, 4, 5}
>>> a & b              # intersection: only what's in both
{3}
>>> a - b              # difference: in a but not b
{1, 2}
```

Use a set when you care *only* about membership and uniqueness, a dictionary when you need to attach a *value* to each item, a list when order and duplicates matter, and a tuple when the collection is fixed. That four-way choice (`list`, `tuple`, `dict`, `set`) covers nearly every container decision you will make, and making it well is most of what "thinking in data structures" means.

#fig([The four core containers at a glance: ordered vs unordered, changeable vs fixed, and whether they carry values per key.], cetz.canvas({
  import cetz.draw: *
  let cell(x, y, title, sub, col) = {
    rect((x, y), (x+3.6, y+1.5), fill: col, stroke: 0.6pt + rgb("#0b5394"))
    content((x+1.8, y+1.05), box(width: 3.2cm, inset: 2pt, align(center, text(size: 9pt, weight: "bold")[#title])))
    content((x+1.8, y+0.45), box(width: 3.2cm, inset: 2pt, align(center, text(size: 7.6pt)[#sub])))
  }
  cell(0,   2, [list  `[ ]`],  [ordered · changeable · duplicates], rgb("#eef4fb"))
  cell(4,   2, [tuple `( )`],  [ordered · fixed · duplicates],      rgb("#fbf7ef"))
  cell(0,   0, [dict  `{k:v}`],[keyed · changeable · unique keys],  rgb("#eef9f3"))
  cell(4,   0, [set   `{ }`],  [unordered · changeable · unique],   rgb("#f3eefb"))
}))

#checkpoint[You need to record, for each distinct byte value 0–255, how many times it appears in a file. Which container, and why?][A *dictionary* (or equivalently a 256-slot list), mapping each byte value (the key) to its count (the value). A set would tell you *which* bytes appeared but not how often; a plain list with no keys would force you back to the parallel-list bookkeeping we are trying to escape. The mapping nature of the problem - symbol to count - calls for a `dict`.]

== Ordering data: `sorted`, keys, and a first taste of `lambda`

A frequency table tells you *which* symbols are common, but a Huffman coder (Chapter 24) wants them *in order* - rarest first, or most-common first - so it can build short codes for the frequent ones. Ordering is a need that recurs throughout compression, and Python serves it two ways. The list method `lst.sort()` reorders a list *in place*, changing it; the built-in `sorted(iterable)` leaves its input untouched and *returns a new sorted list*. The second is usually what you want, because it does not mutate data out from under you, and because it accepts *any* iterable - a set, a dict's keys, a generator - not just a list.

```python
>>> sorted([4, 1, 9, 2])          # returns a NEW sorted list
[1, 2, 4, 9]
>>> sorted("mississippi")         # sorts the characters
['i', 'i', 'i', 'i', 'm', 'p', 'p', 's', 's', 's', 's']
>>> sorted([4, 1, 9, 2], reverse=True)   # largest first
[9, 4, 2, 1]
```

By default Python sorts numbers from small to large and strings alphabetically. But the interesting question in compression is rarely "sort these values" - it is "sort these *records* by *one field* of each." Given a list of `(symbol, count)` pairs, we want them ordered *by count*, not by symbol. That is what the `key` argument does: you hand `sorted` a small function that, given one item, returns the value to *sort by*, and `sorted` orders the items by those returned values.

```python
>>> pairs = [("a", 6), ("n", 4), ("b", 2), ("d", 1)]
>>> sorted(pairs, key=second_field)        # order by the count
[("d", 1), ("b", 2), ("n", 4), ("a", 6)]
```

where `second_field` is a function returning the count of a pair. Writing a named function for so trivial a job is heavy, though, so Python offers a featherweight way to write a one-expression function on the spot: the `lambda`.

#gopython("`lambda`: a tiny throwaway function")[
A `lambda` is an *anonymous* function - one with no name - written in a single expression, perfect for the small "given an item, return the field to sort by" jobs that `sorted`, `min`, and `max` ask for. The form is `lambda parameters: expression`; its value is a function you can call or pass along:

```python
>>> by_count = lambda pair: pair[1]   # given a pair, return its 2nd item
>>> by_count(("a", 6))
6
>>> pairs = [("a", 6), ("n", 4), ("b", 2)]
>>> sorted(pairs, key=lambda pair: pair[1])          # by count, ascending
[("b", 2), ("n", 4), ("a", 6)]
>>> sorted(pairs, key=lambda pair: pair[1], reverse=True)   # most common first
[("a", 6), ("n", 4), ("b", 2)]
```

Read `lambda pair: pair[1]` as "a function that takes a `pair` and gives back `pair[1]`, its count." It is exactly `def f(pair): return pair[1]` with the ceremony stripped away. Use a `lambda` only for these tiny one-liners; the moment the logic needs more than one expression or a docstring, write a proper `def`. We will pass `key=lambda ...` to `sorted` whenever `tinyzip` needs symbols ordered by frequency - which is the very first thing Huffman's algorithm does.
]

Two more built-ins ride on the same `key` idea and are worth meeting now, because they answer questions a codec asks constantly. `min` and `max` find the smallest and largest item, and with a `key` they find the smallest/largest *by a chosen field* - for instance, the rarest or most common symbol in a frequency table:

```python
>>> counts = {"a": 6, "n": 4, "b": 2, "d": 1}
>>> max(counts, key=lambda ch: counts[ch])     # the MOST common symbol
'a'
>>> min(counts, key=lambda ch: counts[ch])     # the RAREST symbol
'd'
>>> sorted(counts, key=lambda ch: counts[ch])  # all symbols, rarest first
['d', 'b', 'n', 'a']
```

Looping `max(counts, key=...)` gives the most frequent symbol - the "track the best so far" pattern of Chapter 15, now a single built-in call. And `sorted(counts, key=lambda ch: counts[ch])` returns every symbol ordered from rarest to most common, which is precisely the queue Huffman coding consumes. The standard library's `Counter.most_common()` we met earlier is, under the hood, doing exactly this sort. Ordering, like counting, turns out to be a one-liner once you have the right tool.

#gomaths("Sorting and the cost of comparison: $O(n log n)$")[
Chapter 14 measured an algorithm's cost with Big-O, and sorting is the textbook example worth recalling. To sort $n$ items by comparing pairs of them, the best general algorithms - the kind `sorted` uses - take on the order of $n log_2 n$ comparisons, written $O(n log n)$. Why the logarithm? A good sort repeatedly *splits* the work in half (merge sort) or partitions it (quicksort), and Chapter 7 taught that the number of times you can halve $n$ before reaching 1 is $log_2 n$. With $n$ items each touched across about $log_2 n$ levels of splitting, the total is roughly $n log_2 n$. For a 1000-symbol alphabet that is about $1000 times 10 = 10","000$ comparisons - fast. The lesson for `tinyzip`: sorting a frequency table is cheap, so we sort freely; but sorting the *whole file* every time we search for a match would be ruinously slow, which is exactly why Chapter 28's match finders use hash tables, not repeated sorts.
]

#checkpoint[You have `pairs = [("x", 3), ("y", 1), ("z", 3)]`. What does `sorted(pairs, key=lambda p: p[1])` return, and what breaks the tie between `"x"` and `"z"`?][It returns `[("y", 1), ("x", 3), ("z", 3)]`. The `key` orders by the second field (the count), so `"y"` with count 1 comes first. The two count-3 pairs tie on the key, and Python's sort is *stable* - it keeps tied items in their original order - so `"x"` stays before `"z"` because it appeared first in the input.]

== Comprehensions: building a container in one line

A pattern recurs so often that Python gives it dedicated syntax: *start with an empty list, loop over something, append a transformed item each time.* You have already written it by hand. Here it is the long way, squaring the numbers 0 to 4:

```python
squares = []
for n in range(5):
    squares.append(n * n)
# squares is [0, 1, 4, 9, 16]
```

A *list comprehension* compresses those four lines into one, by writing the expression *first* and the loop *after* it, all inside the square brackets:

```python
>>> squares = [n * n for n in range(5)]
>>> squares
[0, 1, 4, 9, 16]
```

Read it left to right as a sentence: "the value `n * n`, for each `n` in `range(5)`." The part before `for` is what each item *becomes*; the `for` clause says what we loop over. It is not merely shorter - once your eye is trained, it is *clearer*, because the whole intent ("a list of squares") sits on one line instead of being scattered across an accumulator, a loop, and an append. This idiom turns one sequence into another, which is most of what data-shuffling code does:

```python
>>> text = "Hi!"
>>> [ord(ch) for ch in text]          # every character's byte value
[72, 105, 33]
>>> nums = [10, 25, 30, 45]
>>> [n // 2 for n in nums]            # halve each number
[5, 12, 15, 22]
```

You may also *filter*, by adding an `if` clause at the end - it keeps only the items for which the condition is true:

```python
>>> [n for n in range(20) if n % 2 == 0]      # only the evens
[0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
>>> data = "a1b2c3"
>>> [ch for ch in data if ch.isdigit()]       # keep only the digits
['1', '2', '3']
```

Read this as "the value `n`, for each `n` in the range, *if* `n` is even." Transform on the left, filter on the right - that two-part shape handles a startling fraction of everyday list-building. In `tinyzip` we will write `[count for count in counts.values() if count > 0]` to drop never-seen symbols before computing entropy, and `[length for (dist, length) in matches]` to pull just the match lengths out of a list of `(distance, length)` tuples.

#gopython("Dict and set comprehensions")[
The same one-line magic builds dictionaries and sets, not just lists. A *dict comprehension* uses `key: value` before the `for`; a *set comprehension* uses bare values in curly braces:

```python
>>> {n: n * n for n in range(4)}          # dict: each n maps to n squared
{0: 0, 1: 1, 2: 4, 3: 9}
>>> {ch for ch in "mississippi"}          # set: the distinct characters
{'m', 'i', 's', 'p'}
```

The first is genuinely handy for building lookup tables - for instance, a code table `{symbol: codeword for ...}` in one readable line. The second is just `set("mississippi")` written the long way, but the comprehension form lets you *filter* and *transform* while you deduplicate: `{ch.lower() for ch in text if ch.isalpha()}` gives the distinct letters, lower-cased, ignoring punctuation. Whenever you catch yourself writing "empty container, loop, add transformed item," a comprehension is almost always the cleaner choice.
]

#pitfall[
Comprehensions are for *building a container*, not for *doing things*. If the loop body's job is a side effect - printing, writing to a file, mutating something - write an ordinary `for` loop; do not abuse a comprehension to run side effects, because `[print(x) for x in items]` builds a pointless throwaway list of `None`s and obscures your intent. The rule of thumb: a comprehension should *produce a value you keep*. If you are not keeping the result, you want a plain loop.
]

== Functions: naming a piece of work

We have *called* functions since Chapter 15 (`print`, `len`, `ord`, and the methods `.append`, `.get`). Now we learn to *write* our own. A function is a named, reusable piece of work: you define it once, then call it as often as you like. This is the single most important tool for keeping code readable as it grows, because it lets you give a *name* to a computation and then forget how it works - exactly as you use `len` without knowing how it counts.

You define a function with the keyword `def`, a name, a parenthesised list of *parameters* (the inputs it expects), and a colon, followed by an indented *body* - the same colon-and-indentation grammar as `if` and `for`. The body may `return` a value back to the caller:

```python
def double(x):
    return x * 2

print(double(21))        # → 42
print(double(double(3))) # → 12  (double of double of 3)
```

When you call `double(21)`, Python binds the parameter `x` to the argument `21`, runs the body, and the `return` hands `42` back to wherever the call appeared. A function with no `return` (or a bare `return`) hands back the special value `None`, Python's "nothing here" - which is why `print(...)`, whose job is the side effect of showing text, returns `None`. The distinction matters: a function that *computes and returns* a value can be used inside a larger expression; a function that only *acts* cannot.

Here is a function that does real work - counting the bytes below a threshold, the kind of small query a codec asks constantly:

```python
def count_small(values, limit):
    """Return how many of the values are below limit."""
    total = 0
    for v in values:
        if v < limit:
            total += 1
    return total

data = [200, 5, 130, 9, 255, 1]
print(count_small(data, 100))     # → 3  (the values 5, 9, 1)
```

Three things to notice. The function takes *two* parameters, `values` and `limit`, supplied as positional arguments in order at the call. The triple-quoted string just under the `def` line is a *docstring* - a special comment, by convention the function's one-line description, that Python stores and tools can display. And the work is now *named*: anywhere we need this count, we write `count_small(...)` instead of re-typing the loop, and a reader sees the *intent* without the mechanics. As programs grow, this is what keeps them comprehensible - and `tinyzip` will be a few dozen such small, named functions wired together.

#gopython("Default arguments: making a parameter optional")[
A parameter may carry a *default value*, given with `=` in the `def` line. If the caller omits that argument, the default is used; if they supply it, theirs wins. This lets one function serve both the common case and the special case:

```python
def repeat(text, times=2):        # times defaults to 2
    return text * times

>>> repeat("ab")                  # uses the default: times = 2
'abab'
>>> repeat("ab", 5)               # overrides it: times = 5
'ababababab'
```

Defaults are how the standard library offers sensible behaviour out of the box while still letting you tune it - recall `print`'s `sep` and `end` from Chapter 15, which are exactly default arguments. There is one famous trap: *never use a mutable value like a list or dict as a default* (`def f(items=[]):`), because that single list is created once and *shared* across every call, accumulating surprises. The safe idiom is `def f(items=None):` and then `if items is None: items = []` inside. We will follow that rule whenever a function needs an optional collection.
]

#gopython("Keyword arguments and call clarity")[
When you call a function, you may pass arguments *by name* rather than by position, writing `name=value` - these are *keyword arguments*, the same mechanism as `print(sep="-")` in Chapter 15. Named arguments can come in any order and, more importantly, make a call self-documenting:

```python
def make_match(distance, length):
    return (distance, length)

>>> make_match(12, 4)                       # positional: which is which?
(12, 4)
>>> make_match(length=4, distance=12)       # keyword: unmistakable
(12, 4)
```

Compare the two calls. `make_match(12, 4)` forces the reader to remember the parameter order; `make_match(distance=12, length=4)` says exactly what each number means. When a function takes several numbers that are easy to transpose - and an LZ77 match's distance and length are *exactly* that kind of confusable pair - passing them by keyword is a small kindness to whoever reads the code next, usually you. We will favour keyword arguments at call sites in `tinyzip` wherever the meaning of a bare number would otherwise be a guess.
]

== Type hints: code that documents itself

Python never *forces* you to say what type a value is - `double(x)` happily doubles a number, a string, or a list. But you may *optionally annotate* what types you intend, and doing so turns your code into its own documentation and lets tools catch mistakes before you run them. These annotations are *type hints*, and the modern Python world - including every compression-and-ML library you will meet later - uses them pervasively.

A hint goes after a parameter name with a colon, and the return type after an arrow `->`:

```python
def count_small(values: list[int], limit: int) -> int:
    """Return how many of the values are below limit."""
    total = 0
    for v in values:
        if v < limit:
            total += 1
    return total
```

Read the signature as a sentence: "`count_small` takes a `values` which is a *list of ints* and a `limit` which is an *int*, and returns an *int*." The notation `list[int]` means "a list whose items are integers"; the square brackets say what is *inside* the container. This is the self-describing style the book promised, and it is why the chapter's title singles out hints like `dict[int, int]`.

#gopython("Reading container type hints: `list[int]`, `dict[int, int]`, and friends")[
Container hints spell out both the container and its contents, using square brackets:

- `list[int]` - a list of integers (e.g. a list of byte values).
- `list[str]` - a list of strings.
- `dict[int, int]` - a dictionary whose *keys* are ints and whose *values* are ints. For a frequency table mapping each byte value to its count, this is the exact type: `dict[int, int]`.
- `dict[str, int]` - keys are strings, values are ints (a character-to-count table).
- `tuple[int, int]` - a tuple of exactly two ints, like an LZ77 `(distance, length)` match.
- `list[tuple[int, int]]` - a list of such pairs: a whole list of matches.

```python
def histogram(data: bytes) -> dict[int, int]:
    """Map each byte value to how many times it occurs."""
    counts: dict[int, int] = {}
    for b in data:
        counts[b] = counts.get(b, 0) + 1
    return counts
```

That signature tells the whole story before you read a line of the body: feed it `bytes` (the raw file content we meet in Chapter 17), get back a `dict[int, int]` from byte value to count. You can even annotate a *variable*, as in `counts: dict[int, int] = {}`, to pin down what an initially-empty container is meant to hold. These hints are exactly the type names we will write throughout `tinyzip`, so that each function announces its contract.
]

#note[
Type hints are *not checked when the program runs* - Python ignores them at run time, so a wrong hint will not crash anything. Their value is twofold: they document intent for human readers, and they let a separate *type checker* (a tool such as `mypy` or `pyright`, which you run like a spell-checker over your code) flag mismatches (passing a `str` where a `list[int]` was promised) *before* you ever run the program. In Python 3.12 and after, the language even gained clean syntax for generic functions and type aliases (PEP 695), so modern annotations read more naturally than the older style. For this book, treat hints as precise comments that happen to be machine-readable: they cost a few characters and repay them every time someone (you, next month) reads the function.
]

#gomaths("Domain and codomain, in a function signature")[
Chapter 6 gave every function a *domain* (the set of allowed inputs) and a *codomain* (the set the outputs live in). A type hint is a programmer's shorthand for exactly those. `def histogram(data: bytes) -> dict[int, int]` declares the domain to be "byte strings" and the codomain to be "integer-to-integer dictionaries." Reading a signature this way - input type to output type - is the same reading you give a mathematical function $f: A -> B$, and it is why a well-typed function is so easy to reason about: you know the *shape* of what goes in and what comes out before you study how. When we later write `entropy(counts: dict[int, int]) -> float`, the signature alone tells you it turns a frequency table into a single number of bits - the domain-to-codomain story of Chapter 6, made executable.
]

== Modules: splitting code and borrowing batteries

A program of any size does not live in one file. Python organises code into *modules* - a module is simply a `.py` file full of functions and values - and the `import` statement lets one file *borrow* the contents of another. This is how you split `tinyzip` into tidy pieces (a `utils.py`, a `huffman.py`, a `bitio.py`) and, just as importantly, how you reach Python's enormous *standard library*: the hundreds of ready-made modules that ship with the language, its famous "batteries included."

There are two import styles. `import module` brings in the whole module, and you reach its contents through a dot; `from module import name` pulls one specific name straight into your file:

```python
>>> import math                  # bring in the math module
>>> math.log2(256)               # reach log2 through the dot
8.0
>>> from math import log2        # pull just log2 into our file
>>> log2(1024)                   # now call it directly
10.0
```

`math.log2` is the base-2 logarithm of Chapter 7 ("how many bits"), and it ships free with Python, ready for the entropy formula $H = -sum p_i log_2 p_i$ we will code in Volume II. That is the standard library's promise: the dull-but-essential machinery is already written, tested, and waiting. You will lean on `math` for logarithms, on `collections` for ready-made counters, on `heapq` for the priority queue that Huffman coding needs (Chapter 24), and on `pathlib` and `struct` for files (Chapter 17). Knowing what is already in the box saves you from rebuilding it.

#gopython("`from collections import Counter`: a frequency table for free")[
The single most useful "battery" for this chapter lives in the `collections` module. `Counter` is a dictionary purpose-built for counting: hand it any sequence and it returns a `dict` mapping each item to how many times it appeared - the entire histogram, in one call.

```python
>>> from collections import Counter
>>> Counter("banana bandana")
Counter({'a': 6, 'n': 4, 'b': 2, ' ': 1, 'd': 1})
>>> counts = Counter("mississippi")
>>> counts["s"]                       # use it exactly like a dict
4
>>> counts.most_common(2)             # the two most frequent items
[('i', 4), ('s', 4)]
```

A `Counter` *is* a `dict` - every dictionary method works on it - with extras tailored to frequency work. `most_common(n)` returns the `n` highest-count items as `(item, count)` tuples, already sorted, which is precisely the order a Huffman coder wants. And a missing key returns `0` instead of raising `KeyError`, so you never need the `get(..., 0)` dance. The twenty-line histogram of Chapter 15, then the three-line dict version of this chapter, has reached its final form: one line, `Counter(data)`. This is what "batteries included" buys you - but we *taught the dict first*, because you must understand what `Counter` is doing to trust it, and because one day you will need a counting structure that does something `Counter` does not.
]

#aside[
You can write your own modules just as easily. Put functions in a file `utils.py`, and any other script in the same folder can `from utils import histogram`. When Python imports a module it *runs* the file once, top to bottom, and remembers the result, so a common idiom guards code that should only run when the file is launched directly, not when it is imported: `if __name__ == "__main__":`. That slightly cryptic line means "only do this if I am the program being run, not a module someone imported." We will use it to let `tinyzip`'s files double as both importable libraries *and* runnable scripts - import the functions from elsewhere, or run the file to see a demo.
]

#project("Step 2 · `utils.histogram(data: bytes)` and a typed `utils.py`")[
In Step 1 (Chapter 15) we created the `tinyzip/` package skeleton and a `cli.py` that reads a file into `bytes`. Step 2 gives that toolkit its first real measurement - the canonical histogram. A real compressor counts raw *bytes*, the 0-to-255 values of Chapter 13, not characters, so the spec fixes the signature as `histogram(data: bytes) -> dict[int, int]`: feed it the bytes of a file, get back a dictionary from each byte *value* to how many times it occurs. (We meet `bytes` properly in Chapter 17; for now, know only that iterating over `bytes` hands you integers 0–255, and that `"banana bandana".encode()` turns a string into its bytes.) Create `tinyzip/utils.py` to hold the small functions every later stage will share:

```python
# tinyzip/utils.py - shared helpers for the tinyzip project.
from collections import Counter

def histogram(data: bytes) -> dict[int, int]:
    """Map each byte value (0–255) in data to how many times it occurs.

    Returns a dict from byte value to count, in first-seen order.
    """
    counts: dict[int, int] = {}
    for b in data:                       # iterating bytes yields ints 0–255
        counts[b] = counts.get(b, 0) + 1
    return counts

def alphabet_size(counts: dict[int, int]) -> int:
    """How many DISTINCT byte values appear (the alphabet size)."""
    return len(counts)

def total_symbols(counts: dict[int, int]) -> int:
    """Sum of all counts - the total number of symbols."""
    return sum(counts.values())

if __name__ == "__main__":
    data = "banana bandana".encode()      # the sample, as raw bytes
    counts = histogram(data)
    print(f"Histogram  : {counts}")
    print(f"Alphabet   : {alphabet_size(counts)} distinct symbols")
    print(f"Total       : {total_symbols(counts)} symbols")
    # Cross-check against the standard library's Counter:
    assert counts == dict(Counter(data)), "histogram disagrees with Counter!"
    print("Self-check  : histogram() matches collections.Counter ✓")
```

Run it with `python tinyzip/utils.py`:

```
Histogram  : {98: 2, 97: 6, 110: 4, 32: 1, 100: 1}
Alphabet   : 5 distinct symbols
Total       : 14 symbols
Self-check  : histogram() matches collections.Counter ✓
```

The keys are now byte *values* (`97` is the byte for `'a'`, `98` for `'b'`, `110` for `'n'`, `32` for the space, `100` for `'d'` - the ASCII codes of Chapter 13), but the counts are exactly the same as our character histogram: six `a`s, four `n`s, two `b`s, and a lone space and `d`. We have simply moved from "count characters" to "count bytes," which is what a file-level compressor actually sees.

Several firsts here earn their place. Every function is *typed* (`-> dict[int, int]`, `-> int`), so it announces its contract - and the signature matches the canonical `tinyzip` spec exactly, so Chapter 17's byte-level code and Chapter 24's Huffman coder can both `from tinyzip.utils import histogram` and get precisely the function they expect. The `if __name__ == "__main__":` guard lets this file be both an importable library and a runnable demo. And the `assert` line is our first *test*: it checks our hand-written `histogram` against the trusted `Counter`, and the program *stops with an error* if they ever disagree - a tiny but real safety net of the kind every serious codec needs. (We wrote our own `histogram` rather than just using `Counter` so that the toolkit has no surprises in it and so you understand every line; the `assert` proves the two agree.) `tinyzip` now has a tested, typed utilities module, the spine that the rest of the build chapters hang functions on.
]

== Iterators and generators: streaming without hoarding

We have looped over strings, lists, ranges, and dictionaries with `for`, and never asked *how* `for` knows what comes next. The answer is the *iterator protocol*, and understanding it unlocks one of Python's most important tools for compression: the ability to process a gigantic file *one piece at a time*, without ever holding the whole thing in memory.

An *iterable* is anything you can loop over - a string, list, dict, set, range, or file. When a `for` loop starts, it asks the iterable for an *iterator*: a little object whose one job is to produce the next item each time it is asked, and to signal when it is exhausted. You almost never touch this machinery directly, but seeing it once demystifies every loop you will ever write:

```python
>>> it = iter([10, 20, 30])     # get an iterator from a list
>>> next(it)                    # ask for the next item
10
>>> next(it)
20
>>> next(it)
30
>>> next(it)                    # nothing left
Traceback (most recent call last):
  ...
StopIteration
```

`iter` makes an iterator; `next` pulls one item; `StopIteration` is the polite signal "I'm out." A `for` loop is exactly this dance, wrapped up: it calls `iter` once, then `next` repeatedly, and stops cleanly when `StopIteration` arrives. That is the whole secret. The reason it matters is *laziness*: an iterator produces items *on demand*, one at a time, so it need not have them all sitting in memory at once. We already met one lazy producer (`range(10 ** 12)` in Chapter 15, which loops a trillion times without ever building a trillion numbers). Iterators generalise that thrift to *any* sequence you can describe.

#gopython("Writing a generator with `yield`")[
The easiest way to make your own lazy producer is a *generator*: a function that uses `yield` instead of `return`. Where `return` hands back one value and ends the function, `yield` hands back a value and *pauses* the function, ready to resume from exactly where it left off the next time an item is asked for. The function becomes a stream:

```python
def first_n_squares(n: int):
    """Yield 0, 1, 4, 9, ... one at a time, never building a list."""
    for i in range(n):
        yield i * i           # hand back one value, then pause

>>> for sq in first_n_squares(5):
...     print(sq, end=" ")
0 1 4 9 16
>>> list(first_n_squares(4))      # force it to a list if you want all
[0, 1, 4, 9]
```

Calling `first_n_squares(5)` does *not* run the loop; it hands back a generator, paused at the top. Each turn of the `for` loop resumes it just far enough to produce one square, then pauses again. No list of squares is ever stored - only the single value currently in flight. For five squares the saving is nothing; for the bytes of a multi-gigabyte file it is the difference between a program that runs and one that exhausts your memory. This is why `tinyzip`'s real codecs will *stream*: read a chunk, compress it, emit it, and let it go, holding only a small window of data at a time.
]

Generators are the Pythonic way to express a *pipeline*, which is exactly what a compressor is: bytes flow in, pass through a model, then an encoder, and compressed bytes flow out, each stage pulling from the one before it on demand. Here is a tiny taste - a generator that yields the runs of a string, the streaming heart of the run-length idea from Chapter 15:

```python
def runs(data: str):
    """Yield (character, run_length) pairs for each run in data."""
    i = 0
    while i < len(data):
        ch = data[i]
        length = 1
        while i + length < len(data) and data[i + length] == ch:
            length += 1
        yield (ch, length)        # stream one run, then pause
        i += length

>>> for ch, n in runs("aaabbbc"):
...     print(f"{ch}×{n}", end="  ")
a×3  b×3  c×1
```

The caller consumes runs one at a time, unpacking each `(char, length)` tuple in the `for` header - and the generator never builds a list of all runs, so it would handle a file far too large to hold in memory. The same shape, refined, is how a real RLE or LZ encoder feeds tokens to the entropy stage without buffering the entire input. We will build exactly such pipelines from Chapter 24 onward.

#gomaths("A generator as a lazy sequence")[
Chapter 11 introduced a *sequence* as an ordered, possibly endless list of terms $a_0, a_1, a_2, dots$ defined by a rule. A generator is that idea made executable: `first_n_squares` is the rule $a_i = i^2$, and `yield` produces the terms one at a time *only when asked*. The crucial new power over a list is that a generator can be *infinite*, because it never has to finish:

```python
def naturals():
    n = 0
    while True:            # never stops on its own
        yield n
        n += 1             # the rule a_{n+1} = a_n + 1
```

You could never build the infinite list of natural numbers, but you can describe its *rule* with a generator and pull as many terms as you need (`next(gen)` for one, or a `for` loop with a `break` to take the first hundred). This is the computational face of an infinite sequence: not all the terms stored, but a rule that yields each on demand. Lazy evaluation is how programs cope with data that is, in principle, unbounded - a stream from a network, a sensor, or a file longer than memory.
]

== The `match` statement: branching on shape

Our last new piece of grammar is the *match statement*, added in Python 3.10. At its simplest it is a tidy alternative to a long `if`/`elif`/`else` ladder: you give it a value, list several *patterns*, and it runs the branch for the first pattern the value fits. But it does far more than a switch - it can look *inside* a value and pull pieces out, which is why it shines for the tagged, structured tokens a codec passes around.

The simplest form matches against literal values, with `case _` as the catch-all "anything else" (the underscore is Python's "I don't care about this" placeholder):

```python
def describe(byte: int) -> str:
    match byte:
        case 0:
            return "null"
        case 10:
            return "newline"
        case 32:
            return "space"
        case _:                    # the wildcard: anything not matched above
            return "other"

>>> describe(10)
'newline'
>>> describe(200)
'other'
```

That alone is just a neater `if`/`elif`. The real power appears when you match the *shape* of a tuple and bind names to its parts in one move - *structural pattern matching*. A compressor's intermediate stream is full of tagged tokens: "a literal byte," "a back-reference of some distance and length," "end of block." Matching on their shape reads like a specification:

```python
def render(token: tuple) -> str:
    match token:
        case ("literal", value):                 # a 2-tuple tagged "literal"
            return f"emit byte {value}"
        case ("match", distance, length):        # a 3-tuple tagged "match"
            return f"copy {length} bytes from {distance} back"
        case ("end",):                           # a 1-tuple tagged "end"
            return "end of block"
        case _:
            return "unknown token"

>>> render(("literal", 65))
'emit byte 65'
>>> render(("match", 12, 4))
'copy 4 bytes from 12 back'
>>> render(("end",))
'end of block'
```

Look at what each `case` did: it checked the token's *tag* and its *length*, and in the same breath unpacked its fields into named variables you use on the right. `case ("match", distance, length):` means "if this is a three-part tuple whose first piece is the text `"match"`, bind the other two to `distance` and `length`." This is precisely how the decoder for almost any LZ-family codec dispatches on its token stream, and we will write code shaped exactly like this when `tinyzip` grows a real LZ77 stage in Chapter 28. The `match` statement turns "inspect the tag, check the arity, pull out the fields, then act" - four fiddly steps - into one readable block.

#gopython("`match` patterns: literals, captures, and the wildcard")[
Three pattern kinds cover most needs:

- A *literal* pattern matches an exact value: `case 0:`, `case "literal":`. The value must equal the literal.
- A *capture* pattern is a bare name: `case value:` matches anything and *binds* it to `value`. Inside a sequence pattern, `case ("literal", value):` matches a two-tuple and captures its second element.
- The *wildcard* `_` matches anything *without* binding - `case _:` is the catch-all final branch, the `match` equivalent of `else`.

```python
match point:
    case (0, 0):              # literal pattern: exactly the origin
        kind = "origin"
    case (0, y):              # capture: x is 0, bind y to the rest
        kind = f"on the y-axis at {y}"
    case (x, y):              # capture both coordinates
        kind = f"general point ({x}, {y})"
    case _:
        kind = "not a point"
```

Patterns are tried top to bottom, first match wins - so order them specific-to-general, exactly as you would an `if`/`elif` chain. A subtle rule worth knowing: a bare name in a pattern *always captures*, it never compares against an existing variable, so `case literal:` does not check "equals the variable `literal`," it captures into a new name `literal`. To match against a constant you must use a literal or a dotted name. For our tagged tokens this never bites, because the tags are string literals like `"match"`.
]

#misconception[Python's `match` is just a `switch` statement like other languages have.][A C-style `switch` only compares a value against constants. Python's `match` does *structural* matching: it can check the *shape* of a value - is this a 3-tuple? a 2-tuple tagged "literal"? - and simultaneously *destructure* it, binding the inner pieces to names. That makes it a tool for dispatching on richly structured data, like a codec's token stream, not merely a tidy multi-way branch. The switch-like use is the least of what it does.]

#tryit[
*A streaming RLE encoder, decoder, and round-trip test.* Let us combine generators, tuples, type hints, and `match` into a true *codec pair* - an encoder and a decoder that are exact inverses, with a test proving it. This is illustrative rather than a numbered `tinyzip` step (run-length coding is not one of the project's canonical modules), but it has the *exact shape* every real codec in this book will take, so it is worth building in full. Save it as a scratch file `rle_demo.py`. Where Chapter 15's RLE toy built a string, this version *streams tagged tokens*, the shape every real codec uses.

```python
# tinyzip/rle.py - a streaming run-length codec with a round-trip test.

def rle_encode(data: str):
    """Yield ("run", char, length) tokens for each run in data."""
    i = 0
    while i < len(data):
        ch = data[i]
        length = 1
        while i + length < len(data) and data[i + length] == ch:
            length += 1
        yield ("run", ch, length)      # a tagged token, ready for match
        i += length

def rle_decode(tokens) -> str:
    """Rebuild the original string from a stream of run tokens."""
    out: list[str] = []
    for token in tokens:
        match token:
            case ("run", ch, length):  # unpack the tagged token
                out.append(ch * length)
            case _:
                raise ValueError(f"unknown token: {token}")
    return "".join(out)                # join the pieces into one string

if __name__ == "__main__":
    sample = "aaabbbbbcaaaa"
    tokens = list(rle_encode(sample))           # force the generator to a list
    print(f"Tokens : {tokens}")
    restored = rle_decode(tokens)
    print(f"Restored: {restored!r}")
    assert restored == sample, "round-trip FAILED - codec is not lossless!"
    print("Round-trip: encode then decode reproduces the input exactly ✓")
```

Running `python tinyzip/rle.py` prints:

```
Tokens : [('run', 'a', 3), ('run', 'b', 5), ('run', 'c', 1), ('run', 'a', 4)]
Restored: 'aaabbbbbcaaaa'
Round-trip: encode then decode reproduces the input exactly ✓
```

This small program is a milestone, because it has the *exact shape* of every codec in this book. The encoder is a *generator* that streams `("run", char, length)` tokens without buffering. The decoder *dispatches with `match`*, unpacking each token's fields and rebuilding the data - and refusing, with a clear error, anything it does not recognise. The `"".join(out)` idiom stitches a list of string pieces into one final string (far faster than repeated `+`, because it avoids rebuilding the growing string each time). And the closing `assert` is the *round-trip test*: encode, then decode, and demand that we get back exactly what we started with. That property, *losslessness*, is the iron contract of every lossless compressor in Volume II: whatever transformations happen in between, `decode(encode(x))` must equal `x`, byte for byte. We have now written, tested, and proven a complete (if humble) lossless codec, structured the way the real ones are.
]

#scoreboard(caption: "tinyzip toolkit after Chapter 16 (sample = \"banana bandana\", 14 chars)",
  [No compression (8 bits/char)], [112 bits], [1.00×], [The bar to beat (from Chapter 15)],
  [Frequency model (`utils.histogram`, Step 2)], [n/a], [n/a], [One typed call; tested vs `Counter`],
  [Streaming RLE demo + round-trip test], [n/a], [n/a], [First lossless encode/decode pair (illustrative)],
)

#keyidea[
Choosing the right container is most of the battle. A *list* `[ ]` is an ordered, changeable shelf; a *tuple* `( )` is a fixed record you can use as a dict key; a *dict* `{k: v}` maps keys to values with near-instant lookup - the natural home for a frequency table; a *set* `{ }` holds distinct items for fast membership. Match the structure to the problem and, as Torvalds said, the code follows. Everything else this chapter taught (slicing, comprehensions, functions, generators, `match`) is about *moving data between these containers* cleanly.
]

#takeaways((
  [Four containers cover almost everything: `list` (ordered, mutable), `tuple` (ordered, immutable, hashable - usable as a key), `dict` (key→value, fast lookup, insertion-ordered), and `set` (distinct items, fast membership).],
  [*Slicing* `s[start:stop:step]` extracts a piece using half-open intervals (stop excluded), so slice length is `stop − start`, slices join cleanly, and `s[::-1]` reverses. A full slice `s[:]` copies.],
  [Mutable containers are shared by reference: `b = a` aliases the *same* list, so a change through either is seen through both. Copy with `a.copy()` or `a[:]` when you need independence.],
  [*Comprehensions* build a container in one line - `[expr for x in it if cond]` - with `{k: v for ...}` and `{x for ...}` for dicts and sets. Use them to *produce values*, not for side effects.],
  [*Functions* (`def`) name reusable work; they take positional, keyword, and default arguments, and `return` a value (or `None`). Never default a parameter to a mutable value.],
  [*Type hints* like `dict[int, int]`, `list[tuple[int, int]]`, and `-> float` document a function's domain and codomain. They are ignored at run time but caught by type checkers and invaluable to readers.],
  [*Modules* and `import` split code and unlock the standard library - `math.log2` for bits, `collections.Counter` for an instant frequency table. Guard demo code with `if __name__ == "__main__":`.],
  [*Iterators* (`iter`/`next`/`StopIteration`) power every `for` loop; *generators* (`yield`) produce items lazily, one at a time, so a codec can *stream* data far larger than memory.],
  [The *`match`* statement branches on the *shape* of data and destructures it in one move - the idiomatic way to dispatch on a codec's tagged token stream, e.g. `case ("match", distance, length):`.],
  [`tinyzip` now has a typed, tested `utils.py` whose canonical `histogram(data: bytes) -> dict[int, int]` (Step 2) maps each byte value to its count, plus `alphabet_size` and `total_symbols`; and we built an illustrative streaming RLE codec with a round-trip *losslessness* test - the exact structure every later codec will share.],
))

== Exercises

#exercise("16.1", 1)[
Predict, then check in the REPL, the result and the *type* of each: (a) `[1, 2, 3] + [4, 5]`, (b) `(1, 2)[0]`, (c) `{"a": 1, "a": 2}`, (d) `len({3, 1, 4, 1, 5})`, (e) `"compression"[3:7]`, (f) `"abcdef"[::-1]`.
]
#solution("16.1")[
(a) `[1, 2, 3, 4, 5]`, a `list` - `+` concatenates lists. (b) `1`, an `int` - indexing a tuple reads its first element. (c) `{'a': 2}`, a `dict` - a key cannot repeat, so the later value wins. (d) `4`, an `int` - the set `{3, 1, 4, 5}` drops the duplicate `1`. (e) `'pres'`, a `str` - positions 3,4,5,6, with 7 excluded. (f) `'fedcba'`, a `str` - a step of −1 reverses.
]

#exercise("16.2", 1)[
Explain why this prints `[1, 2, 3, 99]` and not `[1, 2, 3]`, and fix it so that `original` is left unchanged:
```python
original = [1, 2, 3]
backup = original
backup.append(99)
print(original)
```
]
#solution("16.2")[
`backup = original` copies the *arrow*, not the list, so `backup` and `original` name the *same* list; appending through `backup` changes the one shared list, which `original` also sees. The fix is to make a genuine copy: `backup = original.copy()` (or `backup = original[:]`). Then `backup.append(99)` touches only the copy, and `original` stays `[1, 2, 3]`. This aliasing of mutable containers is the chapter's central pitfall.
]

#exercise("16.3", 1)[
Rewrite each loop as a one-line comprehension: (a) build a list of the cubes of `0` through `5`; (b) build a list of only the *uppercase* characters in `"Hello World"` (hint: `ch.isupper()`); (c) build a dict mapping each character of `"abc"` to its byte value via `ord`.
]
#solution("16.3")[
(a) `[n ** 3 for n in range(6)]` → `[0, 1, 8, 27, 64, 125]`.
(b) `[ch for ch in "Hello World" if ch.isupper()]` → `['H', 'W']`.
(c) `{ch: ord(ch) for ch in "abc"}` → `{'a': 97, 'b': 98, 'c': 99}`.
Each replaces the empty-container / loop / append pattern with a single readable expression - transform on the left, optional filter on the right.
]

#exercise("16.4", 2)[
Write a typed function `distinct_count(text: str) -> int` that returns how many *distinct* characters appear in `text`, using a set. Then write `is_all_same(text: str) -> bool` that returns `True` exactly when every character in a non-empty string is identical, in a single line built on `distinct_count`.
]
#solution("16.4")[
```python
def distinct_count(text: str) -> int:
    return len(set(text))

def is_all_same(text: str) -> bool:
    return distinct_count(text) == 1
```
`set(text)` collapses `text` to its distinct characters, and `len` counts them, so `distinct_count("mississippi")` is `4`. A string whose characters are all identical has exactly *one* distinct character, so `is_all_same` just asks whether the distinct count is `1` - `is_all_same("aaaa")` is `True`, `is_all_same("aab")` is `False`. (A run of identical bytes is exactly the case RLE compresses best, which is why a codec might call such a check.)
]

#exercise("16.5", 2)[
Using `.items()`, write `total_bits(counts: dict[str, int], code_lengths: dict[str, int]) -> int` that returns the total number of bits to encode a message, given each symbol's frequency in `counts` and its codeword length in `code_lengths`. (This is the sum, over symbols, of frequency times code length - the cost of a code, which Huffman coding will later minimise.)
]
#solution("16.5")[
```python
def total_bits(counts: dict[str, int],
               code_lengths: dict[str, int]) -> int:
    total = 0
    for symbol, freq in counts.items():
        total += freq * code_lengths[symbol]
    return total
```
The loop unpacks each `(symbol, freq)` pair from `counts.items()`, looks up that symbol's codeword length, and adds `freq * length` to the running total. For `counts = {"a": 6, "b": 2}` and `code_lengths = {"a": 1, "b": 2}` it returns `6*1 + 2*2 = 10` bits. This expression, $sum_s "freq"(s) times "len"(s)$, is precisely the quantity Chapter 24's Huffman algorithm exists to make as small as possible.
]

#exercise("16.6", 2)[
Write a generator `evens(n: int)` that yields the even numbers `0, 2, 4, ...` up to (but not including) `n`, one at a time. Show two ways to consume it: a `for` loop that prints each, and a single call that collects them all into a list. Why might the generator be preferable to returning a list outright?
]
#solution("16.6")[
```python
def evens(n: int):
    for i in range(0, n, 2):       # step by 2
        yield i

for e in evens(10):
    print(e, end=" ")              # 0 2 4 6 8
print()
all_evens = list(evens(10))        # [0, 2, 4, 6, 8]
```
`yield` makes `evens` produce its numbers lazily, one per request, so a `for` loop pulls them as needed and `list(...)` forces them all. The generator is preferable when `n` is huge or the consumer might stop early: it never builds the whole list in memory, producing each value only when asked - the same thrift that lets `tinyzip` stream a file larger than RAM.
]

#exercise("16.7", 2)[
A token in a codec's stream is one of `("literal", byte)`, `("match", distance, length)`, or `("end",)`. Write `decode_size(token: tuple) -> int` that uses a `match` statement to return how many output bytes the token produces: a literal makes 1 byte, a match makes `length` bytes, and `("end",)` makes 0. Raise `ValueError` on anything else.
]
#solution("16.7")[
```python
def decode_size(token: tuple) -> int:
    match token:
        case ("literal", _byte):
            return 1
        case ("match", _distance, length):
            return length
        case ("end",):
            return 0
        case _:
            raise ValueError(f"unknown token: {token}")
```
Each `case` matches the token's tag and arity and binds the fields it needs (the wildcard `_byte` and `_distance` show we accept a value but ignore it). A literal expands to one byte, a match to its `length` bytes, and `end` to none; anything unrecognised raises. Summing `decode_size` over a token stream tells a decoder exactly how large its output buffer must be - the kind of bookkeeping every LZ decoder does.
]

#exercise("16.8", 2)[
Without running it, give the output and explain the aliasing:
```python
def add_tag(tags=[]):          # mutable default - a trap!
    tags.append("x")
    return tags

print(add_tag())
print(add_tag())
print(add_tag())
```
Then rewrite `add_tag` correctly so each call with no argument starts from an empty list.
]
#solution("16.8")[
It prints `['x']`, then `['x', 'x']`, then `['x', 'x', 'x']`. The default list is created *once*, when the function is defined, and *shared* across every call that omits the argument, so each call appends to the same growing list. The fix uses `None` as the sentinel and makes a fresh list inside:
```python
def add_tag(tags=None):
    if tags is None:
        tags = []
    tags.append("x")
    return tags
```
Now every call without an argument gets its own empty list, so each prints `['x']`. "Never default to a mutable value" is the rule; `None` plus an inside check is the cure.
]

#exercise("16.9", 3)[
Building on Step 2's `histogram(data: bytes) -> dict[int, int]`, write a companion `entropy_terms(counts: dict[int, int]) -> list[float]` that returns the list of probabilities $p_i = "count"_i / "total"$ for each symbol. (We will turn these probabilities into bits with $-sum p_i log_2 p_i$ in Volume II; here, just produce the probabilities.) Use `sum`, a comprehension, and type hints. Then show the two functions composing on `data = b"aab"`.
]
#solution("16.9")[
```python
def entropy_terms(counts: dict[int, int]) -> list[float]:
    total = sum(counts.values())
    return [c / total for c in counts.values()]

# Composing with Step 2's histogram:
counts = histogram(b"aab")            # {97: 2, 98: 1}
probs = entropy_terms(counts)         # [0.666..., 0.333...]
```
The canonical `histogram` already maps each byte value to its count - iterating over `bytes` hands you integers directly (a fact Chapter 17 makes much of), so `histogram(b"aab")` is `{97: 2, 98: 1}`. `entropy_terms` finds the total with `sum(counts.values())`, then a comprehension turns each count into a probability `c / total`, giving `[0.666..., 0.333...]`. These $p_i$ are the raw material of the entropy formula - Volume II multiplies each by its own $-log_2 p_i$ and sums, but the probabilities themselves are this one comprehension.
]

#exercise("16.10", 3)[
Extend the streaming RLE codec from the demo above so that it never *expands* the data. Write `rle_encode_smart(data: str)` that yields `("run", ch, length)` only when a run has length 2 or more, and `("lit", ch)` for a single, isolated character - and a matching `rle_decode_smart` using `match`. Explain why this still cannot beat the counting bound of Chapter 8, and prove with a round-trip `assert` that your codec stays lossless on `"aaab"` and on `"abcd"`.
]
#solution("16.10")[
```python
def rle_encode_smart(data: str):
    i = 0
    while i < len(data):
        ch = data[i]
        length = 1
        while i + length < len(data) and data[i + length] == ch:
            length += 1
        if length >= 2:
            yield ("run", ch, length)
        else:
            yield ("lit", ch)
        i += length

def rle_decode_smart(tokens) -> str:
    out: list[str] = []
    for token in tokens:
        match token:
            case ("run", ch, length):
                out.append(ch * length)
            case ("lit", ch):
                out.append(ch)
            case _:
                raise ValueError(f"unknown token: {token}")
    return "".join(out)

for s in ("aaab", "abcd"):
    assert rle_decode_smart(rle_encode_smart(s)) == s
print("both round-trips pass ✓")
```
Using a separate `("lit", ch)` token for isolated characters avoids emitting a wasteful run-length of 1, so the encoder no longer doubles run-free data the way Chapter 15's toy did. But it *still* cannot shrink every input: the two token kinds must be distinguishable, which costs at least one tag bit per token, so an incompressible string like `"abcd"` is encoded with overhead, never savings. That is the counting/pigeonhole bound of Chapter 8 in action - no lossless scheme shrinks every possible input; a tag that lets you pick the better of two encodings must itself be stored. The `assert` loop confirms losslessness on both a runny and a run-free string, the non-negotiable contract.
]

== Further reading

- #link("https://docs.python.org/3/tutorial/datastructures.html")[The Python Tutorial - Data Structures] - the official, free walkthrough of lists, tuples, dicts, sets, comprehensions, and slicing, current for Python 3.14.
- #link("https://docs.python.org/3/library/collections.html")[`collections` - Container datatypes] - the standard-library module behind `Counter`, plus `defaultdict`, `deque`, and `namedtuple`, all of which recur in real codec code.
- #link("https://docs.python.org/3/reference/compound_stmts.html#the-match-statement")[The `match` statement reference] and #link("https://peps.python.org/pep-0636/")[PEP 636 - Structural Pattern Matching: Tutorial] - the gentle, example-led introduction to `match` and its patterns.
- #link("https://peps.python.org/pep-0695/")[PEP 695 - Type Parameter Syntax] - the modern (Python 3.12+) syntax for generics and type aliases that makes hints like `dict[int, int]` read cleanly.
- #link("https://docs.python.org/3/howto/functional.html")[Functional Programming HOWTO] - Python's own guide to iterators and generators, the streaming machinery this chapter introduced.
- #link("https://docs.python.org/3/whatsnew/3.14.html")[What's New in Python 3.14] - release notes for the version we use throughout the book.

#bridge[
You can now hold and shape data: containers to store it, slicing and comprehensions to reshape it, functions and type hints to name and document the work, generators to stream it, and `match` to dispatch on its shape. `tinyzip` has a real toolkit - a typed `utils.py` and a tested, lossless RLE codec. But everything so far has worked on *strings* of characters, and a real compressor works on raw *bytes* - the 0-to-255 values of Chapter 13 - and must read and write actual *files* and pack individual *bits*. In *Chapter 17* we make that leap: `bytes` and `bytearray`, the bit operators `& | ^ << >>` from Chapter 5 wielded in Python, reading and writing binary files, the `struct` module, and a from-scratch `BitReader`/`BitWriter` - the toolkit that lets `tinyzip` emit genuine compressed files. With that final piece of the language in hand, Volume II's first true codec, Huffman coding, will be ours to build.
]
