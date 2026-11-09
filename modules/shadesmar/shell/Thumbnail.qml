// A window's picture, filling its own geometry (the overview moves it from
// the window's place into the grid and back), in a frame lit when it's the
// one picked. Captured once when it shows, then again on refresh(): a live
// one asks for a new frame at each repaint, so while it moves Hyprland
// would copy the window at every frame. Hyprland copies a window only
// while it overlaps its screen: the scrolling layout's columns beside it
// get their app's icon instead.
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
    // the picture kept: a frame when it shows, more on refresh()
    property bool capturing: true
    property real radius: 7
    // Hyprland's shadow (its defaults: 4 px, #1a1a1a at 93 %), while
    // it's in the window's place: its opacity
    property real shadow: 0
    // the frame's opacity when lit
    property real framed: 1
    readonly property bool hasContent: copy.hasContent

    function refresh() {
        if (thumb.capturing && copy.captureSource)
            copy.captureFrame()
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

    // no picture: its app's icon
    Rectangle {
        anchors.fill: parent
        visible: !copy.hasContent
        radius: thumb.radius
        color: Theme.slot

        IconImage {
            anchors.centerIn: parent
            implicitSize: Math.min(96, parent.height / 2)
            source: {
                const entry = DesktopEntries.heuristicLookup(thumb.appClass)
                return Quickshell.iconPath(entry ? entry.icon : thumb.appClass, "application-x-executable")
            }
        }
    }

    ScreencopyView {
        id: copy

        // at the window's own size, shown through the mipmapped copy below
        width: Math.max(1, sourceSize.width)
        height: Math.max(1, sourceSize.height)
        captureSource: thumb.capturing ? thumb.toplevel.wayland : null
        live: false
    }

    // A smaller picture is the window's averaged down (mipmaps), not
    // sampled: sampled, text loses strokes below half its size and blurs.
    // Drawn again only with a new frame, not while it moves.
    ShaderEffectSource {
        anchors.fill: parent
        visible: copy.hasContent
        sourceItem: copy
        hideSource: true
        mipmap: true
        smooth: true
    }

    // over the picture's corners
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: thumb.radius + 3
        color: "transparent"
        border.width: 3
        border.color: Theme.accent
        opacity: thumb.lit ? thumb.framed : 0
    }
}
