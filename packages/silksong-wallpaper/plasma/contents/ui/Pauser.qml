/*
 * When the desktop's world stands still (PauseWhen), from the windows Plasma's task manager sees.
 * Only plasmashell loads it (main.qml): the lock screen never stands still, and has no task
 * manager to ask.
 *
 *   1  a window is maximized or full screen on this screen (as Plasma's own picture wallpaper
 *      stops an animated picture)
 *   2  any window is focused, on any screen: every screen stops and starts together, as one
 *      stopped beside one playing could show Hornet twice
 *
 * The windows the taskbar leaves out (KRunner, Yakuake) don't count, nor do any while the desktop
 * is shown (Show Desktop moves the windows aside without minimizing them); nor, focused,
 * plasmashell's own (this wallpaper's settings, where a change should be seen).
 */
import QtQuick
import org.kde.kwindowsystem
import org.kde.taskmanager as TaskManager

Item {
    id: pauser

    required property int mode
    required property rect screenGeometry
    readonly property bool wanted: !KWindowSystem.showingDesktop && (mode === 1 ? covered : mode === 2 ? focused : false)

    // Stands still at once, but moves again only once nothing has asked it to stand still for a
    // moment: on Wayland, focus going from one window to another first leaves none focused, which
    // would start every screen for a frame.
    property bool paused: false
    onWantedChanged: {
        if (wanted) {
            settle.stop();
            paused = true;
        } else {
            settle.restart();
        }
    }
    Timer {
        id: settle
        interval: 100
        onTriggered: pauser.paused = false
    }

    // Worked out again whenever windows come or go too: the task manager only tells of a newly
    // focused window when one gains or loses focus, not when it fills in (after this is first
    // worked out) nor when a window comes in focused. Not plasmashell's own windows, whose app id
    // it gives with or without its desktop file's extension.
    readonly property bool focused: tasks.count > 0 && tasks.activeTask.valid
        && String(tasks.data(tasks.activeTask, TaskManager.AbstractTasksModel.AppId)).replace(/\.desktop$/, "") !== "org.kde.plasmashell"

    // Looked for again once the windows have changed, at most once a turn of the event loop (a
    // window being dragged changes many times a frame), and only for what can cover the screen: a
    // terminal's or a browser's title changes all the time.
    property bool covered: false
    readonly property var coverRoles: [TaskManager.AbstractTasksModel.IsMaximized, TaskManager.AbstractTasksModel.IsFullScreen,
        TaskManager.AbstractTasksModel.IsMinimized, TaskManager.AbstractTasksModel.ScreenGeometry]
    function scan() {
        let any = false;
        for (let i = 0; i < tasks.count && !any; i++) {
            const task = tasks.index(i, 0);
            any = tasks.data(task, TaskManager.AbstractTasksModel.IsMaximized) === true
                || tasks.data(task, TaskManager.AbstractTasksModel.IsFullScreen) === true;
        }
        covered = any;
    }
    onModeChanged: if (mode === 1) Qt.callLater(scan)
    Component.onCompleted: {
        paused = wanted;
        if (mode === 1) {
            Qt.callLater(scan);
        }
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        activity: activityInfo.currentActivity
        filterByActivity: true
        filterByCurrentVirtualDesktop: true
        filterMinimized: true
        screenGeometry: pauser.screenGeometry
        filterByScreen: pauser.mode === 1
    }
    Connections {
        target: tasks
        enabled: pauser.mode === 1

        function onRowsInserted() {
            Qt.callLater(pauser.scan);
        }
        function onRowsRemoved() {
            Qt.callLater(pauser.scan);
        }
        function onModelReset() {
            Qt.callLater(pauser.scan);
        }
        function onDataChanged(topLeft, bottomRight, roles) {
            // No roles named: any of them may have changed.
            if (roles.length === 0 || roles.some(role => pauser.coverRoles.indexOf(role) >= 0)) {
                Qt.callLater(pauser.scan);
            }
        }
    }
}
