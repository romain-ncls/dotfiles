// While the screen is recorded (Recorder.qml): a red dot and the time in
// the bar; a click stops.
import QtQuick

Item {
    id: dot

    required property var recorder

    visible: recorder.busy
    implicitWidth: row.implicitWidth + 14
    implicitHeight: Theme.barHeight - 8

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: area.containsMouse ? Theme.slot : "transparent"
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 7

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: Theme.warn
            opacity: dot.recorder.state === "stopping" ? 0.4 : 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.floor(dot.recorder.seconds / 60)}:${String(dot.recorder.seconds % 60).padStart(2, "0")}`
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            font.features: {
                "tnum": 1
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: dot.recorder.stop()
    }
}
