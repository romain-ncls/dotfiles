// Colors, sizes and fonts: plain placeholders until lumar writes them
// (docs/hyprland.md, phase 4).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property color bar: Qt.rgba(0.086, 0.09, 0.106, 0.92)
    readonly property color text: "#dcdee4"
    readonly property color dim: "#8a8f9c"
    readonly property color accent: "#61afef"
    readonly property color slot: "#3c404a"
    readonly property color warn: "#e06c75"
    readonly property string font: "Noto Sans"
    readonly property int barHeight: 40
    readonly property int icon: 18
}
