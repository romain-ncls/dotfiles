// The speakers' volume: the wheel changes it, a middle click mutes. Its
// popup, as Plasma's audio applet (Meta+~ opens it too): the output and the
// microphone, their volume and mute, and which device each is.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

BarButton {
    id: volume

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property int percent: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

    // the devices, not the apps' streams
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)

    popup: "volume"
    icon: muted ? "audio-volume-muted" : percent < 34 ? "audio-volume-low" : percent < 67 ? "audio-volume-medium" : "audio-volume-high"
    label: percent + "%"
    labelColor: muted ? Theme.dim : Theme.text

    function nudge(audio, delta) {
        if (audio)
            audio.volume = Math.max(0, Math.min(1, audio.volume + (delta > 0 ? 0.05 : -0.05)))
    }

    onScrolled: delta => nudge(sink ? sink.audio : null, delta)
    onMiddleClicked: {
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted
    }

    PwObjectTracker {
        objects: [volume.sink, volume.source].concat(volume.sinks, volume.sources)
    }

    GlobalShortcut {
        appid: "shadesmar"
        name: "volume"
        description: "The sound's popup (Plasma's Meta+~)"
        onPressed: volume.bar.open = volume.bar.open === "volume" ? "" : "volume"
    }

    function name(node) {
        return node.description || node.nickname || node.name
    }

    BarPopup {
        bar: volume.bar
        from: volume
        name: "volume"

        PopupHeader {
            title: "Output"
        }

        Row {
            width: parent.width
            spacing: 10

            ListRow {
                width: 40
                icon: volume.icon
                onClicked: {
                    if (volume.sink && volume.sink.audio)
                        volume.sink.audio.muted = !volume.sink.audio.muted
                }
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100
                value: volume.sink && volume.sink.audio ? volume.sink.audio.volume : 0
                onMoved: v => {
                    if (volume.sink && volume.sink.audio)
                        volume.sink.audio.volume = v
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: volume.percent + "%"
                color: volume.muted ? Theme.dim : Theme.text
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        Repeater {
            model: volume.sinks.length > 1 ? volume.sinks : []

            ListRow {
                required property var modelData

                icon: "audio-speakers-symbolic"
                title: volume.name(modelData)
                active: modelData === volume.sink
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
        }

        PopupHeader {
            title: "Microphone"
        }

        Row {
            width: parent.width
            spacing: 10

            readonly property bool micMuted: volume.source && volume.source.audio ? volume.source.audio.muted : false

            ListRow {
                width: 40
                icon: parent.micMuted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high"
                onClicked: {
                    if (volume.source && volume.source.audio)
                        volume.source.audio.muted = !volume.source.audio.muted
                }
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100
                value: volume.source && volume.source.audio ? volume.source.audio.volume : 0
                onMoved: v => {
                    if (volume.source && volume.source.audio)
                        volume.source.audio.volume = v
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: volume.source && volume.source.audio ? Math.round(volume.source.audio.volume * 100) + "%" : ""
                color: parent.micMuted ? Theme.dim : Theme.text
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        Repeater {
            model: volume.sources.length > 1 ? volume.sources : []

            ListRow {
                required property var modelData

                icon: "audio-input-microphone-symbolic"
                title: volume.name(modelData)
                active: modelData === volume.source
                onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
    }
}
