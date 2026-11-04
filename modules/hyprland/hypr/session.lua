-- The session (docs/hyprland.md): what apps see, and the lid.

-- environment.d's variables (gpg-ssh's SSH_AUTH_SOCK…), from systemd's own
-- generator: Plasma's startup reads them, Hyprland's doesn't.
local generator = io.popen("/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator")
if generator then
    for line in generator:lines() do
        local name, value = line:match("^([%w_]+)=(.*)$")
        if name then
            hl.env(name, value)
        end
    end
    generator:close()
end

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

-- KDE Connect's tray icon (Plasma shows it as a widget instead). Not in the
-- dev rigs: their daemon would be a second one with the same identity.
hl.on("hyprland.start", function()
    if not os.getenv("HYPR_DEV") then
        hl.exec_cmd("kdeconnect-indicator")
    end
end)
