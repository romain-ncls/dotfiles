/*
 * Renders each screen's view at given times, without Plasma, on a virtual display with
 * OpenGL (Hornet is coloured by a shader; the offscreen platform only has the software
 * renderer, which shows her uncoloured):
 *
 *   xvfb-run -a -s "-screen 0 5760x1200x24" env QT_QPA_PLATFORM=xcb \
 *       qml tools/preview.qml -- OUT_DIR [--world] TIME...
 *
 * TIME is seconds since the epoch, or HH:MM today (the world's daylight follows
 * the clock). Writes OUT_DIR/<screen>@<time>.png at each screen's real
 * resolution; tools/desk.py lays them out as they sit on the desk.
 */
import QtQuick
import QtQuick.Window
import QtCore

import "../plasma/contents/ui"

Window {
    id: win

    // This desk, as Qt.application.screens reports it.
    readonly property var screens: [
        { name: "DP-3", virtualX: 0, width: 1920, height: 1080, pixelDensity: 1920 / 476.2 },
        { name: "eDP-1", virtualX: 1920, width: 1920, height: 1200, pixelDensity: 1920 / 344 },
        { name: "HDMI-A-1", virtualX: 3840, width: 1920, height: 1080, pixelDensity: 1920 / 476.2 },
    ]
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

    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (win.pending > 0 || win.warmup-- > 0) {
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
