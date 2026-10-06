# Hyprland Lua config (staged, NOT active)

Converted 2026-10-06 from `home/.config/hypr/*.conf` for Hyprland 0.56.2. Not linked into `$HOME`
(it lives outside `home/`, so `install.sh --check/--install` ignore it). The running session keeps
using `hyprland.conf` until you activate it. Hyprland picks the config type ONCE at startup:
`hyprland.lua` exists -> Lua is used, otherwise legacy `hyprland.conf`.

Method: `hyprlang2lua` (EIonTusk, third-party; Hyprland ships no official converter) plus hand fixes
(shared vars module, layer rules, `moveintoorcreategroup`, `unbind`, mouse binds, duplicate `tag` keys,
`%` sizes, vendored omarchy snapshot). Validated with `Hyprland --verify-config -c <file>`.

## Check before activating
    Hyprland --verify-config -c ~/.dotfiles/migrations/hyprland-lua/hyprland.lua   # expect: config ok

## hyprctl call sites: already ported (dual-mode)
Under a Lua config `hyprctl dispatch X` is `return hl.dispatch(X)` and `hyprctl keyword` is refused
(src/debug/HyprCtl.cpp @ v0.56.2). Every call site now goes through `home/bin/hypr-dispatch`, which
probes the manager (`hyprctl eval 'return true'` answers `ok` only under Lua) and sends the hyprlang
form or the Lua form. It works in BOTH sessions, so it was safe to land before activation.
Ported: hypridle-resume.sh, hypridle-suspend.sh, hypridle.conf `before_sleep_cmd`, power-menu,
wlogout/layout, hypr-move, hypr-preselect, grab-menu, tev-fit, zshaliases (`dropdown`), colortemp-ctl,
hdr-toggle, waybar confirm-workspace.sh + workspaces-pill.sh, .claude/hooks/attention.sh.
theme-apply: its `hyprctl keyword cursor:default` was already a no-op (no such option) and was removed.
The two Lua binds (SUPER+ALT+F VRR, SUPER+CTRL+L wiggle) use native `hl.get_config/hl.config/hl.dispatch`.
Tests: tests/hypr-dispatch-test.sh (both modes), hdr-toggle-test.sh (both modes), colortemp-ctl-test.sh.
Not verifiable before activation (valid per source + wiki, never run against a live Lua session):
the Lua forms of the hdr-toggle `hl.monitor{}` re-apply and the VRR bind's `hl.config` at runtime.

## Activation checklist
1. `Hyprland --verify-config -c ~/.dotfiles/migrations/hyprland-lua/hyprland.lua`  -> `config ok`
2. `~/.dotfiles/tests/hypr-dispatch-test.sh && ~/.dotfiles/tests/hdr-toggle-test.sh`  -> PASS
3. Restart hypridle so it reads the new before_sleep_cmd: `systemctl --user restart hypridle` (or log out).
4. Do NOT toggle HDR (SUPER+ALT+H) in the first Lua session until you have seen it work once on purpose.
5. Activate (below), then log out and back in. If the desktop is wrong: roll back (below).
6. In the new session: `~/bin/hypr-dispatch mode` -> `lua`; `hyprctl configerrors` -> empty; try
   SUPER+ALT+F, SUPER+CTRL+L, SUPER+SHIFT+h/l (hypr-move), SUPER+V (preselect), the `dropdown` alias.

## Omarchy scripts that stay broken under Lua (upstream, not edited)
They still use hyprlang `hyprctl dispatch/keyword` or write hyprlang toggle files, so these omarchy
features stop working after activation: omarchy-hyprland-window-pop (our SUPER+O bind),
-active-window-transparency-toggle (SUPER+BACKSPACE), -window-close-all, -workspace-layout-toggle,
-monitor-scaling-cycle, -window-gaps-toggle, -window-single-square-aspect-toggle (SUPER+SHIFT/CTRL+BACKSPACE),
-monitor-internal(-mirror) + lid switch binds, omarchy-toggle-touchpad/-touchscreen (XF86Touchpad* keys),
omarchy-launch-or-focus, omarchy-launch-screensaver/omarchy-screensaver (cursor:invisible), omarchy-update-*
(tag noidle, suppress_errors), omarchy-hyprland-toggle*/omarchy-refresh-hypr*/omarchy-menu toggles
(edit ~/.config/hypr/*.conf or toggles/*.conf, which Lua never reads). Fix path: wait for/port upstream
omarchy Lua support, or wrap them with hypr-dispatch the same way.

## Activate (one step, then log out and back in)
    cd ~/.dotfiles && git mv migrations/hyprland-lua/hyprland.lua home/.config/hypr/hyprland.lua && git mv migrations/hyprland-lua/lua home/.config/hypr/lua && ./install.sh --install

## Roll back
    rm ~/.config/hypr/hyprland.lua      # then `hyprctl dispatch exit` / re-login: legacy hyprland.conf is used again
(from a TTY: same `rm`, then start Hyprland). Optionally `git mv` the two paths back to migrations/.
All ported scripts keep working in the legacy session, so rollback needs no script changes.

## Known behaviour differences
- omarchy defaults are a frozen snapshot (omarchy a3aedb0c); `omarchy-toggle-*` and theme switches
  write hyprlang files that Lua no longer reads (gaps/transparency toggles, theme accent).
- SUPER+CTRL+L: hyprlang left omarchy "Lock system" bound next to our wiggle bind (unbind was
  case-mismatched); Lua unbinds it as the old comment intended. Lock stays on CTRL+ALT+Delete.
- `theme-apply` runs in `hyprland.start` and `config.reloaded` (hyprlang `exec =` ran on both).
- hypridle.conf / hyprlock.conf stay hyprlang (hypridle 0.1.8, hyprlock 0.9.6 are current releases).
