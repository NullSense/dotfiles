"""Tests for the output-cleanup logic in RewriteService.

These are the defenses against:
  - Qwen's <think>...</think> blocks leaking through despite our prefill
  - Gemma occasionally wrapping output in code fences or quotes
"""

from __future__ import annotations

from src.services.rewrite import _clean_output


def test_strips_think_blocks():
    out = _clean_output("<think>some reasoning</think>actual answer")
    assert out == "actual answer"


def test_strips_multiline_think_blocks():
    raw = "<think>\nstep 1\nstep 2\n</think>\n\nFinal answer."
    assert _clean_output(raw) == "Final answer."


def test_strips_multiple_think_blocks():
    raw = "<think>a</think>start<think>b</think>end"
    assert _clean_output(raw) == "startend"


def test_strips_leading_code_fence():
    raw = "```\nactual answer\n```"
    out = _clean_output(raw)
    assert out == "actual answer"


def test_strips_leading_code_fence_with_lang():
    raw = "```python\nprint('hi')\n```"
    out = _clean_output(raw)
    assert out == "print('hi')"


def test_strips_surrounding_double_quotes():
    assert _clean_output('"hello world"') == "hello world"


def test_strips_surrounding_single_quotes():
    assert _clean_output("'hello world'") == "hello world"


def test_strips_surrounding_backticks():
    assert _clean_output("`hello`") == "hello"


def test_does_not_strip_internal_quotes():
    """Internal quotes around a phrase should survive."""
    assert _clean_output('She said "hello" loudly') == 'She said "hello" loudly'


def test_does_not_strip_mismatched_quotes():
    """Only matching pair on outer ends should be stripped."""
    assert _clean_output('"hello\'') == '"hello\''


def test_strips_leading_trailing_whitespace():
    assert _clean_output("\n\n  hello world  \n\n") == "hello world"


def test_empty_input_stays_empty():
    assert _clean_output("") == ""


def test_only_think_block_returns_empty():
    """If the model returned ONLY a thinking block, cleaning leaves
    nothing — caller should treat as fallback."""
    assert _clean_output("<think>just thinking</think>") == ""


def test_unicode_preserved():
    assert _clean_output("Hyprland — žingsnis") == "Hyprland — žingsnis"


def test_complex_combo():
    """Real-world: think block + leading fence + surrounding quotes."""
    raw = "<think>analyzing</think>```\n\"final answer\"\n```"
    # think stripped → ```\n"final answer"\n``` → "final answer" → final answer
    assert _clean_output(raw) == "final answer"
