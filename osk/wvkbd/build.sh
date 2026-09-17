#!/bin/bash
# Build wvkbd with the "surface" layout set (AZERTY + QWERTY + symbols), patched to show
# the Shift and AltGr characters of each key.
# Usage: build.sh <output-binary>
set -euo pipefail

WVKBD_REPO=https://github.com/jjsullivan5196/wvkbd.git
WVKBD_TAG=v0.20

HERE=$(dirname "$(readlink -f "$0")")
OUT=$(realpath -m "$1")
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$WVKBD_TAG" "$WVKBD_REPO" "$BUILD/wvkbd"
git -C "$BUILD/wvkbd" apply "$HERE"/wvkbd-surface.patch
cp "$HERE"/config.surface.h "$HERE"/layout.surface.h "$HERE"/keymap.surface.h "$BUILD/wvkbd/"
make -C "$BUILD/wvkbd" --no-print-directory LAYOUT=surface wvkbd-surface >"$BUILD/make.log" 2>&1 || {
	cat "$BUILD/make.log"
	exit 1
}
install -D -m755 "$BUILD/wvkbd/wvkbd-surface" "$OUT"
