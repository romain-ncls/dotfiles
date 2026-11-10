// The bell: the notifications (Notifications.qml), the count of those that
// left the screen since it was last opened. Its popup: Do not disturb; all
// of them by app, the app with the newest first, those new since the last
// look marked; opening it takes the popups there (a critical one stays on
// screen too). An app's newest shows, the others unfold under
// it; Clear for an app's, or for all. A click runs one's default action,
// opens the file it's about, or shows its app; the cross dismisses it.
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
    // the apps unfolded, while it's open
    property var unfolded: ({})

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
                center.unfolded = ({})
            }
        }

        PopupHeader {
            title: "Do not disturb"
            toggle: true
            checked: center.notifications.dnd
            onToggled: center.notifications.dnd = !center.notifications.dnd
        }

        PopupHeader {
            title: "Notifications"
            action: center.notifications.entries.length > 0 ? "Clear" : ""
            onActed: center.notifications.clear()
        }

        Text {
            visible: center.notifications.entries.length === 0
            x: 4
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: "None"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        // up to 100: it scrolls past the height of half a screen
        Flickable {
            visible: center.notifications.entries.length > 0
            width: parent.width
            height: Math.min(contentHeight, 520)
            contentHeight: list.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: list

                width: parent.width
                spacing: 2

                Repeater {
                    model: center.notifications.groups

                    Column {
                        id: group

                        required property var modelData
                        // the newest first
                        readonly property var items: center.notifications.listedBy[modelData.key] ?? []
                        readonly property bool open: center.unfolded[modelData.key] === true

                        width: list.width

                        Repeater {
                            model: group.open ? group.items : group.items.slice(0, 1)

                            ListRow {
                                required property var modelData
                                readonly property var e: modelData

                                // its picture while the app keeps it (Discord's
                                // avatar), else the app's icon
                                iconSource: center.notifications.live[e.key] && e.picture ? e.picture : e.icon
                                title: e.summary + (e.count > 1 ? `  ×${e.count}` : "")
                                subtitle: [e.app, e.body].filter(s => s !== "").join(" · ")
                                subtitleLines: 2
                                trailing: center.ago(e)
                                marked: e.time > center.lastSeen
                                removable: true
                                onClicked: {
                                    popup.close()
                                    center.notifications.activate(e)
                                }
                                onRemoved: center.notifications.dismiss(e)
                            }
                        }

                        // the app's others: unfold them, fold them; clear them
                        Item {
                            visible: group.items.length > 1
                            width: parent.width
                            height: 22

                            Text {
                                x: 40
                                anchors.verticalCenter: parent.verticalCenter
                                text: group.items.length < 2 ? "" : group.open ? "Show less" : `${group.items.length - 1} more from ${group.items[0].app}`
                                color: fold.containsMouse ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11

                                MouseArea {
                                    id: fold

                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    onClicked: center.unfolded = Object.assign({}, center.unfolded, {
                                        [group.modelData.key]: !group.open
                                    })
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear"
                                color: clearing.containsMouse ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11

                                MouseArea {
                                    id: clearing

                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    onClicked: center.notifications.clearGroup(group.modelData.key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
