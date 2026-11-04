// A popup of the bar, above the bar item it opens from. One at a time: the
// bar's `open` names it. A click elsewhere, or Escape, closes it.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: popup

    required property var bar
    required property Item from
    required property string name
    property int popupWidth: 360
    default property alias content: body.data

    readonly property bool shown: bar.open === name

    function close() {
        if (shown)
            bar.open = ""
    }

    anchor.window: bar
    anchor.item: from
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.SlideX
    anchor.rect.y: -6
    visible: shown
    implicitWidth: popupWidth
    implicitHeight: body.implicitHeight + 24
    color: "transparent"

    // the bar too: a click on its items opens another popup, not nothing
    HyprlandFocusGrab {
        windows: [popup, popup.bar]
        active: popup.visible
        onCleared: popup.close()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.popup
        border.width: 1
        border.color: Theme.outline

        Column {
            id: body

            x: 12
            y: 12
            width: parent.width - 24
            spacing: 6
        }
    }

    Item {
        focus: true
        Keys.onEscapePressed: popup.close()
    }
}
