/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Plasma's LockScreen.qml, choosing the prompt: the Silksong one (SilksongLockUi.qml) once
// tools/extract_ui.py has put the game's art in ~/.local/share/silksong-wallpaper/ui, Plasma's
// own (LockScreenUi.qml, linked from the system's shell) without it or if it can't be loaded.

import QtQuick
import QtQuick.Window
import QtCore

import "prompts.js" as Prompts

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
        asynchronous: true // made a little at a time between frames (below)
        onStatusChanged: {
            if (status === Loader.Error && source.toString().endsWith("SilksongLockUi.qml")) {
                console.warn("Silksong lock screen: falling back to Plasma's prompt");
                source = "LockScreenUi.qml";
            }
        }
    }

    // The prompt is made once every screen has drawn its first frame (the wallpaper's painting,
    // prompts.js): it only shows on a key or the mouse, and making it first (the first screen's
    // compiles it, a tenth of a second) would hold those frames back. Should no frame come (the
    // screen off), made anyway half a second on. Made a moment after it's due, not from within a
    // frame's handler, and a little at a time: each window takes the compositor's word on its
    // surface on the GUI thread, and until it has, its wallpaper's animations stand still (the
    // wallpaper's Painting.qml).
    property string prompt: ""
    property bool drawn: false
    property bool promptDue: false
    function makePrompt() {
        promptDue = true;
    }
    Timer {
        interval: 30
        running: root.promptDue && root.prompt !== "" && ui.source.toString() === ""
        onTriggered: ui.source = root.prompt
    }
    Connections {
        target: root.Window.window
        enabled: ui.source.toString() === ""

        function onFrameSwapped() {
            root.drawn = true;
            Prompts.shown();
        }
    }
    Timer {
        interval: 500
        running: ui.source.toString() === ""
        onTriggered: root.makePrompt()
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
        prompt = kit ? "SilksongLockUi.qml" : "LockScreenUi.qml";
        Prompts.join(root);
    }
    Component.onDestruction: Prompts.leave(root)
}
