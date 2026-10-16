/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Plasma's LockScreen.qml, choosing the prompt: the Silksong one (SilksongLockUi.qml) once
// tools/extract_ui.py has put the game's art in ~/.local/share/silksong-wallpaper/ui, Plasma's
// own (LockScreenUi.qml, linked from the system's shell) without it or if it can't be loaded.

import QtQuick
import QtCore

Item {
    id: root
    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // These are magical properties that kscreenlocker looks for
    property bool viewVisible: false

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    implicitWidth: 800
    implicitHeight: 600

    // Given by kscreenlocker: the user's full name, else the login.
    readonly property string userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : ""
    readonly property url uiDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/silksong-wallpaper/ui/"
    // Kit.qml lists the art; read once, synchronously, before the prompt is chosen. The prompt
    // needs a Kit.qml of this version (tools/extract_ui.py's KIT_VERSION) or later.
    readonly property int kitVersion: 2
    property QtObject kit: null

    Loader {
        id: ui
        anchors.fill: parent
        focus: true
        onStatusChanged: {
            if (status === Loader.Error && source.toString().endsWith("SilksongLockUi.qml")) {
                console.warn("Silksong lock screen: falling back to Plasma's prompt");
                source = "LockScreenUi.qml";
            }
        }
    }

    Component.onCompleted: {
        const component = Qt.createComponent(uiDir + "Kit.qml");
        if (component.status === Component.Ready) {
            kit = component.createObject(root);
        }
        if (kit && !(kit.version >= kitVersion)) {
            console.warn("Silksong lock screen: the game's art is from an older tools/extract_ui.py; run it again");
            kit = null;
        }
        ui.source = kit ? "SilksongLockUi.qml" : "LockScreenUi.qml";
    }
}
