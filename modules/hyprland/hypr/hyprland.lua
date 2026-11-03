-- Hyprland's config (modules/hyprland; plan: docs/hyprland.md). Lua since
-- 0.55, and only Lua since 0.57: write it from the current wiki and the stubs
-- in /usr/share/hypr/stubs, not from the hyprlang examples found online.
-- HYPR_DEV is set by dev/nested.sh and dev/headless.sh.

-- hyprslide (modules/hyprslide): the grid's slides, diagonals included.
-- Missing, or built for another Hyprland (which won't load it), it's
-- silently not there and the grid fades instead.
pcall(hl.plugin.load, "/usr/lib/hyprslide/hyprslide.so")

require("looknfeel")
require("session")
require("input")
require("windows")
require("binds") -- requires grid, which requires monitors
require("dev")

-- The modules' own shortcuts (bemoji, mutectl, soundboard…), written by
-- lodestar from their shortcuts: with Plasma's keys. Missing until the
-- first apply.
pcall(require, os.getenv("HOME") .. "/.local/share/lodestar/hyprland-shortcuts")

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
    ecosystem = {
        no_update_news = true, -- release notes are read before upgrading
        no_donation_nag = true,
    },
})
