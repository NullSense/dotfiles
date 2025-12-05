#!/bin/bash
# Development environment setup for Node.js, Python, Rust
# Simple approach: system packages + pnpm (no version manager bloat)

set -euo pipefail

echo "=== Development Environment Setup ==="
echo ""

# ============================================================================
# 1. NODE.JS + PNPM (for Expo.dev and JS projects)
# ============================================================================
echo "[1/4] Installing Node.js + pnpm..."

sudo pacman -S --noconfirm --needed \
    nodejs \
    npm \
    pnpm

# Global pnpm config (optional - faster installs)
pnpm config set store-dir ~/.local/share/pnpm/store

echo "Node.js $(node --version) installed"
echo "pnpm $(pnpm --version) installed"

# ============================================================================
# 2. PYTHON (system Python + pip)
# ============================================================================
echo "[2/4] Installing Python..."

sudo pacman -S --noconfirm --needed \
    python \
    python-pip \
    python-virtualenv \
    python-pipx

# pipx for global CLI tools (keeps them isolated)
pipx ensurepath

echo "Python $(python --version) installed"

# ============================================================================
# 3. RUST (via rustup - the standard way)
# ============================================================================
echo "[3/4] Installing Rust via rustup..."

if ! command -v rustup &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

echo "Rust $(rustc --version) installed"

# ============================================================================
# 4. ADDITIONAL DEV TOOLS
# ============================================================================
echo "[4/4] Installing additional dev tools..."

sudo pacman -S --noconfirm --needed \
    docker \
    docker-compose \
    github-cli \
    httpie \
    jq \
    yq

# Enable docker
sudo systemctl enable docker
sudo usermod -aG docker "$USER"

echo ""
echo "=== Development Environment Complete ==="
echo ""
echo "Installed:"
echo "  - Node.js $(node --version) + pnpm"
echo "  - Python $(python --version) + pip + pipx"
echo "  - Rust $(rustc --version 2>/dev/null || echo 'run: source ~/.cargo/env')"
echo "  - Docker, GitHub CLI, httpie, jq, yq"
echo ""
echo "Expo.dev workflow:"
echo "  pnpm create expo-app my-app"
echo "  cd my-app && pnpm install"
echo "  pnpm start"
echo ""
echo "Python virtual envs:"
echo "  python -m venv .venv"
echo "  source .venv/bin/activate"
echo ""
echo "Rust is managed by rustup:"
echo "  rustup update"
echo "  rustup default stable"
echo ""
echo "NOTE: Log out and back in for docker group to take effect"
echo ""

# ============================================================================
# OPTIONAL: Install mise if you need multiple Node/Python versions
# ============================================================================
cat << 'EOF'
=== OPTIONAL: mise (if you need multiple versions) ===

If you need different Node.js versions per project:
  curl https://mise.run | sh
  echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc

Then per project:
  cd my-project
  mise use node@18  # Creates .mise.toml

For now, system Node + pnpm should be fine for most Expo work.
EOF
