// lumar's colors and shapes (modules/lumar; docs/hyprland.md). The colors
// are the palette both sessions share, as apply-lumar writes it to
// ~/.local/share/lumar/palette.json, followed live (Nalthis's defaults
// until it's there); the layout, flush or floating, is lumar's mode file
// (Meta+G, modules/hyprland's lumar.lua).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme

    readonly property string home: Quickshell.env("HOME")

    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || theme.home + "/.local/share") + "/lumar/palette.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: palette

            property string frame: "#12161b"
            property string base: "#191d23"
            property string pane: "#21262d"
            property string raised: "#282e36"
            property string overlay: "#323942"
            property string text: "#e7ecf2"
            property string text2: "#a9b2be"
            property string text3: "#737b86"
            property string accent: "#2d78bd"
            property string accentText: "#73b6fa"
            property string red: "#e66e68"
        }
    }

    FileView {
        id: mode

        path: (Quickshell.env("XDG_STATE_HOME") || theme.home + "/.local/state") + "/lumar/mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // flush: the bar docked; floating: the bar too, with gaps and corners
    readonly property bool floating: mode.text().trim() === "floating"

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
    readonly property color frameColor: palette.frame
    readonly property color raisedColor: palette.raised

    // the bar and the notifications, see-through, blurred behind (Hyprland)
    readonly property color bar: alpha(frameColor, 0.92)
    readonly property color popup: alpha(raisedColor, 0.97) // the bar's popups
    readonly property color shade: alpha(frameColor, 0.88) // behind the overview
    readonly property color text: palette.text
    readonly property color dim: palette.text2
    readonly property color accent: palette.accentText // marks, fills, sliders
    readonly property color accentText: palette.frame // text on the accent
    readonly property color slot: palette.overlay // hover, tracks, empty desktops
    readonly property color warn: palette.red

    readonly property string font: "Noto Sans"
    readonly property int radius: 10
    readonly property int barHeight: 40
    readonly property int icon: 18
}
