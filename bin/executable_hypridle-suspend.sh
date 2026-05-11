#!/usr/bin/env bash
# Hypridle 4-min idle: per-monitor power down.
#
#   OLED (AORUS FO32U2):  DDC D6=04 (hardware off — required for burn-in).
#   MSI  (MAG274QRF-QD):  DDC brightness=0 — D6=04 is silently rejected by this
#                         panel (DDCRC_VERIFY on write; getvcp D6 then *lies*
#                         and reports 01 even though panel state diverges).
#                         Brightness=0 is the well-tested write path that
#                         actually extinguishes the backlight here.
#   Plus DPMS off so any future third monitor parks too.
#
# Display numbers are detected by EDID model (positional `--display 1 2`
# breaks silently when the kernel renumbers ddcutil's bus order).

set -u

oled_num=""
msi_num=""
cur=""
while IFS= read -r line; do
    case "$line" in
        Display\ *)
            cur="${line#Display }"; cur="${cur%% *}"
            ;;
        *Model:*)
            case "${line#*Model:}" in
                *FO32U2*) oled_num="$cur" ;;
                *MAG274*) msi_num="$cur" ;;
            esac
            ;;
    esac
done < <(ddcutil detect 2>/dev/null)

# OLED: hardware power-off via DDC. Verify ON — we want to see if this ever
# starts failing the way MSI does.
[ -n "$oled_num" ] && \
    ddcutil --display "$oled_num" --sleep-multiplier 0.5 setvcp d6 04 \
        >/dev/null 2>&1 &

# MSI: brightness to 0 via DDC. --noverify because the brightness-ctl path
# already proved this works without a verify step on this panel.
[ -n "$msi_num" ] && \
    ddcutil --display "$msi_num" --noverify --sleep-multiplier 0.5 setvcp 10 0 \
        >/dev/null 2>&1 &

wait
hyprctl dispatch dpms off >/dev/null 2>&1
