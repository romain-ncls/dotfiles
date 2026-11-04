// The bar: the desktops on the left; the tray, the clipboard, the
// notifications, the network, Bluetooth, the sound, the battery and the
// clock on the right. Their popups open above them, one at a time (`open`;
// qs -c shadesmar ipc call bar open <name>). Docked across the screen in
// lumar's flush layout, floating with gaps and corners in the other.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: bar

    required property var notifications
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

    Rectangle {
        anchors.fill: parent
        radius: Theme.floating ? Theme.radius : 0
        color: Theme.bar
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

        Item {
            Layout.fillWidth: true
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
            Layout.leftMargin: 6
        }
    }
}
