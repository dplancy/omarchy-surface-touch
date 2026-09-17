#!/bin/bash
# Install the Surface IPTS touchscreen driver for Omarchy's linux-omarchy kernel.
# Usage: sudo ./install.sh [--yes] [--force] [--dry-run]
set -uo pipefail

REPO_DIR=$(dirname "$(readlink -f "$0")")
VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$REPO_DIR/src/ipts/dkms.conf")
LOG="$REPO_DIR/install.log"

# MEI controllers used by IPTS (Surface Pro 4/5/6, Surface Book 1/2, Surface Laptop 1/2)
IPTS_IDS="0x8086:0x9d3e"

SURFACE_KEY_URL=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
SURFACE_KEY_FPR=87DEFA4AB94A99A4C8C3112556C464BAAC421453
SURFACE_REPO_SERVER=https://pkg.surfacelinux.com/arch/
OMARCHY_HOOK=.config/omarchy/hooks/pre-refresh-pacman.d/linux-surface-repo

ASSUME_YES=0
FORCE=0
DRY_RUN=0
KVER=

usage() {
	cat <<EOF
Usage: sudo $0 [options]

  -y, --yes      do not ask for confirmation (also passed to pacman)
  -f, --force    install even if no supported touch controller is detected
  -n, --dry-run  show what would be done without changing anything
  -h, --help     show this help
EOF
}

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

confirm() {
	((ASSUME_YES)) && return 0
	local answer
	read -r -p "$1 [y/N] " answer
	[[ $answer == [yY]* ]]
}

pacman_install() {
	local opts=(--needed)
	((ASSUME_YES)) && opts+=(--noconfirm)
	run pacman "$@" "${opts[@]}"
}

find_ipts_controller() {
	local dev id
	for dev in /sys/bus/pci/devices/*; do
		id="$(cat "$dev/vendor"):$(cat "$dev/device")"
		[[ " $IPTS_IDS " == *" $id "* ]] && echo "${dev##*/} ($id)" && return 0
	done
	return 1
}

secure_boot_enabled() {
	local var=(/sys/firmware/efi/efivars/SecureBoot-*)
	[[ -r ${var[0]} ]] && [[ $(od -An -t u1 "${var[0]}" | awk '{print $NF}') == 1 ]]
}

preflight() {
	say "checks"

	((DRY_RUN)) || ((EUID == 0)) || die "run this script with sudo"
	[[ -n $VERSION ]] || die "cannot read PACKAGE_VERSION from src/ipts/dkms.conf"
	command -v pacman >/dev/null || die "pacman not found, this installer targets Omarchy (Arch Linux)"

	local os_id
	os_id=$(. /etc/os-release && echo "$ID")
	if [[ $os_id != omarchy ]]; then
		warn "this system is '$os_id', not Omarchy"
		((FORCE)) || die "use --force to install anyway"
	fi

	local controller
	if controller=$(find_ipts_controller); then
		echo "touch controller: $controller"
	else
		warn "no supported IPTS touch controller found (expected PCI ID $IPTS_IDS)"
		((FORCE)) || die "this device is not supported, use --force to install anyway"
	fi

	pacman -Q linux-omarchy >/dev/null 2>&1 || die "the linux-omarchy kernel is not installed"
	KVER=$(pacman -Ql linux-omarchy | awk -F/ '$NF == "vmlinuz" {print $(NF-1); exit}')
	[[ -n $KVER ]] || die "cannot find the linux-omarchy kernel version"
	echo "kernel: $KVER (running: $(uname -r))"

	local builtin
	builtin=$(modinfo -k "$KVER" -n ipts 2>/dev/null)
	if [[ -n $builtin && $builtin != */updates/dkms/* ]]; then
		warn "$KVER already ships an ipts driver ($builtin)"
		((FORCE)) || die "nothing to do, use --force to install anyway"
	fi

	if secure_boot_enabled; then
		warn "Secure Boot is enabled: the DKMS module only loads if its signing key is enrolled"
		confirm "Continue?" || exit 1
	fi
}

install_packages() {
	say "packages: dkms, kernel headers, libinput-tools"
	pacman_install -S dkms linux-omarchy-headers libinput-tools || die "package installation failed"

	if ((!DRY_RUN)) && [[ ! -d /usr/lib/modules/$KVER/build ]]; then
		die "no headers for $KVER (linux-omarchy and linux-omarchy-headers versions differ?), run 'sudo pacman -Syu', reboot and try again"
	fi
}

add_surface_repo() {
	local tmp fpr
	tmp=$(mktemp -d) || die "mktemp failed"

	echo "downloading the linux-surface signing key"
	curl -fsSL "$SURFACE_KEY_URL" -o "$tmp/surface.asc" || die "cannot download $SURFACE_KEY_URL"
	fpr=$(gpg --homedir "$tmp" --batch --with-colons --import-options show-only --import "$tmp/surface.asc" 2>/dev/null |
		awk -F: '$1 == "pub" {p = 1} $1 == "fpr" && p {print $10; p = 0}')
	[[ $fpr == "$SURFACE_KEY_FPR" ]] || die "unexpected key fingerprint '$fpr', expected $SURFACE_KEY_FPR"
	echo "key fingerprint verified: $fpr"

	run pacman-key --add "$tmp/surface.asc" || die "pacman-key --add failed"
	run pacman-key --lsign-key "$SURFACE_KEY_FPR" || die "pacman-key --lsign-key failed"
	rm -rf "$tmp"

	if ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
		echo "adding [linux-surface] to /etc/pacman.conf"
		((DRY_RUN)) || printf '\n[linux-surface]\nServer = %s\n' "$SURFACE_REPO_SERVER" >>/etc/pacman.conf
	fi
}

install_omarchy_hook() {
	local user=${SUDO_USER:-}
	if [[ -z $user || $user == root ]]; then
		warn "not run through sudo, skipping the Omarchy hook that keeps the linux-surface repository"
		return
	fi

	local home
	home=$(getent passwd "$user" | cut -d: -f6)
	echo "Omarchy hook: $home/$OMARCHY_HOOK"
	run sudo -u "$user" install -D -m644 "$REPO_DIR/files/linux-surface-repo.hook" "$home/$OMARCHY_HOOK" ||
		warn "cannot install the Omarchy hook"
}

install_iptsd() {
	say "iptsd (touch processing daemon, from the linux-surface repository)"

	if pacman -Q iptsd >/dev/null 2>&1; then
		echo "already installed: $(pacman -Q iptsd)"
	elif pacman -Si iptsd >/dev/null 2>&1; then
		pacman_install -S iptsd || die "iptsd installation failed"
	else
		echo "iptsd is not in your repositories. It is provided by linux-surface:"
		echo "  $SURFACE_REPO_SERVER (key $SURFACE_KEY_FPR)"
		echo "Only iptsd is installed from it, your kernel stays linux-omarchy."
		confirm "Add the linux-surface repository?" || die "iptsd is required for touch input"
		add_surface_repo
		# Full upgrade after adding a repository, partial upgrades are unsupported on Arch
		pacman_install -Syu iptsd || die "iptsd installation failed"
	fi

	# omarchy refresh pacman rewrites /etc/pacman.conf and would drop the repository
	grep -q '^\[linux-surface\]' /etc/pacman.conf && install_omarchy_hook
}

install_module() {
	say "ipts kernel module (DKMS $VERSION)"

	local old olds
	olds=$(dkms status -m ipts 2>/dev/null | sed -n 's|^ipts/\([^,:]*\).*|\1|p' | sort -u)

	# reinstalling the same version: start from a clean copy
	if grep -qxF "$VERSION" <<<"$olds"; then
		run dkms remove "ipts/$VERSION" --all
	fi
	run rm -rf "/usr/src/ipts-$VERSION"
	run install -d "/usr/src/ipts-$VERSION" || die "cannot create /usr/src/ipts-$VERSION"
	run install -m644 "$REPO_DIR"/src/ipts/* "/usr/src/ipts-$VERSION/" || die "cannot copy the sources"
	run dkms add "ipts/$VERSION" || die "dkms add failed"

	# build first, so a failed build leaves a previously working version in place
	if ! run dkms build "ipts/$VERSION" -k "$KVER"; then
		die "build failed, see /var/lib/dkms/ipts/$VERSION/build/make.log"
	fi

	for old in $olds; do
		[[ $old == "$VERSION" ]] && continue
		echo "removing previous DKMS version ipts/$old"
		run dkms remove "ipts/$old" --all
		run rm -rf "/usr/src/ipts-$old"
	done

	run dkms install "ipts/$VERSION" -k "$KVER" || die "dkms install failed"

	((DRY_RUN)) || echo "module used by modprobe: $(modinfo -k "$KVER" -n ipts)"
}

install_iommu_hook() {
	say "IOMMU passthrough for the touch controller"

	local other
	other=$(grep -hs '^install mei_me' /etc/modprobe.d/*.conf /usr/lib/modprobe.d/*.conf |
		grep -v ipts-iommu-passthrough)
	[[ -n $other ]] && warn "another 'install mei_me' rule exists and may override this one: $other"

	run install -m755 "$REPO_DIR/files/ipts-iommu-passthrough" /usr/local/sbin/ipts-iommu-passthrough ||
		die "cannot install /usr/local/sbin/ipts-iommu-passthrough"
	run install -m644 "$REPO_DIR/files/ipts-iommu.conf" /etc/modprobe.d/ipts-iommu.conf ||
		die "cannot install /etc/modprobe.d/ipts-iommu.conf"
}

check_initramfs() {
	say "initramfs check (the IOMMU hook cannot run if mei_me is loaded from the initramfs)"

	local img contents checked=0 found=0
	while IFS= read -r img; do
		contents=$(lsinitcpio "$img" 2>/dev/null) || continue
		checked=$((checked + 1))
		if grep -qE '/mei[-_]me\.ko' <<<"$contents"; then
			warn "mei_me is in $img, remove it from MODULES in /etc/mkinitcpio.conf and rebuild"
			found=1
		fi
	done < <(find /boot /efi -type f \( -iname '*initramfs*' -o -iname '*.efi' \) 2>/dev/null)

	if ((checked == 0)); then
		warn "no initramfs image could be read, check manually that mei_me is not in it"
	elif ((!found)); then
		echo "ok ($checked images checked)"
	fi
}

main() {
	preflight
	install_packages
	install_iptsd
	install_module
	install_iommu_hook
	check_initramfs

	say "done"
	echo "Reboot into linux-omarchy, then check touch input with:"
	echo "  sudo $REPO_DIR/verify.sh"
}

while (($#)); do
	case $1 in
	-y | --yes) ASSUME_YES=1 ;;
	-f | --force) FORCE=1 ;;
	-n | --dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage
		exit 1
		;;
	esac
	shift
done

if ((DRY_RUN)); then
	main
else
	main 2>&1 | tee "$LOG"
	status=${PIPESTATUS[0]}
	[[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER:" "$LOG" 2>/dev/null
	exit "$status"
fi
