#!/usr/bin/env bash
#
# run_onchange_after_install-system-tuning.sh
#
# Deploys this machine's custom /etc system-tuning files AS ROOT.
#
# WHY THIS SCRIPT EXISTS — and why these files are NOT kept in the chezmoi
# source tree as managed targets:
#
#   chezmoi operates on $HOME. Files placed under a source subdir such as
#   `root/etc/...` are interpreted as targets under ~/root/etc and NEVER reach
#   the real /etc — they only litter ~/root. The previous setup did exactly
#   that, and the real /etc copies were then deployed ad-hoc as the user,
#   which left /etc, /etc/systemd and /etc/udev owned by `nullsense` and broke
#   pacman's systemd-tmpfiles hook ("unsafe path transition /etc").
#
#   chezmoi's own FAQ ("Can I use chezmoi to manage files outside my home
#   directory?") says the supported way to manage files outside $HOME is a
#   script that runs arbitrary commands. This is that script.
#
# run_onchange_  => chezmoi tracks this file's SHA256 and re-runs it only when
#                  its contents change. Because every managed file is inlined
#                  below, editing any config here triggers redeployment on the
#                  next `chezmoi apply`.
# _after_        => runs after normal target files are applied.
#
# Files are written with `sudo tee` so they are owned root:root by
# construction (no post-hoc chown drift). Requires sudo (interactive apply).
#
# DELIBERATELY EXCLUDED (managed by their proper owners — do not add here):
#   /etc/pam.d/sddm                 -> owned by the `sddm` pacman package
#   /etc/sddm.conf.d/00-omarchy.conf -> deployed/managed by omarchy
#
set -euo pipefail

if ! command -v sudo >/dev/null 2>&1; then
    echo "install-system-tuning: sudo not found; cannot deploy /etc files" >&2
    exit 1
fi

echo ":: Deploying custom /etc system-tuning files (needs sudo)…"

# write_root_file <dest> <mode>  — content on stdin, owned root:root
write_root_file() {
    local dest="$1" mode="$2"
    sudo install -d -o root -g root -m 755 "$(dirname "$dest")"
    sudo tee "$dest" >/dev/null
    sudo chown root:root "$dest"
    sudo chmod "$mode" "$dest"
    echo "   installed $dest ($mode)"
}

write_root_file /etc/systemd/network/00-wol.link 644 <<'WOL_EOF'
# Enable Wake-on-LAN (magic packet) for the wired NIC.
#
# Processed by systemd-udevd at every link-up event — applies on boot AND
# after each resume from suspend. This matters because the r8169 driver
# resets WoL across suspend cycles, so a one-shot `ethtool -s eno1 wol g`
# would silently stop working after the first sleep.
#
# Matched by permanent MAC to survive interface rename, virtual MAC changes
# from systemd-networkd, or NIC slot moves. The MAC was read from
# `ip -br link` on this box (Realtek RTL8125B at 0000:0a:00.0).
#
# Required on the wake side:
#   - This file installed at /etc/systemd/network/00-wol.link
#   - BIOS/UEFI: "Power on by PCIe/PCI" or "Wake on LAN" set to Enabled
#     (board-specific menu name; usually under Power / Advanced)
#   - Router/switch leaves NIC PHY powered when host suspends — automatic
#     on managed switches and almost all home routers
#
# To send the wake packet from the OnePlus 8T homelab node (per the
# project_oneplus_8t_homelab memory), install `etherwake` in Termux:
#   etherwake -i wlan0 60:cf:84:ac:86:d3
# or via Tailscale if the homelab phone is on the tailnet:
#   tailscale ssh user@desktop -- echo dummy   (just need any wake-up trigger)
# Real wake protocols vary; magic packet works at L2 only — needs L2
# bridging via the home router or wol-relay otherwise.

[Match]
PermanentMACAddress=60:cf:84:ac:86:d3

[Link]
WakeOnLan=magic
WOL_EOF

write_root_file /etc/systemd/sleep.conf.d/00-msi-ddc-safe.conf 644 <<'SLEEP_EOF'
# Drop-in: force deep (S3) suspend and disable every hibernate-adjacent mode.
#
# Why MemorySleepMode=deep on this box:
#   Kernel cmdline carries `amdgpu.runpm=0` and `pcie_aspm=off` (stability
#   workarounds for this AMDGPU + display setup). Combined with the default
#   s2idle "freeze" mode, enough of the DP link stays trained on the MSI
#   MAG274QRF-QD that its DDC controller half-wakes on the next idle cycle
#   and starts dropping `setvcp 10` writes from hypridle. Deep sleep cleanly
#   parks the link, so the DDC controller observes one well-formed
#   power-cycle on wake and behaves.
#
#   On firmware that doesn't expose S3, the kernel will fall back to s2idle
#   automatically — setting `deep` is therefore safe to set unconditionally.
#
# Why disable hibernate paths:
#   Belt-and-suspenders with logind.conf.d/00-suspend-only.conf. Even if a
#   stray script invokes `systemctl hibernate` directly, refuse it rather
#   than silently producing a broken state.

[Sleep]
MemorySleepMode=deep
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
SLEEP_EOF

write_root_file /etc/systemd/logind.conf.d/00-suspend-only.conf 644 <<'LOGIND_EOF'
# Drop-in: scope `systemctl suspend` and the keyboard suspend key to plain
# suspend-to-RAM. Default in systemd 256+ is `suspend-then-hibernate suspend`,
# which silently tries to hibernate after HibernateDelaySec (≈60 min on AC).
#
# This box is NOT configured for hibernate:
#   - no `resume=` kernel parameter on the kernel cmdline
#   - no `resume_offset=` for the btrfs swapfile
#   - no `resume` hook in mkinitcpio.conf HOOKS
#   - swapfile is 12 GB but RAM is 60 GB — too small
#
# So the hibernate attempt fails (or saves-to-disk-then-cold-boot depending
# on kernel) and you lose your session. Override to plain `suspend` until
# proper hibernate is wired up.

[Login]
SleepOperation=suspend
LOGIND_EOF

write_root_file /etc/systemd/system-sleep/10-unload-llm-vram 755 <<'SLEEPHOOK_EOF'
#!/bin/bash
# Pre-suspend hook: empty GPU VRAM before the kernel enters S3 deep sleep.
#
# Why: On AMDGPU, suspend-to-RAM does not always evict VRAM correctly. With
# models loaded (LM Studio, llama-server, comfyui, etc.) at suspend time you
# get one of two failure modes:
#   1. The S3 save area has to copy VRAM contents into system RAM. If VRAM
#      usage exceeds free system RAM, the suspend itself OOMs and the box
#      either refuses to suspend or wakes up with a kernel ring reset.
#   2. The GPU command ring is left in a partially-running state across the
#      sleep ramp; on resume you get GPU resets in dmesg, hangs in the
#      compositor, or amdgpu's "ring gfx_0.0.0 timeout" cascade.
#
# This script unloads everything that holds VRAM before the kernel reaches
# the suspend ramp. LM Studio is unloaded gracefully via its CLI (`lms
# unload --all`) — keeps the LM Studio server process alive so the next
# request reloads cleanly. Other engines (llama-server, ollama, vllm,
# comfyui) get SIGTERM; they're typically launched per-task and re-spawned
# on demand, no graceful unload needed.
#
# Runs as root with no user env. The lms CLI lives in $USER_HOME/.lmstudio/bin
# so we re-enter the user account with `runuser` + a login shell to pull the
# normal PATH. A 5s `timeout` wrapper prevents a hung lms from blocking suspend.
#
# Args (systemd-suspend(8)):
#   $1 = pre | post
#   $2 = suspend | hibernate | hybrid-sleep | suspend-then-hibernate
#
# Filename starts with `10-` so it sorts before any future hooks and runs
# early in the pre-suspend phase. Sleep hooks live in /etc/systemd/system-sleep/
# (admin-managed) — the /usr/lib/systemd/system-sleep/ tree is for vendor
# packages and would get clobbered by package updates.

set -u

USER_NAME=nullsense

case "$1" in
    pre)
        # LM Studio: graceful unload via the official CLI. Keeps the server
        # process so MCP/handoff clients (hyprwhspr-lms-handoff, etc.) don't
        # see a connection drop — just an empty VRAM until next request.
        timeout 5 runuser -u "$USER_NAME" -- bash -lc 'lms unload --all' \
            >/dev/null 2>&1 || true

        # Standalone llama.cpp processes. `pkill <name>` matches the comm
        # field (15-char limit), which catches both llama-server and
        # llama-cli regardless of full path.
        pkill --signal TERM llama-server  >/dev/null 2>&1 || true
        pkill --signal TERM llama-cli     >/dev/null 2>&1 || true

        # Other inference engines that hold VRAM. `-f` matches the full
        # command line because these processes have non-distinctive comm
        # fields ("python3", "node", etc.).
        pkill --signal TERM -f 'ollama serve' >/dev/null 2>&1 || true
        pkill --signal TERM -f 'vllm.*serve'  >/dev/null 2>&1 || true
        pkill --signal TERM -f 'comfyui'      >/dev/null 2>&1 || true

        # Give amdgpu ~1s to release VRAM allocations before the kernel
        # starts the suspend ramp. Without this we sometimes start the
        # ramp while the IOMMU still has unmapped pages pending.
        sleep 1
        ;;
esac

exit 0
SLEEPHOOK_EOF

write_root_file /etc/udev/rules.d/60-ioschedulers.rules 644 <<'UDEV_EOF'
# Set I/O scheduler for NVMe and SSD drives
# 'none' scheduler is best for NVMe drives
# 'mq-deadline' or 'bfq' is good for SATA SSDs

# NVMe drives
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"

# SATA SSDs (assumed to be sd[a-z] on modern systems)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDDs (traditional spinning disks)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
UDEV_EOF

# Re-apply the rules/links that can take effect live.
echo ":: Reloading udev (I/O schedulers + WoL link)…"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=block --action=change >/dev/null 2>&1 || true
sudo udevadm trigger --subsystem-match=net   --action=change >/dev/null 2>&1 || true

# logind/sleep drop-ins are read at login / suspend time respectively — no safe
# live reload (restarting systemd-logind can disrupt the session). They take
# effect on next login / next suspend. The system-sleep hook is active as soon
# as it is in place.
echo ":: Done. logind/sleep settings apply on next login/suspend."
