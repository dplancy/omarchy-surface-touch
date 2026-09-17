#!/bin/bash
# Check the IPTS touchscreen after rebooting into linux-omarchy, then record a few gestures.
# Usage: sudo ./verify.sh [--no-gestures]
set -u

REPO_DIR=$(dirname "$(readlink -f "$0")")
IPTS_IDS="0x8086:0x9d3e"
GESTURES=1

case ${1:-} in
--no-gestures) GESTURES=0 ;;
"") ;;
*)
	echo "Usage: sudo $0 [--no-gestures]"
	exit 1
	;;
esac

((EUID == 0)) || {
	echo "ERROR: run this script with sudo (dmesg and input devices need root)"
	exit 1
}

STAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$REPO_DIR/logs"
LOG="$LOG_DIR/verify-$STAMP.log"
RAW="$LOG_DIR/verify-$STAMP-events.log"
FAILED=0

pass() { printf '  ok    %s\n' "$*"; }
fail() {
	printf '  FAIL  %s\n' "$*"
	FAILED=$((FAILED + 1))
}

check_boot() {
	echo "== system"
	local kver
	kver=$(uname -r)
	if [[ $kver == *-omarchy ]]; then pass "kernel $kver"; else fail "running $kver, boot linux-omarchy"; fi

	local dev="" d
	for d in /sys/bus/pci/devices/*; do
		[[ " $IPTS_IDS " == *" $(cat "$d/vendor"):$(cat "$d/device") "* ]] && dev=$d
	done
	if [[ -z $dev ]]; then
		fail "no IPTS touch controller ($IPTS_IDS)"
	else
		local type
		type=$(cat "$dev/iommu_group/type" 2>/dev/null || echo "no IOMMU")
		if [[ $type == identity || $type == "no IOMMU" ]]; then
			pass "controller ${dev##*/}, IOMMU: $type"
		else
			fail "controller ${dev##*/}, IOMMU group is '$type' instead of identity"
		fi
	fi

	local file
	file=$(modinfo -n ipts 2>/dev/null)
	if ! grep -q '^ipts ' /proc/modules; then
		fail "ipts module not loaded"
	elif [[ $file == */updates/dkms/* ]]; then
		pass "ipts module loaded from $file"
	else
		fail "ipts module loaded, but not from DKMS: $file"
	fi
	echo "        dkms: $(dkms status -m ipts 2>/dev/null | tr '\n' ' ')"

	# the "module verification failed ... tainting kernel" notice is expected for DKMS modules
	local errors
	errors=$(dmesg | grep -iE 'DMAR: \[DMA|ipts.*(fail|error)' | grep -v 'module verification failed')
	if [[ -z $errors ]]; then
		pass "no DMAR or ipts errors since boot"
	else
		fail "kernel errors since boot:"
		sed 's/^/        /' <<<"$errors" | tail -10
	fi

	local units
	units=$(systemctl list-units --state=running --no-legend --plain 'iptsd@*' | awk '{print $1}')
	if [[ -n $units ]]; then
		pass "iptsd running: $units"
		journalctl -b -u 'iptsd@*' --no-pager -o cat | grep -E 'Loading config|Connected to device' |
			sort -u | sed 's/^/        /'
	else
		fail "iptsd is not running (journalctl -b -u 'iptsd@*')"
	fi
}

find_touchscreen() {
	local e
	for e in /sys/class/input/event*; do
		if grep -q 'IPTSD Virtual Touchscreen' "$e/device/name" 2>/dev/null; then
			echo "/dev/input/${e##*/}"
			return 0
		fi
	done
	return 1
}

record_gestures() {
	echo
	echo "== gestures"
	command -v libinput >/dev/null || {
		fail "libinput not found, install libinput-tools"
		return
	}

	local node
	node=$(find_touchscreen) || {
		fail "iptsd virtual touchscreen not found"
		return
	}
	echo "recording $node, follow the >>> prompts (6 seconds each)"

	stdbuf -oL libinput debug-events --device "$node" 2>/dev/null |
		while IFS= read -r line; do printf '%s %s\n' "$(date +%s.%N)" "$line"; done >"$RAW" &
	# background jobs ignore Ctrl-C in scripts, stop the recording explicitly
	trap 'pkill -f "debug-events --device $node"' EXIT
	trap 'exit 130' INT TERM
	sleep 2

	local phases=("tap:tap once in the middle of the screen"
		"double:double-tap"
		"long:press and hold for about 1.5 seconds"
		"swipe:swipe down with 2 fingers"
		"pinch:pinch in and out with 2 fingers"
		"five:put 5 fingers on the screen at once")
	local starts=() p
	for p in "${phases[@]}"; do
		echo
		echo ">>> ${p#*:}"
		starts+=("${p%%:*}:$(date +%s.%N)")
		sleep 6
	done
	starts+=("end:$(date +%s.%N)")
	pkill -f "debug-events --device $node"
	trap - EXIT INT TERM
	sleep 1

	echo
	echo "results (touches: contacts detected, max: fingers at the same time,"
	echo "longest: longest contact, drops: contact lost for <100 ms, usually harmless)"
	local i
	for ((i = 0; i < ${#phases[@]}; i++)); do
		awk -v t0="${starts[i]#*:}" -v t1="${starts[i + 1]#*:}" -v name="${starts[i]%%:*}" '
			$1 < t0 || $1 >= t1 { next }
			# libinput pads coordinates ("20.50/ 5.25"), so a field split is not enough
			function coords(line,   m) {
				return match(line, /([0-9]+\.[0-9]+)\/ *([0-9]+\.[0-9]+) \(/, m) ? m[1] "/" m[2] : ""
			}
			$3 == "TOUCH_DOWN" {
				split(coords($0), pos, "/")
				if (last_up != "" && $1 - last_up < 0.1 && (pos[1] - up_x) ^ 2 + (pos[2] - up_y) ^ 2 < 9)
					drops++
				downs++; down_at[$5] = $1; cur[$5] = pos[1] "/" pos[2]
				if (++active > most) most = active
			}
			$3 == "TOUCH_UP" || $3 == "TOUCH_CANCEL" {
				if ($5 in down_at) {
					if ($1 - down_at[$5] > longest) longest = $1 - down_at[$5]
					split(cur[$5], pos, "/"); up_x = pos[1]; up_y = pos[2]; last_up = $1
					delete down_at[$5]; active--
				}
			}
			END {
				printf "  %-7s touches=%-3d max=%d longest=%.2fs drops=%d\n",
					name, downs, most, longest, drops
			}' "$RAW"
	done
}

main() {
	echo "omarchy-surface-touch verify, $(date)"
	check_boot
	((GESTURES)) && record_gestures
	echo
	if ((FAILED)); then
		echo "== $FAILED check(s) failed, see the README troubleshooting section"
	else
		echo "== all checks passed"
	fi
	echo "log: $LOG"
	((FAILED == 0))
}

mkdir -p "$LOG_DIR"
main 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
[[ -n ${SUDO_USER:-} ]] && chown -R "$SUDO_USER:" "$LOG_DIR" 2>/dev/null
exit "$status"
