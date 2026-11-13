// The network, as Plasma's applet, laid out as Omarchy's panel: the bar
// shows the Wi-Fi's signal, or the cable. The popup: the connection in use,
// big (its name; connected, limited or asking to sign in, with a button to
// the network's sign-in page) and the Wi-Fi's switch; its details (address,
// gateway, traffic, signal and band, speed); the Wi-Fi's networks, the known
// ones first (a click connects or disconnects, Forget on hover; a new
// secured one asks its password under it); the VPNs, through nmcli
// (Quickshell's NetworkManager knows no VPN). What a connection asks,
// spanreed's secret agent passes on: a card where the popup opens.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

BarButton {
    id: net

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var current: wifi ? wifi.networks.values.find(n => n.connected) ?? null : null
    // the device in use: the cable first
    readonly property var device: wired ?? (current ? wifi : null)
    // NetworkManager's check (nmcli general): a portal is a network's
    // sign-in page, in the way until one signs in
    readonly property bool portal: Networking.connectivity === NetworkConnectivity.Portal
    readonly property bool limited: portal || Networking.connectivity === NetworkConnectivity.Limited

    // Quickshell's strength is 0 to 1
    function strength(n) {
        return n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength
    }
    function signalIcon(n, locked) {
        const s = strength(n)
        const level = s > 0.75 ? "excellent" : s > 0.5 ? "good" : s > 0.25 ? "ok" : "weak"
        return `network-wireless-signal-${level}${locked ? "-locked" : ""}-symbolic`
    }
    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
    }

    popup: "network"
    icon: wired ? "network-wired-symbolic" : current ? signalIcon(current, false) : wifi && Networking.wifiEnabled ? "network-wireless-disconnected-symbolic" : "network-disconnect-symbolic"

    // the networks: the one in use and the known ones, then the others, by
    // signal; each section's name on its first
    readonly property var rows: {
        if (!wifi)
            return []
        const all = wifi.networks.values.filter(n => n.name !== "").sort((a, b) => (b.connected - a.connected) || (strength(b) - strength(a)))
        const known = all.filter(n => n.known || n.connected)
        const other = all.filter(n => !n.known && !n.connected).slice(0, 20)
        return [...known.map((n, i) => ({ net: n, section: i === 0 ? "Known networks" : "" })), ...other.map((n, i) => ({ net: n, section: i === 0 ? "Other networks" : "" }))]
    }

    // the network whose password is asked, the one last given one, and
    // what failed, by name
    property var asking: null
    property string tried: ""
    property var failed: ({})

    function fail(n, text) {
        failed = Object.assign({}, failed, { [n.name]: text })
    }
    function pick(n) {
        const f = Object.assign({}, failed)
        delete f[n.name]
        failed = f
        if (n.connected)
            n.disconnect()
        else if (n.known || !secured(n))
            n.connect()
        else
            asking = n
    }
    function status(n) {
        if (n.state === ConnectionState.Connecting)
            return "Connecting…"
        if (n.state === ConnectionState.Disconnecting)
            return "Disconnecting…"
        if (failed[n.name])
            return failed[n.name]
        if (n.connected)
            return portal ? "Sign-in required" : limited ? "Limited access" : "Connected"
        return ""
    }

    // the scan: on while the popup is open, the networks coming in the
    // first seconds; again on Rescan
    property bool scanning: false

    function rescan() {
        if (!wifi)
            return
        wifi.scannerEnabled = false
        scanning = true
        scanAgain.restart()
        scanned.restart()
    }
    Timer {
        id: scanAgain

        interval: 100
        onTriggered: {
            if (net.wifi)
                net.wifi.scannerEnabled = popup.shown
        }
    }
    Timer {
        id: scanned

        interval: 4000
        onTriggered: net.scanning = false
    }

    // The details of the device in use: its address and gateway, and the
    // Wi-Fi's band, channel, rate and signal (nmcli, no new scan); its
    // traffic from the kernel's counters, each second while open.
    property var info: ({})
    property real rx: -1
    property real tx: -1
    property var last: null
    property real infoAt: 0

    Process {
        id: readInfo

        command: ["sh", "-c", "nmcli -t -f IP4.ADDRESS,IP4.GATEWAY device show \"$1\"; [ -z \"$2\" ] || nmcli -t -f IN-USE,FREQ,CHAN,RATE,SIGNAL device wifi list ifname \"$2\" --rescan no | grep '^\\*'", "sh", net.device ? net.device.name : "", net.device === net.wifi && net.wifi ? net.wifi.name : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const i = {}
                for (const l of text.split("\n")) {
                    if (l.startsWith("IP4.ADDRESS"))
                        i.ip = l.slice(l.indexOf(":") + 1).split("/")[0]
                    else if (l.startsWith("IP4.GATEWAY:"))
                        i.gateway = l.slice(12)
                    else if (l.startsWith("*:")) {
                        const f = l.split(":")
                        const mhz = parseInt(f[1])
                        i.band = mhz > 5900 ? "6 GHz" : mhz > 4900 ? "5 GHz" : "2.4 GHz"
                        i.channel = f[2]
                        i.rate = f[3].replace(" Mbit/s", " Mb/s")
                        i.signal = f[4]
                    }
                }
                net.info = i
            }
        }
    }

    Process {
        id: readTraffic

        command: ["sh", "-c", "cat /sys/class/net/\"$1\"/statistics/rx_bytes /sys/class/net/\"$1\"/statistics/tx_bytes", "sh", net.device ? net.device.name : "-"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [r, t] = text.trim().split("\n").map(Number)
                const now = Date.now()
                if (net.last && now > net.last.time) {
                    const s = (now - net.last.time) / 1000
                    net.rx = Math.max(0, (r - net.last.r) / s)
                    net.tx = Math.max(0, (t - net.last.t) / s)
                }
                net.last = { r: r, t: t, time: now }
            }
        }
    }

    Timer {
        running: popup.shown && net.device !== null
        repeat: true
        triggeredOnStart: true
        interval: 1000
        onTriggered: {
            readTraffic.running = true
            // the rest every few seconds
            if (Date.now() - net.infoAt > 4000) {
                readInfo.running = true
                net.infoAt = Date.now()
            }
        }
    }
    onDeviceChanged: {
        info = ({})
        infoAt = 0
        last = null
        rx = tx = -1
    }

    function rate(bytes) {
        if (bytes < 0)
            return "—"
        const k = bytes / 1000
        return k < 1000 ? `${k < 10 ? k.toFixed(1) : Math.round(k)} kB/s` : `${(k / 1000).toFixed(1)} MB/s`
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
        popupWidth: 380
        onShownChanged: {
            if (shown) {
                net.rescan()
            } else {
                if (net.wifi)
                    net.wifi.scannerEnabled = false
                net.asking = null
            }
        }

        // what's in use, big
        PopupHero {
            icon: net.icon
            title: net.wired ? "Wired" : net.current ? net.current.name : "Offline"
            caption: net.portal ? "Sign-in required" : net.limited ? "Limited access" : net.device ? (net.device === net.wifi && net.info.band ? `Connected · ${net.info.band}` : "Connected") : net.wifi && !Networking.wifiEnabled ? "Wi-Fi off" : "No network"
            warn: net.limited
            toggle: net.wifi !== null
            checked: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        // the network's sign-in page: any plain http address leads there
        // (NetworkManager's own check is on a site browsers only reach by
        // https, which the portal can't take over)
        Rectangle {
            visible: net.portal
            width: parent.width
            height: 34
            radius: 8
            color: portalArea.containsMouse ? Theme.alpha(Theme.warn, 0.22) : Theme.alpha(Theme.warn, 0.12)
            border.width: 1
            border.color: Theme.alpha(Theme.warn, 0.5)

            Text {
                anchors.centerIn: parent
                text: "Sign in to the network"
                color: Theme.warn
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: portalArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    Quickshell.execDetached(["xdg-open", "http://neverssl.com"])
                    popup.close()
                }
            }
        }

        // its details, two by two; a click copies an address
        Grid {
            visible: net.device !== null
            width: parent.width
            columns: 2
            columnSpacing: 20
            rowSpacing: 3
            topPadding: 2
            bottomPadding: 4

            Repeater {
                model: !net.device ? [] : [
                    { label: "IP address", value: net.info.ip, copy: true },
                    { label: "Gateway", value: net.info.gateway, copy: true },
                    { label: "Receiving", value: net.rate(net.rx) },
                    { label: "Sending", value: net.rate(net.tx) },
                    ...(net.device === net.wifi ? [
                        { label: "Signal", value: net.info.signal ? `${net.info.signal} %` : "" },
                        { label: "Band", value: net.info.band ? `${net.info.band} · ch ${net.info.channel}` : "" },
                        { label: "Speed", value: net.info.rate }
                    ] : [
                        { label: "Speed", value: net.wired.linkSpeed > 0 ? (net.wired.linkSpeed >= 1000 ? `${net.wired.linkSpeed / 1000} Gb/s` : `${net.wired.linkSpeed} Mb/s`) : "" },
                        { label: "Interface", value: net.wired.name }
                    ])
                ]

                Item {
                    id: cell

                    required property var modelData
                    property bool copied: false

                    width: (parent.width - 20) / 2
                    height: 18

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 4
                        text: cell.modelData.label
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        text: cell.copied ? "Copied" : cell.modelData.value || "—"
                        color: cell.copied ? Theme.accent : copyArea.containsMouse ? Theme.accent : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.features: {
                            "tnum": 1
                        }

                        MouseArea {
                            id: copyArea

                            enabled: cell.modelData.copy === true && !!cell.modelData.value
                            anchors.fill: parent
                            anchors.margins: -3
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                Quickshell.execDetached(["wl-copy", cell.modelData.value])
                                cell.copied = true
                                uncopy.restart()
                            }
                        }
                    }

                    Timer {
                        id: uncopy

                        interval: 900
                        onTriggered: cell.copied = false
                    }
                }
            }
        }

        // the Wi-Fi's networks
        Text {
            visible: net.wifi !== null && Networking.wifiEnabled && net.rows.length === 0
            x: 4
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: net.scanning ? "Looking for networks…" : "No network in reach"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        ListView {
            id: networks

            visible: net.wifi !== null && Networking.wifiEnabled && net.rows.length > 0
            width: parent.width
            height: Math.min(contentHeight, 330)
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: net.rows

            delegate: Column {
                id: entry

                required property var modelData
                required property int index
                readonly property var n: modelData.net

                width: networks.width

                SectionLabel {
                    visible: entry.modelData.section !== ""
                    text: entry.modelData.section
                    action: entry.index === 0 ? (net.scanning ? "Scanning…" : "Rescan") : ""
                    onActed: net.rescan()
                }

                ListRow {
                    icon: net.signalIcon(entry.n, false)
                    trailingIcon: net.secured(entry.n) ? Qt.resolvedUrl("icons/lock.svg") : ""
                    title: entry.n.name
                    active: entry.n.connected
                    subtitle: net.status(entry.n)
                    removable: entry.n.known && !entry.n.connected
                    removeLabel: "Forget"
                    onClicked: net.pick(entry.n)
                    onRemoved: entry.n.forget()
                }

                // a new secured network's password, under it
                Rectangle {
                    visible: net.asking === entry.n
                    width: parent.width
                    height: visible ? 36 : 0
                    radius: 8
                    color: Theme.slot

                    TextInput {
                        id: psk

                        x: 12
                        width: parent.width - 24 - join.width
                        anchors.verticalCenter: parent.verticalCenter
                        focus: net.asking === entry.n
                        echoMode: TextInput.Password
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        clip: true
                        onAccepted: join.go()
                        Keys.onEscapePressed: event => {
                            net.asking = null
                            text = ""
                        }

                        Text {
                            visible: psk.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Password"
                            color: Theme.dim
                            font: psk.font
                        }
                    }

                    Text {
                        id: join

                        function go() {
                            if (psk.text === "")
                                return
                            net.tried = entry.n.name
                            entry.n.connectWithPsk(psk.text)
                            psk.text = ""
                            net.asking = null
                        }

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Connect"
                        color: psk.text === "" ? Theme.dim : joinArea.containsMouse ? Theme.text : Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold

                        MouseArea {
                            id: joinArea

                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            onClicked: join.go()
                        }
                    }
                }

                Connections {
                    target: entry.n

                    function onConnectionFailed(reason) {
                        if (reason === ConnectionFailReason.NoSecrets) {
                            net.fail(entry.n, net.tried === entry.n.name ? "Wrong password" : "")
                            net.asking = entry.n
                        } else {
                            net.fail(entry.n, "Couldn't connect")
                        }
                        net.tried = ""
                    }
                }
            }
        }

        SectionLabel {
            visible: net.vpns.length > 0
            text: "VPN"
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
