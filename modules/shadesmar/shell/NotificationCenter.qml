// The bell: the notifications whose popup has gone (Notifications.qml), the
// count of those unread. Its popup: Do not disturb; the history, the newest
// first (a click runs one's default action, the cross dismisses it), and
// Clear.
import QtQuick
import Quickshell

BarButton {
    id: center

    required property var notifications

    popup: "notifications"
    icon: notifications.dnd ? "notifications-disabled" : "notifications"
    badge: notifications.unread

    // for the "5 min" of each, refreshed while it's open
    property real now: Date.now()

    function ago(n) {
        const s = (now - (notifications.times[n.id] ?? now)) / 1000
        return s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)} min` : s < 86400 ? `${Math.floor(s / 3600)} h` : `${Math.floor(s / 86400)} d`
    }

    Timer {
        running: popup.shown
        repeat: true
        triggeredOnStart: true
        interval: 30000
        onTriggered: center.now = Date.now()
    }

    BarPopup {
        id: popup

        bar: center.bar
        from: center
        name: "notifications"
        popupWidth: 400
        onShownChanged: {
            if (shown)
                center.notifications.unread = 0
        }

        PopupHeader {
            title: "Do not disturb"
            toggle: true
            checked: center.notifications.dnd
            onToggled: center.notifications.dnd = !center.notifications.dnd
        }

        PopupHeader {
            title: "Notifications"
            action: center.notifications.history.length > 0 ? "Clear" : ""
            onActed: center.notifications.clear()
        }

        Text {
            visible: center.notifications.history.length === 0
            x: 4
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: "None"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        // at most 10: Clear for the rest
        Repeater {
            model: center.notifications.history.slice(0, 10)

            ListRow {
                required property var modelData
                readonly property var defaultAction: modelData.actions.find(a => a.identifier === "default") ?? null

                iconSource: center.notifications.picture(modelData) || center.notifications.icon(modelData)
                title: modelData.summary
                subtitle: [modelData.appName, modelData.body].filter(s => s !== "").join(" · ")
                subtitleLines: 2
                trailing: center.ago(modelData)
                removable: true
                onClicked: {
                    if (defaultAction) {
                        popup.close()
                        defaultAction.invoke()
                    }
                }
                onRemoved: modelData.dismiss()
            }
        }
    }
}
