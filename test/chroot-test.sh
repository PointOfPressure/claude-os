#!/usr/bin/env bash
# test/chroot-test.sh: run bootstrap + doctor inside a fresh debootstrap'd
# trixie chroot: the build-machine stand-in for a debian:trixie container.
# Everything btrfs/grub/systemd-dependent self-skips, same as in docker.
#
# Run as root (WSL2 or any Linux):  sudo test/chroot-test.sh [chroot-dir]
# Fresh run:                        sudo test/chroot-test.sh clean [chroot-dir]
#
# NEVER `rm -rf` the chroot yourself: /proc /sys /dev are (r)bind-mounted
# inside it and rm will chew through the host's live kernel filesystems.
# The clean subcommand unmounts first.
set -euo pipefail
if [ "${1:-}" = "clean" ]; then
    CLEAN=1; shift
else
    CLEAN=0
fi
CHROOT="${1:-/srv/claude-test}"
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

if [ "$CLEAN" -eq 1 ] && [ -d "$CHROOT" ]; then
    echo "claude-os-test: cleaning $CHROOT"
    # deepest mounts first, then the chroot itself
    awk -v c="$CHROOT" '$2 ~ "^"c {print $2}' /proc/mounts | sort -r |
        while read -r m; do umount -R "$m" 2>/dev/null || umount -l "$m" || true; done
    rm -rf --one-file-system "$CHROOT"
fi

if [ ! -f "$CHROOT/etc/debian_version" ]; then
    echo "claude-os-test: debootstrap trixie -> $CHROOT"
    debootstrap trixie "$CHROOT" http://deb.debian.org/debian
fi

# Chroot plumbing (left mounted between runs; a reboot clears them).
mountpoint -q "$CHROOT/proc" || mount -t proc proc "$CHROOT/proc"
mountpoint -q "$CHROOT/sys" || mount --rbind /sys "$CHROOT/sys"
mountpoint -q "$CHROOT/dev" || mount --rbind /dev "$CHROOT/dev"
cp /etc/resolv.conf "$CHROOT/etc/resolv.conf"

# No daemon may start inside the chroot (standard debootstrap practice).
printf '#!/bin/sh\nexit 101\n' >"$CHROOT/usr/sbin/policy-rc.d"
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

echo "claude-os-test: sync repo -> $CHROOT/opt/claude-os"
rsync -a --delete --exclude .git "$REPO/" "$CHROOT/opt/claude-os/"

echo "claude-os-test: bootstrap"
chroot "$CHROOT" bash /opt/claude-os/bootstrap.sh

echo "claude-os-test: hook unit tests"
chroot "$CHROOT" bash /opt/claude-os/test/hook-test.sh

echo "claude-os-test: grub-btrfs installability"
chroot "$CHROOT" bash /opt/claude-os/test/grub-btrfs-install-test.sh

echo "claude-os-test: doctor"
chroot "$CHROOT" bash /opt/claude-os/doctor.sh
