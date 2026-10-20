#!/usr/bin/env bash
# Hypridle 4-min idle: per-monitor power down.
#
#   OLED (AORUS FO32U2):  DDC D6=04 (hardware off — required for burn-in).
#   MSI  (MAG274QRF-QD):  DDC brightness=0 — D6=04 is silently rejected by this
#                         panel (DDCRC_VERIFY on write; getvcp D6 then *lies*
#                         and reports 01 even though panel state diverges).
#                         Brightness=0 is the well-tested write path that
#                         actually extinguishes the backlight here.
# Manual stay-off: hypridle-suspend.sh --hold. Automatic resume stays blocked
# until hypridle-resume.sh --force.
#
# Display numbers are detected by EDID model (positional `--display 1 2`
# breaks silently when the kernel renumbers ddcutil's bus order).

set -u

case "${1:-}" in
    ''|--hold) ;;
    *) printf 'Usage: %s [--hold]\n' "$0" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2

# Serialize with resume, including any wake already in flight. Keep the hold in
# the user's runtime directory; ordinary idle-off never clears it.
power_runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
exec 9>"$power_runtime/aorus-power.lock"
flock -x 9 || exit 1
if [ "${1:-}" = --hold ]; then
    printf '1\n' > "$power_runtime/aorus-power-hold" || exit 1
fi

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

# MSI (DP-2): DELIBERATELY LEFT ALONE on idle. 2026-07-02 — the rotated DP-2
# (transform=1) hits aquamarine#240's page-flip race on the wake path: the
# backlight-0 + DPMS-off deep-sleep, then DP link re-train on resume, kicks a
# self-feeding modeset->card1-uevent loop that mass-crashes GUI clients. DP-2 is
# an IPS LCD (no burn-in risk) and its DDC controller half-sleeps/lies anyway,
# so powering it down here was both useless AND the trigger. It stays lit
# (dimmed via the 2/3-min DDC tiers, which tested safe) until fixed upstream.
# See ~/.claude memory reference_dp2_10bit_wayland_crash.
: "${msi_num:=}"  # (was: ddcutil --display "$msi_num" setvcp 10 0)

wait
# NO `dpms off` here (2026-10-15). The OLED is already hardware-off via DDC D6=04 above, and a
# DPMS cycle is what killed Hyprland: the wake-side modeset ("Modesetting DP-1") derefs a null
# plane buffer in libaquamarine 0.15.1 (SEGV -> uwsm SIGHUP -> SDDM start-limit; see
# aquamarine#434, omarchy#15440). Skipping DPMS removes that disable/modeset round trip
# entirely; the compositor keeps scanning out to a panel that is dark.
