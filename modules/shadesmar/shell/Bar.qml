// The bar: the desktops on the left; the tray, volume, battery and clock on
// the right.
import QtQuick
import QtQuick.Layouts
import Quickshell

PanelWindow {
    id: bar

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.bar

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 16

        Desktops {}

        Item {
            Layout.fillWidth: true
        }

        Tray {
            window: bar
        }
        Volume {}
        Battery {}
        Clock {}
    }
}
