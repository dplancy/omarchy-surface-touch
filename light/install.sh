#!/bin/bash
# Install automatic brightness for the current user (no sudo, except for missing packages).
# Usage: ./light/install.sh [--dry-run]
set -uo pipefail

LIGHT_DIR=$(dirname "$(readlink -f "$0")")
LIB_DIR="$HOME/.local/lib/omarchy-surface-light"
BIN_LINK="$HOME/.local/bin/omarchy-surface-light"
UNIT_DIR="$HOME/.config/systemd/user"
PLUGIN_ID=surface-touch.light
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
PACKAGES=(python-dbus python-gobject brightnessctl)

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
	if ! grep -qxs als /sys/bus/iio/devices/*/name; then
		warn "no als light sensor found: the service will install, but nothing will follow"
	fi
	[[ -n $(ls -A /sys/class/backlight 2>/dev/null) ]] || warn "no backlight found in /sys/class/backlight"
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
	run install -D -m755 "$LIGHT_DIR/bin/omarchy-surface-light" "$LIB_DIR/omarchy-surface-light" || die "cannot install the daemon"
	run mkdir -p "$(dirname "$BIN_LINK")"
	run ln -sf "$LIB_DIR/omarchy-surface-light" "$BIN_LINK"
}

install_service() {
	say "user service"
	run install -D -m644 "$LIGHT_DIR/files/omarchy-surface-light.service" "$UNIT_DIR/omarchy-surface-light.service" || die "cannot install the service"
	run systemctl --user daemon-reload
	run systemctl --user enable omarchy-surface-light.service
	run systemctl --user restart omarchy-surface-light.service || die "the service did not start: journalctl --user -u omarchy-surface-light"
}

install_plugin() {
	say "shell plugin (brightness button)"
	run rm -rf "$PLUGIN_DIR"
	run mkdir -p "$PLUGIN_DIR"
	run cp "$LIGHT_DIR"/plugin/* "$PLUGIN_DIR/"
	run omarchy-shell shell rescanPlugins
	if ((!DRY_RUN)); then
		omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null ||
			omarchy plugin enable "$PLUGIN_ID" || warn "enable it with: omarchy plugin enable $PLUGIN_ID"
	fi
}

preflight
install_packages
install_programs
install_service
install_plugin

say "done"
cat <<EOF
The brightness now follows the light around you.
Setting it by hand wins, until the light really changes; the bar button turns the
whole thing off and on.
Status: omarchy-surface-light status   Sensor: omarchy-surface-light sensor
Tuning: ~/.config/omarchy-surface-light/config.json (curve, bias)
Logs: journalctl --user -u omarchy-surface-light
EOF
