// The four desktops of the grid (modules/hyprland/hypr/grid.lua), as a
// 2×2 square: the one shown is lit, a click switches to another. Desktop d
// is workspace d on the left screen (or the laptop alone) and 4 + d on the
// right one.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Grid {
    id: desktops

    columns: 2
    spacing: 3

    // The desktop shown (0: none, comms in place of the grid on the laptop
    // alone). Read from the screens when the bar starts, then told by the
    // grid at each switch ("grid d"): Hyprland only says which workspace the
    // focused screen switched to, so the other screens' would go stale.
    property int current: {
        for (const m of Hyprland.monitors.values) {
            const id = m.activeWorkspace ? m.activeWorkspace.id : 0
            if (id >= 1 && id <= 8)
                return (id - 1) % 4 + 1
        }
        return 0
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "custom" && event.data.startsWith("grid "))
                desktops.current = parseInt(event.data.slice(5))
        }
    }

    Repeater {
        model: 4

        Rectangle {
            required property int index
            readonly property int desktop: index + 1

            width: 22
            height: 13
            radius: 3
            color: desktop === desktops.current ? Theme.accent : Theme.slot

            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(["hyprctl", "eval", `package.loaded["grid"].go(${parent.desktop})`])
            }
        }
    }
}
