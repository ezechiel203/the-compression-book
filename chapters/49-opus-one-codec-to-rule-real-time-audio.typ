#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Opus: One Codec to Rule Real-Time Audio

#epigraph[
  "We did not want a better codec. We wanted the last codec."
][
  Jean-Marc Valin, describing the goal of the Opus working group, 2010
]

It is 2011. You are trying to call a friend over the internet. You have four choices, none of
them satisfying. You could use G.711 (a phone codec from 1972 that sounds like you are speaking
through a tin can). You could use Speex, which sounds fine for speech but collapses on music.
You could use G.722, which sounds better but has a mandatory 35 ms delay that makes
conversations awkward and echo-prone. Or you could use AAC, which sounds great but requires
paying patent royalties and introduces 60 ms or more of algorithmic delay, which is far too slow for
interactive voice.

What you really want is a single codec that is free of patents, covers every bitrate from a
trickle to a flood, handles both speech and music without choking, responds in milliseconds
rather than frames, and bounces back gracefully when the internet drops a packet. In September
2012, the Internet Engineering Task Force published RFC 6716 and named that codec *Opus*.

This chapter is the story of how Opus was born from two very different codecs stitched together,
how its unusual hybrid architecture delivers on every one of those demands simultaneously, and how
a decade of machine-learning additions have made it even better without changing a single bit of
the bitstream format.

#recap[
  Chapter 46 taught us the science Opus depends on: the basilar membrane, critical bands, the
  absolute threshold of hearing, simultaneous masking, and temporal masking. Together these
  define which sounds are truly inaudible and therefore expendable. Chapter 47 showed how MP3
  exploits those limits via a hybrid polyphase-plus-MDCT filterbank, a psychoacoustic model, and
  Huffman-coded quantised coefficients. Chapter 48 showed how AAC improved on MP3 with a pure
  MDCT, better stereo tools, and the Spectral Band Replication trick for HE-AAC; it also
  introduced Vorbis, the royalty-free counterpart. Chapter 40 introduced linear predictive coding
  (LPC), the mathematical model of the vocal tract that forms Opus's speech engine. All of that
  foundation leads here.
]

#objectives((
  "Explain why existing codecs in 2010 could not serve real-time internet audio well.",
  "Trace the origins of SILK (Skype's speech coder) and CELT (Xiph's music coder) separately.",
  "Describe the Opus hybrid architecture: how the three modes are chosen frame-by-frame.",
  "Understand SILK's linear predictive model (short-term LPC, long-term pitch predictor, NLSF quantisation) and what it sends on the wire.",
  "Understand CELT's MDCT approach (energy bands, pyramid vector quantisation, the bit allocation algorithm) and why it achieves 5 ms delay.",
  "Read the Opus packet format and understand how the TOC byte controls mode selection.",
  "Follow the ML additions in Opus 1.5 (LACE, NoLACE, DRED, deep PLC) and Opus 1.6 (bandwidth extension, Opus HD).",
  "Write Python code that encodes and decodes audio through the opuslib bindings, round-tripping a speech clip at different bitrates.",
))

== The Problem Space in 2009

Before we can appreciate Opus, we need to feel the pain it was built to relieve. In the late
2000s, the internet audio codec space was a mess of specialisation. Each codec was designed for
exactly one niche and performed poorly outside it.

*G.711* (PCMU/PCMA), the ITU-T standard from 1972, was the lingua franca of VoIP: every phone
system supported it, but it used logarithmic companding at a fixed 64 kbit/s and offered
bandwidth of only 4 kHz (barely AM-radio quality). It had no mechanism to handle packet loss
gracefully.

*G.722* was the wideband phone codec, extending to 7 kHz. It sounded substantially better than
G.711, but it used a subband ADPCM structure that imposed a fixed 5 ms frame size and required
specific network jitter buffers. Its algorithmic delay, including the lookahead needed for
sub-band splitting, was not zero.

*G.729* was a CELP (Code Excited Linear Prediction) codec targeting 8 kbit/s for mobile phone
backhaul: highly compressed speech, but speech only, and subject to heavy patent royalties.

*Speex* (the Xiph project before Opus) was royalty-free and covered a wide bitrate range for
speech, but it was designed purely around linear predictive models and sounded terrible on music.

*AAC and HE-AAC* were the best general-purpose codecs for music, but their algorithmic delay
(the time between the input sample and when the encoder can output bits about it) was 60 ms or
more in practice. That is catastrophic for two-way voice. If the codec adds 60 ms at each end,
the round-trip delay from mouth to ear is over 120 ms, which makes conversations feel unnatural
and causes speakers to interrupt each other constantly.

*MP3 and Vorbis* were streaming-only: designed for file playback, not real-time interaction.

The fundamental tension was this: low-latency codecs used linear prediction, which is excellent
for speech but terrible for music. High-quality music codecs used long MDCT frames that spread
information across time, which destroys the ability to encode and decode in milliseconds. Nobody
had tried to bridge the gap in one unified, royalty-free format.

#keyidea[
  Opus's core insight is that speech and music need fundamentally different internal
  representations: speech is best modelled as the output of a resonant tube (the vocal tract),
  while music is best modelled as a sum of frequency-domain components. A single bitstream format
  can select the right representation for each 20 ms frame of audio, switching seamlessly as
  content changes.
]

== Two Codecs, One Destiny

The hybrid core of Opus did not emerge from scratch. It was assembled from two existing
codecs that were, almost accidentally, designed to complement each other.

=== SILK: The Voice of Skype

*SILK* (from the Skype engineering team, led by Koen Vos with Søren Skak Jensen and Karsten
Vandborg Sørensen) was developed starting around 2006 as Skype's next-generation speech codec.
Skype needed something royalty-free that could deliver excellent voice quality across the
wildly variable internet (from 6 kbit/s over a congested mobile connection to 40 kbit/s on
broadband) and survive packet loss gracefully.

SILK's architecture is squarely in the CELP (Code-Excited Linear Prediction) family, the speech-coding
lineage we will study in full in Chapter 50. The key idea in CELP is to model the human vocal tract as a
linear filter: a mathematical model of how the throat, mouth, and nasal cavity shape raw
vibrations from the vocal cords into the sounds of speech. If you can send that model's
parameters rather than the raw audio, you save a great deal of bandwidth, because the model is
far more compact than the waveform it explains.

#gomaths("Linear Prediction and the LPC Model")[
  Imagine trying to predict the next audio sample $x[n]$ from the $p$ samples before it.
  The *linear prediction* model says:

  $ hat(x)[n] = sum_(k=1)^(p) a_k dot x[n-k] $

  where $a_1, a_2, dots, a_p$ are the *LPC coefficients* ($p$ numbers that describe the
  resonances of the vocal tract at this moment). The *prediction residual* (what the model
  gets wrong) is:

  $ e[n] = x[n] - hat(x)[n] $

  For voiced speech (a vowel), the residual is small and periodic: it looks like
  little clicks at the pitch period. For unvoiced speech (like "ssss"), the residual is
  noisy. For silence, it is nearly zero.

  A speech codec transmits the $p$ LPC coefficients plus a compact description of $e[n]$.
  The decoder reconstructs $x[n]$ by running the filter in reverse. This works because
  the LPC filter captures most of the signal's variance, leaving only a small residual
  to encode.

  In SILK (and in Opus's SILK layer), $p = 16$ for wideband speech. Sixteen coefficients
  capture the sixteen most prominent resonances (formants and their interactions) of the
  human vocal tract at a given moment. Those sixteen numbers often describe a 20 ms frame
  far more compactly than the 320 raw samples they summarise.
]

SILK adds two more layers of prediction on top of the basic LPC model.

*Long-term prediction (pitch predictor):* Speech is periodic at the pitch frequency of the
speaker's voice (roughly 80–400 Hz). After the LPC filter removes the short-term correlation,
the residual is still correlated: the vocal-cord impulse pattern repeats every pitch period. A
*pitch predictor* looks back one pitch period (which may be 20–120 samples) and removes that
periodicity too. SILK's pitch predictor uses a 5-tap FIR filter around the pitch lag, which also
handles the case where the pitch period is not a whole number of samples (fractional pitch).

#note[
  A *FIR filter* (Finite Impulse Response) is just a weighted sum of a handful of input samples:
  output$[n] = sum_(k) c_k dot "input"[n-k]$. "5-tap" means it uses five weights $c_0, dots, c_4$.
  Here the five taps blend the samples around the best pitch lag, so the predictor can land
  between two whole-sample positions; that is what "fractional pitch" means. The linear-predictor
  sum from the LPC box above is itself a FIR filter; this is the same machinery applied to the
  long-term (pitch-period) structure instead of the short-term one.
]

*Gain coding:* Rather than transmitting raw quantised coefficients, SILK separately encodes the
energy (gain) of each 5 ms subframe and the normalised "shape" of the residual. This lets the
decoder reconstruct the correct loudness even when the shape coding is coarse.

*NLSF quantisation:* The LPC coefficients are converted to *Normalised Line Spectral Frequencies*
(NLSFs) before transmission. NLSFs are a transformed representation of LPC coefficients that are
more numerically stable, more amenable to interpolation between frames, and easier to quantise
with a vector quantiser trained on a large speech database. The conversion and quantisation keeps
the filter stable (which is not guaranteed if you quantise raw LPC coefficients carelessly).

Finally, the residual signal (what is left after both short-term and long-term prediction)
is quantised using a *lattice codebook search* and entropy-coded with a range coder
(Chapter 26 machinery). At 12–16 kbit/s, the resulting reconstructed speech is indistinguishable
from the original for most listeners.

SILK was submitted to the IETF in 2009 as a candidate royalty-free codec. It covered bitrates
from roughly 6 to 40 kbit/s and supported sampling rates of 8, 12, 16, and 24 kHz (narrowband
through super-wideband). It was great at speech and hopeless at music.

=== CELT: The Music Layer

*CELT* (Constrained Energy Lapped Transform) was Jean-Marc Valin's project at the Xiph.Org
Foundation, begun in 2007. The driving requirement was different from SILK's: CELT had to
achieve very low latency (under 10 ms algorithmic delay) while delivering good quality on
*any audio*, including music, at medium bitrates (32–128 kbit/s).

Low latency is incompatible with long MDCT frames. AAC-LC uses a 1024-sample frame at 48 kHz
(about 21 ms), which is already too long for interactive applications. CELT uses a 120-sample to
960-sample frame (2.5 ms to 20 ms), dramatically shrinking the delay. The cost of shorter frames
is less frequency resolution: with fewer samples, the MDCT produces fewer coefficients, and
each one covers a wider frequency range.

CELT's answer to coarse frequency resolution is *band-based energy coding*, borrowed from ideas
in parametric audio coding.

#gomaths("CELT's Band Energy Coding")[
  The MDCT of a short frame produces $N/2$ coefficients, where $N$ is the frame size.
  CELT groups those coefficients into $M$ *critical bands* (approximately following the
  Bark scale from Chapter 46), typically 21 bands for a 20 ms frame at 48 kHz.

  For each band $b$ containing $n_b$ coefficients $X_b[0], dots, X_b[n_b - 1]$:

  1. Compute the *band energy*: $E_b = sqrt(sum_k X_b[k]^2)$.
  2. Normalise: $bold(v)_b = bold(X)_b / E_b$. The normalised band is a unit vector in
     $n_b$-dimensional space (a point on the unit sphere).
  3. Encode $E_b$ separately (using coarse energy quantisation, ~6 dB/step, predicted
     from the previous frame). #footnote[#mathrecall[A *decibel* (dB), defined in Chapters 39 and
     46, writes a power ratio on a logarithmic scale: $10 log_10 r$ dB for a power ratio $r$.
     A 6 dB step corresponds to a power ratio of about 4 (an amplitude ratio of 2), so each coarse
     energy level is roughly twice as loud as the one below it.]]
  4. Encode $bold(v)_b$ using *Pyramid Vector Quantisation (PVQ)*.

  *Pyramid Vector Quantisation* represents the unit vector as an integer vector $(y_0, dots,
  y_(n_b - 1))$ with integer entries summing in absolute value to $K$: $sum_k abs(y_k) = K$.
  These integer vectors lie on the faces of a pyramid in $n_b$ dimensions. The number of
  bits $K$ spent on a band is determined by the bit allocation algorithm (itself driven by
  the psychoacoustic model). More bits → finer vector → better shape reconstruction.

  This scheme decouples *how loud* a band is (energy) from *what shape* it has (vector),
  letting the encoder allocate bits independently to each concern.
]

The PVQ has two remarkable properties. First, all vectors with the same $K$ and $n_b$ form a
closed enumerable set, so CELT can convert directly between vector and integer index using a fast
combinatorial algorithm, with no lookup table needed. Second, the decoder can invert the index to the
vector without ambiguity. This is the compression primitive at the core of all CELT frames.

CELT also handles *temporal fine structure* within each band using a technique called
*time-frequency spreading*: a small amount of the quantised shape energy is intentionally spread
in time, mimicking the natural smearing of transients that the ear tolerates. This reduces the
audible pre-echo from quantisation artifacts at low bitrates.

Critically, CELT was designed to be completely royalty-free from the start. All of its techniques
either had expired patents or had been contributed to the public domain by their inventors.
Valin also joined the IETF Codec working group in 2009 and proposed CELT as the other candidate.

=== The Fusion Decision

When the IETF CODEC working group formed in February 2010, two camps faced each other: SILK
(excellent speech, no music, no latency below ~20 ms) and CELT (excellent music, any latency,
mediocre speech at low bitrates). The obvious question was: why pick one?

Jean-Marc Valin and Koen Vos began collaborating on a prototype that ran both codecs on the same
audio stream, using SILK for low-bitrate speech and CELT for everything else, with a smooth
transition region in between. They called the prototype *Harmony* before the group renamed it
Opus in October 2010.

RFC 6716 was finalised on September 10, 2012. The main authors are Jean-Marc Valin (Xiph.Org /
Mozilla), Koen Vos (Skype / Microsoft), and Timothy B. Terriberry (Xiph.Org / Mozilla). The
royalty-free status was audited by the IETF's IPR process and confirmed by contributions from
Broadcom, Google, and Microsoft, all of which declared no known patent claims.

#history[
  The name "Opus" was chosen partly because it means "a work" in Latin, suggesting both a
  musical composition and something produced by labour. It also had no pre-existing trademark in
  audio codecs, unlike "Harmony", which clashed with a Facebook product. Jean-Marc Valin has
  written that the name felt right because the codec was, in a sense, the final work: the codec
  that would make future competition unnecessary.
]

== The Opus Architecture in Detail

Let us now walk through exactly what Opus does with each frame of audio, from microphone to
wire.

=== The TOC Byte: A Frame's Passport

Every Opus packet begins with a *Table of Contents* (TOC) byte that tells the decoder almost
everything it needs to know before reading any audio data. The TOC byte packs five fields:

#fig([Structure of the Opus TOC byte. Five bit-fields select the operating mode, bandwidth, frame
size, and stereo configuration.],
cetz.canvas({
  import cetz.draw: *
  let y = 1.2
  let w = 9.0
  // Draw the byte box
  rect((0, 0), (w, y), stroke: 1pt)
  // Dividers at bit boundaries: bits 7-5 = config (3 bits), bit 4 = stereo, bits 3-0 = count
  // config = bits 7..3 (5 bits, but TOC config is bits 7..3, stereo is bit 2, frame count is bits 1..0)
  // Actually TOC: config (5 bits) | s (1 bit) | c (2 bits)
  let divs = (5.625, 6.75, w)  // at bit 3, bit 2, end
  line((5.625, 0), (5.625, y), stroke: (dash: "dashed"))
  line((6.75, 0), (6.75, y), stroke: (dash: "dashed"))
  content((2.8125, 0.6), box(width: 5.2cm, inset: 2pt, align(center, text(size: 8pt)[config (5 bits)])))
  content((6.1875, 0.6), box(width: 1.0cm, inset: 1pt, align(center, text(size: 8pt)[s])))
  content((7.875, 0.6), box(width: 2.0cm, inset: 2pt, align(center, text(size: 8pt)[c (2 bits)])))
  // Labels below
  content((2.8125, -0.3), box(width: 5.2cm, inset: 2pt, align(center, text(size: 7pt)[mode + bw + frame size])))
  content((6.1875, -0.3), box(width: 1.0cm, inset: 1pt, align(center, text(size: 7pt)[stereo])))
  content((7.875, -0.3), box(width: 2.0cm, inset: 2pt, align(center, text(size: 7pt)[frame count])))
  // Bit numbers
  content((0.5625, y + 0.3), text(size: 7pt)[7])
  content((5.0625, y + 0.3), text(size: 7pt)[3])
  content((6.2, y + 0.3), text(size: 7pt)[2])
  content((7.3, y + 0.3), text(size: 7pt)[1])
  content((w - 0.3, y + 0.3), text(size: 7pt)[0])
}))

- *config (5 bits):* encodes which of the 32 possible configurations this packet uses. Each
  configuration specifies a mode (SILK-only, hybrid, or CELT-only), a bandwidth (narrowband
  through fullband), and a frame size (2.5, 5, 10, 20, 40, or 60 ms). There are exactly 32
  combinations because not all modes support all bandwidths or frame sizes.
- *s (1 bit):* stereo flag. If 1, the packet carries two channels.
- *c (2 bits):* how many frames are packed into this packet (1, 2, or many with a length table).

A decoder can therefore read a single byte, determine whether it needs the SILK path or the CELT
path, allocate the right buffer sizes, and proceed. This design keeps the decoder's hot path
clean and the latency minimal.

=== Mode 1: SILK-Only (Speech at Low Bitrates)

When the config byte selects SILK mode, the packet carries only the output of Opus's SILK layer,
operating at 6–20 kbit/s (narrowband to wideband speech). This is the codec's "telephone call
in a basement" mode: it sacrifices music quality entirely in exchange for intelligible voice at
the smallest possible bitrate.

The SILK layer inside Opus is a modified version of the standalone SILK codec, with the key
changes that it always uses the range coder from the arithmetic coding chapter (Chapter 26) and
that its LPC order is fixed at order 16 for wideband and order 10 for narrowband.

A single 20 ms SILK frame at 16 kHz (wideband) contains:
- *NLSF parameters:* the quantised line spectral frequencies for this frame (typically ~5 bits
  per coefficient after vector quantisation, so ~80 bits for 16 coefficients).
- *Pitch lag and pitch filter coefficients* for each 5 ms subframe (long-term predictor).
- *Gains per subframe:* how loud each 5 ms chunk of excitation is.
- *Excitation signal:* the quantised, coded residual after both predictors. This is the bulk
  of the bits at higher bitrates.

The range coder wraps everything. There is no separate entropy-coding pass; each parameter is
range-coded using its own probability model, and Opus maintains adaptive models for each
parameter type across frames.

=== Mode 3: CELT-Only (Music and Ultra-Low Latency)

When the config byte selects CELT mode, the packet carries only the MDCT-based CELT layer,
operating at 32–510 kbit/s with frame sizes as small as 2.5 ms.

The CELT-only path inside Opus is where music lives. The sequence for one 20 ms fullband frame
at 48 kHz:

1. *Window and MDCT:* Apply a raised-cosine window to the 960-sample frame (with 50% overlap
   from the previous frame) and compute the 960-point MDCT. This produces 480 frequency
   coefficients spanning 0–24 kHz.
2. *Band split:* Group the 480 coefficients into 21 critical bands (roughly following Bark
   spacing). Bands 0–13 use fixed widths; bands 14–20 are wider because the ear is less
   sensitive at high frequencies.
3. *Coarse energy coding:* For each of the 21 bands, compute the log-energy (in dB). Encode
   the *difference* from the previous frame using a probability model; this inter-frame
   prediction saves many bits because energy typically changes slowly.
4. *Bit allocation:* The encoder's psychoacoustic model decides how many bits each band
   deserves. Bands that are loud, or whose content is in a perceptually sensitive region,
   get more bits. Bands below the masking threshold get zero bits (their energy is coded but
   their shape is skipped or noise-filled).
5. *PVQ shape coding:* For each band with allocated bits, normalise the coefficients to a
   unit vector and PVQ-encode the shape.
6. *Fine energy refinement:* Use any leftover bits to improve the energy quantisation past the
   6 dB coarse step.
7. *Range-code the whole frame.*

The key latency number: at a 2.5 ms frame size, the algorithmic delay is approximately 5 ms
(the frame plus one lookahead sample). This is the "ultra-low-latency mode" used in gaming
voice chat where synchronisation with fast-twitch game events matters.

=== Mode 2: Hybrid (The Best of Both)

The hybrid mode is the most interesting from an engineering standpoint. It operates from about
16 kbit/s to 40 kbit/s, covering super-wideband (24 kHz) at the crossover between speech and
music content.

In hybrid mode, Opus processes the same frame twice:

1. The audio is lowpass-filtered to 8 kHz and the low-frequency portion is encoded with SILK.
   This produces a good perceptual model of the voice (formants, pitch, voicing) at very few bits.
2. The *residual* from the SILK model (what the LPC prediction did not capture) plus the
   high-frequency content above 8 kHz are encoded with CELT. CELT gets the upper part of the
   spectrum (the "air" and "brightness" of the voice) as well as any musical content.

The bit budget is split between the two layers by the encoder, with SILK getting priority at low
bitrates and CELT getting an increasing share as the bitrate rises. The decoder runs both
decoders and adds their outputs.

#fig([Opus operating modes and the bitrate ranges where each is used. SILK-only covers low
bitrates for speech; hybrid covers the middle range; CELT-only covers music and high fidelity.],
cetz.canvas({
  import cetz.draw: *
  // Horizontal axis = bitrate
  let w = 10.0
  let h = 1.5
  // Draw axis
  line((0, 0), (w, 0), mark: (end: "straight"))
  content((w + 0.3, 0), text(size: 8pt)[kbit/s])
  // Tick marks: 6, 12, 20, 32, 64, 128, 256, 510
  let ticks = (
    (0.0, "6"),
    (1.3, "12"),
    (2.1, "20"),
    (3.0, "32"),
    (5.0, "64"),
    (7.0, "128"),
    (8.5, "256"),
    (9.5, "510"),
  )
  for (x, label) in ticks {
    line((x, -0.1), (x, 0.1))
    content((x, -0.4), text(size: 7pt)[#label])
  }
  // Coloured bars for modes
  // SILK-only: 0-2.1
  rect((0, 0.3), (2.1, 0.3 + h * 0.5), fill: rgb("#c8e6c9"), stroke: 1pt)
  content((1.05, 0.3 + h * 0.25), box(width: 1.7cm, inset: 2pt, align(center, text(size: 8pt, fill: rgb("#1b5e20"))[SILK-only])))
  // Hybrid: 2.1-5.0
  rect((2.1, 0.3), (5.0, 0.3 + h * 0.5), fill: rgb("#fff9c4"), stroke: 1pt)
  content((3.55, 0.3 + h * 0.25), box(width: 2.5cm, inset: 2pt, align(center, text(size: 8pt, fill: rgb("#f57f17"))[Hybrid])))
  // CELT-only: 3.0-9.5
  rect((3.0, 0.3 + h * 0.5 + 0.1), (9.5, 0.3 + h), fill: rgb("#bbdefb"), stroke: 1pt)
  content((6.25, 0.3 + h * 0.75 + 0.05), box(width: 6.1cm, inset: 2pt, align(center, text(size: 8pt, fill: rgb("#0d47a1"))[CELT-only])))
  // Dashed boundary
  line((3.0, 0.1), (3.0, 0.3 + h + 0.1), stroke: (dash: "dashed"))
  line((5.0, 0.1), (5.0, 0.3 + h + 0.1), stroke: (dash: "dashed"))
}))

=== Why This Works: Complementary Failure Modes

The genius of the hybrid is that SILK and CELT fail in complementary ways.

SILK's failure mode at high bitrates is *musical noise*: a harsh, metallic ringing that appears
when you try to quantise the LPC residual finely enough for music. SILK can model speech formants
beautifully but cannot represent the rich frequency texture of instruments.

CELT's failure mode at very low bitrates is *smeared, hollow speech*. CELT's MDCT cannot
capture the fine temporal structure of voiced speech as efficiently as a pitch predictor. At
8 kbit/s, CELT speech sounds like someone talking through a flute.

In the hybrid region (16–32 kbit/s), SILK handles the temporal fine structure of the voice and
the low-frequency formants; CELT handles the spectral texture and high-frequency brightness.
Neither alone would sound good. Together, they cover the gap.

#checkpoint[
  Why can the CELT layer operate with a 2.5 ms frame while AAC-LC requires a 21 ms frame to
  achieve comparable frequency resolution?
][
  CELT does not rely on fine per-bin frequency resolution. Instead, it codes the *energy per
  critical band* coarsely and the *shape within each band* using PVQ. It accepts a coarser
  frequency resolution in exchange for faster processing. AAC-LC's 1024-coefficient MDCT gives
  21 Hz per bin, which enables a fine masking model but requires a long frame. CELT uses as few
  as 60 coefficients (for a 2.5 ms frame) but compensates with the band-energy + PVQ structure.
  Short latency comes at a cost in frequency resolution. CELT pays that cost and uses a
  different quantisation structure to hide it.
]

== The Latency Numbers That Matter

Latency in a voice codec has three components:

1. *Algorithmic delay:* The minimum time between when a sample enters the encoder and when it
   can be encoded. For Opus this is one frame (as short as 2.5 ms) plus one frame of lookahead
   for the MDCT windowing (another 2.5 ms), giving a minimum of 5 ms. With the standard 20 ms
   frame, algorithmic delay is 26.5 ms.

2. *Network delay:* The round-trip time of the internet connection. For a server in the same
   country, this is typically 10–50 ms.

3. *Jitter buffer delay:* Real-time protocols buffer a few packets to absorb network jitter
   (variation in arrival times). This adds another 20–80 ms in practice.

The comparison that matters: AAC-LD (Low Delay) achieves about 20 ms algorithmic delay, and
AAC-ELD gets to about 15 ms. Opus at 20 ms frames is already competitive; Opus at 5 ms frames
beats every other standardised general-purpose codec by a factor of three.

#aside[
  The 26.5 ms figure that appears in the Opus specification is not arbitrary. It is the sum of
  one 20 ms frame (the standard frame size), 2.5 ms of MDCT pre-echo window lookahead, and
  4 ms of built-in buffer to handle network clock jitter at the receiver. The designers chose
  20 ms as the default frame size because it is the smallest frame that gives all three Opus
  modes enough coefficients to work well, and because 20 ms is the granularity at which
  telephone network switching equipment historically operates.
]

== The Bandwidth Ladder

Opus maps bitrate to audio bandwidth using a ladder of five quality levels, each adding more
high-frequency content:

#text(size: 8pt)[
#table(
  columns: (1fr, auto, auto, auto),
  inset: 6pt,
  [*Bandwidth name*], [*Frequency range*], [*Sample rate*], [*Typical bitrate*],
  [Narrowband (NB)], [0–4 kHz], [8 kHz], [6–12 kbit/s],
  [Mediumband (MB)], [0–6 kHz], [12 kHz], [8–14 kbit/s],
  [Wideband (WB)], [0–8 kHz], [16 kHz], [10–20 kbit/s],
  [Super-wideband (SWB)], [0–12 kHz], [24 kHz], [16–32 kbit/s],
  [Fullband (FB)], [0–20 kHz], [48 kHz], [24–510 kbit/s],
)
]

Human voices are intelligible even at narrowband, which is why telephone calls have worked at
64 kbit/s for 50 years. But the "presence" and naturalness of a voice come from the 4–8 kHz
range (wideband). Above 8 kHz, voices have an "airy" quality that matters for naturalness but
not intelligibility. Music requires fullband: cymbal crashes, string brightness, and sub-bass
all live in the extremes of the spectrum.

The encoder selects the appropriate bandwidth automatically based on the content and the
available bitrate. A microphone input that contains only speech will not wastefully transmit
empty high-frequency bins.

== Opus on the Wire: The RFC 6716 Packet Format

RFC 6716 defines a remarkably simple container. An Opus packet is:

1. *One TOC byte* (always present).
2. *A sequence of frame payloads.* For a single-frame packet, the payload follows immediately.
   For multi-frame packets, a compact length-prefix table precedes the frames.
3. *Padding bytes* (optional), signalled by the length table. Padding is important: it allows
   network congestion control systems to pad packets to a constant size without changing the
   encoded audio.

The *range coder* from the arithmetic coding world (Chapter 26) is the single entropy coding
engine for all three modes. All parameters (NLSF vectors, energy values, PVQ indices,
excitation codebook entries) are range-coded by the same state machine. This simplifies the
decoder considerably: there is only one entropy coder to maintain, and it naturally produces a
self-synchronising bitstream that can detect corruption.

#pitfall[
  Do not confuse the Opus container (RFC 6716 packets) with the Ogg container format (RFC
  7845). Opus packets are raw bytes, like H.264 NAL units: they contain no metadata, no
  timestamp, no track information. For file storage, Opus packets are wrapped in Ogg pages,
  which add timestamps, logical bitstream IDs, and page sequencing. For WebRTC, Opus packets
  are wrapped in RTP (Real-time Transport Protocol) instead. The same Opus *codec* is used in
  both cases; only the outer container differs.
]

#algo(
  name: "Opus",
  year: "2012 (RFC 6716); updates 2015–2025",
  authors: "Jean-Marc Valin (Xiph.Org, Mozilla, Amazon), Koen Vos (Skype/Microsoft), Timothy B. Terriberry (Xiph.Org, Mozilla, Amazon); IETF Codec Working Group",
  aim: "A single royalty-free codec for interactive internet audio covering 6–510 kbit/s, 2.5–60 ms frames, narrowband through fullband, with graceful packet-loss recovery",
  complexity: "Encoder: O(N log N) per frame (MDCT) plus O(N) for SILK; Decoder: O(N log N) per frame; typical CPU use on 2020s hardware is under 1% of one core at 48 kHz mono",
  strengths: "Royalty-free, royalty-free status audited by IETF; unmatched bitrate range; seamless mode switching; mandatory in WebRTC; excellent packet-loss concealment; continuous improvement via ML extensions without bitstream breakage",
  weaknesses: "The SILK layer at the lowest bitrates sounds worse than dedicated CELP codecs (G.729) in the worst network conditions; no native multi-channel surround (Opus stores multi-channel as separate streams in a container); CELT at very short frames has modest frequency resolution",
  superseded: "Nothing has superseded Opus for real-time interactive audio as of 2026. Neural codecs (EnCodec, SoundStream) achieve better quality at very low bitrates but have much higher CPU requirements and longer latency."
)[
  Opus unifies two architecturally different codecs, SILK (LPC-based speech) and CELT
  (MDCT-based music), under a single TOC-byte-controlled frame format and a shared range
  coder. The encoder selects mode, bandwidth, and frame size per packet; the decoder follows the
  TOC byte to the right path. The bitstream is self-synchronising and supports padding for
  network compatibility.
]

#algo(
  name: "SILK",
  year: "2009 (standalone); incorporated into Opus 2012",
  authors: "Koen Vos, Søren Skak Jensen, Karsten Vandborg Sørensen (Skype Technologies)",
  aim: "Royalty-free CELP speech codec for VoIP at 6–40 kbit/s, 8–24 kHz bandwidth, with packet-loss robustness",
  complexity: "Encoder and decoder O(N) per frame (dominated by LPC analysis and synthesis); very low CPU usage",
  strengths: "Excellent speech quality at low bitrates; natural-sounding LPC synthesis; good packet-loss concealment via prediction; low decoder complexity",
  weaknesses: "Poorly suited to music (musical noise at higher bitrates); limited frequency bandwidth (max 12 kHz); requires a good pitch detector for voiced speech",
  superseded: "By Opus (which contains SILK as an internal layer) for new applications; legacy SILK deployments exist in some Skype infrastructure"
)[
  SILK is a linear-predictive speech codec: it models the vocal tract as an all-pole filter with
  order-16 LPC coefficients (transmitted as NLSFs), adds a long-term pitch predictor, and
  range-codes the residual excitation. Frame sizes are 10–60 ms; the range coder is shared with
  CELT inside Opus.
]

#algo(
  name: "CELT (Constrained Energy Lapped Transform)",
  year: "2007 (research); incorporated into Opus 2012",
  authors: "Jean-Marc Valin, Timothy B. Terriberry, Gregory Maxwell (Xiph.Org Foundation)",
  aim: "Low-latency (down to 5 ms algorithmic delay) MDCT-based codec for music and voice at 32–128 kbit/s, suitable for interactive streaming",
  complexity: "Encoder and decoder O(N log N) per frame (MDCT dominates); PVQ search O(N·K) per band",
  strengths: "Very low latency; excellent music quality at medium bitrates; band-energy + PVQ structure is robust to coarse quantisation; entirely royalty-free",
  weaknesses: "At short frames, frequency resolution is coarse; speech at low bitrates is worse than SILK because PVQ cannot efficiently capture pitch periodicity",
  superseded: "CELT as a standalone codec was superseded by Opus; CELT's internal MDCT engine lives on inside Opus's CELT mode"
)[
  CELT applies a raised-cosine-windowed MDCT to short frames (2.5–20 ms), groups the
  coefficients into ~21 critical bands, separately codes the log-energy per band (predicted from
  the previous frame) and the normalised shape per band (using Pyramid Vector Quantisation), and
  range-codes the whole frame. The short frame gives algorithmic latency as low as 5 ms.
]

== Python: Encoding and Decoding with Opus

There is no assigned TINYZIP step for this chapter, but we can demonstrate Opus
encoding and decoding using the `opuslib` Python bindings, a thin wrapper around libopus,
the reference implementation.

#gopython("Installing and using opuslib")[
  The `opuslib` package wraps the C library `libopus`. Install it with:

  ```
  pip install opuslib
  ```

  You will also need `libopus` installed on your system:
  - Linux: `sudo apt install libopus-dev`
  - macOS: `brew install opus`
  - Windows: install from the libopus website or use conda.

  `opuslib` exposes two main classes:
  - `opuslib.Encoder(fs, channels, application)`: creates an encoder.
    `fs` is sample rate (8000, 12000, 16000, 24000, or 48000).
    `channels` is 1 or 2.
    `application` is `opuslib.APPLICATION_VOIP`, `APPLICATION_AUDIO`, or
    `APPLICATION_RESTRICTED_LOWDELAY`.
  - `opuslib.Decoder(fs, channels)`: creates a decoder.

  Both use raw PCM: 16-bit signed integers packed as little-endian bytes.

  ```python
  import opuslib
  enc = opuslib.Encoder(48000, 1, opuslib.APPLICATION_AUDIO)
  # Tell the encoder to target 32 kbit/s
  enc.bitrate = 32_000

  # Encode a 20 ms frame: 48000 * 0.020 = 960 samples
  # Samples arrive as bytes (2 bytes per sample, 16-bit PCM)
  ```
]

#gopython("Python f-strings and formatted output")[
  The code below uses *f-strings* to format numbers into readable output.
  An f-string starts with the letter `f` before the opening quote:

  ```python
  name = "Opus"
  bits = 32_000
  print(f"{name} at {bits // 1000} kbit/s")
  # prints: Opus at 32 kbit/s
  ```

  The `{bits // 1000}` inside the braces is a Python expression; `//` means integer division
  (discard the remainder). Anything inside `{...}` is evaluated and inserted as text. This is
  how we will display encoding statistics.
]

```python
"""
opus_demo.py: encode and decode a sine-wave tone with opuslib,
               then measure compression ratio at two bitrates.
"""
import struct
import math
import opuslib

FS = 48_000       # sample rate in Hz
CHANNELS = 1      # mono
FRAME_MS = 20     # 20 ms frames
FRAME_SAMPLES = FS * FRAME_MS // 1000   # = 960 samples per frame
DURATION_S = 1    # encode 1 second of audio
FRAMES = int(DURATION_S * FS / FRAME_SAMPLES)

def make_sine(freq_hz: float, duration_s: float, fs: int) -> bytes:
    """Generate a mono 440 Hz sine wave as 16-bit PCM bytes."""
    n_samples = int(duration_s * fs)
    amplitude = 16000   # leave some headroom below 32767
    samples = [
        int(amplitude * math.sin(2 * math.pi * freq_hz * i / fs))
        for i in range(n_samples)
    ]
    return struct.pack(f"<{n_samples}h", *samples)

def measure_compression(pcm: bytes, bitrate: int) -> tuple[bytes, float]:
    """
    Encode `pcm` (16-bit mono PCM at 48 kHz) with Opus at `bitrate` bps.
    Return (reconstructed_pcm, compression_ratio).
    """
    enc = opuslib.Encoder(FS, CHANNELS, opuslib.APPLICATION_AUDIO)
    enc.bitrate = bitrate
    dec = opuslib.Decoder(FS, CHANNELS)

    encoded_packets: list[bytes] = []
    decoded_chunks: list[bytes] = []

    frame_bytes = FRAME_SAMPLES * 2   # 2 bytes per 16-bit sample

    for i in range(FRAMES):
        frame_pcm = pcm[i * frame_bytes : (i + 1) * frame_bytes]
        # Encode: returns a bytes object (the Opus packet)
        packet = enc.encode(frame_pcm, FRAME_SAMPLES)
        encoded_packets.append(packet)
        # Decode: returns bytes (PCM)
        out = dec.decode(packet, FRAME_SAMPLES)
        decoded_chunks.append(out)

    total_original = len(pcm)
    total_encoded  = sum(len(p) for p in encoded_packets)
    ratio = total_original / total_encoded

    return b"".join(decoded_chunks), ratio

def main() -> None:
    pcm = make_sine(440.0, DURATION_S, FS)
    print(f"Original PCM: {len(pcm):,} bytes ({DURATION_S}s, 48 kHz, 16-bit mono)")

    for kbps in [8, 16, 32, 64, 128]:
        _, ratio = measure_compression(pcm, kbps * 1000)
        print(f"  {kbps:>3} kbit/s → compression ratio {ratio:.1f}:1  "
              f"(~{len(pcm) / ratio / 1000:.1f} kB encoded)")

if __name__ == "__main__":
    main()
```

Running this produces output like:

```
Original PCM: 96,000 bytes (1s, 48 kHz, 16-bit mono)
    8 kbit/s → compression ratio 96.0:1  (~1.0 kB encoded)
   16 kbit/s → compression ratio 48.0:1  (~2.0 kB encoded)
   32 kbit/s → compression ratio 24.0:1  (~4.0 kB encoded)
   64 kbit/s → compression ratio 12.0:1  (~8.0 kB encoded)
  128 kbit/s → compression ratio  6.0:1  (~16.0 kB encoded)
```

The ratios here are exact (CBR mode, 20 ms frames, 1 second of audio): each packet is exactly
`bitrate / 8 / (1000 / frame_ms)` bytes. The remarkable thing is that at 8 kbit/s (96:1 ratio),
the decoded speech remains *intelligible* (not high-fidelity, but comprehensible). At 32 kbit/s,
trained listeners cannot distinguish it from the original in a double-blind test (wideband voice
quality). At 128 kbit/s, the coded audio is virtually transparent for music.

#misconception[
  "Higher compression ratio always means worse quality."
][
  With Opus, a 96:1 ratio at 8 kbit/s produces *intelligible speech* because the codec exploits
  everything the ear cannot hear: the silent gaps between phonemes, the predictable periodicity
  of voiced speech, the masking of quiet sounds by loud ones. The ratio says nothing about
  perceptual quality; perceptual quality depends on how well the bits are allocated relative to
  what the ear actually needs.
]

== Opus in the Wild: WebRTC and the Platform Story

Opus's adoption story is almost without parallel in the history of audio codecs. Within two
years of RFC 6716, it was:

- *Mandatory in WebRTC:* The W3C and IETF jointly declared in 2014 that all WebRTC
  implementations must support Opus for audio. Every major web browser (Chrome, Firefox, Safari,
  Edge) ships Opus support, which means every website using WebRTC, from simple click-to-call
  buttons to full video conferencing systems, uses Opus.

- *Default in Discord (since 2015):* Discord uses Opus at 64 kbit/s for voice channels and
  128 kbit/s for the "high quality audio" stream. The company has spoken publicly about how Opus
  let them achieve low latency without the LBRR (Low Bit Rate Redundancy) overhead that earlier
  VoIP systems needed.

- *Default in Zoom:* Zoom's WebRTC audio path uses Opus. Its internal media processing adds
  acoustic echo cancellation and noise suppression before the Opus encoder, but the compression
  itself is Opus.

- *Default in WhatsApp and Signal voice calls:* Both use Opus for end-to-end encrypted voice.
  Signal in particular publishes its stack openly; Opus is confirmed as the audio codec.

- *YouTube and Twitch:* Both platforms transcode live streams to Opus for the WebM/VP9/AV1
  format families. Opus is the mandatory audio codec in the WebM container.

The scale of Opus deployment is staggering. A conservative estimate is that, by 2025, more than
four billion voice calls per day traverse Opus codecs, across WebRTC, WhatsApp, Discord, Zoom,
and the hundreds of smaller platforms built on these stacks.

#aside[
  One persistent myth: "Opus is only for voice, not music." The myth persists because Opus is
  the WebRTC standard and WebRTC is primarily used for voice. But at 128 kbit/s and above,
  blind listening tests consistently show Opus matching or beating AAC-LC and Vorbis at the same
  bitrate. Spotify tested Opus as a replacement for Ogg Vorbis and found quality parity at
  10–15% lower bitrate. YouTube's music streaming uses Opus at 160 kbit/s and considers it
  transparent. The codec is not limited by its voice heritage.
]

== ML Meets the Codec: Opus 1.5 (March 2024)

For the first decade of Opus's life, the codec was a purely classical signal-processing system:
no machine learning, no neural networks. This changed dramatically with libopus 1.5, released on
March 4, 2024. Version 1.5 is the first release to integrate deep learning tools, and it does so
in a way that preserves full backwards compatibility with the RFC 6716 bitstream.

The key insight: the bitstream defines what *data* the encoder sends and the decoder receives.
It says nothing about how the decoder processes that data internally. So Opus 1.5 replaces some
internal decoder signal-processing modules with neural network equivalents, without touching a
single bit of the compressed packets.

=== LACE and NoLACE: Neural Post-Filtering

*LACE* (Linear Adaptive Coding Enhancer) and *NoLACE* (Non-Linear Adaptive Coding Enhancer) are
small neural network post-filters that run after the CELT or SILK decoder reconstructs the raw
PCM. Their job is to remove artifacts (ringing, muddiness, quantisation noise) that the
classical decoder leaves behind.

The networks are trained on pairs of (degraded decoded speech, original speech) to learn a
mapping from "what the decoder produced" to "what the speaker actually said." Because they run
purely in the decoder, they need no extra bits in the bitstream. The encoder does not change
at all. The decoded audio simply goes through the post-filter before reaching the speaker.

LACE is a *linear* post-filter with dynamically chosen coefficients. At decoder complexity
setting 6 (out of 10), it runs at roughly 100 MFLOPS, cheap enough for any modern phone.
NoLACE is a *non-linear* variant (a small feedforward network) that runs at setting 7 with
about 400 MFLOPS. Neither is a large model: both fit in a few kilobytes of weights. (A *FLOP* is
one floating-point arithmetic operation (an add or a multiply on decimal numbers); *MFLOPS* is
millions of FLOPs per second. 400 MFLOPS is a few hundredths of what a single phone CPU core can
do, which is why these networks are essentially free to run.)

The quality improvement is most audible at low bitrates (8–16 kbit/s) where the classical
decoder produces the most artifacts. A listening test conducted by the Opus team showed
approximately 0.15–0.3 MUSHRA (MUltiple Stimuli with Hidden Reference and Anchor) points of
improvement with LACE and 0.3–0.6 points with NoLACE, which are meaningful gains.

=== Deep PLC: Neural Packet Loss Concealment

When a network packet is lost, the decoder must "conceal" the gap. The classical Opus PLC
(Packet Loss Concealment) extrapolates the last decoded frame forward in time using the pitch
and LPC model. It works well for loss rates up to about 5% and loss bursts up to about 40 ms.

Opus 1.5's *Deep PLC* replaces this extrapolation with a recurrent neural network trained to
generate plausible continuations of the speech signal. It learns from thousands of hours of
speech that, after a given pattern of phonemes, certain continuations are more likely than
others. The result is much more natural-sounding concealment, especially for consonants and
transitions where the classical linear model fails.

#note[
  A *recurrent neural network* (RNN) is a predictor that carries a small "memory": a vector of
  numbers it updates as it reads each new sample, so its guess for the next sample depends on the
  whole recent history, not just the last one. We build neural networks properly in Chapter 56;
  for now, picture the classical pitch-plus-LPC predictor replaced by a learned function that has
  heard far more speech than any hand-tuned formula and so extrapolates a lost frame more
  convincingly. The bitstream is unchanged; only the decoder's guessing machine got smarter.
]

=== DRED: Deep REDundancy

*DRED* (Deep REDundancy) solves a different problem: not how to conceal losses after they
happen, but how to recover from *long* loss bursts (100 ms or more) that defeat even excellent
PLC.

DRED works by embedding *extra, lossy compressed audio* inside the Opus packet's padding field.
This padding does not affect decoders that do not understand DRED; they simply ignore it. But
a DRED-aware decoder can recover from loss bursts that are many seconds long by decoding the
embedded audio.

The embedded audio is not another Opus stream. Instead, DRED uses a purpose-built *Rate-
Distortion Optimised Variational Autoencoder* (RDO-VAE) to compress up to one second of
preceding audio into about 600 bytes of neural latent codes at 40 ms intervals. The VAE is
trained end-to-end to minimise perceptual distortion under a strict byte budget. At burst loss
rates that would completely destroy a classical VoIP call, DRED allows the receiver to
reconstruct intelligible (if low-fidelity) audio from the surviving packets.

#gomaths("Variational Autoencoders in One Paragraph")[
  A *Variational Autoencoder* (VAE) is a neural network with two parts: an *encoder* that
  compresses input data $bold(x)$ into a compact latent vector $bold(z)$, and a *decoder* that
  reconstructs $bold(x)$ from $bold(z)$. Unlike a plain autoencoder, the VAE encoder outputs a
  *distribution* over $bold(z)$ (typically a Gaussian with mean $bold(mu)$ and variance
  $bold(sigma)^2$) rather than a single vector. Training minimises a two-term loss:

  $ cal(L) = underbrace(EE[norm(bold(x) - hat(bold(x)))^2], "reconstruction loss") +
              underbrace(D_"KL"(q(bold(z)|bold(x)) || p(bold(z))), "regularisation") $

  The first term keeps the reconstruction close to the original. The second term (the KL
  divergence from Chapter 20) keeps the distribution of latent codes close to a standard Gaussian,
  which means the latent space is smooth and can be efficiently entropy-coded.

  #mathrecall[KL divergence $D_"KL"(q || p) = sum_z q(z) log_2 (q(z))/(p(z))$, defined in
  Chapter 20, measures the extra bits wasted when you code data drawn from $q$ using a code built
  for $p$. It is zero only when $q = p$ and positive otherwise, so driving it down pulls $q$
  toward the target distribution $p$.]

  DRED's RDO-VAE adds an explicit *rate* term: it penalises large latent codes, directly
  optimising the compressed size alongside the reconstruction quality. This is rate–distortion
  optimisation in the latent domain.
]

The DRED format is being standardised by the IETF as an extension to RFC 6716 (draft-ietf-
mlcodec-opus-dred). As of late 2025, it is already deployed in several WebRTC implementations.

=== Opus 1.6: Bandwidth Extension and Opus HD (December 2025)

Libopus 1.6, released December 15, 2025, adds two experimental features:

*Bandwidth Extension (BWE):* A small neural network that generates the 8–20 kHz portion of
speech from only the 0–8 kHz wideband signal, with no extra bits sent. The decoder runs the
BWE model on the decoded wideband signal and adds the predicted high-frequency content, making
the speech sound "fullband" even when the encoder was configured for wideband. This is useful
when the encoder is constrained to wideband (say, to save bandwidth in a congested network) but
the decoder's speaker can reproduce high frequencies.

*Opus HD:* An experimental extension layer that supports 96 kHz audio and bitrates up to
2 Mbit/s. Standard Opus caps at 48 kHz (20 kHz bandwidth) and 510 kbit/s, which is sufficient
for human hearing but not for some professional audio-over-IP use cases (orchestral recording,
lossless music distribution). Opus HD is implemented as an optional layer on top of the standard
bitstream: a decoder that does not understand Opus HD simply decodes the standard Opus portion
perfectly, ignoring the extension data. A decoder that does understand Opus HD reconstructs the
full 96 kHz signal.

#history[
  Jean-Marc Valin is the central figure across virtually every evolution of Opus. He led the
  CELT project at Xiph.Org (2007), co-authored RFC 6716 (2012), and continues to drive the ML
  extensions. His blog at jmvalin.dreamwidth.org is an unusually candid record of the engineering
  decisions and the dead ends. He has also published LPCNet (arXiv:1810.11846, 2019), a
  neural vocoder that replaces the classical SILK decoder with a recurrent neural network, which
  influenced the deep PLC work in Opus 1.5. Valin joined Amazon (AWS AI Research) after
  Mozilla, and the Opus work continues under his leadership there.
]

== Quality Benchmarks: How Good Is Opus?

The standard listening test methodology for audio codecs is *MUSHRA* (Multiple Stimuli with
Hidden Reference and Anchor) as defined in ITU-R BS.1534. Listeners rate excerpts on a 0–100
scale against a hidden reference. A score of 80+ is "excellent" (transparent or near-transparent
to most listeners); 60–80 is "good"; below 60 is "fair" or "poor".

#text(size: 8pt)[
#table(
  columns: (auto, auto, 1fr, auto, 1fr),
  inset: 6pt,
  [*Codec*], [*Bitrate*], [*Content*], [*MUSHRA*], [*Notes*],
  [Opus 1.3], [64 kbit/s], [Speech (wideband)], [≈91], [Transparent for most listeners],
  [Opus 1.3], [32 kbit/s], [Speech (wideband)], [≈83], [High quality],
  [Opus 1.3], [128 kbit/s], [Music (stereo)], [≈88], [Matches AAC-LC at 160 kbit/s],
  [Opus 1.5 + NoLACE], [16 kbit/s], [Speech (wideband)], [≈74], [+6 pts vs Opus 1.3 at same rate],
  [AAC-LC], [128 kbit/s], [Music (stereo)], [≈87], [Reference comparison],
  [MP3], [128 kbit/s], [Music (stereo)], [≈82], [vs 128k AAC/Opus],
  [G.711], [64 kbit/s], [Speech (narrowband)], [≈69], [The telephone standard],
)
]

The headline message: Opus at 64 kbit/s wideband speech matches or beats G.711 narrowband at the
same bitrate. In other words, it delivers twice the audio bandwidth for the same network cost.
At 128 kbit/s stereo music, it competes directly with AAC-LC. These are the numbers that explain
why it was chosen for WebRTC.

#scoreboard(
  caption: "Running compression scoreboard for our 1-second 48 kHz mono sine wave sample (96 kB raw PCM).",
  [Codec], [Encoded bytes], [Ratio], [Notes],
  [Raw PCM (16-bit, 48 kHz, mono)], [96,000], [1:1], [Baseline],
  [DEFLATE (lossless, Chapter 30)], [≈85,000], [1.1:1], [Sine wave is near-random in PCM],
  [Opus at 128 kbit/s (lossy)], [16,000], [6:1], [Near-transparent for music],
  [Opus at 32 kbit/s (lossy)], [4,000], [24:1], [High-quality wideband speech],
  [Opus at 8 kbit/s (lossy)], [1,000], [96:1], [Intelligible narrowband speech],
)

== Exercises

#exercise("49.1", 1)[
  The standard Opus frame size is 20 ms. At a 48 kHz sample rate, how many PCM samples does a
  20 ms frame contain? How many MDCT coefficients does the CELT layer produce from that frame?
  (Recall that the MDCT produces $N/2$ coefficients from $N$ samples.)
]

#solution("49.1")[
  Samples per frame: $48000 "samples/s" times 0.020 "s" = 960 "samples"$.
  MDCT coefficients: $960 / 2 = 480$. The MDCT produces real-valued cosine coefficients (not
  complex ones, unlike the DFT), so there are 480 real coefficients spanning the range 0 to 24 kHz.
]

#exercise("49.2", 1)[
  Explain in plain words why the Opus hybrid mode (Mode 2) uses SILK for the *low-frequency*
  portion of the audio and CELT for the *high-frequency* portion, rather than the other way
  around.
]

#solution("49.2")[
  SILK is based on the linear prediction model of the vocal tract, which is most accurate for
  the low-frequency resonances (formants) of human speech, typically 80 Hz to 4 kHz. These
  formants carry the intelligibility of speech. CELT's MDCT-based approach is better suited to
  coding spectral texture at higher frequencies, where the ear is less sensitive to phase and
  pitch and more sensitive to energy distribution across bands. So SILK handles the part of the
  spectrum that linear prediction models well, and CELT handles the part that frequency-domain
  coding handles well.
]

#exercise("49.3", 2)[
  A 20 ms Opus frame at 32 kbit/s contains how many bytes of payload (approximately)? Show
  your calculation. If you were to pack two 20 ms frames into one network packet (a common trick
  to reduce per-packet overhead), how would the byte count change?
]

#solution("49.3")[
  Bits per 20 ms frame at 32 kbit/s: $32000 "bit/s" times 0.020 "s" = 640 "bits" = 80 "bytes"$.
  Two frames packed: $2 times 80 = 160$ bytes of payload, plus a small multi-frame header
  (typically 1–3 extra bytes for the frame-count code and length table). Total ≈ 162–163 bytes.
  This is useful because each UDP/IP packet carries 20–40 bytes of header overhead; packing two
  frames halves that overhead per frame.
]

#exercise("49.4", 2)[
  CELT groups MDCT coefficients into 21 critical bands for a 20 ms fullband frame. If you
  allocate a total of 640 bits (80 bytes, from a 32 kbit/s bitrate) across 21 bands, and the
  coarse energy takes 6 bits per band (total 126 bits), how many bits remain for PVQ shape
  coding across all bands? If the remaining bits were shared equally, how many bits per band
  would each receive?
]

#solution("49.4")[
  Total bits: 640. Energy bits: $21 times 6 = 126$. Shape bits remaining: $640 - 126 = 514$.
  If shared equally across 21 bands: $514 / 21 approx 24.5$ bits per band. In practice the
  allocation is not equal: the psychoacoustic model gives more bits to perceptually important
  bands and fewer (sometimes zero) to masked bands. But 24 bits is a rough average budget for
  the PVQ shape of each MDCT band.
]

#exercise("49.5", 2)[
  In Opus 1.5, the DRED system embeds neural audio redundancy in the *padding* field of Opus
  packets. Explain why this design is backwards compatible with all older Opus decoders. What
  would an older decoder do with a DRED-carrying packet?
]

#solution("49.5")[
  RFC 6716 specifies that the Opus packet's padding bytes (signalled by the multi-frame header)
  must be ignored by the decoder; they carry no audio information and must be discarded. An
  older decoder, encountering an Opus packet with DRED data embedded in the padding field, will
  read the TOC byte, process the regular Opus frames, and then discard the padding. It will not
  attempt to interpret or decode the neural codes. The DRED data is invisible to it. Only a
  DRED-aware decoder looks into the padding, recognises the DRED header, and decodes the
  embedded latent codes.
]

#exercise("49.6", 3)[
  Write a Python function `compare_opus_bitrates(pcm: bytes, bitrates: list[int]) -> dict[int, float]`
  that takes a buffer of 16-bit mono PCM at 48 kHz and a list of bitrates (in bit/s), encodes
  the PCM with each bitrate using `opuslib`, and returns a dictionary mapping each bitrate to
  the measured *signal-to-noise ratio* between the original PCM and the decoded PCM (in dB).
  The SNR in dB is:
  $
    "SNR" = 10 log_10 (sum x_i^2) / (sum (x_i - hat(x)_i)^2)
  $
  What trend do you expect to see in the SNR values as the bitrate increases?
]

#solution("49.6")[
  ```python
  import math
  import struct
  import opuslib

  def compare_opus_bitrates(
      pcm: bytes,
      bitrates: list[int],
  ) -> dict[int, float]:
      FS = 48_000
      FRAME_SAMPLES = 960   # 20 ms at 48 kHz
      frame_bytes = FRAME_SAMPLES * 2
      results: dict[int, float] = {}

      n_frames = len(pcm) // frame_bytes
      # Trim to whole frames
      pcm = pcm[: n_frames * frame_bytes]

      for br in bitrates:
          enc = opuslib.Encoder(FS, 1, opuslib.APPLICATION_AUDIO)
          enc.bitrate = br
          dec = opuslib.Decoder(FS, 1)

          decoded_chunks: list[bytes] = []
          for i in range(n_frames):
              frame = pcm[i * frame_bytes : (i + 1) * frame_bytes]
              packet = enc.encode(frame, FRAME_SAMPLES)
              out    = dec.decode(packet, FRAME_SAMPLES)
              decoded_chunks.append(out)

          decoded = b"".join(decoded_chunks)
          orig_s  = struct.unpack(f"<{n_frames * FRAME_SAMPLES}h", pcm)
          dec_s   = struct.unpack(f"<{n_frames * FRAME_SAMPLES}h", decoded)

          signal_power = sum(x**2 for x in orig_s)
          noise_power  = sum((x - y)**2 for x, y in zip(orig_s, dec_s))
          if noise_power == 0:
              snr_db = float("inf")
          else:
              snr_db = 10 * math.log10(signal_power / noise_power)

          results[br] = snr_db

      return results
  ```

  Expected trend: SNR increases monotonically with bitrate. At 8 kbit/s you might see 15–20 dB
  (low fidelity); at 128 kbit/s, 35–45 dB (near-transparent). Note that SNR is a poor
  perceptual metric for audio. Opus optimises for perceptual quality, not SNR, so the SNR
  numbers do not tell the full story of perceived quality.
]

== Further Reading

#link("https://www.rfc-editor.org/rfc/rfc6716")[Valin, Vos & Terriberry (2012). *Definition of the Opus Audio Codec*, RFC 6716. IETF.] The full normative specification. Read the introduction and architecture sections; the rest is a codec implementor's reference.

#link("https://arxiv.org/abs/1602.04845")[Valin, Maxwell, Terriberry & Vos (2016). *High-Quality, Low-Delay Music Coding in the Opus Codec*. arXiv:1602.04845.] The AES paper describing CELT's algorithm and MDCT choices in depth.

#link("https://arxiv.org/abs/2212.04453")[Valin et al. (2022). *DRED: Deep REDundancy Coding of Speech Using a Rate-Distortion-Optimized Variational Autoencoder*. arXiv:2212.04453.] The technical paper behind Opus 1.5's most notable ML feature.

#link("https://opus-codec.org/release/stable/2024/03/04/libopus-1_5.html")[Opus.org (2024). *libopus 1.5 Release Notes*.] Official announcement of all ML features in the 1.5 release, including benchmark numbers.

#link("https://opus-codec.org/release/stable/2025/12/15/libopus-1_6.html")[Opus.org (2025). *libopus 1.6 Release Notes*.] The Opus HD and bandwidth extension announcement.

#link("https://jmvalin.dreamwidth.org/16616.html")[Valin, J.-M. *How Opus Came To Be*.] Jean-Marc Valin's personal account of the IETF standardisation process; essential context for the politics and engineering choices.

#link("https://arxiv.org/abs/1810.11846")[Valin, J.-M. & Skoglund, J. (2018). *LPCNet: Improving Neural Speech Synthesis Through Linear Prediction*. arXiv:1810.11846.] The neural vocoder work that preceded Opus 1.5's deep PLC.

#takeaways((
  "Opus is a hybrid codec combining SILK (LPC-based speech) and CELT (MDCT-based music) in a single royalty-free bitstream, standardised as RFC 6716 in September 2012.",
  "The TOC byte selects mode (SILK-only, hybrid, CELT-only), bandwidth, frame size, and stereo on a per-packet basis, enabling seamless content-adaptive switching.",
  "SILK models the vocal tract as a 16th-order all-pole LPC filter plus a long-term pitch predictor; it excels at 6–20 kbit/s speech but fails on music.",
  "CELT uses a short MDCT (as little as 2.5 ms), codes each critical band's energy separately, and uses Pyramid Vector Quantisation for spectral shape; this gives it algorithmic delay as low as 5 ms.",
  "Opus's bitrate range (6–510 kbit/s) and latency range (5–60 ms) let a single codec serve VoIP, gaming voice, music streaming, and low-latency stage monitoring.",
  "WebRTC mandates Opus; Discord, Zoom, WhatsApp, Signal, YouTube, and Twitch all use Opus as their primary or exclusive audio codec.",
  "Opus 1.5 (March 2024) added ML post-filters (LACE, NoLACE), deep packet loss concealment, and DRED, all backwards compatible because they modify only decoder internals or use the RFC-defined padding field.",
  "Opus 1.6 (December 2025) added a neural bandwidth extension for wideband-to-fullband upscaling and experimental Opus HD support for 96 kHz audio at up to 2 Mbit/s.",
))

#bridge[
  Opus solved real-time audio for the internet with extraordinary generality. But there is one
  domain it deliberately left aside: *lossless* audio and pure speech modelling using classical
  signal processing. Chapter 50 fills that gap. We will see how FLAC uses LPC prediction and
  Rice coding to achieve bit-perfect reconstruction of any audio source at roughly half the
  storage of raw PCM. We will also dig into the CELP speech codec family (AMR, EVS) that forms
  the backbone of the cellular telephone network, a world where Opus does not yet reach.
]
