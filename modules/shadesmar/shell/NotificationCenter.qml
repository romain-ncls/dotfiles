// The bell: the notifications (Notifications.qml), the count of those that
// left the screen since it was last opened. Its popup: its switch (popups,
// or Do not disturb); all of them by app, the app with the newest first,
// as the popups' cards (NotificationStack.qml): an app's newest in front,
// its others folded behind, unfolded by their count; those new since the
// last look marked; opening it takes the popups there (a critical one stays
// on screen too). A click runs one's default action, opens the file it's
// about, or shows its app; the cross dismisses it; Clear all.
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
    // the look before this one: what came since is marked
    property real lastSeen: 0
    // each close folds the stacks again
    property int closes: 0

    function ago(e) {
        const s = (now - e.time) / 1000
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
            if (shown) {
                center.lastSeen = center.notifications.seenAt
                center.notifications.seen()
            } else {
                center.closes++
            }
        }

        // the switch: popups on, or Do not disturb
        PopupHero {
            readonly property int fresh: center.notifications.entries.filter(e => e.time > center.lastSeen).length

            icon: center.icon
            title: "Notifications"
            caption: center.notifications.dnd ? "Do not disturb" : fresh > 0 ? `${fresh} new` : "Nothing new"
            toggle: true
            checked: !center.notifications.dnd
            onToggled: center.notifications.dnd = !center.notifications.dnd
        }

        SectionLabel {
            text: "Recent"
            action: center.notifications.entries.length > 0 ? "Clear all" : ""
            onActed: center.notifications.clear()
        }

        Rectangle {
            visible: center.notifications.entries.length === 0
            width: parent.width
            height: 64
            radius: Theme.plateCorner
            color: Theme.plate

            Text {
                anchors.centerIn: parent
                text: "No notifications"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.body
            }
        }

        // past half a screen, it scrolls
        Scroller {
            visible: center.notifications.entries.length > 0
            maxHeight: 520
            spacing: 8

            Repeater {
                model: ScriptModel {
                    values: center.notifications.groups
                    objectProp: "key"
                }

                NotificationStack {
                    required property var modelData

                    width: parent ? parent.width : 380
                    host: center.notifications
                    group: modelData.key
                    flat: true
                    ago: e => center.ago(e)
                    lastSeen: center.lastSeen
                    folds: center.closes
                    onActivated: popup.close()
                }
            }
        }
    }
}
