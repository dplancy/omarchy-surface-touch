#!/bin/bash
# Install automatic screen rotation for the current user (no sudo, except for missing packages).
# Usage: ./rotate/install.sh [--dry-run]
set -uo pipefail

ROTATE_DIR=$(dirname "$(readlink -f "$0")")
LIB_DIR="$HOME/.local/lib/omarchy-surface-rotate"
BIN_LINK="$HOME/.local/bin/omarchy-surface-rotate"
UNIT_DIR="$HOME/.config/systemd/user"
PLUGIN_ID=surface-touch.rotate
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
HYPR_FILE="$HOME/.config/hypr/surface-rotate.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.surface-rotate") -- omarchy-surface-touch screen rotation'
PACKAGES=(python-dbus python-gobject python-pyudev)

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
# remove an exact line from a file, keeping the file itself (and its permissions)
remove_line() {
	local tmp
	tmp=$(mktemp) && grep -vxF -- "$1" "$2" >"$tmp"
	cat "$tmp" >"$2" && rm -f "$tmp"
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
	command -v hyprctl >/dev/null || die "hyprctl not found"
	if ! grep -qxs accel_3d /sys/bus/iio/devices/*/name; then
		warn "no accel_3d sensor found: the service will install, but nothing will rotate"
	fi
	echo "ok"
}

install_packages() {
	say "packages"
	local missing
	missing=$(pacman -T "${PACKAGES[@]}")
	if [[ -z $missing ]]; then
		echo "all present"
	else
		echo "missing: $missing"
		# shellcheck disable=SC2086
		run sudo pacman -S --needed $missing || die "package installation failed"
	fi
}

install_programs() {
	say "daemon"
	run install -D -m755 "$ROTATE_DIR/bin/omarchy-surface-rotate" "$LIB_DIR/omarchy-surface-rotate" || die "cannot install the daemon"
	run mkdir -p "$(dirname "$BIN_LINK")"
	run ln -sf "$LIB_DIR/omarchy-surface-rotate" "$BIN_LINK"
}

install_service() {
	say "user service"
	run install -D -m644 "$ROTATE_DIR/files/omarchy-surface-rotate.service" "$UNIT_DIR/omarchy-surface-rotate.service" || die "cannot install the service"
	run systemctl --user daemon-reload
	run systemctl --user enable omarchy-surface-rotate.service
	run systemctl --user restart omarchy-surface-rotate.service || die "the service did not start: journalctl --user -u omarchy-surface-rotate"
}

install_plugin() {
	say "shell plugin (rotation button)"
	run rm -rf "$PLUGIN_DIR"
	run mkdir -p "$PLUGIN_DIR"
	run cp "$ROTATE_DIR"/plugin/* "$PLUGIN_DIR/"
	run omarchy-shell shell rescanPlugins
	if ((!DRY_RUN)); then
		omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null ||
			omarchy plugin enable "$PLUGIN_ID" || warn "enable it with: omarchy plugin enable $PLUGIN_ID"
	fi
}

install_hyprland_rule() {
	say "Hyprland: file holding the current rotation"
	# the daemon rewrites this file; it starts as "no rotation"
	run mkdir -p "$(dirname "$HYPR_FILE")"
	if ((!DRY_RUN)) && [[ ! -f $HYPR_FILE ]]; then
		cat >"$HYPR_FILE" <<-LUA || die "cannot write $HYPR_FILE"
			-- omarchy-surface-touch: current screen rotation, rewritten by omarchy-surface-rotate
			hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto", transform = 0 })
		LUA
	fi
	[[ -f $HYPR_MAIN ]] || die "$HYPR_MAIN not found, is this an Omarchy Hyprland setup?"
	if ! grep -qxF "$HYPR_REQUIRE" "$HYPR_MAIN"; then
		((DRY_RUN)) || printf '\n%s\n' "$HYPR_REQUIRE" >>"$HYPR_MAIN"
		echo "added to $HYPR_MAIN: $HYPR_REQUIRE"
	fi
	((DRY_RUN)) && return
	hyprctl reload config-only >/dev/null
	local errors
	errors=$(hyprctl configerrors)
	if [[ -n ${errors//[[:space:]]/} ]]; then
		warn "Hyprland reports config errors, removing the rule again:"
		echo "$errors"
		remove_line "$HYPR_REQUIRE" "$HYPR_MAIN"
		rm -f "$HYPR_FILE"
		hyprctl reload config-only >/dev/null
		die "rotation cannot be applied on this configuration"
	fi
}

preflight
install_packages
install_programs
install_hyprland_rule
install_service
install_plugin

say "done"
cat <<EOF
Detach the Type Cover and turn the tablet: the screen follows.
The bar button locks the rotation (and turns it on again with the keyboard attached);
right click on it goes back to landscape.
Status: omarchy-surface-rotate status   Sensor: omarchy-surface-rotate sensor
Logs: journalctl --user -u omarchy-surface-rotate
EOF
