#!/bin/bash
# Remove the automatic brightness installed by light/install.sh.
# Usage: ./light/uninstall.sh
set -uo pipefail

LIB_DIR="$HOME/.local/lib/omarchy-surface-light"
BIN_LINK="$HOME/.local/bin/omarchy-surface-light"
UNIT="$HOME/.config/systemd/user/omarchy-surface-light.service"
PLUGIN_ID=surface-touch.light
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONFIG_DIR="$HOME/.config/omarchy-surface-light"

((EUID != 0)) || {
	echo "ERROR: run this script as your user, not with sudo"
	exit 1
}

echo "== service"
systemctl --user disable --now omarchy-surface-light.service 2>/dev/null
rm -f "$UNIT"
systemctl --user daemon-reload

echo "== shell plugin"
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null
rm -rf "$PLUGIN_DIR"
omarchy-shell -q shell rescanPlugins

echo "== programs"
rm -rf "$LIB_DIR"
rm -f "$BIN_LINK"

echo
echo "done. Your settings are kept in $CONFIG_DIR/config.json (delete the folder to remove them)."
