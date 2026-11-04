// The Silksong lock screen in Hyprland (README, Lock screen): on every screen the world painted in
// watercolor, then the world, and the game's prompt, as on Plasma's lock screen: the scene
// (scene/, Plasma's wallpaper) and the prompt (prompt/SilksongPrompt.qml) as they are, by URL.
// `qs -c silksong-lock` locks the session as it starts and quits once it's unlocked: modules/
// hyprland's lock-screen runs it, and hyprlock instead should it fail. Without the game's art
// (tools/extract_ui.py) it quits at once, status 2; should the prompt fail, status 3, the session
// still locked, which hyprlock takes over.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property url dataDir: "file://" + (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/silksong-wallpaper"
    readonly property url uiDir: dataDir + "/ui/"
    // The prompt needs a Kit.qml of this version (tools/extract_ui.py's KIT_VERSION) or later.
    readonly property int kitVersion: 2
    property QtObject kit: null

    // The screens as the scene reads them: Qt's, as Plasma's. The dev rigs' outputs have no size
    // in millimetres: SILKSONG_DESK gives them the desk's, left to right ("DP-3:476x268,…"), names
    // included, which the views tools/derive.py made for the desk go by.
    readonly property var desk: (Quickshell.env("SILKSONG_DESK") ?? "").split(",").filter(s => s !== "").map(s => {
        const [name, mm] = s.split(":");
        const [w, h] = mm.split("x").map(Number);
        return { name: name, w: w, h: h };
    })
    readonly property var screens: {
        const qt = Array.from(Qt.application.screens);
        if (desk.length === 0) {
            return qt;
        }
        return qt.sort((a, b) => a.virtualX - b.virtualX).map((s, i) => ({
            name: desk[i]?.name ?? s.name,
            virtualX: s.virtualX,
            virtualY: s.virtualY,
            width: s.width,
            height: s.height,
            // QScreen::physicalDotsPerInch() / 25.4, as Qt works it out (tools/desk.js)
            pixelDensity: desk[i] ? (s.height / desk[i].h + s.width / desk[i].w) * 12.7 / 25.4 : s.pixelDensity
        }));
    }
    function nameOf(screen) {
        if (desk.length === 0) {
            return screen?.name ?? "";
        }
        const i = Array.from(Qt.application.screens).sort((a, b) => a.virtualX - b.virtualX).findIndex(s => s.name === screen?.name);
        return desk[i]?.name ?? screen?.name ?? "";
    }

    Locker {
        id: auth

        onUnlocked: {
            lock.locked = false;
            shell.quitWith(0);
        }
    }
    // Quits with this status in a moment: for the compositor to hear an unlock first, and as
    // Quickshell only hears Qt.exit() once the shell is loaded.
    function quitWith(status) {
        quit.status = status;
        quit.start();
    }
    Timer {
        id: quit
        property int status: 0
        interval: 100
        onTriggered: Qt.exit(status)
    }

    WlSessionLock {
        id: lock

        locked: shell.kit !== null
        // Every screen shows its surface: lock-screen waits for this before it leaves the lock to it.
        onSecureChanged: if (secure) marker.running = true

        WlSessionLockSurface {
            id: surface

            color: "black"

            LockSurface {
                anchors.fill: parent
                screens: shell.screens
                screenName: shell.nameOf(surface.screen)
                dataDir: shell.dataDir
                kit: shell.kit
                art: shell.uiDir
                locker: auth
                onBroken: shell.quitWith(3)
            }
        }
    }
    Process {
        id: marker
        command: ["touch", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/silksong-lock.locked"]
    }

    Component.onCompleted: {
        const component = Qt.createComponent(uiDir + "Kit.qml");
        const made = component.status === Component.Ready ? component.createObject(shell) : null;
        if (!made || !(made.version >= kitVersion)) {
            console.warn("Silksong lock screen: no game's art, or from an older tools/extract_ui.py; run it again");
            quitWith(2);
            return;
        }
        kit = made;
    }
}
