"""Tests for prompt construction.

We don't validate the model's output here — that's the e2e suite's job.
We validate that the prompt CONTAINS the right pieces in the right
order, since those are the structural invariants that make Gemma
behave correctly.
"""

from __future__ import annotations

from src.prompts import build_rewrite_prompt, wrap_rewrite_input
from src.window import Context, MarkdownDialect, Window


def test_wrap_input_uses_text_start_end_delimiters():
    out = wrap_rewrite_input("hello world")
    assert "[TEXT START]" in out
    assert "[TEXT END]" in out
    assert "hello world" in out


def test_wrap_input_includes_rewrite_directive():
    """The user-block reminds the model to rewrite, not respond."""
    out = wrap_rewrite_input("any text")
    assert "Rewrite" in out
    assert "Output only" in out


def test_rewrite_prompt_includes_universal_rules():
    win = Window(cls="generic", title="")
    p = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, "")
    assert "Output ONLY the rewritten text" in p
    assert "[TEXT START]" in p and "[TEXT END]" in p
    # Anti-injection rule
    assert "Never answer questions" in p


def test_rewrite_prompt_includes_app_context_block():
    win = Window(cls="discord", title="general")
    p = build_rewrite_prompt(win, Context.CHAT, MarkdownDialect.DISCORD, "")
    assert "[App context]" in p
    assert "class=discord" in p
    assert "title=general" in p
    assert "context=chat" in p


def test_rewrite_prompt_per_context_style_chat_discord():
    win = Window(cls="discord", title="")
    p = build_rewrite_prompt(win, Context.CHAT, MarkdownDialect.DISCORD, "")
    assert "Discord" in p or "Telegram" in p
    # Discord uses standard markdown
    assert "**bold**" in p


def test_rewrite_prompt_per_context_style_chat_slack():
    win = Window(cls="Slack", title="")
    p = build_rewrite_prompt(win, Context.CHAT, MarkdownDialect.SLACK, "")
    # Slack mrkdwn — single asterisk warning
    assert "SINGLE asterisk" in p


def test_rewrite_prompt_per_context_style_email():
    win = Window(cls="thunderbird", title="")
    p = build_rewrite_prompt(win, Context.EMAIL, MarkdownDialect.NONE, "")
    assert "email" in p.lower()
    assert "Don't invent greetings" in p or "greetings/sign-offs" in p


def test_rewrite_prompt_per_context_style_agent_cli():
    win = Window(cls="ghostty", title="claude")
    p = build_rewrite_prompt(win, Context.AGENT_CLI, MarkdownDialect.NONE, "")
    assert "terminal coding agent" in p
    assert "Imperative" in p


def test_rewrite_prompt_per_context_style_notes():
    win = Window(cls="obsidian", title="")
    p = build_rewrite_prompt(win, Context.NOTES, MarkdownDialect.NONE, "")
    assert "CommonMark" in p


def test_rewrite_prompt_includes_vocab_block_when_present():
    win = Window(cls="generic", title="")
    vocab = "\n\n[Known vocabulary]\nThe user uses Cortiq, Tensil."
    p = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, vocab)
    assert "[Known vocabulary]" in p
    assert "Cortiq" in p


def test_rewrite_prompt_omits_vocab_block_when_empty():
    """When vocab is empty, no actual vocab terms should leak into the
    prompt. The string '[Known vocabulary]' may still appear in the
    rules text as a concept reference — that's expected."""
    win = Window(cls="generic", title="")
    p_empty = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, "")
    p_full = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, "\n\n[Known vocabulary]\nThe user uses XyzzyMagic.")
    assert "XyzzyMagic" in p_full
    assert "XyzzyMagic" not in p_empty
    # And the empty prompt is shorter than the full one (vocab block adds bytes)
    assert len(p_full) > len(p_empty)


def test_rewrite_prompt_static_head_stable_for_caching():
    """Per the prefix-cache layout: head + vocab + examples + tail are
    stable across calls (per-fixed-vocab). Only the [App context] +
    style block at the END changes. This test verifies the order so
    llama.cpp's KV cache can reuse the prefix."""
    win = Window(cls="generic", title="")
    p1 = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, "")
    p2 = build_rewrite_prompt(win, Context.CHAT, MarkdownDialect.DISCORD, "")
    # Find the dynamic [App context] start in both
    head1 = p1[: p1.index("[App context]")]
    head2 = p2[: p2.index("[App context]")]
    assert head1 == head2, "static head must be byte-identical across contexts"


def test_rewrite_prompt_examples_present():
    """Few-shots ARE the load-bearing way Gemma learns the [TEXT START]
    convention and behavioral nuances."""
    win = Window(cls="generic", title="")
    p = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, "")
    # Number-normalization example
    assert "64GB" in p and "12GB" in p
    # Numbered-list (sequential) example
    assert "1. Set up the project" in p
    # Bullet-list with header example
    assert "- Node 20" in p
    # Plain "[verb] X, Y, and Z" → bullets (without speaker-stated header)
    assert "I want:" in p
    assert "- apples" in p and "- bananas" in p and "- oranges" in p
    # Grocery / 4-item buy list
    assert "I need to buy:" in p
    # Narrative exception (then-prose)
    assert "I went to the store, then the gym, then home." in p
    # Threshold: 2 items stays prose
    assert "I want apples and bananas." in p


def test_rewrite_prompt_lists_rule_mentions_threshold():
    """The 3+ threshold is the load-bearing rule — verify it's stated."""
    win = Window(cls="generic", title="")
    p = build_rewrite_prompt(win, Context.GENERIC, MarkdownDialect.NONE, "")
    assert "3+" in p
    # Default-bullets policy
    assert "Default is BULLETS" in p
    # Narrative exception is called out
    assert "NARRATIVE EXCEPTION" in p


# ---------------------------------------------------------------------
# OCR mode prompts

def test_ocr_prompt_faithful_mentions_structure():
    from src.prompts import ocr_prompt_for
    p = ocr_prompt_for("faithful")
    # Tables, code, ASCII, multi-column all called out
    assert "TABLE" in p
    assert "MULTI-COLUMN" in p
    assert "CODE" in p
    assert "ASCII" in p
    # Markdown emphasis encoded
    assert "**bold**" in p and "*italic*" in p
    # Don't invent emphasis — anti-hallucination guard
    assert "Do NOT invent" in p


def test_ocr_prompt_faithful_anti_confabulation():
    """The CRITICAL RULES block fights pattern-completion hallucination
    after a real-world test where Gemma autocompleted lists from priors
    (PyAudio / Whisper / Gemini / threadpool not in source)."""
    from src.prompts import ocr_prompt_for
    p = ocr_prompt_for("faithful")
    assert "TRANSCRIBE, DO NOT PARAPHRASE" in p
    assert "DO NOT SUMMARIZE" in p
    # Specific anti-pattern names from the failure mode
    assert "PyAudio" in p or "Whisper" in p
    # The unclear-span signal
    assert "[?]" in p
    # ASCII art guard: pixel-level transcription, not interpretation
    assert "PIXEL-LEVEL" in p
    # LaTeX confusion guard
    assert "LaTeX" in p


def test_ocr_prompt_plain_strips_formatting():
    from src.prompts import ocr_prompt_for
    p = ocr_prompt_for("plain")
    # Explicit strip rule
    assert "STRIP" in p or "Strip" in p
    # Mentions translator as the consumer (justifies why)
    assert "translator" in p.lower()
    # Tables → prose flatten
    assert "flatten" in p.lower() or "row-by-row" in p.lower()


def test_ocr_prompt_modes_are_distinct():
    from src.prompts import ocr_prompt_for
    a = ocr_prompt_for("faithful")
    b = ocr_prompt_for("plain")
    assert a != b
    # Sanity: faithful is meaningfully longer (it has more rules to enumerate)
    assert len(a) > len(b)


def test_ocr_prompt_unknown_mode_raises():
    from src.prompts import ocr_prompt_for
    import pytest
    with pytest.raises(ValueError) as excinfo:
        ocr_prompt_for("klingon")
    assert "klingon" in str(excinfo.value).lower()


def test_ocr_back_compat_constant():
    """VISION_OCR is preserved as an alias of the faithful prompt."""
    from src.prompts import VISION_OCR, VISION_OCR_FAITHFUL
    assert VISION_OCR == VISION_OCR_FAITHFUL
