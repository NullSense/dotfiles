#!/bin/bash
# Combined Claude Code statusline: model, git, context, cost, Vercel deploy status
# Cache dir for Vercel status (avoid hammering API on every 300ms tick)
CACHE_DIR="$HOME/.claude/cache/vercel"
CACHE_TTL=30  # seconds between Vercel API calls

input=$(cat)

# ── Extract session data (individual jq calls avoid tab/IFS issues) ──────────
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
VERSION=$(echo "$input" | jq -r '.version // empty')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // "."')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | floor')
ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

DIR_NAME="${CWD##*/}"

# ── Git branch ───────────────────────────────────────────────────────────────
GIT_SEG=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        if git -C "$CWD" diff-index --quiet HEAD -- 2>/dev/null; then
            GIT_SEG="\033[32m $BRANCH\033[0m"
        else
            GIT_SEG="\033[33m $BRANCH*\033[0m"
        fi
    fi
fi

# ── Context window (color-coded) ────────────────────────────────────────────
USED_INT=${USED_PCT:-0}
if [ "$USED_INT" -ge 75 ] 2>/dev/null; then
    CTX="\033[31m${USED_INT}%\033[0m"
elif [ "$USED_INT" -ge 50 ] 2>/dev/null; then
    CTX="\033[33m${USED_INT}%\033[0m"
else
    CTX="\033[32m${USED_INT}%\033[0m"
fi

# ── Cost ─────────────────────────────────────────────────────────────────────
COST_FMT=$(printf '%.2f' "$COST" 2>/dev/null || echo "0.00")

# ── Lines changed ────────────────────────────────────────────────────────────
LINES=""
if [ "$ADDED" != "0" ] || [ "$REMOVED" != "0" ]; then
    LINES=" \033[32m+${ADDED}\033[0m \033[31m-${REMOVED}\033[0m"
fi

# ── Vercel deploy status (cached) ───────────────────────────────────────────
VERCEL_SEG=""
VERCEL_PROJECT="$CWD/.vercel/project.json"
if [ -f "$VERCEL_PROJECT" ] && command -v vercel >/dev/null 2>&1; then
    PROJECT_ID=$(jq -r '.projectId // empty' "$VERCEL_PROJECT" 2>/dev/null)
    if [ -n "$PROJECT_ID" ]; then
        CACHE_FILE="$CACHE_DIR/${PROJECT_ID}.cache"

        # Refresh cache in background if stale
        CACHE_AGE=999
        if [ -f "$CACHE_FILE" ]; then
            CACHE_MOD=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
            NOW=$(date +%s)
            CACHE_AGE=$(( NOW - CACHE_MOD ))
        fi

        if [ "$CACHE_AGE" -ge "$CACHE_TTL" ]; then
            # Background refresh - don't block the statusline
            (
                RESULT=$(vercel ls --cwd "$CWD" -F json 2>/dev/null | jq -r '
                    .deployments[0] |
                    if . == null then "none||"
                    else "\(.state // "UNKNOWN")|\(.url // "")|\(.meta.githubCommitRef // "")"
                    end
                ' 2>/dev/null)
                [ -n "$RESULT" ] && echo "$RESULT" > "$CACHE_FILE"
            ) &
            disown 2>/dev/null
        fi

        # Read cached status
        if [ -f "$CACHE_FILE" ]; then
            IFS='|' read -r V_STATE V_URL V_BRANCH < "$CACHE_FILE"
            V_LABEL=""
            case "$V_STATE" in
                READY)    V_LABEL="\033[32m▲ Ready\033[0m" ;;
                BUILDING) V_LABEL="\033[33m▲ Building\033[0m" ;;
                QUEUED)   V_LABEL="\033[36m▲ Queued\033[0m" ;;
                ERROR)    V_LABEL="\033[31m▲ Failed\033[0m" ;;
                CANCELED) V_LABEL="\033[90m▲ Canceled\033[0m" ;;
                none)     V_LABEL="\033[90m▲ --\033[0m" ;;
            esac
            if [ -n "$V_LABEL" ]; then
                if [ -n "$V_URL" ]; then
                    # OSC 8 clickable hyperlink: \e]8;;URL\e\\TEXT\e]8;;\e\\
                    VERCEL_SEG=" \033]8;;https://${V_URL}\033\\\\${V_LABEL}\033]8;;\033\\\\\033[0m"
                else
                    VERCEL_SEG=" ${V_LABEL}"
                fi
            fi
        fi
    fi
fi

# ── Assemble ─────────────────────────────────────────────────────────────────
printf "\033[1;35m%s\033[0m \033[1;34m%s\033[0m%b" "$MODEL" "$DIR_NAME" "$GIT_SEG"
printf " \033[90m|\033[0m %b" "$CTX"
printf " \033[90m|\033[0m \033[1m\$%s\033[0m%b" "$COST_FMT" "$LINES"
[ -n "$VERCEL_SEG" ] && printf " \033[90m|\033[0m%b" "$VERCEL_SEG"
[ -n "$VERSION" ] && printf " \033[90m| v%s\033[0m" "$VERSION"
echo
