#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fake_home=$test_root/home
hermes_home=$fake_home/.hermes
runtime_root=$hermes_home/hermes-agent
desktop_file=$fake_home/.local/share/applications/hermes.desktop
desktop_unit=$fake_home/.config/systemd/user/hermes-desktop.service
gateway_dropin=$fake_home/.config/systemd/user/hermes-gateway.service.d/10-agent-vault.conf
secret_helper=$fake_home/.local/libexec/hermes-secret-env
credential_store=$fake_home/.config/credstore.encrypted

mkdir -p \
    "$hermes_home/hindsight" \
    "$runtime_root/venv/bin" \
    "$(dirname "$desktop_file")" \
    "$(dirname "$desktop_unit")" \
    "$(dirname "$gateway_dropin")" \
    "$(dirname "$secret_helper")" \
    "$credential_store"

ln -s /home/nullsense/.hermes/hermes-agent/venv/bin/python "$runtime_root/venv/bin/python"
ln -s /home/nullsense/.hermes/hermes-agent/venv/bin/hermes "$runtime_root/venv/bin/hermes"

cat >"$hermes_home/config.yaml" <<YAML
model:
  default: qwen3.8-27b-uncensored:fast
  provider: custom:qwen38-uncensored
  base_url: http://127.0.0.1:4000/v1
  key_env: LITELLM_MASTER_KEY
memory:
  provider: hindsight
secrets:
  command:
    enabled: true
    command: $secret_helper
YAML

cat >"$hermes_home/hindsight/config.json" <<'JSON'
{
  "mode": "local_embedded",
  "llm_provider": "openai_compatible",
  "llm_base_url": "http://127.0.0.1:4000/v1",
  "llm_model": "qwen3.8-27b-uncensored:fast"
}
JSON

cat >"$desktop_file" <<'DESKTOP'
[Desktop Entry]
Exec=/usr/bin/systemctl --user start hermes-desktop.service
DESKTOP

cat >"$desktop_unit" <<UNIT
[Service]
Environment="HERMES_HOME=$hermes_home"
Environment="HERMES_DESKTOP_HERMES_ROOT=$runtime_root"
Environment="HERMES_DESKTOP_HERMES=$runtime_root/venv/bin/hermes"
ExecStart=$runtime_root/venv/bin/hermes desktop --hermes-root $runtime_root
UNIT

cat >"$gateway_dropin" <<UNIT
[Service]
Environment="HERMES_HOME=$hermes_home"
ExecStart=$runtime_root/venv/bin/python -m hermes_cli.main gateway run
UNIT

touch "$secret_helper"
chmod 700 "$secret_helper"
for credential in hermes-agent-vault-token hermes-hass-token hermes-litellm-key; do
    printf 'encrypted-test-fixture\n' >"$credential_store/$credential.cred"
    chmod 600 "$credential_store/$credential.cred"
done

parity_env=(
    HOME="$fake_home"
    HERMES_PARITY_HOME="$hermes_home"
    HERMES_PARITY_RUNTIME_ROOT="$runtime_root"
    HERMES_PARITY_DESKTOP_FILE="$desktop_file"
    HERMES_PARITY_DESKTOP_UNIT="$desktop_unit"
    HERMES_PARITY_GATEWAY_DROPIN="$gateway_dropin"
    HERMES_PARITY_SECRET_HELPER="$secret_helper"
    HERMES_PARITY_CREDENTIAL_STORE="$credential_store"
)

env "${parity_env[@]}" "$repo/home/.local/bin/hermes-parity" check >"$test_root/parity.out"
grep -q 'Hermes parity: OK' "$test_root/parity.out"

sed -i 's/qwen3.8-27b-uncensored:fast/qwen3.8-drifted/' "$hermes_home/hindsight/config.json"
if env "${parity_env[@]}" "$repo/home/.local/bin/hermes-parity" check >"$test_root/drift.out" 2>&1; then
    echo 'expected parity check to reject a drifted Hindsight model' >&2
    exit 1
fi
grep -q 'Hindsight LLM model differs from Hermes' "$test_root/drift.out"

credentials_dir=$test_root/credentials
mkdir -p "$credentials_dir"
printf 'vault-token\n' >"$credentials_dir/hermes-agent-vault-token"
printf 'hass-token\n' >"$credentials_dir/hermes-hass-token"
printf 'litellm-key\n' >"$credentials_dir/hermes-litellm-key"

fake_agent_vault=$test_root/agent-vault
cat >"$fake_agent_vault" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
shift
export HTTP_PROXY=http://127.0.0.1:14322
export HTTPS_PROXY=http://127.0.0.1:14322
export NO_PROXY=127.0.0.1,localhost
exec "$@"
SH
chmod 700 "$fake_agent_vault"

env -i \
    HOME="$fake_home" \
    PATH=/usr/bin:/bin \
    CREDENTIALS_DIRECTORY="$credentials_dir" \
    HERMES_SECRET_AGENT_VAULT_BIN="$fake_agent_vault" \
    "$repo/home/.local/libexec/hermes-secret-env" >"$test_root/secrets.out"

grep -q '^AGENT_VAULT_TOKEN=vault-token$' "$test_root/secrets.out"
grep -q '^LITELLM_MASTER_KEY=litellm-key$' "$test_root/secrets.out"
grep -q '^HINDSIGHT_LLM_API_KEY=litellm-key$' "$test_root/secrets.out"
grep -q '^HASS_TOKEN=hass-token$' "$test_root/secrets.out"
grep -q '^HTTP_PROXY=http://127.0.0.1:14322$' "$test_root/secrets.out"

echo 'Hermes launch and parity contracts pass'
