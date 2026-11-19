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
    // what was open just before, until the change is through: a popup
    // swapped for another comes and goes at once (BarPopup.qml)
    property string was: ""
    onOpenChanged: Qt.callLater(() => bar.was = bar.open)
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
        // its items' corners, concentric: they're 4 px in
        radius: Theme.floating ? Theme.corner + 4 : 0
        color: Theme.glance
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

    // The light under the pointer, one for the bar: it goes from item to
    // item with the pointer (waiting a moment in the gaps between them),
    // sinks with the item pressed, and leaves the open one its own
    // (BarItem.qml). Come from off the bar, it's there at once.
    property Item lit: null
    function point(item, on) {
        if (on) {
            linger.stop()
            bar.lit = item
        } else if (bar.lit === item) {
            linger.restart()
        }
    }
    Timer {
        id: linger

        interval: 120
        onTriggered: bar.lit = null
    }
    onLitChanged: light.place()
    Connections {
        target: bar.lit

        function onXChanged() {
            light.place()
        }
        function onWidthChanged() {
            light.place()
        }
    }

    Rectangle {
        id: light

        property Item at: null
        property bool glides: false

        function place() {
            light.glides = light.at !== null
            light.at = bar.lit
            if (!bar.lit)
                return
            const p = bar.lit.mapToItem(light.parent, 0, 0)
            light.x = p.x
            light.y = p.y
            light.width = bar.lit.width
            light.height = bar.lit.height
        }

        radius: Theme.corner
        scale: bar.lit ? bar.lit.sunk : 1
        color: !bar.lit || bar.lit.open ? Theme.none : bar.lit.pressed ? Theme.pressed : Theme.hover
        Fade on color {}
        Behavior on x {
            enabled: light.glides && Theme.speed > 0
            Follow {}
        }
        Behavior on width {
            enabled: light.glides && Theme.speed > 0
            Follow {}
        }
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
            bar: bar
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
