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

    Component {
        id: sceneView
        Scene {
            screens: Qt.application.screens
            screenName: root.Screen.name
            dataDir: root.dataDir
            sceneId: root.configuration.SceneId
            gapMm: root.configuration.GapMm
            unitMm: root.configuration.UnitMm
            debug: root.configuration.Debug
        }
    }

    Component {
        id: worldView
        WorldScene {
            screens: Qt.application.screens
            screenName: root.Screen.name
            dataDir: root.dataDir
            gapMm: root.configuration.GapMm
            latitude: root.configuration.Latitude
            longitude: root.configuration.Longitude
            debug: root.configuration.Debug
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.configuration.SceneId === "world" ? worldView : sceneView
    }
}
