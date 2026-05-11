"""Convert Chandra OCR 2's raw output to clipboard-friendly markdown.

Chandra emits two output formats depending on which checkpoint and chat
template you're using:

  1. HTML divs (the format the official `chandra` Python lib expects):
       <div data-label="Section-Header" data-bbox="...">...</div>
       <div data-label="Table" data-bbox="...">...</div>
     For this we use `chandra.output.parse_markdown` directly — it's
     tested, handles math/images/headers/footers, and uses BeautifulSoup
     + markdownify under the hood.

  2. JSON array of typed blocks (what the GGUF builds emit, since their
     chat template differs from the official model's):
       [{"type": "Section-Header", "text": "..."},
        {"type": "Table", "table": [{"col": "v", ...}, ...]}, ...]
     For this we tolerantly parse — Chandra GGUF often emits malformed
     JSON (unescaped quotes inside text, comma-grouped numbers in
     numeric values), so we fix common malformations and fall back to
     per-block regex extraction when strict json.loads fails.

The pipeline auto-detects which format we got and routes accordingly.
"""

from __future__ import annotations

import html
import json
import logging
import re
from typing import Any

from bs4 import BeautifulSoup
from chandra.output import parse_markdown as _chandra_parse_markdown


log = logging.getLogger(__name__)


# ---------- HTML format (official) — minimal post-processing of tables ----------

_TABLE_BLOCK_RE = re.compile(r"<table[^>]*>.*?</table>", re.DOTALL | re.IGNORECASE)


def _table_html_to_gfm(table_html: str) -> str | None:
    """Convert a simple HTML table to GFM. Returns None if too complex
    (rowspan/colspan/ragged rows) so caller keeps the raw HTML."""
    try:
        soup = BeautifulSoup(table_html, "html.parser")
    except Exception:
        return None
    table = soup.find("table")
    if table is None:
        return None
    rows = table.find_all("tr")
    if not rows:
        return None

    grid: list[list[str]] = []
    for tr in rows:
        cells = tr.find_all(["th", "td"])
        if not cells:
            continue
        for c in cells:
            if int(c.get("rowspan", 1)) > 1 or int(c.get("colspan", 1)) > 1:
                return None  # GFM can't represent merges
        row_text: list[str] = []
        for c in cells:
            text = c.get_text(separator=" ", strip=True)
            text = text.replace("|", "\\|").replace("\n", " ")
            row_text.append(text)
        grid.append(row_text)

    if not grid:
        return None
    cols = len(grid[0])
    if any(len(r) != cols for r in grid):
        return None  # ragged

    out = ["| " + " | ".join(grid[0]) + " |"]
    out.append("|" + "|".join("---" for _ in range(cols)) + "|")
    for row in grid[1:]:
        out.append("| " + " | ".join(row) + " |")
    return "\n".join(out)


def _post_process_tables(markdown: str) -> str:
    def repl(m: re.Match[str]) -> str:
        gfm = _table_html_to_gfm(m.group(0))
        return gfm if gfm is not None else m.group(0)
    return _TABLE_BLOCK_RE.sub(repl, markdown)


def _parse_html_format(raw: str) -> str:
    """Run the official chandra parser, then convert simple tables to GFM."""
    try:
        md = _chandra_parse_markdown(
            raw,
            include_headers_footers=False,
            include_images=True,
        )
    except Exception as e:
        log.warning("chandra HTML parser failed: %s", e)
        return ""
    return _post_process_tables(md).strip()


# ---------- JSON format (GGUF-style) — tolerant parser ----------

# Inline HTML → markdown (Chandra embeds <b>, <code>, etc. inside text fields).
_HTML_INLINE_TO_MD = [
    (re.compile(r"<b>(.*?)</b>", re.DOTALL),         r"**\1**"),
    (re.compile(r"<strong>(.*?)</strong>", re.DOTALL), r"**\1**"),
    (re.compile(r"<i>(.*?)</i>", re.DOTALL),         r"*\1*"),
    (re.compile(r"<em>(.*?)</em>", re.DOTALL),       r"*\1*"),
    (re.compile(r"<code>(.*?)</code>", re.DOTALL),   r"`\1`"),
    (re.compile(r"<s>(.*?)</s>", re.DOTALL),         r"~~\1~~"),
    (re.compile(r"<del>(.*?)</del>", re.DOTALL),     r"~~\1~~"),
    (re.compile(r"<u>(.*?)</u>", re.DOTALL),         r"**\1**"),
    (re.compile(r"<sub>(.*?)</sub>", re.DOTALL),     r"\1"),
    (re.compile(r"<sup>(.*?)</sup>", re.DOTALL),     r"\1"),
    (re.compile(r"<a[^>]*>(.*?)</a>", re.DOTALL),    r"\1"),
    (re.compile(r"<br\s*/?>"),                       "\n"),
]


def _inline_md(text: str) -> str:
    out = text
    for pat, repl in _HTML_INLINE_TO_MD:
        out = pat.sub(repl, out)
    return html.unescape(out)


_NUMBER_COMMA_RE = re.compile(r"(\d),(\d{3})\b")


def _normalize_chandra_json(raw: str) -> str:
    """Strip number thousands separators (`1,820` → `1820`) which break
    json.loads. Multiple passes handle chained numbers like `1,234,567`."""
    prev = None
    while prev != raw:
        prev = raw
        raw = _NUMBER_COMMA_RE.sub(r"\1\2", raw)
    return raw


_BLOCK_START_RE = re.compile(r'\{\s*"type"\s*:\s*"[^"]+"', re.DOTALL)


def _split_blocks(raw: str) -> list[str]:
    """Find each `{"type": "...", ...}` block; advance to its matching
    closing brace at depth 0. Robust to malformed inner content because
    we slice based on brace depth, not by parsing."""
    blocks: list[str] = []
    i = 0
    n = len(raw)
    while i < n:
        m = _BLOCK_START_RE.search(raw, i)
        if not m:
            break
        start = m.start()
        depth = 0
        in_str = False
        esc = False
        j = start
        while j < n:
            ch = raw[j]
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"' and not esc:
                in_str = not in_str
            elif not in_str:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        blocks.append(raw[start:j + 1])
                        i = j + 1
                        break
            j += 1
        else:
            break
    return blocks


def _table_dicts_to_gfm(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return ""
    cols = list(rows[0].keys())
    if not cols:
        return ""
    head = "| " + " | ".join(_inline_md(str(c)) for c in cols) + " |"
    sep = "|" + "|".join("---" for _ in cols) + "|"
    body = []
    for r in rows:
        body.append("| " + " | ".join(_inline_md(str(r.get(c, "") or "")) for c in cols) + " |")
    return "\n".join([head, sep, *body])


def _looks_like_code(text: str) -> bool:
    """Heuristic: a Text block is actually code if multi-line + indented."""
    lines = text.split("\n")
    if len(lines) < 2:
        return False
    indented = sum(1 for l in lines if l.startswith(("    ", "\t")))
    keywordy = sum(1 for l in lines if re.search(r"\b(def|class|return|import|from|async|if|else|for|while)\b", l))
    return indented >= 2 or (keywordy / max(len(lines), 1)) >= 0.6


def _block_to_md(block: dict[str, Any]) -> str:
    btype = (block.get("type") or "").strip()
    text = _inline_md(str(block.get("text") or "")).strip()

    if btype in ("Title",):
        return f"# {text}" if text else ""
    if btype in ("Section-Header",):
        return f"## {text}" if text else ""
    if btype in ("Sub-Section-Header", "Subsection-Header"):
        return f"### {text}" if text else ""
    if btype in ("Page-Header", "Page-Footer"):
        return ""  # filtered, like the official parser does by default
    if btype == "Caption":
        return f"*{text}*" if text else ""
    if btype == "List-item":
        return f"- {text}" if text else ""
    if btype == "Numbered-List-item":
        return f"1. {text}" if text else ""
    if btype == "Code":
        lang = block.get("language") or ""
        code = html.unescape(str(block.get("text") or ""))
        return f"```{lang}\n{code}\n```"
    if btype == "Math":
        m = str(block.get("text") or "").strip()
        return f"$$\n{m}\n$$" if "\n" in m else f"${m}$"
    if btype == "Table":
        rows = block.get("table") or block.get("rows") or []
        if isinstance(rows, list):
            return _table_dicts_to_gfm(rows)
        return ""
    if btype in ("Image", "Figure", "Diagram"):
        cap = _inline_md(str(block.get("caption") or "")).strip()
        return f"![{cap}]()"
    if btype == "Checkbox":
        marker = "[x]" if block.get("checked") else "[ ]"
        return f"- {marker} {text}"
    if btype == "Form":
        out = []
        for f in block.get("fields") or []:
            label = _inline_md(str(f.get("label") or ""))
            value = _inline_md(str(f.get("value") or ""))
            out.append(f"- **{label}:** {value}")
        return "\n".join(out)

    # Default (Text, Paragraph, anything else): code-detect if shaped like one.
    if not text:
        return ""
    if btype == "Text" and _looks_like_code(text):
        return f"```\n{text}\n```"
    return text


def _parse_json_format(raw: str) -> str:
    raw = _normalize_chandra_json(raw)
    parsed: list[dict] = []

    # Fast path: strict json.loads of the whole thing.
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            parsed = [b for b in data if isinstance(b, dict)]
        elif isinstance(data, dict):
            parsed = [data]
    except json.JSONDecodeError:
        # Tolerant path: split into per-block strings, parse each.
        skipped = 0
        for chunk in _split_blocks(raw):
            try:
                parsed.append(json.loads(chunk))
                continue
            except json.JSONDecodeError:
                pass
            # Last resort — regex out type+text and recover that much.
            m_type = re.search(r'"type"\s*:\s*"([^"]+)"', chunk)
            m_text = re.search(r'"text"\s*:\s*"((?:[^"\\]|\\.)*)"', chunk, re.DOTALL)
            if m_type:
                t = m_type.group(1)
                inner = ""
                if m_text:
                    try:
                        inner = json.loads(f'"{m_text.group(1)}"')
                    except json.JSONDecodeError:
                        inner = m_text.group(1)
                parsed.append({"type": t, "text": inner})
            else:
                skipped += 1
        if skipped:
            log.info("chandra: skipped %d unparseable blocks", skipped)

    if not parsed:
        return ""
    rendered = [_block_to_md(b) for b in parsed]
    rendered = [r for r in rendered if r]
    return "\n\n".join(rendered)


# ---------- entry point ----------

def parse_chandra_to_markdown(raw: str) -> str:
    """Auto-detect HTML vs JSON Chandra output and route accordingly.
    Returns clean GFM markdown. On total parse failure returns the raw
    string so the user at least gets something to look at."""
    if not raw or not raw.strip():
        return ""
    raw = raw.strip()
    # Peel ```json/html ... ``` fence if the model wrapped it.
    fence = re.match(r"^```(?:json|html)?\s*(.+?)\s*```$", raw, re.DOTALL)
    if fence:
        raw = fence.group(1).strip()

    if raw.startswith(("[", "{")):
        out = _parse_json_format(raw)
        return out if out else raw

    if raw.startswith("<"):
        out = _parse_html_format(raw)
        return out if out else raw

    # Already plain text/markdown — return as-is.
    return raw
