#!/usr/bin/env bash
# Shared container contract for every vLLM wrapper.
#
# Source this after setting PORT. Callers then pass VLLM_MOUNTS, VLLM_ENV,
# VLLM_ULIMITS, and VLLM_NET to `docker run`. All generated code and autotune
# state is kept below one host cache root so ephemeral containers warm once per
# model-wrapper and image combination instead of once per launch. The namespace
# is also a trust boundary: remote model code cannot poison another model's
# executable compilation cache.

set -euo pipefail

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  printf '_vllm-common.sh must be sourced by a model wrapper\n' >&2
  exit 2
fi

: "${PORT:?set PORT before sourcing _vllm-common.sh}"

vllm_cache_root_host="${VLLM_CACHE_ROOT_HOST:-$HOME/.cache/vllm}"
vllm_cache_caller="${VLLM_CACHE_NAMESPACE:-$(basename -- "${BASH_SOURCE[1]:-vllm}")}"
vllm_cache_image="${VLLM_IMAGE:-${IMAGE:-unknown-image}}"
vllm_cache_image_hash=$(printf '%s' "$vllm_cache_image" | sha256sum | cut -c1-12)
VLLM_CACHE_HOST="${VLLM_CACHE_HOST:-$vllm_cache_root_host/runtimes/$vllm_cache_caller-$vllm_cache_image_hash}"
VLLM_TRITON_CACHE_HOST="${VLLM_TRITON_CACHE_HOST:-$VLLM_CACHE_HOST/triton}"

mkdir -p \
  "$VLLM_CACHE_HOST" \
  "$VLLM_CACHE_HOST/cuda" \
  "$VLLM_CACHE_HOST/torch_extensions" \
  "$VLLM_TRITON_CACHE_HOST"

VLLM_MOUNTS=(
  -v "$VLLM_CACHE_HOST:/root/.cache/vllm"
  -v "$VLLM_TRITON_CACHE_HOST:/root/.triton/cache"
  -v "$HOME/.lmstudio/models:$HOME/.lmstudio/models:ro"
)

# Never mount the Hugging Face cache root: it contains `token` and
# `stored_tokens`. Existing remote-ID wrappers receive only the token-free
# content-addressed hub subtree; local wrappers can opt out with `none`. The hub
# is read-only because downloads belong to the host control plane, not
# model-serving containers.
case "${VLLM_HF_CACHE_MODE:-hub}" in
  none) ;;
  hub)
    mkdir -p "$HOME/.cache/huggingface/hub"
    VLLM_MOUNTS+=(
      -v "$HOME/.cache/huggingface/hub:/root/.cache/huggingface/hub:ro"
    )
    ;;
  *)
    printf 'invalid VLLM_HF_CACHE_MODE=%q (expected none or hub)\n' \
      "$VLLM_HF_CACHE_MODE" >&2
    return 2
    ;;
esac

if [[ -n "${VLLM_EXTRA_MOUNT:-}" ]]; then
  VLLM_MOUNTS+=(-v "$VLLM_EXTRA_MOUNT")
fi

VLLM_ENV=(
  -e PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
  -e HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
  -e VLLM_CACHE_ROOT=/root/.cache/vllm
  -e CUDA_CACHE_PATH=/root/.cache/vllm/cuda
  -e TORCH_EXTENSIONS_DIR=/root/.cache/vllm/torch_extensions
  -e VLLM_NO_USAGE_STATS=1
)

# Opt-in sleep mode keeps the container and CUDA context alive while releasing
# model allocations. It is intentionally not enabled globally: llama-swap must
# use its matching vllm-wrapper lifecycle before a model may opt in.
if [[ "${VLLM_SLEEP:-0}" == 1 ]]; then
  VLLM_ENV+=(
    -e VLLM_SERVER_DEV_MODE=1
    -e PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF_SLEEP:-}"
  )
fi

# Exported-by-sourcing arrays are consumed by wrappers, not this file itself.
# shellcheck disable=SC2034
VLLM_ULIMITS=(
  --ulimit memlock=-1
  --ulimit stack=67108864
)

# Every current wrapper binds vLLM itself to 127.0.0.1. Container bridge mode
# cannot forward to a process bound to container loopback, so fail closed rather
# than offering a subtly broken/public networking fallback.
if [[ "${VLLM_HOST_NET:-0}" != 1 ]]; then
  printf 'vLLM wrappers must set VLLM_HOST_NET=1 and bind 127.0.0.1\n' >&2
  return 2
fi
# shellcheck disable=SC2034
VLLM_NET=(--network=host)
