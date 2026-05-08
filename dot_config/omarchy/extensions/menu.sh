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

# ---------------------------------------------------------------------------
# Capture menu — restored interactive screenshot/record/OCR + new AI vision
# entries (Summarize / Explain / Ask) backed by Gemma 4 multimodal.
# Reachable via:
#   - SUPER+ALT+c              direct keybind
#   - omarchy-menu capture     from CLI/scripts
#
# AI entries pipe their result through ai_dispose() — a walker sub-menu
# (Copy / Paste / Save / Show again / Discard) so the user picks where the
# answer lands instead of it auto-pasting somewhere unwanted.
# ---------------------------------------------------------------------------

capture_pick() {
  omarchy-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630 -p "${1}…" 2>/dev/null
}

ai_dispose() {
  local result="$1"
  [[ -z "$result" ]] && {
    notify-send -a omarchy-menu -u normal "Vision returned empty" "Try again or check LM Studio"
    return
  }
  local tmpf
  tmpf="$(mktemp --suffix=.txt)"
  printf '%s\n' "$result" > "$tmpf"

  case $(menu "Result" "  Copy to clipboard\n  Paste at cursor\n  Save to file\n  Show again\n  Discard") in
  *Copy*to*clipboard*)
    printf '%s' "$result" | wl-copy
    notify-send -a omarchy-menu -u low -t 2000 "Copied to clipboard" "$(printf '%s' "$result" | head -c 80)…"
    ;;
  *Paste*at*cursor*)
    printf '%s' "$result" | wl-copy
    sleep 0.1
    # ydotool is what hyprwhspr uses, so paste matches the dictation flow.
    if command -v ydotool >/dev/null; then
      ydotool key 29:1 42:1 47:1 47:0 42:0 29:0  # Ctrl+Shift+V (29=ctrl, 42=shift, 47=v)
    elif command -v wtype >/dev/null; then
      wtype -M ctrl -M shift -k v -m shift -m ctrl
    else
      notify-send -a omarchy-menu -u normal "No paste tool" "Install ydotool or wtype"
    fi
    ;;
  *Save*to*file*)
    local ts dst
    ts="$(date +%Y%m%d-%H%M%S)"
    dst="$HOME/Documents/screen-notes/${ts}.md"
    mkdir -p "$(dirname "$dst")"
    printf '%s\n' "$result" > "$dst"
    notify-send -a omarchy-menu -u low -t 3000 "Saved" "$dst"
    ;;
  *Show*again*)
    omarchy-launch-floating-terminal-with-presentation "less '$tmpf'; rm -f '$tmpf'"
    return  # tmpf cleaned up by less subprocess
    ;;
  *Discard*|*) : ;;
  esac
  rm -f "$tmpf"
}

show_capture_menu() {
  case $(menu "Capture" "  Screenshot…\n  Screen record…\n  Text extraction (OCR)\n  Color picker\n󰋩  AI: Summarize screen\n󰋩  AI: Explain region\n󰋩  AI: Ask about region\n󰏫  Edit last screenshot") in
  *Screenshot…*)        show_screenshot_submenu ;;
  *Screen*record…*)     show_screenrecord_submenu ;;
  *Text*extraction*|*OCR*) omarchy-capture-text-extraction ;;
  *Color*picker*)       pkill hyprpicker || setsid hyprpicker -a >/dev/null 2>&1 & ;;
  *AI*Summarize*screen*) ai_dispose "$(hyprwhspr-vision summarize-screen)" ;;
  *AI*Explain*region*)   ai_dispose "$(hyprwhspr-vision explain-region)" ;;
  *AI*Ask*about*region*) ai_dispose "$(hyprwhspr-vision ask-region)" ;;
  *Edit*last*screenshot*) hyprwhspr-vision edit-last ;;
  *) back_to show_main_menu ;;
  esac
}

show_screenshot_submenu() {
  case $(menu "Screenshot" "  Region\n  Window\n  Full screen") in
  *Region*)      omarchy-capture-screenshot region ;;
  *Window*)      omarchy-capture-screenshot windows ;;
  *Full*screen*) omarchy-capture-screenshot fullscreen ;;
  *) back_to show_capture_menu ;;
  esac
}

show_screenrecord_submenu() {
  case $(menu "Screen record" "󰗅  No audio\n󰕾  Desktop audio\n󰍬  Desktop + microphone") in
  *No*audio*)      omarchy-capture-screenrecording ;;
  *Desktop*audio*) omarchy-capture-screenrecording --with-desktop-audio ;;
  *microphone*)    omarchy-capture-screenrecording --with-desktop-audio --with-microphone-audio ;;
  *) back_to show_capture_menu ;;
  esac
}

# Wrap upstream go_to_menu: add *voice* and *capture* cases, delegate
# everything else to the original. Keeps us robust if omarchy adds new
# top-level menus or changes the existing ones.
if declare -F go_to_menu >/dev/null; then
  eval "$(declare -f go_to_menu | sed '1s/go_to_menu/_omarchy_go_to_menu_upstream/')"
  go_to_menu() {
    case "${1,,}" in
    *voice*)   show_voice_menu ;;
    *capture*) show_capture_menu ;;
    *) _omarchy_go_to_menu_upstream "$@" ;;
    esac
  }
fi
