#!/bin/bash
# Hardware optimization for AMD Ryzen 9700X + RX 6750 XT + 64GB RAM
# Run AFTER post-install.sh.
# Most packages are already installed via archinstall; this script only adds
# AUR-only / niche tooling and tunes kernel cmdline + udev.

set -euo pipefail

echo "=== Hardware Optimization for Ryzen 9700X + RX 6750 XT ==="

# ============================================================================
# 1. AMD CPU sysctl tweaks
# ============================================================================
echo "[1/5] AMD CPU sysctl..."
sudo tee /etc/sysctl.d/99-amd-cpu.conf > /dev/null <<'EOF'
kernel.sched_autogroup_enabled = 1
EOF

# ============================================================================
# 2. AMD GPU power-management udev rule
# ============================================================================
echo "[2/5] AMD GPU udev (auto perf level)..."
sudo tee /etc/udev/rules.d/99-amdgpu.rules > /dev/null <<'EOF'
# AMD GPU power management - auto performance
ACTION=="add", SUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="auto"
EOF

# ============================================================================
# 3. NVMe I/O scheduler
# ============================================================================
echo "[3/5] NVMe I/O scheduler (none)..."
sudo tee /etc/udev/rules.d/60-ioschedulers.rules > /dev/null <<'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

# ============================================================================
# 4. Optional GPU OC tools (AUR / extra) and gamemode user config
# ============================================================================
echo "[4/5] Optional GPU OC tools + gamemode config..."
if command -v paru &>/dev/null; then
  # corectrl is in extra; lact is AUR. Skip if you don't OC.
  paru -S --noconfirm --needed corectrl lact protonup-qt || true
fi
systemctl --user enable --now gamemoded || true
mkdir -p ~/.config/gamemode
cat > ~/.config/gamemode/gamemode.ini <<'EOF'
[general]
renice = 10
ioprio = 0

[gpu]
apply_gpu_optimisations = accept-responsibility
gpu_device = 0
amd_performance_level = high

[custom]
start = notify-send "GameMode" "Started"
end = notify-send "GameMode" "Ended"
EOF

# ============================================================================
# 5. Kernel cmdline — UKI path (/etc/kernel/cmdline) + mkinitcpio rebuild
# ============================================================================
echo "[5/5] Kernel cmdline (UKI: /etc/kernel/cmdline)..."

# Defaults you probably want on this hardware:
#   amd_pstate=active           — EPP mode (often default on 6.12+, harmless to set)
#   zswap.enabled=0             — disable zswap (we use zram)
# OPTIONAL (skip unless you actively overclock the GPU):
#   amdgpu.ppfeaturemask=0xffffffff
DESIRED_PARAMS="amd_pstate=active zswap.enabled=0"

CMDLINE_FILE="/etc/kernel/cmdline"
if [ ! -f "$CMDLINE_FILE" ]; then
  echo "WARNING: $CMDLINE_FILE not found. Are you actually using UKI? Aborting cmdline edit."
  echo "Under UKI, kernel cmdline lives in /etc/kernel/cmdline (or /etc/cmdline.d/*.conf)"
  echo "and is rebuilt into the UKI by 'mkinitcpio -P'. Do NOT edit /boot/loader/entries/*"
  echo "in UKI mode — those files don't exist. Check /etc/mkinitcpio.d/*.preset for UKI presets."
  exit 0
fi

CURRENT="$(sudo cat "$CMDLINE_FILE")"
echo "Current cmdline: $CURRENT"
echo "Desired additions: $DESIRED_PARAMS"

NEEDS_UPDATE=0
NEW_CMDLINE="$CURRENT"
for p in $DESIRED_PARAMS; do
  KEY="${p%%=*}"
  if ! grep -qE "(^|[[:space:]])${KEY}(=|[[:space:]]|$)" <<< "$CURRENT"; then
    NEW_CMDLINE="$NEW_CMDLINE $p"
    NEEDS_UPDATE=1
  fi
done

if [ "$NEEDS_UPDATE" -eq 1 ]; then
  read -p "Update $CMDLINE_FILE and rebuild UKIs? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo cp "$CMDLINE_FILE" "${CMDLINE_FILE}.bak"
    echo "$NEW_CMDLINE" | sudo tee "$CMDLINE_FILE" > /dev/null
    echo "New cmdline: $(sudo cat "$CMDLINE_FILE")"
    echo "Rebuilding UKIs for all installed kernels..."
    sudo mkinitcpio -P
    echo "Done. Reboot to apply."
  fi
else
  echo "Cmdline already contains desired params — nothing to do."
fi

echo
echo "=== Hardware Optimization Complete ==="
echo "Verification after reboot:"
echo "  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver   # amd-pstate-epp"
echo "  zramctl                                                    # 16GB zram"
echo "  swapon --show                                              # zram + /swap/swapfile"
echo "  vulkaninfo --summary | grep deviceName                     # AMD Radeon RX 6750 XT"
echo "  sensors                                                    # temps"
