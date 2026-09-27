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

## If a credential leaks

1. Revoke or rotate the exposed credential at its provider immediately.
2. Store the replacement in the owning secret store above, refresh affected
   Agent Vault vaults, and restart consumers that load credentials at startup.
3. Remove the exposed value from working files and review the affected Git
   history, logs, artifacts, and shared copies. Removing the latest file does
   not remove earlier copies or revoke the credential.
4. Coordinate any published-history rewrite with repository collaborators;
   review its scope before rewriting or force-pushing.
5. Check the provider's access and audit records for unexpected use.
