# OCR Benchmark

Side-by-side comparison of OCR engines on a fixed test suite.

## What's measured

For each test case, every engine runs OCR on the same rendered image. The runner records:

- **Latency** — wall-clock ms per call.
- **Char-recall** — fraction of ground-truth characters that appear in the output (sloppy but fast — flags huge omissions).
- **Structure preservation** — does the output have markdown tables / fenced code / headings where the source did?
- **Output size** — chars produced vs. chars expected.

## Test cases

Modeled after categories in **olmOCR-Bench**, **OmniDocBench**, and **ParseBench** — the established document-AI benchmarks. Each case stresses a specific capability dimension that those benchmarks evaluate.

| File | Capability dimension | Source benchmark equivalent |
|---|---|---|
| `01_simple_doc` | mixed elements (heading + paragraph + table + code + emphasis) | OmniDocBench academic-paper |
| `02_complex_table` | dense numeric table, currency, totals row | olmOCR `table_tests` |
| `03_two_column` | reading order across columns | olmOCR `multi_column` |
| `04_code_heavy` | code blocks with indentation, docstrings, type hints | ParseBench `semantic_formatting.code_blocks` |
| `05_non_latin` | 10 scripts incl. RTL (Arabic, Hebrew) | OmniDocBench multilingual / MDPBench |
| `06_math_special` | math symbols, arrows, Greek, super/subscript | olmOCR `arxiv_math` |
| `07_chart_bar` | bar chart datapoint extraction | ParseBench `charts` |
| `08_receipt` | line-item extraction with totals | SROIE / CORD / JaWildText `receipt_kie` |
| `09_form` | form fields + checkbox state (checked vs unchecked) | FUNSD / OmniDocBench forms |
| `10_chat` | chat UI with usernames, timestamps, mentions, inline code | application-screenshot OCR |
| `11_terminal` | colored terminal output, command + output blocks | code/log OCR |
| `12_emphasis` | bold/italic/strike/underline/sub/sup mix | ParseBench `semantic_formatting.text_styling` |
| `13_nested_lists` | numbered + alpha + bulleted, three levels deep | OmniDocBench `list_item` |
| `14_small_dense` | 9 pt 2-column legalese, fine-print stress test | olmOCR `long_tiny_text` |

Add more by dropping `cases/<name>.html` + `cases/<name>.md` (ground truth) into the `cases/` directory. The runner picks them up automatically.

## Running

```
# 1. Render the images (once, or whenever HTML changes — script caches).
./generate.sh

# 2. Run the benchmark. The shebang points at the daemon's venv (where
#    httpx + bs4 live), so no manual venv activation needed.
./run.py

# Subset of engines:
./run.py --engines chandra,gemma

# Subset of cases:
./run.py --cases 01_simple_doc,02_complex_table

# Include Qwen 3.6 35B-A3B (must be loaded in LM Studio first — won't fit
# alongside Gemma+Chandra in 12 GB VRAM, so eject those two before loading Qwen):
./run.py --engines gemma,chandra,hybrid,surya,qwen
```

## Engine availability

The runner checks LM Studio's `/api/v0/models` and skips engines whose models aren't loaded. To benchmark Qwen, you'll need to manually swap models in LM Studio (Gemma + Chandra ≈ 11.8 GB; Qwen Q5_K_M ≈ 22 GB — they don't coexist).

## Output

Every run writes to **two** places:

1. **`report.md` / `report.json`** at the top level — the latest run, convenient for quick inspection. Overwritten each run.
2. **`runs/<YYYYMMDD_HHMMSS>/`** — per-run snapshot. `report.md`, `report.json`, and a compact `summary.json` (avg latency + recall per engine, empty-output counts). Never overwritten.

In addition, **`runs/history.jsonl`** appends one summary line per run, suitable for plotting regressions over time:

```bash
# Inspect score trends across runs
jq -c '{ts: .timestamp, engines: [.per_engine | to_entries[] | {(.key): .value.avg_char_recall}]}' \
  runs/history.jsonl
```

What's in each artifact:

- `report.md` — latency table, quality table, per-engine summary, full per-case outputs in collapsible sections.
- `report.json` — raw results, output truncated to 500 chars per cell (full outputs are in the markdown).
- `summary.json` — per-engine aggregates only: successful, errored, avg_latency_ms, avg_char_recall, empty_outputs.
- `history.jsonl` — one summary per run, append-only, never rewritten.

## What "good" looks like

- **char-recall ≥ 0.95** — most of the ground-truth content survived.
- **table/code/heading ✅ in every row** — structure preserved, not flattened.
- **Latency** matters less than quality for an interactive use case at this scale; anything under ~30 s is fine for opt-in OCR.
