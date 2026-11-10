// A row of a popup's list: an icon, a title and a line under it, a word on
// the right; the title lit when it's the active one. A click does it; with
// `removable`, a cross on hover removes it; `marked`, a dot before the word
// (new).
import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: row

    property string icon: ""
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property int subtitleLines: 1
    property string trailing: ""
    property bool active: false
    property bool dim: false
    property bool marked: false
    property bool removable: false

    signal clicked
    signal removed

    readonly property string source: iconSource !== "" ? iconSource : icon !== "" ? Quickshell.iconPath(icon, "image-missing") : ""

    width: parent ? parent.width : 320
    height: Math.max(36, texts.implicitHeight + 14)
    radius: 8
    color: area.containsMouse ? Theme.slot : "transparent"

    IconImage {
        id: glyph

        visible: row.source !== ""
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: 22
        source: row.source
    }

    Column {
        id: texts

        x: glyph.visible ? 40 : 10
        anchors.verticalCenter: parent.verticalCenter
        width: row.width - x - right.width - 18
        spacing: 1

        Text {
            width: parent.width
            text: row.title
            elide: Text.ElideRight
            color: row.active ? Theme.accent : row.dim ? Theme.dim : Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: row.active ? Font.DemiBold : Font.Normal
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
            font.pixelSize: 11
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
        width: Math.max(word.implicitWidth, row.removable ? 16 : 0)
        height: 20

        Rectangle {
            visible: row.marked && word.visible
            anchors.right: word.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: Theme.accent
        }

        Text {
            id: word

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !(row.removable && (area.containsMouse || cross.containsMouse))
            text: row.trailing
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: row.removable && (area.containsMouse || cross.containsMouse)
            text: "✕"
            color: cross.containsMouse ? Theme.text : Theme.dim
            font.pixelSize: 12

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
