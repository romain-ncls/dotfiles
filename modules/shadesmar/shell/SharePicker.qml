// Screen sharing's picker, as Plasma's: "Screen Sharing Requested", the
// screens and a region, then the windows, as pictures; a click shares. For
// xdg-desktop-portal-hyprland, which runs shadesmar-share-picker
// (modules/shadesmar/pkg; custom_picker_binary in modules/hyprland's
// hypr/xdph.conf): it calls `share pick` here with a FIFO, and the answer
// goes back through it. The pictures are taken four times a second
// (Thumbnail.qml: not live, which would copy at every repaint); the
// scrolling layout's columns beside the screen show their last one
// (WindowPictures.qml). The windows most recently used first. A region:
// slurp. The search, focused, filters both; arrows move, Enter shares,
// Escape cancels. "Allow the application to do this without asking next
// time" lets it keep a token for the same choice.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: picker

    // the windows' last pictures (the overview's)
    required property var pictures

    property bool shown: false
    // the waiting request's FIFO; "" when none waits
    property string fifo: ""
    property bool allowRestore: true
    // the windows the portal can share: {handle, appClass, title, toplevel}
    property var windows: []
    property string search: ""
    // the screen it shows on: the focused one when it's asked
    property string screenName: ""
    // the item the keys are on, in `items`
    property int current: 0

    signal tick

    // the screens, left to right
    readonly property var screens: Quickshell.screens.slice().sort((a, b) => a.x - b.x || a.y - b.y)

    function screenLabel(s) {
        if (s.name.startsWith("eDP"))
            return "Laptop screen"
        if (!s.model)
            return s.name
        // the same model twice: where it is
        const twins = screens.filter(o => o.model === s.model)
        if (twins.length < 2)
            return s.model
        const i = twins.indexOf(s)
        return `${s.model} (${i === 0 ? "left" : i === twins.length - 1 ? "right" : "middle"})`
    }

    function matches(...texts) {
        const s = search.trim().toLowerCase()
        return s === "" || texts.some(t => t.toLowerCase().includes(s))
    }

    // 0: the window used last
    function recency(w) {
        const o = w.toplevel ? w.toplevel.lastIpcObject : null
        return o && o.focusHistoryID !== undefined ? o.focusHistoryID : 1000
    }

    // what it offers, in order: the screens, a region, the windows
    readonly property var sources: [...screens.filter(s => matches(screenLabel(s), s.name)).map(s => ({
                    kind: "screen",
                    screen: s,
                    label: screenLabel(s)
                })), ...(matches("region") ? [{
                        kind: "region",
                        label: "A region…"
                    }] : [])]
    readonly property var shared: windows.filter(w => matches(w.title, w.appClass)).sort((a, b) => recency(a) - recency(b)).map(w => ({
                kind: "window",
                window: w,
                label: w.title || w.appClass
            }))
    readonly property var items: [...sources, ...shared]

    onSearchChanged: current = 0
    onItemsChanged: current = Math.max(0, Math.min(current, items.length - 1))

    // XDPH_WINDOW_SHARING_LIST: handle[HC>]class[HT>]title[HE>]address[HA>]…,
    // the address Hyprland's, in decimal
    function parse(list) {
        const out = []
        for (const entry of list.split("[HA>]")) {
            const m = entry.match(/^(\d+)\[HC>\]([\s\S]*)\[HT>\]([\s\S]*)\[HE>\](\d+)$/)
            if (!m)
                continue
            const address = Number(m[4]).toString(16)
            out.push({
                handle: m[1],
                appClass: m[2],
                title: m[3],
                toplevel: Hyprland.toplevels.values.find(t => t.address === address) ?? null
            })
        }
        return out
    }

    function ask(fifo, token, list) {
        // a new request: the one before is cancelled
        if (picker.fifo !== "")
            reply("")
        const m = Hyprland.focusedMonitor
        screenName = m ? m.name : ""
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
        windows = parse(list)
        allowRestore = token
        search = ""
        current = 0
        picker.fifo = fifo
        shown = true
    }

    // "screen:…", "window:…", "region:…"; "" cancels
    function reply(selection) {
        if (fifo === "")
            return
        const text = selection === "" ? "" : `${allowRestore ? "r" : ""}/${selection}`
        Quickshell.execDetached(["timeout", "5", "sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", text, fifo])
        fifo = ""
        shown = false
    }

    function share(item) {
        if (!item)
            return
        if (item.kind === "screen")
            reply(`screen:${item.screen.name}`)
        else if (item.kind === "window")
            reply(`window:${item.window.handle}`)
        else {
            // out of the way while it's dragged; the request still waits
            shown = false
            region.running = true
        }
    }

    // a reload drops the request: cancelled, not left waiting
    Component.onDestruction: reply("")

    // slurp, as the recorder's; its screen and the region in it
    Process {
        id: region

        command: ["sh", "-c", 'exec slurp -f "%o %X %Y %W %H" "$@" < /dev/null', "sh", "-d", "-w", "2", "-c", `${Theme.accent}ff`, "-b", `${Theme.frameColor}66`, "-s", "#00000000"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^(\S+) (\d+) (\d+) (\d+) (\d+)$/)
                if (m && +m[4] > 0 && +m[5] > 0)
                    picker.reply(`region:${m[1]}@${m[2]},${m[3]},${m[4]},${m[5]}`)
                else if (picker.fifo !== "")
                    picker.shown = true // Escape: back to the choice
            }
        }
    }

    Timer {
        running: picker.shown
        repeat: true
        interval: 250
        onTriggered: picker.tick()
    }

    // shadesmar-share-picker's call
    IpcHandler {
        target: "share"

        function pick(fifo: string, token: bool, windows: string): void {
            picker.ask(fifo, token, windows)
        }
    }

    PanelWindow {
        id: window

        screen: Quickshell.screens.find(s => s.name === picker.screenName) ?? Quickshell.screens[0]
        visible: picker.shown
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-share"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // a dialog: the clicks beside it go nowhere
        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            id: box

            readonly property int columns: 4
            readonly property real tileWidth: (list.width - (columns - 1) * 12) / columns

            anchors.centerIn: parent
            width: Math.min(920, parent.width - 96)
            height: Math.min(header.height + list.contentHeight + footer.height + 48, parent.height - 120)
            radius: Theme.radius + 4
            color: Theme.popup
            border.width: 1
            border.color: Theme.outline

            MouseArea {
                anchors.fill: parent
            }

            Item {
                id: header

                x: 20
                y: 16
                width: parent.width - 40
                height: 40

                IconImage {
                    id: glyph

                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 26
                    source: Quickshell.iconPath("video-display", "image-missing")
                }

                Column {
                    x: 38
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: "Screen Sharing Requested"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Choose what the app may see"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }

                // the search, which has the keys
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 220
                    height: 32
                    radius: 8
                    color: Theme.slot

                    TextInput {
                        id: input

                        x: 10
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                        focus: picker.shown
                        text: picker.search
                        onTextChanged: picker.search = text
                        clip: true
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 13

                        Text {
                            visible: input.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search…"
                            color: Theme.dim
                            font: input.font
                        }

                        Keys.onPressed: event => {
                            const n = picker.items.length
                            switch (event.key) {
                            case Qt.Key_Escape:
                                picker.reply("")
                                break
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                picker.share(picker.items[picker.current])
                                break
                            case Qt.Key_Right:
                            case Qt.Key_Tab:
                                picker.current = Math.min(n - 1, picker.current + 1)
                                break
                            case Qt.Key_Left:
                            case Qt.Key_Backtab:
                                picker.current = Math.max(0, picker.current - 1)
                                break
                            case Qt.Key_Down:
                                picker.current = Math.min(n - 1, picker.current + box.columns)
                                break
                            case Qt.Key_Up:
                                picker.current = Math.max(0, picker.current - box.columns)
                                break
                            default:
                                return
                            }
                            event.accepted = true
                        }
                    }
                }
            }

            Flickable {
                id: list

                x: 20
                y: header.y + header.height + 16
                width: parent.width - 40
                height: parent.height - y - footer.height - 16
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: content

                    width: parent.width
                    spacing: 12

                    Flow {
                        width: parent.width
                        spacing: 12

                        Repeater {
                            model: picker.sources

                            Tile {
                                required property int index

                                host: picker
                                width: box.tileWidth
                                place: index
                            }
                        }
                    }

                    // as Plasma's: a line, "Windows", a line
                    Item {
                        visible: picker.sources.length > 0 && picker.shared.length > 0
                        width: parent.width
                        height: 20

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: (parent.width - section.width) / 2 - 12
                            height: 1
                            color: Theme.outline
                        }

                        Text {
                            id: section

                            anchors.centerIn: parent
                            text: "Windows"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: (parent.width - section.width) / 2 - 12
                            height: 1
                            color: Theme.outline
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 12

                        Repeater {
                            model: picker.shared

                            Tile {
                                required property int index

                                host: picker
                                width: box.tileWidth
                                place: picker.sources.length + index
                            }
                        }
                    }

                    Text {
                        visible: picker.items.length === 0
                        width: parent.width
                        height: 60
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "Nothing matches"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
            }

            Item {
                id: footer

                x: 20
                y: parent.height - height - 14
                width: parent.width - 40
                height: 30

                // Plasma's checkbox
                Row {
                    id: check

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 4
                        color: picker.allowRestore ? Theme.accent : "transparent"
                        border.width: picker.allowRestore ? 0 : 1
                        border.color: Theme.dim

                        Text {
                            visible: picker.allowRestore
                            anchors.centerIn: parent
                            text: "✓"
                            color: Theme.accentText
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Allow the application to do this without asking next time"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: check
                    onClicked: picker.allowRestore = !picker.allowRestore
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(72, cancel.implicitWidth + 24)
                    height: 28
                    radius: 6
                    color: cancelArea.containsMouse ? Qt.lighter(Theme.slot, 1.2) : Theme.slot

                    Text {
                        id: cancel

                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: cancelArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: picker.reply("")
                    }
                }
            }
        }
    }

    // A screen, the region or a window: its picture in a box, its icon and
    // name under it. The keys' one lit; a click shares it.
    component Tile: Item {
        id: tile

        required property var modelData
        required property var host
        // its index in `items`
        property int place: 0
        readonly property bool lit: tile.host.current === place
        readonly property var screen: modelData.kind === "screen" ? modelData.screen : null
        readonly property var toplevel: modelData.kind === "window" ? modelData.window.toplevel : null
        readonly property string appClass: modelData.kind === "window" ? modelData.window.appClass : ""
        readonly property string icon: {
            if (modelData.kind === "screen")
                return "video-display"
            const entry = DesktopEntries.heuristicLookup(appClass)
            return entry ? entry.icon : appClass
        }
        // its width over its height
        readonly property real aspect: {
            if (screen)
                return screen.width / Math.max(1, screen.height)
            const o = toplevel ? toplevel.lastIpcObject : null
            return o && o.size && o.size[1] > 0 ? o.size[0] / o.size[1] : 16 / 10
        }

        height: frame.height + 30

        Rectangle {
            id: frame

            width: parent.width
            height: Math.round(width * 0.625)
            radius: 8
            color: area.containsMouse || tile.lit ? Theme.slot : Theme.alpha(Theme.slot, 0.45)

            Thumbnail {
                id: thumb

                visible: tile.modelData.kind !== "region"
                anchors.centerIn: parent
                width: Math.min(parent.width - 20, (parent.height - 20) * tile.aspect)
                height: width / tile.aspect
                toplevel: tile.toplevel
                source: tile.screen ?? (tile.toplevel ? tile.toplevel.wayland : null)
                appClass: tile.appClass || tile.icon
                lit: tile.lit
                radius: 5
                capturing: tile.host.shown && (tile.screen !== null || (tile.toplevel !== null && tile.host.pictures.onScreen(tile.toplevel)))
                kept: tile.toplevel ? tile.host.pictures.of(tile.toplevel) : null

                Connections {
                    target: tile.host

                    function onTick() {
                        thumb.refresh()
                    }
                }
            }

            // the region: a dashed frame, lit as the pictures are
            Item {
                visible: tile.modelData.kind === "region"
                anchors.centerIn: parent
                width: thumb.width * 0.6
                height: thumb.height * 0.6

                Dashes {
                    anchors.fill: parent
                    color: tile.lit ? Theme.text : Theme.dim
                    dash: 4
                    weight: 2
                }

                Rectangle {
                    visible: tile.lit
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: 6
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.accent
                }
            }
        }

        Row {
            y: frame.height + 8
            width: parent.width
            spacing: 6

            IconImage {
                visible: tile.modelData.kind !== "region"
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 16
                source: Quickshell.iconPath(tile.icon, "application-x-executable")
            }

            Item {
                visible: tile.modelData.kind === "region"
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16

                Dashes {
                    anchors.centerIn: parent
                    width: 14
                    height: 10
                    color: Theme.dim
                    dash: 2
                    weight: 1.5
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 22
                text: tile.modelData.label
                elide: Text.ElideRight
                color: tile.lit ? Theme.text : Theme.dim
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onEntered: tile.host.current = tile.place
            onClicked: tile.host.share(tile.modelData)
        }
    }

    // a dashed rectangle along its bounds
    component Dashes: Shape {
        id: dashes

        property color color: Theme.dim
        property real dash: 3
        property real weight: 2

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: dashes.color
            strokeWidth: dashes.weight
            strokeStyle: ShapePath.DashLine
            dashPattern: [dashes.dash / dashes.weight, dashes.dash / dashes.weight]
            fillColor: "transparent"
            startX: dashes.weight / 2
            startY: dashes.weight / 2

            PathLine {
                x: dashes.width - dashes.weight / 2
                y: dashes.weight / 2
            }
            PathLine {
                x: dashes.width - dashes.weight / 2
                y: dashes.height - dashes.weight / 2
            }
            PathLine {
                x: dashes.weight / 2
                y: dashes.height - dashes.weight / 2
            }
            PathLine {
                x: dashes.weight / 2
                y: dashes.weight / 2
            }
        }
    }
}
