# Out-of-tree vLLM registration for Nanbeige4.2 (NanbeigeForCausalLM).
# Source: vllm-project/vllm PR #49433 (Nanbeige/vllm branch nanbeige42),
# vendored until the PR merges + ships in a release — then DELETE this plugin
# and drop the pip-install line from the vllm-nanbeige wrapper.
def _patch_eagle3_draft_layer_naming():
    # The looped target registers num_loops * num_hidden_layers virtual
    # attention layers (0..43), but vLLM's Eagle3 draft names its layer at
    # start_layer_id = physical num_hidden_layers (22), colliding with the
    # target's loop-2 layer 22 ("Duplicate layer name: model.layers.22...").
    # Bump the draft's naming offset to the virtual depth. start_layer_id is
    # ONLY a KV-registry prefix (layer_types indexing uses layer_idx), so this
    # is a pure rename.
    # Patches the llama_eagle3 draft (EAGLE-3 heads), the qwen3_eagle3 draft
    # (P-EAGLE heads, class Qwen3Eagle3Model), and the qwen3_dflash draft
    # (DFlash, class DFlashQwen3Model) — all three take start_layer_id from the
    # target's PHYSICAL layer count and collide identically.
    #
    # DFlash detail, verified against the v0.26.0 source 2026-07-28: it names
    # layers `layers.{layer_idx + start_layer_id}` but passes `layer_idx=`
    # to DFlashQwen3DecoderLayer EXPLICITLY and resolves layer_types from that
    # LOCAL index, so only the rename below matters for it. The
    # target_layer_count stamp is inert on the DFlash path (it stays because it
    # IS load-bearing for eagle3, whose decoder derives its index as
    # prefix_index - target_layer_count).
    def _wrap(model_cls):
        if getattr(model_cls, "_nanbeige_layer_naming_patch", False):
            return
        _orig_init = model_cls.__init__

        def _patched_init(self, *, vllm_config, start_layer_id=0, prefix=""):
            tgt_hf = vllm_config.model_config.hf_config
            num_loops = getattr(tgt_hf, "num_loops", 1) or 1
            if (
                getattr(tgt_hf, "model_type", "") == "nanbeige"
                and num_loops > 1
                and start_layer_id == tgt_hf.num_hidden_layers
            ):
                start_layer_id = tgt_hf.num_hidden_layers * num_loops
                # vLLM stamped target_layer_count = physical layers (22) on the
                # draft config; the draft decoder indexes layer_types as
                # (prefix_index - target_layer_count), so the stamp must be
                # virtual too (effective index 0 for the draft layer).
                draft_cfg = vllm_config.speculative_config.draft_model_config.hf_config
                draft_cfg.target_layer_count = start_layer_id
            _orig_init(
                self, vllm_config=vllm_config, start_layer_id=start_layer_id,
                prefix=prefix,
            )

        model_cls.__init__ = _patched_init
        model_cls._nanbeige_layer_naming_patch = True

    try:
        from vllm.model_executor.models import llama_eagle3
        _wrap(llama_eagle3.LlamaModel)
    except ImportError:
        pass
    try:
        from vllm.model_executor.models import qwen3_eagle3  # P-EAGLE draft
        _wrap(qwen3_eagle3.Qwen3Eagle3Model)
    except ImportError:
        pass
    try:
        from vllm.model_executor.models import qwen3_dflash  # DFlash draft
        _wrap(qwen3_dflash.DFlashQwen3Model)
    except (ImportError, AttributeError):
        # Absent before v0.26.0 — the eagle3 paths above must still register.
        pass


def register():
    from vllm import ModelRegistry

    _patch_eagle3_draft_layer_naming()
    # 2026-10-06: NO LONGER a no-op on native support. vLLM >= v0.30 lists
    # NanbeigeForCausalLM but serves it through the Transformers backend, which
    # dies on the repo's remote code (KeyError: 'vllm' in NANBEIGE_ATTENTION_CLASSES)
    # on v0.31.0. The vendored class below is the tested path, so always override.
    ModelRegistry.register_model(
        "NanbeigeForCausalLM",
        "nanbeige_vllm_plugin.nanbeige:NanbeigeForCausalLM",
    )
