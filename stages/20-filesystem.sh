#!/usr/bin/env bash
# 20-filesystem.sh: btrfs subvolume layout, snapper, grub-btrfs, snap CLI.
# Everything btrfs/grub-specific self-skips in containers.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

# The snap CLI is plain bash, deploy it everywhere so it's reviewable/testable.
deploy bin/snap /usr/local/bin/snap 0755

if ! root_is_btrfs; then
    log "skip filesystem work: / is not btrfs (container/test environment)"
    exit 0
fi

apt_install snapper btrfs-progs inotify-tools os-prober

UUID=$(findmnt -no UUID /)
DEV=$(findmnt -no SOURCE / | sed 's/\[.*$//')
TOP=$(mktemp -d /run/claude-os-top.XXXXXX)
mount -o subvolid=5 "$DEV" "$TOP"
cleanup() { umount "$TOP" 2>/dev/null || true; rmdir "$TOP" 2>/dev/null || true; }
trap cleanup EXIT

GRUB_REFRESH=0

# --- 1. root subvolume: Debian installer's @rootfs -> @ ---------------------
if [ ! -d "$TOP/@" ] && [ -d "$TOP/@rootfs" ]; then
    mv "$TOP/@rootfs" "$TOP/@"
    sed -i 's,subvol=/*@rootfs,subvol=@,g' /etc/fstab
    log "renamed root subvolume @rootfs -> @"
    # GRUB embeds the subvolume path in its core image; refresh both stages.
    update-grub 2>/dev/null
    if [ -d /sys/firmware/efi ]; then
        grub-install >/dev/null 2>&1
    else
        grub-install "/dev/$(lsblk -no PKNAME "$DEV")" >/dev/null 2>&1
    fi
    need_reboot "root subvolume renamed"
fi
[ -d "$TOP/@" ] || die "no @ subvolume at btrfs top level (unexpected layout)"

# --- 2. @home ----------------------------------------------------------------
if ! grep -qE '^[^#]\S*\s+/home\s+btrfs' /etc/fstab; then
    if [ ! -d "$TOP/@home" ]; then
        btrfs subvolume create "$TOP/@home" >/dev/null
        rsync -aHAX /home/ "$TOP/@home/"
    fi
    echo "UUID=$UUID /home btrfs defaults,noatime,subvol=@home 0 0" >>/etc/fstab
    # originals stay hidden under the mount (a few KB on a fresh install)
    mount /home
    log "migrated /home to @home"
fi

# --- 3. @var-log (excluded from root snapshots so rollbacks keep logs) -------
if ! grep -qE '^[^#]\S*\s+/var/log\s+btrfs' /etc/fstab; then
    if [ ! -d "$TOP/@var-log" ]; then
        btrfs subvolume create "$TOP/@var-log" >/dev/null
        rsync -aHAX /var/log/ "$TOP/@var-log/"
    fi
    echo "UUID=$UUID /var/log btrfs defaults,noatime,subvol=@var-log 0 0" >>/etc/fstab
    mount /var/log
    has_systemd && systemctl restart systemd-journald
    log "migrated /var/log to @var-log"
fi

# --- 4. @snapshots + snapper root config -------------------------------------
if [ ! -f /etc/snapper/configs/root ]; then
    snapper --no-dbus -c root create-config /
    # snapper made a nested .snapshots subvolume; replace it with a top-level
    # @snapshots so snapshots survive root rollbacks.
    if btrfs subvolume show /.snapshots >/dev/null 2>&1; then
        btrfs subvolume delete /.snapshots >/dev/null
    fi
    [ -d "$TOP/@snapshots" ] || btrfs subvolume create "$TOP/@snapshots" >/dev/null
    mkdir -p /.snapshots
    grep -qE '^[^#]\S*\s+/\.snapshots\s+btrfs' /etc/fstab ||
        echo "UUID=$UUID /.snapshots btrfs defaults,noatime,subvol=@snapshots 0 0" >>/etc/fstab
    mount /.snapshots
    chmod 750 /.snapshots
    log "snapper root config created (@snapshots)"
fi
deploy snapper/root /etc/snapper/configs/root

if has_systemd; then
    systemctl enable --now snapper-cleanup.timer >/dev/null 2>&1
    systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
fi

# --- 5. grub-btrfs (not packaged in Debian; pinned upstream release) ----------
if [ ! -f /etc/grub.d/41_snapshots-btrfs ]; then
    tmp=$(mktemp -d)
    git clone -q --depth 1 --branch v4.14 https://github.com/Antynea/grub-btrfs "$tmp"
    make -C "$tmp" install >/dev/null
    rm -rf "$tmp"
    log "installed grub-btrfs v4.14"
    GRUB_REFRESH=1
fi
if has_systemd && ! systemctl is-enabled -q grub-btrfsd 2>/dev/null; then
    systemctl enable --now grub-btrfsd >/dev/null 2>&1
    log "enabled grub-btrfsd"
fi

# --- 6. GRUB defaults: keep Windows bootable (os-prober), short timeout ------
deploy grub/claude-os.cfg /etc/default/grub.d/claude-os.cfg
[ "$DEPLOY_CHANGED" -eq 1 ] && GRUB_REFRESH=1

if [ "$GRUB_REFRESH" -eq 1 ]; then
    update-grub 2>/dev/null
    log "regenerated grub config"
fi
