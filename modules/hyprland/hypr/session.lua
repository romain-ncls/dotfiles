-- The session (docs/hyprland.md): what apps see, and the lid.

-- Qt apps as in Plasma (kdeglobals: Nalthis's colors and icons) until
-- lumar; Plasma's cursor.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XCURSOR_THEME", "breeze_cursors")
hl.env("XCURSOR_SIZE", "24")

-- The lid, as Plasma has it (hyprland-lid.service keeps logind off it, and
-- off the Sleep key, which is mutectl's Lock AFK):
-- nothing at the desk, the screen locked on the charger, suspend on battery
-- (locked first by hypridle).
hl.bind("switch:on:Lid Switch", function()
    if #hl.get_monitors() > 1 then
        return
    end
    hl.exec_cmd("if grep -qx 1 /sys/class/power_supply/AC/online; then loginctl lock-session; else systemctl suspend; fi")
end, { locked = true })
