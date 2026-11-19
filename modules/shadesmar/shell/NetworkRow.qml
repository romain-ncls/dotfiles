// A Wi-Fi network's row in the Network popup (Network.qml, `host`): its
// signal in a chip, lit while in use; a lock if it asks a password; a click
// connects (or asks the password, in a field under it).
import QtQuick
import Quickshell.Networking

Column {
    id: entry

    required property var host
    required property var modelData
    readonly property var n: modelData

    width: parent ? parent.width : 320

    ListRow {
        chip: true
        icon: entry.host.signalIcon(entry.n, false)
        trailingIcon: entry.host.secured(entry.n) ? Qt.resolvedUrl("icons/lock.svg") : ""
        title: entry.n.name
        active: entry.n.connected
        subtitle: entry.host.status(entry.n)
        busy: entry.n.state === ConnectionState.Connecting || entry.n.state === ConnectionState.Disconnecting
        removable: entry.n.known && !entry.n.connected
        removeLabel: "Forget"
        onClicked: entry.host.pick(entry.n)
        onRemoved: entry.n.forget()
    }

    Rectangle {
        visible: entry.host.asking === entry.n
        width: parent.width
        height: visible ? Theme.row : 0
        radius: Theme.corner
        color: Theme.slot

        TextInput {
            id: psk

            x: 12
            width: parent.width - 24 - join.width
            anchors.verticalCenter: parent.verticalCenter
            focus: entry.host.asking === entry.n
            echoMode: TextInput.Password
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.body
            clip: true
            onAccepted: join.go()
            Keys.onEscapePressed: event => {
                entry.host.asking = null
                text = ""
            }

            Text {
                visible: psk.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Password"
                color: Theme.dim
                font: psk.font
            }
        }

        Text {
            id: join

            function go() {
                if (psk.text === "")
                    return
                entry.host.tried = entry.n.name
                entry.n.connectWithPsk(psk.text)
                psk.text = ""
                entry.host.asking = null
            }

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Connect"
            color: psk.text === "" ? Theme.dim : joinArea.containsMouse ? Theme.text : Theme.accent
            font.family: Theme.font
            font.pixelSize: Theme.body
            font.weight: Font.Medium

            MouseArea {
                id: joinArea

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: join.go()
            }
        }
    }

    Connections {
        target: entry.n

        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets) {
                entry.host.fail(entry.n, entry.host.tried === entry.n.name ? "Wrong password" : "")
                entry.host.asking = entry.n
            } else {
                entry.host.fail(entry.n, "Couldn't connect")
            }
            entry.host.tried = ""
        }
    }
}
