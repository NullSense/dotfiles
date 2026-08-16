# Secret boundaries

This repository is public. It contains configuration and credential *names*,
never credential values.

Use these stores:

1. Infisical for durable application and service secrets.
2. Agent Vault for per-process HTTP/HTTPS credential injection.
3. User-scoped systemd encrypted credentials for daemon bootstrap values and
   protocol-local secrets that an HTTP proxy cannot inject.
4. The desktop keyring for interactive CLI OAuth sessions.

The `hermes` Agent Vault is read-only Infisical-backed. Rotate values in
Infisical, run `agent-vault vault credential-store sync hermes`, then restart
consumers that load encrypted credentials at process start.

Never put secrets in:

- tracked files under `home/`
- systemd `Environment=` lines
- shell command arguments
- `.env` backups or agent transcripts
- Git commits, even temporarily

Gitleaks runs before commits and TruffleHog before pushes. Those are backstops,
not permission to stage plaintext secrets.
