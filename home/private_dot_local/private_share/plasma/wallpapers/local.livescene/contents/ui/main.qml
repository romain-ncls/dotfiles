import QtQuick
import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager
import org.kde.kwindowsystem

// Loads <SceneFolder>/Scene.qml and drives its `time` (seconds). The clock
// stops while a maximized or fullscreen window covers the desktop, unless
// the desktop is being shown (Meta+D hides windows without minimizing them).
WallpaperItem {
    id: wallpaper

    readonly property string folder: configuration.SceneFolder
    readonly property int fps: Math.max(1, Math.min(60, configuration.Fps))
    readonly property bool paused: configuration.PauseWhenCovered && coverCount > 0 && !KWindowSystem.showingDesktop
    property real elapsed: 0
    property int coverCount: 0

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Loader {
        id: scene
        anchors.fill: parent
        source: wallpaper.folder ? "file://" + wallpaper.folder + "/Scene.qml" : ""
        onLoaded: item.time = Qt.binding(() => wallpaper.elapsed)
    }

    Timer {
        property double last: 0
        interval: Math.round(1000 / wallpaper.fps)
        repeat: true
        running: scene.status === Loader.Ready && !wallpaper.paused
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now();
            wallpaper.elapsed += Math.min(now - last, 250) / 1000;
            last = now;
        }
    }

    TaskManager.VirtualDesktopInfo { id: desktops }
    TaskManager.ActivityInfo { id: activities }
    TaskManager.TasksModel {
        id: tasks
        filterByVirtualDesktop: true
        filterByActivity: true
        filterMinimized: true
        virtualDesktop: desktops.currentDesktop
        activity: activities.currentActivity
    }

    function recount() {
        let n = 0;
        for (let i = 0; i < covers.count; i++) {
            const o = covers.objectAt(i);
            if (o && o.covering) n++;
        }
        coverCount = n;
    }

    Instantiator {
        id: covers
        model: tasks
        delegate: QtObject {
            readonly property bool covering: model.IsMaximized === true || model.IsFullScreen === true
            onCoveringChanged: wallpaper.recount()
        }
        onObjectAdded: wallpaper.recount()
        onObjectRemoved: wallpaper.recount()
    }
}
