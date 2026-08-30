#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROUTER="$ROOT/home/bin/url-router"
DESKTOP="$ROOT/home/.local/share/applications/url-router.desktop"
MIMEAPPS="$ROOT/home/.config/mimeapps.list"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

cat >"$TMP/capture" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$0")" "$@" >"$URL_ROUTER_TEST_OUTPUT"
EOF
chmod +x "$TMP/capture"
ln -s capture "$TMP/spotify"
ln -s capture "$TMP/helium"

export URL_ROUTER_SPOTIFY="$TMP/spotify"
export URL_ROUTER_BROWSER="$TMP/helium"
export URL_ROUTER_TEST_OUTPUT="$TMP/output"

assert_route() {
    local expected_program=$1 expected_url=$2 input_url=$3
    "$ROUTER" "$input_url"
    mapfile -t output <"$URL_ROUTER_TEST_OUTPUT"
    [[ ${output[0]:-} == "$expected_program" ]] \
        || fail "$input_url used ${output[0]:-<nothing>}, expected $expected_program"
    [[ ${output[1]:-} == "$expected_url" ]] \
        || fail "$input_url became ${output[1]:-<nothing>}, expected $expected_url"
    [[ ${#output[@]} == 2 ]] \
        || fail "$input_url produced unexpected extra arguments"
}

assert_route spotify spotify:track:3n3Ppam7vgaVa1iaRUc9Lp \
    'https://open.spotify.com/track/3n3Ppam7vgaVa1iaRUc9Lp?si=abc123'
assert_route spotify spotify:album:6DEjYFkNZh67HP7R9PSZvv \
    'https://open.spotify.com/intl-de/album/6DEjYFkNZh67HP7R9PSZvv#details'
assert_route spotify spotify:playlist:37i9dQZF1DXcBWIGoYBM5M \
    'http://OPEN.SPOTIFY.COM/embed/playlist/37i9dQZF1DXcBWIGoYBM5M/'
assert_route helium 'https://open.spotify.com.evil.example/track/not-spotify' \
    'https://open.spotify.com.evil.example/track/not-spotify'
assert_route helium 'https://example.com/music' 'https://example.com/music'

if "$ROUTER" >/dev/null 2>&1; then
    fail "router must reject a missing URL"
fi
if "$ROUTER" https://example.com https://example.org >/dev/null 2>&1; then
    fail "router must reject multiple URLs"
fi

grep -Fqx 'Exec=/home/nullsense/bin/url-router %u' "$DESKTOP"
grep -Fqx 'MimeType=x-scheme-handler/http;x-scheme-handler/https;' "$DESKTOP"
grep -Fqx 'x-scheme-handler/http=url-router.desktop' "$MIMEAPPS"
grep -Fqx 'x-scheme-handler/https=url-router.desktop' "$MIMEAPPS"

printf 'PASS: url-router\n'
