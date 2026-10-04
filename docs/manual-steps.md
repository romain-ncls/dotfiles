# Manual steps

Everything here is done by hand because it cannot be scripted, or because
scripting it would be riskier than doing it. Do them in order on a new machine.

## Both machines

### Firmware (BIOS)
- Secure Boot **off**, CSM **off**.
- Home (MSI, Del at POST): `Above 4G Decoding` and `Re-Size BAR Support` **on**.
- Home: Boot → Boot Option #1 = **Limine**, #2 = **Windows Boot Manager**.
  The MSI firmware reverts boot orders set with `efibootmgr`; only this sticks.

### SSH key (one per machine, never synced)
```sh
ssh-keygen -t ed25519 -C "nicolasromain0+$(hostname)@gmail.com"
chezmoi apply        # regenerates ~/.config/git/allowed_signers from the new key
```
Then on GitHub → Settings → SSH and GPG keys, add `~/.ssh/id_ed25519.pub`
**twice**: once as an *Authentication key*, once as a *Signing key* (commits
are SSH-signed). Remove the key of a machine that is retired.

### Bitwarden CLI
```sh
bw login          # once; afterwards chezmoi runs `bw unlock` itself when a template needs a secret
```

### KDE
- Log out and back in after the first `just apply-home`: some KWin and
  Plasma settings (Xwayland scale, theme) are only fully applied at login.

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
1. Copy `windows/Reboot-to-Arch.ps1` to `C:\Users\nicol\menadion-scripts\`.
2. Right-click the desktop → *New → Shortcut*, location:
   `powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\nicol\menadion-scripts\Reboot-to-Arch.ps1"`
3. Name it *Reboot into Arch Linux*; icon from `%SystemRoot%\System32\shell32.dll`.

The UAC prompt is the only confirmation; unsaved work is discarded.

### mpv on Windows (shares mpv/ with Arch)
```powershell
winget install Git.Git
git clone https://github.com/romain-ncls/dotfiles $HOME\dotfiles
powershell -ExecutionPolicy Bypass -File $HOME\dotfiles\windows\Setup-Mpv.ps1
```
`%APPDATA%\mpv` becomes a junction to `$HOME\dotfiles\mpv`; the old folder is
kept as `mpv.backup-<date>`. Both OSes then read the same files: `git pull`
before changing the mpv config on one side, commit and push after.

### Bluetooth devices shared with Windows (MX Anywhere 3S on channel 2)
Both OSes use the same adapter, so a device remembers only the key of the
OS that paired it last. Pair in Windows, then give Arch the same key:
1. In Windows, pair the device (MX Anywhere 3S: channel 2). Shut Windows down
   properly; a hibernated Windows may not have written the key to disk yet.
2. In Arch, with C: mounted on `/mnt/win`:
   ```sh
   scripts/bt-windows-keys                      # lists what Windows has paired
   sudo scripts/bt-windows-keys "MX Anywhere"   # writes /var/lib/bluetooth/…/info, restarts bluetooth
   ```
Redo both steps after any re-pairing in Windows. Never pair that channel from
Arch, because that replaces the key the mouse holds and breaks Windows. The keys stay
in `/var/lib/bluetooth` and the Windows registry, never in this repo. A
Logitech device gets a different address on each channel, so an old Arch-only
pairing on another channel is a separate entry: `bluetoothctl remove <addr>`.

### Windows boot logo
If the Windows boot animation looks stretched, from an elevated prompt:
`bcdedit /set {globalsettings} highestmode on`.
