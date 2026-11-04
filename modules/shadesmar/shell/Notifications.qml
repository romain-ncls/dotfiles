// Notifications, where Plasma has them: popups in the bottom right corner of
// the bar's screen, above the bar, the newest at the bottom. A click runs
// the notification's default action (Discord: its channel) or dismisses it,
// a right click dismisses it; its other actions are buttons. After their
// timeout (5 s when the app leaves it to us; not while the pointer is on
// them; critical ones stay) they go to the history, the bar's bell
// (NotificationCenter.qml), still there for their app and their actions,
// until dismissed. Do not disturb: no popups but critical ones.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: notifications

    property var screen
    property bool dnd: false
    // the ones in the history since the bell was last opened
    property int unread: 0

    // by notification id: shown as a popup; when it came
    property var popups: ({})
    property var times: ({})

    readonly property var shown: server.trackedNotifications.values.filter(n => popups[n.id])
    // the newest first
    readonly property var history: server.trackedNotifications.values.filter(n => !popups[n.id]).reverse()

    function critical(n) {
        return n.urgency === NotificationUrgency.Critical
    }

    // From its popup to the history.
    function hide(n) {
        if (!popups[n.id])
            return
        const p = Object.assign({}, popups)
        delete p[n.id]
        popups = p
        unread++
    }

    function clear() {
        for (const n of history)
            n.dismiss()
        unread = 0
    }

    // An image that's a theme icon's name (image://icon/…) is an icon, given
    // a fallback when the theme lacks it.
    function picture(n) {
        return n.image.startsWith("image://icon/") ? "" : n.image
    }
    function icon(n) {
        const entry = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        const name = n.image.startsWith("image://icon/") ? n.image.slice(13) : n.appIcon || (entry ? entry.icon : "")
        if (name.startsWith("/") || name.startsWith("file:"))
            return name
        return Quickshell.iconPath(name, "dialog-information")
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true
            notifications.times = Object.assign({}, notifications.times, { [n.id]: Date.now() })
            if (!notifications.dnd || notifications.critical(n))
                notifications.popups = Object.assign({}, notifications.popups, { [n.id]: true })
            else
                notifications.unread++
        }
    }

    PanelWindow {
        screen: notifications.screen
        visible: notifications.shown.length > 0
        anchors {
            bottom: true
            right: true
        }
        margins {
            bottom: 8
            right: 8
        }
        exclusiveZone: 0
        implicitWidth: 380
        implicitHeight: column.implicitHeight
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-notifications"

        Column {
            id: column

            width: parent.width
            spacing: 8

            Repeater {
                model: notifications.shown

                Rectangle {
                    id: popup

                    required property var modelData
                    readonly property var n: modelData
                    readonly property bool critical: notifications.critical(n)
                    // ms; 0: until dismissed
                    readonly property int timeout: critical ? 0 : n.expireTimeout > 0 ? n.expireTimeout * 1000 : n.expireTimeout === 0 ? 0 : 5000
                    readonly property var defaultAction: n.actions.find(a => a.identifier === "default") ?? null
                    readonly property string picture: notifications.picture(n)
                    readonly property string icon: notifications.icon(n)

                    width: column.width
                    height: content.implicitHeight + 24
                    radius: 10
                    color: Theme.bar
                    border.width: critical ? 2 : 0
                    border.color: Theme.warn

                    Timer {
                        running: popup.timeout > 0 && !hover.containsMouse
                        interval: popup.timeout
                        onTriggered: notifications.hide(popup.n)
                    }

                    MouseArea {
                        id: hover

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: event => {
                            if (event.button === Qt.LeftButton && popup.defaultAction)
                                popup.defaultAction.invoke()
                            else
                                popup.n.dismiss()
                        }
                    }

                    Row {
                        id: content

                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 12

                        // the notification's image (a contact's picture), else the app's icon
                        Item {
                            width: 40
                            height: 40

                            Image {
                                id: picture

                                visible: popup.picture !== ""
                                anchors.fill: parent
                                source: popup.picture
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(80, 80)
                            }

                            IconImage {
                                visible: !picture.visible
                                anchors.centerIn: parent
                                implicitSize: 32
                                source: popup.icon
                            }
                        }

                        Column {
                            width: parent.width - 52
                            spacing: 3

                            Item {
                                width: parent.width
                                height: app.implicitHeight

                                Text {
                                    id: app

                                    width: parent.width - 20
                                    text: popup.n.appName
                                    elide: Text.ElideRight
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                }

                                Text {
                                    anchors.right: parent.right
                                    text: "✕"
                                    color: close.containsMouse ? Theme.text : Theme.dim
                                    font.pixelSize: 12

                                    MouseArea {
                                        id: close

                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        onClicked: popup.n.dismiss()
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: popup.n.summary
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: popup.n.body
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                maximumLineCount: 5
                                elide: Text.ElideRight
                                color: Theme.text
                                linkColor: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 13
                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }

                            // the other actions
                            Row {
                                visible: popup.n.actions.some(a => a.identifier !== "default")
                                topPadding: 6
                                spacing: 6

                                Repeater {
                                    model: popup.n.actions.filter(a => a.identifier !== "default")

                                    Rectangle {
                                        required property var modelData

                                        width: label.implicitWidth + 20
                                        height: 26
                                        radius: 6
                                        color: button.containsMouse ? Theme.accent : Theme.slot

                                        Text {
                                            id: label

                                            anchors.centerIn: parent
                                            text: parent.modelData.text
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: button

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: parent.modelData.invoke()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
