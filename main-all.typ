#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026, Complete Edition (all five volumes)",
  volume: "Complete Edition · Volumes I–V",
  tocdepth: 1,
)

#partdivider("I", [Foundations: The Language of Information])
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
#partdivider("II", [Classical Lossless Compression])
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
#partdivider("III", [Lossy and Perceptual Media Compression])
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
#include "chapters/46-psychoacoustics-compressing-for-the-ear.typ"
#pagebreak(weak: true)
#include "chapters/47-mp3-and-the-mpeg-audio-lineage.typ"
#pagebreak(weak: true)
#include "chapters/48-aac-vorbis-and-modern-general-audio.typ"
#pagebreak(weak: true)
#include "chapters/49-opus-one-codec-to-rule-real-time-audio.typ"
#pagebreak(weak: true)
#include "chapters/50-lossless-and-speech-coding.typ"
#pagebreak(weak: true)
#include "chapters/51-the-hybrid-video-codec-motion-prediction-trans.typ"
#pagebreak(weak: true)
#include "chapters/52-h-261-to-h-264-avc-the-workhorse-era.typ"
#pagebreak(weak: true)
#include "chapters/53-hevc-and-vvc-more-compression-more-patents.typ"
#pagebreak(weak: true)
#include "chapters/54-the-open-codecs-vp8-vp9-av1-av2.typ"
#pagebreak(weak: true)
#include "chapters/55-the-successor-frontier-and-encoding-at-scale.typ"
#partdivider("IV", [The Neural and AI Era])
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
#partdivider("V", [Specialized Domains, Systems, and Reflections])
#pagebreak(weak: true)
#include "chapters/66-scientific-and-floating-point-compression.typ"
#pagebreak(weak: true)
#include "chapters/67-columnar-and-database-compression.typ"
#pagebreak(weak: true)
#include "chapters/68-time-series-and-iot-compression.typ"
#pagebreak(weak: true)
#include "chapters/69-genomic-and-biological-sequence-compression.typ"
#pagebreak(weak: true)
#include "chapters/70-dna-data-storage-and-constrained-coding.typ"
#pagebreak(weak: true)
#include "chapters/71-delta-diff-and-deduplication.typ"
#pagebreak(weak: true)
#include "chapters/72-the-error-correction-boundary.typ"
#pagebreak(weak: true)
#include "chapters/73-engineering-fast-codecs.typ"
#pagebreak(weak: true)
#include "chapters/74-compression-in-the-stack.typ"
#pagebreak(weak: true)
#include "chapters/75-measuring-compression-metrics-and-benchmarks.typ"
#pagebreak(weak: true)
#include "chapters/76-a-people-s-history-of-compression.typ"
#pagebreak(weak: true)
#include "chapters/77-patents-standards-and-the-politics-of-formats.typ"
#pagebreak(weak: true)
#include "chapters/78-dead-ends-failures-and-cautionary-tales.typ"
#pagebreak(weak: true)
#include "chapters/79-the-state-of-the-field-june-2026.typ"
#pagebreak(weak: true)
#include "chapters/80-open-problems-and-grand-challenges.typ"
#pagebreak(weak: true)
#include "chapters/81-the-future-of-compression.typ"

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
