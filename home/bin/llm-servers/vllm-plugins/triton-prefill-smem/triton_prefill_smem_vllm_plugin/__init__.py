# Clamp vLLM's Triton prefill-attention tile to fit consumer-Blackwell shared memory.
#
# vllm/v1/attention/ops/triton_prefill_attention.py picks BLOCK_M = BLOCK_N = 128 on
# every CUDA device with capability >= 8.0 and only narrows for head_dim >= 512. That
# tile assumes datacenter shared memory (A100/H100/B200: 164-228 KiB per block). The
# RTX 5090 (SM120) has 99 KiB (101376 B), so EmbeddingGemma 2's head_dim-256 sliding
# layers fail at the first encoder-only forward:
#   triton.runtime.errors.OutOfResources: out of resource: shared memory,
#   Required: 163840, Hardware limit: 101376.
# Measured 2026-10-09 on nightly 8cbd5d03 (vllm 0.31.1rc1.dev173). The kernel's tile
# size changes only how keys are blocked for the online softmax, not what is computed;
# the parity gate in vllm-embeddinggemma2 is what proves the vectors.
#
# Lazy by design: the device query runs inside the first kernel launch (worker
# process, CUDA already initialised), never at plugin load in the API server.
# DELETE this plugin once upstream sizes the tile from the device's shared memory.
import logging

logger = logging.getLogger(__name__)

# BLOCK=128 at head_dim 256 needs 160 KiB; BLOCK=64 halves the K/V/Q tiles.
_NEEDS_FOR_WIDE_TILE = 163840
_NARROW_BLOCK = 64


def register() -> None:
    from vllm.v1.attention.ops import triton_prefill_attention as tpa

    if getattr(tpa, "_smem_clamp_patched", False):
        return
    original = tpa.get_block_size
    limit: list[int] = []

    def get_block_size(dtype):
        block = original(dtype)
        if block <= _NARROW_BLOCK:
            return block
        if not limit:
            import torch

            props = torch.cuda.get_device_properties(torch.cuda.current_device())
            limit.append(int(props.shared_memory_per_block_optin))
            if limit[0] < _NEEDS_FOR_WIDE_TILE:
                logger.warning(
                    "triton_prefill_smem: device shared memory %d B < %d B; "
                    "clamping Triton prefill BLOCK %d -> %d",
                    limit[0], _NEEDS_FOR_WIDE_TILE, block, _NARROW_BLOCK,
                )
        return _NARROW_BLOCK if limit[0] < _NEEDS_FOR_WIDE_TILE else block

    tpa.get_block_size = get_block_size
    tpa._smem_clamp_patched = True
