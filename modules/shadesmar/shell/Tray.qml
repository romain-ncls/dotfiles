// The tray (KDE Connect, Discord…): a click activates, a right click (or an
// item that only has a menu) opens its menu, the middle click is the item's
// other action, scrolling goes to the item.
//
// The apps' own icons are in their colors, beside the bar's line icons
// (nalthis's, Lucide's): each shows as a line icon in the text's color
// instead: for the apps we know, one of nalthis's (KDE Connect's phone,
// Spotify's note: drawn as the bar's) or ours (icons/: Lucide's), else
// its own monochrome one (its theme's "-symbolic"), else its picture as a
// silhouette (Discord's, whose shape says muted or deafened).
// One that asks for attention is in the accent's color.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: tray

    required property var window
    spacing: 6

    // by the item's id: a theme icon's name (nalthis draws it, as the
    // bar's), else ours (icons/)
    readonly property var themed: ({
            "KDE Connect Indicator": "kdeconnect-tray",
            "spotify-client": "folder-music"
        })
    readonly property var ours: ({
            "Easy Effects": "sliders-vertical"
        })

    function glyph(item) {
        const named = themed[item.id]
        if (named)
            return Quickshell.iconPath(named)
        const mine = ours[item.id]
        if (mine)
            return Qt.resolvedUrl(`icons/${mine}.svg`)
        // image://icon/NAME, maybe ?path=… after it
        const icon = String(item.icon)
        if (icon.startsWith("image://icon/")) {
            const name = icon.slice(13).split("?")[0]
            const symbolic = name.endsWith("-symbolic") ? name : Quickshell.iconPath(name + "-symbolic", true)
            if (symbolic !== "")
                return name.endsWith("-symbolic") ? icon : symbolic
        }
        return icon
    }

    Repeater {
        model: SystemTray.items.values

        BarItem {
            id: button

            required property var modelData

            bar: tray.window
            implicitWidth: Theme.icon + 14
            buttons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: event => {
                const item = button.modelData
                if (event.button === Qt.RightButton || (item.onlyMenu && item.hasMenu)) {
                    const p = button.mapToItem(null, 0, 0)
                    item.display(tray.window, p.x, p.y)
                } else if (event.button === Qt.MiddleButton) {
                    item.secondaryActivate()
                } else {
                    item.activate()
                }
            }
            onWheeled: wheel => button.modelData.scroll(wheel.angleDelta.y, false)

            IconImage {
                id: raw

                anchors.centerIn: parent
                implicitSize: Theme.icon
                source: tray.glyph(button.modelData)
                visible: false
            }

            // the silhouette: white, then the color
            MultiEffect {
                anchors.fill: raw
                source: raw
                brightness: 1
                colorization: 1
                colorizationColor: button.modelData.status === Status.NeedsAttention ? Theme.accent : Theme.text
            }
        }
    }
}
