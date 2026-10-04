# Installing from the live USB

`install/<host>.sh` turns an empty (or previous) Arch partition into a system
that already matches the repo: packages, `/etc`, unit links and modes all come
from `system/*.sh`, the same files `just apply-system` uses. `lib.sh` holds the
steps both machines share; each host script holds its disk layout and checks.

| host | script | disk |
|---|---|---|
| MENADION (home) | `menadion.sh` | reuses p1 (shared ESP), reformats p5/p6 with the UUIDs in the repo's fstab; Windows untouched |
| work PC | not written yet — see [WORK.md](WORK.md) | |

## Before booting the USB

- Home: Windows shut down properly (not hibernated), Fast Startup off.
- Anything worth keeping on the Arch partition is backed up: it is erased.
- Write the Arch ISO to a USB stick (Rufus in DD mode, or `dd`), Secure Boot off.

## On the live USB

```sh
loadkeys fr
iwctl station wlan0 connect "SSID"     # or plug in ethernet
pacman -Sy --needed git
git clone https://github.com/romain-ncls/dotfiles /root/dotfiles
bash /root/dotfiles/install/menadion.sh
```

The script checks it is on the right disk (partition types, the ESP's UUID,
Windows' boot manager on the ESP, NTFS on p3) and asks you to type the hostname
before it erases anything. It then asks for your user's and root's passwords,
and builds the AUR packages (~10 min). At the end it unmounts everything.

## After the first boot

1. BIOS (Del): Boot Option #1 = **Limine** (the MSI firmware ignores efibootmgr's order).
2. Log in, then:
   ```sh
   cd ~/dotfiles
   chezmoi init --source ~/dotfiles   # menadion → role "home"
   just apply                         # system part should be a no-op; home part writes $HOME
   just drift                         # must be clean
   ```
3. Log out and back in (KDE theme, scale).
4. [docs/manual-steps.md](../docs/manual-steps.md): new SSH key → GitHub (auth + signing), `bw login`.

## If something fails halfway

The script stops at the first error. Everything it changes is on the Arch
partitions, which it formats again on the next run, so rerunning it is safe.
The ESP is only touched by removing the previous Arch files and by
`limine-install`; Windows boots from its own NVRAM entry regardless
(F11 at POST → Windows Boot Manager).
