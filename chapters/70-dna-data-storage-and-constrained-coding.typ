#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= DNA Data Storage and Constrained Coding

#epigraph[
  Nature has been storing information in DNA for four billion years.
  We are only now learning to read _and write_ the file format.
][Yaniv Erlich, 2017]

Picture a teaspoon of clear liquid sitting on your desk. Inside it, dissolved and invisible,
floats enough synthetic DNA to hold all the data humanity has ever created — every book,
every film, every photograph, every database — with room to spare. That is not a science
fiction premise. It is a number that researchers have calculated from the known physical
chemistry of DNA molecules, and it sits very close to the theoretical maximum that Shannon's
laws of information theory allow.

The punchline: we already know how to get there. The technique is called DNA Fountain, it
was published in _Science_ in March 2017 by Yaniv Erlich and Dina Zielinski at Columbia
University and the New York Genome Center, and it achieves a storage density of roughly
215 petabytes per gram — about six orders of magnitude denser than the best flash memory.

But storing data in molecules is not simply "write bytes into bases." The DNA channel has
quirks that no hard disk or fibre-optic cable has ever had: it hates long runs of the same
base; it needs a balanced ratio of certain chemical pairs; it can lose entire molecules
during synthesis; and reading it back requires a biological sequencing machine that
introduces its own random errors. Making this work reliably requires an elegant combination
of two ideas from very different parts of the compression world — *constrained coding* (the
art of mapping arbitrary bits into sequences that obey physical rules) and *fountain codes*
(a kind of rateless error-correction that lets you recover data even when random pieces
go missing). Together they turn an unpredictable chemical soup into a perfectly reliable
archive.

This chapter is the payoff of a long journey. In Chapter 20 we studied channels and their
capacity — the maximum reliable throughput through any noisy medium. In Chapters 24–26 we
built the entropy coders that squeeze data toward Shannon's theoretical floor. Chapter 69
showed how biology drives compression in the read direction, compressing sequencing data
against a reference genome. Now we flip the question: how do we *write* arbitrary digital
data _into_ a living molecule, reliably, efficiently, and in a way that can be retrieved
years later with zero errors?

#recap[
  Chapter 18 established Shannon entropy and the source-coding theorem. Chapter 20 extended
  this to channels with noise, defining channel capacity $C$ as the maximum rate at which
  information can flow through a noisy medium with arbitrarily small error. Chapter 26 built
  the arithmetic coder that approaches the entropy limit from the source side. Chapter 69
  introduced the DNA sequencing data problem (CRAM, reference-based compression). This
  chapter uses all of that: the channel capacity framework to bound what DNA storage can
  achieve, the constrained-coding lens to meet the biochemical rules, and fountain codes as
  a practical near-capacity erasure corrector.
]

#objectives((
  [Describe the four biochemical constraints of the DNA storage channel and explain why each one matters.],
  [Define a constrained code and calculate its capacity using a finite-state graph.],
  [Explain the fountain-code (LT/Raptor) idea and why it suits the DNA channel perfectly.],
  [Trace the DNA Fountain encoding pipeline from raw bytes to synthesised oligonucleotides.],
  [State the information-density record achieved by DNA Fountain and compare it to the Shannon limit.],
  [Describe the current state of the art in commercial DNA storage as of mid-2026.],
))

== Why DNA at All?

Before diving into the coding theory, it is worth pausing to ask why anyone would bother.
Hard drives are cheap. Tape is cheaper. Flash memory is fast. Why encode data in a molecule
that costs dollars per base to write and days to read?

The answer is a combination of density and longevity that no manufactured material comes
close to matching.

*Density.* A single gram of double-stranded DNA can hold, in principle, about $10^(21)$
bits — roughly $10^9$ terabytes, or a million petabytes. Flash memory in 2025 achieves
roughly 10 terabytes per cubic centimetre of silicon. The same cubic centimetre of dry DNA
could hold on the order of $10^(15)$ terabytes. The advantage is not a factor of two or
ten; it is a factor of roughly one hundred million.

*Longevity.* Magnetic hard drives have a rated lifetime of three to five years under
continuous use, and perhaps twenty to thirty years in cold storage. Tape can last fifty
years in controlled conditions. DNA, under the right conditions — cool, dark, and dry — is
stable for hundreds of thousands of years. Researchers have successfully sequenced DNA from
woolly mammoths that died over 40,000 years ago. In 2021, scientists recovered and decoded
DNA fragments from 1.2-million-year-old mammoth teeth found in Siberian permafrost. No
data centre can match that.

*Energy.* Magnetic storage must be powered continuously to prevent data decay and drive
failure. DNA in a sealed vial at room temperature is essentially passive — no electricity
required. For the hundreds of exabytes of "cold" archival data that humanity accumulates
(video archives, genomic databases, regulatory records that must be kept for decades) but
rarely accesses, this is economically significant.

The catch, as always, is cost and speed. In 2025, synthesising a single DNA base (a
nucleotide) costs on the order of a fraction of a cent at scale (Twist Bioscience quotes
USD 0.007 per base for bulk oligonucleotide synthesis), but reading and writing a megabyte of
data still takes hours and costs far more than equivalent flash storage. The technology is
squarely in the "promising but expensive" zone — which is exactly where hard drives were
in the 1950s, and where flash memory was in the 1990s.

#history[
  *The milestones so far.* The first demonstration of digital data storage in DNA came in
  2012, when George Church, Yuan Gao, and Sriram Kosuri at Harvard Medical School encoded
  a 5.27-megabit book (_Regenesis_ by Church and Ed Regis) into 55,000 short DNA strands
  and read it back correctly. Their paper in _Science_ (August 2012) used a simple encoding:
  each two-bit value (00, 01, 10, 11) mapped to one of three nucleotide letters, deliberately
  avoiding the fourth (T) to limit homopolymer runs — a crude but effective constrained code.
  In 2013, Nick Goldman and colleagues at the EMBL-EBI encoded 739 kilobytes (including an
  MP3 of Martin Luther King's "I Have a Dream" speech) using a more sophisticated scheme that
  spread each byte redundantly across multiple oligos for error tolerance. Erlich and
  Zielinski's DNA Fountain (2017) shattered the efficiency record, encoding 2.14 megabytes
  at 1.55 bits per nucleotide — 85% of the theoretical Shannon channel capacity. In 2019,
  researchers at the University of Washington and Microsoft stored 200 megabytes and read
  it back automatically using a nanopore sequencer. By 2024, the DNA Data Storage Alliance
  (Catalog Technologies, Quantum, Twist Bioscience, Western Digital) released its first
  interoperability specifications, signalling that the industry considers the technology
  pre-commercial.
]

== The DNA Alphabet and the Channel

To understand why constrained coding is necessary, you need a one-paragraph primer on what
DNA actually is.

DNA is a polymer — a long chain molecule made of repeating units called *nucleotides*.
There are four possible nucleotides, conventionally abbreviated by their nitrogen bases:
*A* (adenine), *T* (thymine), *G* (guanine), and *C* (cytosine). Each position in the
chain holds exactly one of these four letters. A strand of length $n$ nucleotides therefore
belongs to an alphabet of size 4, and in an ideal noiseless world could carry exactly
$log_2 4 = 2$ bits of information per position.

Double-stranded DNA (the famous double helix) pairs A with T and G with C — A always bonds
to T, and G always bonds to C. This pairing rule has a critical consequence for storage: it
defines what is called the *GC content* of a strand, the fraction of bases that are G or C
(equivalently, the fraction that are A or T is the AT content). A healthy synthetic DNA
strand for storage purposes needs GC content between about 40% and 60%.

#definition("Oligonucleotide (oligo)")[
  A short, single-stranded synthetic DNA molecule. In data storage applications, oligos are
  typically 100–200 nucleotides long. Each oligo is one "word" in the data; collectively
  a pool of oligos encodes the whole file. The word comes from Greek _oligos_ (few) +
  _nucleotide_.
]

#gomaths("Logarithms base 2 — a quick reminder")[
  You met logarithms in Chapter 7. The base-2 logarithm $log_2 n$ answers the question:
  "To what power must I raise 2 to get $n$?" So $log_2 4 = 2$ because $2^2 = 4$. This is
  exactly the number of bits needed to represent $n$ equally likely choices: with 4 choices
  (A, T, G, C), each base carries $log_2 4 = 2$ bits. The Shannon capacity of a noiseless
  channel with a 4-letter alphabet is 2 bits per symbol.
]

=== The Four Constraints

In practice, a synthesised oligo does not behave like an ideal 4-symbol channel. Four
biochemical facts impose hard constraints on which sequences can reliably be written and
read back.

*Constraint 1: No long homopolymer runs.* A *homopolymer run* is a stretch of repeated
identical bases: `AAAAAAA`, `GCCCCC`, and so on. Long runs (typically five or more of the
same base in a row) cause synthesis machines to "stutter" — making errors at high frequency
— and cause sequencing machines to miscount the length of the run. The fix is to forbid
runs beyond a maximum length $r$ (commonly $r = 3$ or $r = 4$).

*Constraint 2: Balanced GC content.* Sequences with very high GC content (say, 70%+)
form abnormally strong inter-strand bonds and are difficult to melt apart for reading.
Sequences with very low GC content (say, 20%) are structurally fragile and prone to
secondary structure formation (hairpins). The practical sweet spot is 40%–60% GC content
per oligo.

*Constraint 3: No internal repetitive structure.* Certain repeated motifs inside an oligo
cause the molecule to fold back on itself (hairpin loops) or to stick to other oligos
(cross-hybridisation), making retrieval unreliable. This is harder to quantify but is
usually handled by including it in the synthesis quality score.

*Constraint 4: Index/barcode regions.* Each oligo must include a few bases at each end
that serve as a barcode — identifying which oligo is which when the pool is sequenced back.
These bases are not free data; they are overhead. Typical addressing overhead is 20–30
nucleotides per oligo out of a total of 120–200.

Together, constraints 1 and 2 define the core constrained-coding problem: map arbitrary
bits into DNA sequences over the alphabet {A, T, G, C} such that no run exceeds length $r$
and GC content stays between $p_("min")$ and $p_("max")$.

#keyidea[
  The constraints are NOT optional. A sequence that violates them will produce synthesis
  errors, sequencing errors, or both, and your data will not be recoverable. Constrained
  coding is the layer that makes DNA a reliable storage medium rather than a biochemical
  soup of mistakes.
]

#checkpoint[Why does GC content between 40% and 60% matter? What goes wrong if a sequence
is 90% GC?][A 90% GC sequence has very strong inter-strand hydrogen bonding — G-C pairs form
three hydrogen bonds, while A-T pairs form only two. This makes the two strands hard to
separate (high melting temperature), which is required for both synthesis and sequencing.
In extreme cases the strand forms internal structures that block the synthesis machinery
entirely.]

== Constrained Coding Theory

Constrained coding is one of the oldest problems in digital communications, predating
modern computers. Magnetic hard drives face the same issue: the magnetic head needs certain
bit patterns to maintain clock synchronisation, so raw data is mapped into a "run-length
limited" (RLL) code before writing. Audio CDs use EFM (Eight-to-Fourteen Modulation)
for the same reason. The theory that handles all these cases was developed in the 1950s
through 1980s and is built around finite-state machines and their capacities.

=== Finite-State Graphs and Capacity

Think of the constraints as a set of rules about which bases are allowed to follow which
others. We can represent these rules as a *directed graph* (also called a *labeled graph*
or *de Bruijn graph*) where:

- Each *node* represents a state — the recent history of output bases that matters for the
  constraint.
- Each *directed edge* (arrow) represents a valid next base.
- An edge is labelled with the base it contributes.

A valid sequence is any path through this graph. The capacity of the constrained code is
the maximum rate (in bits per nucleotide) at which information can flow through such a
sequence.

#gomaths("Spectral radius and Perron-Frobenius")[
  The capacity of a constrained code is computed from the *adjacency matrix* of its graph:
  a matrix $A$ where entry $A_(i j)$ is 1 if there is a valid transition from state $i$ to
  state $j$, and 0 otherwise. The capacity is:

  $ C = log_2 lambda_max $

  where $lambda_max$ is the *largest eigenvalue* (Perron-Frobenius eigenvalue) of $A$.
  This result was proved by Shannon in 1948. For a completely unconstrained 4-symbol alphabet,
  $A$ is a $4 times 4$ all-ones matrix (every transition allowed), its largest eigenvalue
  is 4, and $C = log_2 4 = 2$ bits/symbol — as expected.

  You do not need to know how to compute eigenvalues from scratch to follow the chapter.
  The key intuition is: constraints reduce the number of paths through the graph, which
  reduces the effective branching factor, which reduces $log_2(lambda_max)$ below 2.
  How far below 2 the capacity falls measures the "cost" of the constraints.
]

Let us work through the simplest interesting case: a run-length constraint of 1 over a
binary alphabet (no two identical bits in a row). The states are "last bit was 0" and
"last bit was 1". The adjacency matrix is:

$ A = mat(0, 1; 1, 0) $

The eigenvalues of this matrix are $+1$ and $-1$. The Perron-Frobenius eigenvalue (the
largest positive one) is $lambda_max = 1$. Capacity $= log_2 1 = 0$ bits/symbol. That
makes sense: the only valid sequences are `010101...` and `101010...` — exactly one bit of
choice at the start, and then no choice at all. This extreme constraint eliminates almost
all information.

Let us do one case where the answer is _not_ zero, so the machinery earns its keep. Loosen
the rule to "no run of length 3 or more" over the binary alphabet — at most two identical
symbols in a row, exactly the constraint drawn in the figure below. A compact way to count
the valid strings is to ask: how many length-$n$ binary strings avoid `000` and `111`? Call
that count $T_n$. A short argument (a valid string of length $n$ ends in either a single
fresh symbol or a doubled one, appended to a shorter valid string) gives the recurrence
$T_n = T_(n-1) + T_(n-2)$ — each term is the sum of the previous two, which is the famous
_Fibonacci recurrence_ (the sequence $1, 1, 2, 3, 5, 8, 13, dots$, where the counting tools of
Chapter 8 and the sequences of Chapter 11 meet). A standard fact about this recurrence is
that its terms grow like $phi^n$, where $phi = (1 + sqrt(5))\/2 approx 1.618$ is the
_golden ratio_ — and that growth rate $phi$ is precisely the Perron-Frobenius eigenvalue of
this constraint's adjacency matrix. The capacity is

$ C = log_2 phi approx log_2 1.618 approx 0.694 "bits/symbol", $

noticeably below the unconstrained 1 bit/symbol but far from the zero we got with the harsher
rule. (Sharpen the rule back to "at most run 2" with a different bookkeeping and you get the
$approx 0.946$ figure quoted in Exercise 70.2; the exact number depends on precisely which
runs you forbid, but the _method_ — count the paths, take $log_2$ of the growth rate — is
always the same.) This is the whole game of constrained-coding capacity in one line: *the
capacity is the base-2 logarithm of the rate at which the number of valid sequences grows.*

For the DNA case, the constraint is softer. With a maximum run length of $r = 3$ over the
4-symbol DNA alphabet (no run of four or more), and approximate GC balance, the constrained
capacity works out to roughly 1.98 bits/nucleotide — astonishingly close to the unconstrained
maximum of 2.00. This means the constraints cost almost nothing in theory; the hard part is
building a practical code that achieves this theoretical limit.

#fig([The finite-state graph for the no-more-than-2-consecutive-same-base constraint over a
2-symbol alphabet {0,1}. States track how many consecutive identical symbols have appeared.
State A: just switched (1 same so far), State B: 2 in a row (max allowed). From B, you
must switch.],
cetz.canvas({
  import cetz.draw: *
  // States
  circle((1, 2), radius: 0.5, stroke: rgb("#0b5394"), fill: rgb("#e8f0f8"), name: "start")
  circle((4, 3), radius: 0.5, stroke: rgb("#0b5394"), fill: rgb("#e8f0f8"), name: "a1")
  circle((7, 3), radius: 0.5, stroke: rgb("#0f766e"), fill: rgb("#e8f5f2"), name: "a2")
  circle((4, 1), radius: 0.5, stroke: rgb("#0b5394"), fill: rgb("#e8f0f8"), name: "b1")
  circle((7, 1), radius: 0.5, stroke: rgb("#0f766e"), fill: rgb("#e8f5f2"), name: "b2")
  // Labels
  content((1, 2))[*S*]
  content((4, 3))[*A1*]
  content((7, 3))[*A2*]
  content((4, 1))[*B1*]
  content((7, 1))[*B2*]
  // Captions
  content((4, 3.8), text(size: 7pt)["1 in row"])
  content((7, 3.8), text(size: 7pt)["2 in row (max)"])
  content((4, 0.3), text(size: 7pt)["1 in row"])
  content((7, 0.3), text(size: 7pt)["2 in row (max)"])
  // Transitions from start
  line((1.4, 2.2), (3.5, 2.9), mark: (end: ">"), stroke: rgb("#0b5394"))
  content((2.5, 2.7), text(size: 7.5pt)[emit A])
  line((1.4, 1.8), (3.5, 1.1), mark: (end: ">"), stroke: rgb("#783f04"))
  content((2.5, 1.3), text(size: 7.5pt)[emit B])
  // A1 -> A2 (same)
  line((4.5, 3), (6.5, 3), mark: (end: ">"), stroke: rgb("#0f766e"))
  content((5.5, 3.3), text(size: 7.5pt)[same])
  // A1 -> B1 (switch)
  line((4.2, 2.5), (4.2, 1.5), mark: (end: ">"), stroke: rgb("#783f04"))
  content((3.5, 2), text(size: 7.5pt)[switch])
  // A2 -> B1 (must switch)
  line((6.5, 2.5), (4.5, 1.5), mark: (end: ">"), stroke: rgb("#9a2617"))
  content((5.8, 2), text(size: 7.5pt)[*must*])
  // B1 -> B2 (same)
  line((4.5, 1), (6.5, 1), mark: (end: ">"), stroke: rgb("#0f766e"))
  content((5.5, 0.7), text(size: 7.5pt)[same])
  // B1 -> A1 (switch)
  line((4.2, 1.5), (4.2, 2.5), mark: (end: ">"), stroke: rgb("#783f04"))
  // B2 -> A1 (must switch)
  line((6.5, 1.5), (4.5, 2.5), mark: (end: ">"), stroke: rgb("#9a2617"))
}))

=== Practical Constrained Codes for DNA

Several families of practical codes have been developed for the DNA constraints.

*Rotation codes.* A simple construction: divide the bit stream into groups, map each group
to a base, and after each group rotate the mapping table by one step. This prevents
systematic runs. The Goldman et al. 2013 code used a variant of this, mapping every pair of
bits (00, 01, 10, 11) to the base that is "different from the previous one" in a defined
rotation order, guaranteeing no two consecutive identical bases.

*D-LOCO codes* (DNA Lexicographically Ordered Constrained Codes). Introduced around 2023
by researchers including Lan Luo and Zhi-Guo Chen, LOCO codes construct their codebook in
a lexicographic order, which gives a natural encoding algorithm based purely on arithmetic
(counting positions in an ordered list) rather than requiring any lookup table. This makes
encoding and decoding very fast for long sequences. D-LOCO codes can simultaneously enforce
both the homopolymer constraint and the GC-balance constraint, and they are capacity-achieving
in the sense that as sequence length grows, the rate approaches the constrained capacity.
In 2025, extended versions were shown to correct substitution errors as well, combining
constrained coding and error correction into a single compact design.

*Erlich-Zielinski screening.* Rather than a carefully crafted mapping, DNA Fountain takes
a different approach: generate a proposed oligo, check whether it satisfies the constraints
using a simple pass/fail test, and if it fails, generate a different one. This is fast
because the generation process (using a pseudorandom number generator seeded by a "drop
number") is cheap, and in practice only a small fraction of candidates need to be discarded.
We will see the full pipeline in the next section.

#misconception[Constrained coding always wastes a large fraction of the capacity.][
  For the DNA constraints (max homopolymer run $r = 3$, GC content 40%–60%), the constrained
  capacity is approximately 1.98 bits/nucleotide, versus the unconstrained maximum of
  2.00 bits/nucleotide. The "waste" is less than 1%. The constraints feel harsh biochemically
  but are mild information-theoretically. The bigger efficiency cost comes from the error-
  correction overhead needed to handle synthesis dropouts and sequencing errors.
]

== Fountain Codes: Drops from an Infinite Stream

The constrained coding layer handles the "which sequences are valid" problem. There is a
second, completely separate challenge: *erasure*. DNA synthesis is not perfectly reliable.
Some oligos simply fail to synthesise. Others synthesise but are present in such small
quantities in the pool that when you sequence a random sample, you just happen to miss them.
When you retrieve your data, some fraction of your oligos will be gone entirely — not
corrupted but absent.

This is the *erasure channel*: the receiver receives each transmitted packet with some
probability, and misses it with the complementary probability, with no way to know in
advance which packets will be missing. Designing error-correcting codes for erasure channels
is a solved problem — classical block codes such as Reed-Solomon (which we will build from
scratch in Chapter 72, _The Error-Correction Boundary_) handle erasures optimally — but those
classical solutions have a drawback for DNA: they require a fixed rate. If you plan for 20%
erasure but actually get 35% erasure, a fixed-rate code fails. You either over-provision
(waste capacity) or under-provision (lose data).

Fountain codes solve this by being *rateless*: there is no fixed code rate. The encoder
can generate as many encoded symbols as needed. The decoder collects symbols until it has
enough to reconstruct the original data, regardless of which specific symbols arrive. The
name comes from the analogy: a water fountain sends out an unlimited stream of droplets,
and you can catch as many as you need to fill your glass, regardless of which exact droplets
you catch.

#definition("Fountain code")[
  A *fountain code* is a rateless erasure code. Given $k$ input symbols (the source data,
  divided into $k$ equal-sized blocks), the encoder produces a potentially unlimited stream
  of encoded symbols. Each encoded symbol depends on some subset of the input symbols.
  A decoder that receives any $k + epsilon$ encoded symbols (for a small overhead $epsilon$)
  can recover all $k$ input symbols with high probability, regardless of which specific
  symbols were received.
]

=== LT Codes: The First Practical Fountain

Michael Luby invented the first practical fountain codes in 1998 (published 2002); they are
called *LT codes* for "Luby Transform." The encoding rule is elegantly simple:

1. Fix a degree distribution $Omega(d)$ — a probability distribution over the integers
   $1, 2, 3, dots, k$.
2. To generate one encoded symbol:
   a. Sample a degree $d$ from $Omega$.
   b. Choose $d$ of the $k$ input symbols uniformly at random.
   c. XOR them together. The result is the encoded symbol.
3. Transmit the encoded symbol together with enough information to know *which* $d$ input
   symbols were chosen (this "connection information" is typically encoded via a shared
   pseudorandom seed so it takes almost no extra space).

The decoder uses *belief propagation* (also called *iterative message passing* or *peeling*):
start with any encoded symbol that XORs together exactly one input symbol (a "degree-1"
symbol), use it to recover that input symbol directly, then subtract it from every other
encoded symbol that depends on it (reducing their degree by 1). This may create new degree-1
symbols, which you decode in turn. Continue until everything is recovered.

#gomaths("XOR — exclusive or")[
  XOR (exclusive or) of two bits: output 1 if they differ, 0 if they are the same.
  Extended to bytes: XOR each pair of corresponding bits independently.
  The crucial property: $a xor a = 0$ and $a xor 0 = a$ for any $a$.
  This means XOR is its own inverse: if you know $a xor b$ and you know $b$,
  you can recover $a$ by XOR-ing with $b$ again.
  For fountain codes: if encoded symbol $e = s_1 xor s_3 xor s_7$ and
  you already know $s_3$ and $s_7$, then $e xor s_3 xor s_7 = s_1$.
]

*Worked example.* Suppose $k = 4$ input blocks: $s_1 = `01`$, $s_2 = `10`$, $s_3 = `11`$,
$s_4 = `00`$ (written as 2-bit values for simplicity). The encoder generates three encoded
symbols:

- $e_1$: degree 1, chose $s_2$. Transmit: `10`.
- $e_2$: degree 2, chose $s_1, s_3$. Transmit: `01 XOR 11 = 10`. (Note `01` XOR `11` = `10`.)
- $e_3$: degree 3, chose $s_2, s_3, s_4$. Transmit: `10 XOR 11 XOR 00 = 01`.

Suppose $e_2$ is lost in the channel. The decoder receives $e_1$ and $e_3$.

Decoding: $e_1$ has degree 1, so $s_2 = $ `10` directly. Now $e_3 = s_2 xor s_3 xor s_4$; subtract the known $s_2$: $e_3 xor s_2 = `01` xor `10` = `11` = s_3 xor s_4$. Still stuck — two unknowns. If we had one more symbol, we could finish. The example illustrates the peeling process and also shows why some overhead beyond $k$ symbols is needed.

The Luby design uses a *Soliton distribution* for the degrees, tuned so that the peeling
process proceeds smoothly. With the ideal Soliton distribution, an LT code can recover $k$
symbols from approximately $k (1 + 1/sqrt(k))$ received symbols. In practice, a "Robust
Soliton" distribution adds a small spike of high-degree symbols to ensure the process
never stalls on hard instances.

=== Raptor Codes: Near-Capacity in Linear Time

LT codes have a weakness: the overhead factor $1/sqrt(k)$ is large for small $k$ but
decreasing for large $k$. For databases of millions of blocks, the overhead is acceptable.
For a few thousand oligos, it can be significant.

*Raptor codes*, invented by Amin Shokrollahi in 2001 and first formally published in 2006,
fix this by cascading a cheap *precode* before the LT stage. The precode is a fixed-rate
erasure code (such as an LDPC code) that pre-processes the $k$ input symbols into
$k' approx k$ *intermediate* symbols, with the property that any $k$ of the $k'$ intermediate
symbols suffice to recover all $k$ originals. The LT stage then generates encoded symbols
from these $k'$ intermediates.

The benefit: because the precode handles any final missing pieces, the LT part can use a
simpler, lower-overhead degree distribution. The combined scheme achieves near-zero overhead
with linear-time encoding and decoding — $O(k log(1/delta))$ operations to fail with
probability at most $delta$, compared to $O(k^2)$ for Reed-Solomon codes.

Raptor codes are deployed in digital broadcasting (the 3GPP eMBMS standard for mobile TV),
in peer-to-peer file sharing, and — crucially — in the DNA Fountain system.

#algo(
  name: "LT Codes (Luby Transform)",
  year: "1998 (published 2002)",
  authors: "Michael Luby",
  aim: "Rateless fountain code for erasure channels; each encoded symbol is the XOR of a random subset of input blocks, drawn from a Soliton degree distribution.",
  complexity: "Encoding: O(k log k) expected per encoded symbol. Decoding: O(k log k) total using belief propagation (peeling).",
  strengths: "Rateless — arbitrarily many encoded symbols can be generated on demand; no fixed code rate needed; simple encoder.",
  weaknesses: "Overhead of O(1/sqrt(k)) symbols beyond k; peeling decoder can stall on rare instances; not universal for all k.",
  superseded: "Raptor codes (Shokrollahi 2006) achieve smaller overhead with linear-time decoding.",
)[]

#algo(
  name: "Raptor Codes",
  year: "2001 (published 2006)",
  authors: "Amin Shokrollahi (EPFL / Digital Fountain Inc.)",
  aim: "Near-capacity rateless erasure codes; a fixed-rate precode followed by an LT code, giving overhead approaching 0 with linear-time encode and decode.",
  complexity: "Encoding and decoding: O(k log(1/δ)) for failure probability δ.",
  strengths: "Near-zero overhead; linear time; standardised in 3GPP and IETF; proven production-ready; excellent for large k.",
  weaknesses: "More complex to implement than pure LT; precode selection affects performance on small k; overhead still nonzero.",
  superseded: "Active research area; no significant successor as of 2026 for the rateless-erasure problem.",
)[]

== DNA Fountain: Putting It All Together

With constrained coding and fountain codes in hand, we can now understand the full DNA
Fountain system that Erlich and Zielinski published in 2017.

=== The Encoding Pipeline

The source file (any binary data) is processed through four stages before the first
molecule is synthesised.

*Stage 1: Packetise.* Divide the file into $k$ segments of equal size (in the 2017 paper,
each segment was 32 bytes). These are the input symbols to the fountain code.

*Stage 2: Generate a drop.* Use a pseudorandom number generator (PRNG) seeded with a
counter called the *drop number* $d$. The PRNG specifies: (a) which segments to XOR
together (the fountain encoding), and (b) which PRNG seed to include in the oligo header
so the decoder knows the connections. XOR the selected segments to produce a *payload*.

*Stage 3: Assemble and screen.* Prepend a barcode (the address of this oligo in the pool)
and the drop number seed. Encode this bit string as a DNA sequence by mapping pairs of bits
to nucleotides. Check the resulting sequence against the constraints: no homopolymer run
exceeds 3, GC content between 45% and 55%. If it fails either check, increment the drop
number and try again. Accepted sequences go to synthesis; rejected ones are silently skipped.

*Stage 4: Synthesise.* Send the accepted sequences to an oligo synthesiser (in the 2017
paper, a commercial service). The machine chemically builds each strand one nucleotide at
a time.

#gopython("Generators and yield")[
  A Python *generator* is a function that produces a sequence of values lazily — one at a
  time, on demand — using the `yield` keyword. This is exactly the right data structure for
  a fountain code: we want to produce encoded drops one at a time, potentially without bound.

  ```python
  def count_up(start: int):
      n = start
      while True:
          yield n
          n += 1

  gen = count_up(0)
  print(next(gen))   # 0
  print(next(gen))   # 1
  print(next(gen))   # 2
  # can continue forever
  ```

  Generators use almost no memory because they do not pre-compute the entire sequence.
  Fountain code encoders are naturally written as generators.
]

The diagram below shows the full pipeline from bytes to DNA oligo.

#fig([The DNA Fountain encoding pipeline. Each drop gets a fresh PRNG seed; sequences that
fail the biochemical screen are silently skipped and a new seed is tried.],
cetz.canvas({
  import cetz.draw: *
  // Boxes
  rect((0, 4), (2.5, 5), fill: rgb("#e8f0f8"), stroke: rgb("#0b5394"), radius: 3pt)
  content((1.25, 4.5))[Source file]
  rect((0, 2.5), (2.5, 3.5), fill: rgb("#e8f0f8"), stroke: rgb("#0b5394"), radius: 3pt)
  content((1.25, 3))[Packetise\ ($k$ segments)]
  rect((3.5, 2.5), (6, 3.5), fill: rgb("#e8f5f2"), stroke: rgb("#0f766e"), radius: 3pt)
  content((4.75, 3))[Fountain\ encode (XOR)]
  rect((3.5, 1), (6, 2), fill: rgb("#faf7ee"), stroke: rgb("#783f04"), radius: 3pt)
  content((4.75, 1.5))[Add header\ + barcode]
  rect((0, 1), (2.5, 2), fill: rgb("#f4f0f8"), stroke: rgb("#5b3a86"), radius: 3pt)
  content((1.25, 1.5))[Screen: GC,\ homopolymer]
  rect((0, -0.5), (2.5, 0.5), fill: rgb("#e8f5f2"), stroke: rgb("#0f766e"), radius: 3pt)
  content((1.25, 0))[Synthesise\ oligo]
  // PRNG box
  rect((7, 2.5), (9.5, 3.5), fill: rgb("#fff4e0"), stroke: rgb("#783f04"), radius: 3pt)
  content((8.25, 3))[PRNG seed\ (drop \#)]
  // Arrows
  line((1.25, 4), (1.25, 3.5), mark: (end: ">"))
  line((2.5, 3), (3.5, 3), mark: (end: ">"))
  line((7, 3), (6, 3), mark: (end: ">"))
  line((4.75, 2.5), (4.75, 2), mark: (end: ">"))
  line((3.5, 1.5), (2.5, 1.5), mark: (end: ">"))
  line((1.25, 1), (1.25, 0.5), mark: (end: ">"))
  // Reject loop
  line((0, 1.5), (-0.7, 1.5), (-0.7, 3), (7, 3), stroke: (dash: "dashed"), mark: (end: ">"))
  content((-0.7, 2.3), text(size: 7pt, fill: rgb("#9a2617"))[fail:\ retry])
  // Pass arrow
  line((0, 1), (0, 0.5), (0, 0), mark: (end: ">"), stroke: rgb("#0f766e"))
  content((0.3, 0.5), text(size: 7pt, fill: rgb("#0f766e"))[pass])
}))

=== The Decoding Pipeline

Sequencing recovers the pool of oligos — not all of them (some were lost) and with some
base-call errors mixed in. The decoder proceeds as follows:

*Stage 1: Error-correct and parse.* Use a short Reed-Solomon or BCH code embedded in the
barcode region to correct individual base errors. Parse out the drop number seed and the
payload.

*Stage 2: Rebuild the connection graph.* For each received drop, use the PRNG seed to
recover which $k$ source segments were XOR-ed. Build the _bipartite graph_ connecting drops
to segments. (A graph is _bipartite_ when its nodes split into two groups — here, "drops" on
one side and "source segments" on the other — and every edge runs _between_ the groups, never
within one. An edge means "this drop is the XOR of, among others, this segment.")

*Stage 3: Belief propagation.* Apply the peeling decoder: find a drop of degree 1 (connected
to exactly one unknown segment), recover that segment, remove it from all other drops,
repeat. Continue until all $k$ segments are recovered.

*Stage 4: Reconstruct the file.* Reassemble segments in order. Verify with a hash or CRC
(Chapter 17 built our CRC-32 into the tinyzip container; the same idea applies here).

In the 2017 demonstration, Erlich and Zielinski encoded 2.14 megabytes of data (including
a full computer operating system, a movie, and other files) into 72,000 oligos of 200
nucleotides each. They used approximately 7% redundancy (about 5,000 extra drops beyond
the minimum needed) to guard against oligo dropout. The entire file was recovered without
a single bit error. The information density achieved was 1.55 bits per nucleotide — 85% of
the theoretical Shannon channel capacity of 1.83 bits/nt (the gap from 2.00 is due to
error-correction overhead, barcoding, and the small GC constraint cost).

#keyidea[
  DNA Fountain achieves 85% of the Shannon channel capacity of the DNA storage medium —
  closer to the theoretical limit than many engineered communication systems. The key
  innovations are: (1) screening rather than constructing constrained sequences, which
  avoids complex code design; (2) using a rateless fountain code, which naturally handles
  unknown and variable dropout rates.
]

=== Why the Combination Works So Well

The beauty of the DNA Fountain design is that constrained coding and fountain coding solve
*orthogonal* problems, and they compose cleanly.

Constrained coding deals with the *alphabet*: which sequences are physically writable and
readable. It operates at the nucleotide level.

Fountain coding deals with *erasure*: which oligos survive through synthesis, storage, and
sequencing. It operates at the oligo level.

Because these two problems are at different levels of the system, the solutions can be
stacked without interference. The fountain code does not care about the internal structure
of each oligo, and the constrained code does not care about which oligos survive. This
separation of concerns — a classic principle of good engineering design — is exactly what
makes the architecture practical.

#gopython("Bitwise XOR in Python")[
  Python's `^` operator is bitwise XOR on integers. For bytes objects, you need to XOR
  element-by-element. Here is a helper function:

  ```python
  def xor_bytes(a: bytes, b: bytes) -> bytes:
      """XOR two equal-length byte strings."""
      assert len(a) == len(b), "Lengths must match"
      return bytes(x ^ y for x, y in zip(a, b))

  # Simple fountain-code drop generator
  import random

  def fountain_encoder(
      segments: list[bytes],
      seed: int = 42
  ):
      """
      Generate encoded fountain drops indefinitely.
      Each drop is the XOR of a randomly chosen subset of segments.
      Yields (drop_seed, encoded_bytes) pairs.
      """
      k = len(segments)
      drop_number = 0
      rng = random.Random(seed)
      while True:
          drop_seed = (seed << 16) ^ drop_number
          local_rng = random.Random(drop_seed)
          # Soliton-like degree: simplified to uniform 1..min(k,4)
          degree = local_rng.randint(1, min(k, 4))
          chosen = local_rng.sample(range(k), degree)
          payload = segments[chosen[0]]
          for idx in chosen[1:]:
              payload = xor_bytes(payload, segments[idx])
          yield (drop_seed, chosen, payload)
          drop_number += 1

  # Demo
  data = b"HELLOWORLD"
  # Split into 2-byte segments
  segs = [data[i:i+2] for i in range(0, len(data), 2)]
  enc = fountain_encoder(segs, seed=1)
  for _ in range(5):
      s, indices, pay = next(enc)
      print(f"seed={s:06x} indices={indices} payload={pay.hex()}")
  ```

  This is a simplified illustration. A production system would use a Robust Soliton degree
  distribution and a cryptographic-quality PRNG for the connection seeds.
]

== Information Density: How Close Are We to the Limit?

Let us pin down the numbers precisely.

*Theoretical maximum.* An unconstrained 4-symbol DNA alphabet carries $log_2 4 = 2$ bits
per nucleotide. This is the absolute ceiling.

*Practical channel capacity.* The DNA storage channel has several sources of noise and
overhead. Erlich and Zielinski calculated that, for their practical architecture (pooled
synthesis, short-read Illumina sequencing, barcoded oligos, typical dropout rates), the
Shannon channel capacity is approximately 1.83 bits per nucleotide. This accounts for
GC constraint and homopolymer constraint (together costing about 0.02 bits/nt), dropout
correction (costing about 0.10 bits/nt), and barcode/addressing overhead (costing about
0.05 bits/nt).

*DNA Fountain achieved.* 1.55 bits per nucleotide = 85% of the 1.83 bits/nt practical
capacity.

*The density record.* At 1.55 bits/nt, and given that one gram of double-stranded DNA
contains approximately $9.1 times 10^(20)$ nucleotides (this follows from the molecular
weight of a nucleotide pair, about 660 daltons, and Avogadro's number), the information
density is:

$ D = 1.55 "bits/nt" times 9.1 times 10^(20) "nt/g" approx 1.4 times 10^(21) "bits/g" $

Converting to petabytes (1 PB = $8 times 10^(15)$ bits):

$ D approx (1.4 times 10^(21)) / (8 times 10^(15)) "PB/g" approx 175,000 "PB/g" = 175 "exabytes/g" $

The "215 petabytes per gram" figure often cited in press releases uses a slightly different
accounting (dry vs. wet weight, specific oligo length assumptions) but is in the same
ballpark. All versions of the number are astonishing compared to flash memory's roughly
10 GB per gram.

#gomaths("Avogadro's number and moles")[
  Avogadro's number, $N_A approx 6.022 times 10^(23)$, is the number of atoms (or molecules,
  or any other specified particle) in one *mole* — the chemist's standard unit for counting
  large numbers of particles. A single nucleotide (DNA base + sugar + phosphate) has a
  molecular weight of about 330 daltons (330 grams per mole). One gram of nucleotides
  therefore contains $1 / 330$ moles, which is $(1/330) times 6.022 times 10^(23) approx
  1.8 times 10^(21)$ nucleotides. In double-stranded DNA, each base is paired, halving
  this to $approx 9 times 10^(20)$ nucleotide pairs per gram — the figure used above.
  This is pure chemistry, but the result — almost a trillion trillion nucleotides per gram
  — is why DNA density is almost beyond comprehension.
]

#scoreboard(caption: "Information density comparison (not bytes on a file, but storage density)",
  [Flash memory (3D NAND, 2025)], [~10 GB/g], [—], [Best consumer storage per gram],
  [Magnetic tape (LTO-9)], [~1 GB/g], [—], [Long-term archival workhorse],
  [DNA storage (Goldman 2013)], [~0.3 bits/nt], [—], [First carefully designed scheme],
  [DNA Fountain (2017)], [1.55 bits/nt], [~85% capacity], [Current practical record],
  [Theoretical maximum], [2.00 bits/nt], [100%], [Shannon limit for 4-symbol alphabet],
)

== The Error Model: What Can Go Wrong

Understanding the DNA channel's error model is essential for designing robust codes. The
errors fall into three categories quite different from anything in digital communications.

*Deletion and insertion errors.* A deletion is when a nucleotide is simply skipped during
synthesis or sequencing. An insertion is when an extra nucleotide is inserted. These errors
are catastrophic for fixed-frame codes: a single deletion shifts every subsequent base by
one position, turning every downstream symbol into garbage. Nanopore sequencing (used for
long reads) has higher deletion/insertion rates than short-read Illumina sequencing. This
is why long-read nanopore and short-read Illumina platforms require different error-correction
strategies.

*Substitution errors.* A single base is miscalled: `A` is read as `C`, for instance. This
is similar to a bit-flip in conventional digital channels, and well-understood codes
(Hamming codes, BCH codes, Reed-Solomon) handle it efficiently.

*Oligo dropout.* An entire oligo may simply fail to synthesise, or may be present in
such low concentration that it is not sampled during sequencing. This is the erasure error
that the fountain code is designed to handle. Typical dropout rates in 2025 systems range
from 1% to 10% depending on the synthesis technology.

*Coverage imbalance.* Even when an oligo is present, it may be amplified unequally during
the _polymerase chain reaction_ (PCR — the standard laboratory technique that copies a DNA
sample many times over to produce enough material to sequence), so some oligos appear
hundreds of times and others only once or twice. This requires careful statistical sequencing
depth planning.

#pitfall[
  It is tempting to use a standard Reed-Solomon code (which handles both errors and erasures)
  and skip the fountain code entirely. This works but forces you to choose a fixed code rate
  in advance. If your dropout rate is unexpectedly high, you lose data. The rateless nature
  of the fountain code is not a theoretical nicety; it is a practical necessity for a medium
  where the dropout rate varies between synthesis runs, synthesis vendors, and storage
  conditions in ways that are hard to predict.
]

== Practical Engineering: From Lab to Product

=== Writing: DNA Synthesis Technologies

Current DNA synthesis for data storage uses *column synthesis* (phosphoramidite chemistry)
or *electrochemical array synthesis* (pioneered by Agilent and Twist Bioscience). In column
synthesis, each nucleotide is added one at a time to a growing chain, with a chemical
coupling efficiency of about 99% per step; for a 200-nucleotide oligo, this means
$(0.99)^(200) approx 13%$ of chains complete successfully without any error, requiring
significant quality control. Twist Bioscience's silicon array platform achieves higher
uniformity by synthesising thousands of sequences simultaneously on a chip. By 2025, Twist
was quoting prices around USD 0.007 per base for bulk orders — expensive for data storage
(a 1 MB file requires roughly 600,000 bases at 1.55 bits/nt) but dropping steadily.

The emerging alternative is *enzymatic synthesis* (companies like Ansa Biotechnologies,
Molecular Assemblies, DNA Script, and Twist's own enzymatic program) which uses a modified
enzyme (terminal deoxynucleotidyl transferase, TdT) to add individual nucleotides without
organic solvents, at higher throughput and with a lower error rate per step. Enzymatic
synthesis is still pre-commercial for data storage as of 2026 but is expected to reduce
costs by one to two orders of magnitude over the next decade.

=== Reading: Sequencing Technologies

Two families of sequencing dominate.

*Short-read sequencing* (Illumina). Reads 150–300 base pairs at a time, with an error rate
of about 0.1% per base, predominantly substitution errors. This is the gold standard for
accuracy and was used in the DNA Fountain demonstration. Cost has dropped below USD 0.001 per
base in bulk.

*Long-read sequencing* (Oxford Nanopore, Pacific Biosciences). Reads thousands of base
pairs at once (up to tens of kilobases), which is useful for reading long oligos or
reconstructing overlapping reads. Error rates are higher (1–5% for nanopore, improving
rapidly in 2024–2026 with AI-based basecallers). The Oxford Nanopore MinION is the size of
a USB drive and can sequence a sample in a few hours on a laptop — transformative for
portability.

=== Random Access: Retrieving One File from the Pool

One advantage of magnetic or flash storage that DNA pools seem to lack is *random access*:
reading one specific file without reading everything else. In a mixed pool of billions of
oligos, how do you find the 72,000 oligos for one specific file?

The answer is *PCR* (the polymerase chain reaction we just met) with file-specific primers. Each file's
oligos carry unique short sequences at their ends (primers) that PCR can recognise and
amplify selectively. Add the matching primer pair to the pool, run PCR, and only the target
file's oligos are amplified — everything else stays in the background at low concentration.
Sequence the amplified product, and you have your file. This is essentially a molecular
key-value lookup. Researchers at the University of Washington (Lee et al., 2019) demonstrated
automated random access in a 200 MB pool.

#history[
  *The Washington-Microsoft system (2019).* In collaboration, researchers at the University
  of Washington and Microsoft Research built a fully automated DNA storage and retrieval
  system. The system stored 200 MB across approximately 13.4 million oligo sequences and
  retrieved individual files using PCR-based random access with a robotic liquid-handling
  system. The whole read-write-retrieve cycle was automated without human intervention, a
  critical milestone on the path from laboratory curiosity to engineering product. The paper
  was published in _Nature Scientific Reports_ in 2019. By 2024, the DNA Data Storage
  Alliance had published its first interoperability specification, beginning the process of
  standardisation.
]

== The Constrained-Coding Rate Penalty in Practice

We noted earlier that the theoretical rate loss from the GC and homopolymer constraints is
tiny (less than 1%). But a more careful analysis reveals an interesting subtlety.

Consider Erlich and Zielinski's screening approach. They generate candidate sequences using
a pseudorandom mapping from bits to DNA, then screen them. Only about 97% of candidates
pass. This means they must generate roughly $1/0.97 approx 1.03$ candidates per accepted
sequence — a 3% overhead in the generation step. This overhead is negligible.

But the rejected sequences are not just "wasted computation": each rejection forces the
use of a different fountain-code drop number. Since the fountain code is rateless, this
is fine — just skip the rejected drop number and use the next. The decoder does not care
which specific drop numbers were used.

This is the elegant cleverness of the design: the screening approach converts the
constrained-coding problem into a *selection* problem, and the fountain code's ratelessness
makes selection free. There is no need to solve the hard combinatorial problem of explicitly
constructing constrained codewords; instead, generate random candidates and discard the bad
ones. The fountain code absorbs the "missing" drops with zero penalty.

#aside[
  This trick — generate many candidates, keep the good ones, and use a rateless outer code
  so that the selection does not create gaps — is broadly applicable. It appears in other
  biological storage media (fluorescent molecules, peptides, synthetic polymers) and in some
  classical communications applications where constructing explicit constrained codes is
  impractical.
]

== State of the Art in 2025–2026

The DNA storage field in mid-2026 sits at an interesting inflection point. The science is
solid — the information-theoretic results are proved, the coding schemes work, multiple
demonstrations have stored and retrieved megabytes to hundreds of megabytes without error.
The bottleneck is engineering cost and speed.

*Writing cost.* Synthesising a megabyte of data in DNA costs on the order of thousands
of dollars in 2025 (estimates vary by synthesis method and scale). For archival data that
never changes and where long-term preservation is the priority, this may be acceptable;
for routine storage, it is not.

*Writing speed.* Current synthesis throughput is on the order of kilobytes to megabytes
per day per device. This is millions of times slower than writing to a hard drive.

*Reading speed.* Sequencing throughput is higher — Oxford Nanopore's PromethION can
sequence tens of gigabases per run — but the wet-lab preparation steps (PCR, library
preparation) add hours of latency.

*Industry activity.* Multiple companies are pursuing commercial DNA storage:
- *Catalog Technologies* (founded 2016, USD 35M Series B in 2021) focuses on high-throughput
  DNA writing for large archival datasets.
- *Ansa Biotechnologies, DNA Script, Molecular Assemblies* are developing enzymatic
  synthesis platforms that aim to slash writing costs.
- *Microsoft* continues research through its Project Silica collaboration and has participated
  in the DNA Data Storage Alliance.
- *Twist Bioscience* supplies high-quality synthetic oligos and is a member of the Alliance.
- The *DNA Data Storage Alliance* (formed 2020, first spec released March 2024) is building
  interoperability standards for file formats, addressing schemes, and error-correction
  metadata.

The consensus view in 2026 is that DNA storage will first become commercially viable for
*cold archival* data — data that is written once, stored for decades, and almost never read.
The economics favour it: no power required for storage, physical footprint near zero,
century-scale durability. The question is not whether the technology works but how quickly
costs fall. Most analysts project DNA storage entering commercial archival markets sometime
in the late 2020s to early 2030s.

#misconception[DNA data storage is a single technology that stores data inside real cells.][
  DNA data storage uses *synthetic* oligonucleotides — short custom-made strands built
  chemically or enzymatically in a laboratory — stored in a sealed vial, not inside living
  cells. Living cells would copy, mutate, and express the DNA in ways that would corrupt the
  data rapidly. The stored molecules are inert chemical compounds, more like a bottle of
  special ink than a biological organism. Separately, "in vivo" DNA storage (storing data
  inside bacteria or yeast genomes) is a research curiosity with very different trade-offs
  and is not what the systems described in this chapter do.
]

== A Python Sketch of the Full System

No TINYZIP step is assigned to this chapter (see the project spec: DNA storage has no
`#project` step). But it is instructive to sketch the complete encode-decode loop in Python
to make the pipeline concrete. The following code is intentionally simplified — it omits
the biochemical screening, uses a minimal PRNG, and represents DNA as a string — but it
captures all the structural pieces.

```python
"""
dna_fountain_sketch.py — illustrative sketch of the DNA Fountain pipeline.
NOT a production implementation. Simplified for teaching purposes.
"""
import random
import hashlib

# ── Constants ──────────────────────────────────────────────────────────────
SEGMENT_BYTES = 4        # bytes per source segment
MAX_DEGREE    = 4        # max fountain-code degree
BASES         = "ACGT"  # the four DNA nucleotides

# ── Encoding helpers ────────────────────────────────────────────────────────
def bits_to_dna(data: bytes) -> str:
    """Map every pair of bits to one nucleotide (00→A, 01→C, 10→G, 11→T)."""
    result = []
    for byte in data:
        for shift in (6, 4, 2, 0):
            pair = (byte >> shift) & 0b11
            result.append(BASES[pair])
    return "".join(result)

def dna_to_bits(seq: str) -> bytes:
    """Reverse of bits_to_dna."""
    bits = 0
    for base in seq:
        bits = (bits << 2) | BASES.index(base)
    total_bytes = len(seq) // 4
    return bits.to_bytes(total_bytes, "big")

def xor_bytes(a: bytes, b: bytes) -> bytes:
    return bytes(x ^ y for x, y in zip(a, b))

def gc_content(seq: str) -> float:
    return (seq.count("G") + seq.count("C")) / len(seq)

def max_run(seq: str) -> int:
    if not seq:
        return 0
    best, cur, prev = 1, 1, seq[0]
    for base in seq[1:]:
        cur = cur + 1 if base == prev else 1
        best = max(best, cur)
        prev = base
    return best

def passes_screen(seq: str) -> bool:
    gc = gc_content(seq)
    return 0.40 <= gc <= 0.60 and max_run(seq) <= 3

# ── Fountain encoder ────────────────────────────────────────────────────────
def fountain_encode(
    source: bytes,
    segment_size: int = SEGMENT_BYTES,
    seed: int = 0,
) -> list[tuple[int, list[int], bytes]]:
    """
    Encode source data using a simplified fountain code.
    Returns a list of (drop_seed, segment_indices, xored_payload).
    Screens out drops that fail biochemical constraints.
    """
    # Pad to multiple of segment_size
    r = len(source) % segment_size
    if r:
        source = source + b"\x00" * (segment_size - r)
    k = len(source) // segment_size
    segments = [source[i*segment_size:(i+1)*segment_size] for i in range(k)]

    drops: list[tuple[int, list[int], bytes]] = []
    drop_number = 0
    accepted = 0
    needed = k + k // 4  # 25% overhead for erasure tolerance

    while accepted < needed:
        drop_seed = seed ^ (drop_number * 0x9e3779b9 & 0xFFFFFFFF)
        rng = random.Random(drop_seed)
        degree = rng.randint(1, min(k, MAX_DEGREE))
        indices = rng.sample(range(k), degree)

        payload = segments[indices[0]]
        for idx in indices[1:]:
            payload = xor_bytes(payload, segments[idx])

        # Encode as DNA and screen
        dna_seq = bits_to_dna(payload)
        if passes_screen(dna_seq):
            drops.append((drop_seed, indices, payload))
            accepted += 1
        drop_number += 1

    return drops

# ── Fountain decoder (belief propagation / peeling) ────────────────────────
def fountain_decode(
    drops: list[tuple[int, list[int], bytes]],
    k: int,
    segment_size: int = SEGMENT_BYTES,
) -> bytes | None:
    """
    Recover k source segments from a list of (seed, indices, payload) drops.
    Returns reconstructed bytes or None if decoding fails.
    """
    recovered: dict[int, bytes] = {}
    # Build working copies of each drop's connection list and payload
    work = [(list(idxs), bytearray(pay)) for _, idxs, pay in drops]

    changed = True
    while changed:
        changed = False
        for idxs, pay in work:
            # Subtract any already-known segments
            still_unknown = []
            for idx in idxs:
                if idx in recovered:
                    for i, b in enumerate(recovered[idx]):
                        pay[i] ^= b
                else:
                    still_unknown.append(idx)
            idxs[:] = still_unknown
            # If degree is now 1, we can recover that segment
            if len(idxs) == 1:
                seg_idx = idxs[0]
                if seg_idx not in recovered:
                    recovered[seg_idx] = bytes(pay)
                    changed = True

    if len(recovered) < k:
        return None  # decoding failed; need more drops

    return b"".join(recovered[i] for i in range(k))

# ── Round-trip test ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    original = b"Hello, DNA storage world!!"
    k = -(-len(original) // SEGMENT_BYTES)   # ceiling division

    print(f"Source: {original!r}  ({len(original)} bytes, {k} segments)")

    drops = fountain_encode(original, seed=6)
    print(f"Generated {len(drops)} drops (including ~25% redundancy)")

    # Simulate 10% oligo dropout
    rng = random.Random(5)
    surviving = [d for d in drops if rng.random() > 0.10]
    print(f"After 10% dropout: {len(surviving)} drops survive")

    result = fountain_decode(surviving, k)
    if result is not None:
        # Strip padding
        result = result[:len(original)]
        ok = result == original
        print(f"Decoded: {result!r}")
        print(f"Round-trip {'PASSED' if ok else 'FAILED'}")
    else:
        print("Decoding FAILED — not enough drops received")
```

Running this on the 26-byte string `"Hello, DNA storage world!!"` splits it into $k = 7$
segments, generates 8 drops (the $k + k\/4$ formula gives $7 + 1$, so one extra drop of
redundancy), loses 1 of the 8 to simulated dropout, and still recovers all 26 bytes exactly.
Notice the margin is thin: with only one spare drop, the peeling decoder succeeds here but
would fail on a less lucky combination of which segments each drop happens to cover. That
fragility is exactly why real systems use a richer degree distribution (the Robust Soliton)
and far more redundancy — typically 5–10% _extra oligos on top of_ a code already designed so
that the peeling process almost never stalls. The sketch is faithful to the _structure_ of
DNA Fountain, not to its safety margins.

#checkpoint[In the fountain decoder, why does the peeling step need to iterate (the `while
changed` loop) rather than making one pass through all drops?][
  A single pass might recover some degree-1 drops but miss others that become degree-1 only
  after the first pass. For example, a degree-2 drop covering segments $s_3$ and $s_5$
  cannot be reduced until one of them is known. If $s_5$ is recovered in the first pass,
  then this drop becomes degree 1 in the second pass and can recover $s_3$. Iterating until
  no new recoveries occur ensures we find all recoverable segments.
]

== Forward Pointers and Open Problems

This chapter has focused on the current state of the art. Several frontier problems remain
open as of 2026.

*Deletion/insertion codes for DNA.* The fountain + constrained approach handles substitution
errors and erasures well. Insertion-deletion errors (indels), which are common in nanopore
sequencing, require a different family of error-correcting codes. *Varshamov-Tenengolts*
(VT) codes, invented in 1965 for different reasons, turn out to handle single deletions in
DNA. Extending to multiple deletions is an active research area. Helitag, a scheme developed
at the Weizmann Institute (2021), provides practical indel protection for short sequences.

*In-memory computation.* Some researchers are exploring not just storing data in DNA but
*computing with it* — molecular logic gates that operate on DNA. This is related to the
broader field of molecular computing (Chapter 80 looks at the longer horizon). For now,
computation in DNA is orders of magnitude slower and more error-prone than silicon.

*Other polymer storage.* DNA is one of many polymers that could encode digital data. Peptides
(chains of amino acids), polysaccharides, and synthetic polymers with custom monomers have
all been demonstrated. Each has a different error model, alphabet size, and cost structure.
The coding-theory framework of this chapter applies to all of them.

*Integration with AI.* Recent work (2025–2026) is exploring using neural networks to predict
synthesis quality scores for proposed sequences, enabling smarter screening that rejects
fewer candidates while maintaining biochemical reliability — marrying the learned-compression
ideas of Chapter 62 with the physical constraints of the DNA channel.

#takeaways((
  [DNA's four-letter alphabet (A, T, G, C) has a theoretical maximum capacity of 2 bits
   per nucleotide; in practice, constraints and overhead bring the achievable rate to about
   1.83 bits/nt, and DNA Fountain achieves 1.55 bits/nt (85% of capacity).],
  [The DNA storage channel has two core biochemical constraints: maximum homopolymer run
   length (avoiding AAAA... runs) and balanced GC content (40%–60% G+C per strand). Both
   are necessary for reliable synthesis and sequencing.],
  [Constrained coding theory uses finite-state graphs and the Perron-Frobenius eigenvalue
   to compute the capacity of a constrained channel. For the DNA constraints, the capacity
   loss is less than 1% below the unconstrained maximum.],
  [Fountain codes (LT codes by Luby, 2002; Raptor codes by Shokrollahi, 2006) are rateless
   erasure codes: the encoder generates unlimited encoded symbols, and the decoder recovers
   the source from any sufficient subset, without knowing in advance which symbols were lost.],
  [DNA Fountain (Erlich and Zielinski, 2017) combines biochemical screening for constrained
   coding with a Raptor-inspired fountain code for erasure correction, achieving 215 PB/g
   equivalent storage density and zero-error recovery of 2.14 MB.],
  [The two layers — constrained coding (nucleotide level) and fountain coding (oligo level)
   — solve orthogonal problems and compose cleanly, which is the architectural key to the
   system's simplicity and near-capacity performance.],
  [As of 2026, DNA storage is not yet commercially competitive with tape for cost and speed,
   but the information-theoretic foundations are solid, writing costs are falling, and the
   DNA Data Storage Alliance is building interoperability standards in anticipation of
   commercial deployment in the late 2020s to early 2030s.],
))

== Exercises

#exercise("70.1", 1)[
  A DNA strand has the sequence `AACGTTTACGAA`. Calculate its GC content and identify the
  longest homopolymer run. Would this sequence pass the DNA Fountain screening criteria
  (GC between 40%–60%, max run ≤ 3)?
]
#solution("70.1")[
  GC count: G appears at positions 4, 9; C appears at positions 3, 10 — total 4 GC out of
  12 bases. GC content = 4/12 = 33.3%. This fails the 40%–60% GC constraint.
  Longest homopolymer run: `TTT` at positions 6–8, length 3. This passes the run constraint.
  Overall verdict: fails screening (GC too low), would be rejected and a new drop tried.
]

#exercise("70.2", 1)[
  In a simple 2-symbol constrained system, runs of 3 or more identical symbols are forbidden.
  Draw the finite-state graph (states represent "how many consecutive identical symbols have
  appeared") and identify all valid transitions. What is the maximum bit-per-symbol capacity
  (qualitatively — more or less than for the unconstrained 2-symbol case)?
]
#solution("70.2")[
  States: S1 (just emitted a symbol, 1 in a row), S2 (2 in a row). Transitions: from S1,
  can go to S2 (same symbol) or S1 in the other class (different symbol). From S2, can
  only go to S1 for the other symbol (forced switch). The adjacency matrix is 2×2 with 2
  possible symbols, but the branching factor from S2 is 1 (no choice), while from S1 it
  is 2. This reduces the long-run branching factor below 2. The capacity is less than
  log_2(2) = 1 bit/symbol but not by much (exact calculation gives ~0.946 bits/symbol
  for binary with max-run-2 constraint).
]

#exercise("70.3", 2)[
  Explain in your own words why fountain codes are called "rateless." How is this different
  from a standard block error-correcting code like Reed-Solomon? Why does ratelessness matter
  specifically for the DNA storage application?
]
#solution("70.3")[
  A block code like Reed-Solomon has a fixed rate: if you want to protect $k$ data symbols
  and send $n$ total symbols, the rate is $k/n$, chosen before encoding. If the channel
  loss rate is higher than expected, the code fails. Fountain codes are rateless because
  there is no predetermined $n$: the encoder generates symbols indefinitely, and the decoder
  collects as many as needed. The "rate" is determined dynamically by how many symbols
  actually survive. For DNA storage, dropout rates vary between synthesis batches, vendors,
  and storage conditions — they cannot be precisely predicted. A rateless code automatically
  adapts: if fewer oligos survive, just sequence more of the pool to get more drops. No
  re-encoding required.
]

#exercise("70.4", 2)[
  The DNA Fountain paper stores 2.14 megabytes using 72,000 oligos of 200 nucleotides each.
  (a) How many total nucleotides is that? (b) What is the raw storage capacity at 2 bits
  per nucleotide? (c) What fraction of that raw capacity is used for actual data? (d) What
  is the effective bits-per-nucleotide rate, and how does it compare to the 1.55 bits/nt
  figure reported in the paper?
]
#solution("70.4")[
  (a) $72{,}000 times 200 = 14{,}400{,}000$ nucleotides total.
  (b) At 2 bits/nt: $14{,}400{,}000 times 2 = 28{,}800{,}000$ bits = 3.6 MB raw capacity.
  (c) Fraction used = $2.14 "MB" / 3.6 "MB" approx 59.4%$.
  (d) Effective rate = $2.14 times 8 times 10^6 "bits" / 14{,}400{,}000 "nt" approx 1.19$ bits/nt.
  This is lower than 1.55 bits/nt because some nucleotides are used for barcode/header
  information, not data. The 1.55 bits/nt figure counts only the data-carrying nucleotides
  in the payload region.
]

#exercise("70.5", 2)[
  Write a Python function `passes_screen(seq: str) -> bool` that returns `True` if a DNA
  sequence (given as a string of A, T, G, C characters) has: (a) GC content between 40%
  and 60% inclusive, and (b) no homopolymer run of length 4 or more. Test it on the sequences
  `"ATGCATGCAT"` (should pass) and `"AAAACGTCGT"` (should fail).
]
#solution("70.5")[
  ```python
  def passes_screen(seq: str) -> bool:
      if not seq:
          return False
      # GC content check
      gc = (seq.count("G") + seq.count("C")) / len(seq)
      if not (0.40 <= gc <= 0.60):
          return False
      # Homopolymer run check
      run = 1
      for i in range(1, len(seq)):
          if seq[i] == seq[i-1]:
              run += 1
              if run >= 4:
                  return False
          else:
              run = 1
      return True

  # Tests
  print(passes_screen("ATGCATGCAT"))  # GC=40%, max_run=1 → True
  print(passes_screen("AAAACGTCGT"))  # AAAA run of 4 → False
  ```
  `"ATGCATGCAT"` has 4 G/C out of 10 bases (GC=40%) and max run 1; passes.
  `"AAAACGTCGT"` has an `AAAA` run of length 4; fails.
]

#exercise("70.6", 3)[
  *Research question.* The XOR-based fountain code described in this chapter works perfectly
  for lossless data storage. But DNA synthesis introduces *substitution errors* as well as
  erasures. Sketch (in words or pseudocode, not full code) how you would extend the system
  to handle both: (a) a short Reed-Solomon code embedded in the barcode/header of each oligo
  to correct individual base substitutions within an oligo, and (b) the fountain code at the
  oligo level to handle oligo erasure. How do these two layers interact, and why does this
  layered approach work cleanly?
]
#solution("70.6")[
  The two layers can be combined as follows. Each oligo is structured as:
  [barcode (20 nt)] [drop-seed (16 nt)] [payload (140 nt)] [RS check symbols (24 nt)].
  The RS code (a short Reed-Solomon over a small field, e.g. GF(16) where each symbol is 4
  bits / one nucleotide) uses the 24 check nucleotides to correct up to 12 substitution
  errors in the entire 200-nt oligo. This handles the within-oligo error layer.
  Above this, the fountain code handles the between-oligo erasure layer: oligos that fail
  RS decoding (too many substitutions to correct) are simply discarded (treated as erased),
  and the fountain code recovers the data from the surviving oligos.
  The layers interact cleanly because RS decoding either succeeds (producing a corrected,
  trusted oligo) or fails (producing a discarded oligo — an erasure). The fountain decoder
  sees only clean oligos or missing oligos; it never receives a partially-corrupted oligo.
  This clean separation of concerns (within-oligo correction via RS; between-oligo recovery
  via fountain) is architecturally robust and matches the way DNA Fountain was actually
  implemented in the 2017 paper.
]

== Further reading

#link("https://www.science.org/doi/10.1126/science.aaj2038")[Erlich Y. and Zielinski D.,
"DNA Fountain enables a robust and efficient storage architecture," _Science_ 355(6328),
pp. 950–954, March 2017. The foundational paper; read the supplementary methods for the
full constrained-coding and fountain-code design.]

#link("https://www.science.org/doi/10.1126/science.1226355")[Church G.M., Gao Y., Kosuri S.,
"Next-Generation Digital Information Storage in DNA," _Science_ 337(6102), p. 1628,
September 2012. The 2012 milestone that demonstrated 5.27 megabits stored in DNA and set the
stage for the field.]

#link("https://dl.acm.org/doi/10.1145/584091.584093")[Luby M., "LT Codes," _Proceedings of
the 43rd IEEE Symposium on Foundations of Computer Science (FOCS)_, 2002. The foundational
paper on Luby Transform (fountain) codes.]

#link("https://ieeexplore.ieee.org/document/1621033")[Shokrollahi A., "Raptor Codes,"
_IEEE Transactions on Information Theory_ 52(6), pp. 2551–2567, June 2006. The definitive
treatment of Raptor codes, which extend LT codes to near-zero overhead with linear-time
decode.]

#link("https://arxiv.org/abs/2311.08325")[Luo L. et al., "Protecting the Future of
Information: LOCO Coding With Error Detection for DNA Data Storage," arXiv:2311.08325,
2023. The D-LOCO codes that achieve the constrained capacity with an elegant lexicographic
encoding.]

#link("https://arxiv.org/abs/2308.05952")["Embracing Errors Is More Efficient Than Avoiding
Them Through Constrained Coding for DNA Data Storage," arXiv:2308.05952, 2023. A provocative
analysis arguing that for modern high-accuracy synthesis, the rate penalty from constrained
coding is smaller than the error-correction overhead of not using constraints — nuanced
engineering trade-off analysis.]

#link("https://www.snia.org/sites/default/files/DNA/SNIA-DNA-Data-Storage-Technology-Review-v1.0.pdf")[
SNIA DNA Data Storage Technology Review, Version 1.0, June 30, 2025. A comprehensive
industry overview of the state of DNA storage technology, covering synthesis, sequencing,
error correction, and standardisation efforts.]

#bridge[
  DNA molecules are the most information-dense storage medium we know of, and we have now
  seen how to use them reliably by layering constrained coding and fountain codes. But DNA
  is exotic and expensive. The next chapter — Chapter 71 — returns to earth, examining
  *delta coding, diff, and deduplication*: the workhorse techniques that store not a fresh
  copy of every file, but only what has changed since the last version. Git, rsync, backup
  systems, and version control all rely on these ideas, and they compress version histories
  by orders of magnitude while remaining entirely practical on commodity hardware. From
  molecules back to bytes — the full circle of the compression story.
]
