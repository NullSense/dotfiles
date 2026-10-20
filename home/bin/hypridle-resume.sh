#!/usr/bin/env bash
# Hypridle wake sequence — used by both the 4-min idle on-resume and the
# after_sleep_cmd path.
# Manual stay-off is respected by both callers. Pass --force to deliberately
# clear a hold set by hypridle-suspend.sh --hold and turn the OLED back on.
#
# Order matters:
#   1. DPMS on FIRST. This re-trains the DP link / brings the AUX channel up
#      so DDC has a path to the panel. The previous design sent DDC bytes
#      while the link was down, which silently dropped them on DP-2.
#   2. OLED: DDC D6=01 to bring the panel out of hardware power-off. Retried
#      up to 3× because the OLED's DDC controller may need a brief moment
#      after DPMS-on before it answers.
#   3. brightness-ctl resync — re-pushes the current $XDG_RUNTIME_DIR/brightness
#      value to every monitor. Restores the MSI from brightness=0 back to
#      whatever the lock/pre-dim tier last set, in one place, no per-tier
#      special-casing here.

set -u

case "${1:-}" in
    ''|--force) ;;
    *) printf 'Usage: %s [--force]\n' "$0" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2

power_runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
exec 9>"$power_runtime/aorus-power.lock"
flock -x 9 || exit 1
if [ "${1:-}" = --force ]; then
    printf '0\n' > "$power_runtime/aorus-power-hold" || exit 1
elif [ "$(cat "$power_runtime/aorus-power-hold" 2>/dev/null)" = 1 ]; then
    exit 0
fi

# DPMS on only the OLED (DP-1); DP-2 was never parked (see suspend script) so it
# needs no wake — and DPMS-cycling the rotated DP-2 is what kicked the race.
# hypr-dispatch picks the right call for the active config manager (hyprlang or Lua);
# the raw hyprctl form is a last-resort fallback so a missing helper can never leave DP-1 dark.
"$HOME/bin/hypr-dispatch" dpms on DP-1 >/dev/null 2>&1 \
    || hyprctl dispatch dpms on DP-1 >/dev/null 2>&1
sleep 0.5   # DP link train + AUX settle before DDC travels over it

oled_num=""
cur=""
while IFS= read -r line; do
    case "$line" in
        Display\ *)
            cur="${line#Display }"; cur="${cur%% *}"
            ;;
        *Model:*)
            case "${line#*Model:}" in
                *FO32U2*) oled_num="$cur" ;;
            esac
            ;;
    esac
done < <(ddcutil detect 2>/dev/null)

if [ -n "$oled_num" ]; then
    for _ in 1 2 3; do
        ddcutil --display "$oled_num" --sleep-multiplier 1.0 setvcp d6 01 \
            >/dev/null 2>&1 && break
        sleep 0.5
    done
fi

# Re-sync brightness state to every monitor. Idempotent on OLED, restores MSI
# from 0 back to the current state-file value (e.g. lock-dim 10, then unlock_cmd
# bumps it back to pre-lock).
~/bin/brightness-ctl resync >/dev/null 2>&1 || true
