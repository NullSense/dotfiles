#!/usr/bin/env bash
# Regression: disabling privacy-dots must retain X-T3 and GPU recording state.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/run"
export XDG_RUNTIME_DIR="$test_root/run"
export PRIVACY_CALLED="$test_root/privacy-called"
export CONSUMER_PID=$$
cat >"$test_root/bin/privacy-dots" <<'STUB'
#!/usr/bin/env bash
: >"$PRIVACY_CALLED"
printf '%s\n' '{"class":"mic-on cam-on scr-on","tooltip":"unexpected privacy probe"}'
STUB
cat >"$test_root/bin/lsusb" <<'STUB'
#!/usr/bin/env bash
[[ "$CAMERA_STATE" == off ]] || echo 'Bus 001 Device 003: ID 04cb:02dd FUJIFILM X-T3'
exit 0
STUB
cat >"$test_root/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
[[ "$CAMERA_STATE" == ready || "$CAMERA_STATE" == live ]]
STUB
cat >"$test_root/bin/fuser" <<'STUB'
#!/usr/bin/env bash
[[ "$CAMERA_STATE" == live ]] || exit 1
printf '%s\n' "$CONSUMER_PID"
STUB
cat >"$test_root/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ "$RECORDING" == 1 ]]
STUB
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:/usr/bin:/bin"
for CAMERA_STATE in off idle ready live; do
  export CAMERA_STATE
  for RECORDING in 0 1; do
    export RECORDING
    output=$("$repo_root/home/.config/waybar/xt3-status.sh")
    [[ ! -e "$PRIVACY_CALLED" ]] || { echo 'privacy-dots was invoked' >&2; exit 1; }
    python3 - "$output" <<'PY'
import json, os, sys
value = json.loads(sys.argv[1])
assert value['class'] == value['alt'] == os.environ['CAMERA_STATE'], value
assert 'Privacy monitoring disabled' in value['tooltip'], value
assert 'X-T3' in value['tooltip'], value
assert '󰍮' not in value['text'] and '󰄁' not in value['text'], value
recording = os.environ['RECORDING'] == '1'
assert ('Screen recording: active' in value['tooltip']) == recording, value
assert ('#c678dd' in value['text']) == recording, value
cache_path = os.path.join(os.environ['XDG_RUNTIME_DIR'], 'waybar-xt3-status.json')
if os.path.exists(cache_path):
    with open(cache_path) as cache:
        assert json.load(cache) == value
PY
  done
done
printf '%s\n' 'waybar xt3 status: 8 state combinations passed'
