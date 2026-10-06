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

## BLOCKER: scripts that still use hyprlang syntax (they break under Lua)
Under a Lua config `hyprctl dispatch X` is `hl.dispatch(X)` (Lua) and `hyprctl keyword` is refused
("keyword can't work with non-legacy parsers. Use eval") -- src/debug/HyprCtl.cpp @ v0.56.2.
Port these first (e.g. `hyprctl dispatch 'hl.dsp.dpms({ action = "on", monitor = "DP-1" })'`;
`hyprctl eval 'hl.config({...})'` / `hl.monitor{...}` instead of `keyword`). hypridle-resume/-suspend
and `before_sleep_cmd` in hypridle.conf matter most: a failed `dpms on` after resume = black screen.
bin/: hypridle-resume.sh hypridle-suspend.sh power-menu hypr-move hypr-preselect grab-menu theme-apply
colortemp-ctl hdr-toggle tev-fit zshaliases; .config/waybar/: confirm-workspace.sh workspaces-pill.sh;
.config/hypr/hypridle.conf (before_sleep_cmd); .config/wlogout/layout; .claude/hooks/attention.sh.
Also the Lua binds `SUPER+ALT+F` (VRR toggle, uses `hyprctl keyword misc:vrr`) and `SUPER+CTRL+L`
(wiggle, uses `hyprctl --batch "dispatch resizeactive ..."`) in lua/bindings.lua, and 12 omarchy
scripts (omarchy-hyprland-window-pop, -toggle-touchpad, -launch-or-focus, ...) that use `hyprctl dispatch`.

## Activate (one step, then log out and back in)
    cd ~/.dotfiles && git mv migrations/hyprland-lua/hyprland.lua home/.config/hypr/hyprland.lua && git mv migrations/hyprland-lua/lua home/.config/hypr/lua && ./install.sh --install

## Roll back
    rm ~/.config/hypr/hyprland.lua      # then `hyprctl dispatch exit` / re-login: legacy hyprland.conf is used again
(from a TTY: same `rm`, then start Hyprland). Optionally `git mv` the two paths back to migrations/.

## Known behaviour differences
- omarchy defaults are a frozen snapshot (omarchy a3aedb0c); `omarchy-toggle-*` and theme switches
  write hyprlang files that Lua no longer reads (gaps/transparency toggles, theme accent).
- SUPER+CTRL+L: hyprlang left omarchy "Lock system" bound next to our wiggle bind (unbind was
  case-mismatched); Lua unbinds it as the old comment intended. Lock stays on CTRL+ALT+Delete.
- `theme-apply` runs in `hyprland.start` and `config.reloaded` (hyprlang `exec =` ran on both).
- hypridle.conf / hyprlock.conf stay hyprlang (hypridle 0.1.8, hyprlock 0.9.6 are current releases).
