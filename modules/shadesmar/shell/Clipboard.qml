// The clipboard's history, Klipper's: what was copied, kept by cliphist
// (clipboard-history.service watches the clipboard; a password manager's
// copies, marked secret, are left out). The popup: a filter, then the
// entries, the newest first, in a list that scrolls past half the screen; a
// click, or Enter on the one Up and Down are on, copies one back; the cross
// forgets it; Clear forgets them all. A picture shows as one: cliphist
// decodes it, once, into the runtime folder.
import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: cb

    popup: "clipboard"
    icon: "klipper"

    // cliphist's lines: "id<TAB>preview"; a picture's preview is
    // "[[ binary data 134 KiB png 300x500 ]]"
    property var entries: []
    property string filter: ""
    // the entry the keys are on
    property int current: 0

    readonly property var matching: {
        const f = filter.toLowerCase()
        return entries.filter(e => f === "" || e.text.toLowerCase().includes(f))
    }
    onMatchingChanged: current = 0

    readonly property string pictures: Quickshell.env("XDG_RUNTIME_DIR") + "/shadesmar-clipboard"

    function parse(l) {
        const tab = l.indexOf("\t")
        const preview = l.slice(tab + 1)
        const m = preview.match(/^\[\[ binary data (.+) (\w+) (\d+)x(\d+) \]\]$/)
        return {
            line: l,
            id: l.slice(0, tab),
            preview: preview,
            image: m ? { size: m[1], type: m[2], width: m[3], height: m[4] } : null,
            text: m ? "image" : preview.replace(/\s+/g, " ").trim()
        }
    }

    Process {
        id: list

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: cb.entries = text.split("\n").filter(l => l.includes("\t")).map(l => cb.parse(l))
        }
    }

    // the line goes to cliphist's stdin, as its docs have it
    function run(script, line) {
        Quickshell.execDetached(["sh", "-c", script, "sh", line])
    }

    function copy(e) {
        if (!e)
            return
        run("printf '%s' \"$1\" | cliphist decode | wl-copy", e.line)
        popup.close()
    }
    function forget(e) {
        run(`printf '%s' "$1" | cliphist delete; rm -f "${pictures}/${e.id}".*`, e.line)
        entries = entries.filter(o => o.line !== e.line)
    }

    BarPopup {
        id: popup

        bar: cb.bar
        from: cb
        name: "clipboard"
        popupWidth: 420
        onShownChanged: {
            if (shown) {
                cb.filter = ""
                list.running = true
            }
        }

        PopupHero {
            icon: cb.icon
            title: "Clipboard"
            caption: cb.entries.length === 1 ? "1 copy kept" : `${cb.entries.length} copies kept`
        }

        Rectangle {
            width: parent.width
            height: 34
            radius: 8
            color: Theme.slot

            TextInput {
                id: search

                x: 10
                width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                focus: popup.shown
                text: cb.filter
                onTextChanged: cb.filter = text
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                clip: true

                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Filter…"
                    color: Theme.dim
                    font: search.font
                }

                Keys.onUpPressed: cb.current = Math.max(0, cb.current - 1)
                Keys.onDownPressed: cb.current = Math.min(cb.matching.length - 1, cb.current + 1)
                onAccepted: cb.copy(cb.matching[cb.current])
            }
        }

        SectionLabel {
            visible: cb.entries.length > 0
            text: "History"
            action: "Clear"
            onActed: {
                Quickshell.execDetached(["sh", "-c", `cliphist wipe; rm -rf "${cb.pictures}"`])
                cb.entries = []
            }
        }

        Text {
            visible: cb.matching.length === 0
            x: 4
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: cb.entries.length === 0 ? "Nothing copied yet" : "No match"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        ListView {
            id: rows

            visible: cb.matching.length > 0
            width: parent.width
            height: Math.min(contentHeight, (cb.bar.screen ? cb.bar.screen.height : 1080) / 2)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: cb.matching
            currentIndex: cb.current
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: ListRow {
                id: row

                required property var modelData
                required property int index
                readonly property var e: modelData
                readonly property string file: e.image ? `${cb.pictures}/${e.id}.${e.image.type}` : ""
                property bool decoded: false

                width: rows.width
                thumbnail: decoded ? "file://" + file : ""
                icon: e.image && !decoded ? "image-x-generic" : ""
                title: e.image ? "Image" : e.text
                subtitle: e.image ? `${e.image.type.toUpperCase()} · ${e.image.width} × ${e.image.height} · ${e.image.size}` : ""
                selected: index === cb.current
                removable: true
                onClicked: cb.copy(e)
                onRemoved: cb.forget(e)

                Process {
                    running: row.file !== ""
                    command: ["sh", "-c", "mkdir -p \"${2%/*}\" && { [ -s \"$2\" ] || { printf '%s' \"$1\" | cliphist decode > \"$2.part\" && mv \"$2.part\" \"$2\"; }; }", "sh", row.e.line, row.file]
                    onExited: code => row.decoded = code === 0
                }
            }
        }
    }
}
