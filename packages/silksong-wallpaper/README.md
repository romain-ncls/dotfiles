# Silksong Aquarium

A Plasma wallpaper (desktop or lock screen) showing a Hollow Knight: Silksong world
spread across all monitors as they physically sit on the desk, with Hornet living in it.

The game's art never enters this repo: the tools read it from your installed copy and
write everything to `~/.local/share/silksong-wallpaper` (caches in `~/.cache/silksong-wallpaper`).

## Setup

```sh
cap="systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0"
tools/extract.py                    # Hornet's animations, from the Steam install
for room in tut_02 clover_02c bellway_city belltown mosstown_01; do $cap tools/kit.py harvest $room; done
$cap tools/kit.py atlas ring           # the Clawline rings and poles
$cap tools/kit.py atlas cog            # Cogwork Core parts: the clock's marks, hands and gears
$cap tools/kit.py harvest belltown_room_spare --save BelltownFurnishingDesk \
    BelltownFurnishingFairyLights BelltownFurnishingSpa BelltownFurnishingGramaphone
$cap tools/world.py                 # the aquarium world
ln -sfn "$PWD/plasma" ~/.local/share/plasma/wallpapers/com.github.romain-ncls.silksong
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin com.github.romain-ncls.silksong
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper \
    --group com.github.romain-ncls.silksong --group General --key SceneId world
```

Each step that reads a room loads all of it (about 4 GB of memory): run one at a time,
under a memory cap as above. `world.py` renders its zones one per process for that reason.

## Tools

- `extract.py`: Hornet's tk2d animation clips, aligned on her pivot.
- `world.py`: the aquarium, one small world across the screens. Its rock is authored (a
  ground running under all three screens, a walkway and branches crossing the bezels,
  floating islands, a climbable step, a cliff) and dressed with pieces from the rooms; each
  screen shows a room's background, rendered with the game's camera, shaders, bloom and
  colour grading and receding a little behind the rock; Hornet's house is furnished with her
  Bellhart house's pieces and walled in Bellhart's timber; a lake and waterfall. Plants and
  vines on the game's grass shaders are kept apart to sway (`sway.png`), and the rooms' own
  ambient particles (Verdania's fireflies) are exported as emitters. Navigation (walk, drop,
  jump, climb) comes from the same rock, so nothing she stands on is hidden.
  `world.py --layout IMAGE` draws just the rock and her ways, quickly.
- `kit.py`: harvests a room's sprites, at their in-game size, as pieces to dress with, with
  how the game's grass shaders sway them and how grass bends as Hornet walks into it.
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
- `preview.qml` + `desk.py`: render each screen on a virtual display and lay them out as on
  the desk (`xvfb-run -a -s "-screen 0 5760x1200x24" env QT_QPA_PLATFORM=xcb qml
  tools/preview.qml -- OUT --world 09:30 22:00`, then `tools/desk.py OUT`).

## Runtime

A running wallpaper reloads the world by itself when `world.py` writes a new one; changes to
the QML itself need plasmashell restarted (`systemctl --user restart plasma-plasmashell`),
the lock screen picks them up at the next lock. Hornet's sheets are shared by every zone and
coloured for the zone she's in by `shaders/hornet.frag`; the waterfall and the lake move in
`shaders/waterfall.frag` and `lake.frag`; plants sway in `sway.vert` (the game's grass
formula, read from its shaders; grass bends as Hornet walks through it) and the fireflies fly
in `particle.vert` (Unity's particle system, one grid per emitter). After editing a shader, compile it, e.g.
`qsb --glsl "100 es,120,150,300 es,330" --hlsl 50 --msl 12 -o lake.frag.qsb lake.frag`
(qsb is in qt6.qtshadertools). Only the screen she's on (or about to reach) loads her sheets,
and only those of the clips she plays in the next 40 seconds.
