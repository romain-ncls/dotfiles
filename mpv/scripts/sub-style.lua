-- sub-style.lua
-- Subtitle style switcher: file's own style, mpv default, VLC-like, and a few
-- popular font presets. Opens a menu (script-binding sub_style/menu) and
-- publishes its state in user-data/sub-style for the ModernZ "Aa" button
-- (see sub-style-modernz-patch.md).
--
-- Plain-text subs (SRT, VTT...) always take the chosen preset. Styled .ass subs
-- keep their own styling unless "Also restyle .ass subtitles" is on, which
-- forces the preset onto them (can break signs/typesetting).
-- Image subs (PGS, VobSub) can't be restyled.
--
-- The choice is remembered across files and restarts (~~state/sub-style.json).
--
-- Bindings: sub_style/menu (custom menu, or the classic one if
-- script-opts/sub_style.conf has menu_style=classic), sub_style/menu-classic
-- (always mpv's console-style menu).

local mp = require "mp"
local utils = require "mp.utils"
local input = require "mp.input"

-- Every option a preset may set. Values not listed in a preset fall back to
-- what mpv had at startup (mpv.conf or built-in defaults).
local KEYS = {
    "sub-font", "sub-font-size", "sub-bold", "sub-italic", "sub-color",
    "sub-outline-size", "sub-outline-color", "sub-shadow-offset",
    "sub-back-color", "sub-border-style", "sub-blur", "sub-spacing",
    "sub-margin-y",
}

-- mpv's built-in values, so "mpv default" stays correct even if mpv.conf
-- sets some sub-* options.
local MPV_DEFAULTS = {
    ["sub-font"] = "sans-serif", ["sub-font-size"] = 38, ["sub-bold"] = false,
    ["sub-italic"] = false, ["sub-color"] = "#FFFFFFFF",
    ["sub-outline-size"] = 1.65, ["sub-outline-color"] = "#FF000000",
    ["sub-shadow-offset"] = 0, ["sub-back-color"] = "#AF000000",
    ["sub-border-style"] = "outline-and-shadow", ["sub-blur"] = 0,
    ["sub-spacing"] = 0, ["sub-margin-y"] = 34,
}

-- id "file" = no styling of ours at all.
local PRESETS = {
    { id = "file", label = "File's own style" },
    { id = "mpv", label = "mpv default", opts = MPV_DEFAULTS },
    { id = "vlc", label = "VLC-like (Arial, thick outline, soft shadow)", opts = {
        ["sub-font"] = "Arial", ["sub-font-size"] = 42,
        ["sub-outline-size"] = 2.2, ["sub-outline-color"] = "#FF000000",
        ["sub-shadow-offset"] = 2, ["sub-back-color"] = "#80000000",
        ["sub-margin-y"] = 24,
    }},
    -- Presets below come from a web survey (Reddit, shared mpv configs,
    -- fansub guides, streaming/broadcast style guides). Fonts live in ~~/fonts.

    -- Most-recommended anime dialogue font today (thewiki.moe mpv block, GJM-style)
    { id = "gandhi", label = "Fansub (Gandhi Sans)", opts = {
        ["sub-font"] = "Gandhi Sans", ["sub-bold"] = true, ["sub-font-size"] = 50,
        ["sub-outline-size"] = 2.4, ["sub-outline-color"] = "#FF000000",
        ["sub-shadow-offset"] = 0.75, ["sub-back-color"] = "#A0000000",
        ["sub-margin-y"] = 40,
    }},
    -- Classic Crunchyroll look; ships with Windows
    { id = "trebuchet", label = "Crunchyroll classic (Trebuchet MS)", opts = {
        ["sub-font"] = "Trebuchet MS", ["sub-bold"] = true, ["sub-font-size"] = 48,
        ["sub-outline-size"] = 3, ["sub-outline-color"] = "#FF000000",
        ["sub-shadow-offset"] = 1.5, ["sub-back-color"] = "#C0000000",
        ["sub-margin-y"] = 36,
    }},
    -- Free stand-in for Netflix Sans (Argon- mpv-config style)
    { id = "streaming", label = "Streaming / Netflix-like (Source Sans 3)", opts = {
        ["sub-font"] = "Source Sans 3 Semibold", ["sub-font-size"] = 44,
        ["sub-outline-size"] = 2, ["sub-outline-color"] = "#FF262626",
        ["sub-shadow-offset"] = 1, ["sub-back-color"] = "#33000000",
        ["sub-blur"] = 0.2, ["sub-spacing"] = 0.3,
    }},
    -- md-subs' "best free all-purpose font"; off-white on dark grey (Zabooby config)
    { id = "clearsans", label = "Soft modern (Clear Sans)", opts = {
        ["sub-font"] = "Clear Sans", ["sub-bold"] = true, ["sub-font-size"] = 46,
        ["sub-color"] = "#FFECEFF4", ["sub-outline-size"] = 2.5,
        ["sub-outline-color"] = "#FF2E3440", ["sub-blur"] = 0.5,
        ["sub-margin-y"] = 50,
    }},
    -- Braille Institute font in a translucent box, like broadcast TV / Apple TV
    { id = "boxed", label = "Boxed high-legibility (Atkinson Hyperlegible)", opts = {
        ["sub-font"] = "Atkinson Hyperlegible Next", ["sub-bold"] = true,
        ["sub-font-size"] = 40, ["sub-border-style"] = "background-box",
        ["sub-outline-size"] = 0, ["sub-shadow-offset"] = 4,
        ["sub-back-color"] = "#B0000000",
    }},
}

local state_path = mp.command_native({"expand-path", "~~state/sub-style.json"})
local startup = {}
local current = "file"
local force_ass = false

local function find(id)
    for _, p in ipairs(PRESETS) do
        if p.id == id then return p end
    end
end

local function load_state()
    local f = io.open(state_path, "r")
    if not f then return end
    local data = utils.parse_json(f:read("*a") or "")
    f:close()
    if type(data) ~= "table" then return end
    if find(data.preset) then current = data.preset end
    force_ass = data.force_ass == true
end

local function save_state()
    local f = io.open(state_path, "w")
    if not f then return end
    f:write(utils.format_json({preset = current, force_ass = force_ass}))
    f:close()
end

local function sub_kind()
    local track = mp.get_property_native("current-tracks/sub")
    if not track then return "none" end
    if track.codec == "ass" or track.codec == "ssa" then return "ass" end
    if track.codec == "hdmv_pgs_subtitle" or track.codec == "dvd_subtitle"
        or track.codec == "dvb_subtitle" then return "image" end
    return "text"
end

-- Tell ModernZ what to draw: icon = own | plain | preset | image | none
local function publish()
    local kind = sub_kind()
    local p = find(current)
    local icon, tip
    if kind == "none" then
        icon, tip = "none", "Subtitle style: no subtitles"
    elseif kind == "image" then
        icon, tip = "image", "Subtitle style: image subtitles (can't be restyled)"
    elseif kind == "ass" and (current == "file" or not force_ass) then
        icon, tip = "own", "Subtitle style: file's own (styled .ass)"
    elseif current == "file" or current == "mpv" then
        icon, tip = "plain", "Subtitle style: mpv default (file has no style of its own)"
        if kind == "ass" then icon, tip = "preset", "Subtitle style: mpv default (forced on .ass)" end
    else
        icon, tip = "preset", "Subtitle style: " .. p.label
    end
    mp.set_property_native("user-data/sub-style", {icon = icon, tooltip = tip, preset = current})
end

local function apply()
    local p = find(current)
    local opts = p.opts or {}
    for _, k in ipairs(KEYS) do
        local v = opts[k]
        if v == nil then v = startup[k] end
        mp.set_property_native(k, v)
    end
    mp.set_property("sub-ass-override", (p.opts and force_ass) and "force" or "scale")
    publish()
end

local function menu_classic()
    local items, ids = {}, {}
    for _, p in ipairs(PRESETS) do
        items[#items + 1] = (p.id == current and "● " or "   ") .. p.label
        ids[#ids + 1] = p.id
    end
    items[#items + 1] = (force_ass and "[x] " or "[ ] ") .. "Also restyle .ass subtitles (may break signs)"
    local kind = sub_kind()
    local prompt = "Subtitle style" .. (kind == "ass" and " — this file has its own style"
        or kind == "text" and " — plain subtitles" or kind == "image" and " — image subtitles" or "")

    input.select({
        prompt = prompt .. ":",
        items = items,
        default_item = (function() for i, id in ipairs(ids) do if id == current then return i end end end)(),
        submit = function(i)
            if i > #ids then
                force_ass = not force_ass
            else
                current = ids[i]
            end
            save_state()
            apply()
            mp.osd_message(find(current).label .. (force_ass and current ~= "file" and " (also on .ass)" or ""))
            -- reopen after toggling the checkbox so the user can keep choosing
            if i > #ids then mp.add_timeout(0.05, menu_classic) end
        end,
    })
end

--------------------------------------------------------------------------------
-- Custom menu: drawn with an ASS overlay, each preset name previewed in its
-- own font. Stays open so styles can be compared live; closes on click
-- outside, right click or Esc. Arrow keys + Enter also work.
--------------------------------------------------------------------------------

local assdraw = require "mp.assdraw"
local options = require "mp.options"

local o = {
    menu_style = "custom",       -- "custom" or "classic" (mpv's console menu)
    accent_color = "#4FA3FF",    -- match ModernZ seekbarfg_color
    ui_font = "Atkinson Hyperlegible Next",  -- bundled in ~~/fonts: same look on Windows and Linux
}
options.read_options(o, "sub_style")

-- Short menu text per preset: name (drawn in the preset's font) + hint
local MENU_TEXT = {
    file      = {"File's own style", "as the subtitle file defines it"},
    mpv       = {"mpv default", "sans-serif, thin outline"},
    vlc       = {"VLC-like", "Arial, thick outline, soft shadow"},
    gandhi    = {"Fansub", "Gandhi Sans · anime standard"},
    trebuchet = {"Crunchyroll classic", "Trebuchet MS"},
    streaming = {"Streaming", "Source Sans 3 · Netflix-like"},
    clearsans = {"Soft modern", "Clear Sans · off-white"},
    boxed     = {"Boxed", "Atkinson Hyperlegible · dark box"},
}

local KIND_TEXT = {
    ass = "this file: styled .ass", text = "this file: plain text",
    image = "this file: image subs", none = "no subtitles selected",
}

local overlay = mp.create_osd_overlay("ass-events")
local m = { open = false, rows = {}, hover = nil, cursor = 1, box = nil, anchor = nil }

-- "#RRGGBB" -> ASS "BBGGRR"
local function bgr(hex)
    hex = hex:gsub("#", "")
    if #hex == 8 then hex = hex:sub(3) end -- drop mpv alpha (#AARRGGBB)
    return hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2)
end

local function esc(text)
    return (text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}"))
end

local function rect(ass, x0, y0, x1, y1, r, color, alpha)
    ass:new_event()
    ass:pos(0, 0)
    ass:append(string.format("{\\an7\\bord0\\shad0\\1c&H%s&\\1a&H%02X&}", bgr(color), alpha or 0))
    ass:draw_start()
    ass:round_rect_cw(x0, y0, x1, y1, r)
    ass:draw_stop()
end

local function text(ass, x, y, an, font, size, color, str, extra)
    ass:new_event()
    ass:an(an)
    ass:pos(x, y)
    ass:append(string.format("{\\fn%s\\fs%d\\bord0\\shad0\\1c&H%s&%s}%s",
        font, size, bgr(color), extra or "", esc(str)))
end

local function render()
    if not m.open then overlay:remove(); return end
    local dim = mp.get_property_native("osd-dimensions")
    local W, H = dim.w, dim.h
    if W <= 0 or H <= 0 then return end
    local s = math.max(1, math.min(2.2, H / 760))

    local pad, row_h, w = 14 * s, 38 * s, 380 * s
    local head_h, toggle_h = 44 * s, 54 * s
    local h = head_h + #PRESETS * row_h + 9 * s + toggle_h + pad * 0.5

    -- open above the button that was clicked, clear of the OSC bar
    -- (ModernZ's bar + seekbar take ~11% of the window height)
    local ax = m.anchor.x
    local bottom = H * 0.89 - 8 * s
    local x0 = math.max(8 * s, math.min(W - w - 8 * s, ax - w / 2))
    local y0 = math.max(8 * s, bottom - h)
    m.box = {x0, y0, x0 + w, y0 + h}

    local ass = assdraw.ass_new()
    local accent = o.accent_color
    rect(ass, x0, y0, x0 + w, y0 + h, 10 * s, "#1C1F24", 0x18)

    text(ass, x0 + pad, y0 + head_h / 2, 4, o.ui_font, 19 * s, "#FFFFFF", "Subtitle style", "\\b1")
    text(ass, x0 + w - pad, y0 + head_h / 2, 6, o.ui_font, 13 * s, "#B4BCC5", KIND_TEXT[sub_kind()])
    rect(ass, x0 + pad, y0 + head_h - 1, x0 + w - pad, y0 + head_h, 0, "#FFFFFF", 0xD8)

    m.rows = {}
    local y = y0 + head_h
    for i, p in ipairs(PRESETS) do
        local t = MENU_TEXT[p.id] or {p.label, ""}
        local hovered = (m.hover == i) or (m.hover == nil and m.cursor == i and m.keyboard)
        if hovered then rect(ass, x0 + 6 * s, y + 3 * s, x0 + w - 6 * s, y + row_h - 3 * s, 6 * s, "#FFFFFF", 0xE6) end
        local selected = p.id == current
        if selected then
            rect(ass, x0 + 6 * s, y + 9 * s, x0 + 9 * s, y + row_h - 9 * s, 1.5 * s, accent, 0)
        end

        -- name in the preset's own font, as a preview
        local po = p.opts or {}
        local font = po["sub-font"] or o.ui_font
        if font == "sans-serif" then font = "Arial" end
        local bold = po["sub-bold"] and "\\b1" or "\\b0"
        local color = selected and accent or (po["sub-color"] or "#FFFFFF")
        text(ass, x0 + pad + 6 * s, y + row_h / 2, 4, font, 21 * s, color, t[1], bold)
        text(ass, x0 + w - pad, y + row_h / 2, 6, o.ui_font, 14 * s, "#A3ACB6", t[2])
        m.rows[i] = {y, y + row_h, i}
        y = y + row_h
    end

    -- toggle row
    y = y + 4 * s
    rect(ass, x0 + pad, y, x0 + w - pad, y + 1, 0, "#FFFFFF", 0xD8)
    y = y + 5 * s
    local ti = #PRESETS + 1
    if m.hover == ti or (m.hover == nil and m.keyboard and m.cursor == ti) then
        rect(ass, x0 + 6 * s, y + 2 * s, x0 + w - 6 * s, y + toggle_h - 2 * s, 6 * s, "#FFFFFF", 0xE6)
    end
    text(ass, x0 + pad + 6 * s, y + toggle_h * 0.38, 4, o.ui_font, 15.5 * s, "#FFFFFF", "Also restyle .ass subtitles")
    text(ass, x0 + pad + 6 * s, y + toggle_h * 0.70, 4, o.ui_font, 13.5 * s, "#A3ACB6", "May break signs and on-screen text")
    local sw, sh = 38 * s, 20 * s
    local sx, sy = x0 + w - pad - sw, y + (toggle_h - sh) / 2
    rect(ass, sx, sy, sx + sw, sy + sh, sh / 2, force_ass and accent or "#4A5058", 0)
    local k = sh - 6 * s
    local kx = force_ass and (sx + sw - 3 * s - k) or (sx + 3 * s)
    rect(ass, kx, sy + 3 * s, kx + k, sy + 3 * s + k, k / 2, "#FFFFFF", 0)
    m.rows[ti] = {y, y + toggle_h, ti}

    overlay.res_x, overlay.res_y = W, H
    overlay.data = ass.text
    overlay:update()
end

local close

local function activate(i)
    if i == #PRESETS + 1 then
        force_ass = not force_ass
    elseif PRESETS[i] then
        current = PRESETS[i].id
    else
        return
    end
    save_state()
    apply()
    render()
end

local function row_at(x, y)
    local b = m.box
    if not b or x < b[1] or x > b[3] or y < b[2] or y > b[4] then return nil, false end
    for _, r in pairs(m.rows) do
        if y >= r[1] and y < r[2] then return r[3], true end
    end
    return nil, true
end

local function on_mouse(_, pos)
    if not m.open or not pos then return end
    local i = row_at(pos.x, pos.y)
    if i ~= m.hover then m.hover = i; m.keyboard = false; render() end
end

local function on_click()
    local pos = mp.get_property_native("mouse-pos")
    local i, inside = row_at(pos.x, pos.y)
    if not inside then close() elseif i then activate(i) end
end

local function move(d)
    local n = #PRESETS + 1
    m.keyboard, m.hover = true, nil
    m.cursor = (m.cursor - 1 + d) % n + 1
    render()
end

local BINDINGS = {
    {"MBTN_LEFT", on_click}, {"MBTN_LEFT_DBL", function() end},
    {"MBTN_RIGHT", function() close() end}, {"ESC", function() close() end},
    {"UP", function() move(-1) end}, {"DOWN", function() move(1) end},
    {"WHEEL_UP", function() move(-1) end}, {"WHEEL_DOWN", function() move(1) end},
    {"ENTER", function() activate(m.cursor) end}, {"KP_ENTER", function() activate(m.cursor) end},
}

close = function()
    if not m.open then return end
    m.open = false
    for _, b in ipairs(BINDINGS) do mp.remove_key_binding("sub-style-menu-" .. b[1]) end
    mp.unobserve_property(on_mouse)
    mp.unobserve_property(render)
    render()
end

local function open_menu()
    if m.open then close(); return end
    local pos = mp.get_property_native("mouse-pos") or {}
    local dim = mp.get_property_native("osd-dimensions")
    -- no usable mouse position (opened from keyboard): bottom-right corner
    if not pos.hover then pos = {x = dim.w - 200, y = dim.h - 40} end
    m.open, m.anchor, m.hover, m.keyboard = true, {x = pos.x, y = pos.y}, nil, false
    for i, p in ipairs(PRESETS) do if p.id == current then m.cursor = i end end
    for _, b in ipairs(BINDINGS) do
        mp.add_forced_key_binding(b[1], "sub-style-menu-" .. b[1], b[2])
    end
    mp.observe_property("mouse-pos", "native", on_mouse)
    mp.observe_property("osd-dimensions", "native", render)
    render()
end

local function menu()
    if o.menu_style == "classic" then menu_classic() else open_menu() end
end

for _, k in ipairs(KEYS) do startup[k] = mp.get_property_native(k) end
load_state()
apply()

mp.observe_property("current-tracks/sub", "native", function()
    publish()
    if m.open then render() end
end)
mp.add_key_binding(nil, "menu", menu)
mp.add_key_binding(nil, "menu-classic", menu_classic)
mp.register_script_message("set", function(id)
    if find(id) then current = id; save_state(); apply() end
end)
