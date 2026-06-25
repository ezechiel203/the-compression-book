#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026 Edition",
  volume: "Tome IV - Transforms and Image Compression",
)

#counter(heading).update(36)   // continuous chapter numbers across the set

#pagebreak(weak: true)
#include "chapters/37-signals-sampling-and-the-frequency-domain.typ"
#pagebreak(weak: true)
#include "chapters/38-transforms-for-compression-klt-dct-wavelets-md.typ"
#pagebreak(weak: true)
#include "chapters/39-quantization-from-scalar-to-vector.typ"
#pagebreak(weak: true)
#include "chapters/40-prediction-and-differential-coding.typ"
#pagebreak(weak: true)
#include "chapters/41-rate-distortion-optimization-in-practice.typ"
#pagebreak(weak: true)
#include "chapters/42-jpeg-anatomy-of-the-world-s-image-codec.typ"
#pagebreak(weak: true)
#include "chapters/43-jpeg-2000-and-the-wavelet-promise.typ"
#pagebreak(weak: true)
#include "chapters/44-lossless-and-simple-image-formats-gif-png-qoi.typ"
#pagebreak(weak: true)
#include "chapters/45-the-modern-image-wars-webp-heic-avif-jpeg-xl.typ"

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
