```
$ git log --oneline --decorate -n 5
9f7e38d (HEAD -> main) Phase 2: flip post_transcription_hook to daemon
3a1c042 hyprwhspr-ai daemon scaffold + systemd unit
b48f9d1 chezmoi: bump _ZO_DOCTOR=0 in zshenv
2e7c891 waybar: pin canonical config.jsonc
771b03e agent-vault: scope SSH_AUTH_SOCK to systemd units

$ cargo test --release
   Compiling hyprwhspr-bridge v0.3.1 (/home/nullsense/dev/bridge)
   Compiling tokio v1.42.1
   Compiling serde_json v1.0.140
    Finished `release` profile [optimized] target(s) in 47.21s
     Running unittests src/lib.rs (target/release/deps/hyprwhspr_bridge-9a8f)

running 24 tests
test client::tests::handles_partial_response ... ok
test client::tests::reconnects_after_socket_close ... ok
test parser::tests::malformed_json_returns_err ... ok
test parser::tests::ascii_art_passthrough FAILED

failures:

---- parser::tests::ascii_art_passthrough stdout ----
thread 'parser::tests::ascii_art_passthrough' panicked at src/parser.rs:142:9:
assertion `left == right` failed
  left:  "+----+\n| ok |\n+----+"
  right: "┌────┐\n│ ok │\n└────┘"

test result: FAILED. 23 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out

$ echo $?
101
```
