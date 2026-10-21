import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property int cfg_FillMode
    property alias formLayout: root

    QQC2.ComboBox {
        Kirigami.FormData.label: "Positioning:"
        textRole: "label"
        valueRole: "fillMode"
        model: [
            { "label": "Scaled and cropped", "fillMode": Image.PreserveAspectCrop },
            { "label": "Scaled, keep proportions", "fillMode": Image.PreserveAspectFit },
            { "label": "Centered", "fillMode": Image.Pad },
        ]
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(root.cfg_FillMode))
        onActivated: root.cfg_FillMode = currentValue
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 25
        wrapMode: Text.Wrap
        text: "Pictures come from Windows Spotlight, Bing and Wallhaven. Right-click the desktop to like the current one, or dislike it to get another right away: the backdrop daemon learns from both. Sources and timing are set in the NixOS services.backdrop options."
    }
}
