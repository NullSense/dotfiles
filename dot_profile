EDITOR="/usr/bin/nvim"

# Wayland-generic environment (compositor-agnostic).
# XDG_CURRENT_DESKTOP and XDG_SESSION_DESKTOP are set by the launcher
# wrapper (~/bin/start-hyprland) so they reflect the compositor we launch.
export XDG_SESSION_TYPE=wayland
export WLR_RENDERER=vulkan          # Vulkan renderer (ICC + HDR support)
export MOZ_ENABLE_WAYLAND=1         # Firefox native Wayland
export QT_QPA_PLATFORM=wayland      # Qt apps use Wayland
export SDL_VIDEODRIVER=wayland      # SDL games use Wayland
export _JAVA_AWT_WM_NONREPARENTING=1 # Fix Java apps

# LM Studio CLI: PATH is set in ~/.zshenv (zsh's universal env file).

. "$HOME/.cargo/env"
