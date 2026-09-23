#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/home/bin/audio-cycle-sink"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Fake pactl: only get-default-sink is consulted in dry-run mode.
cat >"$tmp/pactl" <<'SH'
#!/bin/sh
[ "$1" = get-default-sink ] && echo "$FAKE_DEFAULT"
SH
chmod +x "$tmp/pactl"
export PATH="$tmp:$PATH" AUDIO_CYCLE_DRY_RUN=1

# Sink names must be discovered, not hardcoded to one PCI layout.
sinks=$'alsa_output.pci-0000_0d_00.6.analog-stereo\nalsa_output.pci-0000_01_00.1.hdmi-stereo'
out=$(AUDIO_CYCLE_SINKS=$sinks FAKE_DEFAULT=alsa_output.pci-0000_0d_00.6.analog-stereo "$script")
[[ $out == alsa_output.pci-0000_01_00.1.hdmi-stereo ]]
out=$(AUDIO_CYCLE_SINKS=$sinks FAKE_DEFAULT=alsa_output.pci-0000_01_00.1.hdmi-stereo "$script")
[[ $out == alsa_output.pci-0000_0d_00.6.analog-stereo ]]

# A different PCI layout (the old RX 6750 XT one) must work the same way.
old=$'alsa_output.pci-0000_0f_00.6.analog-stereo\nalsa_output.pci-0000_03_00.1.hdmi-stereo-extra4'
out=$(AUDIO_CYCLE_SINKS=$old FAKE_DEFAULT=alsa_output.pci-0000_0f_00.6.analog-stereo "$script")
[[ $out == alsa_output.pci-0000_03_00.1.hdmi-stereo-extra4 ]]
