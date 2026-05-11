"""Tests for the window classifier and markdown dialect detection.

Pure-function tests — no async, no fixtures, no mocks needed.
"""

from __future__ import annotations

import pytest

from src.window import (
    Context,
    MarkdownDialect,
    Window,
    classify,
    markdown_dialect,
)


# ---------------------------------------------------------------------
# Context classification

@pytest.mark.parametrize("cls,title,expected", [
    # Terminals
    ("foot", "shell", Context.TERMINAL),
    ("kitty", "user@host", Context.TERMINAL),
    ("alacritty", "", Context.TERMINAL),
    ("com.mitchellh.ghostty", "shell", Context.TERMINAL),
    ("org.wezfurlong.wezterm", "", Context.TERMINAL),
    # Terminal title → agent-cli
    ("com.mitchellh.ghostty", "claude — repo", Context.AGENT_CLI),
    ("foot", "codex - some-project", Context.AGENT_CLI),
    ("kitty", "aider", Context.AGENT_CLI),
    ("alacritty", "Cursor Chat", Context.AGENT_CLI),
    ("foot", "ollama: running model", Context.AGENT_CLI),
    # Email clients
    ("thunderbird", "Inbox", Context.EMAIL),
    ("evolution", "", Context.EMAIL),
    ("Geary", "", Context.EMAIL),
    ("BlueMail", "", Context.EMAIL),
    # Chat
    ("discord", "", Context.CHAT),
    ("Vesktop", "general", Context.CHAT),
    ("Signal", "", Context.CHAT),
    ("org.telegram.desktop", "", Context.CHAT),
    ("element", "", Context.CHAT),
    ("Slack", "", Context.CHAT),
    ("Beeper", "", Context.CHAT),
    # Code editors
    ("code", "main.py", Context.CODE_EDITOR),
    ("Code-OSS", "", Context.CODE_EDITOR),
    ("VSCodium", "", Context.CODE_EDITOR),
    ("zed", "", Context.CODE_EDITOR),
    ("jetbrains-pycharm", "", Context.CODE_EDITOR),
    ("helix", "", Context.CODE_EDITOR),
    ("neovide", "", Context.CODE_EDITOR),
    # Browsers — bare class with no title hints
    ("firefox", "", Context.BROWSER),
    ("chromium", "", Context.BROWSER),
    ("brave-browser", "", Context.BROWSER),
    # Browser title heuristics — promote to email/chat/etc.
    ("firefox", "Inbox - Gmail", Context.EMAIL),
    ("chromium", "Outlook", Context.EMAIL),
    ("firefox", "general — Discord", Context.CHAT),
    ("brave-browser", "channel | Slack", Context.CHAT),
    ("firefox", "github.com/foo/bar", Context.CODE_EDITOR),
    ("chromium", "Some Doc - Google Docs (docs.google)", Context.NOTES),
    # Notes
    ("obsidian", "vault", Context.NOTES),
    ("Logseq", "", Context.NOTES),
    # Generic fallback
    ("some-random-app", "", Context.GENERIC),
    ("", "", Context.GENERIC),
])
def test_classify(cls: str, title: str, expected: Context):
    assert classify(Window(cls=cls, title=title)) == expected


# ---------------------------------------------------------------------
# Markdown dialect

def test_dialect_non_chat_is_none():
    """Email, terminal, etc. → no markdown."""
    win = Window(cls="thunderbird", title="")
    assert markdown_dialect(win, Context.EMAIL) == MarkdownDialect.NONE


def test_dialect_discord():
    win = Window(cls="discord", title="")
    assert markdown_dialect(win, Context.CHAT) == MarkdownDialect.DISCORD


def test_dialect_telegram_is_discord():
    """Telegram uses the same modern markdown as Discord."""
    win = Window(cls="org.telegram.desktop", title="")
    assert markdown_dialect(win, Context.CHAT) == MarkdownDialect.DISCORD


def test_dialect_slack():
    win = Window(cls="Slack", title="")
    assert markdown_dialect(win, Context.CHAT) == MarkdownDialect.SLACK


def test_dialect_signal_is_plain():
    """Signal renders asterisks literally — no markdown."""
    win = Window(cls="signal", title="")
    assert markdown_dialect(win, Context.CHAT) == MarkdownDialect.NONE


# ---------------------------------------------------------------------
# Window helpers

def test_window_lower_methods():
    w = Window(cls="FireFox", title="My TITLE")
    assert w.class_lower == "firefox"
    assert w.title_lower == "my title"
