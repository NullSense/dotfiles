# Arch Install Runbook

End-to-end checklist. Read top-to-bottom in order.

## ⚡ Final pre-install gate — do these before booting the Arch USB

Concrete things that, if missed, will hurt:

- [ ] **Push pending dotfile changes** — `chezmoi cd && git status` clean (line `bindkey -e` was already pushed in 76227dc).
- [ ] **Save atuin encryption key to Bitwarden** — `atuin key`, paste into a secure note. Without this, all synced shell history becomes unrecoverable on Arch.
- [ ] **Bitwarden vault export** to a USB stick (Settings → Export Vault → JSON). Emergency-only copy. Delete after Arch is verified working.
- [ ] **Disable Windows Fast Startup** — done (HiberbootEnabled=0).
- [ ] **Update motherboard BIOS** to current. Verify AGESA ≥ 1.2.0.2 in BIOS info screen.
- [ ] **In BIOS**:
  - [ ] CSM disabled
  - [ ] Above-4G Decoding enabled (verified ON via Windows agent)
  - [ ] Resizable BAR enabled — confirm in BIOS UI directly (Windows tools can be inconclusive)
  - [ ] **EXPO/DOCP set to DDR5-6000 profile** — currently running 5600, leaving perf on the table
  - [ ] BIOS Fast Boot disabled
  - [ ] Secure Boot disabled (we re-enable later via sbctl)
- [ ] **Transmission state** copied off if you want torrents to resume (`%APPDATA%\transmission\` → USB).
- [ ] **Note hardware specifics** for the live USB:
  - Motherboard model (so you can google specific BIOS quirks if anything weird)
  - Which DP port is which on the back of the GPU (label them with tape so you don't shuffle DP-1/DP-2 on first boot)

### Then — make the install media

- [ ] Download Arch ISO: https://archlinux.org/download/
- [ ] Write to USB with Rufus (DD/ISO mode, NOT Windows-To-Go).
- [ ] Copy `~/arch-install/` directory to a second USB stick (or a separate partition on the same one).
- [ ] On first USB, boot, run `./preflight-on-usb.sh` then `./validate.sh` then `archinstall --dry-run`. If green, go for real.

### After Arch is up — first 30 minutes

- [ ] `./post-install.sh` (zram + swapfile + mise + udiskie + global anti-AI-attribution git hook + paru + bwrun deps)
- [ ] `./hardware-optimize.sh` (UKI cmdline, GPU udev, gamemode)
- [ ] Open Bitwarden Desktop → Settings → Enable SSH agent → set "Confirm once per unlocked session"
- [ ] Generate new ed25519 SSH key in Bitwarden → add pubkey to GitHub (Authentication AND Signing)
- [ ] `infisical login` → set up your one personal project per the cold-start recipe
- [ ] `tailscale up` → claim machine
- [ ] `./verify-system.sh` — green across the board

The rest (Secure Boot via sbctl, AI inference setup, dual-monitor color tuning, YubiKey if you decide to buy) is all incremental — do it on your schedule.

---


## Phase 0 — Windows side (do BEFORE booting Arch USB)

### Disable Fast Startup

This is mandatory. Fast Startup leaves NTFS in a half-hibernated state so Linux can't safely mount Windows partitions.

**Quickest check (PowerShell as Admin):**
```powershell
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled).HiberbootEnabled
```
- `0` or "property not found" → already off ✓
- `1` → still on, follow steps below

**Disable via Control Panel:**
1. Win+R → `control` → Power Options
2. Sidebar: "Choose what the power buttons do"
3. Click "Change settings that are currently unavailable" (UAC prompt)
4. Uncheck "Turn on fast startup (recommended)"
5. Save changes

**Disable via PowerShell (Admin) instead:**
```powershell
powercfg /h off              # also disables hibernation entirely
# OR keep hibernation but kill fast startup:
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /V HiberbootEnabled /T REG_DWORD /D 0 /F
```

`hiberfil.sys` should disappear from `C:\` either way.

## Phase 1 — BIOS/UEFI checklist

These can ONLY be verified inside the BIOS itself. Boot to UEFI setup (`systemctl reboot --firmware-setup` from Linux, or mash F2/Del at POST):

| Setting | Value | Notes |
|---|---|---|
| BIOS version | Latest from vendor | You said you're current — verify against vendor download page |
| AGESA | ≥ 1.2.0.2 | Visible on main BIOS screen or in System Info |
| CSM (legacy boot) | **Disabled** | UEFI-only required for systemd-boot |
| Secure Boot | Disabled FOR NOW | We enable it later via `setup-secure-boot.sh` |
| Above 4G Decoding | **Enabled** | Prerequisite for ReBAR |
| Resizable BAR (or "Smart Access Memory") | **Enabled** | You said this is on ✓ |
| EXPO / DOCP / XMP for DDR5 | **Enabled** | Without this, RAM runs at JEDEC base (4800 MT/s) |
| SVM / AMD-V | Enabled | If you ever run KVM/QEMU |
| TPM (fTPM) | Enabled | Future-proof; required if you later TPM-bind LUKS |
| Fast Boot (motherboard, NOT Windows) | Disabled | Sometimes skips POST init Linux needs |

After install, run `./verify-system.sh` — it reports back what's actually live (ReBAR, AGESA, BIOS version) so you can spot-check.

## Phase 1.4 — disk_config (already generated inline in user_configuration.json)

The `disk_config` block is now embedded in `user_configuration.json` as `manual_partitioning` for archinstall 4.x. Layout:

| Partition | Start | Size | FS | Flags | Notes |
|---|---|---|---|---|---|
| ESP (`/boot`) | 1 MiB | 2 GiB | fat32 | `boot`, `esp` | Holds 3 UKIs × 2 (regular + fallback) for linux-zen / linux / linux-lts |
| Root | 2 GiB | **1860 GiB** | btrfs | — | Subvolumes: `@`, `@home`, `@snapshots`, `@log`, `@pkg`, `@swap`. Mount opts: `compress=zstd:3,noatime,ssd,discard=async,space_cache=v2` |

**The 1860 GiB is hardcoded** for your specific 2 TB NVMe. If you ever swap to a different drive, regenerate by running `archinstall` interactively on the live USB and choosing "Save configuration" before installing — copy the resulting `disk_config` block back into our `user_configuration.json` (preserve our `packages`, `custom_commands`, `kernels`).

`preflight-on-usb.sh` verifies `/dev/nvme0n1` exists and is at least the expected size before you launch the real install.

## Phase 1.5 — Pre-flight (run on the live USB, before installing)

Boot the Arch USB, get on the network, mount your config USB stick:
```bash
iwctl                                   # only if WiFi
station wlan0 connect "YourSSID"
ping -c2 archlinux.org

# Get configs onto the live env (USB stick or curl from gist):
mount /dev/sdX1 /mnt && cp -r /mnt/arch-install ~/ && umount /mnt
cd ~/arch-install
```

Run the preflight checks:
```bash
./preflight-on-usb.sh                   # hardware visible? UEFI? net? ReBAR? configs valid?
./validate.sh                           # archinstall config sanity
```

If both green, do an **archinstall dry-run** — simulates the whole install without touching disk:
```bash
sudo archinstall --dry-run --silent \
     --config user_configuration.json \
     --creds user_credentials.json
```

If that's clean, drop `--dry-run` for the real run.

**Backup before you wipe** (USB stick or quick SCP to another machine):
- `~/.ssh/id_ed25519` + `.pub` + `known_hosts` (if migrating SSH identity)
- atuin encryption key (`atuin key` — save in Bitwarden)
- Any uncommitted dotfile changes pushed to GitHub
- Transmission state if you want to resume torrents (`%APPDATA%\transmission\` from Windows)
- Bitwarden export (Settings → Export Vault) — emergency recovery copy

## Phase 2 — Install order

```bash
# On the Arch live USB:
./validate.sh                                  # JSON / config sanity
sudo archinstall \
    --config user_configuration.json \
    --creds user_credentials.json
# ... reboot into the new system, log in as your user ...

# As your user:
./post-install.sh           # zram, swapfile, mise, dotfiles, services
./hardware-optimize.sh      # cmdline, udev, gamemode
sudo ./setup-secure-boot.sh # ONLY after putting BIOS in Setup Mode (see below) — needs root
./setup-inference.sh        # llama.cpp Vulkan + ComfyUI Docker
./verify-system.sh          # system-wide health check, run anytime
```

## Phase 3 — Secure Boot (after first successful boot)

Already documented in `setup-secure-boot.sh` header. TL;DR:

1. Reboot into BIOS, **clear Secure Boot keys** to enter Setup Mode (different button per vendor; on ASUS: "Delete all Secure Boot variables").
2. Boot back into Arch.
3. `sudo ./setup-secure-boot.sh` — automated path.
4. Reboot, **enable Secure Boot** in BIOS, save.
5. `sudo sbctl status` should now say "Secure Boot: Enabled".

After that: zero maintenance. `sbctl` pacman hook auto-signs every kernel/UKI/bootloader update.

## Phase 4 — Sway color management & HDR

Already documented in `sway-display-config.txt`. TL;DR for your MAG274QRF-QD:

- Need Sway ≥ 1.12 (released March 2026). If `pacman -S sway` is older, `paru -S sway-git`.
- `WLR_RENDERER=vulkan` is required for color management and HDR.
- For SDR-correct rendering: `output DP-1 color_profile srgb`.
- For HDR10: monitor's HDR mode ON in OSD, then `output DP-1 hdr on`. Caveat: Sway HDR works best in fullscreen — desktop SDR↔HDR mixing is rough.

The MAG274QRF-QD is HDR400 — entry-level. Don't expect dramatic HDR. The bigger win on Sway 1.12 is the proper sRGB transfer rendering for everyday use.

## Phase 5 — Monitor management software

Three layers, all installed via the package list:

| Tool | Use it for |
|---|---|
| **`nwg-displays`** | One-shot GUI to lay out monitors, set resolution/refresh/scale. Saves to `~/.config/sway/outputs`. Run once, include in `~/.config/sway/config`. |
| **`kanshi`** | Daemon. Auto-applies different output configs based on which monitors are plugged in. Overkill for your single-monitor desktop, but free. |
| **`wlr-randr`** | CLI for scripts (`wlr-randr --output DP-1 --mode 2560x1440@165Hz`). |

Add this to your sway config to use nwg-displays output:
```
include ~/.config/sway/outputs
```

## Phase 6 — Fan management

You're on a desktop, so the easiest path is best:

- **Case fans:** let the BIOS handle them (fan curves in BIOS UEFI). Software fan control on top of BIOS curves only causes confusion.
- **GPU fans:** `amdgpu` driver handles them automatically. Fine out of the box.
- **Monitoring:** `lm_sensors` (already installed) → `sensors` shows CPU + GPU + chipset temps. `btop` shows them in a nice TUI.
- **Manual GPU fan curve** (only if you care): install **LACT** (`paru -S lact`). It's the cleanest UI for AMD fan curves + undervolting + memory clock control. Better than CoreCtrl.
- **Don't install:** `fancontrol` (the lm_sensors-based daemon). It fights the BIOS curves and rarely works well on AM5.

If at any point things feel hot, run `sensors -s` (sets the chip), then `sensors`. Expect:
- 9700X idle: 35–45 °C, load: 75–85 °C (AMD targets 95 °C as Tjmax — no PBO weirdness needed).
- RX 6750 XT idle: 40–50 °C, load: 75–85 °C edge / 90–100 °C junction.

## Phase 7 — Steam / gaming

Already in package list: `steam, gamemode, lib32-gamemode, mangohud, lib32-mangohud, gamescope`. Plus `protonup-qt` from AUR via `hardware-optimize.sh`.

**Setup after first launch of Steam:**
1. Settings → Compatibility → "Enable Steam Play for all titles" → use **Proton Experimental** (or GE-Proton via ProtonUp-Qt).
2. Per-game launch options — useful starter:
   ```
   gamemoderun mangohud %command%
   ```
3. For tearing-prone or high-refresh games, wrap in gamescope:
   ```
   gamemoderun gamescope -W 2560 -H 1440 -r 165 -f -- mangohud %command%
   ```
4. **MangoHud config**: `~/.config/MangoHud/MangoHud.conf` — a minimal one:
   ```
   fps
   gpu_temp
   cpu_temp
   ram
   vram
   frame_timing=1
   ```

**Optional polish:**
- `goverlay` (AUR) — GUI to tweak MangoHud config.
- `vkbasalt` — post-processing shaders (sharpen, CAS, SMAA). Only if you want it.
- `lutris` — non-Steam launcher, manages Battle.net/EGS/etc.
- `bottles` — Wine prefix manager (AUR, flatpak preferred).

## Phase 8 — Local AI inference

Run `./setup-inference.sh`. It installs:
- **llama.cpp Vulkan** (native) for chat/code LLMs. Run via `~/llm/run-llama.sh model.gguf`.
- **ComfyUI** (Docker, ROCm with gfx1031→gfx1030 override). `cd ~/comfyui && docker compose up -d`, then http://localhost:8188.

**Why this layout:**
- Vulkan path for LLMs = stable, no ROCm headache.
- ComfyUI in Docker = ROCm hacks isolated to a container. Container handles `HSA_OVERRIDE_GFX_VERSION=10.3.0` for you.

Don't bother with vLLM on this card. gfx1031 isn't a real ROCm target — you'd be patching constantly. If you ever need vLLM-class throughput, it's a card upgrade question.

## Phase 9 — WiFi / Bluetooth

Both are motherboard-chip dependent. Most AM5 boards ship Intel AX210/AX211 (best Linux support), some ship MediaTek MT7921 (good support), occasionally Realtek RTL8852 (decent in 2026 with current firmware).

Already installed:
- `linux-firmware` — covers all three vendors' firmware blobs.
- `networkmanager` + `network-manager-applet` — WiFi UI.
- `bluez` + `bluez-utils` + `blueman` — BT stack + tray.
- Both services auto-enabled via `custom_commands`.

**After install, verify:**
```bash
nmcli device                    # should list your wifi adapter as "available"
bluetoothctl list               # should show your BT controller
```

If WiFi adapter is missing: `lspci | grep -i network` — confirm card is detected. If yes but no driver, `dmesg | grep -i firmware` — usually shows what blob is missing. Almost always solved by an extra firmware package (e.g. `linux-firmware-mediatek` if it was split out).

If Bluetooth scanning fails: `sudo systemctl restart bluetooth` and re-pair. Some Realtek BT chips need `rtkbt-firmware` (AUR) — rare on motherboards but common on USB dongles.

## Phase 9.5 — Storage hygiene (auto-cleanup)

Configured automatically:

| What | How | Limit |
|---|---|---|
| **Pacman cache** | `paccache.timer` weekly | Keep last 3 versions |
| **Snapper snapshots** | `snapper-cleanup.timer` daily + tightened retention | 5 hourly, 7 daily, 2 weekly, 0 monthly/yearly, hard cap 20 |
| **Journal** | `/etc/systemd/journald.conf.d/00-size.conf` | 500 MB total, 50 MB per file, 1 month retention |
| **Btrfs balance** | `btrfs-balance.timer` weekly (post-install) | Light balance (`-dusage=50 -musage=70`) — reclaims fragmented blocks |
| **fstrim** | `fstrim.timer` weekly | NVMe TRIM |
| **AUR build dirs** | `paru.conf`: `CleanAfter` + `RemoveMake` | Cleaned after each build |
| **Docker logs** | `/etc/docker/daemon.json` `local` driver | 10 MB × 3 files per container |
| **Docker images/containers** | Manual | Run `docker system prune -a --volumes` monthly. Or set up a user timer (see below). |
| **Cargo cache** | Built-in GC since Rust 1.78 | Auto-deletes unused after 1 month (downloads after 3) |
| **sccache** | `~/.cache/sccache` | 20 GB hard cap (set in mise env) |

**Optional Docker prune timer** (uncomment in your dotfiles or run once):

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/docker-prune.service <<'EOF'
[Unit]
Description=Docker system prune
[Service]
Type=oneshot
ExecStart=/usr/bin/docker system prune -af --volumes --filter "until=720h"
EOF
cat > ~/.config/systemd/user/docker-prune.timer <<'EOF'
[Unit]
Description=Weekly docker prune
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl --user enable --now docker-prune.timer
```

**Cargo target dirs** are project-local; they're not auto-cleaned. Add this alias if it bothers you:
```sh
alias cargo-sweep='find ~ -type d -name target -path "*/.git" -prune -o -name target -print -exec cargo clean --manifest-path {}/.. \;'
```
Or install `cargo-sweep` (`cargo install cargo-sweep`) and run `cargo sweep -t 30 ~` periodically.

## Phase 9.6 — Firewall & security

**Firewall: firewalld** (installed + enabled via `custom_commands`).

I picked firewalld over ufw because:
- Native nftables backend (no iptables shim).
- Plays nicer with Docker (Docker rules live in their own table; firewalld scopes to its own).
- Zone-aware via NetworkManager — different rules for "home" Wi-Fi vs "public".
- Same UX once configured (`firewall-cmd --add-service=...`).

**Default zone is `public` (drop-by-default).** That's correct for a desktop. Common zone tweaks:

```bash
# Check status
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all

# Open Steam Remote Play / Moonlight if you use them
sudo firewall-cmd --permanent --add-service=steam-streaming
sudo firewall-cmd --reload

# Trust local LAN (e.g., to share llama-server with your phone)
sudo firewall-cmd --permanent --zone=home --add-source=192.168.1.0/24
sudo firewall-cmd --permanent --zone=home --add-port=8080/tcp
sudo firewall-cmd --reload
```

**Docker note:** Docker creates its own iptables/nftables rules that bypass firewalld zones. This is by design — Docker manages its own bridge networking. If you want Docker containers blocked by firewalld too, the cleanest fix is `--network host` only when you actually need to expose, or use `127.0.0.1:PORT` bindings (which bypass external access regardless of firewall).

**What I did NOT install** (intentional):
- `ufw` — the older iptables-frontend; firewalld is strictly better with nftables/zones.
- `apparmor` — adds friction without much desktop benefit; mostly server-grade hardening.
- `usbguard` — meaningful for laptops in adversarial environments, overkill for a home desktop.
- `fail2ban` — only needed if exposing SSH publicly. You're not.

## Phase 9.7 — Keys & secrets

Installed: `gnupg`, `pass`, `keychain`.

**SSH keys**: see [Phase 9.95](#phase-995--ssh-keys-rotate-store-in-bitwarden-use-bitwarden-as-ssh-agent) for the full Bitwarden-SSH-agent-based flow. Bitwarden's desktop SSH agent (built-in since v2025.1.2) replaces the systemd ssh-agent entirely — don't enable both.

**GPG (for signing git commits + pass) — alternative to Bitwarden's SSH-signing path:**
```bash
gpg --full-generate-key   # ed25519 (option 9), 0 = no expiry, real name + email
gpg --list-secret-keys --keyid-format=long
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

**Password store:**
```bash
pass init <YOUR_GPG_KEY_ID>
pass insert github/token
pass insert email/work
pass git init        # version your password store
pass git remote add origin git@github.com:youruser/password-store.git
```

**Secrets in dotfiles:** chezmoi has built-in age/gpg/pass integration. In `~/.local/share/chezmoi/.chezmoi.toml.tmpl`:
```toml
[data.secrets]
github_token = {{ pass "github/token" | quote }}
```

**Don't bother with:**
- `seahorse` (gnome-keyring GUI) — gnome-keyring is heavy and you're on Sway.

### Browser password storage — why not

Three reasons:
1. **Threat model.** Browser password stores decrypt to RAM behind any logged-in session. Any process running as your user (Electron app, malicious browser extension, npm postinstall script) can dump them. A dedicated password manager keeps the vault encrypted at rest until you actively unlock it, and re-locks on idle.
2. **No cross-context sharing.** Browsers can't autofill into native apps, terminals, SSH-passphrase prompts, sudo, IDE git operations, etc.
3. **Sync surface.** Browser-vault sync goes through the browser vendor's account; if you're already paying/using Bitwarden you're trusting fewer vendors with the same data.

The exception that's *fine*: storing low-stakes site logins (forum accounts, etc.) in the browser as a UX shortcut, while the real secrets live in Bitwarden.

### Bitwarden — keep using it

Added `bitwarden` (desktop GUI) and `bitwarden-cli` (`bw`) to the package list. With CLI:
```bash
bw login
bw unlock              # outputs BW_SESSION; export it
bw get password github
bw get item "AWS Console" | jq
```

For shell automation, pair with `pass`-style helpers — or just use `bw` directly in scripts.

If you want self-hosted: **vaultwarden** (Rust rewrite of Bitwarden server) runs in a single Docker container with sqlite. Compatible with all official Bitwarden clients. Worth doing if you're already running Docker for other things.

### Infisical vs Bitwarden — different tools, both useful

| | Bitwarden | Infisical |
|---|---|---|
| **Use case** | Human passwords, 2FA codes, secure notes | App secrets — env vars, API keys, service-account tokens |
| **UX** | Browser autofill, mobile apps, OS keyring | CLI + SDK injection (`infisical run -- npm start`), `.env` replacement, CI/CD pipelines |
| **Sharing model** | Per-item with people | Per-environment (dev/staging/prod), per-service |
| **Audit trail** | Yes, basic | Yes, with secret-rotation, version history, approval workflows |
| **Self-host** | Vaultwarden (community) | Infisical itself is open-core, self-hostable |

**Recommendation:** they don't replace each other.
- **Personal life:** stay on Bitwarden. Adopting Infisical for personal use is overkill — you don't have CI/CD pipelines pulling rotating secrets at home.
- **Work:** if your company is migrating, learn Infisical there. Use it for `.env` files in your dev projects, k8s secret injection, GitHub Actions secret refs. It's strictly better than committing `.env.example` and Slacking real values.
- **Where to draw the line:** if a secret is something *you* type (login form, SSH passphrase) → Bitwarden. If it's something a *machine* reads (DATABASE_URL, OPENAI_API_KEY in code) → Infisical.

You can also bridge them: Bitwarden item → Infisical secret via their API if a value lives in both worlds. But for most setups you just keep them separate.

### Is ed25519 safe? Yes, it's the modern default

Short answer: **use ed25519**. Concerns:

- **Cryptographic strength:** ed25519 is at the ~128-bit security level (equivalent to RSA-3072). NIST FIPS 186-5 standardized it in Aug 2023. Used by Signal, GitHub, modern OpenSSH defaults, sigstore, age. No known practical weaknesses.
- **Performance:** much faster than RSA — signing/verification ~10x quicker, keys are 32 bytes (vs 384 bytes for RSA-3072).
- **"NSA backdoor" concerns:** ed25519 uses Curve25519, designed by Daniel J. Bernstein (djb), specifically chosen with parameters whose origin is fully transparent — unlike NIST P-curves where the seed values aren't explained. ed25519 is the *less* suspicious choice, not more.
- **Quantum:** ed25519 is broken by sufficiently large quantum computers. So is RSA, ECDSA, every classical asymmetric algorithm. When CRQCs land (still years away), everyone migrates to ML-DSA / SLH-DSA together. Until then, no asymmetric algorithm is meaningfully more "post-quantum safe" than another.
- **Optimization:** ed25519 *is* the optimized choice. RSA-4096 is slower, larger, and only "more secure" in the sense that brute-forcing 3072-bit equivalent strength is already astronomically infeasible.

Use ed25519 for SSH and Git signing. Use ed25519 for GPG (option 9 in `gpg --full-generate-key`). Done.

If a service still requires RSA (some legacy enterprise SSH setups), keep an RSA-4096 key on the side — but it's increasingly rare.

## Phase 9.8 — User groups checklist

After `post-install.sh` and `setup-inference.sh`, your user should be in:

| Group | Why | Set by |
|---|---|---|
| `wheel` | sudo | archinstall |
| `docker` | Docker socket access (rootful Docker — alternative is rootless) | `post-install.sh` |
| `render` | `/dev/dri/renderD*` access — Vulkan compute, ROCm | `setup-inference.sh` |
| `video` | `/dev/dri/card*` access — display, VAAPI | `setup-inference.sh` |

Verify with `groups`. After group changes, re-login (or `newgrp <group>` for one shell).

**You probably don't need:**
- `audio` — pipewire/wireplumber don't need it (logind grants audio per-session).
- `input` — same, handled by logind.
- `storage` — only for some block-device tools.
- `lp`, `scanner` — only if you actually use a printer/scanner.

## Phase 9.85 — Dual monitor (AORUS OLED + MSI MAG274QRF-QD)

Full config is in `sway-display-config.txt`. Highlights:

**AORUS OLED — primary, color & HDR**
- Set native mode + max refresh (depends on your specific AORUS model — confirm with `swaymsg -t get_outputs | jq '.[].current_mode'` after first login).
- Scale 1.5 if it's 4K @ 27"; scale 1.0 if 1440p.
- `render_bit_depth 10` — gradients are dramatically better on OLED with 10-bit.
- `adaptive_sync on` is fine — OLEDs handle FreeSync without the desktop flicker that IPS suffers.
- `color_profile srgb` — Sway 1.12+ piece-wise sRGB transfer.
- HDR: bind `Mod+Shift+h` to toggle. Worth it on AORUS OLED (HDR1000), not on the MSI (HDR400).

**MSI MAG274QRF-QD — secondary, IPS**
- 2560x1440@165Hz, scale 1.0, `color_profile srgb`.
- `adaptive_sync off` — IPS+FreeSync flickers on desktop. Bind `Mod+Shift+f` to toggle when gaming.
- Position to the right of AORUS (`position 3840 0` if AORUS is 4K @ 1.5x scale).

**OLED burn-in mitigation** (in `swayidle` config):
- 2 min: DPMS off (screens fully blank, OLED pixels rest).
- 5 min: `swaylock`.
- 10 min: `systemctl suspend`.
- Also turn ON the monitor's OSD pixel-shift / pixel-refresh features.
- **Don't** use software brightness curves on OLED — set it once in OSD and leave it.

**Font rendering quirk:** OLED panels use non-standard subpixel arrangements (WOLED is RGBW, QD-OLED is triangle). Standard RGB-stripe LCD subpixel hinting causes color fringing on OLED text. Recommended: **greyscale antialiasing globally** (`rgba=none`, `lcdfilter=lcdnone`, keep `hintstyle=hintslight`). Looks clean on both panels and avoids the OLED fringing. The fonts.conf snippet is in the display-config file.

**Layout management:**
- Use `nwg-displays` (already installed) for one-shot visual arrangement → saves to `~/.config/sway/outputs`.
- `kanshi` (already installed) for profile-based auto-switch if you ever go single-monitor (laptop dock scenario).

## Phase 9.86 — USB auto-mount

Configured automatically in `post-install.sh`:

- `udisks2` (system) handles the actual mounting.
- `udiskie` (user systemd unit) auto-mounts plugged-in drives to `/run/media/$USER/<label>/`.
- Notifications via mako on mount/unmount.
- Default file manager for opening: thunar (configurable).

Plug in a USB → mount notification → drive appears in thunar / `cd /run/media/$USER/`.

If a drive doesn't auto-mount: `journalctl --user -u udiskie` and `lsblk -f` to debug. Most often: the drive's filesystem isn't supported (e.g., bare exfat needs `exfatprogs` package — already in base).

## Phase 9.87 — Time sync

archinstall sets `"ntp": true` which enables `systemd-timesyncd`. That's accurate to ~10ms — fine for desktop, gaming, dev. **No action needed.**

Verify: `timedatectl status` — look for "System clock synchronized: yes" and "NTP service: active".

If you ever need sub-millisecond precision (audio production, financial trading): replace timesyncd with `chrony` (`systemctl disable --now systemd-timesyncd && pacman -S chrony && systemctl enable --now chronyd`). Otherwise ignore it.

## Phase 9.88 — File managers

You have **two**, picked deliberately:

**Primary: yazi** (terminal, already installed)
- Vim-keys, blazing fast, written in Rust.
- **Image preview works in ghostty** via the kitty graphics protocol — yazi auto-detects.
- Also previews video frames (`ffmpegthumbnailer` installed), PDFs (poppler), heic/raw images, archives.
- Config: `~/.config/yazi/yazi.toml`. Default config is excellent.
- Test image preview: `cd ~/Pictures && yazi`, navigate to an image, see it render in the right pane.

**Secondary: thunar** (GUI, just-added)
- For the rare cases yazi isn't right: dragging from a download notification, drag-and-drop into a browser upload, browsing a USB drive visually.
- `thunar-volman` integrates with udiskie for removable media.
- `thunar-archive-plugin` + `file-roller` give right-click "Extract" for zip/tar/7z.
- `tumbler` + `ffmpegthumbnailer` produce thumbnails for images and videos.

Skipped: nautilus (heavy, GNOME-deps), dolphin (heavy, KDE-deps), nemo (Cinnamon-deps).

## Phase 9.89 — Ghostty configuration

Ghostty (installed via post-install) is GPU-accelerated and supports the kitty graphics protocol — that's what makes yazi image previews work.

Recommended `~/.config/ghostty/config`:

```
# Font (Maple Mono NF is in your packages)
font-family = Maple Mono NF
font-size = 12
font-feature = +calt   # ligatures (=>, !=, etc.)
font-feature = +liga

# Cursor
cursor-style = block
cursor-style-blink = false

# Window
window-padding-x = 8
window-padding-y = 8
window-decoration = false
background-opacity = 0.95
background-blur-radius = 20

# Behavior
copy-on-select = true
shell-integration = zsh
shell-integration-features = cursor,sudo,title

# Image protocol — already on by default, but explicit:
image-storage-limit = 320000000   # 320MB; bumps yazi previews & sixel
```

Ghostty handles ANSI media (sixel, kitty graphics, iTerm inline images) natively. No extra config needed for yazi previews to work.

For text rendering specifically: ghostty does its own glyph rasterization, so the global fontconfig (greyscale AA) doesn't affect it. Ghostty looks crisp on both OLED and IPS without per-monitor tweaking.

## Phase 9.91 — Apps + Windows-side migration

Installed via package list:

| App | Package | Login / migration |
|---|---|---|
| Signal | `signal-desktop` | Open → "Link as new device" → scan QR with phone. Chats live on phone, desktop is a linked client (no message history pre-link). |
| Telegram | `telegram-desktop` | Login by phone number → SMS or in-app code. Message history syncs from cloud automatically. |
| Discord | `discord` | Login or QR-scan. Server/DM history is server-side, just appears. |
| Bitwarden | `bitwarden` + `bitwarden-cli` | Login email + master password. Vault syncs. |
| Transmission | `transmission-qt` | Migrate from Windows: copy `%APPDATA%\transmission\` (specifically `settings.json`, `torrents/`, `resume/`) into `~/.config/transmission/`. Existing torrents resume in-place if data paths match — adjust `download-dir` in settings.json. |
| Jellyfin (client) | `jellyfin-media-player` | Open → enter server URL + login. Pure client; no migration needed. |
| Tailscale | `tailscale` | `sudo tailscale up` → opens browser → claim machine on your tailnet. Same mesh as Windows machine (don't delete the Windows node, you can keep it). |

### Wispr Flow on Linux — closest match is `whisrs`

Wispr Flow is Mac/Windows only. The Linux landscape in 2026 has finally caught up. Options ranked by "how close to Wispr Flow":

1. **`whisrs`** (https://github.com/y0sif/whisrs) — Rust, Linux-first, **explicitly Sway/Hyprland-tested**. Closest to Wispr Flow's UX:
   - Push-to-talk hotkey, types at cursor in any app
   - Backends: Groq (free tier), OpenAI Realtime (streaming), local whisper.cpp (Vulkan-accelerated on your RX 6750 XT)
   - **Custom vocabulary** in config (`vocabulary = ["NullSense", "Hyprland", "ed25519"]`) — improves transcription accuracy on your jargon
   - **Filler word removal** built in (`um`, `uh`, `you know`)
   - **LLM command mode**: select text, dictate instruction, get rewrite — like Wispr Flow's AI mode
   - System tray, transcription history, 18 languages, AUR-packaged
   - Caveat: 5 ⭐ (March 2026 launch), small project but exactly the right shape
2. **`vocalinux`** (https://github.com/jatinkrmalik/vocalinux) — more mature (39 ⭐, 16 releases), 100% offline, GPU-accelerated whisper.cpp via Vulkan. Doesn't have AI rewrite or vocabulary learning, but rock-solid for plain dictation.
3. **`xhisper-local`** — fork that adds local Whisper + Ollama post-processing (grammar/punctuation correction, command-syntax mode). Closer to Wispr Flow's "Flow" rewrite feature.

About the **auto-dictionary** specifically: Wispr Flow's killer feature is that it learns your jargon as you type/correct. **No Linux tool auto-learns yet.** The closest paths:
- **`whisrs` + manually-maintained vocabulary** — write vocabulary list once, refine as you go. Not auto, but durable.
- **`xhisper-local` + Ollama prompt** — post-process every transcript through a local LLM with a prompt like "fix terminology: NullSense, Hyprland, ed25519, Bitwarden..." — close to "auto" if you script vocabulary appends.
- **Roll your own**: `whisper.cpp --prompt "$(cat ~/.cache/dictation-vocab)" ...` and append corrections to the vocab file. ~30 lines of bash.

**My recommendation:** install `whisrs` first (`paru -S whisrs` once you're up). It has the best Sway story, runs whisper.cpp on Vulkan (free, fast on your 6750 XT), and the vocabulary config is right there. If it feels rough, drop down to `vocalinux` for stability.

Did **not** auto-install — these are early-stage projects, you should pick deliberately.

## Phase 9.915 — YubiKey: necessary or not?

Honest answer: **not strictly necessary, but worth it for your profile.** You're a developer with prod-system access, dual-boot dev workstation, multiple AI agents holding secrets, GitHub commits worth signing. The marginal-security upgrade over Bitwarden-alone is meaningful but not gigantic.

### What a YubiKey adds *over Bitwarden SSH agent*

| Threat | Bitwarden alone | + YubiKey |
|---|---|---|
| Master password phished | Attacker has full vault → game over | Master + YubiKey FIDO2 needed → blocked |
| Bitwarden client compromised | Theoretical pre-encryption exposure | Hardware-bound keys never leave the device |
| Malware reads `~/.bitwarden-ssh-agent.sock` while vault unlocked | Could request silent signatures | FIDO2 keys require physical touch — silent abuse blocked |
| Laptop stolen with vault auto-unlock | Attacker has SSH | Useless without the YubiKey |
| Phishing site captures FIDO2 credential | N/A | Origin-bound — can't be replayed |

### Buy if

- You SSH into prod servers or homelab boxes you care about.
- You sign git commits for projects with users / serious deps.
- You've been in any credential breach (haveibeenpwned).
- You travel.

### Skip if

- Single personal machine, no prod, no published code.
- You'd lose two of them in a month.

### What to buy

- **YubiKey 5C NFC** (~$55) primary, USB-C + NFC for phone use. The 5.7 firmware (late 2024) added more passkey slots — get the newest line.
- **YubiKey 5 NFC** (~$50) backup, in a drawer. **Always buy two** — losing your only one locks you out of everything you set up with FIDO2.
- Cheaper: Token2 PIN+ series (~$30) — FIDO2-only, biometric variants exist.

Skip the C version *without* NFC unless you'll never tap to phone.

### What to use it for (priority order)

1. **FIDO2 2FA on Bitwarden itself** — master password + tap. Single most important upgrade because everything downstream depends on Bitwarden integrity.
2. **FIDO2 2FA on GitHub, Google, Apple, your tailnet.** Drop SMS/TOTP where YubiKey works.
3. **Passkeys** on sites that support them — gradually replace passwords.
4. **SSH via FIDO2 resident key** (`ssh-keygen -t ed25519-sk -O resident -O verify-required`). Key handle on YubiKey, touch required per-signature. *Replaces* Bitwarden agent for your most critical key, or sits alongside (Bitwarden for day-to-day dev, YubiKey for prod-server access).
5. **Git commit signing via SSH-FIDO2** — same key, GitHub shows "Verified" with hardware-backing.
6. **LUKS unlock** with YubiKey — fiddly, optional.

Skip storing main GPG key on YubiKey — SSH signing path is cleaner now that git supports it natively.

### Migration order if you buy

1. Two YubiKey 5C NFCs.
2. Set FIDO2 PINs (`ykman fido access change-pin`) on both.
3. Enroll both as 2FA on Bitwarden, GitHub, Google.
4. Enable Bitwarden "WebAuthn for vault unlock" — master + tap.
5. Optional: `id_ed25519_sk` for prod SSH, keep Bitwarden agent for dev.
6. Stash backup somewhere physical. Test it once a quarter.

This is an *additive* layer, do it after Arch is up. No redesign needed.

## Phase 9.92 — Tailscale notes

Enabled via `custom_commands` (tailscaled service starts on boot). After first boot:

```bash
sudo tailscale up                        # opens browser; auth on your tailnet
sudo tailscale up --ssh                  # also enables tailscale-ssh (skip if you don't want it)
sudo tailscale set --operator=$USER      # so you can run 'tailscale status' without sudo
```

Useful flags later:
- `tailscale ip -4` — your tailnet IP.
- `tailscale serve https / http://localhost:8080` — expose llama-server / ComfyUI to your tailnet.
- `tailscale funnel` — expose to public internet (only if you really want that).

Don't forget to **remove the Windows machine** from your tailnet admin console once you've migrated, or rename it so you don't get confused.

## Phase 9.93 — Hardware brightness via DDC/CI (the actually-correct way)

Earlier I said don't software-dim OLED. That was wrong as a blanket rule — Wayland *gamma* dimming doesn't help (just remaps RGB), but real **DDC/CI** brightness writes to the monitor's OSD and lowers the panel's emission voltage. That's hardware-level dimming = real OLED wear reduction.

Set up automatically:
- `ddcutil` installed.
- `i2c-dev` kernel module loaded at boot.
- `i2c` group created, udev rule grants group access to `/dev/i2c-*`.
- Your user added to `i2c` (re-login required after first boot).

After re-login, test:
```bash
ddcutil detect           # must list AORUS + MSI
ddcutil getvcp 10        # current brightness on display 1 (0-100)
ddcutil setvcp 10 50     # set to 50
ddcutil --display 2 setvcp 10 50   # dim only the MSI
```

Sway config (in `sway-display-config.txt`):
- swayidle steps: **90s → DDC dim to 30% → 3 min DPMS off → 5 min lock → 30 min suspend**.
- Helper scripts (`~/.local/bin/dim-monitors`, `~/.local/bin/restore-monitors`) save and restore your "normal" brightness.
- `XF86MonBrightnessUp/Down` keys bound to `ddcutil ... +/- 10`.
- `gammastep` (also installed) for color-temp / night mode — separate from DDC, uses Sway's gamma protocol.

If `ddcutil detect` doesn't find your monitors:
1. Check the i2c module: `lsmod | grep i2c_dev` — load with `sudo modprobe i2c-dev` if absent.
2. Check group: `groups | grep i2c` — re-login if absent.
3. Some monitors ship with DDC/CI **disabled in the OSD by default**. Check the AORUS/MSI menu for "DDC/CI" or "External Control" and enable.
4. DDC/CI doesn't work over USB-C/DP MST hubs reliably — try directly to the GPU.

## Phase 9.94 — Your current dotfile + history + plugin stack

You already have all of this set up. This section documents how to *use* + *migrate* it.

### chezmoi (dotfiles)

- Source repo: `https://github.com/NullSense/dotfiles`
- Source path on disk: `~/.local/share/chezmoi` (a normal git repo)
- Currently tracked branch: `master`, up to date with origin
- **You currently have uncommitted changes to `dot_zshrc`.** Commit + push these BEFORE wiping Windows or you'll lose them.

```bash
# Check what's pending right now:
chezmoi cd                          # cd into source repo
git status
git diff dot_zshrc                  # confirm what changed

# Commit + push (do this on the WSL/Windows machine RIGHT NOW):
chezmoi cd
git add -u
git commit -m "wip: zshrc tweaks"
git push origin master
exit                                # exit subshell back to home
```

**On the new Arch system**, `post-install.sh` runs:
```bash
chezmoi init --apply https://github.com/NullSense/dotfiles.git
```
Which clones + applies in one step. Done.

**Daily use:**
```bash
chezmoi edit ~/.zshrc               # edit the SOURCE (not the deployed copy)
chezmoi diff                        # show what apply would change
chezmoi apply                       # deploy edits to home
chezmoi cd && git push              # publish to GitHub
chezmoi update                      # pull latest from origin and apply
```

The cardinal rule: **edit via `chezmoi edit`, not directly in `~`.** Direct edits in `~` get clobbered on next `chezmoi apply`.

For secrets in templates, chezmoi pairs with `pass`/`bitwarden`/`age`. See [chezmoi docs §templates](https://www.chezmoi.io/user-guide/templating/).

### atuin (terminal history with sync)

- Status now: synced to `https://api.atuin.sh` as user **NullSense**, sync interval 5 min, last sync working ✓.
- Storage: encrypted client-side; the server only sees ciphertext.
- Search: `Ctrl-R` opens fuzzy fullscreen search across **all your machines**.

**Migrate to Arch:**
```bash
# After post-install.sh installs atuin, on the new machine:
atuin login -u NullSense            # enter password + key (generated on first machine)
atuin sync                          # pull all history
```

**You need your encryption key** on the new machine. To export from your current setup:
```bash
# On the Windows/WSL side, BEFORE wiping:
atuin key                           # prints your encryption key — save securely (Bitwarden!)
```

If you lose the key, the history is unrecoverable (server only has ciphertext). **Save it in Bitwarden right now.**

**Self-host alternative** (if you don't want to depend on api.atuin.sh): atuin server is one Docker container with sqlite. Worth doing once you have Tailscale up — point all your machines at `http://atuin.tailnet:8888`.

### zinit (zsh plugin manager)

- Source: `~/.local/share/zinit/zinit.git` (cloned by post-install.sh)
- Loads in turbo/lazy mode in your zshrc — startup stays fast.
- Plugins it manages: `fast-syntax-highlighting`, `zsh-autosuggestions`, `zsh-completions`, plus OMZ snippets (`git`, `sudo`, `command-not-found`).

**Update plugins:**
```bash
zinit self-update                   # update zinit itself
zinit update                        # update all plugins
```

You don't need to manually `git pull` anything — `zinit update` handles all of them.

### Tools your zshrc currently sources (ordered top-to-bottom, with the bug)

```
zinit                   # plugin loader
mise                    # version manager (rust/node/python/bun)
fzf                     # fuzzy finder keybinds
atuin                   # history sync + Ctrl-R
zoxide                  # smart cd ← currently before starship (BUG)
starship                # prompt
zshaliases / zshfzfrc   # your custom aliases
```

**Fix:** move zoxide init to the **last** line (after starship, after aliases). The doctor warning you've been seeing in every shell is because starship's precmd hook runs after zoxide's chpwd, occasionally shadowing it. Edit your dotfiles repo, not `~/.zshrc` directly:

```bash
chezmoi edit ~/.zshrc
# move the `eval "$(zoxide init zsh ...)"` line to the bottom of the file
chezmoi apply
chezmoi cd && git add -u && git commit -m "fix: zoxide init order" && git push
```

## Phase 9.95 — SSH keys (rotate, store in Bitwarden, use Bitwarden as SSH agent)

**Recommended path: rotate, don't migrate.** SSH keys are per-host best practice, you're already provisioning a new machine — the costs are sunk. Generate fresh, add the new pubkey to GitHub + servers, delete the old.

### Bitwarden is your SSH agent (since v2025.1.2)

Bitwarden Desktop runs a Unix socket at `~/.bitwarden-ssh-agent.sock` that drop-in-replaces ssh-agent. SSH key lives encrypted in your vault, never sits as plaintext on disk. Vault unlock (master password, optionally TouchID/WebAuthn) = SSH access.

**One-time setup on Arch:**
```bash
bitwarden &                              # log in, unlock

# In the desktop app:
#   1. Settings → Enable SSH agent
#   2. Vault → Add item → "SSH Key" type
#   3. Click "Generate" → ed25519 → set passphrase from generator
#      (passphrase auto-stored in the same vault item)
#   4. Copy the public key field

# Add the public key to GitHub:
#   github.com/settings/keys → New SSH key → paste

# Wire shell to use Bitwarden's agent:
echo 'export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"' >> ~/.zshenv

# Verify:
ssh-add -L                               # should list Bitwarden-served key
ssh -T git@github.com                    # Bitwarden prompts to authorize first use
```

In Bitwarden's SSH agent settings, choose **"Confirm once per unlocked session"** — confirmed as your preference. First `ssh`/`git push` after vault unlock prompts; everything after is silent until you lock the vault again. Best ergonomic/security balance.

After this, the systemd-user `ssh-agent.service` is no longer needed — disable it:
```bash
systemctl --user disable --now ssh-agent.service
```

### Migrating from your current key (alternative if rotation is too much hassle)

If you really want to keep the existing key:
1. On WSL/Windows side: `cat ~/.ssh/id_ed25519` — copy contents.
2. In Bitwarden Desktop: Add item → SSH Key → "Import key from clipboard" → paste, supply passphrase if any.
3. The key file on the old machine is now redundant — keep `~/.ssh/known_hosts` if useful, but the private key file can be deleted once Bitwarden agent is verified working on Arch.

### `~/.ssh/config` — minimal

You don't need to specify `IdentityFile` since the Bitwarden agent presents the key. Just identity-only matching to keep multiple keys clean:

```
Host github.com
    IdentitiesOnly yes
    AddKeysToAgent no                # agent is Bitwarden, not local cache

Host home-server
    HostName 100.x.y.z               # tailnet IP
    User matas
```

### Git commit signing via Bitwarden SSH agent

Bitwarden's agent supports the SSH signing protocol Git uses since v2.34. Skip GPG entirely:

```bash
# Tell git to sign with the SSH key from Bitwarden:
PUBKEY=$(bw get item "SSH key — main" | jq -r '.sshKey.publicKey')
echo "$PUBKEY" > ~/.config/git/allowed_signers_self.pub

git config --global gpg.format ssh
git config --global user.signingkey "$PUBKEY"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers_self.pub

# At github.com/settings/keys, add the SAME public key as a "Signing Key"
# (separate listing from "Authentication Key", though same key works for both)
```

Now `git commit` triggers a Bitwarden prompt and produces a signed commit. No GPG keys to manage, no `gpg-agent` separately running.

### Unified secrets across AI agents — Infisical + direnv (the ergonomic path)

Running `infisical run -- claude` every time is friction. The fix is **direnv**: it auto-loads env vars when you `cd` into a project and unloads them when you leave. Combined with Infisical, you get "secrets exist while you're in the project, gone when you leave" — no per-command prefix.

#### Why this works

- `direnv` watches your shell. When you `cd` into a directory with an authorized `.envrc`, it sources that file into your shell as exports.
- The `.envrc` calls `infisical export` to fetch secrets and produces shell `export` lines that direnv loads.
- When you leave the directory, direnv unloads the variables. Anything you launch from inside the project (claude, codex, opencode, npm, etc.) inherits them. Anything you launch from outside doesn't.

#### Setup (once per machine)

```bash
# direnv installed via the package list. Enable in your zshrc — already there
# in your dotfiles (line should be: eval "$(direnv hook zsh)")

# Authenticate once with Infisical (browser flow):
infisical login
```

#### Per-project (one-time)

```bash
cd ~/myproject
infisical init                 # binds project to an Infisical project + env

# Create .envrc that auto-imports secrets:
cat > .envrc <<'EOF'
eval $(infisical export --format=dotenv-export --silent)
EOF

direnv allow                   # confirm trust (security gate; runs once per file change)
```

Now when you `cd ~/myproject`, secrets are in the shell. `claude`, `codex`, `opencode` — all of them launched from inside the project see those env vars. **No per-command prefix.** When you `cd` out, secrets disappear from your shell.

Add `.envrc` to `.gitignore` if it contains anything project-specific you don't want shared (the Infisical pattern above is generic — only references `.infisical.json` which is safe to commit).

#### Why this is "more ergonomic"

| Ugly path | Ergonomic path |
|---|---|
| `infisical run -- claude` every time | `cd project; claude` |
| `infisical run -- npm run dev` | `cd project; npm run dev` |
| `.env` file readable by AI agent | Secrets in shell env, never on disk |

#### Do you need dev/staging/prod environments for a personal local machine?

**No.** Multi-environment is for teams where dev/staging/prod have different secret values that need to differ per environment. For personal local-only:

- One Infisical project, **one environment** named anything you want (`dev` is the default slug, just go with it). Don't add staging/prod unless you actually deploy somewhere that needs different values.
- For organizing across projects, use **Infisical folders** (`/personal/myapp`, `/personal/script-x`) — same environment, different paths.
- `.infisical.json`'s `defaultEnvironment` field means you never have to type `--env=dev`.

Self-hosting it on your tailnet (Docker container, ~5 min) gives you full control without the cloud free-tier limits. Once you have Tailscale up:

```yaml
# ~/infisical/docker-compose.yml — minimal solo setup
services:
  infisical:
    image: infisical/infisical:latest
    restart: unless-stopped
    ports: ["127.0.0.1:8080:8080"]
    env_file: .env
    depends_on: [db, redis]
  db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: infisical
      POSTGRES_PASSWORD: <generate>
      POSTGRES_DB: infisical
    volumes: ["./pgdata:/var/lib/postgresql/data"]
  redis:
    image: redis:7-alpine
    restart: unless-stopped
```

Then `export INFISICAL_API_URL=http://localhost:8080` and you're using your own instance. Same CLI, different backend.

### Infisical cold start — from zero to a working `.env` replacement

This is the exact recipe per Infisical's docs (https://infisical.com/docs/cli/usage). Do it once after Arch is up.

#### 1. Pick: cloud free tier vs self-host

| | Infisical Cloud (free) | Self-host on tailnet |
|---|---|---|
| Setup time | 2 minutes | 15 minutes |
| Cost | $0 (5 identity limit, fine for solo) | $0 |
| Trust surface | Infisical Inc. holds your encrypted vault | You hold everything |
| Backup burden | Theirs | Yours (`pgdump`) |

Start with cloud free. You can migrate to self-host later by exporting + re-importing — values are AES-256-GCM encrypted client-side either way, so the cloud never sees plaintext.

#### 2. Authenticate the CLI

```bash
infisical login          # opens browser to app.infisical.com, follow prompts
```

Creates a session cached at `~/.infisical/`. No further login needed until session expires (long).

#### 3. Create the project + folder structure (in the web UI)

For a solo personal user, **one project**, **one environment** (the default `dev` slug — keep it). Organize across projects using folders inside that one environment:

```
Personal (project)
└── dev (environment)
    ├── /myapp            DATABASE_URL, API_KEY, JWT_SECRET
    ├── /side-script      OPENAI_API_KEY
    ├── /homelab          GRAFANA_TOKEN, TAILSCALE_AUTH_KEY
    └── /shared           shared values you want to import into the others
```

The `/shared` folder is the trick for "API keys I reuse across personal projects": import it into each app folder via the web UI's "Add Import" button. Edit the value once, every project sees it.

#### 4. Migrate an existing `.env` file (cold start path)

Per Infisical's docs (https://infisical.com/docs/documentation/getting-started/cli):

```bash
cd ~/myproject               # whatever currently has a .env file
infisical init               # creates .infisical.json (safe to commit)
                             # asks which Infisical project + env to bind

# Push your existing .env values up to Infisical:
while IFS='=' read -r k v; do
  [[ -z "$k" || "$k" =~ ^# ]] && continue
  infisical secrets set "$k=$v" --env=dev --path=/myproject
done < .env

# Verify in the web UI that they all uploaded.

# Now wire direnv:
echo 'eval $(infisical export --format=dotenv-export --silent)' > .envrc
direnv allow

# Test:
cd ..
cd myproject                 # direnv loads → secrets in shell
# Verify variables are loaded WITHOUT echoing values (they may go to scrollback / shell history):
[[ -n "${DATABASE_URL:-}" ]] && echo "DATABASE_URL: set" || echo "DATABASE_URL: missing"
# For agent/tool launches that need secrets injected without leaving them in
# the parent shell, prefer:    infisical run -- <command>
# direnv-loaded values stay in the calling shell — fine for dev convenience,
# but those values can be leaked by anything else that inherits this shell's env.

# Once confirmed, DELETE the .env file. The plaintext is gone from disk.
git rm .env 2>/dev/null
echo .env >> .gitignore      # belt-and-suspenders
shred -u .env 2>/dev/null || rm -f .env
```

After this, the AI agent reading your project tree finds no `.env` — just `.envrc` (which contains a command, not values) and `.infisical.json` (a project ID, not secrets).

#### 5. The "store new keys safely" pattern

When you generate a new API key (OpenAI dashboard, GitHub PAT, etc.), the workflow is:

```bash
# Don't paste it into anything that touches disk. Pipe directly:
echo -n "sk-proj-abc123..." | infisical secrets set OPENAI_API_KEY --env=dev --path=/myapp --plain

# Or use the web UI's "Add Secret" → paste → save.
```

Per their docs, both paths use AES-256-GCM client-side encryption before the value leaves your machine. The secret never appears in `~/.bash_history` or shell logs if you use the `echo | pipe` form.

For a one-shot retrieval without exporting to a `.env`:
```bash
infisical secrets get OPENAI_API_KEY --env=dev --path=/myapp --plain --silent
```

#### 6. The "no reveal" guarantee

Infisical's docs explicitly cover the AI-context concern (https://infisical.com/blog/your-ai-coding-agent-is-reading-your-env-file):
- Secrets are AES-256-GCM encrypted at rest.
- The CLI fetches → decrypts in memory → injects as env vars → never writes to disk.
- The agent inherits env vars but **cannot read other processes' environments** without root.
- `printenv`/`env` from inside the agent's shell will show values **only for that process tree**.

If you want even tighter (block `printenv` from the agent's view), the [Phase CLI](https://docs.phase.dev/integrations/agents/opencode) wraps Infisical-style injection with explicit guardrails: blocks `printenv`/`env`/`export` inside `phase run` for AI agents specifically, redacts sealed secrets, has an "AI mode" that masks values to `[REDACTED]` even when the agent reads the variable name. Overkill for solo, useful if you're paranoid.

For automatic re-load when secrets change in the web UI:
```bash
infisical run --watch -- npm run dev    # restarts npm run dev when secret values change
```

(Don't use `--watch` in prod — only for local dev convenience.)

### Bifrost CLI — explained, since you asked

Bifrost (Maxim AI's open-source AI gateway) sits between your AI agents and the upstream LLM providers. Its concrete benefits **for you specifically**:

| Benefit | Why it matters for you |
|---|---|
| **One API key, all agents** | Your Anthropic key sits in Bifrost. Claude/Codex/OpenCode/Gemini all hit `localhost:bifrost`. No `ANTHROPIC_API_KEY` in 4 different config files. |
| **Swap agents mid-task** | End Claude session → press `h` → relaunch in Codex with the same MCP servers, same models, same context state. Useful when one agent stalls. |
| **Unified MCP** | Configure your MCP servers once in Bifrost; every agent it launches auto-attaches them. No `claude mcp add-json`/`opencode config edit`/etc. four times. |
| **Per-agent budget caps** | Cap how many tokens Claude can burn vs Codex. Useful when one agent goes runaway. |
| **Provider failover** | Anthropic API hiccup → routes the same request to OpenAI or Gemini. Don't need this for solo use, but it's there. |

**For your case**: if you mostly use Anthropic and configure MCP servers per-project anyway, Bifrost is overkill. If you're juggling all four agents weekly, Bifrost saves real configuration time.

**My honest read**: skip Bifrost initially. Start with `direnv + infisical` (which solves the actual ergonomic problem) and only add Bifrost if you find yourself reconfiguring MCP for each agent.

### "VeriDoc"

Couldn't find a secrets-management tool by that name in current research — closest hits were unrelated (medical docs platform). If you meant Doppler (the closed-source Infisical competitor), here's the comparison: **Doppler is more polished, faster setup, $6/user/mo, no self-host. Infisical is open-source, MIT-licensed, self-hostable, free for personal use.** For a single user on a personal machine self-hosting is genuinely fine — you want it. If you meant something else, name it again and I'll look.

### NO AI agent commit attribution — the universal kill switch

You disabled it in Claude's cloud settings. Good. **But there are known bugs** where Claude Code ignores the setting (issues #18253, #17429), and Codex/OpenCode have separate misbehaviors. The bulletproof solution is a **global git commit-msg hook** that strips bot attribution from every commit regardless of which tool produced it.

Set up automatically by `post-install.sh`. The hook lives at `~/.git-hooks/commit-msg`, hooks path is set globally, and it strips:
- `Co-Authored-By: Claude/Codex/OpenCode/Cursor/Copilot/Aider/...`
- `🤖 Generated with Claude Code`
- `Generated with opencode`
- Trailing blank lines after the strip

This runs on **every** commit (yours and theirs) and is idempotent — your normal commits are untouched because they don't have these lines.

#### Per-agent settings (do these too, in case the hook ever breaks)

**Claude Code** — set in BOTH global and project-local settings, **including the `$schema` field** (this is what makes the bug not bite):

```json
// ~/.claude/settings.json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

```json
// .claude/settings.json (per-project, same content)
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

The `$schema` field is what triggers proper config loading; without it, multiple users on 2.1.x reported the setting being silently ignored (issue #18253).

**Codex CLI** — has a separate problem: ships with a default `user.email = codex@example.com` which has been **claimed on a third-party GitHub account** (issue #18095, April 2026). That stranger's avatar shows up on your Vercel deploys if you don't override.

```bash
# Make sure your repos have user.email set BEFORE you run codex in them:
git config --global user.email "you@your-real-email"
git config --global user.name "Matas"
# Codex inherits these. Without them set, you leak attribution to a stranger.
```

**OpenCode** — has an `includeCoAuthoredBy` config option (issue #558, may or may not have shipped). Add this to `~/.config/opencode/opencode.json`:
```json
{ "includeCoAuthoredBy": false }
```
If it doesn't ship, the global commit-msg hook above catches it anyway.

#### Why no agent identity makes sense (you're right)

Tools don't get authored credit. Your IDE doesn't add `Co-Authored-By: VS Code`. `gofmt` doesn't add a trailer. A linter rewriting your code doesn't show up in `git log`. AI assistants are tools — the human running them is the author. Adding bot attribution makes commit history noisier and provides no real auditability (anyone can fake a Co-Authored-By trailer; it's not signed). The whole pattern is a marketing artifact of AI vendors wanting visibility. Strip it.

The only legit case for AI attribution is a regulated environment that requires it for compliance reasons. That's not personal projects.

### Ergonomic Bitwarden: rbw + rofi-rbw

Use the **`rbw`** unofficial CLI (Rust, fast, has its own daemon) plus **`rofi-rbw`** (271 ⭐, actively maintained, last release 2026-03, Wayland-first). Skip `bw`/`bwzy` for daily interactive use.

```bash
# Both installed by post-install.sh via AUR

# One-time rbw setup:
rbw config set email you@email.com
rbw login                            # prompts master password once, daemon caches it
rbw sync                             # pulls vault

# Bind in ~/.config/sway/config:
bindsym $mod+p exec rofi-rbw         # fuzzy-find, autofills via wtype on Wayland
bindsym $mod+Shift+p exec rofi-rbw --action copy   # copy instead of type
```

Why `rbw` over `bw`:
- `rbw` runs a small daemon (`rbw-agent`) that holds the vault decrypted in memory — same UX model as ssh-agent. No `BW_SESSION` shell-variable juggling.
- `rofi-rbw` is the most popular Bitwarden picker (271 ⭐ vs bwzy's 4), works in rofi/wofi/fuzzel/bemenu, autofills via `wtype`, supports TOTP and Wayland natively.
- `bw` (official) still useful for vault edits + scripts that need exact JSON output. Keep it installed (it's in your packages) but reach for `rbw` first.

For scripts:
```bash
rbw get github                       # password
rbw get -f username github           # username
rbw code github                      # TOTP code
```

## Phase 9.9 — Zoxide init order (your current bug)

Your current `~/.zshrc` initializes zoxide **before** starship. The zoxide doctor flags this because starship's `precmd` hook can shadow zoxide's directory tracking.

**Fix:** in your dotfiles `~/.zshrc`, move the zoxide init to the very last line of init code, after starship/atuin/mise:

```sh
# ... mise, fzf, atuin, starship, aliases ...

# zoxide — MUST be last so its hooks aren't shadowed
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
```

If you don't care, silence it instead: `export _ZO_DOCTOR=0`.

## Phase 10 — Verification

`./verify-system.sh` — non-destructive, run anytime. Reports:

- BIOS version, AGESA, motherboard
- UEFI mode, Secure Boot status
- amd-pstate driver active
- ReBAR enabled (by GPU prefetchable BAR size)
- Vulkan device + DRM driver
- NVMe scheduler
- swap state (zram + swapfile)
- snapper timer
- PipeWire/wireplumber running
- NetworkManager active, WiFi adapter, BT controller
- systemd-boot installed, UKIs present, ESP free space
- Sway version (need ≥ 1.12 for color)
- Sensors output
