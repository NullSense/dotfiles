# Sourced by /home/nullsense/.local/share/omarchy/bin/omarchy-menu *after* its
# own definitions, so anything we redefine here overrides upstream.
# See $OMARCHY_PATH/bin/omarchy-menu (line 667) for the source point.

# ---------------------------------------------------------------------------
# Voice menu — hyprwhspr / LM Studio rewrite hook control surface.
# Reachable via:
#   - SUPER+ALT+v              direct keybind (see ~/.config/hypr/bindings.conf)
#   - omarchy-menu voice       from anywhere (CLI / scripts)
#
# Inner walker prompts route through `omarchy-launch-walker` so they share
# the elephant data provider + gapplication-service the rest of omarchy
# uses — bare `walker` invocations render in a different theme.
# ---------------------------------------------------------------------------

voice_input() {
  echo -e "" | omarchy-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630 -p "${1}…" 2>/dev/null
}

voice_pick() {
  omarchy-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630 -p "${1}…" 2>/dev/null
}

show_voice_menu() {
  case $(menu "Voice" "󰂑  Add word\n󰍴  Remove word\n  List words\n󰜉  Restart daemon\n  Test mic\n  Edit config") in
  *Add*word*)
    local from to
    from="$(voice_input 'FROM (what Parakeet hears)')"
    [[ -z "$from" ]] && { back_to show_voice_menu; return; }
    to="$(voice_input 'TO (corrected)')"
    [[ -z "$to" ]] && { back_to show_voice_menu; return; }
    hyprwhspr-dict add "$from" "$to"
    ;;
  *Remove*word*)
    local picked
    picked="$(hyprwhspr-dict list | voice_pick 'remove which?')"
    [[ -z "$picked" ]] && { back_to show_voice_menu; return; }
    hyprwhspr-dict rm "${picked% → *}"
    ;;
  *List*words*)
    hyprwhspr-dict list | voice_pick 'word overrides' >/dev/null
    back_to show_voice_menu
    ;;
  *Restart*daemon*)
    systemctl --user restart hyprwhspr && \
      notify-send -a omarchy-menu -u low "hyprwhspr restarted" || \
      notify-send -a omarchy-menu -u normal "Failed to restart hyprwhspr"
    ;;
  *Test*mic*)
    omarchy-launch-floating-terminal-with-presentation "hyprwhspr test --mic-only"
    ;;
  *Edit*config*)
    omarchy-launch-editor ~/.config/hyprwhspr/config.json
    ;;
  *)
    back_to show_main_menu
    ;;
  esac
}

# Wrap upstream go_to_menu: add a *voice* case, delegate everything else to
# the original. This keeps us robust if omarchy adds new top-level menus.
if declare -F go_to_menu >/dev/null; then
  eval "$(declare -f go_to_menu | sed '1s/go_to_menu/_omarchy_go_to_menu_upstream/')"
  go_to_menu() {
    case "${1,,}" in
    *voice*) show_voice_menu ;;
    *) _omarchy_go_to_menu_upstream "$@" ;;
    esac
  }
fi
