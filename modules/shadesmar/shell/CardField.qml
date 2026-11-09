// A field of a card (BarCard): a PIN, a password, a code; its hint while
// it's empty. Enter is accepted.
import QtQuick

FocusScope {
    id: field

    property alias text: input.text
    property string hint: ""
    property bool secret: false
    property bool digits: false
    property int maxLength: 256

    signal accepted

    width: parent ? parent.width : 0
    height: 36

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.slot
    }

    TextInput {
        id: input

        x: 10
        width: parent.width - 20
        anchors.verticalCenter: parent.verticalCenter
        focus: true
        clip: true
        echoMode: field.secret ? TextInput.Password : TextInput.Normal
        maximumLength: field.maxLength
        inputMethodHints: field.digits ? Qt.ImhDigitsOnly : Qt.ImhNone
        validator: RegularExpressionValidator {
            regularExpression: field.digits ? /[0-9]*/ : /.*/
        }
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 13
        onAccepted: field.accepted()

        Text {
            visible: input.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: field.hint
            color: Theme.dim
            font: input.font
        }
    }
}
