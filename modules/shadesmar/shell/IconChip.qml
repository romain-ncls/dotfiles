// An icon in a circle (a row's, a popup's head's), as Control Center's: lit
// (on, connected, in use), the accent's circle with the icon dark on it;
// else a faint one; while something's under way (`pulsing`: connecting),
// the accent comes and goes in it. Its icon changing pops in (Glyph.qml).
import QtQuick
import Quickshell

Rectangle {
    id: chip

    property string icon: ""
    // or a picture of ours (icons/)
    property string source: ""
    property bool lit: false
    property bool warn: false
    property bool pulsing: false
    property int size: Theme.chip
    property int glyph: 16

    width: size
    height: size
    radius: size / 2
    color: warn ? Theme.alpha(Theme.warn, 0.18) : lit ? Theme.accent : Theme.face

    Behavior on color {
        enabled: Theme.speed > 0
        ColorAnimation {
            duration: Theme.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.fade
        }
    }

    Rectangle {
        id: pulse

        anchors.fill: parent
        radius: width / 2
        color: Theme.accent
        opacity: 0

        SequentialAnimation on opacity {
            running: chip.pulsing && !chip.lit && Theme.speed > 0
            loops: Animation.Infinite
            onRunningChanged: {
                if (!running)
                    pulse.opacity = 0
            }

            NumberAnimation {
                to: 0.55
                duration: 600
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 0.1
                duration: 600
                easing.type: Easing.InOutSine
            }
        }
    }

    Glyph {
        anchors.centerIn: parent
        size: chip.glyph
        icon: chip.icon
        source: chip.source !== "" ? chip.source : chip.icon !== "" ? Quickshell.iconPath(chip.icon, "image-missing") : ""
        color: chip.warn ? Theme.warn : chip.lit ? Theme.accentText : Theme.text
        pops: true
    }
}
