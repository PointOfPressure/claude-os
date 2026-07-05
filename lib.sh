#!/usr/bin/env bash
# lib.sh — shared helpers sourced by bootstrap.sh, stages/*.sh and doctor.sh.
# Not executable on its own.

# Resolve repo layout relative to whichever script sourced us.
: "${REPO_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
CONFIG_DIR="$REPO_DIR/config"

# The user the agent runs as. Overridable for tests.
: "${CLAUDE_OS_USER:=ian}"
CLAUDE_OS_HOME="/home/$CLAUDE_OS_USER"

export DEBIAN_FRONTEND=noninteractive
# Deterministic tool output during bootstrap, even before locales exist.
export LC_ALL=C.UTF-8

log() { printf 'claude-os: %s\n' "$*"; }
die() { printf 'claude-os: ERROR: %s\n' "$*" >&2; exit 1; }

# True inside docker/podman/chroot — anywhere without a running systemd.
is_container() {
    [ -f /.dockerenv ] && return 0
    grep -qa 'container=' /proc/1/environ 2>/dev/null && return 0
    [ ! -d /run/systemd/system ]
}

has_systemd() { [ -d /run/systemd/system ]; }

root_is_btrfs() { [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ]; }

require_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (sudo)"; }

# apt-get update at most once per bootstrap run (marker in /run).
apt_update() {
    if [ ! -f /run/claude-os.apt-updated ]; then
        log "apt-get update"
        apt-get update -qq || die "apt-get update failed"
        touch /run/claude-os.apt-updated
    fi
}

# Force the next apt_update to actually run (call after adding a repo).
apt_update_force() { rm -f /run/claude-os.apt-updated; apt_update; }

# Install only the packages that are missing. Quiet on success, loud on failure.
apt_install() {
    local missing=() p out
    for p in "$@"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    [ "${#missing[@]}" -eq 0 ] && return 0
    apt_update
    log "apt install: ${missing[*]}"
    if ! out=$(apt-get install -y -qq "${missing[@]}" 2>&1 </dev/null); then
        printf '%s\n' "$out" >&2
        die "apt-get install failed: ${missing[*]}"
    fi
}

# deploy <src relative to config/> <dest> [mode] [owner:group]
# Copies a reviewable file out of the repo. No-op (and silent) when unchanged.
# Sets DEPLOY_CHANGED=1 when the file actually changed (for service reloads).
# shellcheck disable=SC2034  # consumed by the stages that source this file
DEPLOY_CHANGED=0
deploy() {
    local src="$CONFIG_DIR/$1" dest="$2" mode="${3:-0644}" owner="${4:-root:root}"
    [ -f "$src" ] || die "missing config file: $src"
    DEPLOY_CHANGED=0
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        return 0
    fi
    install -D -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$src" "$dest"
    # shellcheck disable=SC2034  # consumed by the stages that source this file
    DEPLOY_CHANGED=1
    log "deployed $dest"
}

# Run a command as the primary user with a sane HOME/PATH.
run_as_user() {
    sudo -u "$CLAUDE_OS_USER" \
        env HOME="$CLAUDE_OS_HOME" USER="$CLAUDE_OS_USER" LOGNAME="$CLAUDE_OS_USER" \
        PATH="$CLAUDE_OS_HOME/.local/share/mise/shims:$CLAUDE_OS_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        "$@"
}

# Mark that a reboot is needed to finish (bootstrap reports it at the end).
need_reboot() { touch /run/claude-os.reboot-required; log "reboot required: $*"; }
