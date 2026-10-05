#!/usr/bin/env bash
set -euo pipefail

# Recurring caller: WirePlumber loads home/.config/wireplumber/wireplumber.conf.d/
# at every login. Regression: exact PCI bus addresses in node/device matches went
# stale after hardware changes (RTX 5090 swap, iGPU disabled), so the ALC1220 lost
# its rules and auto-port jumped to the empty front Headphones port (silence).

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
conf="$repo/home/.config/wireplumber/wireplumber.conf.d/51-friendly-names.conf"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$conf" ]] || fail "missing $conf"

# No hard-coded PCI bus numbers in any match (they move when PCIe devices change).
if grep -vE '^\s*#' "$conf" | grep -qE '"alsa_(output|card)\.pci-0000_[0-9a-f]{2}_'; then
    fail 'match still pins an exact PCI bus address'
fi

grep -qE 'device\.name = "~alsa_card\\\\\.pci-\.\*_00\\\\\.6\$"' "$conf" \
    || fail 'ALC1220 device rule (regex on PCI function .6) missing'
grep -qE 'api\.acp\.auto-port = false' "$conf" \
    || fail 'auto-port must be disabled for the ALC1220'

# The regex must match today's real names and not the GPU's HDMI card.
re_card='^alsa_card\.pci-.*_00\.6$'
[[ "alsa_card.pci-0000_0d_00.6" =~ $re_card ]] || fail 'card regex misses ALC1220'
[[ "alsa_card.pci-0000_0f_00.6" =~ $re_card ]] || fail 'card regex not bus-independent'
[[ "alsa_card.pci-0000_01_00.1" =~ $re_card ]] && fail 'card regex also matches GPU HDMI audio'

printf 'PASS: WirePlumber ALC1220 rules are bus-independent with manual port\n'
