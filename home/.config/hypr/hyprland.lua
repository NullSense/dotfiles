-- Hyprland main config (Lua, 0.55+). Replaces the hyprlang hyprland.conf + its `source =` tree.
--
-- Modular: each concern lives in lua/<name>.lua, loaded with require() (each require is its own
-- error scope, so one broken module does not abort the rest -- see wiki.hypr.land/Configuring/Core).
-- Variables ($mod, colors, ...) live in lua/vars.lua.
--
-- Goal (unchanged): faithful sway -> Hyprland translation, preserving every keybind and
-- window rule, native auto-HDR, hypridle instead of swayidle, native monitors instead of kanshi.
--
-- Reference docs: https://wiki.hypr.land/

-- --- Omarchy upstream defaults (VENDORED snapshot, see lua/omarchy/*.lua headers) --------------
-- The hyprlang config `source`d the live omarchy files; Lua cannot read .conf, so the snapshot
-- below was converted once. Menu/media/clipboard/utility binds, default window rules, envs.
-- Skipped on purpose (same as before): omarchy tiling-v2 binds (conflict with our hjkl binds)
-- and omarchy looknfeel.conf (fully overridden by lua/looknfeel.lua).
require("lua.omarchy.autostart")
require("lua.omarchy.binds_media")
require("lua.omarchy.binds_clipboard")
require("lua.omarchy.binds_utilities")
require("lua.omarchy.envs")
require("lua.omarchy.input")
require("lua.omarchy.windows")

-- NOT carried over: ~/.config/omarchy/current/theme/hyprland.conf (only sets general.col.active_border
-- and group.col.border_active to the theme accent; lua/looknfeel.lua overrides both afterwards anyway)
-- and ~/.local/state/omarchy/toggles/hypr/*.conf (omarchy-toggle-* drop hyprlang files there; only
-- the placeholder exists today).

-- --- OUR overrides (must come after omarchy so we win on conflicts) ----------
-- - env:        Wayland env exports
-- - monitors:   DP-1 4K@240 10-bit, DP-2 1440p@120, per-monitor workspaces, special workspaces
-- - input:      mouse/touchpad tuning
-- - looknfeel:  gruvbox border colors, animations, layer rules
-- - windows:    per-app rules
-- - bindings:   hyprwhspr push-to-talk + our $mod binds
-- - autostart:  startup phases
require("lua.env")
require("lua.monitors")
require("lua.input")
require("lua.looknfeel")
require("lua.windows")
require("lua.bindings")
require("lua.autostart")

-- --- Misc one-liners that don't fit a section --------------------------------
-- Match sway's `focus_follows_mouse no`.

hl.config({
    general = {
        no_focus_fallback = false,
    },
    misc = {
        focus_on_activate = true,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        -- `misc:vfr` removed in Hyprland 0.55.x — VFR is now unconditional.
        -- Adaptive sync for fullscreen apps, with video apps excluded by no_vrr
        -- rules in windows.conf to prevent OLED brightness flicker. Mode 3 also
        -- allows tagged video and misses games that don't advertise a content type.
        vrr = 2,
        -- Sway equivalent: focus_follows_mouse no
        mouse_move_focuses_monitor = true,
    },
    input = {
        follow_mouse = 0, -- = focus_follows_mouse no
        -- Even with follow_mouse=0, floating windows still steal focus when the
        -- cursor passes over them (this is the default `=1`). That's what made the
        -- pinned/floating mpv grab focus on hover. 0 = never override focus for floats.
        float_switch_override_focus = 0,
    },
    -- Pinned (sticky) windows can't go fullscreen by default — Hyprland rejects the
    -- request, which is why SUPER+F / SUPER+CTRL+F *and* mpv's own `f` did nothing on
    -- the floating+pinned mpv (windows.conf pins mpv via `pin on`). Enabling this let
    -- a pinned window fullscreen without first unpinning. (Hyprland #1147)
    --
    -- DISABLED 2026-06-06 — this was the direct trigger of a hard Hyprland crash.
    -- Maximizing the pinned+floating mpv fired a client fullscreen request
    -- (CWindow::onUpdateState -> changeWindowFullscreenModeClient) that reaches the
    -- new 0.55 layout engine's Layout::CAlgorithm::recalculate(), which throws an
    -- uncaught std::bad_variant_access -> SIGABRT. Crashed 3x on 2026-06-06 (crash
    -- reports 3908/3694553/3714436). NOT an HDR/color-mgmt bug — backtrace is purely
    -- in the layout/fullscreen path; cm_auto_hdr is off. Known unfixed upstream regression
    -- in 0.55.2 (latest stable): hyprwm/Hyprland discussion #14314 — bad_variant_access
    -- in CAlgorithm::recalculate on fixed-size/fullscreen windows.
    -- Setting this back to default (false) makes Hyprland reject the pinned-window
    -- fullscreen request *before* the buggy recalculate, restoring the safe no-op.
    -- To actually watch fullscreen: unpin first (or use SUPER+SHIFT+F fake-fullscreen,
    -- which keeps the window pinned and does not hit the crashing recalculate path).
    -- Re-enable once on a Hyprland build that fixes #14314.
    binds = {
        allow_pin_fullscreen = false,
        -- Focus tabs before leaving the group. Hyprland's own description:
        -- "when in a grouped window, movefocus will cycle windows in the groups
        -- first". Without it SUPER+H/L jumped straight past a 4-tab group to the
        -- neighbouring tile, and the only way to reach the other tabs was
        -- SUPER+[ / ]. This makes hjkl walk the tabs first, then continue out —
        -- i3's behaviour, and the focus counterpart to ~/bin/hypr-move, which does
        -- the same for SUPER+SHIFT+hjkl.
        movefocus_cycles_groupfirst = true,
    },
})


