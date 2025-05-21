#!/bin/bash
# Generic Arch Linux System Configuration Script
# Run with sudo privileges: sudo ./configure_arch_system.sh

set -e # Exit immediately if a command exits with a non-zero status.
echo "🚀 Starting Generic Arch Linux System Configuration..."

# --- 1. Pacman Mirrorlist (Reflector) ---
echo "INFO: Updating pacman mirrorlist with reflector..."
# Adjust --country and other parameters as needed.
# This assumes reflector is installed.
if command -v reflector &> /dev/null; then
    sudo reflector --country "Germany" --latest 10 --age 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    sudo pacman -Syu --noconfirm # Sync with new mirrors
else
    echo "WARNING: reflector command not found. Skipping mirrorlist update."
fi

# --- 2. Locale Configuration ---
echo "INFO: Configuring system locales..."
# This assumes /etc/locale.gen and /etc/locale.conf have been pre-populated
# with desired content (e.g., by copying them from your dotfiles repo or manually).
# Example content for /etc/locale.gen:
#   en_US.UTF-8 UTF-8
# Example content for /etc/locale.conf:
#   LANG=en_US.UTF-8

if [ -f "/etc/locale.gen" ] && [ -f "/etc/locale.conf" ]; then
    locale-gen
    echo "Locales generated based on /etc/locale.gen."
    echo "System language set based on /etc/locale.conf."
else
    echo "WARNING: /etc/locale.gen or /etc/locale.conf not found. Manual locale setup required."
    echo "         Please ensure these files are correctly placed and configured."
    echo "         Example: echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen"
    echo "                  echo 'LANG=en_US.UTF-8' > /etc/locale.conf"
    echo "         Then run 'locale-gen'."
fi

# --- 3. Systemd Timers & Services ---
echo "INFO: Enabling and starting essential systemd timers/services..."

# SSD Trim (package: util-linux, usually core)
systemctl enable --now fstrim.timer

# Pacman Cache Cleaner (package: pacman-contrib)
if pacman -Qs pacman-contrib &> /dev/null; then
    systemctl enable --now paccache.timer
else
    echo "WARNING: pacman-contrib not installed. Skipping paccache.timer setup."
fi

# Man Page Index Updater (package: man-db)
if pacman -Qs man-db &> /dev/null; then
    systemctl enable --now man-db.timer
else
    echo "WARNING: man-db not installed. Skipping man-db.timer setup."
fi

# mlocate Database Updater (package: mlocate)
if pacman -Qs mlocate &> /dev/null; then
    systemctl enable --now updatedb.timer
else
    echo "WARNING: mlocate not installed. Skipping updatedb.timer setup."
fi

# Log Rotation (package: logrotate)
if pacman -Qs logrotate &> /dev/null; then
    systemctl enable --now logrotate.timer
else
    echo "WARNING: logrotate not installed. Skipping logrotate.timer setup."
fi

# --- 4. Pacman Configuration (Optional - if /etc/pacman.conf needs specific settings) ---
# This script assumes /etc/pacman.conf is already correctly configured.
# If you have a standard pacman.conf (e.g., with Color, ParallelDownloads enabled),
# ensure it's placed in /etc/pacman.conf before running this script or handle it manually.
echo "INFO: Pacman configuration in /etc/pacman.conf is assumed to be correct."
echo "      Consider enabling Color, VerbosePkgLists, and ParallelDownloads in it."

# --- 5. Other System Tweaks (Add as needed) ---

# Example: Set timezone (replace 'Your/Timezone' e.g., 'America/New_York')
# TIMEZONE="Your/Timezone"
# if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
#   echo "INFO: Setting timezone to ${TIMEZONE}..."
#   ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
# else
#   echo "WARNING: Timezone ${TIMEZONE} not found. Please set manually using timedatectl."
#   echo "         List timezones with 'timedatectl list-timezones'."
# fi

# Example: Set hostname (replace 'your-hostname')
# NEW_HOSTNAME="your-hostname"
# CURRENT_HOSTNAME=$(hostname)
# if [ "$CURRENT_HOSTNAME" != "$NEW_HOSTNAME" ]; then
#   echo "INFO: Setting hostname to ${NEW_HOSTNAME}..."
#   hostnamectl set-hostname "${NEW_HOSTNAME}"
# else
#   echo "INFO: Hostname is already ${NEW_HOSTNAME}."
# fi
#
chsh -s $(which zsh)

echo "🎉 Generic System Configuration script finished."
echo "A reboot might be required for all changes (like locale) to take full effect system-wide."
