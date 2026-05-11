#!/home/nullsense/.local/share/hyprwhspr-ai/.venv/bin/python
"""OCR benchmark — Gemma vs Chandra vs Hybrid vs Surya vs Qwen.

For each case in `cases/<name>.html`:
  1. Use the rendered `images/<name>.png` (run executable_generate.sh first).
  2. For each requested engine, time `hyprwhspr-ai ocr --engine <e>` against it.
  3. Record latency, output length, and a lightweight quality flag against
     the ground-truth `cases/<name>.md`.
  4. Emit a markdown report with side-by-side timings and a quality score.

Engine availability is auto-detected from LM Studio's loaded models. To
include `qwen`, load Qwen 3.6 35B-A3B in LM Studio first (you'll need to
eject Gemma+Chandra to fit it). Pass `--qwen-model <id>` to override.

Usage:
    ./executable_run.py [--engines gemma,chandra,hybrid,surya,qwen] \
                        [--qwen-model qwen_qwen3.6-35b-a3b] \
                        [--repeat N] [--out report.md]
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import httpx


HERE = Path(__file__).parent
CASES_DIR = HERE / "cases"
IMAGES_DIR = HERE / "images"

LMS_URL = "http://127.0.0.1:1234"
DAEMON_CLI = "hyprwhspr-ai"


# ---------- result types --------------------------------------------------


@dataclass
class RunResult:
    engine: str
    case: str
    output: str
    latency_ms: int
    error: str | None = None
    quality: dict = field(default_factory=dict)


# ---------- engine adapters -----------------------------------------------


def run_via_daemon(engine: str, image_path: Path, *, timeout: float) -> tuple[str, int]:
    """Invoke the hyprwhspr-ai CLI for daemon-routed engines."""
    t0 = time.perf_counter()
    proc = subprocess.run(
        [DAEMON_CLI, "ocr", "--engine", engine, str(image_path)],
        capture_output=True, text=True, timeout=timeout,
    )
    elapsed = int((time.perf_counter() - t0) * 1000)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"daemon exit {proc.returncode}")
    return proc.stdout, elapsed


def run_via_lmstudio_direct(model_id: str, image_path: Path, *, timeout: float) -> tuple[str, int]:
    """Direct LM Studio call — used for engines we don't expose through the
    daemon (Qwen, since it's not OCR-specialized but worth comparing).
    Sends a minimal OCR prompt; same temperature=0 / max_tokens we use for
    Chandra/Gemma so the comparison is apples-to-apples."""
    img_bytes = image_path.read_bytes()
    b64 = base64.b64encode(img_bytes).decode("ascii")
    body = {
        "model": model_id,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
                {"type": "text", "text": (
                    "Convert this image to clean GitHub-flavored markdown. "
                    "Preserve tables (as markdown tables), code (in fenced blocks), "
                    "lists, headings, and emphasis. Output only the markdown."
                )},
            ],
        }],
        "max_tokens": 4096,
        "temperature": 0.0,
        "stream": False,
    }
    t0 = time.perf_counter()
    with httpx.Client(timeout=timeout) as c:
        r = c.post(f"{LMS_URL}/v1/chat/completions", json=body)
        r.raise_for_status()
        text = r.json()["choices"][0]["message"]["content"] or ""
    elapsed = int((time.perf_counter() - t0) * 1000)
    return text.strip(), elapsed


# ---------- quality heuristics --------------------------------------------


def _normalize_for_compare(s: str) -> str:
    """Strip whitespace + lowercase for sloppy similarity scoring."""
    s = re.sub(r"\s+", " ", s).strip().lower()
    # Common Chandra/Gemma divergence: dashes, smart quotes
    s = (s.replace("—", "-")  # em dash
           .replace("–", "-")  # en dash
           .replace("−", "-")  # minus
           .replace("“", '"').replace("”", '"')
           .replace("‘", "'").replace("’", "'"))
    return s


def char_recall(actual: str, expected: str) -> float:
    """Fraction of expected characters that appear in actual (order-insensitive
    bag-of-chars). Crude but fast — flags huge omissions."""
    if not expected:
        return 1.0
    a = _normalize_for_compare(actual)
    e = _normalize_for_compare(expected)
    if not a:
        return 0.0
    from collections import Counter
    ca, ce = Counter(a), Counter(e)
    matched = sum(min(ca[c], ce[c]) for c in ce)
    return matched / sum(ce.values())


def has_markdown_table(s: str) -> bool:
    """Detect a GFM markdown table — header line + separator line."""
    lines = s.splitlines()
    for i in range(len(lines) - 1):
        if "|" in lines[i] and re.match(r"^\s*\|?(\s*:?-+:?\s*\|)+\s*:?-+:?\s*\|?\s*$", lines[i + 1]):
            return True
    return False


def has_code_fence(s: str) -> bool:
    return bool(re.search(r"```\w*\n.*?\n```", s, re.DOTALL))


def has_heading(s: str) -> bool:
    return bool(re.search(r"^#{1,6}\s+\S", s, re.MULTILINE))


def quality_metrics(actual: str, expected: str) -> dict:
    return {
        "char_recall": round(char_recall(actual, expected), 3),
        "has_table": has_markdown_table(actual),
        "expected_table": has_markdown_table(expected),
        "has_code_fence": has_code_fence(actual),
        "expected_code_fence": has_code_fence(expected),
        "has_heading": has_heading(actual),
        "expected_heading": has_heading(expected),
        "out_chars": len(actual),
        "expected_chars": len(expected),
    }


# ---------- driver --------------------------------------------------------


def discover_loaded_models() -> dict[str, dict]:
    """Hit /api/v0/models so we can skip engines whose models aren't loaded."""
    try:
        r = httpx.get(f"{LMS_URL}/api/v0/models", timeout=5.0)
        r.raise_for_status()
        return {m["id"]: m for m in r.json().get("data", [])}
    except Exception as e:
        print(f"warning: couldn't query LM Studio ({e}); engine availability is a guess",
              file=sys.stderr)
        return {}


def run_engine(engine: str, image: Path, timeout: float, qwen_model: str) -> RunResult:
    case_name = image.stem
    try:
        if engine == "qwen":
            out, ms = run_via_lmstudio_direct(qwen_model, image, timeout=timeout)
        else:
            out, ms = run_via_daemon(engine, image, timeout=timeout)
        return RunResult(engine=engine, case=case_name, output=out, latency_ms=ms)
    except subprocess.TimeoutExpired:
        return RunResult(engine=engine, case=case_name, output="", latency_ms=int(timeout * 1000),
                         error=f"timeout after {timeout}s")
    except Exception as e:
        return RunResult(engine=engine, case=case_name, output="", latency_ms=0, error=str(e))


def render_report(results: list[RunResult], cases: list[str], engines: list[str]) -> str:
    lines: list[str] = []
    lines.append("# OCR Benchmark Report")
    lines.append("")
    lines.append(f"_Run on {time.strftime('%Y-%m-%d %H:%M:%S')}._")
    lines.append("")
    lines.append("## Latency (ms)")
    lines.append("")
    header = "| Case | " + " | ".join(engines) + " |"
    sep = "|---|" + "|".join("---" for _ in engines) + "|"
    lines.append(header)
    lines.append(sep)
    by = {(r.engine, r.case): r for r in results}
    for c in cases:
        cells = []
        for e in engines:
            r = by.get((e, c))
            if r is None or r.error:
                cells.append("—" if r is None else f"err: {r.error[:30]}")
            else:
                cells.append(f"{r.latency_ms}")
        lines.append(f"| {c} | " + " | ".join(cells) + " |")
    lines.append("")

    lines.append("## Quality (char-recall vs ground truth, structure preservation)")
    lines.append("")
    lines.append("| Case | Engine | Recall | Table | Code | Heading | Chars (got/expected) |")
    lines.append("|---|---|---|---|---|---|---|")
    for c in cases:
        for e in engines:
            r = by.get((e, c))
            if r is None or r.error:
                continue
            q = r.quality
            t = "✅" if q["has_table"] == q["expected_table"] else "❌"
            cf = "✅" if q["has_code_fence"] == q["expected_code_fence"] else "❌"
            h = "✅" if q["has_heading"] == q["expected_heading"] else "❌"
            lines.append(
                f"| {c} | {e} | {q['char_recall']:.2f} | {t} | {cf} | {h} "
                f"| {q['out_chars']}/{q['expected_chars']} |"
            )
    lines.append("")

    lines.append("## Per-engine summary")
    lines.append("")
    for e in engines:
        rs = [r for r in results if r.engine == e and not r.error]
        if not rs:
            lines.append(f"- **{e}** — no successful runs")
            continue
        avg_ms = sum(r.latency_ms for r in rs) / len(rs)
        avg_recall = sum(r.quality.get("char_recall", 0) for r in rs) / len(rs)
        lines.append(f"- **{e}** — avg latency {avg_ms:.0f} ms, avg char-recall {avg_recall:.2f} ({len(rs)}/{len(cases)} successful)")
    lines.append("")

    # Full per-case outputs (collapsed) — useful for eyeballing.
    lines.append("## Full outputs (for eyeballing)")
    lines.append("")
    for c in cases:
        lines.append(f"### {c}")
        lines.append("")
        for e in engines:
            r = by.get((e, c))
            if r is None or r.error:
                continue
            lines.append(f"<details><summary>{e} ({r.latency_ms} ms, {len(r.output)} chars)</summary>")
            lines.append("")
            lines.append("```")
            lines.append(r.output)
            lines.append("```")
            lines.append("")
            lines.append("</details>")
            lines.append("")
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--engines", default="gemma,chandra,hybrid,surya",
                   help="comma-separated engines to run (default: gemma,chandra,hybrid,surya)")
    p.add_argument("--qwen-model", default="qwen_qwen3.6-35b-a3b",
                   help="LM Studio model id for the qwen comparison")
    p.add_argument("--timeout", type=float, default=300.0,
                   help="per-call timeout in seconds (default 300)")
    p.add_argument("--out", default=str(HERE / "report.md"),
                   help="output report path")
    p.add_argument("--cases", default=None,
                   help="comma-separated case names to run (default: all)")
    args = p.parse_args()

    engines = [e.strip() for e in args.engines.split(",") if e.strip()]

    if not IMAGES_DIR.exists() or not list(IMAGES_DIR.glob("*.png")):
        print("no images yet — running ./executable_generate.sh first", file=sys.stderr)
        gen = HERE / "executable_generate.sh"
        if gen.is_file():
            subprocess.run([str(gen)], check=True)
        else:
            print("can't find executable_generate.sh; render images manually", file=sys.stderr)
            return 2

    images = sorted(IMAGES_DIR.glob("*.png"))
    if args.cases:
        wanted = {c.strip() for c in args.cases.split(",")}
        images = [i for i in images if i.stem in wanted]
    if not images:
        print("no matching cases", file=sys.stderr)
        return 2

    # Engine availability check
    loaded = discover_loaded_models()
    skip = []
    if "qwen" in engines:
        if args.qwen_model not in loaded or loaded[args.qwen_model].get("state") != "loaded":
            skip.append("qwen")
            print(f"⚠ qwen model '{args.qwen_model}' is not loaded — load it in LM Studio "
                  f"(eject Gemma+Chandra first) and re-run, or remove qwen from --engines",
                  file=sys.stderr)
    if "chandra" in engines and ("chandra-ocr-2" not in loaded or
                                 loaded["chandra-ocr-2"].get("state") != "loaded"):
        skip.append("chandra")
        print("⚠ chandra-ocr-2 is not loaded; chandra results will fail", file=sys.stderr)
    engines = [e for e in engines if e not in skip]

    print(f"engines: {engines}")
    print(f"cases:   {[i.stem for i in images]}")
    print()

    results: list[RunResult] = []
    for img in images:
        case = img.stem
        gt = (CASES_DIR / f"{case}.md").read_text() if (CASES_DIR / f"{case}.md").is_file() else ""
        for e in engines:
            print(f"→ {e:8s} | {case} ", end="", flush=True)
            r = run_engine(e, img, args.timeout, args.qwen_model)
            r.quality = quality_metrics(r.output, gt) if not r.error else {}
            results.append(r)
            if r.error:
                print(f"  ✗ {r.error}")
            else:
                print(f"  ✓ {r.latency_ms} ms, {len(r.output)} chars, "
                      f"recall={r.quality.get('char_recall', 0):.2f}")
    print()

    cases = sorted({r.case for r in results})
    report = render_report(results, cases, engines)

    # Persist every run under runs/<timestamp>/ so we can compare across runs.
    # Also write report.md/.json at HERE for the "latest" view, and append a
    # one-line summary per run to runs/history.jsonl for trend tracking.
    runs_dir = HERE / "runs"
    runs_dir.mkdir(exist_ok=True)
    run_stamp = time.strftime("%Y%m%d_%H%M%S")
    run_dir = runs_dir / run_stamp
    run_dir.mkdir(exist_ok=True)
    (run_dir / "report.md").write_text(report)
    print(f"wrote {run_dir / 'report.md'} ({len(report)} chars)")

    # Per-engine summary stats for the history log.
    summary = {
        "timestamp": run_stamp,
        "engines": engines,
        "cases": cases,
        "n_cases": len(cases),
        "per_engine": {},
    }
    for e in engines:
        rs = [r for r in results if r.engine == e]
        ok = [r for r in rs if not r.error]
        summary["per_engine"][e] = {
            "successful": len(ok),
            "errored": len(rs) - len(ok),
            "avg_latency_ms": round(sum(r.latency_ms for r in ok) / len(ok), 0) if ok else None,
            "avg_char_recall": round(sum(r.quality.get("char_recall", 0) for r in ok) / len(ok), 3) if ok else None,
            "empty_outputs": sum(1 for r in ok if not r.output),
        }
    # Append the summary line to history.jsonl.
    history_path = runs_dir / "history.jsonl"
    with history_path.open("a") as f:
        f.write(json.dumps(summary) + "\n")
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"appended summary to {history_path}")

    # 'Latest' alias paths at the top level — convenient default for users
    # who just want the most recent report without digging into runs/.
    Path(args.out).write_text(report)

    # Stash raw results JSON too
    json_out = Path(args.out).with_suffix(".json")
    raw_json = json.dumps([
        {**r.__dict__, "output": r.output[:500]}  # truncate for compactness
        for r in results
    ], indent=2)
    json_out.write_text(raw_json)
    (run_dir / "report.json").write_text(raw_json)
    print(f"wrote {json_out}")
    print()
    print(f"  run dir: {run_dir}")
    print(f"  history: {history_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
