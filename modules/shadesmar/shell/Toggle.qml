// A switch: on in the accent's color. A click toggles it (`toggled`; the
// owner sets `checked`). Held, its knob stretches toward where it'll go,
// as iOS's; it slides there and the track's color follows.
import QtQuick

Rectangle {
    id: toggle

    property bool checked: false

    signal toggled

    width: 36
    height: 20
    radius: height / 2
    color: checked ? Theme.accent : Theme.slot

    Behavior on color {
        enabled: Theme.speed > 0
        ColorAnimation {
            duration: Theme.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.fade
        }
    }

    Rectangle {
        x: toggle.checked ? parent.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: area.pressed ? 19 : 14
        height: 14
        radius: height / 2
        color: Theme.text

        Behavior on x {
            enabled: Theme.speed > 0
            Ease {}
        }
        Behavior on width {
            enabled: Theme.speed > 0
            Ease {
                duration: Theme.fast
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -4
        onClicked: toggle.toggled()
    }
}
