#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CTL="$ROOT/home/bin/colortemp-ctl"
AUTOSTART="$ROOT/home/.config/hypr/autostart.conf"
WAYBAR="$ROOT/home/.config/waybar/config.jsonc"
SERVICE="$ROOT/home/.config/systemd/user/colortemp.service"
TIMER="$ROOT/home/.config/systemd/user/colortemp.timer"
SERVICE_LINK="$ROOT/home/.config/systemd/user/graphical-session.target.wants/colortemp.service"
TIMER_LINK="$ROOT/home/.config/systemd/user/graphical-session.target.wants/colortemp.timer"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

grep -Fq 'COLORTEMP_GBMONCTL' "$CTL" || fail "hardware USB controller is not implemented"

cat >"$TMP/gbmonctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/commands"
EOF

cat >"$TMP/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/signals"
EOF

chmod +x "$TMP/gbmonctl" "$TMP/pkill"
mkdir -p "$TMP/state/runtime"
: >"$TMP/state/commands"
: >"$TMP/state/signals"

export COLORTEMP_GBMONCTL="$TMP/gbmonctl"
export COLORTEMP_DEVICE_AVAILABLE=1
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

assert_eq 6500K "$($CTL get)" "missing state follows daytime schedule"

$CTL -100
assert_eq 6400K "$($CTL get)" "scrolling down starts at 6500K"

$CTL -5000
assert_eq 2500K "$($CTL get)" "temperature clamps at 2500K"

$CTL +5000
assert_eq 6500K "$($CTL get)" "temperature clamps at neutral 6500K"
assert_eq '-prop colour-mode -val 2' "$(tail -n 1 "$TMP/state/commands")" \
    "6500K uses the calibrated monitor preset"

$CTL night
assert_eq 4000K "$($CTL get)" "night preset is 4000K"
assert_eq $'-prop colour-mode -val 3\n-prop rgb-red -val 100\n-prop rgb-green -val 81\n-prop rgb-blue -val 65' \
    "$(tail -n 4 "$TMP/state/commands")" "4000K hardware RGB mapping"

$CTL toggle
assert_eq 6500K "$($CTL get)" "toggle returns to day"

$CTL toggle
assert_eq 4000K "$($CTL get)" "toggle returns to night"

signal_count=$(wc -l <"$TMP/state/signals")
assert_eq 6 "$signal_count" "every state-changing command signals Waybar"

COLORTEMP_HOUR=5 $CTL auto
assert_eq 4000K "$($CTL get)" "automatic schedule selects night before 06:00"
COLORTEMP_HOUR=6 $CTL auto
assert_eq 6500K "$($CTL get)" "automatic schedule selects day at 06:00"
COLORTEMP_HOUR=19 $CTL auto
assert_eq 4000K "$($CTL get)" "automatic schedule selects night at 19:00"

export COLORTEMP_DEVICE_AVAILABLE=0
assert_eq off "$($CTL get)" "disconnected hardware reports off"

# The Waybar commands intentionally contain a literal $HOME for runtime.
# shellcheck disable=SC2016
grep -Fq 'on-scroll-up": "$HOME/bin/colortemp-ctl +100"' "$WAYBAR"
# shellcheck disable=SC2016
grep -Fq 'on-scroll-down": "$HOME/bin/colortemp-ctl -100"' "$WAYBAR"
grep -Fq 'Gigabyte USB hardware RGB' "$WAYBAR"
grep -Fq 'ExecStart=%h/bin/colortemp-ctl auto' "$SERVICE"
grep -Fq 'OnCalendar=*-*-* 06,19:00:00' "$TIMER"
assert_eq ../colortemp.service "$(readlink "$SERVICE_LINK")" \
    "graphical session applies the current profile"
assert_eq ../colortemp.timer "$(readlink "$TIMER_LINK")" \
    "graphical session enables the daily schedule"

if grep -Fqi 'hyprsunset' "$AUTOSTART" "$WAYBAR"; then
    fail "obsolete hyprsunset integration remains"
fi
[[ ! -e "$ROOT/home/.config/hypr/hyprsunset.conf" ]] || fail "obsolete hyprsunset config remains"
[[ ! -e "$ROOT/home/.config/systemd/user/graphical-session.target.wants/hyprsunset.service" ]] || \
    fail "obsolete hyprsunset service link remains"

printf 'PASS: colortemp-ctl\n'
