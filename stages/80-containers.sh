#!/usr/bin/env bash
# 80-containers.sh — docker from Debian repos: the second line of disposability.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

apt_install docker.io
# compose v2 if trixie carries it (name has moved around between releases)
if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
    apt_install docker-compose-v2
fi

# overlay2 explicitly: never let docker pick the btrfs storage driver, which
# would litter the root subvolume with nested subvolumes and break rollbacks.
deploy docker/daemon.json /etc/docker/daemon.json
if [ "$DEPLOY_CHANGED" -eq 1 ] && has_systemd; then
    systemctl restart docker
fi

if ! id -nG "$CLAUDE_OS_USER" | grep -qw docker; then
    usermod -aG docker "$CLAUDE_OS_USER"
    log "added $CLAUDE_OS_USER to docker group"
fi

if has_systemd; then
    systemctl enable --now docker >/dev/null 2>&1
fi
