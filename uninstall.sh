#!/usr/bin/env bash
set -euo pipefail

plugin_id="user.omarchy-notion"
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id"

for command_path in "$HOME/.local/bin/notion" "$HOME/.local/bin/omarchy-notion"; do
  if [[ -L $command_path && $(readlink -f "$command_path") == "$plugin_dir/omarchy-notion" ]]; then
    rm -- "$command_path"
  fi
done

if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
  omarchy plugin remove "$plugin_id" --yes
fi

printf '%s\n' 'Removed the plugin and CLI links.'
printf '%s\n' 'Your local configuration and keyring token were left intact.'
printf '%s\n' 'Delete them manually only if desired: ~/.config/omarchy-notion'
