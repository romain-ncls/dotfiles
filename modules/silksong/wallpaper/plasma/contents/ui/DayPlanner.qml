/*
 * Hornet's day, planned on a worker thread (planner.mjs) from the world's data and her clips as
 * soon as they're read, while the lock screen makes the world (main.qml, and on Hyprland as it
 * starts: ../../../quickshell/shell.qml): the screens take what it plans as it comes (WorldScene's
 * planned) rather than plan it themselves on the GUI thread, a little at a time between its frames
 * (0.6 s of it, which took a second, the world waiting for it). The world's data and her clips are
 * read by the URLs WorldScene reads them by (on the lock screen, which doesn't watch the files),
 * so read once, and compiled away from the GUI thread.
 */
import QtQuick

QtObject {
    id: root

    required property url dataDir

    // The day's plans (life.mjs planAhead) once made; null meanwhile; undefined should the worker
    // not start (the screens then plan it themselves).
    property var planned: null

    property var world: null
    property var clips: null
    property var reading: [] // (kept while they're compiled)
    // A file of data, compiled asynchronously, then made at once; given to take.
    function read(file, take) {
        const component = Qt.createComponent(root.dataDir + file, Component.Asynchronous);
        reading.push(component);
        const made = () => {
            if (component.status === Component.Ready) {
                take(component.createObject(root));
                ask();
            }
        };
        if (component.status === Component.Loading) {
            component.statusChanged.connect(made);
        } else {
            made();
        }
    }

    property WorkerScript worker: WorkerScript {
        source: "planner.mjs"
        onReadyChanged: root.ask()
        onMessage: message => root.planned = message.planned
    }
    property bool asked: false
    function ask() {
        if (!asked && worker.ready && world && clips) {
            asked = true;
            worker.sendMessage({ world: world, clips: clips, t: Date.now() / 1000 });
        }
    }
    property Timer givingUp: Timer {
        interval: 3000
        running: !root.worker.ready && root.planned === null
        onTriggered: root.planned = undefined
    }
    Component.onCompleted: {
        read("/world/World.qml?v=0", data => world = data.world);
        read("/Sprites.qml?v=0", data => clips = data.clips);
    }
}
