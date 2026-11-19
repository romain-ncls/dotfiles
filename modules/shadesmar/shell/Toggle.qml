// A switch: on in the accent's color, its knob dark on it (white on the
// light blue was hard to see); off, a light knob on the slot. A click
// toggles it (`toggled`; the owner sets `checked`). Under the pointer, a
// soft halo round the knob (Material's); held, the knob stretches toward
// where it'll go, as iOS's; it slides there and the colors follow.
import QtQuick

Item {
    id: toggle

    property bool checked: false

    signal toggled

    width: 36
    height: 20

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? Theme.accent : Theme.slot

        Behavior on color {
            enabled: Theme.speed > 0
            ColorAnimation {
                duration: Theme.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.fade
            }
        }
    }

    // the halo, round the knob, under it
    Rectangle {
        anchors.centerIn: knob
        width: 28
        height: 28
        radius: width / 2
        color: toggle.checked ? Theme.alpha(Theme.accent, 0.25) : Theme.alpha(Theme.textColor, 0.12)
        opacity: area.pressed ? 1 : area.containsMouse ? 0.7 : 0
        scale: area.containsMouse || area.pressed ? 1 : 0.6

        Behavior on opacity {
            enabled: Theme.speed > 0
            NumberAnimation {
                duration: Theme.fast
            }
        }
        Behavior on scale {
            enabled: Theme.speed > 0
            Ease {
                duration: Theme.fast
            }
        }
    }

    Rectangle {
        id: knob

        readonly property real gap: (toggle.height - height) / 2

        x: toggle.checked ? toggle.width - width - gap : gap
        anchors.verticalCenter: parent.verticalCenter
        height: 14
        width: area.pressed ? height + 5 : height
        radius: height / 2
        color: toggle.checked ? Theme.accentText : Theme.text

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
        Behavior on color {
            enabled: Theme.speed > 0
            ColorAnimation {
                duration: Theme.normal
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
