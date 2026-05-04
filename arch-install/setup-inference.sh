#!/bin/bash
# Local AI inference on RX 6750 XT (gfx1031, RDNA2).
#
# Strategy: Vulkan-first because gfx1031 isn't officially in ROCm.
#   - llama.cpp Vulkan: native, fast, "just works" (LLM chat / code)
#   - ComfyUI:           ROCm Docker container (image gen). Containerizing
#                        isolates the gfx1031-override hacks from the host.
#
# Run AFTER post-install.sh and hardware-optimize.sh.

set -euo pipefail

echo "=== AI Inference Setup (RX 6750 XT, Vulkan-first) ==="
echo

# ============================================================================
# 1. Group memberships for /dev/kfd and /dev/dri access (ROCm/Vulkan compute)
# ============================================================================
echo "[1/4] Adding $USER to render + video groups..."
sudo usermod -aG render,video "$USER"
echo "   (re-login required for groups to take effect)"

# ============================================================================
# 2. llama.cpp with Vulkan backend (fast, native, no ROCm)
# ============================================================================
echo
echo "[2/4] Installing llama.cpp (Vulkan)..."
# llama.cpp lands in extra; if not, fall back to AUR build with Vulkan flag.
if pacman -Si llama.cpp-vulkan &>/dev/null; then
  sudo pacman -S --noconfirm --needed llama.cpp-vulkan
elif pacman -Si llama.cpp &>/dev/null; then
  sudo pacman -S --noconfirm --needed llama.cpp
else
  paru -S --noconfirm --needed llama.cpp-vulkan-git
fi

# Sanity-test Vulkan device visibility
echo "Vulkan devices visible to llama.cpp:"
vulkaninfo --summary | grep -E "deviceName|driverName" | head -10

# Make a models dir
mkdir -p ~/llm/models

cat > ~/llm/run-llama.sh <<'RUN'
#!/bin/bash
# Quick launcher for llama.cpp Vulkan server.
# Usage:   ./run-llama.sh <model.gguf> [extra-flags]
# Model defaults to a Qwen2.5 7B Q4_K_M if you put one in ~/llm/models/.
MODEL="${1:-$HOME/llm/models/qwen2.5-7b-instruct-q4_k_m.gguf}"
shift || true
exec llama-server \
  --model "$MODEL" \
  --host 127.0.0.1 --port 8080 \
  --n-gpu-layers 999 \
  --ctx-size 16384 \
  --flash-attn \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  "$@"
RUN
chmod +x ~/llm/run-llama.sh
echo "Launcher: ~/llm/run-llama.sh"
echo "Drop GGUF models into ~/llm/models/ — get them from huggingface.co/unsloth or huggingface.co/bartowski"

# ============================================================================
# 3. ComfyUI via the official rocm/pytorch Docker image
# ============================================================================
echo
echo "[3/4] Setting up ComfyUI (ROCm Docker, gfx1030 override for gfx1031)..."
mkdir -p ~/comfyui/{models,output,custom_nodes,workflows}

cat > ~/comfyui/docker-compose.yml <<'COMPOSE'
services:
  comfyui:
    # Pinned tag — ":latest" silently rolls and can break ROCm/PyTorch ABI mid-update.
    # Bump deliberately after testing. Verify pull with `docker pull` and `docker inspect | jq .RepoDigests`.
    image: rocm/pytorch:rocm6.4_ubuntu24.04_py3.12_pytorch_release_2.7.0
    container_name: comfyui
    restart: unless-stopped
    # Bind ONLY to loopback. Use Tailscale serve / SSH port-forward to expose to your tailnet.
    ports:
      - "127.0.0.1:8188:8188"
    ipc: host                              # PyTorch DataLoader needs this
    cap_add: [SYS_PTRACE]
    security_opt: [seccomp=unconfined]
    group_add: ["video", "render"]
    devices:
      - /dev/kfd
      - /dev/dri
    environment:
      - HSA_OVERRIDE_GFX_VERSION=10.3.0    # gfx1031 → present as gfx1030
      - PYTORCH_HIP_ALLOC_CONF=expandable_segments:True
      - HIP_VISIBLE_DEVICES=0
    volumes:
      - ./models:/workspace/ComfyUI/models
      - ./output:/workspace/ComfyUI/output
      - ./custom_nodes:/workspace/ComfyUI/custom_nodes
      - ./workflows:/workspace/ComfyUI/user/default/workflows
    working_dir: /workspace
    # ComfyUI listens on 0.0.0.0 INSIDE the container; Docker's port mapping above
    # constrains exposure to 127.0.0.1 on the host. Safe.
    command: >
      bash -c '
        if [ ! -d ComfyUI ]; then
          git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
        fi
        cd ComfyUI &&
        pip install -q --no-cache-dir -r requirements.txt &&
        python main.py --listen 0.0.0.0 --port 8188
      '
COMPOSE

echo "ComfyUI compose written: ~/comfyui/docker-compose.yml"
echo "First start (downloads ~15GB image, ~5min):"
echo "  cd ~/comfyui && docker compose up -d && docker compose logs -f"
echo "Then open http://localhost:8188"
echo
echo "Drop SD/Flux checkpoints into:  ~/comfyui/models/checkpoints/"

# ============================================================================
# 4. Optional: ollama if you prefer it over raw llama.cpp
# ============================================================================
echo
echo "[4/4] (Optional) Ollama with Vulkan backend..."
echo "If you prefer ollama's UX over llama-server:"
echo "  paru -S ollama"
echo "  sudo systemctl edit ollama   # add: Environment=OLLAMA_VULKAN=1"
echo "  sudo systemctl enable --now ollama"
echo "  ollama run qwen2.5:7b"

echo
echo "=== Done. Re-login (for render/video groups), then test. ==="
