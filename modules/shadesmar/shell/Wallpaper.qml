// The wallpaper, on every screen: Backdrop's picture (modules/backdrop: its
// daemon keeps it as the only file in ~/.local/share/backdrop/current, which
// Plasma's wallpaper plugin shows too), cropped to fill, cross-faded into
// the next; the newest liked one (~/Pictures/Backdrop) until there's one. A
// right click on it: Backdrop's menu (BackdropMenu.qml). The Silksong scene
// comes here later (docs/hyprland.md, phase 5).
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland

Scope {
    id: wallpaper

    required property var menu

    readonly property string data: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/backdrop"
    // what the screens show
    property url source: ""

    // The newest file of each: while the daemon swaps pictures, the folder
    // briefly holds both, and a swap can land in one rescan that keeps the
    // count: every change looks again.
    function pick() {
        const url = current.count > 0 ? current.get(0, "fileUrl") : liked.count > 0 ? liked.get(0, "fileUrl") : ""
        if (String(url) !== String(source))
            source = url
    }

    FolderListModel {
        id: current

        folder: "file://" + wallpaper.data + "/current"
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Time
        onCountChanged: Qt.callLater(wallpaper.pick)
        onRowsInserted: Qt.callLater(wallpaper.pick)
        onRowsRemoved: Qt.callLater(wallpaper.pick)
        onDataChanged: Qt.callLater(wallpaper.pick)
        onModelReset: Qt.callLater(wallpaper.pick)
        onStatusChanged: Qt.callLater(wallpaper.pick)
    }
    FolderListModel {
        id: liked

        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Backdrop"
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Time
        onCountChanged: Qt.callLater(wallpaper.pick)
        onStatusChanged: Qt.callLater(wallpaper.pick)
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel

            required property var modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.frameColor
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "shadesmar-wallpaper"

            // The next picture fades in over the shown one once it's
            // loaded (decoded at the screen's size, not the file's); the
            // shown one goes after.
            Item {
                id: stage

                property Item front: null
                property Item loading: null

                anchors.fill: parent

                function show(url) {
                    if (String(url) === "")
                        return
                    if (loading)
                        loading.destroy()
                    // sized at once: decoded once, at the screen's size
                    const next = picture.createObject(stage, {
                        source: url,
                        width: stage.width,
                        height: stage.height
                    })
                    loading = next
                    const settle = () => {
                        if (next.status === Image.Loading)
                            return
                        next.statusChanged.disconnect(settle)
                        if (loading === next)
                            loading = null
                        if (next.status !== Image.Ready) {
                            next.destroy()
                            return
                        }
                        const old = front
                        front = next
                        next.opacity = 1
                        if (old)
                            old.destroy(1600)
                    }
                    next.statusChanged.connect(settle)
                    settle()
                }

                Component {
                    id: picture

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(width, height)
                        asynchronous: true
                        cache: false
                        smooth: true
                        opacity: 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 1200
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }

                Connections {
                    target: wallpaper

                    function onSourceChanged() {
                        stage.show(wallpaper.source)
                    }
                }
                Component.onCompleted: show(wallpaper.source)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: event => wallpaper.menu.openAt(panel.screen, event.x, event.y)
            }
        }
    }
}
