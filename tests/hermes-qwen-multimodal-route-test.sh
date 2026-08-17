#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
models="$repo_root/home/.config/litellm/models.yaml"
swap="$repo_root/home/.config/llama-swap/config.yaml"
hermes_config=${HERMES_CONFIG:-$HOME/.hermes/config.yaml}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for alias in \
    qwen3.8-27b-uncensored \
    qwen3.8-27b-uncensored:think \
    qwen3.8-27b-uncensored:fast
do
    # shellcheck disable=SC2016
    count=$(yq -r --arg alias "$alias" \
        '[.model_list[] | select(.model_name == $alias)] | length' "$models")
    [[ $count == 1 ]] || fail "LiteLLM must define exactly one $alias deployment"

    # shellcheck disable=SC2016
    vision=$(yq -r --arg alias "$alias" \
        '.model_list[] | select(.model_name == $alias) | .model_info.supports_vision' "$models")
    [[ $vision == true ]] || fail "$alias must advertise vision support"
done

grep -Fq -- '--mmproj /home/nullsense/.lmstudio/models/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF/Qwen3.8-27B-Uncensored-vision-f16.gguf' "$swap" \
    || fail 'Qwen llama-swap route does not load its vision projector'

[[ $(yq -r '.model.supports_vision // false' "$hermes_config") == true ]] \
    || fail 'Hermes must route the custom Qwen provider through native vision'

printf 'PASS: Hermes Qwen multimodal alias contract\n'
