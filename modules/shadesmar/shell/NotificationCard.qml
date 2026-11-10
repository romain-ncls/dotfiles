// A notification's popup (Notifications.qml): its picture or its app's
// icon, its app, its words, the file it's about as a picture, its buttons
// (the file's, then the app's own while the app keeps the notification). In
// front of a folded stack (NotificationStack.qml), the edges of the others
// under it and their count on it.
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: card

    required property var host
    required property string key
    // the others behind it, folded
    property int more: 0

    // the copy, by its key: what the list has now (gone: blank, for the
    // moment the card has left)
    readonly property var entry: host.byKey[key] ?? ({
            app: "",
            icon: "",
            picture: "",
            summary: "",
            body: "",
            files: [],
            critical: false,
            count: 1
        })
    readonly property var n: host.live[key] ?? null
    readonly property string file: entry.files.length > 0 ? entry.files[0] : ""
    readonly property bool openable: file !== "" && host.kept(file)
    // its buttons: the file's, then the app's other actions
    readonly property var buttons: [...(openable ? [
                {
                    text: "Open",
                    run: () => host.open(entry, file)
                },
                {
                    text: "Show in Files",
                    run: () => host.reveal(entry, file)
                }
            ] : []), ...(n ? n.actions.filter(a => a.identifier !== "default").map(a => ({
                    text: a.text,
                    run: () => host.invoke(entry, a)
                })) : [])]

    implicitHeight: face.height + (more > 1 ? 10 : more > 0 ? 5 : 0)

    // the edges of the folded ones, under it
    Repeater {
        model: Math.min(card.more, 2)

        Rectangle {
            required property int index

            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height - radius + 5 * (index + 1)
            z: -1 - index
            width: face.width - 16 * (index + 1)
            height: radius * 2
            radius: face.radius
            color: Theme.bar
            border.width: 1
            border.color: Theme.outline
        }
    }

    Rectangle {
        id: face

        width: parent.width
        height: content.implicitHeight + 24
        radius: 10
        color: Theme.bar
        border.width: card.entry.critical ? 2 : 1
        border.color: card.entry.critical ? Theme.warn : Theme.outline

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: event => {
                if (event.button === Qt.LeftButton)
                    card.host.activate(card.entry)
                else
                    card.host.dismiss(card.entry)
            }
        }

        Row {
            id: content

            x: 12
            y: 12
            width: parent.width - 24
            spacing: 12

            // the notification's image (a contact's picture), else the app's
            // icon; the image may be gone with the app's notification
            Item {
                width: 40
                height: 40

                Image {
                    id: picture

                    visible: status === Image.Ready
                    anchors.fill: parent
                    source: card.entry.picture
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(80, 80)
                }

                IconImage {
                    visible: !picture.visible
                    anchors.centerIn: parent
                    implicitSize: 32
                    source: card.entry.icon
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

                        width: parent.width - 20 - (others.visible ? others.width + 8 : 0)
                        text: card.entry.app + (card.entry.count > 1 ? `  ×${card.entry.count}` : "")
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }

                    // how many more behind it
                    Rectangle {
                        id: others

                        visible: card.more > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        width: count.implicitWidth + 10
                        height: 15
                        radius: 7.5
                        color: Theme.slot

                        Text {
                            id: count

                            anchors.centerIn: parent
                            text: `+${card.more}`
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
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
                            onClicked: card.host.dismiss(card.entry)
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: card.entry.summary
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
                    text: card.entry.body
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

                // the file, as a picture (a screenshot); outlined, a dark
                // shot on the dark popup
                Item {
                    visible: preview.status === Image.Ready
                    width: parent.width
                    height: preview.paintedHeight + 6

                    Image {
                        id: preview

                        y: 6
                        width: parent.width
                        height: implicitWidth > 0 ? Math.min(180, width * implicitHeight / implicitWidth) : 0
                        source: card.file
                        sourceSize.width: 2 * width
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignLeft
                    }

                    Rectangle {
                        y: 6
                        width: preview.paintedWidth
                        height: preview.paintedHeight
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.outline
                    }
                }

                // the file's buttons and the other actions
                Row {
                    visible: card.buttons.length > 0
                    topPadding: 6
                    spacing: 6

                    Repeater {
                        model: card.buttons

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
                                onClicked: parent.modelData.run()
                            }
                        }
                    }
                }
            }
        }
    }
}
