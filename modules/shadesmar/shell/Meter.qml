// How much of a limit is spent (`value`, 0 to 1), red from `high`; a tick
// where an even pace would be (`pace`: the share of its window gone, none
// below 0), so a fill past the tick is ahead of it.
import QtQuick

Item {
    id: meter

    property real value: 0
    property real pace: -1
    property real high: 0.9
    // the fill, following the value
    property real drawn: value
    Behavior on drawn {
        enabled: Theme.speed > 0
        Follow {}
    }

    implicitHeight: 6

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.slot

        Rectangle {
            // a little is still seen
            width: meter.drawn > 0.001 ? Math.max(height, parent.width * Math.min(1, meter.drawn)) : 0
            height: parent.height
            radius: parent.radius
            color: meter.value >= meter.high ? Theme.warn : Theme.accent
        }
    }

    Rectangle {
        visible: meter.pace >= 0
        x: Math.round((meter.width - width) * Math.min(1, meter.pace))
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: parent.height + 6
        radius: 1
        color: Theme.text
    }
}
