#!/usr/bin/env bash
# 70-appliance.sh: SSH, mDNS, lid/power behaviour, hostname, zram, tmux session.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

apt_install openssh-server avahi-daemon libnss-mdns zram-tools

# --- hostname: claude-os (-> claude-os.local via avahi) ----------------------
if ! is_container && [ "$(cat /etc/hostname)" != "claude-os" ]; then
    old=$(cat /etc/hostname)
    echo "claude-os" >/etc/hostname
    sed -i "s/\b$old\b/claude-os/g" /etc/hosts
    grep -q 'claude-os' /etc/hosts || echo "127.0.1.1	claude-os" >>/etc/hosts
    hostname claude-os
    log "hostname -> claude-os"
fi

# --- SSH keys, then (and only then) key-only auth ----------------------------
install -d -m 0700 -o "$CLAUDE_OS_USER" -g "$CLAUDE_OS_USER" "$CLAUDE_OS_HOME/.ssh"
KEYS="$CLAUDE_OS_HOME/.ssh/authorized_keys"
if grep -Eq '^(ssh-|ecdsa-|sk-)' "$CONFIG_DIR/ssh/authorized_keys"; then
    # repo copy holds real keys -> repo is authoritative
    deploy ssh/authorized_keys "$KEYS" 0600 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
elif [ ! -f "$KEYS" ]; then
    deploy ssh/authorized_keys "$KEYS" 0600 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
fi

if grep -Eq '^(ssh-|ecdsa-|sk-)' "$KEYS"; then
    deploy sshd/claude-os.conf /etc/ssh/sshd_config.d/claude-os.conf
    if [ "$DEPLOY_CHANGED" -eq 1 ]; then
        sshd -t
        has_systemd && systemctl reload ssh
        log "ssh hardened: key-only auth"
    fi
else
    log "WARNING: no public key in $KEYS yet, ssh password auth stays ON (see INSTALL.md)"
fi
if has_systemd; then
    systemctl enable --now ssh >/dev/null 2>&1
    systemctl enable --now avahi-daemon >/dev/null 2>&1
fi

# --- lid closed, never sleeps -------------------------------------------------
deploy logind/claude-os.conf /etc/systemd/logind.conf.d/claude-os.conf
if [ "$DEPLOY_CHANGED" -eq 1 ] && has_systemd; then
    systemctl restart systemd-logind
fi
if has_systemd; then
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1
fi

# --- zram swap (no disk swap: nothing to exclude from snapshots) --------------
deploy zram/zramswap /etc/default/zramswap
if [ "$DEPLOY_CHANGED" -eq 1 ] && has_systemd; then
    systemctl restart zramswap
fi

# --- persistent agent session -------------------------------------------------
deploy bin/claude-session /usr/local/bin/claude-session 0755
