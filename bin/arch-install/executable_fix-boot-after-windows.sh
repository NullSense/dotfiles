#!/bin/bash
# Fix systemd-boot after Windows update overwrites boot order
# Run this from an Arch live USB if Windows breaks your boot

set -euo pipefail

echo "=== Fix systemd-boot after Windows Update ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo ""
echo "This script fixes boot issues after Windows updates."
echo "Run this from an Arch live USB if you can't boot into Arch."
echo ""

# Option 1: Just fix EFI boot order (most common fix)
fix_boot_order() {
    echo "[Method 1] Restoring EFI boot order..."

    # Find the systemd-boot entry
    BOOTNUM=$(efibootmgr | grep -i "Linux Boot Manager" | grep -oP 'Boot\K[0-9A-F]+')

    if [ -z "$BOOTNUM" ]; then
        echo "Linux Boot Manager not found. Creating new entry..."
        # Assuming ESP is on nvme0n1p1
        efibootmgr --create --disk /dev/nvme0n1 --part 1 \
            --label "Linux Boot Manager" \
            --loader '\EFI\systemd\systemd-bootx64.efi'
        BOOTNUM=$(efibootmgr | grep -i "Linux Boot Manager" | grep -oP 'Boot\K[0-9A-F]+')
    fi

    echo "Setting Linux Boot Manager (Boot$BOOTNUM) as first boot option..."
    efibootmgr --bootorder "$BOOTNUM,$(efibootmgr | grep BootOrder | cut -d: -f2 | tr -d ' ')"

    echo "Current boot order:"
    efibootmgr
}

# Option 2: Reinstall systemd-boot (if files are corrupted)
reinstall_bootloader() {
    echo "[Method 2] Reinstalling systemd-boot..."

    # Mount the installed system (adjust device names as needed)
    echo "Mounting installed system..."
    mount /dev/nvme0n1p2 /mnt -o subvol=@
    mount /dev/nvme0n1p1 /mnt/boot

    # Chroot and reinstall
    arch-chroot /mnt bootctl install

    echo "Reinstalled systemd-boot"

    umount -R /mnt
}

# Option 3: Use fallback path (Windows-resistant)
setup_fallback() {
    echo "[Method 3] Setting up fallback boot path..."
    echo "This makes systemd-boot the default EFI fallback."
    echo "More resistant to Windows updates."

    # Mount ESP
    mount /dev/nvme0n1p1 /mnt

    # Backup existing fallback if present
    if [ -f /mnt/EFI/BOOT/BOOTX64.EFI ]; then
        cp /mnt/EFI/BOOT/BOOTX64.EFI /mnt/EFI/BOOT/BOOTX64.EFI.bak
    fi

    # Copy systemd-boot to fallback location
    mkdir -p /mnt/EFI/BOOT
    cp /mnt/EFI/systemd/systemd-bootx64.efi /mnt/EFI/BOOT/BOOTX64.EFI

    echo "Fallback bootloader set up."
    echo "If Windows overwrites boot order, UEFI will fall back to systemd-boot."

    umount /mnt
}

echo "Choose fix method:"
echo "  1) Fix boot order only (try this first)"
echo "  2) Reinstall systemd-boot (if option 1 doesn't work)"
echo "  3) Setup fallback path (most resistant to Windows)"
echo "  4) All of the above"
echo ""
read -p "Enter choice [1-4]: " choice

case $choice in
    1) fix_boot_order ;;
    2) reinstall_bootloader ;;
    3) setup_fallback ;;
    4)
        fix_boot_order
        reinstall_bootloader
        setup_fallback
        ;;
    *) echo "Invalid choice" ;;
esac

echo ""
echo "=== Done ==="
echo "Reboot and check if Arch boots correctly."
echo ""
echo "IMPORTANT: In Windows, disable Fast Startup to prevent ESP corruption:"
echo "  Control Panel > Power Options > Choose what power buttons do"
echo "  > Change settings currently unavailable > Uncheck 'Turn on fast startup'"
