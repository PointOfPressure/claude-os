#!/usr/bin/env bash
# 60-sensor.sh — the one exception to headless: Xvfb + Chromium + Playwright,
# so the agent can render -> screenshot -> verify frontend work.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

apt_install xvfb xauth

run_as_user node -v >/dev/null 2>&1 || die "node missing — stage 40 must run first"

# Playwright package (owned by ian, versions pinned by package.json).
install -d -m 0755 -o "$CLAUDE_OS_USER" -g "$CLAUDE_OS_USER" /opt/playwright
deploy sensor/package.json /opt/playwright/package.json 0644 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
deploy sensor/shot.js /opt/playwright/shot.js 0644 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
if [ ! -d /opt/playwright/node_modules/playwright ]; then
    log "npm install playwright (this downloads ~50MB)"
    run_as_user env NPM_CONFIG_UPDATE_NOTIFIER=false \
        bash -c 'cd /opt/playwright && npm install --no-fund --no-audit --loglevel=error >/dev/null'
fi

# Browsers into a shared system path (PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
# is set system-wide by stage 30). Run as root so --with-deps can apt-install
# the OS dependencies on first run.
NODE_BIN=$(run_as_user bash -c 'mise which node' 2>/dev/null || true)
[ -n "$NODE_BIN" ] || die "cannot resolve mise-managed node binary"
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
if [ ! -d /opt/ms-playwright ]; then
    log "playwright install --with-deps chromium (first run: ~200MB)"
    PATH="$(dirname "$NODE_BIN"):$PATH" \
        /opt/playwright/node_modules/.bin/playwright install --with-deps chromium >/dev/null
else
    # cheap no-op when current; downloads only after a playwright upgrade
    PATH="$(dirname "$NODE_BIN"):$PATH" \
        /opt/playwright/node_modules/.bin/playwright install chromium >/dev/null
fi
chmod -R a+rX /opt/ms-playwright

deploy bin/shot /usr/local/bin/shot 0755
