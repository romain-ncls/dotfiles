-- Keyboard, mouse and touchpad, as in Plasma (modules/kde, hosts/wandersail):
-- AZERTY, Num Lock on, flat acceleration for every mouse (Plasma's
-- flat-mice) with each one's speed, the touchpad's natural scrolling, speed
-- and slower scrolling. Key repeat is Plasma's 600 ms and 25 per second,
-- Hyprland's defaults too. Device names are libinput's, lowercased, spaces
-- as dashes (hyprctl devices).

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

for name, speed in pairs({
    ["logitech-m720-triathlon"] = 0.4,
    ["logitech-mx-anywhere-3s"] = 0.4,
    ["logitech-g305"] = 0.2,
    ["syna311e:00-06cb:cfca-touchpad"] = 1.0,
}) do
    hl.device({ name = name, sensitivity = speed })
end
