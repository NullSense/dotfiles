#!/bin/bash
# Test harness for home/.claude/statusline.sh (the Claude Code status line).
# Feeds mock JSON payloads and checks the rendered output. Hermetic: no real
# project checkouts or ~/.claude cache writes.
SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/home/.claude/statusline.sh"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local json="$2"
    local expect_pattern="$3"  # regex to match in raw output (with escape codes stripped)

    RAW=$(echo "$json" | bash "$SCRIPT" 2>/dev/null)
    # Strip ANSI colors AND OSC 8 hyperlink sequences
    STRIPPED=$(echo "$RAW" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\]8;;[^\x1b]*\x1b\\//g')

    if echo "$STRIPPED" | grep -qP "$expect_pattern"; then
        printf "  \033[32mPASS\033[0m  %s\n" "$name"
        PASS=$((PASS + 1))
    else
        printf "  \033[31mFAIL\033[0m  %s\n" "$name"
        printf "        expected pattern: %s\n" "$expect_pattern"
        printf "        got (stripped):   %s\n" "$STRIPPED"
        FAIL=$((FAIL + 1))
    fi
    # Show rendered output
    printf "        rendered: %s\n\n" "$RAW"
}

echo ""
echo "━━━ Claude Code Statusline Tests ━━━"
echo ""

# ── Test 1: Full payload, low context usage ──────────────────────────────────
run_test "Full payload (low context)" '{
  "model":{"id":"claude-opus-4-5","display_name":"Opus 4.5"},
  "workspace":{"current_dir":"/home/nullsense/Programming/panopticon","project_dir":"/home/nullsense/Programming/panopticon"},
  "version":"1.0.90",
  "cost":{"total_cost_usd":0.0523,"total_lines_added":42,"total_lines_removed":7},
  "context_window":{"total_input_tokens":15000,"total_output_tokens":3000,"context_window_size":200000,"used_percentage":12.3,"remaining_percentage":87.7}
}' 'Opus 4\.5.*panopticon.*12%.*\$0\.05.*\+42.*-7'

# ── Test 2: High context usage (yellow zone) ────────────────────────────────
run_test "High context (yellow 50-75%)" '{
  "model":{"id":"claude-sonnet","display_name":"Sonnet 4"},
  "workspace":{"current_dir":"/home/user/myproject","project_dir":"/home/user/myproject"},
  "version":"1.0.85",
  "cost":{"total_cost_usd":1.2345,"total_lines_added":200,"total_lines_removed":50},
  "context_window":{"used_percentage":62.8}
}' 'Sonnet 4.*myproject.*62%.*\$1\.23.*\+200.*-50'

# ── Test 3: Critical context usage (red zone) ───────────────────────────────
run_test "Critical context (red 75%+)" '{
  "model":{"id":"claude-opus","display_name":"Opus 4"},
  "workspace":{"current_dir":"/tmp/test","project_dir":"/tmp/test"},
  "version":"2.0.0",
  "cost":{"total_cost_usd":5.00,"total_lines_added":0,"total_lines_removed":0},
  "context_window":{"used_percentage":89.1}
}' 'Opus 4.*test.*89%.*\$5\.00'

# ── Test 4: No lines changed (should omit +/- section) ──────────────────────
run_test "No lines changed (clean)" '{
  "model":{"id":"claude-haiku","display_name":"Haiku 3.5"},
  "workspace":{"current_dir":"/home/user/clean","project_dir":"/home/user/clean"},
  "version":"1.0.90",
  "cost":{"total_cost_usd":0.001,"total_lines_added":0,"total_lines_removed":0},
  "context_window":{"used_percentage":5.0}
}' 'Haiku 3\.5.*clean.*5%.*\$0\.00'

# ── Test 5: Missing/null fields (graceful degradation) ──────────────────────
run_test "Minimal payload (missing fields)" '{
  "model":{"display_name":"Opus 4.5"},
  "workspace":{"current_dir":"/home/user/proj"},
  "context_window":{}
}' 'Opus 4\.5.*proj.*0%'

# ── Test 6: git branch shown for a repository workspace ─────────────────────
GIT_TMP=$(mktemp -d)
trap 'rm -rf -- "$GIT_TMP"' EXIT
git -C "$GIT_TMP" init -q -b feat/statusline-test
run_test "Git workspace shows branch" '{
  "model":{"display_name":"Opus 4.5"},
  "workspace":{"current_dir":"'"$GIT_TMP"'","project_dir":"'"$GIT_TMP"'"},
  "version":"1.0.90",
  "cost":{"total_cost_usd":0.33,"total_lines_added":15,"total_lines_removed":3},
  "context_window":{"used_percentage":40.0}
}' 'Opus 4\.5.*feat/statusline-test.*40%.*\$0\.33'

# ── Summary ──────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    printf "\033[32m  All %d tests passed\033[0m\n" "$TOTAL"
else
    printf "\033[31m  %d/%d failed\033[0m\n" "$FAIL" "$TOTAL"
fi
echo ""
[ "$FAIL" -eq 0 ]
