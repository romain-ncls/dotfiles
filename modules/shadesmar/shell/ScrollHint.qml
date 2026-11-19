// That a list scrolls, said over it (Scroller.qml's, a ListView's): its
// edge fades where there's more (the top too, once scrolled), and a thin
// bar shows on the right while it moves or the pointer is on it, a moment
// as it opens too, as macOS's. The fades are the surface's color over the
// list (`color`: the popup's glass, or a plate over it).
import QtQuick

Item {
    id: hint

    required property Flickable target
    property color color: Theme.reading
    readonly property bool scrolls: target.contentHeight > target.height + 1

    component Edge: Rectangle {
        id: edge

        property bool upper: false
        property bool shown: false

        width: hint.width
        height: 28
        opacity: shown ? 1 : 0
        gradient: Gradient {
            GradientStop {
                position: 0
                color: edge.upper ? hint.color : Theme.alpha(hint.color, 0)
            }
            GradientStop {
                position: 1
                color: edge.upper ? Theme.alpha(hint.color, 0) : hint.color
            }
        }

        // coming, a moment; at the end, gone at once
        Behavior on opacity {
            id: coming

            enabled: Theme.speed > 0
            NumberAnimation {
                duration: coming.targetValue > 0.5 ? Theme.fast : 0
            }
        }
    }

    Edge {
        upper: true
        shown: hint.scrolls && !hint.target.atYBeginning
    }

    Edge {
        y: hint.height - height
        shown: hint.scrolls && !hint.target.atYEnd
    }

    HoverHandler {
        id: hover
    }

    // the bar: as tall as the part seen, where it is
    Rectangle {
        x: hint.width - width - 2
        y: 4 + (hint.height - 8 - height) * Math.max(0, Math.min(1, hint.target.contentY / Math.max(1, hint.target.contentHeight - hint.target.height)))
        width: 4
        height: Math.max(24, (hint.height - 8) * hint.target.height / Math.max(1, hint.target.contentHeight))
        radius: width / 2
        color: Theme.alpha(Theme.textColor, 0.35)
        visible: hint.scrolls
        opacity: hint.target.moving || hover.hovered || opening.running ? 1 : 0

        Behavior on opacity {
            enabled: Theme.speed > 0
            NumberAnimation {
                duration: Theme.slow
            }
        }

        Timer {
            id: opening

            interval: 900
            running: hint.scrolls && hint.visible
        }
    }
}
