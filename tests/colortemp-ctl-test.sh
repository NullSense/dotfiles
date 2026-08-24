#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CTL="$ROOT/home/bin/colortemp-ctl"
AUTOSTART="$ROOT/home/.config/hypr/autostart.conf"
WAYBAR="$ROOT/home/.config/waybar/config.jsonc"
SERVICE="$ROOT/home/.config/systemd/user/colortemp.service"
TIMER="$ROOT/home/.config/systemd/user/colortemp.timer"
HYPRSUNSET_OVERRIDE="$ROOT/home/.config/systemd/user/hyprsunset.service.d/override.conf"
HYPRSUNSET_LINK="$ROOT/home/.config/systemd/user/graphical-session.target.wants/hyprsunset.service"
TIMER_LINK="$ROOT/home/.config/systemd/user/graphical-session.target.wants/colortemp.timer"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

cat >"$TMP/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/commands"
EOF

cat >"$TMP/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/signals"
EOF

chmod +x "$TMP/hyprctl" "$TMP/systemctl"
mkdir -p "$TMP/state/runtime"
: >"$TMP/state/commands"
: >"$TMP/state/signals"

export COLORTEMP_HYPRCTL="$TMP/hyprctl"
export COLORTEMP_HOUR=12
export COLORTEMP_STATE_DIR="$TMP/state/runtime"
export COLORTEMP_TEST_STATE="$TMP/state"
export PATH="$TMP:$PATH"

assert_eq() {
    local expected=$1 actual=$2 label=$3
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

command_count() {
    wc -l <"$TMP/state/commands"
}

assert_eq 6500K "$($CTL get)" "missing state follows daytime schedule"

$CTL warmer
assert_eq 6400K "$($CTL get)" "scrolling down changes temperature by 100K"
assert_eq 1 "$(command_count)" "one transition uses one compositor IPC call"
assert_eq 'hyprsunset temperature 6400' "$(tail -n 1 "$TMP/state/commands")" \
    "warm adjustment uses hyprsunset CTM"

$CTL cooler
assert_eq 6500K "$($CTL get)" "scrolling up returns to neutral"
assert_eq 'hyprsunset identity' "$(tail -n 1 "$TMP/state/commands")" \
    "6500K default uses an exact identity matrix"

$CTL cooler
assert_eq 6500K "$($CTL get)" "6500K is the neutral ceiling"
assert_eq 2 "$(command_count)" "scrolling beyond neutral performs no IPC call"

printf '2500\n' >"$TMP/state/runtime/kelvin"
$CTL warmer
assert_eq 2500K "$($CTL get)" "2500K is the warm floor"
assert_eq 2 "$(command_count)" "scrolling below the floor performs no IPC call"

$CTL night
assert_eq 4000K "$($CTL get)" "night preset is 4000K"

$CTL default
assert_eq 6500K "$($CTL get)" "default restores neutral identity"

COLORTEMP_HOUR=5 $CTL auto
assert_eq 4000K "$($CTL get)" "automatic schedule selects night before 06:00"
COLORTEMP_HOUR=6 $CTL auto
assert_eq 6500K "$($CTL get)" "automatic schedule selects identity at 06:00"
COLORTEMP_HOUR=19 $CTL auto
assert_eq 4000K "$($CTL get)" "automatic schedule selects night at 19:00"

assert_eq "$(command_count)" "$(wc -l <"$TMP/state/signals")" \
    "every applied CTM update signals Waybar exactly once"

# The Waybar commands intentionally contain a literal $HOME for runtime.
# shellcheck disable=SC2016
grep -Fq 'on-scroll-up": "$HOME/bin/colortemp-ctl cooler"' "$WAYBAR"
# shellcheck disable=SC2016
grep -Fq 'on-scroll-down": "$HOME/bin/colortemp-ctl warmer"' "$WAYBAR"
# shellcheck disable=SC2016
grep -Fq 'on-click": "$HOME/bin/colortemp-ctl default"' "$WAYBAR"
grep -Fq '100K' "$WAYBAR"
grep -Fq 'native gamut' "$WAYBAR"
grep -Fq 'Hyprland CTM' "$WAYBAR"
grep -Fq 'Requires=hyprsunset.service' "$SERVICE"
grep -Fq 'After=hyprsunset.service' "$SERVICE"
grep -Fq 'ExecStart=%h/bin/colortemp-ctl auto' "$SERVICE"
grep -Fq 'ExecStart=/usr/bin/hyprsunset --identity' "$HYPRSUNSET_OVERRIDE"
grep -Fq 'ExecStartPost=%h/bin/colortemp-ctl auto' "$HYPRSUNSET_OVERRIDE"
grep -Fq 'OnCalendar=*-*-* 06,19:00:00' "$TIMER"
assert_eq /usr/lib/systemd/user/hyprsunset.service "$(readlink "$HYPRSUNSET_LINK")" \
    "graphical session starts the CTM owner"
assert_eq ../colortemp.timer "$(readlink "$TIMER_LINK")" \
    "graphical session enables the day/night schedule"

if grep -Eq '^exec-once.*hyprsunset' "$AUTOSTART"; then
    fail "hyprsunset must have exactly one systemd-owned daemon"
fi
if grep -Eqi 'gbmonctl|ddcutil|colour-mode|rgb-(red|green|blue)|kelvin_to_rgb' "$CTL"; then
    fail "runtime temperature control must not mutate monitor hardware settings"
fi

printf 'PASS: colortemp-ctl\n'
