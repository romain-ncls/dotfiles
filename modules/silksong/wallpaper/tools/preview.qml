/*
 * Renders each screen's view at given times, without Plasma, on a virtual display with
 * OpenGL (Hornet is coloured by a shader; the offscreen platform only has the software
 * renderer, which shows her uncoloured), with the system's image formats as Plasma has them:
 *
 *   xvfb-run -a -s "-screen 0 5760x1200x24" env QT_QPA_PLATFORM=xcb \
 *       qml6 tools/preview.qml -- OUT_DIR [--world] TIME...
 *
 * TIME is seconds since the epoch, or HH:MM today (the world's daylight follows
 * the clock). Writes OUT_DIR/<screen>@<time>.png at each screen's real
 * resolution, once every view has everything it shows; tools/desk.py lays them out as
 * they sit on the desk.
 */
import QtQuick
import QtQuick.Window
import QtCore

import "../plasma/contents/ui"
import "desk.js" as Desk

Window {
    id: win

    readonly property var screens: Desk.screens
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property string outDir: args[0]
    readonly property bool worldMode: args.indexOf("--world") >= 0
    readonly property var labels: args.slice(1).filter(a => a !== "--world")
    readonly property var times: labels.map(a => {
        const hm = a.match(/^(\d+):(\d+)$/);
        if (!hm) {
            return Number(a);
        }
        const d = new Date();
        d.setHours(Number(hm[1]), Number(hm[2]), 0, 0);
        return d.getTime() / 1000;
    })
    readonly property url dataDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/silksong-wallpaper"
    property int step: 0
    property int pending: 0
    property int warmup: 10 // ticks to let the tiles load before the first capture

    width: 5760
    height: 1200
    visible: true

    Component {
        id: sceneView
        Scene {
            anchors.fill: parent
            screens: win.screens
            gapMm: Desk.gapMm
            screenName: parent.screenName
            dataDir: win.dataDir
            live: false
            time: win.times[win.step] ?? 0
            debug: false
        }
    }
    Component {
        id: worldView
        WorldScene {
            anchors.fill: parent
            screens: win.screens
            gapMm: Desk.gapMm
            screenName: parent.screenName
            dataDir: win.dataDir
            live: false
            time: win.times[win.step] ?? 0
            debug: false
        }
    }

    Repeater {
        id: views
        model: win.screens

        Loader {
            required property var modelData
            readonly property string screenName: modelData.name
            x: modelData.virtualX
            width: modelData.width
            height: modelData.height
            sourceComponent: win.worldMode ? worldView : sceneView
        }
    }

    // Whether every view has all it shows in: views that keep track say so (settled); for the
    // others, the warm-up has to do.
    function settled() {
        for (let i = 0; i < views.count; i++) {
            if (!(views.itemAt(i).item?.settled ?? true)) {
                return false;
            }
        }
        return true;
    }

    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (win.pending > 0 || win.warmup-- > 0 || !win.settled()) {
                return;
            }
            if (win.step >= win.times.length) {
                Qt.quit();
                return;
            }
            win.pending = views.count;
            for (let i = 0; i < views.count; i++) {
                const view = views.itemAt(i);
                const file = `${win.outDir}/${view.screenName}@${win.labels[win.step].replace(":", "h")}.png`;
                view.grabToImage(result => {
                    result.saveToFile(file);
                    if (--win.pending === 0) {
                        win.step++;
                        win.warmup = 6; // the next time's sheets load in the background
                    }
                });
            }
        }
    }
}
