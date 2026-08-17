#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
backends="$repo_root/home/.config/hyprwhspr-ai/backends.json"
hyprwhspr_python=${HYPRWHSPR_PYTHON:-$HOME/.local/share/hyprwhspr/venv/bin/python}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

active=$(jq -r '.active' "$backends")
[[ $active == qwen-long-fast ]] \
    || fail 'hyprwhspr-ai rewrite must target the resident Qwen profile'

base_url=$(jq -r --arg active "$active" '.backends[$active].base_url' "$backends")
[[ $base_url == http://127.0.0.1:9292 ]] \
    || fail 'rewrite profile must remain local to llama-swap'

model=$(jq -r --arg active "$active" '.backends[$active].model' "$backends")
[[ $model == qwen3.8-27b-nvfp4-long:fast ]] \
    || fail 'rewrite profile must reuse the non-thinking resident Qwen alias'

[[ -x $hyprwhspr_python ]] || fail "missing Hyprwhspr Python: $hyprwhspr_python"
providers=$(
    "$hyprwhspr_python" -c \
        'import json, onnxruntime as ort; print(json.dumps(ort.get_available_providers()))'
)
[[ $providers == '["CPUExecutionProvider"]' ]] \
    || fail "Hyprwhspr ONNX Runtime can still allocate GPU VRAM: $providers"

printf 'PASS: Hyprwhspr CPU ASR and resident-Qwen rewrite contract\n'
