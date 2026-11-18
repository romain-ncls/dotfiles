// An item of the bar: an icon, maybe a label and a count. A click opens its
// popup (or closes it); a middle click and the wheel are the item's.
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: button

    required property var bar
    required property string popup
    property string icon: ""
    // or a picture of ours (icons/), and its color
    property string iconSource: ""
    property color iconColor: Theme.text
    property string label: ""
    property color labelColor: Theme.text
    property int badge: 0
    // more of the item's own after the label (Claude's meters)
    property alias extra: extra.sourceComponent

    signal middleClicked
    signal scrolled(int delta)

    implicitWidth: row.implicitWidth + 14
    implicitHeight: Theme.barHeight - 8

    Rectangle {
        anchors.fill: parent
        radius: Theme.corner
        color: area.pressed ? Theme.pressed : button.bar.open === button.popup ? Theme.selected : area.containsMouse ? Theme.hover : Theme.none
        Fade on color {}
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            icon: button.icon
            source: button.iconSource !== "" ? button.iconSource : button.icon !== "" ? Quickshell.iconPath(button.icon, "image-missing") : ""
            color: button.iconColor
        }

        Text {
            visible: button.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: button.label
            color: button.labelColor
            font.family: Theme.font
            font.pixelSize: Theme.body
        }

        Loader {
            id: extra

            anchors.verticalCenter: parent.verticalCenter
            active: sourceComponent !== null
            visible: active
        }
    }

    // one more: the count pops, a little bigger, then settles
    property int counted: 0
    onBadgeChanged: {
        if (badge > counted)
            pop.restart()
        counted = badge
    }

    Rectangle {
        id: badgeBox

        visible: button.badge > 0
        anchors.right: parent.right
        anchors.top: parent.top
        width: Math.max(16, count.implicitWidth + 8)
        height: 16
        radius: height / 2
        color: Theme.accent

        SequentialAnimation {
            id: pop

            Ease {
                target: badgeBox
                property: "scale"
                to: 1.25
                duration: Theme.fast / 2
            }
            Ease {
                target: badgeBox
                property: "scale"
                to: 1
                duration: Theme.normal
                easing.bezierCurve: Theme.move
            }
        }

        Text {
            id: count

            anchors.centerIn: parent
            text: button.badge
            color: Theme.accentText
            font.family: Theme.font
            font.pixelSize: Theme.small
            font.weight: Font.Bold
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                button.middleClicked()
            else
                button.bar.open = button.bar.open === button.popup ? "" : button.popup
        }
        onWheel: event => button.scrolled(event.angleDelta.y)
    }
}
