// A section's name in a popup, small and spaced in capitals (KNOWN
// NETWORKS), above its plate (Section.qml), in line with its rows' icons;
// a word to click on the right (`action`). One that folds (`folds`): the
// name is a button, its chevron turning as it opens.
import QtQuick

Item {
    id: section

    property string text: ""
    property string action: ""
    property bool folds: false
    property bool open: true

    signal acted
    signal toggled

    width: parent ? parent.width : 320
    height: 26

    Row {
        id: name

        x: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: section.text.toUpperCase()
            color: section.folds && foldArea.containsMouse ? Theme.text : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.small
            font.weight: Font.Medium
            font.letterSpacing: 1
        }

        Glyph {
            visible: section.folds
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            source: Qt.resolvedUrl("icons/chevron-right.svg")
            color: foldArea.containsMouse ? Theme.text : Theme.dim
            rotation: section.open ? 90 : 0

            Behavior on rotation {
                enabled: Theme.speed > 0
                Ease {}
            }
        }
    }

    // the name's button, a little larger than it
    MouseArea {
        id: foldArea

        enabled: section.folds
        x: name.x - 6
        y: name.y - 4
        width: name.width + 12
        height: name.height + 8
        hoverEnabled: true
        onClicked: section.toggled()
    }

    Text {
        visible: section.action !== ""
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        text: section.action
        color: link.containsMouse ? Theme.accent : Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.small

        MouseArea {
            id: link

            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onClicked: section.acted()
        }
    }
}
