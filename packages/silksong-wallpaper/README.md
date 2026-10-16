# Silksong Aquarium

A Plasma wallpaper (desktop or lock screen) showing a Hollow Knight: Silksong world
spread across all monitors as they physically sit on the desk, with Hornet living in it.

The game's art never enters this repo: the tools read it from your installed copy and
write everything to `~/.local/share/silksong-wallpaper` (caches in `~/.cache/silksong-wallpaper`).

## Setup

```sh
cap="systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0"
tools/extract.py                    # Hornet's animations (and the Bell Beast's, the small creatures'), from the Steam install
for room in tut_02 clover_02c bellway_city belltown mosstown_01; do $cap tools/kit.py harvest $room; done
$cap tools/kit.py atlas ring           # the Clawline rings and poles
$cap tools/kit.py atlas cog            # Cogwork Core parts: the clock's marks, hands and gears
for room in tut_03 bellway_city mosstown_02 belltown; do $cap tools/kit.py particles $room; done  # motes, drips, smoke, dust
$cap tools/kit.py harvest belltown_room_spare --save BelltownFurnishingDesk \
    BelltownFurnishingFairyLights BelltownFurnishingSpa BelltownFurnishingGramaphone
$cap tools/world.py                 # the aquarium world
ln -sfn "$PWD/plasma" ~/.local/share/plasma/wallpapers/com.github.romain-ncls.silksong
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin com.github.romain-ncls.silksong
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper \
    --group com.github.romain-ncls.silksong --group General --key SceneId world
tools/extract_ui.py                 # the lock screen prompt's art and type, from the Steam install
tools/lockscreen.sh install         # the Silksong prompt on the lock screen, from the next login
```

Each step that reads a room loads all of it (about 4 GB of memory): run one at a time,
under a memory cap as above. `world.py` renders its zones one per process for that reason.

The three lines after `world.py` make it the lock screen's wallpaper, the last two give the lock
screen its prompt (see Lock screen). On the desktop, choose Silksong
Aquarium as each screen's wallpaper (Desktop and Wallpaper, from the desktop's menu): its
settings say when it stands still there (see Runtime).

## Tools

- `extract.py`: Hornet's tk2d animation clips, aligned on her pivot.
- `extract_ui.py`: the lock screen prompt's art (`ui/`): the game's own font files (Trajan Pro,
  Perpetua), the frames of the ornaments that grow open (Hornet's dialogue fleur, the weaver's
  prompt fleur) and of Hornet's needle, the full stop of other characters' lines, the inventory's
  hairline, the menu's selection mark, a pair of bug eyes open and half-closed (from the shaman's
  memory), and `Kit.qml`, which lists them. Run it again when an update raises its `KIT_VERSION`.
- `lockscreen.sh`: puts the prompt on the lock screen for this user, or takes it off (see Lock
  screen).
- `world.py`: the aquarium, one small world across the screens. Its rock is authored (a
  ground running under all three screens, a walkway and branches crossing the bezels,
  floating islands, a climbable step, a cliff) and dressed with pieces from the rooms; each
  screen shows a room's background, rendered with the game's camera, shaders, bloom and
  colour grading and receding a little behind the rock; Hornet's house is furnished with her
  Bellhart house's pieces and walled in Bellhart's timber; a lake and waterfall. Plants and
  vines on the game's grass shaders are kept apart to sway (`sway.png`), the station's floor
  bells to jingle (their shake frames), and the rooms' own ambient particles (Verdania's
  fireflies) are exported as emitters. The air (`AIR`) is the game's atmosphere pieces placed
  against our world: light shafts that follow the daylight, mist at the foot of the backdrops
  and on the lake, haze in front; other rooms' particle systems (`MOTES`) add motes, spores,
  drips, low smoke and falling dust, and dust drifting in the shafts. The small life of our
  rooms (`CRITTERS`): the grotto's moss flies behind the rock, dragonflies over the meadow and
  the lake that hold still while Hornet plays her needolin, and Verdania's lilypad flies, which
  sing along to it and fly to their next perch when she comes close (`life.js crittersAt`). Navigation (walk, drop,
  jump, climb) comes from the same rock, so nothing she stands on is hidden.
  `world.py --layout IMAGE` draws just the rock and her ways, quickly.
- `derive.py`: what the wallpaper reads in place of the world's own images, so that each screen
  shows sooner and holds less, and `Derived.qml`, which lists it for the world's build: QOI twins
  of the big images (the tiles, the air, the sheets), the same pixels read 2-4 times faster than
  their PNGs; each screen's own view of the layers (`views/`), the texels it shows of each tile as
  Qt reads them (`derive.qml`), already scaled and cut to the bands that hold anything (about
  half the texels it kept of the tiles); and the sheets at each screen's density (`hornet@40/`,
  `hornet@56/`), as Qt scales them. `world.py` makes them with each world; on a world made
  before, run `tools/derive.py` once (the lock screen reads them from its next lock, the desktop
  once plasmashell restarts). The wallpaper reads the twins where Qt has KDE's image formats
  (kimageformats, which Plasma brings), a view only on the very screen it was made for (this
  desk's, `desk.js`, at the default gap), a set only at its density, and none of them but for the
  world they were made for: else the tiles, the sheets, the PNGs. They take about 134 MB beside
  the PNGs' 40.
- `kit.py`: harvests a room's sprites, at their in-game size, as pieces to dress with, with
  how the game's grass shaders sway them and how grass bends as Hornet walks into it; and a
  room's particle systems (`kit.py particles ROOM`) as templates the world places.
- `terrain.py`: rock shapes and the dressing (silhouettes, moss masses, edge pieces by the
  way a surface faces, plants in front).
- `nav.py`: surfaces and links sized with Hornet's real movement.
- `bake.py`: a single scene from one room (the first version, `SceneId` other than `world`).
- `room.py`, `game.py`: reading Unity scene data and reproducing the game's look.
- `explore.py`: a room's map with a unit grid and its terrain, to choose zones.
- `world.py --wireframe FILE.svg`: the level drawn to scale (rock, water, places, Hornet's
  ways), to agree on the structure before rendering anything.
- `review.py OUT`: the composed world cut into full-resolution crops (every screen, every
  bezel) with the checklist they are reviewed against.
- `check_plan.js`: Hornet's day plans against the built world (`node tools/check_plan.js 7`):
  any teleport between moves, and her fastest speed in each kind of move.
- `check_events.js`: when `life.js` says Hornet and the Bell Beast next change, against what they
  show (`node tools/check_events.js [LIFE_JS] [DAYS] [YYYY-MM-DD]`): any change sooner, which a
  screen would draw late.
- `plan_identity.js`: two versions of `life.js` against each other (`node tools/plan_identity.js
  REF_LIFE NEW_LIFE [DAYS]`): her plans, the Bell Beast's and the small life's, and what the
  screens ask of them moment by moment, must be identical after a change meant to make them
  cheaper.
- `preview.qml` + `desk.py`: render each screen on a virtual display and lay them out as on
  the desk (`xvfb-run -a -s "-screen 0 5760x1200x24" env QT_QPA_PLATFORM=xcb
  QT_PLUGIN_PATH=/run/current-system/sw/lib/qt-6/plugins qml tools/preview.qml -- OUT --world
  09:30 22:00`, then `tools/desk.py OUT`; the plugin path brings KDE's image formats, for the
  QOI twins). It shows the screens as `desk.js` has them, as Qt reports this desk's (so with
  their views), as does `bench.py`.
  `viscmp.py REF OUT` compares two sets of renders: a change meant to leave the look alone
  stays within a difference of 1.
- `bench.py`: the world's cost as the lock screen runs it, one window per screen in one process
  on a headless Weston with the real GPU (`tools/bench.py --at 07:17`, or with a date,
  `--at 2026-10-12T07:17`, to measure the same moment of her day again): when each screen
  shows (how far apart, and whether it still lacked anything) and has all its images in, how
  often they changed on the way, then CPU, frames and ticks per window, GPU time and memory,
  and any warning Qt or the QML printed. `--near-hz` sets `AmbientNearHz`, and
  `--no-system-plugins` leaves KDE's image formats out (the PNGs then); `--fader` draws each
  screen through the lock screen's WallpaperFader and `--greeter` makes each scene only after
  holding the GUI thread a moment, as the greeter does; `--busy-anim` keeps an animation
  running, as a panel does in plasmashell; `--idle`, `--hide-at`/`--show-at`,
  `--pause-at`/`--resume-at` and `--jump-at` time the outputs going idle, the scenes hidden or
  paused (as the desktop's while a window is focused; after which, how soon each screen drew the
  current moment, and whether it lacked a sheet) and the clock jumping; `--trace-ticks` logs one
  screen's every tick, `--trace-frames` sums up, for the grass, the Bell Beast, the bells, Hornet
  and the small life, how often each changed and any frame skipped, held or drawn late;
  `--profile` the render times of every frame.

## Lock screen

`lockscreen/` is Plasma 6.7's lock screen prompt with the game's look, chosen among mockups: the
pause menu's column between Hornet's dialogue fleur and the weaver's prompt fleur, the clock and
date in Trajan Pro, for each character typed the full stop the game ends other characters' lines
with (a pair of bug eyes at the end of the line shows the password), the inventory's hairline
under them, and Sleep and Switch User as menu items. A long password's full stops get smaller,
then the field grows. Messages are written out as dialogue is, ending on Hornet's needle, and the
column opens to let them in. While it's up the aquarium behind is darkened and blurred; idle, the
lock screen shows the aquarium alone, as before. Everything it does is Plasma's own
(`SilksongLockUi.qml` keeps its authenticator calls, messages, timers and keys), and
`LockScreen.qml` shows Plasma's own prompt when the art is missing or older than the prompt needs
(`extract_ui.py` not run, or not since an update) or the Silksong one can't be loaded.

The lock screen takes its prompt from a shell package: the one `plasmashellrc` names, else
`$PLASMA_DEFAULT_SHELL`, else `org.kde.plasma.desktop`, the desktop's. `lockscreen.sh install`
changes nothing in the system and leaves the desktop alone:

- `~/.local/share/plasma/shells/com.github.romain-ncls.silksong-lock`, a shell package with only
  `lockscreen/` (Plasma falls back to `org.kde.plasma.desktop` for the rest): `LockScreen.qml`
  copied (Plasma refuses an entry file whose real path leaves its package), the others linked,
  to `lockscreen/` and to the system's own prompt files. A Plasma env script links it again at
  each login, which follows Plasma updates on NixOS and Arch alike; after editing
  `LockScreen.qml`, `lockscreen.sh link`.
- a drop-in giving KWin, which starts the lock screen, `PLASMA_DEFAULT_SHELL` naming it. Only
  KWin: plasmashell reads the same variable and would lay out a new, empty desktop
  (`plasma-<shell>-appletsrc`).

It applies from the next login (KWin's next start). `lockscreen.sh uninstall` takes both away.

## Runtime

A running desktop wallpaper reloads the world by itself when `world.py` writes a new one, and
Hornet's clips when `extract.py` does (her day is then planned again with them), even where it
started without them, if their folder was there (the lock screen, which lives for minutes, doesn't
watch for them); changes to the QML itself need plasmashell restarted
(`systemctl --user restart plasma-plasmashell`), the lock screen picks them up at the next lock.
Hornet's sheets are shared by every zone and
coloured for the zone she's in by `shaders/hornet.frag`; the waterfall and the lake move in
`shaders/waterfall.frag` and `lake.frag`; plants sway in `sway.vert` (the game's grass
formula, read from its shaders; grass bends as Hornet walks through it) and every particle
system runs in `particle.vert` (Unity's particle system, one grid per emitter). After editing a shader, compile it, e.g.
`qsb --glsl "100 es,120,150,300 es,330" --hlsl 50 --msl 12 -o lake.frag.qsb lake.frag`
(qsb is in qt6.qtshadertools). Each screen draws its own view of the layers where `derive.py`
made one for it, else the tiles it shows, of each only the part it shows. Only the screen she's
on (or about to reach) loads her sheets (at its density, where a set was made for it), and only
those of the clips she plays in the next 40 seconds, letting each go 10 seconds after it leaves
them.

Each screen stays black until it has everything it shows (her sheets for the next few seconds
included), then fades in, all the screens of a process together (`reveal.js`), or after 4
seconds with whatever it has; on the desktop, Plasma's splash screen and panels wait for it. It
goes black again to load anew when the world is rebuilt or the screens change.

Each screen keeps its own clock (`WorldScene.qml`), which only ticks when something it shows
changes: on its window's frames while Hornet moves on it; else just after her clip's next cell,
the Bell Beast's and the floor bells' next frames, and at the pace of what moves on its own (the
water 30 times a second, plants and particles 15, on the grass's own frames; 12 with the Bell
Beast's). Where she rests, that's `AmbientNearHz` times a second if more: 30 by default, 60 for
every frame, 0 for the screen's own pace. It stops while its scene is hidden (the desktop of
another activity), paused (below) or its window draws nothing (the screen off, the window
covered), and starts again at the current moment, as it does when the machine wakes or the clock
is set; if what it shows then isn't loaded (her clips of a minute later), it holds its last frame
until it is, 300 ms at most, rather than draw her missing.

On the desktop the world stands still while you work (`PauseWhen`, in its settings, from the
windows Plasma's task manager sees, `Pauser.qml`): by default on every screen together while
any window is focused, or only on the screen a window covers, maximized or full screen. Windows
the taskbar leaves out (KRunner, Yakuake) don't count, nor plasmashell's own (the wallpaper's
settings), nor any while the desktop is shown: clicking the desktop, or Show Desktop, starts it
again, a tenth of a second later (focus going from one window to another doesn't). The lock
screen never stands still. A desktop hidden for 10 minutes (another activity's) lets go of all it
loaded, and comes back from black; once no screen shows the world, `life.js` lets go of the day's
plans too.
