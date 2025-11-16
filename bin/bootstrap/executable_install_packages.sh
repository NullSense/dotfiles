#!/bin/bash
set -e

PACKAGE_LIST_FILE="$HOME/bin/bootstrap/packages.txt"

if [ ! -f "$PACKAGE_LIST_FILE" ]; then
    echo "Error: Package list $PACKAGE_LIST_FILE not found."
    exit 1
fi

echo "Installing packages from $PACKAGE_LIST_FILE..."

PACKAGES_TO_INSTALL=$(grep -vE '^\s*#|^\s*$' "$PACKAGE_LIST_FILE")

if [ -n "$PACKAGES_TO_INSTALL" ]; then
    sudo pacman -S --needed --noconfirm $PACKAGES_TO_INSTALL
else
    echo "No packages to install."
fi

echo "Package installation complete."

if ! command -v paru &> /dev/null; then
    echo "Installing paru (AUR helper)..."
    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    (cd /tmp/paru-bin && makepkg -si --noconfirm)
    rm -rf /tmp/paru-bin
    echo "paru installed successfully."
else
    echo "paru already installed."
fi

# Install AUR packages
echo "Installing AUR packages..."
if command -v paru &> /dev/null; then
    paru -S --needed --noconfirm swaylock-effects
else
    echo "WARNING: paru not available. Please install AUR packages manually:"
    echo "  - swaylock-effects (for blur effects on lock screen)"
fi
