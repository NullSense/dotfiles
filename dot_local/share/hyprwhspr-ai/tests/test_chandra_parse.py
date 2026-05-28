"""Tests for the Chandra OCR 2 output parser.

Chandra emits two formats depending on which checkpoint / chat template
is in use:
  - HTML divs (the format the official Python lib expects)
  - JSON array of typed blocks (what the community GGUFs emit)

Both must produce sensible markdown.
"""

from __future__ import annotations

import importlib.util

import pytest

from src.services.chandra_parse import parse_chandra_to_markdown


# The HTML-format path needs the optional "ocr" extra (beautifulsoup4 +
# the official chandra lib). Skip those tests when the deps aren't present;
# the JSON/GGUF path tests run unconditionally.
_needs_bs4 = pytest.mark.skipif(
    importlib.util.find_spec("bs4") is None,
    reason="optional 'beautifulsoup4' not installed (extra: ocr)",
)
_needs_chandra = pytest.mark.skipif(
    importlib.util.find_spec("chandra") is None,
    reason="optional 'chandra' OCR lib not installed (extra: ocr)",
)


# ---------------------------------------------------------------------
# JSON format (GGUF output)

def test_json_section_header_and_text():
    raw = '[{"type":"Section-Header","text":"Hello"},{"type":"Text","text":"World"}]'
    out = parse_chandra_to_markdown(raw)
    assert out == "## Hello\n\nWorld"


def test_json_inline_html_to_markdown():
    """Chandra embeds <b>, <code>, <i> inside the text field."""
    raw = '[{"type":"Text","text":"This is <b>bold</b> and <code>code</code>."}]'
    out = parse_chandra_to_markdown(raw)
    assert "**bold**" in out
    assert "`code`" in out


def test_json_table_to_gfm():
    raw = (
        '[{"type":"Table","table":['
        '{"col":"a","val":1},'
        '{"col":"b","val":2}'
        ']}]'
    )
    out = parse_chandra_to_markdown(raw)
    assert "| col | val |" in out
    assert "|---|---|" in out
    assert "| a | 1 |" in out
    assert "| b | 2 |" in out


def test_json_tolerant_to_number_thousands():
    """Chandra emits `1,820` inside number values — invalid JSON. Parser
    must normalize and still produce the correct table."""
    raw = (
        '[{"type":"Table","table":['
        '{"name":"warm","ms":251},'
        '{"name":"cold","ms":1,820}'
        ']}]'
    )
    out = parse_chandra_to_markdown(raw)
    assert "1820" in out
    assert "251" in out


def test_json_tolerant_to_unescaped_quotes():
    """Chandra emits unescaped `""` in code text fields. Parser must
    recover at least the type + text up to the bad quote rather than
    failing the whole document."""
    raw = (
        '[{"type":"Section-Header","text":"Header"},'
        '{"type":"Text","text":"Code: x = ""empty"" here"},'
        '{"type":"Text","text":"After"}]'
    )
    out = parse_chandra_to_markdown(raw)
    assert "## Header" in out
    assert "After" in out
    # Some Code-shaped content survives even if not all of it
    assert "Code:" in out or "x =" in out


def test_json_block_types_render_correctly():
    cases = [
        ('[{"type":"Title","text":"T"}]', "# T"),
        ('[{"type":"Sub-Section-Header","text":"S"}]', "### S"),
        ('[{"type":"List-item","text":"x"}]', "- x"),
        ('[{"type":"Numbered-List-item","text":"x"}]', "1. x"),
        ('[{"type":"Caption","text":"x"}]', "*x*"),
    ]
    for raw, expected in cases:
        assert parse_chandra_to_markdown(raw) == expected


def test_json_page_header_footer_filtered():
    raw = (
        '[{"type":"Page-Header","text":"Hidden"},'
        '{"type":"Text","text":"Body"},'
        '{"type":"Page-Footer","text":"Hidden"}]'
    )
    out = parse_chandra_to_markdown(raw)
    assert "Hidden" not in out
    assert "Body" in out


def test_json_text_that_looks_like_code_gets_fenced():
    raw = (
        '[{"type":"Text","text":"def foo():\\n    return 42\\nx = foo()"}]'
    )
    out = parse_chandra_to_markdown(raw)
    assert out.startswith("```")
    assert out.endswith("```")
    assert "def foo()" in out


def test_json_short_text_does_not_get_fenced():
    """Single-line text should NOT be code-fenced even if it has code-like
    keywords."""
    raw = '[{"type":"Text","text":"return early"}]'
    out = parse_chandra_to_markdown(raw)
    assert "```" not in out


def test_json_html_entities_decoded():
    raw = '[{"type":"Text","text":"x &gt; y &amp;&amp; a &lt; b"}]'
    out = parse_chandra_to_markdown(raw)
    assert "x > y && a < b" in out


# ---------------------------------------------------------------------
# HTML format (official model output)

@_needs_chandra
def test_html_path_uses_official_parser():
    raw = (
        '<div data-label="Section-Header" data-bbox="0 0 100 30"><h1>Hello</h1></div>'
        '<div data-label="Text" data-bbox="0 30 100 60"><p>World</p></div>'
    )
    out = parse_chandra_to_markdown(raw)
    # Official parser uses ATX-style heading
    assert "# Hello" in out
    assert "World" in out


@_needs_bs4
def test_html_table_post_processed_to_gfm():
    raw = (
        '<div data-label="Table" data-bbox="0 0 100 100">'
        '<table><thead><tr><th>A</th><th>B</th></tr></thead>'
        '<tbody><tr><td>1</td><td>2</td></tr></tbody></table>'
        '</div>'
    )
    out = parse_chandra_to_markdown(raw)
    assert "| A | B |" in out
    assert "|---|---|" in out
    assert "| 1 | 2 |" in out


def test_html_complex_table_kept_as_html():
    """A table with rowspan/colspan can't be GFM — keep raw HTML."""
    raw = (
        '<div data-label="Table" data-bbox="0 0 100 100">'
        '<table><tr><th colspan="2">Group</th></tr>'
        '<tr><td>1</td><td>2</td></tr></table>'
        '</div>'
    )
    out = parse_chandra_to_markdown(raw)
    assert "<table" in out  # untouched


@_needs_chandra
def test_html_page_headers_filtered():
    raw = (
        '<div data-label="Page-Header" data-bbox="0 0 100 20"><p>Hide me</p></div>'
        '<div data-label="Text" data-bbox="0 20 100 80"><p>Body</p></div>'
        '<div data-label="Page-Footer" data-bbox="0 80 100 100"><p>Hide me too</p></div>'
    )
    out = parse_chandra_to_markdown(raw)
    assert "Hide me" not in out
    assert "Body" in out


# ---------------------------------------------------------------------
# Edge cases

def test_empty_input():
    assert parse_chandra_to_markdown("") == ""
    assert parse_chandra_to_markdown("   ") == ""


def test_already_markdown_passthrough():
    """If Chandra decides to emit markdown directly (rare), we pass it
    through unchanged."""
    raw = "# Already markdown\n\nWith a paragraph."
    out = parse_chandra_to_markdown(raw)
    assert out == raw


def test_fenced_json_payload():
    """Sometimes the model wraps its output in ```json ... ```."""
    raw = '```json\n[{"type":"Text","text":"x"}]\n```'
    out = parse_chandra_to_markdown(raw)
    assert out == "x"


def test_unparseable_garbage_returned_as_is():
    """If we genuinely can't parse, return the raw so the user at least
    sees something rather than empty."""
    raw = "[{this is not json at all}]"
    out = parse_chandra_to_markdown(raw)
    assert out  # non-empty
