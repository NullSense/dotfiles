#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/home/.local/libexec/hermes-secret-env"
models="$repo_root/home/.config/litellm/models.yaml"
hermes_config=${HERMES_CONFIG:-$HOME/.hermes/config.yaml}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Eq '^[[:space:]]+OPENCODE_GO_API_KEY \\$' "$helper" \
    || fail 'Hermes secret allowlist omits OPENCODE_GO_API_KEY'
grep -Fq 'OPENCODE_GO_API_KEY:-agent-vault-managed' "$helper" \
    || fail 'Hermes does not use the non-secret Agent Vault marker'

[[ $(yq -r '[.model_list[] | select(.model_name == "opencode-go/*")] | length' "$models") == 1 ]] \
    || fail 'LiteLLM must define exactly one OpenCode Go wildcard deployment'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go/*") | .litellm_params.model' "$models") == 'openai/*' ]] \
    || fail 'LiteLLM must preserve the OpenCode Go wildcard model suffix'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go/*") | .litellm_params.api_base' "$models") == 'https://opencode.ai/zen/go/v1' ]] \
    || fail 'LiteLLM OpenCode Go upstream URL is incorrect'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go/*") | .litellm_params.api_key' "$models") == 'os.environ/OPENCODE_GO_API_KEY' ]] \
    || fail 'LiteLLM must resolve the OpenCode Go key from its process environment'

[[ $(yq -r '.delegation.model // ""' "$hermes_config") == 'opencode-go/deepseek-v4-flash' ]] \
    || fail 'Hermes delegation must use the namespaced LiteLLM alias'
[[ $(yq -r '.delegation.provider // ""' "$hermes_config") == '' ]] \
    || fail 'Hermes delegation provider must not bypass the explicit gateway URL'
[[ $(yq -r '.delegation.base_url // ""' "$hermes_config") == 'http://127.0.0.1:8787/v1' ]] \
    || fail 'Hermes delegation must route through the Headroom proxy'
[[ $(yq -r '.delegation.api_mode // ""' "$hermes_config") == chat_completions ]] \
    || fail 'The initial OpenCode Go route must use chat completions'
[[ $(yq -r '.auxiliary.background_review.model // ""' "$hermes_config") == 'opencode-go/deepseek-v4-flash' ]] \
    || fail 'Background review must use the remote OpenCode Go route instead of contending with local Qwen'
[[ $(yq -r '.auxiliary.background_review.provider // ""' "$hermes_config") == 'custom:qwen38-uncensored' ]] \
    || fail 'Background review must resolve the authenticated Headroom custom provider'

printf 'PASS: Hermes full-stack OpenCode Go routing contract\n'
