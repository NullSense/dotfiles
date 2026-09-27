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

See [Secret boundaries](SECRETS.md) for credential storage and leak response,
and the [recovery runbook](arch-install/RUNBOOK.md) for restoring services,
commit signing, and GitHub authentication.

## Regression checks

`tests/` contains only recurring checks for tracked behavior. Run the complete
set through this documented interface instead of adding one-off runner scripts:

```bash
for test_file in ~/.dotfiles/tests/*.sh; do "$test_file"; done
python3 ~/.dotfiles/tests/voice-tools-test.py
```

`audio-test`, `voice-bench`, and `voice-tui` share recording and WAV analysis
through `home/.local/lib/voice-tools.sh`. Their regression test uses simulated
audio devices and temporary recordings; it does not touch the live audio stack.

## Gameplay recording

`~/bin/screenrecord` owns desktop and gameplay capture. Gameplay capture uses
GPU Screen Recorder on the AORUS (`DP-1`): 3840×2160 at 60 FPS, AV1 HDR,
GPU encoding only, 60 Mb/s, and desktop/game audio (no microphone).
HDR must already be enabled on that display.

- **Super+Alt+F9** starts/stops a full recording in `~/Videos/Gameplay/`.
- **Super+Alt+F10** starts/stops a 120-second replay buffer in RAM.
- **Super+Alt+F11** saves the buffered replay in `~/Videos/Gameplay/Replays/`.

Replay uses approximately 900 MB plus overhead at the configured bitrate.
Save a replay before stopping if you want the buffered footage. Captures are
Matroska files; the gameplay path does not trim, normalize or re-encode them.
These modes are opt-in, mutually exclusive, and do not start at login.
The original desktop recording shortcuts and capture menu remain available.

`screenrecord-game@record.service` and `screenrecord-game@replay.service` own
the encoder lifetime. Inspect failures with `journalctl --user -u
screenrecord-game@replay.service` (or `@record.service`). Changes are covered by
`tests/screenrecord-game-test.sh`, included in the regression interface above.

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
- Both LiteLLM services use the existing dedicated LiteLLM Infisical machine
  identity, loaded from user-scoped encrypted credentials at
  `~/.config/credstore.encrypted/litellm-infisical-client-{id,secret}.cred`.
  They obtain a fresh access token at each start and never depend on `infisical login`.
  The identity must retain read access to the Personal project's `dev:/litellm`.
  When replacing a credential, use `systemd-creds encrypt --user` with the embedded
  names `infisical-client-id` and `infisical-client-secret`, then restart both units.
  Keep these encrypted files outside this repository. The pinned install command
  lives in `~/bin/llm-servers/litellm-gateway`; run `stack db-init` after reinstalling.
  `tests/litellm-boot-auth-test.sh` covers authentication and early startup failure;
  the shared `wait-ready` helper is invoked by both units' `ExecStartPost`.
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
