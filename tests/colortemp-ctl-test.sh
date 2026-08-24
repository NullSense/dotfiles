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

cat >"$TMP/gbmonctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/commands"
EOF

cat >"$TMP/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/signals"
EOF

cat >"$TMP/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/legacy-signals"
EOF

chmod +x "$TMP/gbmonctl" "$TMP/systemctl" "$TMP/pkill"
mkdir -p "$TMP/state/runtime"
: >"$TMP/state/commands"
: >"$TMP/state/signals"
: >"$TMP/state/legacy-signals"

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

command_count() {
    wc -l <"$TMP/state/commands"
}

assert_eq normal "$($CTL get)" "missing state follows daytime schedule"

$CTL warmer
assert_eq warm "$($CTL get)" "scrolling down selects warm"
assert_eq 1 "$(command_count)" "one transition uses one hardware write"
assert_eq '-prop colour-mode -val 2' "$(tail -n 1 "$TMP/state/commands")" \
    "warm selects the monitor warm preset"

$CTL warmer
assert_eq warm "$($CTL get)" "warm is the hardware floor"
assert_eq 1 "$(command_count)" "scrolling below the floor performs no write"

$CTL cooler
assert_eq normal "$($CTL get)" "scrolling up returns to normal"
assert_eq '-prop colour-mode -val 1' "$(tail -n 1 "$TMP/state/commands")" \
    "normal selects the monitor normal preset"

$CTL cooler
assert_eq cool "$($CTL get)" "second upward scroll selects cool"
assert_eq '-prop colour-mode -val 0' "$(tail -n 1 "$TMP/state/commands")" \
    "cool selects the monitor cool preset"

$CTL cooler
assert_eq cool "$($CTL get)" "cool is the hardware ceiling"
assert_eq 3 "$(command_count)" "scrolling above the ceiling performs no write"

$CTL night
assert_eq warm "$($CTL get)" "night preset is warm"

$CTL toggle
assert_eq normal "$($CTL get)" "toggle returns to normal"

$CTL toggle
assert_eq warm "$($CTL get)" "toggle returns to warm"

signal_count=$(wc -l <"$TMP/state/signals")
assert_eq 6 "$signal_count" "real state transitions signal Waybar"
assert_eq 0 "$(wc -l <"$TMP/state/legacy-signals")" "notification avoids process-name scanning"

COLORTEMP_HOUR=5 $CTL auto
assert_eq warm "$($CTL get)" "automatic schedule selects warm before 06:00"
COLORTEMP_HOUR=6 $CTL auto
assert_eq normal "$($CTL get)" "automatic schedule selects normal at 06:00"
COLORTEMP_HOUR=19 $CTL auto
assert_eq warm "$($CTL get)" "automatic schedule selects warm at 19:00"

export COLORTEMP_DEVICE_AVAILABLE=0
assert_eq off "$($CTL get)" "disconnected hardware reports off"

# The Waybar commands intentionally contain a literal $HOME for runtime.
# shellcheck disable=SC2016
grep -Fq 'on-scroll-up": "$HOME/bin/colortemp-ctl cooler"' "$WAYBAR"
# shellcheck disable=SC2016
grep -Fq 'on-scroll-down": "$HOME/bin/colortemp-ctl warmer"' "$WAYBAR"
grep -Fq 'Gigabyte USB hardware presets' "$WAYBAR"
grep -Fq '"exec-on-event": false' "$WAYBAR"
grep -Fq 'ExecStart=%h/bin/colortemp-ctl auto' "$SERVICE"
grep -Fq 'OnCalendar=*-*-* 06,19:00:00' "$TIMER"
assert_eq ../colortemp.service "$(readlink "$SERVICE_LINK")" \
    "graphical session applies the current profile"
assert_eq ../colortemp.timer "$(readlink "$TIMER_LINK")" \
    "graphical session enables the daily schedule"

if grep -Fqi 'hyprsunset' "$AUTOSTART" "$WAYBAR"; then
    fail "obsolete hyprsunset integration remains"
fi
if grep -Eq 'rgb-(red|green|blue)|kelvin_to_rgb' "$CTL"; then
    fail "unsupported continuous RGB path remains"
fi

printf 'PASS: colortemp-ctl\n'
