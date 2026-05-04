#!/bin/bash
# OPTIONAL: System-installed dev toolchains.
# post-install.sh already installs mise + uv + bun, which covers most needs.
# Run this ONLY if you prefer system-managed Node/Python/Rust over mise.
#
# Most things below are commented out by default. Uncomment what you want.

set -euo pipefail

echo "=== Optional dev environment (system packages) ==="
echo "post-install.sh already installed: mise, uv, bun, github-cli, jq, yq, httpie, docker."
echo "This script only installs system Node/Python/Rust if you don't want mise."
echo
read -p "Continue? [y/N] " -n 1 -r; echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 0

# --- System Node + pnpm (alternative to mise/bun) ---
# sudo pacman -S --noconfirm --needed nodejs npm pnpm
# pnpm config set store-dir ~/.local/share/pnpm/store

# --- System Python tooling (alternative to uv) ---
# sudo pacman -S --noconfirm --needed python python-pip python-virtualenv python-pipx
# pipx ensurepath

# --- Rust via rustup (rustup-managed, distinct from system /usr/bin/rust) ---
if ! command -v rustup &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
fi

echo "Done. Log out + back in for any group changes (docker)."
