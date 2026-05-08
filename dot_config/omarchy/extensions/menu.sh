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
  # Flat top-level: one entry per category. Icons prepended consistently
  # (Font Awesome) so every line reads at a glance:
  #     Screenshot   (fa-image)
  #     Recording    (fa-video)
  #     OCR          (fa-file-text-o)
  #     Color picker (fa-eyedropper)
  #     AI           (fa-magic / sparkles)
  #     Edit         (fa-pencil-square-o)
  case $(menu "Capture" "  Screenshot\n  Recording\n  OCR\n  Color picker\n  AI…\n  Edit last screenshot") in
  *Screenshot*)       capture_with_disposal smart ;;
  *Recording*)        recording_action ;;
  *OCR*)              omarchy-capture-text-extraction ;;
  *Color*picker*)     pkill hyprpicker || setsid hyprpicker -a >/dev/null 2>&1 & ;;
  *AI*)               show_ai_submenu ;;
  *Edit*last*)        hyprwhspr-vision edit-last ;;
  *) back_to show_main_menu ;;
  esac
}

# Single Recording entry — toggle behavior. If gpu-screen-recorder is
# running, this stops it. Otherwise it asks for audio mode and starts.
recording_action() {
  if pgrep -x gpu-screen-recorder >/dev/null 2>&1; then
    omarchy-capture-screenrecording --stop-recording
    notify-send -a omarchy-menu -u low -t 2500 "Recording stopped" "Saved to ~/Videos"
    return
  fi
  case $(menu "Start recording" "󰗇  No audio\n󰕾  Desktop audio\n󰍬  Desktop + microphone") in
  *No*audio*)       omarchy-capture-screenrecording ;;
  *Desktop*audio*)  omarchy-capture-screenrecording --with-desktop-audio ;;
  *microphone*)     omarchy-capture-screenrecording --with-desktop-audio --with-microphone-audio ;;
  *) back_to show_capture_menu ;;
  esac
}

show_ai_submenu() {
  case $(menu "AI" "  Summarize screen\n  Explain region\n  Ask about region\n  Translate region\n  Translate clipboard") in
  *Summarize*screen*)    ai_dispose "$(hyprwhspr-vision summarize-screen)" ;;
  *Explain*region*)      ai_dispose "$(hyprwhspr-vision explain-region)" ;;
  *Ask*about*region*)    ai_dispose "$(hyprwhspr-vision ask-region)" ;;
  *Translate*region*)    ai_dispose "$(hyprwhspr-translate region)" ;;
  *Translate*clipboard*) ai_dispose "$(hyprwhspr-translate clipboard)" ;;
  *) back_to show_capture_menu ;;
  esac
}

# Run an omarchy screenshot in the requested mode, then offer a disposal
# walker with the just-saved file. omarchy-capture-screenshot saves to
# clipboard + file unconditionally; we layer additional actions on top
# (edit / re-copy / save elsewhere / AI explain / AI ask / open / done).
capture_with_disposal() {
  local mode="$1"
  omarchy-capture-screenshot "$mode" || return
  local shots_dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures/Screenshots}}"
  local file
  file="$(/usr/bin/ls -t "${shots_dir}"/*.png 2>/dev/null | /usr/bin/head -1)"
  [[ -z "$file" || ! -f "$file" ]] && return
  capture_dispose "$file"
}

# Post-capture walker for screenshots. The screenshot is already saved +
# clipboard'd by omarchy; this menu offers extra actions.
capture_dispose() {
  local file="$1"
  local label="${file##*/}"
  case $(menu "Captured: $label" "  Edit in satty\n  Re-copy to clipboard\n  Save to specific location\n  Analyze: explain\n  Analyze: ask custom question\n  Open in image viewer\n  Discard (delete file)\n  Done") in
  *Edit*in*satty*)
    setsid satty --filename "$file" --output-filename "$file" \
      --early-exit --copy-command 'wl-copy' >/dev/null 2>&1 &
    disown 2>/dev/null || true
    ;;
  *Re-copy*to*clipboard*)
    wl-copy < "$file"
    notify-send -a omarchy-menu -u low -t 2000 "Re-copied to clipboard" "$label"
    ;;
  *Save*to*specific*)
    local target dst
    target="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
      -p 'Save as (path or filename)…' 2>/dev/null)"
    [[ -z "$target" ]] && return
    # If user gave a bare filename, drop it into ~/Documents/screenshots/
    if [[ "$target" != /* && "$target" != ~* ]]; then
      mkdir -p "$HOME/Documents/screenshots"
      dst="$HOME/Documents/screenshots/$target"
    else
      dst="${target/#~/$HOME}"
      mkdir -p "$(dirname "$dst")"
    fi
    [[ "$dst" != *.png ]] && dst="${dst}.png"
    cp "$file" "$dst" && notify-send -a omarchy-menu -u low -t 3000 "Saved" "$dst"
    ;;
  *Analyze*explain*)
    ai_dispose "$(hyprwhspr-vision analyze-file "$file" \
      'Explain what is shown in this screenshot. If it is an error or stack trace, decode the cause. If it is a UI, describe what it does. If it is text, summarize. Be concise — 2 to 4 sentences.')"
    ;;
  *Analyze*ask*custom*)
    local q
    q="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
      -p 'Question about this screenshot…' 2>/dev/null)"
    [[ -z "$q" ]] && return
    ai_dispose "$(hyprwhspr-vision analyze-file "$file" "$q")"
    ;;
  *Open*in*image*viewer*)
    setsid xdg-open "$file" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    ;;
  *Discard*delete*)
    rm -f "$file" && notify-send -a omarchy-menu -u low -t 2000 "Deleted" "$label"
    ;;
  *Done*|*) : ;;
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
