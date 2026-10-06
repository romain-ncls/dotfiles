# Silksong Aquarium

A Plasma wallpaper (desktop or lock screen) showing a Hollow Knight: Silksong scene
spread across all monitors as they physically sit on the desk, with Hornet living in it.

The game's art never enters this repo: the tools read it from your installed copy and
write everything to `~/.local/share/silksong-wallpaper`.

## Setup

```sh
tools/extract.py          # Hornet's animations, from the Steam install
systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 tools/bake.py mosshome
ln -sfn "$PWD/plasma" ~/.local/share/plasma/wallpapers/com.github.romain-ncls.silksong
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin com.github.romain-ncls.silksong
```

Baking a scene loads a whole room (about 4 GB of memory): run one at a time, under a
memory cap as above.

## Tools

- `extract.py`: Hornet's tk2d animation clips, aligned on her pivot.
- `bake.py`: a scene from a room. Background and foreground layers rendered with the
  game's camera, shaders, bloom and colour grading; enemies and hazards removed; the
  ground profile from the room's terrain colliders; Hornet's sheets in the room's colours.
- `room.py`, `game.py`: reading Unity scene data and reproducing the game's look.
- `preview.qml` + `desk.py`: render each screen offscreen and lay them out as on the desk.
