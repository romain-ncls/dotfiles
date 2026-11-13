// An icon in one color: a theme icon's name (`icon`) or a picture
// (`source`), its shape in `color` (the text's by default).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

Item {
    id: glyph

    property string icon: ""
    property string source: icon !== "" ? Quickshell.iconPath(icon, "image-missing") : ""
    property color color: Theme.text
    property int size: Theme.icon

    implicitWidth: size
    implicitHeight: size

    IconImage {
        id: raw

        anchors.fill: parent
        implicitSize: glyph.size
        source: glyph.source
        visible: false
    }

    // white, then the color
    MultiEffect {
        anchors.fill: raw
        source: raw
        brightness: 1
        colorization: 1
        colorizationColor: glyph.color
    }
}
