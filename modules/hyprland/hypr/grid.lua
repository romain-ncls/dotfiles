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

-- Each workspace on its screen, whatever creates it (a window sent there,
-- an app's rule): else Hyprland makes it on the focused screen. comms is
-- kept even when empty. A rule's screen that isn't plugged in is ignored,
-- so the laptop alone gets the desktops.
for d = 1, 4 do
    if screens.left then
        hl.workspace_rule({ workspace = tostring(d), monitor = screens.left })
    end
    if screens.right then
        hl.workspace_rule({ workspace = tostring(4 + d), monitor = screens.right })
    end
end
hl.workspace_rule({ workspace = "name:comms", monitor = screens.laptop, persistent = true })

-- The grid screen a monitor is, if it is one.
local function slot(m)
    for _, s in ipairs(grid()) do
        if s.monitor.name == m.name then
            return s
        end
    end
end

-- Where desktop d lies: its row and column, from 0.
local function place(d)
    return math.floor((d - 1) / 2), (d - 1) % 2
end

-- The desktop next to d (nil at the edge: no wrapping, as in KDE).
local function neighbour(d, dir)
    local row, col = place(d)
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

-- Tells the bar's desktops (modules/shadesmar) the one shown, 0 for none
-- (comms in place of the grid, on the laptop alone): Hyprland itself only
-- says which workspace the focused screen switched to.
local function announce(d)
    hl.dispatch(hl.dsp.event("grid " .. d))
end

-- How a switch from desktop a to b moves. With hyprslide (modules/hyprslide)
-- the desktops slide as one plane, a whole screen the way b lies,
-- diagonals included (the desktops between pass by), without the columns
-- the scrolling layout keeps beside the screen; four fingers on the
-- touchpad drag it. Without it (missing, or built for another Hyprland):
-- Hyprland slides sideways or up and down, the direction from the ids'
-- order, so a straight move slides the way it goes and a diagonal one only
-- fades; short slides that fade, as a whole screen's would carry those
-- columns across it.
local travel = "10%"
local function style(a, b)
    local ra, ca = place(a)
    local rb, cb = place(b)
    if ra ~= rb and ca ~= cb then
        return "fade"
    end
    return (ra ~= rb and "slidefadevert " or "slidefade ") .. travel
end

local function hyprslide()
    return hl.plugin.hyprslide
end

-- Tells hyprslide where the desktops lie: each grid screen's, row by row.
local function declare(slide)
    local list = {}
    for _, s in ipairs(grid()) do
        local desktops = {}
        for d = 1, 4 do
            desktops[d] = tostring(s.base + d)
        end
        list[s.monitor.name] = desktops
    end
    slide.grid({ columns = 2, fingers = 4, screens = list })
end

local switching = false

local function animate(how)
    hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = how })
end

-- Meta+D, Plasma's Peek at Desktop: each screen on an empty workspace of
-- its own (the windows stay where they are); again, or any switch, and
-- back. peeking: the workspace each screen had, by screen name.
local peeking = nil

local function bare(m)
    return "name:desktop-" .. m.name
end

-- Back from the peek: what opened meanwhile goes to the workspace its
-- screen had, and each screen back to it (but the grid ones, when a switch
-- takes them elsewhere).
local function unpeek(keep_grid)
    local before = peeking
    peeking = nil
    switching = true
    animate("fade")
    for _, m in ipairs(hl.get_monitors()) do
        local back = before[m.name]
        if back then
            for _, w in ipairs(hl.get_workspace_windows(bare(m))) do
                hl.dispatch(hl.dsp.window.move({ window = w, workspace = back, follow = false }))
            end
            if not (keep_grid and slot(m)) then
                m:set_workspace(back)
            end
        end
    end
    switching = false
end

-- Shows desktop d on every grid screen.
function G.go(d)
    if peeking then
        unpeek(true)
    end
    local from, slide = current(), hyprslide()
    -- hyprslide 2 (a session started before 3 was built) is told the
    -- direction around the switch instead
    local towards = slide and not slide.grid
    if towards and from ~= d then
        local ra, ca = place(from)
        local rb, cb = place(d)
        slide.towards(cb - ca, rb - ra)
    elseif slide then
        declare(slide)
    end
    animate(from == d and "fade" or slide and "slide" or style(from, d))
    shown = d
    switching = true
    for _, s in ipairs(grid()) do
        s.monitor:set_workspace(tostring(s.base + d))
    end
    switching = false
    if towards then
        slide.towards(0, 0)
    end
    announce(d)
end

-- A swipe that lands goes there (hyprslide: four fingers). The plugin
-- loads after the config's first run, which runs again then.
if hyprslide() and hyprslide().grid then
    hl.on("hyprslide.swipe", function(d)
        G.go(d)
    end)
end

function G.move(dir)
    local d = neighbour(current(), dir)
    if d then
        G.go(d)
    end
end

-- Takes the active window to the next desktop, on its screen, and follows.
-- With hyprslide the window stays in sight, going to its place there while
-- the desktops slide under it, as in KDE; without, it leaves and comes back
-- with the desktop. (carry: since hyprslide 2, and Hyprland's Lua window
-- type, which it reads, may change: a failure only loses the effect.)
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
    local slide = hyprslide()
    if slide and slide.carry then
        pcall(slide.carry, w)
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
        announce(0)
    end
end

-- Spotify's scratchpad, on the laptop's screen (a special workspace opens on
-- the focused screen): Spotify over Discord, but for its left strip (the
-- servers, who's in the voice channel), above the bar.
local strip, bar = 375, 40

local function laptop_screen()
    return find(screens.laptop) or hl.get_active_monitor()
end

local function spotify(w)
    return w ~= nil and (w.class == "Spotify" or w.class == "spotify")
end

-- (hl.get_windows' class is the exact class, not a pattern.)
local function spotify_window()
    for _, w in ipairs(hl.get_windows()) do
        if spotify(w) then
            return w
        end
    end
end

local function in_scratchpad(w)
    return w.workspace ~= nil and w.workspace.name == "special:spotify"
end

local function scratchpad_shown()
    local s = laptop_screen().active_special_workspace
    return s ~= nil and s.name == "special:spotify"
end

-- The window to give the focus back to when the scratchpad hides: the one
-- that had it before Spotify.
local back = nil

-- Shows the scratchpad, or hides it.
local function scratchpad(show)
    if show == scratchpad_shown() then
        return
    end
    local a = hl.get_active_window()
    if a and not spotify(a) then
        back = a.address
    end
    hl.dispatch(hl.dsp.focus({ monitor = laptop_screen() }))
    hl.dispatch(hl.dsp.workspace.toggle_special("spotify"))
    if not show and back then
        local w = hl.get_window("address:" .. back)
        if w and w.workspace and w.workspace.visible then
            hl.dispatch(hl.dsp.focus({ window = w }))
        end
        back = nil
    end
end

-- Puts Spotify's window in the scratchpad. Not a window rule: Spotify names
-- its window once it's open, after the rules have run.
local function stow(w)
    local m = laptop_screen()
    if not w.floating then
        hl.dispatch(hl.dsp.window.float({ window = w, action = "enable" }))
    end
    if not in_scratchpad(w) then
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:spotify", follow = false }))
    end
    hl.dispatch(hl.dsp.window.resize({ window = w, x = m.width - strip, y = m.height - bar, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = w, x = m.x + strip, y = m.y, relative = false }))
end

-- Meta+²: Spotify, started the first time, put back in the scratchpad if
-- it left it.
function G.spotify()
    local w = spotify_window()
    if not w then
        hl.exec_cmd("spotify", { workspace = "special:spotify silent", float = true })
    elseif not in_scratchpad(w) then
        stow(w)
        scratchpad(true)
    else
        scratchpad(not scratchpad_shown())
    end
end

-- However Spotify was started, its window goes to the scratchpad, shown.
for _, event in ipairs({ "window.open", "window.class" }) do
    hl.on(event, function(w)
        if spotify(w) then
            stow(w)
            scratchpad(true)
        end
    end)
end

function G.peek()
    if peeking then
        unpeek(false)
        return
    end
    if scratchpad_shown() then
        scratchpad(false)
    end
    peeking = {}
    switching = true
    animate("fade")
    for _, m in ipairs(hl.get_monitors()) do
        local ws = m.active_workspace
        if ws then
            peeking[m.name] = ws.id and ws.id > 0 and tostring(ws.id) or "name:" .. ws.name
            m:set_workspace(bare(m))
        end
    end
    switching = false
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
    -- a window asking for focus during a peek ends it, on its desktop
    if peeking and not (ws.name or ""):find("^desktop%-") then
        local s = slot(ws.monitor)
        unpeek(true)
        G.go(s and ws.id > s.base and ws.id <= s.base + 4 and ws.id - s.base or current())
        return
    end
    if ws.name == "comms" and alone() then
        announce(0)
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
