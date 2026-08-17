#!/usr/bin/env python3
"""Regression tests for Beans' native delegation policy plugin."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
from unittest.mock import patch


PLUGIN = Path.home() / ".hermes/plugins/native-delegation/__init__.py"
spec = importlib.util.spec_from_file_location("native_delegation", PLUGIN)
assert spec and spec.loader
plugin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)


def main() -> None:
    assert plugin._needs_native_delegation(
        "Review this repository for link safety. This is clean non-personal programming work."
    )
    assert not plugin._needs_native_delegation(
        "Review my private Telegram messages and remember what my doctor said."
    )
    assert not plugin._needs_native_delegation("Fix this typo; do not delegate it.")

    with tempfile.TemporaryDirectory() as temp:
        home = Path(temp)
        db_path = home / "state.db"
        with sqlite3.connect(db_path) as db:
            db.executescript(
                "CREATE TABLE messages (id INTEGER PRIMARY KEY, session_id TEXT, role TEXT, "
                "content TEXT, active INTEGER, tool_name TEXT, tool_calls TEXT);"
            )
            db.execute(
                "INSERT INTO messages VALUES (1, 'technical', 'user', ?, 1, NULL, NULL)",
                ("Audit the systemd service configuration for startup races.",),
            )
            db.execute(
                "INSERT INTO messages VALUES (2, 'private', 'user', ?, 1, NULL, NULL)",
                ("Review my private finances and bank mail.",),
            )
        old_home = os.environ.get("HERMES_HOME")
        os.environ["HERMES_HOME"] = str(home)
        try:
            blocked = plugin._on_pre_tool_call(
                tool_name="terminal", args={"command": "systemctl --user status"},
                session_id="technical",
            )
            assert blocked and blocked["action"] == "block"
            assert plugin._on_pre_tool_call(
                tool_name="terminal",
                args={"command": "opencode run --model opencode-go/deepseek-v4-flash brief"},
                session_id="technical",
            ) is None
            assert plugin._on_pre_tool_call(
                tool_name="terminal", args={"command": "ls"}, session_id="private"
            ) is None
            with sqlite3.connect(db_path) as db:
                db.execute(
                    "INSERT INTO messages VALUES (3, 'technical', 'tool', '', 1, "
                    "'native_delegate', NULL)"
                )
            assert plugin._on_pre_tool_call(
                tool_name="read_file", args={"path": "/etc/fstab"}, session_id="technical"
            ) is None
        finally:
            if old_home is None:
                os.environ.pop("HERMES_HOME", None)
            else:
                os.environ["HERMES_HOME"] = old_home

    env = plugin._scrubbed_environment()
    assert not any(
        fragment in name.upper()
        for name in env
        for fragment in ("KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL", "AUTH")
    )

    with tempfile.TemporaryDirectory() as temp:
        exhausted = SimpleNamespace(returncode=1, stdout="Error: Insufficient balance")
        codex_ok = SimpleNamespace(returncode=0, stdout="review complete")
        with patch.object(plugin.subprocess, "run", side_effect=[exhausted, codex_ok]) as run:
            result = plugin._handle_native_delegate({
                "worker": "opencode_easy",
                "task": "Audit this repository test suite.",
                "cwd": temp,
                "write_access": False,
            })
        assert run.call_count == 2
        assert run.call_args_list[0].args[0][:2] == ["opencode", "run"]
        assert run.call_args_list[1].args[0][:2] == ["codex", "exec"]
        assert "worker_used" in result and "codex" in result
    print("PASS: native delegation policy")


if __name__ == "__main__":
    main()
