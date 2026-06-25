#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026 Edition",
  volume: "Volume II - Classical Lossless Compression",
)

#pagebreak(weak: true)
#include "chapters/24-entropy-coding-i-shannon-fano-and-huffman.typ"
#pagebreak(weak: true)
#include "chapters/25-integer-and-universal-codes.typ"
#pagebreak(weak: true)
#include "chapters/26-arithmetic-coding.typ"
#pagebreak(weak: true)
#include "chapters/27-asymmetric-numeral-systems-ans.typ"
#pagebreak(weak: true)
#include "chapters/28-dictionary-coding-i-lz77-and-lz78.typ"
#pagebreak(weak: true)
#include "chapters/29-dictionary-coding-ii-lzw-and-the-patent-wars.typ"
#pagebreak(weak: true)
#include "chapters/30-deflate-zlib-gzip-and-png.typ"
#pagebreak(weak: true)
#include "chapters/31-lzma-and-the-high-ratio-dictionary-coders.typ"
#pagebreak(weak: true)
#include "chapters/32-the-modern-frontier-zstandard-brotli-lz4-snapp.typ"
#pagebreak(weak: true)
#include "chapters/33-statistical-modeling-ppm-and-context-mixing.typ"
#pagebreak(weak: true)
#include "chapters/34-the-ratio-champions-paq-zpaq-and-cmix.typ"
#pagebreak(weak: true)
#include "chapters/35-the-burrows-wheeler-transform-and-bzip2.typ"
#pagebreak(weak: true)
#include "chapters/36-benchmarks-corpora-and-the-hutter-prize.typ"

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
