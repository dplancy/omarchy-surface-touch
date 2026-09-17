#!/bin/bash
# Install the on-screen keyboard for the current user (no sudo, except for missing packages).
# Usage: ./osk/install.sh [--dry-run]
set -uo pipefail

OSK_DIR=$(dirname "$(readlink -f "$0")")
LIB_DIR="$HOME/.local/lib/omarchy-surface-osk"
BIN_LINK="$HOME/.local/bin/omarchy-surface-osk"
UNIT_DIR="$HOME/.config/systemd/user"
PLUGIN_ID=surface-touch.osk
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
HYPR_FILE="$HOME/.config/hypr/surface-osk.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.surface-osk") -- omarchy-surface-touch on-screen keyboard'
CONFIG_DIR="$HOME/.config/omarchy-surface-osk"
CHROMIUM_FLAGS="$HOME/.config/chromium-flags.conf"
IME_FLAGS=(--enable-wayland-ime --wayland-text-input-version=3)
PACKAGES=(python-dbus python-gobject python-pyudev git make gcc pkgconf cairo pango libxkbcommon wayland)

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
	busctl --user introspect org.fcitx.Fcitx5 /virtualkeyboard >/dev/null 2>&1 ||
		die "fcitx5 is not running or has no virtual keyboard support (fcitx5 5.1 or newer is needed)"
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
	say "wvkbd keyboard (AZERTY/QWERTY build) and daemon"
	run "$OSK_DIR/wvkbd/build.sh" "$LIB_DIR/wvkbd-surface" || die "wvkbd build failed"
	run install -D -m755 "$OSK_DIR/bin/omarchy-surface-osk" "$LIB_DIR/omarchy-surface-osk" || die "cannot install the daemon"
	run mkdir -p "$(dirname "$BIN_LINK")"
	run ln -sf "$LIB_DIR/omarchy-surface-osk" "$BIN_LINK"
}

install_service() {
	say "user service"
	run install -D -m644 "$OSK_DIR/files/omarchy-surface-osk.service" "$UNIT_DIR/omarchy-surface-osk.service" || die "cannot install the service"
	run systemctl --user daemon-reload
	run systemctl --user enable omarchy-surface-osk.service
	run systemctl --user restart omarchy-surface-osk.service || die "the service did not start: journalctl --user -u omarchy-surface-osk"
}

install_plugin() {
	say "shell plugin (keyboard icon and bar button)"
	run rm -rf "$PLUGIN_DIR"
	run mkdir -p "$PLUGIN_DIR"
	run cp "$OSK_DIR"/plugin/* "$PLUGIN_DIR/"
	run omarchy-shell shell rescanPlugins
	if ((!DRY_RUN)); then
		omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null ||
			omarchy plugin enable "$PLUGIN_ID" || warn "enable it with: omarchy plugin enable $PLUGIN_ID"
	fi
}

install_hyprland_rule() {
	say "Hyprland: keyboard usable on the lock screen"
	run install -D -m644 "$OSK_DIR/files/surface-osk.lua" "$HYPR_FILE" || die "cannot install $HYPR_FILE"
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
	fi
}

install_chromium_flags() {
	say "Chromium: report text fields to fcitx5"
	if [[ ! -f $CHROMIUM_FLAGS ]]; then
		echo "no $CHROMIUM_FLAGS, skipped"
		return
	fi
	local flag added=()
	for flag in "${IME_FLAGS[@]}"; do
		grep -q -- "^$flag\$" "$CHROMIUM_FLAGS" && continue
		((DRY_RUN)) || echo "$flag" >>"$CHROMIUM_FLAGS"
		added+=("$flag")
	done
	if ((${#added[@]})); then
		echo "added: ${added[*]} (restart Chromium to apply)"
		# remember what we added, so uninstall removes only that
		((DRY_RUN)) || { mkdir -p "$CONFIG_DIR" && printf '%s\n' "${added[@]}" >>"$CONFIG_DIR/added-chromium-flags"; }
	else
		echo "already set"
	fi
}

preflight
install_packages
install_programs
install_service
install_plugin
install_hyprland_rule
install_chromium_flags

say "done"
cat <<EOF
Detach the Type Cover and tap a text field: a keyboard icon appears bottom right.
  tap: open or close the keyboard     press and hold: switch AZERTY / QWERTY
The bar also shows a keyboard button while no physical keyboard is attached.
Status: omarchy-surface-osk status     Logs: journalctl --user -u omarchy-surface-osk
EOF
