// The clipboard's history, Klipper's: what was copied, kept by cliphist
// (clipboard-history.service watches the clipboard; a password manager's
// copies, marked secret, are left out). The popup: a filter, the entries,
// the newest first (a click copies one back, the cross forgets it), and
// Clear.
import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: cb

    popup: "clipboard"
    icon: "klipper"

    // cliphist's lines: "id<TAB>preview"
    property var entries: []
    property string filter: ""

    readonly property var shown: {
        const f = filter.toLowerCase()
        return entries.filter(e => f === "" || e.preview.toLowerCase().includes(f)).slice(0, 30)
    }

    Process {
        id: list

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                cb.entries = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const tab = l.indexOf("\t")
                    return { line: l, preview: l.slice(tab + 1) }
                })
            }
        }
    }

    function refresh() {
        list.running = true
    }

    // the line goes to cliphist's stdin, as its docs have it
    function run(script, line) {
        Quickshell.execDetached(["sh", "-c", script, "sh", line])
    }

    function image(e) {
        return e.preview.startsWith("[[ binary data")
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
                cb.refresh()
            }
        }

        PopupHeader {
            title: "Clipboard"
            action: cb.entries.length > 0 ? "Clear" : ""
            onActed: {
                Quickshell.execDetached(["cliphist", "wipe"])
                cb.entries = []
            }
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

                // Enter copies the first
                onAccepted: {
                    if (cb.shown.length > 0) {
                        cb.run("printf '%s' \"$1\" | cliphist decode | wl-copy", cb.shown[0].line)
                        popup.close()
                    }
                }
            }
        }

        Text {
            visible: cb.shown.length === 0
            x: 4
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: cb.entries.length === 0 ? "Nothing copied yet" : "No match"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        Repeater {
            model: cb.shown

            ListRow {
                required property var modelData

                icon: cb.image(modelData) ? "image-x-generic" : ""
                title: cb.image(modelData) ? "Image " + modelData.preview.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, "") : modelData.preview.replace(/\s+/g, " ").trim()
                removable: true
                onClicked: {
                    cb.run("printf '%s' \"$1\" | cliphist decode | wl-copy", modelData.line)
                    popup.close()
                }
                onRemoved: {
                    cb.run("printf '%s' \"$1\" | cliphist delete", modelData.line)
                    cb.entries = cb.entries.filter(e => e.line !== modelData.line)
                }
            }
        }
    }
}
