#!/usr/bin/env bash
# Recurring launcher contract; included by README.md's tests/*.sh runner.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/credentials"
printf '%s' test-machine-id > "$fixture/credentials/infisical-client-id"
printf '%s' test-machine-secret > "$fixture/credentials/infisical-client-secret"
cat > "$fixture/bin/infisical" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${CHECK_DB_INIT:-0} == 1 ]]; then
    [[ "$*" == *'--domain https://eu.infisical.com --projectId 723a9325-6559-4de6-8e86-c318c2e6b9fd'* ]]
    [[ "$*" == *'--env dev --path /litellm'* && "$*" == *'db-init'* ]]
    echo 'PASS: db-init does not select credentials from its working directory'
    exit 0
fi
case "$1" in
  login)
    [[ "$*" == *'--method=universal-auth'* && "$*" == *'--plain'* && "$*" == *'--silent'* ]]
    [[ "$*" != *test-machine* ]]
    [[ "${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}" == test-machine-id ]]
    [[ "${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}" == test-machine-secret ]]
    [[ "${INFISICAL_DOMAIN:-}" == https://eu.infisical.com ]]
    [[ -z "${INFISICAL_TOKEN:-}" ]]
    [[ "${FAIL_MACHINE_LOGIN:-0}" == 0 ]] || exit 42
    printf '%s' test-fresh-token
    ;;
  run)
    [[ "${INFISICAL_TOKEN:-}" == test-fresh-token ]] || { echo 'FAIL: launcher used interactive/stale authentication' >&2; exit 1; }
    [[ -z "${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}" && -z "${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}" ]]
    [[ "$*" == *'--projectId '* && "$*" == *'--env dev --path /litellm'* ]]
    while [[ "$1" != -- ]]; do shift; done
    shift
    [[ "$1" == env && "$2" == -u && "$3" == INFISICAL_TOKEN ]]
    echo 'PASS: fresh machine token, explicit project, no interactive login or credential argv'
    ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$fixture/bin/infisical"
export PATH="$fixture/bin:$PATH" CREDENTIALS_DIRECTORY="$fixture/credentials"
export LITELLM_OTEL_ENABLED=0 INFISICAL_TOKEN=expired-session
unset STACK_NO_INFISICAL
launcher="$repo_root/home/bin/llm-servers/litellm-gateway"
"$launcher"
if FAIL_MACHINE_LOGIN=1 "$launcher" >"$fixture/failure" 2>&1; then
    echo 'FAIL: machine-login failure fell through to an interactive login' >&2
    exit 1
fi
rm "$fixture/credentials/infisical-client-secret"
if "$launcher" >"$fixture/failure" 2>&1; then
    echo 'FAIL: missing machine credential fell through to interactive login' >&2
    exit 1
fi
printf 'PASS: missing/failed machine credentials fail closed\n'

# Readiness must stop immediately when the main process exits, not retry for minutes.
ready="$repo_root/home/bin/llm-servers/wait-ready"
[[ -x "$ready" ]] || { echo 'FAIL: no process-aware readiness gate' >&2; exit 1; }
sleep 0.01 &
dead_pid=$!
wait "$dead_pid"
if MAINPID="$dead_pid" timeout 3 "$ready" http://127.0.0.1:1/health/liveliness 180 >"$fixture/readiness" 2>&1; then
    echo 'FAIL: readiness accepted a dead main process' >&2
    exit 1
else
    result=$?
    [[ "$result" == 1 ]] || { echo "FAIL: readiness did not detect process exit promptly ($result)" >&2; exit 1; }
fi
for unit in litellm litellm-mcp; do
    file="$repo_root/home/.config/systemd/user/$unit.service"
    for credential in infisical-client-id infisical-client-secret; do
        grep -Fq "LoadCredentialEncrypted=$credential:%h/.config/credstore.encrypted/litellm-$credential.cred" "$file"
    done
    grep -Eq '^ExecStartPost=.*/wait-ready ' "$file"
    grep -Eq '^TimeoutStartSec=[0-9]+' "$file"
done
printf 'PASS: daemon credentials and process-aware readiness\n'

(cd "$fixture" && env -u DATABASE_URL -u STACK_DB_INIT_INFISICAL CHECK_DB_INIT=1 "$repo_root/home/bin/stack" db-init)
