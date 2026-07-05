#!/usr/bin/env bash
# test/grub-btrfs-install-test.sh — verify the pinned grub-btrfs release still
# clones and `make install`s cleanly on trixie (stage 20 does this on real
# hardware, where the chroot test can't reach). Installs into a DESTDIR and
# throws it away — does not touch the running system.
set -euo pipefail
tmp=$(mktemp -d)
dest=$(mktemp -d)
trap 'rm -rf "$tmp" "$dest"' EXIT

git clone -q --depth 1 --branch v4.14 https://github.com/Antynea/grub-btrfs "$tmp"
make -C "$tmp" DESTDIR="$dest" install >/dev/null

fail=0
for f in etc/grub.d/41_snapshots-btrfs usr/bin/grub-btrfsd \
    usr/lib/systemd/system/grub-btrfsd.service etc/default/grub-btrfs/config; do
    if [ -e "$dest/$f" ]; then echo "PASS $f"; else echo "FAIL $f missing"; fail=1; fi
done
exit "$fail"
