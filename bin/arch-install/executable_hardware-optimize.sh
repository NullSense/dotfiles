#!/bin/bash
# Hardware optimization for AMD Ryzen 9700X + RX 6750 XT + 64GB RAM
# Run after post-install.sh

set -euo pipefail

echo "=== Hardware Optimization for Ryzen 9700X + RX 6750 XT ==="

# ============================================================================
# 1. ZRAM SETUP (Better than swap for 64GB RAM)
# ============================================================================
echo "[1/6] Configuring zram..."

# Install zram-generator (simpler than manual setup)
sudo pacman -S --noconfirm --needed zram-generator

# Configure zram - 16GB compressed swap (25% of 64GB)
# Using zstd compression (best for modern CPUs)
cat << 'EOF' | sudo tee /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# Disable zswap (conflicts with zram)
echo "Disabling zswap..."
if ! grep -q "zswap.enabled=0" /etc/kernel/cmdline 2>/dev/null; then
    # For systemd-boot, we'll add to loader entry
    echo "Add 'zswap.enabled=0' to kernel parameters manually if needed"
fi

# Optimize vm settings for zram
cat << 'EOF' | sudo tee /etc/sysctl.d/99-zram.conf
# Zram optimizations for 64GB RAM
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
EOF

# ============================================================================
# 2. AMD CPU OPTIMIZATIONS (Ryzen 9700X / Zen 5)
# ============================================================================
echo "[2/6] Configuring AMD CPU optimizations..."

# Install AMD microcode (should already be installed)
sudo pacman -S --noconfirm --needed amd-ucode

# AMD P-State driver config (for dynamic frequency scaling)
cat << 'EOF' | sudo tee /etc/sysctl.d/99-amd-cpu.conf
# AMD CPU optimizations
# Allow kernel to manage CPU frequency efficiently
kernel.sched_autogroup_enabled = 1
EOF

# Install monitoring tools
sudo pacman -S --noconfirm --needed lm_sensors

# ============================================================================
# 3. AMD GPU SETUP (RX 6750 XT / RDNA2)
# ============================================================================
echo "[3/6] Configuring AMD GPU (RDNA2)..."

# Install GPU drivers and tools
sudo pacman -S --noconfirm --needed \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    libva-mesa-driver \
    lib32-libva-mesa-driver \
    mesa-vdpau \
    lib32-mesa-vdpau \
    rocm-opencl-runtime \
    vulkan-tools

# Install GPU control tools (requires paru from post-install.sh)
if command -v paru &> /dev/null; then
    paru -S --noconfirm --needed corectrl lact
else
    echo "WARNING: paru not installed, skipping corectrl and lact"
    echo "Run post-install.sh first, then re-run this script"
fi

# Create udev rule for GPU power management
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-amdgpu.rules
# AMD GPU power management - auto performance
ACTION=="add", SUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="auto"
EOF

# ============================================================================
# 4. GAMING SETUP (Steam + Proton)
# ============================================================================
echo "[4/6] Setting up gaming (Steam + Proton)..."

# Enable multilib if not already (should be enabled)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling multilib repository..."
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    sudo pacman -Sy
fi

# Install Steam and gaming essentials
sudo pacman -S --noconfirm --needed \
    steam \
    gamemode \
    lib32-gamemode \
    mangohud \
    lib32-mangohud \
    gamescope

# Install ProtonUp-Qt for managing Proton versions
if command -v paru &> /dev/null; then
    paru -S --noconfirm --needed protonup-qt
else
    echo "WARNING: paru not installed, skipping protonup-qt"
fi

# Enable gamemode
systemctl --user enable --now gamemoded

# Create gamemode config
mkdir -p ~/.config/gamemode
cat << 'EOF' > ~/.config/gamemode/gamemode.ini
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

echo ""
echo "=== STEAM LAUNCH OPTIONS for best performance: ==="
echo "gamemoderun mangohud %command%"
echo ""

# ============================================================================
# 5. I/O SCHEDULER FOR NVMe
# ============================================================================
echo "[5/6] Configuring I/O scheduler for NVMe..."

# Use 'none' scheduler for NVMe (lowest latency)
cat << 'EOF' | sudo tee /etc/udev/rules.d/60-ioschedulers.rules
# NVMe - use none scheduler
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# SATA SSD - use mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF

# ============================================================================
# 6. APPLY CHANGES
# ============================================================================
echo "[6/6] Applying sysctl changes..."
sudo sysctl --system

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# ============================================================================
# 7. KERNEL PARAMETERS (Interactive)
# ============================================================================
echo "[7/7] Kernel boot parameters..."

BOOT_ENTRY="/boot/loader/entries/arch.conf"
KERNEL_PARAMS="amd_pstate=active zswap.enabled=0 amdgpu.ppfeaturemask=0xffffffff"

if [ -f "$BOOT_ENTRY" ]; then
    echo ""
    echo "Current boot entry:"
    grep "^options" "$BOOT_ENTRY"
    echo ""
    echo "Recommended kernel parameters to add:"
    echo "  $KERNEL_PARAMS"
    echo ""
    echo "  amd_pstate=active    - AMD P-State CPU frequency driver"
    echo "  zswap.enabled=0      - Disable zswap (using zram instead)"
    echo "  amdgpu.ppfeaturemask - Enable GPU overclocking via CoreCtrl"
    echo ""

    # Check if parameters already exist
    if grep -q "amd_pstate=active" "$BOOT_ENTRY"; then
        echo "Kernel parameters already present - no changes needed."
    else
        read -p "Add these kernel parameters automatically? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Backup original
            sudo cp "$BOOT_ENTRY" "${BOOT_ENTRY}.backup"
            echo "Backup created: ${BOOT_ENTRY}.backup"

            # Add kernel parameters
            sudo sed -i "s/^options \(.*\)$/options \1 $KERNEL_PARAMS/" "$BOOT_ENTRY"
            echo "Kernel parameters added!"
            echo ""
            echo "New boot entry:"
            grep "^options" "$BOOT_ENTRY"
        else
            echo ""
            echo "Skipped. To add manually, edit:"
            echo "  sudo nvim $BOOT_ENTRY"
            echo ""
            echo "Add to the 'options' line:"
            echo "  $KERNEL_PARAMS"
        fi
    fi
else
    echo "Boot entry not found at $BOOT_ENTRY"
    echo ""
    echo "Find your boot entry:"
    echo "  ls /boot/loader/entries/"
    echo ""
    echo "Then add these kernel parameters to the 'options' line:"
    echo "  $KERNEL_PARAMS"
fi

echo ""
echo "=== Hardware Optimization Complete ==="
echo ""
echo "Reboot for all changes to take effect."
echo ""
echo "Post-reboot verification:"
echo "  zramctl                     # Check zram"
echo "  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver  # Should show amd-pstate"
echo "  vulkaninfo | grep deviceName  # Check Vulkan"
echo "  steam                       # Test gaming"
