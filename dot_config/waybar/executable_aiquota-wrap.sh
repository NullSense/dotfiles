#!/usr/bin/env bash
# aiquota waybar wrapper.
#
# systemd-spawned waybar doesn't inherit the interactive-shell agent-vault env
# (HTTPS_PROXY / CURL_CA_BUNDLE / SSL_CERT_FILE), so aiquota's HTTPS calls to
# api.anthropic.com / openai.com bypass the vault and miss credentials.
# This wrapper supplies the env explicitly. The cert path is canonical
# agent-vault MITM-CA location.
set -eu

VAULT_CA="$HOME/.agent-vault/mitm-ca.pem"

if [ -f "$VAULT_CA" ]; then
  export SSL_CERT_FILE="$VAULT_CA"
  export CURL_CA_BUNDLE="$VAULT_CA"
fi

exec "$HOME/code/aiquota/target/release/aiquota" waybar
