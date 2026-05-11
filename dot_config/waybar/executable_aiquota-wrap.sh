#!/usr/bin/env bash
# aiquota waybar wrapper.
#
# systemd-spawned waybar doesn't inherit the interactive-shell env, so calls
# to api.anthropic.com / openai.com need agent-vault credentials injected
# explicitly. `agent-vault vault run` is the canonical wrapper — it sets
# HTTPS_PROXY + the MITM CA env for the child only, project-recommended.
#
# When the agent-vault session is invalid/expired, emit a visible "auth
# needed" pill instead of vanishing the module. Always exit 0 so waybar
# keeps re-running this on its interval.
#
# Stream separation matters: agent-vault writes status lines to stderr
# ("routing HTTPS through MITM proxy", "agent-vault connected..."). aiquota
# writes JSON to stdout. We must NOT conflate them or waybar fails parsing.
#
# Tooltip footer (click bindings) is appended here rather than in the binary
# so a single shell change can re-bind keys without rebuilding aiquota.
set -u

AIQUOTA_BIN="${AIQUOTA_BIN:-$HOME/code/aiquota/target/release/aiquota}"

# Hairline + key bindings appended to whatever the binary emits as tooltip.
# `IFS=` is required — without it, `read` strips the two leading newlines
# we depend on to separate the footer from the body. The hairline glyph
# (U+2500) doubles as the idempotency marker checked below.
IFS= read -r -d '' TOOLTIP_FOOTER <<'EOF' || true


────────────
  click          cycle window: auto · 5h · 7d
  right-click    open TUI
EOF

err_file=$(mktemp -t aiquota-wrap-err.XXXXXX)
trap 'rm -f "$err_file"' EXIT

if out=$(agent-vault vault run --vault default -- \
        "$AIQUOTA_BIN" waybar 2>"$err_file"); then
    # Append footer to .tooltip. jq -c keeps it on a single line so waybar's
    # line-oriented parser doesn't choke. If the binary already includes a
    # footer marker we leave it alone (forward-compat with future versions).
    printf '%s' "$out" | jq -c --arg footer "$TOOLTIP_FOOTER" '
        if (.tooltip // "" | contains("────────────")) then .
        else .tooltip = ((.tooltip // "") + $footer)
        end
    ' 2>/dev/null || printf '%s\n' "$out"
    exit 0
fi

# agent-vault failed (session expired, daemon down, etc.) — render an auth
# pill so the bar stays visible and clickable. The "unauth" class lets you
# style it in waybar's CSS (e.g. red text). Tooltip explains the fix.
# jq -Rs handles all JSON escaping (control chars, unicode, backslashes)
# correctly — the previous hand-rolled sed escape missed multiple cases.
err_summary=$(head -c 500 "$err_file" 2>/dev/null || true)
jq -cn \
    --arg err "$err_summary" \
    --arg footer "$TOOLTIP_FOOTER" \
    '{
        text:    " auth",
        alt:     "unauth",
        class:   "unauth",
        tooltip: ("Agent Vault session invalid or expired.\n\nFix:  agent-vault auth login\n\nLast error: " + $err + $footer)
    }'
exit 0
