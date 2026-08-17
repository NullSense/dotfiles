#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
units="$repo_root/home/.config/systemd/user"
compose=${LLM_STACK_COMPOSE:-$HOME/Programming/llm-stack/stack/observability/docker-compose.yml}

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
