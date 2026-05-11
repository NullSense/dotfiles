# dotfiles

Arch Linux + Hyprland + Wayland. **One repo, one source of truth.** Managed by [chezmoi](https://www.chezmoi.io/).

```
github.com/NullSense/dotfiles                   ← THIS IS THE ONLY REPO
├── arch-install/         ─────────── install-from-zero pipeline (live USB → working desktop)
│   ├── RUNBOOK.md                              top-to-bottom guide; read first
│   ├── RECOVER-AGENT-STATE.md                  Hindsight + Claude/Codex/OpenCode restore
│   ├── user_configuration.json                 archinstall 4.x config (inline disk_config + ~130 packages + custom_commands)
│   ├── user_credentials.json                   passwords (CHANGE_ME placeholder; gitignored when filled)
│   ├── preflight-on-usb.sh                     live-USB hardware probe
│   ├── validate.sh                             config sanity check
│   ├── post-install.sh                         after first boot: paru, mise, AUR, swapfile, services
│   ├── hardware-optimize.sh                    UKI cmdline, AMD GPU udev, gamemode
│   ├── setup-secure-boot.sh                    sbctl flow
│   ├── setup-inference.sh                      llama.cpp + ComfyUI Docker
│   ├── verify-system.sh                        post-install health check
│   └── fix-boot-after-windows.sh               recovery
│
├── dot_claude/        chezmoi → ~/.claude/             Claude Code: CLAUDE.md, mcp.json, statusline, skills, commands, memory, hooks (deny-secrets, destructive-guard)
├── dot_codex/         chezmoi → ~/.codex/              Codex CLI: config.toml, rules
├── dot_config/        chezmoi → ~/.config/             hypr/, waybar/, ghostty/, mako/, opencode/, systemd/user/, agent-isolated/, etc.
├── dot_local/         chezmoi → ~/.local/              user-installed binaries (hypr-waybar-bridge, sudo-pill-daemon, etc.)
├── dot_lmstudio/      chezmoi → ~/.lmstudio/           LM Studio config presets (voice-rewrite, coding, general)
├── dot_zshrc          chezmoi → ~/.zshrc
├── dot_zshenv         chezmoi → ~/.zshenv              minimal: SSH_AUTH_SOCK, PATH, OMARCHY_PATH
├── dot_bashrc         chezmoi → ~/.bashrc
├── dot_gitconfig      chezmoi → ~/.gitconfig           SSH-signed commits/tags, github HTTPS→SSH rewrite
├── dot_profile        chezmoi → ~/.profile
├── dot_envrc          chezmoi → ~/.envrc               direnv root
├── dot_tmux.conf      chezmoi → ~/.tmux.conf
├── private_dot_ssh/   chezmoi → ~/.ssh/                (mode 700; private_ prefix preserves permissions)
├── bin/               chezmoi → ~/bin/                 user shell scripts deployed to PATH (agent-isolated, full-reload, restart-waybar, …)
├── root/              chezmoi → /root/ (system files; opt-in)
│
├── .chezmoiignore                              tells chezmoi which paths to NOT deploy (e.g. arch-install/)
├── .gitignore                                  excludes user_credentials.json, *.bak, etc.
└── SECRETS.md                                  how secrets are managed (Bitwarden + Infisical)
```

## Two phases, one source

### Phase 1 — fresh-machine install (live USB)

Use the `arch-install/` subdir. It is **NOT** deployed by chezmoi (`.chezmoiignore` excludes it) — it lives in the repo because that's where it belongs, but it's tooling for a state where chezmoi hasn't run yet.

Three equivalent ways to reach it on a live USB:

```bash
# A. clone over the network (preferred when wifi works):
git clone --depth=1 https://github.com/NullSense/dotfiles.git
cd dotfiles/arch-install

# B. copy from Ventoy USB (offline-safe; same files):
cp -r /run/media/$USER/Ventoy/migration-backup/arch-install ~/install
cd ~/install

# C. via chezmoi (if chezmoi is installed in the live env):
chezmoi init https://github.com/NullSense/dotfiles.git --no-tty
cd ~/.local/share/chezmoi/arch-install
```

Then read `arch-install/RUNBOOK.md` and run:
```bash
nano user_credentials.json     # fill in real passwords
./preflight-on-usb.sh
./validate.sh
sudo archinstall --config user_configuration.json --creds user_credentials.json --silent
```

After archinstall reboots into the new system:
```bash
chezmoi init --apply https://github.com/NullSense/dotfiles.git
cd ~/.local/share/chezmoi/arch-install
./post-install.sh
./hardware-optimize.sh
./verify-system.sh
```

### Phase 2 — daily dotfile management

Standard chezmoi:
```bash
chezmoi edit ~/.zshrc        # edit source
chezmoi diff                 # preview
chezmoi apply                # deploy
chezmoi cd && git push       # publish
chezmoi update               # pull latest from origin and apply
```

## Why is `arch-install/` in the dotfiles repo and not separate?

It used to be `github.com/NullSense/arch-install` — that was friction. Both are "things needed to bootstrap a machine," and splitting them meant two clones, two places to remember, two diff windows.

This is the de-facto pattern for "Arch + chezmoi" repos in the wild — see [cogikyo/dotfiles](https://github.com/cogikyo/dotfiles) (`etc/arch.json` + `install.sh` at root), [AnshumanTripathi/dotfiles](https://github.com/AnshumanTripathi/dotfiles) (`.chezmoidata/packages.yaml` + `.chezmoiscripts/`), and [rghamilton3/dotfiles](https://github.com/rghamilton3/dotfiles) (per-platform `run_once_*` scripts).

## Secrets

See `SECRETS.md`. TL;DR:
- **Bitwarden** for human-typed secrets (passwords, SSH keys, 2FA codes) — see `arch-install/RUNBOOK.md` Phase 9.95 for the Bitwarden-as-SSH-agent flow
- **Infisical** for app/process secrets (env vars, API keys), via `direnv` per-project — see RUNBOOK Phase 9.95's "Infisical cold start"
- **`.gitignore`** prevents `user_credentials.json` from leaking
- The repo is **public**; nothing here decrypts to plaintext credentials

## Security model

Three layers of defense, top to bottom:

### 1. Authentication backbone — Bitwarden Desktop SSH agent

```
Bitwarden Desktop  →  ~/.bitwarden-ssh-agent.sock  →  SSH_AUTH_SOCK (set in dot_zshenv)
                                                       ├─ ssh / git push over ssh
                                                       └─ git commit/tag signing  (gpg.format=ssh)
```

- `~/.zshenv` exports `SSH_AUTH_SOCK` conditionally — present even in non-interactive contexts (cron, systemd user units, IDEs).
- `[url "git@github.com:"] insteadOf = https://github.com/` in `dot_gitconfig` forces SSH for github so HTTPS auth never falls through.
- `gpg.format = ssh` + `gpg.ssh.allowedSignersFile = ~/.config/git/allowed_signers` — GPG is **not** used for git; the SSH key is the trust root for everything.
- Locking BW Desktop (timeout or manual) clears all SSH operations until you unlock — intentional trade-off.

### 2. Per-invocation isolation — `agent-isolated` (bubblewrap) via PATH shims

Every coding-agent CLI (`claude`, `codex`, `opencode`) is auto-wrapped by `~/bin/agent-isolated`. The wrapping is enforced by **on-disk binary shims** at `~/bin/{claude,codex,opencode}` that PATH-shadow the real binaries — `~/bin/` is first in `$PATH` per `dot_zshenv`. Each shim execs `~/bin/_agent-shim` which lifts known wrapper flags and dispatches through `agent-isolated`.

Why shims, not zsh functions: a function only intercepts zsh invocations. Anything else — `command claude`, `/usr/bin/env claude`, any non-zsh shell, an `exec()` syscall from a program, a systemd unit — would bypass the wrapper. Real binaries on `$PATH` catch all PATH-based lookups regardless of context.

The agent runs with `tmpfs /` + `tmpfs $HOME`, plus a curated allowlist of read-only paths and read-write workspaces. It **cannot** see `~/.ssh`, `~/.gnupg`, `~/.config/rbw`, the rbw/SSH-agent sockets, the chezmoi `private_*` sources, atuin history, the cliphist DB, or any secret-bearing env var.

Escape-hatches (default off, opt-in per invocation):
- `claude --ssh`          → binds `~/.bitwarden-ssh-agent.sock`, exports `SSH_AUTH_SOCK`
- `claude --gpg`          → binds `$XDG_RUNTIME_DIR/gnupg`
- `claude --rbw`          → binds the rbw socket + config + binary
- `claude --agent-vault`  → routes outbound HTTPS through agent-vault for credential injection

Bypasses (deliberate, no longer accidental):
- `AGENT_UNSANDBOX=1 claude …` — env-var gate inside `agent-isolated`
- `~/.local/bin/claude …` (or `/usr/bin/codex`, `/usr/bin/opencode`) — invoke the real binary by full path

`command claude` does **not** bypass: it still resolves through `$PATH` and hits the shim. Closing this hole was the reason for moving from zsh functions to shims.

Self-test: `~/bin/agent-isolated --self-test` runs 26 verifications (20 negative — secrets must be hidden, 6 positive — required surfaces must be reachable).

### 3. Defense in depth — `deny-secrets` PreToolUse hook

Lives at `dot_claude/hooks/deny-secrets.sh`. Pattern-matches every `Bash` tool call inside an agent and refuses ones that name known secret-extraction commands or paths (`rbw`, `bw`, `cat ~/.ssh`, `cat ~/.gnupg`, etc.). Caught a real incident on 2026-05-08 — see `the-night-an-ai-ate-my-home-directory.md`. The hook is redundant with the bwrap sandbox (the secrets aren't reachable from inside anyway), but layered defense costs nothing.

### Verifying the stack

```sh
~/bin/agent-isolated --self-test            # 26-check sandbox verification
stat -c '%a %n' ~/.bitwarden-ssh-agent.sock # expect 700
ssh-add -l                                  # expect your keys listed
git log --show-signature -1                 # expect "Good signature" via SSH
```
