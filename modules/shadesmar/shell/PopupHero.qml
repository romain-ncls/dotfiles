// A popup's head, as Omarchy's panels have it: what it's about, big (an
// icon, a name), a word under it in capitals (CONNECTED), red when
// something's wrong (`warn`); a switch on the right (`toggle`). Its icon
// changing (off, on) pops in.
import QtQuick
import Quickshell

Item {
    id: hero

    property string icon: ""
    property string iconSource: "" // or a picture of ours (icons/)
    property string title: ""
    property string caption: ""
    property bool warn: false
    property bool toggle: false
    property bool checked: false

    signal toggled

    width: parent ? parent.width : 320
    height: 50

    Glyph {
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        size: 30
        icon: hero.icon
        pops: true
        source: hero.iconSource !== "" ? hero.iconSource : hero.icon !== "" ? Quickshell.iconPath(hero.icon, "image-missing") : ""
        color: hero.warn ? Theme.warn : Theme.text
    }

    Column {
        x: 48
        width: parent.width - x - (toggle.visible ? toggle.width + 12 : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

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
            text: hero.caption.toUpperCase()
            elide: Text.ElideRight
            color: hero.warn ? Theme.warn : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.small
            font.weight: Font.Medium
            font.letterSpacing: 1
        }
    }

    Toggle {
        id: toggle

        visible: hero.toggle
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        checked: hero.checked
        onToggled: hero.toggled()
    }
}
