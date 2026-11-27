-- The screens. At the desk at work, a BenQ GW2283 on each side of the
-- laptop, tops aligned (as hosts/wandersail/work-screens has them for
-- KWin); at home, an MSI MAG342CQR (34", 3440x1440) on the laptop's left;
-- elsewhere, the laptop's panel alone. The screens are known by their EDID
-- description (make, model, serial: the BenQs are the same model), not by
-- port, which the dock renumbers. What each screen is for is grid.lua's
-- (home's, not the desk's: the desktops).
--
-- Returns the screens' selectors, for grid.lua. The dev rigs have their
-- own: nested, the window is the laptop alone; headless, three headless
-- outputs named like the roles, which dev/headless.sh's config creates.

local dev = os.getenv("HYPR_DEV")

local screens
if dev == "headless" then
    screens = { left = "LEFT", laptop = "LAPTOP", right = "RIGHT" }
elseif dev == "nested" then
    screens = { laptop = "WAYLAND-1" }
else
    screens = {
        left = "desc:BNQ BenQ GW2283 W4L05023019",
        laptop = "eDP-1",
        right = "desc:BNQ BenQ GW2283 X9L04632019",
        home = "desc:Microstep MSI MAG342CQR DB6H261C02762",
    }
end

local layout = {
    { screens.left, "1920x1080", "0x0" },
    { screens.laptop, "1920x1200", "1920x0" },
    { screens.right, "1920x1080", "3840x0" },
}
for _, s in ipairs(layout) do
    if s[1] then
        local mode = dev == "headless" and s[2] or "preferred"
        hl.monitor({ output = s[1], mode = mode, position = s[3], scale = 1 })
    end
end
-- Home's: its preferred mode over HDMI is 50 Hz, so its native one at
-- 100 Hz; left of the laptop (1920 - 3440), tops aligned as at the desk.
-- (Hyprland gives XWayland its own layout from 0: a negative x is fine.)
if screens.home then
    hl.monitor({ output = screens.home, mode = "3440x1440@100", position = "-1520x0", scale = 1 })
end
-- Anything else (a screen at home, a projector): its own mode, to the
-- right; away from the desk, grid.lua gives it the desktops.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

return screens
