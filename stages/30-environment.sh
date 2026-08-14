#!/usr/bin/env bash
# 30-environment.sh: the token-economy defaults no stock distro has.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

# Env vars, three layers:
#   /etc/environment      -> pam_env: every session incl. `ssh host cmd`
#   /etc/environment.d/   -> systemd user services
#   /etc/profile.d/       -> login shells (belt and braces)
deploy environment/environment /etc/environment
deploy environment.d/50-claude-os.conf /etc/environment.d/50-claude-os.conf
deploy profile.d/claude-os.sh /etc/profile.d/claude-os.sh

# git: no pager, no colour, no advice.
deploy git/gitconfig /etc/gitconfig

# journald cap.
deploy journald/claude-os.conf /etc/systemd/journald.conf.d/claude-os.conf
if [ "$DEPLOY_CHANGED" -eq 1 ] && has_systemd; then
    systemctl restart systemd-journald
fi

# Silence the MOTD: empty static file, defang the dynamic scripts.
deploy motd/motd /etc/motd
if [ -d /etc/update-motd.d ]; then
    find /etc/update-motd.d -type f -perm -u+x -exec chmod -x {} +
fi

# Minimal bashrc: PATH (mise shims) before the interactive gate, terse PS1.
deploy skel/bashrc /etc/skel/.bashrc
deploy skel/bashrc "$CLAUDE_OS_HOME/.bashrc" 0644 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
deploy skel/bashrc /root/.bashrc
