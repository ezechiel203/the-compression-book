# tinyzip — the canonical build-along project spec

`tinyzip` is the real, working compressor the reader builds across the book, one `#project` step at a
time. To stay coherent across 81 independently-authored chapters, EVERY `#project` block MUST follow this
spec exactly: use the **canonical step number(s), module names, and function signatures assigned to your
chapter below**, import and reuse the modules earlier chapters created, and NEVER invent your own numbering
or rename existing functions.

## Package layout (Python 3.14)
```
tinyzip/
  __init__.py      # version, public API
  cli.py           # `python -m tinyzip compress/decompress/bench <file>`
  utils.py         # histogram(), helpers, timing
  bitio.py         # BitWriter, BitReader
  container.py     # file header (magic/version/method/size) + payload + CRC-32
  model.py         # entropy(), cross_entropy(), AdaptiveBitModel (KT)
  huffman.py       # build_tree(), encode(), decode()  (canonical Huffman)
  codes.py         # unary, elias_gamma, rice/golomb
  arithmetic.py    # ArithmeticEncoder/Decoder (range coder)
  ans.py           # rANS encode()/decode()
  lz77.py          # find_matches(), parse(), tokens
  deflate.py       # lz77 + huffman  -> method="deflate"
  bwt.py           # bwt(), ibwt(), mtf(), imtf()
  bench.py         # run all methods on a corpus, print the scoreboard
  transform.py     # dct1d(), idct1d(), dct2d(), idct2d()  (8x8)
  quant.py         # scalar quantizer + dead-zone
  jpeg.py          # toy JPEG encode/decode -> method="jpeg"
  llmzip.py        # model P(next) + arithmetic coder demo
```
Conventions: `bytes` in / `bytes` out for codecs; type hints everywhere (`dict[int,int]`, `tuple[bytes,int]`);
every codec round-trips (`decode(encode(x)) == x`) and ships with a tiny self-test.

## Canonical step table (step #, chapter, what it adds)
**Phase A — plumbing (Volume I)**
1. Ch15 — `tinyzip/` package skeleton + `cli.py`; read a file into `bytes`.
2. Ch16 — `utils.histogram(data: bytes) -> dict[int,int]` + summary stats.
3. Ch17 — `bitio.BitWriter` and `bitio.BitReader`.
4. Ch17 — `container.write(method, payload)` / `container.read()` (magic+version+method+size header).
5. Ch17 — CRC-32 integrity footer in the container.
6. Ch18–19 — `model.entropy(data) -> float`; the "entropy meter" that prints the theoretical floor.
7. Ch23 — `model.AdaptiveBitModel` (Krichevsky–Trofimov estimator) for adaptive prediction.

**Phase B — lossless coders (Volume II)**
8.  Ch24 — `huffman.py`: canonical Huffman `encode`/`decode`; first real `method="huffman"`.
9.  Ch25 — `codes.py`: unary, Elias γ, Rice/Golomb (for residual streams).
10. Ch26 — `arithmetic.py`: range/arithmetic coder driven by `model`.
11. Ch27 — `ans.py`: rANS encode/decode; selectable entropy backend.
12. Ch28 — `lz77.py`: sliding-window match finder + greedy parser + token stream.
13. Ch30 — `deflate.py`: LZ77 + Huffman → `method="deflate"` (the gzip-class milestone).
14. Ch32 — compression levels + optional trained dictionary hook.
15. Ch35 — `bwt.py`: `bwt`/`ibwt` + MTF + RLE → `method="bwt"` (bzip2-class).
16. Ch36 — `bench.py`: run every method on a real corpus and print the running scoreboard.

**Phase C — lossy (Volume III)**
17. Ch37–38 — `transform.py`: `dct1d`/`idct1d`, then 8×8 `dct2d`/`idct2d`.
18. Ch39 — `quant.py`: uniform scalar quantizer with a dead-zone.
19. Ch42 — `jpeg.py`: toy JPEG (DCT → quant → zig-zag → Huffman) → `method="jpeg"`, with PSNR.
20. Ch51 — block motion-compensation demo on two frames (inter-prediction).

**Phase D — neural / AI (Volume IV)**
21. Ch56–57 — a minimal learned-transform sketch (concept-level, numpy).
22. Ch62 — `llmzip.py`: an autoregressive P(next token) model + the `arithmetic` coder → LLM-as-compressor demo.

## Rules for chapter authors
- Implement ONLY the step(s) assigned to your chapter number above. If your chapter has no step here, you may
  still show illustrative Python, but do not add a `#project` step or invent a step number.
- `import` and reuse the modules/functions defined in earlier steps; keep names identical.
- Each `#project("Step N · <title>")` block builds incrementally on the previous step and round-trips.
- The running `#scoreboard` should reflect `bench.py` results once Step 16 exists; before that, cite the
  bytes each new method achieves on the shared sample.
> Note: Volume I chapters were drafted before this spec; their `#project` step numbers will be reconciled to
> this table during the Opus audit pass. New chapters (24+) must follow it precisely.
