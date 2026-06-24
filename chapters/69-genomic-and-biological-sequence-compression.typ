#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Genomic and Biological Sequence Compression

#epigraph[
  The human genome is the most compressible long document in existence, provided
  you have another human genome to compress it against.
][_Folk wisdom among bioinformaticians_]

In 2012, a hospital in Boston sequenced the genomes of every newborn in its
neonatal intensive care unit. The data arrived at 150 gigabytes per baby. Over
the course of a year, they sequenced hundreds of children, and the storage bill
was threatening to dwarf the cost of the sequencing machines themselves. The
bottleneck was not the biology. It was the file format.

That file format was FASTQ: a plain text file that stores every short read the
machine produces, each paired with a string of "quality scores" that say how
confident the sequencer was about each base. Uncompressed, a single whole-genome
sequencing run produces 100 to 300 gigabytes of FASTQ. Compressed with gzip,
you claw back maybe 70 percent. Still tens of gigabytes, and gzip has no idea
it is looking at DNA. It is treating adenine and thymine the same as commas and
colons.

The deeper insight changes everything: *any two human genomes are 99.9 percent
identical*. If you already have one human genome on file, a second one is not
150 gigabytes of new information. It is a list of roughly 4 to 5 million
positions where the two disagree: a difference file, a delta. And a difference
file is tiny.

This is the core idea of *reference-based compression*, and it is the subject
of this chapter. We will trace the chain from raw sequencing reads through the
aligned-read format (BAM), through the reference-compressed format (CRAM), and
through the statistical models that handle the trickiest part of all: quality
scores. We will revisit the Burrows–Wheeler Transform and FM-index from
Chapter 35, not as compressors this time but as search engines that make
reference-based alignment fast enough to be practical. And we will look at where
the field is going in 2025 and 2026, with neural and LLM-assisted compressors
beginning to challenge the classical tools.

#recap[
  Chapter 35 introduced the Burrows–Wheeler Transform (BWT) and showed how the
  same LF-mapping that underpins bzip2 can be turned into the *FM-index*: a
  searchable, compressed representation of a long string that modern DNA aligners
  (Bowtie, BWA) use to find where sequencing reads match a reference genome.
  Chapters 66 through 68 explored the "know your data" philosophy in scientific
  floating-point compression (zfp, SZ), columnar databases (Parquet), and
  time-series (Gorilla). Genomic compression is the most dramatic application of
  that philosophy: the "model" of the data is another genome, and the residual
  after that prediction is extraordinarily small.
]

#objectives((
  "Explain the difference between FASTA, FASTQ, SAM, BAM, and CRAM, and describe what each stores.",
  "Trace how reference-based compression works: align, find differences, store the difference.",
  "Describe CRAM's internal architecture: reference subtraction, quality-score models, and entropy coding.",
  "Explain why quality scores dominate the file size and the trade-offs in lossy quality binning.",
  "Connect the BWT/FM-index from Chapter 35 to the alignment step that makes reference compression possible.",
  "Name the major reference-free compressors (JARVIS3) and the 2024–2026 neural frontier (AgentGC).",
))

== The Genomics Data Deluge

Before we can compress a genome, we need to understand what genomic data actually
looks like, because the format matters enormously for the compression strategy.

A *genome* is the complete genetic instruction manual of an organism, written in
an alphabet of four letters: A, C, G, and T (adenine, cytosine, guanine,
thymine). The human genome is roughly 3.2 billion of these letters long. Stored
naively at 2 bits per letter (since $log_2 4 = 2$), that is 800 megabytes: a
perfectly manageable size for one person's genome. The problem is that we never
store just one copy.

A DNA sequencing machine does not read the genome like a book, cover to cover.
It shatters the DNA into millions of tiny fragments, reads each fragment
independently, and gives you a pile of short "reads" (typically 100 to 300
letters each for the Illumina short-read technology that dominates the field).
To reconstruct the original genome you must then figure out how all those
overlapping pieces fit together, either by comparing them against a known
*reference genome* or by assembling them from scratch.

A single sequencing run typically produces 30 to 100 copies of every position
in the genome (called "30× to 100× coverage"), because you need redundancy to
correct sequencing errors. So instead of storing 800 MB once, you are storing
800 MB thirty times over, plus error annotations. The raw output is not
one tidy sequence but hundreds of millions of short fragments.

=== The File Format Zoo

#definition("FASTA")[
  A plain-text format for storing one or more biological sequences. Each entry
  starts with a header line beginning with `>` and a name, followed by one or
  more lines of sequence data. FASTA stores only the sequence letters (no
  quality scores, no alignment information). It is used for reference genomes,
  protein sequences, and assembled contigs.
]

#definition("FASTQ")[
  An extension of FASTA that adds per-base *quality scores* to every read.
  Each record is four lines: (1) a header line starting with `@`, (2) the
  sequence, (3) a separator line starting with `+`, (4) the quality string.
  The quality string has the same length as the sequence; each character
  encodes the *Phred quality score* (Q) for the corresponding base.
]

#definition("SAM / BAM")[
  *SAM* (Sequence Alignment/Map) is a tab-delimited text format that stores
  reads _together with their alignment_ to a reference genome: which chromosome,
  which position, and any mismatches or gaps. *BAM* (Binary Alignment/Map) is
  the binary, gzip-compressed equivalent of SAM. BAM files are the standard
  intermediate format for most genomics pipelines and serve as the input to
  CRAM.
]

#definition("CRAM")[
  A compressed, reference-aware replacement for BAM. Instead of storing the
  full read sequences, CRAM stores only the differences between each read and
  the reference genome, plus the quality scores and read metadata. CRAM was
  standardized by the *Global Alliance for Genomics and Health* (GA4GH) and is
  maintained as a community standard.
]

#gopython("Phred quality scores and the ASCII encoding trick")[
  A *Phred quality score* Q encodes the probability $p$ that a base is wrong:
  $Q = -10 log_10 p$. So Q = 20 means a 1-in-100 chance of error; Q = 30
  means a 1-in-1000 chance; Q = 40 means a 1-in-10,000 chance.

  Illumina sequencers produce Q scores roughly in the range 0–40. To store
  them in a plain-text file, FASTQ adds 33 to the Q score and encodes the
  result as an ASCII character (so Q=0 becomes `!`, Q=40 becomes `I`).

  ```python
  def q_to_char(q: int) -> str:
      """Convert Phred quality score to FASTQ ASCII character."""
      return chr(q + 33)

  def char_to_q(c: str) -> int:
      """Convert FASTQ ASCII character to Phred quality score."""
      return ord(c) - 33

  # Example: the quality string "IIIIIIIIII" means all bases have Q=40
  example_qual = "IIIIIIIIII"
  scores = [char_to_q(c) for c in example_qual]
  print(scores)   # [40, 40, 40, 40, 40, 40, 40, 40, 40, 40]
  ```

  The space of possible Q values is small (typically 0–41 in Illumina data,
  so 42 possible values), but each read has _one quality character per base_,
  and quality strings often compress poorly because the values fluctuate
  unpredictably across each read.
]

To understand the scale of the problem, here is a rough accounting for a single
30× human whole-genome sequencing run:

#fig(
  [Size comparison of genomic data formats for one 30× human WGS run.],
  cetz.canvas({
    import cetz.draw: *
    // Bar chart showing sizes
    let bars = (
      ("FASTQ (raw)", 200, "200 GB"),
      ("FASTQ.gz", 60, "60 GB"),
      ("BAM", 90, "90 GB"),
      ("CRAM 3.1", 20, "~20 GB"),
    )
    let bar-w = 1.8
    let gap   = 0.5
    let scale = 0.05
    for (i, (label, size, lbl)) in bars.enumerate() {
      let x = i * (bar-w + gap)
      let h = size * scale
      rect((x, 0), (x + bar-w, h),
        fill: if i == 3 { rgb("#0b6e4f").lighten(40%) } else { rgb("#0b5394").lighten(60%) },
        stroke: 0.5pt + rgb("#1a1a1a").lighten(30%))
      content((x + bar-w / 2, h + 0.25), box(width: 1.4cm, align(center, std.text(size: 7pt)[#lbl])))
      content((x + bar-w / 2, -0.4), box(width: 1.4cm, align(center, std.text(size: 7pt)[#label])), anchor: "north")
    }
    // Y axis label
    content((-0.6, 5 * 0.05 * 200 / 2 / 10), text(size: 7pt)[File size], angle: 90deg)
  })
)

The numbers above are approximate but representative of real-world pipelines.
CRAM's ~20 GB per sample is a ten-fold improvement over raw FASTQ, and it is
_lossless_ (or near-lossless, depending on quality-score treatment). To
understand how CRAM achieves this, we need to understand reference-based
compression from the ground up.

== Reference-Based Compression: Predict Then Code the Residual

The core idea of reference-based compression is the same as every other
prediction-based compressor in this book, from FLAC's linear predictors
(Chapter 50) to video inter-frame coding (Chapter 51): *if you can predict what
the data will be, you only need to store the prediction error*.

For genomic reads, the "prediction" is the reference genome. Here is the logic:

1. You have a reference genome (a single, canonical version of the human
   genome, maintained by the Genome Reference Consortium).
2. A sequencer produces a read: `ACGTTTGCAAGTCCAT...` (150 bases).
3. An aligner maps that read to the reference, finding that it matches position
   12,345,678 on chromosome 3, with one mismatch: position 12 of the read
   is T in the sample but C in the reference.
4. Instead of storing all 150 bases, you store: "chromosome 3, position
   12,345,678, length 150, mismatch at offset 12: T instead of C."
5. That record is maybe 20–30 bytes instead of 150. A 5–7× compression just
   from the alignment, before any entropy coding.

#keyidea[
  Reference-based compression is *delta coding against an external source*. The
  reference genome plays the same role as a video's previous frame in inter-
  frame video compression (Chapter 51), or as a dictionary entry in LZW
  (Chapter 29). The key
  difference is scale: a video frame differs from the previous frame by perhaps
  5–20%; a human genome differs from the reference by only ~0.1%. The residual
  is almost nothing.
]

=== What Gets Stored in a CRAM File

A CRAM file is not one monolithic compressed blob. It is a collection of
*slices*, each covering a genomic region (a stretch of chromosome). Within each
slice, the data is separated into independent *data series*, each compressed
with its own entropy coder, because different types of data have very different
statistics:

- *Read positions* (where on the chromosome does each read map): delta-coded
  from the previous read's position, then entropy-coded. Highly compressible.
- *Sequence differences* (mismatches, insertions, deletions): the rare cases
  where the read differs from the reference. These are the actual genetic
  variants. Very sparse: most reads have zero or one.
- *Quality scores*: one integer per base per read. This is the dominant cost
  in practice. Quality scores fluctuate a lot and compress poorly (see next
  section).
- *Read names*, *flags* (paired/unpaired, mapped/unmapped, etc.): metadata.
- *CIGAR strings*: a compact notation for insertions and deletions relative to
  the reference (`M` = match, `I` = insertion, `D` = deletion).

CRAM 3.1 (released 2022) modernized the entropy-coding backends, adding
range coding (similar to the range coder from Chapter 26) and rANS (from
Chapter 27) as options alongside gzip-based coding. The choice of codec per
data series is stored in the file header, so a decoder always knows what it is
getting.

#algo(
  name: "CRAM",
  year: "2011, standardized 2014; CRAM 3.1 in 2022",
  authors: "Markus Hsi-Yang Fritz et al.; GA4GH consortium",
  aim: "Reference-based lossless (or near-lossless) compression of aligned sequencing reads",
  complexity: "Encoding: O(N · L) where N = number of reads, L = read length; effectively linear in input size. Decoding: same.",
  strengths: "50–70% smaller than BAM on typical human data; lossless or controlled-lossy for quality scores; the community standard, supported by all major tools (samtools, GATK, Picard).",
  weaknesses: "Requires the reference genome to be present at decode time; performance degrades for data with high variant rates (e.g. cancer genomes, highly variable species); quality-score compression is still limited.",
  superseded: "Supersedes BAM for archival storage; BAM remains widely used for active analysis pipelines.",
)[
  CRAM is the dominant deployed solution for genomic read storage as of 2026.
  The GA4GH consortium (Global Alliance for Genomics and Health) maintains the
  specification and provides the reference implementation (`htslib`/`samtools`).
  CRAM 3.1 added *adaptive arithmetic coding* and *rANS* backends, achieving
  an additional 7–15% size reduction compared to CRAM 3.0.
]

== The Trickiest Part: Quality Scores

Here is a fact that surprises most people: in a CRAM file, the *sequence bases*
(A, C, G, T) often account for only a small fraction of the total file size.
The dominant cost is the *quality scores*, the per-base confidence values
attached to each read.

Why? Because sequences, after reference subtraction, are nearly all identical
to the reference. There is almost nothing to store. But quality scores are
noisy. Even a perfectly healthy human genome will have quality scores that
bounce around from Q=10 to Q=40 across every read, because the machine's
confidence genuinely varies from base to base depending on local sequence
context, GC content, and instrument wear. Neighboring quality scores are
correlated, but not in a simple or predictable way.

#gomaths("Information entropy of quality scores")[
  Recall from Chapter 18 that the entropy of a source is
  $H = -sum_i p_i log_2 p_i$
  where $p_i$ is the probability of symbol $i$. For a FASTQ quality string
  with 42 possible values (Q = 0 to 41), if the values were uniformly
  distributed the entropy would be $log_2 42 approx 5.4$ bits per quality
  character. In practice, Illumina quality scores cluster around Q = 30–40
  for most bases (the machine is usually confident), so the true entropy is
  lower, roughly 3–4 bits per quality character. But since there is one
  quality character per base, and bases take only 2 bits each after alignment,
  quality scores can cost *twice as many bits as the bases themselves*.
]

=== Lossless Quality Compression

Within CRAM 3.1, quality scores are entropy-coded with range coding or rANS
after applying a *context model*: the coder conditions each quality value on the
neighboring quality values and on the position within the read (the first and
last few bases of a read are systematically lower quality, a well-known
Illumina artifact). This context modeling is the same idea as PPM (Chapter 33),
applied to quality values instead of text characters.

Even with good context modeling, lossless quality compression is hard. Quality
scores are what information theorists call *near-memoryless*: the short-range
correlation is real but weak, and the long-range correlation (across reads) is
essentially zero. You cannot do much better than 3–4 bits per score losslessly.

=== Lossy Quality Binning: Trading Precision for Space

The insight that drives much greater compression is biological: *you do
not need all 42 quality levels to call genetic variants accurately*.

Illumina's GATK variant caller (the industry standard for finding genetic
mutations) was tested exhaustively, and it turns out that 8 quality bins are
sufficient for nearly all downstream analyses: Q=0, Q=10, Q=20, Q=25, Q=30,
Q=35, Q=40, and "maximum." By rounding each quality score to the nearest bin,
you reduce the alphabet from 42 values to 8 ($log_2 8 = 3$ bits in the best
case, and in practice 2–3 bits with entropy coding). The quantized values are
also smoother (less noisy), so context models work better.

CRAM supports this as an optional lossy mode. Illumina's *DRAGEN* platform
(which includes the *ORA* compression format, acquired from Enancio) uses an
even more aggressive approach: it compresses FASTQ files at the instrument
before any alignment, achieving 5–6× compression over the standard fastq.gz,
partly by applying reference alignment internally and partly by quality binning.

#pitfall[
  Quality-score lossy compression is *irreversible*. Once you bin quality
  scores from Q=37 and Q=39 to the same value Q=35, you cannot recover which
  was which. For archival storage, many institutions keep the original FASTQ
  files (or lossless CRAM) and store a lossy CRAM only as a working copy. The
  clinical implications of discarding quality precision are still actively
  debated in the genomics community.
]

#misconception(
  "Lossless CRAM perfectly preserves the original data.",
  [CRAM is lossless for sequence bases: the A, C, G, T letters are always
   recovered exactly. But CRAM gives you a *choice* about quality scores:
   lossless (store every Q value), lossy (bin to 8 levels), or discard (store
   no quality scores, saving the most space). Whether "lossless CRAM" means
   bit-for-bit identical to the original BAM depends on how your pipeline
   handles quality scores. The GA4GH specification makes these choices explicit,
   but downstream users must be aware of them.]
)

== The Alignment Problem: Where BWT and FM-Index Come Back

We said that reference-based compression works by *aligning* each read to a
reference genome, then storing only the differences. But here is a problem we
glossed over: the reference genome is 3.2 billion bases long. A read is 150
bases. Finding where a 150-base read matches in 3.2 billion bases, allowing
for a few mismatches, sounds like it would take enormous computation. And we
need to do this for hundreds of millions of reads.

The tool that makes this tractable is exactly what Chapter 35 introduced: the
*FM-index*, built on the Burrows–Wheeler Transform.

#mathrecall[The FM-index (Ferragina–Manzini, 2000) is a self-index built from
the BWT of a string $T$. It stores the BWT of $T$ plus two auxiliary tables
(the LF-mapping and a sampled suffix array) that together support *backward
search*: finding all occurrences of a pattern $P$ in $T$ in $O(|P|)$ time,
while the index itself takes $O(|T| log |T|)$ bits, much less than a
full-text index.]

In the genomics context, the "text" $T$ is the reference genome (all 3.2
billion bases, concatenated from all chromosomes). The "pattern" $P$ is a
sequencing read. The aligner builds the FM-index of $T$ once (a one-time
upfront cost of a few hours of computation) and then queries it for every read.
Each query takes O(read length) time, which is O(150): essentially constant
compared to the billions of positions in the genome.

The two most widely used aligners, *Bowtie2* (Ben Langmead, 2009, updated 2012)
and *BWA-MEM* (Heng Li, 2009), are built on exactly this foundation. Every
genomic data analysis pipeline runs one of these aligners to convert FASTQ files
(raw reads) into BAM files (aligned reads) before CRAM compression can happen.

#fig(
  [The pipeline from raw reads to CRAM compressed storage.],
  cetz.canvas({
    import cetz.draw: *
    let box-w = 2.4
    let box-h = 0.7
    let gap = 0.6
    let stages = (
      ("Sequencer", "FASTQ"),
      ("BWT Aligner\n(Bowtie2/BWA)", "BAM"),
      ("CRAM Encoder\n(htslib)", "CRAM"),
      ("Archive\nStorage", "~20 GB"),
    )
    for (i, (top, bot)) in stages.enumerate() {
      let x = i * (box-w + gap)
      rect((x, 0), (x + box-w, box-h),
        fill: rgb("#eef4fb"), stroke: 0.8pt + rgb("#0b5394"))
      content((x + box-w / 2, box-h / 2 + 0.1), box(width: 2.0cm, inset: 1pt, align(center, text(size: 7.5pt)[#top])))
      content((x + box-w / 2, -0.25), text(size: 7pt, fill: rgb("#783f04"))[#bot])
      if i < stages.len() - 1 {
        line((x + box-w, box-h / 2), (x + box-w + gap, box-h / 2),
          mark: (end: ">", fill: rgb("#0b5394")), stroke: 1pt + rgb("#0b5394"))
      }
    }
    content((0 * (box-w + gap) + box-w / 2, -0.55), text(size: 6.5pt)[200 GB])
    content((1 * (box-w + gap) + box-w / 2, -0.55), text(size: 6.5pt)[90 GB])
    content((2 * (box-w + gap) + box-w / 2, -0.55), text(size: 6.5pt)[20 GB])
    content((3 * (box-w + gap) + box-w / 2, -0.55), text(size: 6.5pt)[final])
  })
)

=== The BWT Connection in One Paragraph

In Chapter 35, we saw the BWT as a *permutation for compression*: it rearranges
the characters of `banana` so that identical characters cluster, making entropy
coding easier. Here, we use the same BWT for a completely different purpose:
*searching*. Given the BWT of the reference genome, the FM-index's backward
search can answer "does this read occur in the genome, and if so, where?" in
linear time in the read length. No scanning, no hashing: just backward
induction through the BWT's LF-mapping. The compressed index that stores the
reference is itself the search engine that makes compression possible. This is
one of the most elegant examples of *compression as dual-purpose infrastructure*
anywhere in computer science.

== Reference-Free Compression: JARVIS3 and Beyond

What if you have genomic data that cannot easily be aligned to a reference? This
happens with:
- Bacteria and viruses (enormous diversity; reference genomes often absent or
  poor).
- Novel species being sequenced for the first time.
- Highly rearranged cancer genomes where the tumor has shuffled the chromosomes.
- Assembled contigs (already-assembled genome sequences) rather than raw reads.

For these cases, *reference-free compression* applies compression methods
that treat the genome as a sequence with internal repetition, without needing
an external reference.

The most capable reference-free compressors as of 2024–2025 are based on
*finite-context models* mixed with *repeat models*, a combination closely
related to context mixing (Chapter 34), adapted to exploit the repetitive
structure of DNA.

#algo(
  name: "JARVIS3",
  year: "2024",
  authors: "Diogo Pratas, Morteza Hosseini, Armando J. Pinho",
  aim: "Reference-free lossless compression of FASTA and FASTQ genomic sequences using finite-context and repeat models.",
  complexity: "Roughly O(N log N) in practice; dominated by the repeat model lookup tables.",
  strengths: "Best-in-class reference-free compression ratio on assembled genomes; handles both FASTA (sequence only) and FASTQ (with quality scores); parallel computation supported; three configurable profiles (speed/balance/ratio).",
  weaknesses: "Slower than BAM/CRAM for raw reads; requires more computational resources than gzip-class tools; not widely integrated into standard bioinformatics pipelines.",
  superseded: "Successor to JARVIS2 (2021); further work ongoing toward neural-assisted variants.",
)[
  JARVIS3 achieves compression of assembled human genomes at approximately
  0.3–0.5 bits per base, far below the theoretical 2 bits/base for random DNA,
  and well below gzip's ~1.5 bits/base. On FASTQ (with quality scores), ratios
  are less dramatic because quality scores dominate.
]

=== How Context Models Work on DNA

Genomic sequences are not random. The human genome is ~41% GC (guanine +
cytosine) at the global level, but locally it varies enormously. GC-rich
"CpG islands" flank genes, while repetitive elements (Alu sequences, LINE
elements) repeat nearly verbatim millions of times.

A *finite-context model* of order $k$ keeps a table that maps every $k$-base
context (e.g., `ACGTAC`) to a probability distribution over the next base. For
small $k$ (say, $k = 6$), there are only $4^6 = 4096$ possible contexts: a
small table. For large $k$ (say, $k = 20$), there are $4^(20) > 10^(12)$ possible
contexts, impossible to store fully, so hash tables or trie structures are
used. Higher-order models capture the long repeats in genomes; lower-order
models handle regions with genuine randomness.

A *repeat model* is the genomic analogue of an LZ-style back-reference
(Chapter 28): if the current position looks like a previously seen stretch of
sequence, the model predicts a continuation of that earlier stretch. This is
especially effective for the ~50% of the human genome that consists of
transposable elements (ancient sequences that copied themselves thousands of
times).

JARVIS3 mixes many models (finite-context models of different orders, plus
repeat models) using probability mixing, exactly as PAQ and cmix do for text
(Chapter 34). The output probability is fed to an arithmetic coder (Chapter 26).

== The 2024–2026 Frontier: Neural and LLM-Assisted Genomic Compression

The same trend that brought neural networks into image and video compression
(Chapters 57–60) is now touching genomics. The question is the same: can a
learned model capture regularities in DNA better than a hand-crafted context
model?

=== AgentGC (2026)

*AgentGC* (arXiv:2601.13559, January 2026) represents a recent direction:
using a large language model as an *orchestrator* that autonomously searches
for the best combination of encoding strategies for a given genome. Rather than
training a neural network to compress directly, AgentGC uses an LLM to guide
an evolutionary search over a library of encoding choices, trying different
combinations of transforms, models, and entropy coders and keeping the ones
that work best for the data at hand.

The paper demonstrates improvements over JARVIS3 and other classical tools on
several standard benchmark genomes, with the LLM acting as a meta-compressor
that adapts to the specific statistical profile of each genome rather than
applying a fixed algorithm.

=== Why Neural Compression Is Hard for Genomics

Learning-based compression faces the same tension in genomics that it faces
everywhere else in this book (Chapters 57–62): neural models can achieve
excellent compression ratios but are *slow* and *expensive* to run. A hospital
sequencing thousands of genomes per day cannot wait hours per sample for a
neural compressor. CRAM compresses a human genome in minutes on a standard
server; a neural approach may take hours even on GPU hardware.

There is also a *decompression asymmetry*: in production genomics, data is
compressed once and decompressed many times (every time a researcher runs an
analysis). A slow encoder is tolerable; a slow decoder is not. The classical
tools (CRAM, htslib) decompress in memory-mapped chunks that are I/O-bound, not
CPU-bound. Neural decoders are currently nowhere near this speed.

The honest assessment as of mid-2026: *neural and LLM-assisted genomic
compressors are research-level tools that win on benchmarks but are not yet
deployed in production genomics pipelines*. CRAM remains the workhorse.

#aside[
  The *Hecate* compressor (arXiv:2603.15390, 2026) takes a modular approach:
  it represents the genome as a sequence of annotated segments (coding regions,
  repetitive elements, highly conserved regions) and applies the best-matched
  compressor to each type. It is conceptually similar to how a video codec
  chooses between intra-frames and inter-frames depending on the content.
]

== Worked Example: Reference-Based Encoding by Hand

Let us trace through the reference-based encoding idea on a tiny example to
make the arithmetic concrete.

Suppose the reference genome (just a small portion) is:

```
REF: ACGTTTGCAAGTCCATGGATCCA
```

And our sequencer produces this read (20 bases):

```
READ: ACGTTTGCATGTCCATGG
```

*Step 1: Align.* The aligner finds that the read starts at position 0 of the
reference (a perfect match for positions 0–8), with one mismatch: position 9
is G in the read but A in the reference. Let us write out the alignment:

```
REF:  ACGTTTGCAAGTCCATGG
READ: ACGTTTGCATGTCCATGG
                ^ mismatch: A→G at offset 9
```

*Step 2: Encode the residual.* Instead of storing all 18 bases (at 2 bits
each = 36 bits raw, or about 4.5 bytes), CRAM stores:

- Position: 0 (or a delta from the previous read's position)
- Length: 18
- CIGAR: `18M` (18 matches/mismatches, no indels)
- NM (number of mismatches): 1
- MD string (mismatch details): `9A9`, meaning "9 matches, then reference
  had A, then 9 more matches"

The sequence itself is *not stored at all*: it is perfectly reconstructable
from the reference plus the MD string.

*Step 3: Count the savings.* The MD string `9A9` is 3 bytes. The position,
length, CIGAR, and flag fields add another ~15 bytes of metadata. Total: maybe
18 bytes to represent a read whose sequence takes 18 bytes (at 1 byte per base
in text). But in a real genome where reads have almost no mismatches, many
reads need *zero* MD string (just position and length). Quality scores are
stored separately, entropy-coded with context models.

*Step 4: What if there are insertions or deletions?* Suppose the read has one
inserted base (not in the reference):

```
REF:  ACGTTTGCAAGTCCATGG
READ: ACGTTTGCACAAGTCCATGG
                ^ insertion: C at offset 9
```

The CIGAR becomes `9M1I9M`: nine matches, one insertion, nine more matches.
The inserted base `C` is stored explicitly (it has no reference to subtract
against). This is slightly less compressible, but insertions and deletions are
rare in typical human germline sequencing.

#checkpoint[
  If a read of length 100 has zero mismatches and no insertions or deletions,
  how many bytes does CRAM need to store the sequence data for that read (not
  counting quality scores or metadata)?
][
  Zero bytes. If the read perfectly matches the reference at a known position,
  the sequence can be reconstructed entirely from the reference: CRAM stores
  only the position, length, and CIGAR string `100M`. The sequence itself is
  not stored at all.
]

== The Entropy of Genomic Sequences: How Much Can We Compress?

We have been compressing genomes empirically. What does information theory say
about how much is achievable?

#gomaths("Conditional entropy and the compression limit for DNA")[
  Recall from Chapter 18 that the _conditional entropy_ $H(X | Y)$ measures the
  average surprise left in $X$ once you already know $Y$, and that it can only
  shrink as you condition on more: $H(X | Y) <= H(X)$. For DNA we use this with
  $X$ = the next base and $Y$ = the preceding $k$ bases. We call the result the
  *order-$k$* entropy: order-0 conditions on nothing, order-1 on the previous
  base, and so on. Each higher order can only lower the bits-per-base floor.

  The entropy of a random DNA sequence over alphabet {A, C, G, T} with uniform
  distribution is $H = log_2 4 = 2$ bits per base. But real genomes are not
  uniform:
  - Global base frequencies deviate from 25% each (human: ~20.5% A, ~29.5% C,
    ~29.5% G, ~20.5% T).
  - Strong nearest-neighbor correlations: CpG dinucleotides are rare (the
    "CpG suppression" phenomenon).
  - Long-range repeats: transposable elements repeat hundreds of thousands of
    times.

  The *order-0 entropy* of a typical assembled human genome is about 1.97
  bits/base (barely below 2). The *order-1 conditional entropy* (conditioning
  on the previous base) is about 1.92 bits/base. The *order-12 conditional
  entropy* is around 1.5 bits/base.

  But this ignores repetitive structure. When you exploit long repeats
  (as LZ-style or repeat-model compressors do), you can reach 0.3–0.5
  bits/base on assembled genomes.

  For *unassembled reads* from a 30× sequencing run, the information content is
  actually much lower per base: you are storing the same genome 30 times over,
  so an ideal compressor would achieve roughly 1/30 of the assembled-genome
  cost. That is about 0.01 bits per base in theory. CRAM achieves roughly
  0.1 bits per base in practice, still a long way from the theoretical limit,
  with quality scores accounting for most of what remains.
]

#scoreboard(
  caption: "Genomic data: one 30× human WGS run (~90 GB of sequence data)",
  [Raw FASTQ], [~200 GB], [1.0×], [Uncompressed; one quality char per base],
  [fastq.gz (gzip)], [~60 GB], [3.3×], [gzip, knowing nothing about biology],
  [BAM (gzip inside)], [~90 GB], [2.2×], [Aligned; alignment metadata adds overhead vs. FASTQ.gz],
  [CRAM 3.0 (lossless Q)], [~30 GB], [6.7×], [Reference-based; lossless quality scores],
  [CRAM 3.1 (lossless Q)], [~26 GB], [7.7×], [rANS/range backends; +7–15% over CRAM 3.0],
  [CRAM 3.1 (8-bin Q)], [~20 GB], [10×], [Quality scores binned to 8 levels (near-lossless)],
  [DRAGEN ORA], [~33 GB FASTQ→], [6×], [From raw FASTQ; no alignment required; lossless],
)

== A Python Sketch: Reference Subtraction and Delta Coding

CRAM's full implementation is thousands of lines of C in the `htslib` library.
But the core idea (subtract the reference, encode the residual) fits in a
handful of Python lines. The following sketch illustrates the concept without
implementing a real SAM/BAM parser.

#gopython("Python bytes and string slicing")[
  In Python, a `bytes` object is an immutable sequence of integers 0–255.
  You can slice it with `[start:stop]` just like a list. String objects work
  the same way. This is all we need for reference subtraction:

  ```python
  ref = b"ACGTTTGCAAGTCCATGG"
  read = b"ACGTTTGCATGTCCATGG"

  # Find where they differ
  mismatches = [
      (i, chr(ref[i]), chr(read[i]))
      for i in range(len(ref))
      if ref[i] != read[i]
  ]
  print(mismatches)  # [(9, 'A', 'T')]
  ```
]

#gopython("Dataclasses: a struct without the boilerplate")[
  A *class* groups related values (and the functions that act on them) under one
  name. For data that is mostly a labelled bundle of fields, Python's
  `@dataclass` decorator (from the standard `dataclasses` module) writes the
  tedious parts for you: it auto-generates the constructor, a readable
  `repr`, and equality, from nothing but the field names and their type hints.
  The `@` line is a *decorator*: a function that takes the class below it and
  returns an enhanced version of it.

  ```python
  from dataclasses import dataclass

  @dataclass
  class Point:
      x: int
      y: int

  p = Point(3, 4)      # constructor is free
  print(p)             # Point(x=3, y=4)  - repr is free
  print(p.x + p.y)     # 7 - access fields by name
  print(p == Point(3, 4))  # True - equality is free
  ```

  Without `@dataclass` you would hand-write an `__init__`, an `__eq__`, and a
  `__repr__`. That is about a dozen lines of boilerplate for the same result. We use a
  dataclass below to hold one aligned read's fields (position, mismatches,
  quality bytes) as a tidy record.
]

```python
from dataclasses import dataclass

@dataclass
class AlignedRead:
    """A sequencing read aligned to a reference genome."""
    chrom:    str         # chromosome name, e.g. "chr3"
    pos:      int         # 0-based start position in the reference
    length:   int         # read length in bases
    mismatches: list[tuple[int, int, int]]  # (offset, ref_base, read_base)
    insertions: list[tuple[int, bytes]]     # (offset, inserted_bytes)
    deletions:  list[tuple[int, int]]       # (offset, deleted_length)
    qual:     bytes       # quality score bytes (one per base)

def encode_read(ref: bytes, read: bytes, qual: bytes,
                chrom: str, pos: int) -> AlignedRead:
    """
    Compute the difference between `read` and `ref[pos:pos+len(read)]`.
    Returns an AlignedRead storing only the residual.
    Assumes no insertions or deletions (CIGAR = all-M) for simplicity.
    """
    ref_slice = ref[pos : pos + len(read)]
    mismatches = [
        (i, ref_slice[i], read[i])
        for i in range(len(read))
        if i < len(ref_slice) and ref_slice[i] != read[i]
    ]
    return AlignedRead(
        chrom=chrom, pos=pos, length=len(read),
        mismatches=mismatches, insertions=[], deletions=[],
        qual=qual,
    )

def decode_read(ref: bytes, record: AlignedRead) -> bytes:
    """Reconstruct the read from the reference plus the residual."""
    result = bytearray(ref[record.pos : record.pos + record.length])
    for (offset, _ref_base, read_base) in record.mismatches:
        result[offset] = read_base
    return bytes(result)

# Self-test
if __name__ == "__main__":
    reference = b"ACGTTTGCAAGTCCATGGGATCCA"
    read_seq  = b"ACGTTTGCATGTCCATGG"
    qual_str  = b"IIIIIIIIIIIIIIIIII"  # all Q=40

    record = encode_read(reference, read_seq, qual_str, chrom="chr1", pos=0)
    recovered = decode_read(reference, record)
    assert recovered == read_seq, f"Round-trip failed: {recovered!r} != {read_seq!r}"

    print(f"Original read:  {len(read_seq)} bytes")
    print(f"Mismatches:     {record.mismatches}")
    print(f"Residual size:  ~{len(record.mismatches) * 3} bytes (3 ints per mismatch)")
    print("Round-trip: OK")
```

Run this and you will see: the 18-base read reduces to a single mismatch record
of 3 integers. In a real CRAM encoder, these records are then delta-coded
(positions relative to the previous read), packed, and entropy-coded. The
quality scores in `qual` are handled separately by the quality-score data
series, with optional binning and context modeling.

== CRAM vs. BAM: When Does It Matter?

For the practicing bioinformatician, the question is not "how does CRAM work?"
but "should I use CRAM?"

The answer depends on the use case:

#fig(
  [Decision diagram: BAM vs. CRAM for different use cases.],
  cetz.canvas({
    import cetz.draw: *
    // Simple decision boxes
    let bw = 3.2
    let bh = 0.65
    rect((0, 3.5), (bw, 3.5 + bh), fill: rgb("#eef4fb"), stroke: 0.8pt + rgb("#0b5394"))
    content((bw / 2, 3.5 + bh / 2), box(width: 2.8cm, inset: 2pt, align(center, text(size: 8pt)[Do you have the reference?])))

    // Yes branch
    line((bw / 2, 3.5), (bw / 2, 2.8), mark: (end: ">"), stroke: 0.8pt)
    content((bw / 2 + 0.3, 3.15), text(size: 7.5pt)[Yes])
    rect((0, 2.1), (bw, 2.8), fill: rgb("#eef4fb"), stroke: 0.8pt + rgb("#0b5394"))
    content((bw / 2, 2.45), box(width: 2.8cm, inset: 2pt, align(center, text(size: 8pt)[Is speed more important than size?])))

    // Yes → BAM
    line((bw, 2.45), (bw + 0.6, 2.45), mark: (end: ">"), stroke: 0.8pt)
    content((bw + 0.25, 2.65), text(size: 7.5pt)[Yes])
    rect((bw + 0.6, 2.1), (bw + 0.6 + 1.6, 2.8), fill: rgb("#d4e8d4"), stroke: 0.8pt + rgb("#0b6e4f"))
    content((bw + 0.6 + 0.8, 2.45), box(width: 1.3cm, inset: 2pt, align(center, text(size: 8pt)[*Use BAM*])))

    // No → CRAM
    line((bw / 2, 2.1), (bw / 2, 1.4), mark: (end: ">"), stroke: 0.8pt)
    content((bw / 2 + 0.3, 1.75), text(size: 7.5pt)[No])
    rect((0, 0.7), (bw, 1.4), fill: rgb("#d4e8d4"), stroke: 0.8pt + rgb("#0b6e4f"))
    content((bw / 2, 1.05), box(width: 2.8cm, inset: 2pt, align(center, text(size: 7.5pt)[*Use CRAM 3.1*\ (lossless or 8-bin lossy)])))

    // No ref → reference-free
    line((0, 3.5 + bh / 2), (-0.6, 3.5 + bh / 2), mark: (end: ">"), stroke: 0.8pt)
    content((-0.3, 3.5 + bh / 2 + 0.2), text(size: 7.5pt)[No])
    rect((-2.2, 3.2), (-0.6, 3.9), fill: rgb("#fbf7ef"), stroke: 0.8pt + rgb("#783f04"))
    content((-1.4, 3.55), box(width: 1.4cm, inset: 2pt, align(center, text(size: 7.5pt)[JARVIS3\ or gzip])))
  })
)

The community consensus as of 2026:

- *Active analysis pipelines* that re-read data constantly: BAM is fine. The
  random-access overhead of CRAM's slice structure adds latency.
- *Long-term archival storage*: CRAM is strongly preferred. The GA4GH recommends
  CRAM 3.1 as the archival standard for all new sequencing projects.
- *Data sharing and publication*: CRAM, because the space savings reduce
  transfer times enormously.
- *Clinical genomics* (where data must be retained for decades): CRAM with
  *lossless* quality scores, even if it costs more space, because the legal and
  medical implications of discarding precision are serious.

== The Broader Picture: Compression as Infrastructure for Science

Genomics is the most extreme example of a pattern we have seen throughout
Volume V: when you *understand your data deeply*, you can compress it far beyond
what any general-purpose tool achieves. The sequence data format (FASTA/FASTQ),
the alignment format (SAM/BAM), and the compressed format (CRAM) evolved
together over 20 years as the bioinformatics community understood the data
better and better.

The pattern is always the same:
1. *What varies?* Not the whole sequence. Mostly just the mismatches and indels.
2. *What is the dominant cost?* Not the bases, which compress to almost nothing.
   It is the quality scores, which are noisy and resist compression.
3. *What is acceptable to lose?* For most analyses, full 42-level quality
   precision is unnecessary. Eight bins suffice.
4. *What infrastructure enables step 1?* The BWT/FM-index, which makes
   alignment fast enough to be practical.

This four-step reasoning recurs in every domain-specific compressor: in video
(Chapter 52, where the "what varies" is between-frame motion), in scientific
floats (Chapter 66, where "what is acceptable to lose" is controlled by the
user's error bound), in database columns (Chapter 67, where the "dominant cost"
is low-cardinality string columns). Genomics is unique only in how extreme the
ratios are, because the "what varies" is only 0.1%.

#history[
  The *Human Genome Project*, completed in 2003, produced a reference genome
  for the first time. That reference genome (the text that every CRAM file is
  compressed against) was assembled from DNA donated by a small number of
  individuals, and it took a decade of work by hundreds of laboratories to
  produce. Today a single sequencing run takes hours and costs $300–$1000.
  The reference genome changed compression from impossible to trivial, in the
  same way that a shared context dictionary makes LZW trivial for text that
  uses the same vocabulary.

  The *CRAM* format was developed by Markus Hsi-Yang Fritz and colleagues at
  the Sanger Institute in 2011. Its standardization by the *GA4GH* in 2014
  (version 2.0) and the subsequent 3.0 (2017) and 3.1 (2022) releases have
  made it the de facto archive format for human sequencing data worldwide. As
  of 2024, the major public genome repositories (the European Nucleotide
  Archive (ENA), NCBI's Sequence Read Archive (SRA), and the UK Biobank) all
  store data in CRAM.
]

#keyidea[
  *Reference-based compression works because human genomes are 99.9% identical*.
  The BWT/FM-index makes alignment fast. Quality scores are the bottleneck and
  admit lossy compression with minimal scientific impact. CRAM is the deployed
  standard. The frontier is neural and LLM-assisted compressors, which win on
  benchmarks but are not yet production-ready.
]

#takeaways((
  "Genomic data pipelines flow: FASTQ (raw reads) → BAM (aligned) → CRAM (compressed), with the BWT/FM-index aligner as the critical middle step.",
  "Reference-based compression stores only the differences between each read and the reference genome; since human genomes differ by only 0.1%, the residual is tiny.",
  "CRAM separates data into independent series (positions, mismatches, quality scores, metadata) and entropy-codes each with the best-matched coder (rANS, range coder, or gzip).",
  "Quality scores dominate the file size because they are noisy and resist compression; lossy binning to 8 levels (as in CRAM's optional lossy mode) trades precision for space.",
  "The Burrows-Wheeler Transform / FM-index from Chapter 35 reappears here as the engine of fast alignment, not compression. The same mathematical structure serves multiple purposes.",
  "Reference-free compressors (JARVIS3, 2024) use context mixing and repeat models to compress assembled genomes below 0.5 bits/base without needing an external reference.",
  "Neural and LLM-assisted genomic compressors (AgentGC, 2026) are improving rapidly but remain research tools; CRAM is the production workhorse.",
))

== Exercises

#exercise("69.1", 1)[
  A FASTQ file stores the four letters A, C, G, T. If they were equally
  frequent, what would be the minimum bits per base required by a perfect
  compressor (Chapter 18)? Typical human genomic data has roughly 20.5% A,
  29.5% C, 29.5% G, 20.5% T. Using the Huffman lower bound, does the
  base-frequency distribution give significant compression over the uniform
  case?
]
#solution("69.1")[
  The entropy of a uniform 4-symbol source is $H = log_2 4 = 2$ bits/base.
  For the human base distribution, $H = -(2 times 0.205 log_2 0.205 + 2 times 0.295 log_2 0.295) approx -(2 times 0.205 times (-2.29) + 2 times 0.295 times (-1.76)) approx 1.999$ bits/base.
  The distribution is nearly uniform (AT- and GC-pairs are nearly equal in frequency), so frequency coding gives essentially no improvement over the uniform 2 bits/base. Real genomic compression works by exploiting *repetition* (long-range structure and reference similarity), not base-frequency skew.
]

#exercise("69.2", 2)[
  A FASTQ quality string uses Phred scores $Q = -10 log_10 p$. A base has
  $Q = 30$. (a) What is the probability $p$ that this base is wrong? (b) If
  you bin all Q scores 28–32 to Q = 30, what is the maximum error you
  introduce in the estimated error probability? (c) Why do genomics tools
  accept this error?
]
#solution("69.2")[
  (a) $Q = 30 => p = 10^(-30/10) = 10^(-3) = 0.001$ (1 in 1000 chance of error).
  (b) Q = 28: $p = 10^(-2.8) approx 0.00158$. Q = 32: $p = 10^(-3.2) approx 0.00063$. The true probability can be off by a factor of ~2.5 if we record Q=30 for a base that was actually Q=28 or Q=32. (c) Variant callers (like GATK) use quality scores as weights in a log-likelihood model. Tests show that 8-bin quality discretization changes variant calls at a rate below clinical significance. The extra precision beyond 8 levels is measuring noise, not signal.
]

#exercise("69.3", 2)[
  In CRAM reference-based compression, a read of length 100 is stored as
  position + length + CIGAR + a list of mismatches. Suppose the mismatch rate
  is 0.3% (human germline average). On average, how many mismatches do you
  expect per 100-base read? If each mismatch record costs 3 bytes (offset +
  reference base + read base), and the fixed overhead per read is 16 bytes,
  how many bytes does CRAM use per read on average, ignoring quality scores?
  Compare to storing the read as raw text (100 bytes).
]
#solution("69.3")[
  Expected mismatches per read: $0.003 times 100 = 0.3$ on average (we just multiply the per-base error probability by the 100 bases, using expectation as a weighted average from Chapter 10). Since each base is "correct" with probability $0.997$ and there are 100 of them, the chance a read has *zero* mismatches is $0.997^(100) approx 0.74$, so about three-quarters of reads need no mismatch record at all. Average mismatch storage: $0.3 times 3 = 0.9$ bytes. Total per read: $16 + 0.9 approx 17$ bytes. Compared to 100 bytes raw text, this is a *5.9× compression* before any entropy coding, and before quality scores.
]

#exercise("69.4", 2)[
  Explain in your own words why the Burrows–Wheeler Transform, introduced in
  Chapter 35 as a compression aid, turns out to be useful in genomics for
  something completely different. What property of the BWT (and the FM-index
  built on it) makes it useful for DNA alignment?
]
#solution("69.4")[
  In Chapter 35 the BWT was a way to *rearrange* a string so that identical characters cluster, helping entropy coders. The FM-index built on the BWT has a different property: it allows *backward search*, finding all occurrences of a short pattern in a long text in time proportional only to the pattern length, not the text length. This means you can find where a 150-base sequencing read matches within a 3.2-billion-base genome in roughly 150 steps, using an index that stores the compressed genome. The key is the LF-mapping (the relationship between the first and last columns of the sorted rotations), which supports step-by-step backward induction through the text without decompressing it.
]

#exercise("69.5", 3)[
  The DRAGEN ORA format claims ~5–6× compression of FASTQ files (compared to
  1× for uncompressed FASTQ, or ~3× for fastq.gz) using reference-based
  alignment internally. But CRAM 3.1 achieves ~7.7× over uncompressed FASTQ
  for lossless quality scores, starting from an already-aligned BAM file.
  Explain why these two numbers are not directly comparable. What would you
  need to know to make a fair comparison?
]
#solution("69.5")[
  They are measuring different starting points and doing different things:
  (1) ORA compresses FASTQ directly (before alignment), while CRAM compresses BAM (after alignment). The alignment step itself (which requires CPU time and the reference genome) is "inside" ORA and "outside" CRAM.
  (2) ORA's 5–6× is measured over *uncompressed* FASTQ; CRAM's 7.7× is also over uncompressed FASTQ but starting from aligned BAM.
  (3) The alignment stored in BAM adds overhead (CIGAR strings, flags, etc.) that inflates BAM relative to FASTQ, so CRAM's efficiency partly comes from replacing that overhead with the reference.
  A fair comparison would measure: starting from identical raw FASTQ, total compressed size on disk after applying each tool, including any intermediate files. On that basis, CRAM 3.1 and ORA are broadly competitive, both achieving ~6–10× depending on quality-score treatment.
]

#exercise("69.6", 3)[
  Write a Python function `quality_entropy(qual: bytes) -> float` that
  computes the order-0 Shannon entropy of a quality-score string (as a
  `bytes` object, where each byte is the ASCII-encoded quality score). Then
  apply it to the synthetic quality strings `b"IIIIIIIIII"` (all Q=40) and
  `b"5?ABCDI987"` (varying scores). Explain why the entropy of the varying
  string is higher, and what this implies for compression.
]
#solution("69.6")[
  (`Counter`, from Chapter 16, tallies how many times each value appears,
  handing us a ready-made histogram to turn into probabilities.)
  ```python
  import math
  from collections import Counter

  def quality_entropy(qual: bytes) -> float:
      counts = Counter(qual)
      n = len(qual)
      return -sum(
          (c / n) * math.log2(c / n)
          for c in counts.values()
          if c > 0
      )

  s1 = b"IIIIIIIIII"         # all Q=40 (ASCII 73)
  s2 = b"5?ABCDI987"         # varying

  print(f"Entropy of all-same: {quality_entropy(s1):.3f} bits/char")
  print(f"Entropy of varying:  {quality_entropy(s2):.3f} bits/char")
  ```
  All-same: entropy = 0.0 bits/char (one symbol, completely predictable, so a
  perfect compressor stores zero bits per character). Varying: each distinct
  ASCII character appears once in a 10-char string, so all probabilities are
  1/10, entropy = $log_2 10 approx 3.32$ bits/char. Higher entropy means the
  varying string is harder to compress. Real quality strings fall between these
  extremes, which is why quality scores are the dominant cost in CRAM files.
]

== Further Reading

- *Fritz, M. H.-Y. et al. (2011).* "Efficient storage of high throughput DNA sequencing data using reference-based compression." #link("https://genome.cshlp.org/content/21/5/734")[_Genome Research_ 21(5):734–740.] The original CRAM paper.

- *GA4GH CRAM specification and myths.* #link("https://www.ga4gh.org/news/guest-post-seven-myths-about-cram-the-community-standard-for-genomic-data-compression/")[Seven myths about CRAM] (GA4GH guest post). An overview of common misunderstandings.

- *Illumina ORA white paper.* #link("https://www.illumina.com/science/genomics-research/articles/design-ora-lossless-genomic-compression.html")["Design considerations and methodology of .ORA format."] The productized reference-based FASTQ compressor.

- *Langmead, B. & Salzberg, S. (2012).* "Fast gapped-read alignment with Bowtie 2." #link("https://www.nature.com/articles/nmeth.1923")[_Nature Methods_ 9:357–359.] The FM-index-based aligner behind most short-read pipelines.

- *Li, H. & Durbin, R. (2009).* "Fast and accurate short read alignment with Burrows-Wheeler Aligner." #link("https://academic.oup.com/bioinformatics/article/25/14/1754/225615")[_Bioinformatics_ 25(14):1754–1760.] The BWA aligner, companion to Bowtie.

- *Pratas, D., Hosseini, M. & Pinho, A. J. (2024).* "JARVIS3: An efficient encoder for genomic data." #link("https://academic.oup.com/bioinformatics/article/40/12/btae725/7914925")[_Bioinformatics_ 40(12):btae725.] The state-of-the-art reference-free compressor.

- *AgentGC (2026).* "Evolutionary Learning-based Lossless Compression for Genomics Data with LLM-driven Multiple Agent." #link("https://arxiv.org/abs/2601.13559")[arXiv:2601.13559.] LLM-orchestrated genomic compression.

- *Hecate (2026).* "A Modular Genomic Compressor." #link("https://arxiv.org/abs/2603.15390")[arXiv:2603.15390.] Modular approach with per-segment codec selection.

#bridge[
  We have just seen how reference-based compression works when the reference
  is *another organism of the same species*, something you can store once and
  reuse forever. Chapter 70 pushes this idea even further: what if you want to
  store data *in* DNA itself, not just compress data *about* DNA? DNA data
  storage encodes arbitrary binary data as sequences of A, C, G, T, and the
  encoding constraints (avoiding long runs, maintaining balanced GC content,
  correcting synthesis and sequencing errors) look remarkably like the
  constrained-coding and error-correction problems we will see in Chapter 72.
  The same four-letter alphabet that encodes life turns out to be a compelling
  medium for archival data storage, with a theoretical density of around
  $10^(18)$ bytes per cubic centimetre.
]
