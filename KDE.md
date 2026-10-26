# KDE Plasma customizations

Everything changed from stock Plasma 6 (Wayland) on this machine. Snapshot taken 2026-10-05.

Most of this lives in `~/.config` and `~/.local/share`. This repo doesn't manage it; only the bits under
[Managed by Nix](#managed-by-nix) are. Konsave profiles exist as backups (`last-thinkpad-config`,
`nix_default_plus`).

The keyboard is **French AZERTY**, so shortcuts use KDE's names for AZERTY keys: `&` `É` `"` are the
1/2/3 number-row keys, `²` is the key left of `&`, and `<` is the extra key between left Shift and `W`.

---

## Keyboard shortcuts

Source: `~/.config/kglobalshortcutsrc`. Custom commands are `.desktop` files in `~/.local/share/applications/net.local.*.desktop`.

### Custom commands

| Shortcut | Name | Command |
|---|---|---|
| `Meta+Shift+Return` | Brave Claude | `brave "https://claude.ai/new"` |
| `Meta+Ctrl+Shift+Return` | Open Perplexity in Brave | `brave "https://www.perplexity.ai"` |
| `Meta+;` | bemoji type | `bemoji -t` |
| `Meta+.` | bemoji copy | `bemoji -c` |
| `Meta+,` | bemoji to Emojipedia | `bemoji --echo` → opens `emojipedia.org/<emoji>` |
| `Meta+É` | mutectl mute | `mutectl mute` |
| `Meta+&` | mutectl unmute | `mutectl unmute` |
| `Meta+"` | mutectl afk | `mutectl afk` |
| `Sleep` key | Lock AFK | `loginctl lock-session && mutectl afk` |
| `Meta+:` | soundboard gui | `packages/soundboard/soundboard gui` |
| `Meta+/`, `Meta+Ctrl+/`, `Meta+Ctrl+:` | soundboard replay | `packages/soundboard/soundboard replay` |
| `Meta+End` | soundboard stop | `packages/soundboard/soundboard stop` |
| `Meta+<` | Focus Discord | `xdotool search --onlyvisible --class discord windowactivate` |
| `Launch (6)` | toggle awpro ANC | switches headphones between ANC and transparency (level 5) via `awpro` |
| `ScrollLock` | ssh-add | `konsole -e ssh-add ~/.ssh/id_ed25519` |
| `Meta+Num+*` | fix brightness | `qdbus … BrightnessControl setBrightness 10000` |
| `Meta+Ctrl+Shift+G` | g-arrival-log | `~/scripts/g-arrival-log` |

### Virtual desktops and activities

There are 4 virtual desktops in a 2×2 grid, and navigation doesn't wrap around at the edges. The desktop shortcuts use the 2×2 block of
keys at the top-left of AZERTY, laid out like the grid:

```
 A │ Z        Desktop 1 │ Desktop 2
───┼───      ───────────┼───────────
 Q │ S        Desktop 3 │ Desktop 4
```

| Action | Yours | KDE default |
|---|---|---|
| Switch to Desktop 1 | `Ctrl+F1`, `Meta+A`, `Meta+Ctrl+A` | `Ctrl+F1`, `Meta+F1` |
| Switch to Desktop 2 | `Ctrl+F2`, `Meta+Z`, `Meta+Ctrl+Z` | `Ctrl+F2`, `Meta+F2` |
| Switch to Desktop 3 | `Ctrl+F3`, `Meta+Q`, `Meta+Ctrl+Q` | `Ctrl+F3`, `Meta+F3` |
| Switch to Desktop 4 | `Ctrl+F4`, `Meta+S`, `Meta+Ctrl+S` | `Ctrl+F4`, `Meta+F4` |
| Switch to activity "Default" | `Meta+F1` | — |
| Switch to activity "nix" | `Meta+Shift+F2` | — |
| Show Activity Switcher | `Meta+W` | `Meta+Q` |
| Walk through activities (reverse) | `Meta+Shift+A` | — |
| Stop Current Activity | — | `Meta+S` |

Activities: **Default** and **nix**.

### Window management (KWin)

| Action | Yours | KDE default |
|---|---|---|
| Maximize Window | `Meta+Up` | `Meta+PgUp` |
| Minimize Window | `Meta+Down` | `Meta+PgDown` |
| Quick Tile Top | `Meta+PgUp` | `Meta+Up` |
| Quick Tile Bottom | `Meta+PgDown` | `Meta+Down` |
| Move Window to Next Screen | `Meta+Shift+D`, `Meta+Shift+Right` | `Meta+Shift+Right` |
| Move Window to Previous Screen | `Meta+Shift+Q`, `Meta+Shift+Left` | `Meta+Shift+Left` |
| Keep Window Above Others | `Meta+Shift+PgUp` | — |
| Keep Window on All Desktops | `Meta+Ctrl+Shift+PgUp` | — |
| Toggle Overview | `Ctrl+Alt+Tab`, `Meta+Tab` | `Meta+W` |
| Walk Through Windows | `Alt+Tab` | `Alt+Tab`, `Meta+Tab` |
| Walk Through Windows (Reverse) | `Alt+Shift+Backtab` | `Alt+Shift+Tab`, `Meta+Shift+Tab` |
| Walk Through Windows of Current App | ``Alt+` `` | ``Alt+` ``, ``Meta+` `` |
| Walk Through Windows of Current App (Reverse) | `Alt+~` | `Alt+~`, `Meta+~` |
| Present Windows (current desktop) | `Ctrl+F9` | `Ctrl+F9`, `Meta+F9` |
| Present Windows (all desktops) | `Launch (C)`, `Ctrl+F10` | `Launch (C)`, `Ctrl+F10`, `Meta+F10` |
| Present Windows (window class) | `Ctrl+F7` | `Ctrl+F7`, `Meta+F7` |
| Activate Window Demanding Attention | `Ctrl+Alt+A` | `Meta+Ctrl+A` |
| Kill Window | `Ctrl+Alt+Esc` | `Meta+Ctrl+Esc` |
| Zoom In | `Meta+=` | `Meta++`, `Meta+=` |

The swaps follow a pattern. Up/Down maximize and minimize, PgUp/PgDown quick-tile. `Q`/`D` around `S`
pick the screen (AZERTY's version of WASD). Every `Meta+` variant that clashed with the desktop or
activity keys was removed.

### Plasma shell and widgets

| Action | Yours | KDE default |
|---|---|---|
| Activate Application Launcher | — | `Meta`, `Alt+F1` |
| Application Launcher widget | `Alt+F1` | — |
| Audio Volume widget | `Meta+~` | — |
| Media Player widget | `Meta+²` | — |
| Clipboard: Automatic Action Popup | `Ctrl+Alt+X` | `Meta+Ctrl+X` |
| Clipboard: Manually Invoke Action | `Ctrl+Alt+R` | — |
| Clipboard: Show Items at Mouse Position | — | `Meta+V` |

A Meta tap no longer opens the launcher. `Alt+F1` still does, through the Kickoff widget's own shortcut.

### Apps and services

| Action | Yours | KDE default |
|---|---|---|
| KRunner | `Search`, `Alt+Space`, `Alt+F2`, `Meta+Space` | `Alt+Space`, `Alt+F2`, `Search` |
| Konsole: New Window | `Meta+Return` (`Ctrl+Alt+T` still launches) | — |
| Spectacle: launch | `Print` | `Print`, `Meta+Shift+S` |
| Spectacle: Rectangular Region | `Meta+Shift+S`, `Meta+Shift+Print` | `Meta+Shift+Print` |
| Emoji Selector | `Meta+Ctrl+Alt+Shift+Space` | `Meta+.`, `Meta+Ctrl+Alt+Shift+Space` |
| Touchpad toggle | `Touchpad Toggle` | `Touchpad Toggle`, `Meta+Ctrl+Touchpad Toggle`, `Meta+Ctrl+Zenkaku Hankaku` |

`Meta+.` was taken from the Emoji Selector for bemoji, and `Meta+Shift+S` moved from "launch Spectacle"
to "region screenshot", which is how Windows does it.

### Session, power, audio, input

| Action | Yours | KDE default |
|---|---|---|
| Shut Down Without Confirmation | `Ctrl+Alt+Shift+PgDown` | — |
| Reboot Without Confirmation | `Ctrl+Alt+Shift+PgUp` | — |
| Log Out Without Confirmation | `Ctrl+Alt+Shift+Del` | — |
| Suspend | — (the `Sleep` key runs "Lock AFK" instead) | `Sleep` |
| Mute Microphone | `Microphone Mute` | `Microphone Mute`, `Meta+Volume Mute` |
| Switch to Next Keyboard Layout | `Launch (5)` | `Meta+Alt+K` |
| Toggle Screen Reader | — | `Meta+Alt+S` |

### Browser extension global shortcuts (Brave)

All of them are unbound so they don't grab keys system-wide:

- Bitwarden: autofill login (`Ctrl+Shift+L`), generate password (`Ctrl+Shift+9`), autofill card/identity, lock vault
- Raindrop.io: open sidebar (`Ctrl+.`), save page (`Ctrl+Shift+S`), open web site

### Konsole in-app shortcuts

Source: `~/.local/share/kxmlgui5/konsole/konsoleui.rc`

| Action | Shortcut |
|---|---|
| Focus split view left / right / up / down | `Alt+Left` / `Alt+Right` / `Alt+Up` / `Alt+Down` |
| Split view left/right | `Ctrl+Shift+D` |
| Split view top/bottom | `Ctrl+Shift+S` |
| Clone tab, Help contents | unbound |

### Cleanup candidates

These entries in `kglobalshortcutsrc` point to `.desktop` files that no longer exist. KDE ignores them, but
several of them still hold keys:

| Stale entry | Shortcut it still holds |
|---|---|
| `bash.desktop` | `Meta+:`, `Meta+!`, `Meta+Home` |
| `bemoji.desktop` / `bemoji-2` / `bemoji-3` | `Meta+.` / `Meta+Ctrl+.` / `Meta+;` |
| `brave.desktop` | `Meta+Shift+Return` |
| `mutectl.desktop` / `mutectl-2` | `Meta+&` / `Meta+É` |
| `play-to-discord-stop.desktop` | `Meta+End` |
| `xdotool.desktop` | `Meta+²` |
| `{bb510259-…}.desktop` | `Meta+Shift+S` |
| `org.kde.kcalc.desktop` | none (KCalc isn't installed) |

Other leftovers:

- **Old activities**: switch entries for "Réunion", "Défaut" and "DANGER", all unbound.
- **`~/.config/khotkeysrc`** (Jan 2025): Plasma 5 hotkeys, which Plasma 6 doesn't run. The ones that
  mattered were recreated as custom commands.
- **Unbound custom commands**: `net.local.brave.desktop` (ChatGPT) and `net.local.flameshot.desktop`.
- **Orphan window rules**: two duplicate rule groups in `kwinrulesrc` (albert, Flameshot) that `[General] rules=` doesn't list.

---

## Appearance

| Setting | Value |
|---|---|
| Global theme | **Amethyst** (in `~/.local/share/plasma/look-and-feel`) |
| Plasma style | Amethyst |
| Colors | Breeze Dark |
| Application style | Breeze (overrides Amethyst's Lightly) |
| Window decoration | Breeze (overrides Amethyst's Lightly) with normal borders |
| Title bar buttons, left | Menu, Keep Above, On All Desktops (`MFS`) |
| Icons | Tela-circle-dark |
| Cursor | Sweet-cursors (comes with the global theme) |
| Splash screen | Amethyst |
| Task switcher | Thumbnail Grid, showing only windows on the current screen |
| Wallpaper | **backdrop** (`com.github.romain-ncls.backdrop`, from `packages/backdrop`) on every desktop of both activities |

**Hidden title bars** (Breeze window decoration exceptions, `breezerc`): Konsole, Spotify and mpv.
Exceptions for Discord, Brave and `.*` (all windows) exist but are turned off.

Also installed locally, but not in use: Orchis, Sweet, Aritim-Dark and Jade themes, plus Papirus and
candy icons.

## KWin behavior and effects

- **Wobbly windows** on (advanced mode, stiffness 20)
- **Blur** tuned: strength 11, noise 4
- **Off**: shake cursor, desktop-change OSD, minimize-all
- **No hot corners**: the top-left corner no longer opens Overview, and the Present Windows / Overview edge triggers are cleared
- **No edge barrier** between screens (`EdgeBarrier=0`)
- **New windows open centered** (`Placement=Centered`)
- **Desktop switching doesn't wrap** (`RollOverDesktops=false`)
- **Extra effects installed** in `~/.local/share/kwin/effects`: kinetic open/close/maximize/minimize/popups animations, glitch

### Window rules (`kwinrulesrc`)

| Window | Rule |
|---|---|
| albert | on all activities |
| Discord | on all activities |
| Spotify | starts on all virtual desktops |
| Flameshot | forced to position 0,0, kept above other windows, not fullscreen |

## Input

| Device | Settings |
|---|---|
| Keyboard | French (`fr`) layout, NumLock on at login |
| Logitech M720 Triathlon | flat acceleration, speed 0.4, normal scroll |
| Touchpad (SYNA311E) | natural scroll, flat acceleration at 1.0, scroll speed 0.3 |
| Touchpad (Synaptics TM3471, old ThinkPad) | natural scroll |

## Panel and widgets

There's one floating bottom panel, 40 px tall. From left to right:

1. Application Launcher (Kickoff), `Alt+F1`
2. Pager
3. Icons-only Task Manager, with System Settings pinned
4. **Claude usage** widget (`org.kde.plasma.claudeusage`, installed locally)
5. System Tray
6. Digital Clock, with week numbers and French holidays
7. Peek at Desktop

The system tray always shows Media Player and **Weather** (Clermont-Ferrand, BBC; temperature shown in
the panel; metric units). It also includes KDE Connect, Vault, Night Light, Brightness, Camera indicator,
Print manager, Input method and KScreen.

Other plasmoids installed: crypto-tracker and plasmusic-toolbar. Wallpaper plugins installed: HTML
wallpaper, Reddit, Smart Video Wallpaper Reborn, Matrix rain, Quarks and Wandering Icon.

## Power, session and lock screen

- **On AC**: the screen never turns off and the machine never auto-suspends
- **Screen lock** after 6 minutes, using the backdrop wallpaper, with media controls hidden on the lock screen
- **Login** starts an empty session instead of restoring the previous one, and Konsole is excluded from session saving
- **Do Not Disturb** doesn't switch on automatically for fullscreen apps
- **Sleep key** locks the screen and sets mutectl to AFK instead of suspending (see [custom commands](#custom-commands))

## Applications

- **Konsole**: "Local default" profile with fish, Fira Code Retina 11, the **DarkOneNuanced** color scheme
  (DarkOneBlue and DarkOneRed are also installed locally), 8 px margin, 90×24 size. Menu bar and status bar
  are hidden, and window size isn't remembered.
- **Dolphin**: full path in the title bar, menu bar hidden, Git plugin on, extended previews (video, ebook,
  RAW, Blender, fonts, …)
- **File dialogs**: show hidden files, detailed tree view
- **Spectacle**: OCR for English and French (see Nix below), red annotation tools
- **Trash**: files deleted after 7 days, size capped at 10%
- **Default apps**: Brave for web links and HTML, mpv for every video type. URL handlers are set for
  `claude-cli`, JetBrains, Fleet, Obsidian, Logseq, GitKraken, Bitwarden, Postman, HTTPie, AFFiNE and SiYuan.
- **Autostart**: Bitwarden, Packet, Remmina applet
- **Locale**: en_US formats, Europe/Paris time zone, French public holidays in the calendar

### KDE Connect

- **This computer's name**: `nixos`
- **Run command** "Lock AFK" from the phone runs `packages/kdeconnect-scripts/lock-afk`. It locks the screen,
  sets mutectl to AFK and pings the phone back.
- **Plugins on**: presenter, remote commands, share. **Off**: media control (both directions), share input devices.

## Managed by Nix

In `hosts/nixos/`:

- `services.desktopManager.plasma6.enable` and `services.displayManager.plasma-login-manager.enable`
- xkb layout `fr`
- Spectacle built with Tesseract OCR (`eng`, `fra`)
- Firewall ports 1714–1764 opened for KDE Connect
- Packages: `kdeconnect-kde`, `konsave`, `qtwebengine` (for the HTML wallpaper), `bemoji`, `bemenu`,
  `wl-clipboard`, `xdotool` (used by the shortcuts above)
- The `backdrop` (wallpaper plugin), `mutectl` and `spotify-vol` packages and services. `soundboard` is run
  straight from `packages/soundboard/` by path
