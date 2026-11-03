-- The screens. At the desk at work, a BenQ GW2283 on each side of the
-- laptop, tops aligned (as hosts/wandersail/work-screens has them for
-- KWin); away from it, the laptop's panel alone. The BenQs are known by
-- their EDID description (make, model, serial: the two models are the
-- same), not by port, which the dock renumbers. What each screen is for is
-- grid.lua's.
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
-- Anything else (a projector, a TV): its own mode, to the right.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

return screens
