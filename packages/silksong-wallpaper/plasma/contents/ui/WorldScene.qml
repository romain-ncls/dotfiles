/*
 * What one screen sees of the aquarium (tools/world.py). Plain QtQuick, so
 * tools/preview.qml can lay several of these side by side without Plasma.
 */
import QtQuick
import Qt.labs.folderlistmodel

import "world.js" as World
import "daylight.js" as Daylight
import "life.js" as Life

Item {
    id: root

    required property var screens // Qt.application.screens, or stand-ins with the same fields
    required property string screenName
    required property url dataDir
    property real gapMm: 15
    property real latitude: 48.85
    property real longitude: 2.35
    property bool debug: false

    // Seconds since the epoch. Driven by the wall clock unless live is off.
    property bool live: true
    property real time: Date.now() / 1000

    readonly property url worldDir: dataDir + "/world"
    readonly property var world: worldData.item?.world ?? null
    readonly property var clips: sprites.item?.clips ?? null
    readonly property string build: world ? "?v=" + world.build : ""
    readonly property real unitMm: world ? world.unitMm : 10

    readonly property var layout: World.layout(screens, gapMm)
    readonly property var me: layout.screens[screenName] ?? { x: 0, y: 0, w: width / 4, h: height / 4 }
    readonly property real pxPerMm: width / me.w
    readonly property real pxPerUnit: pxPerMm * unitMm

    readonly property var hornet: clips && world ? Life.hornetAt(world, clips, time) : null
    readonly property var hornetZone: hornet ? World.zoneAt(world, hornet.x, hornet.y) : null
    readonly property bool hornetHere: hornet !== null
        && hornet.x * unitMm > me.x - 120 && hornet.x * unitMm < me.x + me.w + 120
    readonly property var daylight: Daylight.lightingAt(new Date(time * 1000), latitude, longitude)

    function toX(xMm) {
        return (xMm - me.x) * pxPerMm;
    }
    function toY(yMm) {
        return height - (yMm - me.y) * pxPerMm;
    }

    // Full frame rate only while Hornet is on this screen; elsewhere the clock
    // only needs to notice her coming and move the daylight along.
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

    // The world and Hornet's clips, reloaded whenever tools/world.py or extract.py write new
    // ones: each version gets its own URL, as the QML engine keeps what it loaded by URL for as
    // long as the process lives (plasmashell runs for days).
    component Watch: FolderListModel {
        required property string file
        property real stamp: 0
        property real seen: -1 // the version loaded at startup

        function update() {
            const t = count > 0 ? get(0, "fileModified").getTime() : 0;
            if (seen < 0 && t > 0) {
                seen = t;
            } else if (t > 0 && t !== seen) {
                stamp = t;
            }
        }

        nameFilters: [file]
        showDirs: false
        onCountChanged: update()
        onStatusChanged: update()
        onDataChanged: update()
        onRowsInserted: update()
        onModelReset: update()
    }
    Watch {
        id: worldWatch
        folder: root.worldDir
        file: "World.qml"
    }
    Watch {
        id: spritesWatch
        folder: root.dataDir
        file: "Sprites.qml"
    }
    Loader {
        id: sprites
        source: root.dataDir + "/Sprites.qml?v=" + spritesWatch.stamp
    }
    Loader {
        id: worldData
        source: root.worldDir + "/World.qml?v=" + worldWatch.stamp
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
                readonly property real unitsX: modelData.x / root.world.pixelsPerUnit
                readonly property real unitsW: modelData.width / root.world.pixelsPerUnit
                readonly property bool shown: (unitsX + unitsW) * root.unitMm > root.me.x && unitsX * root.unitMm < root.me.x + root.me.w

                visible: shown
                source: shown ? root.worldDir + "/" + modelData.file + root.build : ""
                x: Math.floor(root.toX(unitsX * root.unitMm))
                y: Math.floor(root.toY(root.world.height * root.unitMm))
                width: Math.ceil(unitsW * root.pxPerUnit) + 1
                height: Math.ceil(root.world.height * root.pxPerUnit)
                sourceSize.width: width
                asynchronous: true
                cache: false
                smooth: true
            }
        }
    }

    // The light Hornet carries, in the colours of the zone she's in. It lights the
    // backdrop behind her, never the rock: at night it grows stronger under the veil.
    component HeroLight: Image {
        readonly property var info: root.hornetZone?.light ?? null
        visible: root.hornetHere && info !== null
        opacity: info ? Math.min(1, info.strength * (1 + root.daylight.lights * 0.6)) : 0
        source: info ? root.worldDir + "/" + info.file + root.build : ""
        x: info ? root.toX((root.hornet.x + info.left) * root.unitMm) : 0
        y: info ? root.toY((root.hornet.y + info.bottom + info.height) * root.unitMm) : 0
        width: info ? info.width * root.pxPerUnit : 0
        height: info ? info.height * root.pxPerUnit : 0
        smooth: true
    }

    Layer {
        tiles: root.world?.layers.back ?? []
    }

    HeroLight {}

    Layer {
        tiles: root.world?.layers.mid ?? []
    }

    // Hornet's sheets, only on the screen she's on or about to reach, only the clips she plays
    // in the next 40 seconds, loaded in the background; screens in one process share them.
    readonly property bool hornetNear: hornet !== null
        && hornet.x * unitMm > me.x - 150 && hornet.x * unitMm < me.x + me.w + 150
    readonly property int lookahead: Math.floor(time / 5)
    readonly property var clipsAhead: hornetNear ? Life.clipsAhead(world, clips, lookahead * 5, 45) : []
    readonly property real sheetScale: Math.min(1, pxPerUnit / 64)
    property var sheets: ({})
    property var luts: ({})

    Item {
        visible: false

        Repeater {
            model: root.clipsAhead

            Image {
                required property string modelData
                readonly property var sheet: root.clips[modelData]

                source: root.worldDir + "/" + sheet.file + root.build
                sourceSize.width: Math.ceil(sheet.columns * sheet.cellWidth * root.sheetScale)
                asynchronous: true
                smooth: true
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.sheets = Object.assign({}, root.sheets, { [modelData]: this });
                    }
                }
                Component.onDestruction: {
                    if (root.sheets[modelData] === this) {
                        const left = Object.assign({}, root.sheets);
                        delete left[modelData];
                        root.sheets = left;
                    }
                }
            }
        }
        Repeater {
            model: root.world?.zones ?? []

            Image {
                required property var modelData

                source: root.worldDir + "/" + modelData.grade.lut + root.build
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.luts = Object.assign({}, root.luts, { [modelData.id]: this });
                    }
                }
            }
        }
    }

    // Her silk thread, when she has thrown her needle: from her hand to the needle or ring.
    Rectangle {
        readonly property var th: root.hornetHere ? root.hornet.thread : null
        readonly property real dx: th ? (th[2] - th[0]) * root.pxPerUnit : 0
        readonly property real dy: th ? (th[3] - th[1]) * root.pxPerUnit : 0

        visible: th !== null
        x: th ? root.toX(th[0] * root.unitMm) : 0
        y: th ? root.toY(th[1] * root.unitMm) - height / 2 : 0
        width: Math.hypot(dx, dy)
        height: Math.max(1.5, root.pxPerUnit * 0.05)
        radius: height / 2
        color: "#f2efe6"
        opacity: 0.9
        transformOrigin: Item.Left
        rotation: -Math.atan2(dy, dx) * 180 / Math.PI
    }

    // Her needle, flying to a ring or holding on to it.
    HornetSprite {
        readonly property var nd: root.hornetHere ? root.hornet.needle : null

        visible: nd !== null && texture !== null && lut !== null
        sheet: root.clips && root.clips["Harpoon Needle"] ? root.clips["Harpoon Needle"]
            : { sequence: [0], frames: 1, columns: 1, cellWidth: 1, cellHeight: 1, anchorX: 0, anchorY: 0, pixelsPerUnit: 64 }
        texture: root.sheets["Harpoon Needle"] ?? null
        grade: root.hornetZone?.grade ?? { ambient: [0.5, 0.5, 0.5], heroSaturation: 1, saturation: 1 }
        lut: root.hornetZone ? root.luts[root.hornetZone.id] ?? null : null
        frame: sheet.frames - 1
        mirrored: true // drawn pointing left
        pixelScale: root.pxPerUnit / sheet.pixelsPerUnit
        x: nd ? Math.round(root.toX(nd.x * root.unitMm)) : 0
        y: nd ? Math.round(root.toY(nd.y * root.unitMm)) : 0
        transformOrigin: Item.TopLeft
        rotation: nd ? -nd.angle : 0
    }

    HornetSprite {
        readonly property string clip: root.hornet?.clip ?? ""
        readonly property real tilt: root.hornet?.angle ?? 0

        visible: root.hornetHere && root.hornetZone !== null && root.sheets[clip] !== undefined
            && root.luts[root.hornetZone.id] !== undefined
        sheet: root.clips && root.clips[clip] ? root.clips[clip]
            : { sequence: [0], frames: 1, columns: 1, cellWidth: 1, cellHeight: 1, anchorX: 0, anchorY: 0, pixelsPerUnit: 64 }
        texture: root.sheets[clip] ?? null
        grade: root.hornetZone?.grade ?? { ambient: [0.5, 0.5, 0.5], heroSaturation: 1, saturation: 1 }
        lut: root.hornetZone ? root.luts[root.hornetZone.id] ?? null : null
        frame: root.hornet?.frame ?? 0
        mirrored: root.hornet?.facingRight ?? false
        pixelScale: root.pxPerUnit / sheet.pixelsPerUnit * (root.hornet?.scale ?? 1)
        x: Math.round(root.toX((root.hornet?.x ?? 0) * root.unitMm))
        y: Math.round(root.toY((root.hornet?.y ?? 0) * root.unitMm))
        transformOrigin: Item.TopLeft
        // Along her Clawline dash she leans into it: nose up, whichever way she faces.
        rotation: mirrored ? -tilt : tilt
    }

    Layer {
        tiles: root.world?.layers.front ?? []
    }

    // Time of day: a veil over everything, then the light sources shining through it.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.daylight.color[0], root.daylight.color[1], root.daylight.color[2], 1)
        opacity: root.daylight.opacity
    }

    Layer {
        tiles: root.daylight.lights > 0.01 ? root.world?.layers.lights ?? [] : [] // loaded only after dusk
        opacity: root.daylight.lights
    }

    Text {
        visible: root.debug
        x: root.pxPerMm * 8
        y: root.pxPerMm * 8
        color: "#c8d3e0"
        style: Text.Outline
        styleColor: "black"
        font.pixelSize: root.pxPerMm * 4
        text: `${root.screenName}  ${root.me.w.toFixed(0)}×${root.me.h.toFixed(0)} mm at x=${root.me.x.toFixed(0)}\n`
            + (root.world ? `world ${root.world.width}×${root.world.height} units, ${root.world.zones.length} zones` : `no world in ${root.worldDir}: run tools/world.py`)
            + `\nsun ${root.daylight.sun.sunrise.toFixed(2)}–${root.daylight.sun.sunset.toFixed(2)}, veil ${root.daylight.opacity.toFixed(2)}`
            + (root.hornetZone ? `\nHornet in ${root.hornetZone.id}` : "")
    }
}
