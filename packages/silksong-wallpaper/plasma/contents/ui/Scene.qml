/*
 * What one screen sees of the world. Plain QtQuick, so tools/preview.qml can
 * lay several of these side by side without Plasma.
 */
import QtQuick
import QtQuick.Shapes

import "world.js" as World

Item {
    id: root

    required property var screens // Qt.application.screens, or stand-ins with the same fields
    required property string screenName
    required property url dataDir
    property string sceneId: "mosshome"
    property real gapMm: 15
    property real unitMm: 16.3 // size of one game unit on the glass
    property bool debug: false

    // Seconds since the epoch. Driven by the wall clock unless live is off.
    property bool live: true
    property real time: Date.now() / 1000

    readonly property var layout: World.layout(screens, gapMm)
    readonly property var me: layout.screens[screenName] ?? { x: 0, y: 0, w: width / 4, h: height / 4 }
    readonly property real pxPerMm: width / me.w
    readonly property real pxPerUnit: pxPerMm * unitMm
    readonly property url sceneDir: dataDir + "/scenes/" + sceneId

    readonly property var clips: sprites.item?.clips ?? null
    readonly property var scene: sceneData.item?.scene ?? null
    readonly property var hornet: clips && scene ? World.hornetAt(clips, scene, time) : null

    // Hornet is drawn on this screen (with a margin for her size and light).
    readonly property bool hornetHere: hornet !== null
        && hornet.x * unitMm > me.x - 120 && hornet.x * unitMm < me.x + me.w + 120

    function toX(xMm) {
        return (xMm - me.x) * pxPerMm;
    }
    function toY(yMm) {
        return height - (yMm - me.y) * pxPerMm;
    }

    // Full frame rate only while Hornet is on this screen; elsewhere just keep
    // the clock close enough to notice her coming.
    FrameAnimation {
        running: root.live && root.hornetHere
        onTriggered: root.time = Date.now() / 1000
    }
    Timer {
        interval: 250
        repeat: true
        running: root.live && !root.hornetHere
        onTriggered: root.time = Date.now() / 1000
    }

    Loader {
        id: sprites
        source: root.dataDir + "/Sprites.qml"
    }
    Loader {
        id: sceneData
        source: root.sceneDir + "/Scene.qml"
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // One baked layer, cut in tiles; each screen only loads the tiles it shows.
    component Layer: Item {
        id: layer
        required property var tiles
        anchors.fill: parent

        Repeater {
            model: layer.tiles

            Image {
                required property var modelData
                readonly property real unitsX: modelData.x / root.scene.pixelsPerUnit
                readonly property real unitsW: modelData.width / root.scene.pixelsPerUnit
                readonly property bool shown: (unitsX + unitsW) * root.unitMm > root.me.x && unitsX * root.unitMm < root.me.x + root.me.w

                visible: shown
                source: shown ? root.sceneDir + "/" + modelData.file : ""
                x: Math.floor(root.toX(unitsX * root.unitMm))
                y: Math.floor(root.toY(root.scene.height * root.unitMm))
                width: Math.ceil(unitsW * root.pxPerUnit) + 1
                height: Math.ceil(root.scene.height * root.pxPerUnit)
                sourceSize.width: width
                asynchronous: true
                cache: false
                smooth: true
            }
        }
    }

    Layer {
        tiles: root.scene?.layers.back ?? []
    }

    // The light Hornet carries (screen-blended in game, baked as white over transparency).
    Image {
        visible: root.hornetHere && root.scene !== null
        source: root.scene ? root.sceneDir + "/" + root.scene.light.file : ""
        x: root.hornet ? root.toX((root.hornet.x + root.scene.light.left) * root.unitMm) : 0
        y: root.hornet ? root.toY((root.hornet.y + root.scene.light.bottom + root.scene.light.height) * root.unitMm) : 0
        width: root.scene ? root.scene.light.width * root.pxPerUnit : 0
        height: root.scene ? root.scene.light.height * root.pxPerUnit : 0
        smooth: true
    }

    Repeater {
        model: root.clips && root.scene ? World.clipsUsed(root.clips, root.scene) : []

        SpriteClip {
            required property string modelData

            sheet: root.clips[modelData]
            dataDir: root.sceneDir
            visible: root.hornetHere && root.hornet.clip === modelData
            frame: visible ? root.hornet.frame : 0
            mirrored: root.hornet?.facingRight ?? false
            pixelScale: root.pxPerUnit / sheet.pixelsPerUnit
            x: Math.round(root.toX((root.hornet?.x ?? 0) * root.unitMm))
            y: Math.round(root.toY((root.hornet?.y ?? 0) * root.unitMm))
        }
    }

    Layer {
        tiles: root.scene?.layers.front ?? []
    }

    // Alignment checks: a straight diagonal across all screens, a ruler along the
    // bottom in millimetres, and the ground Hornet walks on.
    Item {
        anchors.fill: parent
        visible: root.debug

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: "#e0b050"
                strokeWidth: Math.max(1, root.pxPerMm * 0.6)
                fillColor: "transparent"
                startX: root.toX(0)
                startY: root.toY(0)
                PathLine {
                    x: root.toX(root.layout.width)
                    y: root.toY(root.layout.height)
                }
            }
            ShapePath {
                strokeColor: "#ff40ff"
                strokeWidth: Math.max(1, root.pxPerMm * 0.5)
                fillColor: "transparent"
                PathPolyline {
                    path: root.scene ? root.scene.ground.map((y, i) => Qt.point(root.toX(i * root.scene.groundStep * root.unitMm), root.toY((y ?? 0) * root.unitMm))) : []
                }
            }
        }

        Repeater {
            model: Math.floor(root.layout.width / 50) + 1

            Rectangle {
                required property int index
                readonly property bool major: index % 2 === 0
                x: root.toX(index * 50) - width / 2
                y: root.height - height
                width: Math.max(1, root.pxPerMm * 0.5)
                height: root.pxPerMm * (major ? 8 : 4)
                color: "#c8d3e0"
            }
        }

        Text {
            x: root.pxPerMm * 8
            y: root.pxPerMm * 8
            color: "#c8d3e0"
            style: Text.Outline
            styleColor: "black"
            font.pixelSize: root.pxPerMm * 4
            text: `${root.screenName}  x=${root.me.x.toFixed(0)} mm  ${root.me.w.toFixed(0)}×${root.me.h.toFixed(0)} mm  `
                + `${root.pxPerMm.toFixed(2)} px/mm\nworld ${root.layout.width.toFixed(0)}×${root.layout.height.toFixed(0)} mm`
                + (root.scene ? `, scene ${root.sceneId} ${(root.scene.width * root.unitMm).toFixed(0)} mm` : `\nno scene in ${root.sceneDir}: run tools/bake.py`)
                + (root.clips ? "" : `\nno sprites in ${root.dataDir}: run tools/extract.py`)
        }
    }
}
