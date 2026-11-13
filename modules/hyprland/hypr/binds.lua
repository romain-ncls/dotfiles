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
-- Meta+~ (Meta+Shift+²): the sound's popup, as Plasma's audio applet (Volume.qml).
bind(mod .. " + SHIFT + twosuperior", hl.dsp.global("shadesmar:volume"))

-- Windows. Alt+Tab goes through the desktop's windows from left to right,
-- then round to the first again (Alt+Shift+Tab: the other way), in the
-- order they stand, not in the order of use: the docked ones along the
-- tape (those of one column top to bottom), then the floating ones. (A
-- floating window's place on the screen changes as the tape scrolls: among
-- the docked ones, it would come round twice or not at all.)
local function cycle(step)
    local w = hl.get_active_window()
    local ws = w and w.workspace or hl.get_active_workspace()
    if not ws then
        return
    end
    local list = {}
    for _, o in ipairs(hl.get_windows({ workspace = ws })) do
        if not o.hidden then
            local at = o.at
            list[#list + 1] = { window = o, key = { o.floating and 1 or 0, at.x, at.y, o.stable_id } }
        end
    end
    if #list == 0 then
        return
    end
    table.sort(list, function(a, b)
        for i = 1, 4 do
            if a.key[i] ~= b.key[i] then
                return a.key[i] < b.key[i]
            end
        end
        return false
    end)
    local n = step > 0 and 1 or #list
    for i, o in ipairs(list) do
        if w and o.window.address == w.address then
            n = (i - 1 + step) % #list + 1
        end
    end
    hl.dispatch(hl.dsp.focus({ window = list[n].window }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end
bind("ALT + Tab", function() cycle(1) end)
bind("ALT + SHIFT + Tab", function() cycle(-1) end)

-- Alt+² and Alt+Shift+² (Plasma's Alt+` and Alt+~): the current app's
-- windows on the screens. (hl.get_windows' class is the exact class.)
local function same_app(step)
    local w = hl.get_active_window()
    if not w then
        return
    end
    local list = {}
    for _, o in ipairs(hl.get_windows({ class = w.class })) do
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

-- A window is docked (a column of the tape) or floating. Meta+Up docks a
-- floating one, its column as wide as the screen, and floats a docked one,
-- in the middle of the screen. Meta+Left and Right: half the screen, on
-- that side (Plasma's quick tile): a floating window snaps there; a docked
-- one stays docked, its column half as wide, the tape scrolled to put it
-- on that half. Not a desktop's only column, always as wide as the screen
-- (scrolling.fullscreen_on_one_column), nor the first one to the right: the
-- tape doesn't scroll before its start.
local function layout(msg)
    hl.dispatch(hl.dsp.layout(msg))
end

-- The screen's area the bar leaves.
local function area(m)
    local r = m.reserved
    return {
        x = m.x + r.left,
        y = m.y + r.top,
        width = m.width / m.scale - r.left - r.right,
        height = m.height / m.scale - r.top - r.bottom,
    }
end

-- A docked window's column (index from 0), and how many the tape has.
local function column(w)
    local l = not w.floating and w.layout
    return l and l.column
end
local function columns(ws)
    local n = 0
    for _, o in ipairs(hl.get_windows({ workspace = ws, floating = false })) do
        local c = column(o)
        if c then
            n = math.max(n, c.index + 1)
        end
    end
    return n
end

-- Hyprland has no message to put a column against a side of the screen.
-- `fit active` puts it, as wide as the screen, right over it, which gives
-- where both sides are; then it halves, and the tape moves by what's left.
-- Moving the tape focuses the column in the middle of the screen (against
-- the right side, the one before), which the tape fits in; the window takes
-- the focus back and the tape fits it in: from the left, so against the
-- right side.
local function dock_half(w, side)
    local col = column(w)
    if not col or columns(w.workspace) < 2 or (side == "right" and col.index == 0) then
        return
    end
    layout("fit active")
    local left, right = w.at.x, w.at.x + w.size.x
    layout("colresize 0.5")
    local delta = side == "left" and left - w.at.x or right - w.at.x - w.size.x
    if delta ~= 0 then
        layout(string.format("move %+d", delta))
        hl.dispatch(hl.dsp.focus({ window = w }))
    end
end

local function unmaximize()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset" }))
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
end

local function half(side)
    local w = hl.get_active_window()
    if not w then
        return
    end
    if not w.floating then
        dock_half(w, side)
        return
    end
    unmaximize()
    local a, gap = area(w.monitor), 8
    local width, height = math.floor(a.width / 2) - gap * 3 / 2, a.height - gap * 2
    local x = a.x + (side == "left" and gap or math.floor(a.width / 2) + gap / 2)
    hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = a.y + gap, relative = false }))
end

local function dock_or_float()
    local w = hl.get_active_window()
    if not w then
        return
    end
    if not w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "enable" }))
        hl.dispatch(hl.dsp.window.center())
        return
    end
    unmaximize()
    hl.dispatch(hl.dsp.window.float({ action = "disable" }))
    layout("fit active")
end

bind(mod .. " + up", dock_or_float)
bind(mod .. " + left", function() half("left") end)
bind(mod .. " + right", function() half("right") end)

-- Meta+Shift+Left and Right: the window one place along the tape (its
-- column swapped with the next one), and from either end onto the screen on
-- that side, at the end it comes in by: a window alone on its desktop goes
-- at once, as with Plasma's Window to Next Screen. A floating one goes at
-- once.
local function beside(m, side)
    local a = area(m)
    for _, o in ipairs(hl.get_monitors()) do
        local b = area(o)
        if (side == "left" and o.x + o.width / o.scale == m.x)
            or (side == "right" and o.x == m.x + m.width / m.scale) then
            if b.y < a.y + a.height and a.y < b.y + b.height then
                return o
            end
        end
    end
end

local function along(side)
    local w = hl.get_active_window()
    if not w then
        return
    end
    local col = column(w)
    if col and (side == "left" and col.index > 0 or side == "right" and col.index + 1 < columns(w.workspace)) then
        layout("swapcol " .. side:sub(1, 1))
        return
    end
    local m = beside(w.monitor, side)
    if not m then
        return
    end
    hl.dispatch(hl.dsp.window.move({ monitor = m.name }))
    col = column(w)
    if col then
        local steps = side == "right" and col.index or columns(w.workspace) - 1 - col.index
        for _ = 1, steps do
            layout("swapcol " .. (side == "right" and "l" or "r"))
        end
    end
end
bind(mod .. " + SHIFT + left", function() along("left") end)
bind(mod .. " + SHIFT + right", function() along("right") end)

-- On every desktop (Plasma's Meta+Ctrl+Shift+PgUp): only a floating window
-- can be, so it floats first.
bind(mod .. " + CTRL + SHIFT + Page_Up", function()
    local w = hl.get_active_window()
    if w and not w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "enable" }))
    end
    hl.dispatch(hl.dsp.window.pin({}))
end)

-- Meta+D: a peek at the desktop (grid.lua). Meta+Tab, Ctrl+Alt+Tab: the
-- overview (shadesmar's Overview.qml). Meta+W: the grid view, Plasma's
-- (DesktopGrid.qml; its key there is Meta+G, lumar's here).
bind(mod .. " + d", function() G.peek() end)
-- Meta+G: lumar's other layout, flush or floating (lumar.lua).
bind(mod .. " + g", function() require("lumar").toggle() end)
bind(mod .. " + Tab", hl.dsp.global("shadesmar:overview"))
bind("CTRL + ALT + Tab", hl.dsp.global("shadesmar:overview"))
bind(mod .. " + w", hl.dsp.global("shadesmar:grid"))

-- Zoom, as KWin's: Meta+Ctrl+scroll, or Meta+= in, Meta+- out, by steps
-- of 1.2, Meta+0 (à on AZERTY, with or without Shift) back; the screen
-- magnified around the pointer.
local function zoom(step)
    local z = step and (hl.get_config("cursor.zoom_factor") or 1) * step or 1
    hl.config({ cursor = { zoom_factor = math.max(1, math.min(z, 20)) } })
end
bind(mod .. " + equal", function() zoom(1.2) end, { repeating = true })
bind(mod .. " + minus", function() zoom(1 / 1.2) end, { repeating = true })
bind(mod .. " + CTRL + mouse_up", function() zoom(1.2) end)
bind(mod .. " + CTRL + mouse_down", function() zoom(1 / 1.2) end)
bind(mod .. " + agrave", function() zoom(nil) end)
bind(mod .. " + SHIFT + agrave", function() zoom(nil) end)

-- To the other screens straight away (Meta+Shift+arrows: along the tape
-- first, above).
bind(mod .. " + SHIFT + d", hl.dsp.window.move({ monitor = "+1" }))
bind(mod .. " + SHIFT + q", hl.dsp.window.move({ monitor = "-1" }))

bind("ALT + F4", hl.dsp.window.close())
bind("CTRL + ALT + Escape", hl.dsp.exec_cmd("hyprctl kill")) -- click the window to kill
bind("CTRL + ALT + a", hl.dsp.focus({ urgent_or_last = true }))
bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Apps.
-- Meta+Return's terminal floats: an exec rule, which follows the PID it
-- starts. A plain `ghostty` hands its window to the Ghostty already running
-- (single instance) and quits, and the window, the running one's, would tile.
bind(mod .. " + Return", hl.dsp.exec_cmd("ghostty --gtk-single-instance=false", { float = true }))
bind("CTRL + ALT + t", hl.dsp.exec_cmd("ghostty"))
-- the files, a new window each time (Dolphin's Meta+E)
bind(mod .. " + e", hl.dsp.exec_cmd("nautilus --new-window"))
for _, keys in ipairs({ mod .. " + space", "ALT + space", "ALT + F2" }) do
    bind(keys, hl.dsp.global("shadesmar:launcher")) -- Launcher.qml
end

-- Screenshots (LumineCapture, modules/lumine-capture), on Spectacle's keys:
-- Meta+Shift+S (or Meta+Shift+Print) its editor over every screen, frozen:
-- drag a region, annotate; Enter or Ctrl+C copies, Ctrl+S saves (and
-- copies too). Print saves the screen under the pointer, Shift+Print every
-- screen, to ~/Pictures/Screenshots.
bind(mod .. " + SHIFT + s", hl.dsp.exec_cmd("lumine-capture"))
bind(mod .. " + SHIFT + Print", hl.dsp.exec_cmd("lumine-capture"))
bind("Print", hl.dsp.exec_cmd("lumine-capture -f -m -t s"))
bind("SHIFT + Print", hl.dsp.exec_cmd("lumine-capture -f -t s"))

-- Recordings (shadesmar's Recorder.qml), on Spectacle's keys: Meta+Shift+R
-- a region, Meta+Alt+R the screen under the pointer; the same key again
-- stops.
bind(mod .. " + SHIFT + r", hl.dsp.global("shadesmar:record-region"))
bind(mod .. " + ALT + r", hl.dsp.global("shadesmar:record-screen"))

-- Volume, brightness, media. shadesmar's OSD shows the volume as PipeWire
-- changes it, and the brightness as told here.
local function brightness(step)
    return hl.dsp.exec_cmd("brightnessctl -e4 -n2 -m set " .. step
        .. " | cut -d, -f4 | tr -d % | xargs -r qs -c shadesmar ipc call osd brightness")
end
local locked = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), locked)
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), locked)
bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
bind("XF86MonBrightnessUp", brightness("5%+"), locked)
bind("XF86MonBrightnessDown", brightness("5%-"), locked)
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Session: Plasma's Lock Session (hypridle runs hyprlock on it), and its
-- "without confirmation" ones.
bind(mod .. " + l", hl.dsp.exec_cmd("loginctl lock-session"))
bind("XF86ScreenSaver", hl.dsp.exec_cmd("loginctl lock-session"))
bind("CTRL + ALT + SHIFT + Delete", hl.dsp.exit())
bind("CTRL + ALT + SHIFT + Page_Down", hl.dsp.exec_cmd("systemctl poweroff"))
bind("CTRL + ALT + SHIFT + Page_Up", hl.dsp.exec_cmd("systemctl reboot"))
