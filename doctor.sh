#!/usr/bin/env bash
# doctor.sh — verifies every claim in the Claude OS spec.
# One line per check: OK / FAIL / SKIP. Non-zero exit on any FAIL.
# Checks that need real hardware (btrfs/grub/systemd/docker daemon) SKIP in
# containers — INSTALL.md lists them as first-boot verification.
set -uo pipefail
REPO_DIR="${REPO_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=lib.sh
. "$REPO_DIR/lib.sh"
require_root

PASS=0 FAIL=0 SKIPPED=0
ok() { printf 'OK   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL %s%s\n' "$1" "${2:+ — $2}"; FAIL=$((FAIL + 1)); }
skip() { printf 'SKIP %s (%s)\n' "$1" "$2"; SKIPPED=$((SKIPPED + 1)); }
chk() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else fail "$n"; fi; }

# Emulate an `ssh claude-os.local <cmd>` shell: pam_env applies /etc/environment,
# then Debian's bash (compiled with SSH_SOURCE_BASHRC) sources ~/.bashrc because
# SSH_CLIENT is set. This is the exact code path a remote non-login command takes.
as_ssh() {
    local envvars
    envvars=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' /etc/environment || true)
    # shellcheck disable=SC2086
    sudo -u "$CLAUDE_OS_USER" env -i $envvars \
        HOME="$CLAUDE_OS_HOME" USER="$CLAUDE_OS_USER" LOGNAME="$CLAUDE_OS_USER" \
        SHELL=/bin/bash TERM=dumb SSH_CLIENT='127.0.0.1 0 22' \
        PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        bash -c "$1"
}

# ---- base --------------------------------------------------------------------
CORE_PKGS=(git gh curl wget ripgrep fd-find bat jq yq sqlite3 tmux htop btop
    tree unzip zip p7zip-full rsync build-essential pkg-config cmake python3
    python3-venv ca-certificates gnupg lsof strace ltrace net-tools dnsutils
    nmap ncdu moreutils shellcheck)
missing=()
for p in "${CORE_PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ "${#missing[@]}" -eq 0 ]; then ok "core packages (${#CORE_PKGS[@]})"; else fail "core packages" "missing: ${missing[*]}"; fi

chk "fd symlink" fd --version
chk "bat symlink" bat --version
chk "locale en_GB.UTF-8" bash -c "locale -a | grep -qi 'en_GB.utf8'"
chk "timezone Europe/London" bash -c "readlink -f /etc/localtime | grep -q 'Europe/London'"
chk "user $CLAUDE_OS_USER exists" id -u "$CLAUDE_OS_USER"
chk "sudo NOPASSWD for $CLAUDE_OS_USER" bash -c "sudo -l -U $CLAUDE_OS_USER | grep -q NOPASSWD"
chk "apt assume-yes" bash -c "apt-config dump | grep -q 'APT::Get::Assume-Yes .*true'"
chk "apt conffile answers forced" bash -c "apt-config dump | grep -q 'force-confold'"
if is_container; then
    skip "wifi firmware packages" "container"
else
    chk "wifi firmware packages" bash -c "dpkg -s firmware-iwlwifi >/dev/null && dpkg -s firmware-brcm80211 >/dev/null"
fi

# ---- token-economy environment -------------------------------------------------
for v in 'NO_COLOR=1' 'PAGER=cat' 'GIT_PAGER=cat' 'MANPAGER=cat' 'SYSTEMD_PAGER=' 'DEBIAN_FRONTEND=noninteractive'; do
    chk "/etc/environment: $v" grep -q "^$v$" /etc/environment
done
chk "pam_env wired into sshd" bash -c "grep -rq pam_env /etc/pam.d/sshd /etc/pam.d/common-session 2>/dev/null"
chk "environment.d deployed" test -f /etc/environment.d/50-claude-os.conf
chk "profile.d deployed" test -f /etc/profile.d/claude-os.sh
chk "git: no pager" bash -c "[ \"\$(git config --system core.pager)\" = cat ]"
chk "git: defaultBranch main" bash -c "[ \"\$(git config --system init.defaultBranch)\" = main ]"
chk "journald capped 200M" grep -q 'SystemMaxUse=200M' /etc/systemd/journald.conf.d/claude-os.conf
chk "motd silent" bash -c "[ ! -s /etc/motd ] && ! find /etc/update-motd.d -type f -perm -u+x 2>/dev/null | grep -q ."
chk "minimal bashrc for $CLAUDE_OS_USER" cmp -s "$CONFIG_DIR/skel/bashrc" "$CLAUDE_OS_HOME/.bashrc"
if [ "$(as_ssh 'echo $PAGER' 2>/dev/null)" = "cat" ]; then ok "ssh shell: PAGER=cat"; else fail "ssh shell: PAGER=cat"; fi

# ---- snapshots -----------------------------------------------------------------
chk "snap CLI deployed" test -x /usr/local/bin/snap
chk "snap CLI parses" bash -n /usr/local/bin/snap
if root_is_btrfs; then
    chk "subvol: / on @" bash -c "findmnt -no OPTIONS / | grep -q 'subvol=/@\$\|subvol=/@,\|subvol=@'"
    chk "subvol: /home on @home" bash -c "findmnt -no OPTIONS /home | grep -q '@home'"
    chk "subvol: /var/log on @var-log" bash -c "findmnt -no OPTIONS /var/log | grep -q '@var-log'"
    chk "subvol: /.snapshots on @snapshots" bash -c "findmnt -no OPTIONS /.snapshots | grep -q '@snapshots'"
    chk "snapper root config" test -f /etc/snapper/configs/root
    chk "snapper timeline off" grep -q '^TIMELINE_CREATE="no"' /etc/snapper/configs/root
    chk "snapper list works" snapper --no-dbus -c root list
    chk "grub-btrfs installed" test -f /etc/grub.d/41_snapshots-btrfs
    chk "grub cfg lists snapshots" grep -q 'snapshots' /boot/grub/grub.cfg
    chk "grub os-prober enabled" test -f /etc/default/grub.d/claude-os.cfg
    chk "grub cfg lists Windows" grep -qi 'windows' /boot/grub/grub.cfg
    if has_systemd; then
        chk "snapper-cleanup.timer active" systemctl is-active snapper-cleanup.timer
        chk "grub-btrfsd active" systemctl is-active grub-btrfsd
    fi
else
    skip "btrfs layout / snapper / grub-btrfs" "root is not btrfs — verify on hardware"
fi

# ---- claude code ----------------------------------------------------------------
chk "claude installed" bash -c "command -v claude"
if as_ssh 'claude --version' >/dev/null 2>&1; then ok "claude --version (as $CLAUDE_OS_USER)"; else fail "claude --version (as $CLAUDE_OS_USER)"; fi
chk "snapshot hook deployed" test -x /usr/local/bin/claude-snapshot-hook
hook_out=$(echo '{"tool_input":{"command":"true"}}' | /usr/local/bin/claude-snapshot-hook 2>&1); hook_rc=$?
if [ "$hook_rc" -eq 0 ] && [ -z "$hook_out" ]; then ok "snapshot hook: silent exit 0"; else fail "snapshot hook: silent exit 0" "rc=$hook_rc out=$hook_out"; fi
chk "settings.json valid JSON" jq empty "$CLAUDE_OS_HOME/.claude/settings.json"
chk "settings.json registers hook" jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash")' "$CLAUDE_OS_HOME/.claude/settings.json"
chk "global CLAUDE.md deployed" test -s "$CLAUDE_OS_HOME/.claude/CLAUDE.md"

# ---- toolchain (through the ssh-emulated shell: the real acceptance) -------------
for tool in 'node -v' 'pnpm -v' 'go version' 'rustc --version' 'uv --version' 'dotnet --list-sdks'; do
    if as_ssh "$tool" >/dev/null 2>&1; then ok "ssh shell: $tool"; else fail "ssh shell: $tool"; fi
done
chk "dotnet SDK 10.x" bash -c "dotnet --list-sdks | grep -q '^10\.'"

# ---- sensor -----------------------------------------------------------------------
chk "xvfb-run present" bash -c "command -v xvfb-run"
chk "playwright installed" test -d /opt/playwright/node_modules/playwright
chk "chromium downloaded" bash -c "ls /opt/ms-playwright | grep -qi chromium"
rm -f /tmp/claude-os-doctor.png
if as_ssh 'shot about:blank /tmp/claude-os-doctor.png' >/dev/null 2>&1 && [ -s /tmp/claude-os-doctor.png ]; then
    ok "shot screenshots about:blank"
else
    fail "shot screenshots about:blank"
fi
rm -f /tmp/claude-os-doctor.png

# ---- appliance --------------------------------------------------------------------
chk "sshd config valid" sshd -t
if grep -Eq '^(ssh-|ecdsa-|sk-)' "$CLAUDE_OS_HOME/.ssh/authorized_keys" 2>/dev/null; then
    chk "ssh: password auth off" bash -c "sshd -T 2>/dev/null | grep -q '^passwordauthentication no'"
    chk "ssh: root login off" bash -c "sshd -T 2>/dev/null | grep -q '^permitrootlogin no'"
else
    skip "ssh key-only auth" "no public key pasted yet — INSTALL.md step"
fi
chk "logind lid config deployed" grep -q 'HandleLidSwitch=ignore' /etc/systemd/logind.conf.d/claude-os.conf
chk "claude-session deployed" test -x /usr/local/bin/claude-session
if is_container || ! has_systemd; then
    skip "hostname/avahi/sleep-mask/zram/docker daemon" "no systemd — verify on hardware"
else
    chk "hostname claude-os" bash -c "[ \"\$(hostname)\" = claude-os ]"
    chk "avahi active" systemctl is-active avahi-daemon
    chk "sleep targets masked" bash -c "[ \"\$(systemctl is-enabled sleep.target)\" = masked ]"
    chk "zram swap active" bash -c "swapon --show=NAME --noheadings | grep -q zram"
    chk "docker daemon runs containers" docker run --rm hello-world
fi

# ---- containers ---------------------------------------------------------------------
chk "docker.io installed" dpkg -s docker.io
chk "$CLAUDE_OS_USER in docker group" bash -c "id -nG $CLAUDE_OS_USER | grep -qw docker"
chk "docker storage-driver pinned" grep -q overlay2 /etc/docker/daemon.json

printf -- '---\n%d ok, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIPPED"
[ "$FAIL" -eq 0 ]
