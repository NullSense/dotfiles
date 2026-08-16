#!/bin/sh
# Idempotent bootstrap for Omarchy-owned mutable state. These paths are kept
# outside the dotfile link farm because omarchy-theme-set rewrites them.

set -eu

mkdir -p "$HOME/.config/omarchy/current" "$HOME/.config/omarchy/themed"

# waybar-off toggle — tells omarchy's hyprland autostart to skip its bare
# `exec-once = uwsm-app -- waybar` line, because our systemd waybar.service
# owns waybar lifecycle. Without this we get two waybar processes racing
# the same output. The toggle is just a flag file omarchy probes via
# `omarchy-toggle-enabled waybar-off`.
mkdir -p "$HOME/.local/state/omarchy/toggles"
touch "$HOME/.local/state/omarchy/toggles/waybar-off"

# Wallpaper symlink — omarchy's autostart fires `swaybg -i ~/.config/
# omarchy/current/background -m fill` early in the session. Without this
# target the bar comes up over a black screen (swaybg falls back to
# --color #000000 silently).
if [ -e "$HOME/Pictures/wallpaper.png" ] && [ ! -e "$HOME/.config/omarchy/current/background" ]; then
    ln -snf "$HOME/Pictures/wallpaper.png" "$HOME/.config/omarchy/current/background"
fi

# Render the active theme on first boot so per-app theme files (ghostty
# .conf, alacritty .toml, walker.css, mako.ini, hyprlock.conf, etc.)
# exist for the apps that source/import them. Skipped if a theme is
# already current.
if [ ! -L "$HOME/.config/omarchy/current/theme" ] && [ ! -d "$HOME/.config/omarchy/current/theme" ]; then
    if command -v omarchy-theme-set >/dev/null 2>&1; then
        omarchy-theme-set nullsense >/dev/null 2>&1 || true
    fi
fi
