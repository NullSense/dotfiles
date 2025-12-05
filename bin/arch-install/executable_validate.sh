#!/bin/bash
# Pre-flight validation for Arch Linux installation
# Run this BEFORE archinstall to catch configuration errors

set -euo pipefail

echo "=== Arch Install Pre-Flight Validation ==="
echo ""

ERRORS=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}ERROR:${NC} $1"
    ((ERRORS++))
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
    ((WARNINGS++))
}

ok() {
    echo -e "${GREEN}OK:${NC} $1"
}

# ============================================================================
# 1. Check JSON syntax
# ============================================================================
echo "[1/6] Validating JSON syntax..."

for file in disk-layout.json user_configuration.json user_credentials.json; do
    if [ -f "$file" ]; then
        if python3 -m json.tool "$file" > /dev/null 2>&1; then
            ok "$file is valid JSON"
        else
            error "$file has invalid JSON syntax"
        fi
    else
        error "$file not found"
    fi
done

# ============================================================================
# 2. Check credentials
# ============================================================================
echo ""
echo "[2/6] Checking credentials..."

if [ -f "user_credentials.json" ]; then
    if grep -q "CHANGE_ME" user_credentials.json; then
        error "user_credentials.json still contains 'CHANGE_ME' placeholder passwords!"
        echo "      Edit the file and set real passwords before running archinstall."
    else
        ok "Credentials appear to be set"
    fi
fi

# ============================================================================
# 3. Check bootloader setting
# ============================================================================
echo ""
echo "[3/6] Checking bootloader configuration..."

if [ -f "user_configuration.json" ]; then
    BOOTLOADER=$(grep -o '"bootloader"[[:space:]]*:[[:space:]]*"[^"]*"' user_configuration.json | cut -d'"' -f4)
    if [ "$BOOTLOADER" = "systemd" ]; then
        ok "Bootloader is correctly set to 'systemd'"
    elif [ "$BOOTLOADER" = "systemd-bootctl" ]; then
        error "Bootloader is set to 'systemd-bootctl' - should be 'systemd'"
    else
        warn "Bootloader is set to '$BOOTLOADER' - expected 'systemd'"
    fi
fi

# ============================================================================
# 4. Check disk device
# ============================================================================
echo ""
echo "[4/6] Checking disk configuration..."

if [ -f "disk-layout.json" ]; then
    DEVICE=$(grep -o '"device"[[:space:]]*:[[:space:]]*"[^"]*"' disk-layout.json | head -1 | cut -d'"' -f4)
    echo "Target device: $DEVICE"

    if [ -b "$DEVICE" ]; then
        ok "Device $DEVICE exists"
        SIZE=$(lsblk -b -d -n -o SIZE "$DEVICE" 2>/dev/null || echo "0")
        SIZE_GB=$((SIZE / 1024 / 1024 / 1024))
        echo "      Size: ${SIZE_GB}GB"
    else
        warn "Device $DEVICE not found - make sure it exists before running archinstall"
    fi
fi

# ============================================================================
# 5. Check network
# ============================================================================
echo ""
echo "[5/6] Checking network connectivity..."

if ping -c 1 archlinux.org > /dev/null 2>&1; then
    ok "Network is connected"
else
    error "No network connectivity - archinstall requires internet"
fi

# ============================================================================
# 6. Check archinstall version
# ============================================================================
echo ""
echo "[6/6] Checking archinstall..."

if command -v archinstall &> /dev/null; then
    VERSION=$(archinstall --version 2>&1 | head -1 || echo "unknown")
    ok "archinstall is available: $VERSION"
else
    warn "archinstall not found - are you running from Arch live USB?"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=========================================="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}VALIDATION FAILED${NC}"
    echo "$ERRORS error(s), $WARNINGS warning(s)"
    echo ""
    echo "Fix the errors above before running archinstall!"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}VALIDATION PASSED WITH WARNINGS${NC}"
    echo "$WARNINGS warning(s)"
    echo ""
    echo "Review the warnings above, then run:"
    echo "  archinstall --config user_configuration.json --disk-layout disk-layout.json --creds user_credentials.json"
    exit 0
else
    echo -e "${GREEN}VALIDATION PASSED${NC}"
    echo ""
    echo "Ready to install! Run:"
    echo "  archinstall --config user_configuration.json --disk-layout disk-layout.json --creds user_credentials.json"
    exit 0
fi
