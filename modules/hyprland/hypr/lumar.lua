-- lumar, the session's look (modules/lumar; docs/hyprland.md). Two layouts:
-- flush, the default, as close to maximized as it gets (no gaps, no
-- borders, square windows: rounded ones touching the screen's edges and each
-- other leave notches; the bar docked), and floating (gaps, 10 px corners,
-- the bar floating), swapped with Meta+G. The layout is kept in
-- ~/.local/state/lumar/mode, which shadesmar follows for its bar. The
-- colors are lumar's colors.lua, from the palette both sessions share.

local L = {}

local home = os.getenv("HOME")
local state = (os.getenv("XDG_STATE_HOME") or home .. "/.local/state") .. "/lumar"
local data = (os.getenv("XDG_DATA_HOME") or home .. "/.local/share") .. "/lumar"

local LAYOUTS = {
    flush = {
        general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
        decoration = { rounding = 0 },
    },
    floating = {
        general = { gaps_in = 4, gaps_out = 8, border_size = 0 },
        decoration = { rounding = 10 },
    },
}

local function saved()
    local f = io.open(state .. "/mode")
    if not f then
        return "flush"
    end
    local mode = f:read("l")
    f:close()
    return LAYOUTS[mode] and mode or "flush"
end

function L.set(mode)
    hl.config(LAYOUTS[mode])
    L.mode = mode
end

-- Meta+G: the other layout, kept for the next login and for shadesmar.
function L.toggle()
    local mode = L.mode == "floating" and "flush" or "floating"
    os.execute("mkdir -p '" .. state .. "'")
    local f = io.open(state .. "/mode", "w")
    if f then
        f:write(mode .. "\n")
        f:close()
    end
    L.set(mode)
end

L.set(saved())

-- Floating windows (the Meta+Return terminal, dialogs, picture in picture)
-- keep their corners in both layouts: they touch nothing.
hl.window_rule({ name = "lumar-floating-corners", match = { float = true }, rounding = 10 })

-- The colors (apply-lumar writes them; Hyprland's defaults until it has).
local ok, colors = pcall(dofile, data .. "/colors.lua")
if ok and type(colors) == "table" and colors.frame then
    hl.config({ misc = { background_color = "rgb(" .. colors.frame:sub(2) .. ")" } })
end

-- shadesmar's bar, notifications and OSD are see-through: blurred behind,
-- the bar's popups too, not their transparent margins.
hl.config({ decoration = { blur = { enabled = true, size = 8, passes = 2, popups = true } } })
hl.layer_rule({
    name = "shadesmar-blur",
    match = { namespace = "^shadesmar-(bar|notifications|osd)$" },
    blur = true,
    blur_popups = true,
    ignore_alpha = 0.2,
})

return L
