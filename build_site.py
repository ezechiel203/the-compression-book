#!/usr/bin/env python3
"""Build the static website for The Compression Book from chapter .typ sources."""
import json, os, re, shutil, subprocess, html
from concurrent.futures import ThreadPoolExecutor

ROOT = "/home/ezechiel203/Projects/RESEARCH/compression/book"
SITE = f"{ROOT}/web/site"
RAW = f"{SITE}/_raw"
TYPST = os.path.expanduser("~/.local/bin/typst")
os.makedirs(RAW, exist_ok=True)
os.makedirs(f"{SITE}/pdf", exist_ok=True)

out = json.load(open(f"{ROOT}/outline.json"))
chapters = out["chapters"]
volumes = out["volumes"]
by_num = {c["number"]: c for c in chapters}
nums = sorted(by_num)
vol_short = {v: v.split(" — ")[0] for v in volumes}
vol_title = {v: v.split(" — ", 1)[1] if " — " in v else v for v in volumes}

def compile_raw(c):
    n = c["number"]; tmp = f"{ROOT}/chapters/_web{n:02d}.typ"
    src = open(f"{ROOT}/{c['file']}").read().split("\n")
    src[0] = src[0].replace("../lib.typ", "../web.typ")
    open(tmp, "w").write("\n".join(src))
    r = subprocess.run([TYPST, "compile", "--features", "html", "--root", ROOT,
                        tmp, f"{RAW}/ch{n:02d}.html"], capture_output=True, text=True)
    os.remove(tmp)
    return (n, r.returncode, (r.stderr or "")[:200])

print("compiling 81 chapters to raw HTML ...")
fails = []
with ThreadPoolExecutor(max_workers=6) as ex:
    for n, rc, err in ex.map(compile_raw, chapters):
        if rc != 0:
            fails.append(n); print(f"  FAIL ch{n}: {err}")
print(f"raw built: {81 - len(fails)}/81" + (f"  fails={fails}" if fails else ""))

# ---- sidebar nav (mark current chapter/volume) ----
def sidebar(cur):
    cur_vol = by_num[cur]["volume"]
    parts = ['<nav class="sidebar" id="sb">']
    parts.append('<h3>The Compression Book</h3>')
    for v in volumes:
        cs = [c for c in chapters if c["volume"] == v]
        op = " open" if v == cur_vol else ""
        parts.append(f'<details{op}><summary>{html.escape(vol_short[v])} — {html.escape(vol_title[v])}</summary><ol>')
        for c in cs:
            cls = ' class="cur"' if c["number"] == cur else ""
            parts.append(f'<li><a{cls} href="ch{c["number"]:02d}.html">{c["number"]}. {html.escape(c["title"])}</a></li>')
        parts.append('</ol></details>')
    parts.append('</nav>')
    return "".join(parts)

TOPBAR = ('<div class="topbar"><button id="menuBtn" aria-label="menu">☰</button>'
          '<a class="brand" href="index.html">The Compression Book</a>'
          '<span class="spacer"></span><span class="vol">{vol}</span>'
          '<a href="pdf/TheCompressionBook-{volfile}.pdf" class="vol">PDF ↓</a></div>')
SCRIPT = ('<script>document.getElementById("menuBtn").onclick=function(){'
          'document.getElementById("sb").classList.toggle("open")};'
          'document.querySelectorAll(".sidebar a").forEach(a=>a.onclick=()=>'
          'document.getElementById("sb").classList.remove("open"));</script>')

def chapnav(n):
    i = nums.index(n); out = ['<div class="chapnav">']
    if i > 0:
        p = by_num[nums[i-1]]
        out.append(f'<a class="prev" href="ch{p["number"]:02d}.html"><span class="lbl">← Previous</span>{html.escape(p["title"])}</a>')
    if i < len(nums)-1:
        nx = by_num[nums[i+1]]
        out.append(f'<a class="next" href="ch{nx["number"]:02d}.html"><span class="lbl">Next →</span>{html.escape(nx["title"])}</a>')
    out.append('</div>')
    return "".join(out)

volfile = {volumes[i]: f"Vol{i+1}" for i in range(len(volumes))}
volnum = {volumes[i]: i+1 for i in range(len(volumes))}

def assemble(c):
    n = c["number"]; raw = open(f"{RAW}/ch{n:02d}.html").read()
    title = f'{n}. {c["title"]} — The Compression Book'
    topbar = TOPBAR.format(vol=html.escape(vol_short[c["volume"]]), volfile=volfile[c["volume"]])
    raw = raw.replace("</head>", f'<title>{html.escape(title)}</title>'
                      f'<link rel="stylesheet" href="book.css"></head>', 1)
    raw = raw.replace("<body>", f'<body>{topbar}<div class="layout">{sidebar(n)}'
                      f'<main class="chapter">', 1)
    raw = raw.replace("</body>", f'{chapnav(n)}</main></div>{SCRIPT}</body>', 1)
    open(f"{SITE}/ch{n:02d}.html", "w").write(raw)

for c in chapters:
    if c["number"] not in fails:
        assemble(c)

# ---- copy PDFs (before computing page counts) ----
for i in range(1, 6):
    s = f"{ROOT}/TheCompressionBook-Vol{i}.pdf"
    if os.path.exists(s): shutil.copy(s, f"{SITE}/pdf/")

# ---- landing page ----
def pages_of(pdf):
    try:
        d = open(pdf, "rb").read(); return len(re.findall(rb"/Type\s*/Page[^s]", d))
    except: return 0
cards = []
for i, v in enumerate(volumes, 1):
    cs = [c for c in chapters if c["volume"] == v]
    first = cs[0]["number"]
    pdf = f"{SITE}/pdf/TheCompressionBook-Vol{i}.pdf"
    pp = pages_of(pdf)
    cards.append(f'<a class="volcard" href="ch{first:02d}.html"><div class="vn">{html.escape(vol_short[v])}</div>'
                 f'<div class="vt">{html.escape(vol_title[v])}</div>'
                 f'<div class="vm">{len(cs)} chapters · {pp} pp · <a href="pdf/TheCompressionBook-Vol{i}.pdf">PDF</a></div></a>')
total_pp = sum(pages_of(f"{SITE}/pdf/TheCompressionBook-Vol{i}.pdf") for i in range(1, 6))
index = f'''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The Compression Book</title><link rel="stylesheet" href="book.css"></head><body>
<div class="topbar"><a class="brand" href="index.html">The Compression Book</a></div>
<div class="hero">
<h1>The Compression Book</h1>
<p class="sub">A Complete History and Technical Treatise on Data Compression — June 2026</p>
<p>From zero to expert, assuming only 9th-grade mathematics. Five volumes, 81 chapters, ~768,000 words —
with a from-scratch Python&nbsp;3.14 primer, the <code>tinyzip</code> build-along compressor, exercises with
solutions, and diagrams throughout. Read it in your browser, or download each volume as a PDF.</p>
<div class="volgrid">{''.join(cards)}</div>
<p class="dl"><b>Start reading:</b> <a href="ch01.html">Chapter 1 — What Is Compression?</a>
&nbsp;·&nbsp; {total_pp} pages total &nbsp;·&nbsp;
<a href="pdf/TheCompressionBook-Vol1.pdf">all PDFs in the menu</a></p>
</div></body></html>'''
open(f"{SITE}/index.html", "w").write(index)


print(f"site built: {len([c for c in chapters if c['number'] not in fails])} chapter pages + index")
print(f"total pages across PDFs: {total_pp}")
