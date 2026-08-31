#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LAUNCHER="$ROOT/home/.local/bin/comfyui"
DESKTOP="$ROOT/home/.local/share/applications/comfyui.desktop"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$TMP/bin" "$TMP/home/.local/bin"

cat >"$TMP/bin/ss" <<'EOF'
#!/usr/bin/env bash
printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\n'
if [[ -e "$COMFYUI_TEST_DIR/up" ]]; then
    printf 'LISTEN 0 128 127.0.0.1:8188 0.0.0.0:*\n'
fi
EOF

cat >"$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ $* == '--user is-active --quiet comfyui.service' ]]; then
    [[ -e "$COMFYUI_TEST_DIR/up" ]]
    exit
fi
exit 0
EOF

cat >"$TMP/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COMFYUI_TEST_DIR/systemd-run"
touch "$COMFYUI_TEST_DIR/up"
EOF

cat >"$TMP/bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COMFYUI_TEST_DIR/xdg-open"
EOF

cat >"$TMP/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COMFYUI_TEST_DIR/notify-send"
EOF

chmod +x "$TMP/bin/ss" "$TMP/bin/systemctl" "$TMP/bin/systemd-run" \
    "$TMP/bin/xdg-open" "$TMP/bin/notify-send"

export COMFYUI_TEST_DIR=$TMP
export HOME="$TMP/home"
export PATH="$TMP/bin:$PATH"

"$LAUNCHER"

grep -Fq -- '--unit=comfyui' "$TMP/systemd-run" \
    || fail "cold launch must create the comfyui user service"
grep -Fq -- "$HOME/.local/bin/comfyui-server" "$TMP/systemd-run" \
    || fail "user service must execute the canonical server launcher"
grep -Fqx 'http://127.0.0.1:8188' "$TMP/xdg-open" \
    || fail "cold launch must open the local ComfyUI URL"

"$LAUNCHER"
[[ $(wc -l <"$TMP/systemd-run") == 1 ]] \
    || fail "warm launch must reuse the listening server"
[[ $(wc -l <"$TMP/xdg-open") == 2 ]] \
    || fail "warm launch must open the existing server"

if grep -Fq ghostty "$LAUNCHER"; then
    fail "launcher must not depend on an optional terminal emulator"
fi

grep -Fqx 'Exec=/home/nullsense/.local/bin/comfyui' "$DESKTOP"

printf 'PASS: comfyui-launcher\n'
