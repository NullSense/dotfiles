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

    # shellcheck disable=SC2016
    max_input=$(yq -r --arg alias "$alias" \
        '.model_list[] | select(.model_name == $alias) | .model_info.max_input_tokens' "$models")
    [[ $max_input == 210432 ]] || fail "$alias must advertise the 210432-token input budget"
done

grep -Fq -- '--mmproj /home/nullsense/.lmstudio/models/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF/Qwen3.8-27B-Uncensored-vision-f16.gguf' "$swap" \
    || fail 'Qwen llama-swap route does not load its vision projector'

grep -Fq -- '--fit-ctx 219136' "$swap" \
    || fail 'Qwen llama-swap route must reserve input + output + slack context'

grep -Fq -- '--reasoning-effort medium' "$swap" \
    || fail 'Qwen llama-swap route must default to medium reasoning effort'

[[ $(yq -r '.model.supports_vision // false' "$hermes_config") == true ]] \
    || fail 'Hermes must route the custom Qwen provider through native vision'

[[ $(yq -r '.model.context_length // 0' "$hermes_config") == 210432 ]] \
    || fail 'Hermes must use the advertised 210432-token input budget'

printf 'PASS: Hermes Qwen multimodal alias contract\n'
