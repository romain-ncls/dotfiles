// The OSD, as Plasma's: a pill at the bottom of the focused screen, for a
// moment after a change. The speakers' volume and the microphone's mute
// come from PipeWire, whatever changed them; the brightness from its binds
// (modules/hyprland's binds.lua, after brightnessctl); a player's volume
// and messages from spanreed, which serves Plasma's OSD service for
// backdrop and spotify-vol (pkg/spanreed).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: osd

    property string icon: ""
    property int value: -1 // a percentage, or -1 for a message
    property string label: ""
    property bool shown: false

    function show(icon, value, label) {
        osd.icon = icon
        osd.value = value
        osd.label = label
        shown = true
        hide.restart()
    }

    Timer {
        id: hide

        interval: 1500
        onTriggered: osd.shown = false
    }

    // PipeWire's first values aren't changes.
    property bool ready: false

    Timer {
        running: true
        interval: 2000
        onTriggered: osd.ready = true
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [osd.sink, osd.source]
    }

    Connections {
        target: osd.sink && osd.sink.audio ? osd.sink.audio : null

        function onVolumeChanged() {
            osd.speakers()
        }
        function onMutedChanged() {
            osd.speakers()
        }
    }

    Connections {
        target: osd.source && osd.source.audio ? osd.source.audio : null

        function onMutedChanged() {
            if (!osd.ready)
                return
            const muted = osd.source.audio.muted
            osd.show(muted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high", -1, muted ? "Microphone muted" : "Microphone on")
        }
    }

    function speakers() {
        if (!ready)
            return
        const a = sink.audio
        const p = Math.round(a.volume * 100)
        show(a.muted ? "audio-volume-muted" : p < 34 ? "audio-volume-low" : p < 67 ? "audio-volume-medium" : "audio-volume-high", a.muted ? 0 : p, "")
    }

    // qs -c shadesmar ipc call osd …
    IpcHandler {
        target: "osd"

        function brightness(percent: int): void {
            osd.show(percent < 50 ? "brightness-low" : "brightness-high", percent, "")
        }
        function text(icon: string, text: string): void {
            osd.show(icon, -1, text)
        }
        function player(percent: int, player: string, icon: string): void {
            osd.show(icon, percent, player)
        }
    }

    PanelWindow {
        screen: {
            const m = Hyprland.focusedMonitor
            return Quickshell.screens.find(s => m && s.name === m.name) ?? Quickshell.screens[0]
        }
        visible: osd.shown
        anchors.bottom: true
        margins.bottom: 72
        implicitWidth: 320
        implicitHeight: 52
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-osd"
        // clicks go through
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.bar
            border.width: 1
            border.color: Theme.outline

            IconImage {
                id: glyph

                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 24
                source: Quickshell.iconPath(osd.icon, "dialog-information")
            }

            // a percentage: a bar and its number, under the player's name if any
            Item {
                visible: osd.value >= 0
                anchors.left: glyph.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height

                Text {
                    id: player

                    visible: osd.label !== ""
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    text: osd.label
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11
                }

                Rectangle {
                    id: track

                    anchors.left: parent.left
                    anchors.right: number.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: player.visible ? 6 : 0
                    height: 6
                    radius: 3
                    color: Theme.slot

                    Rectangle {
                        width: parent.width * Math.min(osd.value, 100) / 100
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: 80
                            }
                        }
                    }
                }

                Text {
                    id: number

                    anchors.right: parent.right
                    anchors.verticalCenter: track.verticalCenter
                    width: 36
                    horizontalAlignment: Text.AlignRight
                    text: osd.value
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }

            // a message
            Text {
                visible: osd.value < 0
                anchors.left: glyph.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: osd.label
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }
}
