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

    Toggle {
        visible: header.toggle
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        checked: header.checked
        onToggled: header.toggled()
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
