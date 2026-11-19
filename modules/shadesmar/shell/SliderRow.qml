// A level, a row of a plate (Section.qml): its icon in a chip, lit while
// it's on, a button (a click mutes); its slider; its value, rolling.
// `off`: muted, the chip unlit.
import QtQuick

Item {
    id: level

    property string icon: ""
    property real value: 0
    property bool off: false

    signal moved(real value)
    signal clicked

    width: parent ? parent.width : 320
    height: Theme.row2

    Item {
        id: button

        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.chip
        height: Theme.chip
        scale: area.pressed ? Theme.sunk(width) : 1
        Squish on scale {}

        IconChip {
            icon: level.icon
            lit: !level.off
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: area.pressed ? Theme.pressed : area.containsMouse ? Theme.hover : Theme.none
            Fade on color {}
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: level.clicked()
        }
    }

    Slider {
        x: button.x + button.width + 12
        width: parent.width - x - 54
        anchors.verticalCenter: parent.verticalCenter
        value: level.value
        onMoved: v => level.moved(v)
    }

    Digits {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(level.value * 100) + "%"
        color: level.off ? Theme.dim : Theme.text
    }
}
