// A window's live picture, in its shape, fitted in maxWidth × maxHeight, in
// a frame lit when it's the one picked (the overview, Alt+Tab). Hyprland
// copies a window only while it overlaps its screen: the scrolling layout's
// columns beside it get their app's icon instead.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

Rectangle {
    id: thumb

    required property var toplevel
    property real maxWidth: 320
    property real maxHeight: 200
    property bool lit: false
    property bool live: true
    readonly property var size: toplevel.lastIpcObject.size ?? [16, 9]
    readonly property real scale: Math.min(maxWidth / size[0], maxHeight / size[1], 1)

    width: size[0] * scale + 6
    height: size[1] * scale + 6
    radius: 10
    color: copy.hasContent ? "transparent" : Theme.slot
    border.width: 3
    border.color: lit ? Theme.accent : "transparent"

    ScreencopyView {
        id: copy

        anchors.fill: parent
        anchors.margins: 3
        captureSource: thumb.live ? thumb.toplevel.wayland : null
        live: true
        constraintSize: Qt.size(width, height)
    }

    IconImage {
        visible: !copy.hasContent
        anchors.centerIn: parent
        implicitSize: Math.min(96, parent.height / 2)
        source: {
            const cls = thumb.toplevel.lastIpcObject.class || ""
            const entry = DesktopEntries.heuristicLookup(cls)
            return Quickshell.iconPath(entry ? entry.icon : cls, "application-x-executable")
        }
    }
}
