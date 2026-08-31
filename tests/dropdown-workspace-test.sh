#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/home/.config/hypr/windows.conf"

dropdown_class='com.mitchellh.ghostty-dropdown'
dropdown_class_regex='com\.mitchellh\.ghostty-dropdown'
escape_rule="windowrule = workspace m+0 silent, match:workspace special:dropdown, match:class negative:$dropdown_class_regex"

grep -Fqx "windowrule = workspace special:dropdown silent, match:class $dropdown_class" "$config"

if ! grep -Fqx "$escape_rule" "$config"; then
    printf 'FAIL: windows opened over the dropdown must escape to its underlying normal workspace\n' >&2
    exit 1
fi

printf 'PASS: dropdown child workspace routing\n'
