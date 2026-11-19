// The four desktops of the grid (modules/hyprland/hypr/grid.lua), as a
// 2×2 square: the one shown is lit, the light going there at a switch, its
// front first and its back after, so it stretches on the way; a click
// switches to another (the square pressed sinks). Desktop d is workspace d on the left screen
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
                scale: cell.pressed ? Theme.sunk(width) : 1
                Squish on scale {}

                MouseArea {
                    id: cell

                    anchors.fill: parent
                    onClicked: Quickshell.execDetached(["hyprctl", "eval", `package.loaded["grid"].go(${parent.desktop})`])
                }
            }
        }
    }

    // the light, on the one shown (none, it waits on the first, unseen):
    // its four edges, each going on its own, the one in front quicker
    readonly property int column: (Math.max(1, current) - 1) % 2
    readonly property int line: Math.floor((Math.max(1, current) - 1) / 2)
    property real leftEdge: column * (cellWidth + gap)
    property real topEdge: line * (cellHeight + gap)
    property real rightEdge: column * (cellWidth + gap) + cellWidth
    property real bottomEdge: line * (cellHeight + gap) + cellHeight

    Stretch on leftEdge {
        leading: true
        from: desktops.leftEdge
    }
    Stretch on rightEdge {
        from: desktops.rightEdge
    }
    Stretch on topEdge {
        leading: true
        from: desktops.topEdge
    }
    Stretch on bottomEdge {
        from: desktops.bottomEdge
    }

    Rectangle {
        visible: desktops.current >= 1
        x: desktops.leftEdge
        y: desktops.topEdge
        width: desktops.rightEdge - desktops.leftEdge
        height: desktops.bottomEdge - desktops.topEdge
        radius: 3
        color: Theme.accent
    }
}
