#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Vectors, Matrices, and Linear Transformations

#epigraph[
  "I have had my results for a long time: but I do not yet know how I am to arrive at them."
][Carl Friedrich Gauss]

Here is a small magic trick. Take eight numbers — say the brightnesses of eight pixels in a row across a photograph, which because the photo is smooth will be eight numbers that barely differ:

$ 52, quad 55, quad 61, quad 66, quad 70, quad 61, quad 64, quad 73. $

Eight numbers, eight bytes. Now multiply that little list by a fixed table of cosines — a table that never changes, the same table for every photograph ever taken — and out comes a *different* list of eight numbers:

$ 156, quad -22, quad 1, quad 3, quad 1, quad -1, quad 0, quad 1. $

Same information, perfectly reversible: feed the second list back through the table's twin and you get the original eight pixels exactly. But look at the shape of it. The first number is large and carries the gist; the rest have collapsed toward zero. Six of the eight are now small enough that, if we are willing to lose a hair of fidelity, we can round them to nothing and store almost nothing at all. We have not thrown information away yet — we have just *rearranged* it so that almost all of it piles into one corner, leaving the rest nearly empty and nearly free to discard.

That rearrangement is the engine inside JPEG, inside MP3, inside every video your phone has ever played. It is a *linear transformation*, performed by a *matrix*, acting on a *vector*. Those three words — vector, matrix, transformation — are the subject of this chapter, and by the end of it the magic table above will hold no mystery: you will know what it is, why those particular cosines, and exactly why the energy slides into the corner. The same three words also describe what happens inside every layer of every neural network in Volume IV: a neural network, stripped of its mystique, is mostly a tall stack of matrices multiplied by vectors. Master this one chapter and two whole volumes of this book stop being magic and start being arithmetic.

#recap[
  In Chapter 6 we built *functions* — machines that take an input and return exactly one output — and *sets*. In Chapter 7 we made *exponents and logarithms* second nature, and in Chapter 11 we met $sum$ (sigma) notation for sums, sequences, and the first gentle ideas of slopes and gradients (we will lean on $sum$ constantly here). We have also, since Chapter 4, been perfectly at home with ordered lists of numbers — a row of pixels, a run of audio samples, a byte as eight bits. This chapter gives those lists a name (*vectors*), gives them a geometry (arrows you can measure and add), and then builds the machine (*matrices*) that transforms one list into another. Everything is built from the arithmetic you already own: adding and multiplying numbers, and the $sum$ shorthand from Chapter 11.
]

#objectives((
  [Read a *vector* two ways at once — as an ordered list of numbers and as an arrow in space — and add, scale, and measure them.],
  [Compute a *dot product* by hand and explain what it measures: alignment, similarity, and "how much of one thing is in another."],
  [Define *length* (norm), *distance*, and the *angle* between vectors, and recognise *orthogonality* (perpendicularity) as the key to clean, independent coordinates.],
  [Read a *matrix* as a table of numbers and, more importantly, as a *transformation* that takes vectors in and sends vectors out.],
  [Multiply a matrix by a vector, and a matrix by a matrix, and say in plain words what each product means.],
  [Explain *basis*, *change of basis*, and *orthogonal* matrices — the precise machinery behind every transform codec — and prove that an orthogonal transform preserves energy.],
  [Write Python that represents vectors and matrices as lists, and code dot products, matrix–vector products, and a tiny reusable transform by hand.],
  [Connect all of it to compression: why the DCT is "just a matrix," why decorrelation slides energy into a corner, and why neural networks are stacks of these same operations.],
))

== A vector is a list, and also an arrow

Begin with the simplest honest definition, the one we have secretly used since Chapter 4. A *vector* is an ordered list of numbers. That is all. The row of pixels $(52, 55, 61, 66, 70, 61, 64, 73)$ is a vector with eight entries. A stereo audio sample $(0.3, -0.1)$ — left channel, right channel — is a vector with two entries. The colour of a pixel, $(255, 128, 0)$ for a particular orange, is a vector with three entries. The word *ordered* is doing real work: $(1, 2)$ and $(2, 1)$ are different vectors, just as "left then right" is different from "right then left."

#definition("Vector")[
  A *vector* of *dimension* $n$ is an ordered list of $n$ numbers, called its *components* or *entries*. We write it across, $bold(v) = (v_1, v_2, dots, v_n)$, or stacked down, and we name the whole list with one bold letter $bold(v)$. The set of all vectors with $n$ real-number components is written $RR^n$ ("R-n"), read "$n$-dimensional space." Each number $v_i$ is the vector's $i$-th *coordinate*.
]

The notation $RR^n$ deserves a word, because it will appear for the rest of the book. The $RR$ is the set of all real numbers — every decimal, positive, negative, or zero — which we met informally in Chapter 6. The little exponent $n$ counts the slots. So $RR^2$ is "all pairs of numbers," $RR^3$ is "all triples," and $RR^8$ is "all lists of eight numbers" — the home of our eight pixels. (Yes, it is the same exponent notation as Chapter 7; a list of $n$ numbers is a point you reach by choosing one value for each of $n$ independent slots, and choices multiply.)

Now the second way to see a vector, the way that turns dry lists into geometry. A vector of dimension two, $(3, 2)$, can be drawn as an *arrow*: start at the origin — the point $(0,0)$, the centre of the page — and walk $3$ steps right and $2$ steps up. The arrowhead lands at the point $(3, 2)$, and the arrow from origin to arrowhead *is* the vector. The list tells you the destination; the arrow shows you the journey. Both are the same object wearing different clothes.

#fig([The vector $(3,2)$ drawn as an arrow from the origin: three steps right, two steps up. The list of numbers and the arrow are the same object.],
  cetz.canvas({
    import cetz.draw: *
    // axes
    line((-0.5, 0), (4.2, 0), mark: (end: ">"), stroke: 0.6pt)
    line((0, -0.5), (0, 3.2), mark: (end: ">"), stroke: 0.6pt)
    content((4.4, 0))[$x$]
    content((0, 3.45))[$y$]
    // gridlines
    for x in (1, 2, 3) { line((x, -0.08), (x, 0.08), stroke: 0.5pt) }
    for y in (1, 2) { line((-0.08, y), (0.08, y), stroke: 0.5pt) }
    content((3, -0.32))[$3$]
    content((-0.28, 2))[$2$]
    // the vector
    line((0,0), (3,2), mark: (end: ">"), stroke: 1.6pt + rgb("#0b5394"))
    // helper dashes
    line((3,0), (3,2), stroke: (dash: "dashed", paint: gray, thickness: 0.5pt))
    line((0,2), (3,2), stroke: (dash: "dashed", paint: gray, thickness: 0.5pt))
    content((1.7, 1.35))[$bold(v) = (3,2)$]
  }))

This double vision — list *and* arrow — is the whole reason vectors are powerful. The *list* view lets a computer store and crunch a vector as plain numbers in memory. The *arrow* view lets us reason about it with geometry: lengths, directions, angles, "this points the same way as that." Compression lives in the gap between the two. A block of pixels is just a list to the machine; but when we ask "is this block smooth or busy?" we are really asking a geometric question about the arrow, and the transform we apply is a geometric move. Hold both pictures in your head at once.

#gopython("Lists as vectors")[
  We have used Python lists since the primer chapters; here we simply agree to *treat a list of numbers as a vector*. A list is written with square brackets, items separated by commas, and you fetch an item by its position (counting from $0$):
  ```python
  v: list[float] = [3.0, 2.0]      # a 2-D vector
  print(v[0])                      # 3.0  — the first component
  print(len(v))                    # 2    — the dimension
  pixels = [52, 55, 61, 66, 70, 61, 64, 73]   # an 8-D vector
  ```
  The type hint `list[float]` (Python 3.14 syntax) says "a list whose items are floats." We will keep vectors as plain lists for clarity; real code uses libraries like NumPy, but every operation we write would work the same on a bare list. Nothing here is hidden.
  ]

=== Adding vectors and scaling them

Two operations make lists into a genuine algebra, and both are exactly what the arrow picture suggests.

*Adding* two vectors means adding them slot by slot: $(3, 2) + (1, 4) = (3+1, 2+4) = (4, 6)$. You may only add vectors of the *same* dimension — you cannot add a pair to a triple, just as you cannot add "left, right" to "red, green, blue." Geometrically, vector addition is "follow the first arrow, then from its tip follow the second arrow"; the combined journey lands you at the sum. This is the *tip-to-tail* rule, and it is why forces, velocities, and — for us — signals add the way they do.

*Scaling* a vector means multiplying every component by a single ordinary number, called a *scalar*: $2 dot (3, 2) = (6, 4)$, and $0.5 dot (3, 2) = (1.5, 1)$. Geometrically, scaling stretches or shrinks the arrow without turning it: $2 dot bold(v)$ points the same way as $bold(v)$ but is twice as long; $-1 dot bold(v)$ is the same length pointing backwards. The word *scalar* — a plain number, as opposed to a vector — earns its name precisely because its whole job is to *scale*.

#definition("Vector addition and scalar multiplication")[
  For vectors $bold(u) = (u_1, dots, u_n)$ and $bold(v) = (v_1, dots, v_n)$ in $RR^n$ and a scalar $c in RR$:
  $ bold(u) + bold(v) = (u_1 + v_1, dots, u_n + v_n), quad quad c dot bold(v) = (c v_1, dots, c v_n). $
  Subtraction is addition of the negative: $bold(u) - bold(v) = bold(u) + (-1)dot bold(v) = (u_1 - v_1, dots, u_n - v_n)$.
]

These two operations are the entire reason the subject is called *linear* algebra. A combination built only out of scaling-and-adding — like $3 bold(u) + 2 bold(v) - bold(w)$ — is called a *linear combination*, and linear combinations are the only thing this chapter ever really does. Everything fancy ahead (transforms, bases, neural layers) is a linear combination wearing a costume.

#fig([Tip-to-tail addition. Walk along $bold(u) = (3,1)$, then from its tip walk along $bold(v) = (1,2)$; you arrive at $bold(u)+bold(v) = (4,3)$.],
  cetz.canvas({
    import cetz.draw: *
    line((-0.4, 0), (4.6, 0), mark: (end: ">"), stroke: 0.6pt)
    line((0, -0.4), (0, 3.6), mark: (end: ">"), stroke: 0.6pt)
    // u from origin
    line((0,0), (3,1), mark: (end: ">"), stroke: 1.4pt + rgb("#0b5394"))
    content((1.5, 0.25))[$bold(u)$]
    // v from tip of u
    line((3,1), (4,3), mark: (end: ">"), stroke: 1.4pt + rgb("#783f04"))
    content((3.75, 2.0))[$bold(v)$]
    // sum
    line((0,0), (4,3), mark: (end: ">"), stroke: 1.6pt + rgb("#0b6e4f"))
    content((1.7, 1.9))[$bold(u)+bold(v)$]
  }))

#gopython("Looping with zip and comprehensions for vector arithmetic")[
  To add two lists slot by slot we walk both at once. Python's `zip` pairs up the items of two lists, and a *list comprehension* — `[expr for item in iterable]` — builds a new list in one line (both met in the primer chapters):
  ```python
  def add(u: list[float], v: list[float]) -> list[float]:
      return [a + b for a, b in zip(u, v)]        # slot-by-slot sum

  def scale(c: float, v: list[float]) -> list[float]:
      return [c * x for x in v]                    # every entry times c

  print(add([3, 2], [1, 4]))      # [4, 6]
  print(scale(2, [3, 2]))         # [6, 4]
  ```
  Read `[a + b for a, b in zip(u, v)]` as "the list of $a+b$, as $(a,b)$ ranges over paired entries of `u` and `v`." This little `add`/`scale` pair is the seed of everything in this chapter.
  ]

#checkpoint[
  Compute $2 dot (1, 0, -3) + (4, 5, 6)$.
][Scale first: $2 dot (1,0,-3) = (2, 0, -6)$. Then add slot by slot: $(2+4, 0+5, -6+6) = (6, 5, 0)$.]

== The dot product: measuring alignment

Adding and scaling keep us inside the world of vectors. The next operation reaches *out* of it: the *dot product* takes two vectors and returns a single ordinary number. That number is the most useful quantity in all of applied mathematics, because it measures *how much two vectors agree*.

The recipe is simple: multiply the vectors slot by slot, then add up all the products.

#definition("Dot product")[
  For two vectors $bold(u) = (u_1, dots, u_n)$ and $bold(v) = (v_1, dots, v_n)$ of the same dimension, their *dot product* (or *inner product*) is the single number
  $ bold(u) dot bold(v) = u_1 v_1 + u_2 v_2 + dots + u_n v_n = sum_(i=1)^n u_i v_i. $
  The result is a *scalar*, not a vector. (The $sum$ is exactly the sigma sum from Chapter 11.)
]

A tiny example, slowly. Let $bold(u) = (3, 2)$ and $bold(v) = (1, 4)$. Then
$ bold(u) dot bold(v) = 3 times 1 + 2 times 4 = 3 + 8 = 11. $
Multiply the first slots ($3 times 1$), multiply the second slots ($2 times 4$), add the results ($3 + 8$). That is the whole operation. For eight-dimensional pixel vectors you do the same thing with eight products instead of two.

Why does this matter? Because the dot product secretly measures *alignment*. Here is the beautiful fact, which we will use without exhausting its depths: for any two vectors,
$ bold(u) dot bold(v) = norm(bold(u)) thin norm(bold(v)) thin cos theta, $
where $norm(bold(u))$ is the length of $bold(u)$ (defined in a moment), and $theta$ is the angle between the two arrows. We will not prove this formula from scratch — it follows from the law of cosines, geometry from before this book — but its *consequences* are everything:

- If the two vectors point in the *same* direction, $theta = 0$, $cos theta = 1$, and the dot product is large and positive — maximal agreement.
- If they are *perpendicular*, $theta = 90 degree$, $cos theta = 0$, and the dot product is exactly *zero* — no agreement, no overlap, total independence.
- If they point in *opposite* directions, $theta = 180 degree$, $cos theta = -1$, and the dot product is large and negative — maximal disagreement.

#keyidea[
  The dot product answers one question: *how much of one vector lies along the other?* A big positive number means "they line up." Zero means "they are perpendicular — utterly independent." This single idea is the hinge of the whole chapter. Decorrelation, orthogonal transforms, similarity search, the attention mechanism in modern AI — all of them are, at heart, a pile of dot products asking "how much does this agree with that?"
]

#gomaths("Why slot-by-slot multiply-and-add measures an angle")[
  It feels like a coincidence that a mechanical recipe (multiply, add) should know about angles. It is not. In two dimensions, write the arrows in terms of their lengths and directions and expand; the cross terms reassemble — via the trigonometric identity $cos(alpha - beta) = cos alpha cos beta + sin alpha sin beta$ — into exactly $norm(bold(u))norm(bold(v))cos theta$, where $theta$ is the angle between them. The "multiply matching slots and add" rule is the algebra; "length times length times cosine of the angle" is the geometry; they are the same number seen from two sides. You do not need the derivation to use the result — but it is reassuring that the bridge is solid, not magic. The key takeaway to carry forward: *dot product zero $arrow.l.r.double$ perpendicular.*
  ]

#gopython("Coding the dot product with sum and a generator")[
  The dot product is a one-liner once you have `zip`. We pair the slots, multiply each pair, and sum:
  ```python
  def dot(u: list[float], v: list[float]) -> float:
      return sum(a * b for a, b in zip(u, v))

  print(dot([3, 2], [1, 4]))      # 11
  print(dot([1, 0], [0, 1]))      # 0  — perpendicular axes
  ```
  Here `a * b for a, b in zip(u, v)` is a *generator expression* — like a list comprehension but it produces the products one at a time and hands them straight to `sum`, never building a list in memory. For an 8-vector that is a rounding error; for the million-dimensional vectors inside a neural network it saves real memory. `sum(...)` is exactly the $sum$ of Chapter 11, now in code.
  ]

#checkpoint[
  Are $(2, 1)$ and $(-1, 2)$ perpendicular? Compute their dot product.
][$2 times(-1) + 1 times 2 = -2 + 2 = 0$. Yes — a zero dot product means the arrows meet at a right angle.]

== Length, distance, and the right angle

The dot product quietly hands us three more tools, all of which we need for compression.

*Length.* How long is the arrow $bold(v) = (3, 4)$? Pythagoras, from before this book: walk $3$ right and $4$ up, and the straight-line distance to the tip is $sqrt(3^2 + 4^2) = sqrt(9 + 16) = sqrt(25) = 5$. In general the length — properly the *norm*, written $norm(bold(v))$ — is the square root of the sum of the squares of the components. But notice: the sum of the squares of the components is just the vector dotted with *itself*, $bold(v) dot bold(v) = v_1^2 + dots + v_n^2$. So length is the dot product in disguise.

#definition("Norm (length) of a vector")[
  The *norm* (Euclidean length) of $bold(v) = (v_1, dots, v_n)$ is
  $ norm(bold(v)) = sqrt(v_1^2 + v_2^2 + dots + v_n^2) = sqrt(bold(v) dot bold(v)). $
  The *squared norm* $norm(bold(v))^2 = bold(v) dot bold(v) = sum_i v_i^2$ is often the friendlier quantity — no square root — and in compression it has a name we will use constantly: the *energy* of the signal.
]

That word *energy* is not a metaphor we are borrowing loosely; it is the literal physical energy of a sound wave or the total squared brightness of an image patch, and it is the quantity transforms are built to concentrate. Remember our eight pixels: before the transform the energy was spread across all eight numbers; after, almost all of it sat in the first. We will soon *prove* that a good transform keeps the total energy unchanged while moving it around — that is the entire game.

*Distance.* The distance between two vectors is the length of the arrow between them: $"dist"(bold(u), bold(v)) = norm(bold(u) - bold(v))$. Subtract slot by slot, square, add, root. This is how a codec measures *distortion* — how far the reconstructed signal $hat(bold(x))$ strayed from the original $bold(x)$. The famous "mean squared error" (MSE) you will meet in Volume III is exactly $norm(bold(x) - hat(bold(x)))^2$ divided by the number of components. Distortion is a distance between vectors. Hold that.

*Orthogonality.* Two vectors are *orthogonal* — a fancy word for *perpendicular* — exactly when their dot product is zero. We just saw $(1,0)$ and $(0,1)$ are orthogonal, and so are $(2,1)$ and $(-1,2)$. Orthogonality is the property that makes coordinates *clean*: if your reference directions are mutually orthogonal, then the amount of "stuff" along one direction tells you nothing about the amount along another. They do not interfere. This non-interference is precisely what lets a codec store the eight transformed numbers independently and throw some away without disturbing the rest.

#pitfall[
  A zero dot product means orthogonal, but it does *not* mean "small" or "unimportant." Two long arrows at right angles still have a dot product of zero. Conversely, two short arrows pointing the same way can have a small dot product simply because they are short. The dot product blends *length* and *alignment*; to isolate the angle you must divide out the lengths (that is *cosine similarity*, $bold(u) dot bold(v) \/ (norm(bold(u)) norm(bold(v)))$, the workhorse of search engines and recommendation systems).
]

#tryit[
  Take any photo block as a list of numbers and compute its energy $sum_i v_i^2$ before and after running it through the DCT table at the top of this chapter. The two totals match (up to a fixed scaling). That equality is not luck; it is the orthogonality theorem we prove later in the chapter — energy is conserved, only *rearranged*.
]

== The matrix: a table that transforms

So far a vector goes in and a number comes out (dot product) or a vector comes out (add, scale). Now we want the operation at the heart of compression: a vector goes in and a *different, equally long* vector comes out — the eight pixels in, the eight transformed coefficients out. The machine that does this is a *matrix*.

On the page a matrix is just a rectangular table of numbers, written in big brackets, with *rows* (across) and *columns* (down). A matrix with $m$ rows and $n$ columns is called an "$m times n$ matrix" (say "$m$ by $n$"). For example,
$ A = mat(2, 0; 0, 3), quad quad B = mat(1, 2, 3; 4, 5, 6) $
where $A$ is $2 times 2$ and $B$ is $2 times 3$. The entry in row $i$, column $j$ is written $A_(i j)$; so for $B$ above, $B_(1 2) = 2$ and $B_(2 3) = 6$. Rows first, columns second — always, the same convention as a spreadsheet cell reference.

#definition("Matrix")[
  An *$m times n$ matrix* $A$ is a rectangular array of numbers with $m$ rows and $n$ columns. The number in the $i$-th row and $j$-th column is the *entry* $A_(i j)$. A matrix with the same number of rows as columns ($m = n$) is called *square*. A vector is just a matrix with a single column (or a single row).
]

But the table is the costume, not the creature. The real identity of a matrix is that it is a *transformation*: a rule that takes a vector in and produces a vector out, by a fixed recipe of scalings and additions. The table simply *stores* that recipe. To see the recipe, we need to learn how a matrix *acts* on a vector — the matrix–vector product.

=== Multiplying a matrix by a vector

Here is the single most important calculation in the chapter. To multiply an $m times n$ matrix $A$ by a vector $bold(x)$ of length $n$, you take the *dot product of each row of $A$ with $bold(x)$*. The first row dotted with $bold(x)$ gives the first output component; the second row dotted with $bold(x)$ gives the second; and so on down the rows. The output is a vector of length $m$ — one component per row.

That is the whole rule, and notice it is built entirely from the dot product you already own. A matrix–vector product is just a *stack of dot products*. Let us do one slowly. Take

$ A = mat(2, 0; 0, 3), quad bold(x) = (5, 4). $

Row $1$ of $A$ is $(2, 0)$; dotted with $bold(x) = (5,4)$ that is $2 times 5 + 0 times 4 = 10$. Row $2$ is $(0, 3)$; dotted with $bold(x)$ that is $0 times 5 + 3 times 4 = 12$. So

$ A bold(x) = mat(2, 0; 0, 3) vec(5, 4) = vec(10, 12). $

What did this matrix *do*? It doubled the first coordinate ($5 arrow.r 10$) and tripled the second ($4 arrow.r 12$). It is a *stretch* — twice as wide, three times as tall. That is the transformation this particular table stores. A different table stores a different transformation: a rotation, a reflection, a shear, or — the one we care about — the cosine mixing that powers JPEG.

#definition("Matrix–vector product")[
  For an $m times n$ matrix $A$ with rows $bold(a)_1, dots, bold(a)_m$ (each a vector of length $n$) and a vector $bold(x)$ of length $n$, the product $A bold(x)$ is the length-$m$ vector whose $i$-th component is the dot product of row $i$ with $bold(x)$:
  $ (A bold(x))_i = bold(a)_i dot bold(x) = sum_(j=1)^n A_(i j) x_j. $
  The widths must match: the number of *columns* of $A$ must equal the *length* of $bold(x)$, because each row of $A$ has to dot evenly against $bold(x)$.
]

There is a second, equally true way to read the very same product, and it unlocks the whole geometric picture. Instead of "rows dotted with $bold(x)$," read it as "$bold(x)$ tells you how much of each *column* to take." Watch:

$ mat(2, 0; 0, 3) vec(5, 4) = 5 dot vec(2, 0) + 4 dot vec(0, 3) = vec(10, 0) + vec(0, 12) = vec(10, 12). $

The output is a *linear combination of the columns of $A$*, with the entries of $bold(x)$ as the mixing amounts: "$5$ parts of the first column, $4$ parts of the second." This is the deeper truth. The columns of a matrix are the *building blocks* it offers; the input vector is the *recipe* saying how much of each block to use; the output is the blend. When JPEG transforms a block, the matrix's columns (well, rows — by symmetry it amounts to the same family) are eight fixed cosine wave patterns, and the output coefficients say "this block is so-much flat grey, plus so-much slow ripple, plus so-much fast ripple, ..." Energy compaction means most of those amounts come out near zero.

#keyidea[
  A matrix–vector product can be read two ways, and you should be able to flip between them at will: *(1) rows dotted with the input* (the mechanical recipe), and *(2) a linear combination of the columns* (the meaning). Reading (2) is what lets you understand a transform as "expressing a signal in a new set of building blocks." Every transform codec in this book is reading (2) in disguise.
]

#gopython("Matrix as a list of lists; the matrix–vector product")[
  We store a matrix as a *list of rows*, each row itself a list — a "list of lists." Then the matrix–vector product is just "dot every row with `x`," reusing our `dot` from before:
  ```python
  Matrix = list[list[float]]      # a type alias: a matrix is rows of floats

  def matvec(A: Matrix, x: list[float]) -> list[float]:
      return [dot(row, x) for row in A]    # one dot product per row

  A = [[2, 0],
       [0, 3]]
  print(matvec(A, [5, 4]))        # [10, 12]  — doubled, tripled
  ```
  `Matrix = list[list[float]]` is a *type alias*: a readable nickname for an ugly type. The function reads almost like the definition: the output is the list of `dot(row, x)` as `row` ranges over the rows of `A`. We have written, in two lines, the operation at the core of JPEG.
  ]

=== Multiplying a matrix by a matrix

If a matrix transforms a vector, what does it mean to multiply two matrices? It means *do one transformation, then the other* — composing them into a single combined transformation. This is the deep reason matrix multiplication is defined the strange way it is.

The rule: to multiply $A$ (size $m times n$) by $B$ (size $n times p$), the entry in row $i$, column $j$ of the product $A B$ is *the dot product of row $i$ of $A$ with column $j$ of $B$*. Once again — dot products all the way down. The inner sizes must match ($A$ has $n$ columns, $B$ has $n$ rows) and the result is $m times p$.

A small worked example:
$ A = mat(1, 2; 3, 4), quad B = mat(0, 1; 1, 0), quad A B = mat(1 dot 0 + 2 dot 1, 1 dot 1 + 2 dot 0; 3 dot 0 + 4 dot 1, 3 dot 1 + 4 dot 0) = mat(2, 1; 4, 3). $

Notice what $B$ did here: $mat(0,1;1,0)$ is the *swap* matrix, and multiplying by it swapped the columns of $A$. That is "$B$'s transformation applied to $A$." Matrix multiplication is function composition written as arithmetic: $(A B) bold(x) = A(B bold(x))$, meaning "transform $bold(x)$ by $B$ first, then by $A$." Read right to left, like nested functions from Chapter 6.

#pitfall[
  Matrix multiplication is *not commutative*: in general $A B != B A$. Order is meaning. "Rotate then stretch" lands somewhere different from "stretch then rotate" — try it with your hands. This trips up everyone once; let it trip you now, on paper, rather than later in a codec. (Matrix multiplication *is* associative, though: $(A B)C = A(B C)$, so you can regroup a chain freely as long as you do not reorder it.)
]

#definition("Matrix product")[
  For $A$ of size $m times n$ and $B$ of size $n times p$, the product $A B$ is the $m times p$ matrix with entries
  $ (A B)_(i j) = sum_(k=1)^n A_(i k) B_(k j) = ("row " i "of " A) dot ("column " j "of " B). $
  It represents the composed transformation "$B$ first, then $A$." The inner dimensions ($n$) must agree.
]

#gomaths("The transpose, the identity, and the inverse")[
  Three special matrices keep appearing, so meet them once, properly.

  The *identity matrix* $I$ has $1$s down the diagonal and $0$s everywhere else, e.g. $I = mat(1, 0; 0, 1)$. It is the "do nothing" transformation: $I bold(x) = bold(x)$ for every $bold(x)$, the matrix equivalent of multiplying a number by $1$.

  The *transpose* $A^T$ flips a matrix across its diagonal — rows become columns. If $A = mat(1, 2; 3, 4)$ then $A^T = mat(1, 3; 2, 4)$, and $(A^T)_(i j) = A_(j i)$. Transposing turns the *rows* of $A$ into the *columns* of $A^T$; it is how we will state orthogonality compactly.

  The *inverse* $A^(-1)$ is the transformation that *undoes* $A$: $A^(-1) A = A A^(-1) = I$. It is the matrix version of "divide": if $A$ stretches by $2$ and $3$, then $A^(-1)$ shrinks by $1/2$ and $1/3$. Not every matrix has an inverse (one that squashes a dimension flat loses information and cannot be undone — the matrix analogue of dividing by zero) — but every transform a codec uses is carefully built to be invertible, because a compressor that cannot perfectly reverse its own transform is useless.
  ]

== Why "linear," and why we care

We have used the word *linear* a dozen times. Let us nail it down, because it is the precise property that makes the whole machine work — and the precise property a codec exploits.

A transformation $T$ (a function that takes a vector and returns a vector) is called *linear* if it respects scaling and adding:
$ T(c bold(x)) = c thin T(bold(x)) quad "and" quad T(bold(x) + bold(y)) = T(bold(x)) + T(bold(y)). $
In words: *scaling the input scales the output by the same amount, and the transform of a sum is the sum of the transforms.* Doubling the brightness of an image block doubles every transform coefficient; the transform of (block A plus block B) is the transform of A plus the transform of B. These two rules look modest, but they are exactly equivalent to "$T$ can be written as multiplication by some matrix." Every linear transformation is a matrix, and every matrix is a linear transformation. They are two names for one thing.

#theorem("Every linear transformation is a matrix")[
  A transformation $T : RR^n -> RR^m$ is linear if and only if there is an $m times n$ matrix $A$ with $T(bold(x)) = A bold(x)$ for all $bold(x)$. The columns of $A$ are simply where $T$ sends the standard axis directions.
]

#proof[
  ($arrow.l.double$) Matrix–vector multiplication obeys both rules directly from its definition $(A bold(x))_i = sum_j A_(i j) x_j$: scaling $bold(x)$ by $c$ scales every term, hence the whole sum, by $c$; and summing two inputs sums the products term by term. So any $A bold(x)$ is linear.

  ($arrow.r.double$) Suppose $T$ is linear. Write any input as a linear combination of the *standard basis vectors* $bold(e)_1 = (1, 0, dots, 0)$, $bold(e)_2 = (0, 1, 0, dots, 0)$, and so on — the unit arrows along each axis. Then $bold(x) = x_1 bold(e)_1 + dots + x_n bold(e)_n$, and applying linearity, $T(bold(x)) = x_1 T(bold(e)_1) + dots + x_n T(bold(e)_n)$. So $T$ is completely determined by the $n$ output vectors $T(bold(e)_1), dots, T(bold(e)_n)$. Stack those as the columns of a matrix $A$, and the linear-combination-of-columns reading of $A bold(x)$ reproduces exactly $T(bold(x))$. Hence $T(bold(x)) = A bold(x)$. #h(1fr)
]

This theorem is why we can be so cavalier about flipping between "transformation" and "table of numbers." They are genuinely the same. And it tells you *how to find the matrix of any linear operation*: just see where it sends each axis, and write those down as columns. We will use exactly this trick to build the DCT matrix.

#aside[
  The word *linear* comes from *line*: in one dimension, a linear function $T(x) = a x$ is a straight line through the origin. In many dimensions it generalises to "straight lines stay straight and the origin stays put" — no bending, no shifting. Linearity is the mathematics of "no surprises": the parts add up to the whole. It is also why linear methods are everywhere — they are the ones we can fully understand, decompose, and invert. Compression leans on them for exactly that reason.
]

== Basis: choosing the right axes

Here is the idea that pays for the whole chapter. The numbers in a vector are not sacred — they depend on the *axes you measure against*. The pixel list $(52, 55, dots)$ measures the block against the standard axes: "how much pixel-1, how much pixel-2, ..." But we are free to measure the very same block against a *different* set of reference directions, and get a different list of numbers describing the identical object. That set of reference directions is called a *basis*, and choosing a clever basis is the entire art of transform coding.

#definition("Basis")[
  A *basis* for $RR^n$ is a set of $n$ vectors $bold(b)_1, dots, bold(b)_n$ such that every vector $bold(x)$ in $RR^n$ can be written as a linear combination of them in *exactly one way*:
  $ bold(x) = c_1 bold(b)_1 + c_2 bold(b)_2 + dots + c_n bold(b)_n. $
  The unique numbers $c_1, dots, c_n$ are the *coordinates* of $bold(x)$ in that basis. The everyday *standard basis* is $bold(e)_1, dots, bold(e)_n$, the unit arrows along the axes; with it, the coordinates are just the components themselves.
]

A basis is a *complete, non-redundant vocabulary* for describing vectors. "Complete" because every vector can be expressed; "non-redundant" because the expression is unique — no wasted words. Changing basis re-describes the same vector in a new vocabulary. The vector — the actual block of light — has not changed; only the words we use for it have.

Why bother? Because in a *good* basis, the description is mostly zeros. The standard basis describes our smooth pixel block as eight roughly-equal middling numbers — a verbose description with no structure exposed. The DCT basis describes the *same* block as "mostly the flat pattern, plus a touch of the slowest ripple, and essentially nothing else" — a description that is one big number and a handful of near-zeros. Same block, same information, radically more compressible *words*. Compression is, to a startling degree, the search for the basis in which your data is boring.

#keyidea[
  A transform does not change the signal; it changes the *coordinates* — the words used to describe the signal. The whole point of choosing a clever basis (DCT, wavelet, KLT) is that good data, described in the right words, is mostly zeros. Zeros are free. Find the basis where your data is boring, and you have found the compression.
]

#fig([The same point described in two bases. Against the standard axes (grey) it is $(3, 2)$. Against the rotated axes $bold(b)_1, bold(b)_2$ (blue) the very same point has different coordinates — a new vocabulary for one unchanged location.],
  cetz.canvas({
    import cetz.draw: *
    // standard axes
    line((-0.4, 0), (3.8, 0), mark: (end: ">"), stroke: 0.5pt + gray)
    line((0, -0.4), (0, 3.2), mark: (end: ">"), stroke: 0.5pt + gray)
    // rotated basis (about 30 deg)
    line((0,0), (2.6, 1.5), mark: (end: ">"), stroke: 1.3pt + rgb("#0b5394"))
    line((0,0), (-1.0, 1.73), mark: (end: ">"), stroke: 1.3pt + rgb("#0b5394"))
    content((2.85, 1.55))[$bold(b)_1$]
    content((-1.15, 1.95))[$bold(b)_2$]
    // the point
    circle((3, 2), radius: 0.06, fill: rgb("#9a2617"), stroke: none)
    content((3.35, 2.2))[$P$]
    line((0,0), (3,2), stroke: (dash: "dashed", thickness: 0.6pt, paint: rgb("#9a2617")))
  }))

#gomaths("Span, linear independence, and why a basis needs exactly n vectors")[
  Two notions make "basis" precise. The *span* of a set of vectors is everything you can build from them by scaling and adding — all their linear combinations. The arrows $bold(e)_1, bold(e)_2$ span the whole plane: any point is some amount right plus some amount up. A set is *linearly independent* if none of them is a redundant combination of the others — each adds a genuinely new direction. A *basis* is a set that is both: it *spans* (reaches everything) and is *independent* (wastes nothing). In $RR^n$ that forces the count to be exactly $n$: fewer than $n$ independent vectors cannot span (some directions unreachable); more than $n$ cannot stay independent (someone is redundant). This $n$ is the *dimension* — and it is why $8$ pixels need exactly $8$ basis patterns to describe them with no loss, which is exactly how many the DCT provides.
  ]

How do you actually *find* the new coordinates? For the friendliest kind of basis — one whose vectors are mutually perpendicular and of length one, which we meet by name in the next section — it is just a pile of dot products, and it is worth doing once by hand. Take the two perpendicular unit arrows $bold(b)_1 = (1\/sqrt(2),thin 1\/sqrt(2))$ (pointing up-and-right at $45 degree$) and $bold(b)_2 = (-1\/sqrt(2),thin 1\/sqrt(2))$ (up-and-left), and the point $bold(x) = (4, 2)$. The coordinate of $bold(x)$ along $bold(b)_1$ is simply "how much of $bold(x)$ lies along $bold(b)_1$" — which is exactly the dot product:
$ c_1 = bold(x) dot bold(b)_1 = 4 dot 1/sqrt(2) + 2 dot 1/sqrt(2) = 6/sqrt(2) approx 4.24, quad c_2 = bold(x) dot bold(b)_2 = -4/sqrt(2) + 2/sqrt(2) = -2/sqrt(2) approx -1.41. $
So the same point that the standard axes call $(4, 2)$, the rotated axes call $(4.24, -1.41)$ — one point, two vocabularies. And here is the punchline that ties the whole chapter together: *stacking the basis vectors as the rows of a matrix and multiplying by $bold(x)$ produces all the new coordinates at once.* Change of basis *is* a matrix–vector product; a transform is nothing but the matrix whose rows are the basis you chose. Hold that thought into the next section, where that matrix earns the name *orthogonal* and a remarkable property comes with it.

== Orthogonal matrices: the rotations that conserve energy

Not all bases are equally pleasant. The friendliest are the *orthonormal* ones: bases whose vectors are mutually orthogonal (every pair has dot product zero — perpendicular) and each of length one (*unit* vectors). "Ortho" for perpendicular, "normal" for unit length. The standard basis is orthonormal; so, crucially, is the DCT basis. A matrix whose columns form an orthonormal basis is called an *orthogonal matrix*, and orthogonal matrices are the heroes of transform coding for one spectacular reason: *they conserve energy*.

Recall energy is squared length, $norm(bold(x))^2 = bold(x) dot bold(x)$. An orthogonal transform may *rotate or reflect* a vector — spin the arrow to point a new way — but it never stretches or shrinks it. The arrow keeps its length; only its direction (its coordinates) change. So the total energy of the eight transformed coefficients exactly equals the total energy of the eight original pixels. Nothing is created or destroyed in the transform; energy is merely *redistributed* among the new coordinates — and a good transform redistributes it into a lopsided pile we can then cheaply quantise. Let us prove it.

#theorem("Orthogonal transforms preserve length and dot products")[
  Let $Q$ be a square matrix whose columns are orthonormal, equivalently $Q^T Q = I$. Then for all vectors $bold(x), bold(y)$:
  $ (Q bold(x)) dot (Q bold(y)) = bold(x) dot bold(y), quad "and in particular" quad norm(Q bold(x)) = norm(bold(x)). $
  The transform preserves every dot product, hence every length, every angle, and the total energy.
]

#proof[
  First, a compact fact about the dot product: for any vectors $bold(u), bold(v)$, the dot product equals the matrix product $bold(u) dot bold(v) = bold(u)^T bold(v)$ (a row times a column is exactly "multiply matching slots and add"). Now compute, using this and one more rule — that transposing a product flips its order, $(A B)^T = B^T A^T$ (intuitively, "undo, then redo, in reverse": the same reversal you see when taking off shoes-then-socks undoes socks-then-shoes):
  $ (Q bold(x)) dot (Q bold(y)) = (Q bold(x))^T (Q bold(y)) = bold(x)^T Q^T Q thin bold(y) = bold(x)^T I thin bold(y) = bold(x)^T bold(y) = bold(x) dot bold(y), $
  where the middle step used the defining property $Q^T Q = I$. So every dot product survives the transform unchanged. Setting $bold(y) = bold(x)$ gives $norm(Q bold(x))^2 = (Q bold(x))dot(Q bold(x)) = bold(x) dot bold(x) = norm(bold(x))^2$, and taking square roots, $norm(Q bold(x)) = norm(bold(x))$. #h(1fr)
]

This little proof is the mathematical heart of every transform codec ever built. It guarantees three priceless things. First, *energy in equals energy out* — so the transform itself is lossless; all the loss in JPEG happens later, in quantisation, never in the transform. Second, *the inverse is trivial*: for an orthogonal matrix, $Q^(-1) = Q^T$ — to undo the transform you just multiply by the transpose, no expensive inversion needed, which is why decoders are cheap. Third, *distortion is measured fairly*: because distances are preserved, the error you make by rounding coefficients (measured in the transform domain) equals the error in the reconstructed image (measured in pixels). Round-off in the friendly domain costs exactly what it costs in the real one. That is the licence that makes rate–distortion optimisation (Chapter 41) even possible.

#misconception[The DCT compresses an image.][The DCT compresses *nothing* — it is a lossless, energy-preserving rotation that takes eight numbers to eight numbers. Not a single bit is saved by the transform itself. What it does is *rearrange* the energy so that the *next* steps — quantisation (Chapter 39) and entropy coding (Chapters 24–27) — have an easy, lopsided distribution to feed on. The transform sets the table; the coders eat the meal. Confusing the rotation with the saving is the single most common misunderstanding of how JPEG works.]

== The DCT is just a matrix

Now we can disarm the magic trick from the first page. That "fixed table of cosines" is an $8 times 8$ orthogonal matrix, the *Discrete Cosine Transform* matrix, and multiplying our pixel vector by it is nothing more exotic than the matrix–vector product we have practised all chapter: eight dot products of eight numbers each.

Where do the entries come from? Each *row* of the DCT matrix is a sampled cosine wave, at a different frequency. Row $0$ is a flat line — the constant pattern, frequency zero. Row $1$ is half a cosine wave — the slowest ripple. Row $2$ is a full wave; row $3$ faster still; and so on up to row $7$, the fastest wiggle eight samples can represent. Concretely, the entry in row $k$, column $n$ (rows and columns numbered from $0$) is

$ C_(k n) = alpha_k cos[ (pi (2n + 1) k) / 16 ], quad alpha_0 = sqrt(1/8), quad alpha_k = sqrt(2/8) "for" k >= 1, $

where the $alpha_k$ are just normalising constants chosen to make each row a *unit* vector. The point is not the exact formula — we will derive it lovingly in Chapter 38 — but the *shape* of the idea: the rows are a chosen orthonormal basis of cosine patterns, and multiplying a pixel block by this matrix *re-describes the block in terms of "how much of each cosine pattern it contains."*

#fig([The eight DCT basis patterns (rows of the $8 times 8$ matrix), from the flat constant (top) to the fastest ripple (bottom). A pixel block's DCT coefficients say "how much of each pattern is present." Smooth blocks need mostly the top few.],
  cetz.canvas({
    import cetz.draw: *
    let n = 8
    for k in range(8) {
      let yoff = (7 - k) * 0.78
      // sample a cosine of frequency k across 8 points, draw as a polyline
      let pts = ()
      for s in range(n) {
        let val = calc.cos(calc.pi * (2.0 * s + 1.0) * k / 16.0)
        pts.push((0.42 * s, yoff + 0.30 * val))
      }
      line(..pts, stroke: 1.0pt + rgb("#0b5394"))
      content((-0.7, yoff), text(size: 8pt)[$k=#k$])
    }
  }))

Read the figure top to bottom: a smooth photo block — low contrast, gentle gradient — overlaps strongly with the flat top pattern and the slow ripples below it, and barely at all with the frantic ripples at the bottom. So its DCT coordinates are big at the top and near-zero at the bottom: energy compaction, exactly the lopsided list from page one. A busy, noisy block would light up the bottom rows too — and would, rightly, compress poorly, because there is genuinely more information in noise. The transform is honest: it concentrates energy precisely to the degree the data is actually smooth.

#history[
  The DCT was introduced by Nasir Ahmed, T. Raj Natarajan, and K. R. Rao in a three-page paper, "Discrete Cosine Transform," in _IEEE Transactions on Computers_ in January 1974. Ahmed had conceived it at Kansas State University around 1972 — reportedly his grant proposal to study it was rejected as too impractical — and worked it out with Natarajan and Rao at the University of Texas at Arlington. The DCT-II they defined is the exact transform that, eighteen years later, sat at the centre of the JPEG standard (1992) and then MPEG video, and it has been multiplied against image blocks more times than almost any other matrix in history — uncountably many billions of times a second, right now, on screens everywhere. A rejected, "impractical" idea became perhaps the most-executed numerical recipe ever written.
]

#aside[
  Why cosines and not, say, the deeper-sounding *Karhunen–Loève transform* (KLT), which is provably the *optimal* energy-compacting orthogonal basis for a given source? Two reasons, both practical. The KLT's basis depends on the data's exact statistics, so you would have to compute it per image and ship it in the file — expensive and self-defeating. The DCT is a *fixed* matrix that, for the smoothly-correlated signals real photographs produce, gets startlingly close to the KLT's optimum while needing no transmission and admitting a much faster shortcut algorithm (the work it costs grows roughly like $n log n$ instead of the $n^2$ a plain matrix multiply needs — the "$O(dot)$" way of measuring an algorithm's cost is built from scratch in Chapter 14). It is the triumph of "good enough, and free, and fast" over "optimal, and costly." We meet the KLT and this trade-off properly in Chapter 38.
]

#tryit[
  This chapter has no `tinyzip` build step of its own — the project's transform module, `transform.py`, is built later, in Chapters 37--38, where the real DCT arrives. But the *machinery* it rides on is pure linear algebra, and we can write it now to watch the energy-preservation theorem come alive on real numbers: a tiny, exact, orthogonal transform and its inverse. (Treat the code below as a sketch to play with, not a project module to keep.)
  ```python
  Matrix = list[list[float]]

  def matvec(A: Matrix, x: list[float]) -> list[float]:
      return [sum(a * xi for a, xi in zip(row, x)) for row in A]

  def transpose(A: Matrix) -> Matrix:
      return [[A[i][j] for i in range(len(A))] for j in range(len(A[0]))]

  def energy(x: list[float]) -> float:
      return sum(xi * xi for xi in x)         # squared norm = energy

  # A 2x2 orthogonal matrix: a 45-degree rotation (the simplest real transform).
  r = 0.7071067811865476                      # 1 / sqrt(2)
  Q: Matrix = [[ r,  r],
               [-r,  r]]

  block = [52.0, 55.0]
  coeffs = matvec(Q, block)                   # forward transform
  back   = matvec(transpose(Q), coeffs)       # inverse = multiply by Q^T

  print(coeffs)                               # rotated coordinates
  print(back)                                 # ~ [52.0, 55.0]  — exact recovery
  print(energy(block), energy(coeffs))        # equal!  energy is conserved
  ```
  Run it: `back` recovers the input (because $Q^T Q = I$), and the two energies match to the last decimal — the orthogonality theorem, alive in code. Swap `Q` for the real $8 times 8$ cosine matrix in Chapter 38 and this exact scaffolding becomes a JPEG transform stage. A transform alone saves no bytes, exactly as the myth-box warned — but it builds the lossless, invertible rotation that the quantiser (Chapter 39) and entropy coder (Chapters 24--27) downstream turn into real savings.
]

== Decorrelation: the geometric reason it all works

We can now state, in one clean sentence, *why* transforms compress. Real signals are *correlated*: neighbouring pixels are nearly equal, consecutive audio samples drift smoothly. Correlation means the data, as an arrow in $RR^n$, does not point in random directions — it clusters along a few preferred diagonals of the space. The standard axes (one per pixel) cut across that cluster clumsily, so the energy smears across all coordinates. An orthogonal transform *rotates the axes to line up with the cluster*. In the new, aligned coordinates, a few directions carry almost all the energy and the rest carry almost none. That is decorrelation, and it is purely geometric: spin the ruler to match the grain of the wood.

#keyidea[
  Compression by transform = rotate the coordinate axes until they align with the structure in your data. Correlated data lies along a few diagonals; an orthogonal rotation makes those diagonals the new axes, piling energy onto a handful of coordinates and emptying the rest. The emptied coordinates quantise to zero almost for free. Geometry does the work; the entropy coder banks the winnings.
]

#checkpoint[
  After an orthogonal transform, you keep only the $2$ largest of $8$ coefficients and zero the other $6$. Using the energy theorem, what fraction of the original signal energy do you retain — and what does that tell you about the distortion?
][You retain exactly the energy of the $2$ kept coefficients, because total energy is the sum of squared coefficients (the transform conserves it and orthonormal coordinates do not interfere). If those $2$ hold, say, $97%$ of the energy, you have discarded only $3%$ — and since the transform preserves distances, that $3%$ is the distortion you will see in the reconstructed pixels. Energy compaction is *exactly* the promise that keeping few coefficients costs little distortion.]

== These same matrices are the whole of neural networks

One more dividend before we close, the one that pays off all of Volume IV. Open up any neural network — the kind powering the learned codecs of Chapter 57 and the language-models-as-compressors of Chapter 62 — and underneath the hype you find this chapter, stacked. A single neural-network *layer* takes an input vector $bold(x)$, multiplies it by a matrix of learned numbers $W$ (the *weights*), adds an offset vector $bold(b)$ (the *bias*), and passes each result through a simple bend:

$ bold(y) = f(W bold(x) + bold(b)). $

That $W bold(x)$ is precisely the matrix–vector product we coded on page one of this chapter — a stack of dot products, "how much does the input align with each learned pattern $W$ stores in its rows?" The bias $bold(b)$ is a vector addition. The only genuinely new ingredient is $f$, a tiny *non-linear* bend applied to each component (so the network can do more than rotate), and even that is a one-number function we will meet in Chapter 56. A "deep" network is just many such layers composed — and composing linear maps is matrix multiplication, exactly Section 12.5. The trillion-parameter models of 2025–26 are, at the level of arithmetic, this chapter run at colossal scale: vectors flowing through matrices.

#note[
  This is also why compressing a neural network (Volume IV, Chapters 63–64) *is* compressing matrices: quantising the weight matrix $W$ to $4$ bits, or factoring it into two thin matrices (low-rank / LoRA), or pruning its near-zero entries, are all operations on the objects of this chapter. And it is why the modern *attention* mechanism is, at its core, a giant batch of dot products asking "how much does this token align with that one?" — the very question Section 12.2 introduced. The vector and the matrix are the atoms of the entire AI era. You now know them.
]

#takeaways((
  [A *vector* is an ordered list of numbers and, equally, an arrow in $n$-dimensional space $RR^n$. Add and subtract them slot by slot; *scale* them by a single number; both have a clean tip-to-tail geometric meaning.],
  [The *dot product* $bold(u) dot bold(v) = sum_i u_i v_i$ returns one number measuring *alignment*: positive means "point the same way," and *zero means perpendicular (orthogonal) — utterly independent*. This one idea drives decorrelation, similarity search, and attention.],
  [*Length* (norm) is $norm(bold(v)) = sqrt(bold(v) dot bold(v))$; *energy* is squared length $sum_i v_i^2$; *distance* between vectors is *distortion*. Mean squared error is a distance.],
  [A *matrix* is a table of numbers but truly a *linear transformation*. The matrix–vector product is a *stack of dot products* (rows · input) and also a *linear combination of the columns* (input mixes the building blocks).],
  [Matrix × matrix = *composition* of transformations ("do $B$, then $A$"); it is associative but *not* commutative — order is meaning.],
  [A *basis* is a complete, non-redundant vocabulary for vectors; changing basis re-describes the same signal in new words. *Compression is finding the basis in which your data is mostly zeros.*],
  [*Orthogonal* matrices (orthonormal columns, $Q^T Q = I$) *preserve energy, length, and distance*, invert trivially as $Q^(-1) = Q^T$, and so make a *lossless, reversible* rotation. We proved it.],
  [The DCT is *just an $8 times 8$ orthogonal matrix* of cosine rows; it compresses nothing itself but *rearranges* energy into a corner so the later quantiser and entropy coder can win. Neural networks are these same matrix–vector products, stacked.],
))

== Exercises

#exercise("12.1", 1)[
  Let $bold(u) = (2, -1, 3)$ and $bold(v) = (4, 0, -2)$. Compute (a) $bold(u) + bold(v)$, (b) $3 bold(u)$, (c) $bold(u) - 2bold(v)$.
]
#solution("12.1")[
  (a) $(2{+}4, -1{+}0, 3{-}2) = (6, -1, 1)$. (b) $(6, -3, 9)$. (c) $bold(u) - 2bold(v) = (2, -1, 3) - (8, 0, -4) = (-6, -1, 7)$.
]

#exercise("12.2", 1)[
  Compute the dot product $(1, 2, 2) dot (2, -3, 1)$. Then find the length (norm) of $(1, 2, 2)$.
]
#solution("12.2")[
  Dot product: $1 dot 2 + 2 dot (-3) + 2 dot 1 = 2 - 6 + 2 = -2$. Norm: $sqrt(1^2 + 2^2 + 2^2) = sqrt(1+4+4) = sqrt(9) = 3$.
]

#exercise("12.3", 1)[
  Show that $(3, 4)$ and $(4, -3)$ are orthogonal, and confirm they have the same length. (They form an orthogonal basis of $RR^2$.)
]
#solution("12.3")[
  Dot product $3 dot 4 + 4 dot (-3) = 12 - 12 = 0$, so they are perpendicular. Each has length $sqrt(3^2+4^2) = sqrt(25) = 5 = sqrt(4^2 + (-3)^2)$. Dividing each by $5$ gives an *orthonormal* basis.
]

#exercise("12.4", 2)[
  Let $A = mat(1, 2; 0, 1)$ (a *shear*) and $bold(x) = (3, 2)$. (a) Compute $A bold(x)$. (b) In words, what did $A$ do to the vector? (c) Compute $A^2 = A A$ and describe the combined transformation.
]
#solution("12.4")[
  (a) Row 1: $1 dot 3 + 2 dot 2 = 7$; row 2: $0 dot 3 + 1 dot 2 = 2$. So $A bold(x) = (7, 2)$. (b) It left the second coordinate alone but added twice the second coordinate to the first — a horizontal *shear*, sliding points sideways by an amount proportional to their height. (c) $A^2 = mat(1, 2; 0, 1)mat(1, 2; 0, 1) = mat(1, 4; 0, 1)$ — shearing twice doubles the slide, a shear of strength $4$.
]

#exercise("12.5", 2)[
  Demonstrate that matrix multiplication is not commutative by computing both $A B$ and $B A$ for $A = mat(1, 1; 0, 1)$ and $B = mat(1, 0; 1, 1)$.
]
#solution("12.5")[
  $A B = mat(1 dot 1 + 1 dot 1, 1 dot 0 + 1 dot 1; 0 dot 1 + 1 dot 1, 0 dot 0 + 1 dot 1) = mat(2, 1; 1, 1)$. $B A = mat(1 dot 1 + 0 dot 0, 1 dot 1 + 0 dot 1; 1 dot 1 + 1 dot 0, 1 dot 1 + 1 dot 1) = mat(1, 1; 1, 2)$. Since $mat(2,1;1,1) != mat(1,1;1,2)$, order matters: $A B != B A$.
]

#exercise("12.6", 2)[
  The $2 times 2$ rotation-by-$45 degree$ matrix is $Q = mat(r, -r; r, r)$ with $r = 1/sqrt(2) approx 0.707$. (a) Verify its columns are orthonormal (each unit length, dot product zero). (b) Apply $Q$ to $bold(x) = (1, 1)$ and confirm the output has the same length as the input.
]
#solution("12.6")[
  (a) Column 1 is $(r, r)$, length $sqrt(r^2 + r^2) = sqrt(2 r^2) = sqrt(2 dot 1/2) = 1$. Column 2 is $(-r, r)$, length $1$ likewise. Their dot product: $r dot (-r) + r dot r = -r^2 + r^2 = 0$. Orthonormal. (b) $Q bold(x) = (r dot 1 - r dot 1, thin r dot 1 + r dot 1) = (0, 2r) = (0, sqrt(2))$. Length $sqrt(0 + 2) = sqrt(2)$, which equals $norm((1,1)) = sqrt(2)$. Energy conserved, as the theorem promised.
]

#exercise("12.7", 2)[
  An orthogonal transform sends a block to coefficients $(10, 4, 2, 1, 0, 0, 0, 0)$. (a) What is the total energy? (b) If you keep only the first three coefficients and zero the rest, what fraction of the energy do you retain? (c) Why does this *not* depend on which orthogonal transform was used?
]
#solution("12.7")[
  (a) Energy $= 10^2 + 4^2 + 2^2 + 1^2 = 100 + 16 + 4 + 1 = 121$. (b) Kept energy $= 100 + 16 + 4 = 120$, fraction $120/121 approx 99.2%$. (c) Because *every* orthogonal transform conserves total energy ($Q^T Q = I$), and energy is the sum of squared coefficients regardless of the basis — so the retained-energy fraction is a property of the coefficient list itself, not of which energy-preserving rotation produced it.
]

#exercise("12.8", 3)[
  Prove that if $bold(u)$ and $bold(v)$ are orthogonal ($bold(u) dot bold(v) = 0$), then $norm(bold(u) + bold(v))^2 = norm(bold(u))^2 + norm(bold(v))^2$. (This is the Pythagorean theorem for vectors — and the reason orthonormal coordinates store energy without interference.)
]
#solution("12.8")[
  Expand the squared norm as a dot product and use that the dot product distributes over addition (it is *bilinear*): $norm(bold(u)+bold(v))^2 = (bold(u)+bold(v))dot(bold(u)+bold(v)) = bold(u)dot bold(u) + bold(u)dot bold(v) + bold(v)dot bold(u) + bold(v)dot bold(v)$. The two cross terms are each $bold(u) dot bold(v) = 0$ by orthogonality, leaving $bold(u)dot bold(u) + bold(v)dot bold(v) = norm(bold(u))^2 + norm(bold(v))^2$. Because the cross terms vanish, energy along orthogonal directions simply adds — no interference — which is exactly why a codec can store and discard orthonormal coefficients independently.
]

#exercise("12.9", 3)[
  *Coding.* Using only Python lists (no libraries), write `matvec(A, x)` and a function `is_orthonormal(Q)` that returns `True` when the columns of a square matrix `Q` are mutually orthonormal (each pairwise dot product is $0$, each self dot product is $1$), allowing a small tolerance. Test it on the $45 degree$ rotation matrix.
]
#solution("12.9")[
  ```python
  def dot(u, v): return sum(a * b for a, b in zip(u, v))
  def matvec(A, x): return [dot(row, x) for row in A]

  def column(Q, j): return [Q[i][j] for i in range(len(Q))]

  def is_orthonormal(Q, tol=1e-9):
      n = len(Q)
      for i in range(n):
          for j in range(n):
              d = dot(column(Q, i), column(Q, j))
              target = 1.0 if i == j else 0.0
              if abs(d - target) > tol:
                  return False
      return True

  r = 0.7071067811865476
  Q = [[r, -r], [r, r]]
  print(is_orthonormal(Q))    # True
  ```
  The double loop checks every pair of columns: diagonal entries (a column with itself) must be $1$ (unit length squared), off-diagonal entries must be $0$ (perpendicular). The `tol` guards against floating-point dust. This is exactly the test that certifies a transform matrix is energy-preserving.
]

#exercise("12.10", 3)[
  Explain, in your own words and with a small numeric sketch, why describing a *smooth* signal in the DCT basis yields mostly small coefficients, while describing pure *noise* yields coefficients of all similar size. Connect your answer to (a) energy conservation and (b) why noise resists compression.
]
#solution("12.10")[
  A smooth signal — say $(50, 51, 52, 53)$ — is almost entirely "flatness plus a gentle trend," so it aligns strongly with the low-frequency DCT rows (the flat and slow-ripple patterns) and barely at all with the high-frequency rows. Its coefficients therefore come out large at the low end and near zero at the high end: the energy, which orthogonality conserves in total, piles into a few coordinates. Pure noise, by contrast, has no preferred direction — it aligns equally (and weakly) with *every* basis pattern, smooth or wiggly — so the conserved energy spreads evenly across all coefficients, none small enough to drop. (a) In both cases the *total* energy is unchanged by the transform; only its *distribution* differs — concentrated for smooth data, uniform for noise. (b) Compression by transform works only when energy concentrates; noise refuses to concentrate in any fixed basis, which is the geometric face of the deeper truth (Chapters 8 and 18) that random data is incompressible.
]

== Further reading

- Gilbert Strang, _Introduction to Linear Algebra_ (6th ed., 2023) and his MIT OpenCourseWare lectures — the gold-standard friendly, geometry-first treatment of everything in this chapter; start with the lectures on the four fundamental subspaces and orthogonality.
- N. Ahmed, T. Natarajan, and K. R. Rao, "Discrete Cosine Transform," #link("https://doi.org/10.1109/T-C.1974.223784")[_IEEE Transactions on Computers_, vol. C-23, no. 1, pp. 90–93, Jan. 1974] — the original three-page paper; remarkably readable, and the matrix this chapter demystified.
- Gilbert Strang, "The Discrete Cosine Transform," #link("https://doi.org/10.1137/S0036144598336745")[_SIAM Review_, vol. 41, no. 1, pp. 135–147, 1999] — a beautiful linear-algebra-first account of why the DCT's cosines are the eigenvectors of a simple tridiagonal matrix, bridging exactly this chapter to Chapter 38.
- Sheldon Axler, _Linear Algebra Done Right_ (4th ed., 2024) — for the reader who wants the abstract, basis-and-transformation view developed rigorously; harder, but the cleanest conceptual treatment of orthogonality and inner products.

#bridge[
  We can now turn lists of numbers into geometry, rotate them with energy-preserving matrices, and re-describe a signal in any vocabulary we please — the exact machinery the DCT (Chapter 38), wavelets (Chapter 43), and every neural layer (Volume IV) are built from. But we have leaned on one word without ever measuring it: *information*. We have said correlated data is compressible and noise is not, that a rare event "carries more information" than a common one — but how *much* more, in what units, and where is the hard floor below which no transform, no matrix, no cleverness can take us? For that we need the final foundation, and the most beautiful idea in the book. Next, Chapter 13 shows how a computer actually stores all these numbers as bits and bytes — and then Volume I culminates in Chapter 18, where Claude Shannon, in 1948, turns the vague word "information" into a precise number measured in bits, and tells us exactly how far compression can ever go.
]
