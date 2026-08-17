#!/usr/bin/env bash
# Literal shell fragments below intentionally must not expand in this test.
# shellcheck disable=SC2016
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
models="$repo_root/home/.config/litellm/models.yaml"
swap="$repo_root/home/.config/llama-swap/config.yaml"
qwen_wrapper="$repo_root/home/bin/llm-servers/vllm-qwen38"
vllm_common="$repo_root/home/bin/llm-servers/_vllm-common.sh"
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

grep -Fq 'cmd: env PORT=${PORT} /home/nullsense/bin/llm-servers/vllm-qwen38' "$swap" \
    || fail 'llama-swap must delegate the Qwen engine contract to its wrapper'
grep -Fq 'checkEndpoint: /health' "$swap" \
    || fail 'llama-swap must wait for vLLM readiness before forwarding requests'
grep -Fq -- '--max-model-len "$MAX_MODEL_LEN"' "$qwen_wrapper" \
    || fail 'Qwen NVFP4 route must allocate the 210432-token engine window'
grep -Fq 'MAX_MODEL_LEN="${MAX_MODEL_LEN:-210432}"' "$qwen_wrapper" \
    || fail 'Qwen wrapper must default to the measured 210432-token window'
grep -Fq 'MAX_NUM_SEQS="${MAX_NUM_SEQS:-3}"' "$qwen_wrapper" \
    || fail 'Qwen NVFP4 route must retain three scheduler slots'
grep -Fq -- '--kv-cache-dtype fp8' "$qwen_wrapper" \
    || fail 'Qwen NVFP4 route must use FP8 KV for the long-context budget'
grep -Fq -- '--enable-prefix-caching' "$qwen_wrapper" \
    || fail 'Qwen NVFP4 route must preserve automatic prefix caching'
grep -Fq -- '--enable-chunked-prefill' "$qwen_wrapper" \
    || fail 'Qwen NVFP4 route must preserve chunked prefill'

grep -Fq 'VLLM_CACHE_ROOT=/root/.cache/vllm' "$vllm_common" \
    || fail 'shared vLLM cache root is not explicit'
grep -Fq '$VLLM_CACHE_HOST:/root/.cache/vllm' "$vllm_common" \
    || fail 'vLLM generated artifacts are not persisted'
grep -Fq '$VLLM_TRITON_CACHE_HOST:/root/.triton/cache' "$vllm_common" \
    || fail 'Triton kernels are not persisted'

rendered=$(PORT=19316 VLLM_DRY_RUN=1 "$qwen_wrapper")
[[ $rendered == *'--max-model-len 210432'* ]] \
    || fail 'rendered Qwen command lost its 210432-token window'
[[ $rendered == *'--max-num-seqs 3'* ]] \
    || fail 'rendered Qwen command lost its three scheduler slots'
[[ $rendered == *'/root/.cache/vllm'* ]] \
    || fail 'rendered Qwen command does not mount its namespaced vLLM cache'
[[ $rendered == *'/root/.triton/cache'* ]] \
    || fail 'rendered Qwen command does not mount its namespaced Triton cache'
[[ $rendered != *'/root/.cache/huggingface'* ]] \
    || fail 'local Qwen must not receive the Hugging Face cache or credentials'

[[ $(yq -r '.hooks.on_startup.preload[] | select(. == "qwen3.8-27b-nvfp4-long")' "$swap") == qwen3.8-27b-nvfp4-long ]] \
    || fail 'llama-swap must preload Qwen so built-in autotuning finishes before use'

[[ $(yq -r '.agent.reasoning_effort // ""' "$hermes_config") == low ]] \
    || fail 'Hermes must default Qwen requests to low reasoning effort'

[[ $(yq -r '.providers["qwen38-nvfp4"].extra_body.reasoning_effort // ""' "$hermes_config") == low ]] \
    || fail 'Hermes Qwen provider must default requests to low reasoning effort'

[[ $(yq -r '.model.supports_vision // false' "$hermes_config") == true ]] \
    || fail 'Hermes must route the custom Qwen provider through native vision'

[[ $(yq -r '.model.context_length // 0' "$hermes_config") == 202240 ]] \
    || fail 'Hermes must reserve 8192 output tokens inside the 210432-token engine window'

printf 'PASS: Hermes Qwen multimodal alias contract\n'
