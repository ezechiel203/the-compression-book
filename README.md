# The Compression Book

**A Complete History and Technical Treatise on Data Compression** — June 2026 edition.

A from-zero-to-expert book that assumes only **9th-grade mathematics** and builds everything
else from scratch. **Seven tomes, 81 chapters, ~750,000 words, ~2,360 pages**, typeset O'Reilly-style (Garamond body, 7x9.25" trim), each tome ending with an alphabetical index.

## What makes it different

- **Nothing is used before it is explained.** Every mathematical idea (logarithms, probability,
  expectation, vectors, Fourier, KL divergence, …) is taught from scratch in skippable
  *“Go Further · The Maths”* boxes — the main prose still reads cleanly if you skip them.
- **It teaches Python too.** Python 3.14 is taught the same way (skippable *“Go Further · Python”*
  boxes), and across the book the reader builds **`tinyzip`**, a real working compressor in Python
  (BitIO → Huffman → arithmetic coding → rANS → LZ77 → DEFLATE → BWT → a toy JPEG → an LLM-as-compressor).
- **One rising arc**, not a list of topics: each chapter builds on the previous ones, with
  algorithm profiles (author / year / aim / strengths / weaknesses / what superseded it),
  diagrams, worked examples, and graded exercises with worked solutions.

## The five volumes

| Tome | Title | Chapters |
|------|-------|----------|
| I    | Foundations: Mathematics, Logic, and Programming | 1–17 |
| II   | Information Theory and Entropy Coding | 18–27 |
| III  | Dictionary Coding and the Lossless Toolkit | 28–36 |
| IV   | Transforms and Image Compression | 37–45 |
| V    | Audio and Video Compression | 46–55 |
| VI   | The Neural and AI Era | 56–65 |
| VII  | Specialized Domains, Systems, and the Future | 66–81 |

## Read it

- **Online** (reflowable, responsive, with collapsible solutions and SVG diagrams):
  **<https://ezechiel203.github.io/the-compression-book/>**
- **PDFs**: one per volume, on the [latest release](https://github.com/ezechiel203/the-compression-book/releases/latest).
- **Locally**: `cd web/site && python3 -m http.server 9999` then open <http://localhost:9999/>.

## Build it yourself

Requirements: [Typst](https://typst.app) 0.15+ (the CeTZ 0.4.2 diagram package is fetched on first compile).

```sh
# one volume PDF
typst compile --root . main-vol1.typ TheCompressionBook-Vol1.pdf

# the whole website (compiles all 81 chapters to HTML + assembles the site)
python3 build_site.py
```

## Repository layout

```
chapters/          the 81 chapter sources (Typst)
lib.typ            components + book template for the PDF build
web.typ            HTML-target components for the website build
outline.json       structure: per-chapter title, volume, model, floor, content inventory
CHAPTER_GUIDE.md   the authoring specification (pedagogy + Typst conventions)
TINYZIP.md         the canonical spec for the build-along `tinyzip` project
build_site.py      website build pipeline
main-vol{1..5}.typ per-volume document entry points
web/site/          the built website (HTML, CSS, PDFs)
```

## About

Written and typeset by Alexandre Betry (M.D., M.Sc. C.S.) using Typst. The guiding rule
throughout is that nothing is used before it is explained, so the book builds the reader up
from a 9th-grade starting point to working expertise, one chapter at a time.

## License

Dual-licensed: the **book content** (prose, figures, the typeset book) under
[CC BY 4.0](LICENSE), and the **source code** (build tooling, `lib.typ`/`web.typ`,
`build_site.py`, and the `tinyzip` code) under the [MIT License](LICENSE-CODE).
