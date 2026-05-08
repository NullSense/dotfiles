#!/usr/bin/env bash
# Bootstrap the NLLB translation pipeline on a fresh machine.
#
# Idempotent — safe to re-run. Skips steps already done.
#
# Final state:
#   ~/.local/share/hyprwhspr-translate/.venv/      Python 3.12 venv
#   ~/.local/share/hyprwhspr-translate/nllb-1.3B-int8/   1.4GB model
#   systemctl --user enable --now hyprwhspr-nllb         (lazy-loaded server)

set -euo pipefail

DIR="$HOME/.local/share/hyprwhspr-translate"
cd "$DIR"

echo "[1/4] mise: install pinned python + uv"
if ! command -v mise >/dev/null; then
  echo "ERROR: mise not installed. Install via: pacman -S mise" >&2
  exit 1
fi
mise install

echo "[2/4] uv: create venv with mise-pinned python"
if [[ ! -x ".venv/bin/python" ]]; then
  uv venv --python "$(mise where python)/bin/python"
fi

echo "[3/4] uv: install runtime deps (~300MB)"
uv pip install --python .venv/bin/python --quiet \
  ctranslate2 sentencepiece transformers huggingface-hub

echo "[4/4] download NLLB-200 INT8 model (~1.4GB) if missing"
if [[ ! -f "nllb-1.3B-int8/model.bin" ]]; then
  .venv/bin/python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='OpenNMT/nllb-200-distilled-1.3B-ct2-int8',
    local_dir='./nllb-1.3B-int8',
    allow_patterns=['*.bin', '*.json', '*.txt', '*.spm', 'sentencepiece*'],
)
print('downloaded')
"
else
  echo "  model already present, skipping"
fi

echo
echo "Done. Enable the server:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now hyprwhspr-nllb"
echo
echo "Test:"
echo "  echo 'Hello world' | hyprwhspr-nllb eng_Latn lit_Latn"
