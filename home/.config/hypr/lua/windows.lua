-- Window rules — translates sway `for_window` to Hyprland 0.54 syntax.
--
-- Hyprland 0.54.x window rule syntax (current, post-deprecation):
--   windowrule = ACTION [VALUE], match:KEY VALUE [, match:KEY2 VALUE2 ...]
--
-- Notes vs older docs:
--   - Drop regex anchors: `class:^(foo)$` → `match:class foo`
--   - On/off rules need explicit `on`: `float` → `float on`
--   - Match conditions go in `match:KEY VALUE` form (space, no colon)
--
-- `inhibit_idle fullscreen` from sway is handled by hypridle's
-- `inhibit_sources = audio` instead.

-- --- Special workspaces / dropdown -------------------------------------------
-- Dropdown terminal — toggled by $mod+u, spawned by dropdown-terminal.service
-- as `ghostty --gtk-single-instance=false --class=com.mitchellh.ghostty-dropdown`.
-- Keep this valid GTK app ID consistent with the service and child escape rule.
-- `silent` is required on the workspace rule — without it `togglespecial`
-- focus-glitches when systemd's Restart=always races a respawn.
hl.window_rule({
    match = {
        class = "com.mitchellh.ghostty-dropdown",
    },
    workspace = "special:dropdown silent",
    float = true,
    size = "1400 900",
    center = true,
})

-- A special workspace is an overlay, but Hyprland otherwise treats it as the
-- focused placement target. Route every other window mapped while the dropdown
-- has focus to the normal workspace underneath it. `m+0` resolves to the
-- current regular workspace on that monitor; later app-specific rules can still
-- override this (for example, Signal -> workspace 3 or mpv -> special:floats).
hl.window_rule({
    match = {
        workspace = "special:dropdown",
        class = "negative:com\\.mitchellh\\.ghostty-dropdown",
    },
    workspace = "m+0 silent",
})

-- Spotify scratchpad — same dropdown pattern as ghostty (the ghostty
-- block above): workspace + float on + size + center 1. The previous
-- rule only set workspace, so Spotify ended up un-centered at [0,0].
-- Same `match:class Spotify` selector — verified via hyprctl clients -j.
hl.window_rule({
    match = {
        class = "Spotify",
    },
    workspace = "special:spotify silent",
    float = true,
    size = "1500 950",
    center = true,
})

-- Media downloader popup — grab-menu (SUPER+ALT+G) opens its fzf pickers in
-- Ghostty with the stable app ID com.mitchellh.ghostty-grab. Float + center on the CURRENT workspace (no
-- scratchpad) so the picker pops up over your work.
hl.window_rule({
    match = {
        class = "com.mitchellh.ghostty-grab",
    },
    float = true,
    size = "1500 950",
    center = true,
})

-- Floats scratchpad — OPT-IN allow-list (toggle with SUPER+CTRL+U; send any
-- window on demand with SUPER+CTRL+SHIFT+U).
--
-- Design note — why an allow-list and NOT `match:float true` (all floats):
-- app dialogs (file pickers, progress/confirm popups) open *floating* and share
-- their parent app's class. A catch-all "all floats → special:floats" therefore
-- inhales those dialogs into the hidden scratchpad, so the app looks dead when
-- you click a button. We kept patching that with a `negative:` deny-list, but it
-- was unbounded — EVERY new GUI app's dialogs broke until added (transmission-qt,
-- PrismLauncher, Lutris, ...). Hyprland has no reliable "is-a-dialog" matcher
-- (`match:modal` only catches modal popups; most of these are non-modal), so the
-- robust fix is to invert the default: route ONLY the windows we deliberately
-- float (each also has its own `float on` rule below) into the scratchpad. New
-- apps default to VISIBLE — add a class here only if you WANT it stashed.
-- satty is deliberately NOT here: the screenshot flow spawns it on demand
-- (notification click / edit bind) and `silent` made it open invisible in the
-- scratchpad — users piled up hidden instances thinking the editor never
-- launched. It keeps its float/size/center rules below but opens visible.
hl.window_rule({
    match = {
        class = "^(mpv|imv|clipboard-picker|screenshot-picker|com\\.local\\.floating-monitor|floating-monitor)$",
    },
    workspace = "special:floats silent",
})

-- Attention indicator — tag-based, agent-agnostic. Each agent's hook
-- (~/.claude/hooks/attention.sh and analogues) runs `hyprctl dispatch
-- tagwindow +attention-<agent-id> address:0x...` on its own terminal
-- window. We match the tag here and paint a red border. Tag-based instead
-- of title-sentinel because Claude Code's TUI manages its own window title
-- and overwrites OSC-2 sentinels within ms — tags are out-of-band and
-- survive any title rewrite.
hl.window_rule({
    match = {
        tag = "attention-claude",
    },
    border_color = "rgb(FF3344) rgb(880808)",
})

hl.window_rule({
    match = {
        tag = "attention-codex",
    },
    border_color = "rgb(FF3344) rgb(880808)",
})

hl.window_rule({
    match = {
        tag = "attention-opencode",
    },
    border_color = "rgb(FF3344) rgb(880808)",
})

hl.window_rule({
    match = {
        tag = "attention-gemini",
    },
    border_color = "rgb(FF3344) rgb(880808)",
})

hl.window_rule({
    match = {
        tag = "attention-copilot",
    },
    border_color = "rgb(FF3344) rgb(880808)",
})

-- --- Idle inhibit ------------------------------------------------------------
-- Fullscreen video/games keep the session awake (no dim/lock/power-off mid-movie). Compositor-level
-- Wayland idle-inhibit, honoured by hypridle (ignore_systemd_inhibit/dbus stay false). Scoped to
-- media/game classes so a static fullscreen terminal still dims (OLED burn-in).
hl.window_rule({
    match = {
        class = "^(helium|mpv|steam_app_.*)$",
    },
    idle_inhibit = "fullscreen",
})

-- --- OLED VRR flicker ---------------------------------------------------------
-- Fullscreen video triggered visible brightness flicker on the AORUS FO32U2;
-- disabling VRR resolved it. Keep these apps at fixed refresh while misc:vrr=2
-- continues to allow adaptive sync for fullscreen games.
hl.window_rule({
    match = {
        class = "^(helium|mpv)$",
    },
    no_vrr = true,
})

-- --- Floating + sticky for media-style apps ----------------------------------
hl.window_rule({
    match = {
        class = "mpv",
    },
    float = true,
    pin = true,
})

hl.window_rule({
    match = {
        class = "imv",
    },
    float = true,
})

-- Satty's actual class is com.gabm.satty (verified via hyprctl clients).
-- `match:class satty` would silently fail to match.
hl.window_rule({
    match = {
        class = "com.gabm.satty",
    },
    float = true,
    size = "1400 900",
    center = true,
})

-- tev — HDR/10-bit image viewer launched from yazi via ~/bin/tev-fit.
-- Class is bare `tev` (GLFW, verified via hyprctl clients -j). Must float so
-- tev-fit can resize it to the image's pixels (or fullscreen it for large
-- images); center 1 is the pre-size fallback. Deliberately NOT in the
-- floats-scratchpad allow-list (line ~61) so it opens visible, not stashed.
hl.window_rule({
    match = {
        class = "tev",
    },
    float = true,
    center = true,
})

-- --- Pickers (clipboard/screenshot) — large floating ------------------------
-- Capture dialogs open above the current workspace without disturbing tiling.
-- Separate GTK app IDs let the audio picker stay compact and review stay large.
hl.window_rule({
    match = { class = "local\\.screenrecord\\.Review" },
    float = true,
    size = "(monitor_w*0.65) (monitor_h*0.88)",
    center = true,
})

hl.window_rule({
    match = { class = "local\\.screenrecord\\.Audio" },
    float = true,
    center = true,
})

hl.window_rule({
    match = {
        class = "clipboard-picker",
    },
    float = true,
    size = "(monitor_w*0.5) (monitor_h*0.4)",
    center = true,
})

hl.window_rule({
    match = {
        class = "screenshot-picker",
    },
    float = true,
    size = "(monitor_w*0.4) (monitor_h*0.25)",
    center = true,
})

-- floating-monitor — used by waybar click handlers to spawn btop/htop/etc.
-- Ghostty needs a valid reverse-DNS GTK app ID; old foot used the bare
-- `floating-monitor` string. Both names match here so any leftover spawns
-- from old binaries also get the rule.
hl.window_rule({
    match = {
        class = "com.local.floating-monitor",
    },
    float = true,
    size = "(monitor_w*0.6) (monitor_h*0.6)",
    center = true,
})

hl.window_rule({
    match = {
        class = "floating-monitor",
    },
    float = true,
    size = "(monitor_w*0.6) (monitor_h*0.6)",
    center = true,
})

-- --- Problematic / utility apps ----------------------------------------------
hl.window_rule({
    match = {
        class = "electrum",
    },
    float = true,
    size = "1280 720",
})

hl.window_rule({
    match = {
        class = "pavucontrol",
    },
    float = true,
    size = "1280 720",
})

hl.window_rule({
    match = {
        class = "nm-connection-editor",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "blueman-manager",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "gnome-calculator",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "org.gnome.Calculator",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "io.gpu-screen-recorder.GPUScreenRecorder",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "org.gnome.FileRoller",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "org.kde.ark",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "thunar",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "file-roller",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "xdg-desktop-portal-gtk",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "wlogout",
    },
    float = true,
})

-- Picture-in-Picture popups float, pinned, top-right
hl.window_rule({
    match = {
        title = "Picture-in-Picture",
    },
    float = true,
    pin = true,
    size = "480 270",
    move = "(monitor_w-500) (monitor_h-290)",
})

hl.window_rule({
    match = {
        title = "Polkit",
    },
    float = true,
})

hl.window_rule({
    match = {
        title = "File Operation Progress",
    },
    float = true,
})

hl.window_rule({
    match = {
        title = "Sharing Indicator",
    },
    float = true,
    pin = true,
})

-- --- Chat apps → workspace 3 (vertical MSI) ----------------------------------
hl.window_rule({
    match = {
        class = "Signal",
    },
    workspace = "3 silent",
})

hl.window_rule({
    match = {
        class = "signal",
    },
    workspace = "3 silent",
})

hl.window_rule({
    match = {
        class = "discord",
    },
    workspace = "3 silent",
})

hl.window_rule({
    match = {
        class = "TelegramDesktop",
    },
    workspace = "3 silent",
})

hl.window_rule({
    match = {
        class = "org.telegram.desktop",
    },
    workspace = "3 silent",
})

-- --- Center + size for browser dialogs ---------------------------------------
hl.window_rule({
    match = {
        class = "Navigator",
    },
    center = true,
    size = "1080 720",
})

-- --- Decoration tweaks ------------------------------------------------------
-- noshadow / noblur as windowrule actions were renamed/removed in 0.54.x.
-- Decoration scope is now controlled at the global level (see looknfeel.conf
-- `decoration { blur { ... } shadow { ... } }`). Inactive-only blur is
-- achieved by setting `inactive_opacity` differently or via layer rules.
-- We accept blur/shadow on all windows for now — it's subtle anyway.

-- --- Fullscreen visual indicators -------------------------------------------
-- Hyprland renders fullscreen states identically to a regular tiled window
-- unless we differentiate them. Common pain point per upstream wiki +
-- discussion #13095: SUPER+F (maximize, mode 1) keeps the bar + gaps and is
-- hard to distinguish at a glance, and SUPER+SHIFT+F (fake-fullscreen for
-- screensharing) is even more invisible — nothing about geometry changes.
--
-- Standard solution: per-state windowrule bumping `border_size` and
-- `border_color` so the active fullscreen mode is unmistakable.
--
--   internal 1                  → maximize (SUPER+F, daily use)
--                                 4px nullsense gold (#fabd2f / #d79921)
--   internal 0 + client 2       → fake fullscreen (SUPER+SHIFT+F, sharing)
--                                 4px magenta — also a "you're sharing" cue
--   internal 2                  → exclusive fullscreen (SUPER+CTRL+F)
--                                 No rule — bar/gaps already disappear, the
--                                 visual change is unmistakable on its own.
--
-- Known issue (Hyprland #13095, Jan 2026, still present in 0.54.3): the
-- rule occasionally fails to reset when leaving fullscreen. Workaround:
-- declare each rule twice (once single-color, once active+inactive). If
-- you see stuck borders, swap to the duplicated form below.
hl.window_rule({
    match = {
        fullscreen_state_internal = 1,
    },
    border_size = 4,
    border_color = "rgb(fabd2f) rgb(d79921)",
})

hl.window_rule({
    match = {
        fullscreen_state_internal = 0,
        fullscreen_state_client = 2,
    },
    border_size = 4,
    border_color = "rgb(d3869b) rgb(b16286)",
})

-- ----- Split preselect indicator (SUPER+V) ----------------------------------
-- i3 draws a split indicator on the container showing where the next window
-- lands. Hyprland renders nothing for this — of the 353 options in 0.56.2 the
-- only split-related ones (force_split, preserve_split, smart_split,
-- permanent_direction_override, split_bias …) all control *behaviour*, none
-- draw anything, and upstream #9187 "Directional split and visualization" is
-- still open. So we draw it, but declaratively, the same way the fullscreen
-- states above are drawn — no colours hardcoded in a script.
--
-- ~/bin/hypr-preselect only tags the window (`dispatch tagwindow +psel-<dir>`);
-- everything visual lives here, themeable alongside the rest of your styling.
--
-- i3 paints a SOLID bar on exactly one border side (src/x.c, x_draw_decoration:
-- L_SPLITH -> right border, L_SPLITV -> bottom border, in the `indicator` colour
-- from the client.focused line). Hyprland has no per-side border colour, so the
-- nearest equivalent is a gradient — but a plain 2-stop fade smears the cue
-- across the whole window, which reads nothing like i3.
--
-- Fix: 4 transparent stops then 1 solid. The shader interpolates between evenly
-- spaced stops, so the border stays fully transparent for the first ~75% and
-- ramps to solid only over the last quarter — a bar concentrated on the target
-- edge, close to i3's look, while still legal Hyprland gradient syntax (the
-- shader takes up to 10 stops; 2/3/5 all verified to parse).
--
-- The angle IS the direction, with the last stop landing on that edge — read off
-- src/render/shaders/glsl/gradient.glsl, getOkColorForCoordArray1:
--   progress = y*sin(a) + x*(1-sin(a)), gradient[0] at progress 0
--   0deg -> right   90deg -> down   180deg -> left   270deg -> up
--
-- border_size is set here too, not just the colour: general:border_size is 0
-- whenever omarchy's no-gaps toggle is on, and colouring a zero-pixel border
-- draws nothing. Retag/untag makes the rule apply and release, so the window
-- returns to whatever the global value is.
-- Stops are written out longhand rather than hoisted into a `$pselVar`: an
-- unparseable colour in a windowrule does NOT raise a configerror (verified —
-- a deliberately bogus colour was accepted silently), so a variable that failed
-- to expand would fail invisibly. Not worth the brevity.
hl.window_rule({
    match = {
        tag = "psel-r",
    },
    border_size = 4,
    border_color = "rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2fff) 0deg",
})

hl.window_rule({
    match = {
        tag = "psel-d",
    },
    border_size = 4,
    border_color = "rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2fff) 90deg",
})

hl.window_rule({
    match = {
        tag = "psel-l",
    },
    border_size = 4,
    border_color = "rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2fff) 180deg",
})

hl.window_rule({
    match = {
        tag = "psel-u",
    },
    border_size = 4,
    border_color = "rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2f00) rgba(fabd2fff) 270deg",
})

