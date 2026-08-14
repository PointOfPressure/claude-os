# DESIGN: why each decision went the way it did

Ordering principle for every call: **turn economy > output economy > cheap
disposability**, and when two options tie, the more boring one (deeper
training-data representation) wins.

Facts marked *(verified)* were checked against live docs/repos on 2026-07-05,
not recalled from memory.

## Base system

- **Debian 13 stable, no desktop.** The distro every LLM knows best; stable
  means the agent never fights version churn. Netinst + preseed keeps
  reinstall at ~20 min.
- **Core package list baked in** (stage 10): every `apt install ripgrep` the
  agent doesn't run is a saved turn. `bat` added beyond the spec list since
  `fd`/`bat` symlinks were required anyway.
- **`fd`/`bat` symlinked in `/usr/local/bin`** (Debian ships them as
  `fdfind`/`batcat`): the agent will type the upstream names.
- **Locale en_GB, TZ Europe/London**: the operator is in Exeter.
- **User `ian` + `NOPASSWD:ALL` sudoers drop-in; root SSH login off.** The
  agent has root by design; the sudoers file is validated with `visudo -c`
  before deployment.

## Filesystem & snapshots

- **btrfs + snapper + grub-btrfs** over LVM/ZFS: in-kernel, snapper is
  packaged and boring, grub-btrfs gives bootable snapshots.
- **Installer keeps its happy path; stage 20 reshapes.** The Debian installer
  can only make a single `@rootfs` subvolume without acrobatics, so INSTALL.md
  asks for a plain btrfs `/` and bootstrap does the rest: rename
  `@rootfs`→`@` (safe while booted, subvolumes are held by id, not name),
  update fstab, `update-grub` **and `grub-install`** (GRUB embeds the
  subvolume path in its core image, skipping grub-install after the rename
  would drop you in a grub rescue shell), then demand one reboot.
- **Layout `@ / @home / @var-log / @snapshots`**, all top-level:
  - `@home`: work survives OS rollbacks.
  - `@var-log`: rollbacks keep the logs that explain what you rolled back
    from.
  - `@snapshots` mounted at `/.snapshots` (snapper's nested `.snapshots` is
    deleted and replaced): snapshots survive replacement of `@` itself.
- **Rollback = rename-and-replace `@`** (`snap rollback`), not
  `snapper rollback`: Debian boots a fixed `subvol=@` (unlike openSUSE's
  default-subvolume scheme), so setting a new default subvolume wouldn't take
  effect. Renaming gives one code path that works both from a live system and
  from a grub-btrfs snapshot boot, and keeps the old root parked as
  `@-pre-rollback-*` for forensics.
- **Timeline snapshots off, number cleanup on** (≤30 kept, ≤10 important):
  timeline is noise; the hook + manual `snap now` create everything worth
  keeping.
- **grub-btrfs pinned to upstream v4.14** *(verified: not packaged in Debian
  trixie; latest release v4.14)*, installed via `make install` from a
  shallow clone; `grub-btrfsd` (inotify-tools) regenerates the GRUB submenu
  on every snapshot.
- **os-prober force-enabled** (`/etc/default/grub.d/claude-os.cfg`): disabled
  by default since Debian 11, and the Windows partition must stay bootable.
- **No btrfs compression, no disk swap.** Compression is a knob nobody asked
  for. Swap is zram (zstd, 50% RAM): nothing to exclude from snapshots, no
  btrfs-swapfile caveats, and it helps the 8 GB-class laptop survive builds.
- **Docker storage driver pinned to overlay2**: on btrfs, docker's btrfs
  driver would nest hundreds of subvolumes under `@`, breaking rollback and
  subvolume deletion. This is load-bearing, not a preference.

## Token-economy environment

- **`/etc/environment` is the primary layer**: pam_env applies it to every
  PAM session **including `ssh host cmd` non-login shells**, the agent's
  main entry point. `environment.d/` covers systemd user services;
  `profile.d/` is belt-and-braces for login shells.
- **mise shims PATH lives in `~/.bashrc` *above* the interactive-exit gate.**
  Debian's bash is compiled with `SSH_SOURCE_BASHRC`, so sshd-invoked
  non-interactive shells source `.bashrc`; putting PATH first makes
  `ssh claude-os.local node -v` work. doctor.sh tests exactly this code path
  (env -i + `SSH_CLIENT=` set).
- **git `core.pager=cat`, not `false`** (spec said `false`): git would try to
  *execute* `false` as the pager and swallow all output on a tty. `cat` is
  the safe spelling of "no pager". Real `user.name`/`user.email` instead of
  placeholders, single-operator appliance.
- **npm/pip/uv/dotnet quieting via env vars** (`NPM_CONFIG_*`, `PIP_*`,
  `UV_NO_PROGRESS`, `DOTNET_NOLOGO`) rather than per-tool config files:
  version-manager-proof (mise swaps node versions; env vars survive).
- **MOTD emptied + update-motd.d de-executed; PS1 `\w \$ `**: every prompt
  character is repeated in every captured transcript.
- **apt: assume-yes, force-confdef/confold, no fancy progress, no colour**, an apt conffile prompt is the canonical wasted turn.

## Toolchain

- **mise via its apt repo through `extrepo`** *(verified: documented route
  for Debian 11+)*: system binary, updated by apt, no curl-pipe drift. Tools
  (`node@lts pnpm@latest go@latest rust@latest uv@latest`) install per-user
  for `ian`, channels, not pinned numbers, so `mise up` tracks currency.
- **.NET SDK 10 (current LTS) from packages.microsoft.com/config/debian/13**
  *(verified: Debian 13 supported, .NET 10/9/8 available)*. System-wide, `dotnet new` works in any shell with zero setup.
- **Python via `uv`** (installed by mise): venvs and tools without touching
  system python3.

## Claude Code (stage 50)

- **Anthropic's signed apt repo, `stable` channel** *(verified: repo at
  downloads.claude.ai/claude-code/apt, package `claude-code`)*; the signing
  key fingerprint is pinned in the stage and verified before the repo is
  trusted. No npm install (per spec), no self-updater surprises, updates
  ride `apt upgrade`.
- **OAuth is a documented manual step**, deliberately not automated.
- **Hook design** *(schema verified against live hooks docs)*: one
  `PreToolUse` hook matching the `Bash` tool; reads `tool_input.command`
  from stdin JSON; regex heuristics for mutating commands (package ops,
  service ops, recursive rm, writes under /etc /usr /boot /opt).
  - **Subcommand-level matching**: `apt list`, `dpkg -l`, `systemctl status`
    and friends are read-only and constant in agent traffic, matching bare
    program names would snapshot on recon. Only mutating subcommands match.
  - **Partitioning tools deliberately excluded** (`fdisk`, `parted`, `mkfs`):
    a root-filesystem snapshot cannot undo partition-table damage, so a
    snapshot there is false comfort. The hook only guards what snapper can
    actually restore. (`test/hook-test.sh` pins all of this behaviour.)
  - **Single snapshots, not pre/post pairs**: pairing needs a PostToolUse
    hook and number plumbing for marginal benefit; number-cleanup prunes
    either way.
  - **Rate-limited** (1 per 10 min, mtime state file in /tmp) so a burst of
    apt commands doesn't mint 30 snapshots.
  - **Contract: always exit 0, always silent**, a broken safety hook must
    degrade to "no snapshot", never to "agent can't run commands".
- **`~/.claude/settings.json` and `CLAUDE.md` are repo-owned and deployed**, hand-edits there die on the next bootstrap, by design (edit the repo).

## Sensor (stage 60)

- **Playwright-managed Chromium** in `/opt/ms-playwright`
  (`PLAYWRIGHT_BROWSERS_PATH` set system-wide) rather than Debian's chromium:
  `--with-deps` installs the system libraries *(verified: Debian 13 is a
  supported Playwright platform; Node 22/24/26 required, mise's node LTS
  qualifies)*.
- **`shot` uses headless Chromium, Xvfb isn't in its path.** Xvfb is still
  installed (spec) for the rare genuinely-headed case via `xvfb-run`.
- Playwright the npm package lives in `/opt/playwright` owned by `ian`,
  pinned by `package.json` (`^1.50`).

## Appliance (stage 70)

- **Key-only SSH is gated on a real key existing** in
  `~ian/.ssh/authorized_keys`: hardening can never lock you out of a fresh
  install. Until then bootstrap logs a warning and doctor SKIPs.
- avahi + libnss-mdns → `claude-os.local`; logind ignores the lid everywhere;
  sleep/suspend/hibernate targets masked.
- **`claude-session` = `tmux new -A -s claude`**: the spec's "systemd user
  service" option was skipped, tmux alone survives SSH drops, and one moving
  part is fewer than two.

## Containers (stage 80)

- **`docker.io` from Debian repos** (spec: fluency beats freshness), user in
  `docker` group, `docker-compose-v2` when trixie carries it. json-file logs
  capped 10 MB×3, output economy applies to disk too.

## Repo/process decisions

- **`snap` name collides with snapd's CLI**, accepted: snapd isn't
  installed on this box and `/usr/local/bin` shadows `/usr/bin` anyway.
  The word had to be one token.
- **Preseed does not partition.** A wrong automated answer nukes Windows; the
  partitioning screen is the one place a human must look at the actual disk.
- **`test/chroot-test.sh`**: Docker Desktop on the build tower turned out to
  be broken (backend crash, no WSL distros), so container-equivalent testing
  runs in a debootstrap'd trixie chroot inside WSL2-Debian instead. Same
  skip-behaviour as docker (`is_container` = "no running systemd").
  Use its `clean` subcommand for fresh runs, a bare `rm -rf` on a chroot
  with live `/proc` `/sys` `/dev` rbinds eats the host (this was learned the
  disposable way: the first WSL build distro died exactly like that and was
  reinstalled in two minutes, which is at least on-message).
- **Companion tests**: `hook-test.sh` (27 cases: regex precision, rate
  limit, garbage-stdin safety), `grub-btrfs-install-test.sh` (pinned release
  still builds on trixie, DESTDIR throwaway), `btrfs-snap-test.sh` (the
  exact rename-and-replace mechanics of `snap rollback`/`prune` on a btrfs
  loop device, validated on WSL2's kernel).
- **Stages log one line per action and nothing when idle**; second bootstrap
  run prints only stage banners. `deploy()` copies files from `config/`, configs are reviewable diffs, never heredocs.
