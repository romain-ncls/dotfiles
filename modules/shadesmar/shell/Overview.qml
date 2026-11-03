// The overview (Plasma's, on Meta+Tab and Ctrl+Alt+Tab): on every screen,
// the windows of the workspace it shows, the scrolling layout's columns
// beside the screen included, as live thumbnails in their order. A click
// or Enter goes to one, the arrows move between them, typing filters them
// by title or app on every screen; Escape, a click beside them or the key
// again closes it.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: overview

    property bool shown: false
    property string filter: ""

    function open() {
        // Quickshell follows only the focused screen's switches, and the
        // windows' places come with a refresh.
        Hyprland.refreshMonitors()
        Hyprland.refreshToplevels()
        filter = ""
        shown = true
    }
    function close() {
        shown = false
    }
    function toggle() {
        if (shown)
            close()
        else
            open()
    }
    function go(toplevel) {
        close()
        if (toplevel && toplevel.wayland)
            toplevel.wayland.activate()
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "overview"
        description: "The windows of every screen"
        onPressed: overview.toggle()
    }

    // qs -c shadesmar ipc call overview toggle
    IpcHandler {
        target: "overview"

        function toggle(): void {
            overview.toggle()
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: view

            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool focusedScreen: monitor !== null && monitor.focused

            // The workspace's windows, left to right as the tape has them. By
            // the workspace's name: a named one (comms) has no id in 0.57.
            readonly property var windows: {
                const ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.name : null
                const f = overview.filter.toLowerCase()
                return Hyprland.toplevels.values.filter(t => {
                    const o = t.lastIpcObject
                    if (!o || !o.workspace || o.workspace.name !== ws || !o.size)
                        return false
                    return f === "" || `${t.title} ${o.class}`.toLowerCase().includes(f)
                }).sort((a, b) => a.lastIpcObject.at[0] - b.lastIpcObject.at[0] || a.lastIpcObject.at[1] - b.lastIpcObject.at[1])
            }
            property int selected: 0

            readonly property int gap: 32
            readonly property int titleHeight: 28
            // The columns that give the biggest thumbnails.
            readonly property int cols: {
                const n = windows.length
                if (n === 0)
                    return 1
                const w = Math.max(...windows.map(t => t.lastIpcObject.size[0]))
                const h = Math.max(...windows.map(t => t.lastIpcObject.size[1]))
                let best = 1, bestScale = 0
                for (let c = 1; c <= n; c++) {
                    const r = Math.ceil(n / c)
                    const s = Math.min((area.width - (c - 1) * gap) / c / w, ((area.height - (r - 1) * gap) / r - titleHeight) / h)
                    if (s > bestScale) {
                        best = c
                        bestScale = s
                    }
                }
                return best
            }
            readonly property int rows: Math.max(1, Math.ceil(windows.length / cols))
            readonly property real cellWidth: (area.width - (cols - 1) * gap) / cols
            readonly property real cellHeight: (area.height - (rows - 1) * gap) / rows

            screen: modelData
            visible: overview.shown
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shadesmar-overview"
            WlrLayershell.keyboardFocus: focusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Connections {
                target: overview

                // the active window first, as Plasma's
                function onShownChanged() {
                    const i = view.windows.indexOf(Hyprland.activeToplevel)
                    view.selected = Math.max(0, i)
                }
                function onFilterChanged() {
                    view.selected = 0
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.shade
                opacity: overview.shown ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: overview.close()
            }

            // The filter, on the focused screen.
            Rectangle {
                visible: view.focusedScreen
                anchors.horizontalCenter: parent.horizontalCenter
                y: 24
                width: 360
                height: 36
                radius: 18
                color: Theme.bar

                Text {
                    anchors.centerIn: parent
                    text: overview.filter === "" ? "Type to filter" : overview.filter
                    color: overview.filter === "" ? Theme.dim : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                }
            }

            Item {
                id: area

                anchors.fill: parent
                anchors.margins: 64
                anchors.topMargin: 84

                Repeater {
                    model: view.windows

                    Item {
                        id: cell

                        required property var modelData
                        required property int index
                        readonly property int row: Math.floor(index / view.cols)
                        readonly property int col: index % view.cols
                        readonly property int inRow: Math.min(view.cols, view.windows.length - row * view.cols)
                        readonly property var size: modelData.lastIpcObject.size
                        readonly property real scale: Math.min(width / size[0], (height - view.titleHeight) / size[1], 1)
                        readonly property bool selected: view.focusedScreen && view.selected === index

                        // the last row centred
                        x: ((view.cols - inRow) / 2 + col) * (view.cellWidth + view.gap)
                        y: row * (view.cellHeight + view.gap)
                        width: view.cellWidth
                        height: view.cellHeight

                        Rectangle {
                            id: frame

                            anchors.horizontalCenter: parent.horizontalCenter
                            y: (parent.height - view.titleHeight - height) / 2
                            width: cell.size[0] * cell.scale + 6
                            height: cell.size[1] * cell.scale + 6
                            radius: 10
                            color: copy.hasContent ? "transparent" : Theme.slot
                            border.width: 3
                            border.color: cell.selected || hover.containsMouse ? Theme.accent : "transparent"

                            ScreencopyView {
                                id: copy

                                anchors.fill: parent
                                anchors.margins: 3
                                captureSource: overview.shown ? cell.modelData.wayland : null
                                live: true
                                constraintSize: Qt.size(width, height)
                            }

                            // Hyprland copies a window only while it's on its
                            // screen: the columns beside it get their app's
                            // icon instead.
                            IconImage {
                                visible: !copy.hasContent
                                anchors.centerIn: parent
                                implicitSize: Math.min(96, parent.height / 2)
                                source: {
                                    const cls = cell.modelData.lastIpcObject.class || ""
                                    const entry = DesktopEntries.heuristicLookup(cls)
                                    return Quickshell.iconPath(entry ? entry.icon : cls, "application-x-executable")
                                }
                            }
                        }

                        Text {
                            anchors.top: frame.bottom
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(implicitWidth, cell.width)
                            text: cell.modelData.title
                            elide: Text.ElideRight
                            color: cell.selected ? Theme.text : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: frame
                            hoverEnabled: true
                            onEntered: view.selected = cell.index
                            onClicked: overview.go(cell.modelData)
                        }
                    }
                }
            }

            Item {
                focus: true

                Keys.onPressed: event => {
                    const n = view.windows.length
                    switch (event.key) {
                    case Qt.Key_Escape:
                        overview.close()
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (n > 0)
                            overview.go(view.windows[view.selected])
                        break
                    case Qt.Key_Left:
                        if (n > 0)
                            view.selected = (view.selected + n - 1) % n
                        break
                    case Qt.Key_Right:
                    case Qt.Key_Tab:
                        if (n > 0)
                            view.selected = (view.selected + 1) % n
                        break
                    case Qt.Key_Up:
                        view.selected = Math.max(0, view.selected - view.cols)
                        break
                    case Qt.Key_Down:
                        view.selected = Math.min(n - 1, view.selected + view.cols)
                        break
                    case Qt.Key_Backspace:
                        overview.filter = overview.filter.slice(0, -1)
                        break
                    default:
                        if (event.text.length !== 1 || event.text < " ")
                            return
                        overview.filter += event.text
                    }
                    event.accepted = true
                }
            }
        }
    }
}
