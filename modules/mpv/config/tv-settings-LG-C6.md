# TV reference — LG C6 77"

Notes on menadion's screen, how it's set up for the PC, and why. Written
2026-11-27, the day it arrived. It replaces the TCL 65C711
(`tv-settings-TCL-65C711.md`). The TV's purchase, its apps and Jellyfin on
it: `~/git/homelab/docs/home-cinema.md`.

## The TV

- **Model:** LG OLED77C6 (2026), webOS 26, "Primary RGB Tandem" WOLED panel.
  Menu language: French.
- **Reviews:** ~2,000 nits on a 10% window, ~340 nits full screen
  (Filmmaker). Input lag 12.9 ms at 60 Hz. Dolby Vision, HDR10, HLG; no
  HDR10+, no DTS.
- **HDMI 2.1:** 4K 120 Hz, VRR 40–120 Hz, ALLM, 48 Gbps (FRL 12 Gbps × 4).
- **What it tells the PC (EDID):** sRGB primaries in the base block (not
  its real gamut), no HDR luminance values. The Dolby Vision block has the
  real ones: red 0.6875, 0.3086; green 0.2461, 0.7109; blue 0.1484, 0.0469;
  max 2147 nits.

## TV settings for the PC's input

Menu names may differ a little on the TV; they weren't all checked there.

| Setting | Value | Why |
|---|---|---|
| HDMI Ultra HD Deep Colour (PC's port) | On | Off, the EDID stops at HDMI 2.0: 4K 30 Hz at most, no VRR |
| Input icon | PC | Otherwise the TV drops 4:4:4 and small text gets colour fringes |
| Picture mode, SDR and HDR | Filmmaker | Desktop and films. The TV keeps one per input and per signal type |
| Picture mode for games | Optimiseur de jeu | Lowest lag, VRR, HGIG |
| Dynamic tone mapping (in Optimiseur de jeu) | HGIG | The TV shows what KDE sends, no second tone mapping |
| VRR & G-Sync (Optimiseur de jeu's settings) | On | |
| Energy Saving Step | Off | On out of the box, it dims the picture |

- **The picture mode switched to Optimiseur de jeu on its own** once, when
  the PC first sent 4K 120 Hz HDR. Probably Instant Game Response (ALLM):
  it switches when it thinks a game runs. KWin tells the TV what the
  fullscreen window is (HDMI content type): Game only for games that say
  so, Cinema for mpv, Graphics for the desktop. If it switches during
  desktop use again, turn Instant Game Response off for that port.
- **Burn-in care:** LG's protections at their defaults (screen move, logo
  dimming, pixel cleaning at switch-off); don't cut standby power at the
  wall, the cleaning runs after switch-off. On the PC: the taskbar
  auto-hides, and blackout blacks the screen after 5 minutes idle
  (`docs/decisions.md`, "OLED TV").

## PC side (KDE)

| Setting | Value | Where it's set |
|---|---|---|
| Mode | 3840×2160 at 119.88 Hz | KWin's own config |
| Scale | 200% | `hosts/menadion/display.sh` |
| HDR, wide colour gamut | On | `display.sh` |
| HDR colour profile | `~/.local/share/icc/lg-c6-sdr300-peak1950.icc` (ICC) | `display.sh`, made by `hosts/menadion/hdr-icc/` |
| SDR white, peak | 300 nits, 1950 nits | in the profile |
| SDR colour intensity | 50% | `display.sh` |
| VRR | Automatic (fullscreen only) | `display.sh` |

- **Peak 1950 nits** is what KDE's `hdrcalibrator` found in Filmmaker.
- **SDR white 300 nits**, under what the TV holds full screen (~340), so
  big white windows don't get dimmed by the TV. It was 400 the first
  evening. Change it in the profile (`-sdr`), not in System Settings.
- **Colour intensity** reaches apps that leave colour to KDE: the desktop,
  wallpapers, most apps, SDR video in mpv, and Brave, whose own colour
  management menadion turns off (HDR video in the browser plays as SDR).
  Details in `docs/decisions.md`.

## mpv

- **SDR video** (anime): handed to KDE (`sdr-to-kde` profile in mpv.conf),
  so it gets the desktop's colour intensity.
- **HDR10, HLG, Dolby Vision:** mpv tone-maps them itself to the peak KDE
  gives (1950 nits), then sends them as HDR.
- **Dolby audio** (AC-3, E-AC-3 with Atmos) goes to the TV undecoded
  (`dolby-to-tv` profile; the TV shows its Atmos logo), so it plays at the
  same level as in the TV's apps. Decoded by mpv, it was louder: no
  dialnorm, and a downmix that isn't normalized. mpv's volume doesn't reach
  these tracks. DTS and TrueHD are still decoded by mpv.
- **To check:** subtitles in HDR video. On the TV's Jellyfin app, white
  subtitles in Dolby Vision were too bright; mpv has `sub-hdr-peak` and
  `image-subs-hdr-peak` for that.
