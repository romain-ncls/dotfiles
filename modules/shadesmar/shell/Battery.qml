// The battery (UPower's display device): its icon and charge; hidden on a
// machine without one.
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Widgets

Row {
    id: battery

    readonly property var device: UPower.displayDevice
    // UPower gives 0 to 1
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0

    visible: device && device.isLaptopBattery
    spacing: 6

    IconImage {
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: Theme.icon
        source: battery.device ? Quickshell.iconPath(battery.device.iconName, "battery") : ""
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: battery.percent + "%"
        color: battery.percent <= 10 && UPower.onBattery ? Theme.warn : Theme.text
        font.family: Theme.font
        font.pixelSize: 13
    }
}
