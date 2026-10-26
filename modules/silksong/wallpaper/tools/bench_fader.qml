/*
 * What the lock screen draws over its wallpaper (plasma-desktop's lockscreen/LockScreenUi.qml),
 * for tools/bench.qml --fader: its root fading in at launch, holding breeze's WallpaperFader,
 * which draws a blurred, colour-matrixed live copy of the wallpaper even while the password
 * prompt is hidden (a blur of radius 0 and an identity matrix, every layer still rendered).
 * Needs the system's QML modules (qml6 finds them on Arch).
 */
import QtQuick

import org.kde.breeze.components

Item {
    id: lockScreenRoot
    property Item wallpaper

    NumberAnimation on opacity {
        from: 0
        to: 1
        duration: 800 // Kirigami.Units.veryLongDuration * 2
    }

    WallpaperFader {
        anchors.fill: parent
        state: "off"
        source: lockScreenRoot.wallpaper
        mainStack: mainStack
        footer: footer
        clock: clock
    }

    // Empty stand-ins for what it fades, siblings as in LockScreenUi, so that they are there
    // by the time its state names them.
    Item {
        id: clock
        property Item shadow: Item {}
    }

    Item {
        id: mainStack
    }

    Item {
        id: footer
    }
}
