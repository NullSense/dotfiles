#!/usr/bin/env bash
# Hypridle wake sequence — used by both the 4-min idle on-resume and the
# after_sleep_cmd path.
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

# DPMS on only the OLED (DP-1); DP-2 was never parked (see suspend script) so it
# needs no wake — and DPMS-cycling the rotated DP-2 is what kicked the race.
hyprctl dispatch dpms on DP-1 >/dev/null 2>&1
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
