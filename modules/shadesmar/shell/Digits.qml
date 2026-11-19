// Text with a number that rolls, as Apple's numeric text: each digit that
// changes goes out upward as the new one comes up from under it (downward,
// the number falling); the rest just changes. The digits are all as wide
// (Theme.qml), so what's around them stays put.
import QtQuick

Row {
    id: digits

    property string text: ""
    property color color: Theme.text
    property int size: Theme.body
    property int weight: Font.Normal
    // changing without rolling (a read-out coming up with its new value)
    property bool still: false

    // which way they roll: the number's digits, read as one, compared
    property int way: 1
    property real value: NaN
    onTextChanged: {
        const v = parseInt(text.replace(/\D/g, ""))
        if (!isNaN(v) && !isNaN(value) && v !== value)
            way = v > value ? 1 : -1
        value = v
        // a place for each character, counted from the right: the units
        // keep theirs as the number grows a digit
        while (places.count < text.length)
            places.append({})
        while (places.count > text.length)
            places.remove(places.count - 1)
    }
    Component.onCompleted: {
        value = parseInt(text.replace(/\D/g, ""))
        for (let i = 0; i < text.length; i++)
            places.append({})
        ready = true
    }
    property bool ready: false

    layoutDirection: Qt.RightToLeft

    Repeater {
        model: ListModel {
            id: places
        }

        Item {
            id: place

            required property int index
            readonly property string char: digits.text.charAt(digits.text.length - 1 - index)
            property string shown: ""
            readonly property real reach: Math.round(digits.size * 0.6)

            implicitWidth: now.implicitWidth
            implicitHeight: now.implicitHeight

            onCharChanged: roll()
            // a digit more (9 to 10): it comes up too
            Component.onCompleted: {
                shown = char
                if (digits.ready && /\d/.test(char) && Theme.speed > 0 && !digits.still)
                    turn.restart()
            }

            function roll() {
                if (char === shown)
                    return
                const digit = /\d/.test(char) && /\d/.test(shown)
                was.text = digit ? shown : ""
                shown = char
                if (digit && Theme.speed > 0 && digits.visible && !digits.still)
                    turn.restart()
                else
                    turn.complete()
            }

            Text {
                id: now

                text: place.shown
                color: digits.color
                font.family: Theme.font
                font.pixelSize: digits.size
                font.weight: digits.weight
                font.features: {
                    "tnum": 1
                }
            }

            Text {
                id: was

                opacity: 0
                color: digits.color
                font: now.font
            }

            ParallelAnimation {
                id: turn

                NumberAnimation {
                    target: now
                    property: "y"
                    from: digits.way * place.reach
                    to: 0
                    duration: Theme.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.out
                }
                NumberAnimation {
                    target: now
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Theme.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.fade
                }
                NumberAnimation {
                    target: was
                    property: "y"
                    from: 0
                    to: -digits.way * place.reach
                    duration: Theme.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.out
                }
                NumberAnimation {
                    target: was
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Theme.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.fade
                }
            }
        }
    }
}
