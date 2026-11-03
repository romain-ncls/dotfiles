-- Binds, close to Plasma's (modules/kde, hosts/wandersail; docs/hyprland.md,
-- Binds). The modules' own shortcuts (bemoji, mutectl, soundboard…) come
-- from lodestar later; Plasma's actions are here, done Hyprland's way.

local G = require("grid")

local mod = "SUPER"

local bind = hl.bind

-- Desktops: jumps (Meta+A Z / Q S on AZERTY, Ctrl+F1..F4), moves in the
-- grid (Meta+Ctrl+arrows), the window along (Meta+Ctrl+Shift+arrows).
for d, key in ipairs({ "a", "z", "q", "s" }) do
    bind(mod .. " + " .. key, function() G.go(d) end)
    bind(mod .. " + CTRL + " .. key, function() G.go(d) end)
    bind("CTRL + F" .. d, function() G.go(d) end)
end
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    bind(mod .. " + CTRL + " .. dir, function() G.move(dir) end)
    bind(mod .. " + CTRL + SHIFT + " .. dir, function() G.send(dir) end)
end

-- The middle screen: Discord and Teams (Meta+<), Spotify over them (Meta+²,
-- Plasma's media player key).
bind(mod .. " + less", function() G.comms() end)
bind(mod .. " + twosuperior", function() G.spotify() end)

-- Windows. Alt+Tab goes through the workspace's windows, the terminal
-- floating over them included.
bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next({}))
    hl.dispatch(hl.dsp.window.bring_to_top())
end)
bind("ALT + SHIFT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- Alt+` and Alt+~ (Alt+Shift+²): the current app's windows on the screens.
local function escape(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%{%}|\\]", "\\%0"))
end
local function same_app(step)
    local w = hl.get_active_window()
    if not w then
        return
    end
    local list = {}
    for _, o in ipairs(hl.get_windows({ class = "^" .. escape(w.class) .. "$" })) do
        if o.workspace and o.workspace.visible then
            list[#list + 1] = o
        end
    end
    table.sort(list, function(a, b) return a.stable_id < b.stable_id end)
    for i, o in ipairs(list) do
        if o.address == w.address then
            local next = list[(i - 1 + step) % #list + 1]
            hl.dispatch(hl.dsp.focus({ window = next }))
            hl.dispatch(hl.dsp.window.bring_to_top())
            return
        end
    end
end
bind("ALT + twosuperior", function() same_app(1) end)
bind("ALT + SHIFT + twosuperior", function() same_app(-1) end)

-- Meta+Up: as wide as the screen (a floating window: maximized); Meta+Left
-- and Right: half of it, on that side (Plasma's quick tile); Meta+Down hides
-- the window (Hyprland has no minimizing), Meta+Shift+Down shows them.
local function half(side)
    local w = hl.get_active_window()
    if not w then
        return
    end
    if not w.floating then
        hl.dispatch(hl.dsp.layout("colresize 0.5"))
        return
    end
    local m, gap = w.monitor, 8
    local width, height = math.floor(m.width / 2) - gap * 3 / 2, m.height - gap * 2
    local x = m.x + (side == "left" and gap or math.floor(m.width / 2) + gap / 2)
    hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = m.y + gap, relative = false }))
end
bind(mod .. " + up", function()
    local w = hl.get_active_window()
    if w and w.floating then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
    else
        hl.dispatch(hl.dsp.layout("colresize 1.0"))
    end
end)
bind(mod .. " + left", function() half("left") end)
bind(mod .. " + right", function() half("right") end)
bind(mod .. " + down", hl.dsp.window.move({ workspace = "special:hidden", follow = false }))
bind(mod .. " + SHIFT + down", hl.dsp.workspace.toggle_special("hidden"))

-- On every desktop (Plasma's Meta+Ctrl+Shift+PgUp): only a floating window
-- can be, so it floats first.
bind(mod .. " + CTRL + SHIFT + Page_Up", function()
    local w = hl.get_active_window()
    if w and not w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "enable" }))
    end
    hl.dispatch(hl.dsp.window.pin({}))
end)

-- To the other screens.
bind(mod .. " + SHIFT + d", hl.dsp.window.move({ monitor = "+1" }))
bind(mod .. " + SHIFT + right", hl.dsp.window.move({ monitor = "+1" }))
bind(mod .. " + SHIFT + q", hl.dsp.window.move({ monitor = "-1" }))
bind(mod .. " + SHIFT + left", hl.dsp.window.move({ monitor = "-1" }))

bind("ALT + F4", hl.dsp.window.close())
bind("CTRL + ALT + Escape", hl.dsp.exec_cmd("hyprctl kill")) -- click the window to kill
bind("CTRL + ALT + a", hl.dsp.focus({ urgent_or_last = true }))
bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Apps.
bind(mod .. " + Return", hl.dsp.exec_cmd("ghostty", { float = true }))
bind("CTRL + ALT + t", hl.dsp.exec_cmd("ghostty"))
for _, keys in ipairs({ mod .. " + space", "ALT + space", "ALT + F2" }) do
    bind(keys, hl.dsp.exec_cmd("fuzzel")) -- shadesmar's launcher later
end

-- Screenshots, as Spectacle's: Print the screens, to a file and the
-- clipboard; Meta+Shift+S (or Meta+Shift+Print) a region, to the clipboard.
local shots = "mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"
bind("Print", hl.dsp.exec_cmd(shots .. " && grim \"$f\" && wl-copy < \"$f\""))
bind(mod .. " + SHIFT + s", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
bind(mod .. " + SHIFT + Print", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))

-- Volume, brightness, media (shadesmar's OSD later shows them).
local locked = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), locked)
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), locked)
bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), locked)
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), locked)
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Session, as Plasma's "without confirmation" ones.
bind("CTRL + ALT + SHIFT + Delete", hl.dsp.exit())
bind("CTRL + ALT + SHIFT + Page_Down", hl.dsp.exec_cmd("systemctl poweroff"))
bind("CTRL + ALT + SHIFT + Page_Up", hl.dsp.exec_cmd("systemctl reboot"))
