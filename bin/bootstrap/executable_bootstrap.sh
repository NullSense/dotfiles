#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

echo "🚀 Starting Arch Linux Bootstrap..."

# Ensure system is up-to-date and install essential packages
sudo pacman -Syu --noconfirm --needed chezmoi reflector

# Configure reflector to get best mirrors (example)
echo "Updating mirrorlist with Reflector..."
sudo reflector --country "Germany" --latest 7 --protocol https --age 10 --sort rate --save /etc/pacman.d/mirrorlist
sudo pacman -Syu --noconfirm # Sync again with new mirrors

CHEZMOI_REPO="https://github.com/NullSense/dots.git"
if [ -z "$CHEZMOI_REPO" ]; then
    echo "Error: CHEZMOI_REPO variable is not set. Please edit bootstrap.sh."
    exit 1
fi

echo "Initializing Chezmoi from $CHEZMOI_REPO..."
chezmoi init --apply "$CHEZMOI_REPO"

echo "Chezmoi initialized."
echo "Installing packages"
$HOME/bin/bootstrap/install_packages.sh
echo "Configuring system"
$HOME/bin/bootstrap/system_cfg.sh
echo "You might need to log out and log back in or reboot for all changes to take effect."
echo "🎉 Bootstrap complete!"
