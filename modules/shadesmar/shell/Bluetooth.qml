// Bluetooth, as Plasma's applet: the bar's icon, lit while a device is
// connected; the popup, the adapter's switch, the paired devices (a click
// connects or disconnects; their battery), and a scan for new ones (a click
// pairs, trusts and connects; a device that wants a PIN typed needs
// bluetoothctl: there's no pairing agent yet).
import QtQuick
import Quickshell
import Quickshell.Bluetooth

BarButton {
    id: bt

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var paired: devices.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var found: devices.filter(d => !d.paired && d.deviceName !== "")
    readonly property bool anyConnected: paired.some(d => d.connected)

    visible: adapter !== null
    popup: "bluetooth"
    icon: !adapter || !adapter.enabled ? "network-bluetooth-inactive-symbolic" : anyConnected ? "network-bluetooth-activated-symbolic" : "network-bluetooth-symbolic"

    function state(d) {
        switch (d.state) {
        case BluetoothDeviceState.Connecting:
            return "Connecting…"
        case BluetoothDeviceState.Disconnecting:
            return "Disconnecting…"
        case BluetoothDeviceState.Connected:
            return d.batteryAvailable ? `Connected · ${Math.round(d.battery * 100)}%` : "Connected"
        default:
            return d.pairing ? "Pairing…" : ""
        }
    }

    BarPopup {
        id: popup

        bar: bt.bar
        from: bt
        name: "bluetooth"
        onShownChanged: {
            // the scan stops with the popup
            if (!shown && bt.adapter && bt.adapter.discovering)
                bt.adapter.discovering = false
        }

        PopupHeader {
            title: "Bluetooth"
            toggle: true
            checked: bt.adapter ? bt.adapter.enabled : false
            onToggled: bt.adapter.enabled = !bt.adapter.enabled
        }

        Repeater {
            model: bt.adapter && bt.adapter.enabled ? bt.paired : []

            ListRow {
                required property var modelData

                icon: modelData.icon || "network-bluetooth-symbolic"
                title: modelData.name
                active: modelData.connected
                subtitle: bt.state(modelData)
                onClicked: {
                    if (modelData.connected)
                        modelData.disconnect()
                    else
                        modelData.connect()
                }
            }
        }

        PopupHeader {
            visible: bt.adapter !== null && bt.adapter.enabled
            title: "Other devices"
            action: bt.adapter && bt.adapter.discovering ? "Stop" : "Scan"
            onActed: bt.adapter.discovering = !bt.adapter.discovering
        }

        Repeater {
            model: bt.adapter && bt.adapter.enabled && bt.adapter.discovering ? bt.found : []

            ListRow {
                required property var modelData

                icon: modelData.icon || "network-bluetooth-symbolic"
                title: modelData.deviceName
                subtitle: modelData.pairing ? "Pairing…" : "Click to pair"
                dim: true
                onClicked: {
                    modelData.trusted = true
                    modelData.pair()
                }

                // once paired, connect
                Connections {
                    target: modelData

                    function onPairedChanged() {
                        if (modelData.paired)
                            modelData.connect()
                    }
                }
            }
        }
    }
}
