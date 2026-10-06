-- VENDORED SNAPSHOT of omarchy default/hypr/input (omarchy a3aedb0c, converted from hyprlang).
-- The old hyprland.conf `source`d the live file; Lua cannot, so omarchy updates no longer
-- propagate here automatically. Re-diff against ~/.local/share/omarchy after `omarchy` updates.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "compose:caps",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.
        touchpad = {
            natural_scroll = false,
        },
    },
    misc = {
        key_press_enables_dpms = true, -- key press will trigger wake
        mouse_move_enables_dpms = true, -- mouse move will trigger wake
    },
})

