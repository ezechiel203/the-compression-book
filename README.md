# The Compression Book

**A Complete History and Technical Treatise on Data Compression** — June 2026 edition.

A from-zero-to-expert book that assumes only **9th-grade mathematics** and builds everything
else from scratch. Five volumes, **81 chapters, ~768,000 words, ~4,068 pages**.

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

| Vol | Title | Chapters |
|-----|-------|----------|
| I   | Foundations: The Language of Information | 1–23 |
| II  | Classical Lossless Compression | 24–36 |
| III | Lossy and Perceptual Media Compression | 37–55 |
| IV  | The Neural and AI Era | 56–65 |
| V   | Specialized Domains, Systems, and Reflections | 66–81 |

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

## How it was made

Authored by a multi-agent research workflow (mixed Opus/Sonnet drafting in throttled batches,
followed by a full Opus audit/expand pass over every chapter for the *nothing-unexplained*
invariant, cross-chapter articulation, and `tinyzip` consistency), typeset with Typst.

## License

Dual-licensed: the **book content** (prose, figures, the typeset book) under
[CC BY 4.0](LICENSE), and the **source code** (build tooling, `lib.typ`/`web.typ`,
`build_site.py`, and the `tinyzip` code) under the [MIT License](LICENSE-CODE).
