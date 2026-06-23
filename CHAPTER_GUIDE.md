# Chapter Authoring Guide — "The Compression Book" (Gold-Standard Edition)

You are writing ONE chapter of a multi-volume Typst book that aims to be **the most complete and the most
didactic book on data compression ever written**. It takes a complete beginner "from zero to genuine expert".
Read this whole guide before writing a single line.

## THE READER (never forget this)
A motivated, intelligent person with **only a 9th-grade education**. They are NOT comfortable with advanced
mathematics or computer science. They are curious and willing to work, but you must EARN every step.
Everything below serves one rule:

> ### THE PRIME DIRECTIVE: nothing is ever used before it is explained.
> No symbol, no term, no theorem, no line of code, no acronym appears without having been built from scratch
> first — either earlier in the book or, at first use, right here in a skippable box. If you introduce it, you
> explain it. There are NO exceptions. This is the single most important property of the book.

## TONE — warm, witty, story-driven O'Reilly
Curiosity-led and human. Open with a concrete puzzle, not a definition. Foreground the drama and the people
(Huffman beating his professor, the GIF patent war, Bellard's feats, the xz backdoor). Light, true humor is
welcome; never cutesy, never padded. Precise and rigorous *underneath* the friendliness. Respect the reader's
intelligence while assuming none of their prior knowledge.

## VALUE PER LINE
Every paragraph must teach or advance. No throat-clearing, no "in this section we will". Lead with the
question/problem → the idea (intuition first) → the math → the code → the caveat. Use concrete numbers and tiny
worked examples constantly. Lengthen a demonstration when understanding truly needs it; keep it tight when it
doesn't. Page count is irrelevant — completeness and clarity are everything.

## THE BOOK IS ONE RISING ARC (articulation)
Each chapter BUILDS ON the previous ones. You are given the full `outline.json`, so:
- Open with a `#recap[...]` that wires explicitly to earlier chapters ("In Chapter N we proved …; now we use it").
- Reference earlier chapters by number/title ("as we saw in Chapter 7"). Assume everything in earlier chapters
  is known; do NOT re-teach it (use `#mathrecall[..]`/`#pyrecall[..]` for a one-line reminder if helpful).
- End with a `#bridge[...]` that motivates the next chapter.
- Stay in your lane: cover YOUR brief deeply; defer neighbouring topics with a forward-reference.

## THE TWO SPINES: math taught from scratch, AND Python taught from scratch
1. **Math:** the FIRST time the book needs any concept beyond ~9th grade (logarithms, ∑/∏ notation, sets,
   probability, expectation, vectors, matrices, derivatives/gradients, Fourier, KL divergence, …), teach it
   from scratch in a `#gomaths("Topic")[ plain definition + tiny numeric example + intuition ]` box.
2. **Python (3.14):** the reader must become fluent at READING Python by the end. Treat Python exactly like
   math: the first time you use a Python feature or data structure (variables, `for`, `list`, `dict`, `bytes`,
   slicing, comprehensions, classes, generators, `match`, type hints, …) explain it from scratch in a
   `#gopython("Topic")[ ... with a tiny runnable snippet ]` box. Use **Python 3.14 syntax** (modern type hints
   like `dict[int,int]`, `match` statements, f-strings, `:=`, etc.). All code must be correct and runnable.
The MAIN PROSE must read perfectly for someone who SKIPS every `#gomaths` and `#gopython` box.

## THE tinyzip PROJECT (the build-along spine)
Across the book the reader incrementally builds real, working compressors in Python, collectively `tinyzip`.
**Read `/home/ezechiel203/Projects/RESEARCH/compression/book/TINYZIP.md` and follow it EXACTLY.** It assigns each chapter its canonical step number(s),
module names, and function signatures. If your chapter has an assigned step, add a `#project("Step N · …")[ …
Python 3.14 … ]` block that implements precisely that step, importing and reusing the modules earlier steps
created (identical names), round-tripping, with a tiny self-test. Do NOT invent your own step numbers or rename
existing functions. If your chapter has no assigned step, you may still show illustrative Python but add no
`#project` step. Keep functions small, typed, and explained.

## THE SCOREBOARD (watch the bytes melt)
The book compresses the SAME running sample data with each new technique. When relevant, end a technique with a
`#scoreboard(caption: "...", [Technique],[Bytes],[Ratio],[Notes], ...)` that includes the cumulative results up
to and including your chapter, so the reader watches progress accumulate.

## REQUIRED CHAPTER SHAPE (consistent rhythm)
1. `#import "../lib.typ": *`  then (if you use diagrams) `#import "@preview/cetz:0.4.2"`, blank line, `= <exact title>`.
2. `#epigraph[..][..]` + a **hook** (a concrete puzzle/question that the chapter will answer).
3. `#recap[...]` (where we are) and `#objectives((...))` (what they'll be able to do).
4. Body `==` sections following your brief: idea → `#gomaths`/`#gopython` as needed → worked numeric example →
   Python (`#project` where implementable) → `#algo(...)` profile for EVERY named algorithm (name/year/authors/
   aim/complexity/strengths/weaknesses/superseded) → trade-offs → `#history`/`#aside`/`#misconception`. Use
   `#definition`/`#theorem`/`#proof`, `#keyidea`/`#pitfall`, `#checkpoint[q][a]`, and CeTZ `#fig(...)` diagrams.
5. `#scoreboard(...)` update where relevant.
6. `#takeaways((...))`.
7. `== Exercises` with `#exercise("C.n", stars)[..]` (stars 1–3 = difficulty) covering conceptual, mathematical,
   and coding problems, EACH paired with a `#solution("C.n")[..]` (renders into the volume's solutions appendix,
   NOT inline). Use your chapter number for C (e.g. `"11.3"`).
8. `== Further reading` with `#link(...)` to canonical papers (see `seed/_references.md` and `../papers/`).
9. `#bridge[...]`.

## FIGURES (CeTZ 0.4.2) — compression is visual, use diagrams
Draw Huffman trees, sliding windows, DCT basis grids, motion vectors, pipelines, etc. Pattern:
```
#import "@preview/cetz:0.4.2"
#fig([Caption text.], cetz.canvas({
  import cetz.draw: *
  rect((0,0),(2,1)); line((0,0),(2,1)); content((1,1.3))[label]
}))
```
Keep canvases simple and robust. If a diagram fights you, fall back to a `#table` or labelled boxes rather than
shipping a broken build.

## TYPST SYNTAX (NOT LaTeX) — the essentials
- Bold `*x*`, italic `_x_`, code `` `x` ``. **Escape literal `*` and `_` in prose**: write `PPM\*`, `snake\_case`
  (top cause of broken builds). Headings: `==` section, `===` subsection (the `=` title appears once).
- Inline math `$H(X)=-sum_i p_i log_2 p_i$`; block math on its own line `$ ... $`. Typst math: `sum`, `product`,
  `integral`, `log_2`, `times`, `<=`, `>=`, `!=`, `->`, `approx`, `in`, greek `alpha lambda`, subscripts `x_i`,
  multi-char `x_(i+1)`, words `R_"max"`, fractions `(a)/(b)`, `abs(x)`, `norm(x)`, `EE`, `RR`.
- Python code blocks: triple backticks + `python`. Lists `- `/`+ `. Links `#link("url")[text]`.

## COMPONENTS (from lib.typ) — use them richly
`#gomaths("T")[..]` `#gopython("T")[..]` `#mathrecall[..]` `#pyrecall[..]` · `#algo(...)[..]` · `#keyidea[..]`
`#pitfall[..]` `#note[..]` `#history[..]` `#tryit[..]` `#aside[..]` `#misconception[claim][reality]` ·
`#definition("t")[..]` `#theorem("n")[..]` `#proof[..]` · `#recap[..]` `#bridge[..]` `#objectives((..))` ·
`#project("step")[..]` `#scoreboard(caption:"..", ...)` `#checkpoint[q][a]` · `#fig(caption, body)` ·
`#exercise("c.n", stars)[..]` `#solution("c.n")[..]` · `#takeaways((..))`.

## PROCESS
1. Read `CHAPTER_GUIDE.md` (this file), `outline.json` (find YOUR chapter by number — title, brief, profiles,
   target words, file path, model, seed indices, and what `tinyzip` already contains), the matching `seed/NN-*.md`
   and any archived `drafts_v1/NN-*.typ` for your topic (expand FAR beyond them), and `seed/_references.md`.
2. Research with web search to verify dates/names/numbers and 2024–2026 developments (today: June 2026).
3. Write your file across MULTIPLE Write/Edit calls. Your outline entry gives an `inventory` (minimum counts of
   concept boxes, algorithm profiles, proofs, worked examples, code listings, and exercises) and a word `floor`.
   **Treat the `inventory` as a COMPLETENESS CHECKLIST you must meet or exceed, and the `floor` as a minimum word
   count, NEVER a cap** — go well beyond both wherever full understanding requires it. Expand every section to
   real depth; never stop short or pad. Honour the PRIME DIRECTIVE on every line.
4. Compile-check and REPAIR until clean (verify the REAL exit code is 0; ignore 'unknown font' warnings):
   `$HOME/.local/bin/typst compile --root /home/ezechiel203/Projects/RESEARCH/compression/book <your-file> /tmp/ckNN.pdf`
5. Report: word count, compiles (true only if exit 0), #sections, #gomaths, #gopython, #exercises, #figures, one-line note.
