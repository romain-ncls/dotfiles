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

    // One clock per screen, so each change is drawn once: at full frame rate while Hornet is on
    // this screen; otherwise as often as what it shows needs, the water 30 times a second, swaying
    // plants and particles 15 (the game snaps its grass to 12 or 15 frames a second), the Bell
    // Beast's 12 fps animations 12, the clock's gears 10, else 4 (to notice her coming and move the
    // daylight along).
    readonly property bool showsClock: clock !== null
        && clock.x * unitMm > me.x - 30 && clock.x * unitMm < me.x + me.w + 30
    readonly property bool showsAmbient: (swayHere.length > 0 || showsParticles) && GraphicsInfo.api !== GraphicsInfo.Software
    function tick() {
        const now = Date.now() / 1000;
        time = now;
        ambientTime = now % 3600; // the shaders work in single precision
    }
    FrameAnimation {
        running: root.live && root.hornetHere
        onTriggered: root.tick()
    }
    Timer {
        interval: root.showsWater ? 33 : root.showsAmbient ? 66 : root.showsBeast ? 83 : root.showsClock ? 100 : 250
        repeat: true
        running: root.live && !root.hornetHere
        onTriggered: root.tick()
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

    // What moves on its own: the water, the swaying plants, the rooms' particles, on the screen's
    // clock (tick), wrapped every hour.
    readonly property var sway: world?.sway ?? null
    readonly property var swayHere: sway ? sway.items.filter(it => (it.x + it.w) * unitMm > me.x && it.x * unitMm < me.x + me.w) : []
    readonly property bool showsParticles: (world?.particles ?? []).some(p => (p.area[0] + p.area[2]) * unitMm > me.x
        && p.area[0] * unitMm < me.x + me.w)
    property real ambientTime: time % 3600

    // An AnimationCurve's value at t: keys [time, value, in slope, out slope], Hermite between them.
    function curveAt(keys, t) {
        if (t <= keys[0][0])
            return keys[0][1];
        for (let i = 1; i < keys.length; i++) {
            const [t0, v0, , out0] = keys[i - 1];
            const [t1, v1, in1] = keys[i];
            if (t <= t1) {
                const d = t1 - t0, u = (t - t0) / d, u2 = u * u, u3 = u2 * u;
                return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * d * out0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * d * in1;
            }
        }
        return keys[keys.length - 1][1];
    }

    Image {
        id: swayAtlas
        visible: false
        source: root.sway ? root.worldDir + "/" + root.sway.atlas + root.build : ""
        smooth: true
    }

    // Plants and hanging vines on the game's grass shaders, swaying as it sways them
    // (shaders/sway.vert), over the layer they belong to; still, without a GPU.
    component SwaySprites: Repeater {
        id: sprites
        required property string group // the layer it belongs to
        model: root.swayHere.filter(it => it.layer === sprites.group)

        Item {
            id: piece
            required property var modelData
            readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
            x: root.toX(modelData.x * root.unitMm)
            y: root.toY((modelData.y + modelData.h) * root.unitMm)
            width: modelData.w * root.pxPerUnit
            height: modelData.h * root.pxPerUnit

            // Hornet walking into grass bends it her way, along the game's curve (GrassBehaviour).
            readonly property var react: modelData.react ?? null
            readonly property real rootAt: modelData.y + modelData.h * (1 - modelData.root)
            readonly property real feet: root.hornetHere ? root.hornet.y - root.world.heroFeet : -1e6
            readonly property bool touched: react !== null && root.hornetHere
                && Math.abs(root.hornet.x - modelData.x - modelData.w / 2) < modelData.w / 2
                && feet > rootAt - 0.3 && feet < rootAt + modelData.h * 0.7
            property real touchedAt: -1e9
            property real way: 1
            onTouchedChanged: {
                if (touched) {
                    touchedAt = root.time;
                    way = root.hornet.facingRight ? 1 : -1;
                }
            }
            readonly property real push: react && root.time - touchedAt < react.length
                ? react.amount * way * root.curveAt(react.keys, (root.time - touchedAt) / react.length) : 0

            ShaderEffect {
                readonly property real time: root.ambientTime
                readonly property real push: piece.push
                readonly property real amount: piece.modelData.amount
                readonly property real speed: piece.modelData.speed
                readonly property real phase: piece.modelData.phase
                readonly property real fps: piece.modelData.fps
                readonly property real rootY: piece.modelData.root * height
                readonly property vector4d mags: Qt.vector4d(piece.modelData.mags[0], piece.modelData.mags[1], piece.modelData.mags[2], 0)
                readonly property vector4d times: Qt.vector4d(piece.modelData.times[0], piece.modelData.times[1], piece.modelData.times[2], 0)
                readonly property vector4d uv: Qt.vector4d(piece.modelData.uv[0], piece.modelData.uv[1], piece.modelData.uv[2], piece.modelData.uv[3])
                readonly property Image source: swayAtlas

                anchors.fill: parent
                visible: !piece.software
                vertexShader: Qt.resolvedUrl("shaders/sway.vert.qsb")
                fragmentShader: Qt.resolvedUrl("shaders/sway.frag.qsb")
            }

            Image {
                anchors.fill: parent
                visible: piece.software
                source: piece.software ? swayAtlas.source : ""
                sourceClipRect: Qt.rect(piece.modelData.uv[0] * root.sway.size[0], piece.modelData.uv[1] * root.sway.size[1],
                    (piece.modelData.uv[2] - piece.modelData.uv[0]) * root.sway.size[0],
                    (piece.modelData.uv[3] - piece.modelData.uv[1]) * root.sway.size[1])
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

    // The rooms' own ambient particles (Verdania's fireflies), behind the rock: one item per
    // emitter, its particles' quads on a grid that shaders/particle.vert moves along their lives.
    Repeater {
        model: root.world?.particles?.filter(p => (p.area[0] + p.area[2]) * root.unitMm > root.me.x
            && p.area[0] * root.unitMm < root.me.x + root.me.w) ?? []

        ShaderEffect {
            id: emitter
            required property var modelData
            readonly property var p: modelData
            readonly property real time: root.ambientTime
            readonly property real slots: p.slots
            readonly property real pxPerUnit: root.pxPerUnit
            readonly property vector4d area: Qt.vector4d(p.area[0], p.area[1], p.area[2], p.area[3])
            readonly property vector4d centre: Qt.vector4d(p.x, p.y, p.shape === "box" ? 1 : 0, p.thickness)
            readonly property vector4d axes: Qt.vector4d(p.axes[0], p.axes[1], p.axes[2], p.axes[3])
            readonly property vector4d lifeSize: Qt.vector4d(p.life[0], p.life[1], p.size[0], p.size[1])
            readonly property vector4d velocity: Qt.vector4d(p.velocity[0], p.velocity[1], p.velocity[2], p.velocity[3])
            readonly property vector4d spin: Qt.vector4d(p.spin[0], p.spin[1], p.rotation[0], p.rotation[1])
            readonly property vector4d misc: Qt.vector4d(p.alpha, p.gravity, p.additive ? 1 : 0, 0)
            readonly property vector4d sheet: Qt.vector4d(p.sheet[0], p.sheet[1], p.sheet[2], 0)
            readonly property vector4d keyT0: Qt.vector4d(p.keys[0][0], p.keys[1][0], p.keys[2][0], p.keys[3][0])
            readonly property vector4d keyT1: Qt.vector4d(p.keys[4][0], p.keys[5][0], p.keys[6][0], p.keys[7][0])
            readonly property vector4d keyA0: Qt.vector4d(p.keys[0][1], p.keys[1][1], p.keys[2][1], p.keys[3][1])
            readonly property vector4d keyA1: Qt.vector4d(p.keys[4][1], p.keys[5][1], p.keys[6][1], p.keys[7][1])
            readonly property Image source: texture

            visible: GraphicsInfo.api !== GraphicsInfo.Software
            x: root.toX(p.area[0] * root.unitMm)
            y: root.toY((p.area[1] + p.area[3]) * root.unitMm)
            width: p.area[2] * root.pxPerUnit
            height: p.area[3] * root.pxPerUnit
            mesh: GridMesh {
                resolution: Qt.size(2 * emitter.p.slots - 1, 1)
            }
            vertexShader: Qt.resolvedUrl("shaders/particle.vert.qsb")
            fragmentShader: Qt.resolvedUrl("shaders/particle.frag.qsb")

            Image {
                id: texture
                visible: false
                source: root.worldDir + "/" + emitter.p.texture + root.build
                smooth: true
            }
        }
    }

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

    SwaySprites {
        group: "mid"
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

    // The station's floor bells, drawn apart from the layer in front of them: they jingle (their
    // shake frames, as the game's BasicSpriteAnimator plays them) while Hornet walks among them,
    // and around the Bell Beast while it sings, shakes, gets up or lies down.
    readonly property var stirring: beastPose && /Sing|Shake|Wake/.test(beastPose.clip) ? beast.x : null
    Repeater {
        model: root.world?.animated?.filter(a => (a.x + a.w) * root.unitMm > root.me.x && a.x * root.unitMm < root.me.x + root.me.w) ?? []

        Item {
            id: piece
            required property var modelData
            readonly property var a: modelData
            readonly property real feet: root.hornetHere ? root.hornet.y - root.world.heroFeet : -1e6
            readonly property bool stirred: (root.hornetHere && root.hornet.x > a.x && root.hornet.x < a.x + a.w
                    && feet > a.y - 1.0 && feet < a.y + a.h + 0.4)
                || (root.stirring !== null && Math.abs(a.x + a.w / 2 - root.stirring) < 4.5)
            readonly property int frame: stirred ? 1 + Math.floor(root.time * a.fps) % a.frames : 0
            readonly property real scale: root.pxPerUnit / root.world.pixelsPerUnit

            x: root.toX(a.x * root.unitMm)
            y: root.toY((a.y + a.h) * root.unitMm)
            width: a.w * root.pxPerUnit
            height: a.h * root.pxPerUnit
            clip: true

            Image {
                source: root.worldDir + "/" + piece.a.sheet + root.build
                x: -(piece.a.cell[0] + piece.frame * piece.a.step) * piece.scale
                y: -piece.a.cell[1] * piece.scale
                width: sourceSize.width * piece.scale
                height: sourceSize.height * piece.scale
                smooth: true
            }
        }
    }

    Layer {
        tiles: root.world?.layers.front ?? []
    }

    SwaySprites {
        group: "front"
    }

    // The water, moving (shaders/waterfall.frag, lake.frag): in front of Hornet, under the
    // time of day. Its own clock, wrapped every hour (the shaders work in single precision).
    readonly property var water: world?.water ?? null
    readonly property bool showsWater: water !== null
        && (water.lake.left - 1) * unitMm < me.x + me.w && (water.lake.left + water.lake.width + 1) * unitMm > me.x
    component WaterEffect: ShaderEffect {
        required property var area // left, bottom, width, height in units
        readonly property real time: root.ambientTime
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
