// A press (Theme.qml's motion), as `Squish on scale {}` under
// `scale: area.pressed ? Theme.sunk(width) : 1`: it sinks at once, and
// comes back with a little spring, past its size and back, as Apple's
// buttons, so even a quick click is felt.
import QtQuick

Behavior {
    id: squish

    property real last: 1
    property bool down: false

    enabled: Theme.speed > 0
    // told before the animation starts (QQuickBehavior::write)
    onTargetValueChanged: {
        down = targetValue < last
        last = targetValue
    }

    NumberAnimation {
        duration: squish.down ? Theme.press : Theme.slow
        easing.type: squish.down ? Easing.BezierSpline : Easing.OutBack
        easing.bezierCurve: Theme.out
        easing.overshoot: 3
    }
}
