// What may be longer than its room (a popup's list): past `maxHeight`, it
// scrolls, and says so (ScrollHint.qml).
import QtQuick

Item {
    id: scroller

    property real maxHeight: 320
    property alias color: hint.color
    property alias spacing: column.spacing
    default property alias content: column.data

    width: parent ? parent.width : 320
    height: Math.min(column.implicitHeight, maxHeight)

    Flickable {
        id: flick

        anchors.fill: parent
        contentHeight: column.implicitHeight
        interactive: hint.scrolls
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: flick.width
        }
    }

    ScrollHint {
        id: hint

        anchors.fill: parent
        target: flick
    }
}
