// A motion of the shell (Theme.qml's rules): quick, eased out unless told.
import QtQuick

NumberAnimation {
    duration: Theme.normal
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.out
}
