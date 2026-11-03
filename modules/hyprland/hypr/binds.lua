-- Binds, close to Plasma's (docs/hyprland.md, Binds). For now only enough to
-- use a session: a terminal, closing a window, dragging, logging out.

local mod = "SUPER"

hl.bind(mod .. " + Return", hl.dsp.exec_cmd("ghostty", { float = true }))
hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd("ghostty"))
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
-- Plasma's "Log Out Without Confirmation"
hl.bind("CTRL + ALT + SHIFT + Delete", hl.dsp.exit())
