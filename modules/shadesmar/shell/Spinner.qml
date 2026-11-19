// Something under way (Connecting…, Pairing…): three quarters of a ring,
// going round.
import QtQuick
import QtQuick.Shapes

Shape {
    id: spinner

    property color color: Theme.dim
    property int size: 14

    implicitWidth: size
    implicitHeight: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: spinner.color
        strokeWidth: 2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            centerX: spinner.size / 2
            centerY: spinner.size / 2
            radiusX: spinner.size / 2 - 1
            radiusY: spinner.size / 2 - 1
            startAngle: 0
            sweepAngle: 270
        }
    }

    RotationAnimator on rotation {
        running: spinner.visible
        from: 0
        to: 360
        duration: 800
        loops: Animation.Infinite
    }
}
