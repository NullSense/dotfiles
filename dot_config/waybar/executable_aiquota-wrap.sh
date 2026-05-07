#!/usr/bin/env bash
# aiquota waybar wrapper.
#
# systemd-spawned waybar doesn't inherit the interactive-shell env, so calls
# to api.anthropic.com / openai.com need agent-vault credentials injected
# explicitly. `agent-vault vault run` is the canonical wrapper — it sets
# HTTPS_PROXY + the MITM CA env for the child only, project-recommended.
set -eu

exec agent-vault vault run --vault default -- \
    "$HOME/code/aiquota/target/release/aiquota" waybar
