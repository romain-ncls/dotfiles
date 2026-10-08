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
    // The clock's gears turn smoothly enough at 10 updates a second, the Bell Beast's 12 fps
    // animations need 12.
    readonly property bool showsClock: clock !== null
        && clock.x * unitMm > me.x - 30 && clock.x * unitMm < me.x + me.w + 30
    Timer {
        interval: root.showsBeast ? 83 : root.showsClock ? 100 : 250
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
                // Neighbouring tiles share their edge exactly: an overlap would draw a translucent
                // column twice (a line through the lake), a gap would show the black behind.
                x: Math.round(root.toX(unitsX * root.unitMm))
                y: Math.floor(root.toY(root.world.height * root.unitMm))
                width: Math.round(root.toX((unitsX + unitsW) * root.unitMm)) - x
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

    // The clock's gears, turning with the time: behind the great tree's frame (under the mid
    // layer), or inside the dial, behind the hands.
    component ClockGears: Repeater {
        required property bool dial
        model: root.clock ? root.clock.gears.filter(g => !!g.dial === dial) : []

        Image {
            required property var modelData
            source: root.worldDir + "/" + modelData.file + root.build
            width: modelData.size * root.pxPerUnit
            height: width
            x: root.toX(modelData.x * root.unitMm) - width / 2
            y: root.toY(modelData.y * root.unitMm) - height / 2
            rotation: (root.time / 60 * modelData.turns % 1) * 360
            smooth: true
            mipmap: true
        }
    }

    ClockGears {
        dial: false
    }

    Layer {
        tiles: root.world?.layers.mid ?? []
    }

    // The clock in the great tree's window: two Cogwork pointers for hands, on local time.
    readonly property var clock: world?.clock ?? null
    readonly property var now: new Date(time * 1000)
    readonly property real minuteAngle: (now.getMinutes() + now.getSeconds() / 60) * 6
    readonly property real hourAngle: (now.getHours() % 12 + now.getMinutes() / 60) * 30

    component ClockHands: Repeater {
        model: root.clock ? root.clock.hands : []

        Item {
            required property var modelData
            // At the dial's centre; the needle image points left, a quarter turn points it at 12.
            x: root.toX(root.clock.x * root.unitMm)
            y: root.toY(root.clock.y * root.unitMm)
            rotation: 90 + (modelData.name === "hour" ? root.hourAngle : root.minuteAngle)

            Image {
                source: root.worldDir + "/" + parent.modelData.file + root.build
                width: parent.modelData.length * root.pxPerUnit
                height: parent.modelData.height * root.pxPerUnit
                x: -parent.modelData.pivot[0] * width
                y: -parent.modelData.pivot[1] * height
                smooth: true
                mipmap: true
            }
        }
    }

    ClockGears {
        dial: true
    }

    ClockHands {}

    // Hornet's sheets, only on the screen she's on or about to reach, only the clips she plays
    // in the next 40 seconds, loaded in the background; screens in one process share them.
    readonly property bool hornetNear: hornet !== null
        && hornet.x * unitMm > me.x - 150 && hornet.x * unitMm < me.x + me.w + 150
    readonly property int lookahead: Math.floor(time / 5)
    readonly property var clipsAhead: (hornetNear ? Life.clipsAhead(world, clips, lookahead * 5, 45) : [])
        .concat(showsBeast ? Life.beastClipsAhead(world, clips, lookahead * 5, 45) : [])
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

    // The Bell Beast in its station: behind Hornet, its lower body in the trench behind the
    // station's floor (the front layer). Coloured like a character of its zone.
    readonly property var beast: world?.beast ?? null
    readonly property bool showsBeast: beast !== null
        && (beast.x - 5) * unitMm < me.x + me.w && (beast.x + 5) * unitMm > me.x
    readonly property var beastPose: showsBeast && clips ? Life.beastAt(world, clips, time) : null
    readonly property var beastZone: beast ? world.zones.find(z => z.id === beast.zone) ?? null : null

    HornetSprite {
        readonly property string clip: root.beastPose?.clip ?? ""

        visible: root.beastPose !== null && root.sheets[clip] !== undefined && root.beastZone !== null
            && root.luts[root.beastZone.id] !== undefined
        sheet: root.clips && root.clips[clip] ? root.clips[clip]
            : { sequence: [0], frames: 1, columns: 1, cellWidth: 1, cellHeight: 1, anchorX: 0, anchorY: 0, pixelsPerUnit: 64 }
        texture: root.sheets[clip] ?? null
        grade: root.beastZone ? { ambient: root.beastZone.grade.ambient, heroSaturation: 1.0,
                                  saturation: root.beastZone.grade.saturation }
                              : { ambient: [0.5, 0.5, 0.5], heroSaturation: 1, saturation: 1 }
        lut: root.beastZone ? root.luts[root.beastZone.id] ?? null : null
        frame: root.beastPose?.frame ?? 0
        pixelScale: root.pxPerUnit / sheet.pixelsPerUnit
        x: root.beast ? Math.round(root.toX(root.beast.x * root.unitMm)) : 0
        y: root.beast ? Math.round(root.toY(root.beast.y * root.unitMm)) : 0
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

    // The water, moving (shaders/waterfall.frag, lake.frag): in front of Hornet, under the
    // time of day. Its own clock, wrapped every hour (the shaders work in single precision).
    readonly property var water: world?.water ?? null
    readonly property bool showsWater: water !== null
        && (water.lake.left - 1) * unitMm < me.x + me.w && (water.lake.left + water.lake.width + 1) * unitMm > me.x
    property real waterTime: time % 3600
    Timer {
        interval: 33
        repeat: true
        running: root.live && root.showsWater && GraphicsInfo.api !== GraphicsInfo.Software
        onTriggered: root.waterTime = (Date.now() / 1000) % 3600
    }

    component WaterEffect: ShaderEffect {
        required property var area // left, bottom, width, height in units
        readonly property real time: root.waterTime
        readonly property vector2d extent: Qt.vector2d(area.width, area.height)
        readonly property color shallow: Qt.rgba(root.water.shallow[0], root.water.shallow[1], root.water.shallow[2], 1)
        readonly property color light: Qt.rgba(root.water.light[0], root.water.light[1], root.water.light[2], 1)

        visible: root.showsWater && GraphicsInfo.api !== GraphicsInfo.Software
        x: root.toX(area.left * root.unitMm)
        y: root.toY((area.bottom + area.height) * root.unitMm)
        width: area.width * root.pxPerUnit
        height: area.height * root.pxPerUnit
    }

    WaterEffect {
        area: root.water ? root.water.fall : { left: 0, bottom: 0, width: 0, height: 0, edges: [0, 0, 0, 0] }
        readonly property vector4d edges: Qt.vector4d(area.edges[0], area.edges[1], area.edges[2], area.edges[3])
        fragmentShader: Qt.resolvedUrl("shaders/waterfall.frag.qsb")
    }

    Image {
        id: waterMask
        visible: false
        source: root.water ? root.worldDir + "/" + root.water.lake.mask + root.build : ""
        smooth: true
    }

    WaterEffect {
        area: root.water ? root.water.lake : { left: 0, bottom: 0, width: 0, height: 0, level: 0, impact: 0 }
        readonly property real level: area.level
        readonly property real impact: area.impact
        readonly property Image mask: waterMask
        fragmentShader: Qt.resolvedUrl("shaders/lake.frag.qsb")
    }

    WaterEffect {
        area: root.water ? root.water.splash : { left: 0, bottom: 0, width: 0, height: 0, level: 0, impact: 0, fallWidth: 0, maskRect: [0, 0, 1, 1] }
        readonly property real level: area.level
        readonly property real impact: area.impact
        readonly property real fallWidth: area.fallWidth
        readonly property vector4d maskRect: Qt.vector4d(area.maskRect[0], area.maskRect[1], area.maskRect[2], area.maskRect[3])
        readonly property Image mask: waterMask
        fragmentShader: Qt.resolvedUrl("shaders/splash.frag.qsb")
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

    // After dark the hands keep a little of their shine, so the time stays readable.
    Item {
        anchors.fill: parent
        opacity: root.daylight.lights * 0.45
        visible: opacity > 0.01

        ClockHands {}
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
