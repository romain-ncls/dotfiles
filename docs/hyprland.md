# Hyprland on wandersail (plan)

A Hyprland session next to Plasma on the work laptop, with our own shell in
Quickshell (**shadesmar**, its Go helper **spanreed**) and a theme made from
scratch (**lumar**). Names from the Cosmere: Shadesmar, the realm beneath the
physical one; the spanreed, Roshar's paired pens that carry messages; Lumar,
Tress's planet of seas of colored spores. Plasma stays installed and stays the
daily session until this one is ready; then it stays as the fallback. Nalthis
is not ported. Branch `feat/hyprland`, based on `feat/nalthis-darkly` (what
the machine runs).

Versions planned against (Arch, 2 Nov 2026): Hyprland 0.57.0, Quickshell
0.3.2. Hyprland's config is Lua: 0.57 removed the old hyprlang format, and
most of what is online (and in models' memory) is still hyprlang. Check the
wiki (wiki.hypr.land, which tracks git main) and the 0.57 source before
writing anything; the wiki's own animation examples use a `curve` key 0.57
rejects (`bezier` or `spring`).

## The workflow to keep

- One desktop = one workspace on each side screen; **the side screens switch
  together**, as in KDE.
- Four desktops in a **2×2 grid**: direct jumps (Meta+A/Z/Q/S, Ctrl+F1..F4)
  and moves up/down/left/right, the animation sliding the way you move.
- **The middle screen (the laptop's) has one workspace of its own** that
  never switches: Discord there, and the Teams web app as the other window
  (one or the other fills it). Discord always stays in view, at least its
  servers and channels: who is in the voice channel.
- **Spotify is a scratchpad on the middle screen**: a shortcut shows it over
  Discord, leaving Discord's left side (servers and channel list, about the
  first 375 px) uncovered, and hides it again.
- **The terminal from Meta+Return always opens floating**; from there it goes
  anywhere (over a window, into the tape at half width, two side by side).
- What the KDE habits are for: one window filling each screen and quick
  switching between them. Hyprland's own ways of doing that come first
  (below), KDE's stacking model only if they don't stick.
- **Shortcuts stay close to today's at first** (KDE's bindings, below);
  more keyboard-driven ones can come later.
- Every shortcut the modules declare (bemoji, mutectl, soundboard, awpro,
  spotify-vol, ssh-add, Claude in Brave…), on the French AZERTY layout.

## Decisions

- **The scrolling layout, embraced rather than bent into KWin.** Each
  workspace is a tape of columns (`layout = "scrolling"`, built into 0.57,
  wiki: configuring/layouts/scrolling-layout). Columns are full width by
  default (`scrolling.column_width = 1.0`): one window per screen, like a
  maximized one, the others beside it. Alt+Tab becomes moving along the
  tape (`hl.dsp.layout("focus r")`, wrapping); the shell's switcher with
  previews comes later. The terminal from Meta+Return opens floating
  (`exec_cmd(cmd, { float = true, … })`: the rule comes with that launch,
  not with the app); tiled, it takes half width (`scrolling_width = 0.5`):
  two side by side fill a screen; `colresize +conf` cycles
  1/3, 1/2, 2/3, full; `consume`/`expel` stack windows in a column; a floating
  toggle puts it over the other windows. Touchpad swipes scroll the tape.
  Floating is for dialogs, picture-in-picture and pinned windows only.
  Plan B if the tape doesn't stick: everything floating, maximize as a
  window state, quick tile by binds (KDE's model); or monocle.
- **The middle screen: a workspace of its own, a scratchpad over it.** No
  pinning (only floating windows can be pinned, and they'd cover the tape).
  The laptop's workspace (a name, `comms`, bound to the laptop's panel, kept
  out of the grid) holds Discord and Teams (Brave's web app) as full-width
  columns, opened there by window rules. Spotify lives on a special
  workspace (Hyprland's scratchpad), floating, from x = 375 px to the right
  edge, the full height under the bar. Not a rule: Spotify (XWayland) names
  its window after it opens, so grid.lua places it on `window.class`, and
  again on the shortcut if it left. The shortcut focuses the laptop's
  screen, then toggles it (a special workspace opens on the focused screen),
  so it always shows there; hiding it gives the focus back to the window
  that had it. `decoration.dim_special = 0`, or the uncovered strip of
  Discord is dimmed.
- **The grid is Lua in the compositor config.** Workspace ids are numbered per
  side screen, row by row (desktop d on the n-th side screen: `(n-1)*4 + d`),
  each bound to its screen by EDID description (workspace rules: else a
  workspace that doesn't exist yet is made on the focused screen). A switch
  computes the neighbour, sets the workspace animation's style and calls
  `set_workspace` on the side monitors; the middle screen's workspace never
  moves. The bar learns the desktop shown from the grid's own event
  (`hl.dsp.event`, `custom>>grid d`): Hyprland reports a workspace change
  only for the focused screen.
- **The slides are a plugin of ours, hyprslide** (`modules/hyprslide`, C++,
  two hooks). Hyprland slides sideways or up and down only, the direction
  from the ids' order, and draws during a slide the columns the scrolling
  layout keeps beside the screen, which then cross it. hyprslide sets the
  workspace's offset on both axes, the way the grid says the desktop lies
  (`hl.plugin.hyprslide.towards(dx, dy)` around `set_workspace`), and leaves
  out the tiled windows whose middle is off the screen while their workspace
  slides: KDE's slide, diagonals included. Plugins must match the exact
  Hyprland build, so lodestar rebuilds it with each new Hyprland
  (`pkg: built-against: [hyprland]`); Hyprland refuses one built for
  another, and the grid then falls back to short slides that fade (10 %,
  so the columns barely show) and a fade for a diagonal. Third-party
  plugins stay out: they lag behind Hyprland (hyprtasking doesn't compile on
  0.57 yet, hyprexpo is gone). An overview of the grid, if wanted, comes
  later in the shell.
- **Our own shell in Quickshell, not Noctalia or another ready-made shell.**
  Noctalia 5 is native C++ with no QML, so the Silksong scene can't run in it;
  Dux Shell (ex-DankMaterialShell) and Caelestia are large, weekly-moving
  codebases to fork. Quickshell has what we need natively: layer-shell
  windows, session lock with PAM, Hyprland IPC, notifications server, tray,
  MPRIS, PipeWire, UPower, Bluetooth, NetworkManager, polkit agent, idle
  monitor and inhibitor, global shortcuts, live window previews
  (`ScreencopyView`). Omarchy 4 made the same move (one Quickshell process in
  place of waybar, mako, swayosd, hyprlock, hypridle, walker…): its `shell/`
  is our reference code, with Dux Shell's (github.com/duxlabs-dev/dux-shell,
  Quickshell with a Go daemon, as ours): its consistency and the way it's
  built are the model, not its Material look.
- **The Silksong scene is ported to Quickshell, not rewritten in Rust.** Its
  cost is GPU work a Rust renderer would do the same; the scene itself
  imports only QtQuick. What changes: `main.qml` (the Plasma wallpaper
  wrapper) becomes a background-layer window per screen, `Pauser.qml` (KDE's
  task manager) reads Hyprland's windows, and the lock UI drops KDE's locker,
  battery, sessions and keyboard indicator for `WlSessionLock`, PAM and
  UPower. `bench.py` moves to a headless Hyprland and decides whether
  anything (`life.js`) is worth more. Hyprland keeps sending frame callbacks
  to a wallpaper that windows cover, so the scene must stand still itself, as
  it already does on the desktop.
- **A small Go helper beside the shell, `spanreed`,** for what QML can't
  do: own D-Bus names and talk to logind. It serves
  `org.kde.osdService.showText` (backdrop and spotify-vol call it: they stay
  as they are), `org.freedesktop.ScreenSaver` inhibits (browsers and video
  players; Omarchy's open bug #6475 is not owning it), and logind's `Lock`
  and `PrepareForSleep` (`loginctl lock-session` from mutectl's Lock AFK, lock
  before suspend and hibernate within a delay inhibitor); it forwards to the
  shell with `qs ipc call`.
- **Shortcuts are declared once.** lodestar turns every `shortcuts:` entry
  with `run:` into a Hyprland bind (a generated Lua file the config requires),
  translating KDE's key names: `Meta` → `SUPER`, `Launch (5)` → `XF86Launch5`,
  `²` → `twosuperior`, `É` → `eacute`… (Hyprland resolves a bind against the
  first layout's unshifted keysyms, so Meta+~ is `SUPER + SHIFT + twosuperior`).
  Entries with `component:`/`action:` are KDE's own actions: their
  equivalents are written by hand in the Hyprland config.
- **Started by `start-hyprland`** (the official launcher, a watchdog with a
  safe mode) from the Plasma login screen's session list. Hyprland 0.57
  starts `hyprland-session.target` itself, bound to `graphical-session.target`,
  so our user units start in both sessions; those that only work in Plasma
  for now get `ConditionEnvironment=XDG_CURRENT_DESKTOP=KDE` (backdrop, and
  logi-smartshift until it reads Hyprland's events). That target doesn't
  pull in `xdg-desktop-autostart.target`: a drop-in adds it, or the XDG
  autostart entries wouldn't start (`pam_kwallet_init`, the KDE Connect
  daemon, Bitwarden, Packet, limine-snapper-notify, xdg-user-dirs); those
  marked `OnlyShowIn=KDE` (plasmashell, powerdevil, KDE's polkit agent…)
  stay out by themselves. Plasma's startup also reads `environment.d`
  (gpg-ssh's `SSH_AUTH_SOCK`: git's signing, ssh-add on ScrollLock), and
  Hyprland's doesn't: `session.lua` runs systemd's generator and sets what it
  gives.
- **Updates read before they land, not held.** 0.55 and 0.57 both broke
  configs, but `IgnorePkg` would be a partial upgrade: a held Hyprland breaks
  when aquamarine or hyprutils move under it, and Arch rebuilds Quickshell
  with each Qt (Omarchy's Quickshell broke on a Qt update because they ship
  their own). So everything upgrades together, the release notes read first
  (later: `lodestar upgrade` stopping on a new Hyprland or Quickshell minor
  version), and `Hyprland --verify-config` right after.

## Development

No test user: the real test is romain's own session. Until it's enough to
work in (Phases: first login), it's built in:

1. **Nested, inside Plasma**: `Hyprland` started as romain in a window,
   under `dbus-run-session` (its own session bus, so its shell's
   notifications and tray don't fight Plasma's), with a dev config. Claude can
   start it, query it (`hyprctl -j`, `hyprctl eval`), screenshot it (`grim`)
   and stop it.
2. **Headless**, for automated checks and screenshots: Hyprland with no
   display, headless outputs laid out like the desk (`hyprctl output create
   headless`), permissions not enforced so `grim` works. The shell's and the
   scene's benches run here.

Then romain logs out of Plasma and into Hyprland, and works there; Claude
runs inside it and sees the live session (`hyprctl -j`, the shell's logs),
and keeps screenshots and experiments to the nested and headless ones. The
two sessions are never open at once: Plasma's parts and our daemons are
user units of one user manager. Plasma stays in the login screen's list,
as the fallback.

Every config change: `Hyprland --verify-config`, `hyprctl configerrors`, then
the result checked with `hyprctl -j` or a screenshot. `~/.config/hypr` and
the shell's folder are this repo's folders: try changes on a copy
(`HYPR_DEV_CONFIG=<copy>/hyprland.lua dev/headless.sh`, `qs -p <copy>`),
then copy them back. The shell reloads on save (a `//@ pragma` needs a
restart of `shadesmar.service`); Hyprland's Lua config doesn't: `hyprctl
reload`.

## Repo layout (to be confirmed as it's built)

- `modules/hyprland/`: packages, `home/.config/hypr/` (Lua: `hyprland.lua`
  requiring `monitors`, `grid`, `windows`, `binds`, `input`, `looknfeel`,
  `autostart`; LuaLS stubs from `/usr/share/hypr/stubs`), the dev rig
  (`dev/nested.sh`, `dev/headless.sh`).
- `modules/hyprslide/`: the plugin (`pkg/`: its C++ and PKGBUILD).
- `modules/shadesmar/`: the Quickshell config (`~/.config/quickshell/shadesmar/`,
  linked, edited in place) and the Go helper, spanreed (`pkg/`).
- `modules/lumar/`: the theme (below).
- `modules/silksong/wallpaper/quickshell/`: the scene's wrappers; the scene
  files move to a folder both wrappers import while Plasma still uses them.
- lodestar: the shortcut translation (Go, with tests).

Quickshell 0.3 no longer resolves a config's symlinks: a linked config gets
its own shell id and state folder. Fine, but link the same path everywhere.

## Phases

1. **Base.** The `hyprland` module (packages: hyprland, quickshell,
   xdg-desktop-portal-hyprland, hyprland-guiutils, ghostty, grim, slurp,
   wl-clipboard…), added to wandersail; the nested and headless rigs. Plasma
   must not change: `lodestar plan` shows only additions.
2. **First login: enough to work.** What romain needs: the workspaces,
   moving windows, locking the screen; and what a working day needs
   around them. Stand-ins from the Hypr project and others do what
   shadesmar will do later, so the first login comes early:
   - Compositor: monitors by EDID description (the desk's BenQs, the laptop
     alone: replaces `work-screens`), the 2×2 grid on the side screens,
     `comms` and the Spotify scratchpad on the middle one, hotplug (the
     laptop alone keeps four desktops), the scrolling layout (column widths
     per app, floating rules for dialogs and picture-in-picture), the binds
     (Binds, below), input (per-device acceleration as `flat-mice` and the
     host file set it, touchpad, repeat, Num Lock, AZERTY).
   - Every module's shortcuts: the lodestar translation.
   - Lock: hyprlock (PAM) and hypridle (idle, `loginctl lock-session` for
     Lock AFK, lock before sleep, the lid), `allow_session_lock_restore`.
     Replaced by shadesmar's lock in phase 5.
   - shadesmar's first bar: desktops, clock, battery, tray (Discord, KDE
     Connect), volume.
   - Stand-ins: mako (notifications: Discord and others freeze without a
     notification server), fuzzel (launcher), KDE's polkit agent (already
     installed), grim and slurp on Print, volume, brightness and media keys
     on `wpctl`, `brightnessctl` and `playerctl`, a plain wallpaper.
   - The session's plumbing (Decisions and Secrets): XDG autostart, the
     Plasma-only units' condition, `pam_kwallet_init`, one secret store
     pinned for Brave and VS Code, nm-applet for networks and the VPN's
     prompts, the portals, the Sleep key and the lid.
   - Apps look as in Plasma (the same GTK files and `kdeglobals`, Qt through
     KDE's platform plugin): no theme work before lumar.
3. **shadesmar grows**, replacing the stand-ins one by one, in the live
   session: the launcher, notifications, the OSD with spanreed (backdrop's and
   spotify-vol's calls work again), network, Bluetooth, power profiles,
   clipboard history (Alt+Tab with previews: dropped, below). Done: the
   launcher (apps by name, the most launched first, or a command; Hyprland
   starts them, so a restart of the shell leaves them be), notifications
   (popups, actions, a history in the bar, Do not disturb), the OSD
   (PipeWire's volume and mute, the brightness from its binds, spanreed's
   calls), the overview (Meta+Tab), and the bar's popups, as Plasma's tray:
   the clipboard's history (cliphist, recorded by clipboard-history.service),
   the network (Wi-Fi, the cable, the VPNs through nmcli; nm-applet stays
   for its prompts, its icon hidden), Bluetooth (no pairing agent yet: a
   device wanting a PIN typed needs bluetoothctl), the sound (devices,
   volume, the microphone; Meta+~), the battery (power profiles,
   brightness).
4. **lumar, from scratch.** One palette, templates rendered at apply (Go
   templates, as now): Hyprland, shadesmar, Ghostty, libadwaita and adw-gtk3
   (below, Apps and toolkits), qt6ct for the few Qt apps, then each app with
   its own UI (Brave, Discord's Vencord CSS, VS Code, JetBrains, Obsidian,
   GitKraken…), Omarchy's way: most of the work is there. The GNOME apps
   replace the KDE ones then. GTK's files are shared by both sessions (and
   Nalthis writes them for Plasma): each session points them at its own
   theme when it starts (the two are never open at once).
   Picked on 2026-11-04 on the lumar page (claude.ai/artifact/4qoiTRCu5ectVG2SmLvgnF,
   the picks in its store): Nalthis's own colors, so lumar takes them from
   Nalthis's knobs (`modules/nalthis/palette.json`, `nalthis tokens`): one
   palette for both sessions, GTK's and Qt's files already in it, Nalthis's
   page in System Settings re-tinting Hyprland too. `modules/lumar`'s
   apply-lumar writes it for shadesmar (read live), Hyprland and Ghostty, on
   every apply and when the knobs change (`lumar-palette.path`). Flush by
   default, as close to maximized as it gets: no gaps, no borders, square
   tiled windows (floating ones keep 10 px corners in both layouts), the bar
   docked; floating on Meta+G (gaps, 10 px corners, the bar floating), kept
   across logins. The bar, its popups, notifications and the OSD in
   Nalthis's glass from Plasma: the pane at 80 %, blurred behind, a 10 %
   outline in the text's color (the page's 92 % of the frame, dropped).
   Noto Sans;
   Ghostty in Fira Code, no title bar, the page's terminal colors on Konsole's
   Nalthis background (the raised surface) and text. The wallpaper: shadesmar's,
   the newest of the ones liked in Backdrop (~/Pictures/Backdrop). The GNOME
   apps are in, Hyprland's defaults through hyprland-mimeapps.list. Next: the
   apps with their own UI, then qt6ct.
5. **Silksong on desktop and lock screen.** The wrappers above, the bench on
   headless Hyprland, then shadesmar's lock in place of hyprlock: lid,
   suspend, hibernate, Lock AFK, a crash of the shell while locked.
6. **Then whatever was missed**: a grid overview, Klipper-like actions,
   more keyboard-driven binds and terminal apps.

## Borrowed from Omarchy (github.com/omacom/omarchy, branch `quattro`)

- Lua modules with a description on every bind (`default/hypr/helpers.lua`),
  so a cheat sheet is generated; `hyprctl binds` only shows Lua binds as
  `__lua`.
- Binds that call the shell's global shortcuts (`hl.dsp.global(...)`) rather
  than spawning a process per key.
- Monitors known by make, model and serial, not connector.
- The lock path: lock on lid close unless docked, wait for the lock to be
  secure before sleeping (`bin/omarchy-system-sleep-lock`), detect a held lock
  with no live locker (`bin/omarchy-hyprland-session-lock-stranded`).
- Window rules (`default/hypr/apps/`): picture-in-picture floated and pinned,
  file dialogs floated, password managers hidden from screen sharing,
  JetBrains without focus-follows-mouse, tags shared by rules and scripts.
- Misc: `allow_session_lock_restore`, `focus_on_activate`,
  `xwayland.force_zero_scaling`, Wayland env for Qt, GTK and Electron.
- Theme pipeline: a semantic palette, templates with color mixing, a
  hand-written file always beats a template, visible apps retinted first.

Left out: per-monitor workspaces (the opposite of ours), universal
Super+C/V, their GTK/Qt theming (Adwaita and `QT_QPA_PLATFORMTHEME=gtk3`),
migrations and update channels (lodestar does that), their titlebar plugin.

## Binds, close to KDE's at first

- Desktops: Meta+A/Z/Q/S and Ctrl+F1..F4 jump (as now), Meta+Ctrl+arrows
  move in the grid (KDE's default). The side screens only.
- Windows: Alt+Tab along the tape (wrapping: Hyprland's cycle, the view
  scrolling to the window; a switcher with previews, as Plasma's, was tried
  and dropped on 2026-11-04: romain prefers the plain scroll), Meta+Up full
  width (or maximized), Meta+Left/Right half width (KDE's quick tile),
  Meta+Down a hidden special workspace (Hyprland has no minimize),
  Meta+Shift+Left/Right and Meta+Shift+Q/D to the other screen, Ctrl+Alt+Esc
  kill.
- Meta+Return: the terminal, floating. Meta+²: Spotify's scratchpad (the key
  that opens Plasma's media player now). Meta+~: volume (the shell).
- Meta+Tab, Ctrl+Alt+Tab: shadesmar's overview, Plasma's: each screen's
  windows as live thumbnails, the tape's off-screen columns included (as
  their app's icon: Hyprland copies a window only while it overlaps its
  screen); click or Enter, arrows, typing filters. Meta+D: a peek at the
  desktop, each screen on an empty workspace of its own. Meta+= / Meta+- /
  Meta+0 (à), Meta+Ctrl+scroll: KWin's zoom, Hyprland's `cursor.zoom_factor`
  by steps of 1.2.
  Meta+L locks.
- Dropped: Meta+< (Focus Discord: Discord is always on the middle screen).
- **The laptop alone**: its screen shows the grid's four desktops; `comms`
  (Discord, Teams) is a fifth workspace with its own key; Spotify's
  scratchpad opens over whatever is there.

## Secrets (KWallet)

What's in the wallet now: Brave's (and Chromium's) Safe Storage key, which
encrypts their cookies and saved logins; the Wi-Fi passwords and the work
VPN's secrets (stored by Plasma's network applet); an SMB password. It's
unlocked at login by Plasma Login's PAM (`pam_kwallet5`), and `ksecretd`
also serves it as the freedesktop Secret Service (libsecret).

- **Keep it, invisible**, in both sessions: Hyprland starts
  `pam_kwallet_init` so the PAM unlock reaches it, and libsecret apps get
  `ksecretd`. Nothing to migrate, nothing to see.
- **Chromium and Electron apps choose their store by desktop** (KWallet in
  Plasma, libsecret elsewhere): the same app would look for its key in
  another place in Hyprland, fail to decrypt its data and log out, and again
  back in Plasma. The wallet shows two such apps, Brave and VS Code (their
  "Safe Storage" keys): both pinned to KWallet (`--password-store=kwallet6`
  in `brave-flags.conf` and `code-flags.conf`). JetBrains, gh, Zed and Warp
  already use the Secret Service, the same in both sessions; Discord,
  Obsidian, GitKraken and Bitwarden keep nothing there. Check at the first
  login that each stays logged in.
- **Networks: nm-applet in Hyprland** (a stand-in until shadesmar). Most
  Wi-Fi passwords are Plasma's network applet's (agent-owned, in the
  wallet), and both work VPNs ask a challenge (an OTP) at each connection:
  Hyprland needs an agent that prompts anyway. nm-applet asks each Wi-Fi
  password once (they're in Bitwarden) and keeps it in the Secret Service;
  Plasma keeps its own copy.

## Apps and toolkits: GTK first

The desktop's own apps are GNOME's (GTK 4 and libadwaita), so that one
palette makes them consistent: libadwaita takes colors from `gtk.css`
(named colors, as `modules/nalthis/pkg/gtk.go` writes them now), GTK 3 apps
follow with adw-gtk3 (`adw-gtk-theme`) in the same colors. Only colors:
the widgets keep Adwaita's shapes, so lumar is its palette, fonts, icons and
shadesmar, drawn to sit with Adwaita (radii, spacing). Qt can reshape
widgets, but only through a style engine, and Nalthis showed what that
costs.

| For | In Hyprland | Instead of |
|---|---|---|
| files | Nautilus | Dolphin |
| documents (PDFs, reading only) | Papers | Okular |
| images | Loupe | Gwenview |
| archives | File Roller, Nautilus's own extract | Ark |
| terminal | Ghostty | Konsole |
| screenshots | grim, slurp, shadesmar | Spectacle |
| file chooser | Nautilus's (xdg-desktop-portal-gnome, `FileChooser` only in `hyprland-portals.conf`; the rest from xdg-desktop-portal-hyprland and -gtk) | KDE's |

Kate goes (not used). Still Qt: qBittorrent, EasyEffects (Kirigami since
8), KDE Connect, qrca: lumar's palette through qt6ct, set only in Hyprland's
environment (Plasma never reads it), and a neutral style; their tray menus
are drawn by shadesmar anyway. The KDE apps stay installed for Plasma until
it's only the fallback.

Apps with their own UI (Chromium and Electron: Brave, Discord, VS Code,
Obsidian, GitKraken, Teams; CEF: Spotify, Steam; Tauri: Readest; Swing:
JetBrains; mpv's OSD) follow no toolkit: each gets a lumar template.
Terminal apps (TUIs) follow Ghostty's palette: the way to more keyboard
later (yazi, btop, lazygit…).

## Recovery

- The locker crashes: the session stays locked (Hyprland shows its "lock
  dead" screen). From a TTY (Ctrl+Alt+F3): `hyprctl --instance 0 eval
  'hl.exec_cmd("hyprlock")'` (`qs -c shadesmar` once shadesmar locks), with
  `allow_session_lock_restore`; or end the session and log in to Plasma.
- Hyprland won't start: `start-hyprland` falls back to safe mode; Plasma is
  in the session list.

## Open

- [x] Changing the workspace animation's style from a bind at runtime: works
      (grid.lua does it at each switch).
- [ ] The overview's animations: the windows going from their place to
      the grid and back, as Plasma's (it only appears and disappears now).
- [ ] Brave stays on its Classic theme (no bar above the tabs) with lumar's
      colors: a Chrome theme (a manifest of frame, tab and toolbar colors)
      rendered by lumar and loaded unpacked once, like mutectl's Teams
      extension; or the `BrowserThemeColor` policy in `/etc/brave/policies`
      (one seed color, no manual step), if Brave honors it. Either way it's
      the profile's, so Brave in Plasma gets lumar too. Check in Hyprland
      whether any bar is left above the tabs: Hyprland draws no title bars,
      and "Use system title bar and borders" then leaves only the tabs.
- [x] Hotplug: what becomes of windows on a screen that goes away (they go
      to the same desktop on the screens left, grid.lua; tried headless).
- [ ] A drop-down terminal (Ghostty's quick terminal, or a special workspace
      as Omarchy's Super+\`), on top of the free-floating one.
- [ ] Focus after a switch stays on the screen it was on (`set_workspace`
      doesn't move focus, by the source): check.

## Alternatives considered

- Shells: Noctalia 5 (native C++, Luau plugins, TOML config; no QML, so no
  Silksong scene), Dux Shell (ex-DankMaterialShell) and Caelestia
  (Quickshell configs, large and fast-moving), Omarchy's (Quickshell, tied to
  Omarchy), the classic kit (waybar, mako, fuzzel or walker, swayosd,
  hyprlock, hypridle, hyprpaper: many pieces to theme one by one, and the
  lock screen would still be ours), AGS/Astal (TypeScript and GTK 4: the
  scene would be rewritten).
- Compositors: Umbriel (Noctalia's own, young), Labwc (stacking, the closest
  to KWin, few effects), niri (scrolling, fights maximize and Alt+Tab),
  COSMIC (no plugins on the lock screen, no grid).
