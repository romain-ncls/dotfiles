// A window's live picture, filling its own geometry (the overview moves it
// from the window's place into the grid and back), with rounded corners, in
// a frame lit when it's the one picked. Hyprland copies a window only while
// it overlaps its screen: the scrolling layout's columns beside it get their
// app's icon instead.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: thumb

    required property var toplevel
    property string appClass: ""
    property bool lit: false
    property bool live: true
    property real radius: 7
    // Hyprland's shadow (its defaults: 4 px, #1a1a1a at 93 %), while
    // it's in the window's place: its opacity
    property real shadow: 0
    // the frame's opacity when lit
    property real framed: 1
    readonly property bool hasContent: copy.hasContent

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: thumb.radius + 3
        color: "transparent"
        border.width: 3
        border.color: Theme.accent
        opacity: thumb.lit ? thumb.framed : 0
    }

    RectangularShadow {
        anchors.fill: parent
        visible: thumb.shadow > 0
        opacity: thumb.shadow
        radius: thumb.radius
        blur: 2
        spread: 0.5
        color: Qt.rgba(0.1, 0.1, 0.1, 0.93)
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: thumb.radius
        color: copy.hasContent ? "transparent" : Theme.slot

        ScreencopyView {
            id: copy

            anchors.fill: parent
            captureSource: thumb.live ? thumb.toplevel.wayland : null
            live: true
        }

        IconImage {
            visible: !copy.hasContent
            anchors.centerIn: parent
            implicitSize: Math.min(96, parent.height / 2)
            source: {
                const entry = DesktopEntries.heuristicLookup(thumb.appClass)
                return Quickshell.iconPath(entry ? entry.icon : thumb.appClass, "application-x-executable")
            }
        }
    }
}
