// The overview (Plasma's, on Meta+Tab and Ctrl+Alt+Tab): on every screen,
// the windows of the workspace it shows (the scrolling layout's columns
// beside the screen, and the scratchpad when it's out, included) as live
// thumbnails in their order. As Plasma's, they come from their places into
// the grid, and go back to them when it closes; the one picked goes to
// where it will be, as the tape scrolls to it. A click or Enter goes to one,
// the arrows move between them, typing filters them by title or app on
// every screen (the others fade, the grid closes up); Escape, a click
// beside them or the key again closes it.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: overview

    // under the thumbnails while they move, in place of the windows
    required property url wallpaper

    // shown: open to keys and clicks. up: its windows are there, from the
    // open to the end of the way back. revealed: the thumbnails cover the
    // windows (once they have their pictures). progress: 0, the thumbnails
    // in the windows' places; 1, in the grid.
    property bool shown: false
    property bool up: false
    property bool revealed: false
    property real progress: 0
    readonly property bool settled: shown && progress === 1
    property string filter: ""

    // Hyprland's curve for windows (looknfeel.lua: easeOutQuint), quicker
    readonly property int duration: 300
    readonly property var curve: [0.23, 1, 0.32, 1, 1, 1]

    // Where the windows are and what each screen shows, from hyprctl at the
    // open (Quickshell's own copies lag: it follows only the focused
    // screen's switches), and the windows' again after a pick: where they
    // will be (Hyprland gives the goals of its animations).
    property var monitors: []
    property var clients: []
    property int waiting: 0
    property bool opening: false
    signal snapshot

    function open() {
        if (shown)
            return
        filter = ""
        shown = true
        back.stop()
        focusing.stop()
        picked = null
        // again before it had closed: from where they are
        if (revealed) {
            forth.start()
            return
        }
        up = true
        fetch(true)
    }
    function close() {
        if (!shown)
            return
        shown = false
        forth.stop()
        if (revealed) {
            refreshAll()
            back.start()
        } else {
            down()
        }
    }
    function toggle() {
        if (shown)
            close()
        else
            open()
    }
    // The window picked, focused once the overview has let the keyboard
    // go: Hyprland focuses no window while a layer holds it, and the
    // overview lets it go with its next frame. So it asks again until
    // Hyprland says the window is active (300 ms at most), then goes back
    // to where the windows will be.
    property var picked: null

    function go(toplevel) {
        if (!shown)
            return
        shown = false
        forth.stop()
        picked = toplevel
        focusing.restart()
    }
    function down() {
        focusing.stop()
        picked = null
        ready.stop()
        late.stop()
        back.stop()
        up = false
        revealed = false
        progress = 0
    }

    function fetch(all) {
        opening = all
        waiting = all ? 2 : 1
        late.restart()
        if (all)
            monitorsJson.running = true
        clientsJson.running = true
    }
    function landed() {
        if (--waiting > 0)
            return
        late.stop()
        if (opening) {
            if (!up)
                return
            snapshot()
            ready.start()
        } else if (!shown) {
            refreshAll()
            back.start()
        }
    }
    function refreshAll() {
        views.instances.forEach(v => v.refresh())
    }
    function parse(text) {
        try {
            return JSON.parse(text)
        } catch (e) {
            return []
        }
    }

    Process {
        id: monitorsJson

        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                overview.monitors = overview.parse(text)
                overview.landed()
            }
        }
    }
    Process {
        id: clientsJson

        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                overview.clients = overview.parse(text)
                overview.landed()
            }
        }
    }

    Timer {
        id: focusing

        property int tries: 0

        interval: 30
        repeat: true
        onRunningChanged: tries = 0
        onTriggered: {
            const t = overview.picked
            if (t && t.wayland && !t.activated && ++tries <= 10) {
                t.wayland.activate()
                return
            }
            stop()
            overview.picked = null
            if (overview.revealed)
                overview.fetch(false)
            else
                overview.down()
        }
    }

    // hyprctl didn't answer: closed, or back from where they were
    Timer {
        id: late

        interval: 500
        onTriggered: {
            if (overview.opening)
                overview.down()
            else if (!overview.shown)
                back.start()
        }
    }

    // The thumbnails show once the windows on the screens have their
    // pictures (a few frames), so that they cover them exactly; 320 ms at
    // most.
    Timer {
        id: ready

        property int tries: 0

        interval: 16
        repeat: true
        onRunningChanged: tries = 0
        onTriggered: {
            if (++tries < 20 && !views.instances.every(v => v.ready()))
                return
            stop()
            overview.revealed = true
            if (overview.shown)
                forth.start()
            else
                overview.down()
        }
    }

    NumberAnimation {
        id: forth

        target: overview
        property: "progress"
        to: 1
        duration: overview.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: overview.curve
    }
    NumberAnimation {
        id: back

        target: overview
        property: "progress"
        to: 0
        duration: overview.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: overview.curve
        onFinished: overview.down()
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "overview"
        description: "The windows of every screen"
        onPressed: overview.toggle()
    }

    // qs -c shadesmar ipc call overview toggle
    IpcHandler {
        target: "overview"

        function toggle(): void {
            overview.toggle()
        }
    }

    Variants {
        id: views

        model: Quickshell.screens

        PanelWindow {
            id: view

            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool focusedScreen: monitor !== null && monitor.focused
            // hyprctl's
            readonly property var mon: overview.monitors.find(m => m.name === modelData.name) ?? null
            // the bar's strip: left, top, right, bottom
            readonly property var reserved: mon && mon.reserved ? mon.reserved : [0, 0, 0, 0]

            // The windows it shows, left to right as the tape has them, at
            // the open; those the filter keeps (their indexes); the one
            // picked among those.
            property var entries: []
            readonly property var picks: {
                const f = overview.filter.toLowerCase()
                const alive = Hyprland.toplevels.values
                const out = []
                entries.forEach((e, i) => {
                    if (alive.includes(e.toplevel) && (f === "" || `${e.toplevel.title} ${e.cls}`.toLowerCase().includes(f)))
                        out.push(i)
                })
                return out
            }
            property int selected: 0

            // the pictures again (not live: see Thumbnail.qml)
            function refresh() {
                for (let i = 0; i < cells.count; i++) {
                    const c = cells.itemAt(i)
                    if (c)
                        c.refresh()
                }
            }

            // in the grid, the pictures follow the windows, 20 times a second
            Timer {
                interval: 50
                repeat: true
                running: overview.settled
                onTriggered: view.refresh()
            }

            function ready() {
                if (paper.status === Image.Loading)
                    return false
                for (let i = 0; i < cells.count; i++) {
                    const c = cells.itemAt(i)
                    if (c && !c.ready)
                        return false
                }
                return true
            }

            readonly property int gap: 32
            readonly property int titleHeight: 28
            readonly property rect area: Qt.rect(64, 84, width - 128, height - 148)
            readonly property var sizes: picks.map(i => entries[i].first.size)
            // The columns that give the biggest thumbnails.
            readonly property int cols: {
                const n = sizes.length
                if (n === 0)
                    return 1
                const w = Math.max(...sizes.map(s => s[0]))
                const h = Math.max(...sizes.map(s => s[1]))
                let best = 1, bestScale = 0
                for (let c = 1; c <= n; c++) {
                    const r = Math.ceil(n / c)
                    const s = Math.min((area.width - (c - 1) * gap) / c / w, ((area.height - (r - 1) * gap) / r - titleHeight) / h)
                    if (s > bestScale) {
                        best = c
                        bestScale = s
                    }
                }
                return best
            }
            // Each one's picture in the grid, in the order picked: fitted in
            // its cell, above its title; the last row centred.
            readonly property var targets: {
                const n = sizes.length
                const rows = Math.max(1, Math.ceil(n / cols))
                const cw = (area.width - (cols - 1) * gap) / cols
                const ch = (area.height - (rows - 1) * gap) / rows
                return sizes.map((s, k) => {
                    const row = Math.floor(k / cols)
                    const col = k % cols
                    const inRow = Math.min(cols, n - row * cols)
                    const scale = Math.min(cw / s[0], (ch - titleHeight) / s[1], 1)
                    const x = area.x + ((cols - inRow) / 2 + col) * (cw + gap)
                    const y = area.y + row * (ch + gap)
                    return {
                        x: Math.round(x + (cw - s[0] * scale) / 2),
                        y: Math.round(y + (ch - titleHeight - s[1] * scale) / 2),
                        w: Math.round(s[0] * scale),
                        h: Math.round(s[1] * scale)
                    }
                })
            }

            screen: modelData
            visible: overview.up
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shadesmar-overview"
            WlrLayershell.keyboardFocus: overview.shown && focusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // on the way back, clicks and keys go to the windows already
            mask: overview.shown ? null : through

            Region {
                id: through
            }

            Connections {
                target: overview

                // the windows of the workspace it shows, the scratchpad's
                // when it's out, the pinned ones; the active window picked
                // first, as Plasma's
                function onSnapshot() {
                    const m = view.mon
                    if (!m) {
                        view.entries = []
                        return
                    }
                    const ws = m.activeWorkspace ? m.activeWorkspace.name : ""
                    const special = m.specialWorkspace ? m.specialWorkspace.name : ""
                    const shows = c => c.pinned || (c.workspace && (c.workspace.name === ws || (special !== "" && c.workspace.name === special)))
                    view.entries = overview.clients.filter(c => c.mapped && !c.hidden && c.monitor === m.id && c.size && shows(c)).sort((a, b) => a.at[0] - b.at[0] || a.at[1] - b.at[1]).map(c => ({
                                address: c.address,
                                cls: c["class"] || "",
                                first: c,
                                toplevel: Hyprland.toplevels.values.find(t => "0x" + t.address === c.address) ?? null
                            })).filter(e => e.toplevel !== null)
                    const active = view.entries.findIndex(e => e.toplevel === Hyprland.activeToplevel)
                    view.selected = Math.max(0, view.picks.indexOf(active))
                }
                function onFilterChanged() {
                    view.selected = 0
                }
                function onUpChanged() {
                    if (!overview.up)
                        view.entries = []
                }
            }

            // The wallpaper again, under the shade: while the thumbnails
            // leave the windows' places, the windows themselves don't show.
            // Not over the bar's strip (Hyprland's reserved area), which
            // keeps the bar.
            Item {
                visible: overview.revealed
                width: parent.width
                height: parent.height - view.reserved[3]
                clip: true

                Rectangle {
                    width: view.width
                    height: view.height
                    color: Theme.frameColor
                }
                Image {
                    id: paper

                    width: view.width
                    height: view.height
                    source: overview.up ? overview.wallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    // as Wallpaper.qml's: the same decoded picture
                    sourceSize: Qt.size(width, height)
                    asynchronous: true
                    smooth: true
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.shade
                opacity: overview.progress
            }

            MouseArea {
                anchors.fill: parent
                enabled: overview.shown
                onClicked: overview.close()
            }

            // The thumbnails above the bar's strip, as Hyprland draws the
            // windows (their shadows under the bar).
            Item {
                x: view.reserved[0]
                y: view.reserved[1]
                width: view.width - view.reserved[0] - view.reserved[2]
                height: view.height - view.reserved[1] - view.reserved[3]
                clip: true

                Item {
                    x: -parent.x
                    y: -parent.y

                    Repeater {
                        id: cells

                        model: view.entries

                        Item {
                            id: cell

                            required property var modelData
                            required property int index
                            // hyprctl's latest: after a pick, where it will be
                            readonly property var client: overview.clients.find(c => c.address === modelData.address) ?? modelData.first
                            readonly property int slot: view.picks.indexOf(index)
                            readonly property real p: overview.progress

                            // its place on the screen
                            readonly property real hx: client.at[0] - (view.mon ? view.mon.x : 0)
                            readonly property real hy: client.at[1] - (view.mon ? view.mon.y : 0)
                            readonly property real hw: client.size[0]
                            readonly property real hh: client.size[1]
                            readonly property real homeRadius: client.fullscreen ? 0 : client.floating || Theme.floating ? 10 : 0
                            // its picture on the screen first (columns beside it
                            // have none)
                            readonly property bool ready: hx >= view.width || hx + hw <= 0 || hy >= view.height || hy + hh <= 0 || thumb.hasContent

                            // its place in the grid, kept while the filter hides it
                            property real gx: 0
                            property real gy: 0
                            property real gw: hw
                            property real gh: hh
                            readonly property var target: slot >= 0 ? view.targets[slot] ?? null : null
                            function refresh() {
                                thumb.refresh()
                            }
                            function place() {
                                if (!target)
                                    return
                                gx = target.x
                                gy = target.y
                                gw = target.w
                                gh = target.h
                            }
                            onTargetChanged: place()
                            Component.onCompleted: place()

                            // kept by the filter: the others fade
                            property real kept: slot >= 0 ? 1 : 0

                            Behavior on gx {
                                enabled: overview.settled
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on gy {
                                enabled: overview.settled
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on gw {
                                enabled: overview.settled
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on gh {
                                enabled: overview.settled
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on kept {
                                enabled: overview.settled
                                NumberAnimation {
                                    duration: 200
                                }
                            }

                            // as Hyprland stacks them: the tiled ones, then the
                            // floating ones, in its list's order
                            z: (client.floating ? 2000 : 1000) + overview.clients.indexOf(client)
                            visible: overview.revealed && Hyprland.toplevels.values.includes(modelData.toplevel)

                            Thumbnail {
                                id: thumb

                                x: cell.hx + (cell.gx - cell.hx) * cell.p
                                y: cell.hy + (cell.gy - cell.hy) * cell.p
                                width: cell.hw + (cell.gw - cell.hw) * cell.p
                                height: cell.hh + (cell.gh - cell.hh) * cell.p
                                toplevel: cell.modelData.toplevel
                                appClass: cell.modelData.cls
                                capturing: overview.up
                                radius: cell.homeRadius + (7 - cell.homeRadius) * cell.p
                                lit: overview.shown && cell.slot >= 0 && ((view.focusedScreen && view.selected === cell.slot) || hover.containsMouse)
                                framed: cell.p
                                shadow: cell.client.fullscreen ? 0 : 1 - cell.p
                                opacity: 1 - cell.p * (1 - cell.kept)

                                MouseArea {
                                    id: hover

                                    anchors.fill: parent
                                    enabled: overview.shown && cell.slot >= 0
                                    hoverEnabled: true
                                    // on a move only: a pointer resting where the
                                    // overview opens doesn't pick for the keyboard
                                    onPositionChanged: view.selected = cell.slot
                                    onClicked: overview.go(cell.modelData.toplevel)
                                }
                            }

                            Text {
                                // under its picture, wherever it is; once it has
                                // nearly arrived
                                x: thumb.x + (thumb.width - width) / 2
                                y: thumb.y + thumb.height + 9
                                width: Math.min(implicitWidth, thumb.width)
                                opacity: Math.max(0, (cell.p - 0.6) / 0.4) * cell.kept
                                text: cell.modelData.toplevel.title
                                elide: Text.ElideRight
                                color: cell.slot >= 0 && view.focusedScreen && view.selected === cell.slot ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }

            // The filter, on the focused screen.
            Rectangle {
                z: 3000
                visible: view.focusedScreen
                opacity: overview.progress
                anchors.horizontalCenter: parent.horizontalCenter
                y: 24
                width: 360
                height: 36
                radius: 18
                color: Theme.bar

                Text {
                    anchors.centerIn: parent
                    text: overview.filter === "" ? "Type to filter" : overview.filter
                    color: overview.filter === "" ? Theme.dim : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                }
            }

            Item {
                focus: true

                Keys.onPressed: event => {
                    const n = view.picks.length
                    switch (event.key) {
                    case Qt.Key_Escape:
                        overview.close()
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (n > 0)
                            overview.go(view.entries[view.picks[view.selected]].toplevel)
                        break
                    case Qt.Key_Left:
                        if (n > 0)
                            view.selected = (view.selected + n - 1) % n
                        break
                    case Qt.Key_Right:
                    case Qt.Key_Tab:
                        if (n > 0)
                            view.selected = (view.selected + 1) % n
                        break
                    case Qt.Key_Up:
                        view.selected = Math.max(0, view.selected - view.cols)
                        break
                    case Qt.Key_Down:
                        view.selected = Math.min(n - 1, view.selected + view.cols)
                        break
                    case Qt.Key_Backspace:
                        overview.filter = overview.filter.slice(0, -1)
                        break
                    default:
                        if (event.text.length !== 1 || event.text < " ")
                            return
                        overview.filter += event.text
                    }
                    event.accepted = true
                }
            }
        }
    }
}
