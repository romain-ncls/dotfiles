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

    // The screens as the scene reads them, as Plasma's: Qt's, in the sizes KWin gives them, the
    // EDID's detailed timing's millimetres (476 by 268), which tools/derive.py made this desk's views
    // for. Hyprland gives the EDID's whole centimetres instead (480 by 270): the world would be laid
    // out a little wider, and each screen, its own view not found, would read the tiles it shows,
    // many times the work. The dev rigs' outputs have no size at all: SILKSONG_DESK gives them the
    // desk's, left to right ("DP-3:476x268,…"), names included, which the views go by.
    readonly property var desk: (Quickshell.env("SILKSONG_DESK") ?? "").split(",").filter(s => s !== "").map(s => {
        const [name, mm] = s.split(":");
        const [w, h] = mm.split("x").map(Number);
        return { name: name, w: w, h: h };
    })
    // The EDID's sizes by output, read as the lock screen starts (edid below); the scene is made once
    // they're in, or without them a moment on (sized).
    property var edidMm: ({})
    property bool sized: desk.length > 0
    // QScreen::physicalDotsPerInch() / 25.4, as Qt works it out (tools/desk.js)
    function density(s, mm) {
        return (s.height / mm.h + s.width / mm.w) * 12.7 / 25.4;
    }
    readonly property var screens: {
        const qt = Array.from(Qt.application.screens);
        const standIn = (s, name, mm) => ({
            name: name,
            virtualX: s.virtualX,
            virtualY: s.virtualY,
            width: s.width,
            height: s.height,
            pixelDensity: mm ? density(s, mm) : s.pixelDensity
        });
        if (desk.length === 0) {
            return qt.map(s => standIn(s, s.name, edidMm[s.name]));
        }
        return qt.sort((a, b) => a.virtualX - b.virtualX).map((s, i) => standIn(s, desk[i]?.name ?? s.name, desk[i]));
    }
    Process {
        id: edid

        running: shell.desk.length === 0
        // Each connected output's first detailed timing: its pixel clock, then its image size in mm.
        command: ["sh", "-c", "for f in /sys/class/drm/card*-*/edid; do set -- $(od -An -tu1 -j54 -N15 \"$f\" 2>/dev/null); [ $# -eq 15 ] && [ $(($1 + $2)) -gt 0 ] || continue; n=${f%/edid}; n=${n##*/}; echo \"${n#card*-} $((${13} + ((${15} >> 4) << 8))) $((${14} + ((${15} & 15) << 8)))\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (shell.sized) {
                    return;
                }
                const sizes = {};
                for (const line of text.split("\n")) {
                    const [name, w, h] = line.trim().split(" ");
                    if (name && Number(w) > 0 && Number(h) > 0) {
                        sizes[name] = { w: Number(w), h: Number(h) };
                    }
                }
                console.info("Silksong lock screen: sizes from the EDID:", Object.keys(sizes).map(n => `${n} ${sizes[n].w}×${sizes[n].h} mm`).join(", ") || "none");
                shell.edidMm = sizes;
                shell.sized = true;
            }
        }
    }
    Timer {
        interval: 300
        running: !shell.sized
        onTriggered: shell.sized = true
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
                sized: shell.sized
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
