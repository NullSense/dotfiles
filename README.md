# NullSense dotfiles

Arch Linux, Hyprland, Wayland, local LLM infrastructure, and agent tooling.

This is a plain Git repository. Tracked home files live under `home/` using
their literal destination paths and are individually symlinked into `$HOME`.
There is no templating, encoded filename scheme, generated source tree, or
apply/re-add state.

## Install

```bash
git clone https://github.com/NullSense/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh --install
~/.dotfiles/scripts/bootstrap-omarchy.sh
systemctl --user daemon-reload
```

The installer only replaces an existing target when its content already
matches the tracked file. Conflicts are moved to
`~/.local/state/dotfiles-backups/<timestamp>/` before linking.

Verify the live link farm with:

```bash
~/.dotfiles/install.sh --check
```

Uninstalling removes only symlinks that point into this checkout:

```bash
~/.dotfiles/install.sh --uninstall
```

## Daily workflow

Edit the live file normally. It is the tracked file through a symlink:

```bash
$EDITOR ~/.zshrc
git -C ~/.dotfiles diff
git -C ~/.dotfiles add home/.zshrc
git -C ~/.dotfiles commit -m 'fix(shell): ...'
git -C ~/.dotfiles push
```

The repository is public. Never commit credentials. Runtime secrets belong in
Infisical, Agent Vault, systemd encrypted credentials, or ignored local state.
Pre-commit and pre-push hooks run Gitleaks and TruffleHog.

## Regression checks

`tests/` contains only recurring checks for tracked behavior. Run the complete
set through this documented interface instead of adding one-off runner scripts:

```bash
for test_file in ~/.dotfiles/tests/*.sh; do "$test_file"; done
```

## Layout

```text
home/                 literal files linked into $HOME
scripts/              explicit bootstrap and system-tuning scripts
arch-install/         workstation recovery/install tooling
install.sh            conservative per-file symlink installer
```

## Agent and secret architecture

- Agent binaries run directly; there is no custom bubblewrap wrapper layer.
- Agent Vault brokers supported HTTP credentials per process.
- The `hermes` Agent Vault is read-only Infisical-backed and force-syncable.
- LiteLLM on loopback port 4001 is the single MCP gateway for local clients.
- Hermes Gateway receives its Agent Vault token and non-proxyable local or
  WebSocket credentials through systemd encrypted credentials.
- Hindsight is self-hosted for Hermes. The API listens on loopback port 9177,
  uses the local LiteLLM gateway for inference, and has one canonical bank:
  `hermes`.

## Hindsight memory

Hindsight has four installed access paths with distinct responsibilities:

- Hermes's native `local_external` provider performs automatic retain and
  recall against the `hermes` bank in hybrid mode.
- LiteLLM MCP exposes `retain`, `recall`, and `reflect` to MCP clients through
  the loopback MCP gateway on port 4001.
- The official `hindsight` CLI in `~/.local/bin/` provides bank, memory,
  entity, operation, and mental-model administration.
- The control-plane UI is available at <http://127.0.0.1:19177> while
  `hindsight-hermes-ui.service` is active.

The API, MCP gateway, Hermes gateway, and UI are user services:

```bash
systemctl --user is-active hindsight-hermes.service litellm-mcp.service \
  hermes-gateway.service hindsight-hermes-ui.service
hindsight --version
hindsight bank list
hindsight bank stats hermes
hindsight mental-model list hermes
```

The MCP is intentionally the small agent-facing surface; use the CLI for
administration. Hindsight's optional upstream `hindsight-self-hosted` skill is
not installed because Hermes's native provider and MCP already own runtime
memory behavior. Installing that skill later would add agent usage guidance,
not another memory database.

Auto-consolidation and observations are enabled. Do not run routine manual
consolidation when there are no pending operations, and do not treat duplicate
entity labels as duplicate memories. Hindsight currently has no supported
entity-merge command.

See `arch-install/AGENTS.md` for the concise operational map.
