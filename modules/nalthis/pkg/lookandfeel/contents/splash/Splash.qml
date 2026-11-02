/*
    Nalthis splash: the palette's darkest surface, Plasma's mark dimmed, and
    a thin accent bar that fills as Plasma starts (KSplash counts stages
    up to 6). Everything else falls back to Breeze's global theme.
*/

import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false
    color: Kirigami.Theme.backgroundColor

    property int stage

    onStageChanged: {
        if (stage == 2) {
            fadeIn.running = true;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // Plasma's mark, from Breeze's splash (the icon theme only has
        // badge versions of it).
        Image {
            id: mark
            anchors.centerIn: parent
            readonly property real size: Kirigami.Units.gridUnit * 4
            source: "/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash/images/plasma.svgz"
            sourceSize.width: size
            sourceSize.height: size
            asynchronous: true
            opacity: 0.85
        }

        // The progress: a 3 px track in the text color, the accent over it.
        Rectangle {
            id: track
            anchors.top: mark.bottom
            anchors.topMargin: Kirigami.Units.gridUnit * 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: Kirigami.Units.gridUnit * 8
            height: 3
            radius: 1.5
            color: Qt.alpha(Kirigami.Theme.textColor, 0.14)

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.min(root.stage, 6) / 6
                color: Kirigami.Theme.highlightColor
                Behavior on width {
                    NumberAnimation {
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }

    OpacityAnimator {
        id: fadeIn
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
