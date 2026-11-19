// One of a few (the power profile): side by side on a plate, the one
// chosen lit in the accent, the light sliding to the one picked; under the
// pointer one lightens, pressed it sinks.
import QtQuick

Rectangle {
    id: segmented

    // [{ icon, label }]
    property var options: []
    property int current: 0
    // its padding: 0 on a plate (Section.qml), which has its own
    property int inset: Theme.inset
    readonly property real cell: (width - 2 * segmented.inset) / Math.max(1, options.length)

    signal picked(int index)

    width: parent ? parent.width : 320
    height: 36 + 2 * inset
    radius: Theme.plateCorner
    color: Theme.plate

    Rectangle {
        visible: segmented.current >= 0
        x: segmented.inset + segmented.current * segmented.cell
        y: segmented.inset
        width: segmented.cell
        height: segmented.height - 2 * segmented.inset
        radius: Theme.corner
        color: Theme.accent

        Behavior on x {
            enabled: Theme.speed > 0
            Ease {
                easing.bezierCurve: Theme.move
            }
        }
    }

    Row {
        x: segmented.inset
        y: segmented.inset

        Repeater {
            model: segmented.options

            Item {
                id: option

                required property var modelData
                required property int index
                readonly property bool lit: index === segmented.current

                width: segmented.cell
                height: segmented.height - 2 * segmented.inset
                scale: area.pressed ? Theme.sunk(width) : 1
                Squish on scale {}

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.corner
                    color: !option.lit && area.containsMouse ? Theme.hover : Theme.none
                    Fade on color {}
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        source: option.modelData.icon
                        color: option.lit ? Theme.accentText : Theme.text
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: option.modelData.label
                        color: option.lit ? Theme.accentText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.body
                        font.weight: option.lit ? Font.Medium : Font.Normal
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: segmented.picked(option.index)
                }
            }
        }
    }
}
