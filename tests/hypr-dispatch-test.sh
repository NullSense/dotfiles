#!/usr/bin/env bash
# hypr-dispatch: one helper, two Hyprland config managers (hyprlang | Lua).
# Fake hyprctl mimics src/debug/HyprCtl.cpp @ v0.56.2: `eval` answers `ok` only in Lua mode;
# `dispatch`/`keyword` are logged. Also drives hypr-preselect's tag helpers through both modes.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HD="$ROOT/home/bin/hypr-dispatch"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: expected '$1', got '$2'"; }

cat >"$TMP/hyprctl" <<'E2'
#!/usr/bin/env bash
if [ "${FAKE_DOWN:-0}" = 1 ]; then echo "Couldn't connect" >&2; exit 1; fi
case "$1" in
    eval)
        if [ "$FAKE_MODE" = lua ]; then
            [ "$2" = 'return true' ] || printf '%s\n' "$*" >>"$FAKE_LOG"
            printf 'ok\n'
        else
            printf 'eval is only supported with the lua config manager\n'
        fi ;;
    dispatch|keyword)
        printf '%s\n' "$*" >>"$FAKE_LOG"
        if [ "${FAKE_FAIL:-0}" = 1 ]; then printf 'Invalid dispatcher\n'; else printf 'ok\n'; fi ;;
    *) printf 'unexpected: %s\n' "$*" >&2; exit 1 ;;
esac
E2
chmod +x "$TMP/hyprctl"
export HYPR_DISPATCH_HYPRCTL="$TMP/hyprctl" FAKE_LOG="$TMP/log" HYPRLAND_INSTANCE_SIGNATURE=test
last() { tail -n 1 "$FAKE_LOG"; }

for mode in legacy lua; do
    export FAKE_MODE=$mode
    : >"$FAKE_LOG"
    assert_eq "$mode" "$("$HD" mode)" "mode probe ($mode)"

    "$HD" dpms on DP-1
    if [ $mode = lua ]; then
        assert_eq 'dispatch hl.dsp.dpms({ action = "on", monitor = "DP-1" })' "$(last)" "dpms on ($mode)"
    else
        assert_eq 'dispatch dpms on DP-1' "$(last)" "dpms on ($mode)"
    fi
    "$HD" dpms off
    if [ $mode = lua ]; then
        assert_eq 'dispatch hl.dsp.dpms({ action = "off" })' "$(last)" "dpms off all ($mode)"
    else
        assert_eq 'dispatch dpms off' "$(last)" "dpms off all ($mode)"
    fi

    # A leading '-' inside the dispatch string must stay one argument.
    "$HD" dispatch 'tagwindow -psel-d address:0x1' 'hl.dsp.window.tag({ tag = "-psel-d", window = "address:0x1" })'
    if [ $mode = lua ]; then
        assert_eq 'dispatch hl.dsp.window.tag({ tag = "-psel-d", window = "address:0x1" })' "$(last)" "dispatch ($mode)"
    else
        assert_eq 'dispatch tagwindow -psel-d address:0x1' "$(last)" "dispatch ($mode)"
    fi

    "$HD" keyword decoration:screen_shader /x.frag 'hl.config({ decoration = { screen_shader = [=[/x.frag]=] } })'
    if [ $mode = lua ]; then
        assert_eq 'eval hl.config({ decoration = { screen_shader = [=[/x.frag]=] } })' "$(last)" "keyword ($mode)"
    else
        assert_eq 'keyword decoration:screen_shader /x.frag' "$(last)" "keyword ($mode)"
    fi

    rc=0; FAKE_FAIL=1 "$HD" dispatch bogus bogus 2>/dev/null || rc=$?
    assert_eq 1 "$rc" "a non-ok answer is exit 1 ($mode)"
done

rc=0; FAKE_DOWN=1 "$HD" dpms on DP-1 2>/dev/null || rc=$?
assert_eq 3 "$rc" "unreachable Hyprland is exit 3"
rc=0; "$HD" bogus 2>/dev/null || rc=$?
assert_eq 2 "$rc" "usage error is exit 2"

# --- the ported scripts, driven through the same fake, in both modes -----------------------------
mkdir -p "$TMP/home/bin"
ln -s "$HD" "$TMP/home/bin/hypr-dispatch"
for mode in legacy lua; do
    export FAKE_MODE=$mode
    : >"$FAKE_LOG"
    HOME="$TMP/home" PATH="$TMP:$PATH" bash -c '
        . /dev/stdin <<<"$(sed -n "/^unpaint()/,/^}/p; /^paint()/,/^}/p" "'"$ROOT"'/home/bin/hypr-preselect")"
        HD="$HOME/bin/hypr-dispatch"; TAG_PREFIX=psel-; unpaint 0xabc' || true
    n=$(grep -c . "$FAKE_LOG" || true)
    assert_eq 4 "$n" "hypr-preselect unpaint sends 4 tag removals ($mode)"
    if [ $mode = lua ]; then
        grep -Fq 'dispatch hl.dsp.window.tag({ tag = "-psel-r", window = "address:0xabc" })' "$FAKE_LOG" \
            || fail "hypr-preselect Lua tag expression"
    else
        grep -Fqx 'dispatch tagwindow -psel-r address:0xabc' "$FAKE_LOG" || fail "hypr-preselect legacy tag dispatch"
    fi
done

printf 'PASS: hypr-dispatch\n'
