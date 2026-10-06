# _vllm-image.sh — THE central vLLM image pins. Source this from wrappers and use:
#   source "$(dirname "$(readlink -f "$0")")/_vllm-image.sh"
#   IMAGE="${VLLM_IMAGE:-$VLLM_IMAGE_PIN}"        # leading tier (default)
#   IMAGE="${VLLM_IMAGE:-$VLLM_IMAGE_PIN_HELD}"   # held tier (a model is broken upstream)
#
# TWO TIERS, one file. `vllm-update` bumps ONLY this file (pull → smoke test each
# wrapper on the pin it actually uses → sed → rollback on failure).
#
#   VLLM_IMAGE_PIN       leading edge. Wrappers here take upstream fixes as they land.
#   VLLM_IMAGE_PIN_HELD  last version where the held wrappers actually boot. Every
#                        `vllm-update` run RE-TESTS these against latest and tells you
#                        when they can rejoin the leading tier, so the hold is a
#                        temporary quarantine and not a pin that silently rots.
#
# Why two tiers instead of one: on 2026-08-15 a single lockstep pin forced an
# all-or-nothing choice — v0.27.1 works for the pooling models and breaks both
# generative ones, so "hold everything at v0.26.0" was denying the embedder and
# reranker upstream fixes to protect two unrelated models. Splitting is not drift;
# the drift case is a wrapper carrying its OWN literal pin (vllm-diffusiongemma
# @ v0.24.0), which nothing re-tests. Prefer a tier over a literal.
#
# ⚠ Floor: >= v0.25.0 — the Nemotron NVFP4 checkpoint family is broken on v0.23.x/0.24.x.
VLLM_IMAGE_PIN="vllm/vllm-openai:v0.31.0"   # 2026-10-06 (was v0.29.0; rollback = restore _vllm-image.sh.bak-20261006)

# HELD at v0.26.0 for vllm-gemma4b (dies at architecture inspection on v0.27.1,
# before any memory is allocated — not a GPU_UTIL artefact, measured by booting on
# both images at wrapper defaults):
#   gemma4b   ValueError: 'head_dim' is a per-layer attribute and may vary across layers
# Reads as fallout from v0.27's PyTorch 2.13 / transformers bump. Drop this pin and
# move the wrapper back to VLLM_IMAGE_PIN once `vllm-update` reports it passing on latest.
#
# ⚠ CORRECTED 2026-09-12: this comment used to also list vllm-nanbeige as held here,
# alongside gemma4b. That was stale — `grep IMAGE= ~/bin/llm-servers/vllm-nanbeige`
# shows it actually sources `${VLLM_IMAGE:-$VLLM_IMAGE_PIN}` (leading), not HELD, and
# `docker ps` / `vllm-update`'s own classification confirm it has been running on the
# LEADING pin (v0.29.0) the whole time. Nothing in this file's history explains when
# nanbeige moved tiers — the wrapper was fixed (or never actually broken the way this
# comment claimed) without this note being updated. Lesson repeated from the Warm
# Path doctrine: a comment is not evidence of what a wrapper does — `grep` the
# wrapper or ask `vllm-update` (no --apply; it only queries Docker Hub + classifies
# local wrappers, it does not pull or mutate anything in that mode).
#
# ⚠ NO v0.26.0 IMAGE IS ON DISK as of 2026-09-12 (a 10 GB pull was deliberately
# cancelled). vllm-gemma4b is therefore the ONLY wrapper still reading this pin, and
# the next time anything requests it — a manual boot, a `vllm-update` held-tier
# retest, or llama-swap routing a live request — it will try to pull the full image
# inside whatever health-check window is watching it and can time out exactly like
# glm-ocr did below before this fix (5m timeout, 381s to a 500, and an unrelated
# healthy model evicted to make room for a pull that was never going to finish in
# time). Pull `vllm/vllm-openai:v0.26.0` deliberately (~10 GB) before touching
# gemma4b, or accept that it is currently unbootable.
#
# vllm-glm-ocr was ALSO held here from 2026-08-15 to 2026-09-12, for a DIFFERENT
# reason than gemma4b: it did NOT fail architecture inspection — it booted into
# KV-cache sizing and failed there on v0.27.1's default GPU_UTIL=0.15:
#   ValueError: To serve at least one request with the model's max seq len (16384),
#   (1.0 GiB KV cache is needed, which is larger than the available KV cache memory
#   (0.59 GiB)...
# v0.27.1's fixed per-process overhead (weights+activation+CUDA-graph) was larger
# than v0.26.0's at the SAME gpu_memory_utilization fraction, so the 0.15×32GB≈4.8GB
# budget that fit v0.26.0 comfortably no longer left room for a 16384-token KV pool.
# This was a GPU_UTIL artefact, not a hard incompatibility — RAISING GPU_UTIL was
# always the fix, never shrinking MAXLEN (an earlier note here suggested dropping
# the 16384 context as the cheaper option; that was wrong — legalkb/the Documents
# OCR cascade pushes many-page documents through this cascade, so the context is
# sized to the real workload and cutting it would silently truncate long documents
# rather than free budget).
#
# RESOLVED 2026-09-12: measured on v0.29.0 (two minors past the v0.27.1 error above,
# on-disk, no pull needed), booting the real wrapper standalone at PORT=8011 and
# incrementing GPU_UTIL by hand:
#   0.15  Available KV cache memory: -0.13 GiB   → fails (same class as v0.27.1)
#   0.16  Available KV cache memory:  0.72 GiB   → fails: "1.0 GiB KV cache is
#         needed... available (0.72 GiB)" — the ORIGINAL v0.27.1 error text, verbatim,
#         reproduced on v0.29.0 at this util
#   0.17  Available KV cache memory:  1.02 GiB   → boots; 16,656-token KV pool,
#         "Maximum concurrency for 16,384 tokens per request: 1.02x" — only ~272
#         tokens of margin above the single-request floor, too thin to trust
#   0.18  Available KV cache memory:  1.34 GiB   → boots; 21,872-token KV pool, 1.33x
#         concurrency, "Desired GPU memory utilization is (0.18, 5.66 GiB)" — LANDED
#         HERE: real margin above the floor, and it matches paddleocr-vl's existing
#         0.18 (same reservation convention across both cascade engines, easy to
#         remember, see config.yaml's `ocr` matrix set)
# Verified past boot: a real page image (rendered from a live Documents-vault PDF
# via pymupdf) sent to POST /v1/chat/completions with the model-card prompt
# "Text Recognition:" returned 200 with plausible, accurate German OCR text (a
# comdirect letter body) — not the "!!!!..." degenerate output documented elsewhere
# in config.yaml for a broken serving path (see the `mineru` entry).
# glm-ocr now sources VLLM_IMAGE_PIN (leading tier) at GPU_UTIL default 0.18 — see
# the wrapper itself. `vllm-update` (check mode, no --apply) confirms Docker Hub's
# current latest IS v0.29.0, so the leading pin is not behind anything newer either.
VLLM_IMAGE_PIN_HELD="vllm/vllm-openai:v0.26.0"
