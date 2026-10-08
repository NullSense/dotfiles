#!/usr/bin/env bash
# The sccache-cargo rustc-wrapper must keep cargo-only CARGO_* variables out of
# sccache's cache key without changing what any compile produces: crates that
# read a removed variable through env!/option_env! must see the real value,
# on cache misses and on cache hits, and everything else must share entries.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WRAPPER="$ROOT/home/.local/libexec/sccache-cargo/sccache"
SCCACHE=/usr/bin/sccache
PORT=4259

# Start from a known environment: no inherited CARGO_*, wrapper or sccache
# settings. An isolated CARGO_HOME keeps ~/.cargo/config.toml (global
# rustc-wrapper, linker flags) out of the builds.
while IFS= read -r name; do
    case $name in
        CARGO_* | SCCACHE_* | RUSTC_WRAPPER | RUSTC_WORKSPACE_WRAPPER | RUSTFLAGS) unset "$name" ;;
    esac
done < <(compgen -e)

TMP=$(mktemp -d /var/tmp/sccache-cargo-wrapper-test.XXXXXX)
export CARGO_HOME="$TMP/cargo-home"
export SCCACHE_SERVER_PORT=$PORT SCCACHE_DIR="$TMP/cache" SCCACHE_CONF="$TMP/sccache.conf"
export SCCACHE_IDLE_TIMEOUT=0
mkdir -p "$CARGO_HOME" "$SCCACHE_DIR"
: >"$SCCACHE_CONF"
cleanup() {
    "$SCCACHE" --stop-server >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected=$1 actual=$2 label=$3
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

# Workspace: `opt` reads removed variables through option_env! (compiles
# either way, so sccache caches it), `req` reads one through env! (a compile
# error without it), `plain` reads none. `app` prints what opt and req saw.
W="$TMP/ws"
mkdir -p "$W/opt/src" "$W/req/src" "$W/plain/src" "$W/app/src"
cat >"$W/Cargo.toml" <<'EOF'
[workspace]
members = ["opt", "req", "plain", "app"]
resolver = "2"

[profile.dev]
# Incremental compiles are never cached by sccache.
incremental = false
EOF
for crate in opt req plain; do
    printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2021"\n' "$crate" >"$W/$crate/Cargo.toml"
done
cat >"$W/app/Cargo.toml" <<'EOF'
[package]
name = "app"
version = "0.1.0"
edition = "2021"

[dependencies]
opt = { path = "../opt" }
req = { path = "../req" }
EOF
cat >"$W/opt/src/lib.rs" <<'EOF'
pub const TARGET_DIR: Option<&str> = option_env!("CARGO_TARGET_DIR");
pub const PROFILE_DEV_DEBUG: Option<&str> = option_env!("CARGO_PROFILE_DEV_DEBUG");
fn opt_unused() {}
EOF
cat >"$W/req/src/lib.rs" <<'EOF'
pub const HTTP_TIMEOUT: &str = env!("CARGO_HTTP_TIMEOUT");
EOF
cat >"$W/plain/src/lib.rs" <<'EOF'
pub fn answer() -> u32 {
    42
}
fn plain_unused() {}
EOF
cat >"$W/app/src/main.rs" <<'EOF'
fn main() {
    println!("{:?} {:?} {:?}", opt::TARGET_DIR, opt::PROFILE_DEV_DEBUG, req::HTTP_TIMEOUT);
}
EOF

"$SCCACHE" --start-server >/dev/null || fail "isolated sccache server on port $PORT did not start"

stat_count() {
    "$SCCACHE" --show-stats --stats-format json |
        python3 -c 'import json, sys; print(json.load(sys.stdin)["stats"][sys.argv[1]]["counts"].get("Rust", 0))' "$1"
}

count() {
    grep -cF -- "$1" "$2" || true
}

# The variables under test; CARGO_PROFILE_DEV_DEBUG=true is the dev default,
# so it doesn't change rustc's arguments.
export CARGO_PROFILE_DEV_DEBUG=true CARGO_HTTP_TIMEOUT=7 CARGO_TERM_COLOR=never

# 1. Values a crate reads through env!/option_env! match an unwrapped build.
export CARGO_TARGET_DIR="$TMP/target-a"
(cd "$W" && cargo build -q --bin app) 2>"$TMP/build0.err" || { cat "$TMP/build0.err" >&2; fail "unwrapped build failed"; }
expected=$("$CARGO_TARGET_DIR/debug/app")
assert_eq "Some(\"$TMP/target-a\") Some(\"true\") \"7\"" "$expected" "unwrapped build sees the variables"
rm -rf "$CARGO_TARGET_DIR"

"$SCCACHE" --zero-stats >/dev/null 2>&1
(cd "$W" && RUSTC_WRAPPER="$WRAPPER" cargo build --bin app) 2>"$TMP/build1.err" ||
    { cat "$TMP/build1.err" >&2; fail "wrapped build failed"; }
assert_eq "$expected" "$("$CARGO_TARGET_DIR/debug/app")" "wrapped build output equals unwrapped build"
# The direct recompile replaces sccache's output: diagnostics reach cargo once.
assert_eq 1 "$(count 'function `opt_unused` is never used' "$TMP/build1.err")" "opt warning forwarded once"
assert_eq 0 "$(count 'not defined at compile time' "$TMP/build1.err")" "env! error from the sccache run not forwarded"
assert_eq 1 "$(stat_count cache_misses)" "opt was compiled through sccache (req failed there, app is a bin)"

# 2. Cache hit whose replayed dep-info still names a removed variable: opt is
# served from the cache, then recompiled directly with the real value.
export CARGO_TARGET_DIR="$TMP/target-b"
"$SCCACHE" --zero-stats >/dev/null 2>&1
(cd "$W" && RUSTC_WRAPPER="$WRAPPER" cargo build -q --bin app) 2>"$TMP/build2.err" ||
    { cat "$TMP/build2.err" >&2; fail "second wrapped build failed"; }
assert_eq 1 "$(stat_count cache_hits)" "opt is a cache hit across target dirs"
assert_eq "Some(\"$TMP/target-b\") Some(\"true\") \"7\"" "$("$CARGO_TARGET_DIR/debug/app")" \
    "cache hit still yields the real CARGO_TARGET_DIR"

# 3. A crate that reads none of them shares one cache entry across
# environments that differ only in cargo-only variables.
"$SCCACHE" --zero-stats >/dev/null 2>&1
(
    cd "$W"
    unset CARGO_TERM_COLOR CARGO_HTTP_TIMEOUT CARGO_TARGET_DIR
    RUSTC_WRAPPER="$WRAPPER" cargo build -p plain --target-dir "$TMP/target-c" 2>"$TMP/build3.err"
) || fail "plain build failed"
(
    cd "$W"
    CARGO_TERM_COLOR=never CARGO_HTTP_TIMEOUT=9 CARGO_TARGET_DIR="$TMP/target-d" \
        RUSTC_WRAPPER="$WRAPPER" cargo build -p plain 2>"$TMP/build3-hit.err"
) || fail "plain rebuild failed"
assert_eq 1 "$(stat_count cache_misses)" "plain compiled once"
assert_eq 1 "$(stat_count cache_hits)" "plain is a cache hit when only cargo-only variables differ"
assert_eq 1 "$(count 'function `plain_unused` is never used' "$TMP/build3.err")" "plain warning forwarded once"
assert_eq 1 "$(count 'function `plain_unused` is never used' "$TMP/build3-hit.err")" "cache hit replays the warning once"

# 4. A genuine compile error is not retried and is reported once.
if (cd "$W" && unset CARGO_HTTP_TIMEOUT && RUSTC_WRAPPER="$WRAPPER" cargo build -p req) 2>"$TMP/build4.err"; then
    fail "req built without CARGO_HTTP_TIMEOUT"
fi
assert_eq 1 "$(count 'environment variable `CARGO_HTTP_TIMEOUT` not defined' "$TMP/build4.err")" \
    "missing variable reported once"

printf 'ok\n'
