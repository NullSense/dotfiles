#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/home/.local/libexec/hermes-secret-env"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Eq '^[[:space:]]+OPENCODE_GO_API_KEY \\$' "$helper" \
    || fail 'Hermes secret allowlist omits OPENCODE_GO_API_KEY'
grep -Fq 'OPENCODE_GO_API_KEY:-agent-vault-managed' "$helper" \
    || fail 'Hermes does not use the non-secret Agent Vault marker'

if grep -R -Eq 'api_key:.*OPENCODE_GO|opencode-go/kimi-k3' \
    "$repo_root/home/.config/litellm/config.yaml" \
    "$repo_root/home/.config/litellm/models.yaml"; then
    fail 'OpenCode Go must use Hermes native routing, not a partial LiteLLM shim'
fi

printf 'PASS: Hermes native OpenCode Go secret boundary\n'
