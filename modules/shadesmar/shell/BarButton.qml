// An item of the bar (BarItem.qml): an icon, maybe a label and a count. A
// click opens its popup (or closes it); a middle click and the wheel are
// the item's. A new icon pops in, the label's numbers roll (Digits.qml), a
// count going up pops and swings the icon (the bell).
import QtQuick
import Quickshell

BarItem {
    id: button

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
    open: bar.open === popup
    buttons: Qt.LeftButton | Qt.MiddleButton
    onClicked: event => {
        if (event.button === Qt.MiddleButton)
            button.middleClicked()
        else
            button.bar.open = button.bar.open === button.popup ? "" : button.popup
    }
    onWheeled: event => button.scrolled(event.angleDelta.y)

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Glyph {
            id: glyph

            anchors.verticalCenter: parent.verticalCenter
            icon: button.icon
            source: button.iconSource !== "" ? button.iconSource : button.icon !== "" ? Quickshell.iconPath(button.icon, "image-missing") : ""
            color: button.iconColor
            pops: true
        }

        Digits {
            visible: button.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: button.label
            color: button.labelColor
        }

        Loader {
            id: extra

            anchors.verticalCenter: parent.verticalCenter
            active: sourceComponent !== null
            visible: active
        }
    }

    property int counted: 0
    onBadgeChanged: {
        if (badge > counted) {
            pop.restart()
            glyph.swing()
        }
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
}
