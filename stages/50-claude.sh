#!/usr/bin/env bash
# 50-claude.sh: Claude Code from Anthropic's apt repo + hooks + global CLAUDE.md.
set -euo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib.sh
. "$REPO_DIR/lib.sh"
require_root

CLAUDE_KEY_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

# --- signed apt repo (stable channel) ----------------------------------------
install -d -m 0755 /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/claude-code.asc ]; then
    curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
        -o /etc/apt/keyrings/claude-code.asc
    fpr=$(gpg --show-keys --with-colons /etc/apt/keyrings/claude-code.asc 2>/dev/null |
        awk -F: '/^fpr/ {print $10; exit}')
    if [ "$fpr" != "$CLAUDE_KEY_FPR" ]; then
        rm -f /etc/apt/keyrings/claude-code.asc
        die "claude-code signing key fingerprint mismatch (got: ${fpr:-none})"
    fi
    log "added claude-code signing key (fingerprint verified)"
fi
if [ ! -f /etc/apt/sources.list.d/claude-code.list ]; then
    echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
        >/etc/apt/sources.list.d/claude-code.list
    log "added claude-code apt repo (stable channel)"
    rm -f /run/claude-os.apt-updated
fi
apt_install claude-code

# --- snapshot hook + agent-global config -------------------------------------
deploy bin/claude-snapshot-hook /usr/local/bin/claude-snapshot-hook 0755

install -d -m 0755 -o "$CLAUDE_OS_USER" -g "$CLAUDE_OS_USER" "$CLAUDE_OS_HOME/.claude"
deploy claude/CLAUDE.md "$CLAUDE_OS_HOME/.claude/CLAUDE.md" 0644 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
deploy claude/settings.json "$CLAUDE_OS_HOME/.claude/settings.json" 0644 "$CLAUDE_OS_USER:$CLAUDE_OS_USER"
jq empty "$CLAUDE_OS_HOME/.claude/settings.json"

# Auth is interactive OAuth, a documented manual step, not automated here.
command -v claude >/dev/null || die "claude not on PATH after install"
