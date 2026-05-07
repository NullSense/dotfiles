#!/bin/bash
# Post-install setup for fresh Arch — runs ONCE after first boot as user.
# Pre-req: archinstall completed, you're logged in, internet is up.
set -euo pipefail

echo "=== [1/11] (pacman config + service enables already handled by archinstall custom_commands) ==="

echo "=== [2/11] zram (16GB compressed, single source of truth) ==="
sudo tee /etc/systemd/zram-generator.conf > /dev/null <<'ZRAM'
[zram0]
zram-size = ram / 4
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAM
sudo systemctl daemon-reexec
sudo systemctl start systemd-zram-setup@zram0.service || true

# Sysctl tuned for zram (high swappiness preferred for compressed swap)
sudo tee /etc/sysctl.d/99-zram.conf > /dev/null <<'SYSCTL'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
SYSCTL
sudo sysctl --system

echo "=== [3/11] btrfs swapfile on @swap (12GB, low priority — overflow only) ==="
# @swap subvolume is excluded from snapper snapshots (swap can't be snapshotted).
# `btrfs filesystem mkswapfile` (btrfs-progs >=6.1) atomically does:
#   - chattr +C (NODATACOW, mandatory for btrfs swapfiles)
#   - fallocate (preallocated, no holes — also mandatory)
#   - mkswap
# Priority 10 < zram priority 100, so zram fills first and the disk swapfile
# is overflow only. With 64GB RAM + 16GB zram, 12GB on-disk is plenty.
if ! swapon --show | grep -q '/swap/swapfile'; then
  sudo btrfs filesystem mkswapfile --size 12g --uuid clear /swap/swapfile
  sudo swapon --priority 10 /swap/swapfile
  if ! grep -q '/swap/swapfile' /etc/fstab; then
    echo '/swap/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab
  fi
fi
swapon --show

echo "=== [4/11] systemd timers (snapper, plocate, man-db, pkgfile, btrfs-balance) ==="
for t in man-db.timer plocate-updatedb.timer logrotate.timer \
         snapper-timeline.timer snapper-cleanup.timer pkgfile-update.timer; do
  sudo systemctl enable --now "$t" || true
done
# Activate already-enabled services
sudo systemctl start fstrim.timer paccache.timer reflector.timer fwupd-refresh.timer || true

# Tighten snapper retention (defaults keep way too many snapshots)
sudo sed -i \
  -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
  -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
  -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' \
  -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' \
  -e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' \
  -e 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="20"/' \
  /etc/snapper/configs/root || true

# Weekly btrfs balance (reclaims fragmented metadata blocks)
sudo tee /etc/systemd/system/btrfs-balance.service > /dev/null <<'BBS'
[Unit]
Description=Weekly btrfs balance (light)
[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/bin/btrfs balance start -dusage=50 -musage=70 /
BBS
sudo tee /etc/systemd/system/btrfs-balance.timer > /dev/null <<'BBT'
[Unit]
Description=Weekly btrfs balance
[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h
[Install]
WantedBy=timers.target
BBT
sudo systemctl daemon-reload
sudo systemctl enable --now btrfs-balance.timer

# reflector config (Germany / Netherlands / France)
sudo mkdir -p /etc/xdg/reflector
sudo tee /etc/xdg/reflector/reflector.conf > /dev/null <<'REF'
--save /etc/pacman.d/mirrorlist
--country Germany,Netherlands,France
--protocol https
--latest 12
--age 24
--sort rate
REF

echo "=== [5/11] activate pre-enabled services + power-profiles-daemon ==="
sudo systemctl start bluetooth NetworkManager || true
sudo systemctl enable --now power-profiles-daemon.service

echo "=== [6/11] paru (AUR helper) ==="
if ! command -v paru &>/dev/null; then
  git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
  (cd /tmp/paru-bin && makepkg -si --noconfirm)
  rm -rf /tmp/paru-bin
fi
# Auto-clean AUR build dirs after every build (saves GBs over time)
sudo sed -i 's/^#CleanAfter/CleanAfter/' /etc/paru.conf
sudo sed -i 's/^#RemoveMake/RemoveMake/' /etc/paru.conf

echo "=== [7/11] AUR packages (genuinely AUR-only: fonts, browser, launcher, jellyfin client, infisical) ==="
# ghostty/swappy/rbw/rofi-rbw/sway-contrib moved to official packages list (extra repo).
# zen-browser-bin: AUR, 297 votes, popularity 19.86, not out-of-date — actively maintained Firefox fork.
paru -S --noconfirm --needed \
  ttf-maple-mono-nf \
  zen-browser-bin \
  sway-launcher-desktop \
  jellyfin-media-player \
  infisical-bin \
  xpadneo-dkms-git

echo "=== [7c/11] Boot-order self-heal (resists Windows update boot hijacks) ==="
# Windows feature/security updates often re-prioritize 'Windows Boot Manager'
# at position 0 in UEFI BootOrder. Without intervention you'd press F8 at
# every POST forever. This systemd oneshot runs at boot, checks if
# 'Linux Boot Manager' is first, and if not, swaps it to first via
# efibootmgr. Idempotent: silent and no-op when already correct.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo install -m 755 "$SCRIPT_DIR/assert-boot-priority.sh" /usr/local/bin/assert-boot-priority
sudo install -m 644 "$SCRIPT_DIR/assert-boot-priority.service" /etc/systemd/system/assert-boot-priority.service
sudo systemctl daemon-reload
sudo systemctl enable assert-boot-priority.service
# Run once now so the order is correct before next boot
sudo /usr/local/bin/assert-boot-priority || true

echo "=== [8/11] mise as unified runtime/tool manager ==="
# mise (installed via pacman in user_configuration.json) manages:
#   - node, bun, python, rust toolchains (per-project via .mise.toml)
#   - cargo: tools (sccache, cargo-nextest, cargo-binstall) — fast via binstall
#   - npm: tools (oxlint, pnpm, etc) globally without polluting projects
# uv (Python) installed separately for speed — uv complements mise (mise calls uv under the hood for python).
command -v mise >/dev/null || sudo pacman -S --noconfirm mise
mkdir -p ~/.config/mise
cat > ~/.config/mise/config.toml <<'MISE'
# Global tool versions. Per-project overrides go in <project>/.mise.toml.
[tools]
node = "lts"
python = "3.12"
bun = "latest"
rust = "latest"
"cargo:cargo-binstall" = "latest"
"cargo:cargo-nextest" = "latest"
"cargo:cargo-watch"    = "latest"
"cargo:cargo-edit"     = "latest"
"npm:pnpm"   = "latest"
"npm:oxlint" = "latest"

[settings]
experimental = true
# Use cargo-binstall for cargo: tools (huge speedup, no source builds)
cargo.binstall = true
# Use bun for npm: tools (faster than npm)
npm.bun = true

[env]
# sccache wraps rustc to cache compiled crates across projects
RUSTC_WRAPPER = "sccache"
SCCACHE_DIR = "{{env.HOME}}/.cache/sccache"
SCCACHE_CACHE_SIZE = "20G"
MISE
mise install
mise reshim || true

# Standalone uv (Astral's Python installer, faster than pip — mise integrates it)
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

echo "=== [9/11] zinit (zsh plugin manager) ==="
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

echo "=== [10/11] chezmoi pull dotfiles ==="
if ! command -v chezmoi &>/dev/null; then sudo pacman -S --noconfirm chezmoi; fi
chezmoi init --apply https://github.com/NullSense/dotfiles.git

echo "=== [10.1/11] Helium browser (Chromium-based, AppImage with weekly auto-update) ==="
# Helium has no built-in updater. The helium-update script deployed by chezmoi
# queries GitHub releases and atomically replaces the AppImage when a new tag appears.
if [[ -x "$HOME/bin/helium-update" ]]; then
  "$HOME/bin/helium-update"
  systemctl --user daemon-reload || true
  systemctl --user enable --now helium-update.timer || true
else
  echo "  helium-update missing after chezmoi apply; skipping Helium install"
fi

echo "=== [10.5/11] global git commit-msg hook to strip ALL AI attribution ==="
# Belt-and-suspenders: even if Claude/Codex/OpenCode misbehave and add
# Co-Authored-By: <bot> trailers despite settings, this hook strips them
# from every commit (yours and AI-driven). Works regardless of which agent.
mkdir -p ~/.git-hooks
cat > ~/.git-hooks/commit-msg <<'HOOK'
#!/bin/bash
# Strip AI bot attribution lines from commit messages.
sed -i \
  -e '/^Co-Authored-By:.*\(Claude\|claude\|Codex\|codex\|OpenCode\|opencode\|Cursor\|cursor\|Copilot\|copilot\|Aider\|aider\|GitHub Copilot\)/Id' \
  -e '/^[[:space:]]*🤖 Generated with/d' \
  -e '/^[[:space:]]*Generated with Claude Code/d' \
  -e '/^[[:space:]]*Generated with opencode/Id' \
  "$1"
# Collapse trailing blank lines.
sed -i -e :a -e '/^\s*$/{$d;N;ba' -e '}' "$1"
HOOK
chmod +x ~/.git-hooks/commit-msg
git config --global core.hooksPath ~/.git-hooks

echo "=== [11/11] docker group + default shell + udiskie + ssh-agent ==="
sudo usermod -aG docker "$USER" || true
sudo systemctl start docker.service || true
[[ "$SHELL" != */zsh ]] && chsh -s /usr/bin/zsh "$USER"

# i2c group for ddcutil (real hardware brightness via DDC/CI)
sudo usermod -aG i2c "$USER" || true

# DDC brightness helper scripts (referenced by sway-display-config.txt swayidle stages)
mkdir -p ~/.local/bin
cat > ~/.local/bin/dim-monitors <<'DIM'
#!/bin/bash
# Save current DDC brightness per monitor to /tmp, then dim to 30%.
# Called by swayidle on inactivity.
set -u
for d in 1 2; do
  cur=$(ddcutil --display "$d" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+' || true)
  [[ -n "$cur" ]] && echo "$cur" > "/tmp/brightness-display-$d"
  ddcutil --display "$d" setvcp 10 30 2>/dev/null || true
done
DIM
cat > ~/.local/bin/restore-monitors <<'RESTORE'
#!/bin/bash
# Restore DDC brightness from /tmp snapshots (default 80 if absent).
set -u
for d in 1 2; do
  b=$(cat "/tmp/brightness-display-$d" 2>/dev/null || echo 80)
  ddcutil --display "$d" setvcp 10 "$b" 2>/dev/null || true
done
RESTORE
chmod +x ~/.local/bin/dim-monitors ~/.local/bin/restore-monitors
# Sanity test — should list both monitors after re-login + udev reload:
#   ddcutil detect

# udiskie — auto-mount USB drives (no tray; mako shows mount notifications)
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/udiskie.service <<'UDS'
[Unit]
Description=Automounter for removable media
PartOf=graphical-session.target
[Service]
ExecStart=/usr/bin/udiskie --no-tray --notify --automount --file-manager thunar
Restart=on-failure
[Install]
WantedBy=graphical-session.target
UDS
systemctl --user daemon-reload
systemctl --user enable udiskie.service

# SSH agent: Bitwarden Desktop is the agent (~/.bitwarden-ssh-agent.sock).
# We do NOT enable systemd-user ssh-agent — Bitwarden replaces it.
# Make sure SSH_AUTH_SOCK is set in the user's shell env (handled by dotfiles):
#   export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
systemctl --user disable --now ssh-agent.service 2>/dev/null || true

echo
echo "=== DONE — reboot, then run hardware-optimize.sh, then populate ~/.secrets per dotfiles/SECRETS.md ==="
