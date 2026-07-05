# Claude OS

A bare-metal Debian 13 configuration optimised as a **native habitat for
Claude Code**: a headless appliance where the agent has root, and safety comes
from btrfs snapshots and cheap disposability instead of permission walls.

Target: a Dell Inspiron 7548 on the home LAN (`claude-os.local`), lid closed,
accessed over SSH from the tower and the Claude Code mobile app. It replaces
the old Zorin partition and leaves the Windows partition bootable.

## The three principles

The OS is never the performance bottleneck — inference latency is. Every
decision here optimises, in order:

1. **Turn economy** — nothing may cost the agent a conversational turn: no
   interactive prompts, no pagers, no missing table-stakes tools, no conffile
   questions.
2. **Output economy** — every byte of stdout costs context tokens: no colour,
   no progress bars, no MOTD, a two-character prompt.
3. **Cheap disposability** — the agent runs as root; its undo button is
   `snap rollback`, its parachute is a bootable-snapshot GRUB menu, and its
   ejector seat is a 20-minute zero-thought reinstall.

Boring is a feature: Debian conventions, bash, apt — the deepest grooves in an
LLM's training data.

## Quickstart

```
# 1. Install Debian 13 netinst with preseed.cfg  -> docs/INSTALL.md
# 2. First boot:
sudo /opt/claude-os/bootstrap.sh     # reshapes btrfs, says "reboot"
sudo reboot
sudo /opt/claude-os/bootstrap.sh     # installs everything else
# 3. Paste SSH keys, authenticate claude          -> docs/INSTALL.md §6-7
sudo /opt/claude-os/doctor.sh        # every line should say OK
```

`bootstrap.sh` is idempotent — run it after every repo change; it is the
reproducibility story. `doctor.sh` is the acceptance test.

## Layout

| Path | What |
|---|---|
| `bootstrap.sh` | entry point; clones/updates the repo, runs stages in order |
| `stages/10..80` | idempotent build stages (base → fs → env → toolchain → claude → sensor → appliance → docker) |
| `config/` | every deployed file, reviewable in the repo — never heredocs |
| `doctor.sh` | verifies the whole spec, `OK`/`FAIL`/`SKIP` per line |
| `docs/INSTALL.md` | USB → netinst → first boot, step by step |
| `docs/ROLLBACK.md` | snapshot rollback, boot-into-snapshot, full reinstall |
| `docs/DESIGN.md` | rationale for every decision |
| `test/chroot-test.sh` | run bootstrap+doctor in a fresh trixie chroot (build-machine CI) |

## The safety model in one paragraph

`snapper` snapshots the root subvolume; a Claude Code `PreToolUse` hook takes
one automatically before mutating commands (rate-limited); `grub-btrfs` makes
every snapshot bootable from the GRUB menu; the `snap` CLI (`now`/`list`/
`diff`/`rollback`/`prune`) makes all of it one token long. `/home` and
`/var/log` are separate subvolumes, so rolling back the OS never eats work or
evidence. If all else fails: netinst USB + `preseed.cfg` + `bootstrap.sh`
rebuild the entire machine in ~20 minutes.
