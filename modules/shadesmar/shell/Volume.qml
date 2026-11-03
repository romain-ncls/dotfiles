// The speakers' volume: scroll to change it, click to mute.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

Item {
    id: volume

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property int percent: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    PwObjectTracker {
        objects: [volume.sink]
    }

    Row {
        id: row

        spacing: 6

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: Theme.icon
            source: Quickshell.iconPath(volume.muted ? "audio-volume-muted"
                : volume.percent < 34 ? "audio-volume-low"
                : volume.percent < 67 ? "audio-volume-medium" : "audio-volume-high")
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: volume.percent + "%"
            color: volume.muted ? Theme.dim : Theme.text
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    // Over the row, not in it: a Row sizes itself from its children.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (volume.sink && volume.sink.audio)
                volume.sink.audio.muted = !volume.sink.audio.muted
        }
        onWheel: wheel => {
            if (!volume.sink || !volume.sink.audio)
                return
            const v = volume.sink.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)
            volume.sink.audio.volume = Math.max(0, Math.min(1, v))
        }
    }
}
