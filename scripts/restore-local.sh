#!/usr/bin/env bash
set -euo pipefail
config_path="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
backup=$(mktemp "${config_path}.before-update-restore.XXXXXXXX")
cp -p "$config_path" "$backup"
# Disabling a clone brings back the built-in indicator it replaced.
omarchy plugin disable velunori.update || echo 'Disable IPC interrupted; restarting to apply the saved configuration.' >&2
omarchy restart shell
echo "Built-in Omarchy update indicator restored. Configuration backup: $backup"
