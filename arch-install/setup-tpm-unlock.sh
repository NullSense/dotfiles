#!/bin/bash
# Bind LUKS2 root partition to TPM2 so the box auto-unlocks after Secure Boot
# is enrolled. Recipe (ArchWiki systemd-cryptenroll): PCR 7 (Secure Boot state)
# + PCR 15 pinned to zero. The initrd measures the volume key into PCR 15 after
# unlock (rd.luks.options=...tpm2-measure-pcr=yes in /etc/kernel/cmdline), so the
# key can't be unsealed again later in the same boot.
# - PCR 0/2 binding is OBSOLETE (breaks on every firmware update)
# - Raw PCR 11 is the UKI hash and changes on EVERY kernel/initramfs rebuild;
#   use it only through a signed PCR policy (ukify PCRPKey), never as a raw value.
# - Needs the systemd initramfs (HOOKS: systemd ... sd-encrypt); the busybox
#   `encrypt` hook ignores TPM2 tokens entirely.
#
# RUN AFTER: setup-secure-boot.sh has finished and Secure Boot is active.
# Without active Secure Boot in user mode, PCR 7 is meaningless.

set -euo pipefail

LUKS_DEV="${LUKS_DEV:-/dev/disk/by-partlabel/cryptroot}"

# Find LUKS device if the conventional partlabel doesn't exist. Only guess when
# exactly one LUKS device exists; otherwise make the caller name it.
if [[ ! -b "$LUKS_DEV" ]]; then
  mapfile -t luks_devs < <(blkid -t TYPE=crypto_LUKS -o device)
  if (( ${#luks_devs[@]} != 1 )); then
    echo "FAIL: found ${#luks_devs[@]} LUKS devices; set LUKS_DEV=/dev/disk/by-uuid/<uuid>" >&2
    exit 1
  fi
  LUKS_DEV=${luks_devs[0]}
fi
[[ -b "$LUKS_DEV" ]] || { echo "FAIL: cannot find LUKS device" >&2; exit 1; }

echo "Target LUKS device: $LUKS_DEV"

# Verify Secure Boot is actually active before binding to PCR 7
if ! sbctl status 2>/dev/null | grep -qE "Secure Boot.*Enabled"; then
  echo "FAIL: Secure Boot is not enabled. Run setup-secure-boot.sh and reboot first." >&2
  echo "PCR 7 binding without active Secure Boot would be exploitable." >&2
  exit 1
fi

# The zeroed-PCR-15 pin only protects anything if the initrd extends PCR 15
# after unlocking. Without tpm2-measure-pcr=yes it stays zero all boot and root
# can unseal the volume key from userspace. Require it in both the running
# kernel's cmdline and the one baked into future UKIs.
for f in /proc/cmdline /etc/kernel/cmdline; do
  if ! grep -q 'tpm2-measure-pcr=yes' "$f"; then
    echo "FAIL: $f lacks rd.luks.options=...tpm2-measure-pcr=yes; PCR 15 pin would be inert." >&2
    exit 1
  fi
done

# PCR 7 only records WHICH keys verified the boot chain. With Microsoft's
# vendor keys in db, any Microsoft-signed bootloader (shim + another distro,
# Windows PE, ...) reproduces PCR 7 and can unseal the key. In that case demand
# a TPM PIN, or an explicit, informed override.
PIN_ARGS=()
if sbctl status 2>/dev/null | grep -qiE 'Vendor Keys:.*microsoft'; then
  if [[ "${TPM2_PIN:-}" == 1 ]]; then
    PIN_ARGS=(--tpm2-with-pin=yes)
  elif [[ "${ALLOW_PCR7_WITH_VENDOR_KEYS:-}" != 1 ]]; then
    cat >&2 <<'EOF'
FAIL: Microsoft vendor keys are enrolled in Secure Boot db, so PCR 7 alone does
not tie the key to YOUR boot chain. Choose one:
  TPM2_PIN=1                     enroll with a TPM PIN typed at boot (recommended)
  ALLOW_PCR7_WITH_VENDOR_KEYS=1  accept PCR 7+15 without a PIN (weaker)
The strong PIN-less option is a signed PCR 11 policy (ukify PCRPKey +
--tpm2-public-key), which survives kernel updates; this script doesn't do that.
EOF
    exit 1
  fi
fi

# 1. Enroll a recovery key FIRST. This is non-negotiable — if your motherboard
#    dies or BIOS is updated and PCR state shifts, this is your only way back in.
echo "=== Enrolling recovery key (write this down NOW, store in Bitwarden) ==="
sudo systemd-cryptenroll --recovery-key "$LUKS_DEV"

# 2. Enroll TPM2 bound to PCR 7 + zeroed PCR 15.
#    --wipe-slot=tpm2 ensures we replace any stale TPM enrollment, not append.
echo
echo "=== Enrolling TPM2 (PCR 7 + zeroed PCR 15) ==="
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7+15:sha256=0000000000000000000000000000000000000000000000000000000000000000 \
  "${PIN_ARGS[@]}" \
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
