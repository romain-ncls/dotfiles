// The tray (KDE Connect, Discord…): a click activates, a right click (or an
// item that only has a menu) opens its menu, scrolling goes to the item.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: tray

    required property var window
    spacing: 10

    Repeater {
        // nm-applet stays for its prompts; Network.qml is its menu
        model: SystemTray.items.values.filter(item => item.id !== "nm-applet")

        IconImage {
            id: icon

            required property var modelData

            implicitSize: Theme.icon
            source: modelData.icon

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: event => {
                    const item = icon.modelData
                    if (event.button === Qt.RightButton || (item.onlyMenu && item.hasMenu)) {
                        const p = icon.mapToItem(null, 0, 0)
                        item.display(tray.window, p.x, p.y)
                    } else if (event.button === Qt.MiddleButton) {
                        item.secondaryActivate()
                    } else {
                        item.activate()
                    }
                }
                onWheel: wheel => icon.modelData.scroll(wheel.angleDelta.y, false)
            }
        }
    }
}
