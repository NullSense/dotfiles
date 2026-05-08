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
set -u

err_file=$(mktemp -t aiquota-wrap-err.XXXXXX)
trap 'rm -f "$err_file"' EXIT

if out=$(agent-vault vault run --vault default -- \
        "$HOME/code/aiquota/target/release/aiquota" waybar 2>"$err_file"); then
    printf '%s\n' "$out"
    exit 0
fi

# agent-vault failed (session expired, daemon down, etc.) — render an auth
# pill so the bar stays visible and clickable. The "unauth" class lets you
# style it in waybar's CSS (e.g. red text). Tooltip explains the fix.
err_summary=$(head -1 "$err_file" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"text":" auth","alt":"unauth","class":"unauth","tooltip":"Agent Vault session invalid or expired.\\n\\nFix:  agent-vault auth login\\n\\nLast error: %s"}\n' "$err_summary"
exit 0
