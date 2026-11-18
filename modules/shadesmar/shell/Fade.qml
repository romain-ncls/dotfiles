// A state's color changing (Theme.qml's motion), as `Fade on color {}`:
// lighter at once, fading back over a moment (Linear's hovers: a hover
// comes at once, goes over 150 ms). Going from a color to `Theme.none`,
// the text's color unseen, it fades without darkening on the way.
import QtQuick

Behavior {
    id: fade

    property real last: 0
    property bool down: false

    // told before the animation starts (QQuickBehavior::write)
    onTargetValueChanged: {
        down = targetValue.a < last
        last = targetValue.a
    }

    ColorAnimation {
        duration: fade.down ? Theme.fast : 0
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.fade
    }
}
