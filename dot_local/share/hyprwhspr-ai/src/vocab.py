"""Vocabulary file reader with mtime-based caching.

User maintains ~/.config/hyprwhspr/vocabulary.txt (chezmoi-managed).
We read it once, watch its mtime, and only re-read when the file
changes. The result is the pre-formatted "[Known vocabulary]" block
that the rewrite system prompt injects into every request — building
this once per change instead of once per dictation.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path


log = logging.getLogger(__name__)


@dataclass
class VocabRepository:
    """Reads + caches the user's vocabulary list.

    Atomic re-read on mtime change. No file watch (inotify) needed —
    we check mtime on every access, which is cheap (single stat call).
    """

    path: Path
    _mtime: float = field(default=-1.0, init=False)
    _block: str = field(default="", init=False)

    def block(self) -> str:
        """Return the formatted vocabulary block to inject in prompts.

        Returns empty string if no vocabulary file exists or it's empty.
        """
        try:
            mtime = self.path.stat().st_mtime
        except FileNotFoundError:
            self._mtime = -1.0
            self._block = ""
            return ""
        if mtime == self._mtime:
            return self._block
        try:
            terms: list[str] = []
            for line in self.path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                terms.append(line)
        except OSError as e:
            log.warning("vocab read failed: %s", e)
            self._mtime = -1.0
            self._block = ""
            return ""
        if not terms:
            self._block = ""
        else:
            joined = ", ".join(terms)
            self._block = (
                "\n\n[Known vocabulary]\n"
                f"The user uses these proper nouns / specialized terms regularly: {joined}.\n"
                "If the input contains a token that looks like a phonetic near-miss of any "
                "of these (different spelling, missing/added letters, similar sound), correct "
                "it to the canonical form above. Be conservative: only swap if you are confident "
                "it's a near-miss; do NOT introduce these words otherwise. Preserve case as listed."
            )
        self._mtime = mtime
        return self._block
