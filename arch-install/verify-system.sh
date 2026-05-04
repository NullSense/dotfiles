#!/bin/bash
# Post-install system verification — walks the BIOS/firmware/driver/audio/wifi/bt
# checklist and tells you what's good and what still needs fixing.
# Read-only; safe to run any time.

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}    $1"; }
warn() { echo -e "${YELLOW}WARN${NC}  $1"; }
fail() { echo -e "${RED}FAIL${NC}  $1"; }
info() { echo -e "      $1"; }

echo "=== System Verification ==="
echo

# Detect WSL early — half the checks are meaningless under WSL
if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
  echo -e "${YELLOW}NOTE${NC}: This is WSL. Most hardware checks below will be empty or wrong"
  echo "      (no UEFI, no GPU PCI, no audio stack, no BT, virtual disks)."
  echo "      Run this script on the Arch live USB or on the installed system."
  echo
fi


# ---- BIOS / motherboard / AGESA ----
echo "── BIOS / firmware ──"
MOBO=$(sudo dmidecode -s baseboard-product-name 2>/dev/null || echo unknown)
BIOS_VER=$(sudo dmidecode -s bios-version 2>/dev/null || echo unknown)
BIOS_DATE=$(sudo dmidecode -s bios-release-date 2>/dev/null || echo unknown)
info "Motherboard:   $MOBO"
info "BIOS version:  $BIOS_VER ($BIOS_DATE)"
info "Compare against your motherboard vendor's latest BIOS download page."
info "Look for AGESA 1.2.0.2 or newer (Zen 5 stability + 105W TDP for 9700X)."
AGESA=$(sudo dmesg 2>/dev/null | grep -i agesa | head -1 || true)
[[ -n "$AGESA" ]] && info "dmesg AGESA: $AGESA"
echo

# ---- UEFI / Secure Boot ----
echo "── UEFI / Secure Boot ──"
if [[ -d /sys/firmware/efi ]]; then ok "Booted in UEFI mode"; else fail "Not booted in UEFI mode"; fi
if command -v sbctl &>/dev/null; then
  SB_STATUS=$(sudo sbctl status 2>/dev/null || true)
  if grep -q "Secure Boot:.*Enabled" <<<"$SB_STATUS"; then
    ok "Secure Boot is ENABLED"
  elif grep -q "Setup Mode:.*Enabled" <<<"$SB_STATUS"; then
    warn "Secure Boot is in Setup Mode — run setup-secure-boot.sh"
  else
    warn "Secure Boot is disabled (run setup-secure-boot.sh to enable)"
  fi
fi
echo

# ---- CPU / amd-pstate ----
echo "── CPU (Ryzen 9700X) ──"
DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo none)
if [[ "$DRIVER" =~ amd-pstate ]]; then ok "scaling_driver: $DRIVER"; else warn "scaling_driver: $DRIVER (expected amd-pstate-epp)"; fi
info "CPU model: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
info "Cores online: $(nproc)"
echo

# ---- Memory + Resizable BAR ----
echo "── Memory / Resizable BAR ──"
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
info "RAM: ${RAM_GB} GiB"
# ReBAR check: GPU BAR size > 256MB roughly indicates ReBAR enabled
GPU_BAR=$(lspci -vvv -d ::0300 2>/dev/null | grep "Region.*Memory.*prefetchable" | head -1 || true)
if echo "$GPU_BAR" | grep -qE 'size=(8G|16G|32G)'; then
  ok "GPU prefetchable BAR is large → Resizable BAR is ENABLED"
elif echo "$GPU_BAR" | grep -qE 'size=256M'; then
  warn "GPU BAR is 256M → Resizable BAR is DISABLED. Enable in BIOS."
else
  info "GPU BAR: $GPU_BAR"
fi
echo

# ---- GPU / Vulkan ----
echo "── GPU (RX 6750 XT) ──"
if lspci | grep -qi "Navi 22"; then ok "AMD Navi 22 detected"; fi
if command -v vulkaninfo &>/dev/null; then
  DEV=$(vulkaninfo --summary 2>/dev/null | grep deviceName | head -1)
  if [[ -n "$DEV" ]]; then ok "Vulkan: $DEV"; else fail "Vulkan not initializing"; fi
fi
DRM=$(ls /sys/class/drm/card*/device/driver 2>/dev/null | head -1 || true)
if [[ -n "$DRM" ]]; then info "DRM driver: $(readlink "$DRM" | xargs basename)"; fi
echo

# ---- Storage / NVMe ----
echo "── Storage / NVMe ──"
for d in /sys/block/nvme*; do
  [[ -e "$d" ]] || continue
  NAME=$(basename "$d")
  SCHED=$(cat "$d/queue/scheduler" 2>/dev/null | grep -oE '\[[a-z-]+\]' | tr -d '[]' || echo ?)
  info "$NAME scheduler: $SCHED  (expect 'none')"
done
echo "fstab swap:"
grep -E '^[^#].*swap' /etc/fstab || echo "  (none — relying on zram or zramswap)"
swapon --show
echo

# ---- Btrfs / snapper ----
echo "── Btrfs / snapper ──"
if mount | grep -q "type btrfs"; then ok "btrfs root"; fi
if systemctl is-active --quiet snapper-timeline.timer; then ok "snapper-timeline.timer active"; else warn "snapper-timeline.timer inactive"; fi
echo

# ---- Audio (PipeWire) ----
echo "── Audio (PipeWire) ──"
if pgrep -x pipewire >/dev/null; then ok "pipewire running"; else fail "pipewire not running"; fi
if pgrep -x wireplumber >/dev/null; then ok "wireplumber running"; else warn "wireplumber not running"; fi
if command -v wpctl &>/dev/null; then
  SINKS=$(wpctl status 2>/dev/null | grep -A20 "Sinks:" | grep -E '^\s+[│└├*].*\.' | head -3 || true)
  [[ -n "$SINKS" ]] && info "Output sinks detected"
fi
echo

# ---- Network / WiFi / Bluetooth ----
echo "── Network ──"
if systemctl is-active --quiet NetworkManager; then ok "NetworkManager active"; else fail "NetworkManager inactive"; fi
nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -v unmanaged | head -5
echo
echo "── WiFi adapter ──"
WIFI_PCI=$(lspci -nnk | grep -iA3 -E "network controller|wireless" || true)
USB_WIFI=$(lsusb | grep -iE "wireless|wifi|wlan|802.11" || true)
if [[ -n "$WIFI_PCI" ]]; then
  echo "$WIFI_PCI"
  # Check driver bound
  DRV=$(echo "$WIFI_PCI" | grep -oP 'Kernel driver in use:\s*\K\S+' | head -1)
  if [[ -n "$DRV" ]]; then ok "Driver: $DRV"; else warn "No kernel driver bound — likely missing firmware"; fi
elif [[ -n "$USB_WIFI" ]]; then
  echo "USB WiFi: $USB_WIFI"
else
  info "(no WiFi adapter found — wired-only system?)"
fi
# iwd or wpa_supplicant? NetworkManager handles either.
WL_IF=$(ip -o link show 2>/dev/null | awk -F': ' '/wlan|wlp|wl/{print $2; exit}')
[[ -n "$WL_IF" ]] && ok "WiFi interface up: $WL_IF" || true
# Check available networks (only if interface exists, doesn't connect)
if [[ -n "$WL_IF" ]]; then
  COUNT=$(nmcli -t -f SSID device wifi list 2>/dev/null | sort -u | wc -l)
  info "Networks visible: $COUNT (run 'nmcli device wifi list' for details)"
fi
# Common firmware split-package check
echo "Loaded firmware blobs:"
sudo dmesg 2>/dev/null | grep -iE "firmware.*loaded|firmware.*: direct-loading" | tail -5 || true
echo
echo "── Bluetooth ──"
BT_PCI=$(lspci -nnk | grep -iA2 bluetooth || true)
BT_USB=$(lsusb | grep -iE "bluetooth|wireless interface" || true)
[[ -n "$BT_PCI" ]] && echo "$BT_PCI"
[[ -n "$BT_USB" ]] && echo "USB BT: $BT_USB"
if systemctl is-active --quiet bluetooth; then ok "bluetooth.service active"; else warn "bluetooth.service inactive"; fi
if command -v bluetoothctl &>/dev/null; then
  BT_INFO=$(bluetoothctl show 2>/dev/null | head -3)
  if [[ -n "$BT_INFO" ]]; then
    ok "BT controller present"
    info "$BT_INFO"
    POWERED=$(bluetoothctl show 2>/dev/null | grep -oP 'Powered:\s*\K\w+')
    [[ "$POWERED" == "yes" ]] && ok "BT powered on" || warn "BT not powered (run: bluetoothctl power on)"
  else
    warn "No BT controller detected — check 'lsmod | grep bluetooth' and 'dmesg | grep -i bluetooth'"
  fi
fi
# Common Bluetooth firmware issues
sudo dmesg 2>/dev/null | grep -iE "bluetooth.*firmware|bluetooth.*failed" | tail -5 || true
echo
echo "── Display / DDC (monitors) ──"
if command -v ddcutil &>/dev/null; then
  DDCD=$(ddcutil detect --terse 2>/dev/null | grep -c "^Display")
  if [[ "$DDCD" -gt 0 ]]; then
    ok "DDC/CI detected on $DDCD monitor(s) — hardware brightness works"
    ddcutil detect --terse 2>/dev/null | head -20
  else
    warn "ddcutil detect found no DDC-capable displays. Check: i2c-dev module loaded? user in i2c group?"
    info "  lsmod | grep i2c_dev   # should list i2c_dev"
    info "  groups | grep i2c      # should include i2c"
  fi
fi
echo

# ---- systemd-boot / UKI ----
echo "── systemd-boot / UKI ──"
if [[ -f /boot/loader/loader.conf ]]; then ok "systemd-boot installed"; fi
ls /boot/EFI/Linux/*.efi 2>/dev/null | while read -r u; do
  SIZE=$(du -h "$u" | cut -f1)
  info "UKI: $u ($SIZE)"
done
echo "ESP free space:"
df -h /boot | tail -1
echo

# ---- Sway / Wayland ----
echo "── Sway / Wayland ──"
if pgrep -x sway >/dev/null; then
  ok "sway running"
  SWAY_VER=$(sway --version 2>/dev/null | awk '{print $3}')
  info "sway version: $SWAY_VER  (need >= 1.12 for color-management)"
fi
echo "WLR_RENDERER: ${WLR_RENDERER:-(unset — set to 'vulkan' for color/HDR)}"
echo

# ---- Sensors ----
echo "── Sensors / temps ──"
if command -v sensors &>/dev/null; then sensors 2>/dev/null | grep -E '^[A-Z].*:|^Tctl|^edge|^junction' | head -10; fi
echo
echo "=== Verification complete ==="
