/*
 * Silksong Aquarium: one fixed scene spread across the physical monitors,
 * with Hornet living in it. plasmashell runs one copy per screen and the lock
 * screen greeter runs its own; see world.js for how they stay in step.
 *
 * Sprites and scenes come from the player's own copy of the game, made by
 * tools/extract.py and tools/bake.py into ~/.local/share/silksong-wallpaper.
 */
import QtQuick
import QtQuick.Window
import QtCore

import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    Scene {
        anchors.fill: parent
        screens: Qt.application.screens
        screenName: root.Screen.name
        dataDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/silksong-wallpaper"
        sceneId: root.configuration.SceneId
        gapMm: root.configuration.GapMm
        unitMm: root.configuration.UnitMm
        debug: root.configuration.Debug
    }
}
