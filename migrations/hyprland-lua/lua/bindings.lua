local V = require("lua.vars")
local mod, term = V.mod, V.term

-- Keybindings — direct translation from sway with Hyprland equivalents.
--
-- bind     — basic
-- bindl    — fires even when locked (matches sway --locked)
-- binde    — repeats while held
-- bindel   — locked + repeats (volume keys when locked)
-- bindd    — same as bind but with description (shows in `hyprctl binds`)
-- bindgesture — touchpad gestures (we use built-in `gestures` block instead)
-- submap   — modal mode (resize, system, media)

-- ============================================================================
-- Apps
-- ============================================================================

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(term), { description = "Open terminal" })

-- Launcher — omarchy stock (omarchy-launch-walker). Stock SUPER+SPACE already
-- maps to this in omarchy/utilities.conf; we add SUPER+D / SUPER+TAB as
-- additional muscle-memory entry points. Omarchy's stock SUPER+D (Lazy Docker)
-- is intentionally overridden — we don't use it.
hl.bind(mod .. " + d", hl.dsp.exec_cmd("omarchy-launch-walker"), { description = "App launcher" })
hl.bind(mod .. " + SHIFT + d", hl.dsp.exec_cmd("omarchy-launch-walker -m runner"), { description = "Run command" })
hl.bind(mod .. " + Tab", hl.dsp.exec_cmd("omarchy-launch-walker -m windows"), { description = "Window switcher" })

-- Bitwarden — omarchy has no direct equivalent; keep our walker-rbw wrapper.
-- (rbw = command-line Bitwarden client; walker-rbw is a custom picker that
-- lists vault entries via walker --dmenu, then offers a per-entry action
-- sub-menu: copy/type password|username, copy TOTP, open/copy URI(s),
-- copy notes, copy custom fields.)
hl.bind(mod .. " + b", hl.dsp.exec_cmd("/home/nullsense/bin/walker-rbw"), { description = "Bitwarden picker" })
hl.bind(mod .. " + SHIFT + b", hl.dsp.exec_cmd("/home/nullsense/bin/walker-rbw type"), { description = "Bitwarden type password" })

-- Media downloader menu (G = Grab). Walker front-end over ~/bin/grab (video via
-- yt-dlp / images via gallery-dl / zoomable art via dezoomify-rs) and ~/bin/artgrab
-- (find & compare high-res artwork scans across museums). Takes the clipboard URL.
-- NB: SUPER+ALT+C is the Capture menu and SUPER+ALT+D is dictation — hence G.
hl.bind(mod .. " + ALT + g", hl.dsp.exec_cmd("/home/nullsense/bin/grab-menu"), { description = "Download media (grab)" })

-- Vicinae — Raycast-style launcher kept as backup. SUPER+SPACE is now the
-- omarchy stock launcher (canonical). SUPER+ALT+V was reassigned to the
-- Voice menu (see Voice dictation section); `vicinae toggle` is still
-- reachable via the CLI or can be re-bound to a free key if needed.
-- bindd = $mod ALT, v,   Vicinae launcher (backup), exec, vicinae toggle  # disabled — clashes with Voice menu

-- Discoverability — omarchy's walker-based keybindings picker. Stock omarchy
-- uses SUPER+K for the same; we keep SUPER+/ as the muscle-memory alias.
hl.bind(mod .. " + slash", hl.dsp.exec_cmd("omarchy-menu-keybindings"), { description = "Show keybindings" })

-- Localhost services picker — scans `ss` for listeners, opens chosen one in browser.
-- Labels live in ~/.config/services.toml.
hl.bind(mod .. " + s", hl.dsp.exec_cmd("~/bin/services"), { description = "Localhost services" })

-- OCR — select an area, extract text, copy to clipboard.
-- Uses tesseract under the hood. `~/bin/ocr <lang>` for non-English (e.g. jpn+eng).
hl.bind(mod .. " + SHIFT + t", hl.dsp.exec_cmd("~/bin/ocr"), { description = "OCR text from screen" })

-- Color picker — eyedropper, copies hex to clipboard.
hl.bind(mod .. " + SHIFT + c", hl.dsp.exec_cmd("~/bin/colorpick"), { description = "Color picker (hex)" })

-- Dropdown terminal — toggle the special:dropdown workspace
hl.bind(mod .. " + u", hl.dsp.workspace.toggle_special("dropdown"), { description = "Dropdown terminal" })

-- Dropdown Spotify — toggle the special:spotify workspace
hl.bind(mod .. " + m", hl.dsp.workspace.toggle_special("spotify"), { description = "Dropdown Spotify" })

-- Floating-windows scratchpad — show/hide every floating window at once.
-- Auto-population: see windows.conf `floating:1` rule. Use SUPER+CTRL+U
-- (SUPER+ALT+U is `moveoutofgroup`; SUPER+U is the dropdown terminal).
-- SUPER+CTRL+SHIFT+U sends the current window into the scratchpad.
hl.bind(mod .. " + CTRL + u", hl.dsp.workspace.toggle_special("floats"), { description = "Toggle floats scratchpad" })
hl.bind(mod .. " + CTRL + SHIFT + u", hl.dsp.window.move({ workspace = "special:floats", follow = false }), { description = "Send window to floats" })

-- ============================================================================
-- Screenshot / capture
-- ============================================================================
--
-- PRINT, ALT+PRINT, SUPER+CTRL+PRINT now use omarchy stock from
-- omarchy/default/hypr/bindings/utilities.conf:
--   PRINT             omarchy-capture-screenshot
--   ALT+PRINT         omarchy-menu screenrecord
--   SUPER+CTRL+PRINT  omarchy-capture-text-extraction (OCR)
-- Region/window screenshots are reachable from the capture menu.
-- Our ~/bin/screenshot, ~/bin/capture-menu, ~/bin/ocr, ~/bin/screenrecord
-- scripts stay installed and runnable from launcher search if ever needed.

-- Color picker (hyprpicker, eyedropper). Not a screenshot tool — kept here
-- because it's bound to a SUPER+PRINT muscle memory.
hl.bind("SUPER + Print", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"), { description = "Color picker" })

-- Screenrecord direct paths (modifier variants for desktop / mic audio)
hl.bind("SUPER + ALT + r", hl.dsp.exec_cmd("/home/nullsense/bin/screenrecord"), { description = "Screen recording" })
hl.bind("SUPER + ALT + SHIFT + r", hl.dsp.exec_cmd("/home/nullsense/bin/screenrecord --with-desktop-audio"), { description = "Record + desktop audio" })
hl.bind("SUPER + CTRL + ALT + r", hl.dsp.exec_cmd("/home/nullsense/bin/screenrecord --with-microphone-audio"), { description = "Record + mic audio" })
-- Gameplay capture: dedicated encoder, AV1 HDR, game audio, no microphone.
-- Checked against live binds before adding; existing desktop shortcuts remain.
hl.bind("SUPER + ALT + F9", hl.dsp.exec_cmd("/home/nullsense/bin/screenrecord --game"), { description = "HDR gameplay recording" })
hl.bind("SUPER + ALT + F10", hl.dsp.exec_cmd("/home/nullsense/bin/screenrecord --replay"), { description = "Toggle HDR replay" })
hl.bind("SUPER + ALT + F11", hl.dsp.exec_cmd("/home/nullsense/bin/screenrecord --save-replay"), { description = "Save HDR replay" })

-- HDR toggle — flips DP-1 between the normal sRGB desktop and verified
-- forced-HDR-everywhere. SUPER+ALT+H is free; SUPER+CTRL+H is omarchy's
-- Hardware menu, SUPER+SHIFT+H collides at runtime.
hl.bind("SUPER + ALT + H", hl.dsp.exec_cmd("/home/nullsense/bin/hdr-toggle"), { description = "Toggle HDR (DP-1)" })

-- ============================================================================
-- Clipboard
-- ============================================================================

hl.bind(mod .. " + Insert", hl.dsp.exec_cmd("notify-send -t 2000 \"$(wl-paste)\""), { description = "Show clipboard" })
-- Clipboard history is now omarchy stock SUPER+CTRL+V (omarchy-launch-walker
-- -m clipboard). SUPER+C is omarchy's "Universal copy" (sendshortcut) — we
-- don't override it anymore.
hl.bind(mod .. " + SHIFT + Insert", hl.dsp.exec_cmd("sh -c 'wl-paste | /home/nullsense/bin/0x0'"), { description = "Upload clipboard" })
hl.bind(mod .. " + CTRL + Insert", hl.dsp.exec_cmd("/home/nullsense/bin/escaper"), { description = "Escape clipboard" })

-- ============================================================================
-- Media — playerctld picks most-recently-active player
-- ============================================================================

-- Direct playerctl shortcuts. SUPER+P alone is reserved for `pseudo` (omarchy
-- tiling convention, defined in window-management section below); media
-- playback uses CTRL/ALT modifiers + the dedicated SUPER+SHIFT+M submap.
-- XF86Audio* keys are owned by omarchy stock (omarchy-swayosd-client) for OSD.
hl.bind(mod .. " + CTRL + p", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind(mod .. " + ALT + p", hl.dsp.exec_cmd("playerctld shift"), { locked = true })

-- Media submap — Mod+Shift+m enters; press q/Esc/Return to exit
hl.bind(mod .. " + SHIFT + m", hl.dsp.submap("media"), { description = "Enter media mode" })
hl.define_submap("media", function()
    hl.bind("space", hl.dsp.exec_cmd("playerctl play-pause"), { repeating = true })
    hl.bind("n", hl.dsp.exec_cmd("playerctl next"), { repeating = true })
    hl.bind("p", hl.dsp.exec_cmd("playerctl previous"), { repeating = true })
    hl.bind("bracketright", hl.dsp.exec_cmd("playerctl position 5+"), { repeating = true })
    hl.bind("bracketleft", hl.dsp.exec_cmd("playerctl position 5-"), { repeating = true })
    hl.bind("equal", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
    hl.bind("minus", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
    hl.bind("s", hl.dsp.workspace.toggle_special("spotify"))
    hl.bind("c", hl.dsp.exec_cmd("playerctld shift"))
    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind("q", hl.dsp.submap("reset"))
end)

-- ============================================================================
-- Audio + Brightness — XF86 keys owned by omarchy stock
-- ============================================================================
--
-- Volume/mute/mic-mute and brightness on the dedicated function keys are
-- handled by omarchy/default/hypr/bindings/utilities.conf via
-- omarchy-swayosd-client / omarchy-brightness-display. We let those win so
-- you get the nice OSD overlay. Our $mod-modified brightness binds below
-- stay because they don't conflict (no XF86 trigger).

-- Volume on $mod+= / $mod+- via omarchy's OSD wrapper (same on-screen
-- overlay you get from XF86Audio* keys). Brightness moves up one modifier
-- step to $mod SHIFT + = / -, calling our DDC/CI ~/bin/brightness-ctl
-- directly so external monitors actually respond. The previous max/30%
-- brightness extremes on $mod SHIFT + = / - are dropped — rarely used.
hl.bind(mod .. " + equal", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume raise"), { locked = true, repeating = true })
hl.bind(mod .. " + minus", hl.dsp.exec_cmd("omarchy-swayosd-client --output-volume lower"), { locked = true, repeating = true })
hl.bind(mod .. " + SHIFT + equal", hl.dsp.exec_cmd("~/bin/brightness-ctl +10"), { locked = true, repeating = true })
hl.bind(mod .. " + SHIFT + minus", hl.dsp.exec_cmd("~/bin/brightness-ctl -10"), { locked = true, repeating = true })

-- ============================================================================
-- VRR / FreeSync toggle (gaming) — Hyprland equivalent of `output DP-1 adaptive_sync toggle`
-- Now on SUPER+ALT+F (mnemonic: F = FreeSync). It previously sat on $mod+Shift+v,
-- which is i3's split slot — V belongs to the preselect pair (see Window
-- management). SUPER+ALT+F was verified free against `hyprctl binds`; the
-- SUPER+ALT family is the "system/tooling" tier here (c=Capture, d=Dictate,
-- g=Grab, r=Record, v=Voice, H=HDR), which is where a display toggle belongs
-- anyway — it sits right next to SUPER+ALT+H for HDR.
-- ============================================================================

hl.bind(mod .. " + ALT + f", hl.dsp.exec_cmd("sh -c 'cur=$(hyprctl getoption -j misc:vrr | jq .int); new=$([ \"$cur\" -eq 0 ] && echo 2 || echo 0); hyprctl keyword misc:vrr $new; notify-send \"Adaptive Sync\" \"$([ $new -eq 2 ] && echo \"on (fullscreen)\" || echo off)\"'"), { description = "Toggle VRR / FreeSync" })

-- ============================================================================
-- Lock & system mode
-- ============================================================================

hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("hyprlock"), { description = "Lock screen" })

-- Power menu — walker dmenu picker (omarchy-style), self-contained script at
-- ~/bin/power-menu. Re-running the binding while the picker is open closes it
-- (single-instance toggle). Replaces the prior wlogout overlay because we want
-- the same walker theme/UX as the rest of the system, and wlogout's separate
-- GTK window doesn't theme-track omarchy theme switches.
hl.bind("CTRL + Delete", hl.dsp.exec_cmd("power-menu"), { description = "Power menu" })

-- ============================================================================
-- Window management
-- ============================================================================

hl.bind(mod .. " + SHIFT + q", hl.dsp.window.close(), { description = "Kill window" })

-- Focus — sway-style hjkl. (Omarchy's tiling-v2.conf is no longer sourced
-- from hyprland.conf; we own SUPER+J/F/T/W/L/P here without conflicts.)
-- unbind clears the omarchy stock binds for K (omarchy-menu-keybindings),
-- COMMA (makoctl dismiss), X (Universal cut). We have alternates:
--   - keybindings menu  → SUPER+/  (alias kept in launcher section above)
--   - dismiss notif     → swipe via mako; or set up your own bind later
--   - universal cut     → CTRL+X works in apps; sendshortcut isn't worth losing X
hl.unbind("SUPER + K")
hl.unbind("SUPER + COMMA")
hl.unbind("SUPER + X")
hl.bind(mod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + j", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + l", hl.dsp.focus({ direction = "right" }))

-- Move windows — group-aware, so pushing a window around behaves like i3 rather
-- than teleporting past containers. `movewindoworgroup` is a three-way dispatch
-- (documented at wiki.hypr.land/Configuring/Dispatchers):
--   group in that direction        -> moveintogroup   (merge into it)
--   no group there, but you're in one -> moveoutofgroup (pop out FIRST)
--   otherwise                      -> movewindow      (plain move)
-- The middle case is the one that matters day to day: pushing out of a group
-- costs one press to leave the group and a second to actually travel, instead of
-- jumping straight to the next monitor and leaving the group behind in one go.
-- ~/bin/hypr-move wraps movewindoworgroup with i3's missing case: inside a
-- group, left/right REORDER the tab and only eject you once you push past the
-- first/last one. Hyprland has no option for that — movegroupwindow wraps
-- forever, movewindoworgroup ejects immediately — so the two are combined there.
hl.bind(mod .. " + SHIFT + h", hl.dsp.exec_cmd("~/bin/hypr-move l"))
hl.bind(mod .. " + SHIFT + j", hl.dsp.exec_cmd("~/bin/hypr-move d"))
hl.bind(mod .. " + SHIFT + k", hl.dsp.exec_cmd("~/bin/hypr-move u"))
hl.bind(mod .. " + SHIFT + l", hl.dsp.exec_cmd("~/bin/hypr-move r"))

-- ----- i3 container controls ------------------------------------------------
-- Mapped 1:1 onto i3's container keys. The old config had SUPER+V and SUPER+E
-- both bound to `layoutmsg togglesplit` — a copy/paste duplicate that wasted the
-- V slot and left i3's `split` verb with no key at all. V is now the split key
-- (see the Preselect section below); E keeps i3's "toggle split orientation".
--
--   i3                      here
--   ---------------------   ------------------------------------------
--   $mod+e  layout toggle   SUPER+E        layoutmsg togglesplit
--   (no i3 equivalent)      SUPER+SHIFT+E  layoutmsg swapsplit
--   $mod+w  layout tabbed   SUPER+W        togglegroup      (Tabs section)
--   $mod+a  focus parent    SUPER+A        moveoutofgroup   (closest analogue)
--
-- NB dwindle has no focus-parent: its tree nodes aren't focusable the way i3's
-- containers are. SUPER+A therefore keeps the useful half of i3's mod+a — pop the
-- window out of its tab group — and SUPER+SHIFT+A promotes it to the root of the
-- workspace tree, which is the "escape this deeply nested split" move you'd
-- normally reach focus-parent for.
hl.bind(mod .. " + e", hl.dsp.layout("togglesplit"), { description = "Toggle split orientation" })
hl.bind(mod .. " + SHIFT + e", hl.dsp.layout("swapsplit"), { description = "Swap the two split halves" })
hl.bind(mod .. " + a", hl.dsp.window.move({ out_of_group = true }), { description = "Pop window out of tab group" })
hl.bind(mod .. " + SHIFT + a", hl.dsp.layout("movetoroot"), { description = "Promote window to tree root" })

-- ----- Preselect: "where will the next window land?" -------------------------
-- i3's `split h` / `split v`, plus the visible split indicator i3 draws and
-- Hyprland does not (upstream request hyprwm/Hyprland#9187 is still open).
--
-- SUPER+V cycles off -> down -> right -> off. While armed, the focused window's
-- border becomes a dim->bright gradient whose BRIGHT end sits on the edge that is
-- about to be split, so you can see the next terminal's slot before you open it.
-- The indicator is driven by ~/bin/hypr-preselect, whose `watch` daemon (started
-- from autostart.conf) clears it the moment dwindle consumes the preselect —
-- so an armed border always means genuinely armed.
hl.bind(mod .. " + v", hl.dsp.exec_cmd("~/bin/hypr-preselect cycle"), { description = "Preselect split (cycle down/right/off)" })
hl.bind(mod .. " + SHIFT + v", hl.dsp.exec_cmd("~/bin/hypr-preselect clear"), { description = "Preselect: clear" })
-- togglefloating moved off SUPER+SHIFT+SPACE — omarchy owns that for
-- `omarchy-toggle-waybar`. Use SUPER+T (omarchy convention).
hl.bind(mod .. " + t", hl.dsp.window.float({ action = "toggle" }))

-- ----- Window states ---------------------------------------------------------
-- Hyprland has three "big window" modes, each with a different use case:
--   fullscreen 1               — maximize (under bar, gaps kept).  Everyday.
--   fullscreen 0               — exclusive (covers bar).            Games/video.
--   fullscreenstate, 0, 2      — fake fullscreen: window renders at tile size
--                                but the *client* thinks it's fullscreen.
--                                For screensharing / theater-mode YouTube.
--                                (Replaces the deprecated `fakefullscreen`.)
hl.bind(mod .. " + f", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), { description = "Maximize (under bar)" })
hl.bind(mod .. " + CTRL + f", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Exclusive fullscreen" })
hl.bind(mod .. " + SHIFT + f", hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }), { description = "Fake fullscreen (share)" })
-- Pseudo + pop-out — omarchy convention. SUPER+P = pseudo; SUPER+O = float
-- AND pin AND raise (omarchy-hyprland-window-pop) which subsumes our old
-- manual Pin combo.
hl.bind(mod .. " + p", hl.dsp.window.pseudo(), { description = "Pseudo" })
hl.bind(mod .. " + o", hl.dsp.exec_cmd("omarchy-hyprland-window-pop"), { description = "Pop window out (float+pin)" })
hl.bind(mod .. " + CTRL + Return", hl.dsp.window.center(), { description = "Center floating window" })

-- ----- Native tab groups (i3 `layout tabbed`) -------------------------------
-- SUPER+W is i3's tabbed layout. Hyprland's native groups already behave the way
-- i3 tabs do here, because `group:auto_group` and `group:insert_after_current`
-- are both on (verified via hyprctl getoption): once a window is grouped, the
-- next window you open joins it as a tab immediately after the current one,
-- rather than splitting the tile. So SUPER+W then SUPER+Return stacks terminals
-- into tabs exactly like i3.
--
-- SUPER+SHIFT+W locks the group, which is the piece people miss: a locked group
-- stops swallowing new windows, so you can build a 3-tab group and then open a
-- 4th window *beside* it instead of inside it. SUPER+A pops the active tab back
-- out (Window management section above).
--
-- THE MODEL (all four verbs verified empirically on 0.56.2, see notes below):
--
--   make/dissolve   SUPER+W              togglegroup
--                     On a plain window this creates a group of ONE. That looks
--                     like nothing happened except a groupbar appearing — it is
--                     the "this tile is now a tabbed container" state. Press
--                     again to dissolve.
--   fill by opening  (automatic)         group:auto_group = 1
--                     With a group focused, every newly opened window joins it
--                     as a tab. This is the main way groups grow.
--   MERGE into an existing group   SUPER+SHIFT+hjkl   movewindoworgroup <dir>
--                     Push the focused window at a group and it becomes a tab.
--                     This is the answer to "how do I merge into a window I
--                     already pressed SUPER+W on" — aim at it and push.
--                     Same key pops you back OUT when you push away from the
--                     group (see the Focus/move section above).
--   MERGE two plain windows        SUPER+ALT+arrows   moveintoorcreategroup <dir>
--                     Needed when the neighbour is NOT yet a group: this creates
--                     the group from it first. movewindoworgroup won't, since
--                     there is no group in that direction to move into.
--   unmerge one tab  SUPER+A             moveoutofgroup
--   switch tab       SUPER+[ / ]         changegroupactive b/f
--   reorder tab      SUPER+SHIFT+[ / ]   movegroupwindow b/f
--   stop swallowing  SUPER+SHIFT+W       lockactivegroup toggle
--
-- WHY TWO MERGE KEYS — the split is real, per the documented behaviour:
--   `movewindoworgroup <dir>` merges into a group that ALREADY exists, pops out
--   when there is none in that direction, and otherwise moves normally. It does
--   NOT create a group out of a plain neighbour.
--   `moveintogroup <dir>` only ever joins an existing group and silently no-ops
--   otherwise — strictly weaker, so unused here (it is what omarchy's unsourced
--   tiling-v2.conf binds).
--   `moveintoorcreategroup <dir>` is the only one that will create the group,
--   hence the dedicated arrow-key binds.
-- NB an earlier revision of this comment claimed movewindoworgroup never merges.
-- That was a bad test: it used `lockactivegroup lock` to keep a third window out
-- and then released the lock while focus was on the wrong window, so the group
-- stayed locked and refused the merge. Retested with the global `lockgroups`
-- instead — it merges, exactly as documented.
hl.bind(mod .. " + w", hl.dsp.group.toggle(), { description = "Toggle tab group" })
hl.bind(mod .. " + SHIFT + w", hl.dsp.group.lock_active({ action = "toggle" }), { description = "Toggle group lock" })
hl.bind(mod .. " + bracketleft", hl.dsp.group.prev(), { description = "Group: prev tab" })
hl.bind(mod .. " + bracketright", hl.dsp.group.next(), { description = "Group: next tab" })
hl.bind(mod .. " + SHIFT + bracketleft", hl.dsp.group.move_window({ forward = false }), { description = "Group: move tab left" })
hl.bind(mod .. " + SHIFT + bracketright", hl.dsp.group.move_window({ forward = true }), { description = "Group: move tab right" })

-- Merge with the neighbour in a direction. Arrow keys rather than hjkl because
-- hjkl is saturated (focus on SUPER, move on SUPER+SHIFT) and because this is
-- the one omarchy convention worth keeping — its tiling-v2.conf uses
-- SUPER+ALT+arrows for the same idea. Verified free against `hyprctl binds`:
-- the only arrow binds are the bare ones inside the resize submap.
hl.bind(mod .. " + ALT + left", hl.dsp.window.move({ into_or_create_group = "left" }), { description = "Merge window into group (left)" })
hl.bind(mod .. " + ALT + right", hl.dsp.window.move({ into_or_create_group = "right" }), { description = "Merge window into group (right)" })
hl.bind(mod .. " + ALT + up", hl.dsp.window.move({ into_or_create_group = "up" }), { description = "Merge window into group (up)" })
hl.bind(mod .. " + ALT + down", hl.dsp.window.move({ into_or_create_group = "down" }), { description = "Merge window into group (down)" })

-- Mouse drag-to-move (replaces sway `floating_modifier $mod`)
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ----- Force redraw (fix TUI render corruption) -----------------------------
-- Wiggles the focused window 1px right then back. Triggers SIGWINCH and forces
-- a full repaint, which fixes the terminal-agnostic Claude Code / Ink
-- contaminated back-buffer bug (anthropics/claude-code #42010): the diff
-- renderer mutates the previous-frame screen which gets reused as the next
-- frame's write target, so corruption escalates until a SIGWINCH swaps both
-- buffers. Keep this terminal-independent recovery binding available after
-- switching to Ghostty; normal redraw behavior is verified separately.
-- A real window resize is required — sending SIGWINCH alone doesn't flush the
-- terminal's internal sync buffer. Bound away from plain CTRL+L to preserve
-- the shell's clear-screen muscle memory. SUPER+CTRL+L was previously
-- the omarchy stock lock binding (omarchy-system-lock) — we explicitly
-- unbind it first; lock now lives on CTRL+ALT+Delete + the power menu.
hl.unbind("SUPER + CTRL + L")
hl.bind(mod .. " + CTRL + l", hl.dsp.exec_cmd("hyprctl --batch \"dispatch resizeactive 1 0 ; dispatch resizeactive -1 0\""), { description = "Wiggle window (fix TUI render corruption)" })

-- ============================================================================
-- Workspaces
-- ============================================================================

-- Move focused workspace between monitors (sway: move workspace to output left/right)
hl.bind(mod .. " + SHIFT + comma", hl.dsp.workspace.move({ monitor = "l" }), { description = "Move workspace to left monitor" })
hl.bind(mod .. " + SHIFT + period", hl.dsp.workspace.move({ monitor = "r" }), { description = "Move workspace to right monitor" })

-- ----- Workspace navigation (Hyprland-native patterns) ----------------------
-- +1/-1   = next/prev workspace      (cycles through existing)
-- e+1/e-1 = next/prev *empty*        (sway-style — finds a free one)
-- m+1/m-1 = next/prev on *this monitor*
-- previous= toggle to last visited (alt-tab for workspaces)
--
-- SUPER+CTRL+L is now our Ghostty wiggle (see Window management section);
-- SUPER+CTRL+H is reserved for omarchy stock (omarchy-menu hardware).
-- Workspace nav lives on Page Up/Down + grave + numbered direct-jumps + scroll wheel.
hl.bind(mod .. " + Page_Down", hl.dsp.focus({ workspace = "+1" }), { description = "Next workspace" })
hl.bind(mod .. " + Page_Up", hl.dsp.focus({ workspace = "-1" }), { description = "Prev workspace" })
hl.bind(mod .. " + grave", hl.dsp.focus({ workspace = "previous" }), { description = "Last workspace" })
hl.bind(mod .. " + SHIFT + Page_Down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next empty workspace" })
hl.bind(mod .. " + SHIFT + Page_Up", hl.dsp.focus({ workspace = "e-1" }), { description = "Prev empty workspace" })
-- Scroll on the bar/desktop changes workspace too
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }), { description = "Workspace scroll +" })
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "m-1" }), { description = "Workspace scroll -" })

-- ----- Multi-monitor focus --------------------------------------------------
hl.bind(mod .. " + period", hl.dsp.focus({ monitor = "+1" }), { description = "Focus next monitor" })
hl.bind(mod .. " + comma", hl.dsp.focus({ monitor = "-1" }), { description = "Focus prev monitor" })

-- ----- Window cycling (alt-tab style) ---------------------------------------
hl.bind(mod .. " + n", hl.dsp.window.cycle_next({ next = true }), { description = "Cycle next window" })
hl.bind(mod .. " + SHIFT + n", hl.dsp.window.cycle_next({ prev = true }), { description = "Cycle prev window" })
hl.bind(mod .. " + x", hl.dsp.window.bring_to_top(), { description = "Bring float to front" })

-- Switch to workspace
hl.bind(mod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mod .. " + 5", hl.dsp.exec_cmd("~/.config/waybar/confirm-workspace.sh 5"))
hl.bind(mod .. " + 6", hl.dsp.exec_cmd("~/.config/waybar/confirm-workspace.sh 6"))
hl.bind(mod .. " + 7", hl.dsp.exec_cmd("~/.config/waybar/confirm-workspace.sh 7"))
hl.bind(mod .. " + 8", hl.dsp.exec_cmd("~/.config/waybar/confirm-workspace.sh 8"))
hl.bind(mod .. " + 9", hl.dsp.exec_cmd("~/.config/waybar/confirm-workspace.sh 9"))
hl.bind(mod .. " + 0", hl.dsp.exec_cmd("~/.config/waybar/confirm-workspace.sh 10"))

-- Move container to workspace
hl.bind(mod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(mod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(mod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(mod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(mod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(mod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(mod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(mod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Full reload (≈ sway's `bindsym $mod+Shift+r reload`, but also kicks
-- waybar/mako/walker/dropdown/swaybg via the helper script). Use this
-- after any config edit to avoid logout+login. See ~/bin/full-reload.
hl.bind(mod .. " + SHIFT + r", hl.dsp.exec_cmd("~/bin/full-reload"), { description = "Reload everything" })

-- ============================================================================
-- Resize submap
-- ============================================================================

hl.bind(mod .. " + r", hl.dsp.submap("resize"), { description = "Resize mode" })
hl.define_submap("resize", function()
    hl.bind("h", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
    hl.bind("j", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })
    hl.bind("k", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
    hl.bind("l", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
    hl.bind("Left", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
    hl.bind("Down", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })
    hl.bind("Up", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
    hl.bind("Right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind(mod .. " + r", hl.dsp.submap("reset"))
end)

-- ============================================================================
-- Voice dictation — hyprwhspr (Parakeet TDT v3 via onnx-asr, in-process)
-- ============================================================================
-- hyprwhspr injects via ydotool (single Ctrl+V paste, not character typing) so
-- the modifier-stuck issue we hit with whisrs doesn't apply here — modifier
-- combos like SUPER+ALT+D are safe.
-- Push-to-talk: hold to record, release to stop + paste at cursor.
-- (recording_mode=auto in config.json also makes a quick tap behave as toggle —
-- tap once to start, tap again to stop. Use the cancel bind below if you tap
-- and want to abort without pasting.)
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("echo start > ~/.config/hyprwhspr/recording_control"), { description = "Voice dictation (start)" })
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("echo stop  > ~/.config/hyprwhspr/recording_control"), { release = true, description = "Voice dictation (stop)" })
-- Cancel/discard the in-progress recording without transcribing or pasting.
-- Routes through the same FIFO (cancel is a valid base command at main.py:1929)
-- so it works regardless of use_hypr_bindings setting.
hl.bind("SUPER + ALT + X", hl.dsp.exec_cmd("echo cancel > ~/.config/hyprwhspr/recording_control"), { description = "Voice dictation (cancel)" })
-- Voice menu — vocab/dictionary, restart daemon, test mic, etc.
-- Mnemonic: SUPER+ALT+v (Voice/Vocab) — sits next to the dictation key (d).
-- NOTE: lowercase `v` matters — Hyprland treats capital V as shift+v, so
-- `SUPER ALT, V` would silently require SUPER+ALT+SHIFT+V to fire.
-- We bind directly to ~/.local/bin/hyprwhspr-dict (uses omarchy-launch-walker
-- internally for theming) instead of `omarchy-menu voice`. The omarchy-menu
-- integration at ~/.config/omarchy/extensions/menu.sh remains for users who
-- go through the main menu (SUPER+ALT+SPACE → … → Voice).
hl.bind("SUPER + ALT + v", hl.dsp.exec_cmd("/home/nullsense/.local/bin/hyprwhspr-dict"), { description = "Voice menu" })
-- Learn from correction — fix a misheard term in place, select it, press this:
-- the term is added to the voice vocabulary (notification with Undo). Reads the
-- PRIMARY selection, so just highlight the corrected word. Lowercase `l` for the
-- same capital-letter trap as the `v` above; SUPER+SHIFT+L would shadow movewindow.
hl.bind("SUPER + ALT + l", hl.dsp.exec_cmd("/home/nullsense/.local/bin/hyprwhspr-ai learn"), { description = "Learn selected term" })
-- Capture menu — screenshot/record/OCR/picker + AI vision (summarize/explain/ask).
-- Mnemonic: SUPER+ALT+c (Capture). Sits in the same family as +d (Dictate)
-- and +v (Voice menu). Bare Print, SUPER+CTRL+Print, etc. remain wired to
-- their direct omarchy-capture-* fast paths for muscle memory.
hl.bind("SUPER + ALT + c", hl.dsp.exec_cmd("omarchy-menu capture"), { description = "Capture menu" })
-- Unbind the omarchy stock SUPER+CTRL+C "Capture menu" — moved to SUPER+ALT+c
-- above for ergonomic family with +d (Dictate) and +v (Voice menu). The stock
-- binding lives in ~/.local/share/omarchy/default/hypr/bindings/utilities.conf
-- which is owned by omarchy; we override at the user level via unbindd.
hl.unbind("SUPER + CTRL + C")
