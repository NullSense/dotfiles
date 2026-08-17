"""Native subscription-worker delegation with a conservative privacy gate."""

from __future__ import annotations

import os
from pathlib import Path
import re
import sqlite3
import subprocess
from typing import Any

from tools.registry import tool_error, tool_result


_TECHNICAL = re.compile(
    r"\b(?:program(?:ming)?|repository|repo|code|coding|workstation|systemd|"
    r"journal|logs?|config(?:uration)?|service|linux|arch|dotfiles?|tests?|"
    r"bugs?|debug|package|dependency|files?|project)\b",
    re.IGNORECASE,
)
_BROAD_ACTION = re.compile(
    r"\b(?:review|investigat|audit|implement|fix|repair|refactor|migrat|"
    r"diagnos|inspect|perus|analy[sz]|trace|benchmark|test)\w*\b",
    re.IGNORECASE,
)
_PRIVATE = re.compile(
    r"\b(?:personal|private|relationship|health|medical|finance|bank|tax|"
    r"identity|remember|memory|email|mail|calendar|telegram|signal|password|"
    r"credential|secret|token|api[ _-]?key|home address)\b",
    re.IGNORECASE,
)
_OPT_OUT = re.compile(
    r"\b(?:do not|don't|dont|must not|never)\s+delegat|\bkeep (?:it|this) local\b",
    re.IGNORECASE,
)
_LOCAL_PERUSAL_TOOLS = {
    "terminal", "read_file", "search_files", "write_file", "patch",
    "apply_patch", "browser", "web_search",
}
_NATIVE_COMMAND = re.compile(r"(?:^|[;&|]\s*)(?:opencode\s+run|codex\s+exec)\b")


NATIVE_DELEGATE_SCHEMA = {
    "name": "native_delegate",
    "description": (
        "Delegate a clean non-personal programming, repository, research, or "
        "workstation task to a native subscription coding agent. Use this as "
        "the FIRST tool for broad technical perusal instead of reading/searching "
        "the tree locally. Never include personal memories, communications, "
        "credentials, secrets, or unrelated conversation history. Use "
        "opencode_easy for bounded work, opencode_complex for multi-file or "
        "reasoning-heavy work, and codex for coding/review work where Codex is "
        "requested or the better fit. An OpenCode billing failure falls back to "
        "native Codex inside the same call. Wait for the result, verify its evidence, "
        "then finish the user's task. Hindsight is unavailable to these workers."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "worker": {
                "type": "string",
                "enum": ["opencode_easy", "opencode_complex", "codex"],
            },
            "task": {
                "type": "string",
                "description": "Fresh minimal technical brief with no personal context or secrets.",
            },
            "cwd": {
                "type": "string",
                "description": "Absolute existing working directory that bounds the worker's task.",
            },
            "write_access": {
                "type": "boolean",
                "description": "Allow changes in cwd. False is the default for reviews and investigations.",
                "default": False,
            },
        },
        "required": ["worker", "task", "cwd"],
    },
}


def _state_db() -> Path:
    return Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes"))) / "state.db"


def _first_user_prompt(session_id: str) -> str:
    if not session_id:
        return ""
    try:
        with sqlite3.connect(f"file:{_state_db()}?mode=ro", uri=True, timeout=1) as db:
            row = db.execute(
                "SELECT content FROM messages "
                "WHERE session_id = ? AND role = 'user' AND active = 1 "
                "ORDER BY id LIMIT 1",
                (session_id,),
            ).fetchone()
    except (OSError, sqlite3.Error):
        return ""
    return str(row[0] or "") if row else ""


def _already_attempted(session_id: str) -> bool:
    if not session_id:
        return False
    try:
        with sqlite3.connect(f"file:{_state_db()}?mode=ro", uri=True, timeout=1) as db:
            row = db.execute(
                "SELECT 1 FROM messages WHERE session_id = ? AND "
                "(tool_name = 'native_delegate' OR tool_calls LIKE '%opencode run%' "
                "OR tool_calls LIKE '%codex exec%') LIMIT 1",
                (session_id,),
            ).fetchone()
    except (OSError, sqlite3.Error):
        return False
    return row is not None


def _needs_native_delegation(prompt: str) -> bool:
    normalized = re.sub(r"\bnon[ -]?personal\b", "", prompt, flags=re.IGNORECASE)
    if _OPT_OUT.search(normalized) or _PRIVATE.search(normalized):
        return False
    return bool(_TECHNICAL.search(normalized) and _BROAD_ACTION.search(normalized))


def _is_native_terminal_call(args: Any) -> bool:
    if not isinstance(args, dict):
        return False
    return bool(_NATIVE_COMMAND.search(str(args.get("command") or "").strip()))


def _on_pre_tool_call(
    *, tool_name: str = "", args: Any = None, session_id: str = "", **_: Any
) -> dict[str, str] | None:
    if tool_name == "native_delegate" or _already_attempted(session_id):
        return None
    if tool_name == "terminal" and _is_native_terminal_call(args):
        return None
    if tool_name not in _LOCAL_PERUSAL_TOOLS:
        return None
    if not _needs_native_delegation(_first_user_prompt(session_id)):
        return None
    return {
        "action": "block",
        "message": (
            "Delegation policy: this is broad, non-personal technical work. "
            "Your first meaningful action must be native_delegate with a fresh "
            "minimal brief and narrow cwd. Do not inspect the tree locally first. "
            "If the tool is deferred, call tool_describe for native_delegate, then "
            "tool_call with top-level name='native_delegate' and arguments={worker,task,cwd,write_access}."
        ),
    }


def _scrubbed_environment() -> dict[str, str]:
    keep_exact = {
        "HOME", "USER", "LOGNAME", "PATH", "SHELL", "TERM", "COLORTERM",
        "LANG", "SSH_AUTH_SOCK", "CODEX_HOME",
    }
    keep_prefixes = ("LC_", "XDG_", "OPENCODE_")
    denied_fragments = ("KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL", "AUTH")
    clean: dict[str, str] = {}
    for name, value in os.environ.items():
        if any(fragment in name.upper() for fragment in denied_fragments):
            continue
        if name in keep_exact or name.startswith(keep_prefixes):
            clean[name] = value
    clean["NO_COLOR"] = "1"
    return clean


def _handle_native_delegate(args: dict[str, Any], **_: Any) -> str:
    worker = str(args.get("worker") or "").strip()
    task = str(args.get("task") or "").strip()
    cwd = Path(str(args.get("cwd") or "")).expanduser().resolve()
    write_access = bool(args.get("write_access", False))

    if worker not in {"opencode_easy", "opencode_complex", "codex"}:
        return tool_error("worker must be opencode_easy, opencode_complex, or codex")
    if not task:
        return tool_error("task is required")
    if not cwd.is_dir():
        return tool_error(f"cwd is not an existing directory: {cwd}")
    if _PRIVATE.search(re.sub(r"\bnon[ -]?personal\b", "", task, flags=re.IGNORECASE)):
        return tool_error("delegation brief appears to contain private context; keep this task local")

    if worker.startswith("opencode_"):
        model = (
            "opencode-go/deepseek-v4-flash"
            if worker == "opencode_easy"
            else "opencode-go/glm-5.3"
        )
        command = [
            "opencode", "run", "--model", model, "--dir", str(cwd),
            "--format", "default",
        ]
        if write_access:
            command.append("--auto")
        command.append(task)
    else:
        command = [
            "codex", "exec", "--ephemeral", "-c", "features.memories=false",
            "-c", "mcp_servers.litellm.enabled=false", "--sandbox",
            "workspace-write" if write_access else "read-only", "-C", str(cwd), task,
        ]

    actual_worker = worker
    try:
        completed = subprocess.run(
            command, cwd=cwd, env=_scrubbed_environment(), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800, check=False,
        )
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or "")[-12000:] if isinstance(exc.stdout, str) else ""
        return tool_error(f"{worker} timed out after 30 minutes\n{output}")
    except OSError as exc:
        return tool_error(f"could not start {worker}: {exc}")

    # OpenCode Go occasionally leaves its catalog visible while the workspace
    # balance is exhausted. Do not spend two more local Qwen turns rediscovering
    # that fact and manually retrying: use the already-authorized native Codex
    # subscription as the availability fallback within this same delegation.
    if (
        completed.returncode != 0
        and worker.startswith("opencode_")
        and "insufficient balance" in completed.stdout.lower()
    ):
        actual_worker = "codex"
        command = [
            "codex", "exec", "--ephemeral", "-c", "features.memories=false",
            "-c", "mcp_servers.litellm.enabled=false", "--sandbox",
            "workspace-write" if write_access else "read-only", "-C", str(cwd), task,
        ]
        try:
            completed = subprocess.run(
                command, cwd=cwd, env=_scrubbed_environment(), text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                timeout=1800, check=False,
            )
        except subprocess.TimeoutExpired as exc:
            output = (exc.stdout or "")[-12000:] if isinstance(exc.stdout, str) else ""
            return tool_error(f"OpenCode billing fallback to Codex timed out\n{output}")
        except OSError as exc:
            return tool_error(f"OpenCode billing fallback could not start Codex: {exc}")

    output = completed.stdout[-80000:]
    payload = {
        "worker_requested": worker, "worker_used": actual_worker,
        "exit_code": completed.returncode,
        "cwd": str(cwd), "output": output,
    }
    return tool_result(payload) if completed.returncode == 0 else tool_error(str(payload))


def register(ctx) -> None:
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
    ctx.register_tool(
        name="native_delegate", toolset="native_delegation",
        schema=NATIVE_DELEGATE_SCHEMA, handler=_handle_native_delegate, emoji="🧭",
    )
