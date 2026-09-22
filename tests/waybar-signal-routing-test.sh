#!/usr/bin/env bash
# Regression: unrelated Waybar refreshes must not wake hardware probes.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG="$ROOT/home/.config/waybar/config.jsonc"
BRIGHTNESS="$ROOT/home/bin/brightness-ctl"
XT3_ACTION="$ROOT/home/.config/waybar/xt3-action.sh"
SCREENRECORD="$ROOT/home/bin/screenrecord"

python3 - "$CONFIG" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
def block(name):
    match = re.search(r'"' + re.escape(name) + r'"\s*:\s*\{(.*?)\n\s*\}', text, re.S)
    assert match, name
    return match.group(1)
xt3 = block('custom/xt3-status')
brightness = block('custom/brightness')
colortemp = block('custom/colortemp')
assert '"interval": 10' in xt3
assert '"signal": 15' in xt3
assert '"interval": "once"' in brightness
assert '"signal": 16' in brightness
assert '"interval": "once"' in colortemp
assert '"signal": 13' in colortemp
assert '"signal": 8' not in xt3
assert '"signal": 8' not in brightness
PY

grep -Fq 'SIGNAL_NUM=16' "$BRIGHTNESS"
grep -Fq 'WAYBAR_SIGNAL=15' "$XT3_ACTION"
grep -Fq 'RTMIN+15' "$SCREENRECORD"

# Exercise the real brightness producer with harmless stubs: a state change
# must emit RTMIN+16 and still perform the normal DDC worker path.
producer_tmp=$(mktemp -d)
producer_log="$producer_tmp/log"
trap 'rm -rf "$producer_tmp"; rm -f "${old:-}"' EXIT
mkdir -p "$producer_tmp/bin" "$producer_tmp/run"
cat >"$producer_tmp/bin/pkill" <<'STUB'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >>"$BRIGHTNESS_TEST_LOG"
STUB
cat >"$producer_tmp/bin/ddcutil" <<'STUB'
#!/usr/bin/env bash
printf 'ddcutil %s\n' "$*" >>"$BRIGHTNESS_TEST_LOG"
if [[ ${1:-} == detect ]]; then
  printf 'Display 1\n  I2C bus: /dev/i2c-7\n'
fi
STUB
chmod +x "$producer_tmp/bin/"*
BRIGHTNESS_TEST_LOG="$producer_log" \
XDG_RUNTIME_DIR="$producer_tmp/run" \
PATH="$producer_tmp/bin:/usr/bin:/bin" \
  "$BRIGHTNESS" 55
sleep 0.2
grep -Fq 'pkill -RTMIN+16' "$producer_log"
grep -Fq 'ddcutil --bus 7 --noverify --sleep-multiplier 0.1 setvcp 10 55' "$producer_log"
rm -rf "$producer_tmp"

# The old shared-signal configuration must fail this routing contract.
old=$(mktemp)
sed -e 's/"interval": 10/"interval": 2/' \
    -e 's/"signal": 15/"signal": 8/' \
    -e 's/"interval": "once"/"interval": 5/' \
    -e 's/"signal": 16/"signal": 8/' "$CONFIG" >"$old"
if python3 - "$old" 2>/dev/null <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
def block(name):
    return re.search(r'"' + re.escape(name) + r'"\s*:\s*\{(.*?)\n\s*\}', text, re.S).group(1)
xt3, brightness = block('custom/xt3-status'), block('custom/brightness')
assert '"signal": 8' not in xt3 and '"signal": 8' not in brightness
PY
then
  echo 'old shared-signal config unexpectedly passed' >&2
  exit 1
fi
printf '%s\n' 'prechange shared-signal config rejected as expected'

printf '%s\n' 'waybar signal routing: hardware probes isolated from workspace signal'
