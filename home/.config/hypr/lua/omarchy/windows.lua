-- VENDORED SNAPSHOT of omarchy default/hypr/windows (omarchy a3aedb0c, converted from hyprlang).
-- The old hyprland.conf `source`d the live file; Lua cannot, so omarchy updates no longer
-- propagate here automatically. Re-diff against ~/.local/share/omarchy after `omarchy` updates.

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more
-- Hyprland 0.53+ syntax
hl.window_rule({
    match = {
        class = ".*",
    },
    suppress_event = "maximize",
})

-- Tag all windows for default opacity (apps can override with -default-opacity tag)
hl.window_rule({
    match = {
        class = ".*",
    },
    tag = "+default-opacity",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    match = {
        class = "^$",
        title = "^$",
        xwayland = 1,
        float = 1,
        fullscreen = 0,
        pin = 0,
    },
    no_focus = true,
})

-- App-specific tweaks (may remove default-opacity tag)
require("lua.omarchy.apps")

-- Apply default opacity after apps have had a chance to opt out
hl.window_rule({
    match = {
        tag = "default-opacity",
    },
    opacity = "0.97 0.9",
})

