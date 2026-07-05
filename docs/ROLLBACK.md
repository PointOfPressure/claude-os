# ROLLBACK — the undo button, three depths

The safety model: snapper snapshots of the root subvolume (`@`), taken
automatically before mutating agent commands (PreToolUse hook) and manually
via `snap now`. `/home` and `/var/log` are separate subvolumes — **no rollback
below touches your files or your logs**.

Snapshots live in the top-level `@snapshots` subvolume (mounted at
`/.snapshots`), so they survive even replacing `@` entirely.

## Depth 1 — live rollback (system boots, userspace is wrong)

```bash
snap list                 # find the number from before the damage
snap diff 42              # optional: see what changed since 42
snap rollback 42
sudo reboot
```

What `snap rollback` does: renames the current root subvolume to
`@-pre-rollback-<timestamp>` (kept for forensics), then makes a writable copy
of snapshot 42 as the new `@`. Nothing else moves. After verifying the system,
`snap prune` deletes the parked old root.

## Depth 2 — rollback from GRUB (userspace won't boot)

1. Power on with the lid open (or attach a screen) — at the **GRUB menu**
   pick the **snapshots submenu** (added by grub-btrfs; it lists every
   snapper snapshot with date and description).
2. Boot the newest snapshot from *before* the damage. This boots read-only —
   expect grumbling from services; you only need a shell.
3. Log in as `ian` and run exactly the Depth-1 procedure:

   ```bash
   snap rollback <that snapshot's number>
   sudo reboot
   ```

   This works from a snapshot boot because `snap rollback` only writes to the
   btrfs top level, not to the (read-only) running root.

4. Boot normally.

If GRUB's snapshot submenu is missing but GRUB itself works: boot the normal
entry with `systemd.unit=rescue.target` appended (press `e` to edit), then run
the same `snap rollback`.

## Depth 3 — full reinstall (~20 minutes, zero thought)

For when the filesystem or bootloader is beyond saving, or the machine should
simply be factory-reset:

1. Flash/reuse the netinst USB with `preseed.cfg` (INSTALL.md §1–2).
2. Reinstall: the only manual inputs are the partitioning screen (format the
   same btrfs partition, keep ESP + Windows untouched) and two passwords.
   ~10 minutes.
3. First boot: `sudo /opt/claude-os/bootstrap.sh` → reboot → run it again.
   ~10 minutes, unattended.
4. Paste SSH keys + `claude` OAuth (INSTALL.md §6–7).

Everything that matters is either in this repo (system config), in git
remotes (work), or disposable — that's the design contract. Anything in
`/home` you weren't ready to lose was already a mistake.

## Snapshot hygiene

- Cleanup is automatic: `NUMBER_LIMIT=30` recent + `snapper-cleanup.timer`.
- The hook rate-limits itself (max 1 snapshot / 10 min).
- `snap prune` = run number-cleanup now **and** delete parked
  `@-pre-rollback-*` roots.
- Disk pressure check: `sudo btrfs filesystem usage / | head -5` and
  `snap list | wc -l`.
