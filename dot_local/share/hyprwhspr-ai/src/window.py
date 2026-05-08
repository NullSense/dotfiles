"""Window context detection.

Calls ``hyprctl activewindow -j`` and classifies the focused window
into a Context enum. Cached for a short TTL so multiple rapid
requests don't re-fork hyprctl.

Context families (carried forward from the bash classifier):

  agent-cli      — terminal whose title says claude/codex/aider/opencode
  terminal       — bare shell/git terminal
  code-editor    — VSCode, Zed, JetBrains, helix, neovide, etc.
  email          — Thunderbird et al, OR a browser tab on Gmail/Outlook
  chat           — Discord/Slack/Signal/etc., OR browser tab matching
  browser        — fallback for browsers
  notes          — Obsidian/Logseq/Notion/Google Docs
  generic        — anything else
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass
from enum import Enum
from typing import Optional


log = logging.getLogger(__name__)


class Context(str, Enum):
    AGENT_CLI = "agent-cli"
    TERMINAL = "terminal"
    CODE_EDITOR = "code-editor"
    EMAIL = "email"
    CHAT = "chat"
    BROWSER = "browser"
    NOTES = "notes"
    GENERIC = "generic"


class MarkdownDialect(str, Enum):
    NONE = "none"        # plain text — Signal, iMessage, terminals
    DISCORD = "discord"  # Discord/Telegram/Element — standard markdown
    SLACK = "slack"      # Slack mrkdwn — *bold* (single asterisk!)


@dataclass(frozen=True, slots=True)
class Window:
    cls: str    # WM_CLASS
    title: str

    @property
    def class_lower(self) -> str:
        return self.cls.lower()

    @property
    def title_lower(self) -> str:
        return self.title.lower()


# Class-name patterns are matched as substrings (lowercased).
_TERMINAL_CLASSES = {
    "org.wezfurlong.wezterm", "foot", "kitty", "alacritty",
    "com.mitchellh.ghostty", "ghostty", "xterm", "st", "wezterm",
    "terminator",
}
_EMAIL_CLASSES = ("thunderbird", "evolution", "geary", "bluemail",
                  "mailspring", "betterbird")
_CHAT_CLASSES = ("discord", "vesktop", "signal", "telegram", "element",
                 "slack", "beeper", "whatsapp", "teams", "teams-for-linux",
                 "fractal")
_CODE_EDITOR_CLASSES = ("code", "code-oss", "codium", "vscodium", "cursor",
                        "zed", "jetbrains", "idea", "pycharm", "webstorm",
                        "goland", "rustrover", "clion", "sublime_text",
                        "gedit", "kate", "nvim-qt", "neovide", "helix")
_BROWSER_CLASSES = ("firefox", "firefoxdeveloperedition", "chromium",
                    "brave-browser", "google-chrome", "microsoft-edge",
                    "zen", "librewolf", "vivaldi", "helium")
_NOTES_CLASSES = ("obsidian", "logseq", "notion", "joplin", "standardnotes",
                  "anytype")

# Title patterns that promote a browser to a more specific context.
_BROWSER_TITLE_EMAIL = ("gmail", "mail.google", "outlook", "proton mail",
                        "fastmail", "tutanota")
_BROWSER_TITLE_CHAT = ("discord", " slack", "messenger", " x.com", "twitter",
                       "reddit", "whatsapp", " teams", "matrix")
_BROWSER_TITLE_CODE = ("github.com", "gitlab.com", " jira", "linear.app")
_BROWSER_TITLE_NOTES = ("docs.google", "notion.so", " confluence", "onedrive")

# Title patterns inside terminals that promote to agent-cli.
_TERMINAL_TITLE_AGENT = ("claude", "codex", "aider", "ollama", "opencode",
                         "goose", "cursor chat")


class WindowProvider:
    """Cached window-context provider.

    Calls hyprctl at most once per cache TTL (default 2s). Concurrent
    callers within the TTL window get the cached result. The cache
    invalidates by age, not by signal — the trade is cheap.
    """

    def __init__(self, cache_ttl_s: float):
        self._ttl = cache_ttl_s
        self._cached: Optional[Window] = None
        self._cached_at: float = 0.0
        self._lock = asyncio.Lock()

    async def current(self, force_refresh: bool = False) -> Window:
        now = time.time()
        if (not force_refresh
                and self._cached is not None
                and (now - self._cached_at) < self._ttl):
            return self._cached
        async with self._lock:
            # Re-check under lock (TOCTOU).
            now = time.time()
            if (not force_refresh
                    and self._cached is not None
                    and (now - self._cached_at) < self._ttl):
                return self._cached
            win = await self._fetch()
            self._cached = win
            self._cached_at = now
            return win

    @staticmethod
    async def _fetch() -> Window:
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            return Window(cls="", title="")
        try:
            proc = await asyncio.create_subprocess_exec(
                "hyprctl", "activewindow", "-j",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=1.0)
            if proc.returncode != 0 or not out:
                return Window(cls="", title="")
            data = json.loads(out)
            return Window(cls=data.get("class") or "", title=data.get("title") or "")
        except (asyncio.TimeoutError, json.JSONDecodeError, FileNotFoundError) as e:
            log.warning("hyprctl activewindow failed: %s", e)
            return Window(cls="", title="")


def classify(window: Window) -> Context:
    """Map a Window to a Context. Pure function, easy to unit-test."""
    cls = window.class_lower
    title = window.title_lower

    # Direct class match.
    if cls in _TERMINAL_CLASSES:
        ctx = Context.TERMINAL
    elif any(p in cls for p in _EMAIL_CLASSES):
        ctx = Context.EMAIL
    elif any(p in cls for p in _CHAT_CLASSES):
        ctx = Context.CHAT
    elif any(p in cls for p in _CODE_EDITOR_CLASSES):
        ctx = Context.CODE_EDITOR
    elif any(p in cls for p in _BROWSER_CLASSES):
        ctx = Context.BROWSER
    elif any(p in cls for p in _NOTES_CLASSES):
        ctx = Context.NOTES
    else:
        ctx = Context.GENERIC

    # Browser title heuristics (Gmail-in-Firefox → email, etc.).
    if ctx == Context.BROWSER:
        if any(p in title for p in _BROWSER_TITLE_EMAIL):
            ctx = Context.EMAIL
        elif any(p in title for p in _BROWSER_TITLE_CHAT):
            ctx = Context.CHAT
        elif any(p in title for p in _BROWSER_TITLE_CODE):
            ctx = Context.CODE_EDITOR
        elif any(p in title for p in _BROWSER_TITLE_NOTES):
            ctx = Context.NOTES

    # Terminal title → agent-cli (Claude Code, Codex, aider, etc.).
    if ctx == Context.TERMINAL and any(p in title for p in _TERMINAL_TITLE_AGENT):
        ctx = Context.AGENT_CLI

    return ctx


def markdown_dialect(window: Window, ctx: Context) -> MarkdownDialect:
    """Determine the markdown dialect for the chat context.

    For non-chat contexts, returns NONE (handled by per-context style).
    """
    if ctx != Context.CHAT:
        return MarkdownDialect.NONE
    cls = window.class_lower
    title = window.title_lower
    if any(p in cls for p in ("discord", "vesktop", "telegram", "element")):
        return MarkdownDialect.DISCORD
    if "slack" in cls:
        return MarkdownDialect.SLACK
    # Browser-promoted-to-chat — peek at title.
    if cls in _BROWSER_CLASSES or any(b in cls for b in _BROWSER_CLASSES):
        if any(p in title for p in ("discord", "telegram", "messenger")):
            return MarkdownDialect.DISCORD
        if " slack" in title:
            return MarkdownDialect.SLACK
    return MarkdownDialect.NONE
