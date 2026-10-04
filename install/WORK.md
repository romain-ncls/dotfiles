# Work PC: what is left to do

Instructions for the Claude session that sets up the work PC. Read
`../CLAUDE.md` first; everything there applies.

**Machine:** Intel Core Ultra 5 125U (Meteor Lake), integrated Arc graphics
only, laptop. Single boot (no Windows), **LUKS** encryption, otherwise the same
system as the home PC: btrfs subvolumes, snapper, Limine with bootable
snapshots, Plasma on Wayland, the same packages and `$HOME`.

## 1. Write `install/work.sh`

Model it on `install/menadion.sh` and reuse `install/lib.sh` unchanged where
possible. Differences:

- **Disk:** whole disk, fresh GPT. Partitions: a **4 GiB FAT32 ESP** (Limine
  reads only FAT, kernels and snapshot kernels live there;
  `limine-snapper-sync` wants ≥ 4 GiB), and the rest as **LUKS2** holding
  btrfs. Ask the user for the exact disk and confirm with `lsblk` and the model
  name before writing anything.
- **Swap / hibernation:** decide with the user. Options: a btrfs swapfile
  inside LUKS (hibernation needs `resume=` + `resume_offset=` from
  `btrfs inspect-internal map-swapfile -r`), or a separate LUKS swap partition.
  No swap at all if hibernation is not wanted.
- **initramfs:** `HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck sd-btrfs-overlayfs)`.
  `MODULES=(btrfs)`, plus `i915` or `xe` only if early KMS is wanted (no NVIDIA
  here, so the hibernation problem of the home PC does not apply; still test it).
  Add the Logitech modules only if the same receiver is used there.
- **Kernel command line** (`/etc/kernel/cmdline`):
  `rd.luks.name=<luks-uuid>=root root=/dev/mapper/root rootflags=subvol=@ rw quiet loglevel=3`
  (+ `resume=…` if hibernating). Consider `rd.luks.options=discard` for the SSD.
- **UUIDs:** a fresh install creates new ones. Either write them into the repo
  right after formatting (fstab, cmdline), or let the script generate
  `/etc/fstab` with `genfstab -U` and copy the result into the repo afterwards.
- **No Windows:** `system/limine/work.conf` has only the globals (no Windows
  entry), e.g. `timeout: 1`, `remember_last_entry: yes`. No reboot-to-windows.

## 2. Fill in the repo for the work PC

After the first boot, run `just drift` (the user runs it; it needs sudo) and
sort `system/99-unsorted.sh`:

- Host files under `system/files/hosts/work/` (`hostname`, `hosts`, `fstab`,
  `kernel/cmdline`, `mkinitcpio.conf`), declared in `system/50-work.sh` with
  `host /etc/…` lines like `system/50-home.sh`.
- `system/50-work.sh` guards on `$HOSTNAME != menadion`; once the hostname is
  chosen, make it test that hostname explicitly, like `50-home.sh` does.
- Laptop extras to consider with the user: `power-profiles-daemon` (Plasma's
  power profiles), `fwupd`, fingerprint reader (`fprintd`), webcam.
- KDE: per-key settings for this machine go in `home/.kde/work.tsv`.
- Anything common that turns up on both machines goes in `system/10-*.sh`,
  `20-*.sh`, `30-*.sh`, not in `50-work.sh`.

## 3. Manual steps

`docs/manual-steps.md` "Both machines" applies: BIOS (Secure Boot off unless
signing is set up), new SSH key for this machine → GitHub (auth + signing),
`bw login`. Add anything specific to this machine there.
