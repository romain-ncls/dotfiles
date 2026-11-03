-- Desktops (docs/hyprland.md). Four, in a 2×2 grid, on the side screens,
-- which switch together as in KDE; the laptop's screen between them keeps a
-- workspace of its own, comms (Discord, Teams), with Spotify as a
-- scratchpad over it. The laptop alone shows the grid itself, comms then
-- being a fifth workspace.
--
-- Desktop d (1 2 / 3 4) of a grid screen is workspace base + d: base 0 on
-- the left screen (and on the laptop alone), 4 on the right one. Numbered
-- row by row, so that Hyprland, which slides by the ids' order, slides the
-- way you move: d + 1 is to the right, d + 2 below.

local screens = require("monitors")

local G = {}

-- Whether monitor m is the one a selector of monitors.lua names (desc:
-- matches the start of the description, as Hyprland's does).
local function is(m, sel)
    if not sel then
        return false
    end
    if sel:sub(1, 5) == "desc:" then
        return m.description:sub(1, #sel - 5) == sel:sub(6)
    end
    return m.name == sel
end

-- The monitor a selector names, if it's connected.
local function find(sel)
    for _, m in ipairs(hl.get_monitors()) do
        if is(m, sel) then
            return m
        end
    end
end

-- The screens holding the grid now, each with its base.
local function grid()
    local list = {}
    local left, right = find(screens.left), find(screens.right)
    if left then
        list[#list + 1] = { monitor = left, base = 0 }
    end
    if right then
        list[#list + 1] = { monitor = right, base = 4 }
    end
    local laptop = #list == 0 and (find(screens.laptop) or hl.get_active_monitor())
    if laptop then
        list[1] = { monitor = laptop, base = 0 }
    end
    return list
end

local function alone()
    return not find(screens.left) and not find(screens.right)
end

-- The grid screen a monitor is, if it is one.
local function slot(m)
    for _, s in ipairs(grid()) do
        if s.monitor.name == m.name then
            return s
        end
    end
end

-- The desktop next to d (nil at the edge: no wrapping, as in KDE).
local function neighbour(d, dir)
    local row, col = math.floor((d - 1) / 2), (d - 1) % 2
    if dir == "left" then
        col = col - 1
    elseif dir == "right" then
        col = col + 1
    elseif dir == "up" then
        row = row - 1
    else
        row = row + 1
    end
    if row < 0 or row > 1 or col < 0 or col > 1 then
        return nil
    end
    return row * 2 + col + 1
end

-- The desktop shown: kept as it's switched, and read from the screens when
-- the config is (re)loaded, since a reload starts this file again.
local shown = nil
local function current()
    if not shown then
        shown = 1
        for _, s in ipairs(grid()) do
            local ws = s.monitor.active_workspace
            if ws and ws.id and ws.id > s.base and ws.id <= s.base + 4 then
                shown = ws.id - s.base
                break
            end
        end
    end
    return shown
end

local switching = false

-- Shows desktop d on every grid screen, sliding the way it lies.
function G.go(d)
    local style = math.abs(d - current()) == 2 and "slidevert" or "slide"
    hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = style })
    shown = d
    switching = true
    for _, s in ipairs(grid()) do
        s.monitor:set_workspace(tostring(s.base + d))
    end
    switching = false
end

function G.move(dir)
    local d = neighbour(current(), dir)
    if d then
        G.go(d)
    end
end

-- Takes the active window to the next desktop, on its screen, and follows.
function G.send(dir)
    local w = hl.get_active_window()
    local d = neighbour(current(), dir)
    if not w or not d or not w.monitor then
        return
    end
    local s = slot(w.monitor)
    if not s then
        return
    end
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(s.base + d), follow = false }))
    G.go(d)
    hl.dispatch(hl.dsp.focus({ window = w }))
end

-- Discord and Teams: the laptop's screen at the desk, comms in place of the
-- desktop on the laptop alone (and back).
function G.comms()
    local laptop = find(screens.laptop)
    if not laptop then
        return
    end
    if not alone() then
        hl.dispatch(hl.dsp.focus({ monitor = laptop }))
    elseif laptop.active_workspace and laptop.active_workspace.name == "comms" then
        G.go(current())
    else
        laptop:set_workspace("name:comms")
    end
end

-- Spotify's scratchpad, always on the laptop's screen (a special workspace
-- opens on the focused screen). Started the first time.
function G.spotify()
    local laptop = find(screens.laptop)
    if laptop then
        hl.dispatch(hl.dsp.focus({ monitor = laptop }))
    end
    if #hl.get_windows({ class = "^[Ss]potify$" }) == 0 then
        hl.exec_cmd("spotify")
    else
        hl.dispatch(hl.dsp.workspace.toggle_special("spotify"))
    end
end

-- Puts each screen on what it shows: the current desktop on the grid
-- screens, comms on the laptop's at the desk.
function G.arrange()
    G.go(current())
    local laptop = find(screens.laptop)
    if laptop and not alone() then
        laptop:set_workspace("name:comms")
    end
end

-- A grid screen that leaves gives its windows to the same desktop of the
-- screens left (the laptop alone, or the other side).
hl.on("monitor.removed", function(m)
    local base = nil
    if is(m, screens.left) then
        base = 0
    elseif is(m, screens.right) then
        base = 4
    end
    local to = grid()[1]
    if base and to and to.base ~= base then
        for d = 1, 4 do
            for _, w in ipairs(hl.get_workspace_windows(tostring(base + d))) do
                hl.dispatch(hl.dsp.window.move({ window = w, workspace = tostring(to.base + d), follow = false }))
            end
        end
    end
    G.arrange()
end)

hl.on("monitor.added", function()
    G.arrange()
end)

-- Whatever changed a grid screen's desktop (a click on a notification, a
-- window asking for focus), the other grid screens follow.
hl.on("workspace.active", function(ws)
    if switching or not ws or not ws.monitor or not ws.id then
        return
    end
    local s = slot(ws.monitor)
    if s and ws.id > s.base and ws.id <= s.base + 4 and ws.id - s.base ~= current() then
        G.go(ws.id - s.base)
    end
end)

hl.on("hyprland.start", function()
    G.arrange()
end)

current() -- on a reload, before a screen plugged in meanwhile shows something else

return G
