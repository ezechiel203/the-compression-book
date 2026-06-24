#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Patents, Standards, and the Politics of Formats

#epigraph[
  The best compression algorithm in the world is worthless if nobody is allowed to use it.
][Anonymous engineer, circa 1994]

Imagine you are an engineer in 1994. You have just added a beautiful feature to your software: it can now display GIF images, those little animated pictures that everyone loves. Then, on Christmas Eve, you open your email and find a letter from a company called Unisys. They own a patent on the compression technique buried inside every GIF file, and they want you to pay them money (retroactively) for every copy of your software you have ever shipped. Merry Christmas.

This is not a hypothetical. It happened, and it changed the internet. The story of compression is not just a story of clever algorithms. It is also a story of lawyers, committees, lobbyists, and corporate strategies, and the slow realization that a mathematical idea locked behind a patent can shape which technologies billions of people use. This chapter is that story.

#recap[
  Volume II taught us the algorithms: Huffman coding (Chapter 24), arithmetic coding (Chapter 26), LZ77 and LZ78 (Chapter 28), and the formats built from them: DEFLATE (Chapter 30), BWT (Chapter 35). Volume III showed us JPEG (Chapter 42), HEVC (Chapter 53), and AV1 (Chapter 54). Volume IV introduced learned compression (Chapters 56–62). In Chapter 76 we met the people behind these ideas. Now we meet the institutions: patents, standards bodies, and the political machines that decided which ideas reached the world.
]

#objectives((
  "Understand what a patent is, what a standard is, and how they interact in compression",
  "Trace the GIF/LZW crisis and its direct consequence: PNG",
  "Explain why JPEG's arithmetic coder was avoided for 30 years",
  "Describe the HEVC patent-pool catastrophe and how it produced AV1",
  "Understand the MP3 licensing story and what happened in April 2017",
  "Name the key standards bodies and what each one governs",
  "Recognize the pattern: patent friction → royalty-free competitor",
))

== What a Patent Actually Is

Before we can understand any of the patent wars, we need to understand the weapon itself.

#definition("Patent")[
  A *patent* is a legal bargain between an inventor and the government. The inventor publicly discloses how their invention works, in enough detail that someone else could reproduce it. In exchange, the government grants the inventor the exclusive right to make, use, and sell that invention for a fixed period: in most countries, 20 years from the date of filing. After the patent expires, anyone can use the invention freely forever.
]

The logic sounds fair. Inventors get rewarded; after 20 years the public gets the idea. But the system was designed for physical things: a new type of screw, a pharmaceutical molecule. Applying it to *mathematical algorithms* became deeply controversial.

#keyidea[
  Software patents are controversial because an algorithm is an abstract mathematical procedure, not a physical object. Many countries (including the European Union) officially do not grant patents on "mathematical methods as such." The United States does, if the algorithm is claimed as part of a system or method with a practical application. This gap between jurisdictions has caused decades of confusion.
]

When a patent covers a technique that becomes part of an international standard (something everyone *must* use to communicate with everyone else), the stakes become enormous. Whoever holds that patent has a potential toll booth on the internet.

=== Standard-Essential Patents

#definition("Standard-Essential Patent (SEP)")[
  A *standard-essential patent* (SEP) is a patent that covers a technique so thoroughly described in a standard that any product implementing that standard necessarily infringes the patent. You cannot comply with the standard without practicing the patent.
]

SEPs come with a supposed safeguard: the patent holder typically promises to license them on *FRAND* terms (*Fair, Reasonable, and Non-Discriminatory*). In theory this prevents extortion. In practice, what counts as "fair" and "reasonable" has been litigated in courts on every continent for decades.

#aside[
  The FRAND promise is not enforceable until someone actually tries to collect, and by then the standard has millions of users. This is what economists call a "hold-up problem": a company can agree to FRAND terms during standardization, then demand a much higher price once the standard is deployed and switching costs are prohibitive.
]

== The LZW Patent: How a Christmas Eve Letter Changed the Internet

The story begins in 1977. Abraham Lempel and Jacob Ziv published the LZ77 algorithm (Chapter 28). In 1978 they published LZ78. In 1984, Terry Welch at Sperry Corporation published an improvement to LZ78, which he called *LZW* (Lempel-Ziv-Welch). Welch had filed a patent application (which became US 4,558,302) on June 20, 1983, assigned to Sperry; the patent itself was granted in December 1985. Sperry merged with Burroughs in 1986 to form a new company called *Unisys*.

Meanwhile, at CompuServe, engineers were building a new image format for the slow, expensive dial-up modems of the 1980s. They needed something that could compress simple graphics efficiently. They chose LZW, apparently not knowing (or not worrying) about the patent. In 1987 CompuServe published the *Graphics Interchange Format*, GIF. The web adopted it enthusiastically. By the early 1990s, GIF was the dominant image format on what was still a young World Wide Web.

#history[
  CompuServe later said it was unaware of the Unisys patent when it designed GIF. This was not implausible: patent searches in the 1980s were done manually by browsing paper indices at the US Patent Office, and the connection between Sperry's patent and CompuServe's image format was not obvious. The LZW technique was widely described in academic literature as if it were in the public domain.
]

In January 1993, Unisys quietly approached CompuServe. Negotiations dragged on for eighteen months. Then, on *December 24, 1994* (Christmas Eve), CompuServe announced the deal publicly: it had agreed to pay Unisys royalties, and any company that shipped GIF-reading software would also owe Unisys a license fee. The fee was a few thousand dollars per company, not per copy, but the principle enraged the nascent online community. The internet, which had grown up treating information as free, suddenly discovered that one of its most basic visual tools had a toll booth.

#keyidea[
  The GIF/LZW affair was the first time most internet users encountered the concept of a software patent with real, painful consequences. It felt unfair: Unisys had done nothing to popularize GIF, had not invented LZ78 (Lempel and Ziv had), and had waited until GIF was irreplaceable before demanding payment.
]

The reaction was swift and creative. On January 4, 1995, a public mailing list post called for the development of a *patent-free* image format. Within days, Thomas Boutell and others had begun designing what would become PNG (the *Portable Network Graphics* format). PNG used DEFLATE (Chapter 30), which is based on LZ77 and was not covered by the Unisys patent. The first PNG specification was published in 1996.

The Unisys US patent on LZW expired on *June 20, 2003*, exactly 20 years after it was filed. Patents in the UK, France, Germany, Italy, Japan, and Canada all expired in 2004. At that point the GIF format was legally free, and technically PNG was superior for lossless images anyway. But the patent dispute had done permanent damage to GIF's reputation and had permanently established PNG as the web's lossless image standard.

#fig(
  [Timeline of the LZW patent crisis and its consequences.],
  cetz.canvas({
    import cetz.draw: *
    let y0 = 0
    // Timeline line
    line((0, y0), (13, y0), stroke: 1.5pt)
    // Marks
    let events = (
      (0.5, "1983\nWelch files\nUS patent"),
      (2.0, "1984\nWelch publishes\nLZW"),
      (3.5, "1987\nCompuServe\npublishes GIF"),
      (5.5, "1993\nUnisys\napproaches\nCompuServe"),
      (7.0, "Dec 24,\n1994\nBomb\ndropped"),
      (8.5, "1996\nPNG spec\npublished"),
      (11.5, "2003\nUS patent\nexpires"),
    )
    for (x, label) in events {
      line((x, -0.15), (x, 0.15), stroke: 1.2pt)
      content((x, -0.6), box(width: 1.6cm, align(center, text(size: 6.5pt)[#label])))
    }
  })
)

== The Arithmetic Coder the World Refused to Use

Now for a subtler story, one that played out inside a standard rather than against it.

We learned arithmetic coding in Chapter 26. It is theoretically superior to Huffman coding: it can represent any symbol with a non-integer number of bits, approaching the true entropy of the source. The JPEG standard (Chapter 42), finalized in 1992, included an *optional* arithmetic coder alongside the default Huffman coder. On paper, the arithmetic-coded JPEG would be a few percent smaller. In practice, almost nobody used it.

Why? Patents.

IBM researchers Jorma Rissanen and Glen Langdon had published the arithmetic coding algorithm in 1979 in the IBM Journal of Research and Development. IBM had also filed patents (US 4,122,440 in 1977 and US 4,286,256 in 1979) covering key aspects of arithmetic coding. Related patents were held by AT&T and Mitsubishi Electric. The JPEG standard included the arithmetic coder, but implementing it required a license from these companies.

The patent holders were not aggressive. IBM issued a statement in 1992 saying it would not charge royalties for non-commercial use, and there was a pathway to commercial licenses. But in the software world, "you might need a license and you might not" translates immediately to "avoid entirely." Legal departments at every company that considered implementing the arithmetic coder ran the math: the few-percent size gain was not worth the legal risk, the licensing conversation, or the time. Every major JPEG implementation shipped with only the Huffman option enabled.

#pitfall[
  This is one of the most important lessons in the chapter: patent risk does not need to be certain or even large to poison a technology. The *uncertainty* is the problem. An engineer cannot ship a product with a cloud of legal risk hanging over it, even if that risk is 5% rather than 95%. When in doubt, engineers choose the route that requires no lawyer.
]

The IBM arithmetic coding patents expired in the late 1990s and early 2000s. At that point, the JPEG arithmetic coder was legally clear. Nobody switched, though, because Huffman-coded JPEG files were already on every server and device on earth, and the format had calcified. The patent had done its damage and walked away.

#history[
  The same arithmetic-coding patents also shadowed JBIG and JBIG2, the black-and-white image compression standards used in fax machines and document scanners. JBIG (1993) included an arithmetic coder that many fax manufacturers quietly avoided or replaced with less efficient methods. When the patents expired, JBIG2 (2000) was adopted freely. By then, however, document scanning had already evolved around the limitation.
]

== The Standards Bodies: Who Writes the Rules?

To understand why compression patents are so powerful, you need to understand where compression standards come from. There are a handful of bodies whose decisions determine what billions of devices support.

=== ISO and IEC

The *International Organization for Standardization* (ISO) and the *International Electrotechnical Commission* (IEC) are the global standards bodies. They produce standards by consensus among national member bodies (like ANSI in the United States, DIN in Germany, BSI in Britain). ISO and IEC jointly run a committee called *JTC 1* (Joint Technical Committee 1) for information technology standards. Inside JTC 1, two working groups dominate compression:

- *SC 29*: Subcommittee 29, "Coding of Audio, Picture, Multimedia and Hypermedia Information." This is the home of JPEG (Working Group 1, WG 1) and MPEG.
- *MPEG*, formally ISO/IEC JTC 1/SC 29/WG 11, was the *Moving Picture Experts Group*, the committee that produced MPEG-1, MPEG-2, MP3, MPEG-4, H.264 (jointly with ITU), H.265, and H.266. In 2020, MPEG was reorganized into multiple working groups under SC 29.

The JPEG committee is WG 1, responsible for JPEG, JPEG 2000, JPEG XL, and related still-image standards.

=== ITU-T

The *International Telecommunication Union* (ITU) is a United Nations agency. Its *Telecommunication Standardization Sector* (ITU-T) produces standards for telecommunications, including video coding. ITU-T Study Group 16 handles video. The "H.26x" series of video codecs (H.261, H.263, H.264, H.265, H.266) are ITU-T standards.

Many codecs are *joint standards*: H.264 is both an ITU-T standard (Rec. H.264) and an ISO/IEC standard (ISO/IEC 14496-10). The Joint Video Experts Team (JVET) currently handles joint work between ITU-T SG16 and ISO/IEC JTC 1/SC 29.

=== IETF

The *Internet Engineering Task Force* (IETF) produces standards for the internet's protocols: HTTP, TCP/IP, and the like. Audio and general-purpose compression formats often reach IETF as *Requests for Comments* (RFCs). DEFLATE is RFC 1951, gzip is RFC 1952, Zstandard is RFC 8878, and Opus audio is RFC 6716. IETF standards tend to be royalty-free by policy; the IETF requires that any standard it publishes be implementable without paying patent royalties.

=== The Alliance for Open Media (AOMedia)

AOMedia is not a traditional standards body. It is a *consortium* - a membership organization of technology companies formed in September 2015 with a single goal: create royalty-free media formats. Its founding members were Amazon, Cisco, Google, Intel, Microsoft, Mozilla, and Netflix. Apple joined in 2016. The direct motivation was the HEVC patent debacle (discussed below). AOMedia produced AV1 (2018) and is developing AV2.

#fig(
  [The standards ecosystem for compression formats.],
  cetz.canvas({
    import cetz.draw: *
    let boxes = (
      (0, 2.5, "ISO/IEC JTC 1\n(JPEG, MPEG,\nH.264, H.265, H.266)"),
      (4.5, 2.5, "ITU-T SG16\n(H.261, H.263,\nH.264, H.265)"),
      (0, 0, "IETF\n(DEFLATE, gzip,\nZstd, Opus)"),
      (4.5, 0, "AOMedia\n(AV1, AV2)"),
    )
    for (x, y, label) in boxes {
      rect((x, y), (x + 3.8, y + 1.8), radius: 3pt, stroke: 0.8pt)
      content((x + 1.9, y + 0.9), box(width: 3.4cm, inset: 2pt, align(center, text(size: 7.5pt)[#label])))
    }
    // Joint arrow between ISO and ITU
    line((3.8, 3.4), (4.5, 3.4), stroke: (dash: "dashed"))
    content((4.15, 3.7), text(size: 6pt)[JVET])
    content((2.2, -0.5), text(size: 7pt, style: "italic")[Royalty-free by policy])
    content((6.4, -0.5), text(size: 7pt, style: "italic")[Royalty-free by design])
  })
)

== The MP3 Story: A Patent Pool That Fed Research

MP3 (MPEG Audio Layer III) was the audio companion to the video codecs of the early 1990s. The algorithm was developed at Fraunhofer IIS (Institut für Integrierte Schaltungen) in Erlangen, Germany, with key contributions from Karlheinz Brandenburg and colleagues, building on work by AT&T Bell Labs and the University of Erlangen-Nuremberg. It was standardized as part of MPEG-1 in 1991 and MPEG-2 in 1994.

The patents were held jointly by Fraunhofer IIS and Thomson Multimedia (later Technicolor). Beginning in the late 1990s, Thomson actively collected royalties: manufacturers of MP3 players, software developers distributing MP3 encoders, and streaming services that used the format all had to pay. The fees were not trivial. Software MP3 encoders like `lame` operated in a legal gray zone in the United States for years, with the `lame` project explicitly disclaiming that users were responsible for their own patent compliance.

This created a peculiar market: free, open-source MP3 decoders existed and were widely distributed (patents were harder to enforce against individuals), but commercial software had to pay. The result was that MP3 became dominant anyway, because it was good enough and the alternatives (AAC, Ogg Vorbis) were not sufficiently widespread. The patent licensing revenue funded continued research at Fraunhofer, which went on to help develop AAC, the MP3 successor that became the default for streaming and mobile.

The MP3 patents began expiring in Europe in 2012 (European patents have a 20-year life). In the United States, the critical patents expired in stages: US patent 5,878,080 in February 2017, US patent 5,960,037 in April 2017. On *April 23, 2017*, Technicolor and Fraunhofer jointly announced the termination of the MP3 licensing program. At that point, MP3 was legally free.

#aside[
  The 2017 headlines said "MP3 is dead." They were wrong and right at the same time. MP3 the format is healthier than ever: billions of files exist, every device plays them, and the format will last decades. What died was the patent licensing program. The announcement just made formal what had already been true in practice for most users.
]

The MP3 story has a different moral than the LZW story. LZW patents were seen as extortion against a format the patent holder did not create. The MP3 patents were held by the people who *built* MP3, and the licensing fees funded real research. The question of whether software patents are good or bad is muddier than it first appears.

== The HEVC Catastrophe: How One Standard Handed a Win to Its Competitor

H.265, also called HEVC (High Efficiency Video Coding), was finalized in January 2013. It was legitimately impressive: compared to H.264, it achieved roughly the same visual quality at half the bitrate. For a streaming service, that means halving bandwidth costs. For a broadcaster, it means fitting twice as many channels in the same spectrum. HEVC should have swept the world.

It did not.

The problem was patents: not one patent pool, but *three competing ones*, each claiming to cover essential HEVC techniques.

#definition("Patent Pool")[
  A *patent pool* is an arrangement in which multiple patent holders agree to license their patents together, as a bundle, at a single negotiated rate. In theory this simplifies licensing: instead of negotiating with each patent holder separately, an implementer pays one license fee to the pool administrator and gets access to all the pooled patents. In practice, pools can have gaps, overlaps, and competing claims.
]

For HEVC, three pools formed in quick succession:

1. *MPEG LA* - the traditional pool administrator for MPEG standards - formed an HEVC pool with licenses from dozens of companies. MPEG LA had successfully administered pools for MPEG-2 and H.264.

2. *HEVC Advance* (later renamed Access Advance) - a second pool, formed in 2015, with a dramatically different royalty structure. Where MPEG LA charged per-device fees, HEVC Advance initially proposed to charge *per stream*, meaning a Netflix or YouTube would pay royalties on every video play. To see why that terrified the streaming industry, do the arithmetic. A per-device fee is paid once: sell a TV, pay (say) a dollar, done forever. A per-stream fee is paid every single time content is watched. A service streaming a billion videos a day at even a tenth of a cent each owes a million dollars *a day* (roughly \$365 million a year), and that bill grows every time the service gets more popular. A per-device fee rewards success once; a per-stream fee taxes it forever. The reaction was horrified. Just 42 days before AOMedia's founding, HEVC Advance published its initial licensing offer, and the sheer shock of that announcement directly accelerated the formation of AOMedia.

3. *Velos Media* - a third pool, formed in 2016 from Ericsson, Nokia, Sharp, and others, with yet another royalty structure.

And after all three pools existed, a fourth problem emerged: many important patent holders were not in *any* pool. They were filing lawsuits separately, in multiple jurisdictions.

A device manufacturer implementing HEVC had to negotiate with at least two pools simultaneously, worry about the holdouts who were not in any pool, and face the prospect of paying royalties from multiple directions on the same standard. Many simply gave up. Streaming services that could afford to deliver video without HEVC did so.

#keyidea[
  The HEVC patent situation demonstrated that fragmented intellectual property can destroy a standard more thoroughly than any technical flaw. HEVC is a remarkable technical achievement. Its patent licensing killed its open adoption.
]

The situation partially resolved itself in December 2025, when Access Advance acquired the administrator of Via Licensing Alliance's HEVC and VVC pools. This consolidated two of the three pool administrators under one roof, though numerous essential patent holders remained outside any pool as of mid-2026. The consolidation reduced *some* of the friction but did not eliminate it.

Meanwhile, the streaming world had moved on to AV1.

=== The Royalty-Free Counter-Movement

Google had been watching the HEVC situation develop. It had acquired On2 Technologies in February 2010 for approximately \$124.6 million, gaining the VP8 video codec and its successor VP9. Google made both royalty-free, releasing them inside the open WebM container. VP9 approximately matched HEVC quality.

But Google alone was not enough to challenge a standard backed by the entire MPEG ecosystem. A coalition was needed. On *September 1, 2015*, Amazon, Cisco, Google, Intel, Microsoft, Mozilla, and Netflix announced the formation of the *Alliance for Open Media*. Their goal: develop a video codec that was royalty-free, patent-unencumbered, and technically competitive with HEVC.

The timing was not coincidental. HEVC Advance's shocking royalty proposal had come just six weeks earlier.

AOMedia merged three in-flight codec projects: Google's VP10 (the VP9 successor), Mozilla's Daala (an experimental wavelet-based codec), and Cisco's Thor. The resulting codec was *AV1*, released in March 2018. By 2020 YouTube was serving AV1 to browsers that supported it; Netflix followed in 2020; Amazon in 2024.

The lesson the industry drew: if you make a standard with unclear or aggressive patent licensing, the market will fund and adopt a worse-but-free alternative. AV1 is not better than H.266/VVC on most metrics; it won because it is free.

#scoreboard(
  caption: "The royalty-free vs. patented landscape (audio/video)",
  [Format], [Year], [License], [Status 2026],
  [MP3], [1991], [Patented → free 2017], [Ubiquitous],
  [AAC], [1997], [Patent-licensed], [Mobile default],
  [Ogg Vorbis], [2000], [Royalty-free], [Niche],
  [Opus], [2012], [Royalty-free (IETF)], [VoIP/streaming],
  [H.264/AVC], [2003], [Patent pool (MPEG LA)], [Universal],
  [H.265/HEVC], [2013], [3 competing pools + holdouts], [Niche web, Apple devices],
  [VP9], [2013], [Royalty-free (Google)], [Widespread],
  [AV1], [2018], [Royalty-free (AOMedia)], [Dominant web video],
  [H.266/VVC], [2020], [Patent-licensed, fragmented], [Minimal adoption],
)

== The GIF-to-PNG Transition: Patents as Evolutionary Pressure

Let us return to still images and trace the aftermath of the LZW crisis more carefully.

PNG was designed as a direct response to GIF's patent problem. Its designers made deliberate choices to avoid all known patents: DEFLATE was chosen as the compression algorithm because Phil Katz had published its specification in RFC 1951 without any patent claims, and the format was placed in the public domain. PNG offered several technical advantages over GIF anyway (true color where GIF was limited to 256 colors, a proper alpha channel for transparency, and better compression), but it is likely that without the patent crisis, the world would have continued using GIF for years longer.

The GIF case is an early example of what we might call *patent-driven format evolution*: a patent forces the market to seek alternatives, and the alternatives sometimes turn out to be technically superior. The same pattern repeats in audio (Ogg Vorbis created as an MP3 alternative; Opus eventually superseding it) and in video (VP8/VP9 and then AV1 as HEVC alternatives).

#misconception[
  "Open-source software is always patent-free."
][
  Open-source licenses govern copyright, not patents. Software can be released under the MIT or GPL license and still infringe patents. The LZW-in-GIF problem involved code that was freely copyable but patent-encumbered. Similarly, open-source H.264 encoders like `x264` are perfectly legal to distribute as source code in most countries, but deploying them commercially may require a patent license from MPEG LA. The two legal systems (copyright and patent) are completely independent.
]

== The JPEG XL Saga: Politics Without a Patent (For Once)

The story of JPEG XL (finalized as ISO/IEC 18181 in 2021–2022, covered technically in Chapter 45) is unusual because the primary obstacle was not patent licensing. JPEG XL is royalty-free. The politics were entirely different: corporate strategy, browser-market share, and the interests of a company that happened to own the competing format.

Google removed JPEG XL support from Chrome in December 2022 (Chrome 110), citing "insufficient ecosystem interest" and security concerns in the C++ decoder. The imaging community was furious. JPEG XL supporters pointed out that Google also owned and promoted AVIF (based on AV1), and that AVIF and JPEG XL compete directly for the "replace JPEG" slot in web imaging.

Google's removal decision triggered years of debate. Was it a legitimate technical call? A competitive move? The answer is probably both. The security concern was real: memory-safety bugs in C++ image decoders have caused serious vulnerabilities in the past (the ImageMagick vulnerabilities of 2016, various browser sandbox escapes). But the decision also conveniently removed a competitor to AVIF.

The resolution came from a different direction. A team of engineers wrote `jxl-rs`, a memory-safe JPEG XL decoder written in *Rust* - a systems programming language whose compiler refuses to build code that could read or write the wrong region of memory. That is exactly the class of bug (a "memory-safety" bug) that lets a malicious image hijack a decoder. Because the whole category of vulnerability that worried Google is ruled out at compile time, rewriting the decoder in Rust answered the security objection at its root. The JPEG XL decoder rewrite is told in full in Chapter 45 (The Modern Image Wars). With the security objection addressed, Google reversed course: JPEG XL support returned to Chrome 145 in February 2026, initially behind a flag, with broad default enablement expected in the second half of 2026.

#history[
  The JPEG XL removal also affected the WebP format's reputation. WebP was a Google format (based on VP8 intra coding) that Google had similarly promoted aggressively, requiring it for images on the Google Play Store to pressure developers to support it. Critics who felt that Google was using Chrome market dominance to steer web standards toward its own formats pointed to both WebP and the JPEG XL removal as evidence.
]

The JPEG XL story is a reminder that format politics extends beyond patents. Browser market share, corporate ownership of competing formats, and control of the web's distribution infrastructure are all levers that can be pulled.

== How Standards Actually Get Made: The Slow Machine

The process of creating an international compression standard is deliberately slow, open, and consensus-driven. This is both its strength and its weakness.

A typical ISO/IEC/MPEG standard goes through these stages:

1. *Call for Proposals (CfP)*: the committee publishes a document saying "we want to standardize something for this use case; please submit your technology proposals." Any company or research group can submit.
2. *Core Experiment phase*: submitters test different techniques against a common corpus and evaluation criteria. This can last years.
3. *Working Draft (WD)*: an evolving technical document. Multiple rounds of WD review.
4. *Committee Draft (CD)*: a more stable draft sent to national bodies.
5. *Draft International Standard (DIS)*: a ballot of all national member bodies. Comments must be resolved.
6. *Final Draft International Standard (FDIS)*: near-final ballot.
7. *International Standard (IS)*: published.

H.266/VVC took about four years from initial studies to publication (2016–2020). JPEG XL took about three years from the Call for Proposals to publication. The slowness is intentional: it gives time for patent holders to declare their SEPs and for the committee to work around them or negotiate FRAND commitments.

#checkpoint[
  Why does a standard go through so many draft stages before publication?
][
  Each stage adds scrutiny: first from technical experts inside the committee, then from national standards bodies, and finally from a global ballot. This catches both technical errors and patent encumbrances before the standard is deployed. A standard that turns out to be technically wrong or legally encumbered after publication causes enormous damage (think of the HEVC situation).
]

The IETF process is faster and more pragmatic. An IETF standard starts as an *Internet-Draft*, goes through a working group, becomes a *Proposed Standard* (RFC), and eventually may become an *Internet Standard*. The IETF's IPR (Intellectual Property Rights) policy requires that participants disclose any patents they know about, and standards are expected to be implementable royalty-free. This makes IETF standards less prestigious internationally but far more reliably deployable.

== A Code View: Probing Patent Status

Here is a small Python sketch illustrating how a tool might check which compression algorithms are available "royalty-free" in a software stack: the kind of audit an engineer would run before deploying a compression library in a commercial product.

#gopython("Dictionary: a lookup table from key to value")[
  A *dictionary* (called `dict` in Python) maps *keys* to *values*. You can look up any key in constant time - almost instant, no matter how large the dictionary. You write one like this:

  ```python
  d = {"apple": 3, "banana": 7}
  print(d["apple"])   # prints 3
  ```

  Dictionaries are written with curly braces `{}`, keys and values separated by `:`, and items separated by `,`. If you try to look up a key that does not exist, Python raises a `KeyError`.
]

#pyrecall[
  The `@dataclass` decorator (first met in Chapter 24) turns a class into a tidy record: you list the fields with their type hints, and Python writes the boilerplate constructor for you, so `CodecStatus("LZW", 1984, True, "...")` just works. The `list[CodecStatus]` annotation (Chapter 16) means "a list whose every element is a `CodecStatus`", and the `[c for c in CODECS if c.royalty_free]` line is a _list comprehension_ (Chapter 16): "collect every `c` from `CODECS` for which `c.royalty_free` is true."
]

```python
# codec_status.py - a simple reference table for patent status of common
# compression algorithms as of June 2026.
# This is illustrative; always verify with a qualified patent attorney.

from dataclasses import dataclass

@dataclass
class CodecStatus:
    name: str
    year_standardized: int
    royalty_free: bool
    notes: str

CODECS: list[CodecStatus] = [
    CodecStatus("LZW",    1984, True,
        "US patent expired 2003, EU patents 2004. Now fully free."),
    CodecStatus("MP3",    1991, True,
        "All key patents expired by April 2017."),
    CodecStatus("JPEG (Huffman)", 1992, True,
        "Baseline Huffman JPEG is patent-free."),
    CodecStatus("JPEG (arithmetic)", 1992, True,
        "IBM/AT&T arithmetic patents expired; but effectively unused."),
    CodecStatus("H.264/AVC", 2003, False,
        "MPEG LA pool; ~$0.20/device royalty above threshold."),
    CodecStatus("H.265/HEVC", 2013, False,
        "Multiple competing pools; many holdouts. High uncertainty."),
    CodecStatus("Opus",   2012, True,
        "IETF RFC 6716; royalty-free by design."),
    CodecStatus("VP9",    2013, True,
        "Google royalty-free; no known pool."),
    CodecStatus("AV1",    2018, True,
        "AOMedia royalty-free; broad browser/device support."),
    CodecStatus("JPEG XL", 2022, True,
        "ISO/IEC 18181; royalty-free; Chrome support restored Feb 2026."),
    CodecStatus("H.266/VVC", 2020, False,
        "Access Advance + holdouts; adoption minimal on open web."),
    CodecStatus("DEFLATE", 1996, True,
        "RFC 1951; no known patents; foundation of gzip, PNG, zlib."),
    CodecStatus("Zstandard", 2018, True,
        "RFC 8878; Facebook/Meta; BSD license; royalty-free."),
]

def print_status_table() -> None:
    free     = [c for c in CODECS if c.royalty_free]
    encumbered = [c for c in CODECS if not c.royalty_free]
    print(f"Royalty-free ({len(free)} codecs):")
    for c in free:
        print(f"  {c.year_standardized}  {c.name:<20} {c.notes}")
    print(f"\nPatent-encumbered ({len(encumbered)} codecs):")
    for c in encumbered:
        print(f"  {c.year_standardized}  {c.name:<20} {c.notes}")

if __name__ == "__main__":
    print_status_table()
```

This is not legal advice, but it illustrates the kind of table every compression engineer keeps in their head. The pattern that leaps out: every format that has dominated the *open web* for more than a decade is on the royalty-free list. The patented formats dominate *device storage* and *proprietary pipelines*, where companies can negotiate individual licenses. The open internet trends relentlessly toward royalty-free.

== Why Free Tech Keeps Winning on the Open Web

There is a structural reason for this pattern, and it is worth making explicit.

The web works because any server can send a file to any browser, anywhere, without prior arrangement. If that file uses a patented format, then the browser vendor, the server operator, and possibly the end user are all potentially liable for patent infringement. Even a small per-device royalty, multiplied across billions of browser installations, is an enormous sum. Browser vendors (companies like Mozilla, which is a non-profit) cannot afford to pay royalties for every codec they support.

The result is a two-tier market:
- *Open web and general software*: gravitates strongly toward royalty-free. IETF and AOMedia formats win here.
- *Consumer devices, broadcast, and enterprise*: can negotiate licensing deals. H.264 is on every phone (hardware decoders paid for through MPEG LA licensing), HEIC is the default on every iPhone, AAC is the default audio for Apple and Android.

The open web tier is larger by number of users; the device tier is larger by revenue. Both matter. But if you are writing open-source software or building a web service, you essentially must use royalty-free formats for your public-facing interfaces.

#keyidea[
  The IETF has a clear policy: any standard it publishes must be implementable without royalties. AOMedia's founding principle is the same. The ISO/IEC process does not have this requirement. It allows patented technology in standards, with the FRAND commitment as the safety valve. This single difference explains most of the format landscape.
]

== The Virtuous Cycle: When Patents Handed Wins to Free Tech

The great irony is that the patent holders in each of these stories largely defeated themselves. Consider:

- *Unisys* demanded GIF royalties → internet invented PNG → PNG is now the universal lossless web image format → Unisys received nothing after the first wave of license payments, and its name is associated with villainy.

- *IBM/AT&T patents on arithmetic coding* → JPEG shipped with Huffman only → by the time patents expired, Huffman JPEG was entrenched → IBM received no royalties on the compression technique inside most of the world's photos.

- *HEVC patent pool chaos* → AOMedia formed → AV1 developed → AV1 now dominates web video → HEVC licensing revenue goes primarily to Apple and broadcast customers, not the open internet.

- *HEVC Advance's aggressive royalties* → directly accelerated AV1 timeline by two to three years, according to most estimates.

Each time, aggressive or confused patent licensing gave free alternatives the time and the motivation to catch up. The pattern is almost mechanical: if the tax on using the patented format exceeds the cost of building a substitute, someone will build the substitute.

== What Happens When Patents and Standards Align Well

Not every patent story ends in disaster. H.264/AVC is the clearest counterexample. It has been deployed on essentially every internet-connected device on earth since about 2010. It remains the only video format with near-universal hardware decode support. The MPEG LA patent pool is straightforward: one pool, clear terms, reasonable rates. Companies knew exactly what they owed and paid it.

H.264 succeeded partly because MPEG LA learned from the MPEG-2 experience: keep the pool simple, keep the rates predictable, and move quickly to get all the major patent holders inside. When that happened, implementers could make confident licensing decisions, and H.264 took off.

The contrast with HEVC (where three competing pools formed, each claiming to cover essential techniques) shows that the *structure* of the licensing matters as much as the *existence* of patents. A single, clean pool with reasonable rates is navigable. Three competing pools with uncertain scope is a swamp.

#aside[
  MPEG LA (now Via Licensing Alliance, which was acquired by Access Advance in December 2025) has administered patent pools for MPEG-2, MP3, H.264, HEVC, and more. The original MPEG LA model (charge device manufacturers a small per-unit fee, share the pool revenue with patent holders based on declared essential claims) was reasonably effective for a decade. The HEVC fragmentation represented a breakdown of that model, partly because the number of essential patent holders had grown and partly because some holders calculated they could extract more revenue by staying outside the pool and litigating separately.
]

== The 2025–2026 Horizon: Next-Generation Standards

As of mid-2026, the compression standards landscape is in an interesting moment.

For video, *H.266/VVC* exists and is technically impressive (roughly 50% better than HEVC), but its patent situation remains complex. Access Advance's December 2025 acquisition of Via Licensing Alliance consolidated two of the three pools, but essential patent holders outside any pool remain a concern. VVC deployment on the open web is essentially zero; it finds use in broadcast applications where companies can negotiate directly.

*AV2*, AOMedia's successor to AV1, was announced for a "year-end 2025" launch. As of mid-2026 the bitstream specification is essentially finalized, with hardware decode support expected broadly around 2027–2028. AV2 claims roughly 30% improvement over AV1.

ISO/IEC JTC 1/SC 29 has issued a call for proposals for a next-generation video standard (*MPEG-I Video* and beyond) with submissions due October 2026 and finalization expected around 2029–2030. The interesting question for that standard will be whether MPEG has learned from HEVC: can they coordinate a single clean patent pool before the standard is finalized?

For images, *JPEG XL* is the hot topic. Its return to Chrome 145 in February 2026 set off a fresh wave of developer interest. The combination of superior compression, progressive decoding, and the unique lossless-JPEG-transcoding feature (existing JPEG files can be losslessly converted to JPEG XL and reversed, giving ~20% size reduction with zero quality loss) positions it well. Since JPEG XL is royalty-free, it does not face the patent problems that plagued HEVC.

The learned and neural compression systems covered in Volume IV are beginning to appear in standards contexts. ISO/IEC 23088 (Video Coding for Machines) advanced to Draft International Standard status at the 153rd MPEG meeting, optimizing compressed video for machine analysis rather than human viewing. Neural-network components are appearing in hybrid standards, though the patent landscape for neural compression is currently unsettled: many institutions are filing patents on neural encoder/decoder architectures.

#keyidea[
  The next frontier for format politics will likely be neural and AI-based compression. The question of whether neural architectures trained on public data and described in academic papers can be patented (and if so, by whom) is beginning to be asked. The field is still early enough that we do not yet know whether neural compression will follow the HEVC fragmentation pattern or the AV1 royalty-free pattern.
]

#takeaways((
  "A patent gives an inventor 20 years of exclusive rights in exchange for public disclosure; after expiry, anyone can use the invention freely.",
  "Standard-essential patents (SEPs) must be licensed on FRAND terms, but 'fair and reasonable' is fiercely litigated.",
  "The LZW patent (US 4,558,302, expired 2003) forced the internet to invent PNG as a royalty-free GIF replacement.",
  "IBM's arithmetic-coding patents caused JPEG to ship with only its Huffman option for 30 years, despite arithmetic coding being technically superior.",
  "Three competing HEVC patent pools (MPEG LA, HEVC Advance, Velos Media) crippled H.265 adoption and directly motivated the formation of AOMedia.",
  "AOMedia (founded September 1, 2015) produced AV1 (2018), now the dominant royalty-free web video codec.",
  "MP3 patents expired in April 2017; the format is now free, but AAC had already taken its natural market.",
  "The key standards bodies are ISO/IEC (JPEG, MPEG), ITU-T (H.26x), IETF (internet protocols, royalty-free by policy), and AOMedia (AV1/AV2, royalty-free by design).",
  "The open web gravitates toward royalty-free formats; patented formats dominate device storage and proprietary pipelines.",
  "The recurring pattern: aggressive patent licensing gives free alternatives the time and motivation to catch up, and free tech usually wins the open internet.",
))

== Exercises

#exercise("77.1", 1)[
  What is a standard-essential patent (SEP), and what does the acronym FRAND stand for? Give one example of a compression standard that contains essential patents licensed on FRAND terms.
]

#solution("77.1")[
  A standard-essential patent (SEP) is a patent that any implementation of a given standard must infringe: you cannot comply with the standard without practicing the patent. FRAND stands for *Fair, Reasonable, and Non-Discriminatory*, a licensing commitment that SEP holders typically make when their technology is accepted into a standard. One example is H.264/AVC: the MPEG LA patent pool licenses the essential H.264 patents on FRAND terms to device manufacturers.
]

#exercise("77.2", 1)[
  On what date did Unisys announce publicly that it would collect royalties from GIF-using software? What format was created as a direct result of this controversy, and what compression algorithm does that format use?
]

#solution("77.2")[
  The announcement came on *December 24, 1994*. The format created as a result was *PNG* (Portable Network Graphics). PNG uses *DEFLATE* compression (LZ77-based, specified in RFC 1951), which was not covered by the Unisys LZW patent.
]

#exercise("77.3", 2)[
  Why did the optional arithmetic coder in the JPEG standard almost never get implemented, even though arithmetic coding is theoretically superior to Huffman coding? What eventually made this moot?
]

#solution("77.3")[
  The arithmetic coder was covered by patents held by IBM, AT&T, and Mitsubishi Electric. Even though the patent holders offered licenses, the legal uncertainty was enough to deter engineers. Legal departments preferred the certain-to-be-safe Huffman option. The patents expired in the late 1990s and early 2000s, but by then Huffman-coded JPEG files were on every server and device, and the format was too entrenched to change the default. (Today, JPEG XL replaces the role of JPEG with modern entropy coding.)
]

#exercise("77.4", 2)[
  Describe the three competing HEVC patent pools. Why did this fragmentation hurt adoption? How did it lead to the formation of AOMedia?
]

#solution("77.4")[
  The three pools were: (1) *MPEG LA* - the traditional HEVC pool with per-device fees; (2) *HEVC Advance* (later Access Advance) - a second pool with an initial proposal to charge per-stream fees, which alarmed streaming services; and (3) *Velos Media* - a third pool from Ericsson, Nokia, Sharp, and others. Additionally, many essential patent holders remained outside all pools, filing lawsuits independently. An HEVC implementer might owe fees to multiple pools simultaneously plus face litigation from holdouts. This made the licensing cost and legal risk unpredictable, so many developers avoided HEVC. The shock of HEVC Advance's initial royalty proposal in July 2015 was a direct trigger: just 42 days later, on September 1, 2015, Amazon, Cisco, Google, Intel, Microsoft, Mozilla, and Netflix announced the formation of the Alliance for Open Media to develop a royalty-free alternative.
]

#exercise("77.5", 3)[
  Consider the following claim: "If HEVC had been licensed royalty-free like AV1, it would have been universally adopted and AV1 would never have been developed." Argue both for and against this claim. What does your analysis suggest about the role of patent licensing as a force for technical evolution?
]

#solution("77.5")[
  *For the claim:* HEVC is technically superior to AV1 on most benchmarks, particularly for high-resolution and high-fidelity content. A royalty-free HEVC would have had hardware support on virtually all devices (silicon vendors were already building HEVC decoders). Adoption would have been fast and nearly universal, and AV1's main competitive advantage (being free) would have disappeared. Billions of dollars spent on AV1 development might have gone elsewhere.

  *Against the claim:* AV1 was not just a response to HEVC's royalties; it was also a deliberate engineering effort to build a cleaner codec with fewer legacy constraints. AV1 may have been developed anyway, just later. Moreover, the "royalty-free HEVC" scenario requires all the major HEVC patent holders to voluntarily forgo licensing revenue, which is contrary to their corporate incentives. The fragmentation was partly structural: with so many essential patent holders, coordination costs made a single clean pool economically difficult even if everyone wanted one. Finally, if HEVC had been royalty-free and universally adopted, the impetus to develop better tools for the open web (AV2, JPEG XL, modern royalty-free audio codecs) would have been reduced.

  *On patent licensing as an evolutionary force:* The pattern across the chapter suggests that aggressive patent licensing reliably accelerates the development of free alternatives. This is not efficient: billions of dollars are spent on duplication. But it has produced formats (PNG, AV1, Opus, Zstandard) that are technically excellent and legally unencumbered. A world with no software patents might have had faster adoption of the *best* technology; a world with very aggressive patents has produced a competitive ecosystem of *good* technologies with diversity and resilience.
]

== Further Reading

#link("https://en.wikipedia.org/wiki/Arithmetic_coding")[Arithmetic coding - Wikipedia] - includes the full history of the IBM/AT&T patents and their effect on JPEG.

#link("https://groups.csail.mit.edu/mac/projects/lpf/Patents/Gif/Gif.html")[The Unisys/CompuServe GIF Controversy (League for Programming Freedom, 1995)] - the primary historical document from the time of the crisis.

#link("https://www.kyzer.me.uk/essays/giflzw/")[Sad day... GIF patent dead at 20 (Stuart Caie, 2003)] - a detailed technical and legal history of the LZW patent expiry.

#link("https://streaminglearningcenter.com/codecs/hevc-licensing-misunderstood-maligned-and-surprisingly-successful.html")[HEVC Licensing: Misunderstood, Maligned, and Surprisingly Successful (Streaming Learning Center)] - a balanced analysis of the HEVC patent situation.

#link("https://www.audioblog.iis.fraunhofer.com/mp3-software-patents-licenses")[Alive and Kicking - MP3 Software, Patents and Licenses (Fraunhofer IIS)] - the official Fraunhofer perspective on the MP3 patent history and the 2017 termination.

#link("https://www.rfc-editor.org/rfc/rfc1951.txt")[RFC 1951: DEFLATE Compressed Data Format Specification] - the patent-free compression spec at the heart of PNG and gzip.

#link("https://aomedia.org")[Alliance for Open Media] - the consortium home page, with white papers on AV1, AV2, and AOMedia's royalty-free licensing model.

#link("https://arxiv.org/abs/2506.05987")[Alakuijala et al. (2025): JPEG XL - Overview and Applications (arXiv:2506.05987)] - the most current technical and status overview of JPEG XL as of 2025.

#bridge[
  Chapter 78 turns to the other side of the ledger: the ideas that seemed brilliant but did not work, the formats that were technically superior but lost anyway, and the cautionary tales that every compression engineer memorizes. We have spent this chapter on the legal and political obstacles to adoption; the next chapter asks what happens when the obstacles are technical, social, or simply bad luck, and what we can learn from those failures.
]
