// =============================================================================
// lib.typ — template + reusable components for
// "The Compression Book" (Typst 0.15)
// Every chapter file starts with:  #import "../lib.typ": *
// so chapters are self-contained and individually compilable.
// =============================================================================

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
      #box(baseline: 1pt, text(size: 11pt)[∑]) GO FURTHER · THE MATHS#if topic != "" [ — #topic]
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
       GO FURTHER · PYTHON#if topic != "" [ — #topic]]],
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
    #text(fill: white, weight: "bold", size: 11.5pt)[#name]
    #h(1fr)
    #if year != "" { text(fill: white.darken(5%), size: 9.5pt)[#year] }
  ]
  #block(inset: (x: 11pt, y: 9pt))[
    #set text(size: 9.8pt)
    #let row(k, val) = if val != "" [
      #grid(columns: (78pt, 1fr), gutter: 6pt,
        text(weight: "bold", fill: c-accent2)[#k], [#val])
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
  #text(weight: "bold")[Definition — #term.] #h(3pt) #body
]

#let theorem(name, body) = block(width: 100%, breakable: true,
  inset: (x: 10pt, y: 8pt), radius: 4pt, fill: rgb("#eef4fb"),
  stroke: (left: 3pt + c-accent), above: 9pt, below: 9pt)[
  #text(weight: "bold", style: "italic")[Theorem (#name).] #h(3pt)
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
  #text(fill: c-accent2)[— #who]
]) + v(6pt)

// ---- chapter takeaways list ------------------------------------------------
#let takeaways(items) = block(width: 100%, breakable: true,
  inset: (x: 12pt, y: 10pt), radius: 4pt, fill: c-key.lighten(92%),
  stroke: (left: 3pt + c-key), above: 12pt, below: 8pt)[
  #text(weight: "bold", fill: c-key)[Chapter takeaways]
  #v(3pt)
  #set text(size: 10pt)
  #for it in items [- #it\ ]
]

// ---- learning objectives / chapter connectors ------------------------------
#let objectives(items) = block(width: 100%, breakable: true,
  inset: (x: 11pt, y: 9pt), radius: 4pt, fill: c-accent.lighten(93%),
  stroke: (left: 3pt + c-accent), above: 10pt, below: 10pt)[
  #text(weight: "bold", fill: c-accent)[By the end of this chapter you will be able to:]
  #v(2pt)
  #set text(size: 10pt)
  #for it in items [- #it\ ]
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
    SCOREBOARD#if caption != "" [ — #caption]]
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
  heading(level: 1)[Solutions to Exercises]
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
    #text(size: 13pt, fill: c-accent, weight: "bold", tracking: 3pt)[PART #numeral]
    #v(10pt)
    #line(length: 30%, stroke: 1.2pt + c-accent)
    #v(14pt)
    #text(size: 26pt, weight: "bold")[#title]
  ]
  v(2fr)
  pagebreak(weak: true)
}

// ===========================================================================
// Book document template — used by main.typ only.
// ===========================================================================
#let book(title: "", subtitle: "", author: "", date: "", volume: "", body) = {
  set document(title: if volume != "" { title + " — " + volume } else { title }, author: author)
  set page(
    width: 176mm, height: 250mm,
    margin: (inside: 24mm, outside: 18mm, top: 22mm, bottom: 22mm),
    numbering: "1",
    number-align: center,
  )
  set text(font: ("Libertinus Serif", "New Computer Modern", "DejaVu Serif"),
           size: 10.5pt, lang: "en", fill: c-ink)
  set par(justify: true, leading: 0.62em, first-line-indent: 1.1em)
  show heading: set block(above: 1.2em, below: 0.7em)
  set heading(numbering: "1.1")
  set figure(numbering: "1")
  show figure.caption: set text(size: 9pt, fill: c-ink.lighten(20%))

  // raw / code styling
  show raw.where(block: true): it => block(width: 100%, fill: rgb("#f6f8fa"),
    inset: 9pt, radius: 4pt, breakable: true,
    text(font: ("DejaVu Sans Mono","Liberation Mono"), size: 8.8pt, it))
  show raw.where(block: false): it => box(fill: rgb("#f0f2f4"),
    inset: (x: 2.5pt, y: 0pt), outset: (y: 2.5pt), radius: 2pt,
    text(font: ("DejaVu Sans Mono","Liberation Mono"), size: 9pt, it))

  show link: set text(fill: c-accent)

  // chapter headings (level 1) are big; the page break is emitted by the volume
  // file BEFORE each #include (not here) — doing it in the show rule breaks when a
  // heading is measured inside a container (e.g. a CeTZ canvas).
  show heading.where(level: 1): it => {
    block(above: 0pt, below: 18pt)[
      #set text(size: 9pt, fill: c-accent, weight: "bold", tracking: 1.5pt)
      #if it.numbering != none [#upper[Chapter] #counter(heading).display("1")]
      #v(4pt)
      #set text(size: 23pt, fill: c-ink, weight: "bold", tracking: 0pt)
      #it.body
      #v(3pt)
      #line(length: 38%, stroke: 1.2pt + c-accent)
    ]
  }
  show heading.where(level: 2): set text(size: 14pt, fill: c-accent)
  show heading.where(level: 3): set text(size: 11.5pt, fill: c-accent2)

  // ---- title page ----
  set page(numbering: none)
  v(1fr)
  align(center)[
    #if volume != "" [#text(size: 16pt, fill: c-accent2, weight: "bold", tracking: 2pt)[#upper(volume)] #v(14pt)]
    #text(size: 34pt, weight: "bold")[#title]
    #v(6pt)
    #text(size: 15pt, fill: c-accent)[#subtitle]
    #v(20pt)
    #line(length: 45%, stroke: 1pt + c-rule)
    #v(20pt)
    #text(size: 13pt)[#author]
    #v(3pt)
    #text(size: 10.5pt, fill: c-ink.lighten(30%))[#date]
  ]
  v(2fr)
  pagebreak()

  // ---- table of contents ----
  set page(numbering: "i")
  counter(page).update(1)
  outline(title: [Contents], depth: 2, indent: auto)
  pagebreak()

  // ---- body ----
  set page(numbering: "1")
  counter(page).update(1)
  body
}
