#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026 Edition",
  volume: "Tome II - Information Theory and Entropy Coding",
)

#counter(heading).update(17)   // continuous chapter numbers across the set

#pagebreak(weak: true)
#include "chapters/18-shannon-and-the-birth-of-information-theory.typ"
#pagebreak(weak: true)
#include "chapters/19-the-source-coding-theorem.typ"
#pagebreak(weak: true)
#include "chapters/20-mutual-information-channels-and-the-noisy-chan.typ"
#pagebreak(weak: true)
#include "chapters/21-rate-distortion-the-theory-of-lossy-compressio.typ"
#pagebreak(weak: true)
#include "chapters/22-kolmogorov-complexity-and-algorithmic-informat.typ"
#pagebreak(weak: true)
#include "chapters/23-compression-prediction-learning.typ"
#pagebreak(weak: true)
#include "chapters/24-entropy-coding-i-shannon-fano-and-huffman.typ"
#pagebreak(weak: true)
#include "chapters/25-integer-and-universal-codes.typ"
#pagebreak(weak: true)
#include "chapters/26-arithmetic-coding.typ"
#pagebreak(weak: true)
#include "chapters/27-asymmetric-numeral-systems-ans.typ"

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
