/*
 * Hornet's day, planned as soon as the worlds may be made (main.qml), a little at a time (life.js
 * prepareDay), while the world itself is made rather than once it's made: the world shares what's
 * planned (WorldScene's planSome) and has everything it shows that much sooner. The world's data
 * and her clips read by the URLs WorldScene reads them by (on the lock screen, which doesn't watch
 * the files), so read once, and compiled away from the GUI thread.
 */
import QtQuick

import "life.js" as Life

Item {
    id: root

    required property url dataDir

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
                planSome();
            }
        };
        if (component.status === Component.Loading) {
            component.statusChanged.connect(made);
        } else {
            made();
        }
    }

    property var prep: null
    function planSome() {
        if (!world || !clips) {
            return;
        }
        if (!prep) {
            prep = Life.prepareDay(world, clips, Date.now() / 1000);
        }
        if (!prep.step(25)) {
            Qt.callLater(planSome);
        }
    }
    Component.onCompleted: {
        read("/world/World.qml?v=0", data => world = data.world);
        read("/Sprites.qml?v=0", data => clips = data.clips);
    }
}
