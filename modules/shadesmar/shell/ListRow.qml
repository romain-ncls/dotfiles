// A row of a popup's list: an icon (or a picture, `thumbnail`), a title and
// a line under it, a word on the right; the title lit when it's the active
// one, the row when it's the one the keys are on (`selected`); with `chip`,
// its icon in a circle (IconChip.qml), the circle lit instead. A click does
// it; with `removable`, a cross on hover removes it; `marked`, a dot before
// the word (new).
import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: row

    property string icon: ""
    property string iconSource: ""
    property string thumbnail: ""
    // a line icon of ours (icons/), in the text's color
    property string lineIcon: ""
    property string title: ""
    property string subtitle: ""
    property int subtitleLines: 1
    property string trailing: ""
    // a small icon on the right, after the word (a lock)
    property string trailingIcon: ""
    property bool active: false
    property bool selected: false
    property bool dim: false
    property bool marked: false
    property bool busy: false
    // its icon in a circle (IconChip.qml), lit while it's the active one;
    // its title then stays in the text's color
    property bool chip: false
    property bool removable: false
    // what the cross says instead (Forget)
    property string removeLabel: ""

    signal clicked
    signal removed

    readonly property string source: iconSource !== "" ? iconSource : icon !== "" ? Quickshell.iconPath(icon, "image-missing") : ""

    width: parent ? parent.width : 320
    height: Math.max(thumbnail !== "" ? 56 : chip || subtitle !== "" ? Theme.row2 : Theme.row, texts.implicitHeight + 6)
    radius: Theme.corner
    color: area.pressed ? Theme.pressed : selected ? Theme.selected : area.containsMouse ? Theme.hover : Theme.none
    Fade on color {}
    scale: area.pressed ? Theme.sunk(width) : 1
    Squish on scale {}

    IconImage {
        id: glyph

        visible: !row.chip && row.thumbnail === "" && row.lineIcon === "" && row.source !== ""
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: 22
        source: row.thumbnail === "" ? row.source : ""
    }

    Glyph {
        id: line

        visible: !row.chip && row.thumbnail === "" && row.lineIcon !== ""
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        size: 18
        source: row.lineIcon
        color: row.active ? Theme.accent : Theme.text
    }

    IconChip {
        id: chip

        visible: row.chip
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        icon: row.lineIcon !== "" ? "" : row.icon
        source: row.lineIcon !== "" ? row.lineIcon : row.iconSource
        lit: row.active
    }

    // a picture: in a 72 × 44 box, its whole
    Rectangle {
        id: picture

        visible: row.thumbnail !== ""
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        height: 44
        radius: 4
        color: Theme.slot
        border.width: 1
        border.color: Theme.outline

        Image {
            anchors.fill: parent
            anchors.margins: 1
            source: row.thumbnail
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: 144
            sourceSize.height: 88
        }
    }

    Column {
        id: texts

        x: picture.visible ? 88 : chip.visible ? 44 : glyph.visible || line.visible ? 40 : 10
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - x - right.width - 18
        spacing: 1

        Text {
            width: parent.width
            text: row.title
            elide: Text.ElideRight
            color: row.active && !row.chip ? Theme.accent : row.dim ? Theme.dim : Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.body
            font.weight: row.active ? Font.Medium : Font.Normal
        }

        Text {
            visible: row.subtitle !== ""
            width: parent.width
            text: row.subtitle
            wrapMode: Text.Wrap
            maximumLineCount: row.subtitleLines
            elide: Text.ElideRight
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.small
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: row.clicked()
    }

    // the word on the right, or the cross on hover
    Item {
        id: right

        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(word.implicitWidth + (side.visible ? side.width + (word.implicitWidth > 0 ? 6 : 0) : 0) + (spinner.visible ? spinner.width + 6 : 0), row.removable ? removal.implicitWidth : 0)
        height: 20

        Rectangle {
            visible: row.marked && word.visible
            anchors.right: word.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: height / 2
            color: Theme.accent
        }

        Spinner {
            id: spinner

            visible: row.busy && word.visible
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Glyph {
            id: side

            visible: row.trailingIcon !== "" && word.visible
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: 14
            source: row.trailingIcon
            color: Theme.dim
        }

        Text {
            id: word

            anchors.right: side.visible ? side.left : parent.right
            anchors.rightMargin: side.visible && text !== "" ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: !(row.removable && (area.containsMouse || cross.containsMouse))
            text: row.trailing
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.small
        }

        Text {
            id: removal

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: row.removable && (area.containsMouse || cross.containsMouse)
            text: row.removeLabel !== "" ? row.removeLabel : "✕"
            color: cross.containsMouse ? (row.removeLabel !== "" ? Theme.warn : Theme.text) : Theme.dim
            font.pixelSize: Theme.small
            font.family: Theme.font

            MouseArea {
                id: cross

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: row.removed()
            }
        }
    }
}
