// =============================================================================
// web.typ — HTML-target component library for "The Compression Book" website.
// Used ONLY for the HTML build: each chapter's `#import "../lib.typ": *` is
// swapped to `#import "../web.typ": *`. PDFs keep using lib.typ untouched.
// Every visual component emits semantic, CSS-classed HTML (book.css styles it).
// Diagrams (CeTZ) are wrapped in html.frame() -> inline SVG. Math stays MathML.
// =============================================================================

// palette (mirrors lib.typ so chapters that reference these inside CeTZ canvases work)
#let c-ink    = rgb("#1a1a1a")
#let c-accent = rgb("#0b5394")
#let c-accent2= rgb("#783f04")
#let c-key    = rgb("#0b6e4f")
#let c-warn   = rgb("#9a2617")
#let c-note   = rgb("#5b3a86")
#let c-soft   = rgb("#f4f6f8")
#let c-rule   = rgb("#d0d7de")
#let c-math   = rgb("#0f766e")
#let c-py     = rgb("#1f5066")
#let c-algo   = rgb("#0b5394")

#let _starstr(n) = {
  let s = ""
  for _ in range(n) { s += "★" }
  s
}
#let _e = html.elem

// ---- Go Further boxes (skippable primers) ----------------------------------
#let gomaths(topic, body) = _e("aside", attrs: (class: "gobox gomaths"))[
  #_e("div", attrs: (class: "gf-head"))[∑ Go Further · The Maths#if topic != "" [: #topic]#_e("span", attrs: (class: "gf-skip"))[skip if familiar]]
  #body
]
#let gopython(topic, body) = _e("aside", attrs: (class: "gobox gopython"))[
  #_e("div", attrs: (class: "gf-head"))[#_e("span", attrs: (class: "py-badge"))[PY] Go Further · Python#if topic != "" [: #topic]#_e("span", attrs: (class: "gf-skip"))[skip if fluent]]
  #body
]
#let mathrecall(body) = _e("span", attrs: (class: "recall mathrecall"))[*Recall.* #body]
#let pyrecall(body) = _e("span", attrs: (class: "recall pyrecall"))[*Python.* #body]

// ---- algorithm / technique profile -----------------------------------------
#let algo(name: "", year: "", authors: "", aim: "", strengths: "",
          weaknesses: "", superseded: "", complexity: "", body) = _e("div", attrs: (class: "algo"))[
  #_e("div", attrs: (class: "algo-head"))[#name#if year != "" [#_e("span", attrs: (class: "algo-year"))[#year]]]
  #{
    let row(k, v) = if v != "" { _e("dt")[#k] + _e("dd")[#v] }
    _e("dl", attrs: (class: "algo-meta"))[#row("Authors", authors)#row("Aim", aim)#row("Complexity", complexity)#row("Strengths", strengths)#row("Weaknesses", weaknesses)#row("Superseded by", superseded)]
  }
  #if body != none { _e("div", attrs: (class: "algo-body"))[#body] }
]

// ---- admonitions -----------------------------------------------------------
#let _adm(cls, label, body) = _e("div", attrs: (class: "admon " + cls))[#_e("span", attrs: (class: "adm-label"))[#label] #body]
#let keyidea(body) = _adm("keyidea", "Key idea", body)
#let pitfall(body) = _adm("pitfall", "Pitfall", body)
#let note(body)    = _adm("note", "Note", body)
#let history(body) = _adm("history", "Historical note", body)
#let tryit(body)   = _adm("tryit", "Try it yourself", body)
#let recap(body)   = _adm("recap", "Where we are", body)
#let bridge(body)  = _adm("bridge", "Coming up next", body)
#let aside(body)   = _e("div", attrs: (class: "aside"))[#_e("strong")[Aside. ]#body]
#let misconception(claim, body) = _e("div", attrs: (class: "misconception"))[#_e("strong")[Myth. ]#emph(claim) #_e("strong")[Reality. ]#body]

// ---- definition / theorem / proof ------------------------------------------
#let definition(term, body) = _e("div", attrs: (class: "definition"))[#_e("strong")[Definition (#term).] #body]
#let theorem(name, body)    = _e("div", attrs: (class: "theorem"))[#_e("strong")[Theorem (#name).] #emph(body)]
#let proof(body)            = _e("div", attrs: (class: "proof"))[#emph[Proof.] #body #h(0.3em)▪]

// ---- chapter connectors ----------------------------------------------------
#let epigraph(quote, who) = _e("blockquote", attrs: (class: "epigraph"))[#quote #_e("footer")[#who]]
#let objectives(items) = _e("div", attrs: (class: "objectives"))[
  #_e("h4")[By the end of this chapter you will be able to:]
  #_e("ul")[#for it in items { _e("li")[#it] }]
]
#let takeaways(items) = _e("div", attrs: (class: "takeaways"))[
  #_e("h4")[Chapter takeaways]
  #_e("ul")[#for it in items { _e("li")[#it] }]
]

// ---- tinyzip project + scoreboard ------------------------------------------
#let project(step, body) = _e("div", attrs: (class: "project"))[
  #_e("div", attrs: (class: "proj-head"))[BUILD tinyzip#if step != "" [ · #step]]
  #_e("div", attrs: (class: "proj-body"))[#body]
]
#let scoreboard(caption: "", ..rows) = {
  let cells = rows.pos()
  _e("div", attrs: (class: "scoreboard"))[
    #_e("h4")[Scoreboard#if caption != "" [: #caption]]
    #_e("table")[
      #_e("thead")[#_e("tr")[#_e("th")[Technique]#_e("th")[Bytes]#_e("th")[Ratio]#_e("th")[Notes]]]
      #_e("tbody")[#{
        let out = []
        let i = 0
        while i + 3 < cells.len() {
          out = out + _e("tr")[#_e("td")[#cells.at(i)]#_e("td")[#cells.at(i+1)]#_e("td")[#cells.at(i+2)]#_e("td")[#cells.at(i+3)]]
          i += 4
        }
        out
      }]
    ]
  ]
}

// ---- checkpoint + exercises + solutions (native collapsibles) --------------
#let checkpoint(body, answer) = _e("details", attrs: (class: "checkpoint"))[
  #_e("summary")[Checkpoint: #body]
  #_e("div", attrs: (class: "cp-answer"))[#answer]
]
#let exercise(ref, stars, body) = _e("div", attrs: (class: "exercise"))[
  #_e("span", attrs: (class: "ex-ref"))[Exercise #ref] #_e("span", attrs: (class: "ex-stars"))[#_starstr(stars)]
  #body
]
#let solution(ref, body) = _e("details", attrs: (class: "solution"))[
  #_e("summary")[Solution #ref]
  #body
]
#let solutions-appendix() = none  // web shows solutions inline as <details>

// ---- figure (CeTZ canvas -> inline SVG) -------------------------------------
#let fig(caption, body) = _e("figure", attrs: (class: "diagram"))[
  #html.frame(body)
  #_e("figcaption")[#caption]
]

// ---- harmless stubs for paged-only helpers (not used inside chapters) ------
#let partdivider(numeral, title) = none
#let book(..args) = none
