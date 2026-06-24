#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Dead Ends, Failures, and Cautionary Tales

#epigraph[
  "For every complex problem there is an answer that is clear, simple, and wrong."
][H. L. Mencken, _A Mencken Chrestomathy_, 1949]

Here is a puzzle to open this chapter.

Imagine a salesman knocks on your door and says he has invented a machine that
can take _any_ file on your hard drive and make it smaller, guaranteed, every
single time. Compress a text file: smaller. Compress a music file: smaller.
Compress a random scramble of noise: smaller. And then compress the already-
compressed output: smaller still. Run it enough times and you could store your
entire photo library in a file the size of a single letter of the alphabet.

You should feel a little thrill of "wait, that's too good." Because it is
impossible. Not just hard. Not just "nobody has managed it yet." Mathematically,
provably, forever impossible. In Chapter 19 we saw the source coding theorem;
here we will sharpen that into the counting argument that kills infinite-
compression promises on contact.

But before we get to impossibility proofs, we need to talk about failure in a
broader sense. The history of data compression is not just a heroic march of
ingenious inventions. It is also littered with cautionary markers: ideas that
seemed brilliant but hit an invisible wall, formats that were technically
superior but still lost to the market, and attacks on the infrastructure we all
rely on that came from directions nobody expected. Every story here teaches
something different: the gap between theory and practice, the politics of
ecosystems, the unexpected fragility of software, and what happens when someone
claims to break the laws of mathematics.

These lessons are not mere history trivia. Engineers who do not know them will
reinvent the same mistakes. As you read compression benchmarks, vendor
whitepapers, and breathless news headlines, these patterns will save you hours.

#recap[
  In *Chapter 18* we met Shannon's entropy, and in *Chapter 19* the source
  coding theorem made it precise (the theoretical floor below which no lossless
  compressor can go). In *Chapter 22*
  we studied Kolmogorov complexity and the impossibility of a universal
  compressor that beats the entropy of every input. In *Chapter 43* we followed
  the technical story of JPEG 2000 and wavelets in depth; here we examine _why_
  a technically superior format can still fail commercially. In *Chapter 77* we
  explored patents and standards politics that often determine winners and losers
  independent of technical merit. This chapter draws together those threads and
  looks honestly at the wreckage: what did not work, why, and what the wreckage
  teaches.
]

#objectives((
  "State and prove the counting argument that makes universal lossless compression impossible.",
  "Explain what fractal compression promised, how it works at a high level, and why it never displaced JPEG.",
  "Explain why JPEG 2000 was technically superior but failed to win the web, and where it succeeded.",
  "Describe the xz backdoor (CVE-2024-3094), how it was planted, how it was found, and what it teaches about open-source trust.",
  "Recognize the patterns of compression fraud and apply the counting argument to debunk impossible claims.",
  "Name several historical compression scams and explain exactly which law of mathematics they violated.",
))

== The Counting Argument: Why Infinite Compression Is Impossible

We begin with the most important lesson in this chapter, because it is the
atomic weapon that vaporises an entire class of false claims.

=== The Setup

Suppose someone sells you a lossless compressor. They insist it can compress
_any_ input by at least one bit. Let us call that claim *Claim C.*

#gomaths("The Pigeonhole Principle")[
  Here is a counting idea so simple it almost feels like cheating.

  Imagine you have ten pigeons and only nine boxes. You must put every pigeon
  into some box. Can every box contain at most one pigeon? No, there are not
  enough boxes. At least one box must hold two or more pigeons.

  More generally: if you have *N* objects and only *M* boxes, and $N > M$, then
  at least one box holds more than one object.

  This principle (_more objects than containers forces a collision_) is all we
  need to kill infinite-compression claims.
]

Now apply it to files. Think of all possible files that are exactly $n$ bits
long. There are exactly $2^n$ of them, because each bit can be 0 or 1, and
there are $n$ bits. For example:

- Files of length 3 bits: 000, 001, 010, 011, 100, 101, 110, 111, that is
  $2^3 = 8$ files.

If Claim C is true, our compressor turns every $n$-bit file into a file of at
most $n - 1$ bits. How many files of length at most $n-1$ bits are there? Let
us count:

$
"(length 0)" + "  (length 1)" + dots + "(length n-1)"
$
$
= 1 + 2 + 4 + dots + 2^(n-1) = 2^n - 1.
$

So: we have $2^n$ different input files, and only $2^n - 1$ possible output
files. We are trying to park $2^n$ pigeons in $2^n - 1$ boxes. At least two
different inputs must produce the _same_ compressed output. But then the
decompressor, given that output, does not know which input to restore.
_Lossless_ decompression is broken.

#theorem("No Universal Lossless Compressor")[
  No lossless compression algorithm can compress every possible input file.
  More precisely: for any lossless compressor, there exists at least one input
  that the compressor cannot make shorter (and in fact must make longer or keep
  the same length).
]

This is not a result about current hardware, current cleverness, or current
algorithms. It is a result about _counting_. The pigeonhole argument holds for
every compressor, in every programming language, on every computer, until the
end of time.

#keyidea[
  The correct claim for any real lossless compressor is not "I can compress
  everything" but rather "I can compress _likely_ inputs." A file drawn from
  natural language, source code, or sensor measurements has far lower entropy
  than a random file of the same length. Compressors exploit that structure.
  Present them with truly random data (like an already-encrypted file) and they
  will not compress it; they will often make it slightly larger.
]

=== Worked Example: Running the Numbers

Let us make this very concrete. Consider all 8-bit files (one byte). There are
$2^8 = 256$ of them. A compressor that always outputs something shorter than
the input must output files of at most 7 bits. There are only $2^7 - 1 = 127$
such outputs. Our compressor must map 256 distinct inputs into at most 127
distinct outputs, so at minimum two inputs per output bucket on average. It is
literally impossible to do this without collisions.

Now scale up. Consider all files of up to one megabyte ($8{,}388{,}608$ bits).
There are $2^(8{,}388{,}608)$ such files. A compressor that makes every one
shorter by even one bit must produce files of at most $8{,}388{,}607$ bits,
giving $2^(8{,}388{,}607)$ possible outputs, exactly half the number of inputs.
Half of all files must collide. Half of all lossless compressed files are, by
mathematical necessity, longer than their input when passed through any
"compress everything" algorithm.

#checkpoint[
  A company claims its algorithm can compress any 1 MB file to at most 512 KB,
  losslessly. Is this claim consistent with information theory?
][
  No. By the counting argument, at least $2^(4{,}194{,}304)$ different 1 MB files
  would need to map to the same 512 KB output, making lossless decompression
  impossible for those files. The claim violates the pigeonhole principle.
]

=== A Gallery of Infinite-Compression Scams

The counting argument is not merely academic. It has been needed, repeatedly,
in real disputes. Here is a brief gallery of cases where someone claimed to
break it, and the argument showed them the door.

#history[
  *WEB Technologies, 1992.* A company in Smyrna, Georgia, claimed its program
  `DataFiles/16` could compress "almost any amount of data to less than 1,024
  bytes." BYTE magazine investigated in its June 1992 issue. Independent
  testing showed the program produced output files that were _larger_ than their
  inputs, or simply corrupt. The program exploited the novelty of the claim to
  extract money from hopeful buyers; the counting argument would have dismissed
  it in seconds.

  *ZeoSync, 2002.* A company announced it had achieved 100:1 lossless
  compression of random data, explicitly claiming to have surpassed Shannon's
  theoretical limits. Cryptographer Bruce Schneier noted at the time: "The odds
  on a compression claim turning out to be true are always identical to the
  compression ratio claimed." ZeoSync never provided a demonstration that held
  up under scrutiny. Its website vanished a few months after the announcement.

  *Jan Sloot's Digital Coding System, 1999.* Perhaps the most dramatic case.
  Romke Jan Bernhard Sloot, a Dutch electronics technician, claimed in 1999 to
  have compressed a full feature-length film into a file of just 8 kilobytes.
  (Shannon's source coding theorem tells us a movie contains far more than $8
  times 8 = 64{,}000$ bits of information, so the claim required something
  genuinely impossible.) Investors were enthusiastic. Sloot gave a live
  demonstration. Then, on July 11, 1999, two days before he was to hand over
  the source code to a notary, he died suddenly of a heart attack. The source
  code was never found. Whether Sloot was a genuine eccentric who built
  something nobody understood, or a fraud who was staging an exit, is a mystery.
  The mathematics, however, leaves no room for the system to work as described.
]

#pitfall[
  The tell-tale signs of a compression scam are always the same: (1) no
  independent demonstration; (2) "any file" or "all data" claims; (3) ratios
  that would require compressing entropy that, by Shannon's theorem, does not
  exist; (4) appeals to proprietary secret techniques that "cannot be revealed."
  The counting argument demolishes all of these without needing to inspect a
  single line of code.
]

#gopython("Proving impossibility with code")[
  You can actually demonstrate the counting argument on a toy case in Python.
  The snippet below counts, over all 2-bit strings, how many a hypothetical
  "always-compress-by-1-bit" function could handle:

  ```python
  # There are 2**n possible inputs of exactly n bits.
  # A compressor that always shrinks by >=1 bit must
  # output files of at most n-1 bits.
  # At most 2**(n-1) - 1 distinct outputs exist.

  def count_argument(n: int) -> None:
      inputs   = 2 ** n
      outputs  = 2 ** (n - 1) - 1  # files strictly shorter than n bits
      shortfall = inputs - outputs
      print(f"n={n}: {inputs} inputs, {outputs} possible outputs")
      print(f"  → at least {shortfall} inputs must collide (lossless broken)")

  for n in range(2, 10):
      count_argument(n)
  ```

  Running this prints, for example:
  ```
  n=2: 4 inputs, 1 possible outputs  → at least 3 inputs must collide
  n=8: 256 inputs, 127 possible outputs → at least 129 inputs must collide
  n=20: 1048576 inputs, 524287 possible outputs → at least 524289 must collide
  ```

  Every row confirms: more than half of all $n$-bit files cannot be losslessly
  compressed. Any claim to the contrary is wrong, regardless of the algorithm.
]

== Fractal Compression: A Brilliant Idea That Hit a Wall

=== The Promise

In the 1980s, mathematician Michael Barnsley was doing extraordinary things with
fractals. He had shown that many complicated, beautiful shapes (fern leaves,
coastlines, mountain silhouettes) could be described by very short lists of
simple geometric rules. His book _Fractals Everywhere_ (1988) captured the
imagination of a generation of computer scientists, and with good reason: if a
picture of a fern could be stored as five rules instead of a million pixels,
compression ratios of thousands-to-one seemed within reach.

The idea crystallised into _fractal image compression_ in the late 1980s and
early 1990s. Barnsley, working at Georgia Tech and then at his company Iterated
Systems Inc. (co-founded with Alan Sloan in 1987), held patents on the core
approach. His graduate student Arnaud Jacquin published the first fully
automated fractal compression algorithm in 1992, making the technique viable
without human intervention.

At the time, the claims were heady. Barnsley suggested that natural images could
be compressed to a few hundred bytes using the self-similarity buried in their
structure. In an era when a full-color photograph required hundreds of kilobytes
on a floppy disk, that sounded like magic.

=== How Fractal Compression Actually Works

The key insight is _self-similarity at multiple scales_. Natural images often
contain regions that look like scaled, rotated, or colour-shifted versions of
other regions in the same image. Fractal compression tries to find and exploit
these relationships.

#definition("Iterated Function System (IFS)")[
  An *iterated function system* is a finite collection of _contractive
  transformations_: functions that shrink and move regions of an image. When
  applied repeatedly, an IFS converges to a unique fixed point called the
  *attractor*. For images, the attractor is the compressed image itself.
]

#gomaths("Contractions and fixed points")[
  A transformation is *contractive* if it always pulls any two points closer
  together. Concretely, if applying the map $f$ to two inputs $x$ and $y$ shrinks
  the gap between them (say, it at most halves it every time), then $f$ is a
  contraction.

  Here is the magic. Pick _any_ starting point and apply $f$ over and over:
  $x, f(x), f(f(x)), dots$ Because each step shrinks distances, the points crowd
  ever closer together and home in on one special point $p$ that does not move:
  $f(p) = p$. That unmoving point is the *fixed point*. A simple numeric example:
  let $f(x) = x\/2 + 3$. Starting from $x = 0$ we get $0, 3, 4.5, 5.25, dots$,
  marching toward $p = 6$ (and indeed $6\/2 + 3 = 6$). Start from $x = 100$
  instead and you get $100, 53, 29.5, dots$, still heading to the very same $6$.

  This is the whole trick of fractal _decoding_: the encoder picks transformations
  whose joint fixed point _is the original image_. The decoder can then begin
  from a blank canvas (or any image at all) and simply iterate until the picture
  stops changing, because the contraction guarantees it always lands on the same
  attractor. Mathematicians call this guarantee the _Banach fixed-point
  theorem_; we need only the intuition that shrinking maps have one inevitable
  destination.
]

The compression process works in three stages:

+ *Partition the image into range blocks.* Divide the image into small,
  non-overlapping tiles (say 8×8 pixels each). These are the regions you are
  trying to describe. Each range block is what you want to encode.

+ *For each range block, find a matching domain block.* Search the full image
  for a larger block (say 16×16) that, when scaled down and transformed
  (rotation, reflection, brightness adjustment), resembles the target range
  block as closely as possible.

+ *Store the transformation, not the pixels.* Instead of saving the pixel values
  of the range block, save the compact description: "range block at position
  $(x, y)$ ≈ domain block at position $(p, q)$, scaled and transformed by
  parameters $s, theta, b$" (where $s$ scales the contrast, $theta$ is the
  rotation angle, and $b$ is the brightness offset).

At decompression time, you start with any arbitrary image (even a blank
canvas), apply all the stored transformations repeatedly, and the image converges
to the original, because the transformations were chosen to make the original
the unique fixed point of the IFS.

#fig(
  [Fractal encoding loop: for each small range block, a larger domain block is
   found that, after contraction and colour adjustment, approximates it.
   The stored transformation replaces raw pixel data.],
  cetz.canvas({
    import cetz.draw: *
    // Left: full image with domain block highlighted
    rect((0,0),(4,3), stroke: 0.8pt)
    content((2, 3.3), text(size: 8pt)[Full Image])
    // domain block
    rect((0.5, 1.0),(2.5, 2.5), stroke: (dash: "dashed", paint: blue, thickness: 1.2pt))
    content((1.5, 0.7), text(size: 7.5pt, fill: blue)[Domain block (16×16)])
    // range block (small)
    rect((2.8, 0.2),(3.6, 0.8), stroke: (paint: red, thickness: 1.2pt))
    content((3.2, -0.2), text(size: 7.5pt, fill: red)[Range block (8×8)])
    // arrow
    line((2.5, 1.75),(2.8, 0.5), mark: (end: ">"), stroke: (paint: eastern, thickness: 1.2pt))
    content((3.0, 1.2), text(size: 7.5pt, fill: eastern)[Contract + adjust])
    // Right side: stored data
    rect((5.0, 0.5),(8.5, 2.5), stroke: 0.6pt, fill: luma(96%))
    content((6.75, 2.8), box(width: 3.1cm, align(center, text(size: 8pt)[Stored: transformation list])))
    content((6.75, 2.15), box(width: 3.1cm, align(center, text(size: 7.5pt)[(p=12, q=34,])))
    content((6.75, 1.75), box(width: 3.1cm, align(center, text(size: 7.5pt)[s=0.75, θ=90°,])))
    content((6.75, 1.35), box(width: 3.1cm, align(center, text(size: 7.5pt)[brightness=+5])))
    content((6.75, 0.85), box(width: 3.1cm, inset: 2pt, align(center, text(size: 7pt, fill: gray)[one entry per range block])))
  })
)

=== The Problems

Fractal compression turned out to be brilliant in theory and brutal in practice.
Three interlocking problems doomed it as a general-purpose codec.

*The encoding speed wall.* For each range block, the encoder must search the
entire image for the best-matching domain block. On a 512×512 image with
8×8 range blocks and 16×16 domain blocks, that means $64 times 64 = 4096$
range blocks, each requiring a search over $(512 - 16 + 1)^2 ≈ 245{,}000$
domain candidates. Even with pruning heuristics, encoding times were measured
in hours, not seconds. Early practical systems required literally _100 hours_
of encoding time per image on workstation hardware of the day. JPEG encoded the
same image in a second.

*The quality ceiling.* The self-similarity assumption is only approximately
true. When the encoder cannot find a good domain match, it settles for a
mediocre one and the reconstructed image shows blurry "fractal artifacts":
pattern repetitions that look nothing like natural image degradation.

*Patents and secrecy.* Iterated Systems Inc. held numerous patents and was
slow to license. This chilled academic and commercial adoption precisely when
JPEG was being standardised openly and freely.

Decoding was fast (apply the transformations a handful of times and the image
converges), and fractal images showed the attractive property of
_resolution independence_: you could zoom in and the attractor would fill in
detail rather than showing pixels. Barnsley's company sold a product called
*Genuine Fractals* as a photographic zoom tool, and Microsoft used a fractal-
compressed version of Encarta's 1994 edition encyclopaedia images. But none of
this amounted to a displacement of JPEG.

By the late 1990s, the academic community had drawn the curtain: extensive
benchmarks showed that JPEG outperformed fractal compression at equivalent
encoding times, and that even wavelet-based coders (the basis of JPEG 2000)
were superior at high quality. The technique survived in textbooks and
occasional niche applications, but the mainstream passed it by.

#algo(
  name: "Fractal Image Compression (PIFS)",
  year: "1988–1992",
  authors: "Michael Barnsley, Alan Sloan, Arnaud Jacquin (Iterated Systems Inc.)",
  aim: "Encode each image block as a contractive transformation of a larger block elsewhere in the image, exploiting self-similarity.",
  complexity: "Encoding: $O(N^2)$ or worse per image; Decoding: $O(N log 1/epsilon)$ iterations to convergence.",
  strengths: "Resolution-independent reconstruction; elegant mathematical foundation; fast decoding; good subjective quality at very high compression for some images.",
  weaknesses: "Catastrophically slow encoding; blurry artifacts when self-similarity assumption fails; patent-encumbered; outperformed by DCT and wavelet methods at equal encode time.",
  superseded: "JPEG (DCT-based) for practical use; wavelets (JPEG 2000) for quality; modern learned codecs for both.",
)[
  Barnsley's IFS framework was mathematically profound: the _Collage Theorem_
  guarantees that if you can approximate an image with contractive maps, the
  attractor of those maps is close to the original. But finding good maps
  automatically (Jacquin's 1992 contribution) still required brute-force search.
  Research into faster search strategies (genetic algorithms, hierarchical
  matching, neural approximation) never closed the gap with JPEG sufficiently
  to matter commercially. Fractal compression is a cautionary example of
  "theoretically beautiful, practically inconvenient," a pattern that recurs
  throughout the field.
]

#misconception[
  Fractal compression can achieve infinite zoom with perfect detail because
  fractals are infinitely detailed.
][
  The stored IFS is a _model_ chosen to approximate the original image, not the
  image's true mathematical structure. At scales smaller than the range block
  size, the decompressor _invents_ detail by extrapolation from the stored
  self-similarity patterns. This invented detail is plausible-looking but not
  real. It is not what the original camera captured. "Resolution independence"
  is a form of interpolation, not information recovery.
]

=== The Redemption: What Fractal Thinking Actually Gave Us

Fractal compression itself failed, but the ideas it introduced did not disappear.
The notion of exploiting _self-similarity at multiple scales_ reappeared in:

- *Intra-prediction in video codecs.* H.264, HEVC, and AV1 all predict each
  block from neighbouring blocks already encoded in the same frame, a
  descendant of the "find a match elsewhere in the image" idea, made fast and
  practical.
- *Wavelet transforms.* The multi-scale decomposition in JPEG 2000 and modern
  learned codecs captures the same scale-dependent structure that Barnsley was
  after, but with a fixed mathematical basis rather than a data-driven search.
- *Learned image compression.* Modern autoencoders (Chapter 57) implicitly
  learn to model scale-dependent correlations in images, a data-driven IFS, if
  you squint.

Bad ideas often fertilise good ones. The lesson is not to dismiss fractal
compression entirely, but to understand exactly where it broke down and why.

== JPEG 2000: The Technically Superior Standard That Lost

=== A Clean-Sheet Redesign

In the late 1990s, the JPEG committee looked at the problems with JPEG
(blocking artifacts, no lossless mode worth using, no progressive quality
scalability) and set out to build a successor from scratch. The result, *ISO/IEC
15444-1*, was finalised between 2000 and 2001. Technically, it was a stunning
achievement, and Chapter 43 covers the engineering in full. Here we focus on
_why it lost despite being better_.

JPEG 2000 replaced the block DCT with a *Discrete Wavelet Transform (DWT)*
applied to the whole image. Because there are no independent 8×8 blocks, there
are no blocking artifacts. At low bitrates, JPEG 2000 degrades gracefully into
a soft blur; JPEG degrades into chunky tiles. JPEG 2000 supported:

- *True lossless compression* via an integer wavelet (the 5/3 filter).
- *Progressive decoding*: the same bitstream could be truncated at any point and
  still give a valid (if lower quality) image.
- *Arbitrary regions of interest*: encode specific regions at higher quality.
- *High bit depths* (up to 16 bits per channel), critical for medical imaging.

These are not marginal improvements. In every technical dimension that mattered
for high-quality professional work, JPEG 2000 was ahead.

=== Why It Did Not Win

The reasons are a case study in how standards actually succeed or fail.

*Computational cost.* The wavelet transform over a whole image requires far more
memory and CPU than JPEG's independent 8×8 blocks. In 2001, decoding a JPEG
2000 image on typical consumer hardware was noticeably slower than JPEG. For a
standard that needed to be universally fast to succeed on the web, this was a
serious problem. Web browsers could not afford the memory budget.

*Complexity of the standard.* JPEG 2000's flexibility was also a curse. The
standard allowed data to be organised in tiles, layers, resolutions, and
precincts in many combinations. Implementing a correct, fully-compliant decoder
was a large engineering project. Implementers cut corners; interoperability
problems accumulated. JPEG required a few hundred lines of code to decode;
JPEG 2000 required thousands.

*Patent uncertainty.* Part 1 of the standard was nominally royalty-free, but
there were lingering concerns about patents held by various parties in the
broader specification. The spectre of a GIF-style patent crisis (see Chapter 29
for the LZW/GIF saga) scared browser vendors away.

*No browser support.* Internet Explorer, Firefox, and then Chrome and Safari
never shipped native JPEG 2000 support for web content. (Safari has supported
it since 2017 for iOS developers using the HEIF container, but not as a web
image format.) Without browser support, web developers could not use it.
Without web developers using it, the ecosystem of encoders, image editing tools,
and CDN support never developed.

*Network effects and inertia.* The installed base of JPEG (cameras,
editing software, content management systems, email clients, social media
platforms) was vast. JPEG 2000 would have needed to be _dramatically_ better,
cheaper to decode, and universally supported to overcome that inertia. It was
better. But not dramatically so at the quality levels typical users cared about.

#scoreboard(caption: "The JPEG 2000 lesson: technical advantage vs. market outcome",
  [JPEG (1992)], [~30 KB], [10:1], [Web universal; fast; blocking at low quality],
  [JPEG 2000 (2001)], [~20 KB], [15:1], [Technically superior; never won web],
  [PNG (1996)], [~200 KB], [Lossless], [Won niche: lossless, transparency],
  [AVIF (2019)], [~15 KB], [20:1], [Royalty-free; AV1-based; won web],
  [JPEG XL (2022)], [~12 KB], [25:1], [Image-native; back in Chrome Feb 2026],
)

=== Where JPEG 2000 Actually Won

Losing the web did not mean losing everywhere. In niches where its technical
advantages mattered more than decode speed on mobile browsers, JPEG 2000 found
durable homes:

*Digital cinema.* In 2005, the *Digital Cinema Initiatives (DCI)* consortium
(the Hollywood studios) selected JPEG 2000 as the mandatory compression
standard for Digital Cinema Packages (DCPs). Every movie you have watched in a
digital cinema was stored and distributed as JPEG 2000. The reasons were
exactly the ones the web could not pay for: high bit depth, lossless options,
precise quality at high bitrates, and a single well-defined standard that
studios could mandate.

*Medical imaging.* DICOM, the standard for medical image storage and
transmission, incorporates JPEG 2000 as a compression option. CT scans, MRIs,
and pathology slides need the lossless mode, the high bit depth, and the
progressive decoding (to show a low-resolution preview quickly while the full
image loads).

*Digital archiving.* The US Library of Congress, many national archives, and
the Google Books project adopted JPEG 2000 for long-term storage of scanned
documents, precisely because its lossless mode preserves every pixel.

The lesson is precise and counterintuitive: *the same technical properties that
made JPEG 2000 unattractive for consumer web use made it ideal for
professional, archival, and mission-critical uses*. The format found its true
market. It just was not the market its creators had hoped for.

#keyidea[
  Technical superiority does not guarantee market success. Adoption is determined
  by: decoder cost at scale; patent clarity; ecosystem inertia; and whether
  "good enough" already exists. JPEG was good enough for most users; the extra
  quality of JPEG 2000 did not justify the switching cost. The same dynamic
  appears repeatedly: Betamax vs. VHS, DAT vs. CD, FLAC vs. MP3, and JPEG 2000
  vs. JPEG.
]

=== The Slow Vindication

JPEG 2000 has been partly vindicated, not by conquering the web, but by
demonstrating that its _ideas_ were right. The JPEG XL standard (Chapter 45),
finalized 2021–2022 and back in Chrome as of February 2026, was co-developed
by Jon Sneyers, one of the key minds behind FLIF, and borrows several
architectural ideas from JPEG 2000: progressive decoding, high bit depth,
lossless and lossy in one format, and a careful attention to professional
workflows. JPEG XL is not a wavelet codec; it uses a variable-block-size DCT
and the Modular mode for lossless. But the _design philosophy_ that failed
commercially in 2001 has quietly shaped the designs that came after.

== The xz Backdoor: When the Attack Came From Inside the Project

=== A Strange Latency

On a weekday morning in late March 2024, *Andres Freund*, a software engineer
at Microsoft and a contributor to the PostgreSQL database project, was running
performance tests on a Linux system. SSH logins were taking about 500
milliseconds, roughly five times longer than expected. Most engineers would
have moved on. Freund did not. He profiled the connection and found that the
`sshd` process was consuming an unexpectedly large amount of CPU cycles inside
a library called `liblzma`, the library at the core of *XZ Utils*, one of the
most widely used compression tools on Linux.

That anomaly set off a ten-day investigation that ended with one of the most
significant supply-chain security disclosures in the history of open-source
software.

=== XZ Utils and Why It Matters

XZ Utils is a small, unglamorous package. It implements the LZMA2 compression
algorithm (the engine of the `.xz` format) and provides the `xz` command-line
tool. It is not famous. Most users have never heard of it. But it is a
_dependency_ of thousands of other packages. On many Linux distributions,
`liblzma` is linked into `systemd`, and `systemd` is linked into `sshd`, the
daemon that handles all remote logins. This chain meant that a vulnerability in
`liblzma` was, in effect, a vulnerability in SSH itself on affected systems.

=== The Attack: Three Years of Patience

The attacker operated under the GitHub username *Jia Tan* (handle: `JiaT75`).
The account was created in 2021, and for over two years the person behind it
did nothing but make legitimate, high-quality contributions to various
open-source projects, including XZ Utils. The contributions were technically
correct, the code was clean, and the patches were helpful.

During the same period, a series of other accounts (widely believed to be
"sock puppets" controlled by the same actor) began posting complaints to the
XZ Utils mailing list, arguing that the project's maintainer, *Lasse Collin*,
was too slow to review and merge contributions. The pressure was persistent and
targeted. By late 2022, Jia Tan had been granted co-maintainer status and,
by 2023, had replaced Collin as the primary contact for Google's `oss-fuzz`
fuzzing service, a key quality-assurance relationship.

The timeline of the actual backdoor:

- *January 22, 2024*: First backdoor-related commit.
- *February 23, 2024*: The obfuscated backdoor payload committed to the
  repository.
- *February 24, 2024*: XZ Utils *5.6.0* released, the first version containing
  the backdoor.
- *March 9, 2024*: XZ Utils *5.6.1* released, with minor "fixes" that in fact
  refined the backdoor.
- *March 28, 2024*: Andres Freund posts to the Openwall security mailing list.
  Within 24 hours, Linux distributions including Red Hat, Debian, and SUSE
  reverted to the previous clean version. CVE-2024-3094 was assigned, with a
  CVSS score of *10.0*, the highest possible.

#fig(
  [The xz backdoor timeline: trust-building spanning years, then a narrow
   window of deployment before discovery.],
  cetz.canvas({
    import cetz.draw: *
    // Timeline bar
    line((0, 1.5), (10, 1.5), mark: (end: ">"), stroke: 1pt)
    // Ticks and labels
    let ticks = (
      (0.0, "2021\nJia Tan\ncreated"),
      (2.5, "Late 2022\nCo-maintainer\nstatus"),
      (5.5, "Jan 2024\nFirst bad\ncommit"),
      (7.0, "Feb 24\n5.6.0\nreleased"),
      (8.5, "Mar 9\n5.6.1\nreleased"),
      (10.0, "Mar 28\nFreund\ndiscovers"),
    )
    for (x, lbl) in ticks {
      line((x, 1.3), (x, 1.7), stroke: 0.8pt)
      // Split the label on newlines so each fragment is a real line break.
      let lines = lbl.split("\n")
      content((x, 0.4), align(center, text(size: 6.8pt)[
        #lines.join(linebreak())
      ]))
    }
    // Shaded "trust building" zone
    rect((0, 1.5), (5.5, 1.8), fill: green.lighten(70%), stroke: none)
    content((2.75, 2.0), box(width: 5.1cm, align(center, text(size: 7pt, fill: eastern)[Trust-building phase (2+ years)])))
    // Shaded "backdoor live" zone
    rect((7.0, 1.5), (10.0, 1.8), fill: red.lighten(70%), stroke: none)
    content((8.5, 2.0), box(width: 2.6cm, align(center, text(size: 7pt, fill: red)[Backdoor live (33 days)])))
  })
)

=== How the Backdoor Worked

The attack was technically remarkable for its sophistication. The malicious code
was not stored in the GitHub repository in plain sight. It was hidden inside
*binary test files*, nominally "test data" for compression library testing. A
build script extracted and injected the payload only when building release
tarballs, not when compiling from source via git. This means:

- Reviewing the git history showed no malicious C code.
- Running standard source-code analysis tools on the repository found nothing.
- The backdoor was only present in the release packages that distributions would
  download and ship.

The payload itself modified the `liblzma` library to hook into the RSA key
verification code in `sshd`. The hook allowed someone with a specific private
key (presumably Jia Tan's) to authenticate to any affected system _without
knowing the correct password_: a universal remote login backdoor.

#aside[
  CVE-2024-3094 affected only versions 5.6.0 and 5.6.1 of XZ Utils, and only
  on systems where those versions were linked into `sshd` (common in rolling-
  release distributions like Arch Linux and some Fedora betas, but not yet in
  stable Debian or Ubuntu releases at the time of discovery). This is part of
  why the attack was caught before causing widespread damage: it had been shipped
  to bleeding-edge distributions but not yet to the conservative stable releases
  that run most production servers.
]

=== What the xz Backdoor Teaches

The xz incident is not, strictly speaking, a compression failure (the LZMA
algorithm is correct). It is a *trust failure* at the intersection of
compression software and open-source maintenance practices. The lessons it
crystallised have been discussed in security communities for years since
discovery:

*Open source is not the same as audited source.* The conventional wisdom is
that "many eyes make all bugs shallow" (Linus's Law). The xz attacker understood
this and worked around it: the malicious payload was not in source code that
eyes could review, but in binary blobs that most reviewers glance past.

*Maintainer burnout is an attack surface.* Lasse Collin had been maintaining
XZ Utils largely alone for years. The social-engineering campaign targeted him
precisely because he was overworked and receptive to help. Under-resourced
maintainers of critical infrastructure are a systemic vulnerability.

*Supply chains extend downward, invisibly.* Most users of `sshd` had never
heard of `liblzma`. The chain from a tiny compression library to a universal
SSH backdoor was invisible until it mattered.

*State-level sophistication.* The two-and-a-half-year patience, the technical
depth, the multi-account social engineering, and the sophisticated hiding of
the payload all pointed to a well-resourced, likely nation-state-level actor.
No individual hobbyist would invest that much time in such a subtle attack. As
of June 2026, the true identity of "Jia Tan" has not been publicly confirmed.

#pitfall[
  Do not conclude that open source is uniquely vulnerable. Closed-source
  software can conceal backdoors just as well (or better), with fewer people
  positioned to notice. The xz case is notable because the open-source process
  _allowed_ Freund to find it: the SSH latency anomaly led him to public source
  code he could actually read. A closed-source library would have offered no
  such pathway.
]

=== The Aftermath and Systemic Response

The discovery triggered a broad conversation about open-source security practices:

- *OpenSSF (Open Source Security Foundation)* and various Linux distributions
  increased funding for security audits of critical infrastructure libraries.
- *Reproducible builds* (the practice of ensuring that the same source code
  produces byte-identical binaries) gained urgent attention as a mitigation
  for the "binary test file" hiding technique.
- The concept of *software bills of materials (SBOMs)*, inventories of every
  dependency a piece of software relies on, accelerated in adoption, pushed by
  both the US federal government and the European Union's Cyber Resilience Act.

None of this makes the underlying problem go away. Compression libraries, codec
implementations, and low-level file-format parsers are exactly the kind of code
that sits deep in dependency trees, receives minimal security scrutiny, and
processes untrusted data. The xz backdoor was a compression story that turned
into a security story, a reminder that the tools we build for data efficiency
can become attack vectors.

== Engineering Epistemics: What Failure Teaches

=== The Pattern of Cautionary Tales

Looking across the four stories in this chapter (the counting argument, fractal
compression, JPEG 2000's market failure, and the xz backdoor), a few patterns
emerge that are worth naming explicitly.

*Impossibility claims deserve a mathematical gun, not a wait-and-see.* The
counting argument is absolute. When someone claims lossless universal
compression, do not ask to see benchmarks. Ask them to explain how they evade
the pigeonhole principle. They cannot. Save everyone's time.

*Theory and practice diverge in both directions.* Fractal compression was
theoretically elegant but practically too slow. JPEG was theoretically crude
(8×8 block DCT is not the optimal transform for any known image model) but
practically fast enough to win. In engineering, "good enough, right now" usually
beats "perfect, eventually."

*Ecosystem is often more important than technology.* JPEG 2000 lost not because
JPEG was technically superior, but because JPEG was already everywhere. The
switching cost was invisible but enormous. Any technology that requires the
whole world to upgrade in lockstep faces this problem.

*Security vulnerabilities hide in boring, trusted code.* The xz backdoor did
not hide in an exciting, security-critical library. It hid in an unremarkable
compression utility that happened to sit in a critical dependency chain.
"Low-profile" and "low-risk" are not the same thing.

*Patience and trust are attack surfaces.* The most sophisticated attack in
recent open-source history did not exploit a buffer overflow or a cryptographic
weakness. It exploited social dynamics: maintainer exhaustion, the goodwill
extended to a reliable contributor, and the human tendency to trust people who
have been helpful for a long time.

=== Honest Engineering Epistemics

The phrase _engineering epistemics_ sounds fancy, but it means: how do we know
what we know, and how should we update when we are wrong?

#keyidea[
  A field that only celebrates its successes cannot learn from its failures.
  Fractal compression, for all its commercial disappointment, generated real
  research that influenced multi-scale image analysis for decades. JPEG 2000's
  failure in consumer markets highlighted exactly the properties needed for
  JPEG XL to eventually succeed. The counting argument has prevented countless
  hours of wasted engineering by giving a two-line proof that certain classes of
  algorithms are impossible. Even the xz backdoor, as damaging as it could have
  been, produced a net gain in open-source security awareness and funding.
  *Failure is a precision instrument for learning, when we bother to look at it.*
]

The bias toward success stories in textbooks and conference papers is not
malicious; nobody wants to write a paper about the algorithm that did not work.
But it produces a distorted map of the territory. This chapter is an attempt at
correction. The things that did not work, the claims that were wrong, and the
attacks that almost succeeded are as important to understand as the breakthroughs.

#checkpoint[
  What do fractal compression and JPEG 2000 have in common, despite being very
  different technologies?
][
  Both were technically superior to the dominant alternative (JPEG) in at least
  some measurable dimension, yet both failed to displace it commercially. In
  both cases, the reason was not the quality of the underlying mathematics but
  practical engineering constraints (encoding speed for fractal compression;
  decoder cost, complexity, and ecosystem inertia for JPEG 2000).
]

=== A Diagnostic Tool for Compression Claims

Here is a practical checklist you can apply to any new compression claim,
whether from an academic paper, a vendor whitepaper, or a comment on a forum:

#note[
  *The Compression Claim Checklist*

  1. *Is the claim lossless-universal?* If it says it compresses _every_ input,
     invoke the counting argument immediately. The claim is false.

  2. *What is the test corpus?* Compression ratios are meaningful only relative
     to specific input types. A compressor optimised for English text will look
     terrible on genomic data and random bytes.

  3. *What is the encoding speed?* A compressor with a 1,000,000:1 ratio that
     takes ten years to encode is not useful.

  4. *Is the decompressor independently implementable?* If the algorithm is
     secret, it cannot become a standard, cannot be audited for correctness, and
     cannot be trusted.

  5. *What are the patent encumbrances?* JPEG 2000 and numerous other superior
     technologies stalled partly because of patent uncertainty.

  6. *Has it been independently reproduced?* A single group's result, with a
     proprietary binary, is a starting hypothesis, not a finding.

  7. *Where does it break?* Every compressor has inputs it handles poorly. If
     nobody will show you those inputs, be suspicious.
]

== Further Reading

#link("https://matt.might.net/articles/why-infinite-or-guaranteed-file-compression-is-impossible/")[Matt Might, _Why Guaranteed File Compression is Impossible_ (2012).] A clear, short web essay deriving the counting argument with minimal prerequisites.

#link("https://en.wikipedia.org/wiki/Fractal_compression")[Wikipedia: Fractal Compression.] A good starting reference with pointers into the primary literature.

#link("https://blog.ansi.org/ansi/why-jpeg-2000-never-used-standard-iso-iec/")[ANSI Blog: Why JPEG 2000 Never Took Off.] A readable overview of the adoption barriers.

#link("https://cloudinary.com/blog/the_great_jpeg_2000_debate_analyzing_the_pros_and_cons_to_widespread_adoption")[Cloudinary: The Great JPEG 2000 Debate.] Industry perspective on the pros and cons.

#link("https://securitylabs.datadoghq.com/articles/xz-backdoor-cve-2024-3094/")[Datadog Security Labs: The XZ Backdoor, Everything You Need to Know.] Detailed technical analysis of CVE-2024-3094.

#link("https://en.wikipedia.org/wiki/XZ_Utils_backdoor")[Wikipedia: XZ Utils Backdoor.] A well-maintained summary of the attack, discovery, and aftermath.

#link("https://compressionscams.blogspot.com/")[Compression Scams blog.] An informal but useful archive of impossible-compression claims over the decades.

#link("https://malicious.life/episode/jan_sloots_data_compression_system/")[Malicious Life Podcast: Jan Sloot's Data Compression System.] An entertaining and informative account of the Sloot affair.

== Exercises

#exercise("78.1", 1)[
  Apply the counting argument to the following claim: "Our algorithm can compress
  any file of size 1 byte to 0 bytes." Count the number of 1-byte files and the
  number of 0-byte files. Why does this immediately refute the claim?
]

#solution("78.1")[
  There are $2^8 = 256$ distinct 1-byte files (all bit patterns from 00000000 to
  11111111). There is exactly $2^0 = 1$ file of 0 bytes (the empty file). A
  lossless compressor cannot map 256 distinct inputs to 1 output; the
  decompressor cannot know which of the 256 original inputs to restore. The
  claim is impossible.
]

#exercise("78.2", 2)[
  Suppose you are given an already-compressed archive (say, a `.zip` file of
  source code). A friend suggests running it through gzip again to save more
  space. Using the counting argument, explain (a) why this cannot consistently
  produce smaller output, and (b) why in practice it usually makes the file
  slightly _larger_.
]

#solution("78.2")[
  (a) The counting argument says no compressor can compress every input. In
  particular, there must exist some inputs that the compressor cannot shrink,
  and the set of already-compressed files is a natural candidate. (b) A `.zip`
  file has had its redundancy removed: the symbol frequencies are close to
  uniform, so the entropy is near the maximum (≈ 8 bits/byte). Huffman and LZ77
  cannot exploit structure that does not exist. The overhead of gzip's header
  and metadata then makes the output a few dozen bytes _larger_ than the input.
]

#exercise("78.3", 2)[
  In 100–150 words, write a memo to a non-technical manager explaining why the
  company should not pay a vendor who claims their tool can "compress any file to
  one-tenth its original size, guaranteed, with no data loss." Use the counting
  argument in plain language.
]

#solution("78.3")[
  A model memo: "The vendor is claiming something mathematically impossible.
  Here is why. If you gave this tool every possible 1 MB file, there are more
  possible 1 MB files than possible 100 KB files. That means some 1 MB files
  would have to produce the same 100 KB output, so the tool could not losslessly
  tell them apart when decompressing. This is not a hard engineering problem
  waiting for the right breakthrough; it is a fundamental counting argument. No
  algorithm, no matter how clever, can evade it. We should not pay for something
  the laws of mathematics say cannot exist."
]

#exercise("78.4", 2)[
  Fractal compression was technically elegant but commercially unsuccessful.
  Identify three specific engineering trade-offs that led to its failure, and for
  each one, explain which competing technology addressed that trade-off and how.
]

#solution("78.4")[
  1. *Encoding speed.* Fractal encoding required hours per image; JPEG encodes in
  a second because the 8×8 DCT is a fixed-time operation with no search. Modern
  codecs like HEVC and AV1 also require long encoding times but use parallelism
  and hardware acceleration to manage it.

  2. *Quality at high bitrates.* JPEG and JPEG 2000 provide better PSNR (the
  peak signal-to-noise ratio quality measure from Chapter 42) at
  equivalent file sizes because their transforms (DCT, wavelet) are better matched
  to typical image statistics than a data-driven IFS search. Learned codecs
  (Chapter 57) address this further with end-to-end optimisation.

  3. *Patent encumbrances.* Iterated Systems Inc. held numerous patents and was
  slow to license. JPEG was standardised openly. Open licensing (as with AV1 and
  JPEG XL) is now considered a prerequisite for web format adoption.
]

#exercise("78.5", 3)[
  Research the concept of *reproducible builds* and explain, in a paragraph, how
  they would have made the xz backdoor either (a) much easier to detect earlier,
  or (b) harder to conceal. Support your argument with specific reference to
  how the backdoor payload was hidden.
]

#solution("78.5")[
  Reproducible builds ensure that compiling the same source code always produces
  byte-identical binaries, regardless of the build environment or time. The xz
  backdoor hid its payload in binary test-data files included in the release
  tarballs, not in the git repository source. A reproducible build system would
  have required that the release tarball be derivable from the git source alone,
  with no additional binary blobs. Any discrepancy between the git-built binary
  and the release-tarball binary would have been immediately detectable. In this
  specific case, the backdoor payload would either have had to appear in the git
  repository (where it could be read and reviewed) or the reproducible build
  would have failed to match, triggering an alert. Reproducible builds do not
  prevent all attacks, but they close the specific hiding technique used here:
  injecting malicious content only in release artifacts.
]

#takeaways((
  "The counting (pigeonhole) argument proves that no lossless compressor can compress every input: there are always more possible inputs than possible shorter outputs.",
  "Compression scams across the decades (WEB Technologies 1992, ZeoSync 2002, Jan Sloot 1999) all violate this same mathematical impossibility; the counting argument dismisses them without inspecting any code.",
  "Fractal image compression was mathematically elegant but commercially failed due to catastrophic encoding speed, artifacts where self-similarity was weak, and patent barriers; its ideas later reappeared in intra-prediction and multi-scale learned codecs.",
  "JPEG 2000 was technically superior to JPEG in almost every measurable dimension but lost the web due to higher decoder cost, format complexity, patent uncertainty, and ecosystem inertia; it won in digital cinema, medical imaging, and archival.",
  "Technical superiority does not guarantee market success: ecosystem inertia, decoder cost, and patent clarity often matter more than compression ratio.",
  "The xz backdoor (CVE-2024-3094, March 2024) was a sophisticated supply-chain attack that planted a universal SSH backdoor via a compression library, concealed in binary test files, by a contributor who spent over two years building trust.",
  "The xz attack exploited maintainer burnout, social engineering via sock-puppet accounts, and the architectural invisibility of low-level library dependencies, all attack surfaces that are characteristic of open-source infrastructure.",
  "Honest engineering epistemics requires studying failures as carefully as successes: the pattern of what breaks and why is the most reliable guide to what will work next.",
))

#bridge[
  We have looked honestly at what did not work and why. Now, stepping back from
  cautionary tales to the panoramic view: *Chapter 79* takes stock of where the
  entire field of compression stands in June 2026. Which formats actually
  dominate deployment? How close are learned codecs to displacing classical
  engineered designs? What does the convergence of compression and machine
  learning mean for the discipline's identity going forward? The wreckage of
  Chapter 78 maps the rocks; Chapter 79 charts the navigable water.
]
