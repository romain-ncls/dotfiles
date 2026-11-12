-- How it moves: quick animations. How the workspaces switch is set by
-- grid.lua at each switch (the way the desktop lies); how it looks (gaps,
-- corners, colors) is lumar.lua's.

hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slidefade 10%" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slidefadevert 20%" })

-- shadesmar's overview moves its thumbnails itself, from the windows'
-- places: its first frame covers them exactly, which a fade would spoil.
hl.layer_rule({ name = "shadesmar-overview", match = { namespace = "^shadesmar-overview$" }, no_anim = true })
-- The grid view (DesktopGrid.qml) zooms out of the screen: the same.
hl.layer_rule({ name = "shadesmar-grid", match = { namespace = "^shadesmar-grid$" }, no_anim = true })

-- LumineCapture's editor (modules/lumine-capture): the screens frozen, there
-- at once.
hl.layer_rule({ name = "lumine-capture", match = { namespace = "^lumine-capture$" }, no_anim = true })
