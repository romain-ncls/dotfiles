// A popup's head, as Control Center's modules: what it's about, its icon in
// a circle, lit in the accent while it's on (`lit`: connected, playing,
// popups shown), red when something's wrong (`warn`); its name, a line
// under it (Connected · 5 GHz); a switch on the right (`toggle`), and before
// it the buttons put inside it (Chevron.qml: Claude's reload, the Wi-Fi's
// QR code). Its icon changing (off, on) pops in.
import QtQuick
import Quickshell

Item {
    id: hero

    default property alias tools: tools.data
    property string icon: ""
    property string iconSource: "" // or a picture of ours (icons/)
    property string title: ""
    property string caption: ""
    property bool warn: false
    property bool toggle: false
    property bool checked: false
    property bool lit: toggle && checked

    signal toggled

    width: parent ? parent.width : 320
    height: 52

    IconChip {
        id: chip

        x: 6
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.headChip
        glyph: 22
        icon: hero.icon
        source: hero.iconSource
        lit: hero.lit
        warn: hero.warn
    }

    Column {
        x: chip.x + chip.width + 12
        width: (tools.width > 0 ? tools.x - 4 : toggle.visible ? toggle.x - 8 : parent.width - 8) - x
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: hero.title
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.title
            font.weight: Font.Medium
        }

        Text {
            visible: hero.caption !== ""
            width: parent.width
            text: hero.caption
            elide: Text.ElideRight
            color: hero.warn ? Theme.warn : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.small
        }
    }

    Toggle {
        id: toggle

        visible: hero.toggle
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        checked: hero.checked
        onToggled: hero.toggled()
    }

    Row {
        id: tools

        anchors.right: toggle.visible ? toggle.left : parent.right
        anchors.rightMargin: toggle.visible ? 8 : 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
    }
}
