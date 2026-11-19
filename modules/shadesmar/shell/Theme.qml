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
    readonly property color paneColor: palette.pane
    readonly property color baseColor: palette.base
    readonly property color textColor: palette.text

    // The rules every part of the shell follows (docs/hyprland.md, "The
    // shell's rules"): Apple's, GNOME's and Windows' guidelines, Linear's
    // motion.

    // Glass: one material, the base (the bar's, the new tab's islands',
    // Ghostty's), blurred behind (Hyprland), thicker where there's reading:
    // the bar and the OSD, glanced at; popups, toasts, the launcher, the
    // year, pickers, read. Their edge: a 10 % line in the text's color.
    readonly property color glance: alpha(baseColor, 0.83)
    readonly property color reading: alpha(baseColor, 0.90)
    readonly property color outline: alpha(textColor, 0.10)
    readonly property color shade: alpha(frameColor, 0.88) // behind the overview

    readonly property color text: palette.text
    readonly property color dim: palette.text2
    readonly property color accent: palette.accentText // marks, fills, sliders
    readonly property color accentText: palette.frame // text on the accent
    readonly property color slot: palette.overlay // tracks, fields, switches off, empty desktops
    readonly property color warn: palette.red // never alone: with a word or an icon

    // States: the text's color over whatever is under, so on any glass
    readonly property color hover: alpha(textColor, 0.08)
    readonly property color selected: alpha(textColor, 0.12) // open, picked
    readonly property color pressed: alpha(textColor, 0.16)
    readonly property color none: alpha(textColor, 0) // no state, for Fade.qml
    // a button's face (Cancel, a tile), and under the pointer; the main
    // one is the accent, lighter under the pointer
    readonly property color face: alpha(textColor, 0.10)
    readonly property color faceHover: alpha(textColor, 0.16)

    // Type: five sizes, macOS's (caption, body, title), in Regular, Medium
    // (titles, what's on; Noto Sans has no SemiBold: DemiBold is Medium)
    // and Bold for a count or today. Its digits are all as wide.
    readonly property string font: "Noto Sans"
    readonly property int small: 11 // captions, section names, second lines
    readonly property int body: 13 // the bar, rows, buttons
    readonly property int title: 15 // popups' and views' titles
    readonly property int large: 22 // big numbers, the launcher's field
    readonly property int display: 40 // the clock popup's time

    // Space: a 4 px grid (2, 4, 6, 8, 12, 16, 24). A surface's padding, and
    // its rows: one line, two (or a switch).
    readonly property int pad: 12
    readonly property int row: 32
    readonly property int row2: 40

    // Corners, concentric: a surface's is its rows' and its padding's. A
    // capsule (height / 2) for switches, sliders, badges.
    readonly property int corner: 8 // controls, rows, the bar's items
    readonly property int surfaceCorner: corner + pad // popups, toasts, menus
    readonly property int overlayCorner: 24 // the launcher, the year, pickers

    // Motion (Ease.qml, Fade.qml, Follow.qml, Squish.qml, Stretch.qml,
    // Digits.qml): quick, from where it comes, never on what's done by the
    // keys or a hundred times a day; a click always answered (a press
    // sinks, what changed pops, rolls or slides). Glass is faded by
    // Hyprland only, whole surfaces (looknfeel.lua): the shell moves and
    // grows; faded by it, the blur would stay whole under the fading glass.
    // Three lengths: a hover going, an exit, a small change; a popup, a
    // toast, a move; a big view. `speed` scales them all: 0, no motion at
    // all.
    readonly property real speed: 1
    readonly property int fast: 150 * speed
    readonly property int normal: 200 * speed
    readonly property int slow: 300 * speed
    // a press going in (Squish.qml): quicker than a click
    readonly property int press: 100 * speed
    // how far a press sinks a thing: 2 px a side, so the small ones more
    // (a chevron to 0.9, a row to 0.99)
    function sunk(size) {
        return 1 - 4 / Math.max(40, size)
    }
    // ease-out, strong (Hyprland's easeOutQuint): what comes, the default
    readonly property var out: [0.23, 1, 0.32, 1, 1, 1]
    // Material's standard: what moves from one place to another
    readonly property var move: [0.2, 0, 0, 1, 1, 1]
    // ease-out-quad (Linear's): what fades
    readonly property var fade: [0.25, 0.46, 0.45, 0.94, 1, 1]

    readonly property int barHeight: 40
    readonly property int icon: 18
}
