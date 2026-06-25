#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026 Edition",
  volume: "Tome VI - The Neural and AI Era",
)

#counter(heading).update(55)   // continuous chapter numbers across the set

#pagebreak(weak: true)
#include "chapters/56-a-machine-learning-primer-for-compression.typ"
#pagebreak(weak: true)
#include "chapters/57-learned-image-compression-autoencoders-and-hyp.typ"
#pagebreak(weak: true)
#include "chapters/58-generative-and-perceptual-codecs.typ"
#pagebreak(weak: true)
#include "chapters/59-learned-video-and-implicit-neural-representati.typ"
#pagebreak(weak: true)
#include "chapters/60-neural-audio-codecs-as-tokenizers.typ"
#pagebreak(weak: true)
#include "chapters/61-compression-as-intelligence-the-theory.typ"
#pagebreak(weak: true)
#include "chapters/62-large-language-models-as-compressors.typ"
#pagebreak(weak: true)
#include "chapters/63-model-compression-i-quantization.typ"
#pagebreak(weak: true)
#include "chapters/64-model-compression-ii-pruning-distillation-low-.typ"
#pagebreak(weak: true)
#include "chapters/65-kv-cache-context-and-embedding-compression.typ"

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
