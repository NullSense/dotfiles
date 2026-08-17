#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
units="$repo_root/home/.config/systemd/user"
compose=${LLM_STACK_COMPOSE:-$HOME/Programming/llm-stack/stack/observability/docker-compose.yml}
litellm_launcher="$repo_root/home/bin/llm-servers/litellm-gateway"
stack="$repo_root/home/bin/stack"
litellm_config="$repo_root/home/.config/litellm/config.yaml"
litellm_mcp_config="$repo_root/home/.config/litellm/config-mcp.yaml"
litellm_models="$repo_root/home/.config/litellm/models.yaml"
llama_swap_config="$repo_root/home/.config/llama-swap/config.yaml"
llama_swap_unit="$units/llama-swap.service"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Fq 'pg_isready' "$compose" || fail 'litellm-db has no PostgreSQL healthcheck'
grep -Fq -- '--wait --wait-timeout 90 litellm-db' "$units/litellm-db.service" \
    || fail 'litellm-db.service does not use Compose readiness waiting'
grep -Fq 'Requires=litellm-db.service' "$units/litellm.service" \
    || fail 'LiteLLM does not require its database readiness unit'
grep -Fq 'After=litellm-db.service' "$units/litellm.service" \
    || fail 'LiteLLM is not ordered after its database readiness unit'
# shellcheck disable=SC2016
grep -Fq 'export PATH="$HOME/.local/share/uv/tools/litellm/bin:$PATH"' "$litellm_launcher" \
    || fail 'LiteLLM launcher does not expose its Prisma executable to subprocesses'
grep -Fq 'prisma_client._Prisma__engine = engine' "$stack" \
    || fail 'stack db-init does not detect the broken LiteLLM Prisma engine setter'
grep -Fq 'prisma_client._engine = engine' "$stack" \
    || fail 'stack db-init does not install the compatible Prisma engine setter'
grep -Fq 'patch_litellm_prisma_client' "$stack" \
    || fail 'stack db-init does not own the LiteLLM Prisma compatibility repair'
grep -Fq 'STACK_DB_INIT_INFISICAL' "$stack" \
    || fail 'stack db-init does not acquire its database credential through Infisical'

for config in "$litellm_config" "$litellm_mcp_config"; do
    grep -Eq '^[[:space:]]*store_model_in_db:[[:space:]]*false([[:space:]]|$)' "$config" \
        || fail "$(basename "$config") does not keep YAML authoritative"
done

if grep -Eq 'stack pro|vllm-diffusiongemma|summarize-pro' \
    "$stack" "$litellm_models" "$llama_swap_config"; then
    fail 'retired premium summarizer machinery returned'
fi

grep -Fq -- '--watch-config' "$llama_swap_unit" \
    && fail 'llama-swap unsafe automatic config reload is enabled'
grep -Fq 'TimeoutStopSec=60' "$llama_swap_unit" \
    || fail 'llama-swap stop timeout does not cover its graceful drain budget'
grep -Fq '/api/events' "$stack" \
    || fail 'stack has no authoritative llama-swap in-flight check'
grep -Fq 'wait_llama_swap_idle' "$stack" \
    || fail 'stack does not drain llama-swap before a controlled restart'
grep -Fq 'role:diagnostic' "$stack" \
    || fail 'stack canary lacks a LiteLLM diagnostic role tag'
grep -Fq 'dash|pro|obs' "$stack" \
    && fail 'retired stack pro command remains advertised'

if grep -Eq 'After=.*(docker|network-online)\.service|After=.*network-online\.target' \
    "$units/litellm.service" "$units/litellm-mcp.service" "$units/hindsight-hermes.service"; then
    fail 'user unit contains an ineffective system-manager ordering dependency'
fi

for spec in \
    'litellm.service:4000/health/liveliness' \
    'litellm-mcp.service:4001/health/liveliness' \
    'hindsight-hermes.service:9177/health/ready' \
    'headroom-hermes.service:8787/readyz' \
    'agent-vault.service:14321/health'
do
    unit=${spec%%:*}
    endpoint=${spec#*:}
    grep -Fq "ExecStartPost=" "$units/$unit" || fail "$unit has no readiness gate"
    grep -Fq "$endpoint" "$units/$unit" || fail "$unit checks the wrong readiness endpoint"
done

gateway="$units/hermes-gateway.service.d/10-agent-vault.conf"
for dependency in agent-vault.service hindsight-hermes.service headroom-hermes.service litellm-mcp.service; do
    grep -Eq "^After=.*${dependency}([[:space:]]|$)" "$gateway" \
        || fail "Hermes is not ordered after $dependency"
done

printf 'PASS: systemd AI-stack readiness contract\n'
