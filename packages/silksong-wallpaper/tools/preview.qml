/*
 * Renders each screen's view of the scene at given times, without Plasma:
 *
 *   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
 *       qml tools/preview.qml -- OUT_DIR TIME...
 *
 * writes OUT_DIR/<screen>@<time>.png at each screen's real resolution;
 * tools/desk.py lays them out as they sit on the desk.
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
    readonly property var times: args.slice(1).map(Number)
    property int step: 0
    property int pending: 0
    property int warmup: 10 // ticks to let the tiles load before the first capture

    width: 5760
    height: 1200
    visible: true

    Repeater {
        id: views
        model: win.screens

        Scene {
            required property var modelData
            x: modelData.virtualX
            width: modelData.width
            height: modelData.height
            screens: win.screens
            screenName: modelData.name
            dataDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/silksong-wallpaper"
            live: false
            time: win.times[win.step] ?? 0
            debug: false
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
                const file = `${win.outDir}/${view.screenName}@${win.times[win.step]}.png`;
                view.grabToImage(result => {
                    result.saveToFile(file);
                    if (--win.pending === 0) {
                        win.step++;
                    }
                });
            }
        }
    }
}
