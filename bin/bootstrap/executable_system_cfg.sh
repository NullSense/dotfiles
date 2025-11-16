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

# --- 6. Enable user systemd services ---
echo "INFO: Enabling user systemd services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || echo "Pipewire services may already be running"

# --- 7. Enable firewall (optional) ---
if pacman -Qs ufw &> /dev/null; then
    echo "INFO: UFW firewall detected. Enabling and configuring..."
    sudo systemctl enable --now ufw
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    echo "UFW firewall is now active (deny incoming, allow outgoing)."
else
    echo "INFO: UFW not installed. Skipping firewall setup."
    echo "      Note: A firewall is optional on desktop Linux but recommended if you:"
    echo "      - Connect to public WiFi frequently"
    echo "      - Run local servers (web, SSH, etc.)"
    echo "      - Want extra security layer"
    echo "      Install with: sudo pacman -S ufw"
fi

# --- 8. Set default shell to zsh ---
if command -v zsh &> /dev/null; then
    CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
    ZSH_PATH=$(which zsh)
    if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
        echo "INFO: Changing default shell to zsh..."
        chsh -s "$ZSH_PATH"
        echo "Default shell changed to zsh. Please log out and log back in for changes to take effect."
    else
        echo "INFO: Default shell is already zsh."
    fi
else
    echo "WARNING: zsh not found. Skipping shell change."
fi

# --- 9. Install udev rules for I/O scheduler ---
echo "INFO: Installing I/O scheduler udev rules..."
if [ -f "$HOME/.local/share/chezmoi/root/etc/udev/rules.d/60-ioschedulers.rules" ]; then
    sudo cp "$HOME/.local/share/chezmoi/root/etc/udev/rules.d/60-ioschedulers.rules" /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    echo "I/O scheduler rules installed and activated."
else
    echo "WARNING: I/O scheduler rules file not found."
fi

echo "🎉 Generic System Configuration script finished."
echo "A reboot might be required for all changes (like locale) to take full effect system-wide."
