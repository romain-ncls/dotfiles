// The bar: the desktops and Claude Code's limits on the left; a
// recording's dot, the tray, the clipboard, the notifications, the network,
// Bluetooth, the sound, the battery and the clock on the right. Their
// popups open above them, one at a time (`open`; qs -c shadesmar ipc call
// bar open <name>). Docked across the screen in lumar's flush layout,
// floating with gaps and corners in the other.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: bar

    required property var notifications
    required property var recorder
    property var yearView: null // YearCalendar.qml, from the clock's popup
    property string open: ""
    readonly property int gap: Theme.floating ? 8 : 0

    anchors {
        bottom: true
        left: true
        right: true
    }
    margins {
        bottom: bar.gap
        left: bar.gap
        right: bar.gap
    }
    implicitHeight: Theme.barHeight
    color: "transparent"
    // Hyprland blurs behind it (lumar.lua)
    WlrLayershell.namespace: "shadesmar-bar"

    // the glass, outlined as Plasma's panel: all round when it floats, its
    // top edge when docked
    Rectangle {
        anchors.fill: parent
        radius: Theme.floating ? Theme.radius : 0
        color: Theme.island
        border.width: Theme.floating ? 1 : 0
        border.color: Theme.outline
    }

    Rectangle {
        visible: !Theme.floating
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.outline
    }

    IpcHandler {
        target: "bar"

        function open(name: string): void {
            bar.open = name
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 6

        Desktops {}
        Claude {
            bar: bar
            Layout.leftMargin: 6
        }

        Item {
            Layout.fillWidth: true
        }

        Recording {
            recorder: bar.recorder
        }

        Tray {
            window: bar
        }
        Clipboard {
            bar: bar
        }
        NotificationCenter {
            bar: bar
            notifications: bar.notifications
        }
        Network {
            bar: bar
        }
        Bluetooth {
            bar: bar
        }
        Volume {
            bar: bar
        }
        Battery {
            bar: bar
        }
        Clock {
            bar: bar
            yearView: bar.yearView
            Layout.leftMargin: 6
        }
    }
}
