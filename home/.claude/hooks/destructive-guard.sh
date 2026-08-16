#!/usr/bin/env bash
# RETIRED 2026-05-22. Superseded by dcg (Destructive Command Guard,
# https://github.com/Dicklesworthstone/destructive_command_guard).
#
# Wired into ~/.claude/settings.json as PreToolUse hook `dcg`. This script
# is no-op and only kept on disk so a stale settings.json reference still
# returns exit 0 (allow) rather than failing.
#
# To inspect retired contents:
#   git -C ~/.local/share/chezmoi log -p -- dot_claude/hooks/executable_destructive-guard.sh
#
# dcg covers everything this script did plus DBs, k8s, docker, cloud,
# terraform, supply-chain, AST-level interpreter escape detection. Per-rule
# allowlist via `dcg allow <rule-id>` (~/.config/dcg/allowlist.toml).
exit 0
