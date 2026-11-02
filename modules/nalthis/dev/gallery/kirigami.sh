#!/bin/bash
# Runs the Kirigami gallery with KDE's desktop QtQuick style, which draws
# through the application style (Darkly), as KDE apps get it (the bare QML
# runner doesn't pick it up on its own). Extra args: menu|combo|tooltip.
here=$(cd "$(dirname "$0")" && pwd)
QT_QUICK_CONTROLS_STYLE=org.kde.desktop exec /usr/lib/qt6/bin/qml "$here/kirigami.qml" -- "$@"
