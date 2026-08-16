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
- Hindsight uses the local LiteLLM gateway and the shared `hermes` bank.

See `arch-install/AGENTS.md` for the concise operational map.
