// A card above the bar, where the popup of the item it's about opens:
// what spanreed's agents ask (a Bluetooth pairing, a network's secrets).
// A window of its own, which takes the keyboard, as a request can come
// with no popup open. Its icon, title and line, what it holds, then its
// buttons: no, and yes when it has one (dimmed until it's ready). Escape or
// a click elsewhere is no.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: card

    required property var bar
    // the bar item it's about
    required property Item from
    property bool shown: false
    property string icon: ""
    property string title: ""
    property string message: ""
    property string no: "Cancel"
    property string yes: ""
    property bool ready: true
    // after the title, in its column
    default property alias content: body.data

    signal accepted
    signal dismissed

    // before it shows: centred on the item, in place of the bar's popup
    property real centre: 0
    function place() {
        centre = bar.margins.left + from.mapToItem(null, from.width / 2, 0).x
        bar.open = ""
    }

    screen: bar.screen
    visible: shown
    anchors {
        bottom: true
        right: true
    }
    margins {
        bottom: 6
        right: Math.max(card.bar.margins.right, (screen ? screen.width : 0) - card.centre - card.implicitWidth / 2)
    }
    exclusiveZone: 0
    implicitWidth: 360
    implicitHeight: body.implicitHeight + buttons.height + 3 * Theme.pad
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shadesmar-card"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // once shown, as BarPopup's
    HyprlandFocusGrab {
        windows: [card]
        active: card.backingWindowVisible
        onCleared: card.dismissed()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.surfaceCorner
        color: Theme.reading
        border.width: 1
        border.color: Theme.outline
    }

    // Escape, from its fields too
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: card.dismissed()

        Column {
            id: body

            x: Theme.pad
            y: Theme.pad
            width: parent.width - 2 * Theme.pad
            spacing: Theme.pad

            Item {
                width: parent.width
                height: Math.max(glyph.height, texts.implicitHeight)

                IconImage {
                    id: glyph

                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 22
                    source: Quickshell.iconPath(card.icon, "dialog-password-symbolic")
                }

                Column {
                    id: texts

                    x: 32
                    width: parent.width - x
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: card.title
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.body
                        font.weight: Font.Medium
                    }

                    Text {
                        width: parent.width
                        text: card.message
                        wrapMode: Text.Wrap
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.small
                    }
                }
            }
        }

        Row {
            id: buttons

            anchors.right: body.right
            y: body.y + body.height + Theme.pad
            spacing: 6

            CardButton {
                text: card.no
                onClicked: card.dismissed()
            }
            CardButton {
                visible: card.yes !== ""
                text: card.yes
                accent: true
                opacity: card.ready ? 1 : 0.5
                onClicked: {
                    if (card.ready)
                        card.accepted()
                }
            }
        }
    }

    component CardButton: Rectangle {
        id: button

        property string text
        property bool accent: false

        signal clicked

        width: Math.max(72, label.implicitWidth + 24)
        height: 28
        radius: Theme.corner
        color: accent ? (area.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent) : (area.containsMouse ? Theme.faceHover : Theme.face)

        Text {
            id: label

            anchors.centerIn: parent
            text: button.text
            color: button.accent ? Theme.accentText : Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.body
            font.weight: button.accent ? Font.Medium : Font.Normal
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: button.clicked()
        }
    }
}
