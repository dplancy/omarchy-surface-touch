#!/bin/bash
# Remove the edge gestures installed by gestures/install.sh.
# Usage: ./gestures/uninstall.sh
set -uo pipefail

PLUGIN_ID=surface-touch.gestures
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

((EUID != 0)) || {
	echo "ERROR: run this script as your user, not with sudo"
	exit 1
}

echo "== shell plugin"
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null
rm -rf "$PLUGIN_DIR"
omarchy-shell -q shell rescanPlugins

echo
echo "done."
