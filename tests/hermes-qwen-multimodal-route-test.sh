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
    qwen3.8-27b-nvfp4-long \
    qwen3.8-27b-nvfp4-long:think \
    qwen3.8-27b-nvfp4-long:fast
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
    [[ $max_input == 202240 ]] || fail "$alias must advertise 202240 input tokens plus the 8192-token output reserve"
done

grep -Fq -- '--max-model-len 210432' "$swap" \
    || fail 'Qwen NVFP4 route must allocate the 210432-token engine window'
grep -Fq -- '--max-num-seqs 3' "$swap" \
    || fail 'Qwen NVFP4 route must retain three scheduler slots'
grep -Fq -- '--kv-cache-dtype fp8' "$swap" \
    || fail 'Qwen NVFP4 route must use FP8 KV for the long-context budget'

[[ $(yq -r '.agent.reasoning_effort // ""' "$hermes_config") == low ]] \
    || fail 'Hermes must default Qwen requests to low reasoning effort'

[[ $(yq -r '.providers["qwen38-nvfp4"].extra_body.reasoning_effort // ""' "$hermes_config") == low ]] \
    || fail 'Hermes Qwen provider must default requests to low reasoning effort'

[[ $(yq -r '.model.supports_vision // false' "$hermes_config") == true ]] \
    || fail 'Hermes must route the custom Qwen provider through native vision'

[[ $(yq -r '.model.context_length // 0' "$hermes_config") == 202240 ]] \
    || fail 'Hermes must reserve 8192 output tokens inside the 210432-token engine window'

printf 'PASS: Hermes Qwen multimodal alias contract\n'
