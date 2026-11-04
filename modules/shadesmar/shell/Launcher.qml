// The launcher, on KRunner's keys (Alt+Space, Alt+F2) and Meta+Space: the
// apps whose name, generic name, keywords or command match what's typed, the
// most launched first (with nothing typed, the most launched), or what's
// typed run as a command. Up and Down, Enter, Escape. Hyprland starts what
// it launches, as its binds do: a child of the shell would go with
// shadesmar.service when it restarts.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: launcher

    property bool shown: false
    property string query: ""
    property int selected: 0

    function open() {
        query = ""
        selected = 0
        shown = true
    }
    function close() {
        shown = false
    }
    function toggle() {
        if (shown)
            close()
        else
            open()
    }

    // How many times each app was launched, by its desktop entry's id.
    FileView {
        id: store

        path: Quickshell.statePath("launches.json")
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter()
        }

        JsonAdapter {
            id: launches

            property var counts: ({})
        }
    }

    function count(entry) {
        return launches.counts[entry.id] ?? 0
    }

    // 4: the name starts with it, 3: a word of it does, 2: it's in the
    // name, 1: in the rest; 0: no match.
    function score(entry, q) {
        const name = entry.name.toLowerCase()
        if (name.startsWith(q))
            return 4
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 3
        if (name.includes(q))
            return 2
        const rest = [entry.genericName, entry.comment, entry.keywords.join(" "), entry.execString].join(" ").toLowerCase()
        return rest.includes(q) ? 1 : 0
    }

    readonly property var results: {
        const q = query.trim().toLowerCase()
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay)
        if (q === "")
            return apps.filter(e => count(e) > 0).sort((a, b) => count(b) - count(a)).slice(0, 8)
        return apps.map(e => ({ entry: e, score: score(e, q) })).filter(r => r.score > 0)
            .sort((a, b) => b.score - a.score || count(b.entry) - count(a.entry) || a.entry.name.localeCompare(b.entry.name))
            .slice(0, 8).map(r => r.entry)
    }
    // the rows: the apps, then what's typed as a command
    readonly property int rows: results.length + (query.trim() !== "" ? 1 : 0)
    onQueryChanged: selected = 0

    function quote(arg) {
        return "'" + arg.replace(/'/g, "'\\''") + "'"
    }

    // Hyprland runs it (sh -c), from a Lua long string.
    function run(command) {
        Quickshell.execDetached(["hyprctl", "eval", `hl.exec_cmd([==[${command}]==])`])
    }

    function launch(i) {
        close()
        if (i >= results.length) {
            run(query.trim())
            return
        }
        const entry = results[i]
        const args = entry.command.filter(a => !/^%[fFuUdDnNickvm]$/.test(a))
        const command = args.map(quote).join(" ")
        run(entry.runInTerminal ? `ghostty -e ${command}` : command)
        const counts = Object.assign({}, launches.counts)
        counts[entry.id] = (counts[entry.id] ?? 0) + 1
        launches.counts = counts
        store.writeAdapter()
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "launcher"
        description: "Launch an app or a command"
        onPressed: launcher.toggle()
    }

    // qs -c shadesmar ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.toggle()
        }
    }

    PanelWindow {
        id: window

        screen: {
            const m = Hyprland.focusedMonitor
            return Quickshell.screens.find(s => m && s.name === m.name) ?? Quickshell.screens[0]
        }
        visible: launcher.shown
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea {
            anchors.fill: parent
            onClicked: launcher.close()
        }

        Rectangle {
            id: box

            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 4
            width: 560
            height: list.y + list.height + 10
            radius: Theme.radius + 4
            color: Theme.popup
            border.width: 1
            border.color: Theme.outline

            // clicks inside stay inside
            MouseArea {
                anchors.fill: parent
            }

            TextInput {
                id: input

                x: 20
                y: 16
                width: parent.width - 40
                height: 28
                focus: launcher.shown
                text: launcher.query
                onTextChanged: launcher.query = text
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font
                font.pixelSize: 18
                clip: true

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Launch…"
                    color: Theme.dim
                    font: input.font
                }

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        launcher.close()
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (launcher.rows > 0)
                            launcher.launch(launcher.selected)
                        break
                    case Qt.Key_Down:
                    case Qt.Key_Tab:
                        if (launcher.rows > 0)
                            launcher.selected = (launcher.selected + 1) % launcher.rows
                        break
                    case Qt.Key_Up:
                        if (launcher.rows > 0)
                            launcher.selected = (launcher.selected + launcher.rows - 1) % launcher.rows
                        break
                    default:
                        return
                    }
                    event.accepted = true
                }
            }

            Column {
                id: list

                x: 10
                y: input.y + input.height + 12
                width: parent.width - 20

                Repeater {
                    model: launcher.rows

                    Rectangle {
                        id: row

                        required property int index
                        readonly property bool isCommand: index >= launcher.results.length
                        readonly property var entry: isCommand ? null : launcher.results[index]

                        width: list.width
                        height: 44
                        radius: 8
                        color: launcher.selected === index ? Theme.slot : "transparent"

                        IconImage {
                            id: glyph

                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 28
                            source: Quickshell.iconPath(row.isCommand ? "utilities-terminal" : row.entry.icon, "application-x-executable")
                        }

                        Text {
                            id: title

                            anchors.left: glyph.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.isCommand ? `Run “${launcher.query.trim()}”` : row.entry.name
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 14
                        }

                        Text {
                            anchors.left: title.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.isCommand ? "" : row.entry.genericName || row.entry.comment
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: launcher.selected = row.index
                            onClicked: launcher.launch(row.index)
                        }
                    }
                }
            }
        }
    }
}
