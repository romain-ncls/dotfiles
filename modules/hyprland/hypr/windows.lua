-- Windows: the scrolling layout everywhere (docs/hyprland.md: columns as
-- wide as the screen, the terminal half as wide), and where some apps go.

hl.config({
    general = {
        layout = "scrolling",
    },
    scrolling = {
        column_width = 1.0,
        fullscreen_on_one_column = true,
    },
    decoration = {
        dim_special = 0, -- Spotify's scratchpad leaves Discord's left side in view
    },
    misc = {
        focus_on_activate = true,
    },
})

hl.window_rule({ name = "terminal-half", match = { class = [[^com\.mitchellh\.ghostty$]] }, scrolling_width = 0.5 })

-- The middle screen's workspace: Discord, and Teams (Brave's web app, two
-- installs of it; crx_ under XWayland, brave- under Wayland).
hl.window_rule({ name = "comms-discord", match = { class = "^discord$" }, workspace = "name:comms silent" })
hl.window_rule({
    name = "comms-teams",
    match = { class = "^(crx_|brave-)(ompifgpmddkgmclendfeacglnodjjndh|cifhbcnohmdccbgoicgdjpfamggdegmo)" },
    workspace = "name:comms silent",
})

-- Spotify: a scratchpad over Discord, its servers and channels (the first
-- 375 px) left uncovered.
hl.window_rule({
    name = "spotify-scratchpad",
    match = { class = "^[Ss]potify$" },
    workspace = "special:spotify",
    float = true,
    move = { 375, 0 },
    size = { "monitor_w - 375", "monitor_h - 40" }, -- above shadesmar's bar
})

-- Dialogs and picture-in-picture float (Omarchy's default/hypr/apps/).
hl.window_rule({ name = "pip", match = { title = "^Picture.in.[Pp]icture$" }, float = true, pin = true, keep_aspect_ratio = true })
hl.window_rule({ name = "dialogs", match = { modal = true }, float = true })
