#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/mpweaver/omarchy-notion"
plugin_id="user.omarchy-notion"
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id"

command -v omarchy >/dev/null 2>&1 || {
  echo "This plugin requires Omarchy." >&2
  exit 1
}

echo "Installing required packages..."
omarchy pkg add curl jq libsecret wl-clipboard

if ! omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then
  omarchy plugin add "$repo_url" --enable --yes
else
  echo "$plugin_id is already installed"
fi

[[ -f $plugin_dir/manifest.json ]] || {
  echo "The plugin was not found at $plugin_dir" >&2
  exit 1
}

mkdir -p "$HOME/.local/bin"
ln -sfn "$plugin_dir/omarchy-notion" "$HOME/.local/bin/omarchy-notion"
ln -sfn "$plugin_dir/omarchy-notion" "$HOME/.local/bin/notion"
chmod +x "$plugin_dir/omarchy-notion" "$plugin_dir/install.sh" "$plugin_dir/uninstall.sh"

omarchy-shell shell rescanPlugins || true
omarchy bar move "$plugin_id" --section right
echo "Omarchy Notion installed. Run: notion setup"
