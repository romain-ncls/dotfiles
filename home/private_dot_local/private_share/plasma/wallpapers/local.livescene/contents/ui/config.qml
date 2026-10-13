import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_SceneFolder: folder.text
    property alias cfg_Fps: fps.value
    property alias cfg_PauseWhenCovered: pause.checked

    QQC2.TextField {
        id: folder
        Kirigami.FormData.label: "Scene folder:"
        placeholderText: "/home/…/Pictures/Wallpapers/live/<scene>"
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    }
    QQC2.SpinBox {
        id: fps
        Kirigami.FormData.label: "Frame rate:"
        from: 5
        to: 60
    }
    QQC2.CheckBox {
        id: pause
        text: "Pause while a maximized or fullscreen window covers the desktop"
    }
}
