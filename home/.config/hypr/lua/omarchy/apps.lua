-- VENDORED SNAPSHOT of omarchy default/hypr/apps.conf + apps/*.conf (omarchy a3aedb0c, converted from hyprlang).
-- The old hyprland.conf `source`d the live file; Lua cannot, so omarchy updates no longer
-- propagate here automatically. Re-diff against ~/.local/share/omarchy after `omarchy` updates.

-- apps/1password.conf
hl.window_rule({
    match = {
        class = "^(1[p|P]assword)$",
    },
    no_screen_share = true,
    tag = "+floating-window",
})

-- apps/bitwarden.conf
hl.window_rule({
    match = {
        class = "^(Bitwarden)$",
    },
    no_screen_share = true,
    tag = "+floating-window",
})

-- Bitwarden Chrome Extension
hl.window_rule({
    match = {
        class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default",
    },
    no_screen_share = true,
    tag = "+floating-window",
})

-- apps/browser.conf
-- Browser types
hl.window_rule({
    match = {
        class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)",
    },
    tag = "+chromium-based-browser",
})

hl.window_rule({
    match = {
        class = "([fF]irefox|zen|librewolf)",
    },
    tag = "+firefox-based-browser",
})

hl.window_rule({
    match = {
        tag = "chromium-based-browser",
    },
    tag = "-default-opacity",
})

hl.window_rule({
    match = {
        tag = "firefox-based-browser",
    },
    tag = "-default-opacity",
})

-- Video apps: remove chromium browser tag so they don't get opacity applied
hl.window_rule({
    match = {
        class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)",
    },
    tag = "-chromium-based-browser",
})
-- (hyprlang allowed two `tag` effects in one rule; a Lua table cannot repeat a key, so split)
hl.window_rule({
    match = {
        class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)",
    },
    tag = "-default-opacity",
})

-- Force chromium-based browsers into a tile to deal with --app bug
hl.window_rule({
    match = {
        tag = "chromium-based-browser",
    },
    tile = true,
})

-- Only a subtle opacity change, but not for video sites
hl.window_rule({
    match = {
        tag = "chromium-based-browser",
    },
    opacity = "1.0 0.97",
})

hl.window_rule({
    match = {
        tag = "firefox-based-browser",
    },
    opacity = "1.0 0.97",
})

-- Hide the screen-sharing notification bar (the "Hide" button on it is broken on Wayland)
hl.window_rule({
    match = {
        title = ".*is sharing.*",
    },
    workspace = "special silent",
})

-- apps/hyprshot.conf
-- Remove 1px border around hyprshot screenshots
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true })

-- apps/jetbrains.conf
-- Disable mouse focus (see https://github.com/basecamp/omarchy/pull/5183#issuecomment-4189299971)
hl.window_rule({
    name = "jetbrains-focus",
    match = {
        class = "^(jetbrains-.*)$",
    },
    no_follow_mouse = true,
})

-- apps/localsend.conf
-- Float LocalSend and fzf file picker
hl.window_rule({
    match = {
        class = "(Share|localsend)",
    },
    float = true,
    center = true,
})

hl.window_rule({
    match = {
        class = "localsend",
    },
    size = "1100 700",
})

-- apps/pip.conf
-- Picture-in-picture overlays
hl.window_rule({
    match = {
        title = "(Picture.?in.?[Pp]icture)",
    },
    tag = "+pip",
})

hl.window_rule({
    match = {
        tag = "pip",
    },
    tag = "-default-opacity",
    float = true,
    pin = true,
    size = "600 338",
    keep_aspect_ratio = true,
    border_size = 0,
    opacity = "1 1",
    move = "(monitor_w-window_w-40) (monitor_h*0.04)",
})

-- apps/qemu.conf
hl.window_rule({
    match = {
        class = "qemu",
    },
    tag = "-default-opacity",
    opacity = "1 1",
})

-- apps/retroarch.conf
hl.window_rule({
    match = {
        class = "com.libretro.RetroArch",
    },
    fullscreen = true,
    tag = "-default-opacity",
    opacity = "1 1",
    idle_inhibit = "fullscreen",
})

-- apps/steam.conf
-- Float Steam
hl.window_rule({
    match = {
        class = "steam",
    },
    float = true,
})

hl.window_rule({
    match = {
        class = "steam",
        title = "Steam",
    },
    center = true,
})

hl.window_rule({
    match = {
        class = "steam.*",
    },
    tag = "-default-opacity",
    opacity = "1 1",
})

hl.window_rule({
    match = {
        class = "steam",
        title = "Steam",
    },
    size = "1100 700",
})

hl.window_rule({
    match = {
        class = "steam",
        title = "Friends List",
    },
    size = "460 800",
})

hl.window_rule({
    match = {
        class = "steam",
    },
    idle_inhibit = "fullscreen",
})

-- apps/geforce.conf
hl.window_rule({
    name = "geforce",
    match = {
        class = "GeForceNOW",
    },
    idle_inhibit = "fullscreen",
})

-- apps/moonlight.conf
hl.window_rule({
    name = "moonlight",
    match = {
        class = "com.moonlight_stream.Moonlight",
    },
    fullscreen = true,
    idle_inhibit = "fullscreen",
})

-- apps/system.conf
-- Floating windows
hl.window_rule({
    match = {
        tag = "floating-window",
    },
    float = true,
    center = true,
    size = "875 600",
})

hl.window_rule({
    match = {
        class = "(org.omarchy.bluetui|org.omarchy.impala|org.omarchy.wiremix|org.omarchy.btop|org.omarchy.terminal|org.omarchy.bash|org.gnome.NautilusPreviewer|org.gnome.Evince|com.gabm.satty|Omarchy|About|TUI.float|imv|mpv)",
    },
    tag = "+floating-window",
})

hl.window_rule({
    match = {
        class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)",
        title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
    },
    tag = "+floating-window",
})

hl.window_rule({
    match = {
        class = "org.gnome.Calculator",
    },
    float = true,
})

-- Fullscreen screensaver
hl.window_rule({
    match = {
        class = "org.omarchy.screensaver",
    },
    fullscreen = true,
    float = true,
    animation = "slide",
})

-- No transparency on media windows
hl.window_rule({
    match = {
        class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
    },
    tag = "-default-opacity",
    opacity = "1 1",
})

-- Popped window rounding
hl.window_rule({
    match = {
        tag = "pop",
    },
    rounding = 8,
})

-- Prevent idle while open
hl.window_rule({
    match = {
        tag = "noidle",
    },
    idle_inhibit = "always",
})

-- apps/telegram.conf
-- Prevent Telegram from stealing focus on new messages
hl.window_rule({
    match = {
        class = "org.telegram.desktop",
    },
    focus_on_activate = false,
})

-- apps/typora.conf
-- Float Typora print dialog
hl.window_rule({
    match = {
        class = "^Typora$",
        title = "^Print$",
    },
    float = true,
    center = true,
})

-- apps/terminals.conf
-- Define terminal tag to style them uniformly
hl.window_rule({
    match = {
        class = "(Alacritty|kitty|com.mitchellh.ghostty)",
    },
    tag = "+terminal",
})

hl.window_rule({
    match = {
        tag = "terminal",
    },
    tag = "-default-opacity",
    opacity = "0.97 0.9",
})

-- apps/walker.conf
-- Application-specific animation
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true })

-- apps/webcam-overlay.conf
-- Webcam overlay for screen recording
hl.window_rule({
    match = {
        title = "WebcamOverlay",
    },
    float = true,
    pin = true,
    no_initial_focus = true,
    no_dim = true,
    move = "(monitor_w-window_w-40) (monitor_h-window_h-40)",
})
