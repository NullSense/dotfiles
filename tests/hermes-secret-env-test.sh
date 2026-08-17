#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/home/.local/libexec/hermes-secret-env"
tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT

cat >"$tmpdir/systemd-creds" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *hermes-agent-vault-token*) printf 'vault-token' ;;
  *hermes-hass-token*) printf 'hass-token' ;;
  *hermes-litellm-key*) printf 'virtual-key' ;;
  *) exit 1 ;;
esac
EOF

cat >"$tmpdir/agent-vault" <<'EOF'
#!/usr/bin/env bash
[[ $1 == run && $2 == -- ]]
shift 2
exec "$@"
EOF

chmod +x "$tmpdir/systemd-creds" "$tmpdir/agent-vault"

output=$(
  HERMES_CREDENTIAL_STORE="$tmpdir/credentials" \
  HERMES_SECRET_SYSTEMD_CREDS_BIN="$tmpdir/systemd-creds" \
  HERMES_SECRET_AGENT_VAULT_BIN="$tmpdir/agent-vault" \
    "$helper"
)

grep -qx 'LITELLM_API_KEY=virtual-key' <<<"$output"
grep -qx 'HINDSIGHT_LLM_API_KEY=virtual-key' <<<"$output"
if grep -q '^LITELLM_MASTER_KEY=' <<<"$output"; then
  echo 'Hermes must not expose a client virtual key as LITELLM_MASTER_KEY' >&2
  exit 1
fi

echo 'hermes-secret-env test: PASS'
