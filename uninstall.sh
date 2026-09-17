#!/bin/bash
# Remove what install.sh added. iptsd and the linux-surface repository are kept.
# Usage: sudo ./uninstall.sh [--dry-run]
set -uo pipefail

SURFACE_KEY_FPR=87DEFA4AB94A99A4C8C3112556C464BAAC421453
OMARCHY_HOOK=.config/omarchy/hooks/pre-refresh-pacman.d/linux-surface-repo
DRY_RUN=0

case ${1:-} in
-n | --dry-run) DRY_RUN=1 ;;
"") ;;
*)
	echo "Usage: sudo $0 [--dry-run]"
	exit 1
	;;
esac

run() {
	if ((DRY_RUN)); then
		printf '[dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

((DRY_RUN)) || ((EUID == 0)) || {
	echo "ERROR: run this script with sudo"
	exit 1
}

echo "== ipts DKMS module"
for version in $(dkms status -m ipts 2>/dev/null | sed -n 's|^ipts/\([^,:]*\).*|\1|p' | sort -u); do
	run dkms remove "ipts/$version" --all
	run rm -rf "/usr/src/ipts-$version"
done

echo "== IOMMU hook"
run rm -f /etc/modprobe.d/ipts-iommu.conf /usr/local/sbin/ipts-iommu-passthrough

if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
	echo "== Omarchy hook"
	run rm -f "$(getent passwd "$SUDO_USER" | cut -d: -f6)/$OMARCHY_HOOK"
fi

cat <<EOF

== done, reboot to unload the driver

iptsd and the linux-surface repository were left in place. To remove them too:
  sudo pacman -Rns iptsd
  remove the [linux-surface] section from /etc/pacman.conf
  sudo pacman-key --delete $SURFACE_KEY_FPR
EOF
