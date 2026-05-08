#!/usr/bin/env bash
# sudo-indicator — waybar custom module.
#
# Reads /run/user/$UID/sudo-active maintained by pam_exec via
# /usr/local/bin/sudo-flag.sh. The flag is created on PAM open_session and
# REFRESHED (not deleted) on close_session, so its mtime tracks the most
# recent sudo invocation. A user-space TTL (default 300s = sudo's default
# cache lifetime) decides "active" vs "idle" — matches sudo's auth cache
# semantics rather than the per-command session lifetime.
#
# This avoids the race where `sudo true` opens and closes a PAM session in
# <100ms and waybar's polling never catches it.
#
# Override the TTL by setting SUDO_CACHE_SEC (e.g. if `Defaults timestamp_timeout=15`
# in /etc/sudoers, set SUDO_CACHE_SEC=900).
set -u

flag="/run/user/$(id -u)/sudo-active"
ttl=${SUDO_CACHE_SEC:-300}

if [[ -f "$flag" ]]; then
  mtime=$(stat -c %Y "$flag" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mtime ))
  if (( age < ttl )); then
    body=$(<"$flag")
    remaining=$(( ttl - age ))
    # Format remaining as Mm Ss
    rem_min=$(( remaining / 60 ))
    rem_sec=$(( remaining % 60 ))
    printf '{"text":"󰌾","alt":"active","class":"active","tooltip":"sudo cache active — ~%dm %ds remaining\\n%s"}\n' \
      "$rem_min" "$rem_sec" "$body"
    exit 0
  fi
fi
printf '{"text":"","alt":"idle","class":"idle","tooltip":"no active sudo session"}\n'
