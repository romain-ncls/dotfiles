// The battery (UPower's display device), hidden on a machine without one.
// Its popup, as Plasma's battery applet: the charge and what it's doing,
// the power profile (power-profiles-daemon), the screen's brightness, and
// the other devices' batteries: UPower's (a Logitech mouse, through its
// receiver) and the Alienware headset's (modules/awpro, asked when the
// popup opens; there while its dongle reaches it).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

BarButton {
    id: battery

    readonly property var device: UPower.displayDevice
    // UPower gives 0 to 1
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool low: percent <= 10 && UPower.onBattery

    visible: device && device.isLaptopBattery
    popup: "battery"
    // nalthis's line icons by tens (UPower's names fall back on Breeze's)
    readonly property bool charging: device !== null && device.state !== UPowerDeviceState.Discharging && !UPower.onBattery
    icon: `battery-${String(Math.round(percent / 10) * 10).padStart(3, "0")}${charging ? "-charging" : ""}-symbolic`
    label: percent + "%"
    labelColor: low ? Theme.warn : Theme.text

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

    // the headset: {level, charging}, or null (no dongle, link down, no awpro)
    property var headset: null

    Process {
        id: readHeadset

        command: ["awpro", "--json", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text)
                    battery.headset = s.wireless_link && s.wireless_link.up && s.battery ? s.battery : null
                } catch (e) {
                    battery.headset = null
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                battery.headset = null
        }
    }

    // the other batteries UPower knows
    readonly property var others: UPower.devices.values.filter(d => d.isPresent && !d.isLaptopBattery && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Battery && d.type !== UPowerDeviceType.Ups)

    // UPower files some Logitech mice as keyboards (their HID++ battery)
    function kindIcon(type, model) {
        if (/\bM\d{3}\b|\bMX (Master|Anywhere|Vertical)|mouse/i.test(model || ""))
            return "input-mouse-symbolic"
        switch (type) {
        case UPowerDeviceType.Mouse:
            return "input-mouse-symbolic"
        case UPowerDeviceType.Keyboard:
            return "input-keyboard-symbolic"
        case UPowerDeviceType.Headset:
            return "audio-headset-symbolic"
        case UPowerDeviceType.Headphones:
            return "audio-headphones-symbolic"
        case UPowerDeviceType.Phone:
            return "phone-symbolic"
        case UPowerDeviceType.GamingInput:
            return "input-gaming-symbolic"
        default:
            return "battery-symbolic"
        }
    }

    BarPopup {
        id: popup

        bar: battery.bar
        from: battery
        name: "battery"
        onShownChanged: {
            if (shown) {
                readBrightness.running = true
                readHeadset.running = true
            }
        }

        PopupHero {
            icon: battery.icon
            title: `${battery.percent}%`
            caption: battery.status + (battery.device && battery.device.healthSupported ? ` · health ${Math.round(battery.device.healthPercentage)}%` : "")
            warn: battery.low
            lit: battery.charging
        }

        // the profile: one of three, side by side
        Section {
            id: profiles

            readonly property var choices: [
                { profile: PowerProfile.PowerSaver, label: "Saver", icon: Qt.resolvedUrl("icons/leaf.svg") },
                { profile: PowerProfile.Balanced, label: "Balanced", icon: Qt.resolvedUrl("icons/scale.svg") },
                { profile: PowerProfile.Performance, label: "Performance", icon: Qt.resolvedUrl("icons/gauge.svg") }
            ].filter(p => p.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

            title: "Power profile"

            Segmented {
                width: parent.width
                color: "transparent"
                inset: 0
                options: profiles.choices
                current: options.findIndex(p => p.profile === PowerProfiles.profile)
                onPicked: i => PowerProfiles.profile = options[i].profile
            }
        }

        Section {
            visible: battery.brightness >= 0
            title: "Brightness"

            SliderRow {
                icon: "brightness-high-symbolic"
                value: battery.brightness
                onMoved: v => {
                    // at least 1 %: 0 turns the panel off
                    const p = Math.max(1, Math.round(v * 100))
                    battery.brightness = p / 100
                    Quickshell.execDetached(["brightnessctl", "-q", "set", p + "%"])
                }
            }
        }

        Section {
            visible: battery.headset !== null || battery.others.length > 0
            title: "Devices"

            ListRow {
                visible: battery.headset !== null
                chip: true
                icon: "audio-headset-symbolic"
                title: "Alienware Pro headset"
                subtitle: battery.headset && battery.headset.charging ? "Charging" : ""
                trailing: battery.headset ? `${battery.headset.level}%` : ""
            }

            Repeater {
                model: battery.others

                ListRow {
                    required property var modelData

                    chip: true
                    icon: battery.kindIcon(modelData.type, modelData.model)
                    title: modelData.model || "Device"
                    subtitle: modelData.state === UPowerDeviceState.Charging ? "Charging" : ""
                    trailing: `${Math.round(modelData.percentage * 100)}%`
                }
            }
        }
    }
}
