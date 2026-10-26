/*
 * Silksong Aquarium: Silksong spread across the physical monitors, with Hornet
 * living in it. plasmashell runs one copy per screen and the lock screen
 * greeter runs its own; see world.js for how they stay in step.
 *
 * Sprites and scenes come from the player's own copy of the game, made by
 * tools/extract.py, tools/bake.py (single scenes) and tools/world.py (the
 * aquarium) into ~/.local/share/silksong-wallpaper.
 */
import QtQuick
import QtQuick.Window
import QtCore

import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property url dataDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/silksong-wallpaper"
    // The desktop (plasmashell), rather than the lock screen, which lives for minutes.
    readonly property bool desktop: Qt.application.name === "plasmashell"

    // The scene is made once the wallpaper is in its window, at its size: until then (the greeter
    // makes it before the lock screen it goes in) root.Screen is the primary screen, and each
    // screen would start loading the primary screen's images. Then it stays, even moved to another
    // window, rather than being made again.
    property bool seated: false
    readonly property bool canSeat: Window.window !== null && width > 0 && height > 0
    onCanSeatChanged: if (canSeat) seated = true
    // Loading until the scene shows: on the desktop, Plasma's splash screen and panels wait for it.
    // Set once made (WallpaperItem clears it then), before the scene is made: a single scene shows
    // as soon as it's made.
    Component.onCompleted: {
        loading = true;
        if (canSeat) {
            seated = true;
        }
    }

    // Plasma's accent colour, when taken from the wallpaper, would otherwise come from a picture
    // of it taken as it loads, all black. Hornet's red instead: her cloak's, in her sheets.
    accentColor: "#723c47"

    // A desktop on another activity, or whose screen was taken away, is only hidden by Plasma,
    // which keeps it: its world stands still at once (WorldScene running), and after 10 minutes
    // hidden it's let go with all it loaded, to be made again, from black, once shown.
    property bool released: false
    Timer {
        interval: 600000
        running: root.desktop && root.seated && !root.visible
        onTriggered: root.released = true
    }
    onVisibleChanged: if (visible) released = false

    // On the lock screen, made once every screen shows its painting (below), hidden under it until
    // it uncovers the world. Loaded by URL, as Scene.qml below: WorldScene.qml and life.js are
    // only compiled then, not before the painting's first frame (the lock screen compiles it all
    // at every lock). Its properties come with it, bindings included. Compiled and made
    // asynchronously, a little at a time between frames: made at once, it would hold the
    // painting's brush back (Painting.qml).
    Loader {
        id: view
        anchors.fill: parent
        asynchronous: true
        active: root.seated && root.configuration.SceneId === "world" && !root.released
            && (!(painting.item?.present ?? false) || painting.item.up)
        visible: !(painting.item?.present ?? false) || painting.item.uncover

        Component.onCompleted: setSource(Qt.resolvedUrl("WorldScene.qml"), {
            coverFirst: Qt.binding(() => !(painting.item?.present ?? false)),
            screens: Qt.binding(() => Qt.application.screens),
            screenName: Qt.binding(() => root.Screen.name),
            dataDir: root.dataDir,
            gapMm: Qt.binding(() => root.configuration.GapMm),
            latitude: Qt.binding(() => root.configuration.Latitude),
            longitude: Qt.binding(() => root.configuration.Longitude),
            dayHours: Qt.binding(() => [root.configuration.NightUntil ?? "", root.configuration.DayFrom ?? "",
                                        root.configuration.DayUntil ?? "", root.configuration.NightFrom ?? ""]),
            debug: Qt.binding(() => root.configuration.Debug),
            everyFrame: Qt.binding(() => (root.configuration.Motion ?? 0) === 0),
            nearHz: Qt.binding(() => [60, 60, 30, 0][root.configuration.Motion ?? 0] ?? 60),
            watchFiles: root.desktop,
            paused: Qt.binding(() => pauser.item?.paused ?? false)
        })
    }
    // Hornet's day planned meanwhile (DayPlanner.qml), from when the world is made: compiled away from
    // the GUI thread (it imports life.js), then made at once (it's small), not after the world as a
    // Loader making it asynchronously would; by URL, as WorldScene.qml is (life.js compiled only
    // then). Let go with the painting.
    property QtObject dayPlanner: null
    property Component dayPlannerType: null // (kept while it's compiled)
    function planDay() {
        dayPlannerType = Qt.createComponent(Qt.resolvedUrl("DayPlanner.qml"), Component.Asynchronous);
        const make = () => {
            if (dayPlannerType?.status === Component.Ready && !dayPlanner && !paintingGone) {
                dayPlanner = dayPlannerType.createObject(root, { dataDir: root.dataDir });
            }
        };
        dayPlannerType.statusChanged.connect(make);
        make();
    }
    Connections {
        target: painting.item

        function onUpChanged() {
            if (painting.item.up) {
                root.planDay();
            }
        }
    }
    onPaintingGoneChanged: {
        if (paintingGone && dayPlanner) {
            dayPlanner.destroy();
            dayPlanner = null;
        }
    }
    // On the lock screen, the world painted in watercolor (Painting.qml) in the first frame while
    // the world is made, washing away over it once it's in; then let go. Not on the desktop, where
    // Plasma's splash screen covers the wallpaper until the world shows.
    property bool paintingGone: false
    Loader {
        id: painting
        anchors.fill: parent
        active: root.seated && !root.desktop && root.configuration.SceneId === "world" && !root.paintingGone

        sourceComponent: Painting {
            screens: Qt.application.screens
            screenName: root.Screen.name
            dataDir: root.dataDir
            gapMm: root.configuration.GapMm
            latitude: root.configuration.Latitude
            longitude: root.configuration.Longitude
            dayHours: [root.configuration.NightUntil ?? "", root.configuration.DayFrom ?? "",
                       root.configuration.DayUntil ?? "", root.configuration.NightFrom ?? ""]
            revealed: view.item?.revealed ?? false
            onGoneChanged: if (gone) root.paintingGone = true
        }
    }
    // On the desktop, standing still while windows are in front of it (PauseWhen). Pauser.qml
    // imports Plasma's task manager, loaded by URL as Scene.qml below: the lock screen, which
    // never stands still, doesn't even compile it.
    Loader {
        id: pauser
        active: root.desktop && root.configuration.PauseWhen > 0 && view.active

        Component.onCompleted: setSource(Qt.resolvedUrl("Pauser.qml"), {
            mode: Qt.binding(() => root.configuration.PauseWhen),
            screenGeometry: Qt.binding(() => Qt.rect(root.Screen.virtualX, root.Screen.virtualY, root.Screen.width, root.Screen.height))
        })
    }
    Connections {
        target: view.item

        function onRevealedChanged() {
            if (view.item.revealed) {
                root.loading = false;
            }
        }
    }

    // A single scene (tools/bake.py), loaded by URL so that Scene.qml and what it imports are only
    // compiled when one is chosen. Its required properties can only come with it, as initial
    // properties; the Loader keeps them for each time it makes it again, bindings included.
    Loader {
        anchors.fill: parent
        active: root.seated && root.configuration.SceneId !== "world"

        onStatusChanged: {
            if (status === Loader.Ready || status === Loader.Error) {
                root.loading = false;
            }
        }
        Component.onCompleted: setSource(Qt.resolvedUrl("Scene.qml"), {
            screens: Qt.binding(() => Qt.application.screens),
            screenName: Qt.binding(() => root.Screen.name),
            dataDir: root.dataDir,
            sceneId: Qt.binding(() => root.configuration.SceneId),
            gapMm: Qt.binding(() => root.configuration.GapMm),
            unitMm: Qt.binding(() => root.configuration.UnitMm),
            debug: Qt.binding(() => root.configuration.Debug)
        })
    }
}
