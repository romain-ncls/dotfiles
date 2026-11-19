// While the screen is recorded (Recorder.qml): a red dot and the time in
// the bar; a click stops.
import QtQuick

BarItem {
    id: dot

    required property var recorder

    visible: recorder.busy
    implicitWidth: row.implicitWidth + 14
    onClicked: dot.recorder.stop()

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: height / 2
            color: Theme.warn
            opacity: dot.recorder.state === "stopping" ? 0.4 : 1
        }

        Digits {
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.floor(dot.recorder.seconds / 60)}:${String(dot.recorder.seconds % 60).padStart(2, "0")}`
        }
    }
}
