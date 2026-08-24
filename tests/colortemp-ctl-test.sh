#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CTL="$ROOT/home/bin/colortemp-ctl"
CONFIG="$ROOT/home/.config/hypr/hyprsunset.conf"
AUTOSTART="$ROOT/home/.config/hypr/autostart.conf"
WAYBAR="$ROOT/home/.config/waybar/config.jsonc"
SCREENSHOT="$ROOT/home/bin/screenshot"
SERVICE_LINK="$ROOT/home/.config/systemd/user/graphical-session.target.wants/hyprsunset.service"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
    "hyprsunset identity get")
        cat "$COLORTEMP_TEST_STATE/identity"
        ;;
    "hyprsunset identity")
        printf 'true\n' >"$COLORTEMP_TEST_STATE/identity"
        ;;
    "hyprsunset temperature")
        cat "$COLORTEMP_TEST_STATE/kelvin"
        ;;
    "hyprsunset temperature "*)
        printf '%s\n' "$3" >"$COLORTEMP_TEST_STATE/kelvin"
        printf 'false\n' >"$COLORTEMP_TEST_STATE/identity"
        ;;
    *)
        printf 'unexpected hyprctl arguments: %s\n' "$*" >&2
        exit 64
        ;;
esac
EOF

cat >"$TMP/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COLORTEMP_TEST_STATE/signals"
EOF

chmod +x "$TMP/hyprctl" "$TMP/pkill"
mkdir -p "$TMP/state"
printf 'true\n' >"$TMP/state/identity"
printf '6500\n' >"$TMP/state/kelvin"
: >"$TMP/state/signals"

export COLORTEMP_HYPRCTL="$TMP/hyprctl"
export COLORTEMP_TEST_STATE="$TMP/state"
export PATH="$TMP:$PATH"

assert_eq() {
    local expected=$1 actual=$2 label=$3
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq 6500K "$($CTL get)" "identity is shown as neutral 6500K"

$CTL -100
assert_eq 6400K "$($CTL get)" "scrolling down from day starts at 6500K"

$CTL -5000
assert_eq 2500K "$($CTL get)" "temperature clamps at 2500K"

$CTL +5000
assert_eq 6500K "$($CTL get)" "6500K ceiling becomes unfiltered day mode"

$CTL night
assert_eq 4000K "$($CTL get)" "night preset is 4000K"

$CTL toggle
assert_eq 6500K "$($CTL get)" "toggle returns to day"

$CTL toggle
assert_eq 4000K "$($CTL get)" "toggle returns to night"

signal_count=$(wc -l <"$TMP/state/signals")
assert_eq 6 "$signal_count" "every state-changing command signals Waybar"

grep -Fq 'time = 06:00' "$CONFIG"
grep -Fq 'time = 19:00' "$CONFIG"
# The Waybar command intentionally contains a literal $HOME for runtime.
# shellcheck disable=SC2016
grep -Fq 'on-scroll-up": "$HOME/bin/colortemp-ctl +100"' "$WAYBAR"
# shellcheck disable=SC2016
grep -Fq 'on-scroll-down": "$HOME/bin/colortemp-ctl -100"' "$WAYBAR"
grep -Fq 'hyprsunset.service' "$AUTOSTART"
if grep -Fqi 'hyprshade' "$AUTOSTART" "$WAYBAR" "$SCREENSHOT"; then
    printf 'FAIL: obsolete hyprshade integration remains\n' >&2
    exit 1
fi
assert_eq /usr/lib/systemd/user/hyprsunset.service "$(readlink "$SERVICE_LINK")" \
    "graphical session enables hyprsunset"

printf 'PASS: colortemp-ctl\n'
