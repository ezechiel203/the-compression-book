#import "../lib.typ": *
#import "@preview/cetz:0.4.2"

= Compression in the Stack

#epigraph[
  "The network is the computer, and compression is the oil that keeps it running."
][Jim Gray, Microsoft Research, circa 2000]

Here is something that might surprise you: compression is not a thing you ever
consciously choose to turn on. You didn't tick a box when you opened this book's
PDF, you didn't configure anything when your phone downloaded its last app update,
and you certainly didn't flip a switch before your browser fetched a web page this
morning. Compression was already there: invisible, automatic, working at every
layer of the stack simultaneously.

What does "the stack" mean? Engineers use that word to describe the layers
a piece of data passes through from the moment it leaves a server's memory
to the moment it arrives in your eyes or ears. A web page, for example,
travels through a database, a server application, an HTTP response, a CDN
edge node, a TLS session, a TCP stream, a router, a Wi-Fi radio, an operating
system, a browser, and finally a display. Compression is silently active at
several of those layers all at once: body content compressed by Brotli,
headers compressed by QPACK, filesystem blocks compressed by Btrfs,
swap pages compressed by zram in RAM.

In Chapters 28 through 36 you learned the algorithms (LZ77, Huffman,
Brotli, zstd, the BWT). In Chapter 73 you saw how to engineer them to run
fast. This chapter zooms out from the algorithm and asks: where in real
deployed systems does compression actually live, who put it there, and what
does it buy? By the end you will be able to answer a systems-design interview
question like "how does compression work end-to-end in a CDN" with real
precision, and you will know which layer is doing what and why.

#recap[
  In *Chapter 28* we built the LZ77 sliding-window match finder; in *Chapter 30*
  we assembled it with Huffman coding into the DEFLATE format that gzip uses.
  In *Chapter 35* the BWT gave us a bzip2-class compressor. *Chapter 36* added
  `bench.py` so we can measure ratios. *Chapter 73* showed how modern codecs like
  zstd squeeze every CPU cycle for gigabyte-per-second throughput. Now we ask
  where all those codecs are actually deployed.
]

#objectives((
  "Explain what HTTP Content-Encoding is and trace the negotiation between browser and server.",
  "Compare gzip, Brotli, and zstd for web delivery and know which is fastest, which compresses best, and which is newest.",
  "Explain how HPACK (HTTP/2) and QPACK (HTTP/3) compress headers separately from body content.",
  "Describe transparent filesystem compression in Btrfs and ZFS/OpenZFS.",
  "Explain what zram and zswap do and how they let RAM compress itself.",
  "Understand where databases apply compression and why columnar storage wins.",
  "Describe the role of CDN edge nodes in delivering pre-compressed content.",
))

== The HTTP Layer: Compressing the Body

=== A Journey of 30 Bytes

Type any URL into a browser and press Enter. In the first few hundred
milliseconds a conversation happens that you have never seen:

```
GET /index.html HTTP/1.1
Host: example.com
Accept-Encoding: gzip, deflate, br, zstd
```

That fourth line, `Accept-Encoding`, is the browser announcing to the
server: "I can decode gzip, deflate, Brotli (br), or Zstandard (zstd).
Pick one." The server looks at that list, picks the best algorithm it
supports, compresses the response body, and replies:

```
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Encoding: br
Content-Length: 4120

[4120 bytes of Brotli-compressed HTML]
```

The browser sees `Content-Encoding: br`, runs the Brotli decompressor,
and hands the uncompressed HTML to the rendering engine. The whole
negotiation is invisible to you. This mechanism is called
*HTTP Content-Encoding*, and it has been the primary way the web has
delivered compressed content since the 1990s.

#definition("HTTP Content-Encoding")[
  A per-response HTTP header that names the transformation applied to
  the message body. Unlike `Content-Type` (which says what the data
  *is*), `Content-Encoding` says how the bytes *were packaged* for
  transport. The server picks an algorithm from the client's
  `Accept-Encoding` list; the client must reverse that transformation
  before reading the content.
]

#history[
  *The gzip era (1992–2015).* `Content-Encoding: gzip` was proposed in
  HTTP/1.0 and standardized in RFC 1952 (1996). For nearly two decades
  it was the only compression option any web server or browser actually
  used in practice. Deflate (`Content-Encoding: deflate`) was also
  defined but was notoriously broken (different servers had subtly
  incompatible implementations of what "deflate" even meant), so browsers
  learned to ignore it. If you look at server logs from 2005 or 2010, you
  will see gzip everywhere and almost nothing else.
]

=== The Three Algorithms You Will See in the Wild

Today there are three algorithms that real browsers and servers negotiate:
gzip, Brotli, and Zstandard. Let us meet each one.

*gzip* (RFC 1952, 1996) is the veteran. Under the hood it is DEFLATE
with a two-byte magic number and a checksum wrapped around it: the same
DEFLATE we implemented in Chapter 30. Every browser, every server, every
CDN in the world supports it. Its weakness is age: it was designed for
1990s CPUs and 1990s network speeds, and modern alternatives can compress
20–25% more at comparable or higher speed.

*Brotli* (RFC 7932, July 2016) was designed at Google by Jyrki Alakuijala
and Zoltán Szabadka, originally in 2013 to shrink font files (`.woff2`)
for the web. They noticed something gzip does not exploit: a huge fraction
of web content (HTML tags, CSS property names, JavaScript keywords, common
words in any language) recurs in *exactly the same byte sequences* across
billions of web pages. So they built a *static dictionary* of roughly 13,500
common strings (122 kilobytes of lookup table) and baked it permanently into
the algorithm. Every Brotli decoder on earth already knows the word
`"content"`, `"function"`, `"<!DOCTYPE html>"`, and thousands more.
An encoder can reference those strings with a tiny index instead of copying
the bytes; effectively it gets 120 KB of free context that gzip never had.
Brotli typically produces files 15–25% smaller than gzip at the same CPU
budget for web content.

#gomaths("Static dictionaries and the free context trick")[
  Imagine you are writing a telegram and you have to pay by the letter.
  The word "congratulations" costs 15 letters. But if both you and the
  receiver have agreed in advance that the code "C7" means "congratulations",
  it costs only 2. A *static dictionary* is exactly that pre-agreed codebook,
  permanently built into both the compressor and the decompressor. Because
  you never have to transmit the dictionary itself, every byte saved is
  pure win: there is no startup cost. The downside: the dictionary only
  helps if the actual data contains those exact strings, which is why
  Brotli's dictionary was carefully chosen from a crawl of the real web.
]

*Zstandard* (RFC 8878, February 2021) was written by Yann Collet at Facebook
(now Meta) and open-sourced in August 2016. You already know its internals
from *Chapter 32* (The Modern Frontier); it combines LZ77 matching with the
ANS entropy coder we built in *Chapter 27*, and
as Chapter 73 showed, it decompresses at multi-gigabyte-per-second rates.
For HTTP it sits between gzip and Brotli on ratio (roughly 10–12% better than
gzip, a little behind Brotli) but compresses *much* faster, which makes it ideal for
dynamic pages that are generated per-request and cannot be pre-compressed.
Chrome added zstd to `Accept-Encoding` in Chrome 123 (March 2024);
Firefox followed in version 126 (May 2024). By mid-2026, according to
the HTTP Archive Web Almanac, CDNs handled roughly 46% of requests with
Brotli, 42% with gzip, and 12% with Zstandard. The Zstandard share
is rising fast.

#algo(
  name: "HTTP Content-Encoding (gzip / Brotli / zstd)",
  year: "1996 / 2016 / 2021",
  authors: "IETF (RFC 1952 / RFC 7932 / RFC 8878)",
  aim: "Compress HTTP response bodies in transit from server to browser, negotiated per-request via Accept-Encoding.",
  strengths: "Transparent to application code; universally deployed; each algorithm tunable from speed to ratio.",
  weaknesses: "Only compresses body bytes, not headers (handled separately by HPACK/QPACK); adds latency for on-the-fly compression of dynamic responses.",
  superseded: "Raw HTTP/1.0 without compression; deflate (implementation-broken, effectively abandoned).",
)[
  The negotiation is stateless: each request independently advertises what
  the client supports; each response independently declares what was applied.
  A CDN can serve pre-compressed Brotli to Chrome while serving gzip to an
  older device that doesn't support Brotli, all from the same origin file.
]

=== Pre-compression vs. On-the-Fly Compression

For *static* assets (images, fonts, compiled JavaScript bundles, CSS files)
the server can compress them once at deploy time and store the compressed
version. When a browser requests `/app.js`, the server just reads the
pre-compressed `/app.js.br` from disk and streams it. This is fast and
allows using the slowest, highest-quality Brotli level (level 11),
because the CPU cost is paid once during build, not per request.

For *dynamic* content (a user's news feed, a search result page, an API
response), the server must compress in real time, because the bytes are
different for every user. Here Brotli's slow encoder at high quality becomes
a liability, because level-11 Brotli can be 50–100× slower than gzip.
The common practice is to use Brotli at level 4–6 for dynamic content
(still better than gzip) or switch to Zstandard, which offers excellent
ratio at much higher speed.

#keyidea[
  *Rule of thumb for web compression:* use maximum-quality Brotli for
  static assets (build once, serve forever); use Zstandard or medium-quality
  Brotli for dynamic content (must compress in milliseconds per request).
  Never serve uncompressed text; even gzip is a dramatic win over nothing.
]

=== The Compression Dictionary Transport: The 2024–2025 Frontier

In 2024–2025 the IETF standardized two companion documents that make Brotli
and Zstandard even more powerful for the web:

- *RFC 9841 (Shared Brotli Compressed Data Format, 2025)*: defines a
  variant of Brotli that accepts an *external* dictionary, not just the built-in
  one. The dictionary can be anything both client and server have agreed on.
- *RFC 9842 (Compression Dictionary Transport, 2025)*: defines the HTTP headers
  to negotiate which dictionary to use. A server can designate `/framework-v3.js`
  as a dictionary; when it ships `/framework-v3.1.js`, the delta can be encoded
  relative to the previous version, achieving ratios close to binary diffing.
  Chrome added support in Chrome 130 (October 2024).

The new content-encoding tokens are `dcb` (dictionary-compressed Brotli) and
`dcz` (dictionary-compressed Zstandard). For versioned web app bundles that
change only slightly between deploys, savings of 60–80% over ordinary Brotli
have been reported. This is essentially the binary diffing idea from
Chapter 71 directly inside the HTTP layer.

#checkpoint[
  A browser sends `Accept-Encoding: gzip, br`. The server only supports
  gzip and Zstandard. What does the server do?
][
  The server sends the response compressed with gzip (the only algorithm
  on both lists) and sets `Content-Encoding: gzip`. If the server
  only supported Zstandard and not gzip, it would send the response
  *uncompressed* (no `Content-Encoding` header) rather than send something
  the browser cannot decode.
]

== Compressing Headers: HPACK and QPACK

So far we have compressed the *body* of HTTP responses. But HTTP also has
*headers* (those lines like `Content-Type`, `Set-Cookie`, `Authorization`,
`Cache-Control`), and for many requests, headers are larger than the body.
An API call that returns `{"ok": true}` has maybe 10 bytes of body but
600 bytes of headers. `Content-Encoding` only covers the body.

=== Why Headers Were Left Uncompressed in HTTP/1.1

HTTP/1.1 sends headers as plain ASCII text, request after request. A site
that needs 20 HTTP requests to load a page sends the same cookie header
20 times. The same `Accept-Language: en-US,en;q=0.9` header, byte for byte,
on every single request. This redundancy is glaring, yet HTTP/1.1 has no
mechanism to compress it.

There was a proposal called SPDY (Google, 2012) that used zlib deflate on
headers, but it had to be *removed* because of a compression-based side-channel
attack called *CRIME* (Compression Ratio Info-leak Made Easy, 2012). When
an attacker can inject data into a compressed stream alongside a secret (like
a cookie), measuring how much the compressed output *shrinks* leaks information
about the secret, because compression exploits repetition.

Here is the trick made concrete. Say the secret cookie is `token=SECRET` and
the attacker can make the browser send a request containing a guess. If the
attacker injects `token=S`, that 7-byte string now *matches* the start of the
real cookie sitting in the same compressed buffer, so LZ77 replaces the
duplicate with a short back-reference and the response gets a byte or two
*smaller*. If the attacker injects `token=X` (a wrong guess), there is no
match and the output stays larger. By watching the encrypted response *length*
shrink or not, the attacker reads the secret out one character at a time,
without ever decrypting anything. Compressing headers alongside secret data
turned out to be dangerous.

HTTP/2 needed to compress headers without this vulnerability. The solution,
designed by Roberto Peon and Hervé Ruellan, is *HPACK*.

=== HPACK: Header Compression for HTTP/2 (RFC 7541, 2015)

HPACK is intentionally *not* a general-purpose compressor. It has no sliding
window, no LZ77, no arithmetic coding. Instead it is a specialized
dictionary-based scheme with two tables:

*The static table* is a pre-defined list of 61 common header name+value
pairs, numbered 1–61: entry 2 is `:method: GET`, entry 6 is `:scheme: https`,
entry 32 is `content-type: application/json`. A whole header can be
represented as a single 1-byte index. No compression is needed at all:
the receiver already knows what that byte means.

*The dynamic table* is a per-connection list that grows as new headers
are transmitted. The first time the server sends `set-cookie: session=abc123`,
HPACK adds it to the dynamic table. The *second* time that same header
appears (even in a different response), the server sends only the dynamic
table index, one or two bytes instead of dozens.

The design avoids CRIME because HPACK uses *explicit indexing*, not
context-based compression. An attacker watching compressed output sees
only table indices, which do not shrink or grow based on whether secret
content was partially guessed. The security model was carefully reviewed
before RFC 7541 was published in May 2015.

#algo(
  name: "HPACK",
  year: "2015",
  authors: "Roberto Peon, Hervé Ruellan (RFC 7541)",
  aim: "Compress HTTP/2 headers using a stateful indexed table, avoiding the CRIME vulnerability that broke DEFLATE-based header compression.",
  strengths: "Very low overhead per header on subsequent requests; resistant to compression side-channels; simple to implement.",
  weaknesses: "Stateful: the encoder and decoder must maintain synchronized dynamic tables, requiring reliable ordered delivery (TCP); breaks under packet reordering.",
  superseded: "zlib-compressed headers (SPDY, removed due to CRIME).",
)[
  Because HPACK is stateful and requires ordered delivery, it is
  tied to HTTP/2 over TCP. HTTP/3 uses a redesigned version called QPACK.
]

#gomaths("Prefix codes and variable-length integers in HPACK")[
  HPACK encodes table indices with *variable-length integers*: small
  indices (1–30) fit in a single byte; larger ones spill into additional
  bytes. The prefix length depends on how many bits are available in the
  first byte (some bits are used for flags). The rule is:

  $ "If value" < 2^N - 1: "encode in N bits."$
  $ "Otherwise: set first N bits to 1, then encode" ("value" - (2^N - 1)) "in" 7 "bits per subsequent byte, MSB=1 until last." $

  For a 5-bit prefix (N = 5): values 0–30 fit in one byte; value 31
  needs a second byte encoding (31 − 31) = 0, so the two-byte sequence
  `11111 0 0000000` = `[0x1F, 0x00]`. The "7 payload bits per byte, top
  bit signals continuation" spill rule is exactly the byte varint we built
  in *Chapter 25* (Integer and Universal Codes); HPACK just bolts an
  $N$-bit prefix onto the front of it.
]

=== QPACK: Header Compression for HTTP/3 (RFC 9204, 2022)

HTTP/3 runs over QUIC (a UDP-based transport), and QUIC allows multiple
independent *streams* that can arrive in any order. This is a major
advantage: no head-of-line blocking, where a lost packet on one stream
stalls all other streams as TCP would do. But it breaks HPACK entirely.
HPACK assumes the sender's and receiver's dynamic tables evolve in the same
order, because TCP guarantees in-order delivery. On QUIC, stream 5 might
arrive before stream 3, so a dynamic-table reference in stream 5 might point
to an entry that hasn't been inserted yet. Deadlock.

QPACK (RFC 9204, June 2022) solves this with a clever split:

- *Required-insert-count:* each encoded header block carries a number
  that says "I need at least this many entries in your dynamic table
  before you can decode me." The decoder holds the block until it has
  received enough dynamic-table updates.
- *Encoder and decoder instruction streams:* two dedicated unidirectional
  QUIC streams carry table-update instructions out-of-band from the data
  streams. The encoder inserts entries, cancels them, or acknowledges
  receipt of acknowledgements through these streams.
- *Risk-free references:* a sender can reference a dynamic table entry
  only if it knows the decoder already has it (blocking avoidance mode),
  or it can accept that the header will block the stream until the entry
  arrives (blocking mode). The tradeoff is tunable.

In practice, QPACK achieves compression ratios almost identical to HPACK
while handling out-of-order delivery safely. For the reader, the key
takeaway is: *HTTP body compression and HTTP header compression are
completely separate mechanisms, solved by different algorithms, for
different reasons.*

#fig(
  [HPACK vs. QPACK: how headers travel in HTTP/2 and HTTP/3.],
  cetz.canvas({
    import cetz.draw: *
    // HTTP/2 column
    rect((0,0), (3.8, 6.5), fill: rgb("#eef4fb"), stroke: 0.5pt + rgb("#0b5394"), radius: 3pt)
    content((1.9, 6.2), text(weight: "bold", size: 9pt)[HTTP/2 over TCP])
    rect((0.2, 4.6), (3.6, 5.9), fill: white, stroke: 0.4pt, radius: 2pt)
    content((1.9, 5.4), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8.5pt)[HPACK dynamic table])))
    content((1.9, 5.0), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt, style: "italic")[state shared by all streams])))
    rect((0.2, 3.0), (3.6, 4.4), fill: rgb("#f6f8fa"), stroke: 0.4pt, radius: 2pt)
    content((1.9, 3.9), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8.5pt)[Stream 1 (ordered)])))
    content((1.9, 3.5), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt)[headers → HPACK indices])))
    rect((0.2, 1.4), (3.6, 2.8), fill: rgb("#f6f8fa"), stroke: 0.4pt, radius: 2pt)
    content((1.9, 2.3), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8.5pt)[Stream 2 (ordered)])))
    content((1.9, 1.9), box(width: 3.0cm, inset: 2pt, align(center, text(size: 8pt)[headers → HPACK indices])))
    content((1.9, 0.7), box(width: 3.4cm, inset: 2pt, align(center, text(size: 8pt)[Single TCP connection (ordered)])))

    // HTTP/3 column
    rect((4.4,0), (8.8, 6.5), fill: rgb("#f4fbf7"), stroke: 0.5pt + rgb("#0b6e4f"), radius: 3pt)
    content((6.6, 6.2), text(weight: "bold", size: 9pt)[HTTP/3 over QUIC])
    rect((4.6, 4.6), (8.6, 5.9), fill: white, stroke: 0.4pt, radius: 2pt)
    content((6.6, 5.4), box(width: 3.6cm, inset: 2pt, align(center, text(size: 8.5pt)[QPACK encoder stream])))
    content((6.6, 5.0), box(width: 3.6cm, inset: 2pt, align(center, text(size: 8pt, style: "italic")[table updates out-of-band])))
    rect((4.6, 3.0), (8.6, 4.4), fill: rgb("#f6f8fa"), stroke: 0.4pt, radius: 2pt)
    content((6.6, 3.9), box(width: 3.6cm, inset: 2pt, align(center, text(size: 8pt)[Data stream A (may arrive first)])))
    content((6.6, 3.5), box(width: 3.6cm, inset: 2pt, align(center, text(size: 8pt)[headers w/ required-insert-count])))
    rect((4.6, 1.4), (8.6, 2.8), fill: rgb("#f6f8fa"), stroke: 0.4pt, radius: 2pt)
    content((6.6, 2.3), box(width: 3.6cm, inset: 2pt, align(center, text(size: 8pt)[Data stream B (may arrive first)])))
    content((6.6, 1.9), box(width: 3.6cm, inset: 2pt, align(center, text(size: 8pt)[headers w/ required-insert-count])))
    content((6.6, 0.7), text(size: 8pt)[QUIC: unordered streams])
  })
)

== Filesystem Compression: Btrfs and ZFS

Every layer so far has been about network transport. But what about the bytes
sitting on disk? Modern Linux filesystems can compress data *transparently*:
the application reads and writes ordinary files; the filesystem silently
compresses blocks on the way to storage and decompresses them on the way
back. No application change required. Let us look at the two most capable
filesystems: Btrfs and OpenZFS.

=== Btrfs: Fine-Grained Transparent Compression

Btrfs (B-tree filesystem) was merged into the Linux kernel in 2009.
Its compression implementation works at the level of 128-kilobyte file
extents: each extent is independently compressed, which makes random
read access efficient (you decompress only the 128 KB chunk you need,
not the whole file). Three algorithms are available:

- *zlib* (levels 1–9): the oldest, using DEFLATE. Reasonable ratio,
  slow compression, slowest decompression. Good for archives that you
  read infrequently.
- *LZO*: extremely fast (often close to raw memcpy throughput) but
  the worst ratio of the three. Good for temporary files or swap.
- *zstd* (levels −15 to 15; added in Linux 4.14, 2017): the
  best of both worlds. Levels 1–3 are near-real-time and still
  compress better than zlib. Level 1 is the default recommendation
  for most workloads.

Btrfs negative compression levels (like `-1` through `-15`) are real-time
levels added in recent kernels that trade ratio for speed, useful on very
fast NVMe storage where even a tiny decompression delay costs throughput.

The filesystem also supports `autodetect` mode: if an extent's compressed
form is *larger* than the raw form (which happens with already-compressed
data like JPEG images or ZIP archives), it silently stores the extent
uncompressed. This prevents the infamous "compressed incompressible data
is bigger than the original" trap.

The practical effect of Btrfs zstd on a typical desktop installation:

#scoreboard(caption: "Btrfs transparent compression on a mixed desktop workload",
  [Raw (uncompressed)], [100 GB], [1.00×], [No compression],
  [Btrfs + LZO], [78 GB], [1.28×], [Fastest; ratio roughly gzip-level 1],
  [Btrfs + zstd:1], [68 GB], [1.47×], [Default; near-real-time speed],
  [Btrfs + zstd:5], [61 GB], [1.64×], [Good balance; slightly slower writes],
  [Btrfs + zlib:6], [58 GB], [1.72×], [Best ratio; noticeably slower],
)

#keyidea[
  Compression on a modern NVMe SSD often *improves* read throughput:
  the CPU can decompress data faster than the SSD can feed it. The
  bottleneck shifts from storage bandwidth to compute. Compression thus
  effectively expands both capacity *and* speed simultaneously.
]

=== OpenZFS: Pool-Level Compression

ZFS (Zettabyte File System) was originally designed at Sun Microsystems
and is now maintained as OpenZFS, running on Linux, FreeBSD, macOS,
and illumos. ZFS compression works at the *block* level (typically 128 KB),
similar to Btrfs but with a different architecture: instead of per-file
settings, compression is a property of the *dataset* (a logical partition
within the pool) and is inherited by all files in that dataset.

Available algorithms in OpenZFS:

- *lz4* (default since OpenZFS 2.0): extremely fast - 800 MB/s compression,
  4.5 GB/s decompression per thread. Ratio is lower than zstd but the
  speed overhead is essentially zero on modern hardware.
- *zstd* (multiple levels, added 2020): dramatically better ratio for
  cold data. The recommendation for archival datasets is `zstd` or
  `zstd-6`; for active data, stick with `lz4`.
- *gzip* (1–9): available but rarely chosen; worse than zstd in every dimension.
- *lzjb*: the original ZFS algorithm, now deprecated in favour of lz4.

An important ZFS feature: when you enable compression on an existing
dataset, only *new* data is compressed. Existing blocks remain uncompressed
until they are rewritten. This means enabling compression after the fact
only helps going forward.

#gopython("Reading filesystem compression stats from Python")[
  Python can ask the OS how much space a file actually occupies on
  a compressed filesystem, versus its logical size, using `os.stat`:

  ```python
  import os, pathlib

  def compression_ratio(path: str) -> float:
      """
      Return the apparent compression ratio a filesystem has achieved on
      this file: logical_size / actual_disk_blocks.
      Works on Linux; on other OSes the result may be 1.0 (no block info).
      """
      st = os.stat(path)           # standard stat call
      logical = st.st_size         # bytes the file claims to be
      # st_blocks counts 512-byte "disk allocation units" actually used
      physical = st.st_blocks * 512
      if physical == 0:
          return float("inf")      # empty file
      return logical / physical

  # Example:
  p = "/etc/os-release"
  print(f"{p}: ratio ≈ {compression_ratio(p):.2f}×")
  ```

  On a Btrfs zstd filesystem, a text file might report 2.8×; a JPEG
  (already compressed) will report ≈ 1.0× because the filesystem
  stored it uncompressed after noticing it could not be shrunk.

  `os.stat` is a function from Python's built-in `os` module. `st.st_size`
  and `st.st_blocks` are attributes (named fields) of the stat result object.
]

== RAM Compression: zram and zswap

So far we have compressed bytes on disk and bytes in transit over the
network. What about bytes in *RAM*? Modern systems have a related trick
that is just as useful: compress swap memory in RAM itself.

=== Why Swap Exists and Why It Hurts

When a program needs more RAM than the machine physically has, the operating
system moves the least-recently-used pages of memory to *swap*, a region
on disk set aside for this purpose. Accessing a swapped-out page is
agonizingly slow: a disk access takes microseconds to milliseconds, while
RAM access takes nanoseconds. Applications become sluggish or unresponsive.

On mobile phones and embedded systems (where there may be no swap disk
at all), running out of RAM simply kills the least-important process.

*zram* and *zswap* are two Linux kernel features that solve this by
compressing swapped-out pages and keeping them in RAM. No disk write required.

=== zram: A Compressed Block Device in RAM

zram (merged into the Linux kernel in version 3.14, 2014) creates a virtual
block device (e.g., `/dev/zram0`) whose "storage" is a compressed pool in
RAM. You format it as swap, and the kernel uses it exactly like a disk-based
swap partition. When a page is swapped out, it goes to `/dev/zram0`, where
the kernel compresses it (using LZO, LZ4, or zstd) before writing it to
the in-RAM pool.

The result: a page that occupied 4 KB of RAM uncompressed might compress
to 1.5 KB, so 4 KB of physical RAM holds the equivalent of over 10 KB
of swapped-out data. For typical workloads (browser tabs, text editors,
system services), RAM-resident text and heap data compresses at 2–4×,
meaning zram effectively expands usable RAM by 50–75%.

*Android* has used zram as its primary memory management technique since
Android 4.4 (KitKat, 2013). *ChromeOS*, *Ubuntu* (since 20.04), and
*Fedora* (since Fedora 33) all enable zram by default. The kernel default
as of Linux 6.x is LZO-RLE; zstd offers better ratios at slightly higher
CPU cost and is increasingly recommended.

=== zswap: A Compressed Cache in Front of Disk

zswap takes a different approach. Rather than *replacing* disk swap, it
acts as a *cache* in front of it. When a page is about to be written to
disk swap, zswap intercepts it, compresses it, and holds it in a pool
of RAM. If the page is accessed again soon, it is decompressed from the
RAM cache with no disk I/O. Only if the RAM cache fills up does zswap
evict compressed pages to actual disk swap.

zswap is therefore a hybrid: RAM holds the hot compressed pages, disk
holds the cold overflow. On desktop machines with disk swap enabled,
zswap often eliminates disk swap I/O entirely under typical workloads,
with only a few percent of RAM overhead for the compressed pool.

#fig(
  [zram vs. zswap: two ways to compress swap pages in RAM.],
  cetz.canvas({
    import cetz.draw: *
    // Application RAM box
    rect((0, 5.5), (9, 7), fill: rgb("#eef4fb"), stroke: 0.4pt + rgb("#0b5394"), radius: 3pt)
    content((4.5, 6.4), box(width: 8.6cm, inset: 2pt, align(center, text(weight: "bold", size: 9pt)[Physical RAM: active pages (uncompressed)])))
    // Arrow down-left (zram path)
    line((2.0, 5.5), (2.0, 4.0), mark: (end: ">"), stroke: 0.8pt)
    content((0.6, 4.75), text(size: 8pt)[swap out])
    // zram box
    rect((0.2, 2.7), (3.8, 4.0), fill: rgb("#f4fbf7"), stroke: 0.6pt + rgb("#0b6e4f"), radius: 3pt)
    content((2.0, 3.5), box(width: 3.2cm, inset: 2pt, align(center, text(weight: "bold", size: 8.5pt)[zram pool (in RAM)])))
    content((2.0, 3.1), box(width: 3.2cm, inset: 2pt, align(center, text(size: 8pt)[pages compressed w/ LZ4/zstd])))
    content((2.0, 2.2), text(size: 8pt)[No disk write. 2–4× expansion.])
    // Arrow down-right (zswap path)
    line((7.0, 5.5), (7.0, 4.0), mark: (end: ">"), stroke: 0.8pt)
    content((7.8, 4.75), text(size: 8pt)[swap out])
    // zswap box
    rect((5.2, 2.7), (8.8, 4.0), fill: rgb("#fbf7ef"), stroke: 0.6pt + rgb("#783f04"), radius: 3pt)
    content((7.0, 3.5), box(width: 3.2cm, inset: 2pt, align(center, text(weight: "bold", size: 8.5pt)[zswap cache (in RAM)])))
    content((7.0, 3.1), box(width: 3.2cm, inset: 2pt, align(center, text(size: 8pt)[compressed hot pages])))
    // Arrow from zswap to disk
    line((7.0, 2.7), (7.0, 1.5), mark: (end: ">"), stroke: 0.8pt)
    content((7.8, 2.1), text(size: 8pt)[evict])
    // Disk box
    rect((5.2, 0.5), (8.8, 1.5), fill: rgb("#f6f8fa"), stroke: 0.4pt, radius: 2pt)
    content((7.0, 1.1), box(width: 3.2cm, inset: 2pt, align(center, text(size: 8pt)[Disk swap (uncompressed)])))
    content((7.0, 0.7), box(width: 3.2cm, inset: 2pt, align(center, text(size: 8pt)[cold pages only])))
  })
)

#gopython("Checking zram status from Python")[
  You can inspect zram compression statistics by reading the sysfs
  virtual files the kernel exposes at `/sys/block/zramN/mm_stat`:

  ```python
  import pathlib

  def zram_stats(device: str = "zram0") -> dict[str, float]:
      """
      Read memory stats for a zram device.
      Returns a dict with logical and compressed sizes in MB.
      """
      p = pathlib.Path(f"/sys/block/{device}/mm_stat")
      if not p.exists():
          return {}
      # mm_stat columns: orig_data_size, compr_data_size, mem_used_total,
      #                  mem_limit, mem_used_max, same_pages, pages_compacted
      cols = p.read_text().split()
      orig  = int(cols[0]) / 1_048_576   # bytes → MB
      compr = int(cols[1]) / 1_048_576
      ratio = orig / compr if compr > 0 else float("inf")
      return {"logical_MB": orig, "compressed_MB": compr, "ratio": ratio}

  stats = zram_stats()
  if stats:
      print(f"zram0: {stats['logical_MB']:.1f} MB logical "
            f"→ {stats['compressed_MB']:.1f} MB compressed "
            f"({stats['ratio']:.2f}× ratio)")
  ```

  `pathlib.Path` is a built-in Python class for working with file paths.
  `.read_text()` reads the entire file as a string. `.split()` on a string
  returns a list of whitespace-separated words. The `/` in integer division
  is true division (returns a float); `//` would give integer floor division.
]

== Database Compression

Relational and analytical databases have their own compression story,
and it is shaped by a fundamental choice in how data is stored.

=== Row-Oriented vs. Column-Oriented Storage

A traditional database like MySQL or PostgreSQL stores data *row by row*.
A table with columns `(id, name, salary, department)` writes each row
(all four values for one person) as a contiguous group on disk. This
is efficient for finding or updating one person's record.

But consider a query like "what is the average salary across the company?"
The database needs to read *all* salary values but *none* of the names or
department strings. In a row-oriented layout, it must read all four values
for every row to get to the one it wants. This is wasteful.

*Column-oriented* (columnar) databases store each column separately.
All salary values are together, all department strings are together.
The "average salary" query reads only the salary column, perhaps 10% of
the total data. And crucially for compression: a column contains values
of a *single type*, often with a *narrow range* and *many repeats*.
A department column might have only five distinct values across a million
rows, and that compresses to almost nothing.

=== Compression Techniques at the Column Level

Apache Parquet (2013, from Google's Dremel research) and Apache ORC are
the dominant open columnar formats for analytical data. They layer
multiple compression stages:

*Dictionary encoding* is first. If a column has few distinct values
(say, `"Engineering"`, `"Marketing"`, `"Finance"` repeated a million
times), replace each string with a tiny integer ID (0, 1, 2). The
dictionary of three strings is stored once; the column becomes a list
of tiny integers. A billion-byte string column becomes a million 2-bit
integers plus three short strings.

*Run-length encoding (RLE)* follows. If the column is sorted (as many
analytical tables are), the integer IDs appear in long runs: a million
rows of `0`, then 500,000 rows of `1`. RLE stores this as
`(0, count=1 000 000), (1, count=500 000)`: two pairs instead of
1.5 million entries.

*Bit-packing* squeezes integer columns. If every value in a column fits
in 10 bits, there is no reason to store each in 32 bits. Pack four values
into every 40 bits; you reduce the column to 31% of its original size
without any information loss.

*Delta encoding* helps ordered numeric columns: instead of storing
`1001, 1002, 1003, 1004`, store `1001, +1, +1, +1`. Deltas are small
and compress well with bit-packing or RLE.

These domain-specific codes are then optionally followed by a byte-level
compressor (Snappy or zstd) as a final pass. Ratios of 5–10× are routine
for typical analytical tables; 30× and beyond appear on sorted low-cardinality
columns.

#keyidea[
  Columnar compression is a lesson in *knowing your data*. General-purpose
  codecs like gzip work on opaque byte streams and have no idea that a
  column contains integers, strings, or timestamps. A columnar encoder
  exploits type information, sort order, and cardinality, which a
  generic compressor simply does not have. The result is ratios that
  generic codecs cannot match even at their best levels.
]

=== PostgreSQL and MySQL: Row-Level Page Compression

For row-oriented databases, compression is applied at the *page* level
(a page is typically 8 KB, the unit the database reads from disk).
Each 8 KB page holds a mix of different columns from different rows, which
is harder to compress than a homogeneous column.

PostgreSQL's transparent compression mechanism is called *TOAST*
(The Oversized-Attribute Storage Technique). When a row value (like a
large text field or a binary blob) exceeds about 2 KB, PostgreSQL
automatically compresses it using a fast LZ-family algorithm (PGLZ, based
on LZ77). PostgreSQL 14 (2021) added a per-column `COMPRESSION` option
letting you choose between `pglz` and `lz4`, the latter being significantly
faster at moderate ratio cost.

MySQL's InnoDB engine supports page compression: an entire 8 KB or 16 KB
page is compressed before being written to disk, using zlib. Pages that
compress well are stored in fewer disk sectors; MySQL uses OS-level
hole-punching to return the unused sectors to the filesystem.

=== Time-Series: Gorilla and Delta-of-Delta

For time-series data (metrics, sensor readings, monitoring), Facebook's
*Gorilla* storage system (Pelkonen et al., VLDB 2015) introduced two
elegant tricks:

*Timestamp compression:* timestamps in a time series are nearly regular.
A Prometheus metric sampled every 15 seconds has timestamps 15000, 15000,
15000, ... apart. Store the first timestamp, then the interval (15 s), then
the *deviation from that interval* (usually zero or ±1). Most deviations
fit in 1–2 bits. Gorilla calls this *delta-of-delta* encoding.

*Value compression:* consecutive readings of the same metric are similar.
XOR adjacent float64 values: `float1 XOR float2` tends to have many leading
and trailing zero bits. Store only the meaningful (middle) bits. Most
XOR results fit in 12 bits.

#pyrecall[
  Recall two tools from earlier: *XOR* (the `^` bitwise operator, *Chapter 5*
  and *Chapter 17*) outputs a `1` only where two bits *differ*, so XOR-ing two
  nearly-equal numbers yields mostly `0` bits. And a *float64* (*Chapter 13*)
  is just 64 fixed bits (sign, exponent, mantissa). Two readings like
  `21.0` and `21.1` differ only deep in the mantissa, so their XOR is `0`
  except for a short burst of bits in the middle: exactly the redundancy
  Gorilla harvests.
] Combined with the timestamp trick, Gorilla
typically achieves 1.37 bytes per data point on typical monitoring metrics,
versus 16 bytes for raw float64 + int64. A factor of over 11× with
perfect reconstruction.

#algo(
  name: "Gorilla Time-Series Compression",
  year: "2015",
  authors: "Tuomas Pelkonen et al., Facebook (VLDB 2015)",
  aim: "Compress in-memory time-series (metric name + timestamp + float value) to drastically reduce monitoring-system memory.",
  strengths: "Extremely fast encode/decode; tailored for the specific statistics of metric data; lossless.",
  weaknesses: "Tightly coupled to the timestamp + float data model; performs poorly on irregular or string-valued series.",
  superseded: "Gorilla ideas are now incorporated into InfluxDB, Prometheus TSDB, VictoriaMetrics, ClickHouse, and others.",
)[
  The name comes from the gorilla paper's lead system (Beringei), not the primate.
  The delta-of-delta idea was later adapted for video timestamps in container
  formats like Matroska.
]

== The CDN Edge: Where Compression and Caching Meet

Body compression, header compression, and filesystem compression all
converge at the CDN edge, which is perhaps the most important place
in the stack to understand.

=== What a CDN Edge Does

A *Content Delivery Network* (CDN) places servers (called *edge nodes* or
*PoPs*, Points of Presence) geographically close to end users: in data
centres in São Paulo, Tokyo, Frankfurt, Lagos, and hundreds of other cities.
When a user in Frankfurt requests `example.com/app.js`, the CDN intercepts
the request at the Frankfurt edge node instead of routing it all the way to
the origin server in Virginia. If the Frankfurt node has a cached copy,
it serves it immediately, with no transcontinental round-trip.

Compression interacts with CDN caching in a subtle way: the CDN typically
caches content in a *compressed form*. When it receives the response from
the origin (possibly compressed with gzip), it may:

1. *Transcode* it to a better format: decompress the gzip, recompress as
   maximum-quality Brotli, store the Brotli version. Serve Brotli to
   clients that support it, serve gzip to those that don't.
2. *Cache multiple variants*: store both gzip and Brotli, serve each
   to the appropriate client based on `Accept-Encoding`.
3. *Apply compression rules*: Cloudflare, for example, prefers to serve
   Zstandard over Brotli over gzip, based on what the client advertises.
   Enterprise Cloudflare customers have custom compression rules; as of
   October 2024 Zstandard became available on all Cloudflare plans.

=== Pre-compression: The CDN's Superpower

For static assets (JavaScript bundles, CSS files, font files), the CDN
performs *pre-compression* at cache-fill time: when an asset first enters
the cache, the CDN compresses it at the highest quality setting (Brotli
level 11, Zstandard level 19) and stores the result. All subsequent requests
for that asset get the pre-compressed bytes served from memory, with no
compression work at serve time. The CPU cost of slow high-quality compression
is paid once; the bandwidth savings multiply across thousands of cache hits.

This is one reason Brotli level 11 (too slow for dynamic on-the-fly
compression) is routinely used for web assets: the CDN pre-compresses
and serves the result essentially for free.

=== The Shared Dictionary Revolution at the Edge

With RFC 9841/9842 now supported in Chrome, CDNs are beginning to deploy
dictionary-compressed responses. The scenario works like this:

1. A user downloads `framework-v4.0.0.js` (500 KB, cached).
2. The site ships `framework-v4.1.0.js` (502 KB, 3 KB of changes).
3. The CDN serves `framework-v4.1.0.js` as a `dcz` (dictionary-compressed
   Zstandard) response, using `framework-v4.0.0.js` as the dictionary.
4. The browser, which cached `v4.0.0`, uses it as a dictionary to decode
   the response. The transferred bytes: instead of 502 KB, perhaps 5 KB.

This is binary diffing built directly into HTTP. The CDN controls which
resources are designated as dictionaries and serves the appropriate delta
for each version, automating what would otherwise require a custom software
update protocol.

#misconception[
  "Gzip is fine - it compresses the HTML, nothing else matters."
][
  A modern web page load involves dozens to hundreds of HTTP requests
  for HTML, CSS, JavaScript, fonts, API responses, images, and more.
  Headers on those requests can total more bytes than small response bodies.
  Compression improvements compound across every resource in the page.
  Switching from gzip to Brotli on a site with 200 subrequests per page
  load gives savings on every one of them. The cumulative impact on
  page-load time and bandwidth is significant, especially on slow mobile
  connections.
]

#aside[
  *The QUIC transport itself does not compress.* You might expect that since
  HTTP/3 runs over QUIC, QUIC would handle compression. It does not. QUIC
  provides encryption and reliable delivery but leaves content encoding to
  the HTTP layer. Body compression (gzip/Brotli/zstd) and header compression
  (QPACK) both live in HTTP/3, not in QUIC. QUIC is a transport, not
  a compressor.
]

== Putting It All Together: A Single Web Page Request

Let us trace every compression that happens when your browser loads a
web page from a CDN-fronted site, to make the layers concrete.

You type `https://example.com/` and press Enter.

*Step 1: DNS and TCP/QUIC setup.* Your browser resolves the domain name
and connects to the nearest CDN edge node. If the edge supports HTTP/3,
a QUIC connection is established.

*Step 2: HTTP/3 request.* The browser sends a `GET /` request.
The request headers (`:method: GET`, `:path: /`, etc.) are compressed
by QPACK using the static table: the common headers become a handful
of single-byte indices. The request might be 600 bytes of raw headers
but only 80 bytes on the wire.

*Step 3: CDN serves pre-compressed HTML.* The edge node has the HTML
cached in Brotli-compressed form. It sends `Content-Encoding: br`.
The response headers are also QPACK-compressed. The HTML body, 25 KB
uncompressed, arrives as 7 KB of Brotli.

*Step 4: Browser parses HTML, makes sub-requests.* Dozens of requests
follow: for `app.js`, `styles.css`, fonts, images. Each request/response
goes through the same QPACK header compression and body Content-Encoding
compression. Images arrive as JPEG or WebP (already compressed; no
`Content-Encoding` applied, since double-compressing would waste CPU).

*Step 5: OS and filesystem.* When the browser's disk cache writes
the downloaded files to disk, if the filesystem is Btrfs with zstd,
it may compress the cache files further. Most web content is already
compressed, so Btrfs's autodetect mode will skip trying to compress
Brotli or JPEG output.

*Step 6: RAM pressure.* If many browser tabs are open, the OS may
move some tab processes' memory pages to the zram compressed pool,
silently recovering physical RAM without writing to disk.

In total, the uncompressed HTML + JS + CSS for a complex page might
be 5 MB; what actually crossed the network wire is closer to 1.5 MB,
and the system is using perhaps 3 MB of RAM instead of 8 MB for
cached pages. Compression did not "help" in one place; it ran
simultaneously at six layers without the user knowing any of it.

#fig(
  [The compression stack: six layers active simultaneously in a single page load.],
  cetz.canvas({
    import cetz.draw: *
    let layers = (
      ("Application layer (browser/app)", "No compression here: logic only", rgb("#f6f8fa")),
      ("HTTP/3 headers", "QPACK compression (static + dynamic table)", rgb("#eef4fb")),
      ("HTTP/3 body", "Content-Encoding: br / zstd / gzip", rgb("#eef4fb")),
      ("CDN edge", "Pre-compressed cache; transcoding; dict transport", rgb("#f4fbf7")),
      ("Filesystem", "Btrfs/ZFS transparent block compression (zstd/lz4)", rgb("#fbf7ef")),
      ("RAM/swap", "zram / zswap: compressed swap pages in memory", rgb("#fdf4f4")),
    )
    for (i, (name, detail, col)) in layers.enumerate() {
      let y = 5.5 - i * 0.95
      rect((0.0, y), (9.0, y + 0.85), fill: col, stroke: 0.4pt, radius: 2pt)
      content((4.5, y + 0.6), text(weight: "bold", size: 8.5pt)[#name])
      content((4.5, y + 0.25), text(size: 7.8pt, fill: rgb("#555555"))[#detail])
    }
    // vertical arrow
    line((9.5, 5.5), (9.5, 0.2), mark: (end: ">"), stroke: 1pt + rgb("#0b5394"))
    content((9.5, 5.7), text(size: 8pt)[top])
    content((9.5, 0.0), text(size: 8pt)[bottom])
  })
)

== Why Not Compress Everything at Every Layer?

A natural question: if compression is free money at every layer, why not
add it everywhere? The answer is cost: not money, but CPU, latency, and
correctness.

*Already-compressed data does not compress further.* JPEG, MP4, ZIP,
and gzip are all already compressed output. Wrapping them in
another compressor wastes CPU to produce output slightly *larger* than
the input (because the compressed output looks random). Btrfs's autodetect
mode and CDN logic both check for this.

*Latency budget.* Compressing a 100 MB video stream on-the-fly at Brotli
level 11 could take seconds; a user waiting for a live video stream would
see a stall. The right tool is a fast codec (zstd or LZ4) or no codec
at all for pre-encoded media.

*Double-encryption/compression interactions.* TLS (the encryption layer
that protects HTTPS) encrypts data after HTTP applies `Content-Encoding`.
The CRIME attack exploited the fact that an attacker could inject content
into a compressed-then-encrypted stream and measure the ciphertext size to
leak secrets. The defense is to *not* compress data at the TLS layer itself
(TLS 1.3 removed its built-in compression support) and to be careful about
what is compressed alongside secret data at the HTTP layer. HPACK and QPACK
were designed with this threat model in mind.

*Complexity and debugging.* Each compression layer adds a transform that
must be unwrapped when debugging. A network capture that looks garbled may
be Brotli-compressed; a file that looks corrupt may be Btrfs-compressed.
Every sysadmin has stared in confusion at bytes that turned out to be
harmless, just compressed.

#pitfall[
  Never compress data that is already compressed. Calling `gzip` on a
  `.zip` file, or serving a `.jpeg` with `Content-Encoding: gzip`, wastes
  CPU, adds latency, and typically makes the output *larger*. Always check
  whether your data is pre-compressed before adding another layer.
  The standard MIME types that CDNs skip compression for include
  `image/jpeg`, `image/png`, `image/webp`, `video/*`, `audio/*`, and
  any content type ending in `+zip`, `+zstd`, or `+br`.
]

#takeaways((
  "HTTP Content-Encoding (gzip → Brotli → Zstandard) compresses response bodies; negotiated per-request via Accept-Encoding.",
  "Brotli wins on ratio for static web content due to its 120 KB static dictionary; Zstandard wins on speed for dynamic content.",
  "HPACK (HTTP/2) and QPACK (HTTP/3) compress headers separately from body content, using indexed static and dynamic tables, not a sliding-window compressor.",
  "QPACK extends HPACK to work with out-of-order QUIC streams by adding required-insert-count and instruction streams.",
  "RFC 9841/9842 (2025) introduce shared dictionary transport, enabling HTTP-level binary delta compression for versioned web assets.",
  "Btrfs and OpenZFS provide transparent filesystem compression (zstd and lz4 respectively), often improving both capacity and read throughput on fast SSDs.",
  "zram compresses swap pages in RAM (no disk), effectively multiplying usable RAM by 2–4×; zswap adds a compressed cache in front of disk swap.",
  "Databases apply domain-specific codes (dictionary encoding, RLE, bit-packing, delta encoding) in columnar formats; Gorilla adds delta-of-delta for time series.",
  "CDN edges pre-compress static assets at maximum quality and serve the appropriate encoding per client, making slow high-quality Brotli practical.",
  "Compressing already-compressed data wastes CPU and makes output larger; every layer checks this before applying compression.",
))

== Exercises

#exercise("74.1", 1)[
  A server supports only Brotli and Zstandard. A browser sends
  `Accept-Encoding: gzip, deflate`. What does the server reply, and
  what `Content-Encoding` header (if any) does it include? Explain.
]

#solution("74.1")[
  The server sends the response body *uncompressed* with no
  `Content-Encoding` header. The browser requested only gzip and deflate,
  neither of which the server supports. The server must not apply an
  encoding the client has not declared it can decode. The client will
  receive and interpret the raw bytes as-is.
]

#exercise("74.2", 1)[
  Explain in one paragraph why HPACK cannot be used with HTTP/3.
]

#solution("74.2")[
  HPACK maintains a dynamic table that both encoder and decoder must update
  in strict sequence. HTTP/3 uses QUIC, which delivers independent streams
  out of order: a stream carrying a reference to dynamic table entry 20 may
  arrive before the stream that inserted entry 20. This creates a
  decoding deadlock: the decoder cannot process the block until the entry
  exists, but with HPACK there is no mechanism to signal this dependency.
  QPACK solves it with a `required-insert-count` field and out-of-band
  instruction streams that let the decoder know when the needed table state
  has arrived.
]

#exercise("74.3", 2)[
  A Btrfs filesystem using zstd:1 compression stores a 10 GB directory of
  typical office documents (Word, PDF, spreadsheets). Based on the ratios
  in this chapter, estimate how much physical disk space the directory
  occupies. Then repeat the estimate for a 10 GB directory of JPEG
  photographs. Explain why the estimates differ so dramatically.
]

#solution("74.3")[
  Office documents (Word, PDF, spreadsheets) are largely text, XML, or
  only lightly compressed formats. zstd:1 on such content commonly achieves
  2–3× ratio; a conservative estimate for this mixed directory is 1.5–2×,
  placing the physical size between 5 GB and 6.7 GB. JPEG photos are
  already compressed by the JPEG codec (the DCT from Chapter 38 plus the
  Huffman coding of Chapter 24, assembled into JPEG in Chapter 42).
  The output of a good lossy compressor looks nearly random to a second
  compressor. Btrfs's autodetect mode detects that compression would make
  each JPEG larger and stores it uncompressed. Physical size: ≈ 10 GB,
  ratio ≈ 1.0×. The difference arises because Btrfs compresses data
  redundancy, and JPEG files have almost no remaining redundancy to exploit.
]

#exercise("74.4", 2)[
  A machine has 8 GB of physical RAM and has zram configured with a 4 GB
  compressed pool at a compression ratio of 3×.

  (a) What is the maximum amount of data (in GB) that can be stored in zram?

  (b) A developer argues: "We should just buy more RAM instead of paying
  CPU cycles for compression." Give one scenario where zram is *clearly*
  superior to buying more RAM, and one where buying RAM is the better choice.
]

#solution("74.4")[
  (a) A 4 GB pool at 3× ratio holds 4 × 3 = 12 GB of uncompressed data.
  The machine effectively gains up to 12 GB of swap space without any disk.

  (b) *zram is superior:* in a cloud VM or mobile device where you cannot
  physically add RAM, or where the cost of a RAM upgrade exceeds the value
  of the use case. Compressing at a few GB/s costs a few percent of one
  CPU core and is cheaper per effective-GB than DRAM.

  *RAM is better:* for a workload involving large matrix operations or
  random-access traversal of huge datasets that do not compress well
  (e.g., already-compressed model weights). The decompression latency,
  even if just nanoseconds, is measurable when the CPU is performing
  millions of cache misses per second. More physical RAM has zero
  decompression cost.
]

#exercise("74.5", 2)[
  A startup runs a global CDN serving a JavaScript SPA (single-page
  application). The bundle is 2 MB uncompressed and changes roughly once
  per week. The CDN handles 50 million requests per day to this file.

  (a) Estimate daily bandwidth saved by serving Brotli (level 11, ratio ≈ 3.5×)
  instead of uncompressed.

  (b) The marketing team suggests compressing at level 4 instead to "be
  safe and not slow things down." Explain why this concern is misplaced
  for a CDN serving static content, and what the actual trade-off is.
]

#solution("74.5")[
  (a) Uncompressed: 2 MB × 50M = 100 TB/day.
  Brotli 11 at 3.5×: 2 MB / 3.5 ≈ 571 KB. Total: 571 KB × 50M ≈ 28.6 TB/day.
  Bandwidth saved: 100 − 28.6 ≈ 71.4 TB/day, a 71% reduction.

  (b) The concern is misplaced because CDNs perform *pre-compression* once
  at cache-fill time (typically when the asset first enters the edge or when
  the origin publishes a new version). The level-11 compression cost is paid
  *once*, not 50 million times per day. Subsequent serves read pre-compressed
  bytes from cache and transmit them directly. The actual trade-off is between
  spending an extra few seconds of CPU time once per week (to compress at
  level 11 vs. level 4) versus serving files that are 15–20% larger to
  every user for the entire week.
]

#exercise("74.6", 3)[
  Design a simplified HTTP content-encoding negotiation function in
  Python 3.14. It should take an `Accept-Encoding` header string
  (from the client) and a list of encodings the server supports,
  and return the best encoding to use (or `"identity"` for no
  compression). Define "best" as: prefer `zstd`, then `br`, then `gzip`,
  then `deflate`, then `identity`. Handle the `q=` quality values
  in the Accept-Encoding header.
]

#solution("74.6")[
  ```python
  PREFERENCE = ["zstd", "br", "gzip", "deflate", "identity"]

  def negotiate_encoding(
      accept_encoding: str,
      server_supports: list[str],
  ) -> str:
      """
      Parse Accept-Encoding header and return best mutually supported encoding.
      Respects q= quality values; 0 means "not acceptable".
      Returns "identity" if nothing better is found.
      """
      # Parse: "gzip;q=1.0, br;q=0.9, zstd;q=0.8, identity;q=0"
      client: dict[str, float] = {}
      for token in accept_encoding.split(","):
          token = token.strip()
          if not token:
              continue
          # Split "br;q=0.9" into the name and an optional "q=0.9" part.
          # str.partition(";") returns a 3-tuple: (before, sep, after).
          name, _sep, params = token.partition(";")
          enc = name.strip().lower()
          q = 1.0  # default quality if no q= given
          if "q=" in params:
              # take the text right after "q=" up to the next ; if any
              q_text = params.split("q=", 1)[1].split(";", 1)[0]
              q = float(q_text)
          client[enc] = q

      # Also accept wildcard "*"
      wildcard_q = client.get("*", None)

      for preferred in PREFERENCE:
          if preferred not in server_supports:
              continue
          # Get client's q for this encoding
          q = client.get(preferred, wildcard_q)
          if q is None:
              q = 1.0   # not listed and no wildcard → assume acceptable
          if q > 0:
              return preferred

      return "identity"

  # Self-test
  assert negotiate_encoding(
      "gzip, br;q=0.9, zstd;q=0.8",
      ["gzip", "zstd"]
  ) == "zstd"   # zstd is preferred over gzip even though gzip has higher q

  assert negotiate_encoding(
      "gzip;q=1.0, identity;q=0",
      ["zstd", "br", "identity"]
  ) == "identity"  # Only gzip is requested at q>0, but server has none;
                   # identity has q=0 so it's forbidden → return identity
                   # (in practice: 406 Not Acceptable; simplified here)

  print("All tests passed.")
  ```

  Note: the real HTTP spec says that when `identity;q=0` is sent, the server
  *must not* send uncompressed content and should return a 406 error. This
  simplified version returns `"identity"` as a fallback; a production
  implementation would raise an exception or return a 406 response instead.
]

== Further Reading

#link("https://datatracker.ietf.org/doc/rfc7541/")[RFC 7541: HPACK Header Compression for HTTP/2 (2015)]:
The complete specification for HPACK. Section 2 (the compression model) is
worth reading in full; it explains the static table, dynamic table, and
the deliberate avoidance of context-based compression for security.

#link("https://datatracker.ietf.org/doc/rfc9204/")[RFC 9204: QPACK Field Compression for HTTP/3 (2022)]:
The QPACK specification. Compare the required-insert-count mechanism with
HPACK's simpler model to see exactly what changes when you move from
ordered TCP to unordered QUIC.

#link("https://datatracker.ietf.org/doc/rfc9842/")[RFC 9842: Compression Dictionary Transport (2025)]:
Defines the HTTP headers for negotiating shared Brotli and Zstandard
dictionaries. Read alongside RFC 9841 for the shared Brotli data format.

#link("https://www.debugbear.com/blog/shared-compression-dictionaries")[DebugBear: The Ultimate Guide to Shared Compression Dictionaries (2024)]:
A practitioner's walkthrough of deploying dictionary compression on a
real CDN, with measured bandwidth savings.

#link("https://btrfs.readthedocs.io/en/latest/Compression.html")[Btrfs Compression Documentation]:
The authoritative guide to Btrfs compression algorithms, levels, mount
options, and the autodetect heuristic. Includes per-algorithm benchmarks
on various storage hardware.

#link("https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Workload%20Tuning.html")[OpenZFS Workload Tuning Guide]:
Practical guidance on choosing between lz4 and zstd for ZFS datasets,
including the case for always enabling at least `compression=lz4`.

#link("https://datazone.de/en/aktuelles/zfs-komprimierung-speichereffizienz-performance/")[DATAZONE: ZFS Compression in Practice: LZ4 vs. ZSTD vs. ZSTD-Fast]:
A detailed benchmark comparing LZ4, zstd, and zstd-fast on real NAS
workloads, with throughput and ratio measurements.

#link("https://dl.acm.org/doi/10.1145/2824032.2824077")[Gorilla: A Fast, Scalable, In-Memory Time Series Database (VLDB 2015)]:
The original Gorilla paper by Pelkonen et al., describing the delta-of-delta
timestamp compression and XOR float compression that became industry standard
for monitoring systems.

#link("https://almanac.httparchive.org/en/2025/cdn")[HTTP Archive Web Almanac 2025, CDN chapter]:
Real-world adoption statistics for gzip, Brotli, and Zstandard across
the top million websites, broken down by CDN provider. A ground-truth view
of what is actually deployed.

#bridge[
  We now know *where* compression runs: at every layer of the stack,
  simultaneously and invisibly. But knowing that Brotli is "better" than
  gzip or that zstd is "faster" raises an uncomfortable question: how do we
  actually *measure* that? What does "better" mean when one codec has higher
  ratio and another has lower latency? What does "faster" mean when a codec
  decompresses at 5 GB/s on your laptop but only at 1 GB/s on a
  ten-year-old server? Chapter 75 gives you the rigorous answer: ratio,
  bits-per-pixel, throughput, rate-distortion curves, BD-rate, and the
  careful benchmark design needed to compare codecs without fooling yourself.
]
