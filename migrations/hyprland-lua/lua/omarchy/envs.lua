-- VENDORED SNAPSHOT of omarchy default/hypr/envs (omarchy a3aedb0c, converted from hyprlang).
-- The old hyprland.conf `source`d the live file; Lua cannot, so omarchy updates no longer
-- propagate here automatically. Re-diff against ~/.local/share/omarchy after `omarchy` updates.

-- GUM environment variables for styling purposes
-- hyprlang noerror true
require("lua.omarchy.gum_env")
-- hyprlang noerror false

-- Cursor size
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("XCOMPOSEFILE", "~/.XCompose")

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
    -- Use XCompose file
    -- Don't show update on first launch
    ecosystem = {
        no_update_news = true,
    },
})

