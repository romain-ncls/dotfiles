// An icon in one color: a theme icon's name (`icon`) or a picture
// (`source`), its shape in `color` (the text's by default). With `pops`, a
// new icon (muted, connected, charging) comes in small and springs to its
// size; swing() rocks it from its top, as a bell rings.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

Item {
    id: glyph

    property string icon: ""
    property string source: icon !== "" ? Quickshell.iconPath(icon, "image-missing") : ""
    property color color: Theme.text
    property int size: Theme.icon
    property bool pops: false

    implicitWidth: size
    implicitHeight: size

    property bool ready: false
    Component.onCompleted: ready = true
    onSourceChanged: {
        if (pops && ready && Theme.speed > 0)
            pop.restart()
    }

    function swing() {
        if (Theme.speed > 0)
            rock.restart()
    }

    IconImage {
        id: raw

        anchors.fill: parent
        implicitSize: glyph.size
        source: glyph.source
        visible: false
    }

    // white, then the color
    MultiEffect {
        id: shape

        anchors.fill: raw
        source: raw
        brightness: 1
        colorization: 1
        colorizationColor: glyph.color
    }

    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: shape
            property: "scale"
            from: 0.5
            to: 1
            duration: Theme.slow
            easing.type: Easing.OutBack
            easing.overshoot: 2.5
        }
        NumberAnimation {
            target: shape
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.fade
        }
    }

    SequentialAnimation {
        id: rock

        PropertyAction {
            target: shape
            property: "transformOrigin"
            value: Item.Top
        }
        NumberAnimation {
            target: shape
            property: "rotation"
            to: 16
            duration: 80
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: shape
            property: "rotation"
            to: -12
            duration: 140
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: shape
            property: "rotation"
            to: 7
            duration: 130
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: shape
            property: "rotation"
            to: -3
            duration: 120
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: shape
            property: "rotation"
            to: 0
            duration: 110
            easing.type: Easing.OutQuad
        }
    }
}
