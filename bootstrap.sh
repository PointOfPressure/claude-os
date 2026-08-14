#!/usr/bin/env bash
# bootstrap.sh: Claude OS entry point. Safe to run repeatedly.
#
# Fresh machine (after Debian netinst):
#   curl -fsSL https://raw.githubusercontent.com/PointOfPressure/claude-os/main/bootstrap.sh | sudo bash
# From a checkout:
#   sudo ./bootstrap.sh [stage-number ...]
set -euo pipefail

REPO_URL="${CLAUDE_OS_REPO:-https://github.com/PointOfPressure/claude-os.git}"
REPO_TARGET="${CLAUDE_OS_DIR:-/opt/claude-os}"

if [ "$(id -u)" -ne 0 ]; then
    echo "claude-os: must run as root (pipe to 'sudo bash' or run 'sudo ./bootstrap.sh')" >&2
    exit 1
fi

# Where are we? If bootstrap.sh sits inside a checkout, use it. If we were
# piped from curl, clone (or update) the repo and re-exec from there.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$(dirname -- "$SELF")/lib.sh" ]; then
    REPO_DIR="$(cd -- "$(dirname -- "$SELF")" && pwd)"
else
    export DEBIAN_FRONTEND=noninteractive
    command -v git >/dev/null || { apt-get update -qq && apt-get install -y -qq git; }
    if [ -d "$REPO_TARGET/.git" ]; then
        git -C "$REPO_TARGET" pull --ff-only -q || true
    else
        git clone -q "$REPO_URL" "$REPO_TARGET"
    fi
    exec bash "$REPO_TARGET/bootstrap.sh" "$@"
fi

export REPO_DIR
# shellcheck source=lib.sh
. "$REPO_DIR/lib.sh"

rm -f /run/claude-os.apt-updated /run/claude-os.reboot-required

start=$SECONDS
if [ "$#" -gt 0 ]; then
    # Run selected stages only, e.g.: sudo ./bootstrap.sh 30 50
    for n in "$@"; do
        stage=$(compgen -G "$REPO_DIR/stages/$n-*.sh" || true)
        [ -n "$stage" ] || die "no stage matches '$n'"
        log "stage $(basename "$stage")"
        bash "$stage"
    done
else
    for stage in "$REPO_DIR"/stages/*.sh; do
        log "stage $(basename "$stage")"
        bash "$stage"
    done
fi
log "bootstrap done in $((SECONDS - start))s"

if [ -f /run/claude-os.reboot-required ]; then
    log "ACTION REQUIRED: reboot now, then run 'sudo $REPO_DIR/bootstrap.sh' once more"
elif [ -x "$REPO_DIR/doctor.sh" ]; then
    log "run '$REPO_DIR/doctor.sh' to verify"
fi
