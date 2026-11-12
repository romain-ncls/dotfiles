// The grid view (Plasma's, on Meta+W and four fingers pinched in): on each
// screen of the grid (modules/hyprland/hypr/grid.lua), its four desktops as
// hyprslide lays them, the plane zoomed out to fit: the desktop shown
// shrinks from the screen into its place while the others come in around
// it. Each desktop is the screen's rectangle: the wallpaper and the windows
// on it where they are (the tape's columns beside it stay out, as in a
// slide), in their last pictures (WindowPictures.qml), the shown one's
// taken again. A click on a desktop goes there, on a window to it; a window
// dragged onto another desktop moves there. The arrows pick a desktop,
// Enter goes; Escape, a click beside the desktops or the key again close,
// back into the one shown. The laptop's screen at the desk (comms) isn't
// part of the grid: it stays as it is.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: grid

    // under the desktops while they move, in place of the windows
    required property url wallpaper
    required property var pictures
    // one view at a time: either closes when the other opens
    required property var overview

    Connections {
        target: grid.overview

        function onShownChanged() {
            if (grid.overview.shown)
                grid.close()
        }
    }

    // shown: open to keys and clicks. up: its windows are there, from the
    // open to the end of the way back. revealed: the desktops cover the
    // screens (once the shown one has its pictures). progress: 0, the
    // desktop shown fills its screen; 1, the grid.
    property bool shown: false
    property bool up: false
    property bool revealed: false
    property real progress: 0
    readonly property bool settled: shown && progress === 1

    // the overview's duration and curve (Hyprland's easeOutQuint, quicker)
    readonly property int duration: 300
    readonly property var curve: [0.23, 1, 0.32, 1, 1, 1]

    // The desktop on the screens (at the open, then the one gone to: the
    // way back ends on it), the one picked by the keys or the pointer.
    property int current: 1
    property int selected: 1

    // What the screens show and where the windows are, from hyprctl at the
    // open (as the overview), the windows' again after a move or a pick.
    property var monitors: []
    property var clients: []
    property int waiting: 0
    property bool opening: false
    signal snapshot

    function open() {
        if (shown)
            return
        overview.close()
        shown = true
        back.stop()
        focusing.stop()
        going.stop()
        picked = null
        // again before it had closed: from where it is
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
        if (revealed)
            back.start()
        else
            down()
    }
    function toggle() {
        if (shown)
            close()
        else
            open()
    }
    function down() {
        focusing.stop()
        going.stop()
        ready.stop()
        late.stop()
        back.stop()
        picked = null
        dragged = null
        up = false
        revealed = false
        progress = 0
    }

    // Desktop d picked (and a window on it): the grid switches there at
    // once, under the view (grid.lua, no slide: the view zooms in instead),
    // the window is focused through Hyprland's dispatcher once the view has
    // let the keyboard go (it asks again until Hyprland says it's active,
    // 300 ms at most, as the overview), and the view goes back into it,
    // with its windows where they are then.
    property var picked: null

    function go(d, toplevel) {
        if (!shown)
            return
        shown = false
        forth.stop()
        selected = d
        current = d
        picked = toplevel ?? null
        Quickshell.execDetached(["hyprctl", "eval", `package.loaded["grid"].go(${d}, true)`])
        going.restart()
    }

    // grid.lua says it switched ("grid d"): the windows of the desktop gone
    // to are on the screens, to be focused and taken again.
    Connections {
        target: Hyprland
        enabled: going.running

        function onRawEvent(event) {
            if (event.name === "custom" && event.data === `grid ${grid.current}`) {
                going.stop()
                grid.arrived()
            }
        }
    }
    // already there, or grid.lua didn't answer
    Timer {
        id: going

        interval: 250
        onTriggered: grid.arrived()
    }
    function arrived() {
        if (picked)
            focusing.restart()
        else if (revealed)
            fetch(false)
        else
            down()
    }

    Timer {
        id: focusing

        property int tries: 0

        interval: 30
        repeat: true
        onRunningChanged: tries = 0
        onTriggered: {
            const t = grid.picked
            if (t && !t.activated && ++tries <= 10) {
                Hyprland.dispatch(`hl.dsp.focus({ window = 'address:0x${t.address}' })`)
                return
            }
            stop()
            grid.picked = null
            if (grid.revealed)
                grid.fetch(false)
            else
                grid.down()
        }
    }

    // A window dropped on another desktop moves there (and stays where it
    // is on the screens); the view shows where Hyprland put it.
    property var dragged: null

    function move(toplevel, workspace) {
        Hyprland.dispatch(`hl.dsp.window.move({ window = 'address:0x${toplevel.address}', workspace = '${workspace}', follow = false })`)
        moved.restart()
    }
    Timer {
        id: moved

        interval: 60
        onTriggered: {
            if (grid.shown)
                clientsJson.running = true
        }
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
            opening = false
            if (!up)
                return
            snapshot()
            ready.start()
        } else if (!shown && up) {
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
                grid.monitors = grid.parse(text)
                grid.landed()
            }
        }
    }
    Process {
        id: clientsJson

        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                grid.clients = grid.parse(text)
                if (grid.waiting > 0)
                    grid.landed()
            }
        }
    }

    // hyprctl didn't answer: closed, or back from where they were
    Timer {
        id: late

        interval: 500
        onTriggered: {
            if (grid.opening)
                grid.down()
            else if (!grid.shown)
                back.start()
        }
    }

    // The desktops show once the shown one's windows have their pictures
    // (a few frames), so that it covers the screen exactly; 320 ms at most.
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
            grid.revealed = true
            if (grid.shown)
                forth.start()
            else
                grid.down()
        }
    }

    NumberAnimation {
        id: forth

        target: grid
        property: "progress"
        to: 1
        duration: grid.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: grid.curve
    }
    NumberAnimation {
        id: back

        target: grid
        property: "progress"
        to: 0
        duration: grid.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: grid.curve
        onFinished: grid.down()
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "grid"
        description: "The desktops of the grid"
        onPressed: grid.toggle()
    }
    // the touchpad's pinch (in, out): one way each
    GlobalShortcut {
        appid: "shadesmar"
        name: "grid-in"
        description: "Open the grid view"
        onPressed: grid.open()
    }
    GlobalShortcut {
        appid: "shadesmar"
        name: "grid-out"
        description: "Close the grid view"
        onPressed: grid.close()
    }

    // qs -c shadesmar ipc call grid toggle
    IpcHandler {
        target: "grid"

        function toggle(): void {
            grid.toggle()
        }
    }

    Connections {
        target: grid

        // the desktop the grid screens show; none (the peek, comms on the
        // laptop alone): nothing to show
        function onSnapshot() {
            const m = grid.monitors.find(m => m.activeWorkspace && m.activeWorkspace.id >= 1 && m.activeWorkspace.id <= 8)
            if (!m) {
                grid.shown = false
                grid.down()
                return
            }
            grid.current = (m.activeWorkspace.id - 1) % 4 + 1
            grid.selected = grid.current
        }
    }

    Variants {
        id: views

        model: Quickshell.screens

        PanelWindow {
            id: view

            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            // hyprctl's
            readonly property var mon: grid.monitors.find(m => m.name === modelData.name) ?? null
            // the first of its desktops' workspaces less one: 0 on the left
            // screen (or the laptop alone), 4 on the right one; -1, not a
            // grid screen
            readonly property int base: {
                const id = mon && mon.activeWorkspace ? mon.activeWorkspace.id : 0
                return id >= 1 && id <= 8 ? Math.floor((id - 1) / 4) * 4 : -1
            }
            readonly property bool gridScreen: base >= 0
            // the keys: the focused screen, or the first grid screen when the
            // focused one isn't
            readonly property bool keys: {
                if (!gridScreen)
                    return false
                if (monitor && monitor.focused)
                    return true
                const focused = grid.monitors.find(m => m.focused)
                const fid = focused && focused.activeWorkspace ? focused.activeWorkspace.id : 0
                if (fid >= 1 && fid <= 8)
                    return false
                return grid.monitors.find(m => m.activeWorkspace && m.activeWorkspace.id >= 1 && m.activeWorkspace.id <= 8)?.name === modelData.name
            }
            // the bar's strip: left, top, right, bottom
            readonly property var reserved: mon && mon.reserved ? mon.reserved : [0, 0, 0, 0]

            // The plane: the desktops at the screen's size, a gap between;
            // at progress 1, scaled to fit above the bar's strip, centred.
            readonly property real margin: 56
            readonly property real gap: 28
            readonly property real fitW: width - reserved[0] - reserved[2] - 2 * margin
            readonly property real fitH: height - reserved[1] - reserved[3] - 2 * margin
            readonly property real fit: Math.max(0.05, Math.min((fitW - gap) / (2 * width), (fitH - gap) / (2 * height)))
            readonly property real planeGap: gap / fit
            readonly property real fitX: reserved[0] + margin + (fitW - fit * (2 * width + planeGap)) / 2
            readonly property real fitY: reserved[1] + margin + (fitH - fit * (2 * height + planeGap)) / 2
            function cellX(d) {
                return ((d - 1) % 2) * (width + planeGap)
            }
            function cellY(d) {
                return Math.floor((d - 1) / 2) * (height + planeGap)
            }
            // between: the scale and the plane's place go straight from one
            // to the other (so the desktop shown does)
            readonly property real p: grid.progress
            readonly property real scale: 1 + (fit - 1) * p
            readonly property real planeX: -cellX(grid.current) * (1 - p) + fitX * p
            readonly property real planeY: -cellY(grid.current) * (1 - p) + fitY * p

            // where a point of the view lies: the desktop under it, 0 none
            function deskAt(x, y) {
                const px = (x - planeX) / scale
                const py = (y - planeY) / scale
                const col = px >= 0 && px < width ? 0 : px >= width + planeGap && px < 2 * width + planeGap ? 1 : -1
                const row = py >= 0 && py < height ? 0 : py >= height + planeGap && py < 2 * height + planeGap ? 1 : -1
                return col < 0 || row < 0 ? 0 : row * 2 + col + 1
            }

            function refresh() {
                for (let i = 0; i < desks.count; i++) {
                    const d = desks.itemAt(i)
                    if (d)
                        d.refresh()
                }
            }
            function ready() {
                if (!gridScreen)
                    return true
                if (paper.status === Image.Loading)
                    return false
                for (let i = 0; i < desks.count; i++) {
                    const d = desks.itemAt(i)
                    if (d && !d.ready())
                        return false
                }
                return true
            }

            // in the grid, the shown desktop's pictures follow its windows,
            // 20 times a second
            Timer {
                interval: 50
                repeat: true
                running: grid.settled && view.gridScreen
                onTriggered: view.refresh()
            }

            screen: modelData
            visible: grid.up && gridScreen
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shadesmar-grid"
            WlrLayershell.keyboardFocus: grid.shown && keys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // on the way back, clicks and keys go to the windows already
            mask: grid.shown ? null : through

            Region {
                id: through
            }

            // Above the bar's strip (Hyprland's reserved area), which keeps
            // the bar.
            Item {
                id: area

                visible: grid.revealed
                x: view.reserved[0]
                y: view.reserved[1]
                width: view.width - view.reserved[0] - view.reserved[2]
                height: view.height - view.reserved[1] - view.reserved[3]
                clip: true

                Item {
                    id: stage

                    x: -area.x
                    y: -area.y
                    width: view.width
                    height: view.height

                    // the wallpaper again, under the shade: while the
                    // desktops shrink, the windows themselves don't show
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.frameColor
                    }
                    Image {
                        id: paper

                        anchors.fill: parent
                        source: grid.up ? grid.wallpaper : ""
                        fillMode: Image.PreserveAspectCrop
                        // as Wallpaper.qml's: the same decoded picture
                        sourceSize: Qt.size(view.width, view.height)
                        asynchronous: true
                        smooth: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.shade
                        opacity: view.p
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: grid.shown
                        onClicked: grid.close()
                    }

                    Item {
                        id: plane

                        x: view.planeX
                        y: view.planeY
                        transform: Scale {
                            xScale: view.scale
                            yScale: view.scale
                        }

                        Repeater {
                            id: desks

                            model: view.gridScreen ? 4 : 0

                            Desk {}
                        }
                    }

                    // the window dragged, over the desktops
                    ShaderEffectSource {
                        id: ghost

                        readonly property var d: grid.dragged
                        readonly property bool here: d !== null && d.view === view

                        visible: here
                        sourceItem: here ? d.thumb : null
                        hideSource: here
                        mipmap: true
                        smooth: true
                        x: here ? d.x - d.dx * view.scale : 0
                        y: here ? d.y - d.dy * view.scale : 0
                        width: here ? d.thumb.width * view.scale : 0
                        height: here ? d.thumb.height * view.scale : 0
                        opacity: 0.9
                    }
                }
            }

            component Desk: Item {
                id: desk

                required property int index
                readonly property int d: index + 1
                readonly property int workspace: view.base + d
                // on the screens now: its windows can be taken again
                readonly property bool live: d === grid.current
                readonly property bool lit: grid.shown && (grid.selected === d || target)
                // a window dragged over it, from another desktop
                readonly property bool target: grid.dragged !== null && grid.dragged.view === view && grid.dragged.over === d && grid.dragged.from !== d

                // as Hyprland stacks them: the tiled ones, then the floating
                // ones, in its list's order. A tiled one whose middle is
                // beside the screen (the tape's other columns) isn't on it.
                readonly property var windows: {
                    const m = view.mon
                    if (!m)
                        return []
                    const on = c => {
                        if (!c.mapped || c.hidden || !c.size || !c.workspace || c.workspace.id !== desk.workspace)
                            return false
                        if (c.floating)
                            return true
                        const mx = c.at[0] - m.x + c.size[0] / 2
                        const my = c.at[1] - m.y + c.size[1] / 2
                        return mx >= 0 && mx < view.width && my >= 0 && my < view.height
                    }
                    return grid.clients.filter(on).map(c => ({
                                client: c,
                                toplevel: Hyprland.toplevels.values.find(t => "0x" + t.address === c.address) ?? null
                            })).filter(e => e.toplevel !== null)
                }

                function refresh() {
                    for (let i = 0; i < wins.count; i++) {
                        const w = wins.itemAt(i)
                        if (w)
                            w.refresh()
                    }
                }
                function ready() {
                    for (let i = 0; i < wins.count; i++) {
                        const w = wins.itemAt(i)
                        if (w && !w.ready)
                            return false
                    }
                    return true
                }

                x: view.cellX(d)
                y: view.cellY(d)
                width: view.width
                height: view.height
                clip: true

                Image {
                    anchors.fill: parent
                    source: grid.up ? grid.wallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(view.width, view.height)
                    asynchronous: true
                    smooth: true
                }

                // a click beside its windows: there
                MouseArea {
                    anchors.fill: parent
                    enabled: grid.shown
                    hoverEnabled: true
                    onPositionChanged: grid.selected = desk.d
                    onClicked: grid.go(desk.d)
                }

                Repeater {
                    id: wins

                    model: desk.windows

                    Item {
                        id: win

                        required property var modelData
                        readonly property var client: modelData.client
                        readonly property real hx: client.at[0] - (view.mon ? view.mon.x : 0)
                        readonly property real hy: client.at[1] - (view.mon ? view.mon.y : 0)
                        readonly property bool onScreen: desk.live && hx < view.width && hx + client.size[0] > 0 && hy < view.height && hy + client.size[1] > 0
                        // its own picture comes, needed first
                        readonly property bool ready: !onScreen || thumb.hasContent
                        function refresh() {
                            thumb.refresh()
                        }

                        x: hx
                        y: hy
                        width: client.size[0]
                        height: client.size[1]
                        z: (client.floating ? 2000 : 1000) + grid.clients.indexOf(client)

                        Thumbnail {
                            id: thumb

                            anchors.fill: parent
                            toplevel: win.modelData.toplevel
                            appClass: win.client["class"] || ""
                            capturing: grid.up && win.onScreen
                            kept: grid.pictures.of(win.modelData.toplevel)
                            radius: win.client.fullscreen ? 0 : win.client.floating || Theme.floating ? 10 : 0
                            shadow: win.client.fullscreen ? 0 : 1
                            lit: false
                        }

                        // a click goes to it, a drag takes it to another
                        // desktop
                        MouseArea {
                            id: handle

                            property point pressed
                            property bool dragging: false

                            anchors.fill: parent
                            enabled: grid.shown
                            hoverEnabled: true
                            preventStealing: true
                            onPositionChanged: mouse => {
                                grid.selected = desk.d
                                if (!(mouse.buttons & Qt.LeftButton))
                                    return
                                const at = mapToItem(stage, mouse.x, mouse.y)
                                if (!dragging && Math.hypot(mouse.x - pressed.x, mouse.y - pressed.y) * view.scale > 8) {
                                    dragging = true
                                    grid.dragged = {
                                        view: view,
                                        thumb: thumb,
                                        toplevel: win.modelData.toplevel,
                                        from: desk.d,
                                        dx: pressed.x,
                                        dy: pressed.y,
                                        x: at.x,
                                        y: at.y,
                                        over: desk.d
                                    }
                                }
                                if (dragging)
                                    grid.dragged = Object.assign({}, grid.dragged, {
                                        x: at.x,
                                        y: at.y,
                                        over: view.deskAt(at.x, at.y)
                                    })
                            }
                            onPressed: mouse => {
                                pressed = Qt.point(mouse.x, mouse.y)
                                dragging = false
                            }
                            onReleased: {
                                if (!dragging)
                                    return
                                const dr = grid.dragged
                                grid.dragged = null
                                dragging = false
                                if (dr && dr.over > 0 && dr.over !== dr.from)
                                    grid.move(dr.toplevel, view.base + dr.over)
                            }
                            onCanceled: {
                                dragging = false
                                grid.dragged = null
                            }
                            onClicked: {
                                if (!dragging)
                                    grid.go(desk.d, win.modelData.toplevel)
                            }
                        }
                    }
                }

                // its frame, over its windows, on the screen's pixels
                // whatever the scale: lit when picked
                Rectangle {
                    z: 10000
                    anchors.fill: parent
                    color: "transparent"
                    opacity: view.p
                    border.width: (desk.lit ? 3 : 1) / view.scale
                    border.color: desk.lit ? Theme.accent : Theme.outline
                }
            }

            Item {
                focus: true

                Keys.onPressed: event => {
                    const s = grid.selected
                    switch (event.key) {
                    case Qt.Key_Escape:
                        grid.close()
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        grid.go(s)
                        break
                    case Qt.Key_Left:
                    case Qt.Key_Right:
                        grid.selected = s % 2 === 1 ? s + 1 : s - 1
                        break
                    case Qt.Key_Up:
                    case Qt.Key_Down:
                        grid.selected = s <= 2 ? s + 2 : s - 2
                        break
                    default:
                        return
                    }
                    event.accepted = true
                }
            }
        }
    }
}
