# Arch Linux Installation Guide

NVMe 2TB SSD with Btrfs + Sway/Wayland setup using archinstall.

**Hardware**: AMD Ryzen 7 9700X + RX 6750 XT + 64GB RAM
**Setup**: Dual-boot with Windows 11 on separate NVMe drives

Integrates with your existing dotfiles: https://github.com/NullSense/dotfiles

## Dual-Boot Strategy (Separate Drives)

Since Windows 11 is on a separate NVMe, this is the **ideal** dual-boot setup:

- Each drive has its **own ESP** (EFI System Partition)
- Windows **cannot** overwrite Arch's bootloader
- Just set boot order in BIOS to prefer Arch drive
- Press F12/F8 (varies by mobo) to switch between drives

**No need for multiple ESPs on the Arch drive** - the separation is physical.

## Pre-Installation

1. Download Arch ISO from https://archlinux.org/download/
2. Create bootable USB: `dd bs=4M if=archlinux.iso of=/dev/sdX status=progress`
3. Boot from USB (disable Secure Boot in BIOS)
4. **Important**: Verify UEFI mode: `cat /sys/firmware/efi/fw_platform_size` should return `64`

## Installation Steps

### 1. Connect to Internet
```bash
# For Wi-Fi
iwctl
station wlan0 connect "YourNetwork"

# Verify
ping -c 3 archlinux.org
```

### 2. Copy Config Files to Live Environment
From another machine, copy these files to the live USB or fetch them:
```bash
# Option A: Fetch from your repo/gist
curl -LO https://your-url/disk-layout.json
curl -LO https://your-url/user_configuration.json
curl -LO https://your-url/user_credentials.json

# Option B: Mount USB with configs
mount /dev/sdb1 /mnt
cp /mnt/arch-install/*.json .
umount /mnt
```

### 3. Edit Credentials (IMPORTANT!)
```bash
nano user_credentials.json
# Change "CHANGE_ME" to your actual passwords
```

### 4. Identify Your NVMe Drive
```bash
lsblk
# Should show nvme0n1 (2TB = ~1.8TiB)
```

If your NVMe is NOT `/dev/nvme0n1`, edit `disk-layout.json`:
```bash
nano disk-layout.json
# Change "device": "/dev/nvme0n1" to your actual device
```

### 5. Run Archinstall
```bash
archinstall --config user_configuration.json \
            --disk-layout disk-layout.json \
            --creds user_credentials.json
```

### 6. Reboot
```bash
reboot
```

## Post-Installation

After first boot, login as your user and run:
```bash
curl -LO https://raw.githubusercontent.com/NullSense/dotfiles/main/post-install.sh
chmod +x post-install.sh
./post-install.sh
```

Or manually:
```bash
# Install chezmoi and apply dotfiles
sudo pacman -S chezmoi
chezmoi init --apply https://github.com/NullSense/dotfiles.git

# Set zsh as default
chsh -s /usr/bin/zsh

# Start sway
sway
```

## Btrfs Subvolume Layout

| Subvolume | Mountpoint | Purpose |
|-----------|------------|---------|
| @ | / | Root filesystem |
| @home | /home | User data |
| @snapshots | /.snapshots | Snapper snapshots |
| @log | /var/log | System logs (excluded from snapshots) |
| @pkg | /var/cache/pacman/pkg | Package cache (excluded from snapshots) |
| @swap | /swap | Swapfile location |

Mount options: `compress=zstd:3,noatime,ssd,discard=async,space_cache=v2`

## Included Packages

- **Sway**: Tiling Wayland compositor (i3-compatible)
- **Waybar**: Status bar
- **Wofi**: Application launcher
- **Alacritty/Foot**: Terminal emulators
- **Mako**: Notification daemon
- **Grim/Slurp**: Screenshots
- **PipeWire**: Audio
- **NetworkManager**: Network management

## Troubleshooting

### Sway won't start
```bash
# Check for errors
sway -d 2>&1 | head -50

# For NVIDIA (not recommended with Sway)
sway --unsupported-gpu
```

### No sound
```bash
systemctl --user enable --now pipewire pipewire-pulse wireplumber
```

### Snapper not working
```bash
sudo snapper -c root create-config /
sudo systemctl enable --now snapper-timeline.timer
```

## systemd-boot (What archinstall sets up)

The config uses `systemd-bootctl` as the bootloader (not GRUB). Here's what archinstall configures:

### Boot Partition Layout
```
/boot/                          # ESP (EFI System Partition) - 1GB FAT32
├── EFI/
│   ├── BOOT/
│   │   └── BOOTX64.EFI        # Fallback bootloader
│   └── systemd/
│       └── systemd-bootx64.efi # systemd-boot EFI binary
├── loader/
│   ├── loader.conf             # Boot menu config
│   └── entries/
│       └── arch.conf           # Arch Linux boot entry
├── vmlinuz-linux               # Kernel
├── initramfs-linux.img         # Initramfs
└── initramfs-linux-fallback.img
```

### Key Files

**`/boot/loader/loader.conf`**:
```ini
default arch.conf
timeout 3
console-mode max
editor no
```

**`/boot/loader/entries/arch.conf`**:
```ini
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=xxx rw rootflags=subvol=@
```

### Why systemd-boot over GRUB?

| Feature | systemd-boot | GRUB |
|---------|-------------|------|
| Speed | Faster boot | Slower |
| Config | Simple text files | Complex grub.cfg |
| UEFI only | Yes | No (supports BIOS) |
| Btrfs snapshots | Manual entries | grub-btrfs auto-detects |
| Complexity | Minimal | Feature-rich |

### Managing Boot Entries

```bash
# Check status
bootctl status

# List entries
bootctl list

# Update after kernel upgrade (usually automatic via hook)
bootctl update

# Add a new entry
sudo nvim /boot/loader/entries/arch-fallback.conf
```

### After Installation - Kernel Updates

systemd-boot auto-updates via pacman hook. If you need manual update:
```bash
sudo bootctl update
```

### Optional: Add Btrfs Snapshot Boot Entries

If you want to boot into snapshots (like GRUB + grub-btrfs), you'll need to manually create entries or use a tool like `snap-pac-grub` alternative for systemd-boot.

## Windows Dual-Boot Protection

Windows updates can break systemd-boot by:
1. **Overwriting EFI boot order** (most common)
2. **Resetting default bootloader**
3. **Corrupting shared ESP** (if Fast Startup enabled)

### Prevention

**Before installing Windows (if dual-booting):**
1. Install Windows FIRST, then Arch
2. Use separate ESPs if possible (Windows on its own, Arch on its own)
3. Or share ESP but be prepared to fix boot order

**After Windows is installed:**
```bash
# Disable Fast Startup in Windows (CRITICAL!)
# Control Panel > Power Options > Choose what power buttons do
# > Change settings currently unavailable
# > Uncheck "Turn on fast startup"
```

### If Windows Breaks Your Boot

Use the included `fix-boot-after-windows.sh` from an Arch live USB:

```bash
# Boot Arch live USB, then:
curl -LO https://your-url/fix-boot-after-windows.sh
chmod +x fix-boot-after-windows.sh
sudo ./fix-boot-after-windows.sh
```

**Quick manual fix:**
```bash
# From Arch live USB
efibootmgr  # List boot entries

# Set Linux Boot Manager first
efibootmgr --bootorder 0001,0000  # Adjust numbers as needed
```

**Nuclear option - use fallback path:**
```bash
# Makes systemd-boot the UEFI fallback (more Windows-resistant)
mount /dev/nvme0n1p1 /mnt
cp /mnt/EFI/systemd/systemd-bootx64.efi /mnt/EFI/BOOT/BOOTX64.EFI
umount /mnt
```

## Enabled Systemd Timers

The post-install script enables these maintenance timers:

| Timer | Package | Frequency | Purpose |
|-------|---------|-----------|---------|
| `fstrim.timer` | util-linux | Weekly | SSD TRIM for NVMe longevity |
| `paccache.timer` | pacman-contrib | Weekly | Clean old package cache |
| `man-db.timer` | man-db | Daily | Update man page index |
| `plocate-updatedb.timer` | plocate | Daily | Update file database for `locate` |
| `logrotate.timer` | logrotate | Daily | Rotate system logs |
| `reflector.timer` | reflector | Weekly | Update pacman mirrorlist |
| `snapper-timeline.timer` | snapper | Hourly | Create btrfs snapshots |
| `snapper-cleanup.timer` | snapper | Daily | Clean old snapshots |

Check timer status:
```bash
systemctl list-timers --all
```

## Pacman Configuration

The post-install enables these in `/etc/pacman.conf`:
- `Color` - Colored output
- `ParallelDownloads = 5` - Faster downloads
- `VerbosePkgLists` - Show old/new versions during upgrades

## Hardware Optimization (Ryzen 9700X + RX 6750 XT)

Run `hardware-optimize.sh` after post-install for:

### CPU (Zen 5)
- **AMD P-State driver** for efficient frequency scaling
- Kernel parameter: `amd_pstate=active`

### RAM (64GB)
- **zram** with zstd compression (16GB compressed swap)
- Better than disk swap for high-RAM systems
- Optimized vm.swappiness for zram

### GPU (RDNA2)
- Full Vulkan/Mesa stack with 32-bit libs
- **CoreCtrl** and **LACT** for overclocking
- Kernel parameter for OC: `amdgpu.ppfeaturemask=0xffffffff`

### Gaming
- **Steam** with **Proton** support
- **GameMode** for automatic CPU/GPU optimization
- **MangoHud** for FPS overlay
- **Gamescope** for better Wayland gaming

**Kernel parameters to add** (`/boot/loader/entries/arch.conf`):
```
options root=PARTUUID=xxx rw rootflags=subvol=@ amd_pstate=active zswap.enabled=0 amdgpu.ppfeaturemask=0xffffffff
```

## Development Environment (mise)

Run `dev-environment.sh` for a clean dev setup:

### Why mise over asdf/nvm/pyenv?
- **Single tool** replaces asdf + direnv + nvm + pyenv + rustup
- **Per-project configs** in `.mise.toml` (not in .zshrc)
- **Automatic switching** when you cd into projects
- **Task runner** built-in

### Usage
```bash
# Global tools
mise use --global node@lts python@3.12 rust@stable

# Project-specific (creates .mise.toml)
cd my-expo-app
mise use node@20

# Project env vars (in .mise.toml)
[env]
EXPO_DEBUG = "true"
API_KEY = "xxx"
```

### For Expo.dev
```bash
mkdir my-app && cd my-app
mise use node@20
npx create-expo-app .
# mise auto-switches Node when you enter this directory
```

## Files Overview

| File | Purpose |
|------|---------|
| `disk-layout.json` | Btrfs NVMe layout |
| `user_configuration.json` | Packages + profile |
| `user_credentials.json` | Passwords (edit!) |
| `post-install.sh` | Dotfiles + timers |
| `hardware-optimize.sh` | CPU/GPU/RAM tuning |
| `dev-environment.sh` | mise + dev tools |
| `fix-boot-after-windows.sh` | Boot recovery |

## Installation Order

```bash
# 1. Boot Arch USB, run archinstall with configs
# 2. Reboot into new system
./post-install.sh        # Dotfiles, timers, AUR
./hardware-optimize.sh   # CPU, GPU, zram, gaming
./dev-environment.sh     # mise, Node, Python, Rust
# 3. Reboot for all changes
```

## Color Calibration (DisplayCAL / ICC Profiles)

**Important**: Sway currently **does not have native ICC color management**. This is a known limitation.

### Options for MAG274QRF-QD

1. **Monitor's built-in calibration**: Use the OSD to load sRGB or Adobe RGB presets
2. **Hardware LUT loading** (partial): Use `dispwin` from ArgyllCMS
3. **Wait for Sway 2.0**: Color management is in development (wlroots has merged support)
4. **Alternative**: Use KDE Plasma Wayland for color-critical work (has full ICC support)

### Using dispwin (Workaround)

```bash
# Install ArgyllCMS
sudo pacman -S argyllcms

# Load your existing ICC profile to GPU LUT
# Copy your .icm/.icc file from Windows first
dispwin -d 1 ~/path/to/MAG274QRF-QD.icm

# Add to sway startup (partial effect only)
# exec dispwin -d 1 ~/path/to/MAG274QRF-QD.icm
```

**Limitations**: This only loads 1D LUT curves to the GPU. Full ICC support (3D LUT, per-app profiles) is not available in Sway yet.

### Creating New Profile on Linux

```bash
# Install DisplayCAL (fork that works on Wayland)
paru -S displaycal

# Run calibration (will create ICC profile)
displaycal
```

**Note**: DisplayCAL on Wayland has some bugs. For best results, calibrate on Windows and copy the .icm file.

## Mouse Sensitivity (Logitech)

The sway config is set up to match Windows:

- **Acceleration**: Flat (no acceleration = Windows "Enhance pointer precision" OFF)
- **Sensitivity**: 0.0 (equivalent to Windows 6th tick)

To adjust sensitivity:
```bash
# Edit ~/.config/sway/config
# Find "input type:pointer" section
# Change pointer_accel value: -1.0 (slowest) to 1.0 (fastest)
```

Your Logitech mouse DPI is stored in the mouse itself, so it will be the same as Windows.

## Font Rendering (1440p)

Fontconfig is set up for 27" 1440p (109 PPI):
- Subpixel rendering (RGB)
- Slight hinting
- LCD filter (lcdlight)

Located at: `~/.config/fontconfig/fonts.conf`

## Sources

- [Arch Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Archinstall](https://wiki.archlinux.org/title/Archinstall)
- [systemd-boot - ArchWiki](https://wiki.archlinux.org/title/Systemd-boot)
- [Ryzen - ArchWiki](https://wiki.archlinux.org/title/Ryzen)
- [AMDGPU - ArchWiki](https://wiki.archlinux.org/title/AMDGPU)
- [zram - ArchWiki](https://wiki.archlinux.org/title/Zram)
- [Improving performance - ArchWiki](https://wiki.archlinux.org/title/Improving_performance)
- [mise - GitHub](https://github.com/jdx/mise)
- [Btrfs - ArchWiki](https://wiki.archlinux.org/title/Btrfs)
- [Sway - ArchWiki](https://wiki.archlinux.org/title/Sway)
