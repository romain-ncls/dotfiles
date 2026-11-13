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
  tape, wrapping (binds.lua: the windows in the order they stand, not of
  use). The terminal from Meta+Return opens floating
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
- **The slides and swipes are a plugin of ours, hyprslide**
  (`modules/hyprslide`, C++, three hooks and the touchpad's swipe events).
  Hyprland slides two workspaces sideways or up and down only, the
  direction from the ids' order, and draws during a slide the columns the
  scrolling layout keeps beside the screen, which then cross it. grid.lua
  tells hyprslide where the desktops lie (`hl.plugin.hyprslide.grid`, each
  grid screen's, row by row, at each switch), and it slides them as one
  plane, as KDE's: every desktop's offset on both axes, from where the plane
  lies to where it lies with the next desktop on the screen. So a diagonal
  move shows the desktops between in the corners, and a switch made while
  one slides goes on from where the plane is. It leaves out the tiled
  windows whose place is off the screen while their workspace slides. Four
  fingers on the touchpad drag the plane, on the side screens at once
  (Hyprland's gesture events, cancelled for it): along one axis, or both
  when the swipe is clearly diagonal (past 25° from either). Let go, it
  goes to the next desktop on each axis that went far or fast enough
  (Hyprland's `gestures.workspace_swipe_*` settings), by asking grid.lua (a
  plugin event, `hl.on("hyprslide.swipe")`, so the grid's bookkeeping
  stays in one place); the plane goes on from where the fingers left it.
  Otherwise it goes back. Hyprland gives a plugin event only to the Lua
  state that was there when it was added, and a reload makes a new one:
  hyprslide adds it again after each reload. A window moved along
  (Meta+Ctrl+Shift+arrows, `hl.plugin.hyprslide.carry(window)` before it
  moves) stays in sight while the desktops slide under it, as KWin's: on
  the screen, a window is its position plus its workspace's offset, so its
  position goes from where it was less a screen to its place there, on the
  slide's own curve, and it goes straight from one to the other. Hyprland
  would fade it out of the desktop it leaves, push a floating one over the
  edge back (its floating offset), and skip drawing it while its position
  is a screen away: hyprslide stops all three for it. Hyprland moves a
  window first, then switches, so it otherwise rides in with the new
  desktop; no plugin found does KWin's (2026-11 survey: Hyprgrid,
  hyprland-virtual-desktops, hyprtasking, hyprmosaic). Plugins must match the exact
  Hyprland build, so lodestar rebuilds it with each new Hyprland
  (`pkg: built-against: [hyprland]`); Hyprland refuses one built for
  another, and the grid then falls back to short slides that fade (10 %,
  so the columns barely show) and a fade for a diagonal (and no swipes).
  Third-party plugins stay out: they lag behind Hyprland (hyprtasking
  compiles on 0.57 only since 9 Nov 2026, hyprexpo is gone). hyprmosaic
  (MIT) was the model for the swipe. The overview of the grid is the
  shell's: drawing live desktops scaled down takes Hyprland's render
  internals, which is what breaks those plugins at each release.
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
  anything (`life.mjs`) is worth more. Hyprland keeps sending frame callbacks
  to a wallpaper that windows cover, so the scene must stand still itself, as
  it already does on the desktop.
- **A small Go helper beside the shell, `spanreed`,** for what QML can't
  do: own D-Bus names and talk to logind. It serves
  `org.kde.osdService.showText` (backdrop and spotify-vol call it: they stay
  as they are), `org.freedesktop.ScreenSaver` inhibits (browsers and video
  players; Omarchy's open bug #6475 is not owning it), and logind's `Lock`
  and `PrepareForSleep` (`loginctl lock-session` from mutectl's Lock AFK, lock
  before suspend and hibernate within a delay inhibitor), BlueZ's pairing
  agent (`org.bluez.Agent1` on the system bus, the default one: the code to
  compare or to type, a PIN, a yes or no) and NetworkManager's secret agent
  (`org.freedesktop.NetworkManager.SecretAgent`: below, Secrets). It
  forwards to the shell with `qs ipc call` (one JSON object for a network's
  request: an argument in brackets would be split), and the shell's answers
  come back on the session bus (`org.shadesmar.Spanreed`: `busctl` for
  Bluetooth, `spanreed answer` for a network, its secrets on stdin rather
  than in a command line any process can read).
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
  for now get `ConditionEnvironment=XDG_CURRENT_DESKTOP=KDE` (logi-smartshift
  until it reads Hyprland's events; backdrop's daemon runs in both since
  10 Nov 2026). That target doesn't
  pull in `xdg-desktop-autostart.target`: a drop-in adds it, or the XDG
  autostart entries wouldn't start (the KDE Connect daemon, Bitwarden,
  Packet, limine-snapper-notify, xdg-user-dirs); those marked
  `OnlyShowIn=KDE` (plasmashell, powerdevil, KDE's polkit agent…) stay out
  by themselves, and `pam_kwallet_init`'s is `X-systemd-skip` (below,
  Secrets). Plasma's startup also reads `environment.d`
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
- **The lid does nothing** (5 Nov 2026): no lock, no suspend, at the desk or
  not, on the charger or on battery. Until then it did as Plasma does
  (nothing at the desk, locked on the charger, suspended on battery).
  `hyprland-lid.service` keeps logind off it, whose default would suspend;
  Plasma still suspends on battery (powerdevil's default).
- **hypridle stays** (9 Nov 2026), not replaced by the shell's idle
  monitor: it locks on idle and before sleep from outside shadesmar, so a
  crash of the shell doesn't stop the locking.

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
- `modules/silksong/wallpaper/quickshell/`: the scene's wrappers. The scene
  files stay where Plasma's package has them, untouched; the wrappers
  load them through a link.
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
     Lock AFK, lock before sleep; the lid does nothing: Decisions),
     `allow_session_lock_restore`.
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
   (popups stacked by app, actions, a history in the bar that keeps what
   the apps withdraw, Do not disturb; below, Open), the OSD
   (PipeWire's volume and mute, the brightness from its binds, spanreed's
   calls), the overview (Meta+Tab), the grid view (Meta+W), and the bar's
   popups, as Plasma's tray: the clipboard's history (cliphist, recorded
   by clipboard-history.service), the network (Wi-Fi, the cable, the VPNs
   through nmcli; their secrets through spanreed's agent, in place of
   nm-applet), Bluetooth (pairing through spanreed's agent); both agents
   ask in a card above the bar, a window of its own, as a request can
   come with no popup open (BarCard.qml), the sound (devices, volume, the
   microphone; Meta+~), the battery (power profiles,
   brightness).
4. **lumar, from scratch.** One palette, templates rendered at apply (Go
   templates, as now): Hyprland, shadesmar, Ghostty, libadwaita and adw-gtk3
   (below, Apps and toolkits), `kdeglobals` for the few Qt apps, then each app with
   its own UI (Brave, Discord's Vencord CSS, VS Code, JetBrains, Obsidian,
   GitKraken…), Omarchy's way: most of the work is there. The GNOME apps
   replace the KDE ones then. GTK's files are shared by both sessions (and
   Nalthis writes them for Plasma): each session points them at its own
   theme when it starts (the two are never open at once).
   Picked on 2026-11-04 on the lumar page (claude.ai/artifact/4qoiTRCu5ectVG2SmLvgnF,
   the picks in its store): Nalthis's colors at first, then lighter and
   nearer One Dark's tint. lumar is its own theme, so it has its own knobs
   (`modules/lumar/palette.json`: hue 260, tint 1.3, depth 0.03, accent
   250; Nalthis keeps 255, 1, 0, 250), turned into colors with Nalthis's
   maths (`nalthis tokens`). apply-lumar writes them for shadesmar (read
   live), Hyprland and Ghostty, and writes the files both sessions read,
   in the colors of the session it runs in: Nalthis's own files (`nalthis
   apply` with the session's knobs, not saved: `kdeglobals`, which the Qt
   apps follow live, Konsole's schemes, GTK's palette) and Brave's theme.
   It runs at each login (`lumar-session.service`, before the autostarted
   apps, and in Plasma before KWin and the shell), on every apply, and
   when the knobs change (`lumar-palette.path`; `apply-lumar set
   depth=0.04`); the apps are only told to repaint when `kdeglobals`
   changes. The Qt apps keep Darkly and nalthis's icons: Hyprland adds
   Plasma's `~/.config/kdedefaults` to `XDG_CONFIG_DIRS`, as Plasma's
   startup does (session.lua). Flush by
   default, as close to maximized as it gets: no gaps, no borders, square
   tiled windows (floating ones keep 10 px corners in both layouts), the bar
   docked; floating on Meta+G (gaps, 10 px corners, the bar floating), kept
   across logins. The bar, its popups, notifications, the OSD and the
   launcher in Nalthis's glass from Plasma: the pane at 80 %, blurred
   behind, a 10 % outline in the text's color (the page's 92 % of the
   frame, dropped). Noto Sans; Ghostty in Fira Code, no title bar, the
   page's terminal colors on the pane (about Konsole's Nalthis background)
   and the second text color. The wallpaper: shadesmar's, Backdrop's current
   picture (the newest liked one, ~/Pictures/Backdrop, until its daemon ran
   in Hyprland: below, Open). The GNOME apps are in,
   Hyprland's defaults through hyprland-mimeapps.list; Brave's theme too
   (docs/manual-steps.md); the file chooser is GTK's (Nautilus's needs
   GNOME Shell). Done.
5. **Silksong on desktop and lock screen.** The wrappers above, the bench on
   headless Hyprland, then shadesmar's lock in place of hyprlock: lid,
   suspend, hibernate, Lock AFK, a crash of the shell while locked. Done so
   far: the lock screen, a Quickshell config of its own (`qs -c
   silksong-lock`, modules/silksong's README) with the Silksong prompt,
   which is now shared with Plasma's (`SilksongPrompt.qml`, a locker for
   each). `lock-screen` is hypridle's lock_cmd, so Meta+L, the idle,
   sleep and Lock AFK all reach it; sleep waits for the lock
   (`inhibit_sleep = 3`). hyprlock stays as the fallback: without the art or
   the PAM service, if the lock doesn't come up within 5 seconds, or if it
   ends while locked. The painting starts over the windows ("over", chosen
   among mockups), the screens' sizes read from their EDID as KWin does
   (Hyprland's whole centimetres made it slow and jerky). The desktop keeps
   shadesmar's wallpaper from Backdrop (5 Nov 2026): Silksong is the lock
   screen's only. The bench is the lock screen's, as `lock-screen` runs it, in
   the headless rig (modules/silksong's `tools/lockbench.sh`; `bench.py` stays
   Plasma's). Left: the lid, suspend and hibernate on the machine (romain's
   tests, later).
6. **Then what's asked for, when it's needed** (9 Nov 2026): no list kept
   ahead (Klipper-like actions, more keyboard-driven binds and terminal
   apps were the ideas).

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
- Notifications (4.5, `docs/notifications.md`): a copy of each, kept when
  the app withdraws it, written to a file (100, 24 h, no images, nothing
  `transient`); popups stacked by sender, identical repeats collapsed; the
  click's fallback to the app's window. Not their replay of the history
  as cards on a key: shadesmar keeps Plasma's list under the bell.

Left out: per-monitor workspaces (the opposite of ours), universal
Super+C/V, their GTK/Qt theming (Adwaita and `QT_QPA_PLATFORMTHEME=gtk3`),
migrations and update channels (lodestar does that), their titlebar plugin.

## Binds, close to KDE's at first

- Desktops: Meta+A/Z/Q/S and Ctrl+F1..F4 jump (as now), Meta+Ctrl+arrows
  move in the grid (KDE's default), four fingers on the touchpad drag it
  (hyprslide). The side screens only.
- Windows: Alt+Tab along the tape, left to right and round again (the
  docked windows in the tape's order, then the floating ones; the view
  scrolling to the window; a switcher with previews, as Plasma's, was tried
  and dropped on 2026-11-04: romain prefers the plain scroll). Meta+Up docks
  a floating window, full width, and floats a docked one (KDE's maximize
  and restore); Meta+Left/Right: half the screen on that side (KDE's quick
  tile), a docked window staying docked, the tape scrolled to put it there.
  Meta+Shift+Q/D move the window along the tape, and past its end onto the
  next screen; Meta+Shift+Left/Right straight to the other screen (KDE's).
  With columns as wide as the screen the move shows nothing: the view
  follows the window, and the neighbour passes behind it (Hyprland draws
  the focused window last).
  Meta+Down, KDE's minimize, is unbound since 2026-11-13: Hyprland has no
  minimize, and a window hidden in a special workspace left no trace to find
  it by (a minimize would need the bar to list hidden windows).
  Ctrl+Alt+Esc kill.
- Meta+Return: the terminal, floating. Meta+E: the files (Nautilus, a new
  window, as Dolphin's). Meta+²: Spotify's scratchpad (the key that opens
  Plasma's media player now). Meta+~: volume (the shell).
- Meta+Tab, Ctrl+Alt+Tab: shadesmar's overview, Plasma's: each screen's
  windows as live thumbnails, the tape's off-screen columns included (with
  their last picture: Hyprland copies a window only while it overlaps its
  screen); click or Enter, arrows, typing filters. Meta+W, or four fingers
  pinched together (spread: back): shadesmar's grid view, Plasma's Grid
  (Meta+G there, lumar's here): each grid screen's four desktops, zoomed
  out of the plane hyprslide slides; click a desktop or a window, drag a
  window to another desktop, arrows and Enter. Meta+D: a peek at the
  desktop, each screen on an empty workspace of its own. Meta+= / Meta+- /
  Meta+0 (à), Meta+Ctrl+scroll: KWin's zoom, Hyprland's `cursor.zoom_factor`
  by steps of 1.2.
  Meta+L locks.
- Screenshots, on Spectacle's keys (LumineCapture): Meta+Shift+S or
  Meta+Shift+Print its editor over every screen, frozen (drag a region,
  annotate; Enter or Ctrl+C copies, Ctrl+S saves and copies, Ctrl+P pins
  it above the windows); Print saves the screen under the pointer,
  Shift+Print every screen, to `~/Pictures/Screenshots`.
- Recordings, on Spectacle's keys (shadesmar): Meta+Shift+R a region,
  Meta+Alt+R the screen under the pointer; the same key again, or a click
  on the bar's red dot, stops.
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
  `ksecretd`. Nothing to migrate, nothing to see. At login, PAM starts a
  `ksecretd` with the password, waiting for the session's environment on a
  socket, which `pam_kwallet_init` sends. Plasma runs it as a unit
  (`plasma-kwallet-pam.service`), and its XDG autostart entry is
  `X-systemd-skip`; its socket's path (`PAM_KWALLET5_LOGIN`) is in
  Hyprland's environment, not systemd's. So Hyprland has its own unit
  (`hyprland-kwallet-pam.service`, the path written in), run before
  `graphical-session.target`. Without it, Brave was the first to ask: it
  started another `ksecretd`, a locked one, which asked for the password
  every morning.
- **Chromium and Electron apps choose their store by desktop** (KWallet in
  Plasma, libsecret elsewhere): the same app would look for its key in
  another place in Hyprland, fail to decrypt its data and log out, and again
  back in Plasma. The wallet shows two such apps, Brave and VS Code (their
  "Safe Storage" keys): both pinned to KWallet (`--password-store=kwallet6`
  in `brave-flags.conf` and `code-flags.conf`). JetBrains, gh, Zed and Warp
  already use the Secret Service, the same in both sessions; Discord,
  Obsidian, GitKraken and Bitwarden keep nothing there. Check at the first
  login that each stays logged in.
- **Networks: spanreed's secret agent in Hyprland** (nm-applet's until
  then). Most Wi-Fi passwords are Plasma's network applet's (agent-owned, in
  the wallet's folder of its own), and the work VPNs (OpenVPN) ask a
  challenge (an OTP) at each connection: Hyprland needs an agent that
  prompts anyway. spanreed keeps what NetworkManager leaves to the agent in
  the Secret Service, in nm-applet's items (libnma's schema), so what
  nm-applet kept (the VPNs' passwords) is still found; it asks each Wi-Fi
  password once (they're in Bitwarden), Plasma keeps its own copy. A VPN's
  secrets are its plugin's: its auth dialog, in external UI mode as GNOME
  Shell runs it, says which to ask (the password when none is kept, the
  OTP with the server's message) and finds the kept ones itself; a plugin
  without that mode (openconnect's) gets no answer. nm-connection-editor
  stays for editing connections.

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
| files | Nautilus (Meta+E), folders before files (GTK's file chooser setting, which its dialogs share: dconf keys, set by `modules/hyprland/gtk-settings` on every apply). Its sidebar's bookmarks (`modules/hyprland/home/.config/gtk-3.0/bookmarks.tmpl`): Dolphin's folders, ~/git and ~/dotfiles, under the places it always shows (Home, Recent, Starred, Network, Trash; no setting hides them); GTK's file dialogs show them too. Nautilus rewrites the file when a bookmark is added or removed there: `lodestar drift` shows it, to bring back here | Dolphin |
| documents (PDFs, reading only) | Papers | Okular |
| images | Loupe | Gwenview |
| archives | File Roller, Nautilus's own extract | Ark |
| terminal | Ghostty | Konsole |
| screenshots | LumineCapture (`modules/lumine-capture`); Flameshot if it falls short | Spectacle (it captures through KWin) |
| recordings | wl-screenrec, driven by shadesmar (Recorder.qml) | Spectacle |
| screen sharing's picker | shadesmar's (SharePicker.qml), for xdg-desktop-portal-hyprland | KDE's portal dialog |
| file chooser | GTK's (xdg-desktop-portal-gtk, `FileChooser` in `hyprland-portals.conf`), for the apps that ask the portal: GTK 4's (by default now), Brave. Not Nautilus's: xdg-desktop-portal-gnome serves only its settings outside GNOME Shell ("Non-compatible display server") | KDE's |

Kate goes (not used). Still Qt: qBittorrent, EasyEffects (Kirigami since
8), KDE Connect, qrca, and the Qt apps' own file dialog (KDE's, drawn in
their process): `kdeglobals` in lumar's colors (apply-lumar), with Darkly
and nalthis's icons. Not qt6ct, as planned first: the KDE apps read their
colors from `kdeglobals` whatever the platform theme says (KColorScheme),
so qt6ct would only have recolored half of them. Their tray menus are
drawn by shadesmar anyway. The KDE apps stay installed for Plasma until
it's only the fallback.

Apps with their own UI (Chromium and Electron: Brave, Discord, VS Code,
Obsidian, GitKraken, Teams; CEF: Spotify, Steam; Tauri: Readest; Swing:
JetBrains; mpv's OSD) follow no toolkit: each gets a lumar template.
Terminal apps (TUIs) follow Ghostty's palette: the way to more keyboard
later (yazi, btop, lazygit…).

## Recovery

- The lock screen crashes: the session stays locked, and `lock-screen` starts
  hyprlock, which takes the lock over (`misc.allow_session_lock_restore`).
  If neither shows (Hyprland's "lock dead" screen), from a TTY
  (Ctrl+Alt+F3): `hyprctl --instance 0 eval 'hl.exec_cmd("hyprlock")'`; or
  end the session and log in to Plasma.
- Hyprland won't start: `start-hyprland` falls back to safe mode; Plasma is
  in the session list.

## Open

- [x] Changing the workspace animation's style from a bind at runtime: works
      (grid.lua does it at each switch).
- [x] The overview's animations, as Plasma's (9 Nov 2026): the windows go
      from their places to the grid and back, the one picked to where the
      tape scrolls it; a filter closes the grid up. The shell only sees
      the windows, so it does it with their live pictures over a copy of the
      wallpaper (Overview.qml): they show once they have their pictures (a
      few frames), at the windows' places as hyprctl gives them, in
      Hyprland's order, corners and shadow, so the first frame is the
      screen as it was (checked pixel by pixel, headless); the bar's strip
      stays the bar. Hyprland's fade is off for that layer (looknfeel.lua).
      A pick goes through Hyprland's dispatcher (a Wayland activation is
      followed by a refocus of the window under the pointer, which wins
      when the pointer just moved to click), once Hyprland has let the
      keyboard go: it focuses no window while a layer holds the keyboard.
      The pictures aren't live
      (a live ScreencopyView asks for a frame at each repaint, so Hyprland
      copied every window at every frame of the animation: 20-30 fps):
      one frame when it opens, then 20 a second in the grid; drawn
      mipmapped, so text shrunk below half keeps its strokes. The
      scrolling layout's columns beside the screen show their last
      picture (WindowPictures.qml): Hyprland copies a window only while
      it overlaps its monitor (ScreenshareManager::onOutputCommit), so
      the windows on their screens are taken again each time the focus
      moves, before the tape scrolls one out. Never one beside: its
      request would wait until it's back, and while one waits Hyprland
      draws a copy of that screen at every frame (outputNeedsCopyFB).
      About 16 MB per 1920×1080 window, kept all the time.
- [x] Brave stays on its Classic layout (no bar above the tabs) in lumar's
      colors: a Chrome theme apply-lumar renders from the palette
      (`~/.local/share/lumar/brave-theme`, which Brave loads at each start:
      lumar's `brave: extensions`): the tab strip the frame, the active tab and
      toolbar the pane, the address bar and new tab the base. One profile,
      two sessions: each login rewrites it in its session's colors (Brave
      rereads it when it starts). Discord and VS Code already
      match with their own dark themes.
- [x] Hotplug: what becomes of windows on a screen that goes away (they go
      to the same desktop on the screens left, grid.lua; tried headless).
- [x] A drop-down terminal (Ghostty's quick terminal, or a special workspace
      as Omarchy's Super+\`): dropped, not needed (9 Nov 2026); the
      free-floating one on Meta+Return is enough.
- [x] Focus after a switch stays on the screen it was on (tried headless,
      grid.lua's functions as the binds and the bar call them): a jump or a
      move in the grid keeps the focus on that screen, on its window there
      or, on an empty desktop, on the screen alone (not the other screen's
      window); comms keeps it; a window taken along keeps it; the peek and
      back give it back. A window of another desktop that takes the focus
      (a notification's) brings its desktop and keeps the focus.
- [x] Screenshots with annotations (9 Nov 2026): LumineCapture, built from
      its repo's PKGBUILD at a release tag (`modules/lumine-capture`; a
      young project, one main author). Its editor freezes every screen,
      takes the region and its annotations in place, as Spectacle's and
      Flameshot's do. Its settings are the repo's, its colors lumar's: one
      config file, so apply-lumar writes both. On Hyprland it would open
      its editor as fullscreen windows (columns, in the scrolling layout):
      `overlay = "layer"`, and Hyprland's fade off for that layer
      (looknfeel.lua); a pinned shot floats on every desktop (windows.lua).
      Tried headless: the three screens, a region, an arrow, Ctrl+C (the
      clipboard only), Ctrl+A then Ctrl+S, the pin, the two saves without
      the editor (the gaps under the shorter screens transparent), its
      notifications in shadesmar. On the machine: the keys work, and the
      pointer isn't in the shots (LumineCapture has no option to put it
      in; Spectacle had a checkbox: later, maybe upstream). Its magnifier
      (M) is off: LumineCapture remembers that in its state, not its
      config. Its notifications use Plasma's x-kde-urls, which shadesmar
      now knows: the shot as a picture, Open and Show in Files.
- [x] Recordings, for short clips of the UI (9 Nov 2026): shadesmar runs
      wl-screenrec (Recorder.qml), which encodes on the Arc's GPU, the
      frames never through the CPU (a U-series chip encoding in software
      could drop the animations' frames), the pointer in. A region is
      picked with slurp (in lumar's colors, its size shown; its stdin
      empty, or it waits for
      boxes to choose from) and framed in red just outside while it's
      recorded; a screen is the one under the pointer (`hyprctl
      cursorpos`: the focused one can be another). The bar shows a red
      dot and the time. Saved to `~/Videos/Recordings/<date>.mp4` (H.264:
      GitHub, Slack and Linear play it); its notification opens it,
      shows it in Nautilus or makes a GIF of it (ffmpeg: its own palette,
      30 fps, 1280 wide at most). Tried headless with wf-recorder in
      wl-screenrec's place (the same arguments): a screen, a region
      (the frame outside the video), Escape in slurp, the shortcuts
      through Hyprland, the dot, the notification and its GIF. On the
      machine: wl-screenrec works.
- [x] Screen sharing's picker, after Plasma's (9 Nov 2026): Hyprland's portal
      (xdg-desktop-portal-hyprland) asks its own picker, which lists the
      screens and windows by name. It can run another
      (`custom_picker_binary`, hypr/xdph.conf): shadesmar-share-picker
      (spanreed's package) passes the request to shadesmar
      (SharePicker.qml) and waits on a FIFO for the answer; Hyprland's
      own picker if the shell doesn't answer (`qs ipc call` exits 0 even
      then: it's what it prints that tells). "Screen Sharing Requested":
      the screens as they're arranged, to scale, as pictures taken four
      times a second: romain shares a screen most of the time, a different
      one each time. A window or a region (slurp) folded away under them,
      unfolded by a click, Down or a search: the windows most recently
      used first (the scrolling layout's columns beside the screen with
      their last picture, WindowPictures.qml, as in the overview; a
      window on another desktop is copied all the same). Arrows, Enter,
      Escape; nothing lit until the keys or the pointer pick. Never
      remembered (9 Nov 2026, after a first try with Plasma's "Allow the
      application to do this without asking next time"): no "r" flag, so
      no restore token, and `allow_token_by_default` off. The portal
      gives the windows with their Hyprland address, so each finds its
      picture. Tried headless, through the portal itself (its own
      instance on the rig's bus, a small client asking as an app does): a
      window shared, its stream back (and a token, then: its rig wrote it
      to the user's permission store, a shared file; deleted); and each
      answer: a screen, a window, a search and Enter, the keys, Escape, a
      region and Escape in slurp. The portal reads its config when it
      starts: `systemctl --user restart xdg-desktop-portal-hyprland` once
      the package is in.
- [x] Notifications that stay (10 Nov 2026): they vanished from the
      bell's history, and its count could say 2 over an empty list. An
      app may withdraw its notification (CloseNotification: Discord does
      as its next message comes, Teams in a browser as its popup goes),
      and the history was only what the apps still kept; the count was a
      counter of its own. Plasma and GNOME do the same (the spec: "no
      longer relevant"; KDE: "a Discord bug"); Omarchy 4.5 keeps what was
      seen. Done as Omarchy, Notifications.qml: each one copied when it
      comes; a withdrawal takes the app's buttons, not the copy, and a
      click on it shows the app's window (or starts the app). The count
      is the list's, since the bell was last opened; opening it takes the
      popups there (critical ones stay on screen). Kept across restarts
      and logins (the shell's state folder): 100, a day, no pictures,
      nothing marked transient (the spec's hint); Do not disturb too. By
      app: the popups stack (NotificationStack.qml, the newest in front,
      the pointer unfolds them), the bell's list folds an app's others
      under its newest, with a Clear each; the same one again counts
      ("×2"). New words from the app (replaces_id: Spotify's next song)
      show it again. App-given timeouts are milliseconds as Quickshell
      gives them (were taken for seconds: a 5 s one lasted 83 min). Tried
      headless (a virtual pointer for hover and clicks: the rig has no
      pointer of its own): a burst stacked and unfolded, a withdrawal, the
      pause under the pointer, a reload and a restart (the buttons back
      on a kept one), a replacement, transient, critical, Do not disturb,
      the bell's folds, marks and Clear, a click focusing the app.
- [x] Backdrop in Hyprland (10 Nov 2026): its daemon only fills
      ~/.local/share/backdrop (its one Plasma call, the OSD's showText, is
      spanreed's here), so backdrop.service runs in both sessions now.
      Wallpaper.qml shows its current picture, cross-faded into the next,
      as the Plasma plugin does. A right click on the wallpaper opens
      Backdrop's menu (BackdropMenu.qml), Hyprland's desktop having none of
      its own: the picture's title and place (not the picture: it's right
      behind), where it's from, its credit, its score ("62% to your
      taste"), when the next comes; Like (a heart in the accent once
      liked), Dislike and Next, which keep the menu open to go through
      several (L, D, N or Right; Escape); its page, the image, the liked
      ones' folder. The daemon down: "Backdrop isn't running" and a button
      that starts it. In lumar's glass, blurred behind (lumar.lua's rule).
      It closes when the desktop is covered (another workspace, Meta+D's
      peek ending, a window opening), and sits on whole pixels (the
      pointer's are fractions). Tried headless with a second daemon on a
      copy of the state: like, dislike, next, the keys, the cross-fade,
      the turn at the screen's edges, Escape and a click outside, the
      daemon down. Backdrop's state.json keeps absolute paths: a copy run
      with another XDG_DATA_HOME still points at the real pool, and its
      daemon deleted the real pool's files (prefetched, not yet shown; 5 of
      10 fetched again, Bing's archive mirror being down). A copy's paths
      are rewritten first now.
- [x] A window moved along stays in sight (10 Nov 2026): Meta+Ctrl+Shift+
      arrows moved the window first, so it faded out, then rode in with
      the next desktop. hyprslide 2 takes it along (the hyprslide passage
      above). Tried headless, slides slowed to 4 s and caught frame by
      frame: a tiled window to an empty desktop and onto one with a window
      (it goes to its column while that desktop's window slides in under
      it), up and down, a second move while the first still slides, a
      floating window (visible from the first frame on), and its own
      animations back to Hyprland's after. The first build aborted the
      rig's Hyprland: a callback locked a window's animation through a
      weak pointer, which asserts for what a window owns.
- [x] The desktops as one plane, swipes (12 Nov 2026): a diagonal move
      slid the two desktops alone, the corners empty (the wallpaper),
      where KDE's grid shows the desktops between pass by. hyprslide 3
      knows the grid and slides it whole, and four fingers drag it (the
      hyprslide passage above). Tried headless with swipes fed to
      Hyprland's input manager by a rig-only plugin (as libinput's
      would be), slides slowed to 4 s: diagonal moves both ways on both
      side screens, a move made mid-slide (no jump), a window taken along,
      swipes sideways, diagonal and slightly crooked (held to its axis),
      one too short (back), one at the grid's edge (nothing moves), after
      a config reload, the peek's fade untouched. A test window that never
      showed had only part of its first picture, its app's doing.
- [x] The grid view, Plasma's Grid (12 Nov 2026): DesktopGrid.qml, on
      Meta+W and four fingers pinched together. Each grid screen's four
      desktops are laid as hyprslide's plane, which zooms out to fit (the
      shown desktop's scale and place go straight from the screen to its
      cell). Each desktop is the screen's rectangle: the wallpaper, then
      its windows at their places as hyprctl gives them, tiled under
      floating, the tape's columns beside it left out (their middle off
      it, as in a slide). The pictures are the overview's kept ones
      (WindowPictures.qml), the shown desktop's taken again 20 times a
      second. Hyprland copies only windows on their screen, so another
      desktop shows its windows as they were when last seen, or their
      app's icon. A pick switches at once under the view (`G.go(d, true)`:
      the workspaces' animation off for that switch), then the view zooms
      into it; a window picked is focused once grid.lua says it switched
      (`grid d`), as the overview does it. A dropped window moves with
      `follow = false`. The bar's strip stays the bar, a peek or comms on
      the laptop alone opens nothing, and Hyprland's layer fade is off
      for it (looknfeel.lua), or the windows showed through as it opened.
      Hyprland names a pinch by its zoom: fingers together is `zoomout`.
      Tried headless with a virtual pointer and keyboard (wtype) and fake
      pinches: the zoom both ways, arrows, hover, a click on a desktop, on
      a window, on the right screen, a drag onto another desktop, the
      laptop alone under the bar. Seen there: Quickshell clients can die
      when an output goes ("global wl_output is unavailable"), the rig's
      config reload disabling one.

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
- Screenshot editors (9 Nov 2026): Flameshot 15 (the same frozen overlay,
  mature; a long record of multi-monitor trouble on wlroots and Hyprland:
  the fallback), Satty (grim and slurp first, then a window: the screens
  not frozen, the region fixed before annotating), Swappy (Satty's
  predecessor), Gradia (polishes a shot in a window: backgrounds, padding).
- Screen recorders (9 Nov 2026): wf-recorder (the same command line, in
  Arch's repos; it encodes on the CPU unless told otherwise),
  gpu-screen-recorder (as light, made for games and instant replays; on
  Wayland it captures through a privileged helper or the portal's
  picker), Kooha (a window; the portal's picker at each recording), OBS
  (much more than clips of a few seconds). LumineCapture's own recording
  is only on its roadmap.
