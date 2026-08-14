#!/usr/bin/env bash
# 40-toolchain.sh: mise (node/pnpm/go/rust/uv) + .NET SDK.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

# --- mise via its apt repo (extrepo carries it for Debian 11+) ---------------
apt_install extrepo
if ! compgen -G '/etc/apt/sources.list.d/extrepo_mise*' >/dev/null; then
    extrepo enable mise
    log "enabled mise apt repo (extrepo)"
    rm -f /run/claude-os.apt-updated
fi
apt_install mise

# Tool versions are channels, not numbers, mise keeps them current.
# Installed per-user for ian; shims land in ~/.local/share/mise/shims, which
# ~/.bashrc puts on PATH for interactive AND `ssh host cmd` shells.
run_as_user env MISE_YES=1 mise use -g node@lts pnpm@latest go@latest rust@latest uv@latest

# --- .NET SDK (current LTS) from packages.microsoft.com for Debian 13 --------
if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
    curl -fsSL -o /tmp/packages-microsoft-prod.deb \
        https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb >/dev/null
    rm -f /tmp/packages-microsoft-prod.deb
    log "added packages.microsoft.com repo"
    rm -f /run/claude-os.apt-updated
fi
apt_install dotnet-sdk-10.0
