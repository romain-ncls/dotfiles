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
    property alias cfg_Debug: debug.checked
    property alias formLayout: root

    QQC2.TextField {
        id: scene
        Kirigami.FormData.label: "Scene:"
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

    QQC2.CheckBox {
        id: debug
        Kirigami.FormData.label: "Alignment guides:"
        text: "Show"
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 25
        wrapMode: Text.Wrap
        text: "Screens are placed side by side in the order of the display settings, bottom edges aligned, at the physical size each one reports. Sprites and scenes are read from ~/.local/share/silksong-wallpaper; make them from your copy of the game with packages/silksong-wallpaper/tools/extract.py and bake.py."
    }
}
