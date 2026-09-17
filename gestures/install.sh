#!/bin/bash
# Install the edge gestures for the current user (no sudo needed).
# Usage: ./gestures/install.sh [--dry-run]
set -uo pipefail

GESTURES_DIR=$(dirname "$(readlink -f "$0")")
PLUGIN_ID=surface-touch.gestures
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

DRY_RUN=0
case ${1:-} in
-n | --dry-run) DRY_RUN=1 ;;
"") ;;
*)
	echo "Usage: $0 [--dry-run]"
	exit 1
	;;
esac

say() { printf '\n== %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*"; }
die() {
	printf 'ERROR: %s\n' "$*"
	exit 1
}
run() {
	if ((DRY_RUN)); then
		printf '[dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

preflight() {
	say "checks"
	((EUID != 0)) || die "run this script as your user, not with sudo"
	[[ $(. /etc/os-release && echo "$ID") == omarchy ]] || die "this component needs Omarchy"
	command -v omarchy-shell >/dev/null || die "omarchy-shell not found"
	[[ -x $HOME/.local/bin/omarchy-surface-osk ]] ||
		warn "the on-screen keyboard is not installed: the bottom edge will have nothing to open"
	echo "ok"
}

install_plugin() {
	say "shell plugin (edge gestures)"
	run rm -rf "$PLUGIN_DIR"
	run mkdir -p "$PLUGIN_DIR"
	run cp "$GESTURES_DIR"/plugin/* "$PLUGIN_DIR/"
	run omarchy-shell shell rescanPlugins
	if ((!DRY_RUN)); then
		omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null ||
			omarchy plugin enable "$PLUGIN_ID" || warn "enable it with: omarchy plugin enable $PLUGIN_ID"
	fi
}

preflight
install_plugin

say "done"
cat <<EOF
Swipe up from the bottom edge: the on-screen keyboard opens or closes.
Swipe down from the top left corner: the Omarchy menu opens.
Swiping in from the left or right edge changes workspace, which is Hyprland's own
gesture: turn it on with gestures.workspace_swipe_touch in ~/.config/hypr/input.lua.
Remove the strips again with ./gestures/uninstall.sh
EOF
