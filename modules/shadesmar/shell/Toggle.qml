// A switch: on in the accent's color. A click toggles it (`toggled`; the
// owner sets `checked`). Under the pointer its knob grows and its track
// lightens; held, the knob stretches toward where it'll go, as iOS's; it
// slides there and the track's color follows.
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

    // the pointer on it: the text's color over the track, as on a row
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: area.containsMouse ? Theme.hover : Theme.none
        Fade on color {}
    }

    Rectangle {
        id: knob

        readonly property real gap: (toggle.height - height) / 2

        x: toggle.checked ? toggle.width - width - gap : gap
        anchors.verticalCenter: parent.verticalCenter
        height: area.containsMouse || area.pressed ? 16 : 14
        width: area.pressed ? height + 5 : height
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
        Behavior on height {
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
        hoverEnabled: true
        onClicked: toggle.toggled()
    }
}
