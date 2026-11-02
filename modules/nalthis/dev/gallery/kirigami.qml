// Kirigami / QtQuick Controls gallery for dev/test.sh:
//   kirigami.sh [menu|combo|tooltip]
// opens that popup after a moment, since the headless session has no pointer.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win
    width: 900
    height: 620
    title: "Kirigami gallery"
    readonly property string popupArg: Qt.application.arguments[Qt.application.arguments.length - 1]

    globalDrawer: Kirigami.GlobalDrawer {
        modal: false
        collapsible: true
        actions: [
            Kirigami.Action { icon.name: "user-home"; text: "Home"; checked: true },
            Kirigami.Action { icon.name: "folder-documents"; text: "Documents" },
            Kirigami.Action { icon.name: "folder-download"; text: "Downloads" },
            Kirigami.Action { icon.name: "configure"; text: "Settings" }
        ]
    }

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: "Controls"
        actions: [
            Kirigami.Action { icon.name: "document-new"; text: "New" },
            Kirigami.Action { icon.name: "edit-find"; text: "Find"; checkable: true; checked: true }
        ]

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: true
                type: Kirigami.MessageType.Positive
                text: "lodestar applied 3 changes."
            }

            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                QQC2.Button { text: "Button" }
                QQC2.Button { text: "Highlighted"; highlighted: true }
                QQC2.Button { text: "Disabled"; enabled: false }
                QQC2.ToolButton { icon.name: "edit-copy"; text: "Tool" }
                QQC2.Button { text: "Checked"; checkable: true; checked: true }
            }

            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                QQC2.CheckBox { text: "Checked"; checked: true }
                QQC2.CheckBox { text: "Unchecked" }
                QQC2.RadioButton { text: "Radio"; checked: true }
                QQC2.RadioButton { text: "Off" }
                QQC2.Switch { text: "On"; checked: true }
                QQC2.Switch { text: "Off" }
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                QQC2.TextField { id: field; Kirigami.FormData.label: "Name:"; text: "Focused" }
                QQC2.TextField { Kirigami.FormData.label: "Search:"; placeholderText: "Placeholder" }
                QQC2.ComboBox { id: combo; Kirigami.FormData.label: "Combo:"; model: ["Nocturne", "Graphite", "Abyss"] }
                QQC2.SpinBox { Kirigami.FormData.label: "Spin:"; value: 4 }
                QQC2.Slider { Kirigami.FormData.label: "Slider:"; value: 0.6 }
                QQC2.ProgressBar { Kirigami.FormData.label: "Progress:"; value: 0.64 }
            }

            QQC2.TabBar {
                QQC2.TabButton { text: "First" }
                QQC2.TabButton { text: "Second" }
                QQC2.TabButton { text: "Third" }
            }

            Kirigami.Card {
                Layout.fillWidth: true
                banner.title: "Card"
                contentItem: QQC2.Label { wrapMode: Text.WordWrap; text: "A Kirigami card with some body text." }
            }

            Repeater {
                model: 8
                QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    icon.name: index % 3 ? "text-x-generic" : "folder"
                    text: "Item " + (index + 1)
                    highlighted: index === 2
                }
            }
        }
    }

    QQC2.Menu {
        id: menu
        QQC2.MenuItem { icon.name: "document-new"; text: "New" }
        QQC2.MenuItem { icon.name: "document-open"; text: "Open…" }
        QQC2.MenuSeparator {}
        QQC2.MenuItem { text: "Word Wrap"; checkable: true; checked: true }
        QQC2.MenuItem { icon.name: "edit-delete"; text: "Move to Trash" }
        QQC2.MenuItem { text: "Disabled entry"; enabled: false }
    }

    QQC2.ToolTip { id: tip; text: "Split the view in two"; x: 200; y: 60 }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            if (win.popupArg === "menu") { menu.popup(260, 120); menu.currentIndex = 1 }
            else if (win.popupArg === "combo") combo.popup.open()
            else if (win.popupArg === "tooltip") tip.open()
        }
    }
    Component.onCompleted: field.forceActiveFocus(Qt.TabFocusReason)
}
