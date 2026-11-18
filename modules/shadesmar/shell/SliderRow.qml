// A level: its icon (a click on it mutes), its slider, its value. `off`:
// muted, dimmed.
import QtQuick

Item {
    id: level

    property string icon: ""
    property real value: 0
    property bool off: false

    signal moved(real value)
    signal clicked

    width: parent ? parent.width : 320
    height: Theme.row

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: Theme.row
        radius: Theme.corner
        color: area.pressed ? Theme.pressed : area.containsMouse ? Theme.hover : Theme.none
        Fade on color {}

        Glyph {
            anchors.centerIn: parent
            icon: level.icon
            color: level.off ? Theme.dim : Theme.text
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: level.clicked()
        }
    }

    Slider {
        x: 46
        width: parent.width - x - 50
        anchors.verticalCenter: parent.verticalCenter
        value: level.value
        onMoved: v => level.moved(v)
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(level.value * 100) + "%"
        color: level.off ? Theme.dim : Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.body
        font.features: {
            "tnum": 1
        }
    }
}
