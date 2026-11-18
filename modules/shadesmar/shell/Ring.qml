// A ring filled clockwise from the top as far as `value` (0 to 1): Claude's
// limits in the bar.
import QtQuick
import QtQuick.Shapes

Shape {
    id: ring

    property real value: 0
    property color color: Theme.accent
    // seen on the bar and on its items' hover alike (Theme.hover, under it)
    property color track: Theme.alpha(Theme.textColor, 0.18)
    property real thickness: 3
    property int size: 18

    readonly property real radius: (size - thickness) / 2
    // the arc, following the value
    property real drawn: value
    Behavior on drawn {
        enabled: Theme.speed > 0
        Follow {}
    }

    implicitWidth: size
    implicitHeight: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: ring.track
        strokeWidth: ring.thickness
        fillColor: "transparent"

        PathAngleArc {
            centerX: ring.size / 2
            centerY: ring.size / 2
            radiusX: ring.radius
            radiusY: ring.radius
            startAngle: 0
            sweepAngle: 360
        }
    }

    ShapePath {
        strokeColor: ring.drawn > 0.001 ? ring.color : "transparent"
        strokeWidth: ring.thickness
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            centerX: ring.size / 2
            centerY: ring.size / 2
            radiusX: ring.radius
            radiusY: ring.radius
            startAngle: -90
            // a little is still seen
            sweepAngle: Math.max(8, 360 * Math.min(1, ring.drawn))
        }
    }
}
