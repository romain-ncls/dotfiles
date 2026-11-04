//@ pragma UseQApplication
// shadesmar (modules/shadesmar; plan: docs/hyprland.md): the bar, at the
// bottom of the laptop's screen where Plasma's panel is, with the
// notifications above it; the overview over every screen; the launcher and
// the OSD on the focused one. (The pragma: the tray's menus are Qt
// widgets' menus.)
import QtQuick
import Quickshell

ShellRoot {
    // The laptop's panel; the dev rigs' (modules/hyprland/hypr/monitors.lua)
    // otherwise, or the first screen.
    readonly property var barScreen: {
        for (const name of ["eDP-1", "LAPTOP", "WAYLAND-1"]) {
            const s = Quickshell.screens.find(s => s.name === name)
            if (s)
                return s
        }
        return Quickshell.screens[0]
    }

    Wallpaper {}
    Overview {}
    Osd {}
    Launcher {}
    Notifications {
        id: notifications

        screen: barScreen
    }

    Bar {
        notifications: notifications
        screen: barScreen
    }
}
