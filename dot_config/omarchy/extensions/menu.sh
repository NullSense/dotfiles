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
  *OCR*)              ocr_region_to_clipboard ;;
  *Color*picker*)     pkill hyprpicker || setsid hyprpicker -a >/dev/null 2>&1 & ;;
  *AI*)               show_ai_submenu ;;
  *Edit*last*)        edit_last_screenshot ;;
  *) back_to show_main_menu ;;
  esac
}

# Region OCR — pick engine first, then drag region. Three engines:
#   Gemma  — fast (~2s), good general-purpose, can fumble dense tables
#   Surya  — verbatim (~15s), word-perfect, no markdown structure
#   Hybrid — Surya text + Gemma layout cleanup (~22s), best for tables
# Falls back to Tesseract via omarchy-capture-text-extraction if daemon down.
ocr_region_to_clipboard() {
  if ! hyprwhspr-ai ping >/dev/null 2>&1; then
    notify-send -a omarchy-menu -u low -t 1500 "Daemon down — using Tesseract"
    omarchy-capture-text-extraction
    return
  fi
  local engine_pick engine engine_label
  engine_pick=$(menu "OCR engine" \
    "  Hybrid — best quality, ~20s\n  Gemma — fast, ~4s\n  Granite — small, Apache 2.0, ~5s\n  Chandra — document-OCR, ~11s\n  Surya — verbatim, ~16s\n  Qwen 35B — top quality, ~60s (model swap)\n  Tesseract — instant, no structure")
  case "$engine_pick" in
    *Hybrid*)    engine=hybrid;    engine_label="Hybrid" ;;
    *Gemma*)     engine=gemma;     engine_label="Gemma" ;;
    *Granite*)   engine=granite;   engine_label="Granite" ;;
    *Chandra*)   engine=chandra;   engine_label="Chandra" ;;
    *Surya*)     engine=surya;     engine_label="Surya" ;;
    *Qwen*)      engine=qwen;      engine_label="Qwen" ;;
    *Tesseract*) omarchy-capture-text-extraction; return ;;
    *)           back_to show_capture_menu; return ;;
  esac
  notify-send -a omarchy-menu -u low -t 2000 "${engine_label} OCR — drag a region…"
  local text err rc
  # Capture stdout AND stderr separately so we can show the real reason
  # if something goes wrong. stderr is meant for diagnostics (cancelled,
  # daemon down, model error); stdout is the OCR'd text.
  local err_file
  err_file="$(mktemp)"
  text="$(hyprwhspr-ai ocr --region --engine "$engine" 2>"$err_file")"
  rc=$?
  err="$(cat "$err_file")"
  rm -f "$err_file"
  if [[ $rc -ne 0 ]]; then
    notify-send -a omarchy-menu -u normal "${engine_label} OCR failed" "${err:-(no error message)}"
    return
  fi
  if [[ -z "$text" ]]; then
    notify-send -a omarchy-menu -u normal "${engine_label} OCR — empty result" \
      "The model recognized no text. Try a tighter region around actual content, or another engine."
    return
  fi
  printf '%s' "$text" | wl-copy
  notify-send -a omarchy-menu -u low -t 2500 "󰴑    Copied (${engine_label})" \
    "$(printf '%s' "$text" | head -c 80)…"
}

# Open the most recent screenshot in satty for annotation. No AI involved —
# pure UI shortcut (was previously `hyprwhspr-vision edit-last`).
edit_last_screenshot() {
  local shots_dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures/Screenshots}}"
  local last
  last="$(/usr/bin/ls -t "${shots_dir}"/*.png 2>/dev/null | /usr/bin/head -1)"
  if [[ -z "$last" || ! -f "$last" ]]; then
    notify-send -a omarchy-menu -u normal "No screenshots found" "Looked in ${shots_dir}"
    return
  fi
  setsid satty --filename "$last" --output-filename "$last" \
    --early-exit --copy-command 'wl-copy' >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# Pick a target translation language. Favorites from
# ~/.config/hyprwhspr/languages.txt + an "Other…" walker free-text entry.
# Echoes the picked name (or NLLB code) on stdout, empty on cancel.
pick_target_language() {
  local langs_file="${XDG_CONFIG_HOME:-$HOME/.config}/hyprwhspr/languages.txt"
  local favs
  favs="$(grep -vE '^\s*(#|$)' "$langs_file" 2>/dev/null \
          || printf 'English\nGerman\nLithuanian\n')"
  local picked
  picked="$(printf '%s\n  Other…\n' "$favs" | capture_pick 'Translate to')"
  [[ -z "$picked" ]] && return 1
  if [[ "$picked" == *Other* ]]; then
    picked="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
              -p 'Language (name or ISO code, e.g. "Polish" or "pl")…' 2>/dev/null)"
    [[ -z "$picked" ]] && return 1
  fi
  printf '%s' "$picked"
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
  # Top level: pick a TASK first. Each task asks the user where the
  # input comes from (clipboard / screen / region / file).
  case $(menu "AI" "  Summarize\n  Explain\n  Ask\n  Translate") in
  *Summarize*) ai_run_task summarize ;;
  *Explain*)   ai_run_task explain ;;
  *Ask*)       ai_run_task ask ;;
  *Translate*) ai_run_translate ;;
  *) back_to show_capture_menu ;;
  esac
}

# Task runner: prompt for source (clipboard / screen / region / file), then
# for "ask" prompt the question. Dispatches to the right hyprwhspr-ai op
# (text-task for clipboard/file-text; vision-task for screen/region/file-image).
ai_run_task() {
  local task="$1"
  local task_label
  case "$task" in
    summarize) task_label="Summarize" ;;
    explain)   task_label="Explain" ;;
    ask)       task_label="Ask" ;;
  esac

  local source_pick
  source_pick=$(menu "${task_label}: source" "  Clipboard\n  Screen\n  Region\n  File")
  case "$source_pick" in
    *Clipboard*) ai_run_task_clipboard "$task" "$task_label" ;;
    *Screen*)    ai_run_task_vision "$task" "$task_label" monitor ;;
    *Region*)    ai_run_task_vision "$task" "$task_label" region ;;
    *File*)      ai_run_task_file "$task" "$task_label" ;;
    *)           back_to show_ai_submenu ;;
  esac
}

# task × clipboard → text-task (LLM on plain text via wl-paste)
ai_run_task_clipboard() {
  local task="$1" task_label="$2"
  local clip
  clip="$(wl-paste 2>/dev/null)"
  if [[ -z "$clip" ]]; then
    notify-send -a omarchy-menu -u normal "Clipboard empty" "Nothing to ${task}"
    return
  fi
  local q=""
  if [[ "$task" == "ask" ]]; then
    q="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
         -p 'Question about clipboard text…' 2>/dev/null)"
    [[ -z "$q" ]] && { back_to show_ai_submenu; return; }
  fi
  notify-send -a omarchy-menu -u low -t 2000 "${task_label} (clipboard)…"
  if [[ "$task" == "ask" ]]; then
    ai_dispose "$(printf '%s' "$clip" | hyprwhspr-ai text-task ask --question "$q" 2>/dev/null)"
  else
    ai_dispose "$(printf '%s' "$clip" | hyprwhspr-ai text-task "$task" 2>/dev/null)"
  fi
}

# task × screen|region → vision-task (LLM on a captured image)
ai_run_task_vision() {
  local task="$1" task_label="$2" source="$3"
  local q=""
  if [[ "$task" == "ask" ]]; then
    q="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
         -p "Question about ${source}…" 2>/dev/null)"
    [[ -z "$q" ]] && { back_to show_ai_submenu; return; }
  fi
  notify-send -a omarchy-menu -u low -t 2000 "${task_label} (${source})…"
  if [[ "$task" == "ask" ]]; then
    ai_dispose "$(hyprwhspr-ai vision-task ask --source "$source" --question "$q" 2>/dev/null)"
  else
    ai_dispose "$(hyprwhspr-ai vision-task "$task" --source "$source" 2>/dev/null)"
  fi
}

# task × file → walker file picker, branch on extension:
#   image (png/jpg/etc) → vision-task --source file
#   text  (everything else) → text-task with file content piped in
ai_run_task_file() {
  local task="$1" task_label="$2"
  local f
  f="$(omarchy-launch-walker --dmenu -I --width 360 --minheight 1 --maxheight 630 \
       -p 'File path (absolute or ~)…' 2>/dev/null)"
  [[ -z "$f" ]] && { back_to show_ai_submenu; return; }
  f="${f/#\~/$HOME}"
  if [[ ! -f "$f" ]]; then
    notify-send -a omarchy-menu -u normal "File not found" "$f"
    return
  fi
  local q=""
  if [[ "$task" == "ask" ]]; then
    q="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
         -p 'Question about file…' 2>/dev/null)"
    [[ -z "$q" ]] && { back_to show_ai_submenu; return; }
  fi
  case "${f,,}" in
    *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.gif)
      notify-send -a omarchy-menu -u low -t 2000 "${task_label} (image)…"
      if [[ "$task" == "ask" ]]; then
        ai_dispose "$(hyprwhspr-ai vision-task ask --source file --image "$f" --question "$q" 2>/dev/null)"
      else
        ai_dispose "$(hyprwhspr-ai vision-task "$task" --source file --image "$f" 2>/dev/null)"
      fi
      ;;
    *)
      # Read text file content. Cap at 100KB to avoid blowing up Gemma's context.
      local content
      content="$(/usr/bin/head -c 102400 "$f" 2>/dev/null)"
      if [[ -z "$content" ]]; then
        notify-send -a omarchy-menu -u normal "File empty or unreadable" "$f"
        return
      fi
      notify-send -a omarchy-menu -u low -t 2000 "${task_label} (text file)…"
      if [[ "$task" == "ask" ]]; then
        ai_dispose "$(printf '%s' "$content" | hyprwhspr-ai text-task ask --question "$q" 2>/dev/null)"
      else
        ai_dispose "$(printf '%s' "$content" | hyprwhspr-ai text-task "$task" 2>/dev/null)"
      fi
      ;;
  esac
}

# Translate: pick source (clipboard / region / file), then target language.
ai_run_translate() {
  local source_pick
  source_pick=$(menu "Translate: source" "  Clipboard\n  Region\n  File")
  case "$source_pick" in
    *Clipboard*)
      local clip target
      clip="$(wl-paste 2>/dev/null)"
      if [[ -z "$clip" ]]; then
        notify-send -a omarchy-menu -u normal "Clipboard empty" "Nothing to translate"
        return
      fi
      target="$(pick_target_language)" || { back_to show_ai_submenu; return; }
      notify-send -a omarchy-menu -u low -t 2000 "Translating to ${target}…"
      ai_dispose "$(printf '%s' "$clip" | hyprwhspr-ai translate --target "$target" 2>/dev/null)"
      ;;
    *Region*)
      local target
      target="$(pick_target_language)" || { back_to show_ai_submenu; return; }
      notify-send -a omarchy-menu -u low -t 2000 "Reading + translating to ${target}…"
      ai_dispose "$(hyprwhspr-ai translate --target "$target" --region 2>/dev/null)"
      ;;
    *File*)
      local f target
      f="$(omarchy-launch-walker --dmenu -I --width 360 --minheight 1 --maxheight 630 \
           -p 'File path (absolute or ~)…' 2>/dev/null)"
      [[ -z "$f" ]] && { back_to show_ai_submenu; return; }
      f="${f/#\~/$HOME}"
      [[ ! -f "$f" ]] && { notify-send -a omarchy-menu -u normal "File not found" "$f"; return; }
      target="$(pick_target_language)" || { back_to show_ai_submenu; return; }
      case "${f,,}" in
        *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.gif)
          notify-send -a omarchy-menu -u low -t 2000 "OCR + translate to ${target}…"
          # OCR via daemon (plain mode = strip markdown for NLLB), then translate.
          local ocr_text
          ocr_text="$(hyprwhspr-ai ocr --mode plain "$f" 2>/dev/null)"
          if [[ -z "$ocr_text" ]]; then
            notify-send -a omarchy-menu -u normal "OCR returned empty" "$f"
            return
          fi
          ai_dispose "$(printf '%s' "$ocr_text" | hyprwhspr-ai translate --target "$target" 2>/dev/null)"
          ;;
        *)
          local content
          content="$(/usr/bin/head -c 102400 "$f" 2>/dev/null)"
          [[ -z "$content" ]] && { notify-send -a omarchy-menu -u normal "File empty or unreadable" "$f"; return; }
          notify-send -a omarchy-menu -u low -t 2000 "Translating to ${target}…"
          ai_dispose "$(printf '%s' "$content" | hyprwhspr-ai translate --target "$target" 2>/dev/null)"
          ;;
      esac
      ;;
    *) back_to show_ai_submenu ;;
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
    notify-send -a omarchy-menu -u low -t 2000 "Asking Gemma 4…"
    ai_dispose "$(hyprwhspr-ai vision analyze_file --image "$file" --prompt \
      'Explain what is shown in this screenshot. If it is an error or stack trace, decode the cause. If it is a UI, describe what it does. If it is text, summarize. Be concise — 2 to 4 sentences.' 2>/dev/null)"
    ;;
  *Analyze*ask*custom*)
    local q
    q="$(omarchy-launch-walker --dmenu -I --width 295 --minheight 1 --maxheight 630 \
      -p 'Question about this screenshot…' 2>/dev/null)"
    [[ -z "$q" ]] && return
    notify-send -a omarchy-menu -u low -t 2000 "Asking Gemma 4…"
    ai_dispose "$(hyprwhspr-ai vision analyze_file --image "$file" --prompt "$q" 2>/dev/null)"
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
