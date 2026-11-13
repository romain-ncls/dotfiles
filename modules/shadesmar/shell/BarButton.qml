// An item of the bar: an icon, maybe a label and a count. A click opens its
// popup (or closes it); a middle click and the wheel are the item's.
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: button

    required property var bar
    required property string popup
    property string icon: ""
    property string label: ""
    property color labelColor: Theme.text
    property int badge: 0

    signal middleClicked
    signal scrolled(int delta)

    implicitWidth: row.implicitWidth + 14
    implicitHeight: Theme.barHeight - 8

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: area.containsMouse || button.bar.open === button.popup ? Theme.slot : "transparent"
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            icon: button.icon
        }

        Text {
            visible: button.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: button.label
            color: button.labelColor
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    Rectangle {
        visible: button.badge > 0
        anchors.right: parent.right
        anchors.top: parent.top
        width: Math.max(16, count.implicitWidth + 8)
        height: 16
        radius: 8
        color: Theme.accent

        Text {
            id: count

            anchors.centerIn: parent
            text: button.badge
            color: Theme.accentText
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                button.middleClicked()
            else
                button.bar.open = button.bar.open === button.popup ? "" : button.popup
        }
        onWheel: event => button.scrolled(event.angleDelta.y)
    }
}
