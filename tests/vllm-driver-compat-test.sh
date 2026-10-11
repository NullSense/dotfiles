#!/usr/bin/env bash
# Recurring invocation: README.md's tests/*.sh regression interface.
set -euo pipefail
export VLLM_HOST_NET=1
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
loaded=$(sed -nE 's/^NVRM version:.* ([0-9]+\.[0-9]+\.[0-9]+) .*$/\1/p' /proc/driver/nvidia/version 2>/dev/null || true)

# No snapshot keeps Docker's normal GPU admission.
PORT=8014 VLLM_CACHE_ROOT_HOST="$scratch/cache" VLLM_HF_CACHE_MODE=none \
  bash -c 'source "$1"; [[ "${VLLM_GPU_ARGS[*]}" == "--gpus all" ]]' _ \
  "$root/home/bin/llm-servers/_vllm-common.sh"

if [[ -n "$loaded" ]]; then
  mkdir -p "$scratch/driver"
  for lib in libcuda libnvidia-ml libnvidia-ptxjitcompiler libnvidia-gpucomp; do
    touch "$scratch/driver/$lib.so.$loaded"
  done
  PORT=8014 VLLM_CACHE_ROOT_HOST="$scratch/cache" VLLM_HF_CACHE_MODE=none \
    VLLM_DRIVER_COMPAT_ROOT="$scratch/driver" bash -c '
      source "$1"
      [[ "${VLLM_GPU_ARGS[*]}" == *"--runtime=runc"* ]]
      [[ "${VLLM_GPU_ARGS[*]}" != *"--gpus"* ]]
      [[ "${VLLM_MOUNTS[*]}" == *"/usr/local/nvidia/lib64:ro"* ]]
      [[ "${VLLM_ENV[*]}" == *"NVIDIA_VISIBLE_DEVICES=void"* ]]
    ' _ "$root/home/bin/llm-servers/_vllm-common.sh"
  rm -- "$scratch/driver/libcuda.so.$loaded"
  if PORT=8014 VLLM_CACHE_ROOT_HOST="$scratch/cache" VLLM_HF_CACHE_MODE=none \
    VLLM_DRIVER_COMPAT_ROOT="$scratch/driver" bash -c 'source "$1"' _ \
    "$root/home/bin/llm-servers/_vllm-common.sh"; then
    echo 'FAIL: incomplete driver snapshot admitted' >&2
    exit 1
  fi
fi
echo 'PASS: normal GPU admission and retained-driver compute fallback'
