// A slider from 0 to 1: dragged, clicked or scrolled; moved(value) as it
// goes (the owner sets `value` from what it controls). Changed from
// elsewhere (the wheel, the keys), it glides there; held, it's under the
// pointer, its knob bigger.
import QtQuick

Item {
    id: slider

    property real value: 0
    readonly property real clamped: Math.max(0, Math.min(1, value))
    property real drawn: clamped
    Behavior on drawn {
        enabled: Theme.speed > 0 && !area.pressed
        Follow {}
    }

    signal moved(real value)

    implicitHeight: 24

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: height / 2
        color: Theme.slot

        Rectangle {
            width: parent.width * slider.drawn
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    Rectangle {
        x: (slider.width - width) * slider.drawn
        anchors.verticalCenter: parent.verticalCenter
        width: area.pressed ? 18 : 14
        height: width
        radius: height / 2
        color: Theme.text

        Behavior on width {
            Ease {
                duration: Theme.fast
            }
        }
    }

    MouseArea {
        id: area

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
