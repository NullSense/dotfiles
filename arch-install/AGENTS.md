# Agent Toolchain Architecture

This directory documents the host-side agent toolchain. Live dotfiles are
individual symlinks into `~/.dotfiles/home`; edit the live path normally.

## Current boundaries

- `claude`, `codex`, and `opencode` resolve directly to their vendor binaries.
  There are no PATH-shadowing shims, `infisical run` launchers, or outer bwrap
  wrappers.
- Agent Vault is the HTTP/HTTPS credential broker. Invoke it explicitly with
  `agent-vault vault run --vault <vault> -- <command>` or from a service drop-in.
- Infisical backs selected Agent Vault vaults. Infisical credentials belong to
  the Agent Vault service, not agent processes.
- Protocol-local values that an HTTP proxy cannot inject (for example a Home
  Assistant WebSocket auth frame or a local LiteLLM virtual key) use encrypted
  systemd credentials scoped to the consuming service.
- Destructive-command hooks, signed commits, and commit/push secret scanning
  remain independent controls; they do not depend on a filesystem sandbox.

## Authoritative files

| Concern | Source |
|---|---|
| Agent Vault service | `home/.config/systemd/user/agent-vault.service` |
| Hermes credential boundary | `home/.config/systemd/user/hermes-gateway.service.d/10-agent-vault.conf` |
| Hindsight API | `home/.config/systemd/user/hindsight-hermes.service` |
| Hindsight runtime config | `home/.config/hindsight/hermes.env` |
| Hindsight control-plane UI | `home/.config/systemd/user/hindsight-hermes-ui.service` |
| MCP gateway inventory | `home/.config/litellm/config-mcp.yaml` |
| MCP client endpoints | each client's native config under `home/` |
| Commit signing | `home/bin/git-sign-ssh`, `home/.config/systemd/user/git-sign-agent.service` |
| Claude safety hooks | `home/.claude/hooks/` and `home/.claude/settings.json` |

## Hermes runtime

Hermes owns and may regenerate its base `hermes-gateway.service`. Dotfiles
track only `hermes-gateway.service.d/10-agent-vault.conf`; the drop-in
survives vendor regeneration, loads encrypted credentials, orders Hermes after
its local dependencies, and keeps the vendor-supported direct `ExecStart`.

The `hermes-gateway` Agent Vault identity has instance role `no-access` and
only the `proxy` role in the `hermes` vault. Its token and direct-protocol
credentials are encrypted under `~/.config/credstore.encrypted/` and unsealed
by the user systemd manager at service start.

## Hindsight runtime

`hindsight-hermes.service` owns the self-hosted API on `127.0.0.1:9177` and
the embedded PostgreSQL instance `hindsight-embed-hermes`. It uses local CPU
embeddings and reranking and sends LLM requests to LiteLLM on port 4000. The
only live bank is `hermes`.

Hermes uses its native `local_external` provider for automatic retain/recall.
MCP clients reach the same bank through the `hindsight` entry in
`config-mcp.yaml`; that MCP intentionally exposes only retain, recall, and
reflect. Use the official `hindsight` CLI for bank, memory, operation, entity,
and mental-model administration.

The optional upstream `hindsight-self-hosted` skill is not installed. It is
not required for the native provider, MCP, CLI, API, or UI.

## Verification

```sh
command -v claude codex opencode hermes
systemctl --user is-active agent-vault.service hindsight-hermes.service \
  litellm-mcp.service hermes-gateway.service hindsight-hermes-ui.service
systemctl --user cat hermes-gateway.service
agent-vault vault run --vault hermes -- agent-vault vault discover --json
codex mcp list
hindsight bank list
hindsight bank stats hermes
ss -ltn 'sport = :4001'
git log --show-signature -1
```

No verification command should print credential values or full agent process
arguments.
