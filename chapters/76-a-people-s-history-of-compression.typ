#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= A People's History of Compression

#epigraph[
  "The best way to understand any field is to know who built it, why they were there, and what they were frustrated by."
][attributed to Donald Knuth, in various forms]

Here is a question nobody seems to ask at the start of a compression textbook: *Who were these people, and what were they actually trying to do?*

Shannon was not trying to invent data compression. Huffman was trying to win a bet with a professor. Ziv and Lempel were not building gzip -- they were chasing a mathematical proof that a single algorithm could work on any source without knowing the source's statistics. Welch was a researcher at Sperry who wanted to speed up disk controllers. Katz wanted to fix the patent mess that Welch's paper had accidentally created. Brandenburg spent a decade fighting inside a standards committee to get a psychoacoustics model that everyone else thought was too complicated, into a format nobody yet called MP3. Collet wrote Zstandard in his spare time at Facebook because the existing tools annoyed him. Duda, a mathematician in Krakow, posted a paper to the physics preprint server because he did not know where else to put it, and it turned into the entropy-coding engine inside JPEG XL, zstd, and every modern codec.

Compression was not discovered by a single genius in a single morning. It was built -- argument by argument, patent by patent, late night by late night -- by a long chain of people who each added one brick and passed the pile to the next person in line.

This chapter is that chain. We will walk it chronologically, meeting the humans and the institutions that shaped every algorithm we have studied. By the end, the field will look less like a collection of techniques and more like what it actually is: a messy, living conversation between people who love the problem of making things smaller.

#recap[
  You have now studied every major compression technique in this book: information theory in Chapters 18--23 and entropy coding in Chapters 24--27, dictionary methods in Chapters 28--33, the BWT and benchmarks in Chapters 35--36, lossy and perceptual coding in Chapters 37--55, learned and neural compression in Chapters 56--73, and the systems and measurement landscape in Chapters 74--75. This chapter takes all of those ideas and puts *faces* on them. It is unabashedly a history chapter -- narrative, human-centred, and deliberate about naming the social forces (patents, standards bodies, institutional affiliations, personal rivalries) that shaped what got built and what got buried.
]

#objectives((
  [Name the key people and institutions behind every major compression algorithm studied in this book, and state what each person was actually trying to solve.],
  [Explain how patents shaped the development of compression formats -- particularly GIF/LZW, MP3, arithmetic coding, and ANS -- and what that meant for which tools got used in practice.],
  [Describe the role of academic institutions and corporate research labs (Bell Labs, IBM, DEC SRC, Fraunhofer IIS) in the history of compression.],
  [Recognize the pattern of "lone outsider produces a breakthrough" that recurs across the field.],
  [Write a short annotated timeline of compression history and explain how each development built on the previous one.],
))

== The Bell Labs era: Shannon and the birth of the bit

The story starts not with compression but with communication. In the 1940s, Bell Telephone Laboratories -- a vast, strange campus in Murray Hill, New Jersey, partly funded by AT&T's monopoly revenues -- had a peculiar advantage: it could afford to hire people to think about problems that might not have immediate commercial value. Claude Shannon was one of those people.

Shannon was born in 1916 in a small Michigan town, the son of a judge and a teacher. He was mechanically gifted (he built a telegraph line to a friend's house using barbed-wire fencing) and mathematically brilliant, earning his doctorate at MIT in 1940 with a master's thesis -- on applying Boolean algebra to electrical circuits -- that is sometimes described as the most influential master's thesis of the 20th century. He joined Bell Labs the following year.

At Bell, Shannon had an unusual way of working. He juggled on a unicycle down the corridors. He built a device to solve the Rubik's Cube predecessor. He played chess against early computers and thought about machine learning before the phrase existed. But beneath the eccentricity was a searingly rigorous mind, and in 1948 he published "A Mathematical Theory of Communication" in two parts across the July and October issues of the _Bell System Technical Journal_.

#history[
  Shannon's 1948 paper was the founding act of information theory. We covered its technical content in Chapter 18 (entropy) and Chapter 19 (the source coding theorem): the connection between a symbol's probability and its ideal code length. But here the human context matters. Shannon built on earlier work by Harry Nyquist (1924, quantifying telegraph signal speed) and Ralph Hartley (1928, the Hartley measure of information). Shannon unified and vastly extended their ideas. He was also helped, in ways he generously acknowledged, by conversations with John von Neumann and Norbert Wiener. The word _bit_ -- binary digit -- appears in the paper, where Shannon credited it to John Tukey, a statistician at Princeton who had used it in an internal memo. Shannon's paper was so complete that almost nothing in its foundational structure has needed revision in 75 years.
]

Shannon also invented Shannon-Fano coding (independently, at the same time, with Robert Fano at MIT), though he knew it was suboptimal. The optimal prefix code -- the one you cannot do better than, for any fixed-length symbol probabilities -- would be found four years later by a 25-year-old MIT student trying to escape an exam.

== Huffman wins a bet

David Huffman was taking a graduate information theory course at MIT taught by Robert Fano in 1951. Fano gave students a choice: take a final exam, or write a term paper. Huffman chose the paper. His topic was: can you prove that Shannon-Fano coding is optimal, or find something better?

Huffman worked for months without progress, then nearly gave up and started studying for the exam. In one of those moments that researchers learn to treasure -- the flash of insight after you have stopped pushing -- he saw it. The correct strategy is to start from the _bottom_, assigning the two least probable symbols the two longest codes first, then merging them into a combined symbol and working _up_ the probability distribution to the root. Build the tree from the leaves, not from the root.

To see the trick in miniature, suppose four symbols occur with probabilities `A`=0.5, `B`=0.25, `C`=0.125, `D`=0.125. Huffman's recipe is mechanical: repeatedly take the two smallest probabilities, merge them into one node, and put the sum back. Merge `C` and `D` (0.125 + 0.125 = 0.25); now the pool is `A`=0.5, `B`=0.25, and the `CD` node=0.25. Merge `B` and `CD` (0.25 + 0.25 = 0.5); the pool is `A`=0.5 and the `BCD` node=0.5. Merge those two into the root. Read the branches off the tree and you get `A`=`0`, `B`=`10`, `C`=`110`, `D`=`111` -- average length $0.5(1) + 0.25(2) + 0.125(3) + 0.125(3) = 1.75$ bits, which is exactly the entropy of that distribution. No code can do better, and Huffman found it by always servicing the two rarest symbols first.

The resulting algorithm -- now simply called Huffman coding -- was provably optimal. No other prefix code can do better in expected code length, given the symbol probabilities. Huffman submitted his paper to Fano, who graded it and told him it was one of the finest student papers he had ever seen. Fano then helped Huffman publish it in the Proceedings of the IRE in 1952.

#aside[
  Fano had himself worked on the problem and had not found the optimal solution. His own Shannon-Fano method built codes from the top down, splitting probabilities, and was good but not optimal. So Huffman, a student, had done what the professor had not. Fano later said he included the problem on the assignment _because_ he knew it was unsolved and hoped a student might crack it. Whether that counts as generous or audacious -- or both -- depends on your point of view.
]

Huffman coding (Chapter 24) is still used today, in a canonical form that ensures unique decodability, inside JPEG, gzip, DEFLATE, and a dozen other formats. Huffman himself went on to a long career at MIT and then UC Santa Cruz, making contributions to digital circuit design. He died in 1999, quietly famous.

#gomaths("Why 'optimal' matters here")[
  When we say Huffman coding is _optimal_ among prefix codes, we mean: given a fixed probability distribution over symbols (say, `E` appears 12% of the time, `Z` appears 0.07% of the time), no other code that uses whole numbers of bits per symbol and is uniquely decodable can beat Huffman's average code length.

  The qualifier matters. A prefix code is constrained to use _whole_ bits per symbol: 1 bit, 2 bits, 3 bits, not 1.7 bits. The entropy $H(X) = -sum_i p_i log_2 p_i$ is not constrained to be a whole number. So there is always a small gap between Huffman's average length and the entropy, at most 1 bit per symbol. Arithmetic coding (Chapter 26) breaks the whole-bit constraint and can get arbitrarily close to $H(X)$. But Huffman is simpler, faster, and "optimal given the constraint," and that is good enough for most situations.
]

== IBM, Rissanen, and the arithmetic revolution

Through the 1960s and early 1970s, Bell Labs and IBM Research led most of the fundamental information-theory and coding work in industry. IBM had a different culture from Bell Labs -- more oriented toward computing hardware -- but it gave researchers extraordinary latitude, and several of the most important contributions to compression came from its Yorktown Heights research lab in New York.

Jorma Rissanen arrived at IBM Research from Finland in the early 1970s. He was a control theorist by training, interested in the problem of _modeling_: how do you tell, from data, which model of the world generated it? This question would eventually become the _Minimum Description Length_ principle (introduced in Chapter 23 and revisited in Chapter 61), which frames model selection as a compression problem. But Rissanen also made a more immediately practical contribution.

In 1976, working with a colleague named Glen Langdon, Rissanen published a description of _arithmetic coding_ -- a way of encoding a message into a single number in the interval $[0, 1)$, spending essentially $-log_2 p(x)$ bits for each symbol $x$, without being constrained to whole bits. (Richard Pasco had independently published a similar finite-precision version the same year.) Arithmetic coding had been sketched earlier by Shannon, but Rissanen and Langdon made it practical and clean. The 1979 paper "Arithmetic Coding" (_IBM Journal of Research and Development_) is the canonical reference. We use that coder in Chapter 26, essentially as they described it.

IBM then did something that would haunt compression for the next twenty years: it patented arithmetic coding aggressively. By the late 1980s, the IBM patent thicket included the QM-coder (US 4,905,297, granted February 1990), a related range-based implementation that JPEG's arithmetic mode was built on. Those patents meant the JPEG committee -- which knew arithmetic coding was about 10% more efficient than Huffman -- shipped JPEG with an optional arithmetic mode that almost nobody used, because the patent licensing was too complicated and too expensive.

The compression ecosystem spent a decade routing around those patents: gzip used Huffman only; bzip2's creator explicitly said he avoided arithmetic coding to dodge the patents. The IBM patents expired around 2007, too late to change the embedded Huffman infrastructure that had calcified in ten thousand implementations.

#history[
  Jorma Rissanen also invented MDL -- the Minimum Description Length principle -- in 1978 ("Modeling by Shortest Data Description," _Automatica_). MDL says: the best model is the one that gives the shortest description of the data _plus_ the description of the model itself. It is a formalization of Occam's razor in information-theoretic terms, and it quietly underpins how we think about regularization, model selection, and the deep connection between compression and machine learning. Rissanen worked at IBM Research for most of his career and died in 2020.
]

== Ziv and Lempel: the universality breakthrough

In 1977 and 1978, two Israeli mathematicians published two short, dense papers in the _IEEE Transactions on Information Theory_ that changed the field more than almost anything before or since.

Abraham Lempel and Jacob Ziv were at the Technion -- Israel Institute of Technology -- in Haifa. Their question was mathematical: is there a single compression algorithm that, without knowing anything about the statistical structure of the input, can nevertheless compress _any_ source to its entropy rate? Shannon had proved that you need $H(X)$ bits per symbol in the limit; could you achieve that limit _universally_, without a model?

The answer they found was yes, and the mechanism was surprisingly simple: a _sliding window dictionary_. Their 1977 paper described LZ77: look back in the recent past of the data, find the longest match to the current position, encode a pointer to that match. Their 1978 paper described LZ78: build an explicit trie dictionary of all substrings seen so far. Both algorithms are _universal_ -- Lempel and Ziv proved that, in the limit of large inputs, both converge to the source's entropy rate, for _any_ stationary ergodic source, without any prior model.

#mathrecall[
  A _stationary ergodic source_ (Chapter 28) is, in plain terms, a source whose statistical behaviour does not drift over time (_stationary_) and a long-enough single sample of which reveals those statistics (_ergodic_) -- so the frequencies you observe in one long stretch of output match the true probabilities. It is the mild assumption under which "learn the statistics from the data itself" provably works.
]

#keyidea[
  The Lempel-Ziv universality theorem (which we proved the intuition of in Chapter 28) is one of the deepest results in compression theory. It says: you do not need a probability model. The dictionary _becomes_ the model, implicitly, by remembering what appeared before. This is why gzip, bzip2, and zstd -- all LZ-family tools -- work reasonably on almost any file you throw at them, without being told what kind of file it is. They are model-free, yet they approach the entropy limit.
]

Lempel and Ziv were primarily theorists, not engineers. They were not trying to build a product. They were proving a mathematical theorem about the asymptotic behaviour of a class of algorithms. The practical impact came later, when others took their framework and built on it.

== Terry Welch and the LZW patent disaster

Terry Welch was a computer scientist at Sperry Corporation (later Unisys) who read the Lempel-Ziv papers and saw an engineering opportunity. The LZ78 algorithm required looking up a string in a dictionary and finding the longest match, which was slow on the hardware of the early 1980s. Welch simplified it: instead of arbitrary string matches, maintain a fixed-size code table where each entry is one symbol longer than its prefix. Encoding becomes a simple hash-table lookup. Decoding is fast and simple. He published this as "A Technique for High-Performance Data Compression" in _IEEE Computer_ in June 1984.

The algorithm -- which he called LZW, for Lempel, Ziv, and Welch -- was efficient enough to work in real-time on disk controllers, and it was quickly incorporated into the GIF format by CompuServe in 1987, then into TIFF and PostScript. It became ubiquitous.

Then, in December 1985, US Patent 4,558,302 was issued to Welch (assigned to Sperry). For a few years, nobody paid much attention. Then in December 1994, Unisys (which had merged with Sperry and inherited the patent) announced it would start collecting licensing royalties from companies that shipped software using GIF/LZW compression. The reaction was furious.

The web was exploding in 1994--1995. GIF was everywhere. Suddenly, the free Internet might owe licensing fees to a corporation that had nothing to do with building the web.

== PNG: the free alternative

Within months of the Unisys announcement, a working group of programmers from the Internet community -- using mailing lists and newsgroups as their tools -- designed and released PNG: the Portable Network Graphics format. PNG uses DEFLATE compression (see below), which is based on LZ77 and Huffman coding. Neither is patented in any way that would allow royalty collection on implementations. PNG also added an alpha channel (transparency) that GIF lacked. It became an Internet standard (RFC 2083) in March 1996.

The PNG episode is a perfect example of the way patent pressure in compression has repeatedly driven the field toward free alternatives -- not because the free alternatives are necessarily better, but because being free matters more than being best.

Unisys's GIF/LZW patent expired in 2003 in the United States. By then, PNG had won the web. Today, GIF survives only as a vehicle for short looping animations, a use-case it was never designed for.

== Phil Katz and the gzip era

Phil Katz was not an academic. He was a freelance programmer in Milwaukee, Wisconsin, who in the mid-1980s wrote a shareware compression utility called PKZIP that was dramatically faster than its competitors. He had a gift for low-level systems programming that made his implementations noticeably quicker than the incumbent tools.

In 1989, Katz designed the DEFLATE compression format for PKZIP 2.0. DEFLATE combines LZ77 (sliding-window dictionary coding) with Huffman coding in a specific, carefully engineered way. A DEFLATE stream first runs LZ77 to replace repeated strings with back-references, producing a mixed stream of literal bytes and (length, distance) pairs. That stream is then compressed with Huffman codes -- two separate Huffman trees, one for the literal/length values and one for the back-references, both transmitted in compact canonical form at the start of each block. The result is a format that is fast, practical, and compresses well on a wide range of inputs.

Katz released the DEFLATE specification publicly. Jean-Loup Gailly and Mark Adler implemented it as the open-source gzip tool (and the zlib library), which was standardized in RFC 1950, 1951, and 1952 in 1996. gzip became the universal lossless compressor of the Unix and Internet world, and DEFLATE became the compression algorithm inside gzip, zlib, PNG, ZIP files, and HTTP content-encoding. Twenty-five years later, it is still the most deployed lossless compression format on the planet by a wide margin.

#history[
  Phil Katz's story has a sad ending. He fought a legal battle with his former employer over the PKZIP code, which consumed years of his life and much of his income. He became reclusive and struggled with alcoholism. He died alone in a Milwaukee motel room in April 2000 at age 37. The compression community lost one of its most talented engineers, a man who had arguably done more for practical compression than anyone since Huffman, at an age when he should have had decades of work ahead of him.
]

== The Fraunhofer story: how MP3 was born

The human story of audio compression is very different from the data compression stories above. It begins with psychoacoustics -- the science of how the human auditory system actually perceives sound -- and with a West German engineer named Karlheinz Brandenburg who became obsessed with a question: how few bits do you actually need to represent music in a way that humans cannot distinguish from the original?

Brandenburg began his PhD work at the University of Erlangen-Nuremberg in 1977, the same year Ziv and Lempel published LZ77. His advisor was Dieter Seitzer, who had the idea of transmitting music over telephone lines -- a visionary and at the time laughable goal. The phone network had 64 kilobits per second available; a CD-quality stereo audio stream needs 1.4 megabits per second. You would need to compress audio by a factor of more than 20 while making it sound good.

Brandenburg spent the next fifteen years figuring out how. The key insight came from psychoacoustics: the ear does not hear all frequencies equally. If a loud sound is present at one frequency, the ear's hearing threshold rises at nearby frequencies -- the loud sound _masks_ the nearby quiet sounds. A compression system that exploits masking can throw away any sound that is already inaudible. This is not lossy compression in the sense of accepting degradation; it is compression that discards _perceptually zero_ information.

The tool for implementing this was the Modified Discrete Cosine Transform (MDCT), which we covered in Chapter 38. The MDCT takes a window of audio samples and transforms them into frequency-domain coefficients, with a special overlapping structure that avoids the blocking artifacts that simpler DCT approaches suffer. Brandenburg's group at Fraunhofer IIS (Fraunhofer Institute for Integrated Circuits) used MDCT coefficients, a psychoacoustic model to decide how many bits to spend on each frequency band, and Huffman coding for the quantized coefficients.

The result entered a long, painful standardization process. Brandenburg had to win over skeptics, navigate political fights between competing approaches, and repeatedly demonstrate that his codec sounded good on the most demanding test signals -- including a song by Suzanne Vega called "Tom's Diner" that he played obsessively as a stress test because it exposed encoding artifacts clearly. (The song was later nicknamed "the mother of MP3.")

#history[
  The MP3 standardization is a story of how long it takes to get a technology accepted even when it works. Brandenburg's work was essentially complete in the late 1980s, formalized in a proposal called ASPEC. The ISO MPEG committee did not finalize MP3 (formally: MPEG-1 Audio Layer III, ISO/IEC 11172-3) until 1992--1993. Brandenburg later said the committee process was one of the most draining experiences of his professional life. But without that process, the format might not have had the interoperability that let it spread so quickly once digital audio distribution became possible in the mid-1990s. Standards processes are slow and painful because they are trying to make something work for everyone -- which is the right goal even when the process is maddening.
]

MP3 spread through the late 1990s not because it was officially released, but because the Fraunhofer team made a poor-quality free encoder available and sold a high-quality licensed encoder. Teenager programmers in Germany and around the world built tools and shared them on early Internet sites. When Napster launched in 1999, MP3 was already the de facto standard.

Then Fraunhofer started enforcing its patents. In September 1998, Fraunhofer and its partner Thomson began issuing licenses and demanding royalties. This triggered the same response as the GIF/LZW crisis: engineers started working on alternatives. The Xiph.Org Foundation released Ogg Vorbis in 2000, a completely royalty-free MDCT-based codec. The MP3 patent era ended not with a single event but with a slow expiration of patents. In April 2017, the last relevant US MP3 patents expired, and Fraunhofer terminated its licensing program. MP3 became free -- and by then, streaming had largely replaced downloaded files anyway.

== Burrows, Wheeler, and the transform that came from nowhere

In 1994, two researchers at Digital Equipment Corporation's Systems Research Center (DEC SRC) in Palo Alto, California, published a technical report called "A Block-Sorting Lossless Data Compression Algorithm." The researchers were Michael Burrows (a systems researcher) and David Wheeler (one of the grand old men of computing, who had invented the subroutine and the Turing equivalence argument back in the 1950s at Cambridge).

The BWT, which we built from scratch in Chapter 35, is a bizarre-seeming operation: sort all rotations of the input string, then take the last column. The result is a permutation of the original data that has wonderful properties for subsequent compression: the sorted last column tends to cluster identical characters together, which LZ-family or run-length compression can exploit very effectively. The inverse transform recovers the original string exactly. There is no quality loss.

The BWT paper was unusual in the compression literature for two reasons. First, it was not published in a journal or conference -- it was a technical report from a corporate lab, available free. DEC SRC was then one of the finest industrial research labs in the world. Second, the BWT was immediately practical: a year later, Julian Seward implemented bzip2, a command-line compressor based on BWT + MTF + RLE + Huffman, and released it on July 18, 1996.

Seward chose Huffman coding (not arithmetic coding) explicitly because of the arithmetic coding patents. This was a completely rational engineering decision that illustrates the real cost of the IBM patent thicket: the technically superior algorithm was unavailable, so a slightly inferior one was used, and a whole generation of tools calcified around Huffman.

#gopython("Reading a historical Python example: BWT in eight lines")[
  The BWT is clean enough that you can implement it in a single Python function. We built the full production version in Chapter 35; here is the minimal version for understanding:

  ```python
  def bwt(s: str) -> str:
      """Burrows-Wheeler Transform of string s (adds sentinel '$')."""
      s = s + '$'                          # sentinel: smaller than any character
      rotations = sorted(s[i:] + s[:i] for i in range(len(s)))
      return ''.join(r[-1] for r in rotations)   # last column

  def ibwt(t: str) -> str:
      """Inverse BWT -- recovers original string (strips sentinel)."""
      table = [''] * len(t)
      for _ in range(len(t)):
          table = sorted(t[i] + table[i] for i in range(len(t)))
      return [row for row in table if row.endswith('$')][0][:-1]

  # Quick self-test
  original = "banana"
  transformed = bwt(original)
  recovered = ibwt(transformed)
  assert recovered == original
  print(f"BWT('{original}') = '{transformed}'")   # BWT('banana') = 'annb$aa'
  ```

  A `for` loop runs its body once for each element it iterates over. `sorted` returns a sorted list. `''.join(...)` glues a list of strings into one. That is all the Python you need to read this example. We covered these forms in Chapter 16.
]

David Wheeler died in 2004. Michael Burrows went on to work at Google, where he co-authored Bigtable. Their 1994 technical report has been cited thousands of times; the BWT is now also the foundation of all modern genome-alignment tools (Chapter 69), because its sorted-rotation structure enables _compressed full-text indexes_ that can search a genome without decompressing it.

== Ian Witten, Alistair Moffat, and the PPM tradition

Prediction by Partial Matching (PPM) was invented by John Cleary and Ian Witten at the University of Calgary in 1984. The idea, which we developed in Chapter 33, is to model the probability of the next character by looking at the last $k$ characters of context, using a hierarchy of context lengths and an escape mechanism to handle unseen strings.

Witten was a prolific and generous researcher who also (with Neal and Cleary) published the most widely read description of practical arithmetic coding (_Communications of the ACM_, 1987) -- the paper that taught most of the next generation of compression researchers how to actually implement an arithmetic coder. He and his students produced textbook after textbook on compression, information retrieval, and digital libraries.

Alistair Moffat, at the University of Melbourne, became the primary keeper of PPM through the 1990s, producing the PPMB, PPMC, and PPMD variants that progressively improved both compression ratio and speed. PPMD -- later refined by Dmitry Shkarin in Russia into PPMd (2002) -- became the gold standard for text compression ratio for many years and is still embedded in 7-Zip's archive formats.

The PPM tradition is an example of how academic researchers, spread across Australia, New Zealand, and Russia, built and maintained a line of work over two decades through pure interest and shared data structures, without a corporate lab or a major grant. The code was shared freely, the papers were written honestly about what worked and what did not, and the algorithms got steadily better.

== Matt Mahoney and the competitive fringe

Not all compression progress came from corporate labs or universities. One of the most persistent forces in compression improvement has been a small community of competitive individuals who develop context-mixing compressors in their spare time and compete on public benchmarks.

Matt Mahoney is the central figure here. A software engineer at Florida Institute of Technology and, later, Google, Mahoney has spent decades developing and publishing compression algorithms that blend multiple probabilistic models and mix their predictions. His 2000 paper "Fast Text Compression with Neural Networks" (AAAI FLAIRS) was one of the first serious efforts to use a neural network as a compression model -- more than a decade before "neural compression" became fashionable.

In 2002, Mahoney released PAQ1, the first in the PAQ series of context-mixing compressors. The PAQ family works by running many different models in parallel, each predicting the probability of the next bit, and combining their predictions through a weighted average (with weights updated based on which models have been accurate). Over hundreds of versions -- PAQ1 through PAQ8, then variations named by contributors including Knoll, Rhatushnyak, and others -- the PAQ family progressively pushed the boundary of what lossless compression could achieve.

Mahoney also maintains the _Large Text Compression Benchmark_ (LTCB) and the associated _enwik8_ and _enwik9_ datasets -- the first 100 million and 1 billion bytes, respectively, of an English Wikipedia dump. These became the canonical benchmarks for general-purpose text compression, giving the competitive community a shared yardstick.

Marcus Hutter, an AI researcher at IDSIA (and later Google DeepMind), noticed that the LTCB benchmark was a proxy for something deeper: to compress Wikipedia well, you need to understand it. In 2006 he founded the _Hutter Prize_, offering €50,000 (later raised to €500,000 for enwik9) to anyone who could beat the current record. In October 2024, the record was set by Kaido Orav and Byron Knoll with fx2-cmix at 110,793,128 bytes -- about 11% of the original one billion bytes.

#gomaths("What compressing to 11 percent actually means")[
  If we start with one billion bytes ($10^9$ bytes = 1 GB) and compress it to 110,793,128 bytes, the ratio is:

  $ "ratio" = 110793128 / 1000000000 approx 0.111 $

  That means the compressed version is about 11.1% of the original size -- equivalently, we are storing the original data in about $0.111 times 8 approx 0.89$ bits per byte, where the original bytes used 8 bits each. Since English text has an entropy of roughly 1 to 1.5 bits per character, getting to under 1 bit per byte is well into the territory where the model is doing real work.

  To put it in human terms: the winner has taught a compression program to understand enough about Wikipedia that it can predict what comes next well enough to store a billion characters in the space that would normally hold about 111 million characters.
]

== Jarek Duda and the ANS revolution from an unexpected place

In 2007, a mathematics PhD student in Krakow, Poland, posted a preprint to arXiv -- the physics and mathematics preprint server -- with a title that would have been incomprehensible to most compression engineers: "Asymmetric Numeral Systems." The author was Jaroslaw Duda, known as Jarek, then a graduate student at the Jagiellonian University.

Duda's idea, which we studied in Chapter 27, is a way to encode a stream of symbols, each drawn from a given probability distribution, into a single integer, in a way that matches arithmetic coding's compression ratio but runs at speeds closer to Huffman coding. The key insight is to represent the coder's state as a number in a range whose size encodes the current probability, and to update that number with simple table lookups. The result -- Asymmetric Numeral Systems, or ANS -- has two main flavors: rANS (range ANS) and tANS (tabled ANS).

Duda published, refined, and posted several versions of the paper between 2007 and 2013. He was not at a prestigious institution; he was not connected to the compression industry; his paper was on a preprint server rather than a refereed journal. For several years, almost nobody noticed.

Then Fabian Giesen, a programmer working on game-engine graphics (at RAD Game Tools), read the paper, understood it, and implemented it. Giesen posted a series of blog posts in 2013--2014 explaining ANS in plain terms, with working code, demonstrating that it was genuinely better than Huffman at comparable speed. The game-development and systems-programming communities read them.

Yann Collet was working at Facebook at the time, developing what would become Zstandard (zstd). He chose ANS as his entropy coder. The JPEG XL team (formerly Google's PIK project) chose ANS. Apple chose ANS for LZFSE. Suddenly, a theorem from a mathematics PhD student's preprint was the entropy-coding engine running inside billions of deployed devices.

#history[
  The ANS story has a disquieting coda about patents. In 2022, Microsoft was granted a US patent (US 11,356,122) on a modification of rANS, despite Duda's prior art. Duda had deliberately placed ANS in the public domain and had provided extensive prior-art documentation to try to block exactly this kind of patent. As of mid-2026, the patent has not been enforced aggressively, and the compression community has rallied around the prior-art arguments. But the episode illustrates that the patent-thicket problem has not been solved -- it keeps reappearing whenever a new algorithm achieves wide adoption.
]

== Yann Collet and Zstandard: compression as infrastructure

By 2013, it was clear that gzip, while ubiquitous, was old. It could not take advantage of modern multi-core processors. Its compression ratio was good but not excellent. Its speed was adequate but not impressive by 2013 standards. Facebook was compressing and decompressing enormous quantities of data -- stored data, in-transit data, binary logs -- and the overhead was real.

Yann Collet was a French programmer working at Facebook's Paris office. He had already released LZ4 in 2011, a codec that sacrificed compression ratio for extreme speed -- LZ4 is still one of the fastest compressors in existence, used when you need something closer to a memory-copy speed than a gzip speed. Now he turned to building something that combined good ratio with good speed.

Zstandard (zstd), released as version 1.0 in August 2016, does this by layering a sophisticated LZ77-based matcher (with a range of window sizes and hash tables at multiple granularities) under ANS entropy coding, with a dictionary-training interface that lets you pre-train on a sample of your data for much better ratios on short inputs. The result was a codec that, at its balanced settings, beats gzip's ratio and is several times faster. At its speed settings, it competes with LZ4 while offering much better compression.

Collet published zstd under a BSD license and contributed it to the Linux kernel (which it entered in version 4.14 in 2017) and to the IETF (RFC 8478 in 2018, updated RFC 8878 in 2021). Facebook uses it for nearly all its internal compression. Linux distributions use it for package compression.

The zstd story is a counterexample to the "lone outsider" pattern that shows up elsewhere in this chapter. Collet is a skilled engineer, but he had institutional support, access to real-scale testing data at Facebook, and time. The algorithm is not a mathematical breakthrough in the Lempel-Ziv or Shannon sense -- it is extremely good engineering, carefully calibrated against real workloads. That is a different kind of contribution, equally important and rather more reproducible.

== Johannes Balle and the neural turn

Johannes Balle arrived at Google Research (and later Google DeepMind) via a path that combined classical signal processing with neuroscience and machine learning. His 2016--2017 work on end-to-end optimized image compression, published at ICLR 2017 with Valero Laparra and Eero Simoncelli, changed what compression researchers thought was possible.

The core idea, which we developed in Chapters 56--58, is to replace every hand-designed component of an image codec -- the transform, the quantization step, the entropy model -- with learned neural components, and to train the entire pipeline jointly using a rate-distortion loss. The "rate" is the actual entropy of the quantized representation (estimated differentiably using a learned entropy model); the "distortion" is a difference measure between the original and reconstructed images. You set a Lagrange multiplier $lambda$ to trade between the two, and gradient descent finds the transforms and quantizers that minimize the combined cost.

#mathrecall[
  The Lagrange multiplier $lambda$ in $J = D + lambda R$ is the single "exchange rate" knob from rate--distortion optimization (Chapter 41): it says how many units of distortion $D$ you are willing to pay to save one bit of rate $R$. Turn $lambda$ up and the encoder spends fewer bits (smaller, blurrier); turn it down and it spends more (bigger, sharper).
]

Balle's 2018 follow-up (with Minnen, Johnston, Sung Jin Hwang, and Toderici), the _scale hyperprior_, added a second-level latent that captures spatial structure in the quantization noise, functioning like a side channel that tells the entropy coder where the image is complex versus smooth. The 2018 NeurIPS paper by Minnen, Balle, and Toderici added an autoregressive context model on top. Together these made learned image compression competitive with, and then better than, HEVC intra-coding on standard metrics.

#keyidea[
  Balle's insight was that the division between "the transform" and "the entropy coder" is artificial. They are both parts of the same objective: minimize the expected description length of the image. If you let gradient descent optimize all parts jointly, it finds better solutions than hand-designing them separately, because it can exploit structure that the hand-designer did not know to look for. The same idea now dominates learned video, audio, and point-cloud compression.
]

Balle has been generous in publishing code, datasets, and tutorials; the CompressAI toolkit (from InterDigital) and the TensorFlow Compression library are both influenced by or directly extend his work. He represents a new archetype in the field: the academic-industrial researcher who publishes openly, builds shared infrastructure, and moves a community rather than just a technique.

== Fabrice Bellard: the polymath's compression project

Fabrice Bellard is a French software engineer who has, over the course of roughly thirty years, built: FFmpeg (the foundational open-source multimedia processing framework), QEMU (a major open-source machine emulator), a fast $pi$-computing algorithm, a real-time H.264 encoder that ran on a 1 GHz CPU in 2011 when that was considered impossible, a JavaScript CPU emulator, a compact C compiler, and several other things that most engineers would consider the work of a lifetime each.

In 2019, Bellard turned his attention to neural lossless compression and released NNCP -- a neural network compressor for general data. Unlike the learned image codecs (which are specialized, lossy, and require GPU training), NNCP was a general-purpose, _lossless_ compressor that used a recurrent neural network (LSTM, at first) to predict the next byte, fed predictions to an arithmetic coder, and produced a smaller file than PAQ8 on some benchmarks while being a working tool rather than a research prototype. In 2021 he upgraded to a Transformer architecture; the result topped the Large Text Compression Benchmark.

In 2023 Bellard released ts_zip (text and source-code compressor), which uses a pre-trained LLM as the predictor. We studied this in Chapter 62. The tool is practical rather than state-of-the-art (the LLM is small enough to run locally in reasonable time), but it demonstrates the principle that a pre-trained general model can be repurposed as a compressor without any modification -- because it already _is_ a predictor, and prediction _is_ compression.

#aside[
  NNCP and ts_zip have a strict requirement that is easy to overlook: the encoder and decoder must use _exactly the same_ sequence of random numbers in _exactly the same_ order. Neural networks often use floating-point arithmetic, and floating-point arithmetic is notoriously hard to reproduce exactly across different hardware, operating systems, and library versions. A difference in the 17th decimal place of one multiply can propagate and cause the decoder to diverge completely from the encoder. Bellard spent considerable engineering effort ensuring deterministic arithmetic across platforms -- a requirement that has nothing to do with compression theory and everything to do with the practical engineering of lossless systems.
]

Bellard embodies an important tradition in compression: the generalist who arrives from outside the field, ignores conventions, solves the problem as a pure engineering challenge, and publishes the result because the obvious thing to do with a good tool is to give it away.

== The institutions: Bell Labs, IBM, DEC SRC, Fraunhofer IIS

The people above did not work alone. They were embedded in institutions that shaped what they worked on, what they had access to, and what they were allowed to publish.

*Bell Labs* (Murray Hill, New Jersey; later Holmdel) was the research engine of AT&T's telephone monopoly. Because AT&T was not allowed to compete in computing (a consequence of its 1956 consent decree with the US government), Bell Labs could afford to do fundamental research without worrying immediately about products. Shannon, Johnston, and dozens of others worked there under this unusually generous arrangement. When AT&T was broken up in 1984 and competitive pressure increased, Bell Labs' character changed. It still produces important work, but the era of unlimited blue-sky research ended.

*IBM Research* (Yorktown Heights, New York; Almaden, California; and global labs) operated under similar logic in the mainframe era: IBM had such dominant market share that it could fund researchers to think freely. Rissanen, Langdon, and the arithmetic-coding team worked here. IBM's decision to patent arithmetic coding aggressively was made by the legal department, not the researchers; Rissanen himself has expressed regret about the effect it had on the field.

*DEC SRC* (Palo Alto, California) was a smaller and arguably more intellectually pure lab. DEC (Digital Equipment Corporation) was the second-largest computer company in the world in the 1980s before being acquired by Compaq in 1998. SRC produced fundamental work on systems software, programming languages, and data structures. The Burrows-Wheeler paper is characteristic of its output: deep, surprising, and freely available. When DEC collapsed, many SRC researchers dispersed to Google, Microsoft, and academia, carrying the intellectual culture with them.

*Fraunhofer IIS* (Erlangen, Germany) is a German applied-research institute. Fraunhofer institutes are publicly funded but expected to generate revenue from licensing their technologies to industry. This dual mandate explains the MP3 story: Fraunhofer was under pressure to commercialize Brandenburg's work, which led directly to the patent licensing that drove the development of Vorbis and AAC.

== The pattern: outsiders, amateurs, and the long tail

Step back from the individual stories and a pattern emerges. Many of the most important contributions in compression came from:

- _People solving a different problem entirely_ (Shannon was studying communication, not compression; Huffman was writing a term paper; Duda was doing a PhD in mathematics).
- _People outside the mainstream of the field_ (Mahoney was an industrial engineer who did compression as a hobby project; Bellard arrived from systems programming and multimedia).
- _People in unexpected places_ (Duda in Krakow; the PPM tradition in Melbourne and Christchurch; bzip2 by Julian Seward as a solo project).
- _Adversarial selection_ -- patent pressure repeatedly drove the field toward free alternatives, and the free alternatives often ended up technically superior (PNG, Vorbis, AV1).

#misconception[
  "Compression research happens in large corporate labs with massive resources."
][
  Much of the most important compression work was done by individuals and small academic groups with modest resources. Shannon worked essentially alone on the 1948 paper. Huffman wrote his algorithm in the context of a student assignment. Duda published ANS from a preprint server. The PAQ series came from a global community of enthusiasts with consumer hardware. Large labs (Bell, IBM, Fraunhofer, Google) matter enormously, but they do not have a monopoly on fundamental contributions.
]

== A compressed timeline

The figure below places the major events on a single timeline, so you can see the rhythm of the field -- the bursts of activity, the gaps, the way new techniques build on each other with a decade or more of lag between theory and deployed tool.

#fig([Timeline of major milestones in data compression, 1948--2026. Events above the centreline are theoretical contributions; events below are practical tools and standards.], cetz.canvas({
  import cetz.draw: *

  let w = 13.0
  let yr(y) = (y - 1948) / (2026 - 1948) * w

  line((0, 0), (w + 0.3, 0), stroke: 0.7pt, mark: (end: ">"))

  for (y, lbl) in (
    (1948, "1948"), (1960, "1960"), (1977, "1977"),
    (1991, "1991"), (2007, "2007"), (2020, "2020"),
  ) {
    let x = yr(y)
    line((x, -0.1), (x, 0.1), stroke: 0.5pt)
    content((x, -0.25), anchor: "center", text(size: 6pt)[#lbl])
  }

  // Above-axis: theory
  let above-items = (
    (1948, "Shannon 1948"),
    (1952, "Huffman coding"),
    (1977, "LZ77/LZ78"),
    (1984, "PPM / Arithmetic"),
    (2007, "ANS (Duda)"),
    (2017, "Learned codecs"),
  )
  for (i, (y, lbl)) in above-items.enumerate() {
    let x = yr(y)
    let h = 0.40 + calc.rem(i, 2) * 0.30
    line((x, 0.0), (x, h), stroke: (paint: blue.lighten(30%), thickness: 0.5pt))
    content((x, h + 0.10), anchor: "center", text(size: 5.8pt, fill: blue.darken(20%))[#lbl])
  }

  // Below-axis: practice
  let below-items = (
    (1984, "LZW/GIF"),
    (1991, "gzip/DEFLATE"),
    (1993, "MP3"),
    (1994, "BWT/bzip2"),
    (2002, "PAQ series"),
    (2016, "zstd"),
    (2023, "LLM compress"),
  )
  for (i, (y, lbl)) in below-items.enumerate() {
    let x = yr(y)
    let h = 0.35 + calc.rem(i, 2) * 0.28
    line((x, 0.0), (x, -h), stroke: (paint: orange.darken(10%), thickness: 0.5pt))
    content((x, -(h + 0.10)), anchor: "center", text(size: 5.8pt, fill: orange.darken(30%))[#lbl])
  }
}))

#gopython("Building a simple timeline in Python")[
  A clean way to represent this history in code is as a list of tuples. Each tuple holds a year, a short label, and a category. Then you can sort, filter, and display them.

  ```python
  # A minimal compression timeline as data
  # Each entry: (year, label, category)
  type Timeline = list[tuple[int, str, str]]

  milestones: Timeline = [
      (1948, "Shannon entropy theorem", "theory"),
      (1952, "Huffman coding", "theory"),
      (1977, "LZ77 (Ziv & Lempel)", "theory"),
      (1984, "LZW in GIF", "practice"),
      (1987, "Arithmetic coding paper", "theory"),
      (1991, "DEFLATE / gzip (Katz)", "practice"),
      (1993, "MP3 standardized", "practice"),
      (1994, "BWT (Burrows & Wheeler)", "theory"),
      (1996, "bzip2 released", "practice"),
      (2002, "PAQ1 (Mahoney)", "practice"),
      (2007, "ANS (Duda)", "theory"),
      (2016, "zstd v1.0 (Collet)", "practice"),
      (2017, "Learned image codecs (Balle)", "theory"),
      (2019, "NNCP (Bellard)", "practice"),
      (2023, "LLM as compressor", "theory"),
  ]

  # Print theory milestones in chronological order
  theory = [(y, lbl) for y, lbl, cat in milestones if cat == "theory"]
  for year, label in sorted(theory):
      print(f"{year}: {label}")
  ```

  A _list comprehension_ (the `[... for ... in ... if ...]` form) builds a new list by filtering and transforming an existing one. `sorted` returns the list in ascending order. We covered these forms in Chapter 16.
]

== Why history matters: the lag between theory and deployment

The compression field is not only a technical story. It is a political and economic story about who controls the ability to efficiently represent information. Patents have repeatedly created crises (GIF, MP3, arithmetic coding, ANS) and repeatedly driven the creation of free alternatives (PNG, Vorbis/Ogg, gzip, AV1). Standards bodies have both accelerated progress (MP3 would have been an academic curiosity without ISO/IEC adoption) and slowed it (the patent disputes around H.265/HEVC fractured the standards landscape in ways that drove the formation of the Alliance for Open Media and the creation of AV1).

Looking across the history, one striking regularity appears: a major technique takes 5 to 15 years from academic publication to widespread deployment. Shannon 1948 to gzip 1991: 43 years, but that included building the entire digital communications industry first. Huffman 1952 to JPEG 1992: 40 years, but JPEG required not just Huffman but DCT, quantization, psychovisual models, and a standards committee. ANS 2007 to zstd 2016: 9 years. Learned codecs 2017 to first deployed products 2022+: roughly 5 years. The lag is getting shorter as the engineering ecosystem matures, but it has never reached zero.

#checkpoint[
  Name three examples from this chapter where patent pressure led directly to the development of a free alternative. For each, state what was patented, what free alternative was created, and roughly when.
][
  (1) LZW in GIF/TIFF: Welch's LZW patent (1985, held by Unisys) enforced in 1994, which led to PNG using DEFLATE, released 1996. (2) Arithmetic coding (IBM patents, 1988--1990) caused gzip and bzip2 to use Huffman only through the 1990s; when patents lapsed around 2007, ANS had already emerged as the successor. (3) MP3 (Fraunhofer/Thomson licensing from 1998) triggered the development of Ogg Vorbis (2000, Xiph.Org) as a royalty-free MDCT audio codec.
]

The people in this chapter were not all heroic figures working purely for the common good. Shannon's work was funded by a telephone monopoly trying to squeeze more calls onto copper wires. Fraunhofer was a government-funded research institute that behaved like a patent licensor once its algorithm became valuable. IBM's arithmetic-coding patents were a genuine obstacle to the field for twenty years. These are human institutions, with human incentives, and compression did not escape those forces.

At the same time: Shannon did not benefit personally from information theory the way a startup founder benefits from a product. Huffman wrote a term paper. Duda posted a preprint. Mahoney maintains a website and a benchmark. The compression community has an unusually strong tradition of giving away the work, of measuring against shared standards, and of building on each other's ideas openly. That tradition is worth naming and worth preserving.

#takeaways((
  [Compression was built by a chain of people across seven decades, each solving a specific problem: Shannon (how little information does a source contain?), Huffman (what is the optimal prefix code?), Lempel and Ziv (can one algorithm work on any source?), Rissanen (can we get arbitrarily close to entropy?), Welch and Katz (can this work fast on real hardware?), Brandenburg (can we compress audio to near-perceptual transparency?), Burrows and Wheeler (can a sorting operation enable better compression?), Mahoney and Duda (can we push the ratio further with smarter statistics?), Collet (can we have good ratio and good speed simultaneously?), Balle and Bellard (can neural models improve on hand-designed systems?).],
  [Patents have repeatedly been the central political force in compression: the GIF/LZW crisis created PNG; the arithmetic-coding patents shaped gzip and bzip2 around Huffman; the MP3 patents created Vorbis and AAC; the ANS patent threats remind us the problem is not solved.],
  [The most important research came from unexpected places: an MIT term paper, a preprint server in Poland, a solo open-source project in England, a hobbyist community running benchmarks from home computers. Institutional prestige correlates weakly with compression impact.],
  [Bell Labs, IBM Research, DEC SRC, and Fraunhofer IIS each played a defining role at a specific moment, and their institutional incentives shaped what got published, patented, and licensed.],
  [The open-source and open-standards tradition -- from gzip to bzip2 to AV1 to zstd -- is not merely ethical; it is also technically productive, because open code gets tested, improved, and built upon by far more people than proprietary code.],
  [Every major compression breakthrough has had a lag of five to fifteen years between the technical publication and widespread deployment. Understanding this lag helps calibrate expectations for today's neural compression research.],
))

== Exercises

#exercise("76.1", 1)[
  Shannon published his foundational paper in 1948. Huffman published the optimal prefix-code algorithm in 1952. Explain in two or three sentences why a four-year gap makes sense: what did Shannon prove, and what question did it leave open that Huffman answered?
]
#solution("76.1")[
  Shannon proved that the entropy $H(X)$ is both a lower bound and an achievable target for average code length -- but he did not give a practical algorithm that achieves it for a given probability distribution. The Shannon-Fano code (which Shannon and Fano co-developed around 1948--1950) is a reasonable heuristic but is provably not always optimal. Huffman's 1952 paper gave an efficient, correct algorithm (build the tree bottom-up, merging the two least probable symbols at each step) and proved it achieves the minimum average code length among all prefix codes. The gap between the existence proof -- that the minimum equals $H(X)$ -- and a constructive polynomial-time algorithm is exactly what Huffman filled.
]

#exercise("76.2", 1)[
  The IBM arithmetic-coding patents (issued around 1988--1990) caused gzip and bzip2 to use Huffman coding even though arithmetic coding would have been somewhat more efficient. What is the approximate cost of this choice in bits per symbol, and why did engineers accept this cost?
]
#solution("76.2")[
  Huffman coding is within 1 bit per symbol of the entropy $H(X)$, but cannot reach $H(X)$ exactly because it must use whole numbers of bits per symbol. Arithmetic coding can get arbitrarily close to $H(X)$, typically achieving within a tiny fraction of a bit per symbol. For English text, the practical gap is on the order of 0.01--0.1 bits per symbol, depending on the context model. Engineers accepted this because the alternative -- paying patent royalties to IBM for the arithmetic-coding implementation -- was more costly than the efficiency gap, especially for open-source tools that had no revenue from which to pay royalties.
]

#exercise("76.3", 2)[
  Jarek Duda published ANS on a physics preprint server as a mathematics PhD student in 2007, and the paper was largely unnoticed for several years. Identify at least three factors from this chapter that explain why an important technical contribution can take years to achieve wide adoption.
]
#solution("76.3")[
  (1) _Institutional prestige and visibility_: Duda was a PhD student at a non-elite institution, and a mathematics preprint server reaches a different audience than the systems-programming and compression communities. A paper from Google or Bell Labs would have been noticed immediately; a preprint from Krakow took longer to propagate. (2) _Translation to practice_: The theoretical insight (ANS is fast and near-optimal) needed an engineer -- Fabian Giesen -- to implement it clearly, test it, and publish accessible explanations before the broader community could evaluate it. The lag between theory and practice is structural. (3) _Incumbent inertia_: Huffman coding and arithmetic coding were both well-understood, well-implemented, and embedded in existing standards. There is a real cost to switching, even if the new technique is superior. (4) _Patent risk_: After the arithmetic-coding patent experience, compression engineers were cautious about adopting new entropy-coding techniques without confidence about the patent landscape.
]

#exercise("76.4", 2)[
  The chapter describes three distinct institutional models for compression research: (a) a corporate monopoly lab (Bell Labs / IBM Research), (b) a government-funded applied-research institute (Fraunhofer IIS), and (c) individual open-source contributors (Mahoney, Duda, Seward, Collet, Bellard). For each model, state one structural advantage and one structural disadvantage relative to the others, and give a specific example from the chapter.
]
#solution("76.4")[
  (a) _Corporate monopoly lab_: Advantage -- very long time horizons and ability to hire the best researchers without commercial pressure. Example: Shannon's 1948 paper was possible because Bell Labs could let him think freely for years. Disadvantage -- intellectual property is owned by the corporation and may be patented aggressively. Example: IBM's arithmetic-coding patents blocked a superior entropy-coding method for nearly two decades. (b) _Government-funded applied institute_: Advantage -- sustained, long-term project funding and close industry collaboration. Example: Fraunhofer IIS funded Brandenburg's decade-long MP3 development. Disadvantage -- dual mandate (public funding + commercial licensing) creates incentive to enforce patents even at the cost of ecosystem harm. Example: Fraunhofer's 1998 MP3 licensing enforcement triggered the Ogg Vorbis reaction. (c) _Individual open-source contributors_: Advantage -- no patent overhead, immediate worldwide distribution, and improvement by many contributors. Example: gzip (Gailly and Adler implementing Katz's DEFLATE spec) became the universal Unix compressor. Disadvantage -- no guaranteed sustained funding; contributors may move on. Example: Phil Katz died at 37 and PKZIP's development effectively died with him.
]

#exercise("76.5", 3)[
  The chapter observes that major techniques take 5--15 years from publication to widespread deployment. Using the specific examples of (i) LZ77 (1977) and gzip (1991), and (ii) ANS (2007) and zstd (2016), calculate the actual lags in years. Then argue: does this lag indicate a problem with how the compression field disseminates its findings, or is a lag of this magnitude structurally inevitable? Support your argument with evidence from the chapter.
]
#solution("76.5")[
  (i) LZ77 was published in 1977; gzip (using DEFLATE, an engineered LZ77 + Huffman scheme) was released in 1991. Lag: 14 years. Note that intermediate steps existed (PKZIP 1989, DEFLATE spec 1991). (ii) Duda posted the first ANS preprint in 2007; zstd v1.0 shipped in 2016. Lag: 9 years. A reasonable answer could argue either position: _problem_ view -- the field's fragmentation across academia, industry, and hobbyist communities creates translation barriers; a paper on a physics preprint server is invisible to compression engineers; better interdisciplinary channels would shorten the lag. _Structurally inevitable_ view -- the lag reflects time needed for (a) mathematical refinement (the 2007 ANS paper needed years of revisions before it was clean enough to implement confidently), (b) engineering work to make theory practical (Giesen's 2013--2014 blog posts were the engineering translation), and (c) ecosystem adoption (Collet's zstd built trust through years of benchmarking at Facebook). No amount of faster communication can eliminate the time needed to do these things well.
]

== Further reading

- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon 1948] -- Read the original paper. It is surprisingly accessible and does not require more mathematics than a motivated reader of this book possesses. The prose is elegant.

- #link("https://ieeexplore.ieee.org/document/4051119")[Huffman 1952] -- The original paper is short (five pages) and contains the full proof of optimality.

- #link("https://ieeexplore.ieee.org/document/1659158")[Welch 1984] -- The LZW paper is readable and shows exactly what practical engineering problem Welch was solving.

- #link("https://www.cs.jhu.edu/~langmea/resources/burrows_wheeler.pdf")[Burrows & Wheeler 1994] -- The original DEC SRC technical report; DEC released it freely and it has circulated unchanged for 30 years.

- #link("https://arxiv.org/abs/0902.0271")[Duda 2009] -- The original ANS preprint. The 2013 version (arXiv:1311.2540) is the one most implementors worked from.

- #link("https://www.mattmahoney.net/dc/text.html")[Mahoney's Large Text Compression Benchmark] -- Still active; the rankings, descriptions, and Mahoney's own notes form a living archive of thirty years of competitive compression.

- #link("http://prize.hutter1.net/")[The Hutter Prize] -- The prize's history page documents every record and contestant since 2006.

- #link("https://bellard.org/nncp/")[Bellard's NNCP page] -- Short, characteristically spare documentation of the NNCP and ts_zip tools.

- #link("https://arxiv.org/abs/1611.01704")[Balle et al. 2017] -- The paper that started end-to-end learned image compression.

#bridge[
  This chapter has been about the people. The next chapter -- Chapter 77, "Patents, Standards, and the Politics of Formats" -- is about the systems those people operated within: the patent offices, the ISO and IETF standards processes, the industry consortia, and the advocacy organizations (like Xiph.Org and the Alliance for Open Media) that have shaped which algorithms got standardized, which got locked up, and which got freed. If this chapter taught you _who_ built compression, Chapter 77 will teach you _how the rules of the game_ shaped what got built.
]
