// An app's popups (Notifications.qml): its newest in front, the others
// folded behind it (NotificationCard.qml); the pointer on the stack unfolds
// it, the oldest at the top, the newest at the bottom, where it was.
import QtQuick
import Quickshell

Column {
    id: stack

    required property var host
    required property string group
    // the newest first; gone (the stack leaving, Notifications.qml's
    // list), the last ones, for its way out
    readonly property var current: host.popupsBy[group] ?? []
    property var kept: []
    onCurrentChanged: {
        if (current.length > 0)
            kept = current
    }
    Component.onCompleted: kept = current
    readonly property var cards: current.length > 0 ? current : kept
    readonly property string front: cards.length > 0 ? cards[0].key : ""
    readonly property bool open: hover.hovered && cards.length > 1

    spacing: 6

    HoverHandler {
        id: hover
    }

    Repeater {
        model: ScriptModel {
            values: stack.cards.map(e => ({ key: e.key })).reverse()
            objectProp: "key"
        }

        NotificationCard {
            required property var modelData

            host: stack.host
            key: modelData.key
            width: stack.width
            visible: stack.open || key === stack.front
            more: stack.open ? 0 : stack.cards.length - 1
        }
    }
}
