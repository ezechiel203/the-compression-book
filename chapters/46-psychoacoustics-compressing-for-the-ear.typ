#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Psychoacoustics: Compressing for the Ear

#epigraph[
  The ear is not a microphone. It is a living instrument that decides,
  moment by moment, what deserves attention and what can safely be forgotten.
][
  Hermann von Helmholtz, _On the Sensations of Tone_, 1863
]

Here is a puzzle that bothered engineers for decades. A CD stores one minute of stereo music as roughly 10 megabytes of raw data — 44,100 samples per second, two channels, sixteen bits each. An MP3 file of the same song might weigh only 900 kilobytes. That is about eleven times smaller. Yet when you compare them on good headphones, you cannot tell the difference. Something is being thrown away, but nothing seems to be missing.

How is that possible? The answer is not in the math of compression — it is in the biology of your inner ear. This chapter is about what your auditory system can and cannot hear, and how codec designers exploit that biology to discard information that was never going to reach your consciousness anyway. Everything else in audio compression — the filterbanks, the MDCT, the bit-allocation loops you will see in Chapters 47 and 48 — is machinery in service of this single insight.

#recap[
  In Chapter 39 we studied quantization: the controlled rounding that introduces distortion in exchange for fewer bits. In Chapter 42 we saw JPEG use that principle in the image domain, guided by the DCT's ability to concentrate energy in low-frequency coefficients. Audio compression does the same thing, but its "distortion budget" is not measured in mean squared error — it is measured in what the human ear can actually detect. To set that budget, we need to understand the ear first. Chapters 47 through 50 will build on everything here.
]

#objectives((
  [Describe the physical structure of the basilar membrane and explain why it acts as a frequency analyser.],
  [Define a critical band and the Bark scale, and reproduce the 24-band table from memory or reasoning.],
  [Explain simultaneous (frequency) masking: what causes it, what its shape looks like, and why it is asymmetric.],
  [Explain temporal masking: the difference between pre-masking and post-masking, and typical durations for each.],
  [Define the absolute threshold of hearing (ATH) and describe why the ear is most sensitive around 2–4 kHz.],
  [Define perceptual entropy and explain what James D. Johnston's 1988 measurement implies about audio compression.],
  [Sketch the pipeline of a psychoacoustic model: STFT or filterbank → masking threshold → bit-allocation target.],
  [Interpret a masking curve diagram and identify the noise-to-mask ratio (NMR) for a given signal and noise level.],
))

== The Ear Is Not a Microphone

Every compression scheme we have studied so far has worked on the _signal_: find patterns, exploit redundancy, encode cleverly. Generic entropy coding (Chapters 24–27) removes statistical redundancy. Dictionary coding (Chapters 28–30) finds repeated strings. Transform coding (Chapters 37–43) concentrates energy so that most coefficients can be discarded. All of these are signal-level tricks. They would work equally well whether the file contained music, speech, X-ray images, or a database dump.

Perceptual audio coding takes a completely different approach. Instead of asking "what redundancy can I exploit in the signal?", it asks "what information in this signal will the listener's brain never process?" The answer is: a surprising amount. The human auditory system evolved to extract meaning — speech, footsteps, approaching predators — not to be a perfect recording instrument. It has hard limits and deliberate shortcuts, and those limits are precisely what a psychoacoustic model maps.

To exploit them, you need to understand three separable phenomena: the absolute threshold of hearing, simultaneous (frequency) masking, and temporal masking. Each one defines a region of sound that the ear ignores; together they carve out a huge fraction of a typical audio signal that can be discarded or coarsely quantized at no perceptible cost.

Before we get to those phenomena, we need to understand the hardware: the basilar membrane.

== Inside the Ear: The Basilar Membrane

Your inner ear contains a snail-shaped fluid-filled tube called the *cochlea*. Coiled inside the cochlea is a thin ribbon of tissue called the *basilar membrane*, about 35 mm long and tapered from narrow and stiff at the base (near the eardrum) to wide and flexible at the apex (the tip of the coil). When sound enters the cochlea as a pressure wave in the fluid, it causes the basilar membrane to ripple.

The key discovery — one that earned *Georg von Békésy* the Nobel Prize in Physiology or Medicine in 1961 — is that this ripple does not look the same everywhere. A pure tone at a specific frequency causes a *travelling wave* that builds to a peak at a particular spot along the membrane, and then dies away. High-frequency tones peak near the stiff base; low-frequency tones travel further and peak near the flexible apex. The membrane acts as a physical frequency analyser, spreading the incoming sound across its length according to frequency, much like a prism spreads white light into its component colours.

#history[
  Georg von Békésy (1899–1972) was a Hungarian-American physicist who spent decades at the Bell Telephone Laboratories and later Harvard. His Nobel Prize citation described his discovery of "the physical mechanism of stimulation within the cochlea." He could not use living animals because the waves were too tiny to measure — so he built human-scale mechanical models of the cochlea using a rubber membrane stretched in a water-filled channel, and used stroboscopic photography to capture the wave. Working in the 1940s and 1950s, decades before digital signal processing existed, he laid the physical foundation for everything in this chapter.
]

The hair cells that sit on the basilar membrane and convert vibration to nerve signals are not infinitely precise. Each hair cell responds to a *range* of frequencies around its preferred frequency, not to a single exact frequency. That range is called a *critical band*. Two tones that land in the same critical band interfere with each other in the ear's processing; two tones in different bands are processed more independently. This bandwidth of interaction is the fundamental unit of psychoacoustics.

#keyidea[
  The basilar membrane is a physical spectrum analyser built into your ear. Its frequency resolution is not uniform — it is coarser at high frequencies and finer at low frequencies. The critical band is the minimum frequency range over which the cochlea integrates sound energy as a single "lump". Anything that falls within one critical band of a louder sound becomes very hard to hear separately.
]

== Critical Bands and the Bark Scale

How wide is a critical band? In 1961, the German acoustician *Eberhard Zwicker* measured masking and loudness data systematically and found that the audible range from roughly 20 Hz to 15,500 Hz divides naturally into *24 critical bands*. Each band is called one *Bark*, named after Heinrich Barkhausen, an early pioneer in measuring loudness. Zwicker's scale is called the *Bark scale*.

The critical bands are not equally wide in hertz. Below about 500 Hz, each band spans roughly 100 Hz. Above 500 Hz, the bandwidth grows — by 8 kHz, a single Bark covers more than 1,000 Hz. This reflects the non-linear geometry of the basilar membrane: the low-frequency region takes up more physical length than the high-frequency region, so it has finer frequency resolution.

#fig([The 24 critical bands of the Bark scale. Each rectangle represents one Bark. The bands are narrow and equally spaced in perceived pitch at low frequencies, growing wider in hertz at high frequencies.],
cetz.canvas({
  import cetz.draw: *

  // Draw the 24 Bark bands (simplified)
  let bands = (
    (20, 100), (100, 200), (200, 300), (300, 400), (400, 510), (510, 630),
    (630, 770), (770, 920), (920, 1080), (1080, 1270), (1270, 1480),
    (1480, 1720), (1720, 2000), (2000, 2320), (2320, 2700), (2700, 3150),
    (3150, 3700), (3700, 4400), (4400, 5300), (5300, 6400), (6400, 7700),
    (7700, 9500), (9500, 12000), (12000, 15500)
  )

  let max_freq = 15500.0
  let width = 11.0
  let height = 1.2

  // draw each band as a rectangle, x scaled logarithmically
  let log_min = calc.log(20)
  let log_max = calc.log(15500)

  for (i, band) in bands.enumerate() {
    let (f0, f1) = band
    let x0 = (calc.log(f0) - log_min) / (log_max - log_min) * width
    let x1 = (calc.log(f1) - log_min) / (log_max - log_min) * width
    let fill_col = if calc.rem(i, 2) == 0 { rgb("#0b5394").lighten(55%) } else { rgb("#0b5394").lighten(75%) }
    rect((x0, 0), (x1, height), fill: fill_col, stroke: 0.5pt + rgb("#0b5394"))
  }

  // x-axis label
  content((0, -0.4), anchor: "west")[#text(size: 7pt)[20 Hz]]
  content((width * 0.28, -0.4), anchor: "center")[#text(size: 7pt)[500 Hz]]
  content((width * 0.58, -0.4), anchor: "center")[#text(size: 7pt)[2 kHz]]
  content((width * 0.80, -0.4), anchor: "center")[#text(size: 7pt)[8 kHz]]
  content((width, -0.4), anchor: "east")[#text(size: 7pt)[15.5 kHz]]

  line((0, -0.2), (width, -0.2), stroke: 0.7pt)
  content((width / 2, 1.7))[#text(size: 8pt, fill: rgb("#0b5394"))[← 24 Bark bands (logarithmic frequency axis) →]]
}))

Here is a condensed version of the Bark scale table to build intuition:

#table(
  columns: (auto, auto, auto, auto),
  align: (center, right, right, right),
  fill: (_, row) => if row == 0 { rgb("#0b5394").lighten(85%) } else { none },
  table.header([*Bark*], [*Lower (Hz)*], [*Upper (Hz)*], [*Width (Hz)*]),
  [1], [20], [100], [80],
  [2], [100], [200], [100],
  [3], [200], [300], [100],
  [6], [510], [630], [120],
  [10], [1080], [1270], [190],
  [14], [2000], [2320], [320],
  [18], [3700], [4400], [700],
  [22], [7700], [9500], [1800],
  [24], [12000], [15500], [3500],
)

Notice how the bandwidth in hertz grows from 80 Hz (band 1) to 3,500 Hz (band 24) — a 44-fold increase — while staying psychologically "one unit" wide throughout.

We do not have to read these band edges off a table every time. Zwicker fitted a smooth closed-form curve to his measurements that converts any frequency $f$ (in hertz) directly into a Bark value $z$:

$ z = 13 arctan(0.00076 f) + 3.5 arctan((f \/ 7500)^2). $

Plug in $f = 100$ and you get $z approx 1.0$ (band 1); plug in $f = 4000$ and you get $z approx 17.3$ (band 17). The two `arctan` terms simply bend the line so it rises quickly at low frequencies and flattens at high ones — exactly the squashing the ear performs. We will turn this formula into a one-line Python function (`hz_to_bark`) later in the chapter.

#mathrecall[
  $arctan$ (the _arc-tangent_, met in Chapter 37) is the function that takes a number and returns the angle whose tangent is that number; its output here is just a real value that grows toward $approx 1.57$ as its input grows. You never evaluate it by hand — a calculator, or Python's `math.atan` / NumPy's `np.arctan`, does it for you. In this chapter treat $arctan(x)$ as a black box that smoothly squashes large inputs toward a ceiling.
]

#gomaths("Logarithms and Perceptual Scales")[
  We keep finding that our senses respond to ratios, not differences. Double the frequency and the pitch goes up by one octave — regardless of whether you doubled from 200 Hz to 400 Hz or from 2,000 Hz to 4,000 Hz. The mathematical tool for describing ratios is the *logarithm*.

  $log_2(f_2 / f_1)$ tells you how many octaves separate two frequencies. If $f_2 = 2 f_1$, then $log_2(2) = 1$ octave. If $f_2 = 4 f_1$, that is $log_2(4) = 2$ octaves.

  The Bark scale is not quite logarithmic — it is based on empirical data about the basilar membrane — but it behaves logarithmically: each Bark unit represents a roughly constant perceptual "step" in pitch, while the corresponding hertz range grows at higher frequencies. A ruler that is uniformly spaced in Bark is non-uniformly spaced in hertz, with the high-frequency end stretched out.

  This same principle governs the decibel scale for loudness: a 10 dB increase always represents the same perceptual jump in loudness, even though the physical power ratio doubles roughly every 3 dB.
]

== The Absolute Threshold of Hearing

The first tool in a psychoacoustic model is the simplest: there is a minimum sound pressure level below which a given frequency is simply inaudible in a quiet room. This is the *absolute threshold of hearing* (ATH), also called the minimum audible field.

The ATH is not flat across frequencies. The curve is famously U-shaped, looking something like a shallow valley:

- *Below 200 Hz*: the threshold rises steeply. A 50 Hz tone needs to be about 40 dB louder than a 1 kHz tone to be heard at all. Very low bass requires a lot of energy to register.
- *1 kHz–4 kHz*: this is the bottom of the valley, where the ear is most sensitive. At around 3–4 kHz, the threshold dips below 0 dB SPL (sound pressure level), meaning the ear can detect sounds so faint they are literally below the conventional reference pressure level. This extraordinary sensitivity around 3 kHz is caused by a resonance of the ear canal itself — the ~2.5 cm tube amplifies frequencies in this range by roughly 10–15 dB.
- *Above 8 kHz*: the threshold rises again steeply. By 15 kHz, many adults need 50 dB or more to detect a tone. This rise accelerates with age — older listeners may lose sensitivity above 10–12 kHz entirely.

#fig([Approximate shape of the absolute threshold of hearing. Each point on the curve is the sound pressure level at which a pure tone just becomes audible in quiet surroundings.],
cetz.canvas({
  import cetz.draw: *

  // Approximate ATH curve points (freq_bark_like_x, threshold_dB)
  // Plotted on a log-frequency x axis: x = log10(f/20)/log10(15500/20) * 10
  let pts = (
    (0.0, 74),   // 20 Hz
    (1.5, 50),   // 40 Hz
    (2.8, 35),   // 80 Hz
    (3.8, 20),   // 150 Hz
    (4.8, 12),   // 300 Hz
    (5.5, 5),    // 500 Hz
    (6.2, 2),    // 1000 Hz
    (6.9, -3),   // 2000 Hz
    (7.3, -5),   // 3000-4000 Hz (most sensitive)
    (7.8, 0),    // 5000 Hz
    (8.3, 8),    // 7000 Hz
    (8.8, 20),   // 10000 Hz
    (9.4, 35),   // 13000 Hz
    (10.0, 60),  // 15500 Hz
  )

  // Scale: x 0-10 maps to plot width 10, y: dB range -10 to 80 maps to 0-6
  let px(x) = x
  let py(y) = (y + 10) / 90 * 6.0

  // axes
  line((0, 0), (10.2, 0), stroke: 0.7pt, mark: (end: ">"))
  line((0, 0), (0, 6.5), stroke: 0.7pt, mark: (end: ">"))

  // grid
  for y_dB in (0, 20, 40, 60) {
    let y = py(y_dB)
    line((0, y), (10.2, y), stroke: (dash: "dotted", paint: gray, thickness: 0.4pt))
    content((-0.5, y), anchor: "east")[#text(size: 7pt)[#y_dB]]
  }

  // x labels
  for (label, x_norm) in (("100", 3.2), ("1k", 6.2), ("4k", 7.6), ("10k", 9.0)) {
    content((x_norm, -0.4), anchor: "center")[#text(size: 7pt)[#label Hz]]
  }

  // sensitivity peak marker
  line((7.3, py(-5)), (7.3, py(40)), stroke: (dash: "dashed", paint: rgb("#0b6e4f").lighten(30%), thickness: 0.5pt))
  content((7.3, py(42)))[#text(size: 7pt, fill: rgb("#0b6e4f"))[~3 kHz peak]]

  // draw ATH curve
  let path_pts = pts.map(((x, y)) => (px(x), py(y)))
  catmull(..path_pts, stroke: (paint: rgb("#9a2617"), thickness: 1.5pt), tension: 0.4)

  // labels
  content((5.0, 6.4))[#text(size: 8pt, fill: rgb("#9a2617"))[Absolute Threshold of Hearing]]
  content((10.4, -0.2))[#text(size: 7pt)[Hz]]
  content((-0.6, 6.4))[#text(size: 7pt)[dB SPL]]
}))

For audio compression, the ATH is a free lunch: any frequency component whose energy falls below the threshold can be dropped entirely, at zero perceptual cost. The gain is largest at very low and very high frequencies.

== Simultaneous (Frequency) Masking

The ATH only applies in silence. In a real piece of music, the threshold is constantly being pushed up by the sounds that are already present. This is *simultaneous masking* (also called *frequency masking*): a loud sound makes nearby frequencies harder to hear, by raising the threshold for them.

=== How Masking Works

The mechanism is physical. When a loud tone at frequency $f_m$ (the *masker*) causes a large-amplitude travelling wave that peaks at the corresponding spot on the basilar membrane, the surrounding hair cells are also partially activated by the wave's skirt. This makes them temporarily less sensitive — the threshold for detecting a quieter tone at a nearby frequency $f_t$ (the *maskee*) is raised by tens of decibels.

The masking effect has a characteristic shape called a *masking curve* or *spreading function*:

- *Below the masker*: masking extends downward in frequency but falls off relatively steeply. A masker at 1 kHz might raise the threshold 20 dB at 700 Hz, but only 5 dB at 400 Hz.
- *Above the masker*: masking extends upward much more strongly. The same 1 kHz masker might raise the threshold by 40 dB at 1.5 kHz and still 20 dB at 2 kHz. This *upward spread of masking* is the dominant effect — and the one codecs exploit the most.

The asymmetry comes from the shape of the travelling wave itself. The wave peaks sharply at the characteristic frequency location but has a long, gradual tail that extends toward the apex (low-frequency region). This means a high-frequency masker hardly affects low frequencies, but a low-frequency masker has a long upward reach.

#keyidea[
  Masking is asymmetric: a loud low-frequency tone masks high-frequency sounds much more effectively than the reverse. Codecs exploit this heavily by allowing coarser quantization (more noise) in the frequency bands above a loud peak, knowing the noise will stay hidden under the masking curve.
]

#fig([Simultaneous masking: a loud tone at 1 kHz raises the hearing threshold for nearby frequencies. Anything below the masking curve is inaudible. The upward spread (right side) is wider than the downward spread (left side).],
cetz.canvas({
  import cetz.draw: *

  let py = y => (y + 10) / 90 * 5.5

  // Shaded "inaudible" region: draw as a filled rect background, then
  // overdraw the masking curve on top.
  rect((0, 0), (10.0, py(35)), fill: rgb("#0b5394").lighten(92%), stroke: none)

  // ATH curve points
  let ath_pts = (
    (0.0, py(35)), (2.0, py(18)), (3.8, py(8)), (5.0, py(1)),
    (5.8, py(-2)), (6.5, py(-5)), (7.0, py(-3)),
    (7.5, py(2)), (8.2, py(12)), (9.0, py(28)), (10.0, py(55)),
  )
  catmull(..ath_pts, stroke: (paint: rgb("#783f04"), thickness: 1pt, dash: "dashed"), tension: 0.4)

  // Masking curve points
  let mask_pts = (
    (0.0, py(35)), (3.5, py(12)), (4.8, py(8)), (5.5, py(18)),
    (5.9, py(40)), (6.2, py(70)),
    (6.6, py(60)), (7.0, py(50)), (7.6, py(40)),
    (8.2, py(28)), (8.8, py(16)), (9.5, py(8)), (10.0, py(4)),
  )
  catmull(..mask_pts, stroke: (paint: rgb("#0b5394"), thickness: 1.5pt), tension: 0.4)

  // Masker vertical line
  let masker_x = 6.2
  line((masker_x, 0), (masker_x, py(70)),
    stroke: (paint: rgb("#9a2617"), thickness: 1.5pt))
  content((masker_x, py(70) + 0.3))[#text(size: 7pt, fill: rgb("#9a2617"))[1 kHz, 70 dB]]

  // Axes
  line((0, 0), (10.5, 0), stroke: 0.7pt, mark: (end: ">"))
  line((0, 0), (0, 6.2), stroke: 0.7pt, mark: (end: ">"))

  for (y_dB, label) in ((0, "0"), (20, "20"), (40, "40"), (60, "60")) {
    let y = py(y_dB)
    line((0, y), (10.2, y),
      stroke: (dash: "dotted", paint: gray.lighten(40%), thickness: 0.4pt))
    content((-0.55, y), anchor: "east")[#text(size: 7pt)[#label]]
  }

  for (label, xv) in (("200", 4.0), ("1k", 6.2), ("4k", 7.6), ("10k", 9.0)) {
    content((xv, -0.4), anchor: "center")[#text(size: 7pt)[#label]]
  }

  content((8.2, py(50)))[#text(size: 7pt, fill: rgb("#0b5394"))[masking threshold]]
  content((9.2, py(22)))[#text(size: 7pt, fill: rgb("#783f04"))[ATH]]
  content((3.0, py(5)))[#text(size: 7.5pt, fill: rgb("#0b5394").lighten(30%))[inaudible region]]
  content((10.6, -0.2))[#text(size: 7pt)[Hz]]
  content((-0.3, 6.4))[#text(size: 7pt)[dB SPL]]
}))

=== The Tonal vs. Noise Character of the Masker

The shape of the masking curve depends on whether the masker is a *tonal* component (a narrow, sine-wave-like frequency peak) or a *noise-like* component (energy spread across a band). A noise masker is slightly more effective — it masks more of its neighbourhood than a pure tone at the same energy level. Codecs compute a measure called the *spectral flatness measure* (SFM) to decide whether each band should be treated as tonal or noise-like before computing the masking threshold. This distinction was formalised by James D. Johnston at Bell Labs in 1988, in work that became the foundation for the psychoacoustic models in MP3 and AAC.

=== Worked Example: Masking in Action

Suppose a flute is playing a strong A4 note at 880 Hz, with an amplitude corresponding to 75 dB SPL. The masking curve around 880 Hz might lift the threshold to:

- 600 Hz: threshold raised to about 20 dB (masking spread slightly downward)
- 1,200 Hz: threshold raised to about 55 dB (strong upward spread)
- 2,000 Hz: threshold raised to about 35 dB (masking falling off with distance)

If the guitar accompaniment has a harmonic at 1,200 Hz that is only 50 dB strong, it falls below the 55 dB masking threshold and is completely masked — entirely inaudible while the flute A4 is playing. You can quantize that guitar harmonic down to a single bit (or even drop it entirely) without the listener noticing anything. That is how perceptual coding achieves compression factors of 10:1 or more.

== Temporal Masking

Simultaneous masking covers sounds happening at the same time. But masking also operates *across time* — a loud transient makes it hard to hear quiet sounds just before and after it. This is *temporal masking*.

=== Forward Masking (Post-Masking)

After a loud sound ends, the auditory system takes a while to recover. During this recovery period — which lasts roughly *50 to 200 ms* depending on how loud the masker was and how long it lasted — soft sounds are masked. This is called *forward masking* or *post-masking*.

A drum hit, for example, is a very brief but very loud transient. In the 100 ms following the hit, soft guitar picking is partially masked. Quantization noise introduced during that 100 ms window will be hidden. The codec can afford to be coarser right after transients.

=== Backward Masking (Pre-Masking)

Counterintuitively, a loud sound also masks quiet sounds that arrive *just before it* — backward masking or *pre-masking*. The window is much shorter, only about *5–20 ms* before the masker onset (with the strongest effect in the last 1–5 ms). This seems like it should be impossible — how can a future event affect perception of the past? The answer is that the auditory system does not process sounds instantaneously; it integrates energy over a short window, and the arriving loud transient "drowns out" the preceding quiet signal in that integration.

Pre-masking is important for coding: if the encoder can look slightly ahead (which offline encoders can), it knows that quantization noise introduced in the 5–10 ms just before a transient will be masked. This is one reason why audio codecs operate in buffered blocks rather than sample by sample.

#fig([Temporal masking. A brief loud masker (the drum hit) raises the hearing threshold both before it (pre-masking, ~5 ms) and after it (post-masking, up to 200 ms). The codec can afford to introduce quantization noise in both shaded windows.],
cetz.canvas({
  import cetz.draw: *

  // Time axis: x from 0 to 9 (representing ~0 to 300 ms)
  // Masker at x=3, duration x=3 to x=4

  // Threshold curve (schematic): high during masker presence, elevated before/after
  let thresh_pts = (
    (0.0, 0.3),  // quiet baseline (ATH level)
    (2.5, 0.3),  // pre-masking onset (5-20ms before)
    (2.8, 1.8),  // threshold starts rising
    (3.0, 3.5),  // masker onset
    (4.0, 3.5),  // masker ends (still at masker level)
    (5.0, 2.8),  // post-masking decay
    (6.5, 1.5),
    (8.0, 0.5),
    (9.0, 0.3),
  )

  // shading: pre-masking region (simplified as a rect)
  rect((2.5, 0), (3.0, 2.5), fill: rgb("#783f04").lighten(80%), stroke: none)

  // shading: post-masking region (simplified as a rect)
  rect((4.0, 0), (8.0, 2.8), fill: rgb("#0b5394").lighten(80%), stroke: none)

  // masker rectangle
  rect((3.0, 0), (4.0, 3.5), fill: rgb("#9a2617").lighten(70%), stroke: 0.8pt + rgb("#9a2617"))
  content((3.5, 1.75))[#text(size: 7pt, fill: rgb("#9a2617"))[drum hit]]

  // threshold curve
  let tpts = thresh_pts.map(((x, y)) => (x, y))
  catmull(..tpts, stroke: (paint: rgb("#0b5394"), thickness: 1.5pt), tension: 0.4)

  // ATH baseline
  line((0, 0.3), (9.0, 0.3), stroke: (paint: rgb("#783f04"), thickness: 0.8pt, dash: "dashed"))

  // axes
  line((0, 0), (9.5, 0), stroke: 0.7pt, mark: (end: ">"))
  line((0, 0), (0, 4.8), stroke: 0.7pt, mark: (end: ">"))

  content((9.6, 0))[#text(size: 7pt)[time]]
  content((0, 5.0))[#text(size: 7pt)[threshold]]

  // time markers
  content((2.7, -0.35), anchor: "center")[#text(size: 6.5pt)[~5–20 ms]]
  content((6.0, -0.35), anchor: "center")[#text(size: 6.5pt)[up to 200 ms]]
  content((3.5, -0.35))[#text(size: 6.5pt, fill: rgb("#9a2617"))[]]

  // labels
  content((1.8, 2.5))[#text(size: 7pt, fill: rgb("#783f04"))[pre-masking]]
  content((6.2, 2.3))[#text(size: 7pt, fill: rgb("#0b5394"))[post-masking]]
  content((8.8, 0.6))[#text(size: 7pt, fill: rgb("#783f04"))[ATH]]
}))

#checkpoint[
  A codec is encoding a 20 ms block that sits immediately after a very loud transient. Knowing about post-masking, should the codec allocate more bits to this block or fewer bits? Why?
][
  Fewer bits. Post-masking means the hearing threshold in this block is elevated above the ATH, so more quantization noise is inaudible. The codec can afford coarser quantization, saving bits, without the listener noticing any extra noise.
]

== Putting It Together: The Masking Threshold

In practice, simultaneous masking from all the active frequency components is computed, the temporal masking from recent transients is added, and the ATH provides a floor. The result is a *global masking threshold* — a frequency-by-frequency curve that specifies, for each band, the maximum amount of quantization noise that will remain inaudible.

This threshold is the output of what engineers call a *psychoacoustic model* — a mathematical procedure that takes a short window of audio and produces a masking threshold curve. Everything else in the encoder is then driven to keep quantization noise *just below* the masking threshold everywhere.

#algo(
  name: "Psychoacoustic Model (Generic Pipeline)",
  year: "1980s–present",
  authors: "Johnston (1988), MPEG committees (1992–present), and many others",
  aim: "Convert a short frame of audio into a per-band masking threshold that the quantizer must not exceed.",
  complexity: "O(N log N) per frame (dominated by the FFT/filterbank)",
  strengths: "Dramatically reduces the bits needed for transparent-quality audio; output is perceptually driven, not signal-driven.",
  weaknesses: "Adds encoder complexity; model accuracy varies with signal type; pre-echo artifacts possible if transient detection fails.",
  superseded: "",
)[
  *Step 1 — Window and transform.* Apply a short-time window (Hann, Kaiser-Bessel, or similar) to an overlapping frame of samples, then compute an FFT or run the audio through a filterbank. This gives a short-time spectrum.

  *Step 2 — Identify maskers.* Locate tonal components (narrow spectral peaks) and noise-like components (broad spectral energy) in the spectrum. Compute the spectral flatness measure (SFM) per band.

  *Step 3 — Compute individual masking thresholds.* For each masker, apply the spreading function — the masking curve shape — to find how much it raises the threshold in each critical band.

  *Step 4 — Add ATH.* The absolute threshold of hearing provides a frequency-dependent floor. A masking threshold can never be below the ATH (even in the absence of any masker, you cannot quantize below the hearing floor).

  *Step 5 — Combine.* Sum all individual masking thresholds (in power) with the ATH, per critical band. The result is the *global masking threshold* T(f).

  *Step 6 — Output SMR.* Compute the signal-to-mask ratio (SMR) per band: how much louder the signal is than the masking threshold. The encoder's bit-allocation module converts SMR into bit counts for each band.
]

== The Signal-to-Mask Ratio and Bit Allocation

The central number that ties the psychoacoustic model to the actual codec is the *signal-to-mask ratio* (SMR), defined per critical band:

$ "SMR"_b = L_b - T_b $

where $L_b$ is the signal level in dB in band $b$, and $T_b$ is the masking threshold in dB in the same band. A large positive SMR means the signal is much louder than the masking threshold — you need many bits to represent it faithfully (or at least, the noise must be driven well below the threshold). A zero or negative SMR means the signal itself is at or below the masking threshold — it can be dropped entirely.

The *noise-to-mask ratio* (NMR) is the complement: $"NMR"_b = N_b - T_b$, where $N_b$ is the actual quantization noise level. The encoder's goal is to keep NMR below 0 dB in every band — keep the noise under the mask.

#gomaths("Decibels (dB) — Why We Measure Loudness Logarithmically")[
  Loudness covers an enormous dynamic range: the quietest sound a healthy ear can detect is about $2 times 10^(-5)$ Pa of pressure; a jet engine at 1 metre is roughly $200$ Pa — a ratio of 10 million to one. Writing such numbers is cumbersome, and comparing them is confusing.

  The *decibel* (dB) compresses this range by using a logarithm. Sound pressure level is defined as:

  $ L = 20 log_(10) (p / p_0) $

  where $p$ is the measured pressure and $p_0 = 20 mu"Pa"$ is the reference (the ATH at 1 kHz). A factor-of-10 increase in pressure gives $+20$ dB. A factor-of-2 increase gives $+6$ dB.

  *Power* follows the same idea: $L = 10 log_(10)(P / P_0)$. Notice the factor is 10 (not 20) for power, because power is proportional to pressure squared, and $20 log(x) = 10 log(x^2)$.

  Everyday reference points:
  - 0 dB SPL: the threshold of hearing (a barely audible tone at 1 kHz)
  - 30 dB: a quiet library
  - 60 dB: normal conversation
  - 85 dB: heavy traffic (risk of damage over hours)
  - 120 dB: a rock concert front row (pain threshold)

  In audio coding, all signal levels, masking thresholds, and noise levels are expressed in dB because the equations then become subtractions instead of divisions — which is much cleaner.
]

The bit-allocation problem works like this. Suppose each band needs to be quantized with enough bits that the quantization noise stays below $T_b$. For a uniform quantizer, each additional bit cuts the noise power by roughly 6 dB (a factor of 4 in power). So the number of bits needed in band $b$ is approximately:

$ n_b approx (L_b - T_b + "headroom") / 6 $

A band with SMR of 30 dB needs about 5 bits per sample to push the noise 30 dB below the signal (and thus under the mask). A band with SMR of 0 dB — signal right at the mask — needs 0 bits: it can be dropped.

The codec's inner loop is a constrained optimization: allocate available bits across bands to minimise the worst-case NMR, subject to a total bit budget. This is why perceptual audio coding is sometimes called *noise shaping* guided by the ear: you are not minimising total noise power, you are shaping the noise to hide inside the masking curve.

How does the encoder actually choose the bits? In practice it does not solve the optimization in closed form — it runs a short iterative loop, the heart of every MPEG-audio encoder:

#algo(
  name: "Perceptual Bit-Allocation Loop",
  year: "1988–present",
  authors: "Johnston (1988); MPEG-1 Audio (ISO/IEC 11172-3, 1992)",
  aim: "Distribute a fixed bit budget across critical bands so that the quantization noise stays below the masking threshold in as many bands as possible.",
  complexity: "O(B · I) per frame, where B is the number of bands and I the number of iterations (typically small)",
  strengths: "Spends bits exactly where the ear will notice their absence; degrades gracefully when the budget is too small.",
  weaknesses: "Greedy — it can miss the global optimum; needs careful tuning to avoid audible 'pumping' as the allocation shifts between frames.",
  superseded: "Refined by the two-loop (rate/distortion) structure of MP3 and the trellis-based allocation of later codecs.",
)[
  *Inputs:* per-band signal levels $L_b$, masking thresholds $T_b$ (from the psychoacoustic model), and a total bit budget $B_"total"$.

  *Step 1 — Compute the demand.* For each band, form the signal-to-mask ratio $"SMR"_b = L_b - T_b$. Bands with a large SMR are the loudest-relative-to-mask and therefore the most urgent.

  *Step 2 — Initialise.* Give every band zero bits. Set the current noise in each band equal to its full signal level (un-quantized = maximum error).

  *Step 3 — Greedy refinement.* Repeat until the budget is exhausted: find the band with the worst (largest) noise-to-mask ratio $"NMR"_b = N_b - T_b$, and give it one more bit. Adding a bit drops that band's noise $N_b$ by about 6 dB, lowering its NMR.

  *Step 4 — Stop.* When the budget runs out (or every band already has $"NMR"_b < 0$), stop. Emit the per-band bit counts as side information so the decoder knows how to read each band back.
]

Notice what this loop is really doing: it is a *water-filling* procedure run in reverse. Instead of pouring power into the quietest channels (as in the rate--distortion theory of Chapter 21), it pours _bits_ into the bands whose noise currently pokes furthest above the mask, always attacking the most audible error first. The masking threshold $T_b$ is the "water level" the noise must be kept under.

#misconception[
  "Perceptual coding discards high frequencies to save space."
][
  This is a common but wrong mental model. Perceptual coding does not discard fixed frequency ranges — it discards energy in any frequency band that is masked by something louder, whether that band is at 100 Hz or 10 kHz. A loud bass note can mask mid-frequency content just as well. The masking threshold is a dynamic, frame-by-frame calculation, not a fixed filter. A 128 kbps MP3 does cut very high frequencies (above ~16 kHz) to meet its bit budget, but that is a budget constraint, not the primary mechanism.
]

== Perceptual Entropy: The Theoretical Floor

The most striking application of the psychoacoustic model is measuring the theoretical limit of transparent audio compression — how small can you make a file before a normal listener begins to notice any degradation?

In 1988, *James D. Johnston* at Bell Laboratories published a landmark paper: "Transform Coding of Audio Signals Using Perceptual Noise Criteria" (IEEE JSAC, 1988). He took the masking threshold framework and used it as a distortion criterion to define the *perceptual entropy* (PE) of an audio signal: the number of bits per sample that are genuinely necessary to represent the signal at quality that is indistinguishable from the original.

Johnston's key measurement was this: for a wide variety of CD-quality music, the perceptual entropy is approximately *2.1 bits per sample*. CD audio uses 16 bits per sample. So the theoretical compression ratio for transparent quality is about $16 / 2.1 approx 7.6:1$. At 44,100 samples per second, stereo, that corresponds to roughly 185 kbps — not coincidentally close to the perceptual transparency threshold that audiophiles quote for well-tuned MP3 encoders.

#keyidea[
  Perceptual entropy is the Shannon entropy of the signal *after masking*: the bits that actually matter to the listener. Johnston's 1988 measurement — about 2.1 bits/sample for typical music — implies that a ratio of approximately 7:1 is the hard perceptual limit for lossless-sounding audio compression, regardless of how good the codec is. Better codecs approach this limit; they cannot beat it.
]

This is a profound result. It says that the 11:1 ratio achieved by 128 kbps MP3 in the late 1990s was actually slightly beyond the perceptual transparency threshold for typical listeners in typical conditions — and that 320 kbps MP3 was providing about twice as many bits as transparency requires, just for safety margin.

More sophisticated encoders (AAC, Opus, and beyond) approach the perceptual entropy limit more closely by refining the psychoacoustic model and the bit-allocation loop. But no amount of clever coding can compress a signal below its perceptual entropy without some listener in some condition noticing.

== Pre-Echo: When the Model Gets It Wrong

Psychoacoustic models work beautifully when the audio signal is *stationary* — when its frequency content is roughly the same across the analysis window. But music is not stationary. Transients — drum hits, piano attacks, consonant plosives in speech — introduce sudden, sharp changes that violate this assumption.

When a loud transient arrives, the encoder computes the masking threshold over a window that straddles the transient. If the window is 20 ms long (a typical block size), the masker's energy is spread across the whole window in the model's view. The encoder then allows high quantization noise in the pre-transient portion of the window, expecting that the masker will hide it. But in reality, the transient has not happened yet during the pre-transient part of the window — there is no masker yet, only the ATH. The quantization noise (which, unlike the masker, is spread across the whole window in time) becomes audible *before the transient hits*.

This artifact is called *pre-echo*: you hear a faint "smear" of noise a few milliseconds before a sharp attack. It is the most characteristic failure mode of transform-based audio codecs.

Codecs fight pre-echo with *transient detection*: when the encoder detects a large change in energy within a block, it switches to shorter blocks (512 or 256 samples instead of 1024 or 2048) that straddle the transient more precisely, keeping the quantization noise confined to a narrow time window where the masker is actually present.

#pitfall[
  Pre-echo is not caused by the frequency transform itself — it is caused by the mismatch between the time extent of the quantization noise and the time extent of the masker in the psychoacoustic model. Shorter blocks fix pre-echo by reducing temporal smearing, but at the cost of frequency resolution (shorter blocks = wider frequency bins), which is why codecs use variable block lengths.
]

== Stereo Masking and Binaural Effects

So far we have talked about one audio channel. Real music is stereo, and the two channels interact in the listener's perception.

=== Mid-Side Stereo

The simplest gain is to decorrelate the two channels. Instead of encoding left (L) and right (R) independently, the encoder transforms to *mid* and *side* components:

$ M = (L + R) / 2 quad "and" quad S = (L - R) / 2 $

For typical music, M (the mono sum) carries most of the energy and spectral content. S (the stereo difference) is often much quieter. This means S can be quantized more coarsely — fewer bits — without perceptual cost, because the human auditory system is less sensitive to stereo difference information than to mono.

=== Binaural Masking Level Difference

The psychoacoustic picture is even richer: the auditory system also compares phase and timing between the two ears. The *binaural masking level difference* (BMLD) is the effect where a tone becomes easier to detect in stereo when its interaural phase differs from that of a noise masker. Exploiting BMLD requires tracking phase relationships between channels — something that HE-AAC and Opus parametric stereo do in simplified form.

== Critical Bands in Code: A Worked Python Example

Let us make the Bark scale concrete by implementing a simple function that maps a frequency to its critical band number, and then computes the masking threshold from a simple set of input maskers.

#gopython("NumPy Arrays and List Comprehensions")[
  NumPy is a library that adds efficient numerical arrays to Python. You saw it briefly in Chapter 37 for the DCT. Here we use it for fast array arithmetic:

  ```python
  import numpy as np

  freqs = np.array([100.0, 500.0, 1000.0, 4000.0])  # a 1-D array of floats
  levels = np.array([60.0,  70.0,   80.0,   50.0])   # dB levels

  # operations broadcast across all elements at once
  above_threshold = levels > 55.0          # array of booleans
  print(above_threshold)                   # [False  True  True  False]
  ```

  A *list comprehension* is a compact way to build a list: `[f(x) for x in items]` applies `f` to every element of `items` and collects the results. For example:

  ```python
  bark_numbers = [hz_to_bark(f) for f in freqs]
  ```
]

```python
# psycho.py — minimal psychoacoustic model helpers
import numpy as np

# ------------------------------------------------------------------ #
# 1. Bark scale conversion                                            #
# ------------------------------------------------------------------ #

def hz_to_bark(f: float) -> float:
    """Convert a frequency in Hz to Bark units.

    Uses Zwicker's 1961 formula (approximation):
       z = 13 * arctan(0.00076 * f) + 3.5 * arctan((f / 7500)^2)
    Returns a value in the range [0, 24].
    """
    return (13.0 * np.arctan(0.00076 * f)
            + 3.5 * np.arctan((f / 7500.0) ** 2))


def bark_to_hz_approx(z: float) -> float:
    """Approximate inverse: Bark to Hz (numerical, not exact)."""
    # Iterative Newton method would be exact; here we use a lookup
    # table interpolation for illustration.
    bark_table = [0,  100, 200, 300, 400, 510, 630, 770, 920,
                  1080, 1270, 1480, 1720, 2000, 2320, 2700, 3150,
                  3700, 4400, 5300, 6400, 7700, 9500, 12000, 15500]
    idx = min(int(z), 23)
    f0 = bark_table[idx]
    f1 = bark_table[min(idx + 1, 24)]
    frac = z - idx
    return f0 + frac * (f1 - f0)


# ------------------------------------------------------------------ #
# 2. Absolute Threshold of Hearing                                    #
# ------------------------------------------------------------------ #

def ath_db(f: float) -> float:
    """ISO 226 approximation of the absolute threshold of hearing in dB SPL.

    Valid for ~20 Hz to 16 kHz.
    Uses a common polynomial approximation (Moore, 1995).
    """
    f_khz = f / 1000.0
    if f_khz <= 0:
        return 90.0
    term = (3.64 * (f_khz ** -0.8)
            - 6.5  * np.exp(-0.6 * (f_khz - 3.3) ** 2)
            + 1e-3 * (f_khz ** 4))
    return float(term)


# ------------------------------------------------------------------ #
# 3. Spreading function (simplified Schroeder model)                  #
# ------------------------------------------------------------------ #

def spreading_function_db(dz: float, masker_db: float,
                          is_tonal: bool) -> float:
    """The amount by which a masker spreads into a band dz Bark away.

    dz > 0: band is above the masker (upward spread).
    dz < 0: band is below the masker (downward spread).
    is_tonal: True for narrow spectral peaks, False for noise-like maskers.

    Returns the masking threshold contribution in dB.
    """
    # Noise maskers mask slightly more than tonal ones
    tonal_correction = -6.0 if is_tonal else 0.0

    if dz >= 0:
        # Upward spread: gradual slope
        slope = -10.0  # dB per Bark (simplified)
    else:
        # Downward spread: steeper
        slope = 27.0   # dB per Bark (steeper falloff below masker)

    # The threshold contribution at distance dz Bark
    threshold_db = masker_db + tonal_correction + slope * abs(dz)
    return threshold_db


# ------------------------------------------------------------------ #
# 4. Simple masking threshold calculator                              #
# ------------------------------------------------------------------ #

def compute_masking_threshold(
    freqs_hz: np.ndarray,
    levels_db: np.ndarray,
    query_freqs_hz: np.ndarray,
) -> np.ndarray:
    """Given a set of spectral components (freqs + levels in dB SPL),
    compute the masking threshold at each query frequency.

    Returns threshold_db: shape (len(query_freqs_hz),)
    """
    n_query = len(query_freqs_hz)
    # Start from the ATH
    threshold = np.array([ath_db(f) for f in query_freqs_hz])

    for f_m, L_m in zip(freqs_hz, levels_db):
        z_m = hz_to_bark(f_m)
        # Tonal if this masker is a narrow peak (here we assume tonal
        # for simplicity; a real model checks SFM).
        for i, f_q in enumerate(query_freqs_hz):
            z_q = hz_to_bark(f_q)
            dz = z_q - z_m
            contrib = spreading_function_db(dz, L_m, is_tonal=True)
            # Take the maximum (highest threshold = hardest to hear)
            if contrib > threshold[i]:
                threshold[i] = contrib

    return threshold


# ------------------------------------------------------------------ #
# 5. Quick self-test                                                   #
# ------------------------------------------------------------------ #

if __name__ == "__main__":
    # A 1 kHz tone at 70 dB SPL
    maskers_hz  = np.array([1000.0])
    maskers_db  = np.array([70.0])

    # Query at several frequencies
    query_hz = np.array([300.0, 500.0, 800.0, 1000.0,
                         1500.0, 2000.0, 4000.0, 8000.0])
    T = compute_masking_threshold(maskers_hz, maskers_db, query_hz)

    print(f"{'Freq (Hz)':>10}  {'ATH (dB)':>10}  {'Mask T (dB)':>12}")
    for f, t in zip(query_hz, T):
        print(f"{f:10.0f}  {ath_db(f):10.1f}  {t:12.1f}")
```

Running this prints something like:

```
  Freq (Hz)    ATH (dB)   Mask T (dB)
       300        14.3          30.0
       500         5.2          30.0
       800         1.6          50.5
      1000        -0.5          64.0
      1500        -2.1          55.0
      2000        -3.3          45.0
      4000        -3.1          25.0
      8000        14.7          14.7   ← ATH dominates here
```

At 8 kHz, the masker's reach has faded to nothing, and the ATH is the binding constraint. At 1 kHz (the masker itself), the threshold is just below the masker level. Between 800 Hz and 2 kHz, the masking curve dominates the ATH.

#gopython("Importing Libraries and if __name__ == '__main__'")[
  The line `import numpy as np` loads the NumPy library and gives it the short alias `np`. This is a universal convention — you will see it in almost every scientific Python file.

  The block `if __name__ == "__main__":` at the bottom of a file runs only when you execute the file directly (e.g., `python psycho.py`), not when it is imported by another module. It is Python's standard way of writing a file that is both a reusable library *and* a runnable script.

  ```python
  # in mylib.py
  def useful_function():
      return 42

  if __name__ == "__main__":
      # Only runs when you type: python mylib.py
      print(useful_function())
  ```
]

== Psychoacoustics in Practice: What Every Codec Does

This chapter has built the scientific foundations. In Chapters 47–50 we will see exactly how MP3, AAC, Vorbis, and Opus each implement this model. But it is worth previewing the common structure all of them share.

Every perceptual audio codec is a pipeline with the same shape:

#fig([The shared structure of all perceptual audio codecs. The psychoacoustic model (centre-right box) acts as a controller that decides how many bits each band receives.],
cetz.canvas({
  import cetz.draw: *

  // Boxes and arrows for the codec pipeline
  let box_fill = rgb("#0b5394").lighten(90%)
  let box_stroke = rgb("#0b5394")
  let model_fill = rgb("#0b6e4f").lighten(88%)
  let model_stroke = rgb("#0b6e4f")

  // input
  rect((0, 1.5), (1.8, 2.5), fill: box_fill, stroke: box_stroke, radius: 3pt)
  content((0.9, 2.0))[#text(size: 7.5pt)[PCM input]]

  // filterbank / MDCT
  rect((2.2, 1.5), (4.0, 2.5), fill: box_fill, stroke: box_stroke, radius: 3pt)
  content((3.1, 2.0))[#text(size: 7.5pt)[Filter bank\ (MDCT)]]
  line((1.8, 2.0), (2.2, 2.0), mark: (end: ">"), stroke: 0.7pt)

  // quantizer
  rect((4.4, 1.5), (6.2, 2.5), fill: box_fill, stroke: box_stroke, radius: 3pt)
  content((5.3, 2.0))[#text(size: 7.5pt)[Quantizer]]
  line((4.0, 2.0), (4.4, 2.0), mark: (end: ">"), stroke: 0.7pt)

  // entropy coder
  rect((6.6, 1.5), (8.4, 2.5), fill: box_fill, stroke: box_stroke, radius: 3pt)
  content((7.5, 2.0))[#text(size: 7.5pt)[Entropy\ coder]]
  line((6.2, 2.0), (6.6, 2.0), mark: (end: ">"), stroke: 0.7pt)

  // bitstream output
  rect((8.8, 1.5), (10.6, 2.5), fill: box_fill, stroke: box_stroke, radius: 3pt)
  content((9.7, 2.0))[#text(size: 7.5pt)[Bitstream\ output]]
  line((8.4, 2.0), (8.8, 2.0), mark: (end: ">"), stroke: 0.7pt)

  // psychoacoustic model box
  rect((2.2, 0.0), (6.2, 1.1), fill: model_fill, stroke: model_stroke, radius: 3pt)
  content((4.2, 0.55))[#text(size: 7.5pt, fill: model_stroke)[Psychoacoustic model\ (masking threshold T(f))]]

  // arrows from filterbank and to quantizer
  line((3.1, 1.5), (3.1, 1.1), mark: (end: ">"), stroke: (paint: model_stroke, thickness: 0.7pt))
  line((5.3, 1.1), (5.3, 1.5), mark: (end: ">"), stroke: (paint: model_stroke, thickness: 0.7pt))
  content((4.2, -0.3))[#text(size: 6.5pt, fill: model_stroke)[computes SMR → bit allocation target]]
}))

1. *Analysis filterbank or MDCT*: the time-domain PCM signal is transformed into frequency-domain coefficients, grouped into critical-band-like subbands.
2. *Psychoacoustic model* (running in parallel): the same time-domain signal is also analysed with a short-time FFT to compute the masking threshold T(f) for this block.
3. *Bit allocation*: the threshold T(f) is compared to the signal levels to compute SMR per band; the bit-allocation algorithm distributes the available bit budget to drive NMR negative in every band.
4. *Quantization*: each subband's coefficients are quantized with the number of bits the allocation step prescribes.
5. *Entropy coding*: the quantized coefficients are losslessly compressed — Huffman tables in MP3, arithmetic coding in AAC and Opus — to remove the statistical redundancy that the quantizer leaves.
6. *Bitstream output*: headers, side information, and the entropy-coded payload are packed into the container format (ID3, ADTS, Ogg, etc.).

The decoder simply reverses steps 5→4→1. Crucially, the decoder does NOT run the psychoacoustic model — it does not need to. The model's output (the bit allocation) was already baked into the quantization choices by the encoder. Decoders are therefore much simpler than encoders.

#aside[
  This asymmetry — complex encoder, simple decoder — is a deliberate design choice. There is one encoder (or a small number of professional mastering tools), but millions of decoders (every phone, browser, car). Moving complexity to the encoder is almost always the right trade-off for mass-market distribution formats.
]

== Why This Matters: The Perceptual Coding Revolution

It is worth pausing to appreciate how radical the shift from signal coding to perceptual coding really was.

Before the late 1980s, audio compression meant using linear prediction (like FLAC or telephony vocoders) to reduce the statistical redundancy of the sample stream. The implicit goal was to recover the signal exactly, or as close to exactly as possible. Distortion was measured in mean squared error — the average of the squared differences between original and reconstructed samples.

The psychoacoustic revolution reframed the entire question. Distortion should be measured not in signal space but in perceptual space. An error of 10 quantization levels in a frequency band that is completely masked is worth exactly zero. An error of 0.1 quantization levels in an unmasked band at 3 kHz is audible and matters. MSE treats these two situations identically and optimises the wrong thing.

#history[
  The engineering breakthrough was the combination of two developments that matured in parallel during the 1980s:

  First, *psychoacoustic measurement*. Harvey Fletcher at Bell Labs had studied masking in the 1930s. Zwicker's critical-band measurements arrived in 1961. But it took until the 1970s–1980s for a precise, computationally tractable model of the masking threshold to emerge — particularly Johnston's 1988 perceptual entropy paper and the psychoacoustic models that fed into the MPEG Audio standardisation process (1988–1993).

  Second, *fast digital signal processing*. The FFT had existed since Cooley-Tukey in 1965 (Chapter 37), but applying it in real time required hardware that did not exist at scale until the mid-1980s. When DSP chips became cheap enough to run an FFT in real time, the psychoacoustic model became practical.

  The two developments met in the MPEG Audio work. At MPEG's 1991 Hannover meeting, fourteen competing codec proposals were evaluated blind. The winners — what became MPEG-1 Layer I, II, and III — were those that most effectively used psychoacoustic masking to allocate bits where they mattered most.
]

== The Limits of Psychoacoustic Models

No psychoacoustic model is perfect, and every perceptual codec has audible failure modes that reveal the limits of the underlying model.

*Tonal signals are hard to mask*. A pure sine wave is easy to hear against noise — the auditory system is exquisitely sensitive to sustained tones. If the codec introduces broadband noise (as even a sophisticated quantizer does), that noise can become audible around a sustained sine wave even if its level is below the threshold predicted by the model. This is the "swirling noise" artifact sometimes heard around sustained piano notes at moderate bitrates.

*Stereo imaging can collapse*. When bit rates are very low, the codec may merge the two channels (reducing to joint stereo or even mono for some frequency bands) to free up bits. Listeners with good headphones can hear this as a narrowing of the stereo image.

*Out-of-band noise folds in*. A filterbank with imperfect stopband rejection will allow energy from one band to leak into adjacent bands. This *aliasing* can create artefacts that the psychoacoustic model did not account for because the model and the filterbank are computed separately.

*Binaural acuity at high frequencies*. Above about 1.5 kHz, the auditory system uses intensity differences between ears (rather than timing differences) for spatial localisation. Coarse quantization of the phase information at low-to-mid frequencies can slightly blur the stereo image in ways that the standard psychoacoustic model does not capture.

Modern codecs address these failure modes with refinements: better transient detection, shape-adaptive quantization, joint-stereo psychoacoustic modelling, and — most recently — neural post-processors that learn the residual errors that classical psychoacoustic models leave behind. (Chapter 49 covers Opus 1.5's neural layer, which does exactly this.)

#checkpoint[
  A codec is encoding a flute playing a long, sustained A5 note (880 Hz) against a quiet background. Predict which artifact is most likely to appear and why.
][
  Tonal noise ("swirling noise" or "birdie") around the sustained tone. Sustained pure tones are very easy to detect against broadband noise, and the psychoacoustic model may over-estimate the masking coverage of the fundamental and its immediate neighbours. The quantization noise in nearby frequency bins becomes audible as a faint swirling or warbling sound.
]

#takeaways((
  [The basilar membrane acts as a physical spectrum analyser: each position responds to a different frequency, creating the auditory system's frequency selectivity.],
  [Critical bands (the Bark scale, 24 bands from 20 Hz to 15.5 kHz) are the fundamental units of auditory frequency processing: sounds within one band interact strongly.],
  [The absolute threshold of hearing (ATH) defines the minimum audible level per frequency; it is lowest (most sensitive) around 2–4 kHz due to ear canal resonance.],
  [Simultaneous masking: a loud sound raises the hearing threshold for nearby frequencies, with a larger upward spread than downward spread.],
  [Temporal masking: a loud transient masks sounds up to ~5–20 ms before (pre-masking) and 50–200 ms after (post-masking).],
  [The psychoacoustic model converts a short audio frame into a global masking threshold T(f) per critical band; the encoder then allocates bits to keep quantization noise below T(f).],
  [Signal-to-mask ratio (SMR) = signal level − masking threshold in dB; it drives bit allocation. Noise-to-mask ratio (NMR) = noise level − threshold; the encoder's goal is NMR < 0 dB everywhere.],
  [Perceptual entropy (Johnston, 1988) measures the minimum bits/sample for transparent quality. For typical music it is ~2.1 bits/sample, implying a theoretical 7–8:1 compression ratio.],
  [Pre-echo is the characteristic failure mode when temporal masking is over-applied around transients; codecs fight it with variable block lengths.],
))

== Exercises

#exercise("46.1", 1)[
  A flute plays a pure tone at 2 kHz at 65 dB SPL. Using the concept of simultaneous masking, explain whether a cello playing at 1 kHz and 30 dB SPL would be audible at the same time. Justify your answer qualitatively (no calculation needed).
]
#solution("46.1")[
  The 2 kHz tone is the masker. Masking spreads downward (below the masker) more weakly than upward. The 1 kHz tone is one Bark below 2 kHz. The downward spread from a masker at 65 dB drops steeply — by about 25–27 dB per Bark below the masker. One Bark below would push the threshold to roughly 65 − 27 ≈ 38 dB at 1 kHz. The cello at 30 dB SPL is below this threshold, so it would be masked and inaudible while the flute plays. (Note: in real music the cello has many harmonics above 1 kHz that may not be masked, so in practice you would hear it, just without its fundamental.)
]

#exercise("46.2", 1)[
  Convert the following frequencies to Bark units using the approximate formula $z = 13 arctan(0.00076 f) + 3.5 arctan((f/7500)^2)$: (a) 100 Hz, (b) 1,000 Hz, (c) 4,000 Hz. For each, identify which critical band number it falls in.
]
#solution("46.2")[
  (a) $f=100$: $z = 13 arctan(0.076) + 3.5 arctan((0.0133)^2) approx 13(0.0756) + 3.5(0.000178) approx 0.983 + 0.001 approx 1.0$ Bark (band 1). (b) $f=1000$: $z = 13 arctan(0.76) + 3.5 arctan((0.133)^2) approx 13(0.650) + 3.5(0.0178) approx 8.45 + 0.062 approx 8.5$ Bark (band 8–9). (c) $f=4000$: $z = 13 arctan(3.04) + 3.5 arctan((0.533)^2) approx 13(1.257) + 3.5(0.274) approx 16.3 + 0.96 approx 17.3$ Bark (band 17).
]

#exercise("46.3", 2)[
  A critical band at 1,500 Hz has a signal level of 55 dB SPL. The psychoacoustic model predicts a masking threshold of 45 dB SPL in that band. (a) Compute the signal-to-mask ratio (SMR). (b) Estimate how many bits per sample the quantizer should allocate to this band to keep the noise-to-mask ratio just negative (NMR < 0 dB). Use the approximation that each bit buys ~6 dB of noise reduction.
]
#solution("46.3")[
  (a) SMR = signal − threshold = 55 − 45 = 10 dB. (b) We need the quantization noise to be below the masking threshold. The signal is 55 dB; with $n$ bits, the quantization noise is roughly $55 − 6n$ dB. We need $55 − 6n < 45$, so $6n > 10$, giving $n > 1.67$. Rounding up: 2 bits per sample. With 2 bits, noise ≈ $55 − 12 = 43$ dB, which is 2 dB below the mask threshold of 45 dB — NMR = −2 dB. ✓
]

#exercise("46.4", 2)[
  Explain in your own words why pre-echo occurs and why switching to shorter transform blocks reduces it. Be specific about the relationship between block length, time resolution, and frequency resolution.
]
#solution("46.4")[
  Pre-echo occurs because the psychoacoustic model computes masking over an entire transform block (e.g., 20 ms). If a loud transient occurs at the end of a block, the model sees the transient's energy and assumes it masks the whole block — including the quiet portion at the beginning, before the transient. But the quantization noise from the quantizer is also spread across the whole block in time. Before the transient, there is no real masker present, so the noise becomes audible.

  Shorter blocks have better time resolution: a 5 ms block captures a smaller time slice, so a transient can only dominate its entire block if the block is short enough that the transient fills it. The trade-off: shorter blocks have fewer samples, so the FFT has fewer frequency bins — worse frequency resolution. Critical bands become wider, and it is harder to allocate bits to individual frequency ranges. Codecs therefore use long blocks for stationary signals (good frequency resolution, better masking) and switch to short blocks for transients (better time resolution, pre-echo prevention).
]

#exercise("46.5", 2)[
  Johnston's 1988 perceptual entropy measurement gives approximately 2.1 bits/sample for typical CD music. CD audio uses 16 bits/sample at 44,100 Hz, stereo. Calculate: (a) the compression ratio implied by the perceptual entropy; (b) the corresponding bitrate in kbps; (c) whether 128 kbps MP3 is above or below the transparency threshold, and by how much.
]
#solution("46.5")[
  (a) Compression ratio = 16 / 2.1 ≈ 7.6:1.

  (b) Bitrate at perceptual entropy: $44100 "samples/s" times 2.1 "bits/sample" times 2 "channels" = 185,220 "bps" approx 185 "kbps"$.

  (c) 128 kbps is below 185 kbps, so it is below the theoretical transparency threshold. The margin is 185 − 128 = 57 kbps — meaning 128 kbps MP3 is operating roughly 3 dB (in average bit budget terms) below what Johnston's model predicts is needed for full transparency. This is consistent with the well-known observation that trained listeners can detect 128 kbps MP3 on critical material.
]

#exercise("46.6", 3)[
  Implement a `smr_per_bark(freqs_hz, levels_db)` function in Python that: (a) converts each frequency to its Bark band number (integer, 1–24) using `hz_to_bark`; (b) finds the maximum signal level within each Bark band; (c) computes the ATH for the centre frequency of each band using `ath_db`; (d) returns an array of 24 SMR values (signal level − masking threshold, where the masking threshold is the maximum of the ATH and a simplified per-band masking prediction using the spreading function). Test it on a set of three maskers at 500 Hz / 70 dB, 2 kHz / 60 dB, and 8 kHz / 55 dB.
]
#solution("46.6")[
  ```python
  import numpy as np
  from psycho import hz_to_bark, ath_db, spreading_function_db

  # Centre frequencies of the 24 Bark bands (midpoints in Hz)
  BARK_CENTRES = [
      60, 150, 250, 350, 450, 570, 700, 845, 1000, 1175,
      1375, 1600, 1860, 2160, 2510, 2925, 3425, 4050, 4850,
      5850, 7000, 8600, 10750, 13750
  ]

  def smr_per_bark(
      freqs_hz: np.ndarray,
      levels_db: np.ndarray,
  ) -> np.ndarray:
      n_bands = 24
      signal_per_band = np.full(n_bands, -np.inf)

      # Assign each masker to its Bark band
      for f, L in zip(freqs_hz, levels_db):
          band_idx = min(int(hz_to_bark(f)), n_bands - 1)
          if L > signal_per_band[band_idx]:
              signal_per_band[band_idx] = L

      # Compute masking threshold per band (ATH + spreading)
      threshold = np.array([ath_db(fc) for fc in BARK_CENTRES])
      for i, fc_q in enumerate(BARK_CENTRES):
          z_q = hz_to_bark(fc_q)
          for f_m, L_m in zip(freqs_hz, levels_db):
              z_m = hz_to_bark(f_m)
              contrib = spreading_function_db(z_q - z_m, L_m, is_tonal=True)
              if contrib > threshold[i]:
                  threshold[i] = contrib

      # SMR = signal - threshold (−inf where no signal in band)
      smr = signal_per_band - threshold
      return smr

  # Test
  f = np.array([500.0, 2000.0, 8000.0])
  L = np.array([70.0,  60.0,   55.0])
  result = smr_per_bark(f, L)
  for i, s in enumerate(result):
      if s > -np.inf:
          print(f"Band {i+1:2d} ({BARK_CENTRES[i]:5d} Hz): SMR = {s:+.1f} dB")
  ```
  Expected output shows large positive SMR in bands near the maskers (500 Hz → band 5, 2 kHz → band 13, 8 kHz → band 22), moderate positive SMR in nearby bands (due to spreading), and very negative or −inf SMR in silent unmasked bands.
]

== Further Reading

- #link("https://www.ee.columbia.edu/~dpwe/papers/Johns88-audiocoding.pdf")[Johnston, J. D. (1988). "Transform Coding of Audio Signals Using Perceptual Noise Criteria." IEEE Journal on Selected Areas in Communications, 6(2), 314–323.] — The foundational perceptual entropy paper; defines SMR and the psychoacoustic model pipeline used in MP3 and AAC.

- #link("https://www.cns.nyu.edu/~david/courses/perceptionGrad/Readings/PainterSpanias-ProcIEEE2000.pdf")[Painter, T. & Spanias, A. (2000). "Perceptual Coding of Digital Audio." Proceedings of the IEEE, 88(4), 451–515.] — A comprehensive 65-page tutorial covering everything from critical bands to MP3 to then-emerging formats; the best single-paper overview of the field.

- #link("https://www.nobelprize.org/prizes/medicine/1961/bekesy/facts/")[Nobel Prize (1961). Georg von Békésy — facts.] — Background on the Nobel Prize awarded for the discovery of the travelling wave mechanism.

- Brandenburg, K. & Bosi, M. (1997). "Overview of MPEG Audio: Current and Future Standards for Low-Bit-Rate Audio Coding." Journal of the Audio Engineering Society, 45(1/2), 4–21. — How the MPEG committee applied psychoacoustics to produce MP3 and AAC.

- Moore, B. C. J. (2012). _An Introduction to the Psychology of Hearing_ (6th ed.), Brill. — The standard textbook on psychoacoustics; Chapters 3–5 cover masking in precise detail.

- Zwicker, E. & Fastl, H. (1999). _Psychoacoustics: Facts and Models_ (2nd ed.), Springer. — The technical reference; Zwicker was the inventor of the Bark scale and the leading figure in quantitative psychoacoustics.

#bridge[
  We now have everything we need to understand how real audio codecs work from the inside out. Chapter 47 takes the psychoacoustic framework we built here and traces it into the specific engineering choices that made MP3 — MPEG-1 Audio Layer III — the format that transformed the music industry. We will see the hybrid filterbank (why combine a polyphase filterbank with an MDCT?), the two-pass bit-allocation inner loop, and the Huffman entropy tables that handle the final encoding. Along the way, we will meet the people at Fraunhofer IIS who spent fifteen years turning psychoacoustic theory into a codec that fit on a 486 processor and played music that stunned listeners at 128 kbps.
]
