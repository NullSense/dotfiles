#!/usr/bin/env bash
# Claude Code PreToolUse hook — denies access to known secret-bearing
# commands and paths. Defense in depth on top of ~/bin/agent-isolated;
# catches the case where an agent runs without the bwrap wrapper
# (`command claude` or `AGENT_UNSANDBOX=1`).
#
# Originally only covered Bash, which left a gap: the Read/Edit/Write tools
# bypassed the hook entirely, so a prompt-injected agent could enumerate
# bind-mounted public files (gitconfig, zshrc) or — outside the sandbox —
# read genuine secrets directly. Now covers Bash + Read/Edit/Write/
# NotebookEdit/Glob/Grep via dual matchers in ~/.claude/settings.json.
#
# Protocol: stdin is a JSON event from Claude Code. Per tool, we inspect
# the appropriate tool_input field and pattern-match. On match: emit a
# permissionDecision of "deny" with a reason. On no match: exit silently.
#
# Logs every decision to $XDG_RUNTIME_DIR/deny-secrets.log for debugging.

set -euo pipefail
LOG="${XDG_RUNTIME_DIR:-/tmp}/deny-secrets.log"

event="$(cat)"
tool="$(printf '%s' "$event" | jq -r '.tool_name // ""' 2>/dev/null || echo)"

# ── Path patterns: shared by Bash `cat <path>` and read-tool file_path. ──
# Match anywhere in the path; secret_path_patterns is used for both. The
# bwrap sandbox already masks these via tmpfs, so a hit here usually means
# the agent is running with AGENT_UNSANDBOX=1 or via `command claude` —
# i.e. the user deliberately exposed the surface, and we want a second gate.
secret_path_patterns=(
    '(^|/)\.ssh($|/)'
    '(^|/)\.gnupg($|/)'
    '(^|/)\.aws($|/)'
    '(^|/)\.kube($|/)'
    '(^|/)\.docker/(config\.json|credentials)'
    '(^|/)\.config/rbw($|/)'
    '(^|/)\.config/Bitwarden($|/)'
    '(^|/)\.local/share/keyrings($|/)'
    '(^|/)\.cache/cliphist($|/)'
    '(^|/)\.password-store($|/)'
    '(^|/)\.netrc$'
    '(^|/)\.git-credentials$'
    '(^|/)\.bitwarden-ssh-agent\.sock$'
    '\.local/share/chezmoi/SECRETS\.md$'
    '\.local/share/chezmoi/private_'
    '\.local/share/chezmoi/\.git($|/)'
    '\.(env|envrc|key|pem|p12|pfx|jks|kdbx|asc)$'
)

deny() {
    local reason="$1"
    printf '[%s] DENY [%s]: %s\n' "$(date -Iseconds)" "$tool" "${reason:0:200}" >> "$LOG"
    jq -nc --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'
    exit 0
}

check_path() {
    local path="$1" pat
    [[ -z "$path" ]] && return 0
    for pat in "${secret_path_patterns[@]}"; do
        if [[ "$path" =~ $pat ]]; then
            deny "deny-secrets hook blocked $tool of a secret-bearing path (\`$path\`). The bwrap sandbox normally masks these paths; if you see this inside an agent something is off. To intentionally access, use AGENT_UNSANDBOX=1 or the appropriate --ssh/--gpg/--rbw escape hatch."
        fi
    done
}

case "$tool" in
    Bash)
        cmd="$(printf '%s' "$event" | jq -r '.tool_input.command // ""' 2>/dev/null || echo)"
        [[ -z "$cmd" ]] && exit 0

        # Secret-extraction commands (run, not just read a file).
        cmd_patterns=(
            '(^|[[:space:];|&])rbw([[:space:]]|$)'
            '(^|[[:space:];|&])bw([[:space:]]|$)'
            '(^|[[:space:];|&])secret-tool([[:space:]]|$)'
            '(^|[[:space:];|&])pass[[:space:]]+(show|otp|edit|cp)'
            '(^|[[:space:];|&])keyctl([[:space:]]|$)'
            'ssh-add[[:space:]]+-L'
            'gpg[[:space:]]+(--export-secret|--export-ownertrust|-K|--list-secret)'
            'op[[:space:]]+(read|item|signin|inject|run)'
            'aws[[:space:]]+configure[[:space:]]+get'
            'doppler[[:space:]]+(run|secrets|me)'
            'vault[[:space:]]+(read|kv|login)'
            'cat[[:space:]]+.*\.(env|envrc|key|pem|p12|pfx|jks|kdbx|asc)([[:space:]]|$)'
            'cat[[:space:]]+.*/(\.ssh|\.gnupg|\.aws|\.kube|\.netrc|\.git-credentials)'
        )
        for pat in "${cmd_patterns[@]}"; do
            if [[ "$cmd" =~ $pat ]]; then
                deny "deny-secrets hook blocked a known secret-extraction command (\`${BASH_REMATCH[0]}\`). If you genuinely need this, run the agent with \`agent-isolated <agent> --rbw\`/\`--ssh\`/\`--gpg\` for the relevant escape hatch, or set AGENT_UNSANDBOX=1 to bypass entirely."
            fi
        done
        printf '[%s] allow [Bash]: %s\n' "$(date -Iseconds)" "${cmd:0:120}" >> "$LOG"
        ;;
    Read|Edit|Write|NotebookEdit)
        check_path "$(printf '%s' "$event" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo)"
        ;;
    Glob|Grep)
        check_path "$(printf '%s' "$event" | jq -r '.tool_input.path // ""' 2>/dev/null || echo)"
        ;;
    *)
        # Unknown tool — allow silently.
        exit 0
        ;;
esac

exit 0
