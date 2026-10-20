#!/usr/bin/env bash
# Recurring regression: bash ~/.dotfiles/tests/hypridle-power-hold-test.sh
# Exercise the real idle callbacks without touching a physical display.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch_root="${XDG_CACHE_HOME:-$HOME/.cache}/agent-tmp"
mkdir -p "$scratch_root"
scratch=$(mktemp -d "$scratch_root/hypridle-power-test.XXXXXX")
trap 'agent-clean path "$scratch" >/dev/null' EXIT
mkdir -p "$scratch/home/bin" "$scratch/runtime" "$scratch/bin"
export FAKE_POWER_LOG="$scratch/commands"
export XDG_RUNTIME_DIR="$scratch/runtime"
: > "$FAKE_POWER_LOG"

cat > "$scratch/bin/ddcutil" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = detect ]; then
    printf 'Display 1\n   Model: AORUS FO32U2\n'
else
    printf 'ddcutil %s\n' "$*" >> "$FAKE_POWER_LOG"
fi
STUB
cat > "$scratch/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$FAKE_POWER_LOG"
exit "${FAKE_WAKE_FAILURE:-0}"
STUB
cat > "$scratch/home/bin/hypr-dispatch" <<'STUB'
#!/usr/bin/env bash
printf 'dispatch %s\n' "$*" >> "$FAKE_POWER_LOG"
STUB
cat > "$scratch/home/bin/brightness-ctl" <<'STUB'
#!/usr/bin/env bash
printf 'brightness %s\n' "$*" >> "$FAKE_POWER_LOG"
STUB
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/sleep"
chmod +x "$scratch/bin/"* "$scratch/home/bin/"*

run_callback() {
    HOME="$scratch/home" PATH="$scratch/bin:$PATH" \
        bash "$ROOT/home/bin/hypridle-$1.sh" "${@:2}"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Activity and after-sleep callbacks must be inert while manually held off.
printf '1\n' > "$XDG_RUNTIME_DIR/aorus-power-hold"
run_callback resume
[ ! -s "$FAKE_POWER_LOG" ] || fail 'automatic resume woke a manually held display'

# Repeated manual power-off is idempotent and sets the hold before returning.
printf '0\n' > "$XDG_RUNTIME_DIR/aorus-power-hold"
run_callback suspend --hold
[ "$(cat "$XDG_RUNTIME_DIR/aorus-power-hold")" = 1 ] || fail 'manual off did not persist hold'
grep -q 'setvcp d6 04' "$FAKE_POWER_LOG" || fail 'manual off did not power down OLED'
: > "$FAKE_POWER_LOG"
run_callback resume
[ ! -s "$FAKE_POWER_LOG" ] || fail 'idle activity cleared manual hold'
run_callback suspend
[ "$(cat "$XDG_RUNTIME_DIR/aorus-power-hold")" = 1 ] || fail 'idle off cleared manual hold'

# Deliberate wake clears the hold; ordinary automatic wake works again after it.
: > "$FAKE_POWER_LOG"
run_callback resume --force
[ "$(cat "$XDG_RUNTIME_DIR/aorus-power-hold")" = 0 ] || fail 'explicit wake did not clear hold'
grep -qx 'dispatch dpms on DP-1' "$FAKE_POWER_LOG" || fail 'explicit wake missed DPMS'
grep -q 'setvcp d6 01' "$FAKE_POWER_LOG" || fail 'explicit wake missed OLED power-on'
grep -qx 'brightness resync' "$FAKE_POWER_LOG" || fail 'explicit wake missed brightness restore'
: > "$FAKE_POWER_LOG"
run_callback resume
grep -q 'setvcp d6 01' "$FAKE_POWER_LOG" || fail 'ordinary wake stayed disabled after explicit wake'

# Ordinary off arms hardware wake before DDC; failure leaves the display on.
: > "$FAKE_POWER_LOG"
run_callback suspend
[ "$(head -n 1 "$FAKE_POWER_LOG")" = 'systemctl --user start aorus-input-wake.service' ] \
    || fail 'physical wake was not armed before power-off'
grep -q 'setvcp d6 04' "$FAKE_POWER_LOG" || fail 'ordinary idle missed OLED power-off'
: > "$FAKE_POWER_LOG"
export FAKE_WAKE_FAILURE=1
if run_callback suspend; then fail 'failed wake watcher did not abort idle-off'; fi
if grep -q 'setvcp d6 04' "$FAKE_POWER_LOG"; then fail 'powered off without a working wake watcher'; fi

printf 'PASS: manual hold, physical wake readiness, and startup failure fallback\n'
