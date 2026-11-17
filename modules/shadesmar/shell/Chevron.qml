// A small button with a line icon of ours (icons/<icon>.svg): the clock's
// month steps and year button, the year view's, Claude's reload (turn():
// the icon goes round once, to say it was done).
import QtQuick

Item {
    id: chevron

    property string icon: ""

    signal clicked

    function turn() {
        spin.restart()
    }

    width: 32
    height: 32

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: press.containsMouse ? Theme.slot : "transparent"
    }

    Glyph {
        id: glyph

        anchors.centerIn: parent
        size: 16
        source: Qt.resolvedUrl(`icons/${chevron.icon}.svg`)
        color: press.containsMouse ? Theme.text : Theme.dim
    }

    RotationAnimator {
        id: spin

        target: glyph
        from: 0
        to: 360
        duration: 500
        easing.type: Easing.OutCubic
    }

    MouseArea {
        id: press

        anchors.fill: parent
        hoverEnabled: true
        onClicked: chevron.clicked()
    }
}
