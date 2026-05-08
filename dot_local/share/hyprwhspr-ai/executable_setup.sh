#!/usr/bin/env bash
# Idempotent bootstrap for the hyprwhspr-ai daemon.
#
# Final state:
#   ~/.local/share/hyprwhspr-ai/.venv/    Python 3.12 venv (mise-pinned)
#   ~/.local/share/hyprwhspr-ai/src/      package source
#   systemctl --user enable --now hyprwhspr-ai.service

set -euo pipefail

DIR="$HOME/.local/share/hyprwhspr-ai"
cd "$DIR"

echo "[1/3] mise: install pinned python + uv"
if ! command -v mise >/dev/null; then
  echo "ERROR: mise not installed. Install via: pacman -S mise" >&2
  exit 1
fi
mise install

echo "[2/3] uv: create venv with mise-pinned python (3.12)"
if [[ ! -x ".venv/bin/python" ]]; then
  uv venv --python "$(mise where python)/bin/python"
fi

echo "[3/3] uv: install runtime deps"
uv pip install --python .venv/bin/python --quiet -e ".[dev]"

echo
echo "Done. Enable the daemon:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now hyprwhspr-ai.service"
echo
echo "Test:"
echo "  hyprwhspr-ai ping"
