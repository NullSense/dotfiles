#!/usr/bin/env bash
set -euo pipefail

owner_home=${1:?usage: configure-sddm-wayland.sh /absolute/user/home}
case "$owner_home" in
  /*) ;;
  *) echo "owner home must be an absolute path" >&2; exit 2 ;;
esac

source_theme=/usr/share/sddm/themes/sddm-astronaut-theme
theme_root=/usr/local/share/sddm/themes
theme_dir=$theme_root/nullsense-gruvbox
background=$owner_home/.config/omarchy/current/background

[[ -f "$source_theme/Main.qml" ]] || {
  echo "missing source SDDM theme: $source_theme" >&2
  exit 1
}
[[ -f "$background" ]] || {
  echo "missing lock-screen background: $background" >&2
  exit 1
}
command -v weston >/dev/null || {
  echo "weston is required for the SDDM Wayland greeter" >&2
  exit 1
}

install -d -m 0755 "$theme_dir"
cp -a "$source_theme"/. "$theme_dir"/
install -m 0644 "$background" "$theme_dir/Backgrounds/nullsense-lockscreen.jpg"
cp "$theme_dir/Themes/astronaut.conf" "$theme_dir/Themes/nullsense-gruvbox.conf"

sed -i \
  -e 's|^ConfigFile=.*|ConfigFile=Themes/nullsense-gruvbox.conf|' \
  "$theme_dir/metadata.desktop"
sed -i \
  -e 's|^BackgroundPlaceholder=.*|BackgroundPlaceholder="Backgrounds/nullsense-lockscreen.jpg"|' \
  -e 's|^Background=.*|Background="Backgrounds/nullsense-lockscreen.jpg"|' \
  -e 's|^Font=.*|Font="Hack Nerd Font Mono"|' \
  -e 's|^FormPosition=.*|FormPosition="center"|' \
  -e 's|^HeaderTextColor=.*|HeaderTextColor="#ebdbb2"|' \
  -e 's|^DateTextColor=.*|DateTextColor="#ebdbb2"|' \
  -e 's|^TimeTextColor=.*|TimeTextColor="#ebdbb2"|' \
  -e 's|^FormBackgroundColor=.*|FormBackgroundColor="#cc1d2021"|' \
  -e 's|^BackgroundColor=.*|BackgroundColor="#1d2021"|' \
  -e 's|^DimBackgroundColor=.*|DimBackgroundColor="#1d2021"|' \
  -e 's|^LoginFieldBackgroundColor=.*|LoginFieldBackgroundColor="#cc1d2021"|' \
  -e 's|^PasswordFieldBackgroundColor=.*|PasswordFieldBackgroundColor="#cc1d2021"|' \
  -e 's|^LoginFieldTextColor=.*|LoginFieldTextColor="#ebdbb2"|' \
  -e 's|^PasswordFieldTextColor=.*|PasswordFieldTextColor="#ebdbb2"|' \
  -e 's|^UserIconColor=.*|UserIconColor="#fabd2f"|' \
  -e 's|^PasswordIconColor=.*|PasswordIconColor="#fabd2f"|' \
  -e 's|^PlaceholderTextColor=.*|PlaceholderTextColor="#a89984"|' \
  -e 's|^WarningColor=.*|WarningColor="#fb4934"|' \
  -e 's|^LoginButtonTextColor=.*|LoginButtonTextColor="#1d2021"|' \
  -e 's|^LoginButtonBackgroundColor=.*|LoginButtonBackgroundColor="#fabd2f"|' \
  -e 's|^SystemButtonsIconsColor=.*|SystemButtonsIconsColor="#ebdbb2"|' \
  -e 's|^SessionButtonTextColor=.*|SessionButtonTextColor="#ebdbb2"|' \
  -e 's|^HighlightTextColor=.*|HighlightTextColor="#1d2021"|' \
  -e 's|^HighlightBackgroundColor=.*|HighlightBackgroundColor="#fabd2f"|' \
  "$theme_dir/Themes/nullsense-gruvbox.conf"

install -d -m 0755 /etc/sddm.conf.d
cat > /etc/sddm.conf.d/00-nullsense-wayland.conf <<EOF
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=weston --shell=kiosk
SessionDir=/usr/share/wayland-sessions

[Theme]
ThemeDir=$theme_root
Current=nullsense-gruvbox
EOF

# Remove the old Omarchy fragment so there is one authoritative display-server
# selection rather than two lexically ordered files.
rm -f /etc/sddm.conf.d/00-omarchy.conf /etc/sddm.conf.d/10-theme.conf
