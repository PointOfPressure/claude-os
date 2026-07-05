#!/usr/bin/env bash
# test/btrfs-snap-test.sh — exercise the exact subvolume mechanics that
# `snap rollback` and `snap prune` perform, on a throwaway btrfs loop device.
# Needs a kernel with btrfs (WSL2 qualifies) and btrfs-progs. Run as root.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

img=$(mktemp /tmp/snaptest-XXXX.img)
m=$(mktemp -d)
# shellcheck disable=SC2317  # invoked via trap
cleanup() {
    umount "$m" 2>/dev/null || true
    if [ -n "${loop:-}" ]; then losetup -d "$loop" 2>/dev/null || true; fi
    rm -f "$img"
    rmdir "$m" 2>/dev/null || true
}
trap cleanup EXIT

truncate -s 512M "$img"
loop=$(losetup -f --show "$img")
mkfs.btrfs -q "$loop"
mount "$loop" "$m"   # top level (subvolid=5), same as snap's mount_top

fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# simulate the installed layout: @ is root, @snapshots holds snapper's tree
btrfs subvolume create "$m/@" >/dev/null
btrfs subvolume create "$m/@snapshots" >/dev/null
mkdir -p "$m/@snapshots/42"
echo current >"$m/@/marker"
btrfs subvolume snapshot -r "$m/@" "$m/@snapshots/42/snapshot" >/dev/null
# root then diverges past the snapshot
echo broken >"$m/@/marker"

# --- what `snap rollback 42` does -------------------------------------------
ts=20260705-000000
mv "$m/@" "$m/@-pre-rollback-$ts"
btrfs subvolume snapshot "$m/@snapshots/42/snapshot" "$m/@" >/dev/null

check "new @ has snapshot content" "[ \"\$(cat \"$m/@/marker\")\" = current ]"
check "old root parked" "[ -d \"$m/@-pre-rollback-$ts\" ] && [ \"\$(cat \"$m/@-pre-rollback-$ts/marker\")\" = broken ]"
check "new @ is writable" "echo t >\"$m/@/writetest\""
check "snapshots subvol untouched" "[ -d \"$m/@snapshots/42/snapshot\" ]"

# --- what `snap prune` does to parked roots -----------------------------------
btrfs subvolume delete "$m/@-pre-rollback-$ts" >/dev/null
check "parked root deletable" "[ ! -d \"$m/@-pre-rollback-$ts\" ]"

# rolling back a second time from the same snapshot must also work
mv "$m/@" "$m/@-pre-rollback-b"
btrfs subvolume snapshot "$m/@snapshots/42/snapshot" "$m/@" >/dev/null
check "rollback repeatable" "[ \"\$(cat \"$m/@/marker\")\" = current ]"

exit "$fail"
