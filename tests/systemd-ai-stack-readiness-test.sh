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
hermes_config=${HERMES_CONFIG:-$HOME/.hermes/config.yaml}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

sift_chat_capacity_contract_is_valid() {
    local config=$1

    yq -e '
        (.models."nanbeige-sift".cmd // "") as $command
        | (.models."nanbeige-sift".metadata.sift_chat_capacity // {}) as $capacity
        | ([ $command | scan("--kv-cache-memory-bytes[[:space:]]+[^[:space:]]+") ]
            == ["--kv-cache-memory-bytes 7G"])
          and (.models."nanbeige-sift".aliases
            == ["sift-nanbeige", "sift-agent", "sift-decompose"])
          and (.matrix.vars.A == "nanbeige-sift")
          and (.matrix.vars.n == "nemotron-embed-1b")
          and (.matrix.vars.x == "tei-sparse")
          and (.matrix.vars.m == "nemotron-rerank-1b")
          and (.matrix.sets."sift-chat" == "A & n & x & m")
          and ($capacity.minimum_headroom_mib == 4096)
          and ($capacity.measured_headroom_mib >= $capacity.minimum_headroom_mib)
          and ($capacity.measured_at == "2026-09-01")
    ' "$config" >/dev/null 2>&1
}

sift_chat_capacity_contract_is_valid "$llama_swap_config" \
    || fail 'sift-chat capacity contract is not the measured 7 GiB/full-quartet/4 GiB-headroom shape'

sift_chat_capacity_negative_controls_are_valid() {
    local fixture_dir fixture
    fixture_dir=$(mktemp -d)
    fixture="$fixture_dir/llama-swap.yaml"

    yq -y '
        .models."nanbeige-sift".cmd
            |= sub("--kv-cache-memory-bytes 7G"; "--kv-cache-memory-bytes 8G")
    ' "$llama_swap_config" >"$fixture" \
        || { rm -r -- "$fixture_dir"; return 1; }
    if sift_chat_capacity_contract_is_valid "$fixture"; then
        rm -r -- "$fixture_dir"
        return 1
    fi

    yq -y '.matrix.sets."sift-chat" = "A & n & m"' \
        "$llama_swap_config" >"$fixture" \
        || { rm -r -- "$fixture_dir"; return 1; }
    if sift_chat_capacity_contract_is_valid "$fixture"; then
        rm -r -- "$fixture_dir"
        return 1
    fi

    yq -y '
        .models."nanbeige-sift".metadata.sift_chat_capacity.measured_headroom_mib = 4095
    ' "$llama_swap_config" >"$fixture" \
        || { rm -r -- "$fixture_dir"; return 1; }
    if sift_chat_capacity_contract_is_valid "$fixture"; then
        rm -r -- "$fixture_dir"
        return 1
    fi

    rm -r -- "$fixture_dir"
}

sift_chat_capacity_negative_controls_are_valid \
    || fail 'sift-chat capacity negative controls did not reject an invalid fixture'

sift_chat_preflight_synthetic_controls_are_valid() {
    local fixture_dir fake_bin good_running missing_running output result=0
    fixture_dir=$(mktemp -d)
    fake_bin="$fixture_dir/bin"
    mkdir "$fake_bin"

    cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *'http://127.0.0.1:9292/running'* ]]
[[ "$*" != *'--data'* && "$*" != *'-X '* && "$*" != *'--request'* ]]
printf '%s\n' "${SIFT_CHAT_PREFLIGHT_RUNNING_JSON:?}"
EOF
    cat >"$fake_bin/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '--query-gpu=memory.free --format=csv,noheader,nounits' ]]
printf '%s\n' "${SIFT_CHAT_PREFLIGHT_FREE_MIB:?}"
EOF
    chmod +x "$fake_bin/curl" "$fake_bin/nvidia-smi"

    good_running='{"running":["nanbeige-sift","nemotron-embed-1b","tei-sparse","nemotron-rerank-1b"]}'
    missing_running='{"running":["nemotron-embed-1b","tei-sparse","nemotron-rerank-1b"]}'

    if ! output=$(PATH="$fake_bin:$PATH" \
        SIFT_CHAT_PREFLIGHT_RUNNING_JSON="$good_running" \
        SIFT_CHAT_PREFLIGHT_FREE_MIB=4438 \
        LSWAP_CFG="$llama_swap_config" \
        "$stack" preflight sift-chat 2>&1); then
        result=1
    elif [[ "$output" != *'sift-chat preflight passed'* ]]; then
        result=1
    fi

    if PATH="$fake_bin:$PATH" \
        SIFT_CHAT_PREFLIGHT_RUNNING_JSON="$missing_running" \
        SIFT_CHAT_PREFLIGHT_FREE_MIB=4438 \
        LSWAP_CFG="$llama_swap_config" \
        "$stack" preflight sift-chat >/dev/null 2>&1; then
        result=1
    fi

    if PATH="$fake_bin:$PATH" \
        SIFT_CHAT_PREFLIGHT_RUNNING_JSON="$good_running" \
        SIFT_CHAT_PREFLIGHT_FREE_MIB=4095 \
        LSWAP_CFG="$llama_swap_config" \
        "$stack" preflight sift-chat >/dev/null 2>&1; then
        result=1
    fi

    rm -r -- "$fixture_dir"
    return "$result"
}

sift_chat_preflight_synthetic_controls_are_valid \
    || fail 'stack preflight sift-chat synthetic readiness controls are invalid'

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

[[ $(yq -r '.display.busy_input_mode // ""' "$hermes_config") == queue ]] \
    || fail 'Hermes must queue follow-up input instead of interrupting long-running turns'

printf 'PASS: systemd AI-stack readiness contract\n'
