#!/bin/bash
# Install the long-press-to-right-click Hyprland plugin for the current user
# (no sudo, except for missing packages).
# Usage: ./longpress/install.sh [--dry-run]
set -uo pipefail

LONGPRESS_DIR=$(dirname "$(readlink -f "$0")")
LIB_DIR="$HOME/.local/lib/omarchy-surface-longpress"
SO="$LIB_DIR/longpress.so"
HOOK_DIR="$HOME/.config/omarchy/hooks/post-update.d"
HYPR_FILE="$HOME/.config/hypr/surface-longpress.lua"
HYPR_MAIN="$HOME/.config/hypr/hyprland.lua"
HYPR_REQUIRE='require("hypr.surface-longpress") -- omarchy-surface-touch long press'
PACKAGES=(gcc pkgconf hyprland)

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
	pkg-config --exists hyprland || die "Hyprland headers not found (pacman -S hyprland)"
	command -v g++ >/dev/null || die "g++ not found (pacman -S gcc)"
	echo "Hyprland $(pkg-config --modversion hyprland), g++ $(g++ -dumpversion)"
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

install_plugin() {
	say "plugin (built here, against the Hyprland you are running)"
	# the sources stay next to the build, so the post-update hook can rebuild it
	run rm -rf "$LIB_DIR/src"
	run install -D -m644 "$LONGPRESS_DIR/src/main.cpp" "$LIB_DIR/src/main.cpp"
	run install -D -m755 "$LONGPRESS_DIR/build.sh" "$LIB_DIR/build.sh"
	run install -D -m755 "$LONGPRESS_DIR/files/rebuild" "$LIB_DIR/rebuild"
	run "$LIB_DIR/build.sh" "$SO" || die "the plugin did not build"
}

install_hook() {
	say "rebuild after every Omarchy update"
	# a plugin only loads into the exact Hyprland build it was compiled against
	run install -D -m755 "$LONGPRESS_DIR/files/rebuild" "$HOOK_DIR/omarchy-surface-longpress"
}

install_hyprland_rule() {
	say "Hyprland: load the plugin at startup"
	run install -D -m644 "$LONGPRESS_DIR/files/surface-longpress.lua" "$HYPR_FILE" || die "cannot install $HYPR_FILE"
	[[ -f $HYPR_MAIN ]] || die "$HYPR_MAIN not found, is this an Omarchy Hyprland setup?"
	if ! grep -qxF "$HYPR_REQUIRE" "$HYPR_MAIN"; then
		((DRY_RUN)) || printf '\n%s\n' "$HYPR_REQUIRE" >>"$HYPR_MAIN"
		echo "added to $HYPR_MAIN: $HYPR_REQUIRE"
	fi
}

preflight
install_packages
install_plugin
install_hook
install_hyprland_rule

say "done"
cat <<EOF
Load it into the session you are in right now with:
  hyprctl plugin load $SO
or just log out and back in. A plugin runs inside the compositor, so try a long
press on something harmless first.
Remove it again with ./longpress/uninstall.sh
EOF
