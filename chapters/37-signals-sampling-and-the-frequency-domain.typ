#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Signals, Sampling, and the Frequency Domain

#epigraph[If you would understand anything, observe its beginning and its development.][Aristotle (attributed)]

Hum a steady note. Now hum a different one, higher. What, physically, did you change? Not loudness — both notes can be equally loud. Not duration. You changed something your ear measures effortlessly but that we have not yet given a name or a number: the _frequency_ of the sound, how fast the air is wiggling back and forth. A low note wiggles slowly; a high note wiggles fast. A piano chord is several wiggle-rates happening at once. A spoken vowel is a particular recipe of wiggle-rates that your brain recognises as "ah" or "ee." A photograph, oddly, is also made of wiggle-rates — not in time but across space: a smooth blue sky is "slow" wiggling, a picket fence or a strand of hair is "fast" wiggling.

Here is the thunderbolt that the next several chapters are built around. _Almost everything your senses record can be taken apart into pure wiggles of different rates, the way a prism takes white light apart into colours._ That recipe — how much of each wiggle-rate is present — is called the *frequency-domain* view of the signal, and it is the single most useful change of perspective in all of media compression. Once you see a sound or an image as a recipe of frequencies, throwing away the parts nobody will notice becomes almost easy. Every lossy codec in this book — JPEG, MP3, the codec inside your phone's camera and the one inside your video call — earns its living in the frequency domain.

But before we can compute a frequency recipe we have to cross a chasm. The real world is _continuous_ — sound pressure has a value at every instant, with no gaps — yet a computer can only store a _finite list of numbers_. How do you turn an endless, smooth wave into a handful of numbers without losing the music? The astonishing answer, proved by a small group of engineers between 1915 and 1949, is that under one clean condition you lose _nothing at all_: a finite list of samples can hold a continuous signal perfectly. That theorem is the gateway to the digital world, and it is where this chapter begins.

#recap[
We are starting Volume III, _Lossy and Perceptual Media Compression_, and we lean hard on Volume I. From Chapter 7 we keep the *logarithm* and the idea of *exponential growth*; we will need its cousin, the *exponential function*, here. From Chapters 9 and 10 we keep *probability* and *expected value*. From Chapter 11 we keep $sum$ (sigma) *summation notation*, *sequences*, and the gentle idea of a *limit* and a *derivative* (a slope). From Chapter 12 we keep *vectors*, the *dot product*, *basis*, and *orthogonality* — they are the backbone of everything here. From Chapter 21 we keep the *rate–distortion function* $R(D)$, the proof that lossy compression has a theoretical floor; this chapter and the next build the machine that approaches it. And from Chapter 18 we keep *entropy* $H(X)$, the lossless floor we have spent all of Volume II chasing. Two new bits of mathematics — the *sine wave* and a friendly slice of *complex numbers* — get their own from-scratch boxes the moment we need them.
]

#objectives((
  [Explain what a *signal* is, the difference between *continuous* (analog) and *discrete* (digital) signals, and what *sampling* and *quantization* each do.],
  [Define *frequency*, *amplitude*, and *phase* of a sine wave, and read a signal as a sum of sine waves.],
  [State and prove (gently) the *Nyquist–Shannon sampling theorem*, and explain the *Nyquist rate* and why sampling too slowly causes *aliasing*.],
  [Define the *Discrete Fourier Transform (DFT)*, compute a small one by hand, and read its output as the *frequency recipe* (spectrum) of a signal.],
  [Explain how the *Fast Fourier Transform (FFT)* computes the same answer in $N log N$ instead of $N^2$ operations, and why that single speed-up made digital media possible.],
  [Connect the frequency domain to compression: why *energy compaction* in frequency is the doorway to every transform codec in the chapters ahead.],
))

== What is a signal?

Strip away the jargon and a *signal* is just _a quantity that varies_, usually with time or with position, carrying information by how it varies. The voltage on a microphone wire as you speak is a signal: it rises and falls in step with the air pressure at the microphone. The brightness along one row of a photograph is a signal: it varies from dark to light as you scan across the picture. Your weight measured every morning is a signal. The common thread is a _value that depends on something else_ — almost always time $t$ or a position $x$ — and we write it as a function, $x(t)$ or $s(t)$, read "the signal $s$ at time $t$."

#definition("Signal")[
A *signal* is a function $s(t)$ that assigns a value (the _amplitude_) to each point $t$ of some independent variable, usually time or space. The value is the thing we measure; the independent variable is the thing we measure it _against_.
]

The deepest split in this whole subject is between two kinds of signal, and getting it straight now will save you confusion for five chapters.

A *continuous-time* signal (often called *analog*) is defined at _every_ instant. Between any two moments there is always another moment, and the signal has a value there too. Real-world sound, light, and voltage are continuous: there is no smallest gap in time. A continuous signal is an unbroken curve you could draw without lifting your pen.

A *discrete-time* signal is defined only at a _list_ of separate instants — say once every millisecond — and is simply undefined in between. It is a sequence of numbers, exactly the kind of object Chapter 11 called a sequence and Chapter 16 stored in a Python `list`. A discrete signal is a row of dots, not a curve.

#fig([A continuous signal (smooth curve) and the discrete signal obtained by *sampling* it at evenly spaced instants — keeping only the dots. The whole question of this chapter is: when do the dots remember the curve?], cetz.canvas({
  import cetz.draw: *
  line((-0.2, 0), (8.2, 0), mark: (end: ">"))
  line((0, -1.4), (0, 1.6), mark: (end: ">"))
  content((8.4, -0.25))[time $t$]
  content((-0.35, 1.5))[$s$]
  let pts = ()
  for i in range(0, 161) {
    let x = i/20
    let y = 1.05 * calc.sin(x * 1.15) * calc.cos(x*0.4)
    pts.push((x, y))
  }
  line(..pts, stroke: 1.1pt + rgb("#0b5394"))
  for k in range(0, 11) {
    let x = k * 0.8
    let y = 1.05 * calc.sin(x * 1.15) * calc.cos(x*0.4)
    line((x, 0), (x, y), stroke: (paint: rgb("#9a2617"), thickness: 0.5pt, dash: "dotted"))
    circle((x, y), radius: 0.07, fill: rgb("#9a2617"), stroke: none)
  }
}))

Turning a continuous signal into a discrete one is called *sampling*: you look at the signal at regularly spaced instants and write down its value each time, ignoring everything in between. The gap between two looks is the *sampling interval* $T$ (in seconds), and its reciprocal, how many samples you take per second, is the *sampling rate* or *sampling frequency* $f_s = 1\/T$ (in samples per second, called *hertz*, abbreviated Hz). A compact disc samples sound $44{,}100$ times a second, so $f_s = 44.1$ kHz and $T approx 22.7$ microseconds.

A worked example fixes the units in place. Suppose we sample a $1$-second tone at $f_s = 8{,}000$ Hz. Then the sampling interval is $T = 1\/8000 = 0.000125$ s $= 125$ microseconds, and we collect exactly $f_s times 1 "s" = 8{,}000$ samples. If instead we record $10$ seconds at the CD rate $44{,}100$ Hz, we collect $44{,}100 times 10 = 441{,}000$ samples — and in _stereo_ (two channels) twice that, $882{,}000$ numbers, each typically $2$ bytes, giving about $1.76$ megabytes for ten seconds of raw audio. That number is exactly why compression exists: a three-minute song is over $30$ megabytes raw, and MP3 will shrink it tenfold by working, as we will see, in the frequency domain.

Sampling fixes _when_ we look. A second, separate step fixes _what we are allowed to write down_: a real number like $0.7183...$ has infinitely many digits, but a computer stores finitely many, so each sample is rounded to one of a finite set of levels. That rounding is *quantization*, and it is so central to lossy compression that Chapter 39 is devoted entirely to it. For now, hold the two apart in your mind: *sampling discretises time; quantization discretises value.* This chapter is about sampling and what comes after it; quantization waits its turn.

#keyidea[
Two independent discretisations turn analog into digital. *Sampling* chops the _time axis_ into evenly spaced instants. *Quantization* chops the _value axis_ into finitely many levels. Sampling is the subject of this chapter; it can, remarkably, be _lossless_. Quantization (Chapter 39) is where the loss in "lossy" compression is born.
]

#history[
The leap from analog to digital is not a metaphor; it was a deliberate engineering revolution. The telephone network of the 1950s–70s carried voice as continuous voltage; converting it to a stream of samples (*pulse-code modulation*, PCM, invented by *Alec Reeves* in 1937 and made practical at Bell Labs in the following decades) made it possible to send voice as _numbers_, immune to the hiss and fade that plague analog wires. Every digital recording, every phone call today, every line of this book travels as samples. The theorem that licenses it all — that a finite list of samples can stand in for a continuous wave with _no loss_ — is the one we prove below.
]

== Sine waves: the atoms of signals

To talk about frequency we need the simplest possible signal that has a single, definite frequency: the *sine wave*. It is the shape a perfectly elastic spring traces as it bobs, the shape of a pure musical tone, the shape of the voltage from the wall socket. Everything else in this chapter is built from sine waves the way molecules are built from atoms, so we spend a moment making them concrete.

#gomaths("The sine wave, from a spinning wheel")[
Picture a point painted on the rim of a wheel of radius $A$, turning at a steady speed. Watch only its _height_ above the centre as the wheel spins. That height traces a smooth up-and-down curve: the *sine wave*. Three numbers describe it completely.

*Amplitude* $A$ — the radius of the wheel — is how far the height swings from the middle to the top. Bigger $A$ means a louder sound or a brighter stripe.

*Frequency* $f$ — how many full turns the wheel makes per second — is how fast it wiggles, measured in hertz (Hz). One full turn is one *cycle*. A 440 Hz wave (musical A) completes 440 cycles every second.

*Phase* $phi.alt$ — where the painted point started — is a head-start, a shift left or right in time. It decides whether the curve begins at zero, at the top, or somewhere between.

In symbols, a sine wave of amplitude $A$, frequency $f$, and phase $phi.alt$ is
$ s(t) = A sin(2 pi f t + phi.alt). $
The $2 pi$ is there because one full turn of the wheel is $2 pi$ _radians_ (the natural way to measure angles: a full circle is $2 pi approx 6.283$ radians, just as it is $360$ degrees). So $2 pi f$ is "radians turned per second," and $2 pi f t$ is "radians turned after $t$ seconds." A tiny numeric check: at $f = 1$ Hz and $t = 1\/4$ second, the wheel has turned a quarter circle, $2 pi dot 1 dot 1\/4 = pi\/2$ radians, and $sin(pi\/2) = 1$ — the height is at its maximum $A$, exactly as a quarter-turn from the start should be.
]

A sine wave's _period_ — the time for one full cycle — is $T_"per" = 1\/f$. The musical A at $440$ Hz repeats every $1\/440 approx 2.27$ milliseconds. The *cosine* is the very same shape shifted by a quarter cycle: $cos(theta) = sin(theta + pi\/2)$. We will use both, and treat "sinusoid" as the umbrella word for any sine or cosine of a given frequency.

Now the magic, stated plainly and proved by Joseph Fourier in 1822: _any_ reasonable signal, no matter how jagged, can be built by adding together sine waves of different frequencies, amplitudes, and phases. A square wave, a vowel, a drumbeat, the brightness across a photograph — all are sums of sinusoids. This is *Fourier's theorem*, and the list of "how much of each frequency you need" is the signal's *frequency content* or *spectrum*. The whole frequency-domain idea is just this: instead of describing a signal by its value at each _time_, describe it by its _amount at each frequency_. Same information, different costume — and for compression, a far more useful costume.

#fig([Building a jagged signal by adding sinusoids. The flat-topped wave (heavy line) is the sum of just three odd-frequency sine waves (thin lines): a square wave is mostly its lowest frequency plus shrinking high-frequency corrections.], cetz.canvas({
  import cetz.draw: *
  line((-0.2, 0), (8.2, 0), mark: (end: ">"))
  content((8.45, -0.25))[$t$]
  let comp(mult, amp) = {
    let p = ()
    for i in range(0, 161) {
      let x = i/20
      p.push((x, amp*calc.sin(x*mult)))
    }
    p
  }
  line(..comp(1.2, 0.75), stroke: 0.5pt + rgb("#0b6e4f"))
  line(..comp(3.6, 0.25), stroke: 0.5pt + rgb("#0b6e4f"))
  line(..comp(6.0, 0.15), stroke: 0.5pt + rgb("#0b6e4f"))
  let s = ()
  for i in range(0, 161) {
    let x = i/20
    let y = 0.75*calc.sin(x*1.2) + 0.25*calc.sin(x*3.6) + 0.15*calc.sin(x*6.0)
    s.push((x, y))
  }
  line(..s, stroke: 1.3pt + rgb("#0b5394"))
}))

#checkpoint[Middle C on a piano is about $262$ Hz. How long does one cycle of a pure $262$ Hz tone last, and how many cycles fit in one second of audio?][One cycle lasts $T_"per" = 1\/262 approx 0.00382$ s, about $3.82$ milliseconds. In one second there are, by definition of frequency, $262$ cycles. (Frequency in hertz _is_ "cycles per second.")]

== The sampling theorem: when do the dots remember the curve?

Return to the central puzzle. We have a smooth continuous signal; we keep only its values at evenly spaced sample instants. Have we thrown information away? Sometimes obviously yes: a wave that wiggles up and down a hundred times between two samples is hopeless — our samples skip right over the wiggles and we will never recover them. But sometimes, remarkably, _no_: if the signal is "smooth enough" relative to how often we sample, the dots remember the curve _exactly_, and we can rebuild the continuous wave from the samples with zero error. The theorem tells us precisely where the boundary lies.

The key idea is *bandwidth*. By Fourier, a signal is a sum of sinusoids; the *bandwidth* is the highest frequency present in that sum. A signal is *band-limited* to $B$ hertz if it contains no frequency above $B$ — its Fourier recipe stops at $B$. Human hearing tops out near $20$ kHz, so audio for human ears is essentially band-limited to about $20$ kHz; everything above is inaudible and can be filtered away before sampling.

#theorem("Nyquist–Shannon sampling theorem")[
If a continuous signal $s(t)$ contains no frequency higher than $B$ hertz, then it is completely determined by its samples taken at a rate of more than $2B$ samples per second. From those samples the original $s(t)$ can be reconstructed _exactly_.
]

The number $2B$ is the *Nyquist rate*: the minimum sampling rate that captures a signal of bandwidth $B$ without loss. Equivalently, if you sample at rate $f_s$, the highest frequency you can faithfully capture is $f_s\/2$, called the *Nyquist frequency*. This is exactly why CDs sample at $44.1$ kHz: a hair above twice the $\~20$ kHz limit of hearing, leaving a little room for the filter to do its work.

#keyidea[
To capture a signal whose fastest wiggle is $B$ hertz, sample _faster than twice_ $B$. You need at least two samples per cycle of the fastest sinusoid present — one to catch its rise, one to catch its fall. Below that, the fast wiggle disguises itself as a slow one (aliasing). The threshold $f_s = 2B$ is the *Nyquist rate*; half your sampling rate, $f_s\/2$, is the highest frequency you can honestly record.
]

Why two samples per cycle, and not, say, one or three? Here is the intuition first, then a real proof. One sample per cycle is plainly too few: a sine wave sampled once per period gives you the same value every time — a flat line — and you cannot tell its amplitude or even that it is moving. You need at least one sample on the way _up_ and one on the way _down_ to know there is an oscillation at all, and that means at least two per cycle. Two is not merely necessary but _sufficient_, and that sufficiency is the deep half of the theorem. Let us prove the _necessary_ half first, because it is short and completely convincing, then prove the _sufficient_ half.

#theorem("Necessity of the Nyquist rate")[
If a signal is sampled at rate $f_s$, then any sinusoid of frequency exactly $f_s\/2$ or higher cannot, in general, be recovered from the samples — its amplitude and phase are lost.
]

#proof[
Consider the sinusoid $s(t) = A sin(2 pi f t + phi.alt)$ sampled at instants $t_n = n T$ with $T = 1\/f_s$, so the samples are $s_n = A sin(2 pi f n T + phi.alt)$. Take the worst case $f = f_s\/2$, the Nyquist frequency itself. Then $2 pi f n T = 2 pi (f_s\/2) n (1\/f_s) = pi n$, and the samples become
$ s_n = A sin(pi n + phi.alt) = A [sin(pi n) cos phi.alt + cos(pi n) sin phi.alt] = A (-1)^n sin phi.alt, $
using $sin(pi n) = 0$ and $cos(pi n) = (-1)^n$. Every sample is $plus.minus A sin phi.alt$. Notice the amplitude $A$ and the phase $phi.alt$ appear only through the single product $A sin phi.alt$. A loud wave at one phase ($A$ large, $phi.alt$ small) produces _identical_ samples to a quiet wave at another phase. In the special case $phi.alt = 0$ every sample is exactly zero — the wave is _invisible_ regardless of how loud it is. So the samples cannot determine the sinusoid: necessity is forced. The same collapse afflicts every frequency above $f_s\/2$ by the folding argument of the next section, which is why the theorem demands $f_s$ _strictly greater_ than $2B$.
]

#proof[
We give the classical argument, leaning only on Fourier's theorem. Suppose $s(t)$ is band-limited to $B$ hertz: its spectrum $S(f)$ — the amount of each frequency $f$ — is zero for $abs(f) > B$. Sampling $s(t)$ every $T = 1\/f_s$ seconds is, mathematically, multiplying it by an infinitely fine comb of spikes, one at each sample instant. A foundational fact of Fourier analysis (the one Exercise 37.7 explores) is that multiplying by a comb in _time_ becomes _copying-and-shifting_ in _frequency_: the spectrum of the sampled signal is the original spectrum $S(f)$ repeated over and over, with a copy centred at every multiple of the sampling rate $f_s$ — at $0, plus.minus f_s, plus.minus 2 f_s, dots$

Now picture those copies on the frequency axis. The original spectrum occupies the band from $-B$ to $+B$. Its neighbour, shifted by $f_s$, occupies $f_s - B$ to $f_s + B$. The two copies stay clear of each other exactly when the right edge of the original, $+B$, sits below the left edge of the neighbour, $f_s - B$:
$ B < f_s - B quad <==> quad f_s > 2 B. $
When $f_s > 2B$, the copies are separated by clean gaps. We can then slide a perfect "low-pass filter" over the central copy — a window that keeps frequencies below $f_s\/2$ and discards the rest — and recover $S(f)$ untouched, hence $s(t)$ exactly. When $f_s <= 2B$, the copies _overlap_; high frequencies from one copy land on top of low frequencies of another, their values add together, and no filter can ever separate them again. That overlap _is_ aliasing, and it is irreversible.
]

The reconstruction is not just abstract existence; there is an explicit formula, the *Whittaker–Shannon interpolation formula*, that rebuilds the continuous curve from the dots:
$ s(t) = sum_(n=-oo)^(oo) s(n T) dot "sinc"((t - n T)/T), quad "where" "sinc"(x) = (sin(pi x))/(pi x). $
Each sample $s(n T)$ is multiplied by a gently rippling "sinc" bump centred at its own instant; add up all the bumps and the smooth original reappears, valleys and peaks filled in between the dots. You do not need to memorise this formula, only to believe what it asserts: under the Nyquist condition, the samples contain _everything_, and the in-between values were never independent information at all.

It pays to dwell on _why_ the sinc bump is the right shape, because it explains a practical fact you have heard without knowing it. The sinc function, $sin(pi x)\/(pi x)$, is exactly $1$ at its own centre ($x = 0$) and exactly $0$ at every other integer ($x = plus.minus 1, plus.minus 2, dots$). So the bump centred on sample $n$ contributes the full value $s(n T)$ at that sample's instant and contributes _nothing_ at every other sample's instant — the reconstruction passes precisely through all the dots, then fills the gaps with the unique band-limited curve that connects them. There is only one such curve, which is the whole content of the theorem. A real digital-to-analog converter — the chip in a phone or a CD player that turns numbers back into sound — is an approximation of this sinc interpolation: it cannot use an infinitely long sinc (that would need all past and future samples), so it uses a finite, carefully designed *reconstruction filter* and accepts a tiny, inaudible error. This is the unsung second half of the analog–digital round trip: sampling on the way in, sinc-shaped interpolation on the way out.

#note[
Real systems never use an _ideal_ filter, so they cannot sample at exactly $2B$; they leave a margin and oversample a little, then let an imperfect but cheap filter do the rest. A few sampling rates you live with daily, each chosen as "a bit above twice the highest frequency that matters": telephone speech at $8$ kHz (voice energy below $\~3.4$ kHz); CD audio at $44.1$ kHz and professional/film audio at $48$ kHz (hearing below $\~20$ kHz); high-resolution audio at $96$ or $192$ kHz (margin for gentle filters, mostly inaudible benefit); film at $24$ frames per second and video at $30$ or $60$ (motion the eye perceives as smooth); a phone camera at tens of millions of pixels (spatial sampling fine enough that aliasing is rare on ordinary scenes). Every one of these numbers is a Nyquist decision in disguise.
]

#history[
The theorem carries many names because many people found it. *Edmund Whittaker* published the interpolation formula in 1915. *Harry Nyquist* (the same Nyquist who, with Hartley, prefigured Shannon's information theory in Chapter 18) showed in 1928 that a channel of bandwidth $B$ can carry $2B$ independent pulses per second. *Vladimir Kotelnikov*, in the Soviet Union, proved the full sampling theorem in 1933 — which is why Russian texts call it Kotelnikov's theorem. And *Claude Shannon* stated and proved it cleanly in his 1949 paper _Communication in the Presence of Noise_, tying it into information theory. The honest name is the *Whittaker–Nyquist–Kotelnikov–Shannon theorem*; we will follow common usage and say *Nyquist–Shannon*.
]

#algo(
  name: "Nyquist–Shannon Sampling Theorem",
  year: "1915–1949",
  authors: "Whittaker; Nyquist; Kotelnikov; Shannon",
  aim: "Determine exactly when a continuous (analog) signal can be perfectly represented and reconstructed from evenly spaced samples.",
  complexity: "Reconstruction by ideal sinc interpolation; in practice an analog low-pass filter before sampling and after reconstruction.",
  strengths: "Proves sampling can be perfectly lossless; gives the exact rate threshold; foundation of all digital audio, video, and imaging.",
  weaknesses: "Requires a strictly band-limited signal and an ideal (non-causal, infinitely long) reconstruction filter; real systems approximate both and must oversample slightly.",
  superseded: "Generalised, never overturned (compressed sensing, 2006, samples below Nyquist when the signal is sparse — an addition, not a refutation).",
)[
The single most consequential theorem for digital media. It tells the engineer the one number — the sampling rate — that decides whether digitising a signal keeps the music or wrecks it. Sample above $2B$ and the analog world fits, losslessly, into a finite list of numbers; sample below and you suffer aliasing forever.
]

== Aliasing: when fast pretends to be slow

What actually goes wrong when you sample too slowly is worth seeing directly, because *aliasing* is not a rare pathology — it is the constant enemy that every camera, microphone, and codec must defend against. When the sampling rate falls below the Nyquist rate, a frequency that is too high to capture does not simply vanish. It _disguises itself_ as a lower frequency that the sampling rate _can_ represent, and the disguise is perfect: from the samples alone, the impostor is indistinguishable from a genuine low tone. The high frequency has stolen the identity — the "alias" — of a low one.

#fig([Aliasing. A fast sine wave (light) sampled too slowly (dots) is indistinguishable from a slow sine wave (heavy) drawn through the very same dots. From the samples alone you cannot tell which signal you had.], cetz.canvas({
  import cetz.draw: *
  line((-0.2, 0), (8.4, 0), mark: (end: ">"))
  content((8.6, -0.25))[$t$]
  let fast = ()
  for i in range(0, 169) {
    let x = i/20
    fast.push((x, 1.0*calc.sin(x*5.5)))
  }
  line(..fast, stroke: 0.6pt + rgb("#0b6e4f"))
  let slow = ()
  for i in range(0, 169) {
    let x = i/20
    slow.push((x, 1.0*calc.sin(x*0.78)))
  }
  line(..slow, stroke: 1.3pt + rgb("#0b5394"))
  for k in range(0, 11) {
    let x = k*0.805
    let y = 1.0*calc.sin(x*0.78)
    circle((x, y), radius: 0.07, fill: rgb("#9a2617"), stroke: none)
  }
}))

You have seen aliasing with your own eyes. In old films, a fast-spinning wagon wheel sometimes appears to turn slowly backward: the camera samples the wheel $24$ times a second, the spokes move _almost_ a full gap between frames, and the eye reads the small leftover motion as slow reverse rotation. That is temporal aliasing — the wheel's true frequency exceeds half the frame rate, so it aliases to a slow, even negative, apparent frequency. In images, aliasing shows as *moiré*: photograph a finely striped shirt or a distant brick wall and shimmering false patterns appear, high spatial frequencies (the close stripes) folding down into coarse, wrong ones because the sensor's pixel grid samples them too sparsely.

#gomaths("The folding formula for an alias")[
If you sample at rate $f_s$ and feed in a pure tone of frequency $f$ above the Nyquist frequency $f_s\/2$, it appears at the *aliased frequency*
$ f_"alias" = abs(f - f_s dot "round"(f \/ f_s)), $
which always lands in the representable band $0$ to $f_s\/2$. A quick numeric example: sample at $f_s = 1000$ Hz and present a $700$ Hz tone. The nearest multiple of $1000$ is $1000$, so $f_"alias" = abs(700 - 1000) = 300$ Hz. The $700$ Hz tone is recorded as though it were a $300$ Hz tone, and nothing downstream can undo it. Notice $700$ and $300$ are mirror images about the Nyquist frequency $500$: frequencies "fold" around $f_s\/2$ like light off a mirror, which is why $f_s\/2$ is also called the _folding frequency_.
]

A fully worked aliasing example drives the danger home. Imagine a digital camera whose sensor samples brightness at $100$ "pixels per centimetre" across a scene, so its spatial Nyquist frequency is $50$ cycles per centimetre — the finest stripe pattern it can honestly resolve. Now photograph a shirt with $70$ stripes per centimetre. The folding formula gives the apparent pattern: the nearest multiple of $100$ is $100$, so $f_"alias" = abs(70 - 100) = 30$ cycles per centimetre. The fine $70$-stripe weave is recorded as a coarse $30$-stripe pattern that _is not on the shirt at all_ — the shimmering false bands you have seen in photos of suits and television presenters' ties. Worse, the false pattern often _moves_ as the camera shifts, because the aliasing relationship changes with sub-pixel position. No amount of post-processing recovers the true weave; the information folded down and merged with real low-frequency content the instant the sensor sampled it.

The defence is simple and universal: before sampling, pass the signal through an *anti-aliasing filter* — a low-pass filter that removes every frequency above $f_s\/2$ _before_ the samples are taken. If the high frequencies are gone before sampling, they cannot fold down and corrupt the low ones. Every camera sensor, every audio interface, every video encoder applies one. It is the reason your CD player's $44.1$ kHz does not turn an inaudible $30$ kHz squeak into an audible $14.1$ kHz whine: the squeak was filtered out before it ever became a sample.

#misconception[A higher sampling rate always gives a more faithful recording, so more is always better.][Above the Nyquist rate, extra samples buy you _nothing_ in fidelity — the theorem says the signal is _already_ captured exactly once you exceed $2B$. Doubling $44.1$ kHz audio to $88.2$ kHz cannot make the audible band sound better; it only doubles the data and the cost. What oversampling _does_ buy is engineering slack: gentler, cheaper anti-aliasing filters, and room to push quantization noise out of the audible band (Chapter 39). Beyond that practical margin, "more samples" is just bigger files, which is the opposite of what this book is about.]

== The frequency recipe by hand: the Discrete Fourier Transform

We now have a list of samples that faithfully holds a band-limited signal. The next move — the one that powers all of lossy compression — is to compute the signal's _frequency recipe_ from those samples: how much of each frequency is present. For a finite list of $N$ samples, the tool that does this is the *Discrete Fourier Transform*, the DFT. It takes $N$ numbers in (the signal in the time domain) and gives $N$ numbers out (the signal in the frequency domain), each output telling you the strength of one particular frequency.

Here is the idea, and it is beautifully simple once you have the dot product from Chapter 12. To ask "how much of frequency $k$ is in my signal?", you _compare_ the signal against a pure wave of frequency $k$ and measure how well they march in step. The comparison is a dot product: multiply the signal sample-by-sample against the test wave and add up the products. If the signal contains that frequency, the products reinforce and the sum is large; if it does not, the products cancel to near zero. Do this for every frequency $k = 0, 1, dots, N-1$ and you have the whole recipe. This is the very same move that powered the entropy coders of Volume II in spirit — _project the data onto a better basis_ — except now the basis is made of waves rather than symbols, and the goal is to expose structure the eye and ear care about.

#misconception[The Fourier transform deals with continuous, infinite signals, so it is too abstract and mathematical to compute on a real computer.][There are several Fourier transforms, and the one we compute is thoroughly finite and concrete. The _continuous_ Fourier transform of pure mathematics integrates over all time and produces a frequency function for every real frequency — beautiful, but uncomputable as stated. The *Discrete Fourier Transform* takes a _finite list_ of $N$ samples in and gives a _finite list_ of $N$ numbers out, with nothing but multiplications and additions; it is exactly what a computer does and exactly what this chapter defines. The continuous version is the theory; the DFT is the practice. Every "Fourier transform" inside a codec is a DFT, and (almost always) computed by an FFT. You will never integrate anything to compress a JPEG.]

There is one more frequency to keep straight. The DFT's index $k$ counts whole _cycles per block_: $k = 1$ means "one full cycle across the $N$ samples," $k = 2$ means "two cycles across the block," and so on. To turn a bin index $k$ into a real-world frequency in hertz you multiply by the *bin spacing* $f_s\/N$: bin $k$ corresponds to $f = k dot f_s\/N$ hertz. A block of $N = 1024$ samples at $f_s = 48{,}000$ Hz therefore resolves frequency in steps of $48000\/1024 approx 46.9$ Hz — coarse enough that two close piano notes might share a bin, which is exactly the time–frequency trade-off we meet shortly.

#gomaths("A friendly slice of complex numbers")[
The DFT is cleanest with one new tool: the *complex exponential*. You need only three facts.

First, mathematicians invented a number $i$ with $i^2 = -1$ — a "$90$-degree turn." A *complex number* $a + b i$ is then just a point in a plane, $a$ across and $b$ up; you can picture it as an arrow from the origin.

Second, *Euler's formula* says that the arrow of length $1$ at angle $theta$ is written
$ e^(i theta) = cos theta + i sin theta. $
So $e^(i theta)$ is simply "a point on the unit circle at angle $theta$" — a sine and a cosine bundled into one tidy symbol. As $theta$ grows, the arrow spins around the circle. That is exactly the spinning wheel that made our sine waves, now in one object.

Third, multiplying by $e^(i theta)$ _rotates_ by angle $theta$. That is all we use. Wherever you see $e^(-i 2 pi k n \/ N)$ below, read it as "a unit arrow pointing at angle $-2 pi k n \/ N$" — a sample of a pure cosine-and-sine wave of frequency $k$. The minus sign just makes the wheel spin clockwise; it is a convention.

One last word we will lean on in the proofs: the *complex conjugate* of $z = a + b i$, written $overline(z)$, is the mirror image $a - b i$ — the same arrow flipped to the other side of the horizontal axis (its "up" part negated). It has one property we use: $z dot overline(z) = a^2 + b^2 = abs(z)^2$, the arrow's squared length, a plain non-negative real number. So conjugating then multiplying is how you square the length of a complex arrow, exactly as $x dot x = x^2$ does for an ordinary number.
]

#definition("Discrete Fourier Transform (DFT)")[
Given $N$ samples $x_0, x_1, dots, x_(N-1)$, their *DFT* is the list of $N$ numbers $X_0, dots, X_(N-1)$ defined by
$ X_k = sum_(n=0)^(N-1) x_n dot e^(-i 2 pi k n \/ N), quad k = 0, 1, dots, N-1. $
Each $X_k$ measures the amount of frequency $k$ in the signal. Its size $abs(X_k)$ is that frequency's *amplitude* (how loud); its angle is the *phase* (its head-start). $X_0$, where the wave is constant, is simply the sum of all samples — the signal's average times $N$, the "DC" or zero-frequency term.
]

Two pieces of vocabulary make this readable. The number $abs(X_k)$ is how _much_ of frequency $k$ there is; the collection of all the $abs(X_k)$ is the *magnitude spectrum*, the picture you see on a graphic equaliser's dancing bars. And by symmetry, for a real-valued signal $X_k$ and $X_(N-k)$ are mirror images (complex conjugates), so the genuinely new information lives in the first half, frequencies $0$ up to $N\/2$ — which is exactly the Nyquist frequency again, reappearing on its own. That two-for-the-price-of-one symmetry is why a real-valued block of $N$ samples really only has about $N\/2$ independent frequencies, and it is exploited by every real-signal FFT to run twice as fast.

#gomaths("Magnitude and phase: reading one complex coefficient")[
Each DFT output $X_k$ is a complex number — an arrow in the plane (the previous box). Any arrow is described two ways: by its $x$ and $y$ components $a + b i$, or by its _length_ and _angle_. The *magnitude* is the length,
$ abs(X_k) = sqrt(a^2 + b^2), $
and it answers "how _much_ of frequency $k$ is present" — the loudness of that pitch. The *phase* is the angle,
$ angle X_k = arctan(b \/ a), $
and it answers "_where in its cycle_ does that frequency start" — its left-right shift in time. (Here $arctan$, "arc-tangent," is simply the function that turns the two side-lengths of the arrow — $a$ across and $b$ up — back into _the angle_ it points at, the reverse of the spinning-wheel picture that turned an angle into a height. You will never compute it by hand — every calculator and every `math.atan2` call in Python does it for you — you only need to know it converts "$a$ across, $b$ up" into "pointing at this angle.") A tiny example: if $X_3 = 0$, frequency $3$ is simply absent. If $X_3 = 4i$, then $abs(X_3) = 4$ (a strong frequency) at phase $angle X_3 = 90$ degrees (a quarter-cycle head start, i.e. a pure sine rather than a pure cosine). For most compression the ear and eye care far more about magnitude than phase, which is one early hint of where bits can be saved — though, as the audio chapters show, phase matters more than that first guess suggests.
]

#fig([The DFT as a change of view. The same data, twice: on the left a row of time samples; on the right the magnitude spectrum — how much of each frequency is present. Compression happens because the right-hand picture is often mostly empty.], cetz.canvas({
  import cetz.draw: *
  content((1.4, 2.0))[*time domain*]
  line((0, 0), (3.0, 0), mark: (end: ">"))
  line((0, -1.2), (0, 1.4))
  for k in range(0, 9) {
    let x = 0.32 + k*0.32
    let y = 0.9*calc.sin(k*1.1) + 0.3*calc.sin(k*2.7)
    line((x, 0), (x, y), stroke: 0.5pt + rgb("#9a2617"))
    circle((x, y), radius: 0.05, fill: rgb("#9a2617"), stroke: none)
  }
  content((3.95, 0.1))[$arrow.r.long$]
  content((3.95, 0.55), text(size: 8pt)[DFT])
  content((6.6, 2.0))[*frequency domain*]
  line((4.9, 0), (8.3, 0), mark: (end: ">"))
  line((4.9, 0), (4.9, 1.4))
  let heights = (0.2, 1.2, 0.15, 0.55, 0.1, 0.08, 0.06, 0.05)
  for (j, h) in heights.enumerate() {
    let x = 5.2 + j*0.36
    rect((x - 0.12, 0), (x + 0.12, h), fill: rgb("#0b5394"), stroke: none)
  }
  content((6.7, -0.45), text(size: 8pt)[frequency $k arrow.r$])
}))

Let us compute a tiny DFT entirely by hand, because nothing demystifies a formula like watching it spit out a number. Take the shortest interesting signal, $N = 4$ samples: $x = (1, 0, -1, 0)$. This is one full cycle of a cosine sampled four times — up, zero, down, zero — so we _expect_ the recipe to say "all of frequency $1$, nothing else."

For $N = 4$ the rotation factor is $e^(-i 2 pi k n \/ 4) = e^(-i pi k n \/ 2)$, which takes only the four values $1, -i, -1, i$ as the angle steps by quarter-turns. Compute each output. First the zero-frequency term,
$ X_0 = x_0 + x_1 + x_2 + x_3 = 1 + 0 + (-1) + 0 = 0, $
so the average is zero, as it should be for a wave that swings symmetrically about zero. Next,
$ X_1 = x_0 dot 1 + x_1 dot (-i) + x_2 dot (-1) + x_3 dot i = 1 - 0 + 1 + 0 = 2, $
a clean, large value — the signal is _all_ frequency $1$, just as designed. Then
$ X_2 = x_0 dot 1 + x_1 dot (-1) + x_2 dot 1 + x_3 dot (-1) = 1 + 0 - 1 + 0 = 0, $
and by the mirror symmetry $X_3 = 2$ as well. The recipe reads $(0, 2, 0, 2)$: energy only at frequency $1$ (and its mirror image $3$), nothing at $0$ or $2$. The DFT looked at four numbers and correctly announced, "this is a pure tone of frequency $1$." That is the whole trick, scaled up to millions of samples in real codecs.

#checkpoint[Without computing all of it, what is $X_0$ for the samples $x = (3, 1, 4, 1, 5, 9, 2, 6)$?][$X_0$ is always the plain sum of the samples (every rotation factor is $1$ when $k = 0$): $3+1+4+1+5+9+2+6 = 31$. It is the signal's total, and dividing by $N = 8$ gives the average, $3.875$ — the "DC" level the signal hovers around.]

Let us watch the DFT run in Python on a signal we built ourselves, so you can see the recipe come back out.

#gopython("Loops, lists, and complex numbers in Python")[
Python has complex numbers built in: write `2 + 3j` (engineers use `j`, not `i`). The module `cmath` gives `cmath.exp(z)` for the complex exponential $e^z$, and `abs(z)` gives the arrow's length $abs(z)$. We also use a *list comprehension* (Chapter 16): `[f(n) for n in range(N)]` builds a list by running `f` for each `n`. And `sum(...)` adds an iterable up. With those, the DFT formula transcribes almost letter for letter.
```python
import cmath, math

def dft(x: list[complex]) -> list[complex]:
    """Discrete Fourier Transform of a list of samples."""
    N = len(x)
    return [
        sum(x[n] * cmath.exp(-2j * math.pi * k * n / N) for n in range(N))
        for k in range(N)
    ]

samples = [1.0, 0.0, -1.0, 0.0]          # one cosine cycle, N=4
spectrum = dft(samples)
print([round(abs(c), 3) for c in spectrum])   # -> [0.0, 2.0, 0.0, 2.0]
```
The output `[0.0, 2.0, 0.0, 2.0]` is exactly the by-hand recipe above: all the energy sits at frequency $1$ and its mirror $3$. The `round(..., 3)` just hides the tiny $10^(-16)$ dust that floating-point arithmetic always leaves behind.
]

The DFT is invertible: an *inverse DFT*, almost the same formula with the sign of the exponent flipped and a $1\/N$ out front, rebuilds the exact time samples from the spectrum,
$ x_n = 1/N sum_(k=0)^(N-1) X_k dot e^(+i 2 pi k n \/ N). $
So nothing is lost in going to the frequency domain and back — it is a lossless change of coordinates, a rotation of the data (in the precise sense of Chapter 12's orthogonal transforms). Why this works is worth proving, because the same orthogonality is the secret engine inside every transform codec to come.

#theorem("Orthogonality of the DFT waves, and exact invertibility")[
The $N$ pure waves $w_k = (e^(i 2 pi k n \/ N))_(n=0)^(N-1)$, one per frequency $k$, are mutually *orthogonal*: distinct frequencies have dot product zero. Consequently the inverse-DFT formula above recovers the original samples exactly.
]

#proof[
The dot product of wave $k$ with wave $m$ (using the conjugate for complex vectors, Chapter 12) is the geometric sum
$ sum_(n=0)^(N-1) e^(i 2 pi k n \/ N) dot e^(-i 2 pi m n \/ N) = sum_(n=0)^(N-1) r^n, quad r = e^(i 2 pi (k - m) \/ N). $
If $k = m$ then $r = 1$ and every term is $1$, so the sum is $N$. If $k != m$ then $r != 1$, and the finite geometric series (Chapter 11) sums to $(r^N - 1)\/(r - 1)$; but $r^N = e^(i 2 pi (k - m)) = 1$ because $k - m$ is a whole number, so the numerator is $0$ and the whole sum is $0$. In one line:
$ sum_(n=0)^(N-1) e^(i 2 pi (k - m) n \/ N) = cases(N\, & "if" k = m, 0\, & "if" k != m.) $
The frequencies are an orthogonal basis. Now substitute the forward DFT $X_k = sum_n x_n e^(-i 2 pi k n \/ N)$ into the inverse formula and swap the order of the two sums:
$ 1/N sum_(k=0)^(N-1) X_k e^(i 2 pi k ell \/ N) = 1/N sum_(n=0)^(N-1) x_n underbracket(sum_(k=0)^(N-1) e^(i 2 pi k (ell - n) \/ N), = N "only when" n = ell) = 1/N dot x_ell dot N = x_ell. $
Every cross term ($n != ell$) is annihilated by orthogonality, and the surviving term reproduces $x_ell$ exactly. The DFT is therefore a perfectly invertible change of coordinates: lossless, to the last bit.
]

That losslessness matters: the _transform_ throws nothing away; the throwing-away happens later, when we _quantize_ the coefficients. The transform's only job is to rearrange the signal so that the quantizer can do its job cheaply.

== The Fast Fourier Transform: the algorithm that built the digital world

The DFT as written has a fatal flaw for real signals: it is _slow_. Look again at the formula. To get each of the $N$ outputs you sum over all $N$ inputs, so the total work is $N times N = N^2$ multiply-and-adds. For a one-second snippet of CD audio, $N = 44{,}100$, and $N^2 approx 1.9$ billion operations — for one second of sound. For an image or a video, multiply that by the number of blocks, the number of frames. At $N^2$, the frequency domain would be a beautiful idea no machine could afford.

#gomaths("Why $N^2$ versus $N log N$ is the whole ballgame")[
We met *Big-O* growth in Chapter 14. The difference between an algorithm that costs $N^2$ and one that costs $N log_2 N$ is not a tweak; it is the difference between possible and impossible. At $N = 1{,}000{,}000$ samples:
$ N^2 = 10^12 quad "versus" quad N log_2 N approx 10^6 times 20 = 2 times 10^7. $
That is a factor of *fifty thousand*. A computation that would take a full day at $N^2$ finishes in under two seconds at $N log N$. The frequency domain became usable not when the DFT was understood — that was a century old — but the day someone found a way to compute it in $N log N$.
]

That someone, in the public record, was *James Cooley* of IBM and *John Tukey* of Princeton, who in 1965 published _An Algorithm for the Machine Calculation of Complex Fourier Series_. Their *Fast Fourier Transform* (FFT) computes the _exact same_ DFT — same outputs, to the last bit — but in $O(N log N)$ operations instead of $O(N^2)$. The trick is *divide and conquer* (Chapter 14): split the $N$-point DFT into two $N\/2$-point DFTs — one over the even-indexed samples, one over the odd-indexed — and stitch their results together with a single layer of cheap combinations. Each half splits again, and again, $log_2 N$ times down to trivial one-point transforms; at each level the stitching costs only $O(N)$, so the total is $O(N log N)$.

#algo(
  name: "Fast Fourier Transform (FFT)",
  year: "1965",
  authors: "James W. Cooley, John W. Tukey (rediscovering Gauss, c. 1805)",
  aim: "Compute the Discrete Fourier Transform of N samples exactly, but in O(N log N) operations instead of the naive O(N²).",
  complexity: "O(N log N) time; works most simply when N is a power of two (radix-2), with variants (mixed-radix, Bluestein) for any N.",
  strengths: "Exact, not approximate; a ~50,000× speed-up at a million points; the workhorse of audio, image, video, radar, telecoms, and scientific computing.",
  weaknesses: "Classic radix-2 form wants N a power of two; recursive memory traffic; numerically a touch noisier than the direct sum (negligible in practice).",
  superseded: "Refined, never replaced — FFTW (1998) auto-tunes the best decomposition for each machine and size; the underlying idea is unchanged.",
)[
Cooley and Tukey did not invent the idea so much as rediscover it: *Carl Friedrich Gauss* had used essentially the same doubling trick around 1805 to interpolate asteroid orbits, two years before Fourier's own work, but left it unpublished in a notebook. Tukey reportedly hit on the method while serving on a presidential science advisory committee, seeking a way to detect Soviet nuclear tests from seismic data. _IEEE Computing in Science & Engineering_ later named the FFT one of the *ten most important algorithms of the 20th century*. Without it there is no JPEG, no MP3, no digital video, no Wi-Fi.
]

Let us see the split happen once, concretely, so "divide and conquer" stops being a slogan. The DFT output $X_k = sum_(n=0)^(N-1) x_n e^(-i 2 pi k n \/ N)$ can be torn into its even-indexed and odd-indexed input samples:
$ X_k = underbracket(sum_(m=0)^(N\/2 - 1) x_(2m) e^(-i 2 pi k m \/ (N\/2)), E_k\, "DFT of the evens") + e^(-i 2 pi k \/ N) underbracket(sum_(m=0)^(N\/2 - 1) x_(2m+1) e^(-i 2 pi k m \/ (N\/2)), O_k\, "DFT of the odds"). $
The two inner sums are themselves DFTs of half the size — $E_k$ over the even samples, $O_k$ over the odd samples — and the extra factor $e^(-i 2 pi k \/ N)$ that multiplies $O_k$ is called a *twiddle factor*. The magic is that the half-size transforms only need to be computed for $k = 0, dots, N\/2 - 1$, because each pair of full outputs reuses them:
$ X_k = E_k + w^k O_k quad "and" quad X_(k + N\/2) = E_k - w^k O_k, quad w = e^(-i 2 pi \/ N). $
This pair — two outputs from one shared multiplication — is the famous *butterfly*. You compute $E_k$ and $O_k$ once, do a single multiply $w^k O_k$, then get _two_ final answers by one addition and one subtraction. Recurse on each half $log_2 N$ times and the $N^2$ collapses to $N log N$. That single algebraic regrouping — "evens here, odds there, share the work" — is the whole FFT.

We will not code the full FFT here — Chapter 38 builds its close relative, the *Discrete Cosine Transform*, which is the form compression actually uses — but you should know that every numerical library ships a battle-tested FFT (`numpy.fft.fft`, for instance), and that whenever this book says "take the spectrum," an FFT is what runs under the hood.

#history[
The deepest irony of the FFT is that it kept being discovered and forgotten. Gauss had it in 1805. Carl Runge and others published doubling schemes around 1903–1924. Gordon Danielson and Cornelius Lanczos rediscovered a version in 1942 for X-ray crystallography. None of it stuck, because before electronic computers there was little reason to compute huge DFTs. Cooley and Tukey's 1965 paper landed at the exact moment the digital computer made the speed-up worth a fortune, and this time the idea caught fire and never went out. It is a clean lesson: an algorithm's impact depends not only on its cleverness but on whether the world is ready to spend it.
]

== The time–frequency view: where things happen, and at what pitch

The DFT gives a glorious answer to "what frequencies are in this signal?" — but it throws away an equally important question: "_when_ does each frequency happen?" Take the whole DFT of a three-minute song and you learn the overall mix of pitches, but you lose all sense of melody: the spectrum of "the whole song" cannot tell the opening note from the closing chord. For music, speech, and video — signals whose frequency content _changes over time_ — we need both axes at once: time _and_ frequency.

The fix is simple and is the workhorse of real audio codecs. Instead of one giant DFT over the whole signal, chop the signal into short, overlapping *frames* — say $20$ milliseconds each — and take a small DFT of each frame. Each frame's spectrum is a snapshot: "here is the frequency mix _during this slice of time_." Lay the snapshots side by side, time running left to right and frequency running bottom to top, and shade each cell by how much energy that frequency had in that frame. The result is a *spectrogram* — a picture of the signal's frequency content evolving through time. This frame-by-frame transform has a name, the *Short-Time Fourier Transform* (STFT), and it is the analysis stage of essentially every perceptual audio codec in Volume III.

#fig([A spectrogram: time on the horizontal axis, frequency on the vertical, darkness showing energy. Two rising tones (the diagonal bands) and a steady hum (the flat band) become visible at once — _when_ and _at what pitch_, together.], cetz.canvas({
  import cetz.draw: *
  // frame and axes
  line((0, 0), (7.4, 0), mark: (end: ">"))
  line((0, 0), (0, 3.2), mark: (end: ">"))
  content((7.5, -0.3))[time]
  content((-0.55, 3.1))[freq]
  // steady hum: flat band low
  rect((0.1, 0.45), (7.0, 0.7), fill: rgb("#0b5394").lighten(20%), stroke: none)
  // rising tone 1: blocks marching up-right
  for j in range(0, 11) {
    let x = 0.3 + j*0.6
    let y = 0.9 + j*0.18
    rect((x, y), (x + 0.45, y + 0.22), fill: rgb("#0b5394").darken(5%), stroke: none)
  }
  // rising tone 2, steeper, fainter
  for j in range(0, 8) {
    let x = 1.6 + j*0.62
    let y = 0.7 + j*0.31
    rect((x, y), (x + 0.4, y + 0.2), fill: rgb("#783f04").lighten(15%), stroke: none)
  }
}))

This frame-by-frame view exposes a deep, unavoidable trade-off, and it is one you should carry forward into the audio chapters.

#gomaths("The time–frequency uncertainty trade-off")[
You cannot have sharp time resolution _and_ sharp frequency resolution at once. A short frame pins down _when_ something happened (good time resolution) but, having few samples, can only crudely tell _which_ frequency (poor frequency resolution). A long frame measures frequency finely but smears the timing across its whole length. The product of the two uncertainties is bounded below — a signal-processing cousin of Heisenberg's uncertainty principle in physics. Concretely, a frame of $N$ samples at rate $f_s$ lasts $N\/f_s$ seconds and resolves frequency to within $f_s\/N$ hertz; shrinking one necessarily grows the other, since their product is $1$. Codec designers choose the frame length to suit the signal, even switching _adaptively_: short frames during sharp drum hits (to keep the timing crisp and avoid "pre-echo"), long frames during sustained tones (to resolve pitch finely). The MP3 and AAC encoders of Chapter 47 literally flip between block sizes for exactly this reason.
]

== From the frequency domain to compression

Why have we spent a whole chapter on signals and Fourier when the book is about compression? Because the frequency domain is where lossy compression _lives_, and the reason is one phrase we met back in Chapter 21: *energy compaction*. Real signals — natural sounds, photographs, video frames — are not random. Their energy is wildly _lopsided_ across frequencies. A photograph is mostly smooth regions (sky, skin, walls) with sharp detail only at edges, so its spectrum is dominated by a few low frequencies, with the high frequencies near zero. A musical note is a fundamental plus a handful of harmonics, a few tall spikes in a sea of silence. When you look at a real signal's spectrum, it is _mostly empty_.

That emptiness is the gift. In the _time_ domain, every sample looks roughly as important as every other, and quantizing them all coarsely wrecks the signal evenly. In the _frequency_ domain, a few coefficients hold almost all the energy and the rest are nearly zero — so you can spend your precious bits on the few that matter and round the many near-zero coefficients straight down to nothing, almost for free. Discard the inaudible high tones, the invisible fine textures; keep the dominant low frequencies the eye and ear actually use. That is the entire strategy of JPEG, MP3, and every transform codec ahead.

#keyidea[
The frequency domain is useful for compression because real signals are *energy-compacted* there: a few low-frequency coefficients carry almost all the energy, and the rest are nearly zero. Quantizing the near-zero coefficients to zero costs almost no quality but saves enormous numbers of bits. _Transform first, then quantize, then entropy-code_ — the pipeline of Chapter 21 — works because the transform moves the signal into a domain where what to throw away is obvious.
]

There is a precise reason this is _safe_ — why discarding small coefficients does only small damage. It is *Parseval's theorem*, and it is the mathematical license behind the entire transform-coding industry.

#theorem("Parseval's theorem (energy is conserved by the DFT)")[
The total energy of a signal equals the total energy of its spectrum (up to the bookkeeping factor $N$):
$ sum_(n=0)^(N-1) abs(x_n)^2 = 1/N sum_(k=0)^(N-1) abs(X_k)^2. $
]

#proof[
Write the left side as $sum_n x_n overline(x_n)$, where $overline(x_n)$ is the complex conjugate, and replace each $x_n$ using the inverse DFT $x_n = (1\/N) sum_k X_k e^(i 2 pi k n \/ N)$ and likewise $overline(x_n) = (1\/N) sum_m overline(X_m) e^(-i 2 pi m n \/ N)$:
$ sum_(n=0)^(N-1) x_n overline(x_n) = 1/N^2 sum_(k) sum_(m) X_k overline(X_m) underbracket(sum_(n=0)^(N-1) e^(i 2 pi (k - m) n \/ N), = N "iff" k = m). $
By the orthogonality relation just proved, the inner sum is $N$ when $k = m$ and $0$ otherwise, collapsing the double sum to a single one:
$ = 1/N^2 sum_(k=0)^(N-1) X_k overline(X_k) dot N = 1/N sum_(k=0)^(N-1) abs(X_k)^2. $
That is exactly the claim.
]

Read Parseval as an accounting identity: *the error you commit equals the energy of the coefficients you discard.* If you zero out a coefficient whose energy $abs(X_k)^2$ is one-thousandth of the total, you have changed the reconstructed signal by an amount whose energy is one-thousandth of the total — a tiny, often imperceptible distortion. This is the quantitative promise behind energy compaction: because real signals pile their energy into a few coefficients, throwing the rest away costs provably little distortion while saving enormous numbers of bits. Parseval is the bridge from "the spectrum is mostly empty" to "therefore we may compress," and it is the reason the rate–distortion curve $R(D)$ of Chapter 21 can be approached at all by transform coding.

Three more reasons the frequency domain is the right stage for lossy coding tie the whole arc together. First, *decorrelation*: neighbouring samples in time are highly correlated (one pixel predicts the next), which wastes bits; the Fourier coefficients are nearly _uncorrelated_, so each can be coded independently — the very property Chapter 21 named, and which the next chapter's transforms achieve. Second, *perceptual selectivity*: human hearing and vision are organised by frequency (Chapter 46's critical bands, Chapter 42's contrast sensitivity), so the frequency axis is exactly where "what people notice" is easiest to express — you can be coarse in the bands the senses ignore. Third, the *sampling theorem itself* tells us the highest frequency worth keeping ($f_s\/2$); everything above is either inaudible or was filtered away, so the spectrum has a natural, finite top edge to budget bits across.

#aside[
There is a small but important caveat the next chapter resolves. The plain DFT assumes the signal _repeats_ forever, which it does not; chopping a long signal into blocks and DFT-ing each block creates artificial jumps at the block edges that smear energy across all frequencies (called *spectral leakage*) and cause audible or visible *blocking artifacts*. The fixes — tapering each block with a *window*, and the overlapping *Modified DCT* (MDCT) that cancels the seams exactly — are the subject of Chapter 38 and the audio chapters. For now, just know that "transform each block" hides a real wrinkle, and that clever windowing irons it out.
]

Let us close the loop with a tiny demonstration of energy compaction in code, so the central claim is not just a promise.

#gopython("Reading a spectrum and measuring compaction")[
We reuse our `dft` from before. We build a smooth, slowly varying signal — exactly the kind real data resembles — take its spectrum, and ask: how much of the total energy sits in just the few lowest frequencies? *Energy* of a coefficient is its squared magnitude, `abs(c)**2` (Chapter 12's squared length). `sorted(..., reverse=True)` orders the energies from largest to smallest.
```python
import math

N = 64
# a smooth signal: a low-frequency wave plus a gentle trend (like a sky gradient)
signal = [math.sin(2*math.pi*2*n/N) + 0.4*n/N for n in range(N)]

spectrum = dft(signal)               # reuse dft() from the box above
energy = [abs(c)**2 for c in spectrum]
total = sum(energy)

biggest = sorted(energy, reverse=True)
top4 = sum(biggest[:4]) / total
print(f"top 4 of {N} coefficients hold {top4:.1%} of the energy")
# -> top 4 of 64 coefficients hold 99.x% of the energy
```
A handful of coefficients out of $64$ carry essentially all the energy; the other sixty are near-zero and can be quantized away almost for free. That single sentence is the financial model of every transform codec in this book.
]

#scoreboard(caption: "where the frequency domain enters the pipeline (preview)",
  [Raw samples (time domain)], [100%], [1.00×], [every sample equally costly; no obvious redundancy to attack],
  [After transform (frequency)], [100%], [1.00×], [_lossless_ rotation; energy now compacted into a few coefficients],
  [After quantizing small coefficients], [≈10–20%], [5–10×], [the lossy step — the subject of Ch 38–42; bytes finally melt],
)

The scoreboard above is a _preview_, not a measurement: this chapter adds no codec to `tinyzip` and melts no bytes yet. It marks where, in the chapters just ahead, the savings will come from. The transform itself is free of loss; it merely sets the table. In the next chapter we build the specific transform compression actually uses — the Discrete Cosine Transform — and add `transform.py` to `tinyzip`. Then quantization (Chapter 39) and JPEG (Chapter 42) finally turn this rearrangement into shrinking files.

#takeaways((
  [A *signal* is a value that varies with time or space. *Sampling* discretises time; *quantization* (Chapter 39) discretises value. Sampling can be lossless; quantization is where loss is born.],
  [Any signal is a sum of *sine waves*, each with an amplitude, a frequency, and a phase (Fourier). The list of "how much of each frequency" is the signal's *spectrum* — its frequency-domain view.],
  [The *Nyquist–Shannon theorem*: a signal band-limited to $B$ Hz is perfectly captured by samples taken faster than $2B$ per second. Below that rate, high frequencies *alias* into false low ones — irreversibly.],
  [The *anti-aliasing filter* removes frequencies above $f_s\/2$ before sampling; the *Nyquist frequency* $f_s\/2$ is the highest frequency you can honestly record.],
  [The *DFT* turns $N$ time samples into $N$ frequency coefficients via a dot product against pure waves; it is a lossless, invertible change of coordinates.],
  [The *FFT* computes the DFT exactly in $O(N log N)$ instead of $O(N^2)$ — a ~50,000× speed-up at a million points — and that single algorithm made all digital media practical.],
  [Compression lives in the frequency domain because real signals are *energy-compacted* there: a few coefficients hold almost all the energy, so the rest can be quantized to nothing almost for free.],
))

== Exercises

#exercise("37.1", 1)[
A telephone line is engineered to carry frequencies up to about $3{,}400$ Hz. What is the minimum sampling rate (the Nyquist rate) that captures it without aliasing? (The actual digital telephone standard samples at $8{,}000$ Hz — explain in one sentence why a margin above the bare minimum is sensible.)
]
#solution("37.1")[
The Nyquist rate is twice the bandwidth: $2 times 3{,}400 = 6{,}800$ samples per second. Sampling at $8{,}000$ Hz leaves about $600$ Hz of headroom above $2B$, giving the anti-aliasing low-pass filter a gentle "transition band" to roll off in (a perfectly sharp filter is impossible to build), so any residual energy near $3{,}400$ Hz is safely attenuated before it can fold down and alias.
]

#exercise("37.2", 1)[
A pure tone of $9{,}000$ Hz is sampled at $f_s = 8{,}000$ Hz with no anti-aliasing filter. At what frequency does it appear in the samples? Show the folding arithmetic.
]
#solution("37.2")[
Use the folding formula. The nearest multiple of $f_s = 8{,}000$ to $9{,}000$ is $8{,}000$, so $f_"alias" = abs(9{,}000 - 8{,}000) = 1{,}000$ Hz. The $9$ kHz tone masquerades as a $1$ kHz tone — well inside the band $0$ to $4{,}000$ Hz — and no later processing can recover the truth. This is precisely why the filter must come first.
]

#exercise("37.3", 2)[
Compute the full DFT of the $4$-sample signal $x = (1, 1, 1, 1)$ by hand. Interpret the result: which frequencies are present?
]
#solution("37.3")[
$X_0 = 1+1+1+1 = 4$. For $X_1$: $1 dot 1 + 1 dot(-i) + 1 dot(-1) + 1 dot(i) = (1-1) + (-i + i) = 0$. By the same cancellation, $X_2 = 1 - 1 + 1 - 1 = 0$ and $X_3 = 0$. The spectrum is $(4, 0, 0, 0)$: _all_ the energy is at frequency $0$. That is correct — a constant signal has no oscillation at all, only a DC (zero-frequency) level, here equal to $N$ times the average value $1$.
]

#exercise("37.4", 2)[
Explain, in your own words and without formulas, why you need _at least two_ samples per cycle of the highest frequency, and why _one_ sample per cycle is provably useless. Use the spinning-wheel picture of a sine wave.
]
#solution("37.4")[
A sine wave is the height of a point on a spinning wheel. If you sample exactly once per full turn, you always catch the point at the same place on the circle, so every sample reads the same height — a flat line — and you cannot even tell the wheel is turning, let alone how big it is. To detect oscillation you must catch the point on the way _up_ and on the way _down_ within a single turn, which means at least two looks per cycle. Two samples per cycle is the bare minimum that records "there is a wiggle here, this fast," and the sampling theorem proves it is also sufficient.
]

#exercise("37.5", 2)[
A CD samples at $44.1$ kHz. (a) What is its Nyquist frequency? (b) Roughly why was $44.1$ kHz chosen rather than, say, $40$ kHz, given that human hearing tops out near $20$ kHz?
]
#solution("37.5")[
(a) The Nyquist frequency is $f_s\/2 = 22.05$ kHz — the highest frequency a CD can represent. (b) Human hearing reaches about $20$ kHz, so the bare Nyquist rate would be $40$ kHz; the extra $4.1$ kHz of margin gives the anti-aliasing filter a transition band between $20$ and $22.05$ kHz in which to fall from "pass" to "stop," since no real filter cuts off instantly. (Historically the exact figure $44.1$ kHz also came from fitting digital audio onto video-tape recorders used as early storage, which constrained the rate to convenient line and frame counts.)
]

#exercise("37.6", 2)[
Argue, without running code, why a signal that varies _slowly_ (few, low frequencies) compresses far better in the frequency domain than a signal of pure random noise. What does the spectrum of random noise look like?
]
#solution("37.6")[
A slowly varying signal is dominated by a few low-frequency sinusoids, so its spectrum is a few tall spikes and a vast number of near-zero coefficients — extreme energy compaction, perfect for quantizing the small coefficients to zero. Random noise, by contrast, has _no_ structure to compact: its energy is spread roughly evenly across _all_ frequencies (a "flat" or "white" spectrum), so every coefficient is comparably important, none can be discarded without losing energy, and the transform buys you nothing. This is the frequency-domain face of the counting argument from Chapter 8: truly random data is incompressible, in any domain.
]

#exercise("37.7", 3)[
The proof of the sampling theorem rested on the claim that "multiplying by a comb of spikes in time copies-and-shifts the spectrum in frequency." Without doing the full Fourier analysis, give an intuitive argument for why _sampling_ (which keeps the signal only at evenly spaced instants) should produce _periodic repetition_ in the frequency domain. Hint: think about what a regularly spaced pattern looks like in terms of frequencies.
]
#solution("37.7")[
A comb of evenly spaced spikes is itself a perfectly _periodic_ pattern in time, with spacing $T$. By Fourier, a periodic pattern is built from a discrete set of harmonics — frequencies that are integer multiples of $1\/T = f_s$. So the comb's own "frequency content" is itself another comb, this time in the frequency domain, with teeth at $0, f_s, 2 f_s, dots$ A foundational rule of Fourier analysis is that _multiplying_ two signals in time corresponds to _smearing_ (convolving) their spectra in frequency; smearing a spectrum against a comb of teeth at multiples of $f_s$ stamps a shifted copy of that spectrum at each tooth. Hence sampling — multiplying by the time comb — produces the spectrum repeated at every multiple of $f_s$, which is exactly the copies that must not overlap. The "no overlap" condition is $f_s > 2B$.
]

#exercise("37.8", 3)[
Modify the chapter's `dft` function to also return the *dominant frequency* — the index $k$ (in the range $1$ to $N\/2$) whose coefficient has the largest magnitude. Then describe how you would use this to build a crude pitch detector for a recorded musical note.
]
#solution("37.8")[
```python
import cmath, math

def dft(x: list[complex]) -> list[complex]:
    N = len(x)
    return [sum(x[n] * cmath.exp(-2j*math.pi*k*n/N) for n in range(N))
            for k in range(N)]

def dominant_freq(x: list[complex]) -> int:
    spec = dft(x)
    half = len(x) // 2                     # only first half is independent
    mags = [abs(spec[k]) for k in range(1, half)]   # skip k=0 (the DC term)
    return 1 + max(range(len(mags)), key=lambda i: mags[i])
```
To detect a note's pitch: record $N$ samples at a known rate $f_s$, run `dominant_freq`, and convert the winning index $k$ to hertz via $f = k dot f_s \/ N$ (each DFT bin spans $f_s\/N$ Hz). We skip $k = 0$ because that is the DC level, not a pitch. The result is the strongest frequency present, which for a clean musical tone is its fundamental — its pitch. (Real pitch detectors add windowing to reduce leakage and inspect harmonic patterns to avoid octave errors, but this captures the core idea.)
]

== Further reading

- C. E. Shannon (1949), _Communication in the Presence of Noise_, Proceedings of the IRE 37(1), 10–21 — the clean statement and proof of the sampling theorem, by the founder of the field; #link("https://ieeexplore.ieee.org/document/1697831")[IEEE].
- H. Nyquist (1928), _Certain Topics in Telegraph Transmission Theory_, Transactions of the AIEE 47, 617–644 — the $2B$ pulses-per-second result that gave the rate its name.
- J. W. Cooley and J. W. Tukey (1965), _An Algorithm for the Machine Calculation of Complex Fourier Series_, Mathematics of Computation 19, 297–301 — the paper that made the frequency domain affordable; #link("https://www.ams.org/journals/mcom/1965-19-090/S0025-5718-1965-0178586-1/")[AMS].
- M. T. Heideman, D. H. Johnson, C. S. Burrus (1984), _Gauss and the History of the Fast Fourier Transform_, IEEE ASSP Magazine 1(4), 14–21 — the surprising tale of an algorithm discovered and forgotten for 160 years.
- E. O. Brigham, _The Fast Fourier Transform and Its Applications_ (Prentice Hall, 1988) — a friendly, picture-rich book-length treatment of everything in this chapter.
- A. V. Oppenheim and R. W. Schafer, _Discrete-Time Signal Processing_ (Prentice Hall, 3rd ed., 2009) — the standard graduate text; rigorous coverage of sampling, the DFT, and the FFT.

#bridge[
We now know that a signal is a recipe of frequencies, that a finite list of samples can hold it losslessly, and that the FFT can read off that recipe cheaply. But the plain DFT has two flaws for compression: it produces _complex_ numbers (awkward for real images), and chopping signals into blocks creates ugly seams. In the next chapter we meet the transform that fixes both and that compression actually uses — the *Discrete Cosine Transform (DCT)* — together with its ideal cousin the *Karhunen–Loève Transform*, multiresolution *wavelets*, and the seam-cancelling *MDCT*. We will prove why the DCT is the practical champion of energy compaction, code an $8 times 8$ DCT into `tinyzip`, and so build the engine at the heart of JPEG, MP3, and every video codec that follows.
]
