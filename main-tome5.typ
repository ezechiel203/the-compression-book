#import "lib.typ": *

#show: book.with(
  title: "The Compression Book",
  subtitle: "A Complete History and Technical Treatise on Data Compression",
  author: "Alexandre Betry, M.D., M.Sc. C.S.",
  date: "June 2026 Edition",
  volume: "Tome V - Audio and Video Compression",
)

#counter(heading).update(45)   // continuous chapter numbers across the set

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

#pagebreak(weak: true)
#solutions-appendix()

#make-index()
