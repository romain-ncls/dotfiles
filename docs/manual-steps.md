# Manual steps

Everything here is done by hand because it cannot be scripted, or because
scripting it would be riskier than doing it. Do them in order on a new machine.

## Both machines

### Firmware (BIOS)
- CSM **off**. Secure Boot **off** on the home PC; on the laptop it is turned
  on after install, with our own keys ("Secure Boot and TPM unlock" below).
- Home (MSI, Del at POST): `Above 4G Decoding` and `Re-Size BAR Support` **on**.
- Home: Boot → Boot Option #1 = **Limine**, #2 = **Windows Boot Manager**.
  The MSI firmware reverts boot orders set with `efibootmgr`; only this sticks.

### SSH key (one per machine, never synced)
```sh
ssh-keygen -t ed25519 -C "nicolasromain0+$(hostname)@gmail.com"
lodestar apply       # regenerates ~/.config/git/allowed_signers from the new key
```
Then on GitHub → Settings → SSH and GPG keys, add `~/.ssh/id_ed25519.pub`
**twice**: once as an *Authentication key*, once as a *Signing key* (commits
are SSH-signed). Remove the key of a machine that is retired.

### Bitwarden CLI
```sh
bw login          # once; afterwards lodestar runs `bw unlock` itself when a template needs a secret
```

### KDE
- Log out and back in after the first `lodestar apply`: some KWin and
  Plasma settings (Xwayland scale, theme) are only fully applied at login.
- Konsole (hosts with the `konsole` module): right-click the toolbar and hide
  the main and session toolbars. Konsole keeps that in a binary window state
  (`~/.local/state/konsolestaterc`), not in a key the repo could set.

### Readest
- Settings → *Theme* → color theme **Contrast** (for both the library and the
  reader). Readest keeps the color theme in its web view's local storage, not
  in `settings.json`, so the repo cannot set it.
- The library (books, progress, stats) is data, not config: copy
  `~/.local/share/com.bilingify.readest/Readest/` from the old machine if wanted.

## Home PC (MENADION) only

### Windows
- Fast Startup **off**, Hibernate **kept**: Control Panel → Power Options →
  *Choose what the power buttons do* → *Change settings that are currently
  unavailable* → untick *Turn on fast startup*. Check with `powercfg /a`.
- Hardware clock: option C (nothing changed). Both systems sync over NTP; Linux
  keeps the RTC in UTC (`timedatectl` → `RTC in local TZ: no`).
- Never boot Linux out of a hibernated Windows. C: then mounts read-only (the
  `ntfs` driver checks `hiberfil.sys`); resume Windows and shut it down properly.

### Reboot-to-Arch shortcut on the Windows desktop
1. Copy `hosts/menadion/windows/Reboot-to-Arch.ps1` to `C:\Users\nicol\menadion-scripts\`.
2. Right-click the desktop → *New → Shortcut*, location:
   `powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\nicol\menadion-scripts\Reboot-to-Arch.ps1"`
3. Name it *Reboot into Arch Linux*; icon from `%SystemRoot%\System32\shell32.dll`.

The UAC prompt is the only confirmation; unsaved work is discarded.

### mpv on Windows (shares modules/mpv/config/ with Arch)
```powershell
winget install Git.Git
git clone https://github.com/romain-ncls/dotfiles $HOME\dotfiles
powershell -ExecutionPolicy Bypass -File $HOME\dotfiles\modules\mpv\windows\Setup-Mpv.ps1
```
`%APPDATA%\mpv` becomes a junction to `$HOME\dotfiles\modules\mpv\config`; the old folder is
kept as `mpv.backup-<date>`. Both OSes then read the same files: `git pull`
before changing the mpv config on one side, commit and push after.

### Bluetooth devices shared with Windows (MX Anywhere 3S on channel 2)
Both OSes use the same adapter, so a device remembers only the key of the
OS that paired it last. Pair in Windows, then give Arch the same key:
1. In Windows, pair the device (MX Anywhere 3S: channel 2). Shut Windows down
   properly; a hibernated Windows may not have written the key to disk yet.
2. In Arch, with C: mounted on `/mnt/win`:
   ```sh
   bt-windows-keys                      # lists what Windows has paired
   sudo bt-windows-keys "MX Anywhere"   # writes /var/lib/bluetooth/…/info, restarts bluetooth
   ```
Redo both steps after any re-pairing in Windows. Never pair that channel from
Arch, because that replaces the key the mouse holds and breaks Windows. The keys stay
in `/var/lib/bluetooth` and the Windows registry, never in this repo. A
Logitech device gets a different address on each channel, so an old Arch-only
pairing on another channel is a separate entry: `bluetoothctl remove <addr>`.

### Windows boot logo
If the Windows boot animation looks stretched, from an elevated prompt:
`bcdedit /set {globalsettings} highestmode on`.

## Work laptop (wandersail) only

### First boot after `lodestar install`
1. Type the disk passphrase, then log in to Plasma.
2. `lodestar apply`: the home part (KDE settings, shortcuts, home files).
   It asks for the password once.
3. Restore data from the backup with the drive's menu script
   (`bash backup.sh` on the `home-bkp` partition). Pick folders, not the
   whole home: files written for NixOS point into `/nix/store`. The data:
   `~/git`, `~/Documents`, `~/Pictures`, `~/Images`, `~/Music`, `~/scripts`,
   `~/.ssh`, `~/.gnupg`, `~/.kube`, `~/.claude`,
   `~/.local/share/{mkcert,backdrop,silksong-wallpaper,kwalletd,easyeffects,com.bilingify.readest}`,
   `~/.config/{BraveSoftware,JetBrains,kdeconnect,Vencord}`, and the fish
   config (`~/.config/fish`, private, kept out of this repo).
   `~/.ssh` brings back this laptop's own key, already on GitHub: skip
   "SSH key" above, and `lodestar apply` again for `allowed_signers`.
4. Log out and back in.

### Secure Boot and TPM unlock
Once, after `lodestar apply` has installed sbctl and enrolled Limine's config
hash (`ENABLE_ENROLL_LIMINE_CONFIG=yes`). Reboot once at this point: it proves
the enrolled config boots before Secure Boot is on.
1. Keys, then sign Limine with them:
   ```sh
   sudo sbctl create-keys
   sudo limine-enroll-config      # re-enrolls the hash and signs BOOTX64.EFI
   sudo sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi
   sudo sbctl verify              # Limine's binary and fwupd's: signed
   ```
   `-s` saves fwupd's binary in sbctl's list: its pacman hook re-signs it
   when fwupd-efi updates. Firmware updates then go through fwupd as before.
2. Firmware (F10 at POST): Security → Secure Boot Configuration →
   **Secure Boot: enabled**, **Clear Secure Boot keys** (setup mode). Save; HP
   asks for a 4-digit code at the next boot.
3. Back in Arch (setup mode boots unsigned):
   ```sh
   sudo sbctl enroll-keys -m      # -m: keep Microsoft's keys (option ROMs, firmware)
   ```
   Reboot. `sbctl status` and `bootctl status` show Secure Boot **enabled**.
4. **After that reboot**, with Secure Boot enabled (not in the setup-mode
   boot of step 3: the TPM would record Secure Boot off and never unlock),
   bind the disk to the TPM (PCR 7: the Secure Boot state and the key that
   signed what booted). The passphrase stays as a key slot:
   ```sh
   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/255164aa-991a-4b46-a733-3c73fa801fb3
   ```
   Add `--tpm2-with-pin=yes` to also ask a PIN at boot.

Never `sbctl sign` the fallback `EFI/BOOT/BOOTX64.EFI`: it has no config hash
enrolled, so a signed copy would boot any `limine.conf`.

The TPM stops unlocking (the passphrase prompt comes back) when PCR 7 changes:
new Secure Boot keys, a db/dbx update (fwupd), a BIOS update or reset. Re-bind:
`sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/255164aa-…`.

### By hand in Plasma
- Activities (and their shortcuts): their ids change, so they are recreated.
- The panel: Kickoff, Pager, Icons-only Task Manager, Claude Usage, System
  Tray (with Weather and Media Player), Digital Clock (week numbers,
  holidays), Peek at Desktop.
- KDE Connect: the phone's *Lock AFK* command runs `lock-afk`.

### Apps
- Brave: load the Teams extension unpacked from
  `~/dotfiles/modules/mutectl/chrome-extension`.
- JetBrains Toolbox: install GoLand, WebStorm, PyCharm and DataGrip.
- NetworkManager: import the company's OpenVPN profile and the Wi-Fi
  networks (their passwords are in Bitwarden).
