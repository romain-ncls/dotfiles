// The wallpaper, on every screen: the newest of the ones liked in Backdrop
// (it keeps them in ~/Pictures/Backdrop), cropped to fill. Backdrop's
// rotation stays Plasma's for now; the Silksong scene comes here later
// (docs/hyprland.md, phase 5).
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland

Scope {
    id: wallpaper

    FolderListModel {
        id: liked

        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Backdrop"
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    readonly property url source: liked.count > 0 ? liked.get(0, "fileUrl") : ""

    Variants {
        model: Quickshell.screens

        PanelWindow {
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

            Image {
                anchors.fill: parent
                source: wallpaper.source
                fillMode: Image.PreserveAspectCrop
                // decoded at the screen's size, not the file's
                sourceSize: Qt.size(width, height)
                asynchronous: true
                smooth: true
            }
        }
    }
}
