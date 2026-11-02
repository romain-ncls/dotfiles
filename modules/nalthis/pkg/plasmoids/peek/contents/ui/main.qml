// Show desktop as on Windows: a thin strip at the panel's end, a line on
// its inner side, the tasks' hover wash, and a click that hides or brings
// back every window (KWin's showDesktop, over D-Bus: Plasma's own widget
// keeps its backend private).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int thickness: 8 // Windows' strip

    // asyncCall's callback form needs both callbacks: with only one, QML
    // picks the one-argument overload and drops the callback.
    function toggle() {
        const kwin = { service: "org.kde.KWin", path: "/KWin" };
        const failed = reply => console.warn("peek:", reply.error.message);
        DBus.SessionBus.asyncCall(Object.assign({ iface: "org.freedesktop.DBus.Properties", member: "Get",
                arguments: ["org.kde.KWin", "showingDesktop"] }, kwin), reply => {
            DBus.SessionBus.asyncCall(Object.assign({ iface: "org.kde.KWin", member: "showDesktop",
                    arguments: [!reply.value] }, kwin), () => {}, failed);
        }, failed);
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    toolTipMainText: i18nc("@info:tooltip", "Show desktop")
    toolTipSubText: ""

    fullRepresentation: MouseArea {
        Layout.minimumWidth: root.vertical ? 0 : root.thickness
        Layout.maximumWidth: root.vertical ? Infinity : root.thickness
        Layout.minimumHeight: root.vertical ? root.thickness : 0
        Layout.maximumHeight: root.vertical ? root.thickness : Infinity
        Layout.fillWidth: root.vertical
        Layout.fillHeight: !root.vertical

        hoverEnabled: true
        onClicked: root.toggle()
        Accessible.role: Accessible.Button
        Accessible.name: root.toolTipMainText
        Accessible.onPressAction: root.toggle()

        Rectangle { // the hover wash (text at 7%, as tasks)
            anchors.fill: parent
            radius: 3
            color: Kirigami.Theme.textColor
            opacity: parent.containsMouse ? (parent.pressed ? 0.11 : 0.07) : 0
        }
        Rectangle { // the line on the inner side
            x: root.vertical ? parent.width / 4 : 0
            y: root.vertical ? 0 : parent.height / 4
            width: root.vertical ? parent.width / 2 : 1
            height: root.vertical ? 1 : parent.height / 2
            color: Kirigami.Theme.textColor
            opacity: 0.2
        }
    }
}
