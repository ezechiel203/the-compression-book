// =============================================================================
// lib.typ — template + reusable components for
// "The Compression Book" (Typst 0.15)
// Every chapter file starts with:  #import "../lib.typ": *
// so chapters are self-contained and individually compilable.
// =============================================================================

#import "bookindex.typ": _idxpat, _index-mark, make-index

// ---- palette ---------------------------------------------------------------
#let c-ink    = rgb("#1a1a1a")
#let c-accent = rgb("#0b5394")   // deep blue
#let c-accent2= rgb("#783f04")   // brown
#let c-key    = rgb("#0b6e4f")   // green  (key ideas)
#let c-warn   = rgb("#9a2617")   // red    (pitfalls)
#let c-note   = rgb("#5b3a86")   // purple (notes)
#let c-algo   = rgb("#0b5394")   // blue   (algorithm profiles)
#let c-soft   = rgb("#f4f6f8")
#let c-rule   = rgb("#d0d7de")

// Render a field that may be a string: if it contains math ($...$), parse it as
// markup so the math (and any markup) renders instead of showing literal $ signs.
#let _mk(v) = if type(v) == str and "$" in v { eval(v, mode: "markup") } else { v }

// ---- admonition primitive --------------------------------------------------
#let _admon(title, col, body) = block(
  width: 100%, breakable: true,
  inset: (x: 11pt, y: 9pt), radius: 4pt,
  fill: col.lighten(90%), stroke: (left: 3pt + col),
  above: 10pt, below: 10pt,
)[
  #text(weight: "bold", fill: col, size: 9.5pt, tracking: 0.4pt)[#upper(title)]
  #v(2pt)
  #set text(size: 10pt)
  #body
]

#let keyidea(body)  = _admon("Key idea", c-key, body)
#let pitfall(body)  = _admon("Pitfall", c-warn, body)
#let note(body)     = _admon("Note", c-note, body)
#let history(body)  = _admon("Historical note", c-accent2, body)
#let tryit(body)    = _admon("Try it yourself", c-accent, body)

// ---- "Go Further: The Maths" box -------------------------------------------
// A self-contained, SKIPPABLE primer on a math concept, introduced at first use.
// The main narrative must read fine even if the reader skips every one of these.
//   #gomaths("Logarithms")[ ...from-scratch explanation... ]
#let c-math = rgb("#0f766e")  // teal
#let gomaths(topic, body) = block(
  width: 100%, breakable: true, radius: 4pt,
  fill: c-math.lighten(93%), stroke: (left: 3pt + c-math),
  inset: (x: 11pt, y: 9pt), above: 11pt, below: 11pt,
)[
  #grid(columns: (1fr, auto), align: (left + horizon, right + horizon),
    text(weight: "bold", fill: c-math, size: 9.5pt, tracking: 0.5pt)[
      #box(baseline: 1pt, text(size: 11pt)[∑]) GO FURTHER · THE MATHS#if topic != "" [: #_mk(topic)]
    ],
    text(size: 7.8pt, style: "italic", fill: c-math.lighten(10%))[skip if familiar],
  )
  #v(3pt)
  #set text(size: 9.9pt)
  #body
]

// A quick one-line in-margin reminder (lighter than a full gomaths box)
#let mathrecall(body) = box(inset: (x: 6pt, y: 2pt), radius: 2pt,
  fill: c-math.lighten(94%))[#text(size: 9pt, fill: c-math)[*Recall.* #body]]

// ---- "Go Further: Python" box ----------------------------------------------
// A self-contained, SKIPPABLE primer on a Python concept (syntax or data structure),
// taught from scratch at first use. Python 3.14. Main narrative must read fine if skipped.
//   #gopython("Lists")[ ...explanation + tiny runnable example... ]
#let c-py = rgb("#1f5066")  // python blue-slate
#let gopython(topic, body) = block(
  width: 100%, breakable: true, radius: 4pt,
  fill: c-py.lighten(92%), stroke: (left: 3pt + c-py),
  inset: (x: 11pt, y: 9pt), above: 11pt, below: 11pt,
)[
  #grid(columns: (1fr, auto), align: (left + horizon, right + horizon),
    [#box(fill: c-py, inset: (x: 4pt, y: 1pt), radius: 2pt,
        text(fill: white, weight: "bold", size: 8pt)[PY])
     #h(4pt) #text(weight: "bold", fill: c-py, size: 9.5pt, tracking: 0.5pt)[
       GO FURTHER · PYTHON#if topic != "" [: #_mk(topic)]]],
    text(size: 7.8pt, style: "italic", fill: c-py.lighten(8%))[skip if fluent],
  )
  #v(3pt)
  #set text(size: 9.9pt)
  #body
]
#let pyrecall(body) = box(inset: (x: 6pt, y: 2pt), radius: 2pt,
  fill: c-py.lighten(93%))[#text(size: 9pt, fill: c-py)[*Python.* #body]]

// ---- algorithm / technique profile card ------------------------------------
// Usage:
// #algo(
//   name: "LZ77", year: "1977", authors: "Abraham Lempel, Jacob Ziv",
//   aim: "...", strengths: "...", weaknesses: "...", superseded: "...",
// )[ free-form prose ]
#let algo(name: "", year: "", authors: "", aim: "", strengths: "",
          weaknesses: "", superseded: "", complexity: "", body) = block(
  width: 100%, breakable: true, radius: 5pt,
  stroke: 0.7pt + c-algo, fill: c-soft,
  inset: 0pt, above: 12pt, below: 12pt,
)[
  #block(width: 100%, fill: c-algo, inset: (x: 11pt, y: 7pt),
         radius: (top: 5pt))[
    #text(fill: white, weight: "bold", size: 11.5pt)[#_mk(name)]
    #h(1fr)
    #if year != "" { text(fill: white.darken(5%), size: 9.5pt)[#year] }
  ]
  #block(inset: (x: 11pt, y: 9pt))[
    #set text(size: 9.8pt)
    #let row(k, val) = if val != "" [
      #grid(columns: (78pt, 1fr), gutter: 6pt,
        text(weight: "bold", fill: c-accent2)[#k], [#_mk(val)])
      #v(2pt)
    ]
    #row("Authors", authors)
    #row("Aim", aim)
    #row("Complexity", complexity)
    #row("Strengths", strengths)
    #row("Weaknesses", weaknesses)
    #row("Superseded by", superseded)
    #if body != none [
      #v(3pt)
      #line(length: 100%, stroke: 0.5pt + c-rule)
      #v(4pt)
      #body
    ]
  ]
]

// ---- definition / theorem / proof ------------------------------------------
#let definition(term, body) = block(width: 100%, breakable: true,
  inset: (x: 10pt, y: 8pt), radius: 4pt, fill: rgb("#fbf7ef"),
  stroke: (left: 3pt + c-accent2), above: 9pt, below: 9pt)[
  #text(weight: "bold")[Definition (#_mk(term)).] #h(3pt) #body
]

#let theorem(name, body) = block(width: 100%, breakable: true,
  inset: (x: 10pt, y: 8pt), radius: 4pt, fill: rgb("#eef4fb"),
  stroke: (left: 3pt + c-accent), above: 9pt, below: 9pt)[
  #text(weight: "bold", style: "italic")[Theorem (#_mk(name)).] #h(3pt)
  #emph(body)
]

#let proof(body) = block(above: 6pt, below: 9pt)[
  #text(style: "italic")[Proof.] #h(3pt) #body #h(1fr) $square$
]

// ---- chapter epigraph ------------------------------------------------------
#let epigraph(quote, who) = align(right, block(width: 78%)[
  #set text(style: "italic", size: 10pt, fill: c-ink.lighten(15%))
  #quote
  #v(2pt)
  #set text(style: "normal", size: 9pt)
  #text(fill: c-accent2)[#who]
]) + v(6pt)

// ---- chapter takeaways list ------------------------------------------------
#let takeaways(items) = block(width: 100%, breakable: true,
  inset: (x: 12pt, y: 10pt), radius: 4pt, fill: c-key.lighten(92%),
  stroke: (left: 3pt + c-key), above: 12pt, below: 8pt)[
  #text(weight: "bold", fill: c-key)[Chapter takeaways]
  #v(3pt)
  #set text(size: 10pt)
  #for it in items [- #_mk(it)\ ]
]

// ---- learning objectives / chapter connectors ------------------------------
#let objectives(items) = block(width: 100%, breakable: true,
  inset: (x: 11pt, y: 9pt), radius: 4pt, fill: c-accent.lighten(93%),
  stroke: (left: 3pt + c-accent), above: 10pt, below: 10pt)[
  #text(weight: "bold", fill: c-accent)[By the end of this chapter you will be able to:]
  #v(2pt)
  #set text(size: 10pt)
  #for it in items [- #_mk(it)\ ]
]
#let recap(body)  = _admon("Where we are", c-accent, body)   // wires to earlier chapters
#let bridge(body) = _admon("Coming up next", c-accent2, body) // wires to the next chapter

// ---- myth-busting ----------------------------------------------------------
#let misconception(claim, body) = block(width: 100%, breakable: true,
  inset: (x: 11pt, y: 9pt), radius: 4pt, fill: c-warn.lighten(91%),
  stroke: (left: 3pt + c-warn), above: 10pt, below: 10pt)[
  #text(weight: "bold", fill: c-warn)[Myth.] #emph(claim)
  #v(3pt)
  #text(weight: "bold", fill: c-key)[Reality.] #body
]

// ---- aside / fun fact ------------------------------------------------------
#let aside(body) = block(width: 100%, breakable: true, inset: (x: 10pt, y: 7pt),
  radius: 4pt, fill: rgb("#faf7ee"), stroke: (left: 2pt + c-accent2),
  above: 8pt, below: 8pt)[
  #text(size: 9.3pt)[#text(weight: "bold", fill: c-accent2)[Aside. ]#body]
]

// ---- the running tinyzip project -------------------------------------------
#let project(step, body) = block(width: 100%, breakable: true, radius: 5pt,
  stroke: 0.8pt + c-key, fill: c-key.lighten(95%), inset: 0pt, above: 12pt, below: 12pt)[
  #block(width: 100%, fill: c-key, inset: (x: 11pt, y: 6pt), radius: (top: 5pt))[
    #text(fill: white, weight: "bold", size: 10.5pt)[
      BUILD `tinyzip`#if step != "" [ · #step]]]
  #block(inset: (x: 11pt, y: 9pt))[#body]
]

// ---- running scoreboard (compression results so far) -----------------------
#let scoreboard(caption: "", ..rows) = block(width: 100%, breakable: true,
  above: 12pt, below: 12pt)[
  #text(weight: "bold", fill: c-accent2, size: 9.5pt)[
    SCOREBOARD#if caption != "" [: #_mk(caption)]]
  #v(3pt)
  #table(columns: (auto, auto, auto, 1fr), inset: 6pt,
    align: (left, right, right, left),
    fill: (_, row) => if row == 0 { c-accent.lighten(85%) } else { none },
    table.header([*Technique*], [*Bytes*], [*Ratio*], [*Notes*]),
    ..rows.pos())
]

// ---- checkpoint (self-test; answer deferred to a footnote) -----------------
#let checkpoint(body, answer) = block(width: 100%, breakable: true,
  inset: (x: 11pt, y: 8pt), radius: 4pt, fill: c-note.lighten(93%),
  stroke: (left: 3pt + c-note), above: 10pt, below: 10pt)[
  #text(weight: "bold", fill: c-note)[Checkpoint.] #body
  #footnote[*Checkpoint answer.* #answer]
]

// ---- exercises + deferred (per-volume) solutions ---------------------------
#let _stars(n) = {
  let s = ""
  for _ in range(n) { s += "★" }
  text(fill: c-accent2)[#s]
}
#let exercise(ref, stars, body) = block(width: 100%, breakable: true,
  inset: (x: 10pt, y: 7pt), above: 8pt, below: 8pt, stroke: (left: 2pt + c-rule))[
  #text(weight: "bold")[Exercise #ref] #h(5pt) #_stars(stars) \
  #body
]
// solution renders NOTHING inline; it is collected into the volume's appendix.
#let solution(ref, body) = [#metadata((ref: ref, body: body)) <booksol>]
#let solutions-appendix() = context {
  heading(level: 1, numbering: none)[Solutions to Exercises]
  for el in query(<booksol>) {
    block(above: 9pt, breakable: true)[
      #text(weight: "bold", fill: c-accent)[Solution #el.value.ref.] #h(3pt) #el.value.body
    ]
  }
}

// ---- captioned figure (wrap a CeTZ canvas or image) ------------------------
#let fig(caption, body) = figure(block(breakable: false, inset: 5pt)[#body],
  caption: caption)

// ---- part divider (full page) ----------------------------------------------
#let partdivider(numeral, title) = {
  pagebreak(weak: true)
  set page(numbering: none)
  v(1fr)
  align(center)[
    #set text(hyphenate: false)
    #text(size: 13pt, fill: c-accent, weight: "bold", tracking: 3pt)[TOME #numeral]
    #v(10pt)
    #line(length: 30%, stroke: 1.2pt + c-accent)
    #v(14pt)
    #block(width: 80%)[#text(size: 26pt, weight: "bold")[#title]]
  ]
  v(2fr)
  pagebreak(weak: true)
}

// ===========================================================================
// Book document template — used by main.typ only.
// ===========================================================================
#let book(title: "", subtitle: "", author: "", date: "", volume: "", tocdepth: 2, body) = {
  set document(title: if volume != "" { title + ": " + volume } else { title }, author: author)
  set page(
    width: 178mm, height: 235mm,                          // O'Reilly trim (7 x 9.25 in)
    margin: (inside: 24mm, outside: 18mm, top: 20mm, bottom: 18mm),
    numbering: "1",
    footer: none,                                          // page number lives in the running head
    header: context {
      let pg = counter(page).at(here()).first()
      let chs = query(heading.where(level: 1).before(here()))
      if chs.len() == 0 { return none }                   // front matter / before first chapter
      if counter(page).at(chs.last().location()).first() == pg { return none }  // chapter-opener page
      let secs = query(heading.where(level: 2).before(here()))
      let cht = chs.last().body
      let sct = if secs.len() > 0 { secs.last().body } else { cht }
      set text(font: "Source Sans 3", size: 8pt, fill: c-ink.lighten(15%))
      block(width: 100%, stroke: (bottom: 0.4pt + c-rule), inset: (bottom: 3pt), {
        if calc.even(pg) {
          grid(columns: (auto, 1fr), align: (left + bottom, right + bottom),
               strong(counter(page).display()), upper(cht))
        } else {
          grid(columns: (1fr, auto), align: (left + bottom, right + bottom),
               upper(sct), strong(counter(page).display()))
        }
      })
    },
  )
  set text(font: ("EB Garamond", "Libertinus Serif"), size: 11.6pt, lang: "en",
           fill: c-ink, hyphenate: true)
  set smartquote(enabled: false)   // plain straight quotes
  set par(justify: true, leading: 0.74em, spacing: 0.74em, first-line-indent: 1.2em)
  // headings: humanist sans, stick to following content, never break a word
  show heading: set text(font: "Source Sans 3", weight: "semibold", hyphenate: false)
  show heading: set block(above: 1.4em, below: 0.72em, sticky: true)
  show outline.entry: set text(hyphenate: false)
  set heading(numbering: "1.1")
  set figure(numbering: "1")
  show figure: set block(breakable: false)
  show figure.caption: set text(font: "Source Sans 3", size: 8.5pt, fill: c-ink.lighten(20%))
  set table(inset: (x: 6pt, y: 3.5pt), stroke: 0.5pt + c-rule)
  show table: set text(size: 9.2pt, hyphenate: true)
  show table.cell: set par(justify: false, leading: 0.5em, first-line-indent: 0pt)

  // code in Source Code Pro
  show raw.where(block: true): it => block(width: 100%, fill: rgb("#f7f8fa"),
    inset: 8pt, radius: 3pt, breakable: true, stroke: 0.5pt + rgb("#e6eaee"),
    text(font: ("Source Code Pro", "DejaVu Sans Mono"), size: 9pt, it))
  show raw.where(block: false): it => box(fill: rgb("#eef1f4"),
    inset: (x: 2.5pt, y: 0pt), outset: (y: 2.5pt), radius: 2pt,
    text(font: ("Source Code Pro", "DejaVu Sans Mono"), size: 9.4pt, it))

  show link: set text(fill: c-accent)

  // chapter opener (O'Reilly style): small kicker + big sans title + rule
  show heading.where(level: 1): it => {
    block(above: 0pt, below: 20pt)[
      #set text(font: "Source Sans 3")
      #if it.numbering != none [
        #text(size: 11pt, fill: c-accent, weight: "bold", tracking: 2pt)[#upper[Chapter] #counter(heading).display("1")]
        #v(6pt)
      ]
      #text(size: 25pt, fill: c-ink, weight: "bold")[#it.body]
      #v(6pt)
      #line(length: 100%, stroke: 0.8pt + c-accent.lighten(25%))
    ]
  }
  show heading.where(level: 2): set text(size: 15pt, fill: c-accent)
  show heading.where(level: 3): set text(size: 12pt, fill: c-accent2)

  // ---- title page ----
  set page(numbering: none, header: none)
  set text(font: "Source Sans 3")
  v(1fr)
  align(center)[
    #set text(hyphenate: false)
    #if volume != "" [#text(size: 13pt, fill: c-accent2, weight: "bold", tracking: 1.5pt)[#upper(volume)] #v(16pt)]
    #text(size: 36pt, weight: "bold")[#title]
    #v(10pt)
    #block(width: 84%)[#text(size: 15pt, fill: c-accent, weight: "regular")[#subtitle]]
    #v(22pt)
    #line(length: 42%, stroke: 1pt + c-rule)
    #v(22pt)
    #text(size: 13pt)[#author]
    #v(3pt)
    #text(size: 10.5pt, fill: c-ink.lighten(30%))[#date]
  ]
  v(2fr)
  pagebreak()

  // ---- table of contents ----
  set page(numbering: "i", header: none)
  counter(page).update(1)
  show outline.entry.where(level: 1): set text(font: "Source Sans 3", weight: "semibold", size: 10.5pt)
  outline(title: [Contents], depth: tocdepth, indent: auto)
  pagebreak()

  // ---- body (index terms marked here; title page + TOC above are not) ----
  set page(numbering: "1")
  counter(page).update(1)
  show _idxpat: _index-mark
  body
}
