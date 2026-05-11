#!/usr/bin/env bash
# Render every cases/*.html → images/*.png via Chromium headless.
# Output PNGs are deterministic-ish (same DOM → same render) so the
# benchmark can re-run without regenerating images.

set -euo pipefail
cd "$(dirname "$0")"

mkdir -p images

# Chromium variants Arch users tend to have.
CHROMIUM=""
for cmd in chromium chromium-browser google-chrome brave brave-browser; do
    if command -v "$cmd" >/dev/null 2>&1; then
        CHROMIUM="$cmd"
        break
    fi
done
if [[ -z "$CHROMIUM" ]]; then
    echo "no chromium-family browser on PATH; install one to render test images" >&2
    exit 1
fi

# Render each case
shopt -s nullglob
count=0
for html in cases/*.html; do
    name="$(basename "${html%.html}")"
    out="images/${name}.png"
    if [[ "$out" -nt "$html" ]]; then
        # Cache: only re-render if the source HTML is newer.
        continue
    fi
    echo "→ rendering $name"
    "$CHROMIUM" \
        --headless \
        --disable-gpu \
        --no-sandbox \
        --window-size=820,1100 \
        --hide-scrollbars \
        --screenshot="$(realpath "$out")" \
        "file://$(realpath "$html")" >/dev/null 2>&1
    if [[ ! -s "$out" ]]; then
        echo "  ✗ failed: $out is empty" >&2
        rm -f "$out"
        exit 2
    fi
    count=$((count + 1))
done

if [[ $count -eq 0 ]]; then
    echo "(all images already up-to-date — nothing to render)"
else
    echo "rendered $count image(s)"
fi
echo
echo "images/:"
/usr/bin/ls -la images/
