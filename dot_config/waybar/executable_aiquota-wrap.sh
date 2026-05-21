#!/usr/bin/env bash
# Waybar wrapper for aiquota — guarantees a valid JSON object every poll, so
# transient failures (binary missing, timeout, panic, malformed output) render
# as a "⚠ aiquota" pill with the error in the tooltip instead of waybar
# silently dropping the module.
#
# All failure paths exit 0 with a synthetic JSON payload. Real success passes
# the binary's stdout through untouched.

set -u

BIN="${AIQUOTA_BIN:-$HOME/Programming/aiquota/target/release/aiquota}"
TIMEOUT="${AIQUOTA_TIMEOUT:-10}"

emit_error() {
  # $1 = short reason header, $2 = full detail (stderr / output blob)
  local reason="$1"
  local detail="$2"
  jq -cn --arg reason "$reason" --arg detail "$detail" '
    def pango_escape: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    {
      text: "<span foreground=\"#fb4934\">⚠</span> aiquota",
      tooltip: ("<span foreground=\"#fb4934\"><b>aiquota error</b></span>\n"
                + ($reason | pango_escape)
                + "\n\n<span foreground=\"#928374\" size=\"small\">"
                + ($detail | pango_escape)
                + "</span>"),
      class: "error",
      alt: "error"
    }
  '
}

if [ ! -x "$BIN" ]; then
  emit_error "binary not found or not executable" "expected: $BIN

build with:
  cd $(dirname "$(dirname "$(dirname "$BIN")")") && cargo build --release"
  exit 0
fi

stderr_file=$(mktemp -t aiquota-wrap.XXXXXX.err) || {
  emit_error "could not allocate temp file" "mktemp failed"
  exit 0
}
trap 'rm -f "$stderr_file"' EXIT

out=$(timeout "$TIMEOUT" "$BIN" waybar 2>"$stderr_file")
rc=$?
err=$(cat "$stderr_file" 2>/dev/null || true)

if [ $rc -ne 0 ]; then
  case $rc in
    124) reason="timed out after ${TIMEOUT}s" ;;
    126) reason="binary not executable (permission)" ;;
    127) reason="binary not found at runtime" ;;
    *)   reason="exited with code $rc" ;;
  esac
  emit_error "$reason" "${err:-(no stderr)}"
  exit 0
fi

if [ -z "$out" ]; then
  emit_error "empty stdout" "${err:-(no stderr)}"
  exit 0
fi

# Validate the binary's output is well-formed JSON. If aiquota ever panics
# mid-print or emits log noise on stdout, we want that to surface as an error
# rather than silently break the module.
if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
  emit_error "malformed JSON from aiquota" "$out"
  exit 0
fi

printf '%s\n' "$out"
