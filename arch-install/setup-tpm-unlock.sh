#!/bin/bash
# Bind LUKS2 root partition to TPM2 so the box auto-unlocks after Secure Boot
# is enrolled. Modern recipe: PCR 7 (Secure Boot policy) + PCR 11 (UKI hash).
# - PCR 0/2 binding is OBSOLETE (breaks on every firmware update)
# - PCR 7+11 is what systemd-cryptenroll docs + ArchWiki recommend in 2026
#
# RUN AFTER: setup-secure-boot.sh has finished and Secure Boot is active.
# Without active Secure Boot in user mode, PCR 7 is meaningless.

set -euo pipefail

LUKS_DEV="${LUKS_DEV:-/dev/disk/by-partlabel/cryptroot}"

# Find LUKS device if the conventional partlabel doesn't exist
if [[ ! -b "$LUKS_DEV" ]]; then
  LUKS_DEV=$(blkid -t TYPE=crypto_LUKS -o device | head -1)
fi
[[ -b "$LUKS_DEV" ]] || { echo "FAIL: cannot find LUKS device" >&2; exit 1; }

echo "Target LUKS device: $LUKS_DEV"

# Verify Secure Boot is actually active before binding to PCR 7
if ! sbctl status 2>/dev/null | grep -qE "Secure Boot.*Enabled"; then
  echo "FAIL: Secure Boot is not enabled. Run setup-secure-boot.sh and reboot first." >&2
  echo "PCR 7 binding without active Secure Boot would be exploitable." >&2
  exit 1
fi

# 1. Enroll a recovery key FIRST. This is non-negotiable — if your motherboard
#    dies or BIOS is updated and PCR state shifts, this is your only way back in.
echo "=== Enrolling recovery key (write this down NOW, store in Bitwarden) ==="
sudo systemd-cryptenroll --recovery-key "$LUKS_DEV"

# 2. Enroll TPM2 bound to PCR 7 + PCR 11.
#    --wipe-slot=tpm2 ensures we replace any stale TPM enrollment, not append.
echo
echo "=== Enrolling TPM2 (PCR 7 + 11) ==="
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7+11 \
  --wipe-slot=tpm2 \
  "$LUKS_DEV"

# 3. List current keyslots so you can verify enrollment
echo
echo "=== Current keyslot inventory ==="
sudo systemd-cryptenroll "$LUKS_DEV"

cat <<'NOTE'

=== Done ===

Reboot. The box should unlock without prompting for the LUKS passphrase.
If it prompts:
  - your original passphrase still works (kept in keyslot 0)
  - the recovery key from step 1 also works
  - rerun this script after reboot to refresh the TPM binding

If you ever do a major firmware update or BIOS reset, PCR 7 may shift and
auto-unlock will fail. That's expected — boot with the recovery key, then
rerun this script to re-enroll against the new PCR 7 value.

NOTE
