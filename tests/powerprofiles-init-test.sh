#!/usr/bin/env bash
set -euo pipefail

# Recurring caller: Omarchy's default hypr autostart runs `omarchy-powerprofiles-init`
# at every login. Upstream picks `performance` whenever no laptop battery is found,
# which pins every core at ~5.5 GHz on this desktop. Our shadow in ~/.local/bin must
# select `balanced` (amd-pstate-epp powersave + balance_performance) instead.

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo/home/.local/bin/omarchy-powerprofiles-init"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$script" ]] || fail "shadow $script missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
cat >"$tmp/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PPD_LOG"
EOF
chmod +x "$tmp/powerprofilesctl"

PPD_LOG="$tmp/log" PATH="$tmp:$PATH" "$script"

grep -qx 'set balanced' "$tmp/log" || fail "expected 'set balanced', got: $(cat "$tmp/log")"
if grep -q 'performance' "$tmp/log"; then
    fail 'shadow still selects performance'
fi

printf 'PASS: omarchy-powerprofiles-init shadow selects balanced\n'
