-- Keyboard, mouse and touchpad, as in Plasma (modules/kde, hosts/wandersail):
-- AZERTY, Num Lock on, flat acceleration for every mouse (Plasma's
-- flat-mice) with each one's speed, the touchpad's natural scrolling, speed
-- and slower scrolling. Key repeat is Plasma's 600 ms and 25 per second,
-- Hyprland's defaults too. Device names are libinput's, lowercased, spaces
-- as dashes (hyprctl devices). A Logitech mouse is also a keyboard (its extra
-- buttons) under the same name; whichever comes up second gets "-1", so a
-- mouse's speed goes to both names.

hl.config({
    input = {
        kb_layout = "fr",
        numlock_by_default = true,
        accel_profile = "flat",
        touchpad = {
            natural_scroll = true,
            scroll_factor = 0.3,
        },
    },
})

-- Three fingers sideways scroll the tape.
hl.gesture({ fingers = 3, direction = "horizontal", action = "scroll_move" })

-- Four fingers: sideways or up and down, they drag the grid's desktops
-- (hyprslide, grid.lua); pinched together, the grid view (shadesmar's
-- DesktopGrid.qml), spread, back. Hyprland names a pinch by its zoom:
-- together is zoomout.
hl.gesture({ fingers = 4, direction = "zoomout", action = function()
    hl.dispatch(hl.dsp.global("shadesmar:grid-in"))
end })
hl.gesture({ fingers = 4, direction = "zoomin", action = function()
    hl.dispatch(hl.dsp.global("shadesmar:grid-out"))
end })

for name, speed in pairs({
    ["logitech-m720-triathlon"] = 0.4,
    ["logitech-mx-anywhere-3s"] = 0.4,
    ["logitech-g305"] = 0.2,
}) do
    hl.device({ name = name, sensitivity = speed })
    hl.device({ name = name .. "-1", sensitivity = speed })
end
hl.device({ name = "syna311e:00-06cb:cfca-touchpad", sensitivity = 1.0 })
