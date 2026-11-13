// A popup of the bar, above the bar item it opens from. One at a time: the
// bar's `open` names it. It has the keyboard (its filter, a password) while
// open; a click elsewhere, or Escape, closes it.
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
    // the screen less the bar and a margin
    readonly property real room: (bar.screen ? bar.screen.height : 1080) - Theme.barHeight - 48
    implicitHeight: Math.min(body.implicitHeight, room) + 24
    color: "transparent"

    // Clicks elsewhere close it, but not on the bar: a click on its items
    // opens another popup, not nothing. Started once the popup's window is
    // shown: started with `visible`, it leaves the popup out (Quickshell
    // makes the popup's surface after it), and a click in the popup closes
    // it. The popup alone first: Hyprland gives the keyboard to the grab's
    // window under the pointer, else its first, and the pointer is on the
    // bar; the bar joins once the popup has it.
    HyprlandFocusGrab {
        id: grab

        windows: grab.active ? [popup, popup.bar] : [popup]
        active: popup.backingWindowVisible
        onCleared: popup.close()
    }

    // Escape, from its fields too
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: popup.close()

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.popup
            border.width: 1
            border.color: Theme.outline

            // taller than the screen leaves room for, it scrolls (its long
            // lists scroll themselves first)
            Flickable {
                x: 12
                y: 12
                width: parent.width - 24
                height: parent.height - 24
                contentHeight: body.implicitHeight
                interactive: contentHeight > height
                clip: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: body

                    width: popup.popupWidth - 24
                    spacing: 6
                }
            }
        }
    }
}
