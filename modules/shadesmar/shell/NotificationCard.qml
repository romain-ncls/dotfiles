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
    // in the bell's list: on a plate, not glass; its time (`when`); new since
    // the last look (`marked`)
    property bool flat: false
    property string when: ""
    property bool marked: false
    // the count on it clicked (the bell's list unfolds its stack)
    signal unfold
    // clicked, after its action ran (the bell's popup closes)
    signal activated
    // its face's height, for its stack (NotificationStack.qml)
    readonly property real natural: face.height
    readonly property int pad: flat ? 10 : Theme.pad

    // the copy, by its key: what the list has now; gone from it (a
    // transient one, leaving), the last it had, for its way out
    readonly property var found: host.byKey[key] ?? null
    property var kept: null
    onFoundChanged: {
        if (found)
            kept = found
    }
    Component.onCompleted: kept = found
    readonly property var entry: found ?? kept ?? ({
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

    implicitHeight: face.height + 5 * Math.min(more, 2)

    // the edges of the folded ones, under it: they slide out from under it
    // as it folds, back under as it opens
    Repeater {
        model: 2

        Rectangle {
            id: edge

            required property int index
            property real out: card.more > index ? 1 : 0

            Behavior on out {
                enabled: Theme.speed > 0
                Ease {
                    easing.bezierCurve: Theme.move
                }
            }

            visible: out > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.height - radius + 5 * (index + 1) * out
            z: -1 - index
            width: face.width - 16 * (index + 1)
            height: radius * 2
            radius: face.radius
            color: card.flat ? Theme.plateGlass : Theme.reading
            border.width: card.flat ? 0 : 1
            border.color: Theme.outline
        }
    }

    Rectangle {
        id: face

        width: parent.width
        height: content.implicitHeight + 2 * card.pad
        radius: card.flat ? Theme.plateCorner : Theme.surfaceCorner
        color: card.flat ? Theme.plateGlass : Theme.reading
        border.width: card.entry.critical ? 2 : card.flat ? 0 : 1
        border.color: card.entry.critical ? Theme.warn : Theme.outline
        scale: hit.pressed ? Theme.sunk(width) : 1
        Squish on scale {}

        MouseArea {
            id: hit

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: event => {
                if (event.button === Qt.LeftButton) {
                    card.host.activate(card.entry)
                    card.activated()
                }
                else
                    card.host.dismiss(card.entry)
            }
        }

        Row {
            id: content

            x: card.pad
            y: card.pad
            width: parent.width - 2 * card.pad
            spacing: card.pad

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

                    // its app, how many times, when; a dot if it's new
                    Row {
                        id: app

                        width: parent.width - 20 - (others.visible ? others.width + 8 : 0)
                        spacing: 6

                        Rectangle {
                            visible: card.marked
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent
                        }

                        Text {
                            width: Math.min(implicitWidth, app.width - (card.marked ? 12 : 0))
                            text: [card.entry.app + (card.entry.count > 1 ? `  ×${card.entry.count}` : ""), card.when].filter(s => s !== "").join("  ·  ")
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.small
                        }
                    }

                    // how many more behind it; in the bell's list, a click
                    // unfolds them
                    Rectangle {
                        id: others

                        visible: card.more > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        width: count.implicitWidth + 12
                        height: 18
                        radius: height / 2
                        color: card.flat && unfolding.containsMouse ? Theme.faceHover : Theme.face
                        Fade on color {}
                        scale: unfolding.pressed ? Theme.sunk(width) : 1
                        Squish on scale {}

                        Text {
                            id: count

                            anchors.centerIn: parent
                            text: `+${card.more}`
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: Theme.small
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: unfolding

                            enabled: card.flat
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            onClicked: card.unfold()
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        text: "✕"
                        color: close.containsMouse ? Theme.text : Theme.dim
                        font.pixelSize: Theme.small

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
                    font.pixelSize: Theme.body
                    font.weight: Font.Medium
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
                    font.pixelSize: Theme.body
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
                            height: 28
                            radius: Theme.corner
                            color: button.containsMouse ? Theme.faceHover : Theme.face
                            Fade on color {}
                            // pressed, it sinks, and comes back past its size (Squish.qml)
                            scale: button.pressed ? Theme.sunk(width) : 1
                            Squish on scale {}

                            Text {
                                id: label

                                anchors.centerIn: parent
                                text: parent.modelData.text
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.body
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
