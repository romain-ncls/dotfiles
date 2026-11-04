// One screen of the Silksong lock screen in Hyprland: what Plasma's lock screen makes of the
// wallpaper (scene/main.qml, its lock screen half: the world painted in watercolor, then the
// world, Hornet's day planned meanwhile) and of the prompt (prompt/LockScreen.qml: made once every
// screen has drawn its first frame), with the scene and the prompt as they are, by URL. The
// wallpaper's settings are Plasma's lock screen's (main.xml's defaults).
import QtQuick
import QtQuick.Window
import Quickshell

import "prompt/prompts.js" as Prompts

Item {
    id: root

    required property var screens
    required property string screenName
    required property url dataDir
    required property QtObject kit
    required property url art
    required property QtObject locker
    // The prompt couldn't be made: the lock screen hands the session over to hyprlock.
    signal broken()

    // The scene and the prompt by file: URL, not Quickshell's own (qs:), through which the types
    // beside them (HornetSprite.qml) aren't found in a linked folder.
    function file(path) {
        return "file://" + Quickshell.shellPath(path);
    }

    readonly property real gapMm: 15
    readonly property real latitude: 48.85
    readonly property real longitude: 2.35
    readonly property var dayHours: ["09:30", "10:00", "17:00", "17:30"]

    // Made once the surface has its size, then kept (main.qml).
    property bool seated: false
    readonly property bool canSeat: width > 0 && height > 0
    onCanSeatChanged: if (canSeat) seated = true

    Item {
        id: wallpaper
        anchors.fill: parent

        Loader {
            id: view
            anchors.fill: parent
            asynchronous: true
            active: root.seated && (!(painting.item?.present ?? false) || painting.item.up)
            visible: !(painting.item?.present ?? false) || painting.item.uncover

            Component.onCompleted: setSource(root.file("scene/WorldScene.qml"), {
                coverFirst: Qt.binding(() => !(painting.item?.present ?? false)),
                screens: Qt.binding(() => root.screens),
                screenName: Qt.binding(() => root.screenName),
                dataDir: root.dataDir,
                gapMm: root.gapMm,
                latitude: root.latitude,
                longitude: root.longitude,
                dayHours: root.dayHours,
                debug: false,
                everyFrame: true,
                nearHz: 60,
                watchFiles: false,
                paused: false
            })
        }

        property bool paintingGone: false
        Loader {
            id: painting
            anchors.fill: parent
            active: root.seated && !wallpaper.paintingGone

            Component.onCompleted: setSource(root.file("scene/Painting.qml"), {
                screens: Qt.binding(() => root.screens),
                screenName: Qt.binding(() => root.screenName),
                dataDir: root.dataDir,
                gapMm: root.gapMm,
                latitude: root.latitude,
                longitude: root.longitude,
                dayHours: root.dayHours,
                revealed: Qt.binding(() => view.item?.revealed ?? false)
            })
        }
        Connections {
            target: painting.item

            function onUpChanged() {
                if (painting.item.up) {
                    root.planDay();
                }
            }
            function onGoneChanged() {
                if (painting.item.gone) {
                    wallpaper.paintingGone = true;
                }
            }
        }
    }

    // Hornet's day, planned while the world is made (main.qml), let go with the painting.
    property QtObject dayPlanner: null
    property Component dayPlannerType: null
    function planDay() {
        dayPlannerType = Qt.createComponent(root.file("scene/DayPlanner.qml"), Component.Asynchronous);
        const make = () => {
            if (dayPlannerType?.status === Component.Ready && !dayPlanner && !wallpaper.paintingGone) {
                dayPlanner = dayPlannerType.createObject(root, { dataDir: root.dataDir });
            }
        };
        dayPlannerType.statusChanged.connect(make);
        make();
    }
    Connections {
        target: wallpaper

        function onPaintingGoneChanged() {
            if (wallpaper.paintingGone && root.dayPlanner) {
                root.dayPlanner.destroy();
                root.dayPlanner = null;
            }
        }
    }

    // The prompt, as LockScreen.qml makes it: once every screen has drawn its first frame
    // (prompts.js), or half a second on, a moment after it's due, a little at a time.
    property bool drawn: false
    property bool promptDue: false
    function makePrompt() {
        promptDue = true;
    }
    Timer {
        interval: 30
        running: root.promptDue && ui.status === Loader.Null
        onTriggered: ui.setSource(root.file("prompt/SilksongPrompt.qml"), {
            locker: root.locker,
            kit: root.kit,
            art: root.art,
            backdrop: wallpaper
        })
    }
    Connections {
        target: root.Window.window
        enabled: ui.status === Loader.Null

        function onFrameSwapped() {
            root.drawn = true;
            Prompts.shown();
        }
    }
    Timer {
        interval: 500
        running: ui.status === Loader.Null
        onTriggered: root.makePrompt()
    }
    Loader {
        id: ui
        anchors.fill: parent
        focus: true
        asynchronous: true

        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("Silksong lock screen: the prompt can't be made");
                root.broken();
            }
        }
    }
    // While the prompt is up, Caps Lock is read (Locker.qml).
    property bool promptShown: ui.item?.shown ?? false
    onPromptShownChanged: locker.promptsShown += promptShown ? 1 : -1

    Component.onCompleted: {
        if (canSeat) {
            seated = true;
        }
        Prompts.join(root);
    }
    Component.onDestruction: {
        if (promptShown) {
            locker.promptsShown--;
        }
        Prompts.leave(root);
    }
}
