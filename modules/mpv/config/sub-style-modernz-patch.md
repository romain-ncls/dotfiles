# sub-style ↔ ModernZ patch

`scripts/sub-style.lua` does all the work (menu, presets, remembering the choice).
`scripts/modernz.lua` was patched to draw an **"Aa" button** next to the subtitles button
that shows the current style state and opens the menu. **Updating ModernZ overwrites
this patch** — this file is everything needed to put it back.

Patched against **ModernZ v0.3.3**, mpv v0.41. Every patched line is tagged
`-- [sub-style]` (`grep -n "sub-style\]" scripts/modernz.lua` to check if it's still there).

## How the two scripts talk

- `sub-style.lua` publishes `user-data/sub-style` = `{icon, tooltip, preset}` whenever the
  preset or the subtitle track changes.
  - `icon` is one of: `own` (styled .ass using its own style), `preset` (one of our styles
    is applied), `plain` (plain text subs, mpv default look), `image` (PGS/VobSub, can't be
    restyled), `none` (no subtitle selected).
- ModernZ observes that property and re-inits the OSC. The button is:
  - amber "Aa" (#FFB300) → `own`
  - accent "Aa" (`seekbarfg_color`) → `preset`
  - white "Aa" (`side_buttons_color`) → `plain`
  - gray "Aa" (`ne.off`) → `image` / `none`
- The script registers as `sub_style` (mpv turns `-` into `_`), so the binding is
  `sub_style/menu`, not `sub-style/menu`.
- Left click runs `sub_style_mbtn_left_command` (default `script-binding sub_style/menu`).
- The icon font (`fonts/modernz-icons.ttf`) has no "text style" glyph, so the button is
  plain text "Aa" in Arial bold via inline ASS tags.

## What to re-apply (5 spots)

1. **user_opts** — after `subtitles_button = true,` add the `sub_style_button` option; after
   `sub_track_wheel_up_command` add `sub_style_mbtn_left_command`.
2. **state table** — after `sub_track_count = 0,` add `sub_style = nil,`.
3. **osc_init()** — after the `sub_track` element (`bind_buttons("sub_track")`) add the
   `sub_style` element.
4. **layouts** — right after each `sub_track` placement, place `sub_style` the same way:
   default layout (`left_side_button`), compact and mini (`right_side_button`). Other layouts
   are fine without it (ModernZ drops elements that have no layout).
5. **observers** — after `mp.observe_property("track-list", ...)` observe `user-data/sub-style`.

If ModernZ's internals have changed, the intent is: add a button element named `sub_style`,
place it next to `sub_track` in every layout, refresh it when `user-data/sub-style` changes.

## Exact diff (against ModernZ v0.3.3)

```diff
--- a/scripts/modernz.lua
+++ b/scripts/modernz.lua
@@ -89,6 +89,7 @@
 
     -- Buttons display and functionality
     subtitles_button = true,               -- show the subtitles menu button
+    sub_style_button = true,               -- [sub-style] show the "Aa" subtitle style button (needs scripts/sub-style.lua)
     audio_tracks_button = true,            -- show the audio tracks menu button
     jump_buttons = true,                   -- show the jump backward and forward buttons
     jump_amount = 10,                      -- change the jump amount in seconds
@@ -258,6 +259,9 @@
     sub_track_wheel_down_command = "cycle sub",
     sub_track_wheel_up_command = "cycle sub down",
 
+    -- [sub-style] subtitle style button mouse actions
+    sub_style_mbtn_left_command = "script-binding sub_style/menu",
+
     -- play/pause button mouse actions
     play_pause_mbtn_left_command = "cycle pause",
     play_pause_mbtn_mid_command = "cycle-values loop-playlist inf no",
@@ -606,6 +610,7 @@
     idle_active = false,
     audio_track_count = 0,
     sub_track_count = 0,
+    sub_style = nil,                        -- [sub-style] published by sub-style.lua
     playlist_count = 0,
     playlist_pos_1 = 0,
     pause = false,
@@ -2281,6 +2286,7 @@
     if playlist_button then left_side_button("playlist", 550) end
     if audio_track and user_opts.audio_tracks_button then left_side_button("audio_track", 650) end
     if subtitle_track and user_opts.subtitles_button then left_side_button("sub_track", 750) end
+    if subtitle_track and user_opts.sub_style_button then left_side_button("sub_style", 750) end -- [sub-style]
 
     if audio_track and user_opts.volume_control then
         -- volume button
@@ -2621,6 +2627,7 @@
     right_side_button("fullscreen", 300, user_opts.fullscreen_button)
     right_side_button("ontop", 400, user_opts.ontop_button and not (window_controls_enabled() and user_opts.ontop_in_topbar and state.ontop))
     right_side_button("sub_track", 500, user_opts.subtitles_button and state.sub_track_count > 0)
+    right_side_button("sub_style", 500, user_opts.sub_style_button and state.sub_track_count > 0) -- [sub-style]
     right_side_button("audio_track", 600, user_opts.audio_tracks_button and state.audio_track_count > 0)
     right_side_button("playlist", 300, user_opts.playlist_button)
     right_side_button("download", 800, state.is_url and user_opts.download_button)
@@ -2796,6 +2803,7 @@
     right_side_button("fullscreen", 250, user_opts.fullscreen_button)
     right_side_button("ontop", 300, user_opts.ontop_button and not (window_controls_enabled() and user_opts.ontop_in_topbar and state.ontop))
     right_side_button("sub_track", 400, user_opts.subtitles_button and state.sub_track_count > 0)
+    right_side_button("sub_style", 400, user_opts.sub_style_button and state.sub_track_count > 0) -- [sub-style]
     right_side_button("audio_track", 500, user_opts.audio_tracks_button and state.audio_track_count > 0)
     right_side_button("playlist", 600, user_opts.playlist_button)
     right_side_button("download", 700, state.is_url and user_opts.download_button)
@@ -3286,6 +3294,19 @@
     ne.nothingavailable = locale.no_subs
     bind_buttons("sub_track")
 
+    -- [sub-style] "Aa" button: amber = file's own style, accent = preset applied, white = plain, gray = none/image
+    ne = new_element("sub_style", "button")
+    local ss = state.sub_style or {icon = "none", tooltip = "Subtitle style"}
+    ne.enabled = state.sub_track_count > 0
+    ne.off = ss.icon == "none" or ss.icon == "image"
+    ne.content = function ()
+        local icon = (state.sub_style or {}).icon
+        local color = icon == "preset" and user_opts.seekbarfg_color or icon == "own" and "#FFB300" or user_opts.side_buttons_color
+        return "{\\fnArial\\b1\\fs" .. (user_opts.layout == "mini" and 14 or 18) .. "\\1c&H" .. osc_color_convert(color) .. "&}Aa"
+    end
+    ne.tooltipF = function () return (state.sub_style or ss).tooltip end
+    bind_buttons("sub_style")
+
     -- vol_ctrl
     ne = new_element("vol_ctrl", "button")
     ne.enabled = state.audio_track_count > 0
@@ -4147,6 +4168,7 @@
     request_init()
 end)
 mp.observe_property("track-list", "native", update_tracklist)
+mp.observe_property("user-data/sub-style", "native", function(_, val) state.sub_style = val; request_init() end) -- [sub-style]
 observe_cached("playlist-count", request_init)
 observe_cached("playlist-pos-1", request_init)
 observe_cached("chapter-list", function ()
```

## Options (script-opts/modernz.conf)

```
sub_style_button=yes
sub_style_mbtn_left_command=script-binding sub_style/menu
```
