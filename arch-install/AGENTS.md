# Agent Toolchain Architecture

This directory documents the host-side agent toolchain. Chezmoi source is
authoritative; edit source files and apply only the target you changed.

## Current boundaries

- `claude`, `codex`, and `opencode` resolve directly to their vendor binaries.
  There are no PATH-shadowing shims, `infisical run` launchers, or outer bwrap
  wrappers.
- Agent Vault is the HTTP/HTTPS credential broker. Invoke it explicitly with
  `agent-vault run --vault <vault> -- <command>` or from a service drop-in.
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
| Agent Vault service | `dot_config/systemd/user/agent-vault.service` |
| Hermes credential boundary | `dot_config/systemd/user/hermes-gateway.service.d/10-agent-vault.conf` |
| Agent Vault operations | `AGENT-VAULT.md` |
| MCP inventory | `.chezmoidata/mcp.yaml` |
| MCP renderer | `dot_local/bin/executable_mcp-sync` |
| Commit signing | `bin/executable_git-sign-ssh`, `dot_config/systemd/user/git-sign-agent.service` |
| Claude safety hooks | `dot_claude/hooks/` and `dot_claude/settings.json` |

## Hermes runtime

Hermes owns and may regenerate its base `hermes-gateway.service`. Chezmoi
manages only `hermes-gateway.service.d/10-agent-vault.conf`; the drop-in
survives vendor regeneration and replaces `ExecStart` with the supported
`agent-vault run` chain.

The `hermes-gateway` Agent Vault identity has instance role `no-access` and
only the `proxy` role in the `hermes` vault. Its token and direct-protocol
credentials are encrypted under `~/.config/credstore.encrypted/` and unsealed
by the user systemd manager at service start.

## Verification

```sh
command -v claude codex opencode hermes
systemctl --user is-active agent-vault.service hermes-gateway.service
systemctl --user cat hermes-gateway.service
agent-vault run --vault hermes -- agent-vault vault discover --json
codex mcp list
git log --show-signature -1
```

No verification command should print credential values or full agent process
arguments.
