# Claude OS, agent manual

You are on **claude-os**: a headless Debian laptop on the home LAN, built as a
native habitat for Claude Code. You are user `ian` with **passwordless sudo**, you effectively have root. That is the design. The machine is disposable: the
git repo at `/opt/claude-os` rebuilds this entire OS, and a full reinstall is
~20 minutes. Act accordingly, bias to action, not caution.

## Undo = snapshots, not permission walls

- `snap now <label>`, snapshot root now, prints the snapshot number
- `snap list`, csv: number,date,description
- `snap diff <n>`, files changed between snapshot n and now
- `snap rollback <n>`, replace root with snapshot n, then `sudo reboot`
- `snap prune`, enforce cleanup, delete old pre-rollback roots
- A PreToolUse hook already snapshots before mutating commands (rate-limited
  to 1 per 10 min). Routine package installs need no manual snapshot; take
  `snap now` before genuinely risky system surgery.
- `/home` and `/var/log` are separate subvolumes, rollback never touches
  your work or the logs that explain what went wrong.
- If you brick userspace: physical GRUB menu → "Debian snapshots" entry →
  boot any snapshot → `snap rollback <n>` → reboot. See
  `/opt/claude-os/docs/ROLLBACK.md`.

## Environment guarantees (rely on these)

- **Nothing ever blocks on interactivity.** No pager runs (`PAGER=cat`,
  `GIT_PAGER=cat`, `SYSTEMD_PAGER=` …), apt never prompts
  (`DEBIAN_FRONTEND=noninteractive`, conffile answers forced), no colour
  (`NO_COLOR=1`). If a command seems hung, it is not a pager or a prompt.
- **Table stakes are preinstalled**, do not `apt install` these: git, gh,
  curl, wget, rg, fd, jq, yq, sqlite3, tmux, htop, btop, tree, zip/unzip/7z,
  rsync, build-essential, pkg-config, cmake, python3, shellcheck, lsof,
  strace, ltrace, nmap, dig/host, ncdu, moreutils (sponge!), bat.
- **Toolchains:** node (LTS), pnpm, go, rust via mise, shims are on PATH in
  every shell, including `ssh claude-os.local <cmd>`. Python: use `uv`
  (`uv venv`, `uv pip`, `uv tool install`). .NET SDK (LTS) system-wide:
  `dotnet new` just works.
- **Docker** is running and you are in the `docker` group. Use containers as
  the second line of disposability, build/test junk in a container instead
  of on the host when convenient.

## Terse output beats pretty output

Prefer flags that emit JSON or plain text and pipe through `jq`:

- `ip -j addr`, `lsblk -J`, `findmnt -J`, `ss -tlnH`
- `docker inspect`, `docker ps --format json`
- `gh pr view --json`, `gh run list --json`
- `systemctl show -p ActiveState --value <unit>` (never parse `systemctl status`)
- `journalctl -o cat -n 50 -u <unit>` (drops timestamps/hostname prefix)
- `git -c core.quotepath=false status --porcelain`

## Frontend verification loop

- `shot <url> [out.png] [--full] [--wait ms]`, headless Chromium screenshot,
  prints the output path. Read the image to verify rendering.
- Playwright lives at `/opt/playwright` (browsers in `/opt/ms-playwright`);
  write one-off scripts against it for click-through checks. `xvfb-run` exists
  if something truly needs a display.

## Long-running work

- `claude-session`, attach/create the tmux session `claude`; work survives
  SSH drops. Detach with `Ctrl-b d`.

## The OS is a repo

- `/opt/claude-os` defines this machine. To change system config, edit the
  repo and re-run `sudo /opt/claude-os/bootstrap.sh` (idempotent), then
  commit. Avoid hand-editing `/etc`, anything not in the repo is lost on
  reinstall by design.
- `~/.claude/settings.json` and this file are deployed from that repo, edit
  them there.
- `/opt/claude-os/doctor.sh` verifies the whole machine spec (OK/FAIL per
  line). Run it after system surgery.
