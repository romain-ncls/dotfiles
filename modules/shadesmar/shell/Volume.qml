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

    // A device by its short name (node.nick: "HDMI 3", a monitor's, the
    // headset's), the card's own kind of output under it when it says more
    // ("HDMI / DisplayPort 2 Output"); else its description.
    function name(node) {
        return node.nickname || node.description || node.name
    }
    function detail(node) {
        const kind = node.properties["device.profile.description"] || ""
        return node.nickname && kind !== node.nickname ? kind : ""
    }
    function kindIcon(node, input) {
        const text = `${node.description} ${node.nickname}`
        if (input)
            return "audio-input-microphone-symbolic"
        if (/HDMI|DisplayPort/.test(text))
            return "video-display-symbolic"
        if (/Headphones/.test(text))
            return "audio-headphones-symbolic"
        if (node.properties["device.bus"] === "usb")
            return "audio-headset-symbolic"
        return "audio-speakers-symbolic"
    }
    // Easy Effects' own sink, in its tray icon's shape
    function effects(node) {
        return /easyeffects/i.test(node.name)
    }

    BarPopup {
        bar: volume.bar
        from: volume
        name: "volume"

        SectionLabel {
            text: "Output"
        }

        SliderRow {
            icon: volume.icon
            value: volume.sink && volume.sink.audio ? volume.sink.audio.volume : 0
            off: volume.muted
            onClicked: {
                if (volume.sink && volume.sink.audio)
                    volume.sink.audio.muted = !volume.sink.audio.muted
            }
            onMoved: v => {
                if (volume.sink && volume.sink.audio)
                    volume.sink.audio.volume = v
            }
        }

        Repeater {
            model: volume.sinks.length > 1 ? volume.sinks : []

            ListRow {
                required property var modelData

                icon: volume.effects(modelData) ? "" : volume.kindIcon(modelData, false)
                lineIcon: volume.effects(modelData) ? Qt.resolvedUrl("icons/sliders-vertical.svg") : ""
                title: volume.name(modelData)
                subtitle: volume.detail(modelData)
                active: modelData === volume.sink
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
        }

        SectionLabel {
            text: "Microphone"
        }

        SliderRow {
            readonly property bool micMuted: volume.source && volume.source.audio ? volume.source.audio.muted : false

            icon: micMuted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high"
            value: volume.source && volume.source.audio ? volume.source.audio.volume : 0
            off: micMuted
            onClicked: {
                if (volume.source && volume.source.audio)
                    volume.source.audio.muted = !volume.source.audio.muted
            }
            onMoved: v => {
                if (volume.source && volume.source.audio)
                    volume.source.audio.volume = v
            }
        }

        Repeater {
            model: volume.sources.length > 1 ? volume.sources : []

            ListRow {
                required property var modelData

                icon: volume.kindIcon(modelData, true)
                title: volume.name(modelData)
                subtitle: volume.detail(modelData)
                active: modelData === volume.source
                onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
        }
    }
}
