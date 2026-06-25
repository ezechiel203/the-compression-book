#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026 Edition",
  volume: "Tome I - Foundations: Mathematics, Logic, and Programming",
)

#counter(heading).update(0)   // continuous chapter numbers across the set

#pagebreak(weak: true)
#include "chapters/01-what-is-compression.typ"
#pagebreak(weak: true)
#include "chapters/02-a-guided-history-of-the-field.typ"
#pagebreak(weak: true)
#include "chapters/03-information-data-and-symbols.typ"
#pagebreak(weak: true)
#include "chapters/04-numbers-and-number-systems.typ"
#pagebreak(weak: true)
#include "chapters/05-logic-and-boolean-algebra.typ"
#pagebreak(weak: true)
#include "chapters/06-sets-functions-and-relations.typ"
#pagebreak(weak: true)
#include "chapters/07-exponents-logarithms-and-growth.typ"
#pagebreak(weak: true)
#include "chapters/08-counting-and-combinatorics.typ"
#pagebreak(weak: true)
#include "chapters/09-probability-from-scratch.typ"
#pagebreak(weak: true)
#include "chapters/10-random-variables-expectation-and-variance.typ"
#pagebreak(weak: true)
#include "chapters/11-sequences-sums-and-a-gentle-calculus.typ"
#pagebreak(weak: true)
#include "chapters/12-vectors-matrices-and-linear-transformations.typ"
#pagebreak(weak: true)
#include "chapters/13-how-computers-represent-things.typ"
#pagebreak(weak: true)
#include "chapters/14-algorithms-data-structures-and-complexity.typ"
#pagebreak(weak: true)
#include "chapters/15-a-python-primer-i-values-types-and-control-flo.typ"
#pagebreak(weak: true)
#include "chapters/16-a-python-primer-ii-data-structures-functions-a.typ"
#pagebreak(weak: true)
#include "chapters/17-a-python-primer-iii-bytes-bits-files-and-binar.typ"

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
