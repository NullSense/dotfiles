#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CTL="$ROOT/home/bin/hdr-toggle"
BINDINGS="$ROOT/home/.config/hypr/bindings.conf"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected=$1 actual=$2 message=$3
    [ "$expected" = "$actual" ] || fail "$message: expected '$expected', got '$actual'"
}

mkdir -p "$TMP/bin"
printf 'srgb\n' >"$TMP/preset"

cat >"$TMP/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
    '-j monitors all')
        preset=$(cat "$HDR_TEST_DIR/preset")
        jq -n --arg preset "$preset" '[{
            name: "DP-7",
            description: "GIGA-BYTE TECHNOLOGY CO. LTD. AORUS FO32U2 SERIAL",
            model: "AORUS FO32U2",
            width: 3840,
            height: 2160,
            refreshRate: 239.97,
            x: 100,
            y: 20,
            scale: 1.5,
            colorManagementPreset: $preset
        }]'
        ;;
    'keyword monitor '*)
        printf '%s\n' "$3" >>"$HDR_TEST_DIR/commands"
        case "$3" in
            'DP-7, 3840x2160@239.97, 100x20, 1.5, bitdepth, 10, cm, hdr')
                printf 'hdr\n' >"$HDR_TEST_DIR/preset"
                ;;
            'DP-7, 3840x2160@239.97, 100x20, 1.5, bitdepth, 10, cm, srgb')
                printf 'srgb\n' >"$HDR_TEST_DIR/preset"
                ;;
            *)
                printf 'unexpected monitor specification: %s\n' "$3" >&2
                exit 1
                ;;
        esac
        printf 'ok\n'
        ;;
    'keyword decoration:screen_shader [[EMPTY]]')
        printf '%s\n' "$*" >>"$HDR_TEST_DIR/shader_commands"
        printf 'ok\n'
        ;;
    *)
        printf 'unexpected hyprctl invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF

cat >"$TMP/bin/colortemp-ctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HDR_TEST_DIR/colortemp"
EOF

cat >"$TMP/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HDR_TEST_DIR/notifications"
EOF

cat >"$TMP/bin/modetest" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
preset=$(cat "$HDR_TEST_DIR/preset")
value=0
if [ "$preset" = hdr ] && [ "${HDR_TEST_KMS_REJECT:-0}" != 1 ]; then
    value=9
fi
cat <<EOT
Connectors:
77 76 connected DP-7 690x390 42 76
  props:
    1215 Colorspace:
        flags: enum
        enums: Default=0 BT2020_RGB=9 BT2020_YCC=10
        value: $value
    8 HDR_OUTPUT_METADATA:
        flags: blob
        blobs:
        value:
EOT
EOF

chmod +x "$TMP/bin/hyprctl" "$TMP/bin/colortemp-ctl" "$TMP/bin/notify-send" "$TMP/bin/modetest"
export HDR_HYPRCTL="$TMP/bin/hyprctl"
export HDR_COLORTEMP_CTL="$TMP/bin/colortemp-ctl"
export HDR_NOTIFY_SEND="$TMP/bin/notify-send"
export HDR_MODETEST="$TMP/bin/modetest"
export HDR_TEST_DIR="$TMP"
unset AQ_NO_ATOMIC

"$CTL"
assert_eq hdr "$(cat "$TMP/preset")" "SDR toggles to HDR"
assert_eq 'DP-7, 3840x2160@239.97, 100x20, 1.5, bitdepth, 10, cm, hdr' \
    "$(tail -n 1 "$TMP/commands")" "toggle targets the live connector and geometry"
assert_eq default "$(tail -n 1 "$TMP/colortemp")" "HDR disables the night-color transform"
assert_eq 'keyword decoration:screen_shader [[EMPTY]]' "$(tail -n 1 "$TMP/shader_commands")" \
    "HDR removes the compositor night-color shader"

"$CTL"
assert_eq srgb "$(cat "$TMP/preset")" "HDR toggles back to SDR"
assert_eq auto "$(tail -n 1 "$TMP/colortemp")" "SDR restores scheduled night color"

if HDR_TEST_KMS_REJECT=1 "$CTL"; then
    fail "rejected NVIDIA HDR metadata must fail the toggle"
fi
assert_eq srgb "$(cat "$TMP/preset")" "rejected HDR signal rolls back to SDR"
assert_eq auto "$(tail -n 1 "$TMP/colortemp")" \
    "rejected HDR signal restores scheduled night color"

grep -Fq 'bindd = SUPER ALT, H,           Toggle HDR (DP-1),       exec, /home/nullsense/bin/hdr-toggle' "$BINDINGS"

if grep -Fq '/tmp/hdr-state' "$CTL"; then
    fail "HDR state must come from Hyprland, not a stale temporary file"
fi

printf 'srgb\n' >"$TMP/preset"
command_count=$(wc -l <"$TMP/commands")
if AQ_NO_ATOMIC=1 "$CTL"; then
    fail "legacy DRM session must reject hardware HDR"
fi
assert_eq "$command_count" "$(wc -l <"$TMP/commands")" \
    "legacy DRM rejection must not touch the monitor"

printf 'PASS: hdr-toggle\n'
