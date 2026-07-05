#!/usr/bin/env bash
# 10-base.sh — apt behaviour, core packages, firmware, locale/tz, primary user.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

# apt must be silent and non-interactive before anything else installs.
deploy apt/99claude-os /etc/apt/apt.conf.d/99claude-os

# Make sure the non-free-firmware component is enabled (deb822 sources).
if [ -f /etc/apt/sources.list.d/debian.sources ] &&
    ! grep -q 'non-free-firmware' /etc/apt/sources.list.d/debian.sources; then
    sed -i 's/^Components: .*/& non-free-firmware/' /etc/apt/sources.list.d/debian.sources
    log "enabled non-free-firmware component"
    rm -f /run/claude-os.apt-updated
fi

# Core packages: the agent should never burn a turn installing table stakes.
apt_install \
    git gh curl wget ripgrep fd-find bat jq yq sqlite3 tmux htop btop tree \
    unzip zip p7zip-full rsync build-essential pkg-config cmake \
    python3 python3-venv ca-certificates gnupg lsof strace ltrace \
    net-tools bind9-dnsutils nmap ncdu moreutils shellcheck \
    locales sudo

# Firmware for the Inspiron's WiFi (Intel or Broadcom SKU) — hardware only.
if ! is_container; then
    apt_install firmware-linux-nonfree firmware-iwlwifi firmware-brcm80211
fi

# Debian names collide with upstream: fd and bat deserve their real names.
[ -e /usr/local/bin/fd ] || { ln -s "$(command -v fdfind)" /usr/local/bin/fd; log "symlinked fd"; }
[ -e /usr/local/bin/bat ] || { ln -s "$(command -v batcat)" /usr/local/bin/bat; log "symlinked bat"; }

# Locale + timezone.
if ! grep -q '^en_GB.UTF-8 UTF-8' /etc/locale.gen; then
    sed -i 's/^# *en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
    grep -q '^en_GB.UTF-8 UTF-8' /etc/locale.gen || echo 'en_GB.UTF-8 UTF-8' >>/etc/locale.gen
    locale-gen >/dev/null
    update-locale LANG=en_GB.UTF-8
    log "locale en_GB.UTF-8"
fi
if [ "$(readlink -f /etc/localtime)" != "/usr/share/zoneinfo/Europe/London" ]; then
    ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
    echo "Europe/London" >/etc/timezone
    log "timezone Europe/London"
fi

# Primary user (the netinst creates it; containers don't).
if ! id -u "$CLAUDE_OS_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$CLAUDE_OS_USER"
    log "created user $CLAUDE_OS_USER"
fi

# Passwordless sudo — the agent has root by design.
visudo -cf "$CONFIG_DIR/sudoers.d/ian-nopasswd" >/dev/null
deploy sudoers.d/ian-nopasswd /etc/sudoers.d/ian-nopasswd 0440
