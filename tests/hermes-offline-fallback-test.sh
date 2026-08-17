#!/usr/bin/env bash

set -euo pipefail

HERMES_HOME=${HERMES_HOME:-$HOME/.hermes}
HERMES_PYTHON=${HERMES_PYTHON:-$HERMES_HOME/hermes-agent/venv/bin/python}
HERMES_BIN=${HERMES_BIN:-$HERMES_HOME/hermes-agent/venv/bin/hermes}
CONFIG_PATH=$HERMES_HOME/config.yaml

"$HERMES_PYTHON" - "$CONFIG_PATH" <<'PY'
import sys
from pathlib import Path

import yaml

config = yaml.safe_load(Path(sys.argv[1]).read_text()) or {}
fallbacks = config.get("fallback_providers") or []
expected = {
    "provider": "custom",
    "model": "qwen3.8-27b-uncensored:fast",
    "base_url": "http://127.0.0.1:9292/v1",
    "api_mode": "chat_completions",
}

if expected not in fallbacks:
    raise SystemExit("Hermes local llama-swap fallback is missing or drifted")
if (config.get("agent") or {}).get("api_max_retries") != 0:
    raise SystemExit("Hermes api_max_retries must be 0 for immediate fallback")
PY

if [[ ${1:-} != --outage ]]; then
    echo "PASS: Hermes offline fallback configuration"
    exit 0
fi

systemctl --user stop litellm.service
trap 'systemctl --user start litellm.service' EXIT

if curl -fsS --max-time 2 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1; then
    echo "FAIL: LiteLLM remained reachable during outage test" >&2
    exit 1
fi

output=$(timeout 120 "$HERMES_BIN" --ignore-rules -z 'Reply exactly HERMES_OFFLINE_OK')
grep -Fxq 'HERMES_OFFLINE_OK' <<<"$output" \
    || { printf '%s\n' "$output" >&2; echo "FAIL: Hermes did not use the offline fallback" >&2; exit 1; }

systemctl --user start litellm.service
trap - EXIT
for _ in {1..30}; do
    if curl -fsS --max-time 2 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1; then
        echo "PASS: Hermes works while LiteLLM is unavailable and LiteLLM recovered"
        exit 0
    fi
    sleep 1
done

echo "FAIL: LiteLLM did not recover after the outage test" >&2
exit 1
