-- Hyprland's config (modules/hyprland; plan: docs/hyprland.md). Lua since
-- 0.55, and only Lua since 0.57: write it from the current wiki and the stubs
-- in /usr/share/hypr/stubs, not from the hyprlang examples found online.
-- HYPR_DEV is set by dev/nested.sh and dev/headless.sh.

require("input")
require("binds")

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
