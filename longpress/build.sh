#!/bin/bash
# Build the long-press plugin against the Hyprland installed right now.
# Usage: build.sh <output.so>
set -euo pipefail

HERE=$(dirname "$(readlink -f "$0")")
OUT=$(realpath -m "$1")

pkg-config --exists hyprland || {
	echo "hyprland headers not found (install the hyprland package)" >&2
	exit 1
}

mkdir -p "$(dirname "$OUT")"
# Hyprland passes C++ objects to plugins, so this has to be built with the same
# compiler and the same headers as the running compositor, and rebuilt when it updates
g++ -shared -fPIC --no-gnu-unique -std=c++26 -O2 -Wall \
	-DWLR_USE_UNSTABLE \
	$(pkg-config --cflags hyprland pixman-1 libdrm) \
	"$HERE/src/main.cpp" -o "$OUT"
echo "built $OUT for Hyprland $(pkg-config --modversion hyprland)"
