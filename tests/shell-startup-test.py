#!/usr/bin/env python3
"""Check terminal-only integrations from the real zsh startup config."""
import os
from pathlib import Path
import subprocess
import unittest


class ShellStartupTest(unittest.TestCase):
    config = (Path(__file__).resolve().parents[1] / "home/.zshrc").read_text()

    def integration(self, marker):
        return next(line for line in self.config.splitlines() if marker in line and not line.startswith("#"))

    def check_startup(self, fragment, term):
        result = subprocess.run(
            ["zsh", "-fic", fragment],
            env={**os.environ, "TERM": term},
            text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(result.stderr, "")

    def test_fzf_without_line_editor(self):
        self.check_startup(self.integration("source /usr/share/fzf/key-bindings.zsh"), "xterm-256color")

    def test_prompt_in_dumb_terminal(self):
        self.check_startup(self.integration("starship init zsh"), "dumb")


if __name__ == "__main__":
    unittest.main()
