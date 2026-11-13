// A section's name in a popup, small and spaced in capitals (KNOWN
// NETWORKS), with a word to click on the right (`action`).
import QtQuick

Item {
    id: section

    property string text: ""
    property string action: ""

    signal acted

    width: parent ? parent.width : 320
    height: 26

    Text {
        x: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        text: section.text.toUpperCase()
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
    }

    Text {
        visible: section.action !== ""
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        text: section.action
        color: link.containsMouse ? Theme.accent : Theme.dim
        font.family: Theme.font
        font.pixelSize: 11

        MouseArea {
            id: link

            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onClicked: section.acted()
        }
    }
}
