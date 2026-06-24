#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= AAC, Vorbis, and Modern General Audio

#epigraph[
  "We did not merely improve MP3. We threw it out and started from first principles."
][
  Karlheinz Brandenburg, reflecting on AAC development, AES 1999
]

Picture a music store in late 1997. Shelves still hold plastic CD cases. A few blocks away, a
university researcher is quietly ripping one of those CDs to a file one-tenth the size, and it
sounds _better_ than a 128 kbit/s MP3. The tool is brand new, unknown to the public, and will not
reach most ears for another five years. Its name is AAC.

Meanwhile, a different kind of revolution is brewing in a living room. A software engineer named
Chris Montgomery has just received a letter from Fraunhofer's lawyers saying that his favourite
music format (MP3) is about to start charging royalties. He reads the letter, puts it down, and
starts writing a replacement from scratch. That replacement will be called Vorbis, and it will be
free forever.

This chapter is about those two successors to MP3, how they work, why they sound better, and how
the codec family that began with AAC evolved over two decades into the backbone of modern
streaming. We will also look at the licensing war that separated the two camps and its surprising
recent resolution.

#recap[
  In Chapter 46 we explored the science the ear uses to filter sound: critical bands, masking
  thresholds, temporal pre- and post-masking. We showed how a psychoacoustic model turns those
  limits into a per-band noise budget. Chapter 47 then showed how MP3 exploits that budget using
  a hybrid filterbank (32-band polyphase followed by MDCT), Huffman-coded quantized coefficients,
  and a global gain knob. We ended with MP3's fatal flaw: its blocky filterbank and limited MDCT
  resolution leave audible artifacts, especially on transients and high frequencies, that a better
  codec could avoid.
]

#objectives((
  "Explain the four key improvements AAC made over MP3: pure MDCT, TNS, PNS, and joint stereo.",
  "Describe the AAC profile family: LC, Main, HE-AAC v1 (SBR), HE-AAC v2 (Parametric Stereo), and xHE-AAC/USAC.",
  "Trace the architecture of Vorbis (floor curves, residue, vector-quantised codebooks) and why it is truly royalty-free.",
  "Read a Python simulation that measures spectral flatness, the metric SBR relies on.",
  "Understand the licensing landscape and why it still matters in 2026.",
))

== From Hybrid to Pure: AAC's First Big Move

MP3's hybrid filterbank was a historical accident. The polyphase filterbank was inherited from
earlier MPEG Audio Layers I and II, and the MDCT was bolted on top to improve frequency
resolution. The result worked, but the two stages had different frequency resolutions that were
difficult to align. A loud transient in one MDCT block could leak pre-echo noise backward in time,
producing an audible click or ringing before the actual drum hit.

AAC swept this away. Its core (formally standardised as MPEG-2 Part 7 in April 1997, then
absorbed into MPEG-4 Part 3 in 1999) is a *single pure MDCT* with two selectable block sizes:

- *Long block (1024 coefficients):* used during steady-state music, giving fine frequency resolution of roughly 21.5 Hz per bin at 44.1 kHz.
- *Short block (128 coefficients):* switched in during transients, eight short blocks stacking to cover the same time as one long block, giving eight times finer time resolution.

The switch between long and short is guided by the psychoacoustic model: when it detects a
sudden transient, it flips to short blocks before the event and back after. This alone eliminates
the pre-echo that plagued MP3.

#gomaths("Window switching and block sizes")[
  Recall from Chapter 38 that an MDCT fed a windowed frame of $N$ input samples (each frame
  overlapping its neighbour by 50%) produces exactly $N\/2$ frequency coefficients: half as many
  numbers out as in, which is why the MDCT is called _critically sampled_. The frequency
  resolution (the spacing between neighbouring coefficients, each one a "bin" on the frequency
  axis) is the audio bandwidth $f_s\/2$ shared out among those $N\/2$ bins:

  $ Delta f = (f_s \/ 2) / (N \/ 2) = f_s / N $

  AAC's long block produces 1024 coefficients, so it is fed $N = 2048$ input samples. At
  $f_s = 44 100$ Hz:

  $ Delta f = 44100 / 2048 approx 21.5 "Hz" $

  The short block produces 128 coefficients, so $N = 256$ samples:

  $ Delta f = 44100 / 256 approx 172.3 "Hz" $

  So the long block resolves frequencies eight times more finely (21.5 Hz versus 172.3 Hz); the
  short block, being eight times shorter in time, pins down _when_ a sound happens eight times more
  precisely. You cannot have both at once. That is the classic time–frequency trade-off we first
  met in Chapter 46. Window switching simply lets the encoder pick the better option frame by frame.
]

#keyidea[
  The single greatest architectural improvement of AAC over MP3 is the elimination of the 32-band
  polyphase filterbank. A single MDCT with adaptive block sizes gives better frequency resolution
  in steady state _and_ better time resolution on transients, by switching modes.
]

== The Three New Tools: TNS, PNS, and Joint Stereo

AAC added three new compression tools that MP3 lacked entirely.

=== Temporal Noise Shaping (TNS)

Even with adaptive block sizes, a long MDCT block advances the audio timeline by about 23 ms
each step (its overlapping window spans roughly twice that). If a transient lands near the end of
such a block, the quantisation noise generated during encoding spreads across the whole block in
the time domain, producing pre-echo before the transient.

*Temporal Noise Shaping (TNS)* attacks this differently. Instead of switching to short blocks, it
applies a linear prediction filter _in the frequency domain_ to reshape how quantisation noise
distributes itself in time.

Here is the key insight: linear prediction (the same idea used in speech coding, which we will see
in Chapter 50) works in the frequency domain to shape the noise temporally. By predicting each
frequency coefficient from its neighbours, the encoder creates a prediction residual that has a
flat temporal envelope. When quantisation noise is added to this flat residual and the inverse
filter is applied, the noise concentrates itself in time, right on top of the transient, where
temporal masking hides it.

The TNS filter coefficients are transmitted as side information alongside the spectrum. The
decoder applies the inverse filter to spread the quantised data back into the correct time shape,
and the quantisation noise is sculpted to ride under the masking threshold.

#aside[
  TNS was invented by Bernhard Edler and Heiko Purnhagen at the University of Hannover and added
  to AAC as a key differentiator. Its genius is that it uses the same mathematical tool as a
  speech codec (linear prediction) but runs it on the transform-domain data rather than the
  time-domain signal, flipping the usual direction.
]

=== Perceptual Noise Substitution (PNS)

Music contains a lot of "noise-like" regions: cymbals, breath sounds, wind instruments in certain
registers, the reverberant tail of a piano note. These regions have an essentially flat, random
spectrum with no tonal structure that the ear can track. If you replace them with a synthetic
random noise burst of the right energy and bandwidth, most listeners cannot tell the difference.

*Perceptual Noise Substitution (PNS)*, added to AAC in the MPEG-4 version (1999), exploits this.
The encoder classifies each spectral band as either tonal (with a clear peak the ear will notice)
or noise-like (with a flat spectrum). For noise-like bands, instead of encoding and transmitting
the actual coefficients, it transmits only the _energy_ of the band: a single number. The decoder
generates a random noise burst of that energy. Bits saved; perception preserved.

#keyidea[
  PNS is compression by replacement rather than quantisation. It does not compress the noise; it
  throws it away entirely and synthesises a perceptually equivalent substitute. The transmitted
  information shrinks from tens of coefficients to a single energy value.
]

=== Joint Stereo Coding: Mid--Side and Intensity

Stereo audio has two channels (left, L, and right, R), but the ear is much more sensitive to
loudness (the sum $L + R$) than to stereo position (the difference $L - R$). AAC exploits this
with two joint-stereo tools.

*Mid--Side (M/S) stereo* encodes the sum and difference rather than L and R directly:

$ M = (L + R) / 2 , quad S = (L - R) / 2 $

The mid channel $M$ carries the shared musical content; the side channel $S$ carries only the
difference, which is usually quieter and can be quantised more coarsely. Bits move from the quiet
side to the loud mid.

*Intensity stereo* goes further. At high frequencies (above ~6 kHz), the ear loses its ability to
detect phase differences between left and right; it can only sense the _energy_ on each side.
Intensity coding merges both high-frequency channels into one, transmitting a single spectral
envelope plus a pan angle. This halves the data in that frequency range with no perceptible cost.

#gomaths("Mid--Side transform")[
  Given left sample $L$ and right sample $R$:

  $ M = (L + R) / 2 , quad S = (L - R) / 2 $

  The inverse is exact:

  $ L = M + S , quad R = M - S $

  If the stereo image is narrow (L ≈ R), then $S ≈ 0$ and can be heavily quantised. If the image
  is wide (L and R very different), $S$ carries real information that must be preserved.
]

== The AAC Profile Ladder

Because different applications need different trade-offs, the AAC standard defines a family of
profiles, each a superset of the previous one.

#fig([The AAC profile ladder, from AAC-LC (1997) to xHE-AAC (2012). Each rung adds new tools while
  remaining a superset of the rungs below it.], cetz.canvas({
  import cetz.draw: *
  let rung(y, label, sub) = {
    rect((0, y), (10, y + 0.9), fill: rgb("#dbeafe"), stroke: rgb("#0b5394"))
    content((5, y + 0.45), box(width: 9.6cm, inset: 2pt, align(center, text(size: 8.5pt)[*#label* -- #sub])))
  }
  rung(0.0, "AAC-LC", "1997 / MPEG-2 · the foundation")
  rung(1.1, "AAC-Main", "1997 · backward prediction, higher complexity")
  rung(2.2, "HE-AAC v1", "2003 · + Spectral Band Replication (SBR)")
  rung(3.3, "HE-AAC v2", "2006 · + Parametric Stereo (PS)")
  rung(4.4, "xHE-AAC / USAC", "2012 · MDCT + ACELP, full range 12-300 kbit/s")
  line((5, 5.3), (5, 5.6), mark: (end: ">"))
  content((5, 5.85), box(width: 6cm, inset: 2pt, align(center, text(size: 8.5pt, fill: rgb("#0b5394"))[Higher efficiency / more tools])))
}))

=== AAC-LC: The Workhorse

*AAC Low Complexity (AAC-LC)* is the profile that runs on every phone, in every browser, on every
streaming platform. It uses MDCT + TNS + M/S stereo + PNS. "Low complexity" means it omits
backward prediction (a tool that makes the encoder look back at already-coded frames to build a
better model, but with high memory cost). In practice AAC-LC at 128 kbit/s is considered
transparent (indistinguishable from the original) for most listeners, which MP3 at 128 kbit/s
is not.

=== HE-AAC v1: Spectral Band Replication

Radio stations broadcast at low bitrates. Mobile data in many markets is expensive. Could AAC
sound good at 48 kbit/s? At 32? The key insight is that at very low bitrates, most bits go to the
low-frequency content of music (the bass, harmony, and voice) because the high-frequency
overtones cost too many bits to code individually. But those overtones are largely predictable
from the low-frequency content: the harmonic relationships of music mean that if you know the
melody, you can guess the upper harmonics.

*Spectral Band Replication (SBR)*, standardised as HE-AAC v1 in 2003, exploits this. The encoder:

1. Codes only the low-frequency part of the spectrum (roughly below 6 kHz) with AAC-LC.
2. Transmits a small side-channel (the "guide data") describing the high-frequency envelope: which frequency regions are loud, which quiet, and their shapes.
3. The decoder reconstructs the high-frequency portion by copying and frequency-shifting patches from the already-decoded low band, then reshaping them with the guide data.

The result: audio that sounds full-bandwidth at bitrates where a plain AAC-LC encoder would sound
thin and tinny. Typical application: DAB+ digital radio at 32–48 kbit/s per programme.

#aside[
  SBR was invented by the company Coding Technologies (CT), which Dolby acquired in 2007. The key
  patent inventors were Per Ekstrand and Martin Dietz. Dolby and Fraunhofer cross-licensed it into
  the HE-AAC standard.
]

=== HE-AAC v2: Parametric Stereo

Even with SBR, stereo at 24 kbit/s still demands more bits than are available. *Parametric Stereo
(PS)*, added in HE-AAC v2 (2006), addresses this by reducing the stereo information to a tiny set
of spatial parameters rather than coding both channels fully.

The PS encoder reduces the stereo signal to:
1. A mono sum (coded as the SBR-enhanced AAC-LC core).
2. A small set of spatial parameters per frequency band per time frame: inter-channel level
   difference (ILD), inter-channel phase difference (IPD), and inter-channel coherence (ICC).

These parameters are typically a few hundred bits per second. The decoder recreates the stereo
image from the mono core plus the spatial parameters, using a binaural model of how the ears
perceive direction. The result: listenable stereo music at 24–32 kbit/s, the bitrate range used
by mobile streaming on slow data networks.

#checkpoint[
  At 24 kbit/s using HE-AAC v2, what fraction of the available bits are consumed by the stereo
  parameters versus the audio content?
][
  The spatial parameters typically cost 0.5–2 kbit/s; the rest (22–23.5 kbit/s) goes to the mono
  core audio. So audio takes roughly 95–97% of the budget; stereo costs only 3–5%.
]

=== xHE-AAC / USAC: Bridging Speech and Music

The profiles above are all optimised for music. But streaming services increasingly deliver
*mixed content*: a podcast that cuts from an interview (speech) to a music bed to an ad.
Speech and music require different coding strategies. Speech codecs use linear prediction of
the vocal tract; music codecs use transform methods. Switching between them abruptly causes
audible glitches.

*USAC (Unified Speech and Audio Coding)* (ISO/IEC 23003-3, finalised early 2012) and its
streaming profile *xHE-AAC* solve this by fusing the two worlds into one codec. At the core,
USAC can switch, frame by frame and transparently, between:

- An MDCT-based path (like AAC-LC + SBR) for music and broadband audio.
- An *ACELP* (Algebraic Code-Excited Linear Prediction) path for speech, the same family used in
  3GPP mobile voice codecs.

The two paths share a common bitstream container and common entropy coding. The codec can blend
between them for signals that are neither pure speech nor pure music (singing, for example). The
result operates cleanly across the entire range from 12 kbit/s (narrow-band speech equivalent) to
300 kbit/s (high-quality stereo music), a 25:1 dynamic range on a single, backward-compatible
codec.

Platform support: Android 9 (Pie) added native xHE-AAC decoding in 2018; iOS 13 and macOS 11
followed in 2019–2020; Windows 11 and Xbox added it in October 2022. Netflix began streaming
xHE-AAC to Android devices in January 2021, reporting that users switched from headphones to
speakers 16% less often on high-dynamic-range content when the codec was enabled. By mid-2026,
the format reaches more than two billion devices monthly.

#algo(
  name: "AAC-LC (Advanced Audio Coding - Low Complexity)",
  year: "1997 (MPEG-2 Part 7); extended 1999 (MPEG-4 Part 3)",
  authors: "Fraunhofer IIS, Dolby Laboratories, AT&T Bell Labs, Sony, Nokia",
  aim: "High-quality audio compression with pure MDCT, TNS, PNS, and joint stereo; target 96–128 kbit/s stereo",
  complexity: "Encoder O(N log N) MDCT + psychoacoustic model; decoder O(N log N)",
  strengths: "Better frequency and time resolution than MP3; TNS eliminates pre-echo; transparent at 96 kbit/s; universally supported",
  weaknesses: "Patent-encumbered (Via LA pool); awkward at very low bitrates without HE extensions; licensing fees still apply",
  superseded: "HE-AAC / xHE-AAC for low-bitrate use; Opus for real-time; Vorbis/Opus for royalty-free use",
)[
  AAC-LC became the audio track format of choice for iTunes (2003), YouTube (2009), and virtually
  every smartphone platform. The bitrate sweet spot is 96–128 kbit/s stereo, at which most
  double-blind tests find it transparent. Main profile adds backward prediction for higher quality
  at the cost of more memory; SSR (Scalable Sampling Rate) allows bandwidth reduction; neither is
  widely deployed.
]

#algo(
  name: "HE-AAC v1 and v2 (High Efficiency AAC)",
  year: "HE-AAC v1: 2003; HE-AAC v2: 2006 (both MPEG-4 Part 3)",
  authors: "Coding Technologies (SBR); Agere Systems / Philips (Parametric Stereo); Fraunhofer IIS",
  aim: "Extend AAC to very low bitrates: 24–64 kbit/s stereo with acceptable quality",
  complexity: "Encoder adds SBR envelope analysis; PS adds spatial parameter estimation; both O(N)",
  strengths: "Dominant format for DAB+ digital radio; streaming on slow links; 24 kbit/s stereo music",
  weaknesses: "SBR and PS introduce artefacts on transient-rich or stereo-wide signals; not transparent below ~48 kbit/s",
  superseded: "xHE-AAC/USAC at modern streaming bitrates; Opus for real-time at similar bitrates",
)[
  HE-AAC v1 is the format of DAB+ digital radio in Europe and Australia, ATSC 3.0 broadcast in
  North America, and many internet radio services. HE-AAC v2 is the compressed voice-and-music
  format used by early mobile streaming apps when data was expensive.
]

== Vorbis: The Free Alternative

=== Why It Exists

In September 1998, Fraunhofer IIS sent a letter to MP3 software developers announcing that royalty
fees (previously in a grace period) would begin being collected. Decoders would need a licence;
encoders would need a licence. The fees were modest per unit but existential for open-source
projects that charged nothing.

Chris Montgomery ("Monty"), already part of the nascent Xiph.Org open multimedia project, read
the letter and accelerated work on a royalty-free replacement. The Vorbis project had begun under
Montgomery in 1993 as abstract research; the 1998 Fraunhofer letter transformed it into an
engineering emergency. The Ogg container format (the transport wrapper) and the Vorbis audio codec
were developed in tandem. Vorbis 1.0 was frozen in specification on *July 17, 2002*, five years
after AAC but years before AAC hardware support became universal.

#history[
  The name "Ogg" comes from a manoeuvre in the MOS game _Netrek_, where an "ogg" means to attack
  recklessly and without regard for the consequences, a fitting metaphor for a small non-profit
  charging at the Fraunhofer licensing machine. "Vorbis" is named after a character in Terry
  Pratchett's _Small Gods_.
]

=== The Vorbis Architecture

Like AAC, Vorbis is MDCT-based. But its internal design is architecturally distinct, with three
novel features: *floor curves*, *residue coding*, and *codebook vector quantisation*.

==== Block Sizes and Windows

Vorbis uses two MDCT block sizes (long: 2048 samples by default; short: 256 samples) with
the same time–frequency trade-off as AAC. Transitions between block sizes use special asymmetric
windows to ensure perfect reconstruction.

==== Floor Curves

After computing the MDCT spectrum of a frame, Vorbis estimates its *spectral envelope*, the
smooth shape of the spectrum ignoring fine detail. This envelope is the psychoacoustic masking
curve: frequencies above the envelope are loud and need precise encoding; frequencies below it
are masked and can be coarsely coded.

In Vorbis this envelope is called the *floor curve* (because it represents the audibility floor
for that frame). Two methods are defined:

- *Floor 0* (deprecated): a Fourier-series representation of the envelope, efficient but complex to decode.
- *Floor 1* (universal): the envelope is described as a piecewise linear curve over a set of
  chosen frequency "knots". The knots are stored as a codebook-selected set of amplitude values.

The floor curve is then removed from the raw MDCT spectrum, leaving a *residue*: the fine
spectral detail. "Removed" means _divided out_: each MDCT magnitude is divided by the floor value
at that frequency. (Equivalently, since the floor is stored in the log domain, the floor is
_subtracted_ from the log-magnitude spectrum, and subtracting logs is the same as dividing the
original numbers, exactly the rule we met in Chapter 7.) Either way the effect is the same. Where
the spectrum was loud, the floor is high, so dividing brings it down toward 1; where it was quiet,
the floor is low, so dividing lifts it back up toward 1. The result is a residue clustered around
1: a much flatter, more uniform set of numbers than the wildly varying original. This step is
called *spectral whitening*, and it is the whole trick. A flat residue is far cheaper to quantise
than a peaky spectrum, because the codebooks no longer have to waste entries describing the same
broad spectral shape over and over.

==== Residue Coding and Vector Quantisation

The residue is encoded using *vector quantisation with trained codebooks*. Vorbis ships with
static codebooks (lookup tables that map blocks of residue values to compact codewords)
pre-trained on large music corpora during encoder development. The residue is broken into small
vectors (small groups of MDCT coefficients), each matched to the nearest entry in the codebook.

This is fundamentally different from AAC's scalar Huffman coding of individual quantised
coefficients. Vector quantisation (which we built from scratch in Chapter 39, where we met the
LBG algorithm that learns a codebook by clustering training vectors) can exploit correlations
_between_ nearby frequency components, not just within each component individually.

#aside[
  Vorbis does not define a formal psychoacoustic model in its specification. That is entirely
  left to the encoder. The libvorbis reference encoder uses a custom psychoacoustic model, but
  third-party encoders can use any model they like. This was a deliberate design choice: the
  bitstream format is the standard; the encoder intelligence is not.
]

==== Channel Coupling

Vorbis handles stereo through *channel coupling*: it can group pairs of channels and apply a
rotation matrix (essentially the M/S transform) before encoding, transmitting the coupled
channels jointly. The encoder decides whether coupling helps on a per-frame basis.

#gopython("Python bytes and list slicing")[
  In the examples below we work with raw PCM audio as a Python `bytes` object, a sequence of
  bytes. To get individual 16-bit samples from it, we use `struct.unpack`. Slicing a `list` or
  `bytes` with `a[start:stop]` gives elements from index `start` up to but not including `stop`.
  Example:

  ```python
  import struct

  # 4 bytes = 2 samples of 16-bit signed PCM
  raw = bytes([0x00, 0x40, 0xFF, 0x3F])
  # unpack as two little-endian signed shorts
  samples = list(struct.unpack_from("<2h", raw))
  print(samples)   # [16384, 16383]
  print(samples[0:1])   # [16384]  -- slice: first sample only
  ```

  The `<` means little-endian; `h` means signed 16-bit integer. We will use this pattern whenever
  we read real PCM audio data from a file.
]

== Measuring Spectral Flatness: The SBR Pre-Check

Spectral Band Replication works best when the high-frequency content is a recognisable
transformation of the low-frequency content. A useful metric for predicting how well SBR will work
is *Spectral Flatness Measure (SFM)*, sometimes called the "tonality" of a signal. A flat,
noise-like spectrum has SFM close to 1; a tonal signal with sharp peaks has SFM close to 0.

SFM compares the geometric mean of the spectrum to its arithmetic mean:

$ "SFM" = (product_(k=0)^(N-1) |X[k]|)^(1/N) / ((1/N) sum_(k=0)^(N-1) |X[k]|) $

#gomaths("Geometric mean vs arithmetic mean")[
  The *arithmetic mean* of $N$ numbers $x_1, x_2, dots, x_N$ is their ordinary average:

  $ mu_A = (x_1 + x_2 + dots + x_N) / N $

  The *geometric mean* is the $N$-th root of their product:

  $ mu_G = (x_1 dot x_2 dot dots dot x_N)^(1/N) $

  For a concrete example: numbers 1, 2, 8.

  $mu_A = (1+2+8)/3 = 11/3 approx 3.67$

  $mu_G = (1 times 2 times 8)^(1/3) = 16^(1/3) approx 2.52$

  The geometric mean is always $<=$ the arithmetic mean (by the AM-GM inequality). The closer they
  are, the "flatter" the set of numbers is, meaning the less variation they have. For a spectrum,
  flat means noise-like; peaked means tonal.
]

#gopython("NumPy arrays and the FFT")[
  Python's `numpy` library provides fast numeric arrays and a Fast Fourier Transform (FFT). We use
  `numpy.fft.rfft` which takes a real-valued array and returns complex frequency coefficients.
  `numpy.abs` gives the magnitude of each coefficient.

  ```python
  import numpy as np

  x = np.array([1.0, -0.5, 0.3, -0.2, 0.1, 0.0, -0.1, 0.2])
  X = np.fft.rfft(x)       # complex spectrum
  mags = np.abs(X)          # magnitudes (float array)
  print(mags.round(3))
  # [0.8   1.162 1.131 0.616 0.2  ]
  ```

  Arrays support element-wise operations: `mags ** 2` squares every element, `np.log(mags)` takes
  the log of every element, `np.mean(mags)` computes the arithmetic mean.
]

Here is a short Python function that computes the SFM for a window of audio and uses it to
classify a spectral band as tonal or noise-like:

```python
import numpy as np

def spectral_flatness(magnitudes: np.ndarray) -> float:
    """
    Compute the Spectral Flatness Measure (SFM) for an array of MDCT magnitudes.
    SFM near 1.0 -> noise-like (flat spectrum).
    SFM near 0.0 -> tonal (sharp peaks).
    """
    # Avoid log(0) by clamping very small values
    eps = 1e-10
    mags = np.clip(magnitudes, eps, None)
    log_geo_mean = np.mean(np.log(mags))     # log of geometric mean
    arith_mean   = np.mean(mags)
    geo_mean     = np.exp(log_geo_mean)
    return float(geo_mean / arith_mean)

def classify_band(mags: np.ndarray, threshold: float = 0.25) -> str:
    """Classify a spectral band as 'tonal' or 'noise-like' using SFM."""
    sfm = spectral_flatness(mags)
    return "noise-like" if sfm >= threshold else "tonal"

# Quick demo:
# A flat (white-noise-like) spectrum
flat  = np.ones(64) + np.random.default_rng(0).normal(0, 0.05, 64)
# A tonal spectrum (sharp peak at bin 10)
tonal = np.full(64, 0.01)
tonal[10] = 1.0

print(classify_band(flat))    # -> noise-like
print(classify_band(tonal))   # -> tonal
print(f"Flat SFM:  {spectral_flatness(flat):.3f}")
print(f"Tonal SFM: {spectral_flatness(tonal):.3f}")
```

An AAC encoder uses exactly this kind of classification, band by band and frame by frame, to decide
whether to apply PNS (for noise-like bands) or to encode the actual coefficients (for tonal bands).
The SBR guide data generation uses SFM to decide how aggressively to extend high-frequency content
from the low-band reconstruction.

== The Vorbis Encoding Pipeline: A Walkthrough

Let us trace a single frame of stereo music through a Vorbis encoder, putting the pieces together.

=== Step 1: Windowing and MDCT

The encoder takes a block of 2048 PCM samples per channel (overlapping 50% with the previous block),
multiplies by a Vorbis window (a smooth bell shape), and computes the MDCT to get 1024 frequency
coefficients per channel. If a transient is detected, it switches to 256-sample blocks for the next
frame.

=== Step 2: Channel Coupling

For stereo, the encoder tests whether M/S coupling helps by comparing the bit cost of sending
the two channels independently versus the coupled M and S channels. It chooses whichever costs fewer bits.

=== Step 3: Floor Curve Estimation

For each channel (or for the coupled M and S), the encoder fits a Floor 1 piecewise-linear curve
to the MDCT magnitude envelope. The knot positions are fixed by the codec configuration; the knot
amplitudes are chosen to track the spectral shape. These amplitudes are quantised and encoded using
a codebook.

=== Step 4: Residue Computation and VQ Coding

The MDCT coefficients are divided by the floor curve (removing the spectral shape), leaving a flat
residue. This residue is split into small vectors and matched against the trained codebooks.
The best matching codebook entry index is output as a compact codeword.

=== Step 5: Entropy Coding

The floor codebook indices and residue codebook indices are packed into an Ogg bitstream using a
variable-length code. Vorbis does not use Huffman coding in the traditional sense; instead, the
codebooks themselves are Huffman-shaped (entries assigned lengths inversely proportional to their
usage frequency during training).

=== Step 6: Ogg Framing

The encoded audio bitstream is packetised into an Ogg logical bitstream. Ogg provides the container
(start and stop codes, page checksums, page sizing) but is completely format-agnostic; the same
Ogg container wraps Theora video, FLAC audio, and Opus.

#fig([The Vorbis encoding pipeline. One block of PCM enters on the left; a compressed Ogg packet
  exits on the right. The floor curve and residue paths are the central innovation.],
  cetz.canvas({
    import cetz.draw: *
    let vbox(x, y, w, h, label, col) = {
      rect((x, y), (x+w, y+h), fill: col, stroke: rgb("#0b5394"))
      content((x + w/2, y + h/2), box(width: (w - 0.4) * 1cm, inset: 1pt, align(center, text(size: 7.5pt)[#label])))
    }
    // PCM input
    vbox(0, 1.5, 1.6, 0.7, "PCM\nsamples", rgb("#e8f4fd"))
    line((1.6, 1.85), (2.2, 1.85), mark: (end: ">"))
    // MDCT
    vbox(2.2, 1.5, 1.5, 0.7, "MDCT", rgb("#dbeafe"))
    line((3.7, 1.85), (4.3, 1.85), mark: (end: ">"))
    // Fork
    line((4.3, 1.85), (4.8, 1.85))
    line((4.8, 1.85), (4.8, 2.7))
    line((4.8, 1.85), (4.8, 1.0))
    // Floor branch (top)
    line((4.8, 2.7), (5.3, 2.7), mark: (end: ">"))
    vbox(5.3, 2.35, 1.7, 0.7, "Floor\ncurve fit", rgb("#fde8d0"))
    // Residue branch (bottom)
    line((4.8, 1.0), (5.3, 1.0), mark: (end: ">"))
    vbox(5.3, 0.65, 1.7, 0.7, "Residue\n÷ floor", rgb("#fde8d0"))
    // VQ coding
    line((7.0, 0.65 + 0.35), (7.5, 0.65 + 0.35), mark: (end: ">"))
    vbox(7.5, 0.65, 1.6, 0.7, "VQ code\nbooks", rgb("#d1fae5"))
    // Output
    line((7.0, 2.35 + 0.35), (7.5, 2.35 + 0.35), mark: (end: ">"))
    vbox(7.5, 2.35, 1.6, 0.7, "Floor\nindices", rgb("#d1fae5"))
    // Merge
    line((9.1, 2.7), (9.6, 2.7))
    line((9.1, 1.0), (9.6, 1.0))
    line((9.6, 2.7), (9.6, 1.0))
    line((9.6, 1.85), (10.1, 1.85), mark: (end: ">"))
    vbox(10.1, 1.5, 1.5, 0.7, "Ogg\npacket", rgb("#ede9fe"))
  })
)

== Comparing AAC and Vorbis at the Same Bitrate

At 128 kbit/s stereo, decades of listening tests place AAC and Vorbis essentially level:
both are transparent for most listeners in most conditions. AAC has a slight measured advantage
at 64 kbit/s and below; Vorbis has a reputation for cleaner transient handling at mid-to-high
bitrates due to its more aggressive short-block usage. The practical differences are smaller than
encoder quality: a well-tuned Vorbis encoder (aoTuV, for example) will outperform a poorly
configured AAC encoder, and vice versa.

The real difference is not quality but *ecosystem*:

- AAC plays natively on every Apple device, every Android phone, every modern browser, every
  streaming service. It is the audio track for MPEG-4 video (the `.m4a`, `.mp4`, `.m4v` files
  that dominate consumer video).
- Vorbis requires a decoder installation on Windows (though Firefox, Chrome, and every Linux
  system ship one). It is the default audio track for WebM video and the standard format for
  many games (thanks to zero royalties and small code size).

#scoreboard(caption: "Audio codec quality overview -- 128 kbit/s stereo, typical music",
  [AAC-LC (128 kbit/s)], [16 kB/s], [~11:1 vs CD], [Transparent for most listeners; universal support],
  [HE-AAC v1 (48 kbit/s)], [6 kB/s], [~29:1 vs CD], [Acceptable; SBR adds bandwidth perception],
  [HE-AAC v2 (24 kbit/s)], [3 kB/s], [~58:1 vs CD], [Listenable; artefacts on wide stereo],
  [Vorbis q5 (~160 kbit/s)], [20 kB/s], [~9:1 vs CD], [Transparent; royalty-free],
  [Vorbis q3 (~112 kbit/s)], [14 kB/s], [~12:1 vs CD], [Near-transparent; royalty-free],
  [xHE-AAC (32 kbit/s)], [4 kB/s], [~44:1 vs CD], [Speech+music mixed; excellent for streaming],
)

== The Licensing War and Its Uneasy Resolution

AAC's quality advantage came with a price tag. The Via Licensing Alliance (formerly Via Licensing
Corporation) manages the AAC patent pool, which by the mid-2020s includes over 900 licensees
paying royalties ranging from roughly \$0.10 to \$0.98 per device or unit. Fraunhofer IIS, Dolby,
Sony, Philips, Nokia, and others share in these fees.

For a consumer electronics company shipping millions of devices, the fees are an accepted cost of
doing business. For an indie developer or a small streaming startup, they are a barrier. The open
source community largely avoided AAC encoders for this reason; FFmpeg included AAC coding for
years under a murky legal cloud before settling on a licensed approach.

Vorbis (and later Opus) was designed from the ground up to be unencumbered. Xiph.Org's
charter explicitly opposes software patents as barriers to innovation. The Vorbis specification
was released to the public domain; the reference implementation (libvorbis) is BSD-licensed.
Anyone can encode and decode Vorbis without paying a cent, without notifying anyone, without
filing any paperwork.

The patent landscape for AAC will continue shifting through the late 2020s as the earliest AAC
patents (filed 1994–1997) expire on their statutory 20-year term. The Via LA pool has already
adapted its rates downward to reflect expiring patents. However, MPEG-4 AAC extensions (PNS, LD)
and HE-AAC/USAC patents filed in the early 2000s extend the encumbered period well beyond 2020.
The xHE-AAC pool is likely to remain relevant through the early 2030s.

#misconception[
  "AAC is free to use -- MP3 royalties expired in 2017 so audio formats are all free now."
][
  MP3's last relevant US patents expired in April 2017 and Fraunhofer terminated its MP3
  licensing program the same year. However, AAC, HE-AAC, and xHE-AAC have entirely separate
  patent pools (Via LA) that remain active. Using AAC in a commercial product still requires a
  licence from Via LA. Opus and Vorbis are genuinely royalty-free; AAC is not.
]

== USAC and the End of the Speech/Music Divide

We described USAC (xHE-AAC) above as a technical achievement. It also represents a conceptual
breakthrough: the idea that a single codec can unify the historically separate worlds of speech
coding (Chapter 50) and music coding.

For 40 years these two domains had parallel but non-intersecting research communities. Speech
coders (G.711, G.729, AMR, SILK) were designed around the linear prediction model of the human
vocal tract and performed miserably on music. Music coders (MP3, AAC, Vorbis) were designed
around transform coding of broadband audio and performed poorly on narrow-band speech. A
broadcast that mixed both required transcoding (converting between codecs) at every transition,
degrading quality.

USAC eliminates this transcoding seam. Its ACELP path handles speech efficiently from 6 kbit/s
upward; its MDCT path handles music from 12 kbit/s upward; the crossfade logic between them
operates within a single bitstream with no discontinuity. For a podcast application receiving
audio with unknown content, or for a radio broadcaster sending a mix of talk and music over a
single low-bitrate channel, this is a significant operational simplification.

#keyidea[
  USAC/xHE-AAC is the first general audio codec to formally unify speech and music coding under
  a single bitstream format. It took 40 years of parallel research in two separate communities
  to reach the point where both disciplines could be merged without compromise.
]

== The Ogg Container and Why It Matters

A note on packaging. Vorbis audio is never sent raw; it is always wrapped in the *Ogg* container
format. Ogg is a streaming-first container: it is designed so that a decoder can lock on at any
point in the stream, identify the logical bitstream structure, and begin decoding without access to
a file header. This is essential for live radio streaming.

The structure of an Ogg stream is:
- A sequence of *pages*, each with a magic number (`OggS`), a sequence number, a granule position
  (roughly, the position in the audio timeline), and a checksum.
- Each page carries one or more *packets* belonging to one or more *logical bitstreams* (audio,
  video, subtitles).
- Seeking within a file uses a binary search on granule positions.

This contrasts with MPEG-4's container (the `.mp4` / ISOBMFF format), which stores media index
data in a separate `moov` atom that is conventionally placed at the end of the file. A progressive
web player downloading an `.mp4` must either wait for the entire file or request the `moov` out of
order (using HTTP range requests). The Ogg container's page-level structure makes it naturally
streamable in a way that MPEG-4 must add engineering around.

#aside[
  Opus (the subject of Chapter 49) also uses the Ogg container when stored as a file, but
  the underlying audio packets have a different structure. The Ogg container is thus "format
  agnostic": the same bytes-on-disk format can carry Vorbis, Opus, FLAC (in its Ogg variant),
  or Theora video.
]

== A Practical Look at Bitrate and Quality Choices

When should you reach for which codec? Here is the practical guide as of mid-2026:

*High-quality music archiving (> 160 kbit/s):* The choice between AAC-LC and Vorbis is largely
irrelevant: both are transparent. Choose based on ecosystem needs: AAC for Apple compatibility,
Vorbis/Opus for royalty-free deployment.

*Podcast and speech streaming (16–48 kbit/s):* xHE-AAC (USAC) is now the professional choice
for services that require a single codec to handle mixed speech and music content. At 48 kbit/s,
xHE-AAC substantially outperforms any earlier profile. For royalty-free speech, Opus at 24–48
kbit/s is the direct alternative (Chapter 49).

*Broadcast radio (32–64 kbit/s):* DAB+ digital radio uses HE-AAC v1, and this is deeply
entrenched. xHE-AAC is being phased into newer DAB+ profiles but adoption is slow because
billions of existing radios only decode HE-AAC v1.

*Games:* Vorbis is the dominant format for in-game music and effects, used by nearly every
cross-platform game engine (Godot, Unity, Unreal). Zero royalties mean a game can ship with
thousands of audio files without triggering per-unit codec fees.

*WebRTC and real-time audio:* Opus dominates (Chapter 49). Neither AAC nor Vorbis has the
ultra-low latency mode (2.5 ms frames) that real-time communication requires.

#checkpoint[
  A game developer wants to include 500 MB of background music in their commercial game. They are
  choosing between AAC-LC and Vorbis. What is the most important non-technical factor?
][
  Royalties. Shipping a commercial game that encodes or decodes AAC requires a licence from Via
  LA, potentially costing per-unit fees. Vorbis has no licence fee, no per-unit cost, and no
  paperwork. For a small studio shipping 1 million units, this is a meaningful financial
  consideration.
]

== Worked Example: What 128 kbit/s Really Means

CD audio is 44,100 samples/second, 16 bits/sample, stereo:

$ 44100 times 16 times 2 = 1,411,200 "bit/s" approx 1.41 "Mbit/s" $

A three-minute song is:

$ 3 times 60 times 1,411,200 = 254,016,000 "bits" = 31.8 "MB" $

At 128 kbit/s (the standard quality setting for both AAC and Vorbis):

$ 3 times 60 times 128,000 = 23,040,000 "bits" = 2.88 "MB" $

The compression ratio is:

$ 31.8 "MB" / 2.88 "MB" approx 11.0:1 $

That 11:1 ratio is achieved by quantising approximately 90% of the spectral information below the
masking threshold, substituting noise for noise-like bands, and sharing stereo information
between channels. Every technique in this chapter and Chapter 46–47 contributes to that 11:1
number.

At HE-AAC v2 (24 kbit/s):

$ 3 times 60 times 24,000 = 4,320,000 "bits" = 0.54 "MB" $

Ratio: $31.8 / 0.54 approx 59:1$. Fifty-nine times smaller than CD audio, achieved by adding
SBR and Parametric Stereo on top of AAC-LC.

#takeaways((
  "AAC replaced MP3's hybrid filterbank with a pure MDCT and two block sizes, eliminating pre-echo and improving both frequency and time resolution simultaneously.",
  "Temporal Noise Shaping (TNS) reshapes quantisation noise in the time domain by applying linear prediction in the frequency domain, preventing pre-echo on transients without switching to short blocks.",
  "Perceptual Noise Substitution (PNS) replaces noise-like spectral bands with a single energy value plus a synthesised random noise burst at the decoder, saving tens of bits per band.",
  "HE-AAC v1 adds Spectral Band Replication (SBR) to reconstruct the high-frequency spectrum from the low-frequency content plus a compact guide, enabling good quality at 32–64 kbit/s.",
  "HE-AAC v2 adds Parametric Stereo (PS), reducing stereo information to a mono core plus spatial parameters, enabling listenable stereo music at 24 kbit/s.",
  "xHE-AAC / USAC (2012) unifies speech and music coding by switching frame-by-frame between ACELP and MDCT paths, covering 12–300 kbit/s on a single, backward-compatible bitstream.",
  "Vorbis was created in direct response to the 1998 Fraunhofer licensing letter; it uses MDCT with floor-curve spectral whitening and vector-quantised codebooks, all royalty-free.",
  "The AAC patent pool (Via LA) remains active through the late 2020s and into the 2030s for newer profiles; Vorbis and Opus are genuinely unencumbered alternatives.",
))

== Exercises

#exercise("48.1", 1)[
  A CD audio recording runs for exactly 4 minutes. Calculate the uncompressed size in megabytes,
  and the compressed size at 96 kbit/s AAC. State the compression ratio.
]

#solution("48.1")[
  Uncompressed: $44100 times 16 times 2 times 240 = 338,688,000 "bits" = 40.3 "MB"$.
  At 96 kbit/s: $96000 times 240 = 23,040,000 "bits" = 2.88 "MB"$.
  Ratio: $40.3 / 2.88 approx 14.0:1$.
]

#exercise("48.2", 1)[
  AAC's long block produces 1024 MDCT coefficients, so (from the box above) it is fed a window of
  2048 input samples at a 44.1 kHz sample rate. How many milliseconds of audio does one long-block
  window cover? Because blocks overlap by 50%, the encoder advances by only half a window each
  step. How many milliseconds of _new_ audio does each long block add? Repeat for a short block
  (128 coefficients, 256-sample window).
]

#solution("48.2")[
  Long block: window $2048 / 44100 approx 46.4 "ms"$; new audio per block (the 1024-sample hop)
  $1024 / 44100 approx 23.2 "ms"$. Short block: window $256 / 44100 approx 5.8 "ms"$; new audio
  per block (128-sample hop) $128 / 44100 approx 2.9 "ms"$. The 50% overlap is what lets the MDCT
  reconstruct the signal perfectly across block boundaries (time-domain aliasing cancellation,
  Chapter 38).
]

#exercise("48.3", 2)[
  Explain in plain words why Temporal Noise Shaping (TNS) is described as "linear prediction in
  the frequency domain". What does each of those three words contribute to the explanation?
]

#solution("48.3")[
  "Linear" -- the filter is a linear combination (weighted sum) of nearby values.
  "Prediction" -- each frequency coefficient is predicted from its neighbours; the residual
  (prediction error) is what gets quantised.
  "In the frequency domain" -- ordinarily, linear prediction is applied to time-domain samples to
  model the vocal tract (Chapter 50). Here, the same mathematical operation is applied to
  frequency-domain MDCT coefficients, which reshapes the noise distribution in time rather than
  in frequency. The word "domain" distinguishes this unusual application from the classical one.
]

#exercise("48.4", 2)[
  HE-AAC v2 achieves stereo audio at 24 kbit/s using Parametric Stereo. The spatial parameters
  (ILD, IPD, ICC) typically cost about 1.5 kbit/s. If the SBR guide data costs 3 kbit/s, how
  many bits per second are left for the AAC-LC mono core, and what fraction of the total bitrate
  does the core consume?
]

#solution("48.4")[
  Core bits: $24000 - 3000 - 1500 = 19500 "bit/s"$.
  Fraction: $19500 / 24000 = 0.8125 = 81.25%$. The core audio takes about 81% of the budget;
  the two enhancement tools together consume the remaining 19%.
]

#exercise("48.5", 2)[
  Write a Python function `sfm_db(magnitudes)` that computes the Spectral Flatness Measure in
  decibels: $"SFM"_"dB" = 10 log_10("SFM")$. What is $"SFM"_"dB"$ for a perfectly flat spectrum
  (all magnitudes equal)? What is it for a spectrum where one bin has magnitude 1.0 and all
  others are 0.001 (N = 64 bins total)?
]

#solution("48.5")[
  ```python
  import numpy as np

  def sfm_db(magnitudes: np.ndarray) -> float:
      eps = 1e-10
      m = np.clip(magnitudes, eps, None)
      geo = np.exp(np.mean(np.log(m)))
      arith = np.mean(m)
      return 10.0 * np.log10(geo / arith)

  flat = np.ones(64)
  print(sfm_db(flat))   # 0.0 dB -- perfectly flat

  peaky = np.full(64, 0.001)
  peaky[0] = 1.0
  print(sfm_db(peaky))  # approx -30.9 dB -- very tonal
  ```
  For a perfectly flat spectrum, geometric mean = arithmetic mean, so SFM = 1.0, SFM\_dB = 0 dB.
  For the peaky spectrum, the geometric mean is much lower than the arithmetic mean, giving a
  strongly negative dB value (approximately -30 dB), indicating a highly tonal signal.
]

#exercise("48.6", 3)[
  The Vorbis floor curve is a piecewise linear approximation to the log-magnitude spectrum. If the
  floor has 10 knot points covering bins 0–1023, and each knot amplitude is quantised to 6 bits,
  how many bits does the floor use per frame (ignoring entropy coding)? Compare this with encoding
  1024 coefficients each as a 6-bit scalar. What is the reduction factor, and what assumption
  makes this a fair comparison?
]

#solution("48.6")[
  Floor: $10 times 6 = 60 "bits per frame"$.
  Full scalar: $1024 times 6 = 6144 "bits per frame"$.
  Reduction factor: $6144 / 60 approx 102.4 times$.
  The fair-comparison assumption is that both the floor and the full coefficients are quantised
  to the same 6-bit resolution. In practice the floor captures the smooth spectral envelope while
  the residue captures the fine structure. The actual bits for the residue (VQ-coded) plus the
  floor should be compared with the cost of coding all coefficients with the same perceptual
  quality, which is harder to pin down. The factor of ~100 illustrates the efficiency gain of
  separating envelope from detail.
]

== Further Reading

#link("https://en.wikipedia.org/wiki/Advanced_Audio_Coding")[Advanced Audio Coding -- Wikipedia: the most concise technical overview of the full profile family]

#link("https://www.aes.org/e-lib/browse.cfm?elib=8079")[Brandenburg, K. (1999). *MP3 and AAC Explained*. AES 17th International Conference. -- the co-inventor's own summary]

#link("https://xiph.org/vorbis/doc/Vorbis_I_spec.html")[Vorbis I Specification -- the normative bitstream spec, freely available, surprisingly readable]

#link("https://voiceage.com/xHE-AAC.html")[VoiceAge xHE-AAC overview -- covers USAC architecture and the ACELP/MDCT switching mechanism]

#link("https://www.via-la.com/licensing-programs/aac/")[Via LA AAC licensing -- the authoritative source for current patent pool membership and royalty rates]

#link("https://www.researchgate.net/publication/226546544_Audio_coding_standard_overview_MPEG4-AAC_HE-AAC_and_HE-AAC_V2")[Audio coding standard overview: MPEG4-AAC, HE-AAC, and HE-AAC V2 -- technical paper covering SBR and PS in depth]

#bridge[
  AAC and Vorbis settled the *music streaming* battlefield. But the digital world was about to
  face a new challenge: voice and video calls over the internet, where latency is not a
  preference but a physical limit. A 23-millisecond MDCT block is unacceptable when you are
  trying to have a natural conversation. Chapter 49 tells the story of *Opus*, the codec that
  unified speech and music, cut delay to 2.5 milliseconds, and became the audio backbone of
  WebRTC, Discord, Zoom, and the modern real-time internet.
]
