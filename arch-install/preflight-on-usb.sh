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
HARD_STOP=0            # tracks whether we must block install due to data-loss risk

# Enumerate all NVMe devices and show identification — critical when multiple
# drives are installed. archinstall WILL wipe whatever sits at $TARGET.
echo "── NVMe inventory ──"
lsblk -d -o NAME,SIZE,MODEL,SERIAL --noheadings | awk '/^nvme/{print "  /dev/" $0}'
NVME_COUNT=$(lsblk -d -n -o NAME | grep -c '^nvme' || true)
if [[ "$NVME_COUNT" -gt 1 ]]; then
  fail "Multiple NVMe drives detected — REFUSING to continue."
  fail "  archinstall hardcodes /dev/nvme0n1 as the wipe target, but Linux NVMe"
  fail "  enumeration order is firmware-dependent. The wrong drive could end up"
  fail "  at nvme0n1 and get wiped."
  fail "  Power off, physically REMOVE all drives except the blank target, re-run."
  fail "  Override (DANGEROUS — only if you've verified models above): FORCE_INSTALL=1"
  HARD_STOP=1
fi

if [[ -b "$TARGET" ]]; then
  SIZE_GB=$(($(blockdev --getsize64 "$TARGET") / 1024 / 1024 / 1024))
  TARGET_MODEL=$(lsblk -d -n -o MODEL "$TARGET" | xargs)
  TARGET_SERIAL=$(lsblk -d -n -o SERIAL "$TARGET" | xargs)
  PART_COUNT=$(lsblk -n -o NAME "$TARGET" | tail -n +2 | wc -l)
  echo "  → Target /dev/nvme0n1: $TARGET_MODEL (sn=$TARGET_SERIAL, ${SIZE_GB} GiB, $PART_COUNT partition(s))"

  if [[ "$SIZE_GB" -lt "$EXPECTED_GB" ]]; then
    fail "$TARGET is ${SIZE_GB} GiB but disk_config needs ≥${EXPECTED_GB} GiB."
    HARD_STOP=1
  fi

  # Anything other than 0 partitions = potentially-populated drive. Block.
  if [[ "$PART_COUNT" -gt 0 ]]; then
    fail "$TARGET has $PART_COUNT existing partition(s) — REFUSING to continue."
    fail "  This drive is NOT blank. archinstall would wipe it entirely."
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$TARGET" | sed 's/^/    /'
    # Look for filesystem signatures characteristic of an existing OS install
    SIGS=$(lsblk -n -o FSTYPE "$TARGET" | sort -u | tr '\n' ' ')
    if echo "$SIGS" | grep -qE "ntfs|exfat|hfsplus|apfs"; then
      fail "  Detected non-Linux filesystem(s): $SIGS"
      fail "  This looks like a Windows / macOS / external data drive."
    fi
    fail "  If this is the WRONG drive: power off, swap M.2 slots, re-run preflight."
    fail "  If this is GENUINELY the right drive (you wiped it earlier and signatures linger):"
    fail "    sudo wipefs -a $TARGET   # then re-run preflight"
    fail "  Override (DANGEROUS): FORCE_INSTALL=1 ./preflight-on-usb.sh"
    HARD_STOP=1
  else
    ok "Target $TARGET is BLANK ($TARGET_MODEL, sn=$TARGET_SERIAL, ${SIZE_GB} GiB)"
  fi
else
  fail "$TARGET missing — check the disk_config block inside user_configuration.json"
  echo "Available disks:"
  lsblk -d -o NAME,SIZE,MODEL
  HARD_STOP=1
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
  HARD_STOP=1
fi

# archinstall presence
echo
if command -v archinstall &>/dev/null; then
  ok "archinstall: $(archinstall --version 2>&1 | head -1)"
else
  fail "archinstall not found — are you actually on the live USB?"
fi

echo
if [[ "$HARD_STOP" -eq 1 ]] && [[ "${FORCE_INSTALL:-0}" != "1" ]]; then
  echo -e "${RED}=== HARD STOP — install blocked ===${NC}"
  echo "One or more checks above would risk wiping a populated drive."
  echo "Resolve the issues, OR (only if you've genuinely verified):"
  echo "  FORCE_INSTALL=1 ./preflight-on-usb.sh"
  exit 2
fi
if [[ "${FORCE_INSTALL:-0}" == "1" ]] && [[ "$HARD_STOP" -eq 1 ]]; then
  warn "FORCE_INSTALL=1 set — bypassing safety checks. You're on your own."
fi

echo "=== Next: dry-run, then real install ==="
echo "  sudo archinstall --dry-run --silent \\"
echo "       --config user_configuration.json \\"
echo "       --creds user_credentials.json"
echo "  # archinstall 4.x has no --disk-layout flag; the disk plan lives inside user_configuration.json's disk_config block."
echo
echo "If dry-run is clean, drop --dry-run for the real run."
