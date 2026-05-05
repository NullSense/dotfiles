#!/usr/bin/env bash
# Self-heal UEFI boot priority. Runs on every boot via the systemd unit of
# the same name. If Windows updates (or a BIOS reset) push Linux out of
# BootOrder[0], we shove it back automatically.
#
# Idempotent and silent on the happy path. Logs via journald.

set -euo pipefail

LABEL="${1:-Linux Boot Manager}"

# Find our boot entry's hex ID (e.g. "0001")
ENTRY=$(efibootmgr | awk -v lbl="$LABEL" '
  $0 ~ lbl {
    match($1, /[0-9A-Fa-f]+/);
    print substr($1, RSTART, RLENGTH);
    exit
  }')

if [[ -z "$ENTRY" ]]; then
  echo "assert-boot-priority: no UEFI entry labeled '$LABEL' found — nothing to do"
  exit 0
fi

# Read current order, drop our entry from wherever it is, and prepend it
CURRENT=$(efibootmgr | awk -F': ' '/^BootOrder:/{print $2}' | tr -d ' ')
if [[ -z "$CURRENT" ]]; then
  echo "assert-boot-priority: BootOrder is empty"
  exit 0
fi

# If we're already first, exit silent — no NVRAM write
FIRST="${CURRENT%%,*}"
if [[ "${FIRST^^}" == "${ENTRY^^}" ]]; then
  exit 0
fi

# Build new order: ENTRY first, then everything else (de-duped)
REST=$(echo "$CURRENT" | tr ',' '\n' | grep -viE "^${ENTRY}$" | paste -sd,)
NEW="${ENTRY},${REST}"

echo "assert-boot-priority: $LABEL ($ENTRY) was not first"
echo "  before: $CURRENT"
echo "  after:  $NEW"
efibootmgr --bootorder "$NEW" >/dev/null
