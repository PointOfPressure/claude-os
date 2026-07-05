#!/usr/bin/env bash
# test/hook-test.sh — unit-test claude-snapshot-hook's mutating-command
# detection and rate limiting, using a fake snapper. Safe to run anywhere the
# hook is deployed (chroot or real host); restores state afterwards.
set -u

HOOK=/usr/local/bin/claude-snapshot-hook
[ -x "$HOOK" ] || { echo "hook not deployed"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

FAKEBIN=$(mktemp -d)
CALLS="$FAKEBIN/calls.log"
printf '#!/bin/bash\necho "$@" >> %s\n' "$CALLS" >"$FAKEBIN/snapper"
chmod +x "$FAKEBIN/snapper"

# the hook requires a snapper config to act at all
MADE_CFG=0
if [ ! -f /etc/snapper/configs/root ]; then
    mkdir -p /etc/snapper/configs
    touch /etc/snapper/configs/root
    MADE_CFG=1
fi

FAILED=0
t() { # t <snap|none> <command string>
    local want=0 calls=0 rc out
    [ "$1" = snap ] && want=1
    rm -f "/tmp/claude-os-snapshot-$(id -u).last" "$CALLS"
    out=$(printf '%s' "$2" | jq -Rs '{tool_input:{command:.}}' |
        PATH="$FAKEBIN:$PATH" "$HOOK" 2>&1)
    rc=$?
    [ -f "$CALLS" ] && calls=$(wc -l <"$CALLS")
    if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$calls" -eq "$want" ]; then
        echo "PASS [$1] $2"
    else
        echo "FAIL [$1] rc=$rc calls=$calls out='$out' cmd: $2"
        FAILED=1
    fi
}

# should snapshot
t snap 'apt install foo'
t snap 'sudo apt-get update && sudo apt-get -y install make'
t snap 'systemctl restart nginx'
t snap 'systemctl enable --now grub-btrfsd'
t snap 'sudo dpkg -i thing.deb'
t snap 'usermod -aG docker ian'
t snap 'update-grub'
t snap 'rm -rf /tmp/x'
t snap 'echo hi > /etc/foo.conf'
t snap 'sed -i s/a/b/ /etc/hosts'
t snap 'cp x /usr/local/bin/x'
t snap 'curl -o /opt/tool https://x | true; chmod +x /opt/tool'
# should NOT snapshot (read-only or not undoable-by-snapshot)
t none 'ls -la'
t none 'cat /etc/passwd'
t none 'grep -r foo /usr/share'
t none 'git status'
t none 'rm file.txt'
t none 'echo test > /tmp/out'
t none 'systemctl status ssh'
t none 'systemctl show -p ActiveState --value docker'
t none 'apt list --installed'
t none 'sudo apt-get update'
t none 'dpkg -l | grep vim'
t none 'apt-cache search compose'
t none 'find /etc -name "*.conf"'

# rate limit: two mutating commands back to back -> exactly one snapshot
rm -f "/tmp/claude-os-snapshot-$(id -u).last" "$CALLS"
printf '%s' 'apt install a' | jq -Rs '{tool_input:{command:.}}' | PATH="$FAKEBIN:$PATH" "$HOOK"
printf '%s' 'apt install b' | jq -Rs '{tool_input:{command:.}}' | PATH="$FAKEBIN:$PATH" "$HOOK"
if [ "$(wc -l <"$CALLS")" -eq 1 ]; then
    echo "PASS rate-limit (1 snapshot for 2 commands)"
else
    echo "FAIL rate-limit"
    FAILED=1
fi

# garbage on stdin must be silently ignored
out=$(echo 'not json' | "$HOOK" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "PASS garbage stdin"; else echo "FAIL garbage stdin rc=$rc out='$out'"; FAILED=1; fi

[ "$MADE_CFG" -eq 1 ] && rm -f /etc/snapper/configs/root
rm -rf "$FAKEBIN" "/tmp/claude-os-snapshot-$(id -u).last"
exit "$FAILED"
