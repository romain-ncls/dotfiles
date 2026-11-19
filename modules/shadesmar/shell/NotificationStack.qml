// An app's notifications as a stack (NotificationCard.qml): its newest in
// front, the others folded behind it, their edges under it and their count
// on it. Unfolded, they slide out from behind it to their places and back
// in as it folds, the stack growing and shrinking with them (no glass
// fades: Hyprland's blur behind would stay whole). The popups' stacks
// (Notifications.qml) unfold upward while the pointer is on them, the
// oldest at the top, the newest at the bottom, where it was; the bell's
// (NotificationCenter.qml, `flat`) downward, its count clicked.
import QtQuick
import Quickshell

Item {
    id: stack

    required property var host
    required property string group
    property bool flat: false
    // the bell's list: each one's time, and since when they're new
    property var ago: e => ""
    property real lastSeen: 0
    property bool clickedOpen: false
    // the bell's popup closing folds them all again
    property int folds: 0
    onFoldsChanged: clickedOpen = false

    signal activated

    // the newest first; gone (the stack leaving, Notifications.qml's list),
    // the last ones, for its way out
    readonly property var current: (flat ? host.listedBy[group] : host.popupsBy[group]) ?? []
    property var kept: []
    onCurrentChanged: {
        if (current.length > 0)
            kept = current
    }
    Component.onCompleted: kept = current
    readonly property var cards: current.length > 0 ? current : kept
    readonly property bool unfolded: (flat ? clickedOpen : hover.hovered) && cards.length > 1
    readonly property int spacing: 6

    // the cards' heights, by place (the newest 0), as they say them
    property var heights: []
    function measured(i, h) {
        if (heights[i] === h)
            return
        const a = heights.slice()
        a[i] = h
        heights = a
    }
    // where a card goes, from the stack's foot (upward) or head
    function place(i) {
        if (!unfolded)
            return 0
        let d = 0
        for (let j = 0; j < i; j++)
            d += (heights[j] ?? 0) + spacing
        return d
    }
    readonly property real front: heights[0] ?? 0
    readonly property real whole: place(cards.length - 1) + (heights[cards.length - 1] ?? 0)
    // under the front one folded, its edges
    property real foot: unfolded ? 0 : 5 * Math.min(cards.length - 1, 2)
    Behavior on foot {
        enabled: Theme.speed > 0
        Ease {
            easing.bezierCurve: Theme.move
        }
    }

    implicitHeight: unfolded ? whole : front + 5 * Math.min(cards.length - 1, 2)
    Behavior on implicitHeight {
        enabled: Theme.speed > 0
        Ease {
            easing.bezierCurve: Theme.move
        }
    }

    HoverHandler {
        id: hover

        enabled: !stack.flat
    }

    Repeater {
        model: ScriptModel {
            values: stack.cards.map(e => ({ key: e.key }))
            objectProp: "key"
        }

        NotificationCard {
            id: card

            required property var modelData
            required property int index
            readonly property real offset: stack.place(index)

            host: stack.host
            key: modelData.key
            flat: stack.flat
            when: stack.ago(entry)
            marked: stack.flat && entry.time > stack.lastSeen
            width: stack.width
            z: stack.cards.length - index
            more: index === 0 && !stack.unfolded ? stack.cards.length - 1 : 0
            onUnfold: stack.clickedOpen = !stack.clickedOpen
            onActivated: stack.activated()

            // its place, sliding there; folded, those behind are hidden
            // once back under the front one (its edges stand for them)
            property real slid: offset
            Behavior on slid {
                enabled: Theme.speed > 0
                Ease {
                    id: slide

                    easing.bezierCurve: Theme.move
                }
            }
            visible: index === 0 || stack.unfolded || slide.running
            y: stack.flat ? slid : stack.height - stack.foot - slid - natural

            onNaturalChanged: stack.measured(index, natural)
            onIndexChanged: stack.measured(index, natural)
            Component.onCompleted: stack.measured(index, natural)
        }
    }
}
