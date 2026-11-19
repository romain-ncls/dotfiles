// An edge of something going elsewhere (Desktops.qml's light), as
// `Stretch on left { leading: true }`, `Stretch on right {}`: the edge in
// front goes quicker than the one behind, so it stretches on the way, and
// catches up.
import QtQuick

Behavior {
    id: edge

    // the left (or top) edge, in front going left (up); the other, right
    property bool leading: false
    property bool front: false
    property real from: NaN

    enabled: Theme.speed > 0
    // told before the animation starts (QQuickBehavior::write)
    onTargetValueChanged: {
        front = leading ? targetValue < from : targetValue > from
        from = targetValue
    }

    NumberAnimation {
        duration: edge.front ? Theme.normal : Theme.slow + Theme.fast / 2
        easing.type: Easing.BezierSpline
        easing.bezierCurve: edge.front ? Theme.out : Theme.move
    }
}
