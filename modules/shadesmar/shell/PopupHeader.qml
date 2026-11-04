// A popup's title, with a switch on the right when `toggle`, or a word to
// click (`action`).
import QtQuick

Item {
    id: header

    property string title: ""
    property bool toggle: false
    property bool checked: false
    property string action: ""

    signal toggled
    signal acted

    width: parent ? parent.width : 320
    height: 30

    Text {
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        text: header.title
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Rectangle {
        visible: header.toggle
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 20
        radius: 10
        color: header.checked ? Theme.accent : Theme.slot

        Rectangle {
            x: header.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: Theme.text

            Behavior on x {
                NumberAnimation {
                    duration: 100
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: header.toggled()
        }
    }

    Text {
        visible: header.action !== ""
        anchors.right: parent.right
        anchors.rightMargin: header.toggle ? 50 : 4
        anchors.verticalCenter: parent.verticalCenter
        text: header.action
        color: link.containsMouse ? Theme.accent : Theme.dim
        font.family: Theme.font
        font.pixelSize: 12

        MouseArea {
            id: link

            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onClicked: header.acted()
        }
    }
}
