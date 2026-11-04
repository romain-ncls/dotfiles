// A slider from 0 to 1: dragged, clicked or scrolled; moved(value) as it
// goes (the owner sets `value` from what it controls).
import QtQuick

Item {
    id: slider

    property real value: 0
    readonly property real clamped: Math.max(0, Math.min(1, value))

    signal moved(real value)

    implicitHeight: 24

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.slot

        Rectangle {
            width: parent.width * slider.clamped
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    Rectangle {
        x: (slider.width - width) * slider.clamped
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: Theme.text
    }

    MouseArea {
        anchors.fill: parent

        function at(x) {
            slider.moved(Math.max(0, Math.min(1, x / width)))
        }

        onPressed: event => at(event.x)
        onPositionChanged: event => {
            if (pressed)
                at(event.x)
        }
        onWheel: event => slider.moved(Math.max(0, Math.min(1, slider.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
