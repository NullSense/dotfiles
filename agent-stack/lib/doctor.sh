#!/usr/bin/env bash
# Agent-stack health board. Run via `mise run doctor`. Non-zero exit on failure.
set -uo pipefail
pass=0; fail=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
no()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail+1)); }
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1"; fi; }

echo "── Sandbox ──────────────────────────────────────────"
chk "bubblewrap installed"                "command -v bwrap"
chk "unprivileged user namespaces work"   "unshare --user --map-root-user true"
echo "  running agent-isolated --self-test:"
_st="$(mktemp)"
if "$HOME/bin/agent-isolated" --self-test >"$_st" 2>&1; then
    ok "agent-isolated --self-test ($(grep -oE '[0-9]+ passed' "$_st" | head -1))"
else
    no "agent-isolated --self-test FAILED ($(grep -oE '[0-9]+ failed' "$_st" | head -1)) — see $_st"
fi

echo "── Commit signing ───────────────────────────────────"
chk "git-sign-agent.service active"       "systemctl --user is-active git-sign-agent.service"
chk "gpg.ssh.program = wrapper"           "test \"\$(git config --global gpg.ssh.program)\" = \"$HOME/bin/git-sign-ssh\""
_d=$(mktemp -d)
if git -C "$_d" init -q && git -C "$_d" commit --allow-empty -m doctor -q 2>/dev/null \
   && git -C "$_d" log --show-signature -1 2>&1 | grep -q 'Good "git" signature'; then
    ok "signed commit verifies"
else
    no "signed commit does NOT verify"
fi

echo "── Push auth ────────────────────────────────────────"
chk "remotes route over HTTPS (insteadOf)" "git config --global --get-regexp 'url.https://github.com/.insteadof'"
chk "gh authenticated"                     "gh auth status"

echo "── Destructive guard (multi-agent) ──────────────────"
chk "cc-safety-net resolvable"             "command -v cc-safety-net || bunx cc-safety-net --version"
chk "claude hook wired"                    "grep -q cc-safety-net $HOME/.claude/settings.json"
chk "opencode plugin wired"                "grep -q cc-safety-net $HOME/.config/opencode/opencode.jsonc"
grep -q cc-safety-net "$HOME/.codex/hooks.json" 2>/dev/null \
    && ok "codex hook wired" \
    || printf '  \033[33m~\033[0m codex hook NOT wired (TUI: /plugins install + /hooks trust)\n'

echo
printf "── %d passed, %d failed ──\n" "$pass" "$fail"
exit "$fail"
