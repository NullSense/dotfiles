#!/bin/bash
# Secure Boot setup with sbctl + UKI on Arch.
# Run AFTER post-install.sh, AFTER hardware-optimize.sh, after a working boot.
#
# PRE-REQUISITES (do these first, in BIOS):
#   1. Reboot:  systemctl reboot --firmware-setup
#   2. In BIOS Security menu:
#        - Set Secure Boot mode to "Custom" / "Setup Mode" (clear keys, keep SB enabled)
#        - On most ASUS/MSI boards: "Delete all Secure Boot variables" or "Reset to Setup Mode"
#   3. Save & boot back into Arch.
#   4. Confirm: `sudo sbctl status` should show "Setup Mode: Enabled"
#
# This script will then: create keys, enroll them (with Microsoft KEK to keep
# fwupd/option ROMs working), sign the bootloader + UKIs, and install pacman
# hooks for auto-signing on every kernel/systemd update.
#
# After it finishes, reboot → BIOS → re-enable Secure Boot. Done forever.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

echo "=== Secure Boot setup via sbctl + UKI ==="
echo

# 1. Verify Setup Mode
echo "[1/5] Checking Secure Boot status..."
sbctl status
echo
if ! sbctl status | grep -q "Setup Mode:.*Enabled"; then
  echo "ERROR: Setup Mode is not enabled."
  echo "Reboot into BIOS and clear the Secure Boot keys to enter Setup Mode."
  echo "Run 'systemctl reboot --firmware-setup' to jump directly to BIOS."
  exit 1
fi
echo "OK — Setup Mode is enabled."
echo

# 2. Create keys
echo "[2/5] Creating Secure Boot keys (stored in /var/lib/sbctl/keys)..."
if [[ -d /var/lib/sbctl/keys/PK ]]; then
  echo "Keys already exist — skipping create-keys."
else
  sbctl create-keys
fi

# 3. Enroll keys (with Microsoft KEK — important for fwupd/option ROMs)
echo "[3/5] Enrolling keys (-m keeps Microsoft KEK; required for fwupd & option ROMs)..."
sbctl enroll-keys --microsoft

# 4. Sign everything in the file database
echo "[4/5] Signing bootloader + UKIs..."
# UKI sign hook is automatic via mkinitcpio post-hook; force a regen to trigger it now
mkinitcpio -P
# Pick up systemd-boot binary + anything else not handled by the UKI hook
sbctl sign-all

# 5. Verify
echo "[5/5] Verifying signatures..."
sbctl verify

echo
echo "=== Done. ==="
echo
echo "Next steps:"
echo "  1. Reboot:                  systemctl reboot --firmware-setup"
echo "  2. In BIOS, ENABLE Secure Boot (back to Standard / User Mode)."
echo "  3. Save & boot back into Arch."
echo "  4. Verify:                  sudo sbctl status"
echo "       → 'Secure Boot: Enabled' + 'Setup Mode: Disabled' = success."
echo
echo "From now on, every kernel/systemd/bootloader update is auto-signed via"
echo "the sbctl pacman hook. Zero ongoing maintenance."
