# TV reference — TCL 65C711

Notes on the TV that mpv plays on, how it's set up, and why. Written 2026-10-02.

## The TV

- **Model:** TCL 65C711, 2020 entry-level 4K QLED, Android TV 9 (internal name "BeyondTV2", Realtek chip).
- **60 Hz** panel, **no local dimming** (global dimming only: the whole backlight
  brightens or dims at once). Its sibling 65C715 is rated around **350 nits** peak.
- Accepts HDR10 / HDR10+ / HLG / Dolby Vision, but it's too dim and has no local dimming
  to really show HDR. In practice HDR on this TV looks dim and washed out.
- Connected to the PC over HDMI. Menu language: **French**.

## Decisions

- **Windows HDR stays off.** mpv converts HDR to SDR itself (tone mapping, `profile=high-quality`).
  That looks better than the TV's own HDR handling. The user prefers mpv's look over VLC's
  (mpv is brighter, ~+20% mid-tones, ~+28% highlights on HDR content).
- **Picture preset stays on "Dynamique"** and **color temperature on "Normale"**. This is the user's
  preference: other presets look flat to them, and Warm looks orange to them. Don't push for
  Movie/Warm again; only reduce the processing that costs detail.

## Current picture settings (HDMI PC input, preset Dynamique)

Read from the TV over adb on 2026-10-02. "Changed" = changed by the user that day.

**Image (main menu)**

| Setting | Value |
|---|---|
| Préréglage de l'image | Dynamique |
| Luminosité | 60 |
| Saturation des couleurs | 60 |
| Appliquer tout mode d'image | Source actuelle |

**Paramètres avancés → Paramètres de luminosité**

| Setting | Value | Notes |
|---|---|---|
| Luminosité | 60 | |
| Contraste | 90 | |
| Niveau de noir | 50 | |
| Contraste Dynamique | Arrêt | |
| Renforcement du noir | Faible | |
| Rétroéclairage dynamique | Luminosité+ | adjusts the backlight per scene (see brightness pumping below) |
| Micro atténuation | **Faible** | **changed** from Fort to reduce brightness pumping |

**Paramètres avancés → Couleur**

| Setting | Value |
|---|---|
| Saturation des couleurs | 60 |
| Teinte | 50 |
| Nuance des couleurs | Normale |
| Mode RVB | Arrêt |
| Balance des blancs / Espace colorimétrique | not read |

**Paramètres avancés → Clarté**

| Setting | Before | Now |
|---|---|---|
| Netteté | 60 | **10** (changed) |
| Filtrage bruits MPEG | Moyen | **Arrêt** (changed) |
| Réduction de bruits | Arrêt | Arrêt |
| Lissage numérique | Arrêt | Arrêt |

**Paramètres avancés → Mouvement**

| Setting | Value |
|---|---|
| Netteté de mouvement LED | NON |

There is no motion smoothing (MEMC) on this model.

**Paramètres avancés → Réglages d'écran**

| Setting | Value | Notes |
|---|---|---|
| Format auto | OUI | |
| Mode écran | 16:9 | |
| Surbalayage | NON | overscan off: pixel-for-pixel, correct for a PC |

All values above were confirmed by reading the TV again after the user's changes.

**Not read yet:** Couleur → Balance des blancs / Espace colorimétrique (submenus), and the HDMI
black level (range) setting (location in the menu unknown).

## Why these settings

- **Netteté 60 → low:** at 60 the TV draws bright halos around every edge, including subtitles,
  on top of mpv's already-sharp scaling.
- **Filtrage bruits MPEG → Off:** it's meant for low-quality broadcasts. On clean 4K files it
  blurs fine detail.
- **Micro atténuation Fort / Rétroéclairage dynamique Luminosité+:** these give the deep blacks and
  punch of Dynamique, but they also make the overall brightness change from scene to scene.

## Brightness changing from scene to scene

Three things can cause it, and they add up:
1. **Micro atténuation (now Faible, was Fort)** dims the whole backlight on dark scenes. With global dimming
   the whole screen dims at once.
2. **Rétroéclairage dynamique (Luminosité+)** adjusts the backlight to the average brightness of each scene.
3. **mpv's HDR tone mapping (HDR files only)**: mpv measures each scene's brightness and adapts
   its conversion (`hdr-compute-peak`, plus Dolby Vision metadata). This is intentional and usually subtle.

To find which one bothers you: micro dimming is now Faible. If brightness still pumps, try
Rétroéclairage dynamique off next, and watch the same scene again.

## Slow color recovery after toggling Windows HDR

When Windows HDR is turned on or off, the TV takes a while to look right again. The likely
causes (not tested on this TV):
- **The HDMI signal changes type** (SDR ↔ HDR10, different color space). The TV re-syncs and
  switches between its **separate SDR and HDR picture settings**.
- **The dynamic backlight and micro dimming then re-adapt gradually** over a few seconds, which
  looks like colors and brightness "settling".
- Windows also re-applies its own color settings for the desktop.

This is mostly the TV's signal handling plus the dynamic backlight, not the Dynamique preset itself.
It's another reason to keep Windows HDR off.

## Controlling the TV from the PC (adb)

- **Setup:** Developer options enabled (Settings → Device Preferences → About → Build ×7),
  **USB debugging** turned on. This alone opens adb over the network; this TV's menu has no separate
  "Network debugging" entry. Turn USB debugging off when done.
- **TV address:** `192.168.1.119:5555` (may change if the router assigns a new IP). This PC
  is already approved on the TV.
- **adb:** Google platform-tools for Linux, run from WSL. It's not installed permanently; download it from
  `https://dl.google.com/android/repository/platform-tools-latest-linux.zip`.
- **What works:**
  - `adb shell input keyevent KEYCODE_DPAD_UP|DOWN|LEFT|RIGHT|CENTER|BACK` presses remote buttons.
  - `adb shell uiautomator dump` reads the on-screen menu as **text**, including which item
    is selected (`selected="true"`, or a focused `FrameLayout`).
  - `adb shell dumpsys window | grep mCurrentFocus` shows what's on screen. `com.tcl.settings` means
    the picture menu is open; `com.tcl.tv/.TVActivity` means the HDMI input with no menu.
- **What doesn't work:**
  - **Screenshots:** `screencap` is refused (`SurfaceFlinger: FB is protected: PERMISSION_DENIED`)
    while the HDMI input is on screen, even with a menu open.
  - **Opening the menu:** `KEYCODE_SETTINGS` doesn't open it; the user opens it with the remote
    (it opens on "Réglages": Image / Son / Système / Plus de réglages; CENTER on Image enters it).
    The menu also closes by itself after a while, and key presses then go to the HDMI screen.
  - **Reading or writing picture settings directly:** they live in protected TCL system
    services (`tcl_tv`, `TVKitService`), not in Android's settings. `com.tcl.settings` refuses
    access. Don't poke those services.
- **Safety:** always read which item is selected before pressing CENTER, because
  "Réinitialiser image" (resets all picture settings) is in the same menu.

Helper used on 2026-10-02 (presses keys, then prints the menu with `>>` on the selected row):

```bash
#!/bin/bash
A="adb -s 192.168.1.119:5555"
for k in "$@"; do $A shell input keyevent "$k"; sleep 0.6; done
sleep 0.4
$A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
$A pull /sdcard/ui.xml ./ui.xml >/dev/null 2>&1; $A shell rm -f /sdcard/ui.xml
python3 - ./ui.xml <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
def walk(n, sel=False):
    sel = sel or n.get('selected') == 'true' or (n.get('focused') == 'true' and n.get('class','').endswith('Layout'))
    t = (n.get('text') or '').strip()
    if t: print(('>> ' if sel else '   ') + t)
    for c in n: walk(c, sel)
walk(root)
PY
```

**Menu layout (French):** Image → Préréglage de l'image / Luminosité / Saturation des couleurs /
Paramètres avancés / Appliquer tout mode d'image / Réinitialiser image.
Paramètres avancés → Paramètres de luminosité / Couleur / Clarté / Mouvement / Réglages d'écran.

## Considered and skipped

- **hdr-mode.lua** (https://github.com/dyphire/mpv-scripts/blob/main/hdr-mode.lua, needs
  https://github.com/dyphire/mpv-display-plugin): turns Windows HDR on/off automatically per video
  and sends HDR straight to the display. Skipped on 2026-10-03: this TV's HDR is too weak, the user
  prefers mpv's own HDR conversion, and every switch would trigger the TV's slow color recovery.
  **Worth revisiting with a better HDR display** (≈600+ nits with local dimming, or OLED).
