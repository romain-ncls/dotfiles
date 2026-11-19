// An item of the bar, whatever it shows (BarButton.qml's icons, the clock,
// the tray's, the recording's): lit while its popup is open (`open`); the
// pointer on it, the bar's light comes under it (Bar.qml); a press sinks
// what it shows, not the item: its popup opens from where it stays. Its
// clicks and the wheel on it are the owner's.
import QtQuick

Item {
    id: item

    required property var bar
    property bool open: false
    property int buttons: Qt.LeftButton
    readonly property bool pressed: area.pressed
    // how far it's sunk, for the bar's light
    readonly property real sunk: face.scale
    default property alias content: inside.data

    signal clicked(var event)
    signal wheeled(var event)

    implicitHeight: Theme.barHeight - 8

    Item {
        id: face

        anchors.fill: parent
        scale: area.pressed ? Theme.sunk(width) : 1
        Squish on scale {}

        Rectangle {
            anchors.fill: parent
            radius: Theme.corner
            color: !item.open ? Theme.none : area.pressed ? Theme.pressed : Theme.selected
            Fade on color {}
        }

        Item {
            id: inside

            anchors.fill: parent
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: item.buttons
        onContainsMouseChanged: item.bar.point(item, containsMouse)
        onClicked: event => item.clicked(event)
        onWheel: event => item.wheeled(event)
    }

    // gone from under the pointer (a tray's app quitting)
    Component.onDestruction: {
        if (item.bar)
            item.bar.point(item, false)
    }
}
