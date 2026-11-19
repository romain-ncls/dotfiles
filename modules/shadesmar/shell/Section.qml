// A group of a popup's rows (iOS's grouped lists): its name above
// (SectionLabel.qml), its rows on a plate. With `folds`, its name unfolds
// and folds it, a chevron turning, the plate opening to its rows' height.
import QtQuick

Column {
    id: section

    property string title: ""
    property string action: ""
    property bool folds: false
    property bool open: true
    // a count after the name, folded (OTHER NETWORKS 7)
    property int count: -1
    default property alias rows: rows.data

    signal acted

    width: parent ? parent.width : 320
    spacing: 2

    SectionLabel {
        visible: section.title !== ""
        text: section.title + (section.folds && section.count >= 0 ? `  ${section.count}` : "")
        action: section.action
        folds: section.folds
        open: section.open
        onActed: section.acted()
        onToggled: section.open = !section.open
    }

    Rectangle {
        width: parent.width
        height: section.open ? rows.implicitHeight + 2 * Theme.inset : 0
        radius: Theme.plateCorner
        color: Theme.plate
        clip: true
        visible: height > 0

        Behavior on height {
            enabled: Theme.speed > 0
            Ease {
                easing.bezierCurve: Theme.move
            }
        }

        Column {
            id: rows

            x: Theme.inset
            y: Theme.inset
            width: parent.width - 2 * Theme.inset
            opacity: section.open ? 1 : 0

            Behavior on opacity {
                enabled: Theme.speed > 0
                NumberAnimation {
                    duration: Theme.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.fade
                }
            }
        }
    }
}
