// A window's picture, filling its own geometry (the overview moves it from
// the window's place into the grid and back), in a frame lit when it's the
// one picked. Captured once when it shows, then again on refresh(): a live
// one asks for a new frame at each repaint, so while it moves Hyprland
// would copy the window at every frame. Hyprland copies a window only
// while it overlaps its screen: a column beside the screen shows the
// picture WindowPictures.qml kept, or else its app's icon, until its own
// comes (the tape scrolls to it).
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
    // the window's last picture (WindowPictures.qml), lent while shown
    property Item kept: null
    property real radius: 7
    // Hyprland's shadow (its defaults: 4 px, #1a1a1a at 93 %), while
    // it's in the window's place: its opacity
    property real shadow: 0
    // the frame's opacity when lit
    property real framed: 1
    // its own picture, of the window as it is now
    readonly property bool hasContent: copy.hasContent
    readonly property Item picture: copy.hasContent ? copy : kept && kept.hasContent ? kept : null

    function refresh() {
        if (thumb.capturing && copy.captureSource)
            copy.captureFrame()
    }

    // the kept picture comes into this window while it's the one shown, and
    // leaves it after
    function lend() {
        if (!kept)
            return
        if (picture === kept)
            kept.parent = thumb
        else if (kept.parent === thumb)
            kept.parent = null
    }
    onPictureChanged: lend()
    Component.onCompleted: lend()
    Component.onDestruction: {
        if (kept && kept.parent === thumb)
            kept.parent = null
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
        visible: thumb.picture === null
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
        visible: thumb.picture !== null
        sourceItem: thumb.picture
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
