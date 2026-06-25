// bookindex.typ - automatic back-of-book index for The Compression Book.
// A show rule (applied to the body by lib.typ) marks every occurrence of a
// curated term; make-index() collects their displayed page numbers and renders
// an alphabetical, two-column, hyperlinked index.

#let _idxpat = regex("\\b(Discrete\\s+Fourier\\s+Transform|Discrete\\s+Wavelet\\s+Transform|Minimum\\s+Description\\s+Length|Burrows[-–]Wheeler\\s+Transform|Discrete\\s+Cosine\\s+Transform|Kraft[-–]McMillan\\s+inequality|Blahut[-–]Arimoto\\s+algorithm|Content[-–]defined\\s+chunking|Karhunen[-–]Loève\\s+transform|Linear\\s+predictive\\s+coding|Nyquist[-–]Shannon\\s+sampling|Variational\\s+autoencoder|Knowledge\\s+distillation|Psychoacoustic\\s+masking|HTTP\\s+content[-–]encoding|Kolmogorov\\s+complexity|Learned\\s+entropy\\s+model|LLM\\+arithmetic\\s+coding|Product\\s+quantization|Dictionary\\s+encoding|Fractal\\s+compression|Lloyd[-–]Max\\s+quantizer|Motion\\s+compensation|Shannon[-–]Fano\\s+coding|Vector\\s+quantization|Golomb[-–]Rice\\s+coding|Per[-–]title\\s+encoding|Arithmetic\\s+coding|Canonical\\s+Huffman|Adaptive\\s+Huffman|Ballé\\s+hyperprior|Interleaved\\s+rANS|Levinson[-–]Durbin|Roaring\\s+bitmaps|Shannon\\s+entropy|Abraham\\s+Lempel|Big[-–]O\\s+notation|Context\\s+mixing|Delta[-–]of[-–]delta|Huffman\\s+coding|Lagrangian\\s+RDO|Lottery\\s+Ticket|LBG\\s+algorithm|Move[-–]to[-–]front|BitNet\\s+b1\\.58|DeepSeek\\s+MLA|DNA\\s+Fountain|Hutter\\s+Prize|Modified\\s+DCT|Range\\s+coding|Reed[-–]Solomon|Stream\\s+VByte|Autoencoder|Brandenburg|Elias\\s+gamma|Polar\\s+codes|Residual\\s+VQ|SoundStream|Yann\\s+Collet|Exp[-–]Golomb|Kolmogorov|Morse\\s+code|Solomonoff|TurboQuant|Jacob\\s+Ziv|JPEG\\s+2000|Phil\\s+Katz|Zstandard|FM[-–]index|Fountain|Levinson|LT\\s+codes|Rissanen|BD[-–]rate|Bellard|Burrows|Chaitin|DEFLATE|EnCodec|Gorilla|Hartley|Huffman|JPEG\\s+XL|JPEG[-–]LS|Mahoney|Nyquist|Parquet|Pruning|Shannon|Wheeler|Brotli|bsdiff|Collet|Durbin|Golomb|Hutter|Lempel|MPEG[-–]2|nvCOMP|Snappy|ts_zip|VCDIFF|Vitter|Vorbis|Witten|ACELP|Ahmed|Balle|Blosc|CABAC|delta|EBCOT|Elias|H\\.262|H\\.264|H\\.265|H\\.266|HiFiC|PerCo|Welch|AIXI|AVIF|CELP|CELT|cmix|COIN|CRAM|DCVC|DPCM|Duda|Fano|FLAC|GPTQ|HEVC|JPEG|LDPC|LoRA|LZ77|LZ78|LZMA|LZSS|nncp|NNVC|Opus|rANS|SILK|SSIM|tANS|VMAF|WebP|ZPAQ|AAC|AV1|AV2|AVC|AWQ|ECM|FPC|GIF|INR|LZ4|LZW|MP3|ORC|PAQ|PNG|PPM|QOI|VP9|VVC|zfp|Ziv|SZ)\\b")

// the show-rule body lib.typ applies before the main body:
#let _index-mark(it) = { [#metadata(it.text.replace("\u{2013}", "-"))<bookidx>]; it }

#let make-index(title: "Index", accent: rgb("#0b5394")) = context {
  let start = counter(page).at(here()).first()
  let by = (:)
  for h in query(<bookidx>) {
    let key = h.value
    let pg = counter(page).at(h.location()).first()
    if pg >= start { continue }            // skip the index's own pages
    if key not in by { by.insert(key, ()) }
    if by.at(key).find(e => e.at(0) == pg) == none { by.at(key).push((pg, h.location())) }
  }
  pagebreak(weak: true)
  heading(level: 1, numbering: none)[#title]
  set text(size: 9pt)
  set par(first-line-indent: 0pt, justify: false, leading: 0.5em)
  columns(2, gutter: 14pt, {
    let cur = ""
    for k in by.keys().sorted(key: x => lower(x)) {
      let f = upper(k.clusters().at(0))
      if f != cur and f.match(regex("[A-Z]")) != none {
        cur = f
        block(above: 7pt, below: 2pt, text(weight: "bold", size: 11pt, fill: accent)[#f])
      }
      let refs = by.at(k).sorted(key: e => e.at(0))
      block(below: 1pt)[#k #h(3pt) #text(fill: accent.darken(5%))[#refs.map(e => link(e.at(1))[#str(e.at(0))]).join(", ")]]
    }
  })
}
