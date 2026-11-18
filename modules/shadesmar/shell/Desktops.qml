// The four desktops of the grid (modules/hyprland/hypr/grid.lua), as a
// 2×2 square: the one shown is lit, the light sliding there at a switch; a
// click switches to another. Desktop d is workspace d on the left screen
// (or the laptop alone) and 4 + d on the right one.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Item {
    id: desktops

    readonly property int cellWidth: 22
    readonly property int cellHeight: 13
    readonly property int gap: 3

    implicitWidth: 2 * cellWidth + gap
    implicitHeight: 2 * cellHeight + gap

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

    Grid {
        columns: 2
        spacing: desktops.gap

        Repeater {
            model: 4

            Rectangle {
                required property int index
                readonly property int desktop: index + 1

                width: desktops.cellWidth
                height: desktops.cellHeight
                radius: 3
                color: Theme.slot

                MouseArea {
                    anchors.fill: parent
                    onClicked: Quickshell.execDetached(["hyprctl", "eval", `package.loaded["grid"].go(${parent.desktop})`])
                }
            }
        }
    }

    // the light, on the one shown
    Rectangle {
        visible: desktops.current >= 1
        x: (desktops.current - 1) % 2 * (desktops.cellWidth + desktops.gap)
        y: Math.floor((desktops.current - 1) / 2) * (desktops.cellHeight + desktops.gap)
        width: desktops.cellWidth
        height: desktops.cellHeight
        radius: 3
        color: Theme.accent

        Behavior on x {
            Ease {
                easing.bezierCurve: Theme.move
            }
        }
        Behavior on y {
            Ease {
                easing.bezierCurve: Theme.move
            }
        }
    }
}
