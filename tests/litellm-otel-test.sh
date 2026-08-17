#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/litellm" <<'EOF'
#!/usr/bin/env bash
printf 'v2=%s disabled=%s\n' "${LITELLM_OTEL_V2:-}" "${OTEL_SDK_DISABLED:-}"
EOF
chmod +x "$fixture/litellm"

output=$(PATH="$fixture:/usr/bin" STACK_NO_INFISICAL=1 \
  LITELLM_OTEL_ENABLED=0 LITELLM_MASTER_KEY=test OPENROUTER_API_KEY=test \
  "$repo/home/bin/llm-servers/litellm-gateway")
[[ $output == 'v2=false disabled=true' ]]

echo 'litellm OTEL disabled-path test passed'
