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
| MCP gateway inventory | `home/.config/litellm/config-mcp.yaml` |
| MCP client endpoints | each client's native config under `home/` |
| Commit signing | `home/bin/git-sign-ssh`, `home/.config/systemd/user/git-sign-agent.service` |
| Claude safety hooks | `home/.claude/hooks/` and `home/.claude/settings.json` |

## Hermes runtime

Hermes owns and may regenerate its base `hermes-gateway.service`. Dotfiles
track only `hermes-gateway.service.d/10-agent-vault.conf`; the drop-in
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
agent-vault vault run --vault hermes -- agent-vault vault discover --json
codex mcp list
ss -ltn 'sport = :4001'
git log --show-signature -1
```

No verification command should print credential values or full agent process
arguments.
