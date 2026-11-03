-- The dev rigs' screens (dev/headless.sh): three headless outputs named
-- like monitors.lua's roles, then the offscreen KWin's window off.

if os.getenv("HYPR_DEV") ~= "headless" then
    return
end

local function off()
    hl.monitor({ output = "WAYLAND-1", disabled = true })
end

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl output create headless LEFT; hyprctl output create headless LAPTOP; hyprctl output create headless RIGHT")
    hl.timer(off, { timeout = 1500, type = "oneshot" })
end)
hl.on("config.reloaded", off)
