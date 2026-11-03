-- Keyboard, mouse and touchpad, as in Plasma (modules/kde, hosts/wandersail):
-- AZERTY, Num Lock on, the touchpad's natural scrolling. Key repeat is
-- Plasma's 600 ms and 25 per second, Hyprland's defaults too.

hl.config({
    input = {
        kb_layout = "fr",
        numlock_by_default = true,
        touchpad = {
            natural_scroll = true,
        },
    },
})
