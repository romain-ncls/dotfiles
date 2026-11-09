// Bluetooth, as Plasma's applet: the bar's icon, lit while a device is
// connected; the popup, the adapter's switch, the paired devices (a click
// connects or disconnects; their battery), and a scan for new ones (a click
// pairs, trusts and connects). What a pairing asks, spanreed's agent passes
// on (modules/shadesmar/pkg: BlueZ's requests): a card where the popup
// opens, a code to compare, one to type on the device or here, or a yes or
// no; Escape or a click elsewhere says no.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

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

    // The device being paired from the popup, connected once paired (here,
    // not in its row: the popup may close meanwhile, the card takes its place).
    property var pairing: null

    function pair(d) {
        pairing = d
        d.trusted = true
        d.pair()
    }

    Connections {
        target: bt.pairing

        function onPairedChanged() {
            if (bt.pairing.paired)
                bt.pairing.connect()
            bt.pairing = null
        }
        function onPairingChanged() {
            if (!bt.pairing.pairing && !bt.pairing.paired)
                bt.pairing = null
        }
    }

    // The pairing's request (spanreed's bluetooth.go): id, kind, the device's
    // D-Bus path, its code, the digits typed so far (show-passkey). Kinds:
    // confirm (both show this code), authorize (it pairs from its side),
    // service (a service it wants), pin and passkey (typed here), show-pin
    // and show-passkey (typed on the device, nothing to answer).
    property var request: null
    readonly property var asker: request ? devices.find(d => d.dbusPath === request.device) ?? null : null
    readonly property bool typed: request !== null && (request.kind === "pin" || request.kind === "passkey")

    function waits(r) {
        return !r.kind.startsWith("show-")
    }

    // The answer, to spanreed; no to a code shown cancels the pairing.
    function answer(ok, value) {
        const r = request
        const device = asker
        if (!r)
            return
        request = null
        if (waits(r))
            Quickshell.execDetached(["busctl", "--user", "call", "org.shadesmar.Spanreed", "/org/shadesmar/Bluetooth", "org.shadesmar.Bluetooth", "Answer", "ubs", String(r.id), String(ok), value])
        else if (!ok && device)
            device.cancelPair()
    }

    // (BlueZ's device paths end with dev_AA_BB_CC_DD_EE_FF)
    function nameOf(r) {
        if (asker)
            return asker.name || asker.deviceName
        return r.device.split("/").pop().replace(/^dev_/, "").replace(/_/g, ":")
    }

    // the services a device that isn't trusted asks for, by their UUID's
    // 16 bits
    readonly property var services: ({
            "1105": "file transfers",
            "1106": "file transfers",
            "1108": "calls",
            "110a": "audio",
            "110b": "audio",
            "110c": "remote control",
            "110e": "remote control",
            "1112": "calls",
            "1115": "the network",
            "1116": "the network",
            "111e": "calls",
            "111f": "calls",
            "1124": "input",
            "1812": "input"
        })

    function message(r) {
        switch (r.kind) {
        case "confirm":
            return "Pair if it shows the same code"
        case "authorize":
            return "Wants to pair"
        case "service":
            return `Wants to use ${services[r.code.slice(4, 8).toLowerCase()] ?? r.code}`
        case "pin":
            return "Asks for its PIN (often 0000)"
        case "passkey":
            return "Asks for the code it shows"
        default:
            return "Type this code on it, then Enter"
        }
    }

    // 123 456; the digits typed on the device lit
    function code(r) {
        const c = r.code.length === 6 ? r.code.slice(0, 3) + " " + r.code.slice(3) : r.code
        if (r.kind !== "show-passkey" || r.entered <= 0)
            return c
        const lit = r.entered + (r.entered > 3 ? 1 : 0)
        return `<font color="${Theme.accent}">${c.slice(0, lit)}</font>${c.slice(lit)}`
    }

    IpcHandler {
        target: "bluetooth"

        function ask(id: int, kind: string, device: string, code: string, entered: int): void {
            // a new one replaces the one asked before
            if (bt.request && bt.waits(bt.request))
                bt.answer(false, "")
            card.place()
            bt.request = {
                id: id,
                kind: kind,
                device: device,
                code: code,
                entered: entered
            }
        }
        // BlueZ gave up (0: whichever it is), or nobody answered
        function cancel(id: int): void {
            if (bt.request && (id === 0 || bt.request.id === id))
                bt.request = null
        }
    }

    // a code shown goes once the pairing's done
    Connections {
        target: bt.request && !bt.waits(bt.request) ? bt.asker : null

        function onPairingChanged() {
            if (!bt.asker.pairing)
                bt.request = null
        }
    }

    // the request's card, above the bar (a pairing the device starts comes
    // with no popup open)
    BarCard {
        id: card

        bar: bt.bar
        from: bt
        shown: bt.request !== null
        icon: bt.asker?.icon || "network-bluetooth-symbolic"
        title: bt.request ? bt.nameOf(bt.request) : ""
        message: bt.request ? bt.message(bt.request) : ""
        no: bt.request?.kind === "service" ? "Deny" : "Cancel"
        yes: !bt.request || !bt.waits(bt.request) ? "" : bt.request.kind === "service" ? "Allow" : "Pair"
        ready: !bt.typed || entry.text !== ""
        onAccepted: bt.answer(true, bt.typed ? entry.text : "")
        onDismissed: bt.answer(false, "")

        // the code, to compare or to type on the device
        Text {
            visible: bt.request !== null && bt.request.code !== "" && (bt.request.kind === "confirm" || !bt.waits(bt.request))
            anchors.horizontalCenter: parent.horizontalCenter
            text: bt.request ? bt.code(bt.request) : ""
            textFormat: Text.StyledText
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 26
            font.weight: Font.DemiBold
            font.letterSpacing: 3
        }

        // the PIN or the code, typed here
        CardField {
            id: entry

            visible: bt.typed
            focus: bt.typed
            digits: bt.request?.kind === "passkey"
            maxLength: bt.request?.kind === "passkey" ? 6 : 16
            hint: bt.request?.kind === "passkey" ? "The code, then Enter" : "The PIN, then Enter"
            onAccepted: {
                if (text !== "")
                    bt.answer(true, text)
            }

            Connections {
                target: bt

                function onRequestChanged() {
                    entry.text = ""
                }
            }
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
                onClicked: bt.pair(modelData)
            }
        }
    }
}
