#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Information, Data, and Symbols

#epigraph[
  The word is not the thing, the map is not the territory, and the data is not the message.
][Alfred Korzybski, _Science and Sanity_, 1933]

Imagine you receive a telegram. It reads: "ALL WELL STOP LETTER FOLLOWS." Eight words — a handful of ink marks on yellow paper. But something invisible traveled with those marks, from the sender's hand to your eyes, and that invisible thing changed what you knew about the world. _What exactly was transmitted?_

Not ink. Not paper. Not even the specific shapes of the letters — those are just an agreement between you and the telegraph company, a code so familiar you forget it's a code. What was transmitted was *information*: the resolution of your uncertainty about someone's wellbeing. The ink and paper were just *data* — a physical carrier. And the letters and spaces were *symbols* — agreed-upon marks in a shared *alphabet*.

This chapter sorts out what those three words actually mean, why they are different things, and why that difference is the single most important idea before we can talk about compression at all. No formulas yet — just the conceptual landscape, built from everyday examples. By the time we're done you will see redundancy not as wastefulness but as a handle that compression can grip.

#recap[
  In Chapter 1 we saw that compression is fundamentally about removing redundancy from data. In Chapter 2 we swept through the historical arc, from Morse code to neural codecs. Now we slow down and ask the foundational question: before we compress anything, we need to understand what "data" actually *is* — what it's made of, how it carries meaning, and where redundancy hides inside it.
]

#objectives((
  [Explain what a symbol, an alphabet, a message, and a code are — and why these concepts are distinct.],
  [Describe the difference between a signal and a representation, and between analog and digital.],
  [Name at least five kinds of redundancy hiding in a typical text file.],
  [Articulate why redundancy is not always bad, and give one real example where it saves you.],
  [Give an intuitive (no-formula) explanation of what information content means.],
))

== Signs, Symbols, and Alphabets

Before bits and bytes, before computers, humans developed a remarkable technology for transmitting thought across space and time: *writing*. At its core, writing is a system of marks — *signs* — that carry agreed-upon meanings. A sign becomes a *symbol* the moment a community of people agrees that it stands for something. The letter "A" is a black wedge shape pressed onto white paper; it means nothing to someone who hasn't been taught that community's agreement. It's pure symbol: shape by convention, meaning by consensus.

#definition("Symbol")[
  A *symbol* is a mark, sound, gesture, or any distinguishable thing that a community has agreed will stand for something else. A symbol has two faces: its *form* (the physical mark) and its *meaning* (what it stands for). A compression algorithm cares only about the form — the meaning is irrelevant to it.
]

An *alphabet* is a finite set of symbols that a system uses. The English alphabet has 26 letters. The decimal system's alphabet is $\{0, 1, 2, 3, 4, 5, 6, 7, 8, 9\}$ — ten digits. A computer's most basic alphabet is $\{0, 1\}$ — just two symbols, called *bits*. An emoji keyboard is an alphabet with thousands of symbols.

#note[
  Those curly braces are just shorthand for "the collection of these things, listed once each, order doesn't matter": $\{0, 1\}$ is read aloud as "the set containing 0 and 1". That bundle is called a *set*, and we will study sets properly in Chapter 6. Here we only ever use them to write down an alphabet, so you can read $\{dots\}$ as "the alphabet consisting of" and lose nothing.
]

#keyidea[
  Compression doesn't care about *meaning* — it cares about *form*. Whether `A` means the first letter of the English alphabet or represents a musical note or is a blood type designation is completely irrelevant to a compressor. A compressor sees only a sequence of symbols drawn from an alphabet, and asks: how can I represent this sequence with fewer symbols from some other (usually binary) alphabet?
]

A *message* is a sequence of symbols chosen from an alphabet. "HELLO" is a message in the alphabet $\{A, B, \ldots, Z\}$. The binary string `01001000 01000101` is a message in the alphabet $\{0, 1\}$. Messages can encode other messages — that's what codes are for.

#definition("Code")[
  A *code* is a systematic rule for mapping each symbol (or group of symbols) in one alphabet to one or more symbols in another alphabet. Morse code maps each letter to a sequence of dots and dashes. ASCII maps each character to a 7-bit binary number. A compression algorithm is just a code that tries to make the output message *shorter than* the input message — at least on average.
]

=== The Map Is Not the Territory

Here's a subtlety that trips up beginners: data and the thing it represents are not the same. A photograph of a fire is not hot. A map of a city is not a city. A medical scan is not a body. Data is always a *representation* — a model of something real, constructed according to some set of choices about what to measure, how precisely, and how to encode the result.

Those choices matter enormously for compression. Consider a doctor's thermometer:

- The thermometer's mercury column is a *signal*: a physical quantity (height of mercury) that *varies continuously* with temperature.
- If you read off "37.2°C", you have made a *measurement*, converting that continuous signal into a *number*.
- If you type that number into a computer as the text string `"37.2"`, you have *encoded* it as four ASCII characters: 51, 55, 46, 50 in decimal — 32 bits total.
- If instead you store it as a 16-bit integer in units of tenths-of-a-degree (372), you use only 16 bits.
- Or you could use a single 8-bit integer if you only care about whole degrees (37) — 8 bits.

Same information (roughly). Very different data. A compressor works on the data, not the underlying reality, and so the encoding choices made *before* the compressor sees the data already determine a lot about how compressible it will be.

#aside[
  This is why domain knowledge matters in compression. A seismic sensor array might record ground motion at 1000 samples per second, 32-bit floating point, on hundreds of channels — a firehose of data. But seismologists know that ground motion is mostly correlated across nearby sensors, changes slowly compared to the sampling rate, and has a strong frequency structure. A compressor that exploits those facts (like the scientific floating-point codecs we'll study in Chapter 66) can crush the data far more than a general-purpose tool that knows none of this.
]

== Analog Versus Digital

The mercury thermometer illustrates the first great divide in data: *analog* vs. *digital*.

*Analog* means continuous. Temperature, sound pressure, electrical voltage, light intensity — these quantities can take any value within a range, with infinite possible values between any two. The world as physics experiences it is predominantly analog.

*Digital* means discrete — limited to a finite set of possible values. The digits 0 through 9 are digital. A light switch is digital (on or off). A single bit is maximally digital: only two possible values.

The step from analog to digital is called *sampling* and *quantization*:

- *Sampling* means measuring the value at specific moments in time (or positions in space), rather than tracking it continuously. A CD samples audio 44,100 times per second.
- *Quantization* means rounding each measured value to the nearest value in a finite set. A CD stores each audio sample as a 16-bit integer, which means there are exactly $2^(16) = 65,536$ possible volume levels.

#gomaths("Powers of two — counting how many things bits can name")[
  The little raised number is an *exponent*: $2^(16)$ means "multiply 2 by itself 16 times". It is just repeated multiplication, written compactly. $2^1 = 2$, $2^2 = 2 times 2 = 4$, $2^3 = 2 times 2 times 2 = 8$, and so on, doubling at each step: $16, 32, 64, dots, 65536$ at $2^(16)$.

  Why does this exact pattern keep appearing? Because each *bit* (a single 0-or-1 choice) doubles the number of distinct things you can name. One bit names $2$ things; two bits name $2 times 2 = 4$ (`00`, `01`, `10`, `11`); $N$ bits name $2^N$ things. So $N$ bits give you exactly $2^N$ possible values — and that is why a 16-bit sample has $2^(16) = 65{,}536$ possible levels.

  We build exponents properly in Chapter 4 (number systems) and Chapter 7 (exponents and logarithms); for now you only need "exponent = repeated multiplication, and $N$ bits = $2^N$ values".
]

#fig(
  [Turning a smooth analog waveform into digital data: the wave is sampled at equally-spaced instants (vertical arrows), and each sample is rounded to the nearest of the $2^N$ quantization levels (horizontal dashes). The result is a sequence of integers.],
  cetz.canvas({
    import cetz.draw: *
    // Draw axes
    line((0, 0), (9, 0), mark: (end: "stealth", fill: black), name: "xaxis")
    line((0, -0.3), (0, 3.3), mark: (end: "stealth", fill: black), name: "yaxis")
    content((9.2, 0))[$t$]
    content((0.2, 3.4))[$A$]
    // Draw smooth sine-like curve
    bezier((0.2, 1.5), (1.5, 3.0), (0.8, 3.2), (1.2, 3.0))
    bezier((1.5, 3.0), (3.0, 0.3), (2.2, 2.0), (2.6, 0.6))
    bezier((3.0, 0.3), (4.5, 2.8), (3.6, 0.1), (4.0, 2.5))
    bezier((4.5, 2.8), (6.0, 0.5), (5.1, 2.8), (5.5, 0.6))
    bezier((6.0, 0.5), (7.5, 2.4), (6.5, 0.5), (7.0, 2.2))
    bezier((7.5, 2.4), (8.5, 1.2), (7.9, 2.5), (8.2, 1.4))
    // Quantization level lines (dashed)
    set-style(stroke: (dash: "dashed", paint: gray, thickness: 0.5pt))
    line((0.1, 0.5), (8.8, 0.5))
    line((0.1, 1.0), (8.8, 1.0))
    line((0.1, 1.5), (8.8, 1.5))
    line((0.1, 2.0), (8.8, 2.0))
    line((0.1, 2.5), (8.8, 2.5))
    line((0.1, 3.0), (8.8, 3.0))
    // Sample arrows at regular intervals
    set-style(stroke: (dash: "solid", paint: rgb("#0b5394"), thickness: 1pt))
    for x in (1.5, 3.0, 4.5, 6.0, 7.5) {
      line((x, 0), (x, 0.3), mark: (end: "stealth", fill: rgb("#0b5394")))
    }
    // Sampled points
    set-style(stroke: none, fill: rgb("#0b5394"))
    for (x, y) in ((1.5, 3.0), (3.0, 0.5), (4.5, 3.0), (6.0, 0.5), (7.5, 2.5)) {
      circle((x, y), radius: 0.1)
    }
    // Labels
    content((0.55, 0.5), text(size: 7pt)[$q_1$])
    content((0.55, 1.5), text(size: 7pt)[$q_3$])
    content((0.55, 2.5), text(size: 7pt)[$q_5$])
    content((0.55, 3.0), text(size: 7pt)[$q_6$])
  })
)

Why does analog-to-digital conversion matter for compression? Because *every digital representation already contains choices that create or destroy compressibility*:

- A higher sampling rate (more samples per second) captures more detail but produces more data — and more of it will be correlated with neighboring samples, which means *more structure for a compressor to exploit*.
- Finer quantization (more bits per sample) gives smoother values — but human ears and eyes can only tell the difference down to some limit, after which the extra bits are pure waste.
- *Lossy* compression often works by reversing some of the quantization: it accepts a coarser, noisier representation in exchange for far fewer bits. More on this when we reach audio and image codecs in Volume III.

#checkpoint[
  A sound engineer records audio at 96 kHz / 24-bit instead of the CD standard 44.1 kHz / 16-bit. By roughly what factor does the raw data size increase?
][
  Sampling rate ratio: $96000 / 44100 approx 2.18$. Bit depth ratio: $24/16 = 1.5$. Total factor: $2.18 times 1.5 approx 3.27$. So the file is about three times bigger before any compression. A good lossless audio codec will shrink both, but a 24-bit/96kHz file will always start bigger.
]

== What Is Information?

We've established that data is a sequence of symbols and that those symbols are just agreed-upon marks. Now comes the harder question: what's the *information content* of a message?

Here's a thought experiment. Your friend sends you two texts:

1. "The sun rose this morning."
2. "Your exam results just posted — you passed!"

Both are messages. Both use roughly the same number of symbols. But which one carries more *information*? Intuitively, the second one — because you weren't sure whether you'd passed, and now you know. The first one carries almost no information, because you were already certain the sun would rise.

This insight is the heart of information theory: *information is the resolution of uncertainty.* A message carries a lot of information if it tells you something you didn't know. It carries no information if it tells you something you already knew for certain.

#definition("Information content (informal)")[
  The *information content* of a message is proportional to how surprised you were when you received it. Common events are unsurprising; they carry little information. Rare events are surprising; they carry a lot of information. A certain event (probability 1) carries *zero* information. An impossible event (probability 0) carries infinitely many — but of course it never arrives.
]

We'll make this precise with logarithms and probability in Chapters 9 and 18. For now, keep the intuition: *the rarer, the richer*.

=== The Twenty-Questions Game

Here's a beautiful way to make "information" concrete. Play "Twenty Questions": I'm thinking of a number from 1 to 1024. You get to ask yes/no questions. If you ask "Is it greater than 512?" and I say yes, you've cut the possibilities in half. Each perfect yes/no question cuts the remaining possibilities in half. After 10 questions (because $2^(10) = 1024$), you can pin down any of the 1024 numbers exactly.

So 1024 equally-likely numbers need exactly 10 bits of information to identify. If instead you chose from just 2 numbers, 1 question (1 bit) suffices. If you chose from 4 numbers, 2 questions (2 bits). The pattern: $N$ equally-likely possibilities require $log_2(N)$ bits to identify.

#gomaths("Logarithms — the key to measuring information")[
  A *logarithm* is the inverse of exponentiation. If $2^(10) = 1024$, then $log_2(1024) = 10$. In general, $log_2(N)$ asks: "to what power do I raise 2 to get N?"

  Concretely: $log_2(2) = 1$, $log_2(4) = 2$, $log_2(8) = 3$, $log_2(32) = 5$, $log_2(1) = 0$.

  When probabilities appear, we use $log_2(1/p)$ — the log of the *reciprocal* of the probability. A very likely event has $p$ close to 1, so $1/p$ is close to 1, so $log_2(1/p)$ is close to 0: small information content. A rare event has small $p$, so $1/p$ is large, so $log_2(1/p)$ is large: big information content. This is exactly the surprise-equals-information idea, made mathematical.

  One handy shorthand you will see later in this very chapter: dividing by something equals negating its logarithm, so $log_2(1/p) = -log_2(p)$. For example $log_2(1/0.5) = log_2(2) = 1$, and equally $-log_2(0.5) = -(-1) = 1$. Both ways of writing it mean the same "one bit of surprise". (We prove this rule in Chapter 7; here just trust the two forms are equal.)

  We'll build logarithms from scratch in Chapter 7; you don't need to calculate them yet.
]

Now notice: the number of bits you *need* to encode a message is related to the number of equally-likely possibilities you might receive. If your friend can only ever say one of 4 things, you need at most 2 bits to encode each message. If they can say any of $10^6$ possible things, you need about 20 bits ($2^(20) approx 10^6$). The more possibilities, the more bits — and this is *exactly* why compression is possible: real messages don't use all possibilities equally, and some are far more likely than others.

=== Symbols Aren't All Created Equal

Return to the telegram alphabet: 26 letters (we'll ignore case for simplicity), a space, and a few punctuation marks — call it a 32-symbol alphabet. If every sequence of symbols were equally likely, we'd need 5 bits per symbol ($2^5 = 32$). A 1,000-character telegram would require 5,000 bits.

But real English text is wildly non-uniform:

- The letter *E* appears about 12.7% of the time; *Z* appears about 0.07%.
- The letter *Q* is almost always followed by *U*.
- The word "the" appears in almost any paragraph; the word "syzygy" might never appear.

These patterns mean that real English has far less than 5 bits per character of genuine information content. Shannon estimated in 1951 (by having humans guess the next letter of printed English) that English text has roughly *1 to 1.5 bits per character* of true information content. That means a 1,000-character telegram contains perhaps 1,200 bits of actual information — but we're storing it in 8,000 bits (as ASCII). The other 6,800 bits are *redundancy*.

Compression's job is to find that redundancy and remove it.

== Redundancy: The Enemy (and Friend) of Compression

*Redundancy* means saying the same thing more than once — using more symbols than the minimum necessary to convey your information. This sounds wasteful, and for a file you want to store, it is. But before we declare war on redundancy, we should understand it properly, because not all redundancy is the same kind.

#definition("Redundancy")[
  *Redundancy* is the difference between how many bits a message actually uses and the minimum number of bits that would be *sufficient* to convey the same information (given a perfect compressor and a perfect model of the source). A file with zero redundancy cannot be compressed further without losing information.
]

=== Five Kinds of Redundancy

Real data sources display at least five distinct kinds of redundancy, and different compression algorithms attack different ones:

*1. Symbol-frequency redundancy.* Some symbols appear far more often than others. In English text, `e`, `t`, `a`, `o`, `i`, `n`, `s` are far more common than `q`, `x`, `z`. If you use the same fixed number of bits for every symbol (like ASCII uses 8 bits for every character), you're wasting bits on the common ones and spending exactly the right number on the rare ones. The fix is to use shorter codes for common symbols and longer codes for rare ones — exactly what Huffman coding (Chapter 24) does.

*2. Sequential (n-gram) redundancy.* Adjacent symbols are not independent. In English, after `q` comes almost certainly `u`. After `th` comes very likely `e`. After "the " comes usually a noun or adjective. A code that ignores this context and treats each symbol independently misses all this structure. Arithmetic coding with a context model (Chapters 26, 33) can exploit it.

*3. Long-range repetition.* Long passages of text repeat phrases, words, and patterns seen much earlier. "The quick brown fox" might appear on page 2 and again on page 200. Dictionary coding (Chapters 28–31) finds these repeated matches and replaces them with short references: "see earlier occurrence at offset X, length Y."

*4. Structural / format redundancy.* File formats often contain boilerplate, headers, metadata, and fixed-layout fields that are mostly the same across files of the same type. A JPEG file always starts with the bytes `FF D8 FF`; a ZIP file always starts with `PK\x03\x04`. A compressor that knows the format can exploit this.

*5. Perceptual / semantic redundancy.* Human eyes can't see the difference between two very similar shades of blue. Human ears can't hear a quiet sound that happens simultaneously with a loud one at the same pitch. Images and audio contain enormous amounts of detail that is, for practical purposes, invisible or inaudible to humans. *Lossy* compression (Chapters 37–55) exploits this kind of redundancy — it discards information, but information the receiver doesn't care about.

#keyidea[
  Each redundancy type requires a different computational tool to exploit:
  - *Frequency redundancy* → variable-length symbol codes (Huffman, ANS)
  - *Sequential redundancy* → context modeling (arithmetic coder + probability model)
  - *Long-range repetition* → dictionary / match-and-copy (LZ77, LZ78, LZMA)
  - *Format redundancy* → preprocessors and filters (specific to each format)
  - *Perceptual redundancy* → transform + quantization (DCT, wavelets, masking models)

  The most powerful compressors combine multiple tools in a pipeline, attacking different redundancy types in sequence.
]

=== When Redundancy Is Your Friend

Redundancy isn't always your enemy. Consider:

- *Error correction.* QR codes are about 30% redundant so that even if part of the code is torn or dirty, the scanner can still recover the data. CDs use Reed–Solomon error-correction codes that can survive entire scratches. More redundancy means more resilience.
- *Human communication.* English has enormous redundancy — which is why we can understand someone speaking in a noisy coffee shop, or read a message full of typos. "Th qck brwn fx" is immediately parseable. If human speech had zero redundancy, any noise would make it unintelligible.
- *Cryptography.* A one-time pad with a truly random key produces ciphertext that has zero redundancy (maximum entropy) — it looks like pure noise. This is both what makes it unbreakable and what makes it unattractive for compression: you can't compress random data.

#misconception[
  "If we could just remove all redundancy from our data, we'd have the best possible compression."
][
  True for a fixed source — but in practice, *some* redundancy is always present in the *compressed* output because our model of the source is imperfect. And even the ideal compressor must leave a hard floor of bits per symbol — the genuine information content of the source itself, which is _not_ redundancy and cannot be removed without losing the message. (Chapter 18 gives this floor a name, the *entropy*, written $H(X)$, and Chapter 19 proves it really is a floor.) What compression removes is only the *excess* above that floor.
]

== Codes and Representations

We've been using the word "code" loosely. Let's be more precise. A *representation* is a specific way of encoding a set of possible messages as sequences of symbols in a chosen alphabet. Different representations of the same information differ in:

- *Efficiency*: how many symbols they use on average.
- *Uniqueness*: whether every message has exactly one representation.
- *Decodability*: whether you can recover the original message from the representation without ambiguity.

#fig(
  [Three different representations of the same 5-letter alphabet $\{A, B, C, D, E\}$. Fixed-length codes use 3 bits per symbol; a simple Huffman-style code assigns shorter codes to more frequent symbols; a broken code (prefix-ambiguous) cannot be decoded unambiguously.],
  cetz.canvas({
    import cetz.draw: *
    // Table structure
    content((1.5, 4.2), text(weight: "bold", size: 9pt)[Symbol])
    content((3.5, 4.2), text(weight: "bold", size: 9pt)[Fixed (3 bits)])
    content((6.0, 4.2), text(weight: "bold", size: 9pt)[Variable (good)])
    content((8.5, 4.2), text(weight: "bold", size: 9pt)[Broken])
    line((0.2, 4.0), (9.8, 4.0), stroke: 0.8pt)
    let rows = (
      ("A (40%)", "000", "0",    "0"),
      ("B (26%)", "001", "10",   "01"),
      ("C (16%)", "010", "110",  "10"),
      ("D (12%)", "011", "1110", "110"),
      ("E ( 6%)", "100", "1111", "1110"),
    )
    for (i, row) in rows.enumerate() {
      let y = 3.3 - i * 0.65
      content((1.5, y), text(size: 8.5pt)[#row.at(0)])
      content((3.5, y), text(size: 8.5pt, font: "DejaVu Sans Mono")[#row.at(1)])
      content((6.0, y), text(size: 8.5pt, font: "DejaVu Sans Mono")[#row.at(2)])
      content((8.5, y), text(size: 8.5pt, font: "DejaVu Sans Mono")[#row.at(3)])
    }
    line((0.2, 0.7), (9.8, 0.7), stroke: 0.5pt + gray)
    content((1.5, 0.35), text(size: 8pt, style: "italic")[Avg bits/sym])
    content((3.5, 0.35), text(size: 8pt)[3.00])
    content((6.0, 0.35), text(size: 8pt)[2.24])
    content((8.5, 0.35), text(size: 8pt)[? (broken)])
  })
)

The "variable (good)" column in the figure above encodes `A` (the most common symbol) with just 1 bit, while `E` (the rarest) needs 4 bits. The average bits per symbol works out to about 2.24 — a significant saving over the fixed 3 bits. And crucially, the code is *decodable*: you can read a stream of bits and always know where one symbol ends and the next begins.

Watch the "good" code decode the stream `0101111` with no spaces or markers — just bits arriving one at a time. Read `0`: that is a complete codeword, `A`, so emit `A`. Read `1`: not yet any codeword. Read `0`: now `10` is exactly `B`, emit `B`. Read `1`, `1`, `1`, `1`: that is `1111`, exactly `E`, emit `E`. Result: `A B E`, recovered uniquely with nothing but the bits. The trick is that the moment you have read a complete codeword you _know_ you are done, because no codeword is the start of a longer one — `0` can never be the beginning of `10`, `110`, `1110`, or `1111`.

The "broken" column lacks exactly this property. There, `0` codes `A` but is also the first bit of `01` (`B`), so when the decoder reads a `0` it cannot tell whether the symbol is finished or just beginning. Faced with `01`, it has no way to know whether you meant `B`, or `A` followed by the start of `C` (`10`) — the stream is genuinely ambiguous, and that is why we marked its average length "broken": a code you cannot decode has no useful length at all.

This decodability requirement has a mathematical name: a code must be a *prefix-free code* (also called a *prefix code*). We'll make this rigorous in Chapter 19. For now: no valid codeword can be the beginning of any other valid codeword.

#gopython("Variables in Python")[
  Python lets you store and name values with simple assignment statements. A *variable* is just a name bound to a value. Here we store symbol frequencies and print them:

  ```python
  freq_A = 0.40   # A appears 40% of the time
  freq_E = 0.06   # E appears only 6% of the time
  total = freq_A + freq_E
  print(f"A + E together: {total:.0%}")  # prints: A + E together: 46%
  ```

  The `f"..."` notation is an *f-string* — a string that evaluates expressions inside `{}`. The `:0%` part formats the number as a percentage. We'll build on Python slowly from Chapter 15 onward; for now just read the code for meaning rather than trying to run it.
]

=== A Worked Example: Encoding the Word "BANANA"

Let's make redundancy concrete with a tiny example. Suppose we want to encode the word "BANANA" — six letters from the alphabet $\{A, B, N\}$.

*Step 1: Count the symbols.*

#table(
  columns: (1fr, 1fr, 1fr),
  table.header([Symbol], [Count], [Fraction]),
  [A], [3], [3/6 = 50%],
  [N], [2], [2/6 = 33%],
  [B], [1], [1/6 = 17%],
)

*Step 2: Fixed-length encoding.*

Three symbols need $log_2(3) approx 1.58$ bits to distinguish them. Since we must use whole bits, a fixed-length code needs 2 bits per symbol:

- A → `00`, N → `01`, B → `10`
- "BANANA" → `10 00 01 00 01 00` = 12 bits

*Step 3: Variable-length encoding.*

A is most common, so give it the shortest code:

- A → `0` (1 bit), N → `10` (2 bits), B → `11` (2 bits)
- "BANANA" → `11 0 10 0 10 0` = 9 bits

We just saved 3 bits — a 25% reduction — on a 6-character message, with no loss of information, just by using shorter codes for more frequent symbols. On a million-character document the savings would be proportional: roughly 25% smaller.

*Step 4: What's the theoretical minimum?*

The true information content of "BANANA" (given these frequencies) is approximately:

- $A$: each `A` contributes $-log_2(0.5) = 1$ bit of information.
- $N$: each `N` contributes $-log_2(0.333) approx 1.58$ bits.
- $B$: `B` contributes $-log_2(0.167) approx 2.58$ bits.

Total: $3 times 1 + 2 times 1.58 + 1 times 2.58 = 3 + 3.16 + 2.58 = 8.74$ bits.

Our variable-length code used 9 bits — just 0.26 bits above the theoretical minimum! Perfect encodings of 6 symbols are hard to squeeze because you can't use fractional bits. But encode a million BANANAs and you'll converge very close to the minimum.

== The Many Faces of Data

Up to now we've spoken as if data were always text. In reality, computers store many kinds of data, and each has different structure, different redundancy, and different compressibility.

=== Text

Text data is sequences of characters. English text in ASCII or UTF-8 has rich n-gram structure (some letter sequences are far more common than others), strong long-range repetition (boilerplate, repeated phrases), and typically compresses 60–75% with general-purpose tools.

But not all "text" is English prose. Source code compresses even better (lots of repeated keywords and structural patterns). Random Base64 data disguised as text is nearly incompressible. The file extension `.txt` tells you the encoding, not the compressibility.

=== Images

An image is a 2D grid of *pixels*. Each pixel has a color — usually represented as three numbers for red, green, and blue intensity. A 1920×1080 full-HD image has $1920 times 1080 = 2,073,600$ pixels, and at 3 bytes (24 bits) per pixel, it takes about 6 MB of raw storage.

Real images are enormously redundant:
- *Spatial correlation*: neighboring pixels are almost always similar in color. A blue sky image has millions of pixels all close to the same shade of blue.
- *Block repetition*: textures repeat; walls, grass, and fabric have repeating patterns.
- *Perceptual limits*: very fine high-frequency detail (tiny variations at the pixel level) is largely invisible to the human eye.

A PNG file (lossless) might compress that 6 MB image to 3–4 MB. A JPEG file (lossy) might compress it to 300 KB — a 20× reduction — with no visible quality difference at normal viewing distances.

=== Audio

Audio is a sequence of amplitude samples — typically 44,100 or 48,000 times per second, stored as 16-bit or 24-bit integers. One second of stereo CD audio is $44100 times 2 times 2 = 176,400$ bytes. Silence or simple tones are extremely redundant (nearly constant or highly periodic values). Complex music with rich textures is less redundant — but even then, psychoacoustic models (Chapter 46) reveal that much of what's in the waveform is inaudible.

=== Video

Video is simply a sequence of images, displayed fast enough to create the illusion of motion. At 24 frames per second, full-HD, the raw data rate is $24 times 6 "MB" = 144 "MB/s"$. That's nearly 500 GB per hour — utterly impractical to store or stream without compression. Video is the most demanding compression problem in everyday use.

The redundancy in video comes from two dimensions:
- *Spatial*: within each frame, nearby pixels are correlated (just like in still images).
- *Temporal*: between consecutive frames, most of the image is unchanged. The background of a news broadcast stays constant while only the newsreader's lips and hands move.

Modern video codecs (H.264, AV1, AV2) exploit both kinds simultaneously, achieving compression ratios of 100× or more over raw video — the engineering that makes streaming services possible.

=== Structured / Tabular Data

Databases, spreadsheets, scientific datasets. These often have columns where every value is an integer in a small range, or a repeated category label, or a slowly-changing number. Columnar compression schemes (Chapter 67) exploit the structure of one column at a time, often achieving enormous ratios.

=== Random Data

At the extreme opposite end: truly random data. A file of bytes produced by a cryptographically secure random number generator has *no* redundancy whatsoever. Every bit is independent of every other, every value is equally likely, and no compressor can make it smaller. In fact, trying to compress random data typically makes it *slightly larger* (because any compression format has a header). We'll prove this mathematically in Chapter 8 using a counting argument — it's one of the most elegant results in the field.

#misconception[
  "A good compressor should be able to compress anything."
][
  No compressor can compress *all* inputs. For every algorithm that makes some files shorter, there must exist files that get *longer* (or stay the same size). This isn't a limitation of any particular algorithm — it's a mathematical theorem. The counting argument goes like this: there are $2^N$ possible files of $N$ bits. If compression mapped all of them to files shorter than $N$ bits, those outputs would have to come from a smaller set — but there aren't enough shorter strings to be a one-to-one mapping for all inputs. We'll see this proven in Chapter 8.
]

== Codes Everywhere: A Few Historical Examples

Humans have been encoding information into compact forms long before computers. A quick tour gives context for why the ideas in this book are ancient and why they matter.

=== Morse Code (1837–1844)

Samuel Morse and Alfred Vail developed what would become Morse code beginning in the late 1830s. The system assigns sequences of short dots and long dashes (called "dits" and "dahs") to letters and digits. E — the most common letter in English — gets just a single dot. T — second most common — gets a single dash. Z, Q, and other rarities get four-element sequences.

This is *variable-length coding* — exactly what Huffman would formalize a century later. Morse arrived at short codes for common letters by the pragmatic means of counting letters in a printer's type-case (more type meant more frequent use) — a practical frequency analysis.

Morse code was designed for a two-symbol channel (short pulse / long pulse, or mark / space) with timing. It is not uniquely decodable from the bits alone — you also need the timing gaps between symbols to tell letters from words. This ambiguity was acceptable for skilled operators but would be fatal in a computer file format.

#history[
  *Morse's frequency trick.* Morse and Vail reportedly determined the relative frequency of English letters by visiting a local newspaper office and counting the number of type pieces in each letter's case. More type → more frequent use → shorter code. The letter E, most common, got one dot. The letter Z, least common, got four dashes and a dot. This is the world's first recorded instance of frequency-based variable-length coding, predating Huffman's formal proof of optimality by more than a century.
]

=== Braille (1824)

Louis Braille, blinded at age three in an accident in his father's workshop, developed the Braille writing system by 1824. Braille uses a $2 times 3$ grid of raised dots — six positions each either raised or flat — to encode 64 possible symbols (2^6). The system is essentially a fixed-length binary code: 6 bits per character. Its efficiency isn't its point; its point is that fingers can read it at high speed, even though the encoding is inefficient by compression standards.

Braille illustrates that *the optimal encoding depends on the receiver*. For eyes, variable-length visual symbols (letters of different widths and shapes) are efficient. For fingers, a fixed-size tactile grid is efficient. Compression algorithms make the same tradeoff: the "right" encoding is the one that works for the decoder.

=== Teleprinter Codes (1870–1960)

Emile Baudot's 1870 five-bit code (later standardized as ITA-2) encoded 32 characters using a five-bit fixed-length code. This was used in telegraphs and teletype machines worldwide. The 5-bit limit (32 symbols) required two shift states (letters shift and figures shift) to encode both letters and numbers — an early example of *context switching* in a code.

The Baudot code was explicitly designed for simplicity of mechanical implementation, not for compression efficiency. It predates the concept of entropy by 78 years.

=== ASCII (1963) and Unicode (1991–)

By the early 1960s, the need for a standard computer character encoding was clear. ASCII (American Standard Code for Information Interchange, 1963) assigned 7-bit codes to 128 characters: 26 uppercase letters, 26 lowercase letters, 10 digits, common punctuation, and 33 control codes. Using 7 bits for every character, regardless of frequency, is maximally simple — and maximally inefficient. An `E` and a `Z` waste the same number of bits.

ASCII served well for English, but excluded virtually all other human writing systems. Unicode (version 1.0 in 1991, with UTF-8 encoding standardized in 1993) addressed this by defining code points for over 143,000 characters as of 2023, covering 154 writing systems. UTF-8 is variable-length: the most common characters (ASCII range) use 1 byte; less common characters use 2, 3, or 4 bytes. This is again the compression insight applied: common things get shorter representations.

As of 2025, UTF-8 accounts for over 98% of all text on the web, according to W3Techs. The 1993 decision to use variable-length encoding has paid enormous dividends.

#aside[
  Unicode Emoji are a telling example of competing pressures. Each emoji is a single code point (like U+1F600 for 😀) and in UTF-8 occupies 4 bytes — as much as four ASCII characters. In compressed text this barely matters, but in raw form it means a single "😊" costs 4× as much as "A". Social media platforms and messaging apps deal with this by compressing message payloads.
]

== How Compressors See Your File

Pull everything together. When a compression algorithm receives your file, it sees:

1. A sequence of *symbols* (usually bytes: values 0–255) drawn from a fixed *alphabet*.
2. No knowledge of what those bytes "mean" — no access to the domain, the context, the intent.
3. Only statistical patterns in the sequence itself.

The algorithm's job is to find a shorter sequence in some output alphabet (again usually bytes) that, together with the *decoder algorithm*, is sufficient to reconstruct the original sequence exactly (for lossless compression) or acceptably (for lossy).

Every technique in this book is an answer to: "What pattern in the data can I exploit to shorten the sequence?" The answer depends on:

- What *kind* of redundancy is present (frequency? sequential? repetitive? perceptual?).
- How much *memory* the algorithm can use to model the past.
- How much *computation* is acceptable (encoding is often slow; decoding must be fast).
- Whether *any* information loss is permitted.

#gopython("A Python 'histogram' — counting symbol frequencies")[
  Before compressing anything, we need to know how often each symbol appears. The Python `dict` type (a dictionary — a map from keys to values) is perfect for counting:

  ```python
  def histogram(data: bytes) -> dict[int, int]:
      """Count how many times each byte value appears."""
      counts: dict[int, int] = {}
      for byte in data:            # 'data' is a sequence of integers 0-255
          if byte in counts:
              counts[byte] += 1    # seen before: increment count
          else:
              counts[byte] = 1     # first time: set count to 1
      return counts

  # Try it:
  msg = b"BANANA"              # b"..." is a bytes literal in Python
  h = histogram(msg)
  for symbol, count in sorted(h.items()):
      print(f"byte {symbol} ({chr(symbol)}): {count} times")
  # Output:
  # byte 65 (A): 3 times
  # byte 66 (B): 1 times
  # byte 78 (N): 2 times
  ```

  Notice that `byte 65` is the ASCII code for 'A' — the computer sees the number 65, not the letter. This is exactly how a compressor sees your text: as a stream of integers. The `chr()` function converts an integer back to the character it represents in ASCII/Unicode.
]

=== The Running Sample

Throughout this book we'll compress the same short passage to demonstrate each technique's effect. Here is our running sample — a 400-character excerpt from Lewis Carroll's _Through the Looking-Glass_ (1871, long out of copyright):

```text
'Twas brillig, and the slithy toves
Did gyre and gimble in the wabe:
All mimsy were the borogoves,
And the mome raths outgrabe.
"Beware the Jabberwock, my son!
The jaws that bite, the claws that catch!
Beware the Jubjub bird, and shun
The frumious Bandersnatch!"
```

Raw (UTF-8): approximately 380 bytes. In Chapter 24 we'll apply Huffman coding and watch the bytes shrink for the first time.

#scoreboard(
  caption: "Our running sample — before any compression",
  [Raw UTF-8], [380], [1.00×], [Baseline; no compression applied yet],
)

== The Compression Pipeline in Plain English

Most practical compressors aren't a single idea — they're a *pipeline* of ideas, each attacking a different kind of redundancy:

*Stage 1: Preprocessing / transformation.* Rearrange the data to make patterns more obvious. The Burrows-Wheeler Transform (Chapter 35) sorts the data so identical contexts cluster together. The Discrete Cosine Transform (Chapter 38) turns an image's spatial data into frequency components. Delta coding replaces absolute values with the difference from the previous value.

*Stage 2: Modeling.* Estimate the probability of each next symbol, given the symbols seen so far. A simple model might just count how often each byte appeared. A sophisticated model might look at the last dozen bytes and use a large table of conditional probabilities. The better the model, the less bits the coder needs.

*Stage 3: Entropy coding.* Given a model (probabilities), assign short bit patterns to likely events and long patterns to unlikely ones. Huffman coding (Chapter 24), Arithmetic coding (Chapter 26), and ANS (Chapter 27) are the main tools here.

*Stage 4: Postprocessing / framing.* Add a header, checksums, metadata — enough for the decoder to reconstruct the original.

The model stage is where almost all the interesting competition happens. Every improvement in compression over the past 75 years has been primarily an improvement in modeling — in building a better probability estimate for what comes next. The entropy coder then converts that estimate into bits, and the best possible entropy coder (arithmetic or ANS) does it nearly perfectly. So the compressor that wins is the one with the best model.

This is the deep reason why, as we'll discuss at length in Chapters 23 and 62, large language models are also excellent compressors: they are, above all, excellent models of what comes next.

#keyidea[
  The pipeline is: *transform → model → entropy-code*. Every lossless compressor follows this structure, explicitly or implicitly. The entropy coder (Huffman, arithmetic, ANS) is a solved problem — it perfectly converts probabilities into bits. The competition is entirely in the modeling stage. Better model = shorter compressed file.
]

== What This Chapter Has Built

You've now got the conceptual scaffolding for everything that follows:

- *Symbols, alphabets, messages, codes* — the vocabulary of the field.
- *Analog vs. digital* — how real-world quantities become sequences of bits.
- *Information as surprise* — rare events carry more information than common ones.
- *Five kinds of redundancy* — the targets compression attacks.
- *The pipeline* — transform, model, entropy-code.
- *Codes are trade-offs* — efficiency vs. simplicity vs. error-resilience.

We haven't seen a single compression algorithm yet. But every algorithm you'll encounter over the next 78 chapters is an answer to one question: *where is the redundancy, and how can we efficiently model it away?*

#takeaways((
  [A *symbol* is any agreed-upon mark; an *alphabet* is a finite set of symbols; a *message* is a sequence of symbols; a *code* maps one alphabet to another.],
  [Data is always a *representation* — the same information can be encoded in many different ways with very different sizes.],
  [*Analog* signals are continuous; *digital* signals are discrete. Sampling and quantization convert one to the other, with choices that affect compressibility.],
  [*Information content* is proportional to surprise: rare events carry more information than common ones.],
  [Real data has at least five kinds of redundancy: frequency redundancy, sequential redundancy, long-range repetition, structural/format redundancy, and perceptual redundancy.],
  [Redundancy is bad for storage but good for error correction and human communication — it's a resource to be managed, not simply eliminated.],
  [No compressor can compress *all* inputs: for any algorithm, some inputs must get longer. This is a mathematical theorem, not an engineering limitation.],
  [The compression pipeline is: transform → model → entropy-code. The competitive stage is *modeling* — better probability estimates = shorter output.],
))

== Exercises

#exercise("3.1", 1)[
  You have an alphabet of 8 equally likely symbols. How many bits does a fixed-length code need per symbol? Now suppose one symbol appears 50% of the time and the other seven share the remaining 50% equally. Describe (in words, no formula) which symbols should get shorter codes in a variable-length scheme, and why.
]
#solution("3.1")[
  A fixed-length code for 8 symbols needs $log_2(8) = 3$ bits per symbol. For the skewed distribution, the one symbol that appears 50% of the time should get the shortest code (even 1 bit) because it appears so often that saving bits on it has a huge overall effect. The seven rare symbols (each appearing about 7.1% of the time) can afford longer codes because they rarely appear. On average, this scheme uses fewer bits than 3 per symbol.
]

#exercise("3.2", 1)[
  Consider the message "AABABBA". Using only the symbols in this message and the frequencies you observe, write a variable-length prefix code (no symbol's code may begin with another symbol's code) that uses fewer bits than a fixed 2-bit code would. Show your encoding of the full message and count the bits.
]
#solution("3.2")[
  The message "AABABBA" has: A appears 4 times (57%), B appears 3 times (43%). A fixed 2-bit code uses $7 times 2 = 14$ bits. Assign A → #raw("0") (1 bit), B → #raw("1") (1 bit). Then "AABABBA" → #raw("0 0 1 0 1 1 0") = 7 bits. This is prefix-free (trivially, as both codes are 1 bit). An even better code isn't possible here since both symbols need at least 1 bit. Total: 7 bits vs. 14 — a 50% reduction.
]

#exercise("3.3", 2)[
  A camera produces RAW files where each pixel is a 14-bit integer. The camera's marketing claims this gives "beautiful detail". A friend argues that you should save in 8-bit JPEG instead because "14 bits is overkill." From a redundancy perspective, who is right, and why might both be right or wrong depending on the use case? Think about: sensor noise, the final display medium, post-processing needs, storage costs.
]
#solution("3.3")[
  Both are right in different contexts. 14-bit RAW contains more dynamic range information — useful for post-processing (recovering shadows/highlights) and for printing large formats. But a typical display can only show 8–10 bits of dynamic range, and the human eye distinguishes only about 8 bits of luminance under typical conditions. The extra bits in 14-bit data represent headroom for processing, not perceptual benefit on screen. From a pure storage-vs-quality-on-screen perspective, JPEG at appropriate quality captures all the visually relevant information at 1/5 to 1/20 the size. But for professional editing workflows, 14-bit RAW is standard because it preserves the latitude for color grading and exposure correction.
]

#exercise("3.4", 2)[
  In the "BANANA" example we encoded 6 characters in 9 bits (variable code) vs. 12 bits (fixed code). The theoretical minimum was approximately 8.74 bits. Explain in plain English why we can't always achieve *exactly* the theoretical minimum when encoding a single short message.
]
#solution("3.4")[
  The theoretical minimum (entropy) is a real number — in this case 8.74. But bits come in whole numbers, and every symbol in a prefix code must be encoded with a whole number of bits. The minimum we can assign to A (the most likely symbol) is 1 bit; but its theoretical contribution is exactly $-log_2(0.5) = 1$ bit, so A is perfectly encoded. N's theoretical share is $1.58$ bits, but we must use 2 — 0.42 bits wasted per N. B's theoretical share is 2.58 bits, but we use 2 — actually 0.58 bits *saved* per B. On a very long message, these small overages and savings average out to near-zero. On a short message of 6 characters, the averaging hasn't happened yet, so we're stuck a bit above the floor. Arithmetic coding can overcome this by encoding multiple symbols together, approaching the floor much more closely.
]

#exercise("3.5", 3)[
  *Coding challenge.* Write a Python function #raw("symbol_frequencies(text: str) -> dict[str, float]") that takes a string and returns a dictionary mapping each unique character to its fraction of the total characters (so the fractions sum to 1.0). Then, call it on the Jabberwocky sample and print the 5 most common and 5 least common characters. (You don't need to run it — write the code and trace through it by hand for a short test string like "ABBA".)
]
#solution("3.5")[
  ```python
  def symbol_frequencies(text):
      counts = {}
      for ch in text:
          counts[ch] = counts.get(ch, 0) + 1
      total = len(text)
      return {ch: count / total for ch, count in counts.items()}

  # Hand trace for "ABBA":
  # After loop: counts = {'A': 2, 'B': 2}
  # total = 4
  # Result: {'A': 0.5, 'B': 0.5}
  ```
  For the Jabberwocky excerpt, the most common characters would likely be space and the letter e, t, a, h; least common would be uppercase letters and rare letters like x, q, z.
]

== Further Reading

- #link("https://people.math.harvard.edu/~ctm/home/text/others/shannon/entropy/entropy.pdf")[Shannon, C.E. (1948). "A Mathematical Theory of Communication."] The founding paper. Section 1 introduces symbols, sources, and entropy in roughly the same order as this chapter, but with mathematical precision. Surprisingly readable.

- #link("https://archive.org/details/bstj30-1-50")[Shannon, C.E. (1951). "Prediction and Entropy of Printed English."] The paper where Shannon estimated English text has ~1–1.5 bits per character of true information content, using human predictors. A beautiful experiment in information theory.

- #link("https://www.unicode.org/versions/Unicode15.1.0/")[The Unicode Standard, Version 15.1.] The authoritative reference on character encoding. Chapter 2 ("General Structure") explains the design decisions behind Unicode and UTF-8's variable-length scheme.

- #link("https://home.mit.bme.hu/~kollar/papers/morse-history.pdf")[Beauchamp, K.G. (2001). "History of Telegraphy."] Chapter 4 covers the development of Morse code and Baudot codes, with the historical context of how engineers arrived at variable-length codes before information theory existed.

#bridge[
  We now know what data is, what redundancy is, and why it can be removed. Before we can talk about *how* to remove it, we need the mathematical foundation that underpins everything: *number systems*. Computers represent all symbols — text, images, audio, video — as sequences of 0s and 1s. To understand any compression algorithm, you must be comfortable converting between binary, decimal, and hexadecimal, and understanding what a "byte" actually contains. That's Chapter 4.
]
