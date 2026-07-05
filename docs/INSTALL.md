# INSTALL — USB flash → Debian netinst → first boot → bootstrap

Target machine: Dell Inspiron 7548 (Broadwell, 2015), currently dual-booting
Windows + Zorin. Claude OS replaces **only the Zorin partition**. The Windows
partition and the EFI System Partition are never formatted.

Total time: ~20 minutes of installer + ~15 minutes of unattended bootstrap.

## 1. Flash the USB (on the Windows tower)

1. Download the Debian 13 (trixie) **amd64 netinst** ISO from
   https://www.debian.org/download (non-free firmware is included by default
   since Debian 12).
2. Flash with [Rufus](https://rufus.ie): select the ISO, keep the default
   **ISO mode** (not dd mode) so the USB stays writable.
3. Copy `preseed.cfg` from this repo to the **root of the USB drive**.

## 2. Boot the installer

1. Plug in USB + ethernet if available (WiFi works too — firmware is on the
   ISO; you'll be asked to pick a network and passphrase).
2. Power on, hammer **F12** for the Dell one-time boot menu, pick the USB
   (UEFI entry if both are offered).
3. At the Debian boot menu highlight **Install** (or *Advanced options →
   Automated install*) and press **e** (UEFI/GRUB) or **Tab** (BIOS). Append
   to the `linux` line:

   ```
   auto=true priority=critical file=/cdrom/preseed.cfg
   ```

   then **Ctrl-X**/**Enter** to boot. (`/cdrom` is the USB.)

The preseed answers everything except **passwords** (asked on purpose — no
default credentials live in this repo) and **partitioning** (deliberately
interactive; see next section — an automated guess could destroy Windows).

## 3. Partitioning — the only careful part

When the installer reaches partitioning, choose **Manual**. You will see
something like (order/sizes vary):

| Partition | Size | Type | Identity | Action |
|---|---|---|---|---|
| #1 | ~100–650 MB | EFI System (FAT32) | shared bootloader | **keep, do NOT format** |
| #2 | ~16–128 MB | Microsoft reserved | Windows | don't touch |
| #3 | large | NTFS | Windows C: | don't touch |
| #4/#5 | large | ext4 | **Zorin root** | reuse as btrfs / |
| maybe | 2–8 GB | swap | Zorin swap | see below |
| maybe | ~500 MB–1 GB | NTFS | Windows recovery | don't touch |

Steps:

1. Select the **Zorin ext4 partition** (identify it by being ext4 and by its
   size — the only Linux filesystem partition). Set:
   - Use as: **btrfs journaling file system**
   - Format the partition: **yes, format it**
   - Mount point: **/**
2. Select the **EFI System Partition** and confirm it shows *Use as: EFI
   System Partition*. Do **not** set "format". (Windows boots from here.)
3. If Zorin had a **swap partition**: either leave it as swap (harmless) or
   set it to *do not use* — Claude OS uses zram swap, not disk swap. If the
   installer warns "you have not selected any swap space", answer **No**
   (continue without swap).
4. **Finish partitioning and write changes to disk.** On the confirmation
   screen verify that **exactly one** partition is listed to be formatted
   (the ex-Zorin one, as btrfs). If anything else says "format", go back.

The installer creates a single btrfs subvolume `@rootfs`. That's expected —
`bootstrap.sh` reshapes it into the final `@ / @home / @snapshots / @var-log`
layout on first run (this is why the installer's thin btrfs support doesn't
matter).

## 4. Finish the install

- Passwords: set the `ian` password when asked (root login is disabled).
- GRUB: the preseed pre-answers "install alongside other OS" — if asked where
  to install, take the default disk (the internal one). os-prober support for
  the Windows entry is finalised by bootstrap later.
- Remove the USB when it reboots.

## 5. First boot — bootstrap

Log in as `ian` on the console (or `ssh ian@<ip>` — password auth is still on
at this point; get the IP from `ip -4 a` on the console or your router).

```bash
# repo should already be at /opt/claude-os (preseed clones it); if not:
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/PointOfPressure/claude-os.git /opt/claude-os

sudo /opt/claude-os/bootstrap.sh
```

The first run renames `@rootfs`→`@`, splits out `@home`/`@var-log`/
`@snapshots`, refreshes GRUB, and ends with **ACTION REQUIRED: reboot**:

```bash
sudo reboot
# ...log back in...
sudo /opt/claude-os/bootstrap.sh   # now runs to completion (~15 min of downloads)
```

## 6. SSH keys → hardening

Password auth stays on **until a real key exists** (no-lockout rule). From the
tower (PowerShell):

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ian@claude-os.local "cat >> ~/.ssh/authorized_keys"
```

Add the phone's key the same way (copy it from the Claude Code app / your SSH
client's key export). Then:

```bash
sudo /opt/claude-os/bootstrap.sh 70    # re-runs the appliance stage
```

which turns off password auth and root login. Alternatively: paste keys into
`config/ssh/authorized_keys` in the repo (then the repo is authoritative and
reinstalls carry the keys).

## 7. Authenticate Claude Code (interactive, once)

```bash
ssh -t ian@claude-os.local claude
```

Follow the OAuth prompt: open the printed URL on any browser (tower/phone),
log in, paste the code back. Credentials persist in `~/.claude`.

## 8. Verify

```bash
sudo /opt/claude-os/doctor.sh
```

Every line should read `OK` (the `ssh key-only auth` line shows `SKIP` until
step 6 is done). Because the build machine can only test in containers, give
these **hardware-only checks** special attention on first boot:

- `subvol:` lines — the four-subvolume layout is live
- `snapper list works`, `snapper-cleanup.timer active`
- `grub cfg lists snapshots` and `grub-btrfsd active`
- `grub cfg lists Windows` — **dual boot survived**; also eyeball the GRUB
  menu on a reboot before you close the lid for good
- `docker daemon runs containers`
- `zram swap active`, `sleep targets masked`, `avahi active`

## 9. Appliance-ify

- BIOS (F2): set *AC Power Recovery / Auto-On* if you want it to survive power
  cuts (optional).
- Close the lid (logind ignores it), park it near the router.
- From anywhere: `ssh ian@claude-os.local`, then `claude-session` for a
  tmux-persistent agent session.
