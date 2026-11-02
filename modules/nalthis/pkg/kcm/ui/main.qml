// Nalthis palette page: four sliders and a preview of what they give.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    component Knob: RowLayout {
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        property real value
        property string text
        signal moved(real value)
        spacing: Kirigami.Units.smallSpacing
        QQC2.Slider {
            id: slider
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            value: parent.value
            onMoved: parent.moved(value)
        }
        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            text: parent.text
            font.features: { "tnum": 1 }
        }
    }

    component Swatch: ColumnLayout {
        property color color
        property string text
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            radius: Kirigami.Units.cornerRadius
            color: parent.color
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }
        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            text: parent.text
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            visible: kcm.error !== ""
            text: kcm.error
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Knob {
                Kirigami.FormData.label: i18nc("@label:slider", "Grey hue:")
                from: 0; to: 359; stepSize: 1
                value: kcm.hue
                text: Math.round(kcm.hue) + "°"
                onMoved: value => kcm.hue = value
            }
            Knob {
                Kirigami.FormData.label: i18nc("@label:slider how colored the greys are", "Tint:")
                from: 0; to: 3; stepSize: 0.05
                value: kcm.tint
                text: "×" + kcm.tint.toFixed(2)
                onMoved: value => kcm.tint = value
            }
            Knob {
                Kirigami.FormData.label: i18nc("@label:slider lightness of the surfaces", "Depth:")
                from: -0.06; to: 0.08; stepSize: 0.005
                value: kcm.depth
                text: (kcm.depth >= 0 ? "+" : "") + kcm.depth.toFixed(3)
                onMoved: value => kcm.depth = value
            }
            Knob {
                Kirigami.FormData.label: i18nc("@label:slider", "Accent hue:")
                from: 0; to: 359; stepSize: 1
                value: kcm.accent
                text: Math.round(kcm.accent) + "°"
                onMoved: value => kcm.accent = value
            }

            Item { Kirigami.FormData.isSection: true }

            RowLayout {
                Kirigami.FormData.label: i18nc("@label", "Surfaces:")
                spacing: Kirigami.Units.largeSpacing
                Swatch { color: kcm.tokens.frame ?? "black"; text: i18nc("@label surface", "Frame") }
                Swatch { color: kcm.tokens.base ?? "black"; text: i18nc("@label surface", "Views") }
                Swatch { color: kcm.tokens.pane ?? "black"; text: i18nc("@label surface", "Windows") }
                Swatch { color: kcm.tokens.raised ?? "black"; text: i18nc("@label surface", "Header") }
                Swatch { color: kcm.tokens.overlay ?? "black"; text: i18nc("@label surface", "Popups") }
            }
            RowLayout {
                Kirigami.FormData.label: i18nc("@label", "Accent:")
                spacing: Kirigami.Units.largeSpacing
                Swatch { color: kcm.tokens.accent ?? "black"; text: i18nc("@label", "Fills") }
                Swatch { color: kcm.tokens.accentText ?? "black"; text: i18nc("@label", "Text") }
            }
            Rectangle {
                Kirigami.FormData.label: i18nc("@label", "Text:")
                implicitWidth: sample.implicitWidth + Kirigami.Units.largeSpacing * 4
                implicitHeight: sample.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.cornerRadius
                color: kcm.tokens.base ?? "black"
                Row {
                    id: sample
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.largeSpacing * 2
                    QQC2.Label { text: i18nc("@label sample", "Text"); color: kcm.tokens.text ?? "white" }
                    QQC2.Label { text: i18nc("@label sample", "Secondary"); color: kcm.tokens.text2 ?? "white" }
                    QQC2.Label { text: i18nc("@label sample", "Disabled"); color: kcm.tokens.text3 ?? "white" }
                    QQC2.Label { text: i18nc("@label sample", "Link"); color: kcm.tokens.accentText ?? "white" }
                }
            }

            Item { Kirigami.FormData.isSection: true }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18nc("@info", "Changes show on the desktop as you move the sliders. Apply saves them in the dotfiles repo (modules/nalthis/palette.json). Same knobs in a terminal: nalthis tune.")
            }
        }
    }
}
