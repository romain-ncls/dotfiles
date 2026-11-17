// A small button with a line icon of ours (icons/<icon>.svg): the clock's
// month steps, the year view's, the world clock's rows.
import QtQuick

Item {
    id: chevron

    property string icon: ""
    readonly property bool hovered: press.containsMouse

    signal clicked

    width: 32
    height: 32

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: press.containsMouse ? Theme.slot : "transparent"
    }

    Glyph {
        anchors.centerIn: parent
        size: 16
        source: Qt.resolvedUrl(`icons/${chevron.icon}.svg`)
        color: Theme.dim
    }

    MouseArea {
        id: press

        anchors.fill: parent
        hoverEnabled: true
        onClicked: chevron.clicked()
    }
}
