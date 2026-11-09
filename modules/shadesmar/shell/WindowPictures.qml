// The last picture of every window, for the overview's columns beside the
// screen: Hyprland copies a window only while it overlaps its screen, and
// the scrolling layout keeps columns beside it. Each time the focus moves
// to a window (before the tape scrolls a column out), the windows on their
// screens are taken again, where Hyprland last placed them; none beside
// it, whose request would wait until it's back, and Hyprland draws a copy
// of the whole screen at every frame while one waits. A window has none
// until it has been on its screen once. Two buffers of its size each
// (16 MB for 1920×1080), in no window: the overview lends them to its
// thumbnails (Thumbnail.qml), and takes none of its own meanwhile.
import QtQml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: pictures

    // the overview's up: its own pictures are fresher
    property bool paused: false

    // the picture of a window (Hyprland's toplevel), or null
    function of(toplevel) {
        for (let i = 0; i < all.count; i++) {
            const p = all.objectAt(i)
            if (p && p.toplevel === toplevel)
                return p
        }
        return null
    }

    // on its screen, as Hyprland last placed it (Hyprland.refreshToplevels)
    function onScreen(t) {
        const o = t.lastIpcObject
        if (!o || !o.at || !o.size || o.hidden)
            return false
        const m = Hyprland.monitors.values.find(m => m.id === o.monitor)
        if (!m || m.scale <= 0)
            return false
        const w = m.width / m.scale
        const h = m.height / m.scale
        return o.at[0] < m.x + w && o.at[0] + o.size[0] > m.x && o.at[1] < m.y + h && o.at[1] + o.size[1] > m.y
    }

    function take() {
        for (let i = 0; i < all.count; i++) {
            const p = all.objectAt(i)
            if (!p || !p.toplevel.wayland || !onScreen(p.toplevel))
                continue
            if (p.taken)
                p.captureFrame()
            else
                p.taken = true // its first: when the capture starts
        }
    }

    Instantiator {
        id: all

        model: Hyprland.toplevels

        ScreencopyView {
            required property var modelData
            readonly property var toplevel: modelData
            property bool taken: false

            // at the window's size, drawn only through a thumbnail's
            // mipmapped copy
            width: Math.max(1, sourceSize.width)
            height: Math.max(1, sourceSize.height)
            captureSource: taken ? modelData.wayland : null
            live: false
        }
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            if (pictures.paused || !Hyprland.activeToplevel)
                return
            pictures.take()
            // where they are now, for the next time
            Hyprland.refreshMonitors()
            Hyprland.refreshToplevels()
        }
    }

    Component.onCompleted: {
        Hyprland.refreshMonitors()
        Hyprland.refreshToplevels()
    }
}
