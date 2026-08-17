#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/home/.local/libexec/hermes-secret-env"
models="$repo_root/home/.config/litellm/models.yaml"
mcp_config="$repo_root/home/.config/litellm/config-mcp.yaml"
opencode_config="$repo_root/home/.config/opencode/opencode.jsonc"
hindsight_env="$repo_root/home/.config/hindsight/hermes.env"
hermes_config=${HERMES_CONFIG:-$HOME/.hermes/config.yaml}
hermes_soul=${HERMES_SOUL:-$HOME/.hermes/SOUL.md}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Eq '^[[:space:]]+OPENCODE_GO_API_KEY \\$' "$helper" \
    || fail 'Hermes secret allowlist omits OPENCODE_GO_API_KEY'
grep -Fq 'OPENCODE_GO_API_KEY:-agent-vault-managed' "$helper" \
    || fail 'Hermes does not use the non-secret Agent Vault marker'

[[ $(yq -r '[.model_list[] | select(.model_name == "opencode-go-chat/*")] | length' "$models") == 1 ]] \
    || fail 'LiteLLM must define exactly one OpenCode Go Chat Completions route'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go-chat/*") | .litellm_params.model' "$models") == 'openai/*' ]] \
    || fail 'LiteLLM must preserve the OpenCode Go Chat Completions suffix'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go-chat/*") | .litellm_params.api_base' "$models") == 'https://opencode.ai/zen/go/v1' ]] \
    || fail 'LiteLLM OpenCode Go Chat Completions URL is incorrect'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go-chat/*") | .litellm_params.api_key' "$models") == 'os.environ/OPENCODE_GO_API_KEY' ]] \
    || fail 'LiteLLM must resolve the OpenCode Go key from its process environment'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go-messages/*") | .litellm_params.model' "$models") == 'anthropic/*' ]] \
    || fail 'LiteLLM OpenCode Go Messages route is incorrect'
[[ $(yq -r '.model_list[] | select(.model_name == "opencode-go-responses/*") | .litellm_params.model' "$models") == 'openai/responses/*' ]] \
    || fail 'LiteLLM OpenCode Go Responses route must use the Responses bridge'

[[ $(yq -r '.mcp_servers.hindsight // "absent"' "$mcp_config") == absent ]] \
    || fail 'Personal Hindsight must not be exposed through the shared LiteLLM MCP gateway'
[[ $(yq -r '.permission."litellm_hindsight_*" // ""' "$opencode_config") == deny ]] \
    || fail 'OpenCode must deny Hindsight tools as a defense-in-depth boundary'

[[ $(yq -r '.delegation.model // ""' "$hermes_config") == 'qwen3.8-27b-nvfp4-long:think' ]] \
    || fail 'Private Hermes delegation must stay on local Qwen'
[[ $(yq -r '.delegation.provider // ""' "$hermes_config") == 'custom:qwen38-nvfp4' ]] \
    || fail 'Private Hermes delegation must use the local Qwen provider'
[[ $(yq -r '.delegation.base_url // ""' "$hermes_config") == 'http://127.0.0.1:8787/v1' ]] \
    || fail 'Private Hermes delegation must route through Headroom'
[[ $(yq -r '.delegation.api_mode // ""' "$hermes_config") == chat_completions ]] \
    || fail 'Private Hermes delegation must use chat completions'
[[ $(yq -r '.delegation.max_concurrent_children // 0' "$hermes_config") == 1 ]] \
    || fail 'Private local delegation must leave the 50K Hindsight reserve intact'
[[ $(yq -r '.delegation.inherit_mcp_toolsets' "$hermes_config") == false ]] \
    || fail 'Delegated children must not inherit the parent MCP inventory'
[[ $(yq -r '.auxiliary.background_review.model // ""' "$hermes_config") == 'qwen3.8-27b-nvfp4-long:fast' ]] \
    || fail 'Background review must stay on non-thinking local Qwen'
[[ $(yq -r '.auxiliary.compression.model // ""' "$hermes_config") == 'qwen3.8-27b-nvfp4-long:fast' ]] \
    || fail 'Hermes context compression must use the stable fast Qwen route'
[[ $(yq -r '.auxiliary.compression.base_url // ""' "$hermes_config") == 'http://127.0.0.1:8787/v1' ]] \
    || fail 'Hermes context compression must traverse Headroom'
[[ $(yq -r '.compression.abort_on_summary_failure' "$hermes_config") == true ]] \
    || fail 'Hermes must preserve context when a compression summary fails'
grep -Fqx 'HINDSIGHT_API_REFLECT_MAX_CONTEXT_TOKENS=50000' "$hindsight_env" \
    || fail 'Hindsight reflection must fit inside the 50K scheduling reserve'

grep -Fq 'opencode-go/deepseek-v4-flash' "$hermes_soul" \
    || fail 'Hermes delegation policy omits the easy OpenCode route'
grep -Fq 'opencode-go/glm-5.3' "$hermes_soul" \
    || fail 'Hermes delegation policy omits the complex OpenCode route'
grep -Fq 'they do not get Hindsight' "$hermes_soul" \
    || fail 'Hermes delegation policy omits the Hindsight privacy boundary'

printf 'PASS: Hermes private-local and native-remote delegation contract\n'
