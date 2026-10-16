import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property alias cfg_SceneId: scene.text
    property alias cfg_GapMm: gap.value
    property real cfg_UnitMm
    property alias cfg_Motion: motion.currentIndex
    property alias cfg_PauseWhen: pauseWhen.currentIndex
    property alias cfg_Debug: debug.checked
    property real cfg_Latitude
    property real cfg_Longitude
    property alias formLayout: root

    QQC2.TextField {
        id: scene
        Kirigami.FormData.label: "Scene:"
        placeholderText: "world"
    }

    QQC2.SpinBox {
        id: gap
        Kirigami.FormData.label: "Gap between screens (mm):"
        from: 0
        to: 200
    }

    // In tenths of a millimetre, SpinBox being integer-only.
    QQC2.SpinBox {
        Kirigami.FormData.label: "Game unit size (mm):"
        from: 50
        to: 600
        value: Math.round(root.cfg_UnitMm * 10)
        textFromValue: (v, locale) => Number(v / 10).toLocaleString(locale, "f", 1)
        valueFromText: (text, locale) => Math.round(Number.fromLocaleString(locale, text) * 10)
        onValueModified: root.cfg_UnitMm = value / 10
    }

    QQC2.TextField {
        Kirigami.FormData.label: "Latitude, longitude:"
        text: `${root.cfg_Latitude}, ${root.cfg_Longitude}`
        onEditingFinished: {
            const parts = text.split(",").map(p => Number(p.trim()));
            if (parts.length === 2 && parts.every(Number.isFinite)) {
                root.cfg_Latitude = parts[0];
                root.cfg_Longitude = parts[1];
            }
        }
    }

    QQC2.ComboBox {
        id: motion
        Kirigami.FormData.label: "Motion:"
        model: ["Every frame, on every screen", "Paced: every frame where Hornet is", "Paced: 30 times a second where she rests", "Paced: each screen at its own rate"]
    }

    QQC2.ComboBox {
        id: pauseWhen
        Kirigami.FormData.label: "On the desktop, stand still:"
        model: ["Never", "While a window is maximized or full screen on that screen", "While any window is focused"]
    }

    QQC2.CheckBox {
        id: debug
        Kirigami.FormData.label: "Alignment guides:"
        text: "Show"
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 25
        wrapMode: Text.Wrap
        text: "Screens are placed side by side in the order of the display settings, bottom edges aligned, at the physical size each one reports. Sprites and scenes are read from ~/.local/share/silksong-wallpaper; make them from your copy of the game with the tools in packages/silksong-wallpaper (see its README): world.py for the aquarium, the scene \"world\", or bake.py for a single scene. On the desktop the world can stand still while you work: windows the taskbar leaves out (KRunner, Yakuake) don't count, nor these settings. The lock screen, whose settings show this choice too, never stands still."
    }
}
