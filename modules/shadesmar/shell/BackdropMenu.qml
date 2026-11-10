// Backdrop's menu (modules/backdrop), on a right click on the wallpaper
// (Wallpaper.qml): Hyprland's desktop has no menu of its own, so it's all
// Backdrop's. What the picture is (its title, place and credit, where it's
// from; not the picture itself, which is right there), how much it's to
// your taste, when the next one comes; Like, Dislike (another comes at
// once) and Next keep the menu open, to go through several; then its page,
// the image, the liked ones' folder. Keys: L, D, N, Escape. Through
// backdrop's CLI (the daemon's socket); when backdrop.service isn't
// running, a button starts it.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: menu

    property bool shown: false
    property var screen: null
    // where it was asked, in the screen's coordinates
    property real atX: 0
    property real atY: 0

    // backdrop info --json: null until it answers
    property var info: null
    property bool offline: false
    property string doing: ""

    readonly property bool known: info !== null && !!info.id
    readonly property bool pending: info !== null && info.pending === true
    readonly property string sourceName: !known ? "" : ({
            spotlight: "Windows Spotlight",
            bing: "Bing",
            wallhaven: "Wallhaven"
        })[info.source] ?? info.source
    readonly property string liked: Quickshell.env("HOME") + "/Pictures/Backdrop"

    function openAt(where, x, y) {
        menu.screen = where
        menu.atX = x
        menu.atY = y
        menu.shown = true
        menu.refresh()
    }
    function close() {
        menu.shown = false
    }

    function refresh() {
        if (!asking.running)
            asking.running = true
    }
    function act(verb) {
        if (doing !== "" || !known)
            return
        menu.doing = verb
        acting.command = ["backdrop", verb]
        acting.running = true
    }
    // started through Hyprland, as the launcher does: not the shell's child
    function run(args) {
        const command = args.map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ")
        Quickshell.execDetached(["hyprctl", "eval", `hl.exec_cmd([==[${command}]==])`])
        close()
    }

    function when(iso) {
        const d = new Date(iso)
        if (isNaN(d.getTime()) || d.getFullYear() < 2000)
            return ""
        const today = new Date().toDateString() === d.toDateString()
        return today ? Qt.formatTime(d, "HH:mm") : Qt.formatDateTime(d, "ddd HH:mm")
    }

    Process {
        id: asking

        command: ["backdrop", "info", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    menu.info = JSON.parse(text)
                    menu.offline = false
                } catch (e) {
                    menu.info = null
                    menu.offline = true
                }
            }
        }
    }
    Process {
        id: acting

        onExited: {
            menu.doing = ""
            menu.refresh()
        }
    }
    // a picture on its way (the pool was empty), or the daemon starting:
    // asked again until it's there
    Timer {
        running: menu.shown && (menu.pending || menu.offline)
        interval: 1500
        repeat: true
        onTriggered: menu.refresh()
    }

    // The desktop it's about covered: another workspace (Meta+D's peek
    // ending too), a window opening.
    Connections {
        target: Hyprland
        enabled: menu.shown

        function onRawEvent(event) {
            if (["workspacev2", "activespecial", "openwindow"].includes(event.name))
                menu.close()
        }
    }

    PanelWindow {
        id: window

        screen: menu.screen
        visible: menu.shown && menu.screen !== null
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // a click elsewhere closes it
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: menu.close()
        }

        Rectangle {
            id: card

            // from where it was asked, turned back at the screen's edges; on
            // whole pixels (a pointer's are fractions), for sharp text
            x: Math.round(Math.max(8, menu.atX + width + 8 > parent.width ? menu.atX - width : menu.atX))
            y: Math.round(Math.max(8, menu.atY + height + 8 > parent.height ? menu.atY - height : menu.atY))
            width: 340
            height: Math.ceil(column.implicitHeight)
            radius: Theme.radius + 4
            color: Theme.popup
            border.width: 1
            border.color: Theme.outline

            opacity: 0
            scale: 0.97
            transformOrigin: menu.atY + height + 8 > parent.height ? Item.Bottom : Item.Top
            states: State {
                when: window.visible
                PropertyChanges {
                    card.opacity: 1
                    card.scale: 1
                }
            }
            transitions: Transition {
                to: "*"
                NumberAnimation {
                    properties: "opacity,scale"
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            // clicks inside stay inside
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Item {
                focus: menu.shown
                Keys.onEscapePressed: menu.close()
                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_L:
                        if (menu.known && !menu.info.liked)
                            menu.act("like")
                        break
                    case Qt.Key_D:
                        menu.act("dislike")
                        break
                    case Qt.Key_N:
                    case Qt.Key_Right:
                        menu.act("next")
                        break
                    default:
                        return
                    }
                    event.accepted = true
                }
            }

            Column {
                id: column

                width: parent.width

                Column {
                    x: 12
                    width: parent.width - 24
                    topPadding: 14
                    bottomPadding: 8
                    spacing: 12

                    // what it is
                    Column {
                        x: 4
                        width: parent.width - 8
                        spacing: 2

                        Text {
                            width: parent.width
                            text: menu.offline ? "Backdrop isn't running" : menu.pending ? "Fetching another one…" : menu.known ? menu.info.title : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: menu.offline ? "Its pictures stop changing until it's back" : menu.known && !menu.pending ? menu.info.place ?? "" : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }

                    // where it's from, its credit; how it scores, when the
                    // next one comes
                    Column {
                        visible: menu.known && !menu.pending
                        x: 4
                        width: parent.width - 8
                        spacing: 2

                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: menu.known ? [menu.sourceName, menu.info.credit ?? ""].filter(s => s).join("  ·  ") : ""
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                        Text {
                            width: parent.width
                            text: !menu.known ? "" : [`${Math.round(100 * menu.info.like)}% to your taste`, menu.when(menu.info.next) ? `the next one at ${menu.when(menu.info.next)}` : ""].filter(s => s).join("  ·  ")
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }

                    // Like, Dislike, Next; or, the daemon down, Start
                    Row {
                        id: buttons

                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: menu.offline ? [
                                {
                                    verb: "start",
                                    text: "Start Backdrop",
                                    icon: "media-playback-start"
                                }
                            ] : [
                                {
                                    verb: "like",
                                    text: menu.known && menu.info.liked ? "Liked" : "Like",
                                    icon: "love"
                                },
                                {
                                    verb: "dislike",
                                    text: "Dislike",
                                    icon: "dialog-cancel"
                                },
                                {
                                    verb: "next",
                                    text: "Next",
                                    icon: "media-skip-forward"
                                }
                            ]

                            Rectangle {
                                id: button

                                required property var modelData
                                readonly property bool lit: modelData.verb === "like" && menu.known && menu.info.liked
                                readonly property bool enabled: modelData.verb === "start" || (menu.known && !menu.pending && menu.doing === "" && !lit)

                                width: (buttons.width - buttons.spacing * (menu.offline ? 0 : 2)) / (menu.offline ? 1 : 3)
                                height: 56
                                radius: 10
                                color: lit ? Theme.alpha(Theme.accent, 0.16) : press.containsMouse && enabled ? Theme.alpha(Theme.text, 0.14) : Theme.alpha(Theme.text, 0.07)
                                opacity: enabled || lit ? 1 : 0.5

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        implicitSize: 20
                                        source: Quickshell.iconPath(button.modelData.icon, "image-missing")
                                        // liked: the heart in the accent
                                        layer.enabled: button.lit
                                        layer.effect: MultiEffect {
                                            colorization: 1
                                            colorizationColor: Theme.accent
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: menu.doing === button.modelData.verb ? "…" : button.modelData.text
                                        color: button.lit ? Theme.accent : Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        font.weight: button.lit ? Font.DemiBold : Font.Normal
                                    }
                                }

                                MouseArea {
                                    id: press

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (!button.enabled)
                                            return
                                        if (button.modelData.verb === "start") {
                                            Quickshell.execDetached(["systemctl", "--user", "start", "backdrop.service"])
                                            menu.offline = false
                                            menu.info = null
                                            menu.refresh()
                                        } else {
                                            menu.act(button.modelData.verb)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // its page, the image, the liked ones
                    Column {
                        width: parent.width

                        ListRow {
                            visible: menu.known && !!menu.info.infoUrl
                            icon: "help-about"
                            title: "About this picture"
                            subtitle: visible ? menu.info.infoUrl.replace(/^https?:\/\/(www\.)?/, "").replace(/\/.*$/, "") : ""
                            onClicked: menu.run(["xdg-open", menu.info.infoUrl])
                        }
                        ListRow {
                            visible: menu.known && !!menu.info.file
                            icon: "view-preview"
                            title: "Open the image"
                            onClicked: menu.run(["xdg-open", menu.info.file])
                        }
                        ListRow {
                            icon: "folder-pictures"
                            title: "Liked pictures"
                            subtitle: "~/Pictures/Backdrop"
                            onClicked: menu.run(["xdg-open", menu.liked])
                        }
                    }
                }
            }
        }
    }
}
