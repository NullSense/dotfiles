# Secrets management

Never commit secrets to this repo. Use ONE of these strategies.

## Strategy 1: plain `~/.secrets` (simplest)

```bash
# ~/.secrets — gitignored, NOT in chezmoi source
export GOOGLE_PLACES_API_KEY="..."
export ELEVENLABS_API_KEY="..."
export BWS_ACCESS_TOKEN="..."
export BRAVE_API_KEY="..."
```

`.zshrc` already does `[[ -f ~/.secrets ]] && source ~/.secrets`.
File must be `chmod 600 ~/.secrets` and explicitly never tracked.

## Strategy 2: Infisical (recommended if team uses it)

```bash
# install
curl -1sLf 'https://artifacts-cli.infisical.com/setup.sh' | sudo -E bash
sudo pacman -S infisical-cli  # if available

# login + link project
infisical login
infisical init

# usage in zshrc (already present, just uncomment)
eval "$(infisical export --format=dotenv-export)"

# per-project run
infisical run -- npm run dev
```

## Strategy 3: Bitwarden Secrets Manager

```bash
# install bws CLI
sudo pacman -S bitwarden-secrets-manager-cli  # AUR

# usage (uncomment in zshrc)
export BWS_ACCESS_TOKEN="..."  # from a service account
eval "$(bws secret list --output env)"
```

## Strategy 4: chezmoi templates + age

```bash
chezmoi add --encrypt ~/.secrets   # encrypts via age, commits encrypted blob
chezmoi apply                       # decrypts on this machine using local age key
```

Best for machine-specific stuff that needs to survive reinstall.

## Recovery checklist after a leak

1. **Rotate every leaked key** (cannot be skipped)
2. Move replacements to chosen strategy above
3. `git filter-repo --path .zshrc --invert-paths` (or BFG) to scrub history
4. Force-push: `git push --force-with-lease`
5. GitHub → Settings → Security → Audit log: confirm no unexpected access
