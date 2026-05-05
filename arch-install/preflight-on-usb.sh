#!/bin/bash
# PRE-FLIGHT — run this from the Arch live USB BEFORE running archinstall.
# Catches hardware/firmware/network problems that would otherwise interrupt
# the installer mid-run.

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}OK${NC}    $1"; }
warn() { echo -e "${YELLOW}WARN${NC}  $1"; }
fail() { echo -e "${RED}FAIL${NC}  $1"; }

echo "=== Live-USB pre-flight ==="
echo

# UEFI
if [[ -d /sys/firmware/efi ]]; then ok "Booted in UEFI mode"; else fail "Not UEFI — reboot, disable CSM in BIOS"; fi
[[ -f /sys/firmware/efi/fw_platform_size ]] && [[ "$(cat /sys/firmware/efi/fw_platform_size)" == "64" ]] && ok "64-bit UEFI"

# Internet
if ping -c1 -W3 archlinux.org &>/dev/null; then ok "Internet reachable"; else fail "No internet — fix before continuing"; fi

# Time
if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then ok "Time synced"; else warn "Time not synced — run: timedatectl set-ntp true"; fi

# Disk presence + size match (disk_config hardcodes /dev/nvme0n1 as target)
TARGET="/dev/nvme0n1"
EXPECTED_GB=1860       # btrfs partition size from user_configuration.json

# Enumerate all NVMe devices and show identification — critical when multiple
# drives are installed. archinstall WILL wipe whatever sits at $TARGET.
echo "── NVMe inventory ──"
lsblk -d -o NAME,SIZE,MODEL,SERIAL --noheadings | awk '/^nvme/{print "  /dev/" $0}'
NVME_COUNT=$(lsblk -d -n -o NAME | grep -c '^nvme' || true)
if [[ "$NVME_COUNT" -gt 1 ]]; then
  warn "Multiple NVMe drives detected. archinstall will WIPE /dev/nvme0n1."
  warn "Verify above that nvme0n1 is the BLANK target drive (not your existing data drive)."
  warn "If wrong, power off, swap M.2 slots, and re-run this script."
fi

if [[ -b "$TARGET" ]]; then
  SIZE_GB=$(($(blockdev --getsize64 "$TARGET") / 1024 / 1024 / 1024))
  TARGET_MODEL=$(lsblk -d -n -o MODEL "$TARGET" | xargs)
  TARGET_SERIAL=$(lsblk -d -n -o SERIAL "$TARGET" | xargs)
  HAS_PARTITIONS=$(lsblk -n "$TARGET" | wc -l)
  if [[ "$SIZE_GB" -ge "$EXPECTED_GB" ]]; then
    ok "Target $TARGET ($TARGET_MODEL, sn=$TARGET_SERIAL, ${SIZE_GB} GiB)"
  else
    fail "$TARGET is ${SIZE_GB} GiB but disk_config needs ≥${EXPECTED_GB} GiB. Regenerate disk_config for this drive."
  fi
  if [[ "$HAS_PARTITIONS" -gt 1 ]]; then
    warn "$TARGET already has partitions:"
    lsblk "$TARGET" | sed 's/^/    /'
    warn "archinstall will wipe ALL of these. Confirm this is the right drive."
  fi
else
  fail "$TARGET missing — check the disk_config block inside user_configuration.json"
  echo "Available disks:"
  lsblk -d -o NAME,SIZE,MODEL
fi

# CPU + AGESA
echo
echo "── CPU / firmware ──"
grep -m1 'model name' /proc/cpuinfo | sed 's/^/  /'
DMI_BIOS=$(dmidecode -s bios-version 2>/dev/null || echo unknown)
DMI_MOBO=$(dmidecode -s baseboard-product-name 2>/dev/null || echo unknown)
DMI_DATE=$(dmidecode -s bios-release-date 2>/dev/null || echo unknown)
echo "  Motherboard: $DMI_MOBO"
echo "  BIOS:        $DMI_BIOS ($DMI_DATE)"
AGESA=$(dmesg | grep -i agesa | head -1 || true)
[[ -n "$AGESA" ]] && echo "  AGESA:       $AGESA"

# GPU
echo
echo "── GPU ──"
lspci -nn | grep -iE "vga|display|3d" | sed 's/^/  /'

# WiFi + Bluetooth detection
echo
echo "── WiFi / Bluetooth chips ──"
WIFI=$(lspci -nnk | grep -iA3 -E "network controller|wireless")
[[ -n "$WIFI" ]] && echo "$WIFI" | sed 's/^/  /' || echo "  (none detected on PCI)"
BT=$(lspci -nnk | grep -iA2 bluetooth)
[[ -n "$BT" ]] && echo "$BT" | sed 's/^/  /' || echo "  (no PCI BT — likely combo with WiFi or USB)"
USB_BT=$(lsusb 2>/dev/null | grep -iE "bluetooth|wireless" || true)
[[ -n "$USB_BT" ]] && echo "  USB: $USB_BT"

# Memory
echo
echo "── Memory ──"
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "  RAM: ${RAM_GB} GiB"
dmidecode -t memory 2>/dev/null | grep -E "Speed:|Configured Memory Speed:" | sort -u | head -2 | sed 's/^/  /'

# Resizable BAR check (target GPU)
echo
echo "── TPM 2.0 ──"
if [[ -e /dev/tpm0 || -e /dev/tpmrm0 ]]; then
  ok "TPM device present (TPM2 auto-unlock available post-install)"
else
  warn "No TPM device — disk encryption still works but you'll type passphrase at every boot. Enable TPM/fTPM in BIOS to skip that."
fi

echo
echo "── Resizable BAR ──"
GPU_BAR=$(lspci -vvv -d ::0300 2>/dev/null | grep "prefetchable" | head -1)
if echo "$GPU_BAR" | grep -qE 'size=(8G|16G|32G)'; then
  ok "ReBAR enabled (large GPU BAR)"
elif echo "$GPU_BAR" | grep -qE 'size=256M'; then
  warn "ReBAR DISABLED (256M BAR). Reboot, enable Above-4G + ReBAR in BIOS."
else
  echo "  BAR: $GPU_BAR"
fi

# JSON sanity (run validate.sh path too)
echo
echo "── archinstall config ──"
for f in user_configuration.json user_credentials.json; do
  if python -c "import json; json.load(open('$f'))" 2>/dev/null; then
    ok "$f parses"
  else
    fail "$f BROKEN"
  fi
done
if grep -q CHANGE_ME user_credentials.json 2>/dev/null; then
  fail "user_credentials.json still contains CHANGE_ME — edit before installing"
fi

# archinstall presence
echo
if command -v archinstall &>/dev/null; then
  ok "archinstall: $(archinstall --version 2>&1 | head -1)"
else
  fail "archinstall not found — are you actually on the live USB?"
fi

echo
echo "=== Optional: actual archinstall dry-run ==="
echo "  sudo archinstall --dry-run --silent \\"
echo "       --config user_configuration.json \\"
echo "       --creds user_credentials.json"
echo "  # archinstall 4.x has no --disk-layout flag; the disk plan lives inside user_configuration.json's disk_config block."
echo
echo "If everything above is OK and dry-run is clean, run without --dry-run."
