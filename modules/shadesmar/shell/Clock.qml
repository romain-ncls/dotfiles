// The time, and the date under it, as Plasma's clock has them.
import QtQuick
import Quickshell

Column {
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(clock.date, "dd/MM/yyyy")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11
    }
}
