// The battery (UPower's display device), hidden on a machine without one.
// Its popup, as Plasma's battery applet: the charge and what it's doing,
// the power profile (power-profiles-daemon), the screen's brightness.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

BarButton {
    id: battery

    readonly property var device: UPower.displayDevice
    // UPower gives 0 to 1
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0

    visible: device && device.isLaptopBattery
    popup: "battery"
    icon: device ? device.iconName : "battery"
    label: percent + "%"
    labelColor: percent <= 10 && UPower.onBattery ? Theme.warn : Theme.text

    function duration(seconds) {
        const h = Math.floor(seconds / 3600)
        const m = Math.round(seconds % 3600 / 60)
        return h > 0 ? `${h} h ${m} min` : `${m} min`
    }

    readonly property string status: {
        if (!device)
            return ""
        switch (device.state) {
        case UPowerDeviceState.Charging:
            return device.timeToFull > 0 ? `Charging, full in ${duration(device.timeToFull)}` : "Charging"
        case UPowerDeviceState.Discharging:
            return device.timeToEmpty > 0 ? `${duration(device.timeToEmpty)} left` : "On battery"
        case UPowerDeviceState.FullyCharged:
            return "Fully charged"
        case UPowerDeviceState.PendingCharge:
            return "Plugged in, not charging"
        default:
            return UPower.onBattery ? "On battery" : "Plugged in"
        }
    }

    // brightnessctl's percentage, read when the popup opens
    property real brightness: -1

    Process {
        id: readBrightness

        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = parseInt(text.split(",")[3])
                battery.brightness = isNaN(p) ? -1 : p / 100
            }
        }
    }

    BarPopup {
        id: popup

        bar: battery.bar
        from: battery
        name: "battery"
        onShownChanged: {
            if (shown)
                readBrightness.running = true
        }

        PopupHeader {
            title: `Battery · ${battery.percent}%`
        }

        ListRow {
            icon: battery.icon
            title: battery.status
            subtitle: battery.device && battery.device.healthSupported ? `Health ${Math.round(battery.device.healthPercentage)}%` : ""
        }

        PopupHeader {
            title: "Power profile"
        }

        Repeater {
            model: [
                { profile: PowerProfile.PowerSaver, name: "Power saver", icon: "battery-profile-powersave-symbolic" },
                { profile: PowerProfile.Balanced, name: "Balanced", icon: "battery-profile-balanced-symbolic" },
                { profile: PowerProfile.Performance, name: "Performance", icon: "battery-profile-performance-symbolic" }
            ].filter(p => p.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

            ListRow {
                required property var modelData

                icon: modelData.icon
                title: modelData.name
                active: PowerProfiles.profile === modelData.profile
                onClicked: PowerProfiles.profile = modelData.profile
            }
        }

        PopupHeader {
            visible: battery.brightness >= 0
            title: "Brightness"
        }

        Slider {
            visible: battery.brightness >= 0
            width: parent.width
            value: battery.brightness
            onMoved: v => {
                // at least 1 %: 0 turns the panel off
                const p = Math.max(1, Math.round(v * 100))
                battery.brightness = p / 100
                Quickshell.execDetached(["brightnessctl", "-q", "set", p + "%"])
            }
        }
    }
}
