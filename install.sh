#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=${1:---install}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_root=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups/$stamp
changed=0
backed_up=0

case "$mode" in
    --install|--check|--uninstall) ;;
    *) echo "usage: $0 [--install|--check|--uninstall]" >&2; exit 2 ;;
esac

while IFS= read -r -d '' tracked; do
    rel=${tracked#home/}
    source=$repo/$tracked
    target=$HOME/$rel

    if [[ "$mode" == --check ]]; then
        if [[ ! -L "$target" || $(readlink "$target") != "$source" ]]; then
            printf 'not linked: %s\n' "$target"
            changed=1
        fi
        continue
    fi

    if [[ "$mode" == --uninstall ]]; then
        if [[ -L "$target" && $(readlink "$target") == "$source" ]]; then
            rm -- "$target"
            printf 'unlinked: %s\n' "$target"
        fi
        continue
    fi

    mkdir -p "$(dirname "$target")"
    if [[ -L "$target" && $(readlink "$target") == "$source" ]]; then
        continue
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -f "$source" && -f "$target" ]] && cmp -s -- "$source" "$target"; then
            rm -- "$target"
        elif [[ -L "$source" && -L "$target" ]] && [[ $(readlink "$source") == $(readlink "$target") ]]; then
            rm -- "$target"
        else
            backup=$backup_root/$rel
            mkdir -p "$(dirname "$backup")"
            mv -- "$target" "$backup"
            backed_up=1
            printf 'backed up: %s -> %s\n' "$target" "$backup"
        fi
    fi

    ln -s -- "$source" "$target"
    printf 'linked: %s\n' "$target"
done < <(git -C "$repo" ls-files -z 'home/**')

if [[ "$mode" == --check ]]; then
    (( changed == 0 )) || exit 1
    echo 'all tracked dotfiles are linked'
elif [[ "$mode" == --install && $backed_up == 1 ]]; then
    printf 'pre-existing files were preserved under %s\n' "$backup_root"
fi
