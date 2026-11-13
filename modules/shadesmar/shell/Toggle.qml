// A switch: on in the accent's color. A click toggles it (`toggled`; the
// owner sets `checked`).
import QtQuick

Rectangle {
    id: toggle

    property bool checked: false

    signal toggled

    width: 36
    height: 20
    radius: 10
    color: checked ? Theme.accent : Theme.slot

    Rectangle {
        x: toggle.checked ? parent.width - width - 3 : 3
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
        anchors.margins: -4
        onClicked: toggle.toggled()
    }
}
