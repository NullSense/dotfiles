#!/bin/bash
# Post-installation script for Arch Linux
# Run this after first boot as your user
# This integrates with your existing chezmoi bootstrap from github.com/NullSense/dotfiles

set -euo pipefail

echo "=== Arch Linux Post-Install Setup ==="

# Step 1: Initialize chezmoi and apply dotfiles
echo "[1/7] Setting up chezmoi and dotfiles..."
if ! command -v chezmoi &> /dev/null; then
    sudo pacman -S --noconfirm chezmoi
fi

# Use your existing dotfiles repo
CHEZMOI_REPO="https://github.com/NullSense/dotfiles.git"
chezmoi init --apply "$CHEZMOI_REPO"

echo "[2/7] Running your bootstrap scripts..."
# Your existing bootstrap will handle:
# - install_packages.sh (installs packages from packages.txt)
# - system_cfg.sh (enables timers, sets zsh, etc.)

if [ -f "$HOME/bin/bootstrap/install_packages.sh" ]; then
    "$HOME/bin/bootstrap/install_packages.sh"
fi

if [ -f "$HOME/bin/bootstrap/system_cfg.sh" ]; then
    "$HOME/bin/bootstrap/system_cfg.sh"
fi

# Step 2: Install paru (your preferred AUR helper)
echo "[3/7] Installing paru (AUR helper)..."
if ! command -v paru &> /dev/null; then
    git clone https://aur.archlinux.org/paru-bin.git ~/paru-bin
    (cd ~/paru-bin && makepkg -si --noconfirm)
    rm -rf ~/paru-bin
fi

# Step 3: Install AUR packages needed by your sway config
echo "[4/7] Installing AUR packages..."
paru -S --noconfirm --needed \
    sway-launcher-desktop \
    grimshot \
    swappy \
    helium-browser-bin

# Step 4: Ensure ALL systemd timers are enabled
# (some may already be enabled by system_cfg.sh, but --now is idempotent)
echo "[5/7] Enabling all recommended systemd timers..."

# SSD TRIM - critical for NVMe longevity
sudo systemctl enable --now fstrim.timer

# Pacman cache cleanup - keeps disk space in check
sudo systemctl enable --now paccache.timer

# Man page indexing
sudo systemctl enable --now man-db.timer

# File database for locate/plocate
sudo systemctl enable --now plocate-updatedb.timer

# Log rotation
sudo systemctl enable --now logrotate.timer

# Reflector - auto-update mirrorlist (from your auto_install.md)
# First configure reflector
sudo mkdir -p /etc/xdg/reflector
cat << 'EOF' | sudo tee /etc/xdg/reflector/reflector.conf > /dev/null
--save /etc/pacman.d/mirrorlist
--country Germany
--protocol https
--latest 10
--age 12
--sort rate
EOF
sudo systemctl enable --now reflector.timer

# Snapper timers for btrfs snapshots
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

# Step 5: Setup btrfs swapfile
echo "[6/7] Creating btrfs swapfile (8GB)..."
if [ ! -f /swap/swapfile ]; then
    sudo btrfs filesystem mkswapfile --size 8G /swap/swapfile
    # Ensure swapfile is not compressed (critical for btrfs)
    sudo chattr +C /swap/swapfile 2>/dev/null || true
    sudo chmod 600 /swap/swapfile
    sudo swapon /swap/swapfile
    echo "/swap/swapfile none swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null
fi

# Setup snapper for btrfs snapshots
echo "Setting up snapper..."
if command -v snapper &> /dev/null; then
    if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
        sudo snapper -c root create-config /
    fi
fi

# Step 6: Pacman.conf tweaks
echo "[7/7] Configuring pacman..."
# Enable Color, ParallelDownloads, VerbosePkgLists if not already
if ! grep -q "^Color" /etc/pacman.conf; then
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
fi
if ! grep -q "^ParallelDownloads" /etc/pacman.conf; then
    sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
fi
if ! grep -q "^VerbosePkgLists" /etc/pacman.conf; then
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
fi

# Enable essential services
echo "Enabling services..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now sshd

# Yazi theme (from your auto_install.md)
echo "Installing yazi gruvbox theme..."
if command -v ya &> /dev/null; then
    ya pack -a bennyyip/gruvbox-dark || true
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Enabled systemd timers:"
echo "  - fstrim.timer        (SSD TRIM weekly)"
echo "  - paccache.timer      (clean pacman cache weekly)"
echo "  - man-db.timer        (update man index)"
echo "  - plocate-updatedb.timer (update file database)"
echo "  - logrotate.timer     (rotate logs)"
echo "  - reflector.timer     (update mirrors weekly)"
echo "  - snapper-timeline.timer (hourly btrfs snapshots)"
echo "  - snapper-cleanup.timer  (cleanup old snapshots)"
echo ""
echo "Next steps:"
echo "  1. Log out and log back in (or reboot)"
echo "  2. Run 'sway' to start your desktop"
echo ""
echo "Your dotfiles from github.com/NullSense/dotfiles have been applied."
