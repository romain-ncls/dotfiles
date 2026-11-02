# Hyprland on wandersail (plan)

A Hyprland session next to Plasma on the work laptop, with our own shell in
Quickshell and a theme made from scratch. Plasma stays installed and stays the
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

- One desktop = one workspace on each of the three screens; **all screens
  switch together**, as in KDE.
- Four desktops in a **2×2 grid**: direct jumps (Meta+A/Z/Q/S, Ctrl+F1..F4)
  and moves up/down/left/right, the animation sliding the way you move.
- A stacking workflow, not tiling: mostly maximized windows switched with
  Alt+Tab; the terminal floating, maximized, on half a screen, or two side by
  side; Discord pinned on the middle screen, Spotify on all desktops.
- Every shortcut the modules declare (bemoji, mutectl, soundboard, awpro,
  spotify-vol, ssh-add, Claude in Brave…), on the French AZERTY layout.

## Decisions

- **Everything floats; maximize is a window state.** Pinning (on every
  workspace) only works on floating windows, the terminal has to float freely,
  and Hyprland has no keep-above: floating windows are above tiled ones, so a
  mix would fight us. New windows open maximized
  (`fullscreen({mode="maximized"})`) unless a rule says otherwise. Half-screen
  is a bind that moves and resizes (KDE's quick tile), not a tiling layout.
  Plan B if floating proves clumsy: the built-in monocle layout (every tiled
  window fills the screen) with the terminal and pinned windows floating.
- **The grid is Lua in the compositor config.** Workspace ids are numbered per
  screen, row by row (desktop d on the n-th screen: `(n-1)*4 + d`), each bound
  to its screen by EDID description. A switch computes the neighbour, sets the
  workspace animation's style (`slide` or `slidevert`, the direction from the
  ids' order) and calls `set_workspace` on every monitor. No plugin: plugins
  must match the exact Hyprland build (hyprtasking doesn't compile on 0.57
  yet, hyprexpo is gone). An overview of the grid, if wanted, comes later in
  the shell.
- **Our own shell in Quickshell, not Noctalia or another ready-made shell.**
  Noctalia 5 is native C++ with no QML, so the Silksong scene can't run in it;
  Dux Shell (ex-DankMaterialShell) and Caelestia are large, weekly-moving
  codebases to fork. Quickshell has what we need natively: layer-shell
  windows, session lock with PAM, Hyprland IPC, notifications server, tray,
  MPRIS, PipeWire, UPower, Bluetooth, NetworkManager, polkit agent, idle
  monitor and inhibitor, global shortcuts, live window previews
  (`ScreencopyView`). Omarchy 4 made the same move (one Quickshell process in
  place of waybar, mako, swayosd, hyprlock, hypridle, walker…): its `shell/`
  is our reference code.
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
- **A small Go helper beside the shell** (name to choose) for what QML can't
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
  so our user units start in both sessions; those that only make sense in
  Plasma (backdrop's Plasma side, the KRDP server) get a condition.
- **Updates held.** `hyprland` and `quickshell` go in pacman's `IgnorePkg`
  (base module) and are upgraded on purpose after reading the release notes
  (0.55 and 0.57 both broke configs; Omarchy pins Hyprland and builds its own
  Quickshell after a Qt update broke it).

## Development

Three places to run it:

1. **Nested, inside Plasma** (most of the time): `Hyprland` started as romain
   in a window, under `dbus-run-session` (its own session bus, so its shell's
   notifications and tray don't fight Plasma's), with a dev config. Claude can
   start it, query it (`hyprctl -j`, `hyprctl eval`), screenshot it (`grim`)
   and stop it.
2. **Headless**, for automated checks and screenshots: Hyprland with no
   display, headless outputs laid out like the desk (`hyprctl output create
   headless`), permissions not enforced so `grim` works. The shell's and the
   scene's benches run here.
3. **The real session as `hyprtest`**, a temporary user, on another TTY while
   Plasma runs: the three screens, the grid across them, idle, lock and PAM,
   suspend, hibernate, lid. Its `~/.config/hypr` and `~/.config/quickshell`
   are links into this repo, so edits reload live there too. Claude can't see
   into that session (its sockets are in its own `/run/user`): it's checked
   by eye and screenshots. Removed when romain switches over.

   ```sh
   sudo useradd -m -G input,video hyprtest && sudo passwd hyprtest
   setfacl -m u:hyprtest:x /home/romain   # pass through to ~/dotfiles only
   ```

Two sessions of the same user at once (Plasma on one TTY, Hyprland on
another, both as romain) are not an option: Plasma's parts and our daemons
are systemd user units of one user manager, and two desktops would share them.

Every config change: `Hyprland --verify-config`, `hyprctl configerrors`, then
the result checked with `hyprctl -j` or a screenshot. Hyprland and the shell
reload on save.

## Repo layout (to be confirmed as it's built)

- `modules/hyprland/`: packages, `home/.config/hypr/` (Lua: `hyprland.lua`
  requiring `monitors`, `grid`, `windows`, `binds`, `input`, `looknfeel`,
  `autostart`; LuaLS stubs from `/usr/share/hypr/stubs`), the dev rig
  (`dev/nested.sh`, `dev/headless.sh`).
- `modules/<shell>/`: the Quickshell config (`~/.config/quickshell/<shell>/`,
  linked, edited in place) and the Go helper (`pkg/`).
- `modules/<theme>/`: the theme (below).
- `modules/silksong/wallpaper/quickshell/`: the scene's wrappers; the scene
  files move to a folder both wrappers import while Plasma still uses them.
- lodestar: the shortcut translation (Go, with tests).

Quickshell 0.3 no longer resolves a config's symlinks: a linked config gets
its own shell id and state folder. Fine, but link the same path everywhere.

## Phases

Each phase ends with something usable in the nested session, then checked as
`hyprtest`.

1. **Base.** The `hyprland` module (packages: hyprland, quickshell,
   xdg-desktop-portal-hyprland, hyprland-guiutils, grim, slurp, wl-clipboard,
   cliphist, hyprpicker, hyprsunset…), added to wandersail; the nested and
   headless rigs; the `hyprtest` user. Plasma must not change: `lodestar plan`
   shows only additions.
2. **Compositor.** Monitors by EDID description (the desk's BenQs, the laptop
   alone: replaces `work-screens`), the 2×2 grid across screens, hotplug
   (`monitor.added`/`removed`: the laptop alone keeps four desktops, windows
   from the gone screens come back to the matching desktop), floating and
   maximize rules, pinned Discord and Spotify, KDE's window binds (maximize,
   quick tile, move to next screen, kill, Alt+Tab and Alt+\` for the current
   app's windows), input (per-device acceleration as `flat-mice` and the host
   file set it, touchpad, repeat, Num Lock).
3. **Shortcuts.** The lodestar translation; every module's commands bound.
4. **Shell, the minimum to live in it.** Bar, launcher, notifications, OSD
   (with the helper), polkit, tray (KDE Connect, Discord), audio and media,
   network, Bluetooth, battery and power profiles, clipboard history,
   screenshots (grim, slurp, tesseract for text), lock with PAM, idle.
5. **Theme from scratch.** One palette, templates rendered at apply (Go
   templates, as now): Hyprland, the shell, Konsole, GTK 3/4 and libadwaita,
   Qt apps (Dolphin, Kate, Okular: KDE color scheme and a Qt style; Omarchy
   has nothing usable here). To settle first: how the theme stays out of the
   Plasma session while both are in use, since KDE apps read `kdeglobals`
   and GTK apps `~/.config/gtk-*` in either session.
6. **Silksong on desktop and lock screen.** The wrappers above, the bench on
   headless Hyprland, then the real lock: lid, suspend, hibernate, Lock AFK,
   a crash of the shell while locked.
7. **Switch over.** romain logs into Hyprland; `hyprtest` and its ACL go.
   Then whatever was missed: Alt+Tab previews, a grid overview, Klipper-like
   actions if missed.

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

## Recovery

- The shell crashes while locked: the session stays locked (Hyprland shows its
  "lock dead" screen). From a TTY: `hyprctl --instance 0 eval
  'hl.exec_cmd("qs -c <shell>")'` (with `allow_session_lock_restore`), or log
  in to Plasma.
- Hyprland won't start: `start-hyprland` falls back to safe mode; Plasma is
  in the session list.

## Open

- [ ] Names: the shell, the helper, the theme (from books read, as for lodestar).
- [ ] Terminal: Konsole stays (its colors from the theme) or another.
- [ ] File chooser portal: KDE's (Dolphin's dialogs) or GTK's.
- [ ] KWallet in Hyprland (Brave, KDE apps), or another secret service.
- [ ] Changing the workspace animation's style from a bind at runtime: works
      by reading the source, not yet tried.
- [ ] Keeping the theme out of the Plasma session (phase 5).
- [ ] Hotplug: what becomes of windows on a screen that goes away.
