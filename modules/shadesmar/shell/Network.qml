// The network, as Plasma's applet: the bar shows the Wi-Fi's signal, or the
// cable. The popup: the Wi-Fi's switch and networks (a click connects or
// disconnects; a new secured one asks its password here), the cable, and
// the VPNs, through nmcli (Quickshell's NetworkManager knows no VPN). What a
// connection asks, spanreed's secret agent passes on: a card where the
// popup opens.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

BarButton {
    id: net

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var current: wifi ? wifi.networks.values.find(n => n.connected) ?? null : null

    // Quickshell's strength is 0 to 1
    function strength(n) {
        return n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength
    }
    function signalIcon(n) {
        const s = strength(n)
        return s > 0.75 ? "network-wireless-signal-excellent-symbolic" : s > 0.5 ? "network-wireless-signal-good-symbolic" : s > 0.25 ? "network-wireless-signal-ok-symbolic" : "network-wireless-signal-weak-symbolic"
    }
    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
    }

    popup: "network"
    icon: wired ? "network-wired-symbolic" : current ? signalIcon(current) : "network-offline-symbolic"

    // the networks: the one in use, then the known ones, then by signal
    readonly property var networks: {
        if (!wifi)
            return []
        return wifi.networks.values.filter(n => n.name !== "").sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (strength(b) - strength(a))).slice(0, 12)
    }

    // the network whose password is asked, and the last one that failed
    property var asking: null
    property string failed: ""

    function pick(n) {
        failed = ""
        if (n.connected)
            n.disconnect()
        else if (n.known || !secured(n))
            n.connect()
        else
            asking = n
    }

    // VPNs: name, uuid, active, from nmcli's terse output (colons escaped)
    property var vpns: []

    Process {
        id: listVpns

        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                net.vpns = text.split("\n").filter(l => l !== "").map(l => l.replace(/\\:/g, "\u0000").split(":").map(f => f.replace(/\u0000/g, ":"))).filter(f => f[2] === "vpn" || f[2] === "wireguard").map(f => ({ name: f[0], uuid: f[1], active: f[3] === "yes" }))
            }
        }
    }

    Timer {
        running: popup.shown
        repeat: true
        triggeredOnStart: true
        interval: 2000
        onTriggered: listVpns.running = true
    }

    // What a connection asks (spanreed's secret agent, network.go): a Wi-Fi's
    // password, a VPN's one-time code, in a card above the bar; kept ones are
    // only said to be ("saved": an empty field keeps it). The answer goes back
    // through `spanreed answer` (SPANREED: a dev rig's build), the secrets on
    // its stdin.
    // {id, setting, name, message, fields: [{key, label, secret, saved}]}
    property var request: null

    function answer(ok) {
        const r = request
        if (!r)
            return
        const values = {}
        for (let i = 0; ok && i < fields.count; i++)
            values[fields.itemAt(i).key] = fields.itemAt(i).text
        request = null
        reply.stdinEnabled = true
        reply.exec([Quickshell.env("SPANREED") || "spanreed", "answer"])
        reply.write(JSON.stringify({ id: r.id, ok: ok, values: values }))
        reply.stdinEnabled = false
    }

    // the fields still empty that have nothing kept
    function missing() {
        for (let i = 0; i < fields.count; i++) {
            const f = fields.itemAt(i)
            if (f && !f.saved && f.text === "")
                return f
        }
        return null
    }

    Process {
        id: reply
    }

    IpcHandler {
        target: "network"

        // the request: one JSON object (setting, name, message, fields)
        function ask(id: int, request: string): void {
            // a new one replaces the one asked before
            if (net.request)
                net.answer(false)
            card.place()
            net.request = Object.assign(JSON.parse(request), { id: id })
        }
        // NetworkManager gave up, or nobody answered
        function cancel(id: int): void {
            if (net.request && net.request.id === id)
                net.request = null
        }
    }

    BarCard {
        id: card

        bar: net.bar
        from: net
        shown: net.request !== null
        icon: !net.request ? "" : net.request.setting === "vpn" ? "network-vpn-symbolic" : net.request.setting === "802-11-wireless-security" ? "network-wireless-symbolic" : "network-wired-symbolic"
        title: net.request ? net.request.name : ""
        message: net.request ? net.request.message : ""
        yes: "Connect"
        ready: fields.count > 0 && net.missing() === null
        onAccepted: net.answer(true)
        onDismissed: net.answer(false)

        Repeater {
            id: fields

            model: net.request ? net.request.fields : []

            CardField {
                required property var modelData
                required property int index
                readonly property string key: modelData.key
                readonly property bool saved: modelData.saved

                focus: index === 0
                secret: modelData.secret
                hint: saved ? `${modelData.label}: saved` : modelData.label
                // the next empty one, or connect
                onAccepted: {
                    const next = net.missing()
                    if (next)
                        next.forceActiveFocus()
                    else
                        net.answer(true)
                }
            }
        }
    }

    BarPopup {
        id: popup

        bar: net.bar
        from: net
        name: "network"
        onShownChanged: {
            if (net.wifi)
                net.wifi.scannerEnabled = shown
            if (!shown)
                net.asking = null
        }

        PopupHeader {
            visible: net.wifi !== null
            title: "Wi-Fi"
            toggle: true
            checked: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        Repeater {
            model: Networking.wifiEnabled ? net.networks : []

            ListRow {
                id: row

                required property var modelData

                icon: net.signalIcon(modelData)
                title: modelData.name
                active: modelData.connected
                subtitle: modelData.state === ConnectionState.Connecting ? "Connecting…" : modelData.state === ConnectionState.Disconnecting ? "Disconnecting…" : net.failed === modelData.name ? "Couldn't connect" : modelData.connected ? "Connected" : ""
                trailing: net.secured(modelData) ? "🔒" : ""
                onClicked: net.pick(modelData)

                Connections {
                    target: row.modelData

                    function onConnectionFailed(reason) {
                        net.failed = row.modelData.name
                        if (reason === ConnectionFailReason.NoSecrets)
                            net.asking = row.modelData
                    }
                }
            }
        }

        // a new secured network's password
        Rectangle {
            visible: net.asking !== null
            width: parent.width
            height: 40
            radius: 8
            color: Theme.slot

            TextInput {
                id: psk

                x: 12
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                focus: net.asking !== null
                echoMode: TextInput.Password
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                onAccepted: {
                    net.asking.connectWithPsk(text)
                    text = ""
                    net.asking = null
                }

                Text {
                    visible: psk.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: net.asking ? `Password for ${net.asking.name}, then Enter` : ""
                    color: Theme.dim
                    font: psk.font
                }
            }
        }

        ListRow {
            visible: net.wired !== null
            icon: "network-wired-symbolic"
            title: "Wired"
            active: true
            subtitle: net.wired && net.wired.linkSpeed > 0 ? `Connected · ${net.wired.linkSpeed} Mb/s` : "Connected"
        }

        PopupHeader {
            visible: net.vpns.length > 0
            title: "VPN"
        }

        Repeater {
            model: net.vpns

            ListRow {
                required property var modelData

                icon: "network-vpn-symbolic"
                title: modelData.name
                active: modelData.active
                subtitle: modelData.active ? "Connected" : ""
                onClicked: {
                    Quickshell.execDetached(["nmcli", "connection", modelData.active ? "down" : "up", "uuid", modelData.uuid])
                    listVpns.running = true
                }
            }
        }
    }
}
