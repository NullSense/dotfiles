# dotfiles

Arch Linux + Sway + Wayland. **One repo, one source of truth.** Managed by [chezmoi](https://www.chezmoi.io/).

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
│   ├── fix-boot-after-windows.sh               recovery
│   └── sway-display-config.txt                 dual-monitor + DDC + HDR + fonts
│
├── dot_claude/        chezmoi → ~/.claude/             Claude Code: CLAUDE.md, mcp.json, statusline, skills, commands, memory
├── dot_codex/         chezmoi → ~/.codex/              Codex CLI: config.toml, rules
├── dot_config/        chezmoi → ~/.config/             opencode/, sway/, ghostty/, etc.
├── dot_local/         chezmoi → ~/.local/              user-installed binaries layout
├── dot_swaylock/      chezmoi → ~/.swaylock/           swaylock theming
├── dot_zshrc          chezmoi → ~/.zshrc
├── dot_bashrc         chezmoi → ~/.bashrc
├── dot_gitconfig      chezmoi → ~/.gitconfig
├── dot_profile        chezmoi → ~/.profile
├── dot_tmux.conf      chezmoi → ~/.tmux.conf
├── private_dot_ssh/   chezmoi → ~/.ssh/                (mode 700; private_ prefix preserves permissions)
├── symlink_dot_vimrc  chezmoi → ~/.vimrc               (symlink, not copy)
├── bin/               chezmoi → ~/bin/                 user shell scripts deployed to PATH
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
