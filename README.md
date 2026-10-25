# Claude OS

<p align="center"><code>sudo /opt/claude-os/bootstrap.sh</code></p>

A Debian 13 setup for running Claude Code on bare metal as root, made safe by btrfs snapshots and a fast reinstall, not permission prompts.

Built for a Dell Inspiron 7548 on the LAN (`claude-os.local`), lid closed,
reached over SSH. It replaces a Zorin partition and leaves Windows bootable.

Inference latency is the bottleneck, not the OS. It optimises for, in order:

1. Nothing may cost the agent a turn: no interactive prompts, no pagers, no
   missing tools, no conffile questions.
2. Every byte of stdout costs context: no colour, no progress bars, no MOTD, a
   two-character prompt.
3. The agent runs as root. Undo is `snap rollback`, the fallback is a bootable
   snapshot in the GRUB menu, and the last resort is a 20-minute reinstall.

Debian, bash and apt throughout: the best represented in LLM training data.

## Usage

```
# 1. Install Debian 13 netinst with preseed.cfg  -> docs/INSTALL.md
# 2. First boot:
sudo /opt/claude-os/bootstrap.sh     # reshapes btrfs, says "reboot"
sudo reboot
sudo /opt/claude-os/bootstrap.sh     # installs everything else
# 3. Paste SSH keys: authenticate claude          -> docs/INSTALL.md §6-7
sudo /opt/claude-os/doctor.sh        # every line should say OK
```

`bootstrap.sh` is idempotent; rerun it after any repo change. `doctor.sh` is
the acceptance test.

## How it works

`snapper` snapshots the root subvolume; a rate-limited `PreToolUse` hook takes
one before mutating commands. `grub-btrfs` makes every
snapshot bootable from the GRUB menu. The `snap` CLI wraps `now`, `list`,
`diff`, `rollback` and `prune`.

`/home` and `/var/log` are separate subvolumes, so an OS rollback keeps work
and logs. Failing all that, a netinst USB with `preseed.cfg` and
`bootstrap.sh` rebuilds the machine in about 20 minutes.

<details><summary>Layout</summary>

| Path | What |
|---|---|
| `bootstrap.sh` | entry point; clones or updates the repo, runs stages in order |
| `stages/10..80` | idempotent build stages: base, fs, env, toolchain, claude, sensor, appliance, docker |
| `config/` | every deployed file, in the repo rather than in heredocs |
| `doctor.sh` | verifies the spec, `OK`/`FAIL`/`SKIP` per line |
| `docs/INSTALL.md` | USB to netinst to first boot |
| `docs/ROLLBACK.md` | snapshot rollback, boot into snapshot, full reinstall |
| `docs/DESIGN.md` | why each decision was made |
| `test/chroot-test.sh` | bootstrap and doctor in a fresh trixie chroot |

</details>
